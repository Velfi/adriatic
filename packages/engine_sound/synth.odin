package engine_sound

import "core:math"

SAMPLE_RATE :: 48_000
TAU :: f32(math.PI * 2)

// Controls deliberately separate rotational rate from delivered power. A
// free-revving engine can therefore sound fast and light, while a climbing or
// accelerating engine can sound slower but heavily loaded.
Controls :: struct {
    rate:   f32,
    power:  f32,
    active: bool,
}

Synth :: struct {
    rate, power, level: f32,
    crank_phase:        f32,
    firing_phase:       f32,
    noise_state:        u32,
    low_pass:           f32,
}

new :: proc(seed := u32(0x6d2b79f5)) -> Synth {
    return {noise_state = seed}
}

approach :: proc(current, target, rate, seconds: f32) -> f32 {
    amount := clamp(rate * seconds, 0, 1)
    return current + (target - current) * amount
}

noise :: proc(state: ^u32) -> f32 {
    state^ = state^ * 1_664_525 + 1_013_904_223
    return f32(i32(state^ >> 9) - 4_194_304) / 4_194_304
}

// render writes mono floating-point PCM. The asymmetric firing pulse and its
// octave produce the mechanical cadence; power adds combustion body and
// broadband intake/exhaust texture without incorrectly raising the RPM.
render :: proc(synth: ^Synth, controls: Controls, samples: []f32) {
    if synth == nil || len(samples) == 0 do return
    target_rate := controls.active ? clamp(controls.rate, 0, 1) : f32(0)
    target_power := controls.active ? clamp(controls.power, 0, 1) : f32(0)
    target_level := controls.active ? f32(1) : f32(0)
    seconds_per_sample := f32(1.0 / SAMPLE_RATE)

    for &sample in samples {
        synth.rate = approach(synth.rate, target_rate, 9, seconds_per_sample)
        synth.power = approach(synth.power, target_power, 12, seconds_per_sample)
        synth.level = approach(synth.level, target_level, controls.active ? f32(7) : f32(12), seconds_per_sample)

        crank_hz := 18 + synth.rate * 92
        firing_hz := crank_hz * 2
        synth.crank_phase += crank_hz * seconds_per_sample
        synth.firing_phase += firing_hz * seconds_per_sample
        synth.crank_phase -= math.floor(synth.crank_phase)
        synth.firing_phase -= math.floor(synth.firing_phase)

        crank := math.sin(synth.crank_phase * TAU)
        harmonic := math.sin(synth.firing_phase * TAU)
        pulse_sine := math.sin((synth.firing_phase * 2) * TAU)
        firing_pulse := max(harmonic, f32(-.28))
        rough := noise(&synth.noise_state)
        cutoff_follow := .035 + synth.rate * .12 + synth.power * .08
        synth.low_pass += (rough - synth.low_pass) * cutoff_follow

        light_mechanical := crank * .18 + harmonic * .12 + pulse_sine * .04
        loaded_combustion := firing_pulse * .32 + synth.low_pass * .20
        amplitude := (.16 + synth.power * .28) * synth.level
        sample = clamp((light_mechanical + loaded_combustion * synth.power) * amplitude, -.92, .92)
    }
}
