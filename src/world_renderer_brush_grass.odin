package main
import "core:math"

import circulation "../packages/circulation"
import dio "../packages/dio"
import terrain "../packages/terrain"
import canvas2d "zelda_engine:canvas2d"

world_plant_stamp_attachment_preview :: proc(editor: ^Editor) {
    if editor == nil ||
       !editor.plant_stamp_target_valid ||
       editor.plant_stamp_target_index < 0 ||
       editor.plant_stamp_target_index >= editor.project.structure_count {
        return
    }
    target := editor.project.structures[editor.plant_stamp_target_index]
    world_structure_frame(target, target.base_y + .08, {121, 244, 181, 255})
    attachment_z := target.depth * .5 + .34
    if target.kind != .Architecture do attachment_z = max(target.width, target.depth) * .48 + .28
    preview_seed := target.seed ~ 0x8f31a6d5
    world_climbing_leaf_vine(
        target,
        0,
        0,
        attachment_z,
        target.height * .72,
        max(editor.climbing_leaf_brush_strength, f32(.35)),
        preview_seed,
        preview_seed,
        true,
    )
}

world_brush :: proc(editor: ^Editor) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "world_brush")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    if editor.selection_tool_active do return
    formation_brush := editor.authoring_tool == .Formations || editor.authoring_tool == .Foliage
    if editor.in_map ||
       editor.road_mode ||
       (editor.tool == .Structure &&
               !editor.architecture_paint_mode &&
               !editor.marina_paint_mode &&
               !editor.farm_paint_mode &&
               !editor.wreck_paint_mode &&
               !editor.climbing_leaf_paint_mode &&
               !formation_brush) {
        return
    }
    if editor.authoring_tool == .Foliage && editor.plant_stamp_mode == .Climbing {
        world_plant_stamp_attachment_preview(editor)
        return
    }
    // Input and rendering must share the same pick. Recasting here can use a
    // later camera pose (or a different focal length), visibly separating the
    // brush preview from both the pointer and the applied stroke.
    if !editor.cursor_hit do return
    x, z := editor.cursor_world_x, editor.cursor_world_z
    color: canvas2d.Color = {230, 244, 218, 76}
    radius, hardness := editor.radius, editor.hardness
    if editor.authoring_tool == .Sculpt {
        settings := editor.terrain_sculpt.settings[int(editor.terrain_sculpt.action)]
        radius = settings.size + settings.feather
        hardness = settings.inner_core
        color = settings.affect_seabed ? canvas2d.Color{105, 205, 214, 92} : canvas2d.Color{244, 214, 122, 88}
    }
    switch editor.tool {
    case .Raise:
        color = {244, 214, 122, 88}
    case .Smooth:
        color = {176, 225, 236, 88}
    case .Paint:
        color = {168, 239, 220, 88}
    case .Structure:
        color = {90, 102, 112, 86}
        radius = settlement_brush_preset_span(editor.architecture_brush_preset) * .5
        hardness = editor.architecture_brush_hardness
        if editor.marina_paint_mode {
            color = editor.marina_preview_valid ? canvas2d.Color{128, 211, 166, 92} : canvas2d.Color{218, 105, 86, 104}
            radius = editor.marina_brush_radius
            hardness = .72
        } else if editor.farm_paint_mode {
            color = editor.farm_preview_valid ? canvas2d.Color{153, 174, 76, 92} : canvas2d.Color{218, 105, 86, 104}
            radius = editor.farm_brush_radius
            hardness = .68
        } else if editor.wreck_paint_mode {
            color = editor.wreck_preview_valid ? canvas2d.Color{92, 137, 151, 92} : canvas2d.Color{218, 105, 86, 104}
            radius = editor.wreck_brush_size * .55
            hardness = .68
        } else if formation_brush {
            color =
                editor.authoring_tool == .Foliage ? canvas2d.Color{105, 176, 92, 96} : canvas2d.Color{172, 126, 84, 96}
            radius = editor.formation_brush_radius
            hardness = editor.formation_brush_hardness
        } else if editor.climbing_leaf_paint_mode {
            color = {72, 164, 88, 96}
            radius = editor.climbing_leaf_brush_radius
            hardness = editor.climbing_leaf_brush_hardness
        }
    }
    if canvas2d.IsMouseButtonDown(.RIGHT) do color = {245, 126, 112, 108}
    if editor.architecture_paint_mode {
        return
    }
    world_brush_disc(editor, x, z, radius, .09, color)
    // A denser inner disc makes the hardness setting legible at the cursor:
    // harder brushes have a larger, more opaque core while the outer disc
    // continues to show the full affected radius.
    inner_radius :=
        editor.authoring_tool == .Sculpt ? editor.terrain_sculpt.settings[int(editor.terrain_sculpt.action)].size * hardness : radius * (.25 + hardness * .65)
    core := color
    core.a = u8(min(int(color.a) + 34, 180))
    world_brush_disc(editor, x, z, inner_radius, .105, core)
    if editor.authoring_tool == .Sculpt &&
       terrain_action_is_spline(editor.terrain_sculpt.action) &&
       editor.terrain_sculpt.session.active {
        path_radius := max(editor.terrain_sculpt.settings[int(editor.terrain_sculpt.action)].size * .5, f32(1))
        for point in editor.terrain_sculpt.session.path[:editor.terrain_sculpt.session.path_count] {
            world_brush_disc(editor, point.x, point.z, path_radius, .115, core)
        }
    }
}

world_ground_grass_has_land :: proc(editor: ^Editor, center_x, center_z, radius: f32) -> bool {
    // Low-flying aircraft can spend entire frames over shallow water, where
    // the terrain height alone still passes the altitude gate below. Probe a
    // coarse disc before walking the dense sub-metre grass grid; if no land is
    // present, none of those candidates can emit geometry.
    SAMPLE_RADIUS :: 2
    spacing := radius / f32(SAMPLE_RADIUS)
    for sample_z in -SAMPLE_RADIUS ..= SAMPLE_RADIUS {
        for sample_x in -SAMPLE_RADIUS ..= SAMPLE_RADIUS {
            if sample_x * sample_x + sample_z * sample_z > SAMPLE_RADIUS * SAMPLE_RADIUS do continue
            x := center_x + f32(sample_x) * spacing
            z := center_z + f32(sample_z) * spacing
            if terrain.sample_surface_height(&editor.project, 0, x, z) > editor.project.sea_level + .35 {
                return true
            }
        }
    }
    return false
}

ground_grass_chunk_release :: proc(key: [2]int) {
    chunk, found := world_renderer.grass_chunk_cache[key]
    if !found do return
    // Keep the fixed-size chunk allocation available for the next streaming
    // miss. The cache is intentionally bounded, so evictions are common while
    // flying and repeatedly allocating the same 28 KiB object is avoidable.
    append(&world_renderer.grass_chunk_pool, chunk)
    delete_key(&world_renderer.grass_chunk_cache, key)
    world_renderer.grass_stream_dirty = true
}

ground_grass_cache_clear :: proc() {
    for _, chunk in world_renderer.grass_chunk_cache do free(chunk)
    clear(&world_renderer.grass_chunk_cache)
    for chunk in world_renderer.grass_chunk_pool do free(chunk)
    clear(&world_renderer.grass_chunk_pool)
    world_renderer.grass_stream_dirty = true
}

ground_grass_cache_invalidate_bounds :: proc(min_x, min_z, max_x, max_z: f32) {
    if world_renderer.grass_chunk_cache == nil do return
    jitter_padding := GROUND_GRASS_SPACING * .5 * .76
    padded_min_x, padded_min_z := min_x - jitter_padding, min_z - jitter_padding
    padded_max_x, padded_max_z := max_x + jitter_padding, max_z + jitter_padding
    stale := make([dynamic][2]int, 0, 16, context.temp_allocator)
    for key, _ in world_renderer.grass_chunk_cache {
        chunk_min_x := f32(key[0]) * GROUND_GRASS_CHUNK_WORLD_SIZE
        chunk_min_z := f32(key[1]) * GROUND_GRASS_CHUNK_WORLD_SIZE
        chunk_max_x := chunk_min_x + GROUND_GRASS_CHUNK_WORLD_SIZE
        chunk_max_z := chunk_min_z + GROUND_GRASS_CHUNK_WORLD_SIZE
        if chunk_max_x < padded_min_x ||
           chunk_min_x > padded_max_x ||
           chunk_max_z < padded_min_z ||
           chunk_min_z > padded_max_z {
            continue
        }
        append(&stale, key)
    }
    for key in stale do ground_grass_chunk_release(key)
}

ground_grass_cache_make_room :: proc() {
    CACHE_OVERHEAD_RESERVE :: 256 * 1024
    maximum_chunks := max((GROUND_GRASS_CACHE_BUDGET_BYTES - CACHE_OVERHEAD_RESERVE) / size_of(Ground_Grass_Chunk), 1)
    if len(world_renderer.grass_chunk_cache) < maximum_chunks do return
    oldest_key: [2]int
    oldest_tick := ~u64(0)
    found := false
    for key, chunk in world_renderer.grass_chunk_cache {
        if chunk.last_used < oldest_tick {
            oldest_key = key
            oldest_tick = chunk.last_used
            found = true
        }
    }
    if found do ground_grass_chunk_release(oldest_key)
}

coastal_grass_card_density :: #force_inline proc(material, x, z: f32) -> f32 {
    stabilization := clamp(material + 1, f32(0), f32(1))
    // Marram establishes in colonies rather than filling every eligible
    // square. Two crossed low-frequency fields leave readable sand windows
    // between tufts and avoid a uniform green carpet over coastal relief.
    crossed := f32(math.sin(f64(x * .067 + z * .021 + 1.7))) * f32(math.sin(f64(x * -.019 + z * .083 - .6)))
    broad := f32(math.sin(f64(x * .026 - z * .014 + 2.4)))
    patch := clamp(.42 + crossed * .34 + broad * .16, f32(.10), f32(.88))
    // A fourth-power response keeps partly active sand genuinely sparse while
    // allowing mature shoulders to retain recognizable colonies.
    return stabilization * stabilization * stabilization * stabilization * patch * .72
}

ground_grass_chunk_build :: proc(
    editor: ^Editor,
    key: [2]int,
    building_footprints: []Architecture_Grass_Footprint,
    circulation_plan: ^circulation.Plan,
    cell_budget: int = GROUND_GRASS_CHUNK_CELLS * GROUND_GRASS_CHUNK_CELLS,
) -> ^Ground_Grass_Chunk {
    chunk, found := world_renderer.grass_chunk_cache[key]
    if !found {
        ground_grass_cache_make_room()
        if len(world_renderer.grass_chunk_pool) > 0 {
            chunk = pop(&world_renderer.grass_chunk_pool)
            chunk^ = {}
        } else {
            chunk = new(Ground_Grass_Chunk)
        }
        world_renderer.grass_chunk_cache[key] = chunk
        world_renderer.grass_candidate_misses += 1
    }
    chunk.last_used = world_renderer.grass_chunk_clock
    previous_built_cells := chunk.built_cells
    base_grid_x := key[0] * GROUND_GRASS_CHUNK_CELLS
    base_grid_z := key[1] * GROUND_GRASS_CHUNK_CELLS
    total_cells := GROUND_GRASS_CHUNK_CELLS * GROUND_GRASS_CHUNK_CELLS
    end_cell := min(chunk.built_cells + max(cell_budget, 0), total_cells)
    for linear_cell in chunk.built_cells ..< end_cell {
        local_x := linear_cell % GROUND_GRASS_CHUNK_CELLS
        local_z := linear_cell / GROUND_GRASS_CHUNK_CELLS
        world_grid_x := base_grid_x + local_x
        world_grid_z := base_grid_z + local_z
        seed_index := world_grid_x * 73856093 + world_grid_z * 19349663
        jitter_x := (wind_streak_hash(seed_index, 1) - .5) * GROUND_GRASS_SPACING * .76
        jitter_z := (wind_streak_hash(seed_index, 2) - .5) * GROUND_GRASS_SPACING * .76
        x := f32(world_grid_x) * GROUND_GRASS_SPACING + jitter_x
        z := f32(world_grid_z) * GROUND_GRASS_SPACING + jitter_z
        height_at := terrain.sample_surface_height(&editor.project, 0, x, z)
        if farmland_excludes_ground_grass(editor, x, z) ||
           settlement_patios_contain_point(editor, x, z, .12) ||
           !coastal_grass_renderable_at(editor, x, z, circulation_plan) {
            continue
        }
        architecture_height_scale := world_architecture_grass_height_scale(building_footprints, x, z)
        if architecture_height_scale <= 0 do continue
        terrain_material := terrain.sample_material(&editor.project, 0, x, z)
        sand_stabilization := f32(1)
        inland_colony_strength := f32(1)
        if terrain_material < 0 {
            // Negative terrain material is the coastal sand/stabilization
            // mask. Keep active sand and wet shore bare while allowing the
            // deterministic card field to fill back in across stabilized
            // dry beach shoulders.
            sand_stabilization = clamp(terrain_material + 1, f32(0), f32(1))
            density := coastal_grass_card_density(terrain_material, x, z)
            if wind_streak_hash(seed_index, 11) > density do continue
        } else {
            // Inland grass also grows in colonies rather than occupying every
            // eligible half-metre cell. Correlated broad fields expose soft
            // terrain windows and prevent the near field from becoming a
            // uniformly tiled carpet, while a hashed roll keeps patch edges
            // irregular and stable under camera movement.
            crossed := f32(math.sin(f64(x * .052 + z * .019 + .8))) * f32(math.sin(f64(x * -.017 + z * .061 - 1.4)))
            broad := f32(math.sin(f64(x * .021 - z * .013 + 2.7)))
            colony_density := clamp(.56 + crossed * .27 + broad * .16, f32(.22), f32(.94))
            if wind_streak_hash(seed_index, 15) > colony_density do continue
            colony_t := clamp((colony_density - .22) / (.94 - .22), f32(0), f32(1))
            inland_colony_strength = colony_t * colony_t * (3 - 2 * colony_t)
        }
        ground_color, cliff_weight, _ := clipmap_vertex_color(editor, 0, x, z, height_at, 0)
        if cliff_weight > .2 do continue
        variation := wind_streak_hash(seed_index, 4)
        elevation := max(height_at - editor.project.sea_level, f32(0))
        altitude := clamp((elevation - 2.4) / 28, f32(0), f32(1))
        // Lowland grass should sit beneath the foliage palette, not glow as
        // a cyan carpet. Warm, restrained woodland greens preserve blade
        // contrast while matching Adriatic olive and dry-meadow ground.
        low := canvas2d.Color{58, 100, 60, 255}
        middle := canvas2d.Color{83, 122, 61, 255}
        high := canvas2d.Color{136, 132, 67, 255}
        color := color_lerp(middle, high, (altitude - .52) / .48)
        if altitude < .52 do color = color_lerp(low, middle, altitude / .52)
        temperature_field :=
            f32(math.sin(f64(x * .018 + z * .007))) + f32(math.sin(f64(x * -.006 + z * .014 + 2.1))) * .55
        if temperature_field < -.55 {
            color = color_lerp(color, {56, 94, 67, 255}, .24)
        } else if temperature_field > .58 {
            color = color_lerp(color, {161, 153, 74, 255}, .27)
        } else {
            color = color_lerp(color, {103, 121, 75, 255}, .16)
        }
        if terrain_material < 0 {
            // Sparse marram and dry coastal grasses are shorter, less
            // saturated, and warmer than the lush inland card field. A muted
            // straw-olive target avoids neon green cards against pale sand
            // while stabilized crests retain some living green.
            sand_dryness := 1 - sand_stabilization
            color = color_lerp(color, {132, 127, 73, 255}, .52 + sand_dryness * .34)
        }
        color = color_lerp(color, {170, 166, 87, 255}, variation * .08)
        grass_value := f32(color.r) * .2126 + f32(color.g) * .7152 + f32(color.b) * .0722
        ground_value := f32(ground_color.r) * .2126 + f32(ground_color.g) * .7152 + f32(ground_color.b) * .0722
        value_scale := ground_value / max(grass_value, f32(1))
        color.r = u8(clamp(f32(color.r) * value_scale, 0, 255))
        color.g = u8(clamp(f32(color.g) * value_scale, 0, 255))
        color.b = u8(clamp(f32(color.b) * value_scale, 0, 255))
        height_noise := wind_streak_hash(seed_index, 7)
        width_noise := wind_streak_hash(seed_index, 8)
        height := .48 + height_noise * .62
        if height_noise < .12 {
            height *= .62
        } else if height_noise > .90 {
            height *= 1.28
        }
        if terrain_material >= 0 do height *= .70 + inland_colony_strength * .38
        if terrain_material < 0 do height *= .52 + sand_stabilization * .22
        height *= architecture_height_scale
        width := height * (.56 + width_noise * .48)
        flower_density := wildflower_density_at(x, z)
        has_flower :=
            terrain_material >= 0 && flower_density > .18 && wind_streak_hash(seed_index, 12) < flower_density * .34
        flower_height := .32 + wind_streak_hash(seed_index, 13) * .34
        chunk.entries[chunk.count] = {
            grass = {
                center = {x, height_at + height * .5, z},
                size = {width, height},
                tile = u32(abs(seed_index) % 16),
                color = world_color(color),
            },
            ground_color = world_color(ground_color),
            density_roll = wind_streak_hash(seed_index, 3),
            flower_y = height_at +
            flower_height * .5 +
            .12,
            flower_size = {.22 + wind_streak_hash(seed_index, 14) * .18, flower_height},
            flower_tile = u32(abs(seed_index / 11) % 16),
            has_flower = has_flower,
        }
        chunk.count += 1
    }
    chunk.built_cells = end_cell
    if end_cell > previous_built_cells do chunk.stream_emitted = false
    return chunk
}

ground_grass_chunk_get :: proc(key: [2]int) -> ^Ground_Grass_Chunk {
    chunk, found := world_renderer.grass_chunk_cache[key]
    if !found do return nil
    chunk.last_used = world_renderer.grass_chunk_clock
    world_renderer.grass_candidate_hits += 1
    return chunk
}

ground_grass_cache_stream_disc :: proc(
    editor: ^Editor,
    field_x, field_z, radius: f32,
    building_footprints: []Architecture_Grass_Footprint,
    circulation_plan: ^circulation.Plan,
    remaining_cells: ^int,
) {
    STREAMING_CELLS_PER_CHUNK :: 64
    if remaining_cells == nil || remaining_cells^ <= 0 do return
    radius_squared := radius * radius
    center_chunk_x := int(math.floor(f64(field_x / GROUND_GRASS_CHUNK_WORLD_SIZE)))
    center_chunk_z := int(math.floor(f64(field_z / GROUND_GRASS_CHUNK_WORLD_SIZE)))
    chunk_radius := int(math.ceil(f64(radius / GROUND_GRASS_CHUNK_WORLD_SIZE))) + 1
    // Chebyshev rings visit the camera's chunk first, then expand outward.
    // Visible work therefore wins the fixed budget before speculative prefetch.
    for ring in 0 ..= chunk_radius {
        for offset_z in -ring ..= ring {
            for offset_x in -ring ..= ring {
                if max(abs(offset_x), abs(offset_z)) != ring do continue
                chunk_x := center_chunk_x + offset_x
                chunk_z := center_chunk_z + offset_z
                chunk_min_x := f32(chunk_x) * GROUND_GRASS_CHUNK_WORLD_SIZE
                chunk_min_z := f32(chunk_z) * GROUND_GRASS_CHUNK_WORLD_SIZE
                closest_x := clamp(field_x, chunk_min_x, chunk_min_x + GROUND_GRASS_CHUNK_WORLD_SIZE)
                closest_z := clamp(field_z, chunk_min_z, chunk_min_z + GROUND_GRASS_CHUNK_WORLD_SIZE)
                dx, dz := closest_x - field_x, closest_z - field_z
                if dx * dx + dz * dz > radius_squared do continue
                key := [2]int{chunk_x, chunk_z}
                chunk, found := world_renderer.grass_chunk_cache[key]
                complete := found && chunk.built_cells >= GROUND_GRASS_CHUNK_CELLS * GROUND_GRASS_CHUNK_CELLS
                if complete do continue
                cell_budget := min(STREAMING_CELLS_PER_CHUNK, remaining_cells^)
                _ = ground_grass_chunk_build(editor, key, building_footprints, circulation_plan, cell_budget)
                remaining_cells^ -= cell_budget
                if remaining_cells^ <= 0 do return
            }
        }
    }
}

ground_grass_cache_prefetch :: proc(
    editor: ^Editor,
    field_x, field_z, field_radius: f32,
    building_footprints: []Architecture_Grass_Footprint,
    circulation_plan: ^circulation.Plan,
) {
    PREFETCH_MARGIN :: f32(16)
    STREAMING_CELLS_PER_FRAME :: 512
    VISIBLE_CELL_RESERVE :: 384
    visible_cells := VISIBLE_CELL_RESERVE
    ground_grass_cache_stream_disc(
        editor,
        field_x,
        field_z,
        field_radius,
        building_footprints,
        circulation_plan,
        &visible_cells,
    )
    prefetch_cells := STREAMING_CELLS_PER_FRAME - VISIBLE_CELL_RESERVE + visible_cells
    ground_grass_cache_stream_disc(
        editor,
        field_x,
        field_z,
        field_radius + PREFETCH_MARGIN,
        building_footprints,
        circulation_plan,
        &prefetch_cells,
    )
}

world_ground_grass :: proc(editor: ^Editor) {
    if editor == nil || !editor.in_map || editor.benchmark_ground_grass_disabled do return
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "ground_grass")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    // Populate around the active view rather than the player character. This
    // keeps the visible field dense when an inspection or chase camera moves
    // away from the mouse, while the snapped world grid prevents shimmer.
    field_x, field_z := editor.camera_pose.position.x, editor.camera_pose.position.z
    field_radius := f32(42)
    if driving_aircraft(editor) {
        body := active_aircraft_body(editor)
        ground := terrain.sample_surface_height(&editor.project, 0, body.position.x, body.position.z)
        if body.position.y - ground > 28 do return
        field_radius = 60
    } else if editor.pilot.mode != .On_Foot && !driving_car(editor) {
        return
    }
    if !world_ground_grass_has_land(editor, field_x, field_z, field_radius) do return

    building_footprints := world_architecture_grass_footprints(editor)
    defer delete(building_footprints)
    circulation_plan := editor_circulation_plan(editor)

    if world_renderer.grass_chunk_cache == nil {
        world_renderer.grass_chunk_cache = make(map[[2]int]^Ground_Grass_Chunk, 256)
    }
    if world_renderer.grass_cache_project_revision != editor.project.revision {
        ground_grass_cache_clear()
        world_renderer.grass_cache_project_revision = editor.project.revision
    }
    world_renderer.grass_cache_terrain_revision = editor.terrain_revision
    world_renderer.grass_chunk_clock += 1
    ground_grass_cache_prefetch(editor, field_x, field_z, field_radius, building_footprints[:], circulation_plan)
    center_chunk_x := int(math.floor(f64(field_x / GROUND_GRASS_CHUNK_WORLD_SIZE)))
    center_chunk_z := int(math.floor(f64(field_z / GROUND_GRASS_CHUNK_WORLD_SIZE)))
    chunk_radius := int(math.ceil(f64(field_radius / GROUND_GRASS_CHUNK_WORLD_SIZE))) + 1
    radius_squared := field_radius * field_radius
    for chunk_z in center_chunk_z - chunk_radius ..= center_chunk_z + chunk_radius {
        for chunk_x in center_chunk_x - chunk_radius ..= center_chunk_x + chunk_radius {
            chunk_min_x := f32(chunk_x) * GROUND_GRASS_CHUNK_WORLD_SIZE
            chunk_min_z := f32(chunk_z) * GROUND_GRASS_CHUNK_WORLD_SIZE
            closest_x := clamp(field_x, chunk_min_x, chunk_min_x + GROUND_GRASS_CHUNK_WORLD_SIZE)
            closest_z := clamp(field_z, chunk_min_z, chunk_min_z + GROUND_GRASS_CHUNK_WORLD_SIZE)
            chunk_dx, chunk_dz := closest_x - field_x, closest_z - field_z
            if chunk_dx * chunk_dx + chunk_dz * chunk_dz > radius_squared do continue
            chunk := ground_grass_chunk_get({chunk_x, chunk_z})
            if chunk == nil do continue
            if chunk.stream_emitted do continue
            for &cached in chunk.entries[:chunk.count] {
                x, z := cached.grass.center[0], cached.grass.center[2]
                // Patio exclusion is part of ground_grass_chunk_build and any
                // project edit invalidates the chunk cache. Re-querying the
                // settlement spatial data for every cached blade every frame
                // made this retained cache substantially more expensive than
                // generating its visible instance stream.
                grass := cached.grass
                grass.ground_color = cached.ground_color
                grass.cull_params = {cached.density_roll, field_radius, 1, 0}
                append(&world_renderer.grass_instances, grass)
                world_renderer.grass_instances_emitted += 1
                if cached.has_flower {
                    append(
                        &world_renderer.wildflower_instances,
                        Grass_Instance {
                            center = {x, cached.flower_y, z},
                            size = cached.flower_size,
                            tile = cached.flower_tile,
                            color = {1, 1, 1, 2},
                            cull_params = {cached.density_roll, field_radius, 1, 0},
                        },
                    )
                }
            }
            chunk.stream_emitted = true
        }
    }
}
