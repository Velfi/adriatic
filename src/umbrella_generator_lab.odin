package main

import atmosphere "../packages/atmosphere"
import third_person "../packages/third_person"
import umbrellas "../packages/umbrellas"
import "core:fmt"
import canvas2d "zelda_engine:canvas2d"

umbrella_lab_seed := u32(0x554d4252)
umbrella_lab_kind := umbrellas.Kind.Beach
umbrella_lab_radius := f32(1.85)
umbrella_lab_height := f32(2.35)
umbrella_lab_panels := 10

umbrella_lab_type_bounds :: proc() -> canvas2d.Rectangle {return {38, 68, 118, 28}}
umbrella_lab_seed_bounds :: proc() -> canvas2d.Rectangle {return {168, 68, 154, 28}}
umbrella_lab_radius_bounds :: proc() -> canvas2d.Rectangle {return {38, 118, 138, 28}}
umbrella_lab_height_bounds :: proc() -> canvas2d.Rectangle {return {188, 118, 138, 28}}
umbrella_lab_panels_bounds :: proc() -> canvas2d.Rectangle {return {338, 118, 122, 28}}

umbrella_lab_reset_kind :: proc(kind: umbrellas.Kind) {
    config := umbrellas.defaults(kind)
    umbrella_lab_kind = kind
    umbrella_lab_radius = config.radius
    umbrella_lab_height = config.height
    umbrella_lab_panels = config.panel_count
}

umbrella_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    switch target {
    case "", "beach":
        umbrella_lab_reset_kind(.Beach)
    case "patio":
        umbrella_lab_reset_kind(.Patio)
    case:
        return false
    }
    editor.in_map = true
    editor.capture_world_only = false
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    editor.project.sea_level = -20
    atmosphere.set_world_minutes(&editor.atmosphere, 10 * 60 + 15)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    editor.camera_pose = third_person.camera_look_at({6.8, 3.8, 7.3}, {0, 1.45, 0})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

umbrella_lab_process_input :: proc(_: ^Editor) {
    if lab_ui_button_pressed(umbrella_lab_type_bounds()) do umbrella_lab_reset_kind(umbrella_lab_kind == .Beach ? .Patio : .Beach)
    if lab_ui_button_pressed(umbrella_lab_seed_bounds()) do umbrella_lab_seed += 1
    radius_delta := lab_ui_stepper_delta(umbrella_lab_radius_bounds())
    height_delta := lab_ui_stepper_delta(umbrella_lab_height_bounds())
    panels_delta := lab_ui_stepper_delta(umbrella_lab_panels_bounds())
    if radius_delta != 0 do umbrella_lab_radius = clamp(umbrella_lab_radius + f32(radius_delta) * .15, f32(1.2), f32(4))
    if height_delta != 0 do umbrella_lab_height = clamp(umbrella_lab_height + f32(height_delta) * .15, f32(1.8), f32(4.5))
    if panels_delta != 0 do umbrella_lab_panels = clamp(umbrella_lab_panels + panels_delta * 2, 6, umbrellas.MAX_PANELS)
    if canvas2d.IsKeyPressed(.A) do umbrella_lab_seed -= 1
    if canvas2d.IsKeyPressed(.D) do umbrella_lab_seed += 1
    if canvas2d.IsKeyPressed(.S) do umbrella_lab_reset_kind(umbrella_lab_kind == .Beach ? .Patio : .Beach)
    if canvas2d.IsKeyPressed(.LEFT) do umbrella_lab_radius = max(f32(1.2), umbrella_lab_radius - .15)
    if canvas2d.IsKeyPressed(.RIGHT) do umbrella_lab_radius = min(f32(4), umbrella_lab_radius + .15)
    if canvas2d.IsKeyPressed(.DOWN) do umbrella_lab_panels = max(6, umbrella_lab_panels - 2)
    if canvas2d.IsKeyPressed(.UP) do umbrella_lab_panels = min(umbrellas.MAX_PANELS, umbrella_lab_panels + 2)
    if canvas2d.IsKeyPressed(.ONE) do umbrella_lab_height = max(f32(1.8), umbrella_lab_height - .15)
    if canvas2d.IsKeyPressed(.TWO) do umbrella_lab_height = min(f32(4.5), umbrella_lab_height + .15)
}

world_umbrella_generator_lab :: proc(_: ^Editor) {
    ground := umbrella_lab_kind == .Beach ? canvas2d.Color{219, 196, 145, 255} : canvas2d.Color{180, 169, 145, 255}
    world_box_rotated({0, -.12, 0}, {16, .24, 16}, 0, ground)
    plan := umbrellas.generate(
        umbrella_lab_seed,
        {
            kind = umbrella_lab_kind,
            radius = umbrella_lab_radius,
            height = umbrella_lab_height,
            panel_count = umbrella_lab_panels,
        },
    )
    world_umbrella(&plan, {0, 0, 0})
}

umbrella_lab_draw_ui :: proc(_: ^Editor, _: i32, _: i32) {
    panel := canvas2d.Rectangle {
        x      = 22,
        y      = 22,
        width  = 470,
        height = 164,
    }
    canvas2d.DrawRectangleRounded(panel, .10, 8, {10, 27, 37, 226})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {104, 168, 184, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "UMBRELLA GENERATOR", {38, 38}, 20, 1, {245, 238, 197, 255})
    kind_name: cstring = umbrella_lab_kind == .Beach ? "BEACH" : "PATIO"
    lab_ui_draw_button(umbrella_lab_type_bounds(), kind_name, true)
    lab_ui_draw_button(umbrella_lab_seed_bounds(), fmt.ctprintf("NEW SEED  %08X", umbrella_lab_seed))
    canvas2d.DrawTextEx(canvas2d.Font{}, "RADIUS", {38, 103}, 10, 1, {171, 201, 207, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "HEIGHT", {188, 103}, 10, 1, {171, 201, 207, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "PANELS", {338, 103}, 10, 1, {171, 201, 207, 255})
    lab_ui_draw_stepper(umbrella_lab_radius_bounds(), fmt.ctprintf("%.2f M", umbrella_lab_radius))
    lab_ui_draw_stepper(umbrella_lab_height_bounds(), fmt.ctprintf("%.2f M", umbrella_lab_height))
    lab_ui_draw_stepper(umbrella_lab_panels_bounds(), fmt.ctprintf("%d", umbrella_lab_panels))
}
