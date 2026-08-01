package road_planner

import "core:testing"
import "core:math"

@(test)
planner_avoids_an_expensive_ridge :: proc(t: ^testing.T) {
    heights: [9 * 9]f32
    for z in 1 ..< 8 do heights[z * 9 + 4] = 18
    config := default_config()
    config.cell_size = 10
    config.grade_cost = 200
    config.steep_grade_cost = 10000
    work := new(Workspace)
    defer free(work)
    result := plan(work, {origin_x = 0, origin_z = 0, width = 9, height = 9, heights = heights[:]}, config, {10, 40}, {70, 40})
    testing.expect(t, result.found)
    testing.expect(t, result.point_count > 6)
    crossed_ridge := false
    for point in result.points[:result.point_count] {
        if point.x == 40 && point.z > 0 && point.z < 80 do crossed_ridge = true
    }
    testing.expect(t, !crossed_ridge)
}

@(test)
planner_uses_direct_route_on_flat_ground :: proc(t: ^testing.T) {
    heights: [8 * 8]f32
    config := default_config()
    config.cell_size = 10
    work := new(Workspace)
    defer free(work)
    result := plan(work, {origin_x = 0, origin_z = 0, width = 8, height = 8, heights = heights[:]}, config, {10, 10}, {60, 60})
    testing.expect(t, result.found)
    testing.expect_value(t, result.point_count, 6)
    testing.expect_value(t, result.points[0], Point{10, 10})
    testing.expect_value(t, result.points[result.point_count - 1], Point{60, 60})
}

@(test)
planner_reconstructs_routes_longer_than_legacy_capacity :: proc(t: ^testing.T) {
    heights := make([]f32, 128 * 128)
    defer delete(heights)
    for barrier_index in 0 ..< 7 {
        x := 16 + barrier_index * 16
        for z in 0 ..< 128 do heights[z * 128 + x] = 1000
        gap := barrier_index % 2 == 0 ? 0 : 127
        heights[gap * 128 + x] = 0
    }
    config := default_config()
    config.cell_size = 1
    config.grade_cost = 100000
    config.steep_grade_cost = 100000
    config.heuristic_weight = 1
    work := new(Workspace)
    defer free(work)
    result := plan(
        work,
        {origin_x = 0, origin_z = 0, width = 128, height = 128, heights = heights},
        config,
        {0, 64},
        {127, 64},
    )
    testing.expect(t, result.found)
    testing.expect(t, result.point_count > 512)
}

@(test)
planner_can_trade_length_for_a_switchback_grade :: proc(t: ^testing.T) {
    heights: [64 * 64]f32
    for z in 0 ..< 64 {
        for x in 0 ..< 64 do heights[z * 64 + x] = f32(x) * .2
    }
    config := default_config()
    config.cell_size = 1
    config.length_cost = .05
    config.grade_cost = 10
    config.steep_grade_cost = 10000
    config.maximum_grade = .1
    config.turn_cost = 0
    config.switchback_cost = 0
    config.heuristic_weight = 1
    work := new(Workspace)
    defer free(work)
    result := plan(
        work,
        {origin_x = 0, origin_z = 0, width = 64, height = 64, heights = heights[:]},
        config,
        {2, 32},
        {30, 32},
    )
    testing.expect(t, result.found)
    left_contour := false
    route_length := f32(0)
    for index in 1 ..< result.point_count {
        dx := result.points[index].x - result.points[index - 1].x
        dz := result.points[index].z - result.points[index - 1].z
        route_length += math.sqrt(dx * dx + dz * dz)
        left_contour = left_contour || result.points[index].z != 32
    }
    testing.expect(t, left_contour)
    testing.expect(t, route_length > 28)
}

@(test)
planner_respects_product_supplied_exclusions :: proc(t: ^testing.T) {
    heights: [9 * 9]f32
    blocked: [9 * 9]bool
    for z in 1 ..< 8 do blocked[z * 9 + 4] = true
    config := default_config()
    config.cell_size = 10
    work := new(Workspace)
    defer free(work)
    result := plan(
        work,
        {
            origin_x = 0,
            origin_z = 0,
            width = 9,
            height = 9,
            heights = heights[:],
            blocked = blocked[:],
        },
        config,
        {10, 40},
        {70, 40},
    )
    testing.expect(t, result.found)
    for point in result.points[:result.point_count] {
        cell_x := int(math.round(point.x / config.cell_size))
        cell_z := int(math.round(point.z / config.cell_size))
        testing.expect(t, !blocked[cell_z * 9 + cell_x])
    }
}

@(test)
planner_rejects_routes_without_a_legal_grade :: proc(t: ^testing.T) {
    heights: [3 * 3]f32
    for z in 0 ..< 3 do for x in 1 ..< 3 do heights[z * 3 + x] = 20
    config := default_config()
    config.cell_size = 10
    config.maximum_grade = .1
    work := new(Workspace)
    defer free(work)
    result := plan(
        work,
        {origin_x = 0, origin_z = 0, width = 3, height = 3, heights = heights[:]},
        config,
        {0, 10},
        {20, 10},
    )
    testing.expect(t, !result.found)
}
