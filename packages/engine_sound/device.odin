package engine_sound

import "core:c"
import "core:fmt"
import "core:math"
import sdl "vendor:sdl3"

BUFFER_SAMPLES :: 1024
TARGET_QUEUED_SAMPLES :: SAMPLE_RATE / 10

Device :: struct {
    stream:         ^sdl.AudioStream,
    synth:          Synth,
    slip_synth:     Slip_Synth,
    roll_synth:     Roll_Synth,
    crash_mixer:    Crash_Mixer,
    footstep_mixer: Footstep_Mixer,
    dialogue_voice: Dialogue_Voice,
    mix_state:      Mix_State,
    mute_gain:      f32,
    buffer:         [BUFFER_SAMPLES]f32,
}

open :: proc(device: ^Device) -> bool {
    if device == nil do return false
    device.synth = new()
    device.slip_synth = new_slip()
    device.roll_synth = new_roll()
    device.crash_mixer = new_crash_mixer()
    device.footstep_mixer = new_footstep_mixer()
    device.dialogue_voice = {}
    device.mix_state = {}
    device.mute_gain = 1
    if !sdl.InitSubSystem(sdl.INIT_AUDIO) do return false
    spec := sdl.AudioSpec {
        format   = .F32,
        channels = 1,
        freq     = SAMPLE_RATE,
    }
    device.stream = sdl.OpenAudioDeviceStream(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, nil, nil)
    if device.stream == nil {
        sdl.QuitSubSystem(sdl.INIT_AUDIO)
        return false
    }
    if !sdl.ResumeAudioStreamDevice(device.stream) {
        sdl.DestroyAudioStream(device.stream)
        device.stream = nil
        sdl.QuitSubSystem(sdl.INIT_AUDIO)
        return false
    }
    return true
}

close :: proc(device: ^Device) {
    if device == nil do return
    if device.stream != nil {
        sdl.DestroyAudioStream(device.stream)
        device.stream = nil
    }
    sdl.QuitSubSystem(sdl.INIT_AUDIO)
}

update :: proc(
    device: ^Device,
    controls: Controls,
    slip := Slip_Controls{},
    roll := Roll_Controls{},
    crash_severity: f32 = 0,
    crash_water_mix: f32 = 0,
    crash_slide_speed: f32 = 0,
    crash_surface: Crash_Surface = .Dirt,
    footstep_triggered: bool = false,
    footstep_intensity: f32 = .5,
    footstep_surface: Footstep_Surface = .Grass,
    footstep_landing: bool = false,
    footstep_wetness: f32 = 0,
    crash_profile: Crash_Profile = .Car,
    crash_wetness: f32 = 0,
    crash_obliqueness: f32 = 0,
    footstep_slide: f32 = 0,
    muted: bool = false,
) {
    if device == nil || device.stream == nil do return
    if crash_severity > 0 {
        trigger_crash_mixer(
            &device.crash_mixer,
            crash_severity,
            crash_water_mix,
            crash_slide_speed,
            crash_surface,
            crash_profile,
            crash_wetness,
            crash_obliqueness,
        )
    }
    if controls.shift do trigger_shift(&device.synth)
    if footstep_triggered {
        fmt.eprintf(
            "audio probe: footstep trigger intensity=%.3f queued_bytes=%d device=%d\n",
            footstep_intensity,
            sdl.GetAudioStreamQueued(device.stream),
            sdl.GetAudioStreamDevice(device.stream),
        )
        trigger_footstep_mixer(
            &device.footstep_mixer,
            footstep_intensity,
            footstep_surface,
            footstep_landing,
            footstep_wetness,
            footstep_slide,
        )
    }
    bytes_per_sample := size_of(f32)
    queued_samples := int(sdl.GetAudioStreamQueued(device.stream)) / bytes_per_sample
    for queued_samples < TARGET_QUEUED_SAMPLES {
        render(&device.synth, controls, device.buffer[:])
        render_slip_add(&device.slip_synth, slip, device.buffer[:])
        render_roll_add(&device.roll_synth, roll, device.buffer[:])
        render_footstep_mixer_add(&device.footstep_mixer, device.buffer[:])
        render_crash_mixer_add(&device.crash_mixer, device.buffer[:])
        render_dialogue_voice_add(&device.dialogue_voice, device.buffer[:])
        process_mix(&device.mix_state, device.buffer[:])
        apply_device_mute(&device.mute_gain, device.buffer[:], muted)
        if footstep_triggered {
            peak := f32(0)
            for sample in device.buffer do peak = max(peak, math.abs(sample))
            fmt.eprintf(
                "audio probe: mixed peak=%.6f muted=%v gain=%.3f\n",
                peak,
                muted,
                device.mute_gain,
            )
        }
        if !sdl.PutAudioStreamData(
            device.stream,
            raw_data(device.buffer[:]),
            c.int(len(device.buffer) * bytes_per_sample),
        ) {
            break
        }
        queued_samples += len(device.buffer)
    }
}

// UI muting is deliberately independent of Controls.active. Pausing should
// not synthesize a mechanical shutdown and resume should not retrigger the
// starter; only the final device gain moves, with a short click-free ramp.
apply_device_mute :: proc(gain: ^f32, samples: []f32, muted: bool) {
    if gain == nil do return
    target := muted ? f32(0) : f32(1)
    rate := muted ? f32(18) : f32(12)
    seconds_per_sample := f32(1.0 / SAMPLE_RATE)
    for &sample in samples {
        gain^ = approach(gain^, target, rate, seconds_per_sample)
        sample *= gain^
    }
}
