package main

import engine_sound "../packages/engine_sound"
import "core:fmt"
import "core:os"
import "core:strconv"

DIALOGUE_PREVIEW_DEFAULT_TEXT :: "Hello, little harbor! Are you ready for an adventure?"

dialogue_voice_preview_profile :: proc(name: string) -> (engine_sound.Dialogue_Voice_Profile, bool) {
    switch name {
    case "sprout":
        return dialogue_sound_lab_presets[0], true
    case "storybook":
        return dialogue_sound_lab_presets[1], true
    case "chirpy":
        return dialogue_sound_lab_presets[2], true
    case "cozy":
        return dialogue_sound_lab_presets[3], true
    }
    return {}, false
}

dialogue_voice_preview_append_rendered :: proc(
    output: ^[dynamic]f32,
    mixer: ^engine_sound.Dialogue_Voice_Mixer,
    sample_count: int,
) {
    if output == nil || mixer == nil || sample_count <= 0 do return
    scratch: [1024]f32
    remaining := sample_count
    for remaining > 0 {
        count := min(remaining, len(scratch))
        for &sample in scratch[:count] do sample = 0
        engine_sound.render_dialogue_voice_mixer_add(mixer, scratch[:count])
        append(output, ..scratch[:count])
        remaining -= count
    }
}

dialogue_voice_preview_render :: proc(
    text: string,
    profile: engine_sound.Dialogue_Voice_Profile,
    unit_blend: f32 = .82,
    expression: f32 = 1,
    formant_shift_semitones: f32 = 0,
    allocator := context.allocator,
) -> [dynamic]f32 {
    reveal_seconds := DIALOGUE_REVEAL_SECONDS
    samples_per_glyph := int(reveal_seconds * f32(engine_sound.SAMPLE_RATE))
    estimated := max(len(text) * samples_per_glyph, 4096)
    output := make([dynamic]f32, 0, estimated, allocator)
    mixer := engine_sound.Dialogue_Voice_Mixer {
        unit_blend = clamp(unit_blend, 0, 1),
    }
    cursor := 0
    for cursor < len(text) {
        start := cursor
        cursor = dialogue_voice_unit_end(text, start)
        unit := text[start:cursor]
        if dialogue_voice_should_synthesize_at(text, start, cursor) {
            next_grapheme := dialogue_voice_next_synthesized_grapheme(text, cursor)
            _ = engine_sound.dialogue_voice_trigger_grapheme_mixer(
                &mixer,
                text[start:cursor],
                profile,
                dialogue_voice_cadence_hint(text, start, cursor),
                next_grapheme,
                dialogue_voice_word_progress(text, start, cursor),
                expression,
                formant_shift_semitones,
            )
        } else if unit == " " || unit == "\t" {
            engine_sound.dialogue_voice_mixer_word_boundary(&mixer)
        } else if dialogue_voice_is_phrase_boundary(unit) {
            engine_sound.dialogue_voice_mixer_phrase_boundary(&mixer)
        }
        seconds := DIALOGUE_REVEAL_SECONDS + dialogue_reveal_pause(unit)
        dialogue_voice_preview_append_rendered(&output, &mixer, max(int(seconds * engine_sound.SAMPLE_RATE), 1))
    }
    dialogue_voice_preview_append_rendered(&output, &mixer, int(.24 * engine_sound.SAMPLE_RATE))
    return output
}

dialogue_wav_u16 :: proc(bytes: []u8, offset: int, value: u16) {
    bytes[offset + 0] = u8(value)
    bytes[offset + 1] = u8(value >> 8)
}

dialogue_wav_u32 :: proc(bytes: []u8, offset: int, value: u32) {
    bytes[offset + 0] = u8(value)
    bytes[offset + 1] = u8(value >> 8)
    bytes[offset + 2] = u8(value >> 16)
    bytes[offset + 3] = u8(value >> 24)
}

dialogue_voice_preview_write_wav :: proc(path: string, samples: []f32) -> bool {
    if path == "" || len(samples) == 0 do return false
    data_bytes := len(samples) * 2
    output := make([]u8, 44 + data_bytes, context.temp_allocator)
    copy(output[0:4], "RIFF")
    dialogue_wav_u32(output, 4, u32(36 + data_bytes))
    copy(output[8:12], "WAVE")
    copy(output[12:16], "fmt ")
    dialogue_wav_u32(output, 16, 16)
    dialogue_wav_u16(output, 20, 1)
    dialogue_wav_u16(output, 22, 1)
    dialogue_wav_u32(output, 24, engine_sound.SAMPLE_RATE)
    dialogue_wav_u32(output, 28, engine_sound.SAMPLE_RATE * 2)
    dialogue_wav_u16(output, 32, 2)
    dialogue_wav_u16(output, 34, 16)
    copy(output[36:40], "data")
    dialogue_wav_u32(output, 40, u32(data_bytes))
    for sample, index in samples {
        value := i16(clamp(sample, -1, 1) * 32767)
        dialogue_wav_u16(output, 44 + index * 2, cast(u16)value)
    }
    file, create_error := os.create(path)
    if create_error != nil {
        fmt.eprintf("dialogue preview: cannot create %s: %v\n", path, create_error)
        return false
    }
    defer os.close(file)
    written, write_error := os.write(file, output)
    if write_error != nil || written != len(output) {
        fmt.eprintf("dialogue preview: cannot write %s: %v\n", path, write_error)
        return false
    }
    return true
}

dialogue_voice_preview_cli :: proc(args: []string) -> bool {
    if len(args) < 3 {
        fmt.eprintln(
            "usage: adriatic dialogue-preview <output.wav> [sprout|storybook|chirpy|cozy] [text] [formant-shift] [base-pitch] [expression]",
        )
        return false
    }
    preset := len(args) >= 4 ? args[3] : "storybook"
    profile, known := dialogue_voice_preview_profile(preset)
    if !known {
        fmt.eprintf("dialogue preview: unknown preset %s\n", preset)
        return false
    }
    text := len(args) >= 5 ? args[4] : DIALOGUE_PREVIEW_DEFAULT_TEXT
    formant_shift := f32(0)
    if len(args) >= 6 {
        parsed, ok := strconv.parse_f32(args[5])
        if !ok || parsed < -7 || parsed > 7 {
            fmt.eprintf("dialogue preview: formant shift must be between -7 and +7 semitones\n")
            return false
        }
        formant_shift = parsed
    }
    if len(args) >= 7 {
        parsed, ok := strconv.parse_f32(args[6])
        if !ok || parsed < 90 || parsed > 700 {
            fmt.eprintf("dialogue preview: base pitch must be between 90 and 700 Hz\n")
            return false
        }
        profile.base_hz = parsed
    }
    expression := f32(1)
    if len(args) >= 8 {
        parsed, ok := strconv.parse_f32(args[7])
        if !ok || parsed < 0 || parsed > 1 {
            fmt.eprintf("dialogue preview: expression must be between 0 and 1\n")
            return false
        }
        expression = parsed
    }
    output, resolved := adriatic_cli_absolute_path(args[2])
    if !resolved do return false
    if err := os.make_directory_all(os.dir(output)); err != nil && err != .Exist {
        fmt.eprintf("dialogue preview: cannot create output directory: %v\n", err)
        return false
    }
    samples := dialogue_voice_preview_render(
        text,
        profile,
        expression = expression,
        formant_shift_semitones = formant_shift,
    )
    defer delete(samples)
    if !dialogue_voice_preview_write_wav(output, samples[:]) do return false
    seconds := f32(len(samples)) / engine_sound.SAMPLE_RATE
    fmt.printf("dialogue preview: %s preset, %.2f seconds -> %s\n", preset, seconds, output)
    return true
}
