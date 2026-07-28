package main

import dialogue "../packages/dialogue"
import dialogue_glossary "../packages/dialogue_glossary"
import engine_sound "../packages/engine_sound"
import story "../packages/story"
import "core:fmt"
import "core:math"
import rl "zelda_engine:canvas2d"

DIALOGUE_REFERENCE_HEIGHT :: f32(720)
DIALOGUE_REVEAL_SECONDS :: f32(.032)
DIALOGUE_CHOICE_VISIBLE_MAX :: 5

@(no_instrumentation)
dialogue_font :: #force_inline proc() -> rl.Font {
    return rl.DisplayFont()
}

Dialogue_View_State :: struct {
    revision:         u64,
    revealed_bytes:   int,
    reveal_timer:     f32,
    first_choice:     int,
    reaction_seconds: f32,
    previous_focus:   int,
}

Dialogue_Tv_Layout :: struct {
    scale:        f32,
    player_card:  rl.Rectangle,
    conversation: rl.Rectangle,
    npc_card:     rl.Rectangle,
    speech:       rl.Rectangle,
    choices:      rl.Rectangle,
    choice_row_h: f32,
    choice_gap:   f32,
}

dialogue_tv_layout :: proc(width, height: i32) -> Dialogue_Tv_Layout {
    scale := max(f32(height) / DIALOGUE_REFERENCE_HEIGHT, f32(1))
    safe_x := max(f32(width) * .05, 24 * scale)
    safe_y := max(f32(height) * .05, 24 * scale)
    available := max(f32(width) - safe_x * 2, 720 * scale)
    gap := 24 * scale
    card_w := min(240 * scale, max((available - 624 * scale - gap * 2) * .5, 112 * scale))
    center_w := available - card_w * 2 - gap * 2
    center_w = max(center_w, 480 * scale)
    total_w := card_w * 2 + center_w + gap * 2
    start_x := (f32(width) - total_w) * .5
    height_safe := max(f32(height) - safe_y * 2, 620 * scale)
    center := rl.Rectangle{start_x + card_w + gap, safe_y, center_w, height_safe}
    speech_h := min(230 * scale, center.height * .38)
    return {
        scale = scale,
        player_card = {start_x, safe_y, card_w, height_safe},
        conversation = center,
        npc_card = {center.x + center.width + gap, safe_y, card_w, height_safe},
        speech = {center.x + 28 * scale, center.y + 76 * scale, center.width - 56 * scale, speech_h},
        choices = {
            center.x + 24 * scale,
            center.y + 76 * scale + speech_h + 12 * scale,
            center.width - 48 * scale,
            center.height - 76 * scale - speech_h - 36 * scale,
        },
        choice_row_h = 64 * scale,
        choice_gap = 10 * scale,
    }
}

dialogue_next_glyph_end :: proc(text: string, start: int) -> int {
    if start >= len(text) do return len(text)
    return min(start + rl.TextNextGrapheme(text[start:]), len(text))
}

dialogue_reveal_pause :: proc(glyph: u8) -> f32 {
    switch glyph {
    case '.', '!', '?':
        return .18
    case ',', ';', ':':
        return .09
    case '\n':
        return .12
    }
    return 0
}

dialogue_voice_profile :: proc(resident: story.Resident) -> engine_sound.Dialogue_Voice_Profile {
    switch resident {
    case .Marta:
        return {390, 170, .72, .34, .105}
    case .Gerta:
        return {310, 120, .48, .72, .11}
    case .Niko:
        return {270, 105, .42, .82, .11}
    case .Iva:
        return {430, 155, .68, .48, .10}
    case .Bojan:
        return {235, 90, .38, .88, .115}
    case .Zora:
        return {335, 210, .62, .68, .105}
    }
    return {340, 140, .55, .6, .1}
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
    if view.previous_focus != editor.attendant_dialogue_focus {
        view.previous_focus = editor.attendant_dialogue_focus
        view.reaction_seconds = .22
    }
    view.reveal_timer -= max(delta_seconds, 0)
    for view.revealed_bytes < len(text) && view.reveal_timer <= 0 {
        start := view.revealed_bytes
        view.revealed_bytes = dialogue_next_glyph_end(text, start)
        glyph := text[start]
        view.reveal_timer += DIALOGUE_REVEAL_SECONDS + dialogue_reveal_pause(glyph)
        if (glyph >= 'A' && glyph <= 'Z') || (glyph >= 'a' && glyph <= 'z') || glyph >= 0x80 {
            engine_sound.dialogue_voice_trigger(
                &editor.engine_audio,
                glyph,
                dialogue_voice_profile(editor.dialogue_resident),
            )
        }
    }
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
    return max(min(int((layout.choices.height + layout.choice_gap) / stride), DIALOGUE_CHOICE_VISIBLE_MAX), 1)
}

dialogue_choice_scroll_focus :: proc(editor: ^Editor, visible_rows: int) {
    if editor == nil do return
    count := dialogue.available_count(&editor.attendant_dialogue)
    max_first := max(count - visible_rows, 0)
    if editor.attendant_dialogue_focus < editor.attendant_dialogue_view.first_choice {
        editor.attendant_dialogue_view.first_choice = editor.attendant_dialogue_focus
    } else if editor.attendant_dialogue_focus >= editor.attendant_dialogue_view.first_choice + visible_rows {
        editor.attendant_dialogue_view.first_choice = editor.attendant_dialogue_focus - visible_rows + 1
    }
    editor.attendant_dialogue_view.first_choice = clamp(editor.attendant_dialogue_view.first_choice, 0, max_first)
}

dialogue_choice_bounds :: proc(layout: Dialogue_Tv_Layout, visible_row: int) -> rl.Rectangle {
    return {
        layout.choices.x,
        layout.choices.y + f32(visible_row) * (layout.choice_row_h + layout.choice_gap),
        layout.choices.width,
        layout.choice_row_h,
    }
}

dialogue_draw_wrapped :: proc(text: string, bounds: rl.Rectangle, size, spacing, line_height: f32, color: rl.Color) {
    if len(text) == 0 do return
    _ = rl.DrawTextWrappedEx(dialogue_font(), fmt.ctprintf("%s", text), bounds, size, spacing, line_height, color)
}

dialogue_word_byte :: proc(byte: u8) -> bool {
    return (byte >= 'A' && byte <= 'Z') || (byte >= 'a' && byte <= 'z') || byte >= 0x80
}

// Draws the same wrapped text as dialogue_draw_wrapped, but keeps word bounds
// so Adriatic vocabulary can act as an unobtrusive language-learning aid.
dialogue_draw_glossed_wrapped :: proc(
    text: string,
    bounds: rl.Rectangle,
    size, spacing, line_height: f32,
    color: rl.Color,
    mouse: rl.Vector2,
) -> string {
    if len(text) == 0 do return ""
    lines := make([dynamic]rl.Text_Wrapped_Line, 0, 8, context.temp_allocator)
    rl.LayoutTextWrappedEx(dialogue_font(), fmt.ctprintf("%s", text), size, spacing, bounds.width, .Auto, &lines)
    hovered_english := ""
    visible := min(len(lines), max(int(bounds.height / line_height), 0))
    for line, line_index in lines[:visible] {
        x := bounds.x
        y := bounds.y + f32(line_index) * line_height
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
            measured := rl.MeasureTextEx(dialogue_font(), fmt.ctprintf("%s", token), size, spacing)
            if !is_space && x > bounds.x && x + measured.x > bounds.x + bounds.width {
                x = bounds.x
                y += line_height
                if y + line_height > bounds.y + bounds.height do break
            }
            if is_space && x == bounds.x do continue

            rl.DrawTextEx(dialogue_font(), fmt.ctprintf("%s", token), {x, y}, size, spacing, color)
            if !is_space {
                word_start, word_end := 0, len(token)
                for word_start < word_end && !dialogue_word_byte(token[word_start]) do word_start += 1
                for word_end > word_start && !dialogue_word_byte(token[word_end - 1]) do word_end -= 1
                if word_start < word_end {
                    word := token[word_start:word_end]
                    if english, found := dialogue_glossary.english_for(word); found {
                        prefix_width: f32
                        if word_start > 0 {
                            prefix := token[:word_start]
                            prefix_width =
                                rl.MeasureTextEx(dialogue_font(), fmt.ctprintf("%s", prefix), size, spacing).x
                        }
                        word_width := rl.MeasureTextEx(dialogue_font(), fmt.ctprintf("%s", word), size, spacing).x
                        word_bounds := rl.Rectangle{x + prefix_width, y, word_width, line_height}
                        hovered := rl.CheckCollisionPointRec(mouse, word_bounds)
                        underline_color := hovered ? ui_theme_focus() : ui_theme_accent(190)
                        rl.DrawRectangle(
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

dialogue_draw_glossary_tooltip :: proc(english: string, mouse: rl.Vector2, width, height: i32, scale: f32) {
    if len(english) == 0 do return
    label := fmt.ctprintf("English: %s", english)
    font_size := 20 * scale
    measured := rl.MeasureTextEx(dialogue_font(), label, font_size, .8 * scale)
    panel := rl.Rectangle {
        clamp(mouse.x + 14 * scale, 8 * scale, f32(width) - measured.x - 32 * scale),
        clamp(mouse.y - 48 * scale, 8 * scale, f32(height) - 42 * scale),
        measured.x + 20 * scale,
        34 * scale,
    }
    rl.DrawRectangleRounded(panel, .22, 6, ui_theme_surface_elevated(250))
    rl.DrawRectangleRoundedLinesEx(panel, .22, 6, 1 * scale, ui_theme_focus())
    rl.DrawTextEx(
        dialogue_font(),
        label,
        {panel.x + 10 * scale, panel.y + 7 * scale},
        font_size,
        .8 * scale,
        ui_theme_text(),
    )
}

dialogue_draw_tarot_strip :: proc(editor: ^Editor, bounds: rl.Rectangle, scale: f32) {
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
        card := rl.Rectangle{x + f32(index) * (card_w + gap), y, card_w, card_h}
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
            source := rl.Rectangle{f32(atlas_column * 108), f32(atlas_row * 158), 108, 158}
            if placement.orientation == .Reversed {
                source.x += source.width
                source.y += source.height
                source.width = -source.width
                source.height = -source.height
            }
            rl.DrawTexturePro(editor.tarot_atlas, source, card, {255, 255, 255, 255})
        } else {
            rl.DrawRectangleRounded(card, .06, 6, ui_theme_control())
        }
        rl.DrawRectangleRoundedLinesEx(card, .06, 6, 1 * scale, ui_theme_focus())
    }
}

dialogue_portrait_color :: proc(editor: ^Editor, resident: story.Resident, player: bool) -> rl.Color {
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
    }
    return {145, 125, 101, 255}
}

dialogue_draw_live_portrait :: proc(
    editor: ^Editor,
    bounds: rl.Rectangle,
    resident: story.Resident,
    player, active: bool,
    reaction: f32,
) {
    scale := min(bounds.width / 240, bounds.height / 620)
    // The true mesh is rendered in the world pass beneath this chrome. Keep
    // the portrait interior untouched so its lighting and colors remain true.
    border := active ? ui_theme_focus() : ui_theme_border()
    rl.DrawRectangleRoundedLinesEx(bounds, .06, 10, active ? 3 * scale : 1 * scale, border)
    _ = reaction
    name := player ? "YOU" : story.resident_name(resident)
    name_size := 24 * scale
    measured := rl.MeasureTextEx(dialogue_font(), fmt.ctprintf("%s", name), name_size, 1 * scale)
    nameplate := rl.Rectangle {
        bounds.x + (bounds.width - measured.x) * .5 - 12 * scale,
        bounds.y + bounds.height - 72 * scale,
        measured.x + 24 * scale,
        42 * scale,
    }
    rl.DrawRectangleRounded(nameplate, .35, 8, ui_theme_surface_elevated(232))
    rl.DrawRectangleRoundedLinesEx(nameplate, .35, 8, 1 * scale, border)
    rl.DrawTextEx(
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
    layout := dialogue_tv_layout(width, height)
    scale := layout.scale
    // Portrait meshes are part of the world target, so dim around their cards
    // rather than painting over them. The opaque center panel covers its gap.
    dim := ui_theme_scrim(202)
    cards_top := layout.player_card.y
    cards_bottom := layout.player_card.y + layout.player_card.height
    rl.DrawRectangle(0, 0, width, i32(cards_top), dim)
    rl.DrawRectangle(0, i32(cards_bottom), width, max(height - i32(cards_bottom), 0), dim)
    rl.DrawRectangle(0, i32(cards_top), i32(layout.player_card.x), i32(layout.player_card.height), dim)
    between_x := layout.player_card.x + layout.player_card.width
    rl.DrawRectangle(
        i32(between_x),
        i32(cards_top),
        max(i32(layout.npc_card.x - between_x), 0),
        i32(layout.player_card.height),
        dim,
    )
    npc_right := layout.npc_card.x + layout.npc_card.width
    rl.DrawRectangle(
        i32(npc_right),
        i32(cards_top),
        max(width - i32(npc_right), 0),
        i32(layout.player_card.height),
        dim,
    )
    conversation := &editor.attendant_dialogue
    current := dialogue.current(conversation)
    if current == nil do return
    revealing := dialogue_view_revealing(editor)
    player_active := !revealing
    dialogue_draw_live_portrait(
        editor,
        layout.player_card,
        editor.dialogue_resident,
        true,
        player_active,
        editor.attendant_dialogue_view.reaction_seconds,
    )
    dialogue_draw_live_portrait(
        editor,
        layout.npc_card,
        editor.dialogue_resident,
        false,
        !player_active,
        revealing ? f32(.12) : 0,
    )
    rl.DrawRectangleRounded(layout.conversation, .035, 10, ui_theme_surface())
    rl.DrawRectangleRoundedLinesEx(layout.conversation, .035, 10, 2 * scale, ui_theme_border_strong())
    speaker := current.speaker(&conversation.ctx)
    rl.DrawTextEx(
        dialogue_font(),
        fmt.ctprintf("%s", speaker),
        {layout.conversation.x + 28 * scale, layout.conversation.y + 24 * scale},
        24 * scale,
        1.2 * scale,
        ui_theme_accent(),
    )
    text := current.text(&conversation.ctx)
    visible_end := clamp(editor.attendant_dialogue_view.revealed_bytes, 0, len(text))
    speech_bounds := layout.speech
    current_is_tarot := current.id == "zora-reading" && editor.story_state.tarot_layout.count > 0
    if current_is_tarot do speech_bounds.height -= 108 * scale
    mouse := rl.GetMousePosition()
    hovered_english := dialogue_draw_glossed_wrapped(
        text[:visible_end],
        speech_bounds,
        28 * scale,
        1 * scale,
        37 * scale,
        ui_theme_text(),
        mouse,
    )
    dialogue_draw_tarot_strip(editor, layout.speech, scale)
    count := dialogue.available_count(conversation)
    visible_rows := dialogue_choice_visible_rows(layout)
    dialogue_choice_scroll_focus(editor, visible_rows)
    first := editor.attendant_dialogue_view.first_choice
    last := min(first + visible_rows, count)
    for choice_index in first ..< last {
        row := choice_index - first
        bounds := dialogue_choice_bounds(layout, row)
        focused := editor.attendant_dialogue_focus == choice_index
        hovered := rl.CheckCollisionPointRec(mouse, bounds)
        state := UI_Control_State.Resting
        if hovered do state = .Hovered
        if focused do state = .Focused
        style := ui_theme_control_style(state)
        rl.DrawRectangleRounded(bounds, .12, 8, style.fill)
        rl.DrawRectangleRoundedLinesEx(bounds, .12, 8, (focused ? 3 : style.border_width) * scale, style.border)
        if response := dialogue.available_at(conversation, choice_index); response != nil {
            text_bounds := rl.Rectangle {
                bounds.x + 18 * scale,
                bounds.y + 8 * scale,
                bounds.width - 36 * scale,
                bounds.height - 12 * scale,
            }
            choice_english := dialogue_draw_glossed_wrapped(
                response.text,
                text_bounds,
                26 * scale,
                .8 * scale,
                31 * scale,
                style.text,
                mouse,
            )
            if len(choice_english) > 0 do hovered_english = choice_english
        }
    }
    if first > 0 {
        rl.DrawTextEx(
            dialogue_font(),
            "MORE ABOVE",
            {layout.choices.x + layout.choices.width - 150 * scale, layout.choices.y - 25 * scale},
            18 * scale,
            .6 * scale,
            ui_theme_text_muted(),
        )
    }
    if last < count {
        rl.DrawTextEx(
            dialogue_font(),
            "MORE BELOW",
            {
                layout.choices.x + layout.choices.width - 150 * scale,
                layout.choices.y + f32(visible_rows) * (layout.choice_row_h + layout.choice_gap) - 2 * scale,
            },
            18 * scale,
            .6 * scale,
            ui_theme_text_muted(),
        )
    }
    dialogue_draw_glossary_tooltip(hovered_english, mouse, width, height, scale)
}
