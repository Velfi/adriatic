package air_compare

import flight "../flight"
import postale "../postale"
import "core:math"
import "core:math/bits"

SCENARIO_DELTA_SECONDS :: f32(1.0 / 120.0)
SCENARIO_GROUND_HEIGHT :: f32(-1000)

Scenario_Kind :: enum {
    Level_Cruise,
    Coordinated_Turn,
    Full_Roll,
    Loop,
    Low_Energy_Recovery,
    Aggressive_Roll_Yaw,
}

Command_Segment :: struct {
    steps:   int,
    command: flight.Control_Command,
}

Scenario_Measurement :: struct {
    absolute_heading_change: f32,
    altitude_span:           f32,
    absolute_local_rotation: flight.Vec3,
}

// Broad action-visibility contract. Zero maximum fields mean no upper bound.
Scenario_Envelope :: struct {
    require_not_crashed:             bool,
    minimum_heading_change:          f32,
    maximum_heading_change:          f32,
    minimum_altitude_span:           f32,
    maximum_altitude_span:           f32,
    minimum_signed_local_rotation:   flight.Vec3,
    minimum_absolute_local_rotation: flight.Vec3,
    maximum_absolute_local_rotation: flight.Vec3,
    minimum_recovery_seconds:        f32,
    maximum_recovery_seconds:        f32,
    minimum_recovery_altitude_loss:  f32,
    maximum_recovery_altitude_loss:  f32,
}

scenario_name :: proc(kind: Scenario_Kind) -> string {
    switch kind {
    case .Level_Cruise:
        return "level cruise"
    case .Coordinated_Turn:
        return "coordinated turn"
    case .Full_Roll:
        return "full roll"
    case .Loop:
        return "loop"
    case .Low_Energy_Recovery:
        return "low-energy break and recovery"
    case .Aggressive_Roll_Yaw:
        return "aggressive roll/yaw transition"
    }
    return ""
}

expand_command_segments :: proc(
    segments: []Command_Segment,
    allocator := context.allocator,
) -> (
    commands: []flight.Control_Command,
    ok: bool,
) {
    command_count: int
    for segment in segments {
        if segment.steps < 0 || segment.steps > bits.INT_MAX - command_count do return
        command_count += segment.steps
    }
    if command_count == 0 do return nil, true

    commands = make([]flight.Control_Command, command_count, allocator)
    index := 0
    for segment in segments {
        for _ in 0 ..< segment.steps {
            commands[index] = segment.command
            index += 1
        }
    }
    return commands, true
}

destroy_commands :: proc(commands: ^[]flight.Control_Command, allocator := context.allocator) {
    if commands == nil do return
    if commands^ != nil do delete(commands^, allocator)
    commands^ = nil
}

destroy_scenario :: proc(scenario: ^Scenario, allocator := context.allocator) {
    if scenario == nil do return
    destroy_commands(&scenario.commands, allocator)
    scenario^ = {}
}

make_airborne_checkpoint :: proc(pace, energy, altitude: f32) -> (postale.Checkpoint, bool) {
    runtime := postale.new_runtime({0, altitude, 0})
    runtime.body = {
        position    = {0, altitude, 0},
        velocity    = {0, 0, -pace},
        orientation = flight.identity_orientation(),
    }
    runtime.flight_model = .Current_Aero
    runtime.flight_runtime = flight.default_runtime()
    runtime.telemetry = {
        airspeed = pace,
    }
    runtime.ace_tuning = postale.ace_tuning_preset()
    runtime.ace_runtime = flight.default_ace_runtime(runtime.body, runtime.ace_tuning)
    runtime.ace_runtime.energy = energy
    runtime.ace_telemetry = {
        pace       = pace,
        energy     = energy,
        edge_state = .Free,
    }
    runtime.throttle = 1
    runtime.flap_fraction = 0
    runtime.pitch = 0
    runtime.roll = 0
    runtime.yaw = 0
    runtime.grounded = false
    runtime.crashed = false
    runtime.was_grounded = false
    runtime.grounded_time = 0
    runtime.ground_pitch_radians = 0
    runtime.ground_brake_amount = 0
    runtime.gear_compression = 0
    runtime.gear_force = 0
    runtime.structural_damage = 0
    runtime.last_landing = {}
    runtime.landing_feedback_seconds = 0
    runtime.landing_intent_seconds = 0
    runtime.landing_intent = false
    return postale.capture_checkpoint(&runtime)
}

make_scenario :: proc(kind: Scenario_Kind, allocator := context.allocator) -> (scenario: Scenario, ok: bool) {
    name := scenario_name(kind)
    if len(name) == 0 do return

    pace, energy, altitude: f32 = 60, 1, 120
    commands: []flight.Control_Command
    switch kind {
    case .Level_Cruise:
        segments := [?]Command_Segment{{steps = 600, command = {throttle = 1}}}
        commands, ok = expand_command_segments(segments[:], allocator)
    case .Coordinated_Turn:
        segments := [?]Command_Segment {
            {steps = 360, command = {pitch = .18, roll = .55, yaw = .25, throttle = .85}},
            {steps = 120, command = {throttle = .85}},
        }
        commands, ok = expand_command_segments(segments[:], allocator)
    case .Full_Roll:
        segments := [?]Command_Segment {
            {steps = 180, command = {roll = 1, throttle = 1}},
            {steps = 120, command = {throttle = 1}},
        }
        commands, ok = expand_command_segments(segments[:], allocator)
    case .Loop:
        pace, altitude = 65, 150
        segments := [?]Command_Segment {
            {steps = 300, command = {pitch = 1, throttle = 1}},
            {steps = 120, command = {throttle = 1}},
        }
        commands, ok = expand_command_segments(segments[:], allocator)
    case .Low_Energy_Recovery:
        pace, energy, altitude = 18, .04, 150
        segments := [?]Command_Segment {
            {steps = 240, command = {pitch = 1, roll = .6, yaw = .35}},
            {steps = 360, command = {pitch = -1, throttle = 1}},
            {steps = 360, command = {throttle = 1}},
        }
        commands, ok = expand_command_segments(segments[:], allocator)
    case .Aggressive_Roll_Yaw:
        energy = .8
        segments := [?]Command_Segment {
            {steps = 90, command = {roll = 1, yaw = 1, throttle = .9}},
            {steps = 60, command = {roll = -1, yaw = -1, throttle = .9}},
            {steps = 90, command = {roll = 1, yaw = -1, throttle = .9}},
            {steps = 120, command = {throttle = .9}},
        }
        commands, ok = expand_command_segments(segments[:], allocator)
    }
    if !ok do return

    checkpoint, captured := make_airborne_checkpoint(pace, energy, altitude)
    if !captured {
        destroy_commands(&commands, allocator)
        return
    }
    scenario = {
        name          = name,
        checkpoint    = checkpoint,
        delta_seconds = SCENARIO_DELTA_SECONDS,
        commands      = commands,
        ground_height = SCENARIO_GROUND_HEIGHT,
    }
    return scenario, true
}

scenario_envelope :: proc(
    kind: Scenario_Kind,
    model: postale.Flight_Model,
) -> (
    envelope: Scenario_Envelope,
    ok: bool,
) {
    if !flight_model_is_valid(model) do return
    envelope.require_not_crashed = true
    switch kind {
    case .Level_Cruise:
        envelope.maximum_heading_change = .25
        envelope.maximum_altitude_span = 200
        envelope.maximum_absolute_local_rotation = {2, 1, 1}
    case .Coordinated_Turn:
        envelope.minimum_heading_change = .05
        envelope.minimum_absolute_local_rotation.z = 2
    case .Full_Roll:
        if model == .Ace_Arcade {
            envelope.minimum_signed_local_rotation.z = 5.5
            envelope.minimum_absolute_local_rotation.z = 5.5
            envelope.maximum_absolute_local_rotation.z = 8.5
        } else {
            envelope.minimum_signed_local_rotation.z = 2
            envelope.minimum_absolute_local_rotation.z = 2
        }
    case .Loop:
        envelope.minimum_altitude_span = 50
        envelope.maximum_altitude_span = 400
        if model == .Ace_Arcade {
            envelope.minimum_signed_local_rotation.x = 5.5
            envelope.minimum_absolute_local_rotation.x = 5.5
            envelope.maximum_absolute_local_rotation.x = 8.5
        } else {
            envelope.minimum_signed_local_rotation.x = 2
            envelope.minimum_absolute_local_rotation.x = 2
        }
    case .Low_Energy_Recovery:
        if model == .Ace_Arcade {
            envelope.minimum_recovery_seconds = .5
            envelope.maximum_recovery_seconds = 8
            envelope.minimum_recovery_altitude_loss = .25
            envelope.maximum_recovery_altitude_loss = 100
        } else {
            envelope.maximum_recovery_seconds = .01
            envelope.maximum_recovery_altitude_loss = .01
        }
    case .Aggressive_Roll_Yaw:
        envelope.minimum_absolute_local_rotation.y = .5
        envelope.minimum_absolute_local_rotation.z = 2
    }
    return envelope, true
}

scenario_measurement :: proc(result: Run_Result) -> Scenario_Measurement {
    measurement := Scenario_Measurement {
        absolute_heading_change = math.abs(
            math.atan2(math.sin(result.metrics.final_heading), math.cos(result.metrics.final_heading)),
        ),
        altitude_span           = result.metrics.max_altitude - result.metrics.min_altitude,
    }
    for sample in result.samples {
        basis := flight.basis_from_orientation(sample.body.orientation)
        local_rate := flight.world_to_local(basis, sample.body.angular_velocity_world)
        measurement.absolute_local_rotation +=
            {math.abs(local_rate.x), math.abs(local_rate.y), math.abs(local_rate.z)} * SCENARIO_DELTA_SECONDS
    }
    return measurement
}

envelope_minimum_vector_met :: proc(value, minimum: flight.Vec3) -> bool {
    return value.x >= minimum.x && value.y >= minimum.y && value.z >= minimum.z
}

envelope_maximum_vector_met :: proc(value, maximum: flight.Vec3) -> bool {
    if maximum.x > 0 && value.x > maximum.x do return false
    if maximum.y > 0 && value.y > maximum.y do return false
    if maximum.z > 0 && value.z > maximum.z do return false
    return true
}

envelope_maximum_met :: proc(value, maximum: f32) -> bool {
    return maximum <= 0 || value <= maximum
}

scenario_result_is_within_envelope :: proc(
    kind: Scenario_Kind,
    model: postale.Flight_Model,
    result: Run_Result,
) -> bool {
    envelope, valid_envelope := scenario_envelope(kind, model)
    if !valid_envelope ||
       !result.final_checkpoint.valid ||
       result.final_checkpoint.flight_model != model ||
       len(result.samples) == 0 ||
       !finite_scalar(result.metrics.final_heading) ||
       !finite_scalar(result.metrics.min_altitude) ||
       !finite_scalar(result.metrics.max_altitude) ||
       !finite_scalar(result.metrics.min_pace) ||
       !finite_scalar(result.metrics.max_pace) ||
       result.metrics.min_pace < 0 ||
       result.metrics.max_pace < result.metrics.min_pace {
        return false
    }
    if envelope.require_not_crashed && result.final_checkpoint.crashed do return false

    measurement := scenario_measurement(result)
    signed_rotation := flight.Vec3 {
        math.abs(result.metrics.local_rotation.x),
        math.abs(result.metrics.local_rotation.y),
        math.abs(result.metrics.local_rotation.z),
    }
    return(
        measurement.absolute_heading_change >= envelope.minimum_heading_change &&
        envelope_maximum_met(measurement.absolute_heading_change, envelope.maximum_heading_change) &&
        measurement.altitude_span >= envelope.minimum_altitude_span &&
        envelope_maximum_met(measurement.altitude_span, envelope.maximum_altitude_span) &&
        envelope_minimum_vector_met(signed_rotation, envelope.minimum_signed_local_rotation) &&
        envelope_minimum_vector_met(measurement.absolute_local_rotation, envelope.minimum_absolute_local_rotation) &&
        envelope_maximum_vector_met(measurement.absolute_local_rotation, envelope.maximum_absolute_local_rotation) &&
        result.metrics.recovery_seconds >= envelope.minimum_recovery_seconds &&
        envelope_maximum_met(result.metrics.recovery_seconds, envelope.maximum_recovery_seconds) &&
        result.metrics.recovery_altitude_loss >= envelope.minimum_recovery_altitude_loss &&
        envelope_maximum_met(result.metrics.recovery_altitude_loss, envelope.maximum_recovery_altitude_loss) \
    )
}
