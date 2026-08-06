package main

import leaf_mesh "../packages/leaf_mesh"
import plant_assets "../packages/plant_assets"
import third_person "zelda_engine:third_person"
import "core:math"
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
foliage_transition_benchmarks_span_the_full_corridor_with_bounded_density :: proc(t: ^testing.T) {
    example, ok := foliage_transition_target("pine-benchmark")
    testing.expect(t, ok)
    testing.expect_value(t, example, Foliage_Transition_Example.Pine_Forest)
    testing.expect_value(t, foliage_transition_forest_sample_limit, 36)
    testing.expect_value(t, foliage_transition_forest_depth, f32(348))
    example, ok = foliage_transition_target("oak-benchmark")
    testing.expect(t, ok)
    testing.expect_value(t, example, Foliage_Transition_Example.Oak_Forest)
    testing.expect_value(t, foliage_transition_forest_sample_limit, 36)
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
plant_instance_shadow_deformation_keeps_leaf_pivot_on_branch :: proc(t: ^testing.T) {
    instance := generated_plant_instance(
        {1, 0, 0},
        {0, 1, 0},
        {0, 0, 1},
        {2, 3, 4},
        {255, 255, 255, 255},
        {2, 0, 4},
        1,
        .73,
        .8,
        .9,
        1,
    )
    leaf := world_vertex({}, {255, 255, 255, 255})
    leaf.kind = .Leaf
    branch := leaf
    branch.kind = .Bark
    leaf_position := shadow_instance_position(leaf, instance, 12.5, .6, 5, 2)
    branch_position := shadow_instance_position(branch, instance, 12.5, .6, 5, 2)
    for component in 0 ..< 3 {
        testing.expect(t, math.abs(leaf_position[component] - branch_position[component]) < 1e-5)
    }

    root_instance := instance
    root_instance.basis_y_translation_y[3] = 0
    root := shadow_instance_position(branch, root_instance, 12.5, .6, 5, 2)
    testing.expect(t, math.abs(root[0] - 2) < 1e-5)
    testing.expect(t, math.abs(root[1]) < 1e-5)
    testing.expect(t, math.abs(root[2] - 4) < 1e-5)
}

@(test)
plant_vertex_shadow_wind_keeps_roots_fixed_and_respects_stiffness :: proc(t: ^testing.T) {
    instance := generated_plant_instance(
        {1, 0, 0}, {0, 1, 0}, {0, 0, 1}, {}, {255, 255, 255, 255}, {}, 1, .41, 1, 1, 1,
    )
    root := Plant_Vertex{position = {}, stiffness = 1}
    root_position := shadow_plant_position(root, instance, 8, .7, 6, 2)
    testing.expect(t, math.abs(root_position[0]) + math.abs(root_position[1]) + math.abs(root_position[2]) < 1e-6)

    stiff := Plant_Vertex {
        position = {0, 3, 0},
        primary_anchor = {},
        secondary_anchor = {0, 1, 0},
        stiffness = 1,
        hierarchy_depth = 2,
        phase = .27,
    }
    flexible := stiff
    flexible.stiffness = 0
    stiff_position := shadow_plant_position(stiff, instance, 8, .7, 6, 2)
    flexible_position := shadow_plant_position(flexible, instance, 8, .7, 6, 2)
    stiff_delta := math.sqrt(
        f64(stiff_position[0] * stiff_position[0] +
            (stiff_position[1] - 3) * (stiff_position[1] - 3) +
            stiff_position[2] * stiff_position[2]),
    )
    flexible_delta := math.sqrt(
        f64(flexible_position[0] * flexible_position[0] +
            (flexible_position[1] - 3) * (flexible_position[1] - 3) +
            flexible_position[2] * flexible_position[2]),
    )
    testing.expect(t, flexible_delta > stiff_delta)
}

@(test)
plant_shadow_transition_dither_rejects_zero_and_accepts_opaque :: proc(t: ^testing.T) {
    a := third_person.Vec3{1, 2, 3}
    b := third_person.Vec3{2, 2, 3}
    c := third_person.Vec3{1, 3, 3}
    testing.expect(t, !shadow_plant_transition_visible(a, b, c, 0))
    testing.expect(t, shadow_plant_transition_visible(a, b, c, 1))
    first := shadow_plant_transition_visible(a, b, c, .47)
    testing.expect_value(t, shadow_plant_transition_visible(a, b, c, .47), first)
}

@(test)
released_plant_mesh_storage_is_reused_without_growing_backing_buffers :: proc(t: ^testing.T) {
    world_instance_meshes_clear()
    defer {
        world_instance_meshes_clear()
        delete(world_renderer.plant_vertices)
        delete(world_renderer.instance_indices)
        delete(world_renderer.plant_meshes)
        world_renderer.plant_vertices = {}
        world_renderer.instance_indices = {}
        world_renderer.plant_meshes = {}
    }
    vertices := [4]Plant_Vertex{}
    indices := [6]u32{0, 1, 2, 0, 2, 3}
    first := world_plant_mesh_reuse_or_add(vertices[:], indices[:])
    vertex_count, index_count := len(world_renderer.plant_vertices), len(world_renderer.instance_indices)
    world_plant_mesh_release(first)
    second := world_plant_mesh_reuse_or_add(vertices[:3], indices[:3])
    testing.expect_value(t, second, first)
    testing.expect_value(t, len(world_renderer.plant_vertices), vertex_count)
    testing.expect_value(t, len(world_renderer.instance_indices), index_count)
    testing.expect(t, !world_renderer.plant_meshes[second].available)
}

@(test)
middle_tree_instance_meshes_persist_while_frame_instances_clear :: proc(t: ^testing.T) {
    world_instance_meshes_clear()
    vertices := [3]World_Vertex{{position = {0, 0, 0}}, {position = {1, 0, 0}}, {position = {0, 1, 0}}}
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
    replacement_vertices := [2]World_Vertex{{position = {2, 0, 0}}, {position = {0, 2, 0}}}
    replacement_indices := [3]u32{0, 1, 0}
    testing.expect(t, world_instance_mesh_replace(mesh_index, replacement_vertices[:], replacement_indices[:], true))
    testing.expect(t, world_renderer.instance_meshes[mesh_index].casts_shadow)
    testing.expect_value(t, world_renderer.instance_meshes[mesh_index].index_count, u32(3))
    oversized_vertices := [4]World_Vertex{}
    testing.expect(t, !world_instance_mesh_replace(mesh_index, oversized_vertices[:], replacement_indices[:]))
    world_instance_meshes_clear()
    delete(world_renderer.instance_vertices)
    delete(world_renderer.instance_indices)
    delete(world_renderer.instance_flattened)
    delete(world_renderer.instance_meshes)
    delete(world_renderer.plant_vertices)
    delete(world_renderer.plant_meshes)
    world_renderer.instance_vertices = {}
    world_renderer.instance_indices = {}
    world_renderer.instance_flattened = {}
    world_renderer.instance_meshes = {}
    world_renderer.plant_vertices = {}
    world_renderer.plant_meshes = {}
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
    testing.expect_value(t, len(world_renderer.plant_meshes), 3)
    testing.expect_value(t, generated_plant_leaf_meshes[int(leaf_mesh.Shape.Elliptic) * 2], near_elliptic + 1)

    world_instance_meshes_clear()
    delete(world_renderer.instance_vertices)
    delete(world_renderer.instance_indices)
    delete(world_renderer.instance_flattened)
    delete(world_renderer.instance_meshes)
    delete(world_renderer.plant_vertices)
    delete(world_renderer.plant_meshes)
    world_renderer.instance_vertices = {}
    world_renderer.instance_indices = {}
    world_renderer.instance_flattened = {}
    world_renderer.instance_meshes = {}
    world_renderer.plant_vertices = {}
    world_renderer.plant_meshes = {}
}

@(test)
compiled_distant_plants_build_blendable_impostor_views :: proc(t: ^testing.T) {
    world_instance_meshes_clear()
    generated_plant_cache_destroy()
    request := plant_assets.PLANT_ASSET_MANIFEST[0]
    entry := generated_plant_cached(request.species, request.seed, .Far, request.habit, nil, 1)
    testing.expect(t, entry != nil && entry.compiled_asset)
    if entry != nil {
        first := generated_plant_impostor_mesh_ensure(entry, 0)
        second := generated_plant_impostor_mesh_ensure(entry, 1)
        aerial := generated_plant_impostor_mesh_ensure(entry, 16)
        testing.expect(t, first >= 0 && second >= 0 && aerial >= 0)
        testing.expect(t, first != second && second != aerial)
        testing.expect(t, len(world_renderer.plant_meshes[first].instances) == 0)
        testing.expect(t, world_renderer.plant_meshes[first].index_count > 0)
        testing.expect(t, world_renderer.plant_meshes[first].casts_shadow)
    }
    runtime := generated_plant_cached(.Olive, 42, .Far, .Free_Standing, nil, 1)
    testing.expect(t, runtime != nil && !runtime.compiled_asset)
    if runtime != nil {
        testing.expect(t, generated_plant_runtime_impostor_ensure(runtime))
        testing.expect_value(
            t,
            len(runtime.impostor_color),
            plant_assets.PLANT_IMPOSTOR_ATLAS_WIDTH * plant_assets.PLANT_IMPOSTOR_ATLAS_HEIGHT * 4,
        )
        testing.expect(t, generated_plant_impostor_mesh_ensure(runtime, 8) >= 0)
    }
    generated_plant_cache_destroy()
    world_instance_meshes_clear()
    delete(world_renderer.instance_vertices)
    delete(world_renderer.plant_vertices)
    delete(world_renderer.instance_indices)
    delete(world_renderer.instance_flattened)
    delete(world_renderer.instance_meshes)
    delete(world_renderer.plant_meshes)
    world_renderer.instance_vertices = {}
    world_renderer.plant_vertices = {}
    world_renderer.instance_indices = {}
    world_renderer.instance_flattened = {}
    world_renderer.instance_meshes = {}
    world_renderer.plant_meshes = {}
}

@(test)
runtime_plant_cache_evicts_oldest_nonpermanent_entry_to_byte_budget :: proc(t: ^testing.T) {
    generated_plant_cache_destroy()
    defer generated_plant_cache_destroy()
    generated_plant_cache_count = 3
    for index in 0 ..< 3 {
        entry := &generated_plant_cache[index]
        entry.occupied = true
        entry.last_used = u64(index + 1)
        entry.impostor_color = make([dynamic]byte, 16)
    }
    generated_plant_cache[2].permanent = true
    generated_plant_cache_evict_runtime_to_budget(1, 16)
    testing.expect(t, !generated_plant_cache[0].occupied)
    testing.expect(t, generated_plant_cache[1].occupied)
    testing.expect(t, generated_plant_cache[2].occupied)
}
