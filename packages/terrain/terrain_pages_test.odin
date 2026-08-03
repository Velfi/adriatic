package terrain

import "core:testing"
import "core:math"

@(test)
terrain_pages_omit_ocean_and_restore_land :: proc(t: ^testing.T) {
    project := new(Project)
    defer free_project(project)
    project.sea_level = 0
    for &level in project.levels {
        level.cell_size = 1
        level.origin_x = -256
        level.origin_z = -256
    }
    project.levels[0].heights[sample_index(12, 13)] = 4
    terrain_pages_rebuild(project)
    testing.expect(t, len(project.terrain_pages) == 1)
    project.levels = {}
    testing.expect(t, terrain_pages_restore(project))
    testing.expect_value(t, project.levels[0].heights[sample_index(12, 13)], f32(4))
}

@(test)
terrain_pages_rebuild_replaces_freed_page_storage :: proc(t: ^testing.T) {
    project := new(Project)
    defer free_project(project)
    project.sea_level = 0
    for &level in project.levels {
        level.cell_size = 1
        level.origin_x = -256
        level.origin_z = -256
    }
    project.levels[0].heights[sample_index(12, 13)] = 4

    terrain_pages_rebuild(project)
    testing.expect_value(t, len(project.terrain_pages), 1)
    terrain_pages_rebuild(project)
    testing.expect_value(t, len(project.terrain_pages), 1)
}

@(test)
terrain_pages_restore_omitted_ocean_at_negative_sea_level :: proc(t: ^testing.T) {
    project := new(Project)
    defer free_project(project)
    project.sea_level = -20
    for &level in project.levels {
        level.cell_size = 1
        level.origin_x = -256
        level.origin_z = -256
        for &height in level.heights do height = project.sea_level
    }
    project.levels[0].heights[sample_index(12, 13)] = -10
    terrain_pages_rebuild(project)
    project.levels = {}
    testing.expect(t, terrain_pages_restore(project))
    testing.expect_value(t, project.levels[0].heights[sample_index(200, 200)], f32(-20))
    _, _, ocean_is_land := sample_land(project, 0, -56, -56)
    testing.expect(t, !ocean_is_land)
}

@(test)
terrain_pages_mixed_page_classifies_each_sample :: proc(t: ^testing.T) {
    project := new(Project)
    defer free_project(project)
    project.sea_level = 0
    project.island_transforms = default_island_transforms()
    for &level in project.levels {
        level.cell_size = 1
        level.origin_x = -256
        level.origin_z = -256
    }
    project.levels[0].heights[sample_index(17, 19)] = 4
    terrain_pages_rebuild(project)
    land_x, land_z := f32(-256 + 17), f32(-256 + 19)
    ocean_x, ocean_z := f32(-256 + 2), f32(-256 + 3)
    _, _, land_found := sample_land(project, 0, land_x, land_z)
    _, _, ocean_found := sample_land(project, 0, ocean_x, ocean_z)
    testing.expect(t, land_found)
    testing.expect(t, !ocean_found)
    testing.expect_value(t, sample_surface(project, 0, ocean_x, ocean_z), Surface_Kind.Deep_Ocean)
}

@(test)
terrain_pages_reject_duplicate_and_out_of_bounds_keys :: proc(t: ^testing.T) {
    project := new(Project)
    defer free_project(project)
    for &layout in project.terrain_level_layout do layout.cell_size = 1
    append(&project.terrain_pages, Terrain_Page{}, Terrain_Page{})
    testing.expect(t, !terrain_pages_restore(project))
    clear(&project.terrain_pages)
    append(&project.terrain_pages, Terrain_Page{page_x = u8(TERRAIN_RESOLUTION / TERRAIN_PAGE_RESOLUTION)})
    testing.expect(t, !terrain_pages_restore(project))
}

@(test)
bathymetry_missing_chunk_is_deep_ocean :: proc(t: ^testing.T) {
    project := new(Project)
    defer free_project(project)
    project.sea_level = 3
    sample := sample_water_interface(project, 5000, 5000)
    testing.expect_value(t, sample.depth, DEEP_OCEAN_DEPTH)
    testing.expect_value(t, sample_surface(project, 0, 5000, 5000), Surface_Kind.Deep_Ocean)
}

@(test)
bathymetry_chunk_is_not_land :: proc(t: ^testing.T) {
    project := new(Project)
    defer free_project(project)
    project.sea_level = 0
    chunk := Bathymetry_Chunk{
        chunk_x = 0,
        chunk_z = 0,
        heights = make([dynamic]f16, BATHYMETRY_CHUNK_SAMPLES),
        material = make([dynamic]i8, BATHYMETRY_CHUNK_SAMPLES),
    }
    for &height in chunk.heights do height = -6
    append(&project.bathymetry_chunks, chunk)
    sample := sample_water_interface(project, 12, 12)
    testing.expect_value(t, sample.depth, f32(6))
    testing.expect_value(t, sample_surface(project, 0, 12, 12), Surface_Kind.Bathymetry)
}

@(test)
bathymetry_level_edits_the_bed_instead_of_the_water_surface :: proc(t: ^testing.T) {
    project := new(Project)
    defer free_project(project)
    project.sea_level = 2
    chunk := Bathymetry_Chunk{
        heights = make([dynamic]f16, BATHYMETRY_CHUNK_SAMPLES),
        material = make([dynamic]i8, BATHYMETRY_CHUNK_SAMPLES),
    }
    for &height in chunk.heights do height = -4
    append(&project.bathymetry_chunks, chunk)
    terrain_sampling_lookup_rebuild(project)
    apply_bathymetry_level(project, 16, 16, 8, -7, 0)
    bed, _, source, found := sample_bathymetry(project, 16, 16)
    testing.expect(t, found)
    testing.expect_value(t, bed, f32(-7))
    testing.expect_value(t, source, Water_Source_Kind.Harbor)
    testing.expect_value(t, sample_surface_height(project, 0, 16, 16), f32(2))
}

@(test)
bathymetry_is_bilinear_and_rejects_incomplete_material :: proc(t: ^testing.T) {
    project := new(Project)
    defer free_project(project)
    project.island_transforms = default_island_transforms()
    chunk := Bathymetry_Chunk{
        heights = make([dynamic]f16, BATHYMETRY_CHUNK_SAMPLES),
        material = make([dynamic]i8, BATHYMETRY_CHUNK_SAMPLES),
    }
    chunk.heights[0] = -8
    chunk.heights[1] = -4
    chunk.heights[BATHYMETRY_CHUNK_RESOLUTION] = -4
    chunk.heights[BATHYMETRY_CHUNK_RESOLUTION + 1] = 0
    append(&project.bathymetry_chunks, chunk)
    terrain_sampling_lookup_rebuild(project)
    bed, _, _, found := sample_bathymetry(project, 4, 4)
    testing.expect(t, found)
    testing.expect(t, abs(bed - f32(-4)) < .01)
    resize(&project.bathymetry_chunks[0].material, BATHYMETRY_CHUNK_SAMPLES - 1)
    _, _, _, malformed_found := sample_bathymetry(project, 4, 4)
    testing.expect(t, !malformed_found)
}

@(test)
bathymetry_follows_moved_island_owner :: proc(t: ^testing.T) {
    project := new(Project)
    defer free_project(project)
    project.island_transforms = default_island_transforms()
    source_x, source_z := project.island_transforms[0].source_x, project.island_transforms[0].source_z
    chunk_x := i32(math.floor(f64(source_x / BATHYMETRY_CHUNK_SIZE)))
    chunk_z := i32(math.floor(f64(source_z / BATHYMETRY_CHUNK_SIZE)))
    chunk := Bathymetry_Chunk{
        chunk_x = chunk_x,
        chunk_z = chunk_z,
        owner = .West,
        heights = make([dynamic]f16, BATHYMETRY_CHUNK_SAMPLES),
        material = make([dynamic]i8, BATHYMETRY_CHUNK_SAMPLES),
    }
    for &height in chunk.heights do height = -7
    append(&project.bathymetry_chunks, chunk)
    terrain_sampling_lookup_rebuild(project)
    project.island_transforms[0].current_x += 96
    project.island_transforms[0].current_z -= 64
    bed, _, _, found := sample_bathymetry(project, source_x + 96, source_z - 64)
    testing.expect(t, found)
    testing.expect_value(t, bed, f32(-7))
}

@(test)
bathymetry_negative_chunk_and_shared_edge_are_deterministic :: proc(t: ^testing.T) {
    project := new(Project)
    defer free_project(project)
    project.island_transforms = default_island_transforms()
    for chunk_x in -1 ..= 0 {
        chunk := Bathymetry_Chunk{
            chunk_x = i32(chunk_x),
            heights = make([dynamic]f16, BATHYMETRY_CHUNK_SAMPLES),
            material = make([dynamic]i8, BATHYMETRY_CHUNK_SAMPLES),
        }
        for &height in chunk.heights do height = -5
        append(&project.bathymetry_chunks, chunk)
    }
    terrain_sampling_lookup_rebuild(project)
    left, _, _, left_found := sample_bathymetry(project, -.001, 8)
    edge, _, _, edge_found := sample_bathymetry(project, 0, 8)
    testing.expect(t, left_found && edge_found)
    testing.expect_value(t, left, f32(-5))
    testing.expect_value(t, edge, f32(-5))
}

@(test)
surface_height_uses_water_interface_when_land_is_absent :: proc(t: ^testing.T) {
    project := new(Project)
    defer free_project(project)
    project.sea_level = 3
    project.island_transforms = default_island_transforms()
    testing.expect_value(t, sample_surface_height(project, 0, 9000, 9000), f32(3))
    testing.expect_value(t, sample_surface(project, 0, 9000, 9000), Surface_Kind.Deep_Ocean)
}

@(test)
bathymetry_world_fallback_uses_world_coordinates :: proc(t: ^testing.T) {
    project := new(Project)
    defer free_project(project)
    project.island_transforms = default_island_transforms()
    project.island_transforms[0].current_x = 0
    project.island_transforms[0].current_z = 0
    chunk := Bathymetry_Chunk{
        owner = .World,
        heights = make([dynamic]f16, BATHYMETRY_CHUNK_SAMPLES),
        material = make([dynamic]i8, BATHYMETRY_CHUNK_SAMPLES),
    }
    for z in 0 ..< BATHYMETRY_CHUNK_RESOLUTION {
        for x in 0 ..< BATHYMETRY_CHUNK_RESOLUTION {
            chunk.heights[z * BATHYMETRY_CHUNK_RESOLUTION + x] = f16(-f32(x))
        }
    }
    append(&project.bathymetry_chunks, chunk)
    terrain_sampling_lookup_rebuild(project)
    bed, _, _, found := sample_bathymetry(project, 12, 12)
    testing.expect(t, found)
    testing.expect(t, abs(bed - f32(-1.5)) < .01)
}

@(test)
bathymetry_owned_chunk_resolves_outside_island_ellipse :: proc(t: ^testing.T) {
    project := new(Project)
    defer free_project(project)
    project.island_transforms = default_island_transforms()
    source_x := project.island_transforms[0].source_x - DEFAULT_GENERATED_ISLAND_HALF_X - 220
    source_z := project.island_transforms[0].source_z
    chunk := Bathymetry_Chunk{
        chunk_x = i32(math.floor(f64(source_x / BATHYMETRY_CHUNK_SIZE))),
        chunk_z = i32(math.floor(f64(source_z / BATHYMETRY_CHUNK_SIZE))),
        owner = .West,
        heights = make([dynamic]f16, BATHYMETRY_CHUNK_SAMPLES),
        material = make([dynamic]i8, BATHYMETRY_CHUNK_SAMPLES),
    }
    for &height in chunk.heights do height = -9
    append(&project.bathymetry_chunks, chunk)
    terrain_sampling_lookup_rebuild(project)
    _, island_owned := island_index(island_at(project, source_x, source_z))
    testing.expect(t, !island_owned)
    bed, _, _, found := sample_bathymetry(project, source_x, source_z)
    testing.expect(t, found)
    testing.expect_value(t, bed, f32(-9))
}

@(test)
default_bathymetry_covers_near_and_distant_islands :: proc(t: ^testing.T) {
    project := new(Project)
    defer free_project(project)
    project.island_transforms = default_island_transforms()
    bathymetry_build_default(project)
    for transform in project.island_transforms {
        _, _, _, center_found := sample_bathymetry(project, transform.current_x, transform.current_z)
        _, _, _, offshore_found := sample_bathymetry(
            project,
            transform.current_x + DEFAULT_GENERATED_ISLAND_HALF_X + 200,
            transform.current_z,
        )
        testing.expect(t, center_found)
        testing.expect(t, offshore_found)
    }
}
