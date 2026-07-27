package main

import architecture "../packages/architecture"
import roads "../packages/roads"
import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"

settlement_plan_add_route :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    geometry: Settlement_Route,
    class: Settlement_Route_Class,
    required, drivable: bool,
    rng: ^Settlement_Rng,
) {
    if plan == nil || geometry.count < 2 || plan.route_count >= len(plan.routes) do return
    width := settlement_route_width_sample(rng, class)
    average_grade, maximum_grade: f32
    grade_count := 0
    for index in 0 ..< geometry.count - 1 {
        a, b := geometry.points[index], geometry.points[index + 1]
        distance := linalg.length(b - a)
        if distance <= .01 do continue
        grade :=
            math.abs(terrain.sample_height(project, 0, b[0], b[1]) - terrain.sample_height(project, 0, a[0], a[1])) /
            distance
        average_grade += grade
        maximum_grade = max(maximum_grade, grade)
        grade_count += 1
    }
    if grade_count > 0 do average_grade /= f32(grade_count)
    plan.routes[plan.route_count] = {
        geometry      = geometry,
        class         = class,
        width         = width,
        shoulder      = drivable ? f32(.8) : f32(.15),
        pavement      = .Cobblestone,
        required      = required,
        drivable      = drivable,
        average_grade = average_grade,
        maximum_grade = maximum_grade,
    }
    plan.route_count += 1
}

settlement_plan_commit_routes :: proc(plan: ^Settlement_Plan, project: ^terrain.Project) {
    if plan == nil || project == nil do return
    // Required anchors are stored first by the generator. This deterministic
    // priority pass preserves them if the fixed road graph reaches capacity.
    for required_pass in 0 ..= 1 {
        required := required_pass == 0
        for route in plan.routes[:plan.route_count] {
            if route.required != required || !route.drivable do continue
            settlement_route_commit(project, route.geometry, route.width, route.shoulder, route.pavement)
        }
    }
}

settlement_route_join_at_end :: proc(first, second: Settlement_Route) -> Settlement_Route {
    result := first
    if first.count == 0 do return second
    if second.count == 0 do return first
    for index in 1 ..< second.count {
        if result.count >= len(result.points) do break
        result.points[result.count] = second.points[index]
        result.count += 1
    }
    return result
}

settlement_plan_add_segmented_spine :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    start, center, finish: [2]f32,
    central_class: Settlement_Route_Class,
    rng: ^Settlement_Rng,
) {
    if plan == nil || project == nil do return
    direction := linalg.normalize0(finish - start)
    length := linalg.length(finish - start)
    if length <= .01 do return
    central_half_length := min(max(plan.request.radius * .055, f32(8)), f32(14))
    central_start := center - direction * central_half_length
    central_finish := center + direction * central_half_length
    central_start[0], central_start[1] = settlement_fit_landscape_point(
        project,
        central_start[0],
        central_start[1],
        central_half_length * .45,
    )
    central_finish[0], central_finish[1] = settlement_fit_landscape_point(
        project,
        central_finish[0],
        central_finish[1],
        central_half_length * .45,
    )
    first := settlement_route_find(project, start[0], start[1], central_start[0], central_start[1], .Street)
    center_route := settlement_route_find(
        project,
        central_start[0],
        central_start[1],
        central_finish[0],
        central_finish[1],
        central_class,
    )
    last := settlement_route_find(project, central_finish[0], central_finish[1], finish[0], finish[1], .Street)
    settlement_plan_add_route(plan, project, first, .Street, true, true, rng)
    settlement_plan_add_route(plan, project, center_route, central_class, true, true, rng)
    settlement_plan_add_route(plan, project, last, .Street, true, true, rng)
}

settlement_route_anchor_eligible :: proc(scale: Settlement_Scale, age: f32) -> bool {
    switch scale {
    case .City:
        return age <= .78
    case .Town:
        return age <= .72
    case .Village:
        return age <= .62
    }
    return false
}

settlement_route_anchor_supported :: proc(plan: ^Settlement_Plan, index: int) -> bool {
    if plan == nil || index < 0 || index >= plan.macro_cell_count do return false
    cell := plan.macro_cells[index]
    reach := max(cell.radius * 2.15, f32(1))
    support := 0
    for other, other_index in plan.macro_cells[:plan.macro_cell_count] {
        if other_index == index do continue
        dx, dz := other.center[0] - cell.center[0], other.center[1] - cell.center[1]
        if dx * dx + dz * dz <= reach * reach do support += 1
    }
    required := 3
    switch plan.request.scale {
    case .City:
        required = 3
    case .Town:
        required = 2
    case .Village:
        required = 1
    }
    return support >= required
}

settlement_plan_build_macro_routes :: proc(plan: ^Settlement_Plan, project: ^terrain.Project, rng: ^Settlement_Rng) {
    if plan == nil || project == nil || plan.macro_cell_count < 2 do return
    center := plan.request.center
    radius := plan.request.radius
    west, east, north, south, core := -1, -1, -1, -1, -1
    for cell, index in plan.macro_cells[:plan.macro_cell_count] {
        hash := u32(index) * u32(0x9e3779b9) ~ plan.request.seed
        if !settlement_fabric_cell_kept(plan.request.scale, cell.age, hash) ||
           !settlement_route_anchor_eligible(plan.request.scale, cell.age) ||
           !settlement_route_anchor_supported(plan, index) {
            continue
        }
        if core < 0 {
            west, east, north, south, core = index, index, index, index, index
            continue
        }
        if cell.center[0] < plan.macro_cells[west].center[0] do west = index
        if cell.center[0] > plan.macro_cells[east].center[0] do east = index
        if cell.center[1] < plan.macro_cells[north].center[1] do north = index
        if cell.center[1] > plan.macro_cells[south].center[1] do south = index
        if cell.age < plan.macro_cells[core].age do core = index
    }
    if core < 0 do return
    core_point := plan.macro_cells[core].center

    if plan.request.scale == .Village {
        // A village uses actual tissue extrema as the ends of its three-arm
        // junction. Fixed-radius endpoints produced long roads through empty
        // terrain whenever the terrain-grown envelope was asymmetric.
        endpoints := plan.request.region == .Adriatic ? [3]int{west, north, east} : [3]int{west, south, east}
        accepted: [3]int
        accepted_count := 0
        for endpoint in endpoints {
            if endpoint == core do continue
            duplicate := false
            for index in 0 ..< accepted_count {
                if accepted[index] == endpoint {
                    duplicate = true
                    break
                }
            }
            if duplicate do continue
            accepted[accepted_count] = endpoint
            accepted_count += 1
            point := plan.macro_cells[endpoint].center
            if accepted_count == 1 {
                direction := linalg.normalize0(core_point - point)
                length := linalg.length(core_point - point)
                if length <= .01 do continue
                civic_length := min(max(radius * .06, f32(5)), f32(8))
                civic_start := core_point - direction * civic_length
                approach := settlement_route_find(project, point[0], point[1], civic_start[0], civic_start[1], .Street)
                civic := settlement_route_find(
                    project,
                    civic_start[0],
                    civic_start[1],
                    core_point[0],
                    core_point[1],
                    .Civic_Spine,
                )
                settlement_plan_add_route(plan, project, approach, .Street, true, true, rng)
                settlement_plan_add_route(plan, project, civic, .Civic_Spine, true, true, rng)
            } else {
                route := settlement_route_find(project, point[0], point[1], core_point[0], core_point[1], .Street)
                settlement_plan_add_route(plan, project, route, .Street, true, true, rng)
            }
        }
        return
    }

    if plan.request.region == .Adriatic {
        settlement_plan_add_segmented_spine(
            plan,
            project,
            plan.macro_cells[west].center,
            core_point,
            plan.macro_cells[east].center,
            .Civic_Spine,
            rng,
        )
    } else {
        // Aegean civic space follows an elevation band instead of bisecting
        // the settlement. Snap the desired offset to retained fabric so a
        // contour ribbon cannot loop through an empty fringe.
        desired_mid := [2]f32{center[0], center[1] + radius * .22}
        contour_index, contour_distance := core, f32(1e30)
        for cell, cell_index in plan.macro_cells[:plan.macro_cell_count] {
            if !settlement_route_anchor_eligible(plan.request.scale, cell.age) ||
               !settlement_route_anchor_supported(plan, cell_index) {
                continue
            }
            dx, dz := cell.center[0] - desired_mid[0], cell.center[1] - desired_mid[1]
            distance := dx * dx + dz * dz
            if distance < contour_distance {
                contour_index, contour_distance = cell_index, distance
            }
        }
        contour_mid := plan.macro_cells[contour_index].center
        settlement_plan_add_segmented_spine(
            plan,
            project,
            plan.macro_cells[west].center,
            contour_mid,
            plan.macro_cells[east].center,
            .Waterfront,
            rng,
        )
        route := settlement_route_find(
            project,
            core_point[0],
            core_point[1],
            contour_mid[0],
            contour_mid[1],
            .Connector,
        )
        settlement_plan_add_route(plan, project, route, .Connector, true, true, rng)
    }

    // The old route deliberately cuts across the younger tissue. Splitting it
    // at the historic core guarantees graph connectivity without turning it
    // into a geometrically perfect avenue.
    confounding_ends := plan.request.region == .Adriatic ? [2]int{north, south} : [2]int{south, east}
    old_first := settlement_route_find(
        project,
        plan.macro_cells[confounding_ends[0]].center[0],
        plan.macro_cells[confounding_ends[0]].center[1],
        core_point[0],
        core_point[1],
        .Street,
    )
    old_second := settlement_route_find(
        project,
        core_point[0],
        core_point[1],
        plan.macro_cells[confounding_ends[1]].center[0],
        plan.macro_cells[confounding_ends[1]].center[1],
        .Street,
    )
    confounding := settlement_route_join_at_end(old_first, old_second)
    settlement_plan_add_route(plan, project, confounding, .Street, true, true, rng)

    connector_count := 1
    used_hubs: [2]int
    for connector_index in 0 ..< connector_count {
        hub, best_score := -1, f32(-1)
        for cell, cell_index in plan.macro_cells[:plan.macro_cell_count] {
            hash := u32(cell_index) * u32(0x9e3779b9) ~ plan.request.seed
            if cell_index == core ||
               !settlement_fabric_cell_kept(plan.request.scale, cell.age, hash) ||
               !settlement_route_anchor_eligible(plan.request.scale, cell.age) ||
               !settlement_route_anchor_supported(plan, cell_index) {
                continue
            }
            already_used := false
            for used_index in 0 ..< connector_index {
                if used_hubs[used_index] == cell_index do already_used = true
            }
            if already_used do continue
            dx, dz := cell.center[0] - core_point[0], cell.center[1] - core_point[1]
            score := (dx * dx + dz * dz) * (.35 + cell.density * .65)
            if score > best_score {
                hub, best_score = cell_index, score
            }
        }
        if hub < 0 do continue
        used_hubs[connector_index] = hub
        route := settlement_route_find(
            project,
            core_point[0],
            core_point[1],
            plan.macro_cells[hub].center[0],
            plan.macro_cells[hub].center[1],
            .Connector,
        )
        settlement_plan_add_route(plan, project, route, .Connector, connector_index == 0, true, rng)
    }
}

settlement_block_dimensions :: proc(rng: ^Settlement_Rng, tissue: Settlement_Tissue) -> (short_side, long_side: f32) {
    switch tissue {
    case .Dalmatian_Planned:
        return settlement_sample_triangular(rng, 18, 26, 36), settlement_sample_triangular(rng, 35, 48, 70)
    case .Venetian_Mercantile, .Harbor:
        return settlement_sample_triangular(rng, 28, 39, 55), settlement_sample_triangular(rng, 50, 72, 100)
    case .Later_Extension:
        return settlement_sample_triangular(rng, 45, 62, 85), settlement_sample_triangular(rng, 65, 88, 125)
    case .Cycladic_Accretion, .Contour_Terrace, .Church_Cluster:
        return settlement_sample_triangular(rng, 12, 26, 50), settlement_sample_triangular(rng, 20, 42, 85)
    case .Hillside_Accretion, .Fortified_Precinct:
        return settlement_sample_triangular(rng, 18, 28, 42), settlement_sample_triangular(rng, 28, 46, 70)
    }
    return 28, 46
}

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
) -> (
    origin, tangent, normal: [2]f32,
    width, shoulder, distance_to_route: f32,
    route_index: int,
    found: bool,
) {
    best_distance := f32(1e30)
    route_index = -1
    for route, candidate_route_index in plan.routes[:plan.route_count] {
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

settlement_structure_clear :: proc(
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan,
    x, z, width, depth, rotation, separation: f32,
) -> bool {
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

settlement_oriented_rectangles_clear :: proc(
    ax, az, aw, ad, ar: f32,
    bx, bz, bw, bd, br: f32,
    separation: f32,
) -> bool {
    a_tangent := [2]f32{f32(math.cos(f64(ar))), f32(math.sin(f64(ar)))}
    a_normal := [2]f32{-a_tangent[1], a_tangent[0]}
    b_tangent := [2]f32{f32(math.cos(f64(br))), f32(math.sin(f64(br)))}
    b_normal := [2]f32{-b_tangent[1], b_tangent[0]}
    delta := [2]f32{bx - ax, bz - az}
    axes := [4][2]f32{a_tangent, a_normal, b_tangent, b_normal}
    for axis in axes {
        center_distance := math.abs(delta[0] * axis[0] + delta[1] * axis[1])
        a_extent :=
            math.abs(a_tangent[0] * axis[0] + a_tangent[1] * axis[1]) * aw * .5 +
            math.abs(a_normal[0] * axis[0] + a_normal[1] * axis[1]) * ad * .5
        b_extent :=
            math.abs(b_tangent[0] * axis[0] + b_tangent[1] * axis[1]) * bw * .5 +
            math.abs(b_normal[0] * axis[0] + b_normal[1] * axis[1]) * bd * .5
        if center_distance >= a_extent + b_extent + separation do return true
    }
    return false
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
        if age >= .85 do return false
        edge_probability := clamp((.85 - age) / (.85 - .58), 0, 1)
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
        return distance <= 42
    case .Village:
        return distance <= 30
    }
    return false
}

settlement_city_prune_to_largest_component :: proc(city_plan: ^architecture.City_Plan, link_distance: f32) {
    if city_plan == nil || city_plan.count <= 1 do return
    component: [terrain.STRUCTURE_CAPACITY]int
    queue: [terrain.STRUCTURE_CAPACITY]int
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
}

settlement_pedestrian_segment_clear :: proc(city_plan: ^architecture.City_Plan, start, end: [2]f32) -> bool {
    if city_plan == nil do return false
    for sample in 1 ..< 10 {
        amount := f32(sample) / 10
        point := start + (end - start) * amount
        for structure in city_plan.structures[:city_plan.count] {
            delta := point - [2]f32{structure.center_x, structure.center_z}
            clearance := min(structure.width, structure.depth) * .42 + .8
            if linalg.dot(delta, delta) < clearance * clearance do return false
        }
    }
    return true
}

settlement_plan_generate_pedestrian_access :: proc(
    plan: ^Settlement_Plan,
    city_plan: ^architecture.City_Plan,
    rng: ^Settlement_Rng,
) {
    if plan == nil || city_plan == nil || rng == nil do return
    budget := 12
    maximum_length := f32(32)
    switch plan.request.scale {
    case .City:
        budget, maximum_length = 12, 32
    case .Town:
        budget, maximum_length = 6, 24
    case .Village:
        budget, maximum_length = 2, 32
    }
    for block in plan.blocks[:plan.block_count] {
        if city_plan.alley_count >= min(budget, len(city_plan.alleys)) do break
        origin, _, _, route_width, route_shoulder, route_distance, _, found := settlement_nearest_route_frame(
            plan,
            block.center,
        )
        if !found do continue
        approach_depth := min(block.short_side, block.long_side) * .5 + 1.2
        length := route_distance - route_width * .5 - route_shoulder - approach_depth
        if length < 4 || length > maximum_length do continue
        delta := block.center - origin
        distance := linalg.length(delta)
        if distance <= .01 do continue
        direction := delta / distance
        start_offset := route_width * .5 + route_shoulder + .45
        start := origin + direction * start_offset
        end := block.center - direction * approach_depth
        duplicate := false
        for alley in city_plan.alleys[:city_plan.alley_count] {
            previous := [2]f32{alley.start_x, alley.start_z}
            if linalg.length(previous - start) < 14 {
                duplicate = true
                break
            }
        }
        if duplicate || !settlement_pedestrian_segment_clear(city_plan, start, end) do continue
        width := settlement_route_width_sample(rng, .Alley)
        city_plan.alleys[city_plan.alley_count] = {
            start_x    = start[0],
            start_z    = start[1],
            end_x      = end[0],
            end_z      = end[1],
            half_width = width * .5,
        }
        city_plan.alley_count += 1
    }
}

settlement_lamp_position_clear :: proc(city_plan: ^architecture.City_Plan, x, z: f32) -> bool {
    if city_plan == nil do return false
    for structure in city_plan.structures[:city_plan.count] {
        sine, cosine := math.sin(structure.rotation), math.cos(structure.rotation)
        dx, dz := x - structure.center_x, z - structure.center_z
        local_x := dx * cosine + dz * sine
        local_z := -dx * sine + dz * cosine
        if math.abs(local_x) < structure.width * .5 + .65 && math.abs(local_z) < structure.depth * .5 + .65 {
            return false
        }
    }
    for lamp in city_plan.lamps[:city_plan.lamp_count] {
        dx, dz := x - lamp.x, z - lamp.z
        if dx * dx + dz * dz < 12 * 12 do return false
    }
    return true
}

settlement_plan_generate_lamps :: proc(plan: ^Settlement_Plan, city_plan: ^architecture.City_Plan) {
    if plan == nil || city_plan == nil || plan.request.scale == .Village do return
    for route in plan.routes[:plan.route_count] {
        if route.class != .Civic_Spine && route.class != .Waterfront && route.class != .Street {
            continue
        }
        spacing := route.class == .Civic_Spine ? f32(22) : f32(30)
        if plan.request.scale == .Town {
            spacing = route.class == .Civic_Spine ? f32(18) : f32(25)
        }
        for segment_index in 0 ..< route.geometry.count - 1 {
            a, b := route.geometry.points[segment_index], route.geometry.points[segment_index + 1]
            delta := b - a
            length := linalg.length(delta)
            if length < spacing * .65 do continue
            tangent := delta / length
            normal := [2]f32{-tangent.y, tangent.x}
            sample_count := int(length / spacing)
            for sample in 0 ..< sample_count {
                if city_plan.lamp_count >= len(city_plan.lamps) do return
                along := (f32(sample) + .5) / f32(sample_count)
                side := ((sample + segment_index) & 1) == 0 ? f32(1) : f32(-1)
                offset := route.width * .5 + route.shoulder + .65
                point := a + delta * along + normal * (offset * side)
                if !settlement_lamp_position_clear(city_plan, point.x, point.y) do continue
                city_plan.lamps[city_plan.lamp_count] = {
                    x   = point.x,
                    z   = point.y,
                    yaw = math.atan2(tangent.x, tangent.y),
                }
                city_plan.lamp_count += 1
            }
        }
    }
}

settlement_village_reason_pick :: proc(plan: ^Settlement_Plan, project: ^terrain.Project) -> Village_Reason {
    if plan == nil || project == nil do return .Route_Stop
    anchor := plan.request.center
    tissue := Settlement_Tissue.Dalmatian_Planned
    if plan.neighborhood_count > 0 {
        anchor = plan.neighborhoods[0].center
        tissue = plan.neighborhoods[0].tissue
    }
    height := terrain.sample_height(project, 0, anchor[0], anchor[1])
    sample := f32(10)
    dx :=
        terrain.sample_height(project, 0, anchor[0] + sample, anchor[1]) -
        terrain.sample_height(project, 0, anchor[0] - sample, anchor[1])
    dz :=
        terrain.sample_height(project, 0, anchor[0], anchor[1] + sample) -
        terrain.sample_height(project, 0, anchor[0], anchor[1] - sample)
    slope := linalg.length([2]f32{dx, dz}) / (sample * 2)
    if tissue == .Harbor || height <= project.sea_level + 5 do return .Harbor_Fishery
    if tissue == .Contour_Terrace || tissue == .Hillside_Accretion || slope >= .09 {
        if height > project.sea_level + 20 do return .Upland_Pastoral
        return .Agricultural_Terrace
    }
    selector := (plan.request.seed >> 5) & 3
    if selector == 0 do return .Agricultural_Terrace
    if selector == 1 && plan.request.region == .Aegean do return .Upland_Pastoral
    return .Route_Stop
}

settlement_village_program :: proc(
    reason: Village_Reason,
    seed: u32,
    purposes: ^[24]Settlement_Building_Purpose,
) -> int {
    if purposes == nil do return 0
    count := 0
    purposes[count] = .Inn_Shop
    purposes[count + 1] = .Workshop
    count += 2
    dwelling_count := 7 + int(seed % 4)
    for _ in 0 ..< dwelling_count {
        purposes[count] = .Dwelling
        count += 1
    }
    switch reason {
    case .Harbor_Fishery:
        purposes[count] = .Fishery
        purposes[count + 1] = .Fishery
        purposes[count + 2] = .Storehouse
        purposes[count + 3] = .Storehouse
        count += 4
    case .Agricultural_Terrace:
        purposes[count] = .Farmstead
        purposes[count + 1] = .Farmstead
        purposes[count + 2] = .Barn_Granary
        purposes[count + 3] = .Barn_Granary
        purposes[count + 4] = .Barn_Granary
        purposes[count + 5] = .Mill
        count += 6
    case .Upland_Pastoral:
        purposes[count] = .Farmstead
        purposes[count + 1] = .Barn_Granary
        purposes[count + 2] = .Barn_Granary
        purposes[count + 3] = .Storehouse
        count += 4
    case .Route_Stop:
        purposes[count] = .Farmstead
        purposes[count + 1] = .Barn_Granary
        purposes[count + 2] = .Storehouse
        count += 3
    }
    return count
}

settlement_village_purpose_dimensions :: proc(
    purpose: Settlement_Building_Purpose,
    region: Settlement_Region,
    rng: ^Settlement_Rng,
) -> (
    frontage, depth: f32,
) {
    frontage = settlement_sample_lognormal(rng, 7.5, .20, 4.5, 13)
    depth = clamp(frontage * settlement_sample_triangular(rng, 1.25, 1.4, 1.65), 6, 18)
    if region == .Aegean {
        frontage = settlement_sample_lognormal(rng, 6.5, .18, 4, 11)
        depth = clamp(frontage * settlement_sample_triangular(rng, 1.15, 1.3, 1.55), 5.5, 16)
    }
    switch purpose {
    case .Barn_Granary, .Storehouse:
        frontage = clamp(frontage * 1.15, 5.5, region == .Aegean ? f32(11) : f32(13))
        depth = clamp(depth * 1.12, 7, region == .Aegean ? f32(16) : f32(18))
    case .Workshop, .Inn_Shop, .Fishery, .Mill:
        frontage = clamp(frontage * 1.08, 5, region == .Aegean ? f32(11) : f32(13))
    case .Farmstead:
        depth = clamp(depth * 1.10, 7, region == .Aegean ? f32(16) : f32(18))
    case .Dwelling:
    }
    return
}

settlement_village_add_path :: proc(city_plan: ^architecture.City_Plan, start, end: [2]f32, width: f32) {
    if city_plan == nil || city_plan.alley_count >= len(city_plan.alleys) do return
    dx, dz := end[0] - start[0], end[1] - start[1]
    length_squared := dx * dx + dz * dz
    if length_squared < 5 * 5 ||
       length_squared > 55 * 55 ||
       !settlement_pedestrian_segment_clear(city_plan, start, end) {
        return
    }
    city_plan.alleys[city_plan.alley_count] = {
        start_x    = start[0],
        start_z    = start[1],
        end_x      = end[0],
        end_z      = end[1],
        half_width = width * .5,
    }
    city_plan.alley_count += 1
}

settlement_plan_generate_village_buildings :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    rng: ^Settlement_Rng,
) -> architecture.City_Plan {
    result: architecture.City_Plan
    if plan == nil || project == nil || rng == nil do return result
    plan.village_reason = settlement_village_reason_pick(plan, project)
    program: [24]Settlement_Building_Purpose
    program_count := settlement_village_program(plan.village_reason, plan.request.seed, &program)
    anchor := plan.request.center
    density := f32(.38)
    tissue := Settlement_Tissue.Dalmatian_Planned
    if plan.neighborhood_count > 0 {
        anchor = plan.neighborhoods[0].center
        density = plan.neighborhoods[0].density
        tissue = plan.neighborhoods[0].tissue
    }
    route_origin, route_tangent, route_normal, route_width, route_shoulder, _, _, route_found :=
        settlement_nearest_route_frame(plan, anchor)
    common := anchor
    // Keep the common at the route junction. Earlier placement offset the
    // entire program to one side of one route, which made a village read as a
    // detached compound beside several otherwise empty road arms.
    resource_direction := [2]f32{route_normal[0], route_normal[1]}
    sample := f32(12)
    gradient := [2]f32 {
        terrain.sample_height(project, 0, common[0] + sample, common[1]) -
        terrain.sample_height(project, 0, common[0] - sample, common[1]),
        terrain.sample_height(project, 0, common[0], common[1] + sample) -
        terrain.sample_height(project, 0, common[0], common[1] - sample),
    }
    gradient_length := linalg.length(gradient)
    if gradient_length > .001 {
        sign := plan.village_reason == .Harbor_Fishery ? f32(-1) : f32(1)
        resource_direction = gradient / gradient_length * sign
    }
    minimum_height, maximum_height := settlement_height_band(plan.request.region, .Village)
    resource_index, inn_index := -1, -1
    route_occupancy: [SETTLEMENT_PLANNED_ROUTE_CAPACITY]int
    golden_angle := f32(2.39996323)
    aegean_form := plan.request.region == .Aegean
    if resource_direction[0] * resource_direction[0] + resource_direction[1] * resource_direction[1] < .001 {
        resource_phase := f64(plan.request.seed & 0xffff) / f64(0xffff) * math.TAU
        resource_direction = {f32(math.cos(resource_phase)), f32(math.sin(resource_phase))}
    }
    resource_center_distance := aegean_form ? f32(28) : f32(34)
    resource_center := [2]f32 {
        common[0] + resource_direction[0] * resource_center_distance,
        common[1] + resource_direction[1] * resource_center_distance,
    }
    for purpose, program_index in program[:program_count] {
        frontage, depth := settlement_village_purpose_dimensions(purpose, plan.request.region, rng)
        best_x, best_z, best_rotation, best_score := f32(0), f32(0), f32(0), f32(1e30)
        best_route_index := -1
        found := false
        // Keep enough angular retries at the outer radius to complete the
        // fixed village program after earlier buildings, groves, and road
        // arms consume the easiest sites. A smaller pool could drop a final
        // inn or storehouse for otherwise valid deterministic seeds.
        for candidate_index in 0 ..< 360 {
            phase := f32(plan.request.seed & 0xffff) / f32(0xffff) * f32(math.PI * 2)
            angle := phase + f32(program_index * 11 + candidate_index) * golden_angle
            radius_low, radius_high := f32(14), f32(34)
            switch purpose {
            case .Inn_Shop, .Workshop:
                radius_low, radius_high = 9, 19
            case .Farmstead:
                radius_low, radius_high = 22, 40
            case .Barn_Granary, .Storehouse, .Mill, .Fishery:
                radius_low, radius_high = 30, 48
            case .Dwelling:
            }
            if aegean_form {
                // Cycladic villages gather more tightly around a shared court
                // and step outward in short contour bands. Adriatic villages
                // retain the broader road-front hamlet envelope above.
                switch purpose {
                case .Inn_Shop, .Workshop:
                    radius_low, radius_high = 7, 14
                case .Farmstead:
                    radius_low, radius_high = 18, 31
                case .Barn_Granary, .Storehouse, .Mill, .Fishery:
                    radius_low, radius_high = 26, 43
                case .Dwelling:
                    // Dwellings orbit one of three small courtyard voids
                    // instead of filling a uniform ring around the road
                    // junction. The cluster center is applied below.
                    radius_low, radius_high = 4.5, 24
                }
            }
            if plan.village_reason == .Harbor_Fishery && purpose == .Dwelling {
                radius_low, radius_high =
                    aegean_form ? f32(5) : f32(8),
                    aegean_form ? f32(28) : f32(38)
            }
            if plan.village_reason == .Harbor_Fishery &&
               (purpose == .Inn_Shop || purpose == .Workshop) {
                radius_low, radius_high =
                    aegean_form ? f32(7) : f32(9),
                    aegean_form ? f32(24) : f32(27)
            }
            if plan.village_reason == .Agricultural_Terrace && purpose == .Farmstead {
                radius_low, radius_high =
                    aegean_form ? f32(18) : f32(25),
                    aegean_form ? f32(38) : f32(44)
            }
            resource_purpose :=
                purpose == .Barn_Granary || purpose == .Storehouse || purpose == .Mill || purpose == .Fishery
            if resource_purpose {
                radius_low, radius_high = aegean_form ? f32(6) : f32(7), f32(24)
            }
            amount := f32(candidate_index / 12) / 8
            radius := radius_low + (radius_high - radius_low) * clamp(amount, 0, 1)
            placement_center := resource_purpose ? resource_center : common
            if aegean_form && purpose == .Dwelling {
                cluster_index := (program_index - 2) % 3
                cluster_angle := phase + f32(cluster_index) * f32(math.TAU / 3)
                cluster_distance := f32(9)
                placement_center = {
                    common[0] + f32(math.cos(f64(cluster_angle))) * cluster_distance,
                    common[1] + f32(math.sin(f64(cluster_angle))) * cluster_distance,
                }
            }
            x := placement_center[0] + f32(math.cos(f64(angle))) * radius
            z := placement_center[1] + f32(math.sin(f64(angle))) * radius
            candidate_route_origin,
            candidate_route_tangent,
            candidate_route_normal,
            candidate_route_width,
            candidate_route_shoulder,
            candidate_route_distance,
            candidate_route_index,
            candidate_route_found := settlement_nearest_route_frame(plan, {x, z})
            if candidate_route_found && !resource_purpose && purpose != .Farmstead {
                desired_setback :=
                    candidate_route_width * .5 + candidate_route_shoulder + depth * .5 +
                    (aegean_form ? f32(1.2) : f32(1.8))
                side :=
                    (x - candidate_route_origin[0]) * candidate_route_normal[0] +
                    (z - candidate_route_origin[1]) * candidate_route_normal[1] >= 0 ? f32(1) : f32(-1)
                frontage_x := candidate_route_origin[0] + candidate_route_normal[0] * desired_setback * side
                frontage_z := candidate_route_origin[1] + candidate_route_normal[1] * desired_setback * side
                frontage_pull := aegean_form ? f32(.30) : f32(.50)
                if plan.village_reason == .Harbor_Fishery {
                    frontage_pull = aegean_form ? f32(.55) : f32(.72)
                }
                x += (frontage_x - x) * frontage_pull
                z += (frontage_z - z) * frontage_pull
                candidate_route_origin,
                candidate_route_tangent,
                candidate_route_normal,
                candidate_route_width,
                candidate_route_shoulder,
                candidate_route_distance,
                candidate_route_index,
                candidate_route_found = settlement_nearest_route_frame(plan, {x, z})
            }
            height_at_site := terrain.sample_height(project, 0, x, z)
            if height_at_site <= project.sea_level + .6 do continue
            rotation := angle + f32(math.PI * .5)
            if aegean_form && gradient_length > .001 {
                // Present long façades along the contour, producing stepped
                // court clusters rather than a miniature roadside suburb.
                rotation = f32(math.atan2(f64(-gradient[0]), f64(gradient[1])))
            } else if candidate_route_found && !resource_purpose {
                rotation = f32(math.atan2(f64(candidate_route_tangent[1]), f64(candidate_route_tangent[0])))
            } else if gradient_length > .001 {
                rotation = f32(math.atan2(f64(-gradient[0]), f64(gradient[1])))
            }
            separation := purpose == .Dwelling ? f32(2.2) : f32(3.2)
            if aegean_form do separation = purpose == .Dwelling ? f32(1.5) : f32(2.8)
            if plan.village_reason == .Harbor_Fishery && purpose == .Dwelling {
                separation = aegean_form ? f32(1.1) : f32(.75)
            }
            if resource_purpose do separation = aegean_form ? f32(2.0) : f32(2.2)
            if !settlement_structure_clear(project, &result, x, z, frontage, depth, rotation, separation) do continue
            score := radius
            if candidate_route_found {
                // Favor a legible street wall without forcing a rigid ribbon.
                // Frontage is measured from the building center, so include
                // half its depth when choosing the desired setback.
                desired_setback :=
                    candidate_route_width * .5 + candidate_route_shoulder + depth * .5 +
                    (plan.request.region == .Aegean ? f32(1.2) : f32(1.8))
                frontage_error := math.abs(candidate_route_distance - desired_setback)
                switch purpose {
                case .Inn_Shop, .Workshop:
                    score =
                        frontage_error * (aegean_form ? f32(2.2) : f32(4)) +
                        radius * (aegean_form ? f32(.48) : f32(.24))
                case .Dwelling:
                    score =
                        frontage_error * (aegean_form ? f32(1.25) : f32(2.6)) +
                        radius * (aegean_form ? f32(.68) : f32(.40))
                case .Farmstead:
                    score =
                        frontage_error * (aegean_form ? f32(.8) : f32(1.8)) +
                        radius * (aegean_form ? f32(.72) : f32(.52))
                case .Barn_Granary, .Storehouse, .Mill, .Fishery:
                }
                if !resource_purpose &&
                   candidate_route_index >= 0 &&
                   candidate_route_index < plan.route_count {
                    candidate_route := plan.routes[candidate_route_index]
                    route_length := f32(0)
                    for segment_index in 0 ..< candidate_route.geometry.count - 1 {
                        a := candidate_route.geometry.points[segment_index]
                        b := candidate_route.geometry.points[segment_index + 1]
                        dx, dz := b[0] - a[0], b[1] - a[1]
                        route_length += f32(math.sqrt(f64(dx * dx + dz * dz)))
                    }
                    if route_length >= 12 {
                        // Once one arm has a frontage, make an equally viable
                        // empty arm preferable. This distributes the civic and
                        // domestic cluster without imposing a rigid quota.
                        score += f32(route_occupancy[candidate_route_index]) *
                            (aegean_form ? f32(3.2) : f32(4.5))
                    }
                }
            }
            if resource_purpose {
                // Barns, mills, stores, and fisheries share one legible
                // working yard instead of becoming unrelated outer outliers.
                score = radius * .75
            }
            height_error := math.abs(height_at_site - terrain.sample_height(project, 0, common[0], common[1]))
            score += height_error * (aegean_form ? f32(2.4) : f32(1.4))
            if score >= best_score do continue
            best_x, best_z, best_rotation, best_score = x, z, rotation, score
            best_route_index = candidate_route_index
            found = true
        }
        if !found {
            settlement_plan_record_rejected_site(plan, common[0], common[1], frontage, depth, 0)
            continue
        }
        seed := settlement_rng_u32(rng)
        purpose_height_scale := purpose == .Barn_Granary || purpose == .Storehouse ? f32(.72) : f32(1)
        height :=
            (minimum_height +
                (maximum_height - minimum_height) * clamp(density * .62 + settlement_rng_unit(rng) * .28, 0, 1)) *
            purpose_height_scale
        height = architecture.facade_fitted_height_in_range(height, minimum_height, maximum_height)
        structure := terrain.structure_make(best_x, best_z, frontage, depth, 0, height)
        structure.kind = .Architecture
        structure.seed = seed
        structure.width, structure.depth, structure.height = frontage, depth, height
        structure.rotation = best_rotation
        structure.building = architecture.architecture_identity({
                region           = settlement_building_region(plan.request.region),
                purpose          = settlement_building_purpose(purpose),
                tissue           = settlement_architecture_tissue(tissue),
                density          = density,
                attached         = false,
                frontage         = frontage,
                depth            = depth,
                route            = purpose == .Inn_Shop ? architecture.Context_Route.Street : architecture.Context_Route.Unspecified,
                waterfront       = plan.village_reason == .Harbor_Fishery,
                purpose_explicit = true,
            }, seed)
        structure.color = architecture.architecture_color(seed, false)
        if plan.request.region == .Aegean do structure.color = {236, 232, 216, 255}
        parcel := architecture.City_Parcel {
            frontage_width = frontage,
            depth          = depth,
            density        = density,
            seed           = seed,
            attached       = false,
        }
        tangent := [2]f32{f32(math.cos(f64(best_rotation))), f32(math.sin(f64(best_rotation)))}
        normal := [2]f32{-tangent[1], tangent[0]}
        half_frontage, half_depth := frontage * .5, depth * .5
        parcel.corners = {
            {
                best_x - tangent[0] * half_frontage - normal[0] * half_depth,
                best_z - tangent[1] * half_frontage - normal[1] * half_depth,
            },
            {
                best_x + tangent[0] * half_frontage - normal[0] * half_depth,
                best_z + tangent[1] * half_frontage - normal[1] * half_depth,
            },
            {
                best_x + tangent[0] * half_frontage + normal[0] * half_depth,
                best_z + tangent[1] * half_frontage + normal[1] * half_depth,
            },
            {
                best_x - tangent[0] * half_frontage + normal[0] * half_depth,
                best_z - tangent[1] * half_frontage + normal[1] * half_depth,
            },
        }
        result.structures[result.count] = structure
        result.parcels[result.parcel_count] = parcel
        if purpose == .Inn_Shop do inn_index = result.count
        if purpose == .Fishery || purpose == .Mill || purpose == .Storehouse do resource_index = result.count
        plan.ordinary_purposes[plan.ordinary_purpose_count] = purpose
        plan.ordinary_purpose_count += 1
        if best_route_index >= 0 && best_route_index < plan.route_count && !(
            purpose == .Barn_Granary ||
            purpose == .Storehouse ||
            purpose == .Mill ||
            purpose == .Fishery
        ) {
            route_occupancy[best_route_index] += 1
        }
        result.count += 1
        result.parcel_count += 1
    }
    settlement_plan_record_built_group(plan, &result, 0, result.count, tissue)
    if route_found {
        destination := common
        if inn_index >= 0 {
            destination = {result.structures[inn_index].center_x, result.structures[inn_index].center_z}
        }
        start_offset := route_width * .5 + route_shoulder + .5
        delta := destination - route_origin
        length := linalg.length(delta)
        if length > .01 {
            start := route_origin + delta / length * start_offset
            settlement_village_add_path(&result, start, destination, 1.6)
        }
    }
    if resource_index >= 0 {
        resource := result.structures[resource_index]
        settlement_village_add_path(&result, common, {resource.center_x, resource.center_z}, 1.25)
    }
    core_half_x, core_half_z := aegean_form ? f32(6) : f32(8), aegean_form ? f32(5) : f32(6)
    settlement_plan_record_terrain_edit(
        plan,
        project,
        .Plaza,
        common[0],
        common[1],
        core_half_x,
        core_half_z,
        2.5,
    )
    if aegean_form && route_found {
        // A short, broad alley renders as the paved Cycladic court. Adriatic
        // villages retain the smoothed but grassy common as a village green.
        court_start := [2]f32 {
            common[0] - route_tangent[0] * core_half_x,
            common[1] - route_tangent[1] * core_half_x,
        }
        court_end := [2]f32 {
            common[0] + route_tangent[0] * core_half_x,
            common[1] + route_tangent[1] * core_half_x,
        }
        settlement_village_add_path(&result, court_start, court_end, core_half_z * 1.45)
    }
    return result
}

settlement_plan_generate_buildings :: proc(
    settlement: ^Settlement_Plan,
    project: ^terrain.Project,
    rng: ^Settlement_Rng,
) -> architecture.City_Plan {
    result: architecture.City_Plan
    if settlement == nil || project == nil do return result
    if settlement.request.scale == .Village {
        return settlement_plan_generate_village_buildings(settlement, project, rng)
    }
    minimum_height, maximum_height := settlement_height_band(settlement.request.region, settlement.request.scale)
    fabric := settlement.macro_cells[:settlement.macro_cell_count]
    if settlement.request.scale == .Village && settlement.neighborhood_count > 0 {
        // Macro cells remain the density/suitability field, but a village is
        // composed at neighborhood scale. Treating every occupied raster cell
        // as a parcel anchor produces a conspicuous one-building-wide string.
        fabric = settlement.neighborhoods[:settlement.neighborhood_count]
    }
    for district, district_index in fabric {
        hash := u32(district_index) * u32(0x9e3779b9) ~ settlement.request.seed
        if !settlement_fabric_cell_kept(settlement.request.scale, district.age, hash) do continue
        target := 1
        if district.density > .48 && district.age < .78 do target = 2
        if settlement.request.scale == .Town && district.density > .34 && district.age < .65 {
            target = 2
        }
        if settlement.request.scale == .City && district.density > .70 && district.age < .52 && hash & 3 != 0 {
            target = 3
        }
        if settlement.request.scale == .Village {
            // One reachable neighborhood must be sufficient to form a real
            // village; additional neighborhoods become satellite compounds,
            // not a prerequisite for meeting the minimum settlement size.
            target = 12 + int(clamp(district.density, 0, 1) * 4)
            if district.age > .72 do target = max(target - 2, 12)
        }
        district_start := result.count
        route_origin, route_tangent, route_normal, route_width, route_shoulder, route_distance, _, route_found :=
            settlement_nearest_route_frame(settlement, district.center)
        if !settlement_fabric_route_reachable(settlement.request.scale, route_distance, route_found) {
            continue
        }
        for slot in 0 ..< target * 5 {
            if result.count >= len(result.structures) || result.count - district_start >= target do break
            placement_index := result.count - district_start
            layout_index := slot
            if settlement.request.scale == .Village {
                // Retry a compact slot with several footprint samples, then
                // move past a park, landmark, or unsuitable patch instead of
                // starving the rest of the court. The upper bound prevents
                // rejected candidates from recreating a long raster ribbon.
                attempted_slot := min((slot + 2) / 3, target + 2)
                layout_index = max(placement_index, attempted_slot)
            }
            median_frontage, frontage_low, frontage_high := f32(8.5), f32(4.5), f32(16)
            depth_low, depth_high := f32(9), f32(28)
            if settlement.request.region == .Aegean {
                median_frontage, frontage_low, frontage_high = 6.5, 4, 11
                depth_low, depth_high = 5.5, 16
            } else if settlement.request.scale == .Village {
                median_frontage, frontage_low, frontage_high = 7.5, 4.5, 13
                depth_low, depth_high = 6, 18
            }
            frontage := settlement_sample_lognormal(rng, median_frontage, .24, frontage_low, frontage_high)
            ratio_mode, ratio_high := f32(1.65), f32(2.5)
            if settlement.request.region == .Aegean {
                ratio_mode, ratio_high = 1.25, 1.55
            } else if settlement.request.scale == .Village {
                ratio_mode, ratio_high = 1.35, 1.60
            }
            depth := clamp(
                frontage * settlement_sample_triangular(rng, 1.25, ratio_mode, ratio_high),
                depth_low,
                depth_high,
            )
            x, z, rotation: f32
            attached := settlement_rng_unit(rng) < settlement_attachment_probability(district.age)
            separation := settlement_building_separation(
                settlement.request.region,
                settlement.request.scale,
                district.age,
                attached,
            )
            frontage_reach :=
                settlement.request.scale == .City ? f32(30) : settlement.request.scale == .Town ? f32(24) : f32(18)
            if settlement.request.region == .Adriatic {
                frontage_reach =
                    settlement.request.scale == .City ? f32(24) : settlement.request.scale == .Town ? f32(19) : f32(16)
            }
            frontage_slots := settlement.request.scale == .Village ? 1 : 4
            use_frontage := route_found && layout_index < frontage_slots && route_distance <= frontage_reach
            if settlement.request.scale == .Village {
                // A village compound is organized around its court. The
                // pedestrian-access pass connects that court to the nearest
                // road; reserving a special frontage parcel here creates a
                // ribbon/court transition that repeatedly collides.
                use_frontage = false
            }
            if use_frontage {
                side := (layout_index + int(hash & 1)) & 1
                row := layout_index / 2
                signed_row := f32((row + 1) / 2) * (frontage + separation)
                if row & 1 == 1 do signed_row = -signed_row
                // The projected macro-cell centers otherwise line up at
                // identical stations on long routes. Drift each frontage
                // group within its own cell, without changing which street it
                // addresses.
                station_noise := f32((hash ~ u32(slot + 1) * u32(0x27d4eb2d)) & 0xffff) / f32(0xffff) - .5
                signed_row += station_noise * district.radius * .68
                side_sign := side == 0 ? f32(-1) : f32(1)
                setback_noise := f32((hash >> 12) & 255) / 255
                setback_variation := (.15 + district.age * .65) * setback_noise
                setback := route_width * .5 + route_shoulder + .8 + depth * .5 + separation * .5 + setback_variation
                x = route_origin[0] + route_tangent[0] * signed_row + route_normal[0] * setback * side_sign
                z = route_origin[1] + route_tangent[1] * signed_row + route_normal[1] * setback * side_sign
                rotation = f32(math.atan2(f64(route_tangent[1]), f64(route_tangent[0])))
            } else {
                // Distant Adriatic districts form compact courts; Aegean and
                // hillside tissue forms contour-aligned attached terraces.
                columns := min(settlement.request.region == .Aegean ? 4 : 3, target)
                row := layout_index / columns
                sample := f32(7)
                gradient_x :=
                    terrain.sample_height(project, 0, district.center[0] + sample, district.center[1]) -
                    terrain.sample_height(project, 0, district.center[0] - sample, district.center[1])
                gradient_z :=
                    terrain.sample_height(project, 0, district.center[0], district.center[1] + sample) -
                    terrain.sample_height(project, 0, district.center[0], district.center[1] - sample)
                gradient_length := linalg.length([2]f32{gradient_x, gradient_z})
                tangent := [2]f32{1, 0}
                if route_found && (settlement.request.region == .Adriatic || settlement.request.scale == .Village) {
                    tangent = route_tangent
                } else if gradient_length > .001 {
                    tangent = {-gradient_z / gradient_length, gradient_x / gradient_length}
                }
                normal := [2]f32{-tangent.y, tangent.x}
                row_count := max((target + columns - 1) / columns, 1)
                centered_row := f32(row) - f32(row_count - 1) * .5
                centered_column := f32(layout_index % columns) - f32(columns - 1) * .5
                column_pitch, row_pitch := frontage + separation, depth + separation
                if settlement.request.scale == .Village {
                    // Stable pitches are based on the largest village parcel,
                    // not the current random sample. Recomputing the grid from
                    // every candidate makes later rows collide with earlier
                    // buildings of a different size.
                    column_pitch, row_pitch = 22, 26
                }
                group_center := district.center
                if settlement.request.scale == .Village && route_found {
                    side_dot :=
                        (district.center[0] - route_origin[0]) * route_normal[0] +
                        (district.center[1] - route_origin[1]) * route_normal[1]
                    side_sign := side_dot < 0 ? f32(-1) : f32(1)
                    if math.abs(side_dot) < .01 && hash & 1 == 0 do side_sign = -1
                    court_half_depth := f32(row_count - 1) * row_pitch * .5 + 9
                    court_offset := route_width * .5 + route_shoulder + 4 + court_half_depth
                    first_center := [2]f32 {
                        route_origin[0] + route_normal[0] * court_offset * side_sign,
                        route_origin[1] + route_normal[1] * court_offset * side_sign,
                    }
                    opposite_center := [2]f32 {
                        route_origin[0] - route_normal[0] * court_offset * side_sign,
                        route_origin[1] - route_normal[1] * court_offset * side_sign,
                    }
                    first_height := terrain.sample_height(project, 0, first_center[0], first_center[1])
                    opposite_height := terrain.sample_height(project, 0, opposite_center[0], opposite_center[1])
                    if first_height <= project.sea_level + .6 || opposite_height > first_height + 1 {
                        side_sign = -side_sign
                    }
                    group_center = {
                        route_origin[0] + route_normal[0] * court_offset * side_sign,
                        route_origin[1] + route_normal[1] * court_offset * side_sign,
                    }
                }
                x =
                    group_center[0] +
                    tangent[0] * centered_column * column_pitch +
                    normal[0] * centered_row * row_pitch
                z =
                    group_center[1] +
                    tangent[1] * centered_column * column_pitch +
                    normal[1] * centered_row * row_pitch
                group_jitter_radius := district.radius
                if settlement.request.scale == .Village {
                    group_jitter_radius = min(group_jitter_radius, 22)
                }
                jitter_tangent := (f32((hash >> 8) & 255) / 255 - .5) * group_jitter_radius * .62
                jitter_normal := (f32((hash >> 16) & 255) / 255 - .5) * group_jitter_radius * .62
                slot_hash := hash ~ u32(slot + 1) * u32(0x165667b1)
                jitter_tangent += (f32(slot_hash & 255) / 255 - .5) * min(district.radius * .24, frontage * .55)
                jitter_normal += (f32((slot_hash >> 8) & 255) / 255 - .5) * min(district.radius * .18, depth * .35)
                x += tangent[0] * jitter_tangent + normal[0] * jitter_normal
                z += tangent[1] * jitter_tangent + normal[1] * jitter_normal
                rotation = f32(math.atan2(f64(tangent[1]), f64(tangent[0])))
                if settlement.request.region == .Adriatic &&
                   district.tissue != .Later_Extension &&
                   district.tissue != .Dalmatian_Planned {
                    rotation_noise :=
                        (f32((slot_hash >> 16) & 255) / 255 - .5) * (district.age < .7 ? f32(.34) : f32(.14))
                    rotation += rotation_noise
                } else if settlement.request.region == .Aegean {
                    rotation_span := f32(.34)
                    if district.tissue == .Later_Extension {
                        rotation_span = .10
                    } else if settlement.request.scale == .Village {
                        rotation_span = .18
                    }
                    rotation += (f32((slot_hash >> 16) & 255) / 255 - .5) * rotation_span
                }
            }
            if terrain.sample_height(project, 0, x, z) <= project.sea_level + .6 {
                settlement_plan_record_rejected_site(settlement, x, z, frontage, depth, rotation)
                continue
            }
            if !settlement_structure_clear(project, &result, x, z, frontage, depth, rotation, separation) {
                settlement_plan_record_rejected_site(settlement, x, z, frontage, depth, rotation)
                continue
            }
            seed := settlement_rng_u32(rng)
            density := clamp(district.density, 0, 1)
            height :=
                minimum_height +
                (maximum_height - minimum_height) * clamp(density * .78 + settlement_rng_unit(rng) * .22, 0, 1)
            height = architecture.facade_fitted_height_in_range(height, minimum_height, maximum_height)
            structure := terrain.structure_make(x, z, frontage, depth, 0, height)
            structure.kind = .Architecture
            structure.seed = seed
            structure.width = frontage
            structure.depth = depth
            structure.height = height
            structure.rotation = rotation
            identity := architecture.architecture_identity({
                    region           = settlement_building_region(settlement.request.region),
                    tissue           = settlement_architecture_tissue(district.tissue),
                    density          = density,
                    attached         = attached,
                    frontage         = frontage,
                    depth            = depth,
                    route            = route_found ? architecture.Context_Route.Street : architecture.Context_Route.Unspecified,
                    waterfront       = district.tissue == .Harbor,
                    purpose_explicit = false,
                }, seed)
            structure.building = identity
            structure.color = architecture.architecture_color(seed, false)
            if settlement.request.region == .Aegean do structure.color = {236, 232, 216, 255}
            parcel := architecture.City_Parcel {
                frontage_width = frontage,
                depth          = depth,
                density        = density,
                seed           = seed,
                attached       = attached,
            }
            half_frontage, half_depth := frontage * .5, depth * .5
            tangent := [2]f32{f32(math.cos(f64(rotation))), f32(math.sin(f64(rotation)))}
            normal := [2]f32{-tangent[1], tangent[0]}
            parcel.corners = {
                {
                    x - tangent[0] * half_frontage - normal[0] * half_depth,
                    z - tangent[1] * half_frontage - normal[1] * half_depth,
                },
                {
                    x + tangent[0] * half_frontage - normal[0] * half_depth,
                    z + tangent[1] * half_frontage - normal[1] * half_depth,
                },
                {
                    x + tangent[0] * half_frontage + normal[0] * half_depth,
                    z + tangent[1] * half_frontage + normal[1] * half_depth,
                },
                {
                    x - tangent[0] * half_frontage + normal[0] * half_depth,
                    z - tangent[1] * half_frontage + normal[1] * half_depth,
                },
            }
            result.structures[result.count] = structure
            if settlement.ordinary_purpose_count < len(settlement.ordinary_purposes) {
                switch identity.purpose {
                case .Dwelling:
                    settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Dwelling
                case .Farmstead:
                    settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Farmstead
                case .Barn_Granary:
                    settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Barn_Granary
                case .Workshop:
                    settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Workshop
                case .Inn_Shop:
                    settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Inn_Shop
                case .Mill:
                    settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Mill
                case .Fishery:
                    settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Fishery
                case .Storehouse:
                    settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Storehouse
                }
                settlement.ordinary_purpose_count += 1
            }
            result.count += 1
            result.parcels[result.parcel_count] = parcel
            result.parcel_count += 1
        }
        settlement_plan_record_built_group(
            settlement,
            &result,
            district_start,
            result.count - district_start,
            district.tissue,
        )
    }
    settlement_plan_generate_pedestrian_access(settlement, &result, rng)
    settlement_plan_generate_lamps(settlement, &result)
    return result
}

settlement_plan_record_rejected_site :: proc(plan: ^Settlement_Plan, x, z, width, depth, rotation: f32) {
    if plan == nil || plan.rejected_site_count >= len(plan.rejected_sites) do return
    structure := terrain.structure_make(x, z, width, depth, 0, .25)
    structure.width = width
    structure.depth = depth
    structure.rotation = rotation
    plan.rejected_sites[plan.rejected_site_count] = {
        structure = structure,
        kind      = .Rejected,
        tissue    = settlement_nearest_tissue(plan, x, z),
        accepted  = false,
    }
    plan.rejected_site_count += 1
}

settlement_landmark_anchor_index :: proc(plan: ^Settlement_Plan, project: ^terrain.Project, ordinal: int) -> int {
    if plan == nil || plan.neighborhood_count == 0 do return -1
    // A village has one composed core around neighborhoods[0]. Its sole
    // landmark must reinforce that same center; selecting the globally oldest
    // tissue independently can strand a church or campanile beyond the farms.
    if plan.request.scale == .Village do return 0
    best := 0
    if ordinal == 0 {
        for neighborhood, index in plan.neighborhoods[:plan.neighborhood_count] {
            if neighborhood.age < plan.neighborhoods[best].age do best = index
        }
        return best
    }
    if ordinal == 1 {
        for neighborhood, index in plan.neighborhoods[:plan.neighborhood_count] {
            if terrain.sample_height(project, 0, neighborhood.center[0], neighborhood.center[1]) <
               terrain.sample_height(
                   project,
                   0,
                   plan.neighborhoods[best].center[0],
                   plan.neighborhoods[best].center[1],
               ) {
                best = index
            }
        }
        return best
    }
    if ordinal == 2 {
        for neighborhood, index in plan.neighborhoods[:plan.neighborhood_count] {
            if terrain.sample_height(project, 0, neighborhood.center[0], neighborhood.center[1]) >
               terrain.sample_height(
                   project,
                   0,
                   plan.neighborhoods[best].center[0],
                   plan.neighborhoods[best].center[1],
               ) {
                best = index
            }
        }
        return best
    }
    return (ordinal * 13 + plan.neighborhood_count / 3) % plan.neighborhood_count
}

settlement_plan_import_city :: proc(
    plan: ^Settlement_Plan,
    city_plan: ^architecture.City_Plan,
    project: ^terrain.Project,
) {
    if plan == nil || city_plan == nil || project == nil do return
    plan.city_plan = city_plan^
    count := min(city_plan.count, city_plan.parcel_count)
    for index in 0 ..< count {
        if plan.site_count >= len(plan.sites) do break
        structure, parcel := city_plan.structures[index], city_plan.parcels[index]
        purpose := Settlement_Building_Purpose.Dwelling
        if index < plan.ordinary_purpose_count do purpose = plan.ordinary_purposes[index]
        plan.sites[plan.site_count] = {
            structure = structure,
            parcel    = parcel,
            kind      = .Ordinary,
            tissue    = settlement_nearest_tissue(plan, structure.center_x, structure.center_z),
            density   = parcel.density,
            attached  = parcel.attached,
            accepted  = true,
            purpose   = purpose,
        }
        plan.site_count += 1
    }
    for alley in city_plan.alleys[:city_plan.alley_count] {
        if plan.route_count >= len(plan.routes) do break
        geometry := Settlement_Route{}
        geometry.points[0] = {alley.start_x, alley.start_z}
        geometry.points[1] = {alley.end_x, alley.end_z}
        geometry.count = 2
        length := linalg.length([2]f32{alley.end_x - alley.start_x, alley.end_z - alley.start_z})
        start_height := terrain.sample_height(project, 0, alley.start_x, alley.start_z)
        end_height := terrain.sample_height(project, 0, alley.end_x, alley.end_z)
        grade := length > .01 ? math.abs(end_height - start_height) / length : f32(0)
        class := Settlement_Route_Class.Alley
        tissue := settlement_nearest_tissue(
            plan,
            (alley.start_x + alley.end_x) * .5,
            (alley.start_z + alley.end_z) * .5,
        )
        if grade >= .12 &&
           (tissue == .Hillside_Accretion || tissue == .Contour_Terrace || tissue == .Cycladic_Accretion) {
            class = .Stair
        } else if alley.half_width * 2 >= 1.8 {
            class = .Lane
        }
        plan.routes[plan.route_count] = {
            geometry      = geometry,
            class         = class,
            width         = alley.half_width * 2,
            pavement      = .Cobblestone,
            drivable      = false,
            average_grade = grade,
            maximum_grade = grade,
        }
        plan.route_count += 1
    }
}

settlement_plan_seat_city :: proc(
    city_plan: ^architecture.City_Plan,
    project: ^terrain.Project,
) {
    if city_plan == nil || project == nil do return
    for &structure in city_plan.structures[:city_plan.count] {
        _, foundation_high := architecture.architecture_foundation_height_range(project, structure)
        structure.base_y = foundation_high
    }
}

settlement_plan_seat_project_architecture :: proc(project: ^terrain.Project) {
    if project == nil do return
    for &structure in project.structures[:project.structure_count] {
        if structure.kind != .Architecture do continue
        _, foundation_high := architecture.architecture_foundation_height_range(project, structure)
        structure.base_y = foundation_high
    }
}

settlement_plan_record_reserved_site :: proc(
    plan: ^Settlement_Plan,
    structure: terrain.Structure,
    kind: Settlement_Site_Kind,
    landmark_kind: Settlement_Landmark_Kind = {},
) {
    if plan == nil || plan.site_count >= len(plan.sites) do return
    plan.sites[plan.site_count] = {
        structure     = structure,
        kind          = kind,
        landmark_kind = landmark_kind,
        tissue        = settlement_nearest_tissue(plan, structure.center_x, structure.center_z),
        accepted      = true,
    }
    plan.site_count += 1
}

settlement_landmark_kind :: proc(region: Settlement_Region, ordinal: int) -> Settlement_Landmark_Kind {
    adriatic := [?]Settlement_Landmark_Kind {
        .Campanile,
        .Palace_Loggia,
        .Church,
        .Harbor_Office,
        .Market_Hall,
        .Fortress_Gate,
    }
    aegean := [?]Settlement_Landmark_Kind {
        .Cycladic_Bell,
        .Church,
        .Monastery,
        .Harbor_Office,
        .Market_Hall,
        .Fortress_Gate,
    }
    if region == .Aegean do return aegean[ordinal % len(aegean)]
    return adriatic[ordinal % len(adriatic)]
}

settlement_plan_reserved_kind_count :: proc(plan: ^Settlement_Plan, kind: Settlement_Site_Kind) -> int {
    if plan == nil do return 0
    result := 0
    for site in plan.sites[:plan.site_count] {
        if site.accepted && site.kind == kind do result += 1
    }
    return result
}

settlement_cut_fill_estimate :: proc(
    sample_heights: [5]f32,
    area: f32,
) -> (
    target_height, cut_volume, fill_volume: f32,
) {
    for sample_height in sample_heights do target_height += sample_height
    target_height /= f32(len(sample_heights))
    for sample_height in sample_heights {
        delta := target_height - sample_height
        if delta > 0 {
            fill_volume += delta * area / f32(len(sample_heights))
        } else {
            cut_volume += -delta * area / f32(len(sample_heights))
        }
    }
    return
}

settlement_plan_record_terrain_edit :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    kind: Settlement_Terrain_Edit_Kind,
    x, z, half_x, half_z, feather: f32,
) {
    if plan == nil || project == nil || plan.terrain_edit_count >= len(plan.terrain_edits) do return
    samples := [5][2]f32 {
        {x, z},
        {x - half_x, z - half_z},
        {x + half_x, z - half_z},
        {x + half_x, z + half_z},
        {x - half_x, z + half_z},
    }
    sample_heights: [5]f32
    for point, index in samples {
        sample_heights[index] = terrain.sample_height(project, 0, point[0], point[1])
    }
    area := max(half_x * 2, f32(1)) * max(half_z * 2, f32(1))
    height, cut_volume, fill_volume := settlement_cut_fill_estimate(sample_heights, area)
    height = max(height, project.sea_level + .6)
    plan.terrain_edits[plan.terrain_edit_count] = {
        kind          = kind,
        center        = {x, z},
        half_extent   = {half_x, half_z},
        target_height = height,
        feather       = feather,
        cut_volume    = cut_volume,
        fill_volume   = fill_volume,
    }
    plan.terrain_edit_count += 1
    // The lab terrain is disposable. Smoothing is bounded to the recorded pad
    // and cascades through clipmap levels in the terrain package.
    if kind != .Retaining_Edge {
        terrain.apply_stroke_with_hardness(project, .Smooth, x, z, max(half_x, half_z) + feather, .72, 1, .62)
    }
}

settlement_plan_prepare_block_terrain :: proc(plan: ^Settlement_Plan, project: ^terrain.Project) {
    if plan == nil || project == nil do return
    budget := 24
    switch plan.request.scale {
    case .City:
        budget = 24
    case .Town:
        budget = 12
    case .Village:
        budget = 4
    }
    prepared := 0
    for block in plan.blocks[:plan.block_count] {
        if prepared >= budget do break
        minimum_height, maximum_height := f32(1e30), f32(-1e30)
        lowest_corner := block.center
        for corner_index in 0 ..< block.corner_count {
            corner := block.corners[corner_index]
            height := terrain.sample_height(project, 0, corner[0], corner[1])
            if height < minimum_height {
                minimum_height = height
                lowest_corner = corner
            }
            maximum_height = max(maximum_height, height)
        }
        if minimum_height <= project.sea_level + .6 || maximum_height - minimum_height < .65 {
            continue
        }
        half_x := min(block.short_side * .44, f32(14))
        half_z := min(block.long_side * .44, f32(20))
        edit_kind := Settlement_Terrain_Edit_Kind.Building_Pad
        if block.tissue == .Hillside_Accretion ||
           block.tissue == .Contour_Terrace ||
           block.tissue == .Cycladic_Accretion {
            edit_kind = .Neighborhood_Terrace
        }
        settlement_plan_record_terrain_edit(
            plan,
            project,
            edit_kind,
            block.center[0],
            block.center[1],
            half_x,
            half_z,
            4,
        )
        if maximum_height - minimum_height >= 2 && plan.terrain_edit_count < len(plan.terrain_edits) {
            settlement_plan_record_terrain_edit(
                plan,
                project,
                .Retaining_Edge,
                lowest_corner[0],
                lowest_corner[1],
                min(half_x, f32(8)),
                .5,
                0,
            )
        }
        prepared += 1
    }
}
