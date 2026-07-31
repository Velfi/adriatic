package main

import canvas2d "zelda_engine:canvas2d"

// Player-facing UI colors are organized by role, not by screen. The hierarchy
// moves from dark umber scrims through parchment surfaces to terracotta accents.
UI_Control_State :: enum {
    Resting,
    Hovered,
    Focused,
    Selected,
    Disabled,
}

UI_Theme_Mode :: enum {
    Light,
    Dark,
}

ui_theme_mode := UI_Theme_Mode.Light

ui_theme_set_mode :: proc(mode: UI_Theme_Mode) {
    ui_theme_mode = mode
}

ui_theme_mode_label :: proc(mode: UI_Theme_Mode) -> cstring {
    return mode == .Dark ? "DARK" : "LIGHT"
}

UI_Control_Style :: struct {
    fill:         canvas2d.Color,
    border:       canvas2d.Color,
    text:         canvas2d.Color,
    border_width: f32,
}

ui_theme_scrim :: #force_inline proc(alpha: u8 = 190) -> canvas2d.Color {
    return {38, 30, 23, alpha}
}

ui_theme_surface :: #force_inline proc(alpha: u8 = 252) -> canvas2d.Color {
    if ui_theme_mode == .Dark do return {42, 35, 29, alpha}
    return {239, 224, 195, alpha}
}

ui_theme_surface_elevated :: #force_inline proc(alpha: u8 = 255) -> canvas2d.Color {
    if ui_theme_mode == .Dark do return {55, 45, 36, alpha}
    return {249, 239, 216, alpha}
}

ui_theme_control :: #force_inline proc(alpha: u8 = 255) -> canvas2d.Color {
    if ui_theme_mode == .Dark do return {67, 54, 43, alpha}
    return {224, 202, 164, alpha}
}

ui_theme_control_hover :: #force_inline proc(alpha: u8 = 255) -> canvas2d.Color {
    if ui_theme_mode == .Dark do return {82, 66, 51, alpha}
    return {235, 216, 181, alpha}
}

ui_theme_border :: #force_inline proc(alpha: u8 = 255) -> canvas2d.Color {
    if ui_theme_mode == .Dark do return {142, 111, 75, alpha}
    return {177, 143, 98, alpha}
}

ui_theme_border_strong :: #force_inline proc(alpha: u8 = 255) -> canvas2d.Color {
    if ui_theme_mode == .Dark do return {212, 177, 119, alpha}
    return {112, 79, 51, alpha}
}

ui_theme_text :: #force_inline proc(alpha: u8 = 255) -> canvas2d.Color {
    if ui_theme_mode == .Dark do return {245, 232, 204, alpha}
    return {55, 43, 32, alpha}
}

ui_theme_text_muted :: #force_inline proc(alpha: u8 = 255) -> canvas2d.Color {
    if ui_theme_mode == .Dark do return {190, 168, 134, alpha}
    return {105, 82, 59, alpha}
}

ui_theme_text_inverse :: #force_inline proc(alpha: u8 = 255) -> canvas2d.Color {
    return {255, 247, 228, alpha}
}

ui_theme_accent :: #force_inline proc(alpha: u8 = 255) -> canvas2d.Color {
    if ui_theme_mode == .Dark do return {205, 105, 72, alpha}
    return {174, 77, 50, alpha}
}

ui_theme_accent_hover :: #force_inline proc(alpha: u8 = 255) -> canvas2d.Color {
    if ui_theme_mode == .Dark do return {225, 126, 88, alpha}
    return {196, 96, 62, alpha}
}

ui_theme_focus :: #force_inline proc(alpha: u8 = 255) -> canvas2d.Color {
    if ui_theme_mode == .Dark do return {224, 185, 112, alpha}
    return {121, 87, 47, alpha}
}

ui_theme_positive :: #force_inline proc(alpha: u8 = 255) -> canvas2d.Color {
    if ui_theme_mode == .Dark do return {130, 158, 103, alpha}
    return {82, 111, 68, alpha}
}

ui_theme_disabled :: #force_inline proc(alpha: u8 = 255) -> canvas2d.Color {
    if ui_theme_mode == .Dark do return {119, 106, 89, alpha}
    return {139, 123, 101, alpha}
}

// Interactive components share this state ladder so focus, selection, hover,
// and disabled meaning stay consistent across menus, dialogue, and HUD chrome.
ui_theme_control_style :: #force_inline proc(state: UI_Control_State) -> UI_Control_Style {
    switch state {
    case .Hovered:
        return {ui_theme_control_hover(), ui_theme_border_strong(), ui_theme_text(), 1}
    case .Focused:
        return {ui_theme_surface_elevated(), ui_theme_focus(), ui_theme_text(), 2}
    case .Selected:
        return {ui_theme_accent(), ui_theme_border_strong(), ui_theme_text_inverse(), 2}
    case .Disabled:
        return {ui_theme_control(150), ui_theme_disabled(), ui_theme_disabled(), 1}
    case .Resting:
        return {ui_theme_control(), ui_theme_border(), ui_theme_text(), 1}
    }
    return {ui_theme_control(), ui_theme_border(), ui_theme_text(), 1}
}
