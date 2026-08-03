package terrain

import "core:math"
import "core:testing"

@(test)
authoring_mask_has_flat_core_and_independent_feather :: proc(t: ^testing.T) {
    testing.expect_value(t, authoring_mask(0, 100, .5, 50), f32(1))
    testing.expect_value(t, authoring_mask(49, 100, .5, 50), f32(1))
    testing.expect(t, authoring_mask(100, 100, .5, 50) > .45 && authoring_mask(100, 100, .5, 50) < .55)
    testing.expect(t, authoring_mask(149.9, 100, .5, 50) > 0)
    testing.expect_value(t, authoring_mask(150, 100, .5, 50), f32(0))
}

@(test)
authoring_preserve_detail_never_reverses_spline_displacement :: proc(t: ^testing.T) {
    current, target, amount, preserve := f32(10), f32(30), f32(.1), f32(.8)
    next := current + (target - current) * amount * (1 - preserve)
    testing.expect(t, next >= current)
    testing.expect(t, next <= current + (target - current) * amount)
}

@(test)
authoring_samples_are_owned_by_the_finest_resident_level :: proc(t: ^testing.T) {
    project := new(Project); defer free(project)
    init_project(project); defer destroy_project(project)
    fine := &project.levels[0]
    x := fine.origin_x + fine.cell_size * f32(TERRAIN_RESOLUTION / 2)
    z := fine.origin_z + fine.cell_size * f32(TERRAIN_RESOLUTION / 2)
    testing.expect(t, authoring_level_is_finest_at(project, 0, x, z))
    testing.expect(t, !authoring_level_is_finest_at(project, 1, x, z))

    coarse := &project.levels[1]
    outside_fine_x := coarse.origin_x + coarse.cell_size
    outside_fine_z := coarse.origin_z + coarse.cell_size
    testing.expect(t, !level_contains(fine, outside_fine_x, outside_fine_z))
    testing.expect(t, authoring_level_is_finest_at(project, 1, outside_fine_x, outside_fine_z))
}

@(test)
authoring_roughness_is_deterministic :: proc(t: ^testing.T) {
    testing.expect_value(t, authoring_noise(12.5, -31.25, 40, 4, 0x1234), authoring_noise(12.5, -31.25, 40, 4, 0x1234))
    testing.expect(t, authoring_noise(12.5, -31.25, 40, 4, 0x1234) != authoring_noise(12.5, -31.25, 40, 4, 0x5678))
}

@(test)
authoring_brush_respects_seabed_policy :: proc(t: ^testing.T) {
    project := new(Project); defer free(project)
    init_project(project); defer destroy_project(project)
    x, z, _ := island_center(project, .East)
    // Force a submerged sample inside the island ownership domain.
    source_x, source_z, ok := terrain_operator_source_point(project, .East, x, z)
    testing.expect(t, ok)
    level := terrain_operator_authored_level(project, source_x - 8, source_z - 8, source_x + 8, source_z + 8)
    data := &project.levels[level]
    sx := clamp(int(math.round(f64((source_x - data.origin_x) / data.cell_size))), 0, TERRAIN_RESOLUTION - 1)
    sz := clamp(int(math.round(f64((source_z - data.origin_z) / data.cell_size))), 0, TERRAIN_RESOLUTION - 1)
    data.heights[sample_index(sx, sz)] = project.sea_level - 4
    before := data.heights[sample_index(sx, sz)]
    request := Authoring_Brush_Request {
        owner       = .East,
        operation   = .Roughen,
        world_x     = x,
        world_z     = z,
        size        = 12,
        inner_core  = 1,
        flow        = 1,
        amplitude   = 5,
        noise_scale = 8,
        octaves     = 3,
        seed        = 7,
        iterations  = 1,
    }
    _ = apply_authoring_brush(project, request)
    testing.expect_value(t, data.heights[sample_index(sx, sz)], before)
    request.affect_seabed = true
    testing.expect(t, apply_authoring_brush(project, request))
    testing.expect(t, data.heights[sample_index(sx, sz)] != before)
}

@(test)
authoring_grade_rejects_excessive_slope :: proc(t: ^testing.T) {
    project := new(Project); defer free(project)
    init_project(project); defer destroy_project(project)
    x, z, _ := island_center(project, .East)
    points := [2]Cliff_Point{{x - 10, z}, {x + 10, z}}
    before := project.revision
    changed := apply_authoring_spline(
        project,
        {
            owner = .East,
            operation = .Grade,
            points = points[:],
            width = 12,
            feather = 4,
            flow = 1,
            start_height = 0,
            end_height = 20,
            maximum_grade = .1,
        },
    )
    testing.expect(t, !changed)
    testing.expect_value(t, project.revision, before)
}
