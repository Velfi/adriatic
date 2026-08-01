package main

import fixture_v0016 "../packages/fixture_history/v0016"
import roads "../packages/roads"
import "core:testing"

@(test)
fixture_migration_v0016_to_v0017_preserves_legacy_road_behavior :: proc(t: ^testing.T) {
    historical := new(fixture_v0016.Fixture)
    tentative := new(Fixture)
    defer free(historical)
    defer free(tentative)
    graph := &tentative.project.road_graph
    from := roads.add_node(graph, {0, 2, 0})
    to := roads.add_node(graph, {40, 7, 10})
    edge_index := roads.add_straight_edge(graph, from, to, 7, 1.25, .Cobblestone)
    edge := &graph.edges[edge_index]
    edge.design_id = 42
    edge.alignment_kind = .Arc
    edge.structure_kind = .Bridge
    edge.engineering_designed = true
    edge.authored_profile = true

    migration_error := fixture_migrate_v0016_to_v0017(historical^, tentative, context.allocator)
    testing.expect(t, migration_error.kind == .None)
    testing.expect_value(t, edge.pavement, roads.Pavement.Cobblestone)
    testing.expect_value(t, edge.policy_pavement, roads.Pavement.Cobblestone)
    testing.expect_value(t, edge.design_id, u32(0))
    testing.expect_value(t, edge.alignment_kind, roads.Alignment_Element_Kind.Legacy_Bezier)
    testing.expect_value(t, edge.structure_kind, roads.Structure_Span_Kind.Legacy_Automatic)
    testing.expect(t, !edge.engineering_designed && !edge.authored_profile)
}

@(test)
fixture_v0017_rejects_inconsistent_legacy_metadata :: proc(t: ^testing.T) {
    fixture := new(Fixture)
    defer free(fixture)
    graph := &fixture.project.road_graph
    from := roads.add_node(graph, {})
    to := roads.add_node(graph, {10, 0, 0})
    edge := roads.add_straight_edge(graph, from, to, 4)
    graph.edges[edge].design_id = 9
    graph.edges[edge].policy_pavement = graph.edges[edge].pavement
    migration_error := fixture_v0017_validate_road_design(fixture)
    testing.expect_value(t, migration_error.kind, Fixture_Migration_Error_Kind.Invalid_Source)
}

