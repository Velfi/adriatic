package tests

import roads "../packages/roads"
import terrain "../packages/terrain"
import "core:math"
import "core:os"
import "core:testing"

@(test)
terrain_strokes_propagate_through_every_clipmap_level :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer free(project)
    revision := project.revision
    terrain.apply_stroke(project, .Raise, 0, 0, 8, 1, 1)
    testing.expect(t, project.revision == revision + 1)
    for level in 0 ..< terrain.CLIPMAP_LEVELS do testing.expect(t, terrain.sample_height(project, level, 0, 0) > 0)
}

@(test)
terrain_material_is_bounded :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer free(project)
    terrain.apply_stroke(project, .Paint, 0, 0, 8, 10, 1)
    for level in 0 ..< terrain.CLIPMAP_LEVELS do testing.expect(t, terrain.sample_material(project, level, 0, 0) == 1)
}

@(test)
terrain_brush_hardness_controls_edge_falloff :: proc(t: ^testing.T) {
    soft := terrain.new_project()
    hard := terrain.new_project()
    defer free(soft)
    defer free(hard)
    center := terrain.BASE_CELL_SIZE * .5
    terrain.apply_stroke_with_hardness(soft, .Raise, center, center, 100, 1, 1, 0)
    terrain.apply_stroke_with_hardness(hard, .Raise, center, center, 100, 1, 1, 1)
    testing.expect(
        t,
        terrain.sample_height(hard, 0, center + 50, center) > terrain.sample_height(soft, 0, center + 50, center),
    )
    testing.expect(t, terrain.sample_height(soft, 0, center, center) == terrain.sample_height(hard, 0, center, center))
}

@(test)
terrain_project_file_round_trips_height_material_and_structures :: proc(t: ^testing.T) {
    path := "build/terrain_project_test.bin"
    defer os.remove(path)
    source := terrain.new_project()
    loaded := terrain.new_project()
    defer free(source)
    defer free(loaded)
    terrain.apply_stroke_with_hardness(source, .Raise, 0, 0, 100, 1, 1, .8)
    terrain.apply_stroke_with_hardness(source, .Paint, 0, 0, 100, 1, 1, .8)
    terrain.add_structure(source, terrain.structure_make(20, -30, 40, 50, 0, 60))
    road_a := roads.add_node(&source.road_graph, {0, 2, 0})
    road_b := roads.add_node(&source.road_graph, {40, 3, 20})
    roads.add_straight_edge(&source.road_graph, road_a, road_b, 7, 1, .Cobblestone)
    testing.expect(t, terrain.save_project(source, path))
    testing.expect(t, terrain.load_project(loaded, path))
    testing.expect(t, terrain.sample_height(loaded, 0, 0, 0) == terrain.sample_height(source, 0, 0, 0))
    testing.expect(t, terrain.sample_material(loaded, 0, 0, 0) == terrain.sample_material(source, 0, 0, 0))
    testing.expect(t, loaded.structure_count == 1)
    testing.expect(t, loaded.structures[0].height == source.structures[0].height)
    testing.expect(t, loaded.structures[0].group_id == source.structures[0].group_id)
    testing.expect(t, loaded.road_graph.node_count == 2)
    testing.expect(t, loaded.road_graph.edge_count == 1)
    testing.expect(t, loaded.road_graph.nodes[1].position == source.road_graph.nodes[1].position)
    testing.expect(t, loaded.road_graph.edges[0].pavement == .Cobblestone)
}

@(test)
default_terrain_has_two_opposite_corner_islands :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer free(project)
    half_extent := f32(terrain.RING_RESOLUTION - 1) * project.levels[0].cell_size * .5
    offset := half_extent * terrain.DEFAULT_ISLAND_OFFSET
    testing.expect(t, terrain.sample_height(project, 0, -offset, -offset) > project.sea_level)
    testing.expect(t, terrain.sample_height(project, 0, offset, offset) > project.sea_level)
    testing.expect(t, terrain.sample_height(project, 0, -offset, offset) == project.sea_level)
    testing.expect(t, terrain.sample_height(project, 0, offset, -offset) == project.sea_level)
}

@(test)
coarse_clipmap_levels_do_not_repeat_scaled_islands :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer free(project)
    authored_half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    for level in 1 ..< terrain.CLIPMAP_LEVELS {
        level_half_extent := f32(terrain.RING_RESOLUTION - 1) * project.levels[level].cell_size * .5
        echo_center := level_half_extent * terrain.DEFAULT_ISLAND_OFFSET
        testing.expect(t, terrain.sample_height(project, level, echo_center, echo_center) == project.sea_level)
    }
    testing.expect(
        t,
        terrain.sample_height(
            project,
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
    defer free(project)
    half_extent := f32(terrain.RING_RESOLUTION - 1) * project.levels[0].cell_size * .5
    for sign in terrain.DEFAULT_ISLAND_SIGNS {
        center := sign * half_extent * terrain.DEFAULT_ISLAND_OFFSET
        runway_half_length := half_extent * terrain.DEFAULT_RUNWAY_HALF_LENGTH
        runway_half_width := half_extent * terrain.DEFAULT_RUNWAY_HALF_WIDTH
        runway_ends := [2]f32{center - runway_half_length, center + runway_half_length}
        runway_sides := [2]f32{center - runway_half_width, center + runway_half_width}
        for x in runway_ends {
            for z in runway_sides {
                testing.expect(t, terrain.sample_height(project, 0, x, z) > project.sea_level)
            }
        }
    }
}

@(test)
default_islands_are_aircraft_scale :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer free(project)
    half_extent := f32(terrain.RING_RESOLUTION - 1) * project.levels[0].cell_size * .5
    diameter := half_extent * terrain.DEFAULT_ISLAND_RADIUS * 2
    runway_length := half_extent * terrain.DEFAULT_RUNWAY_HALF_LENGTH * 2
    testing.expect(t, diameter >= 550)
    testing.expect(t, runway_length >= 399)
}

@(test)
finest_terrain_level_is_four_kilometers_square :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer free(project)
    span := f32(terrain.RING_RESOLUTION - 1) * project.levels[0].cell_size
    testing.expect(t, span == terrain.WORLD_SIZE_METERS)
}

@(test)
structure_placement_snaps_and_follows_terrain :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer free(project)
    cell := project.levels[0].cell_size
    structure := terrain.structure_make(13.2, -8.7, 1, 1, 999, 24)
    structure.center_x = terrain.snap_to_grid(structure.center_x, cell)
    structure.center_z = terrain.snap_to_grid(structure.center_z, cell)
    structure.base_y = terrain.sample_height(project, 0, structure.center_x, structure.center_z)
    index := terrain.add_structure(project, structure)
    testing.expect(t, index == 0)
    testing.expect(t, project.structures[index].center_x == terrain.snap_to_grid(13.2, cell))
    testing.expect(
        t,
        project.structures[index].base_y == terrain.sample_height(project, 0, structure.center_x, structure.center_z),
    )
}

@(test)
structure_hit_testing_prefers_the_topmost_structure :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer free(project)
    first := terrain.add_structure(project, terrain.structure_make(0, 0, 20, 20, 0, 10))
    second := terrain.add_structure(project, terrain.structure_make(0, 0, 8, 8, 0, 10))
    testing.expect(t, first == 0)
    testing.expect(t, second == 1)
    testing.expect(t, terrain.structure_index_at(project, 0, 0) == second)
    testing.expect(t, terrain.structure_index_at(project, 9, 0) == first)
    testing.expect(t, terrain.structure_index_at(project, 20, 20) == -1)
}

@(test)
structure_duplicate_and_remove_preserve_ids :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer free(project)
    original := terrain.add_structure(project, terrain.structure_make(0, 0, 10, 10, 0, 10))
    duplicate := terrain.duplicate_structure(project, original, 20, 0)
    original_id := project.structures[original].id
    duplicate_id := project.structures[duplicate].id
    testing.expect(t, original_id != duplicate_id)
    testing.expect(t, project.structures[duplicate].center_x == 20)
    testing.expect(t, terrain.remove_structure(project, original))
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
formation_segments_merge_only_across_similar_angles :: proc(t: ^testing.T) {
    minimum_cosine := f32(0.9961947)
    testing.expect(t, terrain.formation_segments_can_merge(0, 0, 10, 0, 20, 0, minimum_cosine))
    testing.expect(t, terrain.formation_segments_can_merge(0, 0, 10, 0, 20, .5, minimum_cosine))
    testing.expect(t, !terrain.formation_segments_can_merge(0, 0, 10, 0, 20, 2, minimum_cosine))
    testing.expect(t, !terrain.formation_segments_can_merge(0, 0, 10, 0, 10, 10, minimum_cosine))
    testing.expect(t, !terrain.formation_segments_can_merge(0, 0, 0, 0, 10, 0, minimum_cosine))
}

@(test)
rotated_structure_hit_testing_uses_local_bounds :: proc(t: ^testing.T) {
    structure := terrain.structure_make(0, 0, 20, 4, 0, 10)
    structure.rotation = math.PI * .25
    testing.expect(t, terrain.structure_contains_point(structure, 0, 6))
    testing.expect(t, !terrain.structure_contains_point(structure, 0, 16))
}
