package engine_sound

import "core:c"
import sdl "vendor:sdl3"

BUFFER_SAMPLES :: 1024
TARGET_QUEUED_SAMPLES :: SAMPLE_RATE / 10

Device :: struct {
    stream:     ^sdl.AudioStream,
    synth:      Synth,
    slip_synth: Slip_Synth,
    roll_synth: Roll_Synth,
    buffer:     [BUFFER_SAMPLES]f32,
}

open :: proc(device: ^Device) -> bool {
    if device == nil do return false
    device.synth = new()
    device.slip_synth = new_slip()
    device.roll_synth = new_roll()
    if !sdl.InitSubSystem(sdl.INIT_AUDIO) do return false
    spec := sdl.AudioSpec{format = .F32, channels = 1, freq = SAMPLE_RATE}
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
) {
    if device == nil || device.stream == nil do return
    bytes_per_sample := size_of(f32)
    queued_samples := int(sdl.GetAudioStreamQueued(device.stream)) / bytes_per_sample
    for queued_samples < TARGET_QUEUED_SAMPLES {
        render(&device.synth, controls, device.buffer[:])
        render_slip_add(&device.slip_synth, slip, device.buffer[:])
        render_roll_add(&device.roll_synth, roll, device.buffer[:])
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
