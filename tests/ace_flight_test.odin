package tests

import flight "../packages/flight"
import "core:math"
import "core:math/linalg"
import "core:testing"

ace_knob_values :: proc(tuning: flight.Ace_Tuning) -> [22]f32 {
    return {
        tuning.pace,
        tuning.punch,
        tuning.coast,
        tuning.brake,
        tuning.roll_snap,
        tuning.pull_strength,
        tuning.rudder_bite,
        tuning.weight,
        tuning.settle,
        tuning.air_grip,
        tuning.drift,
        tuning.turn_hold,
        tuning.climb_generosity,
        tuning.dive_payoff,
        tuning.hang_time,
        tuning.break_drama,
        tuning.recovery_punch,
        tuning.low_speed_authority,
        tuning.steadiness,
        tuning.line_hold,
        tuning.commitment,
        tuning.exit_catch,
    }
}

ace_uniform_tuning :: proc(value: f32) -> flight.Ace_Tuning {
    return {
        pace = value,
        punch = value,
        coast = value,
        brake = value,
        roll_snap = value,
        pull_strength = value,
        rudder_bite = value,
        weight = value,
        settle = value,
        air_grip = value,
        drift = value,
        turn_hold = value,
        climb_generosity = value,
        dive_payoff = value,
        hang_time = value,
        break_drama = value,
        recovery_punch = value,
        low_speed_authority = value,
        steadiness = value,
        line_hold = value,
        commitment = value,
        exit_catch = value,
    }
}

ace_expect_safe_derived_tuning :: proc(t: ^testing.T, tuning: flight.Ace_Derived_Tuning) {
    values := [?]f32 {
        tuning.minimum_pace,
        tuning.cruise_pace,
        tuning.dive_pace,
        tuning.maximum_pitch_rate,
        tuning.maximum_roll_rate,
        tuning.maximum_yaw_rate,
        tuning.engage_response,
        tuning.roll_engage_response,
        tuning.release_response,
        tuning.pace_punch_response,
        tuning.pace_coast_loss_response,
        tuning.pace_brake_response,
        tuning.track_grip_response,
        tuning.track_retention,
        tuning.throttle_energy_gain,
        tuning.dive_energy_gain,
        tuning.climb_energy_cost,
        tuning.turn_energy_cost,
        tuning.slip_energy_cost,
        tuning.inverted_energy_cost,
        tuning.edge_energy_cost,
        tuning.turn_pace_loss,
        tuning.climb_pace_loss,
        tuning.warning_margin,
        tuning.hang_margin,
        tuning.break_margin,
        tuning.recovery_margin,
        tuning.warning_min_seconds,
        tuning.hang_seconds,
        tuning.break_min_seconds,
        tuning.recovery_min_seconds,
        tuning.break_pitch_drama,
        tuning.break_roll_drama,
        tuning.break_track_drama,
        tuning.recovery_response,
        tuning.recovery_energy_gain,
        tuning.low_energy_pitch_authority,
        tuning.low_energy_roll_authority,
        tuning.low_energy_yaw_authority,
        tuning.steadiness_response,
        tuning.line_hold_response,
        tuning.commitment_threshold,
        tuning.exit_catch_seconds,
        tuning.exit_catch_response,
    }
    for value in values {
        testing.expect(t, value == value && !math.is_inf_f32(value))
    }
    for value in values[:len(values) - 2] {
        testing.expect(t, value > 0)
    }
    testing.expect(t, tuning.exit_catch_seconds >= 0)
    testing.expect(t, tuning.exit_catch_response >= 0)
}

ace_expect_ordered_derived_tuning :: proc(t: ^testing.T, tuning: flight.Ace_Derived_Tuning) {
    testing.expect(t, tuning.minimum_pace < tuning.cruise_pace)
    testing.expect(t, tuning.cruise_pace < tuning.dive_pace)
    testing.expect(t, tuning.maximum_yaw_rate < tuning.maximum_pitch_rate)
    testing.expect(t, tuning.maximum_pitch_rate < tuning.maximum_roll_rate)
    testing.expect(t, tuning.break_margin < tuning.hang_margin)
    testing.expect(t, tuning.hang_margin < tuning.warning_margin)
    testing.expect(t, tuning.warning_margin < tuning.recovery_margin)
    testing.expect(t, tuning.warning_min_seconds < tuning.hang_seconds)
    testing.expect(t, tuning.warning_min_seconds < tuning.break_min_seconds)
    testing.expect(t, tuning.low_energy_pitch_authority < tuning.low_energy_roll_authority)
    testing.expect(t, tuning.low_energy_roll_authority < tuning.low_energy_yaw_authority)
}

@(test)
ace_defaults_are_safe_and_valid :: proc(t: ^testing.T) {
    tuning := flight.default_ace_tuning()
    testing.expect(t, flight.ace_tuning_is_valid(tuning))
    for knob in ace_knob_values(tuning) {
        testing.expect(t, knob >= 0 && knob <= 1)
    }

    runtime := flight.default_ace_runtime({}, tuning)
    testing.expect(t, runtime.energy >= 0 && runtime.energy <= 1)
    testing.expect(t, runtime.energy == 0)
    testing.expect(t, runtime.edge_state == .Free)
    testing.expect(t, runtime.edge_seconds == 0)
    testing.expect(t, runtime.local_rate == flight.Vec3{})

    telemetry := flight.Ace_Telemetry{}
    testing.expect(t, telemetry.pace == 0)
    testing.expect(t, telemetry.energy == 0)
    testing.expect(t, telemetry.track_grip == 0)
    testing.expect(t, telemetry.attitude_track_angle == 0)
    testing.expect(t, telemetry.edge_state == .Free)
}

@(test)
ace_derived_tuning_endpoints_stay_finite_positive_and_ordered :: proc(t: ^testing.T) {
    low := flight.derive_ace_tuning(ace_uniform_tuning(0))
    high := flight.derive_ace_tuning(ace_uniform_tuning(1))
    ace_expect_safe_derived_tuning(t, low)
    ace_expect_safe_derived_tuning(t, high)
    ace_expect_ordered_derived_tuning(t, low)
    ace_expect_ordered_derived_tuning(t, high)
}

@(test)
ace_every_designer_knob_has_monotonic_visible_meaning :: proc(t: ^testing.T) {
    low, high := flight.default_ace_tuning(), flight.default_ace_tuning()

    low.pace, high.pace = 0, 1
    low_values, high_values := flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.minimum_pace > low_values.minimum_pace)
    testing.expect(t, high_values.cruise_pace > low_values.cruise_pace)
    testing.expect(t, high_values.dive_pace > low_values.dive_pace)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.punch, high.punch = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.pace_punch_response > low_values.pace_punch_response)
    testing.expect(t, high_values.throttle_energy_gain > low_values.throttle_energy_gain)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.coast, high.coast = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.pace_coast_loss_response < low_values.pace_coast_loss_response)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.brake, high.brake = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.pace_brake_response > low_values.pace_brake_response)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.roll_snap, high.roll_snap = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.maximum_roll_rate > low_values.maximum_roll_rate)
    testing.expect(t, high_values.roll_engage_response > low_values.roll_engage_response)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.pull_strength, high.pull_strength = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.maximum_pitch_rate > low_values.maximum_pitch_rate)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.rudder_bite, high.rudder_bite = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.maximum_yaw_rate > low_values.maximum_yaw_rate)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.weight, high.weight = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.engage_response < low_values.engage_response)
    testing.expect(t, high_values.roll_engage_response < low_values.roll_engage_response)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.settle, high.settle = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.release_response > low_values.release_response)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.air_grip, high.air_grip = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.track_grip_response > low_values.track_grip_response)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.drift, high.drift = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.track_retention > low_values.track_retention)
    testing.expect(t, high_values.track_grip_response < low_values.track_grip_response)
    testing.expect(t, high_values.slip_energy_cost < low_values.slip_energy_cost)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.turn_hold, high.turn_hold = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.turn_pace_loss < low_values.turn_pace_loss)
    testing.expect(t, high_values.turn_energy_cost < low_values.turn_energy_cost)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.climb_generosity, high.climb_generosity = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.climb_energy_cost < low_values.climb_energy_cost)
    testing.expect(t, high_values.climb_pace_loss < low_values.climb_pace_loss)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.dive_payoff, high.dive_payoff = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.dive_energy_gain > low_values.dive_energy_gain)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.hang_time, high.hang_time = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.hang_seconds > low_values.hang_seconds)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.break_drama, high.break_drama = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.break_pitch_drama > low_values.break_pitch_drama)
    testing.expect(t, high_values.break_roll_drama > low_values.break_roll_drama)
    testing.expect(t, high_values.break_track_drama > low_values.break_track_drama)
    testing.expect(t, high_values.break_min_seconds == low_values.break_min_seconds)
    testing.expect(t, high_values.edge_energy_cost == low_values.edge_energy_cost)
    testing.expect(t, high_values.warning_margin == low_values.warning_margin)
    testing.expect(t, high_values.hang_margin == low_values.hang_margin)
    testing.expect(t, high_values.break_margin == low_values.break_margin)
    testing.expect(t, high_values.recovery_margin == low_values.recovery_margin)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.recovery_punch, high.recovery_punch = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.recovery_response > low_values.recovery_response)
    testing.expect(t, high_values.recovery_energy_gain > low_values.recovery_energy_gain)
    testing.expect(t, high_values.recovery_min_seconds < low_values.recovery_min_seconds)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.low_speed_authority, high.low_speed_authority = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.low_energy_pitch_authority > low_values.low_energy_pitch_authority)
    testing.expect(t, high_values.low_energy_roll_authority > low_values.low_energy_roll_authority)
    testing.expect(t, high_values.low_energy_yaw_authority > low_values.low_energy_yaw_authority)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.steadiness, high.steadiness = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.steadiness_response > low_values.steadiness_response)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.line_hold, high.line_hold = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.line_hold_response > low_values.line_hold_response)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.commitment, high.commitment = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, high_values.commitment_threshold < low_values.commitment_threshold)

    low, high = flight.default_ace_tuning(), flight.default_ace_tuning()
    low.exit_catch, high.exit_catch = 0, 1
    low_values, high_values = flight.derive_ace_tuning(low), flight.derive_ace_tuning(high)
    testing.expect(t, low_values.exit_catch_seconds == 0)
    testing.expect(t, low_values.exit_catch_response == 0)
    testing.expect(t, high_values.exit_catch_seconds > low_values.exit_catch_seconds)
    testing.expect(t, high_values.exit_catch_response > low_values.exit_catch_response)
}

@(test)
ace_tuning_clamps_every_knob_and_rejects_invalid_input :: proc(t: ^testing.T) {
    invalid := flight.Ace_Tuning {
        pace                = f32(0h7fc0_0000),
        punch               = f32(0h7f80_0000),
        coast               = -1,
        brake               = 2,
        roll_snap           = -1,
        pull_strength       = 2,
        rudder_bite         = -1,
        weight              = 2,
        settle              = -1,
        air_grip            = 2,
        drift               = -1,
        turn_hold           = 2,
        climb_generosity    = -1,
        dive_payoff         = 2,
        hang_time           = -1,
        break_drama         = 2,
        recovery_punch      = -1,
        low_speed_authority = 2,
        steadiness          = -1,
        line_hold           = 2,
        commitment          = -1,
        exit_catch          = 2,
    }
    testing.expect(t, !flight.ace_tuning_is_valid(invalid))

    tuning := flight.clamp_ace_tuning(invalid)
    testing.expect(t, flight.ace_tuning_is_valid(tuning))
    for knob in ace_knob_values(tuning) {
        testing.expect(t, knob >= 0 && knob <= 1)
    }
    testing.expect(t, tuning.pace == 0)
    testing.expect(t, tuning.punch == 1)
    testing.expect(t, tuning.coast == 0)
    testing.expect(t, tuning.brake == 1)
}

@(test)
ace_runtime_seeds_local_rate_from_body_state :: proc(t: ^testing.T) {
    body := flight.Body_State {
        angular_velocity_world = {1, 2, -3},
        orientation            = flight.identity_orientation(),
    }
    runtime := flight.default_ace_runtime(body, flight.default_ace_tuning())
    testing.expect(t, runtime.local_rate == flight.Vec3{1, 2, 3})
    testing.expect(t, runtime.energy == 0)
    testing.expect(t, runtime.edge_state == .Free)
}

@(test)
ace_model_modifiers_extract_shared_product_intent :: proc(t: ^testing.T) {
    modifiers := flight.model_modifiers_from_runtime(flight.default_runtime())
    testing.expect(
        t,
        modifiers == flight.Model_Modifiers{engine_output = 1, control_authority = 1, controls_damaged = false},
    )

    runtime := flight.default_runtime()
    runtime.engine_output = -1
    runtime.control_authority = 2
    runtime.controls_damaged = true
    modifiers = flight.model_modifiers_from_runtime(runtime)
    testing.expect(t, modifiers.engine_output == 0)
    testing.expect(t, modifiers.control_authority == 1)
    testing.expect(t, modifiers.controls_damaged)

    runtime.engine_output = f32(0h7fc0_0000)
    runtime.control_authority = f32(0h7f80_0000)
    modifiers = flight.model_modifiers_from_runtime(runtime)
    testing.expect(t, modifiers.engine_output == 0)
    testing.expect(t, modifiers.control_authority == 1)

    runtime.engine_output = f32(0hff80_0000)
    runtime.control_authority = -1
    modifiers = flight.model_modifiers_from_runtime(runtime)
    testing.expect(t, modifiers.engine_output == 0)
    testing.expect(t, modifiers.control_authority == 0)
}

@(test)
ace_model_modifiers_ignore_legacy_aero_only_fields :: proc(t: ^testing.T) {
    runtime := flight.default_runtime()
    baseline := flight.model_modifiers_from_runtime(runtime)
    runtime.drag_multiplier = 0
    testing.expect(t, flight.model_modifiers_from_runtime(runtime) == baseline)
}

ace_step_angular_n :: proc(
    body: ^flight.Body_State,
    command: flight.Control_Command,
    tuning: flight.Ace_Tuning,
    runtime: ^flight.Ace_Runtime,
    modifiers: flight.Model_Modifiers,
    step_count: int,
) {
    derived := flight.derive_ace_tuning(tuning)
    for _ in 0 ..< step_count {
        flight.ace_step_angular(body, command, derived, runtime, modifiers, 1.0 / 120.0)
    }
}

ace_angular_response :: proc(
    command: flight.Control_Command,
    tuning: flight.Ace_Tuning,
    energy: f32 = 1,
    modifiers: flight.Model_Modifiers = {control_authority = 1},
    step_count: int = 1,
) -> flight.Ace_Runtime {
    body := flight.Body_State {
        orientation = flight.identity_orientation(),
    }
    runtime := flight.Ace_Runtime {
        energy = energy,
    }
    ace_step_angular_n(&body, command, tuning, &runtime, modifiers, step_count)
    return runtime
}

@(test)
ace_angular_invalid_step_does_not_mutate_state :: proc(t: ^testing.T) {
    body := flight.Body_State {
        orientation            = flight.identity_orientation(),
        angular_velocity_world = {1, 2, 3},
    }
    runtime := flight.Ace_Runtime {
        energy     = .5,
        local_rate = {4, 5, 6},
    }
    body_before, runtime_before := body, runtime
    derived := flight.derive_ace_tuning(flight.default_ace_tuning())

    flight.ace_step_angular(nil, {}, derived, &runtime, {}, 1.0 / 120.0)
    testing.expect(t, runtime == runtime_before)
    flight.ace_step_angular(&body, {}, derived, nil, {}, 1.0 / 120.0)
    testing.expect(t, body == body_before)
    flight.ace_step_angular(&body, {}, derived, &runtime, {}, 0)
    testing.expect(t, body == body_before)
    testing.expect(t, runtime == runtime_before)
    flight.ace_step_angular(&body, {}, derived, &runtime, {}, -1)
    testing.expect(t, body == body_before)
    testing.expect(t, runtime == runtime_before)

    invalid_steps := [?]f32{f32(0h7fc0_0000), f32(0h7f80_0000), .051}
    for delta_seconds in invalid_steps {
        flight.ace_step_angular(&body, {}, derived, &runtime, {}, delta_seconds)
        testing.expect(t, body == body_before)
        testing.expect(t, runtime == runtime_before)
    }
}

@(test)
ace_angular_rejects_nonfinite_body_rate_before_mutation :: proc(t: ^testing.T) {
    derived := flight.derive_ace_tuning(flight.default_ace_tuning())
    runtime := flight.Ace_Runtime {
        energy     = .5,
        local_rate = {4, 5, 6},
    }
    runtime_before := runtime

    nan_body := flight.Body_State {
        angular_velocity_world = {f32(0h7fc0_0000), 2, 3},
    }
    nan_orientation_before := nan_body.orientation
    flight.ace_step_angular(&nan_body, {}, derived, &runtime, {}, 1.0 / 120.0)
    testing.expect(t, nan_body.orientation == nan_orientation_before)
    testing.expect(t, nan_body.angular_velocity_world.x != nan_body.angular_velocity_world.x)
    testing.expect(t, nan_body.angular_velocity_world.y == 2)
    testing.expect(t, nan_body.angular_velocity_world.z == 3)
    testing.expect(t, runtime == runtime_before)

    infinite_body := flight.Body_State {
        angular_velocity_world = {1, 2, f32(0h7f80_0000)},
    }
    infinite_orientation_before := infinite_body.orientation
    flight.ace_step_angular(&infinite_body, {}, derived, &runtime, {}, 1.0 / 120.0)
    testing.expect(t, infinite_body.orientation == infinite_orientation_before)
    testing.expect(t, infinite_body.angular_velocity_world.x == 1)
    testing.expect(t, infinite_body.angular_velocity_world.y == 2)
    testing.expect(t, math.is_inf_f32(infinite_body.angular_velocity_world.z))
    testing.expect(t, runtime == runtime_before)
}

@(test)
ace_angular_repairs_zero_orientation_and_rejects_nonfinite_orientation :: proc(t: ^testing.T) {
    derived := flight.derive_ace_tuning(flight.default_ace_tuning())
    modifiers := flight.Model_Modifiers {
        control_authority = 1,
    }
    zero_body := flight.Body_State{}
    zero_runtime := flight.Ace_Runtime {
        energy = .5,
    }
    flight.ace_step_angular(&zero_body, {}, derived, &zero_runtime, modifiers, 1.0 / 120.0)
    testing.expect(t, zero_body.orientation == flight.identity_orientation())

    nan_body := flight.Body_State {
        orientation            = flight.identity_orientation(),
        angular_velocity_world = {1, 2, 3},
    }
    nan_body.orientation.x = f32(0h7fc0_0000)
    nan_runtime := flight.Ace_Runtime {
        energy     = .5,
        local_rate = {4, 5, 6},
    }
    nan_rate_before, nan_runtime_before := nan_body.angular_velocity_world, nan_runtime
    flight.ace_step_angular(&nan_body, {}, derived, &nan_runtime, modifiers, 1.0 / 120.0)
    testing.expect(t, nan_body.orientation.x != nan_body.orientation.x)
    testing.expect(t, nan_body.orientation.y == 0)
    testing.expect(t, nan_body.orientation.z == 0)
    testing.expect(t, nan_body.orientation.w == 1)
    testing.expect(t, nan_body.angular_velocity_world == nan_rate_before)
    testing.expect(t, nan_runtime == nan_runtime_before)

    infinite_body := flight.Body_State {
        orientation            = flight.identity_orientation(),
        angular_velocity_world = {1, 2, 3},
    }
    infinite_body.orientation.w = f32(0h7f80_0000)
    infinite_runtime := flight.Ace_Runtime {
        energy     = .5,
        local_rate = {4, 5, 6},
    }
    infinite_rate_before, infinite_runtime_before := infinite_body.angular_velocity_world, infinite_runtime
    flight.ace_step_angular(&infinite_body, {}, derived, &infinite_runtime, modifiers, 1.0 / 120.0)
    testing.expect(t, infinite_body.orientation.x == 0)
    testing.expect(t, infinite_body.orientation.y == 0)
    testing.expect(t, infinite_body.orientation.z == 0)
    testing.expect(t, math.is_inf_f32(infinite_body.orientation.w))
    testing.expect(t, infinite_body.angular_velocity_world == infinite_rate_before)
    testing.expect(t, infinite_runtime == infinite_runtime_before)
}

@(test)
ace_neutral_command_settles_seeded_angular_rate :: proc(t: ^testing.T) {
    body := flight.Body_State {
        orientation            = flight.identity_orientation(),
        angular_velocity_world = {1, 2, -3},
    }
    runtime := flight.default_ace_runtime(body, flight.default_ace_tuning())
    initial_rate := runtime.local_rate

    ace_step_angular_n(&body, {}, flight.default_ace_tuning(), &runtime, {control_authority = 1}, 30)

    testing.expect(t, math.abs(runtime.local_rate.x) < math.abs(initial_rate.x))
    testing.expect(t, math.abs(runtime.local_rate.y) < math.abs(initial_rate.y))
    testing.expect(t, math.abs(runtime.local_rate.z) < math.abs(initial_rate.z))
}

@(test)
ace_angular_input_is_precise_monotonic_and_reaches_full_authority :: proc(t: ^testing.T) {
    tuning := flight.default_ace_tuning()
    small := ace_angular_response({roll = .1}, tuning, step_count = 60)
    half := ace_angular_response({roll = .5}, tuning, step_count = 60)
    full := ace_angular_response({roll = 1}, tuning, step_count = 60)
    maximum_roll_rate := flight.derive_ace_tuning(tuning).maximum_roll_rate

    testing.expect(t, small.local_rate.z > 0)
    testing.expect(t, small.local_rate.z < half.local_rate.z)
    testing.expect(t, half.local_rate.z < full.local_rate.z)
    testing.expect(t, small.local_rate.z < maximum_roll_rate * .1)
    testing.expect(t, full.local_rate.z > maximum_roll_rate * .95)
}

@(test)
ace_commitment_only_advances_strong_input_response :: proc(t: ^testing.T) {
    low, high := flight.default_ace_tuning(), flight.default_ace_tuning()
    low.commitment, high.commitment = 0, 1

    weak_low := ace_angular_response({roll = .5}, tuning = low, step_count = 60)
    weak_high := ace_angular_response({roll = .5}, tuning = high, step_count = 60)
    strong_low := ace_angular_response({roll = .8}, tuning = low, step_count = 60)
    strong_high := ace_angular_response({roll = .8}, tuning = high, step_count = 60)

    testing.expect(t, weak_low.local_rate.z == weak_high.local_rate.z)
    testing.expect(t, strong_high.local_rate.z > strong_low.local_rate.z)
}

@(test)
ace_roll_snap_raises_roll_rate :: proc(t: ^testing.T) {
    low, high := flight.default_ace_tuning(), flight.default_ace_tuning()
    low.roll_snap, high.roll_snap = 0, 1

    low_response := ace_angular_response({roll = 1}, tuning = low, step_count = 30)
    high_response := ace_angular_response({roll = 1}, tuning = high, step_count = 30)

    testing.expect(t, high_response.local_rate.z > low_response.local_rate.z)
}

@(test)
ace_weight_slows_initial_angular_engagement :: proc(t: ^testing.T) {
    light, heavy := flight.default_ace_tuning(), flight.default_ace_tuning()
    light.weight, heavy.weight = 0, 1

    light_response := ace_angular_response({pitch = 1}, tuning = light)
    heavy_response := ace_angular_response({pitch = 1}, tuning = heavy)

    testing.expect(t, light_response.local_rate.x > heavy_response.local_rate.x)
}

@(test)
ace_settle_stops_released_rotation_faster :: proc(t: ^testing.T) {
    low, high := flight.default_ace_tuning(), flight.default_ace_tuning()
    low.settle, high.settle = 0, 1
    low_body := flight.Body_State {
        orientation            = flight.identity_orientation(),
        angular_velocity_world = {0, 0, -2},
    }
    high_body := low_body
    low_runtime := flight.default_ace_runtime(low_body, low)
    high_runtime := flight.default_ace_runtime(high_body, high)

    ace_step_angular_n(&low_body, {}, low, &low_runtime, {control_authority = 1}, 12)
    ace_step_angular_n(&high_body, {}, high, &high_runtime, {control_authority = 1}, 12)

    testing.expect(t, math.abs(high_runtime.local_rate.z) < math.abs(low_runtime.local_rate.z))
}

@(test)
ace_settle_accelerates_partial_release_and_reversal :: proc(t: ^testing.T) {
    low, high := flight.default_ace_tuning(), flight.default_ace_tuning()
    low.settle, high.settle = 0, 1
    partial_low_body := flight.Body_State {
        orientation            = flight.identity_orientation(),
        angular_velocity_world = {0, 0, -4},
    }
    partial_high_body := partial_low_body
    partial_low_runtime := flight.default_ace_runtime(partial_low_body, low)
    partial_high_runtime := flight.default_ace_runtime(partial_high_body, high)

    ace_step_angular_n(&partial_low_body, {roll = .5}, low, &partial_low_runtime, {control_authority = 1}, 1)
    ace_step_angular_n(&partial_high_body, {roll = .5}, high, &partial_high_runtime, {control_authority = 1}, 1)
    testing.expect(t, partial_high_runtime.local_rate.z < partial_low_runtime.local_rate.z)

    reverse_low_body := flight.Body_State {
        orientation            = flight.identity_orientation(),
        angular_velocity_world = {0, 0, -2},
    }
    reverse_high_body := reverse_low_body
    reverse_low_runtime := flight.default_ace_runtime(reverse_low_body, low)
    reverse_high_runtime := flight.default_ace_runtime(reverse_high_body, high)

    ace_step_angular_n(&reverse_low_body, {roll = -1}, low, &reverse_low_runtime, {control_authority = 1}, 1)
    ace_step_angular_n(&reverse_high_body, {roll = -1}, high, &reverse_high_runtime, {control_authority = 1}, 1)
    testing.expect(t, reverse_high_runtime.local_rate.z < reverse_low_runtime.local_rate.z)
}

@(test)
ace_steadiness_bonus_only_applies_to_neutral_command :: proc(t: ^testing.T) {
    low, high := flight.default_ace_tuning(), flight.default_ace_tuning()
    low.steadiness, high.steadiness = 0, 1
    active_low_body := flight.Body_State {
        orientation            = flight.identity_orientation(),
        angular_velocity_world = {0, 0, -2},
    }
    active_high_body := active_low_body
    active_low_runtime := flight.default_ace_runtime(active_low_body, low)
    active_high_runtime := flight.default_ace_runtime(active_high_body, high)
    no_authority := flight.Model_Modifiers {
        control_authority = 0,
    }

    ace_step_angular_n(&active_low_body, {roll = 1}, low, &active_low_runtime, no_authority, 1)
    ace_step_angular_n(&active_high_body, {roll = 1}, high, &active_high_runtime, no_authority, 1)
    testing.expect(t, active_low_runtime.local_rate.z == active_high_runtime.local_rate.z)

    neutral_low_body := flight.Body_State {
        orientation            = flight.identity_orientation(),
        angular_velocity_world = {0, 0, -2},
    }
    neutral_high_body := neutral_low_body
    neutral_low_runtime := flight.default_ace_runtime(neutral_low_body, low)
    neutral_high_runtime := flight.default_ace_runtime(neutral_high_body, high)

    ace_step_angular_n(&neutral_low_body, {}, low, &neutral_low_runtime, no_authority, 1)
    ace_step_angular_n(&neutral_high_body, {}, high, &neutral_high_runtime, no_authority, 1)
    testing.expect(t, neutral_high_runtime.local_rate.z < neutral_low_runtime.local_rate.z)
}

@(test)
ace_low_energy_preserves_roll_and_yaw_before_pitch :: proc(t: ^testing.T) {
    command := flight.Control_Command {
        pitch = 1,
        roll  = 1,
        yaw   = 1,
    }
    tuning := flight.default_ace_tuning()
    low := ace_angular_response(command, tuning, energy = 0, step_count = 60)
    high := ace_angular_response(command, tuning, energy = 1, step_count = 60)
    pitch_ratio := math.abs(low.local_rate.x / high.local_rate.x)
    yaw_ratio := math.abs(low.local_rate.y / high.local_rate.y)
    roll_ratio := math.abs(low.local_rate.z / high.local_rate.z)

    testing.expect(t, math.abs(low.local_rate.y) > 0)
    testing.expect(t, math.abs(low.local_rate.z) > 0)
    testing.expect(t, pitch_ratio < roll_ratio)
    testing.expect(t, pitch_ratio < yaw_ratio)
}

@(test)
ace_product_authority_and_damage_reduce_angular_response :: proc(t: ^testing.T) {
    command := flight.Control_Command {
        roll = 1,
    }
    tuning := flight.default_ace_tuning()
    normal := ace_angular_response(command, tuning, modifiers = {control_authority = 1})
    damaged := ace_angular_response(command, tuning, modifiers = {control_authority = 1, controls_damaged = true})
    suppressed := ace_angular_response(command, tuning, modifiers = {control_authority = 0})

    testing.expect(t, damaged.local_rate.z > 0)
    testing.expect(t, damaged.local_rate.z < normal.local_rate.z)
    testing.expect(t, suppressed.local_rate.z == 0)
}

@(test)
ace_angular_replay_is_exact_from_copied_state :: proc(t: ^testing.T) {
    body_a := flight.Body_State {
        orientation            = flight.identity_orientation(),
        angular_velocity_world = {.2, -.1, .3},
    }
    runtime_a := flight.Ace_Runtime {
        energy     = .37,
        local_rate = {.2, -.1, -.3},
    }
    body_b, runtime_b := body_a, runtime_a
    commands := [?]flight.Control_Command {
        {pitch = .1, roll = .8, yaw = -.2},
        {pitch = .6, roll = .5, yaw = .4},
        {pitch = -.3, roll = -.7, yaw = .9},
        {},
    }
    derived := flight.derive_ace_tuning(flight.default_ace_tuning())
    modifiers := flight.Model_Modifiers {
        control_authority = .82,
        controls_damaged  = true,
    }

    for _ in 0 ..< 30 {
        for command in commands {
            flight.ace_step_angular(&body_a, command, derived, &runtime_a, modifiers, 1.0 / 120.0)
            flight.ace_step_angular(&body_b, command, derived, &runtime_b, modifiers, 1.0 / 120.0)
        }
    }

    testing.expect(t, body_a.orientation == body_b.orientation)
    testing.expect(t, body_a.angular_velocity_world == body_b.angular_velocity_world)
    testing.expect(t, runtime_a.local_rate == runtime_b.local_rate)
}

ace_step_n :: proc(
    body: ^flight.Body_State,
    command: flight.Control_Command,
    tuning: flight.Ace_Tuning,
    runtime: ^flight.Ace_Runtime,
    modifiers: flight.Model_Modifiers,
    step_count: int,
) -> flight.Ace_Telemetry {
    telemetry: flight.Ace_Telemetry
    for _ in 0 ..< step_count {
        telemetry = flight.ace_step(body, command, tuning, runtime, modifiers, 1.0 / 120.0)
    }
    return telemetry
}

ACE_SCENARIO_DT :: f32(1.0 / 120.0)

Ace_Scenario_Metrics :: struct {
    signed_local_rotation, absolute_local_rotation: flight.Vec3,
    initial_altitude, final_altitude:               f32,
    minimum_altitude, maximum_altitude:             f32,
    minimum_pace, maximum_pace:                     f32,
    minimum_energy, maximum_energy:                 f32,
    maximum_pace_delta, maximum_energy_delta:       f32,
    heading_error:                                  f32,
}

ace_horizontal_heading :: proc(direction: flight.Vec3) -> flight.Vec3 {
    horizontal := flight.Vec3{direction.x, 0, direction.z}
    length_squared := linalg.dot(horizontal, horizontal)
    if length_squared <= 1e-8 do return {0, 0, -1}
    return horizontal / math.sqrt(length_squared)
}

ace_run_scenario :: proc(
    body: ^flight.Body_State,
    runtime: ^flight.Ace_Runtime,
    tuning: flight.Ace_Tuning,
    modifiers: flight.Model_Modifiers,
    commands: []flight.Control_Command,
) -> Ace_Scenario_Metrics {
    initial_heading := ace_horizontal_heading(body.velocity)
    initial_pace := linalg.length(body.velocity)
    metrics := Ace_Scenario_Metrics {
        initial_altitude = body.position.y,
        final_altitude   = body.position.y,
        minimum_altitude = body.position.y,
        maximum_altitude = body.position.y,
        minimum_pace     = initial_pace,
        maximum_pace     = initial_pace,
        minimum_energy   = runtime.energy,
        maximum_energy   = runtime.energy,
    }
    previous_pace, previous_energy := initial_pace, runtime.energy

    for command in commands {
        telemetry := flight.ace_step(body, command, tuning, runtime, modifiers, ACE_SCENARIO_DT)
        rotation := runtime.local_rate * ACE_SCENARIO_DT
        metrics.signed_local_rotation += rotation
        metrics.absolute_local_rotation += {math.abs(rotation.x), math.abs(rotation.y), math.abs(rotation.z)}
        metrics.minimum_altitude = min(metrics.minimum_altitude, body.position.y)
        metrics.maximum_altitude = max(metrics.maximum_altitude, body.position.y)
        metrics.minimum_pace = min(metrics.minimum_pace, telemetry.pace)
        metrics.maximum_pace = max(metrics.maximum_pace, telemetry.pace)
        metrics.minimum_energy = min(metrics.minimum_energy, telemetry.energy)
        metrics.maximum_energy = max(metrics.maximum_energy, telemetry.energy)
        metrics.maximum_pace_delta = max(metrics.maximum_pace_delta, math.abs(telemetry.pace - previous_pace))
        metrics.maximum_energy_delta = max(metrics.maximum_energy_delta, math.abs(telemetry.energy - previous_energy))
        previous_pace, previous_energy = telemetry.pace, telemetry.energy
    }

    metrics.final_altitude = body.position.y
    final_heading := ace_horizontal_heading(body.velocity)
    metrics.heading_error = math.acos(clamp(linalg.dot(initial_heading, final_heading), -1, 1))
    return metrics
}

ace_cruise_body :: proc(
    direction: flight.Vec3 = {0, 0, -1},
    pace: f32 = 60,
    up: flight.Vec3 = {0, 1, 0},
) -> flight.Body_State {
    return {velocity = direction * pace, orientation = flight.orientation_from_forward_and_up(direction, up)}
}

ace_steps_until_edge :: proc(
    body: ^flight.Body_State,
    runtime: ^flight.Ace_Runtime,
    tuning: flight.Ace_Tuning,
    command: flight.Control_Command,
    target: flight.Ace_Edge_State,
    maximum_steps: int,
    modifiers: flight.Model_Modifiers = {engine_output = 1, control_authority = 1},
) -> int {
    for tick in 0 ..< maximum_steps {
        flight.ace_step(body, command, tuning, runtime, modifiers, 1.0 / 120.0)
        if runtime.edge_state == target do return tick + 1
    }
    return -1
}

@(test)
ace_neutral_cruise_scenario_stays_stable_for_five_seconds :: proc(t: ^testing.T) {
    tuning := flight.default_ace_tuning()
    derived := flight.derive_ace_tuning(tuning)
    body := ace_cruise_body(pace = derived.cruise_pace)
    body.position.y = 100
    runtime := flight.Ace_Runtime {
        energy = 1,
    }
    commands: [600]flight.Control_Command
    for &command in commands {
        command = {
            throttle = 1,
        }
    }

    metrics := ace_run_scenario(&body, &runtime, tuning, {engine_output = 1, control_authority = 1}, commands[:])

    testing.expect(t, runtime.edge_state == .Free)
    testing.expect(t, metrics.heading_error < .1)
    testing.expect(t, math.abs(metrics.final_altitude - metrics.initial_altitude) < 40)
    testing.expect(t, metrics.minimum_pace >= derived.minimum_pace * .9)
    testing.expect(t, metrics.maximum_pace <= derived.dive_pace * 1.05)
    testing.expect(t, metrics.minimum_energy >= 0)
    testing.expect(t, metrics.maximum_energy <= 1)
}

@(test)
ace_full_roll_scenario_accumulates_more_than_one_rotation :: proc(t: ^testing.T) {
    tuning := flight.default_ace_tuning()
    derived := flight.derive_ace_tuning(tuning)
    body := ace_cruise_body(pace = derived.cruise_pace)
    runtime := flight.Ace_Runtime {
        energy = 1,
    }
    commands: [240]flight.Control_Command
    for &command in commands {
        command = {
            roll     = 1,
            throttle = 1,
        }
    }

    metrics := ace_run_scenario(&body, &runtime, tuning, {engine_output = 1, control_authority = 1}, commands[:])

    testing.expect(t, metrics.signed_local_rotation.z > f32(2 * math.PI))
    testing.expect(t, metrics.absolute_local_rotation.z < f32(4 * math.PI))
    testing.expect(t, metrics.absolute_local_rotation.x < .25)
    testing.expect(t, metrics.absolute_local_rotation.y < .25)
    testing.expect(t, metrics.minimum_pace > 0)
    testing.expect(t, metrics.maximum_pace <= derived.dive_pace * 1.05)
}

@(test)
ace_loop_scenario_passes_apex_and_accumulates_more_than_one_rotation :: proc(t: ^testing.T) {
    tuning := flight.default_ace_tuning()
    tuning.pull_strength = 1
    tuning.turn_hold = 1
    tuning.climb_generosity = 1
    tuning.low_speed_authority = 1
    tuning.air_grip = 1
    tuning.drift = 0
    derived := flight.derive_ace_tuning(tuning)
    body := ace_cruise_body(pace = derived.cruise_pace)
    body.position.y = 100
    runtime := flight.Ace_Runtime {
        energy = 1,
    }
    commands: [480]flight.Control_Command
    for &command in commands {
        command = {
            pitch    = 1,
            throttle = 1,
        }
    }

    metrics := ace_run_scenario(&body, &runtime, tuning, {engine_output = 1, control_authority = 1}, commands[:])

    testing.expect(t, metrics.signed_local_rotation.x > f32(2 * math.PI))
    testing.expect(t, metrics.maximum_altitude > metrics.initial_altitude + 5)
    testing.expect(t, metrics.final_altitude < metrics.maximum_altitude - 1)
    testing.expect(t, metrics.minimum_pace > 0)
    testing.expect(t, metrics.maximum_pace <= derived.dive_pace * 1.05)
}

@(test)
ace_pace_punch_and_pull_strength_change_runtime_behavior :: proc(t: ^testing.T) {
    low_pace, high_pace := flight.default_ace_tuning(), flight.default_ace_tuning()
    low_pace.pace, high_pace.pace = 0, 1
    low_pace_body := ace_cruise_body(pace = 30)
    high_pace_body := low_pace_body
    low_pace_runtime := flight.Ace_Runtime {
        energy = 1,
    }
    high_pace_runtime := low_pace_runtime
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }
    low_pace_result := ace_step_n(&low_pace_body, {throttle = 1}, low_pace, &low_pace_runtime, modifiers, 240)
    high_pace_result := ace_step_n(&high_pace_body, {throttle = 1}, high_pace, &high_pace_runtime, modifiers, 240)
    testing.expect(t, high_pace_result.pace > low_pace_result.pace)

    low_punch, high_punch := flight.default_ace_tuning(), flight.default_ace_tuning()
    low_punch.punch, high_punch.punch = 0, 1
    low_punch_body := ace_cruise_body(pace = 20)
    high_punch_body := low_punch_body
    low_punch_runtime := flight.Ace_Runtime {
        energy = 1,
    }
    high_punch_runtime := low_punch_runtime
    low_punch_result := ace_step_n(&low_punch_body, {throttle = 1}, low_punch, &low_punch_runtime, modifiers, 30)
    high_punch_result := ace_step_n(&high_punch_body, {throttle = 1}, high_punch, &high_punch_runtime, modifiers, 30)
    testing.expect(t, high_punch_result.pace > low_punch_result.pace)

    low_pull, high_pull := flight.default_ace_tuning(), flight.default_ace_tuning()
    low_pull.pull_strength, high_pull.pull_strength = 0, 1
    low_pull_body := ace_cruise_body()
    high_pull_body := low_pull_body
    low_pull_runtime := flight.Ace_Runtime {
        energy = 1,
    }
    high_pull_runtime := low_pull_runtime
    ace_step_n(&low_pull_body, {pitch = 1, throttle = 1}, low_pull, &low_pull_runtime, modifiers, 60)
    ace_step_n(&high_pull_body, {pitch = 1, throttle = 1}, high_pull, &high_pull_runtime, modifiers, 60)
    testing.expect(t, high_pull_runtime.local_rate.x > low_pull_runtime.local_rate.x)
}

@(test)
ace_climb_generosity_break_drama_and_recovery_punch_change_runtime_behavior :: proc(t: ^testing.T) {
    low_climb, high_climb := flight.default_ace_tuning(), flight.default_ace_tuning()
    low_climb.climb_generosity, high_climb.climb_generosity = 0, 1
    diagonal := f32(.70710677)
    low_climb_body := ace_cruise_body({0, diagonal, -diagonal}, pace = 50)
    high_climb_body := low_climb_body
    low_climb_runtime := flight.Ace_Runtime {
        energy = .8,
    }
    high_climb_runtime := low_climb_runtime
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }
    low_climb_result := ace_step_n(&low_climb_body, {throttle = .5}, low_climb, &low_climb_runtime, modifiers, 120)
    high_climb_result := ace_step_n(&high_climb_body, {throttle = .5}, high_climb, &high_climb_runtime, modifiers, 120)
    testing.expect(t, high_climb_runtime.energy > low_climb_runtime.energy)
    testing.expect(t, high_climb_result.pace > low_climb_result.pace)

    low_break, high_break := flight.default_ace_tuning(), flight.default_ace_tuning()
    low_break.break_drama, high_break.break_drama = 0, 1
    low_break_body := ace_cruise_body(pace = 20)
    high_break_body := low_break_body
    low_break_runtime := flight.Ace_Runtime {
        energy     = .05,
        edge_state = .Break,
    }
    high_break_runtime := low_break_runtime
    break_command := flight.Control_Command {
        roll = 1,
        yaw  = .25,
    }
    ace_step_n(&low_break_body, break_command, low_break, &low_break_runtime, modifiers, 20)
    ace_step_n(&high_break_body, break_command, high_break, &high_break_runtime, modifiers, 20)
    testing.expect(t, high_break_runtime.local_rate.x < low_break_runtime.local_rate.x)
    testing.expect(t, high_break_runtime.local_rate.z > low_break_runtime.local_rate.z)
    testing.expect(t, high_break_body.velocity.y < low_break_body.velocity.y)

    low_recovery, high_recovery := flight.default_ace_tuning(), flight.default_ace_tuning()
    low_recovery.recovery_punch, high_recovery.recovery_punch = 0, 1
    recovery_direction := flight.Vec3{0, -.3, -.9539392}
    low_recovery_body := ace_cruise_body(recovery_direction, pace = 30)
    high_recovery_body := low_recovery_body
    low_recovery_runtime := flight.Ace_Runtime {
        energy     = .3,
        edge_state = .Recovery,
    }
    high_recovery_runtime := low_recovery_runtime
    low_recovery_ticks := ace_steps_until_edge(
        &low_recovery_body,
        &low_recovery_runtime,
        low_recovery,
        {throttle = 1},
        .Free,
        1200,
        modifiers,
    )
    high_recovery_ticks := ace_steps_until_edge(
        &high_recovery_body,
        &high_recovery_runtime,
        high_recovery,
        {throttle = 1},
        .Free,
        1200,
        modifiers,
    )
    testing.expect(t, low_recovery_ticks > 0)
    testing.expect(t, high_recovery_ticks > 0)
    testing.expect(t, high_recovery_ticks < low_recovery_ticks)
}

@(test)
ace_low_speed_authority_line_hold_and_exit_catch_change_runtime_behavior :: proc(t: ^testing.T) {
    low_authority, high_authority := flight.default_ace_tuning(), flight.default_ace_tuning()
    low_authority.low_speed_authority, high_authority.low_speed_authority = 0, 1
    low_authority_body := ace_cruise_body(pace = 18)
    high_authority_body := low_authority_body
    low_authority_runtime := flight.Ace_Runtime{}
    high_authority_runtime := low_authority_runtime
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }
    authority_command := flight.Control_Command {
        pitch = 1,
        roll  = 1,
        yaw   = 1,
    }
    ace_step_n(&low_authority_body, authority_command, low_authority, &low_authority_runtime, modifiers, 12)
    ace_step_n(&high_authority_body, authority_command, high_authority, &high_authority_runtime, modifiers, 12)
    testing.expect(t, math.abs(high_authority_runtime.local_rate.x) > math.abs(low_authority_runtime.local_rate.x))
    testing.expect(t, math.abs(high_authority_runtime.local_rate.y) > math.abs(low_authority_runtime.local_rate.y))
    testing.expect(t, math.abs(high_authority_runtime.local_rate.z) > math.abs(low_authority_runtime.local_rate.z))

    low_line, high_line := flight.default_ace_tuning(), flight.default_ace_tuning()
    low_line.line_hold, high_line.line_hold = 0, 1
    low_line_body := ace_cruise_body()
    high_line_body := low_line_body
    low_line_body.position.y = 100
    high_line_body.position.y = 100
    low_line_runtime := flight.Ace_Runtime {
        energy = 1,
    }
    high_line_runtime := low_line_runtime
    ace_step_n(&low_line_body, {throttle = 1}, low_line, &low_line_runtime, modifiers, 240)
    ace_step_n(&high_line_body, {throttle = 1}, high_line, &high_line_runtime, modifiers, 240)
    testing.expect(t, high_line_body.position.y > low_line_body.position.y)
    testing.expect(t, high_line_body.velocity.y > low_line_body.velocity.y)

    low_catch, high_catch := flight.default_ace_tuning(), flight.default_ace_tuning()
    low_catch.exit_catch, high_catch.exit_catch = 0, 1
    low_catch_body := ace_cruise_body()
    low_catch_body.angular_velocity_world = {0, 0, -2}
    high_catch_body := low_catch_body
    low_catch_runtime := flight.Ace_Runtime {
        energy     = .6,
        edge_state = .Recovery,
    }
    high_catch_runtime := low_catch_runtime
    ace_step_n(&low_catch_body, {}, low_catch, &low_catch_runtime, modifiers, 12)
    ace_step_n(&high_catch_body, {}, high_catch, &high_catch_runtime, modifiers, 12)
    testing.expect(t, math.abs(high_catch_runtime.local_rate.z) < math.abs(low_catch_runtime.local_rate.z))
}

@(test)
ace_air_grip_and_drift_order_attitude_track_closure :: proc(t: ^testing.T) {
    low_grip, high_grip := flight.default_ace_tuning(), flight.default_ace_tuning()
    low_grip.air_grip, high_grip.air_grip = 0, 1
    low_grip_body := ace_cruise_body({1, 0, 0})
    high_grip_body := low_grip_body
    low_grip_body.orientation = flight.identity_orientation()
    high_grip_body.orientation = flight.identity_orientation()
    low_grip_runtime := flight.Ace_Runtime {
        energy = 1,
    }
    high_grip_runtime := low_grip_runtime

    low_grip_telemetry := ace_step_n(
        &low_grip_body,
        {throttle = 1},
        low_grip,
        &low_grip_runtime,
        {engine_output = 1, control_authority = 1},
        60,
    )
    high_grip_telemetry := ace_step_n(
        &high_grip_body,
        {throttle = 1},
        high_grip,
        &high_grip_runtime,
        {engine_output = 1, control_authority = 1},
        60,
    )
    testing.expect(t, high_grip_telemetry.attitude_track_angle < low_grip_telemetry.attitude_track_angle)

    low_drift, high_drift := flight.default_ace_tuning(), flight.default_ace_tuning()
    low_drift.drift, high_drift.drift = 0, 1
    low_drift_body := ace_cruise_body({1, 0, 0})
    high_drift_body := low_drift_body
    low_drift_body.orientation = flight.identity_orientation()
    high_drift_body.orientation = flight.identity_orientation()
    low_drift_runtime := flight.Ace_Runtime {
        energy = 1,
    }
    high_drift_runtime := low_drift_runtime

    low_drift_telemetry := ace_step_n(
        &low_drift_body,
        {throttle = 1},
        low_drift,
        &low_drift_runtime,
        {engine_output = 1, control_authority = 1},
        60,
    )
    high_drift_telemetry := ace_step_n(
        &high_drift_body,
        {throttle = 1},
        high_drift,
        &high_drift_runtime,
        {engine_output = 1, control_authority = 1},
        60,
    )
    testing.expect(t, high_drift_telemetry.attitude_track_angle > low_drift_telemetry.attitude_track_angle)
}

@(test)
ace_bank_yaw_and_pitch_each_bend_track :: proc(t: ^testing.T) {
    tuning := flight.default_ace_tuning()
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }
    neutral_body := ace_cruise_body()
    banked_body := neutral_body
    banked_body.orientation = flight.orientation_from_forward_and_up({0, 0, -1}, {.70710677, .70710677, 0})
    neutral_runtime := flight.Ace_Runtime {
        energy = 1,
    }
    banked_runtime := neutral_runtime
    ace_step_n(&neutral_body, {throttle = 1}, tuning, &neutral_runtime, modifiers, 60)
    ace_step_n(&banked_body, {throttle = 1}, tuning, &banked_runtime, modifiers, 60)
    testing.expect(t, math.abs(banked_body.velocity.x) > math.abs(neutral_body.velocity.x))

    no_yaw_body := ace_cruise_body()
    yaw_body := no_yaw_body
    no_yaw_runtime := flight.Ace_Runtime {
        energy = 1,
    }
    yaw_runtime := no_yaw_runtime
    ace_step_n(&no_yaw_body, {throttle = 1}, tuning, &no_yaw_runtime, modifiers, 60)
    ace_step_n(&yaw_body, {yaw = 1, throttle = 1}, tuning, &yaw_runtime, modifiers, 60)
    testing.expect(t, yaw_body.velocity.x > no_yaw_body.velocity.x)
    testing.expect(t, yaw_body.velocity.x > 0)

    no_pitch_body := ace_cruise_body()
    pitch_body := no_pitch_body
    no_pitch_runtime := flight.Ace_Runtime {
        energy = 1,
    }
    pitch_runtime := no_pitch_runtime
    ace_step_n(&no_pitch_body, {throttle = 1}, tuning, &no_pitch_runtime, modifiers, 60)
    ace_step_n(&pitch_body, {pitch = 1, throttle = 1}, tuning, &pitch_runtime, modifiers, 60)
    testing.expect(t, pitch_body.velocity.y > no_pitch_body.velocity.y)
}

@(test)
ace_track_step_cannot_reverse_and_zero_pace_has_finite_fallback :: proc(t: ^testing.T) {
    tuning := flight.default_ace_tuning()
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }
    opposed := ace_cruise_body({0, 0, 1})
    opposed.orientation = flight.identity_orientation()
    opposed_runtime := flight.Ace_Runtime {
        energy = 1,
    }
    old_track := linalg.normalize(opposed.velocity)
    flight.ace_step(&opposed, {throttle = 1}, tuning, &opposed_runtime, modifiers, 1.0 / 120.0)
    testing.expect(t, linalg.dot(old_track, linalg.normalize(opposed.velocity)) > 0)

    stopped := flight.Body_State {
        orientation = flight.identity_orientation(),
    }
    stopped_runtime := flight.Ace_Runtime {
        energy = .5,
    }
    telemetry := flight.ace_step(&stopped, {throttle = .5}, tuning, &stopped_runtime, modifiers, 1.0 / 120.0)
    testing.expect(t, telemetry.pace > 0)
    testing.expect(t, !math.is_inf_f32(telemetry.pace))
    testing.expect(t, stopped.velocity.x == stopped.velocity.x)
    testing.expect(t, stopped.velocity.y == stopped.velocity.y)
    testing.expect(t, stopped.velocity.z == stopped.velocity.z)
    testing.expect(t, linalg.dot(stopped.velocity, flight.Vec3{0, 0, -1}) > 0)
}

@(test)
ace_edge_states_contribute_distinct_track_behavior_without_transition :: proc(t: ^testing.T) {
    tuning := flight.default_ace_tuning()
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }

    free_hang_body := ace_cruise_body({1, 0, 0}, pace = 20)
    free_hang_body.orientation = flight.identity_orientation()
    hang_body := free_hang_body
    free_hang_runtime := flight.Ace_Runtime {
        energy = .1,
    }
    hang_runtime := flight.Ace_Runtime {
        energy     = .1,
        edge_state = .Hang,
    }
    free_hang_telemetry := ace_step_n(
        &free_hang_body,
        {yaw = 1, throttle = .5},
        tuning,
        &free_hang_runtime,
        modifiers,
        1,
    )
    hang_telemetry := ace_step_n(&hang_body, {yaw = 1, throttle = .5}, tuning, &hang_runtime, modifiers, 1)
    testing.expect(t, hang_telemetry.attitude_track_angle > free_hang_telemetry.attitude_track_angle)
    testing.expect(t, hang_body.velocity.x > 0)
    testing.expect(t, hang_runtime.edge_state == .Hang)

    neutral_hang_body := ace_cruise_body()
    yaw_hang_body := neutral_hang_body
    neutral_hang_runtime := flight.Ace_Runtime {
        energy     = .6,
        edge_state = .Hang,
    }
    yaw_hang_runtime := neutral_hang_runtime
    ace_step_n(&neutral_hang_body, {throttle = .5}, tuning, &neutral_hang_runtime, modifiers, 30)
    ace_step_n(&yaw_hang_body, {yaw = 1, throttle = .5}, tuning, &yaw_hang_runtime, modifiers, 30)
    testing.expect(t, yaw_hang_body.velocity.x > neutral_hang_body.velocity.x)

    free_break_body := ace_cruise_body()
    free_break_body.angular_velocity_world = {0, -.5, -.5}
    break_body := free_break_body
    free_break_runtime := flight.Ace_Runtime {
        energy = .6,
    }
    break_runtime := flight.Ace_Runtime {
        energy     = .6,
        edge_state = .Break,
    }
    ace_step_n(&free_break_body, {}, tuning, &free_break_runtime, modifiers, 20)
    ace_step_n(&break_body, {}, tuning, &break_runtime, modifiers, 20)
    testing.expect(t, break_body.velocity.x > free_break_body.velocity.x)
    testing.expect(t, break_body.velocity.y < free_break_body.velocity.y)
    testing.expect(t, break_runtime.edge_state == .Break)

    free_recovery_body := ace_cruise_body({1, 0, 0})
    free_recovery_body.orientation = flight.identity_orientation()
    recovery_body := free_recovery_body
    free_recovery_runtime := flight.Ace_Runtime {
        energy = .6,
    }
    recovery_runtime := flight.Ace_Runtime {
        energy     = .6,
        edge_state = .Recovery,
    }
    free_recovery_telemetry := ace_step_n(
        &free_recovery_body,
        {throttle = .5},
        tuning,
        &free_recovery_runtime,
        modifiers,
        30,
    )
    recovery_telemetry := ace_step_n(&recovery_body, {throttle = .5}, tuning, &recovery_runtime, modifiers, 30)
    testing.expect(t, recovery_telemetry.attitude_track_angle < free_recovery_telemetry.attitude_track_angle)
    testing.expect(t, recovery_runtime.edge_state == .Recovery)
}

@(test)
ace_edge_committed_path_and_transition_ticks_are_deterministic :: proc(t: ^testing.T) {
    tuning := flight.default_ace_tuning()
    body_a := ace_cruise_body(pace = 16)
    runtime_a := flight.Ace_Runtime {
        energy = .04,
    }
    body_b, runtime_b := body_a, runtime_a
    transitions_a, transitions_b: [5]flight.Ace_Edge_State
    ticks_a, ticks_b: [5]int
    count_a, count_b: int
    previous_a, previous_b := flight.Ace_Edge_State.Free, flight.Ace_Edge_State.Free
    break_altitude := body_a.position.y
    minimum_edge_altitude := body_a.position.y
    tracking_edge_altitude := false

    for tick in 0 ..< 2400 {
        command_a := flight.Control_Command {
            pitch = 1,
            roll  = .8,
            yaw   = .5,
        }
        modifiers_a := flight.Model_Modifiers {
            engine_output = 1,
        }
        if runtime_a.edge_state == .Break {
            command_a = {
                pitch    = -1,
                throttle = 1,
            }
            modifiers_a.control_authority = 1
        } else if runtime_a.edge_state == .Recovery {
            command_a = {
                throttle = 1,
            }
            modifiers_a.control_authority = 1
        }
        command_b, modifiers_b := command_a, modifiers_a

        flight.ace_step(&body_a, command_a, tuning, &runtime_a, modifiers_a, 1.0 / 120.0)
        flight.ace_step(&body_b, command_b, tuning, &runtime_b, modifiers_b, 1.0 / 120.0)

        if runtime_a.edge_state == .Break && previous_a != .Break {
            break_altitude = body_a.position.y
            minimum_edge_altitude = break_altitude
            tracking_edge_altitude = true
        }
        if tracking_edge_altitude {
            minimum_edge_altitude = min(minimum_edge_altitude, body_a.position.y)
        }

        if runtime_a.edge_state != previous_a {
            if count_a < len(transitions_a) {
                transitions_a[count_a] = runtime_a.edge_state
                ticks_a[count_a] = tick + 1
            }
            count_a += 1
            previous_a = runtime_a.edge_state
        }
        if runtime_b.edge_state != previous_b {
            if count_b < len(transitions_b) {
                transitions_b[count_b] = runtime_b.edge_state
                ticks_b[count_b] = tick + 1
            }
            count_b += 1
            previous_b = runtime_b.edge_state
        }
        if count_a >= len(transitions_a) && runtime_a.edge_state == .Free do break
    }

    expected := [5]flight.Ace_Edge_State{.Warning, .Hang, .Break, .Recovery, .Free}
    testing.expect(t, count_a == len(expected))
    testing.expect(t, count_b == count_a)
    testing.expect(t, transitions_a == expected)
    testing.expect(t, transitions_b == transitions_a)
    testing.expect(t, ticks_b == ticks_a)
    testing.expect(t, body_b == body_a)
    testing.expect(t, runtime_b == runtime_a)
    recovery_ticks := ticks_a[4] - ticks_a[3]
    altitude_loss := break_altitude - minimum_edge_altitude
    derived := flight.derive_ace_tuning(tuning)
    testing.expect(t, f32(recovery_ticks) * ACE_SCENARIO_DT >= derived.recovery_min_seconds)
    testing.expect(t, recovery_ticks < 1200)
    testing.expect(t, altitude_loss > 0)
    testing.expect(t, altitude_loss < 500)
}

@(test)
ace_edge_warning_release_cancels_without_hang_or_break :: proc(t: ^testing.T) {
    body := ace_cruise_body(pace = 16)
    runtime := flight.Ace_Runtime {
        energy = .04,
    }
    tuning := flight.default_ace_tuning()

    flight.ace_step(&body, {pitch = 1, roll = .8}, tuning, &runtime, {engine_output = 1}, 1.0 / 120.0)
    testing.expect(t, runtime.edge_state == .Warning)
    ace_step_n(&body, {}, tuning, &runtime, {engine_output = 1}, 30)
    testing.expect(t, runtime.edge_state == .Free)
}

@(test)
ace_invalid_edge_timers_restart_without_blocking_break_or_recovery :: proc(t: ^testing.T) {
    invalid_seconds := [?]f32{f32(0h7fc0_0000), f32(0h7f80_0000), f32(0hff80_0000), -1}
    tuning := flight.default_ace_tuning()
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }

    for invalid in invalid_seconds {
        break_body := ace_cruise_body(pace = 18)
        break_runtime := flight.Ace_Runtime {
            energy       = 0,
            edge_state   = .Break,
            edge_seconds = invalid,
        }
        flight.ace_step(&break_body, {pitch = -1, throttle = 1}, tuning, &break_runtime, modifiers, 1.0 / 120.0)
        testing.expect(
            t,
            break_runtime.edge_seconds == break_runtime.edge_seconds &&
            !math.is_inf_f32(break_runtime.edge_seconds) &&
            break_runtime.edge_seconds >= 0,
        )
        testing.expect(t, break_runtime.edge_state == .Break)
        break_ticks := ace_steps_until_edge(
            &break_body,
            &break_runtime,
            tuning,
            {pitch = -1, throttle = 1},
            .Recovery,
            240,
            modifiers,
        )
        testing.expect(t, break_ticks > 0)

        recovery_body := ace_cruise_body()
        recovery_runtime := flight.Ace_Runtime {
            energy       = 1,
            edge_state   = .Recovery,
            edge_seconds = invalid,
        }
        flight.ace_step(&recovery_body, {throttle = 1}, tuning, &recovery_runtime, modifiers, 1.0 / 120.0)
        testing.expect(
            t,
            recovery_runtime.edge_seconds == recovery_runtime.edge_seconds &&
            !math.is_inf_f32(recovery_runtime.edge_seconds) &&
            recovery_runtime.edge_seconds >= 0,
        )
        testing.expect(t, recovery_runtime.edge_state == .Recovery)
        recovery_ticks := ace_steps_until_edge(
            &recovery_body,
            &recovery_runtime,
            tuning,
            {throttle = 1},
            .Free,
            360,
            modifiers,
        )
        testing.expect(t, recovery_ticks > 0)
    }
}

@(test)
ace_hang_time_delays_break_without_skipping_states :: proc(t: ^testing.T) {
    short, long := flight.default_ace_tuning(), flight.default_ace_tuning()
    short.hang_time, long.hang_time = 0, 1
    short_body := ace_cruise_body(pace = 16)
    long_body := short_body
    short_runtime := flight.Ace_Runtime {
        energy     = 0,
        edge_state = .Hang,
    }
    long_runtime := short_runtime
    command := flight.Control_Command {
        pitch = 1,
        roll  = .8,
        yaw   = .5,
    }
    modifiers := flight.Model_Modifiers {
        engine_output = 1,
    }

    short_ticks := ace_steps_until_edge(&short_body, &short_runtime, short, command, .Break, 1200, modifiers)
    long_ticks := ace_steps_until_edge(&long_body, &long_runtime, long, command, .Break, 1200, modifiers)
    testing.expect(t, short_ticks > 0)
    testing.expect(t, long_ticks > short_ticks)
}

@(test)
ace_hang_release_enters_recovery_and_invalid_state_fails_to_break :: proc(t: ^testing.T) {
    tuning := flight.default_ace_tuning()
    body := ace_cruise_body(pace = 16)
    runtime := flight.Ace_Runtime {
        energy     = 0,
        edge_state = .Hang,
    }
    flight.ace_step(&body, {}, tuning, &runtime, {engine_output = 1, control_authority = 1}, 1.0 / 120.0)
    testing.expect(t, runtime.edge_state == .Recovery)

    invalid_body := ace_cruise_body(pace = 16)
    invalid_runtime := flight.Ace_Runtime {
        energy     = 0,
        edge_state = cast(flight.Ace_Edge_State)99,
    }
    flight.ace_step(
        &invalid_body,
        {},
        tuning,
        &invalid_runtime,
        {engine_output = 1, control_authority = 1},
        1.0 / 120.0,
    )
    testing.expect(t, invalid_runtime.edge_state == .Break)
}

@(test)
ace_break_requires_real_recovery_and_mirrors_roll_off :: proc(t: ^testing.T) {
    tuning := flight.default_ace_tuning()
    derived := flight.derive_ace_tuning(tuning)
    nose_up := flight.Vec3{0, .5, -.8660254}
    waiting_body := ace_cruise_body(nose_up, pace = 18)
    waiting_runtime := flight.Ace_Runtime {
        energy       = 0,
        edge_state   = .Break,
        edge_seconds = derived.break_min_seconds,
    }
    ace_step_n(&waiting_body, {}, tuning, &waiting_runtime, {engine_output = 1, control_authority = 1}, 120)
    testing.expect(t, waiting_runtime.edge_state == .Break)

    recovery_ticks := ace_steps_until_edge(
        &waiting_body,
        &waiting_runtime,
        tuning,
        {pitch = -1, throttle = 1},
        .Recovery,
        240,
    )
    testing.expect(t, recovery_ticks > 0)

    positive_body := ace_cruise_body(pace = 20)
    negative_body := positive_body
    positive_runtime := flight.Ace_Runtime {
        energy     = .05,
        edge_state = .Break,
    }
    negative_runtime := positive_runtime
    ace_step_n(
        &positive_body,
        {roll = 1, yaw = .25},
        tuning,
        &positive_runtime,
        {engine_output = 1, control_authority = 1},
        20,
    )
    ace_step_n(
        &negative_body,
        {roll = -1, yaw = -.25},
        tuning,
        &negative_runtime,
        {engine_output = 1, control_authority = 1},
        20,
    )
    testing.expect(t, positive_runtime.local_rate.z > 0)
    testing.expect(t, negative_runtime.local_rate.z < 0)
    testing.expect(t, positive_body.velocity.x * negative_body.velocity.x < 0)
}

@(test)
ace_dive_level_climb_and_turn_demand_order_energy :: proc(t: ^testing.T) {
    tuning := flight.default_ace_tuning()
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }
    diagonal := f32(.70710677)
    dive_body := ace_cruise_body({0, -diagonal, -diagonal})
    level_body := ace_cruise_body()
    climb_body := ace_cruise_body({0, diagonal, -diagonal})
    dive_runtime := flight.Ace_Runtime {
        energy = .5,
    }
    level_runtime := dive_runtime
    climb_runtime := dive_runtime

    flight.ace_step(&dive_body, {throttle = .5}, tuning, &dive_runtime, modifiers, 1.0 / 120.0)
    flight.ace_step(&level_body, {throttle = .5}, tuning, &level_runtime, modifiers, 1.0 / 120.0)
    flight.ace_step(&climb_body, {throttle = .5}, tuning, &climb_runtime, modifiers, 1.0 / 120.0)
    testing.expect(t, dive_runtime.energy > level_runtime.energy)
    testing.expect(t, level_runtime.energy > climb_runtime.energy)

    gentle_body := ace_cruise_body()
    hard_body := gentle_body
    gentle_runtime := flight.Ace_Runtime {
        energy = .8,
    }
    hard_runtime := gentle_runtime
    flight.ace_step(
        &gentle_body,
        {pitch = .2, roll = .2, yaw = .2, throttle = .5},
        tuning,
        &gentle_runtime,
        modifiers,
        1.0 / 120.0,
    )
    flight.ace_step(
        &hard_body,
        {pitch = 1, roll = 1, yaw = 1, throttle = .5},
        tuning,
        &hard_runtime,
        modifiers,
        1.0 / 120.0,
    )
    testing.expect(t, hard_runtime.energy < gentle_runtime.energy)
}

@(test)
ace_inverted_hold_spends_more_energy_than_upright :: proc(t: ^testing.T) {
    tuning := flight.default_ace_tuning()
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }
    upright := ace_cruise_body()
    inverted := ace_cruise_body(up = {0, -1, 0})
    upright_runtime := flight.Ace_Runtime {
        energy = .8,
    }
    inverted_runtime := upright_runtime

    flight.ace_step(&upright, {throttle = .5}, tuning, &upright_runtime, modifiers, 1.0 / 120.0)
    flight.ace_step(&inverted, {throttle = .5}, tuning, &inverted_runtime, modifiers, 1.0 / 120.0)
    testing.expect(t, inverted_runtime.energy < upright_runtime.energy)
}

@(test)
ace_neutral_inverted_flight_builds_edge_pressure_without_auto_upright :: proc(t: ^testing.T) {
    body := ace_cruise_body(pace = 16, up = {0, -1, 0})
    orientation_before := body.orientation
    runtime := flight.Ace_Runtime {
        energy = 0,
    }
    tuning := flight.default_ace_tuning()
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }

    hang_tick := ace_steps_until_edge(&body, &runtime, tuning, {}, .Hang, 240, modifiers)

    testing.expect(t, hang_tick > 0)
    testing.expect(t, runtime.edge_state == .Hang)
    testing.expect(t, body.orientation == orientation_before)
    testing.expect(t, body.angular_velocity_world == flight.Vec3{})
}

@(test)
ace_inverted_commands_keep_local_pitch_roll_and_yaw_control :: proc(t: ^testing.T) {
    neutral_body := ace_cruise_body(up = {0, -1, 0})
    pitch_body, roll_body, yaw_body := neutral_body, neutral_body, neutral_body
    orientation_before := neutral_body.orientation
    neutral_runtime := flight.Ace_Runtime {
        energy = 1,
    }
    pitch_runtime, roll_runtime, yaw_runtime := neutral_runtime, neutral_runtime, neutral_runtime
    derived := flight.derive_ace_tuning(flight.default_ace_tuning())
    modifiers := flight.Model_Modifiers {
        control_authority = 1,
    }

    flight.ace_step_angular(&neutral_body, {}, derived, &neutral_runtime, modifiers, 1.0 / 120.0)
    flight.ace_step_angular(&pitch_body, {pitch = 1}, derived, &pitch_runtime, modifiers, 1.0 / 120.0)
    flight.ace_step_angular(&roll_body, {roll = 1}, derived, &roll_runtime, modifiers, 1.0 / 120.0)
    flight.ace_step_angular(&yaw_body, {yaw = 1}, derived, &yaw_runtime, modifiers, 1.0 / 120.0)

    testing.expect(t, neutral_runtime.local_rate == flight.Vec3{})
    testing.expect(t, neutral_body.orientation == orientation_before)
    testing.expect(t, pitch_runtime.local_rate.x > 0)
    testing.expect(t, roll_runtime.local_rate.z > 0)
    testing.expect(t, yaw_runtime.local_rate.y < 0)
    testing.expect(t, pitch_body.orientation != orientation_before)
    testing.expect(t, roll_body.orientation != orientation_before)
    testing.expect(t, yaw_body.orientation != orientation_before)
}

ace_knife_body :: proc(energy: f32) -> (flight.Body_State, flight.Ace_Runtime) {
    body := ace_cruise_body(pace = 60, up = {1, 0, 0})
    body.velocity = linalg.normalize(flight.Vec3{0, -.12, -1}) * 60
    return body, {energy = energy}
}

ace_knife_skyward_yaw :: proc(body: flight.Body_State) -> f32 {
    basis := flight.basis_from_orientation(body.orientation)
    if linalg.dot(basis.right, flight.Vec3{0, 1, 0}) < 0 do return -1
    return 1
}

@(test)
ace_knife_support_is_mirrored_and_requires_skyward_rudder :: proc(t: ^testing.T) {
    right_body := ace_cruise_body(pace = 60, up = {1, 0, 0})
    left_body := ace_cruise_body(pace = 60, up = {-1, 0, 0})
    right_orientation, left_orientation := right_body.orientation, left_body.orientation
    tuning := flight.default_ace_tuning()
    derived := flight.derive_ace_tuning(tuning)
    modifiers := flight.Model_Modifiers {
        control_authority = 1,
    }
    right_basis := flight.basis_from_orientation(right_body.orientation)
    left_basis := flight.basis_from_orientation(left_body.orientation)
    right_yaw := ace_knife_skyward_yaw(right_body)
    left_yaw := ace_knife_skyward_yaw(left_body)

    right_support := flight.ace_knife_edge_support(
        right_basis,
        derived.cruise_pace,
        1,
        right_yaw,
        tuning,
        derived,
        modifiers,
    )
    left_support := flight.ace_knife_edge_support(
        left_basis,
        derived.cruise_pace,
        1,
        left_yaw,
        tuning,
        derived,
        modifiers,
    )
    neutral_support := flight.ace_knife_edge_support(
        right_basis,
        derived.cruise_pace,
        1,
        0,
        tuning,
        derived,
        modifiers,
    )
    opposite_support := flight.ace_knife_edge_support(
        right_basis,
        derived.cruise_pace,
        1,
        -right_yaw,
        tuning,
        derived,
        modifiers,
    )

    testing.expect(t, right_support.y > 0)
    testing.expect(t, left_support == right_support)
    testing.expect(t, right_support.x == 0 && right_support.z == 0)
    testing.expect(t, neutral_support == flight.Vec3{})
    testing.expect(t, opposite_support == flight.Vec3{})
    testing.expect(t, right_body.orientation == right_orientation)
    testing.expect(t, left_body.orientation == left_orientation)
}

@(test)
ace_knife_support_orders_pace_energy_authority_damage_and_rudder_bite :: proc(t: ^testing.T) {
    body := ace_cruise_body(pace = 60, up = {1, 0, 0})
    orientation_before := body.orientation
    basis := flight.basis_from_orientation(body.orientation)
    yaw := ace_knife_skyward_yaw(body)
    low_tuning, high_tuning := flight.default_ace_tuning(), flight.default_ace_tuning()
    low_tuning.rudder_bite, high_tuning.rudder_bite = 0, 1
    derived := flight.derive_ace_tuning(high_tuning)
    low_pace := derived.minimum_pace + (derived.cruise_pace - derived.minimum_pace) * .25
    healthy := flight.Model_Modifiers {
        control_authority = 1,
    }
    damaged := flight.Model_Modifiers {
        control_authority = 1,
        controls_damaged  = true,
    }
    no_authority := flight.Model_Modifiers{}

    cruise := flight.ace_knife_edge_support(basis, derived.cruise_pace, 1, yaw, high_tuning, derived, healthy)
    low_pace_support := flight.ace_knife_edge_support(basis, low_pace, 1, yaw, high_tuning, derived, healthy)
    minimum_pace := flight.ace_knife_edge_support(basis, derived.minimum_pace, 1, yaw, high_tuning, derived, healthy)
    no_energy := flight.ace_knife_edge_support(basis, derived.cruise_pace, 0, yaw, high_tuning, derived, healthy)
    no_control := flight.ace_knife_edge_support(basis, derived.cruise_pace, 1, yaw, high_tuning, derived, no_authority)
    damaged_support := flight.ace_knife_edge_support(basis, derived.cruise_pace, 1, yaw, high_tuning, derived, damaged)
    low_rudder := flight.ace_knife_edge_support(basis, derived.cruise_pace, 1, yaw, low_tuning, derived, healthy)

    testing.expect(t, cruise.y > low_pace_support.y)
    testing.expect(t, low_pace_support.y > minimum_pace.y)
    testing.expect(t, minimum_pace == flight.Vec3{})
    testing.expect(t, no_energy == flight.Vec3{})
    testing.expect(t, no_control == flight.Vec3{})
    testing.expect(t, damaged_support.y > 0 && damaged_support.y < cruise.y)
    testing.expect(t, cruise.y > low_rudder.y)
    testing.expect(t, body.orientation == orientation_before)
}

@(test)
ace_first_knife_support_step_is_mirrored :: proc(t: ^testing.T) {
    right_body, right_runtime := ace_knife_body(1)
    left_body, left_runtime := ace_knife_body(1)
    left_body.orientation = flight.orientation_from_forward_and_up({0, 0, -1}, {-1, 0, 0})
    neutral_body, neutral_runtime := ace_knife_body(1)
    right_yaw := ace_knife_skyward_yaw(right_body)
    left_yaw := ace_knife_skyward_yaw(left_body)
    tuning := flight.default_ace_tuning()
    tuning.rudder_bite = 1
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }

    flight.ace_step(&right_body, {yaw = right_yaw, throttle = 1}, tuning, &right_runtime, modifiers, 1.0 / 120.0)
    flight.ace_step(&left_body, {yaw = left_yaw, throttle = 1}, tuning, &left_runtime, modifiers, 1.0 / 120.0)
    flight.ace_step(&neutral_body, {throttle = 1}, tuning, &neutral_runtime, modifiers, 1.0 / 120.0)

    testing.expect(t, right_body.velocity.y == left_body.velocity.y)
    testing.expect(t, right_body.velocity.y > neutral_body.velocity.y)
}

@(test)
ace_signed_knife_rudder_loses_less_altitude_than_neutral_or_opposite :: proc(t: ^testing.T) {
    best_body, best_runtime := ace_knife_body(1)
    neutral_body, neutral_runtime := ace_knife_body(1)
    opposite_body, opposite_runtime := ace_knife_body(1)
    skyward_yaw := ace_knife_skyward_yaw(best_body)
    tuning := flight.default_ace_tuning()
    tuning.rudder_bite = 1
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }

    ace_step_n(&best_body, {yaw = skyward_yaw, throttle = 1}, tuning, &best_runtime, modifiers, 60)
    ace_step_n(&neutral_body, {throttle = 1}, tuning, &neutral_runtime, modifiers, 60)
    ace_step_n(&opposite_body, {yaw = -skyward_yaw, throttle = 1}, tuning, &opposite_runtime, modifiers, 60)

    testing.expect(t, best_body.position.y > neutral_body.position.y)
    testing.expect(t, best_body.position.y > opposite_body.position.y)
}

@(test)
ace_knife_support_scales_with_energy_and_vanishes_without_commitment :: proc(t: ^testing.T) {
    high_body, high_runtime := ace_knife_body(1)
    low_body, low_runtime := ace_knife_body(0)
    neutral_body, neutral_runtime := ace_knife_body(1)
    orientation_before := neutral_body.orientation
    skyward_yaw := ace_knife_skyward_yaw(high_body)
    tuning := flight.default_ace_tuning()
    tuning.rudder_bite = 1
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }

    flight.ace_step(&high_body, {yaw = skyward_yaw, throttle = 1}, tuning, &high_runtime, modifiers, 1.0 / 120.0)
    flight.ace_step(&low_body, {yaw = skyward_yaw, throttle = 1}, tuning, &low_runtime, modifiers, 1.0 / 120.0)
    flight.ace_step(&neutral_body, {throttle = 1}, tuning, &neutral_runtime, modifiers, 1.0 / 120.0)

    testing.expect(t, high_body.velocity.y > low_body.velocity.y)
    testing.expect(t, neutral_body.orientation == orientation_before)
    testing.expect(t, neutral_body.angular_velocity_world == flight.Vec3{})
}

@(test)
ace_turn_hold_preserves_more_pace_under_demand :: proc(t: ^testing.T) {
    low, high := flight.default_ace_tuning(), flight.default_ace_tuning()
    low.turn_hold, high.turn_hold = 0, 1
    low_body := ace_cruise_body(pace = 65)
    high_body := low_body
    low_runtime := flight.Ace_Runtime {
        energy = 1,
    }
    high_runtime := low_runtime
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }
    command := flight.Control_Command {
        pitch    = .65,
        roll     = .45,
        yaw      = .35,
        throttle = .75,
    }

    low_telemetry := ace_step_n(&low_body, command, low, &low_runtime, modifiers, 120)
    high_telemetry := ace_step_n(&high_body, command, high, &high_runtime, modifiers, 120)
    testing.expect(t, high_telemetry.pace > low_telemetry.pace)
}

@(test)
ace_dive_payoff_raises_energy_then_pace_without_changing_envelope :: proc(t: ^testing.T) {
    low, high := flight.default_ace_tuning(), flight.default_ace_tuning()
    low.dive_payoff, high.dive_payoff = 0, 1
    diagonal := f32(.70710677)
    low_body := ace_cruise_body({0, -diagonal, -diagonal}, pace = 45)
    high_body := low_body
    low_runtime := flight.Ace_Runtime {
        energy = .2,
    }
    high_runtime := low_runtime
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }
    command := flight.Control_Command {
        throttle = .2,
    }

    low_telemetry := ace_step_n(&low_body, command, low, &low_runtime, modifiers, 180)
    high_telemetry := ace_step_n(&high_body, command, high, &high_runtime, modifiers, 180)
    testing.expect(t, high_runtime.energy > low_runtime.energy)
    testing.expect(t, high_telemetry.pace > low_telemetry.pace)
    testing.expect(t, flight.derive_ace_tuning(low).dive_pace == flight.derive_ace_tuning(high).dive_pace)
}

@(test)
ace_coast_and_brake_order_passive_pace_loss :: proc(t: ^testing.T) {
    low_coast, high_coast := flight.default_ace_tuning(), flight.default_ace_tuning()
    low_coast.coast, high_coast.coast = 0, 1
    low_coast.brake, high_coast.brake = 0, 0
    low_coast_body := ace_cruise_body(pace = 80)
    high_coast_body := low_coast_body
    low_coast_runtime := flight.Ace_Runtime {
        energy = 1,
    }
    high_coast_runtime := low_coast_runtime
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }

    low_coast_telemetry := ace_step_n(&low_coast_body, {}, low_coast, &low_coast_runtime, modifiers, 120)
    high_coast_telemetry := ace_step_n(&high_coast_body, {}, high_coast, &high_coast_runtime, modifiers, 120)
    testing.expect(t, high_coast_telemetry.pace > low_coast_telemetry.pace)

    low_brake, high_brake := flight.default_ace_tuning(), flight.default_ace_tuning()
    low_brake.brake, high_brake.brake = 0, 1
    low_brake_body := ace_cruise_body(pace = 80)
    high_brake_body := low_brake_body
    low_brake_runtime := flight.Ace_Runtime {
        energy = 1,
    }
    high_brake_runtime := low_brake_runtime
    low_brake_telemetry := ace_step_n(&low_brake_body, {}, low_brake, &low_brake_runtime, modifiers, 60)
    high_brake_telemetry := ace_step_n(&high_brake_body, {}, high_brake, &high_brake_runtime, modifiers, 60)
    testing.expect(t, high_brake_telemetry.pace < low_brake_telemetry.pace)
}

@(test)
ace_pace_and_energy_change_smoothly_between_adjacent_steps :: proc(t: ^testing.T) {
    tuning := flight.default_ace_tuning()
    derived := flight.derive_ace_tuning(tuning)
    body := ace_cruise_body(pace = derived.minimum_pace)
    runtime := flight.Ace_Runtime {
        energy = .5,
    }
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }
    previous_pace := linalg.length(body.velocity)
    previous_energy := runtime.energy
    maximum_pace_delta, maximum_energy_delta: f32

    for index in 0 ..< 240 {
        command := flight.Control_Command {
            pitch    = .75,
            roll     = .6,
            yaw      = .4,
            throttle = 1,
        }
        if index >= 120 {
            command = {
                pitch = -.4,
                roll  = -.7,
                yaw   = -.3,
            }
        }
        telemetry := flight.ace_step(&body, command, tuning, &runtime, modifiers, 1.0 / 120.0)
        maximum_pace_delta = max(maximum_pace_delta, math.abs(telemetry.pace - previous_pace))
        maximum_energy_delta = max(maximum_energy_delta, math.abs(telemetry.energy - previous_energy))
        previous_pace = telemetry.pace
        previous_energy = telemetry.energy
    }

    testing.expect(t, maximum_pace_delta < derived.dive_pace * .1)
    testing.expect(t, maximum_energy_delta < .05)
}

@(test)
ace_step_invalid_body_or_step_does_not_mutate_state :: proc(t: ^testing.T) {
    tuning := flight.default_ace_tuning()
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }
    body := ace_cruise_body()
    body.position = {1, 2, 3}
    body.angular_velocity_world = {4, 5, 6}
    runtime := flight.Ace_Runtime {
        energy     = 2,
        local_rate = {7, 8, 9},
    }
    body_before, runtime_before := body, runtime

    flight.ace_step(nil, {}, tuning, &runtime, modifiers, 1.0 / 120.0)
    testing.expect(t, runtime == runtime_before)
    flight.ace_step(&body, {}, tuning, nil, modifiers, 1.0 / 120.0)
    testing.expect(t, body == body_before)

    invalid_steps := [?]f32{0, -1, .051, f32(0h7fc0_0000), f32(0h7f80_0000)}
    for delta_seconds in invalid_steps {
        flight.ace_step(&body, {}, tuning, &runtime, modifiers, delta_seconds)
        testing.expect(t, body == body_before)
        testing.expect(t, runtime == runtime_before)
    }

    body.velocity.x = f32(0h7f80_0000)
    flight.ace_step(&body, {}, tuning, &runtime, modifiers, 1.0 / 120.0)
    testing.expect(t, body.position == body_before.position)
    testing.expect(t, math.is_inf_f32(body.velocity.x))
    testing.expect(t, body.velocity.y == body_before.velocity.y)
    testing.expect(t, body.velocity.z == body_before.velocity.z)
    testing.expect(t, body.orientation == body_before.orientation)
    testing.expect(t, body.angular_velocity_world == body_before.angular_velocity_world)
    testing.expect(t, runtime == runtime_before)
}

@(test)
ace_step_repairs_zero_orientation_and_rejects_nonfinite_orientation :: proc(t: ^testing.T) {
    tuning := flight.default_ace_tuning()
    modifiers := flight.Model_Modifiers {
        engine_output     = 1,
        control_authority = 1,
    }
    zero_body := ace_cruise_body()
    zero_body.orientation = {}
    zero_runtime := flight.Ace_Runtime {
        energy = .5,
    }
    flight.ace_step(&zero_body, {}, tuning, &zero_runtime, modifiers, 1.0 / 120.0)
    testing.expect(t, zero_body.orientation == flight.identity_orientation())

    nan_body := ace_cruise_body()
    nan_body.position = {1, 2, 3}
    nan_body.angular_velocity_world = {4, 5, 6}
    nan_body.orientation.z = f32(0h7fc0_0000)
    nan_runtime := flight.Ace_Runtime {
        energy     = 2,
        local_rate = {7, 8, 9},
    }
    nan_position_before := nan_body.position
    nan_velocity_before := nan_body.velocity
    nan_rate_before := nan_body.angular_velocity_world
    nan_runtime_before := nan_runtime
    flight.ace_step(&nan_body, {}, tuning, &nan_runtime, modifiers, 1.0 / 120.0)
    testing.expect(t, nan_body.position == nan_position_before)
    testing.expect(t, nan_body.velocity == nan_velocity_before)
    testing.expect(t, nan_body.angular_velocity_world == nan_rate_before)
    testing.expect(t, nan_body.orientation.x == 0)
    testing.expect(t, nan_body.orientation.y == 0)
    testing.expect(t, nan_body.orientation.z != nan_body.orientation.z)
    testing.expect(t, nan_body.orientation.w == 1)
    testing.expect(t, nan_runtime == nan_runtime_before)

    infinite_body := ace_cruise_body()
    infinite_body.position = {1, 2, 3}
    infinite_body.angular_velocity_world = {4, 5, 6}
    infinite_body.orientation.y = f32(0hff80_0000)
    infinite_runtime := flight.Ace_Runtime {
        energy     = 2,
        local_rate = {7, 8, 9},
    }
    infinite_position_before := infinite_body.position
    infinite_velocity_before := infinite_body.velocity
    infinite_rate_before := infinite_body.angular_velocity_world
    infinite_runtime_before := infinite_runtime
    flight.ace_step(&infinite_body, {}, tuning, &infinite_runtime, modifiers, 1.0 / 120.0)
    testing.expect(t, infinite_body.position == infinite_position_before)
    testing.expect(t, infinite_body.velocity == infinite_velocity_before)
    testing.expect(t, infinite_body.angular_velocity_world == infinite_rate_before)
    testing.expect(t, infinite_body.orientation.x == 0)
    testing.expect(t, math.is_inf_f32(infinite_body.orientation.y))
    testing.expect(t, infinite_body.orientation.z == 0)
    testing.expect(t, infinite_body.orientation.w == 1)
    testing.expect(t, infinite_runtime == infinite_runtime_before)
}

@(test)
ace_step_replay_is_exact_from_copied_state_and_commands :: proc(t: ^testing.T) {
    tuning := flight.default_ace_tuning()
    body_a := flight.Body_State {
        position               = {4, 80, -12},
        velocity               = {7, -3, -55},
        angular_velocity_world = {.2, -.1, .3},
        orientation            = flight.orientation_from_forward_and_up({.1, .2, -.97}, {0, 1, 0}),
    }
    runtime_a := flight.Ace_Runtime {
        energy       = .63,
        edge_state   = .Warning,
        edge_seconds = .12,
        local_rate   = {.2, -.1, -.3},
    }
    body_b, runtime_b := body_a, runtime_a
    modifiers := flight.Model_Modifiers {
        engine_output     = .82,
        control_authority = .76,
        controls_damaged  = true,
    }
    commands := [?]flight.Control_Command {
        {pitch = .1, roll = .8, yaw = -.2, throttle = .9},
        {pitch = .6, roll = .5, yaw = .4, throttle = .7},
        {pitch = -.3, roll = -.7, yaw = .9, throttle = .3},
        {},
    }
    telemetry_a, telemetry_b: flight.Ace_Telemetry

    for _ in 0 ..< 30 {
        for command in commands {
            telemetry_a = flight.ace_step(&body_a, command, tuning, &runtime_a, modifiers, 1.0 / 120.0)
            telemetry_b = flight.ace_step(&body_b, command, tuning, &runtime_b, modifiers, 1.0 / 120.0)
        }
    }

    testing.expect(t, body_a == body_b)
    testing.expect(t, runtime_a == runtime_b)
    testing.expect(t, telemetry_a == telemetry_b)
}
