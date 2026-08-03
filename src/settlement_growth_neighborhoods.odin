package main

import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"

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

settlement_growth_record :: proc(
    plan: ^Settlement_Plan,
    kind: Settlement_Growth_Event_Kind,
    age: f32,
    target, route_index: int,
) {
    if plan == nil ||
       route_index < 0 ||
       route_index >= plan.route_count ||
       plan.growth_event_count >= len(plan.growth_events) {
        return
    }
    route := plan.routes[route_index].geometry
    if route.count < 2 do return
    event_index := plan.growth_event_count
    plan.growth_events[event_index] = {
        kind                = kind,
        age                 = age,
        order               = event_index,
        target_neighborhood = target,
        route_index         = route_index,
        frontage_start      = route.points[0],
        frontage_finish     = route.points[route.count - 1],
    }
    plan.growth_event_count += 1
}

settlement_growth_route_grade :: proc(project: ^terrain.Project, route: Settlement_Route) -> f32 {
    maximum: f32
    if project == nil do return 1
    for index in 0 ..< route.count - 1 {
        a, b := route.points[index], route.points[index + 1]
        distance := linalg.length(b - a)
        if distance <= .01 do continue
        grade :=
            math.abs(terrain.sample_surface_height(project, 0, b[0], b[1]) - terrain.sample_surface_height(project, 0, a[0], a[1])) /
            distance
        maximum = max(maximum, grade)
    }
    return maximum
}

settlement_growth_nearest_network_points :: proc(
    plan: ^Settlement_Plan,
    target: [2]f32,
    points: ^[16][2]f32,
    distances: ^[16]f32,
) -> int {
    if plan == nil || points == nil || distances == nil do return 0
    count := 0
    for &distance in distances do distance = f32(1e30)
    for route in plan.routes[:plan.route_count] {
        if !route.drivable do continue
        for segment_index in 0 ..< route.geometry.count - 1 {
            a, b := route.geometry.points[segment_index], route.geometry.points[segment_index + 1]
            delta := b - a
            length_squared := linalg.dot(delta, delta)
            if length_squared <= .001 do continue
            along := clamp(linalg.dot(target - a, delta) / length_squared, f32(0), f32(1))
            candidate := a + delta * along
            distance := linalg.length(target - candidate)
            duplicate := false
            for existing in points[:count] {
                if settlement_route_point_near(existing, candidate, 1) {
                    duplicate = true
                    break
                }
            }
            if duplicate do continue
            insert := count
            if count < len(points) {
                count += 1
            } else if distance >= distances[len(distances) - 1] {
                continue
            } else {
                insert = len(points) - 1
            }
            for insert > 0 && distance < distances[insert - 1] {
                if insert < len(points) {
                    points[insert] = points[insert - 1]
                    distances[insert] = distances[insert - 1]
                }
                insert -= 1
            }
            points[insert], distances[insert] = candidate, distance
        }
    }
    return count
}

settlement_growth_route_double_backs :: proc(route: Settlement_Route) -> bool {
    for index in 1 ..< route.count - 1 {
        incoming := linalg.normalize0(route.points[index] - route.points[index - 1])
        outgoing := linalg.normalize0(route.points[index + 1] - route.points[index])
        if linalg.dot(incoming, outgoing) < -.25 do return true
    }
    return false
}

settlement_growth_truncate_at_first_contact :: proc(
    plan: ^Settlement_Plan,
    route: Settlement_Route,
) -> Settlement_Route {
    if plan == nil || route.count < 2 do return route
    best_segment := route.count - 2
    best_along := f32(1)
    best_point := route.points[route.count - 1]
    found := false
    distance_before := f32(0)
    best_distance := f32(1e30)
    for segment_index in 0 ..< route.count - 1 {
        a, b := route.points[segment_index], route.points[segment_index + 1]
        segment_length := linalg.length(b - a)
        for event in plan.growth_events[:plan.growth_event_count] {
            if event.route_index < 0 || event.route_index >= plan.route_count do continue
            existing := plan.routes[event.route_index].geometry
            for existing_index in 0 ..< existing.count - 1 {
                point, along, _, intersects := settlement_route_segment_intersection(
                    a,
                    b,
                    existing.points[existing_index],
                    existing.points[existing_index + 1],
                )
                if !intersects do continue
                distance := distance_before + segment_length * clamp(along, f32(0), f32(1))
                if distance <= .5 || distance >= best_distance do continue
                best_segment, best_along, best_point = segment_index, along, point
                best_distance = distance
                found = true
            }
        }
        distance_before += segment_length
    }
    if !found do return route
    result: Settlement_Route
    for index in 0 ..= best_segment {
        result.points[result.count] = route.points[index]
        result.count += 1
    }
    if result.count < len(result.points) &&
       !settlement_route_point_near(result.points[result.count - 1], best_point, .05) {
        result.points[result.count] = best_point
        result.count += 1
    } else if result.count > 0 && best_along >= .999 {
        result.points[result.count - 1] = best_point
    }
    return result
}

settlement_growth_route_clear_of_tree :: proc(
    plan: ^Settlement_Plan,
    route: Settlement_Route,
    contact: [2]f32,
    clearance: f32,
) -> bool {
    if plan == nil || route.count < 2 do return false
    clearance_squared := clearance * clearance
    for segment_index in 0 ..< route.count - 1 {
        a, b := route.points[segment_index], route.points[segment_index + 1]
        for sample_index in 1 ..= 3 {
            point := a + (b - a) * (f32(sample_index) / 4)
            if linalg.length(point - contact) <= clearance * 1.5 do continue
            for event in plan.growth_events[:plan.growth_event_count] {
                if event.route_index < 0 || event.route_index >= plan.route_count do continue
                existing := plan.routes[event.route_index].geometry
                for existing_index in 0 ..< existing.count - 1 {
                    if settlement_point_segment_distance_squared(
                           point,
                           existing.points[existing_index],
                           existing.points[existing_index + 1],
                       ) <
                       clearance_squared {
                        return false
                    }
                }
            }
        }
    }
    return true
}

settlement_village_external_anchor :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    root: int,
) -> (
    anchor: [2]f32,
    found: bool,
) {
    if plan == nil || project == nil || root < 0 || root >= plan.neighborhood_count do return
    root_point := plan.neighborhoods[root].center
    root_height := terrain.sample_surface_height(project, 0, root_point[0], root_point[1])
    fabric_center: [2]f32
    for neighborhood in plan.neighborhoods[:plan.neighborhood_count] {
        fabric_center += neighborhood.center
    }
    fabric_center /= f32(max(plan.neighborhood_count, 1))
    outward := root_point - fabric_center
    if linalg.length(outward) <= .001 {
        outward = root_point - plan.request.center
    }
    if linalg.length(outward) <= .001 do outward = {1, 0}
    outward = linalg.normalize(outward)
    best_score := f32(-1e30)
    for ring in 0 ..< 2 {
        distance := plan.request.radius * (ring == 0 ? f32(.45) : f32(.65))
        for sample in 0 ..< 32 {
            angle := f32(sample) * f32(math.TAU / 32)
            direction := [2]f32{f32(math.cos(f64(angle))), f32(math.sin(f64(angle)))}
            candidate := root_point + direction * distance
            height := terrain.sample_surface_height(project, 0, candidate[0], candidate[1])
            if height <= project.sea_level + .6 do continue
            alignment := linalg.dot(direction, outward)
            score: f32
            switch plan.village_reason {
            case .Harbor_Fishery:
                score = -height * 8 + distance * .02
            case .Agricultural_Terrace:
                score = -math.abs(height - root_height) * 6 + distance * .02
            case .Upland_Pastoral:
                score = height * 5 + distance * .02
            case .Route_Stop:
                score = alignment * 20 + distance * .02
            }
            if score > best_score {
                anchor, best_score, found = candidate, score, true
            }
        }
    }
    return
}

settlement_plan_build_village_routes :: proc(plan: ^Settlement_Plan, project: ^terrain.Project, rng: ^Settlement_Rng) {
    if plan == nil || project == nil || rng == nil || plan.neighborhood_count < 2 do return
    root := 0
    for neighborhood, index in plan.neighborhoods[:plan.neighborhood_count] {
        if neighborhood.age < plan.neighborhoods[root].age do root = index
    }
    root_point := plan.neighborhoods[root].center
    anchor, anchor_found := settlement_village_external_anchor(plan, project, root)
    if !anchor_found do return
    backbone_class := Settlement_Route_Class.Street
    switch plan.village_reason {
    case .Harbor_Fishery:
        backbone_class = .Waterfront
    case .Upland_Pastoral:
        backbone_class = .Ridge
    case .Route_Stop, .Agricultural_Terrace:
    }
    backbone := settlement_route_find(project, anchor[0], anchor[1], root_point[0], root_point[1], backbone_class)
    if backbone.count < 2 ||
       settlement_route_crosses_sea(project, backbone) ||
       settlement_growth_route_grade(project, backbone) > settlement_route_grade_limit(backbone_class) ||
       backbone.count > 5 ||
       settlement_growth_route_double_backs(backbone) ||
       settlement_route_length(backbone) > linalg.length(anchor - root_point) * 1.35 {
        return
    }
    before := plan.route_count
    settlement_plan_add_route(plan, project, backbone, backbone_class, true, true, rng)
    if plan.route_count == before do return
    plan.routes[before].shoulder = min(plan.routes[before].shoulder, f32(.65))
    settlement_growth_record(plan, .Backbone, plan.neighborhoods[root].age, root, before)

    visited: [SETTLEMENT_NEIGHBORHOOD_CAPACITY]bool
    visited[root] = true
    for branch_index in 0 ..< 2 {
        target := -1
        for neighborhood, index in plan.neighborhoods[:plan.neighborhood_count] {
            if visited[index] || neighborhood.suitability <= .05 do continue
            if target < 0 ||
               neighborhood.age < plan.neighborhoods[target].age ||
               (neighborhood.age == plan.neighborhoods[target].age && index < target) {
                target = index
            }
        }
        if target < 0 do break
        visited[target] = true
        nodes: [8][2]f32
        degrees: [8]int
        node_count := 0
        for event in plan.growth_events[:plan.growth_event_count] {
            endpoints := [2][2]f32{event.frontage_start, event.frontage_finish}
            for endpoint in endpoints {
                node_index := -1
                for existing, existing_index in nodes[:node_count] {
                    if settlement_route_point_near(existing, endpoint, .05) {
                        node_index = existing_index
                        break
                    }
                }
                if node_index < 0 && node_count < len(nodes) {
                    node_index = node_count
                    nodes[node_count] = endpoint
                    node_count += 1
                }
                if node_index >= 0 do degrees[node_index] += 1
            }
        }
        order: [8]int
        for index in 0 ..< node_count do order[index] = index
        for index in 1 ..< node_count {
            insertion := index
            for insertion > 0 &&
                linalg.length(nodes[order[insertion]] - plan.neighborhoods[target].center) <
                    linalg.length(nodes[order[insertion - 1]] - plan.neighborhoods[target].center) {
                order[insertion], order[insertion - 1] = order[insertion - 1], order[insertion]
                insertion -= 1
            }
        }
        parent := -1
        for ordered_index in order[:node_count] {
            if degrees[ordered_index] >= 3 do continue
            if linalg.length(plan.neighborhoods[target].center - nodes[ordered_index]) <= 8 do continue
            parent = ordered_index
            break
        }
        if parent < 0 do continue
        join := nodes[parent]
        direct_distance := linalg.length(plan.neighborhoods[target].center - join)
        candidate := settlement_route_find(
            project,
            plan.neighborhoods[target].center[0],
            plan.neighborhoods[target].center[1],
            join[0],
            join[1],
            .Lane,
        )
        candidate = settlement_growth_truncate_at_first_contact(plan, candidate)
        if candidate.count < 2 do continue
        contact := candidate.points[candidate.count - 1]
        if settlement_route_crosses_sea(project, candidate) ||
           settlement_growth_route_grade(project, candidate) > settlement_route_grade_limit(.Lane) ||
           candidate.count > 5 ||
           settlement_growth_route_double_backs(candidate) ||
           settlement_route_length(candidate) > direct_distance * 1.35 ||
           !settlement_growth_route_clear_of_tree(plan, candidate, contact, 4) {
            continue
        }
        before = plan.route_count
        settlement_plan_add_route(plan, project, candidate, .Lane, false, true, rng)
        if plan.route_count == before do continue
        plan.routes[before].shoulder = min(plan.routes[before].shoulder, f32(.35))
        settlement_growth_record(plan, .Exploration, plan.neighborhoods[target].age, target, before)
    }
}

settlement_plan_build_macro_routes :: proc(plan: ^Settlement_Plan, project: ^terrain.Project, rng: ^Settlement_Rng) {
    if plan == nil || project == nil do return
    if plan.request.scale == .Village {
        settlement_plan_build_village_routes(plan, project, rng)
        return
    }
    if plan.macro_cell_count < 2 do return
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
    cross_route_junction := core_point

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
        // Compact hillside towns read more naturally as a sequence of small
        // junctions than as every important road radiating from one plaza.
        // Keep the civic space at the historic core, but let the cross-town
        // route and its sparse connector tree meet the spine a short distance
        // along it. Cities retain the stronger central convergence.
        if plan.request.scale == .Town {
            spine_direction := linalg.normalize0(plan.macro_cells[east].center - plan.macro_cells[west].center)
            offset_sign := plan.request.seed & 1 == 0 ? f32(-1) : f32(1)
            offset := min(max(radius * .06, f32(10)), f32(18))
            cross_route_junction = core_point + spine_direction * offset * offset_sign
            cross_route_junction[0], cross_route_junction[1] = settlement_fit_landscape_point(
                project,
                cross_route_junction[0],
                cross_route_junction[1],
                4,
            )
        }
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
    // at its junction guarantees graph connectivity without turning it into
    // a geometrically perfect avenue. Town junctions are slightly staggered
    // along their civic spine to avoid an oversized radial junction.
    confounding_ends := plan.request.region == .Adriatic ? [2]int{north, south} : [2]int{south, east}
    old_first := settlement_route_find(
        project,
        plan.macro_cells[confounding_ends[0]].center[0],
        plan.macro_cells[confounding_ends[0]].center[1],
        cross_route_junction[0],
        cross_route_junction[1],
        .Street,
    )
    old_second := settlement_route_find(
        project,
        cross_route_junction[0],
        cross_route_junction[1],
        plan.macro_cells[confounding_ends[1]].center[0],
        plan.macro_cells[confounding_ends[1]].center[1],
        .Street,
    )
    confounding := settlement_route_join_at_end(old_first, old_second)
    settlement_plan_add_route(plan, project, confounding, .Street, true, true, rng)

    // Treat the historic core and the strongest outer districts as PoIs.
    // Farthest-first sampling spreads those anchors across the settlement;
    // the network builder then chooses a sparse terrain-cost tree between
    // them instead of forcing every district onto a radial core spoke.
    // Towns need a legible hierarchy, not a miniature ring road. One outer
    // anchor plus the civic and old cross-town spines covers the compact
    // fabric without wrapping it in the large triangular loop that dominated
    // hillside views. Cities retain the broader four-anchor network.
    connector_count := plan.request.scale == .City ? 4 : 1
    network_pois: [8]Settlement_Road_Network_PoI
    network_pois[0] = {
        position = core_point,
        required = true,
    }
    network_poi_count := 1
    used_hubs: [4]int
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
            nearest_anchor_distance := f32(1e30)
            for poi in network_pois[:network_poi_count] {
                delta := cell.center - poi.position
                nearest_anchor_distance = min(nearest_anchor_distance, linalg.dot(delta, delta))
            }
            score := nearest_anchor_distance * (.35 + cell.density * .65)
            if score > best_score {
                hub, best_score = cell_index, score
            }
        }
        if hub < 0 do continue
        used_hubs[connector_index] = hub
        network_pois[network_poi_count] = {
            position = plan.macro_cells[hub].center,
            required = true,
        }
        network_poi_count += 1
    }
    gateways: [SETTLEMENT_ROAD_GATEWAY_CAPACITY][2]f32
    gateway_count := settlement_plan_road_gateways(plan, project, &gateways)
    for gateway in gateways[:gateway_count] {
        if network_poi_count >= len(network_pois) do break
        network_pois[network_poi_count] = {
            position = gateway,
            required = true,
        }
        network_poi_count += 1
    }
    _ = settlement_plan_connect_road_network(plan, project, network_pois[:network_poi_count], rng, .Connector)
}

settlement_plan_junction_plaza_center :: proc(plan: ^Settlement_Plan) -> (center: [2]f32, degree: int, found: bool) {
    if plan == nil do return
    topology := settlement_plan_route_topology(plan)
    best_score := f32(-1e30)
    for node, node_index in topology.nodes[:topology.node_count] {
        node_degree := 0
        for edge in topology.edges[:topology.edge_count] {
            if edge[0] == node_index || edge[1] == node_index do node_degree += 1
        }
        if node_degree <= 0 do continue
        delta := node - plan.request.center
        distance := linalg.length(delta)
        // Degree dominates: a genuine multi-way junction always beats a
        // prettier but less connected site. Proximity breaks equal-degree
        // ties so the settlement's principal square remains civic and useful.
        score := f32(node_degree) * 10000 - distance
        if score > best_score {
            center, degree, found = node, node_degree, true
            best_score = score
        }
    }
    if !found {
        center, degree, found = plan.request.center, 0, true
    }
    return
}

settlement_plan_reserve_junction_plaza :: proc(plan: ^Settlement_Plan, project: ^terrain.Project) -> bool {
    if plan == nil || project == nil do return false
    center, _, found := settlement_plan_junction_plaza_center(plan)
    if !found do return false
    half_x, half_z := f32(9), f32(7)
    switch plan.request.scale {
    case .City:
        half_x, half_z = 12, 9
    case .Town:
        // Riviera civic space is a room in the street wall, not a broad
        // cleared apron. Keep enough area for gathering and circulation while
        // allowing narrow-fronted houses to enclose it closely.
        half_x, half_z = 8, 6
    case .Village:
        half_x, half_z = 8, 6
    }
    feather := plan.request.scale == .Town ? f32(1.8) : f32(3)
    settlement_plan_record_terrain_edit(plan, project, .Plaza, center[0], center[1], half_x, half_z, feather)
    plan.program.plazas.placed += 1
    return true
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
