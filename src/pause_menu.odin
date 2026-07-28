package main

import game_input "../packages/game_input"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import sdl "vendor:sdl3"
import rl "zelda_engine:canvas2d"

Pause_Screen :: enum {
    Closed,
    Pause,
    Journal,
    Options,
    Customization,
}

pause_menu_pointer_enabled := true

Gameplay_Options :: struct {
    look_sensitivity:    f32,
    invert_look_x:       bool,
    invert_look_y:       bool,
    invert_flight_pitch: bool,
    show_hud:            bool,
    crunchiness:         Crunchiness,
    dither_mode:         Dither_Mode,
    hdr_exposure:        bool,
    theme_mode:          UI_Theme_Mode,
}

Crunchiness :: enum {
    P240,
    P480,
    P720,
    Full,
}

gameplay_options_default :: proc() -> Gameplay_Options {
    return {
        look_sensitivity = .012,
        invert_look_x = true,
        invert_look_y = false,
        invert_flight_pitch = false,
        show_hud = true,
        crunchiness = .P480,
        dither_mode = .Off,
        hdr_exposure = true,
        theme_mode = .Light,
    }
}

crunchiness_label :: proc(value: Crunchiness) -> cstring {
    switch value {
    case .P240:
        return "240P"
    case .P480:
        return "480P"
    case .P720:
        return "720P"
    case .Full:
        return "FULL"
    }
    return "480P"
}

crunchiness_apply :: proc(value: Crunchiness) {
    switch value {
    case .P240:
        rl.SetWorldRenderSize(426, 240)
    case .P480:
        rl.SetWorldRenderSize(854, 480)
    case .P720:
        rl.SetWorldRenderSize(1280, 720)
    case .Full:
        rl.SetWorldRenderSize(0, 0)
    }
}

pause_menu_is_open :: proc(editor: ^Editor) -> bool {
    return editor != nil && (editor.console.open || editor.main_menu_active || editor.pause_screen != .Closed)
}

pause_menu_panel :: proc(width, height: i32, options: bool) -> rl.Rectangle {
    panel_width := min(f32(500), f32(width) - 40)
    panel_height := options ? f32(560) : f32(430)
    panel_height = min(panel_height, f32(height) - 32)
    return {(f32(width) - panel_width) * .5, (f32(height) - panel_height) * .5, panel_width, panel_height}
}

pause_menu_button_bounds :: proc(panel: rl.Rectangle, row: int) -> rl.Rectangle {
    return {panel.x + 44, panel.y + 126 + f32(row) * 58, panel.width - 88, 46}
}

MAIN_MENU_BUTTON_COUNT :: 3

main_menu_panel :: proc(width, height: i32) -> rl.Rectangle {
    panel_width := min(f32(430), f32(width) - 48)
    panel_height := min(f32(360), f32(height) - 48)
    return {f32(width) - panel_width - 54, (f32(height) - panel_height) * .5, panel_width, panel_height}
}

main_menu_button_bounds :: proc(panel: rl.Rectangle, row: int) -> rl.Rectangle {
    return {panel.x + 42, panel.y + 128 + f32(row) * 62, panel.width - 84, 48}
}

OPTIONS_ROW_COUNT :: 10
OPTIONS_RESTORE_FOCUS :: OPTIONS_ROW_COUNT
OPTIONS_BACK_FOCUS :: OPTIONS_ROW_COUNT + 1
OPTIONS_CONTENT_HEIGHT :: f32(786)

options_menu_viewport :: proc(panel: rl.Rectangle) -> rl.Rectangle {
    return {panel.x + 30, panel.y + 108, panel.width - 54, max(panel.height - 178, f32(80))}
}

options_menu_max_scroll :: proc(panel: rl.Rectangle) -> f32 {
    return max(OPTIONS_CONTENT_HEIGHT - options_menu_viewport(panel).height, f32(0))
}

options_menu_row_bounds :: proc(panel: rl.Rectangle, row: int, scroll_y: f32 = 0) -> rl.Rectangle {
    viewport := options_menu_viewport(panel)
    return {panel.x + 40, viewport.y + 10 + f32(row) * 72 - scroll_y, panel.width - 80, 58}
}

options_menu_restore_bounds :: proc(panel: rl.Rectangle, scroll_y: f32 = 0) -> rl.Rectangle {
    viewport := options_menu_viewport(panel)
    return {panel.x + 44, viewport.y + 730 - scroll_y, panel.width - 88, 46}
}

options_menu_back_bounds :: proc(panel: rl.Rectangle) -> rl.Rectangle {
    return {panel.x + 44, panel.y + panel.height - 54, panel.width - 88, 46}
}

options_menu_scrollbar_track :: proc(panel: rl.Rectangle) -> rl.Rectangle {
    viewport := options_menu_viewport(panel)
    return {panel.x + panel.width - 19, viewport.y + 8, 4, max(viewport.height - 16, f32(16))}
}

options_menu_scrollbar_thumb :: proc(panel: rl.Rectangle, scroll_y: f32) -> rl.Rectangle {
    track := options_menu_scrollbar_track(panel)
    viewport := options_menu_viewport(panel)
    maximum := options_menu_max_scroll(panel)
    if maximum <= 0 do return track
    thumb_height := max(f32(36), track.height * viewport.height / OPTIONS_CONTENT_HEIGHT)
    travel := max(track.height - thumb_height, f32(0))
    return {track.x - 3, track.y + travel * clamp(scroll_y / maximum, 0, 1), track.width + 6, thumb_height}
}

options_menu_slider_track :: proc(bounds: rl.Rectangle) -> rl.Rectangle {
    return {bounds.x + 14, bounds.y + 41, bounds.width - 28, 6}
}

pause_menu_button :: proc(bounds: rl.Rectangle, label: cstring, accent: bool = false, focused: bool = false) {
    hovered := pause_menu_pointer_enabled && rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds)
    fill := ui_theme_control()
    border := ui_theme_border()
    text := ui_theme_text()
    if hovered {
        fill = ui_theme_control_hover()
        border = ui_theme_border_strong()
    }
    if accent {
        fill = hovered ? ui_theme_accent_hover() : ui_theme_accent()
        border = ui_theme_border_strong()
        text = ui_theme_text_inverse()
    }
    if focused {
        border = ui_theme_focus()
        if !accent do fill = ui_theme_surface_elevated()
    }
    rl.DrawRectangleRounded(bounds, .12, 8, fill)
    rl.DrawRectangleRoundedLinesEx(bounds, .12, 8, accent || focused ? 2 : 1, border)
    size := ui_measure_text(.Label, label, .5)
    ui_draw_text(
        .Label,
        label,
        {bounds.x + (bounds.width - size.x) * .5, bounds.y + (bounds.height - size.y) * .5 + 4},
        .5,
        text,
    )
}

pause_menu_open :: proc(editor: ^Editor) {
    if editor == nil || !editor.in_map do return
    editor.pause_screen = .Pause
    editor.pause_focus = 0
    editor.map_time = f32(rl.GetTime())
    set_pointer_locked(false)
}

pause_menu_resume :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.pause_screen = .Closed
    editor.controller_disconnect_notice = false
    editor.map_time = f32(rl.GetTime())
    set_pointer_locked(editor.in_map)
}

pause_menu_return_to_editor :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.pause_screen = .Closed
    editor.in_map = false
    game_state_reset(editor)
    third_person.camera_set_active(&editor.cameras, .Player)
    editor.map_time = f32(rl.GetTime())
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    set_pointer_locked(false)
    _ = sdl.ShowCursor()
}

options_menu_focus_bounds :: proc(panel: rl.Rectangle, focus: int, scroll_y: f32) -> rl.Rectangle {
    if focus >= 0 && focus < OPTIONS_ROW_COUNT do return options_menu_row_bounds(panel, focus, scroll_y)
    if focus == OPTIONS_RESTORE_FOCUS do return options_menu_restore_bounds(panel, scroll_y)
    return options_menu_back_bounds(panel)
}

options_menu_reveal_focus :: proc(editor: ^Editor, panel: rl.Rectangle) {
    if editor == nil || editor.options_focus < 0 || editor.options_focus > OPTIONS_RESTORE_FOCUS do return
    viewport := options_menu_viewport(panel)
    bounds := options_menu_focus_bounds(panel, editor.options_focus, editor.options_scroll_y)
    top := viewport.y + 6
    bottom := viewport.y + viewport.height - 6
    if bounds.y < top {
        editor.options_scroll_y -= top - bounds.y
    } else if bounds.y + bounds.height > bottom {
        editor.options_scroll_y += bounds.y + bounds.height - bottom
    }
    editor.options_scroll_y = clamp(editor.options_scroll_y, 0, options_menu_max_scroll(panel))
}

options_menu_adjust_focused :: proc(editor: ^Editor, direction: int) {
    if editor == nil || direction == 0 do return
    switch editor.options_focus {
    case 0:
        editor.gameplay_options.look_sensitivity = clamp(
            editor.gameplay_options.look_sensitivity + f32(direction) * .001,
            .004,
            .024,
        )
    case 1:
        editor.gameplay_options.invert_look_x = direction > 0
    case 2:
        editor.gameplay_options.invert_look_y = direction > 0
    case 3:
        editor.gameplay_options.invert_flight_pitch = direction > 0
    case 4:
        editor.gameplay_options.show_hud = direction > 0
    case 5:
        selected := clamp(int(editor.gameplay_options.crunchiness) + direction, 0, 3)
        editor.gameplay_options.crunchiness = Crunchiness(selected)
        crunchiness_apply(editor.gameplay_options.crunchiness)
    case 6:
        editor.gameplay_options.dither_mode = dither_adjust_mode(editor.gameplay_options.dither_mode, direction)
        dither_apply(editor)
    case 7:
        editor.gameplay_options.hdr_exposure = direction > 0
        dither_apply(editor)
    case 8:
        editor.gameplay_options.theme_mode = direction > 0 ? .Dark : .Light
        ui_theme_set_mode(editor.gameplay_options.theme_mode)
    }
}

options_menu_process_input :: proc(editor: ^Editor, width, height: i32, delta_seconds: f32) {
    options_before := editor.gameplay_options
    defer {
        if editor.gameplay_options != options_before do _ = mouse_preference_save(editor)
    }
    panel := pause_menu_panel(width, height, true)
    mouse := rl.GetMousePosition()
    pressed := rl.IsMouseButtonPressed(.LEFT)
    mouse_delta := rl.GetMouseDelta()
    mouse_active := pressed || math.abs(mouse_delta.x) > .01 || math.abs(mouse_delta.y) > .01
    viewport := options_menu_viewport(panel)
    maximum_scroll := options_menu_max_scroll(panel)
    editor.options_scroll_y = clamp(editor.options_scroll_y, 0, maximum_scroll)
    stick_x, stick_y := game_input.menu_steps(
        &editor.runtime_input,
        gamepad_axis(.Left_X),
        gamepad_axis(.Left_Y),
        delta_seconds,
    )

    focus_direction := 0
    if rl.IsKeyPressed(.UP) || (rl.GamepadAvailable() && rl.IsGamepadButtonPressed(.Dpad_Up)) {
        focus_direction -= 1
    }
    if rl.IsKeyPressed(.DOWN) || (rl.GamepadAvailable() && rl.IsGamepadButtonPressed(.Dpad_Down)) {
        focus_direction += 1
    }
    if focus_direction == 0 do focus_direction = stick_y
    if focus_direction != 0 {
        editor.options_focus = clamp(editor.options_focus + focus_direction, 0, OPTIONS_BACK_FOCUS)
        options_menu_reveal_focus(editor, panel)
    }

    adjust_direction := 0
    if rl.IsKeyPressed(.LEFT) || (rl.GamepadAvailable() && rl.IsGamepadButtonPressed(.Dpad_Left)) {
        adjust_direction -= 1
    }
    if rl.IsKeyPressed(.RIGHT) || (rl.GamepadAvailable() && rl.IsGamepadButtonPressed(.Dpad_Right)) {
        adjust_direction += 1
    }
    if adjust_direction == 0 do adjust_direction = stick_x
    if adjust_direction != 0 do options_menu_adjust_focused(editor, adjust_direction)

    confirm := input_action_pressed(.Menu_Accept)
    if confirm {
        switch editor.options_focus {
        case 1:
            editor.gameplay_options.invert_look_x = !editor.gameplay_options.invert_look_x
        case 2:
            editor.gameplay_options.invert_look_y = !editor.gameplay_options.invert_look_y
        case 3:
            editor.gameplay_options.invert_flight_pitch = !editor.gameplay_options.invert_flight_pitch
        case 4:
            editor.gameplay_options.show_hud = !editor.gameplay_options.show_hud
        case 6:
            editor.gameplay_options.dither_mode = dither_next_mode(editor.gameplay_options.dither_mode)
            dither_apply(editor)
        case 7:
            editor.gameplay_options.hdr_exposure = !editor.gameplay_options.hdr_exposure
            dither_apply(editor)
        case 8:
            editor.gameplay_options.theme_mode = editor.gameplay_options.theme_mode == .Dark ? .Light : .Dark
            ui_theme_set_mode(editor.gameplay_options.theme_mode)
        case OPTIONS_RESTORE_FOCUS:
            editor.gameplay_options = gameplay_options_default()
            crunchiness_apply(editor.gameplay_options.crunchiness)
            dither_apply(editor)
            ui_theme_set_mode(editor.gameplay_options.theme_mode)
        case 9:
            editor.pause_screen = .Customization
            editor.customization_focus = 0
        case OPTIONS_BACK_FOCUS:
            editor.pause_screen = editor.main_menu_active ? .Closed : .Pause
            editor.options_scroll_dragging = false
        }
        if editor.options_focus != 0 &&
           editor.options_focus != 5 &&
           editor.options_focus != 6 &&
           editor.options_focus != 7 &&
           editor.options_focus != 8 {
            return
        }
    }

    if rl.CheckCollisionPointRec(mouse, viewport) {
        wheel := rl.GetMouseWheelMove()
        if wheel != 0 do editor.options_scroll_y = clamp(editor.options_scroll_y - wheel * 42, 0, maximum_scroll)
    }

    scrollbar := options_menu_scrollbar_track(panel)
    thumb := options_menu_scrollbar_thumb(panel, editor.options_scroll_y)
    if maximum_scroll > 0 && pressed && rl.CheckCollisionPointRec(mouse, thumb) {
        editor.options_scroll_dragging = true
        editor.options_scroll_drag_offset = mouse.y - thumb.y
    } else if maximum_scroll > 0 &&
       pressed &&
       rl.CheckCollisionPointRec(mouse, {scrollbar.x - 8, scrollbar.y, 20, scrollbar.height}) {
        thumb_height := thumb.height
        travel := max(scrollbar.height - thumb_height, f32(1))
        normalized := clamp((mouse.y - scrollbar.y - thumb_height * .5) / travel, 0, 1)
        editor.options_scroll_y = normalized * maximum_scroll
        editor.options_scroll_dragging = true
        editor.options_scroll_drag_offset = thumb_height * .5
    }
    if editor.options_scroll_dragging {
        if rl.IsMouseButtonDown(.LEFT) {
            thumb = options_menu_scrollbar_thumb(panel, editor.options_scroll_y)
            travel := max(scrollbar.height - thumb.height, f32(1))
            normalized := clamp((mouse.y - editor.options_scroll_drag_offset - scrollbar.y) / travel, 0, 1)
            editor.options_scroll_y = normalized * maximum_scroll
        } else {
            editor.options_scroll_dragging = false
        }
    }

    content_hovered := rl.CheckCollisionPointRec(mouse, viewport)
    scroll_y := editor.options_scroll_y
    if content_hovered && mouse_active {
        for index in 0 ..< OPTIONS_ROW_COUNT {
            if rl.CheckCollisionPointRec(mouse, options_menu_row_bounds(panel, index, scroll_y)) {
                editor.options_focus = index
            }
        }
        if rl.CheckCollisionPointRec(mouse, options_menu_restore_bounds(panel, scroll_y)) {
            editor.options_focus = OPTIONS_RESTORE_FOCUS
        }
    }
    if mouse_active && rl.CheckCollisionPointRec(mouse, options_menu_back_bounds(panel)) {
        editor.options_focus = OPTIONS_BACK_FOCUS
    }

    sensitivity := options_menu_row_bounds(panel, 0, scroll_y)
    track := options_menu_slider_track(sensitivity)
    if content_hovered &&
       rl.IsMouseButtonDown(.LEFT) &&
       rl.CheckCollisionPointRec(mouse, {track.x - 8, track.y - 12, track.width + 16, 30}) {
        editor.options_focus = 0
        normalized := clamp((mouse.x - track.x) / track.width, 0, 1)
        editor.gameplay_options.look_sensitivity = .004 + normalized * .020
    }
    if content_hovered && pressed && rl.CheckCollisionPointRec(mouse, options_menu_row_bounds(panel, 1, scroll_y)) {
        editor.options_focus = 1
        editor.gameplay_options.invert_look_x = !editor.gameplay_options.invert_look_x
        return
    }
    if content_hovered && pressed && rl.CheckCollisionPointRec(mouse, options_menu_row_bounds(panel, 2, scroll_y)) {
        editor.options_focus = 2
        editor.gameplay_options.invert_look_y = !editor.gameplay_options.invert_look_y
        return
    }
    if content_hovered && pressed && rl.CheckCollisionPointRec(mouse, options_menu_row_bounds(panel, 3, scroll_y)) {
        editor.options_focus = 3
        editor.gameplay_options.invert_flight_pitch = !editor.gameplay_options.invert_flight_pitch
        return
    }
    if content_hovered && pressed && rl.CheckCollisionPointRec(mouse, options_menu_row_bounds(panel, 4, scroll_y)) {
        editor.options_focus = 4
        editor.gameplay_options.show_hud = !editor.gameplay_options.show_hud
        return
    }
    crunchiness := options_menu_row_bounds(panel, 5, scroll_y)
    segment_gap := f32(6)
    segment_width := (crunchiness.width - segment_gap * 3) / 4
    if content_hovered && pressed {
        for index in 0 ..< 4 {
            segment := rl.Rectangle {
                crunchiness.x + f32(index) * (segment_width + segment_gap),
                crunchiness.y + 28,
                segment_width,
                30,
            }
            if rl.CheckCollisionPointRec(mouse, segment) {
                editor.options_focus = 5
                editor.gameplay_options.crunchiness = Crunchiness(index)
                crunchiness_apply(editor.gameplay_options.crunchiness)
                return
            }
        }
    }
    if content_hovered && pressed && rl.CheckCollisionPointRec(mouse, options_menu_restore_bounds(panel, scroll_y)) {
        editor.options_focus = OPTIONS_RESTORE_FOCUS
        editor.gameplay_options = gameplay_options_default()
        crunchiness_apply(editor.gameplay_options.crunchiness)
        dither_apply(editor)
        ui_theme_set_mode(editor.gameplay_options.theme_mode)
        return
    }
    dither := options_menu_row_bounds(panel, 6, scroll_y)
    dither_gap := f32(6)
    dither_segment_width := (dither.width - dither_gap * 3) / 4
    if content_hovered && pressed {
        for index in 0 ..< 4 {
            segment := rl.Rectangle {
                dither.x + f32(index) * (dither_segment_width + dither_gap),
                dither.y + 28,
                dither_segment_width,
                30,
            }
            if rl.CheckCollisionPointRec(mouse, segment) {
                editor.options_focus = 6
                editor.gameplay_options.dither_mode = Dither_Mode(index)
                dither_apply(editor)
                return
            }
        }
    }
    if content_hovered && pressed && rl.CheckCollisionPointRec(mouse, options_menu_row_bounds(panel, 7, scroll_y)) {
        editor.options_focus = 7
        editor.gameplay_options.hdr_exposure = !editor.gameplay_options.hdr_exposure
        dither_apply(editor)
        return
    }
    if content_hovered && pressed && rl.CheckCollisionPointRec(mouse, options_menu_row_bounds(panel, 8, scroll_y)) {
        editor.options_focus = 8
        editor.gameplay_options.theme_mode = editor.gameplay_options.theme_mode == .Dark ? .Light : .Dark
        ui_theme_set_mode(editor.gameplay_options.theme_mode)
        return
    }
    if content_hovered && pressed && rl.CheckCollisionPointRec(mouse, options_menu_row_bounds(panel, 9, scroll_y)) {
        editor.options_focus = 9
        editor.pause_screen = .Customization
        editor.customization_focus = 0
        return
    }
    if pressed && rl.CheckCollisionPointRec(mouse, options_menu_back_bounds(panel)) {
        editor.options_focus = OPTIONS_BACK_FOCUS
        editor.pause_screen = editor.main_menu_active ? .Closed : .Pause
        editor.options_scroll_dragging = false
    }
}

main_menu_process_input :: proc(editor: ^Editor, width, height: i32, delta_seconds: f32) {
    if editor == nil || !editor.main_menu_active do return
    if editor.pause_screen == .Customization {
        if input_action_pressed(.Menu_Cancel) || gamepad_pressed(.Start) {
            editor.pause_screen = .Options
            return
        }
        customization_scene_process_input(editor, width, height, delta_seconds)
        return
    }
    if editor.pause_screen == .Options {
        if input_action_pressed(.Menu_Cancel) || gamepad_pressed(.Start) {
            editor.pause_screen = .Closed
            editor.options_scroll_dragging = false
            return
        }
        options_menu_process_input(editor, width, height, delta_seconds)
        return
    }

    panel := main_menu_panel(width, height)
    mouse := rl.GetMousePosition()
    mouse_delta := rl.GetMouseDelta()
    mouse_active := rl.IsMouseButtonPressed(.LEFT) || math.abs(mouse_delta.x) > .01 || math.abs(mouse_delta.y) > .01
    focus_direction := 0
    _, stick_y := game_input.menu_steps(
        &editor.runtime_input,
        gamepad_axis(.Left_X),
        gamepad_axis(.Left_Y),
        delta_seconds,
    )
    if rl.IsKeyPressed(.UP) || gamepad_pressed(.Dpad_Up) do focus_direction -= 1
    if rl.IsKeyPressed(.DOWN) || gamepad_pressed(.Dpad_Down) do focus_direction += 1
    if focus_direction == 0 do focus_direction = stick_y
    if focus_direction != 0 {
        editor.main_menu_focus = clamp(editor.main_menu_focus + focus_direction, 0, MAIN_MENU_BUTTON_COUNT - 1)
    }
    if mouse_active {
        for index in 0 ..< MAIN_MENU_BUTTON_COUNT {
            if rl.CheckCollisionPointRec(mouse, main_menu_button_bounds(panel, index)) {
                editor.main_menu_focus = index
            }
        }
    }

    activated := -1
    if input_action_pressed(.Menu_Accept) do activated = editor.main_menu_focus
    if rl.IsMouseButtonPressed(.LEFT) {
        for index in 0 ..< MAIN_MENU_BUTTON_COUNT {
            if rl.CheckCollisionPointRec(mouse, main_menu_button_bounds(panel, index)) do activated = index
        }
    }
    switch activated {
    case 0:
        editor.main_menu_active = false
        editor.pause_screen = .Closed
        editor_spawn_into_world(editor)
    case 1:
        editor.pause_screen = .Options
        editor.options_focus = 0
        editor.options_scroll_y = 0
    case 2:
        editor.quit_requested = true
    }
}

pause_menu_process_input :: proc(editor: ^Editor, width, height: i32, delta_seconds: f32) {
    if editor == nil do return
    if editor.main_menu_active {
        main_menu_process_input(editor, width, height, delta_seconds)
        return
    }
    if !editor.in_map do return
    if rl.GamepadAvailable() do editor.controller_disconnect_notice = false

    if editor.pause_screen == .Closed {
        if input_action_pressed(.Journal) {
            quest_log_open(editor)
            return
        }
        if input_action_pressed(.Pause) {
            pause_menu_open(editor)
        }
        return
    }

    if editor.pause_screen == .Journal {
        if input_action_pressed(.Journal) || input_action_pressed(.Menu_Cancel) || gamepad_pressed(.Start) {
            quest_log_close(editor)
            return
        }
        quest_log_process_input(editor, width, height, delta_seconds)
        return
    }

    if input_action_pressed(.Menu_Cancel) || gamepad_pressed(.Start) {
        if editor.pause_screen == .Customization {
            editor.pause_screen = .Options
        } else if editor.pause_screen == .Options {
            editor.pause_screen = .Pause
        } else {
            pause_menu_resume(editor)
        }
        return
    }

    if editor.pause_screen == .Options {
        options_menu_process_input(editor, width, height, delta_seconds)
        return
    }
    if editor.pause_screen == .Customization {
        customization_scene_process_input(editor, width, height, delta_seconds)
        return
    }

    panel := pause_menu_panel(width, height, false)
    mouse := rl.GetMousePosition()
    mouse_delta := rl.GetMouseDelta()
    mouse_active := rl.IsMouseButtonPressed(.LEFT) || math.abs(mouse_delta.x) > .01 || math.abs(mouse_delta.y) > .01
    focus_direction := 0
    _, stick_y := game_input.menu_steps(
        &editor.runtime_input,
        gamepad_axis(.Left_X),
        gamepad_axis(.Left_Y),
        delta_seconds,
    )
    if rl.IsKeyPressed(.UP) || gamepad_pressed(.Dpad_Up) do focus_direction -= 1
    if rl.IsKeyPressed(.DOWN) || gamepad_pressed(.Dpad_Down) do focus_direction += 1
    if focus_direction == 0 do focus_direction = stick_y
    if focus_direction != 0 {
        editor.pause_focus = clamp(editor.pause_focus + focus_direction, 0, 3)
    }
    if mouse_active {
        for index in 0 ..< 4 {
            if rl.CheckCollisionPointRec(mouse, pause_menu_button_bounds(panel, index)) {
                editor.pause_focus = index
            }
        }
    }
    activated := -1
    if input_action_pressed(.Menu_Accept) do activated = editor.pause_focus
    if rl.IsMouseButtonPressed(.LEFT) {
        for index in 0 ..< 4 {
            if rl.CheckCollisionPointRec(mouse, pause_menu_button_bounds(panel, index)) do activated = index
        }
    }
    switch activated {
    case 0:
        pause_menu_resume(editor)
    case 1:
        editor.pause_screen = .Options
        editor.options_focus = 0
    case 2:
        if editor.vehicle_paint_scene {
            if vehicle_paint_close(editor) do editor.pause_screen = .Closed
        } else if markov_wreck_return_from_flight(editor) {
            // The wreck lab owns this flight session, so return to its
            // inspection view instead of the ordinary terrain editor.
        } else {
            pause_menu_return_to_editor(editor)
        }
    case 3:
        if editor.vehicle_paint_scene {
            if vehicle_paint_discard(editor) do editor.pause_screen = .Closed
        } else {
            editor.quit_requested = true
        }
    }
}

pause_menu_draw_header :: proc(panel: rl.Rectangle, eyebrow, title: cstring) {
    if eyebrow != "" {
        ui_draw_text(.Data, eyebrow, {panel.x + 40, panel.y + 28}, .6, ui_theme_accent())
    }
    title_y := panel.y + 57
    if eyebrow == "" do title_y = panel.y + 38
    ui_draw_text(.Display, title, {panel.x + 40, title_y}, .5, ui_theme_text())
    rl.DrawLineEx({panel.x + 40, panel.y + 96}, {panel.x + panel.width - 40, panel.y + 96}, 1, ui_theme_border())
}

options_menu_draw_toggle :: proc(bounds: rl.Rectangle, label: cstring, enabled: bool, focused: bool = false) {
    hovered := pause_menu_pointer_enabled && rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds)
    fill := hovered ? ui_theme_control_hover() : ui_theme_control()
    border := hovered ? ui_theme_border_strong() : ui_theme_border()
    if focused {
        fill = ui_theme_surface_elevated()
        border = ui_theme_focus()
    }
    rl.DrawRectangleRounded(bounds, .1, 8, fill)
    rl.DrawRectangleRoundedLinesEx(bounds, .1, 8, focused ? 2 : 1, border)
    ui_draw_text(.Label, label, {bounds.x + 14, bounds.y + 18}, .4, ui_theme_text())
    toggle := rl.Rectangle{bounds.x + bounds.width - 70, bounds.y + 14, 56, 30}
    status: cstring = enabled ? "ON" : "OFF"
    status_size := ui_measure_text(.Data, status, .2)
    ui_draw_text(
        .Data,
        status,
        {toggle.x - status_size.x - 12, bounds.y + 19},
        .2,
        enabled ? ui_theme_positive() : ui_theme_disabled(),
    )

    // A soft underlay and outlined track keep the switch legible against both
    // the resting and hovered row colors.
    rl.DrawRectangleRounded({toggle.x, toggle.y + 2, toggle.width, toggle.height}, 1, 12, ui_theme_scrim(65))
    track_fill := enabled ? ui_theme_positive() : ui_theme_disabled()
    track_border := enabled ? ui_theme_border_strong() : ui_theme_border()
    rl.DrawRectangleRounded(toggle, 1, 12, track_fill)
    rl.DrawRectangleRoundedLinesEx(toggle, 1, 12, 1, track_border)

    knob_x := enabled ? toggle.x + toggle.width - 15 : toggle.x + 15
    knob_center := rl.Vector2{knob_x, toggle.y + toggle.height * .5}
    rl.DrawCircleV({knob_center.x, knob_center.y + 2}, 11, ui_theme_scrim(80))
    rl.DrawCircleV(knob_center, 11, ui_theme_surface_elevated())
    rl.DrawCircleV(knob_center, 4, enabled ? ui_theme_positive() : ui_theme_disabled())
}

options_menu_draw_scrollbar :: proc(panel: rl.Rectangle, scroll_y: f32) {
    track := options_menu_scrollbar_track(panel)
    thumb := options_menu_scrollbar_thumb(panel, scroll_y)
    rl.DrawRectangleRounded(track, 1, 6, ui_theme_control(190))
    thumb_color := options_menu_max_scroll(panel) > 0 ? ui_theme_border_strong() : ui_theme_disabled(150)
    rl.DrawRectangleRounded(thumb, 1, 8, thumb_color)
}

options_menu_draw :: proc(editor: ^Editor, panel: rl.Rectangle) {
    pause_menu_draw_header(panel, "", "OPTIONS")
    navigation_hint: cstring = "ARROWS MOVE + CHANGE"
    if controller_prompt_active(editor) do navigation_hint = "D-PAD / LS MOVE + CHANGE"
    navigation_size := ui_measure_text(.Data, navigation_hint, .2)
    ui_draw_text(
        .Data,
        navigation_hint,
        {panel.x + panel.width - navigation_size.x - 40, panel.y + 64},
        .2,
        ui_theme_text_muted(),
    )
    viewport := options_menu_viewport(panel)
    scroll_y := clamp(editor.options_scroll_y, 0, options_menu_max_scroll(panel))
    rl.BeginScissorMode(viewport)

    sensitivity := options_menu_row_bounds(panel, 0, scroll_y)
    sensitivity_hovered := pause_menu_pointer_enabled && rl.CheckCollisionPointRec(rl.GetMousePosition(), sensitivity)
    sensitivity_fill := sensitivity_hovered ? ui_theme_control_hover() : ui_theme_control()
    sensitivity_border := sensitivity_hovered ? ui_theme_border_strong() : ui_theme_border()
    if editor.options_focus == 0 {
        sensitivity_fill = ui_theme_surface_elevated()
        sensitivity_border = ui_theme_focus()
    }
    rl.DrawRectangleRounded(sensitivity, .1, 8, sensitivity_fill)
    rl.DrawRectangleRoundedLinesEx(sensitivity, .1, 8, editor.options_focus == 0 ? 2 : 1, sensitivity_border)
    ui_draw_text(.Label, "LOOK SENSITIVITY", {sensitivity.x + 14, sensitivity.y + 8}, .4, ui_theme_text())
    percent := editor.gameplay_options.look_sensitivity / .012
    value := fmt.ctprintf("%d%%", int(percent * 100 + .5))
    value_size := ui_measure_text(.Data, value, .3)
    ui_draw_text(
        .Data,
        value,
        {sensitivity.x + sensitivity.width - value_size.x - 14, sensitivity.y + 8},
        .3,
        ui_theme_accent(),
    )
    track := options_menu_slider_track(sensitivity)
    rl.DrawRectangleRounded(track, 1, 6, ui_theme_border(180))
    for tick in 0 ..= 4 {
        tick_x := track.x + track.width * f32(tick) / 4
        rl.DrawLineEx({tick_x, track.y - 2}, {tick_x, track.y + track.height + 2}, 1, ui_theme_border_strong(120))
    }
    normalized := clamp((editor.gameplay_options.look_sensitivity - .004) / .020, 0, 1)
    rl.DrawRectangleRounded({track.x, track.y, track.width * normalized, track.height}, 1, 6, ui_theme_accent())
    knob := rl.Vector2{track.x + track.width * normalized, track.y + track.height * .5}
    rl.DrawCircleV({knob.x, knob.y + 2}, 9, ui_theme_scrim(80))
    rl.DrawCircleV(knob, 9, ui_theme_surface_elevated())
    rl.DrawCircleV(knob, 3, ui_theme_accent())

    options_menu_draw_toggle(
        options_menu_row_bounds(panel, 1, scroll_y),
        "INVERT HORIZONTAL LOOK",
        editor.gameplay_options.invert_look_x,
        editor.options_focus == 1,
    )
    options_menu_draw_toggle(
        options_menu_row_bounds(panel, 2, scroll_y),
        "INVERT VERTICAL LOOK",
        editor.gameplay_options.invert_look_y,
        editor.options_focus == 2,
    )
    options_menu_draw_toggle(
        options_menu_row_bounds(panel, 3, scroll_y),
        "INVERT FLIGHT PITCH",
        editor.gameplay_options.invert_flight_pitch,
        editor.options_focus == 3,
    )
    options_menu_draw_toggle(
        options_menu_row_bounds(panel, 4, scroll_y),
        "SHOW ON-SCREEN INFO",
        editor.gameplay_options.show_hud,
        editor.options_focus == 4,
    )

    crunchiness := options_menu_row_bounds(panel, 5, scroll_y)
    if editor.options_focus == 5 {
        rl.DrawRectangleRounded(
            {crunchiness.x - 4, crunchiness.y - 4, crunchiness.width + 8, crunchiness.height + 8},
            .08,
            8,
            ui_theme_surface_elevated(220),
        )
        rl.DrawRectangleRoundedLinesEx(
            {crunchiness.x - 4, crunchiness.y - 4, crunchiness.width + 8, crunchiness.height + 8},
            .08,
            8,
            2,
            ui_theme_focus(),
        )
    }
    ui_draw_text(.Label, "CRUNCHINESS", {crunchiness.x, crunchiness.y + 2}, .4, ui_theme_text())
    segment_gap := f32(6)
    segment_width := (crunchiness.width - segment_gap * 3) / 4
    for index in 0 ..< 4 {
        value := Crunchiness(index)
        pause_menu_button(
            {crunchiness.x + f32(index) * (segment_width + segment_gap), crunchiness.y + 28, segment_width, 30},
            crunchiness_label(value),
            editor.gameplay_options.crunchiness == value,
        )
    }

    dither := options_menu_row_bounds(panel, 6, scroll_y)
    if editor.options_focus == 6 {
        rl.DrawRectangleRounded(
            {dither.x - 4, dither.y - 4, dither.width + 8, dither.height + 8},
            .08,
            8,
            ui_theme_surface_elevated(220),
        )
        rl.DrawRectangleRoundedLinesEx(
            {dither.x - 4, dither.y - 4, dither.width + 8, dither.height + 8},
            .08,
            8,
            2,
            ui_theme_focus(),
        )
    }
    ui_draw_text(.Label, "COLOR DITHER", {dither.x, dither.y + 2}, .4, ui_theme_text())
    dither_gap := f32(6)
    dither_segment_width := (dither.width - dither_gap * 3) / 4
    for index in 0 ..< 4 {
        value := Dither_Mode(index)
        pause_menu_button(
            {dither.x + f32(index) * (dither_segment_width + dither_gap), dither.y + 28, dither_segment_width, 30},
            dither_mode_label(value),
            editor.gameplay_options.dither_mode == value,
        )
    }

    options_menu_draw_toggle(
        options_menu_row_bounds(panel, 7, scroll_y),
        "HDR EXPOSURE",
        editor.gameplay_options.hdr_exposure,
        editor.options_focus == 7,
    )

    options_menu_draw_toggle(
        options_menu_row_bounds(panel, 8, scroll_y),
        "DARK MODE",
        editor.gameplay_options.theme_mode == .Dark,
        editor.options_focus == 8,
    )

    pause_menu_button(options_menu_row_bounds(panel, 9, scroll_y), "CUSTOMIZE MOUSE", true, editor.options_focus == 9)

    pause_menu_button(
        options_menu_restore_bounds(panel, scroll_y),
        "RESTORE DEFAULTS",
        false,
        editor.options_focus == OPTIONS_RESTORE_FOCUS,
    )
    rl.EndScissorMode()
    options_menu_draw_scrollbar(panel, scroll_y)
    rl.DrawLineEx(
        {panel.x + 30, viewport.y + viewport.height + 4},
        {panel.x + panel.width - 30, viewport.y + viewport.height + 4},
        1,
        ui_theme_border(),
    )
    pause_menu_button(options_menu_back_bounds(panel), "BACK", true, editor.options_focus == OPTIONS_BACK_FOCUS)
}

main_menu_draw :: proc(editor: ^Editor, width, height: i32, postcard: rl.Texture) {
    if editor == nil || !editor.main_menu_active do return
    pause_menu_pointer_enabled = !controller_prompt_active(editor)

    if postcard.ready {
        rl.DrawTexturePro(
            postcard,
            {0, 0, f32(postcard.width), f32(postcard.height)},
            {0, 0, f32(width), f32(height)},
            {255, 255, 255, 255},
        )
    } else {
        rl.ClearBackground(ui_theme_border_strong())
    }
    rl.DrawRectangle(0, 0, width, height, ui_theme_scrim(72))

    frame_width := max(i32(8), i32(min(f32(width) / 1280, f32(height) / 720) * 10))
    frame_color := ui_theme_surface_elevated()
    rl.DrawRectangle(0, 0, width, frame_width, frame_color)
    rl.DrawRectangle(0, height - frame_width, width, frame_width, frame_color)
    rl.DrawRectangle(0, 0, frame_width, height, frame_color)
    rl.DrawRectangle(width - frame_width, 0, frame_width, height, frame_color)

    if editor.pause_screen == .Customization {
        customization_scene_draw(editor, width, height)
        return
    }
    if editor.pause_screen == .Journal {
        quest_log_draw(editor, width, height)
        return
    }

    options := editor.pause_screen == .Options
    panel := options ? pause_menu_panel(width, height, true) : main_menu_panel(width, height)
    rl.DrawRectangleRounded(panel, .035, 12, ui_theme_surface(245))
    rl.DrawRectangleRoundedLinesEx(panel, .035, 12, 1, ui_theme_border_strong(220))
    if options {
        options_menu_draw(editor, panel)
        return
    }

    pause_menu_draw_header(panel, "GREETINGS FROM", "ADRIATIC")
    pause_menu_button(main_menu_button_bounds(panel, 0), "PLAY", true, editor.main_menu_focus == 0)
    pause_menu_button(main_menu_button_bounds(panel, 1), "OPTIONS", false, editor.main_menu_focus == 1)
    pause_menu_button(main_menu_button_bounds(panel, 2), "QUIT", false, editor.main_menu_focus == 2)
    hint: cstring = "ARROWS SELECT  |  ENTER CONFIRMS"
    if controller_prompt_active(editor) {
        hint = fmt.ctprintf("D-PAD / LS SELECTS  |  %s CONFIRMS", controller_face_label(editor, .South))
    }
    hint_size := ui_measure_text(.Data, hint, .2)
    ui_draw_text(
        .Data,
        hint,
        {panel.x + (panel.width - hint_size.x) * .5, panel.y + panel.height - 24},
        .2,
        ui_theme_text_muted(),
    )
}

pause_menu_draw :: proc(editor: ^Editor, width, height: i32, postcard: rl.Texture = {}) {
    if editor == nil || (!editor.main_menu_active && editor.pause_screen == .Closed) do return
    if editor.main_menu_active {
        main_menu_draw(editor, width, height, postcard)
        return
    }
    pause_menu_pointer_enabled = !controller_prompt_active(editor)
    overlay_alpha: u8 = editor.pause_screen == .Customization ? 58 : 190
    rl.DrawRectangle(0, 0, width, height, ui_theme_scrim(overlay_alpha))

    if editor.pause_screen == .Customization {
        customization_scene_draw(editor, width, height)
        return
    }
    if editor.pause_screen == .Journal {
        quest_log_draw(editor, width, height)
        return
    }

    options := editor.pause_screen == .Options
    panel := pause_menu_panel(width, height, options)
    rl.DrawRectangleRounded(panel, .035, 12, ui_theme_surface())
    rl.DrawRectangleRoundedLinesEx(panel, .035, 12, 1, ui_theme_border())

    if options {
        options_menu_draw(editor, panel)
        return
    }

    if editor.controller_disconnect_notice {
        pause_menu_draw_header(panel, "", "CONTROLLER DISCONNECTED")
    } else if editor.vehicle_paint_scene {
        pause_menu_draw_header(panel, "", "PAUSED")
    } else {
        pause_menu_draw_header(panel, "", "PAUSED")
    }
    pause_menu_button(pause_menu_button_bounds(panel, 0), "RESUME", true, editor.pause_focus == 0)
    pause_menu_button(pause_menu_button_bounds(panel, 1), "OPTIONS", false, editor.pause_focus == 1)
    return_label: cstring = "RETURN TO EDITOR"
    if editor.vehicle_paint_scene {
        return_label = "SAVE AND EXIT"
    } else if lab_scene_is_active(editor, "markov-wreck") && markov_wreck_postale_spawned {
        return_label = "RETURN TO WRECK LAB"
    }
    quit_label: cstring = editor.vehicle_paint_scene ? "DISCARD AND EXIT" : "QUIT TO DESKTOP"
    pause_menu_button(pause_menu_button_bounds(panel, 2), return_label, false, editor.pause_focus == 2)
    pause_menu_button(pause_menu_button_bounds(panel, 3), quit_label, false, editor.pause_focus == 3)
    hint: cstring
    if editor.controller_disconnect_notice {
        hint = "Reconnect the controller or continue with keyboard and mouse"
    } else if controller_prompt_active(editor) {
        hint = fmt.ctprintf(
            "D-PAD / LS selects  |  %s confirms  |  %s resumes",
            controller_face_label(editor, .South),
            controller_face_label(editor, .East),
        )
    } else {
        hint = "ESC resumes  |  ENTER confirms"
    }
    hint_size := ui_measure_text(.Data, hint, .3)
    ui_draw_text(
        .Data,
        hint,
        {panel.x + (panel.width - hint_size.x) * .5, panel.y + panel.height - 28},
        .3,
        ui_theme_text_muted(),
    )
}
