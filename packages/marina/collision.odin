package marina

import boats "../boats"
import "core:math"

resolve_segment_circle :: proc(segment: Segment, plan: ^Plan, position: Vec2, radius: f32) -> (Vec2, bool) {
    a := plan_world_position(plan, segment.a)
    b := plan_world_position(plan, segment.b)
    axis := Vec2{b.x - a.x, b.z - a.z}
    axis_length_squared := axis.x * axis.x + axis.z * axis.z
    t := f32(0)
    if axis_length_squared > .000001 {
        offset := Vec2{position.x - a.x, position.z - a.z}
        t = clamp((offset.x * axis.x + offset.z * axis.z) / axis_length_squared, 0, 1)
    }
    closest := Vec2{a.x + axis.x * t, a.z + axis.z * t}
    delta := Vec2{position.x - closest.x, position.z - closest.z}
    distance_squared := delta.x * delta.x + delta.z * delta.z
    clearance := segment.width * .5 + radius
    if distance_squared >= clearance * clearance do return position, false
    if distance_squared > .000001 {
        scale := clearance / f32(math.sqrt(f64(distance_squared)))
        return {closest.x + delta.x * scale, closest.z + delta.z * scale}, true
    }
    axis_length := f32(math.sqrt(f64(axis_length_squared)))
    if axis_length > .000001 {
        return {closest.x - axis.z / axis_length * clearance, closest.z + axis.x / axis_length * clearance}, true
    }
    return {closest.x + clearance, closest.z}, true
}

resolve_office_circle :: proc(plan: ^Plan, position: Vec2, radius: f32) -> (Vec2, bool) {
    center := plan_world_position(plan, plan.office)
    cosine, sine := math.cos(plan.world_yaw), math.sin(plan.world_yaw)
    delta_x, delta_z := position.x - center.x, position.z - center.z
    local_x := delta_x * cosine - delta_z * sine
    local_z := delta_x * sine + delta_z * cosine
    half_x, half_z := f32(4.1) + radius, f32(3.2) + radius
    if abs(local_x) >= half_x || abs(local_z) >= half_z do return position, false

    distance_x := half_x - abs(local_x)
    distance_z := half_z - abs(local_z)
    if distance_x < distance_z {
        local_x = local_x < 0 ? -half_x : half_x
    } else {
        local_z = local_z < 0 ? -half_z : half_z
    }
    return {center.x + local_x * cosine + local_z * sine, center.z - local_x * sine + local_z * cosine}, true
}

// resolve_circle derives collision directly from the generated plan. Occupied
// slips are included because those boats are rendered from the plan rather
// than necessarily appearing in the global traffic list.
resolve_circle :: proc(plan: ^Plan, position: Vec2, radius: f32) -> (Vec2, bool) {
    if plan == nil || !plan.valid || radius < 0 do return position, false
    result := position
    collided := false
    // A few passes let corners made from intersecting segments settle without
    // leaving the circle embedded in the neighboring primitive.
    for _ in 0 ..< 3 {
        changed := false
        for segment in plan.segments[:plan.segment_count] {
            corrected, hit := resolve_segment_circle(segment, plan, result, radius)
            if hit {
                result = corrected
                changed, collided = true, true
            }
        }
        corrected, hit := resolve_office_circle(plan, result, radius)
        if hit {
            result = corrected
            changed, collided = true, true
        }
        for slip in plan.slips[:plan.slip_count] {
            if !slip.occupied do continue
            world := plan_world_position(plan, slip.position)
            agent := boats.Agent {
                class    = slip.class,
                position = {world.x, world.z},
                yaw      = plan_world_yaw(plan, slip.yaw),
            }
            boat_position, boat_hit := boats.resolve_circle(&agent, {result.x, result.z}, radius)
            if boat_hit {
                result = {boat_position.x, boat_position.y}
                changed, collided = true, true
            }
        }
        if !changed do break
    }
    return result, collided
}
