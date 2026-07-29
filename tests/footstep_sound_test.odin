package tests

import engine_sound "../packages/engine_sound"
import "core:math"
import "core:testing"

@(test)
footstep_phase_detects_half_stride_and_wrap_contacts :: proc(t: ^testing.T) {
    testing.expect(t, engine_sound.footstep_phase_crossed(3.0, 3.2))
    testing.expect(t, engine_sound.footstep_phase_crossed(6.1, .1))
    testing.expect(t, !engine_sound.footstep_phase_crossed(.2, 2.8))
}

@(test)
footstep_surfaces_are_deterministic_distinct_and_decay :: proc(t: ^testing.T) {
    grass, matching, stone :=
        engine_sound.new_footstep(37), engine_sound.new_footstep(37), engine_sound.new_footstep(37)
    grass_samples, matching_samples, stone_samples: [engine_sound.SAMPLE_RATE / 4]f32
    engine_sound.trigger_footstep(&grass, .8, .Grass)
    engine_sound.trigger_footstep(&matching, .8, .Grass)
    engine_sound.trigger_footstep(&stone, .8, .Cobblestone)
    engine_sound.render_footstep_add(&grass, grass_samples[:])
    engine_sound.render_footstep_add(&matching, matching_samples[:])
    engine_sound.render_footstep_add(&stone, stone_samples[:])

    testing.expect(t, grass_samples == matching_samples)
    testing.expect(t, grass_samples != stone_samples)
    testing.expect(t, grass.duration == 0)
    testing.expect(t, stone.duration == 0)
}

@(test)
footstep_intensity_controls_energy :: proc(t: ^testing.T) {
    quiet, loud := engine_sound.new_footstep(43), engine_sound.new_footstep(43)
    quiet_samples, loud_samples: [4096]f32
    engine_sound.trigger_footstep(&quiet, .2, .Gravel)
    engine_sound.trigger_footstep(&loud, 1, .Gravel)
    engine_sound.render_footstep_add(&quiet, quiet_samples[:])
    engine_sound.render_footstep_add(&loud, loud_samples[:])

    quiet_energy, loud_energy := f32(0), f32(0)
    for index in 0 ..< len(quiet_samples) {
        quiet_energy += quiet_samples[index] * quiet_samples[index]
        loud_energy += loud_samples[index] * loud_samples[index]
    }
    testing.expect(t, loud_energy > quiet_energy * 10)
}

@(test)
landing_contact_has_more_body_and_a_longer_tail :: proc(t: ^testing.T) {
    step, landing := engine_sound.new_footstep(47), engine_sound.new_footstep(47)
    step_samples, landing_samples: [4096]f32
    engine_sound.trigger_footstep(&step, .7, .Dirt)
    engine_sound.trigger_footstep(&landing, .7, .Dirt, true)
    step_duration, landing_duration := step.duration, landing.duration
    engine_sound.render_footstep_add(&step, step_samples[:])
    engine_sound.render_footstep_add(&landing, landing_samples[:])

    step_energy, landing_energy := f32(0), f32(0)
    for index in 0 ..< len(step_samples) {
        step_energy += step_samples[index] * step_samples[index]
        landing_energy += landing_samples[index] * landing_samples[index]
    }
    testing.expect(t, landing_duration > step_duration)
    testing.expect(t, landing_energy > step_energy * 1.2)
}

@(test)
fast_landing_adds_delayed_surface_skid :: proc(t: ^testing.T) {
    vertical, sliding := engine_sound.new_footstep(53), engine_sound.new_footstep(53)
    engine_sound.trigger_footstep(&vertical, .8, .Asphalt, true, 0, 0)
    engine_sound.trigger_footstep(&sliding, .8, .Asphalt, true, 0, 1)
    testing.expect(t, vertical.landing_slide == 0)
    testing.expect(t, sliding.landing_slide == 1)
    testing.expect(t, sliding.duration > vertical.duration)
    without_skid := sliding
    without_skid.landing_slide = 0
    plain_samples, sliding_samples: [engine_sound.SAMPLE_RATE / 3]f32
    engine_sound.render_footstep_add(&without_skid, plain_samples[:])
    engine_sound.render_footstep_add(&sliding, sliding_samples[:])

    skid_start := int(.025 * engine_sound.SAMPLE_RATE)
    for index in 0 ..< skid_start {
        testing.expect(t, plain_samples[index] == sliding_samples[index])
    }
    difference := f64(0)
    for index in skid_start + 1 ..< len(sliding_samples) {
        difference += math.abs(f64(sliding_samples[index] - plain_samples[index]))
    }
    testing.expect(t, difference > 10)
}

@(test)
footstep_has_deterministic_delayed_heel_to_toe_contact :: proc(t: ^testing.T) {
    first, matching := engine_sound.new_footstep(59), engine_sound.new_footstep(59)
    first_samples, matching_samples: [engine_sound.SAMPLE_RATE / 4]f32
    engine_sound.trigger_footstep(&first, .75, .Cobblestone)
    engine_sound.trigger_footstep(&matching, .75, .Cobblestone)
    toe_sample := int(first.toe_delay * engine_sound.SAMPLE_RATE)
    testing.expect(t, first.toe_delay > .04 && first.toe_delay < .08)
    testing.expect(t, first.toe_hz > first.tap_hz)

    engine_sound.render_footstep_add(&first, first_samples[:])
    engine_sound.render_footstep_add(&matching, matching_samples[:])
    testing.expect(t, first_samples == matching_samples)

    before_energy, after_energy := f32(0), f32(0)
    window := engine_sound.SAMPLE_RATE / 200
    for index in toe_sample - window ..< toe_sample {
        before_energy += first_samples[index] * first_samples[index]
    }
    for index in toe_sample ..< toe_sample + window {
        after_energy += first_samples[index] * first_samples[index]
    }
    testing.expect(t, after_energy > before_energy)
}

@(test)
soft_surface_toe_contact_emphasizes_scuff_over_tap :: proc(t: ^testing.T) {
    sand, stone := engine_sound.new_footstep(61), engine_sound.new_footstep(61)
    sand_samples, stone_samples: [engine_sound.SAMPLE_RATE / 4]f32
    engine_sound.trigger_footstep(&sand, .7, .Sand)
    engine_sound.trigger_footstep(&stone, .7, .Cobblestone)
    engine_sound.render_footstep_add(&sand, sand_samples[:])
    engine_sound.render_footstep_add(&stone, stone_samples[:])

    testing.expect(t, sand.grit > stone.grit)
    testing.expect(t, sand.hardness < stone.hardness)
    testing.expect(t, sand_samples != stone_samples)
}

@(test)
loose_surfaces_produce_deterministic_density_controlled_micro_grains :: proc(t: ^testing.T) {
    gravel, matching, asphalt :=
        engine_sound.new_footstep(63), engine_sound.new_footstep(63), engine_sound.new_footstep(63)
    gravel_samples, matching_samples, asphalt_samples: [engine_sound.SAMPLE_RATE / 4]f32
    engine_sound.trigger_footstep(&gravel, .8, .Gravel)
    engine_sound.trigger_footstep(&matching, .8, .Gravel)
    engine_sound.trigger_footstep(&asphalt, .8, .Asphalt)
    engine_sound.render_footstep_add(&gravel, gravel_samples[:])
    engine_sound.render_footstep_add(&matching, matching_samples[:])
    engine_sound.render_footstep_add(&asphalt, asphalt_samples[:])

    testing.expect(t, gravel_samples == matching_samples)
    testing.expect(t, gravel.grain_count == matching.grain_count)
    testing.expect(t, gravel.grain_count > asphalt.grain_count * 5)
    testing.expect(t, gravel.grain_count >= 8)
}

@(test)
loose_surface_grains_use_aperiodic_seeded_intervals :: proc(t: ^testing.T) {
    first, matching := engine_sound.new_footstep(65), engine_sound.new_footstep(65)
    engine_sound.trigger_footstep(&first, 1, .Gravel)
    engine_sound.trigger_footstep(&matching, 1, .Gravel)
    event_samples: [32]int
    event_count := 0
    previous_count := u32(0)
    first_sample, matching_sample: [1]f32
    for sample_index in 0 ..< engine_sound.SAMPLE_RATE / 4 {
        engine_sound.render_footstep_add(&first, first_sample[:])
        engine_sound.render_footstep_add(&matching, matching_sample[:])
        testing.expect(t, first_sample == matching_sample)
        if first.grain_count != previous_count {
            event_samples[event_count] = sample_index
            event_count += 1
            previous_count = first.grain_count
        }
    }

    testing.expect(t, event_count >= 8)
    distinct_intervals := 0
    reference_interval := event_samples[1] - event_samples[0]
    for index in 2 ..< event_count {
        interval := event_samples[index] - event_samples[index - 1]
        if interval != reference_interval do distinct_intervals += 1
    }
    testing.expect(t, distinct_intervals >= event_count / 2)
    testing.expect(t, first.grain_count == matching.grain_count)
}

@(test)
wet_footsteps_add_surface_appropriate_water_contact :: proc(t: ^testing.T) {
    dry, wet_asphalt, wet_dirt :=
        engine_sound.new_footstep(67), engine_sound.new_footstep(67), engine_sound.new_footstep(67)
    dry_samples, asphalt_samples, dirt_samples: [engine_sound.SAMPLE_RATE / 4]f32
    engine_sound.trigger_footstep(&dry, .8, .Asphalt)
    engine_sound.trigger_footstep(&wet_asphalt, .8, .Asphalt, false, 1)
    engine_sound.trigger_footstep(&wet_dirt, .8, .Dirt, false, 1)
    engine_sound.render_footstep_add(&dry, dry_samples[:])
    engine_sound.render_footstep_add(&wet_asphalt, asphalt_samples[:])
    engine_sound.render_footstep_add(&wet_dirt, dirt_samples[:])

    testing.expect(t, wet_asphalt.wetness == 1)
    testing.expect(t, asphalt_samples != dry_samples)
    testing.expect(t, dirt_samples != asphalt_samples)
    testing.expect(t, wet_dirt.hardness < wet_asphalt.hardness)
    for index in 0 ..< len(asphalt_samples) {
        testing.expect(t, abs(asphalt_samples[index]) < 2)
        testing.expect(t, abs(dirt_samples[index]) < 2)
    }
}

@(test)
footstep_wetness_is_clamped_and_extends_water_tail :: proc(t: ^testing.T) {
    dry, wet := engine_sound.new_footstep(71), engine_sound.new_footstep(71)
    engine_sound.trigger_footstep(&dry, .7, .Grass)
    engine_sound.trigger_footstep(&wet, .7, .Grass, false, 4)
    testing.expect(t, wet.wetness == 1)
    testing.expect(t, wet.duration > dry.duration)
}

@(test)
footstep_mixer_preserves_landing_tail_under_a_followup_step :: proc(t: ^testing.T) {
    mixer := engine_sound.new_footstep_mixer(73)
    landing_index := engine_sound.trigger_footstep_mixer(&mixer, .9, .Dirt, true, .4)
    warmup: [2048]f32
    engine_sound.render_footstep_mixer_add(&mixer, warmup[:])
    landing_age := mixer.voices[landing_index].age

    step_index := engine_sound.trigger_footstep_mixer(&mixer, .65, .Gravel)
    testing.expect(t, step_index != landing_index)
    overlap: [2048]f32
    engine_sound.render_footstep_mixer_add(&mixer, overlap[:])
    testing.expect(t, mixer.voices[landing_index].age > landing_age)
    testing.expect(t, mixer.voices[step_index].age > 0)
    overlap_energy := f32(0)
    for sample in overlap do overlap_energy += sample * sample
    testing.expect(t, overlap_energy / f32(len(overlap)) > .0001)
}

@(test)
saturated_footstep_mixer_steals_quietest_tail_click_free :: proc(t: ^testing.T) {
    mixer := engine_sound.new_footstep_mixer(79)
    for index in 0 ..< engine_sound.FOOTSTEP_VOICE_COUNT {
        engine_sound.trigger_footstep_mixer(&mixer, .8, .Cobblestone)
        mixer.voices[index].age = mixer.voices[index].duration * (.15 + f32(index) * .18)
    }
    mixer.voices[2].age = mixer.voices[2].duration * .96
    mixer.voices[2].last_output = .2
    mixer.voices[2].pan = -.14
    stolen := engine_sound.trigger_footstep_mixer(&mixer, .7, .Grass)
    testing.expect(t, stolen == 2)
    testing.expect(t, math.abs(f64(mixer.stolen_tail_left - .228)) < 1e-6)
    testing.expect(t, math.abs(f64(mixer.stolen_tail_right - .172)) < 1e-6)

    with_tail := mixer
    without_tail := mixer
    without_tail.stolen_tail_left = 0
    without_tail.stolen_tail_right = 0
    with_samples, without_samples: [1024]f32
    engine_sound.render_footstep_mixer_add(&with_tail, with_samples[:])
    engine_sound.render_footstep_mixer_add(&without_tail, without_samples[:])
    first_difference := math.abs(f64(with_samples[0] - without_samples[0]))
    last_difference := math.abs(f64(with_samples[len(with_samples) - 1] - without_samples[len(without_samples) - 1]))
    testing.expect(t, math.abs(first_difference - .2) < 1e-5)
    testing.expect(t, last_difference < first_difference * .02)

    stereo_tail := mixer
    no_stereo_tail := mixer
    no_stereo_tail.stolen_tail_left = 0
    no_stereo_tail.stolen_tail_right = 0
    with_stereo, without_stereo: [2]f32
    engine_sound.render_footstep_mixer_stereo_add(&stereo_tail, with_stereo[:])
    engine_sound.render_footstep_mixer_stereo_add(&no_stereo_tail, without_stereo[:])
    testing.expect(t, math.abs(f64((with_stereo[0] - without_stereo[0]) - .228)) < 1e-6)
    testing.expect(t, math.abs(f64((with_stereo[1] - without_stereo[1]) - .172)) < 1e-6)
}

@(test)
ordinary_footsteps_alternate_stereo_side_while_landings_stay_centered :: proc(t: ^testing.T) {
    mixer := engine_sound.new_footstep_mixer(83)
    left := engine_sound.trigger_footstep_mixer(&mixer, .8, .Cobblestone)
    right := engine_sound.trigger_footstep_mixer(&mixer, .8, .Cobblestone)
    landing := engine_sound.trigger_footstep_mixer(&mixer, .8, .Cobblestone, true)
    testing.expect(t, mixer.voices[left].pan < 0)
    testing.expect(t, mixer.voices[right].pan > 0)
    testing.expect(t, mixer.voices[landing].pan == 0)

    stereo: [4096 * 2]f32
    engine_sound.render_footstep_mixer_stereo_add(&mixer, stereo[:])
    left_energy, right_energy := f64(0), f64(0)
    for frame in 0 ..< len(stereo) / 2 {
        left_energy += f64(stereo[frame * 2] * stereo[frame * 2])
        right_energy += f64(stereo[frame * 2 + 1] * stereo[frame * 2 + 1])
    }
    testing.expect(t, left_energy > 0)
    testing.expect(t, right_energy > 0)
}

@(test)
stereo_footstep_render_collapses_exactly_to_mono_render :: proc(t: ^testing.T) {
    mono_mixer, stereo_mixer := engine_sound.new_footstep_mixer(89), engine_sound.new_footstep_mixer(89)
    engine_sound.trigger_footstep_mixer(&mono_mixer, .72, .Gravel)
    engine_sound.trigger_footstep_mixer(&stereo_mixer, .72, .Gravel)
    mono: [2048]f32
    stereo: [len(mono) * 2]f32
    engine_sound.render_footstep_mixer_add(&mono_mixer, mono[:])
    engine_sound.render_footstep_mixer_stereo_add(&stereo_mixer, stereo[:])
    for index in 0 ..< len(mono) {
        collapsed := (stereo[index * 2] + stereo[index * 2 + 1]) * .5
        testing.expect(t, math.abs(f64(collapsed - mono[index])) < 1e-6)
    }
}
