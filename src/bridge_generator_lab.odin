package main

import atmosphere "../packages/atmosphere"
import bridges "../packages/bridges"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

bridge_lab_seed := u32(0xB12D6E)
bridge_lab_config: bridges.Config
bridge_lab_cleft_width := f32(30)
bridge_lab_cleft_depth := f32(7)
bridge_lab_bank_slope := f32(4)
bridge_lab_archetype_bounds :: proc() -> canvas2d.Rectangle {return {38, 68, 232, 28}}
bridge_lab_seed_bounds :: proc() -> canvas2d.Rectangle {return {282, 68, 154, 28}}
bridge_lab_length_bounds :: proc() -> canvas2d.Rectangle {return {38, 116, 128, 28}}
bridge_lab_spans_bounds :: proc() -> canvas2d.Rectangle {return {178, 116, 118, 28}}
bridge_lab_clearance_bounds :: proc() -> canvas2d.Rectangle {return {308, 116, 136, 28}}
bridge_lab_cleft_width_bounds :: proc() -> canvas2d.Rectangle {return {456, 116, 136, 28}}
bridge_lab_cleft_depth_bounds :: proc() -> canvas2d.Rectangle {return {604, 116, 136, 28}}
bridge_lab_cutwaters_bounds :: proc() -> canvas2d.Rectangle {return {38, 160, 122, 28}}
bridge_lab_shops_bounds :: proc() -> canvas2d.Rectangle {return {172, 160, 104, 28}}

bridge_lab_archetype_name :: proc(value: bridges.Archetype) -> cstring {
    switch value {
    case .Dalmatian_Multi_Arch:
        return "DALMATIAN MULTI-ARCH"
    case .Herzegovinian_High_Arch:
        return "HERZEGOVINIAN HIGH ARCH"
    case .Venetian_Canal:
        return "VENETIAN CANAL"
    case .Cycladic_Rural:
        return "CYCLADIC RURAL"
    case .Aegean_Fortress:
        return "AEGEAN FORTRESS APPROACH"
    case .Timber_Trestle:
        return "TIMBER TRESTLE"
    case .Iron_Truss:
        return "IRON TRUSS"
    }
    return "BRIDGE"
}

bridge_lab_region_name :: proc(value: bridges.Region) -> cstring {
    switch value {case .Adriatic:
        return "ADRIATIC"; case .Aegean:
        return "AEGEAN"; case .Later_Era:
        return "LATER ERA"}
    return "REGION"
}

bridge_lab_material_name :: proc(value: bridges.Material) -> cstring {
    switch value {
    case .Limestone:
        return "LIMESTONE"
    case .Travertine:
        return "TRAVERTINE"
    case .Istrian_Stone:
        return "ISTRIAN STONE"
    case .Slate:
        return "SLATE"
    case .Fieldstone:
        return "FIELDSTONE"
    case .Timber:
        return "TIMBER"
    case .Iron:
        return "IRON"
    }
    return "MATERIAL"
}

bridge_lab_apply_archetype :: proc(archetype: bridges.Archetype) {
    bridge_lab_config = bridges.defaults(archetype)
    bridge_lab_cleft_width = bridge_lab_config.length * .82
    bridge_lab_cleft_depth = bridge_lab_config.clearance + 1.6
    bridge_lab_bank_slope = clamp(bridge_lab_config.length * .12, f32(2.5), f32(7))
}

bridge_lab_smooth01 :: #force_inline proc(value: f32) -> f32 {
    t := clamp(value, f32(0), f32(1))
    return t * t * (3 - 2 * t)
}

bridge_lab_terrain_sample :: proc(_: ^Editor, world_x, world_z: f32) -> Lab_Terrain_Sample {
    plateau := bridge_lab_config.clearance
    floor := plateau - bridge_lab_cleft_depth
    phase := f32(bridge_lab_seed & 255) / 255 * math.PI * 2
    center := math.sin(world_z * .045 + phase) * bridge_lab_cleft_width * .045
    distance := abs(world_x - center)
    // Cleft width is the complete rim-to-rim opening. Subtract the two bank
    // transitions before finding the flat channel floor so the bridge always
    // retains a landing beyond each rim.
    half_floor := max(f32(1), bridge_lab_cleft_width * .5 - bridge_lab_bank_slope)
    bank := bridge_lab_smooth01((distance - half_floor) / bridge_lab_bank_slope)
    broad_undulation := math.sin(world_x * .065 + phase) * .10 + math.sin(world_z * .052 - phase) * .08
    height := floor + (plateau - floor) * bank
    if bank > .98 do height += broad_undulation
    // Seat each approach in a small, level landing cut into the generated
    // bank. The landing is slightly below paving so stone overlaps terrain
    // instead of relying on two independently sampled surfaces to coincide.
    terminus_distance := abs(abs(world_x) - bridge_lab_config.length * .5)
    landing_along := 1 - bridge_lab_smooth01(max(f32(0), terminus_distance - 2.8) / 2.2)
    landing_across := 1 - bridge_lab_smooth01(max(f32(0), abs(world_z) - bridge_lab_config.width * .62) / 2.4)
    landing_weight := landing_along * landing_across
    height += (plateau - .10 - height) * landing_weight
    material := -.95 + (bank * .95)
    if height > .35 do material = .22 + broad_undulation
    return {height = height, material = material}
}

bridge_lab_regenerate_terrain :: proc(editor: ^Editor) {
    if editor == nil do return
    extent_x := bridge_lab_config.length * .5 + bridge_lab_bank_slope + 18
    // Carry the cleft well beyond the authored camera so the focused patch
    // reads as a continuous landform instead of a rectangular test basin.
    extent_z := max(f32(110), bridge_lab_config.width * 8)
    _ = lab_terrain_load(
        editor,
        {
            half_extent_x = extent_x,
            half_extent_z = extent_z,
            sea_level = 0,
            outside_height = bridge_lab_config.clearance,
            outside_material = .22,
        },
        bridge_lab_terrain_sample,
    )
}

bridge_generator_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    bridge_lab_seed = 0xB12D6E
    bridge_lab_apply_archetype(.Dalmatian_Multi_Arch)
    switch target {
    case "", "adriatic", "dalmatian", "multi-arch":
    case "herzegovinian", "high-arch", "mostar":
        bridge_lab_apply_archetype(.Herzegovinian_High_Arch)
    case "venetian", "canal":
        bridge_lab_apply_archetype(.Venetian_Canal)
    case "rialto":
        bridge_lab_apply_archetype(.Venetian_Canal)
        bridge_lab_config.urban_shops = true
        bridge_lab_config.length = 30
        bridge_lab_config.width = 8
    case "aegean", "cycladic", "rural":
        bridge_lab_apply_archetype(.Cycladic_Rural)
    case "fortress", "andros":
        bridge_lab_apply_archetype(.Aegean_Fortress)
    case "timber", "trestle":
        bridge_lab_apply_archetype(.Timber_Trestle)
    case "iron", "truss":
        bridge_lab_apply_archetype(.Iron_Truss)
    case:
        return false
    }
    bridge_lab_regenerate_terrain(editor)
    editor.in_map = true
    editor.capture_world_only = false
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    editor.project.sea_level = 0
    atmosphere.set_world_minutes(&editor.atmosphere, 16 * 60 + 10)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    camera_eye := third_person.Vec3{34, 17, 30}
    camera_target := third_person.Vec3{0, 4.2, 0}
    switch bridge_lab_config.archetype {
    case .Herzegovinian_High_Arch:
        camera_eye, camera_target = {25, 14, 22}, {0, 5.2, 0}
    case .Venetian_Canal:
        camera_eye, camera_target = {20, 10, 18}, {0, 3.4, 0}
    case .Cycladic_Rural:
        camera_eye, camera_target = {14, 8, 13}, {0, 2.9, 0}
    case .Aegean_Fortress:
        camera_eye, camera_target = {19, 11, 17}, {0, 4.0, 0}
    case .Timber_Trestle, .Iron_Truss:
        camera_eye, camera_target = {27, 14, 24}, {0, 4.0, 0}
    case .Dalmatian_Multi_Arch:
    }
    editor.camera_pose = third_person.camera_look_at(camera_eye, camera_target)
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

bridge_generator_lab_process_input :: proc(editor: ^Editor) {
    terrain_changed := false
    if lab_ui_button_pressed(bridge_lab_archetype_bounds()) {
        count := int(bridges.Archetype.Iron_Truss) + 1
        bridge_lab_apply_archetype(bridges.Archetype((int(bridge_lab_config.archetype) + 1) % count))
        terrain_changed = true
    }
    if lab_ui_button_pressed(bridge_lab_seed_bounds()) {
        bridge_lab_seed += 1
        terrain_changed = true
    }
    length_delta := lab_ui_stepper_delta(bridge_lab_length_bounds())
    spans_delta := lab_ui_stepper_delta(bridge_lab_spans_bounds())
    clearance_delta := lab_ui_stepper_delta(bridge_lab_clearance_bounds())
    cleft_width_delta := lab_ui_stepper_delta(bridge_lab_cleft_width_bounds())
    cleft_depth_delta := lab_ui_stepper_delta(bridge_lab_cleft_depth_bounds())
    if length_delta != 0 {
        bridge_lab_config.length = clamp(bridge_lab_config.length + f32(length_delta) * 2, f32(10), f32(80))
        bridge_lab_cleft_width = min(bridge_lab_cleft_width, bridge_lab_config.length * .90)
        terrain_changed = true
    }
    if spans_delta != 0 do bridge_lab_config.span_count = clamp(bridge_lab_config.span_count + spans_delta, 1, bridges.MAX_SPANS)
    if clearance_delta != 0 {
        bridge_lab_config.clearance = clamp(bridge_lab_config.clearance + f32(clearance_delta) * .5, f32(2.5), f32(16))
        terrain_changed = true
    }
    if cleft_width_delta != 0 {
        bridge_lab_cleft_width = clamp(bridge_lab_cleft_width + f32(cleft_width_delta), f32(4), bridge_lab_config.length * .90)
        terrain_changed = true
    }
    if cleft_depth_delta != 0 {
        bridge_lab_cleft_depth = clamp(bridge_lab_cleft_depth + f32(cleft_depth_delta) * .5, f32(2), f32(18))
        terrain_changed = true
    }
    if lab_ui_button_pressed(bridge_lab_cutwaters_bounds()) do bridge_lab_config.pier_cutwaters = !bridge_lab_config.pier_cutwaters
    if bridge_lab_config.archetype == .Venetian_Canal && lab_ui_button_pressed(bridge_lab_shops_bounds()) do bridge_lab_config.urban_shops = !bridge_lab_config.urban_shops
    if canvas2d.IsKeyPressed(.A) do bridge_lab_seed -= 1
    if canvas2d.IsKeyPressed(.D) do bridge_lab_seed += 1
    if canvas2d.IsKeyPressed(.A) || canvas2d.IsKeyPressed(.D) do terrain_changed = true
    if canvas2d.IsKeyPressed(.S) {
        count := int(bridges.Archetype.Iron_Truss) + 1
        bridge_lab_apply_archetype(bridges.Archetype((int(bridge_lab_config.archetype) + 1) % count))
        terrain_changed = true
    }
    if canvas2d.IsKeyPressed(.R) {
        switch bridge_lab_config.region {
        case .Adriatic:
            bridge_lab_apply_archetype(.Cycladic_Rural)
        case .Aegean:
            bridge_lab_apply_archetype(.Timber_Trestle)
        case .Later_Era:
            bridge_lab_apply_archetype(.Dalmatian_Multi_Arch)
        }
        terrain_changed = true
    }
    if canvas2d.IsKeyPressed(.LEFT) {
        bridge_lab_config.length = max(f32(10), bridge_lab_config.length - 2)
        bridge_lab_cleft_width = min(bridge_lab_cleft_width, bridge_lab_config.length * .90)
        terrain_changed = true
    }
    if canvas2d.IsKeyPressed(.RIGHT) {
        bridge_lab_config.length = min(f32(80), bridge_lab_config.length + 2)
        terrain_changed = true
    }
    if canvas2d.IsKeyPressed(.DOWN) do bridge_lab_config.span_count = max(1, bridge_lab_config.span_count - 1)
    if canvas2d.IsKeyPressed(.UP) do bridge_lab_config.span_count = min(bridges.MAX_SPANS, bridge_lab_config.span_count + 1)
    if canvas2d.IsKeyPressed(.ONE) {
        bridge_lab_config.clearance = max(f32(2.5), bridge_lab_config.clearance - .5)
        terrain_changed = true
    }
    if canvas2d.IsKeyPressed(.TWO) {
        bridge_lab_config.clearance = min(f32(16), bridge_lab_config.clearance + .5)
        terrain_changed = true
    }
    if canvas2d.IsKeyPressed(.Q) {
        bridge_lab_cleft_width = max(f32(4), bridge_lab_cleft_width - 1)
        terrain_changed = true
    }
    if canvas2d.IsKeyPressed(.E) {
        bridge_lab_cleft_width = min(bridge_lab_config.length * .90, bridge_lab_cleft_width + 1)
        terrain_changed = true
    }
    if canvas2d.IsKeyPressed(.Z) {
        bridge_lab_cleft_depth = max(f32(2), bridge_lab_cleft_depth - .5)
        terrain_changed = true
    }
    if canvas2d.IsKeyPressed(.X) {
        bridge_lab_cleft_depth = min(f32(18), bridge_lab_cleft_depth + .5)
        terrain_changed = true
    }
    if canvas2d.IsKeyPressed(.C) do bridge_lab_config.pier_cutwaters = !bridge_lab_config.pier_cutwaters
    if canvas2d.IsKeyPressed(.U) && bridge_lab_config.archetype == .Venetian_Canal do bridge_lab_config.urban_shops = !bridge_lab_config.urban_shops
    if terrain_changed do bridge_lab_regenerate_terrain(editor)
}

bridge_lab_scale_color :: proc(color: canvas2d.Color, scale: f32) -> canvas2d.Color {
    return {
        u8(clamp(f32(color.r) * scale, 0, 255)),
        u8(clamp(f32(color.g) * scale, 0, 255)),
        u8(clamp(f32(color.b) * scale, 0, 255)),
        color.a,
    }
}

bridge_lab_palette :: proc(plan: ^bridges.Plan) -> (body, ring, paving, accent: canvas2d.Color) {
    switch plan.material {
    case .Limestone:
        return {151, 143, 126, 255}, {188, 179, 157, 255}, {126, 121, 108, 255}, {78, 66, 50, 255}
    case .Travertine:
        return {159, 148, 124, 255}, {188, 173, 142, 255}, {131, 123, 106, 255}, {88, 76, 57, 255}
    case .Istrian_Stone:
        return {205, 199, 178, 255}, {235, 229, 207, 255}, {173, 166, 148, 255}, {113, 86, 55, 255}
    case .Slate:
        return {101, 106, 102, 255}, {137, 142, 137, 255}, {83, 88, 86, 255}, {65, 60, 52, 255}
    case .Fieldstone:
        return {137, 128, 105, 255}, {164, 154, 127, 255}, {111, 104, 89, 255}, {75, 66, 48, 255}
    case .Timber:
        return {91, 64, 41, 255}, {124, 88, 52, 255}, {74, 55, 39, 255}, {49, 45, 39, 255}
    case .Iron:
        return {61, 67, 64, 255}, {88, 96, 92, 255}, {78, 75, 67, 255}, {43, 46, 44, 255}
    }
    return {}, {}, {}, {}
}

bridge_lab_profile_rise :: proc(plan: ^bridges.Plan, x: f32) -> f32 {
    normalized := clamp(abs(x) / (plan.length * .5), f32(0), f32(1))
    switch plan.deck_profile {
    case .Crowned:
        return plan.deck_rise * (1 - normalized * normalized)
    case .Humpback:
        return plan.deck_rise * (1 - normalized)
    case .Stepped:
        steps := f32(8)
        return math.floor((1 - normalized) * steps) / steps * plan.deck_rise
    case .Level:
        return 0
    }
    return 0
}

bridge_lab_deck_surface :: proc(plan: ^bridges.Plan, x: f32) -> f32 {
    return plan.clearance + bridge_lab_profile_rise(plan, x)
}

bridge_lab_member :: proc(a, b: third_person.Vec3, thickness: f32, color: canvas2d.Color) {
    world_box_between(a, b, {0, 0, 1}, thickness, thickness, color)
}

bridge_lab_arch_fraction :: proc(plan: ^bridges.Plan, u: f32) -> f32 {
    switch plan.arch_shape {
    case .Semicircular, .Segmental:
        return math.sqrt(max(f32(0), 1 - u * u))
    case .Slightly_Pointed:
        semicircle := math.sqrt(max(f32(0), 1 - u * u))
        straight_sided := max(f32(0), 1 - abs(u))
        return (semicircle + straight_sided * .20) / 1.20
    }
    return 0
}

bridge_lab_spandrel_strip :: proc(x0, x1, opening_y0, opening_y1, top_y0, top_y1, width: f32, color: canvas2d.Color) {
    z := width * .5
    p := [8]third_person.Vec3 {
        {x0, opening_y0, -z},
        {x1, opening_y1, -z},
        {x1, top_y1, -z},
        {x0, top_y0, -z},
        {x0, opening_y0, z},
        {x1, opening_y1, z},
        {x1, top_y1, z},
        {x0, top_y0, z},
    }
    // Match world_box's outward winding while allowing the lower face to
    // follow the arch. Adjacent strips now share their complete edge instead
    // of leaving triangular holes between midpoint-sampled rectangles.
    world_quad(p[0], p[3], p[2], p[1], color)
    world_quad(p[4], p[5], p[6], p[7], color)
    world_quad(p[0], p[4], p[7], p[3], color)
    world_quad(p[1], p[2], p[6], p[5], color)
    world_quad(p[3], p[7], p[6], p[2], color)
    world_quad(p[0], p[1], p[5], p[4], color)
}

bridge_lab_masonry :: proc(plan: ^bridges.Plan, body, ring: canvas2d.Color) {
    pieces := 18
    sides := [2]f32{-1, 1}
    for span in 0 ..< plan.pier_count + 1 {
        center_x := -plan.length * .5 + (f32(span) + .5) * plan.span_length
        half_opening := plan.span_length * .43
        spring_y := max(f32(.32), plan.clearance - plan.arch_rise)
        span_left := center_x - plan.span_length * .5
        span_right := center_x + plan.span_length * .5
        left_inner := center_x - half_opening
        right_inner := center_x + half_opening
        bridge_lab_spandrel_strip(
            span_left,
            left_inner,
            0,
            0,
            bridge_lab_deck_surface(plan, span_left) - plan.deck_thickness,
            bridge_lab_deck_surface(plan, left_inner) - plan.deck_thickness,
            plan.width,
            body,
        )
        bridge_lab_spandrel_strip(
            right_inner,
            span_right,
            0,
            0,
            bridge_lab_deck_surface(plan, right_inner) - plan.deck_thickness,
            bridge_lab_deck_surface(plan, span_right) - plan.deck_thickness,
            plan.width,
            body,
        )
        for index in 0 ..< pieces {
            x0 := center_x - half_opening + f32(index) * half_opening * 2 / f32(pieces)
            x1 := center_x - half_opening + f32(index + 1) * half_opening * 2 / f32(pieces)
            xm := (x0 + x1) * .5
            u0 := (x0 - center_x) / half_opening
            u1 := (x1 - center_x) / half_opening
            opening_y0 := spring_y + bridge_lab_arch_fraction(plan, u0) * plan.arch_rise
            opening_y1 := spring_y + bridge_lab_arch_fraction(plan, u1) * plan.arch_rise
            underside0 := bridge_lab_deck_surface(plan, x0) - plan.deck_thickness
            underside1 := bridge_lab_deck_surface(plan, x1) - plan.deck_thickness
            shade :=
                1 +
                (f32(bridges.mix(plan.seed + u32(span * pieces + index)) & 255) / 255 - .5) * plan.masonry_variation
            bridge_lab_spandrel_strip(
                x0,
                x1,
                min(opening_y0, underside0 - .02),
                min(opening_y1, underside1 - .02),
                underside0,
                underside1,
                plan.width,
                bridge_lab_scale_color(body, shade),
            )
        }
        for side in sides {
            z := side * (plan.width * .5 + .018)
            previous := third_person.Vec3{center_x - half_opening, spring_y, z}
            for index in 1 ..= pieces {
                u := -1 + f32(index) * 2 / f32(pieces)
                point := third_person.Vec3 {
                    center_x + u * half_opening,
                    spring_y + bridge_lab_arch_fraction(plan, u) * plan.arch_rise,
                    z,
                }
                bridge_lab_member(previous, point, plan.dressed_arch_ring ? f32(.34) : f32(.28), ring)
                previous = point
            }
        }
    }

    // The generated span layout extends beneath the bank so the bridge can
    // meet different cleft widths. Close that buried part with a solid
    // terminal abutment; otherwise the outer arch opening remains visible
    // through the terrain-facing end of the bridge.
    bridge_half := plan.length * .5
    terminal_outer := bridge_half + 2.4
    terminal_inner := clamp(bridge_lab_cleft_width * .5 - .35, f32(0), bridge_half - .15)
    terminal_width := plan.width + .10
    if terminal_inner < bridge_half {
        bridge_lab_spandrel_strip(
            -terminal_outer,
            -terminal_inner,
            0,
            0,
            bridge_lab_deck_surface(plan, -bridge_half) - plan.deck_thickness,
            bridge_lab_deck_surface(plan, -terminal_inner) - plan.deck_thickness,
            terminal_width,
            body,
        )
        bridge_lab_spandrel_strip(
            terminal_inner,
            terminal_outer,
            0,
            0,
            bridge_lab_deck_surface(plan, terminal_inner) - plan.deck_thickness,
            bridge_lab_deck_surface(plan, bridge_half) - plan.deck_thickness,
            terminal_width,
            body,
        )
    }
}

bridge_lab_deck :: proc(plan: ^bridges.Plan, body, paving: canvas2d.Color) {
    pieces := 32
    for index in 0 ..< pieces {
        x0 := -plan.length * .5 + f32(index) * plan.length / f32(pieces)
        x1 := -plan.length * .5 + f32(index + 1) * plan.length / f32(pieces)
        y0 := bridge_lab_deck_surface(plan, x0) - plan.deck_thickness * .5
        y1 := bridge_lab_deck_surface(plan, x1) - plan.deck_thickness * .5
        bridge_lab_member({x0, y0, 0}, {x1, y1, 0}, plan.deck_thickness, body)
        xm := (x0 + x1) * .5
        world_box({xm, bridge_lab_deck_surface(plan, xm) + .025, 0}, {(x1 - x0) * .92, .05, plan.width * .90}, paving)
    }
}

bridge_lab_approaches :: proc(plan: ^bridges.Plan, body, paving: canvas2d.Color) {
    overlap := f32(1.1)
    extension := f32(2.4)
    sides := [2]f32{-1, 1}
    for side in sides {
        inner_x := side * (plan.length * .5 - overlap)
        outer_x := side * (plan.length * .5 + extension)
        surface := bridge_lab_deck_surface(plan, side * plan.length * .5)
        // Keep only a thin paving course above the terrain landing. Its lower
        // face is buried; the approach is carried visually by the bank rather
        // than by a freestanding rectangular slab.
        world_box_between(
            {inner_x, surface - .035, 0},
            {outer_x, surface - .035, 0},
            {0, 1, 0},
            plan.width * .86,
            .11,
            paving,
        )
        wing_sides := [2]f32{-1, 1}
        for wing_side in wing_sides {
            z := wing_side * (plan.width * .5 - plan.parapet_width * .5)
            world_box_between(
                {side * (plan.length * .5 - .35), surface + .10, z},
                {side * (plan.length * .5 + extension * .82), surface + .10, z},
                {0, 0, 1},
                .58,
                plan.parapet_width,
                body,
            )
        }
    }
}

bridge_lab_piers :: proc(plan: ^bridges.Plan, body, accent: canvas2d.Color) {
    for pier in plan.piers[:plan.pier_count] {
        top := bridge_lab_deck_surface(plan, pier.station) - plan.deck_thickness
        world_box({pier.station, top * .5, 0}, {pier.width, top, plan.width * .82}, body)
        if plan.pier_cutwaters {
            world_box_rotated(
                {pier.station, top * .32, -plan.width * .48},
                {pier.width * .82, top * .60, pier.width * .82},
                math.PI * .25,
                accent,
            )
            world_box_rotated(
                {pier.station, top * .32, plan.width * .48},
                {pier.width * .82, top * .60, pier.width * .82},
                math.PI * .25,
                accent,
            )
        }
    }
}

bridge_lab_parapets :: proc(plan: ^bridges.Plan, color: canvas2d.Color) {
    sides := [2]f32{-1, 1}
    pieces := 24
    foundation_depth := f32(.14)
    for side in sides {
        z := side * (plan.width * .5 - plan.parapet_width * .5)
        if plan.parapet == .Balustrade || plan.parapet == .Rail {
            for index in 0 ..= pieces {
                x := -plan.length * .5 + f32(index) * plan.length / f32(pieces)
                surface := bridge_lab_deck_surface(plan, x)
                post_height := plan.parapet_height + foundation_depth
                world_box(
                    {x, surface + (plan.parapet_height - foundation_depth) * .5, z},
                    {plan.parapet_width, post_height, plan.parapet_width},
                    color,
                )
            }
            for index in 0 ..< pieces {
                x0 := -plan.length * .5 + f32(index) * plan.length / f32(pieces)
                x1 := -plan.length * .5 + f32(index + 1) * plan.length / f32(pieces)
                bridge_lab_member(
                    {x0, bridge_lab_deck_surface(plan, x0) + plan.parapet_height, z},
                    {x1, bridge_lab_deck_surface(plan, x1) + plan.parapet_height, z},
                    plan.parapet_width,
                    color,
                )
            }
        } else {
            for index in 0 ..< pieces {
                x0 := -plan.length * .5 + f32(index) * plan.length / f32(pieces)
                x1 := -plan.length * .5 + f32(index + 1) * plan.length / f32(pieces)
                xm := (x0 + x1) * .5
                irregular :=
                    plan.parapet == .Low_Irregular ? (f32(bridges.mix(plan.seed + u32(index)) & 255) / 255 - .5) * .16 : f32(0)
                height := plan.parapet_height + irregular
                grounded_height := height + foundation_depth
                world_box(
                    {xm, bridge_lab_deck_surface(plan, xm) + (height - foundation_depth) * .5, z},
                    {(x1 - x0) * 1.02, grounded_height, plan.parapet_width},
                    color,
                )
            }
        }
    }
}

bridge_lab_trusses :: proc(plan: ^bridges.Plan, color: canvas2d.Color) {
    sides := [2]f32{-1, 1}
    for side in sides {
        z := side * (plan.width * .5 + .08)
        deck_y := plan.clearance
        bridge_lab_member({-plan.length * .5, deck_y, z}, {plan.length * .5, deck_y, z}, .18, color)
        bridge_lab_member(
            {-plan.length * .5, deck_y + plan.truss_height, z},
            {plan.length * .5, deck_y + plan.truss_height, z},
            .16,
            color,
        )
        bays := max(4, plan.cross_brace_count * (plan.pier_count + 1))
        for index in 0 ..< bays {
            x0 := -plan.length * .5 + f32(index) * plan.length / f32(bays)
            x1 := -plan.length * .5 + f32(index + 1) * plan.length / f32(bays)
            bridge_lab_member(
                {x0, index & 1 == 0 ? deck_y : deck_y + plan.truss_height, z},
                {x1, index & 1 == 0 ? deck_y + plan.truss_height : deck_y, z},
                .12,
                color,
            )
        }
    }
}

bridge_lab_trestles :: proc(plan: ^bridges.Plan, color: canvas2d.Color) {
    sides := [2]f32{-1, 1}
    for span in 0 ..< plan.pier_count + 1 {
        x := -plan.length * .5 + (f32(span) + .5) * plan.span_length
        for side in sides {
            z := side * plan.width * .38
            bridge_lab_member(
                {x - plan.span_length * .35, 0, z},
                {x + plan.span_length * .35, plan.clearance, z},
                .24,
                color,
            )
            bridge_lab_member(
                {x + plan.span_length * .35, 0, z},
                {x - plan.span_length * .35, plan.clearance, z},
                .24,
                color,
            )
        }
    }
}

bridge_lab_shops :: proc(plan: ^bridges.Plan, body, accent: canvas2d.Color) {
    if !plan.urban_shops do return
    sides := [2]int{-1, 1}
    for side in sides {
        for index in 0 ..< 4 {
            x := -plan.length * .34 + (f32(index) + .5) * plan.length * .68 / 4
            surface := bridge_lab_deck_surface(plan, x)
            z := f32(side) * plan.width * .36
            world_box({x, surface + 1.25, z}, {plan.length * .13, 2.5, plan.width * .23}, body)
            world_box({x, surface + 2.57, z}, {plan.length * .15, .18, plan.width * .27}, accent)
        }
    }
}

bridge_lab_fortification :: proc(plan: ^bridges.Plan, body, accent: canvas2d.Color) {
    if !plan.fortified_end do return
    sides := [2]f32{-1, 1}
    for side in sides {
        x := side * (plan.length * .5 + 1.4)
        world_box({x, 3.1, 0}, {2.8, 6.2, plan.width + 1.2}, body)
        for merlon in 0 ..< 4 {
            z := -plan.width * .5 + f32(merlon) * plan.width / 3
            world_box({x, 6.55, z}, {.72, .7, .72}, accent)
        }
    }
}

world_bridge_generator_lab :: proc(_: ^Editor) {
    plan := bridges.generate(bridge_lab_seed, bridge_lab_config)
    body, ring, paving, accent := bridge_lab_palette(&plan)
    if plan.construction != .Framed do bridge_lab_masonry(&plan, body, ring)
    bridge_lab_piers(&plan, body, accent)
    bridge_lab_deck(&plan, body, paving)
    bridge_lab_approaches(&plan, body, paving)
    bridge_lab_parapets(&plan, ring)
    if plan.archetype == .Iron_Truss do bridge_lab_trusses(&plan, accent)
    if plan.archetype == .Timber_Trestle do bridge_lab_trestles(&plan, body)
    bridge_lab_shops(&plan, body, accent)
    bridge_lab_fortification(&plan, body, ring)
}

bridge_generator_lab_draw_ui :: proc(_: ^Editor, _: i32, _: i32) {
    plan := bridges.generate(bridge_lab_seed, bridge_lab_config)
    panel := canvas2d.Rectangle{22, 22, 820, 184}
    canvas2d.DrawRectangleRounded(panel, .10, 8, {21, 27, 27, 232})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {143, 151, 126, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "BRIDGE GENERATOR LAB", {38, 38}, 20, 1, {237, 228, 194, 255})
    lab_ui_draw_button(bridge_lab_archetype_bounds(), bridge_lab_archetype_name(plan.archetype), true)
    lab_ui_draw_button(bridge_lab_seed_bounds(), fmt.ctprintf("NEW SEED  %06X", bridge_lab_seed))
    labels := [5]cstring{"LENGTH", "SPANS", "CLEARANCE", "CLEFT WIDTH", "CLEFT DEPTH"}
    xs := [5]f32{38, 178, 308, 456, 604}
    for label, index in labels do canvas2d.DrawTextEx(canvas2d.Font{}, label, {xs[index], 103}, 9, 1, {199, 198, 177, 255})
    lab_ui_draw_stepper(bridge_lab_length_bounds(), fmt.ctprintf("%.0f M", bridge_lab_config.length))
    lab_ui_draw_stepper(bridge_lab_spans_bounds(), fmt.ctprintf("%d", bridge_lab_config.span_count))
    lab_ui_draw_stepper(bridge_lab_clearance_bounds(), fmt.ctprintf("%.1f M", bridge_lab_config.clearance))
    lab_ui_draw_stepper(bridge_lab_cleft_width_bounds(), fmt.ctprintf("%.0f M", bridge_lab_cleft_width))
    lab_ui_draw_stepper(bridge_lab_cleft_depth_bounds(), fmt.ctprintf("%.1f M", bridge_lab_cleft_depth))
    lab_ui_draw_button(bridge_lab_cutwaters_bounds(), "CUTWATERS", bridge_lab_config.pier_cutwaters)
    if bridge_lab_config.archetype == .Venetian_Canal do lab_ui_draw_button(bridge_lab_shops_bounds(), "SHOPS", bridge_lab_config.urban_shops)
    canvas2d.DrawTextEx(canvas2d.Font{}, fmt.ctprintf("%s  /  %s", bridge_lab_region_name(plan.region), bridge_lab_material_name(plan.material)), {300, 168}, 11, 1, {190, 213, 189, 255})
}
