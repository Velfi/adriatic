package tests

import spray_audio "../packages/spray_audio"
import "core:math"
import "core:testing"

@(test)
spray_synth_is_deterministic_stereo_and_bounded :: proc(t: ^testing.T) {
    a := spray_audio.new_synth(42)
    b := spray_audio.new_synth(42)
    spray_audio.set_active(&a, true, .8)
    spray_audio.set_active(&b, true, .8)
    a_samples, b_samples: [spray_audio.SAMPLE_RATE]f32
    spray_audio.render(&a, a_samples[:])
    spray_audio.render(&b, b_samples[:])
    testing.expect(t, a_samples == b_samples)

    energy, stereo_difference := f64(0), f64(0)
    for frame in 0 ..< len(a_samples) / 2 {
        left, right := a_samples[frame * 2], a_samples[frame * 2 + 1]
        energy += f64(left * left + right * right)
        stereo_difference += math.abs(f64(left - right))
        testing.expect(t, abs(left) < 1 && abs(right) < 1)
    }
    testing.expect(t, energy > 1)
    testing.expect(t, stereo_difference > 1)
}

@(test)
spray_synth_has_click_free_attack_and_release :: proc(t: ^testing.T) {
    synth := spray_audio.new_synth(7)
    samples: [2]f32
    spray_audio.set_active(&synth, true)
    spray_audio.render(&synth, samples[:])
    testing.expect(t, synth.level > 0 && synth.level < 1)

    for _ in 0 ..< spray_audio.SAMPLE_RATE / 4 {
        spray_audio.render(&synth, samples[:])
    }
    testing.expect(t, synth.level > .99)
    before_release := synth.level
    spray_audio.set_active(&synth, false)
    spray_audio.render(&synth, samples[:])
    testing.expect(t, synth.level > 0 && synth.level < before_release)

    for _ in 0 ..< spray_audio.SAMPLE_RATE / 2 {
        spray_audio.render(&synth, samples[:])
    }
    testing.expect(t, synth.level < .001)
}

@(test)
spray_synth_intensity_increases_bright_detail :: proc(t: ^testing.T) {
    low, high := spray_audio.new_synth(23), spray_audio.new_synth(23)
    low_samples, high_samples: [spray_audio.SAMPLE_RATE]f32
    spray_audio.set_active(&low, true, .05)
    spray_audio.set_active(&high, true, 1)
    spray_audio.render(&low, low_samples[:])
    spray_audio.render(&high, high_samples[:])

    low_detail, high_detail := f64(0), f64(0)
    for index in 2 ..< len(low_samples) {
        low_delta := low_samples[index] - low_samples[index - 2]
        high_delta := high_samples[index] - high_samples[index - 2]
        low_detail += f64(low_delta * low_delta)
        high_detail += f64(high_delta * high_delta)
    }
    testing.expect(t, high_detail > low_detail * 1.4)
}

@(test)
spray_synth_render_is_deterministic_across_callback_chunks :: proc(t: ^testing.T) {
    whole, chunked := spray_audio.new_synth(31), spray_audio.new_synth(31)
    whole_samples, chunked_samples: [4096]f32
    spray_audio.set_active(&whole, true, .76)
    spray_audio.set_active(&chunked, true, .76)
    spray_audio.render(&whole, whole_samples[:])
    for offset := 0; offset < len(chunked_samples); offset += 258 {
        count := min(258, len(chunked_samples) - offset)
        spray_audio.render(&chunked, chunked_samples[offset:offset + count])
    }
    testing.expect(t, whole_samples == chunked_samples)
}

@(test)
spray_filter_coefficients_preserve_real_time_decay_across_sample_rates :: proc(t: ^testing.T) {
    reference := f32(.11)
    at_24k := spray_audio.coefficient_for_sample_rate(reference, 24_000)
    at_48k := spray_audio.coefficient_for_sample_rate(reference, 48_000)
    at_96k := spray_audio.coefficient_for_sample_rate(reference, 96_000)
    testing.expect(t, math.abs(f64(at_48k - reference)) < 1e-7)

    residual_24k := math.pow(f64(1 - at_24k), 240)
    residual_48k := math.pow(f64(1 - at_48k), 480)
    residual_96k := math.pow(f64(1 - at_96k), 960)
    testing.expect(t, math.abs(residual_24k - residual_48k) < 1e-5)
    testing.expect(t, math.abs(residual_48k - residual_96k) < 1e-5)
}

@(test)
spray_valve_transients_trigger_once_per_activation_edge :: proc(t: ^testing.T) {
    synth := spray_audio.new_synth(43)
    samples: [2]f32
    spray_audio.set_active(&synth, true, .8)
    testing.expect(t, synth.onset_level == 1)
    testing.expect(t, synth.release_level == 0)
    spray_audio.render(&synth, samples[:])
    decayed_onset := synth.onset_level
    spray_audio.set_active(&synth, true, .8)
    testing.expect(t, synth.onset_level == decayed_onset)

    spray_audio.set_active(&synth, false, .8)
    testing.expect(t, synth.release_level > 0)
    testing.expect(t, synth.onset_level == 0)
    decayed_release := synth.release_level
    spray_audio.set_active(&synth, false, .8)
    testing.expect(t, synth.release_level == decayed_release)
}

@(test)
spray_mute_fades_without_creating_valve_edges :: proc(t: ^testing.T) {
    synth := spray_audio.new_synth(45)
    samples: [4096]f32
    spray_audio.set_active(&synth, true, .8)
    spray_audio.render(&synth, samples[:])
    onset_before_mute := synth.onset_level
    testing.expect(t, synth.active)
    testing.expect(t, synth.release_level == 0)

    spray_audio.set_muted(&synth, true)
    for _ in 0 ..< 12 do spray_audio.render(&synth, samples[:])
    testing.expect(t, synth.mute_gain < .001)
    testing.expect(t, synth.active)
    testing.expect(t, synth.release_level == 0)
    testing.expect(t, synth.onset_level < onset_before_mute)

    spray_audio.set_active(&synth, true, .8)
    testing.expect(t, synth.onset_level == 0)
    spray_audio.set_muted(&synth, false)
    previous_gain := synth.mute_gain
    spray_audio.render(&synth, samples[:])
    testing.expect(t, synth.mute_gain > previous_gain)
    testing.expect(t, synth.release_level == 0)
}

@(test)
spray_release_has_a_bounded_nozzle_sputter_tail :: proc(t: ^testing.T) {
    sputter, envelope_only := spray_audio.new_synth(47), spray_audio.new_synth(47)
    warmup_a, warmup_b: [spray_audio.SAMPLE_RATE]f32
    spray_audio.set_active(&sputter, true, .75)
    spray_audio.set_active(&envelope_only, true, .75)
    spray_audio.render(&sputter, warmup_a[:])
    spray_audio.render(&envelope_only, warmup_b[:])
    testing.expect(t, warmup_a == warmup_b)

    spray_audio.set_active(&sputter, false, .75)
    envelope_only.active = false
    envelope_only.target_level = 0
    sputter_samples, envelope_samples: [4096]f32
    spray_audio.render(&sputter, sputter_samples[:])
    spray_audio.render(&envelope_only, envelope_samples[:])

    sputter_energy, envelope_energy := f64(0), f64(0)
    for index in 0 ..< len(sputter_samples) {
        sputter_energy += f64(sputter_samples[index] * sputter_samples[index])
        envelope_energy += f64(envelope_samples[index] * envelope_samples[index])
        testing.expect(t, abs(sputter_samples[index]) < 1)
    }
    testing.expect(t, sputter_energy > envelope_energy)
}

@(test)
sustained_spray_pressure_sags_and_recovers_at_rest :: proc(t: ^testing.T) {
    synth := spray_audio.new_synth(53)
    samples: [4096]f32
    spray_audio.set_active(&synth, true, 1)
    rendered_frames := 0
    for rendered_frames < spray_audio.SAMPLE_RATE * 10 {
        spray_audio.render(&synth, samples[:])
        rendered_frames += len(samples) / spray_audio.CHANNELS
    }
    testing.expect(t, synth.can_pressure < .78)
    testing.expect(t, synth.can_pressure > .67)

    sagged_pressure := synth.can_pressure
    spray_audio.set_active(&synth, false, 1)
    rendered_frames = 0
    for rendered_frames < spray_audio.SAMPLE_RATE * 6 {
        spray_audio.render(&synth, samples[:])
        rendered_frames += len(samples) / spray_audio.CHANNELS
    }
    testing.expect(t, synth.can_pressure > sagged_pressure)
    testing.expect(t, synth.can_pressure > .95)
}

@(test)
depleted_spray_can_adds_seeded_nozzle_sputters :: proc(t: ^testing.T) {
    fresh, depleted, chunked := spray_audio.new_synth(57), spray_audio.new_synth(57), spray_audio.new_synth(57)
    spray_audio.set_active(&fresh, true, 1)
    spray_audio.set_active(&depleted, true, 1)
    spray_audio.set_active(&chunked, true, 1)
    fresh.level, depleted.level, chunked.level = 1, 1, 1
    fresh.intensity, depleted.intensity, chunked.intensity = 1, 1, 1
    fresh.onset_level, depleted.onset_level, chunked.onset_level = 0, 0, 0
    depleted.can_pressure, chunked.can_pressure = .68, .68

    fresh_samples, depleted_samples, chunked_samples: [16_384]f32
    spray_audio.render(&fresh, fresh_samples[:])
    spray_audio.render(&depleted, depleted_samples[:])
    for offset := 0; offset < len(chunked_samples); offset += 514 {
        count := min(514, len(chunked_samples) - offset)
        spray_audio.render(&chunked, chunked_samples[offset:offset + count])
    }

    testing.expect(t, fresh.sputter_count == 0)
    testing.expect(t, depleted.sputter_count >= 1)
    testing.expect(t, depleted.sputter_count == chunked.sputter_count)
    testing.expect(t, depleted_samples == chunked_samples)
    for sample in depleted_samples {
        testing.expect(t, abs(sample) < 1)
    }
}

@(test)
lower_can_pressure_softens_and_reduces_sustained_spray :: proc(t: ^testing.T) {
    full, sagged := spray_audio.new_synth(59), spray_audio.new_synth(59)
    spray_audio.set_active(&full, true, 1)
    spray_audio.set_active(&sagged, true, 1)
    full.level, sagged.level = 1, 1
    full.intensity, sagged.intensity = 1, 1
    full.onset_level, sagged.onset_level = 0, 0
    full.can_pressure = 1
    sagged.can_pressure = .68
    full_samples, sagged_samples: [spray_audio.SAMPLE_RATE]f32
    spray_audio.render(&full, full_samples[:])
    spray_audio.render(&sagged, sagged_samples[:])

    full_energy, sagged_energy := f64(0), f64(0)
    for index in 0 ..< len(full_samples) {
        full_energy += f64(full_samples[index] * full_samples[index])
        sagged_energy += f64(sagged_samples[index] * sagged_samples[index])
        testing.expect(t, abs(full_samples[index]) < 1)
        testing.expect(t, abs(sagged_samples[index]) < 1)
    }
    testing.expect(t, full_energy > sagged_energy * 1.1)
}

@(test)
strong_atomization_widens_the_aerosol_plume :: proc(t: ^testing.T) {
    narrow, wide := spray_audio.new_synth(60), spray_audio.new_synth(60)
    spray_audio.set_active(&narrow, true, .05)
    spray_audio.set_active(&wide, true, 1)
    narrow.intensity, wide.intensity = .05, 1
    narrow_samples, wide_samples: [spray_audio.SAMPLE_RATE]f32
    spray_audio.render(&narrow, narrow_samples[:])
    spray_audio.render(&wide, wide_samples[:])

    testing.expect(t, wide.aerosol_spread > narrow.aerosol_spread * 2)
    narrow_side, wide_side := f64(0), f64(0)
    narrow_mid, wide_mid := f64(0), f64(0)
    for frame in 0 ..< len(narrow_samples) / spray_audio.CHANNELS {
        narrow_left, narrow_right := narrow_samples[frame * 2], narrow_samples[frame * 2 + 1]
        wide_left, wide_right := wide_samples[frame * 2], wide_samples[frame * 2 + 1]
        narrow_side += f64((narrow_left - narrow_right) * (narrow_left - narrow_right))
        wide_side += f64((wide_left - wide_right) * (wide_left - wide_right))
        narrow_mid += f64((narrow_left + narrow_right) * (narrow_left + narrow_right))
        wide_mid += f64((wide_left + wide_right) * (wide_left + wide_right))
    }
    testing.expect(t, wide_side / wide_mid > narrow_side / narrow_mid * 2)
}

@(test)
spray_pan_tracks_cursor_direction_and_moves_smoothly :: proc(t: ^testing.T) {
    left, right := spray_audio.new_synth(61), spray_audio.new_synth(61)
    spray_audio.set_active(&left, true, .8, -1)
    spray_audio.set_active(&right, true, .8, 1)
    left.pan, right.pan = -1, 1

    left_samples, right_samples: [8192]f32
    spray_audio.render(&left, left_samples[:])
    spray_audio.render(&right, right_samples[:])
    left_left_energy, left_right_energy := f64(0), f64(0)
    right_left_energy, right_right_energy := f64(0), f64(0)
    for frame in 0 ..< len(left_samples) / spray_audio.CHANNELS {
        left_left_energy += f64(left_samples[frame * 2] * left_samples[frame * 2])
        left_right_energy += f64(left_samples[frame * 2 + 1] * left_samples[frame * 2 + 1])
        right_left_energy += f64(right_samples[frame * 2] * right_samples[frame * 2])
        right_right_energy += f64(right_samples[frame * 2 + 1] * right_samples[frame * 2 + 1])
    }
    testing.expect(t, left_left_energy > left_right_energy * 1.5)
    testing.expect(t, right_right_energy > right_left_energy * 1.5)

    previous_pan := right.pan
    spray_audio.set_active(&right, true, .8, -5)
    transition: [2]f32
    spray_audio.render(&right, transition[:])
    testing.expect(t, right.target_pan == -1)
    testing.expect(t, right.pan < previous_pan)
    testing.expect(t, right.pan > -1)
}
