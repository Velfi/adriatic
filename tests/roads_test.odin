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
    saw_road, saw_shoulder, saw_junction := false, false, false
    for vertex in mesh.vertices {
        saw_road = saw_road || vertex.surface == .Road
        saw_shoulder = saw_shoulder || vertex.surface == .Shoulder
        saw_junction = saw_junction || vertex.surface == .Junction
    }
    testing.expect(t, saw_road && saw_shoulder && saw_junction)
    for index in mesh.indices do testing.expect(t, int(index) < len(mesh.vertices))
}

@(test)
road_t_junction_bakes_one_merged_cap_at_shared_node :: proc(t: ^testing.T) {
    graph: roads.Graph
    west := roads.add_node(&graph, {-20, 0, 0}, 2)
    junction := roads.add_node(&graph, {0, 1, 0}, 5)
    east := roads.add_node(&graph, {20, 2, 0}, 2)
    north := roads.add_node(&graph, {0, 4, 20}, 2)
    roads.add_straight_edge(&graph, west, junction, 6)
    roads.add_straight_edge(&graph, junction, east, 6)
    roads.add_edge(&graph, junction, north, {0, 2, 7}, {0, 3, 14}, 8)
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
    center_index_uses := 0
    for index in mesh.indices {
        if int(index) == shared_center do center_index_uses += 1
    }
    testing.expect(t, center_index_uses == 6)
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
