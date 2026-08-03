package main
import "core:math"

import dio "../packages/dio"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math/linalg"
import vk "vendor:vulkan"
import canvas2d "zelda_engine:canvas2d"
import gltf "zelda_engine:gltf"

world_small_faceted_rock :: proc(structure: terrain.Structure) {
    world_small_rock_templates_init()
    template := &small_rock_templates[int(structure.seed % SMALL_ROCK_VARIATION_COUNT)]
    base_color := canvas2d.Color{structure.color[0], structure.color[1], structure.color[2], structure.color[3]}
    radius_x := structure.width * .5 * template.footprint_x
    radius_z := structure.depth * .5 * template.footprint_z
    rock_height := structure.height * template.height_scale
    bottom: [SMALL_ROCK_SIDE_CAPACITY]third_person.Vec3
    shoulder: [SMALL_ROCK_SIDE_CAPACITY]third_person.Vec3
    crest: [SMALL_ROCK_SIDE_CAPACITY]third_person.Vec3
    side_normal: [SMALL_ROCK_SIDE_CAPACITY]third_person.Vec3
    ridge_x, ridge_z := math.cos(template.ridge_angle), math.sin(template.ridge_angle)
    for side in 0 ..< template.side_count {
        angle := f32(side) * math.TAU / f32(template.side_count)
        local_x := math.cos(angle) * radius_x * template.bottom_radius[side]
        local_z := math.sin(angle) * radius_z * template.bottom_radius[side]
        bottom_x, bottom_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x,
            local_z,
            structure.rotation,
        )
        shoulder_x, shoulder_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x * template.shoulder_radius[side],
            local_z * template.shoulder_radius[side],
            structure.rotation,
        )
        bottom[side] = {bottom_x, structure.base_y, bottom_z}
        shoulder[side] = {shoulder_x, structure.base_y + rock_height * template.shoulder_height[side], shoulder_z}
        if template.cap_mode == 1 || template.cap_mode == 2 {
            projection := math.cos(angle - template.ridge_angle)
            ridge_local_x := ridge_x * projection * radius_x * template.ridge_length
            ridge_local_z := ridge_z * projection * radius_z * template.ridge_length
            crest_x, crest_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                ridge_local_x + template.cap_offset_x * radius_x,
                ridge_local_z + template.cap_offset_z * radius_z,
                structure.rotation,
            )
            saddle := template.cap_mode == 2 ? abs(projection) * .12 - .05 : f32(0)
            crest[side] = {crest_x, structure.base_y + rock_height * (template.cap_height + saddle), crest_z}
        } else {
            crest_x, crest_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x * template.cap_scale + template.cap_offset_x * radius_x,
                local_z * template.cap_scale + template.cap_offset_z * radius_z,
                structure.rotation,
            )
            step := template.cap_mode == 3 && side & 1 == 0 ? f32(.09) : f32(0)
            crest[side] = {crest_x, structure.base_y + rock_height * (template.cap_height + step), crest_z}
        }
        normal_x, normal_z := world_rotate_xz(
            0,
            0,
            math.cos(angle) / max(radius_x, f32(.01)),
            math.sin(angle) / max(radius_z, f32(.01)),
            structure.rotation,
        )
        side_normal[side] = linalg.normalize0([3]f32{normal_x, .22, normal_z})
    }
    tone := f32(int(structure.seed & 7) - 3) * 1.7
    rock_color := canvas2d.Color {
        r = u8(clamp(f32(base_color.r) + tone, 0, 255)),
        g = u8(clamp(f32(base_color.g) + tone * .65, 0, 255)),
        b = u8(clamp(f32(base_color.b) - tone * .30, 0, 255)),
        a = base_color.a,
    }
    for side in 0 ..< template.side_count {
        next := (side + 1) % template.side_count
        world_triangle_smooth_lit(
            bottom[side],
            shoulder[side],
            shoulder[next],
            side_normal[side],
            side_normal[side],
            side_normal[next],
            rock_color,
            rock_color,
            rock_color,
            .96,
        )
        world_triangle_smooth_lit(
            bottom[side],
            shoulder[next],
            bottom[next],
            side_normal[side],
            side_normal[next],
            side_normal[next],
            rock_color,
            rock_color,
            rock_color,
            .96,
        )
        world_triangle_smooth_lit(
            shoulder[side],
            crest[side],
            crest[next],
            {0, 1, 0},
            {0, 1, 0},
            {0, 1, 0},
            rock_color,
            rock_color,
            rock_color,
            .98,
        )
        world_triangle_smooth_lit(
            shoulder[side],
            crest[next],
            shoulder[next],
            {0, 1, 0},
            {0, 1, 0},
            {0, 1, 0},
            rock_color,
            rock_color,
            rock_color,
            .98,
        )
    }
    if template.cap_mode == 0 || template.cap_mode == 3 {
        cap_x, cap_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            template.cap_offset_x * radius_x,
            template.cap_offset_z * radius_z,
            structure.rotation,
        )
        cap := third_person.Vec3 {
            cap_x,
            structure.base_y + rock_height * (template.cap_height + (template.cap_mode == 3 ? f32(.04) : f32(0))),
            cap_z,
        }
        for side in 0 ..< template.side_count {
            next := (side + 1) % template.side_count
            world_triangle_smooth_lit(
                crest[side],
                cap,
                crest[next],
                {0, 1, 0},
                {0, 1, 0},
                {0, 1, 0},
                rock_color,
                rock_color,
                rock_color,
                .98,
            )
        }
    }
}

world_cliff_rock_asset_point :: proc(
    structure: terrain.Structure,
    mesh: ^gltf.Glb_Mesh,
    vertex: gltf.Vec3,
) -> third_person.Vec3 {
    span_x := max(mesh.max.x - mesh.min.x, f32(.001))
    span_y := max(mesh.max.y - mesh.min.y, f32(.001))
    span_z := max(mesh.max.z - mesh.min.z, f32(.001))
    local_x := (vertex.x - (mesh.min.x + mesh.max.x) * .5) * structure.width / span_x
    local_y := (vertex.y - mesh.min.y) * structure.height / span_y
    local_z := (vertex.z - (mesh.min.z + mesh.max.z) * .5) * structure.depth / span_z
    world_x, world_z := world_rotate_xz(structure.center_x, structure.center_z, local_x, local_z, structure.rotation)
    return {world_x, structure.base_y + local_y, world_z}
}

world_cliff_rock_asset_normal :: proc(
    structure: terrain.Structure,
    mesh: ^gltf.Glb_Mesh,
    vertex: gltf.Vec3,
) -> third_person.Vec3 {
    center_x := (mesh.min.x + mesh.max.x) * .5
    center_y := (mesh.min.y + mesh.max.y) * .5
    center_z := (mesh.min.z + mesh.max.z) * .5
    span_x := max(mesh.max.x - mesh.min.x, f32(.001))
    span_y := max(mesh.max.y - mesh.min.y, f32(.001))
    span_z := max(mesh.max.z - mesh.min.z, f32(.001))
    normal := linalg.normalize0(
        [3]f32{(vertex.x - center_x) / span_x, (vertex.y - center_y) / span_y, (vertex.z - center_z) / span_z},
    )
    x, z := world_rotate_xz(0, 0, normal.x, normal.z, structure.rotation)
    return linalg.normalize0([3]f32{x, normal.y, z})
}

world_cliff_rock_asset :: proc(structure: terrain.Structure) -> bool {
    asset_index := int(structure.seed % CLIFF_ROCK_ASSET_COUNT)
    if !cliff_rock_assets.ready[asset_index] do return false
    mesh := &cliff_rock_assets.meshes[asset_index]
    color := canvas2d.Color{structure.color[0], structure.color[1], structure.color[2], structure.color[3]}
    for primitive in mesh.primitives {
        end := min(primitive.first + primitive.count, len(mesh.indices))
        for index := primitive.first; index + 2 < end; index += 3 {
            for corner in 0 ..< 3 {
                vertex_index := mesh.indices[index + corner]
                if vertex_index >= u32(len(mesh.vertices)) do continue
                source := mesh.vertices[vertex_index]
                point := world_cliff_rock_asset_point(structure, mesh, source)
                normal := world_cliff_rock_asset_normal(structure, mesh, source)
                vertex := world_vertex(point, color)
                vertex.kind = .Rock
                vertex.normal = {normal.x, normal.y, normal.z}
                vertex.material = {1.05, .86}
                if vertex_index < u32(len(mesh.texcoords)) {
                    uv := mesh.texcoords[vertex_index]
                    vertex.uv = {uv.x, uv.y}
                }
                append(&world_renderer.vertices, vertex)
            }
        }
    }
    return true
}

@(no_instrumentation)
world_formation_sea_vegetation_band :: proc(
    structure: terrain.Structure,
    project: ^terrain.Project,
    lod: Structure_LOD = .Near,
) {
    if project == nil || structure.base_y > project.sea_level + .04 do return

    footprint := max(structure.width, structure.depth)
    band_height := clamp(footprint * .09, f32(.18), structure.height * .22)
    if band_height <= .04 do return

    // Larger sea stacks support a broader fringe, while the height cap keeps
    // small, tall spires from turning green all the way up their faces.
    color := canvas2d.Color{76, 105, 73, 255}
    if structure.kind == .Cliff {
        band := structure
        band.width += .035
        band.depth += .035
        band.height = band_height
        band.color = {color.r, color.g, color.b, color.a}
        world_cliff_formation(band, lod)
        return
    }

    segments := lod == .Near ? 16 : lod == .Medium ? 10 : 6
    lower: [16]third_person.Vec3
    upper: [16]third_person.Vec3
    fraction := clamp(band_height / max(structure.height, f32(.001)), 0, 1)
    top_radius := f32(1)
    switch structure.kind {
    case .Rock:
        top_radius = 1 - fraction * .25
    case .Spire:
        top_radius = 1 - fraction * .72
    case .Mountain:
        top_radius = 1 - fraction * .25
    case .Ridge:
        top_radius = 1 - fraction * .30
    case .Box, .Cliff, .Foliage, .Architecture, .Ruins:
        return
    }
    top_radius = max(top_radius, f32(.2))
    for segment in 0 ..< segments {
        angle := f32(segment) * math.PI * 2 / f32(segments)
        lower_x, lower_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            math.cos(angle) * structure.width * .505,
            math.sin(angle) * structure.depth * .505,
            structure.rotation,
        )
        upper_x, upper_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            math.cos(angle) * structure.width * .5 * (top_radius + .01),
            math.sin(angle) * structure.depth * .5 * (top_radius + .01),
            structure.rotation,
        )
        lower[segment] = {lower_x, structure.base_y, lower_z}
        upper[segment] = {upper_x, structure.base_y + band_height, upper_z}
    }
    for segment in 0 ..< segments {
        next := (segment + 1) % segments
        world_quad(lower[segment], upper[segment], upper[next], lower[next], color)
    }
}

world_formation :: proc(structure: terrain.Structure, project: ^terrain.Project = nil, lod: Structure_LOD = .Near) {
    switch structure.kind {
    case .Box:
        world_box_rotated(
            {structure.center_x, structure.base_y + structure.height * .5, structure.center_z},
            {structure.width, structure.height, structure.depth},
            structure.rotation,
            canvas2d.Color{structure.color[0], structure.color[1], structure.color[2], structure.color[3]},
        )
    case .Rock:
        if structure.color[3] == 254 && world_cliff_rock_asset(structure) {
            // Authored cliff-rock kit instance.
        } else if max(structure.width, structure.depth, structure.height) <= 5 && lod != .Far {
            world_small_faceted_rock(structure)
        } else {
            world_radial_formation(structure, {1, .94, .62, .20}, {0, .24, .58, .88}, 1, .96, lod)
        }
    case .Spire:
        world_radial_formation(structure, {1, .62, .30, .07}, {0, .20, .46, .94}, 1, 1, lod)
    case .Mountain:
        world_radial_formation(structure, {1, .94, .68, .24}, {0, .22, .54, .86}, 1, .99, lod)
    case .Ridge:
        stone := structure
        stone.color = world_limestone_color(.Ridge)
        world_radial_formation(stone, {1, .92, .60, .14}, {0, .22, .50, .78}, .42, .90, lod)
        world_formation_foliage(stone, lod)
    case .Cliff:
        stone := structure
        stone.color = world_limestone_color(.Cliff)
        world_cliff_formation(stone, lod)
        world_formation_foliage(stone, lod)
    case .Foliage:
        if settlement_cemetery_structure_is_reservation(structure) do return
        world_foliage_formation(structure, terrain.BASE_CELL_SIZE, lod)
    case .Architecture:
        world_architecture(structure, project, lod)
    case .Ruins:
        world_settlement_ruin(structure, lod)
    }
    world_formation_sea_vegetation_band(structure, project, lod)
}

world_foliage_formation_cached :: proc(structure: terrain.Structure, structure_index: int, force_near := false) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "world_foliage_cache")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    if structure_index < 0 || structure_index >= len(world_renderer.foliage_geometry_cache) {
        world_foliage_formation(structure)
        return
    }
    entry := &world_renderer.foliage_geometry_cache[structure_index]
    lod_result := structure_lod_for(structure, entry.lod, force_near)
    camera := world_renderer.editor.camera_pose.position
    aerial_view := foliage_aerial_view_select(
        camera.y - structure.base_y,
        structure.height,
        entry.valid && entry.structure == structure && entry.aerial_view,
        driving_aircraft(world_renderer.editor),
    )
    dx := camera.x - structure.center_x
    dz := camera.z - structure.center_z
    distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
    // Foliage topology and surface detail vary with camera distance, while a
    // few accent cards choose the camera-facing side of a crown. Quantizing
    // both values keeps those authored LOD decisions responsive without
    // rebuilding thousands of deterministic static vertices every frame.
    // Structure-relative buckets also stagger rebuilds naturally as the
    // player moves through a forest instead of invalidating the whole scene.
    distance_bucket := lod_result.tier == .Far ? i32(0) : i32(math.floor(distance / 16))
    direction := math.atan2(dz, dx)
    direction_bucket := lod_result.tier == .Far ? i32(0) : i32(math.floor((direction + math.PI) * 16 / (math.PI * 2)))
    if entry.valid &&
       entry.structure == structure &&
       entry.aerial_view == aerial_view &&
       entry.lod == lod_result.tier &&
       entry.distance_bucket == distance_bucket &&
       entry.direction_bucket == direction_bucket {
        append(&world_renderer.vertices, ..entry.world_vertices[:])
        append(&world_renderer.foliage_vertices, ..entry.foliage_vertices[:])
        return
    }

    world_first := len(world_renderer.vertices)
    foliage_first := len(world_renderer.foliage_vertices)
    world_foliage_formation(structure, terrain.BASE_CELL_SIZE, lod_result.tier, aerial_view)
    world_renderer.structure_lod_cache_rebuilds += 1
    clear(&entry.world_vertices)
    clear(&entry.foliage_vertices)
    if world_first < len(world_renderer.vertices) {
        append(&entry.world_vertices, ..world_renderer.vertices[world_first:])
    }
    if foliage_first < len(world_renderer.foliage_vertices) {
        append(&entry.foliage_vertices, ..world_renderer.foliage_vertices[foliage_first:])
    }
    entry.valid = true
    entry.structure = structure
    entry.aerial_view = aerial_view
    entry.lod = lod_result.tier
    entry.lod_transition = lod_result.transition
    entry.distance_bucket = distance_bucket
    entry.direction_bucket = direction_bucket
}

world_retained_static_draw_emit :: proc(cache_index: int) {
    if cache_index < 0 || cache_index >= len(world_renderer.static_geometry_cache) do return
    entry := &world_renderer.static_geometry_cache[cache_index]
    if !entry.valid || len(entry.world_vertices) == 0 || len(entry.world_indices) == 0 do return
    append(&world_renderer.retained_static_draws, Retained_Static_Draw{cache_index = cache_index})
}

world_retained_static_repack :: proc() {
    if !world_renderer.retained_static_dirty do return
    clear(&world_renderer.static_vertices)
    clear(&world_renderer.static_indices)
    structure_count := 0
    if world_renderer.editor != nil {
        structure_count = min(world_renderer.editor.project.structure_count, len(world_renderer.static_geometry_cache))
    }
    for index in 0 ..< structure_count {
        entry := &world_renderer.static_geometry_cache[index]
        if !entry.valid || len(entry.world_vertices) == 0 || len(entry.world_indices) == 0 do continue
        entry.retained_first_vertex = u32(len(world_renderer.static_vertices))
        entry.retained_first_index = u32(len(world_renderer.static_indices))
        append(&world_renderer.static_vertices, ..entry.world_vertices[:])
        append(&world_renderer.static_indices, ..entry.world_indices[:])
    }
    world_renderer.retained_patio_first_vertex = u32(len(world_renderer.static_vertices))
    world_renderer.retained_patio_first_index = u32(len(world_renderer.static_indices))
    append(&world_renderer.static_vertices, ..world_renderer.retained_patio_vertices[:])
    append(&world_renderer.static_indices, ..world_renderer.retained_patio_indices[:])
    world_renderer.retained_patio_index_count = u32(len(world_renderer.retained_patio_indices))
    world_renderer.retained_static_revision += 1
    if world_renderer.retained_static_revision == 0 {
        world_renderer.retained_static_revision = 1
        world_renderer.retained_static_uploaded_revision = {}
    }
    world_renderer.retained_static_dirty = false
}

world_static_indirect_commands_build :: proc() {
    clear(&world_renderer.static_draw_commands)
    for draw in world_renderer.retained_static_draws {
        if draw.cache_index < 0 || draw.cache_index >= len(world_renderer.static_geometry_cache) do continue
        entry := &world_renderer.static_geometry_cache[draw.cache_index]
        if !entry.valid || len(entry.world_indices) == 0 do continue
        append(
            &world_renderer.static_draw_commands,
            vk.DrawIndexedIndirectCommand {
                indexCount = u32(len(entry.world_indices)),
                instanceCount = 1,
                firstIndex = entry.retained_first_index,
                vertexOffset = i32(entry.retained_first_vertex),
            },
        )
    }
    if world_renderer.retained_patio_index_count > 0 {
        append(
            &world_renderer.static_draw_commands,
            vk.DrawIndexedIndirectCommand {
                indexCount = world_renderer.retained_patio_index_count,
                instanceCount = 1,
                firstIndex = world_renderer.retained_patio_first_index,
                vertexOffset = i32(world_renderer.retained_patio_first_vertex),
            },
        )
    }
}

world_static_formation_cached :: proc(
    structure: terrain.Structure,
    structure_index: int,
    project: ^terrain.Project,
    force_near := false,
) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "world_static_cache")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    if project == nil || structure_index < 0 || structure_index >= len(world_renderer.static_geometry_cache) {
        world_formation(structure, project)
        return
    }
    entry := &world_renderer.static_geometry_cache[structure_index]
    lod_result := structure_lod_for(structure, entry.lod, force_near)
    focal_length := f32(1.35)
    if world_renderer.editor.in_map && driving_aircraft(world_renderer.editor) {
        focal_length = world_renderer.editor.flight_camera.focal_length
    }
    camera := perspective_camera(world_renderer.editor.camera_pose, focal_length)
    billboard_right := [3]f32{camera.right.x, camera.right.y, camera.right.z}
    billboard_up := [3]f32{camera.up.x, camera.up.y, camera.up.z}
    if entry.valid && entry.structure == structure && entry.lod == lod_result.tier {
        world_retained_static_draw_emit(structure_index)
        append(&world_renderer.foliage_vertices, ..entry.foliage_vertices[:])
        for card in entry.bougainvillea_cards {
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
        return
    }

    world_first := len(world_renderer.vertices)
    foliage_first := len(world_renderer.foliage_vertices)
    bougainvillea_first := len(world_renderer.bougainvillea_vertices)
    clear(&entry.bougainvillea_cards)
    climbing_leaf_card_capture = &entry.bougainvillea_cards
    world_formation(structure, project, lod_result.tier)
    climbing_leaf_card_capture = nil
    world_renderer.structure_lod_cache_rebuilds += 1
    clear(&entry.world_vertices)
    clear(&entry.world_indices)
    clear(&entry.foliage_vertices)
    clear(&entry.bougainvillea_vertices)
    if world_first < len(world_renderer.vertices) {
        source := world_renderer.vertices[world_first:]
        resize(&entry.world_vertices, len(source))
        resize(&entry.world_indices, len(source))
        optimized_count := adriatic_optimize_unindexed_mesh(
            raw_data(entry.world_vertices),
            raw_data(entry.world_indices),
            raw_data(source),
            u32(len(source)),
            u32(size_of(World_Vertex)),
        )
        if optimized_count > 0 {
            resize(&entry.world_vertices, int(optimized_count))
            resize(&world_renderer.vertices, world_first)
        } else {
            clear(&entry.world_vertices)
            clear(&entry.world_indices)
        }
    }
    if foliage_first < len(world_renderer.foliage_vertices) {
        append(&entry.foliage_vertices, ..world_renderer.foliage_vertices[foliage_first:])
    }
    if bougainvillea_first < len(world_renderer.bougainvillea_vertices) {
        append(&entry.bougainvillea_vertices, ..world_renderer.bougainvillea_vertices[bougainvillea_first:])
    }
    entry.valid = true
    entry.structure = structure
    entry.lod = lod_result.tier
    entry.lod_transition = lod_result.transition
    entry.billboard_right = billboard_right
    entry.billboard_up = billboard_up
    world_renderer.retained_static_dirty = true
    world_retained_static_draw_emit(structure_index)
}

world_structure_preview_cluster :: proc(editor: ^Editor) {
    if editor == nil do return
    preview := editor.structure_preview
    preview.color = {168, 239, 220, 255}
    world_formation(preview)
    world_structure_frame(preview, preview.base_y + .04, {190, 255, 229, 255})
    if !editor.structure_scatter_mode do return
    dx := editor.structure_preview_end_x - editor.structure_anchor_x
    dz := editor.structure_preview_end_z - editor.structure_anchor_z
    length := f32(math.sqrt(f64(dx * dx + dz * dz)))
    if length <= 0 do return
    direction_x, direction_z := dx / length, dz / length
    perpendicular_x, perpendicular_z := -direction_z, direction_x
    cell := editor.project.levels[0].cell_size
    for cluster_index in 0 ..< editor.structure_scatter_count - 1 {
        offset := f32(cluster_index) - f32(editor.structure_scatter_count - 2) * .5
        copy := preview
        copy.center_x += direction_x * offset * length * .22
        copy.center_z += direction_z * offset * length * .22
        jitter := f32(
            math.sin(
                f64(f32(cluster_index) * 2.31 + f32(editor.project.next_structure_id + u64(cluster_index + 1)) * .17),
            ),
        )
        copy.center_x += perpendicular_x * jitter * length * .10
        copy.center_z += perpendicular_z * jitter * length * .10
        copy.width = max(cell, copy.width * (.58 + f32(cluster_index % 2) * .12))
        copy.depth = max(cell, copy.depth * (.58 + f32((cluster_index + 1) % 2) * .12))
        copy.height = max(cell, copy.height * (.72 + f32(cluster_index) * .06))
        copy.base_y = terrain.sample_surface_height(&editor.project, 0, copy.center_x, copy.center_z)
        copy.seed = u32(editor.project.next_structure_id + u64(cluster_index + 1)) * 747796405
        if editor.authoring_tool == .Foliage {
            copy.kind = .Foliage
        } else if !editor.structure_force_box && !editor.structure_cliff_mode {
            copy.kind = terrain.formation_kind_for_gesture(copy.width, copy.depth, copy.height)
        }
        copy.color = {168, 239, 220, 255}
        world_formation(copy)
        world_structure_frame(copy, copy.base_y + .04, {190, 255, 229, 255})
    }
}

world_curve_preview :: proc(editor: ^Editor) {
    if editor == nil || !editor.curve_drawing || editor.curve_point_count < 2 do return
    for index in 0 ..< editor.curve_point_count - 1 {
        if editor.curve_cliff_mode {
            start, end := editor.curve_points[index], editor.curve_points[index + 1]
            dx, dz := end.x - start.x, end.z - start.z
            length := f32(math.sqrt(f64(dx * dx + dz * dz)))
            if length <= .001 do continue
            // A filled ribbon on the directed left side makes the eventual
            // high side legible without previewing obsolete cliff geometry.
            left_x, left_z := -dz / length, dx / length
            marker_width := min(editor.curve_width * .35, editor.project.levels[0].cell_size * 2)
            a_y := terrain.sample_surface_height(&editor.project, 0, start.x, start.z) + .10
            b_y := terrain.sample_surface_height(&editor.project, 0, end.x, end.z) + .10
            c_x, c_z := end.x + left_x * marker_width, end.z + left_z * marker_width
            d_x, d_z := start.x + left_x * marker_width, start.z + left_z * marker_width
            c_y := terrain.sample_surface_height(&editor.project, 0, c_x, c_z) + .10
            d_y := terrain.sample_surface_height(&editor.project, 0, d_x, d_z) + .10
            world_quad(
                {start.x, a_y, start.z},
                {end.x, b_y, end.z},
                {c_x, c_y, c_z},
                {d_x, d_y, d_z},
                {82, 207, 198, 180},
            )
            continue
        }
        preview := curve_segment_structure(editor, editor.curve_points[index], editor.curve_points[index + 1])
        preview.color = {168, 239, 220, 255}
        world_formation(preview)
        world_structure_frame(preview, preview.base_y + .04, {190, 255, 229, 255})
    }
}
