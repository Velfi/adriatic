package main

import game_input "zelda_engine:game_input"
import player_mail "../packages/player_mail"
import story "../packages/story"
import "core:fmt"
import "core:math"
import sdl "vendor:sdl3"
import canvas2d "zelda_engine:canvas2d"

PLAYER_MAIL_ROW_HEIGHT :: f32(62)

player_mail_available_count :: proc(editor: ^Editor) -> int {
    if editor == nil do return 0
    count := 0
    if !editor.player_mail.received[int(player_mail.Letter_ID.Welcome)] do count += 1
    if story.has_friendometer(&editor.story_state) &&
       !editor.player_mail.received[int(player_mail.Letter_ID.Mirna_Field_Notes)] {
        count += 1
    }
    if editor.story_state.completed_deliveries >= 3 &&
       !editor.player_mail.received[int(player_mail.Letter_ID.Postmasters_Thanks)] {
        count += 1
    }
    return count
}

player_mail_collect :: proc(editor: ^Editor) -> int {
    if editor == nil do return 0
    collected := 0
    if player_mail.receive(&editor.player_mail, .Welcome) do collected += 1
    if story.has_friendometer(&editor.story_state) && player_mail.receive(&editor.player_mail, .Mirna_Field_Notes) {
        collected += 1
    }
    if editor.story_state.completed_deliveries >= 3 && player_mail.receive(&editor.player_mail, .Postmasters_Thanks) {
        collected += 1
    }
    editor.player_mail_last_collected = collected
    if collected > 0 do editor.player_mail_notice_until = canvas2d.GetTime() + 4
    return collected
}

player_mail_notice_draw :: proc(editor: ^Editor, width: i32) {
    if editor == nil || editor.player_mail_last_collected <= 0 || canvas2d.GetTime() >= editor.player_mail_notice_until do return
    text: cstring =
        editor.player_mail_last_collected == 1 ? "1 LETTER COLLECTED" : fmt.ctprintf("%d LETTERS COLLECTED", editor.player_mail_last_collected)
    size := ui_measure_text(.Label, text, .25)
    bounds := canvas2d.Rectangle{(f32(width) - size.x) * .5 - 18, 22, size.x + 36, 42}
    canvas2d.DrawRectangleRounded(bounds, .18, 8, ui_theme_surface(242))
    canvas2d.DrawRectangleRoundedLinesEx(bounds, .18, 8, 1, ui_theme_border_strong())
    ui_draw_text(.Label, text, {bounds.x + 18, bounds.y + 12}, .25, ui_theme_accent())
}

player_mail_open :: proc(editor: ^Editor) {
    if editor == nil do return
    menu_scene_push(editor, .Mail)
    editor.player_mail_focus = 0
    ids: [player_mail.LETTER_COUNT]player_mail.Letter_ID
    if player_mail_received_ids(editor, &ids) > 0 do _ = player_mail.mark_read(&editor.player_mail, ids[0])
    game_input.reset_menu_repeat(&editor.runtime_input)
    set_pointer_locked(false)
    _ = sdl.ShowCursor()
}

player_mail_received_ids :: proc(editor: ^Editor, ids: ^[player_mail.LETTER_COUNT]player_mail.Letter_ID) -> int {
    if editor == nil || ids == nil do return 0
    count := 0
    for id in player_mail.Letter_ID {
        if editor.player_mail.received[int(id)] {
            ids[count] = id
            count += 1
        }
    }
    return count
}

player_mail_process_input :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil do return
    ids: [player_mail.LETTER_COUNT]player_mail.Letter_ID
    count := player_mail_received_ids(editor, &ids)
    _, vertical := game_input.menu_steps(
        &editor.runtime_input,
        gamepad_axis(.Left_X),
        gamepad_axis(.Left_Y),
        delta_seconds,
    )
    if canvas2d.IsKeyPressed(.UP) || gamepad_pressed(.Dpad_Up) do vertical = -1
    if canvas2d.IsKeyPressed(.DOWN) || gamepad_pressed(.Dpad_Down) do vertical = 1
    if count > 0 && vertical != 0 {
        editor.player_mail_focus = clamp(editor.player_mail_focus + vertical, 0, count - 1)
        _ = player_mail.mark_read(&editor.player_mail, ids[editor.player_mail_focus])
    }
    if count > 0 && input_action_pressed(.Menu_Accept) {
        _ = player_mail.mark_read(&editor.player_mail, ids[editor.player_mail_focus])
    }
}

player_mail_draw :: proc(editor: ^Editor, width, height: i32) {
    panel := canvas2d.Rectangle{40, 32, f32(width) - 80, f32(height) - 64}
    list := canvas2d.Rectangle{panel.x + 24, panel.y + 100, min(f32(330), panel.width * .36), panel.height - 142}
    detail := canvas2d.Rectangle {
        list.x + list.width + 18,
        list.y,
        panel.x + panel.width - list.x - list.width - 42,
        list.height,
    }
    canvas2d.DrawRectangle(0, 0, width, height, ui_theme_scrim(210))
    canvas2d.DrawRectangleRounded(panel, .025, 12, ui_theme_surface())
    canvas2d.DrawRectangleRoundedLinesEx(panel, .025, 12, 2, ui_theme_border_strong())
    ui_draw_text(.Data, "COURIER'S", {panel.x + 28, panel.y + 20}, .45, ui_theme_accent())
    ui_draw_text(.Display, "LETTERS", {panel.x + 28, panel.y + 44}, .55, ui_theme_text())
    unread := player_mail.unread_count(&editor.player_mail)
    ui_draw_text(
        .Data,
        fmt.ctprintf("%d UNREAD", unread),
        {panel.x + panel.width - 112, panel.y + 58},
        .3,
        ui_theme_accent(),
    )

    ids: [player_mail.LETTER_COUNT]player_mail.Letter_ID
    count := player_mail_received_ids(editor, &ids)
    if count == 0 {
        ui_draw_text(
            .Body,
            "No letters collected yet. Check at either island post office.",
            {list.x + 12, list.y + 18},
            .2,
            ui_theme_text_muted(),
        )
    } else {
        editor.player_mail_focus = clamp(editor.player_mail_focus, 0, count - 1)
        for id, row in ids[:count] {
            definition := player_mail.definition(id)
            bounds := canvas2d.Rectangle {
                list.x,
                list.y + f32(row) * PLAYER_MAIL_ROW_HEIGHT,
                list.width,
                PLAYER_MAIL_ROW_HEIGHT - 6,
            }
            focused := row == editor.player_mail_focus
            style := ui_theme_control_style(focused ? .Focused : .Resting)
            canvas2d.DrawRectangleRounded(bounds, .1, 8, style.fill)
            canvas2d.DrawRectangleRoundedLinesEx(bounds, .1, 8, style.border_width, style.border)
            marker: cstring = editor.player_mail.read[int(id)] ? "" : "NEW"
            ui_draw_text(.Label, fmt.ctprintf("%s", definition.subject), {bounds.x + 12, bounds.y + 9}, .2, style.text)
            ui_draw_text(
                .Data,
                fmt.ctprintf("%s  %s", definition.sender, marker),
                {bounds.x + 12, bounds.y + 34},
                .14,
                ui_theme_text_muted(),
            )
        }
        selected := ids[editor.player_mail_focus]
        definition := player_mail.definition(selected)
        canvas2d.DrawRectangleRounded(detail, .025, 10, ui_theme_surface_elevated())
        canvas2d.DrawRectangleRoundedLinesEx(detail, .025, 10, 1, ui_theme_border())
        ui_draw_text(
            .Data,
            fmt.ctprintf("FROM %s", definition.sender),
            {detail.x + 24, detail.y + 24},
            .25,
            ui_theme_accent(),
        )
        dialogue_draw_wrapped(
            definition.subject,
            {detail.x + 24, detail.y + 52, detail.width - 48, 70},
            28,
            1,
            34,
            ui_theme_text(),
        )
        dialogue_draw_wrapped(
            definition.body,
            {detail.x + 24, detail.y + 128, detail.width - 48, detail.height - 154},
            20,
            .7,
            28,
            ui_theme_text(),
        )
    }
    hint: cstring = "ESC closes  |  ARROWS select"
    size := ui_measure_text(.Data, hint, .2)
    ui_draw_text(
        .Data,
        hint,
        {panel.x + panel.width - size.x - 28, panel.y + panel.height - 18},
        .2,
        ui_theme_text_muted(),
    )
}
