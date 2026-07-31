package main

import game_input "../packages/game_input"
import vehicles "../packages/vehicles"
import "core:fmt"
import canvas2d "zelda_engine:canvas2d"

CONTROL_HINT_TILE_SIZE :: f32(64)
CONTROL_HINT_DRAW_SIZE :: f32(22)

Control_Hint_Binding :: enum {
    Move,
    Look,
    Zoom,
    Jump,
    Run,
    Interact,
    Pause,
    Pitch,
    Roll,
    Yaw,
    Camera,
    Recenter,
    Power,
    Exit,
    Drive,
    Steer,
    Brake,
    Altitude,
    Bomber,
    Drop,
}

Control_Hint_Entry :: struct {
    binding: Control_Hint_Binding,
    label:   cstring,
}

Control_Hint_Atlases :: struct {
    keyboard_mouse: canvas2d.Texture,
    generic:        canvas2d.Texture,
    xbox:           canvas2d.Texture,
    playstation:    canvas2d.Texture,
    nintendo:       canvas2d.Texture,
}

control_hints_load :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.control_hint_atlases = {
        keyboard_mouse = canvas2d.LoadTexture("assets/icons/control-hints/keyboard-mouse.png"),
        generic        = canvas2d.LoadTexture("assets/icons/control-hints/generic.png"),
        xbox           = canvas2d.LoadTexture("assets/icons/control-hints/xbox.png"),
        playstation    = canvas2d.LoadTexture("assets/icons/control-hints/playstation.png"),
        nintendo       = canvas2d.LoadTexture("assets/icons/control-hints/nintendo.png"),
    }
}

control_hint_tile :: proc(x, y: f32) -> canvas2d.Rectangle {
    return {x, y, CONTROL_HINT_TILE_SIZE, CONTROL_HINT_TILE_SIZE}
}

control_hint_keyboard_source :: proc(binding: Control_Hint_Binding) -> canvas2d.Rectangle {
    switch binding {
    case .Move, .Pitch, .Drive:
        return control_hint_tile(128, 832) // W
    case .Roll, .Steer:
        return control_hint_tile(256, 64) // A
    case .Yaw:
        return control_hint_tile(576, 640) // Q
    case .Look, .Camera:
        return control_hint_tile(1024, 832) // mouse move
    case .Zoom:
        return control_hint_tile(576, 896) // mouse wheel
    case .Jump, .Brake:
        return control_hint_tile(1024, 704) // Space
    case .Run, .Power, .Altitude:
        return control_hint_tile(512, 704) // Shift
    case .Interact, .Exit:
        return control_hint_tile(0, 384) // F
    case .Pause:
        return control_hint_tile(832, 320) // Esc
    case .Recenter:
        return control_hint_tile(128, 256) // C
    case .Bomber:
        return control_hint_tile(320, 64) // B
    case .Drop:
        return control_hint_tile(512, 256) // X
    }
    return {}
}

control_hint_controller_texture :: proc(editor: ^Editor) -> canvas2d.Texture {
    switch editor.runtime_input.controller_style {
    case .Xbox:
        return editor.control_hint_atlases.xbox
    case .PlayStation:
        return editor.control_hint_atlases.playstation
    case .Nintendo:
        return editor.control_hint_atlases.nintendo
    case .Generic:
        return editor.control_hint_atlases.generic
    }
    return {}
}

control_hint_controller_source :: proc(
    style: game_input.Controller_Style,
    binding: Control_Hint_Binding,
) -> canvas2d.Rectangle {
    switch style {
    case .Xbox:
        switch binding {
        case .Move, .Pitch, .Roll, .Drive, .Steer:
            return control_hint_tile(576, 448) // left stick
        case .Look, .Camera:
            return control_hint_tile(448, 512) // right stick
        case .Zoom, .Power, .Altitude:
            return control_hint_tile(448, 448) // right trigger
        case .Jump, .Recenter:
            return control_hint_tile(256, 0) // A
        case .Run:
            return control_hint_tile(128, 192) // Y
        case .Interact, .Exit:
            return control_hint_tile(0, 192) // X
        case .Pause:
            return control_hint_tile(256, 128) // Start
        case .Yaw:
            return control_hint_tile(448, 384) // LB
        case .Brake:
            return control_hint_tile(192, 448) // RB
        case .Bomber, .Drop:
            return control_hint_tile(64, 128) // D-pad
        }
    case .PlayStation:
        switch binding {
        case .Move, .Pitch, .Roll, .Drive, .Steer:
            return control_hint_tile(384, 192) // left stick
        case .Look, .Camera:
            return control_hint_tile(128, 256) // right stick
        case .Zoom, .Power, .Altitude:
            return control_hint_tile(128, 384) // R2
        case .Jump, .Recenter:
            return control_hint_tile(320, 64) // Cross
        case .Run:
            return control_hint_tile(64, 128) // Triangle
        case .Interact, .Exit:
            return control_hint_tile(704, 64) // Square
        case .Pause:
            return control_hint_tile(64, 576) // Options
        case .Yaw:
            return control_hint_tile(128, 320) // L1
        case .Brake:
            return control_hint_tile(640, 320) // R1
        case .Bomber, .Drop:
            return control_hint_tile(576, 512) // D-pad
        }
    case .Nintendo:
        switch binding {
        case .Move, .Pitch, .Roll, .Drive, .Steer:
            return control_hint_tile(128, 512) // left stick
        case .Look, .Camera:
            return control_hint_tile(640, 512) // right stick
        case .Zoom, .Power, .Altitude:
            return control_hint_tile(512, 128) // ZR
        case .Jump, .Recenter:
            return control_hint_tile(384, 0) // B
        case .Run:
            return control_hint_tile(128, 128) // X
        case .Interact, .Exit:
            return control_hint_tile(256, 128) // Y
        case .Pause:
            return control_hint_tile(192, 64) // Plus
        case .Yaw:
            return control_hint_tile(640, 0) // L
        case .Brake:
            return control_hint_tile(320, 64) // R
        case .Bomber, .Drop:
            return control_hint_tile(256, 448) // D-pad
        }
    case .Generic:
        switch binding {
        case .Move, .Pitch, .Roll, .Drive, .Steer:
            return control_hint_tile(192, 256) // stick
        case .Look, .Camera:
            return control_hint_tile(128, 320) // stick right
        case .Zoom, .Power, .Altitude:
            return control_hint_tile(256, 64) // trigger
        case .Yaw, .Brake:
            return control_hint_tile(64, 128) // trigger
        case .Jump, .Run, .Interact, .Pause, .Recenter, .Exit, .Bomber, .Drop:
            return control_hint_tile(64, 0) // button
        }
    }
    return {}
}

control_hint_draw_bar :: proc(editor: ^Editor, entries: []Control_Hint_Entry, position: canvas2d.Vector2, max_width: f32) {
    if editor == nil do return
    controller := controller_prompt_active(editor)
    texture := editor.control_hint_atlases.keyboard_mouse
    if controller do texture = control_hint_controller_texture(editor)
    if !texture.ready do return

    cursor_x := position.x
    for entry in entries {
        source := control_hint_keyboard_source(entry.binding)
        if controller {
            source = control_hint_controller_source(editor.runtime_input.controller_style, entry.binding)
        }
        // Kenney's atlas metadata uses a top-left origin; canvas texture UVs
        // address rows from the bottom.
        source.y = f32(texture.height) - source.y - source.height
        label_size := canvas2d.MeasureTextEx(canvas2d.Font{}, entry.label, 13, .6)
        entry_width := CONTROL_HINT_DRAW_SIZE + 4 + label_size.x
        if cursor_x + entry_width > position.x + max_width do break
        canvas2d.DrawTexturePro(
            texture,
            source,
            {cursor_x, position.y - 4, CONTROL_HINT_DRAW_SIZE, CONTROL_HINT_DRAW_SIZE},
            ui_theme_text(),
        )
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            entry.label,
            {cursor_x + CONTROL_HINT_DRAW_SIZE + 4, position.y},
            13,
            .6,
            ui_theme_text_muted(),
        )
        cursor_x += entry_width + 14
    }
}

control_hint_draw_gameplay_hud :: proc(editor: ^Editor, width: i32) {
    if editor == nil || !editor.in_map || !editor.gameplay_options.show_hud || editor.attendant_dialogue_open {
        return
    }

    flying := driving_aircraft(editor)
    in_car := driving_car(editor)
    panel_width := i32(790)
    entries: [8]Control_Hint_Entry
    count := 7
    title := "ON FOOT"
    entries[0] = {.Move, "MOVE"}
    entries[1] = {.Look, "LOOK"}
    entries[2] = {.Zoom, "ZOOM"}
    entries[3] = {.Jump, "JUMP"}
    entries[4] = {.Run, "RUN"}
    entries[5] = {.Interact, "USE"}
    entries[6] = {.Pause, "PAUSE"}

    if flying {
        panel_width = 820
        count = 7
        title = vehicles.aircraft_kind_name(editor.aircraft.active)
        entries[0] = {.Pitch, "PITCH"}
        entries[1] = {.Roll, "ROLL"}
        entries[2] = {.Yaw, "YAW"}
        entries[3] = {.Camera, "CAMERA"}
        entries[4] = {.Power, "POWER"}
        entries[5] = {.Recenter, "CENTER"}
        entries[6] = {.Exit, "EXIT"}
        if editor.bomber_mode {
            panel_width = 920
            entries[3] = {.Bomber, "SIGHT"}
            entries[5] = {.Drop, "DROP"}
        }
        if editor.aircraft.active != .Postale {
            entries[4] = {.Altitude, "ALTITUDE"}
        }
    } else if in_car {
        panel_width = 690
        count = 6
        title = "DRIVING"
        entries[0] = {.Drive, "DRIVE"}
        entries[1] = {.Steer, "STEER"}
        entries[2] = {.Look, "LOOK"}
        entries[3] = {.Brake, "BRAKE"}
        entries[4] = {.Exit, "EXIT"}
        entries[5] = {.Pause, "PAUSE"}
    }

    panel_width = min(panel_width, width - 28)
    panel := canvas2d.Rectangle{14, 14, f32(panel_width), 58}
    canvas2d.DrawRectangleRounded(panel, .16, 8, ui_theme_surface(232))
    canvas2d.DrawRectangleRoundedLinesEx(panel, .16, 8, 1, ui_theme_border(235))
    canvas2d.DrawTextEx(canvas2d.Font{}, fmt.ctprintf("%s", title), {26, 23}, 17, 1, ui_theme_text())
    journal_hint: cstring = "J JOURNAL"
    if controller_prompt_active(editor) {
        journal_hint = fmt.ctprintf("%s JOURNAL", controller_journal_label(editor))
    }
    journal_size := canvas2d.MeasureTextEx(canvas2d.Font{}, journal_hint, 13, .6)
    ui_draw_text(
        .Data,
        journal_hint,
        {panel.x + panel.width - journal_size.x - 12, panel.y + 34},
        .2,
        ui_theme_accent(),
    )
    control_hint_draw_bar(editor, entries[:count], {26, 46}, f32(panel_width - 48) - journal_size.x)
}
