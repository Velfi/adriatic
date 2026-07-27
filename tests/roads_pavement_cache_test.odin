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
