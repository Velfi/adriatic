package ocean_audio

import "core:c"
import "core:math"
import sdl "vendor:sdl3"

SAMPLE_RATE :: 48_000
CHANNELS :: 2
CALLBACK_SAMPLES :: 4096

Settings :: struct {
    volume: f32,
    surf:   f32,
    foam:   f32,
    depth:  f32,
}

Synth :: struct {
    settings:             Settings,
    random_state:         u32,
    swell_phase:          f32,
    secondary_phase:      f32,
    foam_phase:           f32,
    shore_phase:          f32,
    wave_strength:        f32,
    target_wave_strength: f32,
    wave_variation:       f32,
    wave_set_phase:       f32,
    wave_set_strength:    f32,
    swell_rate:           f32,
    target_swell_rate:    f32,
    wave_count:           u32,
    previous_breaker:     f32,
    breaker_peak:         f32,
    crest_age:            f32,
    crest_duration:       f32,
    crest_strength:       f32,
    crest_pan:            f32,
    crest_count:          u32,
    backwash_age:         f32,
    backwash_duration:    f32,
    backwash_strength:    f32,
    backwash_count:       u32,
    shingle_timer:        f32,
    shingle_phase:        f32,
    shingle_phase_b:      f32,
    shingle_hz:           f32,
    shingle_level:        f32,
    shingle_count:        u32,
    sea_state:            f32,
    target_sea_state:     f32,
    direction:            f32,
    target_direction:     f32,
    rumble:               f32,
    wash_left:            f32,
    wash_right:           f32,
    backwash_low_left:    f32,
    backwash_low_right:   f32,
    air_left:             f32,
    air_right:            f32,
    dc_left:              f32,
    dc_right:             f32,
    previous_left:        f32,
    previous_right:       f32,
    gain:                 f32,
    target_gain:          f32,
    presence:             f32,
    target_presence:      f32,
}

Runtime :: struct {
    synth:             Synth,
    stream:            ^sdl.AudioStream,
    owns_audio_system: bool,
    manual_feed:       bool,
}

new_synth :: proc(seed: u32 = 0x4f434541) -> Synth {
    stable_seed := seed == 0 ? u32(0x4f434541) : seed
    synth := Synth {
        settings = {volume = .24, surf = .78, foam = .52, depth = .42},
        random_state = stable_seed,
        foam_phase = .37,
        shore_phase = .83,
        wave_set_phase = f32(stable_seed & 0xffff) / 65_535 * 2 * math.PI,
        gain = 1,
        target_gain = 1,
        presence = 1,
        target_presence = 1,
        sea_state = .25,
        target_sea_state = .25,
    }
    synth.wave_set_strength = .92 + (.5 + .5 * f32(math.sin(f64(synth.wave_set_phase)))) * .16
    synth.wave_variation = (next_noise(&synth) + 1) * .5
    synth.target_wave_strength = (.72 + synth.sea_state * .28 + synth.wave_variation * .32) * synth.wave_set_strength
    synth.wave_strength = synth.target_wave_strength
    synth.target_swell_rate = .96 + (next_noise(&synth) + 1) * .10
    synth.swell_rate = synth.target_swell_rate
    return synth
}

set_muted :: proc "contextless" (synth: ^Synth, muted: bool) {
    if synth != nil do synth.target_gain = muted ? 0 : 1
}

set_conditions :: proc "contextless" (synth: ^Synth, wind_speed, storm_severity: f32, direction: f32 = 0) {
    if synth == nil do return
    wind_state := clamp(wind_speed / 18, 0, 1)
    storm_state := clamp(storm_severity, 0, 1)
    synth.target_sea_state = clamp(max(wind_state, storm_state * .92), 0, 1)
    synth.target_wave_strength =
        (.72 + synth.target_sea_state * .28 + synth.wave_variation * .32) * synth.wave_set_strength
    synth.target_direction = clamp(direction, -1, 1)
}

presence_for_listener_height :: proc "contextless" (height_above_sea: f32) -> f32 {
    altitude := max(height_above_sea, f32(0))
    normalized := clamp((altitude - 12) / 220, 0, 1)
    // Preserve a quiet low-frequency sense of the sea from high aircraft
    // while removing the implausibly close breaker and foam perspective.
    return 1 - normalized * normalized * (3 - 2 * normalized) * .94
}

presence_for_listener :: proc "contextless" (height_above_sea, shore_proximity: f32) -> f32 {
    shoreline_mix := .12 + clamp(shore_proximity, 0, 1) * .88
    return presence_for_listener_height(height_above_sea) * shoreline_mix
}

set_listener_height :: proc "contextless" (synth: ^Synth, height_above_sea: f32) {
    if synth != nil do synth.target_presence = presence_for_listener_height(height_above_sea)
}

set_listener_environment :: proc "contextless" (synth: ^Synth, height_above_sea, shore_proximity: f32) {
    if synth != nil do synth.target_presence = presence_for_listener(height_above_sea, shore_proximity)
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

// Converts a one-pole coefficient authored at 48 kHz to an equivalent
// coefficient at another rate while preserving its real-time decay.
coefficient_for_sample_rate :: proc "contextless" (reference_coefficient, sample_rate: f32) -> f32 {
    if sample_rate <= 0 do return 0
    coefficient := clamp(reference_coefficient, 0, 1)
    return f32(1 - math.pow(f64(1 - coefficient), f64(SAMPLE_RATE) / f64(sample_rate)))
}

render :: proc "contextless" (synth: ^Synth, output: []f32, sample_rate: f32 = SAMPLE_RATE) {
    frame_count := len(output) / CHANNELS
    if synth == nil || frame_count <= 0 || sample_rate <= 0 do return

    primary_step := f32(2 * math.PI * .071 / sample_rate)
    secondary_step := f32(2 * math.PI * .113 / sample_rate)
    foam_step := f32(2 * math.PI * .037 / sample_rate)
    shore_step := f32(2 * math.PI * .019 / sample_rate)
    wave_set_step := f32(2 * math.PI * .013 / sample_rate)
    gain_smoothing := f32(1 - math.exp(f64(-12 / sample_rate)))
    presence_smoothing := f32(1 - math.exp(f64(-.9 / sample_rate)))
    wave_smoothing := f32(1 - math.exp(f64(-.65 / sample_rate)))
    cadence_smoothing := f32(1 - math.exp(f64(-.28 / sample_rate)))
    sea_smoothing := f32(1 - math.exp(f64(-.42 / sample_rate)))
    direction_smoothing := f32(1 - math.exp(f64(-.34 / sample_rate)))
    rumble_cutoff := coefficient_for_sample_rate(.0007, sample_rate)
    wash_cutoff := coefficient_for_sample_rate(.018, sample_rate)
    backwash_cutoff := coefficient_for_sample_rate(.0045, sample_rate)
    shingle_decay := f32(math.exp(f64(-145 / sample_rate)))
    air_cutoff := coefficient_for_sample_rate(.12, sample_rate)
    dc_pole := 1 - coefficient_for_sample_rate(.005, sample_rate)
    for frame in 0 ..< frame_count {
        synth.gain += (synth.target_gain - synth.gain) * gain_smoothing
        synth.presence += (synth.target_presence - synth.presence) * presence_smoothing
        synth.sea_state += (synth.target_sea_state - synth.sea_state) * sea_smoothing
        synth.direction += (synth.target_direction - synth.direction) * direction_smoothing
        synth.wave_strength += (synth.target_wave_strength - synth.wave_strength) * wave_smoothing
        synth.swell_rate += (synth.target_swell_rate - synth.swell_rate) * cadence_smoothing
        synth.wave_set_phase += wave_set_step * (.88 + synth.sea_state * .24)
        if synth.wave_set_phase >= 2 * math.PI do synth.wave_set_phase -= 2 * math.PI
        set_primary := .5 + .5 * f32(math.sin(f64(synth.wave_set_phase)))
        set_secondary := .5 + .5 * f32(math.sin(f64(synth.wave_set_phase * .47 + 1.3)))
        synth.wave_set_strength = .92 + (set_primary * .72 + set_secondary * .28) * .16
        white_left := next_noise(synth)
        white_right := next_noise(synth)
        tempo := .82 + synth.sea_state * .72
        synth.swell_phase += primary_step * tempo * synth.swell_rate
        synth.secondary_phase += secondary_step * (.9 + synth.sea_state * .38)
        synth.foam_phase += foam_step * (.88 + synth.sea_state * .55)
        synth.shore_phase += shore_step
        if synth.swell_phase >= 2 * math.PI {
            synth.swell_phase -= 2 * math.PI
            // Each arriving wave gets a new seeded energy target, avoiding an
            // identical breaker on every primary swell cycle.
            synth.wave_variation = (next_noise(synth) + 1) * .5
            synth.target_wave_strength =
                (.72 + synth.target_sea_state * .28 + synth.wave_variation * .32) * synth.wave_set_strength
            synth.target_swell_rate = .96 + (next_noise(synth) + 1) * .10
            synth.wave_count += 1
        }
        if synth.secondary_phase >= 2 * math.PI do synth.secondary_phase -= 2 * math.PI
        if synth.foam_phase >= 2 * math.PI do synth.foam_phase -= 2 * math.PI
        if synth.shore_phase >= 2 * math.PI do synth.shore_phase -= 2 * math.PI

        primary := .5 + .5 * f32(math.sin(f64(synth.swell_phase - 1.15)))
        secondary := .5 + .5 * f32(math.sin(f64(synth.secondary_phase + .8)))
        swell := primary * primary * (.62 + .38 * secondary) * synth.wave_strength
        breaker_threshold := .62 - synth.sea_state * .12
        breaker := clamp((primary - breaker_threshold) * (2.45 + synth.sea_state * .7), 0, 1)
        breaker *= breaker * synth.wave_strength
        synth.breaker_peak = max(synth.breaker_peak, breaker)
        if synth.previous_breaker <= .001 && breaker > .001 {
            duration_variation := (next_noise(synth) + 1) * .5
            strength_variation := (next_noise(synth) + 1) * .5
            pan_variation := next_noise(synth) * .18
            synth.crest_age = 0
            synth.crest_duration = .18 + duration_variation * .22
            synth.crest_strength = (.48 + synth.sea_state * .42 + strength_variation * .18) * synth.wave_strength
            synth.crest_pan = clamp(synth.direction * synth.sea_state * .27 + pan_variation, -.46, .46)
            synth.crest_count += 1
        }
        if synth.previous_breaker > .001 && breaker <= .001 {
            synth.backwash_age = 0
            synth.backwash_duration = 2.4 + (next_noise(synth) + 1) * .55 + synth.sea_state * .75
            synth.backwash_strength = clamp(synth.breaker_peak, .25, 1.4)
            synth.shingle_timer = .04 + (next_noise(synth) + 1) * .09
            synth.backwash_count += 1
            synth.breaker_peak = 0
        }
        synth.previous_breaker = breaker
        foam_wander := .5 + .5 * f32(math.sin(f64(synth.foam_phase)))
        shore_pan :=
            f32(math.sin(f64(synth.shore_phase))) * .14 +
            f32(math.sin(f64(synth.secondary_phase * .43 + .6))) * .05 +
            synth.direction * synth.sea_state * .27
        shore_pan = clamp(shore_pan, -.46, .46)

        // Shared low rumble, broad stereo wash, and bright foam give the
        // synthesized sea depth without relying on a looping recording.
        synth.rumble += rumble_cutoff * (white_left - synth.rumble)
        synth.wash_left += wash_cutoff * (white_left - synth.wash_left)
        synth.wash_right += wash_cutoff * (white_right - synth.wash_right)
        synth.backwash_low_left += backwash_cutoff * (white_left - synth.backwash_low_left)
        synth.backwash_low_right += backwash_cutoff * (white_right - synth.backwash_low_right)
        synth.air_left += air_cutoff * (white_left - synth.air_left)
        synth.air_right += air_cutoff * (white_right - synth.air_right)

        distance_body := .30 + synth.presence * .70
        distance_wash := .18 + synth.presence * .82
        distance_foam := synth.presence * synth.presence
        output_distance := .20 + synth.presence * .80
        depth :=
            synth.rumble * (.34 + .66 * swell) * synth.settings.depth * (.72 + synth.sea_state * .58) * distance_body
        wash_gain := (.18 + .82 * swell) * synth.settings.surf * (.62 + synth.sea_state * .72) * distance_wash
        foam_gain :=
            breaker * (.55 + .45 * foam_wander) * synth.settings.foam * (.24 + synth.sea_state * 1.34) * distance_foam
        crest_left, crest_right := f32(0), f32(0)
        if synth.crest_duration > 0 {
            crest_progress := synth.crest_age / synth.crest_duration
            crest_envelope :=
                (1 - f32(math.exp(f64(-synth.crest_age * 52)))) * f32(math.exp(f64(-crest_progress * 3.8)))
            crest_body := synth.rumble * .58 + (synth.wash_left + synth.wash_right) * .21
            crest_spray_left := white_left - synth.air_left
            crest_spray_right := white_right - synth.air_right
            crest_gain :=
                crest_envelope *
                synth.crest_strength *
                (.10 + synth.sea_state * .08) *
                synth.settings.surf *
                distance_foam
            crest_left = (crest_body * .62 + crest_spray_left * .38) * crest_gain * (1 - synth.crest_pan)
            crest_right = (crest_body * .62 + crest_spray_right * .38) * crest_gain * (1 + synth.crest_pan)
            synth.crest_age += 1 / sample_rate
            if synth.crest_age >= synth.crest_duration do synth.crest_duration = 0
        }
        left_gain := 1 - shore_pan
        right_gain := 1 + shore_pan
        backwash_left, backwash_right := f32(0), f32(0)
        shingle := f32(0)
        if synth.backwash_duration > 0 {
            backwash_progress := synth.backwash_age / synth.backwash_duration
            backwash_envelope :=
                (1 - f32(math.exp(f64(-synth.backwash_age * 4.5)))) * f32(math.exp(f64(-backwash_progress * 2.35)))
            backwash_gain :=
                backwash_envelope *
                synth.backwash_strength *
                synth.settings.surf *
                (.13 + synth.sea_state * .08) *
                distance_wash
            // Reversing the shore-pan gains makes the wash appear to draw
            // away from the side where the breaker arrived.
            backwash_left =
                ((synth.wash_left - synth.backwash_low_left) * .72 - synth.rumble * .18) * backwash_gain * right_gain
            backwash_right =
                ((synth.wash_right - synth.backwash_low_right) * .72 - synth.rumble * .18) * backwash_gain * left_gain
            // Retreating water rolls small shoreline stones in sparse,
            // inharmonic clacks. The event density follows the energized
            // backwash, while each seeded strike excites a different short
            // pebble mode instead of replaying a fixed granular loop.
            synth.shingle_timer -= 1 / sample_rate
            if synth.shingle_timer <= 0 {
                pitch_variation := (next_noise(synth) + 1) * .5
                strength_variation := (next_noise(synth) + 1) * .5
                interval_variation := (next_noise(synth) + 1) * .5
                synth.shingle_hz = 430 + pitch_variation * 920
                synth.shingle_phase = 0
                synth.shingle_phase_b = 0
                synth.shingle_level +=
                    (.10 + strength_variation * .13) * synth.backwash_strength * (.42 + synth.sea_state * .58)
                event_rate := 4.5 + synth.sea_state * 9 + synth.backwash_strength * 3
                synth.shingle_timer = (.58 + interval_variation * .84) / event_rate
                synth.shingle_count += 1
            }
            synth.backwash_age += 1 / sample_rate
            if synth.backwash_age >= synth.backwash_duration {
                synth.backwash_duration = 0
            }
        }
        if synth.shingle_level > .000001 {
            synth.shingle_phase += synth.shingle_hz / sample_rate
            synth.shingle_phase_b += synth.shingle_hz * 2.63 / sample_rate
            synth.shingle_phase -= math.floor(synth.shingle_phase)
            synth.shingle_phase_b -= math.floor(synth.shingle_phase_b)
            synth.shingle_level *= shingle_decay
            shingle =
                (f32(math.sin(f64(synth.shingle_phase * 2 * math.PI))) * .76 +
                    f32(math.sin(f64(synth.shingle_phase_b * 2 * math.PI))) * .24) *
                synth.shingle_level *
                synth.settings.surf *
                distance_foam
        } else {
            synth.shingle_level = 0
        }
        left :=
            depth +
            synth.wash_left * wash_gain * left_gain +
            (white_left - synth.air_left) * foam_gain * .34 * left_gain +
            crest_left +
            backwash_left +
            shingle * right_gain * .19
        right :=
            depth +
            synth.wash_right * wash_gain * right_gain +
            (white_right - synth.air_right) * foam_gain * .34 * right_gain +
            crest_right +
            backwash_right +
            shingle * left_gain * .19

        dc_blocked_left := left - synth.previous_left + dc_pole * synth.dc_left
        dc_blocked_right := right - synth.previous_right + dc_pole * synth.dc_right
        synth.previous_left = left
        synth.previous_right = right
        synth.dc_left = dc_blocked_left
        synth.dc_right = dc_blocked_right
        output[frame * 2] = soft_clip(dc_blocked_left * synth.settings.volume * 2.4) * synth.gain * output_distance
        output[frame * 2 + 1] =
            soft_clip(dc_blocked_right * synth.settings.volume * 2.4) * synth.gain * output_distance
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
        if !sdl.PutAudioStreamData(stream, raw_data(samples[:count]), c.int(count * size_of(f32))) do break
        remaining -= count
    }
}

init :: proc(runtime: ^Runtime, playback_device: sdl.AudioDeviceID = 0) -> bool {
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
    if playback_device != 0 {
        runtime.stream = sdl.CreateAudioStream(&spec, nil)
        if runtime.stream != nil && !sdl.BindAudioStream(playback_device, runtime.stream) {
            sdl.DestroyAudioStream(runtime.stream)
            runtime.stream = nil
        }
        runtime.manual_feed = runtime.stream != nil
    } else {
        runtime.stream = sdl.OpenAudioDeviceStream(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, audio_callback, runtime)
    }
    if runtime.stream == nil {
        if runtime.owns_audio_system do sdl.QuitSubSystem(sdl.INIT_AUDIO)
        runtime.owns_audio_system = false
        return false
    }
    if playback_device == 0 && !sdl.ResumeAudioStreamDevice(runtime.stream) {
        sdl.DestroyAudioStream(runtime.stream)
        runtime.stream = nil
        if runtime.owns_audio_system do sdl.QuitSubSystem(sdl.INIT_AUDIO)
        runtime.owns_audio_system = false
        return false
    }
    return true
}

update :: proc(
    runtime: ^Runtime,
    wind_speed: f32 = 0,
    storm_severity: f32 = 0,
    muted: bool = false,
    listener_height_above_sea: f32 = 0,
    shore_proximity: f32 = 1,
    direction: f32 = 0,
) {
    if runtime == nil do return
    if runtime.stream == nil {
        set_conditions(&runtime.synth, wind_speed, storm_severity, direction)
        set_muted(&runtime.synth, muted)
        set_listener_environment(&runtime.synth, listener_height_above_sea, shore_proximity)
    } else if sdl.LockAudioStream(runtime.stream) {
        set_conditions(&runtime.synth, wind_speed, storm_severity, direction)
        set_muted(&runtime.synth, muted)
        set_listener_environment(&runtime.synth, listener_height_above_sea, shore_proximity)
        sdl.UnlockAudioStream(runtime.stream)
    }
    if runtime.manual_feed {
        queued_samples := int(sdl.GetAudioStreamQueued(runtime.stream)) / size_of(f32)
        target_samples := SAMPLE_RATE / 10 * CHANNELS
        samples: [CALLBACK_SAMPLES]f32
        for queued_samples < target_samples {
            count := min(target_samples - queued_samples, CALLBACK_SAMPLES)
            count -= count % CHANNELS
            if count == 0 do break
            render(&runtime.synth, samples[:count])
            if !sdl.PutAudioStreamData(runtime.stream, raw_data(samples[:count]), c.int(count * size_of(f32))) {
                break
            }
            queued_samples += count
        }
    }
}

destroy :: proc(runtime: ^Runtime) {
    if runtime == nil do return
    if runtime.stream != nil do sdl.DestroyAudioStream(runtime.stream)
    if runtime.owns_audio_system do sdl.QuitSubSystem(sdl.INIT_AUDIO)
    runtime^ = {}
}
