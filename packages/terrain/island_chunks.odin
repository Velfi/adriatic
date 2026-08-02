package terrain

import "core:math"

// Island terrain is authored in a stable local coordinate system. World
// placement never changes chunk keys or sample data.
ISLAND_CHUNK_CELLS :: 32
ISLAND_CHUNK_SAMPLES :: ISLAND_CHUNK_CELLS * ISLAND_CHUNK_CELLS
ISLAND_MAX_CLIPMAP_LEVELS :: 6
// The far three logical levels reuse the level-2 island raster. This keeps
// island-wide detail dense where it is visible while avoiding serialization of
// six copies of the same broad landscape.
ISLAND_BUILT_CLIPMAP_LEVELS :: 3
BATHYMETRY_TILE_CELLS :: 64
BATHYMETRY_TILE_SAMPLES :: BATHYMETRY_TILE_CELLS * BATHYMETRY_TILE_CELLS
ISLAND_MATERIAL_QUANTIZATION :: f32(16)

Island_Transform :: struct {
    position_x, position_z: f32,
    rotation:               f32,
    uniform_scale:          f32,
    basis_cos, basis_sin:   f32,
}

Island_Chunk_Key :: struct {
    island_id: u64,
    level:     u8,
    chunk_x:   i32,
    chunk_z:   i32,
}

Island_Terrain_Chunk :: struct {
    key:       Island_Chunk_Key,
    cell_size: f32,
    origin_x:  f32,
    origin_z:  f32,
    heights:   [ISLAND_CHUNK_SAMPLES]f16,
    material:  [ISLAND_CHUNK_SAMPLES]i8,
    revision:  u64,
}

Island_Asset :: struct {
    id:             u64,
    seed:           u32,
    local_min_x:    f32,
    local_min_z:    f32,
    local_max_x:    f32,
    local_max_z:    f32,
    transform:      Island_Transform,
    chunks:         [dynamic]Island_Terrain_Chunk,
    revision:       u64,
}

Bathymetry_Tile :: struct {
    tile_x:   i32,
    tile_z:   i32,
    cell_size: f32,
    origin_x: f32,
    origin_z: f32,
    depth:    [BATHYMETRY_TILE_SAMPLES]f32,
    material: [BATHYMETRY_TILE_SAMPLES]f32,
}

island_transform_valid :: proc(transform: Island_Transform) -> bool {
    return !math.is_nan(transform.position_x) && !math.is_inf(transform.position_x, 0) &&
           !math.is_nan(transform.position_z) && !math.is_inf(transform.position_z, 0) &&
           !math.is_nan(transform.rotation) && !math.is_inf(transform.rotation, 0) &&
           !math.is_nan(transform.uniform_scale) && !math.is_inf(transform.uniform_scale, 0) &&
           transform.uniform_scale > 0
}

island_transform_prepare :: proc(transform: Island_Transform) -> Island_Transform {
    result := transform
    result.basis_cos = f32(math.cos(f64(transform.rotation)))
    result.basis_sin = f32(math.sin(f64(transform.rotation)))
    return result
}

island_local_to_world :: proc(transform: Island_Transform, x, z: f32) -> (world_x, world_z: f32) {
    scale := transform.uniform_scale
    c, s := transform.basis_cos, transform.basis_sin
    if c == 0 && s == 0 && transform.rotation == 0 do c = 1
    if c == 0 && s == 0 && transform.rotation != 0 {
        c, s = f32(math.cos(f64(transform.rotation))), f32(math.sin(f64(transform.rotation)))
    }
    return transform.position_x + (x * c - z * s) * scale,
           transform.position_z + (x * s + z * c) * scale
}

island_world_to_local :: proc(transform: Island_Transform, x, z: f32) -> (local_x, local_z: f32) {
    dx, dz := x - transform.position_x, z - transform.position_z
    c, s := transform.basis_cos, transform.basis_sin
    if c == 0 && s == 0 && transform.rotation == 0 do c = 1
    if c == 0 && s == 0 && transform.rotation != 0 {
        c, s = f32(math.cos(f64(transform.rotation))), f32(math.sin(f64(transform.rotation)))
    }
    scale := max(transform.uniform_scale, f32(1e-6))
    return (dx * c + dz * s) / scale, (-dx * s + dz * c) / scale
}

island_chunk_key_equal :: #force_inline proc(a, b: Island_Chunk_Key) -> bool {
    return a.island_id == b.island_id && a.level == b.level &&
           a.chunk_x == b.chunk_x && a.chunk_z == b.chunk_z
}

island_chunk_index :: #force_inline proc(x, z: int) -> int {
    return z * ISLAND_CHUNK_CELLS + x
}

island_contains_world_point :: proc(island: ^Island_Asset, x, z: f32) -> bool {
    if island == nil || !island_transform_valid(island.transform) do return false
    local_x, local_z := island_world_to_local(island.transform, x, z)
    return local_x >= island.local_min_x && local_x <= island.local_max_x &&
           local_z >= island.local_min_z && local_z <= island.local_max_z
}

island_chunk_at :: proc(island: ^Island_Asset, level: int, local_x, local_z: f32) -> ^Island_Terrain_Chunk {
    if island == nil || level < 0 || level >= ISLAND_MAX_CLIPMAP_LEVELS do return nil
    effective_level := min(level, ISLAND_BUILT_CLIPMAP_LEVELS - 1)
    cell_size := FINE_CELL_SIZE * f32(u32(1) << u32(effective_level))
    extent := f32(ISLAND_CHUNK_CELLS) * cell_size
    target_x := int(math.floor(f64((local_x - island.local_min_x) / extent)))
    target_z := int(math.floor(f64((local_z - island.local_min_z) / extent)))
    target := Island_Chunk_Key{island_id = island.id, level = u8(effective_level), chunk_x = i32(target_x), chunk_z = i32(target_z)}
    left, right := 0, len(island.chunks)
    for left < right {
        middle := (left + right) / 2
        key := island.chunks[middle].key
        before := key.level < target.level || (key.level == target.level &&
            (key.chunk_z < target.chunk_z || (key.chunk_z == target.chunk_z && key.chunk_x < target.chunk_x)))
        if before {
            left = middle + 1
        } else {
            right = middle
        }
    }
    if left < len(island.chunks) && island_chunk_key_equal(island.chunks[left].key, target) {
        return &island.chunks[left]
    }
    return nil
}

island_sample_chunk :: proc(chunk: ^Island_Terrain_Chunk, local_x, local_z: f32) -> (height, material: f32, ok: bool) {
    if chunk == nil || chunk.cell_size <= 0 do return
    grid_x := (local_x - chunk.origin_x) / chunk.cell_size
    grid_z := (local_z - chunk.origin_z) / chunk.cell_size
    x0, z0 := int(math.floor(f64(grid_x))), int(math.floor(f64(grid_z)))
    if x0 < 0 || z0 < 0 || x0 >= ISLAND_CHUNK_CELLS || z0 >= ISLAND_CHUNK_CELLS do return
    tx, tz := clamp(grid_x - f32(x0), 0, 1), clamp(grid_z - f32(z0), 0, 1)
    x1, z1 := min(x0 + 1, ISLAND_CHUNK_CELLS - 1), min(z0 + 1, ISLAND_CHUNK_CELLS - 1)
    a := f32(chunk.heights[island_chunk_index(x0, z0)]) * (1 - tx) + f32(chunk.heights[island_chunk_index(x1, z0)]) * tx
    b := f32(chunk.heights[island_chunk_index(x0, z1)]) * (1 - tx) + f32(chunk.heights[island_chunk_index(x1, z1)]) * tx
    ma := f32(chunk.material[island_chunk_index(x0, z0)]) / ISLAND_MATERIAL_QUANTIZATION * (1 - tx) + f32(chunk.material[island_chunk_index(x1, z0)]) / ISLAND_MATERIAL_QUANTIZATION * tx
    mb := f32(chunk.material[island_chunk_index(x0, z1)]) / ISLAND_MATERIAL_QUANTIZATION * (1 - tx) + f32(chunk.material[island_chunk_index(x1, z1)]) / ISLAND_MATERIAL_QUANTIZATION * tx
    return a * (1 - tz) + b * tz, ma * (1 - tz) + mb * tz, true
}

island_sample_world :: proc(island: ^Island_Asset, level: int, x, z: f32) -> (height, material: f32, ok: bool) {
    if !island_contains_world_point(island, x, z) do return
    local_x, local_z := island_world_to_local(island.transform, x, z)
    chunk := island_chunk_at(island, level, local_x, local_z)
    return island_sample_chunk(chunk, local_x, local_z)
}

island_assets_destroy :: proc(islands: ^[dynamic]Island_Asset) {
    if islands == nil do return
    for &island in islands^ do delete(island.chunks)
    delete(islands^)
    islands^ = nil
}

island_chunk_append_default :: proc(
    island: ^Island_Asset,
    level: int,
    cell_size: f32,
    source_levels: ^[CLIPMAP_LEVELS]Clipmap_Level,
) {
    if island == nil || level < 0 || level >= ISLAND_MAX_CLIPMAP_LEVELS do return
    extent := f32(ISLAND_CHUNK_CELLS) * cell_size
    count_x := int(math.ceil(f64((island.local_max_x - island.local_min_x) / extent)))
    count_z := int(math.ceil(f64((island.local_max_z - island.local_min_z) / extent)))
    for chunk_z in 0 ..< count_z {
        for chunk_x in 0 ..< count_x {
            candidate_origin_x := island.local_min_x + f32(chunk_x) * extent
            candidate_origin_z := island.local_min_z + f32(chunk_z) * extent
            source := &source_levels[level]
            chunk := Island_Terrain_Chunk{
                key = {island_id = island.id, level = u8(level), chunk_x = i32(chunk_x), chunk_z = i32(chunk_z)},
                cell_size = cell_size,
                origin_x = candidate_origin_x,
                origin_z = candidate_origin_z,
                revision = 1,
            }
            land_corner := false
            corners := [2]f32{0, f32(ISLAND_CHUNK_CELLS - 1)}
            for corner in corners {
                for side in corners {
                    local_x := candidate_origin_x + corner * cell_size
                    local_z := candidate_origin_z + side * cell_size
                    world_x, world_z := island_local_to_world(island.transform, local_x, local_z)
                    if !level_contains(source, world_x, world_z) do source = &source_levels[CLIPMAP_LEVELS - 1]
                    if sample_level_height(source, world_x, world_z) > 0.001 do land_corner = true
                }
            }
            if !land_corner do continue
            for z in 0 ..< ISLAND_CHUNK_CELLS {
                for x in 0 ..< ISLAND_CHUNK_CELLS {
                    local_x := chunk.origin_x + f32(x) * cell_size
                    local_z := chunk.origin_z + f32(z) * cell_size
                    world_x, world_z := island_local_to_world(island.transform, local_x, local_z)
                    source = &source_levels[level]
                    if !level_contains(source, world_x, world_z) do source = &source_levels[CLIPMAP_LEVELS - 1]
                    chunk.heights[island_chunk_index(x, z)] = f16(sample_level_height(source, world_x, world_z))
                    chunk.material[island_chunk_index(x, z)] = i8(clamp(
                        math.round(sample_level_material(source, world_x, world_z) * ISLAND_MATERIAL_QUANTIZATION), -128, 127,
                    ))
                }
            }
            append(&island.chunks, chunk)
        }
    }
}

island_build_default_assets :: proc(
    project: ^Project,
    seeds: [len(DEFAULT_ISLAND_SEEDS)]u32,
) {
    if project == nil do return
    island_assets_destroy(&project.islands)
    signs := DEFAULT_ISLAND_SIGNS
    for seed, index in seeds {
        sign := signs[index]
        center_x, center_z := default_island_center(sign)
        island := Island_Asset{
            id = u64(index + 1),
            seed = seed,
            local_min_x = -DEFAULT_GENERATED_ISLAND_HALF_X,
            local_min_z = -DEFAULT_GENERATED_ISLAND_HALF_Z,
            local_max_x = DEFAULT_GENERATED_ISLAND_HALF_X,
            local_max_z = DEFAULT_GENERATED_ISLAND_HALF_Z,
            transform = island_transform_prepare({position_x = center_x, position_z = center_z, uniform_scale = 1}),
            revision = 1,
        }
        for level in 0 ..< ISLAND_BUILT_CLIPMAP_LEVELS {
            island_chunk_append_default(&island, level, FINE_CELL_SIZE * f32(u32(1) << u32(level)), &project.levels)
        }
        append(&project.islands, island)
    }
}

bathymetry_build_default :: proc(project: ^Project) {
    if project == nil do return
    delete(project.bathymetry_tiles)
    tile := Bathymetry_Tile{
        tile_x = 0,
        tile_z = 0,
        cell_size = 128,
        origin_x = -4096,
        origin_z = -4096,
    }
    source := &project.levels[CLIPMAP_LEVELS - 1]
    for z in 0 ..< BATHYMETRY_TILE_CELLS {
        for x in 0 ..< BATHYMETRY_TILE_CELLS {
            world_x := tile.origin_x + f32(x) * tile.cell_size
            world_z := tile.origin_z + f32(z) * tile.cell_size
            height := sample_level_height(source, world_x, world_z)
            index := z * BATHYMETRY_TILE_CELLS + x
            tile.depth[index] = max(project.sea_level - height, f32(0))
            tile.material[index] = tile.depth[index]
        }
    }
    append(&project.bathymetry_tiles, tile)
}

island_find :: proc(islands: []Island_Asset, id: u64) -> ^Island_Asset {
    if id == 0 do return nil
    for &island in islands do if island.id == id do return &island
    return nil
}

project_set_island_transform :: proc(project: ^Project, island_id: u64, transform: Island_Transform) -> bool {
    if project == nil || !island_transform_valid(transform) do return false
    prepared := island_transform_prepare(transform)
    island := island_find(project.islands[:], island_id)
    if island == nil do return false
    if island.transform == transform do return true
    island.transform = prepared
    island.revision += 1
    project.revision += 1
    return true
}

project_island_overlap :: proc(a, b: ^Island_Asset) -> bool {
    if a == nil || b == nil || a.id == b.id do return false
    // Conservative world-space AABB check. Rotated bounds are intentionally
    // rejected conservatively rather than allowing nondeterministic overlap.
    ax0, az0 := island_local_to_world(a.transform, a.local_min_x, a.local_min_z)
    ax1, az1 := island_local_to_world(a.transform, a.local_max_x, a.local_max_z)
    bx0, bz0 := island_local_to_world(b.transform, b.local_min_x, b.local_min_z)
    bx1, bz1 := island_local_to_world(b.transform, b.local_max_x, b.local_max_z)
    amin_x, amax_x := min(ax0, ax1), max(ax0, ax1)
    amin_z, amax_z := min(az0, az1), max(az0, az1)
    bmin_x, bmax_x := min(bx0, bx1), max(bx0, bx1)
    bmin_z, bmax_z := min(bz0, bz1), max(bz0, bz1)
    return amin_x < bmax_x && amax_x > bmin_x && amin_z < bmax_z && amax_z > bmin_z
}
