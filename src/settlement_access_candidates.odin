package main

import architecture "../packages/architecture"
import roads "../packages/roads"
import "core:math"
import "core:math/linalg"

settlement_access_candidate_score :: proc(
    length, maximum_grade, grade_limit: f32,
    joins_network: bool,
    connection_shape_penalty: f32 = 0,
) -> f32 {
    // Among similarly direct choices, prefer the gentler construction.
    // Crossing the building-use grade target carries a strong penalty so a
    // modest contour detour beats a short stair-like service approach.
    score := length * (1 + maximum_grade * 2)
    score += max(f32(0), maximum_grade - grade_limit) * 120
    // Reusing a verified road-rooted trunk is slightly preferable to cutting
    // an independent verge spur when both journeys are otherwise comparable.
    if joins_network do score *= .72
    // Keep the network-reuse incentive, but let clean doorway throats and
    // legible junction geometry distinguish otherwise similar candidates.
    score += connection_shape_penalty
    return score
}

settlement_access_connection_shape_penalty :: proc(
    city_plan: ^architecture.City_Plan,
    path: Settlement_Route,
    door_outward: [2]f32,
    joins_network: bool,
) -> f32 {
    if path.count < 2 do return 1e30
    first := path.points[1] - path.points[0]
    first_length := linalg.length(first)
    outward_length := linalg.length(door_outward)
    if first_length <= .001 || outward_length <= .001 do return 1e30

    // The first visible run should leave the threshold square-on. A shallow
    // diagonal is substantially more expensive than a modest orthogonal
    // detour, while a route pointing back through the facade is effectively
    // disqualified by the larger negative-alignment penalty.
    doorway_alignment := linalg.dot(first, door_outward) / (first_length * outward_length)
    penalty := (1 - clamp(doorway_alignment, f32(-1), f32(1))) * 10
    if !joins_network || city_plan == nil do return penalty

    junction := path.points[path.count - 1]
    incoming := path.points[path.count - 2] - junction
    incoming_length := linalg.length(incoming)
    if incoming_length <= .001 do return 1e30

    degree := settlement_access_network_degree(city_plan, junction)
    // Reuse is good, but repeatedly adding arms to the same node creates a
    // starburst. Prefer a new T over a fourth arm, with sharply increasing
    // pressure as the existing junction becomes more complex.
    excess_degree := max(degree - 2, 0)
    penalty += f32(excess_degree * excess_degree) * 4

    best_axis_error := f32(1)
    for alley in city_plan.alleys[:city_plan.alley_count] {
        start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
        outgoing: [2]f32
        found := false
        if settlement_alley_point_near(junction, start) {
            outgoing, found = finish - junction, true
        } else if settlement_alley_point_near(junction, finish) {
            outgoing, found = start - junction, true
        }
        if !found do continue
        outgoing_length := linalg.length(outgoing)
        if outgoing_length <= .001 do continue
        absolute_alignment := math.abs(linalg.dot(incoming, outgoing) / (incoming_length * outgoing_length))
        // Zero is a square T/crossing and one is a straight continuation.
        // Values between them are skewed joins; score against the nearest
        // simple axis rather than prescribing which of the two is required.
        best_axis_error = min(best_axis_error, min(absolute_alignment, 1 - absolute_alignment))
    }
    if degree > 0 do penalty += best_axis_error * 12
    return penalty
}

settlement_access_surface :: proc(alley: architecture.City_Alley) -> Settlement_Access_Surface {
    if alley.household_demand >= 4 do return .Stone
    if alley.household_demand >= 2 || alley.half_width >= .8 do return .Gravel
    return .Packed_Earth
}

settlement_access_route_pavement :: proc(maximum_grade, width: f32) -> roads.Pavement {
    if maximum_grade >= SETTLEMENT_ACCESS_STAIR_GRADE do return .Steps
    if width >= 1.6 do return .Gravel
    return .Dirt
}

settlement_alley_point_near :: proc(a, b: [2]f32, epsilon: f32 = .05) -> bool {
    delta := a - b
    return linalg.dot(delta, delta) <= epsilon * epsilon
}

settlement_plaza_terminal_index :: proc(plan: ^Settlement_Plan, point: [2]f32, tolerance: f32 = 2.1) -> int {
    if plan == nil do return -1
    for edit, edit_index in plan.terrain_edits[:plan.terrain_edit_count] {
        if edit.kind != .Plaza do continue
        local := point - edit.center
        outside_x := max(math.abs(local[0]) - edit.half_extent[0], f32(0))
        outside_z := max(math.abs(local[1]) - edit.half_extent[1], f32(0))
        if outside_x * outside_x + outside_z * outside_z <= tolerance * tolerance {
            return edit_index
        }
    }
    return -1
}

settlement_access_segment_plaza_interval :: proc(
    start, finish, center, half_extent: [2]f32,
    margin: f32,
) -> (
    entry, exit: f32,
    intersects: bool,
) {
    delta := finish - start
    entry, exit = 0, 1
    expanded := half_extent + [2]f32{margin, margin}
    local_start := start - center
    for axis in 0 ..< 2 {
        if math.abs(delta[axis]) <= .000001 {
            if math.abs(local_start[axis]) > expanded[axis] do return 0, 0, false
            continue
        }
        near := (-expanded[axis] - local_start[axis]) / delta[axis]
        far := (expanded[axis] - local_start[axis]) / delta[axis]
        if near > far do near, far = far, near
        entry = max(entry, near)
        exit = min(exit, far)
        if entry > exit do return 0, 0, false
    }
    return entry, exit, true
}

// A plaza is itself the connecting surface. Paths terminate at its boundary
// instead of continuing invisibly beneath the paving; opposing boundary
// terminals remain connected through the plaza in graph traversal.
settlement_access_clip_to_plazas :: proc(plan: ^Settlement_Plan, city_plan: ^architecture.City_Plan) {
    if plan == nil || city_plan == nil do return
    for edit in plan.terrain_edits[:plan.terrain_edit_count] {
        if edit.kind != .Plaza do continue
        alley_index := 0
        for alley_index < city_plan.alley_count {
            alley := &city_plan.alleys[alley_index]
            start := [2]f32{alley.start_x, alley.start_z}
            finish := [2]f32{alley.end_x, alley.end_z}
            entry, exit, intersects := settlement_access_segment_plaza_interval(
                start,
                finish,
                edit.center,
                edit.half_extent,
                alley.half_width,
            )
            if !intersects || exit <= .0001 || entry >= .9999 {
                alley_index += 1
                continue
            }
            start_inside := entry <= .0001
            finish_inside := exit >= .9999
            if start_inside && finish_inside {
                city_plan.alley_count -= 1
                city_plan.alleys[alley_index] = city_plan.alleys[city_plan.alley_count]
                resize(&city_plan.alleys, city_plan.alley_count)
                continue
            }
            delta := finish - start
            if start_inside {
                clipped := start + delta * exit
                alley.start_x, alley.start_z = clipped[0], clipped[1]
                alley.start_terminal = .Public_Space
                alley.curve_ready = false
            } else if finish_inside {
                clipped := start + delta * entry
                alley.end_x, alley.end_z = clipped[0], clipped[1]
                alley.end_terminal = .Public_Space
                alley.curve_ready = false
            } else if city_plan.alley_count < SETTLEMENT_PLANNED_ROUTE_CAPACITY {
                far := alley^
                near_point := start + delta * entry
                far_point := start + delta * exit
                alley.end_x, alley.end_z = near_point[0], near_point[1]
                alley.end_terminal = .Public_Space
                alley.curve_ready = false
                far.start_x, far.start_z = far_point[0], far_point[1]
                far.start_terminal = .Public_Space
                far.curve_ready = false
                append(&city_plan.alleys, far)
                city_plan.alley_count += 1
            }
            alley_index += 1
        }
    }
}

settlement_access_network_degree :: proc(city_plan: ^architecture.City_Plan, point: [2]f32) -> int {
    if city_plan == nil do return 0
    degree := 0
    for alley in city_plan.alleys[:city_plan.alley_count] {
        start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
        if settlement_alley_point_near(point, start) {
            degree += 1
        } else if settlement_alley_point_near(point, finish) {
            degree += 1
        } else if settlement_point_segment_distance_squared(point, start, finish) <= .0025 {
            degree += 2
        }
    }
    return degree
}

settlement_access_node_paving_radius :: proc(city_plan: ^architecture.City_Plan, point: [2]f32) -> f32 {
    if city_plan == nil do return 0
    directions: [16][2]f32
    incident_count := 0
    radius: f32
    door_terminal := false
    public_terminal := false
    maximum_demand := 0
    for alley in city_plan.alleys[:city_plan.alley_count] {
        start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
        direction: [2]f32
        if settlement_alley_point_near(point, start) {
            direction = finish - point
            door_terminal = door_terminal || alley.start_terminal == .Door
            public_terminal = public_terminal || alley.start_terminal == .Public_Space
        } else if settlement_alley_point_near(point, finish) {
            direction = start - point
            door_terminal = door_terminal || alley.end_terminal == .Door
            public_terminal = public_terminal || alley.end_terminal == .Public_Space
        } else {
            continue
        }
        length := linalg.length(direction)
        if length <= .001 || incident_count >= len(directions) do continue
        directions[incident_count] = direction / length
        incident_count += 1
        radius = max(radius, alley.half_width)
        maximum_demand = max(maximum_demand, int(alley.household_demand))
    }
    if door_terminal do return 0
    if public_terminal && incident_count == 1 do return max(radius, f32(.9))
    if incident_count < 2 do return 0
    if incident_count == 2 && linalg.dot(directions[0], directions[1]) <= -.985 do return 0
    // A heavily reused turn or junction is the neighborhood's shared court,
    // not merely a circular cap between path rectangles. Keep low-demand
    // branches tight while giving proven communal nodes room to read as a
    // small paved place between houses.
    if maximum_demand >= 4 {
        if incident_count >= 3 do return max(radius, f32(1.8))
        return max(radius, f32(1.35))
    }
    return radius
}

settlement_access_snap_to_network_endpoint :: proc(city_plan: ^architecture.City_Plan, point: [2]f32) -> [2]f32 {
    if city_plan == nil do return point
    for alley in city_plan.alleys[:city_plan.alley_count] {
        endpoints := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
        for endpoint in endpoints {
            if settlement_alley_point_near(point, endpoint) do return endpoint
        }
    }
    return point
}

settlement_access_junction_location_valid :: proc(
    plan: ^Settlement_Plan,
    city_plan: ^architecture.City_Plan,
    point: [2]f32,
) -> bool {
    if plan == nil || city_plan == nil do return false
    for structure in city_plan.structures[:city_plan.count] {
        if linalg.length(point - settlement_structure_front_door_point(structure)) < 1.25 do return false
    }
    _, _, _, route_width, route_shoulder, route_distance, _, found := settlement_nearest_route_frame(plan, point)
    if found {
        road_edge_distance := route_width * .5 + route_shoulder + .45
        if route_distance >= road_edge_distance - .1 && route_distance <= road_edge_distance + 1.25 {
            return false
        }
    }
    return true
}

settlement_access_junction_angle_valid :: proc(city_plan: ^architecture.City_Plan, path: Settlement_Route) -> bool {
    if city_plan == nil || path.count < 2 do return false
    junction := path.points[path.count - 1]
    if settlement_access_network_degree(city_plan, junction) >= 4 do return false
    incoming := path.points[path.count - 2] - junction
    incoming_length := linalg.length(incoming)
    if incoming_length <= .001 do return false
    for alley in city_plan.alleys[:city_plan.alley_count] {
        start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
        outgoing_directions: [2][2]f32
        outgoing_count := 0
        if settlement_alley_point_near(junction, start) {
            outgoing_directions[outgoing_count], outgoing_count = finish - junction, outgoing_count + 1
        } else if settlement_alley_point_near(junction, finish) {
            outgoing_directions[outgoing_count], outgoing_count = start - junction, outgoing_count + 1
        } else if settlement_point_segment_distance_squared(junction, start, finish) <= .0025 {
            outgoing_directions[0], outgoing_directions[1], outgoing_count = start - junction, finish - junction, 2
        }
        for outgoing in outgoing_directions[:outgoing_count] {
            outgoing_length := linalg.length(outgoing)
            if outgoing_length <= .001 do continue
            alignment := linalg.dot(incoming, outgoing) / (incoming_length * outgoing_length)
            // Outward directions pointing into the same narrow sector create
            // a paved wedge. Near-opposite directions are a gently bending
            // through-path and remain valid.
            if alignment > .966 do return false
        }
    }
    return true
}

settlement_access_path_crossings_valid :: proc(
    city_plan: ^architecture.City_Plan,
    path: Settlement_Route,
    terminal_join: bool,
    protect_doorstep: bool = false,
) -> bool {
    if city_plan == nil || path.count < 2 do return false
    terminal := path.points[path.count - 1]
    // A valid walk cannot leave its doorstep and then double back through
    // that same threshold. Check the specific private-terminal invariant in
    // linear time; general crossings are normalized against the network
    // below.
    if protect_doorstep && path.count >= 4 {
        for segment_index in 2 ..< path.count - 1 {
            if settlement_point_segment_distance_squared(
                   path.points[0],
                   path.points[segment_index],
                   path.points[segment_index + 1],
               ) <=
               .0025 {
                return false
            }
        }
    }
    for point_index in 1 ..< path.count {
        point := path.points[point_index]
        at_terminal := terminal_join && point_index == path.count - 1
        if !at_terminal && settlement_access_network_degree(city_plan, point) > 0 do return false
    }
    for path_index in 0 ..< path.count - 1 {
        path_start, path_end := path.points[path_index], path.points[path_index + 1]
        for alley in city_plan.alleys[:city_plan.alley_count] {
            alley_start := [2]f32{alley.start_x, alley.start_z}
            alley_end := [2]f32{alley.end_x, alley.end_z}
            point, _, _, found := settlement_route_segment_intersection(path_start, path_end, alley_start, alley_end)
            if !found do continue
            at_terminal :=
                terminal_join && path_index == path.count - 2 && settlement_alley_point_near(point, terminal)
            if at_terminal do continue
            // Any earlier contact makes the path part of the existing
            // network, even when both segments happen to meet at endpoints.
            // It must relax to that contact and be validated as a junction.
            return false
        }
    }
    return true
}

settlement_access_path_relax_to_network :: proc(
    plan: ^Settlement_Plan,
    city_plan: ^architecture.City_Plan,
    path: Settlement_Route,
) -> (
    Settlement_Route,
    bool,
) {
    if plan == nil || city_plan == nil || path.count < 2 do return path, false
    road_connected := make([]bool, city_plan.alley_count, context.temp_allocator)
    settlement_access_mark_road_connected_segments(plan, city_plan, road_connected)
    for path_index in 0 ..< path.count - 1 {
        path_start, path_end := path.points[path_index], path.points[path_index + 1]
        best_point: [2]f32
        best_along := f32(1e30)
        found_contact := false
        for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
            if !road_connected[alley_index] do continue
            alley_start := [2]f32{alley.start_x, alley.start_z}
            alley_end := [2]f32{alley.end_x, alley.end_z}
            point, path_along, _, found := settlement_route_segment_intersection(
                path_start,
                path_end,
                alley_start,
                alley_end,
            )
            if !found || path_along <= .0001 || path_along > 1.0001 || path_along >= best_along do continue
            best_point, best_along, found_contact = point, path_along, true
        }
        if !found_contact do continue
        result := path
        result.points[path_index + 1] = best_point
        result.count = path_index + 2
        return result, true
    }
    return path, false
}

settlement_access_path_prepend :: proc(path: Settlement_Route, point: [2]f32) -> Settlement_Route {
    if path.count <= 0 || settlement_alley_point_near(path.points[0], point) do return path
    result := path
    if result.count >= len(result.points) do return Settlement_Route{}
    for index := result.count; index > 0; index -= 1 {
        result.points[index] = result.points[index - 1]
    }
    result.points[0] = point
    result.count += 1
    return result
}

settlement_access_path_append :: proc(path: Settlement_Route, point: [2]f32) -> Settlement_Route {
    if path.count <= 0 || settlement_alley_point_near(path.points[path.count - 1], point) do return path
    result := path
    if result.count >= len(result.points) do return Settlement_Route{}
    result.points[result.count] = point
    result.count += 1
    return result
}

settlement_access_path_clear :: proc(
    city_plan: ^architecture.City_Plan,
    path: Settlement_Route,
    clearance: f32,
    source_structure: int,
) -> bool {
    if city_plan == nil || path.count < 2 do return false
    for index in 0 ..< path.count - 1 {
        if !settlement_access_segment_clear(
            city_plan,
            path.points[index],
            path.points[index + 1],
            clearance,
            source_structure,
        ) {
            return false
        }
    }
    return true
}

settlement_access_split_alley :: proc(city_plan: ^architecture.City_Plan, alley_index: int, point: [2]f32) -> bool {
    if city_plan == nil || alley_index < 0 || alley_index >= city_plan.alley_count do return false
    alley := &city_plan.alleys[alley_index]
    start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
    if settlement_alley_point_near(point, start) || settlement_alley_point_near(point, finish) do return false
    tail := alley^
    alley.end_x, alley.end_z = point[0], point[1]
    alley.end_terminal = .None
    tail.start_x, tail.start_z = point[0], point[1]
    tail.start_terminal = .None
    append(&city_plan.alleys, tail)
    city_plan.alley_count += 1
    return true
}

// Convert geometric path intersections into explicit graph nodes. This makes
// T-joins and crossings visible to degree limits, route compaction, and later
// navigation instead of leaving visually connected pavement topologically
// disconnected.
settlement_access_split_intersections :: proc(city_plan: ^architecture.City_Plan) {
    if city_plan == nil do return
    for _ in 0 ..< SETTLEMENT_PLANNED_ROUTE_CAPACITY * SETTLEMENT_ROUTE_CAPACITY {
        changed := false
        for first_index in 0 ..< city_plan.alley_count {
            first := city_plan.alleys[first_index]
            first_start := [2]f32{first.start_x, first.start_z}
            first_end := [2]f32{first.end_x, first.end_z}
            for second_index in first_index + 1 ..< city_plan.alley_count {
                second := city_plan.alleys[second_index]
                second_start := [2]f32{second.start_x, second.start_z}
                second_end := [2]f32{second.end_x, second.end_z}
                first_endpoints := [2][2]f32{first_start, first_end}
                for first_endpoint in first_endpoints {
                    if settlement_alley_point_near(first_endpoint, second_start) ||
                       settlement_alley_point_near(first_endpoint, second_end) {
                        continue
                    }
                    if settlement_point_segment_distance_squared(first_endpoint, second_start, second_end) <= .0025 {
                        changed = settlement_access_split_alley(city_plan, second_index, first_endpoint)
                        break
                    }
                }
                if changed do break
                second_endpoints := [2][2]f32{second_start, second_end}
                for second_endpoint in second_endpoints {
                    if settlement_alley_point_near(second_endpoint, first_start) ||
                       settlement_alley_point_near(second_endpoint, first_end) {
                        continue
                    }
                    if settlement_point_segment_distance_squared(second_endpoint, first_start, first_end) <= .0025 {
                        changed = settlement_access_split_alley(city_plan, first_index, second_endpoint)
                        break
                    }
                }
                if changed do break
                point, _, _, found := settlement_route_segment_intersection(
                    first_start,
                    first_end,
                    second_start,
                    second_end,
                )
                if !found do continue
                first_interior :=
                    !settlement_alley_point_near(point, first_start) && !settlement_alley_point_near(point, first_end)
                second_interior :=
                    !settlement_alley_point_near(point, second_start) &&
                    !settlement_alley_point_near(point, second_end)
                if first_interior {
                    changed = settlement_access_split_alley(city_plan, first_index, point)
                } else if second_interior {
                    changed = settlement_access_split_alley(city_plan, second_index, point)
                }
                if changed do break
            }
            if changed do break
        }
        if !changed do break
    }
}

settlement_access_deduplicate_segments :: proc(city_plan: ^architecture.City_Plan) {
    if city_plan == nil do return
    first_index := 0
    for first_index < city_plan.alley_count {
        first := &city_plan.alleys[first_index]
        first_start := [2]f32{first.start_x, first.start_z}
        first_end := [2]f32{first.end_x, first.end_z}
        second_index := first_index + 1
        for second_index < city_plan.alley_count {
            second := city_plan.alleys[second_index]
            second_start := [2]f32{second.start_x, second.start_z}
            second_end := [2]f32{second.end_x, second.end_z}
            same_direction :=
                settlement_alley_point_near(first_start, second_start) &&
                settlement_alley_point_near(first_end, second_end)
            reverse_direction :=
                settlement_alley_point_near(first_start, second_end) &&
                settlement_alley_point_near(first_end, second_start)
            if !same_direction && !reverse_direction {
                second_index += 1
                continue
            }
            first.half_width = max(first.half_width, second.half_width)
            if same_direction {
                if first.start_terminal == .None do first.start_terminal = second.start_terminal
                if first.end_terminal == .None do first.end_terminal = second.end_terminal
            } else {
                if first.start_terminal == .None do first.start_terminal = second.end_terminal
                if first.end_terminal == .None do first.end_terminal = second.start_terminal
            }
            city_plan.alley_count -= 1
            city_plan.alleys[second_index] = city_plan.alleys[city_plan.alley_count]
            resize(&city_plan.alleys, city_plan.alley_count)
        }
        first_index += 1
    }
}

settlement_access_snap_near_endpoints :: proc(city_plan: ^architecture.City_Plan) {
    if city_plan == nil do return
    for first_index in 0 ..< city_plan.alley_count {
        for first_endpoint_index in 0 ..< 2 {
            first := city_plan.alleys[first_index]
            first_point := [2]f32{first.start_x, first.start_z}
            if first_endpoint_index == 1 do first_point = {first.end_x, first.end_z}
            for second_index in first_index ..< city_plan.alley_count {
                for second_endpoint_index in 0 ..< 2 {
                    if first_index == second_index && first_endpoint_index >= second_endpoint_index do continue
                    second := city_plan.alleys[second_index]
                    second_point := [2]f32{second.start_x, second.start_z}
                    if second_endpoint_index == 1 do second_point = {second.end_x, second.end_z}
                    if !settlement_alley_point_near(first_point, second_point) do continue
                    if second_endpoint_index == 0 {
                        city_plan.alleys[second_index].start_x = first_point[0]
                        city_plan.alleys[second_index].start_z = first_point[1]
                    } else {
                        city_plan.alleys[second_index].end_x = first_point[0]
                        city_plan.alleys[second_index].end_z = first_point[1]
                    }
                }
            }
        }
    }
}

// Independently generated routes can occasionally leave the same junction on
// virtually identical bearings and arrive at graph nodes only a few
// centimetres apart. Merge those anonymous nodes before deduplication so the
// finished network has one shared trunk instead of a visually doubled path.
