package main

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:math/linalg"

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
                    start, finish :=
                        [2]f32{candidate.start_x, candidate.start_z}, [2]f32{candidate.end_x, candidate.end_z}
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
                if linalg.dot(linalg.normalize(others[pair_a] - merge), linalg.normalize(others[pair_b] - merge)) >
                   .966 {
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
                append(
                    &city_plan.alleys,
                    architecture.City_Alley {
                        start_x = point[0],
                        start_z = point[1],
                        end_x = merge[0],
                        end_z = merge[1],
                        half_width = width,
                        household_demand = demand,
                    },
                )
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
