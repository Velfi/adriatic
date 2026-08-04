package main

import leaf_mesh "../packages/leaf_mesh"
import "core:testing"

@(test)
foliage_transition_lab_recognizes_every_authored_corridor :: proc(t: ^testing.T) {
    cases := [5]struct {
        target: string,
        want:   Foliage_Transition_Example,
    } {
        {"wheat", .Wheat_Field},
        {"pine", .Pine_Forest},
        {"oak", .Oak_Forest},
        {"olive", .Olive_Orchard},
        {"hedges", .Residential_Hedges},
    }
    for sample in cases {
        got, ok := foliage_transition_target(sample.target)
        testing.expect(t, ok)
        testing.expect_value(t, got, sample.want)
    }
}

@(test)
foliage_transition_capture_mode_routes_to_the_lab :: proc(t: ^testing.T) {
    kind, ok := capture_kind_from_name("foliage-transition")
    testing.expect(t, ok)
    testing.expect_value(t, kind, Capture_Kind.Foliage_Transition_Lab)
}

@(test)
foliage_transition_middle_diagnostics_are_explicitly_bounded :: proc(t: ^testing.T) {
    example, ok := foliage_transition_target("pine-middle-smoke")
    testing.expect(t, ok)
    testing.expect_value(t, example, Foliage_Transition_Example.Pine_Forest)
    testing.expect_value(t, foliage_transition_forest_sample_limit, 12)
    testing.expect_value(t, foliage_transition_forest_half_width, f32(8))
    testing.expect_value(t, foliage_transition_forest_depth, f32(180))

    example, ok = foliage_transition_target("oak-middle-only-bounded")
    testing.expect(t, ok)
    testing.expect_value(t, example, Foliage_Transition_Example.Oak_Forest)
    testing.expect_value(t, foliage_transition_forest_sample_limit, 96)
    testing.expect_value(t, foliage_transition_forest_start, f32(110))

    // Ordinary authored targets always restore the full corridor after a
    // diagnostic capture in the same process.
    _, ok = foliage_transition_target("pine")
    testing.expect(t, ok)
    testing.expect_value(t, foliage_transition_forest_sample_limit, 420)
    testing.expect_value(t, foliage_transition_forest_start, f32(12))
    testing.expect_value(t, foliage_transition_forest_depth, f32(348))
}

@(test)
middle_tree_instance_meshes_persist_while_frame_instances_clear :: proc(t: ^testing.T) {
    world_instance_meshes_clear()
    vertices := [3]World_Vertex {
        {position = {0, 0, 0}},
        {position = {1, 0, 0}},
        {position = {0, 1, 0}},
    }
    indices := [3]u32{0, 1, 2}
    mesh_index := world_instance_mesh_add(vertices[:], indices[:], false)
    testing.expect_value(t, mesh_index, 0)
    testing.expect(t, !world_renderer.instance_meshes[mesh_index].casts_shadow)
    world_instance_mesh_emit(mesh_index, {})
    world_instances_flatten()
    testing.expect_value(t, len(world_renderer.instance_flattened), 1)

    world_instance_mesh_instances_clear()
    testing.expect_value(t, len(world_renderer.instance_meshes), 1)
    testing.expect_value(t, len(world_renderer.instance_meshes[mesh_index].instances), 0)
    testing.expect_value(t, len(world_renderer.instance_flattened), 0)
    world_instance_meshes_clear()
    delete(world_renderer.instance_vertices)
    delete(world_renderer.instance_indices)
    delete(world_renderer.instance_flattened)
    delete(world_renderer.instance_meshes)
    world_renderer.instance_vertices = {}
    world_renderer.instance_indices = {}
    world_renderer.instance_flattened = {}
    world_renderer.instance_meshes = {}
}

@(test)
generated_plants_share_leaf_meshes_by_shape_and_detail :: proc(t: ^testing.T) {
    world_instance_meshes_clear()
    near_elliptic := generated_plant_leaf_mesh_ensure(.Elliptic, false)
    same_near_elliptic := generated_plant_leaf_mesh_ensure(.Elliptic, false)
    hero_elliptic := generated_plant_leaf_mesh_ensure(.Elliptic, true)
    near_pine := generated_plant_leaf_mesh_ensure(.Pine_Needle_Clump, false)

    testing.expect(t, near_elliptic >= 0)
    testing.expect_value(t, same_near_elliptic, near_elliptic)
    testing.expect(t, hero_elliptic != near_elliptic)
    testing.expect(t, near_pine != near_elliptic)
    testing.expect_value(t, len(world_renderer.instance_meshes), 3)
    testing.expect_value(t, generated_plant_leaf_meshes[int(leaf_mesh.Shape.Elliptic) * 2], near_elliptic + 1)

    world_instance_meshes_clear()
    delete(world_renderer.instance_vertices)
    delete(world_renderer.instance_indices)
    delete(world_renderer.instance_flattened)
    delete(world_renderer.instance_meshes)
    world_renderer.instance_vertices = {}
    world_renderer.instance_indices = {}
    world_renderer.instance_flattened = {}
    world_renderer.instance_meshes = {}
}
