package main

import terrain "../packages/terrain"
import "core:testing"

lab_terrain_test_sampler :: proc(_: ^Editor, x, z: f32) -> Lab_Terrain_Sample {
    return {height = x + z, material = .75}
}

@(test)
lab_terrain_load_centers_levels_and_limits_generation_to_patch :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)
    config := Lab_Terrain_Config {
        center_x         = 12,
        center_z         = -8,
        half_extent_x    = 2,
        half_extent_z    = 3,
        sea_level        = -1,
        outside_height   = -6,
        outside_material = -.5,
    }
    testing.expect(t, lab_terrain_load(editor, config, lab_terrain_test_sampler))
    testing.expect_value(t, editor.project.sea_level, f32(-1))
    testing.expect_value(t, editor.project.levels[0].cell_size, terrain.FINE_CELL_SIZE)
    testing.expect_value(t, terrain.sample_height(&editor.project, 0, 12, -8), f32(4))
    testing.expect_value(t, terrain.sample_height(&editor.project, 0, 30, -8), f32(-6))
}

@(test)
lab_terrain_load_rejects_invalid_configuration_without_mutating_project :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)
    editor.project.revision = 41
    testing.expect(t, !lab_terrain_load(editor, {half_extent_x = -1}))
    testing.expect_value(t, editor.project.revision, u64(41))
}
