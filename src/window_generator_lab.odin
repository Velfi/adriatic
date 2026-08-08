package main

import atmosphere "../packages/atmosphere"
import windows "../packages/facade_windows"
import "core:fmt"
import "core:math"
import canvas2d "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

window_lab_seed := u32(1948)
window_lab_config: windows.Config
window_lab_gallery := true
window_lab_interior_gallery := false
window_lab_room_review := false
window_lab_purpose_gallery := false
window_lab_daylight := false
window_lab_interior_dropdown_open := false
window_lab_slider_dragging := -1

Window_Lab_Interior :: enum u8 {
    Dwelling,
    Shop,
    Workshop,
    Storehouse,
    Civic,
    Clinic,
}

window_lab_interior := Window_Lab_Interior.Dwelling

window_lab_interior_dropdown_bounds :: proc() -> canvas2d.Rectangle {
    return {520, 54, 210, 28}
}

window_lab_interior_option_bounds :: proc(index: int) -> canvas2d.Rectangle {
    bounds := window_lab_interior_dropdown_bounds()
    return {bounds.x, bounds.y + bounds.height + f32(index) * 26, bounds.width, 26}
}

window_lab_button_bounds :: proc(index: int) -> canvas2d.Rectangle {
    widths := [8]f32{82, 92, 76, 64, 70, 78, 82, 74}
    x := f32(38)
    for item in 0 ..< index do x += widths[item] + 7
    return {x, 96, widths[index], 24}
}

window_lab_button_pressed :: proc(index: int) -> bool {
    return(
        canvas2d.IsMouseButtonPressed(.LEFT) &&
        canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), window_lab_button_bounds(index)) \
    )
}

window_lab_slider_bounds :: proc(index: int) -> canvas2d.Rectangle {
    return {38 + f32(index) * 342, 130, 318, 24}
}

window_lab_set_slider :: proc(index: int, mouse_x: f32) {
    bounds := window_lab_slider_bounds(index)
    track_x := bounds.x + 74
    track_width := bounds.width - 126
    normalized := clamp((mouse_x - track_x) / track_width, f32(0), f32(1))
    if index == 0 {
        window_lab_config.width = .65 + normalized * (1.85 - .65)
    } else {
        window_lab_config.height = .75 + normalized * (2.60 - .75)
    }
    window_lab_gallery = false
}

window_lab_interior_name :: proc(interior: Window_Lab_Interior) -> cstring {
    switch interior {
    case .Dwelling:
        return "DWELLING"
    case .Shop:
        return "SHOP"
    case .Workshop:
        return "WORKSHOP"
    case .Storehouse:
        return "STOREHOUSE"
    case .Civic:
        return "CIVIC"
    case .Clinic:
        return "CLINIC"
    }
    return "UNKNOWN"
}

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
    window_lab_interior_gallery =
        target == "interiors" ||
        target == "interiors-day" ||
        target == "purpose-gallery" ||
        target == "purpose-gallery-day" ||
        target == "room-review" ||
        target == "room-review-day" ||
        target == "room-review-shop" ||
        target == "room-review-workshop" ||
        target == "room-review-storehouse" ||
        target == "room-review-civic" ||
        target == "room-review-clinic"
    window_lab_room_review = window_lab_interior_gallery && target != "interiors" && target != "interiors-day"
    window_lab_purpose_gallery = target == "purpose-gallery" || target == "purpose-gallery-day"
    window_lab_daylight = target == "interiors-day" || target == "purpose-gallery-day" || target == "room-review-day"
    if window_lab_purpose_gallery do window_lab_room_review = false
    window_lab_interior = .Dwelling
    switch target {
    case "",
         "gallery",
         "interiors",
         "interiors-day",
         "purpose-gallery",
         "purpose-gallery-day",
         "room-review",
         "room-review-day",
         "adriatic",
         "adriatic-louvered":
    case "room-review-shop":
        window_lab_interior = .Shop
    case "room-review-workshop":
        window_lab_interior = .Workshop
    case "room-review-storehouse":
        window_lab_interior = .Storehouse
    case "room-review-civic":
        window_lab_interior = .Civic
    case "room-review-clinic":
        window_lab_interior = .Clinic
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
    case "dwelling":
        window_lab_interior_gallery = true
    case "shop":
        window_lab_interior_gallery = true
        window_lab_interior = .Shop
    case "workshop":
        window_lab_interior_gallery = true
        window_lab_interior = .Workshop
    case "storehouse":
        window_lab_interior_gallery = true
        window_lab_interior = .Storehouse
    case "civic":
        window_lab_interior_gallery = true
        window_lab_interior = .Civic
    case "clinic":
        window_lab_interior_gallery = true
        window_lab_interior = .Clinic
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
    atmosphere.set_world_minutes(
        &editor.atmosphere,
        window_lab_daylight || !window_lab_interior_gallery ? 15 * 60 + 40 : 19 * 60 + 20,
    )
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    // Gallery framing prioritizes pane pixels so material differences survive captures.
    editor.camera_pose = third_person.camera_look_at(
        window_lab_room_review ? third_person.Vec3{.85, 2.80, 2.70} : (window_lab_interior_gallery ? third_person.Vec3{0, 4.8, 9.5} : (window_lab_gallery ? third_person.Vec3{0, 7.2, 18.5} : third_person.Vec3{4.8, 4.2, 8.4})),
        window_lab_room_review ? third_person.Vec3{0, 2.55, 0} : (window_lab_interior_gallery ? third_person.Vec3{0, 3.80, 0} : (window_lab_gallery ? third_person.Vec3{0, 4.0, 0} : third_person.Vec3{0, 2.55, 0})),
    )
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

window_generator_lab_process_input :: proc(editor: ^Editor) {
    changed_camera := false
    if canvas2d.IsMouseButtonPressed(.LEFT) {
        mouse := canvas2d.GetMousePosition()
        dropdown := window_lab_interior_dropdown_bounds()
        if canvas2d.CheckCollisionPointRec(mouse, dropdown) {
            window_lab_interior_dropdown_open = !window_lab_interior_dropdown_open
        } else if window_lab_interior_dropdown_open {
            selected := false
            for index in 0 ..= int(Window_Lab_Interior.Clinic) {
                if canvas2d.CheckCollisionPointRec(mouse, window_lab_interior_option_bounds(index)) {
                    window_lab_interior = Window_Lab_Interior(index)
                    window_lab_interior_gallery = true
                    window_lab_gallery = false
                    window_lab_purpose_gallery = false
                    window_lab_interior_dropdown_open = false
                    selected = true
                    break
                }
            }
            if !selected do window_lab_interior_dropdown_open = false
        }
    }
    if canvas2d.IsKeyPressed(.G) || window_lab_button_pressed(0) {
        window_lab_gallery = !window_lab_gallery
        window_lab_interior_gallery = false
        window_lab_room_review = false
        window_lab_purpose_gallery = false
        changed_camera = true
    }
    if canvas2d.IsKeyPressed(.I) || window_lab_button_pressed(1) {
        window_lab_interior_gallery = !window_lab_interior_gallery
        window_lab_gallery = false
        window_lab_room_review = false
        window_lab_purpose_gallery = false
        changed_camera = true
    }
    if canvas2d.IsKeyPressed(.C) || window_lab_button_pressed(2) {
        window_lab_room_review = !window_lab_room_review
        window_lab_interior_gallery = true
        window_lab_gallery = false
        window_lab_purpose_gallery = false
        changed_camera = true
    }
    if canvas2d.IsKeyPressed(.V) || window_lab_button_pressed(7) {
        window_lab_purpose_gallery = !window_lab_purpose_gallery
        window_lab_interior_gallery = window_lab_purpose_gallery
        window_lab_room_review = false
        window_lab_gallery = false
        changed_camera = true
    }
    if canvas2d.IsKeyPressed(.P) {
        count := int(Window_Lab_Interior.Clinic) + 1
        window_lab_interior = Window_Lab_Interior((int(window_lab_interior) + 1) % count)
        window_lab_interior_gallery = true
        window_lab_gallery = false
        window_lab_purpose_gallery = false
    }
    if canvas2d.IsKeyPressed(.L) || window_lab_button_pressed(3) {
        current_minutes := editor.atmosphere.world_minutes
        dusk := current_minutes < 18 * 60
        window_lab_daylight = !dusk
        atmosphere.set_world_minutes(&editor.atmosphere, dusk ? 19 * 60 + 20 : 15 * 60 + 40)
    }
    if canvas2d.IsKeyPressed(.R) || window_lab_button_pressed(4) {
        window_lab_config = windows.defaults(window_lab_config.region == .Adriatic ? .Aegean : .Adriatic)
        window_lab_gallery = false
    }
    if canvas2d.IsKeyPressed(.S) || window_lab_button_pressed(5) {
        count := int(windows.Shutter_Style.Persiana) + 1
        window_lab_config.shutter_style = windows.Shutter_Style((int(window_lab_config.shutter_style) + 1) % count)
        window_lab_gallery = false
    }
    if canvas2d.IsKeyPressed(.N) || (window_lab_interior_gallery && window_lab_button_pressed(6)) {
        window_lab_seed += 1
    }
    if canvas2d.IsKeyPressed(.O) || (!window_lab_interior_gallery && window_lab_button_pressed(6)) {
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
    if canvas2d.IsMouseButtonPressed(.LEFT) {
        mouse := canvas2d.GetMousePosition()
        for index in 0 ..< 2 {
            if canvas2d.CheckCollisionPointRec(mouse, window_lab_slider_bounds(index)) {
                window_lab_slider_dragging = index
                window_lab_set_slider(index, mouse.x)
                break
            }
        }
    }
    if canvas2d.IsMouseButtonDown(.LEFT) && window_lab_slider_dragging >= 0 {
        window_lab_set_slider(window_lab_slider_dragging, canvas2d.GetMousePosition().x)
    }
    if canvas2d.IsMouseButtonReleased(.LEFT) do window_lab_slider_dragging = -1
    if canvas2d.IsKeyPressed(.LEFT) do window_lab_config.width = max(f32(.65), window_lab_config.width - .08)
    if canvas2d.IsKeyPressed(.RIGHT) do window_lab_config.width = min(f32(1.85), window_lab_config.width + .08)
    if canvas2d.IsKeyPressed(.DOWN) do window_lab_config.height = max(f32(.75), window_lab_config.height - .10)
    if canvas2d.IsKeyPressed(.UP) do window_lab_config.height = min(f32(2.60), window_lab_config.height + .10)
    if changed_camera {
        editor.camera_pose = third_person.camera_look_at(
            window_lab_room_review ? third_person.Vec3{.85, 2.80, 2.70} : (window_lab_interior_gallery ? third_person.Vec3{0, 4.8, 9.5} : (window_lab_gallery ? third_person.Vec3{0, 7.2, 18.5} : third_person.Vec3{4.8, 4.2, 8.4})),
            window_lab_room_review ? third_person.Vec3{0, 2.55, 0} : (window_lab_interior_gallery ? third_person.Vec3{0, 3.80, 0} : (window_lab_gallery ? third_person.Vec3{0, 4.0, 0} : third_person.Vec3{0, 2.55, 0})),
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

window_lab_draw :: proc(
    config: windows.Config,
    seed: u32,
    origin: third_person.Vec3,
    panel_width, panel_height: f32,
    interior_variant: int = -1,
    show_shutters: bool = true,
) {
    plan := windows.generate(seed, config)
    wall, stone, timber, glass, iron := window_lab_colors(&plan)
    world_box(
        {origin.x, origin.y + panel_height * .5, origin.z - plan.reveal_depth * .5},
        {panel_width, panel_height, plan.reveal_depth},
        wall,
    )
    center := third_person.Vec3{origin.x, origin.y + max(f32(2.15), panel_height * .52), origin.z + .02}
    room_variant := f32(interior_variant >= 0 ? interior_variant : int(seed % 6))
    base_room_depth := plan.region == .Aegean ? f32(.62) : f32(.78)
    // Room depth is also the deterministic seed carried by the compact glass
    // payload. A restrained offset lets NEW vary the interior form while all
    // six purpose comparisons remain geometrically matched.
    room_form_offset := (f32((seed >> 9) & 255) / 255 - .5) * .12
    room_depth := clamp(base_room_depth + room_form_offset, f32(.35), f32(.95))
    interior_light :=
        interior_variant >= 0 ? (window_lab_daylight ? f32(.18) : f32(1)) : (seed % 5 == 1 ? f32(.72) : f32(0))
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
    if show_shutters {
        window_lab_shutter_leaf(&plan, center, -1, timber, iron)
        window_lab_shutter_leaf(&plan, center, 1, timber, iron)
    }
}

world_window_generator_lab :: proc(_: ^Editor) {
    world_box({0, -.14, 0}, {18, .28, 10}, {139, 129, 103, 255})
    if window_lab_interior_gallery {
        if window_lab_purpose_gallery {
            // Keep geometry, lighting, and seed matched so only purpose art changes.
            for purpose_index in 0 ..= int(Window_Lab_Interior.Clinic) {
                config := windows.defaults(.Adriatic)
                config.width = 1.65
                config.height = 1.7
                column := purpose_index % 3
                row := purpose_index / 3
                window_lab_draw(
                    config,
                    window_lab_seed,
                    {-4.3 + f32(column) * 4.3, f32(1 - row) * 3.55, 0},
                    3.75,
                    3.3,
                    purpose_index,
                    false,
                )
            }
            return
        }
        if window_lab_room_review {
            config := windows.defaults(.Adriatic)
            config.width = 2.35
            config.height = 1.75
            config.shutter_state = .Open
            config.shutter_angle = 1.46
            window_lab_draw(config, window_lab_seed, {0, 0, 0}, 5.4, 4.8, int(window_lab_interior), false)
            return
        }
        aspects := [6]f32{.38, .62, 1.0, 1.4, 2.15, 3.4}
        for aspect, index in aspects {
            config := windows.defaults(.Adriatic)
            config.height = aspect > 1.3 ? 2.8 / aspect : 2.15
            config.width = config.height * aspect
            config.shutter_state = .Open
            config.shutter_angle = 1.46
            column := index % 3
            row := index / 3
            window_lab_draw(
                config,
                window_lab_seed + u32(index),
                {-4.3 + f32(column) * 4.3, f32(1 - row) * 3.55, 0},
                3.75,
                3.3,
                int(window_lab_interior),
                false,
            )
        }
        return
    }
    if !window_lab_gallery {
        window_lab_draw(window_lab_config, window_lab_seed, {0, 0, 0}, 6.2, 5.8, int(window_lab_interior))
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

window_generator_lab_draw_ui :: proc(_: ^Editor, width, height: i32) {
    panel := canvas2d.Rectangle{24, 24, 720, 166}
    canvas2d.DrawRectangleRounded(panel, .14, 8, {24, 29, 28, 236})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .14, 8, 1, {137, 151, 126, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "PROCEDURAL WINDOW + SHUTTER LAB", {38, 38}, 18, 1, {232, 224, 189, 255})
    summary: cstring = "REGION  /  SHUTTER  /  OPENING  /  SIZE"
    if window_lab_purpose_gallery {
        summary = "SIX PURPOSES  /  MATCHED WINDOWS"
    } else if window_lab_room_review {
        summary = fmt.ctprintf("%s  /  ROOM REVIEW", window_lab_interior_name(window_lab_interior))
    } else if window_lab_interior_gallery {
        summary = fmt.ctprintf("%s  /  SIX WINDOW SHAPES", window_lab_interior_name(window_lab_interior))
    } else if !window_lab_gallery {
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
    button_labels := [8]cstring{"WINDOWS", "INTERIORS", "REVIEW", "LIGHT", "REGION", "SHUTTER", "OPENING", "PURPOSES"}
    if window_lab_interior_gallery do button_labels[6] = "NEW FORM"
    for label, index in button_labels {
        bounds := window_lab_button_bounds(index)
        hovered := canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), bounds)
        active :=
            (index == 0 && window_lab_gallery) ||
            (index == 1 && window_lab_interior_gallery && !window_lab_room_review) ||
            (index == 2 && window_lab_room_review) ||
            (index == 7 && window_lab_purpose_gallery)
        fill :=
            hovered ? canvas2d.Color{67, 78, 71, 255} : (active ? canvas2d.Color{52, 72, 61, 255} : canvas2d.Color{39, 47, 44, 255})
        border := active ? canvas2d.Color{184, 207, 174, 255} : canvas2d.Color{107, 121, 104, 255}
        canvas2d.DrawRectangleRounded(bounds, .14, 6, fill)
        canvas2d.DrawRectangleRoundedLinesEx(bounds, .14, 6, 1, border)
        canvas2d.DrawTextEx(canvas2d.Font{}, label, {bounds.x + 9, bounds.y + 6}, 10, 1, {232, 224, 189, 255})
    }
    slider_labels := [2]cstring{"WIDTH", "HEIGHT"}
    slider_values := [2]f32{window_lab_config.width, window_lab_config.height}
    slider_lows := [2]f32{.65, .75}
    slider_highs := [2]f32{1.85, 2.60}
    for label, index in slider_labels {
        bounds := window_lab_slider_bounds(index)
        track := canvas2d.Rectangle{bounds.x + 74, bounds.y + 9, bounds.width - 126, 6}
        normalized := (slider_values[index] - slider_lows[index]) / (slider_highs[index] - slider_lows[index])
        knob_x := track.x + clamp(normalized, f32(0), f32(1)) * track.width
        hovered := canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), bounds)
        canvas2d.DrawTextEx(canvas2d.Font{}, label, {bounds.x, bounds.y + 6}, 10, 1, {184, 207, 174, 255})
        canvas2d.DrawRectangleRounded(track, .5, 6, {57, 68, 63, 255})
        canvas2d.DrawRectangleRounded({track.x, track.y, knob_x - track.x, track.height}, .5, 6, {137, 151, 126, 255})
        canvas2d.DrawCircleV(
            {knob_x, track.y + track.height * .5},
            hovered || window_lab_slider_dragging == index ? 7 : 6,
            {232, 224, 189, 255},
        )
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            fmt.ctprintf("%.2f M", slider_values[index]),
            {bounds.x + bounds.width - 44, bounds.y + 6},
            10,
            1,
            {232, 224, 189, 255},
        )
    }
    dropdown := window_lab_interior_dropdown_bounds()
    canvas2d.DrawTextEx(canvas2d.Font{}, "PURPOSE", {dropdown.x - 76, dropdown.y + 7}, 11, 1, {184, 207, 174, 255})
    dropdown_hovered := canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), dropdown)
    dropdown_fill := dropdown_hovered ? canvas2d.Color{57, 68, 63, 255} : canvas2d.Color{39, 47, 44, 255}
    canvas2d.DrawRectangleRounded(dropdown, .12, 6, dropdown_fill)
    canvas2d.DrawRectangleRoundedLinesEx(dropdown, .12, 6, 1, {137, 151, 126, 255})
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        window_lab_interior_name(window_lab_interior),
        {dropdown.x + 12, dropdown.y + 7},
        12,
        1,
        {232, 224, 189, 255},
    )
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        window_lab_interior_dropdown_open ? "^" : "v",
        {dropdown.x + dropdown.width - 18, dropdown.y + 7},
        12,
        1,
        {196, 194, 174, 255},
    )
    if window_lab_interior_dropdown_open {
        for index in 0 ..= int(Window_Lab_Interior.Clinic) {
            bounds := window_lab_interior_option_bounds(index)
            hovered := canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), bounds)
            selected := index == int(window_lab_interior)
            fill := (hovered || selected) ? canvas2d.Color{57, 68, 63, 255} : canvas2d.Color{29, 35, 33, 250}
            canvas2d.DrawRectangleRec(bounds, fill)
            canvas2d.DrawRectangleRoundedLinesEx(bounds, 0, 1, 1, {107, 121, 104, 255})
            canvas2d.DrawTextEx(
                canvas2d.Font{},
                window_lab_interior_name(Window_Lab_Interior(index)),
                {bounds.x + 12, bounds.y + 6},
                12,
                1,
                selected ? canvas2d.Color{232, 224, 189, 255} : canvas2d.Color{196, 207, 198, 255},
            )
        }
    }
    if window_lab_purpose_gallery {
        for purpose_index in 0 ..= int(Window_Lab_Interior.Clinic) {
            column := purpose_index % 3
            row := purpose_index / 3
            label := window_lab_interior_name(Window_Lab_Interior(purpose_index))
            label_size := canvas2d.MeasureTextEx(canvas2d.Font{}, label, 11, 1)
            center_x := f32(width) * (.375 + f32(column) * .125)
            label_y := f32(height) * (row == 0 ? .285 : .475)
            canvas2d.DrawTextEx(
                canvas2d.Font{},
                label,
                {center_x - label_size.x * .5, label_y},
                11,
                1,
                {214, 220, 201, 255},
            )
        }
    }
}
