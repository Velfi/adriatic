package tests

import wind_audio "../packages/wind_audio"
import "core:math"
import "core:testing"

@(test)
wind_synth_is_deterministic_and_stereo :: proc(t: ^testing.T) {
    a := wind_audio.new_synth(42)
    b := wind_audio.new_synth(42)
    wind_audio.set_strength(&a, 1)
    wind_audio.set_strength(&b, 1)
    a_samples: [4096]f32
    b_samples: [4096]f32
    wind_audio.render(&a, a_samples[:])
    wind_audio.render(&b, b_samples[:])
    testing.expect(t, a_samples == b_samples)

    stereo_difference := f32(0)
    for frame in 0 ..< len(a_samples) / 2 {
        stereo_difference += f32(math.abs(f64(a_samples[frame * 2] - a_samples[frame * 2 + 1])))
    }
    testing.expect(t, stereo_difference > .01)
}

@(test)
wind_synth_strength_controls_output_and_stays_bounded :: proc(t: ^testing.T) {
    silent := wind_audio.new_synth(7)
    loud := wind_audio.new_synth(7)
    wind_audio.set_strength(&loud, 1)
    silent_samples: [8192]f32
    loud_samples: [8192]f32
    wind_audio.render(&silent, silent_samples[:])
    wind_audio.render(&loud, loud_samples[:])

    silent_energy, loud_energy := f64(0), f64(0)
    for index in 0 ..< len(loud_samples) {
        silent_energy += f64(silent_samples[index] * silent_samples[index])
        loud_energy += f64(loud_samples[index] * loud_samples[index])
        testing.expect(t, loud_samples[index] >= -.9 && loud_samples[index] <= .9)
    }
    testing.expect(t, silent_energy == 0)
    testing.expect(t, loud_energy > .01)
}

@(test)
strong_wind_adds_wandering_gust_gated_aeolian_modes :: proc(t: ^testing.T) {
    moderate, whole, chunked := wind_audio.new_synth(9), wind_audio.new_synth(9), wind_audio.new_synth(9)
    moderate.strength, whole.strength, chunked.strength = .5, 1, 1
    wind_audio.set_strength(&moderate, .5)
    wind_audio.set_strength(&whole, 1)
    wind_audio.set_strength(&chunked, 1)
    moderate_samples, whole_samples, chunked_samples: [8192]f32
    wind_audio.render(&moderate, moderate_samples[:])
    wind_audio.render(&whole, whole_samples[:])
    for offset := 0; offset < len(chunked_samples); offset += 506 {
        count := min(506, len(chunked_samples) - offset)
        wind_audio.render(&chunked, chunked_samples[offset:offset + count])
    }

    testing.expect(t, moderate.whistle_mix == 0)
    testing.expect(t, whole.whistle_mix > .01)
    testing.expect(t, whole.whistle_phase_a > 0 && whole.whistle_phase_a < 1)
    testing.expect(t, whole.whistle_phase_b > 0 && whole.whistle_phase_b < 1)
    testing.expect(t, whole_samples == chunked_samples)
    for sample in whole_samples {
        testing.expect(t, sample >= -.9 && sample <= .9)
    }
}

@(test)
wind_gusts_brighten_air_texture_relative_to_lulls :: proc(t: ^testing.T) {
    gust, lull := wind_audio.new_synth(10), wind_audio.new_synth(10)
    gust.strength, gust.target_strength = 1, 1
    lull.strength, lull.target_strength = 1, 1
    gust.gust_phase = math.PI / 2
    lull.gust_phase = math.PI * 3 / 2
    gust_samples, lull_samples: [8192]f32
    wind_audio.render(&gust, gust_samples[:])
    wind_audio.render(&lull, lull_samples[:])
    testing.expect(t, gust.gust_value > lull.gust_value)

    gust_energy, lull_energy := f64(0), f64(0)
    gust_detail, lull_detail := f64(0), f64(0)
    for index in 2 ..< len(gust_samples) {
        gust_energy += f64(gust_samples[index] * gust_samples[index])
        lull_energy += f64(lull_samples[index] * lull_samples[index])
        gust_delta := gust_samples[index] - gust_samples[index - 2]
        lull_delta := lull_samples[index] - lull_samples[index - 2]
        gust_detail += f64(gust_delta * gust_delta)
        lull_detail += f64(lull_delta * lull_delta)
    }
    testing.expect(t, gust_detail / gust_energy > lull_detail / lull_energy)
}

@(test)
wind_airflow_combines_weather_and_motion_without_exceeding_unity :: proc(t: ^testing.T) {
    calm := wind_audio.airflow_strength(0, 0)
    weather := wind_audio.airflow_strength(8, 0)
    motion := wind_audio.airflow_strength(0, 30)
    combined := wind_audio.airflow_strength(8, 30)
    testing.expect(t, calm == 0)
    testing.expect(t, weather > calm)
    testing.expect(t, motion > calm)
    testing.expect(t, combined >= weather && combined >= motion)
    testing.expect(t, combined <= 1)
    testing.expect(t, wind_audio.airflow_strength(100, 100) == 1)
}

@(test)
apparent_airflow_audio_spans_flight_speed_and_respects_tailwind_cancellation :: proc(t: ^testing.T) {
    testing.expect(t, wind_audio.apparent_airflow_strength(0, 0) == 0)
    testing.expect(t, wind_audio.apparent_airflow_strength(12, 0) < .2)
    testing.expect(t, wind_audio.apparent_airflow_strength(30, 0) > .5)
    testing.expect(t, wind_audio.apparent_airflow_strength(52, 0) == 1)

    stationary_weather := wind_audio.apparent_airflow_strength(10, 10)
    matching_tailwind := wind_audio.apparent_airflow_strength(0, 10)
    partial_tailwind := wind_audio.apparent_airflow_strength(2, 10)
    headwind := wind_audio.apparent_airflow_strength(22, 10)
    testing.expect(t, matching_tailwind == 0)
    testing.expect(t, partial_tailwind < stationary_weather)
    testing.expect(t, headwind > stationary_weather)
}

@(test)
wind_audio_update_accepts_clamped_apparent_strength :: proc(t: ^testing.T) {
    runtime := wind_audio.Runtime{synth = wind_audio.new_synth(0x41505041)}
    wind_audio.update(&runtime, 12, 0, direction = -.4, strength_override = .37)
    testing.expect(t, runtime.synth.target_strength == .37)
    testing.expect(t, runtime.synth.target_direction == -.4)

    wind_audio.update(&runtime, 0, 0, strength_override = 2)
    testing.expect(t, runtime.synth.target_strength == 1)
}

@(test)
wind_direction_projects_onto_listener_right_axis :: proc(t: ^testing.T) {
    testing.expect(t, wind_audio.wind_lateral_direction(1, 0, 0) == 1)
    testing.expect(t, wind_audio.wind_lateral_direction(-1, 0, 0) == -1)
    testing.expect(t, math.abs(f64(wind_audio.wind_lateral_direction(0, -1, 0))) < .0001)
    testing.expect(t, math.abs(f64(wind_audio.wind_lateral_direction(1, 0, math.PI / 2))) < .0001)
    testing.expect(t, wind_audio.wind_lateral_direction(0, -1, math.PI / 2) > .999)
    testing.expect(t, wind_audio.wind_lateral_direction(0, 0, 1.2) == 0)
}

@(test)
apparent_wind_direction_includes_listener_motion :: proc(t: ^testing.T) {
    testing.expect(t, wind_audio.apparent_lateral_direction(0, 0, 10, 0, 0) == -1)
    testing.expect(t, wind_audio.apparent_lateral_direction(10, 0, 10, 0, 0) == 0)
    testing.expect(t, wind_audio.apparent_lateral_direction(14, 0, 5, 0, 0) == 1)
    testing.expect(t, wind_audio.apparent_lateral_direction(0, -12, 0, 0, math.PI / 2) > .999)
}

@(test)
apparent_airflow_speed_distinguishes_headwind_and_tailwind :: proc(t: ^testing.T) {
    calm_motion := wind_audio.apparent_airflow_speed(0, 0, 12, 0)
    headwind := wind_audio.apparent_airflow_speed(10, 0, -12, 0)
    tailwind := wind_audio.apparent_airflow_speed(10, 0, 12, 0)
    matching_tailwind := wind_audio.apparent_airflow_speed(12, 0, 12, 0)
    testing.expect(t, calm_motion == 12)
    testing.expect(t, headwind == 22)
    testing.expect(t, tailwind == 2)
    testing.expect(t, matching_tailwind == 0)
    testing.expect(t, wind_audio.airflow_strength(headwind, 0) > wind_audio.airflow_strength(tailwind, 0))
}

@(test)
apparent_airflow_speed_includes_vertical_motion :: proc(t: ^testing.T) {
    level := wind_audio.apparent_airflow_speed(0, 0, 24, 0)
    climbing := wind_audio.apparent_airflow_speed(0, 0, 24, 0, 18)
    testing.expect(t, climbing > level)
    testing.expect(t, math.abs(f64(climbing) - 30) < 0.001)
}

@(test)
directional_wind_biases_stereo_energy_and_smooths_turns :: proc(t: ^testing.T) {
    rightward, leftward := wind_audio.new_synth(13), wind_audio.new_synth(13)
    rightward.strength, leftward.strength = 1, 1
    rightward.direction, leftward.direction = 1, -1
    wind_audio.set_strength(&rightward, 1)
    wind_audio.set_strength(&leftward, 1)
    wind_audio.set_direction(&rightward, 1)
    wind_audio.set_direction(&leftward, -1)
    right_samples, left_samples: [8192]f32
    right_left_energy, right_right_energy := f64(0), f64(0)
    left_left_energy, left_right_energy := f64(0), f64(0)
    total_samples := wind_audio.SAMPLE_RATE * 4
    rendered := 0
    for rendered < total_samples {
        count := min(len(right_samples), total_samples - rendered)
        count -= count % wind_audio.CHANNELS
        wind_audio.render(&rightward, right_samples[:count])
        wind_audio.render(&leftward, left_samples[:count])
        for frame in 0 ..< count / wind_audio.CHANNELS {
            right_left_energy += f64(right_samples[frame * 2] * right_samples[frame * 2])
            right_right_energy += f64(right_samples[frame * 2 + 1] * right_samples[frame * 2 + 1])
            left_left_energy += f64(left_samples[frame * 2] * left_samples[frame * 2])
            left_right_energy += f64(left_samples[frame * 2 + 1] * left_samples[frame * 2 + 1])
        }
        rendered += count
    }
    testing.expect(t, right_right_energy > right_left_energy * 1.1)
    testing.expect(t, left_left_energy > left_right_energy * 1.1)

    previous_direction := rightward.direction
    wind_audio.set_direction(&rightward, -1)
    one_frame: [2]f32
    wind_audio.render(&rightward, one_frame[:])
    testing.expect(t, rightward.direction < previous_direction)
    testing.expect(t, rightward.direction > -1)
}

@(test)
wind_synth_precipitation_adds_deterministic_stereo_rain :: proc(t: ^testing.T) {
    dry, rain, matching := wind_audio.new_synth(17), wind_audio.new_synth(17), wind_audio.new_synth(17)
    wind_audio.set_precipitation(&rain, .9)
    wind_audio.set_precipitation(&matching, .9)
    dry_samples, rain_samples, matching_samples: [wind_audio.SAMPLE_RATE]f32
    wind_audio.render(&dry, dry_samples[:])
    wind_audio.render(&rain, rain_samples[:])
    wind_audio.render(&matching, matching_samples[:])
    testing.expect(t, rain_samples == matching_samples)

    dry_energy, rain_energy, stereo_difference := f64(0), f64(0), f64(0)
    for frame in 0 ..< len(rain_samples) / wind_audio.CHANNELS {
        left, right := rain_samples[frame * 2], rain_samples[frame * 2 + 1]
        dry_energy += f64(
            dry_samples[frame * 2] * dry_samples[frame * 2] + dry_samples[frame * 2 + 1] * dry_samples[frame * 2 + 1],
        )
        rain_energy += f64(left * left + right * right)
        stereo_difference += math.abs(f64(left - right))
        testing.expect(t, left >= -.9 && left <= .9)
        testing.expect(t, right >= -.9 && right <= .9)
    }
    testing.expect(t, dry_energy == 0)
    testing.expect(t, rain_energy > 1)
    testing.expect(t, stereo_difference > 1)
}

@(test)
rain_uses_aperiodic_density_and_heavy_splats :: proc(t: ^testing.T) {
    drizzle, downpour := wind_audio.new_synth(19), wind_audio.new_synth(19)
    drizzle.precipitation, downpour.precipitation = .25, 1
    wind_audio.set_precipitation(&drizzle, .25)
    wind_audio.set_precipitation(&downpour, 1)
    drizzle_samples, downpour_samples: [wind_audio.SAMPLE_RATE]f32
    wind_audio.render(&drizzle, drizzle_samples[:])
    wind_audio.render(&downpour, downpour_samples[:])

    testing.expect(t, drizzle.drop_count > 0)
    testing.expect(t, downpour.drop_count > drizzle.drop_count)
    testing.expect(t, drizzle.heavy_drop_count == 0)
    testing.expect(t, downpour.heavy_drop_count > 0)
    testing.expect(t, downpour.drop_timer > 0)
    testing.expect(t, downpour.heavy_drop_timer > 0)

    drizzle_energy, downpour_energy := f64(0), f64(0)
    for index in 0 ..< len(drizzle_samples) {
        drizzle_energy += f64(drizzle_samples[index] * drizzle_samples[index])
        downpour_energy += f64(downpour_samples[index] * downpour_samples[index])
    }
    testing.expect(t, downpour_energy > drizzle_energy * 2)
}

@(test)
rain_impacts_excite_seeded_inharmonic_surface_modes :: proc(t: ^testing.T) {
    resonant := wind_audio.new_synth(191)
    resonant.precipitation, resonant.target_precipitation = 1, 1
    resonant.drop_timer = 100
    resonant.drop_voices[0] = {
        left      = .8,
        right     = .2,
        frequency = 1_200,
    }
    plain := resonant
    plain.drop_voices[0].left, plain.drop_voices[0].right = 0, 0
    resonant_sample, plain_sample: [wind_audio.CHANNELS]f32
    wind_audio.render(&resonant, resonant_sample[:])
    wind_audio.render(&plain, plain_sample[:])

    expected_a := resonant.drop_voices[0].frequency / wind_audio.SAMPLE_RATE
    expected_b := resonant.drop_voices[0].frequency * 1.613 / wind_audio.SAMPLE_RATE
    testing.expect(t, math.abs(f64(resonant.drop_voices[0].phase_a - expected_a)) < 1e-6)
    testing.expect(t, math.abs(f64(resonant.drop_voices[0].phase_b - expected_b)) < 1e-6)
    left_resonance := resonant_sample[0] - plain_sample[0]
    right_resonance := resonant_sample[1] - plain_sample[1]
    testing.expect(t, left_resonance != 0)
    testing.expect(t, math.abs(f64(left_resonance)) > math.abs(f64(right_resonance)) * 3)
}

@(test)
dense_rain_preserves_overlapping_drop_resonances :: proc(t: ^testing.T) {
    synth := wind_audio.new_synth(193)
    synth.precipitation, synth.target_precipitation = 1, 1
    frame: [wind_audio.CHANNELS]f32
    for _ in 0 ..< wind_audio.RAIN_DROP_VOICE_COUNT {
        synth.drop_timer = 0
        wind_audio.render(&synth, frame[:])
    }

    active_voices := 0
    for voice in synth.drop_voices {
        if voice.left + voice.right > .01 {
            active_voices += 1
            testing.expect(t, voice.phase_a > 0)
            testing.expect(t, voice.frequency >= 780 && voice.frequency <= 2_500)
        }
    }
    testing.expect_value(t, active_voices, wind_audio.RAIN_DROP_VOICE_COUNT)
    testing.expect_value(t, synth.next_drop_voice, 0)
}

@(test)
wind_driven_rain_has_denser_impacts_and_brighter_streaks :: proc(t: ^testing.T) {
    still, squall := wind_audio.new_synth(20), wind_audio.new_synth(20)
    still.precipitation, squall.precipitation = 1, 1
    still.strength, squall.strength = 0, 1
    wind_audio.set_precipitation(&still, 1)
    wind_audio.set_precipitation(&squall, 1)
    wind_audio.set_strength(&still, 0)
    wind_audio.set_strength(&squall, 1)
    still_samples, squall_samples: [wind_audio.SAMPLE_RATE]f32
    wind_audio.render(&still, still_samples[:])
    wind_audio.render(&squall, squall_samples[:])

    testing.expect(t, squall.drop_count > still.drop_count)
    testing.expect(t, squall.heavy_drop_count > still.heavy_drop_count)
    still_detail, squall_detail := f64(0), f64(0)
    for index in 2 ..< len(still_samples) {
        still_delta := still_samples[index] - still_samples[index - 2]
        squall_delta := squall_samples[index] - squall_samples[index - 2]
        still_detail += f64(still_delta * still_delta)
        squall_detail += f64(squall_delta * squall_delta)
        testing.expect(t, squall_samples[index] >= -.9 && squall_samples[index] <= .9)
    }
    testing.expect(t, squall_detail > still_detail * 1.2)
}

@(test)
crosswind_biases_rain_impacts_toward_leeward_channel :: proc(t: ^testing.T) {
    rightward, leftward := wind_audio.new_synth(21), wind_audio.new_synth(21)
    rightward.precipitation, leftward.precipitation = 1, 1
    rightward.direction, leftward.direction = 1, -1
    wind_audio.set_precipitation(&rightward, 1)
    wind_audio.set_precipitation(&leftward, 1)
    wind_audio.set_direction(&rightward, 1)
    wind_audio.set_direction(&leftward, -1)
    right_samples, left_samples: [8192]f32
    right_left_energy, right_right_energy := f64(0), f64(0)
    left_left_energy, left_right_energy := f64(0), f64(0)
    rendered := 0
    for rendered < wind_audio.SAMPLE_RATE * 4 {
        wind_audio.render(&rightward, right_samples[:])
        wind_audio.render(&leftward, left_samples[:])
        for frame in 0 ..< len(right_samples) / wind_audio.CHANNELS {
            right_left_energy += f64(right_samples[frame * 2] * right_samples[frame * 2])
            right_right_energy += f64(right_samples[frame * 2 + 1] * right_samples[frame * 2 + 1])
            left_left_energy += f64(left_samples[frame * 2] * left_samples[frame * 2])
            left_right_energy += f64(left_samples[frame * 2 + 1] * left_samples[frame * 2 + 1])
        }
        rendered += len(right_samples) / wind_audio.CHANNELS
    }
    testing.expect(t, right_right_energy > right_left_energy * 1.12)
    testing.expect(t, left_left_energy > left_right_energy * 1.12)
}

@(test)
wind_synth_thunder_is_deterministic_spatial_and_bounded :: proc(t: ^testing.T) {
    a, b := wind_audio.new_synth(23), wind_audio.new_synth(23)
    a.storm_severity, b.storm_severity = 1, 1
    wind_audio.set_storm_severity(&a, 1)
    wind_audio.set_storm_severity(&b, 1)
    wind_audio.trigger_thunder(&a, .9)
    wind_audio.trigger_thunder(&b, .9)
    a_samples, b_samples: [wind_audio.SAMPLE_RATE]f32
    wind_audio.render(&a, a_samples[:])
    wind_audio.render(&b, b_samples[:])
    testing.expect(t, a_samples == b_samples)

    energy, stereo_difference := f64(0), f64(0)
    for frame in 0 ..< len(a_samples) / wind_audio.CHANNELS {
        left, right := a_samples[frame * 2], a_samples[frame * 2 + 1]
        energy += f64(left * left + right * right)
        stereo_difference += math.abs(f64(left - right))
        testing.expect(t, left >= -.9 && left <= .9)
        testing.expect(t, right >= -.9 && right <= .9)
    }
    testing.expect(t, energy > .1)
    testing.expect(t, stereo_difference > .01)
}

@(test)
severe_storm_arms_a_seeded_delay_before_first_thunder :: proc(t: ^testing.T) {
    synth := wind_audio.new_synth(29)
    wind_audio.set_storm_severity(&synth, 1)
    samples: [wind_audio.SAMPLE_RATE]f32
    wind_audio.render(&synth, samples[:])
    testing.expect(t, synth.storm_thunder_armed)
    testing.expect(t, synth.thunder_duration == 0)
    testing.expect(t, synth.thunder_timer > 0)

    chunk: [4096]f32
    rendered := 0
    for synth.thunder_duration <= 0 && rendered < wind_audio.SAMPLE_RATE * 12 {
        wind_audio.render(&synth, chunk[:])
        rendered += len(chunk) / wind_audio.CHANNELS
    }
    testing.expect(t, synth.thunder_duration > 0)
    testing.expect(t, rendered >= wind_audio.SAMPLE_RATE)
}

@(test)
clearing_storm_disarms_pending_thunder :: proc(t: ^testing.T) {
    synth := wind_audio.new_synth(30)
    synth.storm_severity = 1
    wind_audio.set_storm_severity(&synth, 1)
    samples: [2]f32
    wind_audio.render(&synth, samples[:])
    testing.expect(t, synth.storm_thunder_armed)

    synth.storm_severity = 0
    wind_audio.set_storm_severity(&synth, 0)
    wind_audio.render(&synth, samples[:])
    testing.expect(t, !synth.storm_thunder_armed)
    testing.expect(t, synth.thunder_timer == 0)
}

@(test)
wind_mute_preserves_weather_and_pending_thunder_state :: proc(t: ^testing.T) {
    synth := wind_audio.new_synth(33)
    synth.strength, synth.precipitation, synth.storm_severity = .8, .9, 1
    wind_audio.set_strength(&synth, .8)
    wind_audio.set_precipitation(&synth, .9)
    wind_audio.set_storm_severity(&synth, 1)
    samples: [4096]f32
    wind_audio.render(&synth, samples[:])
    testing.expect(t, synth.storm_thunder_armed)
    thunder_timer_before_mute := synth.thunder_timer

    wind_audio.set_muted(&synth, true)
    for _ in 0 ..< 12 do wind_audio.render(&synth, samples[:])
    testing.expect(t, synth.mute_gain < .001)
    testing.expect(t, synth.target_strength == .8)
    testing.expect(t, synth.target_precipitation == .9)
    testing.expect(t, synth.target_storm_severity == 1)
    testing.expect(t, synth.storm_thunder_armed)
    testing.expect(t, synth.thunder_timer < thunder_timer_before_mute)

    wind_audio.set_muted(&synth, false)
    previous_gain := synth.mute_gain
    wind_audio.render(&synth, samples[:])
    testing.expect(t, synth.mute_gain > previous_gain)
    testing.expect(t, synth.storm_thunder_armed)
}

@(test)
thunder_has_seeded_ordered_spatial_reflections :: proc(t: ^testing.T) {
    a, b := wind_audio.new_synth(31), wind_audio.new_synth(31)
    a.storm_severity, b.storm_severity = 1, 1
    wind_audio.set_storm_severity(&a, 1)
    wind_audio.set_storm_severity(&b, 1)
    wind_audio.trigger_thunder(&a, .85)
    wind_audio.trigger_thunder(&b, .85)

    testing.expect(t, a.thunder_echo_delay_a > 0)
    testing.expect(t, a.thunder_echo_delay_b > a.thunder_echo_delay_a)
    testing.expect(t, abs(a.thunder_echo_pan_a) <= .85)
    testing.expect(t, abs(a.thunder_echo_pan_b) <= .85)
    testing.expect(t, a.thunder_echo_delay_a == b.thunder_echo_delay_a)
    testing.expect(t, a.thunder_echo_delay_b == b.thunder_echo_delay_b)
    testing.expect(t, a.thunder_echo_pan_a == b.thunder_echo_pan_a)
    testing.expect(t, a.thunder_echo_pan_b == b.thunder_echo_pan_b)
}

@(test)
thunder_distance_darkens_crack_and_extends_rumble :: proc(t: ^testing.T) {
    near, far := wind_audio.new_synth(35), wind_audio.new_synth(35)
    near.storm_severity, far.storm_severity = 1, 1
    wind_audio.set_storm_severity(&near, 1)
    wind_audio.set_storm_severity(&far, 1)
    wind_audio.trigger_thunder(&near, .9, 0)
    wind_audio.trigger_thunder(&far, .9, 1)
    near_samples, far_samples: [wind_audio.SAMPLE_RATE]f32
    wind_audio.render(&near, near_samples[:])
    wind_audio.render(&far, far_samples[:])

    testing.expect(t, near.thunder_distance == 0)
    testing.expect(t, far.thunder_distance == 1)
    testing.expect(t, far.thunder_duration > near.thunder_duration)
    testing.expect(t, far.thunder_echo_delay_a > near.thunder_echo_delay_a)
    testing.expect(t, far.thunder_echo_delay_b > near.thunder_echo_delay_b)

    near_detail, far_detail := f64(0), f64(0)
    for index in 2 ..< len(near_samples) {
        near_delta := near_samples[index] - near_samples[index - 2]
        far_delta := far_samples[index] - far_samples[index - 2]
        near_detail += f64(near_delta * near_delta)
        far_detail += f64(far_delta * far_delta)
    }
    testing.expect(t, near_detail > far_detail * 1.5)
}

@(test)
rolling_thunder_remains_deterministic_across_callback_chunks :: proc(t: ^testing.T) {
    whole, chunked := wind_audio.new_synth(37), wind_audio.new_synth(37)
    whole.storm_severity, chunked.storm_severity = 1, 1
    wind_audio.set_storm_severity(&whole, 1)
    wind_audio.set_storm_severity(&chunked, 1)
    wind_audio.trigger_thunder(&whole, .92)
    wind_audio.trigger_thunder(&chunked, .92)
    whole_samples, chunked_samples: [8192]f32
    late_energy := f64(0)
    total_samples := wind_audio.SAMPLE_RATE * 2
    rendered := 0
    for rendered < total_samples {
        count := min(len(whole_samples), total_samples - rendered)
        count -= count % wind_audio.CHANNELS
        wind_audio.render(&whole, whole_samples[:count])
        for offset := 0; offset < count; offset += 510 {
            chunk_count := min(510, count - offset)
            wind_audio.render(&chunked, chunked_samples[offset:offset + chunk_count])
        }
        for index in 0 ..< count {
            testing.expect(t, whole_samples[index] == chunked_samples[index])
            if rendered + index >= wind_audio.SAMPLE_RATE {
                late_energy += f64(whole_samples[index] * whole_samples[index])
            }
        }
        rendered += count
    }
    testing.expect(t, late_energy > .01)
}

@(test)
wind_synth_render_is_deterministic_across_callback_chunks :: proc(t: ^testing.T) {
    whole, chunked := wind_audio.new_synth(29), wind_audio.new_synth(29)
    whole_samples, chunked_samples: [4096]f32
    wind_audio.set_strength(&whole, .82)
    wind_audio.set_strength(&chunked, .82)
    wind_audio.render(&whole, whole_samples[:])
    for offset := 0; offset < len(chunked_samples); offset += 254 {
        count := min(254, len(chunked_samples) - offset)
        wind_audio.render(&chunked, chunked_samples[offset:offset + count])
    }
    testing.expect(t, whole_samples == chunked_samples)
}

@(test)
wind_filter_coefficients_preserve_real_time_decay_across_sample_rates :: proc(t: ^testing.T) {
    reference := f32(.047)
    at_24k := wind_audio.coefficient_for_sample_rate(reference, 24_000)
    at_48k := wind_audio.coefficient_for_sample_rate(reference, 48_000)
    at_96k := wind_audio.coefficient_for_sample_rate(reference, 96_000)
    testing.expect(t, math.abs(f64(at_48k - reference)) < 1e-7)

    residual_24k := math.pow(f64(1 - at_24k), 240)
    residual_48k := math.pow(f64(1 - at_48k), 480)
    residual_96k := math.pow(f64(1 - at_96k), 960)
    testing.expect(t, math.abs(residual_24k - residual_48k) < 1e-5)
    testing.expect(t, math.abs(residual_48k - residual_96k) < 1e-5)
}
