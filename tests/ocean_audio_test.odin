package tests

import ocean_audio "../packages/ocean_audio"
import "core:math"
import "core:testing"

@(test)
ocean_synth_is_deterministic_and_bounded :: proc(t: ^testing.T) {
    a := ocean_audio.new_synth(42)
    b := ocean_audio.new_synth(42)
    peak := f32(0)
    energy := f64(0)
    samples: [2]f32
    matching: [2]f32
    for _ in 0 ..< ocean_audio.SAMPLE_RATE * 3 {
        ocean_audio.render(&a, samples[:])
        ocean_audio.render(&b, matching[:])
        testing.expect(t, samples == matching)
        peak = max(peak, max(abs(samples[0]), abs(samples[1])))
        energy += f64(samples[0] * samples[0] + samples[1] * samples[1])
    }
    testing.expect(t, peak < 1)
    testing.expect(t, energy > 1)
}

@(test)
ocean_synth_produces_stereo_motion_without_dc_drift :: proc(t: ^testing.T) {
    synth := ocean_audio.new_synth(7)
    sum_left, sum_right, stereo_delta := f64(0), f64(0), f64(0)
    samples: [2]f32
    count := ocean_audio.SAMPLE_RATE * 8
    for _ in 0 ..< count {
        ocean_audio.render(&synth, samples[:])
        sum_left += f64(samples[0])
        sum_right += f64(samples[1])
        stereo_delta += math.abs(f64(samples[0] - samples[1]))
    }
    testing.expect(t, stereo_delta > 10)
    testing.expect(t, math.abs(sum_left / f64(count)) < .02)
    testing.expect(t, math.abs(sum_right / f64(count)) < .02)
}

@(test)
ocean_synth_fades_smoothly_when_muted :: proc(t: ^testing.T) {
    synth := ocean_audio.new_synth(19)
    samples: [2]f32
    ocean_audio.render(&synth, samples[:])
    ocean_audio.set_muted(&synth, true)
    ocean_audio.render(&synth, samples[:])
    testing.expect(t, synth.gain > 0 && synth.gain < 1)
    for _ in 0 ..< ocean_audio.SAMPLE_RATE {
        ocean_audio.render(&synth, samples[:])
    }
    testing.expect(t, synth.gain < .001)
}

@(test)
ocean_synth_varies_wave_energy_without_losing_chunk_determinism :: proc(t: ^testing.T) {
    a, b := ocean_audio.new_synth(31), ocean_audio.new_synth(31)
    initial_target := a.target_wave_strength
    a_samples, b_samples: [2048]f32
    sample_count := ocean_audio.SAMPLE_RATE * 15 * ocean_audio.CHANNELS
    rendered := 0
    for rendered < sample_count {
        count := min(len(a_samples), sample_count - rendered)
        count -= count % ocean_audio.CHANNELS
        ocean_audio.render(&a, a_samples[:count])
        ocean_audio.render(&b, b_samples[:count])
        for index in 0 ..< count {
            testing.expect(t, a_samples[index] == b_samples[index])
        }
        rendered += count
    }
    testing.expect(t, a.target_wave_strength != initial_target)
    testing.expect(t, a.wave_strength > .7 && a.wave_strength < 1.2)
}

@(test)
ocean_breaker_cadence_varies_smoothly_across_waves :: proc(t: ^testing.T) {
    synth := ocean_audio.new_synth(37)
    initial_target := synth.target_swell_rate
    samples: [4096]f32
    total_samples := ocean_audio.SAMPLE_RATE * 45 * ocean_audio.CHANNELS
    rendered := 0
    for rendered < total_samples {
        count := min(len(samples), total_samples - rendered)
        count -= count % ocean_audio.CHANNELS
        ocean_audio.render(&synth, samples[:count])
        rendered += count
    }

    testing.expect(t, synth.wave_count >= 3)
    testing.expect(t, synth.target_swell_rate != initial_target)
    testing.expect(t, synth.target_swell_rate >= .96 && synth.target_swell_rate <= 1.16)
    testing.expect(t, synth.swell_rate >= .96 && synth.swell_rate <= 1.16)
}

@(test)
ocean_waves_form_slow_deterministic_energy_sets :: proc(t: ^testing.T) {
    a, b := ocean_audio.new_synth(36), ocean_audio.new_synth(36)
    initial_strength := a.wave_set_strength
    samples_a, samples_b: [4096]f32
    rendered_frames := 0
    for rendered_frames < ocean_audio.SAMPLE_RATE * 24 {
        ocean_audio.render(&a, samples_a[:])
        ocean_audio.render(&b, samples_b[:])
        testing.expect(t, samples_a == samples_b)
        rendered_frames += len(samples_a) / ocean_audio.CHANNELS
    }

    testing.expect(t, a.wave_set_strength >= .92 && a.wave_set_strength <= 1.08)
    testing.expect(t, a.wave_set_strength != initial_strength)
    testing.expect(t, a.wave_set_phase == b.wave_set_phase)
    testing.expect(t, a.target_wave_strength == b.target_wave_strength)
}

@(test)
ocean_breaker_rising_edge_adds_seeded_crest_collapse :: proc(t: ^testing.T) {
    synth := ocean_audio.new_synth(38)
    samples: [4096]f32
    rendered_frames := 0
    for synth.crest_count == 0 && rendered_frames < ocean_audio.SAMPLE_RATE * 20 {
        ocean_audio.render(&synth, samples[:])
        rendered_frames += len(samples) / ocean_audio.CHANNELS
    }
    testing.expect(t, synth.crest_count == 1)
    testing.expect(t, synth.backwash_count == 0)
    testing.expect(t, synth.crest_duration >= .18 && synth.crest_duration <= .40)
    testing.expect(t, synth.crest_strength > 0)
    testing.expect(t, abs(synth.crest_pan) <= .46)

    with_crest := synth
    without_crest := synth
    without_crest.crest_duration = 0
    crest_samples, plain_samples: [4096]f32
    ocean_audio.render(&with_crest, crest_samples[:])
    ocean_audio.render(&without_crest, plain_samples[:])
    difference := f64(0)
    for index in 0 ..< len(crest_samples) {
        difference += math.abs(f64(crest_samples[index] - plain_samples[index]))
    }
    testing.expect(t, difference > .1)
}

@(test)
ocean_breaker_falling_edge_triggers_seeded_backwash :: proc(t: ^testing.T) {
    a, b := ocean_audio.new_synth(39), ocean_audio.new_synth(39)
    a_samples, b_samples: [4096]f32
    rendered_frames := 0
    for a.backwash_count == 0 && rendered_frames < ocean_audio.SAMPLE_RATE * 20 {
        ocean_audio.render(&a, a_samples[:])
        ocean_audio.render(&b, b_samples[:])
        testing.expect(t, a_samples == b_samples)
        rendered_frames += len(a_samples) / ocean_audio.CHANNELS
    }

    testing.expect(t, a.backwash_count == 1)
    testing.expect(t, a.backwash_count == b.backwash_count)
    testing.expect(t, a.backwash_duration > 2)
    testing.expect(t, a.backwash_duration == b.backwash_duration)
    testing.expect(t, a.backwash_strength > 0)
    testing.expect(t, a.backwash_age > 0)
    testing.expect(t, abs(a.backwash_low_left) + abs(a.backwash_low_right) > 0)

    for a.shingle_count == 0 && rendered_frames < ocean_audio.SAMPLE_RATE * 22 {
        ocean_audio.render(&a, a_samples[:])
        ocean_audio.render(&b, b_samples[:])
        testing.expect(t, a_samples == b_samples)
        rendered_frames += len(a_samples) / ocean_audio.CHANNELS
    }
    testing.expect(t, a.shingle_count > 0)
    testing.expect(t, a.shingle_count == b.shingle_count)
    testing.expect(t, a.shingle_hz >= 430 && a.shingle_hz <= 1_350)
    testing.expect(t, a.shingle_level > 0)
}

@(test)
ocean_shingle_resonance_starts_at_a_zero_crossing :: proc(t: ^testing.T) {
    synth := ocean_audio.new_synth(40)
    synth.backwash_duration = 1
    synth.backwash_strength = 1
    synth.sea_state, synth.target_sea_state = 1, 1
    synth.shingle_timer = 0
    synth.shingle_phase = .73
    synth.shingle_phase_b = .41
    samples: [2]f32
    ocean_audio.render(&synth, samples[:])

    testing.expect(t, synth.shingle_count == 1)
    testing.expect(t, synth.shingle_phase > 0 && synth.shingle_phase < .03)
    testing.expect(t, synth.shingle_phase_b > 0 && synth.shingle_phase_b < .08)
    testing.expect(t, abs(samples[0]) < 1 && abs(samples[1]) < 1)
}

@(test)
ocean_filter_coefficients_preserve_real_time_decay_across_sample_rates :: proc(t: ^testing.T) {
    reference := f32(.0007)
    at_24k := ocean_audio.coefficient_for_sample_rate(reference, 24_000)
    at_48k := ocean_audio.coefficient_for_sample_rate(reference, 48_000)
    at_96k := ocean_audio.coefficient_for_sample_rate(reference, 96_000)
    testing.expect(t, math.abs(f64(at_48k - reference)) < 1e-7)

    // Residual impulse energy after 10 ms should be rate independent.
    residual_24k := math.pow(f64(1 - at_24k), 240)
    residual_48k := math.pow(f64(1 - at_48k), 480)
    residual_96k := math.pow(f64(1 - at_96k), 960)
    testing.expect(t, math.abs(residual_24k - residual_48k) < 1e-5)
    testing.expect(t, math.abs(residual_48k - residual_96k) < 1e-5)
}

@(test)
ocean_sea_state_smoothly_tracks_wind_and_storm_severity :: proc(t: ^testing.T) {
    synth := ocean_audio.new_synth(41)
    samples: [2]f32
    initial_state := synth.sea_state
    ocean_audio.set_conditions(&synth, 22, 1)
    ocean_audio.render(&synth, samples[:])
    testing.expect(t, synth.sea_state > initial_state)
    testing.expect(t, synth.sea_state < synth.target_sea_state)
    testing.expect(t, synth.target_sea_state == 1)

    for _ in 0 ..< ocean_audio.SAMPLE_RATE * 12 {
        ocean_audio.render(&synth, samples[:])
    }
    testing.expect(t, synth.sea_state > .99)

    ocean_audio.set_conditions(&synth, 0, 0)
    ocean_audio.render(&synth, samples[:])
    testing.expect(t, synth.sea_state > 0)
    testing.expect(t, synth.target_sea_state == 0)
}

@(test)
stormy_ocean_has_more_energy_and_bright_foam_than_calm_ocean :: proc(t: ^testing.T) {
    calm, storm := ocean_audio.new_synth(47), ocean_audio.new_synth(47)
    calm.sea_state, calm.target_sea_state = 0, 0
    storm.sea_state, storm.target_sea_state = 1, 1
    ocean_audio.set_conditions(&calm, 0, 0)
    ocean_audio.set_conditions(&storm, 24, 1)
    calm_samples, storm_samples: [8192]f32
    calm_energy, storm_energy := f64(0), f64(0)
    calm_detail, storm_detail := f64(0), f64(0)
    total_samples := ocean_audio.SAMPLE_RATE * 4
    rendered := 0
    for rendered < total_samples {
        count := min(len(calm_samples), total_samples - rendered)
        count -= count % ocean_audio.CHANNELS
        ocean_audio.render(&calm, calm_samples[:count])
        ocean_audio.render(&storm, storm_samples[:count])
        for index in 2 ..< count {
            calm_energy += f64(calm_samples[index] * calm_samples[index])
            storm_energy += f64(storm_samples[index] * storm_samples[index])
            calm_delta := calm_samples[index] - calm_samples[index - 2]
            storm_delta := storm_samples[index] - storm_samples[index - 2]
            calm_detail += f64(calm_delta * calm_delta)
            storm_detail += f64(storm_delta * storm_delta)
        }
        rendered += count
    }
    testing.expect(t, storm_energy > calm_energy * 1.25)
    testing.expect(t, storm_detail > calm_detail * 1.25)
}

@(test)
ocean_presence_fades_smoothly_with_listener_altitude :: proc(t: ^testing.T) {
    testing.expect(t, ocean_audio.presence_for_listener_height(-10) == 1)
    testing.expect(t, ocean_audio.presence_for_listener_height(12) == 1)
    testing.expect(t, ocean_audio.presence_for_listener_height(120) < 1)
    testing.expect(t, math.abs(f64(ocean_audio.presence_for_listener_height(400) - .06)) < 1e-6)

    synth := ocean_audio.new_synth(53)
    ocean_audio.set_listener_height(&synth, 400)
    samples: [2]f32
    ocean_audio.render(&synth, samples[:])
    testing.expect(t, synth.presence < 1)
    testing.expect(t, synth.presence > synth.target_presence)
}

@(test)
ocean_presence_combines_altitude_and_shore_proximity :: proc(t: ^testing.T) {
    at_shore := ocean_audio.presence_for_listener(0, 1)
    inland := ocean_audio.presence_for_listener(0, 0)
    inland_high := ocean_audio.presence_for_listener(400, 0)
    testing.expect(t, at_shore == 1)
    testing.expect(t, math.abs(f64(inland - .12)) < 1e-6)
    testing.expect(t, inland_high > 0)
    testing.expect(t, inland_high < inland * .1)
    testing.expect(t, ocean_audio.presence_for_listener(0, -4) == inland)
    testing.expect(t, ocean_audio.presence_for_listener(0, 4) == at_shore)

    synth := ocean_audio.new_synth(57)
    ocean_audio.set_listener_environment(&synth, 0, 0)
    testing.expect(t, math.abs(f64(synth.target_presence - .12)) < 1e-6)
}

@(test)
wind_direction_biases_breaker_approach_and_reverses_backwash :: proc(t: ^testing.T) {
    rightward, leftward := ocean_audio.new_synth(58), ocean_audio.new_synth(58)
    rightward.sea_state, leftward.sea_state = 1, 1
    rightward.target_sea_state, leftward.target_sea_state = 1, 1
    rightward.direction, leftward.direction = 1, -1
    ocean_audio.set_conditions(&rightward, 20, 1, 1)
    ocean_audio.set_conditions(&leftward, 20, 1, -1)
    right_samples, left_samples: [8192]f32
    right_left_energy, right_right_energy := f64(0), f64(0)
    left_left_energy, left_right_energy := f64(0), f64(0)
    rendered := 0
    for rendered < ocean_audio.SAMPLE_RATE * 20 {
        ocean_audio.render(&rightward, right_samples[:])
        ocean_audio.render(&leftward, left_samples[:])
        for frame in 0 ..< len(right_samples) / ocean_audio.CHANNELS {
            right_left_energy += f64(right_samples[frame * 2] * right_samples[frame * 2])
            right_right_energy += f64(right_samples[frame * 2 + 1] * right_samples[frame * 2 + 1])
            left_left_energy += f64(left_samples[frame * 2] * left_samples[frame * 2])
            left_right_energy += f64(left_samples[frame * 2 + 1] * left_samples[frame * 2 + 1])
        }
        rendered += len(right_samples) / ocean_audio.CHANNELS
    }
    testing.expect(t, right_right_energy > right_left_energy * 1.08)
    testing.expect(t, left_left_energy > left_right_energy * 1.08)
    testing.expect(t, rightward.backwash_count > 0)
    testing.expect(t, leftward.backwash_count == rightward.backwash_count)
}

@(test)
high_altitude_ocean_retains_a_quiet_distant_bed :: proc(t: ^testing.T) {
    shore, high := ocean_audio.new_synth(59), ocean_audio.new_synth(59)
    shore.presence, shore.target_presence = 1, 1
    high.presence, high.target_presence = .06, .06
    shore_samples, high_samples: [8192]f32
    ocean_audio.render(&shore, shore_samples[:])
    ocean_audio.render(&high, high_samples[:])

    shore_energy, high_energy := f64(0), f64(0)
    shore_detail, high_detail := f64(0), f64(0)
    for index in 2 ..< len(shore_samples) {
        shore_energy += f64(shore_samples[index] * shore_samples[index])
        high_energy += f64(high_samples[index] * high_samples[index])
        shore_delta := shore_samples[index] - shore_samples[index - 2]
        high_delta := high_samples[index] - high_samples[index - 2]
        shore_detail += f64(shore_delta * shore_delta)
        high_detail += f64(high_delta * high_delta)
    }
    testing.expect(t, high_energy > 0)
    testing.expect(t, shore_energy > high_energy * 80)
    testing.expect(t, shore_detail > high_detail * 200)
}
