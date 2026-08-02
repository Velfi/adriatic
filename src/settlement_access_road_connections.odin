package main

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"

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
                    start, finish :=
                        [2]f32{candidate.start_x, candidate.start_z}, [2]f32{candidate.end_x, candidate.end_z}
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
                                settlement_access_count_road_connected_doors(plan, city_plan, project) >=
                                    connected_before &&
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
settlement_access_restore_door_throats :: proc(project: ^terrain.Project, city_plan: ^architecture.City_Plan) -> int {
    if project == nil || city_plan == nil do return 0
    restored := 0
    for structure, structure_index in city_plan.structures[:city_plan.count] {
        door := settlement_structure_front_door_point(structure, .22, project)
        outward := settlement_structure_entrance_approach_outward(structure, project)
        existing_count := city_plan.alley_count
        for alley_index in 0 ..< existing_count {
            alley := &city_plan.alleys[alley_index]
            door_at_start :=
                alley.start_terminal == .Door && settlement_alley_point_near(door, {alley.start_x, alley.start_z})
            door_at_end := alley.end_terminal == .Door && settlement_alley_point_near(door, {alley.end_x, alley.end_z})
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
                if !settlement_access_segment_clear(city_plan, door, candidate, clearance, structure_index) ||
                   !settlement_access_segment_clear(city_plan, candidate, neighbor, clearance, structure_index) {
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
