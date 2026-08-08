package main

import canvas2d "zelda_engine:canvas2d"

lab_ui_button_pressed :: proc(bounds: canvas2d.Rectangle) -> bool {
    return canvas2d.IsMouseButtonPressed(.LEFT) && canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), bounds)
}

lab_ui_draw_button :: proc(bounds: canvas2d.Rectangle, label: cstring, active := false) {
    hovered := canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), bounds)
    fill :=
        active ? canvas2d.Color{61, 76, 62, 255} : hovered ? canvas2d.Color{53, 64, 57, 255} : canvas2d.Color{36, 45, 41, 248}
    canvas2d.DrawRectangleRounded(bounds, .16, 6, fill)
    canvas2d.DrawRectangleRoundedLinesEx(bounds, .16, 6, 1, {118, 145, 119, 255})
    size := canvas2d.MeasureTextEx(canvas2d.Font{}, label, 11, 1)
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        label,
        {bounds.x + (bounds.width - size.x) * .5, bounds.y + 7},
        11,
        1,
        {232, 224, 189, 255},
    )
}

lab_ui_stepper_minus_bounds :: proc(bounds: canvas2d.Rectangle) -> canvas2d.Rectangle {
    return {bounds.x, bounds.y, 28, bounds.height}
}

lab_ui_stepper_plus_bounds :: proc(bounds: canvas2d.Rectangle) -> canvas2d.Rectangle {
    return {bounds.x + bounds.width - 28, bounds.y, 28, bounds.height}
}

lab_ui_stepper_delta :: proc(bounds: canvas2d.Rectangle) -> int {
    if lab_ui_button_pressed(lab_ui_stepper_minus_bounds(bounds)) do return -1
    if lab_ui_button_pressed(lab_ui_stepper_plus_bounds(bounds)) do return 1
    return 0
}

lab_ui_draw_stepper :: proc(bounds: canvas2d.Rectangle, value: cstring) {
    minus := lab_ui_stepper_minus_bounds(bounds)
    plus := lab_ui_stepper_plus_bounds(bounds)
    lab_ui_draw_button(minus, "-")
    lab_ui_draw_button(plus, "+")
    canvas2d.DrawRectangleRec({bounds.x + 28, bounds.y, bounds.width - 56, bounds.height}, {27, 38, 34, 248})
    canvas2d.DrawRectangleRoundedLinesEx(bounds, .16, 6, 1, {118, 145, 119, 255})
    size := canvas2d.MeasureTextEx(canvas2d.Font{}, value, 11, 1)
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        value,
        {bounds.x + (bounds.width - size.x) * .5, bounds.y + 7},
        11,
        1,
        {208, 221, 202, 255},
    )
}
