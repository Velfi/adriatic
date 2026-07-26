package engine_sound

import "core:math"

Slip_Controls :: struct {
    amount: f32,
    speed:  f32,
    active: bool,
}

Slip_Synth :: struct {
    amount, level: f32,
    noise_state:   u32,
    noise_low:     f32,
    squeal_phase:  f32,
}

new_slip :: proc(seed := u32(0x9e3779b9)) -> Slip_Synth {
    return {noise_state = seed}
}

// render_slip_add mixes tire scrub into an existing mono buffer. Broad,
// high-passed noise supplies road texture while two close squeal components
// emerge only during substantial, higher-speed slip.
render_slip_add :: proc(synth: ^Slip_Synth, controls: Slip_Controls, samples: []f32) {
    if synth == nil || len(samples) == 0 do return
    target_amount := controls.active ? clamp(controls.amount, 0, 1) : f32(0)
    target_level := controls.active && controls.speed > .5 ? f32(1) : f32(0)
    speed := clamp(controls.speed, 0, 1)
    seconds_per_sample := f32(1.0 / SAMPLE_RATE)

    for &sample in samples {
        synth.amount = approach(synth.amount, target_amount, 22, seconds_per_sample)
        synth.level = approach(synth.level, target_level, target_level > 0 ? f32(18) : f32(28), seconds_per_sample)

        rough := noise(&synth.noise_state)
        synth.noise_low += (rough - synth.noise_low) * (.035 + speed * .055)
        scrub := rough - synth.noise_low

        squeal_hz := 520 + speed * 980 + synth.amount * 210
        synth.squeal_phase += squeal_hz * seconds_per_sample
        synth.squeal_phase -= math.floor(synth.squeal_phase)
        squeal :=
            math.sin(synth.squeal_phase * TAU) * .72 +
            math.sin(synth.squeal_phase * TAU * 1.037) * .28
        squeal_mix := clamp((synth.amount - .34) / .5, 0, 1) * speed
        gain := synth.amount * synth.amount * synth.level
        tire := (scrub * (.18 + speed * .16) + squeal * squeal_mix * .16) * gain
        sample = clamp(sample + tire, -.92, .92)
    }
}
