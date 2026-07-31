package main

import atmosphere "../packages/atmosphere"
import third_person "../packages/third_person"
import windmills "../packages/windmills"
import "core:fmt"
import "core:math"
import rl "zelda_engine:canvas2d"

windmill_lab_seed := u32(1948)
windmill_lab_style := windmills.Style.Whitewashed
windmill_lab_sails := 4
windmill_lab_rpm := f32(3.5)
windmill_lab_paused := false

windmill_lab_style_name :: proc() -> cstring {
    switch windmill_lab_style {
    case .Stone:
        return "STONE"
    case .Whitewashed:
        return "WHITEWASHED"
    case .Ochre:
        return "OCHRE"
    }
    return "WHITEWASHED"
}

windmill_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    windmill_lab_seed = 1948
    windmill_lab_style = .Whitewashed
    windmill_lab_sails = 4
    windmill_lab_rpm = 3.5
    windmill_lab_paused = false
    switch target {
    case "", "whitewashed":
    case "stone":
        windmill_lab_style = .Stone
    case "ochre":
        windmill_lab_style = .Ochre
    case "six-sail":
        windmill_lab_sails = 6
    case "eight-sail":
        windmill_lab_sails = 8
    case:
        return false
    }
    editor.in_map = true
    editor.capture_world_only = false
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    editor.project.sea_level = -20
    atmosphere.set_world_minutes(&editor.atmosphere, 16 * 60 + 35)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    editor.camera_pose = third_person.camera_look_at({7.2, 5.6, 9.4}, {0, 3.9, 0})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

windmill_lab_process_input :: proc(_: ^Editor) {
    if rl.IsKeyPressed(.A) do windmill_lab_seed -= 1
    if rl.IsKeyPressed(.D) do windmill_lab_seed += 1
    if rl.IsKeyPressed(.S) {
        windmill_lab_style = windmills.Style((int(windmill_lab_style) + 1) % 3)
    }
    if rl.IsKeyPressed(.LEFT) do windmill_lab_sails = max(4, windmill_lab_sails - 1)
    if rl.IsKeyPressed(.RIGHT) do windmill_lab_sails = min(windmills.MAX_SAILS, windmill_lab_sails + 1)
    if rl.IsKeyPressed(.DOWN) do windmill_lab_rpm = max(f32(0), windmill_lab_rpm - .5)
    if rl.IsKeyPressed(.UP) do windmill_lab_rpm = min(f32(12), windmill_lab_rpm + .5)
    if rl.IsKeyPressed(.SPACE) do windmill_lab_paused = !windmill_lab_paused
}

windmill_lab_wall_color :: proc(style: windmills.Style) -> rl.Color {
    switch style {
    case .Stone:
        return {157, 145, 124, 255}
    case .Whitewashed:
        return {225, 218, 193, 255}
    case .Ochre:
        return {199, 150, 92, 255}
    }
    return {225, 218, 193, 255}
}

windmill_lab_tower :: proc(plan: ^windmills.Plan, wall: rl.Color) {
    bottom, top: [24]third_person.Vec3
    for segment in 0 ..< plan.wall_segments {
        angle := (f32(segment) + .5) * math.PI * 2 / f32(plan.wall_segments)
        bottom[segment] = {math.cos(angle) * plan.base_radius, 0, math.sin(angle) * plan.base_radius}
        top[segment] = {math.cos(angle) * plan.top_radius, plan.tower_height, math.sin(angle) * plan.top_radius}
    }
    for segment in 0 ..< plan.wall_segments {
        next := (segment + 1) % plan.wall_segments
        world_quad(bottom[segment], top[segment], top[next], bottom[next], wall)
        world_triangle({0, plan.tower_height, 0}, top[next], top[segment], wall)
    }
    roof_radius := plan.top_radius + plan.cap_overhang
    roof_peak := third_person.Vec3{0, plan.tower_height + plan.cap_height, 0}
    for segment in 0 ..< plan.wall_segments {
        angle_a := (f32(segment) + .5) * math.PI * 2 / f32(plan.wall_segments)
        angle_b := (f32(segment + 1) + .5) * math.PI * 2 / f32(plan.wall_segments)
        a := third_person.Vec3{math.cos(angle_a) * roof_radius, plan.tower_height, math.sin(angle_a) * roof_radius}
        b := third_person.Vec3{math.cos(angle_b) * roof_radius, plan.tower_height, math.sin(angle_b) * roof_radius}
        world_triangle(a, roof_peak, b, {112, 75, 47, 255})
    }
    world_box_rotated({0, 1.12, plan.base_radius + .025}, {1.02, 2.24, .18}, 0, {82, 57, 38, 255})
    world_box_rotated({0, 4.15, plan.top_radius + .035}, {.68, .88, .14}, 0, {66, 83, 86, 255})
    world_box_rotated({0, 4.15, plan.top_radius + .12}, {.07, .88, .05}, 0, {210, 205, 178, 255})
    world_box_rotated({0, 4.15, plan.top_radius + .13}, {.68, .07, .05}, 0, {210, 205, 178, 255})
}

windmill_lab_sails_draw :: proc(plan: ^windmills.Plan) {
    hub_z := plan.top_radius + .40
    angle_offset := plan.phase
    if !windmill_lab_paused {
        angle_offset += f32(rl.GetTime()) * plan.rpm * math.PI * 2 / 60
    }
    timber := rl.Color{91, 62, 39, 255}
    canvas := rl.Color{218, 207, 170, 245}
    for index in 0 ..< plan.sail_count {
        angle := angle_offset + f32(index) * math.PI * 2 / f32(plan.sail_count)
        radial := third_person.Vec3{math.sin(angle), math.cos(angle), 0}
        tangent := third_person.Vec3{math.cos(angle), -math.sin(angle), 0}
        root_center := third_person.Vec3{radial.x * plan.sail_root, plan.hub_height + radial.y * plan.sail_root, hub_z}
        tip_center := third_person.Vec3 {
            radial.x * plan.sail_length,
            plan.hub_height + radial.y * plan.sail_length,
            hub_z,
        }
        a := root_center - tangent * (plan.sail_root_width * .5)
        b := root_center + tangent * (plan.sail_root_width * .5)
        c := tip_center + tangent * (plan.sail_tip_width * .5)
        d := tip_center - tangent * (plan.sail_tip_width * .5)
        world_quad(a, b, c, d, canvas)
        world_quad(d, c, b, a, canvas)
        // Narrow crossed members make the generated cloth rig legible at distance.
        member_half := tangent * .035
        member_lift := third_person.Vec3{0, 0, .012}
        world_quad(
            root_center - member_half + member_lift,
            root_center + member_half + member_lift,
            tip_center + member_half + member_lift,
            tip_center - member_half + member_lift,
            timber,
        )
    }
    world_vertical_disc_rotated({0, plan.hub_height, hub_z + .05}, plan.hub_radius, plan.hub_radius, .34, 0, timber)
}

world_windmill_generator_lab :: proc(_: ^Editor) {
    ground := rl.Color{151, 132, 89, 255}
    world_box_rotated({0, -.14, 0}, {16, .28, 16}, 0, ground)
    plan := windmills.generate(
        windmill_lab_seed,
        {
            style = windmill_lab_style,
            tower_height = 6.8,
            tower_radius = 2.35,
            sail_count = windmill_lab_sails,
            sail_length = 4.15,
            rpm = windmill_lab_rpm,
        },
    )
    windmill_lab_tower(&plan, windmill_lab_wall_color(plan.style))
    windmill_lab_sails_draw(&plan)
}

windmill_lab_draw_ui :: proc(_: ^Editor, _, _: i32) {
    panel := rl.Rectangle {
        x      = 22,
        y      = 22,
        width  = 500,
        height = 164,
    }
    rl.DrawRectangleRounded(panel, .10, 8, {25, 24, 20, 230})
    rl.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {190, 151, 91, 255})
    rl.DrawTextEx(rl.Font{}, "WINDMILL GENERATOR LAB", {38, 38}, 20, 1, {246, 228, 188, 255})
    status := fmt.ctprintf(
        "SEED %08X   %s   %d SAILS   %.1f RPM%s",
        windmill_lab_seed,
        windmill_lab_style_name(),
        windmill_lab_sails,
        windmill_lab_rpm,
        windmill_lab_paused ? "   PAUSED" : "",
    )
    rl.DrawTextEx(rl.Font{}, status, {38, 72}, 14, 1, {224, 211, 178, 255})
    rl.DrawTextEx(rl.Font{}, "A / D seed     S finish     LEFT / RIGHT sails", {38, 104}, 13, 1, {191, 178, 147, 255})
    rl.DrawTextEx(rl.Font{}, "UP / DOWN speed     SPACE pause", {38, 128}, 13, 1, {191, 178, 147, 255})
    rl.DrawTextEx(
        rl.Font{},
        "Deterministic tapered tower · generated cap and sail rig",
        {38, 152},
        12,
        1,
        {155, 143, 116, 255},
    )
}
