package main

import atmosphere "../packages/atmosphere"
import windows "../packages/facade_windows"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

window_lab_seed := u32(1948)
window_lab_config: windows.Config
window_lab_gallery := true

window_lab_region_name :: proc(region: windows.Region) -> cstring {
    return region == .Adriatic ? "ADRIATIC" : "AEGEAN"
}

window_lab_style_name :: proc(style: windows.Shutter_Style) -> cstring {
    switch style {
    case .Solid:
        return "SOLID SKURE"
    case .Louvered:
        return "LOUVERED"
    case .Persiana:
        return "TILTING PERSIANA"
    }
    return "UNKNOWN"
}

window_lab_state_name :: proc(state: windows.Shutter_State) -> cstring {
    switch state {
    case .Closed:
        return "CLOSED"
    case .Ajar:
        return "AJAR"
    case .Open:
        return "OPEN"
    }
    return "UNKNOWN"
}

window_lab_apply_target :: proc(target: string) -> bool {
    window_lab_seed = 1948
    window_lab_config = windows.defaults(.Adriatic)
    window_lab_gallery = target == "" || target == "gallery"
    switch target {
    case "", "gallery", "adriatic", "adriatic-louvered":
    case "adriatic-solid":
        window_lab_config.shutter_style = .Solid
    case "adriatic-persiana", "persiana":
        window_lab_config.shutter_style = .Persiana
    case "aegean", "aegean-solid":
        window_lab_config = windows.defaults(.Aegean)
    case "aegean-louvered":
        window_lab_config = windows.defaults(.Aegean)
        window_lab_config.shutter_style = .Louvered
    case "closed":
        window_lab_config.shutter_state = .Closed
    case "ajar":
        window_lab_config.shutter_state = .Ajar
        window_lab_config.shutter_angle = .58
    case "open":
    case:
        return false
    }
    return true
}

window_generator_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil || !window_lab_apply_target(target) do return false
    editor.in_map = true
    editor.capture_world_only = false
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    editor.project.sea_level = -20
    atmosphere.set_world_minutes(&editor.atmosphere, 15 * 60 + 40)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    editor.camera_pose = third_person.camera_look_at(
        window_lab_gallery ? third_person.Vec3{0, 7.2, 18.5} : third_person.Vec3{4.8, 4.2, 8.4},
        window_lab_gallery ? third_person.Vec3{0, 4.0, 0} : third_person.Vec3{0, 2.55, 0},
    )
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

window_generator_lab_process_input :: proc(editor: ^Editor) {
    changed_camera := false
    if canvas2d.IsKeyPressed(.G) {
        window_lab_gallery = !window_lab_gallery
        changed_camera = true
    }
    if canvas2d.IsKeyPressed(.R) {
        window_lab_config = windows.defaults(window_lab_config.region == .Adriatic ? .Aegean : .Adriatic)
        window_lab_gallery = false
    }
    if canvas2d.IsKeyPressed(.S) {
        count := int(windows.Shutter_Style.Persiana) + 1
        window_lab_config.shutter_style = windows.Shutter_Style((int(window_lab_config.shutter_style) + 1) % count)
        window_lab_gallery = false
    }
    if canvas2d.IsKeyPressed(.O) {
        count := int(windows.Shutter_State.Open) + 1
        window_lab_config.shutter_state = windows.Shutter_State((int(window_lab_config.shutter_state) + 1) % count)
        switch window_lab_config.shutter_state {
        case .Closed:
            window_lab_config.shutter_angle = 0
        case .Ajar:
            window_lab_config.shutter_angle = .58
        case .Open:
            window_lab_config.shutter_angle = 1.46
        }
        window_lab_gallery = false
    }
    if canvas2d.IsKeyPressed(.LEFT) do window_lab_config.width = max(f32(.65), window_lab_config.width - .08)
    if canvas2d.IsKeyPressed(.RIGHT) do window_lab_config.width = min(f32(1.85), window_lab_config.width + .08)
    if canvas2d.IsKeyPressed(.DOWN) do window_lab_config.height = max(f32(.75), window_lab_config.height - .10)
    if canvas2d.IsKeyPressed(.UP) do window_lab_config.height = min(f32(2.60), window_lab_config.height + .10)
    if canvas2d.IsKeyPressed(.N) do window_lab_seed += 1
    if changed_camera {
        editor.camera_pose = third_person.camera_look_at(
            window_lab_gallery ? third_person.Vec3{0, 7.2, 18.5} : third_person.Vec3{4.8, 4.2, 8.4},
            window_lab_gallery ? third_person.Vec3{0, 4.0, 0} : third_person.Vec3{0, 2.55, 0},
        )
        third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    }
}

window_lab_colors :: proc(plan: ^windows.Plan) -> (wall, surround, timber, glass, iron: canvas2d.Color) {
    if plan.region == .Aegean {
        palettes := [4]canvas2d.Color{{50, 99, 126, 255}, {60, 91, 83, 255}, {151, 103, 52, 255}, {91, 68, 50, 255}}
        return {
            224,
            220,
            198,
            255,
        }, {239, 235, 213, 255}, palettes[int(plan.seed % 4)], {39, 72, 78, 255}, {54, 54, 49, 255}
    }
    palettes := [4]canvas2d.Color{{139, 52, 47, 255}, {55, 88, 72, 255}, {54, 88, 99, 255}, {91, 64, 47, 255}}
    return {
        178,
        166,
        139,
        255,
    }, {205, 194, 168, 255}, palettes[int(plan.seed % 4)], {40, 61, 64, 255}, {54, 51, 46, 255}
}

window_lab_shutter_leaf :: proc(
    plan: ^windows.Plan,
    origin: third_person.Vec3,
    side: f32,
    timber, iron: canvas2d.Color,
) {
    angle := plan.shutter_angle
    hinge_x := origin.x + side * plan.width * .5
    center_x := hinge_x - side * math.cos(angle) * plan.shutter_width * .5
    center_z := origin.z + .12 + math.sin(angle) * plan.shutter_width * .5
    yaw := side * angle
    lower_ratio := plan.lower_panel_ratio
    upper_height := plan.height * (1 - lower_ratio)
    upper_y := origin.y + plan.height * .5 - upper_height * .5
    world_box_rotated(
        {center_x, upper_y, center_z},
        {plan.shutter_width, upper_height, plan.shutter_thickness},
        yaw,
        timber,
    )

    if plan.shutter_style != .Solid {
        usable_height := upper_height - .22
        count := max(3, int(f32(plan.louver_count) * (1 - lower_ratio)))
        for index in 0 ..< count {
            y := upper_y - usable_height * .5 + (f32(index) + .5) * usable_height / f32(count)
            world_box_rotated({center_x, y, center_z + .045}, {plan.shutter_width * .78, .035, .035}, yaw, iron)
        }
    } else {
        world_box_rotated({center_x, upper_y, center_z + .045}, {.045, upper_height * .82, .035}, yaw, iron)
        world_box_rotated({center_x, upper_y, center_z + .047}, {plan.shutter_width * .82, .045, .035}, yaw, iron)
    }

    if plan.shutter_style == .Persiana {
        lower_height := plan.height * lower_ratio
        lower_y := origin.y - plan.height * .5 + lower_height * .5
        kick := lower_height * .23
        world_box_rotated(
            {center_x, lower_y, center_z + kick},
            {plan.shutter_width, lower_height, plan.shutter_thickness},
            yaw,
            timber,
        )
        world_box_rotated(
            {center_x, lower_y, center_z + kick + .045},
            {plan.shutter_width * .78, .04, .035},
            yaw,
            iron,
        )
    }
}

window_lab_draw :: proc(config: windows.Config, seed: u32, origin: third_person.Vec3, panel_width, panel_height: f32) {
    plan := windows.generate(seed, config)
    wall, stone, timber, glass, iron := window_lab_colors(&plan)
    world_box(
        {origin.x, origin.y + panel_height * .5, origin.z - plan.reveal_depth * .5},
        {panel_width, panel_height, plan.reveal_depth},
        wall,
    )
    center := third_person.Vec3{origin.x, origin.y + max(f32(2.15), panel_height * .52), origin.z + .02}
    room_variant := f32(seed % 6)
    room_depth := plan.region == .Aegean ? f32(.62) : f32(.78)
    interior_light := seed % 5 == 1 ? f32(.72) : f32(0)
    world_glass_panel(
        {center.x, center.y, center.z + .025},
        plan.width,
        plan.height,
        0,
        glass,
        interior_light,
        1 + room_variant + room_depth,
    )
    frame_w := plan.surround_width
    world_box(
        {center.x - plan.width * .5 - frame_w * .5, center.y, center.z + .05},
        {frame_w, plan.height + frame_w * 2, plan.surround_depth},
        stone,
    )
    world_box(
        {center.x + plan.width * .5 + frame_w * .5, center.y, center.z + .05},
        {frame_w, plan.height + frame_w * 2, plan.surround_depth},
        stone,
    )
    world_box(
        {center.x, center.y + plan.height * .5 + frame_w * .5, center.z + .05},
        {plan.width, frame_w, plan.surround_depth},
        stone,
    )
    world_box(
        {center.x, center.y - plan.height * .5 - plan.sill_height * .5, center.z + plan.sill_projection * .5},
        {plan.width + frame_w * 2.2, plan.sill_height, plan.surround_depth + plan.sill_projection},
        stone,
    )
    for column in 1 ..< plan.pane_columns {
        x := center.x - plan.width * .5 + f32(column) * plan.width / f32(plan.pane_columns)
        world_box({x, center.y, center.z + .075}, {.035, plan.height, .035}, iron)
    }
    for row in 1 ..< plan.pane_rows {
        y := center.y - plan.height * .5 + f32(row) * plan.height / f32(plan.pane_rows)
        world_box({center.x, y, center.z + .075}, {plan.width, .035, .035}, iron)
    }
    window_lab_shutter_leaf(&plan, center, -1, timber, iron)
    window_lab_shutter_leaf(&plan, center, 1, timber, iron)
}

world_window_generator_lab :: proc(_: ^Editor) {
    world_box({0, -.14, 0}, {18, .28, 10}, {139, 129, 103, 255})
    if !window_lab_gallery {
        window_lab_draw(window_lab_config, window_lab_seed, {0, 0, 0}, 6.2, 5.8)
        return
    }
    configs := [6]windows.Config {
        windows.defaults(.Adriatic),
        windows.defaults(.Adriatic),
        windows.defaults(.Adriatic),
        windows.defaults(.Aegean),
        windows.defaults(.Aegean),
        windows.defaults(.Aegean),
    }
    configs[0].shutter_style, configs[0].shutter_state = .Solid, .Closed
    configs[1].shutter_style = .Louvered
    configs[2].shutter_style, configs[2].shutter_state, configs[2].shutter_angle = .Persiana, .Ajar, .58
    configs[3].shutter_style, configs[3].shutter_state = .Solid, .Closed
    configs[4].shutter_style = .Solid
    configs[5].shutter_style = .Louvered
    for config, index in configs {
        column := index % 3
        row := index / 3
        window_lab_draw(
            config,
            window_lab_seed + u32(index),
            {-5.4 + f32(column) * 5.4, f32(1 - row) * 4.0, 0},
            4.5,
            3.8,
        )
    }
}

window_generator_lab_draw_ui :: proc(_: ^Editor, _: i32, _: i32) {
    panel := canvas2d.Rectangle{24, 24, 720, 118}
    canvas2d.DrawRectangleRounded(panel, .14, 8, {24, 29, 28, 236})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .14, 8, 1, {137, 151, 126, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "PROCEDURAL WINDOW + SHUTTER LAB", {38, 38}, 18, 1, {232, 224, 189, 255})
    summary: cstring = "REGION  /  SHUTTER  /  OPENING  /  SIZE"
    if !window_lab_gallery {
        plan := windows.generate(window_lab_seed, window_lab_config)
        summary = fmt.ctprintf(
            "%s  /  %s  /  %s  /  %.2f x %.2f M  /  %d x %d PANES",
            window_lab_region_name(plan.region),
            window_lab_style_name(plan.shutter_style),
            window_lab_state_name(plan.shutter_state),
            plan.width,
            plan.height,
            plan.pane_columns,
            plan.pane_rows,
        )
    }
    canvas2d.DrawTextEx(canvas2d.Font{}, summary, {38, 68}, 13, 1, {184, 207, 174, 255})
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        "G GALLERY   R REGION   S SHUTTER   O OPENING   ARROWS SIZE   N NEXT VARIANT",
        {38, 96},
        11,
        1,
        {196, 194, 174, 255},
    )
}
