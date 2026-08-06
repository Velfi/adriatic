package main

import architecture "../packages/architecture"
import atmosphere "../packages/atmosphere"
import buildings "../packages/buildings"
import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import "core:fmt"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

LIGHTHOUSE_LAB_HEIGHTS := [3]f32{14, 22, 30}

lighthouse_lab_seed: u32
lighthouse_lab_region: buildings.Region
lighthouse_lab_height_index: int
lighthouse_lab_night: bool

lighthouse_lab_apply_lighting :: proc(editor: ^Editor) {
    minutes := lighthouse_lab_night ? f32(23 * 60 + 20) : f32(8 * 60 + 20)
    atmosphere.set_world_minutes(&editor.atmosphere, minutes)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
}

lighthouse_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    // Start with the sweep broadside to the authored inspection camera so the
    // beam is immediately legible instead of hiding end-on behind the tower.
    lighthouse_lab_seed = 0x15BC
    lighthouse_lab_region = .Adriatic
    lighthouse_lab_height_index = 1
    lighthouse_lab_night = false
    switch target {
    case "", "adriatic":
    case "aegean":
        lighthouse_lab_region = .Aegean
    case "night", "adriatic-night":
        lighthouse_lab_night = true
    case "aegean-night":
        lighthouse_lab_region = .Aegean
        lighthouse_lab_night = true
    case "reflection-night":
        lighthouse_lab_region = .Aegean
        lighthouse_lab_night = true
        // Aim the initial sweep toward the authored inspection camera. This
        // is the deterministic maximum-reflection target for water-glitter QA.
        lighthouse_lab_seed = 0x1870
    case "short":
        lighthouse_lab_height_index = 0
    case "tall":
        lighthouse_lab_height_index = 2
    case:
        return false
    }

    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.project.sea_level = 0
    lighthouse_lab_apply_lighting(editor)
    set_pointer_locked(false)
    editor.camera_pose = third_person.camera_look_at({31, 20, 38}, {0, 12, 0})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

lighthouse_lab_process_input :: proc(editor: ^Editor) {
    if canvas2d.IsKeyPressed(.A) do lighthouse_lab_seed -= 1
    if canvas2d.IsKeyPressed(.D) do lighthouse_lab_seed += 1
    if canvas2d.IsKeyPressed(.R) {
        lighthouse_lab_region = lighthouse_lab_region == .Adriatic ? .Aegean : .Adriatic
    }
    if canvas2d.IsKeyPressed(.L) {
        lighthouse_lab_night = !lighthouse_lab_night
        lighthouse_lab_apply_lighting(editor)
    }
    if canvas2d.IsKeyPressed(.ONE) do lighthouse_lab_height_index = 0
    if canvas2d.IsKeyPressed(.TWO) do lighthouse_lab_height_index = 1
    if canvas2d.IsKeyPressed(.THREE) do lighthouse_lab_height_index = 2
}

lighthouse_lab_structure :: proc() -> terrain.Structure {
    height := LIGHTHOUSE_LAB_HEIGHTS[lighthouse_lab_height_index]
    structure := terrain.structure_make(0, 0, 9, 9, 1.1, height)
    structure.kind = .Architecture
    structure.seed = lighthouse_lab_seed
    structure.building = architecture.architecture_identity(
        {region = lighthouse_lab_region, landmark_kind = .Lighthouse, purpose_explicit = true},
        structure.seed,
    )
    structure.color = architecture.architecture_color(structure.seed, true)
    return structure
}

world_lighthouse_lab :: proc(editor: ^Editor) {
    if editor == nil do return

    // A low faceted skerry gives the foundation and silhouette coastal context
    // without hiding any portion of the generated tower.
    rock := canvas2d.Color{111, 105, 91, 255}
    world_tube_between({0, -.45, 0}, {0, .72, 0}, {0, 0, 1}, 8.2, 6.8, rock)
    world_tube_between({0, .68, 0}, {0, 1.08, 0}, {0, 0, 1}, 5.8, 5.0, {143, 132, 108, 255})
    lighthouse := lighthouse_lab_structure()
    world_architecture_lighthouse(lighthouse)
    keeper_x, keeper_z := world_rotate_xz(
        lighthouse.center_x,
        lighthouse.center_z,
        lighthouse.width * .50,
        lighthouse.depth * .5 + .5,
        lighthouse.rotation,
    )
    world_lighthouse_keeper_model(
        editor,
        {keeper_x, 1.08, keeper_z},
        lighthouse.rotation + math.PI * .5,
        lighthouse_lab_region == .Adriatic,
        false,
        1.5,
    )

    // The skerry rises through a continuous water sheet. Cutting a square hole
    // around the octagonal rock exposed the clear color at its corners and
    // looked like a missing chunk beneath the lighthouse.
    water := canvas2d.Color{39, 100, 128, 255}
    extent := f32(90)
    world_water_quad({-extent, 0, -extent}, {-extent, 0, extent}, {extent, 0, extent}, {extent, 0, -extent}, water)
}

lighthouse_lab_draw_ui :: proc(_: ^Editor, width, height: i32) {
    panel := canvas2d.Rectangle {
        x      = 22,
        y      = 22,
        width  = 430,
        height = 142,
    }
    canvas2d.DrawRectangleRounded(panel, .10, 8, {10, 27, 37, 226})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {104, 168, 184, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "LIGHTHOUSE GENERATOR LAB", {38, 38}, 20, 1, {245, 238, 197, 255})
    region := lighthouse_lab_region == .Aegean ? "AEGEAN" : "ADRIATIC"
    lighting := lighthouse_lab_night ? "NIGHT" : "MORNING"
    status := fmt.ctprintf(
        "SEED %08X   %s   %.0f m   %s",
        lighthouse_lab_seed,
        region,
        LIGHTHOUSE_LAB_HEIGHTS[lighthouse_lab_height_index],
        lighting,
    )
    canvas2d.DrawTextEx(canvas2d.Font{}, status, {38, 72}, 14, 1, {208, 239, 240, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "A / D seed     R region     L light", {38, 102}, 13, 1, {171, 201, 207, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "1 / 2 / 3 tower height", {38, 124}, 13, 1, {171, 201, 207, 255})
    _ = width
    _ = height
}
