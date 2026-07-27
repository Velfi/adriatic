package boats

import "core:math"

// resolve_circle keeps a world-space circle outside the agent's hull. The hull
// is represented by a capsule so collision follows long, narrow boats much
// more closely than a single bounding circle.
resolve_circle :: proc(agent: ^Agent, position: Vec2, radius: f32) -> (Vec2, bool) {
    if agent == nil || radius < 0 do return position, false
    spec := specifications(agent.class)
    forward := agent_forward(agent^)
    half_run := max(spec.length * .5 - spec.beam * .5, f32(0))
    a := agent.position - forward * half_run
    b := agent.position + forward * half_run
    axis := b - a
    axis_length_squared := axis.x * axis.x + axis.y * axis.y
    t := f32(0)
    if axis_length_squared > .000001 {
        offset := position - a
        t = clamp((offset.x * axis.x + offset.y * axis.y) / axis_length_squared, 0, 1)
    }
    closest := a + axis * t
    delta := position - closest
    distance_squared := delta.x * delta.x + delta.y * delta.y
    clearance := spec.beam * .5 + radius
    if distance_squared >= clearance * clearance do return position, false

    if distance_squared > .000001 {
        inverse_distance := 1 / f32(math.sqrt(f64(distance_squared)))
        return closest + delta * (clearance * inverse_distance), true
    }

    // At the exact centerline, choose the hull's starboard normal. Any stable
    // normal is preferable to leaving the character embedded.
    side := Vec2{forward.y, -forward.x}
    return closest + side * clearance, true
}
