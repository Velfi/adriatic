package tests

import architecture "../packages/architecture"
import boats "../packages/boats"
import kiosks "../packages/kiosks"
import marina "../packages/marina"
import terrain "../packages/terrain"
import "core:math"
import "core:testing"

@(test)
boat_collision_uses_the_hull_capsule :: proc(t: ^testing.T) {
    agent := boats.Agent {
        class    = .Motor,
        position = {10, 20},
        yaw      = 0,
    }
    corrected, hit := boats.resolve_circle(&agent, {10, 20}, .25)
    testing.expect(t, hit)
    testing.expect(t, abs(corrected.x - 10) > 1.5)

    unchanged, hit_far := boats.resolve_circle(&agent, {20, 20}, .25)
    testing.expect(t, !hit_far)
    testing.expect_value(t, unchanged, boats.Vec2{20, 20})
}

@(test)
marina_collision_covers_generated_harbor_objects :: proc(t: ^testing.T) {
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
    plan.prop_count = 1
    plan.props[0] = {.Crates, {30, 0}, 0}

    segment_position, segment_hit := marina.resolve_circle(&plan, {0, 0}, .25)
    testing.expect(t, segment_hit)
    testing.expect(t, abs(segment_position.z) >= 1.24)

    office_position, office_hit := marina.resolve_circle(&plan, {20, 0}, .25)
    testing.expect(t, office_hit)
    testing.expect(t, abs(office_position.z) >= 3.44)

    boat_position, boat_hit := marina.resolve_circle(&plan, {0, 10}, .25)
    testing.expect(t, boat_hit)
    testing.expect(t, abs(boat_position.x) >= 1.51)

    prop_position, prop_hit := marina.resolve_circle(&plan, {30, 0}, .25)
    testing.expect(t, prop_hit)
    testing.expect(t, abs(prop_position.x - 30) >= 1.29)

    plan.slips[0].position = {40, 0}
    plan.slips[0].kind = .Swing_Mooring
    plan.slips[0].occupied = false
    buoy_position, buoy_hit := marina.resolve_circle(&plan, {40, 0}, .25)
    testing.expect(t, buoy_hit)
    testing.expect(t, abs(buoy_position.x - 40) >= .59)
}

@(test)
building_collision_uses_rotated_rendered_footprint :: proc(t: ^testing.T) {
    structure := terrain.Structure {
        center_x = 10,
        center_z = 20,
        width    = 8,
        depth    = 4,
        rotation = math.PI / 2,
        kind     = .Architecture,
    }

    corrected, hit := architecture.resolve_structure_circle(structure, {10, 20}, .25)
    testing.expect(t, hit)
    testing.expect(t, abs(corrected.x - 10) >= 2.24)

    unchanged, hit_far := architecture.resolve_structure_circle(structure, {20, 20}, .25)
    testing.expect(t, !hit_far)
    testing.expect_value(t, unchanged, [2]f32{20, 20})
}

@(test)
kiosk_collision_covers_walls_and_counter_but_not_the_approach :: proc(t: ^testing.T) {
    center := kiosks.Vec2{10, 20}

    counter_position, counter_hit := kiosks.resolve_circle(center, {10, 19.5}, .24)
    testing.expect(t, counter_hit)
    testing.expect(t, abs(counter_position.y - (center.y + kiosks.KIOSK_COUNTER_Z)) >= .479)

    side_position, side_hit := kiosks.resolve_circle(center, {8.48, 20.5}, .24)
    testing.expect(t, side_hit)
    testing.expect(t, abs(side_position.x - (center.x - kiosks.KIOSK_SIDE_X)) >= .319)

    rear_position, rear_hit := kiosks.resolve_circle(center, {10, 21.58}, .24)
    testing.expect(t, rear_hit)
    testing.expect(t, rear_position.y >= 21.9)

    approach := kiosks.Vec2{10, 18.5}
    unchanged, approach_hit := kiosks.resolve_circle(center, approach, .24)
    testing.expect(t, !approach_hit)
    testing.expect_value(t, unchanged, approach)
}
