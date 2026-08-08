package main

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"

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
        append(&city_plan.alleys, architecture.City_Alley {
            start_x        = start[0],
            start_z        = start[1],
            end_x          = end[0],
            end_z          = end[1],
            half_width     = width * .5,
            start_terminal = .Road,
            end_terminal   = .Public_Space,
        })
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
