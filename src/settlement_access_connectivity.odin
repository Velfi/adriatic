package main

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:math/linalg"

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
