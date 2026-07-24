package tests

import terrain "../packages/terrain"
import "core:math"
import "core:testing"

@(test)
terrain_strokes_propagate_through_every_clipmap_level :: proc(t: ^testing.T) {
    project := terrain.new_project()
    revision := project.revision
    terrain.apply_stroke(&project, .Raise, 0, 0, 8, 1, 1)
    testing.expect(t, project.revision == revision + 1)
    for level in 0 ..< terrain.CLIPMAP_LEVELS do testing.expect(t, terrain.sample_height(&project, level, 0, 0) > 0)
}

@(test)
terrain_material_is_bounded :: proc(t: ^testing.T) {
    project := terrain.new_project()
    terrain.apply_stroke(&project, .Paint, 0, 0, 8, 10, 1)
    for level in 0 ..< terrain.CLIPMAP_LEVELS do testing.expect(t, terrain.sample_material(&project, level, 0, 0) == 1)
}

@(test)
default_terrain_has_two_opposite_corner_islands :: proc(t: ^testing.T) {
    project := terrain.new_project()
    half_extent := f32(terrain.RING_RESOLUTION - 1) * project.levels[0].cell_size * .5
    offset := half_extent * terrain.DEFAULT_ISLAND_OFFSET
    testing.expect(t, terrain.sample_height(&project, 0, -offset, -offset) > project.sea_level)
    testing.expect(t, terrain.sample_height(&project, 0, offset, offset) > project.sea_level)
    testing.expect(t, terrain.sample_height(&project, 0, -offset, offset) == project.sea_level)
    testing.expect(t, terrain.sample_height(&project, 0, offset, -offset) == project.sea_level)
}

@(test)
coarse_clipmap_levels_do_not_repeat_scaled_islands :: proc(t: ^testing.T) {
    project := terrain.new_project()
    authored_half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    for level in 1 ..< terrain.CLIPMAP_LEVELS {
        level_half_extent := f32(terrain.RING_RESOLUTION - 1) * project.levels[level].cell_size * .5
        echo_center := level_half_extent * terrain.DEFAULT_ISLAND_OFFSET
        testing.expect(t, terrain.sample_height(&project, level, echo_center, echo_center) == project.sea_level)
    }
    testing.expect(
        t,
        terrain.sample_height(
            &project,
            0,
            authored_half_extent * terrain.DEFAULT_ISLAND_OFFSET,
            authored_half_extent * terrain.DEFAULT_ISLAND_OFFSET,
        ) >
        project.sea_level,
    )
}

@(test)
default_islands_support_the_full_runway :: proc(t: ^testing.T) {
    project := terrain.new_project()
    half_extent := f32(terrain.RING_RESOLUTION - 1) * project.levels[0].cell_size * .5
    for sign in terrain.DEFAULT_ISLAND_SIGNS {
        center := sign * half_extent * terrain.DEFAULT_ISLAND_OFFSET
        runway_half_length := half_extent * terrain.DEFAULT_RUNWAY_HALF_LENGTH
        runway_half_width := half_extent * terrain.DEFAULT_RUNWAY_HALF_WIDTH
        runway_ends := [2]f32{center - runway_half_length, center + runway_half_length}
        runway_sides := [2]f32{center - runway_half_width, center + runway_half_width}
        for x in runway_ends {
            for z in runway_sides {
                testing.expect(t, terrain.sample_height(&project, 0, x, z) > project.sea_level)
            }
        }
    }
}

@(test)
default_islands_are_aircraft_scale :: proc(t: ^testing.T) {
    project := terrain.new_project()
    half_extent := f32(terrain.RING_RESOLUTION - 1) * project.levels[0].cell_size * .5
    diameter := half_extent * terrain.DEFAULT_ISLAND_RADIUS * 2
    runway_length := half_extent * terrain.DEFAULT_RUNWAY_HALF_LENGTH * 2
    testing.expect(t, diameter >= 550)
    testing.expect(t, runway_length >= 399)
}

@(test)
finest_terrain_level_is_four_kilometers_square :: proc(t: ^testing.T) {
    project := terrain.new_project()
    span := f32(terrain.RING_RESOLUTION - 1) * project.levels[0].cell_size
    testing.expect(t, span == terrain.WORLD_SIZE_METERS)
}

@(test)
structure_placement_snaps_and_follows_terrain :: proc(t: ^testing.T) {
    project := terrain.new_project()
    cell := project.levels[0].cell_size
    structure := terrain.structure_make(13.2, -8.7, 1, 1, 999, 24)
    structure.center_x = terrain.snap_to_grid(structure.center_x, cell)
    structure.center_z = terrain.snap_to_grid(structure.center_z, cell)
    structure.base_y = terrain.sample_height(&project, 0, structure.center_x, structure.center_z)
    index := terrain.add_structure(&project, structure)
    testing.expect(t, index == 0)
    testing.expect(t, project.structures[index].center_x == terrain.snap_to_grid(13.2, cell))
    testing.expect(
        t,
        project.structures[index].base_y == terrain.sample_height(&project, 0, structure.center_x, structure.center_z),
    )
}

@(test)
structure_hit_testing_prefers_the_topmost_structure :: proc(t: ^testing.T) {
    project := terrain.new_project()
    first := terrain.add_structure(&project, terrain.structure_make(0, 0, 20, 20, 0, 10))
    second := terrain.add_structure(&project, terrain.structure_make(0, 0, 8, 8, 0, 10))
    testing.expect(t, first == 0)
    testing.expect(t, second == 1)
    testing.expect(t, terrain.structure_index_at(&project, 0, 0) == second)
    testing.expect(t, terrain.structure_index_at(&project, 9, 0) == first)
    testing.expect(t, terrain.structure_index_at(&project, 20, 20) == -1)
}

@(test)
structure_duplicate_and_remove_preserve_ids :: proc(t: ^testing.T) {
    project := terrain.new_project()
    original := terrain.add_structure(&project, terrain.structure_make(0, 0, 10, 10, 0, 10))
    duplicate := terrain.duplicate_structure(&project, original, 20, 0)
    original_id := project.structures[original].id
    duplicate_id := project.structures[duplicate].id
    testing.expect(t, original_id != duplicate_id)
    testing.expect(t, project.structures[duplicate].center_x == 20)
    testing.expect(t, terrain.remove_structure(&project, original))
    testing.expect(t, project.structure_count == 1)
    testing.expect(t, project.structures[0].id == duplicate_id)
}

@(test)
formation_kinds_cycle_without_skipping :: proc(t: ^testing.T) {
    kind := terrain.Formation_Kind.Box
    kind = terrain.formation_kind_next(kind)
    testing.expect(t, kind == .Rock)
    kind = terrain.formation_kind_next(kind)
    testing.expect(t, kind == .Spire)
    kind = terrain.formation_kind_next(kind)
    testing.expect(t, kind == .Mountain)
    kind = terrain.formation_kind_next(kind)
    testing.expect(t, kind == .Ridge)
    kind = terrain.formation_kind_next(kind)
    testing.expect(t, kind == .Cliff)
    kind = terrain.formation_kind_next(kind)
    testing.expect(t, kind == .Box)
}

@(test)
formation_gesture_selects_useful_profiles :: proc(t: ^testing.T) {
    cell := terrain.BASE_CELL_SIZE
    testing.expect(t, terrain.formation_kind_for_gesture(cell * 8, cell * 2, cell * 3) == .Ridge)
    testing.expect(t, terrain.formation_kind_for_gesture(cell * 2, cell * 2, cell * 5) == .Spire)
    testing.expect(t, terrain.formation_kind_for_gesture(cell * 4, cell * 4, cell * 5) == .Mountain)
    testing.expect(t, terrain.formation_kind_for_gesture(cell * 4, cell * 4, cell * 2) == .Rock)
}

@(test)
rotated_structure_hit_testing_uses_local_bounds :: proc(t: ^testing.T) {
    structure := terrain.structure_make(0, 0, 20, 4, 0, 10)
    structure.rotation = math.PI * .25
    testing.expect(t, terrain.structure_contains_point(structure, 0, 6))
    testing.expect(t, !terrain.structure_contains_point(structure, 0, 16))
}
