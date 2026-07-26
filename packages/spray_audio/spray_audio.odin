package spray_audio

import "core:c"
import "core:math"
import sdl "vendor:sdl3"

SAMPLE_RATE :: 48_000
CHANNELS :: 2
CALLBACK_SAMPLES :: 4096

Synth :: struct {
    random_state:      u32,
    level:             f32,
    target_level:      f32,
    mute_gain:         f32,
    target_mute_gain:  f32,
    intensity:         f32,
    target_intensity:  f32,
    pan:               f32,
    target_pan:        f32,
    can_pressure:      f32,
    pressure_low:      f32,
    hiss_low_left:     f32,
    hiss_low_right:    f32,
    body_low_left:     f32,
    body_low_right:    f32,
    flutter_phase:     f32,
    flutter_noise_low: f32,
    valve_phase:       f32,
    onset_age:         f32,
    release_age:       f32,
    onset_level:       f32,
    release_level:     f32,
    sputter_timer:     f32,
    sputter_age:       f32,
    sputter_duration:  f32,
    sputter_depth:     f32,
    sputter_count:     u32,
    active:            bool,
}

Runtime :: struct {
    synth:             Synth,
    stream:            ^sdl.AudioStream,
    owns_audio_system: bool,
}

new_synth :: proc(seed: u32 = 0x53505259) -> Synth {
    return {
        random_state = seed == 0 ? 0x53505259 : seed,
        intensity = .7,
        target_intensity = .7,
        can_pressure = 1,
        mute_gain = 1,
        target_mute_gain = 1,
    }
}

set_active :: proc "contextless" (synth: ^Synth, active: bool, intensity: f32 = .7, pan: f32 = 0) {
    if synth == nil do return
    if active && !synth.active {
        synth.onset_level = 1
        synth.onset_age = 0
        synth.release_level = 0
        synth.valve_phase = 0
    } else if !active && synth.active {
        synth.release_level = max(synth.level, f32(.25))
        synth.release_age = 0
        synth.onset_level = 0
    }
    synth.active = active
    synth.target_level = active ? 1 : 0
    synth.target_intensity = clamp(intensity, 0, 1)
    synth.target_pan = clamp(pan, -1, 1)
}

set_muted :: proc "contextless" (synth: ^Synth, muted: bool) {
    if synth != nil do synth.target_mute_gain = muted ? 0 : 1
}

next_noise :: proc "contextless" (synth: ^Synth) -> f32 {
    x := synth.random_state
    x = x ~ (x << 13)
    x = x ~ (x >> 17)
    x = x ~ (x << 5)
    synth.random_state = x
    return f32(x & 0x00ffffff) / f32(0x007fffff) - 1
}

soft_clip :: proc "contextless" (value: f32) -> f32 {
    return value / (1 + abs(value))
}

coefficient_for_sample_rate :: proc "contextless" (reference_coefficient, sample_rate: f32) -> f32 {
    if sample_rate <= 0 do return 0
    coefficient := clamp(reference_coefficient, 0, 1)
    return f32(1 - math.pow(f64(1 - coefficient), f64(SAMPLE_RATE) / f64(sample_rate)))
}

render :: proc "contextless" (synth: ^Synth, output: []f32, sample_rate: f32 = SAMPLE_RATE) {
    frame_count := len(output) / CHANNELS
    if synth == nil || frame_count <= 0 || sample_rate <= 0 do return

    // Fast attack makes the can feel responsive; the slower release prevents
    // zipper noise and clicks when a stroke ends between audio callbacks.
    attack := f32(1 - math.exp(f64(-125 / sample_rate)))
    release := f32(1 - math.exp(f64(-28 / sample_rate)))
    control_smoothing := f32(1 - math.exp(f64(-18 / sample_rate)))
    pan_smoothing := f32(1 - math.exp(f64(-9 / sample_rate)))
    mute_smoothing := f32(1 - math.exp(f64(-18 / sample_rate)))
    pressure_cutoff := f32(1 - math.exp(f64(-2 * math.PI * 135 / sample_rate)))
    flutter_cutoff := f32(1 - math.exp(f64(-2 * math.PI * 23 / sample_rate)))
    flutter_step := f32(2 * math.PI * 17 / sample_rate)
    onset_decay := f32(math.exp(f64(-47 / sample_rate)))
    release_decay := f32(math.exp(f64(-23 / sample_rate)))
    pressure_sag := f32(1 - math.exp(f64(-.18 / sample_rate)))
    pressure_recovery := f32(1 - math.exp(f64(-.55 / sample_rate)))
    body_low_intensity := coefficient_for_sample_rate(.11, sample_rate)
    body_high_intensity := coefficient_for_sample_rate(.18, sample_rate)
    hiss_low_intensity := coefficient_for_sample_rate(.56, sample_rate)
    hiss_high_intensity := coefficient_for_sample_rate(.36, sample_rate)

    for frame in 0 ..< frame_count {
        envelope_rate := synth.target_level > synth.level ? attack : release
        synth.level += (synth.target_level - synth.level) * envelope_rate
        synth.intensity += (synth.target_intensity - synth.intensity) * control_smoothing
        synth.pan += (synth.target_pan - synth.pan) * pan_smoothing
        synth.mute_gain += (synth.target_mute_gain - synth.mute_gain) * mute_smoothing
        pressure_target := synth.active ? .82 - synth.intensity * .14 : f32(1)
        pressure_smoothing := synth.active ? pressure_sag : pressure_recovery
        synth.can_pressure += (pressure_target - synth.can_pressure) * pressure_smoothing

        shared := next_noise(synth)
        side := next_noise(synth)
        left_noise := shared * .82 + side * .18
        right_noise := shared * .82 - side * .18
        synth.flutter_noise_low += (shared - synth.flutter_noise_low) * flutter_cutoff
        // Greater can pressure moves the atomizer body upward and opens more
        // of the bright aerosol band.
        effective_pressure := .58 + synth.can_pressure * .42
        effective_intensity := synth.intensity * effective_pressure
        body_cutoff := body_low_intensity + (body_high_intensity - body_low_intensity) * effective_intensity
        hiss_cutoff := hiss_low_intensity + (hiss_high_intensity - hiss_low_intensity) * effective_intensity
        synth.pressure_low += (shared - synth.pressure_low) * pressure_cutoff
        synth.body_low_left += (left_noise - synth.body_low_left) * body_cutoff
        synth.body_low_right += (right_noise - synth.body_low_right) * body_cutoff
        synth.hiss_low_left += (left_noise - synth.hiss_low_left) * hiss_cutoff
        synth.hiss_low_right += (right_noise - synth.hiss_low_right) * hiss_cutoff

        synth.flutter_phase += flutter_step
        if synth.flutter_phase >= 2 * math.PI do synth.flutter_phase -= 2 * math.PI
        valve_step := f32(2 * math.PI * (880 + synth.intensity * 240) / sample_rate)
        synth.valve_phase += valve_step
        if synth.valve_phase >= 2 * math.PI do synth.valve_phase -= 2 * math.PI
        pressure_flutter := 1 + (1 - synth.can_pressure) * 2.4
        random_flutter := clamp(synth.flutter_noise_low * 1.8 * pressure_flutter, -.14, .14)
        flutter := .92 + .035 * f32(math.sin(f64(synth.flutter_phase))) + random_flutter

        // As propellant pressure falls, the nozzle intermittently loses its
        // atomized stream. Seeded event spacing prevents a loop-like cadence;
        // a half-sine envelope makes each micro-dropout enter and leave
        // continuously while coarse droplets replace some missing hiss.
        depletion := clamp((.88 - synth.can_pressure) / .20, 0, 1)
        if synth.active && depletion > .04 && synth.sputter_duration <= 0 {
            synth.sputter_timer -= 1 / sample_rate
            if synth.sputter_timer <= 0 {
                duration_variation := (next_noise(synth) + 1) * .5
                depth_variation := (next_noise(synth) + 1) * .5
                interval_variation := (next_noise(synth) + 1) * .5
                synth.sputter_age = 0
                synth.sputter_duration = .025 + duration_variation * .055
                synth.sputter_depth = (.18 + depth_variation * .30) * depletion
                synth.sputter_timer = (.16 + interval_variation * .48) / (.35 + depletion * .65)
                synth.sputter_count += 1
            }
        }
        sputter_envelope := f32(0)
        if synth.sputter_duration > 0 {
            sputter_progress := clamp(synth.sputter_age / synth.sputter_duration, 0, 1)
            sputter_envelope = f32(math.sin(f64(sputter_progress * math.PI))) * synth.sputter_depth
            synth.sputter_age += 1 / sample_rate
            if synth.sputter_age >= synth.sputter_duration do synth.sputter_duration = 0
        }

        // Mid-band atomizer body plus bright aerosol hiss and a quiet shared
        // pressure component gives the result the scale of a handheld can.
        body_left := synth.body_low_left - synth.pressure_low
        body_right := synth.body_low_right - synth.pressure_low
        hiss_left := left_noise - synth.hiss_low_left
        hiss_right := right_noise - synth.hiss_low_right
        pressure := synth.pressure_low * .11
        brightness := (.18 + synth.intensity * .16) * (.72 + synth.can_pressure * .28)
        gain := synth.level * (.24 + synth.intensity * .12) * flutter * effective_pressure * (1 - sputter_envelope)
        left := (body_left * .62 + hiss_left * brightness + pressure) * gain
        right := (body_right * .62 + hiss_right * brightness + pressure) * gain
        droplet_spit := (shared - synth.body_low_left) * sputter_envelope * (.045 + synth.intensity * .025)
        left += droplet_spit
        right += droplet_spit * .82

        // Pressing the cap produces a brief valve tick and pressure surge.
        // Releasing it leaves a short, irregular atomizer spit rather than
        // reducing the sustained noise envelope alone.
        valve_tick := f32(math.sin(f64(synth.valve_phase))) * synth.onset_level * .055
        pressure_burst := (shared - synth.pressure_low) * synth.onset_level * (.07 + synth.intensity * .035)
        sputter_gate := .48 + .52 * max(f32(math.sin(f64(synth.release_age * 2 * math.PI * 31))), f32(-.45))
        release_spit :=
            (shared - synth.hiss_low_left) * synth.release_level * sputter_gate * (.09 + synth.intensity * .035)
        left += valve_tick + pressure_burst + release_spit
        right += valve_tick + pressure_burst + release_spit * .86
        // Track the paint cursor while retaining the atomizer's intrinsic
        // stereo width. Smoothing prevents abrupt image jumps between frames.
        left_gain := 1 - synth.pan * .34
        right_gain := 1 + synth.pan * .34
        output[frame * 2] = soft_clip(left * left_gain * 1.7) * synth.mute_gain
        output[frame * 2 + 1] = soft_clip(right * right_gain * 1.7) * synth.mute_gain

        synth.onset_level *= onset_decay
        synth.release_level *= release_decay
        if synth.onset_level < .00001 {
            synth.onset_level = 0
        } else {
            synth.onset_age = min(synth.onset_age + 1 / sample_rate, f32(1))
        }
        if synth.release_level < .00001 {
            synth.release_level = 0
        } else {
            synth.release_age = min(synth.release_age + 1 / sample_rate, f32(1))
        }
    }
}

audio_callback :: proc "c" (userdata: rawptr, stream: ^sdl.AudioStream, additional_amount, total_amount: c.int) {
    runtime := cast(^Runtime)userdata
    remaining := int(additional_amount) / size_of(f32)
    samples: [CALLBACK_SAMPLES]f32
    for remaining > 0 {
        count := min(remaining, CALLBACK_SAMPLES)
        count -= count % CHANNELS
        if count == 0 do break
        render(&runtime.synth, samples[:count])
        if !sdl.PutAudioStreamData(stream, raw_data(samples[:count]), c.int(count * size_of(f32))) {
            break
        }
        remaining -= count
    }
}

init :: proc(runtime: ^Runtime) -> bool {
    if runtime == nil do return false
    runtime.synth = new_synth()
    if sdl.WasInit(sdl.INIT_AUDIO) == {} {
        if !sdl.InitSubSystem(sdl.INIT_AUDIO) do return false
        runtime.owns_audio_system = true
    }
    spec := sdl.AudioSpec {
        format   = .F32,
        channels = CHANNELS,
        freq     = SAMPLE_RATE,
    }
    runtime.stream = sdl.OpenAudioDeviceStream(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, audio_callback, runtime)
    if runtime.stream == nil {
        if runtime.owns_audio_system do sdl.QuitSubSystem(sdl.INIT_AUDIO)
        runtime.owns_audio_system = false
        return false
    }
    if !sdl.ResumeAudioStreamDevice(runtime.stream) {
        sdl.DestroyAudioStream(runtime.stream)
        runtime.stream = nil
        if runtime.owns_audio_system do sdl.QuitSubSystem(sdl.INIT_AUDIO)
        runtime.owns_audio_system = false
        return false
    }
    return true
}

update :: proc(runtime: ^Runtime, active: bool, intensity: f32 = .7, pan: f32 = 0, muted: bool = false) {
    if runtime == nil || runtime.stream == nil do return
    if sdl.LockAudioStream(runtime.stream) {
        set_active(&runtime.synth, active, intensity, pan)
        set_muted(&runtime.synth, muted)
        sdl.UnlockAudioStream(runtime.stream)
    }
}

destroy :: proc(runtime: ^Runtime) {
    if runtime == nil do return
    if runtime.stream != nil do sdl.DestroyAudioStream(runtime.stream)
    if runtime.owns_audio_system do sdl.QuitSubSystem(sdl.INIT_AUDIO)
    runtime^ = {}
}
