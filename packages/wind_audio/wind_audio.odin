package wind_audio

import "core:c"
import "core:math"
import sdl "vendor:sdl3"

SAMPLE_RATE :: 48_000
CHANNELS :: 2
CALLBACK_SAMPLES :: 4096

Synth :: struct {
    random_state:    u32,
    strength:        f32,
    target_strength: f32,
    broad_low:       f32,
    body_low:        f32,
    left_air_low:    f32,
    right_air_low:   f32,
    gust_phase:      f32,
}

Runtime :: struct {
    synth:             Synth,
    stream:            ^sdl.AudioStream,
    owns_audio_system: bool,
}

new_synth :: proc(seed: u32 = 0x6d2b79f5) -> Synth {
    return {random_state = seed == 0 ? 0x6d2b79f5 : seed}
}

set_strength :: proc(synth: ^Synth, strength: f32) {
    synth.target_strength = clamp(strength, 0, 1)
}

next_noise :: proc "contextless" (synth: ^Synth) -> f32 {
    x := synth.random_state
    x = x ~ (x << 13)
    x = x ~ (x >> 17)
    x = x ~ (x << 5)
    synth.random_state = x
    return f32(x & 0x00ffffff) / f32(0x007fffff) - 1
}

render :: proc "contextless" (synth: ^Synth, output: []f32, sample_rate: f32 = SAMPLE_RATE) {
    frame_count := len(output) / CHANNELS
    if frame_count <= 0 || sample_rate <= 0 do return

    smoothing := f32(1 - math.exp(f64(-12 / sample_rate)))
    broad_cutoff := f32(1 - math.exp(f64(-2 * math.PI * 520 / sample_rate)))
    body_cutoff := f32(1 - math.exp(f64(-2 * math.PI * 92 / sample_rate)))
    air_cutoff := f32(1 - math.exp(f64(-2 * math.PI * 2700 / sample_rate)))
    phase_step := f32(2 * math.PI * .11 / sample_rate)

    for frame in 0 ..< frame_count {
        synth.strength += (synth.target_strength - synth.strength) * smoothing
        noise := next_noise(synth)
        stereo_noise := next_noise(synth)
        synth.broad_low += (noise - synth.broad_low) * broad_cutoff
        synth.body_low += (synth.broad_low - synth.body_low) * body_cutoff
        synth.left_air_low += (noise - synth.left_air_low) * air_cutoff
        synth.right_air_low += (stereo_noise - synth.right_air_low) * air_cutoff

        gust :=
            .72 + .19 * f32(math.sin(f64(synth.gust_phase))) + .09 * f32(math.sin(f64(synth.gust_phase * 2.37 + 1.4)))
        synth.gust_phase += phase_step
        if synth.gust_phase >= 2 * math.PI do synth.gust_phase -= 2 * math.PI

        body := synth.broad_low - synth.body_low
        left_air := noise - synth.left_air_low
        right_air := stereo_noise - synth.right_air_low
        gain := synth.strength * synth.strength * gust
        output[frame * 2] = clamp((body * .62 + left_air * .16) * gain, -.9, .9)
        output[frame * 2 + 1] = clamp((body * .62 + right_air * .16) * gain, -.9, .9)
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

init :: proc(runtime: ^Runtime) -> bool {
    runtime.synth = new_synth()
    already_initialized := sdl.WasInit(sdl.INIT_AUDIO) != {}
    if !already_initialized {
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
        if runtime.owns_audio_system {
            sdl.QuitSubSystem(sdl.INIT_AUDIO)
            runtime.owns_audio_system = false
        }
        return false
    }
    if !sdl.ResumeAudioStreamDevice(runtime.stream) {
        sdl.DestroyAudioStream(runtime.stream)
        runtime.stream = nil
        if runtime.owns_audio_system {
            sdl.QuitSubSystem(sdl.INIT_AUDIO)
            runtime.owns_audio_system = false
        }
        return false
    }
    return true
}

update :: proc(runtime: ^Runtime, wind_speed: f32, muted: bool = false) {
    if runtime.stream == nil do return
    strength := muted ? f32(0) : clamp((wind_speed - .5) / 12, 0, 1)
    if sdl.LockAudioStream(runtime.stream) {
        set_strength(&runtime.synth, strength)
        sdl.UnlockAudioStream(runtime.stream)
    }
}

destroy :: proc(runtime: ^Runtime) {
    if runtime.stream != nil {
        sdl.DestroyAudioStream(runtime.stream)
        runtime.stream = nil
    }
    if runtime.owns_audio_system {
        sdl.QuitSubSystem(sdl.INIT_AUDIO)
        runtime.owns_audio_system = false
    }
}
