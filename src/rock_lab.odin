package main

import atmosphere "../packages/atmosphere"
import "core:fmt"
import "core:math"
import sdl "vendor:sdl3"
import canvas2d "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

ROCK_LAB_SLIDER_COUNT :: 6
ROCK_LAB_MATERIAL_COUNT :: 3

ROCK_LAB_MATERIAL_NAMES := [ROCK_LAB_MATERIAL_COUNT]string {
    "Weathered Adriatic Cliff Limestone",
    "Weathered Gray Cliff Limestone",
    "Dark Storm Cliff Limestone",
}

ROCK_LAB_MATERIAL_LABELS := [ROCK_LAB_MATERIAL_COUNT]cstring{"PALE LIMESTONE", "GRAY LIMESTONE", "DARK STORM"}

Rock_Lab_State :: struct {
    edge_strength:    f32,
    texture_scale:    f32,
    texture_mix:      f32,
    irregularity:     f32,
    strata:           f32,
    roughness:        f32,
    material_variant: int,
    dragging:         int,
    orbit_yaw:        f32,
    orbit_pitch:      f32,
    orbit_distance:   f32,
}

rock_lab: Rock_Lab_State

rock_lab_apply_material :: proc() {
    variant := clamp(rock_lab.material_variant, 0, ROCK_LAB_MATERIAL_COUNT - 1)
    if index := material_lab_find(ROCK_LAB_MATERIAL_NAMES[variant]); index >= 0 {
        material_lab.selected = index
        material_lab_maps_load()
    }
}

rock_lab_update_camera :: proc(editor: ^Editor) {
    target := third_person.Vec3{0, 2.2, 0}
    horizontal := math.cos(rock_lab.orbit_pitch) * rock_lab.orbit_distance
    position :=
        target +
        third_person.Vec3 {
                math.sin(rock_lab.orbit_yaw) * horizontal,
                math.sin(rock_lab.orbit_pitch) * rock_lab.orbit_distance,
                math.cos(rock_lab.orbit_yaw) * horizontal,
            }
    editor.camera_pose = third_person.camera_look_at(position, target)
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
}

rock_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    rock_lab = {
        edge_strength    = 1.05,
        texture_scale    = .36,
        texture_mix      = 1,
        irregularity     = .58,
        strata           = .28,
        roughness        = .86,
        material_variant = 0,
        dragging         = -1,
        orbit_yaw        = -.72,
        orbit_pitch      = .22,
        orbit_distance   = 18,
    }
    if target == "gray" do rock_lab.material_variant = 1
    if target == "dark" do rock_lab.material_variant = 2
    if target == "edges-off" do rock_lab.edge_strength = 0
    _ = material_lab_ensure_library()
    rock_lab_apply_material()
    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    atmosphere.set_world_minutes(&editor.atmosphere, 10 * 60 + 20)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    rock_lab_update_camera(editor)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    set_pointer_locked(false)
    _ = sdl.ShowCursor()
    return true
}

rock_lab_exit :: proc(_: ^Editor) {
    rock_lab.dragging = -1
    material_lab_maps_destroy()
    _ = sdl.ShowCursor()
}

rock_lab_panel :: proc(width: i32) -> canvas2d.Rectangle {
    return {f32(width) - 354, 28, 326, 440}
}

rock_lab_slider_bounds :: proc(width, index: int) -> canvas2d.Rectangle {
    panel := rock_lab_panel(i32(width))
    return {panel.x + 142, panel.y + 112 + f32(index) * 48, panel.width - 166, 30}
}

rock_lab_slider_value :: proc(index: int) -> (value, low, high: f32) {
    switch index {
    case 0:
        return rock_lab.edge_strength, 0, 1.5
    case 1:
        return rock_lab.texture_scale, .12, 1.2
    case 2:
        return rock_lab.texture_mix, 0, 1
    case 3:
        return rock_lab.irregularity, 0, .8
    case 4:
        return rock_lab.strata, 0, .7
    case 5:
        return rock_lab.roughness, .25, 1
    }
    return 0, 0, 1
}

rock_lab_set_slider :: proc(index: int, normalized: f32) {
    _, low, high := rock_lab_slider_value(index)
    value := low + clamp(normalized, 0, 1) * (high - low)
    switch index {
    case 0:
        rock_lab.edge_strength = value
    case 1:
        rock_lab.texture_scale = value
    case 2:
        rock_lab.texture_mix = value
    case 3:
        rock_lab.irregularity = value
    case 4:
        rock_lab.strata = value
    case 5:
        rock_lab.roughness = value
    }
}

rock_lab_process_input :: proc(editor: ^Editor) {
    if editor == nil do return
    width := canvas2d.GetScreenWidth()
    panel := rock_lab_panel(width)
    mouse := canvas2d.GetMousePosition()
    viewport := !canvas2d.CheckCollisionPointRec(mouse, panel)
    if viewport && canvas2d.IsMouseButtonDown(.RIGHT) {
        delta := canvas2d.GetMouseDelta()
        rock_lab.orbit_yaw -= delta.x * .008
        rock_lab.orbit_pitch = clamp(rock_lab.orbit_pitch - delta.y * .006, -.35, .9)
        rock_lab_update_camera(editor)
    }
    wheel := canvas2d.GetMouseWheelMove()
    if viewport && math.abs(wheel) > .01 {
        rock_lab.orbit_distance = clamp(rock_lab.orbit_distance * f32(math.pow(.86, f64(wheel))), 8, 30)
        rock_lab_update_camera(editor)
    }
    if canvas2d.IsMouseButtonPressed(.LEFT) {
        material_button := canvas2d.Rectangle{panel.x + 20, panel.y + 78, panel.width - 40, 30}
        if canvas2d.CheckCollisionPointRec(mouse, material_button) {
            rock_lab.material_variant = (rock_lab.material_variant + 1) % ROCK_LAB_MATERIAL_COUNT
            rock_lab_apply_material()
        }
        for index in 0 ..< ROCK_LAB_SLIDER_COUNT {
            bounds := rock_lab_slider_bounds(int(width), index)
            if canvas2d.CheckCollisionPointRec(mouse, bounds) {
                rock_lab.dragging = index
                rock_lab_set_slider(index, (mouse.x - bounds.x) / bounds.width)
                break
            }
        }
    }
    if canvas2d.IsMouseButtonDown(.LEFT) && rock_lab.dragging >= 0 {
        bounds := rock_lab_slider_bounds(int(width), rock_lab.dragging)
        rock_lab_set_slider(rock_lab.dragging, (mouse.x - bounds.x) / bounds.width)
    }
    if canvas2d.IsMouseButtonReleased(.LEFT) do rock_lab.dragging = -1
    if canvas2d.IsKeyPressed(.E) {
        rock_lab.edge_strength = rock_lab.edge_strength > .01 ? 0 : f32(1.05)
    }
    if canvas2d.IsKeyPressed(.M) {
        rock_lab.material_variant = (rock_lab.material_variant + 1) % ROCK_LAB_MATERIAL_COUNT
        rock_lab_apply_material()
    }
    if canvas2d.IsKeyPressed(.ESCAPE) do lab_scene_exit_to_main_menu(editor)
}

rock_lab_cross :: proc(a, b: third_person.Vec3) -> third_person.Vec3 {
    return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}

rock_lab_normalize :: proc(value: third_person.Vec3) -> third_person.Vec3 {
    length := math.sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
    if length < .0001 do return {0, 1, 0}
    return value / length
}

rock_lab_point :: proc(latitude, longitude: f32, dimensions: third_person.Vec3, seed: f32) -> third_person.Vec3 {
    phi := -math.PI * .5 + latitude * math.PI
    theta := longitude * math.PI * 2
    unit := third_person.Vec3{math.cos(phi) * math.cos(theta), math.sin(phi), math.cos(phi) * math.sin(theta)}
    broad := math.sin(theta * 3 + seed) * .12 + math.cos(theta * 5 - phi * 2 + seed * .7) * .055
    layered := math.sin((unit.y + 1) * math.PI * 7 + seed) * rock_lab.strata * .08
    radius := 1 + (broad * rock_lab.irregularity / .42) + layered
    y := unit.y
    if y > .38 do y = .38 + (y - .38) * .38
    return {unit.x * radius * dimensions.x, y * radius * dimensions.y, unit.z * radius * dimensions.z}
}

rock_lab_uv :: proc(point, normal: third_person.Vec3) -> [2]f32 {
    scale := max(rock_lab.texture_scale, .01)
    ax, ay, az := math.abs(normal.x), math.abs(normal.y), math.abs(normal.z)
    if ay >= ax && ay >= az do return {point.x * scale, point.z * scale}
    if ax >= az do return {point.z * scale, point.y * scale}
    return {point.x * scale, point.y * scale}
}

rock_lab_triangle :: proc(a, b, c, center, dimensions: third_person.Vec3, color: canvas2d.Color) {
    face_normal := rock_lab_normalize(rock_lab_cross(b - a, c - a))
    if face_normal.y < -0.98 do face_normal = -face_normal
    points := [3]third_person.Vec3{a + center, b + center, c + center}
    locals := [3]third_person.Vec3{a, b, c}
    for point, index in points {
        vertex := world_vertex(point, color)
        vertex.kind = .Rock
        local := locals[index]
        smooth_normal := rock_lab_normalize({local.x / dimensions.x, local.y / dimensions.y, local.z / dimensions.z})
        vertex.normal = {smooth_normal.x, smooth_normal.y, smooth_normal.z}
        vertex.material = {rock_lab.edge_strength, rock_lab.roughness}
        vertex.color[3] = rock_lab.texture_mix
        vertex.uv = rock_lab_uv(local, face_normal)
        append(&world_renderer.vertices, vertex)
    }
}

rock_lab_rock :: proc(center, dimensions: third_person.Vec3, seed: f32, color: canvas2d.Color) {
    LATITUDES :: 7
    LONGITUDES :: 10
    for latitude in 0 ..< LATITUDES {
        v0, v1 := f32(latitude) / LATITUDES, f32(latitude + 1) / LATITUDES
        for longitude in 0 ..< LONGITUDES {
            u0, u1 := f32(longitude) / LONGITUDES, f32(longitude + 1) / LONGITUDES
            p00 := rock_lab_point(v0, u0, dimensions, seed)
            p01 := rock_lab_point(v0, u1, dimensions, seed)
            p10 := rock_lab_point(v1, u0, dimensions, seed)
            p11 := rock_lab_point(v1, u1, dimensions, seed)
            rock_lab_triangle(p00, p10, p11, center, dimensions, color)
            rock_lab_triangle(p00, p11, p01, center, dimensions, color)
        }
    }
}

world_rock_lab :: proc(_: ^Editor) {
    world_box({0, -.24, 0}, {30, .42, 20}, {86, 91, 86, 255})
    limestone: canvas2d.Color = {255, 255, 255, 255}
    rock_lab_rock({-6.4, 2.1, 0}, {2.8, 3.7, 2.3}, 1.1, limestone)
    rock_lab_rock({0, 1.65, 0}, {3.8, 2.9, 2.5}, 2.7, limestone)
    rock_lab_rock({6.2, 2.5, 0}, {2.2, 4.5, 2.0}, 4.4, limestone)
}

rock_lab_draw_ui :: proc(_: ^Editor, width, _: i32) {
    panel := rock_lab_panel(width)
    canvas2d.DrawRectangleRounded(panel, .05, 9, {15, 23, 24, 242})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .05, 9, 1, {143, 119, 75, 255})
    ui_draw_text(.Label, "ROCK LAB", {panel.x + 20, panel.y + 20}, .58, {240, 194, 111, 255})
    ui_draw_text(.Data, "MATERIAL • SHAPE • EDGE SHADING", {panel.x + 20, panel.y + 52}, .20, {150, 169, 164, 255})
    material_button := canvas2d.Rectangle{panel.x + 20, panel.y + 78, panel.width - 40, 30}
    canvas2d.DrawRectangleRounded(material_button, .14, 6, {34, 43, 43, 255})
    canvas2d.DrawRectangleRoundedLinesEx(material_button, .14, 6, 1, {143, 119, 75, 255})
    ui_draw_text(
        .Label,
        fmt.ctprintf("MATERIAL  %s", ROCK_LAB_MATERIAL_LABELS[rock_lab.material_variant]),
        {material_button.x + 10, material_button.y + 9},
        .21,
        {234, 231, 213, 255},
    )
    labels := [?]cstring{"EDGE SHADE", "TEXTURE SCALE", "TEXTURE MIX", "IRREGULARITY", "STRATA", "ROUGHNESS"}
    for label, index in labels {
        value, low, high := rock_lab_slider_value(index)
        normalized := (value - low) / (high - low)
        bounds := rock_lab_slider_bounds(int(width), index)
        ui_draw_text(.Label, label, {panel.x + 20, bounds.y + 7}, .24, {185, 194, 188, 255})
        canvas2d.DrawRectangleRounded({bounds.x, bounds.y + 10, bounds.width, 8}, 1, 4, {48, 57, 57, 255})
        canvas2d.DrawRectangleRounded(
            {bounds.x, bounds.y + 10, bounds.width * normalized, 8},
            1,
            4,
            {240, 194, 111, 255},
        )
        canvas2d.DrawCircleV({bounds.x + bounds.width * normalized, bounds.y + 14}, 7, {239, 232, 210, 255})
        ui_draw_text(
            .Data,
            fmt.ctprintf("%.2f", value),
            {bounds.x + bounds.width - 38, bounds.y - 8},
            .18,
            {151, 168, 163, 255},
        )
    }
    status: cstring = rock_lab.edge_strength <= .01 ? "E: EDGES OFF" : "E: EDGES ON"
    ui_draw_text(.Data, status, {panel.x + 20, panel.y + panel.height - 42}, .20, {240, 194, 111, 255})
    ui_draw_text(
        .Data,
        "M MATERIAL  •  RMB ORBIT  •  WHEEL ZOOM",
        {panel.x + 20, panel.y + panel.height - 22},
        .16,
        {133, 151, 147, 255},
    )
}
