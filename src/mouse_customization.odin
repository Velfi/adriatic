package main

import game_input "../packages/game_input"
import "core:math"
import rl "zelda_engine:canvas2d"

CUSTOMIZATION_COLOR_COUNT :: 6
CUSTOMIZATION_PATTERN_COUNT :: 6
CUSTOMIZATION_PATTERN_COLUMNS :: 3
CUSTOMIZATION_HEADGEAR_COUNT :: 7
CUSTOMIZATION_SCARF_CONTROL_COUNT :: 4
CUSTOMIZATION_PATTERN_START :: CUSTOMIZATION_COLOR_COUNT
CUSTOMIZATION_HEADGEAR_START :: CUSTOMIZATION_PATTERN_START + CUSTOMIZATION_PATTERN_COUNT
CUSTOMIZATION_SCARF_START :: CUSTOMIZATION_HEADGEAR_START + CUSTOMIZATION_HEADGEAR_COUNT
CUSTOMIZATION_BACK_FOCUS :: CUSTOMIZATION_SCARF_START + CUSTOMIZATION_SCARF_CONTROL_COUNT

mouse_fur_label :: proc(value: Mouse_Fur) -> cstring {
    switch value {
    case .Chestnut:
        return "CHESTNUT"
    case .Silver:
        return "SILVER"
    case .Cream:
        return "CREAM"
    case .Soot:
        return "SOOT"
    case .Russet:
        return "RUSSET"
    case .White:
        return "WHITE"
    }
    return "CHESTNUT"
}

mouse_fur_color :: proc(value: Mouse_Fur) -> rl.Color {
    switch value {
    case .Chestnut:
        return {132, 107, 84, 255}
    case .Silver:
        return {139, 145, 151, 255}
    case .Cream:
        return {213, 190, 151, 255}
    case .Soot:
        return {59, 63, 69, 255}
    case .Russet:
        return {169, 91, 55, 255}
    case .White:
        return {226, 224, 216, 255}
    }
    return {132, 107, 84, 255}
}

mouse_pattern_label :: proc(value: Mouse_Fur_Pattern) -> cstring {
    switch value {
    case .Solid:
        return "SOLID"
    case .Pale_Belly:
        return "PALE BELLY"
    case .Hooded:
        return "HOODED"
    case .Piebald:
        return "PIEBALD"
    case .Dorsal_Stripe:
        return "DORSAL STRIPE"
    case .Masked:
        return "MASKED"
    }
    return "SOLID"
}

mouse_headgear_label :: proc(value: Mouse_Accessory) -> cstring {
    switch value {
    case .None:
        return "NONE"
    case .Goggles:
        return "GOGGLES"
    case .Flower:
        return "FLOWER"
    case .Acorn_Cap:
        return "ACORN CAP"
    case .Bottle_Cap:
        return "BOTTLE CAP"
    case .Paper_Boat:
        return "PAPER BOAT"
    case .Chef_Hat:
        return "CHEF HAT"
    }
    return "NONE"
}

customization_scene_panel :: proc(width, height: i32) -> rl.Rectangle {
    panel_width := min(f32(1000), f32(width) - 32)
    panel_height := min(f32(620), f32(height) - 24)
    return {(f32(width) - panel_width) * .5, (f32(height) - panel_height) * .5, panel_width, panel_height}
}

customization_color_bounds :: proc(panel: rl.Rectangle, index: int) -> rl.Rectangle {
    controls_x := panel.x + panel.width * .41
    available := panel.width * .55
    gap := f32(8)
    card_width := (available - gap * 2) / 3
    return {controls_x + f32(index % 3) * (card_width + gap), panel.y + 112 + f32(index / 3) * 52, card_width, 44}
}

customization_pattern_bounds :: proc(panel: rl.Rectangle, index: int) -> rl.Rectangle {
    controls_x := panel.x + panel.width * .41
    available := panel.width * .55
    gap := f32(8)
    card_width := (available - gap * f32(CUSTOMIZATION_PATTERN_COLUMNS - 1)) / f32(CUSTOMIZATION_PATTERN_COLUMNS)
    return {
        controls_x + f32(index % CUSTOMIZATION_PATTERN_COLUMNS) * (card_width + gap),
        panel.y + 252 + f32(index / CUSTOMIZATION_PATTERN_COLUMNS) * 50,
        card_width,
        42,
    }
}

customization_headgear_bounds :: proc(panel: rl.Rectangle, index: int) -> rl.Rectangle {
    controls_x := panel.x + panel.width * .41
    available := panel.width * .55
    gap := f32(8)
    card_width := (available - gap * 3) / 4
    return {controls_x + f32(index % 4) * (card_width + gap), panel.y + 356 + f32(index / 4) * 50, card_width, 42}
}

customization_scarf_bounds :: proc(panel: rl.Rectangle, index: int) -> rl.Rectangle {
    controls_x := panel.x + panel.width * .41
    available := panel.width * .55
    gap := f32(8)
    card_width := (available - gap * 3) / 4
    return {controls_x + f32(index) * (card_width + gap), panel.y + 482, card_width, 42}
}

customization_back_bounds :: proc(panel: rl.Rectangle) -> rl.Rectangle {
    return {panel.x + panel.width * .41, panel.y + panel.height - 58, panel.width * .55, 42}
}

customization_activate :: proc(editor: ^Editor, focus: int) {
    changed := true
    if focus >= 0 && focus < CUSTOMIZATION_COLOR_COUNT {
        editor.mouse_fur = Mouse_Fur(focus)
    } else if focus >= CUSTOMIZATION_PATTERN_START && focus < CUSTOMIZATION_HEADGEAR_START {
        editor.mouse_pattern = Mouse_Fur_Pattern(focus - CUSTOMIZATION_PATTERN_START)
    } else if focus >= CUSTOMIZATION_HEADGEAR_START && focus < CUSTOMIZATION_SCARF_START {
        editor.mouse_headgear = Mouse_Accessory(focus - CUSTOMIZATION_HEADGEAR_START)
    } else if focus == CUSTOMIZATION_SCARF_START {
        editor.mouse_scarf_enabled = !editor.mouse_scarf_enabled
    } else if focus > CUSTOMIZATION_SCARF_START && focus < CUSTOMIZATION_BACK_FOCUS {
        component := focus - CUSTOMIZATION_SCARF_START - 1
        value :=
            component == 0 ? editor.mouse_scarf_color.r : component == 1 ? editor.mouse_scarf_color.g : editor.mouse_scarf_color.b
        next := u8((int(value) + 32) % 256)
        if component == 0 {
            editor.mouse_scarf_color.r = next
        } else if component == 1 {
            editor.mouse_scarf_color.g = next
        } else {
            editor.mouse_scarf_color.b = next
        }
        editor.mouse_scarf_enabled = true
    } else if focus == CUSTOMIZATION_BACK_FOCUS {
        editor.pause_screen = .Options
        changed = false
    } else {
        changed = false
    }
    if changed do _ = mouse_preference_save(editor)
}

customization_move_focus :: proc(editor: ^Editor, horizontal, vertical: int) {
    focus := editor.customization_focus
    if horizontal != 0 {
        if focus < CUSTOMIZATION_COLOR_COUNT {
            row_start := (focus / 3) * 3
            focus = row_start + clamp(focus + horizontal - row_start, 0, 2)
        } else if focus < CUSTOMIZATION_HEADGEAR_START {
            pattern_index := focus - CUSTOMIZATION_PATTERN_START
            row_start :=
                CUSTOMIZATION_PATTERN_START +
                (pattern_index / CUSTOMIZATION_PATTERN_COLUMNS) * CUSTOMIZATION_PATTERN_COLUMNS
            row_end := min(row_start + CUSTOMIZATION_PATTERN_COLUMNS - 1, CUSTOMIZATION_HEADGEAR_START - 1)
            focus = clamp(focus + horizontal, row_start, row_end)
        } else if focus < CUSTOMIZATION_SCARF_START {
            row_start := CUSTOMIZATION_HEADGEAR_START + ((focus - CUSTOMIZATION_HEADGEAR_START) / 4) * 4
            row_end := min(row_start + 3, CUSTOMIZATION_SCARF_START - 1)
            focus = clamp(focus + horizontal, row_start, row_end)
        } else if focus < CUSTOMIZATION_BACK_FOCUS {
            focus = clamp(focus + horizontal, CUSTOMIZATION_SCARF_START, CUSTOMIZATION_BACK_FOCUS - 1)
        }
    }
    if vertical < 0 {
        if focus < 3 {
            focus = CUSTOMIZATION_BACK_FOCUS
        } else if focus < CUSTOMIZATION_COLOR_COUNT {
            focus -= 3
        } else if focus < CUSTOMIZATION_HEADGEAR_START {
            pattern_index := focus - CUSTOMIZATION_PATTERN_START
            if pattern_index < CUSTOMIZATION_PATTERN_COLUMNS {
                focus = 3 + pattern_index
            } else {
                focus -= CUSTOMIZATION_PATTERN_COLUMNS
            }
        } else if focus < CUSTOMIZATION_HEADGEAR_START + 4 {
            focus =
                CUSTOMIZATION_PATTERN_START +
                CUSTOMIZATION_PATTERN_COLUMNS +
                min(focus - CUSTOMIZATION_HEADGEAR_START, CUSTOMIZATION_PATTERN_COLUMNS - 1)
        } else if focus < CUSTOMIZATION_SCARF_START {
            focus -= 4
        } else if focus < CUSTOMIZATION_BACK_FOCUS {
            scarf_column := focus - CUSTOMIZATION_SCARF_START
            if scarf_column < 3 {
                focus = CUSTOMIZATION_HEADGEAR_START + 4 + scarf_column
            } else {
                focus = CUSTOMIZATION_HEADGEAR_START + 3
            }
        } else {
            focus = CUSTOMIZATION_SCARF_START
        }
    } else if vertical > 0 {
        if focus < 3 {
            focus += 3
        } else if focus < CUSTOMIZATION_COLOR_COUNT {
            focus = CUSTOMIZATION_PATTERN_START + min(focus - 3, CUSTOMIZATION_PATTERN_COLUMNS - 1)
        } else if focus < CUSTOMIZATION_HEADGEAR_START {
            pattern_index := focus - CUSTOMIZATION_PATTERN_START
            if pattern_index < CUSTOMIZATION_PATTERN_COLUMNS {
                focus += CUSTOMIZATION_PATTERN_COLUMNS
            } else {
                focus = CUSTOMIZATION_HEADGEAR_START + min(pattern_index - CUSTOMIZATION_PATTERN_COLUMNS, 3)
            }
        } else if focus < CUSTOMIZATION_SCARF_START {
            headgear_index := focus - CUSTOMIZATION_HEADGEAR_START
            if headgear_index < 3 {
                focus += 4
            } else if headgear_index == 3 {
                focus = CUSTOMIZATION_SCARF_START + 3
            } else {
                focus = CUSTOMIZATION_SCARF_START + min(headgear_index - 4, 2)
            }
        } else if focus < CUSTOMIZATION_BACK_FOCUS {
            focus = CUSTOMIZATION_BACK_FOCUS
        } else {
            focus = CUSTOMIZATION_BACK_FOCUS
        }
    }
    editor.customization_focus = clamp(focus, 0, CUSTOMIZATION_BACK_FOCUS)
}

customization_scene_process_input :: proc(editor: ^Editor, width, height: i32, delta_seconds: f32) {
    panel := customization_scene_panel(width, height)
    stick_x, stick_y := game_input.menu_steps(
        &editor.runtime_input,
        gamepad_axis(.Left_X),
        gamepad_axis(.Left_Y),
        delta_seconds,
    )
    horizontal := 0
    vertical := 0
    if rl.IsKeyPressed(.LEFT) || gamepad_pressed(.Dpad_Left) do horizontal = -1
    if rl.IsKeyPressed(.RIGHT) || gamepad_pressed(.Dpad_Right) do horizontal = 1
    if rl.IsKeyPressed(.UP) || gamepad_pressed(.Dpad_Up) do vertical = -1
    if rl.IsKeyPressed(.DOWN) || gamepad_pressed(.Dpad_Down) do vertical = 1
    if horizontal == 0 do horizontal = stick_x
    if vertical == 0 do vertical = stick_y
    if horizontal != 0 || vertical != 0 do customization_move_focus(editor, horizontal, vertical)

    mouse := rl.GetMousePosition()
    mouse_delta := rl.GetMouseDelta()
    mouse_active := rl.IsMouseButtonPressed(.LEFT) || math.abs(mouse_delta.x) > .01 || math.abs(mouse_delta.y) > .01
    pointer_focus := -1
    if mouse_active {
        for index in 0 ..< CUSTOMIZATION_COLOR_COUNT {
            if rl.CheckCollisionPointRec(mouse, customization_color_bounds(panel, index)) {
                pointer_focus = index
            }
        }
        for index in 0 ..< CUSTOMIZATION_PATTERN_COUNT {
            if rl.CheckCollisionPointRec(mouse, customization_pattern_bounds(panel, index)) {
                pointer_focus = CUSTOMIZATION_PATTERN_START + index
            }
        }
        for index in 0 ..< CUSTOMIZATION_HEADGEAR_COUNT {
            if rl.CheckCollisionPointRec(mouse, customization_headgear_bounds(panel, index)) {
                pointer_focus = CUSTOMIZATION_HEADGEAR_START + index
            }
        }
        for index in 0 ..< CUSTOMIZATION_SCARF_CONTROL_COUNT {
            if rl.CheckCollisionPointRec(mouse, customization_scarf_bounds(panel, index)) {
                pointer_focus = CUSTOMIZATION_SCARF_START + index
            }
        }
        if rl.CheckCollisionPointRec(mouse, customization_back_bounds(panel)) {
            pointer_focus = CUSTOMIZATION_BACK_FOCUS
        }
        if pointer_focus >= 0 do editor.customization_focus = pointer_focus
    }
    if input_action_pressed(.Menu_Accept) do customization_activate(editor, editor.customization_focus)
    if rl.IsMouseButtonPressed(.LEFT) && pointer_focus >= 0 {
        if pointer_focus > CUSTOMIZATION_SCARF_START && pointer_focus < CUSTOMIZATION_BACK_FOCUS {
            component := pointer_focus - CUSTOMIZATION_SCARF_START - 1
            bounds := customization_scarf_bounds(panel, component + 1)
            track_x := bounds.x + 42
            normalized := clamp((mouse.x - track_x) / max(bounds.width - 52, f32(1)), 0, 1)
            value := u8(normalized * 255)
            if component == 0 {
                editor.mouse_scarf_color.r = value
            } else if component == 1 {
                editor.mouse_scarf_color.g = value
            } else {
                editor.mouse_scarf_color.b = value
            }
            editor.mouse_scarf_enabled = true
            _ = mouse_preference_save(editor)
        } else {
            customization_activate(editor, pointer_focus)
        }
    }
}

customization_card :: proc(bounds: rl.Rectangle, label: cstring, selected, focused: bool, swatch: rl.Color = {}) {
    hovered := pause_menu_pointer_enabled && rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds)
    fill: rl.Color = hovered ? rl.Color{40, 49, 58, 255} : rl.Color{29, 35, 42, 255}
    border: rl.Color = selected ? rl.Color{81, 205, 194, 255} : rl.Color{55, 65, 75, 255}
    if focused {
        fill = {37, 55, 59, 255}
        border = {118, 238, 226, 255}
    }
    rl.DrawRectangleRounded(bounds, .12, 8, fill)
    rl.DrawRectangleRoundedLinesEx(bounds, .12, 8, focused || selected ? 2 : 1, border)
    text_x := bounds.x + 10
    if swatch.a > 0 {
        rl.DrawCircleV({bounds.x + 18, bounds.y + bounds.height * .5}, 9, swatch)
        text_x = bounds.x + 34
    }
    size := ui_measure_text(.Data, label, .2)
    ui_draw_text(.Data, label, {text_x, bounds.y + (bounds.height - size.y) * .5 + 1}, .2, {229, 234, 238, 255})
}

customization_color_component :: proc(
    bounds: rl.Rectangle,
    label: cstring,
    value: u8,
    focused: bool,
    color: rl.Color,
) {
    customization_card(bounds, label, false, focused)
    track := rl.Rectangle{bounds.x + 42, bounds.y + 16, bounds.width - 52, 10}
    rl.DrawRectangleRounded(track, .45, 6, {12, 17, 21, 255})
    fill := track
    fill.width *= f32(value) / 255
    if fill.width > 0 do rl.DrawRectangleRounded(fill, .45, 6, color)
}

customization_draw_3d_preview :: proc(_: ^Editor, bounds: rl.Rectangle) {
    // The world pass renders the gameplay mouse beneath this translucent frame.
    // Keeping the UI layer to chrome preserves the model's real
    // depth, lighting, animation, fur markings, and headgear geometry.
    rl.DrawRectangleRounded(bounds, .035, 12, {8, 15, 20, 42})
    rl.DrawRectangleRoundedLinesEx(bounds, .035, 12, 2, {83, 151, 151, 235})
}

customization_scene_draw :: proc(editor: ^Editor, width, height: i32) {
    panel := customization_scene_panel(width, height)
    header_panel := rl.Rectangle{panel.x, panel.y, panel.width, 108}
    controls_panel := rl.Rectangle{panel.x + panel.width * .39, panel.y + 100, panel.width * .61, panel.height - 100}
    rl.DrawRectangleRounded(header_panel, .025, 12, {22, 26, 32, 252})
    rl.DrawRectangleRounded(controls_panel, .02, 10, {22, 26, 32, 252})
    rl.DrawRectangleRoundedLinesEx(panel, .025, 12, 1, {78, 88, 100, 255})
    pause_menu_draw_header(panel, "", "CUSTOMIZE MOUSE")
    customization_draw_3d_preview(editor, {panel.x + 28, panel.y + 112, panel.width * .35, panel.height - 142})

    controls_x := panel.x + panel.width * .41
    ui_draw_text(.Label, "FUR COLOR", {controls_x, panel.y + 92}, .4, {225, 230, 235, 255})
    for index in 0 ..< CUSTOMIZATION_COLOR_COUNT {
        value := Mouse_Fur(index)
        customization_card(
            customization_color_bounds(panel, index),
            mouse_fur_label(value),
            editor.mouse_fur == value,
            editor.customization_focus == index,
            mouse_fur_color(value),
        )
    }

    ui_draw_text(.Label, "FUR PATTERN", {controls_x, panel.y + 226}, .4, {225, 230, 235, 255})
    for index in 0 ..< CUSTOMIZATION_PATTERN_COUNT {
        value := Mouse_Fur_Pattern(index)
        customization_card(
            customization_pattern_bounds(panel, index),
            mouse_pattern_label(value),
            editor.mouse_pattern == value,
            editor.customization_focus == CUSTOMIZATION_PATTERN_START + index,
        )
    }

    ui_draw_text(.Label, "HEADGEAR", {controls_x, panel.y + 330}, .4, {225, 230, 235, 255})
    for index in 0 ..< CUSTOMIZATION_HEADGEAR_COUNT {
        value := Mouse_Accessory(index)
        customization_card(
            customization_headgear_bounds(panel, index),
            mouse_headgear_label(value),
            editor.mouse_headgear == value,
            editor.customization_focus == CUSTOMIZATION_HEADGEAR_START + index,
        )
    }

    ui_draw_text(.Label, "SCARF", {controls_x, panel.y + 456}, .4, {225, 230, 235, 255})
    customization_card(
        customization_scarf_bounds(panel, 0),
        editor.mouse_scarf_enabled ? "ON" : "OFF",
        editor.mouse_scarf_enabled,
        editor.customization_focus == CUSTOMIZATION_SCARF_START,
        editor.mouse_scarf_color,
    )
    customization_color_component(
        customization_scarf_bounds(panel, 1),
        "R",
        editor.mouse_scarf_color.r,
        editor.customization_focus == CUSTOMIZATION_SCARF_START + 1,
        {235, 65, 65, 255},
    )
    customization_color_component(
        customization_scarf_bounds(panel, 2),
        "G",
        editor.mouse_scarf_color.g,
        editor.customization_focus == CUSTOMIZATION_SCARF_START + 2,
        {65, 218, 104, 255},
    )
    customization_color_component(
        customization_scarf_bounds(panel, 3),
        "B",
        editor.mouse_scarf_color.b,
        editor.customization_focus == CUSTOMIZATION_SCARF_START + 3,
        {74, 128, 239, 255},
    )

    pause_menu_button(
        customization_back_bounds(panel),
        "DONE",
        true,
        editor.customization_focus == CUSTOMIZATION_BACK_FOCUS,
    )
}
