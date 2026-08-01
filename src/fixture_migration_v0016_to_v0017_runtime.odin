package main

import "core:mem"

fixture_migration_step_v0016_to_v0017 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       step_context.source_version < 1 ||
       step_context.source_version > 16 ||
       step_context.step_from_version != FIXTURE_MIGRATION_V0016_TO_V0017_FROM_VERSION ||
       step_context.step_to_version != FIXTURE_MIGRATION_V0016_TO_V0017_TO_VERSION ||
       step_context.target_version < step_context.step_to_version ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }
    graph := &step_context.tentative.project.road_graph
    if graph.edge_count < 0 || graph.edge_count > len(graph.edges) {
        return {kind = .Invalid_Source, change_id = "field-add:adriatic:packages/roads.Edge.design_id"}
    }
    for &edge in graph.edges[:graph.edge_count] {
        edge.design_id = 0
        edge.alignment_kind = .Legacy_Bezier
        edge.station_from, edge.station_to = 0, 0
        edge.curvature_from, edge.curvature_to = 0, 0
        edge.superelevation_from, edge.superelevation_to = 0, 0
        edge.structure_kind = .Legacy_Automatic
        edge.engineering_designed = false
        edge.policy_pavement = edge.pavement
        edge.authored_profile = false
    }
    return fixture_v0017_validate_road_design(step_context.tentative)
}
