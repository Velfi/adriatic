package tests

import boats "../packages/boats"
import marina "../packages/marina"
import "core:testing"

@(test)
boat_collision_uses_the_hull_capsule :: proc(t: ^testing.T) {
    agent := boats.Agent{class = .Motor, position = {10, 20}, yaw = 0}
    corrected, hit := boats.resolve_circle(&agent, {10, 20}, .25)
    testing.expect(t, hit)
    testing.expect(t, abs(corrected.x - 10) > 1.5)

    unchanged, hit_far := boats.resolve_circle(&agent, {20, 20}, .25)
    testing.expect(t, !hit_far)
    testing.expect_value(t, unchanged, boats.Vec2{20, 20})
}

@(test)
marina_collision_covers_segments_office_and_moored_boats :: proc(t: ^testing.T) {
    plan: marina.Plan
    plan.valid = true
    plan.segment_count = 1
    plan.segments[0] = {.Main_Pier, {-4, 0}, {4, 0}, 2}
    plan.office = {20, 0}
    plan.slip_count = 1
    plan.slips[0] = {
        position = {0, 10},
        class    = .Sail,
        occupied = true,
    }

    segment_position, segment_hit := marina.resolve_circle(&plan, {0, 0}, .25)
    testing.expect(t, segment_hit)
    testing.expect(t, abs(segment_position.z) >= 1.24)

    office_position, office_hit := marina.resolve_circle(&plan, {20, 0}, .25)
    testing.expect(t, office_hit)
    testing.expect(t, abs(office_position.z) >= 3.44)

    boat_position, boat_hit := marina.resolve_circle(&plan, {0, 10}, .25)
    testing.expect(t, boat_hit)
    testing.expect(t, abs(boat_position.x) >= 1.51)
}
