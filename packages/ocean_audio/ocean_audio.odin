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
    settings:        Settings,
    random_state:    u32,
    swell_phase:     f32,
    secondary_phase: f32,
    foam_phase:      f32,
    rumble:          f32,
    wash_left:       f32,
    wash_right:      f32,
    air_left:        f32,
    air_right:       f32,
    dc_left:         f32,
    dc_right:        f32,
    previous_left:   f32,
    previous_right:  f32,
    gain:            f32,
    target_gain:     f32,
}

Runtime :: struct {
    synth:             Synth,
    stream:            ^sdl.AudioStream,
    owns_audio_system: bool,
}

new_synth :: proc(seed: u32 = 0x4f434541) -> Synth {
    return {
        settings = {volume = .24, surf = .78, foam = .52, depth = .42},
        random_state = seed == 0 ? 0x4f434541 : seed,
        foam_phase = .37,
        gain = 1,
        target_gain = 1,
    }
}

set_muted :: proc "contextless" (synth: ^Synth, muted: bool) {
    if synth != nil do synth.target_gain = muted ? 0 : 1
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

    primary_step := f32(2 * math.PI * .071 / sample_rate)
    secondary_step := f32(2 * math.PI * .113 / sample_rate)
    foam_step := f32(2 * math.PI * .037 / sample_rate)
    gain_smoothing := f32(1 - math.exp(f64(-12 / sample_rate)))
    for frame in 0 ..< frame_count {
        synth.gain += (synth.target_gain - synth.gain) * gain_smoothing
        white_left := next_noise(synth)
        white_right := next_noise(synth)
        synth.swell_phase += primary_step
        synth.secondary_phase += secondary_step
        synth.foam_phase += foam_step
        if synth.swell_phase >= 2 * math.PI do synth.swell_phase -= 2 * math.PI
        if synth.secondary_phase >= 2 * math.PI do synth.secondary_phase -= 2 * math.PI
        if synth.foam_phase >= 2 * math.PI do synth.foam_phase -= 2 * math.PI

        primary := .5 + .5 * f32(math.sin(f64(synth.swell_phase - 1.15)))
        secondary := .5 + .5 * f32(math.sin(f64(synth.secondary_phase + .8)))
        swell := primary * primary * (.62 + .38 * secondary)
        breaker := clamp((primary - .56) * 2.7, 0, 1)
        breaker *= breaker
        foam_wander := .5 + .5 * f32(math.sin(f64(synth.foam_phase)))

        // Shared low rumble, broad stereo wash, and bright foam give the
        // synthesized sea depth without relying on a looping recording.
        synth.rumble += .0007 * (white_left - synth.rumble)
        synth.wash_left += .018 * (white_left - synth.wash_left)
        synth.wash_right += .018 * (white_right - synth.wash_right)
        synth.air_left += .12 * (white_left - synth.air_left)
        synth.air_right += .12 * (white_right - synth.air_right)

        depth := synth.rumble * (.34 + .66 * swell) * synth.settings.depth
        wash_gain := (.18 + .82 * swell) * synth.settings.surf
        foam_gain := breaker * (.55 + .45 * foam_wander) * synth.settings.foam
        left := depth + synth.wash_left * wash_gain + (white_left - synth.air_left) * foam_gain * .34
        right := depth + synth.wash_right * wash_gain + (white_right - synth.air_right) * foam_gain * .34

        dc_blocked_left := left - synth.previous_left + .995 * synth.dc_left
        dc_blocked_right := right - synth.previous_right + .995 * synth.dc_right
        synth.previous_left = left
        synth.previous_right = right
        synth.dc_left = dc_blocked_left
        synth.dc_right = dc_blocked_right
        output[frame * 2] = soft_clip(dc_blocked_left * synth.settings.volume * 2.4) * synth.gain
        output[frame * 2 + 1] = soft_clip(dc_blocked_right * synth.settings.volume * 2.4) * synth.gain
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

update :: proc(runtime: ^Runtime, muted: bool) {
    if runtime == nil || runtime.stream == nil do return
    if sdl.LockAudioStream(runtime.stream) {
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
