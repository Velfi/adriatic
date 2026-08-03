package terrain

import "core:math"

TERRAIN_PAGE_RESOLUTION :: 32
TERRAIN_PAGE_SAMPLES :: TERRAIN_PAGE_RESOLUTION * TERRAIN_PAGE_RESOLUTION
BATHYMETRY_CHUNK_RESOLUTION :: 33
BATHYMETRY_CHUNK_SAMPLES :: BATHYMETRY_CHUNK_RESOLUTION * BATHYMETRY_CHUNK_RESOLUTION
BATHYMETRY_CHUNK_SIZE :: f32(256)
DEEP_OCEAN_DEPTH :: f32(64)

Terrain_Level_Layout :: struct { cell_size, origin_x, origin_z: f32 }
Terrain_Page :: struct {
    level, page_x, page_z: u8,
    heights: [TERRAIN_PAGE_SAMPLES]f32,
    material: [TERRAIN_PAGE_SAMPLES]f32,
}
Water_Source_Kind :: enum { Ocean, Harbor, River }
Bathymetry_Chunk :: struct {
    chunk_x, chunk_z: i32,
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
                if level.heights[sample_index(page_z * TERRAIN_PAGE_RESOLUTION + z, page_x * TERRAIN_PAGE_RESOLUTION + x)] > project.sea_level + .01 do keep = true
                }
            }
            if !keep do continue
            page := Terrain_Page{level = u8(level_index), page_x = u8(page_x), page_z = u8(page_z)}
            for z in 0 ..< TERRAIN_PAGE_RESOLUTION {
                for x in 0 ..< TERRAIN_PAGE_RESOLUTION {
                source := sample_index(page_z * TERRAIN_PAGE_RESOLUTION + z, page_x * TERRAIN_PAGE_RESOLUTION + x)
                page.heights[z * TERRAIN_PAGE_RESOLUTION + x] = level.heights[source]
                page.material[z * TERRAIN_PAGE_RESOLUTION + x] = level.material[source]
                }
            }
            append(&project.terrain_pages, page)
            }
        }
    }
}

terrain_pages_restore :: proc(project: ^Project) -> bool {
    if project == nil do return false
    project.levels = {}
    for layout, level_index in project.terrain_level_layout {
        if layout.cell_size <= 0 do return false
        project.levels[level_index].cell_size = layout.cell_size
        project.levels[level_index].origin_x = layout.origin_x
        project.levels[level_index].origin_z = layout.origin_z
    }
    for page in project.terrain_pages {
        level := &project.levels[int(page.level)]
        for z in 0 ..< TERRAIN_PAGE_RESOLUTION {
            for x in 0 ..< TERRAIN_PAGE_RESOLUTION {
            destination := sample_index(int(page.page_z) * TERRAIN_PAGE_RESOLUTION + z, int(page.page_x) * TERRAIN_PAGE_RESOLUTION + x)
            source := z * TERRAIN_PAGE_RESOLUTION + x
            level.heights[destination] = page.heights[source]
            level.material[destination] = page.material[source]
            }
        }
    }
    return true
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

bathymetry_chunk_at :: proc(project: ^Project, x, z: f32) -> ^Bathymetry_Chunk {
    if project == nil do return nil
    cx := i32(math.floor(f64(x / BATHYMETRY_CHUNK_SIZE)))
    cz := i32(math.floor(f64(z / BATHYMETRY_CHUNK_SIZE)))
    for &chunk in project.bathymetry_chunks do if chunk.chunk_x == cx && chunk.chunk_z == cz do return &chunk
    return nil
}

sample_bathymetry :: proc(project: ^Project, x, z: f32) -> (bed_height, material: f32, source: Water_Source_Kind, found: bool) {
    chunk := bathymetry_chunk_at(project, x, z)
    if chunk == nil || len(chunk.heights) != BATHYMETRY_CHUNK_SAMPLES do return
    ox, oz := f32(chunk.chunk_x) * BATHYMETRY_CHUNK_SIZE, f32(chunk.chunk_z) * BATHYMETRY_CHUNK_SIZE
    cell := BATHYMETRY_CHUNK_SIZE / f32(BATHYMETRY_CHUNK_RESOLUTION - 1)
    sx := clamp(int(math.floor(f64((x - ox) / cell))), 0, BATHYMETRY_CHUNK_RESOLUTION - 1)
    sz := clamp(int(math.floor(f64((z - oz) / cell))), 0, BATHYMETRY_CHUNK_RESOLUTION - 1)
    index := sz * BATHYMETRY_CHUNK_RESOLUTION + sx
    return f32(chunk.heights[index]), f32(chunk.material[index]) / 63, chunk.source, true
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
    return result
}

bathymetry_destroy :: proc(chunks: ^[dynamic]Bathymetry_Chunk) {
    if chunks == nil do return
    for &chunk in chunks^ { delete(chunk.heights); delete(chunk.material) }
    delete(chunks^)
}

bathymetry_build_default :: proc(project: ^Project) {
    if project == nil do return
    bathymetry_destroy(&project.bathymetry_chunks)
    extent := f32(TERRAIN_RESOLUTION - 1) * project.levels[CLIPMAP_LEVELS - 1].cell_size
    for cz in -1 ..= 1 {
        for cx in -1 ..= 1 {
        chunk := Bathymetry_Chunk{chunk_x = i32(cx), chunk_z = i32(cz), source = .Ocean, revision = 1}
        chunk.heights = make([dynamic]f16, BATHYMETRY_CHUNK_SAMPLES)
        chunk.material = make([dynamic]i8, BATHYMETRY_CHUNK_SAMPLES)
        origin_x := f32(cx) * BATHYMETRY_CHUNK_SIZE
        origin_z := f32(cz) * BATHYMETRY_CHUNK_SIZE
        for z in 0 ..< BATHYMETRY_CHUNK_RESOLUTION {
            for x in 0 ..< BATHYMETRY_CHUNK_RESOLUTION {
            world_x, world_z := origin_x + f32(x) * BATHYMETRY_CHUNK_SIZE / f32(BATHYMETRY_CHUNK_RESOLUTION - 1), origin_z + f32(z) * BATHYMETRY_CHUNK_SIZE / f32(BATHYMETRY_CHUNK_RESOLUTION - 1)
            height := sample_level_height(&project.levels[CLIPMAP_LEVELS - 1], clamp(world_x, -extent, extent), clamp(world_z, -extent, extent))
            index := z * BATHYMETRY_CHUNK_RESOLUTION + x
            chunk.heights[index] = f16(min(height, project.sea_level - 1))
            chunk.material[index] = 0
            }
        }
        append(&project.bathymetry_chunks, chunk)
        }
    }
}
