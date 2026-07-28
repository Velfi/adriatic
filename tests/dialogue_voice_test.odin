package tests

import engine_sound "../packages/engine_sound"
import "core:testing"

@(test)
dialogue_voice_is_bounded_and_finishes :: proc(t: ^testing.T) {
    voice := engine_sound.Dialogue_Voice {
        duration   = .06,
        frequency  = 390,
        brightness = .7,
        warmth     = .4,
        gain       = .11,
    }
    samples: [engine_sound.SAMPLE_RATE / 5]f32
    engine_sound.render_dialogue_voice_add(&voice, samples[:])
    peak := f32(0)
    audible := false
    for sample in samples {
        magnitude := abs(sample)
        peak = max(peak, magnitude)
        if magnitude > .0001 do audible = true
    }
    testing.expect(t, audible)
    testing.expect(t, peak <= .24)
    testing.expect(t, voice.duration == 0)
}

@(test)
dialogue_voice_render_is_deterministic :: proc(t: ^testing.T) {
    a := engine_sound.Dialogue_Voice {
        duration   = .052,
        frequency  = 335,
        brightness = .62,
        warmth     = .68,
        gain       = .105,
    }
    b := a
    samples_a, samples_b: [512]f32
    engine_sound.render_dialogue_voice_add(&a, samples_a[:])
    engine_sound.render_dialogue_voice_add(&b, samples_b[:])
    testing.expect(t, samples_a == samples_b)
    testing.expect(t, a == b)
}
