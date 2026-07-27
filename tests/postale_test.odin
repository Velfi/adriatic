package tests

import flight "../packages/flight"
import postale "../packages/postale"
import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"
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
    final_speed:       f32,
    final_forward:     f32,
    final_vertical:    f32,
    grounded:          bool,
}

Takeoff_Run :: struct {
    took_off, crashed: bool,
    distance:          f32,
    seconds:           f32,
    liftoff_speed:     f32,
    peak_ground_pitch: f32,
}

run_takeoff :: proc(
    mass_kg: f32,
    wind: flight.Vec3 = {},
    model: postale.Flight_Model = .Current_Aero,
) -> Takeoff_Run {
    runtime := postale.new_runtime(flight.Vec3{0, postale.GROUND_CLEARANCE, 0})
    runtime.flight_model = model
    runtime.airframe.mass_kg = mass_kg
    start := runtime.body.position
    result: Takeoff_Run
    for step_index in 0 ..< 3600 {
        postale.step(&runtime, {throttle_up = true, pitch = .35}, 0, 1.0 / 60.0, wind)
        result.peak_ground_pitch = max(result.peak_ground_pitch, runtime.ground_pitch_radians)
        if !runtime.grounded {
            result.took_off = true
            result.distance = linalg.length(
                flight.Vec3{runtime.body.position.x - start.x, 0, runtime.body.position.z - start.z},
            )
            result.seconds = f32(step_index + 1) / 60
            result.liftoff_speed = postale.selected_airspeed(&runtime)
            break
        }
        if runtime.crashed do break
    }
    result.crashed = runtime.crashed
    return result
}

run_scripted_landing :: proc(scenario: Landing_Scenario, mass_kg: f32 = 3300, wind: flight.Vec3 = {}) -> Landing_Run {
    runtime := postale.new_runtime({0, postale.GROUND_CLEARANCE, 0})
    runtime.airframe.mass_kg = mass_kg
    runtime.grounded = false
    runtime.was_grounded = false
    // Scenario distance is measured outward from the generated runway's
    // positive-X approach threshold.
    runtime.body.position = {TEST_RUNWAY_HALF_LENGTH + scenario.distance, scenario.altitude, 0}
    basis := flight.basis_from_orientation(runtime.body.orientation)
    runtime.body.velocity = basis.forward * scenario.airspeed + flight.Vec3{0, -scenario.sink_speed, 0}
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

        contact := postale.step(&runtime, control, 0, 1.0 / 60.0, wind)
        result.peak_load = max(result.peak_load, runtime.last_landing.load_factor)
        if contact.touched_down && !result.touched_down {
            result.touched_down = true
            result.touchdown_x = runtime.body.position.x
        }
        if result.touched_down &&
           runtime.grounded &&
           linalg.length(runtime.body.velocity) < runtime.tuning.safe_exit_speed {
            result.stopped = true
            result.stop_x = runtime.body.position.x
            break
        }
        if runtime.crashed do break
    }
    result.crashed = runtime.crashed
    result.structural_damage = runtime.structural_damage
    result.final_speed = linalg.length(runtime.body.velocity)
    result.final_forward = linalg.dot(
        runtime.body.velocity,
        flight.basis_from_orientation(runtime.body.orientation).forward,
    )
    result.final_vertical = runtime.body.velocity.y
    result.grounded = runtime.grounded
    return result
}

@(test)
postale_ocean_is_a_drivable_surface_for_now :: proc(t: ^testing.T) {
    testing.expect(t, postale.drivable_surface_height(-12, 0) == 0)
    testing.expect(t, postale.drivable_surface_height(4.5, 0) == 4.5)
}

@(test)
postale_defaults_to_the_current_aero_model :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({})
    testing.expect(t, runtime.flight_model == .Current_Aero)
    testing.expect(t, runtime.ace_tuning == postale.ace_tuning_preset())
    testing.expect(t, flight.ace_tuning_is_valid(runtime.ace_tuning))
}

@(test)
postale_current_aero_dispatch_leaves_ace_state_unchanged :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({0, 80, 0})
    runtime.body.velocity = flight.basis_from_orientation(runtime.body.orientation).forward * 42
    runtime.ace_runtime = {
        energy       = .73,
        edge_state   = .Hang,
        edge_seconds = 1.25,
        local_rate   = {1, 2, 3},
    }
    runtime.ace_telemetry = {
        pace                 = .8,
        energy               = .6,
        track_grip           = .4,
        attitude_track_angle = .2,
        edge_state           = .Warning,
    }
    ace_runtime_before := runtime.ace_runtime
    ace_telemetry_before := runtime.ace_telemetry
    position_before := runtime.body.position

    postale.step_airborne_model(&runtime, {throttle = .7}, .25)

    testing.expect(t, runtime.ace_runtime == ace_runtime_before)
    testing.expect(t, runtime.ace_telemetry == ace_telemetry_before)
    testing.expect(t, runtime.body.position != position_before)
    testing.expect(t, runtime.telemetry.airspeed > 0)
}

@(test)
postale_ace_dispatch_leaves_current_aero_state_unchanged :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({0, 80, 0})
    runtime.flight_model = .Ace_Arcade
    runtime.body.velocity = flight.basis_from_orientation(runtime.body.orientation).forward * 42
    runtime.ace_runtime.energy = .63
    runtime.flight_runtime = {
        engine_output     = .4,
        control_authority = .3,
        drag_multiplier   = 1.2,
        controls_damaged  = true,
    }
    runtime.telemetry = {
        airspeed                = 37,
        angle_of_attack_degrees = .2,
        effective_stall_speed   = 18,
        lift_coefficient        = .7,
        is_stalling             = true,
    }
    flight_runtime_before := runtime.flight_runtime
    telemetry_before := runtime.telemetry
    position_before := runtime.body.position
    ace_runtime_before := runtime.ace_runtime

    postale.step_airborne_model(&runtime, {roll = 1, throttle = 1}, 1.0 / 120.0)

    testing.expect(t, runtime.flight_runtime == flight_runtime_before)
    testing.expect(t, runtime.telemetry == telemetry_before)
    testing.expect(t, runtime.body.position != position_before)
    testing.expect(t, runtime.ace_runtime != ace_runtime_before)
    testing.expect(t, runtime.ace_runtime.local_rate.z > 0)
    testing.expect(t, runtime.ace_telemetry.pace > 0)
    testing.expect(t, runtime.ace_telemetry.energy == runtime.ace_runtime.energy)
}

@(test)
postale_airborne_dispatch_rejects_invalid_delta_without_mutation :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({0, 80, 0})
    runtime.flight_model = .Ace_Arcade
    runtime.body.velocity = {4, -1, 2}
    runtime.ace_runtime.energy = .63
    runtime_before := runtime

    postale.step_airborne_model(&runtime, {pitch = 1}, 0)
    postale.step_airborne_model(&runtime, {pitch = 1}, -1)

    testing.expect(t, runtime == runtime_before)
}

@(test)
postale_normalized_seam_matches_equivalent_prepared_legacy_step :: proc(t: ^testing.T) {
    raw := postale.new_runtime({0, 80, 0})
    raw.grounded = false
    raw.was_grounded = false
    raw.body.position = {3, 80, -5}
    raw.body.velocity = flight.basis_from_orientation(raw.body.orientation).forward * 42
    raw.throttle = .65
    raw.flap_fraction = 0
    raw.pitch = .12
    raw.roll = -.08
    raw.yaw = .04
    raw.landing_feedback_seconds = .4
    normalized := raw
    control := postale.Control {
        pitch = raw.pitch,
        roll  = raw.roll,
        yaw   = raw.yaw,
    }
    command := flight.Control_Command {
        pitch         = normalized.pitch,
        roll          = normalized.roll,
        yaw           = normalized.yaw,
        throttle      = normalized.throttle,
        flap_fraction = normalized.flap_fraction,
    }
    wind := flight.Vec3{1, 0, -.5}

    raw_result := postale.step(&raw, control, 0, 1.0 / 60.0, wind)
    normalized_result := postale.step_normalized_command(&normalized, command, 0, 1.0 / 60.0, wind)

    testing.expect(t, normalized_result == raw_result)
    testing.expect(t, normalized == raw)
}

@(test)
postale_normalized_seam_rejects_nil_and_invalid_delta_without_mutation :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({0, 80, 0})
    runtime_before := runtime

    result := postale.step_normalized_command(nil, {}, 0, 1.0 / 60.0)
    testing.expect(t, result == postale.Ground_Result{})
    result = postale.step_normalized_command(&runtime, {pitch = 1}, 0, 0)
    testing.expect(t, result == postale.Ground_Result{})
    result = postale.step_normalized_command(&runtime, {pitch = 1}, 0, -1)
    testing.expect(t, result == postale.Ground_Result{})
    testing.expect(t, runtime == runtime_before)
}

@(test)
postale_selected_airspeed_follows_active_model :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({})
    runtime.telemetry.airspeed = 37
    runtime.ace_telemetry.pace = 52

    testing.expect(t, postale.selected_airspeed(nil) == 0)
    testing.expect(t, postale.selected_airspeed(&runtime) == 37)
    runtime.flight_model = .Ace_Arcade
    testing.expect(t, postale.selected_airspeed(&runtime) == 52)
}

@(test)
postale_normalized_seam_clamps_command_and_syncs_complete_ace_step :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({0, 80, 0})
    runtime.flight_model = .Ace_Arcade
    runtime.grounded = false
    runtime.was_grounded = false
    runtime.body.position = {3, 80, -5}
    runtime.body.velocity = flight.basis_from_orientation(runtime.body.orientation).forward * 42
    runtime.ace_runtime.energy = 1
    flight_runtime_before := runtime.flight_runtime
    telemetry_before := runtime.telemetry
    position_before := runtime.body.position

    postale.step_normalized_command(
        &runtime,
        {pitch = 2, roll = -2, yaw = 2, throttle = 2, flap_fraction = -1},
        0,
        1.0 / 120.0,
    )

    testing.expect(t, runtime.pitch == 1)
    testing.expect(t, runtime.roll == -1)
    testing.expect(t, runtime.yaw == 1)
    testing.expect(t, runtime.throttle == 1)
    testing.expect(t, runtime.flap_fraction == 0)
    testing.expect(t, runtime.flight_runtime == flight_runtime_before)
    testing.expect(t, runtime.telemetry == telemetry_before)
    testing.expect(t, runtime.body.position != position_before)
    testing.expect(t, runtime.ace_telemetry.pace > 0)
    testing.expect(t, runtime.ace_telemetry.energy == runtime.ace_runtime.energy)
    testing.expect(t, runtime.vehicle.position.x == runtime.body.position.x)
    testing.expect(t, runtime.vehicle.position.y == runtime.body.position.y)
    testing.expect(t, runtime.vehicle.position.z == runtime.body.position.z)
}

@(test)
postale_shared_damage_modifiers_reduce_ace_control_response :: proc(t: ^testing.T) {
    healthy := postale.new_runtime({0, 80, 0})
    healthy.flight_model = .Ace_Arcade
    healthy.grounded = false
    healthy.was_grounded = false
    healthy.body.velocity = flight.basis_from_orientation(healthy.body.orientation).forward * 42
    healthy.ace_runtime.energy = 1
    damaged := healthy
    damaged.flight_runtime.engine_output = .4
    damaged.flight_runtime.control_authority = .25
    damaged.flight_runtime.controls_damaged = true
    command := flight.Control_Command {
        roll     = 1,
        throttle = 1,
    }

    postale.step_normalized_command(&healthy, command, 0, 1.0 / 120.0)
    postale.step_normalized_command(&damaged, command, 0, 1.0 / 120.0)

    testing.expect(t, healthy.ace_runtime.local_rate.z > 0)
    testing.expect(t, damaged.ace_runtime.local_rate.z > 0)
    testing.expect(t, damaged.ace_runtime.local_rate.z < healthy.ace_runtime.local_rate.z)
    testing.expect(t, damaged.ace_telemetry.pace < healthy.ace_telemetry.pace)
}

@(test)
postale_ace_safe_and_unsafe_touchdown_use_shared_ground_policy :: proc(t: ^testing.T) {
    safe := postale.new_runtime({0, postale.GROUND_CLEARANCE, 0})
    safe.flight_model = .Ace_Arcade
    safe.grounded = false
    safe.was_grounded = false
    safe.body.position.y = postale.GROUND_CLEARANCE - .01
    safe.body.velocity = flight.basis_from_orientation(safe.body.orientation).forward * 25 + flight.Vec3{0, -1, 0}
    safe.ace_runtime.energy = 1

    safe_result := postale.step_normalized_command(&safe, {throttle = .3}, 0, 1.0 / 120.0)
    testing.expect(t, safe_result.touched_down)
    testing.expect(t, safe.grounded)
    testing.expect(t, !safe.crashed)
    testing.expect(t, safe.vehicle.position.y == safe.body.position.y)

    unsafe := postale.new_runtime({0, postale.GROUND_CLEARANCE, 0})
    unsafe.flight_model = .Ace_Arcade
    unsafe.grounded = false
    unsafe.was_grounded = false
    unsafe.body.position.y = postale.GROUND_CLEARANCE - .01
    unsafe.body.velocity = flight.basis_from_orientation(unsafe.body.orientation).forward * 25 + flight.Vec3{0, -20, 0}
    unsafe.ace_runtime.energy = 1

    unsafe_result := postale.step_normalized_command(&unsafe, {throttle = .3}, 0, 1.0 / 120.0)
    testing.expect(t, unsafe_result.touched_down)
    testing.expect(t, unsafe.grounded)
    testing.expect(t, unsafe_result.crashed)
    testing.expect(t, unsafe.crashed)
}

@(test)
postale_scripted_approach_lands_and_stops :: proc(t: ^testing.T) {
    result := run_scripted_landing({distance = 180, altitude = 18, airspeed = 30, sink_speed = 1.8})
    testing.expectf(
        t,
        result.touched_down && result.stopped && !result.crashed,
        "landing result: touched=%v stopped=%v crashed=%v grounded=%v speed=%.2f forward=%.2f vertical=%.2f touchdown=%.2f stop=%.2f load=%.2f",
        result.touched_down,
        result.stopped,
        result.crashed,
        result.grounded,
        result.final_speed,
        result.final_forward,
        result.final_vertical,
        result.touchdown_x,
        result.stop_x,
        result.peak_load,
    )
    testing.expect(
        t,
        result.touchdown_x <= TEST_RUNWAY_HALF_LENGTH && result.touchdown_x >= -TEST_RUNWAY_HALF_LENGTH + 80,
    )
    testing.expect(t, result.stop_x >= -TEST_RUNWAY_HALF_LENGTH)
    rollout_distance := math.abs(result.stop_x - result.touchdown_x)
    testing.expectf(
        t,
        rollout_distance >= 170 && rollout_distance <= 220,
        "expected a 170-220 m landing roll, got %.2f m",
        rollout_distance,
    )
    testing.expect(t, result.peak_load < 3)
    testing.expect(t, result.structural_damage == 0)
}

@(test)
postale_landing_envelope_has_adequate_margin :: proc(t: ^testing.T) {
    distances := [2]f32{160, 200}
    altitudes := [3]f32{15, 18, 21}
    airspeeds := [3]f32{27, 30, 33}
    sink_speeds := [3]f32{1.2, 1.8, 2.4}
    attempts, successes, runway_successes := 0, 0, 0
    for distance in distances {
        for altitude in altitudes {
            for airspeed in airspeeds {
                for sink_speed in sink_speeds {
                    attempts += 1
                    result := run_scripted_landing({distance, altitude, airspeed, sink_speed})
                    if result.touched_down && result.stopped && !result.crashed && result.peak_load < 3 {
                        successes += 1
                        if result.touchdown_x >= -TEST_RUNWAY_HALF_LENGTH + 80 &&
                           result.stop_x >= -TEST_RUNWAY_HALF_LENGTH {
                            runway_successes += 1
                        }
                    }
                }
            }
        }
    }
    testing.expectf(
        t,
        successes * 10 >= attempts * 9,
        "expected at least 90%% safe, controlled landings, got %d/%d",
        successes,
        attempts,
    )
    testing.expectf(
        t,
        runway_successes * 4 >= attempts * 3,
        "expected at least 75%% of varied approaches to stop on the runway, got %d/%d",
        runway_successes,
        attempts,
    )
}

@(test)
postale_landing_remains_safe_across_weight_and_wind :: proc(t: ^testing.T) {
    scenario := Landing_Scenario {
        distance   = 180,
        altitude   = 18,
        airspeed   = 30,
        sink_speed = 1.8,
    }
    runs := [?]Landing_Run {
        run_scripted_landing(scenario, 2800),
        run_scripted_landing(scenario, 3300),
        run_scripted_landing(scenario, 3800),
        run_scripted_landing(scenario, 3300, flight.Vec3{4, 0, 0}),
        run_scripted_landing(scenario, 3300, flight.Vec3{-4, 0, 0}),
    }
    for run in runs {
        testing.expectf(
            t,
            run.touched_down && run.stopped && !run.crashed && run.peak_load < 3,
            "unsafe landing condition: touched=%v stopped=%v crashed=%v load=%.2f",
            run.touched_down,
            run.stopped,
            run.crashed,
            run.peak_load,
        )
        rollout := math.abs(run.stop_x - run.touchdown_x)
        testing.expectf(t, rollout < 450, "landing rollout exceeded runway length: %.1f m", rollout)
    }
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
    runtime.body.velocity = flight.basis_from_orientation(runtime.body.orientation).forward * 35
    postale.step(&runtime, {}, 0, .5)
    testing.expect(t, runtime.flap_fraction < 1)
}

@(test)
postale_landing_intent_requires_a_stable_sustained_approach :: proc(t: ^testing.T) {
    runtime := postale.new_runtime(flight.Vec3{0, postale.GROUND_CLEARANCE, 0})
    runtime.grounded = false
    runtime.was_grounded = false
    runtime.body.position.y = postale.GROUND_CLEARANCE + 12
    runtime.body.velocity =
        flight.basis_from_orientation(runtime.body.orientation).forward * 27.5 + flight.Vec3{0, -1.2, 0}
    runtime.throttle = .3

    testing.expect(t, postale.landing_intent_candidate(&runtime, 0))
    for _ in 0 ..< 13 {
        postale.update_landing_intent(&runtime, 0, 1.0 / 60.0)
    }
    testing.expect(t, !runtime.landing_intent)
    for _ in 0 ..< 15 {
        postale.update_landing_intent(&runtime, 0, 1.0 / 60.0)
    }
    testing.expect(t, runtime.landing_intent)
}

@(test)
postale_landing_intent_rejects_takeoff_and_stunt_motion :: proc(t: ^testing.T) {
    takeoff := postale.new_runtime(flight.Vec3{0, postale.GROUND_CLEARANCE, 0})
    takeoff.throttle = 1
    takeoff_basis := flight.basis_from_orientation(takeoff.body.orientation)
    takeoff.body.velocity = takeoff_basis.forward * 24
    testing.expect(t, !postale.landing_intent_candidate(&takeoff, 0))

    stunt := postale.new_runtime(flight.Vec3{0, postale.GROUND_CLEARANCE + 10, 0})
    stunt.grounded = false
    stunt.was_grounded = false
    stunt.throttle = .25
    stunt_basis := flight.basis_from_orientation(stunt.body.orientation)
    stunt.body.velocity = stunt_basis.forward * 28 + flight.Vec3{0, -1, 0}
    stunt.body.angular_velocity_world = stunt_basis.forward * .9
    testing.expect(t, !postale.landing_intent_candidate(&stunt, 0))
    for _ in 0 ..< 60 {
        postale.update_landing_intent(&stunt, 0, 1.0 / 60.0)
    }
    testing.expect(t, !stunt.landing_intent)
}

@(test)
postale_go_around_cancels_landing_intent_immediately :: proc(t: ^testing.T) {
    runtime := postale.new_runtime(flight.Vec3{0, postale.GROUND_CLEARANCE + 10, 0})
    runtime.grounded = false
    runtime.was_grounded = false
    runtime.body.velocity =
        flight.basis_from_orientation(runtime.body.orientation).forward * 28 + flight.Vec3{0, -1, 0}
    runtime.throttle = .3
    runtime.landing_intent = true
    runtime.landing_intent_seconds = postale.LANDING_INTENT_CONFIRM_SECONDS

    runtime.throttle = .8
    postale.update_landing_intent(&runtime, 0, 1.0 / 60.0)
    testing.expect(t, !runtime.landing_intent)
    testing.expect(t, runtime.landing_intent_seconds == 0)
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
postale_braking_requires_a_deliberate_rollout :: proc(t: ^testing.T) {
    runtime := postale.new_runtime(flight.Vec3{0, postale.GROUND_CLEARANCE, 0})
    runtime.body.velocity = flight.basis_from_orientation(runtime.body.orientation).forward * 30
    start := runtime.body.position

    for _ in 0 ..< 60 {
        postale.step(&runtime, {throttle_down = true}, 0, 1.0 / 60.0)
    }

    distance := linalg.length(runtime.body.position - start)
    testing.expectf(
        t,
        linalg.length(runtime.body.velocity) > 22,
        "expected more than 22 m/s after one second of braking, got %.2f",
        linalg.length(runtime.body.velocity),
    )
    testing.expectf(t, distance > 25, "expected more than 25 m of rollout, got %.2f", distance)
    testing.expect(t, !postale.can_exit(&runtime))
}

@(test)
postale_throttle_down_held_at_touchdown_applies_brakes_progressively :: proc(t: ^testing.T) {
    runtime := postale.new_runtime(flight.Vec3{0, postale.GROUND_CLEARANCE, 0})
    runtime.grounded = false
    runtime.was_grounded = false
    runtime.body.position.y = postale.GROUND_CLEARANCE
    runtime.body.velocity =
        flight.basis_from_orientation(runtime.body.orientation).forward * 30 + flight.Vec3{0, -1, 0}

    result := postale.step(&runtime, {throttle_down = true}, 0, 1.0 / 60.0)
    speed_at_touchdown := linalg.dot(
        runtime.body.velocity,
        flight.basis_from_orientation(runtime.body.orientation).forward,
    )
    testing.expect(t, result.touched_down && runtime.grounded)

    for _ in 0 ..< 20 {
        postale.step(&runtime, {throttle_down = true}, 0, 1.0 / 60.0)
    }
    speed_after_hold := linalg.dot(
        runtime.body.velocity,
        flight.basis_from_orientation(runtime.body.orientation).forward,
    )
    testing.expectf(
        t,
        speed_after_hold > speed_at_touchdown - 3,
        "expected a held airborne L2 input to coast after touchdown, speed fell from %.2f to %.2f",
        speed_at_touchdown,
        speed_after_hold,
    )

    speed_before_braking := linalg.dot(
        runtime.body.velocity,
        flight.basis_from_orientation(runtime.body.orientation).forward,
    )
    for _ in 0 ..< 120 {
        postale.step(&runtime, {throttle_down = true}, 0, 1.0 / 60.0)
    }
    speed_after_braking := linalg.dot(
        runtime.body.velocity,
        flight.basis_from_orientation(runtime.body.orientation).forward,
    )
    testing.expectf(
        t,
        speed_after_braking < speed_before_braking - 2,
        "expected L2 pressed after release to brake, speed fell from %.2f to %.2f",
        speed_before_braking,
        speed_after_braking,
    )
}

@(test)
postale_accelerates_and_leaves_the_short_runway :: proc(t: ^testing.T) {
    runtime := postale.new_runtime(flight.Vec3{0, postale.GROUND_CLEARANCE, 0})
    run := run_takeoff(runtime.airframe.mass_kg)
    testing.expectf(
        t,
        run.took_off && !run.crashed,
        "takeoff result: took_off=%v crashed=%v speed=%.2f distance=%.2f",
        run.took_off,
        run.crashed,
        run.liftoff_speed,
        run.distance,
    )
    testing.expectf(
        t,
        run.distance >= 80 && run.distance <= 160,
        "expected an 80-160 m normal-weight takeoff roll, got %.2f m",
        run.distance,
    )
    testing.expectf(
        t,
        run.peak_ground_pitch > .0174533,
        "expected visible aerodynamic rotation before liftoff, got %.3f radians",
        run.peak_ground_pitch,
    )
}

@(test)
postale_ace_uses_shared_takeoff_policy :: proc(t: ^testing.T) {
    run := run_takeoff(3300, model = .Ace_Arcade)
    testing.expectf(
        t,
        run.took_off && !run.crashed,
        "Ace takeoff result: took_off=%v crashed=%v speed=%.2f distance=%.2f",
        run.took_off,
        run.crashed,
        run.liftoff_speed,
        run.distance,
    )
    testing.expect(t, run.distance > 0 && run.distance < 500)
    testing.expect(t, run.peak_ground_pitch > .0174533)
}

@(test)
postale_takeoff_distance_responds_to_weight_and_wind :: proc(t: ^testing.T) {
    light := run_takeoff(2800)
    normal := run_takeoff(3300)
    gross := run_takeoff(3800)
    headwind := run_takeoff(3300, flight.Vec3{4, 0, 0})
    tailwind := run_takeoff(3300, flight.Vec3{-4, 0, 0})

    testing.expectf(
        t,
        light.took_off && normal.took_off && gross.took_off && headwind.took_off && tailwind.took_off,
        "expected all takeoff conditions to fly: light=%v normal=%v gross=%v headwind=%v tailwind=%v",
        light.took_off,
        normal.took_off,
        gross.took_off,
        headwind.took_off,
        tailwind.took_off,
    )
    testing.expectf(
        t,
        light.distance < normal.distance && normal.distance < gross.distance,
        "expected takeoff distance to increase with weight: %.1f, %.1f, %.1f m",
        light.distance,
        normal.distance,
        gross.distance,
    )
    testing.expectf(
        t,
        headwind.distance < normal.distance && normal.distance < tailwind.distance,
        "expected headwind < calm < tailwind distance: %.1f, %.1f, %.1f m",
        headwind.distance,
        normal.distance,
        tailwind.distance,
    )
    testing.expectf(t, gross.distance <= 450, "gross takeoff exceeded runway: %.1f m", gross.distance)
    testing.expectf(t, tailwind.distance <= 450, "tailwind takeoff exceeded runway: %.1f m", tailwind.distance)
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
    runtime.body.velocity = flight.basis_from_orientation(runtime.body.orientation).forward * 42
    for _ in 0 ..< 45 {
        postale.step(&runtime, {roll = .7}, 0, 1.0 / 60.0)
    }
    basis := flight.basis_from_orientation(runtime.body.orientation)
    testing.expect(t, math.abs(postale.bank_radians(basis)) > .35)
}

@(test)
postale_rudder_engages_and_releases_without_snapping :: proc(t: ^testing.T) {
    runtime := postale.new_runtime(flight.Vec3{0, 80, 0})
    runtime.grounded = false
    runtime.was_grounded = false
    runtime.body.velocity = flight.basis_from_orientation(runtime.body.orientation).forward * 42
    postale.step(&runtime, {yaw = 1}, 0, 1.0 / 60.0)
    engaged := runtime.yaw
    testing.expect(t, engaged > 0 && engaged < 1)
    postale.step(&runtime, {}, 0, 1.0 / 60.0)
    testing.expect(t, runtime.yaw >= 0 && runtime.yaw < engaged)
}

@(test)
postale_reset_restores_the_runway_state :: proc(t: ^testing.T) {
    runtime := postale.new_runtime(flight.Vec3{4, postale.GROUND_CLEARANCE, 2})
    runtime.flight_model = .Ace_Arcade
    runtime.ace_tuning.pace = .73
    runtime.ace_runtime = {
        energy       = .9,
        edge_state   = .Break,
        edge_seconds = 2,
        local_rate   = {1, 2, 3},
    }
    runtime.ace_telemetry = {
        pace                 = .8,
        energy               = .6,
        track_grip           = .4,
        attitude_track_angle = .2,
        edge_state           = .Hang,
    }
    ace_tuning := runtime.ace_tuning
    runtime.body.position = {99, -5, 0}
    runtime.body.velocity = {12, 0, 0}
    runtime.throttle = 1
    runtime.flight_runtime.engine_output = 0
    runtime.flight_runtime.control_authority = 0
    runtime.flight_runtime.controls_damaged = true
    runtime.crashed = true
    postale.reset(&runtime, 3)
    expected_height := 3 + postale.GROUND_CLEARANCE - postale.static_gear_compression(&runtime)
    testing.expect(t, runtime.body.position.x == 4 && runtime.body.position.y == expected_height)
    testing.expect(t, runtime.body.velocity == flight.Vec3{} && runtime.throttle == 0)
    testing.expect(t, runtime.flight_runtime.engine_output == 1)
    testing.expect(t, runtime.flight_runtime.control_authority == 1)
    testing.expect(t, !runtime.flight_runtime.controls_damaged)
    testing.expect(t, runtime.flight_model == .Ace_Arcade)
    testing.expect(t, runtime.ace_tuning == ace_tuning)
    testing.expect(t, runtime.ace_runtime == flight.default_ace_runtime(runtime.body, ace_tuning))
    testing.expect(t, runtime.ace_telemetry == flight.Ace_Telemetry{})
    testing.expect(t, runtime.grounded && !runtime.crashed)
}
