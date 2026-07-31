package main

import atmosphere "../packages/atmosphere"
import particle_systems "../packages/particles"
import roads "../packages/roads"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

car_lab_pavement := roads.Pavement.Asphalt
car_lab_show_ui := true

car_lab_surface_name :: proc(surface: particle_systems.Dust_Surface) -> string {
    switch surface {
    case .Grass:
        return "GRASS"
    case .Asphalt:
        return "ASPHALT"
    case .Gravel:
        return "GRAVEL"
    case .Cobblestone:
        return "COBBLE"
    case .Dirt:
        return "DIRT"
    case .Sand:
        return "SAND"
    }
    return "UNKNOWN"
}

car_lab_place_on_pavement :: proc(editor: ^Editor, pavement: roads.Pavement, edge_amount: f32 = .18) -> bool {
    if editor == nil do return false
    edge_index := -1
    for edge, index in editor.project.road_graph.edges[:editor.project.road_graph.edge_count] {
        if edge.pavement == pavement {
            edge_index = index
            break
        }
    }
    if edge_index < 0 do return false

    edge := editor.project.road_graph.edges[edge_index]
    amount := clamp(edge_amount, f32(0), f32(1))
    point := roads.edge_point(&editor.project.road_graph, edge, amount)
    tangent := roads.edge_tangent(&editor.project.road_graph, edge, amount)
    editor.car.position = {point.x, point.y, point.z}
    editor.car.yaw_radians = math.atan2(tangent.z, tangent.x)
    editor.car_drive = {}
    car_physics_teleport(editor)

    // Reset occupancy as well as the rigid body so R and the surface hotkeys
    // recover cleanly even after the driver has stepped out of the car.
    editor.car.driver = nil
    editor.pilot.vehicle = nil
    editor.pilot.mode = .On_Foot
    editor.pilot.position = editor.car.position
    _, entered := vehicles.try_enter_nearest(&editor.pilot, []^vehicles.Vehicle{&editor.car})
    if !entered do return false

    car_lab_pavement = pavement
    editor.camera = third_person.default_camera()
    editor.camera_pose = third_person.camera_pose(editor.car.position, editor.camera)
    third_person.camera_set_pose(&editor.cameras, .Player, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Player)
    return true
}

car_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    seed_road_capture(editor)
    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    atmosphere.set_world_minutes(&editor.atmosphere, 9 * 60 + 10)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true

    pavement := roads.Pavement.Asphalt
    edge_amount := f32(.18)
    all_cobble_junction := false
    neglected_cobble := false
    car_lab_show_ui = true
    switch target {
    case "gravel":
        pavement = .Gravel
    case "cobble", "cobblestone":
        pavement = .Cobblestone
    case "cobble-clean":
        pavement = .Cobblestone
        car_lab_show_ui = false
    case "cobble-grassy-clean":
        pavement = .Cobblestone
        neglected_cobble = true
        car_lab_show_ui = false
    case "cobble-junction-clean":
        pavement = .Cobblestone
        edge_amount = .985
        all_cobble_junction = true
        car_lab_show_ui = false
    case "cobble-night-clean":
        pavement = .Cobblestone
        car_lab_show_ui = false
        atmosphere.set_world_minutes(&editor.atmosphere, 22 * 60)
    case "cobble-storm-clean":
        pavement = .Cobblestone
        car_lab_show_ui = false
        atmosphere.set_world_minutes(&editor.atmosphere, 16 * 60)
        atmosphere.set_weather_override(&editor.atmosphere, .Storm)
        editor.atmosphere.weather = atmosphere.weather_for(.Storm)
    case "dirt":
        pavement = .Dirt
    }
    if all_cobble_junction {
        for &edge in editor.project.road_graph.edges[:editor.project.road_graph.edge_count] {
            edge.pavement = .Cobblestone
        }
        editor.project.revision += 1
    }
    if neglected_cobble {
        for &edge in editor.project.road_graph.edges[:editor.project.road_graph.edge_count] {
            if edge.pavement == .Cobblestone {
                edge.use_intensity = .12
                break
            }
        }
        editor.project.revision += 1
    }
    return car_lab_place_on_pavement(editor, pavement, edge_amount)
}

car_lab_process_input :: proc(editor: ^Editor) {
    if editor == nil do return
    if canvas2d.IsKeyPressed(.ONE) do _ = car_lab_place_on_pavement(editor, .Asphalt)
    if canvas2d.IsKeyPressed(.TWO) do _ = car_lab_place_on_pavement(editor, .Gravel)
    if canvas2d.IsKeyPressed(.THREE) do _ = car_lab_place_on_pavement(editor, .Cobblestone)
    if canvas2d.IsKeyPressed(.FOUR) do _ = car_lab_place_on_pavement(editor, .Dirt)
    if canvas2d.IsKeyPressed(.R) do _ = car_lab_place_on_pavement(editor, car_lab_pavement)
}

car_lab_draw_ui :: proc(editor: ^Editor, width, height: i32) {
    if editor == nil || !car_lab_show_ui do return
    center_surface, center_grip := road_car_surface(editor, editor.car.position)
    speed := vehicles.car_drive_speed(editor.car_drive)
    bump := car_surface_bump_acceleration(center_surface, editor.car.position, speed)
    panel := canvas2d.Rectangle {
        x      = 20,
        y      = 20,
        width  = 410,
        height = 258,
    }
    canvas2d.DrawRectangleRounded(panel, .08, 8, {12, 22, 29, 230})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .08, 8, 1, {191, 157, 94, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "CAR PHYSICS LAB", {36, 35}, 21, 1, {247, 225, 168, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "WASD drive   SPACE handbrake   R reset", {36, 67}, 14, 1, {207, 221, 218, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "1 asphalt   2 gravel   3 cobble   4 dirt", {36, 89}, 14, 1, {207, 221, 218, 255})
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        fmt.ctprintf(
            "SPEED %5.1f m/s    STEER %+.2f    YAW %+.2f rad/s",
            speed,
            editor.car_drive.steering,
            editor.car_drive.yaw_rate,
        ),
        {36, 124},
        14,
        1,
        {238, 239, 222, 255},
    )
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        fmt.ctprintf(
            "SLIP %3.0f%%   BUMP %+.2f m/s2   %s %.2f / %.2f",
            editor.car_drive.slip_amount * 100,
            bump,
            car_lab_surface_name(center_surface),
            center_grip.longitudinal_grip,
            center_grip.lateral_grip,
        ),
        {36, 147},
        14,
        1,
        {238, 239, 222, 255},
    )
    wheel_labels := [4]string{"FR", "FL", "RR", "RL"}
    for index in 0 ..< 4 {
        wheel := editor.car_wheels[index]
        wheel_surface, _ := road_car_surface(editor, {wheel.position[0], wheel.position[1], wheel.position[2]})
        column := index % 2
        row := index / 2
        color := wheel.contact ? canvas2d.Color{139, 219, 161, 255} : canvas2d.Color{224, 121, 102, 255}
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            fmt.ctprintf(
                "%s  %-8s  %s",
                wheel_labels[index],
                car_lab_surface_name(wheel_surface),
                wheel.contact ? "CONTACT" : "AIR",
            ),
            {36 + f32(column) * 190, 184 + f32(row) * 24},
            13,
            1,
            color,
        )
    }
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        fmt.ctprintf("TEST PAD: %s", roads.pavement_name(car_lab_pavement)),
        {36, 238},
        13,
        1,
        {247, 189, 115, 255},
    )
    _ = width
    _ = height
}
