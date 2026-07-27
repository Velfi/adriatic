package tests

import flight "../packages/flight"
import postale "../packages/postale"
import terrain "../packages/terrain"
import "core:math"
import "core:testing"

TEST_RUNWAY_HALF_LENGTH :: terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_RUNWAY_HALF_LENGTH

Landing_Scenario :: struct {
    distance:   f32,
    altitude:   f32,
    airspeed:   f32,
    sink_speed: f32,
}

Landing_Run :: struct {
    touched_down:      bool,
    stopped:           bool,
    crashed:           bool,
    touchdown_x:       f32,
    stop_x:            f32,
    peak_load:         f32,
    structural_damage: f32,
}

run_scripted_landing :: proc(scenario: Landing_Scenario) -> Landing_Run {
    runtime := postale.new_runtime({0, postale.GROUND_CLEARANCE, 0})
    runtime.grounded = false
    runtime.was_grounded = false
    // Scenario distance is measured outward from the generated runway's
    // positive-X approach threshold.
    runtime.body.position = {TEST_RUNWAY_HALF_LENGTH + scenario.distance, scenario.altitude, 0}
    runtime.body.velocity =
        runtime.body.basis.forward * scenario.airspeed + flight.Vec3{0, -scenario.sink_speed, 0}
    runtime.throttle = .34
    runtime.flap_fraction = 1
    result: Landing_Run

    for _ in 0 ..< 2400 {
        height := max(runtime.body.position.y - postale.GROUND_CLEARANCE, f32(0))
        desired_sink := f32(-1.8)
        if height < 7 {
            desired_sink = -.18 - height * .18
        }
        pitch := clamp((desired_sink - runtime.body.velocity.y) * .22, -.35, .55)
        target_speed := f32(29)
        control := postale.Control {
            pitch         = pitch,
            throttle_up   = runtime.telemetry.airspeed < target_speed - .5,
            throttle_down = runtime.telemetry.airspeed > target_speed + .5,
        }
        if runtime.grounded {
            control.pitch = 0
            control.throttle_up = false
            control.throttle_down = true
        }

        contact := postale.step(&runtime, control, 0, 1.0 / 60.0)
        result.peak_load = max(result.peak_load, runtime.last_landing.load_factor)
        if contact.touched_down && !result.touched_down {
            result.touched_down = true
            result.touchdown_x = runtime.body.position.x
        }
        if result.touched_down &&
           runtime.grounded &&
           f32(math.sqrt(f64(
               runtime.body.velocity.x * runtime.body.velocity.x +
               runtime.body.velocity.y * runtime.body.velocity.y +
               runtime.body.velocity.z * runtime.body.velocity.z,
           ))) < runtime.tuning.safe_exit_speed {
            result.stopped = true
            result.stop_x = runtime.body.position.x
            break
        }
        if runtime.crashed do break
    }
    result.crashed = runtime.crashed
    result.structural_damage = runtime.structural_damage
    return result
}

@(test)
postale_ocean_is_a_drivable_surface_for_now :: proc(t: ^testing.T) {
    testing.expect(t, postale.drivable_surface_height(-12, 0) == 0)
    testing.expect(t, postale.drivable_surface_height(4.5, 0) == 4.5)
}

@(test)
postale_scripted_approach_lands_and_stops :: proc(t: ^testing.T) {
    result := run_scripted_landing({distance = 180, altitude = 18, airspeed = 30, sink_speed = 1.8})
    testing.expect(t, result.touched_down && result.stopped && !result.crashed)
    testing.expect(
        t,
        result.touchdown_x <= TEST_RUNWAY_HALF_LENGTH && result.touchdown_x >= -TEST_RUNWAY_HALF_LENGTH + 80,
    )
    testing.expect(t, result.stop_x >= -TEST_RUNWAY_HALF_LENGTH)
    testing.expect(t, result.peak_load < 3)
    testing.expect(t, result.structural_damage == 0)
}

@(test)
postale_landing_envelope_has_adequate_margin :: proc(t: ^testing.T) {
    distances := [2]f32{160, 200}
    altitudes := [3]f32{15, 18, 21}
    airspeeds := [3]f32{27, 30, 33}
    sink_speeds := [3]f32{1.2, 1.8, 2.4}
    attempts, successes := 0, 0
    for distance in distances {
        for altitude in altitudes {
            for airspeed in airspeeds {
                for sink_speed in sink_speeds {
                    attempts += 1
                    result := run_scripted_landing({distance, altitude, airspeed, sink_speed})
                    if result.touched_down &&
                       result.stopped &&
                       !result.crashed &&
                       result.touchdown_x >= -TEST_RUNWAY_HALF_LENGTH + 80 &&
                       result.stop_x >= -TEST_RUNWAY_HALF_LENGTH &&
                       result.peak_load < 3 {
                        successes += 1
                    }
                }
            }
        }
    }
    testing.expect(t, successes * 10 >= attempts * 9)
}

@(test)
postale_throttle_and_automatic_flaps_are_smoothed :: proc(t: ^testing.T) {
    runtime := postale.new_runtime(flight.Vec3{0, postale.GROUND_CLEARANCE, 0})
    postale.step(&runtime, {throttle_up = true}, 0, .5)
    testing.expect(t, runtime.throttle > 0 && runtime.throttle < 1)
    testing.expect(t, runtime.flap_fraction == 1)
    runtime.grounded = false
    runtime.body.position.y = 20
    runtime.throttle = 1
    runtime.body.velocity = runtime.body.basis.forward * 35
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
    safe := postale.new_runtime(flight.Vec3{0, postale.GROUND_CLEARANCE, 0})
    safe.was_grounded = false
    safe.grounded = false
    safe.body.position.y = postale.GROUND_CLEARANCE - .01
    safe.body.velocity.y = -4
    result := postale.resolve_ground_contact(&safe, 0, -4, 1.0 / 60.0)
    testing.expect(t, result.touched_down && result.grounded && !result.crashed)
    testing.expect(t, result.landing.outcome == .Landed)
    testing.expect(t, result.landing.impact_force > result.landing.weight_force)
    testing.expect(t, safe.gear_compression > 0)

    hard := postale.new_runtime(flight.Vec3{0, postale.GROUND_CLEARANCE, 0})
    hard.was_grounded = false
    hard.grounded = false
    hard.body.position.y = postale.GROUND_CLEARANCE - .01
    hard.body.velocity.y = -6
    result = postale.resolve_ground_contact(&hard, 0, -6, 1.0 / 60.0)
    testing.expect(t, result.landing.load_factor > safe.last_landing.load_factor)
}

@(test)
postale_suspension_supports_aircraft_weight_at_static_sag :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({0, postale.GROUND_CLEARANCE, 0})
    force := postale.suspension_force(&runtime, runtime.gear_compression, 0)
    expected_weight := runtime.airframe.mass_kg * postale.GRAVITY
    testing.expect(t, math.abs(force - expected_weight) < .01)
}

@(test)
postale_hard_landings_accumulate_structural_damage :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({0, postale.GROUND_CLEARANCE, 0})
    runtime.grounded = false
    runtime.was_grounded = false
    runtime.body.position.y = postale.GROUND_CLEARANCE - .01
    runtime.body.velocity.y = -5
    result := postale.resolve_ground_contact(&runtime, 0, -5, 1.0 / 60.0)
    testing.expect(t, result.landing.outcome == .Hard_Landing)
    testing.expect(t, runtime.structural_damage > 0 && runtime.structural_damage < 1)
    testing.expect(t, runtime.flight_runtime.control_authority < 1)
}

@(test)
postale_exit_requires_a_safe_stop :: proc(t: ^testing.T) {
    runtime := postale.new_runtime(flight.Vec3{0, postale.GROUND_CLEARANCE, 0})
    testing.expect(t, postale.can_exit(&runtime))
    runtime.body.velocity = {2, 0, 0}
    testing.expect(t, !postale.can_exit(&runtime))
    runtime.body.velocity = {}
    runtime.grounded = false
    testing.expect(t, !postale.can_exit(&runtime))
}

@(test)
postale_accelerates_and_leaves_the_short_runway :: proc(t: ^testing.T) {
    runtime := postale.new_runtime(flight.Vec3{0, postale.GROUND_CLEARANCE, 0})
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
    testing.expect(t, runtime.body.position.y > postale.GROUND_CLEARANCE + 4.5)
}

@(test)
postale_requires_rotation_input_to_take_off :: proc(t: ^testing.T) {
    runtime := postale.new_runtime(flight.Vec3{0, postale.GROUND_CLEARANCE, 0})
    for _ in 0 ..< 360 {
        postale.step(&runtime, {throttle_up = true}, 0, 1.0 / 60.0)
    }
    testing.expect(t, runtime.grounded)
    testing.expect(t, runtime.body.position.y <= postale.GROUND_CLEARANCE)
    testing.expect(t, runtime.body.position.y >= postale.GROUND_CLEARANCE - runtime.tuning.gear_compression_distance)
}

@(test)
postale_suspension_compresses_and_damps_a_touchdown :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({0, postale.GROUND_CLEARANCE, 0})
    runtime.grounded = false
    runtime.was_grounded = false
    runtime.body.velocity.y = -1
    runtime.body.position.y = postale.GROUND_CLEARANCE

    result := postale.step(&runtime, {}, 0, 1.0 / 60.0)

    testing.expect(t, result.touched_down)
    testing.expect(t, runtime.grounded)
    testing.expect(t, runtime.body.velocity.y != 0)
    testing.expect(t, runtime.gear_force > 0)
    for _ in 0 ..< 240 {
        postale.step(&runtime, {}, 0, 1.0 / 60.0)
    }
    testing.expect(t, runtime.grounded)
    expected_height := postale.GROUND_CLEARANCE - postale.static_gear_compression(&runtime)
    testing.expect(t, math.abs(runtime.body.position.y - expected_height) < .03)
    testing.expect(t, math.abs(runtime.body.velocity.y) < .2)
}

@(test)
postale_sustained_roll_input_establishes_a_bank :: proc(t: ^testing.T) {
    runtime := postale.new_runtime(flight.Vec3{0, 80, 0})
    runtime.grounded = false
    runtime.was_grounded = false
    runtime.body.velocity = runtime.body.basis.forward * 42
    for _ in 0 ..< 45 {
        postale.step(&runtime, {roll = .7}, 0, 1.0 / 60.0)
    }
    testing.expect(t, math.abs(postale.bank_radians(runtime.body.basis)) > .35)
}

@(test)
postale_rudder_engages_and_releases_without_snapping :: proc(t: ^testing.T) {
    runtime := postale.new_runtime(flight.Vec3{0, 80, 0})
    runtime.grounded = false
    runtime.was_grounded = false
    runtime.body.velocity = runtime.body.basis.forward * 42
    postale.step(&runtime, {yaw = 1}, 0, 1.0 / 60.0)
    engaged := runtime.yaw
    testing.expect(t, engaged > 0 && engaged < 1)
    postale.step(&runtime, {}, 0, 1.0 / 60.0)
    testing.expect(t, runtime.yaw >= 0 && runtime.yaw < engaged)
}

@(test)
postale_reset_restores_the_runway_state :: proc(t: ^testing.T) {
    runtime := postale.new_runtime(flight.Vec3{4, postale.GROUND_CLEARANCE, 2})
    runtime.body.position = {99, -5, 0}
    runtime.body.velocity = {12, 0, 0}
    runtime.throttle = 1
    runtime.crashed = true
    postale.reset(&runtime, 3)
    expected_height := 3 + postale.GROUND_CLEARANCE - postale.static_gear_compression(&runtime)
    testing.expect(t, runtime.body.position.x == 4 && runtime.body.position.y == expected_height)
    testing.expect(t, runtime.body.velocity == flight.Vec3{} && runtime.throttle == 0)
    testing.expect(t, runtime.grounded && !runtime.crashed)
}
