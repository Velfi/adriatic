package tests

import flight "../packages/flight"
import postale "../packages/postale"
import vehicles "../packages/vehicles"
import "core:testing"

@(test)
postale_checkpoint_rejects_nil_runtime :: proc(t: ^testing.T) {
    _, captured := postale.capture_checkpoint(nil)
    testing.expect(t, !captured)
    testing.expect(t, !postale.restore_checkpoint(nil, {}))
    runtime := postale.new_runtime({})
    testing.expect(t, !postale.restore_checkpoint(&runtime, {}))
}

@(test)
postale_checkpoint_round_trips_owned_state_and_preserves_driver :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({3, postale.GROUND_CLEARANCE, 7})
    driver := vehicles.Character {
        mode    = .Driving,
        vehicle = &runtime.vehicle,
    }
    runtime.vehicle.driver = &driver
    runtime.body = {
        position               = {14, 73, -9},
        velocity               = {31, -2, 5},
        angular_velocity_world = {.2, -.3, .4},
        orientation            = flight.orientation_from_forward_and_up({-.8, .3, -.4}, {.2, .9, .1}),
    }
    runtime.airframe.mass_kg = 1830
    runtime.flight_runtime = {
        engine_output     = .81,
        control_authority = .72,
        drag_multiplier   = 1.3,
        controls_damaged  = true,
    }
    runtime.telemetry = {
        airspeed                = 47,
        angle_of_attack_degrees = 12,
        effective_stall_speed   = 23,
        lift_coefficient        = 1.2,
        is_stalling             = true,
    }
    runtime.flight_model = .Ace_Arcade
    runtime.ace_tuning = postale.ace_tuning_preset()
    runtime.ace_tuning.pace = .83
    runtime.ace_tuning.roll_snap = .76
    runtime.ace_tuning.hang_time = .91
    runtime.ace_tuning.exit_catch = .68
    runtime.ace_runtime = {
        energy       = .74,
        edge_state   = .Hang,
        edge_seconds = 1.25,
        local_rate   = {.7, -.4, .2},
    }
    runtime.ace_telemetry = {
        pace                 = 52,
        energy               = .74,
        track_grip           = .36,
        attitude_track_angle = .48,
        edge_state           = .Hang,
    }
    runtime.throttle = .63
    runtime.flap_fraction = .35
    runtime.propeller_turns = 18
    runtime.pitch = -.2
    runtime.roll = .7
    runtime.yaw = -.4
    runtime.grounded = false
    runtime.crashed = false
    runtime.was_grounded = false
    runtime.grounded_time = .45
    runtime.ground_pitch_radians = .08
    runtime.ground_brake_amount = .37
    runtime.gear_compression = .12
    runtime.gear_force = 1234
    runtime.structural_damage = .27
    runtime.last_landing = {
        outcome      = .Hard_Landing,
        sink_speed   = 4.2,
        weight_force = 23000,
        impact_force = 72000,
        load_factor  = 3.1,
        damage       = .2,
    }
    runtime.landing_feedback_seconds = 2.5
    runtime.landing_intent_seconds = .31
    runtime.landing_intent = true
    runtime.spawn_position = {-4, 2, 11}
    runtime.spawn_orientation = flight.identity_orientation()
    runtime.tuning.takeoff_speed_scale = 1.08
    runtime.vehicle.interaction_radius = 4
    runtime.vehicle.exit_distance = 3
    runtime.vehicle.locked = true

    checkpoint, captured := postale.capture_checkpoint(&runtime)
    testing.expect(t, captured)
    testing.expect(t, checkpoint.flight_model == runtime.flight_model)
    testing.expect(t, checkpoint.ace_tuning == runtime.ace_tuning)
    testing.expect(t, checkpoint.ace_runtime == runtime.ace_runtime)
    testing.expect(t, checkpoint.ace_telemetry == runtime.ace_telemetry)

    postale.reset(&runtime, 0)
    runtime.ace_tuning = {}
    runtime.ace_runtime = {}
    runtime.ace_telemetry = {}
    runtime.vehicle.driver = &driver
    driver.vehicle = &runtime.vehicle
    testing.expect(t, postale.restore_checkpoint(&runtime, checkpoint))

    restored, recaptured := postale.capture_checkpoint(&runtime)
    testing.expect(t, recaptured)
    testing.expect(t, restored == checkpoint)
    testing.expect(t, runtime.vehicle.driver == &driver)
    testing.expect(t, driver.vehicle == &runtime.vehicle)
    testing.expect(t, driver.position == runtime.vehicle.position)
    testing.expect(t, driver.facing_yaw_radians == runtime.vehicle.yaw_radians)
}

@(test)
postale_checkpoint_does_not_transfer_driver_between_runtimes :: proc(t: ^testing.T) {
    source := postale.new_runtime({8, postale.GROUND_CLEARANCE, 2})
    source_driver := vehicles.Character {
        mode    = .Driving,
        vehicle = &source.vehicle,
    }
    source.vehicle.driver = &source_driver
    source.body.position = {12, 45, -3}
    checkpoint, captured := postale.capture_checkpoint(&source)
    testing.expect(t, captured)

    target := postale.new_runtime({-8, postale.GROUND_CLEARANCE, -2})
    target_driver := vehicles.Character {
        mode    = .Driving,
        vehicle = &target.vehicle,
    }
    target.vehicle.driver = &target_driver

    testing.expect(t, postale.restore_checkpoint(&target, checkpoint))
    testing.expect(t, source.vehicle.driver == &source_driver)
    testing.expect(t, source_driver.vehicle == &source.vehicle)
    testing.expect(t, target.vehicle.driver == &target_driver)
    testing.expect(t, target_driver.vehicle == &target.vehicle)
    testing.expect(t, target_driver.position == target.vehicle.position)
    testing.expect(t, target_driver.facing_yaw_radians == target.vehicle.yaw_radians)
}

@(test)
postale_checkpoint_replays_identical_continuation :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({0, postale.GROUND_CLEARANCE, 0})
    runtime.body.position = {0, 90, 0}
    runtime.body.velocity = flight.basis_from_orientation(runtime.body.orientation).forward * 42
    runtime.grounded = false
    runtime.was_grounded = false
    runtime.throttle = .65
    runtime.flap_fraction = 0
    runtime.pitch = .12
    runtime.roll = -.08
    runtime.yaw = .04

    checkpoint, captured := postale.capture_checkpoint(&runtime)
    testing.expect(t, captured)

    for frame in 0 ..< 180 {
        control := postale.Control {
            throttle_up = frame < 60,
            pitch       = frame < 90 ? f32(.45) : f32(-.2),
            roll        = frame < 120 ? f32(.6) : f32(-.35),
            yaw         = frame < 75 ? f32(.2) : f32(-.1),
        }
        postale.step(&runtime, control, 0, 1.0 / 60.0)
    }
    expected, expected_ok := postale.capture_checkpoint(&runtime)
    testing.expect(t, expected_ok)

    testing.expect(t, postale.restore_checkpoint(&runtime, checkpoint))
    for frame in 0 ..< 180 {
        control := postale.Control {
            throttle_up = frame < 60,
            pitch       = frame < 90 ? f32(.45) : f32(-.2),
            roll        = frame < 120 ? f32(.6) : f32(-.35),
            yaw         = frame < 75 ? f32(.2) : f32(-.1),
        }
        postale.step(&runtime, control, 0, 1.0 / 60.0)
    }
    actual, actual_ok := postale.capture_checkpoint(&runtime)
    testing.expect(t, actual_ok)
    testing.expect(t, actual == expected)
}

@(test)
postale_checkpoint_replays_identical_ace_continuation :: proc(t: ^testing.T) {
    runtime := postale.new_runtime({0, postale.GROUND_CLEARANCE, 0})
    runtime.flight_model = .Ace_Arcade
    runtime.body.position = {0, 90, 0}
    runtime.body.velocity = flight.basis_from_orientation(runtime.body.orientation).forward * 52
    runtime.grounded = false
    runtime.was_grounded = false
    runtime.throttle = .72
    runtime.flap_fraction = 0
    runtime.ace_runtime.energy = .78

    checkpoint, captured := postale.capture_checkpoint(&runtime)
    testing.expect(t, captured)

    commands := [?]flight.Control_Command {
        {pitch = .45, roll = .7, yaw = .1, throttle = .85},
        {pitch = .2, roll = -.5, yaw = -.35, throttle = .7},
        {pitch = -.55, roll = .15, yaw = .4, throttle = 1},
        {throttle = .6},
    }
    for _ in 0 ..< 45 {
        for command in commands {
            postale.step_normalized_command(&runtime, command, -1000, 1.0 / 120.0)
        }
    }
    expected, expected_ok := postale.capture_checkpoint(&runtime)
    testing.expect(t, expected_ok)
    testing.expect(t, expected.flight_runtime == checkpoint.flight_runtime)
    testing.expect(t, expected.telemetry == checkpoint.telemetry)

    testing.expect(t, postale.restore_checkpoint(&runtime, checkpoint))
    for _ in 0 ..< 45 {
        for command in commands {
            postale.step_normalized_command(&runtime, command, -1000, 1.0 / 120.0)
        }
    }
    actual, actual_ok := postale.capture_checkpoint(&runtime)
    testing.expect(t, actual_ok)
    testing.expect(t, actual == expected)
}
