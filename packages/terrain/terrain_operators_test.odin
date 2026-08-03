package terrain

import "core:math"
import "core:testing"

@(test)
terrain_operator_falloff_hardness_preserves_center_and_changes_shoulders :: proc(t: ^testing.T) {
    testing.expect_value(t, terrain_operator_falloff(0, 10, 0), f32(1))
    testing.expect_value(t, terrain_operator_falloff(0, 10, 1), f32(1))
    testing.expect(t, terrain_operator_falloff(5, 10, 1) > terrain_operator_falloff(5, 10, 0))
    testing.expect_value(t, terrain_operator_falloff(10, 10, .5), f32(0))
}

@(test)
terrain_level_operator_edits_moved_island_in_authored_space :: proc(t: ^testing.T) {
    project := new(Project)
    defer free(project)
    init_project(project)
    defer destroy_project(project)

    source_x, source_z, _ := island_center(project, .East)
    testing.expect(t, island_set_center(project, .East, 1800, 2100))
    before := sample_surface_height(project, 0, 1800, 2100)
    testing.expect(t, apply_level_operator(project, .East, 1800, 2100, 30, before + 8, 1, 1))
    after := sample_surface_height(project, 0, 1800, 2100)
    testing.expect(t, after > before)
    testing.expect(t, sample_surface_height(project, 0, source_x, source_z) <= project.sea_level + SHORELINE_EPSILON)
}

@(test)
terrain_grade_operator_rejects_cross_island_gesture :: proc(t: ^testing.T) {
    project := new(Project)
    defer free(project)
    init_project(project)
    defer destroy_project(project)

    west_x, west_z, _ := island_center(project, .West)
    east_x, east_z, _ := island_center(project, .East)
    before := project.revision
    testing.expect(
        t,
        !apply_grade_operator(
            project,
            .West,
            west_x,
            west_z,
            sample_surface_height(project, 0, west_x, west_z),
            east_x,
            east_z,
            sample_surface_height(project, 0, east_x, east_z),
            12,
            8,
            1,
        ),
    )
    testing.expect_value(t, project.revision, before)
}

@(test)
terrain_grade_and_terrace_operators_change_land_and_propagate :: proc(t: ^testing.T) {
    project := new(Project)
    defer free(project)
    init_project(project)
    defer destroy_project(project)

    x, z, _ := island_center(project, .East)
    before := sample_surface_height(project, 0, x, z)
    testing.expect(t, apply_grade_operator(project, .East, x - 20, z, before + 6, x + 20, z, before + 6, 16, 8, 1))
    testing.expect(t, sample_surface_height(project, 0, x, z) > before)
    testing.expect(t, apply_terrace_operator(project, .East, x, z, 35, 5, project.sea_level, 1, 1))
    for level in 1 ..< CLIPMAP_LEVELS {
        finer, coarse_level := &project.levels[level - 1], &project.levels[level]
        sample_x := clamp(
            int(math.round(f64((x - coarse_level.origin_x) / coarse_level.cell_size))),
            0,
            TERRAIN_RESOLUTION - 1,
        )
        sample_z := clamp(
            int(math.round(f64((z - coarse_level.origin_z) / coarse_level.cell_size))),
            0,
            TERRAIN_RESOLUTION - 1,
        )
        aligned_x := coarse_level.origin_x + f32(sample_x) * coarse_level.cell_size
        aligned_z := coarse_level.origin_z + f32(sample_z) * coarse_level.cell_size
        if !level_contains(finer, aligned_x, aligned_z) do continue
        fine := sample_level_height(finer, aligned_x, aligned_z)
        coarse := coarse_level.heights[sample_index(sample_x, sample_z)]
        testing.expect(t, math.abs(fine - coarse) < .01)
    }
}

@(test)
terrain_area_level_respects_rectangle_and_land_boundary :: proc(t: ^testing.T) {
    project := new(Project)
    defer free(project)
    init_project(project)
    defer destroy_project(project)

    center_x, center_z, _ := island_center(project, .West)
    inside_before := sample_surface_height(project, 0, center_x, center_z)
    outside_before := sample_surface_height(project, 0, center_x + 80, center_z)
    area := Terrain_Operator_Area {
        owner          = .West,
        start_x        = center_x - 20,
        start_z        = center_z - 20,
        end_x          = center_x + 20,
        end_z          = center_z + 20,
        target_height  = inside_before + 6,
        boundary_blend = 4,
    }
    testing.expect(t, apply_level_area_operator(project, area, 1, 1))
    testing.expect(t, sample_surface_height(project, 0, center_x, center_z) > inside_before)
    testing.expect(t, math.abs(sample_surface_height(project, 0, center_x + 80, center_z) - outside_before) < .001)
}

@(test)
terrain_erode_operator_is_order_independent_and_deterministic :: proc(t: ^testing.T) {
    first := new(Project)
    second := new(Project)
    defer free(first)
    defer free(second)
    init_project(first)
    defer destroy_project(first)
    second^ = first^
    // Prevent the copied project from sharing dynamic storage that destroy owns.
    second.structures = nil
    second.terrain_pages = nil
    second.bathymetry_chunks = nil
    second.terrain_page_lookup = nil
    second.bathymetry_chunk_lookup = nil

    x, z, _ := island_center(first, .East)
    testing.expect(t, apply_erode_operator(first, .East, x, z, 50, 0, .65, .4))
    testing.expect(t, apply_erode_operator(second, .East, x, z, 50, 0, .65, .4))
    for index in 0 ..< SAMPLES_PER_LEVEL {
        testing.expect_value(t, first.levels[0].heights[index], second.levels[0].heights[index])
    }
}
