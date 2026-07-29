package main

import atmosphere "../packages/atmosphere"
import fountains "../packages/fountains"
import third_person "../packages/third_person"
import "core:fmt"
import rl "zelda_engine:canvas2d"

fountain_lab_seed := u32(0xF017A17)
fountain_lab_style := fountains.Style.Tiered
fountain_lab_radius := f32(3.8)
fountain_lab_jets := 10
fountain_lab_height := f32(2.8)

fountain_lab_style_name :: proc() -> cstring {
    switch fountain_lab_style {
    case .Bowl:
        return "BOWL"
    case .Tiered:
        return "TIERED"
    case .Courtyard:
        return "COURTYARD"
    }
    return "TIERED"
}

fountain_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    fountain_lab_seed = 0xF017A17
    fountain_lab_style = .Tiered
    fountain_lab_radius = 3.8
    fountain_lab_jets = 10
    fountain_lab_height = 2.8
    switch target {
    case "", "tiered":
    case "bowl":
        fountain_lab_style = .Bowl
        fountain_lab_radius = 3.2
        fountain_lab_jets = 6
        fountain_lab_height = 1.35
    case "courtyard":
        fountain_lab_style = .Courtyard
        fountain_lab_radius = 5.2
        fountain_lab_jets = 16
        fountain_lab_height = 2.1
    case:
        return false
    }
    editor.in_map = true
    editor.capture_world_only = false
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    editor.project.sea_level = -20
    atmosphere.set_world_minutes(&editor.atmosphere, 10 * 60 + 20)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    editor.camera_pose = third_person.camera_look_at({5.8, 3.35, 6.25}, {0, 1.08, 0})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

fountain_lab_process_input :: proc(_: ^Editor) {
    if rl.IsKeyPressed(.A) do fountain_lab_seed -= 1
    if rl.IsKeyPressed(.D) do fountain_lab_seed += 1
    if rl.IsKeyPressed(.S) {
        count := int(fountains.Style.Courtyard) + 1
        fountain_lab_style = fountains.Style((int(fountain_lab_style) + 1) % count)
    }
    if rl.IsKeyPressed(.LEFT) do fountain_lab_radius = max(f32(2.2), fountain_lab_radius - .3)
    if rl.IsKeyPressed(.RIGHT) do fountain_lab_radius = min(f32(7), fountain_lab_radius + .3)
    if rl.IsKeyPressed(.DOWN) do fountain_lab_jets = max(0, fountain_lab_jets - 1)
    if rl.IsKeyPressed(.UP) do fountain_lab_jets = min(fountains.MAX_JETS, fountain_lab_jets + 1)
    if rl.IsKeyPressed(.ONE) do fountain_lab_height = max(f32(.4), fountain_lab_height - .25)
    if rl.IsKeyPressed(.TWO) do fountain_lab_height = min(f32(6), fountain_lab_height + .25)
}

world_fountain_generator_lab :: proc(_: ^Editor) {
    stone := rl.Color{155, 145, 125, 255}
    world_box_rotated({0, -.13, 0}, {18, .26, 18}, 0, stone)
    plan := fountains.generate(
        fountain_lab_seed,
        {
            radius = fountain_lab_radius,
            style = fountain_lab_style,
            jet_count = fountain_lab_jets,
            jet_height = fountain_lab_height,
        },
    )
    world_fountain(&plan, {0, 0, 0})
}

fountain_lab_draw_ui :: proc(_: ^Editor, width, height: i32) {
    panel := rl.Rectangle {
        x      = 22,
        y      = 22,
        width  = 470,
        height = 164,
    }
    rl.DrawRectangleRounded(panel, .10, 8, {10, 27, 37, 226})
    rl.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {104, 168, 184, 255})
    rl.DrawTextEx(rl.Font{}, "FOUNTAIN GENERATOR LAB", {38, 38}, 20, 1, {245, 238, 197, 255})
    status := fmt.ctprintf(
        "SEED %08X   %s   R %.1f   %d JETS   H %.2f",
        fountain_lab_seed,
        fountain_lab_style_name(),
        fountain_lab_radius,
        fountain_lab_jets,
        fountain_lab_height,
    )
    rl.DrawTextEx(rl.Font{}, status, {38, 72}, 14, 1, {208, 239, 240, 255})
    rl.DrawTextEx(rl.Font{}, "A / D seed     S style     LEFT / RIGHT radius", {38, 104}, 13, 1, {171, 201, 207, 255})
    rl.DrawTextEx(rl.Font{}, "UP / DOWN jets     1 / 2 jet height", {38, 128}, 13, 1, {171, 201, 207, 255})
    rl.DrawTextEx(
        rl.Font{},
        "Deterministic plan · bounded geometry · validated output",
        {38, 152},
        12,
        1,
        {145, 180, 188, 255},
    )
    _ = width
    _ = height
}
