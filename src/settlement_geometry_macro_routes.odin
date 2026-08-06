package main

import architecture "../packages/architecture"
import planar_geometry "zelda_engine:planar_geometry"
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
    return planar_geometry.point_segment_distance_squared(point, a, b)
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
    return planar_geometry.segment_intersects_centered_box(start, finish, {half_width, half_depth}, .000001)
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
            math.abs(
                terrain.sample_surface_height(project, 0, b[0], b[1]) -
                terrain.sample_surface_height(project, 0, a[0], a[1]),
            ) /
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
