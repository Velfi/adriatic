package main

import atmosphere "../packages/atmosphere"
import boats "../packages/boats"
import "core:fmt"
import "core:math"
import canvas2d "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

BOAT_LAB_CLASSES := [5]boats.Class{.Motor, .Sail, .Fishing, .Tug, .Dinghy}

boat_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.project.sea_level = 0
    editor.boat_traffic = boats.new_traffic()
    editor.ocean_traffic = {}
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

    if target == "dinghy" {
        editor.boat_traffic = {}
        _ = boats.add_moored_agent(&editor.boat_traffic, .Dinghy, {0, 0}, .12)
        editor.camera_pose = third_person.camera_look_at({3.0, 2.15, -3.65}, {0, .38, 0})
        third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
        third_person.camera_set_active(&editor.cameras, .Inspection)
        return true
    }

    if target == "tanker" || target == "cruise" {
        editor.boat_traffic = {}
        class := target == "tanker" ? boats.Ocean_Class.Product_Tanker : boats.Ocean_Class.Cruise_Ship
        spec := boats.ocean_specifications(class)
        editor.ocean_traffic.agent = {
            class    = class,
            position = {-spec.cruise_speed_mps * 46, 0},
            yaw      = math.PI * .5,
            active   = true,
        }
        // Arrive at the inspection mark with a mature, continuously generated
        // wake instead of fabricating presentation-only foam.
        for _ in 0 ..< 920 do boats.ocean_traffic_step(&editor.ocean_traffic, .05)
        distance := spec.length * 1.12
        eye := third_person.Vec3{distance * .58, spec.height * 1.24, distance * .66}
        look := third_person.Vec3{0, spec.height * .16, 0}
        editor.camera_pose = third_person.camera_look_at(eye, look)
        third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
        third_person.camera_set_active(&editor.cameras, .Inspection)
        return true
    }

    editor.camera_pose = third_person.camera_look_at({45, 28, 52}, {0, 2.8, 0})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

world_boat_lab_water :: proc() {
    extent := f32(700)
    divisions := 20
    cell := extent * 2 / f32(divisions)
    color := canvas2d.Color{42, 105, 135, 255}
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
    world_ocean_ship_wake(editor)
    world_renderer.dynamic_caster_first = len(world_renderer.vertices)
    world_npc_boats(editor)
    world_ocean_ship(editor)
    world_renderer.dynamic_caster_count = len(world_renderer.vertices) - world_renderer.dynamic_caster_first
}

boat_lab_draw_ui :: proc(editor: ^Editor, width, height: i32) {
    panel := canvas2d.Rectangle {
        x      = 22,
        y      = 22,
        width  = 410,
        height = 224,
    }
    canvas2d.DrawRectangleRounded(panel, .10, 8, {10, 27, 37, 226})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {104, 168, 184, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "NPC BOAT LAB", {38, 38}, 20, 1, {245, 238, 197, 255})
    for class, index in BOAT_LAB_CLASSES {
        spec := boats.specifications(class)
        label := fmt.ctprintf("%s   %.2f m x %.2f m", boats.class_name(class), spec.length, spec.beam)
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            label,
            {38, 70 + f32(index) * 21},
            13,
            1,
            index >= 3 ? canvas2d.Color{247, 189, 115, 255} : canvas2d.Color{208, 239, 240, 255},
        )
    }
    ocean_classes := [2]boats.Ocean_Class{.Product_Tanker, .Cruise_Ship}
    for class, index in ocean_classes {
        spec := boats.ocean_specifications(class)
        name := class == .Product_Tanker ? "PRODUCT TANKER" : "CRUISE SHIP"
        label := fmt.ctprintf("%s   %.2f m x %.2f m", name, spec.length, spec.beam)
        canvas2d.DrawTextEx(canvas2d.Font{}, label, {38, 175 + f32(index) * 21}, 13, 1, {247, 189, 115, 255})
    }
    _ = editor
    _ = width
    _ = height
}
