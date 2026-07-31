package main

import atmosphere "../packages/atmosphere"
import cemeteries "../packages/cemeteries"
import plants "../packages/plants"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

CEMETERY_LAB_DEFAULT_SEED :: u32(0xC3E7E8)

cemetery_lab_seed := CEMETERY_LAB_DEFAULT_SEED
cemetery_lab_style := cemeteries.Style.Adriatic_Medieval
cemetery_lab_width := f32(24)
cemetery_lab_depth := f32(30)
cemetery_lab_density := f32(.72)
cemetery_lab_memorial_index := -1
cemetery_lab_memorial_view := false
cemetery_lab_marker_view := false

cemetery_lab_style_name :: proc() -> cstring {
    switch cemetery_lab_style {
    case .Adriatic_Medieval:
        return "ADRIATIC MEDIEVAL"
    case .Classical_Aegean:
        return "CLASSICAL AEGEAN"
    case .Churchyard:
        return "CHURCHYARD"
    case .Memorial_Garden:
        return "MEMORIAL GARDEN"
    }
    return "CEMETERY"
}

cemetery_lab_memorial_name :: proc(kind: cemeteries.Memorial_Kind) -> cstring {
    switch kind {
    case .Obelisk:
        return "OBELISK"
    case .Cross:
        return "CROSS"
    case .Stele:
        return "STELE"
    case .Shrine:
        return "SHRINE"
    }
    return "MEMORIAL"
}

cemetery_lab_plan :: proc() -> cemeteries.Plan {
    return cemeteries.generate(
        cemetery_lab_seed,
        {
            width = cemetery_lab_width,
            depth = cemetery_lab_depth,
            density = cemetery_lab_density,
            style = cemetery_lab_style,
            memorial_kind = cemetery_lab_memorial_index >= 0 ? cemeteries.Memorial_Kind(cemetery_lab_memorial_index) : .Obelisk,
            memorial_explicit = cemetery_lab_memorial_index >= 0,
        },
    )
}

cemetery_lab_configure_camera :: proc(editor: ^Editor) {
    if cemetery_lab_marker_view {
        editor.camera_pose = third_person.camera_look_at({0, 1.42, -5.15}, {0, .64, 0})
        third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
        third_person.camera_set_active(&editor.cameras, .Inspection)
        return
    }
    if cemetery_lab_memorial_view {
        plan := cemetery_lab_plan()
        focus := third_person.Vec3{plan.memorial.x, plan.memorial.height * .42, plan.memorial.z}
        editor.camera_pose = third_person.camera_look_at({focus.x + 7.4, focus.y + 4.2, focus.z - 8.6}, focus)
        third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
        third_person.camera_set_active(&editor.cameras, .Inspection)
        return
    }
    distance := max(cemetery_lab_width, cemetery_lab_depth) * .72
    editor.camera_pose = third_person.camera_look_at({distance * .75, distance * .56, -distance * .82}, {0, .8, 1.5})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
}

cemetery_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    cemetery_lab_seed = CEMETERY_LAB_DEFAULT_SEED
    cemetery_lab_style = .Adriatic_Medieval
    cemetery_lab_width = 24
    cemetery_lab_depth = 30
    cemetery_lab_density = .72
    cemetery_lab_memorial_index = -1
    cemetery_lab_memorial_view = false
    cemetery_lab_marker_view = false
    switch target {
    case "", "mediterranean", "adriatic-medieval", "stecci":
    case "classical-aegean", "aegean":
        cemetery_lab_style = .Classical_Aegean
    case "churchyard":
        cemetery_lab_style = .Churchyard
    case "garden", "memorial-garden":
        cemetery_lab_style = .Memorial_Garden
    case "dense":
        cemetery_lab_density = 1
    case "sparse":
        cemetery_lab_density = .35
    case "large":
        cemetery_lab_width = 34
        cemetery_lab_depth = 42
    case "obelisk":
        cemetery_lab_memorial_index = int(cemeteries.Memorial_Kind.Obelisk)
        cemetery_lab_memorial_view = true
    case "cross":
        cemetery_lab_memorial_index = int(cemeteries.Memorial_Kind.Cross)
        cemetery_lab_memorial_view = true
    case "stele":
        cemetery_lab_memorial_index = int(cemeteries.Memorial_Kind.Stele)
        cemetery_lab_memorial_view = true
    case "shrine":
        cemetery_lab_memorial_index = int(cemeteries.Memorial_Kind.Shrine)
        cemetery_lab_memorial_view = true
    case "markers", "marker-gallery", "markers-adriatic":
        cemetery_lab_marker_view = true
    case "markers-aegean":
        cemetery_lab_style = .Classical_Aegean
        cemetery_lab_marker_view = true
    case "markers-churchyard":
        cemetery_lab_style = .Churchyard
        cemetery_lab_marker_view = true
    case "markers-garden":
        cemetery_lab_style = .Memorial_Garden
        cemetery_lab_marker_view = true
    case:
        return false
    }
    editor.in_map = true
    editor.capture_world_only = false
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    editor.project.sea_level = -20
    atmosphere.set_world_minutes(&editor.atmosphere, 17 * 60 + 10)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    cemetery_lab_configure_camera(editor)
    return true
}

cemetery_lab_process_input :: proc(editor: ^Editor) {
    changed_size := false
    if canvas2d.IsKeyPressed(.A) do cemetery_lab_seed -= 1
    if canvas2d.IsKeyPressed(.D) do cemetery_lab_seed += 1
    if canvas2d.IsKeyPressed(.S) {
        cemetery_lab_style = cemeteries.Style((int(cemetery_lab_style) + 1) % 4)
    }
    if canvas2d.IsKeyPressed(.M) {
        cemetery_lab_memorial_index = (cemetery_lab_memorial_index + 1) % 4
    }
    if canvas2d.IsKeyPressed(.N) do cemetery_lab_memorial_index = -1
    if canvas2d.IsKeyPressed(.V) {
        cemetery_lab_memorial_view = !cemetery_lab_memorial_view
        cemetery_lab_marker_view = false
        cemetery_lab_configure_camera(editor)
    }
    if canvas2d.IsKeyPressed(.G) {
        cemetery_lab_marker_view = !cemetery_lab_marker_view
        cemetery_lab_memorial_view = false
        cemetery_lab_configure_camera(editor)
    }
    if canvas2d.IsKeyPressed(.LEFT) {
        cemetery_lab_density = max(f32(.2), cemetery_lab_density - .1)
    }
    if canvas2d.IsKeyPressed(.RIGHT) {
        cemetery_lab_density = min(f32(1), cemetery_lab_density + .1)
    }
    if canvas2d.IsKeyPressed(.DOWN) {
        cemetery_lab_width = max(f32(12), cemetery_lab_width - 2)
        cemetery_lab_depth = max(f32(14), cemetery_lab_depth - 2)
        changed_size = true
    }
    if canvas2d.IsKeyPressed(.UP) {
        cemetery_lab_width = min(f32(42), cemetery_lab_width + 2)
        cemetery_lab_depth = min(f32(50), cemetery_lab_depth + 2)
        changed_size = true
    }
    if changed_size do cemetery_lab_configure_camera(editor)
}

cemetery_lab_stone_color :: proc(weathering: f32, variant: u8 = 0) -> canvas2d.Color {
    bases := [4][3]f32{{184, 179, 171}, {169, 174, 166}, {192, 181, 159}, {157, 160, 158}}
    base := bases[min(int(variant), len(bases) - 1)]
    loss := weathering * 38
    return {u8(max(base[0] - loss, 0)), u8(max(base[1] - loss, 0)), u8(max(base[2] - loss, 0)), 255}
}

cemetery_lab_color_mix :: proc(a, b: canvas2d.Color, amount: f32) -> canvas2d.Color {
    t := clamp(amount, f32(0), f32(1))
    return {
        u8(f32(a.r) + (f32(b.r) - f32(a.r)) * t),
        u8(f32(a.g) + (f32(b.g) - f32(a.g)) * t),
        u8(f32(a.b) + (f32(b.b) - f32(a.b)) * t),
        255,
    }
}

cemetery_lab_grave_front :: proc(grave: cemeteries.Grave, local_z: f32) -> [2]f32 {
    x, z := world_rotate_xz(grave.x, grave.z, 0, local_z, grave.rotation)
    return {x, z}
}

cemetery_lab_grave_relief_bar :: proc(
    grave: cemeteries.Grave,
    local_x, center_y, local_z, width, height: f32,
    color: canvas2d.Color,
) {
    x, z := world_rotate_xz(grave.x, grave.z, local_x, local_z, grave.rotation)
    world_box_rotated({x, center_y, z}, {width, height, .022}, grave.rotation, color)
}

cemetery_lab_draw_grave_relief :: proc(
    grave: cemeteries.Grave,
    center_y, local_z, width, height: f32,
    color: canvas2d.Color,
) {
    if !grave.has_relief do return
    thin := max(min(width, height) * .085, f32(.026))
    aegean := grave.pigment_strength > 0
    if aegean {
        panel := cemetery_lab_stone_color(clamp(grave.weathering + .34, f32(0), f32(1)), grave.stone_variant)
        cemetery_lab_grave_relief_bar(grave, 0, center_y, local_z + .012, width * 1.08, height * 1.08, panel)
        cemetery_lab_grave_relief_bar(grave, 0, center_y + height * .47, local_z - .008, width * 1.18, thin, color)
        cemetery_lab_grave_relief_bar(grave, 0, center_y - height * .47, local_z - .008, width * 1.18, thin, color)
    }
    switch grave.relief {
    case .Geometric_Border:
        cemetery_lab_grave_relief_bar(grave, 0, center_y + height * .42, local_z, width, thin, color)
        cemetery_lab_grave_relief_bar(grave, 0, center_y - height * .42, local_z, width, thin, color)
        cemetery_lab_grave_relief_bar(grave, -width * .46, center_y, local_z, thin, height, color)
        cemetery_lab_grave_relief_bar(grave, width * .46, center_y, local_z, thin, height, color)
    case .Cross:
        cemetery_lab_grave_relief_bar(grave, 0, center_y, local_z, thin, height, color)
        cemetery_lab_grave_relief_bar(grave, 0, center_y + height * .12, local_z, width * .72, thin, color)
    case .Solar_Rosette:
        cemetery_lab_grave_relief_bar(grave, 0, center_y, local_z, thin, height * .72, color)
        cemetery_lab_grave_relief_bar(grave, 0, center_y, local_z, width * .72, thin, color)
        cemetery_lab_grave_relief_bar(grave, 0, center_y, local_z - .012, thin * 2.6, thin * 2.6, color)
    case .Arcade:
        for column in -1 ..= 1 {
            cemetery_lab_grave_relief_bar(
                grave,
                f32(column) * width * .28,
                center_y,
                local_z,
                thin,
                height * .78,
                color,
            )
        }
        cemetery_lab_grave_relief_bar(grave, 0, center_y + height * .38, local_z, width, thin, color)
    case .Sword:
        cemetery_lab_grave_relief_bar(grave, 0, center_y, local_z, thin, height, color)
        cemetery_lab_grave_relief_bar(grave, 0, center_y - height * .18, local_z, width * .62, thin, color)
    case .Round_Dance:
        for band in -1 ..= 1 {
            cemetery_lab_grave_relief_bar(
                grave,
                0,
                center_y + f32(band) * height * .28,
                local_z,
                width * (band == 0 ? f32(.62) : f32(.86)),
                thin,
                color,
            )
        }
    case .Palmette:
        cemetery_lab_grave_relief_bar(grave, 0, center_y - height * .12, local_z, thin, height * .82, color)
        for frond in -1 ..= 1 {
            cemetery_lab_grave_relief_bar(
                grave,
                0,
                center_y + f32(frond) * height * .20,
                local_z,
                width * (.42 + f32(frond + 1) * .14),
                thin,
                color,
            )
        }
    case .Wreath:
        cemetery_lab_grave_relief_bar(grave, 0, center_y + height * .34, local_z, width * .70, thin, color)
        cemetery_lab_grave_relief_bar(grave, 0, center_y - height * .34, local_z, width * .70, thin, color)
        cemetery_lab_grave_relief_bar(grave, -width * .34, center_y, local_z, thin, height * .62, color)
        cemetery_lab_grave_relief_bar(grave, width * .34, center_y, local_z, thin, height * .62, color)
    case .Farewell_Panel:
        cemetery_lab_grave_relief_bar(grave, -width * .18, center_y, local_z, thin * 2.2, height * .72, color)
        cemetery_lab_grave_relief_bar(
            grave,
            width * .18,
            center_y - height * .06,
            local_z,
            thin * 2.2,
            height * .60,
            color,
        )
        cemetery_lab_grave_relief_bar(grave, 0, center_y - height * .36, local_z, width * .72, thin, color)
    case .Amphora:
        cemetery_lab_grave_relief_bar(grave, 0, center_y, local_z, width * .54, height * .48, color)
        cemetery_lab_grave_relief_bar(grave, 0, center_y + height * .28, local_z, width * .20, height * .18, color)
        cemetery_lab_grave_relief_bar(grave, 0, center_y - height * .30, local_z, width * .26, thin, color)
    }
}

cemetery_lab_draw_grave_inscription :: proc(
    grave: cemeteries.Grave,
    center_y, local_z, width, height: f32,
    color: canvas2d.Color,
) {
    if !grave.has_inscription do return
    point := cemetery_lab_grave_front(grave, local_z)
    line_count := int(grave.inscription) + 1
    spacing := height / f32(line_count + 1)
    for line in 0 ..< line_count {
        line_width := width * (.78 - f32(line & 1) * .13)
        y := center_y + (f32(line_count - 1) * .5 - f32(line)) * spacing
        world_box_rotated({point[0], y, point[1]}, {line_width, .014, .012}, grave.rotation, color)
    }
}

cemetery_lab_draw_grave_top_inscription :: proc(
    grave: cemeteries.Grave,
    surface_y, center_local_z, width, depth: f32,
    color: canvas2d.Color,
) {
    if !grave.has_inscription do return
    line_count := int(grave.inscription) + 1
    spacing := depth / f32(line_count + 1)
    for line in 0 ..< line_count {
        line_width := width * (.78 - f32(line & 1) * .13)
        local_z := center_local_z + (f32(line_count - 1) * .5 - f32(line)) * spacing
        point := cemetery_lab_grave_front(grave, local_z)
        world_box_rotated({point[0], surface_y, point[1]}, {line_width, .012, .014}, grave.rotation, color)
    }
}

cemetery_lab_draw_grave :: proc(grave: cemeteries.Grave) {
    stone := cemetery_lab_stone_color(grave.weathering, grave.stone_variant)
    shadow := cemetery_lab_stone_color(clamp(grave.weathering + .22, f32(0), f32(1)), grave.stone_variant)
    pigments := [4]canvas2d.Color{{132, 55, 43, 255}, {52, 83, 108, 255}, {65, 94, 67, 255}, {153, 119, 48, 255}}
    relief_color := cemetery_lab_color_mix(shadow, pigments[grave.pigment], grave.pigment_strength)
    lettering := canvas2d.Color{82, 78, 69, 255}
    aegean := grave.pigment_strength > 0
    base_y := grave.ground_y + .04
    horizontal_monolith := grave.marker == .Slab || grave.marker == .Chest || grave.marker == .Gabled
    base_depth := horizontal_monolith ? grave.depth + .18 : max(grave.depth * 1.7, f32(.34))
    if grave.has_base {
        world_box_rotated(
            {grave.x, base_y + grave.base_height * .5, grave.z},
            {grave.base_width, grave.base_height, base_depth},
            grave.rotation,
            shadow,
        )
        base_y += grave.base_height
    }
    switch grave.marker {
    case .Stele:
        body_height := grave.height * (aegean ? f32(.78) : (grave.profile == 2 ? f32(.74) : f32(.82)))
        world_box_rotated(
            {grave.x, base_y + body_height * .5, grave.z},
            {grave.width, body_height, grave.depth},
            grave.rotation,
            stone,
        )
        if aegean {
            crown_height := grave.height - body_height
            cap_height := crown_height * .24
            cap_y := base_y + body_height + cap_height * .25
            world_box_rotated(
                {grave.x, cap_y, grave.z},
                {grave.width * 1.12, cap_height, grave.depth * 1.12},
                grave.rotation,
                shadow,
            )
            world_tube_between(
                {grave.x, cap_y, grave.z},
                {grave.x, base_y + grave.height, grave.z},
                {0, 0, 1},
                grave.width * .52,
                .025,
                stone,
            )
        } else if grave.profile == 0 {
            top_forward := third_person.Vec3{math.sin(grave.rotation), 0, math.cos(grave.rotation)}
            world_tube_between(
                {grave.x, base_y + body_height, grave.z},
                {grave.x, base_y + grave.height, grave.z},
                top_forward,
                grave.width * .5,
                grave.depth * .52,
                stone,
            )
        } else if grave.profile == 1 {
            world_tube_between(
                {grave.x, base_y + body_height, grave.z},
                {grave.x, base_y + grave.height, grave.z},
                {0, 0, 1},
                grave.width * .52,
                .025,
                stone,
            )
        } else if grave.profile == 2 {
            shoulder_y := base_y + body_height + (grave.height - body_height) * .35
            for side in -1 ..= 1 {
                if side == 0 do continue
                world_box_rotated(
                    {grave.x + f32(side) * grave.width * .38, shoulder_y, grave.z},
                    {grave.width * .24, (grave.height - body_height) * .7, grave.depth},
                    grave.rotation,
                    shadow,
                )
            }
            world_box_rotated(
                {grave.x, base_y + grave.height - (grave.height - body_height) * .5, grave.z},
                {grave.width * .58, grave.height - body_height, grave.depth},
                grave.rotation,
                stone,
            )
        } else {
            world_box_rotated(
                {grave.x, base_y + body_height + (grave.height - body_height) * .42, grave.z},
                {grave.width * 1.12, (grave.height - body_height) * .28, grave.depth * 1.18},
                grave.rotation,
                shadow,
            )
            world_tube_between(
                {grave.x, base_y + body_height, grave.z},
                {grave.x, base_y + grave.height, grave.z},
                {0, 0, 1},
                grave.width * .38,
                grave.depth * .52,
                stone,
            )
        }
        cemetery_lab_draw_grave_relief(
            grave,
            base_y + body_height * .54,
            -grave.depth * .55,
            grave.width * .66,
            body_height * .48,
            relief_color,
        )
        cemetery_lab_draw_grave_inscription(
            grave,
            base_y + body_height * .52,
            -grave.depth * .5 + .004,
            grave.width * .68,
            body_height * .44,
            lettering,
        )
    case .Cross:
        stem_width := grave.profile & 1 == 0 ? f32(.18) : f32(.23)
        world_box_rotated(
            {grave.x, base_y + grave.height * .5, grave.z},
            {stem_width, grave.height, grave.depth},
            grave.rotation,
            stone,
        )
        arm_y := grave.profile < 2 ? f32(.67) : f32(.73)
        world_box_rotated(
            {grave.x, base_y + grave.height * arm_y, grave.z},
            {grave.width, stem_width, grave.depth},
            grave.rotation,
            stone,
        )
        if grave.profile == 1 || grave.profile == 3 {
            world_vertical_prism(
                {grave.x, base_y + grave.height * arm_y, grave.z - grave.depth * .12},
                stem_width * 1.35,
                grave.depth * .62,
                stem_width * 1.35,
                grave.rotation,
                shadow,
            )
        }
    case .Slab:
        world_box_rotated(
            {grave.x, base_y + grave.height * .5, grave.z + grave.depth * .12},
            {grave.width, grave.height, grave.depth * .84},
            grave.rotation,
            stone,
        )
        if grave.profile & 1 == 1 {
            world_box_rotated(
                {grave.x, base_y + grave.height + .025, grave.z + grave.depth * .12},
                {grave.width * .78, .05, grave.depth * .62},
                grave.rotation,
                shadow,
            )
        }
        cemetery_lab_draw_grave_top_inscription(
            grave,
            base_y + grave.height + (grave.profile & 1 == 1 ? f32(.044) : f32(-.004)),
            grave.depth * .12,
            grave.width * .58,
            grave.depth * .38,
            lettering,
        )
    case .Pillar:
        shaft_height := grave.height * .72
        if aegean {
            world_vertical_prism(
                {grave.x, base_y + shaft_height * .5, grave.z},
                grave.width * .5,
                grave.depth * .5,
                shaft_height,
                grave.rotation,
                stone,
            )
            world_vertical_prism(
                {grave.x, base_y + .055, grave.z},
                grave.width * .66,
                grave.depth * .66,
                .11,
                grave.rotation,
                shadow,
            )
        } else {
            world_box_rotated(
                {grave.x, base_y + shaft_height * .5, grave.z},
                {grave.width, shaft_height, grave.depth},
                grave.rotation,
                stone,
            )
        }
        world_box_rotated(
            {grave.x, base_y + shaft_height + .07, grave.z},
            {grave.width * 1.28, .14, grave.depth * 1.28},
            grave.rotation,
            shadow,
        )
        if aegean {
            world_vertical_prism(
                {grave.x, base_y + shaft_height + .14 + (grave.height - shaft_height - .14) * .5, grave.z},
                grave.width * .46,
                grave.depth * .46,
                grave.height - shaft_height - .14,
                grave.rotation,
                stone,
            )
        } else {
            world_tube_between(
                {grave.x, base_y + shaft_height + .14, grave.z},
                {grave.x, base_y + grave.height, grave.z},
                {0, 0, 1},
                grave.width * .48,
                grave.profile & 1 == 0 ? f32(.08) : grave.width * .30,
                stone,
            )
        }
        cemetery_lab_draw_grave_inscription(
            grave,
            base_y + shaft_height * .48,
            -grave.depth * .5 + .004,
            grave.width * .68,
            shaft_height * .42,
            lettering,
        )
    case .Plaque:
        support_height := grave.height * .32
        world_box_rotated(
            {grave.x, base_y + support_height * .5, grave.z + .08},
            {grave.width * .72, support_height, grave.depth * 1.2},
            grave.rotation,
            shadow,
        )
        world_box_rotated(
            {grave.x, base_y + support_height + grave.height * .34, grave.z},
            {grave.width, grave.height * .68, grave.depth},
            grave.rotation,
            stone,
        )
        cemetery_lab_draw_grave_inscription(
            grave,
            base_y + support_height + grave.height * .34,
            -grave.depth * .5 + .004,
            grave.width * .68,
            grave.height * .42,
            lettering,
        )
    case .Chest:
        world_box_rotated(
            {grave.x, base_y + grave.height * .5, grave.z},
            {grave.width, grave.height, grave.depth},
            grave.rotation,
            stone,
        )
        world_box_rotated(
            {grave.x, base_y + grave.height + .035, grave.z},
            {grave.width * .92, .07, grave.depth * .92},
            grave.rotation,
            shadow,
        )
        cemetery_lab_draw_grave_relief(
            grave,
            base_y + grave.height * .54,
            -grave.depth * .525,
            grave.width * .70,
            grave.height * .56,
            relief_color,
        )
        cemetery_lab_draw_grave_inscription(
            grave,
            base_y + grave.height * .54,
            -grave.depth * .5 + .004,
            grave.width * .66,
            grave.height * .48,
            lettering,
        )
    case .Gabled:
        body_height := grave.height * .58
        world_box_rotated(
            {grave.x, base_y + body_height * .5, grave.z},
            {grave.width, body_height, grave.depth},
            grave.rotation,
            stone,
        )
        half_width, half_depth := grave.width * .5, grave.depth * .5
        eave_y, peak_y := base_y + body_height, base_y + grave.height
        left_front_x, left_front_z := world_rotate_xz(grave.x, grave.z, -half_width, -half_depth, grave.rotation)
        left_back_x, left_back_z := world_rotate_xz(grave.x, grave.z, -half_width, half_depth, grave.rotation)
        right_front_x, right_front_z := world_rotate_xz(grave.x, grave.z, half_width, -half_depth, grave.rotation)
        right_back_x, right_back_z := world_rotate_xz(grave.x, grave.z, half_width, half_depth, grave.rotation)
        ridge_front_x, ridge_front_z := world_rotate_xz(grave.x, grave.z, 0, -half_depth, grave.rotation)
        ridge_back_x, ridge_back_z := world_rotate_xz(grave.x, grave.z, 0, half_depth, grave.rotation)
        world_quad(
            {left_front_x, eave_y, left_front_z},
            {left_back_x, eave_y, left_back_z},
            {ridge_back_x, peak_y, ridge_back_z},
            {ridge_front_x, peak_y, ridge_front_z},
            stone,
        )
        world_quad(
            {ridge_front_x, peak_y, ridge_front_z},
            {ridge_back_x, peak_y, ridge_back_z},
            {right_back_x, eave_y, right_back_z},
            {right_front_x, eave_y, right_front_z},
            shadow,
        )
        world_triangle(
            {left_front_x, eave_y, left_front_z},
            {ridge_front_x, peak_y, ridge_front_z},
            {right_front_x, eave_y, right_front_z},
            stone,
        )
        world_triangle(
            {right_back_x, eave_y, right_back_z},
            {ridge_back_x, peak_y, ridge_back_z},
            {left_back_x, eave_y, left_back_z},
            shadow,
        )
        cemetery_lab_draw_grave_relief(
            grave,
            base_y + body_height * .54,
            -grave.depth * .525,
            grave.width * .70,
            body_height * .52,
            relief_color,
        )
        cemetery_lab_draw_grave_inscription(
            grave,
            base_y + body_height * .54,
            -grave.depth * .5 + .004,
            grave.width * .66,
            body_height * .44,
            lettering,
        )
    }
}

cemetery_lab_draw_inscription :: proc(
    memorial: cemeteries.Memorial,
    center_y, local_z, width, height: f32,
    panel_color, lettering_color: canvas2d.Color,
) {
    panel_x, panel_z := world_rotate_xz(memorial.x, memorial.z, 0, local_z, memorial.rotation)
    world_box_rotated(
        {panel_x, center_y, panel_z},
        {width, height, .055 * memorial.scale},
        memorial.rotation,
        panel_color,
    )
    line_count := int(memorial.inscription) + 1
    line_height := min(height / f32(line_count + 2), .075 * memorial.scale)
    for line in 0 ..< line_count {
        line_width := width * (.72 - f32(line & 1) * .12)
        line_y := center_y + (f32(line_count - 1) * .5 - f32(line)) * line_height * 1.65
        line_x, line_z := world_rotate_xz(
            memorial.x,
            memorial.z,
            0,
            local_z - .032 * memorial.scale,
            memorial.rotation,
        )
        world_box_rotated(
            {line_x, line_y, line_z},
            {line_width, line_height * .28, .018 * memorial.scale},
            memorial.rotation,
            lettering_color,
        )
    }
}

cemetery_lab_draw_memorial :: proc(memorial: cemeteries.Memorial, court_color: canvas2d.Color, ground_y: f32 = 0) {
    stone := cemetery_lab_stone_color(memorial.weathering * .55)
    dark_stone := cemetery_lab_stone_color(clamp(memorial.weathering + .24, f32(0), f32(1)))
    plaque := canvas2d.Color{73, 72, 66, 255}
    lettering := canvas2d.Color{190, 169, 112, 255}
    center := third_person.Vec3{memorial.x, ground_y, memorial.z}
    world_tube_between(
        center,
        center + third_person.Vec3{0, .055, 0},
        {0, 0, 1},
        memorial.court_radius,
        memorial.court_radius,
        court_color,
    )

    for step in 0 ..< memorial.step_count {
        inset := f32(step) * .25 * memorial.scale
        width := memorial.base_width - inset
        height := .16 * memorial.scale
        y := ground_y + .055 + height * (.5 + f32(step))
        world_box_rotated({memorial.x, y, memorial.z}, {width, height, width * .82}, memorial.rotation, stone)
    }
    base_y := ground_y + .055 + f32(memorial.step_count) * .16 * memorial.scale
    top_y := ground_y + memorial.height

    switch memorial.kind {
    case .Obelisk:
        plinth_height := .62 * memorial.scale
        world_box_rotated(
            {memorial.x, base_y + plinth_height * .5, memorial.z},
            {memorial.base_width * .62, plinth_height, memorial.base_width * .56},
            memorial.rotation,
            dark_stone,
        )
        shaft_bottom := base_y + plinth_height
        shaft_top := top_y - .34 * memorial.scale
        world_tube_between(
            {memorial.x, shaft_bottom, memorial.z},
            {memorial.x, shaft_top, memorial.z},
            {0, 0, 1},
            .38 * memorial.scale,
            .18 * memorial.scale,
            stone,
        )
        world_tube_between(
            {memorial.x, shaft_top, memorial.z},
            {memorial.x, top_y, memorial.z},
            {0, 0, 1},
            .18 * memorial.scale,
            .015,
            stone,
        )
        cemetery_lab_draw_inscription(
            memorial,
            base_y + plinth_height * .55,
            -memorial.base_width * .285,
            memorial.base_width * .38,
            plinth_height * .44,
            plaque,
            lettering,
        )
    case .Cross:
        stem_height := top_y - base_y
        world_box_rotated(
            {memorial.x, base_y + stem_height * .5, memorial.z},
            {.34 * memorial.scale, stem_height, .30 * memorial.scale},
            memorial.rotation,
            stone,
        )
        world_box_rotated(
            {memorial.x, base_y + stem_height * .67, memorial.z},
            {1.65 * memorial.scale, .32 * memorial.scale, .30 * memorial.scale},
            memorial.rotation,
            stone,
        )
        world_box_rotated(
            {memorial.x, base_y + .38 * memorial.scale, memorial.z + .18},
            {1.25 * memorial.scale, .62 * memorial.scale, .24 * memorial.scale},
            memorial.rotation,
            dark_stone,
        )
        cemetery_lab_draw_inscription(
            memorial,
            base_y + .38 * memorial.scale,
            .18 - .135 * memorial.scale,
            .76 * memorial.scale,
            .28 * memorial.scale,
            plaque,
            lettering,
        )
    case .Stele:
        body_height := top_y - base_y
        world_box_rotated(
            {memorial.x, base_y + body_height * .47, memorial.z},
            {1.9 * memorial.scale, body_height * .94, .34 * memorial.scale},
            memorial.rotation,
            stone,
        )
        world_tube_between(
            {memorial.x, base_y + body_height * .91, memorial.z},
            {memorial.x, top_y, memorial.z},
            {0, 0, 1},
            .95 * memorial.scale,
            .18 * memorial.scale,
            stone,
        )
        cemetery_lab_draw_inscription(
            memorial,
            base_y + body_height * .50,
            -.19 * memorial.scale,
            1.28 * memorial.scale,
            body_height * .48,
            plaque,
            lettering,
        )
        for side in -1 ..= 1 {
            if side == 0 do continue
            world_box_rotated(
                {memorial.x + f32(side) * 1.12 * memorial.scale, base_y + .48 * memorial.scale, memorial.z + .08},
                {.42 * memorial.scale, .96 * memorial.scale, .42 * memorial.scale},
                memorial.rotation,
                dark_stone,
            )
        }
    case .Shrine:
        column_offset := memorial.base_width * .32
        roof_y := top_y - .54 * memorial.scale
        for side_x in -1 ..= 1 {
            if side_x == 0 do continue
            for side_z in -1 ..= 1 {
                if side_z == 0 do continue
                x := memorial.x + f32(side_x) * column_offset
                z := memorial.z + f32(side_z) * column_offset * .64
                world_tube_between(
                    {x, base_y, z},
                    {x, roof_y, z},
                    {0, 0, 1},
                    .16 * memorial.scale,
                    .14 * memorial.scale,
                    stone,
                )
            }
        }
        world_box_rotated(
            {memorial.x, roof_y + .18 * memorial.scale, memorial.z},
            {memorial.base_width, .36 * memorial.scale, memorial.base_width * .72},
            memorial.rotation,
            dark_stone,
        )
        world_box_rotated(
            {memorial.x, base_y + .92 * memorial.scale, memorial.z + column_offset * .56},
            {1.2 * memorial.scale, 1.84 * memorial.scale, .22 * memorial.scale},
            memorial.rotation,
            stone,
        )
        cemetery_lab_draw_inscription(
            memorial,
            base_y + .96 * memorial.scale,
            column_offset * .56 - .13 * memorial.scale,
            .78 * memorial.scale,
            .92 * memorial.scale,
            plaque,
            lettering,
        )
        world_box_rotated(
            {memorial.x, top_y - .05, memorial.z},
            {.18 * memorial.scale, .70 * memorial.scale, .16 * memorial.scale},
            memorial.rotation,
            stone,
        )
        world_box_rotated(
            {memorial.x, top_y + .08 * memorial.scale, memorial.z},
            {.62 * memorial.scale, .16 * memorial.scale, .16 * memorial.scale},
            memorial.rotation,
            stone,
        )
    }

    if memorial.flanking_urns {
        for side in -1 ..= 1 {
            if side == 0 do continue
            x := memorial.x + f32(side) * memorial.base_width * .68
            world_vertical_prism(
                {x, base_y + .32 * memorial.scale, memorial.z},
                .25 * memorial.scale,
                .20 * memorial.scale,
                .64 * memorial.scale,
                0,
                dark_stone,
            )
        }
    }
}

world_cemetery_marker_gallery :: proc() {
    ground := canvas2d.Color{92, 111, 71, 255}
    stone_walk := canvas2d.Color{139, 132, 117, 255}
    world_box_rotated({0, -.10, 0}, {11, .20, 5.5}, 0, ground)
    world_box_rotated({0, .015, .18}, {8.8, .05, 2.3}, 0, stone_walk)

    samples: [7]cemeteries.Grave
    found: [7]bool
    found_count := 0
    for seed in u32(0) ..< 16 {
        if found_count == len(found) do break
        plan := cemeteries.generate(
            CEMETERY_LAB_DEFAULT_SEED + seed,
            {width = 34, depth = 42, density = 1, style = cemetery_lab_style},
        )
        for grave in plan.graves[:plan.grave_count] {
            index := int(grave.marker)
            if found[index] do continue
            samples[index] = grave
            found[index] = true
            found_count += 1
        }
    }
    display_index := 0
    for &grave, index in samples {
        if !found[index] do continue
        grave.x = (f32(display_index) - f32(found_count - 1) * .5) * 1.72
        grave.z = 0
        grave.rotation = 0
        cemetery_lab_draw_grave(grave)
        display_index += 1
    }
}

world_cemetery_generator_lab :: proc(_: ^Editor) {
    if cemetery_lab_marker_view {
        world_cemetery_marker_gallery()
        return
    }
    plan := cemetery_lab_plan()
    grass := plan.style == .Adriatic_Medieval ? canvas2d.Color{112, 126, 72, 255} : canvas2d.Color{88, 119, 73, 255}
    path := plan.style == .Memorial_Garden ? canvas2d.Color{151, 143, 126, 255} : canvas2d.Color{136, 125, 103, 255}
    wall := plan.style == .Adriatic_Medieval ? canvas2d.Color{192, 183, 158, 255} : canvas2d.Color{139, 135, 121, 255}
    world_box_rotated({0, -.13, 0}, {plan.width + 6, .26, plan.depth + 6}, 0, grass)
    world_box_rotated({0, .015, 0}, {plan.path_width, .04, plan.depth - 1.2}, 0, path)

    half_width, half_depth := plan.width * .5, plan.depth * .5
    thickness := f32(.34)
    world_box_rotated({-half_width, plan.wall_height * .5, 0}, {thickness, plan.wall_height, plan.depth}, 0, wall)
    world_box_rotated({half_width, plan.wall_height * .5, 0}, {thickness, plan.wall_height, plan.depth}, 0, wall)
    world_box_rotated({0, plan.wall_height * .5, half_depth}, {plan.width, plan.wall_height, thickness}, 0, wall)
    side_wall_width := (plan.width - plan.gate_width) * .5
    world_box_rotated(
        {-(plan.gate_width + side_wall_width) * .5, plan.wall_height * .5, -half_depth},
        {side_wall_width, plan.wall_height, thickness},
        0,
        wall,
    )
    world_box_rotated(
        {(plan.gate_width + side_wall_width) * .5, plan.wall_height * .5, -half_depth},
        {side_wall_width, plan.wall_height, thickness},
        0,
        wall,
    )
    for side in -1 ..= 1 {
        if side == 0 do continue
        x := f32(side) * plan.gate_width * .5
        world_box_rotated({x, plan.wall_height * .75, -half_depth}, {.52, plan.wall_height * 1.5, .52}, 0, wall)
    }

    for grave in plan.graves[:plan.grave_count] do cemetery_lab_draw_grave(grave)
    for tree, tree_index in plan.trees[:plan.tree_count] {
        tree_seed := u64(cemeteries.mix(plan.seed ~ u32(tree_index + 1) * 0x9e3779b9))
        species := plants.Species.Italian_Cypress
        if plan.style == .Memorial_Garden && tree_index % 3 == 1 do species = .Olive
        maturity := clamp(.76 + (tree.height - 3.8) / 14, f32(.76), f32(.96))
        scale := species == .Italian_Cypress ? f32(.82) : f32(.74)
        scale *= .9 + tree.radius * .16
        _ = world_generated_plant(
            species,
            tree_seed,
            {tree.x, 0, tree.z},
            scale,
            f32(tree_index) * .73,
            .Free_Standing,
            nil,
            .Near,
            0,
            maturity,
        )
    }

    cemetery_lab_draw_memorial(plan.memorial, path)
}

cemetery_lab_draw_ui :: proc(_: ^Editor, width, height: i32) {
    plan := cemetery_lab_plan()
    panel := canvas2d.Rectangle {
        x      = 22,
        y      = 22,
        width  = 520,
        height = 164,
    }
    canvas2d.DrawRectangleRounded(panel, .10, 8, {10, 27, 37, 226})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {104, 168, 184, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "CEMETERY / GRAVEYARD GENERATOR LAB", {38, 38}, 20, 1, {245, 238, 197, 255})
    status := fmt.ctprintf("MARKER GALLERY   %s   SOURCE-BACKED FORMS", cemetery_lab_style_name())
    if !cemetery_lab_marker_view {
        status = fmt.ctprintf(
            "SEED %08X   %s   %s   %d GRAVES",
            cemetery_lab_seed,
            cemetery_lab_style_name(),
            cemetery_lab_memorial_name(plan.memorial.kind),
            plan.grave_count,
        )
    }
    canvas2d.DrawTextEx(canvas2d.Font{}, status, {38, 72}, 14, 1, {208, 239, 240, 255})
    dimensions := fmt.ctprintf("%.0f x %.0f m   DENSITY %.0f%%", plan.width, plan.depth, cemetery_lab_density * 100)
    canvas2d.DrawTextEx(canvas2d.Font{}, dimensions, {38, 98}, 13, 1, {184, 213, 216, 255})
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        "A / D seed   S style   M memorial   N auto   V memorial view   G markers",
        {38, 124},
        13,
        1,
        {171, 201, 207, 255},
    )
    canvas2d.DrawTextEx(canvas2d.Font{}, "LEFT / RIGHT density     UP / DOWN grounds size", {38, 148}, 13, 1, {171, 201, 207, 255})
    _ = width
    _ = height
}
