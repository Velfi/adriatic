package main
import "core:math"

import architecture "../packages/architecture"
import dio "zelda_engine:dio"
import flight "../packages/flight"
import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import canvas2d "zelda_engine:canvas2d"

world_climbing_leaves_for_structure :: proc(editor: ^Editor, structure: terrain.Structure, structure_index: int) {
    function_profile := dio.flame_graph_begin(dio.flame_graph_current(), "world_climbing_leaves")
    defer dio.flame_graph_end(dio.flame_graph_current(), function_profile)
    if editor == nil do return
    eligible :=
        structure.kind == .Architecture ||
        structure.kind == .Rock ||
        structure.kind == .Spire ||
        structure.kind == .Mountain ||
        structure.kind == .Ridge ||
        structure.kind == .Cliff
    if !eligible do return
    density := architecture.bougainvillea_density_at_structure(
        &editor.project.climbing_leaf_density,
        structure,
        &editor.project,
    )
    if density < .035 do return
    detail_tier := 2
    if structure.kind == .Architecture {
        dx := editor.camera_pose.position.x - structure.center_x
        dz := editor.camera_pose.position.z - structure.center_z
        detail_tier = architecture.bougainvillea_detail_tier(f32(math.sqrt(f64(dx * dx + dz * dz))))
    }
    capture_seed_enabled :=
        editor.capture_bougainvillea_seed_enabled && structure.id == editor.capture_bougainvillea_structure_id
    capture_seed := capture_seed_enabled ? editor.capture_bougainvillea_seed : u32(0)
    shadow_first := len(world_renderer.vertices)
    defer world_register_shadow_caster(shadow_first)
    entry := &world_renderer.climbing_leaf_geometry_cache[structure_index]
    if entry.valid &&
       entry.structure == structure &&
       entry.density == density &&
       entry.detail_tier == detail_tier &&
       entry.capture_seed_enabled == capture_seed_enabled &&
       entry.capture_seed == capture_seed {
        world_renderer.climbing_leaf_cache_reuses += 1
        profile := dio.flame_graph_begin(dio.flame_graph_current(), "climbing_leaf_cache_reuse")
        append(&world_renderer.vertices, ..entry.world_vertices[:])
        for card in entry.cards {
            world_bougainvillea_card(
                card.center,
                card.width,
                card.height,
                card.tile,
                card.mirror,
                card.roll,
                card.value,
                card.young_growth,
                card.yaw_bias,
            )
        }
        _ = dio.flame_graph_end(dio.flame_graph_current(), profile)
        return
    }
    world_renderer.climbing_leaf_cache_builds += 1
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "climbing_leaf_cache_build")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    clear(&entry.cards)
    climbing_leaf_card_capture = &entry.cards
    defer climbing_leaf_card_capture = nil
    world_first := len(world_renderer.vertices)
    bougainvillea_first := len(world_renderer.bougainvillea_vertices)
    // Compound buildings, laundry anchors, and climbing growth all share
    // the same frontmost rendered mass.
    growth_structure := architecture.architecture_frontage_structure(structure)
    // A painted patch should grow into a small colony of stems rather
    // than a single line; density controls the colony size continuously.
    vine_count := min(1 + int(density * 5.0), 4)
    if structure.kind == .Architecture {
        // Mature bougainvillea usually presents one woody plant with a
        // small number of leaders, not several unrelated ivy-like tracks.
        vine_count = min(1 + int(density * 1.8), 2)
    }
    height_fraction := .50 + density * .30
    if structure.kind == .Architecture {
        maturity := architecture.bougainvillea_maturity(density)
        // Juveniles should be visibly young in reach as well as foliage
        // density. Established plants can still occupy most of a façade.
        height_fraction = architecture.bougainvillea_height_fraction(maturity)
    }
    plant_seed := structure.seed + u32(structure_index * 19)
    if capture_seed_enabled {
        plant_seed = capture_seed
    }
    root_spread := f32(math.sin(f64(f32(plant_seed) * .17))) * .38
    root_attachment_x := architecture.bougainvillea_root_attachment_x(
        growth_structure,
        root_spread * growth_structure.width * .62,
        plant_seed,
    )
    mixed_use_storefront :=
        growth_structure.kind == .Architecture &&
        architecture.architecture_resolve_legacy_identity(growth_structure).archetype == .Mixed_Use_Dwelling
    storefront_growth_side := (plant_seed & 1) == 0 ? f32(-1) : f32(1)
    if mixed_use_storefront {
        // Establish the plant at an outer solid pier. Leaders can fan inward
        // above the canopy, but the exact storefront exclusion keeps their
        // stems and crown off the display glass and central sign.
        root_attachment_x = storefront_growth_side * growth_structure.width * .43
        // A slim wall-mounted training frame makes even a sparse young vine
        // read as intentional shopfront landscaping. Keep its lateral arms
        // above the canopy so the full-height retail glazing remains clear.
        trellis_z := growth_structure.depth * .5 + .235
        trellis_vertical_x := storefront_growth_side * growth_structure.width * .43
        trellis_x, trellis_world_z := world_rotate_xz(
            growth_structure.center_x,
            growth_structure.center_z,
            trellis_vertical_x,
            trellis_z,
            growth_structure.rotation,
        )
        trellis_color := canvas2d.Color{78, 101, 76, 255}
        trellis_rail_width := f32(.028)
        trellis_height := min(growth_structure.height * .40, f32(6.40))
        trellis_center_y := growth_structure.base_y + .55 + trellis_height * .5
        world_box_rotated(
            {trellis_x, trellis_center_y, trellis_world_z},
            {trellis_rail_width, trellis_height, trellis_rail_width},
            growth_structure.rotation,
            trellis_color,
        )
        trellis_arm_width := min(growth_structure.width * .16, f32(1.45))
        trellis_arm_x := storefront_growth_side * (growth_structure.width * .43 - trellis_arm_width * .5)
        arm_x, arm_z := world_rotate_xz(
            growth_structure.center_x,
            growth_structure.center_z,
            trellis_arm_x,
            trellis_z,
            growth_structure.rotation,
        )
        inner_trellis_x := storefront_growth_side * (growth_structure.width * .43 - trellis_arm_width)
        inner_x, inner_z := world_rotate_xz(
            growth_structure.center_x,
            growth_structure.center_z,
            inner_trellis_x,
            trellis_z,
            growth_structure.rotation,
        )
        world_box_rotated(
            {inner_x, trellis_center_y, inner_z},
            {trellis_rail_width, trellis_height, trellis_rail_width},
            growth_structure.rotation,
            trellis_color,
        )
        for arm_index in 0 ..< 3 {
            arm_y := growth_structure.base_y + growth_structure.height * (.28 + f32(arm_index) * .075)
            world_box_rotated(
                {arm_x, arm_y, arm_z},
                {trellis_arm_width, trellis_rail_width, trellis_rail_width},
                growth_structure.rotation,
                trellis_color,
            )
        }
        // Carry visible foliage down the trained leader instead of leaving a
        // bare pole between the commissioned planter and the canopy crown.
        // These are compact leaf-only renewal shoots centered on the outer
        // pier, so the display glazing and merchandise stay unobstructed.
        storefront_maturity := architecture.bougainvillea_maturity(density)
        lower_shoot_count := min(3 + int(storefront_maturity), 4)
        shoot_reach := [4]f32{.18, .62, .34, .78}
        shoot_height_offset := [4]f32{1.02, 1.68, 2.46, 3.08}
        for shoot_index in 0 ..< lower_shoot_count {
            shoot_side := shoot_index % 2 == 0 ? f32(1) : f32(-1)
            shoot_local_x := trellis_vertical_x - storefront_growth_side * shoot_reach[shoot_index]
            shoot_x, shoot_z := world_rotate_xz(
                growth_structure.center_x,
                growth_structure.center_z,
                shoot_local_x,
                trellis_z + .055,
                growth_structure.rotation,
            )
            shoot_width := (.58 + storefront_maturity * .18) * (1 - f32(shoot_index) * .045)
            if shoot_index == 0 {
                // The lowest upright atlas tile is seen almost square-on from
                // across the street. Keep it compact enough to read as a
                // renewal tuft above the pot, not a clipped green planter.
                shoot_width *= .82
            }
            shoot_height := shoot_width * .78
            shoot_center := third_person.Vec3 {
                shoot_x,
                growth_structure.base_y + shoot_height_offset[shoot_index],
                shoot_z,
            }
            shoot_root_x, shoot_root_z := world_rotate_xz(
                growth_structure.center_x,
                growth_structure.center_z,
                trellis_vertical_x,
                trellis_z + .02,
                growth_structure.rotation,
            )
            shoot_root := third_person.Vec3 {
                shoot_root_x,
                shoot_center.y - .14 - f32(shoot_index % 2) * .08,
                shoot_root_z,
            }
            shoot_wood := color_lerp({73, 103, 61, 255}, {112, 77, 51, 255}, storefront_maturity)
            world_tube_between(
                shoot_root,
                shoot_center,
                {0, 1, 0},
                .030 + storefront_maturity * .008,
                .017 + storefront_maturity * .005,
                shoot_wood,
            )
            shoot_tile := int((plant_seed + u32(shoot_index * 13)) % 2) * 2
            world_bougainvillea_card(
                shoot_center,
                shoot_width,
                shoot_height,
                shoot_tile,
                storefront_growth_side > 0,
                shoot_side * (.028 + f32(shoot_index) * .006),
                .94,
                true,
            )
        }
        // Short wall standoffs and warm metal caps make the green frame read
        // as installed hardware rather than lines painted onto the stucco.
        // They remain entirely on the outer masonry pier.
        for rail_index in 0 ..< 2 {
            anchor_local_x := rail_index == 0 ? trellis_vertical_x : inner_trellis_x
            for anchor_level in 0 ..< 3 {
                anchor_y := growth_structure.base_y + .95 + f32(anchor_level) * 2.05
                if anchor_y > trellis_center_y + trellis_height * .5 - .18 do continue
                anchor_x, anchor_z := world_rotate_xz(
                    growth_structure.center_x,
                    growth_structure.center_z,
                    anchor_local_x,
                    growth_structure.depth * .5 + .155,
                    growth_structure.rotation,
                )
                world_box_rotated(
                    {anchor_x, anchor_y, anchor_z},
                    {.085, .085, .22},
                    growth_structure.rotation,
                    {73, 82, 70, 255},
                )
                cap_x, cap_z := world_rotate_xz(
                    growth_structure.center_x,
                    growth_structure.center_z,
                    anchor_local_x,
                    trellis_z + .025,
                    growth_structure.rotation,
                )
                world_box_rotated(
                    {cap_x, anchor_y, cap_z},
                    {.12, .12, .035},
                    growth_structure.rotation,
                    {151, 119, 70, 255},
                )
            }
        }
        // A tiny planter uplight keeps the trained vine legible after dark.
        // Its glow stays low and narrow so it cannot compete with the display
        // windows or read as another municipal street lamp.
        uplight_x, uplight_z := world_rotate_xz(
            growth_structure.center_x,
            growth_structure.center_z,
            storefront_growth_side * growth_structure.width * .43,
            growth_structure.depth * .5 + .58,
            growth_structure.rotation,
        )
        world_box_rotated(
            {uplight_x, growth_structure.base_y + .17, uplight_z},
            {.24, .24, .22},
            growth_structure.rotation,
            {72, 63, 49, 255},
        )
        world_box_rotated_material(
            {uplight_x, growth_structure.base_y + .31, uplight_z},
            {.16, .045, .14},
            growth_structure.rotation,
            {255, 186, 96, 255},
            .Emissive,
        )
        world_billboard_material_uv(
            editor,
            {uplight_x, growth_structure.base_y + .78, uplight_z},
            .62,
            1.10,
            {255, 185, 98, 25},
            .Emissive_Halo,
        )
        world_municipal_light_pool(
            uplight_x,
            growth_structure.base_y,
            uplight_z,
            &editor.project,
            .10,
            .72,
            .52,
            growth_structure.rotation,
            24,
            0,
            {255, 186, 96, 255},
        )
    }
    for vine in 0 ..< vine_count {
        vine_seed := plant_seed + u32(vine * 7)
        spread := root_spread
        if vine_count > 1 do spread += (f32(vine) / f32(vine_count - 1) - .5) * .24
        surface_seed := growth_structure.kind == .Architecture ? plant_seed : vine_seed
        surface_offset := f32(math.cos(f64(f32(surface_seed) * .23))) * .18
        attachment_x := spread * growth_structure.width * .62
        if mixed_use_storefront {
            attachment_x = storefront_growth_side * growth_structure.width * (.43 - f32(vine) * .035)
        }
        attachment_z := growth_structure.depth * .5 + .28 + surface_offset
        if growth_structure.kind != .Architecture {
            // Non-building targets are treated as rounded masses: place
            // each vine on the near radial shell instead of projecting it
            // onto an arbitrary rectangular front plane.
            shell_radius := max(growth_structure.width, growth_structure.depth) * .46 + .24
            attachment_x = spread * shell_radius
            shell_height := f32(
                math.sqrt(f64(max(shell_radius * shell_radius - attachment_x * attachment_x, f32(.16)))),
            )
            attachment_z = shell_height + surface_offset
        }
        vine_height := growth_structure.height * height_fraction * (.88 + f32((vine + int(structure.seed)) % 3) * .08)
        if mixed_use_storefront {
            // Shopfront plants are deliberately trained into the canopy and
            // first-floor band rather than allowed to become tree-like.
            vine_height *= .92
        }
        world_climbing_leaf_vine(
            growth_structure,
            attachment_x,
            root_attachment_x,
            attachment_z,
            vine_height,
            density,
            vine_seed,
            plant_seed,
            vine == 0,
        )
    }
    clear(&entry.world_vertices)
    clear(&entry.bougainvillea_vertices)
    if world_first < len(world_renderer.vertices) {
        append(&entry.world_vertices, ..world_renderer.vertices[world_first:])
    }
    if bougainvillea_first < len(world_renderer.bougainvillea_vertices) {
        append(&entry.bougainvillea_vertices, ..world_renderer.bougainvillea_vertices[bougainvillea_first:])
    }
    entry.valid = true
    entry.structure = structure
    entry.density = density
    entry.detail_tier = detail_tier
    entry.capture_seed_enabled = capture_seed_enabled
    entry.capture_seed = capture_seed
}

world_climbing_leaf_density_overlay :: proc(editor: ^Editor) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "climbing_leaf_overlay")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    if editor == nil || editor.in_map || !editor.climbing_leaf_paint_mode do return
    field := &editor.project.climbing_leaf_density
    cell := terrain.BASE_CELL_SIZE
    half := f32(terrain.RING_RESOLUTION - 1) * .5
    camera := perspective_camera(editor.camera_pose)
    width, height := max(canvas2d.GetScreenWidth(), 1), max(canvas2d.GetScreenHeight(), 1)
    aspect := f32(width) / f32(height)
    near_plane := world_camera_near_clip(editor)
    world_overlay_chunk_bounds_sync(editor)
    islands_moved := false
    for island in editor.project.island_transforms {
        if island.current_x != island.source_x || island.current_z != island.source_z {
            islands_moved = true
            break
        }
    }
    cell_count := terrain.RING_RESOLUTION - 1
    for chunk_z in 0 ..< OVERLAY_CHUNKS_PER_AXIS {
        for chunk_x in 0 ..< OVERLAY_CHUNKS_PER_AXIS {
            bounds := world_renderer.overlay_chunk_bounds[chunk_z * OVERLAY_CHUNKS_PER_AXIS + chunk_x]
            if !islands_moved &&
               !static_sphere_in_frustum(camera, bounds.center, bounds.radius, aspect, near_plane, WORLD_FAR_CLIP) {
                continue
            }
            min_z, max_z := chunk_z * OVERLAY_CHUNK_CELLS, min((chunk_z + 1) * OVERLAY_CHUNK_CELLS, cell_count)
            min_x, max_x := chunk_x * OVERLAY_CHUNK_CELLS, min((chunk_x + 1) * OVERLAY_CHUNK_CELLS, cell_count)
            for z in min_z ..< max_z {
                for x in min_x ..< max_x {
                    density := f32(field[z * terrain.RING_RESOLUTION + x]) / 255
                    if density <= .01 do continue
                    x0, z0 := (f32(x) - half) * cell, (f32(z) - half) * cell
                    x1, z1 := x0 + cell, z0 + cell
                    x0, z0 = terrain.island_world_position(&editor.project, x0, z0)
                    x1, z1 = terrain.island_world_position(&editor.project, x1, z1)
                    lift := f32(.13)
                    a := third_person.Vec3{x0, terrain.sample_surface_height(&editor.project, 0, x0, z0) + lift, z0}
                    b := third_person.Vec3{x1, terrain.sample_surface_height(&editor.project, 0, x1, z0) + lift, z0}
                    c := third_person.Vec3{x1, terrain.sample_surface_height(&editor.project, 0, x1, z1) + lift, z1}
                    d := third_person.Vec3{x0, terrain.sample_surface_height(&editor.project, 0, x0, z1) + lift, z1}
                    world_quad(a, b, c, d, {57, 141, 78, u8(24 + density * 92)})
                }
            }
        }
    }
}

World_Aircraft_Transform :: World_Model_Transform

world_aircraft_presentation_basis :: #force_inline proc(body: flight.Body_State) -> flight.Basis {
    // Aircraft meshes and the flight model both use local -Z as forward.
    // Preserve that shared authoring basis without a presentation-only flip.
    return flight.basis_from_orientation(body.orientation)
}

world_aircraft_transform :: #force_inline proc(body: flight.Body_State, scale: f32) -> World_Aircraft_Transform {
    basis := world_aircraft_presentation_basis(body)
    return world_model_transform_from_basis(
        {body.position.x, body.position.y, body.position.z},
        {basis.right.x * scale, basis.right.y * scale, basis.right.z * scale},
        {basis.up.x * scale, basis.up.y * scale, basis.up.z * scale},
        {basis.forward.x * scale, basis.forward.y * scale, basis.forward.z * scale},
    )
}

world_aircraft_vertex_world :: #force_inline proc(
    transform: World_Aircraft_Transform,
    position: [3]f32,
) -> third_person.Vec3 {
    return world_model_vertex_world(transform, position)
}

world_aircraft_normal_world :: #force_inline proc(
    transform: World_Aircraft_Transform,
    normal: [3]f32,
) -> third_person.Vec3 {
    return world_model_normal_world(transform, normal)
}

world_aircraft_in_view :: proc(editor: ^Editor, position: flight.Vec3, radius: f32) -> bool {
    if editor == nil do return false
    focal_length := editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : f32(1.35)
    camera := perspective_camera(editor.camera_pose, focal_length)
    width := max(canvas2d.GetScreenWidth(), 1)
    height := max(canvas2d.GetScreenHeight(), 1)
    return static_sphere_in_frustum(
        camera,
        {position.x, position.y, position.z},
        radius,
        f32(width) / f32(height),
        world_camera_near_clip(editor),
        WORLD_FAR_CLIP,
    )
}

world_rondine_presentation_basis :: #force_inline proc(editor: ^Editor) -> flight.Basis {
    basis := flight.basis_from_orientation(editor.rondine.body.orientation)
    pitch := clamp(-editor.flight_control.pitch * .075 + editor.rondine.body.velocity.y * .018, -.1, .1)
    pitch_c, pitch_s := math.cos(pitch), math.sin(pitch)
    forward := basis.forward
    up := basis.up
    basis.forward = forward * pitch_c + up * pitch_s
    basis.up = up * pitch_c - forward * pitch_s

    heel := clamp(
        -editor.rondine.steering * .14 -
        editor.rondine.telemetry.slip * (.08 + editor.rondine.telemetry.drift_intensity * .14),
        -.27,
        .27,
    )
    c, s := math.cos(heel), math.sin(heel)
    right := basis.right
    up = basis.up
    basis.right = right * c + up * s
    basis.up = up * c - right * s
    return basis
}

world_rondine_local :: #force_inline proc(editor: ^Editor, p: [3]f32) -> third_person.Vec3 {
    body := editor.rondine.body
    body.orientation = flight.orientation_from_basis(world_rondine_presentation_basis(editor))
    transform := world_aircraft_transform(body, 1)
    return world_aircraft_vertex_world(transform, p)
}

world_rondine_box :: proc(
    editor: ^Editor,
    center, size: [3]f32,
    color: canvas2d.Color,
    material_kind: World_Material_Kind = .BRDF,
) {
    x, y, z := size[0] * .5, size[1] * .5, size[2] * .5
    p := [8][3]f32 {
        {center[0] - x, center[1] - y, center[2] - z},
        {center[0] + x, center[1] - y, center[2] - z},
        {center[0] + x, center[1] + y, center[2] - z},
        {center[0] - x, center[1] + y, center[2] - z},
        {center[0] - x, center[1] - y, center[2] + z},
        {center[0] + x, center[1] - y, center[2] + z},
        {center[0] + x, center[1] + y, center[2] + z},
        {center[0] - x, center[1] + y, center[2] + z},
    }
    w: [8]third_person.Vec3
    for point, index in p do w[index] = world_rondine_local(editor, point)
    world_quad_material(w[0], w[3], w[2], w[1], color, material_kind)
    world_quad_material(w[4], w[5], w[6], w[7], color, material_kind)
    world_quad_material(w[0], w[4], w[7], w[3], color, material_kind)
    world_quad_material(w[1], w[2], w[6], w[5], color, material_kind)
    world_quad_material(w[3], w[7], w[6], w[2], color, material_kind)
    world_quad_material(w[0], w[1], w[5], w[4], color, material_kind)
}

world_rondine_hull :: proc(editor: ^Editor, deck, side, keel: canvas2d.Color) {
    // A long, high bow and a tucked fore-keel make the monohull read as a
    // swallow's small head flowing into a pale breast, not a blunt speedboat.
    bow := world_rondine_local(editor, {0, .5, -5.72})
    bow_keel := world_rondine_local(editor, {0, -.28, -5.12})
    fore_l := world_rondine_local(editor, {-1.02, .88, -3.78})
    fore_r := world_rondine_local(editor, {1.02, .88, -3.78})
    beam_l := world_rondine_local(editor, {-1.22, .96, 1.72})
    beam_r := world_rondine_local(editor, {1.22, .96, 1.72})
    stern_l := world_rondine_local(editor, {-.76, .68, 4.65})
    stern_r := world_rondine_local(editor, {.76, .68, 4.65})
    chine_fore_l := world_rondine_local(editor, {-.9, -.02, -3.72})
    chine_fore_r := world_rondine_local(editor, {.9, -.02, -3.72})
    chine_aft_l := world_rondine_local(editor, {-1.03, -.12, 1.9})
    chine_aft_r := world_rondine_local(editor, {1.03, -.12, 1.9})
    stern_keel_l := world_rondine_local(editor, {-.58, -.08, 4.5})
    stern_keel_r := world_rondine_local(editor, {.58, -.08, 4.5})
    keel_fore := world_rondine_local(editor, {0, -.7, -2.75})
    keel_aft := world_rondine_local(editor, {0, -.62, 3.75})

    // One continuous flying-boat hull: broad deck, hard chines, and a single
    // center keel. The tapered stern keeps it distinct from twin floats.
    world_triangle_material(bow, fore_l, fore_r, deck, .Car_Paint)
    world_quad_material(fore_l, beam_l, beam_r, fore_r, deck, .Car_Paint)
    world_quad_material(beam_l, stern_l, stern_r, beam_r, deck, .Car_Paint)
    world_triangle_material(bow, chine_fore_l, fore_l, side, .Car_Paint)
    world_triangle_material(bow, fore_r, chine_fore_r, side, .Car_Paint)
    world_triangle_material(bow, bow_keel, chine_fore_l, side, .Car_Paint)
    world_triangle_material(bow, chine_fore_r, bow_keel, side, .Car_Paint)
    world_triangle_material(bow_keel, chine_fore_r, chine_fore_l, keel, .Car_Paint)
    world_quad_material(fore_l, chine_fore_l, chine_aft_l, beam_l, side, .Car_Paint)
    world_quad_material(fore_r, beam_r, chine_aft_r, chine_fore_r, side, .Car_Paint)
    world_quad_material(beam_l, chine_aft_l, stern_keel_l, stern_l, side, .Car_Paint)
    world_quad_material(beam_r, stern_r, stern_keel_r, chine_aft_r, side, .Car_Paint)
    world_triangle_material(bow_keel, keel_fore, chine_fore_l, keel, .Car_Paint)
    world_triangle_material(bow_keel, chine_fore_r, keel_fore, keel, .Car_Paint)
    world_quad_material(chine_fore_l, keel_fore, keel_aft, chine_aft_l, keel, .Car_Paint)
    world_quad_material(chine_fore_r, chine_aft_r, keel_aft, keel_fore, keel, .Car_Paint)
    world_triangle_material(chine_aft_l, keel_aft, stern_keel_l, side, .Car_Paint)
    world_triangle_material(chine_aft_r, stern_keel_r, keel_aft, side, .Car_Paint)
    world_quad_material(stern_l, stern_keel_l, stern_keel_r, stern_r, side, .Car_Paint)
}

world_rondine_propeller_blade :: proc(editor: ^Editor, center_x, angle, z: f32, color: canvas2d.Color) {
    c, s := math.cos(angle), math.sin(angle)
    half_length, half_width := f32(1.08), f32(.075)
    direction := [2]f32{c * half_length, s * half_length}
    across := [2]f32{-s * half_width, c * half_width}
    p := [4][3]f32 {
        {center_x - direction[0] - across[0], .52 - direction[1] - across[1], z},
        {center_x - direction[0] + across[0], .52 - direction[1] + across[1], z},
        {center_x + direction[0] + across[0], .52 + direction[1] + across[1], z},
        {center_x + direction[0] - across[0], .52 + direction[1] - across[1], z},
    }
    front: [4]third_person.Vec3
    back: [4]third_person.Vec3
    for point, index in p {
        front[index] = world_rondine_local(editor, point)
        back_point := point
        back_point[2] += .08
        back[index] = world_rondine_local(editor, back_point)
    }
    world_quad(front[0], front[1], front[2], front[3], color)
    world_quad(back[3], back[2], back[1], back[0], color)
    world_quad(front[0], back[0], back[1], front[1], color)
    world_quad(front[1], back[1], back[2], front[2], color)
    world_quad(front[2], back[2], back[3], front[3], color)
    world_quad(front[3], back[3], back[0], front[0], color)
}

world_rondine_propeller_blur :: proc(editor: ^Editor, center_x, phase, strength: f32) {
    if strength <= .01 do return
    center := world_rondine_local(editor, {center_x, .52, 2.075})
    segments :: 16
    radius := f32(1.13)
    alpha := u8(clamp(18 + strength * 42, 0, 68))
    center_color := canvas2d.Color{78, 87, 85, alpha}
    edge_color := canvas2d.Color{92, 105, 101, 0}
    for segment in 0 ..< segments {
        angle_a := phase + f32(segment) / segments * math.PI * 2
        angle_b := phase + f32(segment + 1) / segments * math.PI * 2
        a := world_rondine_local(
            editor,
            {center_x + math.cos(angle_a) * radius, .52 + math.sin(angle_a) * radius, 2.075},
        )
        b := world_rondine_local(
            editor,
            {center_x + math.cos(angle_b) * radius, .52 + math.sin(angle_b) * radius, 2.075},
        )
        world_triangle_colored(center, a, b, center_color, edge_color, edge_color)
        world_triangle_colored(center, b, a, center_color, edge_color, edge_color)
    }
}

world_rondine_propeller :: proc(editor: ^Editor, center_x, phase: f32, color: canvas2d.Color) {
    rotation := editor.rondine.propeller_turns * math.PI * 2 + phase
    world_rondine_propeller_blade(editor, center_x, rotation, 2.08, color)
    world_rondine_propeller_blade(editor, center_x, rotation + math.PI * .5, 2.09, color)
    blur_strength := clamp((editor.rondine.throttle - .22) / .58, 0, 1)
    world_rondine_propeller_blur(editor, center_x, phase * .37, blur_strength)
    world_rondine_box(editor, {center_x, .52, 2.13}, {.36, .36, .28}, {205, 193, 153, 255})
}
