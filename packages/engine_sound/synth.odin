package engine_sound

import "core:math"

SAMPLE_RATE :: 48_000
TAU :: f32(math.PI * 2)

// Controls deliberately separate rotational rate from delivered power. A
// free-revving engine can therefore sound fast and light, while a climbing or
// accelerating engine can sound slower but heavily loaded.
Controls :: struct {
    rate:               f32,
    power:              f32,
    propeller_mix:      f32,
    propeller_airspeed: f32,
    rotor_mix:          f32,
    rotor_rate_a:       f32,
    rotor_rate_b:       f32,
    rotor_rate_c:       f32,
    reverse_mix:        f32,
    transmission_mix:   f32,
    damage:             f32,
    gear:               int,
    shift:              bool,
    active:             bool,
}

Synth :: struct {
    rate,
    power,
    propeller_mix,
    propeller_airspeed,
    rotor_mix,
    rotor_loading,
    reverse_mix,
    transmission_mix,
    damage,
    level: f32,
    gear_position:                                                                                                          f32,
    crank_phase:                                                                                                            f32,
    firing_phase:                                                                                                           f32,
    propeller_phase:                                                                                                        f32,
    propeller_tip_phase:                                                                                                    f32,
    rotor_phase_a:                                                                                                          f32,
    rotor_phase_b:                                                                                                          f32,
    rotor_phase_c:                                                                                                          f32,
    rotor_rate_a:                                                                                                           f32,
    rotor_rate_b:                                                                                                           f32,
    rotor_rate_c:                                                                                                           f32,
    reverse_phase:                                                                                                          f32,
    transmission_phase:                                                                                                     f32,
    turbine_phase:                                                                                                          f32,
    starter_phase:                                                                                                          f32,
    noise_state:                                                                                                            u32,
    low_pass:                                                                                                               f32,
    combustion_body:                                                                                                        f32,
    combustion_velocity:                                                                                                    f32,
    shift_envelope:                                                                                                         f32,
    starter_envelope:                                                                                                       f32,
    starter_age:                                                                                                            f32,
    shutdown_envelope:                                                                                                      f32,
    shutdown_phase:                                                                                                         f32,
    last_target_power:                                                                                                      f32,
    throttle_envelope:                                                                                                      f32,
    overrun_envelope:                                                                                                       f32,
    overrun_level:                                                                                                          f32,
    overrun_phase:                                                                                                          f32,
    coast_mix:                                                                                                              f32,
    coast_phase:                                                                                                            f32,
    damage_low:                                                                                                             f32,
    damage_phase:                                                                                                           f32,
    misfire_envelope:                                                                                                       f32,
    knock_age_a:                                                                                                            f32,
    knock_age_b:                                                                                                            f32,
    knock_hz_a:                                                                                                             f32,
    knock_hz_b:                                                                                                             f32,
    knock_level_a:                                                                                                          f32,
    knock_level_b:                                                                                                          f32,
    knock_next:                                                                                                             u8,
    knock_count:                                                                                                            u32,
    was_active:                                                                                                             bool,
}

new :: proc(seed := u32(0x6d2b79f5)) -> Synth {
    return {noise_state = seed, rotor_phase_b = .31, rotor_phase_c = .67}
}

approach :: proc(current, target, rate, seconds: f32) -> f32 {
    amount := clamp(rate * seconds, 0, 1)
    return current + (target - current) * amount
}

noise :: proc(state: ^u32) -> f32 {
    state^ = state^ * 1_664_525 + 1_013_904_223
    return f32(i32(state^ >> 9) - 4_194_304) / 4_194_304
}

Car_Gearbox :: struct {
    gear:    int,
    shifted: bool,
}

car_rate_for_gear :: proc(speed_normalized: f32, gear: int) -> f32 {
    speed := clamp(speed_normalized, 0, 1)
    switch clamp(gear, 0, 3) {
    case 0:
        return .16 + clamp(speed / .20, 0, 1) * .76
    case 1:
        return .38 + clamp((speed - .20) / .25, 0, 1) * .54
    case 2:
        return .40 + clamp((speed - .45) / .27, 0, 1) * .52
    case:
        return .43 + clamp((speed - .72) / .28, 0, 1) * .52
    }
}

// Stateful audio-only gear selection uses separate up/down thresholds so
// driveline jitter around a boundary cannot chatter between two RPM targets.
car_rate_step :: proc(gearbox: ^Car_Gearbox, speed_normalized: f32, reverse: bool = false) -> f32 {
    if gearbox == nil do return car_rate_for_gear(speed_normalized, 0)
    speed := clamp(speed_normalized, 0, 1)
    gearbox.gear = clamp(gearbox.gear, 0, 3)
    previous_gear := gearbox.gear
    if reverse {
        gearbox.gear = 0
        gearbox.shifted = gearbox.gear != previous_gear
        return .18 + speed * .62
    }
    switch gearbox.gear {
    case 0:
        if speed >= .20 do gearbox.gear = 1
    case 1:
        if speed >= .45 {
            gearbox.gear = 2
        } else if speed < .15 {
            gearbox.gear = 0
        }
    case 2:
        if speed >= .72 {
            gearbox.gear = 3
        } else if speed < .37 {
            gearbox.gear = 1
        }
    case 3:
        if speed < .60 do gearbox.gear = 2
    }
    gearbox.shifted = gearbox.gear != previous_gear
    return car_rate_for_gear(speed, gearbox.gear)
}

// Stateless mapping remains useful for previews and tests.
car_rate_from_speed :: proc(speed_normalized: f32) -> f32 {
    speed := clamp(speed_normalized, 0, 1)
    gear := 0
    if speed >= .72 {
        gear = 3
    } else if speed >= .45 {
        gear = 2
    } else if speed >= .20 {
        gear = 1
    }
    return car_rate_for_gear(speed, gear)
}

trigger_shift :: proc(synth: ^Synth) {
    if synth == nil do return
    synth.shift_envelope = 1
    synth.combustion_velocity += 58 * synth.level * (1 - synth.rotor_mix)
}

trigger_start :: proc(synth: ^Synth) {
    if synth == nil do return
    synth.starter_envelope = 1
    synth.starter_age = 0
    synth.starter_phase = 0
    synth.shutdown_envelope = 0
}

trigger_stop :: proc(synth: ^Synth) {
    if synth == nil do return
    synth.starter_envelope = 0
    synth.shutdown_envelope = max(synth.level, f32(.35))
    synth.shutdown_phase = 0
    synth.combustion_velocity += 34 * synth.level * (1 - synth.rotor_mix)
}

// render writes mono floating-point PCM. The asymmetric firing pulse and its
// octave produce the mechanical cadence; power adds combustion body and
// broadband intake/exhaust texture without incorrectly raising the RPM.
render :: proc(synth: ^Synth, controls: Controls, samples: []f32) {
    if synth == nil || len(samples) == 0 do return
    was_running := synth.was_active
    if controls.active && !synth.was_active {
        trigger_start(synth)
    } else if !controls.active && synth.was_active {
        trigger_stop(synth)
    }
    synth.was_active = controls.active
    target_rate := controls.active ? clamp(controls.rate, 0, 1) : f32(0)
    target_power := controls.active ? clamp(controls.power, 0, 1) : f32(0)
    if was_running && controls.active {
        power_change := target_power - synth.last_target_power
        if power_change > .14 {
            synth.throttle_envelope = max(synth.throttle_envelope, clamp(power_change * 1.35, 0, 1))
        } else if power_change < -.18 {
            synth.overrun_envelope = max(synth.overrun_envelope, clamp(-power_change * 1.2, 0, 1))
        }
    }
    synth.last_target_power = target_power
    target_propeller_mix := clamp(controls.propeller_mix, 0, 1)
    target_propeller_airspeed := f32(0)
    if controls.active && controls.propeller_mix > 0 {
        target_propeller_airspeed = clamp(controls.propeller_airspeed, 0, 1)
    }
    target_rotor_mix := clamp(controls.rotor_mix, 0, 1)
    has_individual_rotor_rates := controls.rotor_rate_a > 0 || controls.rotor_rate_b > 0 || controls.rotor_rate_c > 0
    target_rotor_rate_a := has_individual_rotor_rates ? clamp(controls.rotor_rate_a, 0, 1) : target_rate
    target_rotor_rate_b := has_individual_rotor_rates ? clamp(controls.rotor_rate_b, 0, 1) : target_rate
    target_rotor_rate_c := has_individual_rotor_rates ? clamp(controls.rotor_rate_c, 0, 1) : target_rate
    target_rotor_loading := target_rotor_mix * clamp((target_power - .30) / .70, 0, 1) * (1 - target_rate * .28)
    target_reverse_mix := clamp(controls.reverse_mix, 0, 1)
    target_transmission_mix := clamp(controls.transmission_mix, 0, 1)
    target_gear_position := target_transmission_mix > 0 ? clamp(f32(controls.gear) / 3, 0, 1) : f32(0)
    target_damage := controls.active ? clamp(controls.damage, 0, 1) : f32(0)
    target_coast_mix := f32(0)
    if controls.active {
        target_coast_mix = clamp((target_rate - .28) / .55, 0, 1) * clamp((.42 - target_power) / .42, 0, 1)
    }
    target_level := controls.active ? f32(1) : f32(0)
    seconds_per_sample := f32(1.0 / SAMPLE_RATE)
    shift_decay := f32(math.exp(f64(-24 * seconds_per_sample)))
    starter_decay := f32(math.exp(f64(-4.8 * seconds_per_sample)))
    shutdown_decay := f32(math.exp(f64(-10.5 * seconds_per_sample)))
    throttle_decay := f32(math.exp(f64(-15 * seconds_per_sample)))
    overrun_decay := f32(math.exp(f64(-6.5 * seconds_per_sample)))
    overrun_pop_decay := f32(math.exp(f64(-92 * seconds_per_sample)))
    misfire_decay := f32(math.exp(f64(-5.5 * seconds_per_sample)))

    for &sample in samples {
        synth.rate = approach(synth.rate, target_rate, 9, seconds_per_sample)
        synth.power = approach(synth.power, target_power, 12, seconds_per_sample)
        synth.propeller_mix = approach(synth.propeller_mix, target_propeller_mix, 10, seconds_per_sample)
        synth.propeller_airspeed = approach(synth.propeller_airspeed, target_propeller_airspeed, 6, seconds_per_sample)
        synth.rotor_mix = approach(synth.rotor_mix, target_rotor_mix, 10, seconds_per_sample)
        synth.rotor_rate_a = approach(synth.rotor_rate_a, target_rotor_rate_a, 8, seconds_per_sample)
        synth.rotor_rate_b = approach(synth.rotor_rate_b, target_rotor_rate_b, 8, seconds_per_sample)
        synth.rotor_rate_c = approach(synth.rotor_rate_c, target_rotor_rate_c, 8, seconds_per_sample)
        synth.rotor_loading = approach(synth.rotor_loading, target_rotor_loading, 8, seconds_per_sample)
        synth.reverse_mix = approach(synth.reverse_mix, target_reverse_mix, 14, seconds_per_sample)
        synth.transmission_mix = approach(synth.transmission_mix, target_transmission_mix, 12, seconds_per_sample)
        synth.gear_position = approach(synth.gear_position, target_gear_position, 15, seconds_per_sample)
        synth.damage = approach(synth.damage, target_damage, 5, seconds_per_sample)
        synth.coast_mix = approach(
            synth.coast_mix,
            target_coast_mix,
            target_coast_mix > synth.coast_mix ? f32(8) : f32(12),
            seconds_per_sample,
        )
        synth.level = approach(synth.level, target_level, controls.active ? f32(7) : f32(12), seconds_per_sample)

        crank_hz := 18 + synth.rate * 92
        firing_hz := crank_hz * 2
        propeller_hz := 10 + synth.rate * 48
        propeller_tip_hz := 430 + synth.rate * 970 + synth.propeller_airspeed * 180
        reverse_hz := 210 + synth.rate * 440
        transmission_hz := 285 + synth.rate * 590 + synth.gear_position * 125
        turbine_hz := 160 + synth.rate * 720
        synth.crank_phase += crank_hz * seconds_per_sample
        synth.firing_phase += firing_hz * seconds_per_sample
        synth.propeller_phase += propeller_hz * seconds_per_sample
        synth.propeller_tip_phase += propeller_tip_hz * seconds_per_sample
        synth.rotor_phase_a += (7 + synth.rotor_rate_a * 22) * seconds_per_sample
        synth.rotor_phase_b += (7 + synth.rotor_rate_b * 22) * seconds_per_sample
        synth.rotor_phase_c += (7 + synth.rotor_rate_c * 22) * seconds_per_sample
        synth.reverse_phase += reverse_hz * seconds_per_sample
        synth.transmission_phase += transmission_hz * seconds_per_sample
        synth.turbine_phase += turbine_hz * seconds_per_sample
        starter_hz := 72 + synth.starter_age * 54
        synth.starter_phase += starter_hz * seconds_per_sample
        synth.shutdown_phase += (13 + synth.rate * 9) * seconds_per_sample
        synth.overrun_phase += (47 + synth.rate * 68) * seconds_per_sample
        synth.coast_phase += (235 + synth.rate * 410) * seconds_per_sample
        synth.damage_phase += (31 + synth.rate * 57) * seconds_per_sample
        crank_event := synth.crank_phase >= 1
        fired := synth.firing_phase >= 1
        synth.crank_phase -= math.floor(synth.crank_phase)
        synth.firing_phase -= math.floor(synth.firing_phase)
        synth.propeller_phase -= math.floor(synth.propeller_phase)
        synth.propeller_tip_phase -= math.floor(synth.propeller_tip_phase)
        synth.rotor_phase_a -= math.floor(synth.rotor_phase_a)
        synth.rotor_phase_b -= math.floor(synth.rotor_phase_b)
        synth.rotor_phase_c -= math.floor(synth.rotor_phase_c)
        synth.reverse_phase -= math.floor(synth.reverse_phase)
        synth.transmission_phase -= math.floor(synth.transmission_phase)
        synth.turbine_phase -= math.floor(synth.turbine_phase)
        synth.starter_phase -= math.floor(synth.starter_phase)
        synth.shutdown_phase -= math.floor(synth.shutdown_phase)
        synth.overrun_phase -= math.floor(synth.overrun_phase)
        synth.coast_phase -= math.floor(synth.coast_phase)
        synth.damage_phase -= math.floor(synth.damage_phase)

        crank := math.sin(synth.crank_phase * TAU)
        harmonic := math.sin(synth.firing_phase * TAU)
        pulse_sine := math.sin((synth.firing_phase * 2) * TAU)
        firing_pulse := max(harmonic, f32(-.28))
        rough := noise(&synth.noise_state)
        cutoff_follow := .035 + synth.rate * .12 + synth.power * .08
        synth.low_pass += (rough - synth.low_pass) * cutoff_follow
        synth.damage_low += (rough - synth.damage_low) * .015

        // Each firing event excites a damped engine-block mode. Small,
        // deterministic strength variation keeps repeated pressure pulses from
        // becoming a perfectly static buzz while preserving the requested RPM.
        if fired && synth.level > .001 {
            firing_variation := .88 + (noise(&synth.noise_state) + 1) * .06
            firing_strength := f32(1)
            if synth.damage > .001 && target_rotor_mix < .75 && noise(&synth.noise_state) < synth.damage * .52 {
                firing_strength = .12 + (1 - synth.damage) * .28
                synth.misfire_envelope = max(synth.misfire_envelope, .45 + synth.damage * .55)
            }
            synth.combustion_velocity +=
                (42 + synth.power * 78) * firing_variation * firing_strength * synth.level * (1 - synth.rotor_mix)
            if synth.overrun_envelope > .01 && synth.rotor_mix < .75 && noise(&synth.noise_state) > .18 {
                synth.overrun_level += (.28 + synth.rate * .24) * synth.overrun_envelope * (1 - synth.rotor_mix)
            }
        }

        // Severe piston-engine damage can open bearing clearances enough for
        // a load-sensitive knock once per crank revolution. Two alternating
        // zero-crossing modes allow consecutive strikes to overlap without
        // turning the failure into a fixed buzz.
        if crank_event &&
           synth.damage > .25 &&
           synth.power > .18 &&
           target_rotor_mix < .75 &&
           noise(&synth.noise_state) < .18 + synth.damage * .62 {
            knock_variation := (noise(&synth.noise_state) + 1) * .5
            knock_level :=
                clamp((synth.damage - .25) / .75, 0, 1) * (.14 + synth.power * .20) * (.82 + knock_variation * .36)
            knock_hz := 610 + synth.rate * 430 + knock_variation * 240
            if synth.knock_next == 0 {
                synth.knock_age_a = 0
                synth.knock_hz_a = knock_hz
                synth.knock_level_a = knock_level
                synth.knock_next = 1
            } else {
                synth.knock_age_b = 0
                synth.knock_hz_b = knock_hz * 1.027
                synth.knock_level_b = knock_level
                synth.knock_next = 0
            }
            synth.knock_count += 1
        }
        bearing_knock := f32(0)
        if synth.knock_level_a > .00001 {
            knock_decay_a := f32(math.exp(f64(-synth.knock_age_a * 205)))
            bearing_knock +=
                (math.sin(synth.knock_age_a * synth.knock_hz_a * TAU) * .78 +
                    math.sin(synth.knock_age_a * synth.knock_hz_a * TAU * 1.61) * .22) *
                synth.knock_level_a *
                knock_decay_a
            synth.knock_age_a += seconds_per_sample
            if knock_decay_a < .0001 do synth.knock_level_a = 0
        }
        if synth.knock_level_b > .00001 {
            knock_decay_b := f32(math.exp(f64(-synth.knock_age_b * 218)))
            bearing_knock +=
                (math.sin(synth.knock_age_b * synth.knock_hz_b * TAU) * .76 +
                    math.sin(synth.knock_age_b * synth.knock_hz_b * TAU * 1.57) * .24) *
                synth.knock_level_b *
                knock_decay_b
            synth.knock_age_b += seconds_per_sample
            if knock_decay_b < .0001 do synth.knock_level_b = 0
        }
        body_hz := 82 + synth.rate * 55
        body_angular := body_hz * TAU
        synth.combustion_velocity -= synth.combustion_body * body_angular * body_angular * seconds_per_sample
        synth.combustion_velocity *= f32(math.exp(f64(-105 * seconds_per_sample)))
        synth.combustion_body += synth.combustion_velocity * seconds_per_sample

        light_mechanical := crank * .18 + harmonic * .12 + pulse_sine * .04
        loaded_combustion := firing_pulse * .27 + synth.low_pass * .18 + synth.combustion_body * .62
        piston_signal := light_mechanical + loaded_combustion * synth.power
        intake := rough - synth.low_pass

        // Postale retains its piston core but adds a three-blade shaft cadence
        // and broadband prop wash, separating it from the road car.
        propeller_chop :=
            max(math.sin((synth.propeller_phase * 3) * TAU), f32(-.3)) * .78 +
            math.sin((synth.propeller_phase * 6) * TAU) * .22
        advance_ratio := clamp(synth.propeller_airspeed / max(.22 + synth.rate * .78, f32(.1)), 0, 1)
        blade_loading := synth.power * (1 - advance_ratio * .48)
        propeller_tip :=
            (math.sin(synth.propeller_tip_phase * TAU) * .72 + math.sin((synth.propeller_tip_phase * 2) * TAU) * .28) *
            synth.rate *
            synth.rate *
            synth.propeller_airspeed
        propeller_imbalance :=
            (math.sin(synth.propeller_phase * TAU) * .72 +
                max(math.sin((synth.propeller_phase * 3) * TAU), f32(-.35)) * .28) *
            synth.damage *
            (.035 + synth.rate * .045)
        propeller_signal :=
            piston_signal * .78 +
            propeller_chop * (.14 + blade_loading * .13) +
            math.sin(synth.propeller_phase * TAU) * .055 +
            intake * (.035 + synth.power * .055 + synth.propeller_airspeed * .045) +
            propeller_tip * .035 +
            propeller_imbalance
        piston_character := piston_signal * (1 - synth.propeller_mix) + propeller_signal * synth.propeller_mix
        reverse_whine := math.sin(synth.reverse_phase * TAU) * .72 + math.sin((synth.reverse_phase * 2) * TAU) * .28
        transmission_whine :=
            math.sin(synth.transmission_phase * TAU) * .74 +
            math.sin((synth.transmission_phase * 2) * TAU) * .19 +
            math.sin((synth.transmission_phase * 3) * TAU) * .07
        gear_gain := 1 - synth.gear_position * .42
        forward_transmission :=
            transmission_whine *
            synth.transmission_mix *
            (1 - synth.reverse_mix * .55) *
            gear_gain *
            (.026 + synth.power * .042)
        drive_character :=
            piston_character + forward_transmission + reverse_whine * synth.reverse_mix * (.075 + synth.power * .065)

        // The Libellula's powertrain replaces piston firing with turbine whine,
        // blade-pass pressure, and a load-sensitive intake wash.
        turbine :=
            (math.sin(synth.turbine_phase * TAU) * .68 +
                math.sin((synth.turbine_phase * 2) * TAU) * .20 +
                math.sin((synth.turbine_phase * 3) * TAU) * .12) *
            (1 + synth.damage * clamp(synth.damage_low * 5, -.18, .18))
        blade_a := max(math.sin((synth.rotor_phase_a * 3) * TAU), f32(-.32))
        blade_b := max(math.sin((synth.rotor_phase_b * 3) * TAU), f32(-.32))
        blade_c := max(math.sin((synth.rotor_phase_c * 3) * TAU), f32(-.32))
        rotor_beat :=
            1 +
            math.sin((synth.rotor_phase_a - synth.rotor_phase_b) * TAU) * .07 +
            math.sin((synth.rotor_phase_b - synth.rotor_phase_c) * TAU) * .05
        blade_pass := (blade_a * .38 + blade_b * .34 + blade_c * .28) * rotor_beat
        rotor_wobble :=
            (math.sin(synth.rotor_phase_a * TAU) * .42 +
                math.sin(synth.rotor_phase_b * TAU) * .33 +
                math.sin(synth.rotor_phase_c * TAU) * .25) *
            synth.damage
        rotor_clack :=
            (max(blade_a - .52, f32(0)) * .40 + max(blade_b - .52, f32(0)) * .34 + max(blade_c - .52, f32(0)) * .26) *
            synth.damage
        slap_a := max(blade_a - .36, f32(0))
        slap_b := max(blade_b - .36, f32(0))
        slap_c := max(blade_c - .36, f32(0))
        // High collective loading sharpens each blade passage into a vortex
        // slap. Squared pulse shoulders create broadband edge detail while
        // retaining the three independently simulated rotor cadences.
        rotor_slap :=
            (slap_a * slap_a * .40 + slap_b * slap_b * .34 + slap_c * slap_c * .26) *
            synth.rotor_loading *
            (.72 + intake * .28)
        rotor_signal :=
            turbine * (.16 + synth.power * .10) +
            blade_pass * (.17 + synth.power * .055) +
            intake * (.045 + synth.power * .055) +
            rotor_slap * .052 +
            rotor_wobble * (.026 + synth.rate * .025) +
            rotor_clack * .032
        signal := drive_character * (1 - synth.rotor_mix) + rotor_signal * synth.rotor_mix

        // Persistent crash damage destabilizes combustion or turbine pressure
        // while a loose mechanical layer follows shaft speed. It alters
        // timbre without inventing a separate RPM from the simulation.
        damage_rattle :=
            ((rough - synth.damage_low) * .055 + max(math.sin(synth.damage_phase * TAU), f32(-.3)) * .042) *
            synth.damage
        misfire_cough := max(-harmonic, f32(-.2)) * synth.misfire_envelope * (1 - synth.rotor_mix) * .075
        signal += damage_rattle + misfire_cough + bearing_knock

        // Rapid throttle opening produces a short intake bark in piston
        // vehicles and a smoother turbine surge in the rotorcraft.
        throttle_character :=
            (intake * .74 + synth.combustion_body * .26) * (1 - synth.rotor_mix) +
            (turbine * .46 + intake * .20) * synth.rotor_mix
        throttle_signal := throttle_character * synth.throttle_envelope * (.08 + synth.power * .08)

        // Lift-off excites sparse exhaust pops against a low engine-braking
        // pulse. Events remain tied to firing cadence rather than a separate
        // arbitrary clock.
        synth.overrun_level *= overrun_pop_decay
        overrun_wave := max(math.sin(synth.overrun_phase * TAU), f32(-.22)) * .58 + synth.overrun_level * .42
        overrun_signal := overrun_wave * synth.overrun_envelope * (1 - synth.rotor_mix) * (.045 + synth.rate * .045)

        // Sustained closed-throttle motion retains compression braking after
        // the short overrun pops have faded. Piston cadence drives the rasp,
        // the driveline adds a quiet speed-following whirr, and an airborne
        // propeller contributes windmilling pressure according to airspeed.
        coast_compression := max(-harmonic, f32(-.24)) * .68 + math.sin(synth.coast_phase * TAU) * .22 + intake * .10
        propeller_windmill :=
            max(math.sin((synth.propeller_phase * 3) * TAU), f32(-.28)) *
            synth.propeller_mix *
            synth.propeller_airspeed *
            .32
        coast_signal :=
            (coast_compression + propeller_windmill) *
            synth.coast_mix *
            (1 - synth.rotor_mix) *
            (.026 + synth.rate * .028)

        // Activation spins up from a brushed starter whine into uneven catch
        // pulses. Rotorcraft lean toward turbine spool while piston vehicles
        // retain the lower cranking cadence.
        starter_motor :=
            math.sin(synth.starter_phase * TAU) * .62 + math.sin((synth.starter_phase * 2) * TAU) * .23 + rough * .15
        starter_gate := .35 + .65 * max(math.sin(synth.starter_age * TAU * 7.5), f32(-.2))
        starter_click := f32(math.exp(f64(-58 * synth.starter_age)))
        starter_character :=
            starter_motor * starter_gate * (1 - synth.rotor_mix * .42) +
            turbine * synth.rotor_mix * .38 +
            starter_click * (.5 + rough * .18)
        starter_signal := starter_character * synth.starter_envelope * .16

        // Deactivation leaves a rapidly slowing, asymmetric shudder instead of
        // collapsing directly to silence.
        shutdown_wave :=
            math.sin(synth.shutdown_phase * TAU) * .64 +
            max(math.sin((synth.shutdown_phase * 2) * TAU), f32(-.25)) * .36
        shutdown_signal := shutdown_wave * synth.shutdown_envelope * .13

        // A short torque cut exposes the resonant driveline thump triggered by
        // the gearbox without discontinuously muting the engine.
        torque_cut := 1 - synth.shift_envelope * .28
        amplitude := (.16 + synth.power * .28) * synth.level * torque_cut
        sample = clamp(
            signal * amplitude + throttle_signal + overrun_signal + coast_signal + starter_signal + shutdown_signal,
            -.92,
            .92,
        )
        synth.shift_envelope *= shift_decay
        synth.throttle_envelope *= throttle_decay
        synth.overrun_envelope *= overrun_decay
        synth.misfire_envelope *= misfire_decay
        if synth.throttle_envelope < .00001 do synth.throttle_envelope = 0
        if synth.overrun_envelope < .00001 {
            synth.overrun_envelope = 0
            synth.overrun_level = 0
        }
        if synth.misfire_envelope < .00001 do synth.misfire_envelope = 0
        synth.starter_envelope *= starter_decay
        if synth.starter_envelope < .00001 {
            synth.starter_envelope = 0
        } else {
            synth.starter_age = min(synth.starter_age + seconds_per_sample, f32(2))
        }
        synth.shutdown_envelope *= shutdown_decay
        if synth.shutdown_envelope < .00001 do synth.shutdown_envelope = 0
    }
}
