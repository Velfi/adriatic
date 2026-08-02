package main

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:math/linalg"

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
