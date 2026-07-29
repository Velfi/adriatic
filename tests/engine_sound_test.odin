package tests

import engine_sound "../packages/engine_sound"
import "core:math"
import "core:testing"

@(test)
engine_sound_rate_changes_zero_crossing_density :: proc(t: ^testing.T) {
    slow, fast := engine_sound.new(1), engine_sound.new(1)
    slow_samples, fast_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render(&slow, {rate = .1, power = .5, active = true}, slow_samples[:])
    engine_sound.render(&fast, {rate = .9, power = .5, active = true}, fast_samples[:])

    slow_crossings, fast_crossings := 0, 0
    for index in 1 ..< len(slow_samples) {
        if slow_samples[index - 1] <= 0 && slow_samples[index] > 0 do slow_crossings += 1
        if fast_samples[index - 1] <= 0 && fast_samples[index] > 0 do fast_crossings += 1
    }
    testing.expect(t, fast.rate > slow.rate)
    testing.expect(t, fast_crossings > slow_crossings)
}

@(test)
engine_sound_power_changes_energy_without_changing_rate :: proc(t: ^testing.T) {
    light, loaded := engine_sound.new(9), engine_sound.new(9)
    light_samples, loaded_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render(&light, {rate = .55, power = .05, active = true}, light_samples[:])
    engine_sound.render(&loaded, {rate = .55, power = 1, active = true}, loaded_samples[:])

    light_energy, loaded_energy := f64(0), f64(0)
    for index in 0 ..< len(light_samples) {
        light_energy += f64(light_samples[index] * light_samples[index])
        loaded_energy += f64(loaded_samples[index] * loaded_samples[index])
        testing.expect(t, math.abs(light_samples[index]) <= .92)
        testing.expect(t, math.abs(loaded_samples[index]) <= .92)
    }
    testing.expect(t, loaded_energy > light_energy * 2)
}

@(test)
engine_sound_firing_excites_combustion_resonator :: proc(t: ^testing.T) {
    synth := engine_sound.new(13)
    samples: [engine_sound.SAMPLE_RATE / 4]f32
    engine_sound.render(&synth, {rate = .58, power = .9, active = true}, samples[:])
    resonator_motion := math.abs(synth.combustion_body) + math.abs(synth.combustion_velocity)
    high_resonator_motion := math.abs(synth.combustion_body_high) + math.abs(synth.combustion_velocity_high)
    testing.expect(t, resonator_motion > .001)
    testing.expect(t, high_resonator_motion > .001)
}

@(test)
engine_rotation_has_seeded_subtle_timing_wander :: proc(t: ^testing.T) {
    first, matching, different := engine_sound.new(14), engine_sound.new(14), engine_sound.new(15)
    first_samples, matching_samples, different_samples: [engine_sound.SAMPLE_RATE]f32
    controls := engine_sound.Controls {
        rate   = .12,
        power  = .18,
        active = true,
    }
    engine_sound.render(&first, controls, first_samples[:])
    engine_sound.render(&matching, controls, matching_samples[:])
    engine_sound.render(&different, controls, different_samples[:])

    testing.expect(t, first_samples == matching_samples)
    testing.expect(t, first.firing_phase == matching.firing_phase)
    testing.expect(t, first.firing_phase != different.firing_phase)
    testing.expect(t, abs(first.rpm_wander_low) < .2)
    phase_difference := abs(first.firing_phase - different.firing_phase)
    phase_difference = min(phase_difference, 1 - phase_difference)
    testing.expect(t, phase_difference > .000001)
    testing.expect(t, phase_difference < .05)
}

@(test)
engine_sound_vehicle_characters_are_distinct_and_smoothly_controlled :: proc(t: ^testing.T) {
    piston, propeller, rotor := engine_sound.new(17), engine_sound.new(17), engine_sound.new(17)
    piston_samples, propeller_samples, rotor_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render(&piston, {rate = .68, power = .72, active = true}, piston_samples[:])
    engine_sound.render(&propeller, {rate = .68, power = .72, propeller_mix = 1, active = true}, propeller_samples[:])
    engine_sound.render(&rotor, {rate = .68, power = .72, rotor_mix = 1, active = true}, rotor_samples[:])

    propeller_difference, rotor_difference := f64(0), f64(0)
    for index in 0 ..< len(piston_samples) {
        propeller_difference += math.abs(f64(piston_samples[index] - propeller_samples[index]))
        rotor_difference += math.abs(f64(piston_samples[index] - rotor_samples[index]))
        testing.expect(t, math.abs(propeller_samples[index]) <= .92)
        testing.expect(t, math.abs(rotor_samples[index]) <= .92)
    }
    testing.expect(t, propeller_difference > 10)
    testing.expect(t, rotor_difference > 10)
    testing.expect(t, propeller.propeller_mix > .99)
    testing.expect(t, rotor.rotor_mix > .99)

    sample: [1]f32
    engine_sound.render(&rotor, {rate = .68, power = .72, rotor_mix = 0, active = true}, sample[:])
    testing.expect(t, rotor.rotor_mix > 0 && rotor.rotor_mix < 1)
}

@(test)
tri_rotor_sound_uses_individual_rotor_rates :: proc(t: ^testing.T) {
    balanced, differential := engine_sound.new(73), engine_sound.new(73)
    balanced_samples, differential_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render(
        &balanced,
        {
            rate = .62,
            power = .76,
            rotor_mix = 1,
            rotor_rate_a = .62,
            rotor_rate_b = .62,
            rotor_rate_c = .62,
            active = true,
        },
        balanced_samples[:],
    )
    engine_sound.render(
        &differential,
        {
            rate = .62,
            power = .76,
            rotor_mix = 1,
            rotor_rate_a = .28,
            rotor_rate_b = .94,
            rotor_rate_c = .57,
            active = true,
        },
        differential_samples[:],
    )

    difference := f64(0)
    for index in 0 ..< len(balanced_samples) {
        difference += math.abs(f64(balanced_samples[index] - differential_samples[index]))
        testing.expect(t, math.abs(differential_samples[index]) <= .92)
    }
    testing.expect(t, difference > 5)
    testing.expect(t, differential.rotor_rate_a < differential.rotor_rate_c)
    testing.expect(t, differential.rotor_rate_c < differential.rotor_rate_b)
}

@(test)
tri_rotor_high_load_adds_vortex_blade_slap_at_matched_rpm :: proc(t: ^testing.T) {
    unloaded, loaded := engine_sound.new(75), engine_sound.new(75)
    unloaded_samples, loaded_samples: [engine_sound.SAMPLE_RATE / 2]f32
    unloaded_controls := engine_sound.Controls {
        rate         = .68,
        power        = .12,
        rotor_mix    = 1,
        rotor_rate_a = .52,
        rotor_rate_b = .78,
        rotor_rate_c = .63,
        active       = true,
    }
    loaded_controls := unloaded_controls
    loaded_controls.power = 1
    engine_sound.render(&unloaded, unloaded_controls, unloaded_samples[:])
    engine_sound.render(&loaded, loaded_controls, loaded_samples[:])

    testing.expect(t, unloaded.rotor_loading < .001)
    testing.expect(t, loaded.rotor_loading > .7)
    difference := f64(0)
    unloaded_detail, loaded_detail := f64(0), f64(0)
    for index in 1 ..< len(unloaded_samples) {
        difference += math.abs(f64(loaded_samples[index] - unloaded_samples[index]))
        unloaded_delta := unloaded_samples[index] - unloaded_samples[index - 1]
        loaded_delta := loaded_samples[index] - loaded_samples[index - 1]
        unloaded_detail += f64(unloaded_delta * unloaded_delta)
        loaded_detail += f64(loaded_delta * loaded_delta)
        testing.expect(t, math.abs(loaded_samples[index]) <= .92)
    }
    testing.expect(t, difference > 10)
    testing.expect(t, loaded_detail > unloaded_detail)
}

@(test)
tri_rotor_sound_is_deterministic_across_callback_chunks :: proc(t: ^testing.T) {
    whole, chunked := engine_sound.new(79), engine_sound.new(79)
    whole_samples, chunked_samples: [4096]f32
    controls := engine_sound.Controls {
        rate         = .68,
        power        = .81,
        rotor_mix    = 1,
        rotor_rate_a = .35,
        rotor_rate_b = .88,
        rotor_rate_c = .61,
        active       = true,
    }
    engine_sound.render(&whole, controls, whole_samples[:])
    for offset := 0; offset < len(chunked_samples); offset += 227 {
        count := min(227, len(chunked_samples) - offset)
        engine_sound.render(&chunked, controls, chunked_samples[offset:offset + count])
    }
    testing.expect(t, whole_samples == chunked_samples)
}

@(test)
propeller_sound_distinguishes_static_loading_from_fast_cruise :: proc(t: ^testing.T) {
    static, cruise := engine_sound.new(83), engine_sound.new(83)
    static_samples, cruise_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render(
        &static,
        {rate = .82, power = .85, propeller_mix = 1, propeller_airspeed = 0, active = true},
        static_samples[:],
    )
    engine_sound.render(
        &cruise,
        {rate = .82, power = .85, propeller_mix = 1, propeller_airspeed = 1, active = true},
        cruise_samples[:],
    )

    difference, static_detail, cruise_detail := f64(0), f64(0), f64(0)
    for index in 1 ..< len(static_samples) {
        difference += math.abs(f64(static_samples[index] - cruise_samples[index]))
        static_delta := static_samples[index] - static_samples[index - 1]
        cruise_delta := cruise_samples[index] - cruise_samples[index - 1]
        static_detail += f64(static_delta * static_delta)
        cruise_detail += f64(cruise_delta * cruise_delta)
        testing.expect(t, math.abs(cruise_samples[index]) <= .92)
    }
    testing.expect(t, difference > 5)
    testing.expect(t, cruise_detail > static_detail)
    testing.expect(t, cruise.propeller_airspeed > .9)
}

@(test)
propeller_airspeed_sound_is_deterministic_across_callback_chunks :: proc(t: ^testing.T) {
    whole, chunked := engine_sound.new(89), engine_sound.new(89)
    whole_samples, chunked_samples: [4096]f32
    controls := engine_sound.Controls {
        rate               = .74,
        power              = .78,
        propeller_mix      = 1,
        propeller_airspeed = .66,
        active             = true,
    }
    engine_sound.render(&whole, controls, whole_samples[:])
    for offset := 0; offset < len(chunked_samples); offset += 233 {
        count := min(233, len(chunked_samples) - offset)
        engine_sound.render(&chunked, controls, chunked_samples[offset:offset + count])
    }
    testing.expect(t, whole_samples == chunked_samples)
}

@(test)
car_engine_rate_has_rising_gears_and_smoothed_shift_drops :: proc(t: ^testing.T) {
    first_gear_top := engine_sound.car_rate_from_speed(.199)
    second_gear_bottom := engine_sound.car_rate_from_speed(.20)
    second_gear_top := engine_sound.car_rate_from_speed(.449)
    third_gear_bottom := engine_sound.car_rate_from_speed(.45)
    testing.expect(t, first_gear_top > second_gear_bottom)
    testing.expect(t, second_gear_top > third_gear_bottom)
    testing.expect(t, engine_sound.car_rate_from_speed(0) >= 0)
    testing.expect(t, engine_sound.car_rate_from_speed(1) <= 1)

    synth := engine_sound.new(21)
    warmup: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render(&synth, {rate = first_gear_top, power = .8, active = true}, warmup[:])
    previous_rate := synth.rate
    sample: [1]f32
    engine_sound.render(&synth, {rate = second_gear_bottom, power = .8, active = true}, sample[:])
    testing.expect(t, synth.rate < previous_rate)
    testing.expect(t, synth.rate > second_gear_bottom)
}

@(test)
car_audio_gearbox_uses_hysteresis_at_shift_boundaries :: proc(t: ^testing.T) {
    gearbox: engine_sound.Car_Gearbox
    _ = engine_sound.car_rate_step(&gearbox, .20)
    testing.expect(t, gearbox.gear == 1)
    testing.expect(t, gearbox.shifted)

    // Small speed movement around the upshift boundary stays in second.
    _ = engine_sound.car_rate_step(&gearbox, .19)
    testing.expect(t, gearbox.gear == 1)
    testing.expect(t, !gearbox.shifted)
    _ = engine_sound.car_rate_step(&gearbox, .16)
    testing.expect(t, gearbox.gear == 1)

    // A deliberate drop below the separate downshift threshold selects first.
    _ = engine_sound.car_rate_step(&gearbox, .14)
    testing.expect(t, gearbox.gear == 0)
    testing.expect(t, gearbox.shifted)
}

@(test)
car_reverse_holds_first_gear_and_adds_distinct_whine :: proc(t: ^testing.T) {
    gearbox := engine_sound.Car_Gearbox {
        gear = 3,
    }
    reverse_rate := engine_sound.car_rate_step(&gearbox, .8, true)
    testing.expect(t, gearbox.gear == 0)
    testing.expect(t, gearbox.shifted)
    testing.expect(t, reverse_rate > .18 && reverse_rate < 1)

    forward, reverse := engine_sound.new(27), engine_sound.new(27)
    forward_samples, reverse_samples: [engine_sound.SAMPLE_RATE / 4]f32
    engine_sound.render(&forward, {rate = reverse_rate, power = .7, active = true}, forward_samples[:])
    engine_sound.render(
        &reverse,
        {rate = reverse_rate, power = .7, reverse_mix = 1, active = true},
        reverse_samples[:],
    )
    difference := f64(0)
    for index in 0 ..< len(forward_samples) {
        difference += math.abs(f64(forward_samples[index] - reverse_samples[index]))
        testing.expect(t, math.abs(reverse_samples[index]) <= .92)
    }
    testing.expect(t, difference > 5)
}

@(test)
car_gear_shift_transient_decays_and_stays_bounded :: proc(t: ^testing.T) {
    synth := engine_sound.new(25)
    samples: [engine_sound.SAMPLE_RATE / 4]f32
    controls := engine_sound.Controls {
        rate             = .7,
        power            = .8,
        transmission_mix = 1,
        active           = true,
    }
    engine_sound.render(&synth, controls, samples[:])
    engine_sound.trigger_shift(&synth)
    testing.expect(t, synth.shift_envelope == 1)
    testing.expect(t, synth.shift_reengage_count == 0)
    engine_sound.render(&synth, controls, samples[:])

    testing.expect(t, synth.shift_envelope < .01)
    testing.expect(t, synth.shift_reengage_count == 1)
    testing.expect(t, synth.shift_age > .052)
    testing.expect(t, synth.shift_reengage_level < .001)
    for sample in samples {
        testing.expect(t, math.abs(sample) <= .92)
    }
}

@(test)
car_forward_gears_have_distinct_transmission_character :: proc(t: ^testing.T) {
    first, fourth := engine_sound.new(91), engine_sound.new(91)
    first_samples, fourth_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render(
        &first,
        {rate = .68, power = .75, transmission_mix = 1, gear = 0, active = true},
        first_samples[:],
    )
    engine_sound.render(
        &fourth,
        {rate = .68, power = .75, transmission_mix = 1, gear = 3, active = true},
        fourth_samples[:],
    )

    difference := f64(0)
    for index in 0 ..< len(first_samples) {
        difference += math.abs(f64(first_samples[index] - fourth_samples[index]))
        testing.expect(t, math.abs(first_samples[index]) <= .92)
        testing.expect(t, math.abs(fourth_samples[index]) <= .92)
    }
    testing.expect(t, difference > 3)
    testing.expect(t, first.gear_position < .001)
    testing.expect(t, fourth.gear_position > .99)
}

@(test)
car_transmission_sound_is_deterministic_across_callback_chunks :: proc(t: ^testing.T) {
    whole, chunked := engine_sound.new(97), engine_sound.new(97)
    whole_samples, chunked_samples: [4096]f32
    controls := engine_sound.Controls {
        rate             = .64,
        power            = .71,
        transmission_mix = 1,
        gear             = 2,
        active           = true,
    }
    engine_sound.render(&whole, controls, whole_samples[:])
    for offset := 0; offset < len(chunked_samples); offset += 241 {
        count := min(241, len(chunked_samples) - offset)
        engine_sound.render(&chunked, controls, chunked_samples[offset:offset + count])
    }
    testing.expect(t, whole_samples == chunked_samples)
}

@(test)
engine_sound_render_is_deterministic_across_callback_chunks :: proc(t: ^testing.T) {
    whole, chunked := engine_sound.new(19), engine_sound.new(19)
    whole_samples, chunked_samples: [4096]f32
    controls := engine_sound.Controls {
        rate   = .63,
        power  = .74,
        active = true,
    }
    engine_sound.render(&whole, controls, whole_samples[:])
    for offset := 0; offset < len(chunked_samples); offset += 239 {
        count := min(239, len(chunked_samples) - offset)
        engine_sound.render(&chunked, controls, chunked_samples[offset:offset + count])
    }
    testing.expect(t, whole_samples == chunked_samples)
}

@(test)
engine_sound_start_and_shutdown_have_bounded_procedural_transients :: proc(t: ^testing.T) {
    synth := engine_sound.new(37)
    start_samples: [engine_sound.SAMPLE_RATE / 8]f32
    stop_samples: [engine_sound.SAMPLE_RATE / 8]f32
    controls := engine_sound.Controls {
        rate   = .58,
        power  = .62,
        active = true,
    }
    engine_sound.render(&synth, controls, start_samples[:])
    testing.expect(t, synth.starter_envelope > 0)
    testing.expect(t, synth.was_active)

    controls.active = false
    engine_sound.render(&synth, controls, stop_samples[:])
    testing.expect(t, synth.shutdown_envelope > 0)
    testing.expect(t, !synth.was_active)

    start_energy, stop_energy := f64(0), f64(0)
    for sample in start_samples {
        testing.expect(t, math.abs(sample) <= .92)
        start_energy += f64(sample * sample)
    }
    for sample in stop_samples {
        testing.expect(t, math.abs(sample) <= .92)
        stop_energy += f64(sample * sample)
    }
    testing.expect(t, start_energy > .1)
    testing.expect(t, stop_energy > .01)
}

@(test)
rapid_restart_uses_shorter_hot_catch_than_cold_start :: proc(t: ^testing.T) {
    cold, coasting := engine_sound.new(39), engine_sound.new(39)
    engine_sound.trigger_start(&cold)
    coasting.level = .88
    coasting.rate = .67
    coasting.shutdown_envelope = .6
    engine_sound.trigger_start(&coasting)

    testing.expect(t, cold.starter_envelope == 1)
    testing.expect(t, cold.starter_age == 0)
    testing.expect(t, coasting.starter_envelope < cold.starter_envelope)
    testing.expect(t, coasting.starter_envelope >= .22)
    testing.expect(t, coasting.starter_age > 0)
    testing.expect(t, coasting.shutdown_envelope == 0)
}

@(test)
engine_sound_lifecycle_transitions_do_not_retrigger_per_chunk :: proc(t: ^testing.T) {
    whole, chunked := engine_sound.new(41), engine_sound.new(41)
    whole_samples, chunked_samples: [4096]f32
    controls := engine_sound.Controls {
        rate   = .51,
        power  = .7,
        active = true,
    }
    engine_sound.render(&whole, controls, whole_samples[:])
    for offset := 0; offset < len(chunked_samples); offset += 173 {
        count := min(173, len(chunked_samples) - offset)
        engine_sound.render(&chunked, controls, chunked_samples[offset:offset + count])
    }
    testing.expect(t, whole_samples == chunked_samples)

    controls.active = false
    engine_sound.render(&whole, controls, whole_samples[:])
    for offset := 0; offset < len(chunked_samples); offset += 211 {
        count := min(211, len(chunked_samples) - offset)
        engine_sound.render(&chunked, controls, chunked_samples[offset:offset + count])
    }
    testing.expect(t, whole_samples == chunked_samples)
}

@(test)
device_mute_fades_without_retriggering_engine_lifecycle :: proc(t: ^testing.T) {
    synth := engine_sound.new(43)
    engine_samples: [4096]f32
    controls := engine_sound.Controls {
        rate   = .6,
        power  = .7,
        active = true,
    }
    engine_sound.render(&synth, controls, engine_samples[:])
    starter_before_mute := synth.starter_envelope
    testing.expect(t, synth.was_active)
    testing.expect(t, synth.shutdown_envelope == 0)

    mute_gain := f32(1)
    mute_samples: [engine_sound.BUFFER_SAMPLES]f32
    for _ in 0 ..< 20 {
        for &sample in mute_samples do sample = 1
        engine_sound.apply_device_mute(&mute_gain, mute_samples[:], true)
    }
    testing.expect(t, mute_gain < .001)
    testing.expect(t, mute_samples[0] > mute_samples[len(mute_samples) - 1])

    engine_sound.render(&synth, controls, engine_samples[:])
    testing.expect(t, synth.was_active)
    testing.expect(t, synth.shutdown_envelope == 0)
    testing.expect(t, synth.starter_envelope < starter_before_mute)

    previous_gain := mute_gain
    engine_sound.apply_device_mute(&mute_gain, mute_samples[:], false)
    testing.expect(t, mute_gain > previous_gain)
    testing.expect(t, mute_gain < 1)
}

@(test)
engine_sound_rapid_throttle_changes_trigger_load_transients_once :: proc(t: ^testing.T) {
    synth := engine_sound.new(67)
    warmup: [engine_sound.SAMPLE_RATE / 2]f32
    samples: [4096]f32
    controls := engine_sound.Controls {
        rate   = .68,
        power  = .2,
        active = true,
    }
    engine_sound.render(&synth, controls, warmup[:])
    testing.expect(t, synth.throttle_envelope == 0)

    controls.power = 1
    engine_sound.render(&synth, controls, samples[:])
    testing.expect(t, synth.throttle_envelope > 0)
    decayed_throttle := synth.throttle_envelope
    sample: [1]f32
    engine_sound.render(&synth, controls, sample[:])
    testing.expect(t, synth.throttle_envelope < decayed_throttle)

    controls.power = .08
    engine_sound.render(&synth, controls, samples[:])
    testing.expect(t, synth.overrun_envelope > 0)
    testing.expect(t, synth.overrun_level > 0)
    for value in samples {
        testing.expect(t, math.abs(value) <= .92)
    }
}

@(test)
engine_sound_small_power_adjustments_do_not_trigger_load_transients :: proc(t: ^testing.T) {
    synth := engine_sound.new(71)
    samples: [4096]f32
    controls := engine_sound.Controls {
        rate   = .6,
        power  = .5,
        active = true,
    }
    engine_sound.render(&synth, controls, samples[:])
    controls.power = .59
    engine_sound.render(&synth, controls, samples[:])
    testing.expect(t, synth.throttle_envelope == 0)
    testing.expect(t, synth.overrun_envelope == 0)
    controls.power = .43
    engine_sound.render(&synth, controls, samples[:])
    testing.expect(t, synth.throttle_envelope == 0)
    testing.expect(t, synth.overrun_envelope == 0)
}

@(test)
engine_sound_sustained_high_rate_coast_retains_compression_braking :: proc(t: ^testing.T) {
    coasting, loaded, slow := engine_sound.new(72), engine_sound.new(72), engine_sound.new(72)
    coast_samples, loaded_samples, slow_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render(&coasting, {rate = .9, power = .05, active = true}, coast_samples[:])
    engine_sound.render(&loaded, {rate = .9, power = .8, active = true}, loaded_samples[:])
    engine_sound.render(&slow, {rate = .2, power = .05, active = true}, slow_samples[:])

    testing.expect(t, coasting.coast_mix > .8)
    testing.expect(t, loaded.coast_mix < .001)
    testing.expect(t, slow.coast_mix < .001)
    testing.expect(t, coasting.overrun_envelope == 0)

    coast_loaded_difference, coast_slow_difference := f64(0), f64(0)
    for index in 0 ..< len(coast_samples) {
        coast_loaded_difference += math.abs(f64(coast_samples[index] - loaded_samples[index]))
        coast_slow_difference += math.abs(f64(coast_samples[index] - slow_samples[index]))
        testing.expect(t, math.abs(coast_samples[index]) <= .92)
    }
    testing.expect(t, coast_loaded_difference > 10)
    testing.expect(t, coast_slow_difference > 10)
}

@(test)
aircraft_damage_adds_misfires_and_mechanical_instability :: proc(t: ^testing.T) {
    healthy, damaged := engine_sound.new(101), engine_sound.new(101)
    healthy_samples, damaged_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render(&healthy, {rate = .72, power = .78, propeller_mix = 1, active = true}, healthy_samples[:])
    engine_sound.render(
        &damaged,
        {rate = .72, power = .78, propeller_mix = 1, damage = 1, active = true},
        damaged_samples[:],
    )

    difference := f64(0)
    for index in 0 ..< len(healthy_samples) {
        difference += math.abs(f64(healthy_samples[index] - damaged_samples[index]))
        testing.expect(t, math.abs(damaged_samples[index]) <= .92)
    }
    testing.expect(t, difference > 5)
    testing.expect(t, damaged.damage > .9)
    testing.expect(t, damaged.misfire_envelope > 0)
}

@(test)
damaged_loaded_piston_engine_adds_crank_synchronous_bearing_knock :: proc(t: ^testing.T) {
    healthy, unloaded, loaded := engine_sound.new(104), engine_sound.new(104), engine_sound.new(104)
    healthy_samples, unloaded_samples, loaded_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render(&healthy, {rate = .72, power = .82, damage = 0, active = true}, healthy_samples[:])
    engine_sound.render(&unloaded, {rate = .72, power = .05, damage = 1, active = true}, unloaded_samples[:])
    engine_sound.render(&loaded, {rate = .72, power = .82, damage = 1, active = true}, loaded_samples[:])

    testing.expect(t, healthy.knock_count == 0)
    testing.expect(t, unloaded.knock_count == 0)
    testing.expect(t, loaded.knock_count > 5)
    testing.expect(t, loaded.knock_hz_a >= 610 && loaded.knock_hz_a <= 1_280)
    testing.expect(t, loaded.knock_hz_b >= 610 && loaded.knock_hz_b <= 1_315)
    difference := f64(0)
    for index in 0 ..< len(loaded_samples) {
        difference += math.abs(f64(loaded_samples[index] - healthy_samples[index]))
        testing.expect(t, math.abs(loaded_samples[index]) <= .92)
    }
    testing.expect(t, difference > 5)
}

@(test)
damaged_bearing_knock_is_deterministic_across_callback_chunks :: proc(t: ^testing.T) {
    whole, chunked := engine_sound.new(105), engine_sound.new(105)
    whole_samples, chunked_samples: [4096]f32
    controls := engine_sound.Controls {
        rate   = .78,
        power  = .9,
        damage = 1,
        active = true,
    }
    engine_sound.render(&whole, controls, whole_samples[:])
    for offset := 0; offset < len(chunked_samples); offset += 229 {
        count := min(229, len(chunked_samples) - offset)
        engine_sound.render(&chunked, controls, chunked_samples[offset:offset + count])
    }

    testing.expect(t, whole.knock_count > 0)
    testing.expect(t, whole.knock_count == chunked.knock_count)
    testing.expect(t, whole_samples == chunked_samples)
}

@(test)
damaged_propeller_and_rotors_add_distinct_shaft_imbalance :: proc(t: ^testing.T) {
    prop_healthy, prop_damaged := engine_sound.new(102), engine_sound.new(102)
    rotor_healthy, rotor_damaged := engine_sound.new(102), engine_sound.new(102)
    prop_healthy_samples, prop_damaged_samples: [engine_sound.SAMPLE_RATE / 2]f32
    rotor_healthy_samples, rotor_damaged_samples: [engine_sound.SAMPLE_RATE / 2]f32
    prop_controls := engine_sound.Controls {
        rate               = .74,
        power              = .78,
        propeller_mix      = 1,
        propeller_airspeed = .55,
        active             = true,
    }
    rotor_controls := engine_sound.Controls {
        rate         = .68,
        power        = .76,
        rotor_mix    = 1,
        rotor_rate_a = .48,
        rotor_rate_b = .79,
        rotor_rate_c = .61,
        active       = true,
    }
    engine_sound.render(&prop_healthy, prop_controls, prop_healthy_samples[:])
    engine_sound.render(&rotor_healthy, rotor_controls, rotor_healthy_samples[:])
    prop_controls.damage = 1
    rotor_controls.damage = 1
    engine_sound.render(&prop_damaged, prop_controls, prop_damaged_samples[:])
    engine_sound.render(&rotor_damaged, rotor_controls, rotor_damaged_samples[:])

    prop_difference, rotor_difference := f64(0), f64(0)
    for index in 0 ..< len(prop_healthy_samples) {
        prop_difference += math.abs(f64(prop_damaged_samples[index] - prop_healthy_samples[index]))
        rotor_difference += math.abs(f64(rotor_damaged_samples[index] - rotor_healthy_samples[index]))
        testing.expect(t, math.abs(prop_damaged_samples[index]) <= .92)
        testing.expect(t, math.abs(rotor_damaged_samples[index]) <= .92)
    }
    testing.expect(t, prop_difference > 10)
    testing.expect(t, rotor_difference > 10)
    testing.expect(t, rotor_damaged.misfire_envelope == 0)
}

@(test)
damaged_rotor_sound_is_deterministic_across_callback_chunks :: proc(t: ^testing.T) {
    whole, chunked := engine_sound.new(103), engine_sound.new(103)
    whole_samples, chunked_samples: [4096]f32
    controls := engine_sound.Controls {
        rate         = .67,
        power        = .74,
        rotor_mix    = 1,
        rotor_rate_a = .42,
        rotor_rate_b = .83,
        rotor_rate_c = .59,
        damage       = .88,
        active       = true,
    }
    engine_sound.render(&whole, controls, whole_samples[:])
    for offset := 0; offset < len(chunked_samples); offset += 237 {
        count := min(237, len(chunked_samples) - offset)
        engine_sound.render(&chunked, controls, chunked_samples[offset:offset + count])
    }
    testing.expect(t, whole_samples == chunked_samples)
}

@(test)
engine_sound_master_limiter_is_smooth_bounded_and_monotonic :: proc(t: ^testing.T) {
    samples := [7]f32{-8, -1, -.1, 0, .1, 1, 8}
    engine_sound.limit_mix(samples[:])
    for index in 0 ..< len(samples) {
        testing.expect(t, math.abs(samples[index]) < engine_sound.MASTER_CEILING)
        if index > 0 do testing.expect(t, samples[index] > samples[index - 1])
    }
    testing.expect(t, samples[3] == 0)
}

@(test)
engine_sound_master_limiter_is_linear_below_soft_knee :: proc(t: ^testing.T) {
    samples := [7]f32{-.68, -.4, -.01, 0, .01, .4, .68}
    original := samples
    engine_sound.limit_mix(samples[:])
    testing.expect(t, samples == original)

    below := engine_sound.limit_sample(engine_sound.MASTER_KNEE - .0001)
    at := engine_sound.limit_sample(engine_sound.MASTER_KNEE)
    above := engine_sound.limit_sample(engine_sound.MASTER_KNEE + .0001)
    testing.expect(t, below < at && at < above)
    testing.expect(t, math.abs(f64((at - below) - (above - at))) < .00001)
}

@(test)
engine_sound_master_limiter_soft_knee_preserves_peak_order :: proc(t: ^testing.T) {
    inputs := [6]f32{.68, .72, .8, 1, 2, 8}
    outputs := inputs
    engine_sound.limit_mix(outputs[:])
    for index in 0 ..< len(outputs) {
        testing.expect(t, outputs[index] <= inputs[index])
        testing.expect(t, outputs[index] < engine_sound.MASTER_CEILING)
        if index > 0 do testing.expect(t, outputs[index] > outputs[index - 1])
    }
}

@(test)
engine_sound_master_limiter_contains_full_vehicle_mix :: proc(t: ^testing.T) {
    engine := engine_sound.new(47)
    slip := engine_sound.new_slip(48)
    roll := engine_sound.new_roll(49)
    crash := engine_sound.new_crash(50)
    samples: [engine_sound.SAMPLE_RATE / 4]f32
    engine_sound.render(&engine, {rate = 1, power = 1, active = true}, samples[:])
    engine_sound.render_slip_add(&slip, {amount = 1, speed = 1, active = true}, samples[:])
    engine_sound.render_roll_add(&roll, {speed = 1, roughness = 1, active = true}, samples[:])
    engine_sound.trigger_crash(&crash, 1)
    engine_sound.render_crash_add(&crash, samples[:])
    mix_state: engine_sound.Mix_State
    engine_sound.process_mix(&mix_state, samples[:])

    energy := f64(0)
    for sample in samples {
        testing.expect(t, math.abs(sample) < engine_sound.MASTER_CEILING)
        energy += f64(sample * sample)
    }
    testing.expect(t, energy > 1)
}

@(test)
engine_sound_master_limiter_contains_polyphonic_impacts :: proc(t: ^testing.T) {
    crash := engine_sound.new_crash_mixer(51)
    footsteps := engine_sound.new_footstep_mixer(52)
    samples: [engine_sound.SAMPLE_RATE / 2]f32
    surfaces := [4]engine_sound.Crash_Surface{.Asphalt, .Gravel, .Cobblestone, .Dirt}
    profiles := [4]engine_sound.Crash_Profile{.Car, .Fixed_Wing, .Rotorcraft, .Car}
    foot_surfaces := [4]engine_sound.Footstep_Surface{.Asphalt, .Gravel, .Cobblestone, .Dirt}
    for index in 0 ..< 4 {
        engine_sound.trigger_crash_mixer(
            &crash,
            1,
            f32(index) * .2,
            1,
            surfaces[index],
            profiles[index],
            f32(index) * .15,
        )
        engine_sound.trigger_footstep_mixer(&footsteps, 1, foot_surfaces[index], true, f32(index) * .2)
    }
    engine_sound.render_crash_mixer_add(&crash, samples[:])
    engine_sound.render_footstep_mixer_add(&footsteps, samples[:])

    mix_state: engine_sound.Mix_State
    engine_sound.process_mix(&mix_state, samples[:])

    energy := f64(0)
    peak := f32(0)
    for sample in samples {
        testing.expect(t, sample == sample)
        peak = max(peak, math.abs(sample))
        energy += f64(sample * sample)
    }
    testing.expect(t, peak < engine_sound.MASTER_CEILING)
    testing.expect(t, peak > engine_sound.MASTER_KNEE)
    testing.expect(t, energy > 1)
}

@(test)
engine_sound_mix_rejects_dc_without_removing_engine_fundamental :: proc(t: ^testing.T) {
    dc_state, tone_state: engine_sound.Mix_State
    dc_samples, tone_samples: [1024]f32
    tone_phase := f32(0)
    input_tone_energy, output_tone_energy := f64(0), f64(0)
    rendered := 0
    for rendered < engine_sound.SAMPLE_RATE {
        for index in 0 ..< len(dc_samples) {
            dc_samples[index] = .4
            tone_samples[index] = f32(math.sin(f64(tone_phase))) * .1
            tone_phase += engine_sound.TAU * 18 / engine_sound.SAMPLE_RATE
            if tone_phase >= engine_sound.TAU do tone_phase -= engine_sound.TAU
        }
        engine_sound.process_mix(&dc_state, dc_samples[:])
        engine_sound.process_mix(&tone_state, tone_samples[:])
        if rendered >= engine_sound.SAMPLE_RATE / 4 {
            for sample in tone_samples {
                output_tone_energy += f64(sample * sample)
            }
            // A 0.1-amplitude sine has mean-square energy 0.005.
            input_tone_energy += f64(len(tone_samples)) * .005
        }
        rendered += len(dc_samples)
    }
    testing.expect(t, math.abs(dc_samples[len(dc_samples) - 1]) < .001)
    testing.expect(t, output_tone_energy > input_tone_energy * .85)
}

@(test)
wheel_slip_sound_requires_slip_and_speed :: proc(t: ^testing.T) {
    quiet, slipping := engine_sound.new_slip(17), engine_sound.new_slip(17)
    quiet_samples, slipping_samples: [engine_sound.SAMPLE_RATE / 4]f32
    engine_sound.render_slip_add(&quiet, {amount = 0, speed = .8, active = true}, quiet_samples[:])
    engine_sound.render_slip_add(&slipping, {amount = .9, speed = .8, active = true}, slipping_samples[:])

    quiet_energy, slipping_energy := f64(0), f64(0)
    for index in 0 ..< len(quiet_samples) {
        quiet_energy += f64(quiet_samples[index] * quiet_samples[index])
        slipping_energy += f64(slipping_samples[index] * slipping_samples[index])
        testing.expect(t, math.abs(slipping_samples[index]) <= .92)
    }
    testing.expect(t, slipping_energy > quiet_energy + .01)
}

@(test)
wheel_slip_speed_changes_are_smoothed :: proc(t: ^testing.T) {
    synth := engine_sound.new_slip(31)
    sample: [1]f32
    engine_sound.render_slip_add(&synth, {amount = 1, speed = 1, active = true}, sample[:])
    testing.expect(t, synth.speed > 0 && synth.speed < 1)

    previous_speed := synth.speed
    engine_sound.render_slip_add(&synth, {amount = 1, speed = 0, active = true}, sample[:])
    testing.expect(t, synth.speed > 0 && synth.speed < previous_speed)
}

@(test)
wheel_slip_render_is_deterministic_across_callback_chunks :: proc(t: ^testing.T) {
    whole, chunked := engine_sound.new_slip(37), engine_sound.new_slip(37)
    whole_samples, chunked_samples: [4096]f32
    controls := engine_sound.Slip_Controls {
        amount = .83,
        speed  = .76,
        active = true,
    }
    engine_sound.render_slip_add(&whole, controls, whole_samples[:])
    for offset := 0; offset < len(chunked_samples); offset += 251 {
        count := min(251, len(chunked_samples) - offset)
        engine_sound.render_slip_add(&chunked, controls, chunked_samples[offset:offset + count])
    }
    testing.expect(t, whole_samples == chunked_samples)
}

@(test)
wheel_slip_material_changes_squeal_and_loose_scrub :: proc(t: ^testing.T) {
    asphalt, gravel := engine_sound.new_slip(43), engine_sound.new_slip(43)
    asphalt_samples, gravel_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render_slip_add(
        &asphalt,
        {amount = .9, speed = .84, surface = .Asphalt, active = true},
        asphalt_samples[:],
    )
    engine_sound.render_slip_add(
        &gravel,
        {amount = .9, speed = .84, surface = .Gravel, active = true},
        gravel_samples[:],
    )

    difference := f64(0)
    for index in 0 ..< len(asphalt_samples) {
        difference += math.abs(f64(asphalt_samples[index] - gravel_samples[index]))
        testing.expect(t, math.abs(asphalt_samples[index]) <= .92)
        testing.expect(t, math.abs(gravel_samples[index]) <= .92)
    }
    testing.expect(t, difference > 1)
    testing.expect(t, asphalt.hardness > gravel.hardness)
    testing.expect(t, gravel.looseness > asphalt.looseness)
}

@(test)
dry_asphalt_slip_develops_stronger_stick_slip_breakup :: proc(t: ^testing.T) {
    asphalt, gravel, wet := engine_sound.new_slip(45), engine_sound.new_slip(45), engine_sound.new_slip(45)
    asphalt_samples, gravel_samples, wet_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render_slip_add(
        &asphalt,
        {amount = .95, speed = .9, surface = .Asphalt, active = true},
        asphalt_samples[:],
    )
    engine_sound.render_slip_add(
        &gravel,
        {amount = .95, speed = .9, surface = .Gravel, active = true},
        gravel_samples[:],
    )
    engine_sound.render_slip_add(
        &wet,
        {amount = .95, speed = .9, wetness = 1, surface = .Asphalt, active = true},
        wet_samples[:],
    )

    testing.expect(t, asphalt.stick_depth > .7)
    testing.expect(t, asphalt.stick_depth > gravel.stick_depth * 10)
    testing.expect(t, asphalt.stick_depth > wet.stick_depth * 3)
    testing.expect(t, asphalt.stick_phase > 0 && asphalt.stick_phase < 1)

    asphalt_gravel_difference, asphalt_wet_difference := f64(0), f64(0)
    for index in 0 ..< len(asphalt_samples) {
        asphalt_gravel_difference += math.abs(f64(asphalt_samples[index] - gravel_samples[index]))
        asphalt_wet_difference += math.abs(f64(asphalt_samples[index] - wet_samples[index]))
    }
    testing.expect(t, asphalt_gravel_difference > 1)
    testing.expect(t, asphalt_wet_difference > 1)
}

@(test)
dry_asphalt_squeal_moves_between_seeded_belt_modes :: proc(t: ^testing.T) {
    dry, matching, wet := engine_sound.new_slip(451), engine_sound.new_slip(451), engine_sound.new_slip(451)
    controls := engine_sound.Slip_Controls {
        amount  = .98,
        speed   = .92,
        surface = .Asphalt,
        active  = true,
    }
    dry_samples, matching_samples, wet_samples: [engine_sound.SAMPLE_RATE]f32
    engine_sound.render_slip_add(&dry, controls, dry_samples[:])
    engine_sound.render_slip_add(&matching, controls, matching_samples[:])
    controls.wetness = 1
    engine_sound.render_slip_add(&wet, controls, wet_samples[:])

    testing.expect(t, dry_samples == matching_samples)
    testing.expect(t, dry.squeal_mode_count >= 2)
    testing.expect(t, dry.squeal_mode_count == matching.squeal_mode_count)
    testing.expect(t, abs(dry.squeal_mode_target) <= .06)
    testing.expect(t, abs(dry.squeal_mode_offset) <= .06)
    testing.expect(t, wet.squeal_mode_count == 0)
    testing.expect(t, wet.squeal_mode_offset == 0)
}

@(test)
loose_surface_slip_throws_seeded_aggregate_strikes :: proc(t: ^testing.T) {
    asphalt, gravel, wet_gravel := engine_sound.new_slip(46), engine_sound.new_slip(46), engine_sound.new_slip(46)
    asphalt_samples, gravel_samples, wet_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render_slip_add(
        &asphalt,
        {amount = .95, speed = .9, surface = .Asphalt, active = true},
        asphalt_samples[:],
    )
    engine_sound.render_slip_add(
        &gravel,
        {amount = .95, speed = .9, surface = .Gravel, active = true},
        gravel_samples[:],
    )
    engine_sound.render_slip_add(
        &wet_gravel,
        {amount = .95, speed = .9, wetness = 1, surface = .Gravel, active = true},
        wet_samples[:],
    )

    testing.expect(t, asphalt.aggregate_count == 0)
    testing.expect(t, gravel.aggregate_count > 0)
    testing.expect(t, gravel.aggregate_count > wet_gravel.aggregate_count)
    testing.expect(t, gravel.aggregate_hz > 240)
    difference := f64(0)
    for index in 0 ..< len(gravel_samples) {
        difference += math.abs(f64(gravel_samples[index] - asphalt_samples[index]))
        testing.expect(t, math.abs(gravel_samples[index]) <= .92)
    }
    testing.expect(t, difference > 1)
}

@(test)
tire_roll_speed_and_surface_shape_output :: proc(t: ^testing.T) {
    stopped, smooth, rough := engine_sound.new_roll(23), engine_sound.new_roll(23), engine_sound.new_roll(23)
    stopped_samples, smooth_samples, rough_samples: [engine_sound.SAMPLE_RATE / 4]f32
    engine_sound.render_roll_add(&stopped, {speed = 0, roughness = 1, active = true}, stopped_samples[:])
    engine_sound.render_roll_add(&smooth, {speed = .7, roughness = .1, active = true}, smooth_samples[:])
    engine_sound.render_roll_add(&rough, {speed = .7, roughness = 1, active = true}, rough_samples[:])

    stopped_energy, smooth_energy, rough_energy := f64(0), f64(0), f64(0)
    for index in 0 ..< len(stopped_samples) {
        stopped_energy += f64(stopped_samples[index] * stopped_samples[index])
        smooth_energy += f64(smooth_samples[index] * smooth_samples[index])
        rough_energy += f64(rough_samples[index] * rough_samples[index])
        testing.expect(t, math.abs(rough_samples[index]) <= .92)
    }
    testing.expect(t, stopped_energy < .0001)
    testing.expect(t, smooth_energy > stopped_energy + .001)
    testing.expect(t, rough_energy > smooth_energy)
}

@(test)
tire_roll_render_is_deterministic_across_callback_chunks :: proc(t: ^testing.T) {
    whole, chunked := engine_sound.new_roll(43), engine_sound.new_roll(43)
    whole_samples, chunked_samples: [4096]f32
    controls := engine_sound.Roll_Controls {
        speed     = .78,
        roughness = .86,
        active    = true,
    }
    engine_sound.render_roll_add(&whole, controls, whole_samples[:])
    for offset := 0; offset < len(chunked_samples); offset += 263 {
        count := min(263, len(chunked_samples) - offset)
        engine_sound.render_roll_add(&chunked, controls, chunked_samples[offset:offset + count])
    }
    testing.expect(t, whole_samples == chunked_samples)
}

@(test)
tire_roll_surface_impacts_use_aperiodic_seeded_intervals :: proc(t: ^testing.T) {
    first, matching := engine_sound.new_roll(45), engine_sound.new_roll(45)
    controls := engine_sound.Roll_Controls {
        speed     = 1,
        roughness = 1,
        wetness   = 1,
        surface   = .Gravel,
        active    = true,
    }
    knock_samples, spray_samples: [64]int
    knock_events, spray_events := 0, 0
    previous_knocks, previous_sprays := u32(0), u32(0)
    first_sample, matching_sample: [1]f32
    for sample_index in 0 ..< engine_sound.SAMPLE_RATE {
        engine_sound.render_roll_add(&first, controls, first_sample[:])
        engine_sound.render_roll_add(&matching, controls, matching_sample[:])
        testing.expect(t, first_sample == matching_sample)
        if first.knock_count != previous_knocks {
            if knock_events < len(knock_samples) do knock_samples[knock_events] = sample_index
            knock_events += 1
            previous_knocks = first.knock_count
        }
        if first.spray_count != previous_sprays {
            if spray_events < len(spray_samples) do spray_samples[spray_events] = sample_index
            spray_events += 1
            previous_sprays = first.spray_count
        }
    }

    testing.expect(t, knock_events >= 8 && knock_events <= len(knock_samples))
    testing.expect(t, spray_events >= 8 && spray_events <= len(spray_samples))
    knock_reference := knock_samples[1] - knock_samples[0]
    spray_reference := spray_samples[1] - spray_samples[0]
    varied_knocks, varied_sprays := 0, 0
    for index in 2 ..< knock_events {
        if knock_samples[index] - knock_samples[index - 1] != knock_reference do varied_knocks += 1
    }
    for index in 2 ..< spray_events {
        if spray_samples[index] - spray_samples[index - 1] != spray_reference do varied_sprays += 1
    }
    testing.expect(t, varied_knocks >= knock_events / 2)
    testing.expect(t, varied_sprays >= spray_events / 2)
    testing.expect(t, first.knock_count == matching.knock_count)
    testing.expect(t, first.spray_count == matching.spray_count)
}

@(test)
tire_roll_material_changes_timbre_at_matched_roughness :: proc(t: ^testing.T) {
    gravel, cobble := engine_sound.new_roll(47), engine_sound.new_roll(47)
    gravel_samples, cobble_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render_roll_add(
        &gravel,
        {speed = .74, roughness = .7, surface = .Gravel, active = true},
        gravel_samples[:],
    )
    engine_sound.render_roll_add(
        &cobble,
        {speed = .74, roughness = .7, surface = .Cobblestone, active = true},
        cobble_samples[:],
    )

    difference := f64(0)
    for index in 0 ..< len(gravel_samples) {
        difference += math.abs(f64(gravel_samples[index] - cobble_samples[index]))
        testing.expect(t, math.abs(gravel_samples[index]) <= .92)
        testing.expect(t, math.abs(cobble_samples[index]) <= .92)
    }
    testing.expect(t, difference > 1)
    testing.expect(t, gravel.looseness > cobble.looseness)
    testing.expect(t, cobble.hardness > gravel.hardness)
}

@(test)
damaged_wheel_roll_adds_speed_following_suspension_thumps :: proc(t: ^testing.T) {
    healthy, damaged, slow := engine_sound.new_roll(51), engine_sound.new_roll(51), engine_sound.new_roll(51)
    healthy_samples, damaged_samples, slow_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render_roll_add(
        &healthy,
        {speed = .82, roughness = .2, surface = .Asphalt, active = true},
        healthy_samples[:],
    )
    engine_sound.render_roll_add(
        &damaged,
        {speed = .82, roughness = .2, damage = 1, surface = .Asphalt, active = true},
        damaged_samples[:],
    )
    engine_sound.render_roll_add(
        &slow,
        {speed = .18, roughness = .2, damage = 1, surface = .Asphalt, active = true},
        slow_samples[:],
    )

    testing.expect(t, healthy.wobble_count == 0)
    testing.expect(t, damaged.wobble_count > slow.wobble_count)
    testing.expect(t, damaged.damage > .8)
    difference := f64(0)
    for index in 0 ..< len(healthy_samples) {
        difference += math.abs(f64(damaged_samples[index] - healthy_samples[index]))
        testing.expect(t, math.abs(damaged_samples[index]) <= .92)
    }
    testing.expect(t, difference > 5)
}

@(test)
damaged_wheel_thump_resonance_starts_at_a_zero_crossing :: proc(t: ^testing.T) {
    synth := engine_sound.new_roll(52)
    synth.speed = 1
    synth.damage = 1
    synth.hardness = 1
    synth.level = 1
    synth.wobble_phase = .9999
    synth.wobble_ring_phase = .71
    samples: [1]f32
    engine_sound.render_roll_add(&synth, {speed = 1, damage = 1, surface = .Asphalt, active = true}, samples[:])

    testing.expect(t, synth.wobble_count == 1)
    testing.expect(t, synth.wobble_ring_phase > 0 && synth.wobble_ring_phase < .003)
    testing.expect(t, math.abs(samples[0]) <= .92)
}

@(test)
wet_tire_roll_adds_water_displacement_and_drains_slowly :: proc(t: ^testing.T) {
    dry, wet := engine_sound.new_roll(53), engine_sound.new_roll(53)
    dry_samples, wet_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render_roll_add(&dry, {speed = .8, roughness = .12, active = true}, dry_samples[:])
    engine_sound.render_roll_add(&wet, {speed = .8, roughness = .12, wetness = 1, active = true}, wet_samples[:])

    difference := f64(0)
    for index in 0 ..< len(dry_samples) {
        difference += math.abs(f64(dry_samples[index] - wet_samples[index]))
    }
    testing.expect(t, difference > 1)
    testing.expect(t, wet.wetness > .6)
    wet_before_drying := wet.wetness
    sample: [1]f32
    engine_sound.render_roll_add(&wet, {speed = .8, roughness = .12, active = true}, sample[:])
    testing.expect(t, wet.wetness < wet_before_drying)
    testing.expect(t, wet.wetness > 0)
}

@(test)
deep_water_only_hydroplanes_at_road_speed :: proc(t: ^testing.T) {
    dry, slow_wet, fast_wet := engine_sound.new_roll(57), engine_sound.new_roll(57), engine_sound.new_roll(57)
    dry_samples, slow_wet_samples, fast_wet_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render_roll_add(
        &dry,
        {speed = .9, roughness = .35, surface = .Asphalt, active = true},
        dry_samples[:],
    )
    engine_sound.render_roll_add(
        &slow_wet,
        {speed = .3, roughness = .35, wetness = 1, surface = .Asphalt, active = true},
        slow_wet_samples[:],
    )
    engine_sound.render_roll_add(
        &fast_wet,
        {speed = .9, roughness = .35, wetness = 1, surface = .Asphalt, active = true},
        fast_wet_samples[:],
    )

    testing.expect(t, dry.hydroplane_mix == 0)
    testing.expect(t, slow_wet.hydroplane_mix == 0)
    testing.expect(t, fast_wet.hydroplane_mix > .6)
    testing.expect(t, fast_wet.hydroplane_phase > 0 && fast_wet.hydroplane_phase < 1)

    difference := f64(0)
    for index in 0 ..< len(dry_samples) {
        difference += math.abs(f64(fast_wet_samples[index] - dry_samples[index]))
        testing.expect(t, math.abs(fast_wet_samples[index]) <= .92)
    }
    testing.expect(t, difference > 1)
}

@(test)
wet_wheel_slip_shifts_squeal_into_water_scrub :: proc(t: ^testing.T) {
    dry, wet := engine_sound.new_slip(59), engine_sound.new_slip(59)
    dry_samples, wet_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render_slip_add(&dry, {amount = .9, speed = .85, active = true}, dry_samples[:])
    engine_sound.render_slip_add(&wet, {amount = .9, speed = .85, wetness = 1, active = true}, wet_samples[:])

    difference := f64(0)
    for index in 0 ..< len(dry_samples) {
        difference += math.abs(f64(dry_samples[index] - wet_samples[index]))
        testing.expect(t, math.abs(wet_samples[index]) <= .92)
    }
    testing.expect(t, difference > 1)
    testing.expect(t, wet.wetness > .7)
}

@(test)
interleaved_master_processing_preserves_independent_stereo_channels :: proc(t: ^testing.T) {
    states: [2]engine_sound.Mix_State
    samples := [8]f32{.2, -.4, .3, -.1, -.25, .35, .1, -.2}
    left := [4]f32{samples[0], samples[2], samples[4], samples[6]}
    right := [4]f32{samples[1], samples[3], samples[5], samples[7]}
    left_state, right_state: engine_sound.Mix_State
    engine_sound.process_mix(&left_state, left[:])
    engine_sound.process_mix(&right_state, right[:])
    engine_sound.process_mix_interleaved(states[:], samples[:], 2)

    for index in 0 ..< 4 {
        testing.expect(t, samples[index * 2] == left[index])
        testing.expect(t, samples[index * 2 + 1] == right[index])
    }
}

@(test)
stereo_limiter_links_peak_gain_to_preserve_image_balance :: proc(t: ^testing.T) {
    states: [2]engine_sound.Mix_State
    samples := [2]f32{1.2, .6}
    input_ratio := samples[0] / samples[1]
    engine_sound.process_mix_interleaved(states[:], samples[:], 2)

    testing.expect(t, abs(samples[0]) < engine_sound.MASTER_CEILING)
    testing.expect(t, abs(samples[1]) < engine_sound.MASTER_CEILING)
    testing.expect(t, math.abs(f64(samples[0] / samples[1] - input_ratio)) < 1e-6)
}

@(test)
stereo_limiter_recovers_smoothly_after_peak :: proc(t: ^testing.T) {
    states: [2]engine_sound.Mix_State
    peak := [2]f32{1.4, -.7}
    engine_sound.process_mix_interleaved(states[:], peak[:], 2)
    captured_gain := states[0].limiter_gain
    testing.expect(t, captured_gain > 0 && captured_gain < 1)

    quiet := [2]f32{.1, -.05}
    engine_sound.process_mix_interleaved(states[:], quiet[:], 2)
    testing.expect(t, states[0].limiter_gain > captured_gain)
    testing.expect(t, states[0].limiter_gain < 1)
    testing.expect(t, abs(quiet[0]) < .1)
}

@(test)
powertrain_width_is_stereo_distinct_and_exactly_mono_compatible :: proc(t: ^testing.T) {
    state: engine_sound.Source_Width_State
    mono := [64]f32{}
    for index in 0 ..< len(mono) {
        mono[index] = f32(math.sin(f64(index) * .37)) * .3
    }
    stereo: [len(mono) * 2]f32
    engine_sound.widen_source_stereo(&state, mono[:], stereo[:], .12)

    difference := f32(0)
    for index in 0 ..< len(mono) {
        left, right := stereo[index * 2], stereo[index * 2 + 1]
        difference += abs(left - right)
        testing.expect(t, math.abs(f64((left + right) * .5 - mono[index])) < 1e-6)
    }
    testing.expect(t, difference > .1)
}

@(test)
additive_source_width_preserves_existing_mix_and_mono_sum :: proc(t: ^testing.T) {
    state: engine_sound.Source_Width_State
    mono := [32]f32{}
    stereo := [len(mono) * 2]f32{}
    for index in 0 ..< len(mono) {
        mono[index] = f32(math.sin(f64(index) * .51)) * .22
        stereo[index * 2] = .1
        stereo[index * 2 + 1] = -.06
    }
    engine_sound.widen_source_stereo(&state, mono[:], stereo[:], .14, true)

    for index in 0 ..< len(mono) {
        added_left := stereo[index * 2] - .1
        added_right := stereo[index * 2 + 1] + .06
        collapsed := (added_left + added_right) * .5
        testing.expect(t, math.abs(f64(collapsed - mono[index])) < 1e-6)
    }
}

@(test)
device_mute_fade_duration_is_independent_of_channel_count :: proc(t: ^testing.T) {
    mono_gain, stereo_gain := f32(1), f32(1)
    mono: [4096]f32
    stereo: [len(mono) * 2]f32
    for &sample in mono do sample = 1
    for &sample in stereo do sample = 1
    engine_sound.apply_device_mute(&mono_gain, mono[:], true)
    engine_sound.apply_device_mute(&stereo_gain, stereo[:], true, 2)

    testing.expect(t, math.abs(f64(mono_gain - stereo_gain)) < 1e-6)
    for index in 0 ..< len(mono) {
        collapsed := (stereo[index * 2] + stereo[index * 2 + 1]) * .5
        testing.expect(t, math.abs(f64(collapsed - mono[index])) < .0001)
    }
}

@(test)
audio_queue_target_balances_responsiveness_and_hitch_margin :: proc(t: ^testing.T) {
    queue_seconds := f32(engine_sound.TARGET_QUEUED_FRAMES) / engine_sound.SAMPLE_RATE
    testing.expect(t, engine_sound.TARGET_QUEUED_FRAMES >= engine_sound.BUFFER_SAMPLES * 2)
    testing.expect(t, queue_seconds < .05)
    testing.expect(t, queue_seconds > .04)
}
