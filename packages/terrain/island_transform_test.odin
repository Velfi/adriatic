package terrain

import "core:math"
import "core:testing"

@(test)
island_transform_moves_terrain_structures_and_roads_without_resampling :: proc(t: ^testing.T) {
    project := new(Project)
    defer free(project)
    init_project(project)
    defer destroy_project(project)

    source_x, source_z, ok := island_center(project, .East)
    testing.expect(t, ok)
    source_height := sample_surface_height(project, 0, source_x, source_z)
    structure := structure_make(source_x, source_z, 20, 20, source_height, 10)
    _ = add_structure(project, structure)
    project.road_graph.node_count = 1
    project.road_graph.nodes[0].position = {source_x, source_height, source_z}

    target_x, target_z := f32(1800), f32(2200)
    testing.expect(t, island_set_center(project, .East, target_x, target_z))
    testing.expect(t, math.abs(sample_surface_height(project, 0, target_x, target_z) - source_height) < .001)
    testing.expect(t, sample_surface_height(project, 0, source_x, source_z) <= project.sea_level + .01)
    testing.expect_value(t, project.structures[0].center_x, target_x)
    testing.expect_value(t, project.structures[0].center_z, target_z)
    testing.expect_value(t, project.road_graph.nodes[0].position.x, target_x)
    testing.expect_value(t, project.road_graph.nodes[0].position.z, target_z)
}

@(test)
island_distance_supports_coincident_centers_and_rejects_out_of_bounds_centers :: proc(t: ^testing.T) {
    project := new(Project)
    defer free(project)
    project.island_transforms = default_island_transforms()
    west_x, west_z, _ := island_center(project, .West)
    testing.expect(t, island_set_center(project, .East, west_x, west_z))
    east_x, east_z, _ := island_center(project, .East)
    testing.expect(t, west_x == east_x && west_z == east_z)
    exact_x, exact_z, exact_ok := island_center_at_distance(project, .East, 1000)
    testing.expect(t, exact_ok)
    exact_dx, exact_dz := exact_x - west_x, exact_z - west_z
    testing.expect(t, math.abs(f32(math.sqrt(f64(exact_dx * exact_dx + exact_dz * exact_dz))) - 1000) < .001)
    testing.expect(t, !island_set_center(project, .East, 4000, 4000))
}
