package road_designer

import roads "../roads"
import "core:testing"

flat_request :: proc(heights: []f32, pavement: roads.Pavement = .Gravel) -> Design_Request {
    return {
        grid = {origin_x = 0, origin_z = 0, width = 32, height = 32, sea_level = 0, heights = heights},
        cell_size = 8,
        start = {16, 64},
        finish = {224, 176},
        pavement = pavement,
        width = 7,
        shoulder = 1.25,
        sea_level = 0,
        available_nodes = 64,
        available_edges = 128,
        seed = 0x524f4144,
    }
}

@(test)
surface_policies_match_engineering_defaults :: proc(t: ^testing.T) {
    asphalt := policy_for_pavement(.Asphalt)
    gravel := policy_for_pavement(.Gravel)
    cobble := policy_for_pavement(.Cobblestone)
    dirt := policy_for_pavement(.Dirt)
    testing.expect_value(t, asphalt.design_speed_kph, f32(60))
    testing.expect_value(t, asphalt.maximum_grade, f32(.10))
    testing.expect_value(t, asphalt.minimum_radius, f32(70))
    testing.expect_value(t, gravel.minimum_radius, f32(32))
    testing.expect_value(t, cobble.minimum_spiral_length, f32(8))
    testing.expect_value(t, dirt.maximum_grade, f32(.20))
    testing.expect(t, !asphalt.switchbacks_allowed)
    testing.expect(t, gravel.switchbacks_allowed)
}

@(test)
progressive_optimizer_is_deterministic :: proc(t: ^testing.T) {
    heights: [32 * 32]f32
    request := flat_request(heights[:])
    first, second := new(Optimizer), new(Optimizer)
    defer free(first)
    defer free(second)
    first_work, second_work := new(Workspace), new(Workspace)
    defer free(first_work)
    defer free(second_work)
    testing.expect_value(t, begin(first, request, first_work), Optimizer_Status.Running)
    testing.expect_value(t, begin(second, request, second_work), Optimizer_Status.Running)
    for _ in 0 ..< 14 {
        _ = step(first, 8)
        _ = step(second, 8)
    }
    testing.expect_value(t, first.generation, second.generation)
    testing.expect_value(t, first.evaluations, second.evaluations)
    a, a_ok := candidate(first, .Recommended)
    b, b_ok := candidate(second, .Recommended)
    testing.expect(t, a_ok && b_ok)
    if a_ok && b_ok {
        testing.expect_value(t, a.id, b.id)
        testing.expect_value(t, a.metrics, b.metrics)
        testing.expect_value(t, a.point_count, b.point_count)
    }
}

@(test)
optimizer_reports_capacity_without_mutation :: proc(t: ^testing.T) {
    heights: [32 * 32]f32
    request := flat_request(heights[:])
    request.available_nodes = 1
    optimizer := new(Optimizer)
    defer free(optimizer)
    work := new(Workspace)
    defer free(work)
    testing.expect_value(t, begin(optimizer, request, work), Optimizer_Status.Capacity)
    testing.expect_value(t, optimizer.evaluations, 0)
}

@(test)
water_crossing_produces_an_explicit_structure :: proc(t: ^testing.T) {
    heights: [32 * 32]f32
    for z in 0 ..< 32 {
        for x in 13 ..< 17 do heights[z * 32 + x] = -2
    }
    request := flat_request(heights[:], .Dirt)
    optimizer := new(Optimizer)
    defer free(optimizer)
    work := new(Workspace)
    defer free(work)
    testing.expect_value(t, begin(optimizer, request, work), Optimizer_Status.Running)
    for _ in 0 ..< 7 do _ = step(optimizer, 8)
    value, ok := candidate(optimizer, .Recommended)
    testing.expect(t, ok)
    if ok do testing.expect(t, value.structure_count > 0)
}

@(test)
cancel_preserves_completed_candidates :: proc(t: ^testing.T) {
    heights: [32 * 32]f32
    optimizer := new(Optimizer)
    defer free(optimizer)
    work := new(Workspace)
    defer free(work)
    testing.expect_value(t, begin(optimizer, flat_request(heights[:]), work), Optimizer_Status.Running)
    _ = step(optimizer, POPULATION_SIZE)
    cancel(optimizer)
    testing.expect_value(t, optimizer.status, Optimizer_Status.Cancelled)
    evaluations := optimizer.evaluations
    _ = step(optimizer, 8)
    testing.expect_value(t, optimizer.evaluations, evaluations)
}

@(test)
hard_horizontal_violations_are_not_feasible :: proc(t: ^testing.T) {
    heights: [32 * 32]f32
    request := flat_request(heights[:], .Asphalt)
    candidate: Design_Candidate
    candidate.point_count = 3
    candidate.centerline[0] = {0, 0, 0}
    candidate.centerline[1] = {4, 0, 0}
    candidate.centerline[2] = {4, 0, 4}
    candidate.metrics.minimum_radius = 2
    candidate.genome.point_count = 3
    candidate.genome.radii[1] = 2
    candidate.genome.spirals[1] = 1
    testing.expect(t, !horizontal_constraints_hold(&candidate, request, policy_for_pavement(.Asphalt)))
}

@(test)
nondominated_sort_assigns_fronts_and_crowding :: proc(t: ^testing.T) {
    candidates: [4]Design_Candidate
    for &item in candidates do item.feasibility = .Feasible
    candidates[0].metrics = {construction = 1, travel = 4, impact = 4}
    candidates[1].metrics = {construction = 4, travel = 1, impact = 4}
    candidates[2].metrics = {construction = 4, travel = 4, impact = 1}
    candidates[3].metrics = {construction = 5, travel = 5, impact = 5}
    assign_fronts_and_crowding(candidates[:])
    testing.expect(t, candidates[0].pareto_rank == 0 && candidates[1].pareto_rank == 0 && candidates[2].pareto_rank == 0)
    testing.expect_value(t, candidates[3].pareto_rank, 1)
    testing.expect(t, candidates[0].crowding > 0 && candidates[1].crowding > 0 && candidates[2].crowding > 0)
}

@(test)
materialization_splits_at_structure_boundaries :: proc(t: ^testing.T) {
    candidate: Design_Candidate
    candidate.feasibility = .Feasible
    candidate.pavement = .Gravel
    candidate.width, candidate.shoulder = 7, 1
    candidate.genome.point_count = 2
    candidate.point_count = 3
    candidate.centerline[0] = {0, 5, 0}
    candidate.centerline[1] = {50, 5, 0}
    candidate.centerline[2] = {100, 5, 0}
    candidate.stations[0], candidate.stations[1], candidate.stations[2] = 0, 50, 100
    candidate.structure_count = 1
    candidate.structures[0] = {kind = .Bridge, station_from = 40, station_to = 60}
    graph: roads.Graph
    from := roads.add_node(&graph, candidate.centerline[0])
    to := roads.add_node(&graph, candidate.centerline[2])
    result := materialize_between(&candidate, &graph, 9, from, to)
    testing.expect(t, result.ok)
    testing.expect_value(t, result.edge_count, 3)
    if result.ok {
        testing.expect_value(t, graph.edges[result.first_edge].structure_kind, roads.Structure_Span_Kind.At_Grade)
        testing.expect_value(t, graph.edges[result.first_edge + 1].structure_kind, roads.Structure_Span_Kind.Bridge)
        testing.expect_value(t, graph.edges[result.first_edge + 2].structure_kind, roads.Structure_Span_Kind.At_Grade)
        testing.expect_value(t, graph.edges[result.first_edge + 1].station_from, f32(40))
        testing.expect_value(t, graph.edges[result.first_edge + 1].station_to, f32(60))
    }
}
