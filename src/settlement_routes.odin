package main

import roads "../packages/roads"
import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"

SETTLEMENT_ROUTE_GRID :: 25
SETTLEMENT_ROUTE_CAPACITY :: 12

Settlement_Route :: struct {
    points: [SETTLEMENT_ROUTE_CAPACITY][2]f32,
    count:  int,
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
    ab_x, ab_z := b[0] - a[0], b[1] - a[1]
    cd_x, cd_z := d[0] - c[0], d[1] - c[1]
    denominator := ab_x * cd_z - ab_z * cd_x
    if math.abs(denominator) <= .00001 do return
    ac_x, ac_z := c[0] - a[0], c[1] - a[1]
    along_ab = (ac_x * cd_z - ac_z * cd_x) / denominator
    along_cd = (ac_x * ab_z - ac_z * ab_x) / denominator
    epsilon := f32(.0001)
    if along_ab < -epsilon || along_ab > 1 + epsilon || along_cd < -epsilon || along_cd > 1 + epsilon {
        return
    }
    point = {a[0] + ab_x * along_ab, a[1] + ab_z * along_ab}
    found = true
    return
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
        return .40
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
            if terrain.sample_height(project, 0, point.x, point.y) <= project.sea_level + clearance {
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

settlement_route_find :: proc(
    project: ^terrain.Project,
    start_x, start_z, finish_x, finish_z: f32,
    route_class: Settlement_Route_Class = .Street,
) -> Settlement_Route {
    result: Settlement_Route
    if project == nil do return result

    span_x, span_z := math.abs(finish_x - start_x), math.abs(finish_z - start_z)
    direct_length := linalg.length([2]f32{finish_x - start_x, finish_z - start_z})
    if direct_length <= 12 {
        result.points[0] = {start_x, start_z}
        result.points[1] = {finish_x, finish_z}
        result.count = 2
        return result
    }
    cell := max(max(span_x, span_z) / f32(SETTLEMENT_ROUTE_GRID - 5), f32(10))
    padding := cell * 2
    min_x, min_z := min(start_x, finish_x) - padding, min(start_z, finish_z) - padding
    max_x, max_z := max(start_x, finish_x) + padding, max(start_z, finish_z) + padding
    width := clamp(int(math.ceil(f64((max_x - min_x) / cell))) + 1, 3, SETTLEMENT_ROUTE_GRID)
    height := clamp(int(math.ceil(f64((max_z - min_z) / cell))) + 1, 3, SETTLEMENT_ROUTE_GRID)
    node_count := width * height

    costs: [SETTLEMENT_ROUTE_GRID * SETTLEMENT_ROUTE_GRID]f32
    estimates: [SETTLEMENT_ROUTE_GRID * SETTLEMENT_ROUTE_GRID]f32
    parents: [SETTLEMENT_ROUTE_GRID * SETTLEMENT_ROUTE_GRID]int
    open: [SETTLEMENT_ROUTE_GRID * SETTLEMENT_ROUTE_GRID]bool
    closed: [SETTLEMENT_ROUTE_GRID * SETTLEMENT_ROUTE_GRID]bool
    for index in 0 ..< node_count {
        costs[index] = 1e30
        estimates[index] = 1e30
        parents[index] = -1
    }

    start_gx := clamp(int(math.round(f64((start_x - min_x) / cell))), 0, width - 1)
    start_gz := clamp(int(math.round(f64((start_z - min_z) / cell))), 0, height - 1)
    finish_gx := clamp(int(math.round(f64((finish_x - min_x) / cell))), 0, width - 1)
    finish_gz := clamp(int(math.round(f64((finish_z - min_z) / cell))), 0, height - 1)
    start := start_gz * width + start_gx
    finish := finish_gz * width + finish_gx
    costs[start] = 0
    estimates[start] = 0
    open[start] = true

    directions := [8][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, 1}, {1, -1}, {-1, -1}}
    for _ in 0 ..< node_count {
        current := -1
        best := f32(1e30)
        for index in 0 ..< node_count {
            if open[index] && estimates[index] < best {
                best = estimates[index]
                current = index
            }
        }
        if current < 0 || current == finish do break
        open[current] = false
        closed[current] = true
        cx, cz := current % width, current / width
        current_x, current_z := min_x + f32(cx) * cell, min_z + f32(cz) * cell
        current_height := terrain.sample_height(project, 0, current_x, current_z)

        for direction in directions {
            nx, nz := cx + direction[0], cz + direction[1]
            if nx < 0 || nz < 0 || nx >= width || nz >= height do continue
            neighbor := nz * width + nx
            if closed[neighbor] do continue
            world_x, world_z := min_x + f32(nx) * cell, min_z + f32(nz) * cell
            next_height := terrain.sample_height(project, 0, world_x, world_z)
            if next_height <= project.sea_level + .45 do continue
            diagonal := direction[0] != 0 && direction[1] != 0
            distance_cost := diagonal ? f32(1.41421356) : f32(1)
            grade := math.abs(next_height - current_height) / cell
            cross_slope := settlement_terrain_slope(project, world_x, world_z)
            grade_limit, preferred_grade := f32(.10), f32(.06)
            grade_weight, contour_weight := f32(18), f32(7)
            switch route_class {
            case .Civic_Spine, .Connector:
                grade_limit, preferred_grade = .10, .06
            case .Street:
                grade_limit, preferred_grade = .13, .08
            case .Lane, .Alley:
                grade_limit, preferred_grade = .18, .12
                grade_weight, contour_weight = 10, 4
            case .Stair:
                grade_limit, preferred_grade = .40, .12
                grade_weight, contour_weight = 2, 1
            case .Waterfront:
                grade_limit, preferred_grade = .08, .04
                grade_weight, contour_weight = 24, 12
            case .Ridge:
                grade_limit, preferred_grade = .12, .07
                grade_weight, contour_weight = 16, 4
            }
            if grade > grade_limit do continue
            excess_grade := max(grade - preferred_grade, f32(0))
            terrain_cost :=
                distance_cost *
                (1 + grade * grade_weight + excess_grade * grade_weight * 4 + cross_slope * contour_weight)
            candidate := costs[current] + terrain_cost
            if candidate >= costs[neighbor] do continue
            costs[neighbor] = candidate
            parents[neighbor] = current
            heuristic := linalg.length([2]f32{f32(finish_gx - nx), f32(finish_gz - nz)})
            estimates[neighbor] = candidate + heuristic
            open[neighbor] = true
        }
    }

    if start != finish && parents[finish] < 0 {
        result.points[0] = {start_x, start_z}
        result.points[1] = {finish_x, finish_z}
        result.count = 2
        return result
    }

    reversed: [SETTLEMENT_ROUTE_GRID * SETTLEMENT_ROUTE_GRID]int
    reversed_count := 0
    cursor := finish
    for cursor >= 0 && reversed_count < len(reversed) {
        reversed[reversed_count] = cursor
        reversed_count += 1
        if cursor == start do break
        cursor = parents[cursor]
    }
    point_budget := 4
    switch route_class {
    case .Civic_Spine, .Connector, .Waterfront, .Ridge:
        point_budget = 3
    case .Street:
        point_budget = 4
    case .Lane, .Alley:
        point_budget = 8
    case .Stair:
        point_budget = 10
    }
    desired := min(reversed_count, point_budget)
    for point_index in 0 ..< desired {
        reverse_index := reversed_count - 1 - (point_index * (reversed_count - 1) / max(desired - 1, 1))
        node := reversed[reverse_index]
        gx, gz := node % width, node / width
        result.points[result.count] = {min_x + f32(gx) * cell, min_z + f32(gz) * cell}
        result.count += 1
    }
    result.points[0] = {start_x, start_z}
    result.points[result.count - 1] = {finish_x, finish_z}
    return result
}

settlement_route_commit :: proc(
    project: ^terrain.Project,
    route: Settlement_Route,
    width, shoulder: f32,
    pavement: roads.Pavement,
) {
    if project == nil || route.count < 2 do return
    graph := &project.road_graph
    if graph.node_count + route.count > roads.MAX_NODES || graph.edge_count + route.count - 1 > roads.MAX_EDGES {
        return
    }
    nodes: [SETTLEMENT_ROUTE_CAPACITY]int
    for index in 0 ..< route.count {
        point := route.points[index]
        y := terrain.sample_height(project, 0, point[0], point[1])
        nodes[index] = -1
        for existing_index in 0 ..< graph.node_count {
            existing := graph.nodes[existing_index].position
            dx, dz := existing.x - point[0], existing.z - point[1]
            if dx * dx + dz * dz <= 4 {
                nodes[index] = existing_index
                break
            }
        }
        if nodes[index] < 0 do nodes[index] = roads.add_node(graph, {point[0], y, point[1]}, width * .55)
    }
    for index in 0 ..< route.count - 1 {
        if nodes[index] < 0 || nodes[index + 1] < 0 || nodes[index] == nodes[index + 1] do continue
        a, b := graph.nodes[nodes[index]].position, graph.nodes[nodes[index + 1]].position
        dx, dz := b.x - a.x, b.z - a.z
        c0 := roads.Vec3{a.x + dx / 3, 0, a.z + dz / 3}
        c1 := roads.Vec3{a.x + dx * 2 / 3, 0, a.z + dz * 2 / 3}
        c0.y = terrain.sample_height(project, 0, c0.x, c0.z)
        c1.y = terrain.sample_height(project, 0, c1.x, c1.z)
        // Settlement presets express paved width, while the road graph stores
        // half-width from centerline to edge.
        _ = roads.add_edge(graph, nodes[index], nodes[index + 1], c0, c1, width * .5, shoulder, pavement)
    }
}
