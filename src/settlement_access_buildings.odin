package main

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"

settlement_access_max_shared_width_step :: proc(
    city_plan: ^architecture.City_Plan,
    demand: []int,
    segment_count: int,
) -> f32 {
    result: f32
    if city_plan == nil do return result
    count := min(segment_count, min(city_plan.alley_count, len(demand)))
    for first, first_index in city_plan.alleys[:count] {
        if demand[first_index] < 2 do continue
        first_points := [2][2]f32{{first.start_x, first.start_z}, {first.end_x, first.end_z}}
        first_terminals := [2]architecture.City_Alley_Terminal{first.start_terminal, first.end_terminal}
        for second, second_offset in city_plan.alleys[first_index + 1:count] {
            second_index := first_index + 1 + second_offset
            if demand[second_index] < 2 do continue
            second_points := [2][2]f32{{second.start_x, second.start_z}, {second.end_x, second.end_z}}
            second_terminals := [2]architecture.City_Alley_Terminal{second.start_terminal, second.end_terminal}
            for first_endpoint_index in 0 ..< 2 {
                for second_endpoint_index in 0 ..< 2 {
                    point := first_points[first_endpoint_index]
                    if first_terminals[first_endpoint_index] != .None ||
                       second_terminals[second_endpoint_index] != .None ||
                       !settlement_alley_point_near(point, second_points[second_endpoint_index]) ||
                       settlement_access_network_degree(city_plan, point) != 2 {
                        continue
                    }
                    result = max(result, math.abs(first.half_width - second.half_width))
                }
            }
        }
    }
    return result
}

settlement_access_shared_desired_half_width :: proc(original: f32, household_demand: int) -> f32 {
    desired := original
    if household_demand >= 2 {
        desired += .1
        if household_demand >= 4 do desired += .1
        if household_demand >= 8 do desired += .1
        if household_demand >= 16 do desired += .1
    }
    // Three or more households sharing an offshoot are no longer using a
    // private footpath. Reserve a passable local lane so neighbors are served
    // from common frontage rather than walking single-file past one another.
    if household_demand >= 3 do desired = max(desired, f32(.9))
    return min(desired, f32(1.25))
}

settlement_access_network_candidate_limit :: proc(scale: Settlement_Scale, road_distance: f32) -> f32 {
    factor := f32(.90)
    switch scale {
    case .City:
        factor = 1
    case .Town:
        // A slightly longer doorstep branch is worthwhile when it replaces a
        // second parallel path with one shared hillside passage.
        factor = 1.08
    case .Village:
        factor = .90
    }
    return max(road_distance, f32(0)) * factor
}

settlement_access_building_attachment :: proc(
    city_plan: ^architecture.City_Plan,
    structure: terrain.Structure,
) -> (
    point: [2]f32,
    found: bool,
) {
    if city_plan == nil do return
    door := settlement_structure_front_door_point(structure)
    for alley in city_plan.alleys[:city_plan.alley_count] {
        start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
        if settlement_alley_point_near(door, start) && alley.start_terminal == .Door {
            return finish, true
        }
        if settlement_alley_point_near(door, finish) && alley.end_terminal == .Door {
            return start, true
        }
    }
    return
}

settlement_access_graph_distance :: proc(city_plan: ^architecture.City_Plan, start, finish: [2]f32) -> f32 {
    if city_plan == nil || city_plan.alley_count <= 0 do return 1e30
    capacity :: SETTLEMENT_SITE_CAPACITY * 8
    count := min(city_plan.alley_count, capacity)
    costs: [capacity]f32
    closed: [capacity]bool
    for index in 0 ..< count {
        costs[index] = 1e30
        alley := city_plan.alleys[index]
        a, b := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
        if settlement_alley_point_near(start, a) || settlement_alley_point_near(start, b) {
            costs[index] = settlement_access_alley_length(city_plan, index)
        }
    }
    for _ in 0 ..< count {
        current, best := -1, f32(1e30)
        for index in 0 ..< count {
            if !closed[index] && costs[index] < best {
                current, best = index, costs[index]
            }
        }
        if current < 0 do break
        closed[current] = true
        alley := city_plan.alleys[current]
        endpoints := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
        if settlement_alley_point_near(finish, endpoints[0]) || settlement_alley_point_near(finish, endpoints[1]) {
            return costs[current]
        }
        for neighbor in 0 ..< count {
            if closed[neighbor] || neighbor == current do continue
            candidate := city_plan.alleys[neighbor]
            candidate_endpoints := [2][2]f32 {
                {candidate.start_x, candidate.start_z},
                {candidate.end_x, candidate.end_z},
            }
            connected := false
            for endpoint in endpoints {
                if settlement_alley_point_near(endpoint, candidate_endpoints[0]) ||
                   settlement_alley_point_near(endpoint, candidate_endpoints[1]) {
                    connected = true
                    break
                }
            }
            if !connected do continue
            candidate_cost := costs[current] + settlement_access_alley_length(city_plan, neighbor)
            if candidate_cost < costs[neighbor] do costs[neighbor] = candidate_cost
        }
    }
    return 1e30
}

settlement_circulation_link_half_width :: proc(scale: Settlement_Scale) -> f32 {
    return scale == .Town ? f32(.75) : f32(1.2)
}

// Improve the access graph before assigning widths. Sample plausible trips
// between buildings and add a pedestrian cross-link only when the current
// network sends that trip on a substantial detour. Repeating after every
// accepted link lets later samples judge the improved graph rather than
// blindly drawing an all-pairs web.
settlement_access_promote_circulation_links :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan,
) {
    if plan == nil || project == nil || city_plan == nil || city_plan.count < 3 do return
    link_budget := 3
    switch plan.request.scale {
    case .City:
        link_budget = 12
    case .Town:
        // A few cross-passages make the hillside walkable; eight optional
        // shortcuts on a compact town overdraw the fabric with a second web
        // after every doorstep is already connected.
        link_budget = 4
    case .Village:
        link_budget = 3
    }
    capacity :: SETTLEMENT_SITE_CAPACITY
    building_count := min(city_plan.count, capacity)
    attachments: [capacity][2]f32
    attached: [capacity]bool
    for structure, structure_index in city_plan.structures[:building_count] {
        attachments[structure_index], attached[structure_index] = settlement_access_building_attachment(
            city_plan,
            structure,
        )
    }
    rejected: [capacity][capacity]bool
    accepted := 0
    for _ in 0 ..< link_budget * 8 {
        if accepted >= link_budget do break
        best_source, best_destination := -1, -1
        best_existing, best_score := f32(0), f32(-1e30)
        for source_index in 0 ..< building_count {
            if !attached[source_index] do continue
            nearest_indices := [4]int{-1, -1, -1, -1}
            nearest_distances := [4]f32{1e30, 1e30, 1e30, 1e30}
            for destination_index in 0 ..< building_count {
                unavailable :=
                    destination_index == source_index ||
                    !attached[destination_index] ||
                    rejected[source_index][destination_index]
                if unavailable do continue
                direct_distance := linalg.length(attachments[destination_index] - attachments[source_index])
                if direct_distance < 5 || direct_distance > 34 do continue
                insertion := 3
                if direct_distance >= nearest_distances[insertion] do continue
                for insertion > 0 && direct_distance < nearest_distances[insertion - 1] {
                    nearest_indices[insertion] = nearest_indices[insertion - 1]
                    nearest_distances[insertion] = nearest_distances[insertion - 1]
                    insertion -= 1
                }
                nearest_indices[insertion], nearest_distances[insertion] = destination_index, direct_distance
            }
            for neighbor_slot in 0 ..< len(nearest_indices) {
                destination_index := nearest_indices[neighbor_slot]
                if destination_index < 0 do continue
                direct_distance := nearest_distances[neighbor_slot]
                existing_distance := settlement_access_graph_distance(
                    city_plan,
                    attachments[source_index],
                    attachments[destination_index],
                )
                if existing_distance >= 1e29 || existing_distance < direct_distance * 1.4 do continue
                score := existing_distance - direct_distance + existing_distance / direct_distance * 3
                if score > best_score {
                    best_source, best_destination = source_index, destination_index
                    best_existing, best_score = existing_distance, score
                }
            }
        }
        if best_source < 0 do break
        rejected[best_source][best_destination] = true
        rejected[best_destination][best_source] = true
        source, destination := attachments[best_source], attachments[best_destination]
        path := settlement_access_path_find(project, city_plan, source, destination, -1, .9, true)
        if path.count < 2 do continue
        path_length := f32(0)
        for point_index in 0 ..< path.count - 1 {
            path_length += linalg.length(path.points[point_index + 1] - path.points[point_index])
        }
        if path_length >= best_existing * .82 do continue
        passage_half_width := settlement_circulation_link_half_width(plan.request.scale)
        for point_index in 0 ..< path.count - 1 {
            append(&city_plan.alleys, architecture.City_Alley {
                start_x    = path.points[point_index][0],
                start_z    = path.points[point_index][1],
                end_x      = path.points[point_index + 1][0],
                end_z      = path.points[point_index + 1][1],
                half_width = passage_half_width,
            })
            city_plan.alley_count += 1
        }
        settlement_access_split_intersections(city_plan)
        settlement_access_deduplicate_segments(city_plan)
        settlement_access_snap_near_endpoints(city_plan)
        settlement_access_remove_degenerate_segments(city_plan)
        accepted += 1
    }
}

// Route one synthetic pedestrian journey over the finished access graph and
// accumulate its use on every selected segment. Door-to-road demand alone
// produces a collection of spokes; sampled door-to-door journeys reveal the
// shared cross-town lines that naturally become lanes and passages.
settlement_access_accumulate_building_journey :: proc(
    city_plan: ^architecture.City_Plan,
    travel_length: []f32,
    segment_count: int,
    start, finish: [2]f32,
    demand: []int,
) -> bool {
    if city_plan == nil || segment_count <= 0 || len(demand) < segment_count do return false
    capacity :: SETTLEMENT_SITE_CAPACITY * 8
    count := min(segment_count, min(capacity, city_plan.alley_count))
    costs: [capacity]f32
    parents: [capacity]int
    closed: [capacity]bool
    for index in 0 ..< count {
        costs[index], parents[index] = 1e30, -2
        alley := city_plan.alleys[index]
        a, b := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
        if settlement_alley_point_near(start, a) || settlement_alley_point_near(start, b) {
            costs[index] = travel_length[index]
            parents[index] = -1
        }
    }
    target := -1
    for _ in 0 ..< count {
        current, best := -1, f32(1e30)
        for index in 0 ..< count {
            if !closed[index] && costs[index] < best {
                current, best = index, costs[index]
            }
        }
        if current < 0 do break
        closed[current] = true
        alley := city_plan.alleys[current]
        endpoints := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
        if settlement_alley_point_near(finish, endpoints[0]) || settlement_alley_point_near(finish, endpoints[1]) {
            target = current
            break
        }
        for neighbor in 0 ..< count {
            if closed[neighbor] || neighbor == current do continue
            candidate := city_plan.alleys[neighbor]
            candidate_endpoints := [2][2]f32 {
                {candidate.start_x, candidate.start_z},
                {candidate.end_x, candidate.end_z},
            }
            connected := false
            for endpoint in endpoints {
                if settlement_alley_point_near(endpoint, candidate_endpoints[0]) ||
                   settlement_alley_point_near(endpoint, candidate_endpoints[1]) {
                    connected = true
                    break
                }
            }
            if !connected do continue
            candidate_cost := costs[current] + travel_length[neighbor]
            if candidate_cost >= costs[neighbor] do continue
            costs[neighbor], parents[neighbor] = candidate_cost, current
        }
    }
    if target < 0 do return false
    journey: [capacity]int
    journey_count := 0
    cursor := target
    for cursor >= 0 && journey_count < len(journey) {
        journey[journey_count] = cursor
        journey_count += 1
        cursor = parents[cursor]
    }
    // The first and last edges are private approaches to the sampled doors.
    // Promote only repeated interior circulation; ordinary door-to-road
    // analysis remains responsible for doorstep width.
    if journey_count > 2 {
        for index in 1 ..< journey_count - 1 do demand[journey[index]] += 1
    }
    return true
}

settlement_access_widen_shared_trunks :: proc(plan: ^Settlement_Plan, city_plan: ^architecture.City_Plan) {
    if plan == nil || city_plan == nil do return
    segment_capacity :: SETTLEMENT_SITE_CAPACITY * 8
    segment_count := min(city_plan.alley_count, segment_capacity)
    demand: [segment_capacity]int
    working_width: [segment_capacity]f32
    travel_length: [segment_capacity]f32
    for alley_index in 0 ..< segment_count {
        travel_length[alley_index] = settlement_access_alley_length(city_plan, alley_index)
    }
    road_connected_segments := make([]bool, city_plan.alley_count, context.temp_allocator)
    settlement_access_mark_road_connected_segments(plan, city_plan, road_connected_segments)
    graph_connected := 0
    for structure in city_plan.structures[:city_plan.count] {
        door := settlement_structure_front_door_point(structure)
        journey_half_width: f32
        if settlement_access_point_at_road_edge(plan, door) {
            graph_connected += 1
            continue
        }
        for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
            if !road_connected_segments[alley_index] do continue
            start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
            if settlement_alley_point_near(door, start) || settlement_alley_point_near(door, finish) {
                journey_half_width = max(journey_half_width, alley.half_width)
                graph_connected += 1
                break
            }
        }
        costs: [segment_capacity]f32
        parents: [segment_capacity]int
        closed: [segment_capacity]bool
        for index in 0 ..< segment_count {
            costs[index], parents[index] = 1e30, -2
            alley := city_plan.alleys[index]
            start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
            if settlement_alley_point_near(door, start) || settlement_alley_point_near(door, finish) {
                journey_half_width = max(journey_half_width, alley.half_width)
                costs[index] = travel_length[index]
                parents[index] = -1
            }
        }
        target := -1
        for _ in 0 ..< segment_count {
            current, best := -1, f32(1e30)
            for index in 0 ..< segment_count {
                if !closed[index] && costs[index] < best {
                    current, best = index, costs[index]
                }
            }
            if current < 0 do break
            closed[current] = true
            alley := city_plan.alleys[current]
            endpoints := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
            terminals := [2]architecture.City_Alley_Terminal{alley.start_terminal, alley.end_terminal}
            for endpoint, endpoint_index in endpoints {
                if settlement_access_network_degree(city_plan, endpoint) != 1 do continue
                if terminals[endpoint_index] == .Road {
                    target = current
                    break
                }
                near_road, aligned := settlement_access_road_approach_aligned(
                    plan,
                    endpoint,
                    endpoints[1 - endpoint_index] - endpoint,
                )
                if near_road && aligned {
                    target = current
                    break
                }
            }
            if target >= 0 do break
            for neighbor in 0 ..< segment_count {
                if closed[neighbor] || neighbor == current do continue
                candidate := city_plan.alleys[neighbor]
                candidate_endpoints := [2][2]f32 {
                    {candidate.start_x, candidate.start_z},
                    {candidate.end_x, candidate.end_z},
                }
                connected := false
                for endpoint in endpoints {
                    for candidate_endpoint in candidate_endpoints {
                        if settlement_alley_point_near(endpoint, candidate_endpoint) {
                            connected = true
                            break
                        }
                    }
                    if connected do break
                }
                if !connected do continue
                candidate_cost := costs[current] + travel_length[neighbor]
                if candidate_cost >= costs[neighbor] do continue
                costs[neighbor], parents[neighbor] = candidate_cost, current
            }
        }
        base_half_width := settlement_access_preferred_half_width(
            plan.request.scale,
            Settlement_Building_Purpose.Dwelling,
        )
        working_requirement := journey_half_width > base_half_width + .025 ? journey_half_width : f32(0)
        cursor := target
        for cursor >= 0 {
            demand[cursor] += 1
            working_width[cursor] = max(working_width[cursor], working_requirement)
            cursor = parents[cursor]
        }
    }
    // Sample a deterministic circulation matrix in addition to mandatory
    // door-to-road trips. Two destinations per building are enough to reveal
    // repeated neighborhood paths without turning this into an all-pairs
    // solve. The seed rotates pairings between generated towns while keeping
    // fixture loads and captures reproducible.
    if city_plan.count > 1 {
        seed_offset := int(plan.request.seed % u32(city_plan.count - 1))
        for source_index in 0 ..< city_plan.count {
            source := settlement_structure_front_door_point(city_plan.structures[source_index])
            for sample_index in 0 ..< 2 {
                offset := 1 + (seed_offset + source_index * 7 + sample_index * 11) % (city_plan.count - 1)
                destination_index := (source_index + offset) % city_plan.count
                destination := settlement_structure_front_door_point(city_plan.structures[destination_index])
                _ = settlement_access_accumulate_building_journey(
                    city_plan,
                    travel_length[:segment_count],
                    segment_count,
                    source,
                    destination,
                    demand[:segment_count],
                )
            }
        }
    }
    plan.access_connected_count = graph_connected
    plan.access_shared_segments = 0
    plan.access_widened_segments = 0
    for usage, segment_index in demand[:segment_count] {
        city_plan.alleys[segment_index].household_demand = u16(min(usage, 65535))
        working := working_width[segment_index] > 0
        if usage < 2 && !working do continue
        if usage >= 2 do plan.access_shared_segments += 1
        alley := &city_plan.alleys[segment_index]
        original := alley.half_width
        desired := settlement_access_shared_desired_half_width(original, usage)
        desired = max(desired, working_width[segment_index])
        candidate := original + .05
        for candidate <= desired + .001 {
            if !settlement_access_alley_width_clear(city_plan, segment_index, candidate) do break
            alley.half_width = candidate
            candidate += .05
        }
        if usage >= 2 && alley.half_width > original + .025 do plan.access_widened_segments += 1
    }
    // A constrained narrow segment can sit between wider segments. Finish
    // with a monotone, collision-safe relaxation over the degree-two graph.
    // This is the lower envelope of every existing width plus .15 m per edge:
    // it never widens pavement, so all previously proven clearances remain
    // valid, and it converges regardless of alley storage order.
    transition_edges: [segment_capacity * 2][2]int
    transition_edge_count := 0
    for first_index in 0 ..< segment_count {
        first_active := demand[first_index] >= 2 || working_width[first_index] > 0
        if !first_active do continue
        first := city_plan.alleys[first_index]
        first_points := [2][2]f32{{first.start_x, first.start_z}, {first.end_x, first.end_z}}
        first_terminals := [2]architecture.City_Alley_Terminal{first.start_terminal, first.end_terminal}
        for second_index in first_index + 1 ..< segment_count {
            second_active := demand[second_index] >= 2 || working_width[second_index] > 0
            if !second_active do continue
            second := city_plan.alleys[second_index]
            second_points := [2][2]f32{{second.start_x, second.start_z}, {second.end_x, second.end_z}}
            second_terminals := [2]architecture.City_Alley_Terminal{second.start_terminal, second.end_terminal}
            connected := false
            for first_endpoint_index in 0 ..< 2 {
                for second_endpoint_index in 0 ..< 2 {
                    point := first_points[first_endpoint_index]
                    if first_terminals[first_endpoint_index] == .None &&
                       second_terminals[second_endpoint_index] == .None &&
                       settlement_alley_point_near(point, second_points[second_endpoint_index]) &&
                       settlement_access_network_degree(city_plan, point) == 2 {
                        connected = true
                        break
                    }
                }
                if connected do break
            }
            if !connected || transition_edge_count >= len(transition_edges) do continue
            transition_edges[transition_edge_count] = {first_index, second_index}
            transition_edge_count += 1
        }
    }
    relaxed_widths: [segment_capacity]f32
    for index in 0 ..< segment_count do relaxed_widths[index] = city_plan.alleys[index].half_width
    transition_neighbors: [segment_capacity][2]int
    transition_neighbor_counts: [segment_capacity]int
    for edge in transition_edges[:transition_edge_count] {
        first_index, second_index := edge[0], edge[1]
        if transition_neighbor_counts[first_index] < len(transition_neighbors[first_index]) {
            slot := transition_neighbor_counts[first_index]
            transition_neighbors[first_index][slot] = second_index
            transition_neighbor_counts[first_index] += 1
        }
        if transition_neighbor_counts[second_index] < len(transition_neighbors[second_index]) {
            slot := transition_neighbor_counts[second_index]
            transition_neighbors[second_index][slot] = first_index
            transition_neighbor_counts[second_index] += 1
        }
    }
    // Degree-two continuity makes this graph a set of chains and cycles.
    // Propagate each narrower constraint through its immediate neighbors with
    // a queue instead of rescanning every edge for every segment.
    relaxation_queue: [segment_capacity]int
    queued: [segment_capacity]bool
    queue_head, queue_tail, queue_count := 0, 0, 0
    for index in 0 ..< segment_count {
        relaxation_queue[queue_tail] = index
        queue_tail = (queue_tail + 1) % len(relaxation_queue)
        queue_count += 1
        queued[index] = true
    }
    for queue_count > 0 {
        current := relaxation_queue[queue_head]
        queue_head = (queue_head + 1) % len(relaxation_queue)
        queue_count -= 1
        queued[current] = false
        for neighbor in transition_neighbors[current][:transition_neighbor_counts[current]] {
            limit := relaxed_widths[current] + .15
            if relaxed_widths[neighbor] <= limit + .0001 do continue
            relaxed_widths[neighbor] = limit
            if !queued[neighbor] {
                relaxation_queue[queue_tail] = neighbor
                queue_tail = (queue_tail + 1) % len(relaxation_queue)
                queue_count += 1
                queued[neighbor] = true
            }
        }
    }
    for index in 0 ..< segment_count {
        relaxed := min(city_plan.alleys[index].half_width, relaxed_widths[index])
        // A trunk serving three or more households is a shared side lane,
        // even when it meets a narrower private doorstep segment.
        if demand[index] >= 3 do relaxed = max(relaxed, f32(.9))
        city_plan.alleys[index].half_width = relaxed
    }
    plan.access_max_shared_width_step = settlement_access_max_shared_width_step(
        city_plan,
        demand[:segment_count],
        segment_count,
    )
}

settlement_access_append_public_path :: proc(
    city_plan: ^architecture.City_Plan,
    path: Settlement_Route,
    road_at_finish: bool = false,
) {
    if city_plan == nil || path.count < 2 do return
    for index in 0 ..< path.count - 1 {
        start_terminal := architecture.City_Alley_Terminal.None
        end_terminal := architecture.City_Alley_Terminal.None
        if index == 0 do start_terminal = .Public_Space
        if road_at_finish && index == path.count - 2 do end_terminal = .Road
        append(&city_plan.alleys, architecture.City_Alley {
            start_x        = path.points[index][0],
            start_z        = path.points[index][1],
            end_x          = path.points[index + 1][0],
            end_z          = path.points[index + 1][1],
            half_width     = 1.2,
            start_terminal = start_terminal,
            end_terminal   = end_terminal,
        })
        city_plan.alley_count += 1
    }
}

// Lay a public circulation architecture before private doorstep access exists.
// Begin with a grade- and obstacle-aware route from one building apron to the
// road, then grow new routes through previously unserved open space toward
// other sampled aprons. Door generation can subsequently attach short private
// spurs to this road-rooted network instead of inventing one road spoke per
// household.
