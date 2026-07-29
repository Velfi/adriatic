package tests

import roads "../packages/roads"
import "core:testing"

@(test)
roads_cached_pavement_query_matches_direct_query :: proc(t: ^testing.T) {
    graph: roads.Graph
    from := roads.add_node(&graph, {0, 2, 0})
    to := roads.add_node(&graph, {24, 4, 8})
    _ = roads.add_edge(&graph, from, to, {6, 2.5, -3}, {18, 3.5, 12}, 6, 1.25, .Cobblestone)

    query: roads.Pavement_Query
    roads.pavement_query_build(&graph, &query)
    samples := [4]roads.Vec3{{3, 0, 1}, {12, 0, 3}, {22, 0, 8}, {50, 0, 50}}
    for position in samples {
        direct := roads.pavement_at(&graph, position)
        cached := roads.pavement_at_cached(&graph, &query, position)
        testing.expect_value(t, cached, direct)
    }
}

@(test)
roads_cached_pavement_query_prunes_distant_edges_without_changing_nearest_results :: proc(t: ^testing.T) {
    graph: roads.Graph
    for edge_index in 0 ..< 32 {
        x := f32(edge_index * 100)
        from := roads.add_node(&graph, {x, 0, 0})
        to := roads.add_node(&graph, {x, 0, 20})
        _ = roads.add_straight_edge(&graph, from, to, 3, 1, .Gravel)
    }

    query: roads.Pavement_Query
    roads.pavement_query_build(&graph, &query)

    on_road := roads.pavement_at_cached(&graph, &query, {1601, 0, 10})
    testing.expect(t, on_road.on_surface)
    testing.expect(t, on_road.edge_index == 16)
    testing.expect(t, on_road.distance > .9 && on_road.distance < 1.1)
    testing.expect(t, query.last_candidate_edge_count < graph.edge_count / 2)

    // Even when no corridor contains the point, the hierarchy must retain
    // exact nearest-centerline behavior rather than only checking its first
    // local bucket.
    offroad := roads.pavement_at_cached(&graph, &query, {1640, 0, 40})
    testing.expect(t, !offroad.on_surface)
    testing.expect(t, offroad.edge_index == 16)
    testing.expect(t, offroad.distance > 44 && offroad.distance < 45)
    testing.expect(t, query.last_candidate_edge_count < graph.edge_count / 2)
}
