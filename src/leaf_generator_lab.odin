package main

import atmosphere "../packages/atmosphere"
import leaves "../packages/leaf_mesh"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

leaf_generator_shape := leaves.Shape.Elliptic
leaf_generator_serration := f32(0)
leaf_generator_curl := f32(.12)
leaf_generator_isolated := false
leaf_generator_focus_triptych := false
leaf_generator_veins := true
leaf_generator_shape_dropdown_open := false

leaf_generator_shape_dropdown_bounds :: proc() -> canvas2d.Rectangle { return {38, 60, 210, 28} }
leaf_generator_shape_option_bounds :: proc(index: int) -> canvas2d.Rectangle { return {
        38,
        88 + f32(index) * 25,
        210,
        25,
    } }
leaf_generator_gallery_bounds :: proc() -> canvas2d.Rectangle { return {260, 60, 92, 28} }
leaf_generator_texture_bounds :: proc() -> canvas2d.Rectangle { return {364, 60, 92, 28} }
leaf_generator_edge_bounds :: proc() -> canvas2d.Rectangle { return {38, 101, 128, 28} }
leaf_generator_curl_bounds :: proc() -> canvas2d.Rectangle { return {178, 101, 128, 28} }

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
    case .Pine_Needle_Clump:
        return "pine-needle-clump"
    }
    return ""
}

leaf_generator_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    leaf_generator_focus_triptych = target == "fig-grape-ivy"
    leaf_generator_shape_dropdown_open = false
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
    // Face the specimen board nearly square-on. Mesh depth still preserves
    // curl and cupping, while the regular elevation makes the gallery read as
    // an upright botanical pinboard rather than objects laid on a table.
    editor.camera_pose = third_person.camera_look_at({0, 5.2, 8.5}, {0, 5.2, -1.5})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

leaf_generator_lab_process_input :: proc(_: ^Editor) {
    if canvas2d.IsMouseButtonPressed(.LEFT) {
        mouse := canvas2d.GetMousePosition()
        if canvas2d.CheckCollisionPointRec(mouse, leaf_generator_shape_dropdown_bounds()) {
            leaf_generator_shape_dropdown_open = !leaf_generator_shape_dropdown_open
        } else if leaf_generator_shape_dropdown_open {
            selected := false
            for index in 0 ..< leaves.SHAPE_COUNT {
                if canvas2d.CheckCollisionPointRec(mouse, leaf_generator_shape_option_bounds(index)) {
                    leaf_generator_shape = leaves.Shape(index)
                    leaf_generator_focus_triptych = false
                    leaf_generator_isolated = true
                    leaf_generator_shape_dropdown_open = false
                    selected = true
                    break
                }
            }
            if !selected do leaf_generator_shape_dropdown_open = false
        } else if canvas2d.CheckCollisionPointRec(mouse, leaf_generator_gallery_bounds()) {
            leaf_generator_focus_triptych = false
            leaf_generator_isolated = !leaf_generator_isolated
        } else if canvas2d.CheckCollisionPointRec(mouse, leaf_generator_texture_bounds()) {
            leaf_generator_veins = !leaf_generator_veins
        } else if canvas2d.CheckCollisionPointRec(mouse, leaf_generator_edge_bounds()) {
            leaf_generator_serration = leaf_generator_serration > 0 ? 0 : .16
        } else if canvas2d.CheckCollisionPointRec(mouse, leaf_generator_curl_bounds()) {
            leaf_generator_curl = leaf_generator_curl > .2 ? 0 : leaf_generator_curl + .12
        }
    }
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
    if canvas2d.IsKeyPressed(.V) do leaf_generator_veins = !leaf_generator_veins
}

leaf_generator_palette :: proc(shape: leaves.Shape) -> (base, tip: canvas2d.Color) {
    switch shape {
    case .Elliptic:
        return {55, 105, 58, 255}, {78, 139, 70, 255}
    case .Lanceolate:
        return {50, 101, 65, 255}, {72, 134, 76, 255}
    case .Ovate:
        return {65, 112, 55, 255}, {92, 149, 70, 255}
    case .Cordate:
        return {46, 95, 53, 255}, {72, 130, 66, 255}
    case .Deltoid:
        return {62, 111, 58, 255}, {91, 150, 74, 255}
    case .Lobed:
        return {68, 108, 47, 255}, {103, 148, 63, 255}
    case .Fig:
        return {68, 102, 60, 255}, {103, 139, 77, 255}
    case .Grapevine:
        return {76, 114, 51, 255}, {116, 151, 64, 255}
    case .Ivy:
        return {38, 89, 54, 255}, {63, 127, 66, 255}
    case .Cypress_Spray:
        return {49, 101, 52, 255}, {80, 138, 62, 255}
    case .Pine_Needle_Clump:
        return {39, 83, 47, 255}, {69, 118, 58, 255}
    }
    return {58, 105, 58, 255}, {82, 140, 70, 255}
}

leaf_generator_pigment :: #force_inline proc(base, tip: canvas2d.Color, uv: [2]f32) -> canvas2d.Color {
    // Concentrate chlorophyll subtly toward the petiolar end, then lift the
    // terminal tissue without introducing a painted linear ramp.
    t := clamp((uv.y - .05) / .90, f32(0), f32(1))
    t = t * t * (3 - 2 * t)
    return color_lerp(base, tip, t * .72)
}

leaf_generator_effective_serration :: #force_inline proc(shape: leaves.Shape) -> f32 {
    // The global control is an inspection boost, not a replacement for each
    // botanical profile's authored edge character.
    return max(leaves.defaults(shape).serration, leaf_generator_serration)
}

leaf_generator_board_point :: #force_inline proc(
    position: [3]f32,
    origin: third_person.Vec3,
    scale: f32,
) -> third_person.Vec3 {
    return {origin.x + position[0] * scale, origin.y + position[1] * scale, origin.z + position[2] * scale}
}

leaf_generator_gallery_layout :: #force_inline proc(index: int) -> (origin: third_person.Vec3, scale: f32) {
    column := index % 5
    row := index / 5
    shape := leaves.Shape(index)
    origin = {-5.6 + f32(column) * 2.8, 4.8 - f32(row) * 4.2, -1.25}
    scale = shape == .Cypress_Spray || shape == .Pine_Needle_Clump ? f32(.45) : f32(.82)
    return
}

leaf_generator_draw_mesh :: proc(shape: leaves.Shape, origin: third_person.Vec3, scale: f32) {
    config := leaves.defaults(shape)
    config.serration = leaf_generator_effective_serration(shape)
    config.curl = leaf_generator_curl
    mesh := leaves.generate(config)
    base_color, tip_color := leaf_generator_palette(shape)
    if shape != .Cypress_Spray && shape != .Pine_Needle_Clump && config.stem > 0 {
        // Mesh-local +Y runs from the petiolar junction into the blade.
        // Continue the petiole in the opposite direction
        // so it attaches at the base instead of crossing the lamina.
        // Palmate profiles begin at an inset petiolar notch rather than local
        // Y=0. Find the lowest centerline vertex so the tube meets the actual
        // blade boundary instead of ending in front of it with a visible gap.
        junction := mesh.vertices[0].position
        junction_y := f32(1e9)
        for vertex in mesh.vertices[:mesh.vertex_count] {
            if math.abs(vertex.position[0]) <= .0001 && vertex.position[1] < junction_y {
                junction = vertex.position
                junction_y = vertex.position[1]
            }
        }
        petiole_base := leaf_generator_board_point(junction, origin, scale)
        petiole_tip := third_person.Vec3{petiole_base.x, petiole_base.y - config.stem * scale, origin.z + .006 * scale}
        radius := max(config.width * scale * .018, f32(.012))
        petiole_color := canvas2d.Color {
            max(base_color.r, u8(58)) - 14,
            max(base_color.g, u8(92)) - 18,
            max(base_color.b, u8(54)) - 10,
            255,
        }
        world_tube_between(petiole_tip, petiole_base, {1, 0, 0}, radius * .58, radius, petiole_color)
    }
    for first := 0; first + 2 < mesh.index_count; first += 3 {
        va := mesh.vertices[mesh.indices[first]]
        vb := mesh.vertices[mesh.indices[first + 1]]
        vc := mesh.vertices[mesh.indices[first + 2]]
        a := leaf_generator_board_point(va.position, origin, scale)
        b := leaf_generator_board_point(vb.position, origin, scale)
        c := leaf_generator_board_point(vc.position, origin, scale)
        // The mesh generator accumulates smooth normals across its curved
        // surface. Preserve them through the local-to-world axis transform;
        // recomputing one face normal here made every longitudinal segment
        // read as a hard accordion fold.
        normal_a := linalg.normalize0(third_person.Vec3{va.normal[0], va.normal[1], va.normal[2]})
        normal_b := linalg.normalize0(third_person.Vec3{vb.normal[0], vb.normal[1], vb.normal[2]})
        normal_c := linalg.normalize0(third_person.Vec3{vc.normal[0], vc.normal[1], vc.normal[2]})
        color_a := leaf_generator_pigment(base_color, tip_color, va.uv)
        color_b := leaf_generator_pigment(base_color, tip_color, vb.uv)
        color_c := leaf_generator_pigment(base_color, tip_color, vc.uv)
        if leaf_generator_veins {
            if shape == .Pine_Needle_Clump {
                world_triangle_foliage(a, b, c, base_color, base_color, tip_color, normal_a, normal_b, normal_c, .Leaf)
                world_triangle_foliage(
                    c,
                    b,
                    a,
                    tip_color,
                    base_color,
                    base_color,
                    -normal_c,
                    -normal_b,
                    -normal_a,
                    .Leaf,
                )
                continue
            }
            world_triangle_leaf_textured(
                a,
                b,
                c,
                color_a,
                color_b,
                color_c,
                normal_a,
                normal_b,
                normal_c,
                va.uv,
                vb.uv,
                vc.uv,
                u32(shape),
            )
            world_triangle_leaf_textured(
                c,
                b,
                a,
                color_c,
                color_b,
                color_a,
                -normal_c,
                -normal_b,
                -normal_a,
                vc.uv,
                vb.uv,
                va.uv,
                u32(shape),
            )
        } else {
            world_triangle_foliage(a, b, c, color_a, color_b, color_c, normal_a, normal_b, normal_c, .Leaf)
            world_triangle_foliage(c, b, a, color_c, color_b, color_a, -normal_c, -normal_b, -normal_a, .Leaf)
        }
    }
}

world_leaf_generator_lab :: proc(_: ^Editor) {
    // A shallow upright backing keeps the leaves visibly three-dimensional
    // while presenting the collection like pinned botanical specimens.
    // A 16 x 12 backing preserves the requested 8:6 pinboard proportion.
    world_box({0, 4.0, -1.5}, {16, 12, .32}, {113, 126, 113, 255})
    if leaf_generator_focus_triptych {
        featured := [3]leaves.Shape{.Fig, .Grapevine, .Ivy}
        for shape, column in featured {
            leaf_generator_draw_mesh(shape, {-4.3 + f32(column) * 4.3, 3.0, -1.25}, 2.0)
        }
        return
    }
    if leaf_generator_isolated {
        leaf_generator_draw_mesh(leaf_generator_shape, {0, 2.8, -1.25}, 1.75)
        return
    }
    for index in 0 ..< leaves.SHAPE_COUNT {
        shape := leaves.Shape(index)
        origin, specimen_scale := leaf_generator_gallery_layout(index)
        leaf_generator_draw_mesh(shape, origin, specimen_scale)
    }
}

leaf_generator_projected_bounds :: proc(
    editor: ^Editor,
    shape: leaves.Shape,
    origin: third_person.Vec3,
    scale: f32,
    width, height: i32,
) -> (
    canvas2d.Rectangle,
    bool,
) {
    if editor == nil do return {}, false
    config := leaves.defaults(shape)
    config.serration = leaf_generator_effective_serration(shape)
    config.curl = leaf_generator_curl
    mesh := leaves.generate(config)
    camera := perspective_camera(editor.camera_pose)
    min_x, min_y := f32(1e9), f32(1e9)
    max_x, max_y := f32(-1e9), f32(-1e9)
    projected_count := 0
    for vertex in mesh.vertices[:mesh.vertex_count] {
        point := leaf_generator_board_point(vertex.position, origin, scale)
        projected := project_3d(camera, point, width, height)
        if !projected.visible do continue
        min_x = min(min_x, projected.position.x)
        min_y = min(min_y, projected.position.y)
        max_x = max(max_x, projected.position.x)
        max_y = max(max_y, projected.position.y)
        projected_count += 1
    }
    if projected_count == 0 do return {}, false
    return {min_x, min_y, max_x - min_x, max_y - min_y}, true
}

leaf_generator_draw_label :: proc(
    editor: ^Editor,
    shape: leaves.Shape,
    origin: third_person.Vec3,
    scale: f32,
    width, height: i32,
) {
    silhouette, visible := leaf_generator_projected_bounds(editor, shape, origin, scale, width, height)
    if !visible do return
    style := world_label_style(.Below)
    // Projected mesh bounds exclude the separately rendered petiole. Leave a
    // full stem-sized gutter so the label identifies the blade without
    // covering its attachment.
    style.gap = 24
    anchor := canvas2d.Vector2{silhouette.x + silhouette.width * .5, silhouette.y + silhouette.height}
    _ = screen_label_draw(anchor, width, height, fmt.ctprintf("%s", leaves.shape_name(shape)), style)
}

leaf_generator_lab_draw_ui :: proc(editor: ^Editor, width: i32, height: i32) {
    panel := canvas2d.Rectangle{24, 24, 590, 120}
    canvas2d.DrawRectangleRounded(panel, .14, 8, {19, 31, 27, 232})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .14, 8, 1, {111, 146, 111, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "LEAF MESH GENERATOR", {38, 38}, 18, 1, {232, 224, 189, 255})
    dropdown := leaf_generator_shape_dropdown_bounds()
    lab_ui_draw_button(
        dropdown,
        fmt.ctprintf(
            "%s  %s",
            leaves.shape_name(leaf_generator_shape),
            leaf_generator_shape_dropdown_open ? "^" : "v",
        ),
        leaf_generator_isolated,
    )
    lab_ui_draw_button(leaf_generator_gallery_bounds(), "GALLERY", !leaf_generator_isolated)
    lab_ui_draw_button(leaf_generator_texture_bounds(), "TEXTURE", leaf_generator_veins)
    lab_ui_draw_button(
        leaf_generator_edge_bounds(),
        fmt.ctprintf("EDGE  %.0f%%", leaf_generator_effective_serration(leaf_generator_shape) * 100),
        leaf_generator_serration > 0,
    )
    lab_ui_draw_button(
        leaf_generator_curl_bounds(),
        fmt.ctprintf("CURL  %.2f", leaf_generator_curl),
        leaf_generator_curl > 0,
    )
    if leaf_generator_focus_triptych {
        shapes := [3]leaves.Shape{.Fig, .Grapevine, .Ivy}
        for shape, column in shapes {
            origin := third_person.Vec3{-4.3 + f32(column) * 4.3, 3.0, -1.25}
            leaf_generator_draw_label(editor, shape, origin, 2, width, height)
        }
    } else if !leaf_generator_isolated {
        for index in 0 ..< leaves.SHAPE_COUNT {
            shape := leaves.Shape(index)
            origin, specimen_scale := leaf_generator_gallery_layout(index)
            leaf_generator_draw_label(editor, shape, origin, specimen_scale, width, height)
        }
    }
    if leaf_generator_shape_dropdown_open {
        for index in 0 ..< leaves.SHAPE_COUNT {
            bounds := leaf_generator_shape_option_bounds(index)
            selected := index == int(leaf_generator_shape)
            hovered := canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), bounds)
            canvas2d.DrawRectangleRec(
                bounds,
                (selected || hovered) ? canvas2d.Color{57, 68, 63, 255} : canvas2d.Color{29, 35, 33, 250},
            )
            canvas2d.DrawRectangleRoundedLinesEx(bounds, 0, 1, 1, {107, 121, 104, 255})
            canvas2d.DrawTextEx(
                canvas2d.Font{},
                fmt.ctprintf("%s", leaves.shape_name(leaves.Shape(index))),
                {bounds.x + 10, bounds.y + 6},
                11,
                1,
                {232, 224, 189, 255},
            )
        }
    }
}
