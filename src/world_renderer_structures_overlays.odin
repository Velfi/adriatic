package main
import "core:math"
import "core:slice"

import architecture "../packages/architecture"
import dio "../packages/dio"
import fountains "../packages/fountains"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import canvas2d "zelda_engine:canvas2d"

world_settlement_gardens :: proc(editor: ^Editor) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "world_settlement_gardens")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    if editor == nil || !editor.settlement_plan.valid do return
    garden_count := editor.settlement_plan.garden_count
    if len(world_renderer.settlement_fountain_geometry_cache) < garden_count {
        resize(&world_renderer.settlement_fountain_geometry_cache, garden_count)
    }
    for plot, plot_index in editor.settlement_plan.gardens[:garden_count] {
        if plot.site_index < 0 || plot.site_index >= editor.settlement_plan.site_count do continue
        site := editor.settlement_plan.sites[plot.site_index]
        structure := site.structure
        seed := plot.seed
        is_park := plot.style == .Park
        has_fountain := is_park && site.fountain_enabled
        is_kitchen := plot.style == .Kitchen
        is_wild := plot.style == .Wild

        count := is_park ? (has_fountain ? 12 : 7) : (is_kitchen ? 7 : (is_wild ? 6 : 4))
        radius_x := max(plot.width * .40, f32(1.4))
        radius_z := max(plot.depth * .38, f32(1.2))
        if is_park {
            world_settlement_park_edge(editor, plot)
        }
        if has_fountain {
            fountain_seed := structure.seed ~ editor.settlement_plan.request.seed ~ 0xF017A17
            fountain_config := fountains.Config {
                radius     = site.fountain_radius,
                style      = site.fountain_style,
                jet_count  = site.fountain_jet_count,
                jet_height = site.fountain_jet_height,
            }
            fountain := fountains.generate(fountain_seed, fountain_config)
            fountain_y := terrain.sample_surface_height(&editor.project, 0, structure.center_x, structure.center_z)
            fountain_origin := third_person.Vec3{structure.center_x, fountain_y, structure.center_z}
            cache := &world_renderer.settlement_fountain_geometry_cache[plot_index]
            cache_matches :=
                cache.valid &&
                cache.structure_id == structure.id &&
                cache.seed == fountain_seed &&
                cache.radius == fountain_config.radius &&
                cache.style == fountain_config.style &&
                cache.jet_count == fountain_config.jet_count &&
                cache.jet_height == fountain_config.jet_height &&
                cache.origin == fountain_origin &&
                cache.rotation == structure.rotation &&
                cache.terrain_revision == editor.terrain_revision
            if cache_matches {
                append(&world_renderer.vertices, ..cache.vertices[:])
            } else {
                first_vertex := len(world_renderer.vertices)
                world_fountain_structure(&fountain, fountain_origin, structure.rotation)
                clear(&cache.vertices)
                append(&cache.vertices, ..world_renderer.vertices[first_vertex:])
                cache.valid = true
                cache.structure_id = structure.id
                cache.seed = fountain_seed
                cache.radius = fountain_config.radius
                cache.style = fountain_config.style
                cache.jet_count = fountain_config.jet_count
                cache.jet_height = fountain_config.jet_height
                cache.origin = fountain_origin
                cache.rotation = structure.rotation
                cache.terrain_revision = editor.terrain_revision
            }
            world_fountain_effects(&fountain, fountain_origin, structure.rotation)
            radius_x = max(radius_x, site.fountain_radius + 2.3)
            radius_z = max(radius_z, site.fountain_radius + 2.3)
        }
        for plant_index in 0 ..< count {
            mixed := garden_hash(seed ~ u32(plant_index + 1) * u32(0x85ebca6b))
            along := (f32((mixed >> 8) & 255) / 255 - .5) * radius_x * 2
            local_z := (f32(mixed & 255) / 255 - .5) * radius_z * 2
            if is_park {
                angle := f32(plant_index) / f32(count) * math.PI * 2
                along = math.cos(angle) * radius_x
                local_z = math.sin(angle) * radius_z
            } else if is_kitchen {
                // Loose rows retain the legibility of a tended kitchen garden
                // without turning it into an exact procedural grid.
                row := plant_index % 2
                station := plant_index / 2
                along = (f32(station) - f32((count - 1) / 4)) * min(radius_x * .62, f32(1.35))
                local_z = (f32(row) - .5) * radius_z * 1.15
                along += (f32((mixed >> 16) & 31) / 31 - .5) * .28
            }
            x, z := world_rotate_xz(plot.center[0], plot.center[1], along, local_z, plot.rotation)
            clearance := is_park ? f32(1.4) : f32(1.8)
            // Collision clearance alone does not establish ownership: a clear
            // sample behind a house can lie beyond its parcel on an access
            // path. Keep every garden anchor (and therefore every woody trunk)
            // inset inside the site's actual plot.
            if !settlement_garden_point_in_plot(site, x, z, clearance * .25) do continue
            // The park's reserved foliage footprint is itself a project
            // structure, so only household gardens use the generic collision
            // query; park plants intentionally live inside that reservation.
            if !is_park && !architecture.city_accent_site_clear(&editor.project, x, z, clearance, .4) do continue
            base_y := terrain.sample_surface_height(&editor.project, 0, x, z)
            if !world_sphere_in_view(editor, {x, base_y + 3, z}, 5, 2) do continue
            plant_seed := mixed ~ u32(0x504c414e)
            species, plant_scale, woody := settlement_garden_woody_species(
                editor.settlement_plan.request.region,
                plot.style,
                plant_index,
                mixed,
            )
            if woody {
                _ = world_generated_plant(
                    species,
                    u64(plant_seed) ~ u64(seed) << 32,
                    {x, base_y, z},
                    plant_scale * (.9 + f32((mixed >> 24) & 31) / 155),
                    plot.rotation + f32(mixed & 255) / 255 * math.PI * 2,
                    .Free_Standing,
                    nil,
                    .Medium,
                    0,
                    .72 + f32((mixed >> 8) & 31) / 100,
                    true,
                )
            } else {
                palette := [4]canvas2d.Color {
                    {72, 119, 57, 255},
                    {103, 137, 65, 255},
                    {185, 91, 105, 255},
                    {216, 178, 74, 255},
                }
                color := palette[int((mixed >> 16) & 3)]
                height := .45 + f32((mixed >> 24) & 255) / 255 * .48
                world_grass_card({x, base_y + height * .5, z}, .52 + height * .24, height, int(mixed % 16), color)
            }
        }
    }
}

world_structure_selection_box_overlay :: proc(editor: ^Editor) {
    if editor == nil || !editor.structure_selection_box_active do return

    x0 := min(editor.structure_selection_box_start_x, editor.structure_selection_box_end_x)
    x1 := max(editor.structure_selection_box_start_x, editor.structure_selection_box_end_x)
    z0 := min(editor.structure_selection_box_start_z, editor.structure_selection_box_end_z)
    z1 := max(editor.structure_selection_box_start_z, editor.structure_selection_box_end_z)
    lift := f32(.16)
    a := third_person.Vec3{x0, terrain.sample_surface_height(&editor.project, 0, x0, z0) + lift, z0}
    b := third_person.Vec3{x1, terrain.sample_surface_height(&editor.project, 0, x1, z0) + lift, z0}
    c := third_person.Vec3{x1, terrain.sample_surface_height(&editor.project, 0, x1, z1) + lift, z1}
    d := third_person.Vec3{x0, terrain.sample_surface_height(&editor.project, 0, x0, z1) + lift, z1}

    world_quad(a, b, c, d, {244, 226, 122, 42})
    extent := max(x1 - x0, z1 - z0)
    thickness := clamp(extent * .008, f32(.10), f32(.28))
    border := canvas2d.Color{255, 239, 145, 255}
    world_box_between(a, b, {0, 1, 0}, thickness, thickness, border)
    world_box_between(b, c, {0, 1, 0}, thickness, thickness, border)
    world_box_between(c, d, {0, 1, 0}, thickness, thickness, border)
    world_box_between(d, a, {0, 1, 0}, thickness, thickness, border)
}

world_structure_selection_overlay :: proc(editor: ^Editor) {
    bounds, ok := structure_selection_bounds(editor)
    if !ok do return
    color := canvas2d.Color{244, 226, 122, 255}
    minimum := third_person.Vec3{bounds.minimum_x, bounds.minimum_y, bounds.minimum_z}
    maximum := third_person.Vec3{bounds.maximum_x, bounds.maximum_y, bounds.maximum_z}
    corners := [8]third_person.Vec3{
        {minimum.x, minimum.y, minimum.z}, {maximum.x, minimum.y, minimum.z},
        {maximum.x, minimum.y, maximum.z}, {minimum.x, minimum.y, maximum.z},
        {minimum.x, maximum.y, minimum.z}, {maximum.x, maximum.y, minimum.z},
        {maximum.x, maximum.y, maximum.z}, {minimum.x, maximum.y, maximum.z},
    }
    extent := max(maximum.x - minimum.x, maximum.z - minimum.z)
    thickness := clamp(extent * .006, f32(.08), f32(.32))
    edges := [12][2]int{
        {0, 1}, {1, 2}, {2, 3}, {3, 0},
        {4, 5}, {5, 6}, {6, 7}, {7, 4},
        {0, 4}, {1, 5}, {2, 6}, {3, 7},
    }
    for edge in edges {
        world_box_between(corners[edge[0]], corners[edge[1]], {0, 1, 0}, thickness, thickness, color)
    }

    center := third_person.Vec3{(minimum.x + maximum.x) * .5, minimum.y + thickness * 2, (minimum.z + maximum.z) * .5}
    size := structure_move_gizmo_size(editor, bounds)
    shaft_radius := size * .045
    x_color := editor.structure_move_axis == 1 ? canvas2d.Color{255, 142, 126, 255} : canvas2d.Color{224, 80, 72, 255}
    z_color := editor.structure_move_axis == 2 ? canvas2d.Color{126, 176, 255, 255} : canvas2d.Color{76, 132, 224, 255}
    world_box(center + third_person.Vec3{size * .5, 0, 0}, {size, shaft_radius, shaft_radius}, x_color)
    world_box(center + third_person.Vec3{0, 0, size * .5}, {shaft_radius, shaft_radius, size}, z_color)
    sdf_obstacle_gizmo_arrow(center, .X, size, x_color)
    sdf_obstacle_gizmo_arrow(center, .Z, size, z_color)
    world_box(center, {size * .18, size * .10, size * .18}, color)
}

world_structures :: proc(editor: ^Editor) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "world_structures")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    if editor == nil do return
    world_spatial_sync_structures(editor)
    sky := atmosphere_sky(editor)
    world_architecture_streets(editor, sky.sun_direction, sky.weather.cloud_cover)
    hovered_index := -1
    if editor.tool == .Structure &&
       !editor.road_mode &&
       editor.cursor_hit &&
       !editor.structure_placing &&
       !editor.structure_moving {
        hovered_index = terrain.structure_index_at(&editor.project, editor.cursor_world_x, editor.cursor_world_z)
    }
    // Cull before ordering. The ordering only prioritizes visible geometry
    // when the bounded vertex streams fill; sorting every project structure
    // made any camera translation trigger unnecessary global work.
    focal_length := editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : f32(1.35)
    view_camera := perspective_camera(editor.camera_pose, focal_length)
    screen_width := max(canvas2d.GetScreenWidth(), 1)
    screen_height := max(canvas2d.GetScreenHeight(), 1)
    aspect := f32(screen_width) / f32(screen_height)
    near_plane := world_camera_near_clip(editor)
    stats := &world_renderer.static_visibility
    stats^ = {}
    selected_index := !editor.in_map ? editor.structure_selected : -1
    clear(&world_renderer.structure_visibility_order)
    for structure, index in editor.project.structures[:editor.project.structure_count] {
        stats.candidates += 1
        force_visible := structure_index_selected(editor, index) || index == hovered_index
        center, radius := structure_visibility_sphere(structure)
        if !force_visible &&
           !static_sphere_in_frustum(view_camera, center, radius, aspect, near_plane, WORLD_FAR_CLIP) {
            world_renderer.static_visibility_classification[index] = .Frustum_Culled
            stats.frustum_culled += 1
            continue
        }
        if force_visible {
            world_renderer.static_visibility_classification[index] = .Force_Visible
            stats.force_visible += 1
        } else {
            world_renderer.static_visibility_classification[index] = .Visible
        }
        dx, dz := structure.center_x - view_camera.position.x, structure.center_z - view_camera.position.z
        distance_squared := dx * dx + dz * dz
        if force_visible do distance_squared = -1
        append(
            &world_renderer.structure_visibility_order,
            Structure_Visibility_Order{index = index, distance_squared = distance_squared},
        )
    }
    slice.sort_by(world_renderer.structure_visibility_order[:], structure_visibility_order_less)
    world_architecture_alley_overlap_plan_sync(&editor.architecture_city_plan)
    for ordered in world_renderer.structure_visibility_order {
        index := ordered.index
        structure := editor.project.structures[index]
        if settlement_cemetery_structure_is_reservation(structure) do continue
        force_visible := structure_index_selected(editor, index) || index == hovered_index
        if editor.architecture_painting &&
           structure.kind == .Architecture &&
           architecture.city_bounds_contains(
               architecture.city_bounds_expand(editor.architecture_dirty_bounds, 48),
               structure.center_x,
               structure.center_z,
           ) {
            continue
        }
        if !force_visible &&
           structure.kind == .Foliage &&
           world_architecture_structure_overlaps_alley_cached(&editor.architecture_city_plan, structure, index) {
            world_renderer.static_visibility_classification[index] = .Empty
            stats.empty += 1
            continue
        }
        force_near := structure_index_selected(editor, index) && !editor.in_map
        world_before := len(world_renderer.vertices)
        foliage_vertices_before := len(world_renderer.foliage_vertices)
        bougainvillea_vertices_before := len(world_renderer.bougainvillea_vertices)
        retained_static_indices := 0
        is_park_reservation :=
            structure.kind == .Foliage &&
            settlement_structure_is_park_reservation(&editor.settlement_plan, structure.id)
        is_decorative_grove :=
            structure.kind == .Foliage &&
            settlement_structure_is_decorative_grove(&editor.settlement_plan, structure.id)
        if is_decorative_grove {
            world_settlement_decorative_grove(editor, structure)
        } else if structure.kind == .Foliage && !is_park_reservation {
            world_foliage_formation_cached(structure, index, force_near)
            world_renderer.structure_lod_counts[int(world_renderer.foliage_geometry_cache[index].lod)] += 1
        } else if structure.kind != .Foliage {
            world_static_formation_cached(structure, index, &editor.project, force_near)
            world_renderer.structure_lod_counts[int(world_renderer.static_geometry_cache[index].lod)] += 1
            retained_static_indices = len(world_renderer.static_geometry_cache[index].world_indices)
        }
        world_climbing_leaves_for_structure(editor, structure, index)
        if structure.kind == .Foliage {
            world_register_shadow_caster(world_before)
        }
        world_renderer.structure_lod_world_vertices +=
            len(world_renderer.vertices) - world_before + retained_static_indices
        world_renderer.structure_lod_foliage_vertices +=
            len(world_renderer.foliage_vertices) -
            foliage_vertices_before +
            len(world_renderer.bougainvillea_vertices) -
            bougainvillea_vertices_before
        world_added := len(world_renderer.vertices) - world_before + retained_static_indices
        foliage_added := len(world_renderer.foliage_vertices) - foliage_vertices_before
        bougainvillea_added := len(world_renderer.bougainvillea_vertices) - bougainvillea_vertices_before
        if world_added > 0 || foliage_added > 0 || bougainvillea_added > 0 {
            stats.opaque_cost += u32(max(world_added, 0))
            stats.foliage_cost += u32(max(foliage_added, 0))
            stats.bougainvillea_cost += u32(max(bougainvillea_added, 0))
        } else {
            world_renderer.static_visibility_classification[index] = .Empty
            stats.empty += 1
        }
        if index == hovered_index && !structure_index_selected(editor, index) && !editor.in_map {
            world_structure_frame(structure, structure.base_y + structure.height + .02, {168, 239, 220, 255})
        }
    }
    if editor.selection_tool_active && editor.structure_selected >= 0 && !editor.in_map && !editor.road_mode {
        world_structure_selection_overlay(editor)
    }
    if editor.selection_tool_active && editor.structure_selection_box_active && !editor.in_map && !editor.road_mode {
        world_structure_selection_box_overlay(editor)
    }
    if stats.opaque_cost > 0 do stats.emitted_draws += 1
    if stats.foliage_cost > 0 do stats.emitted_draws += 1
    if stats.bougainvillea_cost > 0 do stats.emitted_draws += 1
    if editor.structure_placing {
        world_structure_preview_cluster(editor)
    }
    world_curve_preview(editor)
    world_settlement_town_building_skirts(editor)
    world_settlement_town_civic_forecourts(editor, &editor.architecture_city_plan)
    world_architecture_alleys(editor, &editor.architecture_city_plan)
    world_architecture_lamps(editor, &editor.architecture_city_plan)
    if editor.architecture_paint_mode && !editor.airport_stamp_mode {
        world_architecture_alleys(editor, &editor.architecture_preview_plan, true)
        for candidate in editor.architecture_preview_plan.structures[:editor.architecture_preview_plan.count] {
            preview := candidate
            preview.color = editor.building_generator_preview_valid ? [4]u8{168, 239, 220, 210} : [4]u8{229, 105, 90, 190}
            world_formation(preview, &editor.project)
            frame_color := editor.building_generator_preview_valid ? canvas2d.Color{190, 255, 229, 210} : canvas2d.Color{255, 145, 126, 220}
            world_structure_frame(preview, preview.base_y + .05, frame_color)
        }
    }
    if editor.greek_placement_mode && editor.ruin_stamp_preview_valid {
        world_settlement_ruin(editor.ruin_stamp_preview, .Near)
        world_structure_frame(
            editor.ruin_stamp_preview,
            editor.ruin_stamp_preview.base_y + editor.ruin_stamp_preview.height,
            {168, 239, 220, 210},
        )
    }
}

world_overlay_chunk_bounds_sync :: proc(editor: ^Editor) {
    if editor == nil do return
    expected_count := OVERLAY_CHUNKS_PER_AXIS * OVERLAY_CHUNKS_PER_AXIS
    if world_renderer.overlay_chunk_terrain_revision == editor.terrain_revision &&
       len(world_renderer.overlay_chunk_bounds) == expected_count {
        return
    }
    clear(&world_renderer.overlay_chunk_bounds)
    reserve(&world_renderer.overlay_chunk_bounds, expected_count)
    cell := terrain.BASE_CELL_SIZE
    half := f32(terrain.RING_RESOLUTION - 1) * .5
    cell_count := terrain.RING_RESOLUTION - 1
    for chunk_z in 0 ..< OVERLAY_CHUNKS_PER_AXIS {
        min_cell_z := chunk_z * OVERLAY_CHUNK_CELLS
        max_cell_z := min(min_cell_z + OVERLAY_CHUNK_CELLS, cell_count)
        z0, z1 := (f32(min_cell_z) - half) * cell, (f32(max_cell_z) - half) * cell
        for chunk_x in 0 ..< OVERLAY_CHUNKS_PER_AXIS {
            min_cell_x := chunk_x * OVERLAY_CHUNK_CELLS
            max_cell_x := min(min_cell_x + OVERLAY_CHUNK_CELLS, cell_count)
            x0, x1 := (f32(min_cell_x) - half) * cell, (f32(max_cell_x) - half) * cell
            minimum_y, maximum_y := f32(1e30), f32(-1e30)
            for sample_z in min_cell_z ..= max_cell_z {
                world_z := (f32(sample_z) - half) * cell
                for sample_x in min_cell_x ..= max_cell_x {
                    world_x := (f32(sample_x) - half) * cell
                    sample_y := terrain.sample_surface_height(&editor.project, 0, world_x, world_z)
                    minimum_y, maximum_y = min(minimum_y, sample_y), max(maximum_y, sample_y)
                }
            }
            center := third_person.Vec3{(x0 + x1) * .5, (minimum_y + maximum_y) * .5, (z0 + z1) * .5}
            half_x, half_y, half_z := (x1 - x0) * .5, (maximum_y - minimum_y) * .5, (z1 - z0) * .5
            radius := f32(math.sqrt(f64(half_x * half_x + half_y * half_y + half_z * half_z))) + .25
            append(&world_renderer.overlay_chunk_bounds, Overlay_Chunk_Bounds{center, radius})
        }
    }
    world_renderer.overlay_chunk_terrain_revision = editor.terrain_revision
}

world_city_density_overlay :: proc(editor: ^Editor) {
    if editor == nil || editor.in_map || !editor.architecture_paint_mode do return
    field := &editor.project.city_density
    if editor.architecture_painting do field = &editor.architecture_density_preview
    cell := terrain.BASE_CELL_SIZE
    half := f32(terrain.RING_RESOLUTION - 1) * .5
    camera := perspective_camera(editor.camera_pose)
    width, height := max(canvas2d.GetScreenWidth(), 1), max(canvas2d.GetScreenHeight(), 1)
    aspect := f32(width) / f32(height)
    near_plane := world_camera_near_clip(editor)
    world_overlay_chunk_bounds_sync(editor)
    cell_count := terrain.RING_RESOLUTION - 1
    for chunk_z in 0 ..< OVERLAY_CHUNKS_PER_AXIS {
        for chunk_x in 0 ..< OVERLAY_CHUNKS_PER_AXIS {
            bounds := world_renderer.overlay_chunk_bounds[chunk_z * OVERLAY_CHUNKS_PER_AXIS + chunk_x]
            if !static_sphere_in_frustum(camera, bounds.center, bounds.radius, aspect, near_plane, WORLD_FAR_CLIP) {
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
                    lift := f32(.115)
                    a := third_person.Vec3{x0, terrain.sample_surface_height(&editor.project, 0, x0, z0) + lift, z0}
                    b := third_person.Vec3{x1, terrain.sample_surface_height(&editor.project, 0, x1, z0) + lift, z0}
                    c := third_person.Vec3{x1, terrain.sample_surface_height(&editor.project, 0, x1, z1) + lift, z1}
                    d := third_person.Vec3{x0, terrain.sample_surface_height(&editor.project, 0, x0, z1) + lift, z1}
                    alpha := u8(28 + density * 112)
                    world_quad(a, b, c, d, {22, 27, 31, alpha})
                }
            }
        }
    }
}

world_climbing_leaf_opening_badness :: proc(structure: terrain.Structure, local_x, local_y: f32) -> f32 {
    if structure.kind != .Architecture do return 0

    badness := f32(0)
    identity := architecture.architecture_resolve_legacy_identity(structure)
    if identity.archetype == .Mixed_Use_Dwelling {
        // Full-glass shops need a continuous clear display field. Leave a
        // masonry corridor at each outer pier so the plant can climb beside
        // the storefront and soften the canopy edge without veiling merchandise.
        glass_x_score := clamp(1 - max(math.abs(local_x) - structure.width * .37, f32(0)) / 1.1, 0, 1)
        glass_y_score := clamp(1 - max(local_y - 4.35, f32(0)) / .75, 0, 1)
        if local_y >= 0 do badness = max(badness, glass_x_score * glass_y_score)
        sign_half_width := min(structure.width * .20, f32(3.0))
        sign_x_score := clamp(1 - max(math.abs(local_x) - sign_half_width, f32(0)) / .65, 0, 1)
        sign_y_score := clamp(1 - math.abs(local_y - 6.05) / .72, 0, 1)
        badness = max(badness, sign_x_score * sign_y_score)
    }
    landmark := structure.height > 60
    if !landmark {
        // Include the lobe footprint in the exclusion margin, not just its
        // center, so a broad cluster cannot clip an opening from the side.
        door_x_score := clamp(1 - math.abs(local_x) / (structure.width * .24), 0, 1)
        door_y_score := clamp(1 - math.abs(local_y - structure.height * .14) / (structure.height * .25), 0, 1)
        badness = max(badness, door_x_score * door_y_score)
    }

    rows := architecture.facade_floor_count(structure.height)
    columns := architecture.facade_column_count(structure.width)
    window_height := architecture.facade_window_height(structure.height)
    window_width := architecture.facade_window_width(structure.width)
    for row in 0 ..< rows {
        window_y := architecture.facade_window_row_y(structure.height, row)
        window_y_score := clamp(1 - math.abs(local_y - window_y) / (window_height * .75 + .55), 0, 1)
        // Protect the full visual window band, not only the dark rectangle.
        // At façade distance a lobe beside a frame still reads as covering
        // the opening, so growth is routed into the masonry between floors.
        badness = max(badness, window_y_score * .74)
        for column in 0 ..< columns {
            window_x := architecture.facade_window_column_x(structure.width, column)
            window_x_score := clamp(1 - math.abs(local_x - window_x) / (window_width * .5 + .75), 0, 1)
            badness = max(badness, window_x_score * window_y_score)
        }
    }
    return clamp(badness, 0, 1)
}

world_climbing_leaf_stem_opening_badness :: proc(structure: terrain.Structure, local_x, local_y: f32) -> f32 {
    if structure.kind != .Architecture do return 0

    // Woody leaders only need to avoid the actual opening rectangles. The
    // broader floor-band exclusion used by foliage masses would make every
    // stem disappear between floors even when there is clear masonry beside
    // the windows.
    badness := f32(0)
    identity := architecture.architecture_resolve_legacy_identity(structure)
    if identity.archetype == .Mixed_Use_Dwelling {
        glass_x_score := clamp(1 - max(math.abs(local_x) - structure.width * .38, f32(0)) / .55, 0, 1)
        glass_y_score := clamp(1 - max(local_y - 4.25, f32(0)) / .45, 0, 1)
        if local_y >= 0 do badness = max(badness, glass_x_score * glass_y_score)
        sign_half_width := min(structure.width * .20, f32(3.0))
        sign_x_score := clamp(1 - max(math.abs(local_x) - sign_half_width, f32(0)) / .35, 0, 1)
        sign_y_score := clamp(1 - math.abs(local_y - 6.05) / .48, 0, 1)
        badness = max(badness, sign_x_score * sign_y_score)
    }
    landmark := structure.height > 60
    if !landmark {
        door_x_score := clamp(1 - math.abs(local_x) / (structure.width * .20), 0, 1)
        door_y_score := clamp(1 - math.abs(local_y - structure.height * .14) / (structure.height * .23), 0, 1)
        badness = max(badness, door_x_score * door_y_score)
    }

    rows := architecture.facade_floor_count(structure.height)
    columns := architecture.facade_column_count(structure.width)
    window_height := architecture.facade_window_height(structure.height)
    window_width := architecture.facade_window_width(structure.width)
    for row in 0 ..< rows {
        window_y := architecture.facade_window_row_y(structure.height, row)
        window_y_score := clamp(1 - math.abs(local_y - window_y) / (window_height * .5 + .30), 0, 1)
        for column in 0 ..< columns {
            window_x := architecture.facade_window_column_x(structure.width, column)
            window_x_score := clamp(1 - math.abs(local_x - window_x) / (window_width * .5 + .35), 0, 1)
            badness = max(badness, window_x_score * window_y_score)
        }
    }
    return clamp(badness, 0, 1)
}

world_climbing_leaf_route_x :: proc(
    structure: terrain.Structure,
    preferred_x, previous_x, previous_y, previous_delta, local_y: f32,
) -> f32 {
    if structure.kind != .Architecture do return preferred_x
    offsets := [13]f32{0, -.055, .055, -.11, .11, -.17, .17, -.23, .23, -.30, .30, -.37, .37}
    best_x := preferred_x
    best_score := f32(1.0e20)
    for offset in offsets {
        candidate := clamp(preferred_x + offset * structure.width, -structure.width * .45, structure.width * .45)
        opening := f32(0)
        // Score the entire proposed segment, not just its destination. A
        // horizontal leader can have clear endpoints yet pass directly
        // through a window between them.
        for route_sample in 0 ..= 4 {
            sample_t := f32(route_sample) / 4
            sample_x := previous_x + (candidate - previous_x) * sample_t
            sample_y := previous_y + (local_y - previous_y) * sample_t
            opening = max(opening, world_climbing_leaf_stem_opening_badness(structure, sample_x, sample_y))
        }
        continuity := math.abs(candidate - previous_x) / max(structure.width, f32(1))
        curvature := math.abs((candidate - previous_x) - previous_delta) / max(structure.width, f32(1))
        departure := math.abs(candidate - preferred_x) / max(structure.width, f32(1))
        score := opening * 4.5 + continuity * 1.40 + curvature * .82 + departure * .18
        if score < best_score {
            best_x, best_score = candidate, score
        }
    }
    return best_x
}

world_climbing_leaf_segment_detour_x :: proc(
    structure: terrain.Structure,
    start_x, start_y, end_x, end_y: f32,
) -> f32 {
    if structure.kind != .Architecture do return (start_x + end_x) * .5
    middle_y := (start_y + end_y) * .5
    preferred_x := (start_x + end_x) * .5
    best_x := preferred_x
    best_score := f32(1.0e20)
    // Search the full usable façade width. The ordinary point router favors
    // smooth local motion; this fallback instead prioritizes a clear masonry
    // corridor so a difficult opening can never sever the woody leader.
    for candidate_index in 0 ..= 20 {
        candidate_x := (-.45 + f32(candidate_index) / 20 * .90) * structure.width
        opening := f32(0)
        for route_sample in 0 ..= 5 {
            sample_t := f32(route_sample) / 5
            first_x := start_x + (candidate_x - start_x) * sample_t
            first_y := start_y + (middle_y - start_y) * sample_t
            second_x := candidate_x + (end_x - candidate_x) * sample_t
            second_y := middle_y + (end_y - middle_y) * sample_t
            opening = max(
                opening,
                max(
                    world_climbing_leaf_stem_opening_badness(structure, first_x, first_y),
                    world_climbing_leaf_stem_opening_badness(structure, second_x, second_y),
                ),
            )
        }
        departure := math.abs(candidate_x - preferred_x) / max(structure.width, f32(1))
        score := opening * 8 + departure * .18
        if score < best_score {
            best_x, best_score = candidate_x, score
        }
    }
    return best_x
}
