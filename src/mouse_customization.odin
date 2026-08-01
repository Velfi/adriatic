package main

import game_input "../packages/game_input"
import "core:fmt"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

CUSTOMIZATION_COLOR_COUNT :: 6
CUSTOMIZATION_PATTERN_COUNT :: 6
CUSTOMIZATION_PATTERN_COLUMNS :: 3
CUSTOMIZATION_HEADGEAR_COUNT :: 12
CUSTOMIZATION_SCARF_CONTROL_COUNT :: 4
CUSTOMIZATION_PATTERN_START :: CUSTOMIZATION_COLOR_COUNT
CUSTOMIZATION_HEADGEAR_START :: CUSTOMIZATION_PATTERN_START + CUSTOMIZATION_PATTERN_COUNT
CUSTOMIZATION_SCARF_START :: CUSTOMIZATION_HEADGEAR_START + CUSTOMIZATION_HEADGEAR_COUNT
CUSTOMIZATION_BACK_FOCUS :: CUSTOMIZATION_SCARF_START + CUSTOMIZATION_SCARF_CONTROL_COUNT
CUSTOMIZATION_BASE_HEIGHT :: f32(620)

customization_scale_y :: proc(panel: canvas2d.Rectangle) -> f32 {
    return panel.height / CUSTOMIZATION_BASE_HEIGHT
}

customization_y :: proc(panel: canvas2d.Rectangle, offset: f32) -> f32 {
    return panel.y + offset * customization_scale_y(panel)
}

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

mouse_fur_color :: proc(value: Mouse_Fur) -> canvas2d.Color {
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
    case .Ushanka:
        return "USHANKA"
    case .Beret:
        return "BERET"
    case .Alpine_Hat:
        return "ALPINE HAT"
    case .Flat_Cap:
        return "FLAT CAP"
    case .Sailor_Hat:
        return "SAILOR HAT"
    }
    return "NONE"
}

customization_scene_panel :: proc(width, height: i32) -> canvas2d.Rectangle {
    panel_width := min(f32(1000), f32(width) - 32)
    panel_height := min(f32(620), f32(height) - 24)
    return {(f32(width) - panel_width) * .5, (f32(height) - panel_height) * .5, panel_width, panel_height}
}

customization_color_bounds :: proc(panel: canvas2d.Rectangle, index: int) -> canvas2d.Rectangle {
    controls_x := panel.x + panel.width * .41
    available := panel.width * .55
    gap := f32(8)
    card_width := (available - gap * 2) / 3
    scale_y := customization_scale_y(panel)
    return {
        controls_x + f32(index % 3) * (card_width + gap),
        customization_y(panel, 106 + f32(index / 3) * 50),
        card_width,
        42 * scale_y,
    }
}

customization_pattern_bounds :: proc(panel: canvas2d.Rectangle, index: int) -> canvas2d.Rectangle {
    controls_x := panel.x + panel.width * .41
    available := panel.width * .55
    gap := f32(8)
    card_width := (available - gap * f32(CUSTOMIZATION_PATTERN_COLUMNS - 1)) / f32(CUSTOMIZATION_PATTERN_COLUMNS)
    return {
        controls_x + f32(index % CUSTOMIZATION_PATTERN_COLUMNS) * (card_width + gap),
        customization_y(panel, 240 + f32(index / CUSTOMIZATION_PATTERN_COLUMNS) * 47),
        card_width,
        39 * customization_scale_y(panel),
    }
}

customization_headgear_bounds :: proc(panel: canvas2d.Rectangle, index: int) -> canvas2d.Rectangle {
    controls_x := panel.x + panel.width * .41
    available := panel.width * .55
    gap := f32(8)
    card_width := (available - gap * 3) / 4
    scale_y := customization_scale_y(panel)
    return {
        controls_x + f32(index % 4) * (card_width + gap),
        customization_y(panel, 356 + f32(index / 4) * 44),
        card_width,
        38 * scale_y,
    }
}

customization_scarf_bounds :: proc(panel: canvas2d.Rectangle, index: int) -> canvas2d.Rectangle {
    controls_x := panel.x + panel.width * .41
    available := panel.width * .55
    gap := f32(8)
    card_width := (available - gap * 3) / 4
    return {
        controls_x + f32(index) * (card_width + gap),
        customization_y(panel, 516),
        card_width,
        38 * customization_scale_y(panel),
    }
}

customization_color_track_bounds :: proc(bounds: canvas2d.Rectangle) -> canvas2d.Rectangle {
    return {bounds.x + 42, bounds.y + 16, max(bounds.width - 82, f32(12)), 10}
}

customization_back_bounds :: proc(panel: canvas2d.Rectangle) -> canvas2d.Rectangle {
    return {
        panel.x + panel.width * .41,
        customization_y(panel, 566),
        panel.width * .55,
        38 * customization_scale_y(panel),
    }
}

customization_preview_bounds :: proc(panel: canvas2d.Rectangle) -> canvas2d.Rectangle {
    return {
        panel.x,
        customization_y(panel, 96),
        panel.width * .39,
        panel.height - 96 * customization_scale_y(panel),
    }
}

customization_rgb_to_hsv :: proc(color: canvas2d.Color) -> (hue, saturation, lightness: f32) {
    r, g, b := f32(color.r) / 255, f32(color.g) / 255, f32(color.b) / 255
    high := max(r, max(g, b))
    low := min(r, min(g, b))
    delta := high - low
    lightness = (high + low) * .5
    if delta <= .0001 do return 0, 0, lightness
    saturation = delta / (1 - math.abs(2 * lightness - 1))
    if high == r {
        hue = (g - b) / delta
        if hue < 0 do hue += 6
    } else if high == g {
        hue = (b - r) / delta + 2
    } else {
        hue = (r - g) / delta + 4
    }
    return hue / 6, saturation, lightness
}

customization_hue_channel :: proc(p, q, t: f32) -> f32 {
    wrapped := t
    if wrapped < 0 do wrapped += 1
    if wrapped > 1 do wrapped -= 1
    if wrapped < 1.0 / 6 do return p + (q - p) * 6 * wrapped
    if wrapped < .5 do return q
    if wrapped < 2.0 / 3 do return p + (q - p) * (2.0 / 3 - wrapped) * 6
    return p
}

customization_hsl_to_color :: proc(hue, saturation, lightness: f32) -> canvas2d.Color {
    if saturation <= .0001 {
        value := u8(clamp(lightness, 0, 1) * 255)
        return {value, value, value, 255}
    }
    q := lightness < .5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
    p := 2 * lightness - q
    return {
        u8(clamp(customization_hue_channel(p, q, hue + 1.0 / 3), 0, 1) * 255),
        u8(clamp(customization_hue_channel(p, q, hue), 0, 1) * 255),
        u8(clamp(customization_hue_channel(p, q, hue - 1.0 / 3), 0, 1) * 255),
        255,
    }
}

customization_set_scarf_component :: proc(editor: ^Editor, component: int, normalized: f32) {
    hue, saturation, lightness := customization_rgb_to_hsv(editor.mouse_scarf_color)
    switch component {
    case 0:
        hue = clamp(normalized, 0, 1)
    case 1:
        saturation = clamp(normalized, 0, 1)
    case:
        lightness = clamp(normalized, .12, .88)
    }
    editor.mouse_scarf_color = customization_hsl_to_color(hue, saturation, lightness)
    editor.mouse_scarf_enabled = true
}

customization_adjust_scarf_component :: proc(editor: ^Editor, component, direction: int, fine: bool = false) {
    hue, saturation, lightness := customization_rgb_to_hsv(editor.mouse_scarf_color)
    current := component == 0 ? hue : (component == 1 ? saturation : lightness)
    step := fine ? f32(.01) : f32(.04)
    next := current + f32(direction) * step
    if component == 0 {
        if next < 0 do next += 1
        if next > 1 do next -= 1
    }
    customization_set_scarf_component(editor, component, next)
    _ = mouse_preference_save(editor)
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
        customization_adjust_scarf_component(editor, component, 1)
        changed = false
    } else if focus == CUSTOMIZATION_BACK_FOCUS {
        menu_scene_set(editor, .Options)
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
            headgear_index := focus - CUSTOMIZATION_HEADGEAR_START
            if headgear_index < 4 {
                focus =
                    CUSTOMIZATION_PATTERN_START +
                    CUSTOMIZATION_PATTERN_COLUMNS +
                    min(headgear_index, CUSTOMIZATION_PATTERN_COLUMNS - 1)
            } else {
                focus -= 4
            }
        } else if focus < CUSTOMIZATION_BACK_FOCUS {
            scarf_column := focus - CUSTOMIZATION_SCARF_START
            last_row_start := (CUSTOMIZATION_HEADGEAR_COUNT - 1) / 4 * 4
            focus = CUSTOMIZATION_HEADGEAR_START + min(last_row_start + scarf_column, CUSTOMIZATION_HEADGEAR_COUNT - 1)
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
            if headgear_index + 4 < CUSTOMIZATION_HEADGEAR_COUNT {
                focus += 4
            } else {
                focus = CUSTOMIZATION_SCARF_START + min(headgear_index % 4, 3)
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
    preview := customization_preview_bounds(panel)
    navigation_x := gamepad_axis(.Left_X)
    navigation_y := gamepad_axis(.Left_Y)
    if canvas2d.IsKeyDown(.LEFT) || gamepad_down(.Dpad_Left) do navigation_x = -1
    if canvas2d.IsKeyDown(.RIGHT) || gamepad_down(.Dpad_Right) do navigation_x = 1
    if canvas2d.IsKeyDown(.UP) || gamepad_down(.Dpad_Up) do navigation_y = -1
    if canvas2d.IsKeyDown(.DOWN) || gamepad_down(.Dpad_Down) do navigation_y = 1
    stick_x, stick_y := game_input.menu_steps(
        &editor.runtime_input,
        navigation_x,
        navigation_y,
        delta_seconds,
    )
    horizontal := stick_x
    vertical := stick_y
    if canvas2d.IsKeyPressed(.TAB) {
        direction := shift_key_down() ? -1 : 1
        editor.customization_focus = (editor.customization_focus + direction + CUSTOMIZATION_BACK_FOCUS + 1) %
                                     (CUSTOMIZATION_BACK_FOCUS + 1)
        horizontal, vertical = 0, 0
        game_input.reset_menu_repeat(&editor.runtime_input)
    }
    if editor.customization_focus >= CUSTOMIZATION_SCARF_START &&
       editor.customization_focus < CUSTOMIZATION_BACK_FOCUS {
        shoulder_step := 0
        if gamepad_pressed(.Left_Shoulder) do shoulder_step = -1
        if gamepad_pressed(.Right_Shoulder) do shoulder_step = 1
        if shoulder_step != 0 {
            scarf_index := editor.customization_focus - CUSTOMIZATION_SCARF_START
            scarf_index = (scarf_index + shoulder_step + CUSTOMIZATION_SCARF_CONTROL_COUNT) %
                          CUSTOMIZATION_SCARF_CONTROL_COUNT
            editor.customization_focus = CUSTOMIZATION_SCARF_START + scarf_index
            horizontal, vertical = 0, 0
            game_input.reset_menu_repeat(&editor.runtime_input)
        }
    }
    if horizontal != 0 &&
       editor.customization_focus > CUSTOMIZATION_SCARF_START &&
       editor.customization_focus < CUSTOMIZATION_BACK_FOCUS {
        component := editor.customization_focus - CUSTOMIZATION_SCARF_START - 1
        customization_adjust_scarf_component(editor, component, horizontal, shift_key_down())
        horizontal = 0
    }
    if horizontal != 0 || vertical != 0 do customization_move_focus(editor, horizontal, vertical)

    mouse := canvas2d.GetMousePosition()
    mouse_delta := canvas2d.GetMouseDelta()
    mouse_active := canvas2d.IsMouseButtonPressed(.LEFT) || math.abs(mouse_delta.x) > .01 || math.abs(mouse_delta.y) > .01
    if canvas2d.IsMouseButtonPressed(.LEFT) && canvas2d.CheckCollisionPointRec(mouse, preview) {
        editor.customization_preview_dragging = true
        editor.customization_preview_drag_x = mouse.x
    }
    if editor.customization_preview_dragging && canvas2d.IsMouseButtonDown(.LEFT) {
        editor.customization_preview_yaw += (mouse.x - editor.customization_preview_drag_x) * .012
        editor.customization_preview_drag_x = mouse.x
    }
    if canvas2d.IsMouseButtonReleased(.LEFT) {
        editor.customization_preview_dragging = false
        editor.customization_slider_drag = 0
    }
    pointer_focus := -1
    if mouse_active {
        for index in 0 ..< CUSTOMIZATION_COLOR_COUNT {
            if canvas2d.CheckCollisionPointRec(mouse, customization_color_bounds(panel, index)) {
                pointer_focus = index
            }
        }
        for index in 0 ..< CUSTOMIZATION_PATTERN_COUNT {
            if canvas2d.CheckCollisionPointRec(mouse, customization_pattern_bounds(panel, index)) {
                pointer_focus = CUSTOMIZATION_PATTERN_START + index
            }
        }
        for index in 0 ..< CUSTOMIZATION_HEADGEAR_COUNT {
            if canvas2d.CheckCollisionPointRec(mouse, customization_headgear_bounds(panel, index)) {
                pointer_focus = CUSTOMIZATION_HEADGEAR_START + index
            }
        }
        for index in 0 ..< CUSTOMIZATION_SCARF_CONTROL_COUNT {
            if canvas2d.CheckCollisionPointRec(mouse, customization_scarf_bounds(panel, index)) {
                pointer_focus = CUSTOMIZATION_SCARF_START + index
            }
        }
        if canvas2d.CheckCollisionPointRec(mouse, customization_back_bounds(panel)) {
            pointer_focus = CUSTOMIZATION_BACK_FOCUS
        }
        if pointer_focus >= 0 do editor.customization_focus = pointer_focus
    }
    if input_action_pressed(.Menu_Accept) do customization_activate(editor, editor.customization_focus)
    if canvas2d.IsMouseButtonPressed(.LEFT) && pointer_focus >= 0 {
        if pointer_focus > CUSTOMIZATION_SCARF_START && pointer_focus < CUSTOMIZATION_BACK_FOCUS {
            component := pointer_focus - CUSTOMIZATION_SCARF_START - 1
            editor.customization_slider_drag = component + 1
        } else {
            customization_activate(editor, pointer_focus)
        }
    }
    if editor.customization_slider_drag > 0 && canvas2d.IsMouseButtonDown(.LEFT) {
        component := editor.customization_slider_drag - 1
        bounds := customization_scarf_bounds(panel, component + 1)
        track := customization_color_track_bounds(bounds)
        normalized := clamp((mouse.x - track.x) / track.width, 0, 1)
        customization_set_scarf_component(editor, component, normalized)
        _ = mouse_preference_save(editor)
    }
}

customization_card :: proc(bounds: canvas2d.Rectangle, label: cstring, selected, focused: bool, swatch: canvas2d.Color = {}) {
    hovered := pause_menu_pointer_enabled && canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), bounds)
    state := UI_Control_State.Resting
    if hovered do state = .Hovered
    if focused do state = .Focused
    if selected do state = .Selected
    style := ui_theme_control_style(state)
    canvas2d.DrawRectangleRounded(bounds, .12, 8, style.fill)
    canvas2d.DrawRectangleRoundedLinesEx(bounds, .12, 8, style.border_width, style.border)
    if selected {
        mark := canvas2d.Vector2{bounds.x + bounds.width - 11, bounds.y + 10}
        canvas2d.DrawCircleV(mark, 5, ui_theme_accent())
        canvas2d.DrawLineEx({mark.x - 2.5, mark.y}, {mark.x - .5, mark.y + 2}, 1.5, ui_theme_text_inverse())
        canvas2d.DrawLineEx({mark.x - .5, mark.y + 2}, {mark.x + 3, mark.y - 2}, 1.5, ui_theme_text_inverse())
    }
    text_x := bounds.x + 10
    if swatch.a > 0 {
        canvas2d.DrawCircleV({bounds.x + 18, bounds.y + bounds.height * .5}, 9, swatch)
        text_x = bounds.x + 34
    }
    size := ui_measure_text(.Data, label, .2)
    ui_draw_text(.Data, label, {text_x, bounds.y + (bounds.height - size.y) * .5 + 1}, .2, style.text)
}

customization_pattern_thumbnail :: proc(bounds: canvas2d.Rectangle, pattern: Mouse_Fur_Pattern) {
    center := canvas2d.Vector2{bounds.x + bounds.width - 17, bounds.y + bounds.height * .5 + 4}
    base := canvas2d.Color{168, 119, 82, 255}
    pale := canvas2d.Color{231, 211, 182, 255}
    canvas2d.DrawCircleV(center, 8, base)
    #partial switch pattern {
    case .Pale_Belly:
        canvas2d.DrawCircleV({center.x, center.y + 3}, 5, pale)
    case .Hooded:
        canvas2d.DrawCircleV({center.x, center.y - 3}, 5, {72, 62, 57, 255})
    case .Piebald:
        canvas2d.DrawCircleV({center.x - 2, center.y - 2}, 3.5, pale)
        canvas2d.DrawCircleV({center.x + 3, center.y + 3}, 2.5, pale)
    case .Dorsal_Stripe:
        canvas2d.DrawRectangleRounded({center.x - 1, center.y - 7, 3, 14}, .5, 3, {73, 58, 49, 255})
    case .Masked:
        canvas2d.DrawRectangleRounded({center.x - 7, center.y - 3, 14, 6}, .5, 4, {67, 57, 52, 255})
    case:
    }
}

customization_headgear_thumbnail :: proc(bounds: canvas2d.Rectangle, accessory: Mouse_Accessory) {
    center := canvas2d.Vector2{bounds.x + bounds.width - 15, bounds.y + bounds.height * .5 + 3}
    color := canvas2d.Color{208, 177, 111, 255}
    #partial switch accessory {
    case .None:
        canvas2d.DrawLineEx({center.x - 5, center.y - 5}, {center.x + 5, center.y + 5}, 2, {91, 102, 113, 255})
    case .Goggles:
        canvas2d.DrawCircleV({center.x - 4, center.y}, 4, {132, 211, 215, 255})
        canvas2d.DrawCircleV({center.x - 4, center.y}, 2.5, {24, 33, 39, 255})
        canvas2d.DrawCircleV({center.x + 4, center.y}, 4, {132, 211, 215, 255})
        canvas2d.DrawCircleV({center.x + 4, center.y}, 2.5, {24, 33, 39, 255})
    case .Flower:
        for angle in 0 ..< 5 {
            radians := f32(angle) * math.PI * .4
            canvas2d.DrawCircleV(
                {center.x + math.cos(radians) * 5, center.y + math.sin(radians) * 5},
                3,
                {226, 126, 145, 255},
            )
        }
        canvas2d.DrawCircleV(center, 3, {247, 211, 83, 255})
    case .Acorn_Cap:
        canvas2d.DrawCircleV({center.x, center.y - 2}, 7, {126, 83, 42, 255})
        canvas2d.DrawLineEx({center.x, center.y - 8}, {center.x + 3, center.y - 12}, 2, {76, 55, 34, 255})
    case .Bottle_Cap:
        canvas2d.DrawRectangleRounded({center.x - 8, center.y - 5, 16, 10}, .2, 4, {187, 70, 61, 255})
        for ridge in -2 ..= 2 do canvas2d.DrawLineEx({center.x + f32(ridge) * 3, center.y - 4}, {center.x + f32(ridge) * 3, center.y + 4}, 1, {236, 132, 111, 255})
    case .Paper_Boat:
        canvas2d.DrawRectangleRounded({center.x - 9, center.y, 18, 6}, .45, 5, {226, 221, 201, 255})
        canvas2d.DrawLineEx({center.x - 7, center.y}, {center.x, center.y - 8}, 3, {226, 221, 201, 255})
        canvas2d.DrawLineEx({center.x, center.y - 8}, {center.x + 7, center.y}, 3, {226, 221, 201, 255})
    case .Chef_Hat:
        canvas2d.DrawCircleV({center.x - 5, center.y - 4}, 5, {238, 236, 220, 255})
        canvas2d.DrawCircleV({center.x, center.y - 6}, 6, {238, 236, 220, 255})
        canvas2d.DrawCircleV({center.x + 5, center.y - 4}, 5, {238, 236, 220, 255})
        canvas2d.DrawRectangleRounded({center.x - 8, center.y - 3, 16, 9}, .15, 3, {238, 236, 220, 255})
    case .Ushanka:
        canvas2d.DrawRectangleRounded({center.x - 8, center.y - 7, 16, 12}, .35, 5, {106, 76, 57, 255})
        canvas2d.DrawCircleV({center.x - 8, center.y + 2}, 4, {126, 91, 66, 255})
        canvas2d.DrawCircleV({center.x + 8, center.y + 2}, 4, {126, 91, 66, 255})
    case .Beret:
        canvas2d.DrawCircleV({center.x, center.y - 2}, 7, {155, 66, 73, 255})
        canvas2d.DrawRectangleRounded({center.x - 9, center.y - 2, 18, 5}, .5, 4, {155, 66, 73, 255})
        canvas2d.DrawLineEx({center.x + 1, center.y - 7}, {center.x + 3, center.y - 10}, 1.5, {155, 66, 73, 255})
    case .Alpine_Hat:
        canvas2d.DrawRectangleRounded({center.x - 8, center.y, 16, 6}, .45, 5, {74, 124, 80, 255})
        canvas2d.DrawLineEx({center.x - 6, center.y}, {center.x + 2, center.y - 9}, 5, {74, 124, 80, 255})
        canvas2d.DrawLineEx({center.x + 2, center.y - 9}, {center.x + 7, center.y}, 5, {74, 124, 80, 255})
        canvas2d.DrawLineEx({center.x + 3, center.y - 5}, {center.x + 8, center.y - 11}, 1.5, {222, 91, 79, 255})
    case .Flat_Cap:
        canvas2d.DrawRectangleRounded({center.x - 8, center.y - 2, 16, 8}, .35, 5, color)
        canvas2d.DrawCircleV({center.x - 1, center.y - 4}, 7, {113, 126, 104, 255})
        canvas2d.DrawRectangleRounded({center.x - 9, center.y - 4, 18, 5}, .5, 4, {113, 126, 104, 255})
    case .Sailor_Hat:
        canvas2d.DrawRectangleRounded({center.x - 9, center.y - 1, 18, 6}, .5, 4, {241, 239, 222, 255})
        canvas2d.DrawRectangleRounded({center.x - 8, center.y - 2, 16, 2}, .5, 2, {38, 88, 145, 255})
        canvas2d.DrawRectangleRounded({center.x - 7, center.y - 5, 14, 2}, .5, 2, {38, 88, 145, 255})
        canvas2d.DrawCircleV({center.x, center.y - 7}, 6, {241, 239, 222, 255})
        canvas2d.DrawCircleV({center.x, center.y - 12}, 1.5, {38, 88, 145, 255})
    }
}

customization_color_component :: proc(
    bounds: canvas2d.Rectangle,
    label: cstring,
    value: f32,
    focused: bool,
    color: canvas2d.Color,
    enabled: bool,
) {
    customization_card(bounds, label, false, focused)
    value_label := fmt.ctprintf("%d", int(clamp(value, 0, 1) * 100 + .5))
    value_size := ui_measure_text(.Data, value_label, .1)
    value_x := bounds.x + bounds.width - value_size.x - 8
    track := customization_color_track_bounds(bounds)
    opacity := enabled ? u8(255) : u8(95)
    canvas2d.DrawRectangleRounded(track, .45, 6, ui_theme_scrim(opacity))
    fill := track
    fill.width *= clamp(value, 0, 1)
    shade := canvas2d.Color{color.r, color.g, color.b, opacity}
    if fill.width > 0 do canvas2d.DrawRectangleRounded(fill, .45, 6, shade)
    handle_x := track.x + track.width * clamp(value, 0, 1)
    canvas2d.DrawCircleV({handle_x, track.y + track.height * .5}, 5, ui_theme_surface_elevated(opacity))
    ui_draw_text(
        .Data,
        value_label,
        {value_x, bounds.y + (bounds.height - value_size.y) * .5 + 1},
        .1,
        ui_theme_text_muted(opacity),
    )
    if !enabled {
        canvas2d.DrawRectangleRounded(bounds, .12, 8, ui_theme_scrim(86))
        if focused do canvas2d.DrawRectangleRoundedLinesEx(bounds, .12, 8, 2, ui_theme_focus())
    }
}

customization_draw_3d_preview :: proc(_: ^Editor, bounds: canvas2d.Rectangle) {
    // The world pass renders the gameplay mouse beneath this translucent frame.
    // Keeping the UI layer to chrome preserves the model's real
    // depth, lighting, animation, fur markings, and headgear geometry.
    canvas2d.DrawRectangleRounded(bounds, .035, 12, ui_theme_scrim(42))
}

customization_scene_draw :: proc(editor: ^Editor, width, height: i32) {
    panel := customization_scene_panel(width, height)
    header_panel := canvas2d.Rectangle{panel.x, panel.y, panel.width, 108 * customization_scale_y(panel)}
    controls_panel := canvas2d.Rectangle {
        panel.x + panel.width * .39,
        customization_y(panel, 96),
        panel.width * .61,
        panel.height - 96 * customization_scale_y(panel),
    }
    canvas2d.DrawRectangleRounded(header_panel, .025, 12, ui_theme_surface())
    canvas2d.DrawRectangleRounded(controls_panel, .02, 10, ui_theme_surface())
    canvas2d.DrawRectangleRoundedLinesEx(panel, .025, 12, 1, ui_theme_border())
    pause_menu_draw_header(panel, "", "CUSTOMIZE MOUSE")
    slider_focused := editor.customization_focus > CUSTOMIZATION_SCARF_START &&
                      editor.customization_focus < CUSTOMIZATION_BACK_FOCUS
    hint: cstring = slider_focused ? "LEFT/RIGHT ADJUST  /  SHIFT = FINE  /  TAB NEXT" :
                                     "SAVES AUTOMATICALLY  /  ARROWS + ENTER"
    if controller_prompt_active(editor) {
        hint = slider_focused ? "LEFT/RIGHT ADJUST  /  LB/RB NEXT" :
                                "SAVES AUTOMATICALLY  /  D-PAD + A"
    }
    hint_size := ui_measure_text(.Data, hint, .2)
    ui_draw_text(
        .Data,
        hint,
        {panel.x + panel.width - hint_size.x - 40, customization_y(panel, 42)},
        .2,
        ui_theme_text_muted(),
    )
    customization_draw_3d_preview(editor, customization_preview_bounds(panel))

    controls_x := panel.x + panel.width * .41
    ui_draw_text(.Label, "FUR COLOR", {controls_x, customization_y(panel, 84)}, .4, ui_theme_text())
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

    ui_draw_text(.Label, "FUR PATTERN", {controls_x, customization_y(panel, 218)}, .4, ui_theme_text())
    for index in 0 ..< CUSTOMIZATION_PATTERN_COUNT {
        value := Mouse_Fur_Pattern(index)
        customization_card(
            customization_pattern_bounds(panel, index),
            mouse_pattern_label(value),
            editor.mouse_pattern == value,
            editor.customization_focus == CUSTOMIZATION_PATTERN_START + index,
        )
        customization_pattern_thumbnail(customization_pattern_bounds(panel, index), value)
    }

    ui_draw_text(.Label, "HEADGEAR", {controls_x, customization_y(panel, 334)}, .4, ui_theme_text())
    for index in 0 ..< CUSTOMIZATION_HEADGEAR_COUNT {
        value := Mouse_Accessory(index)
        customization_card(
            customization_headgear_bounds(panel, index),
            mouse_headgear_label(value),
            editor.mouse_headgear == value,
            editor.customization_focus == CUSTOMIZATION_HEADGEAR_START + index,
        )
        customization_headgear_thumbnail(customization_headgear_bounds(panel, index), value)
    }

    ui_draw_text(.Label, "SCARF", {controls_x, customization_y(panel, 494)}, .4, ui_theme_text())
    scarf_swatch := editor.mouse_scarf_enabled ? editor.mouse_scarf_color : canvas2d.Color{}
    customization_card(
        customization_scarf_bounds(panel, 0),
        editor.mouse_scarf_enabled ? "SCARF ON" : "SCARF OFF",
        editor.mouse_scarf_enabled,
        editor.customization_focus == CUSTOMIZATION_SCARF_START,
        scarf_swatch,
    )
    hue, saturation, lightness := customization_rgb_to_hsv(editor.mouse_scarf_color)
    customization_color_component(
        customization_scarf_bounds(panel, 1),
        "HUE",
        hue,
        editor.customization_focus == CUSTOMIZATION_SCARF_START + 1,
        customization_hsl_to_color(hue, 1, .5),
        editor.mouse_scarf_enabled,
    )
    customization_color_component(
        customization_scarf_bounds(panel, 2),
        "VIVID",
        saturation,
        editor.customization_focus == CUSTOMIZATION_SCARF_START + 2,
        customization_hsl_to_color(hue, saturation, .5),
        editor.mouse_scarf_enabled,
    )
    customization_color_component(
        customization_scarf_bounds(panel, 3),
        "LIGHT",
        lightness,
        editor.customization_focus == CUSTOMIZATION_SCARF_START + 3,
        customization_hsl_to_color(hue, saturation, lightness),
        editor.mouse_scarf_enabled,
    )

    pause_menu_button(
        customization_back_bounds(panel),
        "BACK",
        true,
        editor.customization_focus == CUSTOMIZATION_BACK_FOCUS,
    )
}
