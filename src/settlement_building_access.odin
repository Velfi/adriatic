package main

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:math/linalg"

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
                network_candidate_limit := settlement_access_network_candidate_limit(plan.request.scale, road_distance)
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
                        settlement_access_connection_shape_penalty(city_plan, path, front, joins_network),
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
