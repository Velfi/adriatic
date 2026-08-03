package main

import planar_geometry "../packages/planar_geometry"

import road_planner "../packages/road_planner"
import roads "../packages/roads"
import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"

SETTLEMENT_ROUTE_GRID :: 25
SETTLEMENT_ROUTE_CAPACITY :: 12
SETTLEMENT_ROAD_NETWORK_POI_CAPACITY :: 32
SETTLEMENT_ROAD_GATEWAY_CAPACITY :: 3
// A runway is exceptionally attractive to the terrain router because it is
// broad and level. Make an at-grade crossing a last resort while keeping the
// authored connector from a runway threshold usable.
SETTLEMENT_ROUTE_RUNWAY_CROSSING_COST :: f32(250)
SETTLEMENT_ROUTE_RUNWAY_SAFETY_MARGIN :: f32(6)

Settlement_Route :: struct {
    points: [SETTLEMENT_ROUTE_CAPACITY][2]f32,
    count:  int,
}

Settlement_Route_Construction_Cost :: struct {
    cut:         f32,
    fill:        f32,
    cross_slope: f32,
}

// Estimate the graded footprint rather than looking only at centerline slope.
// The proposed roadbed is the straight vertical profile between the endpoints;
// five transverse samples cover pavement, shoulders, and the beginnings of the
// cut/fill slopes. This stays deliberately cheap because it runs in A*'s inner
// loop, while still making a contour-following bench materially cheaper than a
// road driven across a steep side slope.
settlement_route_construction_cost :: proc(
    project: ^terrain.Project,
    a, b: [2]f32,
    half_width: f32,
) -> Settlement_Route_Construction_Cost {
    result: Settlement_Route_Construction_Cost
    delta := b - a
    length := linalg.length(delta)
    if project == nil || length <= .01 do return result
    tangent := delta / length
    normal := [2]f32{-tangent[1], tangent[0]}
    a_height := terrain.sample_surface_height(project, 0, a[0], a[1])
    b_height := terrain.sample_surface_height(project, 0, b[0], b[1])
    sample_spacing := half_width * .5
    // One representative section keeps the A* inner loop cheap. Its area is
    // extruded over the primitive length; the endpoint samples above define
    // the road's vertical profile.
    center := (a + b) * .5
    road_height := (a_height + b_height) * .5
    left_height, right_height := f32(0), f32(0)
    for across_index in -2 ..= 2 {
        offset := f32(across_index) * sample_spacing
        point := center + normal * offset
        ground := terrain.sample_surface_height(project, 0, point[0], point[1])
        difference := road_height - ground
        area := sample_spacing * length
        if difference > 0 {
            result.fill += difference * area
        } else {
            result.cut += -difference * area
        }
        if across_index == -2 do left_height = ground
        if across_index == 2 do right_height = ground
    }
    result.cross_slope = math.abs(right_height - left_height) / max(half_width * 2, f32(.01))
    return result
}

Settlement_Road_Network_PoI :: struct {
    position: [2]f32,
    required: bool,
}

settlement_route_edge_is_runway :: proc(edge: roads.Edge) -> bool {
    runway_half_width := f32(terrain.WORLD_SIZE_METERS * .5) * terrain.DEFAULT_RUNWAY_HALF_WIDTH
    return edge.pavement == .Asphalt && math.abs(edge.half_width - runway_half_width) <= .001
}

// Turn a regional road passing through the settlement fringe into explicit
// town entrances before local routes are planned.  The town network can then
// grow from shared graph nodes instead of discovering accidental crossings
// after both networks have already chosen their geometry.
settlement_plan_road_gateways :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    gateways: ^[SETTLEMENT_ROAD_GATEWAY_CAPACITY][2]f32,
) -> int {
    if plan == nil || project == nil || gateways == nil do return 0
    graph := &project.road_graph
    if graph.edge_count <= 0 do return 0

    desired_count := 2
    switch plan.request.scale {
    case .Village:
        desired_count = 1
    case .City:
        desired_count = 3
    case .Town:
        desired_count = 2
    }
    desired_count = min(desired_count, SETTLEMENT_ROAD_GATEWAY_CAPACITY)
    target_radius := max(plan.request.radius * .72, f32(18))
    maximum_radius := max(plan.request.radius * 1.18, target_radius + 12)
    minimum_spacing := max(plan.request.radius * .45, f32(18))
    SAMPLES :: 24

    gateway_count := 0
    for gateway_count < desired_count {
        best_edge := -1
        best_amount, best_score := f32(0), f32(1e30)
        for edge, edge_index in graph.edges[:graph.edge_count] {
            // Airport access is authored from a threshold. A runway is not a
            // regional street and must never become an automatic town gateway.
            if settlement_route_edge_is_runway(edge) do continue
            for sample in 2 ..< SAMPLES - 1 {
                amount := f32(sample) / f32(SAMPLES)
                point := roads.edge_point(graph, edge, amount)
                flat := [2]f32{point.x, point.z}
                distance_from_center := linalg.length(flat - plan.request.center)
                if distance_from_center > maximum_radius do continue

                separated := true
                for existing in gateways[:gateway_count] {
                    if linalg.length(flat - existing) < minimum_spacing {
                        separated = false
                        break
                    }
                }
                if !separated do continue

                // Prefer a surveyed entrance near the outer fabric ring.  A
                // small endpoint clearance discourages immediately adjacent
                // regional junctions without excluding short road segments.
                score := math.abs(distance_from_center - target_radius)
                from := graph.nodes[edge.from].position
                to := graph.nodes[edge.to].position
                endpoint_distance := min(
                    linalg.length(flat - [2]f32{from.x, from.z}),
                    linalg.length(flat - [2]f32{to.x, to.z}),
                )
                if endpoint_distance < 12 do score += (12 - endpoint_distance) * 4
                if score < best_score {
                    best_edge, best_amount, best_score = edge_index, amount, score
                }
            }
        }
        if best_edge < 0 do break
        node := roads.split_edge(graph, best_edge, best_amount, 4)
        if node < 0 do break
        position := graph.nodes[node].position
        gateways[gateway_count] = {position.x, position.z}
        gateway_count += 1
    }
    return gateway_count
}

Settlement_Route_Topology :: struct {
    nodes:      [roads.MAX_NODES][2]f32,
    node_count: int,
    edges:      [roads.MAX_EDGES][2]int,
    edge_count: int,
}

settlement_route_point_near :: proc(a, b: [2]f32, epsilon: f32 = .05) -> bool {
    delta := a - b
    return linalg.dot(delta, delta) <= epsilon * epsilon
}

settlement_route_segment_intersection :: proc(
    a, b, c, d: [2]f32,
) -> (
    point: [2]f32,
    along_ab, along_cd: f32,
    found: bool,
) {
    intersection := planar_geometry.segment_intersection(a, b, c, d, .00001)
    if !intersection.found do return
    point = intersection.point
    along_ab, along_cd = intersection.along_ab, intersection.along_cd
    epsilon := f32(.0001)
    if along_ab < -epsilon || along_ab > 1 + epsilon || along_cd < -epsilon || along_cd > 1 + epsilon {
        return
    }
    found = true
    return
}

settlement_route_segment_overlaps_box :: proc(a, b, box_start, box_finish: [2]f32, half_width: f32) -> bool {
    box_delta := box_finish - box_start
    box_length := linalg.length(box_delta)
    if box_length <= .01 do return false
    tangent := box_delta / box_length
    normal := [2]f32{-tangent[1], tangent[0]}
    local_a := [2]f32{linalg.dot(a - box_start, tangent), linalg.dot(a - box_start, normal)}
    local_b := [2]f32{linalg.dot(b - box_start, tangent), linalg.dot(b - box_start, normal)}
    local_delta := local_b - local_a
    enter, exit := f32(0), f32(1)
    bounds := [2][2]f32{{0, box_length}, {-half_width, half_width}}
    for axis in 0 ..< 2 {
        if math.abs(local_delta[axis]) <= .00001 {
            if local_a[axis] < bounds[axis][0] || local_a[axis] > bounds[axis][1] do return false
            continue
        }
        first := (bounds[axis][0] - local_a[axis]) / local_delta[axis]
        second := (bounds[axis][1] - local_a[axis]) / local_delta[axis]
        if first > second do first, second = second, first
        enter = max(enter, first)
        exit = min(exit, second)
        if enter > exit do return false
    }
    return exit >= 0 && enter <= 1 && exit - enter > .00001
}

settlement_route_segment_crosses_runway :: proc(project: ^terrain.Project, a, b: [2]f32) -> bool {
    if project == nil do return false
    graph := &project.road_graph
    CURVE_SEGMENTS :: 16
    for edge in graph.edges[:graph.edge_count] {
        if !settlement_route_edge_is_runway(edge) do continue
        previous := roads.edge_point(graph, edge, 0)
        for segment in 0 ..< CURVE_SEGMENTS {
            current := roads.edge_point(graph, edge, f32(segment + 1) / f32(CURVE_SEGMENTS))
            if settlement_route_segment_overlaps_box(
                a,
                b,
                {previous.x, previous.z},
                {current.x, current.z},
                edge.half_width + SETTLEMENT_ROUTE_RUNWAY_SAFETY_MARGIN,
            ) {
                return true
            }
            previous = current
        }
    }
    return false
}

settlement_route_insert_point :: proc(route: ^Settlement_Route, after_index: int, point: [2]f32) -> bool {
    if route == nil || route.count >= len(route.points) || after_index < 0 || after_index >= route.count - 1 {
        return false
    }
    if settlement_route_point_near(route.points[after_index], point) ||
       settlement_route_point_near(route.points[after_index + 1], point) {
        return false
    }
    for index := route.count; index > after_index + 1; index -= 1 {
        route.points[index] = route.points[index - 1]
    }
    route.points[after_index + 1] = point
    route.count += 1
    return true
}

settlement_plan_split_route_intersections :: proc(plan: ^Settlement_Plan) {
    if plan == nil do return
    // Restart after each insertion because segment indices change. The route
    // and point capacities make this deterministic bounded work.
    for _ in 0 ..< SETTLEMENT_PLANNED_ROUTE_CAPACITY * SETTLEMENT_ROUTE_CAPACITY {
        changed := false
        for first_index in 0 ..< plan.route_count {
            first := &plan.routes[first_index].geometry
            if first.count < 2 do continue
            for second_index in first_index + 1 ..< plan.route_count {
                second := &plan.routes[second_index].geometry
                if second.count < 2 do continue
                for first_segment in 0 ..< first.count - 1 {
                    for second_segment in 0 ..< second.count - 1 {
                        point, first_along, second_along, found := settlement_route_segment_intersection(
                            first.points[first_segment],
                            first.points[first_segment + 1],
                            second.points[second_segment],
                            second.points[second_segment + 1],
                        )
                        if !found do continue
                        first_interior := first_along > .0001 && first_along < .9999
                        second_interior := second_along > .0001 && second_along < .9999
                        if !first_interior && !second_interior do continue
                        inserted := false
                        if first_interior {
                            inserted = settlement_route_insert_point(first, first_segment, point) || inserted
                        }
                        if second_interior {
                            inserted = settlement_route_insert_point(second, second_segment, point) || inserted
                        }
                        if inserted {
                            changed = true
                            break
                        }
                    }
                    if changed do break
                }
                if changed do break
            }
            if changed do break
        }
        if !changed do break
    }
}

settlement_plan_split_project_road_intersections :: proc(plan: ^Settlement_Plan, project: ^terrain.Project) {
    if plan == nil || project == nil do return
    graph := &project.road_graph
    CURVE_SEGMENTS :: 16
    // Restart after each split because both the planned polyline and the road
    // graph change. This turns crossings with runways, airport approaches, and
    // marina connectors into shared nodes before settlement routes commit.
    for _ in 0 ..< SETTLEMENT_PLANNED_ROUTE_CAPACITY * SETTLEMENT_ROUTE_CAPACITY {
        changed := false
        for &planned in plan.routes[:plan.route_count] {
            if !planned.drivable || planned.geometry.count < 2 do continue
            route := &planned.geometry
            for route_segment in 0 ..< route.count - 1 {
                for edge_index in 0 ..< graph.edge_count {
                    edge := graph.edges[edge_index]
                    previous := roads.edge_point(graph, edge, 0)
                    for curve_segment in 0 ..< CURVE_SEGMENTS {
                        next_amount := f32(curve_segment + 1) / f32(CURVE_SEGMENTS)
                        current := roads.edge_point(graph, edge, next_amount)
                        point, route_along, edge_segment_along, found := settlement_route_segment_intersection(
                            route.points[route_segment],
                            route.points[route_segment + 1],
                            {previous.x, previous.z},
                            {current.x, current.z},
                        )
                        if !found {
                            previous = current
                            continue
                        }
                        route_interior := route_along > .0001 && route_along < .9999
                        edge_amount :=
                            (f32(curve_segment) + clamp(edge_segment_along, f32(0), f32(1))) / f32(CURVE_SEGMENTS)
                        edge_interior := edge_amount > .0001 && edge_amount < .9999
                        if !route_interior && !edge_interior {
                            previous = current
                            continue
                        }
                        junction := point
                        if edge_interior {
                            junction_node := roads.split_edge(
                                graph,
                                edge_index,
                                edge_amount,
                                max(planned.width * .7, f32(3)),
                            )
                            if junction_node < 0 do return
                            road_point := graph.nodes[junction_node].position
                            junction = {road_point.x, road_point.z}
                        } else {
                            endpoint := edge_amount <= .5 ? edge.from : edge.to
                            road_point := graph.nodes[endpoint].position
                            junction = {road_point.x, road_point.z}
                        }
                        if route_interior {
                            _ = settlement_route_insert_point(route, route_segment, junction)
                        }
                        changed = true
                        break
                    }
                    if changed do break
                }
                if changed do break
            }
            if changed do break
        }
        if !changed do break
    }
}

settlement_plan_route_topology_size :: proc(plan: ^Settlement_Plan) -> (nodes, edges: int) {
    if plan == nil do return
    unique: [SETTLEMENT_PLANNED_ROUTE_CAPACITY * SETTLEMENT_ROUTE_CAPACITY][2]f32
    for route in plan.routes[:plan.route_count] {
        if !route.drivable || route.geometry.count < 2 do continue
        edges += route.geometry.count - 1
        for point_index in 0 ..< route.geometry.count {
            point := route.geometry.points[point_index]
            found := false
            for existing in unique[:nodes] {
                if settlement_route_point_near(existing, point, 2) {
                    found = true
                    break
                }
            }
            if !found {
                unique[nodes] = point
                nodes += 1
            }
        }
    }
    return
}

settlement_plan_route_topology :: proc(plan: ^Settlement_Plan) -> Settlement_Route_Topology {
    result: Settlement_Route_Topology
    if plan == nil do return result
    for route in plan.routes[:plan.route_count] {
        if !route.drivable || route.geometry.count < 2 do continue
        node_indices: [SETTLEMENT_ROUTE_CAPACITY]int
        for point_index in 0 ..< route.geometry.count {
            point := route.geometry.points[point_index]
            node_index := -1
            for existing, existing_index in result.nodes[:result.node_count] {
                if settlement_route_point_near(existing, point, 2) {
                    node_index = existing_index
                    break
                }
            }
            if node_index < 0 {
                if result.node_count >= len(result.nodes) do return result
                node_index = result.node_count
                result.nodes[result.node_count] = point
                result.node_count += 1
            }
            node_indices[point_index] = node_index
        }
        for point_index in 0 ..< route.geometry.count - 1 {
            from, to := node_indices[point_index], node_indices[point_index + 1]
            if from == to do continue
            duplicate := false
            for edge in result.edges[:result.edge_count] {
                if (edge[0] == from && edge[1] == to) || (edge[0] == to && edge[1] == from) {
                    duplicate = true
                    break
                }
            }
            if duplicate do continue
            if result.edge_count >= len(result.edges) do return result
            result.edges[result.edge_count] = {from, to}
            result.edge_count += 1
        }
    }
    return result
}

settlement_plan_required_routes_connected :: proc(plan: ^Settlement_Plan) -> bool {
    if plan == nil do return false
    topology := settlement_plan_route_topology(plan)
    required_nodes: [roads.MAX_NODES]bool
    required_count, first_required := 0, -1
    for route in plan.routes[:plan.route_count] {
        if !route.required do continue
        for point_index in 0 ..< route.geometry.count {
            point := route.geometry.points[point_index]
            for node, node_index in topology.nodes[:topology.node_count] {
                if !settlement_route_point_near(node, point, 2) do continue
                if !required_nodes[node_index] {
                    required_nodes[node_index] = true
                    required_count += 1
                }
                if first_required < 0 do first_required = node_index
                break
            }
        }
    }
    if required_count <= 1 do return true
    visited: [roads.MAX_NODES]bool
    queue: [roads.MAX_NODES]int
    queue[0] = first_required
    visited[first_required] = true
    queue_start, queue_end := 0, 1
    for queue_start < queue_end {
        current := queue[queue_start]
        queue_start += 1
        for edge in topology.edges[:topology.edge_count] {
            neighbor := -1
            if edge[0] == current {
                neighbor = edge[1]
            } else if edge[1] == current {
                neighbor = edge[0]
            }
            if neighbor < 0 || visited[neighbor] do continue
            visited[neighbor] = true
            queue[queue_end] = neighbor
            queue_end += 1
        }
    }
    for required, node_index in required_nodes {
        if required && !visited[node_index] do return false
    }
    return true
}

settlement_route_grade_limit :: proc(class: Settlement_Route_Class) -> f32 {
    switch class {
    case .Civic_Spine, .Connector:
        return .10
    case .Street:
        return .13
    case .Lane, .Alley:
        return .18
    case .Stair:
        // Purpose-built steps can climb much more sharply than a walkable
        // road; access generation treats slopes above this as excessive.
        return .65
    case .Waterfront:
        return .08
    case .Ridge:
        return .12
    }
    return .13
}

settlement_route_crosses_sea :: proc(
    project: ^terrain.Project,
    route: Settlement_Route,
    clearance: f32 = .45,
) -> bool {
    if project == nil || route.count < 2 do return true
    for segment_index in 0 ..< route.count - 1 {
        a, b := route.points[segment_index], route.points[segment_index + 1]
        delta := b - a
        length := linalg.length(delta)
        samples := max(int(math.ceil(f64(length / 4))), 1)
        for sample_index in 0 ..= samples {
            amount := f32(sample_index) / f32(samples)
            point := a + delta * amount
            land_height, _, land_found := terrain.sample_land(project, 0, point.x, point.y)
            if !land_found || land_height <= project.sea_level + clearance {
                return true
            }
        }
    }
    return false
}

settlement_plan_extract_route_faces :: proc(plan: ^Settlement_Plan) -> int {
    if plan == nil do return 0
    topology := settlement_plan_route_topology(plan)
    if topology.node_count < 3 || topology.edge_count < 3 do return 0
    visited: [roads.MAX_EDGES * 2]bool
    added := 0
    for start_half_edge in 0 ..< topology.edge_count * 2 {
        if visited[start_half_edge] do continue
        face_nodes: [roads.MAX_NODES]int
        face_count := 0
        half_edge := start_half_edge
        closed := false
        for _ in 0 ..< topology.edge_count * 2 + 1 {
            if visited[half_edge] do break
            visited[half_edge] = true
            edge_index := half_edge / 2
            reverse := half_edge & 1 == 1
            from := reverse ? topology.edges[edge_index][1] : topology.edges[edge_index][0]
            to := reverse ? topology.edges[edge_index][0] : topology.edges[edge_index][1]
            if face_count >= len(face_nodes) do break
            face_nodes[face_count] = from
            face_count += 1

            incoming := topology.nodes[to] - topology.nodes[from]
            incoming_angle := f32(math.atan2(f64(incoming[1]), f64(incoming[0])))
            next_half_edge, best_turn := -1, f32(math.PI * 2 + .01)
            for candidate_edge in 0 ..< topology.edge_count {
                edge := topology.edges[candidate_edge]
                candidate_half_edge, candidate_to := -1, -1
                if edge[0] == to {
                    candidate_half_edge, candidate_to = candidate_edge * 2, edge[1]
                } else if edge[1] == to {
                    candidate_half_edge, candidate_to = candidate_edge * 2 + 1, edge[0]
                } else {
                    continue
                }
                if candidate_to == from do continue
                outgoing := topology.nodes[candidate_to] - topology.nodes[to]
                outgoing_angle := f32(math.atan2(f64(outgoing[1]), f64(outgoing[0])))
                turn := outgoing_angle - incoming_angle
                for turn <= 0 do turn += f32(math.PI * 2)
                if turn < best_turn {
                    next_half_edge, best_turn = candidate_half_edge, turn
                }
            }
            if next_half_edge < 0 do break
            half_edge = next_half_edge
            if half_edge == start_half_edge {
                closed = true
                break
            }
        }
        if !closed || face_count < 3 || face_count > len(Settlement_Block{}.corners) do continue
        signed_double_area, perimeter := f32(0), f32(0)
        minimum_x, minimum_z := f32(1e30), f32(1e30)
        maximum_x, maximum_z := f32(-1e30), f32(-1e30)
        center := [2]f32{}
        for index in 0 ..< face_count {
            a := topology.nodes[face_nodes[index]]
            b := topology.nodes[face_nodes[(index + 1) % face_count]]
            signed_double_area += a[0] * b[1] - b[0] * a[1]
            perimeter += linalg.length(b - a)
            minimum_x, minimum_z = min(minimum_x, a[0]), min(minimum_z, a[1])
            maximum_x, maximum_z = max(maximum_x, a[0]), max(maximum_z, a[1])
            center += a
        }
        area := signed_double_area * .5
        if area < 25 || area > 20000 || plan.block_count >= len(plan.blocks) do continue
        center /= f32(face_count)
        width, depth := maximum_x - minimum_x, maximum_z - minimum_z
        if width <= .01 || depth <= .01 do continue
        block := Settlement_Block {
            center       = center,
            corner_count = face_count,
            short_side   = min(width, depth),
            long_side    = max(width, depth),
            area         = area,
            irregularity = clamp(perimeter / max(2 * (width + depth), f32(.01)) - 1, 0, 1),
            tissue       = settlement_nearest_tissue(plan, center[0], center[1]),
        }
        for index in 0 ..< face_count {
            block.corners[index] = topology.nodes[face_nodes[index]]
        }
        plan.blocks[plan.block_count] = block
        plan.block_count += 1
        added += 1
    }
    return added
}


settlement_route_removal_priority :: proc(route: Settlement_Planned_Route) -> int {
    switch route.class {
    case .Alley, .Lane, .Stair:
        return 0
    case .Street:
        return 1
    case .Connector, .Ridge:
        return 2
    case .Waterfront:
        return 3
    case .Civic_Spine:
        return 4
    }
    return 1
}

settlement_plan_simplify_route_capacity :: proc(plan: ^Settlement_Plan, node_capacity, edge_capacity: int) -> bool {
    if plan == nil do return false
    for {
        nodes, edges := settlement_plan_route_topology_size(plan)
        if nodes <= node_capacity && edges <= edge_capacity do return true
        remove_index, best_priority := -1, int(1e9)
        for route, index in plan.routes[:plan.route_count] {
            if route.required do continue
            priority := settlement_route_removal_priority(route)
            if priority < best_priority || (priority == best_priority && index > remove_index) {
                remove_index, best_priority = index, priority
            }
        }
        if remove_index < 0 do return false
        for index in remove_index ..< plan.route_count - 1 {
            plan.routes[index] = plan.routes[index + 1]
        }
        plan.route_count -= 1
    }
}

// Route every authored settlement connection through the shared planner. The
// settlement layer owns product policy (road class, runway exclusion, and the
// compact route representation); search and path reconstruction belong to
// road_planner so editor roads and generated roads cannot drift apart.
settlement_route_find :: proc(
    project: ^terrain.Project,
    start_x, start_z, finish_x, finish_z: f32,
    route_class: Settlement_Route_Class = .Street,
) -> Settlement_Route {
    result: Settlement_Route
    if project == nil do return result

    direct := [2]f32{finish_x - start_x, finish_z - start_z}
    direct_length := linalg.length(direct)
    if direct_length <= .01 do return result

    config := road_planner.get_generation_config()
    grade_limit := settlement_route_grade_limit(route_class)
    config.maximum_grade = grade_limit
    config.heuristic_weight = 1
    config.length_cost = 1
    config.water_cost = 1e8
    config.turn_cost = 2
    config.switchback_cost = 24
    switch route_class {
    case .Civic_Spine, .Connector:
        config.grade_cost = 42
        config.steep_grade_cost = 220
        // Major settlement routes may pay for a short engineered waterway
        // crossing when the land detour is materially worse. The shared road
        // renderer turns those crossing runs into regional bridge plans.
        config.water_cost = 140
    case .Street:
        config.grade_cost = 34
        config.steep_grade_cost = 180
    case .Lane, .Alley:
        config.grade_cost = 20
        config.steep_grade_cost = 100
    case .Stair:
        config.grade_cost = 4
        config.steep_grade_cost = 20
    case .Waterfront:
        config.grade_cost = 56
        config.steep_grade_cost = 260
        config.water_cost = 240
    case .Ridge:
        config.grade_cost = 30
        config.steep_grade_cost = 150
    }

    start_height := terrain.sample_surface_height(project, 0, start_x, start_z)
    finish_height := terrain.sample_surface_height(project, 0, finish_x, finish_z)
    required_length := math.abs(finish_height - start_height) / max(grade_limit, f32(.01))
    lateral_run := f32(0)
    if required_length > direct_length {
        lateral_run =
            f32(math.sqrt(f64(max(required_length * required_length - direct_length * direct_length, f32(0))))) * .5
    }
    minimum_cell := direct_length <= 12 ? f32(2) : f32(10)
    corridor_span := max(math.abs(direct[0]), math.abs(direct[1])) + lateral_run * 2
    config.cell_size = max(
        min(config.cell_size, max(corridor_span / f32(SETTLEMENT_ROUTE_GRID - 5), minimum_cell)),
        max(corridor_span / f32(road_planner.MAX_GRID_WIDTH - 5), minimum_cell),
    )
    padding := max(config.cell_size * 2, lateral_run + config.cell_size)
    origin_x := min(start_x, finish_x) - padding
    origin_z := min(start_z, finish_z) - padding
    width := clamp(
        int(math.ceil(f64((max(start_x, finish_x) + padding - origin_x) / config.cell_size))) + 1,
        3,
        road_planner.MAX_GRID_WIDTH,
    )
    height := clamp(
        int(math.ceil(f64((max(start_z, finish_z) + padding - origin_z) / config.cell_size))) + 1,
        3,
        road_planner.MAX_GRID_HEIGHT,
    )
    heights := make([]f32, width * height)
    defer delete(heights)
    blocked := make([]bool, width * height)
    defer delete(blocked)
    for z in 0 ..< height {
        for x in 0 ..< width {
            world_x := origin_x + f32(x) * config.cell_size
            world_z := origin_z + f32(z) * config.cell_size
            heights[z * width + x] = terrain.sample_surface_height(project, 0, world_x, world_z)
            half_cell := config.cell_size * .5
            blocked[z * width + x] = settlement_route_segment_crosses_runway(
                project,
                {world_x - half_cell, world_z - half_cell},
                {world_x + half_cell, world_z + half_cell},
            )
        }
    }

    workspace := new(road_planner.Workspace)
    defer free(workspace)
    planned := road_planner.plan(
        workspace,
        {
            origin_x = origin_x,
            origin_z = origin_z,
            width = width,
            height = height,
            sea_level = project.sea_level + .45,
            heights = heights,
            blocked = blocked,
        },
        config,
        {start_x, start_z},
        {finish_x, finish_z},
    )
    if !planned.found || planned.point_count < 2 do return result

    // Planner endpoints live on grid cells. Preserve the authored contacts,
    // then greedily retain the farthest legal waypoint that fits the bounded
    // settlement route representation.
    source: [road_planner.MAX_PATH_POINTS][2]f32
    source_count := planned.point_count
    for point, index in planned.points[:planned.point_count] do source[index] = {point.x, point.z}
    source[0] = {start_x, start_z}
    source[source_count - 1] = {finish_x, finish_z}
    result.points[0] = source[0]
    result.count = 1
    cursor := 0
    for cursor < source_count - 1 && result.count < len(result.points) {
        chosen := -1
        for candidate := source_count - 1; candidate > cursor; candidate -= 1 {
            a, b := source[cursor], source[candidate]
            distance := linalg.length(b - a)
            if distance <= .01 do continue
            rise := math.abs(
                terrain.sample_surface_height(project, 0, b[0], b[1]) - terrain.sample_surface_height(project, 0, a[0], a[1]),
            )
            chord: Settlement_Route
            chord.points[0], chord.points[1], chord.count = a, b, 2
            if rise / distance <= grade_limit + .001 &&
               !settlement_route_crosses_sea(project, chord) &&
               !settlement_route_segment_crosses_runway(project, a, b) {
                chosen = candidate
                break
            }
        }
        if chosen < 0 do return Settlement_Route{}
        result.points[result.count] = source[chosen]
        result.count += 1
        cursor = chosen
    }
    if cursor != source_count - 1 do return Settlement_Route{}
    return result
}

settlement_route_length_and_grade :: proc(
    project: ^terrain.Project,
    route: Settlement_Route,
) -> (
    length, average_grade, maximum_grade: f32,
) {
    if project == nil || route.count < 2 do return
    weighted_grade := f32(0)
    for index in 0 ..< route.count - 1 {
        a, b := route.points[index], route.points[index + 1]
        segment_length := linalg.length(b - a)
        if segment_length <= .01 do continue
        rise := math.abs(terrain.sample_surface_height(project, 0, b[0], b[1]) - terrain.sample_surface_height(project, 0, a[0], a[1]))
        grade := rise / segment_length
        length += segment_length
        weighted_grade += grade * segment_length
        maximum_grade = max(maximum_grade, grade)
    }
    if length > .01 do average_grade = weighted_grade / length
    return
}

// Grow a new branch from its unserved PoI toward the connected network, but
// stop as soon as it reaches any road already in the plan.  Without this,
// point-to-point tree edges sail through a civic spine or older street on the
// way to an abstract parent PoI, producing overlapping spokes and dense
// multi-way knots instead of ordinary T-junctions.
settlement_route_truncate_at_plan_contact :: proc(
    plan: ^Settlement_Plan,
    route: Settlement_Route,
) -> Settlement_Route {
    if plan == nil || route.count < 2 do return route
    best_segment := -1
    best_point: [2]f32
    best_distance := f32(1e30)
    distance_before := f32(0)
    for segment_index in 0 ..< route.count - 1 {
        a, b := route.points[segment_index], route.points[segment_index + 1]
        segment_length := linalg.length(b - a)
        for existing_route in plan.routes[:plan.route_count] {
            existing := existing_route.geometry
            for existing_index in 0 ..< existing.count - 1 {
                point, along, _, intersects := settlement_route_segment_intersection(
                    a,
                    b,
                    existing.points[existing_index],
                    existing.points[existing_index + 1],
                )
                if !intersects do continue
                distance := distance_before + segment_length * clamp(along, f32(0), f32(1))
                // Ignore contact at the new branch's origin.  It may already
                // be a district node shared by another route.
                if distance <= .5 || distance >= best_distance do continue
                best_segment, best_point, best_distance = segment_index, point, distance
            }
        }
        distance_before += segment_length
    }
    if best_segment < 0 do return route

    result: Settlement_Route
    for index in 0 ..= best_segment {
        result.points[result.count] = route.points[index]
        result.count += 1
    }
    if result.count < len(result.points) &&
       !settlement_route_point_near(result.points[result.count - 1], best_point, .05) {
        result.points[result.count] = best_point
        result.count += 1
    } else if result.count > 0 {
        result.points[result.count - 1] = best_point
    }
    return result
}

// Connect PoIs with a sparse Prim tree. Candidate edges use the same
// terrain-aware pathfinder as authored settlement routes, so network topology
// is chosen from routes that are actually buildable rather than from straight
// line distance alone. An unreachable PoI remains disconnected instead of
// forcing a submerged or over-grade chord into the landscape.
settlement_town_connector_redundant :: proc(connector_length, road_distance: f32) -> bool {
    return road_distance <= 24 && connector_length >= max(f32(72), road_distance * 3.25)
}

settlement_plan_connect_road_network :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    pois: []Settlement_Road_Network_PoI,
    rng: ^Settlement_Rng,
    route_class: Settlement_Route_Class = .Connector,
) -> int {
    if plan == nil || project == nil || rng == nil || len(pois) == 0 do return 0
    poi_count := min(len(pois), SETTLEMENT_ROAD_NETWORK_POI_CAPACITY)
    connected: [SETTLEMENT_ROAD_NETWORK_POI_CAPACITY]bool
    connected[0] = true
    connected_count := 1

    for connected_count < poi_count {
        best_from, best_to := -1, -1
        best_score := f32(1e30)
        best_route: Settlement_Route
        for from in 0 ..< poi_count {
            if !connected[from] do continue
            for to in 0 ..< poi_count {
                if connected[to] do continue
                // Search from the unserved district toward the tree. This
                // makes first contact with an existing street the natural
                // terminus of the branch.
                route := settlement_route_find(
                    project,
                    pois[to].position[0],
                    pois[to].position[1],
                    pois[from].position[0],
                    pois[from].position[1],
                    route_class,
                )
                route = settlement_route_truncate_at_plan_contact(plan, route)
                if route.count < 2 || settlement_route_crosses_sea(project, route) do continue
                length, average_grade, maximum_grade := settlement_route_length_and_grade(project, route)
                if length <= .01 || maximum_grade > settlement_route_grade_limit(route_class) + .001 do continue
                direct_length := linalg.length(pois[to].position - pois[from].position)
                // Prefer short, gentle links, while charging switchbacks for
                // the extra landscape they consume.
                detour := length / max(direct_length, f32(.01))
                score := length * (1 + average_grade * 12) * max(detour, f32(1))
                if score < best_score {
                    best_from, best_to = from, to
                    best_score = score
                    best_route = route
                }
            }
        }
        // Existing civic streets are already part of the connected town
        // fabric. Give every unserved district a direct candidate to the
        // nearest one, rather than making it chase an abstract PoI through a
        // long parallel contour corridor. The ordinary Prim candidates above
        // remain available when the lateral approach is too steep.
        if plan.request.scale == .Town {
            for to in 0 ..< poi_count {
                if connected[to] do continue
                road_point, _, _, _, _, road_distance, _, road_found := settlement_nearest_route_frame(
                    plan,
                    pois[to].position,
                )
                if !road_found || road_distance <= .5 do continue
                route := settlement_route_find(
                    project,
                    pois[to].position[0],
                    pois[to].position[1],
                    road_point[0],
                    road_point[1],
                    route_class,
                )
                route = settlement_route_truncate_at_plan_contact(plan, route)
                if route.count < 2 || settlement_route_crosses_sea(project, route) do continue
                length, average_grade, maximum_grade := settlement_route_length_and_grade(project, route)
                if length <= .01 || maximum_grade > settlement_route_grade_limit(route_class) + .001 do continue
                detour := length / max(road_distance, f32(.01))
                score := length * (1 + average_grade * 12) * max(detour, f32(1))
                if score < best_score {
                    best_from, best_to = 0, to
                    best_score = score
                    best_route = route
                }
            }
        }
        if best_to < 0 do break
        if plan.request.scale == .Town && route_class == .Connector {
            _, _, _, _, _, road_distance, _, road_found := settlement_nearest_route_frame(plan, pois[best_to].position)
            connector_length := settlement_route_length(best_route)
            if road_found && settlement_town_connector_redundant(connector_length, road_distance) {
                // A compact hillside district this close to an existing
                // street is already served by its pedestrian lanes and
                // stairs. Do not carve a long, nearly parallel switchback
                // merely because a short drivable lateral exceeds grade.
                connected[best_to] = true
                connected_count += 1
                continue
            }
        }
        before := plan.route_count
        settlement_plan_add_route(
            plan,
            project,
            best_route,
            route_class,
            pois[best_from].required || pois[best_to].required,
            true,
            rng,
        )
        if plan.route_count == before && before >= len(plan.routes) do break
        connected[best_to] = true
        connected_count += 1
    }
    return connected_count
}

settlement_route_commit :: proc(
    project: ^terrain.Project,
    route: Settlement_Route,
    width, shoulder: f32,
    pavement: roads.Pavement,
    use_intensity: f32 = 1,
) {
    if project == nil || route.count < 2 do return
    graph := &project.road_graph
    if graph.node_count + route.count > roads.MAX_NODES || graph.edge_count + route.count - 1 > roads.MAX_EDGES {
        return
    }
    nodes: [SETTLEMENT_ROUTE_CAPACITY]int
    for index in 0 ..< route.count {
        point := route.points[index]
        y := terrain.sample_surface_height(project, 0, point[0], point[1])
        nodes[index] = -1
        closest_distance_squared := f32(.25 * .25)
        for existing_index in 0 ..< graph.node_count {
            existing := graph.nodes[existing_index].position
            dx, dz := existing.x - point[0], existing.z - point[1]
            distance_squared := dx * dx + dz * dz
            if distance_squared <= closest_distance_squared {
                nodes[index] = existing_index
                closest_distance_squared = distance_squared
            }
        }
        if nodes[index] < 0 do nodes[index] = roads.add_node(graph, {point[0], y, point[1]}, width * .55)
    }
    for index in 0 ..< route.count - 1 {
        if nodes[index] < 0 || nodes[index + 1] < 0 || nodes[index] == nodes[index + 1] do continue
        a, b := graph.nodes[nodes[index]].position, graph.nodes[nodes[index + 1]].position
        dx, dz := b.x - a.x, b.z - a.z
        segment_length := f32(math.sqrt(f64(dx * dx + dz * dz)))
        outgoing := [2]f32{dx, dz}
        incoming_tangent := outgoing
        outgoing_tangent := outgoing
        if index > 0 {
            previous := route.points[index - 1]
            incoming_tangent = route.points[index + 1] - previous
        }
        if index + 2 < route.count {
            next := route.points[index + 2]
            outgoing_tangent = next - route.points[index]
        }
        incoming_length := linalg.length(incoming_tangent)
        outgoing_length := linalg.length(outgoing_tangent)
        if incoming_length > .001 do incoming_tangent /= incoming_length
        if outgoing_length > .001 do outgoing_tangent /= outgoing_length
        // Catmull-like tangents turn the terrain-selected polyline into one
        // continuous walked line. Keep handles short enough that tight alley
        // corners do not balloon outside their planned corridor.
        handle_length := min(segment_length / 3, f32(4))
        c0 := roads.Vec3{a.x + incoming_tangent[0] * handle_length, 0, a.z + incoming_tangent[1] * handle_length}
        c1 := roads.Vec3{b.x - outgoing_tangent[0] * handle_length, 0, b.z - outgoing_tangent[1] * handle_length}
        c0.y = terrain.sample_surface_height(project, 0, c0.x, c0.z)
        c1.y = terrain.sample_surface_height(project, 0, c1.x, c1.z)
        // Settlement presets express paved width, while the road graph stores
        // half-width from centerline to edge.
        _ = roads.add_edge(
            graph,
            nodes[index],
            nodes[index + 1],
            c0,
            c1,
            width * .5,
            shoulder,
            pavement,
            use_intensity,
        )
    }
}
