package main
import "core:math"

import architecture "../packages/architecture"
import circulation "../packages/circulation"
import hero "../packages/hero_buildings"
import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import canvas2d "zelda_engine:canvas2d"

world_architecture_mixed_use_service_door :: proc(
    structure: terrain.Structure,
    local_x, local_z, yaw_offset: f32,
    outward_x, outward_z: f32,
) {
    door_x, door_z := world_rotate_xz(structure.center_x, structure.center_z, local_x, local_z, structure.rotation)
    yaw := structure.rotation + yaw_offset
    door_color := (structure.seed & 1) == 0 ? canvas2d.Color{68, 98, 97, 255} : canvas2d.Color{111, 72, 58, 255}
    frame_color := canvas2d.Color{192, 174, 139, 255}
    world_box_rotated({door_x, structure.base_y + 1.48, door_z}, {1.42, 2.78, .18}, yaw, door_color)
    for jamb in -1 ..= 1 {
        if jamb == 0 do continue
        jamb_local_x := local_x
        jamb_local_z := local_z
        if math.abs(yaw_offset) > math.PI * .25 {
            jamb_local_z += f32(jamb) * .79
        } else {
            jamb_local_x += f32(jamb) * .79
        }
        jamb_x, jamb_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            jamb_local_x,
            jamb_local_z,
            structure.rotation,
        )
        world_box_rotated({jamb_x, structure.base_y + 1.48, jamb_z}, {.11, 3.02, .12}, yaw, frame_color)
    }
    world_box_rotated({door_x, structure.base_y + 2.94, door_z}, {1.66, .13, .12}, yaw, frame_color)
    step_local_x := local_x + outward_x * .38
    step_local_z := local_z + outward_z * .38
    step_x, step_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        step_local_x,
        step_local_z,
        structure.rotation,
    )
    world_box_rotated({step_x, structure.base_y + .075, step_z}, {1.72, .15, .68}, yaw, {157, 139, 111, 255})
    canopy_local_x := local_x + outward_x * .30
    canopy_local_z := local_z + outward_z * .30
    canopy_x, canopy_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        canopy_local_x,
        canopy_local_z,
        structure.rotation,
    )
    world_box_rotated({canopy_x, structure.base_y + 3.18, canopy_z}, {1.82, .13, .64}, yaw, {174, 103, 72, 255})
    lamp_local_x := local_x + outward_x * .13
    lamp_local_z := local_z + outward_z * .13
    lamp_x, lamp_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        lamp_local_x,
        lamp_local_z,
        structure.rotation,
    )
    world_box_rotated_material(
        {lamp_x, structure.base_y + 2.78, lamp_z},
        {.18, .15, .04},
        yaw,
        {255, 176, 76, 255},
        .Emissive,
    )
    handle_local_x := local_x
    handle_local_z := local_z
    if math.abs(yaw_offset) > math.PI * .25 {
        handle_local_z -= .42
    } else {
        handle_local_x += .42
    }
    handle_local_x += outward_x * .13
    handle_local_z += outward_z * .13
    handle_x, handle_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        handle_local_x,
        handle_local_z,
        structure.rotation,
    )
    world_metal_box_rotated(
        {handle_x, structure.base_y + 1.48, handle_z},
        {.07, .07, .10},
        yaw,
        {205, 164, 84, 255},
        .82,
        .34,
    )
}

world_architecture_mixed_use_service_path :: proc(
    structure: terrain.Structure,
    local_x, local_z, outward_x, outward_z, path_length: f32,
) {
    // Pull the private entrance out into the rear yard with a narrow, visibly
    // jointed stone walk. Without this link the service door reads like an
    // opening stranded in lawn rather than part of the building circulation.
    path_local_x := local_x + outward_x * (path_length * .5 + .48)
    path_local_z := local_z + outward_z * (path_length * .5 + .48)
    path_x, path_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        path_local_x,
        path_local_z,
        structure.rotation,
    )
    path_yaw := structure.rotation
    path_size := [3]f32{1.46, .065, path_length}
    if math.abs(outward_x) > math.abs(outward_z) {
        path_yaw += math.PI * .5
    }
    world_box_rotated({path_x, structure.base_y + .032, path_z}, path_size, path_yaw, {171, 157, 130, 255})
    joint_count := int(max(f32(2), math.floor(path_length / .72)))
    for joint in 1 ..< joint_count {
        distance := .48 + path_length * f32(joint) / f32(joint_count)
        joint_local_x := local_x + outward_x * distance
        joint_local_z := local_z + outward_z * distance
        joint_x, joint_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            joint_local_x,
            joint_local_z,
            structure.rotation,
        )
        world_box_rotated(
            {joint_x, structure.base_y + .068, joint_z},
            {1.30, .012, .045},
            path_yaw,
            {116, 109, 94, 255},
        )
    }
}

world_architecture_entrance_oriented :: proc(source: terrain.Structure) -> terrain.Structure {
    result := source
    switch source.entrance_side {
    case .Front:
    case .Right:
        result.rotation -= math.PI * .5
        result.width, result.depth = source.depth, source.width
    case .Rear:
        result.rotation += math.PI
    case .Left:
        result.rotation += math.PI * .5
        result.width, result.depth = source.depth, source.width
    }
    // The rich architecture pass is authored around local +Z. Present a
    // footprint-equivalent view whose +Z is the selected entrance façade.
    result.entrance_side = .Front
    return result
}

world_lighthouse_beam_angle :: proc(structure: terrain.Structure, elapsed_seconds: f32) -> f32 {
    revolution_seconds := f32(8.0)
    seed_phase := f32(structure.seed % 4096) / 4096 * math.TAU
    return seed_phase + elapsed_seconds * math.TAU / revolution_seconds
}

world_lighthouse_beam_visibility :: proc(
    structure: terrain.Structure,
    point_x, point_z: f32,
    elapsed_seconds: f32,
) -> f32 {
    dx, dz := point_x - structure.center_x, point_z - structure.center_z
    distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
    if distance < 2 || distance > 72 do return 0
    angle := world_lighthouse_beam_angle(structure, elapsed_seconds)
    forward_x, forward_z := math.sin(angle), math.cos(angle)
    along := dx * forward_x + dz * forward_z
    if along <= 0 do return 0
    across := math.abs(dx * forward_z - dz * forward_x)
    half_width := .45 + along * .085
    if across >= half_width do return 0
    edge_fade := 1 - across / half_width
    distance_fade := 1 - clamp((distance - 48) / 24, 0, 1)
    return edge_fade * edge_fade * distance_fade
}

world_architecture_lighthouse_beam :: proc(editor: ^Editor, structure: terrain.Structure, source_y: f32) {
    if editor == nil do return
    night_strength := clamp((.38 - world_renderer.scene_daylight) / .38, 0, 1)
    if night_strength <= .001 do return

    elapsed := f32(canvas2d.GetTime())
    angle := world_lighthouse_beam_angle(structure, elapsed)
    forward_x, forward_z := math.sin(angle), math.cos(angle)
    right_x, right_z := forward_z, -forward_x
    source := third_person.Vec3{structure.center_x, source_y, structure.center_z}
    near_distance, far_distance := f32(1.2), f32(62)
    near_half_width, far_half_width := f32(.28), f32(5.6)
    middle_distance := f32(24)
    middle_half_width := f32(2.35)
    far_y := source_y - 2.2
    near_center := third_person.Vec3 {
        source.x + forward_x * near_distance,
        source.y,
        source.z + forward_z * near_distance,
    }
    far_center := third_person.Vec3{source.x + forward_x * far_distance, far_y, source.z + forward_z * far_distance}
    middle_t := middle_distance / far_distance
    middle_center := third_person.Vec3 {
        source.x + forward_x * middle_distance,
        source.y + (far_y - source.y) * middle_t,
        source.z + forward_z * middle_distance,
    }
    near_left := third_person.Vec3 {
        near_center.x - right_x * near_half_width,
        near_center.y,
        near_center.z - right_z * near_half_width,
    }
    near_right := third_person.Vec3 {
        near_center.x + right_x * near_half_width,
        near_center.y,
        near_center.z + right_z * near_half_width,
    }
    far_left := third_person.Vec3 {
        far_center.x - right_x * far_half_width,
        far_center.y,
        far_center.z - right_z * far_half_width,
    }
    far_right := third_person.Vec3 {
        far_center.x + right_x * far_half_width,
        far_center.y,
        far_center.z + right_z * far_half_width,
    }
    middle_left := third_person.Vec3 {
        middle_center.x - right_x * middle_half_width,
        middle_center.y,
        middle_center.z - right_z * middle_half_width,
    }
    middle_right := third_person.Vec3 {
        middle_center.x + right_x * middle_half_width,
        middle_center.y,
        middle_center.z + right_z * middle_half_width,
    }
    warm_near := canvas2d.Color{255, 241, 190, u8(42 * night_strength)}
    warm_middle := canvas2d.Color{255, 232, 155, u8(14 * night_strength)}
    warm_far := canvas2d.Color{255, 221, 130, u8(2 * night_strength)}
    core_near := canvas2d.Color{255, 249, 215, u8(58 * night_strength)}
    core_middle := canvas2d.Color{255, 239, 180, u8(20 * night_strength)}
    clear_far := canvas2d.Color{255, 229, 151, 0}

    // Layered crossed sheets produce a bright optical core inside a broad,
    // soft atmospheric volume. The middle ring prevents a single linear fade
    // from losing the entire beam within a few metres of the lantern.
    first := len(world_renderer.vertices)
    world_quad_colored(
        near_left,
        near_right,
        middle_right,
        middle_left,
        warm_near,
        warm_near,
        warm_middle,
        warm_middle,
    )
    world_quad_colored(middle_left, middle_right, far_right, far_left, warm_middle, warm_middle, warm_far, warm_far)
    core_near_left := third_person.Vec3 {
        near_center.x - right_x * near_half_width * .36,
        near_center.y + .015,
        near_center.z - right_z * near_half_width * .36,
    }
    core_near_right := third_person.Vec3 {
        near_center.x + right_x * near_half_width * .36,
        near_center.y + .015,
        near_center.z + right_z * near_half_width * .36,
    }
    core_middle_left := third_person.Vec3 {
        middle_center.x - right_x * middle_half_width * .30,
        middle_center.y + .015,
        middle_center.z - right_z * middle_half_width * .30,
    }
    core_middle_right := third_person.Vec3 {
        middle_center.x + right_x * middle_half_width * .30,
        middle_center.y + .015,
        middle_center.z + right_z * middle_half_width * .30,
    }
    world_quad_colored(
        core_near_left,
        core_near_right,
        core_middle_right,
        core_middle_left,
        core_near,
        core_near,
        core_middle,
        core_middle,
    )
    vertical_near_low := third_person.Vec3{near_center.x, near_center.y - .22, near_center.z}
    vertical_near_high := third_person.Vec3{near_center.x, near_center.y + .22, near_center.z}
    vertical_far_low := third_person.Vec3{far_center.x, far_center.y - 2.6, far_center.z}
    vertical_far_high := third_person.Vec3{far_center.x, far_center.y + 2.6, far_center.z}
    world_quad_colored(
        vertical_near_low,
        vertical_near_high,
        vertical_far_high,
        vertical_far_low,
        warm_middle,
        warm_middle,
        clear_far,
        clear_far,
    )
    // Beam energy is authored light, not a surface receiving moonlight.
    for &vertex in world_renderer.vertices[first:] do vertex.kind = .Emissive
    append(&world_renderer.late_transparent_vertices, ..world_renderer.vertices[first:])
    resize(&world_renderer.vertices, first)

    // Use the ocean shader's facet response rather than authored light decals:
    // the overlay only bounds work; each fragment independently decides
    // whether its animated wave normal reflects the lantern toward the camera.
    shimmer_center_x := source.x + forward_x * 34
    shimmer_center_z := source.z + forward_z * 34
    shimmer_first := len(world_renderer.vertices)
    world_ellipse_material_uv(
        {shimmer_center_x, editor.project.sea_level + .055, shimmer_center_z},
        25,
        4.2,
        angle,
        {255, 225, 154, u8(178 * night_strength)},
        .Lighthouse_Glitter,
    )
    for &vertex in world_renderer.vertices[shimmer_first:] {
        // The Fresnel lens collimates the lamp into an effectively directional
        // sheet. Store the water-to-light direction just as the world push
        // stores the Sun direction; the shader then runs the same facet model.
        vertex.normal = {-forward_x, .16, -forward_z}
        vertex.material = {night_strength, 0}
    }
    append(&world_renderer.late_transparent_vertices, ..world_renderer.vertices[shimmer_first:])
    resize(&world_renderer.vertices, shimmer_first)
    // Offset the aureole through the lantern glass in the direction of travel
    // so the optical source remains visible instead of depth-testing entirely
    // inside the opaque cage.
    world_billboard_material_uv(
        editor,
        {source.x + forward_x * .72, source.y, source.z + forward_z * .72},
        1.45,
        1.45,
        {255, 232, 168, u8(58 * night_strength)},
        .Emissive_Halo,
        true,
    )
}

world_architecture_lighthouse :: proc(structure: terrain.Structure, lod: Structure_LOD = .Near) {
    base_y := structure.base_y
    tower_height := max(structure.height, f32(14))
    base_radius := clamp(min(structure.width, structure.depth) * .36, f32(2.4), f32(5.2))
    shaft_top := base_y + tower_height
    masonry := canvas2d.Color{224, 218, 194, 255}
    if architecture.architecture_resolve_legacy_identity(structure).region == .Aegean {
        masonry = {235, 232, 216, 255}
    }
    band := (structure.seed & 1) == 0 ? canvas2d.Color{151, 57, 42, 255} : canvas2d.Color{63, 91, 101, 255}
    dark_metal := canvas2d.Color{49, 55, 54, 255}
    beacon := canvas2d.Color{255, 226, 139, 255}

    // Slightly narrowing stacked drums make the silhouette read as a tapered
    // stone tower while reusing the renderer's deterministic octagonal tube.
    DRUMS :: architecture.LIGHTHOUSE_SHAFT_DRUM_COUNT
    for drum in 0 ..< DRUMS {
        low := base_y + tower_height * f32(drum) / DRUMS
        high := base_y + tower_height * f32(drum + 1) / DRUMS + .04
        radius := base_radius * (1 - f32(drum) * .055)
        color := masonry
        if drum == 2 do color = band
        world_tube_between(
            {structure.center_x, low, structure.center_z},
            {structure.center_x, high, structure.center_z},
            {0, 0, 1},
            radius,
            radius,
            color,
        )
    }
    world_tube_between(
        {structure.center_x, base_y, structure.center_z},
        {structure.center_x, base_y + .48, structure.center_z},
        {0, 0, 1},
        base_radius + .38,
        base_radius + .38,
        formation_face_color(masonry, math.PI, 0),
    )

    gallery_radius := base_radius * .98
    world_tube_between(
        {structure.center_x, shaft_top, structure.center_z},
        {structure.center_x, shaft_top + .40, structure.center_z},
        {0, 0, 1},
        gallery_radius,
        gallery_radius,
        dark_metal,
    )
    lantern_radius := base_radius * .55
    lantern_low := shaft_top + .40
    lantern_high := lantern_low + max(base_radius * .82, f32(2.5))
    // Build the lantern room from the shared pane material instead of a
    // translucent plain tube. Its established interior-light channel retains
    // sky reflection by day and reveals the warm beacon through the glass
    // when the nighttime light is active.
    pane_height := lantern_high - lantern_low
    pane_half_angle := f32(math.PI / 8)
    pane_center_radius := lantern_radius * math.cos(pane_half_angle)
    pane_width := lantern_radius * 2 * math.sin(pane_half_angle) * 1.015
    pane_interior := canvas2d.Color{246, 211, 150, 255}
    for pane in 0 ..< 8 {
        pane_angle := (f32(pane) + .5) * math.PI * .25
        pane_x := structure.center_x + math.cos(pane_angle) * pane_center_radius
        pane_z := structure.center_z + math.sin(pane_angle) * pane_center_radius
        world_glass_panel(
            {pane_x, (lantern_low + lantern_high) * .5, pane_z},
            pane_width,
            pane_height,
            pane_angle - math.PI * .5,
            pane_interior,
            1,
        )
    }
    world_tube_between(
        {structure.center_x, lantern_low + .10, structure.center_z},
        {structure.center_x, lantern_high - .10, structure.center_z},
        {0, 0, 1},
        .22,
        .22,
        beacon,
    )
    world_emissive_fixture_box(
        {structure.center_x, (lantern_low + lantern_high) * .5, structure.center_z},
        {.52, .72, .52},
        structure.rotation,
        beacon,
        3,
    )
    world_tube_between(
        {structure.center_x, lantern_high, structure.center_z},
        {structure.center_x, lantern_high + .36, structure.center_z},
        {0, 0, 1},
        lantern_radius + .24,
        lantern_radius + .24,
        dark_metal,
    )
    roof_tip := third_person.Vec3{structure.center_x, lantern_high + 1.65, structure.center_z}
    for segment in 0 ..< 8 {
        angle_a := f32(segment) * math.PI * .25
        angle_b := f32(segment + 1) * math.PI * .25
        a := third_person.Vec3 {
            structure.center_x + math.cos(angle_a) * (lantern_radius + .30),
            lantern_high + .36,
            structure.center_z + math.sin(angle_a) * (lantern_radius + .30),
        }
        b := third_person.Vec3 {
            structure.center_x + math.cos(angle_b) * (lantern_radius + .30),
            lantern_high + .36,
            structure.center_z + math.sin(angle_b) * (lantern_radius + .30),
        }
        world_triangle(a, roof_tip, b, band)
    }
    world_tube_between(roof_tip, {roof_tip.x, roof_tip.y + .72, roof_tip.z}, {0, 0, 1}, .09, .09, dark_metal)

    editor := world_renderer.editor
    if editor != nil {
        source_y := (lantern_low + lantern_high) * .5
        world_billboard_material_uv(
            editor,
            {structure.center_x, source_y, structure.center_z},
            1.7,
            1.7,
            {255, 229, 160, 54},
            .Emissive_Halo,
            true,
        )
        world_architecture_lighthouse_beam(editor, structure, source_y)
    }

    if lod == .Far do return
    rail_y := shaft_top + 1.18
    for segment in 0 ..< 8 {
        angle_a := f32(segment) * math.PI * .25
        angle_b := f32(segment + 1) * math.PI * .25
        a := third_person.Vec3 {
            structure.center_x + math.cos(angle_a) * gallery_radius,
            rail_y,
            structure.center_z + math.sin(angle_a) * gallery_radius,
        }
        b := third_person.Vec3 {
            structure.center_x + math.cos(angle_b) * gallery_radius,
            rail_y,
            structure.center_z + math.sin(angle_b) * gallery_radius,
        }
        world_tube_between(a, b, {0, 1, 0}, .045, .045, dark_metal)
        world_tube_between({a.x, shaft_top + .35, a.z}, a, {0, 0, 1}, .045, .045, dark_metal)
    }
    // Give the keeper a grounded entrance on the frontage. The first stair
    // slit starts above its head, so the two authored opening systems cannot
    // visually collide on compact towers.
    door_angle := structure.rotation
    door_x := structure.center_x + math.sin(door_angle) * (base_radius + .035)
    door_z := structure.center_z + math.cos(door_angle) * (base_radius + .035)
    world_box_rotated({door_x, base_y + 1.35, door_z}, {1.45, 2.70, .12}, -door_angle, {62, 71, 69, 255})

    // Sparse slit windows spiral with the stair. Seat each pane on the actual
    // tapered drum instead of using the base radius for every level, which
    // left upper panes hovering progressively farther from the masonry.
    for level in 0 ..< architecture.LIGHTHOUSE_SLIT_COUNT {
        height_fraction := architecture.lighthouse_slit_height_fraction(level)
        shaft_radius := base_radius * architecture.lighthouse_shaft_radius_scale(height_fraction)
        angle := structure.rotation + f32(level) * math.PI * .5
        window_x := structure.center_x + math.sin(angle) * (shaft_radius + .025)
        window_z := structure.center_z + math.cos(angle) * (shaft_radius + .025)
        world_box_rotated(
            {window_x, base_y + tower_height * height_fraction, window_z},
            {.62, 1.15, .10},
            -angle,
            {48, 67, 69, 255},
        )
    }
}

world_hero_civic_box :: proc(
    structure: terrain.Structure,
    plan: ^hero.Plan,
    local_center, size: third_person.Vec3,
    material: Settlement_Material,
) {
    x, z := world_rotate_xz(structure.center_x, structure.center_z, local_center.x, local_center.z, structure.rotation)
    world_settlement_material_box_rotated(
        {x, structure.base_y + local_center.y, z},
        size,
        structure.rotation,
        material,
    )
}

world_architecture_hero_civic :: proc(structure: terrain.Structure, kind: hero.Kind, lod: Structure_LOD = .Near) {
    config := hero.defaults(kind)
    config.frontage = structure.width
    config.depth = structure.depth
    plan := hero.generate(structure.seed, config)
    if !plan.valid do return

    // The settlement owns placement and foundation seating; the hero plan
    // owns the recognizable open civic arcade, roof monitor, and bay rhythm.
    world_hero_civic_box(structure, &plan, {0, .04, 0}, {plan.frontage + 1.4, .08, plan.depth + 1.2}, .Arcade_Terrazzo)
    roof_y := plan.arcade_height + plan.roof_height * .5
    world_hero_civic_box(
        structure,
        &plan,
        {0, roof_y, 0},
        {plan.frontage + plan.roof_overhang * 2, plan.roof_height, plan.depth + plan.roof_overhang * 2},
        .Standing_Seam_Roof,
    )
    monitor_spacing := plan.monitor_count == 2 ? plan.monitor_width * .72 : f32(0)
    for monitor in 0 ..< plan.monitor_count {
        monitor_x := plan.monitor_offset_x
        if plan.monitor_count == 2 do monitor_x += (f32(monitor) - .5) * monitor_spacing
        world_hero_civic_box(
            structure,
            &plan,
            {monitor_x, plan.arcade_height + plan.roof_height + plan.monitor_height * .5, -plan.depth * .12},
            {plan.monitor_width / f32(plan.monitor_count), plan.monitor_height, plan.monitor_depth},
            .Monitor_Tinted_Glass,
        )
    }
    for bay in 0 ..= plan.bay_count {
        x := -plan.frontage * .5 + f32(bay) * plan.bay_width
        for side in -1 ..= 1 {
            if side == 0 do continue
            world_hero_civic_box(
                structure,
                &plan,
                {x, plan.arcade_height * .5, f32(side) * (plan.depth * .5 - plan.pier_depth * .5)},
                {plan.pier_width * .78, plan.arcade_height, plan.pier_depth * .82},
                .Pale_Adriatic_Limestone,
            )
        }
    }
    if lod == .Far do return
    sign_x, sign_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        0,
        plan.depth * .5 + .16,
        structure.rotation,
    )
    sign_kind := kind == .Clinic ? Business_Sign_Kind.Clinica : Business_Sign_Kind.Post
    world_business_sign(
        {sign_x, structure.base_y + plan.arcade_height - .62, sign_z},
        structure.rotation,
        sign_kind,
        1.82,
    )
}
