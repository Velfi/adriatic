package air_compare

import flight "../flight"
import postale "../postale"
import "core:math"
import "core:mem"

MAX_DELTA_SECONDS :: f32(.05)

// name and commands are borrowed. Scenario builders own their storage.
Scenario :: struct {
    name:          string,
    checkpoint:    postale.Checkpoint,
    delta_seconds: f32,
    commands:      []flight.Control_Command,
    ground_height: f32,
}

Sample :: struct {
    body:             flight.Body_State,
    pace:             f32,
    legacy_telemetry: flight.Telemetry,
    ace_telemetry:    flight.Ace_Telemetry,
    grounded:         bool,
    crashed:          bool,
}

Metrics :: struct {
    final_position:         flight.Vec3,
    final_heading:          f32,
    min_altitude:           f32,
    max_altitude:           f32,
    min_pace:               f32,
    max_pace:               f32,
    local_rotation:         flight.Vec3,
    recovery_seconds:       f32,
    recovery_altitude_loss: f32,
}

Run_Result :: struct {
    // samples belongs to the allocator passed to run_model.
    samples:          []Sample,
    final_checkpoint: postale.Checkpoint,
    metrics:          Metrics,
}

Comparison_Report :: struct {
    valid:                  bool,
    scenario_name:          string,
    model:                  postale.Flight_Model,
    sample_count:           int,
    metrics:                Metrics,
    initial_ace_energy:     f32,
    final_ace_energy:       f32,
    initial_ace_edge_state: flight.Ace_Edge_State,
    final_ace_edge_state:   flight.Ace_Edge_State,
    grounded:               bool,
    crashed:                bool,
}

finite_scalar :: proc(value: f32) -> bool {
    return value == value && !math.is_inf_f32(value)
}

finite_values :: proc(values: []f32) -> bool {
    for value in values {
        if !finite_scalar(value) do return false
    }
    return true
}

finite_vector :: proc(value: flight.Vec3) -> bool {
    return finite_scalar(value.x) && finite_scalar(value.y) && finite_scalar(value.z)
}

finite_orientation :: proc(value: quaternion128) -> bool {
    components := [?]f32{value.x, value.y, value.z, value.w}
    if !finite_values(components[:]) do return false
    return value.x * value.x + value.y * value.y + value.z * value.z + value.w * value.w > 1e-12
}

finite_body :: proc(body: flight.Body_State) -> bool {
    return(
        finite_vector(body.position) &&
        finite_vector(body.velocity) &&
        finite_vector(body.angular_velocity_world) &&
        finite_orientation(body.orientation) \
    )
}

airframe_is_valid :: proc(airframe: flight.Airframe) -> bool {
    values := [?]f32 {
        airframe.mass_kg,
        airframe.maximum_gross_mass_kg,
        airframe.wing_area,
        airframe.lift_scale,
        airframe.drag_scale,
        airframe.parasitic_drag_area,
        airframe.rated_power_per_engine_kw,
        airframe.propeller_efficiency,
        airframe.static_thrust_per_engine,
        airframe.engine_count,
        airframe.wing_incidence_degrees,
        airframe.lift_curve_slope_per_degree,
        airframe.zero_lift_angle_degrees,
        airframe.critical_angle_degrees,
        airframe.negative_critical_angle_degrees,
        airframe.post_stall_angle_degrees,
        airframe.post_stall_lift_coefficient,
        airframe.induced_drag_factor,
        airframe.trim_angle_of_attack_degrees,
        airframe.pitch_stability,
        airframe.pitch_damping,
        airframe.roll_stability,
        airframe.roll_damping,
        airframe.yaw_stability,
        airframe.yaw_damping,
        airframe.pitch_control_scale,
        airframe.roll_control_scale,
        airframe.yaw_control_scale,
        airframe.water_planing_start_speed,
        airframe.water_planing_full_speed,
        airframe.water_planing_reference_speed,
        airframe.water_plow_drag_scale,
    }
    if !finite_values(values[:]) do return false
    if airframe.flight_layout != flight.fixed_wing_layout do return false
    if airframe.mass_kg <= 0 ||
       airframe.maximum_gross_mass_kg < airframe.mass_kg ||
       airframe.wing_area <= 0 ||
       airframe.lift_scale <= 0 ||
       airframe.drag_scale <= 0 ||
       airframe.parasitic_drag_area <= 0 ||
       airframe.rated_power_per_engine_kw < 0 ||
       airframe.propeller_efficiency < 0 ||
       airframe.propeller_efficiency > 1 ||
       airframe.static_thrust_per_engine < 0 ||
       airframe.engine_count <= 0 {
        return false
    }
    if airframe.lift_curve_slope_per_degree <= 0 ||
       airframe.critical_angle_degrees <= 0 ||
       airframe.negative_critical_angle_degrees >= 0 ||
       airframe.post_stall_angle_degrees <= airframe.critical_angle_degrees ||
       airframe.post_stall_lift_coefficient < 0 ||
       airframe.induced_drag_factor < 0 {
        return false
    }
    if airframe.pitch_stability < 0 ||
       airframe.pitch_damping < 0 ||
       airframe.roll_stability < 0 ||
       airframe.roll_damping < 0 ||
       airframe.yaw_stability < 0 ||
       airframe.yaw_damping < 0 ||
       airframe.pitch_control_scale < 0 ||
       airframe.roll_control_scale < 0 ||
       airframe.yaw_control_scale < 0 {
        return false
    }
    if airframe.water_planing_start_speed < 0 ||
       airframe.water_planing_full_speed < airframe.water_planing_start_speed ||
       airframe.water_planing_reference_speed < 0 ||
       airframe.water_plow_drag_scale < 0 {
        return false
    }
    if airframe.water_capable && airframe.water_planing_reference_speed <= 0 do return false
    return true
}

flight_runtime_is_valid :: proc(runtime: flight.Runtime) -> bool {
    values := [?]f32{runtime.engine_output, runtime.control_authority, runtime.drag_multiplier}
    return(
        finite_values(values[:]) &&
        runtime.engine_output >= 0 &&
        runtime.engine_output <= 1 &&
        runtime.control_authority >= 0 &&
        runtime.control_authority <= 1 &&
        runtime.drag_multiplier > 0 \
    )
}

legacy_telemetry_is_valid :: proc(telemetry: flight.Telemetry) -> bool {
    values := [?]f32 {
        telemetry.airspeed,
        telemetry.angle_of_attack_degrees,
        telemetry.effective_stall_speed,
        telemetry.lift_coefficient,
    }
    return finite_values(values[:]) && telemetry.airspeed >= 0 && telemetry.effective_stall_speed >= 0
}

ace_edge_state_is_valid :: proc(state: flight.Ace_Edge_State) -> bool {
    switch state {
    case .Free, .Warning, .Hang, .Break, .Recovery:
        return true
    case:
        return false
    }
}

ace_runtime_is_valid :: proc(runtime: flight.Ace_Runtime) -> bool {
    values := [?]f32{runtime.energy, runtime.edge_seconds}
    return(
        finite_values(values[:]) &&
        runtime.energy >= 0 &&
        runtime.energy <= 1 &&
        runtime.edge_seconds >= 0 &&
        finite_vector(runtime.local_rate) &&
        ace_edge_state_is_valid(runtime.edge_state) \
    )
}

ace_telemetry_is_valid :: proc(telemetry: flight.Ace_Telemetry) -> bool {
    values := [?]f32{telemetry.pace, telemetry.energy, telemetry.track_grip, telemetry.attitude_track_angle}
    return(
        finite_values(values[:]) &&
        telemetry.pace >= 0 &&
        telemetry.energy >= 0 &&
        telemetry.energy <= 1 &&
        telemetry.track_grip >= 0 &&
        telemetry.track_grip <= 1 &&
        telemetry.attitude_track_angle >= 0 &&
        telemetry.attitude_track_angle <= math.PI &&
        ace_edge_state_is_valid(telemetry.edge_state) \
    )
}

landing_outcome_is_valid :: proc(outcome: postale.Landing_Outcome) -> bool {
    switch outcome {
    case .None, .Smooth, .Landed, .Hard_Landing, .Crash:
        return true
    case:
        return false
    }
}

landing_impact_is_valid :: proc(impact: postale.Landing_Impact) -> bool {
    values := [?]f32{impact.sink_speed, impact.weight_force, impact.impact_force, impact.load_factor, impact.damage}
    return(
        finite_values(values[:]) &&
        landing_outcome_is_valid(impact.outcome) &&
        impact.sink_speed >= 0 &&
        impact.weight_force >= 0 &&
        impact.impact_force >= 0 &&
        impact.load_factor >= 0 &&
        impact.damage >= 0 &&
        impact.damage <= 1 \
    )
}

postale_tuning_is_valid :: proc(tuning: postale.Tuning) -> bool {
    values := [?]f32 {
        tuning.ground_clearance,
        tuning.safe_bank_radians,
        tuning.gear_compression_distance,
        tuning.gear_damping_ratio,
        tuning.smooth_landing_load,
        tuning.hard_landing_load,
        tuning.ultimate_landing_load,
        tuning.safe_exit_speed,
        tuning.throttle_up_rate,
        tuning.throttle_down_rate,
        tuning.pitch_rate_increase,
        tuning.pitch_rate_decrease,
        tuning.roll_rate_increase,
        tuning.roll_rate_decrease,
        tuning.yaw_rate_increase,
        tuning.yaw_rate_decrease,
        tuning.flap_response,
        tuning.flap_auto_throttle,
        tuning.flap_auto_speed,
        tuning.ground_brake,
        tuning.ground_coast,
        tuning.ground_steer_fast,
        tuning.ground_steer_slow,
        tuning.takeoff_throttle,
        tuning.takeoff_speed_scale,
        tuning.takeoff_pitch,
        tuning.takeoff_ground_time,
        tuning.propeller_base_rate,
        tuning.propeller_throttle_rate,
    }
    if !finite_values(values[:]) do return false
    if tuning.ground_clearance < 0 ||
       tuning.safe_bank_radians < 0 ||
       tuning.gear_compression_distance <= 0 ||
       tuning.gear_damping_ratio < 0 ||
       tuning.smooth_landing_load <= 0 ||
       tuning.hard_landing_load < tuning.smooth_landing_load ||
       tuning.ultimate_landing_load <= tuning.hard_landing_load ||
       tuning.safe_exit_speed < 0 {
        return false
    }
    rates := [?]f32 {
        tuning.throttle_up_rate,
        tuning.throttle_down_rate,
        tuning.pitch_rate_increase,
        tuning.pitch_rate_decrease,
        tuning.roll_rate_increase,
        tuning.roll_rate_decrease,
        tuning.yaw_rate_increase,
        tuning.yaw_rate_decrease,
        tuning.flap_response,
        tuning.flap_auto_speed,
        tuning.ground_brake,
        tuning.ground_coast,
        tuning.ground_steer_fast,
        tuning.ground_steer_slow,
        tuning.takeoff_ground_time,
        tuning.propeller_base_rate,
        tuning.propeller_throttle_rate,
    }
    for rate in rates {
        if rate < 0 do return false
    }
    return(
        tuning.flap_auto_throttle >= 0 &&
        tuning.flap_auto_throttle <= 1 &&
        tuning.takeoff_throttle >= 0 &&
        tuning.takeoff_throttle <= 1 &&
        tuning.takeoff_speed_scale > 0 &&
        tuning.takeoff_pitch >= -1 &&
        tuning.takeoff_pitch <= 1 \
    )
}

checkpoint_scalars_are_valid :: proc(checkpoint: postale.Checkpoint) -> bool {
    values := [?]f32 {
        checkpoint.throttle,
        checkpoint.flap_fraction,
        checkpoint.propeller_turns,
        checkpoint.pitch,
        checkpoint.roll,
        checkpoint.yaw,
        checkpoint.grounded_time,
        checkpoint.ground_pitch_radians,
        checkpoint.ground_brake_amount,
        checkpoint.gear_compression,
        checkpoint.gear_force,
        checkpoint.structural_damage,
        checkpoint.landing_feedback_seconds,
        checkpoint.landing_intent_seconds,
        checkpoint.interaction_radius,
        checkpoint.exit_distance,
    }
    return(
        finite_values(values[:]) &&
        checkpoint.throttle >= 0 &&
        checkpoint.throttle <= 1 &&
        checkpoint.flap_fraction >= 0 &&
        checkpoint.flap_fraction <= 1 &&
        checkpoint.propeller_turns >= 0 &&
        checkpoint.pitch >= -1 &&
        checkpoint.pitch <= 1 &&
        checkpoint.roll >= -1 &&
        checkpoint.roll <= 1 &&
        checkpoint.yaw >= -1 &&
        checkpoint.yaw <= 1 &&
        checkpoint.grounded_time >= 0 &&
        checkpoint.ground_brake_amount >= 0 &&
        checkpoint.ground_brake_amount <= 1 &&
        checkpoint.gear_compression >= 0 &&
        checkpoint.gear_force >= 0 &&
        checkpoint.structural_damage >= 0 &&
        checkpoint.structural_damage <= 1 &&
        checkpoint.landing_feedback_seconds >= 0 &&
        checkpoint.landing_intent_seconds >= 0 &&
        checkpoint.interaction_radius >= 0 &&
        checkpoint.exit_distance >= 0 \
    )
}

normalized_command_is_valid :: proc(command: flight.Control_Command) -> bool {
    return(
        finite_scalar(command.pitch) &&
        finite_scalar(command.roll) &&
        finite_scalar(command.yaw) &&
        finite_scalar(command.throttle) &&
        finite_scalar(command.flap_fraction) &&
        command.pitch >= -1 &&
        command.pitch <= 1 &&
        command.roll >= -1 &&
        command.roll <= 1 &&
        command.yaw >= -1 &&
        command.yaw <= 1 &&
        command.throttle >= 0 &&
        command.throttle <= 1 &&
        command.flap_fraction >= 0 &&
        command.flap_fraction <= 1 \
    )
}

scenario_is_valid :: proc(scenario: Scenario) -> bool {
    checkpoint := scenario.checkpoint
    if !checkpoint.valid do return false
    if !flight_model_is_valid(checkpoint.flight_model) do return false
    if !finite_body(checkpoint.body) do return false
    if !airframe_is_valid(checkpoint.airframe) do return false
    if !flight_runtime_is_valid(checkpoint.flight_runtime) do return false
    if !legacy_telemetry_is_valid(checkpoint.telemetry) do return false
    if !flight.ace_tuning_is_valid(checkpoint.ace_tuning) do return false
    if !ace_runtime_is_valid(checkpoint.ace_runtime) do return false
    if !ace_telemetry_is_valid(checkpoint.ace_telemetry) do return false
    if !checkpoint_scalars_are_valid(checkpoint) do return false
    if !landing_impact_is_valid(checkpoint.last_landing) do return false
    if !finite_vector(checkpoint.spawn_position) do return false
    if !finite_orientation(checkpoint.spawn_orientation) do return false
    if !postale_tuning_is_valid(checkpoint.tuning) do return false
    if !finite_scalar(scenario.delta_seconds) ||
       scenario.delta_seconds <= 0 ||
       scenario.delta_seconds > MAX_DELTA_SECONDS {
        return false
    }
    if !finite_scalar(scenario.ground_height) do return false
    for command in scenario.commands {
        if !normalized_command_is_valid(command) do return false
    }
    return true
}

flight_model_is_valid :: proc(model: postale.Flight_Model) -> bool {
    return model == .Current_Aero || model == .Ace_Arcade
}

heading_from_body :: proc(body: flight.Body_State) -> f32 {
    forward := flight.basis_from_orientation(body.orientation).forward
    return math.atan2(-forward.x, -forward.z)
}

sample_runtime :: proc(runtime: ^postale.Runtime) -> Sample {
    return {
        body = runtime.body,
        pace = postale.selected_airspeed(runtime),
        legacy_telemetry = runtime.telemetry,
        ace_telemetry = runtime.ace_telemetry,
        grounded = runtime.grounded,
        crashed = runtime.crashed,
    }
}

derive_metrics :: proc(
    samples: []Sample,
    initial_body: flight.Body_State,
    initial_pace, delta_seconds: f32,
    model: postale.Flight_Model,
) -> Metrics {
    result := Metrics {
        final_position = initial_body.position,
        final_heading  = heading_from_body(initial_body),
        min_altitude   = initial_body.position.y,
        max_altitude   = initial_body.position.y,
        min_pace       = initial_pace,
        max_pace       = initial_pace,
    }
    if len(samples) == 0 || !finite_scalar(delta_seconds) || delta_seconds <= 0 || !flight_model_is_valid(model) {
        return result
    }

    result.min_altitude = samples[0].body.position.y
    result.max_altitude = samples[0].body.position.y
    result.min_pace = samples[0].pace
    result.max_pace = samples[0].pace
    recovering := false
    recovery_start_altitude, recovery_min_altitude: f32
    previous_altitude := initial_body.position.y
    for sample in samples {
        basis := flight.basis_from_orientation(sample.body.orientation)
        local_rate := flight.world_to_local(basis, sample.body.angular_velocity_world)
        result.local_rotation += local_rate * delta_seconds
        result.min_altitude = min(result.min_altitude, sample.body.position.y)
        result.max_altitude = max(result.max_altitude, sample.body.position.y)
        result.min_pace = min(result.min_pace, sample.pace)
        result.max_pace = max(result.max_pace, sample.pace)

        is_recovery := model == .Ace_Arcade && sample.ace_telemetry.edge_state == .Recovery
        if is_recovery {
            if !recovering {
                recovering = true
                recovery_start_altitude = previous_altitude
                recovery_min_altitude = sample.body.position.y
            } else {
                recovery_min_altitude = min(recovery_min_altitude, sample.body.position.y)
            }
            result.recovery_seconds += delta_seconds
        } else if recovering {
            result.recovery_altitude_loss += max(recovery_start_altitude - recovery_min_altitude, f32(0))
            recovering = false
        }
        previous_altitude = sample.body.position.y
    }
    if recovering {
        result.recovery_altitude_loss += max(recovery_start_altitude - recovery_min_altitude, f32(0))
    }
    final := samples[len(samples) - 1].body
    result.final_position = final.position
    result.final_heading = heading_from_body(final)
    return result
}

run_model :: proc(
    scenario: Scenario,
    model: postale.Flight_Model,
    allocator: mem.Allocator,
) -> (
    result: Run_Result,
    ok: bool,
) {
    if !scenario_is_valid(scenario) || !flight_model_is_valid(model) do return
    if len(scenario.commands) > 0 && allocator.procedure == nil do return

    runtime := postale.new_runtime(scenario.checkpoint.spawn_position)
    if !postale.restore_checkpoint(&runtime, scenario.checkpoint) do return
    runtime.flight_model = model

    if len(scenario.commands) > 0 {
        result.samples = make([]Sample, len(scenario.commands), allocator)
        if result.samples == nil do return
    }

    initial_body := runtime.body
    initial_pace := postale.selected_airspeed(&runtime)
    for command, index in scenario.commands {
        postale.step_normalized_command(&runtime, command, scenario.ground_height, scenario.delta_seconds)
        result.samples[index] = sample_runtime(&runtime)
    }

    result.metrics = derive_metrics(result.samples, initial_body, initial_pace, scenario.delta_seconds, model)
    final_checkpoint, captured := postale.capture_checkpoint(&runtime)
    if !captured {
        destroy_run_result(&result, allocator)
        return
    }
    result.final_checkpoint = final_checkpoint
    return result, true
}

destroy_run_result :: proc(result: ^Run_Result, allocator: mem.Allocator) {
    if result == nil do return
    if result.samples != nil do delete(result.samples, allocator)
    result^ = {}
}

comparison_report :: proc(scenario: Scenario, model: postale.Flight_Model, result: Run_Result) -> Comparison_Report {
    final := result.final_checkpoint
    return {
        valid = final.valid,
        scenario_name = scenario.name,
        model = model,
        sample_count = len(result.samples),
        metrics = result.metrics,
        initial_ace_energy = scenario.checkpoint.ace_runtime.energy,
        final_ace_energy = final.ace_runtime.energy,
        initial_ace_edge_state = scenario.checkpoint.ace_runtime.edge_state,
        final_ace_edge_state = final.ace_runtime.edge_state,
        grounded = final.grounded,
        crashed = final.crashed,
    }
}
