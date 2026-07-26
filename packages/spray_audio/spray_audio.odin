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
    intensity:         f32,
    target_intensity:  f32,
    pressure_low:      f32,
    hiss_low_left:     f32,
    hiss_low_right:    f32,
    body_low_left:     f32,
    body_low_right:    f32,
    flutter_phase:     f32,
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
    }
}

set_active :: proc "contextless" (synth: ^Synth, active: bool, intensity: f32 = .7) {
    if synth == nil do return
    synth.target_level = active ? 1 : 0
    synth.target_intensity = clamp(intensity, 0, 1)
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

render :: proc "contextless" (synth: ^Synth, output: []f32, sample_rate: f32 = SAMPLE_RATE) {
    frame_count := len(output) / CHANNELS
    if synth == nil || frame_count <= 0 || sample_rate <= 0 do return

    // Fast attack makes the can feel responsive; the slower release prevents
    // zipper noise and clicks when a stroke ends between audio callbacks.
    attack := f32(1 - math.exp(f64(-125 / sample_rate)))
    release := f32(1 - math.exp(f64(-28 / sample_rate)))
    control_smoothing := f32(1 - math.exp(f64(-18 / sample_rate)))
    pressure_cutoff := f32(1 - math.exp(f64(-2 * math.PI * 135 / sample_rate)))
    body_cutoff := f32(1 - math.exp(f64(-2 * math.PI * 1150 / sample_rate)))
    hiss_cutoff := f32(1 - math.exp(f64(-2 * math.PI * 5200 / sample_rate)))
    flutter_step := f32(2 * math.PI * 17 / sample_rate)

    for frame in 0 ..< frame_count {
        envelope_rate := synth.target_level > synth.level ? attack : release
        synth.level += (synth.target_level - synth.level) * envelope_rate
        synth.intensity += (synth.target_intensity - synth.intensity) * control_smoothing

        shared := next_noise(synth)
        side := next_noise(synth)
        left_noise := shared * .82 + side * .18
        right_noise := shared * .82 - side * .18
        synth.pressure_low += (shared - synth.pressure_low) * pressure_cutoff
        synth.body_low_left += (left_noise - synth.body_low_left) * body_cutoff
        synth.body_low_right += (right_noise - synth.body_low_right) * body_cutoff
        synth.hiss_low_left += (left_noise - synth.hiss_low_left) * hiss_cutoff
        synth.hiss_low_right += (right_noise - synth.hiss_low_right) * hiss_cutoff

        synth.flutter_phase += flutter_step
        if synth.flutter_phase >= 2 * math.PI do synth.flutter_phase -= 2 * math.PI
        flutter := .91 + .09 * f32(math.sin(f64(synth.flutter_phase)))

        // Mid-band atomizer body plus bright aerosol hiss and a quiet shared
        // pressure component gives the result the scale of a handheld can.
        body_left := synth.body_low_left - synth.pressure_low
        body_right := synth.body_low_right - synth.pressure_low
        hiss_left := left_noise - synth.hiss_low_left
        hiss_right := right_noise - synth.hiss_low_right
        pressure := synth.pressure_low * .11
        brightness := .18 + synth.intensity * .16
        gain := synth.level * (.24 + synth.intensity * .12) * flutter
        left := (body_left * .62 + hiss_left * brightness + pressure) * gain
        right := (body_right * .62 + hiss_right * brightness + pressure) * gain
        output[frame * 2] = soft_clip(left * 1.7)
        output[frame * 2 + 1] = soft_clip(right * 1.7)
    }
}

audio_callback :: proc "c" (
    userdata: rawptr,
    stream: ^sdl.AudioStream,
    additional_amount, total_amount: c.int,
) {
    runtime := cast(^Runtime)userdata
    remaining := int(additional_amount) / size_of(f32)
    samples: [CALLBACK_SAMPLES]f32
    for remaining > 0 {
        count := min(remaining, CALLBACK_SAMPLES)
        count -= count % CHANNELS
        if count == 0 do break
        render(&runtime.synth, samples[:count])
        if !sdl.PutAudioStreamData(
            stream,
            raw_data(samples[:count]),
            c.int(count * size_of(f32)),
        ) {
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
    spec := sdl.AudioSpec{format = .F32, channels = CHANNELS, freq = SAMPLE_RATE}
    runtime.stream = sdl.OpenAudioDeviceStream(
        sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK,
        &spec,
        audio_callback,
        runtime,
    )
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

update :: proc(runtime: ^Runtime, active: bool, intensity: f32 = .7) {
    if runtime == nil || runtime.stream == nil do return
    if sdl.LockAudioStream(runtime.stream) {
        set_active(&runtime.synth, active, intensity)
        sdl.UnlockAudioStream(runtime.stream)
    }
}

destroy :: proc(runtime: ^Runtime) {
    if runtime == nil do return
    if runtime.stream != nil do sdl.DestroyAudioStream(runtime.stream)
    if runtime.owns_audio_system do sdl.QuitSubSystem(sdl.INIT_AUDIO)
    runtime^ = {}
}
