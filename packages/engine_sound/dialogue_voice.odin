package engine_sound

import "core:math"
import "core:unicode"
import "core:unicode/utf8"

// Dialogue_Voice_Profile is deliberately presentation-neutral. Games choose
// stable profiles for their speakers and feed visible glyphs to the synth.
Dialogue_Voice_Profile :: struct {
    base_hz:    f32,
    range_hz:   f32,
    brightness: f32,
    warmth:     f32,
    gain:       f32,
    // Optional independent vocal-tract reference. Zero preserves the legacy
    // behavior by following base_hz; authored profiles set it so musical
    // pitch can be tuned without changing apparent character size.
    tract_hz:   f32,
}

Dialogue_Articulation :: enum u8 {
    Neutral,
    Vowel,
    Consonant,
}

Dialogue_Voice :: struct {
    phase_a:             f32,
    phase_b:             f32,
    phase_c:             f32,
    age:                 f32,
    duration:            f32,
    frequency:           f32,
    formant_base_hz:     f32,
    formant_c_hz:        f32,
    formant_ratio_a:     f32,
    formant_ratio_b:     f32,
    previous_formant_a:  f32,
    previous_formant_b:  f32,
    target_formant_a:    f32,
    target_formant_b:    f32,
    onset_mix:           f32,
    voicing:             f32,
    target_voicing:      f32,
    pitch_glide:         f32,
    pitch_start_ratio:   f32,
    portamento_seconds:  f32,
    onset_bloom_depth:   f32,
    onset_bloom_seconds: f32,
    brightness:          f32,
    warmth:              f32,
    gain:                f32,
    cadence_gain:        f32,
    performance_gain:    f32,
    release_power:       f32,
    noise_state:         u32,
    breath_fast:         f32,
    breath_low:          f32,
    body_low:            f32,
    consonant_color:     f32,
    consonant_decay:     f32,
    consonant_voiced:    f32,
    consonant_delay:     f32,
    consonant_attack:    f32,
    consonant_band_hz:   f32,
    consonant_bandwidth: f32,
    consonant_band_mix:  f32,
    consonant_band_y1:   f32,
    consonant_band_y2:   f32,
    nasal_mix:           f32,
    nasal_low:           f32,
    formant_a_y1:        f32,
    formant_a_y2:        f32,
    formant_b_y1:        f32,
    formant_b_y2:        f32,
    formant_c_y1:        f32,
    formant_c_y2:        f32,
    pulse_mix:           f32,
    previous_pulse_mix:  f32,
    target_pulse_mix:    f32,
    vibrato_depth:       f32,
    vibrato_rate:        f32,
    vibrato_phase:       f32,
    pitch_noise_state:   u32,
    pitch_wander:        f32,
    coarticulation:      f32,
    has_vcv_lead:        bool,
}

// The longest CV unit is 98 ms. Five slots preserve its full release at the
// lab's maximum 50-unit/second cadence (20 ms between triggers) without voice
// stealing; normal 32 ms dialogue therefore has comfortable headroom too.
DIALOGUE_VOICE_COUNT :: 5

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

DIALOGUE_VOICE_CANONICAL_TOKEN_PREFIX :: u32(0xd1000000)

dialogue_voice_canonical_glyph :: proc(grapheme: string) -> (u8, bool) {
    if len(grapheme) == 1 {
        glyph := grapheme[0]
        if glyph >= 'A' && glyph <= 'Z' do glyph += 'a' - 'A'
        return glyph, true
    }
    if len(grapheme) == 2 {
        first, second := grapheme[0], grapheme[1]
        if first >= 'A' && first <= 'Z' do first += 'a' - 'A'
        if second >= 'A' && second <= 'Z' do second += 'a' - 'A'
        if first == second &&
           first >= 'a' &&
           first <= 'z' &&
           first != 'a' &&
           first != 'e' &&
           first != 'i' &&
           first != 'o' &&
           first != 'u' &&
           first != 'y' {
            return first, true
        }
    }
    switch grapheme {
    case "á", "à", "â", "ä", "ã", "å", "ā", "ă", "ą", "Á", "À", "Â", "Ä", "Ã", "Å", "Ā", "Ă", "Ą":
        return 'a', true
    case "é", "è", "ê", "ë", "ē", "ė", "ę", "É", "È", "Ê", "Ë", "Ē", "Ė", "Ę":
        return 'e', true
    case "í", "ì", "î", "ï", "ī", "į", "Í", "Ì", "Î", "Ï", "Ī", "Į":
        return 'i', true
    case "ó", "ò", "ô", "ö", "õ", "ø", "ō", "Ó", "Ò", "Ô", "Ö", "Õ", "Ø", "Ō":
        return 'o', true
    case "ú", "ù", "û", "ü", "ū", "Ú", "Ù", "Û", "Ü", "Ū":
        return 'u', true
    case "č", "ć", "Č", "Ć":
        return 'c', true
    case "š", "Š":
        return 's', true
    case "ž", "Ž":
        return 'z', true
    case "đ", "Đ":
        return 'd', true
    case "lj", "Lj", "LJ":
        return 'l', true
    case "nj", "Nj", "NJ":
        return 'n', true
    case "dž", "Dž", "DŽ":
        return 'j', true
    case "sh", "Sh", "SH":
        return 's', true
    case "ch", "Ch", "CH":
        return 'c', true
    case "th", "Th", "TH", "ph", "Ph", "PH":
        return 'f', true
    case "wh", "Wh", "WH":
        return 'w', true
    case "ng", "Ng", "NG":
        return 'n', true
    case "ck", "Ck", "CK", "qu", "Qu", "QU":
        return 'k', true
    }
    return 0, false
}

dialogue_voice_token :: proc(grapheme: string) -> u32 {
    if len(grapheme) == 1 do return u32(grapheme[0])
    hash := u32(2_166_136_261)
    for byte in grapheme {
        hash = (hash ~ u32(byte)) * 16_777_619
    }
    if canonical, known := dialogue_voice_canonical_glyph(grapheme); known {
        return DIALOGUE_VOICE_CANONICAL_TOKEN_PREFIX | (hash & 0x00ffff00) | u32(canonical)
    }
    return hash
}

dialogue_voice_token_is_case_variants :: proc(token: u32, lowercase, titlecase, uppercase: string) -> bool {
    return(
        token == dialogue_voice_token(lowercase) ||
        token == dialogue_voice_token(titlecase) ||
        token == dialogue_voice_token(uppercase) \
    )
}

dialogue_voice_unit_token :: proc(grapheme, next_grapheme: string) -> u32 {
    articulation := dialogue_voice_articulation(grapheme)
    if (articulation != .Consonant && articulation != .Vowel) || dialogue_voice_articulation(next_grapheme) != .Vowel {
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
    glyph, known := dialogue_voice_canonical_glyph(grapheme)
    if known && (glyph == 'a' || glyph == 'e' || glyph == 'i' || glyph == 'o' || glyph == 'u' || glyph == 'y') {
        return .Vowel
    }
    first_rune, width := utf8.decode_rune_in_string(grapheme)
    if width == 0 || !unicode.is_letter(first_rune) do return .Neutral
    return .Consonant
}

dialogue_voice_ascii_lower :: proc(byte: u8) -> u8 {
    return byte >= 'A' && byte <= 'Z' ? byte + ('a' - 'A') : byte
}

dialogue_voice_ascii_vowel :: proc(byte: u8) -> bool {
    glyph := dialogue_voice_ascii_lower(byte)
    return glyph == 'a' || glyph == 'e' || glyph == 'i' || glyph == 'o' || glyph == 'u'
}

dialogue_voice_is_silent_terminal_e :: proc(text: string, start, end: int) -> bool {
    if start < 0 || end != start + 1 || end > len(text) do return false
    if text[start] != 'e' && text[start] != 'E' do return false
    if end < len(text) {
        next_rune, width := utf8.decode_rune_in_string(text[end:])
        if width > 0 && unicode.is_letter(next_rune) do return false
    }
    word_start := start
    for word_start > 0 {
        byte := text[word_start - 1]
        if !((byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z')) do break
        word_start -= 1
    }
    if start - word_start < 3 do return false
    previous := dialogue_voice_ascii_lower(text[start - 1])
    before_previous := dialogue_voice_ascii_lower(text[start - 2])
    // Cover productive CVCe spellings ("make", "home", "cute") and the
    // common consonant-le ending ("little") while leaving short words such
    // as "me", "he", and "she" audible.
    return(
        (!dialogue_voice_ascii_vowel(previous) && dialogue_voice_ascii_vowel(before_previous)) ||
        (previous == 'l' && !dialogue_voice_ascii_vowel(before_previous)) \
    )
}

dialogue_voice_merge_graphemes :: proc(first, second: string) -> bool {
    if len(first) == 1 &&
       len(second) == 1 &&
       dialogue_voice_articulation(first) == .Consonant &&
       dialogue_voice_ascii_lower(first[0]) == dialogue_voice_ascii_lower(second[0]) {
        return true
    }
    return(
        ((first == "l" || first == "L") && (second == "j" || second == "J")) ||
        ((first == "n" || first == "N") && (second == "j" || second == "J")) ||
        ((first == "d" || first == "D") && (second == "ž" || second == "Ž")) ||
        ((first == "s" || first == "S") && (second == "h" || second == "H")) ||
        ((first == "c" || first == "C") && (second == "h" || second == "H")) ||
        ((first == "t" || first == "T") && (second == "h" || second == "H")) ||
        ((first == "p" || first == "P") && (second == "h" || second == "H")) ||
        ((first == "w" || first == "W") && (second == "h" || second == "H")) ||
        ((first == "n" || first == "N") && (second == "g" || second == "G")) ||
        ((first == "c" || first == "C") && (second == "k" || second == "K")) ||
        ((first == "q" || first == "Q") && (second == "u" || second == "U")) \
    )
}

dialogue_voice_token_glyph :: proc(token: u32) -> u8 {
    if token <= 127 do return u8(token)
    if token & 0xff000000 == DIALOGUE_VOICE_CANONICAL_TOKEN_PREFIX do return u8(token & 255)
    return 0
}

dialogue_voice_shape :: proc(token: u32, hash: u32) -> (formant_a, formant_b, onset, pulse, duration, glide: f32) {
    glyph := dialogue_voice_token_glyph(token)
    if glyph >= 'A' && glyph <= 'Z' do glyph += 'a' - 'A'
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

dialogue_voice_consonant_excitation :: proc(token: u32, hash: u32) -> (color, decay, voiced: f32) {
    if dialogue_voice_token_is_case_variants(token, "sh", "Sh", "SH") do return .90, 32, .02
    if dialogue_voice_token_is_case_variants(token, "th", "Th", "TH") do return .78, 38, .025
    if dialogue_voice_token_is_case_variants(token, "ph", "Ph", "PH") do return .94, 34, .02
    if dialogue_voice_token_is_case_variants(token, "ch", "Ch", "CH") do return .86, 105, .015
    if dialogue_voice_token_is_case_variants(token, "wh", "Wh", "WH") do return .28, 50, .32
    if dialogue_voice_token_is_case_variants(token, "ng", "Ng", "NG") do return .14, 46, .42
    glyph := dialogue_voice_token_glyph(token)
    if glyph >= 'A' && glyph <= 'Z' do glyph += 'a' - 'A'
    switch glyph {
    case 'm', 'n', 'l', 'r', 'w':
        return .16, 48, .38
    case 'b', 'd', 'g', 'j', 'v', 'z':
        return .48, 82, .24
    case 'f', 'h', 's', 'x':
        return .96, 34, .025
    case 'c', 'k', 'p', 'q', 't':
        return .84, 158, .015
    }
    return .30 + f32((hash >> 10) & 7) / 7 * .55,
        55 + f32((hash >> 15) & 7) / 7 * 75,
        .06 + f32((hash >> 19) & 3) / 3 * .20
}

dialogue_voice_consonant_band :: proc(token: u32) -> (center_hz, bandwidth, mix: f32) {
    if dialogue_voice_token_is_case_variants(token, "sh", "Sh", "SH") do return 3800, 1800, .76
    if dialogue_voice_token_is_case_variants(token, "th", "Th", "TH") do return 5200, 2400, .62
    if dialogue_voice_token_is_case_variants(token, "ph", "Ph", "PH") do return 3600, 1800, .52
    if dialogue_voice_token_is_case_variants(token, "ch", "Ch", "CH") do return 4500, 1800, .74
    if dialogue_voice_token_is_case_variants(token, "wh", "Wh", "WH") do return 1200, 1000, .25
    if dialogue_voice_token_is_case_variants(token, "ng", "Ng", "NG") do return 1100, 700, .20
    glyph := dialogue_voice_token_glyph(token)
    if glyph >= 'A' && glyph <= 'Z' do glyph += 'a' - 'A'
    // Coarse places of articulation are enough for stylized dialogue, but
    // keep stops and fricatives from collapsing into one generic noise burst.
    switch glyph {
    case 'm', 'n', 'l', 'r', 'w':
        return 900, 650, .18
    case 'p', 'b':
        return 1600, 900, .45
    case 'k', 'g', 'q':
        return 2800, 1000, .58
    case 'f', 'v', 'h':
        return 3600, 1800, .52
    case 't', 'd':
        return 4300, 1200, .68
    case 'c', 'j':
        return 5000, 1400, .70
    case 's', 'z', 'x':
        return 6500, 1600, .78
    }
    return 3000, 1500, .40
}

dialogue_voice_consonant_timing :: proc(token: u32) -> (delay, attack: f32) {
    if dialogue_voice_token_is_case_variants(token, "ch", "Ch", "CH") do return .0015, .0025
    glyph := dialogue_voice_token_glyph(token)
    if glyph >= 'A' && glyph <= 'Z' do glyph += 'a' - 'A'
    switch glyph {
    case 'p', 'b':
        return .0028, .0018
    case 't', 'd':
        return .0018, .0014
    case 'c', 'j':
        return .0015, .0025
    case 'k', 'g', 'q':
        return .0022, .0017
    }
    return 0, .0032
}

dialogue_voice_nasal_mix :: proc(token: u32) -> f32 {
    if dialogue_voice_token_is_case_variants(token, "ng", "Ng", "NG") do return .88
    glyph := dialogue_voice_token_glyph(token)
    if glyph >= 'A' && glyph <= 'Z' do glyph += 'a' - 'A'
    switch glyph {
    case 'm', 'n':
        return .76
    case 'l', 'r', 'w':
        return .16
    }
    return 0
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

dialogue_voice_apply_consonant_source :: proc(voice: ^Dialogue_Voice, token: u32) {
    if voice == nil do return
    hash := token * 747796405 + 2891336453
    formant_a, formant_b, onset, pulse, duration, glide := dialogue_voice_shape(token, hash)
    color, decay, voiced := dialogue_voice_consonant_excitation(token, hash)
    voice.formant_ratio_a = formant_a
    voice.formant_ratio_b = formant_b
    voice.previous_formant_a = formant_a
    voice.previous_formant_b = formant_b
    voice.target_formant_a = formant_a
    voice.target_formant_b = formant_b
    voice.onset_mix = min(onset * 1.48, f32(.58))
    voice.pulse_mix = pulse
    voice.previous_pulse_mix = pulse
    voice.target_pulse_mix = pulse
    voice.duration = max(duration - .009, f32(.038))
    voice.pitch_glide = glide
    voice.consonant_color = color
    voice.consonant_decay = decay
    voice.consonant_voiced = voiced
    voice.consonant_delay, voice.consonant_attack = dialogue_voice_consonant_timing(token)
    voice.consonant_band_hz, voice.consonant_bandwidth, voice.consonant_band_mix = dialogue_voice_consonant_band(token)
    voice.nasal_mix = dialogue_voice_nasal_mix(token)
}

dialogue_voice_apply_vowel_source :: proc(voice: ^Dialogue_Voice, token: u32) {
    if voice == nil do return
    hash := token * 747796405 + 2891336453
    formant_a, formant_b, onset, pulse, duration, glide := dialogue_voice_shape(token, hash)
    voice.formant_ratio_a = formant_a
    voice.formant_ratio_b = formant_b
    voice.previous_formant_a = formant_a
    voice.previous_formant_b = formant_b
    voice.target_formant_a = formant_a
    voice.target_formant_b = formant_b
    voice.onset_mix = onset * .42
    voice.pulse_mix = pulse
    voice.previous_pulse_mix = pulse
    voice.target_pulse_mix = pulse
    voice.duration = duration + .008
    voice.pitch_glide = glide * .78
    voice.voicing = 1.06
    voice.target_voicing = 1.06
}

dialogue_voice_apply_performance_seed :: proc(voice: ^Dialogue_Voice, seed: u32) {
    if voice == nil do return
    hash := seed * 747796405 + 2891336453
    voice.vibrato_rate = 6.35 + f32((hash >> 9) & 255) / 255 * 1.55
    voice.vibrato_phase = f32((hash >> 17) & 255) / 255
    voice.pitch_noise_state = hash ~ 0x6d2b79f5
    voice.pitch_wander = 0
}

trigger_dialogue_voice :: proc(
    voice: ^Dialogue_Voice,
    token: u32,
    profile: Dialogue_Voice_Profile,
    articulation: Dialogue_Articulation = .Neutral,
    formant_shift_semitones: f32 = 0,
) {
    if voice == nil do return
    // A tiny deterministic hash gives words melodic motion without attempting
    // to imitate phonemes from any authored language.
    hash := token * 747796405 + 2891336453
    // Each UTAU-style unit owns a stable synthesized source onset. Reused
    // mixer slots must not inherit oscillator phase from an unrelated prior
    // unit, or identical syllables acquire history-dependent attacks.
    voice.phase_a = f32((hash >> 8) & 0xffff) / 65536
    voice.phase_b = 0
    voice.phase_c = 0
    // Range determines how many exact major-pentatonic degrees are
    // available; it never scales a degree into an out-of-tune microinterval.
    pentatonic_steps := [?]f32{-12, -10, -8, -5, -3, 0, 2, 4, 7, 9, 12}
    available_steps: [len(pentatonic_steps)]f32
    available_count := 0
    base_hz := max(profile.base_hz, f32(1))
    semitone_span := clamp(12 * f32(math.log2(f64(1 + max(profile.range_hz, f32(0)) / base_hz))), f32(0), f32(12))
    for step in pentatonic_steps {
        if abs(step) <= semitone_span + .001 {
            available_steps[available_count] = step
            available_count += 1
        }
    }
    if available_count == 0 {
        available_steps[0] = 0
        available_count = 1
    }
    pitch_step := available_steps[int(hash % u32(available_count))]
    musical_ratio := f32(math.pow(2, f64(pitch_step / 12)))
    formant_a, formant_b, onset, pulse, duration, glide := dialogue_voice_shape(token, hash)
    voice.age = 0
    voice.duration = duration
    voice.frequency = max(profile.base_hz * musical_ratio, f32(90))
    formant_shift := clamp(formant_shift_semitones, -7, 7)
    formant_scale := f32(math.pow(2, f64(formant_shift / 12)))
    tract_hz := profile.tract_hz > 0 ? profile.tract_hz : profile.base_hz
    voice.formant_base_hz = max(tract_hz * formant_scale, f32(90))
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
    voice.pitch_start_ratio = 1
    voice.portamento_seconds = 0
    voice.onset_bloom_depth = .004 + voice.brightness * .006
    voice.onset_bloom_seconds = .028
    voice.brightness = clamp(profile.brightness, 0, 1)
    voice.warmth = clamp(profile.warmth, 0, 1)
    voice.gain = clamp(profile.gain, 0, .24)
    voice.formant_c_hz = clamp(
        2700 + (voice.formant_base_hz - 340) * 1.2 + voice.brightness * 720,
        f32(2200),
        f32(4300),
    )
    voice.cadence_gain = 1
    voice.performance_gain = 1
    voice.release_power = 1.38
    voice.noise_state = hash ~ 0xa511e9b3
    voice.breath_fast = 0
    voice.breath_low = 0
    voice.body_low = 0
    voice.consonant_color = 0
    voice.consonant_decay = 92
    voice.consonant_voiced = 0
    voice.consonant_delay = 0
    voice.consonant_attack = .0032
    voice.consonant_band_hz = 0
    voice.consonant_bandwidth = 0
    voice.consonant_band_mix = 0
    voice.consonant_band_y1 = 0
    voice.consonant_band_y2 = 0
    voice.nasal_mix = 0
    voice.nasal_low = 0
    voice.formant_a_y1 = 0
    voice.formant_a_y2 = 0
    voice.formant_b_y1 = 0
    voice.formant_b_y2 = 0
    voice.formant_c_y1 = 0
    voice.formant_c_y2 = 0
    voice.pulse_mix = pulse
    voice.previous_pulse_mix = pulse
    voice.target_pulse_mix = pulse
    voice.vibrato_depth = .006 + voice.brightness * .009
    dialogue_voice_apply_performance_seed(voice, token)
    voice.coarticulation = 0
    voice.has_vcv_lead = false
    switch articulation {
    case .Vowel:
        voice.duration += .008
        voice.onset_mix *= .42
        voice.pitch_glide *= .78
        voice.voicing = 1.06
    case .Consonant:
        color, decay, voiced := dialogue_voice_consonant_excitation(token, hash)
        voice.consonant_color = color
        voice.consonant_decay = decay
        voice.consonant_voiced = voiced
        voice.consonant_delay, voice.consonant_attack = dialogue_voice_consonant_timing(token)
        voice.consonant_band_hz, voice.consonant_bandwidth, voice.consonant_band_mix = dialogue_voice_consonant_band(
            token,
        )
        voice.nasal_mix = dialogue_voice_nasal_mix(token)
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
    word_progress_hint: f32 = -1,
    expression_hint: f32 = 1,
    formant_shift_semitones: f32 = 0,
) {
    if device == nil || device.stream == nil || len(grapheme) == 0 do return
    _ = dialogue_voice_trigger_grapheme_mixer(
        &device.dialogue_voice,
        grapheme,
        profile,
        cadence_hint,
        next_grapheme,
        word_progress_hint,
        expression_hint,
        formant_shift_semitones,
    )
}

dialogue_voice_trigger_grapheme_mixer :: proc(
    mixer: ^Dialogue_Voice_Mixer,
    grapheme: string,
    profile: Dialogue_Voice_Profile,
    cadence_hint: f32 = 0,
    next_grapheme: string = "",
    word_progress_hint: f32 = -1,
    expression_hint: f32 = 1,
    formant_shift_semitones: f32 = 0,
) -> bool {
    if mixer == nil || len(grapheme) == 0 do return false
    articulation := dialogue_voice_articulation(grapheme)
    if articulation == .Neutral do return false
    if mixer.consumed_vowel && articulation == .Vowel {
        mixer.consumed_vowel = false
        return false
    }
    mixer.consumed_vowel = false
    source_token := dialogue_voice_token(grapheme)
    unit_token := dialogue_voice_unit_token(grapheme, next_grapheme)
    voice_index := trigger_dialogue_voice_mixer(
        mixer,
        unit_token,
        profile,
        cadence_hint,
        articulation,
        word_progress_hint,
        expression_hint,
        formant_shift_semitones,
    )
    voice := &mixer.voices[voice_index]
    if unit_token != source_token {
        // The complete CV/VV spelling owns musical identity, but the original
        // grapheme still owns the synthesized source articulation.
        unit_hash := unit_token * 747796405 + 2891336453
        _, _, _, _, _, unit_glide := dialogue_voice_shape(unit_token, unit_hash)
        prosody_glide := voice.pitch_glide - unit_glide
        if articulation == .Consonant {
            dialogue_voice_apply_consonant_source(voice, source_token)
        } else if articulation == .Vowel {
            dialogue_voice_apply_vowel_source(voice, source_token)
        }
        voice.pitch_glide += prosody_glide
    }
    if (articulation == .Consonant || articulation == .Vowel) &&
       dialogue_voice_apply_cv_unit(voice, next_grapheme, mixer.unit_blend) {
        if articulation == .Consonant && mixer.carried_vowel {
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
    word_progress_hint: f32 = -1,
    expression_hint: f32 = 1,
    formant_shift_semitones: f32 = 0,
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
    trigger_dialogue_voice(&mixer.voices[voice_index], token, profile, articulation, formant_shift_semitones)
    voice := &mixer.voices[voice_index]
    dialogue_voice_apply_performance_seed(voice, token ~ (mixer.syllable_index + 1) * 0x9e3779b9)
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
    expression := clamp(expression_hint, 0, 1)
    expression_scale := .32 + expression * .68
    voice.vibrato_depth *= .42 + expression * .58
    voice.onset_bloom_depth *= (.18 + expression * .82) * (articulation == .Consonant ? f32(.62) : f32(1))
    cadence_pitch := (authored_cadence >= 0 ? -authored_cadence * .045 : -authored_cadence * .075) * expression_scale
    if authored_cadence <= -.75 {
        // Questions hold a little breath and resonance under the upward turn.
        voice.cadence_gain = 1 + .04 * expression_scale
        voice.release_power = 1.38 - .22 * expression_scale
        voice.vibrato_depth *= 1 + .10 * expression_scale
    } else if authored_cadence < 0 {
        // Exclamations are a compact bright pop, not merely a smaller
        // question rise.
        voice.cadence_gain = 1 + .10 * expression_scale
        voice.release_power = 1.38 - .34 * expression_scale
        voice.vibrato_depth *= 1 + .16 * expression_scale
    } else if authored_cadence > 0 {
        // Commas breathe; full stops settle more decisively.
        voice.cadence_gain = 1 - authored_cadence * .055 * expression_scale
        voice.release_power = 1.38 + authored_cadence * .24 * expression_scale
    }
    word_pitch := f32(0)
    word_energy := f32(0)
    if word_progress_hint >= 0 {
        word_progress := clamp(word_progress_hint, 0, 1)
        // A compact rise-and-settle shape gives each written word one
        // intentional gesture. This is analogous to a singer's note curve
        // over a CV/VCV chain, rather than assigning every letter a new tune.
        word_arch := f32(math.sin(f64(word_progress * math.PI))) * .034
        word_accent := (1 - word_progress) * .010
        word_release := word_progress * word_progress * .020
        word_pitch = (word_arch + word_accent - word_release) * expression_scale
        word_energy =
            f32(math.sin(f64(word_progress * math.PI))) * .045 +
            (1 - word_progress) * .025 -
            word_progress * word_progress * .030
    }
    phrase_energy :=
        f32(math.sin(f64(phrase_position * math.PI))) * .025 -
        phrase_position * phrase_position * phrase_position * .018
    dynamics_scale := .15 + expression * .85
    voice.performance_gain = clamp(1 + (word_energy + phrase_energy) * dynamics_scale, f32(.92), f32(1.10))
    voice.frequency *= 1 + phrase_arch + cadence + repetition + alternating + cadence_pitch + word_pitch
    voice.pitch_glide += repetition * .35 - cadence * .25 - authored_cadence * .032
    if mixer.previous_frequency > 0 {
        // Preserve speaker identity and melodic movement without letting a
        // hash-selected glyph leap to an unrelated note inside one phrase.
        step := articulation == .Consonant ? f32(.14) : f32(.11)
        if word_progress_hint > 0 {
            // Inside one word, keep token color but pull the notes into the
            // authored word arc. Larger movement remains available across
            // spaces and punctuation.
            step = articulation == .Consonant ? f32(.075) : f32(.060)
        }
        voice.frequency = clamp(
            voice.frequency,
            mixer.previous_frequency * (1 - step),
            mixer.previous_frequency * (1 + step),
        )
        // UTAU-style units should join into one performed pitch curve even
        // though their excitation is synthesized independently. Begin each
        // unit at the preceding target and settle quickly onto its own note.
        // The bound avoids a conspicuous slide after a larger word-level leap.
        voice.pitch_start_ratio = clamp(mixer.previous_frequency / max(voice.frequency, f32(1)), f32(.88), f32(1.13))
        voice.portamento_seconds = articulation == .Consonant ? f32(.018) : f32(.026)
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

dialogue_voice_resonator :: proc(input, frequency, bandwidth: f32, y1, y2: ^f32) -> f32 {
    if y1 == nil || y2 == nil do return 0
    // A normalized two-pole resonator models one vocal-tract cavity. Its
    // center frequency follows the mouth shape, never the musical note.
    safe_frequency := clamp(frequency, 80, f32(SAMPLE_RATE) * .44)
    // Vowel cavities use 115–600 Hz bands; synthesized consonant noise needs
    // much broader 650–1800 Hz regions to avoid narrow, whistle-like attacks.
    safe_bandwidth := clamp(bandwidth, 45, 3600)
    radius := f32(math.exp(f64(-math.PI * safe_bandwidth / f32(SAMPLE_RATE))))
    coefficient := 2 * radius * f32(math.cos(f64(math.TAU * safe_frequency / f32(SAMPLE_RATE))))
    output := input * (1 - radius) + coefficient * y1^ - radius * radius * y2^
    y2^ = y1^
    y1^ = output
    return output
}

dialogue_voice_glottal_source :: proc(phase, pulse_mix, brightness, warmth: f32) -> f32 {
    // A compact, band-limited approximation of a glottal closure pulse.
    // Alternating harmonic polarity makes the closing edge quicker than the
    // opening edge, while the five-harmonic ceiling remains far below Nyquist
    // throughout the supported dialogue pitch range.
    safe_phase := phase - f32(math.floor(f64(phase)))
    angle := safe_phase * math.TAU
    bright := clamp(brightness, 0, 1)
    warm := clamp(warmth, 0, 1)
    upper := (.52 + bright * .48) * (1 - warm * .30)
    fundamental := f32(math.sin(f64(angle)))
    harmonic :=
        fundamental -
        f32(math.sin(f64(angle * 2))) * .34 * upper +
        f32(math.sin(f64(angle * 3))) * .18 * upper +
        -f32(math.sin(f64(angle * 4))) * .10 * upper +
        f32(math.sin(f64(angle * 5))) * .055 * upper
    // Normalize the worst-case sum before interpolating, so timbre controls
    // cannot turn into hidden gain controls.
    harmonic /= 1 + (.34 + .18 + .10 + .055) * upper
    pulse := clamp(pulse_mix, 0, 1)
    return fundamental + (harmonic - fundamental) * pulse
}

dialogue_voice_pitch_loudness_compensation :: proc(source_hz, tract_hz: f32) -> f32 {
    if source_hz <= 0 || tract_hz <= 0 do return 1
    // With a fixed tract, high fundamentals place fewer but stronger
    // harmonics directly in its resonant bands. Counter that source/tract
    // ratio gently so pitch changes do not masquerade as gain changes.
    ratio := clamp(tract_hz / source_hz, f32(.5), f32(2))
    return clamp(f32(math.pow(f64(ratio), .68)), f32(.68), f32(1.40))
}

dialogue_voice_onset_bloom :: proc(age, duration, depth: f32) -> f32 {
    if duration <= 0 || depth <= 0 || age <= 0 || age >= duration do return 0
    position := clamp(age / duration, 0, 1)
    arch := f32(math.sin(f64(position * math.PI)))
    return arch * arch * clamp(depth, 0, f32(.025))
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
        release_power := voice.release_power > 0 ? voice.release_power : f32(1.38)
        release := f32(math.pow(f64(max(1 - progress, f32(0))), f64(release_power)))
        vibrato_fade := clamp((voice.age - .012) / .025, 0, 1)
        pitch_noise := noise(&voice.pitch_noise_state)
        voice.pitch_wander += (pitch_noise - voice.pitch_wander) * .00072
        wander_depth := .0012 + voice.brightness * .0013
        vibrato_rate := voice.vibrato_rate > 0 ? voice.vibrato_rate : f32(7.2)
        vibrato :=
            f32(math.sin(f64((voice.age * vibrato_rate + voice.vibrato_phase) * math.TAU))) *
            voice.vibrato_depth *
            vibrato_fade
        wobble := 1 + vibrato + voice.pitch_wander * wander_depth
        contour := 1 + voice.pitch_glide * (1 - progress * 1.7)
        pitch_connection := f32(1)
        if voice.portamento_seconds > 0 {
            connection := clamp(voice.age / voice.portamento_seconds, 0, 1)
            connection = connection * connection * (3 - 2 * connection)
            start_ratio := voice.pitch_start_ratio > 0 ? voice.pitch_start_ratio : f32(1)
            pitch_connection = start_ratio + (1 - start_ratio) * connection
        }
        onset_bloom := dialogue_voice_onset_bloom(voice.age, voice.onset_bloom_seconds, voice.onset_bloom_depth)
        frequency := voice.frequency * pitch_connection * wobble * contour * (1 + onset_bloom)
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
        formant_base_hz := voice.formant_base_hz > 0 ? voice.formant_base_hz : frequency
        fundamental := f32(math.sin(f64(voice.phase_a * math.TAU)))
        pulse_mix := voice.pulse_mix
        if voice.has_vcv_lead {
            pulse_mix = voice.previous_pulse_mix + (pulse_mix - voice.previous_pulse_mix) * lead
        }
        pulse_mix += (voice.target_pulse_mix - pulse_mix) * transition
        carrier := dialogue_voice_glottal_source(voice.phase_a, pulse_mix, voice.brightness, voice.warmth)
        // Feed one synthesized glottal source through two vocal-tract
        // resonances. Unlike free-running formant oscillators, the cavities
        // only sing when excited by the source, keeping attacks and pitch
        // motion coherent as one small voice.
        formant_a_hz := formant_base_hz * ratio_a
        formant_b_hz := formant_base_hz * ratio_b
        formant_a := dialogue_voice_resonator(
            carrier,
            formant_a_hz,
            115 + voice.warmth * 80,
            &voice.formant_a_y1,
            &voice.formant_a_y2,
        )
        formant_b := dialogue_voice_resonator(
            carrier,
            formant_b_hz,
            180 + voice.warmth * 150,
            &voice.formant_b_y1,
            &voice.formant_b_y2,
        )
        formant_c_hz :=
            voice.formant_c_hz > 0 ? voice.formant_c_hz : clamp(2700 + (formant_base_hz - 340) * 1.2 + voice.brightness * 720, f32(2200), f32(4300))
        formant_c := dialogue_voice_resonator(
            carrier,
            formant_c_hz,
            420 + voice.warmth * 180,
            &voice.formant_c_y1,
            &voice.formant_c_y2,
        )
        tract_mix := .48 + voice.brightness * .30
        tract :=
            formant_a * (.78 - voice.brightness * .10) +
            formant_b * (.26 + voice.brightness * .16) +
            formant_c * (.08 + voice.brightness * .12)
        body := carrier * (1 - tract_mix) + tract * tract_mix
        smoothing := .52 - voice.warmth * .24
        voice.body_low += (body - voice.body_low) * smoothing
        body = body * (1 - voice.warmth * .48) + voice.body_low * voice.warmth * .48
        voice.nasal_low += (carrier - voice.nasal_low) * .08
        nasal_amount := clamp(voice.nasal_mix, 0, 1) * (1 - transition) * .68
        nasal_body := voice.nasal_low * .84 + fundamental * .16
        body += (nasal_body - body) * nasal_amount
        voicing := voice.voicing > 0 ? voice.voicing : f32(1)
        voicing += (voice.target_voicing - voicing) * transition
        breath := noise(&voice.noise_state)
        voice.breath_fast += (breath - voice.breath_fast) * (.19 + voice.brightness * .06)
        voice.breath_low += (breath - voice.breath_low) * (.06 + voice.brightness * .08)
        consonant_age := max(voice.age - voice.consonant_delay, f32(0))
        consonant_attack_seconds := voice.consonant_attack > 0 ? voice.consonant_attack : f32(.0032)
        consonant_attack :=
            voice.age > voice.consonant_delay ? min(consonant_age / consonant_attack_seconds, f32(1)) : f32(0)
        consonant_color := clamp(voice.consonant_color, 0, 1)
        consonant_decay := voice.consonant_decay > 0 ? voice.consonant_decay : f32(92)
        consonant_noise :=
            (voice.breath_fast - voice.breath_low) * consonant_color + voice.breath_low * (1 - consonant_color) * .46
        if voice.consonant_band_hz > 0 && voice.consonant_band_mix > 0 {
            band_noise := dialogue_voice_resonator(
                breath,
                voice.consonant_band_hz,
                voice.consonant_bandwidth,
                &voice.consonant_band_y1,
                &voice.consonant_band_y2,
            )
            band_mix := clamp(voice.consonant_band_mix, 0, 1)
            consonant_noise += (band_noise * 1.2 - consonant_noise) * band_mix
        }
        consonant :=
            consonant_noise * voice.onset_mix * consonant_attack * f32(math.exp(f64(-consonant_age * consonant_decay)))
        consonant +=
            carrier *
            voice.onset_mix *
            voice.consonant_voiced *
            consonant_attack *
            f32(math.exp(f64(-consonant_age * consonant_decay * .42)))
        // A warm profile has a rounder envelope and less upper-partial energy.
        warmth_gain := .78 + voice.warmth * .22
        // Sparse high-pitched harmonics excite less energy in fixed vocal
        // tract bands than dense low-pitched harmonics. Compensate at the
        // source so character presets retain comparable loudness without
        // hand-authored gain corrections for each pitch.
        excitation_compensation := clamp(formant_base_hz * formant_base_hz / (360 * 360), f32(.45), f32(2.2))
        pitch_loudness_compensation := dialogue_voice_pitch_loudness_compensation(voice.frequency, formant_base_hz)
        cadence_gain := voice.cadence_gain > 0 ? voice.cadence_gain : f32(1)
        performance_gain := voice.performance_gain > 0 ? voice.performance_gain : f32(1)
        sample +=
            (body * voicing * attack * warmth_gain * excitation_compensation * pitch_loudness_compensation +
                consonant) *
            release *
            voice.gain *
            cadence_gain *
            performance_gain
        voice.age += seconds_per_sample
    }
}

dialogue_voice_soft_limit :: proc(sample: f32) -> f32 {
    threshold := f32(.32)
    ceiling := f32(.62)
    magnitude := abs(sample)
    if magnitude <= threshold do return sample
    span := ceiling - threshold
    rounded := threshold + span * (1 - f32(math.exp(f64(-(magnitude - threshold) / span))))
    return sample < 0 ? -rounded : rounded
}

render_dialogue_voice_mixer_add :: proc(mixer: ^Dialogue_Voice_Mixer, samples: []f32) {
    if mixer == nil do return
    scratch: [1024]f32
    offset := 0
    for offset < len(samples) {
        count := min(len(samples) - offset, len(scratch))
        for &sample in scratch[:count] do sample = 0
        for &voice in mixer.voices {
            render_dialogue_voice_add(&voice, scratch[:count])
        }
        for index in 0 ..< count {
            samples[offset + index] += dialogue_voice_soft_limit(scratch[index])
        }
        offset += count
    }
}
