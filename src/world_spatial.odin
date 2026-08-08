package main

import terrain "../packages/terrain"
import "core:math"
import "core:testing"

WORLD_SPATIAL_LEVEL_COUNT :: 6
WORLD_SPATIAL_BASE_CELL_SIZE :: f32(32)
WORLD_SPATIAL_LOOSENESS :: f32(2)

World_Bounds_2D :: struct {
    min_x, min_z: f32,
    max_x, max_z: f32,
}

World_Cell_Key :: struct {
    level: u8,
    x, z:  i32,
}

World_Static_Object :: struct {
    id:                                u64,
    bounds:                            World_Bounds_2D,
    cell:                              World_Cell_Key,
    oversized:                         bool,
    source_revision, terrain_revision: u64,
    cluster_first, cluster_count:      int,
}

World_Render_Bin :: enum u8 {
    Opaque,
    Instanced,
    Foliage,
    Vegetation,
    Road,
}

World_Render_Cluster :: struct {
    center:                    [3]f32,
    radius:                    f32,
    cone_axis:                 [3]f32,
    cone_cutoff:               f32,
    object_id:                 u64,
    first_vertex, first_index: u32,
    vertex_count, index_count: u32,
    material_key:              u32,
    bin:                       World_Render_Bin,
    lod:                       Structure_LOD,
}

World_Spatial_Index :: struct {
    objects:   map[u64]World_Static_Object,
    cells:     map[World_Cell_Key][dynamic]u64,
    oversized: [dynamic]u64,
}

world_structure_bounds_2d :: proc(structure: terrain.Structure) -> World_Bounds_2D {
    half_width := structure.width * .5
    half_depth := structure.depth * .5
    cosine, sine := abs(math.cos(structure.rotation)), abs(math.sin(structure.rotation))
    extent_x := half_width * cosine + half_depth * sine
    extent_z := half_width * sine + half_depth * cosine
    return {
        structure.center_x - extent_x,
        structure.center_z - extent_z,
        structure.center_x + extent_x,
        structure.center_z + extent_z,
    }
}

world_spatial_sync_structures :: proc(editor: ^Editor) {
    if editor == nil || world_renderer.spatial_project_revision == editor.project.revision do return
    if world_renderer.spatial_index.objects == nil {
        world_spatial_index_init(&world_renderer.spatial_index)
    }
    seen := make(map[u64]bool, editor.project.structure_count, context.temp_allocator)
    for structure, index in editor.project.structures[:editor.project.structure_count] {
        id := structure.id
        if id == 0 do id = u64(index + 1) | (u64(1) << 63)
        seen[id] = true
        bounds := world_structure_bounds_2d(structure)
        existing, found := world_renderer.spatial_index.objects[id]
        if !found || existing.bounds != bounds {
            world_spatial_index_upsert(&world_renderer.spatial_index, {
                id               = id,
                bounds           = bounds,
                source_revision  = editor.project.revision,
                terrain_revision = editor.terrain_revision,
            })
        } else {
            existing.source_revision = editor.project.revision
            existing.terrain_revision = editor.terrain_revision
            world_renderer.spatial_index.objects[id] = existing
        }
    }
    removed := make([dynamic]u64, context.temp_allocator)
    for id in world_renderer.spatial_index.objects {
        if !seen[id] do append(&removed, id)
    }
    for id in removed {
        _ = world_spatial_index_remove(&world_renderer.spatial_index, id)
    }
    world_renderer.spatial_project_revision = editor.project.revision
}

world_bounds_2d_normalize :: proc(bounds: World_Bounds_2D) -> World_Bounds_2D {
    return {
        min(bounds.min_x, bounds.max_x),
        min(bounds.min_z, bounds.max_z),
        max(bounds.min_x, bounds.max_x),
        max(bounds.min_z, bounds.max_z),
    }
}

world_bounds_2d_intersects :: #force_inline proc(a, b: World_Bounds_2D) -> bool {
    return a.max_x >= b.min_x && a.min_x <= b.max_x && a.max_z >= b.min_z && a.min_z <= b.max_z
}

world_spatial_cell_size :: #force_inline proc(level: int) -> f32 {
    scale := u32(1) << u32(clamp(level, 0, WORLD_SPATIAL_LEVEL_COUNT - 1))
    return WORLD_SPATIAL_BASE_CELL_SIZE * f32(scale)
}

world_spatial_cell_bounds :: proc(key: World_Cell_Key, loose := true) -> World_Bounds_2D {
    size := world_spatial_cell_size(int(key.level))
    center_x := (f32(key.x) + .5) * size
    center_z := (f32(key.z) + .5) * size
    half := size * .5 * (loose ? WORLD_SPATIAL_LOOSENESS : 1)
    return {center_x - half, center_z - half, center_x + half, center_z + half}
}

world_spatial_cell_for_bounds :: proc(source: World_Bounds_2D) -> (World_Cell_Key, bool) {
    bounds := world_bounds_2d_normalize(source)
    center_x := (bounds.min_x + bounds.max_x) * .5
    center_z := (bounds.min_z + bounds.max_z) * .5
    for level in 0 ..< WORLD_SPATIAL_LEVEL_COUNT {
        size := world_spatial_cell_size(level)
        key := World_Cell_Key {
            level = u8(level),
            x     = i32(math.floor(f64(center_x / size))),
            z     = i32(math.floor(f64(center_z / size))),
        }
        loose_bounds := world_spatial_cell_bounds(key)
        if bounds.min_x >= loose_bounds.min_x &&
           bounds.max_x <= loose_bounds.max_x &&
           bounds.min_z >= loose_bounds.min_z &&
           bounds.max_z <= loose_bounds.max_z {
            return key, true
        }
    }
    return {}, false
}

world_spatial_index_init :: proc(index: ^World_Spatial_Index) {
    if index == nil do return
    index^ = {
        objects   = make(map[u64]World_Static_Object),
        cells     = make(map[World_Cell_Key][dynamic]u64),
        oversized = make([dynamic]u64),
    }
}

world_spatial_index_destroy :: proc(index: ^World_Spatial_Index) {
    if index == nil do return
    for _, ids in index.cells do delete(ids)
    delete(index.cells)
    delete(index.objects)
    delete(index.oversized)
    index^ = {}
}

world_spatial_remove_id :: proc(ids: ^[dynamic]u64, id: u64) -> bool {
    if ids == nil do return false
    for existing, position in ids {
        if existing != id do continue
        unordered_remove(ids, position)
        return true
    }
    return false
}

world_spatial_index_remove :: proc(index: ^World_Spatial_Index, id: u64) -> bool {
    if index == nil || index.objects == nil do return false
    object, found := index.objects[id]
    if !found do return false
    if object.oversized {
        _ = world_spatial_remove_id(&index.oversized, id)
    } else if ids, cell_found := index.cells[object.cell]; cell_found {
        _ = world_spatial_remove_id(&ids, id)
        if len(ids) == 0 {
            delete(ids)
            delete_key(&index.cells, object.cell)
        } else {
            index.cells[object.cell] = ids
        }
    }
    delete_key(&index.objects, id)
    return true
}

world_spatial_index_upsert :: proc(index: ^World_Spatial_Index, object: World_Static_Object) {
    if index == nil || object.id == 0 do return
    if index.objects == nil do world_spatial_index_init(index)
    _ = world_spatial_index_remove(index, object.id)
    stored := object
    stored.bounds = world_bounds_2d_normalize(object.bounds)
    key, found := world_spatial_cell_for_bounds(stored.bounds)
    stored.cell = key
    stored.oversized = !found
    index.objects[stored.id] = stored
    if stored.oversized {
        append(&index.oversized, stored.id)
        return
    }
    ids := index.cells[key]
    append(&ids, stored.id)
    index.cells[key] = ids
}

world_spatial_query :: proc(index: ^World_Spatial_Index, source: World_Bounds_2D, result: ^[dynamic]u64) {
    if index == nil || result == nil do return
    clear(result)
    query := world_bounds_2d_normalize(source)
    for key, ids in index.cells {
        if !world_bounds_2d_intersects(world_spatial_cell_bounds(key), query) do continue
        for id in ids {
            object, found := index.objects[id]
            if found && world_bounds_2d_intersects(object.bounds, query) do append(result, id)
        }
    }
    for id in index.oversized {
        object, found := index.objects[id]
        if found && world_bounds_2d_intersects(object.bounds, query) do append(result, id)
    }
}

when ODIN_TEST {
    @(test)
    world_spatial_assigns_small_object_once :: proc(t: ^testing.T) {
        index: World_Spatial_Index
        world_spatial_index_init(&index)
        defer world_spatial_index_destroy(&index)
        world_spatial_index_upsert(&index, {id = 1, bounds = {-2, -2, 2, 2}})
        object, found := index.objects[1]
        testing.expect(t, found)
        testing.expect(t, !object.oversized)
        testing.expect_value(t, len(index.cells[object.cell]), 1)
    }

    @(test)
    world_spatial_handles_negative_boundary_and_reinsert :: proc(t: ^testing.T) {
        index: World_Spatial_Index
        world_spatial_index_init(&index)
        defer world_spatial_index_destroy(&index)
        world_spatial_index_upsert(&index, {id = 7, bounds = {-33, -1, -31, 1}})
        before := index.objects[7]
        testing.expect(t, before.cell.x < 0)
        world_spatial_index_upsert(&index, {id = 7, bounds = {95, 95, 97, 97}})
        after := index.objects[7]
        testing.expect(t, after.cell != before.cell)
        testing.expect_value(t, len(index.objects), 1)
    }

    @(test)
    world_spatial_promotes_large_and_tracks_oversized :: proc(t: ^testing.T) {
        key, found := world_spatial_cell_for_bounds({-60, -60, 60, 60})
        testing.expect(t, found)
        testing.expect(t, key.level >= 2)
        _, huge_found := world_spatial_cell_for_bounds({-2000, -2000, 2000, 2000})
        testing.expect(t, !huge_found)
    }

    @(test)
    world_spatial_query_returns_only_intersections :: proc(t: ^testing.T) {
        index: World_Spatial_Index
        world_spatial_index_init(&index)
        defer world_spatial_index_destroy(&index)
        world_spatial_index_upsert(&index, {id = 1, bounds = {0, 0, 4, 4}})
        world_spatial_index_upsert(&index, {id = 2, bounds = {200, 200, 204, 204}})
        result := make([dynamic]u64)
        defer delete(result)
        world_spatial_query(&index, {-1, -1, 8, 8}, &result)
        testing.expect_value(t, len(result), 1)
        testing.expect_value(t, result[0], u64(1))
    }
}
