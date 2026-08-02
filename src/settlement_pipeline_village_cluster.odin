package main

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"

settlement_village_connect_services :: proc(
    result: ^architecture.City_Plan,
    project: ^terrain.Project,
    route_found, aegean_cluster_access: bool,
    common: [2]f32,
    inn_index: int,
    route_origin, route_normal: [2]f32,
    route_width, route_shoulder: f32,
    resource_index: int,
    workyard_valid: bool,
) {
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
            settlement_village_add_path(result, start, verge, 1.6, .Road)
            settlement_village_add_path(result, verge, destination, 1.6)
        }
    }
    if resource_index >= 0 && !workyard_valid {
        resource := result.structures[resource_index]
        destination := settlement_structure_approach_point(resource, common)
        settlement_village_add_path(result, common, destination, 1.25)
    }
}

settlement_village_add_aegean_cluster_access :: proc(
    result: ^architecture.City_Plan,
    plan: ^Settlement_Plan,
    common: [2]f32,
    route_found: bool,
) -> bool {
    if plan.request.region != .Aegean || !route_found do return false
    centers: [3][2]f32
    court_alleys := [3]int{-1, -1, -1}
    phase := f32(plan.request.seed & 0xffff) / f32(0xffff) * f32(math.TAU)
    for cluster_index in 0 ..< len(centers) {
        angle := phase + f32(cluster_index) * f32(math.TAU / 3)
        radial := [2]f32{f32(math.cos(f64(angle))), f32(math.sin(f64(angle)))}
        center := common + radial * 9
        centers[cluster_index] = center
        tangent := [2]f32{-radial[1], radial[0]}
        alley_start := result.alley_count
        settlement_village_add_path(
            result,
            center - tangent * 3.5,
            center + tangent * 3.5,
            3.2,
            .Public_Space,
            .Public_Space,
        )
        if result.alley_count > alley_start do court_alleys[cluster_index] = alley_start
    }
    root_index := 0
    root_distance := f32(1e30)
    for center, center_index in centers {
        _, _, _, width, shoulder, distance, _, found := settlement_nearest_route_frame(plan, center)
        throat_length := distance - (width * .5 + shoulder + .45)
        if found && throat_length >= 5 && distance < root_distance {
            root_index, root_distance = center_index, distance
        }
    }
    root_center := centers[root_index]
    root_origin, _, root_normal, root_width, root_shoulder, _, _, found := settlement_nearest_route_frame(
        plan,
        root_center,
    )
    connected := false
    if found {
        direction := root_center - root_origin
        if linalg.length(direction) > .01 {
            side_sign := linalg.dot(direction, root_normal) < 0 ? f32(-1) : f32(1)
            road_edge := root_origin + root_normal * side_sign * (root_width * .5 + root_shoulder + .45)
            court_index := court_alleys[root_index]
            throat_direction := linalg.normalize(root_center - road_edge)
            if court_index >= 0 && linalg.length(throat_direction) > .001 {
                tangent := [2]f32{-throat_direction[1], throat_direction[0]}
                court := &result.alleys[court_index]
                start, end := root_center - tangent * 3.5, root_center + tangent * 3.5
                court.start_x, court.start_z = start[0], start[1]
                court.end_x, court.end_z = end[0], end[1]
            }
            before := result.alley_count
            settlement_village_add_path(result, road_edge, root_center, 1.8, .Road)
            connected = result.alley_count > before
        }
    }
    for chain_index in 0 ..< 2 {
        first := centers[(root_index + chain_index) % 3]
        second := centers[(root_index + chain_index + 1) % 3]
        settlement_village_add_path(result, first, second, 1.6)
    }
    return connected
}
