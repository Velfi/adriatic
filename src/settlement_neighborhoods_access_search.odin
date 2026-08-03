package main

import planar_geometry "../packages/planar_geometry"

import architecture "../packages/architecture"
import roads "../packages/roads"
import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"

settlement_plan_add_neighborhood :: proc(
    plan: ^Settlement_Plan,
    center: [2]f32,
    radius, density, suitability, age: f32,
    tissue: Settlement_Tissue,
    rng: ^Settlement_Rng,
) {
    if plan == nil || plan.neighborhood_count >= len(plan.neighborhoods) do return
    plan.neighborhoods[plan.neighborhood_count] = {
        center      = center,
        radius      = radius,
        density     = density,
        age         = age,
        suitability = suitability,
        tissue      = tissue,
    }
    plan.neighborhood_count += 1
}

settlement_nearest_tissue :: proc(plan: ^Settlement_Plan, x, z: f32) -> Settlement_Tissue {
    best, best_distance := Settlement_Tissue.Later_Extension, f32(1e30)
    for neighborhood in plan.neighborhoods[:plan.neighborhood_count] {
        delta := [2]f32{x - neighborhood.center.x, z - neighborhood.center.y}
        distance := linalg.dot(delta, delta)
        if distance < best_distance {
            best, best_distance = neighborhood.tissue, distance
        }
    }
    return best
}

settlement_nearest_route_frame :: proc(
    plan: ^Settlement_Plan,
    point: [2]f32,
    route_filter: int = -1,
) -> (
    origin, tangent, normal: [2]f32,
    width, shoulder, distance_to_route: f32,
    route_index: int,
    found: bool,
) {
    best_distance := f32(1e30)
    route_index = -1
    for route, candidate_route_index in plan.routes[:plan.route_count] {
        if route_filter >= 0 && candidate_route_index != route_filter do continue
        if !route.drivable do continue
        for index in 0 ..< route.geometry.count - 1 {
            a, b := route.geometry.points[index], route.geometry.points[index + 1]
            delta := b - a
            length_squared := linalg.dot(delta, delta)
            if length_squared <= .001 do continue
            along := clamp(linalg.dot(point - a, delta) / length_squared, 0, 1)
            candidate := a + delta * along
            offset := point - candidate
            distance := linalg.dot(offset, offset)
            if distance >= best_distance do continue
            length := linalg.length(delta)
            origin = candidate
            tangent = delta / length
            normal = {-tangent.y, tangent.x}
            width = route.width
            shoulder = route.shoulder
            distance_to_route = f32(math.sqrt(f64(distance)))
            route_index = candidate_route_index
            found = true
            best_distance = distance
        }
    }
    return
}

settlement_nearest_committed_road_distance :: proc(project: ^terrain.Project, point: [2]f32) -> f32 {
    if project == nil do return 1e30
    best := f32(1e30)
    graph := &project.road_graph
    for edge in graph.edges[:graph.edge_count] {
        if settlement_route_edge_is_runway(edge) do continue
        previous := roads.edge_point(graph, edge, 0)
        for segment in 1 ..= 12 {
            current := roads.edge_point(graph, edge, f32(segment) / 12)
            start := [2]f32{previous.x, previous.z}
            finish := [2]f32{current.x, current.z}
            delta := finish - start
            length_squared := linalg.dot(delta, delta)
            if length_squared > .0001 {
                along := clamp(linalg.dot(point - start, delta) / length_squared, f32(0), f32(1))
                best = min(best, linalg.length(point - (start + delta * along)))
            }
            previous = current
        }
    }
    return best
}

settlement_structure_clear :: proc(
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan,
    x, z, width, depth, rotation, separation: f32,
) -> bool {
    if !settlement_airport_terminals_clear(project, x, z, width, depth, rotation, separation) do return false
    tangent := [2]f32{f32(math.cos(f64(rotation))), f32(math.sin(f64(rotation)))}
    building_normal := [2]f32{-tangent.y, tangent.x}
    graph := &project.road_graph
    for edge in graph.edges[:graph.edge_count] {
        previous := roads.edge_point(graph, edge, 0)
        for segment in 1 ..= 12 {
            current := roads.edge_point(graph, edge, f32(segment) / 12)
            segment_x, segment_z := current.x - previous.x, current.z - previous.z
            segment_delta := [2]f32{segment_x, segment_z}
            length_squared := linalg.dot(segment_delta, segment_delta)
            if length_squared <= .00001 {
                previous = current
                continue
            }
            offset := [2]f32{x - previous.x, z - previous.z}
            amount := clamp(linalg.dot(offset, segment_delta) / length_squared, 0, 1)
            distance := linalg.length(offset - segment_delta * amount)
            segment_length := linalg.length(segment_delta)
            road_normal := [2]f32{-segment_delta.y / segment_length, segment_delta.x / segment_length}
            projected_half_extent :=
                math.abs(linalg.dot(road_normal, tangent)) * width * .5 +
                math.abs(linalg.dot(road_normal, building_normal)) * depth * .5
            required_distance := edge.half_width + edge.shoulder_width + projected_half_extent + .6
            if distance < required_distance do return false
            previous = current
        }
    }
    for structure in project.structures[:project.structure_count] {
        if !settlement_oriented_rectangles_clear(
            x,
            z,
            width,
            depth,
            rotation,
            structure.center_x,
            structure.center_z,
            structure.width,
            structure.depth,
            structure.rotation,
            separation,
        ) {
            return false
        }
    }
    for structure in city_plan.structures[:city_plan.count] {
        if !settlement_oriented_rectangles_clear(
            x,
            z,
            width,
            depth,
            rotation,
            structure.center_x,
            structure.center_z,
            structure.width,
            structure.depth,
            structure.rotation,
            separation,
        ) {
            return false
        }
    }
    return true
}

// The procedural terminal is presentation geometry rather than a full-sized
// terrain.Structure, so ordinary structure collision cannot see it. Reserve
// the union of its 42 x 30 m terminal forecourt and the inward 15 x 20 m
// asphalt approach explicitly. The resulting 42 m square also covers airport
// stamps, whose persistent structure is intentionally only a tiny marker.
settlement_airport_terminals_clear :: proc(
    project: ^terrain.Project,
    x, z, width, depth, rotation, separation: f32,
) -> bool {
    if project == nil do return true
    airport_clearance := max(separation, f32(2))
    for sign in terrain.DEFAULT_ISLAND_SIGNS {
        runway_found := false
        for edge in project.road_graph.edges[:project.road_graph.edge_count] {
            if !settlement_route_edge_is_runway(edge) do continue
            from := project.road_graph.nodes[edge.from].position
            to := project.road_graph.nodes[edge.to].position
            if (from.x + to.x) * .5 * sign > 0 {
                runway_found = true
                break
            }
        }
        if !runway_found do continue
        airport_x, airport_z := terrain.default_airport_center_for_project(project, sign)
        if !settlement_oriented_rectangles_clear(
            x,
            z,
            width,
            depth,
            rotation,
            airport_x,
            airport_z,
            42,
            42,
            0,
            airport_clearance,
        ) {
            return false
        }
    }
    for structure in project.structures[:project.structure_count] {
        if !airport_structure_is_stamp(structure) do continue
        if !settlement_oriented_rectangles_clear(
            x,
            z,
            width,
            depth,
            rotation,
            structure.center_x,
            structure.center_z,
            42,
            42,
            structure.rotation,
            airport_clearance,
        ) {
            return false
        }
    }
    return true
}

// A viable center point is not enough near an irregular shoreline or river: a
// rotated parcel can still cantilever over water. Keep samples no farther than
// two metres apart so a narrow or diagonal generated channel cannot pass
// between the old corner/center probes.
settlement_structure_footprint_on_land :: proc(
    project: ^terrain.Project,
    x, z, width, depth, rotation: f32,
    clearance: f32 = .6,
) -> bool {
    if project == nil do return false
    tangent := [2]f32{f32(math.cos(f64(rotation))), f32(math.sin(f64(rotation)))}
    normal := [2]f32{-tangent.y, tangent.x}
    width_steps := max(int(math.ceil(f64(width / 2))), 1)
    depth_steps := max(int(math.ceil(f64(depth / 2))), 1)
    for depth_step in 0 ..= depth_steps {
        depth_offset := (f32(depth_step) / f32(depth_steps) - .5) * depth
        for width_step in 0 ..= width_steps {
            width_offset := (f32(width_step) / f32(width_steps) - .5) * width
            point := [2]f32{x, z} + tangent * width_offset + normal * depth_offset
            land_height, _, land_found := terrain.sample_land(project, 0, point[0], point[1])
            if !land_found || land_height <= project.sea_level + clearance || terrain.active_waterway_at(project, 0, point[0], point[1]) {
                return false
            }
        }
    }
    return true
}

settlement_oriented_rectangles_clear :: proc(
    ax, az, aw, ad, ar: f32,
    bx, bz, bw, bd, br: f32,
    separation: f32,
) -> bool {
    return planar_geometry.oriented_rectangles_clear({ax, az}, {aw, ad}, ar, {bx, bz}, {bw, bd}, br, separation)
}

settlement_plan_record_built_group :: proc(
    plan: ^Settlement_Plan,
    city_plan: ^architecture.City_Plan,
    first, count: int,
    tissue: Settlement_Tissue,
) {
    if plan == nil || city_plan == nil || count < 2 || plan.block_count >= len(plan.blocks) do return
    minimum_x, minimum_z := f32(1e30), f32(1e30)
    maximum_x, maximum_z := f32(-1e30), f32(-1e30)
    for index in first ..< first + count {
        if index < 0 || index >= city_plan.parcel_count do continue
        for corner in city_plan.parcels[index].corners {
            minimum_x = min(minimum_x, corner[0])
            minimum_z = min(minimum_z, corner[1])
            maximum_x = max(maximum_x, corner[0])
            maximum_z = max(maximum_z, corner[1])
        }
    }
    width, depth := maximum_x - minimum_x, maximum_z - minimum_z
    if width <= 0 || depth <= 0 do return
    short_side, long_side := min(width, depth), max(width, depth)
    block := Settlement_Block {
        center       = {(minimum_x + maximum_x) * .5, (minimum_z + maximum_z) * .5},
        short_side   = short_side,
        long_side    = long_side,
        area         = width * depth,
        irregularity = clamp(1 - f32(count) * .08, 0, 1),
        tissue       = tissue,
        corner_count = 4,
    }
    block.corners[0] = {minimum_x, minimum_z}
    block.corners[1] = {maximum_x, minimum_z}
    block.corners[2] = {maximum_x, maximum_z}
    block.corners[3] = {minimum_x, maximum_z}
    plan.blocks[plan.block_count] = block
    plan.block_count += 1
}

settlement_fabric_cell_kept :: proc(scale: Settlement_Scale, age: f32, hash: u32) -> bool {
    switch scale {
    case .City:
        return true
    case .Town:
        if age <= .58 do return true
        // A compact hillside town can feather into a few villas, but a long
        // tail of old one-house cells turns every contour road into ribbon
        // suburbia. End the urban fabric sooner and leave remote compounds to
        // the village system.
        if age >= .80 do return false
        edge_probability := clamp((.80 - age) / (.80 - .58), 0, 1)
        return f32(hash % 1000) / 1000 < edge_probability
    case .Village:
        if age <= .48 do return true
        if age >= .70 do return false
        edge_probability := clamp((.70 - age) / (.70 - .48), 0, 1)
        return f32(hash % 1000) / 1000 < edge_probability
    }
    return false
}

settlement_fabric_route_reachable :: proc(scale: Settlement_Scale, distance: f32, found: bool) -> bool {
    if !found do return false
    switch scale {
    case .City:
        // Dense urban tissue still needs a plausible walking connection to
        // circulation. Allowing every macro cell made contour-grown Aegean
        // cities form a detached carpet uphill from their road network.
        return distance <= 55
    case .Town:
        // Beyond this distance a town parcel needs a long isolated access
        // spoke and reads as scattered countryside. Keep urban fabric within
        // a walkable frontage/court band; genuinely remote compounds belong
        // to the village generator.
        return distance <= 32
    case .Village:
        return distance <= 30
    }
    return false
}

settlement_city_prune_to_largest_component :: proc(city_plan: ^architecture.City_Plan, link_distance: f32) {
    if city_plan == nil || city_plan.count <= 1 do return
    component := make([]int, city_plan.count)
    queue := make([]int, city_plan.count)
    defer delete(component)
    defer delete(queue)
    component_count, largest_component, largest_size := 0, -1, 0
    for index in 0 ..< city_plan.count do component[index] = -1
    for root in 0 ..< city_plan.count {
        if component[root] >= 0 do continue
        queue_start, queue_end, size := 0, 1, 0
        queue[0] = root
        component[root] = component_count
        for queue_start < queue_end {
            current := queue[queue_start]
            queue_start += 1
            size += 1
            a := city_plan.structures[current]
            for candidate in 0 ..< city_plan.count {
                if component[candidate] >= 0 do continue
                b := city_plan.structures[candidate]
                dx, dz := a.center_x - b.center_x, a.center_z - b.center_z
                if dx * dx + dz * dz > link_distance * link_distance do continue
                component[candidate] = component_count
                queue[queue_end] = candidate
                queue_end += 1
            }
        }
        if size > largest_size {
            largest_component, largest_size = component_count, size
        }
        component_count += 1
    }
    write := 0
    for read in 0 ..< city_plan.count {
        if component[read] != largest_component do continue
        city_plan.structures[write] = city_plan.structures[read]
        city_plan.parcels[write] = city_plan.parcels[read]
        write += 1
    }
    city_plan.count = write
    city_plan.parcel_count = write
    resize(&city_plan.structures, write)
    resize(&city_plan.parcels, write)
}

settlement_segment_intersects_structure_clearance :: proc(
    start, end: [2]f32,
    structure: terrain.Structure,
    clearance: f32 = .8,
) -> bool {
    sine, cosine := math.sin(structure.rotation), math.cos(structure.rotation)
    center := [2]f32{structure.center_x, structure.center_z}
    start_delta, end_delta := start - center, end - center
    local_start := [2]f32 {
        start_delta[0] * cosine + start_delta[1] * sine,
        -start_delta[0] * sine + start_delta[1] * cosine,
    }
    local_end := [2]f32{end_delta[0] * cosine + end_delta[1] * sine, -end_delta[0] * sine + end_delta[1] * cosine}
    direction := local_end - local_start
    half_extents := [2]f32{structure.width * .5 + clearance, structure.depth * .5 + clearance}
    entry, exit := f32(0), f32(1)
    for axis in 0 ..< 2 {
        if math.abs(direction[axis]) <= 1e-5 {
            if local_start[axis] < -half_extents[axis] || local_start[axis] > half_extents[axis] {
                return false
            }
            continue
        }
        inverse := 1 / direction[axis]
        near := (-half_extents[axis] - local_start[axis]) * inverse
        far := (half_extents[axis] - local_start[axis]) * inverse
        if near > far do near, far = far, near
        entry = max(entry, near)
        exit = min(exit, far)
        if entry > exit do return false
    }
    return true
}

settlement_pedestrian_segment_clear :: proc(city_plan: ^architecture.City_Plan, start, end: [2]f32) -> bool {
    if city_plan == nil do return false
    for structure in city_plan.structures[:city_plan.count] {
        if settlement_segment_intersects_structure_clearance(start, end, structure) do return false
    }
    return true
}

settlement_structure_routes_clear :: proc(
    plan: ^Settlement_Plan,
    structure: terrain.Structure,
    clearance: f32 = .35,
) -> bool {
    if plan == nil do return false
    for route in plan.routes[:plan.route_count] {
        if route.geometry.count < 2 do continue
        corridor_clearance := route.width * .5 + route.shoulder + max(clearance, f32(0))
        for point_index in 0 ..< route.geometry.count - 1 {
            if settlement_segment_intersects_structure_clearance(
                route.geometry.points[point_index],
                route.geometry.points[point_index + 1],
                structure,
                corridor_clearance,
            ) {
                return false
            }
        }
    }
    return true
}

// Placement plans against authored route geometry, but committed roads may
// curve between those waypoints and widen at graph junctions. Reject against
// the exact road graph that will render so no building footprint can occupy a
// paved lane even when the planned chord itself was clear.
settlement_structure_committed_roads_clear :: proc(
    project: ^terrain.Project,
    structure: terrain.Structure,
    clearance: f32 = .75,
) -> bool {
    if project == nil do return false
    graph := &project.road_graph
    for edge in graph.edges[:graph.edge_count] {
        previous := roads.edge_point(graph, edge, 0)
        corridor_clearance := edge.half_width + edge.shoulder_width + max(clearance, f32(0))
        for sample in 1 ..= 24 {
            current := roads.edge_point(graph, edge, f32(sample) / 24)
            if settlement_segment_intersects_structure_clearance(
                {previous.x, previous.z},
                {current.x, current.z},
                structure,
                corridor_clearance,
            ) {
                return false
            }
            previous = current
        }
    }
    tangent := [2]f32{f32(math.cos(f64(structure.rotation))), f32(math.sin(f64(structure.rotation)))}
    normal := [2]f32{-tangent[1], tangent[0]}
    center := [2]f32{structure.center_x, structure.center_z}
    for node in graph.nodes[:graph.node_count] {
        delta := [2]f32{node.position.x, node.position.z} - center
        local_x := math.abs(linalg.dot(delta, tangent))
        local_z := math.abs(linalg.dot(delta, normal))
        radius := node.junction_radius + max(clearance, f32(0))
        if local_x <= structure.width * .5 + radius && local_z <= structure.depth * .5 + radius {
            return false
        }
    }
    return true
}

// Public squares reserve the broad apron around a road junction, not merely
// the narrow strips already protected by the incident road corridors.
settlement_structure_plazas_clear :: proc(
    plan: ^Settlement_Plan,
    structure: terrain.Structure,
    clearance: f32 = 1,
) -> bool {
    if plan == nil do return false
    for edit in plan.terrain_edits[:plan.terrain_edit_count] {
        if edit.kind != .Plaza do continue
        if !settlement_oriented_rectangles_clear(
            structure.center_x,
            structure.center_z,
            structure.width,
            structure.depth,
            structure.rotation,
            edit.center[0],
            edit.center[1],
            edit.half_extent[0] * 2,
            edit.half_extent[1] * 2,
            0,
            clearance,
        ) {
            return false
        }
    }
    return true
}

// Bounded local lattice used for collision-aware doorway routing.
SETTLEMENT_ACCESS_GRID :: 61
SETTLEMENT_ACCESS_HEADINGS :: 8
SETTLEMENT_ACCESS_STATE_CAPACITY :: SETTLEMENT_ACCESS_GRID * SETTLEMENT_ACCESS_GRID * SETTLEMENT_ACCESS_HEADINGS

Settlement_Access_Heap :: struct {
    states:    [SETTLEMENT_ACCESS_STATE_CAPACITY]int,
    positions: [SETTLEMENT_ACCESS_STATE_CAPACITY]int,
    count:     int,
}

settlement_access_heap_swap :: proc(heap: ^Settlement_Access_Heap, first, second: int) {
    if heap == nil || first == second do return
    first_state, second_state := heap.states[first], heap.states[second]
    heap.states[first], heap.states[second] = second_state, first_state
    heap.positions[first_state], heap.positions[second_state] = second, first
}

settlement_access_heap_decrease :: proc(
    heap: ^Settlement_Access_Heap,
    estimates: ^[SETTLEMENT_ACCESS_STATE_CAPACITY]f32,
    state: int,
) {
    if heap == nil || estimates == nil || state < 0 || state >= len(heap.positions) do return
    position := heap.positions[state]
    if position < 0 {
        if heap.count >= len(heap.states) do return
        position = heap.count
        heap.states[position], heap.positions[state] = state, position
        heap.count += 1
    }
    for position > 0 {
        parent := (position - 1) / 2
        if estimates[heap.states[parent]] <= estimates[heap.states[position]] do break
        settlement_access_heap_swap(heap, parent, position)
        position = parent
    }
}

settlement_access_heap_pop :: proc(
    heap: ^Settlement_Access_Heap,
    estimates: ^[SETTLEMENT_ACCESS_STATE_CAPACITY]f32,
) -> int {
    if heap == nil || estimates == nil || heap.count <= 0 do return -1
    result := heap.states[0]
    heap.positions[result] = -1
    heap.count -= 1
    if heap.count <= 0 do return result
    heap.states[0] = heap.states[heap.count]
    heap.positions[heap.states[0]] = 0
    position := 0
    for {
        left, right := position * 2 + 1, position * 2 + 2
        if left >= heap.count do break
        child := left
        if right < heap.count && estimates[heap.states[right]] < estimates[heap.states[left]] do child = right
        if estimates[heap.states[position]] <= estimates[heap.states[child]] do break
        settlement_access_heap_swap(heap, position, child)
        position = child
    }
    return result
}

settlement_access_segment_clear :: proc(
    city_plan: ^architecture.City_Plan,
    start, end: [2]f32,
    clearance: f32 = .4,
    ignore_structure: int = -1,
) -> bool {
    if city_plan == nil do return false
    for structure, structure_index in city_plan.structures[:city_plan.count] {
        if structure_index == ignore_structure do continue
        if settlement_segment_intersects_structure_clearance(start, end, structure, clearance) do return false
    }
    return true
}
