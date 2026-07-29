package main

import engine_sound "../packages/engine_sound"
import "core:fmt"
import rl "zelda_engine:canvas2d"

DIALOGUE_SOUND_LAB_TEXT_CAPACITY :: 4096

Dialogue_Sound_Lab_State :: struct {
    text:          [DIALOGUE_SOUND_LAB_TEXT_CAPACITY]u8,
    text_length:   int,
    cursor:        int,
    playing:       bool,
    reveal_timer:  f32,
    last_time:     f64,
    dragging:      int,
    preset:        int,
    unit_blend:    f32,
    speech_rate:   f32,
    expression:    f32,
    formant_shift: f32,
    profile:       engine_sound.Dialogue_Voice_Profile,
}

dialogue_sound_lab: Dialogue_Sound_Lab_State
DIALOGUE_SOUND_LAB_SLIDER_COUNT :: 9

dialogue_sound_lab_presets := [?]engine_sound.Dialogue_Voice_Profile {
    {430, 190, .68, .48, .095, 430},
    {345, 145, .54, .68, .105, 345},
    {520, 235, .78, .34, .082, 520},
    {265, 105, .38, .86, .115, 265},
}

dialogue_sound_lab_preset_names := [?]cstring{"SPROUT", "STORYBOOK", "CHIRPY", "COZY"}

dialogue_sound_lab_text :: proc() -> string {
    return string(dialogue_sound_lab.text[:dialogue_sound_lab.text_length])
}

dialogue_sound_lab_set_text :: proc(text: string) {
    dialogue_sound_lab.text = {}
    dialogue_sound_lab.text_length = min(len(text), len(dialogue_sound_lab.text))
    copy(
        dialogue_sound_lab.text[:dialogue_sound_lab.text_length],
        transmute([]u8)text[:dialogue_sound_lab.text_length],
    )
}

dialogue_sound_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    dialogue_sound_lab = {
        profile       = dialogue_sound_lab_presets[1],
        preset        = 1,
        unit_blend    = .82,
        speech_rate   = 1 / DIALOGUE_REVEAL_SECONDS,
        expression    = .78,
        formant_shift = 0,
        dragging      = -1,
        last_time     = rl.GetTime(),
    }
    dialogue_sound_lab_set_text(
        "Along the harbor wall, every small sound carried: rope against cedar, water under stone, and the soft knock of boats coming home.",
    )
    engine_sound.dialogue_voice_stop(&editor.engine_audio)
    editor.engine_audio.dialogue_voice.unit_blend = dialogue_sound_lab.unit_blend
    _ = rl.StartTextInput()
    set_pointer_locked(false)
    if target == "autoplay" do dialogue_sound_lab_play(editor)
    return true
}

dialogue_sound_lab_exit :: proc(editor: ^Editor) {
    if editor != nil do engine_sound.dialogue_voice_stop(&editor.engine_audio)
    dialogue_sound_lab.playing = false
    dialogue_sound_lab.dragging = -1
    _ = rl.StopTextInput()
}

dialogue_sound_lab_play :: proc(editor: ^Editor) {
    if editor == nil || dialogue_sound_lab.text_length == 0 do return
    engine_sound.dialogue_voice_stop(&editor.engine_audio)
    dialogue_sound_lab.cursor = 0
    dialogue_sound_lab.reveal_timer = 0
    dialogue_sound_lab.playing = true
}

dialogue_sound_lab_stop :: proc(editor: ^Editor) {
    if editor != nil do engine_sound.dialogue_voice_stop(&editor.engine_audio)
    dialogue_sound_lab.playing = false
    dialogue_sound_lab.cursor = 0
    dialogue_sound_lab.reveal_timer = 0
}

dialogue_sound_lab_append :: proc(text: string) {
    if text == "" do return
    remaining := len(dialogue_sound_lab.text) - dialogue_sound_lab.text_length
    count := min(remaining, len(text))
    if count <= 0 do return
    copy(dialogue_sound_lab.text[dialogue_sound_lab.text_length:], transmute([]u8)text[:count])
    dialogue_sound_lab.text_length += count
}

dialogue_sound_lab_backspace :: proc() {
    if dialogue_sound_lab.text_length == 0 do return
    dialogue_sound_lab.text_length -= 1
    for dialogue_sound_lab.text_length > 0 &&
        (dialogue_sound_lab.text[dialogue_sound_lab.text_length] & 0xc0) == 0x80 {
        dialogue_sound_lab.text_length -= 1
    }
}

dialogue_sound_lab_controls :: proc(
    width, height: i32,
) -> (
    panel, editor_bounds, play_bounds, stop_bounds: rl.Rectangle,
    slider_x, slider_y, slider_w: f32,
) {
    panel_w := min(f32(width) - 64, f32(980))
    panel_h := min(f32(height) - 64, f32(650))
    panel = {(f32(width) - panel_w) * .5, (f32(height) - panel_h) * .5, panel_w, panel_h}
    editor_bounds = {panel.x + 34, panel.y + 88, panel.width - 68, 170}
    play_bounds = {panel.x + 34, panel.y + panel.height - 70, 150, 40}
    stop_bounds = {panel.x + 196, panel.y + panel.height - 70, 110, 40}
    slider_x = panel.x + 210
    slider_y = panel.y + 306
    slider_w = panel.width - 252
    return
}

dialogue_sound_lab_slider_value :: proc(index: int) -> (value, low, high: f32) {
    switch index {
    case 0:
        return dialogue_sound_lab.profile.base_hz, 90, 700
    case 1:
        return dialogue_sound_lab.profile.range_hz, 0, 400
    case 2:
        return dialogue_sound_lab.profile.brightness, 0, 1
    case 3:
        return dialogue_sound_lab.profile.warmth, 0, 1
    case 4:
        return dialogue_sound_lab.profile.gain, 0, .24
    case 5:
        return dialogue_sound_lab.unit_blend, 0, 1
    case 6:
        return dialogue_sound_lab.speech_rate, 12, 50
    case 7:
        return dialogue_sound_lab.expression, 0, 1
    case 8:
        return dialogue_sound_lab.formant_shift, -5, 5
    }
    return 0, 0, 1
}

dialogue_sound_lab_set_slider :: proc(index: int, normalized: f32) {
    value, low, high := dialogue_sound_lab_slider_value(index)
    _ = value
    value = low + clamp(normalized, 0, 1) * (high - low)
    switch index {
    case 0:
        dialogue_sound_lab.profile.base_hz = value
    case 1:
        dialogue_sound_lab.profile.range_hz = value
    case 2:
        dialogue_sound_lab.profile.brightness = value
    case 3:
        dialogue_sound_lab.profile.warmth = value
    case 4:
        dialogue_sound_lab.profile.gain = value
    case 5:
        dialogue_sound_lab.unit_blend = value
    case 6:
        dialogue_sound_lab.speech_rate = value
    case 7:
        dialogue_sound_lab.expression = value
    case 8:
        dialogue_sound_lab.formant_shift = value
    }
    if index <= 4 {
        // Presets describe the source timbre. Delivery controls can be tuned
        // independently without making the selected character ambiguous.
        dialogue_sound_lab.preset = -1
    }
}

dialogue_sound_lab_tick :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil || !dialogue_sound_lab.playing do return
    text := dialogue_sound_lab_text()
    dialogue_sound_lab.reveal_timer -= max(delta_seconds, 0)
    for dialogue_sound_lab.cursor < len(text) && dialogue_sound_lab.reveal_timer <= 0 {
        start := dialogue_sound_lab.cursor
        dialogue_sound_lab.cursor = dialogue_voice_unit_end(text, start)
        unit := text[start:dialogue_sound_lab.cursor]
        seconds_per_glyph := 1 / max(dialogue_sound_lab.speech_rate, f32(1))
        pause_scale := seconds_per_glyph / DIALOGUE_REVEAL_SECONDS
        dialogue_sound_lab.reveal_timer += seconds_per_glyph + dialogue_reveal_pause(unit) * pause_scale
        if dialogue_voice_should_synthesize_at(text, start, dialogue_sound_lab.cursor) {
            cadence_hint := dialogue_voice_cadence_hint(text, start, dialogue_sound_lab.cursor)
            next_grapheme := dialogue_voice_next_synthesized_grapheme(text, dialogue_sound_lab.cursor)
            engine_sound.dialogue_voice_trigger_grapheme(
                &editor.engine_audio,
                text[start:dialogue_sound_lab.cursor],
                dialogue_sound_lab.profile,
                cadence_hint,
                next_grapheme,
                dialogue_voice_word_progress(text, start, dialogue_sound_lab.cursor),
                dialogue_sound_lab.expression,
                dialogue_sound_lab.formant_shift,
            )
        } else if unit == " " || unit == "\t" {
            engine_sound.dialogue_voice_mixer_word_boundary(&editor.engine_audio.dialogue_voice)
        } else if dialogue_voice_is_phrase_boundary(unit) {
            engine_sound.dialogue_voice_phrase_boundary(&editor.engine_audio)
        }
    }
    if dialogue_sound_lab.cursor >= len(text) {
        dialogue_sound_lab.playing = false
    }
}

dialogue_sound_lab_process_input :: proc(editor: ^Editor) {
    if editor == nil do return
    now := rl.GetTime()
    delta := f32(clamp(now - dialogue_sound_lab.last_time, f64(0), f64(.05)))
    dialogue_sound_lab.last_time = now
    dialogue_sound_lab_tick(editor, delta)
    editor.engine_audio.dialogue_voice.unit_blend = dialogue_sound_lab.unit_blend

    panel, editor_bounds, play_bounds, stop_bounds, slider_x, slider_y, slider_w := dialogue_sound_lab_controls(
        rl.GetScreenWidth(),
        rl.GetScreenHeight(),
    )
    _ = panel
    _ = rl.SetTextInputArea(editor_bounds, dialogue_sound_lab.text_length)
    if !dialogue_sound_lab.playing {
        dialogue_sound_lab_append(rl.GetTextInput())
        if rl.IsKeyPressed(.BACKSPACE) do dialogue_sound_lab_backspace()
        if rl.IsKeyPressed(.ENTER) do dialogue_sound_lab_append("\n")
    }

    mouse := rl.GetMousePosition()
    pressed := rl.IsMouseButtonPressed(.LEFT)
    if pressed && rl.CheckCollisionPointRec(mouse, play_bounds) do dialogue_sound_lab_play(editor)
    if pressed && rl.CheckCollisionPointRec(mouse, stop_bounds) do dialogue_sound_lab_stop(editor)
    if pressed {
        preset_gap := f32(10)
        preset_w := (editor_bounds.width - preset_gap * 3) / 4
        for _, index in dialogue_sound_lab_presets {
            bounds := rl.Rectangle {
                editor_bounds.x + f32(index) * (preset_w + preset_gap),
                editor_bounds.y + editor_bounds.height + 8,
                preset_w,
                28,
            }
            if rl.CheckCollisionPointRec(mouse, bounds) {
                dialogue_sound_lab.profile = dialogue_sound_lab_presets[index]
                dialogue_sound_lab.preset = index
                break
            }
        }
    }

    if pressed {
        for index in 0 ..< DIALOGUE_SOUND_LAB_SLIDER_COUNT {
            bounds := rl.Rectangle{slider_x, slider_y + f32(index) * 31 - 8, slider_w, 28}
            if rl.CheckCollisionPointRec(mouse, bounds) {
                dialogue_sound_lab.dragging = index
                dialogue_sound_lab_set_slider(index, (mouse.x - slider_x) / slider_w)
                break
            }
        }
    }
    if rl.IsMouseButtonDown(.LEFT) && dialogue_sound_lab.dragging >= 0 {
        dialogue_sound_lab_set_slider(dialogue_sound_lab.dragging, (mouse.x - slider_x) / slider_w)
    }
    if rl.IsMouseButtonReleased(.LEFT) do dialogue_sound_lab.dragging = -1

    if rl.IsKeyPressed(.ESCAPE) {
        lab_scene_exit_to_main_menu(editor)
    }
}

dialogue_sound_lab_button :: proc(bounds: rl.Rectangle, label: cstring, active: bool) {
    fill := active ? rl.Color{30, 112, 108, 255} : rl.Color{25, 43, 50, 255}
    if rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds) {
        fill = active ? rl.Color{38, 137, 131, 255} : rl.Color{36, 58, 66, 255}
    }
    rl.DrawRectangleRounded(bounds, .18, 7, fill)
    rl.DrawRectangleRoundedLinesEx(bounds, .18, 7, 1, {104, 211, 199, 255})
    size := ui_measure_text(.Label, label, .4)
    ui_draw_text(.Label, label, {bounds.x + (bounds.width - size.x) * .5, bounds.y + 11}, .4, {231, 244, 241, 255})
}

dialogue_sound_lab_draw_ui :: proc(_: ^Editor, width, height: i32) {
    rl.DrawRectangle(0, 0, width, height, {7, 15, 20, 255})
    panel, editor_bounds, play_bounds, stop_bounds, slider_x, slider_y, slider_w := dialogue_sound_lab_controls(
        width,
        height,
    )
    rl.DrawRectangleRounded(panel, .035, 10, {12, 27, 34, 255})
    rl.DrawRectangleRoundedLinesEx(panel, .035, 10, 1, {70, 113, 120, 255})
    ui_draw_text(.Label, "DIALOGUE SOUND LAB", {panel.x + 34, panel.y + 28}, .65, {116, 226, 211, 255})
    ui_draw_text(
        .Data,
        "TYPE A PASSAGE, TUNE THE VOICE, THEN PRESS READ",
        {panel.x + 34, panel.y + 57},
        .22,
        {139, 163, 169, 255},
    )

    rl.DrawRectangleRounded(editor_bounds, .035, 6, {7, 17, 22, 255})
    rl.DrawRectangleRoundedLinesEx(editor_bounds, .035, 6, 1, {60, 91, 99, 255})
    text := dialogue_sound_lab_text()
    visible := dialogue_sound_lab.playing ? text[:dialogue_sound_lab.cursor] : text
    dialogue_draw_wrapped(
        visible,
        {editor_bounds.x + 18, editor_bounds.y + 16, editor_bounds.width - 36, editor_bounds.height - 32},
        22,
        1,
        31,
        {224, 233, 232, 255},
    )
    if !dialogue_sound_lab.playing && int(rl.GetTime() * 2) % 2 == 0 {
        rl.DrawRectangle(
            i32(editor_bounds.x + 18),
            i32(editor_bounds.y + editor_bounds.height - 15),
            14,
            2,
            {116, 226, 211, 255},
        )
    }

    preset_gap := f32(10)
    preset_w := (editor_bounds.width - preset_gap * 3) / 4
    for name, index in dialogue_sound_lab_preset_names {
        bounds := rl.Rectangle {
            editor_bounds.x + f32(index) * (preset_w + preset_gap),
            editor_bounds.y + editor_bounds.height + 8,
            preset_w,
            28,
        }
        selected := dialogue_sound_lab.preset == index
        fill := selected ? rl.Color{40, 105, 101, 255} : rl.Color{20, 40, 47, 255}
        if rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds) {
            fill = selected ? rl.Color{48, 126, 120, 255} : rl.Color{30, 56, 63, 255}
        }
        rl.DrawRectangleRounded(bounds, .18, 6, fill)
        rl.DrawRectangleRoundedLinesEx(
            bounds,
            .18,
            6,
            1,
            selected ? rl.Color{142, 231, 217, 255} : rl.Color{60, 91, 99, 255},
        )
        size := ui_measure_text(.Label, name, .28)
        ui_draw_text(.Label, name, {bounds.x + (bounds.width - size.x) * .5, bounds.y + 8}, .28, {210, 229, 226, 255})
    }

    names := [?]cstring {
        "BASE PITCH",
        "PITCH RANGE",
        "BRIGHTNESS",
        "WARMTH",
        "GAIN",
        "CV COARTICULATION",
        "SPEECH RATE",
        "EXPRESSION",
        "FORMANT SHIFT",
    }
    for name, index in names {
        value, low, high := dialogue_sound_lab_slider_value(index)
        y := slider_y + f32(index) * 31
        ui_draw_text(.Label, name, {panel.x + 34, y - 7}, .32, {183, 199, 202, 255})
        rl.DrawRectangleRounded({slider_x, y, slider_w, 8}, 1, 4, {43, 65, 71, 255})
        normalized := (value - low) / (high - low)
        rl.DrawRectangleRounded({slider_x, y, slider_w * normalized, 8}, 1, 4, {77, 182, 171, 255})
        rl.DrawCircleV({slider_x + slider_w * normalized, y + 4}, 8, {170, 235, 225, 255})
        value_label :=
            index < 2 ? fmt.ctprintf("%.0f Hz", value) : (index == 4 ? fmt.ctprintf("%.3f", value) : (index == 6 ? fmt.ctprintf("%.0f char/s", value) : (index == 8 ? fmt.ctprintf("%+.1f st", value) : fmt.ctprintf("%.2f", value))))
        ui_draw_text(.Data, value_label, {slider_x + slider_w - 64, y - 23}, .22, {149, 173, 177, 255})
    }

    dialogue_sound_lab_button(
        play_bounds,
        dialogue_sound_lab.playing ? "READING..." : "READ",
        dialogue_sound_lab.playing,
    )
    dialogue_sound_lab_button(stop_bounds, "STOP", false)
    progress := f32(0)
    if dialogue_sound_lab.text_length > 0 {
        progress = f32(dialogue_sound_lab.cursor) / f32(dialogue_sound_lab.text_length)
    }
    ui_draw_text(
        .Data,
        fmt.ctprintf(
            "%d / %d BYTES  •  %.0f%%",
            dialogue_sound_lab.cursor,
            dialogue_sound_lab.text_length,
            progress * 100,
        ),
        {panel.x + 330, panel.y + panel.height - 56},
        .22,
        {122, 151, 157, 255},
    )
    ui_draw_text(
        .Data,
        "ESC  EXIT",
        {panel.x + panel.width - 105, panel.y + panel.height - 54},
        .22,
        {122, 151, 157, 255},
    )
}
