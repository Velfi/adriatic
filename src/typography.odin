package main

import rl "zelda_engine:canvas2d"

// Product typography is kept here instead of relying on scattered pixel-size
// literals. The canvas is rendered at a small logical resolution and then
// enlarged for the window, so sizes below UI_TYPOGRAPHY_MIN_SIZE become
// difficult to read even when the final window is large.
Ui_Typography_Role :: enum {
    Display,
    Heading,
    Body,
    Label,
    Data,
    World_Label,
}

UI_TYPOGRAPHY_MIN_SIZE :: f32(16)

@(no_instrumentation)
ui_typography_size :: #force_inline proc(role: Ui_Typography_Role) -> f32 {
    switch role {
    case .Display:
        return 24
    case .Heading:
        return 20
    case .Body, .Label, .Data, .World_Label:
        return UI_TYPOGRAPHY_MIN_SIZE
    }
    return UI_TYPOGRAPHY_MIN_SIZE
}

ui_draw_text :: proc(role: Ui_Typography_Role, text: cstring, position: rl.Vector2, spacing: f32, color: rl.Color) {
    rl.DrawTextEx(rl.Font{}, text, position, max(ui_typography_size(role), UI_TYPOGRAPHY_MIN_SIZE), spacing, color)
}

@(no_instrumentation)
ui_measure_text :: #force_inline proc(role: Ui_Typography_Role, text: cstring, spacing: f32) -> rl.Vector2 {
    return rl.MeasureTextEx(rl.Font{}, text, max(ui_typography_size(role), UI_TYPOGRAPHY_MIN_SIZE), spacing)
}
