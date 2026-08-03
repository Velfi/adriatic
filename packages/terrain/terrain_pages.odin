package terrain

import "core:math"

TERRAIN_PAGE_RESOLUTION :: 32
TERRAIN_PAGE_SAMPLES :: TERRAIN_PAGE_RESOLUTION * TERRAIN_PAGE_RESOLUTION
BATHYMETRY_CHUNK_RESOLUTION :: 33
BATHYMETRY_CHUNK_SAMPLES :: BATHYMETRY_CHUNK_RESOLUTION * BATHYMETRY_CHUNK_RESOLUTION
BATHYMETRY_CHUNK_SIZE :: f32(256)
DEEP_OCEAN_DEPTH :: f32(64)
SHORELINE_EPSILON :: f32(.01)

Terrain_Level_Layout :: struct { cell_size, origin_x, origin_z: f32 }
Terrain_Page :: struct {
    level, page_x, page_z: u8,
    heights: [TERRAIN_PAGE_SAMPLES]f32,
    material: [TERRAIN_PAGE_SAMPLES]f32,
}
Water_Source_Kind :: enum { Ocean, Harbor, River }
Bathymetry_Chunk :: struct {
    chunk_x, chunk_z: i32,
    owner: Island_ID,
    revision: u64,
    source: Water_Source_Kind,
    heights: [dynamic]f16,
    material: [dynamic]i8,
}
Surface_Kind :: enum { Land, Bathymetry, Deep_Ocean }
Water_Interface_Sample :: struct {
    kind: Water_Source_Kind,
    water_level, depth: f32,
    shore_distance: f32,
    shore_normal: [2]f32,
}

terrain_pages_rebuild :: proc(project: ^Project) {
    if project == nil do return
    delete(project.terrain_pages)
    for level, level_index in project.levels {
        project.terrain_level_layout[level_index] = {level.cell_size, level.origin_x, level.origin_z}
        pages_axis := TERRAIN_RESOLUTION / TERRAIN_PAGE_RESOLUTION
        for page_z in 0 ..< pages_axis {
            for page_x in 0 ..< pages_axis {
            keep := false
            for z in 0 ..< TERRAIN_PAGE_RESOLUTION {
                for x in 0 ..< TERRAIN_PAGE_RESOLUTION {
                if level.heights[sample_index(page_x * TERRAIN_PAGE_RESOLUTION + x, page_z * TERRAIN_PAGE_RESOLUTION + z)] > project.sea_level + SHORELINE_EPSILON do keep = true
                }
            }
            if !keep do continue
            page := Terrain_Page{level = u8(level_index), page_x = u8(page_x), page_z = u8(page_z)}
            for z in 0 ..< TERRAIN_PAGE_RESOLUTION {
                for x in 0 ..< TERRAIN_PAGE_RESOLUTION {
                source := sample_index(page_x * TERRAIN_PAGE_RESOLUTION + x, page_z * TERRAIN_PAGE_RESOLUTION + z)
                page.heights[z * TERRAIN_PAGE_RESOLUTION + x] = level.heights[source]
                page.material[z * TERRAIN_PAGE_RESOLUTION + x] = level.material[source]
                }
            }
            append(&project.terrain_pages, page)
            }
        }
    }
    terrain_sampling_lookup_rebuild(project)
}

terrain_pages_restore :: proc(project: ^Project) -> bool {
    if project == nil do return false
    project.levels = {}
    for layout, level_index in project.terrain_level_layout {
        if layout.cell_size <= 0 do return false
        project.levels[level_index].cell_size = layout.cell_size
        project.levels[level_index].origin_x = layout.origin_x
        project.levels[level_index].origin_z = layout.origin_z
        for &height in project.levels[level_index].heights do height = project.sea_level
    }
    pages_axis := TERRAIN_RESOLUTION / TERRAIN_PAGE_RESOLUTION
    seen := make(map[[3]i32]bool)
    defer delete(seen)
    for page in project.terrain_pages {
        if int(page.level) >= CLIPMAP_LEVELS || int(page.page_x) >= pages_axis || int(page.page_z) >= pages_axis do return false
        key := [3]i32{i32(page.level), i32(page.page_x), i32(page.page_z)}
        if seen[key] do return false
        seen[key] = true
        level := &project.levels[int(page.level)]
        for z in 0 ..< TERRAIN_PAGE_RESOLUTION {
            for x in 0 ..< TERRAIN_PAGE_RESOLUTION {
            destination := sample_index(int(page.page_x) * TERRAIN_PAGE_RESOLUTION + x, int(page.page_z) * TERRAIN_PAGE_RESOLUTION + z)
            source := z * TERRAIN_PAGE_RESOLUTION + x
            level.heights[destination] = page.heights[source]
            level.material[destination] = page.material[source]
            }
        }
    }
    terrain_sampling_lookup_rebuild(project)
    return true
}

apply_bathymetry_level :: proc(
    project: ^Project,
    world_x, world_z, radius, target_height, feather: f32,
    source := Water_Source_Kind.Harbor,
) {
    if project == nil || radius <= 0 do return
    outer := radius + max(feather, f32(0))
    for &chunk in project.bathymetry_chunks {
        if len(chunk.heights) != BATHYMETRY_CHUNK_SAMPLES do continue
        translation_x, translation_z: f32
        if owner_index, owned := island_index(chunk.owner); owned {
            transform := island_transform_at(project, owner_index)
            translation_x = transform.current_x - transform.source_x
            translation_z = transform.current_z - transform.source_z
        }
        origin_x := f32(chunk.chunk_x) * BATHYMETRY_CHUNK_SIZE
        origin_z := f32(chunk.chunk_z) * BATHYMETRY_CHUNK_SIZE
        cell := BATHYMETRY_CHUNK_SIZE / f32(BATHYMETRY_CHUNK_RESOLUTION - 1)
        chunk_changed := false
        for z in 0 ..< BATHYMETRY_CHUNK_RESOLUTION {
            for x in 0 ..< BATHYMETRY_CHUNK_RESOLUTION {
                sample_x := origin_x + f32(x) * cell + translation_x
                sample_z := origin_z + f32(z) * cell + translation_z
                dx, dz := sample_x - world_x, sample_z - world_z
                distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
                if distance > outer do continue
                weight := distance <= radius ? f32(1) : 1 - (distance - radius) / max(feather, f32(.001))
                index := z * BATHYMETRY_CHUNK_RESOLUTION + x
                current := f32(chunk.heights[index])
                chunk.heights[index] = f16(current + (target_height - current) * weight)
                chunk_changed = true
            }
        }
        if chunk_changed {
            chunk.source = source
            chunk.revision += 1
        }
    }
}

terrain_sampling_lookup_rebuild :: proc(project: ^Project) {
    if project == nil do return
    delete(project.terrain_page_lookup)
    delete(project.bathymetry_chunk_lookup)
    project.terrain_page_lookup = make(map[[3]i32]int, len(project.terrain_pages))
    project.bathymetry_chunk_lookup = make(map[[3]i32]int, len(project.bathymetry_chunks))
    for page, index in project.terrain_pages {
        project.terrain_page_lookup[[3]i32{i32(page.level), i32(page.page_x), i32(page.page_z)}] = index
    }
    for chunk, index in project.bathymetry_chunks {
        project.bathymetry_chunk_lookup[[3]i32{i32(chunk.owner), chunk.chunk_x, chunk.chunk_z}] = index
    }
}

terrain_page_indices_in_bounds :: proc(project: ^Project, level: int, min_x, min_z, max_x, max_z: f32, result: []int) -> int {
    if project == nil || level < 0 || level >= CLIPMAP_LEVELS do return 0
    layout := project.terrain_level_layout[level]
    extent := f32(TERRAIN_PAGE_RESOLUTION) * layout.cell_size
    count := 0
    for page, index in project.terrain_pages {
        if int(page.level) != level do continue
        px := layout.origin_x + f32(page.page_x) * extent
        pz := layout.origin_z + f32(page.page_z) * extent
        if px > max_x || pz > max_z || px + extent < min_x || pz + extent < min_z do continue
        if count < len(result) do result[count] = index
        count += 1
    }
    return count
}

bathymetry_chunk_at_source :: proc(project: ^Project, owner: Island_ID, x, z: f32) -> ^Bathymetry_Chunk {
    if project == nil do return nil
    cx := i32(math.floor(f64(x / BATHYMETRY_CHUNK_SIZE)))
    cz := i32(math.floor(f64(z / BATHYMETRY_CHUNK_SIZE)))
    if len(project.bathymetry_chunk_lookup) != len(project.bathymetry_chunks) do terrain_sampling_lookup_rebuild(project)
    if index, found := project.bathymetry_chunk_lookup[[3]i32{i32(owner), cx, cz}]; found && index >= 0 && index < len(project.bathymetry_chunks) {
        return &project.bathymetry_chunks[index]
    }
    return nil
}

sample_bathymetry :: proc(project: ^Project, x, z: f32) -> (bed_height, material: f32, source: Water_Source_Kind, found: bool) {
    if project == nil do return
    source_x, source_z := x, z
    chunk: ^Bathymetry_Chunk
    for _, island_index in project.island_transforms {
        transform := island_transform_at(project, island_index)
        candidate_x := x - (transform.current_x - transform.source_x)
        candidate_z := z - (transform.current_z - transform.source_z)
        owner := island_id_from_index(island_index)
        candidate := bathymetry_chunk_at_source(project, owner, candidate_x, candidate_z)
        if candidate == nil do continue
        chunk, source_x, source_z = candidate, candidate_x, candidate_z
        break
    }
    if chunk == nil {
        chunk = bathymetry_chunk_at_source(project, .World, x, z)
        source_x, source_z = x, z
    }
    if chunk == nil || len(chunk.heights) != BATHYMETRY_CHUNK_SAMPLES || len(chunk.material) != BATHYMETRY_CHUNK_SAMPLES do return
    ox, oz := f32(chunk.chunk_x) * BATHYMETRY_CHUNK_SIZE, f32(chunk.chunk_z) * BATHYMETRY_CHUNK_SIZE
    cell := BATHYMETRY_CHUNK_SIZE / f32(BATHYMETRY_CHUNK_RESOLUTION - 1)
    gx := clamp((source_x - ox) / cell, f32(0), f32(BATHYMETRY_CHUNK_RESOLUTION - 1))
    gz := clamp((source_z - oz) / cell, f32(0), f32(BATHYMETRY_CHUNK_RESOLUTION - 1))
    x0, z0 := int(math.floor(f64(gx))), int(math.floor(f64(gz)))
    x1, z1 := min(x0 + 1, BATHYMETRY_CHUNK_RESOLUTION - 1), min(z0 + 1, BATHYMETRY_CHUNK_RESOLUTION - 1)
    tx, tz := gx - f32(x0), gz - f32(z0)
    i00, i10 := z0 * BATHYMETRY_CHUNK_RESOLUTION + x0, z0 * BATHYMETRY_CHUNK_RESOLUTION + x1
    i01, i11 := z1 * BATHYMETRY_CHUNK_RESOLUTION + x0, z1 * BATHYMETRY_CHUNK_RESOLUTION + x1
    top := f32(chunk.heights[i00]) + (f32(chunk.heights[i10]) - f32(chunk.heights[i00])) * tx
    bottom := f32(chunk.heights[i01]) + (f32(chunk.heights[i11]) - f32(chunk.heights[i01])) * tx
    material_top := f32(chunk.material[i00]) + (f32(chunk.material[i10]) - f32(chunk.material[i00])) * tx
    material_bottom := f32(chunk.material[i01]) + (f32(chunk.material[i11]) - f32(chunk.material[i01])) * tx
    return top + (bottom - top) * tz, (material_top + (material_bottom - material_top) * tz) / 63, chunk.source, true
}

sample_surface :: proc(project: ^Project, level: int, x, z: f32) -> Surface_Kind {
    _, _, land := sample_land(project, level, x, z)
    if land do return .Land
    _, _, _, bathymetry := sample_bathymetry(project, x, z)
    return bathymetry ? .Bathymetry : .Deep_Ocean
}

sample_water_interface :: proc(project: ^Project, x, z: f32) -> Water_Interface_Sample {
    result := Water_Interface_Sample{}
    if project == nil do return result
    result.water_level = project.sea_level
    if bed, _, source, found := sample_bathymetry(project, x, z); found {
        result.kind, result.depth = source, max(project.sea_level - bed, 0)
    } else {
        result.depth = DEEP_OCEAN_DEPTH
    }
    center, center_found := sample_authored_field_height(project, 0, x, z)
    if center_found {
        step := max(project.levels[0].cell_size, f32(1))
        west, west_found := sample_authored_field_height(project, 0, x - step, z)
        east, east_found := sample_authored_field_height(project, 0, x + step, z)
        north, north_found := sample_authored_field_height(project, 0, x, z - step)
        south, south_found := sample_authored_field_height(project, 0, x, z + step)
        if west_found && east_found && north_found && south_found {
            dx, dz := (east - west) / (step * 2), (south - north) / (step * 2)
            gradient := f32(math.sqrt(f64(dx * dx + dz * dz)))
            if gradient > .0001 {
                result.shore_normal = {dx / gradient, dz / gradient}
                result.shore_distance = (center - project.sea_level) / gradient
            }
        }
    }
    return result
}

bathymetry_destroy :: proc(chunks: ^[dynamic]Bathymetry_Chunk) {
    if chunks == nil do return
    for &chunk in chunks^ { delete(chunk.heights); delete(chunk.material) }
    delete(chunks^)
}

bathymetry_append_default_chunk :: proc(project: ^Project, owner: Island_ID, chunk_x, chunk_z: i32) {
    if project == nil || owner == .World do return
    chunk := Bathymetry_Chunk{
        chunk_x = chunk_x,
        chunk_z = chunk_z,
        owner = owner,
        source = .Ocean,
        revision = 1,
        heights = make([dynamic]f16, BATHYMETRY_CHUNK_SAMPLES),
        material = make([dynamic]i8, BATHYMETRY_CHUNK_SAMPLES),
    }
    origin_x := f32(chunk_x) * BATHYMETRY_CHUNK_SIZE
    origin_z := f32(chunk_z) * BATHYMETRY_CHUNK_SIZE
    cell := BATHYMETRY_CHUNK_SIZE / f32(BATHYMETRY_CHUNK_RESOLUTION - 1)
    for z in 0 ..< BATHYMETRY_CHUNK_RESOLUTION {
        for x in 0 ..< BATHYMETRY_CHUNK_RESOLUTION {
            source_x, source_z := origin_x + f32(x) * cell, origin_z + f32(z) * cell
            height, material, found := sample_authored_field_raw(project, 0, source_x, source_z)
            if !found {
                height, material = project.sea_level - DEEP_OCEAN_DEPTH, 0
            }
            index := z * BATHYMETRY_CHUNK_RESOLUTION + x
            chunk.heights[index] = f16(min(height, project.sea_level - 1))
            chunk.material[index] = i8(clamp(int(math.round(f64(material * 63))), -127, 127))
        }
    }
    append(&project.bathymetry_chunks, chunk)
}

bathymetry_build_default :: proc(project: ^Project) {
    if project == nil do return
    bathymetry_destroy(&project.bathymetry_chunks)
    // Bathymetry residency follows island ownership, not clipmap residency.
    // Level zero is localized around the gameplay island, so deriving chunks
    // from its pages leaves the distant island without a seabed.
    for transform, island_index in project.island_transforms {
        owner := island_id_from_index(island_index)
        extent_x := DEFAULT_GENERATED_ISLAND_HALF_X + 180
        extent_z := DEFAULT_GENERATED_ISLAND_HALF_Z + 180
        min_chunk_x := i32(math.floor(f64((transform.source_x - extent_x) / BATHYMETRY_CHUNK_SIZE))) - 1
        max_chunk_x := i32(math.floor(f64((transform.source_x + extent_x) / BATHYMETRY_CHUNK_SIZE))) + 1
        min_chunk_z := i32(math.floor(f64((transform.source_z - extent_z) / BATHYMETRY_CHUNK_SIZE))) - 1
        max_chunk_z := i32(math.floor(f64((transform.source_z + extent_z) / BATHYMETRY_CHUNK_SIZE))) + 1
        for chunk_z in min_chunk_z ..= max_chunk_z {
            for chunk_x in min_chunk_x ..= max_chunk_x {
                bathymetry_append_default_chunk(project, owner, chunk_x, chunk_z)
            }
        }
    }
    terrain_sampling_lookup_rebuild(project)
}
