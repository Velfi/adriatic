package main

import architecture "../packages/architecture"
import buildings "../packages/buildings"
import fountains "../packages/fountains"
import hero "../packages/hero_buildings"
import roads "../packages/roads"
import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"

SETTLEMENT_ROAD_OVERLAP_REJECT :: f32(0.7)
SETTLEMENT_ROAD_OVERLAP_WIDEN :: f32(0.1)
SETTLEMENT_ROAD_AREA_SAMPLES_ACROSS :: 5
SETTLEMENT_ACCESS_STAIR_GRADE :: f32(.12)
SETTLEMENT_ACCESS_SEVERE_GRADE :: f32(.18)
SETTLEMENT_MUNICIPAL_LIGHT_MIN_SPACING :: f32(16)

settlement_point_segment_distance_squared :: proc(point, a, b: [2]f32) -> f32 {
    segment := b - a
    length_squared := linalg.dot(segment, segment)
    if length_squared <= .000001 do return linalg.dot(point - a, point - a)
    along := clamp(linalg.dot(point - a, segment) / length_squared, f32(0), f32(1))
    offset := point - (a + segment * along)
    return linalg.dot(offset, offset)
}

Settlement_Access_Curve :: struct {
    points: [4][2]f32,
}

settlement_access_alley_endpoint_tangent :: proc(
    city_plan: ^architecture.City_Plan,
    alley_index, endpoint_index: int,
) -> [2]f32 {
    alley := city_plan.alleys[alley_index]
    start := [2]f32{alley.start_x, alley.start_z}
    finish := [2]f32{alley.end_x, alley.end_z}
    point, opposite := start, finish
    terminal := alley.start_terminal
    if endpoint_index == 1 {
        point, opposite = finish, start
        terminal = alley.end_terminal
    }
    fallback := linalg.normalize0(finish - start)
    if terminal != .None do return fallback
    neighbor: [2]f32
    neighbor_found := false
    // At a multi-way footpath junction, continue through the incident arm
    // most nearly opposite this alley. This preserves a soft dominant
    // through-line while the remaining arm curves into it as a branch.
    best_alignment := f32(-1e30)
    for candidate, candidate_index in city_plan.alleys[:city_plan.alley_count] {
        if candidate_index == alley_index do continue
        candidate_start := [2]f32{candidate.start_x, candidate.start_z}
        candidate_finish := [2]f32{candidate.end_x, candidate.end_z}
        candidate_neighbor: [2]f32
        connected := false
        if settlement_alley_point_near(point, candidate_start) {
            if candidate.start_terminal != .None do return fallback
            candidate_neighbor = candidate_finish
            connected = true
        } else if settlement_alley_point_near(point, candidate_finish) {
            if candidate.end_terminal != .None do return fallback
            candidate_neighbor = candidate_start
            connected = true
        }
        if connected {
            candidate_tangent := linalg.normalize0(opposite - candidate_neighbor)
            if endpoint_index == 1 do candidate_tangent = -candidate_tangent
            alignment := linalg.dot(candidate_tangent, fallback)
            if alignment > best_alignment {
                neighbor = candidate_neighbor
                neighbor_found = true
                best_alignment = alignment
            }
        }
    }
    if !neighbor_found do return fallback
    tangent := fallback
    if endpoint_index == 0 {
        tangent = linalg.normalize0(opposite - neighbor)
    } else {
        tangent = linalg.normalize0(neighbor - opposite)
    }
    if linalg.dot(tangent, fallback) < 0 do tangent = -tangent
    if linalg.dot(tangent, tangent) <= .0001 do return fallback
    return tangent
}

settlement_access_alley_curve_raw :: proc(
    city_plan: ^architecture.City_Plan,
    alley_index: int,
) -> Settlement_Access_Curve {
    result: Settlement_Access_Curve
    if city_plan == nil || alley_index < 0 || alley_index >= city_plan.alley_count do return result
    alley := city_plan.alleys[alley_index]
    result.points[0] = {alley.start_x, alley.start_z}
    result.points[3] = {alley.end_x, alley.end_z}
    length := linalg.length(result.points[3] - result.points[0])
    handle_length := min(length / 3, f32(4))
    start_tangent := settlement_access_alley_endpoint_tangent(city_plan, alley_index, 0)
    end_tangent := settlement_access_alley_endpoint_tangent(city_plan, alley_index, 1)
    result.points[1] = result.points[0] + start_tangent * handle_length
    result.points[2] = result.points[3] - end_tangent * handle_length
    return result
}

settlement_access_curve_point :: proc(curve: Settlement_Access_Curve, amount: f32) -> [2]f32 {
    point := roads.bezier_point(
        {curve.points[0][0], 0, curve.points[0][1]},
        {curve.points[1][0], 0, curve.points[1][1]},
        {curve.points[2][0], 0, curve.points[2][1]},
        {curve.points[3][0], 0, curve.points[3][1]},
        amount,
    )
    return {point.x, point.z}
}

settlement_access_curve_sample_count :: proc(curve: Settlement_Access_Curve) -> int {
    chord_length := linalg.length(curve.points[3] - curve.points[0])
    return clamp(int(math.ceil(f64(chord_length / 2))), 2, 12)
}

settlement_access_curve_length :: proc(curve: Settlement_Access_Curve) -> f32 {
    result: f32
    previous := curve.points[0]
    sample_count := settlement_access_curve_sample_count(curve)
    for sample in 1 ..= sample_count {
        current := settlement_access_curve_point(curve, f32(sample) / f32(sample_count))
        result += linalg.length(current - previous)
        previous = current
    }
    return result
}

settlement_access_alley_curve :: proc(
    city_plan: ^architecture.City_Plan,
    alley_index: int,
) -> Settlement_Access_Curve {
    curve: Settlement_Access_Curve
    if city_plan == nil || alley_index < 0 || alley_index >= city_plan.alley_count do return curve
    alley := city_plan.alleys[alley_index]
    if alley.curve_ready {
        curve.points[0] = {alley.start_x, alley.start_z}
        curve.points[1] = alley.curve_control_from
        curve.points[2] = alley.curve_control_to
        curve.points[3] = {alley.end_x, alley.end_z}
        return curve
    }
    curve = settlement_access_alley_curve_raw(city_plan, alley_index)
    ignore_structure := -1
    terminals := [2]architecture.City_Alley_Terminal{alley.start_terminal, alley.end_terminal}
    endpoints := [2][2]f32{curve.points[0], curve.points[3]}
    for terminal, endpoint_index in terminals {
        if terminal != .Door do continue
        for structure, structure_index in city_plan.structures[:city_plan.count] {
            if settlement_alley_point_near(
                endpoints[endpoint_index],
                settlement_structure_front_door_point(structure),
            ) {
                ignore_structure = structure_index
                break
            }
        }
    }
    previous := curve.points[0]
    sample_count := settlement_access_curve_sample_count(curve)
    for sample in 1 ..= sample_count {
        current := settlement_access_curve_point(curve, f32(sample) / f32(sample_count))
        unsafe := !settlement_access_segment_clear(
            city_plan,
            previous,
            current,
            alley.half_width + .25,
            ignore_structure,
        )
        if !unsafe {
            for other, other_index in city_plan.alleys[:city_plan.alley_count] {
                if other_index == alley_index do continue
                other_start := [2]f32{other.start_x, other.start_z}
                other_finish := [2]f32{other.end_x, other.end_z}
                intersection, curve_along, other_along, found := settlement_route_segment_intersection(
                    previous,
                    current,
                    other_start,
                    other_finish,
                )
                if !found do continue
                shared_endpoint :=
                    (settlement_alley_point_near(intersection, curve.points[0]) ||
                        settlement_alley_point_near(intersection, curve.points[3])) &&
                    (settlement_alley_point_near(intersection, other_start) ||
                            settlement_alley_point_near(intersection, other_finish))
                if shared_endpoint do continue
                if (curve_along > .0001 && curve_along < .9999) || (other_along > .0001 && other_along < .9999) {
                    unsafe = true
                    break
                }
            }
        }
        if unsafe {
            delta := curve.points[3] - curve.points[0]
            curve.points[1] = curve.points[0] + delta / 3
            curve.points[2] = curve.points[0] + delta * (f32(2) / 3)
            break
        }
        previous = current
    }
    return curve
}

settlement_access_alley_length :: proc(city_plan: ^architecture.City_Plan, alley_index: int) -> f32 {
    if city_plan == nil || alley_index < 0 || alley_index >= city_plan.alley_count do return 0
    return settlement_access_curve_length(settlement_access_alley_curve(city_plan, alley_index))
}

settlement_access_alley_width_clear :: proc(
    city_plan: ^architecture.City_Plan,
    alley_index: int,
    half_width: f32,
) -> bool {
    if city_plan == nil || alley_index < 0 || alley_index >= city_plan.alley_count do return false
    alley := city_plan.alleys[alley_index]
    curve := settlement_access_alley_curve(city_plan, alley_index)
    ignore_structure := -1
    terminals := [2]architecture.City_Alley_Terminal{alley.start_terminal, alley.end_terminal}
    endpoints := [2][2]f32{curve.points[0], curve.points[3]}
    for terminal, endpoint_index in terminals {
        if terminal != .Door do continue
        for structure, structure_index in city_plan.structures[:city_plan.count] {
            if settlement_alley_point_near(
                endpoints[endpoint_index],
                settlement_structure_front_door_point(structure),
            ) {
                ignore_structure = structure_index
                break
            }
        }
    }
    previous := curve.points[0]
    sample_count := settlement_access_curve_sample_count(curve)
    for sample in 1 ..= sample_count {
        current := settlement_access_curve_point(curve, f32(sample) / f32(sample_count))
        if !settlement_access_segment_clear(city_plan, previous, current, half_width, ignore_structure) {
            return false
        }
        previous = current
    }
    return true
}

settlement_access_finalize_curves :: proc(city_plan: ^architecture.City_Plan) {
    if city_plan == nil do return
    for &alley in city_plan.alleys[:city_plan.alley_count] do alley.curve_ready = false
    for alley_index in 0 ..< city_plan.alley_count {
        curve := settlement_access_alley_curve(city_plan, alley_index)
        city_plan.alleys[alley_index].curve_control_from = curve.points[1]
        city_plan.alleys[alley_index].curve_control_to = curve.points[2]
        city_plan.alleys[alley_index].curve_ready = true
    }
}

settlement_access_point_on_road_apron :: proc(alley: architecture.City_Alley, point: [2]f32, margin: f32) -> bool {
    start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
    segment := finish - start
    length := linalg.length(segment)
    apron_run, outer_width, valid := settlement_access_road_apron(alley, length)
    if !valid || length <= .001 do return false
    terminals := [2]architecture.City_Alley_Terminal{alley.start_terminal, alley.end_terminal}
    endpoints := [2][2]f32{start, finish}
    for terminal, endpoint_index in terminals {
        if terminal != .Road do continue
        inward := segment / length
        if endpoint_index == 1 do inward = -inward
        offset := point - endpoints[endpoint_index]
        along := linalg.dot(offset, inward)
        if along < 0 || along > apron_run do continue
        normal := [2]f32{-inward[1], inward[0]}
        across := math.abs(linalg.dot(offset, normal))
        amount := along / apron_run
        half_width := (outer_width * (1 - amount) + alley.half_width * 2 * amount) * .5
        if across <= half_width + margin do return true
    }
    return false
}

settlement_access_point_on_alley_surface :: proc(
    city_plan: ^architecture.City_Plan,
    point: [2]f32,
    margin: f32 = .18,
) -> bool {
    if city_plan == nil do return false
    for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
        clearance := alley.half_width + margin
        curve := settlement_access_alley_curve(city_plan, alley_index)
        previous := curve.points[0]
        sample_count := settlement_access_curve_sample_count(curve)
        for sample in 1 ..= sample_count {
            current := settlement_access_curve_point(curve, f32(sample) / f32(sample_count))
            if settlement_point_segment_distance_squared(point, previous, current) <= clearance * clearance {
                return true
            }
            previous = current
        }
        if settlement_access_point_on_road_apron(alley, point, margin) do return true
        endpoints := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
        terminals := [2]architecture.City_Alley_Terminal{alley.start_terminal, alley.end_terminal}
        for endpoint, endpoint_index in endpoints {
            if terminals[endpoint_index] != .Public_Space do continue
            public_clearance := max(alley.half_width, f32(.9)) + margin
            delta := point - endpoint
            if linalg.dot(delta, delta) <= public_clearance * public_clearance do return true
        }
    }
    return false
}

settlement_access_segment_intersects_box :: proc(start, finish: [2]f32, half_width, half_depth: f32) -> bool {
    delta := finish - start
    minimum, maximum := f32(0), f32(1)
    starts := [2]f32{start[0], start[1]}
    deltas := [2]f32{delta[0], delta[1]}
    extents := [2]f32{half_width, half_depth}
    for axis in 0 ..< 2 {
        if math.abs(deltas[axis]) <= .000001 {
            if math.abs(starts[axis]) > extents[axis] do return false
            continue
        }
        first := (-extents[axis] - starts[axis]) / deltas[axis]
        second := (extents[axis] - starts[axis]) / deltas[axis]
        if first > second do first, second = second, first
        minimum = max(minimum, first)
        maximum = min(maximum, second)
        if minimum > maximum do return false
    }
    return true
}

settlement_access_structure_overlaps_alley :: proc(
    city_plan: ^architecture.City_Plan,
    structure: terrain.Structure,
    margin: f32 = .25,
) -> bool {
    if city_plan == nil do return false
    cosine, sine := math.cos(structure.rotation), math.sin(structure.rotation)
    for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
        clearance := alley.half_width + margin
        curve := settlement_access_alley_curve_raw(city_plan, alley_index)
        sample_count := 1
        if alley.curve_ready {
            curve.points[1] = alley.curve_control_from
            curve.points[2] = alley.curve_control_to
            sample_count = settlement_access_curve_sample_count(curve)
        } else {
            delta := curve.points[3] - curve.points[0]
            curve.points[1] = curve.points[0] + delta / 3
            curve.points[2] = curve.points[0] + delta * (f32(2) / 3)
        }
        previous := curve.points[0] - [2]f32{structure.center_x, structure.center_z}
        previous_local := [2]f32{previous[0] * cosine + previous[1] * sine, -previous[0] * sine + previous[1] * cosine}
        for sample in 1 ..= sample_count {
            world :=
                settlement_access_curve_point(curve, f32(sample) / f32(sample_count)) -
                [2]f32{structure.center_x, structure.center_z}
            local := [2]f32{world[0] * cosine + world[1] * sine, -world[0] * sine + world[1] * cosine}
            if settlement_access_segment_intersects_box(
                previous_local,
                local,
                structure.width * .5 + clearance,
                structure.depth * .5 + clearance,
            ) {
                return true
            }
            previous_local = local
        }
        endpoints := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
        terminals := [2]architecture.City_Alley_Terminal{alley.start_terminal, alley.end_terminal}
        for endpoint, endpoint_index in endpoints {
            switch terminals[endpoint_index] {
            case .Public_Space:
                offset := endpoint - [2]f32{structure.center_x, structure.center_z}
                local := [2]f32{offset[0] * cosine + offset[1] * sine, -offset[0] * sine + offset[1] * cosine}
                public_margin := max(alley.half_width, f32(.9)) + margin
                if math.abs(local[0]) <= structure.width * .5 + public_margin &&
                   math.abs(local[1]) <= structure.depth * .5 + public_margin {
                    return true
                }
            case .Road:
                alley_start, alley_finish := endpoints[0], endpoints[1]
                direction := alley_finish - alley_start
                length := linalg.length(direction)
                apron_run, outer_width, valid := settlement_access_road_apron(alley, length)
                if !valid || length <= .001 do continue
                inward := direction / length
                if endpoint_index == 1 do inward = -inward
                apron_finish := endpoint + inward * apron_run
                apron_world := [2][2]f32 {
                    endpoint - [2]f32{structure.center_x, structure.center_z},
                    apron_finish - [2]f32{structure.center_x, structure.center_z},
                }
                apron_local: [2][2]f32
                for point, point_index in apron_world {
                    apron_local[point_index] = {
                        point[0] * cosine + point[1] * sine,
                        -point[0] * sine + point[1] * cosine,
                    }
                }
                apron_clearance := outer_width * .5 + margin
                if settlement_access_segment_intersects_box(
                    apron_local[0],
                    apron_local[1],
                    structure.width * .5 + apron_clearance,
                    structure.depth * .5 + apron_clearance,
                ) {
                    return true
                }
            case .None, .Door:
            }
        }
    }
    return false
}

settlement_route_contains_paved_point :: proc(route: Settlement_Planned_Route, point: [2]f32) -> bool {
    half_width := route.width * .5
    for index in 0 ..< route.geometry.count - 1 {
        if settlement_point_segment_distance_squared(
               point,
               route.geometry.points[index],
               route.geometry.points[index + 1],
           ) <=
           half_width * half_width {
            return true
        }
    }
    return false
}

// Estimate overlap by sampling uniformly over each candidate segment's paved
// rectangle. Segment samples are length-weighted, so this is an area fraction
// rather than merely a count of coincident centerline points.
settlement_route_overlap_badness :: proc(
    plan: ^Settlement_Plan,
    geometry: Settlement_Route,
    width: f32,
    coverage_by_route: ^[SETTLEMENT_PLANNED_ROUTE_CAPACITY]f32 = nil,
) -> f32 {
    if plan == nil || geometry.count < 2 || width <= 0 do return 0
    samples, covered := 0, 0
    route_hits: [SETTLEMENT_PLANNED_ROUTE_CAPACITY]int
    for segment_index in 0 ..< geometry.count - 1 {
        a, b := geometry.points[segment_index], geometry.points[segment_index + 1]
        delta := b - a
        length := linalg.length(delta)
        if length <= .01 do continue
        tangent := delta / length
        normal := [2]f32{-tangent[1], tangent[0]}
        along_samples := max(int(math.ceil(f64(length / max(width * .5, f32(1))))), 2)
        for along_index in 0 ..< along_samples {
            along := (f32(along_index) + .5) / f32(along_samples)
            for across_index in 0 ..< SETTLEMENT_ROAD_AREA_SAMPLES_ACROSS {
                across := (f32(across_index) + .5) / f32(SETTLEMENT_ROAD_AREA_SAMPLES_ACROSS) - .5
                point := a + delta * along + normal * (across * width)
                sample_covered := false
                for existing, route_index in plan.routes[:plan.route_count] {
                    if !existing.drivable || !settlement_route_contains_paved_point(existing, point) do continue
                    route_hits[route_index] += 1
                    sample_covered = true
                }
                if sample_covered do covered += 1
                samples += 1
            }
        }
    }
    if samples <= 0 do return 0
    if coverage_by_route != nil {
        for route_index in 0 ..< plan.route_count {
            coverage_by_route[route_index] = f32(route_hits[route_index]) / f32(samples)
        }
    }
    return f32(covered) / f32(samples)
}

settlement_plan_add_route :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    geometry: Settlement_Route,
    class: Settlement_Route_Class,
    required, drivable: bool,
    rng: ^Settlement_Rng,
) {
    if plan == nil || geometry.count < 2 || plan.route_count >= len(plan.routes) do return
    width := settlement_route_width_sample_for_scale(rng, class, plan.request.scale)
    if drivable && plan.route_count > 0 {
        coverage_by_route: [SETTLEMENT_PLANNED_ROUTE_CAPACITY]f32
        badness := settlement_route_overlap_badness(plan, geometry, width, &coverage_by_route)
        plan.road_badness_sum += badness
        plan.road_badness_count += 1
        if badness >= SETTLEMENT_ROAD_OVERLAP_REJECT {
            for &existing, route_index in plan.routes[:plan.route_count] {
                if coverage_by_route[route_index] < SETTLEMENT_ROAD_OVERLAP_WIDEN do continue
                existing.width = max(existing.width, width)
                existing.shoulder = max(existing.shoulder, drivable ? f32(.8) : f32(.15))
                existing.required = existing.required || required
            }
            return
        }
    }
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
        pavement      = class == .Stair ? roads.Pavement.Steps : roads.Pavement.Cobblestone,
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
            // Leave room for the generated island's airport, lighthouse, post
            // office, and clinic connectors. Optional alleys must not starve
            // campaign-critical POIs from the shared road graph.
            if !required && project.road_graph.node_count + route.geometry.count > roads.MAX_NODES - 24 do continue
            settlement_route_commit(
                project,
                route.geometry,
                route.width,
                route.shoulder,
                route.pavement,
                settlement_route_use_intensity(route.class),
            )
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
            math.abs(terrain.sample_height(project, 0, b[0], b[1]) - terrain.sample_height(project, 0, a[0], a[1])) /
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
    root_height := terrain.sample_height(project, 0, root_point[0], root_point[1])
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
            height := terrain.sample_height(project, 0, candidate[0], candidate[1])
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
            x, z, width, depth, rotation,
            airport_x, airport_z, 42, 42, 0,
            airport_clearance,
        ) {
            return false
        }
    }
    for structure in project.structures[:project.structure_count] {
        if !airport_structure_is_stamp(structure) do continue
        if !settlement_oriented_rectangles_clear(
            x, z, width, depth, rotation,
            structure.center_x, structure.center_z, 42, 42, structure.rotation,
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
            if terrain.sample_height(project, 0, point[0], point[1]) <= project.sea_level + clearance ||
               terrain.active_waterway_at(project, 0, point[0], point[1]) {
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

settlement_stoop_road_clearance :: proc(
    project: ^terrain.Project,
    start, finish: [2]f32,
    half_width: f32,
) -> f32 {
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
    straight_clearance := settlement_stoop_road_clearance(
        project,
        wall,
        straight_foot,
        door_width * .5 + .20,
    )
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
        (structure.entrance_side == .Front || structure.entrance_side == .Rear ? structure.width : structure.depth) * .13,
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
    return threshold + outward * (.90 - clearance) +
           tangent * turn_sign * (door_width * .5 + f32(step_count) * .42 + .20)
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
settlement_access_consolidate_parallel_twigs :: proc(city_plan: ^architecture.City_Plan) {
    if city_plan == nil do return
    for _ in 0 ..< SETTLEMENT_ROUTE_CAPACITY {
        consolidated := false
        for first, first_index in city_plan.alleys[:city_plan.alley_count] {
            first_points := [2][2]f32{{first.start_x, first.start_z}, {first.end_x, first.end_z}}
            first_terminals := [2]architecture.City_Alley_Terminal{first.start_terminal, first.end_terminal}
            for second in city_plan.alleys[first_index + 1:city_plan.alley_count] {
                second_points := [2][2]f32{{second.start_x, second.start_z}, {second.end_x, second.end_z}}
                second_terminals := [2]architecture.City_Alley_Terminal{second.start_terminal, second.end_terminal}
                for first_common_index in 0 ..< 2 {
                    for second_common_index in 0 ..< 2 {
                        if !settlement_alley_point_near(
                            first_points[first_common_index],
                            second_points[second_common_index],
                        ) {
                            continue
                        }
                        first_other_index, second_other_index := 1 - first_common_index, 1 - second_common_index
                        if first_terminals[first_other_index] != .None ||
                           second_terminals[second_other_index] != .None {
                            continue
                        }
                        first_direction := first_points[first_other_index] - first_points[first_common_index]
                        second_direction := second_points[second_other_index] - second_points[second_common_index]
                        first_length, second_length := linalg.length(first_direction), linalg.length(second_direction)
                        if first_length <= .5 || second_length <= .5 do continue
                        if linalg.dot(first_direction, second_direction) / (first_length * second_length) < .996 {
                            continue
                        }
                        first_other, second_other := first_points[first_other_index], second_points[second_other_index]
                        if linalg.length(first_other - second_other) > .5 do continue
                        merged := (first_other + second_other) * .5
                        for &alley in city_plan.alleys[:city_plan.alley_count] {
                            start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
                            if settlement_alley_point_near(start, first_other) ||
                               settlement_alley_point_near(start, second_other) {
                                alley.start_x, alley.start_z = merged[0], merged[1]
                            }
                            if settlement_alley_point_near(finish, first_other) ||
                               settlement_alley_point_near(finish, second_other) {
                                alley.end_x, alley.end_z = merged[0], merged[1]
                            }
                        }
                        consolidated = true
                        break
                    }
                    if consolidated do break
                }
                if consolidated do break
            }
            if consolidated do break
        }
        if !consolidated do break
        settlement_access_deduplicate_segments(city_plan)
    }
}

// When two branches leave the same anonymous T on almost the same bearing,
// give them a short shared stem before they divide. This is the built form a
// mason would choose, and avoids the doubled-paving wedge produced by two
// near-parallel spline caps at one node.
settlement_access_stem_shallow_forks :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan,
) -> int {
    if plan == nil || project == nil || city_plan == nil do return 0
    stemmed := 0
    for _ in 0 ..< 8 {
        changed := false
        seen := make([dynamic][2]f32, context.temp_allocator)
        for alley in city_plan.alleys[:city_plan.alley_count] {
            points := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
            for point in points {
                duplicate := false
                for existing in seen {
                    if settlement_alley_point_near(existing, point) {
                        duplicate = true
                        break
                    }
                }
                if duplicate do continue
                append(&seen, point)
                if settlement_access_network_degree(city_plan, point) != 3 ||
                   !settlement_access_junction_location_valid(plan, city_plan, point) {
                    continue
                }
                incident_indices: [3]int
                others: [3][2]f32
                directions: [3][2]f32
                lengths: [3]f32
                incident_count := 0
                protected := false
                for candidate, candidate_index in city_plan.alleys[:city_plan.alley_count] {
                    start, finish := [2]f32{candidate.start_x, candidate.start_z}, [2]f32{candidate.end_x, candidate.end_z}
                    other: [2]f32
                    at_terminal := architecture.City_Alley_Terminal.None
                    if settlement_alley_point_near(point, start) {
                        other, at_terminal = finish, candidate.start_terminal
                    } else if settlement_alley_point_near(point, finish) {
                        other, at_terminal = start, candidate.end_terminal
                    } else {
                        continue
                    }
                    protected = protected || at_terminal != .None
                    if incident_count < 3 {
                        incident_indices[incident_count] = candidate_index
                        others[incident_count] = other
                        lengths[incident_count] = linalg.length(other - point)
                        if lengths[incident_count] > .001 {
                            directions[incident_count] = (other - point) / lengths[incident_count]
                        }
                    }
                    incident_count += 1
                }
                if protected || incident_count != 3 do continue
                pair_a, pair_b := -1, -1
                best_alignment := f32(.966)
                for first in 0 ..< 3 {
                    for second in first + 1 ..< 3 {
                        alignment := linalg.dot(directions[first], directions[second])
                        if alignment > best_alignment {
                            best_alignment = alignment
                            pair_a, pair_b = first, second
                        }
                    }
                }
                if pair_a < 0 do continue
                stem_direction := linalg.normalize(directions[pair_a] + directions[pair_b])
                maximum_stem := min(f32(3), min(lengths[pair_a], lengths[pair_b]) * .45)
                if maximum_stem < .65 do continue
                merge := point + stem_direction * .65
                for candidate_length := f32(.65); candidate_length <= maximum_stem + .001; candidate_length += .25 {
                    candidate_merge := point + stem_direction * candidate_length
                    first_direction := linalg.normalize(others[pair_a] - candidate_merge)
                    second_direction := linalg.normalize(others[pair_b] - candidate_merge)
                    merge = candidate_merge
                    if linalg.dot(first_direction, second_direction) <= .94 do break
                }
                if linalg.dot(
                    linalg.normalize(others[pair_a] - merge),
                    linalg.normalize(others[pair_b] - merge),
                ) > .966 {
                    continue
                }
                original_count := city_plan.alley_count
                originals := make([]architecture.City_Alley, original_count, context.temp_allocator)
                copy(originals, city_plan.alleys[:original_count])
                connected_before := settlement_access_count_road_connected_doors(plan, city_plan, project)
                baseline := plan^
                settlement_plan_measure_access_topology(&baseline, city_plan, project)
                width := f32(0)
                demand := u16(0)
                pair_indices := [2]int{pair_a, pair_b}
                for pair_index in pair_indices {
                    incident := &city_plan.alleys[incident_indices[pair_index]]
                    width = max(width, incident.half_width)
                    demand = max(demand, incident.household_demand)
                    if settlement_alley_point_near(point, {incident.start_x, incident.start_z}) {
                        incident.start_x, incident.start_z = merge[0], merge[1]
                    } else {
                        incident.end_x, incident.end_z = merge[0], merge[1]
                    }
                }
                append(&city_plan.alleys, architecture.City_Alley {
                    start_x = point[0],
                    start_z = point[1],
                    end_x = merge[0],
                    end_z = merge[1],
                    half_width = width,
                    household_demand = demand,
                })
                city_plan.alley_count += 1
                candidate := plan^
                settlement_plan_measure_access_topology(&candidate, city_plan, project)
                worsened :=
                    settlement_access_count_road_connected_doors(plan, city_plan, project) < connected_before ||
                    candidate.access_max_degree > 4 ||
                    candidate.access_crossings > baseline.access_crossings ||
                    candidate.access_unsplit_junctions > baseline.access_unsplit_junctions ||
                    candidate.access_shallow_junctions >= baseline.access_shallow_junctions ||
                    candidate.access_hairpin_bends > baseline.access_hairpin_bends ||
                    candidate.access_bad_door_approaches > baseline.access_bad_door_approaches
                if worsened {
                    resize(&city_plan.alleys, original_count)
                    copy(city_plan.alleys[:original_count], originals)
                    city_plan.alley_count = original_count
                    continue
                }
                stemmed += 1
                changed = true
                break
            }
            if changed do break
        }
        if !changed do break
    }
    return stemmed
}

settlement_access_remove_degenerate_segments :: proc(city_plan: ^architecture.City_Plan) {
    if city_plan == nil do return
    index := 0
    for index < city_plan.alley_count {
        alley := city_plan.alleys[index]
        start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
        if linalg.length(finish - start) >= .1 {
            index += 1
            continue
        }
        city_plan.alley_count -= 1
        city_plan.alleys[index] = city_plan.alleys[city_plan.alley_count]
        resize(&city_plan.alleys, city_plan.alley_count)
    }
}

// Collapse degree-two cusps after the access network has been assembled.
// These arise when two independently relaxed routes approach nearly the same
// corridor, miss one another, and are later endpoint-snapped into a tiny
// doubling-back turn. Replacing the two legs with their clear chord preserves
// connectivity while producing the continuous pedestrian line a builder
// would actually lay out.
settlement_access_simplify_hairpin_bends :: proc(plan: ^Settlement_Plan, city_plan: ^architecture.City_Plan) {
    if plan == nil || city_plan == nil do return
    for _ in 0 ..< SETTLEMENT_ROUTE_CAPACITY {
        simplified := false
        for alley in city_plan.alleys[:city_plan.alley_count] {
            candidates := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
            for point in candidates {
                // Doorstep and verge throats deliberately reserve their
                // endpoint heading. Public-space labels may move along the
                // same continuous surface when a redundant bend is chorded.
                if !settlement_access_junction_location_valid(plan, city_plan, point) do continue
                segment_indices: [2]int
                other_points: [2][2]f32
                other_terminals: [2]architecture.City_Alley_Terminal
                incident_count := 0
                protected_terminal := false
                for candidate, candidate_index in city_plan.alleys[:city_plan.alley_count] {
                    start := [2]f32{candidate.start_x, candidate.start_z}
                    finish := [2]f32{candidate.end_x, candidate.end_z}
                    other: [2]f32
                    other_terminal := architecture.City_Alley_Terminal.None
                    if settlement_alley_point_near(point, start) {
                        other = finish
                        other_terminal = candidate.end_terminal
                        protected_terminal =
                            protected_terminal ||
                            candidate.start_terminal == .Door ||
                            candidate.start_terminal == .Road
                    } else if settlement_alley_point_near(point, finish) {
                        other = start
                        other_terminal = candidate.start_terminal
                        protected_terminal =
                            protected_terminal || candidate.end_terminal == .Door || candidate.end_terminal == .Road
                    } else {
                        continue
                    }
                    if incident_count < 2 {
                        segment_indices[incident_count] = candidate_index
                        other_points[incident_count] = other
                        other_terminals[incident_count] = other_terminal
                    }
                    incident_count += 1
                }
                if protected_terminal do continue
                if incident_count != 2 do continue
                first_direction, second_direction := other_points[0] - point, other_points[1] - point
                first_length, second_length := linalg.length(first_direction), linalg.length(second_direction)
                if first_length <= .001 || second_length <= .001 do continue
                alignment := linalg.dot(first_direction, second_direction) / (first_length * second_length)
                if alignment <= .5 do continue
                if !settlement_access_segment_clear(city_plan, other_points[0], other_points[1], .2, -1) {
                    continue
                }
                keep_index, remove_index := segment_indices[0], segment_indices[1]
                keep_start, keep_finish := other_points[0], other_points[1]
                keep_start_terminal, keep_finish_terminal := other_terminals[0], other_terminals[1]
                if keep_index > remove_index {
                    keep_index, remove_index = remove_index, keep_index
                    keep_start, keep_finish = keep_finish, keep_start
                    keep_start_terminal, keep_finish_terminal = keep_finish_terminal, keep_start_terminal
                }
                replacement := city_plan.alleys[keep_index]
                replacement.start_x, replacement.start_z = keep_start[0], keep_start[1]
                replacement.end_x, replacement.end_z = keep_finish[0], keep_finish[1]
                replacement.start_terminal = keep_start_terminal
                replacement.end_terminal = keep_finish_terminal
                replacement.half_width = max(replacement.half_width, city_plan.alleys[remove_index].half_width)
                city_plan.alleys[keep_index] = replacement
                city_plan.alley_count -= 1
                city_plan.alleys[remove_index] = city_plan.alleys[city_plan.alley_count]
                resize(&city_plan.alleys, city_plan.alley_count)
                simplified = true
                break
            }
            if simplified do break
        }
        if !simplified do break
    }
}

// Two anonymous graph nodes separated by less than a walking pace render as
// overlapping spline caps or a useless paving sliver. Where their combined
// node stays four-way or simpler, replace the pair with one surveyed point.
// This includes degree-two nodes introduced by intersection splitting as well
// as adjacent T-junctions. Doors and road throats never move.
settlement_access_collapse_short_junction_links :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan,
) -> int {
    if plan == nil || project == nil || city_plan == nil do return 0
    collapsed_count := 0
    for _ in 0 ..< 8 {
        collapsed := false
        for candidate, candidate_index in city_plan.alleys[:city_plan.alley_count] {
            if candidate.start_terminal != .None || candidate.end_terminal != .None do continue
            start, finish := [2]f32{candidate.start_x, candidate.start_z}, [2]f32{candidate.end_x, candidate.end_z}
            length := linalg.length(finish - start)
            if length < .1 || length > 1.25 do continue
            start_degree := settlement_access_network_degree(city_plan, start)
            finish_degree := settlement_access_network_degree(city_plan, finish)
            if start_degree < 2 || finish_degree < 2 || start_degree + finish_degree - 2 > 4 do continue
            midpoint := (start + finish) * .5
            if !settlement_access_junction_location_valid(plan, city_plan, midpoint) do continue

            geometry_clear := true
            for incident, incident_index in city_plan.alleys[:city_plan.alley_count] {
                if incident_index == candidate_index do continue
                incident_start := [2]f32{incident.start_x, incident.start_z}
                incident_finish := [2]f32{incident.end_x, incident.end_z}
                other: [2]f32
                ignore_structure := -1
                if settlement_alley_point_near(incident_start, start) ||
                   settlement_alley_point_near(incident_start, finish) {
                    other = incident_finish
                    if incident.end_terminal == .Door {
                        for structure, structure_index in city_plan.structures[:city_plan.count] {
                            if settlement_alley_point_near(other, settlement_structure_front_door_point(structure)) {
                                ignore_structure = structure_index
                                break
                            }
                        }
                    }
                } else if settlement_alley_point_near(incident_finish, start) ||
                   settlement_alley_point_near(incident_finish, finish) {
                    other = incident_start
                    if incident.start_terminal == .Door {
                        for structure, structure_index in city_plan.structures[:city_plan.count] {
                            if settlement_alley_point_near(other, settlement_structure_front_door_point(structure)) {
                                ignore_structure = structure_index
                                break
                            }
                        }
                    }
                } else {
                    continue
                }
                old_grade := min(
                    settlement_access_segment_max_grade(project, other, start),
                    settlement_access_segment_max_grade(project, other, finish),
                )
                new_grade := settlement_access_segment_max_grade(project, other, midpoint)
                if new_grade > old_grade + .02 ||
                   !settlement_access_segment_clear(
                           city_plan,
                           other,
                           midpoint,
                           incident.half_width + .1,
                           ignore_structure,
                       ) {
                    geometry_clear = false
                    break
                }
            }
            if !geometry_clear do continue

            original_count := city_plan.alley_count
            originals := make([]architecture.City_Alley, original_count, context.temp_allocator)
            copy(originals, city_plan.alleys[:original_count])
            connected_before := settlement_access_count_road_connected_doors(plan, city_plan, project)
            baseline := plan^
            settlement_plan_measure_access_topology(&baseline, city_plan, project)
            for &alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
                if alley_index == candidate_index do continue
                if settlement_alley_point_near({alley.start_x, alley.start_z}, start) ||
                   settlement_alley_point_near({alley.start_x, alley.start_z}, finish) {
                    alley.start_x, alley.start_z = midpoint[0], midpoint[1]
                }
                if settlement_alley_point_near({alley.end_x, alley.end_z}, start) ||
                   settlement_alley_point_near({alley.end_x, alley.end_z}, finish) {
                    alley.end_x, alley.end_z = midpoint[0], midpoint[1]
                }
            }
            city_plan.alley_count -= 1
            city_plan.alleys[candidate_index] = city_plan.alleys[city_plan.alley_count]
            resize(&city_plan.alleys, city_plan.alley_count)
            settlement_access_deduplicate_segments(city_plan)
            candidate_metrics := plan^
            settlement_plan_measure_access_topology(&candidate_metrics, city_plan, project)
            worsened :=
                settlement_access_count_road_connected_doors(plan, city_plan, project) < connected_before ||
                candidate_metrics.access_max_degree > 4 ||
                candidate_metrics.access_crossings > baseline.access_crossings ||
                candidate_metrics.access_unsplit_junctions > baseline.access_unsplit_junctions ||
                candidate_metrics.access_shallow_junctions > baseline.access_shallow_junctions ||
                candidate_metrics.access_bad_door_approaches > baseline.access_bad_door_approaches ||
                candidate_metrics.access_bad_road_approaches > baseline.access_bad_road_approaches
            if worsened {
                resize(&city_plan.alleys, original_count)
                copy(city_plan.alleys[:original_count], originals)
                city_plan.alley_count = original_count
                continue
            }
            collapsed, collapsed_count = true, collapsed_count + 1
            break
        }
        if !collapsed do break
    }
    return collapsed_count
}

// Relax the assembled network after independently routed door paths have been
// merged. Only anonymous degree-two nodes may move: doorsteps, road throats,
// court thresholds, and actual junctions retain their authored position.
// Every accepted move must shorten the centerline without increasing grade,
// crossing a structure, losing a road-connected door, or worsening any
// measured topology defect.
settlement_access_relax_degree_two_nodes :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan,
) -> int {
    if plan == nil || project == nil || city_plan == nil do return 0
    moved_count := 0
    for _ in 0 ..< 8 {
        moved_this_iteration := false
        seen := make([dynamic][2]f32, context.temp_allocator)
        for alley in city_plan.alleys[:city_plan.alley_count] {
            endpoints := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
            for point in endpoints {
                duplicate := false
                for existing in seen {
                    if settlement_alley_point_near(existing, point) {
                        duplicate = true
                        break
                    }
                }
                if duplicate do continue
                append(&seen, point)

                incident_indices: [2]int
                neighbors: [2][2]f32
                incident_count := 0
                protected := false
                for candidate, candidate_index in city_plan.alleys[:city_plan.alley_count] {
                    start := [2]f32{candidate.start_x, candidate.start_z}
                    finish := [2]f32{candidate.end_x, candidate.end_z}
                    neighbor: [2]f32
                    terminal := architecture.City_Alley_Terminal.None
                    if settlement_alley_point_near(point, start) {
                        neighbor, terminal = finish, candidate.start_terminal
                    } else if settlement_alley_point_near(point, finish) {
                        neighbor, terminal = start, candidate.end_terminal
                    } else {
                        continue
                    }
                    protected = protected || terminal != .None
                    if incident_count < 2 {
                        incident_indices[incident_count] = candidate_index
                        neighbors[incident_count] = neighbor
                    }
                    incident_count += 1
                }
                if protected || incident_count != 2 do continue

                midpoint := (neighbors[0] + neighbors[1]) * .5
                relaxed := point * .65 + midpoint * .35
                if !settlement_access_junction_location_valid(plan, city_plan, relaxed) do continue
                old_length := linalg.length(neighbors[0] - point) + linalg.length(neighbors[1] - point)
                new_length := linalg.length(neighbors[0] - relaxed) + linalg.length(neighbors[1] - relaxed)
                if new_length >= old_length - .02 ||
                   linalg.length(neighbors[0] - relaxed) < .1 ||
                   linalg.length(neighbors[1] - relaxed) < .1 {
                    continue
                }
                old_grade := max(
                    settlement_access_segment_max_grade(project, neighbors[0], point),
                    settlement_access_segment_max_grade(project, point, neighbors[1]),
                )
                new_grade := max(
                    settlement_access_segment_max_grade(project, neighbors[0], relaxed),
                    settlement_access_segment_max_grade(project, relaxed, neighbors[1]),
                )
                if new_grade > old_grade + .01 ||
                   !settlement_access_segment_clear(city_plan, neighbors[0], relaxed, .2, -1) ||
                   !settlement_access_segment_clear(city_plan, relaxed, neighbors[1], .2, -1) {
                    continue
                }

                baseline := plan^
                settlement_plan_measure_access_topology(&baseline, city_plan)
                connected_before := settlement_access_count_road_connected_doors(plan, city_plan)
                originals := [2]architecture.City_Alley {
                    city_plan.alleys[incident_indices[0]],
                    city_plan.alleys[incident_indices[1]],
                }
                for incident_index in incident_indices {
                    segment := &city_plan.alleys[incident_index]
                    if settlement_alley_point_near(point, {segment.start_x, segment.start_z}) {
                        segment.start_x, segment.start_z = relaxed[0], relaxed[1]
                    } else {
                        segment.end_x, segment.end_z = relaxed[0], relaxed[1]
                    }
                }
                candidate_metrics := plan^
                settlement_plan_measure_access_topology(&candidate_metrics, city_plan)
                connected_after := settlement_access_count_road_connected_doors(plan, city_plan)
                worsened :=
                    connected_after < connected_before ||
                    candidate_metrics.access_crossings > baseline.access_crossings ||
                    candidate_metrics.access_unsplit_junctions > baseline.access_unsplit_junctions ||
                    candidate_metrics.access_shallow_junctions > baseline.access_shallow_junctions ||
                    candidate_metrics.access_hairpin_bends > baseline.access_hairpin_bends ||
                    candidate_metrics.access_bad_door_approaches > baseline.access_bad_door_approaches ||
                    candidate_metrics.access_bad_road_approaches > baseline.access_bad_road_approaches
                if worsened {
                    city_plan.alleys[incident_indices[0]] = originals[0]
                    city_plan.alleys[incident_indices[1]] = originals[1]
                    continue
                }
                moved_count += 1
                moved_this_iteration = true
            }
        }
        if !moved_this_iteration do break
    }
    return moved_count
}

// Seed alleys are optional block circulation laid before doorway demand is
// known. Remove the shorter of two branches that leave the same junction
// within fifteen degrees; required doorway access is generated afterward.
settlement_access_prune_shallow_seed_branches :: proc(city_plan: ^architecture.City_Plan) {
    if city_plan == nil do return
    for _ in 0 ..< SETTLEMENT_PLANNED_ROUTE_CAPACITY {
        removed := false
        for alley in city_plan.alleys[:city_plan.alley_count] {
            endpoints := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
            for point in endpoints {
                directions: [16][2]f32
                lengths: [16]f32
                indices: [16]int
                incident_count := 0
                for candidate, candidate_index in city_plan.alleys[:city_plan.alley_count] {
                    start := [2]f32{candidate.start_x, candidate.start_z}
                    finish := [2]f32{candidate.end_x, candidate.end_z}
                    direction: [2]f32
                    if settlement_alley_point_near(point, start) {
                        direction = finish - point
                    } else if settlement_alley_point_near(point, finish) {
                        direction = start - point
                    } else {
                        continue
                    }
                    length := linalg.length(direction)
                    if length <= .001 || incident_count >= len(directions) do continue
                    directions[incident_count] = direction / length
                    lengths[incident_count] = length
                    indices[incident_count] = candidate_index
                    incident_count += 1
                }
                remove_index := -1
                for first_index in 0 ..< incident_count {
                    for second_index in first_index + 1 ..< incident_count {
                        if linalg.dot(directions[first_index], directions[second_index]) <= .966 do continue
                        first_alley := city_plan.alleys[indices[first_index]]
                        second_alley := city_plan.alleys[indices[second_index]]
                        first_protected := first_alley.start_terminal != .None || first_alley.end_terminal != .None
                        second_protected := second_alley.start_terminal != .None || second_alley.end_terminal != .None
                        // Door thresholds, road throats, and authored public
                        // edges are demanded network, not optional seed
                        // circulation. Never discard one merely because it
                        // leaves a junction close to another protected edge.
                        if first_protected && second_protected do continue
                        if first_protected {
                            remove_index = indices[second_index]
                        } else if second_protected {
                            remove_index = indices[first_index]
                        } else {
                            remove_index = indices[second_index]
                            if lengths[first_index] <= lengths[second_index] {
                                remove_index = indices[first_index]
                            }
                        }
                        break
                    }
                    if remove_index >= 0 do break
                }
                if remove_index < 0 do continue
                city_plan.alley_count -= 1
                city_plan.alleys[remove_index] = city_plan.alleys[city_plan.alley_count]
                resize(&city_plan.alleys, city_plan.alley_count)
                removed = true
                break
            }
            if removed do break
        }
        if !removed do break
    }
}

// Access repair can reintroduce one of the optional near-parallel seed arms.
// Remove it only when the finished graph proves that it is redundant: every
// door remains road-connected and the measured topology strictly improves.
settlement_access_prune_redundant_shallow_branches :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan,
) -> int {
    if plan == nil || project == nil || city_plan == nil do return 0
    removed_count := 0
    for _ in 0 ..< 8 {
        baseline := plan^
        settlement_plan_measure_access_topology(&baseline, city_plan, project)
        if baseline.access_shallow_junctions == 0 do break
        connected_before := settlement_access_count_road_connected_doors(plan, city_plan, project)
        accepted := false
        seen := make([dynamic][2]f32, context.temp_allocator)
        for alley in city_plan.alleys[:city_plan.alley_count] {
            alley_points := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
            for point in alley_points {
                duplicate := false
                for existing in seen {
                    if settlement_alley_point_near(existing, point) {
                        duplicate = true
                        break
                    }
                }
                if duplicate do continue
                append(&seen, point)
                indices: [8]int
                directions: [8][2]f32
                incident_count := 0
                for candidate, candidate_index in city_plan.alleys[:city_plan.alley_count] {
                    start, finish := [2]f32{candidate.start_x, candidate.start_z}, [2]f32{candidate.end_x, candidate.end_z}
                    direction: [2]f32
                    if settlement_alley_point_near(point, start) {
                        if candidate.start_terminal != .None || candidate.end_terminal != .None do continue
                        direction = finish - point
                    } else if settlement_alley_point_near(point, finish) {
                        if candidate.start_terminal != .None || candidate.end_terminal != .None do continue
                        direction = start - point
                    } else {
                        continue
                    }
                    length := linalg.length(direction)
                    if length <= .001 || incident_count >= len(indices) do continue
                    indices[incident_count] = candidate_index
                    directions[incident_count] = direction / length
                    incident_count += 1
                }
                if incident_count < 2 do continue
                for first in 0 ..< incident_count {
                    for second in first + 1 ..< incident_count {
                        if linalg.dot(directions[first], directions[second]) <= .966 do continue
                        candidates := [2]int{indices[first], indices[second]}
                        for remove_index in candidates {
                            original_count := city_plan.alley_count
                            originals := make([]architecture.City_Alley, original_count, context.temp_allocator)
                            copy(originals, city_plan.alleys[:original_count])
                            city_plan.alley_count -= 1
                            city_plan.alleys[remove_index] = city_plan.alleys[city_plan.alley_count]
                            resize(&city_plan.alleys, city_plan.alley_count)
                            candidate_metrics := plan^
                            settlement_plan_measure_access_topology(&candidate_metrics, city_plan, project)
                            improved :=
                                settlement_access_count_road_connected_doors(plan, city_plan, project) >= connected_before &&
                                candidate_metrics.access_shallow_junctions < baseline.access_shallow_junctions &&
                                candidate_metrics.access_crossings <= baseline.access_crossings &&
                                candidate_metrics.access_unsplit_junctions <= baseline.access_unsplit_junctions &&
                                candidate_metrics.access_hairpin_bends <= baseline.access_hairpin_bends &&
                                candidate_metrics.access_bad_door_approaches <= baseline.access_bad_door_approaches &&
                                candidate_metrics.access_bad_road_approaches <= baseline.access_bad_road_approaches &&
                                candidate_metrics.access_orphan_endpoints <= baseline.access_orphan_endpoints
                            if improved {
                                removed_count += 1
                                accepted = true
                                break
                            }
                            resize(&city_plan.alleys, original_count)
                            copy(city_plan.alleys[:original_count], originals)
                            city_plan.alley_count = original_count
                        }
                        if accepted do break
                    }
                    if accepted do break
                }
                if accepted do break
            }
            if accepted do break
        }
        if !accepted do break
    }
    return removed_count
}

settlement_access_road_approach_aligned :: proc(
    plan: ^Settlement_Plan,
    endpoint, direction: [2]f32,
) -> (
    near_road, aligned: bool,
) {
    if plan == nil do return
    direction_length := linalg.length(direction)
    if direction_length <= .001 do return
    approach := direction / direction_length
    other := endpoint + direction
    for route in plan.routes[:plan.route_count] {
        if !route.drivable do continue
        expected_distance := route.width * .5 + route.shoulder + .45
        for segment_index in 0 ..< route.geometry.count - 1 {
            start, finish := route.geometry.points[segment_index], route.geometry.points[segment_index + 1]
            segment := finish - start
            length_squared := linalg.dot(segment, segment)
            if length_squared <= .001 do continue
            along := clamp(linalg.dot(endpoint - start, segment) / length_squared, f32(0), f32(1))
            route_point := start + segment * along
            outward := endpoint - route_point
            distance := linalg.length(outward)
            if math.abs(distance - expected_distance) > .2 || distance <= .001 do continue
            other_along := clamp(linalg.dot(other - start, segment) / length_squared, f32(0), f32(1))
            other_route_point := start + segment * other_along
            other_distance := linalg.length(other - other_route_point)
            if other_distance <= distance + .2 do continue
            near_road = true
            if linalg.dot(approach, outward / distance) > .966 do return true, true
        }
    }
    return
}

settlement_access_point_at_road_edge :: proc(plan: ^Settlement_Plan, point: [2]f32, tolerance: f32 = .35) -> bool {
    if plan == nil do return false
    _, _, _, width, shoulder, distance, _, found := settlement_nearest_route_frame(plan, point)
    if !found do return false
    return math.abs(distance - (width * .5 + shoulder + .45)) <= tolerance
}

settlement_access_straighten_road_throats :: proc(plan: ^Settlement_Plan, city_plan: ^architecture.City_Plan) {
    if plan == nil || city_plan == nil do return
    original_count := city_plan.alley_count
    for alley_index in 0 ..< original_count {
        alley := &city_plan.alleys[alley_index]
        endpoints := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
        terminals := [2]architecture.City_Alley_Terminal{alley.start_terminal, alley.end_terminal}
        road_index := -1
        for endpoint_index in 0 ..< 2 {
            if terminals[endpoint_index] == .Road &&
               settlement_access_network_degree(city_plan, endpoints[endpoint_index]) == 1 {
                road_index = endpoint_index
                break
            }
        }
        if road_index < 0 do continue
        other_index := 1 - road_index
        near_road, aligned := settlement_access_road_approach_aligned(
            plan,
            endpoints[road_index],
            endpoints[other_index] - endpoints[road_index],
        )
        if !near_road || aligned do continue
        origin, _, _, _, _, _, _, found := settlement_nearest_route_frame(plan, endpoints[road_index])
        if !found do continue
        outward := endpoints[road_index] - origin
        outward_length := linalg.length(outward)
        if outward_length <= .001 do continue
        segment_length := linalg.length(endpoints[other_index] - endpoints[road_index])
        // A short road stub cannot contain a fixed .65 m throat without
        // overshooting its next node and creating a tiny reversing tail.
        throat_length := min(f32(.75), max(f32(.25), segment_length * .5))
        throat_end := endpoints[road_index] + outward / outward_length * throat_length
        if linalg.length(throat_end - endpoints[other_index]) < .1 do continue
        tail := alley^
        if road_index == 0 {
            alley.end_x, alley.end_z = throat_end[0], throat_end[1]
            alley.end_terminal = .None
            tail.start_x, tail.start_z = throat_end[0], throat_end[1]
            tail.start_terminal = .None
        } else {
            alley.start_x, alley.start_z = throat_end[0], throat_end[1]
            alley.start_terminal = .None
            tail.end_x, tail.end_z = throat_end[0], throat_end[1]
            tail.end_terminal = .None
        }
        append(&city_plan.alleys, tail)
        city_plan.alley_count += 1
    }
}

settlement_plan_measure_access_topology :: proc(
    plan: ^Settlement_Plan,
    city_plan: ^architecture.City_Plan,
    project: ^terrain.Project = nil,
) {
    if plan == nil || city_plan == nil do return
    plan.access_max_degree = 0
    plan.access_shallow_junctions = 0
    plan.access_hairpin_bends = 0
    plan.access_crossings = 0
    plan.access_unsplit_junctions = 0
    plan.access_bad_door_approaches = 0
    plan.access_bad_road_approaches = 0
    plan.access_orphan_endpoints = 0
    for first, first_index in city_plan.alleys[:city_plan.alley_count] {
        first_start := [2]f32{first.start_x, first.start_z}
        first_end := [2]f32{first.end_x, first.end_z}
        for second in city_plan.alleys[first_index + 1:city_plan.alley_count] {
            second_start := [2]f32{second.start_x, second.start_z}
            second_end := [2]f32{second.end_x, second.end_z}
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
                !settlement_alley_point_near(point, second_start) && !settlement_alley_point_near(point, second_end)
            if first_interior && second_interior {
                plan.access_crossings += 1
            } else if first_interior || second_interior {
                plan.access_unsplit_junctions += 1
            }
        }
    }
    seen := make([dynamic][2]f32, context.temp_allocator)
    for alley in city_plan.alleys[:city_plan.alley_count] {
        endpoints := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
        for point in endpoints {
            duplicate := false
            for existing in seen {
                if settlement_alley_point_near(existing, point) {
                    duplicate = true
                    break
                }
            }
            if duplicate do continue
            append(&seen, point)
            directions := make([dynamic][2]f32, context.temp_allocator)
            neighbors := make([dynamic][2]f32, context.temp_allocator)
            terminal_junction := false
            for candidate in city_plan.alleys[:city_plan.alley_count] {
                start := [2]f32{candidate.start_x, candidate.start_z}
                finish := [2]f32{candidate.end_x, candidate.end_z}
                direction: [2]f32
                if settlement_alley_point_near(point, start) {
                    direction = finish - point
                    terminal_junction = terminal_junction || candidate.start_terminal != .None
                } else if settlement_alley_point_near(point, finish) {
                    direction = start - point
                    terminal_junction = terminal_junction || candidate.end_terminal != .None
                } else {
                    continue
                }
                length := linalg.length(direction)
                if length > .001 {
                    append(&directions, direction / length)
                    append(&neighbors, point + direction)
                }
            }
            plan.access_max_degree = max(plan.access_max_degree, len(directions))
            if len(directions) == 2 &&
               settlement_access_junction_location_valid(plan, city_plan, point) &&
               linalg.dot(directions[0], directions[1]) > .5 &&
               settlement_access_segment_clear(city_plan, neighbors[0], neighbors[1], .2, -1) {
                // Count only avoidable hairpins: obstacle-constrained
                // switchbacks can be necessary, while a clear chord means
                // the network retained an unnecessary doubling-back bend.
                plan.access_hairpin_bends += 1
            }
            if len(directions) < 3 do continue
            shallow := false
            for first_index in 0 ..< len(directions) {
                for second_index in first_index + 1 ..< len(directions) {
                    alignment := linalg.dot(directions[first_index], directions[second_index])
                    if alignment > .966 {
                        shallow = true
                        break
                    }
                }
                if shallow do break
            }
            natural_village_fork := false
            if shallow && plan.request.scale == .Village && len(directions) == 3 {
                for first_index in 0 ..< len(directions) {
                    for second_index in first_index + 1 ..< len(directions) {
                        if linalg.dot(directions[first_index], directions[second_index]) < -.966 {
                            natural_village_fork = true
                            break
                        }
                    }
                    if natural_village_fork do break
                }
            }
            if shallow && !terminal_junction && !natural_village_fork {
                plan.access_shallow_junctions += 1
            }
        }
    }
    for structure, structure_index in city_plan.structures[:city_plan.count] {
        door := settlement_structure_front_door_point(structure, .22, project)
        front := settlement_structure_entrance_approach_outward(structure, project)
        for alley in city_plan.alleys[:city_plan.alley_count] {
            start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
            direction: [2]f32
            if settlement_alley_point_near(door, start) && alley.start_terminal == .Door {
                direction = finish - door
            } else if settlement_alley_point_near(door, finish) && alley.end_terminal == .Door {
                direction = start - door
            } else {
                continue
            }
            length := linalg.length(direction)
            if length <= .001 do continue
            if linalg.dot(direction / length, front) < .966 {
                plan.access_bad_door_approaches += 1
            }
            break
        }
    }
    for alley in city_plan.alleys[:city_plan.alley_count] {
        endpoints := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
        for endpoint, endpoint_index in endpoints {
            if settlement_access_network_degree(city_plan, endpoint) != 1 do continue
            terminal := endpoint_index == 0 ? alley.start_terminal : alley.end_terminal
            if terminal == .Door || terminal == .Public_Space do continue
            at_door := false
            for structure in city_plan.structures[:city_plan.count] {
                if settlement_alley_point_near(endpoint, settlement_structure_front_door_point(structure)) {
                    at_door = true
                    break
                }
            }
            if at_door do continue
            other := endpoints[1 - endpoint_index]
            direction := other - endpoint
            near_road, aligned := settlement_access_road_approach_aligned(plan, endpoint, direction)
            road_edge := terminal == .Road || near_road || settlement_access_point_at_road_edge(plan, endpoint, .6)
            if road_edge {
                if alley.half_width <= 1.25 && near_road && !aligned {
                    plan.access_bad_road_approaches += 1
                }
            } else if alley.half_width <= 1.25 {
                plan.access_orphan_endpoints += 1
            }
        }
    }
}

// Network cleanup may legally move the anonymous node immediately beyond a
// door and leave the final visible segment arriving diagonally across its
// threshold. Restore a short orthogonal throat at the very end of generation;
// the old segment remains connected at the new landing node, so this changes
// presentation geometry without changing door-to-road reachability.
settlement_access_restore_door_throats :: proc(
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan,
) -> int {
    if project == nil || city_plan == nil do return 0
    restored := 0
    for structure, structure_index in city_plan.structures[:city_plan.count] {
        door := settlement_structure_front_door_point(structure, .22, project)
        outward := settlement_structure_entrance_approach_outward(structure, project)
        existing_count := city_plan.alley_count
        for alley_index in 0 ..< existing_count {
            alley := &city_plan.alleys[alley_index]
            door_at_start := alley.start_terminal == .Door &&
                settlement_alley_point_near(door, {alley.start_x, alley.start_z})
            door_at_end := alley.end_terminal == .Door &&
                settlement_alley_point_near(door, {alley.end_x, alley.end_z})
            if !door_at_start && !door_at_end do continue
            neighbor := [2]f32{alley.start_x, alley.start_z}
            if door_at_start do neighbor = {alley.end_x, alley.end_z}
            direction := neighbor - door
            length := linalg.length(direction)
            if length <= .001 || linalg.dot(direction / length, outward) >= .966 do break

            preferred_length := min(max(alley.half_width * 1.1, f32(.55)), f32(.85))
            landing: [2]f32
            elbow: [2]f32
            landing_found := false
            dogleg := false
            for length_scale in ([4]f32{1, .72, .48, .30}) {
                candidate := door + outward * (preferred_length * length_scale)
                continuation := neighbor - candidate
                continuation_length := linalg.length(continuation)
                if continuation_length <= .001 do continue
                // The landing may turn, but it must not double back toward
                // the wall; that would trade a diagonal threshold for a tiny
                // artificial hairpin.
                if linalg.dot(-outward, continuation / continuation_length) > .5 do continue
                clearance := max(alley.half_width - .08, f32(.25))
                if !settlement_access_segment_clear(
                        city_plan,
                        door,
                        candidate,
                        clearance,
                        structure_index,
                    ) ||
                   !settlement_access_segment_clear(
                        city_plan,
                        candidate,
                        neighbor,
                        clearance,
                        structure_index,
                    ) {
                    continue
                }
                landing, landing_found = candidate, true
                break
            }
            if !landing_found {
                // If the surviving network lies partly behind the stair foot,
                // use a compact L-shaped landing rather than either arriving
                // diagonally or creating an outward-and-back hairpin.
                tangent := [2]f32{outward[1], -outward[0]}
                tangent_sign := linalg.dot(neighbor - door, tangent) < 0 ? f32(-1) : f32(1)
                lateral := tangent * tangent_sign
                clearance := max(alley.half_width - .08, f32(.25))
                for length_scale in ([3]f32{.62, .45, .30}) {
                    candidate_landing := door + outward * (preferred_length * length_scale)
                    tangent_distance := math.abs(linalg.dot(neighbor - candidate_landing, tangent))
                    lateral_length := clamp(tangent_distance * .55, f32(.45), f32(1.05))
                    candidate_elbow := candidate_landing + lateral * lateral_length
                    continuation := neighbor - candidate_elbow
                    continuation_length := linalg.length(continuation)
                    if continuation_length <= .001 do continue
                    if linalg.dot(-lateral, continuation / continuation_length) > .5 do continue
                    if !settlement_access_segment_clear(
                            city_plan,
                            door,
                            candidate_landing,
                            clearance,
                            structure_index,
                        ) ||
                       !settlement_access_segment_clear(
                            city_plan,
                            candidate_landing,
                            candidate_elbow,
                            clearance,
                            structure_index,
                        ) ||
                       !settlement_access_segment_clear(
                            city_plan,
                            candidate_elbow,
                            neighbor,
                            clearance,
                            structure_index,
                        ) {
                        continue
                    }
                    landing, elbow = candidate_landing, candidate_elbow
                    landing_found, dogleg = true, true
                    break
                }
            }
            if !landing_found do break
            original_terminal := door_at_start ? alley.start_terminal : alley.end_terminal
            half_width := alley.half_width
            replacement := dogleg ? elbow : landing
            if door_at_start {
                alley.start_x, alley.start_z = replacement[0], replacement[1]
                alley.start_terminal = .None
            } else {
                alley.end_x, alley.end_z = replacement[0], replacement[1]
                alley.end_terminal = .None
            }
            append(
                &city_plan.alleys,
                architecture.City_Alley {
                    start_x = door[0],
                    start_z = door[1],
                    end_x = landing[0],
                    end_z = landing[1],
                    half_width = half_width,
                    start_terminal = original_terminal,
                },
            )
            city_plan.alley_count += 1
            if dogleg {
                append(
                    &city_plan.alleys,
                    architecture.City_Alley {
                        start_x = landing[0],
                        start_z = landing[1],
                        end_x = elbow[0],
                        end_z = elbow[1],
                        half_width = half_width,
                    },
                )
                city_plan.alley_count += 1
            }
            restored += 1
            break
        }
    }
    return restored
}

settlement_access_mark_road_connected_segments :: proc(
    plan: ^Settlement_Plan,
    city_plan: ^architecture.City_Plan,
    connected: []bool,
    excluded_index: int = -1,
) {
    if plan == nil || city_plan == nil do return
    count := min(city_plan.alley_count, len(connected))
    for alley, alley_index in city_plan.alleys[:count] {
        if alley_index == excluded_index do continue
        endpoints := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
        terminals := [2]architecture.City_Alley_Terminal{alley.start_terminal, alley.end_terminal}
        for terminal, endpoint_index in terminals {
            if terminal == .Road {
                connected[alley_index] = true
                break
            }
            // Junction plazas are laid directly over the authored road node.
            // Once hidden path throats are clipped away, their public-space
            // boundary is the road-rooted graph node.
            if terminal == .Public_Space && settlement_plaza_terminal_index(plan, endpoints[endpoint_index]) >= 0 {
                connected[alley_index] = true
                break
            }
        }
    }
    for _ in 0 ..< count {
        changed := false
        for first, first_index in city_plan.alleys[:count] {
            if first_index == excluded_index do continue
            if !connected[first_index] do continue
            first_endpoints := [2][2]f32{{first.start_x, first.start_z}, {first.end_x, first.end_z}}
            for second, second_index in city_plan.alleys[:count] {
                if second_index == excluded_index do continue
                if connected[second_index] do continue
                second_endpoints := [2][2]f32{{second.start_x, second.start_z}, {second.end_x, second.end_z}}
                touches := false
                for first_endpoint in first_endpoints {
                    for second_endpoint in second_endpoints {
                        if settlement_alley_point_near(first_endpoint, second_endpoint) {
                            touches = true
                            break
                        }
                    }
                    if touches do break
                }
                if !touches {
                    first_terminals := [2]architecture.City_Alley_Terminal{first.start_terminal, first.end_terminal}
                    second_terminals := [2]architecture.City_Alley_Terminal{second.start_terminal, second.end_terminal}
                    for first_endpoint, first_endpoint_index in first_endpoints {
                        if first_terminals[first_endpoint_index] != .Public_Space do continue
                        plaza_index := settlement_plaza_terminal_index(plan, first_endpoint)
                        if plaza_index < 0 do continue
                        for second_endpoint, second_endpoint_index in second_endpoints {
                            if second_terminals[second_endpoint_index] != .Public_Space do continue
                            if settlement_plaza_terminal_index(plan, second_endpoint) == plaza_index {
                                touches = true
                                break
                            }
                        }
                        if touches do break
                    }
                }
                if touches {
                    connected[second_index] = true
                    changed = true
                }
            }
        }
        if !changed do break
    }
}

// A road spur generated for one plot can occasionally terminate within the
// snapping tolerance of a later building's doorway. Once that building adds
// its real outward-facing doorstep, the coincident spur turns the private
// threshold into a through-node. Remove only a leaf road spur, and only when
// the authored Door segment remains road-connected without it.
settlement_access_prune_road_spurs_at_doors :: proc(
    plan: ^Settlement_Plan,
    city_plan: ^architecture.City_Plan,
    project: ^terrain.Project = nil,
) {
    if plan == nil || city_plan == nil do return
    if plan.request.scale != .Village do return
    for structure in city_plan.structures[:city_plan.count] {
        door := settlement_structure_front_door_point(structure, .22, project)
        if settlement_access_network_degree(city_plan, door) <= 1 do continue
        candidate_index := 0
        for candidate_index < city_plan.alley_count {
            candidate := city_plan.alleys[candidate_index]
            points := [2][2]f32{{candidate.start_x, candidate.start_z}, {candidate.end_x, candidate.end_z}}
            terminals := [2]architecture.City_Alley_Terminal{candidate.start_terminal, candidate.end_terminal}
            door_endpoint := -1
            if settlement_alley_point_near(door, points[0]) {
                door_endpoint = 0
            } else if settlement_alley_point_near(door, points[1]) {
                door_endpoint = 1
            }
            if door_endpoint < 0 || terminals[door_endpoint] == .Door {
                candidate_index += 1
                continue
            }
            road_endpoint := 1 - door_endpoint
            road_direction := points[road_endpoint] - door
            road_length := linalg.length(road_direction)
            outward := settlement_structure_entrance_approach_outward(structure, project)
            if road_length > .001 && linalg.dot(road_direction / road_length, outward) <= .966 {
                city_plan.alley_count -= 1
                city_plan.alleys[candidate_index] = city_plan.alleys[city_plan.alley_count]
                resize(&city_plan.alleys, city_plan.alley_count)
                continue
            }
            if terminals[road_endpoint] != .Road ||
               settlement_access_network_degree(city_plan, points[road_endpoint]) != 1 {
                candidate_index += 1
                continue
            }
            connected_without := make([]bool, city_plan.alley_count, context.temp_allocator)
            settlement_access_mark_road_connected_segments(plan, city_plan, connected_without, candidate_index)
            doorstep_connected := false
            for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
                if alley_index == candidate_index || !connected_without[alley_index] do continue
                start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
                if (settlement_alley_point_near(door, start) && alley.start_terminal == .Door) ||
                   (settlement_alley_point_near(door, finish) && alley.end_terminal == .Door) {
                    doorstep_connected = true
                    break
                }
            }
            if !doorstep_connected {
                // The only Door-labelled edge may itself be a dead outward
                // throat while this accidental road spur is the edge keeping
                // the old weak connectivity test alive. Remove the pair and
                // let the final repair route a coherent threshold from
                // scratch; retaining either half recreates the through-door.
                dead_door_index := -1
                for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
                    if alley_index == candidate_index do continue
                    door_points := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
                    door_terminals := [2]architecture.City_Alley_Terminal{alley.start_terminal, alley.end_terminal}
                    door_side := -1
                    if settlement_alley_point_near(door, door_points[0]) && door_terminals[0] == .Door {
                        door_side = 0
                    } else if settlement_alley_point_near(door, door_points[1]) && door_terminals[1] == .Door {
                        door_side = 1
                    }
                    if door_side < 0 do continue
                    other_side := 1 - door_side
                    if door_terminals[other_side] == .None &&
                       settlement_access_network_degree(city_plan, door_points[other_side]) == 1 {
                        dead_door_index = alley_index
                        break
                    }
                }
                if dead_door_index >= 0 {
                    first_remove := max(candidate_index, dead_door_index)
                    second_remove := min(candidate_index, dead_door_index)
                    remove_indices := [2]int{first_remove, second_remove}
                    for remove_index in remove_indices {
                        city_plan.alley_count -= 1
                        city_plan.alleys[remove_index] = city_plan.alleys[city_plan.alley_count]
                        resize(&city_plan.alleys, city_plan.alley_count)
                    }
                    candidate_index = 0
                    continue
                }
                candidate_index += 1
                continue
            }
            city_plan.alley_count -= 1
            city_plan.alleys[candidate_index] = city_plan.alleys[city_plan.alley_count]
            resize(&city_plan.alleys, city_plan.alley_count)
        }
    }
}

settlement_access_remove_disconnected_components :: proc(plan: ^Settlement_Plan, city_plan: ^architecture.City_Plan) {
    if plan == nil || city_plan == nil || city_plan.alley_count <= 0 do return
    connected := make([]bool, city_plan.alley_count, context.temp_allocator)
    settlement_access_mark_road_connected_segments(plan, city_plan, connected)
    write := 0
    for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
        if !connected[alley_index] do continue
        city_plan.alleys[write], write = alley, write + 1
    }
    city_plan.alley_count = write
    resize(&city_plan.alleys, write)
}

settlement_access_door_connection_valid :: proc(
    plan: ^Settlement_Plan,
    city_plan: ^architecture.City_Plan,
    structure: terrain.Structure,
    road_connected: []bool,
    project: ^terrain.Project = nil,
) -> bool {
    door := settlement_structure_front_door_point(structure, .22, project)
    if settlement_access_point_at_road_edge(plan, door) do return true
    // Dense town/city blocks can deliberately give a threshold two public
    // faces (street plus court or passage). The private-leaf invariant is the
    // village offshoot rule: that is where using somebody else's doorstep as
    // a through-lane produces the implausible single-file access pattern.
    if plan.request.scale != .Village {
        for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
            if alley_index >= len(road_connected) || !road_connected[alley_index] do continue
            start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
            if settlement_alley_point_near(door, start) || settlement_alley_point_near(door, finish) do return true
        }
        return false
    }
    if settlement_access_network_degree(city_plan, door) != 1 do return false
    outward := settlement_structure_entrance_approach_outward(structure, project)
    for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
        if alley_index >= len(road_connected) || !road_connected[alley_index] do continue
        start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
        direction: [2]f32
        door_terminal := false
        if settlement_alley_point_near(door, start) && alley.start_terminal == .Door {
            direction = finish - start
            door_terminal = true
        } else if settlement_alley_point_near(door, finish) && alley.end_terminal == .Door {
            direction = start - finish
            door_terminal = true
        }
        length := linalg.length(direction)
        if door_terminal && length > .001 && linalg.dot(direction / length, outward) > .966 do return true
    }
    return false
}

settlement_access_repair_disconnected_doors :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan,
    remaining_facade_attempts: int = 3,
) {
    if plan == nil || project == nil || city_plan == nil do return
    flipped := false
    for structure, structure_index in city_plan.structures[:city_plan.count] {
        road_connected := make([]bool, city_plan.alley_count, context.temp_allocator)
        settlement_access_mark_road_connected_segments(plan, city_plan, road_connected)
        door := settlement_structure_front_door_point(structure, .22, project)
        connected := settlement_access_door_connection_valid(plan, city_plan, structure, road_connected, project)
        if connected do continue
        origin, _, route_normal, route_width, route_shoulder, _, _, found := settlement_nearest_route_frame(plan, door)
        if !found do continue
        front := settlement_structure_entrance_approach_outward(structure, project)
        side_sign := linalg.dot(door - origin, route_normal) < 0 ? f32(-1) : f32(1)
        outward := route_normal * side_sign
        road_goal := origin + outward * (route_width * .5 + route_shoulder + .45)
        network_goals: [8][2]f32
        network_goal_distances := [8]f32{1e30, 1e30, 1e30, 1e30, 1e30, 1e30, 1e30, 1e30}
        network_goal_count := 0
        for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
            if !road_connected[alley_index] do continue
            candidates := [3][2]f32 {
                {alley.start_x, alley.start_z},
                {(alley.start_x + alley.end_x) * .5, (alley.start_z + alley.end_z) * .5},
                {alley.end_x, alley.end_z},
            }
            for candidate in candidates {
                if settlement_access_network_degree(city_plan, candidate) >= 4 ||
                   !settlement_access_junction_location_valid(plan, city_plan, candidate) {
                    continue
                }
                distance := linalg.length(candidate - door)
                for slot in 0 ..< len(network_goals) {
                    if distance >= network_goal_distances[slot] do continue
                    for shift := len(network_goals) - 1; shift > slot; shift -= 1 {
                        network_goals[shift] = network_goals[shift - 1]
                        network_goal_distances[shift] = network_goal_distances[shift - 1]
                    }
                    network_goals[slot], network_goal_distances[slot] = candidate, distance
                    network_goal_count = min(network_goal_count + 1, len(network_goals))
                    break
                }
            }
        }
        clearances := [8]f32{.5, .4, .35, .3, .25, .2, .15, .1}
        repaired := false
        for clearance in clearances {
            throat_length := max(f32(.65), clearance * 1.5)
            doorstep := door + front * throat_length
            for alley in city_plan.alleys[:city_plan.alley_count] {
                start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
                existing: [2]f32
                if settlement_alley_point_near(door, start) {
                    existing = finish
                } else if settlement_alley_point_near(door, finish) {
                    existing = start
                } else {
                    continue
                }
                direction := existing - door
                length := linalg.length(direction)
                if length > .001 && linalg.dot(direction / length, front) > .966 {
                    doorstep = existing
                    break
                }
            }
            verge := road_goal + outward * throat_length
            if !settlement_access_segment_clear(city_plan, door, doorstep, clearance, structure_index) {
                continue
            }
            // Town blocks and village courts may enclose a door from every
            // independent road route, so their fallback may join a verified
            // road-rooted pedestrian trunk. Degree and junction checks below
            // prevent that repair from overloading the shared network.
            repair_network_goal_count := 0
            if plan.request.scale == .Town || plan.request.scale == .Village {
                repair_network_goal_count = network_goal_count
            }
            for network_goal in network_goals[:repair_network_goal_count] {
                network_path := settlement_access_path_find(
                    project,
                    city_plan,
                    doorstep,
                    network_goal,
                    structure_index,
                    clearance,
                    true,
                    front,
                )
                if network_path.count < 2 ||
                   !settlement_access_path_crossings_valid(city_plan, network_path, true) ||
                   !settlement_access_junction_location_valid(
                           plan,
                           city_plan,
                           network_path.points[network_path.count - 1],
                       ) ||
                   !settlement_access_junction_angle_valid(city_plan, network_path) {
                    continue
                }
                network_path = settlement_access_path_prepend(network_path, door)
                if plan.request.scale == .Village &&
                   (!settlement_access_path_clear(city_plan, network_path, clearance, structure_index) ||
                           !settlement_access_path_crossings_valid(city_plan, network_path, true, true)) {
                    continue
                }
                width := max(clearance * 2, f32(.5))
                for index in 0 ..< network_path.count - 1 {
                    start_terminal := architecture.City_Alley_Terminal.None
                    if index == 0 do start_terminal = .Door
                    append(
                        &city_plan.alleys,
                        architecture.City_Alley {
                            start_x = network_path.points[index][0],
                            start_z = network_path.points[index][1],
                            end_x = network_path.points[index + 1][0],
                            end_z = network_path.points[index + 1][1],
                            half_width = width * .5,
                            start_terminal = start_terminal,
                        },
                    )
                    city_plan.alley_count += 1
                }
                repaired = true
                break
            }
            if repaired do break
            joined_network := false
            path := settlement_access_path_find(
                project,
                city_plan,
                doorstep,
                verge,
                structure_index,
                clearance,
                true,
                front,
                outward,
            )
            if path.count < 2 {
                path = settlement_access_path_find(
                    project,
                    city_plan,
                    doorstep,
                    verge,
                    structure_index,
                    clearance,
                    false,
                    front,
                    outward,
                )
                path = settlement_access_path_append(path, road_goal)
                path = settlement_access_path_prepend(path, door)
            }
            if !joined_network do path = settlement_access_path_append(path, road_goal)
            path = settlement_access_path_prepend(path, door)
            if path.count < 2 ||
               (plan.request.scale == .Village &&
                       (!settlement_access_path_clear(city_plan, path, clearance, structure_index) ||
                               !settlement_access_path_crossings_valid(city_plan, path, false, true))) {
                continue
            }
            width := max(clearance * 2, f32(.5))
            for index in 0 ..< path.count - 1 {
                start_terminal := architecture.City_Alley_Terminal.None
                end_terminal := architecture.City_Alley_Terminal.None
                if index == 0 do start_terminal = .Door
                if index == path.count - 2 && !joined_network do end_terminal = .Road
                append(
                    &city_plan.alleys,
                    architecture.City_Alley {
                        start_x = path.points[index][0],
                        start_z = path.points[index][1],
                        end_x = path.points[index + 1][0],
                        end_z = path.points[index + 1][1],
                        half_width = width * .5,
                        start_terminal = start_terminal,
                        end_terminal = end_terminal,
                    },
                )
                city_plan.alley_count += 1
            }
            repaired = true
            break
        }
        if repaired {
            settlement_access_split_intersections(city_plan)
            settlement_access_deduplicate_segments(city_plan)
            settlement_access_snap_near_endpoints(city_plan)
            settlement_access_remove_degenerate_segments(city_plan)
        }
        marked := make([]bool, city_plan.alley_count, context.temp_allocator)
        settlement_access_mark_road_connected_segments(plan, city_plan, marked)
        verified := settlement_access_door_connection_valid(
            plan,
            city_plan,
            city_plan.structures[structure_index],
            marked,
            project,
        )
        if !verified && remaining_facade_attempts > 0 {
            purpose := Settlement_Building_Purpose.Dwelling
            if structure_index < plan.ordinary_purpose_count {
                purpose = plan.ordinary_purposes[structure_index]
            }
            preserve_aegean_civic_frontage :=
                plan.request.region == .Aegean &&
                plan.request.scale == .Village &&
                (purpose == .Inn_Shop || purpose == .Workshop)
            if preserve_aegean_civic_frontage do continue
            current_side := int(city_plan.structures[structure_index].entrance_side)
            side_step := plan.request.scale == .Village ? 1 : 2
            city_plan.structures[structure_index].entrance_side = terrain.Entrance_Side((current_side + side_step) & 3)
            flipped = true
        }
    }
    if flipped {
        settlement_access_repair_disconnected_doors(
            plan,
            project,
            city_plan,
            plan.request.scale == .Village ? remaining_facade_attempts - 1 : 0,
        )
    }
}

settlement_access_count_road_connected_doors :: proc(
    plan: ^Settlement_Plan,
    city_plan: ^architecture.City_Plan,
    project: ^terrain.Project = nil,
) -> int {
    if plan == nil || city_plan == nil do return 0
    road_connected := make([]bool, city_plan.alley_count, context.temp_allocator)
    settlement_access_mark_road_connected_segments(plan, city_plan, road_connected)
    connected := 0
    for structure in city_plan.structures[:city_plan.count] {
        // A doorstep is a private leaf of the public access graph. Merely
        // sharing coordinates with a connected segment is not sufficient:
        // that can certify a path which runs through one household's
        // threshold on its way to another.
        if settlement_access_door_connection_valid(plan, city_plan, structure, road_connected, project) do connected += 1
    }
    return connected
}

settlement_access_prune_orphan_stubs :: proc(plan: ^Settlement_Plan, city_plan: ^architecture.City_Plan) {
    if plan == nil || city_plan == nil do return
    for {
        remove := make([]bool, city_plan.alley_count, context.temp_allocator)
        removed := 0
        for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
            if alley.half_width > 1.25 do continue
            endpoints := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
            terminals := [2]architecture.City_Alley_Terminal{alley.start_terminal, alley.end_terminal}
            for endpoint, endpoint_index in endpoints {
                if settlement_access_network_degree(city_plan, endpoint) != 1 ||
                   settlement_access_network_degree(city_plan, endpoints[1 - endpoint_index]) < 2 ||
                   terminals[endpoint_index] != .None ||
                   settlement_access_point_at_road_edge(plan, endpoint, .6) {
                    continue
                }
                serves_door := false
                for structure in city_plan.structures[:city_plan.count] {
                    if settlement_alley_point_near(endpoint, settlement_structure_front_door_point(structure)) {
                        serves_door = true
                        break
                    }
                }
                if !serves_door {
                    remove[alley_index] = true
                    removed += 1
                    break
                }
            }
        }
        if removed == 0 do break
        write := 0
        for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
            if remove[alley_index] do continue
            city_plan.alleys[write], write = alley, write + 1
        }
        city_plan.alley_count = write
        resize(&city_plan.alleys, write)
    }
    // Trimming a dangling chain can expose the far end of a road-rooted
    // public path. Preserve that useful final segment and explain its new
    // endpoint explicitly instead of reporting a fresh orphan.
    for &alley in city_plan.alleys[:city_plan.alley_count] {
        terminals := [2]^architecture.City_Alley_Terminal{&alley.start_terminal, &alley.end_terminal}
        endpoints := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
        for endpoint_index in 0 ..< 2 {
            other_index := 1 - endpoint_index
            if terminals[endpoint_index]^ == .None &&
               terminals[other_index]^ == .Road &&
               settlement_access_network_degree(city_plan, endpoints[endpoint_index]) == 1 {
                terminals[endpoint_index]^ = .Public_Space
            }
        }
    }
}

settlement_access_prune_stale_terminal_free_stubs :: proc(city_plan: ^architecture.City_Plan) {
    if city_plan == nil do return
    remove := make([]bool, city_plan.alley_count, context.temp_allocator)
    for &alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
        endpoints := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
        terminals := [2]architecture.City_Alley_Terminal{alley.start_terminal, alley.end_terminal}
        degrees := [2]int {
            settlement_access_network_degree(city_plan, endpoints[0]),
            settlement_access_network_degree(city_plan, endpoints[1]),
        }
        if terminals[0] == .None && terminals[1] == .None && degrees[0] == 1 && degrees[1] == 1 {
            remove[alley_index] = true
            continue
        }
        for leaf_index in 0 ..< 2 {
            other_index := 1 - leaf_index
            if terminals[leaf_index] != .None || degrees[leaf_index] != 1 {
                continue
            }
            if terminals[other_index] == .Road {
                if leaf_index == 0 {
                    alley.start_terminal = .Public_Space
                } else {
                    alley.end_terminal = .Public_Space
                }
                break
            }
            if degrees[other_index] < 2 do continue
            for structure in city_plan.structures[:city_plan.count] {
                if settlement_alley_point_near(
                    endpoints[other_index],
                    settlement_structure_front_door_point(structure),
                ) {
                    remove[alley_index] = true
                    break
                }
            }
            if remove[alley_index] do break
        }
    }
    write := 0
    for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
        if remove[alley_index] do continue
        city_plan.alleys[write], write = alley, write + 1
    }
    city_plan.alley_count = write
    resize(&city_plan.alleys, write)
}

settlement_access_prune_dead_door_throats :: proc(plan: ^Settlement_Plan, city_plan: ^architecture.City_Plan) {
    if plan == nil || city_plan == nil do return
    for structure in city_plan.structures[:city_plan.count] {
        door := settlement_structure_front_door_point(structure)
        incident_count := 0
        for alley in city_plan.alleys[:city_plan.alley_count] {
            if settlement_alley_point_near(door, {alley.start_x, alley.start_z}) ||
               settlement_alley_point_near(door, {alley.end_x, alley.end_z}) {
                incident_count += 1
            }
        }
        if incident_count < 2 do continue
        index := 0
        for index < city_plan.alley_count {
            alley := city_plan.alleys[index]
            start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
            other: [2]f32
            if settlement_alley_point_near(door, start) {
                other = finish
            } else if settlement_alley_point_near(door, finish) {
                other = start
            } else {
                index += 1
                continue
            }
            if settlement_access_network_degree(city_plan, other) != 1 ||
               settlement_access_point_at_road_edge(plan, other) {
                index += 1
                continue
            }
            city_plan.alley_count -= 1
            city_plan.alleys[index] = city_plan.alleys[city_plan.alley_count]
            resize(&city_plan.alleys, city_plan.alley_count)
            incident_count -= 1
            if incident_count < 2 do break
        }
    }
}

settlement_access_remove_unreachable_buildings :: proc(plan: ^Settlement_Plan, city_plan: ^architecture.City_Plan) {
    if plan == nil || city_plan == nil do return
    connected_segments := make([]bool, city_plan.alley_count, context.temp_allocator)
    settlement_access_mark_road_connected_segments(plan, city_plan, connected_segments)
    original_count := city_plan.count
    write := 0
    for structure, read in city_plan.structures[:original_count] {
        door := settlement_structure_front_door_point(structure)
        connected := settlement_access_point_at_road_edge(plan, door)
        front := settlement_structure_entrance_outward(structure)
        if !connected {
            for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
                if !connected_segments[alley_index] do continue
                start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
                direction: [2]f32
                if settlement_alley_point_near(door, start) {
                    direction = finish - door
                } else if settlement_alley_point_near(door, finish) {
                    direction = start - door
                } else {
                    continue
                }
                length := linalg.length(direction)
                if length > .001 && linalg.dot(direction / length, front) > .966 {
                    connected = true
                    break
                }
            }
        }
        if !connected {
            continue
        }
        if write != read {
            city_plan.structures[write] = structure
            if read < city_plan.parcel_count do city_plan.parcels[write] = city_plan.parcels[read]
            if read < plan.ordinary_purpose_count do plan.ordinary_purposes[write] = plan.ordinary_purposes[read]
        }
        write += 1
    }
    city_plan.count = write
    resize(&city_plan.structures, write)
    if city_plan.parcel_count >= original_count {
        city_plan.parcel_count = write
        resize(&city_plan.parcels, write)
    }
    plan.ordinary_purpose_count = min(plan.ordinary_purpose_count, write)
    plan.access_required_count = write
}

// Accumulate shortest door-to-road journeys over the finished access graph.
// Repeated use widens communal trunks. A purpose-widened doorstep also carries
// its proven working width through the selected road-rooted journey, so a cart
// approach does not immediately collapse into a cottage footpath. Every
// segment remains collision checked.
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
        attachments[structure_index], attached[structure_index] =
            settlement_access_building_attachment(city_plan, structure)
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
                unavailable := destination_index == source_index ||
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
            append(
                &city_plan.alleys,
                architecture.City_Alley {
                    start_x = path.points[point_index][0],
                    start_z = path.points[point_index][1],
                    end_x = path.points[point_index + 1][0],
                    end_z = path.points[point_index + 1][1],
                    half_width = passage_half_width,
                },
            )
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
        append(
            &city_plan.alleys,
            architecture.City_Alley {
                start_x = path.points[index][0],
                start_z = path.points[index][1],
                end_x = path.points[index + 1][0],
                end_z = path.points[index + 1][1],
                half_width = 1.2,
                start_terminal = start_terminal,
                end_terminal = end_terminal,
            },
        )
        city_plan.alley_count += 1
    }
}

// Lay a public circulation skeleton before private doorstep access exists.
// Begin with a grade- and obstacle-aware route from one building apron to the
// road, then grow new routes through previously unserved open space toward
// other sampled aprons. Door generation can subsequently attach short private
// spurs to this road-rooted network instead of inventing one road spoke per
// household.
settlement_access_seed_public_network :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan,
) {
    if plan == nil || project == nil || city_plan == nil || city_plan.count < 3 do return
    branch_budget := plan.request.scale == .City ? 12 : plan.request.scale == .Town ? 8 : 3
    waypoints: [SETTLEMENT_SITE_CAPACITY][2]f32
    waypoint_count := 0
    seed_offset := int(plan.request.seed % u32(city_plan.count))
    // Midpoints between separated building groups tend to land in the
    // unclaimed space that people would actually walk through. A small
    // deterministic lateral offset prevents every waypoint from sitting on
    // the same radial line in regular fabric.
    for sample_index in 0 ..< city_plan.count * 4 {
        if waypoint_count >= branch_budget + 1 do break
        first_index := (seed_offset + sample_index * 7) % city_plan.count
        second_offset := 1 + (seed_offset + sample_index * 11) % (city_plan.count - 1)
        second_index := (first_index + second_offset) % city_plan.count
        first := [2]f32{city_plan.structures[first_index].center_x, city_plan.structures[first_index].center_z}
        second := [2]f32{city_plan.structures[second_index].center_x, city_plan.structures[second_index].center_z}
        separation := second - first
        separation_length := linalg.length(separation)
        if separation_length < 10 || separation_length > 45 do continue
        normal := [2]f32{-separation[1], separation[0]} / separation_length
        jitter_sign := sample_index & 1 == 0 ? f32(1) : f32(-1)
        candidate := (first + second) * .5 + normal * jitter_sign * min(separation_length * .08, f32(2.5))
        if !settlement_access_segment_clear(city_plan, candidate, candidate + [2]f32{.05, 0}, .9, -1) {
            continue
        }
        duplicate := false
        for existing in waypoints[:waypoint_count] {
            if linalg.length(existing - candidate) < 6 {
                duplicate = true
                break
            }
        }
        if duplicate do continue
        waypoints[waypoint_count], waypoint_count = candidate, waypoint_count + 1
    }
    if waypoint_count <= 0 do return

    network: [SETTLEMENT_SITE_CAPACITY][2]f32
    network_count := 0
    root_index := -1
    root_point, root_goal: [2]f32
    root_distance := f32(1e30)
    for waypoint, waypoint_index in waypoints[:waypoint_count] {
        origin, _, route_normal, route_width, route_shoulder, distance, _, found := settlement_nearest_route_frame(
            plan,
            waypoint,
        )
        if !found || distance >= root_distance do continue
        side_sign := linalg.dot(waypoint - origin, route_normal) < 0 ? f32(-1) : f32(1)
        root_index = waypoint_index
        root_point = waypoint
        root_goal = origin + route_normal * side_sign * (route_width * .5 + route_shoulder + .45)
        root_distance = distance
    }
    if root_index < 0 do return
    root_path := settlement_access_path_find(project, city_plan, root_point, root_goal, -1, .9, true)
    if root_path.count < 2 do return
    settlement_access_append_public_path(city_plan, root_path, true)
    for point in root_path.points[:root_path.count] {
        if network_count >= len(network) do break
        network[network_count], network_count = point, network_count + 1
    }

    added := 0
    for attempt in 0 ..< waypoint_count * 2 {
        if added >= branch_budget do break
        waypoint_index := (root_index + 1 + attempt * 3) % waypoint_count
        if waypoint_index == root_index do continue
        waypoint := waypoints[waypoint_index]
        goal, goal_distance := [2]f32{}, f32(1e30)
        for candidate in network[:network_count] {
            distance := linalg.length(candidate - waypoint)
            if distance < goal_distance {
                goal, goal_distance = candidate, distance
            }
        }
        if goal_distance < 5 || goal_distance > 34 do continue
        path := settlement_access_path_find(project, city_plan, waypoint, goal, -1, .9, true)
        if path.count < 2 do continue
        settlement_access_append_public_path(city_plan, path)
        for point in path.points[:path.count - 1] {
            if network_count >= len(network) do break
            network[network_count], network_count = point, network_count + 1
        }
        settlement_access_split_intersections(city_plan)
        settlement_access_deduplicate_segments(city_plan)
        settlement_access_snap_near_endpoints(city_plan)
        settlement_access_remove_degenerate_segments(city_plan)
        added += 1
    }
}

settlement_plan_generate_building_access :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan,
    rng: ^Settlement_Rng,
    maximum_length: f32,
) -> int {
    if plan == nil || project == nil || city_plan == nil || rng == nil do return 0
    settlement_access_split_intersections(city_plan)
    settlement_access_deduplicate_segments(city_plan)
    settlement_access_snap_near_endpoints(city_plan)
    settlement_access_consolidate_parallel_twigs(city_plan)
    settlement_access_deduplicate_segments(city_plan)
    settlement_access_remove_degenerate_segments(city_plan)
    settlement_access_prune_shallow_seed_branches(city_plan)
    settlement_access_seed_public_network(plan, project, city_plan)
    settlement_access_split_intersections(city_plan)
    settlement_access_deduplicate_segments(city_plan)
    settlement_access_snap_near_endpoints(city_plan)
    settlement_access_remove_degenerate_segments(city_plan)
    plan.access_required_count = city_plan.count
    plan.access_connected_count = 0
    plan.access_repair_count = 0
    connected := 0
    network: [SETTLEMENT_SITE_CAPACITY][2]f32
    network_degrees: [SETTLEMENT_SITE_CAPACITY]int
    network_count := 0
    seed_road_connected := make([]bool, city_plan.alley_count, context.temp_allocator)
    settlement_access_mark_road_connected_segments(plan, city_plan, seed_road_connected)
    // Village commons and block alleys are laid down before individual door
    // access. They already begin at a road edge, so seed the growing network
    // with their complete centerlines instead of forcing every house to
    // rediscover a separate escape from the same court.
    for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
        if !seed_road_connected[alley_index] do continue
        points := [3][2]f32 {
            {alley.start_x, alley.start_z},
            {(alley.start_x + alley.end_x) * .5, (alley.start_z + alley.end_z) * .5},
            {alley.end_x, alley.end_z},
        }
        degrees := [3]int {
            settlement_access_network_degree(city_plan, points[0]),
            2,
            settlement_access_network_degree(city_plan, points[2]),
        }
        for point, point_index in points {
            duplicate_index := -1
            for existing, existing_index in network[:network_count] {
                if settlement_alley_point_near(existing, point) {
                    duplicate_index = existing_index
                    break
                }
            }
            if duplicate_index >= 0 {
                network_degrees[duplicate_index] = max(network_degrees[duplicate_index], degrees[point_index])
                continue
            }
            if network_count >= len(network) do break
            network[network_count], network_degrees[network_count], network_count =
                point, degrees[point_index], network_count + 1
        }
    }
    // Grow access from the deepest plots back toward the public road. A
    // nearest-first pass lets a foreground house claim a private path before
    // the generator has seen the households behind it; those later paths then
    // walk past one another or form parallel twigs. Deepest-first makes the
    // first route through an offshoot the candidate communal spine, after
    // which shallower doors can join it. Ties retain program order so this
    // remains deterministic.
    access_order: [SETTLEMENT_SITE_CAPACITY]int
    access_depth: [SETTLEMENT_SITE_CAPACITY]f32
    access_order_count := min(city_plan.count, len(access_order))
    for structure, structure_index in city_plan.structures[:access_order_count] {
        center := [2]f32{structure.center_x, structure.center_z}
        _, _, _, _, _, route_distance, _, route_found := settlement_nearest_route_frame(plan, center)
        access_order[structure_index] = structure_index
        // Towns and cities already receive block-scale public passages before
        // doors are connected. Preserve their program order; reversing those
        // civic and perimeter buildings can consume the few valid junctions
        // before an enclosed door is served. Deepest-first is the village
        // offshoot rule, where a row of households must collectively establish
        // its lane.
        access_depth[structure_index] = plan.request.scale == .Village && route_found ? route_distance : f32(0)
        insertion := structure_index
        for insertion > 0 && access_depth[access_order[insertion - 1]] < access_depth[access_order[insertion]] {
            access_order[insertion - 1], access_order[insertion] = access_order[insertion], access_order[insertion - 1]
            insertion -= 1
        }
    }
    for order_index in 0 ..< access_order_count {
        structure_index := access_order[order_index]
        structure := city_plan.structures[structure_index]
        // A development event may already have authored this building's
        // threshold onto a road-rooted lane, court, quay, or yard. Preserve
        // that frontage as a completed terminal; reconsidering both façade
        // orientations here can flip the building away from its public space
        // and leave the authored path attached to the former door.
        authored_door := settlement_structure_front_door_point(structure, .22, project)
        authored_connected := settlement_access_point_at_road_edge(plan, authored_door)
        if !authored_connected {
            for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
                if alley_index >= len(seed_road_connected) || !seed_road_connected[alley_index] do continue
                start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
                if settlement_alley_point_near(authored_door, start) ||
                   settlement_alley_point_near(authored_door, finish) {
                    authored_connected = true
                    break
                }
            }
        }
        if authored_connected {
            connected += 1
            continue
        }
        center := [2]f32{structure.center_x, structure.center_z}
        nearest_origin, _, _, _, _, _, _, nearest_found := settlement_nearest_route_frame(plan, center)
        if !nearest_found do continue
        purpose := Settlement_Building_Purpose.Dwelling
        if structure_index < plan.ordinary_purpose_count {
            purpose = plan.ordinary_purposes[structure_index]
        }
        direct_grade_limit := settlement_access_direct_grade_limit(purpose)
        best_path: Settlement_Route
        best_score := f32(1e30)
        best_half_width := f32(0)
        best_entrance_side := structure.entrance_side
        best_network_index := -1
        best_joins_network := false
        clearances: [8]f32
        clearance_count := 0
        switch plan.request.scale {
        case .City:
            clearances = {.7, .6, .5, .45, .4, .35, .3, .25}
            clearance_count = 8
        case .Town:
            clearances = {.6, .5, .45, .4, .35, .3, .25, 0}
            clearance_count = 7
        case .Village:
            clearances = {.5, .45, .4, .35, .3, .25, 0, 0}
            clearance_count = 6
        }
        entrance_sides := [4]terrain.Entrance_Side{.Front, .Right, .Rear, .Left}
        entrance_side_count := len(entrance_sides)
        if plan.request.region == .Aegean &&
           plan.request.scale == .Village &&
           (purpose == .Inn_Shop || purpose == .Workshop) {
            // Placement has already oriented these public anchors toward the
            // nearest route. Do not let access optimization rotate the door
            // onto a shorter side wall and erase the civic frontage.
            entrance_sides[0] = structure.entrance_side
            entrance_side_count = 1
        }
        for entrance_side in entrance_sides[:entrance_side_count] {
            oriented_structure := structure
            oriented_structure.entrance_side = entrance_side
            destination := settlement_structure_front_door_point(oriented_structure, .22, project)
            edge := settlement_access_structure_edge(oriented_structure, int(entrance_side))
            front := settlement_structure_entrance_approach_outward(oriented_structure, project)
            side_path_found := false
            for path_clearance in clearances[:clearance_count] {
                origin, route_tangent, route_normal, route_width, route_shoulder, _, _, found :=
                    settlement_nearest_route_frame(plan, destination)
                if !found do continue
                direction := destination - origin
                distance := linalg.length(direction)
                if distance <= .01 do continue
                side_sign := linalg.dot(direction, route_normal) < 0 ? f32(-1) : f32(1)
                road_outward := route_normal * side_sign
                road_goal := origin + road_outward * (route_width * .5 + route_shoulder + .45)
                road_distance := linalg.length(destination - road_goal)
                preferred_doorstep_length := max(f32(.65), path_clearance * 1.5)
                doorstep_length := preferred_doorstep_length
                doorstep := destination + front * doorstep_length
                if !settlement_access_segment_clear(
                    city_plan,
                    destination,
                    doorstep,
                    path_clearance,
                    structure_index,
                ) {
                    continue
                }
                branch_points: [3][2]f32
                branch_distances := [3]f32{1e30, 1e30, 1e30}
                branch_indices := [3]int{-1, -1, -1}
                network_candidate_limit :=
                    settlement_access_network_candidate_limit(plan.request.scale, road_distance)
                for network_point, network_index in network[:network_count] {
                    if network_degrees[network_index] >= 4 do continue
                    candidate_distance := linalg.length(destination - network_point)
                    if candidate_distance >= network_candidate_limit do continue
                    for candidate_slot in 0 ..< len(branch_points) {
                        if candidate_distance >= branch_distances[candidate_slot] do continue
                        for shift_slot in candidate_slot + 1 ..< len(branch_points) {
                            reverse_slot := len(branch_points) - (shift_slot - candidate_slot)
                            branch_points[reverse_slot] = branch_points[reverse_slot - 1]
                            branch_distances[reverse_slot] = branch_distances[reverse_slot - 1]
                            branch_indices[reverse_slot] = branch_indices[reverse_slot - 1]
                        }
                        branch_points[candidate_slot] = network_point
                        branch_distances[candidate_slot] = candidate_distance
                        branch_indices[candidate_slot] = network_index
                        break
                    }
                }
                // Endpoints alone bias growth toward starbursts. Also offer
                // the nearest point on every established segment so a new
                // household can form a T-junction and share the longest
                // practical portion of an existing alley.
                for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
                    if alley_index < len(seed_road_connected) && !seed_road_connected[alley_index] do continue
                    alley_start := [2]f32{alley.start_x, alley.start_z}
                    alley_end := [2]f32{alley.end_x, alley.end_z}
                    segment := alley_end - alley_start
                    length_squared := linalg.dot(segment, segment)
                    if length_squared <= .01 do continue
                    along := clamp(linalg.dot(destination - alley_start, segment) / length_squared, f32(0), f32(1))
                    if along <= .08 || along >= .92 do continue
                    branch_point := alley_start + segment * along
                    if settlement_access_network_degree(city_plan, branch_point) >= 4 do continue
                    candidate_distance := linalg.length(destination - branch_point)
                    if candidate_distance >= network_candidate_limit do continue
                    for candidate_slot in 0 ..< len(branch_points) {
                        if candidate_distance >= branch_distances[candidate_slot] do continue
                        for shift_slot in candidate_slot + 1 ..< len(branch_points) {
                            reverse_slot := len(branch_points) - (shift_slot - candidate_slot)
                            branch_points[reverse_slot] = branch_points[reverse_slot - 1]
                            branch_distances[reverse_slot] = branch_distances[reverse_slot - 1]
                            branch_indices[reverse_slot] = branch_indices[reverse_slot - 1]
                        }
                        branch_points[candidate_slot] = branch_point
                        branch_distances[candidate_slot] = candidate_distance
                        // Interior contacts do not yet have an advertised
                        // network point; normalization will split the segment.
                        branch_indices[candidate_slot] = -2
                        break
                    }
                }
                goals: [10][2]f32
                goal_is_branch: [10]bool
                goal_road_outward: [10][2]f32
                goal_network_indices := [10]int{-1, -1, -1, -1, -1, -1, -1, -1, -1, -1}
                goal_count := 0
                for branch_point, branch_slot in branch_points {
                    if branch_indices[branch_slot] == -1 do continue
                    goals[goal_count] = branch_point
                    goal_is_branch[goal_count] = true
                    goal_network_indices[goal_count] = branch_indices[branch_slot]
                    goal_count += 1
                }
                road_offsets := [7]f32{0, -6, 6, -12, 12, -18, 18}
                for offset in road_offsets {
                    probe := origin + route_tangent * offset
                    shifted_origin, _, shifted_normal, shifted_width, shifted_shoulder, _, _, shifted_found :=
                        settlement_nearest_route_frame(plan, probe)
                    if !shifted_found do continue
                    shifted_direction := destination - shifted_origin
                    shifted_distance := linalg.length(shifted_direction)
                    if shifted_distance <= .01 do continue
                    shifted_side_sign := linalg.dot(shifted_direction, shifted_normal) < 0 ? f32(-1) : f32(1)
                    shifted_outward := shifted_normal * shifted_side_sign
                    shifted_goal := shifted_origin + shifted_outward * (shifted_width * .5 + shifted_shoulder + .45)
                    duplicate := false
                    for existing in goals[:goal_count] {
                        if linalg.length(existing - shifted_goal) < .25 {
                            duplicate = true
                            break
                        }
                    }
                    if !duplicate {
                        for alley in city_plan.alleys[:city_plan.alley_count] {
                            endpoints := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
                            for endpoint in endpoints {
                                if linalg.length(endpoint - shifted_goal) < 1.75 {
                                    duplicate = true
                                    break
                                }
                            }
                            if duplicate do break
                        }
                    }
                    if duplicate || goal_count >= len(goals) do continue
                    goals[goal_count] = shifted_goal
                    goal_road_outward[goal_count] = shifted_outward
                    goal_count += 1
                }
                for goal, goal_index in goals[:goal_count] {
                    // Candidate score can never beat 72% of its straight-line
                    // distance: grade and detours only add cost, while joining
                    // an established trunk is the largest available discount.
                    // Once another candidate beats that admissible lower
                    // bound, avoid an A* search that cannot affect the result.
                    candidate_distance_lower_bound := linalg.length(destination - goal) * .72
                    if best_score <= candidate_distance_lower_bound do continue
                    path_goal := goal
                    preferred_verge_length := max(f32(.65), path_clearance * 1.5)
                    if !goal_is_branch[goal_index] {
                        path_goal += goal_road_outward[goal_index] * preferred_verge_length
                        // The road apron is appended after A*. Reject an
                        // obstructed apron before paying for a search whose
                        // assembled route can never be valid.
                        if plan.request.scale == .Village &&
                           !settlement_access_segment_clear(
                                   city_plan,
                                   path_goal,
                                   goal,
                                   path_clearance,
                                   structure_index,
                               ) {
                            continue
                        }
                    }
                    goal_distance := linalg.length(destination - path_goal)
                    if goal_distance > maximum_length do continue
                    path: Settlement_Route
                    direct_distance := linalg.length(destination - goal)
                    short_direct := false
                    if !goal_is_branch[goal_index] &&
                       direct_distance < doorstep_length + preferred_verge_length + .2 &&
                       direct_distance > .01 {
                        toward_road := (goal - destination) / direct_distance
                        away_from_road := -toward_road
                        short_direct =
                            linalg.dot(toward_road, front) > .966 &&
                            linalg.dot(away_from_road, goal_road_outward[goal_index]) > .966 &&
                            settlement_access_segment_clear(
                                city_plan,
                                destination,
                                goal,
                                path_clearance,
                                structure_index,
                            ) &&
                            settlement_access_segment_max_grade(project, destination, goal) < direct_grade_limit
                        if short_direct {
                            path.points[0], path.points[1], path.count = destination, goal, 2
                        }
                    }
                    if !short_direct {
                        path = settlement_access_path_find(
                            project,
                            city_plan,
                            doorstep,
                            path_goal,
                            structure_index,
                            path_clearance,
                            true,
                            front,
                            goal_road_outward[goal_index],
                            direct_grade_limit,
                        )
                        if !goal_is_branch[goal_index] do path = settlement_access_path_append(path, goal)
                        path = settlement_access_path_prepend(path, destination)
                    }
                    joins_network := goal_is_branch[goal_index]
                    relaxed := false
                    if joins_network && path.count >= 2 {
                        path.points[path.count - 1] = settlement_access_snap_to_network_endpoint(
                            city_plan,
                            path.points[path.count - 1],
                        )
                    }
                    path_valid :=
                        path.count >= 2 &&
                        (plan.request.scale != .Village ||
                                joins_network ||
                                settlement_access_segment_clear(
                                    city_plan,
                                    path.points[path.count - 2],
                                    path.points[path.count - 1],
                                    path_clearance,
                                    structure_index,
                                )) &&
                        settlement_access_path_crossings_valid(
                            city_plan,
                            path,
                            joins_network,
                            plan.request.scale == .Village,
                        ) &&
                        (!joins_network ||
                                settlement_access_junction_location_valid(
                                    plan,
                                    city_plan,
                                    path.points[path.count - 1],
                                )) &&
                        (!joins_network || settlement_access_junction_angle_valid(city_plan, path))
                    if !path_valid {
                        path = settlement_access_path_find(
                            project,
                            city_plan,
                            doorstep,
                            path_goal,
                            structure_index,
                            path_clearance,
                            false,
                            front,
                            goal_road_outward[goal_index],
                            direct_grade_limit,
                        )
                        if !goal_is_branch[goal_index] do path = settlement_access_path_append(path, goal)
                        path = settlement_access_path_prepend(path, destination)
                        path, relaxed = settlement_access_path_relax_to_network(plan, city_plan, path)
                        joins_network = joins_network || relaxed
                        if joins_network && path.count >= 2 {
                            path.points[path.count - 1] = settlement_access_snap_to_network_endpoint(
                                city_plan,
                                path.points[path.count - 1],
                            )
                        }
                        path_valid =
                            path.count >= 2 &&
                            (plan.request.scale != .Village ||
                                    joins_network ||
                                    settlement_access_segment_clear(
                                        city_plan,
                                        path.points[path.count - 2],
                                        path.points[path.count - 1],
                                        path_clearance,
                                        structure_index,
                                    )) &&
                            settlement_access_path_crossings_valid(
                                city_plan,
                                path,
                                joins_network,
                                plan.request.scale == .Village,
                            ) &&
                            (!joins_network ||
                                    settlement_access_junction_location_valid(
                                        plan,
                                        city_plan,
                                        path.points[path.count - 1],
                                    )) &&
                            (!joins_network || settlement_access_junction_angle_valid(city_plan, path))
                    }
                    if !path_valid do continue
                    side_path_found = true
                    path_length := f32(0)
                    for index in 0 ..< path.count - 1 {
                        path_length += linalg.length(path.points[index + 1] - path.points[index])
                    }
                    path_maximum_grade := settlement_access_path_max_grade(project, path)
                    path_score := settlement_access_candidate_score(
                        path_length,
                        path_maximum_grade,
                        direct_grade_limit,
                        joins_network,
                        settlement_access_connection_shape_penalty(
                            city_plan,
                            path,
                            front,
                            joins_network,
                        ),
                    )
                    if path_score < best_score {
                        best_path, best_half_width = path, path_clearance
                        best_score = path_score
                        best_entrance_side = entrance_side
                        best_network_index = relaxed ? -1 : goal_network_indices[goal_index]
                        best_joins_network = joins_network
                    }
                    // Compare the bounded target set for every building.
                    // Otherwise domestic paths accept the first valid road
                    // mouth and never get the opportunity to reuse a nearby
                    // shared trunk.
                }
                if side_path_found do break
            }
        }
        if best_path.count < 2 do continue
        city_plan.structures[structure_index].entrance_side = best_entrance_side
        selected_half_width := best_half_width
        preferred_half_width := settlement_access_preferred_half_width(plan.request.scale, purpose)
        path_maximum_grade := settlement_access_path_max_grade(project, best_path)
        preferred_clear :=
            preferred_half_width > selected_half_width &&
            settlement_access_grade_allows_preferred_width(purpose, path_maximum_grade)
        if preferred_clear {
            for index in 0 ..< best_path.count - 1 {
                if !settlement_access_segment_clear(
                    city_plan,
                    best_path.points[index],
                    best_path.points[index + 1],
                    preferred_half_width,
                    structure_index,
                ) {
                    preferred_clear = false
                    break
                }
            }
        }
        if preferred_clear do selected_half_width = preferred_half_width
        width := selected_half_width * 2
        for index in 0 ..< best_path.count - 1 {
            start_terminal := architecture.City_Alley_Terminal.None
            end_terminal := architecture.City_Alley_Terminal.None
            if index == 0 do start_terminal = .Door
            if index == best_path.count - 2 && !best_joins_network do end_terminal = .Road
            append(
                &city_plan.alleys,
                architecture.City_Alley {
                    start_x = best_path.points[index][0],
                    start_z = best_path.points[index][1],
                    end_x = best_path.points[index + 1][0],
                    end_z = best_path.points[index + 1][1],
                    half_width = width * .5,
                    start_terminal = start_terminal,
                    end_terminal = end_terminal,
                },
            )
            city_plan.alley_count += 1
        }
        settlement_access_split_intersections(city_plan)
        settlement_access_deduplicate_segments(city_plan)
        settlement_access_snap_near_endpoints(city_plan)
        settlement_access_remove_degenerate_segments(city_plan)
        if best_network_index >= 0 && best_network_index < network_count {
            network_degrees[best_network_index] = settlement_access_network_degree(
                city_plan,
                network[best_network_index],
            )
        }
        // Keep both the doorway and its orthogonal doorstep throat private to
        // this building. Neighboring access may branch only beyond that
        // threshold, where a junction cannot smear into the façade.
        advertised_end := best_path.count
        if !best_joins_network do advertised_end = max(2, best_path.count - 2)
        for point in best_path.points[2:advertised_end] {
            duplicate_index := -1
            for existing, existing_index in network[:network_count] {
                if settlement_alley_point_near(existing, point) {
                    duplicate_index = existing_index
                    break
                }
            }
            if duplicate_index >= 0 {
                network_degrees[duplicate_index] = settlement_access_network_degree(city_plan, point)
                continue
            }
            if network_count >= len(network) do break
            degree := settlement_access_network_degree(city_plan, point)
            network[network_count], network_degrees[network_count], network_count = point, degree, network_count + 1
        }
        connected += 1
        plan.access_repair_count += 1
    }
    plan.access_connected_count = connected
    settlement_access_split_intersections(city_plan)
    settlement_access_deduplicate_segments(city_plan)
    settlement_access_snap_near_endpoints(city_plan)
    settlement_access_remove_degenerate_segments(city_plan)
    settlement_access_simplify_hairpin_bends(plan, city_plan)
    settlement_access_split_intersections(city_plan)
    settlement_access_deduplicate_segments(city_plan)
    settlement_access_snap_near_endpoints(city_plan)
    settlement_access_remove_degenerate_segments(city_plan)
    settlement_access_split_intersections(city_plan)
    settlement_access_deduplicate_segments(city_plan)
    settlement_access_snap_near_endpoints(city_plan)
    settlement_access_remove_degenerate_segments(city_plan)
    if plan.access_connected_count < plan.access_required_count {
        settlement_access_repair_disconnected_doors(plan, project, city_plan)
    }
    settlement_access_straighten_road_throats(plan, city_plan)
    settlement_access_split_intersections(city_plan)
    settlement_access_deduplicate_segments(city_plan)
    settlement_access_snap_near_endpoints(city_plan)
    settlement_access_consolidate_parallel_twigs(city_plan)
    settlement_access_deduplicate_segments(city_plan)
    settlement_access_prune_stale_terminal_free_stubs(city_plan)
    settlement_access_remove_degenerate_segments(city_plan)
    // Normalization is allowed to replace or prune geometric segments, but
    // it must not invalidate the settlement's hard door-to-road invariant.
    // Recount the finished graph and close any connectivity lost during
    // throat straightening, twig consolidation, or stale-stub pruning. Keep
    // the post-repair cleanup topology-preserving: aggressive simplification
    // has already run and would merely reopen the same failure.
    if settlement_access_count_road_connected_doors(plan, city_plan, project) < plan.access_required_count {
        settlement_access_repair_disconnected_doors(plan, project, city_plan)
        settlement_access_split_intersections(city_plan)
        settlement_access_deduplicate_segments(city_plan)
        settlement_access_snap_near_endpoints(city_plan)
        settlement_access_remove_degenerate_segments(city_plan)
    }
    // Door access establishes the mandatory graph. Improve it with a small
    // number of trip-derived cross-links before smoothing and width promotion.
    settlement_access_promote_circulation_links(plan, project, city_plan)
    // Independently routed paths can leave a sawtoothed shared centerline
    // even when every individual route was smooth. Relax the assembled graph
    // while all protected terminals and junctions remain fixed.
    _ = settlement_access_relax_degree_two_nodes(plan, project, city_plan)
    // A final repair, court chain, or relaxation move can introduce a
    // degree-two bend after the earlier simplification pass. Chord those
    // obstacle-free internal hairpins now; protected door and road terminals
    // remain excluded by the simplifier itself.
    settlement_access_simplify_hairpin_bends(plan, city_plan)
    settlement_access_split_intersections(city_plan)
    settlement_access_deduplicate_segments(city_plan)
    settlement_access_snap_near_endpoints(city_plan)
    settlement_access_remove_degenerate_segments(city_plan)
    _ = settlement_access_collapse_short_junction_links(plan, project, city_plan)
    settlement_access_prune_road_spurs_at_doors(plan, city_plan, project)
    // Simplification and circulation promotion can leave a narrow anonymous
    // leaf hanging from a real junction. It serves neither a door nor a road
    // and renders as one arm of a starburst across the verge.
    settlement_access_prune_orphan_stubs(plan, city_plan)
    settlement_access_remove_degenerate_segments(city_plan)
    if settlement_access_count_road_connected_doors(plan, city_plan, project) < plan.access_required_count {
        settlement_access_repair_disconnected_doors(plan, project, city_plan)
        settlement_access_split_intersections(city_plan)
        settlement_access_deduplicate_segments(city_plan)
        settlement_access_snap_near_endpoints(city_plan)
        settlement_access_remove_degenerate_segments(city_plan)
    }
    settlement_access_finalize_curves(city_plan)
    settlement_access_widen_shared_trunks(plan, city_plan)
    // Shared-demand analysis can expose a stale coincident road spur after
    // its dead doorstep is no longer part of the selected shortest journey.
    // Reapply the threshold invariant to the exact graph that will be
    // rendered and imported.
    for _ in 0 ..< 3 {
        settlement_access_prune_road_spurs_at_doors(plan, city_plan, project)
        if settlement_access_count_road_connected_doors(plan, city_plan, project) >= plan.access_required_count do break
        settlement_access_repair_disconnected_doors(plan, project, city_plan)
        settlement_access_split_intersections(city_plan)
        settlement_access_deduplicate_segments(city_plan)
        settlement_access_snap_near_endpoints(city_plan)
        settlement_access_remove_degenerate_segments(city_plan)
    }
    settlement_access_clip_to_plazas(plan, city_plan)
    _ = settlement_access_restore_door_throats(project, city_plan)
    // Clipping, repair, and curve preparation can be the last writers of a
    // road leaf. Re-square those final mouths, then give any surviving
    // near-parallel T branches a short common stem before rendering.
    settlement_access_straighten_road_throats(plan, city_plan)
    settlement_access_split_intersections(city_plan)
    settlement_access_deduplicate_segments(city_plan)
    settlement_access_snap_near_endpoints(city_plan)
    settlement_access_remove_degenerate_segments(city_plan)
    _ = settlement_access_stem_shallow_forks(plan, project, city_plan)
    _ = settlement_access_collapse_short_junction_links(plan, project, city_plan)
    _ = settlement_access_prune_redundant_shallow_branches(plan, project, city_plan)
    settlement_access_simplify_hairpin_bends(plan, city_plan)
    settlement_access_split_intersections(city_plan)
    settlement_access_deduplicate_segments(city_plan)
    settlement_access_snap_near_endpoints(city_plan)
    settlement_access_remove_degenerate_segments(city_plan)
    plan.access_connected_count = settlement_access_count_road_connected_doors(plan, city_plan, project)
    if plan.access_connected_count < plan.access_required_count {
        settlement_access_repair_disconnected_doors(plan, project, city_plan)
        settlement_access_split_intersections(city_plan)
        settlement_access_deduplicate_segments(city_plan)
        settlement_access_snap_near_endpoints(city_plan)
        settlement_access_remove_degenerate_segments(city_plan)
        plan.access_connected_count = settlement_access_count_road_connected_doors(plan, city_plan, project)
    }
    // No topology simplifier runs after this point. Reassert the short
    // perpendicular doorstep throat here so late orphan and branch cleanup
    // cannot leave a path arriving diagonally across a facade.
    _ = settlement_access_restore_door_throats(project, city_plan)
    settlement_access_remove_degenerate_segments(city_plan)
    plan.access_connected_count = settlement_access_count_road_connected_doors(plan, city_plan, project)
    settlement_access_finalize_curves(city_plan)
    settlement_plan_measure_access_topology(plan, city_plan, project)
    return connected
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
        if city_plan.alley_count >= budget do break
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
        candidate: Settlement_Route
        candidate.points[0], candidate.points[1], candidate.count = start, end, 2
        if !settlement_access_path_crossings_valid(city_plan, candidate, false) do continue
        if settlement_access_network_degree(city_plan, end) > 0 &&
           !settlement_access_junction_angle_valid(city_plan, candidate) {
            continue
        }
        width := settlement_route_width_sample(rng, .Alley)
        append(
            &city_plan.alleys,
            architecture.City_Alley {
                start_x = start[0],
                start_z = start[1],
                end_x = end[0],
                end_z = end[1],
                half_width = width * .5,
                start_terminal = .Road,
                end_terminal = .Public_Space,
            },
        )
        city_plan.alley_count += 1
    }
}

settlement_municipal_lighting_badness :: proc(city_plan: ^architecture.City_Plan, x, z: f32) -> f32 {
    if city_plan == nil do return 1
    badness := f32(0)
    for lamp in city_plan.lamps[:city_plan.lamp_count] {
        dx, dz := x - lamp.x, z - lamp.z
        distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
        badness = max(
            badness,
            clamp(
                (SETTLEMENT_MUNICIPAL_LIGHT_MIN_SPACING - distance) / SETTLEMENT_MUNICIPAL_LIGHT_MIN_SPACING,
                f32(0),
                f32(1),
            ),
        )
    }
    return badness
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
    return settlement_municipal_lighting_badness(city_plan, x, z) == 0
}

settlement_lamp_sample_count :: proc(length, spacing: f32) -> int {
    if spacing <= 0 || length < spacing * .65 do return 0
    // Ceiling bounds the unlit half-cell at either segment endpoint. Flooring
    // made a 49 m segment receive one lamp while a 50 m segment received two,
    // producing abrupt dark gaps unrelated to street hierarchy.
    return int(math.ceil(f64(length / spacing)))
}

settlement_route_lamp_spacing :: proc(scale: Settlement_Scale, class: Settlement_Route_Class) -> f32 {
    civic := class == .Civic_Spine
    if scale == .Town {
        // The 3.6 m post-top family serves pedestrian-scale town streets.
        // Keep endpoint half-cells bounded near three mounting heights instead
        // of leaving the six-to-seven-height gaps produced by 25 m spacing.
        return civic ? 18 : 22
    }
    return civic ? 20 : 26
}

settlement_plan_generate_lamps :: proc(plan: ^Settlement_Plan, city_plan: ^architecture.City_Plan) {
    if plan == nil || city_plan == nil || plan.request.scale == .Village do return
    for route in plan.routes[:plan.route_count] {
        if route.class != .Civic_Spine && route.class != .Waterfront && route.class != .Street {
            continue
        }
        spacing := settlement_route_lamp_spacing(plan.request.scale, route.class)
        for segment_index in 0 ..< route.geometry.count - 1 {
            a, b := route.geometry.points[segment_index], route.geometry.points[segment_index + 1]
            delta := b - a
            length := linalg.length(delta)
            sample_count := settlement_lamp_sample_count(length, spacing)
            if sample_count <= 0 do continue
            tangent := delta / length
            normal := [2]f32{-tangent.y, tangent.x}
            for sample in 0 ..< sample_count {
                along := (f32(sample) + .5) / f32(sample_count)
                side := ((sample + segment_index) & 1) == 0 ? f32(1) : f32(-1)
                offset := route.width * .5 + route.shoulder + .65
                point := a + delta * along + normal * (offset * side)
                if !settlement_lamp_position_clear(city_plan, point.x, point.y) do continue
                append(
                    &city_plan.lamps,
                    architecture.City_Lamp{x = point.x, z = point.y, yaw = math.atan2(tangent.x, tangent.y)},
                )
                city_plan.lamp_count += 1
            }
        }
    }
    path_spacing := plan.request.scale == .Town ? f32(16) : f32(20)
    for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
        if alley.household_demand < 4 do continue
        curve := settlement_access_alley_curve(city_plan, alley_index)
        curve_steps := settlement_access_curve_sample_count(curve)
        length := f32(0)
        previous := curve.points[0]
        for curve_step in 1 ..= curve_steps {
            current := settlement_access_curve_point(curve, f32(curve_step) / f32(curve_steps))
            length += linalg.length(current - previous)
            previous = current
        }
        sample_count := settlement_lamp_sample_count(length, path_spacing)
        if sample_count <= 0 do continue
        for sample in 0 ..< sample_count {
            along := (f32(sample) + .5) / f32(sample_count)
            center := settlement_access_curve_point(curve, along)
            before := settlement_access_curve_point(curve, max(f32(0), along - .01))
            after := settlement_access_curve_point(curve, min(f32(1), along + .01))
            tangent := linalg.normalize0(after - before)
            normal := [2]f32{-tangent[1], tangent[0]}
            preferred_side := ((sample + alley_index) & 1) == 0 ? f32(1) : f32(-1)
            sides := [2]f32{preferred_side, -preferred_side}
            for side in sides {
                point := center + normal * ((alley.half_width + .55) * side)
                if !settlement_lamp_position_clear(city_plan, point[0], point[1]) ||
                   settlement_access_point_on_alley_surface(city_plan, point, .25) {
                    continue
                }
                append(
                    &city_plan.lamps,
                    architecture.City_Lamp{x = point[0], z = point[1], yaw = math.atan2(tangent[0], tangent[1])},
                )
                city_plan.lamp_count += 1
                break
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

// Ordinary structures represent occupied homes and working buildings, not
// sheds. The area is an exterior footprint: 500 ft² leaves roughly the UK
// 37–39 m² one-person dwelling minimum after thick perimeter walls, while the
// short-side floor prevents the same area from becoming a closet-like sliver.
SETTLEMENT_MIN_ORDINARY_BUILDING_AREA :: f32(46.45152) // 500 ft² in m²
SETTLEMENT_MIN_ORDINARY_BUILDING_SIDE :: f32(4.5)

settlement_normalize_ordinary_building_dimensions :: proc(
    width_in, depth_in: f32,
) -> (
    width, depth: f32,
) {
    width = max(width_in, SETTLEMENT_MIN_ORDINARY_BUILDING_SIDE)
    depth = max(depth_in, SETTLEMENT_MIN_ORDINARY_BUILDING_SIDE)
    area := width * depth
    if area < SETTLEMENT_MIN_ORDINARY_BUILDING_AREA {
        scale := f32(math.sqrt(f64(SETTLEMENT_MIN_ORDINARY_BUILDING_AREA / area)))
        width *= scale
        depth *= scale
    }
    return
}

settlement_ordinary_building_dimensions_valid :: proc(width, depth: f32) -> bool {
    return width >= SETTLEMENT_MIN_ORDINARY_BUILDING_SIDE &&
        depth >= SETTLEMENT_MIN_ORDINARY_BUILDING_SIDE &&
        width * depth >= SETTLEMENT_MIN_ORDINARY_BUILDING_AREA - .001
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
    // The primary entrance is authored on the width/frontage face. Keep that
    // face at least as broad as the side wall so doors land on the building's
    // larger elevation instead of the narrow end of a deep footprint.
    if depth > frontage {
        frontage, depth = depth, frontage
    }
    frontage, depth = settlement_normalize_ordinary_building_dimensions(frontage, depth)
    return
}

settlement_village_add_path :: proc(
    city_plan: ^architecture.City_Plan,
    start, end: [2]f32,
    width: f32,
    start_terminal: architecture.City_Alley_Terminal = .None,
    end_terminal: architecture.City_Alley_Terminal = .None,
) {
    if city_plan == nil do return
    dx, dz := end[0] - start[0], end[1] - start[1]
    length_squared := dx * dx + dz * dz
    if length_squared < 5 * 5 ||
       length_squared > 65 * 65 ||
       !settlement_pedestrian_segment_clear(city_plan, start, end) {
        return
    }
    append(
        &city_plan.alleys,
        architecture.City_Alley {
            start_x = start[0],
            start_z = start[1],
            end_x = end[0],
            end_z = end[1],
            half_width = width * .5,
            start_terminal = start_terminal,
            end_terminal = end_terminal,
        },
    )
    city_plan.alley_count += 1
}

Settlement_Village_Frontage_Lane :: struct {
    road_start:         [2]f32,
    junction:           [2]f32,
    start:              [2]f32,
    end:                [2]f32,
    tangent:            [2]f32,
    normal:             [2]f32,
    half_width:         f32,
    court_radius:       f32,
    connector_required: bool,
    contour_aligned:    bool,
    valid:              bool,
}

Settlement_Village_Frontage_Kind :: enum u8 {
    None,
    Lane,
    Court,
    Quay,
}

// Reserve public access before placing its households. Planned tissue uses a
// road-normal offshoot; hillside tissue uses a contour terrace reached through
// a short road-normal throat. Both select the safer side of the parent route.
settlement_village_frontage_lane :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    route_origin, route_tangent, route_normal: [2]f32,
    route_width, route_shoulder: f32,
    tissue: Settlement_Tissue,
    contour_preferred: bool,
    route_found: bool,
) -> Settlement_Village_Frontage_Lane {
    result: Settlement_Village_Frontage_Lane
    if plan == nil || project == nil || !route_found do return result
    lane_length := f32(64)
    road_offset := route_width * .5 + route_shoulder + .45
    best_score := f32(-1e30)
    seed_side := plan.request.seed & 1 == 0 ? f32(1) : f32(-1)
    sides := [2]f32{seed_side, -seed_side}
    sample := f32(10)
    gradient := [2]f32 {
        terrain.sample_height(project, 0, route_origin[0] + sample, route_origin[1]) -
        terrain.sample_height(project, 0, route_origin[0] - sample, route_origin[1]),
        terrain.sample_height(project, 0, route_origin[0], route_origin[1] + sample) -
        terrain.sample_height(project, 0, route_origin[0], route_origin[1] - sample),
    }
    gradient_length := linalg.length(gradient)
    local_slope := gradient_length / (sample * 2)
    contour_tissue :=
        tissue == .Hillside_Accretion || tissue == .Contour_Terrace || contour_preferred || local_slope >= .06
    contour_tangent := route_tangent
    if contour_tissue {
        if gradient_length > .001 {
            contour_tangent = {-gradient[1] / gradient_length, gradient[0] / gradient_length}
        }
        if plan.request.seed & 2 != 0 do contour_tangent = -contour_tangent
    }
    angle_offsets := [5]f32{-.35, -.175, 0, .175, .35}
    angle_count := contour_tissue ? 5 : 1
    for side in sides {
        outward := route_normal * side
        road_start := route_origin + outward * road_offset
        for angle_index in 0 ..< angle_count {
            angle_offset := contour_tissue ? angle_offsets[angle_index] : f32(0)
            junction := road_start
            tangent := outward
            start := road_start
            end := start + tangent * lane_length
            connector_required := false
            if contour_tissue {
                connector_required = true
                junction = road_start + outward * 6
                cosine, sine := f32(math.cos(f64(angle_offset))), f32(math.sin(f64(angle_offset)))
                tangent = {
                    contour_tangent[0] * cosine - contour_tangent[1] * sine,
                    contour_tangent[0] * sine + contour_tangent[1] * cosine,
                }
                start = junction - tangent * (lane_length * .5)
                end = junction + tangent * (lane_length * .5)
            }
            score := -math.abs(angle_offset) * 2
            previous_height := terrain.sample_height(project, 0, start[0], start[1])
            valid := previous_height > project.sea_level + .6
            maximum_lane_grade := f32(0)
            sample_run := lane_length / 6
            for sample_index in 1 ..= 6 {
                amount := f32(sample_index) / 6
                point := start + tangent * (lane_length * amount)
                height := terrain.sample_height(project, 0, point[0], point[1])
                if height <= project.sea_level + .6 {
                    valid = false
                    break
                }
                height_change := math.abs(height - previous_height)
                maximum_lane_grade = max(maximum_lane_grade, height_change / sample_run)
                score -= height_change * 3
                previous_height = height
            }
            // A residential terrace may undulate, but it must not silently
            // become a long stair. The short connector can absorb the climb.
            if contour_tissue && maximum_lane_grade > .115 do valid = false
            if connector_required {
                connector_grade := settlement_access_segment_max_grade(project, road_start, junction)
                if connector_grade > .18 {
                    valid = false
                } else {
                    score -= connector_grade * 20
                }
            }
            if !valid || score <= best_score do continue
            result = {
                road_start         = road_start,
                junction           = junction,
                start              = start,
                end                = end,
                tangent            = tangent,
                normal             = {-tangent[1], tangent[0]},
                half_width         = .9,
                court_radius       = 2.4,
                connector_required = connector_required,
                contour_aligned    = contour_tissue,
                valid              = true,
            }
            best_score = score
        }
    }
    return result
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
    frontage_lane := settlement_village_frontage_lane(
        plan,
        project,
        route_origin,
        route_tangent,
        route_normal,
        route_width,
        route_shoulder,
        tissue,
        plan.village_reason == .Agricultural_Terrace || plan.village_reason == .Upland_Pastoral,
        route_found &&
        plan.request.region == .Adriatic &&
        tissue != .Harbor &&
        tissue != .Fortified_Precinct &&
        tissue != .Church_Cluster &&
        tissue != .Cycladic_Accretion,
    )
    if frontage_lane.valid {
        if frontage_lane.connector_required {
            settlement_village_add_path(&result, frontage_lane.road_start, frontage_lane.junction, 1.6, .Road)
        }
        settlement_village_add_path(
            &result,
            frontage_lane.start,
            frontage_lane.end,
            frontage_lane.half_width * 2,
            frontage_lane.connector_required ? architecture.City_Alley_Terminal.None : architecture.City_Alley_Terminal.Road,
            .Public_Space,
        )
        court_half_span := frontage_lane.court_radius + .2
        settlement_village_add_path(
            &result,
            frontage_lane.end - frontage_lane.normal * court_half_span,
            frontage_lane.end + frontage_lane.normal * court_half_span,
            frontage_lane.court_radius * 2,
            .Public_Space,
            .Public_Space,
        )
    }
    common := anchor
    // Keep the common at the route junction. Earlier placement offset the
    // entire program to one side of one route, which made a village read as a
    // detached compound beside several otherwise empty road arms.
    aegean_cluster_access := false
    aegean_cluster_centers: [3][2]f32
    aegean_cluster_court_alleys := [3]int{-1, -1, -1}
    if plan.request.region == .Aegean && route_found {
        phase := f32(plan.request.seed & 0xffff) / f32(0xffff) * f32(math.TAU)
        // Cycladic dwellings are sampled around three family-scale clusters.
        // Materialize those latent centers as small courts before placing the
        // houses. Chain the courts from one road root instead of making every
        // lane meet at the common: each intermediate court then has two
        // through-lane edges plus its two frontage halves, capping the authored
        // junction at degree four.
        for cluster_index in 0 ..< len(aegean_cluster_centers) {
            cluster_angle := phase + f32(cluster_index) * f32(math.TAU / 3)
            radial := [2]f32{f32(math.cos(f64(cluster_angle))), f32(math.sin(f64(cluster_angle)))}
            court_center := common + radial * 9
            aegean_cluster_centers[cluster_index] = court_center
            court_tangent := [2]f32{-radial[1], radial[0]}
            court_alley_start := result.alley_count
            settlement_village_add_path(
                &result,
                court_center - court_tangent * 3.5,
                court_center + court_tangent * 3.5,
                3.2,
                .Public_Space,
                .Public_Space,
            )
            if result.alley_count > court_alley_start {
                aegean_cluster_court_alleys[cluster_index] = court_alley_start
            }
        }
        root_index := 0
        root_distance := f32(1e30)
        for center, center_index in aegean_cluster_centers {
            _, _, _, width, shoulder, distance, _, found := settlement_nearest_route_frame(plan, center)
            throat_length := distance - (width * .5 + shoulder + .45)
            if found && throat_length >= 5 && distance < root_distance {
                root_index, root_distance = center_index, distance
            }
        }
        root_center := aegean_cluster_centers[root_index]
        root_origin, _, root_normal, root_width, root_shoulder, _, _, root_found := settlement_nearest_route_frame(
            plan,
            root_center,
        )
        if root_found {
            direction := root_center - root_origin
            direction_length := linalg.length(direction)
            if direction_length > .01 {
                side_sign := linalg.dot(direction, root_normal) < 0 ? f32(-1) : f32(1)
                road_edge := root_origin + root_normal * side_sign * (root_width * .5 + root_shoulder + .45)
                // The root court receives both the road throat and the first
                // cluster lane. Turn its broad public-space axis square to
                // the throat so those routes meet as a legible cross/T,
                // rather than overlaying as two almost-parallel through-lines.
                court_alley_index := aegean_cluster_court_alleys[root_index]
                throat_direction := linalg.normalize(root_center - road_edge)
                if court_alley_index >= 0 && linalg.length(throat_direction) > .001 {
                    court_tangent := [2]f32{-throat_direction[1], throat_direction[0]}
                    court := &result.alleys[court_alley_index]
                    court_start, court_end := root_center - court_tangent * 3.5, root_center + court_tangent * 3.5
                    court.start_x, court.start_z = court_start[0], court_start[1]
                    court.end_x, court.end_z = court_end[0], court_end[1]
                }
                before := result.alley_count
                settlement_village_add_path(&result, road_edge, root_center, 1.8, .Road)
                aegean_cluster_access = result.alley_count > before
            }
        }
        for chain_index in 0 ..< 2 {
            first := aegean_cluster_centers[(root_index + chain_index) % 3]
            second := aegean_cluster_centers[(root_index + chain_index + 1) % 3]
            settlement_village_add_path(&result, first, second, 1.6)
        }
    }
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
    resource_route_origin, _, resource_route_normal, resource_route_width, resource_route_shoulder, _, _, resource_route_found :=
        settlement_nearest_route_frame(plan, resource_center)
    workyard_valid := false
    harbor_quay_valid := false
    harbor_quay_tangent := [2]f32{-resource_direction[1], resource_direction[0]}
    if linalg.length(harbor_quay_tangent) > .001 {
        harbor_quay_tangent = linalg.normalize(harbor_quay_tangent)
    } else {
        harbor_quay_tangent = route_tangent
    }
    harbor_quay_start, harbor_quay_end := resource_center, resource_center
    harbor_quay_half_width := f32(1.6)
    if resource_route_found &&
       terrain.sample_height(project, 0, resource_center[0], resource_center[1]) > project.sea_level + .6 {
        direction := resource_center - resource_route_origin
        direction_length := linalg.length(direction)
        if direction_length > .01 {
            side_sign := linalg.dot(direction, resource_route_normal) < 0 ? f32(-1) : f32(1)
            outward := resource_route_normal * side_sign
            road_edge := resource_route_origin + outward * (resource_route_width * .5 + resource_route_shoulder + .45)
            connector_length := linalg.length(resource_center - road_edge)
            connector_grade := settlement_access_segment_max_grade(project, road_edge, resource_center)
            if connector_length >= 5 && connector_length <= 65 && connector_grade <= .16 {
                settlement_village_add_path(&result, road_edge, resource_center, 2.0, .Road, .Public_Space)
                connector_tangent := linalg.normalize(resource_center - road_edge)
                if plan.village_reason == .Harbor_Fishery {
                    quay_half_spans := [2]f32{28, 22}
                    for quay_half_span in quay_half_spans {
                        candidate_start := resource_center - harbor_quay_tangent * quay_half_span
                        candidate_end := resource_center + harbor_quay_tangent * quay_half_span
                        start_height := terrain.sample_height(project, 0, candidate_start[0], candidate_start[1])
                        end_height := terrain.sample_height(project, 0, candidate_end[0], candidate_end[1])
                        quay_grade := settlement_access_segment_max_grade(project, candidate_start, candidate_end)
                        if start_height <= project.sea_level + .6 ||
                           end_height <= project.sea_level + .6 ||
                           quay_grade > .10 {
                            continue
                        }
                        harbor_quay_start, harbor_quay_end = candidate_start, candidate_end
                        settlement_village_add_path(
                            &result,
                            harbor_quay_start,
                            harbor_quay_end,
                            harbor_quay_half_width * 2,
                            .Public_Space,
                            .Public_Space,
                        )
                        harbor_quay_valid = true
                        break
                    }
                }
                if !harbor_quay_valid {
                    yard_tangent := [2]f32{-connector_tangent[1], connector_tangent[0]}
                    yard_half_span := f32(4.2)
                    settlement_village_add_path(
                        &result,
                        resource_center - yard_tangent * yard_half_span,
                        resource_center + yard_tangent * yard_half_span,
                        4.4,
                        .Public_Space,
                        .Public_Space,
                    )
                }
                workyard_valid = true
            }
        }
    }
    for purpose, program_index in program[:program_count] {
        dwelling_index := program_index - 2
        cohort_center := common
        cohort_route_index := -1
        if plan.growth_event_count > 0 {
            // Consume the historical sequence in order, spreading the fixed
            // village program across accepted frontages instead of asking
            // every household to rediscover the nearest arm afterward.
            cohort_event_index := min(
                program_index * plan.growth_event_count / max(program_count, 1),
                plan.growth_event_count - 1,
            )
            cohort_event := plan.growth_events[cohort_event_index]
            cohort_center = (cohort_event.frontage_start + cohort_event.frontage_finish) * .5
            cohort_route_index = cohort_event.route_index
        }
        frontage, depth := settlement_village_purpose_dimensions(purpose, plan.request.region, rng)
        best_x, best_z, best_rotation, best_score := f32(0), f32(0), f32(0), f32(1e30)
        best_route_index := -1
        best_frontage_kind := Settlement_Village_Frontage_Kind.None
        best_court_outward: [2]f32
        resource_slot := 0
        for prior_purpose in program[:program_index] {
            if prior_purpose == .Barn_Granary ||
               prior_purpose == .Storehouse ||
               prior_purpose == .Mill ||
               prior_purpose == .Fishery {
                resource_slot += 1
            }
        }
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
                radius_low, radius_high = 22, 48
            case .Barn_Granary, .Storehouse, .Mill, .Fishery:
                radius_low, radius_high = 30, 54
            case .Dwelling:
                // The authored lane and terminal court receive the first ten
                // households. Larger village programs still need a modest
                // outer frontage reserve rather than silently dropping the
                // final home when those fixed sites are occupied.
                radius_high = 44
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
                radius_low, radius_high = aegean_form ? f32(5) : f32(8), aegean_form ? f32(28) : f32(38)
            }
            if plan.village_reason == .Harbor_Fishery && (purpose == .Inn_Shop || purpose == .Workshop) {
                radius_low, radius_high = aegean_form ? f32(7) : f32(9), aegean_form ? f32(24) : f32(27)
            }
            if plan.village_reason == .Agricultural_Terrace && purpose == .Farmstead {
                radius_low, radius_high = aegean_form ? f32(18) : f32(25), aegean_form ? f32(38) : f32(44)
            }
            if aegean_cluster_access && (purpose == .Inn_Shop || purpose == .Workshop) {
                // The civic pair belongs on the outer edge of the court
                // chain, not in the three reserved court centers. Apply this
                // after reason-specific bands so a harbor does not collapse
                // both anchors back into the occupied seven-metre core.
                radius_low, radius_high = 30, 70
            }
            resource_purpose :=
                purpose == .Barn_Granary || purpose == .Storehouse || purpose == .Mill || purpose == .Fishery
            if resource_purpose {
                // A working yard is a focus, not a tiny packing circle. Allow
                // later barns and stores to occupy its outer edge while their
                // access paths continue to share the cart connector.
                radius_low, radius_high = aegean_form ? f32(6) : f32(7), f32(34)
            }
            amount := f32(candidate_index / 12) / 12
            radius := radius_low + (radius_high - radius_low) * clamp(amount, 0, 1)
            placement_center := resource_purpose ? resource_center : cohort_center
            if aegean_form && purpose == .Dwelling && cohort_route_index < 0 {
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
            lane_frontage_candidate :=
                frontage_lane.valid &&
                purpose == .Dwelling &&
                dwelling_index >= 0 &&
                dwelling_index < 6 &&
                candidate_index < 24
            court_frontage_candidate :=
                frontage_lane.valid &&
                purpose == .Dwelling &&
                dwelling_index >= 6 &&
                dwelling_index < 10 &&
                candidate_index < 32
            harbor_quay_candidate := harbor_quay_valid && resource_purpose && resource_slot < 4 && candidate_index < 32
            lane_side := f32(1)
            if lane_frontage_candidate {
                lane_side = dwelling_index & 1 == 0 ? f32(-1) : f32(1)
                station := f32(8 + (dwelling_index / 2) * 21)
                // Small deterministic retries allow the reserved frontage to
                // accommodate sampled footprints and nearby pre-existing
                // obstacles without dissolving into unrelated radial sites.
                station += f32(candidate_index / 8) * 1.25
                setback := frontage_lane.half_width + 1.35 + depth * .5
                center :=
                    frontage_lane.start +
                    frontage_lane.tangent * station +
                    frontage_lane.normal * (setback * lane_side)
                x, z = center[0], center[1]
            } else if court_frontage_candidate {
                court_index := dwelling_index - 6
                // Allocate opposite sides first so a two-house court does not
                // crowd both plots into the same quadrant. Later households
                // fill the intermediate frontage positions.
                court_angles := [4]f32{-1.28, 1.28, -.43, .43}
                court_angle_retries := [8]f32{0, .06, -.06, .12, -.12, .18, -.18, .24}
                angle_from_lane :=
                    court_angles[court_index] + court_angle_retries[candidate_index % len(court_angle_retries)]
                court_outward :=
                    frontage_lane.tangent * f32(math.cos(f64(angle_from_lane))) +
                    frontage_lane.normal * f32(math.sin(f64(angle_from_lane)))
                retry_offset := f32(candidate_index / 8) * .65
                distance := frontage_lane.court_radius + 1.35 + depth * .5 + retry_offset
                center := frontage_lane.end + court_outward * distance
                x, z = center[0], center[1]
            } else if harbor_quay_candidate {
                quay_stations := [4]f32{-21, 21, -7, 7}
                station := quay_stations[resource_slot]
                station += f32(candidate_index / 8) * .65 * (resource_slot & 1 == 0 ? f32(-1) : f32(1))
                inland := common - resource_center
                if linalg.length(inland) > .001 {
                    inland = linalg.normalize(inland)
                } else {
                    inland = -resource_direction
                }
                setback := harbor_quay_half_width + 1.2 + depth * .5
                center := resource_center + harbor_quay_tangent * station + inland * setback
                x, z = center[0], center[1]
            }
            candidate_route_origin, candidate_route_tangent, candidate_route_normal, candidate_route_width, candidate_route_shoulder, candidate_route_distance, candidate_route_index, candidate_route_found :=
                settlement_nearest_route_frame(plan, {x, z}, resource_purpose ? -1 : cohort_route_index)
            if candidate_route_found &&
               !resource_purpose &&
               purpose != .Farmstead &&
               !lane_frontage_candidate &&
               !court_frontage_candidate {
                desired_setback :=
                    candidate_route_width * .5 +
                    candidate_route_shoulder +
                    depth * .5 +
                    (aegean_form ? f32(1.2) : f32(1.8))
                side :=
                    (x - candidate_route_origin[0]) * candidate_route_normal[0] + (z - candidate_route_origin[1]) * candidate_route_normal[1] >= 0 ? f32(1) : f32(-1)
                frontage_x := candidate_route_origin[0] + candidate_route_normal[0] * desired_setback * side
                frontage_z := candidate_route_origin[1] + candidate_route_normal[1] * desired_setback * side
                frontage_pull := aegean_form ? f32(.30) : f32(.50)
                if plan.village_reason == .Harbor_Fishery {
                    frontage_pull = aegean_form ? f32(.55) : f32(.72)
                }
                x += (frontage_x - x) * frontage_pull
                z += (frontage_z - z) * frontage_pull
                candidate_route_origin, candidate_route_tangent, candidate_route_normal, candidate_route_width, candidate_route_shoulder, candidate_route_distance, candidate_route_index, candidate_route_found =
                    settlement_nearest_route_frame(plan, {x, z}, cohort_route_index)
            }
            rotation := angle + f32(math.PI * .5)
            civic_route_frontage :=
                candidate_route_found && !resource_purpose && (purpose == .Inn_Shop || purpose == .Workshop)
            if lane_frontage_candidate {
                rotation = f32(math.atan2(f64(frontage_lane.tangent[1]), f64(frontage_lane.tangent[0])))
                rotation = settlement_rotation_face_point(
                    rotation,
                    {x, z},
                    frontage_lane.start +
                    frontage_lane.tangent * linalg.dot([2]f32{x, z} - frontage_lane.start, frontage_lane.tangent),
                )
            } else if court_frontage_candidate {
                court_outward := linalg.normalize([2]f32{x, z} - frontage_lane.end)
                rotation = f32(math.atan2(f64(court_outward[1]), f64(court_outward[0]))) + math.PI * .5
                rotation = settlement_rotation_face_point(rotation, {x, z}, frontage_lane.end)
            } else if harbor_quay_candidate {
                rotation = f32(math.atan2(f64(harbor_quay_tangent[1]), f64(harbor_quay_tangent[0])))
                quay_projection :=
                    resource_center +
                    harbor_quay_tangent * linalg.dot([2]f32{x, z} - resource_center, harbor_quay_tangent)
                rotation = settlement_rotation_face_point(rotation, {x, z}, quay_projection)
            } else if civic_route_frontage {
                // Inns and workshops are public-facing anchors. Even in
                // contour-set Aegean fabric, their entrance addresses the
                // street before the remaining footprint follows the slope.
                rotation = f32(math.atan2(f64(candidate_route_tangent[1]), f64(candidate_route_tangent[0])))
            } else if cohort_route_index >= 0 && candidate_route_found && !resource_purpose {
                rotation = f32(math.atan2(f64(candidate_route_tangent[1]), f64(candidate_route_tangent[0])))
            } else if aegean_form && gradient_length > .001 {
                // Present long façades along the contour, producing stepped
                // court clusters rather than a miniature roadside suburb.
                rotation = f32(math.atan2(f64(-gradient[0]), f64(gradient[1])))
            } else if candidate_route_found && !resource_purpose {
                rotation = f32(math.atan2(f64(candidate_route_tangent[1]), f64(candidate_route_tangent[0])))
            } else if gradient_length > .001 {
                rotation = f32(math.atan2(f64(-gradient[0]), f64(gradient[1])))
            }
            if (civic_route_frontage || (cohort_route_index >= 0 && candidate_route_found)) && !resource_purpose {
                rotation = settlement_rotation_face_point(rotation, {x, z}, candidate_route_origin)
            } else {
                rotation = settlement_rotation_face_point(rotation, {x, z}, placement_center)
            }
            if !settlement_structure_footprint_on_land(project, x, z, frontage, depth, rotation) do continue
            height_at_site := terrain.sample_height(project, 0, x, z)
            separation := purpose == .Dwelling ? f32(2.2) : f32(3.2)
            if aegean_form do separation = purpose == .Dwelling ? f32(1.5) : f32(2.8)
            if aegean_cluster_access && (purpose == .Inn_Shop || purpose == .Workshop) {
                separation = 2
            }
            if plan.village_reason == .Harbor_Fishery && purpose == .Dwelling {
                separation = aegean_form ? f32(1.1) : f32(.75)
            }
            if resource_purpose do separation = aegean_form ? f32(2.0) : f32(2.2)
            if harbor_quay_candidate do separation = .75
            if !settlement_structure_clear(project, &result, x, z, frontage, depth, rotation, separation) do continue
            candidate_structure := terrain.structure_make(x, z, frontage, depth, 0, 1)
            candidate_structure.width, candidate_structure.depth = frontage, depth
            candidate_structure.rotation = rotation
            if !settlement_structure_committed_roads_clear(project, candidate_structure) do continue
            if !settlement_structure_plazas_clear(plan, candidate_structure) do continue
            if settlement_access_structure_overlaps_alley(&result, candidate_structure) do continue
            if court_frontage_candidate {
                // A court plot is only valid when its entrance can actually
                // address the court. Reserving this threshold during site
                // selection prevents an earlier lane house from forcing the
                // eventual door into a long A* detour.
                candidate_door := settlement_structure_front_door_point(candidate_structure, .22, project)
                candidate_court_outward := linalg.normalize([2]f32{x, z} - frontage_lane.end)
                candidate_threshold := frontage_lane.end + candidate_court_outward * frontage_lane.court_radius
                if linalg.length(candidate_threshold - candidate_door) < .4 ||
                   settlement_access_segment_max_grade(project, candidate_door, candidate_threshold) > .65 ||
                   !settlement_access_segment_clear(&result, candidate_door, candidate_threshold, .6, -1) {
                    continue
                }
            }
            score := radius
            if lane_frontage_candidate {
                // A reserved public frontage is a stronger settlement fact
                // than proximity to a coincidental main-road segment.
                score = f32(candidate_index) * .02
            } else if court_frontage_candidate {
                score = f32(candidate_index) * .02
            } else if candidate_route_found {
                // Favor a legible street wall without forcing a rigid ribbon.
                // Frontage is measured from the building center, so include
                // half its depth when choosing the desired setback.
                desired_setback :=
                    candidate_route_width * .5 +
                    candidate_route_shoulder +
                    depth * .5 +
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
                if !resource_purpose && candidate_route_index >= 0 && candidate_route_index < plan.route_count {
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
                        score += f32(route_occupancy[candidate_route_index]) * (aegean_form ? f32(3.2) : f32(4.5))
                    }
                }
            }
            if harbor_quay_candidate {
                score = f32(candidate_index) * .02
            } else if resource_purpose {
                // Barns, mills, stores, and fisheries share one legible
                // working yard instead of becoming unrelated outer outliers.
                score = radius * .75
            }
            height_error := math.abs(height_at_site - terrain.sample_height(project, 0, common[0], common[1]))
            score += height_error * (aegean_form ? f32(2.4) : f32(1.4))
            if score >= best_score do continue
            best_x, best_z, best_rotation, best_score = x, z, rotation, score
            best_route_index = candidate_route_index
            best_frontage_kind =
                lane_frontage_candidate ? Settlement_Village_Frontage_Kind.Lane : court_frontage_candidate ? Settlement_Village_Frontage_Kind.Court : harbor_quay_candidate ? Settlement_Village_Frontage_Kind.Quay : Settlement_Village_Frontage_Kind.None
            if court_frontage_candidate {
                best_court_outward = linalg.normalize([2]f32{x, z} - frontage_lane.end)
            }
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
        structure.building = architecture.architecture_identity(
            {
                region = settlement_building_region(plan.request.region),
                purpose = settlement_building_purpose(purpose),
                tissue = settlement_architecture_tissue(tissue),
                density = density,
                attached = false,
                frontage = frontage,
                depth = depth,
                route = best_frontage_kind == .Quay ? architecture.Context_Route.Waterfront : best_frontage_kind != .None ? architecture.Context_Route.Lane : purpose == .Inn_Shop ? architecture.Context_Route.Street : architecture.Context_Route.Unspecified,
                waterfront = plan.village_reason == .Harbor_Fishery,
                purpose_explicit = true,
            },
            seed,
        )
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
        parcel_center := [2]f32{best_x, best_z}
        parcel_half_frontage, parcel_half_depth := half_frontage, half_depth
        if best_frontage_kind == .Lane {
            lane_projection :=
                frontage_lane.start +
                frontage_lane.tangent * linalg.dot(parcel_center - frontage_lane.start, frontage_lane.tangent)
            side_sign := linalg.dot(parcel_center - lane_projection, frontage_lane.normal) < 0 ? f32(-1) : f32(1)
            parcel.frontage_width = frontage + 2.2
            parcel.depth = depth + 3.55
            parcel_half_frontage = parcel.frontage_width * .5
            parcel_half_depth = parcel.depth * .5
            parcel_center =
                lane_projection + frontage_lane.normal * side_sign * (frontage_lane.half_width + parcel_half_depth)
            tangent = frontage_lane.tangent
            normal = frontage_lane.normal * side_sign
        } else if best_frontage_kind == .Court {
            parcel.frontage_width = frontage + 2.2
            parcel.depth = depth + 3.55
            parcel_half_frontage = parcel.frontage_width * .5
            parcel_half_depth = parcel.depth * .5
            normal = best_court_outward
            tangent = {normal[1], -normal[0]}
            parcel_center = frontage_lane.end + normal * (frontage_lane.court_radius + parcel_half_depth)
        } else if best_frontage_kind == .Quay {
            quay_projection :=
                resource_center +
                harbor_quay_tangent * linalg.dot(parcel_center - resource_center, harbor_quay_tangent)
            inland := common - resource_center
            if linalg.length(inland) > .001 {
                inland = linalg.normalize(inland)
            } else {
                inland = -resource_direction
            }
            parcel.frontage_width = frontage + 1.5
            parcel.depth = depth + 3.2
            parcel_half_frontage = parcel.frontage_width * .5
            parcel_half_depth = parcel.depth * .5
            parcel_center = quay_projection + inland * (harbor_quay_half_width + parcel_half_depth)
            tangent = harbor_quay_tangent
            normal = inland
        }
        parcel.corners = {
            parcel_center - tangent * parcel_half_frontage - normal * parcel_half_depth,
            parcel_center + tangent * parcel_half_frontage - normal * parcel_half_depth,
            parcel_center + tangent * parcel_half_frontage + normal * parcel_half_depth,
            parcel_center - tangent * parcel_half_frontage + normal * parcel_half_depth,
        }
        append(&result.structures, structure)
        append(&result.parcels, parcel)
        if purpose == .Inn_Shop do inn_index = result.count
        if purpose == .Fishery || purpose == .Mill || purpose == .Storehouse do resource_index = result.count
        plan.ordinary_purposes[plan.ordinary_purpose_count] = purpose
        plan.ordinary_purpose_count += 1
        if best_route_index >= 0 &&
           best_route_index < plan.route_count &&
           !(purpose == .Barn_Granary || purpose == .Storehouse || purpose == .Mill || purpose == .Fishery) {
            route_occupancy[best_route_index] += 1
        }
        result.count += 1
        result.parcel_count += 1
        if best_frontage_kind == .Court {
            // The terminal court and these façades are one authored
            // development event. Give each court house a short threshold now
            // instead of asking the later per-door A* pass to rediscover the
            // public space around already placed neighbors. Project onto the
            // court centerline so the access graph has an explicit shared
            // node, while the court's broad surface carries movement between
            // the individual thresholds.
            structure_index := result.count - 1
            door := settlement_structure_front_door_point(result.structures[structure_index], .22, project)
            threshold := frontage_lane.end + best_court_outward * frontage_lane.court_radius
            court_half_span := frontage_lane.court_radius + .2
            court_along := clamp(
                linalg.dot(threshold - frontage_lane.end, frontage_lane.normal),
                -court_half_span,
                court_half_span,
            )
            court_goal := frontage_lane.end + frontage_lane.normal * court_along
            threshold_half_width := f32(.6)
            if linalg.length(threshold - door) >= .4 &&
               settlement_access_segment_clear(&result, door, threshold, threshold_half_width, structure_index) {
                append(
                    &result.alleys,
                    architecture.City_Alley {
                        start_x = door[0],
                        start_z = door[1],
                        end_x = threshold[0],
                        end_z = threshold[1],
                        half_width = threshold_half_width,
                        start_terminal = .Door,
                    },
                )
                result.alley_count += 1
                if linalg.length(court_goal - threshold) > .05 {
                    append(
                        &result.alleys,
                        architecture.City_Alley {
                            start_x = threshold[0],
                            start_z = threshold[1],
                            end_x = court_goal[0],
                            end_z = court_goal[1],
                            half_width = threshold_half_width,
                            end_terminal = .Public_Space,
                        },
                    )
                    result.alley_count += 1
                }
            }
        }
    }
    settlement_plan_record_built_group(plan, &result, 0, result.count, tissue)
    if route_found && !aegean_cluster_access {
        destination := common
        if inn_index >= 0 {
            destination = settlement_structure_approach_point(result.structures[inn_index], route_origin)
        }
        start_offset := route_width * .5 + route_shoulder + .5
        delta := destination - route_origin
        length := linalg.length(delta)
        if length > .01 {
            side_sign := linalg.dot(delta, route_normal) < 0 ? f32(-1) : f32(1)
            outward := route_normal * side_sign
            start := route_origin + outward * start_offset
            verge := start + outward * .8
            settlement_village_add_path(&result, start, verge, 1.6, .Road)
            settlement_village_add_path(&result, verge, destination, 1.6)
        }
    }
    if resource_index >= 0 && !workyard_valid {
        resource := result.structures[resource_index]
        destination := settlement_structure_approach_point(resource, common)
        settlement_village_add_path(&result, common, destination, 1.25)
    }
    core_half_x, core_half_z := aegean_form ? f32(6) : f32(8), aegean_form ? f32(5) : f32(6)
    settlement_plan_record_terrain_edit(plan, project, .Plaza, common[0], common[1], core_half_x, core_half_z, 2.5)
    if aegean_form && route_found && !aegean_cluster_access {
        // A short, broad alley renders as the paved Cycladic court. Adriatic
        // villages retain the smoothed but grassy common as a village green.
        court_start := [2]f32{common[0] - route_tangent[0] * core_half_x, common[1] - route_tangent[1] * core_half_x}
        court_end := [2]f32{common[0] + route_tangent[0] * core_half_x, common[1] + route_tangent[1] * core_half_x}
        settlement_village_add_path(&result, court_start, court_end, core_half_z * 1.45)
    }
    _ = settlement_plan_generate_building_access(plan, project, &result, rng, 120)
    return result
}

settlement_town_district_building_target :: proc(district: Settlement_Neighborhood) -> int {
    target := 1
    if district.age < .78 do target = 2
    if district.density > .24 && district.age < .62 do target = 3
    if district.density > .38 && district.age < .40 do target = 4
    return target
}

settlement_hero_config_for_scale :: proc(kind: hero.Kind, scale: Settlement_Scale) -> hero.Config {
    config := hero.defaults(kind)
    if scale == .Town {
        // Keep civic anchors legible without letting two city-sized compounds
        // consume the silhouette of a compact Riviera town. These remain
        // comfortably above the hero generator's valid minimum dimensions.
        config.frontage = max(config.frontage * .84, f32(18))
        config.depth = max(config.depth * .87, f32(12))
        config.arcade_depth = min(config.arcade_depth, config.depth * .54)
    }
    return config
}

settlement_town_frontage_side_sign :: proc(
    district_center, route_origin, route_normal: [2]f32,
    hash: u32,
) -> f32 {
    side_distance := linalg.dot(district_center - route_origin, route_normal)
    if math.abs(side_distance) > .75 do return side_distance < 0 ? f32(-1) : f32(1)
    return hash & 1 == 0 ? f32(-1) : f32(1)
}

settlement_town_try_pair_singleton :: proc(
    settlement: ^Settlement_Plan,
    project: ^terrain.Project,
    city: ^architecture.City_Plan,
    structure_index: int,
    district: Settlement_Neighborhood,
) -> bool {
    if settlement == nil || project == nil || city == nil ||
       structure_index < 0 || structure_index >= city.count {
        return false
    }
    first := city.structures[structure_index]
    if settlement_structure_is_landmark(first) || buildings.is_landmark(first.building) do return false
    minimum_height, maximum_height := settlement_height_band(settlement.request.region, .Town)
    if first.height > maximum_height + .01 do return false
    // Rescue the missing address with a genuinely narrow infill house. The
    // former near-copy (.82 x .92) usually failed in exactly the constrained
    // frontage gaps this pass exists to repair, leaving a detached singleton
    // surrounded by lawn. Riviera terraces comfortably step down to a four-
    // metre facade and a shallower rear wall while retaining the street line.
    frontage := clamp(first.width * .68, f32(4), f32(7))
    depth := clamp(first.depth * .78, f32(8), f32(16))
    frontage, depth = settlement_normalize_ordinary_building_dimensions(frontage, depth)
    separation := settlement_building_separation(
        settlement.request.region,
        .Town,
        district.age,
        true,
    )
    tangent := [2]f32{f32(math.cos(f64(first.rotation))), f32(math.sin(f64(first.rotation)))}
    pitch := (first.width + frontage) * .5 + separation + .2
    preferred_side := linalg.dot(district.center - [2]f32{first.center_x, first.center_z}, tangent) < 0 ? f32(-1) : f32(1)
    sides := [2]f32{preferred_side, -preferred_side}
    for side in sides {
        point := [2]f32{first.center_x, first.center_z} + tangent * pitch * side
        if settlement_nearest_committed_road_distance(project, point) > 34 ||
           !settlement_structure_footprint_on_land(project, point[0], point[1], frontage, depth, first.rotation) {
            continue
        }
        rescue_height := architecture.facade_fitted_height_in_range(
            clamp(first.height, minimum_height, maximum_height),
            minimum_height,
            maximum_height,
        )
        candidate := terrain.structure_make(point[0], point[1], frontage, depth, 0, rescue_height)
        candidate.width = frontage
        candidate.depth = depth
        candidate.height = rescue_height
        candidate.rotation = first.rotation
        if !settlement_structure_routes_clear(settlement, candidate) ||
           !settlement_structure_committed_roads_clear(project, candidate) ||
           !settlement_structure_plazas_clear(settlement, candidate) ||
           !settlement_structure_clear(
               project,
               city,
               point[0],
               point[1],
               frontage,
               depth,
               first.rotation,
               separation,
           ) {
            continue
        }
        // A rescued terrace mate should share the established facade/roof
        // grammar. A fresh procedural seed can promote the smaller neighbor
        // into an unrelated tall variant during architecture commit.
        seed := first.seed
        candidate.kind = .Architecture
        candidate.seed = seed
        candidate.color = architecture.architecture_color(seed, false)
        if settlement.request.region == .Aegean do candidate.color = {236, 232, 216, 255}
        candidate.building = first.building
        parcel := architecture.City_Parcel {
            frontage_width = frontage,
            depth          = depth,
            density        = clamp(district.density, 0, 1),
            seed           = seed,
            attached       = true,
        }
        half_frontage, half_depth := frontage * .5, depth * .5
        normal := [2]f32{-tangent[1], tangent[0]}
        parcel.corners = {
            point - tangent * half_frontage - normal * half_depth,
            point + tangent * half_frontage - normal * half_depth,
            point + tangent * half_frontage + normal * half_depth,
            point - tangent * half_frontage + normal * half_depth,
        }
        append(&city.structures, candidate)
        append(&city.parcels, parcel)
        city.count += 1
        city.parcel_count += 1
        if settlement.ordinary_purpose_count < len(settlement.ordinary_purposes) {
            settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Dwelling
            switch candidate.building.purpose {
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
            case .Dwelling:
            }
            settlement.ordinary_purpose_count += 1
        }
        return true
    }
    return false
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
    hero_post_office_placed := false
    hero_clinic_placed := false
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
        if settlement.request.scale == .Town {
            // A single oversized object per macro cell produces suburban
            // dots and can never register a built block. Mature town tissue
            // instead gets short runs of narrow houses sharing one frontage.
            target = settlement_town_district_building_target(district)
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
            if result.count - district_start >= target do break
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
            } else if settlement.request.scale == .Town {
                // Adriatic town fabric is made from narrow hillside addresses,
                // not the broad apartment and palazzo parcels used by City.
                // The old city limits produced 350–400 m² ordinary slabs that
                // visually crowded roads even when their collision clearance
                // was valid.
                median_frontage, frontage_low, frontage_high = 7, 4.2, 12.5
                depth_low, depth_high = 8, 20
            } else if settlement.request.scale == .Village {
                median_frontage, frontage_low, frontage_high = 7.5, 4.5, 13
                depth_low, depth_high = 6, 18
            }
            frontage := settlement_sample_lognormal(rng, median_frontage, .24, frontage_low, frontage_high)
            ratio_mode, ratio_high := f32(1.65), f32(2.5)
            if settlement.request.region == .Aegean {
                ratio_mode, ratio_high = 1.25, 1.55
            } else if settlement.request.scale == .Town {
                ratio_mode, ratio_high = 1.5, 2.1
            } else if settlement.request.scale == .Village {
                ratio_mode, ratio_high = 1.35, 1.60
            }
            depth := clamp(
                frontage * settlement_sample_triangular(rng, 1.25, ratio_mode, ratio_high),
                depth_low,
                depth_high,
            )
            // Architecture doors and their access paths use the frontage
            // face. Cities and villages present the broad elevation, while
            // Riviera towns retain narrow-fronted, deep row-house parcels so
            // several addresses can compose a continuous street wall.
            if depth > frontage && settlement.request.scale != .Town {
                frontage, depth = depth, frontage
            }
            frontage, depth = settlement_normalize_ordinary_building_dimensions(frontage, depth)
            hero_candidate := !hero_post_office_placed || !hero_clinic_placed
            hero_kind := !hero_post_office_placed ? hero.Kind.Post_Office : hero.Kind.Clinic
            if hero_candidate {
                // Civic buildings are program inputs, not identities painted
                // onto whatever ordinary parcel happens to be large enough.
                // Give placement, collision, terrain, and access planning the
                // purpose-built footprint from the outset.
                hero_config := settlement_hero_config_for_scale(hero_kind, settlement.request.scale)
                frontage = hero_config.frontage
                depth = hero_config.depth
            }
            x, z, rotation: f32
            attached :=
                settlement_rng_unit(rng) <
                settlement_attachment_probability(district.age, settlement.request.scale)
            separation := settlement_building_separation(
                settlement.request.region,
                settlement.request.scale,
                district.age,
                attached,
            )
            frontage_reach :=
                settlement.request.scale == .City ? f32(30) : settlement.request.scale == .Town ? f32(32) : f32(18)
            if settlement.request.region == .Adriatic {
                frontage_reach =
                    settlement.request.scale == .City ? f32(24) : settlement.request.scale == .Town ? f32(32) : f32(16)
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
                // Keep a macro cell's houses on one side of its street and
                // compose them as a short terrace run. Alternating every slot
                // across the carriageway produced isolated zig-zag houses,
                // made a two-house group span an entire block, and forced
                // separate spoke paths to each threshold.
                centered_slot := f32(layout_index) - f32(target - 1) * .5
                signed_row := centered_slot * (frontage + separation)
                // The projected macro-cell centers otherwise line up at
                // identical stations on long routes. Drift each frontage
                // group within its own cell, without changing which street it
                // addresses.
                station_noise := f32((hash ~ u32(0x27d4eb2d)) & 0xffff) / f32(0xffff) - .5
                signed_row += station_noise * district.radius * .25
                // Once an ordinary frontage run has started, place the next
                // successful house from the previous house's actual edge.
                // Deriving every station independently from its own random
                // width leaves conspicuous lawn slots between otherwise
                // attached rowhouses. Keep collision retries free to seek a
                // new station, and keep purpose-built civic parcels detached.
                if layout_index == placement_index && placement_index > 0 && !hero_candidate {
                    previous := result.structures[result.count - 1]
                    if !settlement_structure_is_landmark(previous) {
                        previous_station :=
                            (previous.center_x - route_origin[0]) * route_tangent[0] +
                            (previous.center_z - route_origin[1]) * route_tangent[1]
                        signed_row = previous_station + previous.width * .5 + frontage * .5 + separation
                    }
                }
                side_sign := hash & 1 == 0 ? f32(-1) : f32(1)
                if settlement.request.scale == .Town {
                    // Keep a cell's terrace on the side of the street where
                    // its growth tissue actually lives. Randomly reflecting
                    // whole groups across the route leaves alternating empty
                    // wedges and makes neighboring infill collide.
                    side_sign = settlement_town_frontage_side_sign(
                        district.center,
                        route_origin,
                        route_normal,
                        hash,
                    )
                }
                setback_noise := f32((hash >> 12) & 255) / 255
                setback_variation := (.15 + district.age * .65) * setback_noise
                setback := route_width * .5 + route_shoulder + .8 + depth * .5 + separation * .5 + setback_variation
                x = route_origin[0] + route_tangent[0] * signed_row + route_normal[0] * setback * side_sign
                z = route_origin[1] + route_tangent[1] * signed_row + route_normal[1] * setback * side_sign
                rotation = architecture.architecture_frontage_rotation(route_tangent[0], route_tangent[1], side_sign)
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
                rotation = settlement_rotation_face_point(rotation, {x, z}, group_center)
            }
            if settlement.request.scale == .Town &&
               settlement_nearest_committed_road_distance(project, {x, z}) > 34 {
                // Optional planned lanes may be simplified out or declined
                // when the shared road graph reaches its budget. Never place
                // town fabric against such a paper street: the access repair
                // would otherwise draw a conspicuous 60–100 m footpath to the
                // nearest road that actually renders.
                settlement_plan_record_rejected_site(settlement, x, z, frontage, depth, rotation)
                continue
            }
            if !settlement_structure_footprint_on_land(project, x, z, frontage, depth, rotation) {
                settlement_plan_record_rejected_site(settlement, x, z, frontage, depth, rotation)
                continue
            }
            candidate_structure := terrain.structure_make(x, z, frontage, depth, 0, .25)
            candidate_structure.width = frontage
            candidate_structure.depth = depth
            candidate_structure.rotation = rotation
            if !settlement_structure_routes_clear(settlement, candidate_structure) ||
               !settlement_structure_committed_roads_clear(project, candidate_structure) {
                settlement_plan_record_rejected_site(settlement, x, z, frontage, depth, rotation)
                continue
            }
            if !settlement_structure_plazas_clear(settlement, candidate_structure) {
                settlement_plan_record_rejected_site(settlement, x, z, frontage, depth, rotation)
                continue
            }
            if !settlement_structure_clear(project, &result, x, z, frontage, depth, rotation, separation) {
                settlement_plan_record_rejected_site(settlement, x, z, frontage, depth, rotation)
                continue
            }
            seed := settlement_rng_u32(rng)
            hero_plan: hero.Plan
            if hero_candidate {
                hero_config := settlement_hero_config_for_scale(hero_kind, settlement.request.scale)
                hero_config.frontage = frontage
                hero_config.depth = depth
                hero_plan = hero.generate(seed, hero_config)
            }
            density := clamp(district.density, 0, 1)
            height_roll := settlement_rng_unit(rng)
            height_factor := clamp(density * .78 + height_roll * .22, 0, 1)
            if settlement.request.region == .Aegean {
                // Aegean settlements need occasional upper rooms and roof
                // terraces stepping above the predominantly low fabric. The
                // former range could never cross the 7.2 m module threshold
                // at Town density, so every ordinary house became 4.8 m.
                height_factor = clamp(density * .90 + height_roll * .42, 0, 1)
            }
            height := minimum_height + (maximum_height - minimum_height) * height_factor
            height = architecture.facade_fitted_height_in_range(height, minimum_height, maximum_height)
            if hero_candidate do height = hero_plan.arcade_height + hero_plan.roof_height + hero_plan.monitor_height
            structure := terrain.structure_make(x, z, frontage, depth, 0, height)
            structure.kind = .Architecture
            structure.seed = seed
            structure.width = frontage
            structure.depth = depth
            structure.height = height
            structure.rotation = rotation
            identity := architecture.architecture_identity(
                {
                    region = settlement_building_region(settlement.request.region),
                    tissue = settlement_architecture_tissue(district.tissue),
                    density = density,
                    attached = attached,
                    frontage = frontage,
                    depth = depth,
                    route = route_found ? architecture.Context_Route.Street : architecture.Context_Route.Unspecified,
                    waterfront = district.tissue == .Harbor,
                    purpose_explicit = false,
                },
                seed,
            )
            if hero_candidate {
                landmark_kind := buildings.Landmark_Kind.Post_Office
                if hero_kind == .Clinic do landmark_kind = .Clinic
                identity = architecture.architecture_identity(
                    {
                        region = settlement_building_region(settlement.request.region),
                        landmark_kind = landmark_kind,
                        frontage = frontage,
                        depth = depth,
                    },
                    seed,
                )
                if hero_kind == .Clinic {
                    hero_clinic_placed = true
                } else {
                    hero_post_office_placed = true
                }
            }
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
            append(&result.structures, structure)
            if settlement.ordinary_purpose_count < len(settlement.ordinary_purposes) {
                if hero_candidate {
                    settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Inn_Shop
                } else {
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
                }
                settlement.ordinary_purpose_count += 1
            }
            result.count += 1
            append(&result.parcels, parcel)
            result.parcel_count += 1
        }
        if settlement.request.scale == .Town &&
           result.count - district_start == 1 &&
           district.density >= .18 &&
           district.age < .92 {
            _ = settlement_town_try_pair_singleton(
                settlement,
                project,
                &result,
                district_start,
                district,
            )
        }
        settlement_plan_record_built_group(
            settlement,
            &result,
            district_start,
            result.count - district_start,
            district.tissue,
        )
    }
    // Buildings establish the construction datum. Lightly settle steep town
    // footprints before routing passages so thresholds, stoops, and the A*
    // grade checks all observe the same finished ground that will be rendered.
    settlement_plan_prepare_block_terrain(settlement, project, &result)
    settlement_plan_seat_city(&result, project)
    settlement_plan_generate_pedestrian_access(settlement, &result, rng)
    maximum_access_length := settlement.request.scale == .City ? f32(180) : f32(150)
    _ = settlement_plan_generate_building_access(settlement, project, &result, rng, maximum_access_length)
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

settlement_alley_endpoint_degree :: proc(city_plan: ^architecture.City_Plan, point: [2]f32, half_width: f32) -> int {
    if city_plan == nil do return 0
    degree := 0
    for alley in city_plan.alleys[:city_plan.alley_count] {
        if math.abs(alley.half_width - half_width) > .05 do continue
        if settlement_alley_point_near(point, {alley.start_x, alley.start_z}) do degree += 1
        if settlement_alley_point_near(point, {alley.end_x, alley.end_z}) do degree += 1
    }
    return degree
}

settlement_access_route_class :: proc(maximum_grade, width: f32) -> Settlement_Route_Class {
    if maximum_grade >= SETTLEMENT_ACCESS_STAIR_GRADE do return .Stair
    if width >= 1.8 do return .Lane
    return .Alley
}

settlement_access_curve_grade_metrics :: proc(
    city_plan: ^architecture.City_Plan,
    project: ^terrain.Project,
    alley_indices: []int,
) -> (
    average_grade, maximum_grade: f32,
) {
    if city_plan == nil || project == nil do return
    total_length, weighted_grade := f32(0), f32(0)
    for alley_index in alley_indices {
        if alley_index < 0 || alley_index >= city_plan.alley_count do continue
        curve := settlement_access_alley_curve(city_plan, alley_index)
        sample_count := settlement_access_curve_sample_count(curve)
        previous := curve.points[0]
        previous_height := terrain.sample_height(project, 0, previous[0], previous[1])
        for sample in 1 ..= sample_count {
            current := settlement_access_curve_point(curve, f32(sample) / f32(sample_count))
            current_height := terrain.sample_height(project, 0, current[0], current[1])
            length := linalg.length(current - previous)
            if length > .01 {
                grade := math.abs(current_height - previous_height) / length
                total_length += length
                weighted_grade += grade * length
                maximum_grade = max(maximum_grade, grade)
            }
            previous, previous_height = current, current_height
        }
    }
    if total_length > .01 do average_grade = weighted_grade / total_length
    return
}

settlement_access_curve_navigation_intervals :: proc(curve: Settlement_Access_Curve) -> int {
    handle_deviation := max(
        settlement_point_segment_distance_squared(curve.points[1], curve.points[0], curve.points[3]),
        settlement_point_segment_distance_squared(curve.points[2], curve.points[0], curve.points[3]),
    )
    if handle_deviation <= .01 do return 1
    return settlement_access_curve_sample_count(curve)
}

// Preserve graph junctions while inserting spline samples. The caller chunks
// a long chain before this point, so every bend receives its requested sample
// density instead of competing with unrelated bends for the fixed payload.
settlement_access_curve_chain_geometry :: proc(
    city_plan: ^architecture.City_Plan,
    alley_indices: []int,
    chain_start: [2]f32,
) -> Settlement_Route {
    result: Settlement_Route
    if city_plan == nil || len(alley_indices) == 0 do return result
    count := min(len(alley_indices), SETTLEMENT_ROUTE_CAPACITY - 1)
    intervals: [SETTLEMENT_ROUTE_CAPACITY]int
    extra_budget := max(0, SETTLEMENT_ROUTE_CAPACITY - (count + 1))
    for alley_index, chain_index in alley_indices[:count] {
        intervals[chain_index] = 1
        curve := settlement_access_alley_curve(city_plan, alley_index)
        desired := settlement_access_curve_navigation_intervals(curve)
        added := min(max(0, desired - 1), extra_budget)
        intervals[chain_index] += added
        extra_budget -= added
    }

    result.points[0], result.count = chain_start, 1
    current := chain_start
    for alley_index, chain_index in alley_indices[:count] {
        curve := settlement_access_alley_curve(city_plan, alley_index)
        forward := settlement_alley_point_near(current, curve.points[0])
        if !forward && !settlement_alley_point_near(current, curve.points[3]) do return Settlement_Route{}
        interval_count := intervals[chain_index]
        for interval in 1 ..= interval_count {
            amount := f32(interval) / f32(interval_count)
            if !forward do amount = 1 - amount
            result.points[result.count] = settlement_access_curve_point(curve, amount)
            result.count += 1
        }
        current = result.points[result.count - 1]
    }
    return result
}

settlement_plan_import_access_route :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    geometry: Settlement_Route,
    width: f32,
    average_grade_override: f32 = -1,
    maximum_grade_override: f32 = -1,
) {
    if plan == nil || project == nil || geometry.count < 2 do return
    if plan.route_count >= len(plan.routes) {
        plan.access_routes_truncated = true
        return
    }
    total_length, weighted_grade, maximum_grade := f32(0), f32(0), f32(0)
    for index in 0 ..< geometry.count - 1 {
        a, b := geometry.points[index], geometry.points[index + 1]
        length := linalg.length(b - a)
        if length <= .01 do continue
        grade :=
            math.abs(terrain.sample_height(project, 0, b[0], b[1]) - terrain.sample_height(project, 0, a[0], a[1])) /
            length
        total_length += length
        weighted_grade += grade * length
        maximum_grade = max(maximum_grade, grade)
    }
    average_grade := total_length > .01 ? weighted_grade / total_length : f32(0)
    if average_grade_override >= 0 do average_grade = average_grade_override
    if maximum_grade_override >= 0 do maximum_grade = maximum_grade_override
    class := settlement_access_route_class(maximum_grade, width)
    if plan.village_reason == .Harbor_Fishery && width >= 3 && maximum_grade < SETTLEMENT_ACCESS_STAIR_GRADE {
        class = .Waterfront
    }
    pavement := settlement_access_route_pavement(maximum_grade, width)
    if class == .Stair do plan.access_stair_routes += 1
    // Above roughly 33 degrees a conventional outdoor stair becomes a
    // ladder-like intervention. Keep this visible as a planning failure
    // rather than silently presenting it as ordinary pedestrian paving.
    if maximum_grade > .65 do plan.access_excessive_grades += 1
    plan.routes[plan.route_count] = {
        geometry      = geometry,
        class         = class,
        width         = width,
        pavement      = pavement,
        drivable      = false,
        average_grade = average_grade,
        maximum_grade = maximum_grade,
    }
    plan.route_count += 1
}

settlement_access_stair_nosing_range :: proc(
    alley: architecture.City_Alley,
    length: f32,
) -> (
    start, finish: f32,
    valid: bool,
) {
    if length <= .01 do return
    start_landing := alley.start_terminal != .None ? f32(.65) : f32(0)
    end_landing := alley.end_terminal != .None ? f32(.65) : f32(0)
    start = min(start_landing, length * .5)
    finish = max(start, length - min(end_landing, length * .5))
    valid = finish - start >= .42
    return
}

settlement_access_stair_rest_count :: proc(run_length: f32) -> int {
    if run_length <= 7 do return 0
    return max(0, int(math.ceil(f64(run_length / 7))) - 1)
}

settlement_access_stair_interval_overlaps_rest :: proc(
    interval_start, interval_finish, run_start, run_length: f32,
    rest_count: int,
    rest_length: f32 = 1.05,
) -> bool {
    if rest_count <= 0 || run_length <= 0 || interval_finish <= interval_start do return false
    half_rest := max(rest_length, f32(0)) * .5
    for rest_index in 0 ..< rest_count {
        center := run_start + f32(rest_index + 1) / f32(rest_count + 1) * run_length
        if interval_finish > center - half_rest && interval_start < center + half_rest do return true
    }
    return false
}

settlement_access_door_apron_width :: proc(alley: architecture.City_Alley) -> f32 {
    return max(alley.half_width * 2, f32(1.1))
}

settlement_access_door_apron :: proc(
    scale: Settlement_Scale,
    alley: architecture.City_Alley,
    length: f32,
) -> (run, width: f32) {
    run = min(f32(.65), length)
    width = settlement_access_door_apron_width(alley)
    if scale == .Town {
        // A Riviera threshold is a tiny paved forecourt: enough room for a
        // stoop, pots, and two people passing, but still subordinate to the
        // adjoining vicolo.
        run = min(f32(1.6), length)
        width = max(width, f32(2.2))
    }
    return
}

settlement_access_road_apron :: proc(
    alley: architecture.City_Alley,
    length: f32,
) -> (
    run, outer_width: f32,
    valid: bool,
) {
    path_width := alley.half_width * 2
    if length <= .01 || path_width < 1.6 do return
    run = min(f32(.9), length)
    outer_width = min(path_width + .6, f32(3))
    valid = true
    return
}

settlement_plan_import_access_network :: proc(
    plan: ^Settlement_Plan,
    city_plan: ^architecture.City_Plan,
    project: ^terrain.Project,
) {
    if plan == nil || city_plan == nil || project == nil || city_plan.alley_count <= 0 do return
    plan.access_stair_routes = 0
    plan.access_excessive_grades = 0
    used := make([]bool, city_plan.alley_count, context.temp_allocator)
    for seed_index in 0 ..< city_plan.alley_count {
        if used[seed_index] do continue
        seed := city_plan.alleys[seed_index]
        seed_start := [2]f32{seed.start_x, seed.start_z}
        seed_end := [2]f32{seed.end_x, seed.end_z}
        start, finish := seed_start, seed_end
        if settlement_alley_endpoint_degree(city_plan, seed_end, seed.half_width) != 2 &&
           settlement_alley_endpoint_degree(city_plan, seed_start, seed.half_width) == 2 {
            start, finish = seed_end, seed_start
        }
        geometry: Settlement_Route
        alley_indices: [SETTLEMENT_ROUTE_CAPACITY]int
        alley_index_count := 1
        alley_indices[0] = seed_index
        geometry.points[0], geometry.points[1], geometry.count = start, finish, 2
        used[seed_index] = true
        current := finish
        for geometry.count < len(geometry.points) {
            if settlement_alley_endpoint_degree(city_plan, current, seed.half_width) != 2 do break
            next_index := -1
            next_point: [2]f32
            for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
                if used[alley_index] || math.abs(alley.half_width - seed.half_width) > .05 do continue
                alley_start := [2]f32{alley.start_x, alley.start_z}
                alley_end := [2]f32{alley.end_x, alley.end_z}
                if settlement_alley_point_near(current, alley_start) {
                    next_index, next_point = alley_index, alley_end
                    break
                }
                if settlement_alley_point_near(current, alley_end) {
                    next_index, next_point = alley_index, alley_start
                    break
                }
            }
            if next_index < 0 do break
            geometry.points[geometry.count], geometry.count = next_point, geometry.count + 1
            used[next_index] = true
            alley_indices[alley_index_count], alley_index_count = next_index, alley_index_count + 1
            current = next_point
        }
        chain_geometry := geometry
        chunk_start := 0
        for chunk_start < alley_index_count {
            chunk_end := chunk_start
            point_count := 1
            for chunk_end < alley_index_count {
                curve := settlement_access_alley_curve(city_plan, alley_indices[chunk_end])
                intervals := min(settlement_access_curve_navigation_intervals(curve), SETTLEMENT_ROUTE_CAPACITY - 1)
                if point_count + intervals > SETTLEMENT_ROUTE_CAPACITY && chunk_end > chunk_start do break
                point_count += min(intervals, SETTLEMENT_ROUTE_CAPACITY - point_count)
                chunk_end += 1
                if point_count >= SETTLEMENT_ROUTE_CAPACITY do break
            }
            if chunk_end <= chunk_start do chunk_end = chunk_start + 1
            chunk_indices := alley_indices[chunk_start:chunk_end]
            chunk_geometry := settlement_access_curve_chain_geometry(
                city_plan,
                chunk_indices,
                chain_geometry.points[chunk_start],
            )
            average_grade, maximum_grade := settlement_access_curve_grade_metrics(city_plan, project, chunk_indices)
            settlement_plan_import_access_route(
                plan,
                project,
                chunk_geometry,
                seed.half_width * 2,
                average_grade,
                maximum_grade,
            )
            chunk_start = chunk_end
        }
    }
}

settlement_plan_import_city :: proc(
    plan: ^Settlement_Plan,
    city_plan: ^architecture.City_Plan,
    project: ^terrain.Project,
) {
    if plan == nil || city_plan == nil || project == nil do return
    count := min(city_plan.count, city_plan.parcel_count)
    for index in 0 ..< count {
        if plan.site_count >= len(plan.sites) do break
        structure, parcel := city_plan.structures[index], city_plan.parcels[index]
        purpose := Settlement_Building_Purpose.Dwelling
        if index < plan.ordinary_purpose_count do purpose = plan.ordinary_purposes[index]
        site_kind := Settlement_Site_Kind.Ordinary
        if buildings.is_landmark(structure.building) do site_kind = .Landmark
        plan.sites[plan.site_count] = {
            structure = structure,
            parcel    = parcel,
            kind      = site_kind,
            tissue    = settlement_nearest_tissue(plan, structure.center_x, structure.center_z),
            density   = parcel.density,
            attached  = parcel.attached,
            accepted  = true,
            purpose   = purpose,
        }
        plan.site_count += 1
    }
    settlement_plan_import_access_network(plan, city_plan, project)
}

settlement_plan_seat_city :: proc(city_plan: ^architecture.City_Plan, project: ^terrain.Project) {
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

// Turn the exposed downhill side of a steep town foundation into a modest
// limestone retaining edge. Foundation seating already prevents buildings
// from sinking into side slopes, but without a visible edge the resulting
// height change reads as a house hovering over one continuous grass sheet.
// Keep the entrance facade open for its stoop and generated access path.
settlement_town_retaining_wall :: proc(
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan,
    structure: terrain.Structure,
) -> (wall: terrain.Structure, valid: bool) {
    if project == nil || city_plan == nil || structure.kind != .Architecture do return
    local_x := [2]f32{f32(math.cos(f64(structure.rotation))), f32(math.sin(f64(structure.rotation)))}
    local_z := [2]f32{-local_x[1], local_x[0]}
    center := [2]f32{structure.center_x, structure.center_z}
    edge_offsets := [4][2]f32 {
        local_z * (structure.depth * .5),
        local_x * (structure.width * .5),
        -local_z * (structure.depth * .5),
        -local_x * (structure.width * .5),
    }
    lowest_edge, lowest_height := -1, f32(1e30)
    for offset, edge_index in edge_offsets {
        if edge_index == int(structure.entrance_side) do continue
        point := center + offset
        height := terrain.sample_height(project, 0, point[0], point[1])
        if height < lowest_height {
            lowest_edge, lowest_height = edge_index, height
        }
    }
    if lowest_edge < 0 do return
    exposed_height := structure.base_y - lowest_height
    if exposed_height < .65 do return

    edge_center := center + edge_offsets[lowest_edge]
    along := local_x
    length := structure.width + .7
    if lowest_edge == 1 || lowest_edge == 3 {
        along = local_z
        length = structure.depth + .7
    }
    wall_height := clamp(exposed_height + .12, f32(.7), f32(3.2))
    wall = terrain.structure_make(edge_center[0], edge_center[1], length, .34, lowest_height - .04, wall_height)
    wall.kind = .Box
    wall.width, wall.depth, wall.height = length, .34, wall_height
    wall.rotation = f32(math.atan2(f64(along[1]), f64(along[0])))
    wall.color = {151, 145, 132, 255}
    if !settlement_structure_committed_roads_clear(project, wall, .08) ||
       settlement_access_structure_overlaps_alley(city_plan, wall) {
        return {}, false
    }
    return wall, true
}

settlement_plan_commit_town_retaining_walls :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan,
) -> int {
    if plan == nil || project == nil || city_plan == nil || plan.request.scale != .Town do return 0
    committed := 0
    for structure in city_plan.structures[:city_plan.count] {
        if committed >= 18 do break
        wall, valid := settlement_town_retaining_wall(project, city_plan, structure)
        if !valid do continue
        if terrain.add_structure(project, wall) < 0 do break
        committed += 1
    }
    return committed
}

settlement_plan_record_reserved_site :: proc(
    plan: ^Settlement_Plan,
    structure: terrain.Structure,
    kind: Settlement_Site_Kind,
    landmark_kind: Settlement_Landmark_Kind = {},
) {
    if plan == nil || plan.site_count >= len(plan.sites) do return
    site := Settlement_Site {
        structure     = structure,
        kind          = kind,
        landmark_kind = landmark_kind,
        tissue        = settlement_nearest_tissue(plan, structure.center_x, structure.center_z),
        accepted      = true,
    }
    if kind == .Park && min(structure.width, structure.depth) >= 10 {
        radius := clamp(min(structure.width, structure.depth) * .18, f32(2.2), f32(4.6))
        style := plan.request.region == .Aegean ? fountains.Style.Bowl : fountains.Style.Courtyard
        site.fountain_style = style
        site.fountain_radius = radius
        site.fountain_jet_count = clamp(int(radius * 2.5), 6, 14)
        site.fountain_jet_height = radius * .62
        site.fountain_enabled = true
    }
    plan.sites[plan.site_count] = site
    plan.site_count += 1
}

settlement_landmark_kind :: proc(region: Settlement_Region, ordinal: int) -> Settlement_Landmark_Kind {
    adriatic := [?]Settlement_Landmark_Kind {
        .Campanile,
        .Palace_Loggia,
        .Church,
        .Lighthouse,
        .Harbor_Office,
        .Market_Hall,
        .Fortress_Gate,
    }
    aegean := [?]Settlement_Landmark_Kind {
        .Cycladic_Bell,
        .Church,
        .Lighthouse,
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
    smooth_strength: f32 = .72,
    smooth_hardness: f32 = .62,
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
        terrain.apply_stroke_with_hardness(
            project,
            .Smooth,
            x,
            z,
            max(half_x, half_z) + feather,
            smooth_strength,
            1,
            smooth_hardness,
        )
    }
}

settlement_plan_prepare_block_terrain :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan = nil,
) {
    if plan == nil || project == nil do return
    if plan.request.scale == .Town && city_plan != nil {
        // Preserve the elevation steps that give a hillside town its profile.
        // Flattening each block's full bounding box caused neighboring edits
        // to overlap into one broad plateau. Compact per-building pads still
        // seat foundations, while same-frontage houses blend into a narrow
        // contour terrace and adjacent runs retain their height difference.
        budget := 28
        prepared := 0
        for structure in city_plan.structures[:city_plan.count] {
            if prepared >= budget do break
            local_slope := settlement_terrain_slope(project, structure.center_x, structure.center_z)
            if local_slope < .035 do continue
            half_x := min(structure.width * .5 + .35, f32(12))
            half_z := min(structure.depth * .5 + .35, f32(9))
            settlement_plan_record_terrain_edit(
                plan,
                project,
                .Building_Pad,
                structure.center_x,
                structure.center_z,
                half_x,
                half_z,
                .7,
                .54,
                .78,
            )
            prepared += 1
        }
        return
    }
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
