package main

import atmosphere "../packages/atmosphere"
import flowers "../packages/flower_mesh"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

flower_generator_shape := flowers.Petal_Shape.Rounded
flower_generator_arrangement := flowers.Arrangement.Whorled
flower_generator_petals := 5
flower_generator_whorls := 1
flower_generator_isolated := false
flower_generator_stage := flowers.Lifecycle_Stage.Bloom
flower_generator_lifecycle_gallery := false
flower_generator_clustered := false
flower_generator_shape_dropdown_open := false
flower_generator_stage_dropdown_open := false

flower_generator_shape_bounds :: proc() -> canvas2d.Rectangle { return {38, 60, 174, 28} }
flower_generator_stage_bounds :: proc() -> canvas2d.Rectangle { return {224, 60, 174, 28} }
flower_generator_arrangement_bounds :: proc() -> canvas2d.Rectangle { return {410, 60, 112, 28} }
flower_generator_petals_bounds :: proc() -> canvas2d.Rectangle { return {38, 106, 140, 28} }
flower_generator_whorls_bounds :: proc() -> canvas2d.Rectangle { return {190, 106, 104, 28} }
flower_generator_cluster_bounds :: proc() -> canvas2d.Rectangle { return {306, 106, 104, 28} }
flower_generator_gallery_bounds :: proc() -> canvas2d.Rectangle { return {422, 106, 100, 28} }
flower_generator_shape_option_bounds :: proc(index: int) -> canvas2d.Rectangle { return {
        38,
        88 + f32(index) * 25,
        174,
        25,
    } }
flower_generator_stage_option_bounds :: proc(index: int) -> canvas2d.Rectangle { return {
        224,
        88 + f32(index) * 25,
        174,
        25,
    } }

flower_generator_shape_name :: proc(shape: flowers.Petal_Shape) -> string {
    switch shape {
    case .Rounded:
        return "ROUNDED"
    case .Pointed:
        return "POINTED"
    case .Notched:
        return "NOTCHED"
    case .Strap:
        return "STRAP"
    case .Ovate:
        return "OVATE"
    case .Spatulate:
        return "SPATULATE"
    case .Lanceolate:
        return "LANCEOLATE"
    }
    return "UNKNOWN"
}

flower_generator_shape_slug :: proc(shape: flowers.Petal_Shape) -> string {
    switch shape {
    case .Rounded:
        return "rounded"
    case .Pointed:
        return "pointed"
    case .Notched:
        return "notched"
    case .Strap:
        return "strap"
    case .Ovate:
        return "ovate"
    case .Spatulate:
        return "spatulate"
    case .Lanceolate:
        return "lanceolate"
    }
    return ""
}

flower_generator_stage_name :: proc(stage: flowers.Lifecycle_Stage) -> string {
    switch stage {
    case .Bud:
        return "BUD"
    case .Opening:
        return "OPENING"
    case .Half_Open:
        return "HALF OPEN"
    case .Bloom:
        return "BLOOM"
    case .Fruit_Set:
        return "FRUIT SET"
    case .Immature_Fruit:
        return "IMMATURE FRUIT"
    case .Ripening_Fruit:
        return "RIPENING FRUIT"
    case .Ripe_Fruit:
        return "RIPE FRUIT"
    }
    return "UNKNOWN"
}

flower_generator_fruit_for_shape :: proc(shape: flowers.Petal_Shape) -> flowers.Fruit_Shape {
    switch shape {
    case .Rounded:
        return .Berry
    case .Pointed:
        return .Citrus
    case .Notched:
        return .Pome
    case .Strap:
        return .Drupe
    case .Ovate:
        return .Berry
    case .Spatulate:
        return .Pome
    case .Lanceolate:
        return .Citrus
    }
    return .Berry
}

flower_generator_config :: proc(shape: flowers.Petal_Shape) -> flowers.Config {
    config := flowers.defaults()
    config.petal_shape = shape
    switch shape {
    case .Rounded:
        config.petal_count = 5
        config.petal_width = .72
        config.opening_angle = .18
    case .Pointed:
        config.petal_count = 6
        config.petal_width = .58
        config.opening_angle = .30
        config.curl = .16
    case .Notched:
        config.petal_count = 5
        config.petal_width = .78
        config.whorl_count = 2
        config.inner_whorl_scale = .72
    case .Strap:
        config.arrangement = .Spiral
        config.petal_count = 13
        config.petal_width = .28
        config.opening_angle = .10
        config.curl = .06
        config.center_radius = .28
    case .Ovate:
        config.petal_count = 5
        config.petal_width = .82
        config.opening_angle = .22
        config.curl = .08
        config.cup = .11
    case .Spatulate:
        config.petal_count = 6
        config.petal_width = .72
        config.opening_angle = .26
        config.curl = .14
        config.center_radius = .20
    case .Lanceolate:
        config.petal_count = 6
        config.petal_length = 1.18
        config.petal_width = .48
        config.opening_angle = .34
        config.curl = .22
        config.center_radius = .18
    }
    return config
}

flower_generator_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    flower_generator_shape_dropdown_open = false
    flower_generator_stage_dropdown_open = false
    flower_generator_shape = .Rounded
    flower_generator_arrangement = .Whorled
    flower_generator_petals = 5
    flower_generator_whorls = 1
    flower_generator_stage = .Bloom
    flower_generator_lifecycle_gallery = target == "lifecycle"
    flower_generator_clustered = target == "cluster" || target == "bushy-cluster"
    flower_generator_isolated = target != "" && target != "gallery" && target != "lifecycle"
    if flower_generator_clustered {
        flower_generator_shape = .Rounded
        flower_generator_petals = 4
    }
    for shape in flowers.Petal_Shape {
        if target == flower_generator_shape_slug(shape) {
            flower_generator_shape = shape
            profile := flower_generator_config(shape)
            flower_generator_arrangement = profile.arrangement
            flower_generator_petals = profile.petal_count
            flower_generator_whorls = profile.whorl_count
        }
    }
    if target == "spiral" {
        flower_generator_shape = .Strap
        flower_generator_arrangement = .Spiral
        flower_generator_petals = 13
    }
    if target == "double" {
        flower_generator_shape = .Notched
        flower_generator_whorls = 2
    }
    switch target {
    case "bud":
        flower_generator_stage = .Bud
    case "opening":
        flower_generator_stage = .Opening
    case "half-open":
        flower_generator_stage = .Half_Open
    case "bloom":
        flower_generator_stage = .Bloom
    case "set", "fruit-set":
        flower_generator_stage = .Fruit_Set
    case "immature":
        flower_generator_stage = .Immature_Fruit
    case "ripening":
        flower_generator_stage = .Ripening_Fruit
    case "fruit", "ripe":
        flower_generator_stage = .Ripe_Fruit
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
    editor.camera_pose = third_person.camera_look_at({0, 10.5, 13.8}, {0, .7, -1.0})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

flower_generator_lab_process_input :: proc(_: ^Editor) {
    if canvas2d.IsMouseButtonPressed(.LEFT) {
        mouse := canvas2d.GetMousePosition()
        if canvas2d.CheckCollisionPointRec(mouse, flower_generator_shape_bounds()) {
            flower_generator_shape_dropdown_open = !flower_generator_shape_dropdown_open
            flower_generator_stage_dropdown_open = false
        } else if flower_generator_shape_dropdown_open {
            selected := false
            for index in 0 ..= int(flowers.Petal_Shape.Lanceolate) {
                if canvas2d.CheckCollisionPointRec(mouse, flower_generator_shape_option_bounds(index)) {
                    flower_generator_shape = flowers.Petal_Shape(index)
                    flower_generator_isolated = true
                    flower_generator_shape_dropdown_open = false
                    selected = true
                    break
                }
            }
            if !selected do flower_generator_shape_dropdown_open = false
        } else if canvas2d.CheckCollisionPointRec(mouse, flower_generator_stage_bounds()) {
            flower_generator_stage_dropdown_open = !flower_generator_stage_dropdown_open
            flower_generator_shape_dropdown_open = false
        } else if flower_generator_stage_dropdown_open {
            selected := false
            for index in 0 ..= int(flowers.Lifecycle_Stage.Ripe_Fruit) {
                if canvas2d.CheckCollisionPointRec(mouse, flower_generator_stage_option_bounds(index)) {
                    flower_generator_stage = flowers.Lifecycle_Stage(index)
                    flower_generator_isolated = true
                    flower_generator_stage_dropdown_open = false
                    selected = true
                    break
                }
            }
            if !selected do flower_generator_stage_dropdown_open = false
        } else if lab_ui_button_pressed(flower_generator_arrangement_bounds()) {
            flower_generator_arrangement =
                flower_generator_arrangement == .Whorled ? flowers.Arrangement.Spiral : flowers.Arrangement.Whorled
            flower_generator_isolated = true
        } else if lab_ui_button_pressed(flower_generator_whorls_bounds()) {
            flower_generator_whorls = flower_generator_whorls == 1 ? 2 : 1
            flower_generator_isolated = true
        } else if lab_ui_button_pressed(flower_generator_cluster_bounds()) {
            flower_generator_clustered = !flower_generator_clustered
            flower_generator_isolated = true
        } else if lab_ui_button_pressed(flower_generator_gallery_bounds()) {
            flower_generator_lifecycle_gallery = !flower_generator_lifecycle_gallery
            flower_generator_isolated = false
        }
    }
    petals_delta := lab_ui_stepper_delta(flower_generator_petals_bounds())
    if petals_delta != 0 {
        flower_generator_petals = clamp(flower_generator_petals + petals_delta, 1, flowers.MAX_PETALS)
        flower_generator_isolated = true
    }
    if canvas2d.IsKeyPressed(.LEFT) {
        count := int(flowers.Petal_Shape.Lanceolate) + 1
        flower_generator_shape = flowers.Petal_Shape((int(flower_generator_shape) + count - 1) % count)
        flower_generator_isolated = true
    }
    if canvas2d.IsKeyPressed(.RIGHT) {
        count := int(flowers.Petal_Shape.Lanceolate) + 1
        flower_generator_shape = flowers.Petal_Shape((int(flower_generator_shape) + 1) % count)
        flower_generator_isolated = true
    }
    if canvas2d.IsKeyPressed(.A) {
        flower_generator_arrangement =
            flower_generator_arrangement == .Whorled ? flowers.Arrangement.Spiral : flowers.Arrangement.Whorled
        flower_generator_isolated = true
    }
    if canvas2d.IsKeyPressed(.W) {
        flower_generator_whorls = flower_generator_whorls == 1 ? 2 : 1
        flower_generator_isolated = true
    }
    if canvas2d.IsKeyPressed(.ONE) {
        flower_generator_petals = max(1, flower_generator_petals - 1)
        flower_generator_isolated = true
    }
    if canvas2d.IsKeyPressed(.TWO) {
        flower_generator_petals = min(flowers.MAX_PETALS, flower_generator_petals + 1)
        flower_generator_isolated = true
    }
    if canvas2d.IsKeyPressed(.G) do flower_generator_isolated = !flower_generator_isolated
    if canvas2d.IsKeyPressed(.L) {
        count := int(flowers.Lifecycle_Stage.Ripe_Fruit) + 1
        flower_generator_stage = flowers.Lifecycle_Stage((int(flower_generator_stage) + 1) % count)
        flower_generator_isolated = true
    }
    if canvas2d.IsKeyPressed(.F) {
        flower_generator_lifecycle_gallery = !flower_generator_lifecycle_gallery
        flower_generator_isolated = false
    }
    if canvas2d.IsKeyPressed(.C) {
        flower_generator_clustered = !flower_generator_clustered
        flower_generator_isolated = true
    }
}

flower_generator_draw_mesh :: proc(
    config: flowers.Config,
    origin: third_person.Vec3,
    scale: f32,
    petal_color: canvas2d.Color,
    stage: flowers.Lifecycle_Stage = .Bloom,
    draw_stem: bool = true,
    frame_right: third_person.Vec3 = {1, 0, 0},
    frame_up: third_person.Vec3 = {0, 0, -1},
    frame_outward: third_person.Vec3 = {0, 1, 0},
) {
    lifecycle := flowers.Lifecycle_Config {
        stage  = stage,
        flower = config,
        fruit  = flowers.fruit_defaults(flower_generator_fruit_for_shape(config.petal_shape)),
    }
    mesh := flowers.generate_lifecycle(lifecycle)
    center_first := config.petal_count * config.whorl_count * (config.segments + 1) * 3
    center_color := canvas2d.Color{223, 166, 48, 255}
    for first := 0; first + 2 < mesh.index_count; first += 3 {
        points: [3]third_person.Vec3
        normals: [3]third_person.Vec3
        center_triangle := stage == .Bud || stage == .Opening || stage == .Half_Open || stage == .Bloom
        for corner in 0 ..< 3 {
            index := mesh.indices[first + corner]
            source := mesh.vertices[index]
            points[corner] =
                origin +
                frame_right * source.position[0] * scale +
                frame_up * source.position[1] * scale +
                frame_outward * source.position[2] * scale
            normals[corner] = linalg.normalize0(
                frame_right * source.normal[0] + frame_up * source.normal[1] + frame_outward * source.normal[2],
            )
            center_triangle = center_triangle && int(index) >= center_first
        }
        color := center_triangle ? center_color : petal_color
        world_triangle_smooth_lit(
            points[0],
            points[1],
            points[2],
            normals[0],
            normals[1],
            normals[2],
            color,
            color,
            color,
            .88,
        )
        world_triangle_smooth_lit(
            points[2],
            points[1],
            points[0],
            -normals[2],
            -normals[1],
            -normals[0],
            color,
            color,
            color,
            .88,
        )
    }
    if draw_stem {
        world_tube_between(
            {origin.x, .10, origin.z},
            {origin.x, origin.y, origin.z},
            {1, 0, 0},
            .035 * scale,
            .022 * scale,
            {65, 112, 65, 255},
        )
    }
}

flower_generator_draw_cluster :: proc(
    config: flowers.Config,
    origin: third_person.Vec3,
    scale: f32,
    color: canvas2d.Color,
    stage: flowers.Lifecycle_Stage,
) {
    cluster_config := flowers.cluster_defaults(.Ball)
    // Hydrangea-scale preview: many small florets form one continuous puff.
    cluster_config.flower_count = 80
    // Keep the same floret-to-envelope ratio used by the hydrangea plant:
    // broad in plan, shallow in profile, and close enough to overlap.
    cluster_config.radius = .72
    cluster_config.height = .46
    cluster_config.floret_scale = .18
    cluster_config.scale_variation = .12
    cluster := flowers.generate_cluster(cluster_config)
    for instance in cluster.instances[:cluster.count] {
        floret_origin :=
            origin +
            third_person.Vec3 {
                    instance.position[0] * scale,
                    instance.position[2] * scale,
                    -instance.position[1] * scale,
                }
        floret_outward := linalg.normalize0(
            third_person.Vec3{instance.normal[0], instance.normal[2], -instance.normal[1]},
        )
        floret_right :=
            third_person.Vec3{1, 0, 0} - floret_outward * linalg.dot(third_person.Vec3{1, 0, 0}, floret_outward)
        if linalg.dot(floret_right, floret_right) < .001 {
            floret_right =
                third_person.Vec3{0, 0, -1} - floret_outward * linalg.dot(third_person.Vec3{0, 0, -1}, floret_outward)
        }
        floret_right = linalg.normalize0(floret_right)
        floret_up := linalg.normalize0(linalg.cross(floret_outward, floret_right))
        cosine, sine := math.cos(instance.rotation), math.sin(instance.rotation)
        rotated_right := linalg.normalize0(floret_right * cosine + floret_up * sine)
        rotated_up := linalg.normalize0(-floret_right * sine + floret_up * cosine)
        flower_generator_draw_mesh(
            config,
            floret_origin,
            scale * instance.scale,
            color,
            stage,
            false,
            rotated_right,
            rotated_up,
            floret_outward,
        )
    }
    world_tube_between({origin.x, .10, origin.z}, origin, {1, 0, 0}, .035 * scale, .022 * scale, {65, 112, 65, 255})
}

world_flower_generator_lab :: proc(_: ^Editor) {
    world_box({0, -.16, -1.5}, {15, .3, 16}, {192, 183, 151, 255})
    if flower_generator_isolated {
        config := flower_generator_config(flower_generator_shape)
        config.arrangement = flower_generator_arrangement
        config.petal_count = flower_generator_petals
        config.whorl_count = flower_generator_whorls
        color := canvas2d.Color{222, 114, 145, 255}
        if flower_generator_stage == .Fruit_Set do color = {112, 151, 72, 255}
        if flower_generator_stage == .Immature_Fruit do color = {91, 143, 66, 255}
        if flower_generator_stage == .Ripening_Fruit do color = {183, 145, 58, 255}
        if flower_generator_stage == .Ripe_Fruit do color = {211, 145, 48, 255}
        if flower_generator_clustered {
            flower_generator_draw_cluster(config, {0, .55, 1.2}, 2.7, color, flower_generator_stage)
        } else {
            flower_generator_draw_mesh(config, {0, .55, 1.2}, 2.7, color, flower_generator_stage)
        }
        return
    }
    if flower_generator_lifecycle_gallery {
        stages := [8]flowers.Lifecycle_Stage {
            .Bud,
            .Opening,
            .Half_Open,
            .Bloom,
            .Fruit_Set,
            .Immature_Fruit,
            .Ripening_Fruit,
            .Ripe_Fruit,
        }
        colors := [8]canvas2d.Color {
            {174, 91, 119, 255},
            {202, 119, 145, 255},
            {224, 160, 178, 255},
            {238, 206, 207, 255},
            {112, 151, 72, 255},
            {91, 143, 66, 255},
            {183, 145, 58, 255},
            {218, 156, 48, 255},
        }
        for stage, index in stages {
            column := index % 4
            row := index / 4
            config := flower_generator_config(.Rounded)
            flower_generator_draw_mesh(
                config,
                {-4.5 + f32(column) * 3.0, .42, 2.5 - f32(row) * 4.8},
                1.18,
                colors[index],
                stage,
            )
        }
        return
    }
    shapes := [7]flowers.Petal_Shape{.Rounded, .Pointed, .Notched, .Strap, .Ovate, .Spatulate, .Lanceolate}
    colors := [7]canvas2d.Color {
        {238, 206, 207, 255},
        {237, 188, 79, 255},
        {220, 111, 149, 255},
        {170, 132, 201, 255},
        {230, 151, 177, 255},
        {241, 220, 153, 255},
        {194, 151, 211, 255},
    }
    for shape, index in shapes {
        column := index % 4
        row := index / 4
        config := flower_generator_config(shape)
        flower_generator_draw_mesh(config, {-5.1 + f32(column) * 3.4, .45, 2.8 - f32(row) * 5.2}, 1.28, colors[index])
    }
}

flower_generator_lab_draw_ui :: proc(_: ^Editor, width: i32, height: i32) {
    panel := canvas2d.Rectangle{24, 24, 650, 124}
    canvas2d.DrawRectangleRounded(panel, .14, 8, {19, 31, 27, 232})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .14, 8, 1, {111, 146, 111, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "FLOWER MESH GENERATOR", {38, 38}, 18, 1, {232, 224, 189, 255})
    arrangement: cstring = flower_generator_arrangement == .Whorled ? "WHORLED" : "SPIRAL"
    lab_ui_draw_button(
        flower_generator_shape_bounds(),
        fmt.ctprintf(
            "%s  %s",
            flower_generator_shape_name(flower_generator_shape),
            flower_generator_shape_dropdown_open ? "^" : "v",
        ),
        flower_generator_isolated,
    )
    lab_ui_draw_button(
        flower_generator_stage_bounds(),
        fmt.ctprintf(
            "%s  %s",
            flower_generator_stage_name(flower_generator_stage),
            flower_generator_stage_dropdown_open ? "^" : "v",
        ),
        flower_generator_isolated,
    )
    lab_ui_draw_button(flower_generator_arrangement_bounds(), arrangement, true)
    lab_ui_draw_stepper(flower_generator_petals_bounds(), fmt.ctprintf("%d PETALS", flower_generator_petals))
    lab_ui_draw_button(
        flower_generator_whorls_bounds(),
        fmt.ctprintf("%d WHORL%s", flower_generator_whorls, flower_generator_whorls == 1 ? "" : "S"),
        flower_generator_whorls > 1,
    )
    lab_ui_draw_button(flower_generator_cluster_bounds(), "CLUSTER", flower_generator_clustered)
    lab_ui_draw_button(
        flower_generator_gallery_bounds(),
        flower_generator_lifecycle_gallery ? "LIFECYCLE" : "GALLERY",
        flower_generator_lifecycle_gallery,
    )
    if flower_generator_lifecycle_gallery {
        labels := [8]cstring{"BUD", "OPENING", "HALF OPEN", "BLOOM", "FRUIT SET", "IMMATURE", "RIPENING", "RIPE"}
        label_x_fractions := [8]f32{.385, .455, .525, .595, .355, .445, .535, .625}
        for label, index in labels {
            row := index / 4
            label_x := f32(width) * label_x_fractions[index]
            label_y := f32(height) * (row == 0 ? f32(.68) : f32(.49))
            bounds := canvas2d.Rectangle{label_x - 5, label_y - 4, 82, 21}
            canvas2d.DrawRectangleRounded(bounds, .3, 6, {19, 31, 27, 210})
            canvas2d.DrawTextEx(canvas2d.Font{}, label, {label_x, label_y}, 9, 1, {232, 224, 189, 255})
        }
    } else if !flower_generator_isolated {
        labels := [7]cstring{"ROUNDED", "POINTED", "NOTCHED", "STRAP", "OVATE", "SPATULATE", "LANCEOLATE"}
        label_x_fractions := [7]f32{.366, .434, .503, .573, .336, .420, .512}
        for label, index in labels {
            row := index / 4
            label_x := f32(width) * label_x_fractions[index]
            label_y := f32(height) * (row == 0 ? f32(.49) : f32(.66))
            bounds := canvas2d.Rectangle{label_x - 5, label_y - 4, 82, 21}
            canvas2d.DrawRectangleRounded(bounds, .3, 6, {19, 31, 27, 210})
            canvas2d.DrawTextEx(canvas2d.Font{}, label, {label_x, label_y}, 9, 1, {232, 224, 189, 255})
        }
    }
    if flower_generator_shape_dropdown_open {
        for index in 0 ..= int(flowers.Petal_Shape.Lanceolate) {
            bounds := flower_generator_shape_option_bounds(index)
            selected := index == int(flower_generator_shape)
            hovered := canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), bounds)
            canvas2d.DrawRectangleRec(
                bounds,
                (selected || hovered) ? canvas2d.Color{57, 68, 63, 255} : canvas2d.Color{29, 35, 33, 250},
            )
            canvas2d.DrawTextEx(
                canvas2d.Font{},
                fmt.ctprintf("%s", flower_generator_shape_name(flowers.Petal_Shape(index))),
                {bounds.x + 10, bounds.y + 6},
                11,
                1,
                {232, 224, 189, 255},
            )
        }
    }
    if flower_generator_stage_dropdown_open {
        for index in 0 ..= int(flowers.Lifecycle_Stage.Ripe_Fruit) {
            bounds := flower_generator_stage_option_bounds(index)
            selected := index == int(flower_generator_stage)
            hovered := canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), bounds)
            canvas2d.DrawRectangleRec(
                bounds,
                (selected || hovered) ? canvas2d.Color{57, 68, 63, 255} : canvas2d.Color{29, 35, 33, 250},
            )
            canvas2d.DrawTextEx(
                canvas2d.Font{},
                fmt.ctprintf("%s", flower_generator_stage_name(flowers.Lifecycle_Stage(index))),
                {bounds.x + 10, bounds.y + 6},
                11,
                1,
                {232, 224, 189, 255},
            )
        }
    }
}
