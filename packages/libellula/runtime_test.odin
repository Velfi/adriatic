package libellula

import flight "../flight"
import "core:math"
import "core:math/linalg"
import "core:testing"

@(test)
assisted_collective_hovers_when_climb_control_is_released :: proc(t: ^testing.T) {
    runtime := new_runtime(flight.Vec3{0, GROUND_CLEARANCE, 0})
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
    runtime := new_runtime(flight.Vec3{0, GROUND_CLEARANCE, 0})
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
assisted_hover_is_advected_by_crosswind :: proc(t: ^testing.T) {
    calm := new_runtime(flight.Vec3{0, GROUND_CLEARANCE, 0})
    windy := calm
    runtimes := [2]^Runtime{&calm, &windy}
    for runtime in runtimes {
        runtime.body.position.y = 20
        runtime.grounded = false
        runtime.was_grounded = false
        runtime.lift_active = true
    }
    for _ in 0 ..< 240 {
        step(&calm, {}, 0, 1.0 / 60.0)
        step(&windy, {}, 0, 1.0 / 60.0, {0, 0, 12})
    }
    testing.expect(t, windy.body.position.z > calm.body.position.z + 4)
    testing.expect(t, windy.body.velocity.z > calm.body.velocity.z + 1)
}

@(test)
assisted_cyclic_is_gentle_near_center :: proc(t: ^testing.T) {
    half_input := assisted_axis(.5, .64, .55)
    testing.expect(t, half_input > 0)
    testing.expect(t, half_input < .25)
    testing.expect(t, assisted_axis(1, .64, .55) == .64)
}

@(test)
holding_forward_commands_a_bounded_tilt_instead_of_tipping_over :: proc(t: ^testing.T) {
    runtime := new_runtime(flight.Vec3{0, GROUND_CLEARANCE, 0})
    runtime.body.position.y = 30
    runtime.grounded = false
    runtime.was_grounded = false
    runtime.lift_active = true
    for _ in 0 ..< 600 {
        step(&runtime, {pitch = -1}, 0, 1.0 / 60.0)
    }

    basis := flight.basis_from_orientation(runtime.body.orientation)
    spawn_basis := flight.basis_from_orientation(runtime.spawn_orientation)
    pitch := math.asin(clamp(basis.forward.y, -1, 1))
    forward_speed := linalg.dot(runtime.body.velocity, spawn_basis.forward)
    testing.expect(t, pitch < -.1)
    testing.expect(t, math.abs(pitch) < runtime.tuning.maximum_tilt_radians + .08)
    testing.expect(t, linalg.dot(basis.up, flight.Vec3{0, 1, 0}) > .9)
    testing.expect(t, forward_speed > 1)

    for _ in 0 ..< 240 {
        step(&runtime, {}, 0, 1.0 / 60.0)
    }
    released_basis := flight.basis_from_orientation(runtime.body.orientation)
    released_pitch := math.asin(clamp(released_basis.forward.y, -1, 1))
    testing.expect(t, math.abs(released_pitch) < .05)
}
