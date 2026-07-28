package engine_sound

import "core:math"

// Dialogue_Voice_Profile is deliberately presentation-neutral. Games choose
// stable profiles for their speakers and feed visible glyphs to the synth.
Dialogue_Voice_Profile :: struct {
    base_hz:    f32,
    range_hz:   f32,
    brightness: f32,
    warmth:     f32,
    gain:       f32,
}

Dialogue_Voice :: struct {
    phase_a:    f32,
    phase_b:    f32,
    phase_c:    f32,
    age:        f32,
    duration:   f32,
    frequency:  f32,
    brightness: f32,
    warmth:     f32,
    gain:       f32,
}

dialogue_voice_trigger :: proc(device: ^Device, glyph: u8, profile: Dialogue_Voice_Profile) {
    if device == nil || device.stream == nil do return
    // A tiny deterministic hash gives words melodic motion without attempting
    // to imitate phonemes from any authored language.
    hash := u32(glyph) * 747796405 + 2891336453
    variation := f32(hash & 255) / 255
    voice := &device.dialogue_voice
    voice.age = 0
    voice.duration = .052 + f32((hash >> 8) & 7) * .002
    voice.frequency = max(profile.base_hz + (variation - .5) * profile.range_hz, f32(90))
    voice.brightness = clamp(profile.brightness, 0, 1)
    voice.warmth = clamp(profile.warmth, 0, 1)
    voice.gain = clamp(profile.gain, 0, .24)
}

dialogue_voice_stop :: proc(device: ^Device) {
    if device == nil do return
    device.dialogue_voice.duration = 0
    device.dialogue_voice.age = 0
}

render_dialogue_voice_add :: proc(voice: ^Dialogue_Voice, samples: []f32) {
    if voice == nil || voice.duration <= 0 do return
    seconds_per_sample := f32(1.0 / SAMPLE_RATE)
    for &sample in samples {
        if voice.age >= voice.duration {
            voice.duration = 0
            break
        }
        progress := voice.age / voice.duration
        attack := min(progress * 18, f32(1))
        release := f32(math.exp(f64(-progress * 5.8)))
        wobble := 1 + f32(math.sin(f64(progress * math.TAU * 1.5))) * .018
        frequency := voice.frequency * wobble
        voice.phase_a = math.mod(voice.phase_a + frequency * seconds_per_sample, 1)
        voice.phase_b = math.mod(voice.phase_b + frequency * 2.01 * seconds_per_sample, 1)
        voice.phase_c = math.mod(voice.phase_c + frequency * 3.97 * seconds_per_sample, 1)
        fundamental := f32(math.sin(f64(voice.phase_a * math.TAU)))
        bright :=
            f32(math.sin(f64(voice.phase_b * math.TAU))) * .34 + f32(math.sin(f64(voice.phase_c * math.TAU))) * .13
        body := fundamental * (1 - voice.brightness * .35) + bright * voice.brightness
        // A warm profile has a rounder envelope and less upper-partial energy.
        warmth_gain := .78 + voice.warmth * .22
        sample += body * attack * release * voice.gain * warmth_gain
        voice.age += seconds_per_sample
    }
}
