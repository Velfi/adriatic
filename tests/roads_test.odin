package tests

import roads "../packages/roads"
import "core:math"
import "core:testing"

@(test)
road_bezier_preserves_endpoints_and_curves_in_3d :: proc(t: ^testing.T) {
    graph: roads.Graph
    start := roads.add_node(&graph, {0, 2, 0})
    end := roads.add_node(&graph, {30, 8, 0})
    roads.add_edge(&graph, start, end, {8, 4, 14}, {22, 6, 14}, 6)
    edge := graph.edges[0]
    testing.expect(t, roads.edge_point(&graph, edge, 0) == graph.nodes[start].position)
    testing.expect(t, roads.edge_point(&graph, edge, 1) == graph.nodes[end].position)
    middle := roads.edge_point(&graph, edge, .5)
    testing.expect(t, middle.z > 9)
    testing.expect(t, middle.y > 2 && middle.y < 8)
}

@(test)
road_bake_outputs_indexed_road_shoulders_and_caps :: proc(t: ^testing.T) {
    graph: roads.Graph
    start := roads.add_node(&graph, {0, 0, 0}, 2)
    end := roads.add_node(&graph, {24, 0, 0}, 2)
    roads.add_straight_edge(&graph, start, end, 6, 1.5)
    mesh := roads.bake(&graph)
    defer roads.mesh_destroy(&mesh)
    testing.expect(t, len(mesh.vertices) > 0)
    testing.expect(t, len(mesh.indices) > 0)
    saw_road, saw_shoulder, saw_junction, saw_verge := false, false, false, false
    for vertex in mesh.vertices {
        saw_road = saw_road || vertex.surface == .Road
        saw_shoulder = saw_shoulder || vertex.surface == .Shoulder
        saw_junction = saw_junction || vertex.surface == .Junction
        saw_verge = saw_verge || vertex.surface == .Verge
        // Procedural pavement uses this metadata to preserve a physical
        // transverse scale instead of stretching with the road's UV width.
        testing.expect(t, math.abs(vertex.road_half_width - 3) < .0001)
        testing.expect(t, math.abs(vertex.use_intensity - 1) < .0001)
    }
    testing.expect(t, saw_road && saw_shoulder && saw_junction && saw_verge)
    for index in mesh.indices do testing.expect(t, int(index) < len(mesh.vertices))
}

@(test)
road_bake_carries_authored_use_intensity_into_surface_vertices :: proc(t: ^testing.T) {
    graph: roads.Graph
    start := roads.add_node(&graph, {0, 0, 0}, 2)
    end := roads.add_node(&graph, {24, 0, 0}, 2)
    roads.add_straight_edge(&graph, start, end, 6, 1.5, .Cobblestone, .2)
    mesh := roads.bake(&graph)
    defer roads.mesh_destroy(&mesh)

    for vertex in mesh.vertices {
        testing.expect(t, math.abs(vertex.use_intensity - .2) < .0001)
    }
}

@(test)
road_use_intensity_is_clamped_at_authoring_boundary :: proc(t: ^testing.T) {
    graph: roads.Graph
    start := roads.add_node(&graph, {0, 0, 0})
    middle := roads.add_node(&graph, {10, 0, 0})
    end := roads.add_node(&graph, {20, 0, 0})
    roads.add_straight_edge(&graph, start, middle, 4, 1, .Cobblestone, -.5)
    roads.add_straight_edge(&graph, middle, end, 4, 1, .Cobblestone, 1.5)
    testing.expect(t, graph.edges[0].use_intensity == 0)
    testing.expect(t, graph.edges[1].use_intensity == 1)
}

@(test)
road_bake_chunks_group_edge_spans_and_keep_junctions_separate :: proc(t: ^testing.T) {
    graph: roads.Graph
    start := roads.add_node(&graph, {0, 0, 0}, 2)
    end := roads.add_node(&graph, {40, 0, 0}, 2)
    roads.add_straight_edge(&graph, start, end, 6, 1.5)
    settings := roads.default_bake_settings()
    settings.target_segment_length = 4
    settings.target_chunk_length = 12
    settings.min_spans_per_chunk = 1
    settings.max_spans_per_chunk = 3
    mesh := roads.bake(&graph, settings)
    defer roads.mesh_destroy(&mesh)

    // Ten edge spans become 3+3+3+1, followed by one end-cap chunk per node.
    testing.expect_value(t, len(mesh.chunks), 6)
    next_index := 0
    for chunk in mesh.chunks {
        testing.expect_value(t, chunk.first_index, next_index)
        testing.expect(t, chunk.index_count > 0)
        testing.expect_value(t, chunk.index_count % 3, 0)
        next_index += chunk.index_count
    }
    testing.expect_value(t, next_index, len(mesh.indices))
}

@(test)
road_bake_feathers_an_outer_verge_beyond_each_shoulder :: proc(t: ^testing.T) {
    graph: roads.Graph
    start := roads.add_node(&graph, {0, 0, 0}, 2)
    end := roads.add_node(&graph, {24, 0, 0}, 2)
    roads.add_straight_edge(&graph, start, end, 6, 1.5, .Dirt)
    mesh := roads.bake(&graph)
    defer roads.mesh_destroy(&mesh)

    testing.expect(t, len(mesh.vertices) >= 6)
    testing.expect(t, mesh.vertices[0].surface == .Verge)
    testing.expect(t, mesh.vertices[1].surface == .Shoulder)
    testing.expect(t, mesh.vertices[2].surface == .Road)
    testing.expect(t, mesh.vertices[3].surface == .Road)
    testing.expect(t, mesh.vertices[4].surface == .Shoulder)
    testing.expect(t, mesh.vertices[5].surface == .Verge)
    testing.expect(t, math.abs(mesh.vertices[0].position.z) > math.abs(mesh.vertices[1].position.z))
    testing.expect(t, math.abs(mesh.vertices[1].position.z) > math.abs(mesh.vertices[2].position.z))
    testing.expect(t, mesh.vertices[0].uv[0] == 0)
    testing.expect(t, mesh.vertices[5].uv[0] == 1)

    saw_rounded_start, saw_rounded_end := false, false
    for vertex in mesh.vertices {
        if vertex.surface != .Road do continue
        saw_rounded_start = saw_rounded_start || vertex.position.x < -.25
        saw_rounded_end = saw_rounded_end || vertex.position.x > 24.25
    }
    testing.expect(t, saw_rounded_start)
    testing.expect(t, saw_rounded_end)
}

@(test)
road_t_junction_bakes_one_merged_cap_at_shared_node :: proc(t: ^testing.T) {
    graph: roads.Graph
    west := roads.add_node(&graph, {-20, 0, 0}, 2)
    junction := roads.add_node(&graph, {0, 1, 0}, 5)
    east := roads.add_node(&graph, {20, 2, 0}, 2)
    north := roads.add_node(&graph, {0, 4, 20}, 2)
    roads.add_straight_edge(&graph, west, junction, 6, 1, .Asphalt)
    roads.add_straight_edge(&graph, junction, east, 6, 1, .Cobblestone)
    roads.add_edge(&graph, junction, north, {0, 2, 7}, {0, 3, 14}, 8, 1, .Dirt)
    mesh := roads.bake(&graph)
    defer roads.mesh_destroy(&mesh)
    junction_vertices := 0
    shared_center := -1
    for vertex, index in mesh.vertices {
        if vertex.surface == .Junction do junction_vertices += 1
        if vertex.surface == .Junction && math.abs(vertex.position.x) < .001 && math.abs(vertex.position.z) < .001 {
            shared_center = index
        }
        length := f32(
            math.sqrt(
                f64(
                    vertex.normal.x * vertex.normal.x +
                    vertex.normal.y * vertex.normal.y +
                    vertex.normal.z * vertex.normal.z,
                ),
            ),
        )
        testing.expect(t, length > .99 && length < 1.01)
    }
    // Each node contributes only one cap center. Its boundary indices are
    // reused from the edge strips, so the graph is welded at every seam.
    testing.expect(t, junction_vertices == 4)
    testing.expect(t, shared_center >= 0)
    testing.expect(t, math.abs(mesh.vertices[shared_center].road_half_width - 4) < .0001)
    center_index_uses := 0
    for index in mesh.indices {
        if int(index) == shared_center do center_index_uses += 1
    }
    testing.expect(t, center_index_uses == 6)

    saw_mixed_shoulder_bridge, saw_mixed_verge_bridge := false, false
    for triangle in 0 ..< len(mesh.indices) / 3 {
        a := mesh.vertices[mesh.indices[triangle * 3]]
        b := mesh.vertices[mesh.indices[triangle * 3 + 1]]
        c := mesh.vertices[mesh.indices[triangle * 3 + 2]]
        mixed_pavement := a.pavement != b.pavement || b.pavement != c.pavement
        if !mixed_pavement do continue
        saw_mixed_shoulder_bridge =
            saw_mixed_shoulder_bridge || a.surface == .Shoulder || b.surface == .Shoulder || c.surface == .Shoulder
        saw_mixed_verge_bridge =
            saw_mixed_verge_bridge || a.surface == .Verge || b.surface == .Verge || c.surface == .Verge
    }
    testing.expect(t, saw_mixed_shoulder_bridge)
    testing.expect(t, saw_mixed_verge_bridge)
}

@(test)
road_equal_angle_rings_keep_edge_insertion_order :: proc(t: ^testing.T) {
    graph: roads.Graph
    junction := roads.add_node(&graph, {0, 0, 0}, 5)
    first := roads.add_node(&graph, {20, 0, 0})
    second := roads.add_node(&graph, {20, 0, 0})
    roads.add_straight_edge(&graph, junction, first, 6, 1, .Asphalt)
    roads.add_straight_edge(&graph, junction, second, 6, 1, .Dirt)
    mesh := roads.bake(&graph)
    defer roads.mesh_destroy(&mesh)

    center_index := -1
    for vertex, index in mesh.vertices {
        if vertex.surface == .Junction && vertex.position.x == 0 && vertex.position.z == 0 {
            center_index = index
            break
        }
    }
    testing.expect(t, center_index >= 0)

    center_use := -1
    for index, value in mesh.indices {
        if int(value) == center_index {
            center_use = int(index)
            break
        }
    }
    testing.expect(t, center_use >= 0)
    first_ring_vertex := mesh.vertices[mesh.indices[center_use + 1]]
    testing.expect(t, first_ring_vertex.pavement == .Asphalt)
}

@(test)
road_graph_rejects_invalid_topology :: proc(t: ^testing.T) {
    graph: roads.Graph
    only := roads.add_node(&graph, {0, 0, 0})
    testing.expect(t, roads.add_straight_edge(&graph, only, only, 5) == -1)
    testing.expect(t, roads.add_straight_edge(&graph, only, 12, 5) == -1)
    testing.expect(t, graph.edge_count == 0)
}

@(test)
road_node_removal_culls_incident_edges_and_remaps_topology :: proc(t: ^testing.T) {
    graph: roads.Graph
    a := roads.add_node(&graph, {0, 0, 0})
    b := roads.add_node(&graph, {10, 0, 0})
    c := roads.add_node(&graph, {20, 0, 0})
    roads.add_straight_edge(&graph, a, b, 5)
    roads.add_straight_edge(&graph, b, c, 5)
    testing.expect(t, roads.edge_between(&graph, a, b) >= 0)
    testing.expect(t, roads.remove_node(&graph, b))
    testing.expect(t, graph.node_count == 2)
    testing.expect(t, graph.edge_count == 0)
    testing.expect(t, graph.nodes[1].position.x == 20)
}

@(test)
road_bake_preserves_mixed_edge_pavements :: proc(t: ^testing.T) {
    graph: roads.Graph
    a := roads.add_node(&graph, {0, 0, 0})
    b := roads.add_node(&graph, {20, 0, 0})
    c := roads.add_node(&graph, {40, 0, 10})
    roads.add_straight_edge(&graph, a, b, 6, 1, .Gravel)
    roads.add_straight_edge(&graph, b, c, 6, 1, .Cobblestone)
    mesh := roads.bake(&graph)
    defer roads.mesh_destroy(&mesh)
    saw_gravel, saw_cobble := false, false
    for vertex in mesh.vertices {
        if vertex.surface != .Road do continue
        saw_gravel = saw_gravel || vertex.pavement == .Gravel
        saw_cobble = saw_cobble || vertex.pavement == .Cobblestone
    }
    testing.expect(t, saw_gravel && saw_cobble)
    testing.expect(t, roads.pavement_next(.Dirt) == .Asphalt)
}

@(test)
road_default_profile_keeps_outer_shoulders_above_the_spline :: proc(t: ^testing.T) {
    settings := roads.default_bake_settings()
    testing.expect(t, settings.surface_lift > settings.shoulder_drop)
    testing.expect(t, settings.surface_lift - settings.shoulder_drop >= .05)
}

@(test)
road_pavement_query_classifies_surface_and_offroad_contacts :: proc(t: ^testing.T) {
    graph: roads.Graph
    a := roads.add_node(&graph, {0, 0, 0})
    b := roads.add_node(&graph, {30, 0, 0})
    roads.add_straight_edge(&graph, a, b, 8, 1.5, .Gravel)

    center := roads.pavement_at(&graph, {15, 0, .5})
    testing.expect(t, center.on_surface)
    testing.expect(t, center.pavement == .Gravel)
    testing.expect(t, center.edge_index == 0)
    testing.expect(t, center.distance < .6)

    offroad := roads.pavement_at(&graph, {15, 0, 8})
    testing.expect(t, !offroad.on_surface)
    testing.expect(t, offroad.pavement == .Gravel)
    testing.expect(t, offroad.distance > 7.9)
}

@(test)
road_pavement_query_keeps_wide_road_surface_when_narrow_branch_is_nearer :: proc(t: ^testing.T) {
    graph: roads.Graph
    wide_from := roads.add_node(&graph, {0, 0, 0})
    junction := roads.add_node(&graph, {30, 0, 0})
    narrow_to := roads.add_node(&graph, {30, 0, 30})
    roads.add_straight_edge(&graph, wide_from, junction, 8, 2, .Asphalt)
    roads.add_straight_edge(&graph, junction, narrow_to, 1, 0, .Dirt)

    // This point is inside the wide asphalt corridor, but the connected dirt
    // branch has the closer centerline.
    surface := roads.pavement_at(&graph, {25, 0, 5.5})
    testing.expect(t, surface.on_surface)
    testing.expect(t, surface.pavement == .Asphalt)
    testing.expect(t, surface.edge_index == 0)
    testing.expect(t, surface.distance > 5.4)
}

@(test)
road_material_grip_profiles_have_predictable_ordering :: proc(t: ^testing.T) {
    asphalt := roads.pavement_grip(.Asphalt)
    cobble := roads.pavement_grip(.Cobblestone)
    gravel := roads.pavement_grip(.Gravel)
    dirt := roads.pavement_grip(.Dirt)
    grass := roads.offroad_grip()

    testing.expect(t, asphalt.lateral > cobble.lateral)
    testing.expect(t, cobble.lateral > gravel.lateral)
    testing.expect(t, gravel.lateral > dirt.lateral)
    testing.expect(t, dirt.lateral > grass.lateral)
    testing.expect(t, asphalt.longitudinal > cobble.longitudinal)
    testing.expect(t, cobble.longitudinal > gravel.longitudinal)
    testing.expect(t, gravel.longitudinal > dirt.longitudinal)
    testing.expect(t, dirt.longitudinal > grass.longitudinal)
    testing.expect(t, asphalt.rolling_resistance < grass.rolling_resistance)
}

@(test)
road_material_roughness_is_deterministic_and_cobble_led :: proc(t: ^testing.T) {
    asphalt := roads.pavement_roughness(.Asphalt)
    gravel := roads.pavement_roughness(.Gravel)
    cobble := roads.pavement_roughness(.Cobblestone)
    dirt := roads.pavement_roughness(.Dirt)
    testing.expect(t, cobble.acceleration > dirt.acceleration)
    testing.expect(t, dirt.acceleration > gravel.acceleration)
    testing.expect(t, gravel.acceleration > asphalt.acceleration)

    first := roads.pavement_bump_acceleration(.Cobblestone, 12.3, -4.7, 10)
    second := roads.pavement_bump_acceleration(.Cobblestone, 12.3, -4.7, 10)
    testing.expect(t, first == second)
    testing.expect(t, roads.pavement_bump_acceleration(.Cobblestone, 12.3, -4.7, 0) == 0)
    testing.expect(t, math.abs(first) <= cobble.acceleration + .001)
}
