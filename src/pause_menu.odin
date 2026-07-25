package main

import third_person "../packages/third_person"
import "core:fmt"
import rl "zelda_engine:canvas2d"

Pause_Screen :: enum {
    Closed,
    Pause,
    Options,
}

Gameplay_Options :: struct {
    look_sensitivity: f32,
    invert_look_y:    bool,
    show_hud:         bool,
    crunchiness:      Crunchiness,
}

Crunchiness :: enum {
    P240,
    P480,
    P720,
    Full,
}

gameplay_options_default :: proc() -> Gameplay_Options {
    return {look_sensitivity = .012, invert_look_y = false, show_hud = true, crunchiness = .P480}
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
    return editor != nil && editor.pause_screen != .Closed
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

OPTIONS_CONTENT_HEIGHT :: f32(354)

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
    return {panel.x + 44, viewport.y + 298 - scroll_y, panel.width - 88, 46}
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
    hovered := rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds)
    fill := rl.Color{31, 36, 43, 255}
    border := rl.Color{73, 82, 94, 255}
    text := rl.Color{230, 235, 240, 255}
    if hovered {
        fill = {45, 53, 62, 255}
        border = {115, 129, 143, 255}
    }
    if accent {
        fill = hovered ? rl.Color{42, 112, 111, 255} : rl.Color{33, 91, 92, 255}
        border = {86, 211, 201, 255}
        text = {246, 255, 254, 255}
    }
    if focused {
        border = {105, 231, 220, 255}
        if !accent do fill = {38, 54, 60, 255}
    }
    rl.DrawRectangleRounded(bounds, .12, 8, fill)
    rl.DrawRectangleRoundedLinesEx(bounds, .12, 8, accent || focused ? 2 : 1, border)
    size := ui_measure_text(.Label, label, .5)
    ui_draw_text(
        .Label,
        label,
        {bounds.x + (bounds.width - size.x) * .5, bounds.y + (bounds.height - size.y) * .5 + 2},
        .5,
        text,
    )
}

pause_menu_open :: proc(editor: ^Editor) {
    if editor == nil || !editor.in_map do return
    editor.pause_screen = .Pause
    editor.map_time = f32(rl.GetTime())
    set_pointer_locked(false)
}

pause_menu_resume :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.pause_screen = .Closed
    editor.map_time = f32(rl.GetTime())
    set_pointer_locked(editor.in_map)
}

pause_menu_return_to_editor :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.pause_screen = .Closed
    editor.in_map = false
    third_person.camera_set_active(&editor.cameras, .Player)
    editor.map_time = f32(rl.GetTime())
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    set_pointer_locked(false)
}

options_menu_focus_bounds :: proc(panel: rl.Rectangle, focus: int, scroll_y: f32) -> rl.Rectangle {
    if focus >= 0 && focus <= 3 do return options_menu_row_bounds(panel, focus, scroll_y)
    if focus == 4 do return options_menu_restore_bounds(panel, scroll_y)
    return options_menu_back_bounds(panel)
}

options_menu_reveal_focus :: proc(editor: ^Editor, panel: rl.Rectangle) {
    if editor == nil || editor.options_focus < 0 || editor.options_focus > 4 do return
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
        editor.gameplay_options.invert_look_y = direction > 0
    case 2:
        editor.gameplay_options.show_hud = direction > 0
    case 3:
        selected := clamp(int(editor.gameplay_options.crunchiness) + direction, 0, 3)
        editor.gameplay_options.crunchiness = Crunchiness(selected)
        crunchiness_apply(editor.gameplay_options.crunchiness)
    }
}

options_menu_process_input :: proc(editor: ^Editor, width, height: i32) {
    panel := pause_menu_panel(width, height, true)
    mouse := rl.GetMousePosition()
    pressed := rl.IsMouseButtonPressed(.LEFT)
    viewport := options_menu_viewport(panel)
    maximum_scroll := options_menu_max_scroll(panel)
    editor.options_scroll_y = clamp(editor.options_scroll_y, 0, maximum_scroll)

    focus_direction := 0
    if rl.IsKeyPressed(.UP) || (rl.GamepadAvailable() && rl.IsGamepadButtonPressed(.Dpad_Up)) {
        focus_direction -= 1
    }
    if rl.IsKeyPressed(.DOWN) || (rl.GamepadAvailable() && rl.IsGamepadButtonPressed(.Dpad_Down)) {
        focus_direction += 1
    }
    if focus_direction != 0 {
        editor.options_focus = clamp(editor.options_focus + focus_direction, 0, 5)
        options_menu_reveal_focus(editor, panel)
    }

    adjust_direction := 0
    if rl.IsKeyPressed(.LEFT) || (rl.GamepadAvailable() && rl.IsGamepadButtonPressed(.Dpad_Left)) {
        adjust_direction -= 1
    }
    if rl.IsKeyPressed(.RIGHT) || (rl.GamepadAvailable() && rl.IsGamepadButtonPressed(.Dpad_Right)) {
        adjust_direction += 1
    }
    if adjust_direction != 0 do options_menu_adjust_focused(editor, adjust_direction)

    confirm := rl.IsKeyPressed(.ENTER) || (rl.GamepadAvailable() && rl.IsGamepadButtonPressed(.South))
    if confirm {
        switch editor.options_focus {
        case 1:
            editor.gameplay_options.invert_look_y = !editor.gameplay_options.invert_look_y
        case 2:
            editor.gameplay_options.show_hud = !editor.gameplay_options.show_hud
        case 4:
            editor.gameplay_options = gameplay_options_default()
            crunchiness_apply(editor.gameplay_options.crunchiness)
        case 5:
            editor.pause_screen = .Pause
            editor.options_scroll_dragging = false
        }
        if editor.options_focus != 0 && editor.options_focus != 3 do return
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
    if content_hovered {
        for index in 0 ..< 4 {
            if rl.CheckCollisionPointRec(mouse, options_menu_row_bounds(panel, index, scroll_y)) {
                editor.options_focus = index
            }
        }
        if rl.CheckCollisionPointRec(mouse, options_menu_restore_bounds(panel, scroll_y)) do editor.options_focus = 4
    }
    if rl.CheckCollisionPointRec(mouse, options_menu_back_bounds(panel)) do editor.options_focus = 5

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
        editor.gameplay_options.invert_look_y = !editor.gameplay_options.invert_look_y
        return
    }
    if content_hovered && pressed && rl.CheckCollisionPointRec(mouse, options_menu_row_bounds(panel, 2, scroll_y)) {
        editor.options_focus = 2
        editor.gameplay_options.show_hud = !editor.gameplay_options.show_hud
        return
    }
    crunchiness := options_menu_row_bounds(panel, 3, scroll_y)
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
                editor.options_focus = 3
                editor.gameplay_options.crunchiness = Crunchiness(index)
                crunchiness_apply(editor.gameplay_options.crunchiness)
                return
            }
        }
    }
    if content_hovered && pressed && rl.CheckCollisionPointRec(mouse, options_menu_restore_bounds(panel, scroll_y)) {
        editor.options_focus = 4
        editor.gameplay_options = gameplay_options_default()
        crunchiness_apply(editor.gameplay_options.crunchiness)
        return
    }
    if pressed && rl.CheckCollisionPointRec(mouse, options_menu_back_bounds(panel)) {
        editor.options_focus = 5
        editor.pause_screen = .Pause
        editor.options_scroll_dragging = false
    }
}

pause_menu_process_input :: proc(editor: ^Editor, width, height: i32) {
    if editor == nil || !editor.in_map do return

    if editor.pause_screen == .Closed {
        if (!shift_key_down() && rl.IsKeyPressed(.ESCAPE)) ||
           (rl.GamepadAvailable() && rl.IsGamepadButtonPressed(.Start)) {
            pause_menu_open(editor)
        }
        return
    }

    if (!shift_key_down() && rl.IsKeyPressed(.ESCAPE)) ||
       (rl.GamepadAvailable() && rl.IsGamepadButtonPressed(.East)) {
        if editor.pause_screen == .Options {
            editor.pause_screen = .Pause
        } else {
            pause_menu_resume(editor)
        }
        return
    }

    if editor.pause_screen == .Options {
        options_menu_process_input(editor, width, height)
        return
    }

    panel := pause_menu_panel(width, height, false)
    mouse := rl.GetMousePosition()
    if rl.IsKeyPressed(.ENTER) ||
       (rl.GamepadAvailable() && rl.IsGamepadButtonPressed(.South)) ||
       (rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, pause_menu_button_bounds(panel, 0))) {
        pause_menu_resume(editor)
        return
    }
    if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, pause_menu_button_bounds(panel, 1)) {
        editor.pause_screen = .Options
        return
    }
    if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, pause_menu_button_bounds(panel, 2)) {
        pause_menu_return_to_editor(editor)
        return
    }
    if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, pause_menu_button_bounds(panel, 3)) {
        editor.quit_requested = true
    }
}

pause_menu_draw_header :: proc(panel: rl.Rectangle, eyebrow, title: cstring) {
    ui_draw_text(.Data, eyebrow, {panel.x + 40, panel.y + 28}, .6, {103, 210, 201, 255})
    ui_draw_text(.Display, title, {panel.x + 40, panel.y + 57}, .5, {244, 247, 249, 255})
    rl.DrawLineEx({panel.x + 40, panel.y + 96}, {panel.x + panel.width - 40, panel.y + 96}, 1, {65, 73, 83, 255})
}

options_menu_draw_toggle :: proc(bounds: rl.Rectangle, label: cstring, enabled: bool, focused: bool = false) {
    hovered := rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds)
    fill := hovered ? rl.Color{39, 47, 55, 255} : rl.Color{29, 34, 41, 255}
    border := hovered ? rl.Color{85, 99, 112, 255} : rl.Color{48, 56, 65, 255}
    if focused {
        fill = {35, 48, 53, 255}
        border = {91, 211, 201, 255}
    }
    rl.DrawRectangleRounded(bounds, .1, 8, fill)
    rl.DrawRectangleRoundedLinesEx(bounds, .1, 8, focused ? 2 : 1, border)
    ui_draw_text(.Label, label, {bounds.x + 14, bounds.y + 18}, .4, {225, 230, 235, 255})
    toggle := rl.Rectangle{bounds.x + bounds.width - 70, bounds.y + 14, 56, 30}
    status: cstring = enabled ? "ON" : "OFF"
    status_size := ui_measure_text(.Data, status, .2)
    ui_draw_text(
        .Data,
        status,
        {toggle.x - status_size.x - 12, bounds.y + 19},
        .2,
        enabled ? rl.Color{105, 224, 214, 255} : rl.Color{130, 140, 151, 255},
    )

    // A soft underlay and outlined track keep the switch legible against both
    // the resting and hovered row colors.
    rl.DrawRectangleRounded({toggle.x, toggle.y + 2, toggle.width, toggle.height}, 1, 12, {10, 14, 18, 105})
    track_fill := enabled ? rl.Color{38, 145, 139, 255} : rl.Color{61, 70, 81, 255}
    track_border := enabled ? rl.Color{83, 218, 207, 255} : rl.Color{91, 102, 114, 255}
    rl.DrawRectangleRounded(toggle, 1, 12, track_fill)
    rl.DrawRectangleRoundedLinesEx(toggle, 1, 12, 1, track_border)

    knob_x := enabled ? toggle.x + toggle.width - 15 : toggle.x + 15
    knob_center := rl.Vector2{knob_x, toggle.y + toggle.height * .5}
    rl.DrawCircleV({knob_center.x, knob_center.y + 2}, 11, {8, 12, 15, 110})
    rl.DrawCircleV(knob_center, 11, {239, 244, 246, 255})
    rl.DrawCircleV(knob_center, 4, enabled ? rl.Color{63, 178, 169, 255} : rl.Color{151, 161, 171, 255})
}

options_menu_draw_scrollbar :: proc(panel: rl.Rectangle, scroll_y: f32) {
    track := options_menu_scrollbar_track(panel)
    thumb := options_menu_scrollbar_thumb(panel, scroll_y)
    rl.DrawRectangleRounded(track, 1, 6, {45, 53, 62, 190})
    thumb_color := options_menu_max_scroll(panel) > 0 ? rl.Color{91, 111, 123, 255} : rl.Color{64, 74, 84, 150}
    rl.DrawRectangleRounded(thumb, 1, 8, thumb_color)
}

options_menu_draw :: proc(editor: ^Editor, panel: rl.Rectangle) {
    pause_menu_draw_header(panel, "PAUSED  /  SETTINGS", "OPTIONS")
    navigation_hint: cstring = "ARROWS MOVE + CHANGE"
    navigation_size := ui_measure_text(.Data, navigation_hint, .2)
    ui_draw_text(
        .Data,
        navigation_hint,
        {panel.x + panel.width - navigation_size.x - 40, panel.y + 64},
        .2,
        {121, 133, 145, 255},
    )
    viewport := options_menu_viewport(panel)
    scroll_y := clamp(editor.options_scroll_y, 0, options_menu_max_scroll(panel))
    rl.BeginScissorMode(viewport)

    sensitivity := options_menu_row_bounds(panel, 0, scroll_y)
    sensitivity_hovered := rl.CheckCollisionPointRec(rl.GetMousePosition(), sensitivity)
    sensitivity_fill := sensitivity_hovered ? rl.Color{36, 44, 52, 255} : rl.Color{27, 32, 39, 255}
    sensitivity_border := sensitivity_hovered ? rl.Color{78, 93, 106, 255} : rl.Color{45, 53, 62, 255}
    if editor.options_focus == 0 {
        sensitivity_fill = {34, 47, 52, 255}
        sensitivity_border = {91, 211, 201, 255}
    }
    rl.DrawRectangleRounded(sensitivity, .1, 8, sensitivity_fill)
    rl.DrawRectangleRoundedLinesEx(sensitivity, .1, 8, editor.options_focus == 0 ? 2 : 1, sensitivity_border)
    ui_draw_text(.Label, "LOOK SENSITIVITY", {sensitivity.x + 14, sensitivity.y + 8}, .4, {225, 230, 235, 255})
    percent := editor.gameplay_options.look_sensitivity / .012
    value := fmt.ctprintf("%d%%", int(percent * 100 + .5))
    value_size := ui_measure_text(.Data, value, .3)
    ui_draw_text(
        .Data,
        value,
        {sensitivity.x + sensitivity.width - value_size.x - 14, sensitivity.y + 8},
        .3,
        {132, 225, 216, 255},
    )
    track := options_menu_slider_track(sensitivity)
    rl.DrawRectangleRounded(track, 1, 6, {51, 60, 69, 255})
    for tick in 0 ..= 4 {
        tick_x := track.x + track.width * f32(tick) / 4
        rl.DrawLineEx({tick_x, track.y - 2}, {tick_x, track.y + track.height + 2}, 1, {88, 99, 110, 150})
    }
    normalized := clamp((editor.gameplay_options.look_sensitivity - .004) / .020, 0, 1)
    rl.DrawRectangleRounded({track.x, track.y, track.width * normalized, track.height}, 1, 6, {52, 177, 168, 255})
    knob := rl.Vector2{track.x + track.width * normalized, track.y + track.height * .5}
    rl.DrawCircleV({knob.x, knob.y + 2}, 9, {8, 12, 15, 120})
    rl.DrawCircleV(knob, 9, {238, 244, 245, 255})
    rl.DrawCircleV(knob, 3, {58, 172, 163, 255})

    options_menu_draw_toggle(
        options_menu_row_bounds(panel, 1, scroll_y),
        "INVERT VERTICAL LOOK",
        editor.gameplay_options.invert_look_y,
        editor.options_focus == 1,
    )
    options_menu_draw_toggle(
        options_menu_row_bounds(panel, 2, scroll_y),
        "SHOW ON-SCREEN INFO",
        editor.gameplay_options.show_hud,
        editor.options_focus == 2,
    )

    crunchiness := options_menu_row_bounds(panel, 3, scroll_y)
    if editor.options_focus == 3 {
        rl.DrawRectangleRounded(
            {crunchiness.x - 4, crunchiness.y - 4, crunchiness.width + 8, crunchiness.height + 8},
            .08,
            8,
            {31, 45, 50, 220},
        )
        rl.DrawRectangleRoundedLinesEx(
            {crunchiness.x - 4, crunchiness.y - 4, crunchiness.width + 8, crunchiness.height + 8},
            .08,
            8,
            2,
            {91, 211, 201, 255},
        )
    }
    ui_draw_text(.Label, "CRUNCHINESS", {crunchiness.x, crunchiness.y + 2}, .4, {225, 230, 235, 255})
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

    pause_menu_button(
        options_menu_restore_bounds(panel, scroll_y),
        "RESTORE DEFAULTS",
        false,
        editor.options_focus == 4,
    )
    rl.EndScissorMode()
    options_menu_draw_scrollbar(panel, scroll_y)
    rl.DrawLineEx(
        {panel.x + 30, viewport.y + viewport.height + 4},
        {panel.x + panel.width - 30, viewport.y + viewport.height + 4},
        1,
        {55, 64, 73, 255},
    )
    pause_menu_button(options_menu_back_bounds(panel), "BACK", true, editor.options_focus == 5)
}

pause_menu_draw :: proc(editor: ^Editor, width, height: i32) {
    if !pause_menu_is_open(editor) do return
    rl.DrawRectangle(0, 0, width, height, {7, 11, 15, 190})

    options := editor.pause_screen == .Options
    panel := pause_menu_panel(width, height, options)
    rl.DrawRectangleRounded(panel, .035, 12, {22, 26, 32, 252})
    rl.DrawRectangleRoundedLinesEx(panel, .035, 12, 1, {78, 88, 100, 255})

    if options {
        options_menu_draw(editor, panel)
        return
    }

    pause_menu_draw_header(panel, "ADRIATIC  /  FLIGHT", "PAUSED")
    pause_menu_button(pause_menu_button_bounds(panel, 0), "RESUME", true)
    pause_menu_button(pause_menu_button_bounds(panel, 1), "OPTIONS")
    pause_menu_button(pause_menu_button_bounds(panel, 2), "RETURN TO EDITOR")
    pause_menu_button(pause_menu_button_bounds(panel, 3), "QUIT TO DESKTOP")
    hint: cstring = "ESC resumes  |  ENTER confirms"
    hint_size := ui_measure_text(.Data, hint, .3)
    ui_draw_text(
        .Data,
        hint,
        {panel.x + (panel.width - hint_size.x) * .5, panel.y + panel.height - 28},
        .3,
        {132, 143, 155, 255},
    )
}
