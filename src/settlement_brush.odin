package main

import architecture "../packages/architecture"
import roads "../packages/roads"
import ruins "../packages/ruins"
import terrain "../packages/terrain"
import "core:fmt"
import "core:math"
import "core:math/linalg"

settlement_brush_preset_span :: proc(preset: Settlement_Brush_Preset) -> f32 {
    switch preset {
    case .Small:
        return 60
    case .Medium:
        return 120
    case .Large:
        return 220
    }
    return 60
}

settlement_brush_shape_name :: proc(shape: Settlement_Brush_Shape) -> cstring {
    switch shape {
    case .Square:
        return "SQUARE"
    case .Rectangle:
        return "RECTANGLE"
    case .Circle:
        return "CIRCLE"
    case .Macaroni:
        return "MACARONI"
    }
    return "CIRCLE"
}

settlement_brush_preset_name :: proc(preset: Settlement_Brush_Preset) -> cstring {
    switch preset {
    case .Small:
        return "SMALL"
    case .Medium:
        return "MEDIUM"
    case .Large:
        return "LARGE"
    }
    return "SMALL"
}

settlement_brush_local_point :: proc(piece: Settlement_Brush_Piece, point: [2]f32) -> [2]f32 {
    delta := point - piece.center
    cosine, sine := f32(math.cos(f64(piece.rotation))), f32(math.sin(f64(piece.rotation)))
    return {delta[0] * cosine + delta[1] * sine, -delta[0] * sine + delta[1] * cosine}
}

settlement_brush_box_sdf :: proc(point, half_extent: [2]f32) -> f32 {
    outside := [2]f32 {
        max(math.abs(point[0]) - half_extent[0], f32(0)),
        max(math.abs(point[1]) - half_extent[1], f32(0)),
    }
    inside := min(max(math.abs(point[0]) - half_extent[0], math.abs(point[1]) - half_extent[1]), f32(0))
    return linalg.length(outside) + inside
}

settlement_brush_signed_distance :: proc(piece: Settlement_Brush_Piece, point: [2]f32) -> f32 {
    local := settlement_brush_local_point(piece, point)
    span := settlement_brush_preset_span(piece.preset)
    switch piece.shape {
    case .Circle:
        return linalg.length(local) - span * .5
    case .Square:
        return settlement_brush_box_sdf(local, {span * .5, span * .5})
    case .Rectangle:
        return settlement_brush_box_sdf(local, {span * .5, span * .275})
    case .Macaroni:
        thickness := span * .28
        centerline_radius := span * .5 - thickness * .5
        half_sweep := f32(math.PI / 3)
        angle := f32(math.atan2(f64(local[1]), f64(local[0])))
        clamped_angle := clamp(angle, -half_sweep, half_sweep)
        nearest := [2]f32 {
            f32(math.cos(f64(clamped_angle))) * centerline_radius,
            f32(math.sin(f64(clamped_angle))) * centerline_radius,
        }
        return linalg.length(local - nearest) - thickness * .5
    }
    return linalg.length(local) - span * .5
}

settlement_brush_weight :: proc(piece: Settlement_Brush_Piece, point: [2]f32) -> f32 {
    distance := settlement_brush_signed_distance(piece, point)
    if distance > 0 do return 0
    span := settlement_brush_preset_span(piece.preset)
    feather := max(span * .5 * (1 - clamp(piece.hardness, 0, 1)), terrain.BASE_CELL_SIZE * .25)
    if distance <= -feather do return 1
    t := clamp(-distance / feather, 0, 1)
    return t * t * (3 - 2 * t)
}

settlement_density_smooth_max :: proc(existing, contribution: f32, blend_width: f32 = .08) -> f32 {
    if blend_width <= 0 || math.abs(existing - contribution) >= blend_width {
        return max(existing, contribution)
    }
    amount := clamp(.5 + .5 * (contribution - existing) / blend_width, 0, 1)
    amount = amount * amount * (3 - 2 * amount)
    return clamp(existing * (1 - amount) + contribution * amount, 0, 1)
}

settlement_brush_piece_bounds :: proc(piece: Settlement_Brush_Piece) -> architecture.City_Bounds {
    half := settlement_brush_preset_span(piece.preset) * .5
    // Rotation can only shrink the true axis-aligned bound relative to this
    // circumscribed square, so this safely covers every supported shape.
    return {piece.center[0] - half, piece.center[1] - half, piece.center[0] + half, piece.center[1] + half, true}
}

settlement_brush_point_developable :: proc(project: ^terrain.Project, point: [2]f32, maximum_slope: f32) -> bool {
    if project == nil do return false
    height, _, found := terrain.sample_land(project, 0, point[0], point[1])
    if !found || height <= project.sea_level + .6 do return false
    cell := terrain.BASE_CELL_SIZE
    east, _, east_found := terrain.sample_land(project, 0, point[0] + cell, point[1])
    west, _, west_found := terrain.sample_land(project, 0, point[0] - cell, point[1])
    north, _, north_found := terrain.sample_land(project, 0, point[0], point[1] + cell)
    south, _, south_found := terrain.sample_land(project, 0, point[0], point[1] - cell)
    if !east_found || !west_found || !north_found || !south_found do return false
    dx, dz := east - west, north - south
    slope := f32(math.sqrt(f64(dx * dx + dz * dz))) / (cell * 2)
    if slope > maximum_slope do return false
    for structure in project.structures[:project.structure_count] {
        if structure.kind != .Architecture do continue
        delta := point - [2]f32{structure.center_x, structure.center_z}
        cosine, sine := math.cos(structure.rotation), math.sin(structure.rotation)
        local := [2]f32{delta[0] * cosine + delta[1] * sine, -delta[0] * sine + delta[1] * cosine}
        if math.abs(local[0]) <= structure.width * .5 + 1 && math.abs(local[1]) <= structure.depth * .5 + 1 {
            return false
        }
    }
    return true
}

settlement_brush_apply_piece :: proc(
    field: ^[terrain.CITY_DENSITY_SAMPLES]u8,
    project: ^terrain.Project,
    piece: Settlement_Brush_Piece,
    maximum_slope: f32,
) -> architecture.City_Bounds {
    if field == nil do return {}
    world_bounds := settlement_brush_piece_bounds(piece)
    source_piece := piece
    if project != nil {
        source_piece.center[0], source_piece.center[1] = terrain.island_source_position(
            project,
            piece.center[0],
            piece.center[1],
        )
    }
    bounds := settlement_brush_piece_bounds(source_piece)
    half_grid := f32(terrain.RING_RESOLUTION - 1) * .5
    minimum_x := clamp(
        int(math.floor(f64(bounds.min_x / terrain.BASE_CELL_SIZE + half_grid))),
        0,
        terrain.RING_RESOLUTION - 1,
    )
    maximum_x := clamp(
        int(math.ceil(f64(bounds.max_x / terrain.BASE_CELL_SIZE + half_grid))),
        0,
        terrain.RING_RESOLUTION - 1,
    )
    minimum_z := clamp(
        int(math.floor(f64(bounds.min_z / terrain.BASE_CELL_SIZE + half_grid))),
        0,
        terrain.RING_RESOLUTION - 1,
    )
    maximum_z := clamp(
        int(math.ceil(f64(bounds.max_z / terrain.BASE_CELL_SIZE + half_grid))),
        0,
        terrain.RING_RESOLUTION - 1,
    )
    for z in minimum_z ..= maximum_z {
        for x in minimum_x ..= maximum_x {
            world_x, world_z := architecture.city_density_world_position(x, z)
            point := [2]f32{world_x, world_z}
            weight := settlement_brush_weight(source_piece, point)
            if weight <= 0 do continue
            index := architecture.city_density_index(x, z)
            if piece.erased {
                value := f32(field[index]) / 255
                field[index] = u8(math.round(f64(clamp(value - piece.density * weight, 0, 1) * 255)))
                continue
            }
            develop_x, develop_z := terrain.island_world_position(project, point[0], point[1])
            if !settlement_brush_point_developable(project, {develop_x, develop_z}, maximum_slope) do continue
            existing := f32(field[index]) / 255
            contribution := clamp(piece.density, 0, 1) * weight
            blended := settlement_density_smooth_max(existing, contribution)
            field[index] = u8(math.round(f64(blended * 255)))
        }
    }
    return world_bounds
}

settlement_brush_pieces_touch :: proc(first, second: Settlement_Brush_Piece, extra: f32 = 0) -> bool {
    first_radius := settlement_brush_preset_span(first.preset) * .5
    second_radius := settlement_brush_preset_span(second.preset) * .5
    return linalg.length(first.center - second.center) <= first_radius + second_radius + extra
}

settlement_brush_assign_component :: proc(plan: ^Settlement_Plan, piece: ^Settlement_Brush_Piece) {
    if plan == nil || piece == nil do return
    connection_distance := max(f32(24), settlement_brush_preset_span(piece.preset) * .2)
    selected: u32
    for existing in plan.brush_pieces[:plan.brush_piece_count] {
        if existing.erased do continue
        if settlement_brush_pieces_touch(existing, piece^, connection_distance) {
            selected = existing.component_id
            break
        }
    }
    if selected == 0 {
        for route in plan.routes[:plan.route_count] {
            for point_index in 0 ..< route.geometry.count - 1 {
                if settlement_point_segment_distance_squared(
                       piece.center,
                       route.geometry.points[point_index],
                       route.geometry.points[point_index + 1],
                   ) <=
                   connection_distance * connection_distance {
                    if plan.next_brush_component_id == 0 do plan.next_brush_component_id = 1
                    selected = plan.next_brush_component_id
                    break
                }
            }
            if selected != 0 do break
        }
    }
    if selected == 0 {
        for site in plan.sites[:plan.site_count] {
            if !site.accepted do continue
            center := [2]f32{site.structure.center_x, site.structure.center_z}
            if linalg.length(center - piece.center) <=
               connection_distance + settlement_brush_preset_span(piece.preset) * .5 {
                if plan.next_brush_component_id == 0 do plan.next_brush_component_id = 1
                selected = plan.next_brush_component_id
                break
            }
        }
    }
    if selected == 0 {
        plan.next_brush_component_id += 1
        if plan.next_brush_component_id == 0 do plan.next_brush_component_id = 1
        selected = plan.next_brush_component_id
    }
    piece.component_id = selected
}

settlement_brush_component_density :: proc(plan: ^Settlement_Plan, component_id: u32, point: [2]f32) -> f32 {
    if plan == nil || component_id == 0 do return 0
    result: f32
    for piece in plan.brush_pieces[:plan.brush_piece_count] {
        if piece.component_id != component_id do continue
        contribution := settlement_brush_weight(piece, point) * piece.density
        if piece.erased {
            result = max(result - contribution, f32(0))
        } else {
            result = settlement_density_smooth_max(result, contribution)
        }
    }
    return clamp(result, 0, 1)
}

settlement_program_scale_minimum :: proc(scale: Settlement_Scale) -> int {
    switch scale {
    case .Village:
        return 8
    case .Town:
        return 24
    case .City:
        return 70
    }
    return 8
}

settlement_program_scale_from_target :: proc(target: int) -> Settlement_Scale {
    if target >= 70 do return .City
    if target >= 24 do return .Town
    return .Village
}

settlement_program_compile :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    component_id: u32,
) -> Settlement_Program {
    result: Settlement_Program
    if plan == nil || project == nil || component_id == 0 do return result
    cell_area := terrain.BASE_CELL_SIZE * terrain.BASE_CELL_SIZE
    density_area, density_sum: f32
    for z in 0 ..< terrain.RING_RESOLUTION {
        for x in 0 ..< terrain.RING_RESOLUTION {
            world_x, world_z := architecture.city_density_world_position(x, z)
            point := [2]f32{world_x, world_z}
            density := settlement_brush_component_density(plan, component_id, point)
            if density <= .01 || !settlement_brush_point_developable(project, point, SETTLEMENT_VILLAGE.max_slope) {
                continue
            }
            density_area += cell_area
            density_sum += density
        }
    }
    result.developable_area = density_area
    average_density := density_area > 0 ? density_sum / (density_area / cell_area) : f32(0)
    result.target_coverage = .10 + (.34 - .10) * average_density
    result.canonical_footprint = 95 + (55 - 95) * average_density
    unconstrained_target := int(
        math.round(f64(result.developable_area * result.target_coverage / max(result.canonical_footprint, f32(1)))),
    )
    scale := settlement_program_scale_from_target(unconstrained_target)
    minimum := settlement_program_scale_minimum(scale)
    target := clamp(max(unconstrained_target, minimum), minimum, SETTLEMENT_SITE_CAPACITY - 8)
    result.ordinary = {
        target  = target,
        minimum = minimum,
    }

    residential := int(math.round(f64(f32(target) * .82)))
    workshops := int(math.round(f64(f32(target) * .08)))
    commerce := int(math.round(f64(f32(target) * .05)))
    production := max(0, target - residential - workshops - commerce)
    result.purposes[int(Settlement_Building_Purpose.Dwelling)] = {
        target  = residential,
        minimum = scale == .Village ? 7 : max(1, int(math.floor(f64(f32(minimum) * .72)))),
    }
    result.purposes[int(Settlement_Building_Purpose.Workshop)] = {
        target  = workshops,
        minimum = 1,
    }
    result.purposes[int(Settlement_Building_Purpose.Inn_Shop)] = {
        target  = commerce,
        minimum = 1,
    }
    result.purposes[int(Settlement_Building_Purpose.Storehouse)] = {
        target  = production,
        minimum = scale == .Village ? 1 : 0,
    }
    landmark_target := scale == .City ? 3 : (scale == .Town ? 2 : 1)
    result.landmarks = {
        target  = landmark_target,
        minimum = landmark_target,
    }
    result.plazas = {
        target  = max(1, int(math.ceil(f64(f32(target) / 45)))),
        minimum = 1,
    }
    result.parks = {
        target  = max(1, int(math.ceil(f64(f32(target) / 35)))),
        minimum = 1,
    }
    result.vegetation = {
        target = max(1, int(math.round(f64(f32(target) * (1 - average_density) * .65)))),
    }
    result.residents.target = residential * 3
    result.residents.minimum = result.purposes[int(Settlement_Building_Purpose.Dwelling)].minimum * 2
    result.workers.target = workshops * 2 + commerce * 3 + production * 2
    plan.request.scale = scale
    plan.request.density = average_density
    return result
}

settlement_population_allocate :: proc(plan: ^Settlement_Plan, project: ^terrain.Project) {
    if plan == nil || project == nil do return
    plan.activity_point_count = 0
    plan.inhabitant_count = 0
    home_indices: [SETTLEMENT_SITE_CAPACITY]int
    home_count := 0
    work_indices: [SETTLEMENT_SITE_CAPACITY]int
    work_count := 0
    for structure, structure_index in project.structures[:project.structure_count] {
        if structure.kind != .Architecture || plan.activity_point_count >= SETTLEMENT_ACTIVITY_CAPACITY do continue
        point := settlement_structure_front_door_point(structure)
        purpose := structure.building.purpose
        activity_kind := Settlement_Activity_Kind.Home
        worker_site := false
        switch purpose {
        case .Workshop, .Inn_Shop, .Mill, .Fishery, .Storehouse, .Barn_Granary:
            activity_kind = .Work
            worker_site = true
        case .Dwelling, .Farmstead:
        }
        activity_index := plan.activity_point_count
        plan.activity_points[activity_index] = {
            position   = point,
            kind       = activity_kind,
            site_index = structure_index,
        }
        plan.activity_point_count += 1
        if worker_site {
            work_indices[work_count] = activity_index
            work_count += 1
        } else {
            home_indices[home_count] = activity_index
            home_count += 1
        }
    }
    resident_target := min(plan.program.residents.target, min(SETTLEMENT_INHABITANT_CAPACITY, max(home_count * 3, 0)))
    worker_target := min(plan.program.workers.target, resident_target)
    for inhabitant_index in 0 ..< resident_target {
        if home_count == 0 do break
        worker := inhabitant_index < worker_target && work_count > 0
        plan.inhabitants[plan.inhabitant_count] = {
            home_activity = home_indices[inhabitant_index % home_count],
            work_activity = worker ? work_indices[inhabitant_index % work_count] : -1,
            seed          = u32(inhabitant_index + 1) * 0x9e3779b9 ~ plan.request.seed,
            worker        = worker,
        }
        plan.inhabitant_count += 1
    }
    plan.program.residents.placed = plan.inhabitant_count
    plan.program.residents.reduced = max(0, plan.program.residents.target - plan.program.residents.placed)
    plan.program.workers.placed = min(worker_target, plan.inhabitant_count)
    plan.program.workers.reduced = max(0, plan.program.workers.target - plan.program.workers.placed)
}

settlement_brush_route_segment_clear :: proc(
    project: ^terrain.Project,
    start, finish: [2]f32,
    clearance: f32,
) -> bool {
    if project == nil do return false
    for structure in project.structures[:project.structure_count] {
        if structure.kind != .Architecture do continue
        if settlement_segment_intersects_structure_clearance(start, finish, structure, clearance) do return false
    }
    return true
}

settlement_brush_ensure_primary_route :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    piece: Settlement_Brush_Piece,
    owner_piece_id: u32,
) -> bool {
    if plan == nil || project == nil || piece.erased do return false
    graph := &project.road_graph
    if graph.node_count + 2 > roads.MAX_NODES || graph.edge_count >= roads.MAX_EDGES do return false
    span := settlement_brush_preset_span(piece.preset)
    tangent := [2]f32{f32(math.cos(f64(piece.rotation))), f32(math.sin(f64(piece.rotation)))}
    start := piece.center - tangent * span * .38
    finish := piece.center + tangent * span * .38
    if !settlement_brush_point_developable(project, start, SETTLEMENT_VILLAGE.max_slope) ||
       !settlement_brush_point_developable(project, finish, SETTLEMENT_VILLAGE.max_slope) ||
       !settlement_brush_route_segment_clear(project, start, finish, 3) {
        tangent = {-tangent[1], tangent[0]}
        start = piece.center - tangent * span * .38
        finish = piece.center + tangent * span * .38
    }
    if !settlement_brush_route_segment_clear(project, start, finish, 3) do return false
    connection_distance := max(f32(24), span * .2)
    nearest_node, nearest_distance := -1, connection_distance * connection_distance
    for node, node_index in graph.nodes[:graph.node_count] {
        delta := [2]f32{node.position.x, node.position.z} - start
        distance := linalg.dot(delta, delta)
        if distance < nearest_distance &&
           settlement_brush_route_segment_clear(project, {node.position.x, node.position.z}, start, 3) {
            nearest_node, nearest_distance = node_index, distance
        }
    }
    from := nearest_node
    if from < 0 {
        start_height := terrain.sample_surface_height(project, 0, start[0], start[1])
        from = roads.add_node(graph, {start[0], start_height, start[1]}, 3)
    }
    finish_height := terrain.sample_surface_height(project, 0, finish[0], finish[1])
    to := roads.add_node(graph, {finish[0], finish_height, finish[1]}, 3)
    if from < 0 || to < 0 do return false
    width := piece.preset == .Large ? f32(6) : (piece.preset == .Medium ? f32(5) : f32(4))
    if roads.add_straight_edge(graph, from, to, width, .8, .Cobblestone) < 0 do return false
    if plan.route_count < len(plan.routes) {
        geometry: Settlement_Route
        geometry.points[0] = {graph.nodes[from].position.x, graph.nodes[from].position.z}
        geometry.points[1] = finish
        geometry.count = 2
        plan.routes[plan.route_count] = {
            geometry = geometry,
            class    = .Street,
            width    = width,
            shoulder = .8,
            pavement = .Cobblestone,
            required = true,
            drivable = true,
        }
        plan.route_piece_ids[plan.route_count] = owner_piece_id
        plan.route_count += 1
    }
    return true
}

settlement_program_assign_new_purposes :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    component_id, owner_piece_id: u32,
) {
    if plan == nil || project == nil || owner_piece_id == 0 do return
    existing: [8]int
    new_sites: [SETTLEMENT_SITE_CAPACITY]int
    new_count := 0
    for site, site_index in plan.sites[:plan.site_count] {
        if !site.accepted || site.kind != .Ordinary do continue
        owner := plan.site_piece_ids[site_index]
        owner_component := u32(0)
        if owner > 0 && int(owner) <= plan.brush_piece_count {
            owner_component = plan.brush_pieces[int(owner) - 1].component_id
        } else if settlement_brush_component_density(
               plan,
               component_id,
               {site.structure.center_x, site.structure.center_z},
           ) >
           .01 {
            owner_component = component_id
        }
        if owner_component != component_id do continue
        if owner == owner_piece_id {
            new_sites[new_count] = site_index
            new_count += 1
        } else {
            existing[int(site.purpose)] += 1
        }
    }
    if new_count == 0 do return
    assigned: [8]int
    remaining := new_count
    constrained := [3]Settlement_Building_Purpose{.Workshop, .Inn_Shop, .Storehouse}
    for purpose in constrained {
        target := plan.program.purposes[int(purpose)]
        needed_minimum := max(0, target.minimum - existing[int(purpose)])
        assigned[int(purpose)] = min(needed_minimum, remaining)
        remaining -= assigned[int(purpose)]
    }
    dwelling := Settlement_Building_Purpose.Dwelling
    dwelling_minimum := max(0, plan.program.purposes[int(dwelling)].minimum - existing[int(dwelling)])
    assigned[int(dwelling)] = min(dwelling_minimum, remaining)
    remaining -= assigned[int(dwelling)]
    for purpose in constrained {
        desired := max(0, plan.program.purposes[int(purpose)].target - existing[int(purpose)] - assigned[int(purpose)])
        addition := min(desired, remaining)
        assigned[int(purpose)] += addition
        remaining -= addition
    }
    assigned[int(dwelling)] += remaining
    cursor := 0
    order := [4]Settlement_Building_Purpose{.Workshop, .Inn_Shop, .Storehouse, .Dwelling}
    for purpose in order {
        for _ in 0 ..< assigned[int(purpose)] {
            if cursor >= new_count do break
            site_index := new_sites[cursor]
            site := &plan.sites[site_index]
            site.purpose = purpose
            identity := architecture.architecture_identity(
                {
                    region = settlement_building_region(plan.request.region),
                    tissue = settlement_architecture_tissue(site.tissue),
                    density = site.density,
                    attached = site.attached,
                    frontage = site.structure.width,
                    depth = site.structure.depth,
                    purpose = settlement_building_purpose(purpose),
                    purpose_explicit = true,
                },
                site.structure.seed,
            )
            site.structure.building = identity
            for &structure in project.structures[:project.structure_count] {
                if structure.kind != .Architecture ||
                   structure.seed != site.structure.seed ||
                   math.abs(structure.center_x - site.structure.center_x) > .01 ||
                   math.abs(structure.center_z - site.structure.center_z) > .01 {
                    continue
                }
                structure.building = identity
                break
            }
            cursor += 1
        }
    }
}

settlement_program_report :: proc(plan: ^Settlement_Plan) -> string {
    if plan == nil do return ""
    program := &plan.program
    return fmt.tprintf(
        "component pieces %d | area %.0fm2 density %.2f coverage %.1f%% | buildings %d/%d min %d reduced %d | residents %d/%d workers %d/%d | vegetation %d/%d | essential %s",
        plan.brush_piece_count,
        program.developable_area,
        plan.request.density,
        program.target_coverage * 100,
        program.ordinary.placed,
        program.ordinary.target,
        program.ordinary.minimum,
        program.ordinary.reduced,
        program.residents.placed,
        program.residents.target,
        program.workers.placed,
        program.workers.target,
        program.vegetation.placed,
        program.vegetation.target,
        program.infeasible_essential ? "INFEASIBLE" : "OK",
    )
}

settlement_program_measure_placed :: proc(plan: ^Settlement_Plan, project: ^terrain.Project, component_id: u32) {
    if plan == nil || project == nil do return
    plan.program.ordinary.placed = 0
    for &count in plan.program.purposes do count.placed = 0
    for structure in project.structures[:project.structure_count] {
        if structure.kind != .Architecture ||
           settlement_brush_component_density(plan, component_id, {structure.center_x, structure.center_z}) <= .01 {
            continue
        }
        plan.program.ordinary.placed += 1
        purpose := Settlement_Building_Purpose(structure.building.purpose)
        if int(purpose) >= 0 && int(purpose) < len(plan.program.purposes) {
            plan.program.purposes[int(purpose)].placed += 1
        }
    }
    plan.program.ordinary.reduced = max(0, plan.program.ordinary.target - plan.program.ordinary.placed)
    for &count in plan.program.purposes {
        count.reduced = max(0, count.target - count.placed)
        if count.placed < count.minimum do plan.program.infeasible_essential = true
    }
    if plan.program.ordinary.placed < plan.program.ordinary.minimum {
        plan.program.infeasible_essential = true
    }
}

settlement_brush_generate_vegetation :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    piece: Settlement_Brush_Piece,
) {
    if plan == nil || project == nil || piece.erased do return
    target := min(plan.program.vegetation.target, 24)
    if target <= 0 do return
    span := settlement_brush_preset_span(piece.preset)
    spacing := max(f32(9), span / max(f32(math.sqrt(f64(target * 2))), f32(1)))
    empty_city: architecture.City_Plan
    placed := 0
    grid := max(2, int(math.ceil(f64(span / spacing))))
    for gz in 0 ..< grid {
        for gx in 0 ..< grid {
            if placed >= target do break
            seed := piece.seed ~ u32(gx * 0x9e37 + gz * 0x85eb)
            jitter_x := (f32(seed & 255) / 255 - .5) * spacing * .55
            jitter_z := (f32((seed >> 8) & 255) / 255 - .5) * spacing * .55
            local := [2]f32 {
                -span * .5 + (f32(gx) + .5) * span / f32(grid) + jitter_x,
                -span * .5 + (f32(gz) + .5) * span / f32(grid) + jitter_z,
            }
            cosine, sine := math.cos(piece.rotation), math.sin(piece.rotation)
            point := piece.center + [2]f32{local[0] * cosine - local[1] * sine, local[0] * sine + local[1] * cosine}
            if settlement_brush_weight(piece, point) < .45 ||
               !settlement_brush_point_developable(project, point, SETTLEMENT_VILLAGE.max_slope) {
                continue
            }
            activity_clear := true
            for activity in plan.activity_points[:plan.activity_point_count] {
                if linalg.length(activity.position - point) < 4 {
                    activity_clear = false
                    break
                }
            }
            if !activity_clear do continue
            width := 3.2 + f32((seed >> 16) & 255) / 255 * 3.8
            depth := width * (.72 + f32((seed >> 24) & 255) / 255 * .35)
            if !settlement_structure_clear(project, &empty_city, point[0], point[1], width, depth, 0, 1.5) {
                continue
            }
            foliage := terrain.structure_make(point[0], point[1], width, depth, 0, 5 + width * .65)
            foliage.kind = .Foliage
            foliage.seed = seed
            foliage.rotation = f32(seed & 255) / 255 * math.PI
            foliage.base_y = terrain.sample_surface_height(project, 0, point[0], point[1])
            if terrain.add_structure(project, foliage) >= 0 do placed += 1
        }
        if placed >= target do break
    }
    plan.program.vegetation.placed += placed
    plan.program.vegetation.reduced = max(0, plan.program.vegetation.target - plan.program.vegetation.placed)
}

settlement_brush_component_reserved_count :: proc(
    plan: ^Settlement_Plan,
    component_id: u32,
    kind: Settlement_Site_Kind,
) -> int {
    if plan == nil do return 0
    result := 0
    for site in plan.sites[:plan.site_count] {
        if !site.accepted || site.kind != kind do continue
        if settlement_brush_component_density(plan, component_id, {site.structure.center_x, site.structure.center_z}) >
           .01 {
            result += 1
        }
    }
    return result
}

settlement_brush_ensure_anchors :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    piece: Settlement_Brush_Piece,
) {
    if plan == nil || project == nil || piece.erased do return
    empty_city: architecture.City_Plan
    if settlement_brush_component_reserved_count(plan, piece.component_id, .Ruin) == 0 {
        span := settlement_brush_preset_span(piece.preset)
        tangent := [2]f32{math.cos(piece.rotation), math.sin(piece.rotation)}
        point := piece.center - tangent * span * .34
        mode := piece.preset == .Small ? ruins.Mode.Ruin : .Complex
        _ = settlement_ruin_try_place(plan, project, point, piece.seed ~ 0x5255494e, mode)
    }
    landmark_count := settlement_brush_component_reserved_count(plan, piece.component_id, .Landmark)
    for ordinal in landmark_count ..< plan.program.landmarks.minimum {
        placed := false
        span := settlement_brush_preset_span(piece.preset)
        for attempt in 0 ..< 16 {
            angle := piece.rotation + f32(attempt) * math.PI * .25
            distance := attempt == 0 ? f32(0) : span * (.14 + f32(attempt / 8) * .12)
            point := piece.center + [2]f32{math.cos(angle), math.sin(angle)} * distance
            width := plan.request.scale == .City ? f32(12) : (plan.request.scale == .Town ? f32(9) : f32(7))
            depth := width * .86
            if settlement_brush_weight(piece, point) < .4 ||
               !settlement_brush_point_developable(project, point, SETTLEMENT_VILLAGE.max_slope) ||
               !settlement_structure_clear(project, &empty_city, point[0], point[1], width, depth, angle, 2) {
                continue
            }
            landmark_kind := settlement_landmark_kind(plan.request.region, ordinal)
            height := plan.request.scale == .City ? f32(30) : (plan.request.scale == .Town ? f32(20) : f32(14))
            structure := terrain.structure_make(point[0], point[1], width, depth, 0, height)
            structure.kind = .Architecture
            structure.rotation = angle
            structure.seed = settlement_landmark_seed(plan.request.region, ordinal, piece.seed)
            structure.building = architecture.architecture_identity(
                {
                    region = settlement_building_region(plan.request.region),
                    landmark_kind = settlement_building_landmark(landmark_kind),
                    purpose_explicit = true,
                },
                structure.seed,
            )
            structure.color = architecture.architecture_color(structure.seed, false)
            _, foundation_high := architecture.architecture_foundation_height_range(project, structure)
            structure.base_y = foundation_high
            if terrain.add_structure(project, structure) < 0 do break
            settlement_plan_record_reserved_site(plan, structure, .Landmark, landmark_kind)
            settlement_plan_record_terrain_edit(
                plan,
                project,
                .Plaza,
                point[0],
                point[1],
                width * .85,
                depth * .75,
                2.5,
            )
            placed = true
            break
        }
        if !placed {
            plan.program.infeasible_essential = true
            break
        }
    }
    if settlement_brush_component_reserved_count(plan, piece.component_id, .Park) == 0 {
        span := settlement_brush_preset_span(piece.preset)
        normal := [2]f32{-math.sin(piece.rotation), math.cos(piece.rotation)}
        point := piece.center + normal * span * .28
        width := min(span * .14, f32(16))
        if settlement_brush_weight(piece, point) > .35 &&
           settlement_brush_point_developable(project, point, SETTLEMENT_VILLAGE.max_slope) &&
           settlement_structure_clear(project, &empty_city, point[0], point[1], width, width * .8, 0, 2) {
            park := terrain.structure_make(point[0], point[1], width, width * .8, 0, width * .9)
            park.kind = .Foliage
            park.seed = piece.seed ~ 0x74a5b3c1
            park.base_y = terrain.sample_surface_height(project, 0, point[0], point[1])
            if terrain.add_structure(project, park) >= 0 {
                settlement_plan_record_reserved_site(plan, park, .Park)
                plan.program.parks.placed += 1
            }
        }
    }
}
