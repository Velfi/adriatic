package main

import atmosphere "../packages/atmosphere"
import cars "../packages/cars"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

CAR_GENERATOR_LAB_KINDS := [5]cars.Kind{.Sedan, .Coupe, .Pickup, .Delivery, .Woody}
car_generator_lab_seed: u32 = 1947
car_generator_lab_selected := -1
car_generator_lab_kind_dropdown_open := false

car_generator_lab_kind_dropdown_bounds :: proc() -> canvas2d.Rectangle {
    return {38, 78, 250, 28}
}

car_generator_lab_seed_bounds :: proc() -> canvas2d.Rectangle {
    return {302, 78, 150, 28}
}

car_generator_lab_kind_option_bounds :: proc(index: int) -> canvas2d.Rectangle {
    bounds := car_generator_lab_kind_dropdown_bounds()
    return {bounds.x, bounds.y + bounds.height + f32(index) * 26, bounds.width, 26}
}

car_generator_lab_selection_label :: proc() -> cstring {
    if car_generator_lab_selected < 0 do return "All body styles"
    return fmt.ctprintf("%s", cars.kind_name(CAR_GENERATOR_LAB_KINDS[car_generator_lab_selected]))
}

car_generator_lab_select :: proc(editor: ^Editor, selected: int) {
    car_generator_lab_selected = selected
    if selected >= 0 {
        editor.camera_pose = third_person.camera_look_at({3.65, 1.95, 4.35}, {0, .70, 0})
    } else {
        editor.camera_pose = third_person.camera_look_at({7.3, 4.5, 9.6}, {0, .70, 0})
    }
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
}

car_generator_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    atmosphere.set_world_minutes(&editor.atmosphere, 9 * 60 + 10)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    selected := -1
    side_view := false
    rear_view := false
    switch target {
    case "alternate", "seed-1984":
        car_generator_lab_seed = 1984
    case "sedan":
        selected = 0
    case "sedan-side":
        selected, side_view = 0, true
    case "coupe":
        selected = 1
    case "coupe-side":
        selected, side_view = 1, true
    case "pickup", "truck":
        selected = 2
    case "pickup-side", "truck-side":
        selected, side_view = 2, true
    case "delivery", "van":
        selected = 3
    case "delivery-side", "van-side":
        selected, side_view = 3, true
    case "delivery-rear", "van-rear":
        selected, rear_view = 3, true
    case "woody", "estate":
        selected = 4
    case "woody-side", "estate-side":
        selected, side_view = 4, true
    }
    car_generator_lab_kind_dropdown_open = false
    car_generator_lab_select(editor, selected)
    if side_view {
        editor.camera_pose = third_person.camera_look_at({-4.15, 1.55, .96}, {0, .68, 0})
        third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    }
    if rear_view {
        editor.camera_pose = third_person.camera_look_at({-.96, 1.65, -4.15}, {0, .82, 0})
        third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    }
    return true
}

car_generator_lab_process_input :: proc(editor: ^Editor) {
    if editor == nil do return
    if canvas2d.IsMouseButtonPressed(.LEFT) {
        mouse := canvas2d.GetMousePosition()
        if canvas2d.CheckCollisionPointRec(mouse, car_generator_lab_kind_dropdown_bounds()) {
            car_generator_lab_kind_dropdown_open = !car_generator_lab_kind_dropdown_open
        } else if car_generator_lab_kind_dropdown_open {
            selected := false
            for index in 0 ..< len(CAR_GENERATOR_LAB_KINDS) + 1 {
                if canvas2d.CheckCollisionPointRec(mouse, car_generator_lab_kind_option_bounds(index)) {
                    car_generator_lab_select(editor, index - 1)
                    car_generator_lab_kind_dropdown_open = false
                    selected = true
                    break
                }
            }
            if !selected do car_generator_lab_kind_dropdown_open = false
        } else if canvas2d.CheckCollisionPointRec(mouse, car_generator_lab_seed_bounds()) {
            car_generator_lab_seed += 1
        }
    }
    if canvas2d.IsKeyPressed(.G) do car_generator_lab_select(editor, -1)
    if canvas2d.IsKeyPressed(.R) do car_generator_lab_seed += 1
    if canvas2d.IsKeyPressed(.ONE) do car_generator_lab_select(editor, 0)
    if canvas2d.IsKeyPressed(.TWO) do car_generator_lab_select(editor, 1)
    if canvas2d.IsKeyPressed(.THREE) do car_generator_lab_select(editor, 2)
    if canvas2d.IsKeyPressed(.FOUR) do car_generator_lab_select(editor, 3)
    if canvas2d.IsKeyPressed(.W) do car_generator_lab_select(editor, 4)
}

car_generator_lab_local :: proc(origin: third_person.Vec3, yaw, x, y, z: f32) -> third_person.Vec3 {
    c, s := math.cos(yaw), math.sin(yaw)
    return {origin.x + x * c - z * s, origin.y + y, origin.z + x * s + z * c}
}

car_generator_lab_box :: proc(
    origin: third_person.Vec3,
    yaw: f32,
    x, y, z, width, height, length: f32,
    color: canvas2d.Color,
) {
    // car_generator_lab_local and world_box_rotated use the same positive-yaw
    // convention.  Negating here skewed every chrome bar away from the body.
    world_box_rotated(car_generator_lab_local(origin, yaw, x, y, z), {width, height, length}, yaw, color)
}

// A tapered coachwork volume: broad at the beltline and narrower at the roof.
// The sloping front and rear faces are the main thing that separates these
// silhouettes from modern slab-sided vans.
car_generator_lab_tapered :: proc(
    origin: third_person.Vec3,
    yaw: f32,
    x, bottom_y, z, bottom_width, bottom_length, top_width, top_length, height: f32,
    color: canvas2d.Color,
) {
    bottom_half_w, bottom_half_l := bottom_width * .5, bottom_length * .5
    top_half_w, top_half_l := top_width * .5, top_length * .5
    local := [8][3]f32 {
        {x - bottom_half_w, bottom_y, z - bottom_half_l},
        {x + bottom_half_w, bottom_y, z - bottom_half_l},
        {x + bottom_half_w, bottom_y, z + bottom_half_l},
        {x - bottom_half_w, bottom_y, z + bottom_half_l},
        {x - top_half_w, bottom_y + height, z - top_half_l},
        {x + top_half_w, bottom_y + height, z - top_half_l},
        {x + top_half_w, bottom_y + height, z + top_half_l},
        {x - top_half_w, bottom_y + height, z + top_half_l},
    }
    p: [8]third_person.Vec3
    for point, index in local {
        p[index] = car_generator_lab_local(origin, yaw, point[0], point[1], point[2])
    }
    world_quad(p[0], p[4], p[5], p[1], color)
    world_quad(p[3], p[2], p[6], p[7], color)
    world_quad(p[0], p[3], p[7], p[4], color)
    world_quad(p[1], p[5], p[6], p[2], color)
    world_quad(p[4], p[7], p[6], p[5], color)
    world_quad(p[0], p[1], p[2], p[3], color)
}

car_generator_lab_colors :: proc(palette: cars.Palette) -> (body, accent, timber: canvas2d.Color) {
    switch palette {
    case .Sage:
        return {113, 139, 113, 255}, {224, 213, 177, 255}, {132, 91, 53, 255}
    case .Cream:
        return {219, 205, 163, 255}, {122, 61, 47, 255}, {143, 96, 54, 255}
    case .Oxblood:
        return {126, 48, 45, 255}, {225, 198, 137, 255}, {146, 93, 52, 255}
    case .Petrol:
        return {47, 104, 111, 255}, {210, 190, 142, 255}, {137, 87, 48, 255}
    case .Mustard:
        return {190, 143, 49, 255}, {72, 84, 76, 255}, {130, 82, 45, 255}
    }
    return {120, 130, 120, 255}, {220, 210, 180, 255}, {140, 90, 50, 255}
}

car_generator_lab_generated_mesh :: proc(
    plan: cars.Plan,
    origin: third_person.Vec3,
    yaw: f32,
    body, accent, timber: canvas2d.Color,
) {
    generated := cars.mesh(plan)
    glass := canvas2d.Color{65, 105, 114, 255}
    for first := 0; first + 2 < generated.index_count; first += 3 {
        source_a := generated.vertices[generated.indices[first + 0]]
        source_b := generated.vertices[generated.indices[first + 1]]
        source_c := generated.vertices[generated.indices[first + 2]]
        a := car_generator_lab_local(origin, yaw, source_a.position[0], source_a.position[1], source_a.position[2])
        b := car_generator_lab_local(origin, yaw, source_b.position[0], source_b.position[1], source_b.position[2])
        c := car_generator_lab_local(origin, yaw, source_c.position[0], source_c.position[1], source_c.position[2])
        normal := linalg.normalize0(linalg.cross(b - a, c - a))
        color := body
        switch source_a.part {
        case .Body:
            color = body
        case .Glass:
            color = glass
        case .Trim:
            color = accent
        case .Timber:
            color = timber
        case .Tire:
            color = {34, 38, 36, 255}
        case .Whitewall:
            color = {221, 213, 185, 255}
        case .Chrome:
            color = {194, 194, 177, 255}
        }
        if source_a.part == .Glass {
            // Glazing is deliberately double-sided: station-generated panes
            // are thin surfaces, unlike the closed body shell.
            world_triangle(a, b, c, color)
            world_triangle(c, b, a, color)
        } else {
            material_kind := source_a.part == .Body ? World_Material_Kind.Car_Paint : World_Material_Kind.BRDF
            finish := source_a.part == .Body ? Car_Paint_Finish.Metal_Flake : Car_Paint_Finish.Opaque
            roughness := source_a.part == .Body ? f32(.62) : f32(.82)
            world_triangle_smooth_lit(
                a,
                b,
                c,
                normal,
                normal,
                normal,
                color,
                color,
                color,
                roughness,
                material_kind,
                finish,
            )
        }
    }
}

car_generator_lab_car :: proc(plan: cars.Plan, origin: third_person.Vec3, yaw: f32) {
    body, accent, timber := car_generator_lab_colors(plan.palette)
    dark := canvas2d.Color{34, 38, 36, 255}
    chrome := canvas2d.Color{194, 194, 177, 255}
    wheel_z := plan.wheelbase * .5
    sides := [2]f32{-1, 1}
    axles := [2]f32{-wheel_z, wheel_z}

    // Low, proud mudguards reinforce the generated arch topology and give the
    // tiny cars the rounded "four paws" stance of period European coachwork.
    for side in sides {
        for axle in axles {
            fender := car_generator_lab_local(origin, yaw, side * plan.width * .485, plan.wheel_radius * 1.02, axle)
            world_ellipsoid_rotated(
                fender,
                plan.wheel_width * .62,
                plan.fender_radius * .72,
                plan.fender_radius * 1.14,
                yaw,
                body,
                .Car_Paint,
            )
        }
        // A slim running board visually joins the arches without returning to
        // the slab-sided lower body of the first pass.
        car_generator_lab_box(
            origin,
            yaw,
            side * plan.width * .515,
            .235,
            0,
            plan.wheel_width * .72,
            .055,
            plan.wheelbase * .58,
            dark,
        )
    }
    // Submit the indexed body after the mudguards: its wheel regions are last
    // in the mesh, keeping tires, whitewalls, and hubs visible in the lab's
    // ordered transparent world pass. Chrome fixtures remain above both.
    car_generator_lab_generated_mesh(plan, origin, yaw, body, accent, timber)
    car_generator_lab_box(origin, yaw, 0, .64, -plan.length * .505, plan.width * .64, .22, .055, accent)
    car_generator_lab_box(origin, yaw, 0, .55, -plan.length * .538, plan.width * .72, .06, .06, chrome)
    for side in sides {
        lamp := car_generator_lab_local(origin, yaw, side * plan.width * .30, .72, -plan.length * .52)
        world_ellipsoid_rotated(lamp, .11, .11, .07, yaw, {247, 215, 134, 255}, .BRDF)
    }
    // Narrow chrome grille bars and a tiny bonnet mascot are deliberately
    // toy-like period punctuation.
    for bar in -2 ..= 2 {
        car_generator_lab_box(
            origin,
            yaw,
            f32(bar) * .07,
            .65,
            -plan.length * .543,
            .025,
            .24 - math.abs(f32(bar)) * .025,
            .025,
            chrome,
        )
    }
    car_generator_lab_box(origin, yaw, 0, .91, -plan.length * .43, .035, .10, .035, chrome)
    car_generator_lab_box(origin, yaw, 0, .38, -plan.length * .54, plan.width * .72, .055, .07, chrome)
    car_generator_lab_box(origin, yaw, 0, .38, plan.length * .525, plan.width * .68, .05, .06, chrome)
}

world_car_generator_lab :: proc(_: ^Editor) {
    extent := car_generator_lab_selected >= 0 ? f32(12) : f32(14)
    depth := car_generator_lab_selected >= 0 ? f32(10) : f32(10)
    world_box({0, -.18, 0}, {extent, .32, depth}, {167, 164, 145, 255})
    // Pale lane stones give scale without competing with the silhouettes.
    for x in -3 ..= 3 {
        world_box({f32(x) * 2, .005, depth * .35}, {1.15, .025, .10}, {222, 215, 188, 255})
    }
    for kind, index in CAR_GENERATOR_LAB_KINDS {
        if car_generator_lab_selected >= 0 && index != car_generator_lab_selected do continue
        x, z := f32(0), f32(0)
        if car_generator_lab_selected < 0 {
            gallery_positions := [5][2]f32{{-3.35, -.90}, {0, -1.55}, {3.35, -.90}, {-1.75, 1.45}, {1.75, 1.45}}
            x, z = gallery_positions[index][0], gallery_positions[index][1]
        }
        plan := cars.generate(kind, car_generator_lab_seed + u32(index) * 31)
        car_generator_lab_car(plan, {x, 0, z}, math.PI - .23)
    }
}

car_generator_lab_draw_ui :: proc(_: ^Editor, width, height: i32) {
    panel := canvas2d.Rectangle {
        x      = 22,
        y      = 22,
        width  = 510,
        height = 205,
    }
    canvas2d.DrawRectangleRounded(panel, .10, 8, {20, 28, 29, 230})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {196, 167, 106, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "EUROPEAN CAR GENERATOR", {38, 38}, 20, 1, {247, 226, 176, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "BODY STYLE  /  1938–1949", {38, 65}, 12, 1, {171, 204, 198, 255})
    dropdown := car_generator_lab_kind_dropdown_bounds()
    seed_button := car_generator_lab_seed_bounds()
    mouse := canvas2d.GetMousePosition()
    control_bounds := [2]canvas2d.Rectangle{dropdown, seed_button}
    for bounds in control_bounds {
        hovered := canvas2d.CheckCollisionPointRec(mouse, bounds)
        canvas2d.DrawRectangleRounded(bounds, .16, 6, hovered ? canvas2d.Color{66, 58, 43, 255} : canvas2d.Color{42, 43, 38, 248})
        canvas2d.DrawRectangleRoundedLinesEx(bounds, .16, 6, 1, {196, 167, 106, 255})
    }
    canvas2d.DrawTextEx(canvas2d.Font{}, car_generator_lab_selection_label(), {dropdown.x + 10, dropdown.y + 7}, 12, 1, {247, 226, 176, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, car_generator_lab_kind_dropdown_open ? "^" : "v", {dropdown.x + dropdown.width - 18, dropdown.y + 7}, 12, 1, {196, 167, 106, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, fmt.ctprintf("NEW SEED  %d", car_generator_lab_seed), {seed_button.x + 10, seed_button.y + 7}, 11, 1, {247, 226, 176, 255})
    for kind, index in CAR_GENERATOR_LAB_KINDS {
        plan := cars.generate(kind, car_generator_lab_seed + u32(index) * 31)
        topology := cars.mesh(plan)
        label := fmt.ctprintf(
            "%d  %s   %.2f x %.2f m   %d V / %d I",
            index + 1,
            cars.kind_name(kind),
            plan.length,
            plan.width,
            topology.vertex_count,
            topology.index_count,
        )
        color :=
            index == car_generator_lab_selected ? canvas2d.Color{247, 205, 121, 255} : canvas2d.Color{224, 219, 197, 255}
        canvas2d.DrawTextEx(canvas2d.Font{}, label, {38, 118 + f32(index) * 15}, 12, 1, color)
    }
    if car_generator_lab_kind_dropdown_open {
        for index in 0 ..< len(CAR_GENERATOR_LAB_KINDS) + 1 {
            bounds := car_generator_lab_kind_option_bounds(index)
            hovered := canvas2d.CheckCollisionPointRec(mouse, bounds)
            selected := index - 1 == car_generator_lab_selected
            fill := (hovered || selected) ? canvas2d.Color{66, 58, 43, 255} : canvas2d.Color{30, 34, 33, 250}
            label: cstring = "All body styles"
            if index > 0 do label = fmt.ctprintf("%s", cars.kind_name(CAR_GENERATOR_LAB_KINDS[index - 1]))
            canvas2d.DrawRectangleRec(bounds, fill)
            canvas2d.DrawRectangleRoundedLinesEx(bounds, 0, 1, 1, {142, 123, 81, 255})
            canvas2d.DrawTextEx(canvas2d.Font{}, label, {bounds.x + 10, bounds.y + 6}, 12, 1, selected ? canvas2d.Color{247, 226, 176, 255} : canvas2d.Color{224, 219, 197, 255})
        }
    }
    _ = width
    _ = height
}
