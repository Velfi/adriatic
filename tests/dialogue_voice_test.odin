package tests

import engine_sound "../packages/engine_sound"
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
dialogue_utf8_graphemes_have_distinct_stable_articulation_tokens :: proc(t: ^testing.T) {
    c_caron := engine_sound.dialogue_voice_token("č")
    c_acute := engine_sound.dialogue_voice_token("ć")
    s_caron := engine_sound.dialogue_voice_token("š")
    testing.expect(t, c_caron == engine_sound.dialogue_voice_token("č"))
    testing.expect(t, c_caron != c_acute)
    testing.expect(t, c_caron != s_caron)
    testing.expect(t, c_acute != s_caron)

    profile := engine_sound.Dialogue_Voice_Profile{330, 100, .6, .6, .1}
    first, second: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&first, c_caron, profile)
    engine_sound.trigger_dialogue_voice(&second, c_acute, profile)
    testing.expect(t, first.frequency != second.frequency)
    testing.expect(
        t,
        first.formant_ratio_a != second.formant_ratio_a || first.formant_ratio_b != second.formant_ratio_b,
    )
}

@(test)
authored_punctuation_hint_adds_falling_phrase_cadence :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{330, 100, .6, .6, .1}
    plain, terminal: engine_sound.Dialogue_Voice_Mixer
    plain_index := engine_sound.trigger_dialogue_voice_mixer(&plain, 'a', profile)
    terminal_index := engine_sound.trigger_dialogue_voice_mixer(&terminal, 'a', profile, 1)
    testing.expect(t, terminal.voices[terminal_index].frequency < plain.voices[plain_index].frequency)
    testing.expect(t, terminal.voices[terminal_index].pitch_glide < plain.voices[plain_index].pitch_glide)
}

@(test)
dialogue_vowels_have_stable_distinct_mouth_shapes :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{390, 170, .7, .45, .1}
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
    profile := engine_sound.Dialogue_Voice_Profile{400, 200, .65, .55, .1}
    unique: [16]f32
    unique_count := 0
    for glyph in "abcdefghijklmnopqrstuv" {
        voice: engine_sound.Dialogue_Voice
        engine_sound.trigger_dialogue_voice(&voice, u32(glyph), profile)
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
    testing.expect(t, unique_count <= 7)
}

@(test)
question_cadence_lifts_while_statement_cadence_falls :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{360, 140, .6, .6, .1}
    plain, question, statement: engine_sound.Dialogue_Voice_Mixer
    plain_index := engine_sound.trigger_dialogue_voice_mixer(&plain, 'e', profile)
    question_index := engine_sound.trigger_dialogue_voice_mixer(&question, 'e', profile, -1)
    statement_index := engine_sound.trigger_dialogue_voice_mixer(&statement, 'e', profile, 1)

    testing.expect(t, question.voices[question_index].frequency > plain.voices[plain_index].frequency)
    testing.expect(t, statement.voices[statement_index].frequency < plain.voices[plain_index].frequency)
    testing.expect(t, question.voices[question_index].pitch_glide > statement.voices[statement_index].pitch_glide)
}

@(test)
synthesized_cv_unit_transitions_into_the_authored_vowel_shape :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{380, 150, .7, .55, .1}
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
    profile := engine_sound.Dialogue_Voice_Profile{380, 150, .7, .55, .1}
    engine_sound.dialogue_voice_trigger_grapheme(&device, "k", profile, 0, "a")
    testing.expect(t, device.dialogue_voice.consumed_vowel)
    testing.expect(t, device.dialogue_voice.syllable_index == 1)

    engine_sound.dialogue_voice_trigger_grapheme(&device, "a", profile)
    testing.expect(t, !device.dialogue_voice.consumed_vowel)
    testing.expect(t, device.dialogue_voice.syllable_index == 1)
}

@(test)
synthesized_vcv_unit_carries_the_previous_vowel_through_the_consonant :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{380, 150, .7, .55, .1}
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
    profile := engine_sound.Dialogue_Voice_Profile{380, 150, .7, .55, .1}
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

    profile := engine_sound.Dialogue_Voice_Profile{380, 150, .7, .55, .1}
    ka_voice, ke_voice: engine_sound.Dialogue_Voice
    engine_sound.trigger_dialogue_voice(&ka_voice, ka, profile, .Consonant)
    engine_sound.trigger_dialogue_voice(&ke_voice, ke, profile, .Consonant)
    testing.expect(t, ka_voice.frequency != ke_voice.frequency)
}


@(test)
dialogue_vowels_are_longer_and_more_voiced_than_consonants :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{330, 100, .6, .6, .1}
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
dialogue_phrase_coarticulation_bounds_adjacent_pitch_leaps :: proc(t: ^testing.T) {
    profile := engine_sound.Dialogue_Voice_Profile{330, 360, .6, .6, .1}
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
