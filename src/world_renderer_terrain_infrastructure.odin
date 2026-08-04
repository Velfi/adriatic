package main
import "core:math"
import "core:mem"
import "core:testing"

import dio "../packages/dio"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math/linalg"
import vk "vendor:vulkan"
import canvas2d "zelda_engine:canvas2d"
import engine "zelda_engine:engine"

terrain_dirty_bounds_include :: proc(target: ^Terrain_Dirty_Bounds, added: Terrain_Dirty_Bounds) {
    if target == nil || !added.valid do return
    if !target.valid {
        target^ = added
        return
    }
    target.full_rebuild = target.full_rebuild || added.full_rebuild
    target.min_x = min(target.min_x, added.min_x)
    target.min_z = min(target.min_z, added.min_z)
    target.max_x = max(target.max_x, added.max_x)
    target.max_z = max(target.max_z, added.max_z)
    target.revision = added.revision
}

@(no_instrumentation)
terrain_dirty_bounds_intersects_circle :: #force_inline proc(
    changed: Terrain_Dirty_Bounds,
    x, z, radius: f32,
) -> bool {
    closest_x := clamp(x, changed.min_x, changed.max_x)
    closest_z := clamp(z, changed.min_z, changed.max_z)
    dx, dz := x - closest_x, z - closest_z
    return dx * dx + dz * dz <= radius * radius
}

world_terrain_invalidate_derived :: proc(editor: ^Editor, changed: Terrain_Dirty_Bounds) {
    if editor == nil || !changed.valid do return
    ground_grass_cache_invalidate_bounds(changed.min_x, changed.min_z, changed.max_x, changed.max_z)
    world_bathymetry_geometry_cache_invalidate_bounds(changed.min_x, changed.min_z, changed.max_x, changed.max_z)
    world_ocean_sample_grid_invalidate_bounds(changed)
    // Terrain strokes also advance Project.revision. Record that revision here
    // so the next render keeps the unaffected chunks instead of treating the
    // localized edit as an unrelated project-wide topology change.
    world_renderer.grass_cache_project_revision = editor.project.revision
    if world_renderer.road_revision != 0 do world_renderer.road_revision = editor.project.revision
    world_road_geometry_cache_preserve_outside_bounds(editor, changed)
    if world_renderer.pavement_query_revision != 0 {
        world_renderer.pavement_query_revision = editor.project.revision
    }
    for &entry in world_renderer.architecture_street_area_cache {
        if !entry.valid do continue
        radius := f32(math.sqrt(f64(entry.area.width * entry.area.width + entry.area.length * entry.area.length))) * .5 + 2
        if terrain_dirty_bounds_intersects_circle(changed, entry.area.center_x, entry.area.center_z, radius) {
            entry.valid = false
            continue
        }
        entry.project_revision = editor.project.revision
        entry.terrain_revision = editor.terrain_revision
    }
    for &entry in world_renderer.settlement_fountain_geometry_cache {
        if !entry.valid do continue
        if terrain_dirty_bounds_intersects_circle(changed, entry.origin.x, entry.origin.z, entry.radius + 2.3) {
            entry.valid = false
            continue
        }
        entry.terrain_revision = editor.terrain_revision
    }
    // These derived city meshes have no cheap bounds index yet. They remain
    // valid while a preview moves, then rebuild once from the final terrain.
    for &entry in world_renderer.architecture_alley_render_cache do entry.valid = false
    world_renderer.architecture_alley_geometry_valid = false
    world_renderer.laundry_geometry_valid = false
    world_renderer.resident_home_cache_valid = false
    for &entry in world_renderer.static_geometry_cache {
        if !entry.valid do continue
        if world_terrain_structure_intersects(entry.structure, changed) {
            entry.valid = false
            world_renderer.retained_static_dirty = true
        }
    }
    for &entry in world_renderer.foliage_geometry_cache {
        if !entry.valid do continue
        if world_terrain_structure_intersects(entry.structure, changed) {
            entry.valid = false
        }
    }
    for &entry in world_renderer.town_mouse_geometry_cache {
        if !entry.valid do continue
        closest_x := clamp(entry.model.position.x, changed.min_x, changed.max_x)
        closest_z := clamp(entry.model.position.z, changed.min_z, changed.max_z)
        dx, dz := entry.model.position.x - closest_x, entry.model.position.z - closest_z
        influence_radius := TOWN_MOUSE_TERRAIN_RADIUS * entry.scale
        if dx * dx + dz * dz <= influence_radius * influence_radius {
            entry.valid = false
            continue
        }
        entry.project_revision = editor.project.revision
        entry.terrain_revision = editor.terrain_revision
        if entry.ground_valid {
            entry.ground_project_revision = editor.project.revision
            entry.ground_terrain_revision = editor.terrain_revision
        }
    }
    world_renderer.dynamic_shadow_terrain_cache.valid = false
}

world_terrain_defer_derived :: proc(editor: ^Editor, changed: Terrain_Dirty_Bounds) {
    if editor == nil || !changed.valid do return
    world_renderer.terrain_live_edit_active = true
    terrain_dirty_bounds_include(&world_renderer.terrain_live_edit_dirty, changed)
    world_renderer.terrain_live_edit_frame_dirty = changed

    // Keep the previously baked secondary world alive while the stroke moves.
    // Only the coarse terrain rings change live; roads, water, and grounded
    // presentation geometry reconcile once when the stroke ends.
    world_renderer.grass_cache_project_revision = editor.project.revision
    if world_renderer.road_revision != 0 do world_renderer.road_revision = editor.project.revision
    if world_renderer.road_geometry_valid {
        world_renderer.road_geometry_revision = editor.project.revision
        world_renderer.road_geometry_terrain_revision = editor.terrain_revision
    }
    if world_renderer.pavement_query_revision != 0 {
        world_renderer.pavement_query_revision = editor.project.revision
    }
    if world_renderer.ocean_cache_valid {
        world_renderer.ocean_cache_project_revision = editor.project.revision
        world_renderer.ocean_cache_terrain_revision = editor.terrain_revision
    }
    for &entry in world_renderer.architecture_street_area_cache {
        if !entry.valid do continue
        entry.project_revision = editor.project.revision
        entry.terrain_revision = editor.terrain_revision
    }
    for &entry in world_renderer.settlement_fountain_geometry_cache {
        if !entry.valid do continue
        entry.terrain_revision = editor.terrain_revision
    }
    if editor.circulation_plan_valid do editor.circulation_revision = editor.project.revision
    world_renderer.architecture_alley_terrain_revision = editor.terrain_revision
    world_renderer.architecture_alley_project_revision = editor.project.revision
    if world_renderer.architecture_alley_geometry_valid {
        world_renderer.architecture_alley_geometry_terrain_revision = editor.terrain_revision
        world_renderer.architecture_alley_geometry_project_revision = editor.project.revision
    }
    if world_renderer.laundry_geometry_valid {
        world_renderer.laundry_geometry_revision = editor.project.revision
        world_renderer.laundry_geometry_terrain_revision = editor.terrain_revision
    }
    if world_renderer.resident_home_cache_valid {
        world_renderer.resident_home_project_revision = editor.project.revision
        world_renderer.resident_home_terrain_revision = editor.terrain_revision
    }
    if world_renderer.town_mouse_placement_valid {
        world_renderer.town_mouse_placement_project_revision = editor.project.revision
        world_renderer.town_mouse_placement_terrain_revision = editor.terrain_revision
    }
    for &entry in world_renderer.town_mouse_geometry_cache {
        if !entry.valid do continue
        entry.project_revision = editor.project.revision
        entry.terrain_revision = editor.terrain_revision
        if entry.ground_valid {
            entry.ground_project_revision = editor.project.revision
            entry.ground_terrain_revision = editor.terrain_revision
        }
    }
    if world_renderer.dynamic_shadow_terrain_cache.valid {
        world_renderer.dynamic_shadow_terrain_cache.project_revision = editor.project.revision
        world_renderer.dynamic_shadow_terrain_cache.terrain_revision = editor.terrain_revision
    }
}

world_terrain_live_edit_flush :: proc(editor: ^Editor) {
    if editor == nil do return
    dirty := world_renderer.terrain_live_edit_dirty
    world_renderer.terrain_live_edit_dirty = {}
    world_renderer.terrain_live_edit_frame_dirty = {}
    world_renderer.terrain_live_edit_active = false
    if !dirty.valid do return

    dirty.revision = editor.terrain_revision
    terrain_dirty_bounds_include(&world_renderer.clipmap_cache_dirty, dirty)
    world_terrain_invalidate_derived(editor, dirty)
}

world_terrain_changed :: proc(editor: ^Editor, x, z, radius: f32, defer_derived := false) {
    if editor == nil do return
    editor.terrain_revision += 1
    revision := editor.terrain_revision
    changed := Terrain_Dirty_Bounds {
        valid    = true,
        revision = revision,
        min_x    = x - radius,
        min_z    = z - radius,
        max_x    = x + radius,
        max_z    = z + radius,
    }
    if defer_derived {
        world_terrain_defer_derived(editor, changed)
        return
    }
    if world_renderer.terrain_live_edit_dirty.valid {
        terrain_dirty_bounds_include(&changed, world_renderer.terrain_live_edit_dirty)
        changed.revision = revision
        world_renderer.terrain_live_edit_dirty = {}
        world_renderer.terrain_live_edit_frame_dirty = {}
        world_renderer.terrain_live_edit_active = false
    }
    cache_dirty := &world_renderer.clipmap_cache_dirty
    if cache_dirty.valid {
        terrain_dirty_bounds_include(cache_dirty, changed)
    } else {
        cache_dirty^ = changed
    }
    for &dirty in world_renderer.clipmap_dirty {
        if dirty.valid {
            if dirty.revision + 1 != revision do dirty.full_rebuild = true
            dirty.min_x = min(dirty.min_x, changed.min_x)
            dirty.min_z = min(dirty.min_z, changed.min_z)
            dirty.max_x = max(dirty.max_x, changed.max_x)
            dirty.max_z = max(dirty.max_z, changed.max_z)
            dirty.revision = revision
        } else {
            dirty = changed
        }
    }
    world_terrain_invalidate_derived(editor, changed)
}

world_terrain_invalidate_all :: proc(editor: ^Editor) {
    if editor == nil do return
    // Full terrain invalidation is the common commit point for undo/redo and
    // semantic terrain regeneration. Refresh derived ocean beds here once;
    // authored harbor and river chunks are excluded by terrain's ownership
    // rule.
    _ = terrain.bathymetry_refresh_all_generated(&editor.project)
    editor.terrain_revision += 1
    ground_grass_cache_clear()
    world_renderer.ocean_cache_valid = false
    world_renderer.ocean_sample_grid_valid = false
    world_renderer.ocean_sample_grid_dirty = {}
    for &entry in world_renderer.bathymetry_geometry_cache do entry.valid = false
    for &dirty in world_renderer.clipmap_dirty {
        dirty = {
            valid        = true,
            full_rebuild = true,
            revision     = editor.terrain_revision,
        }
    }
    world_renderer.clipmap_cache_dirty = {
        valid        = true,
        full_rebuild = true,
        revision     = editor.terrain_revision,
    }
    world_renderer.terrain_live_edit_active = false
    world_renderer.terrain_live_edit_dirty = {}
    world_renderer.terrain_live_edit_frame_dirty = {}
    for &entry in world_renderer.static_geometry_cache do entry.valid = false
    world_renderer.retained_static_dirty = true
    for &entry in world_renderer.foliage_geometry_cache do entry.valid = false
    for &entry in world_renderer.climbing_leaf_geometry_cache do entry.valid = false
    for &entry in world_renderer.town_mouse_geometry_cache do entry.valid = false
}

world_renderer_fixture_invalidate :: proc(editor: ^Editor) {
    if editor == nil do return
    world_terrain_invalidate_all(editor)
    world_renderer.dynamic_shadow.frame_prepared = false
    world_renderer.road_graph_valid = false
    world_renderer.road_revision = 0
    world_renderer.road_geometry_valid = false
    world_renderer.road_geometry_revision = 0
    world_renderer.road_geometry_terrain_revision = 0
    world_renderer.architecture_alley_terrain_revision = 0
    world_renderer.architecture_alley_project_revision = 0
    for &entry in world_renderer.architecture_alley_render_cache do entry.valid = false
    for &entry in world_renderer.architecture_alley_overlap_cache do entry.valid = false
    clear(&world_renderer.architecture_alley_overlap_plan)
    for &entry in world_renderer.architecture_street_area_cache do entry.valid = false
    world_renderer.laundry_geometry_valid = false
    world_renderer.laundry_geometry_revision = 0
    world_renderer.laundry_geometry_terrain_revision = 0
    world_renderer.pavement_query_graph_valid = false
    world_renderer.pavement_query_revision = 0
    for &entry in world_renderer.dialogue_portrait_geometry_cache do entry.valid = false
    world_renderer.libellula_geometry_cache.valid = false
    for &entry in world_renderer.marina_geometry_cache do entry.valid = false
}

world_structure_storage_ensure :: proc(count: int) {
    if count <= len(world_renderer.static_geometry_cache) do return
    MINIMUM_CAPACITY :: 64
    capacity := max(count, max(MINIMUM_CAPACITY, len(world_renderer.static_geometry_cache) * 2))
    resize(&world_renderer.foliage_geometry_cache, capacity)
    resize(&world_renderer.static_geometry_cache, capacity)
    resize(&world_renderer.climbing_leaf_geometry_cache, capacity)
    resize(&world_renderer.static_visibility_classification, capacity)
    reserve(&world_renderer.structure_visibility_order, capacity)
    resize(&world_renderer.structure_building_spans, capacity)
    reserve(&world_renderer.structure_candidates, capacity)
}

// Preview must leave input time for the next SDL poll. Updating a bounded
// dirty patch in an already allocated mesh gives small brushes immediate
// feedback and lets large strokes retain their last complete terrain stack.
CLIPMAP_LIVE_EDIT_VERTEX_BUDGET :: 512

clipmap_dirty_vertex_range :: proc(
    editor: ^Editor,
    level: int,
    center: [2]f32,
    dirty: Terrain_Dirty_Bounds,
) -> (range_min_x, range_min_z, range_max_x, range_max_z: int, valid: bool) {
    if editor == nil || !dirty.valid do return 0, 0, 0, 0, false
    data := &editor.project.levels[level]
    grid_cell := clipmap_grid_cell(editor, level)
    resolution := clipmap_grid_resolution(level)
    half_grid := f32(resolution - 1) * .5
    padding := data.cell_size * 2
    grid_min_x := center[0] - half_grid * grid_cell
    grid_min_z := center[1] - half_grid * grid_cell
    grid_max_x := center[0] + half_grid * grid_cell
    grid_max_z := center[1] + half_grid * grid_cell
    if dirty.max_x + padding < grid_min_x ||
       dirty.max_z + padding < grid_min_z ||
       dirty.min_x - padding > grid_max_x ||
       dirty.min_z - padding > grid_max_z {
        return 0, 0, 0, 0, false
    }
    range_min_x = clamp(int(math.floor(f64((dirty.min_x - padding - grid_min_x) / grid_cell))), 0, resolution - 1)
    range_min_z = clamp(int(math.floor(f64((dirty.min_z - padding - grid_min_z) / grid_cell))), 0, resolution - 1)
    range_max_x = clamp(int(math.ceil(f64((dirty.max_x + padding - grid_min_x) / grid_cell))), 0, resolution - 1)
    range_max_z = clamp(int(math.ceil(f64((dirty.max_z + padding - grid_min_z) / grid_cell))), 0, resolution - 1)
    return range_min_x, range_min_z, range_max_x, range_max_z, true
}

clipmap_live_edit_dirty :: proc(editor: ^Editor, level: int, dirty: Terrain_Dirty_Bounds) -> Terrain_Dirty_Bounds {
    if editor == nil || !dirty.valid do return {}
    cell := clipmap_grid_cell(editor, level)
    padding := editor.project.levels[level].cell_size * 2
    side := f32(math.floor(math.sqrt(f64(CLIPMAP_LIVE_EDIT_VERTEX_BUDGET))))
    radius := max((side - 3) * cell * .5 - padding, cell)
    center_x := (dirty.min_x + dirty.max_x) * .5
    center_z := (dirty.min_z + dirty.max_z) * .5
    return {
        valid    = true,
        revision = dirty.revision,
        min_x    = max(dirty.min_x, center_x - radius),
        min_z    = max(dirty.min_z, center_z - radius),
        max_x    = min(dirty.max_x, center_x + radius),
        max_z    = min(dirty.max_z, center_z + radius),
    }
}

clipmap_update_live_edit :: proc(editor: ^Editor, frame_index: int) {
    if editor == nil do return
    dirty := &world_renderer.terrain_live_edit_frame_dirty
    if !dirty.valid do return
    first_level := world_renderer.clipmap_first_level
    for level in first_level ..< terrain.CLIPMAP_LEVELS {
        if !world_renderer.clipmap_cache_valid[level] do continue
        center := world_renderer.clipmap_cache_center[level]
        live_dirty := clipmap_live_edit_dirty(editor, level, dirty^)
        _, _, _, _, in_level := clipmap_dirty_vertex_range(editor, level, center, live_dirty)
        if !in_level do continue
        generated := clipmap_update_level(
            editor,
            world_renderer.clipmap_cache_vertex[level][:],
            level,
            center,
            &live_dirty,
        )
        if generated == 0 do continue
        upload_profile := dio.flame_graph_begin(dio.flame_graph_current(), "clipmap_upload")
        buffer := &world_renderer.clipmap_vertex[frame_index][level]
        mem.copy_non_overlapping(
            buffer.mapped,
            raw_data(world_renderer.clipmap_cache_vertex[level][:]),
            len(world_renderer.clipmap_cache_vertex[level]) * size_of(World_Vertex),
        )
        _ = dio.flame_graph_end(dio.flame_graph_current(), upload_profile)
        world_renderer.clipmap_center[frame_index][level] = center
        world_renderer.clipmap_valid[frame_index][level] = true
        world_renderer.clipmap_cells_generated += u64(generated)
        world_renderer.clipmap_levels_generated += 1
        world_renderer.clipmap_levels_copied += 1
        return
    }
}

clipmap_update :: proc(editor: ^Editor, frame_index: int, viewport_height: i32, focal_length: f32) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "clipmap_update")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    if world_renderer.terrain_live_edit_active {
        clipmap_update_live_edit(editor, frame_index)
        return
    }
    cache_revision_changed := world_renderer.clipmap_cache_revision != editor.terrain_revision
    dirty := &world_renderer.clipmap_cache_dirty
    localized_revision :=
        cache_revision_changed && dirty.valid && !dirty.full_rebuild && dirty.revision == editor.terrain_revision
    target := [2]f32{editor.camera_pose.target.x, editor.camera_pose.target.z}
    first_level := clipmap_first_render_level(editor, viewport_height, focal_length)
    world_renderer.clipmap_first_level = first_level
    // Skipped caches do not receive terrain revisions. Invalidate them so a
    // later zoom-in regenerates and uploads current terrain instead of
    // reviving stale vertices from the previous detail band.
    for level in 0 ..< first_level {
        world_renderer.clipmap_cache_valid[level] = false
        for frame in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
            world_renderer.clipmap_valid[frame][level] = false
        }
    }
    for level in first_level ..< terrain.CLIPMAP_LEVELS {
        grid_cell := clipmap_grid_cell(editor, level)
        center := clipmap_level_center(target, grid_cell)
        cache_center_changed :=
            !world_renderer.clipmap_cache_valid[level] || world_renderer.clipmap_cache_center[level] != center
        if cache_revision_changed || cache_center_changed {
            resolution := clipmap_grid_resolution(level)
            vertex_count := resolution * resolution
            if len(world_renderer.clipmap_cache_vertex[level]) != vertex_count {
                resize(&world_renderer.clipmap_cache_vertex[level], vertex_count)
            }
            generate_profile := dio.flame_graph_begin(dio.flame_graph_current(), "clipmap_generate")
            generated, copied := 0, 0
            shifted := false
            if cache_center_changed {
                if world_renderer.clipmap_cache_valid[level] && (!cache_revision_changed || localized_revision) {
                    shifted, copied, generated = clipmap_shift_level(
                        editor,
                        level,
                        world_renderer.clipmap_cache_center[level],
                        center,
                    )
                }
                if !shifted {
                    generated = clipmap_update_level(
                        editor,
                        world_renderer.clipmap_cache_vertex[level][:],
                        level,
                        center,
                    )
                    world_renderer.clipmap_full_rebuilds += 1
                } else {
                    world_renderer.clipmap_incremental_shifts += 1
                    world_renderer.clipmap_cells_copied += u64(copied)
                    if localized_revision {
                        generated += clipmap_update_level(
                            editor,
                            world_renderer.clipmap_cache_vertex[level][:],
                            level,
                            center,
                            dirty,
                        )
                    }
                }
            } else if localized_revision {
                generated = clipmap_update_level(
                    editor,
                    world_renderer.clipmap_cache_vertex[level][:],
                    level,
                    center,
                    dirty,
                )
            } else {
                generated = clipmap_update_level(editor, world_renderer.clipmap_cache_vertex[level][:], level, center)
                world_renderer.clipmap_full_rebuilds += 1
            }
            _ = dio.flame_graph_end(dio.flame_graph_current(), generate_profile)
            world_renderer.clipmap_cache_center[level] = center
            world_renderer.clipmap_cache_valid[level] = true
            world_renderer.clipmap_levels_generated += 1
            world_renderer.clipmap_cells_generated += u64(generated)
        }
        if world_renderer.clipmap_revision[frame_index] != editor.terrain_revision ||
           !world_renderer.clipmap_valid[frame_index][level] ||
           world_renderer.clipmap_center[frame_index][level] != center {
            upload_profile := dio.flame_graph_begin(dio.flame_graph_current(), "clipmap_upload")
            buffer := &world_renderer.clipmap_vertex[frame_index][level]
            mem.copy_non_overlapping(
                buffer.mapped,
                raw_data(world_renderer.clipmap_cache_vertex[level][:]),
                len(world_renderer.clipmap_cache_vertex[level]) * size_of(World_Vertex),
            )
            _ = dio.flame_graph_end(dio.flame_graph_current(), upload_profile)
            world_renderer.clipmap_center[frame_index][level] = center
            world_renderer.clipmap_valid[frame_index][level] = true
            world_renderer.clipmap_levels_copied += 1
        }
    }
    world_renderer.clipmap_cache_revision = editor.terrain_revision
    world_renderer.clipmap_revision[frame_index] = editor.terrain_revision
    world_renderer.clipmap_cache_dirty = {}
    for &frame_dirty in world_renderer.clipmap_dirty do frame_dirty = {}
}

@(no_instrumentation)
clipmap_ring_variant :: proc(frame_index, level: int) -> [2]int {
    if level <= 0 || level >= terrain.CLIPMAP_LEVELS do return {1, 1}
    fine_center := world_renderer.clipmap_center[frame_index][level - 1]
    coarse_center := world_renderer.clipmap_center[frame_index][level]
    fine_grid_cell := clipmap_grid_cell(world_renderer.editor, level - 1)
    offset_x := clamp(int(math.round(f64((fine_center[0] - coarse_center[0]) / fine_grid_cell))), -1, 1)
    offset_z := clamp(int(math.round(f64((fine_center[1] - coarse_center[1]) / fine_grid_cell))), -1, 1)
    return {offset_x + 1, offset_z + 1}
}

@(no_instrumentation)
clipmap_ring_hole_bounds :: proc(offset: [2]int, fine_to_coarse_ratio: int = 2) -> [4]int {
    ratio := max(fine_to_coarse_ratio, 2)
    hole_min := CLIPMAP_GRID_RESOLUTION * (ratio - 1) / (ratio * 2)
    hole_min_x := hole_min + (offset[0] > 0 ? 1 : 0)
    hole_min_z := hole_min + (offset[1] > 0 ? 1 : 0)
    hole_width := CLIPMAP_GRID_RESOLUTION / ratio - 1
    return {hole_min_x, hole_min_z, hole_min_x + hole_width, hole_min_z + hole_width}
}

@(no_instrumentation)
clipmap_append_cell :: #force_inline proc(indices: ^[dynamic]u32, x, z, resolution: int) {
    row := resolution
    a := u32(z * row + x)
    b := u32(z * row + x + 1)
    c := u32((z + 1) * row + x + 1)
    d := u32((z + 1) * row + x)
    // Wound so the upward-facing terrain surface is the front (CCW) face, so it
    // survives back-face culling when viewed from above.
    append(indices, a, c, b, a, d, c)
}

clipmap_create_indices :: proc(ctx: ^engine.Vk_Context) -> bool {
    indices := make([dynamic]u32, 0, CLIPMAP_FULL_INDEX_COUNT)
    defer delete(indices)
    for z in 0 ..< CLIPMAP_INNER_GRID_RESOLUTION - 1 {
        for x in 0 ..< CLIPMAP_INNER_GRID_RESOLUTION - 1 {
            clipmap_append_cell(&indices, x, z, CLIPMAP_INNER_GRID_RESOLUTION)
        }
    }
    world_renderer.clipmap_full_indices = u32(len(indices))
    if !world_host_buffer_create(
        ctx,
        vk.DeviceSize(len(indices) * size_of(u32)),
        {.INDEX_BUFFER},
        &world_renderer.clipmap_index,
        "world clipmap full index buffer",
    ) {
        return false
    }
    mem.copy_non_overlapping(world_renderer.clipmap_index.mapped, raw_data(indices[:]), len(indices) * size_of(u32))

    clear(&indices)
    for z in 0 ..< CLIPMAP_GRID_RESOLUTION - 1 {
        for x in 0 ..< CLIPMAP_GRID_RESOLUTION - 1 {
            clipmap_append_cell(&indices, x, z, CLIPMAP_GRID_RESOLUTION)
        }
    }
    world_renderer.clipmap_outer_full_indices = u32(len(indices))
    if !world_host_buffer_create(
        ctx,
        vk.DeviceSize(len(indices) * size_of(u32)),
        {.INDEX_BUFFER},
        &world_renderer.clipmap_outer_full_index,
        "world clipmap outer full index buffer",
    ) {
        return false
    }
    mem.copy_non_overlapping(
        world_renderer.clipmap_outer_full_index.mapped,
        raw_data(indices[:]),
        len(indices) * size_of(u32),
    )

    // Adjacent centers differ by at most half a coarse cell in either axis.
    // A 63-cell asymmetric hole follows that offset and leaves one coarse-cell
    // overlap beneath the finer transition band, preventing cracks without
    // requiring per-frame index generation.
    for variant_z in 0 ..< 3 {
        for variant_x in 0 ..< 3 {
            clear(&indices)
            offset_x, offset_z := variant_x - 1, variant_z - 1
            hole := clipmap_ring_hole_bounds({offset_x, offset_z})
            for z in 0 ..< CLIPMAP_GRID_RESOLUTION - 1 {
                for x in 0 ..< CLIPMAP_GRID_RESOLUTION - 1 {
                    if x >= hole[0] && x < hole[2] && z >= hole[1] && z < hole[3] {
                        continue
                    }
                    clipmap_append_cell(&indices, x, z, CLIPMAP_GRID_RESOLUTION)
                }
            }
            if world_renderer.clipmap_ring_indices == 0 {
                world_renderer.clipmap_ring_indices = u32(len(indices))
            }
            if !world_host_buffer_create(
                ctx,
                vk.DeviceSize(len(indices) * size_of(u32)),
                {.INDEX_BUFFER},
                &world_renderer.clipmap_ring_index[variant_z][variant_x],
                "world clipmap offset ring index buffer",
            ) {
                return false
            }
            mem.copy_non_overlapping(
                world_renderer.clipmap_ring_index[variant_z][variant_x].mapped,
                raw_data(indices[:]),
                len(indices) * size_of(u32),
            )

            clear(&indices)
            sparse_hole := clipmap_ring_hole_bounds({offset_x, offset_z}, 4)
            for z in 0 ..< CLIPMAP_GRID_RESOLUTION - 1 {
                for x in 0 ..< CLIPMAP_GRID_RESOLUTION - 1 {
                    if x >= sparse_hole[0] && x < sparse_hole[2] && z >= sparse_hole[1] && z < sparse_hole[3] {
                        continue
                    }
                    clipmap_append_cell(&indices, x, z, CLIPMAP_GRID_RESOLUTION)
                }
            }
            if world_renderer.clipmap_inner_ring_indices == 0 {
                world_renderer.clipmap_inner_ring_indices = u32(len(indices))
            }
            if !world_host_buffer_create(
                ctx,
                vk.DeviceSize(len(indices) * size_of(u32)),
                {.INDEX_BUFFER},
                &world_renderer.clipmap_inner_ring_index[variant_z][variant_x],
                "world clipmap sparse transition ring index buffer",
            ) {
                return false
            }
            mem.copy_non_overlapping(
                world_renderer.clipmap_inner_ring_index[variant_z][variant_x].mapped,
                raw_data(indices[:]),
                len(indices) * size_of(u32),
            )
        }
    }
    return true
}

PAPI_SIGNAL_CARD_START_DISTANCE :: f32(120)
PAPI_SIGNAL_CARD_BASE_SIZE :: f32(.46)
PAPI_SIGNAL_CARD_ANGULAR_SCALE :: f32(.002)
PAPI_SIGNAL_CARD_MAX_SIZE :: f32(1.10)

@(no_instrumentation)
papi_signal_card_size :: proc(approach_distance: f32) -> f32 {
    return clamp(
        approach_distance * PAPI_SIGNAL_CARD_ANGULAR_SCALE,
        PAPI_SIGNAL_CARD_BASE_SIZE,
        PAPI_SIGNAL_CARD_MAX_SIZE,
    )
}

world_runway_papi :: proc(
    editor: ^Editor,
    runway_x, runway_z, runway_y, runway_half_length, runway_half_width, approach_sign: f32,
) {
    // A PAPI sits just inside the threshold, on the pilot's left when viewed
    // from the approach. Its four optical units transition around a three
    // degree glide path: more white means high, more red means low.
    papi_x := runway_x + approach_sign * (runway_half_length - 45)
    papi_side := -approach_sign
    papi_center_z := runway_z + papi_side * (runway_half_width + 8)
    approach_distance := (editor.camera_pose.position.x - papi_x) * approach_sign
    white_count := 0
    if approach_distance > 1 {
        height_above_papi := max(editor.camera_pose.position.y - runway_y, f32(0))
        glide_angle := f32(math.atan2(f64(height_above_papi), f64(approach_distance))) * 180 / f32(math.PI)
        if glide_angle >= 3.50 {
            white_count = 4
        } else if glide_angle >= 3.20 {
            white_count = 3
        } else if glide_angle >= 2.80 {
            white_count = 2
        } else if glide_angle >= 2.50 {
            white_count = 1
        }
    }

    for light_index in 0 ..< 4 {
        offset := (f32(light_index) - 1.5) * 1.65
        light_z := papi_center_z + offset
        world_box({papi_x, runway_y + .18, light_z}, {.92, .34, .72}, {45, 48, 46, 255})
        lamp_color := light_index < white_count ? canvas2d.Color{255, 247, 213, 255} : canvas2d.Color{255, 42, 31, 255}
        if approach_distance <= 1 {
            lamp_color = {67, 29, 25, 255}
        }
        world_box_rotated_material(
            {papi_x + approach_sign * .39, runway_y + .29, light_z},
            {.08, .22, .46},
            0,
            lamp_color,
            .Emissive,
        )
        if approach_distance >= PAPI_SIGNAL_CARD_START_DISTANCE {
            // PAPI is an approach aid, not ordinary decorative lighting. Its
            // physical lens becomes sub-pixel hundreds of metres out, exactly
            // where the four-light signal must remain readable. Keep a small
            // minimum angular size while retaining separate dots and normal
            // scene depth testing.
            signal_size := papi_signal_card_size(approach_distance)
            world_billboard_material_uv(
                editor,
                {papi_x + approach_sign * .40, runway_y + .29, light_z},
                signal_size,
                signal_size,
                lamp_color,
                .Emissive,
            )
        }
    }
}

world_infrastructure :: proc(editor: ^Editor) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "world_infrastructure")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    half := f32(terrain.WORLD_SIZE_METERS * .5)
    for sign in terrain.DEFAULT_ISLAND_SIGNS {
        x, z := terrain.default_runway_center_for_project(&editor.project, sign)
        run_l, run_w := half * terrain.DEFAULT_RUNWAY_HALF_LENGTH, half * terrain.DEFAULT_RUNWAY_HALF_WIDTH
        y := terrain.sample_surface_height(&editor.project, 0, x, z) + .05
        world_runway_papi(editor, x, z, y, run_l, run_w, -1)
        world_runway_papi(editor, x, z, y, run_l, run_w, 1)
    }
}

@(no_instrumentation)
formation_face_color :: #force_inline proc(base: canvas2d.Color, angle: f32, layer: int) -> canvas2d.Color {
    light := math.cos(angle) * -.45 + math.sin(angle) * -.30
    if base.r > 175 && base.g > 165 && base.b > 135 {
        // Adriatic limestone is pale and cool, with stronger facet separation
        // than the generic formation palette.
        shade := clamp(.78 + light * .38 + f32(layer) * .055, .52, 1.18)
        return {
            r = u8(clamp(f32(base.r) * shade, 0, 255)),
            g = u8(clamp(f32(base.g) * shade * 1.01, 0, 255)),
            b = u8(clamp(f32(base.b) * shade * 1.03, 0, 255)),
            a = base.a,
        }
    }
    shade := clamp(.67 + light * .28 + f32(layer) * .035, .42, 1.05)
    return {
        r = u8(clamp(f32(base.r) * shade, 0, 255)),
        g = u8(clamp(f32(base.g) * shade, 0, 255)),
        b = u8(clamp(f32(base.b) * shade, 0, 255)),
        a = base.a,
    }
}

@(no_instrumentation)
world_rotate_xz :: #force_inline proc(center_x, center_z, x, z, rotation: f32) -> (f32, f32) {
    cosine, sine := math.cos(rotation), math.sin(rotation)
    return center_x + x * cosine - z * sine, center_z + x * sine + z * cosine
}

@(no_instrumentation)
world_land_surface_sample :: #force_inline proc(
    editor: ^Editor,
    center_x, center_z, local_x, local_z, cosine, sine: f32,
) -> World_Land_Surface_Sample {
    x := center_x + local_x * cosine - local_z * sine
    z := center_z + local_x * sine + local_z * cosine
    return {x, z, terrain.sample_surface_height(&editor.project, 0, x, z)}
}

world_box_rotated :: proc(center: third_person.Vec3, size: third_person.Vec3, rotation: f32, color: canvas2d.Color) {
    x, y, z := size.x * .5, size.y * .5, size.z * .5
    p: [8]third_person.Vec3
    local := [8][3]f32 {
        {-x, -y, -z},
        {x, -y, -z},
        {x, y, -z},
        {-x, y, -z},
        {-x, -y, z},
        {x, -y, z},
        {x, y, z},
        {-x, y, z},
    }
    for index in 0 ..< 8 {
        world_x, world_z := world_rotate_xz(center.x, center.z, local[index][0], local[index][2], rotation)
        p[index] = {world_x, center.y + local[index][1], world_z}
    }
    world_quad(p[0], p[3], p[2], p[1], color)
    world_quad(p[4], p[5], p[6], p[7], color)
    world_quad(p[0], p[4], p[7], p[3], color)
    world_quad(p[1], p[2], p[6], p[5], color)
    world_quad(p[3], p[7], p[6], p[2], color)
    world_quad(p[0], p[1], p[5], p[4], color)
}

world_settlement_material_box_rotated :: proc(
    center: third_person.Vec3,
    size: third_person.Vec3,
    rotation: f32,
    material: Settlement_Material,
) {
    x, y, z := size.x * .5, size.y * .5, size.z * .5
    p: [8]third_person.Vec3
    local := [8][3]f32 {
        {-x, -y, -z},
        {x, -y, -z},
        {x, y, -z},
        {-x, y, -z},
        {-x, -y, z},
        {x, -y, z},
        {x, y, z},
        {-x, y, z},
    }
    for index in 0 ..< 8 {
        world_x, world_z := world_rotate_xz(center.x, center.z, local[index][0], local[index][2], rotation)
        p[index] = {world_x, center.y + local[index][1], world_z}
    }
    world_settlement_material_quad(p[0], p[3], p[2], p[1], material, size.x, size.y)
    world_settlement_material_quad(p[4], p[5], p[6], p[7], material, size.x, size.y)
    world_settlement_material_quad(p[0], p[4], p[7], p[3], material, size.z, size.y)
    world_settlement_material_quad(p[1], p[2], p[6], p[5], material, size.z, size.y)
    world_settlement_material_quad(p[3], p[7], p[6], p[2], material, size.x, size.z)
    world_settlement_material_quad(p[0], p[1], p[5], p[4], material, size.x, size.z)
}

// Compatibility names keep the airport generator readable while new
// settlement systems use the shared helpers directly.
world_airport_box_rotated :: world_settlement_material_box_rotated

world_box_rotated_material :: proc(
    center: third_person.Vec3,
    size: third_person.Vec3,
    rotation: f32,
    color: canvas2d.Color,
    kind: World_Material_Kind,
) {
    x, y, z := size.x * .5, size.y * .5, size.z * .5
    p: [8]third_person.Vec3
    local := [8][3]f32 {
        {-x, -y, -z},
        {x, -y, -z},
        {x, y, -z},
        {-x, y, -z},
        {-x, -y, z},
        {x, -y, z},
        {x, y, z},
        {-x, y, z},
    }
    for index in 0 ..< 8 {
        world_x, world_z := world_rotate_xz(center.x, center.z, local[index][0], local[index][2], rotation)
        p[index] = {world_x, center.y + local[index][1], world_z}
    }
    world_quad_material(p[0], p[3], p[2], p[1], color, kind)
    world_quad_material(p[4], p[5], p[6], p[7], color, kind)
    world_quad_material(p[0], p[4], p[7], p[3], color, kind)
    world_quad_material(p[1], p[2], p[6], p[5], color, kind)
    world_quad_material(p[3], p[7], p[6], p[2], color, kind)
    world_quad_material(p[0], p[1], p[5], p[4], color, kind)
}

@(no_instrumentation)
world_quad_lit :: #force_inline proc(a, b, c, d: third_person.Vec3, color: canvas2d.Color, metallic, roughness: f32) {
    normal := linalg.normalize0(linalg.cross(b - a, c - a))
    vertices := [6]World_Vertex {
        world_vertex(a, color),
        world_vertex(b, color),
        world_vertex(c, color),
        world_vertex(a, color),
        world_vertex(c, color),
        world_vertex(d, color),
    }
    for &vertex in vertices {
        vertex.kind = .BRDF
        vertex.normal = {normal.x, normal.y, normal.z}
        vertex.material = {clamp(metallic, 0, 1), clamp(roughness, .04, 1)}
    }
    append(&world_renderer.vertices, ..vertices[:])
}
