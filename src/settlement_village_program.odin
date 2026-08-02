package main

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"

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
    if reason == .Agricultural_Terrace {
        // Reserve coherent farm compounds before domestic infill consumes
        // their yards and field gates. Barn ranges immediately follow their
        // hosts so every agricultural service building has an assignment.
        purposes[0] = .Farmstead
        purposes[1] = .Farmstead
        purposes[2] = .Barn_Granary
        purposes[3] = .Barn_Granary
        purposes[4] = .Barn_Granary
        purposes[5] = .Inn_Shop
        purposes[6] = .Workshop
        count = 7
        dwelling_count := 7 + int(seed % 4)
        for _ in 0 ..< dwelling_count {
            purposes[count] = .Dwelling
            count += 1
        }
        purposes[count] = .Mill
        return count + 1
    }
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
    // Handled above so compounds reserve their envelopes first.
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

settlement_normalize_ordinary_building_dimensions :: proc(width_in, depth_in: f32) -> (width, depth: f32) {
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
    return(
        width >= SETTLEMENT_MIN_ORDINARY_BUILDING_SIDE &&
        depth >= SETTLEMENT_MIN_ORDINARY_BUILDING_SIDE &&
        width * depth >= SETTLEMENT_MIN_ORDINARY_BUILDING_AREA - .001 \
    )
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
    case .Barn_Granary:
        // Mediterranean barns are compact stable/granary ranges rather than
        // freestanding hay halls. Keep the public face broad but low-volume.
        frontage = clamp(frontage * 1.04, 7.2, region == .Aegean ? f32(12) : f32(14))
        depth = clamp(depth * .82, 6.4, region == .Aegean ? f32(10) : f32(11.5))
    case .Storehouse:
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
