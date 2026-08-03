package main
import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"
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
    aegean_cluster_access := settlement_village_add_aegean_cluster_access(&result, plan, common, route_found)
    resource_direction := [2]f32{route_normal[0], route_normal[1]}
    sample := f32(12)
    gradient := [2]f32 {
        terrain.sample_surface_height(project, 0, common[0] + sample, common[1]) -
        terrain.sample_surface_height(project, 0, common[0] - sample, common[1]),
        terrain.sample_surface_height(project, 0, common[0], common[1] + sample) -
        terrain.sample_surface_height(project, 0, common[0], common[1] - sample),
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
       terrain.sample_surface_height(project, 0, resource_center[0], resource_center[1]) > project.sea_level + .6 {
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
                        start_height := terrain.sample_surface_height(project, 0, candidate_start[0], candidate_start[1])
                        end_height := terrain.sample_surface_height(project, 0, candidate_end[0], candidate_end[1])
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
        resource_slot, barn_slot := 0, 0
        for prior_purpose in program[:program_index] {
            if prior_purpose == .Barn_Granary do barn_slot += 1
            if prior_purpose == .Barn_Granary ||
               prior_purpose == .Storehouse ||
               prior_purpose == .Mill ||
               prior_purpose == .Fishery {
                resource_slot += 1
            }
        }
        found := false
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
                radius_high = 44
            }
            if aegean_form {
                switch purpose {
                case .Inn_Shop, .Workshop:
                    radius_low, radius_high = 7, 14
                case .Farmstead:
                    radius_low, radius_high = 18, 31
                case .Barn_Granary, .Storehouse, .Mill, .Fishery:
                    radius_low, radius_high = 26, 43
                case .Dwelling:
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
                radius_low, radius_high = 30, 70
            }
            resource_purpose :=
                purpose == .Barn_Granary || purpose == .Storehouse || purpose == .Mill || purpose == .Fishery
            farm_barn_purpose :=
                purpose == .Barn_Granary &&
                (plan.village_reason == .Agricultural_Terrace || plan.village_reason == .Upland_Pastoral)
            if resource_purpose {
                radius_low, radius_high = aegean_form ? f32(6) : f32(7), f32(34)
            }
            host_compound, host_compound_found := farm_compound_host_for_barn(
                &result,
                plan.request.region,
                barn_slot,
                project,
            )
            if farm_barn_purpose && host_compound_found {
                radius_low, radius_high = aegean_form ? f32(4.8) : f32(5.8), aegean_form ? f32(10) : f32(12)
            }
            amount := f32(candidate_index / 12) / 12
            radius := radius_low + (radius_high - radius_low) * clamp(amount, 0, 1)
            placement_center := resource_purpose ? resource_center : cohort_center
            if farm_barn_purpose && host_compound_found do placement_center = host_compound.yard_center
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
                station += f32(candidate_index / 8) * 1.25
                setback := frontage_lane.half_width + 1.35 + depth * .5
                center :=
                    frontage_lane.start +
                    frontage_lane.tangent * station +
                    frontage_lane.normal * (setback * lane_side)
                x, z = center[0], center[1]
            } else if court_frontage_candidate {
                court_index := dwelling_index - 6
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
                rotation = f32(math.atan2(f64(candidate_route_tangent[1]), f64(candidate_route_tangent[0])))
            } else if cohort_route_index >= 0 && candidate_route_found && !resource_purpose {
                rotation = f32(math.atan2(f64(candidate_route_tangent[1]), f64(candidate_route_tangent[0])))
            } else if aegean_form && gradient_length > .001 {
                rotation = f32(math.atan2(f64(-gradient[0]), f64(gradient[1])))
            } else if candidate_route_found && !resource_purpose {
                rotation = f32(math.atan2(f64(candidate_route_tangent[1]), f64(candidate_route_tangent[0])))
            } else if gradient_length > .001 {
                rotation = f32(math.atan2(f64(-gradient[0]), f64(gradient[1])))
            }
            if farm_barn_purpose && host_compound_found {
                rotation = host_compound.rotation
                rotation = settlement_rotation_face_point(rotation, {x, z}, host_compound.yard_center)
            }
            if (civic_route_frontage || (cohort_route_index >= 0 && candidate_route_found)) && !resource_purpose {
                rotation = settlement_rotation_face_point(rotation, {x, z}, candidate_route_origin)
            } else {
                rotation = settlement_rotation_face_point(rotation, {x, z}, placement_center)
            }
            if !settlement_structure_footprint_on_land(project, x, z, frontage, depth, rotation) do continue
            height_at_site := terrain.sample_surface_height(project, 0, x, z)
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
            allowed_compound := farm_barn_purpose && host_compound_found ? &host_compound : nil
            if purpose != .Farmstead &&
               !farm_compound_structure_clear(
                       &result,
                       plan.request.region,
                       x,
                       z,
                       frontage,
                       depth,
                       rotation,
                       allowed_compound,
                       project,
                   ) {
                continue
            }
            if purpose == .Farmstead {
                compound := farm_compound_derive(plan.request.region, candidate_structure, project)
                if !settlement_structure_footprint_on_land(
                       project,
                       compound.envelope_center[0],
                       compound.envelope_center[1],
                       compound.envelope_width,
                       compound.envelope_depth,
                       compound.rotation,
                       .35,
                   ) ||
                   !settlement_structure_clear(
                           project,
                           &result,
                           compound.envelope_center[0],
                           compound.envelope_center[1],
                           compound.envelope_width,
                           compound.envelope_depth,
                           compound.rotation,
                           .45,
                       ) ||
                   !farm_compound_envelope_clear(&result, compound, project) {
                    continue
                }
            }
            if farm_barn_purpose && host_compound_found {
                if !farm_compound_contains_point(host_compound, x, z, 0) ||
                   !settlement_oriented_rectangles_clear(
                           x,
                           z,
                           frontage,
                           depth,
                           rotation,
                           host_compound.threshing_center[0],
                           host_compound.threshing_center[1],
                           host_compound.threshing_radius * 2,
                           host_compound.threshing_radius * 2,
                           0,
                           .6,
                       ) {
                    continue
                }
            }
            if !settlement_structure_committed_roads_clear(project, candidate_structure) do continue
            if !settlement_structure_plazas_clear(plan, candidate_structure) do continue
            if settlement_access_structure_overlaps_alley(&result, candidate_structure) do continue
            if court_frontage_candidate {
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
                score = f32(candidate_index) * .02
            } else if court_frontage_candidate {
                score = f32(candidate_index) * .02
            } else if candidate_route_found {
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
                        score += f32(route_occupancy[candidate_route_index]) * (aegean_form ? f32(3.2) : f32(4.5))
                    }
                }
            }
            if harbor_quay_candidate {
                score = f32(candidate_index) * .02
            } else if farm_barn_purpose && host_compound_found {
                score = radius * .35
            } else if resource_purpose {
                score = radius * .75
            }
            height_error := math.abs(height_at_site - terrain.sample_surface_height(project, 0, common[0], common[1]))
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
    settlement_village_connect_services(
        &result,
        project,
        route_found,
        aegean_cluster_access,
        common,
        inn_index,
        route_origin,
        route_normal,
        route_width,
        route_shoulder,
        resource_index,
        workyard_valid,
    )
    core_half_x, core_half_z := aegean_form ? f32(6) : f32(8), aegean_form ? f32(5) : f32(6)
    settlement_plan_record_terrain_edit(plan, project, .Plaza, common[0], common[1], core_half_x, core_half_z, 2.5)
    if aegean_form && route_found && !aegean_cluster_access {
        court_start := [2]f32{common[0] - route_tangent[0] * core_half_x, common[1] - route_tangent[1] * core_half_x}
        court_end := [2]f32{common[0] + route_tangent[0] * core_half_x, common[1] + route_tangent[1] * core_half_x}
        settlement_village_add_path(&result, court_start, court_end, core_half_z * 1.45)
    }
    _ = settlement_plan_generate_building_access(plan, project, &result, rng, 120)
    return result
}
