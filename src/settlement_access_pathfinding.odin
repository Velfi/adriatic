package main

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"

settlement_access_segment_network_clear :: proc(
    city_plan: ^architecture.City_Plan,
    start, end, terminal: [2]f32,
) -> bool {
    if city_plan == nil do return false
    for alley in city_plan.alleys[:city_plan.alley_count] {
        alley_start := [2]f32{alley.start_x, alley.start_z}
        alley_end := [2]f32{alley.end_x, alley.end_z}
        point, segment_along, alley_along, found := settlement_route_segment_intersection(
            start,
            end,
            alley_start,
            alley_end,
        )
        if !found do continue
        if settlement_alley_point_near(point, terminal) && settlement_alley_point_near(end, terminal) {
            continue
        }
        segment_interior := segment_along > .0001 && segment_along < .9999
        alley_interior := alley_along > .0001 && alley_along < .9999
        if segment_interior || alley_interior do return false
    }
    return true
}

// Measure the constructed grade rather than only comparing endpoints. A
// shortcut across a shoulder or terrace can have equal endpoint elevations
// while still crossing an implausibly steep rise in between.
settlement_access_segment_max_grade :: proc(
    project: ^terrain.Project,
    start, end: [2]f32,
    sample_spacing: f32 = .75,
) -> f32 {
    if project == nil do return 0
    length := linalg.length(end - start)
    if length <= .001 do return 0
    steps := max(1, int(math.ceil(f64(length / max(sample_spacing, f32(.1))))))
    previous := start
    previous_height := terrain.sample_height(project, 0, start[0], start[1])
    maximum_grade: f32
    for step in 1 ..= steps {
        along := f32(step) / f32(steps)
        point := start + (end - start) * along
        height := terrain.sample_height(project, 0, point[0], point[1])
        distance := linalg.length(point - previous)
        maximum_grade = max(maximum_grade, math.abs(height - previous_height) / max(distance, f32(.01)))
        previous, previous_height = point, height
    }
    return maximum_grade
}

settlement_access_path_max_grade :: proc(project: ^terrain.Project, path: Settlement_Route) -> f32 {
    maximum_grade: f32
    if project == nil do return maximum_grade
    for index in 0 ..< path.count - 1 {
        maximum_grade = max(
            maximum_grade,
            settlement_access_segment_max_grade(project, path.points[index], path.points[index + 1]),
        )
    }
    return maximum_grade
}

settlement_access_path_find :: proc(
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan,
    start, goal: [2]f32,
    source_structure: int,
    path_clearance: f32 = .4,
    avoid_network_crossings: bool = true,
    start_direction: [2]f32 = {},
    goal_direction: [2]f32 = {},
    direct_grade_limit: f32 = SETTLEMENT_ACCESS_SEVERE_GRADE,
) -> Settlement_Route {
    result: Settlement_Route
    if project == nil || city_plan == nil do return result
    direct := goal - start
    direct_headings_valid :=
        (linalg.length(start_direction) <= .001 || linalg.dot(direct, start_direction) > 0) &&
        (linalg.length(goal_direction) <= .001 || linalg.dot(direct, goal_direction) > 0)
    direct_grade := settlement_access_segment_max_grade(project, start, goal)
    // A clear, grade-safe straight connection is already the shortest valid
    // route. Reserve the grid search for obstacles, network conflicts, severe
    // grades, or explicit working-route grade limits. This keeps authored
    // lanes and courts as the network backbone instead of repeatedly
    // rediscovering their unobstructed door aprons with A*.
    if direct_headings_valid &&
       direct_grade < direct_grade_limit &&
       settlement_access_segment_clear(city_plan, start, goal, path_clearance, source_structure) &&
       (!avoid_network_crossings || settlement_access_segment_network_clear(city_plan, start, goal, goal)) {
        result.points[0], result.points[1], result.count = start, goal, 2
        return result
    }
    span := [2]f32{math.abs(goal[0] - start[0]), math.abs(goal[1] - start[1])}
    cell := max(max(span[0], span[1]) / f32(SETTLEMENT_ACCESS_GRID - 19), f32(.8))
    padding := cell * 9
    minimum := [2]f32{min(start[0], goal[0]) - padding, min(start[1], goal[1]) - padding}
    maximum := [2]f32{max(start[0], goal[0]) + padding, max(start[1], goal[1]) + padding}
    width := clamp(int(math.ceil(f64((maximum[0] - minimum[0]) / cell))) + 1, 3, SETTLEMENT_ACCESS_GRID)
    height := clamp(int(math.ceil(f64((maximum[1] - minimum[1]) / cell))) + 1, 3, SETTLEMENT_ACCESS_GRID)
    node_count := width * height
    state_count := node_count * SETTLEMENT_ACCESS_HEADINGS
    costs, estimates: [SETTLEMENT_ACCESS_STATE_CAPACITY]f32
    parents: [SETTLEMENT_ACCESS_STATE_CAPACITY]int
    closed: [SETTLEMENT_ACCESS_STATE_CAPACITY]bool
    heap := new(Settlement_Access_Heap, context.temp_allocator)
    for index in 0 ..< state_count {
        costs[index], estimates[index], parents[index] = 1e30, 1e30, -1
        heap.positions[index] = -1
    }
    start_x := clamp(int(math.round(f64((start[0] - minimum[0]) / cell))), 0, width - 1)
    start_z := clamp(int(math.round(f64((start[1] - minimum[1]) / cell))), 0, height - 1)
    goal_x := clamp(int(math.round(f64((goal[0] - minimum[0]) / cell))), 0, width - 1)
    goal_z := clamp(int(math.round(f64((goal[1] - minimum[1]) / cell))), 0, height - 1)
    start_node, goal_node := start_z * width + start_x, goal_z * width + goal_x
    grade_cost_scale :=
        f32(5) * clamp(SETTLEMENT_ACCESS_SEVERE_GRADE / max(direct_grade_limit, f32(.01)), f32(1), f32(2))
    directions := [8][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, 1}, {1, -1}, {-1, -1}}
    for heading in 0 ..< SETTLEMENT_ACCESS_HEADINGS {
        state := start_node * SETTLEMENT_ACCESS_HEADINGS + heading
        costs[state], estimates[state] = 0, 0
        settlement_access_heap_decrease(heap, &estimates, state)
    }
    goal_state := -1
    for _ in 0 ..< state_count {
        current := settlement_access_heap_pop(heap, &estimates)
        if current < 0 do break
        closed[current] = true
        current_node := current / SETTLEMENT_ACCESS_HEADINGS
        current_heading := current % SETTLEMENT_ACCESS_HEADINGS
        if current_node == goal_node {
            goal_state = current
            break
        }
        cx, cz := current_node % width, current_node / width
        current_point := [2]f32{minimum[0] + f32(cx) * cell, minimum[1] + f32(cz) * cell}
        if current_node == start_node do current_point = start
        current_height := terrain.sample_height(project, 0, current_point[0], current_point[1])
        for direction, next_heading in directions {
            nx, nz := cx + direction[0], cz + direction[1]
            if nx < 0 || nz < 0 || nx >= width || nz >= height do continue
            neighbor_node := nz * width + nx
            neighbor := neighbor_node * SETTLEMENT_ACCESS_HEADINGS + next_heading
            if closed[neighbor] do continue
            next_point := [2]f32{minimum[0] + f32(nx) * cell, minimum[1] + f32(nz) * cell}
            if neighbor_node == goal_node do next_point = goal
            step := next_point - current_point
            if current_node == start_node &&
               linalg.length(start_direction) > .001 &&
               linalg.dot(step, start_direction) <= 0 {
                continue
            }
            if neighbor_node == goal_node &&
               linalg.length(goal_direction) > .001 &&
               linalg.dot(step, goal_direction) <= 0 {
                continue
            }
            if !settlement_access_segment_clear(
                   city_plan,
                   current_point,
                   next_point,
                   path_clearance,
                   source_structure,
               ) ||
               (avoid_network_crossings &&
                       !settlement_access_segment_network_clear(city_plan, current_point, next_point, goal)) {
                continue
            }
            next_height := terrain.sample_height(project, 0, next_point[0], next_point[1])
            distance := linalg.length(next_point - current_point)
            grade := math.abs(next_height - current_height) / max(distance, f32(.01))
            // Door access is allowed to become a stepped path on severe
            // grades; terrain cost steers toward gentler alternatives without
            // making an otherwise valid occupied building unreachable.
            turn_cost: f32
            if current_node != start_node {
                incoming_direction := directions[current_heading]
                incoming := [2]f32{f32(incoming_direction[0]), f32(incoming_direction[1])}
                outgoing := next_point - current_point
                incoming_length, outgoing_length := linalg.length(incoming), linalg.length(outgoing)
                if incoming_length > .001 && outgoing_length > .001 {
                    alignment := clamp(
                        linalg.dot(incoming, outgoing) / (incoming_length * outgoing_length),
                        f32(-1),
                        f32(1),
                    )
                    // Mild curvature is cheaper than grid zigzags or
                    // doubling back. The penalty remains secondary to
                    // clearance and terrain grade.
                    turn_cost = distance * (1 - alignment) * .65
                }
            }
            candidate := costs[current] + distance * (1 + grade * grade_cost_scale) + turn_cost
            if candidate >= costs[neighbor] do continue
            costs[neighbor], parents[neighbor] = candidate, current
            heuristic := linalg.length([2]f32{f32(goal_x - nx), f32(goal_z - nz)}) * cell
            estimates[neighbor] = candidate + heuristic
            settlement_access_heap_decrease(heap, &estimates, neighbor)
        }
    }
    if start_node == goal_node {
        result.points[0], result.points[1], result.count = start, goal, 2
        return result
    }
    if goal_state < 0 do return result
    reversed: [SETTLEMENT_ACCESS_GRID * SETTLEMENT_ACCESS_GRID][2]f32
    reversed_count := 0
    cursor := goal_state
    for cursor >= 0 && reversed_count < len(reversed) {
        node := cursor / SETTLEMENT_ACCESS_HEADINGS
        gx, gz := node % width, node / width
        point := [2]f32{minimum[0] + f32(gx) * cell, minimum[1] + f32(gz) * cell}
        if node == goal_node do point = goal
        if node == start_node do point = start
        reversed[reversed_count], reversed_count = point, reversed_count + 1
        if node == start_node do break
        cursor = parents[cursor]
    }
    cursor = reversed_count - 1
    result.points[result.count], result.count = reversed[cursor], result.count + 1
    for cursor > 0 && result.count < len(result.points) {
        next_cursor := cursor - 1
        for candidate in 0 ..< cursor {
            shortcut_start := result.points[result.count - 1]
            shortcut_end := reversed[candidate]
            if !settlement_access_segment_clear(
                city_plan,
                shortcut_start,
                shortcut_end,
                path_clearance,
                source_structure,
            ) {
                continue
            }
            existing_grade: f32
            for grade_index := candidate; grade_index < cursor; grade_index += 1 {
                existing_grade = max(
                    existing_grade,
                    settlement_access_segment_max_grade(project, reversed[grade_index + 1], reversed[grade_index]),
                )
            }
            shortcut_grade := settlement_access_segment_max_grade(project, shortcut_start, shortcut_end)
            // Permit tiny sampling differences, but never simplify a gentle
            // contour route into a materially steeper ramp or stair.
            if shortcut_grade > existing_grade + .01 do continue
            next_cursor = candidate
            break
        }
        result.points[result.count], result.count = reversed[next_cursor], result.count + 1
        cursor = next_cursor
    }
    for _ in 0 ..< 12 {
        for index in 1 ..< result.count - 1 {
            relaxed := result.points[index] * .5 + (result.points[index - 1] + result.points[index + 1]) * .25
            existing_grade := max(
                settlement_access_segment_max_grade(project, result.points[index - 1], result.points[index]),
                settlement_access_segment_max_grade(project, result.points[index], result.points[index + 1]),
            )
            relaxed_grade := max(
                settlement_access_segment_max_grade(project, result.points[index - 1], relaxed),
                settlement_access_segment_max_grade(project, relaxed, result.points[index + 1]),
            )
            if settlement_access_segment_clear(
                   city_plan,
                   result.points[index - 1],
                   relaxed,
                   path_clearance,
                   source_structure,
               ) &&
               settlement_access_segment_clear(
                   city_plan,
                   relaxed,
                   result.points[index + 1],
                   path_clearance,
                   source_structure,
               ) &&
               relaxed_grade <= existing_grade + .01 {
                result.points[index] = relaxed
            }
        }
    }
    if result.count > 2 {
        write := 1
        for read in 1 ..< result.count - 1 {
            if linalg.length(result.points[read] - result.points[write - 1]) < .75 do continue
            result.points[write], write = result.points[read], write + 1
        }
        final_goal := result.points[result.count - 1]
        if write > 1 && linalg.length(final_goal - result.points[write - 1]) < .75 {
            result.points[write - 1] = final_goal
        } else {
            result.points[write], write = final_goal, write + 1
        }
        result.count = write
    }
    return result
}

settlement_structure_approach_point :: proc(
    structure: terrain.Structure,
    approach_from: [2]f32,
    clearance: f32 = .85,
) -> [2]f32 {
    center := [2]f32{structure.center_x, structure.center_z}
    world_direction := approach_from - center
    if linalg.length(world_direction) <= .001 {
        world_direction = {f32(math.cos(f64(structure.rotation))), f32(math.sin(f64(structure.rotation)))}
    } else {
        world_direction = linalg.normalize(world_direction)
    }
    sine, cosine := math.sin(structure.rotation), math.cos(structure.rotation)
    local_direction := [2]f32 {
        world_direction[0] * cosine + world_direction[1] * sine,
        -world_direction[0] * sine + world_direction[1] * cosine,
    }
    half_extents := [2]f32{structure.width * .5 + clearance, structure.depth * .5 + clearance}
    distance := f32(1e30)
    if math.abs(local_direction[0]) > 1e-5 {
        distance = min(distance, half_extents[0] / math.abs(local_direction[0]))
    }
    if math.abs(local_direction[1]) > 1e-5 {
        distance = min(distance, half_extents[1] / math.abs(local_direction[1]))
    }
    local_point := local_direction * distance
    return(
        center +
        [2]f32{local_point[0] * cosine - local_point[1] * sine, local_point[0] * sine + local_point[1] * cosine} \
    )
}

settlement_rotation_face_point :: proc(rotation: f32, center, target: [2]f32) -> f32 {
    front := [2]f32{-f32(math.sin(f64(rotation))), f32(math.cos(f64(rotation)))}
    result := rotation
    if linalg.dot(target - center, front) < 0 do result += math.PI
    return result
}

settlement_stoop_road_clearance :: proc(project: ^terrain.Project, start, finish: [2]f32, half_width: f32) -> f32 {
    if project == nil || project.road_graph.edge_count <= 0 do return f32(1e30)
    result := f32(1e30)
    for sample in 0 ..= 8 {
        amount := f32(sample) / 8
        point := start + (finish - start) * amount
        hit := architecture.city_nearest_road_frontage(&project.road_graph, point[0], point[1])
        if hit.found do result = min(result, hit.distance - hit.clearance - half_width)
    }
    return result
}

settlement_stoop_layout_choice :: proc(
    project: ^terrain.Project,
    structure: terrain.Structure,
    wall, outward, tangent: [2]f32,
    door_width, threshold_y: f32,
    base_choice: int,
) -> int {
    if project == nil || base_choice != 0 do return base_choice

    straight_probe := wall + outward * .72
    straight_ground := terrain.sample_height(project, 0, straight_probe[0], straight_probe[1])
    straight_rise := threshold_y - straight_ground
    if straight_rise <= .30 do return base_choice
    step_count := clamp(int(math.ceil(f64(straight_rise / .20))), 2, 14)
    straight_foot := wall + outward * (.20 + f32(step_count - 1) * .42)
    straight_clearance := settlement_stoop_road_clearance(project, wall, straight_foot, door_width * .5 + .20)
    if straight_clearance >= 0 do return base_choice

    side_extent := door_width * .5 + (.5 + f32(step_count - 1)) * .42
    landing_center := wall + outward * .90
    left_foot := landing_center - tangent * side_extent
    right_foot := landing_center + tangent * side_extent
    landing_half_width := door_width * .5 + .41
    left_clearance := min(
        settlement_stoop_road_clearance(project, wall, landing_center, landing_half_width),
        settlement_stoop_road_clearance(project, landing_center, left_foot, .81),
    )
    right_clearance := min(
        settlement_stoop_road_clearance(project, wall, landing_center, landing_half_width),
        settlement_stoop_road_clearance(project, landing_center, right_foot, .81),
    )
    if math.abs(left_clearance - right_clearance) <= .01 {
        return structure.seed & 1 == 0 ? 1 : 2
    }
    return left_clearance > right_clearance ? 1 : 2
}

settlement_structure_front_door_point :: proc(
    structure: terrain.Structure,
    clearance: f32 = .22,
    project: ^terrain.Project = nil,
) -> [2]f32 {
    sine, cosine := f32(math.sin(f64(structure.rotation))), f32(math.cos(f64(structure.rotation)))
    local_x := [2]f32{cosine, sine}
    local_z := [2]f32{-sine, cosine}
    center := [2]f32{structure.center_x, structure.center_z}
    threshold: [2]f32
    outward, tangent := local_z, local_x
    switch structure.entrance_side {
    case .Front:
        threshold = center + local_z * (structure.depth * .5 + clearance)
    case .Right:
        threshold = center + local_x * (structure.width * .5 + clearance)
        outward, tangent = local_x, -local_z
    case .Rear:
        threshold = center - local_z * (structure.depth * .5 + clearance)
        outward, tangent = -local_z, -local_x
    case .Left:
        threshold = center - local_x * (structure.width * .5 + clearance)
        outward, tangent = -local_x, local_z
    }
    if project == nil do return threshold

    door_width := clamp(
        (structure.entrance_side == .Front || structure.entrance_side == .Rear ? structure.width : structure.depth) *
        .13,
        f32(1.8),
        f32(2.8),
    )
    layout_choice := settlement_stoop_layout_choice(
        project,
        structure,
        threshold - outward * clearance,
        outward,
        tangent,
        door_width,
        structure.base_y + .20,
        int(structure.seed % 3),
    )
    turned := layout_choice != 0
    turn_sign := layout_choice == 1 ? f32(-1) : f32(1)
    probe := threshold + outward * (turned ? f32(.68) : f32(.50))
    if turned do probe += tangent * turn_sign * (door_width * .5 + 2.4)
    ground_y := terrain.sample_height(project, 0, probe[0], probe[1])
    rise := structure.base_y + .20 - ground_y
    if rise <= .30 do return threshold

    step_count := clamp(int(math.ceil(f64(rise / .20))), 2, 14)
    // Meet the ground-level handoff slab beyond the final tread.  Routing to
    // the final tread's center makes the path climb onto the stoop and read as
    // though it terminates at the doorstep.  These offsets mirror
    // world_architecture_door_stoop's foot placement.
    if !turned {
        return threshold + outward * (.38 - clearance + f32(step_count) * .42)
    }
    return(
        threshold +
        outward * (.90 - clearance) +
        tangent * turn_sign * (door_width * .5 + f32(step_count) * .42 + .20) \
    )
}

settlement_structure_entrance_outward :: proc(structure: terrain.Structure) -> [2]f32 {
    edge := settlement_access_structure_edge(structure, int(structure.entrance_side))
    return edge.outward
}

settlement_structure_entrance_approach_outward :: proc(
    structure: terrain.Structure,
    project: ^terrain.Project,
) -> [2]f32 {
    outward := settlement_structure_entrance_outward(structure)
    if project == nil do return outward
    threshold := settlement_structure_front_door_point(structure)
    handoff := settlement_structure_front_door_point(structure, .22, project)
    tangent := [2]f32{outward[1], -outward[0]}
    tangent_offset := linalg.dot(handoff - threshold, tangent)
    if math.abs(tangent_offset) <= .1 do return outward
    // A turned flight descends parallel to the facade. Continue that walking
    // line from its foot instead of forcing the path to meet the bottom tread
    // broadside along the facade normal.
    return tangent * (tangent_offset < 0 ? f32(-1) : f32(1))
}

Settlement_Access_Frontage_Edge :: struct {
    midpoint:    [2]f32,
    tangent:     [2]f32,
    outward:     [2]f32,
    half_length: f32,
    edge_index:  int,
}

settlement_access_structure_edge :: proc(
    structure: terrain.Structure,
    edge_index: int,
) -> Settlement_Access_Frontage_Edge {
    center := [2]f32{structure.center_x, structure.center_z}
    sine, cosine := f32(math.sin(f64(structure.rotation))), f32(math.cos(f64(structure.rotation)))
    local_x := [2]f32{cosine, sine}
    local_z := [2]f32{-sine, cosine}
    switch edge_index & 3 {
    case 0:
        return {
            midpoint = center + local_z * (structure.depth * .5),
            tangent = local_x,
            outward = local_z,
            half_length = structure.width * .5,
            edge_index = 0,
        }
    case 1:
        return {
            midpoint = center + local_x * (structure.width * .5),
            tangent = local_z,
            outward = local_x,
            half_length = structure.depth * .5,
            edge_index = 1,
        }
    case 2:
        return {
            midpoint = center - local_z * (structure.depth * .5),
            tangent = -local_x,
            outward = -local_z,
            half_length = structure.width * .5,
            edge_index = 2,
        }
    case 3:
        return {
            midpoint = center - local_x * (structure.width * .5),
            tangent = -local_z,
            outward = -local_x,
            half_length = structure.depth * .5,
            edge_index = 3,
        }
    }
    return {}
}

// Find the actual rotated footprint edge that fronts an infinite lane
// centerline. Buildings on opposite sides naturally contribute opposite
// outward normals; no world-space "left" or "right" assumption is involved.
settlement_access_structure_edge_facing_lane :: proc(
    structure: terrain.Structure,
    lane_origin, lane_tangent: [2]f32,
    minimum_clearance, maximum_setback: f32,
) -> (
    edge: Settlement_Access_Frontage_Edge,
    setback: f32,
    found: bool,
) {
    tangent_length := linalg.length(lane_tangent)
    if tangent_length <= .001 do return
    lane_direction := lane_tangent / tangent_length
    best_score := f32(1e30)
    for edge_index in 0 ..< 4 {
        candidate := settlement_access_structure_edge(structure, edge_index)
        alignment := math.abs(linalg.dot(candidate.tangent, lane_direction))
        if alignment < .94 do continue
        along := linalg.dot(candidate.midpoint - lane_origin, lane_direction)
        closest := lane_origin + lane_direction * along
        toward_lane := closest - candidate.midpoint
        distance := linalg.length(toward_lane)
        if distance < minimum_clearance || distance > maximum_setback do continue
        if distance > .001 && linalg.dot(toward_lane / distance, candidate.outward) < .866 do continue
        score := distance + (1 - alignment) * 12
        if score >= best_score do continue
        edge, setback, found = candidate, distance, true
        best_score = score
    }
    return
}

// Access hierarchy begins at the building program. Resource buildings need a
// cart-scale working approach, while inns and workshops warrant a public
// threshold broader than a private dwelling path. These are preferred widths;
// finished routes widen only when their complete footprint and grade allow it.
settlement_access_preferred_half_width :: proc(scale: Settlement_Scale, purpose: Settlement_Building_Purpose) -> f32 {
    // Town thresholds double as the smallest public passages between attached
    // houses. At 1.6 m they read as a paved Riviera vicolo and allow two
    // pedestrians to pass; constrained gaps may still fall back to the
    // narrower pathfinder clearances below.
    scale_widths := [3]f32{.7, .8, .5}
    base := scale_widths[int(scale)]
    switch purpose {
    case .Barn_Granary, .Mill, .Fishery, .Storehouse:
        return max(base, f32(.9))
    case .Workshop, .Inn_Shop:
        return max(base, f32(.8))
    case .Farmstead:
        return max(base, f32(.7))
    case .Dwelling:
        return base
    }
    return base
}

settlement_access_grade_allows_preferred_width :: proc(
    purpose: Settlement_Building_Purpose,
    maximum_grade: f32,
) -> bool {
    switch purpose {
    case .Barn_Granary, .Mill, .Fishery, .Storehouse:
        // Working carts need a gentler approach than a walkable stair.
        return maximum_grade <= .10
    case .Farmstead:
        // A modest farm lane may tolerate a little more slope, but should
        // still remain below the stair threshold.
        return maximum_grade < SETTLEMENT_ACCESS_STAIR_GRADE
    case .Dwelling, .Workshop, .Inn_Shop:
        return true
    }
    return true
}

settlement_access_direct_grade_limit :: proc(purpose: Settlement_Building_Purpose) -> f32 {
    switch purpose {
    case .Barn_Granary, .Mill, .Fishery, .Storehouse:
        return .10
    case .Farmstead:
        return SETTLEMENT_ACCESS_STAIR_GRADE
    case .Dwelling, .Workshop, .Inn_Shop:
        return SETTLEMENT_ACCESS_SEVERE_GRADE
    }
    return SETTLEMENT_ACCESS_SEVERE_GRADE
}
