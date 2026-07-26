package tests

import engine_sound "../packages/engine_sound"
import "core:math"
import "core:testing"

@(test)
crash_sound_is_silent_until_triggered_and_then_decays :: proc(t: ^testing.T) {
    synth := engine_sound.new_crash(17)
    samples: [engine_sound.SAMPLE_RATE / 4]f32
    engine_sound.render_crash_add(&synth, samples[:])
    testing.expect(t, energy(samples[:]) == 0)

    engine_sound.trigger_crash(&synth, .8)
    engine_sound.render_crash_add(&synth, samples[:])
    testing.expect(t, energy(samples[:]) > .01)
    for synth.duration > 0 do engine_sound.render_crash_add(&synth, samples[:])
    testing.expect(t, synth.duration == 0)
}

@(test)
hard_crash_has_more_energy_than_light_crash :: proc(t: ^testing.T) {
    light, hard := engine_sound.new_crash(23), engine_sound.new_crash(23)
    light_samples, hard_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.trigger_crash(&light, .2)
    engine_sound.trigger_crash(&hard, 1)
    engine_sound.render_crash_add(&light, light_samples[:])
    engine_sound.render_crash_add(&hard, hard_samples[:])
    testing.expect(t, energy(hard_samples[:]) > energy(light_samples[:]) * 1.4)
}

@(test)
crash_render_is_deterministic_across_callback_chunk_sizes :: proc(t: ^testing.T) {
    whole, chunked := engine_sound.new_crash(41), engine_sound.new_crash(41)
    whole_samples, chunked_samples: [4096]f32
    engine_sound.trigger_crash(&whole, .65)
    engine_sound.trigger_crash(&chunked, .65)
    engine_sound.render_crash_add(&whole, whole_samples[:])
    for offset := 0; offset < len(chunked_samples); offset += 257 {
        count := min(257, len(chunked_samples) - offset)
        engine_sound.render_crash_add(&chunked, chunked_samples[offset:offset + count])
    }
    testing.expect(t, whole_samples == chunked_samples)
}

@(test)
hard_crash_unfolds_as_a_seeded_structural_crumple_cascade :: proc(t: ^testing.T) {
    light, car, matching := engine_sound.new_crash(47), engine_sound.new_crash(47), engine_sound.new_crash(47)
    light_samples, car_samples, matching_samples: [engine_sound.SAMPLE_RATE / 3]f32
    engine_sound.trigger_crash(&light, .2, 0, 0, .Asphalt, .Car)
    engine_sound.trigger_crash(&car, 1, 0, 0, .Asphalt, .Car)
    engine_sound.trigger_crash(&matching, 1, 0, 0, .Asphalt, .Car)
    engine_sound.render_crash_add(&light, light_samples[:])
    engine_sound.render_crash_add(&car, car_samples[:])
    engine_sound.render_crash_add(&matching, matching_samples[:])

    testing.expect(t, light.crumple_mix == 0)
    testing.expect(t, light.crumple_count == 0)
    testing.expect(t, car.crumple_mix == 1)
    testing.expect(t, car.crumple_count >= 4)
    testing.expect(t, car.crumple_count == matching.crumple_count)
    testing.expect(t, car_samples == matching_samples)
    testing.expect(t, car.crumple_age_a > 0)
    testing.expect(t, car.crumple_age_b > 0)
}

@(test)
vehicle_profiles_tune_structural_buckle_pitch_and_strength :: proc(t: ^testing.T) {
    car, fixed_wing, rotorcraft := engine_sound.new_crash(49), engine_sound.new_crash(49), engine_sound.new_crash(49)
    samples: [engine_sound.SAMPLE_RATE / 4]f32
    engine_sound.trigger_crash(&car, 1, 0, 0, .Asphalt, .Car)
    engine_sound.trigger_crash(&fixed_wing, 1, 0, 0, .Asphalt, .Fixed_Wing)
    engine_sound.trigger_crash(&rotorcraft, 1, 0, 0, .Asphalt, .Rotorcraft)
    engine_sound.render_crash_add(&car, samples[:])
    engine_sound.render_crash_add(&fixed_wing, samples[:])
    engine_sound.render_crash_add(&rotorcraft, samples[:])

    testing.expect(t, fixed_wing.crumple_hz > car.crumple_hz)
    testing.expect(t, car.crumple_hz > rotorcraft.crumple_hz)
    testing.expect(t, car.crumple_mix > rotorcraft.crumple_mix)
    testing.expect(t, rotorcraft.crumple_mix > fixed_wing.crumple_mix)
    testing.expect(t, car.crumple_count > 0)
    testing.expect(t, fixed_wing.crumple_count > 0)
    testing.expect(t, rotorcraft.crumple_count > 0)
}

@(test)
water_crash_has_distinct_splash_body_and_longer_tail :: proc(t: ^testing.T) {
    land, water := engine_sound.new_crash(53), engine_sound.new_crash(53)
    land_samples, water_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.trigger_crash(&land, .8)
    engine_sound.trigger_crash(&water, .8, 1)
    engine_sound.render_crash_add(&land, land_samples[:])
    engine_sound.render_crash_add(&water, water_samples[:])

    testing.expect(t, water.water_mix == 1)
    testing.expect(t, water.duration > land.duration)
    testing.expect(t, water_samples != land_samples)
    testing.expect(t, energy(water_samples[:]) > .005)
}

@(test)
water_crash_adds_delayed_seeded_cavity_gurgle :: proc(t: ^testing.T) {
    water, matching := engine_sound.new_crash(57), engine_sound.new_crash(57)
    engine_sound.trigger_crash(&water, .85, 1, .2)
    engine_sound.trigger_crash(&matching, .85, 1, .2)
    testing.expect(t, water.bubble_mix == 1)
    testing.expect(t, water.bubble_frequency >= 19 && water.bubble_frequency <= 48)
    testing.expect(t, water.bubble_frequency == matching.bubble_frequency)

    without_bubbles := water
    without_bubbles.bubble_mix = 0
    water_samples, plain_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render_crash_add(&water, water_samples[:])
    engine_sound.render_crash_add(&without_bubbles, plain_samples[:])
    delayed_difference := f64(0)
    start := engine_sound.SAMPLE_RATE / 10
    for index in start ..< len(water_samples) {
        delayed_difference += math.abs(f64(water_samples[index] - plain_samples[index]))
    }
    testing.expect(t, delayed_difference > 10)
}

@(test)
fast_tangential_crash_has_sustained_scrape_tail :: proc(t: ^testing.T) {
    strike, slide := engine_sound.new_crash(67), engine_sound.new_crash(67)
    strike_samples, slide_samples: [engine_sound.SAMPLE_RATE]f32
    engine_sound.trigger_crash(&strike, .72, 0, 0)
    engine_sound.trigger_crash(&slide, .72, 0, 1)
    engine_sound.render_crash_add(&strike, strike_samples[:])
    engine_sound.render_crash_add(&slide, slide_samples[:])

    tail_start := engine_sound.SAMPLE_RATE * 3 / 4
    testing.expect(t, slide.slide_speed == 1)
    testing.expect(t, slide.duration > strike.duration)
    testing.expect(t, energy(slide_samples[tail_start:]) > energy(strike_samples[tail_start:]) * 2)
    testing.expect(t, slide_samples != strike_samples)
}

@(test)
crash_slide_speed_is_clamped_and_render_stays_finite :: proc(t: ^testing.T) {
    synth := engine_sound.new_crash(71)
    samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.trigger_crash(&synth, .8, 0, 5)
    engine_sound.render_crash_add(&synth, samples[:])

    testing.expect(t, synth.slide_speed == 1)
    for sample in samples {
        testing.expect(t, sample == sample)
        testing.expect(t, sample > -4 && sample < 4)
    }
}

@(test)
crash_ground_surfaces_have_distinct_hardness_and_grit :: proc(t: ^testing.T) {
    sand, gravel, asphalt := engine_sound.new_crash(73), engine_sound.new_crash(73), engine_sound.new_crash(73)
    sand_samples, gravel_samples, asphalt_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.trigger_crash(&sand, .75, 0, .3, .Sand)
    engine_sound.trigger_crash(&gravel, .75, 0, .3, .Gravel)
    engine_sound.trigger_crash(&asphalt, .75, 0, .3, .Asphalt)
    engine_sound.render_crash_add(&sand, sand_samples[:])
    engine_sound.render_crash_add(&gravel, gravel_samples[:])
    engine_sound.render_crash_add(&asphalt, asphalt_samples[:])

    testing.expect(t, sand.ground_grit > asphalt.ground_grit)
    testing.expect(t, gravel.ground_grit > sand.ground_grit)
    testing.expect(t, asphalt.ground_hardness > gravel.ground_hardness)
    testing.expect(t, sand_samples != gravel_samples)
    testing.expect(t, gravel_samples != asphalt_samples)
    testing.expect(t, sand_samples != asphalt_samples)
}

@(test)
sustained_crash_drag_uses_surface_specific_modes :: proc(t: ^testing.T) {
    sand, gravel, asphalt := engine_sound.new_crash(75), engine_sound.new_crash(75), engine_sound.new_crash(75)
    engine_sound.trigger_crash(&sand, .8, 0, .9, .Sand)
    engine_sound.trigger_crash(&gravel, .8, 0, .9, .Gravel)
    engine_sound.trigger_crash(&asphalt, .8, 0, .9, .Asphalt)
    testing.expect(t, sand.surface_drag_hz < gravel.surface_drag_hz)
    testing.expect(t, gravel.surface_drag_hz < asphalt.surface_drag_hz)

    sand_samples, gravel_samples, asphalt_samples: [engine_sound.SAMPLE_RATE]f32
    engine_sound.render_crash_add(&sand, sand_samples[:])
    engine_sound.render_crash_add(&gravel, gravel_samples[:])
    engine_sound.render_crash_add(&asphalt, asphalt_samples[:])
    tail := engine_sound.SAMPLE_RATE / 2
    sand_gravel_difference, gravel_asphalt_difference := f64(0), f64(0)
    for index in tail ..< len(sand_samples) {
        sand_gravel_difference += math.abs(f64(sand_samples[index] - gravel_samples[index]))
        gravel_asphalt_difference += math.abs(f64(gravel_samples[index] - asphalt_samples[index]))
    }
    testing.expect(t, sand_gravel_difference > 1)
    testing.expect(t, gravel_asphalt_difference > 1)
}

@(test)
water_crash_suppresses_ground_contact_material :: proc(t: ^testing.T) {
    sand, asphalt := engine_sound.new_crash(79), engine_sound.new_crash(79)
    sand_samples, asphalt_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.trigger_crash(&sand, .8, 1, .2, .Sand)
    engine_sound.trigger_crash(&asphalt, .8, 1, .2, .Asphalt)
    engine_sound.render_crash_add(&sand, sand_samples[:])
    engine_sound.render_crash_add(&asphalt, asphalt_samples[:])
    testing.expect(t, sand_samples == asphalt_samples)
}

@(test)
wet_ground_crash_adds_puddle_slap_without_becoming_water_impact :: proc(t: ^testing.T) {
    dry, wet, submerged := engine_sound.new_crash(81), engine_sound.new_crash(81), engine_sound.new_crash(81)
    engine_sound.trigger_crash(&dry, .75, 0, .35, .Asphalt, .Car, 0)
    engine_sound.trigger_crash(&wet, .75, 0, .35, .Asphalt, .Car, 4)
    engine_sound.trigger_crash(&submerged, .75, 1, .35, .Asphalt, .Car, 1)
    testing.expect(t, wet.surface_wetness == 1)
    testing.expect(t, wet.duration > dry.duration)
    testing.expect(t, wet.duration < submerged.duration)

    dry_samples, wet_samples, submerged_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render_crash_add(&dry, dry_samples[:])
    engine_sound.render_crash_add(&wet, wet_samples[:])
    engine_sound.render_crash_add(&submerged, submerged_samples[:])
    testing.expect(t, dry_samples != wet_samples)
    testing.expect(t, wet_samples != submerged_samples)
}

@(test)
crash_has_irregular_severity_scaled_chassis_rebounds :: proc(t: ^testing.T) {
    light, hard := engine_sound.new_crash(83), engine_sound.new_crash(83)
    engine_sound.trigger_crash(&light, .2)
    engine_sound.trigger_crash(&hard, 1)
    testing.expect(t, hard.rebound_time_a >= .095 && hard.rebound_time_a <= .17)
    testing.expect(t, hard.rebound_time_b > hard.rebound_time_a + .1)
    testing.expect(t, hard.rebound_level_a > light.rebound_level_a)
    testing.expect(t, hard.rebound_level_b > light.rebound_level_b)

    with_rebounds := hard
    without_rebounds := hard
    without_rebounds.rebound_level_a = 0
    without_rebounds.rebound_level_b = 0
    rebound_samples, plain_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render_crash_add(&with_rebounds, rebound_samples[:])
    engine_sound.render_crash_add(&without_rebounds, plain_samples[:])

    difference := f64(0)
    rebound_start := int(hard.rebound_time_a * engine_sound.SAMPLE_RATE)
    for index in rebound_start ..< len(rebound_samples) {
        difference += math.abs(f64(rebound_samples[index] - plain_samples[index]))
    }
    testing.expect(t, difference > 1)
}

@(test)
water_damps_secondary_chassis_impacts :: proc(t: ^testing.T) {
    land, water := engine_sound.new_crash(89), engine_sound.new_crash(89)
    engine_sound.trigger_crash(&land, .8, 0)
    engine_sound.trigger_crash(&water, .8, 1)
    testing.expect(t, water.rebound_level_a < land.rebound_level_a * .4)
    testing.expect(t, water.rebound_level_b < land.rebound_level_b * .4)
}

@(test)
severe_crash_adds_delayed_profile_shaped_settling_groan :: proc(t: ^testing.T) {
    light, car, fixed_wing, rotorcraft, water :=
        engine_sound.new_crash(90),
        engine_sound.new_crash(90),
        engine_sound.new_crash(90),
        engine_sound.new_crash(90),
        engine_sound.new_crash(90)
    engine_sound.trigger_crash(&light, .3, 0, 0, .Asphalt, .Car)
    engine_sound.trigger_crash(&car, .9, 0, 0, .Asphalt, .Car)
    engine_sound.trigger_crash(&fixed_wing, .9, 0, 0, .Asphalt, .Fixed_Wing)
    engine_sound.trigger_crash(&rotorcraft, .9, 0, 0, .Asphalt, .Rotorcraft)
    engine_sound.trigger_crash(&water, .9, 1, 0, .Asphalt, .Car)

    testing.expect(t, light.settle_mix == 0)
    testing.expect(t, fixed_wing.settle_hz > car.settle_hz)
    testing.expect(t, car.settle_hz > rotorcraft.settle_hz)
    testing.expect(t, rotorcraft.settle_mix > car.settle_mix)
    testing.expect(t, water.settle_mix < car.settle_mix * .3)
    testing.expect(t, car.settle_time > car.rebound_time_b)

    with_groan := car
    without_groan := car
    without_groan.settle_mix = 0
    groan_samples, plain_samples: [engine_sound.SAMPLE_RATE * 3 / 4]f32
    engine_sound.render_crash_add(&with_groan, groan_samples[:])
    engine_sound.render_crash_add(&without_groan, plain_samples[:])

    settle_start := int(car.settle_time * engine_sound.SAMPLE_RATE)
    for index in 0 ..= settle_start {
        testing.expect(t, groan_samples[index] == plain_samples[index])
    }
    difference := f64(0)
    for index in settle_start + 1 ..< len(groan_samples) {
        difference += math.abs(f64(groan_samples[index] - plain_samples[index]))
    }
    testing.expect(t, difference > 20)
}

@(test)
vehicle_profiles_have_distinct_structural_resonance_and_debris :: proc(t: ^testing.T) {
    car, fixed_wing, rotorcraft := engine_sound.new_crash(91), engine_sound.new_crash(91), engine_sound.new_crash(91)
    engine_sound.trigger_crash(&car, .8, 0, .3, .Dirt, .Car)
    engine_sound.trigger_crash(&fixed_wing, .8, 0, .3, .Dirt, .Fixed_Wing)
    engine_sound.trigger_crash(&rotorcraft, .8, 0, .3, .Dirt, .Rotorcraft)

    testing.expect(t, fixed_wing.ring_frequency_a > car.ring_frequency_a)
    testing.expect(t, fixed_wing.ring_frequency_b > car.ring_frequency_b)
    testing.expect(t, rotorcraft.ring_frequency_a < car.ring_frequency_a)
    testing.expect(t, rotorcraft.debris_scale > car.debris_scale)
    testing.expect(t, fixed_wing.contact_frequency > car.contact_frequency)
    testing.expect(t, car.contact_frequency > rotorcraft.contact_frequency)
    testing.expect(t, fixed_wing.metal_scale > car.metal_scale)
    testing.expect(t, rotorcraft.duration > fixed_wing.duration)

    car_samples, fixed_samples, rotor_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render_crash_add(&car, car_samples[:])
    engine_sound.render_crash_add(&fixed_wing, fixed_samples[:])
    engine_sound.render_crash_add(&rotorcraft, rotor_samples[:])
    testing.expect(t, car_samples != fixed_samples)
    testing.expect(t, fixed_samples != rotor_samples)
}

@(test)
aircraft_crashes_add_seeded_decelerating_blade_strikes :: proc(t: ^testing.T) {
    car, fixed_wing, rotorcraft, water :=
        engine_sound.new_crash(911),
        engine_sound.new_crash(911),
        engine_sound.new_crash(911),
        engine_sound.new_crash(911)
    engine_sound.trigger_crash(&car, .9, 0, .2, .Asphalt, .Car)
    engine_sound.trigger_crash(&fixed_wing, .9, 0, .2, .Asphalt, .Fixed_Wing)
    engine_sound.trigger_crash(&rotorcraft, .9, 0, .2, .Asphalt, .Rotorcraft)
    engine_sound.trigger_crash(&water, .9, 1, .2, .Asphalt, .Rotorcraft)

    testing.expect(t, car.machinery_mix == 0)
    testing.expect(t, fixed_wing.machinery_rate > rotorcraft.machinery_rate * 3)
    testing.expect(t, fixed_wing.machinery_hz > rotorcraft.machinery_hz)
    testing.expect(t, rotorcraft.machinery_mix > fixed_wing.machinery_mix)
    testing.expect(t, water.machinery_mix < rotorcraft.machinery_mix * .3)

    with_strikes := rotorcraft
    without_strikes := rotorcraft
    without_strikes.machinery_mix = 0
    strike_samples, plain_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render_crash_add(&with_strikes, strike_samples[:])
    engine_sound.render_crash_add(&without_strikes, plain_samples[:])

    difference := f64(0)
    for index in 0 ..< len(strike_samples) {
        difference += math.abs(f64(strike_samples[index] - plain_samples[index]))
    }
    testing.expect(t, difference > 10)
}

@(test)
overlapping_blade_strikes_alternate_zero_crossing_resonators :: proc(t: ^testing.T) {
    synth := engine_sound.new_crash(912)
    engine_sound.trigger_crash(&synth, 1, 0, 0, .Asphalt, .Fixed_Wing)
    synth.machinery_phase = .9999
    samples: [1]f32
    engine_sound.render_crash_add(&synth, samples[:])
    testing.expect(t, synth.machinery_count == 1)
    testing.expect(t, synth.machinery_next == 1)
    testing.expect(t, synth.machinery_ring > 0 && synth.machinery_ring < .02)
    first_ring_phase := synth.machinery_ring

    synth.machinery_phase = .9999
    engine_sound.render_crash_add(&synth, samples[:])
    testing.expect(t, synth.machinery_count == 2)
    testing.expect(t, synth.machinery_next == 0)
    testing.expect(t, synth.machinery_ring > first_ring_phase)
    testing.expect(t, synth.machinery_ring_b > 0 && synth.machinery_ring_b < .02)
    testing.expect(t, math.abs(samples[0]) <= .92)
}

@(test)
primary_crash_has_a_click_free_structural_compression_pulse :: proc(t: ^testing.T) {
    pulse, filtered_only := engine_sound.new_crash(92), engine_sound.new_crash(92)
    engine_sound.trigger_crash(&pulse, .9, 0, 0, .Asphalt, .Car)
    engine_sound.trigger_crash(&filtered_only, .9, 0, 0, .Asphalt, .Car)
    filtered_only.contact_frequency = 0
    pulse_samples, filtered_samples: [engine_sound.SAMPLE_RATE / 20]f32
    engine_sound.render_crash_add(&pulse, pulse_samples[:])
    engine_sound.render_crash_add(&filtered_only, filtered_samples[:])

    testing.expect(t, math.abs(f64(pulse_samples[0] - filtered_samples[0])) < 1e-7)
    pulse_difference := f64(0)
    for index in 1 ..< len(pulse_samples) {
        pulse_difference += math.abs(f64(pulse_samples[index] - filtered_samples[index]))
    }
    testing.expect(t, pulse_difference > 10)
}

@(test)
severe_dry_crashes_add_profile_shaped_brittle_fracture :: proc(t: ^testing.T) {
    soft, hard, wet, rotor :=
        engine_sound.new_crash(93), engine_sound.new_crash(93), engine_sound.new_crash(93), engine_sound.new_crash(93)
    engine_sound.trigger_crash(&soft, .35, 0, 0, .Asphalt, .Car)
    engine_sound.trigger_crash(&hard, 1, 0, 0, .Asphalt, .Car)
    engine_sound.trigger_crash(&wet, 1, 1, 0, .Asphalt, .Car)
    engine_sound.trigger_crash(&rotor, 1, 0, 0, .Asphalt, .Rotorcraft)
    testing.expect(t, soft.glass_mix == 0)
    testing.expect(t, hard.glass_mix == 1)
    testing.expect(t, wet.glass_mix < hard.glass_mix * .2)
    testing.expect(t, rotor.glass_mix < hard.glass_mix * .4)
    testing.expect(t, hard.glass_frequency_a > rotor.glass_frequency_a)
    testing.expect(t, hard.glass_frequency_b > rotor.glass_frequency_b)

    with_glass := hard
    without_glass := hard
    without_glass.glass_mix = 0
    glass_samples, plain_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render_crash_add(&with_glass, glass_samples[:])
    engine_sound.render_crash_add(&without_glass, plain_samples[:])
    fracture_difference := f64(0)
    for index in 1 ..< len(glass_samples) {
        glass_delta := glass_samples[index] - glass_samples[index - 1]
        plain_delta := plain_samples[index] - plain_samples[index - 1]
        fracture_difference += math.abs(f64(glass_delta - plain_delta))
    }
    testing.expect(t, fracture_difference > 1)
}

@(test)
severe_car_crash_adds_delayed_tire_pressure_rupture :: proc(t: ^testing.T) {
    light, car, fixed_wing, submerged :=
        engine_sound.new_crash(94), engine_sound.new_crash(94), engine_sound.new_crash(94), engine_sound.new_crash(94)
    engine_sound.trigger_crash(&light, .5, 0, 0, .Asphalt, .Car)
    engine_sound.trigger_crash(&car, 1, 0, 0, .Asphalt, .Car)
    engine_sound.trigger_crash(&fixed_wing, 1, 0, 0, .Asphalt, .Fixed_Wing)
    engine_sound.trigger_crash(&submerged, 1, 1, 0, .Asphalt, .Car)

    testing.expect(t, light.tire_burst_mix == 0)
    testing.expect(t, car.tire_burst_mix == 1)
    testing.expect(t, fixed_wing.tire_burst_mix == 0)
    testing.expect(t, submerged.tire_burst_mix < car.tire_burst_mix * .11)
    testing.expect(t, car.tire_burst_time >= .032 && car.tire_burst_time <= .09)
    testing.expect(t, car.tire_burst_hz >= 118 && car.tire_burst_hz <= 192)

    without_tire := car
    without_tire.tire_burst_mix = 0
    tire_samples, plain_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render_crash_add(&car, tire_samples[:])
    engine_sound.render_crash_add(&without_tire, plain_samples[:])
    burst_start := int(car.tire_burst_time * engine_sound.SAMPLE_RATE)
    for index in 0 ..< burst_start {
        testing.expect(t, tire_samples[index] == plain_samples[index])
    }
    difference := f64(0)
    for index in burst_start ..< len(tire_samples) {
        difference += math.abs(f64(tire_samples[index] - plain_samples[index]))
    }
    testing.expect(t, difference > 3)
}

@(test)
vehicle_impact_detector_ignores_normal_driving_and_detects_collisions :: proc(t: ^testing.T) {
    detector: engine_sound.Vehicle_Impact_Detector
    severity, slide, obliqueness := engine_sound.detect_vehicle_impact(&detector, 16, 0, 0, 15.4, 0, 0, 1.0 / 60)
    testing.expect(t, severity == 0)
    testing.expect(t, slide == 0)
    testing.expect(t, obliqueness == 0)

    severity, slide, obliqueness = engine_sound.detect_vehicle_impact(&detector, 18, -2, 0, 8, 0, 3, 1.0 / 60)
    testing.expect(t, severity > .7)
    testing.expect(t, slide > 0 && slide < 1)
    testing.expect(t, obliqueness < .1)
    testing.expect(t, detector.cooldown > 0)
}

@(test)
vehicle_impact_detector_distinguishes_glancing_impulses :: proc(t: ^testing.T) {
    blunt_detector, glancing_detector: engine_sound.Vehicle_Impact_Detector
    blunt_severity, _, blunt_obliqueness := engine_sound.detect_vehicle_impact(
        &blunt_detector,
        15,
        0,
        0,
        8.9,
        0,
        0,
        1.0 / 60,
    )
    glancing_severity, _, glancing_obliqueness := engine_sound.detect_vehicle_impact(
        &glancing_detector,
        15,
        0,
        0,
        14,
        0,
        -6,
        1.0 / 60,
    )

    testing.expect(t, blunt_severity > 0)
    testing.expect(t, glancing_severity > 0)
    testing.expect(t, blunt_obliqueness < .01)
    testing.expect(t, glancing_obliqueness > .8)
}

@(test)
glancing_crash_trades_compression_for_tearing_and_scrape :: proc(t: ^testing.T) {
    blunt, glancing := engine_sound.new_crash(113), engine_sound.new_crash(113)
    blunt_samples, glancing_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.trigger_crash(&blunt, .8, 0, .35, .Asphalt, .Car, 0, 0)
    engine_sound.trigger_crash(&glancing, .8, 0, .35, .Asphalt, .Car, 0, 1)
    engine_sound.render_crash_add(&blunt, blunt_samples[:])
    engine_sound.render_crash_add(&glancing, glancing_samples[:])

    testing.expect(t, blunt.obliqueness == 0)
    testing.expect(t, glancing.obliqueness == 1)
    testing.expect(t, glancing.duration > blunt.duration)
    difference := f64(0)
    for index in 0 ..< len(blunt_samples) {
        difference += math.abs(f64(glancing_samples[index] - blunt_samples[index]))
    }
    testing.expect(t, difference > 5)
}

@(test)
vehicle_impact_detector_debounces_collision_solver_impulses :: proc(t: ^testing.T) {
    detector: engine_sound.Vehicle_Impact_Detector
    first, _, _ := engine_sound.detect_vehicle_impact(&detector, 20, 0, 0, 5, 0, 0, 1.0 / 60)
    repeated, _, _ := engine_sound.detect_vehicle_impact(&detector, 14, 0, 0, 4, 0, 0, 1.0 / 60)
    testing.expect(t, first == 1)
    testing.expect(t, repeated == 0)

    for detector.cooldown > 0 {
        engine_sound.detect_vehicle_impact(&detector, 2, 0, 0, 2, 0, 0, 1.0 / 60)
    }
    later, _, _ := engine_sound.detect_vehicle_impact(&detector, 12, 0, 0, 4, 0, 0, 1.0 / 60)
    testing.expect(t, later > 0)
}

@(test)
vehicle_audio_damage_accumulates_impacts_and_recovers_slowly :: proc(t: ^testing.T) {
    hard_damage := engine_sound.vehicle_audio_damage_step(0, 1, 1.0 / 60)
    testing.expect(t, hard_damage > .7 && hard_damage < 1)

    first := engine_sound.vehicle_audio_damage_step(0, .55, 1.0 / 60)
    repeated := engine_sound.vehicle_audio_damage_step(first, .55, 1.0 / 60)
    testing.expect(t, first > 0)
    testing.expect(t, repeated > first)

    one_second_later := engine_sound.vehicle_audio_damage_step(repeated, 0, 1)
    testing.expect(t, one_second_later < repeated)
    testing.expect(t, one_second_later > repeated * .95)
    testing.expect(t, engine_sound.vehicle_audio_damage_step(4, 4, 0) == 1)
}

@(test)
crash_mixer_preserves_active_tail_when_another_impact_starts :: proc(t: ^testing.T) {
    mixer := engine_sound.new_crash_mixer(97)
    first_index := engine_sound.trigger_crash_mixer(&mixer, .9, 0, .6, .Asphalt)
    warmup: [4096]f32
    engine_sound.render_crash_mixer_add(&mixer, warmup[:])
    first_age := mixer.voices[first_index].age

    second_index := engine_sound.trigger_crash_mixer(&mixer, .55, 0, .2, .Gravel)
    testing.expect(t, second_index != first_index)
    testing.expect(t, mixer.voices[first_index].age == first_age)
    testing.expect(t, mixer.voices[second_index].age == 0)

    overlap: [4096]f32
    engine_sound.render_crash_mixer_add(&mixer, overlap[:])
    testing.expect(t, mixer.voices[first_index].age > first_age)
    testing.expect(t, mixer.voices[second_index].age > 0)
    testing.expect(t, energy(overlap[:]) > .01)
}

@(test)
crash_mixer_is_deterministic_and_reuses_voices_in_bounded_order :: proc(t: ^testing.T) {
    a, b := engine_sound.new_crash_mixer(101), engine_sound.new_crash_mixer(101)
    a_samples, b_samples: [4096]f32
    for impact in 0 ..< engine_sound.CRASH_VOICE_COUNT + 2 {
        severity := .3 + f32(impact) * .08
        a_index := engine_sound.trigger_crash_mixer(&a, severity)
        b_index := engine_sound.trigger_crash_mixer(&b, severity)
        testing.expect(t, a_index == impact % engine_sound.CRASH_VOICE_COUNT)
        testing.expect(t, b_index == a_index)
    }
    engine_sound.render_crash_mixer_add(&a, a_samples[:])
    engine_sound.render_crash_mixer_add(&b, b_samples[:])
    testing.expect(t, a_samples == b_samples)
}

@(test)
saturated_crash_mixer_steals_the_least_audible_tail :: proc(t: ^testing.T) {
    mixer := engine_sound.new_crash_mixer(107)
    for index in 0 ..< engine_sound.CRASH_VOICE_COUNT {
        engine_sound.trigger_crash_mixer(&mixer, .85, 0, .5)
    }
    mixer.voices[0].age = mixer.voices[0].duration * .35
    mixer.voices[1].age = mixer.voices[1].duration * .92
    mixer.voices[1].last_output = .24
    mixer.voices[2].age = mixer.voices[2].duration * .55
    mixer.voices[3].age = mixer.voices[3].duration * .18

    testing.expect(
        t,
        engine_sound.crash_voice_audibility(&mixer.voices[1]) < engine_sound.crash_voice_audibility(&mixer.voices[0]),
    )
    stolen := engine_sound.trigger_crash_mixer(&mixer, .7)
    testing.expect(t, stolen == 1)
    testing.expect(t, math.abs(f64(mixer.stolen_tail - .24)) < 1e-6)
    testing.expect(t, mixer.voices[1].age == 0)
    testing.expect(t, mixer.voices[0].age > 0)
    testing.expect(t, mixer.voices[2].age > 0)
    testing.expect(t, mixer.voices[3].age > 0)
}

@(test)
stolen_crash_voice_crossfades_from_its_terminal_sample :: proc(t: ^testing.T) {
    with_tail := engine_sound.new_crash_mixer(109)
    for index in 0 ..< engine_sound.CRASH_VOICE_COUNT {
        engine_sound.trigger_crash_mixer(&with_tail, .8)
        with_tail.voices[index].age = with_tail.voices[index].duration * (.2 + f32(index) * .15)
    }
    with_tail.voices[3].age = with_tail.voices[3].duration * .96
    with_tail.voices[3].last_output = -.3
    stolen := engine_sound.trigger_crash_mixer(&with_tail, .65)
    testing.expect(t, stolen == 3)

    without_tail := with_tail
    without_tail.stolen_tail = 0
    with_samples, without_samples: [1024]f32
    engine_sound.render_crash_mixer_add(&with_tail, with_samples[:])
    engine_sound.render_crash_mixer_add(&without_tail, without_samples[:])
    first_difference := math.abs(f64(with_samples[0] - without_samples[0]))
    last_difference := math.abs(f64(with_samples[len(with_samples) - 1] - without_samples[len(without_samples) - 1]))
    testing.expect(t, math.abs(first_difference - .3) < 1e-5)
    testing.expect(t, last_difference < first_difference * .03)
    testing.expect(t, math.abs(f64(with_tail.stolen_tail)) < .01)
}

energy :: proc(samples: []f32) -> f32 {
    result := f32(0)
    for sample in samples do result += sample * sample
    return result / f32(len(samples))
}
