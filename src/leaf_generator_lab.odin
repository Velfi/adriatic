package main

import atmosphere "../packages/atmosphere"
import leaves "../packages/leaf_mesh"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

leaf_generator_shape := leaves.Shape.Elliptic
leaf_generator_serration := f32(0)
leaf_generator_curl := f32(.12)
leaf_generator_isolated := false
leaf_generator_focus_triptych := false

leaf_generator_shape_slug :: proc(shape: leaves.Shape) -> string {
    switch shape {
    case .Elliptic:
        return "elliptic"
    case .Lanceolate:
        return "lanceolate"
    case .Ovate:
        return "ovate"
    case .Cordate:
        return "cordate"
    case .Deltoid:
        return "deltoid"
    case .Lobed:
        return "lobed"
    case .Fig:
        return "fig"
    case .Grapevine:
        return "grape"
    case .Ivy:
        return "ivy"
    case .Cypress_Spray:
        return "cypress-spray"
    }
    return ""
}

leaf_generator_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    leaf_generator_focus_triptych = target == "fig-grape-ivy"
    leaf_generator_isolated = target != "" && !leaf_generator_focus_triptych
    for index in 0 ..< leaves.SHAPE_COUNT {
        if target == leaf_generator_shape_slug(leaves.Shape(index)) {
            leaf_generator_shape = leaves.Shape(index)
        }
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
    editor.camera_pose = third_person.camera_look_at({0, 9.8, 13.5}, {0, 1.7, -1.5})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

leaf_generator_lab_process_input :: proc(_: ^Editor) {
    if canvas2d.IsKeyPressed(.LEFT) {
        leaf_generator_focus_triptych = false
        leaf_generator_shape = leaves.Shape((int(leaf_generator_shape) + leaves.SHAPE_COUNT - 1) % leaves.SHAPE_COUNT)
        leaf_generator_isolated = true
    }
    if canvas2d.IsKeyPressed(.RIGHT) {
        leaf_generator_focus_triptych = false
        leaf_generator_shape = leaves.Shape((int(leaf_generator_shape) + 1) % leaves.SHAPE_COUNT)
        leaf_generator_isolated = true
    }
    if canvas2d.IsKeyPressed(.S) do leaf_generator_serration = leaf_generator_serration > 0 ? 0 : .16
    if canvas2d.IsKeyPressed(.C) do leaf_generator_curl = leaf_generator_curl > .2 ? 0 : leaf_generator_curl + .12
    if canvas2d.IsKeyPressed(.G) {
        leaf_generator_focus_triptych = false
        leaf_generator_isolated = !leaf_generator_isolated
    }
}

leaf_generator_draw_mesh :: proc(shape: leaves.Shape, origin: third_person.Vec3, scale: f32) {
    config := leaves.defaults(shape)
    config.serration = leaf_generator_serration
    config.curl = leaf_generator_curl
    mesh := leaves.generate(config)
    color := canvas2d.Color{73 + u8(int(shape) * 5), 130 + u8(int(shape) * 7), 73, 255}
    for first := 0; first + 2 < mesh.index_count; first += 3 {
        va := mesh.vertices[mesh.indices[first]]
        vb := mesh.vertices[mesh.indices[first + 1]]
        vc := mesh.vertices[mesh.indices[first + 2]]
        a := third_person.Vec3 {
            origin.x + va.position[0] * scale,
            origin.y + va.position[2] * scale,
            origin.z - va.position[1] * scale,
        }
        b := third_person.Vec3 {
            origin.x + vb.position[0] * scale,
            origin.y + vb.position[2] * scale,
            origin.z - vb.position[1] * scale,
        }
        c := third_person.Vec3 {
            origin.x + vc.position[0] * scale,
            origin.y + vc.position[2] * scale,
            origin.z - vc.position[1] * scale,
        }
        normal := linalg.normalize0(linalg.cross(b - a, c - a))
        world_triangle_smooth_lit(a, b, c, normal, normal, normal, color, color, color, .86)
        world_triangle_smooth_lit(c, b, a, -normal, -normal, -normal, color, color, color, .86)
    }
    world_tube_between(
        {origin.x, origin.y, origin.z + config.stem * scale},
        {origin.x, origin.y + leaf_generator_curl * scale, origin.z - config.length * scale},
        {1, 0, 0},
        .018 * scale,
        .009 * scale,
        {204, 222, 153, 255},
    )
}

world_leaf_generator_lab :: proc(_: ^Editor) {
    world_box({0, -.16, -1.5}, {15, .3, 16}, {192, 183, 151, 255})
    if leaf_generator_focus_triptych {
        featured := [3]leaves.Shape{.Fig, .Grapevine, .Ivy}
        for shape, column in featured {
            leaf_generator_draw_mesh(shape, {-4.3 + f32(column) * 4.3, .10, 2.5}, 2.0)
        }
        return
    }
    if leaf_generator_isolated {
        leaf_generator_draw_mesh(leaf_generator_shape, {0, .12, 2.7}, 2.1)
        return
    }
    for index in 0 ..< leaves.SHAPE_COUNT {
        column := index % 3
        row := index / 3
        leaf_generator_draw_mesh(leaves.Shape(index), {-4.2 + f32(column) * 4.2, .10, 4.6 - f32(row) * 4.6}, 1.18)
    }
}

leaf_generator_lab_draw_ui :: proc(_: ^Editor, width: i32, height: i32) {
    panel := canvas2d.Rectangle{24, 24, 590, 118}
    canvas2d.DrawRectangleRounded(panel, .14, 8, {19, 31, 27, 232})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .14, 8, 1, {111, 146, 111, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "LEAF MESH GENERATOR", {38, 38}, 18, 1, {232, 224, 189, 255})
    summary: cstring = "NINE BOTANICAL PROFILES  /  PROCEDURAL INDEXED MESHES"
    if leaf_generator_focus_triptych {
        summary = "FIG / GRAPE / IVY  —  DEDICATED BOTANICAL PROFILES"
    }
    if leaf_generator_isolated {
        summary = fmt.ctprintf(
            "%s  /  SERRATION %.0f%%  /  CURL %.2f",
            leaves.shape_name(leaf_generator_shape),
            leaf_generator_serration * 100,
            leaf_generator_curl,
        )
    }
    canvas2d.DrawTextEx(canvas2d.Font{}, summary, {38, 68}, 13, 1, {174, 207, 160, 255})
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        "LEFT/RIGHT SHAPE   S SERRATION   C CURL   G GALLERY",
        {38, 96},
        11,
        1,
        {184, 191, 174, 255},
    )
    if leaf_generator_focus_triptych {
        names := [3]cstring{"FIG", "GRAPE", "IVY"}
        for name, column in names {
            label_x := f32(width) * (.30 + f32(column) * .20) - 52
            label_y := f32(height) * .69
            bounds := canvas2d.Rectangle{label_x - 8, label_y - 5, 120, 25}
            canvas2d.DrawRectangleRounded(bounds, .3, 6, {19, 31, 27, 210})
            canvas2d.DrawTextEx(canvas2d.Font{}, name, {label_x, label_y}, 11, 1, {232, 224, 189, 255})
        }
    } else if !leaf_generator_isolated {
        for index in 0 ..< leaves.SHAPE_COUNT {
            column := index % 3
            row := index / 3
            label_x := f32(width) * (.38 + f32(column) * .12) - 52
            display_row := 2 - row
            label_y := f32(height) * (.49 + f32(display_row) * .17)
            bounds := canvas2d.Rectangle{label_x - 8, label_y - 5, 120, 25}
            canvas2d.DrawRectangleRounded(bounds, .3, 6, {19, 31, 27, 210})
            canvas2d.DrawTextEx(
                canvas2d.Font{},
                fmt.ctprintf("%s", leaves.shape_name(leaves.Shape(index))),
                {label_x, label_y},
                11,
                1,
                {232, 224, 189, 255},
            )
        }
    }
}
