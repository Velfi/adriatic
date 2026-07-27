package main

import atmosphere "../packages/atmosphere"
import boats "../packages/boats"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import rl "zelda_engine:canvas2d"

BOAT_LAB_CLASSES := [4]boats.Class{.Motor, .Sail, .Fishing, .Tug}

boat_lab_configure :: proc(editor: ^Editor, _: string) -> bool {
    if editor == nil do return false
    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.project.sea_level = 0
    editor.boat_traffic = boats.new_traffic()
    centers := [4]boats.Vec2{{-13, -12}, {0, -12}, {13, -12}, {0, 10}}
    radii := [4]f32{7, 6, 7, 10}
    for &agent, index in editor.boat_traffic.agents[:editor.boat_traffic.count] {
        center := centers[index]
        radius := radii[index]
        agent.loiter_center = center
        agent.loiter_radius = radius * .45
        agent.position = {center.x + radius, center.y}
        agent.route_index = 0
        for route_index in 0 ..< agent.route_count {
            angle := f32(route_index) * math.PI * 2 / f32(agent.route_count) + f32(index) * .27
            agent.route[route_index] = {center.x + math.cos(angle) * radius, center.y + math.sin(angle) * radius * .68}
        }
        agent.speed = boats.specifications(agent.class).cruise_speed_mps * (agent.class == .Tug ? f32(.34) : f32(.62))
    }
    // Seed enough history for captures to show established wakes immediately.
    for _ in 0 ..< 100 do boats.step(&editor.boat_traffic, .05, 8 * 60 + 35)

    // An oblique morning key makes both self-shadowing and the silhouettes
    // cast onto the water easy to inspect.
    atmosphere.set_world_minutes(&editor.atmosphere, 8 * 60 + 35)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true

    editor.camera_pose = third_person.camera_look_at({45, 28, 52}, {0, 2.8, 0})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

world_boat_lab_water :: proc() {
    extent := f32(120)
    divisions := 20
    cell := extent * 2 / f32(divisions)
    color := rl.Color{42, 105, 135, 255}
    for z_index in 0 ..< divisions {
        z0 := -extent + f32(z_index) * cell
        z1 := z0 + cell
        for x_index in 0 ..< divisions {
            x0 := -extent + f32(x_index) * cell
            x1 := x0 + cell
            world_water_quad({x0, 0, z0}, {x0, 0, z1}, {x1, 0, z1}, {x1, 0, z0}, color)
        }
    }
}

world_boat_lab :: proc(editor: ^Editor) {
    if editor == nil do return
    world_boat_lab_water()
    world_boat_wakes(editor)
    world_renderer.dynamic_caster_first = len(world_renderer.vertices)
    world_npc_boats(editor)
    world_renderer.dynamic_caster_count = len(world_renderer.vertices) - world_renderer.dynamic_caster_first
}

boat_lab_draw_ui :: proc(_: ^Editor, width, height: i32) {
    panel := rl.Rectangle {
        x      = 22,
        y      = 22,
        width  = 410,
        height = 158,
    }
    rl.DrawRectangleRounded(panel, .10, 8, {10, 27, 37, 226})
    rl.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {104, 168, 184, 255})
    rl.DrawTextEx(rl.Font{}, "NPC BOAT LAB", {38, 38}, 20, 1, {245, 238, 197, 255})
    for class, index in BOAT_LAB_CLASSES {
        spec := boats.specifications(class)
        label := fmt.ctprintf("%s   %.2f m x %.2f m", boats.class_name(class), spec.length, spec.beam)
        rl.DrawTextEx(
            rl.Font{},
            label,
            {38, 70 + f32(index) * 21},
            13,
            1,
            index == 3 ? rl.Color{247, 189, 115, 255} : rl.Color{208, 239, 240, 255},
        )
    }
    _ = width
    _ = height
}
