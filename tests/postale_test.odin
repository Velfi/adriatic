package tests

import flight "../packages/flight"
import postale "../packages/postale"
import "core:math"
import "core:testing"

@(test)
postale_ocean_is_a_drivable_surface_for_now :: proc(t: ^testing.T) {
    testing.expect(t, postale.drivable_surface_height(-12, 0) == 0)
    testing.expect(t, postale.drivable_surface_height(4.5, 0) == 4.5)
}

@(test)
postale_throttle_and_automatic_flaps_are_smoothed :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({y = postale.GROUND_CLEARANCE})
    postale.step(&runtime, {throttle_up = true}, 0, .5)
    testing.expect(t, runtime.throttle > 0 && runtime.throttle < 1)
    testing.expect(t, runtime.flap_fraction == 1)
    runtime.grounded = false
    runtime.body.position.y = 20
    runtime.throttle = 1
    runtime.body.velocity = flight.scale(runtime.body.basis.forward, 35)
    postale.step(&runtime, {}, 0, .5)
    testing.expect(t, runtime.flap_fraction < 1)
}

@(test)
postale_virtual_yoke_has_a_dead_zone_and_clamps :: proc(t: ^testing.T) {
    testing.expect(t, postale.virtual_yoke_axis(4, 8, 100) == 0)
    testing.expect(t, postale.virtual_yoke_axis(1000, 8, 100) == 1)
    testing.expect(t, postale.virtual_yoke_axis(-1000, 8, 100) == -1)
}

@(test)
postale_ground_contact_distinguishes_landings_from_crashes :: proc(t: ^testing.T) {
    safe := postale.new_runtime({y = postale.GROUND_CLEARANCE})
    safe.was_grounded = false
    safe.grounded = false
    safe.body.position.y = 0
    safe.body.velocity.y = -4
    result := postale.resolve_ground_contact(&safe, 0, -4)
    testing.expect(t, result.touched_down && result.grounded && !result.crashed)
    testing.expect(t, safe.body.position.y == postale.GROUND_CLEARANCE)

    hard := postale.new_runtime({y = postale.GROUND_CLEARANCE})
    hard.was_grounded = false
    hard.grounded = false
    hard.body.position.y = 0
    hard.body.velocity.y = -6
    result = postale.resolve_ground_contact(&hard, 0, -6)
    testing.expect(t, result.crashed && hard.crashed)
}

@(test)
postale_exit_requires_a_safe_stop :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({y = postale.GROUND_CLEARANCE})
    testing.expect(t, postale.can_exit(&runtime))
    runtime.body.velocity = {
        x = 2,
    }
    testing.expect(t, !postale.can_exit(&runtime))
    runtime.body.velocity = {}
    runtime.grounded = false
    testing.expect(t, !postale.can_exit(&runtime))
}

@(test)
postale_accelerates_and_leaves_the_short_runway :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({y = postale.GROUND_CLEARANCE})
    takeoff_distance: f32
    took_off := false
    for _ in 0 ..< 420 {
        postale.step(&runtime, {throttle_up = true, pitch = .35}, 0, 1.0 / 60.0)
        if !took_off && !runtime.grounded {
            took_off = true
            takeoff_distance = math.abs(runtime.body.position.x - runtime.spawn_position.x)
        }
    }
    testing.expect(t, took_off && !runtime.grounded && !runtime.crashed)
    testing.expect(t, takeoff_distance < 50)
    testing.expect(t, runtime.body.position.y > postale.GROUND_CLEARANCE + 5)
}

@(test)
postale_requires_rotation_input_to_take_off :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({y = postale.GROUND_CLEARANCE})
    for _ in 0 ..< 360 {
        postale.step(&runtime, {throttle_up = true}, 0, 1.0 / 60.0)
    }
    testing.expect(t, runtime.grounded)
    testing.expect(t, runtime.body.position.y == postale.GROUND_CLEARANCE)
}

@(test)
postale_does_not_bounce_back_into_flight_on_touchdown :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({y = postale.GROUND_CLEARANCE})
    runtime.grounded = false
    runtime.was_grounded = false
    runtime.throttle = 1
    runtime.pitch = 1
    runtime.body.velocity = flight.scale(runtime.body.basis.forward, 30)
    runtime.body.velocity.y = -1
    runtime.body.position.y = postale.GROUND_CLEARANCE

    result := postale.step(&runtime, {pitch = 1}, 0, 1.0 / 60.0)

    testing.expect(t, result.touched_down)
    testing.expect(t, runtime.grounded)
    testing.expect(t, runtime.body.velocity.y == 0)
    for _ in 0 ..< 120 {
        postale.step(&runtime, {pitch = 1}, 0, 1.0 / 60.0)
    }
    testing.expect(t, runtime.grounded)
    testing.expect(t, runtime.body.position.y == postale.GROUND_CLEARANCE)
}

@(test)
postale_sustained_roll_input_establishes_a_bank :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({y = 80})
    runtime.grounded = false
    runtime.was_grounded = false
    runtime.body.velocity = flight.scale(runtime.body.basis.forward, 42)
    for _ in 0 ..< 45 {
        postale.step(&runtime, {roll = .7}, 0, 1.0 / 60.0)
    }
    testing.expect(t, math.abs(postale.bank_radians(runtime.body.basis)) > .35)
}

@(test)
postale_rudder_engages_and_releases_without_snapping :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({y = 80})
    runtime.grounded = false
    runtime.was_grounded = false
    runtime.body.velocity = flight.scale(runtime.body.basis.forward, 42)
    postale.step(&runtime, {yaw = 1}, 0, 1.0 / 60.0)
    engaged := runtime.yaw
    testing.expect(t, engaged > 0 && engaged < 1)
    postale.step(&runtime, {}, 0, 1.0 / 60.0)
    testing.expect(t, runtime.yaw >= 0 && runtime.yaw < engaged)
}

@(test)
postale_reset_restores_the_runway_state :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({x = 4, y = postale.GROUND_CLEARANCE, z = 2})
    runtime.body.position = {
        x = 99,
        y = -5,
    }
    runtime.body.velocity = {
        x = 12,
    }
    runtime.throttle = 1
    runtime.crashed = true
    postale.reset(&runtime, 3)
    testing.expect(t, runtime.body.position.x == 4 && runtime.body.position.y == 3 + postale.GROUND_CLEARANCE)
    testing.expect(t, runtime.body.velocity == flight.Vec3{} && runtime.throttle == 0)
    testing.expect(t, runtime.grounded && !runtime.crashed)
}
