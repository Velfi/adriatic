package terrain

import "core:testing"

bathymetry_refresh_test_project :: proc() -> ^Project {
    project := new(Project)
    project.sea_level = 0
    for &level in project.levels {
        level.cell_size = 1
        level.origin_x = 0
        level.origin_z = 0
        for &height in level.heights do height = -6
    }
    return project
}

bathymetry_refresh_test_chunk :: proc(chunk_x: i32, source := Water_Source_Kind.Ocean) -> Bathymetry_Chunk {
    chunk := Bathymetry_Chunk {
        chunk_x  = chunk_x,
        source   = source,
        revision = 9,
        heights  = make([dynamic]f16, BATHYMETRY_CHUNK_SAMPLES),
        material = make([dynamic]i8, BATHYMETRY_CHUNK_SAMPLES),
    }
    for &height in chunk.heights do height = -20
    return chunk
}

@(test)
bathymetry_refresh_is_bounded_and_advances_revision_once :: proc(t: ^testing.T) {
    project := bathymetry_refresh_test_project()
    defer free_project(project)
    append(&project.bathymetry_chunks, bathymetry_refresh_test_chunk(0), bathymetry_refresh_test_chunk(1))
    project.levels[0].heights[sample_index(8, 8)] = -3

    refreshed := bathymetry_refresh_generated_bounds(project, 7, 7, 9, 9)

    testing.expect_value(t, refreshed, 1)
    testing.expect_value(t, f32(project.bathymetry_chunks[0].heights[BATHYMETRY_CHUNK_RESOLUTION + 1]), f32(-3))
    testing.expect_value(t, project.bathymetry_chunks[0].revision, u64(10))
    testing.expect_value(t, project.bathymetry_chunks[1].revision, u64(9))
}

@(test)
bathymetry_refresh_preserves_authored_chunk :: proc(t: ^testing.T) {
    project := bathymetry_refresh_test_project()
    defer free_project(project)
    append(&project.bathymetry_chunks, bathymetry_refresh_test_chunk(0, .Harbor))

    refreshed := bathymetry_refresh_generated_bounds(project, 0, 0, 32, 32)

    testing.expect_value(t, refreshed, 0)
    testing.expect_value(t, f32(project.bathymetry_chunks[0].heights[0]), f32(-20))
    testing.expect_value(t, project.bathymetry_chunks[0].revision, u64(9))
}

@(test)
bathymetry_refresh_tracks_coast_advance_and_retreat :: proc(t: ^testing.T) {
    project := bathymetry_refresh_test_project()
    defer free_project(project)
    append(&project.bathymetry_chunks, bathymetry_refresh_test_chunk(0))
    sample := sample_index(8, 8)
    bed := BATHYMETRY_CHUNK_RESOLUTION + 1

    project.levels[0].heights[sample] = 3
    testing.expect_value(t, bathymetry_refresh_generated_bounds(project, 8, 8, 8, 8), 1)
    testing.expect_value(t, f32(project.bathymetry_chunks[0].heights[bed]), f32(-1))
    testing.expect_value(t, project.bathymetry_chunks[0].revision, u64(10))

    project.levels[0].heights[sample] = -4
    testing.expect_value(t, bathymetry_refresh_generated_bounds(project, 8, 8, 8, 8), 1)
    testing.expect_value(t, f32(project.bathymetry_chunks[0].heights[bed]), f32(-4))
    testing.expect_value(t, project.bathymetry_chunks[0].revision, u64(11))
}

@(test)
bathymetry_refresh_keeps_shared_chunk_edge_equal :: proc(t: ^testing.T) {
    project := bathymetry_refresh_test_project()
    defer free_project(project)
    append(&project.bathymetry_chunks, bathymetry_refresh_test_chunk(0), bathymetry_refresh_test_chunk(1))
    project.levels[0].heights[sample_index(256, 8)] = -4

    refreshed := bathymetry_refresh_generated_bounds(project, 255, 7, 257, 9)

    row := BATHYMETRY_CHUNK_RESOLUTION
    left := f32(project.bathymetry_chunks[0].heights[row + BATHYMETRY_CHUNK_RESOLUTION - 1])
    right := f32(project.bathymetry_chunks[1].heights[row])
    testing.expect_value(t, refreshed, 2)
    testing.expect_value(t, left, f32(-4))
    testing.expect_value(t, right, left)
    testing.expect_value(t, project.bathymetry_chunks[0].revision, u64(10))
    testing.expect_value(t, project.bathymetry_chunks[1].revision, u64(10))
}
