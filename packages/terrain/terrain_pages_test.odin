package terrain

import "core:testing"

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
