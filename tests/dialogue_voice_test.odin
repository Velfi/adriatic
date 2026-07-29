package tests

import engine_sound "../packages/engine_sound"
import "core:math"
import "core:testing"
import sdl "vendor:sdl3"

@(test)
dialogue_voice_is_bounded_and_finishes :: proc(t: ^testing.T) {
    voice := engine_sound.Dialogue_Voice {
        duration   = .06,
        frequency  = 390,
        brightness = .7,
        warmth     = .4,
        gain       = .11,
    }
    samples: [engine_sound.SAMPLE_RATE / 5]f32
    engine_sound.render_dialogue_voice_add(&voice, samples[:])
    peak := f32(0)
    audible := false
    for sample in samples {
        magnitude := abs(sample)
        peak = max(peak, magnitude)
        if magnitude > .0001 do audible = true
    }
    testing.expect(t, audible)
    testing.expect(t, peak <= .24)
    testing.expect(t, voice.duration == 0)
}

@(test)
dialogue_bus_soft_ceiling_preserves_quiet_audio_and_bounds_dense_overlap :: proc(t: ^testing.T) {
    testing.expect(t, engine_sound.dialogue_voice_soft_limit(.2) == .2)
    testing.expect(t, engine_sound.dialogue_voice_soft_limit(-.2) == -.2)
    testing.expect(t, engine_sound.dialogue_voice_soft_limit(10) <= .62)
    testing.expect(t, engine_sound.dialogue_voice_soft_limit(-10) >= -.62)
    testing.expect(t, engine_sound.dialogue_voice_soft_limit(.8) == -engine_sound.dialogue_voice_soft_limit(-.8))

    profile := engine_sound.Dialogue_Voice_Profile{430, 190, .8, .3, .24, 0}
    mixer: engine_sound.Dialogue_Voice_Mixer
    for &voice in mixer.voices {
        engine_sound.trigger_dialogue_voice(&voice, 'a', profile, .Vowel)
    }
    samples: [4096]f32
    engine_sound.render_dialogue_voice_mixer_add(&mixer, samples[:])
    peak := f32(0)
    for sample in samples do peak = max(peak, abs(sample))
    testing.expect(t, peak > .1)
    testing.expect(t, peak <= .62)
}

@(test)
dialogue_voice_render_is_deterministic :: proc(t: ^testing.T) {
    a := engine_sound.Dialogue_Voice {
        duration   = .052,
        frequency  = 335,
        brightness = .62,
        warmth     = .68,
        gain       = .105,
    }
    b := a
    samples_a, samples_b: [512]f32
    engine_sound.render_dialogue_voice_add(&a, samples_a[:])
    engine_sound.render_dialogue_voice_add(&b, samples_b[:])
    testing.expect(t, samples_a == samples_b)
    testing.expect(t, a == b)
}

@(test)
organic_pitch_motion_is_deterministic_but_not_identical_between_units :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{390, 170, .7, .45, .1, 0}
    first, matching, different: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&first, 'a', profile, .Vowel)
    engine_sound.trigger_dialogue_voice(&matching, 'a', profile, .Vowel)
    engine_sound.trigger_dialogue_voice(&different, 'e', profile, .Vowel)

    testing.expect(t, first.vibrato_rate == matching.vibrato_rate)
    testing.expect(t, first.vibrato_phase == matching.vibrato_phase)
    testing.expect(t, first.pitch_noise_state == matching.pitch_noise_state)
    testing.expect(t, first.vibrato_rate != different.vibrato_rate || first.vibrato_phase != different.vibrato_phase)

    first_samples, matching_samples: [2048]f32
    engine_sound.render_dialogue_voice_add(&first, first_samples[:])
    engine_sound.render_dialogue_voice_add(&matching, matching_samples[:])
    testing.expect(t, first_samples == matching_samples)
    testing.expect(t, first.pitch_wander == matching.pitch_wander)
    testing.expect(t, first.pitch_wander != 0)

    max_step := f32(0)
    for index in 1 ..< len(first_samples) {
        max_step = max(max_step, abs(first_samples[index] - first_samples[index - 1]))
    }
    testing.expect(t, max_step < .04)
}

@(test)
synthesized_unit_onset_is_independent_of_reused_voice_history :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{390, 170, .7, .45, .1, 0}
    after_low, after_high: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&after_low, 'a', profile, .Vowel)
    engine_sound.trigger_dialogue_voice(&after_high, 'u', profile, .Vowel)
    low_history, high_history: [4096]f32
    engine_sound.render_dialogue_voice_add(&after_low, low_history[:])
    engine_sound.render_dialogue_voice_add(&after_high, high_history[:])
    testing.expect(t, after_low.phase_a != after_high.phase_a)

    engine_sound.trigger_dialogue_voice(&after_low, 'e', profile, .Vowel)
    engine_sound.trigger_dialogue_voice(&after_high, 'e', profile, .Vowel)
    testing.expect(t, after_low.phase_a == after_high.phase_a)
    testing.expect(t, after_low.phase_b == 0 && after_low.phase_c == 0)
    testing.expect(t, after_low == after_high)

    low_result, high_result: [4096]f32
    engine_sound.render_dialogue_voice_add(&after_low, low_result[:])
    engine_sound.render_dialogue_voice_add(&after_high, high_result[:])
    testing.expect(t, low_result == high_result)
    testing.expect(t, after_low == after_high)
}

@(test)
repeated_units_vary_their_performance_but_replay_exactly :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{390, 170, .7, .45, .1, 0}
    first, replay: engine_sound.Dialogue_Voice_Mixer
    first_a := engine_sound.trigger_dialogue_voice_mixer(&first, 'a', profile, 0, .Vowel)
    replay_a := engine_sound.trigger_dialogue_voice_mixer(&replay, 'a', profile, 0, .Vowel)
    first_b := engine_sound.trigger_dialogue_voice_mixer(&first, 'a', profile, 0, .Vowel)
    replay_b := engine_sound.trigger_dialogue_voice_mixer(&replay, 'a', profile, 0, .Vowel)

    testing.expect(t, first.voices[first_a].vibrato_rate == replay.voices[replay_a].vibrato_rate)
    testing.expect(t, first.voices[first_a].vibrato_phase == replay.voices[replay_a].vibrato_phase)
    testing.expect(t, first.voices[first_b].vibrato_rate == replay.voices[replay_b].vibrato_rate)
    testing.expect(t, first.voices[first_b].vibrato_phase == replay.voices[replay_b].vibrato_phase)
    testing.expect(
        t,
        first.voices[first_a].vibrato_rate != first.voices[first_b].vibrato_rate ||
        first.voices[first_a].vibrato_phase != first.voices[first_b].vibrato_phase,
    )
}

@(test)
dialogue_glyphs_shape_resonance_onset_and_pitch_contour :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile {
        base_hz    = 330,
        range_hz   = 80,
        brightness = .62,
        warmth     = .68,
        gain       = .105,
    }
    a, matching, b: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&a, 'a', profile)
    engine_sound.trigger_dialogue_voice(&matching, 'a', profile)
    engine_sound.trigger_dialogue_voice(&b, 'b', profile)

    testing.expect(t, a == matching)
    testing.expect(t, a.formant_ratio_a != b.formant_ratio_a || a.formant_ratio_b != b.formant_ratio_b)
    testing.expect(t, a.onset_mix != b.onset_mix)
    testing.expect(t, a.pitch_glide != b.pitch_glide)

    samples_a, samples_matching, samples_b: [2048]f32
    engine_sound.render_dialogue_voice_add(&a, samples_a[:])
    engine_sound.render_dialogue_voice_add(&matching, samples_matching[:])
    engine_sound.render_dialogue_voice_add(&b, samples_b[:])
    testing.expect(t, samples_a == samples_matching)
    testing.expect(t, samples_a != samples_b)
}

@(test)
dialogue_consonant_onset_decays_into_voiced_body :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile {
        base_hz    = 310,
        range_hz   = 60,
        brightness = .8,
        warmth     = .3,
        gain       = .12,
    }
    voiced, without_onset: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&voiced, 'k', profile)
    without_onset = voiced
    without_onset.onset_mix = 0
    with_samples, without_samples: [2048]f32
    engine_sound.render_dialogue_voice_add(&voiced, with_samples[:])
    engine_sound.render_dialogue_voice_add(&without_onset, without_samples[:])

    early_difference, late_difference := f32(0), f32(0)
    for index in 0 ..< 256 {
        early_difference += abs(with_samples[index] - without_samples[index])
    }
    for index in 1024 ..< 1280 {
        late_difference += abs(with_samples[index] - without_samples[index])
    }
    testing.expect(t, early_difference > late_difference * 4)
}

@(test)
dialogue_mixer_preserves_syllable_tail_at_reveal_cadence :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile {
        base_hz    = 340,
        range_hz   = 120,
        brightness = .6,
        warmth     = .6,
        gain       = .1,
    }
    mixer: engine_sound.Dialogue_Voice_Mixer
    first := engine_sound.trigger_dialogue_voice_mixer(&mixer, 'm', profile)
    prefix: [int(.032 * engine_sound.SAMPLE_RATE)]f32
    engine_sound.render_dialogue_voice_mixer_add(&mixer, prefix[:])
    first_age := mixer.voices[first].age
    second := engine_sound.trigger_dialogue_voice_mixer(&mixer, 'a', profile)

    testing.expect(t, second != first)
    overlap: [1024]f32
    engine_sound.render_dialogue_voice_mixer_add(&mixer, overlap[:])
    testing.expect(t, mixer.voices[first].age > first_age)
    testing.expect(t, mixer.voices[second].age > 0)

    energy := f32(0)
    for sample in overlap do energy += sample * sample
    testing.expect(t, energy > .01)
}

@(test)
dialogue_mixer_does_not_steal_long_cv_units_at_supported_cadences :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{340, 120, .6, .6, .1, 0}
    cadences := [?]f32{.032, .020}
    required_overlaps := [?]int{4, 5}
    for cadence, cadence_index in cadences {
        mixer := engine_sound.Dialogue_Voice_Mixer {
            unit_blend = 1,
        }
        seen: [engine_sound.DIALOGUE_VOICE_COUNT]bool
        scratch: [int(.032 * engine_sound.SAMPLE_RATE)]f32
        for trigger_index in 0 ..< required_overlaps[cadence_index] {
            voice_index := engine_sound.trigger_dialogue_voice_mixer(
                &mixer,
                engine_sound.dialogue_voice_unit_token("k", "u"),
                profile,
                0,
                .Consonant,
            )
            engine_sound.dialogue_voice_apply_consonant_source(
                &mixer.voices[voice_index],
                engine_sound.dialogue_voice_token("k"),
            )
            testing.expect(t, engine_sound.dialogue_voice_apply_cv_unit(&mixer.voices[voice_index], "u", 1))
            testing.expect(t, !seen[voice_index])
            seen[voice_index] = true
            if trigger_index + 1 < required_overlaps[cadence_index] {
                sample_count := int(cadence * engine_sound.SAMPLE_RATE)
                engine_sound.render_dialogue_voice_mixer_add(&mixer, scratch[:sample_count])
            }
        }
    }
}

@(test)
dialogue_mixer_adds_deterministic_phrase_prosody_and_repetition_variation :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile {
        base_hz    = 330,
        range_hz   = 90,
        brightness = .55,
        warmth     = .65,
        gain       = .1,
    }
    first, matching: engine_sound.Dialogue_Voice_Mixer
    first_frequencies, matching_frequencies: [12]f32
    for index in 0 ..< len(first_frequencies) {
        glyph := index < 2 ? u8('a') : u8('e')
        first_index := engine_sound.trigger_dialogue_voice_mixer(&first, u32(glyph), profile)
        matching_index := engine_sound.trigger_dialogue_voice_mixer(&matching, u32(glyph), profile)
        first_frequencies[index] = first.voices[first_index].frequency
        matching_frequencies[index] = matching.voices[matching_index].frequency
    }

    testing.expect(t, first_frequencies == matching_frequencies)
    testing.expect(t, first_frequencies[0] != first_frequencies[1])
    testing.expect(t, first_frequencies[5] > first_frequencies[2])
    testing.expect(t, first_frequencies[10] < first_frequencies[5])
    testing.expect(t, first.syllable_index == 12)
}

@(test)
dialogue_utf8_graphemes_keep_distinct_identity_with_intentional_phonetic_families :: proc(t: ^testing.T) {
    c_caron := engine_sound.dialogue_voice_token("č")
    c_acute := engine_sound.dialogue_voice_token("ć")
    s_caron := engine_sound.dialogue_voice_token("š")
    testing.expect(t, c_caron == engine_sound.dialogue_voice_token("č"))
    testing.expect(t, c_caron != c_acute)
    testing.expect(t, c_caron != s_caron)
    testing.expect(t, c_acute != s_caron)

    profile := engine_sound.Dialogue_Voice_Profile{330, 100, .6, .6, .1, 0}
    first, second, fricative: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&first, c_caron, profile, .Consonant)
    engine_sound.trigger_dialogue_voice(&second, c_acute, profile, .Consonant)
    engine_sound.trigger_dialogue_voice(&fricative, s_caron, profile, .Consonant)
    testing.expect(t, first.formant_ratio_a == second.formant_ratio_a)
    testing.expect(t, first.formant_ratio_b == second.formant_ratio_b)
    testing.expect(t, first.consonant_color == second.consonant_color)
    testing.expect(t, first.vibrato_rate != second.vibrato_rate || first.vibrato_phase != second.vibrato_phase)
    testing.expect(t, fricative.formant_ratio_a != first.formant_ratio_a)
    testing.expect(t, fricative.consonant_color > first.consonant_color)
}

@(test)
unicode_punctuation_is_silent_while_unicode_letters_remain_speakable :: proc(t: ^testing.T) {
    testing.expect(t, engine_sound.dialogue_voice_articulation("…") == .Neutral)
    testing.expect(t, engine_sound.dialogue_voice_articulation("—") == .Neutral)
    testing.expect(t, engine_sound.dialogue_voice_articulation("“") == .Neutral)
    testing.expect(t, engine_sound.dialogue_voice_articulation("🙂") == .Neutral)
    testing.expect(t, engine_sound.dialogue_voice_articulation("λ") == .Consonant)

    profile := engine_sound.Dialogue_Voice_Profile{350, 120, .6, .6, .1, 0}
    mixer: engine_sound.Dialogue_Voice_Mixer
    testing.expect(t, !engine_sound.dialogue_voice_trigger_grapheme_mixer(&mixer, "…", profile))
    testing.expect(t, !engine_sound.dialogue_voice_trigger_grapheme_mixer(&mixer, "—", profile))
    testing.expect(t, mixer.syllable_index == 0)
    testing.expect(t, engine_sound.dialogue_voice_trigger_grapheme_mixer(&mixer, "λ", profile))
    testing.expect(t, mixer.syllable_index == 1)
}

@(test)
accented_latin_vowels_use_vowel_shapes_without_losing_unit_identity :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{350, 120, .6, .6, .1, 0}
    testing.expect(t, engine_sound.dialogue_voice_articulation("á") == .Vowel)
    testing.expect(t, engine_sound.dialogue_voice_articulation("É") == .Vowel)
    testing.expect(t, engine_sound.dialogue_voice_token("á") != engine_sound.dialogue_voice_token("a"))

    plain, accented: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&plain, engine_sound.dialogue_voice_token("a"), profile, .Vowel)
    engine_sound.trigger_dialogue_voice(&accented, engine_sound.dialogue_voice_token("á"), profile, .Vowel)
    testing.expect(t, accented.formant_ratio_a == plain.formant_ratio_a)
    testing.expect(t, accented.formant_ratio_b == plain.formant_ratio_b)

    mixer := engine_sound.Dialogue_Voice_Mixer {
        unit_blend = .82,
    }
    testing.expect(t, engine_sound.dialogue_voice_trigger_grapheme_mixer(&mixer, "m", profile, 0, "á"))
    testing.expect(t, mixer.consumed_vowel)
    testing.expect(t, mixer.voices[0].target_formant_a == plain.formant_ratio_a)
}

@(test)
croatian_digraphs_are_single_distinct_phonetic_source_units :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{350, 120, .6, .6, .1, 0}
    lj_token := engine_sound.dialogue_voice_token("lj")
    nj_token := engine_sound.dialogue_voice_token("nj")
    dz_token := engine_sound.dialogue_voice_token("dž")
    testing.expect(t, lj_token != engine_sound.dialogue_voice_token("l"))
    testing.expect(t, nj_token != engine_sound.dialogue_voice_token("n"))
    testing.expect(t, dz_token != engine_sound.dialogue_voice_token("j"))
    testing.expect(t, lj_token != nj_token)
    testing.expect(t, engine_sound.dialogue_voice_merge_graphemes("l", "j"))
    testing.expect(t, engine_sound.dialogue_voice_merge_graphemes("N", "J"))
    testing.expect(t, engine_sound.dialogue_voice_merge_graphemes("d", "ž"))
    testing.expect(t, !engine_sound.dialogue_voice_merge_graphemes("l", "a"))
    testing.expect(t, !engine_sound.dialogue_voice_merge_graphemes("d", "z"))
    testing.expect(t, engine_sound.dialogue_voice_articulation("lj") == .Consonant)
    testing.expect(t, engine_sound.dialogue_voice_articulation("dž") == .Consonant)

    lj, nj, dz: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&lj, lj_token, profile, .Consonant)
    engine_sound.trigger_dialogue_voice(&nj, nj_token, profile, .Consonant)
    engine_sound.trigger_dialogue_voice(&dz, dz_token, profile, .Consonant)
    testing.expect(t, lj.consonant_color == nj.consonant_color)
    testing.expect(t, lj.consonant_voiced == nj.consonant_voiced)
    testing.expect(t, dz.consonant_color > lj.consonant_color)

    mixer := engine_sound.Dialogue_Voice_Mixer {
        unit_blend = .82,
    }
    testing.expect(t, engine_sound.dialogue_voice_trigger_grapheme_mixer(&mixer, "lj", profile, 0, "a"))
    testing.expect(t, mixer.consumed_vowel)
    testing.expect(t, mixer.syllable_index == 1)
}

@(test)
common_english_digraphs_are_atomic_synthesized_consonant_sources :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{350, 120, .6, .6, .1, 0}
    digraphs := [?][2]string {
        {"s", "h"},
        {"c", "h"},
        {"t", "h"},
        {"p", "h"},
        {"w", "h"},
        {"n", "g"},
        {"c", "k"},
        {"q", "u"},
    }
    for pair in digraphs {
        testing.expect(t, engine_sound.dialogue_voice_merge_graphemes(pair[0], pair[1]))
    }
    testing.expect(t, engine_sound.dialogue_voice_merge_graphemes("S", "H"))
    testing.expect(t, !engine_sound.dialogue_voice_merge_graphemes("s", "k"))

    sh, uppercase_sh, ch, th, f, ng, wh: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&sh, engine_sound.dialogue_voice_token("sh"), profile, .Consonant)
    engine_sound.trigger_dialogue_voice(&uppercase_sh, engine_sound.dialogue_voice_token("SH"), profile, .Consonant)
    engine_sound.trigger_dialogue_voice(&ch, engine_sound.dialogue_voice_token("ch"), profile, .Consonant)
    engine_sound.trigger_dialogue_voice(&th, engine_sound.dialogue_voice_token("th"), profile, .Consonant)
    engine_sound.trigger_dialogue_voice(&f, engine_sound.dialogue_voice_token("f"), profile, .Consonant)
    engine_sound.trigger_dialogue_voice(&ng, engine_sound.dialogue_voice_token("ng"), profile, .Consonant)
    engine_sound.trigger_dialogue_voice(&wh, engine_sound.dialogue_voice_token("wh"), profile, .Consonant)
    s_band_hz, _, _ := engine_sound.dialogue_voice_consonant_band('s')
    testing.expect(t, sh.consonant_color > ch.consonant_color)
    testing.expect(t, sh.consonant_band_hz < s_band_hz)
    testing.expect(t, sh.consonant_band_hz == uppercase_sh.consonant_band_hz)
    testing.expect(t, sh.consonant_bandwidth == uppercase_sh.consonant_bandwidth)
    testing.expect(t, th.consonant_band_hz > f.consonant_band_hz)
    testing.expect(t, th.consonant_bandwidth > f.consonant_bandwidth)
    testing.expect(t, ng.nasal_mix > wh.nasal_mix)
    testing.expect(t, ng.consonant_voiced > wh.consonant_voiced)

    sh_samples, th_samples, f_samples: [2048]f32
    engine_sound.render_dialogue_voice_add(&sh, sh_samples[:])
    engine_sound.render_dialogue_voice_add(&th, th_samples[:])
    engine_sound.render_dialogue_voice_add(&f, f_samples[:])
    testing.expect(t, sh_samples != th_samples && th_samples != f_samples)
    sh_peak, th_peak, f_peak := f32(0), f32(0), f32(0)
    for index in 0 ..< len(sh_samples) {
        sh_peak = max(sh_peak, abs(sh_samples[index]))
        th_peak = max(th_peak, abs(th_samples[index]))
        f_peak = max(f_peak, abs(f_samples[index]))
    }
    testing.expect(t, sh_peak <= profile.gain * 1.5)
    testing.expect(t, th_peak <= profile.gain * 1.5)
    testing.expect(t, f_peak <= profile.gain * 1.5)

    mixer := engine_sound.Dialogue_Voice_Mixer {
        unit_blend = .82,
    }
    testing.expect(t, engine_sound.dialogue_voice_trigger_grapheme_mixer(&mixer, "qu", profile, 0, "i"))
    testing.expect(t, mixer.consumed_vowel)
    testing.expect(t, mixer.syllable_index == 1)
}

@(test)
doubled_consonant_spellings_are_one_atomic_source_unit_not_a_stutter :: proc(t: ^testing.T) {
    testing.expect(t, engine_sound.dialogue_voice_merge_graphemes("t", "t"))
    testing.expect(t, engine_sound.dialogue_voice_merge_graphemes("P", "p"))
    testing.expect(t, engine_sound.dialogue_voice_merge_graphemes("l", "L"))
    testing.expect(t, engine_sound.dialogue_voice_merge_graphemes("s", "S"))
    testing.expect(t, !engine_sound.dialogue_voice_merge_graphemes("a", "a"))
    testing.expect(t, !engine_sound.dialogue_voice_merge_graphemes("e", "e"))
    testing.expect(t, !engine_sound.dialogue_voice_merge_graphemes("y", "y"))
    testing.expect(t, !engine_sound.dialogue_voice_merge_graphemes("s", "k"))

    tt_token := engine_sound.dialogue_voice_token("tt")
    t_token := engine_sound.dialogue_voice_token("t")
    testing.expect(t, tt_token != t_token)
    testing.expect(t, engine_sound.dialogue_voice_token_glyph(tt_token) == 't')
    profile := engine_sound.Dialogue_Voice_Profile{350, 120, .6, .6, .1, 0}
    doubled, single: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&doubled, tt_token, profile, .Consonant)
    engine_sound.trigger_dialogue_voice(&single, t_token, profile, .Consonant)
    testing.expect(t, doubled.consonant_band_hz == single.consonant_band_hz)
    testing.expect(t, doubled.consonant_bandwidth == single.consonant_bandwidth)
    testing.expect(t, doubled.consonant_decay == single.consonant_decay)

    mixer := engine_sound.Dialogue_Voice_Mixer {
        unit_blend = .82,
    }
    testing.expect(t, engine_sound.dialogue_voice_trigger_grapheme_mixer(&mixer, "pp", profile, 0, "y"))
    testing.expect(t, mixer.consumed_vowel)
    testing.expect(t, mixer.syllable_index == 1)
}

@(test)
authored_punctuation_hint_adds_falling_phrase_cadence :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{330, 100, .6, .6, .1, 0}
    plain, terminal: engine_sound.Dialogue_Voice_Mixer
    plain_index := engine_sound.trigger_dialogue_voice_mixer(&plain, 'a', profile)
    terminal_index := engine_sound.trigger_dialogue_voice_mixer(&terminal, 'a', profile, 1)
    testing.expect(t, terminal.voices[terminal_index].frequency < plain.voices[plain_index].frequency)
    testing.expect(t, terminal.voices[terminal_index].pitch_glide < plain.voices[plain_index].pitch_glide)
}

@(test)
dialogue_vowels_have_stable_distinct_mouth_shapes :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{390, 170, .7, .45, .1, 0}
    a, e, o: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&a, 'a', profile, .Vowel)
    engine_sound.trigger_dialogue_voice(&e, 'e', profile, .Vowel)
    engine_sound.trigger_dialogue_voice(&o, 'o', profile, .Vowel)

    testing.expect(t, a.formant_ratio_a < e.formant_ratio_a)
    testing.expect(t, e.formant_ratio_b > a.formant_ratio_b)
    testing.expect(t, o.formant_ratio_a < a.formant_ratio_a)
    testing.expect(t, a.onset_mix < .05)
    testing.expect(t, e.onset_mix < .05)
    testing.expect(t, o.onset_mix < .05)
}

@(test)
dialogue_pitch_choices_belong_to_a_small_musical_vocabulary :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{400, 200, .65, .55, .1, 0}
    allowed_steps := [?]f32{-5, -3, 0, 2, 4, 7}
    unique: [16]f32
    unique_count := 0
    for glyph in "abcdefghijklmnopqrstuv" {
        voice: engine_sound.Dialogue_Voice
        engine_sound.trigger_dialogue_voice(&voice, u32(glyph), profile)
        semitones := 12 * f32(math.log2(f64(voice.frequency / profile.base_hz)))
        tuned := false
        for step in allowed_steps {
            if abs(semitones - step) < .001 {
                tuned = true
                break
            }
        }
        testing.expect(t, tuned)
        testing.expect(t, voice.frequency <= profile.base_hz + profile.range_hz + .001)
        found := false
        for existing in unique[:unique_count] {
            if abs(existing - voice.frequency) < .001 {
                found = true
                break
            }
        }
        if !found {
            unique[unique_count] = voice.frequency
            unique_count += 1
        }
    }
    testing.expect(t, unique_count >= 4)
    testing.expect(t, unique_count <= len(allowed_steps))

    zero_range := engine_sound.Dialogue_Voice_Profile{400, 0, .65, .55, .1, 0}
    for glyph in "abcdef" {
        voice: engine_sound.Dialogue_Voice
        engine_sound.trigger_dialogue_voice(&voice, u32(glyph), zero_range)
        testing.expect(t, voice.frequency == zero_range.base_hz)
    }
}

@(test)
question_cadence_lifts_while_statement_cadence_falls :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{360, 140, .6, .6, .1, 0}
    plain, question, exclamation, statement: engine_sound.Dialogue_Voice_Mixer
    plain_index := engine_sound.trigger_dialogue_voice_mixer(&plain, 'e', profile)
    question_index := engine_sound.trigger_dialogue_voice_mixer(&question, 'e', profile, -1)
    exclamation_index := engine_sound.trigger_dialogue_voice_mixer(&exclamation, 'e', profile, -.35)
    statement_index := engine_sound.trigger_dialogue_voice_mixer(&statement, 'e', profile, 1)

    testing.expect(t, question.voices[question_index].frequency > plain.voices[plain_index].frequency)
    testing.expect(t, statement.voices[statement_index].frequency < plain.voices[plain_index].frequency)
    testing.expect(t, question.voices[question_index].pitch_glide > statement.voices[statement_index].pitch_glide)
    testing.expect(
        t,
        exclamation.voices[exclamation_index].cadence_gain > question.voices[question_index].cadence_gain,
    )
    testing.expect(t, question.voices[question_index].cadence_gain > statement.voices[statement_index].cadence_gain)
    testing.expect(
        t,
        exclamation.voices[exclamation_index].release_power < question.voices[question_index].release_power,
    )
    testing.expect(t, question.voices[question_index].release_power < statement.voices[statement_index].release_power)

    held_question := plain.voices[plain_index]
    held_statement := held_question
    held_question.cadence_gain = question.voices[question_index].cadence_gain
    held_question.release_power = question.voices[question_index].release_power
    held_statement.cadence_gain = statement.voices[statement_index].cadence_gain
    held_statement.release_power = statement.voices[statement_index].release_power
    question_samples, statement_samples: [4096]f32
    engine_sound.render_dialogue_voice_add(&held_question, question_samples[:])
    engine_sound.render_dialogue_voice_add(&held_statement, statement_samples[:])
    question_tail, statement_tail := f32(0), f32(0)
    for index in 1600 ..< 3000 {
        question_tail += question_samples[index] * question_samples[index]
        statement_tail += statement_samples[index] * statement_samples[index]
    }
    testing.expect(t, question_tail > statement_tail * 1.5)
}

@(test)
expression_hint_scales_performance_without_changing_voice_identity :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{360, 140, .6, .6, .1, 0}
    restrained, animated: engine_sound.Dialogue_Voice_Mixer
    restrained_index := engine_sound.trigger_dialogue_voice_mixer(&restrained, 'e', profile, -.35, .Vowel, .5, 0)
    animated_index := engine_sound.trigger_dialogue_voice_mixer(&animated, 'e', profile, -.35, .Vowel, .5, 1)
    restrained_voice := &restrained.voices[restrained_index]
    animated_voice := &animated.voices[animated_index]

    testing.expect(t, animated_voice.frequency > restrained_voice.frequency)
    testing.expect(t, animated_voice.vibrato_depth > restrained_voice.vibrato_depth)
    testing.expect(t, animated_voice.onset_bloom_depth > restrained_voice.onset_bloom_depth)
    testing.expect(t, animated_voice.cadence_gain > restrained_voice.cadence_gain)
    testing.expect(t, animated_voice.release_power < restrained_voice.release_power)
    testing.expect(t, animated_voice.formant_base_hz == restrained_voice.formant_base_hz)
    testing.expect(t, animated_voice.formant_ratio_a == restrained_voice.formant_ratio_a)
    testing.expect(t, animated_voice.formant_ratio_b == restrained_voice.formant_ratio_b)
}

@(test)
onset_bloom_adds_a_bounded_zero_endpoint_cute_pitch_gesture :: proc(t: ^testing.T) {
    duration := f32(.028)
    depth := f32(.012)
    testing.expect(t, engine_sound.dialogue_voice_onset_bloom(0, duration, depth) == 0)
    testing.expect(t, engine_sound.dialogue_voice_onset_bloom(duration, duration, depth) == 0)
    testing.expect(t, abs(engine_sound.dialogue_voice_onset_bloom(duration * .5, duration, depth) - depth) < .000001)
    testing.expect(
        t,
        abs(
            engine_sound.dialogue_voice_onset_bloom(duration * .25, duration, depth) -
            engine_sound.dialogue_voice_onset_bloom(duration * .75, duration, depth),
        ) <
        .000001,
    )
    testing.expect(t, engine_sound.dialogue_voice_onset_bloom(duration * .5, duration, 1) == .025)
    testing.expect(t, engine_sound.dialogue_voice_onset_bloom(duration * .5, 0, depth) == 0)

    profile := engine_sound.Dialogue_Voice_Profile{360, 140, .6, .6, .1, 0}
    vowels, consonants: engine_sound.Dialogue_Voice_Mixer
    vowel_index := engine_sound.trigger_dialogue_voice_mixer(&vowels, 'e', profile, 0, .Vowel, .5, 1)
    consonant_index := engine_sound.trigger_dialogue_voice_mixer(&consonants, 'k', profile, 0, .Consonant, .5, 1)
    testing.expect(
        t,
        vowels.voices[vowel_index].onset_bloom_depth > consonants.voices[consonant_index].onset_bloom_depth,
    )
}

@(test)
synthesized_cv_unit_transitions_into_the_authored_vowel_shape :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{380, 150, .7, .55, .1, 0}
    cv, consonant: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&cv, 'k', profile, .Consonant)
    consonant = cv
    testing.expect(t, engine_sound.dialogue_voice_apply_cv_unit(&cv, "a", .85))
    testing.expect(t, cv.coarticulation == .85)
    testing.expect(t, cv.target_formant_a != cv.formant_ratio_a)
    testing.expect(t, cv.target_formant_b != cv.formant_ratio_b)
    testing.expect(t, cv.duration > consonant.duration)

    cv_samples, consonant_samples: [4096]f32
    engine_sound.render_dialogue_voice_add(&cv, cv_samples[:])
    engine_sound.render_dialogue_voice_add(&consonant, consonant_samples[:])
    early_difference, late_difference := f32(0), f32(0)
    for index in 0 ..< 256 do early_difference += abs(cv_samples[index] - consonant_samples[index])
    for index in 1800 ..< 2400 do late_difference += abs(cv_samples[index] - consonant_samples[index])
    testing.expect(t, late_difference > early_difference)
}

@(test)
synthesized_cv_sequence_consumes_its_vowel_as_one_unit :: proc(t: ^testing.T) {
    device: engine_sound.Device
    device.stream = cast(^sdl.AudioStream)(uintptr(1))
    device.dialogue_voice.unit_blend = .82
    profile := engine_sound.Dialogue_Voice_Profile{380, 150, .7, .55, .1, 0}
    engine_sound.dialogue_voice_trigger_grapheme(&device, "k", profile, 0, "a")
    testing.expect(t, device.dialogue_voice.consumed_vowel)
    testing.expect(t, device.dialogue_voice.syllable_index == 1)

    engine_sound.dialogue_voice_trigger_grapheme(&device, "a", profile)
    testing.expect(t, !device.dialogue_voice.consumed_vowel)
    testing.expect(t, device.dialogue_voice.syllable_index == 1)
}

@(test)
synthesized_vv_sequence_morphs_between_vowels_as_one_unit :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{380, 150, .7, .55, .1, 0}
    mixer := engine_sound.Dialogue_Voice_Mixer {
        unit_blend = .82,
    }
    source, destination: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&source, 'o', profile, .Vowel)
    engine_sound.trigger_dialogue_voice(&destination, 'a', profile, .Vowel)

    testing.expect(t, engine_sound.dialogue_voice_unit_token("o", "a") != engine_sound.dialogue_voice_token("o"))
    testing.expect(t, engine_sound.dialogue_voice_trigger_grapheme_mixer(&mixer, "o", profile, 0, "a"))
    vv := &mixer.voices[0]
    testing.expect(t, mixer.consumed_vowel)
    testing.expect(t, vv.formant_ratio_a == source.formant_ratio_a)
    testing.expect(t, vv.formant_ratio_b == source.formant_ratio_b)
    testing.expect(t, vv.target_formant_a == destination.formant_ratio_a)
    testing.expect(t, vv.target_formant_b == destination.formant_ratio_b)
    testing.expect(t, vv.coarticulation == .82)
    testing.expect(t, !engine_sound.dialogue_voice_trigger_grapheme_mixer(&mixer, "a", profile))
    testing.expect(t, mixer.syllable_index == 1)
}

@(test)
synthesized_vcv_unit_carries_the_previous_vowel_through_the_consonant :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{380, 150, .7, .55, .1, 0}
    mixer := engine_sound.Dialogue_Voice_Mixer {
        unit_blend = .82,
    }
    testing.expect(t, engine_sound.dialogue_voice_trigger_grapheme_mixer(&mixer, "a", profile))
    testing.expect(t, mixer.carried_vowel)
    carried_a, carried_b := mixer.carried_formant_a, mixer.carried_formant_b

    testing.expect(t, engine_sound.dialogue_voice_trigger_grapheme_mixer(&mixer, "k", profile, 0, "o"))
    cv := &mixer.voices[1]
    testing.expect(t, cv.has_vcv_lead)
    testing.expect(t, cv.previous_formant_a == carried_a)
    testing.expect(t, cv.previous_formant_b == carried_b)
    testing.expect(t, cv.target_formant_a != cv.previous_formant_a)
    testing.expect(t, cv.target_formant_b != cv.previous_formant_b)
}

@(test)
synthesized_vcv_context_resets_at_word_boundaries :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{380, 150, .7, .55, .1, 0}
    mixer := engine_sound.Dialogue_Voice_Mixer {
        unit_blend = .82,
    }
    _ = engine_sound.dialogue_voice_trigger_grapheme_mixer(&mixer, "a", profile)
    testing.expect(t, mixer.carried_vowel)
    engine_sound.dialogue_voice_mixer_word_boundary(&mixer)
    testing.expect(t, !mixer.carried_vowel)

    _ = engine_sound.dialogue_voice_trigger_grapheme_mixer(&mixer, "k", profile, 0, "o")
    testing.expect(t, !mixer.voices[1].has_vcv_lead)
}

@(test)
synthesized_cv_note_identity_uses_the_complete_unit :: proc(t: ^testing.T) {
    ka := engine_sound.dialogue_voice_unit_token("k", "a")
    ke := engine_sound.dialogue_voice_unit_token("k", "e")
    plain_k := engine_sound.dialogue_voice_unit_token("k", "r")
    testing.expect(t, ka != ke)
    testing.expect(t, ka == engine_sound.dialogue_voice_unit_token("k", "a"))
    testing.expect(t, plain_k == engine_sound.dialogue_voice_token("k"))

    profile := engine_sound.Dialogue_Voice_Profile{380, 150, .7, .55, .1, 0}
    vowels := [?]string{"a", "e", "i", "o", "u"}
    frequencies: [len(vowels)]f32
    unique_count := 0
    for vowel, index in vowels {
        voice: engine_sound.Dialogue_Voice
        unit := engine_sound.dialogue_voice_unit_token("k", vowel)
        engine_sound.trigger_dialogue_voice(&voice, unit, profile, .Consonant)
        frequencies[index] = voice.frequency
        found := false
        for prior in frequencies[:index] {
            if prior == voice.frequency {
                found = true
                break
            }
        }
        if !found do unique_count += 1
    }
    testing.expect(t, unique_count >= 2)
}

@(test)
synthesized_cv_keeps_consonant_source_and_vowel_destination_separate :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{380, 150, .7, .55, .1, 0}
    nasal, plosive: engine_sound.Dialogue_Voice_Mixer
    nasal.unit_blend = .82
    plosive.unit_blend = .82
    testing.expect(t, engine_sound.dialogue_voice_trigger_grapheme_mixer(&nasal, "m", profile, 0, "a", 0))
    testing.expect(t, engine_sound.dialogue_voice_trigger_grapheme_mixer(&plosive, "k", profile, 0, "a", 0))
    nasal_voice := &nasal.voices[0]
    plosive_voice := &plosive.voices[0]

    testing.expect(t, nasal_voice.formant_ratio_a != plosive_voice.formant_ratio_a)
    testing.expect(t, nasal_voice.onset_mix != plosive_voice.onset_mix)
    testing.expect(t, nasal_voice.consonant_color < plosive_voice.consonant_color)
    testing.expect(t, nasal_voice.consonant_decay < plosive_voice.consonant_decay)
    testing.expect(t, nasal_voice.consonant_voiced > plosive_voice.consonant_voiced)
    testing.expect(t, nasal_voice.nasal_mix > plosive_voice.nasal_mix)
    testing.expect(t, nasal_voice.target_formant_a == plosive_voice.target_formant_a)
    testing.expect(t, nasal_voice.target_formant_b == plosive_voice.target_formant_b)
    testing.expect(t, nasal_voice.coarticulation == plosive_voice.coarticulation)
}

@(test)
nasals_have_a_low_synthesized_tract_distinct_from_other_sonorants :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{350, 120, .6, .6, .1, 0}
    nasal, approximant, plosive: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&nasal, 'm', profile, .Consonant)
    engine_sound.trigger_dialogue_voice(&approximant, 'l', profile, .Consonant)
    engine_sound.trigger_dialogue_voice(&plosive, 'k', profile, .Consonant)
    testing.expect(t, nasal.nasal_mix > approximant.nasal_mix)
    testing.expect(t, approximant.nasal_mix > plosive.nasal_mix)

    without_nasal := nasal
    without_nasal.nasal_mix = 0
    nasal_samples, plain_samples: [2048]f32
    engine_sound.render_dialogue_voice_add(&nasal, nasal_samples[:])
    engine_sound.render_dialogue_voice_add(&without_nasal, plain_samples[:])
    difference := f32(0)
    for index in 256 ..< 1600 {
        difference += abs(nasal_samples[index] - plain_samples[index])
    }
    testing.expect(t, difference > .1)
    testing.expect(t, abs(nasal.nasal_low) > .000001)

    cv, cv_without_nasal: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&cv, 'm', profile, .Consonant)
    testing.expect(t, engine_sound.dialogue_voice_apply_cv_unit(&cv, "a", .82))
    cv_without_nasal = cv
    cv_without_nasal.nasal_mix = 0
    cv_samples, cv_plain_samples: [4096]f32
    engine_sound.render_dialogue_voice_add(&cv, cv_samples[:])
    engine_sound.render_dialogue_voice_add(&cv_without_nasal, cv_plain_samples[:])
    early_difference, late_difference := f32(0), f32(0)
    for index in 256 ..< 800 do early_difference += abs(cv_samples[index] - cv_plain_samples[index])
    for index in 2600 ..< 3200 do late_difference += abs(cv_samples[index] - cv_plain_samples[index])
    testing.expect(t, early_difference > late_difference * 2)
}

@(test)
consonant_families_use_distinct_bounded_synthesized_noise_bands :: proc(t: ^testing.T) {
    p_hz, _, p_mix := engine_sound.dialogue_voice_consonant_band('p')
    k_hz, _, k_mix := engine_sound.dialogue_voice_consonant_band('k')
    t_hz, _, t_mix := engine_sound.dialogue_voice_consonant_band('t')
    c_hz, _, c_mix := engine_sound.dialogue_voice_consonant_band('c')
    s_hz, _, s_mix := engine_sound.dialogue_voice_consonant_band('s')
    testing.expect(t, p_hz < k_hz && k_hz < t_hz && t_hz < c_hz && c_hz < s_hz)
    testing.expect(t, p_mix > 0 && k_mix > 0 && t_mix > 0 && c_mix > 0 && s_mix > 0)

    profile := engine_sound.Dialogue_Voice_Profile{380, 150, .7, .55, .1, 0}
    tokens := [?]u32{'p', 'k', 't', 'c', 's'}
    outputs: [len(tokens)][2048]f32
    for token, token_index in tokens {
        voice: engine_sound.Dialogue_Voice
        engine_sound.trigger_dialogue_voice(&voice, token, profile, .Consonant)
        engine_sound.render_dialogue_voice_add(&voice, outputs[token_index][:])
        peak := f32(0)
        for sample in outputs[token_index] do peak = max(peak, abs(sample))
        testing.expect(t, peak <= profile.gain * 1.5)
        testing.expect(t, abs(voice.consonant_band_y1) > .000001 || abs(voice.consonant_band_y2) > .000001)
    }
    testing.expect(t, outputs[0] != outputs[1])
    testing.expect(t, outputs[1] != outputs[2])
    testing.expect(t, outputs[2] != outputs[3])
    testing.expect(t, outputs[3] != outputs[4])
}

@(test)
synthesized_stops_have_family_specific_closure_and_burst_timing :: proc(t: ^testing.T) {
    p_delay, p_attack := engine_sound.dialogue_voice_consonant_timing('p')
    k_delay, k_attack := engine_sound.dialogue_voice_consonant_timing('k')
    t_delay, t_attack := engine_sound.dialogue_voice_consonant_timing('t')
    ch_delay, ch_attack := engine_sound.dialogue_voice_consonant_timing(engine_sound.dialogue_voice_token("ch"))
    uppercase_ch_delay, uppercase_ch_attack := engine_sound.dialogue_voice_consonant_timing(
        engine_sound.dialogue_voice_token("CH"),
    )
    s_delay, s_attack := engine_sound.dialogue_voice_consonant_timing('s')
    testing.expect(t, p_delay > k_delay && k_delay > t_delay && t_delay > 0)
    testing.expect(t, p_attack != k_attack && k_attack != t_attack)
    testing.expect(t, ch_delay == uppercase_ch_delay && ch_attack == uppercase_ch_attack)
    testing.expect(t, s_delay == 0 && s_attack == .0032)

    profile := engine_sound.Dialogue_Voice_Profile{380, 150, .7, .55, .1, 0}
    stop, without_burst: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&stop, 'p', profile, .Consonant)
    without_burst = stop
    without_burst.onset_mix = 0
    stop_samples, dry_samples: [1024]f32
    engine_sound.render_dialogue_voice_add(&stop, stop_samples[:])
    engine_sound.render_dialogue_voice_add(&without_burst, dry_samples[:])
    closure_samples := int(p_delay * engine_sound.SAMPLE_RATE)
    for index in 0 ..< closure_samples {
        testing.expect(t, stop_samples[index] == dry_samples[index])
    }
    burst_difference := f32(0)
    for index in closure_samples ..< len(stop_samples) {
        burst_difference += abs(stop_samples[index] - dry_samples[index])
    }
    testing.expect(t, burst_difference > .01)
}

@(test)
fricatives_sustain_brighter_synthesized_noise_than_plosives :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{380, 150, .7, .55, .1, 0}
    fricative, plosive: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&fricative, 's', profile, .Consonant)
    engine_sound.trigger_dialogue_voice(&plosive, 'k', profile, .Consonant)
    testing.expect(t, fricative.consonant_color > plosive.consonant_color)
    testing.expect(t, fricative.consonant_decay < plosive.consonant_decay)

    fricative_dry, plosive_dry := fricative, plosive
    fricative_dry.onset_mix = 0
    plosive_dry.onset_mix = 0
    fricative_samples, fricative_dry_samples, plosive_samples, plosive_dry_samples: [2048]f32
    engine_sound.render_dialogue_voice_add(&fricative, fricative_samples[:])
    engine_sound.render_dialogue_voice_add(&fricative_dry, fricative_dry_samples[:])
    engine_sound.render_dialogue_voice_add(&plosive, plosive_samples[:])
    engine_sound.render_dialogue_voice_add(&plosive_dry, plosive_dry_samples[:])
    fricative_tail, plosive_tail := f32(0), f32(0)
    for index in 900 ..< 1500 {
        fricative_tail += abs(fricative_samples[index] - fricative_dry_samples[index])
        plosive_tail += abs(plosive_samples[index] - plosive_dry_samples[index])
    }
    testing.expect(t, fricative_tail > plosive_tail * 2)
}

@(test)
melodic_pitch_does_not_shift_the_synthesized_vocal_tract :: proc(t: ^testing.T) {
    low_profile := engine_sound.Dialogue_Voice_Profile{360, 0, .65, .55, .1, 0}
    melodic_profile := engine_sound.Dialogue_Voice_Profile{360, 240, .65, .55, .1, 0}
    stable, melodic: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&stable, 'e', low_profile, .Vowel)
    engine_sound.trigger_dialogue_voice(&melodic, 'e', melodic_profile, .Vowel)

    testing.expect(t, stable.frequency != melodic.frequency)
    testing.expect(t, stable.formant_base_hz == melodic.formant_base_hz)
    testing.expect(t, stable.formant_c_hz == melodic.formant_c_hz)
    testing.expect(t, stable.formant_ratio_a == melodic.formant_ratio_a)
    testing.expect(t, stable.formant_ratio_b == melodic.formant_ratio_b)
    testing.expect(
        t,
        stable.formant_base_hz * stable.formant_ratio_a == melodic.formant_base_hz * melodic.formant_ratio_a,
    )
    testing.expect(
        t,
        stable.formant_base_hz * stable.formant_ratio_b == melodic.formant_base_hz * melodic.formant_ratio_b,
    )
}

@(test)
authored_tract_reference_decouples_source_pitch_from_character_size :: proc(t: ^testing.T) {
    low_profile := engine_sound.Dialogue_Voice_Profile{280, 0, .65, .55, .1, 360}
    high_profile := low_profile
    high_profile.base_hz = 520
    low, high: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&low, 'e', low_profile, .Vowel)
    engine_sound.trigger_dialogue_voice(&high, 'e', high_profile, .Vowel)

    testing.expect(t, low.frequency == 280)
    testing.expect(t, high.frequency == 520)
    testing.expect(t, low.formant_base_hz == 360)
    testing.expect(t, high.formant_base_hz == 360)
    testing.expect(t, low.formant_c_hz == high.formant_c_hz)
    testing.expect(t, low.formant_ratio_a == high.formant_ratio_a)
    testing.expect(t, low.formant_ratio_b == high.formant_ratio_b)

    legacy := engine_sound.Dialogue_Voice_Profile{315, 0, .65, .55, .1, 0}
    legacy_voice: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&legacy_voice, 'e', legacy, .Vowel)
    testing.expect(t, legacy_voice.formant_base_hz == legacy.base_hz)
}

@(test)
tract_relative_pitch_compensation_keeps_transposition_from_becoming_gain :: proc(t: ^testing.T) {
    low_gain := engine_sound.dialogue_voice_pitch_loudness_compensation(260, 345)
    centered_gain := engine_sound.dialogue_voice_pitch_loudness_compensation(345, 345)
    high_gain := engine_sound.dialogue_voice_pitch_loudness_compensation(480, 345)
    testing.expect(t, low_gain > centered_gain && centered_gain > high_gain)
    testing.expect(t, centered_gain == 1)
    testing.expect(t, engine_sound.dialogue_voice_pitch_loudness_compensation(1, 1000) == 1.40)
    testing.expect(t, engine_sound.dialogue_voice_pitch_loudness_compensation(1000, 1) == .68)
    testing.expect(t, engine_sound.dialogue_voice_pitch_loudness_compensation(0, 345) == 1)

    low_profile := engine_sound.Dialogue_Voice_Profile{260, 0, .54, .68, .105, 345}
    high_profile := low_profile
    high_profile.base_hz = 480
    low, high: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&low, 'e', low_profile, .Vowel)
    engine_sound.trigger_dialogue_voice(&high, 'e', high_profile, .Vowel)
    low_samples, high_samples: [4096]f32
    engine_sound.render_dialogue_voice_add(&low, low_samples[:])
    engine_sound.render_dialogue_voice_add(&high, high_samples[:])
    low_energy, high_energy := f64(0), f64(0)
    for index in 0 ..< len(low_samples) {
        low_energy += f64(low_samples[index] * low_samples[index])
        high_energy += f64(high_samples[index] * high_samples[index])
    }
    energy_ratio := high_energy / low_energy
    testing.expect(t, energy_ratio > .65 && energy_ratio < 1.55)
}

@(test)
formant_shift_changes_character_size_without_transposing_the_source :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{360, 180, .65, .55, .1, 0}
    large, small: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&large, 'e', profile, .Vowel, -4)
    engine_sound.trigger_dialogue_voice(&small, 'e', profile, .Vowel, 4)

    testing.expect(t, large.frequency == small.frequency)
    testing.expect(t, large.formant_base_hz < small.formant_base_hz)
    testing.expect(t, large.formant_c_hz < small.formant_c_hz)
    testing.expect(t, large.formant_ratio_a == small.formant_ratio_a)
    testing.expect(t, large.formant_ratio_b == small.formant_ratio_b)

    large_samples, small_samples: [2048]f32
    engine_sound.render_dialogue_voice_add(&large, large_samples[:])
    engine_sound.render_dialogue_voice_add(&small, small_samples[:])
    testing.expect(t, large_samples != small_samples)

    clamped: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&clamped, 'e', profile, .Vowel, 100)
    maximum_formant_base := profile.base_hz * f32(math.pow(2, f64(7.0 / 12.0)))
    testing.expect(t, abs(clamped.formant_base_hz - maximum_formant_base) < .001)
}

@(test)
synthesized_head_resonance_tracks_character_brightness_not_melody :: proc(t: ^testing.T) {
    soft_profile := engine_sound.Dialogue_Voice_Profile{360, 180, .2, .6, .1, 0}
    bright_profile := engine_sound.Dialogue_Voice_Profile{360, 180, .9, .6, .1, 0}
    soft, bright: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&soft, 'e', soft_profile, .Vowel)
    engine_sound.trigger_dialogue_voice(&bright, 'e', bright_profile, .Vowel)
    testing.expect(t, bright.formant_c_hz > soft.formant_c_hz)
    testing.expect(t, soft.formant_c_hz >= 2200 && soft.formant_c_hz <= 4300)
    testing.expect(t, bright.formant_c_hz >= 2200 && bright.formant_c_hz <= 4300)

    samples: [2048]f32
    engine_sound.render_dialogue_voice_add(&bright, samples[:])
    testing.expect(t, abs(bright.formant_c_y1) > .000001 || abs(bright.formant_c_y2) > .000001)
}

@(test)
synthesized_glottal_source_is_bounded_deterministic_and_timbre_shaped :: proc(t: ^testing.T) {
    bright_residual, warm_residual := f32(0), f32(0)
    for index in 0 ..< 2048 {
        phase := f32(index) / 2048
        sine := f32(math.sin(f64(phase * math.TAU)))
        plain := engine_sound.dialogue_voice_glottal_source(phase, 0, 1, 0)
        bright := engine_sound.dialogue_voice_glottal_source(phase, 1, 1, 0)
        warm := engine_sound.dialogue_voice_glottal_source(phase, 1, 0, 1)
        replay := engine_sound.dialogue_voice_glottal_source(phase, 1, 1, 0)

        testing.expect(t, abs(plain - sine) < .000001)
        testing.expect(t, bright == replay)
        testing.expect(t, abs(bright) <= 1)
        testing.expect(t, abs(warm) <= 1)
        bright_residual += (bright - sine) * (bright - sine)
        warm_residual += (warm - sine) * (warm - sine)
    }
    testing.expect(t, bright_residual > warm_residual * 2)
}

@(test)
synthesized_vocal_tract_resonator_prefers_its_center_frequency :: proc(t: ^testing.T) {
    center_y1, center_y2, off_y1, off_y2 := f32(0), f32(0), f32(0), f32(0)
    center_energy, off_energy := f32(0), f32(0)
    for index in 0 ..< 4096 {
        time := f32(index) / engine_sound.SAMPLE_RATE
        center_input := f32(math.sin(f64(math.TAU * 1000 * time)))
        off_input := f32(math.sin(f64(math.TAU * 3000 * time)))
        centered := engine_sound.dialogue_voice_resonator(center_input, 1000, 120, &center_y1, &center_y2)
        off_center := engine_sound.dialogue_voice_resonator(off_input, 1000, 120, &off_y1, &off_y2)
        if index >= 512 {
            center_energy += centered * centered
            off_energy += off_center * off_center
        }
    }
    testing.expect(t, center_energy > off_energy * 20)
}

@(test)
resonator_honors_broad_consonant_bands_without_changing_vowel_bands :: proc(t: ^testing.T) {
    vowel_y1, vowel_y2, narrow_y1, narrow_y2, broad_y1, broad_y2 := f32(0), f32(0), f32(0), f32(0), f32(0), f32(0)
    vowel_first := engine_sound.dialogue_voice_resonator(1, 1000, 180, &vowel_y1, &vowel_y2)
    narrow_first := engine_sound.dialogue_voice_resonator(1, 5000, 620, &narrow_y1, &narrow_y2)
    broad_first := engine_sound.dialogue_voice_resonator(1, 5000, 1800, &broad_y1, &broad_y2)
    expected_vowel_first := 1 - f32(math.exp(f64(-math.PI * 180 / engine_sound.SAMPLE_RATE)))
    testing.expect(t, abs(vowel_first - expected_vowel_first) < .000001)
    testing.expect(t, broad_first > narrow_first)

    broad_peak := abs(broad_first)
    for index in 1 ..< 4096 {
        input := index & 1 == 0 ? f32(1) : f32(-1)
        output := engine_sound.dialogue_voice_resonator(input, 5000, 1800, &broad_y1, &broad_y2)
        broad_peak = max(broad_peak, abs(output))
    }
    testing.expect(t, broad_peak < 2)
}

@(test)
dialogue_vowels_are_longer_and_more_voiced_than_consonants :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{330, 100, .6, .6, .1, 0}
    vowel, consonant: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&vowel, engine_sound.dialogue_voice_token("a"), profile, .Vowel)
    engine_sound.trigger_dialogue_voice(&consonant, engine_sound.dialogue_voice_token("a"), profile, .Consonant)

    testing.expect(t, engine_sound.dialogue_voice_articulation("A") == .Vowel)
    testing.expect(t, engine_sound.dialogue_voice_articulation("č") == .Consonant)
    testing.expect(t, vowel.duration > consonant.duration)
    testing.expect(t, vowel.voicing > consonant.voicing)
    testing.expect(t, vowel.onset_mix < consonant.onset_mix)
}

@(test)
common_terminal_silent_e_and_vocalic_y_shape_stylized_word_rhythm :: proc(t: ^testing.T) {
    testing.expect(t, engine_sound.dialogue_voice_is_silent_terminal_e("make", 3, 4))
    testing.expect(t, engine_sound.dialogue_voice_is_silent_terminal_e("HOME!", 3, 4))
    testing.expect(t, engine_sound.dialogue_voice_is_silent_terminal_e("little", 5, 6))
    testing.expect(t, !engine_sound.dialogue_voice_is_silent_terminal_e("me", 1, 2))
    testing.expect(t, !engine_sound.dialogue_voice_is_silent_terminal_e("she", 2, 3))
    testing.expect(t, !engine_sound.dialogue_voice_is_silent_terminal_e("meeting", 1, 2))
    testing.expect(t, !engine_sound.dialogue_voice_is_silent_terminal_e("café", 3, 5))

    testing.expect(t, engine_sound.dialogue_voice_articulation("y") == .Vowel)
    profile := engine_sound.Dialogue_Voice_Profile{360, 120, .6, .6, .1, 0}
    i_voice, y_voice: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&i_voice, 'i', profile, .Vowel)
    engine_sound.trigger_dialogue_voice(&y_voice, 'y', profile, .Vowel)
    testing.expect(t, i_voice.formant_ratio_a == y_voice.formant_ratio_a)
    testing.expect(t, i_voice.formant_ratio_b == y_voice.formant_ratio_b)
}

@(test)
dialogue_phrase_coarticulation_bounds_adjacent_pitch_leaps :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{330, 360, .6, .6, .1, 0}
    mixer: engine_sound.Dialogue_Voice_Mixer
    first_index := engine_sound.trigger_dialogue_voice_mixer(
        &mixer,
        engine_sound.dialogue_voice_token("a"),
        profile,
        0,
        .Vowel,
    )
    first_frequency := mixer.voices[first_index].frequency
    second_index := engine_sound.trigger_dialogue_voice_mixer(
        &mixer,
        engine_sound.dialogue_voice_token("u"),
        profile,
        0,
        .Vowel,
    )
    second_frequency := mixer.voices[second_index].frequency

    testing.expect(t, second_frequency >= first_frequency * .89)
    testing.expect(t, second_frequency <= first_frequency * 1.11)
    testing.expect(t, mixer.previous_frequency == second_frequency)
}

@(test)
adjacent_synthesized_units_join_with_short_bounded_portamento :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{330, 360, .6, .6, .1, 0}
    mixer: engine_sound.Dialogue_Voice_Mixer
    first_index := engine_sound.trigger_dialogue_voice_mixer(
        &mixer,
        engine_sound.dialogue_voice_token("a"),
        profile,
        0,
        .Vowel,
    )
    first_frequency := mixer.voices[first_index].frequency
    testing.expect(t, mixer.voices[first_index].portamento_seconds == 0)

    second_index := engine_sound.trigger_dialogue_voice_mixer(
        &mixer,
        engine_sound.dialogue_voice_token("u"),
        profile,
        0,
        .Vowel,
    )
    second := &mixer.voices[second_index]
    connected_frequency := second.frequency * second.pitch_start_ratio
    testing.expect(t, abs(connected_frequency - first_frequency) < .01)
    testing.expect(t, second.pitch_start_ratio >= .88 && second.pitch_start_ratio <= 1.13)
    testing.expect(t, second.portamento_seconds == .026)

    consonant_index := engine_sound.trigger_dialogue_voice_mixer(
        &mixer,
        engine_sound.dialogue_voice_token("k"),
        profile,
        0,
        .Consonant,
    )
    testing.expect(t, mixer.voices[consonant_index].portamento_seconds == .018)

    engine_sound.dialogue_voice_mixer_phrase_boundary(&mixer)
    fresh_index := engine_sound.trigger_dialogue_voice_mixer(
        &mixer,
        engine_sound.dialogue_voice_token("e"),
        profile,
        0,
        .Vowel,
    )
    testing.expect(t, mixer.voices[fresh_index].portamento_seconds == 0)
    testing.expect(t, mixer.voices[fresh_index].pitch_start_ratio == 1)
}

@(test)
word_progress_shapes_one_coherent_rise_and_settle_gesture :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{360, 150, .6, .6, .1, 0}
    plain, shaped: engine_sound.Dialogue_Voice_Mixer
    progress := [?]f32{0, .25, .5, .75, 1}
    plain_frequencies, shaped_frequencies: [len(progress)]f32
    for word_progress, index in progress {
        plain_index := engine_sound.trigger_dialogue_voice_mixer(&plain, 'e', profile, 0, .Vowel)
        shaped_index := engine_sound.trigger_dialogue_voice_mixer(&shaped, 'e', profile, 0, .Vowel, word_progress)
        plain_frequencies[index] = plain.voices[plain_index].frequency
        shaped_frequencies[index] = shaped.voices[shaped_index].frequency
    }

    testing.expect(t, shaped_frequencies[2] > plain_frequencies[2])
    testing.expect(t, shaped_frequencies[4] < plain_frequencies[4])
    testing.expect(t, shaped_frequencies[2] > shaped_frequencies[0])
    testing.expect(t, shaped_frequencies[4] < shaped_frequencies[2])
}

@(test)
word_and_phrase_microdynamics_create_a_bounded_expression_scaled_swell :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{360, 150, .6, .6, .1, 0}
    start_mixer, middle_mixer, end_mixer, restrained_mixer: engine_sound.Dialogue_Voice_Mixer
    start_index := engine_sound.trigger_dialogue_voice_mixer(&start_mixer, 'e', profile, 0, .Vowel, 0, 1)
    middle_index := engine_sound.trigger_dialogue_voice_mixer(&middle_mixer, 'e', profile, 0, .Vowel, .5, 1)
    end_index := engine_sound.trigger_dialogue_voice_mixer(&end_mixer, 'e', profile, 0, .Vowel, 1, 1)
    restrained_index := engine_sound.trigger_dialogue_voice_mixer(&restrained_mixer, 'e', profile, 0, .Vowel, .5, 0)

    start_gain := start_mixer.voices[start_index].performance_gain
    middle_gain := middle_mixer.voices[middle_index].performance_gain
    end_gain := end_mixer.voices[end_index].performance_gain
    restrained_gain := restrained_mixer.voices[restrained_index].performance_gain
    testing.expect(t, middle_gain > start_gain)
    testing.expect(t, start_gain > end_gain)
    testing.expect(t, middle_gain <= 1.10 && end_gain >= .92)
    testing.expect(t, abs(restrained_gain - 1) < abs(middle_gain - 1))

    quiet := start_mixer.voices[start_index]
    swelled := quiet
    swelled.performance_gain = middle_gain
    quiet.performance_gain = end_gain
    quiet_samples, swelled_samples: [2048]f32
    engine_sound.render_dialogue_voice_add(&quiet, quiet_samples[:])
    engine_sound.render_dialogue_voice_add(&swelled, swelled_samples[:])
    quiet_energy, swelled_energy := f32(0), f32(0)
    for index in 0 ..< len(quiet_samples) {
        quiet_energy += quiet_samples[index] * quiet_samples[index]
        swelled_energy += swelled_samples[index] * swelled_samples[index]
    }
    testing.expect(t, swelled_energy > quiet_energy)

    phrase: engine_sound.Dialogue_Voice_Mixer
    phrase_gains: [15]f32
    for &gain, index in phrase_gains {
        voice_index := engine_sound.trigger_dialogue_voice_mixer(&phrase, 'e', profile, 0, .Vowel)
        gain = phrase.voices[voice_index].performance_gain
    }
    testing.expect(t, phrase_gains[7] > phrase_gains[0])
    testing.expect(t, phrase_gains[7] > phrase_gains[14])
}
