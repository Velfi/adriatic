package main

import dialogue "../packages/dialogue"
import dialogue_glossary "../packages/dialogue_glossary"
import engine_sound "../packages/engine_sound"
import story "../packages/story"
import "core:fmt"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

DIALOGUE_REFERENCE_HEIGHT :: f32(720)
DIALOGUE_REVEAL_SECONDS :: f32(.032)
DIALOGUE_CHOICE_VISIBLE_MAX :: 4
DIALOGUE_PANEL_TRANSITION_SECONDS :: f32(.18)
DIALOGUE_CHOICE_TRANSITION_SECONDS :: f32(.16)
DIALOGUE_FOCUS_TRANSITION_SECONDS :: f32(.14)

@(no_instrumentation)
dialogue_font :: #force_inline proc() -> canvas2d.Font {
    return canvas2d.DisplayFont()
}

Dialogue_View_State :: struct {
    revision:         u64,
    revealed_bytes:   int,
    reveal_timer:     f32,
    first_choice:     int,
    reaction_seconds: f32,
    previous_focus:   int,
    panel_seconds:    f32,
    choice_seconds:   f32,
}

Dialogue_Presentation_State :: enum {
    Speaking,
    Choosing,
    Continuing,
}

dialogue_ease_out :: #force_inline proc(value: f32) -> f32 {
    t := clamp(value, 0, 1)
    return 1 - (1 - t) * (1 - t) * (1 - t)
}

dialogue_color_alpha :: #force_inline proc(color: canvas2d.Color, opacity: f32) -> canvas2d.Color {
    result := color
    result.a = u8(clamp(f32(result.a) * clamp(opacity, 0, 1), 0, 255))
    return result
}

dialogue_color_lerp :: #force_inline proc(a, b: canvas2d.Color, t: f32) -> canvas2d.Color {
    amount := clamp(t, 0, 1)
    return {
        u8(f32(a.r) + (f32(b.r) - f32(a.r)) * amount),
        u8(f32(a.g) + (f32(b.g) - f32(a.g)) * amount),
        u8(f32(a.b) + (f32(b.b) - f32(a.b)) * amount),
        u8(f32(a.a) + (f32(b.a) - f32(a.a)) * amount),
    }
}

Dialogue_Tv_Layout :: struct {
    scale:        f32,
    player_card:  canvas2d.Rectangle,
    conversation: canvas2d.Rectangle,
    npc_card:     canvas2d.Rectangle,
    speech:       canvas2d.Rectangle,
    choices:      canvas2d.Rectangle,
    choice_row_h: f32,
    choice_gap:   f32,
}

dialogue_tv_layout :: proc(width, height: i32, choice_count: int = DIALOGUE_CHOICE_VISIBLE_MAX) -> Dialogue_Tv_Layout {
    scale := max(f32(height) / DIALOGUE_REFERENCE_HEIGHT, f32(1))
    safe_x := max(f32(width) * .05, 24 * scale)
    safe_y := max(f32(height) * .05, 24 * scale)
    available := max(f32(width) - safe_x * 2, 720 * scale)
    gap := 20 * scale
    // Keep the speakers at the edges of the world composition while the
    // conversation becomes a compact, cinematic lower-third.
    center_target := min(760 * scale, available - 320 * scale - gap * 2)
    card_w := min(220 * scale, max((available - center_target - gap * 2) * .5, 112 * scale))
    center_w := min(center_target, available - card_w * 2 - gap * 2)
    center_w = max(center_w, 560 * scale)
    total_w := card_w * 2 + center_w + gap * 2
    start_x := (f32(width) - total_w) * .5
    height_safe := max(f32(height) - safe_y * 2, 620 * scale)
    visible_choices := clamp(choice_count, 0, DIALOGUE_CHOICE_VISIBLE_MAX)
    choice_row_h := 62 * scale
    choice_gap := 8 * scale
    speech_h := 154 * scale
    choice_area_h := f32(visible_choices) * choice_row_h + f32(max(visible_choices - 1, 0)) * choice_gap
    center_h := min(58 * scale + speech_h + 12 * scale + choice_area_h + 26 * scale, height_safe)
    center := canvas2d.Rectangle {
        start_x + card_w + gap,
        f32(height) - safe_y - center_h,
        center_w,
        center_h,
    }
    return {
        scale = scale,
        player_card = {start_x, safe_y, card_w, height_safe},
        conversation = center,
        npc_card = {center.x + center.width + gap, safe_y, card_w, height_safe},
        speech = {center.x + 30 * scale, center.y + 58 * scale, center.width - 60 * scale, speech_h},
        choices = {
            center.x + 26 * scale,
            center.y + 58 * scale + speech_h + 12 * scale,
            center.width - 52 * scale,
            center.height - 58 * scale - speech_h - 26 * scale,
        },
        choice_row_h = choice_row_h,
        choice_gap = choice_gap,
    }
}

dialogue_next_glyph_end :: proc(text: string, start: int) -> int {
    if start >= len(text) do return len(text)
    return min(start + canvas2d.TextNextGrapheme(text[start:]), len(text))
}

dialogue_voice_unit_end :: proc(text: string, start: int) -> int {
    first_end := dialogue_next_glyph_end(text, start)
    if first_end >= len(text) do return first_end
    second_end := dialogue_next_glyph_end(text, first_end)
    if engine_sound.dialogue_voice_merge_graphemes(text[start:first_end], text[first_end:second_end]) {
        return second_end
    }
    return first_end
}

dialogue_voice_should_synthesize :: proc(grapheme: string) -> bool {
    articulation := engine_sound.dialogue_voice_articulation(grapheme)
    return articulation == .Vowel || articulation == .Consonant
}

dialogue_voice_should_synthesize_at :: proc(text: string, start, end: int) -> bool {
    if start < 0 || end <= start || end > len(text) do return false
    if engine_sound.dialogue_voice_is_silent_terminal_e(text, start, end) do return false
    return dialogue_voice_should_synthesize(text[start:end])
}

dialogue_voice_next_synthesized_grapheme :: proc(text: string, cursor: int) -> string {
    if cursor < 0 || cursor >= len(text) do return ""
    unit_end := dialogue_voice_unit_end(text, cursor)
    if !dialogue_voice_should_synthesize_at(text, cursor, unit_end) do return ""
    return text[cursor:unit_end]
}

dialogue_voice_is_phrase_boundary :: proc(grapheme: string) -> bool {
    return(
        grapheme == "." ||
        grapheme == "!" ||
        grapheme == "?" ||
        grapheme == "…" ||
        grapheme == "\n" ||
        grapheme == "—" ||
        grapheme == "–" \
    )
}

dialogue_reveal_pause :: proc(grapheme: string) -> f32 {
    switch grapheme {
    case ".", "!", "?":
        return .18
    case "…":
        return .28
    case "—", "–":
        return .12
    case ",", ";", ":":
        return .09
    case " ", "\t":
        return .012
    case "\n":
        return .12
    }
    return 0
}

dialogue_voice_cadence_hint :: proc(text: string, start, end: int) -> f32 {
    if start < 0 || end <= start || end > len(text) do return 0
    cursor := end
    current := text[start:end]
    if engine_sound.dialogue_voice_articulation(current) == .Consonant && cursor < len(text) {
        next_end := dialogue_voice_unit_end(text, cursor)
        if dialogue_voice_should_synthesize_at(text, cursor, next_end) &&
           engine_sound.dialogue_voice_articulation(text[cursor:next_end]) == .Vowel {
            cursor = next_end
        } else if engine_sound.dialogue_voice_is_silent_terminal_e(text, cursor, next_end) {
            cursor = next_end
        }
    }
    if cursor >= len(text) do return 0
    punctuation_end := dialogue_next_glyph_end(text, cursor)
    punctuation := text[cursor:punctuation_end]
    for punctuation == "\"" ||
        punctuation == "'" ||
        punctuation == "”" ||
        punctuation == "’" ||
        punctuation == "»" {
        cursor = punctuation_end
        if cursor >= len(text) do return 0
        punctuation_end = dialogue_next_glyph_end(text, cursor)
        punctuation = text[cursor:punctuation_end]
    }
    switch punctuation {
    case ".":
        return 1
    case "?":
        return -1
    case "!":
        return -.35
    case ",", ";", ":":
        return .45
    case "…":
        return .7
    case "—", "–":
        return .3
    }
    return 0
}

dialogue_voice_word_progress :: proc(text: string, start, end: int) -> f32 {
    if start < 0 || end <= start || end > len(text) do return -1
    if !dialogue_voice_should_synthesize_at(text, start, end) do return -1
    word_start := 0
    cursor := 0
    for cursor < start {
        unit_end := dialogue_voice_unit_end(text, cursor)
        if dialogue_voice_should_synthesize_at(text, cursor, unit_end) {
            if cursor == 0 || word_start >= cursor || !dialogue_voice_should_synthesize_at(text, word_start, cursor) {
                word_start = cursor
            }
        } else {
            word_start = unit_end
        }
        cursor = unit_end
    }
    word_end := end
    for word_end < len(text) {
        unit_end := dialogue_voice_unit_end(text, word_end)
        if !dialogue_voice_should_synthesize_at(text, word_end, unit_end) {
            break
        }
        word_end = unit_end
    }
    travel := word_end - word_start - (end - start)
    if travel <= 0 do return 0
    return clamp(f32(start - word_start) / f32(travel), 0, 1)
}

dialogue_voice_profile :: proc(resident: story.Resident) -> engine_sound.Dialogue_Voice_Profile {
    switch resident {
    case .Marta:
        return {390, 170, .72, .34, .105, 390}
    case .Gerta:
        return {310, 120, .48, .72, .11, 310}
    case .Niko:
        return {270, 105, .42, .82, .11, 270}
    case .Iva:
        return {430, 155, .68, .48, .10, 430}
    case .Bojan:
        return {235, 90, .38, .88, .115, 235}
    case .Zora:
        return {335, 210, .62, .68, .105, 335}
    case .Vesna:
        return {365, 145, .58, .52, .10, 365}
    case .Petar:
        return {285, 115, .44, .74, .11, 285}
    case .Anica:
        return {405, 165, .64, .46, .10, 405}
    case .Toma:
        return {295, 125, .50, .70, .105, 295}
    case .Lena:
        return {385, 170, .65, .50, .10, 385}
    case .Mirna:
        return {455, 185, .74, .40, .085, 455}
    }
    return {340, 140, .55, .6, .1, 340}
}

dialogue_current_resident :: proc(editor: ^Editor) -> story.Resident {
    if editor == nil do return .Marta
    current := dialogue.current(&editor.attendant_dialogue)
    if current == nil do return editor.dialogue_resident
    speaker := current.speaker(&editor.attendant_dialogue.ctx)
    if resident, found := story.resident_from_speaker(speaker); found do return resident
    return editor.dialogue_resident
}

dialogue_view_reset :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.attendant_dialogue_view = {
        revision       = editor.attendant_dialogue.revision,
        previous_focus = editor.attendant_dialogue_focus,
    }
    engine_sound.dialogue_voice_stop(&editor.engine_audio)
}

dialogue_view_update :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil || !editor.attendant_dialogue_open do return
    view := &editor.attendant_dialogue_view
    conversation := &editor.attendant_dialogue
    if view.revision != conversation.revision {
        dialogue_view_reset(editor)
        view = &editor.attendant_dialogue_view
    }
    current := dialogue.current(conversation)
    if current == nil do return
    text := current.text(&conversation.ctx)
    view.reaction_seconds = max(view.reaction_seconds - max(delta_seconds, 0), 0)
    view.panel_seconds += max(delta_seconds, 0)
    if view.previous_focus != editor.attendant_dialogue_focus {
        view.previous_focus = editor.attendant_dialogue_focus
        view.reaction_seconds = .22
    }
    view.reveal_timer -= max(delta_seconds, 0)
    for view.revealed_bytes < len(text) && view.reveal_timer <= 0 {
        start := view.revealed_bytes
        view.revealed_bytes = dialogue_voice_unit_end(text, start)
        unit := text[start:view.revealed_bytes]
        view.reveal_timer += DIALOGUE_REVEAL_SECONDS + dialogue_reveal_pause(unit)
        if dialogue_voice_should_synthesize_at(text, start, view.revealed_bytes) {
            cadence_hint := dialogue_voice_cadence_hint(text, start, view.revealed_bytes)
            next_grapheme := dialogue_voice_next_synthesized_grapheme(text, view.revealed_bytes)
            engine_sound.dialogue_voice_trigger_grapheme(
                &editor.engine_audio,
                text[start:view.revealed_bytes],
                dialogue_voice_profile(dialogue_current_resident(editor)),
                cadence_hint,
                next_grapheme,
                dialogue_voice_word_progress(text, start, view.revealed_bytes),
            )
        } else if unit == " " || unit == "\t" {
            engine_sound.dialogue_voice_mixer_word_boundary(&editor.engine_audio.dialogue_voice)
        } else if dialogue_voice_is_phrase_boundary(unit) {
            engine_sound.dialogue_voice_phrase_boundary(&editor.engine_audio)
        }
    }
    if view.revealed_bytes >= len(text) && dialogue.available_count(conversation) > 0 {
        view.choice_seconds += max(delta_seconds, 0)
    } else {
        view.choice_seconds = 0
    }
}

dialogue_presentation_state :: proc(editor: ^Editor) -> Dialogue_Presentation_State {
    if dialogue_view_revealing(editor) do return .Speaking
    if editor != nil && dialogue.available_count(&editor.attendant_dialogue) > 0 do return .Choosing
    return .Continuing
}

dialogue_view_revealing :: proc(editor: ^Editor) -> bool {
    if editor == nil do return false
    current := dialogue.current(&editor.attendant_dialogue)
    if current == nil do return false
    return editor.attendant_dialogue_view.revealed_bytes < len(current.text(&editor.attendant_dialogue.ctx))
}

dialogue_view_complete_reveal :: proc(editor: ^Editor) {
    if editor == nil do return
    current := dialogue.current(&editor.attendant_dialogue)
    if current != nil {
        editor.attendant_dialogue_view.revealed_bytes = len(current.text(&editor.attendant_dialogue.ctx))
    }
    editor.attendant_dialogue_view.reveal_timer = 0
    engine_sound.dialogue_voice_stop(&editor.engine_audio)
}

dialogue_choice_visible_rows :: proc(layout: Dialogue_Tv_Layout) -> int {
    stride := layout.choice_row_h + layout.choice_gap
    return max(min(int((layout.choices.height + layout.choice_gap) / stride), DIALOGUE_CHOICE_VISIBLE_MAX), 0)
}

dialogue_choice_scroll_focus :: proc(editor: ^Editor, visible_rows: int) {
    if editor == nil do return
    if visible_rows <= 0 {
        editor.attendant_dialogue_view.first_choice = 0
        return
    }
    count := dialogue.available_count(&editor.attendant_dialogue)
    max_first := max(count - visible_rows, 0)
    if editor.attendant_dialogue_focus < editor.attendant_dialogue_view.first_choice {
        editor.attendant_dialogue_view.first_choice = editor.attendant_dialogue_focus
    } else if editor.attendant_dialogue_focus >= editor.attendant_dialogue_view.first_choice + visible_rows {
        editor.attendant_dialogue_view.first_choice = editor.attendant_dialogue_focus - visible_rows + 1
    }
    editor.attendant_dialogue_view.first_choice = clamp(editor.attendant_dialogue_view.first_choice, 0, max_first)
}

dialogue_choice_bounds :: proc(layout: Dialogue_Tv_Layout, visible_row: int) -> canvas2d.Rectangle {
    return {
        layout.choices.x,
        layout.choices.y + f32(visible_row) * (layout.choice_row_h + layout.choice_gap),
        layout.choices.width,
        layout.choice_row_h,
    }
}

dialogue_draw_wrapped :: proc(text: string, bounds: canvas2d.Rectangle, size, spacing, line_height: f32, color: canvas2d.Color) {
    if len(text) == 0 do return
    _ = canvas2d.DrawTextWrappedEx(dialogue_font(), fmt.ctprintf("%s", text), bounds, size, spacing, line_height, color)
}

dialogue_word_byte :: proc(byte: u8) -> bool {
    return (byte >= 'A' && byte <= 'Z') || (byte >= 'a' && byte <= 'z') || byte >= 0x80
}

// Draws the same wrapped text as dialogue_draw_wrapped, but keeps word bounds
// so Adriatic vocabulary can act as an unobtrusive language-learning aid.
dialogue_draw_glossed_wrapped :: proc(
    text: string,
    bounds: canvas2d.Rectangle,
    size, spacing, line_height: f32,
    color: canvas2d.Color,
    mouse: canvas2d.Vector2,
    centered: bool = false,
) -> string {
    if len(text) == 0 do return ""
    lines := make([dynamic]canvas2d.Text_Wrapped_Line, 0, 8, context.temp_allocator)
    canvas2d.LayoutTextWrappedEx(dialogue_font(), fmt.ctprintf("%s", text), size, spacing, bounds.width, .Auto, &lines)
    hovered_english := ""
    visible := min(len(lines), max(int(bounds.height / line_height), 0))
    first_line_y := bounds.y
    if centered && visible > 0 {
        first_line_y = canvas2d.TextBlockCenteredY(dialogue_font(), bounds, size, line_height, visible)
    }
    for line, line_index in lines[:visible] {
        x := bounds.x
        y := first_line_y + f32(line_index) * line_height
        cursor := line.start
        for cursor < line.end {
            start := cursor
            is_space := text[cursor] == ' '
            if is_space {
                for cursor < line.end && text[cursor] == ' ' do cursor += 1
            } else {
                for cursor < line.end && text[cursor] != ' ' do cursor += 1
            }
            token := text[start:cursor]
            measured := canvas2d.MeasureTextEx(dialogue_font(), fmt.ctprintf("%s", token), size, spacing)
            if !is_space && x > bounds.x && x + measured.x > bounds.x + bounds.width {
                x = bounds.x
                y += line_height
                if y + line_height > bounds.y + bounds.height do break
            }
            if is_space && x == bounds.x do continue

            canvas2d.DrawTextEx(dialogue_font(), fmt.ctprintf("%s", token), {x, y}, size, spacing, color)
            if !is_space {
                word_start, word_end := 0, len(token)
                for word_start < word_end && !dialogue_word_byte(token[word_start]) do word_start += 1
                for word_end > word_start && !dialogue_word_byte(token[word_end - 1]) do word_end -= 1
                if word_start < word_end {
                    word := token[word_start:word_end]
                    english, glossary_found := dialogue_glossary.english_for(word)
                    if glossary_found {
                        prefix_width: f32
                        if word_start > 0 {
                            prefix := token[:word_start]
                            prefix_width =
                                canvas2d.MeasureTextEx(dialogue_font(), fmt.ctprintf("%s", prefix), size, spacing).x
                        }
                        word_width := canvas2d.MeasureTextEx(dialogue_font(), fmt.ctprintf("%s", word), size, spacing).x
                        word_bounds := canvas2d.Rectangle{x + prefix_width, y, word_width, line_height}
                        hovered := canvas2d.CheckCollisionPointRec(mouse, word_bounds)
                        underline_color := hovered ? ui_theme_focus() : ui_theme_accent(190)
                        canvas2d.DrawRectangle(
                            i32(word_bounds.x),
                            i32(y + size + 2),
                            max(i32(word_bounds.width), 1),
                            max(i32(hovered ? 3 : 2), 1),
                            underline_color,
                        )
                        if hovered do hovered_english = english
                    }
                }
            }
            x += measured.x
        }
    }
    return hovered_english
}

dialogue_draw_glossary_tooltip :: proc(english: string, mouse: canvas2d.Vector2, width, height: i32, scale: f32) {
    if len(english) == 0 do return
    label := fmt.ctprintf("English: %s", english)
    font_size := 20 * scale
    measured := canvas2d.MeasureTextEx(dialogue_font(), label, font_size, .8 * scale)
    panel := canvas2d.Rectangle {
        clamp(mouse.x + 14 * scale, 8 * scale, f32(width) - measured.x - 32 * scale),
        clamp(mouse.y - 48 * scale, 8 * scale, f32(height) - 42 * scale),
        measured.x + 20 * scale,
        34 * scale,
    }
    canvas2d.DrawRectangleRounded(panel, .22, 6, ui_theme_surface_elevated(250))
    canvas2d.DrawRectangleRoundedLinesEx(panel, .22, 6, 1 * scale, ui_theme_focus())
    canvas2d.DrawTextEx(
        dialogue_font(),
        label,
        {panel.x + 10 * scale, panel.y + 7 * scale},
        font_size,
        .8 * scale,
        ui_theme_text(),
    )
}

dialogue_draw_tarot_strip :: proc(editor: ^Editor, bounds: canvas2d.Rectangle, scale: f32) {
    if editor == nil || editor.dialogue_resident != .Zora do return
    current := dialogue.current(&editor.attendant_dialogue)
    if current == nil || current.id != "zora-reading" do return
    layout := &editor.story_state.tarot_layout
    if layout.count == 0 do return
    count := min(layout.count, 5)
    gap := 8 * scale
    card_w := min(64 * scale, (bounds.width - f32(count - 1) * gap) / f32(count))
    card_h := card_w * 158 / 108
    total_w := f32(count) * card_w + f32(count - 1) * gap
    x := bounds.x + (bounds.width - total_w) * .5
    y := bounds.y + bounds.height - card_h
    for placement, index in layout.placements[:count] {
        card := canvas2d.Rectangle{x + f32(index) * (card_w + gap), y, card_w, card_h}
        if editor.tarot_atlas.ready {
            card_id := int(placement.card)
            atlas_row, atlas_column := 0, 0
            if card_id < 14 {
                atlas_column = card_id
            } else if card_id < 22 {
                atlas_row, atlas_column = 1, card_id - 14
            } else {
                minor := card_id - 22
                atlas_row, atlas_column = 2 + minor / 14, minor % 14
            }
            source := canvas2d.Rectangle{f32(atlas_column * 108), f32(atlas_row * 158), 108, 158}
            if placement.orientation == .Reversed {
                source.x += source.width
                source.y += source.height
                source.width = -source.width
                source.height = -source.height
            }
            canvas2d.DrawTexturePro(editor.tarot_atlas, source, card, {255, 255, 255, 255})
        } else {
            canvas2d.DrawRectangleRounded(card, .06, 6, ui_theme_control())
        }
        canvas2d.DrawRectangleRoundedLinesEx(card, .06, 6, 1 * scale, ui_theme_focus())
    }
}

dialogue_portrait_color :: proc(editor: ^Editor, resident: story.Resident, player: bool) -> canvas2d.Color {
    if player do return mouse_fur_color(editor.mouse_fur)
    switch resident {
    case .Marta:
        return {145, 125, 101, 255}
    case .Gerta:
        return {110, 114, 121, 255}
    case .Niko:
        return {130, 91, 63, 255}
    case .Iva:
        return {205, 186, 145, 255}
    case .Bojan:
        return {82, 78, 75, 255}
    case .Zora:
        return {158, 145, 151, 255}
    case .Vesna:
        return {224, 219, 202, 255}
    case .Petar:
        return {169, 128, 91, 255}
    case .Anica:
        return {181, 169, 146, 255}
    case .Toma:
        return {138, 101, 72, 255}
    case .Lena:
        return {210, 194, 154, 255}
    case .Mirna:
        return {104, 96, 91, 255}
    }
    return {145, 125, 101, 255}
}

dialogue_draw_live_portrait :: proc(
    editor: ^Editor,
    bounds: canvas2d.Rectangle,
    resident: story.Resident,
    player, active: bool,
    reaction: f32,
) {
    scale := min(bounds.width / 240, bounds.height / 620)
    // The true mesh is rendered in the world pass beneath this chrome. Keep
    // the portrait interior untouched so its lighting and colors remain true.
    border := active ? ui_theme_focus() : ui_theme_border()
    canvas2d.DrawRectangleRoundedLinesEx(bounds, .06, 10, active ? 3 * scale : 1 * scale, border)
    _ = reaction
    name := player ? "YOU" : story.resident_name(resident)
    name_size := 24 * scale
    measured := canvas2d.MeasureTextEx(dialogue_font(), fmt.ctprintf("%s", name), name_size, 1 * scale)
    nameplate := canvas2d.Rectangle {
        bounds.x + (bounds.width - measured.x) * .5 - 12 * scale,
        bounds.y + bounds.height - 72 * scale,
        measured.x + 24 * scale,
        42 * scale,
    }
    canvas2d.DrawRectangleRounded(nameplate, .35, 8, ui_theme_surface_elevated(232))
    canvas2d.DrawRectangleRoundedLinesEx(nameplate, .35, 8, 1 * scale, border)
    canvas2d.DrawTextEx(
        dialogue_font(),
        fmt.ctprintf("%s", name),
        {bounds.x + (bounds.width - measured.x) * .5, bounds.y + bounds.height - 62 * scale},
        name_size,
        1 * scale,
        active ? ui_theme_accent() : ui_theme_text_muted(),
    )
}

dialogue_tv_draw :: proc(editor: ^Editor, width, height: i32) {
    if editor == nil do return
    conversation := &editor.attendant_dialogue
    current := dialogue.current(conversation)
    if current == nil do return
    count := dialogue.available_count(conversation)
    layout := dialogue_tv_layout(width, height, count)
    scale := layout.scale
    presentation := dialogue_presentation_state(editor)
    panel_progress := dialogue_ease_out(editor.attendant_dialogue_view.panel_seconds / DIALOGUE_PANEL_TRANSITION_SECONDS)
    choice_progress := dialogue_ease_out(editor.attendant_dialogue_view.choice_seconds / DIALOGUE_CHOICE_TRANSITION_SECONDS)
    // A light full-frame scrim calms the scene without turning the speakers
    // into boxed portrait specimens.
    canvas2d.DrawRectangle(0, 0, width, height, ui_theme_scrim(u8(82 * panel_progress)))
    canvas2d.DrawRectangleRounded(layout.conversation, .025, 10, ui_theme_scrim(u8(226 * panel_progress)))
    canvas2d.DrawRectangleRoundedLinesEx(
        layout.conversation,
        .025,
        10,
        1 * scale,
        ui_theme_border(u8(255 * panel_progress)),
    )
    speaker := current.speaker(&conversation.ctx)
    speaker_size := 24 * scale
    speaker_measure := canvas2d.MeasureTextEx(dialogue_font(), fmt.ctprintf("%s", speaker), speaker_size, 1.2 * scale)
    speaker_tab_width := speaker_measure.x + 64 * scale
    _, resident_speaking := story.resident_from_speaker(speaker)
    speaker_tab_x := layout.conversation.x + 28 * scale
    if resident_speaking {
        speaker_tab_x = layout.conversation.x + layout.conversation.width - speaker_tab_width - 28 * scale
    }
    speaker_tab := canvas2d.Rectangle {
        speaker_tab_x,
        layout.conversation.y - 14 * scale,
        speaker_tab_width,
        46 * scale,
    }
    canvas2d.DrawRectangleRounded(speaker_tab, .12, 8, ui_theme_accent(u8(255 * panel_progress)))
    canvas2d.DrawRectangleRoundedLinesEx(speaker_tab, .12, 8, 1 * scale, ui_theme_accent_hover(u8(255 * panel_progress)))
    notch_center_y := speaker_tab.y + speaker_tab.height * .5
    notch_inner_x := resident_speaking ? speaker_tab.x + speaker_tab.width - 1 * scale : speaker_tab.x + 1 * scale
    notch_tip_x := notch_inner_x + (resident_speaking ? 10 * scale : -10 * scale)
    canvas2d.DrawLineEx(
        {notch_inner_x, notch_center_y - 7 * scale},
        {notch_tip_x, notch_center_y},
        3 * scale,
        ui_theme_accent_hover(),
    )
    canvas2d.DrawLineEx(
        {notch_tip_x, notch_center_y},
        {notch_inner_x, notch_center_y + 7 * scale},
        3 * scale,
        ui_theme_accent_hover(),
    )
    canvas2d.DrawTextEx(
        dialogue_font(),
        fmt.ctprintf("%s", speaker),
        {speaker_tab.x + 32 * scale, speaker_tab.y + 10 * scale},
        speaker_size,
        1.2 * scale,
        ui_theme_text_inverse(u8(255 * panel_progress)),
    )
    text := current.text(&conversation.ctx)
    visible_end := clamp(editor.attendant_dialogue_view.revealed_bytes, 0, len(text))
    speech_bounds := layout.speech
    current_is_tarot := current.id == "zora-reading" && editor.story_state.tarot_layout.count > 0
    if current_is_tarot do speech_bounds.height -= 108 * scale
    mouse := canvas2d.GetMousePosition()
    speech_opacity := panel_progress * (presentation == .Choosing ? f32(.82) : f32(1))
    hovered_english := dialogue_draw_glossed_wrapped(
        text[:visible_end],
        speech_bounds,
        29 * scale,
        1 * scale,
        39 * scale,
        ui_theme_text_inverse(u8(255 * speech_opacity)),
        mouse,
    )
    dialogue_draw_tarot_strip(editor, layout.speech, scale)
    visible_rows := dialogue_choice_visible_rows(layout)
    dialogue_choice_scroll_focus(editor, visible_rows)
    first := editor.attendant_dialogue_view.first_choice
    last := min(first + visible_rows, count)
    for choice_index in first ..< last {
        row := choice_index - first
        bounds := dialogue_choice_bounds(layout, row)
        focused := editor.attendant_dialogue_focus == choice_index
        hovered := canvas2d.CheckCollisionPointRec(mouse, bounds)
        base_state := hovered ? UI_Control_State.Hovered : UI_Control_State.Resting
        base_style := ui_theme_control_style(base_state)
        selected_style := ui_theme_control_style(.Selected)
        focus_progress := f32(0)
        if focused {
            focus_progress = dialogue_ease_out(
                (DIALOGUE_FOCUS_TRANSITION_SECONDS - min(editor.attendant_dialogue_view.reaction_seconds, DIALOGUE_FOCUS_TRANSITION_SECONDS)) /
                    DIALOGUE_FOCUS_TRANSITION_SECONDS,
            )
            if editor.attendant_dialogue_view.reaction_seconds <= 0 do focus_progress = 1
        }
        row_opacity := panel_progress * choice_progress
        fill := dialogue_color_alpha(
            dialogue_color_lerp(base_style.fill, selected_style.fill, focus_progress),
            row_opacity,
        )
        border := dialogue_color_alpha(
            dialogue_color_lerp(base_style.border, selected_style.border, focus_progress),
            row_opacity,
        )
        text_color := dialogue_color_alpha(
            dialogue_color_lerp(base_style.text, selected_style.text, focus_progress),
            row_opacity,
        )
        border_width := base_style.border_width + (selected_style.border_width - base_style.border_width) * focus_progress
        canvas2d.DrawRectangleRounded(bounds, .12, 8, fill)
        canvas2d.DrawRectangleRoundedLinesEx(bounds, .12, 8, border_width * scale, border)
        if focused {
            accent := canvas2d.Rectangle{bounds.x, bounds.y + 8 * scale, 6 * scale, bounds.height - 16 * scale}
            canvas2d.DrawRectangleRounded(accent, .8, 6, ui_theme_text_inverse(u8(255 * row_opacity * focus_progress)))
            canvas2d.DrawTextEx(
                dialogue_font(),
                "›",
                {bounds.x + 18 * scale, bounds.y + 14 * scale},
                30 * scale,
                .8 * scale,
                text_color,
            )
        }
        if response := dialogue.available_at(conversation, choice_index); response != nil {
            text_bounds := canvas2d.Rectangle {
                bounds.x + (focused ? 50 : 22) * scale,
                bounds.y,
                bounds.width - (focused ? 122 : 44) * scale,
                bounds.height,
            }
            choice_english := dialogue_draw_glossed_wrapped(
                response.text,
                text_bounds,
                26 * scale,
                .9 * scale,
                33 * scale,
                text_color,
                mouse,
                true,
            )
            if len(choice_english) > 0 do hovered_english = choice_english
        }
        if focused {
            confirm: cstring = controller_prompt_active(editor) ? controller_face_label(editor, .South) : "ENTER"
            confirm_size := 16 * scale
            confirm_measure := canvas2d.MeasureTextEx(dialogue_font(), confirm, confirm_size, .6 * scale)
            hint := canvas2d.Rectangle {
                bounds.x + bounds.width - confirm_measure.x - 24 * scale,
                bounds.y + (bounds.height - 28 * scale) * .5,
                confirm_measure.x + 14 * scale,
                28 * scale,
            }
            hint_opacity := row_opacity * focus_progress
            canvas2d.DrawRectangleRounded(hint, .3, 6, ui_theme_scrim(u8(78 * hint_opacity)))
            canvas2d.DrawRectangleRoundedLinesEx(hint, .3, 6, 1 * scale, ui_theme_text_inverse(u8(190 * hint_opacity)))
            canvas2d.DrawTextEx(
                dialogue_font(),
                confirm,
                {hint.x + 7 * scale, hint.y + 6 * scale},
                confirm_size,
                .6 * scale,
                ui_theme_text_inverse(u8(255 * hint_opacity)),
            )
        }
    }
    if presentation == .Speaking {
        hint: cstring = controller_prompt_active(editor) ? fmt.ctprintf("%s REVEALS", controller_face_label(editor, .South)) : "ENTER REVEALS"
        measured := canvas2d.MeasureTextEx(dialogue_font(), hint, 16 * scale, .6 * scale)
        canvas2d.DrawTextEx(
            dialogue_font(),
            hint,
            {layout.conversation.x + layout.conversation.width - measured.x - 24 * scale, layout.conversation.y + layout.conversation.height - 24 * scale},
            16 * scale,
            .6 * scale,
            ui_theme_text_inverse(u8(180 * panel_progress)),
        )
    } else if presentation == .Continuing {
        hint: cstring = controller_prompt_active(editor) ? fmt.ctprintf("%s CONTINUES", controller_face_label(editor, .South)) : "ENTER CONTINUES"
        measured := canvas2d.MeasureTextEx(dialogue_font(), hint, 17 * scale, .6 * scale)
        hint_bounds := canvas2d.Rectangle {
            layout.conversation.x + layout.conversation.width - measured.x - 38 * scale,
            layout.conversation.y + layout.conversation.height - 52 * scale,
            measured.x + 20 * scale,
            32 * scale,
        }
        canvas2d.DrawRectangleRounded(hint_bounds, .25, 6, ui_theme_accent(u8(220 * panel_progress)))
        canvas2d.DrawTextEx(
            dialogue_font(),
            hint,
            {hint_bounds.x + 10 * scale, hint_bounds.y + 7 * scale},
            17 * scale,
            .6 * scale,
            ui_theme_text_inverse(u8(255 * panel_progress)),
        )
    }
    if count > visible_rows && visible_rows > 0 {
        position_label := fmt.ctprintf("%d–%d OF %d   ↑↓", first + 1, last, count)
        measured := canvas2d.MeasureTextEx(dialogue_font(), position_label, 16 * scale, .6 * scale)
        canvas2d.DrawTextEx(
            dialogue_font(),
            position_label,
            {
                layout.conversation.x + layout.conversation.width - measured.x - 24 * scale,
                layout.conversation.y + layout.conversation.height - 22 * scale,
            },
            16 * scale,
            .6 * scale,
            ui_theme_text_muted(u8(220 * panel_progress * choice_progress)),
        )
    }
    dialogue_draw_glossary_tooltip(hovered_english, mouse, width, height, scale)
}
