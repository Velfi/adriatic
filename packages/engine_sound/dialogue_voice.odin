package engine_sound

import "core:math"

// Dialogue_Voice_Profile is deliberately presentation-neutral. Games choose
// stable profiles for their speakers and feed visible glyphs to the synth.
Dialogue_Voice_Profile :: struct {
    base_hz:    f32,
    range_hz:   f32,
    brightness: f32,
    warmth:     f32,
    gain:       f32,
}

Dialogue_Articulation :: enum u8 {
    Neutral,
    Vowel,
    Consonant,
}

Dialogue_Voice :: struct {
    phase_a:            f32,
    phase_b:            f32,
    phase_c:            f32,
    age:                f32,
    duration:           f32,
    frequency:          f32,
    formant_ratio_a:    f32,
    formant_ratio_b:    f32,
    previous_formant_a: f32,
    previous_formant_b: f32,
    target_formant_a:   f32,
    target_formant_b:   f32,
    onset_mix:          f32,
    voicing:            f32,
    target_voicing:     f32,
    pitch_glide:        f32,
    brightness:         f32,
    warmth:             f32,
    gain:               f32,
    noise_state:        u32,
    breath_fast:        f32,
    breath_low:         f32,
    body_low:           f32,
    pulse_mix:          f32,
    previous_pulse_mix: f32,
    target_pulse_mix:   f32,
    vibrato_depth:      f32,
    coarticulation:     f32,
    has_vcv_lead:       bool,
}

DIALOGUE_VOICE_COUNT :: 3

Dialogue_Voice_Mixer :: struct {
    voices:             [DIALOGUE_VOICE_COUNT]Dialogue_Voice,
    next_voice:         int,
    syllable_index:     u32,
    previous_token:     u32,
    previous_frequency: f32,
    unit_blend:         f32,
    consumed_vowel:     bool,
    carried_formant_a:  f32,
    carried_formant_b:  f32,
    carried_pulse_mix:  f32,
    carried_vowel:      bool,
}

dialogue_voice_token :: proc(grapheme: string) -> u32 {
    if len(grapheme) == 1 do return u32(grapheme[0])
    hash := u32(2_166_136_261)
    for byte in grapheme {
        hash = (hash ~ u32(byte)) * 16_777_619
    }
    return hash
}

dialogue_voice_unit_token :: proc(grapheme, next_grapheme: string) -> u32 {
    if dialogue_voice_articulation(grapheme) != .Consonant || dialogue_voice_articulation(next_grapheme) != .Vowel {
        return dialogue_voice_token(grapheme)
    }
    hash := u32(2_166_136_261)
    for byte in grapheme {
        hash = (hash ~ u32(byte)) * 16_777_619
    }
    for byte in next_grapheme {
        hash = (hash ~ u32(byte)) * 16_777_619
    }
    return hash
}

dialogue_voice_articulation :: proc(grapheme: string) -> Dialogue_Articulation {
    if len(grapheme) == 0 do return .Neutral
    if grapheme == "a" ||
       grapheme == "e" ||
       grapheme == "i" ||
       grapheme == "o" ||
       grapheme == "u" ||
       grapheme == "A" ||
       grapheme == "E" ||
       grapheme == "I" ||
       grapheme == "O" ||
       grapheme == "U" {
        return .Vowel
    }
    return .Consonant
}

dialogue_voice_shape :: proc(token: u32, hash: u32) -> (formant_a, formant_b, onset, pulse, duration, glide: f32) {
    glyph := u8(0)
    if token <= 127 {
        glyph = u8(token)
        if glyph >= 'A' && glyph <= 'Z' do glyph += 'a' - 'A'
    }
    // Broad mouth-shape families create recognizable articulation without
    // binding the reusable synth to a particular language or character.
    switch glyph {
    case 'a':
        return 1.72, 3.18, .035, .22, .074, .018
    case 'e':
        return 2.18, 4.72, .025, .16, .070, .012
    case 'i', 'y':
        return 2.62, 5.35, .018, .11, .068, .006
    case 'o':
        return 1.48, 2.62, .025, .32, .076, -.012
    case 'u':
        return 1.30, 2.22, .018, .38, .078, -.018
    case 'm', 'n', 'l', 'r', 'w':
        return 1.55, 2.72, .10, .35, .064, -.008
    case 'b', 'd', 'g', 'j', 'v', 'z':
        return 1.88, 3.44, .28, .24, .058, .022
    case 'f', 'h', 's', 'x':
        return 2.35, 5.10, .54, .08, .050, .032
    case 'c', 'k', 'p', 'q', 't':
        return 2.08, 4.15, .43, .15, .052, .040
    }
    return 1.62 + f32((hash >> 12) & 7) / 7 * .72,
        3.05 + f32((hash >> 16) & 7) / 7 * 1.65,
        .10 + f32((hash >> 20) & 7) / 7 * .25,
        .18 + f32((hash >> 24) & 3) / 3 * .18,
        .060 + f32((hash >> 8) & 3) * .003,
        (f32((hash >> 23) & 15) / 15 - .5) * .035
}

dialogue_voice_apply_cv_unit :: proc(voice: ^Dialogue_Voice, next_grapheme: string, amount: f32) -> bool {
    if voice == nil || amount <= 0 || dialogue_voice_articulation(next_grapheme) != .Vowel do return false
    token := dialogue_voice_token(next_grapheme)
    hash := token * 747796405 + 2891336453
    formant_a, formant_b, onset, pulse, duration, glide := dialogue_voice_shape(token, hash)
    _ = onset
    _ = glide
    voice.target_formant_a = formant_a
    voice.target_formant_b = formant_b
    voice.target_pulse_mix = pulse
    voice.target_voicing = 1.06
    voice.coarticulation = clamp(amount, 0, 1)
    voice.duration = max(voice.duration, duration + .020 * voice.coarticulation)
    return true
}

trigger_dialogue_voice :: proc(
    voice: ^Dialogue_Voice,
    token: u32,
    profile: Dialogue_Voice_Profile,
    articulation: Dialogue_Articulation = .Neutral,
) {
    if voice == nil do return
    // A tiny deterministic hash gives words melodic motion without attempting
    // to imitate phonemes from any authored language.
    hash := token * 747796405 + 2891336453
    pitch_steps := [?]f32{-5, -2, 0, 2, 4, 7, 9}
    pitch_step := pitch_steps[int(hash & 7) % len(pitch_steps)]
    pitch_span := clamp(profile.range_hz / max(profile.base_hz, f32(1)), 0, 1)
    musical_ratio := f32(math.pow(2, f64(pitch_step / 12 * pitch_span)))
    formant_a, formant_b, onset, pulse, duration, glide := dialogue_voice_shape(token, hash)
    voice.age = 0
    voice.duration = duration
    voice.frequency = max(profile.base_hz * musical_ratio, f32(90))
    voice.formant_ratio_a = formant_a
    voice.formant_ratio_b = formant_b
    voice.previous_formant_a = formant_a
    voice.previous_formant_b = formant_b
    voice.target_formant_a = formant_a
    voice.target_formant_b = formant_b
    voice.onset_mix = onset
    voice.voicing = 1
    voice.target_voicing = 1
    voice.pitch_glide = glide
    voice.brightness = clamp(profile.brightness, 0, 1)
    voice.warmth = clamp(profile.warmth, 0, 1)
    voice.gain = clamp(profile.gain, 0, .24)
    voice.noise_state = hash ~ 0xa511e9b3
    voice.breath_fast = 0
    voice.breath_low = 0
    voice.body_low = 0
    voice.pulse_mix = pulse
    voice.previous_pulse_mix = pulse
    voice.target_pulse_mix = pulse
    voice.vibrato_depth = .006 + voice.brightness * .009
    voice.coarticulation = 0
    voice.has_vcv_lead = false
    switch articulation {
    case .Vowel:
        voice.duration += .008
        voice.onset_mix *= .42
        voice.pitch_glide *= .78
        voice.voicing = 1.06
    case .Consonant:
        voice.duration = max(voice.duration - .009, f32(.038))
        voice.onset_mix = min(voice.onset_mix * 1.48, f32(.58))
        voice.brightness = clamp(voice.brightness + .08, 0, 1)
        voice.voicing = .72
    case .Neutral:
    }
}

dialogue_voice_trigger :: proc(device: ^Device, glyph: u8, profile: Dialogue_Voice_Profile) {
    if device == nil || device.stream == nil do return
    trigger_dialogue_voice_mixer(&device.dialogue_voice, u32(glyph), profile)
}

dialogue_voice_trigger_grapheme :: proc(
    device: ^Device,
    grapheme: string,
    profile: Dialogue_Voice_Profile,
    cadence_hint: f32 = 0,
    next_grapheme: string = "",
) {
    if device == nil || device.stream == nil || len(grapheme) == 0 do return
    _ = dialogue_voice_trigger_grapheme_mixer(&device.dialogue_voice, grapheme, profile, cadence_hint, next_grapheme)
}

dialogue_voice_trigger_grapheme_mixer :: proc(
    mixer: ^Dialogue_Voice_Mixer,
    grapheme: string,
    profile: Dialogue_Voice_Profile,
    cadence_hint: f32 = 0,
    next_grapheme: string = "",
) -> bool {
    if mixer == nil || len(grapheme) == 0 do return false
    articulation := dialogue_voice_articulation(grapheme)
    if mixer.consumed_vowel && articulation == .Vowel {
        mixer.consumed_vowel = false
        return false
    }
    mixer.consumed_vowel = false
    voice_index := trigger_dialogue_voice_mixer(
        mixer,
        dialogue_voice_unit_token(grapheme, next_grapheme),
        profile,
        cadence_hint,
        articulation,
    )
    voice := &mixer.voices[voice_index]
    if articulation == .Consonant && dialogue_voice_apply_cv_unit(voice, next_grapheme, mixer.unit_blend) {
        if mixer.carried_vowel {
            voice.previous_formant_a = mixer.carried_formant_a
            voice.previous_formant_b = mixer.carried_formant_b
            voice.previous_pulse_mix = mixer.carried_pulse_mix
            voice.has_vcv_lead = true
        }
        mixer.carried_formant_a = voice.target_formant_a
        mixer.carried_formant_b = voice.target_formant_b
        mixer.carried_pulse_mix = voice.target_pulse_mix
        mixer.carried_vowel = true
        mixer.consumed_vowel = true
    } else if articulation == .Vowel {
        mixer.carried_formant_a = voice.formant_ratio_a
        mixer.carried_formant_b = voice.formant_ratio_b
        mixer.carried_pulse_mix = voice.pulse_mix
        mixer.carried_vowel = true
    }
    return true
}

trigger_dialogue_voice_mixer :: proc(
    mixer: ^Dialogue_Voice_Mixer,
    token: u32,
    profile: Dialogue_Voice_Profile,
    cadence_hint: f32 = 0,
    articulation: Dialogue_Articulation = .Neutral,
) -> int {
    if mixer == nil do return -1
    voice_index := mixer.next_voice
    // Normal 32 ms reveal cadence overlaps only two 52–66 ms syllables. Prefer
    // an idle voice, then replace the oldest tail if a frame hitch reveals
    // several glyphs at once.
    oldest_progress := f32(-1)
    for offset in 0 ..< DIALOGUE_VOICE_COUNT {
        candidate := (mixer.next_voice + offset) % DIALOGUE_VOICE_COUNT
        voice := &mixer.voices[candidate]
        if voice.duration <= 0 || voice.age >= voice.duration {
            voice_index = candidate
            break
        }
        progress := voice.age / voice.duration
        if progress > oldest_progress {
            voice_index = candidate
            oldest_progress = progress
        }
    }
    trigger_dialogue_voice(&mixer.voices[voice_index], token, profile, articulation)
    voice := &mixer.voices[voice_index]
    // A quiet phrase contour breaks the "same letter, same note" pattern
    // while remaining stable for replays. Repeated glyphs receive a slightly
    // different inflection, as real articulation never repeats at an
    // identical pitch and attack.
    phrase_position := clamp(f32(mixer.syllable_index) / 14, 0, 1)
    phrase_arch := f32(math.sin(f64(phrase_position * math.PI))) * .028
    cadence := f32(0)
    if mixer.syllable_index >= 10 {
        cadence = -min(f32(mixer.syllable_index - 9) * .004, f32(.025))
    }
    repetition := token == mixer.previous_token && mixer.syllable_index > 0 ? f32(.018) : f32(0)
    alternating := mixer.syllable_index & 1 == 0 ? f32(-.004) : f32(.004)
    authored_cadence := clamp(cadence_hint, -1, 1)
    cadence_pitch := authored_cadence >= 0 ? -authored_cadence * .045 : -authored_cadence * .075
    voice.frequency *= 1 + phrase_arch + cadence + repetition + alternating + cadence_pitch
    voice.pitch_glide += repetition * .35 - cadence * .25 - authored_cadence * .032
    if mixer.previous_frequency > 0 {
        // Preserve speaker identity and melodic movement without letting a
        // hash-selected glyph leap to an unrelated note inside one phrase.
        step := articulation == .Consonant ? f32(.14) : f32(.11)
        voice.frequency = clamp(
            voice.frequency,
            mixer.previous_frequency * (1 - step),
            mixer.previous_frequency * (1 + step),
        )
    }
    mixer.previous_frequency = voice.frequency
    mixer.previous_token = token
    mixer.syllable_index += 1
    mixer.next_voice = (voice_index + 1) % DIALOGUE_VOICE_COUNT
    return voice_index
}

dialogue_voice_phrase_boundary :: proc(device: ^Device) {
    if device == nil do return
    dialogue_voice_mixer_phrase_boundary(&device.dialogue_voice)
}

dialogue_voice_mixer_phrase_boundary :: proc(mixer: ^Dialogue_Voice_Mixer) {
    if mixer == nil do return
    mixer.syllable_index = 0
    mixer.previous_token = 0
    mixer.previous_frequency = 0
    mixer.consumed_vowel = false
    dialogue_voice_mixer_word_boundary(mixer)
}

dialogue_voice_mixer_word_boundary :: proc(mixer: ^Dialogue_Voice_Mixer) {
    if mixer == nil do return
    mixer.carried_formant_a = 0
    mixer.carried_formant_b = 0
    mixer.carried_pulse_mix = 0
    mixer.carried_vowel = false
}

dialogue_voice_stop :: proc(device: ^Device) {
    if device == nil do return
    for &voice in device.dialogue_voice.voices {
        voice.duration = 0
        voice.age = 0
    }
    dialogue_voice_phrase_boundary(device)
}

render_dialogue_voice_add :: proc(voice: ^Dialogue_Voice, samples: []f32) {
    if voice == nil || voice.duration <= 0 do return
    seconds_per_sample := f32(1.0 / SAMPLE_RATE)
    for &sample in samples {
        if voice.age >= voice.duration {
            voice.duration = 0
            break
        }
        progress := voice.age / voice.duration
        transition := f32(0)
        if voice.coarticulation > 0 {
            transition = clamp((progress - .14) / .48, 0, 1)
            transition = transition * transition * (3 - 2 * transition) * voice.coarticulation
        }
        attack := min(voice.age / .007, f32(1))
        release := f32(math.pow(f64(max(1 - progress, f32(0))), 1.38))
        vibrato_fade := clamp((voice.age - .012) / .025, 0, 1)
        wobble := 1 + f32(math.sin(f64(voice.age * math.TAU * 7.2))) * voice.vibrato_depth * vibrato_fade
        contour := 1 + voice.pitch_glide * (1 - progress * 1.7)
        frequency := voice.frequency * wobble * contour
        voice.phase_a = math.mod(voice.phase_a + frequency * seconds_per_sample, 1)
        ratio_a := voice.formant_ratio_a > 0 ? voice.formant_ratio_a : f32(2.01)
        ratio_b := voice.formant_ratio_b > 0 ? voice.formant_ratio_b : f32(3.97)
        lead := f32(1)
        if voice.has_vcv_lead {
            lead = clamp(progress / .18, 0, 1)
            lead = lead * lead * (3 - 2 * lead)
            ratio_a = voice.previous_formant_a + (ratio_a - voice.previous_formant_a) * lead
            ratio_b = voice.previous_formant_b + (ratio_b - voice.previous_formant_b) * lead
        }
        ratio_a += (voice.target_formant_a - ratio_a) * transition
        ratio_b += (voice.target_formant_b - ratio_b) * transition
        voice.phase_b = math.mod(voice.phase_b + frequency * ratio_a * seconds_per_sample, 1)
        voice.phase_c = math.mod(voice.phase_c + frequency * ratio_b * seconds_per_sample, 1)
        fundamental := f32(math.sin(f64(voice.phase_a * math.TAU)))
        triangle := 1 - 4 * abs(voice.phase_a - .5)
        pulse_mix := voice.pulse_mix
        if voice.has_vcv_lead {
            pulse_mix = voice.previous_pulse_mix + (pulse_mix - voice.previous_pulse_mix) * lead
        }
        pulse_mix += (voice.target_pulse_mix - pulse_mix) * transition
        carrier := fundamental * (1 - pulse_mix) + triangle * pulse_mix
        bright :=
            f32(math.sin(f64(voice.phase_b * math.TAU))) * .34 + f32(math.sin(f64(voice.phase_c * math.TAU))) * .13
        body := carrier * (1 - voice.brightness * .32) + bright * voice.brightness
        smoothing := .52 - voice.warmth * .24
        voice.body_low += (body - voice.body_low) * smoothing
        body = body * (1 - voice.warmth * .48) + voice.body_low * voice.warmth * .48
        voicing := voice.voicing > 0 ? voice.voicing : f32(1)
        voicing += (voice.target_voicing - voicing) * transition
        breath := noise(&voice.noise_state)
        voice.breath_fast += (breath - voice.breath_fast) * (.19 + voice.brightness * .06)
        voice.breath_low += (breath - voice.breath_low) * (.06 + voice.brightness * .08)
        consonant_attack := min(voice.age / .0032, f32(1))
        consonant :=
            (voice.breath_fast - voice.breath_low) *
            voice.onset_mix *
            consonant_attack *
            f32(math.exp(f64(-voice.age * 92)))
        // A warm profile has a rounder envelope and less upper-partial energy.
        warmth_gain := .78 + voice.warmth * .22
        sample += (body * voicing * attack * warmth_gain + consonant) * release * voice.gain
        voice.age += seconds_per_sample
    }
}

render_dialogue_voice_mixer_add :: proc(mixer: ^Dialogue_Voice_Mixer, samples: []f32) {
    if mixer == nil do return
    for &voice in mixer.voices {
        render_dialogue_voice_add(&voice, samples)
    }
}
