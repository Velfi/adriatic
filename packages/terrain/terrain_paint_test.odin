package terrain

import "core:testing"

@(test)
paint_stroke_converges_on_selected_material :: proc(t: ^testing.T) {
    project := new(Project)
    defer free_project(project)
    for &level in project.levels {
        level.cell_size = 1
        level.origin_x = -256
        level.origin_z = -256
    }

    center_x, center_z := f32(0), f32(0)
    index := sample_index(TERRAIN_RESOLUTION / 2, TERRAIN_RESOLUTION / 2)
    project.levels[0].material[index] = .8

    apply_stroke_with_hardness(project, .Paint, center_x, center_z, BASE_CELL_SIZE, 1, 1, 1, -1)
    testing.expect(t, project.levels[0].material[index] < -.99)

    apply_stroke_with_hardness(project, .Paint, center_x, center_z, BASE_CELL_SIZE, 1, -1, 1, 0)
    testing.expect(t, abs(project.levels[0].material[index]) < .001)
}
