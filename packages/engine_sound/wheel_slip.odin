package engine_sound

import "core:math"

Slip_Controls :: struct {
    amount:  f32,
    speed:   f32,
    wetness: f32,
    surface: Footstep_Surface,
    active:  bool,
}

Slip_Synth :: struct {
    amount, speed, wetness, hardness, looseness, level: f32,
    stick_depth:                                        f32,
    noise_state:                                        u32,
    noise_low:                                          f32,
    wet_low:                                            f32,
    wander_low:                                         f32,
    squeal_phase:                                       f32,
    squeal_phase_secondary:                             f32,
    stick_phase:                                        f32,
    aggregate_timer:                                    f32,
    aggregate_phase:                                    f32,
    aggregate_hz:                                       f32,
    aggregate_level:                                    f32,
    aggregate_count:                                    u32,
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
    target_speed := controls.active ? clamp(controls.speed, 0, 1) : f32(0)
    target_wetness := controls.active ? clamp(controls.wetness, 0, 1) : f32(0)
    target_hardness, target_looseness := f32(0), f32(0)
    if controls.active {
        switch controls.surface {
        case .Grass:
            target_hardness, target_looseness = .05, .36
        case .Dirt:
            target_hardness, target_looseness = .15, .66
        case .Sand:
            target_hardness, target_looseness = .03, .84
        case .Gravel:
            target_hardness, target_looseness = .25, .96
        case .Cobblestone:
            target_hardness, target_looseness = .82, .20
        case .Asphalt:
            target_hardness, target_looseness = .96, .03
        }
    }
    seconds_per_sample := f32(1.0 / SAMPLE_RATE)

    for &sample in samples {
        synth.amount = approach(synth.amount, target_amount, 22, seconds_per_sample)
        synth.speed = approach(synth.speed, target_speed, 14, seconds_per_sample)
        synth.hardness = approach(synth.hardness, target_hardness, 11, seconds_per_sample)
        synth.looseness = approach(synth.looseness, target_looseness, 11, seconds_per_sample)
        wetness_rate := target_wetness > synth.wetness ? f32(2.8) : f32(.14)
        synth.wetness = approach(synth.wetness, target_wetness, wetness_rate, seconds_per_sample)
        synth.level = approach(synth.level, target_level, target_level > 0 ? f32(18) : f32(28), seconds_per_sample)
        target_stick_depth :=
            target_amount * target_speed * target_hardness * (1 - target_wetness * .72) * (1 - target_looseness * .84)
        synth.stick_depth = approach(synth.stick_depth, target_stick_depth, 13, seconds_per_sample)

        rough := noise(&synth.noise_state)
        synth.noise_low += (rough - synth.noise_low) * (.035 + synth.speed * .055)
        synth.wet_low += (rough - synth.wet_low) * (.13 + synth.speed * .08)
        scrub := rough - synth.noise_low
        synth.wander_low += (rough - synth.wander_low) * .0007

        // Separate phases keep the detuned mode continuous when the primary
        // oscillator wraps. Slow noise wander prevents a sterile fixed tone.
        squeal_hz :=
            (520 + synth.speed * 980 + synth.amount * 210 + synth.wander_low * 34) *
            (1 - synth.wetness * .18) *
            (1 - synth.looseness * .12)
        synth.squeal_phase += squeal_hz * seconds_per_sample
        synth.squeal_phase_secondary += squeal_hz * 1.037 * seconds_per_sample
        synth.squeal_phase -= math.floor(synth.squeal_phase)
        synth.squeal_phase_secondary -= math.floor(synth.squeal_phase_secondary)
        squeal := math.sin(synth.squeal_phase * TAU) * .72 + math.sin(synth.squeal_phase_secondary * TAU) * .28
        // Dry rubber repeatedly grips and releases hard pavement instead of
        // sustaining a perfectly stationary tone. The asymmetric modulation
        // is strongest under heavy asphalt slip; water and loose aggregate
        // turn it back into broadband scrub.
        stick_hz := 18 + synth.speed * 34 + synth.amount * 13 + synth.wander_low * 2
        synth.stick_phase += stick_hz * seconds_per_sample
        synth.stick_phase -= math.floor(synth.stick_phase)
        stick_cycle := max(math.sin(synth.stick_phase * TAU), f32(-.48))
        stick_gain := 1 - synth.stick_depth * .34 + (stick_cycle + .48) / 1.48 * synth.stick_depth * .52
        squeal_mix := clamp((synth.amount - .34) / .5, 0, 1) * synth.speed
        gain := synth.amount * synth.amount * synth.level
        wet_scrub := (rough - synth.wet_low) * synth.wetness * (.12 + synth.speed * .12)
        loose_scrub := (rough - synth.wet_low) * synth.looseness * (.09 + synth.speed * .13)
        // A spinning tire on loose ground throws individual stones in
        // addition to its continuous granular scrub. Each seeded event starts
        // a short zero-crossing pebble mode; pavement never crosses the loose
        // material gate, and wet aggregate sheds less freely.
        aggregate_drive := synth.amount * synth.speed * synth.looseness * (1 - synth.wetness * .68)
        if aggregate_drive > .08 {
            synth.aggregate_timer -= seconds_per_sample
            if synth.aggregate_timer <= 0 {
                pitch_variation := (noise(&synth.noise_state) + 1) * .5
                strength_variation := (noise(&synth.noise_state) + 1) * .5
                interval_variation := (noise(&synth.noise_state) + 1) * .5
                synth.aggregate_phase = 0
                synth.aggregate_hz = 240 + synth.hardness * 720 + pitch_variation * (260 + synth.looseness * 240)
                synth.aggregate_level = (.045 + strength_variation * .075) * aggregate_drive
                event_rate := 3 + aggregate_drive * 31
                synth.aggregate_timer = (.58 + interval_variation * .84) / event_rate
                synth.aggregate_count += 1
            }
        }
        synth.aggregate_phase += synth.aggregate_hz * seconds_per_sample
        synth.aggregate_phase -= math.floor(synth.aggregate_phase)
        synth.aggregate_level *= f32(math.exp(f64(-185 * seconds_per_sample)))
        aggregate_ping := math.sin(synth.aggregate_phase * TAU) * synth.aggregate_level
        dry_squeal_mix := 1 - synth.wetness * .42
        hard_squeal_mix := .12 + synth.hardness * .88
        tire :=
            (scrub * (.15 + synth.speed * .13) +
                loose_scrub +
                aggregate_ping * .42 +
                wet_scrub +
                squeal * stick_gain * squeal_mix * .17 * dry_squeal_mix * hard_squeal_mix) *
            gain
        sample += tire
    }
}
