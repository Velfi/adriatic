package tests

import terrain "../packages/terrain"
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
		level_half_extent :=
			f32(terrain.RING_RESOLUTION - 1) * project.levels[level].cell_size * .5
		echo_center := level_half_extent * terrain.DEFAULT_ISLAND_OFFSET
		testing.expect(
			t,
			terrain.sample_height(&project, level, echo_center, echo_center) == project.sea_level,
		)
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
