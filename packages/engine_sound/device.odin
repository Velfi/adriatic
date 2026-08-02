package engine_sound

import "core:c"
import sdl "vendor:sdl3"

BUFFER_SAMPLES :: 1024
TARGET_QUEUED_FRAMES :: BUFFER_SAMPLES * 4
AUDIO_CHANNELS :: 2

Aux_Mix_Callback :: #type proc(userdata: rawptr, output: []f32)

Device :: struct {
    stream:         ^sdl.AudioStream,
    synth:          Synth,
    slip_synth:     Slip_Synth,
    roll_synth:     Roll_Synth,
    crash_mixer:    Crash_Mixer,
    footstep_mixer: Footstep_Mixer,
    dialogue_voice: Dialogue_Voice_Mixer,
    engine_width:   Source_Width_State,
    tire_width:     Source_Width_State,
    mix_state:      [AUDIO_CHANNELS]Mix_State,
    mute_gain:      f32,
    mono_buffer:    [BUFFER_SAMPLES]f32,
    buffer:         [BUFFER_SAMPLES * AUDIO_CHANNELS]f32,
    aux_mix:        Aux_Mix_Callback,
    aux_userdata:   rawptr,
}

reset_runtime_preserving_io :: proc(device: ^Device) {
    if device == nil do return
    stream := device.stream
    aux_mix := device.aux_mix
    aux_userdata := device.aux_userdata
    device^ = {
        stream       = stream,
        aux_mix      = aux_mix,
        aux_userdata = aux_userdata,
    }
    device.synth = new()
    device.slip_synth = new_slip()
    device.roll_synth = new_roll()
    device.crash_mixer = new_crash_mixer()
    device.footstep_mixer = new_footstep_mixer()
    device.dialogue_voice = {
        unit_blend = .82,
    }
    device.engine_width = {}
    device.tire_width = {}
    device.mix_state = {}
    device.mute_gain = 1
}

open :: proc(device: ^Device, playback_device: sdl.AudioDeviceID = 0) -> bool {
    if device == nil do return false
    reset_runtime_preserving_io(device)
    if !sdl.InitSubSystem(sdl.INIT_AUDIO) do return false
    spec := sdl.AudioSpec {
        format   = .F32,
        channels = AUDIO_CHANNELS,
        freq     = SAMPLE_RATE,
    }
    if playback_device != 0 {
        device.stream = sdl.CreateAudioStream(&spec, nil)
        if device.stream != nil && !sdl.BindAudioStream(playback_device, device.stream) {
            sdl.DestroyAudioStream(device.stream)
            device.stream = nil
        }
    } else {
        device.stream = sdl.OpenAudioDeviceStream(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, nil, nil)
    }
    if device.stream == nil {
        sdl.QuitSubSystem(sdl.INIT_AUDIO)
        return false
    }
    if playback_device == 0 && !sdl.ResumeAudioStreamDevice(device.stream) {
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
    crash_pan: f32 = 0,
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
            crash_pan,
        )
    }
    if controls.shift do trigger_shift(&device.synth)
    if footstep_triggered {
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
    queued_frames := int(sdl.GetAudioStreamQueued(device.stream)) / (bytes_per_sample * AUDIO_CHANNELS)
    for queued_frames < TARGET_QUEUED_FRAMES {
        render(&device.synth, controls, device.mono_buffer[:])
        powertrain_width := .055 + device.synth.propeller_mix * .035 + device.synth.rotor_mix * .055
        widen_source_stereo(&device.engine_width, device.mono_buffer[:], device.buffer[:], powertrain_width)
        for &sample in device.mono_buffer do sample = 0
        render_slip_add(&device.slip_synth, slip, device.mono_buffer[:])
        render_roll_add(&device.roll_synth, roll, device.mono_buffer[:])
        tire_width := .07 + device.roll_synth.speed * .045 + device.slip_synth.amount * .025
        widen_source_stereo(&device.tire_width, device.mono_buffer[:], device.buffer[:], tire_width, true)
        render_crash_mixer_stereo_add(&device.crash_mixer, device.buffer[:])
        for &sample in device.mono_buffer do sample = 0
        render_dialogue_voice_mixer_add(&device.dialogue_voice, device.mono_buffer[:])
        for sample, frame in device.mono_buffer {
            device.buffer[frame * 2] += sample
            device.buffer[frame * 2 + 1] += sample
        }
        render_footstep_mixer_stereo_add(&device.footstep_mixer, device.buffer[:])
        if device.aux_mix != nil do device.aux_mix(device.aux_userdata, device.buffer[:])
        process_mix_interleaved(device.mix_state[:], device.buffer[:], AUDIO_CHANNELS)
        apply_device_mute(&device.mute_gain, device.buffer[:], muted, AUDIO_CHANNELS)
        if !sdl.PutAudioStreamData(
            device.stream,
            raw_data(device.buffer[:]),
            c.int(len(device.buffer) * bytes_per_sample),
        ) {
            break
        }
        queued_frames += BUFFER_SAMPLES
    }
}

// UI muting is deliberately independent of Controls.active. Pausing should
// not synthesize a mechanical shutdown and resume should not retrigger the
// starter; only the final device gain moves, with a short click-free ramp.
apply_device_mute :: proc(gain: ^f32, samples: []f32, muted: bool, channels: int = 1) {
    if gain == nil do return
    target := muted ? f32(0) : f32(1)
    rate := muted ? f32(18) : f32(12)
    channel_count := max(channels, 1)
    seconds_per_frame := f32(1.0 / SAMPLE_RATE)
    frame_count := len(samples) / channel_count
    for frame in 0 ..< frame_count {
        gain^ = approach(gain^, target, rate, seconds_per_frame)
        for channel in 0 ..< channel_count {
            samples[frame * channel_count + channel] *= gain^
        }
    }
    for index in frame_count * channel_count ..< len(samples) {
        gain^ = approach(gain^, target, rate, seconds_per_frame)
        samples[index] *= gain^
    }
}
