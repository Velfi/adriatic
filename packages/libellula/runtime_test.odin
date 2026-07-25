package libellula

import "core:math"
import "core:testing"

@(test)
assisted_collective_hovers_when_climb_control_is_released :: proc(t: ^testing.T) {
    runtime := new_runtime({y = GROUND_CLEARANCE})
    for _ in 0 ..< 180 {
        step(&runtime, {throttle_up = true}, 0, 1.0 / 60.0)
    }
    release_height := runtime.body.position.y
    for _ in 0 ..< 360 {
        step(&runtime, {}, 0, 1.0 / 60.0)
    }

    testing.expect(t, !runtime.grounded)
    testing.expect(t, math.abs(runtime.body.velocity.y) < .35)
    testing.expect(t, math.abs(runtime.body.position.y - release_height) < 4)
}

@(test)
assisted_hover_damps_horizontal_drift :: proc(t: ^testing.T) {
    runtime := new_runtime({y = GROUND_CLEARANCE})
    runtime.body.position.y = 20
    runtime.body.velocity.x = 8
    runtime.grounded = false
    runtime.was_grounded = false
    runtime.lift_active = true
    for _ in 0 ..< 180 {
        step(&runtime, {}, 0, 1.0 / 60.0)
    }

    testing.expect(t, math.abs(runtime.body.velocity.x) < 2)
    testing.expect(t, math.abs(runtime.body.velocity.y) < .35)
}

@(test)
assisted_cyclic_is_gentle_near_center :: proc(t: ^testing.T) {
    half_input := assisted_axis(.5, .64, .55)
    testing.expect(t, half_input > 0)
    testing.expect(t, half_input < .25)
    testing.expect(t, assisted_axis(1, .64, .55) == .64)
}
