package main

import atmosphere "../packages/atmosphere"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import rl "zelda_engine:canvas2d"

PATIO_STONE := rl.Color{205, 190, 159, 255}
PATIO_STONE_DARK := rl.Color{139, 128, 108, 255}
PATIO_WOOD := rl.Color{126, 76, 43, 255}
PATIO_WOOD_LIGHT := rl.Color{174, 112, 61, 255}
PATIO_METAL := rl.Color{54, 70, 68, 255}
PATIO_CREAM := rl.Color{238, 220, 174, 255}
PATIO_RED := rl.Color{184, 62, 48, 255}
PATIO_BLUE := rl.Color{52, 121, 139, 255}
PATIO_GREEN := rl.Color{75, 122, 73, 255}

Patio_Lab_Style :: enum u8 {
    Mixed,
    Coastal,
    Courtyard,
}

patio_lab_seed := u32(0x50415449)
patio_lab_style := Patio_Lab_Style.Mixed
patio_lab_evening := false
patio_lab_chair_count := 0
patio_lab_table_count := 0
patio_lab_umbrella_count := 0

patio_hash :: proc(value: u32) -> u32 {
    result := value
    result = result ~ (result >> 16)
    result *= 0x7feb352d
    result = result ~ (result >> 15)
    result *= 0x846ca68b
    result = result ~ (result >> 16)
    return result
}

patio_random01 :: proc(index: int, salt: u32 = 0) -> f32 {
    value := patio_hash(patio_lab_seed + u32(index) * 0x9e3779b9 + salt)
    return f32(value & 0xffff) / f32(0xffff)
}

patio_style_name :: proc() -> cstring {
    switch patio_lab_style {
    case .Coastal:
        return "COASTAL"
    case .Courtyard:
        return "COURTYARD"
    case .Mixed:
        return "MIXED"
    }
    return "MIXED"
}

patio_style_accent :: proc(index: int) -> rl.Color {
    switch patio_lab_style {
    case .Coastal:
        palette := [3]rl.Color{PATIO_BLUE, rl.Color{83, 153, 164, 255}, rl.Color{38, 82, 105, 255}}
        return palette[index % len(palette)]
    case .Courtyard:
        palette := [3]rl.Color{PATIO_RED, rl.Color{211, 126, 65, 255}, PATIO_GREEN}
        return palette[index % len(palette)]
    case .Mixed:
        palette := [3]rl.Color{PATIO_BLUE, PATIO_RED, PATIO_GREEN}
        return palette[index % len(palette)]
    }
    return PATIO_BLUE
}

patio_style_canopy_secondary :: proc() -> rl.Color {
    return patio_lab_style == .Courtyard ? rl.Color{246, 205, 132, 255} : PATIO_CREAM
}

patio_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    patio_lab_seed = 0x50415449
    patio_lab_style = .Mixed
    patio_lab_evening = false
    if target == "coastal" {
        patio_lab_seed = 0x434f4153
        patio_lab_style = .Coastal
    }
    if target == "courtyard" {
        patio_lab_seed = 0x434f5552
        patio_lab_style = .Courtyard
    }
    if target == "evening" {
        patio_lab_seed = 0x4556454e
        patio_lab_style = .Mixed
        patio_lab_evening = true
    }
    editor.in_map = true
    editor.capture_world_only = false
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.project.sea_level = -20
    minutes := patio_lab_evening ? f32(18 * 60 + 5) : f32(9 * 60 + 20)
    atmosphere.set_world_minutes(&editor.atmosphere, minutes)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    editor.camera_pose = third_person.camera_look_at({14.5, 7.4, 16.0}, {0, 1.0, 0})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

patio_local_point :: proc(center: third_person.Vec3, x, y, z, yaw: f32) -> third_person.Vec3 {
    c, s := math.cos(yaw), math.sin(yaw)
    return {center.x + x * c - z * s, center.y + y, center.z + x * s + z * c}
}

patio_chair :: proc(center: third_person.Vec3, yaw: f32, color: rl.Color = PATIO_BLUE) {
    // Slatted café chair with a slightly reclined-looking high back.
    world_box_rotated(patio_local_point(center, 0, .54, 0, yaw), {1.15, .12, 1.05}, yaw, color)
    for x in ([2]f32{-.46, .46}) {
        for z in ([2]f32{-.40, .40}) {
            world_box_rotated(patio_local_point(center, x, .27, z, yaw), {.10, .54, .10}, yaw, PATIO_METAL)
        }
    }
    for x in ([3]f32{-.42, 0, .42}) {
        world_box_rotated(patio_local_point(center, x, 1.20, .48, yaw), {.25, 1.25, .10}, yaw, color)
    }
    world_box_rotated(patio_local_point(center, 0, .66, .48, yaw), {1.18, .11, .13}, yaw, PATIO_METAL)
}

patio_round_table :: proc(center: third_person.Vec3, color: rl.Color = PATIO_CREAM) {
    world_vertical_prism({center.x, center.y + .72, center.z}, 1.65, 1.65, .16, math.PI / 8, color)
    world_vertical_prism({center.x, center.y + .37, center.z}, .14, .14, .74, 0, PATIO_METAL)
    world_vertical_prism({center.x, center.y + .05, center.z}, .72, .72, .10, math.PI / 8, PATIO_METAL)
}

patio_square_table :: proc(center: third_person.Vec3, yaw: f32) {
    world_box_rotated({center.x, center.y + .76, center.z}, {3.1, .18, 2.15}, yaw, PATIO_WOOD_LIGHT)
    for x in ([2]f32{-1.25, 1.25}) {
        for z in ([2]f32{-.78, .78}) {
            world_box_rotated(patio_local_point(center, x, .38, z, yaw), {.13, .76, .13}, yaw, PATIO_METAL)
        }
    }
}

patio_side_table :: proc(center: third_person.Vec3) {
    world_vertical_prism({center.x, center.y + .47, center.z}, .62, .62, .12, math.PI / 8, PATIO_CREAM)
    world_vertical_prism({center.x, center.y + .24, center.z}, .10, .10, .48, 0, PATIO_METAL)
    world_vertical_prism({center.x, center.y + .04, center.z}, .35, .35, .08, math.PI / 8, PATIO_METAL)
}

patio_lounge_chair :: proc(center: third_person.Vec3, yaw: f32, color: rl.Color) {
    // A deep low seat and inclined back make this silhouette distinct from
    // upright café seating even at the lab's overview distance.
    world_box_rotated(patio_local_point(center, 0, .34, -.22, yaw), {1.18, .16, 1.72}, yaw, color)
    back_left_low := patio_local_point(center, -.58, .40, .50, yaw)
    back_right_low := patio_local_point(center, .58, .40, .50, yaw)
    back_left_high := patio_local_point(center, -.58, 1.46, 1.12, yaw)
    back_right_high := patio_local_point(center, .58, 1.46, 1.12, yaw)
    world_quad(back_left_low, back_left_high, back_right_high, back_right_low, color)
    world_quad(back_right_low, back_right_high, back_left_high, back_left_low, color)
    // Dark rails outline the inclined fabric panel and keep it legible against
    // an umbrella of the same accent color.
    world_box_between(back_left_low, back_left_high, patio_local_point({0, 0, 0}, 1, 0, 0, yaw), .10, .10, PATIO_METAL)
    world_box_between(
        back_right_low,
        back_right_high,
        patio_local_point({0, 0, 0}, 1, 0, 0, yaw),
        .10,
        .10,
        PATIO_METAL,
    )
    for x in ([2]f32{-.48, .48}) {
        world_box_rotated(patio_local_point(center, x, .17, -.58, yaw), {.10, .34, .10}, yaw, PATIO_METAL)
        world_box_rotated(patio_local_point(center, x, .17, .52, yaw), {.10, .34, .10}, yaw, PATIO_METAL)
        world_box_rotated(patio_local_point(center, x, .67, -.15, yaw), {.10, .10, 1.12}, yaw, PATIO_METAL)
    }
    world_box_rotated(patio_local_point(center, 0, .43, -.90, yaw), {1.12, .12, .28}, yaw, PATIO_WOOD_LIGHT)
}

patio_bench :: proc(center: third_person.Vec3, yaw: f32) {
    for z in ([3]f32{-.43, 0, .43}) {
        world_settlement_material_box_rotated(
            patio_local_point(center, 0, .58, z, yaw),
            {4.2, .16, .32},
            yaw,
            .Bench_Slatted_Hardwood,
        )
    }
    for z in ([3]f32{.44, .76, 1.08}) {
        world_settlement_material_box_rotated(
            patio_local_point(center, 0, .75 + z * .68, .51, yaw),
            {4.2, .24, .13},
            yaw,
            .Bench_Slatted_Hardwood,
        )
    }
    for x in ([2]f32{-1.65, 1.65}) {
        world_settlement_material_box_rotated(
            patio_local_point(center, x, .52, .43, yaw),
            {.14, 1.04, .14},
            yaw,
            .Painted_Steel,
        )
        world_settlement_material_box_rotated(
            patio_local_point(center, x, .31, -.35, yaw),
            {.14, .62, .14},
            yaw,
            .Painted_Steel,
        )
    }
}

patio_umbrella :: proc(center: third_person.Vec3, radius: f32, color_a, color_b: rl.Color) {
    world_vertical_prism({center.x, center.y + 1.72, center.z}, .10, .10, 3.44, 0, PATIO_METAL)
    hub := third_person.Vec3{center.x, center.y + 3.72, center.z}
    SEGMENTS :: 12
    for segment in 0 ..< SEGMENTS {
        a := f32(segment) * math.PI * 2 / f32(SEGMENTS)
        b := f32(segment + 1) * math.PI * 2 / f32(SEGMENTS)
        edge_a := third_person.Vec3{center.x + math.cos(a) * radius, center.y + 3.18, center.z + math.sin(a) * radius}
        edge_b := third_person.Vec3{center.x + math.cos(b) * radius, center.y + 3.18, center.z + math.sin(b) * radius}
        color := segment % 2 == 0 ? color_a : color_b
        world_triangle(hub, edge_a, edge_b, color)
        world_triangle(hub, edge_b, edge_a, color)
    }
    world_vertical_prism({center.x, center.y + .05, center.z}, .62, .62, .10, math.PI / 8, PATIO_STONE_DARK)
}

patio_planter :: proc(center: third_person.Vec3, simple_foliage: bool = true) {
    world_settlement_material_box_rotated(
        {center.x, center.y + .38, center.z},
        {1.18, .76, 1.18},
        math.PI / 4,
        .Fired_Terracotta,
    )
    world_settlement_material_box_rotated(
        {center.x, center.y + .79, center.z},
        {.98, .10, .98},
        math.PI / 4,
        .Moist_Planter_Soil,
    )
    if !simple_foliage do return
    for offset in ([5][2]f32{{0, 0}, {-.3, .1}, {.3, .08}, {-.12, -.26}, {.18, -.22}}) {
        world_vertical_prism(
            {center.x + offset[0], center.y + 1.15, center.z + offset[1]},
            .22,
            .22,
            .75,
            0,
            PATIO_GREEN,
        )
    }
}

patio_table_centerpiece :: proc(center: third_person.Vec3, color: rl.Color) {
    if patio_lab_evening {
        world_vertical_prism({center.x, center.y + .93, center.z}, .16, .16, .20, 0, PATIO_METAL)
        world_emissive_fixture_box({center.x, center.y + 1.11, center.z}, {.30, .34, .30}, 0, {255, 205, 118, 255}, 2)
        world_box_rotated({center.x, center.y + 1.31, center.z}, {.36, .08, .36}, 0, PATIO_METAL)
        return
    }
    world_vertical_prism({center.x, center.y + .91, center.z}, .18, .18, .22, 0, {178, 103, 58, 255})
    for index in 0 ..< 5 {
        angle := f32(index) * math.PI * 2 / 5
        bloom := third_person.Vec3 {
            center.x + math.cos(angle) * .18,
            center.y + 1.08 + f32(index % 2) * .05,
            center.z + math.sin(angle) * .18,
        }
        world_vertical_prism(bloom, .09, .09, .12, angle, color)
    }
}

patio_cafe_cluster :: proc(center: third_person.Vec3, cluster_index: int) {
    accent := patio_style_accent(cluster_index)
    patio_round_table(center, cluster_index % 2 == 0 ? PATIO_CREAM : PATIO_WOOD_LIGHT)
    patio_lab_table_count += 1
    chair_count := 2 + int(patio_random01(cluster_index, 0x91) * 2.99)
    rotation := patio_random01(cluster_index, 0x37) * math.PI * 2
    radius := f32(2.15)
    for chair_index in 0 ..< chair_count {
        angle := rotation + f32(chair_index) * math.PI * 2 / f32(chair_count)
        chair_center := third_person.Vec3 {
            center.x + math.cos(angle) * radius,
            center.y,
            center.z + math.sin(angle) * radius,
        }
        // The back points radially away, leaving every seat facing its table.
        patio_chair(chair_center, angle - math.PI / 2, accent)
        patio_lab_chair_count += 1
    }
    if patio_random01(cluster_index, 0xb4) > .42 {
        canopy_a := patio_style_accent(cluster_index + 1)
        patio_umbrella(center, 2.65, canopy_a, patio_style_canopy_secondary())
        patio_lab_umbrella_count += 1
    }
    patio_table_centerpiece(center, accent)
}

patio_dining_cluster :: proc(center: third_person.Vec3, cluster_index: int) {
    accent := patio_style_accent(cluster_index + 2)
    yaw := (patio_random01(cluster_index, 0x63) - .5) * .32
    patio_square_table(center, yaw)
    patio_lab_table_count += 1
    for side in 0 ..< 2 {
        z := side == 0 ? f32(-1.72) : f32(1.72)
        chair_yaw := side == 0 ? yaw + math.PI : yaw
        for x in ([2]f32{-.85, .85}) {
            patio_chair(patio_local_point(center, x, 0, z, yaw), chair_yaw, accent)
            patio_lab_chair_count += 1
        }
    }
    if patio_random01(cluster_index, 0xdd) > .30 {
        patio_umbrella(center, 2.85, accent, patio_style_canopy_secondary())
        patio_lab_umbrella_count += 1
    }
    patio_table_centerpiece(center, PATIO_RED)
}

patio_lounge_cluster :: proc(center: third_person.Vec3, cluster_index: int) {
    accent := patio_style_accent(cluster_index + 1)
    yaw := (patio_random01(cluster_index, 0x82) - .5) * .55
    patio_lounge_chair(patio_local_point(center, -1.0, 0, 0, yaw), yaw, accent)
    patio_lounge_chair(patio_local_point(center, 1.0, 0, 0, yaw), yaw, accent)
    patio_lab_chair_count += 2
    side_table := patio_local_point(center, 0, 0, -.55, yaw)
    patio_side_table(side_table)
    patio_lab_table_count += 1
    patio_table_centerpiece({side_table.x, side_table.y - .25, side_table.z}, PATIO_CREAM)
    if patio_random01(cluster_index, 0xe7) > .24 {
        umbrella_center := patio_local_point(center, 0, 0, 1.0, yaw)
        patio_umbrella(umbrella_center, 2.7, accent, patio_style_canopy_secondary())
        patio_lab_umbrella_count += 1
    }
}

patio_generated_cluster :: proc(center: third_person.Vec3, cluster_index, zone_offset: int) {
    kind := (cluster_index + zone_offset) % 3
    switch kind {
    case 0:
        patio_cafe_cluster(center, cluster_index)
    case 1:
        patio_dining_cluster(center, cluster_index)
    case 2:
        patio_lounge_cluster(center, cluster_index)
    }
}

patio_pergola :: proc(center: third_person.Vec3, yaw: f32) {
    timber := PATIO_WOOD
    timber_light := PATIO_WOOD_LIGHT
    if patio_lab_style == .Coastal {
        timber = {65, 126, 139, 255}
        timber_light = {221, 218, 190, 255}
    } else if patio_lab_style == .Courtyard {
        timber = {119, 66, 38, 255}
        timber_light = {181, 104, 55, 255}
    }
    for x in ([2]f32{-4.2, 4.2}) {
        for z in ([2]f32{-1.7, 1.7}) {
            world_box_rotated(patio_local_point(center, x, 2.25, z, yaw), {.30, 4.5, .30}, yaw, timber)
        }
    }
    for z in ([2]f32{-1.7, 1.7}) {
        world_box_rotated(patio_local_point(center, 0, 4.48, z, yaw), {9.0, .28, .30}, yaw, timber)
    }
    for x_index in 0 ..< 7 {
        x := -3.9 + f32(x_index) * 1.3
        world_box_rotated(patio_local_point(center, x, 4.68, 0, yaw), {.18, .20, 4.1}, yaw, timber_light)
    }
    // Climbing greenery breaks up the timber silhouette and makes the shaded
    // zone feel established rather than newly assembled.
    for leaf_index in 0 ..< 13 {
        x := -3.7 + f32(leaf_index % 7) * 1.22
        z := -1.35 + f32(leaf_index / 7) * 2.5
        leaf := patio_local_point(center, x, 4.86, z, yaw)
        world_vertical_prism(leaf, .34, .26, .13, f32(leaf_index) * .37, PATIO_GREEN)
    }
    if patio_lab_evening {
        // Two warm festoons follow the pergola's long beams. The shallow
        // alternating sag keeps the line readable without introducing curves.
        for row in 0 ..< 2 {
            z := row == 0 ? f32(-1.40) : f32(1.40)
            for bulb_index in 0 ..< 9 {
                x := -3.8 + f32(bulb_index) * .95
                sag := f32(abs(bulb_index - 4)) * .045
                bulb := patio_local_point(center, x, 4.12 + sag, z, yaw)
                world_box_rotated(
                    patio_local_point(center, x, 4.39 + sag * .35, z, yaw),
                    {.035, .52, .035},
                    yaw,
                    PATIO_METAL,
                )
                world_emissive_fixture_box(bulb, {.23, .25, .23}, yaw, {255, 195, 100, 255}, 2)
            }
        }
    }
    patio_bench(patio_local_point(center, 0, 0, 1.15, yaw), yaw + math.PI)
}

patio_mosaic :: proc(center: third_person.Vec3, radius: f32) {
    SEGMENTS :: 16
    hub := third_person.Vec3{center.x, center.y + .07, center.z}
    for segment in 0 ..< SEGMENTS {
        a := f32(segment) * math.PI * 2 / f32(SEGMENTS)
        b := f32(segment + 1) * math.PI * 2 / f32(SEGMENTS)
        edge_a := third_person.Vec3{center.x + math.cos(a) * radius, hub.y, center.z + math.sin(a) * radius}
        edge_b := third_person.Vec3{center.x + math.cos(b) * radius, hub.y, center.z + math.sin(b) * radius}
        color := segment % 2 == 0 ? patio_style_accent(0) : patio_style_canopy_secondary()
        world_triangle(hub, edge_b, edge_a, color)
    }
    world_vertical_prism({center.x, center.y + .09, center.z}, .22, .22, .05, math.PI / 8, PATIO_RED)
}

patio_service_console :: proc(center: third_person.Vec3, yaw: f32) {
    world_box_rotated({center.x, center.y + .68, center.z}, {3.2, 1.36, .78}, yaw, PATIO_WOOD)
    world_box_rotated({center.x, center.y + 1.42, center.z}, {3.45, .14, .98}, yaw, PATIO_STONE)
    for x in ([3]f32{-1.05, 0, 1.05}) {
        world_box_rotated(patio_local_point(center, x, .72, -.41, yaw), {.10, 1.18, .06}, yaw, PATIO_WOOD_LIGHT)
    }
    // A carafe and cup make the function legible from the inspection camera.
    carafe := patio_local_point(center, -.55, 1.68, 0, yaw)
    world_vertical_prism(carafe, .18, .18, .42, 0, PATIO_BLUE)
    cup := patio_local_point(center, .22, 1.56, 0, yaw)
    world_vertical_prism(cup, .13, .13, .20, 0, PATIO_CREAM)
}

patio_boundary :: proc() {
    wall := rl.Color{177, 163, 136, 255}
    cap := rl.Color{220, 205, 173, 255}
    if patio_lab_style == .Coastal {
        wall = {173, 194, 194, 255}
        cap = {235, 235, 215, 255}
    } else if patio_lab_style == .Courtyard {
        wall = {181, 119, 79, 255}
        cap = {231, 184, 127, 255}
    }
    world_box({0, .36, -10.15}, {27, .72, .42}, wall)
    world_box({0, .77, -10.15}, {27.25, .12, .62}, cap)
    world_box({-13.25, .36, 0}, {.42, .72, 20.7}, wall)
    world_box({-13.25, .77, 0}, {.62, .12, 20.95}, cap)
}

patio_coastal_edge :: proc() {
    if patio_lab_style != .Coastal do return
    white := rl.Color{229, 231, 215, 255}
    blue := rl.Color{44, 104, 126, 255}
    // An open slatted windbreak preserves the sea-facing character while
    // differentiating this profile from the enclosed masonry courtyard.
    for x in ([5]f32{-10, -5, 0, 5, 10}) {
        world_box({x, 1.25, -9.82}, {.16, 2.15, .16}, blue)
    }
    world_box({0, 2.28, -9.82}, {20.2, .16, .18}, blue)
    for panel in 0 ..< 20 {
        x := -9.5 + f32(panel)
        world_box({x, 1.22, -9.82}, {.08, 1.72, .10}, panel % 2 == 0 ? white : blue)
    }
}

patio_courtyard_pots :: proc() {
    if patio_lab_style != .Courtyard do return
    for x in ([3]f32{-8.8, 0, 8.8}) {
        patio_planter({x, 0, -9.45})
    }
}

patio_evening_bollards :: proc() {
    if !patio_lab_evening do return
    positions := [4][2]f32{{-10.8, -6.3}, {10.8, -6.3}, {-10.8, 6.3}, {10.8, 6.3}}
    for p in positions {
        world_vertical_prism({p[0], .42, p[1]}, .13, .13, .84, 0, PATIO_METAL)
        world_emissive_fixture_box({p[0], .92, p[1]}, {.32, .38, .32}, 0, {255, 191, 96, 255}, 1)
        world_box_rotated({p[0], 1.14, p[1]}, {.42, .08, .42}, 0, PATIO_METAL)
    }
}

world_patio_lab :: proc(_: ^Editor) {
    // Raised stone terrace with a border and a simple checker of large pavers.
    foundation := PATIO_STONE_DARK
    if patio_lab_style == .Coastal do foundation = {108, 143, 150, 255}
    if patio_lab_style == .Courtyard do foundation = {139, 91, 64, 255}
    world_box({0, -.28, 0}, {27, .52, 21}, foundation)
    for z in 0 ..< 5 {
        for x in 0 ..< 7 {
            shade := (x + z) % 2 == 0 ? PATIO_STONE : rl.Color{195, 180, 149, 255}
            if patio_lab_style == .Coastal {
                shade = (x + z) % 2 == 0 ? rl.Color{208, 213, 198, 255} : rl.Color{184, 205, 203, 255}
            } else if patio_lab_style == .Courtyard {
                shade = (x + z) % 2 == 0 ? rl.Color{213, 168, 119, 255} : rl.Color{194, 139, 94, 255}
            }
            world_box({-10.5 + f32(x) * 3.5, .01, -7 + f32(z) * 3.5}, {3.42, .08, 3.42}, shade)
        }
    }
    world_renderer.dynamic_caster_first = len(world_renderer.vertices)
    patio_boundary()
    patio_coastal_edge()
    patio_courtyard_pots()
    patio_evening_bollards()

    patio_lab_chair_count = 0
    patio_lab_table_count = 0
    patio_lab_umbrella_count = 0

    // A stable seed varies occupancy, rotation, palette, and shade while the
    // zone anchors keep circulation lanes and the terrace edge clear.
    anchors := [3]third_person.Vec3{{-6.1, 0, -3.5}, {1.0, 0, -3.7}, {6.9, 0, 2.0}}
    zone_offset := int(patio_hash(patio_lab_seed) % 3)
    for center, cluster_index in anchors {
        jitter_x := (patio_random01(cluster_index, 0x12) - .5) * .8
        jitter_z := (patio_random01(cluster_index, 0x27) - .5) * .8
        patio_generated_cluster({center.x + jitter_x, 0, center.z + jitter_z}, cluster_index, zone_offset)
    }

    // The rear shade structure gives generated furniture a strong boundary
    // and creates a quieter sitting zone distinct from the café clusters.
    patio_pergola({-5.8, 0, 5.9}, 0)
    patio_service_console({7.8, 0, -8.3}, 0)
    patio_mosaic({-.8, 0, 2.4}, 1.35)
    patio_planter({-10.8, 0, -7.8})
    patio_planter({10.8, 0, -7.8})
    patio_planter({-10.8, 0, 7.8})
    patio_planter({10.8, 0, 7.8})
    world_renderer.dynamic_caster_count = len(world_renderer.vertices) - world_renderer.dynamic_caster_first
}

patio_lab_draw_ui :: proc(_: ^Editor, width, height: i32) {
    panel := rl.Rectangle {
        x      = 22,
        y      = 22,
        width  = 500,
        height = 92,
    }
    rl.DrawRectangleRounded(panel, .12, 8, {27, 35, 30, 224})
    rl.DrawRectangleRoundedLinesEx(panel, .12, 8, 1, {172, 141, 89, 255})
    rl.DrawTextEx(rl.Font{}, "PROCEDURAL PATIO LAB", {38, 38}, 20, 1, {248, 232, 188, 255})
    summary := fmt.ctprintf(
        "%s  /  SEED %08X  /  %d CHAIRS  /  %d TABLES  /  %d UMBRELLAS",
        patio_lab_evening ? cstring("EVENING") : patio_style_name(),
        patio_lab_seed,
        patio_lab_chair_count,
        patio_lab_table_count,
        patio_lab_umbrella_count,
    )
    rl.DrawTextEx(rl.Font{}, summary, {38, 72}, 13, 1, {205, 221, 204, 255})
    _ = width
    _ = height
}
