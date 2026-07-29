package flight

import "core:math"
import "core:math/linalg"

ACE_MAX_STEP_SECONDS :: f32(.05)

Ace_Edge_State :: enum {
    Free,
    Warning,
    Hang,
    Break,
    Recovery,
}

Ace_Tuning :: struct {
    pace, punch, coast, brake:                     f32,
    roll_snap, pull_strength, rudder_bite:         f32,
    weight, settle:                                f32,
    air_grip, drift, turn_hold:                    f32,
    climb_generosity, dive_payoff:                 f32,
    hang_time, break_drama, recovery_punch:        f32,
    low_speed_authority:                           f32,
    steadiness, line_hold, commitment, exit_catch: f32,
}

Ace_Runtime :: struct {
    energy:       f32,
    edge_state:   Ace_Edge_State,
    edge_seconds: f32,
    local_rate:   Vec3 `fixture:"-"`,
}

Ace_Telemetry :: struct {
    pace, energy:         f32,
    track_grip:           f32,
    attitude_track_angle: f32,
    edge_state:           Ace_Edge_State,
}

// Technical movement values derived from designer-facing normalized knobs.
Ace_Derived_Tuning :: struct {
    minimum_pace, cruise_pace, dive_pace:                     f32,
    maximum_pitch_rate, maximum_roll_rate, maximum_yaw_rate:  f32,
    engage_response, roll_engage_response, release_response:  f32,
    pace_punch_response, pace_coast_loss_response:            f32,
    pace_brake_response:                                      f32,
    track_grip_response, track_retention:                     f32,
    throttle_energy_gain, dive_energy_gain:                   f32,
    climb_energy_cost, turn_energy_cost:                      f32,
    slip_energy_cost, inverted_energy_cost, edge_energy_cost: f32,
    turn_pace_loss, climb_pace_loss:                          f32,
    warning_margin, hang_margin:                              f32,
    break_margin, recovery_margin:                            f32,
    warning_min_seconds, hang_seconds:                        f32,
    break_min_seconds, recovery_min_seconds:                  f32,
    break_pitch_drama, break_roll_drama, break_track_drama:   f32,
    recovery_response, recovery_energy_gain:                  f32,
    low_energy_pitch_authority:                               f32,
    low_energy_roll_authority, low_energy_yaw_authority:      f32,
    steadiness_response, line_hold_response:                  f32,
    commitment_threshold:                                     f32,
    exit_catch_seconds, exit_catch_response:                  f32,
}

// Immutable product intent shared by airborne movement models.
Model_Modifiers :: struct {
    // Effective usable engine fraction after product damage and tuning, normalized to [0, 1].
    engine_output:     f32,
    // Primary-control authority after product damage and tuning, normalized to [0, 1].
    control_authority: f32,
    // Coarse damaged-controls mode; not a structural-damage amount.
    controls_damaged:  bool,
}

normalized_fraction :: proc(value: f32) -> f32 {
    if value != value do return 0
    return clamp(value, 0, 1)
}

model_modifiers_from_runtime :: proc(runtime: Runtime) -> Model_Modifiers {
    return {
        engine_output = normalized_fraction(runtime.engine_output),
        control_authority = normalized_fraction(runtime.control_authority),
        controls_damaged = runtime.controls_damaged,
    }
}

default_ace_tuning :: proc() -> Ace_Tuning {
    return {
        pace = .5,
        punch = .5,
        coast = .5,
        brake = .5,
        roll_snap = .5,
        pull_strength = .5,
        rudder_bite = .5,
        weight = .5,
        settle = .5,
        air_grip = .5,
        drift = .5,
        turn_hold = .5,
        climb_generosity = .5,
        dive_payoff = .5,
        hang_time = .5,
        break_drama = .5,
        recovery_punch = .5,
        low_speed_authority = .5,
        steadiness = .5,
        line_hold = .5,
        commitment = .5,
        exit_catch = .5,
    }
}

clamp_ace_tuning :: proc(tuning: Ace_Tuning) -> Ace_Tuning {
    result := tuning
    result.pace = normalized_fraction(result.pace)
    result.punch = normalized_fraction(result.punch)
    result.coast = normalized_fraction(result.coast)
    result.brake = normalized_fraction(result.brake)
    result.roll_snap = normalized_fraction(result.roll_snap)
    result.pull_strength = normalized_fraction(result.pull_strength)
    result.rudder_bite = normalized_fraction(result.rudder_bite)
    result.weight = normalized_fraction(result.weight)
    result.settle = normalized_fraction(result.settle)
    result.air_grip = normalized_fraction(result.air_grip)
    result.drift = normalized_fraction(result.drift)
    result.turn_hold = normalized_fraction(result.turn_hold)
    result.climb_generosity = normalized_fraction(result.climb_generosity)
    result.dive_payoff = normalized_fraction(result.dive_payoff)
    result.hang_time = normalized_fraction(result.hang_time)
    result.break_drama = normalized_fraction(result.break_drama)
    result.recovery_punch = normalized_fraction(result.recovery_punch)
    result.low_speed_authority = normalized_fraction(result.low_speed_authority)
    result.steadiness = normalized_fraction(result.steadiness)
    result.line_hold = normalized_fraction(result.line_hold)
    result.commitment = normalized_fraction(result.commitment)
    result.exit_catch = normalized_fraction(result.exit_catch)
    return result
}

ace_tuning_is_valid :: proc(tuning: Ace_Tuning) -> bool {
    return clamp_ace_tuning(tuning) == tuning
}

derive_ace_tuning :: proc(raw: Ace_Tuning) -> Ace_Derived_Tuning {
    tuning := clamp_ace_tuning(raw)
    engage_response := lerp(12, 3, tuning.weight)
    cruise_pace := lerp(45, 75, tuning.pace)

    return {
        minimum_pace = lerp(14, 22, tuning.pace),
        cruise_pace = cruise_pace,
        dive_pace = cruise_pace + lerp(10, 30, tuning.pace),
        maximum_pitch_rate = lerp(.8, 2.8, tuning.pull_strength),
        maximum_roll_rate = lerp(2, 7, tuning.roll_snap),
        maximum_yaw_rate = lerp(.45, 1.8, tuning.rudder_bite),
        engage_response = engage_response,
        roll_engage_response = engage_response * lerp(.85, 1.25, tuning.roll_snap),
        release_response = lerp(3, 16, tuning.settle),
        pace_punch_response = lerp(1.5, 8, tuning.punch),
        pace_coast_loss_response = lerp(2, .2, tuning.coast),
        pace_brake_response = lerp(.8, 7, tuning.brake),
        track_grip_response = lerp(.8, 5, tuning.air_grip) * lerp(1, .45, tuning.drift),
        track_retention = lerp(.1, .65, tuning.drift),
        throttle_energy_gain = lerp(.12, .4, tuning.punch),
        dive_energy_gain = lerp(.12, .6, tuning.dive_payoff),
        climb_energy_cost = lerp(.65, .18, tuning.climb_generosity),
        turn_energy_cost = lerp(.65, .22, tuning.turn_hold),
        slip_energy_cost = lerp(.42, .2, tuning.drift),
        inverted_energy_cost = .28,
        edge_energy_cost = .28,
        turn_pace_loss = lerp(.75, .2, tuning.turn_hold),
        climb_pace_loss = lerp(.45, .14, tuning.climb_generosity),
        warning_margin = .42,
        hang_margin = .28,
        break_margin = .12,
        recovery_margin = .55,
        warning_min_seconds = .15,
        hang_seconds = lerp(.4, 2.2, tuning.hang_time),
        break_min_seconds = .35,
        recovery_min_seconds = lerp(1.6, .5, tuning.recovery_punch),
        break_pitch_drama = lerp(.18, 1, tuning.break_drama),
        break_roll_drama = lerp(.35, 2.5, tuning.break_drama),
        break_track_drama = lerp(.12, .75, tuning.break_drama),
        recovery_response = lerp(2.5, 10, tuning.recovery_punch),
        recovery_energy_gain = lerp(.12, .65, tuning.recovery_punch),
        low_energy_pitch_authority = lerp(.18, .53, tuning.low_speed_authority),
        low_energy_roll_authority = lerp(.45, .9, tuning.low_speed_authority),
        low_energy_yaw_authority = lerp(.55, .95, tuning.low_speed_authority),
        steadiness_response = lerp(1, 8, tuning.steadiness),
        line_hold_response = lerp(.2, 4, tuning.line_hold),
        commitment_threshold = lerp(.9, .55, tuning.commitment),
        exit_catch_seconds = lerp(0, 1.1, tuning.exit_catch),
        exit_catch_response = lerp(0, 8, tuning.exit_catch),
    }
}

default_ace_runtime :: proc(body: Body_State, _: Ace_Tuning) -> Ace_Runtime {
    basis := basis_from_orientation(body.orientation)
    return {local_rate = world_to_local(basis, body.angular_velocity_world)}
}

ace_angular_value_is_valid :: proc(value: f32) -> bool {
    return value == value && !math.is_inf_f32(value) && value >= 0
}

ace_angular_vector_is_finite :: proc(value: Vec3) -> bool {
    for component in value {
        if component != component || math.is_inf_f32(component) do return false
    }
    return true
}

ace_orientation_is_finite :: proc(value: quaternion128) -> bool {
    components := [?]f32{value.x, value.y, value.z, value.w}
    for component in components {
        if component != component || math.is_inf_f32(component) do return false
    }
    return true
}

ace_angular_tuning_is_valid :: proc(tuning: Ace_Derived_Tuning) -> bool {
    values := [?]f32 {
        tuning.maximum_pitch_rate,
        tuning.maximum_roll_rate,
        tuning.maximum_yaw_rate,
        tuning.engage_response,
        tuning.roll_engage_response,
        tuning.release_response,
        tuning.low_energy_pitch_authority,
        tuning.low_energy_roll_authority,
        tuning.low_energy_yaw_authority,
        tuning.steadiness_response,
        tuning.commitment_threshold,
    }
    for value in values {
        if !ace_angular_value_is_valid(value) do return false
    }
    return(
        tuning.low_energy_pitch_authority <= 1 &&
        tuning.low_energy_roll_authority <= 1 &&
        tuning.low_energy_yaw_authority <= 1 &&
        tuning.commitment_threshold <= 1 \
    )
}

ace_shape_angular_command :: proc(raw, commitment_threshold: f32) -> f32 {
    if raw != raw do return 0
    value := clamp(raw, -1, 1)
    magnitude := math.abs(value)
    precise := magnitude * magnitude * (3 - 2 * magnitude)
    strong_range := 1 - commitment_threshold
    strong: f32
    if strong_range > 1e-5 {
        progress := clamp((magnitude - commitment_threshold) / strong_range, 0, 1)
        strong = progress * progress * (3 - 2 * progress)
    } else if magnitude >= 1 {
        strong = 1
    }
    strong_target := 1 - (1 - magnitude) * (1 - magnitude)
    return sign(value) * lerp(precise, strong_target, strong * .35)
}

ace_approach_angular_rate :: proc(current, target, response, delta_seconds: f32) -> f32 {
    alpha := 1 - f32(math.exp(f64(-response * delta_seconds)))
    return lerp(current, target, alpha)
}

ace_step_angular :: proc(
    body: ^Body_State,
    command: Control_Command,
    derived: Ace_Derived_Tuning,
    runtime: ^Ace_Runtime,
    modifiers: Model_Modifiers,
    delta_seconds: f32,
) {
    if body == nil || runtime == nil do return
    if !(delta_seconds > 0) || delta_seconds > ACE_MAX_STEP_SECONDS || math.is_inf_f32(delta_seconds) do return
    if !ace_angular_tuning_is_valid(derived) do return
    if !ace_angular_vector_is_finite(body.angular_velocity_world) do return
    if !ace_orientation_is_finite(body.orientation) do return

    body.orientation = normalize_orientation(body.orientation)
    basis := basis_from_orientation(body.orientation)
    local_rate := world_to_local(basis, body.angular_velocity_world)
    shaped := Vec3 {
        ace_shape_angular_command(command.pitch, derived.commitment_threshold),
        ace_shape_angular_command(command.yaw, derived.commitment_threshold),
        ace_shape_angular_command(command.roll, derived.commitment_threshold),
    }

    energy := normalized_fraction(runtime.energy)
    control_authority := normalized_fraction(modifiers.control_authority)
    damage_authority: f32 = 1
    if modifiers.controls_damaged do damage_authority = .65
    authority :=
        Vec3 {
            lerp(derived.low_energy_pitch_authority, 1, energy),
            lerp(derived.low_energy_yaw_authority, 1, energy),
            lerp(derived.low_energy_roll_authority, 1, energy),
        } *
        control_authority *
        damage_authority
    target :=
        Vec3 {
            shaped.x * derived.maximum_pitch_rate,
            -shaped.y * derived.maximum_yaw_rate,
            shaped.z * derived.maximum_roll_rate,
        } *
        authority

    if runtime.edge_state == .Break {
        break_side := sign(shaped.z - shaped.y)
        if break_side == 0 do break_side = sign(local_rate.z - local_rate.y)
        target.x = min_f32(target.x, -derived.break_pitch_drama)
        target.z += break_side * derived.break_roll_drama
    }

    response_scale: f32 = 1
    if runtime.edge_state == .Recovery {
        response_scale += derived.recovery_response * .1
    }
    neutral_response := (derived.release_response + derived.steadiness_response) * response_scale
    if runtime.edge_state == .Recovery && runtime.edge_seconds <= derived.exit_catch_seconds {
        neutral_response += derived.exit_catch_response
    }
    engage_responses := Vec3{derived.engage_response, derived.engage_response, derived.roll_engage_response}
    engage_responses *= response_scale
    for axis in 0 ..< 3 {
        current_axis, target_axis := local_rate[axis], target[axis]
        command_is_neutral := math.abs(shaped[axis]) <= 1e-5
        starts_from_neutral := math.abs(current_axis) <= 1e-5
        continues_and_increases :=
            sign(current_axis) == sign(target_axis) && math.abs(target_axis) > math.abs(current_axis)
        response := derived.release_response
        if command_is_neutral {
            response = neutral_response
        } else if starts_from_neutral || continues_and_increases {
            response = engage_responses[axis]
        }
        local_rate[axis] = ace_approach_angular_rate(local_rate[axis], target[axis], response, delta_seconds)
    }

    runtime.local_rate = local_rate
    body.angular_velocity_world = local_to_world(basis, local_rate)
    body.orientation = integrate_orientation(body.orientation, body.angular_velocity_world, delta_seconds)
}

ace_signed_fraction :: proc(value: f32) -> f32 {
    if value != value do return 0
    return clamp(value, -1, 1)
}

ace_safe_command :: proc(command: Control_Command) -> Control_Command {
    return {
        pitch = ace_signed_fraction(command.pitch),
        roll = ace_signed_fraction(command.roll),
        yaw = ace_signed_fraction(command.yaw),
        throttle = normalized_fraction(command.throttle),
        flap_fraction = normalized_fraction(command.flap_fraction),
    }
}

ace_safe_modifiers :: proc(modifiers: Model_Modifiers) -> Model_Modifiers {
    return {
        engine_output = normalized_fraction(modifiers.engine_output),
        control_authority = normalized_fraction(modifiers.control_authority),
        controls_damaged = modifiers.controls_damaged,
    }
}

ace_direction_or :: proc(direction, fallback: Vec3) -> Vec3 {
    length_squared := linalg.dot(direction, direction)
    if !(length_squared > 1e-8) || math.is_inf_f32(length_squared) do return fallback
    return direction / math.sqrt(length_squared)
}

ace_track_angle :: proc(track, attitude_forward: Vec3) -> f32 {
    return math.acos(clamp(linalg.dot(track, attitude_forward), -1, 1))
}

ace_input_demand :: proc(command: Control_Command) -> f32 {
    return clamp(
        math.sqrt(command.pitch * command.pitch + command.roll * command.roll + command.yaw * command.yaw) /
        math.sqrt(f32(3)),
        0,
        1,
    )
}

ace_edge_energy_demand :: proc(state: Ace_Edge_State) -> f32 {
    switch state {
    case .Free:
        return 0
    case .Warning:
        return .25
    case .Hang:
        return .55
    case .Break:
        return 1
    case .Recovery:
        return .2
    }
    return 1
}

ace_enter_edge_state :: proc(runtime: ^Ace_Runtime, state: Ace_Edge_State) {
    runtime.edge_state = state
    runtime.edge_seconds = 0
}

ace_edge_state_is_valid :: proc(state: Ace_Edge_State) -> bool {
    switch state {
    case .Free, .Warning, .Hang, .Break, .Recovery:
        return true
    }
    return false
}

ace_update_edge_state :: proc(
    body: ^Body_State,
    command: Control_Command,
    derived: Ace_Derived_Tuning,
    runtime: ^Ace_Runtime,
    track: Vec3,
    pace: f32,
    delta_seconds: f32,
) {
    if !ace_edge_state_is_valid(runtime.edge_state) {
        ace_enter_edge_state(runtime, .Break)
    }

    basis := basis_from_orientation(body.orientation)
    pace_range := max_f32(derived.cruise_pace - derived.minimum_pace, 1)
    pace_margin := clamp((pace - derived.minimum_pace) / pace_range, 0, 1)
    margin := runtime.energy * .7 + pace_margin * .3
    inverted := clamp(-linalg.dot(basis.up, Vec3{0, 1, 0}), 0, 1)
    edge_demand := max_f32(
        max_f32(max_f32(command.pitch, 0), math.abs(command.yaw) * .8),
        max_f32(math.abs(command.roll) * .65, inverted * .65),
    )
    demand_released := edge_demand < .22
    entry_demand := derived.commitment_threshold * .65
    nose_down := basis.forward.y < -.18
    track_down := track.y < -.16
    recovery_intent :=
        command.pitch < -.25 ||
        (nose_down && command.pitch <= 0) ||
        (track_down && basis.forward.y <= 0 && command.pitch <= 0) ||
        margin >= derived.recovery_margin

    if runtime.edge_state == .Free {
        runtime.edge_seconds = 0
        if margin <= derived.warning_margin && edge_demand >= entry_demand {
            ace_enter_edge_state(runtime, .Warning)
        }
        return
    }

    runtime.edge_seconds += delta_seconds
    switch runtime.edge_state {
    case .Free:
    case .Warning:
        if demand_released || margin > derived.warning_margin + .06 {
            ace_enter_edge_state(runtime, .Free)
        } else if runtime.edge_seconds >= derived.warning_min_seconds &&
           margin <= derived.hang_margin &&
           edge_demand >= .35 {
            ace_enter_edge_state(runtime, .Hang)
        }
    case .Hang:
        if recovery_intent || demand_released {
            ace_enter_edge_state(runtime, .Recovery)
        } else if runtime.edge_seconds >= derived.hang_seconds &&
           margin <= derived.break_margin &&
           edge_demand >= .35 {
            ace_enter_edge_state(runtime, .Break)
        }
    case .Break:
        if runtime.edge_seconds >= derived.break_min_seconds && recovery_intent {
            ace_enter_edge_state(runtime, .Recovery)
        }
    case .Recovery:
        local_rate := world_to_local(basis, body.angular_velocity_world)
        controlled_rate := linalg.length(local_rate) < .75
        if runtime.edge_seconds >= derived.recovery_min_seconds &&
           margin >= derived.recovery_margin &&
           basis.forward.y < .25 &&
           controlled_rate {
            ace_enter_edge_state(runtime, .Free)
        }
    }
}

ace_knife_edge_support :: proc(
    basis: Basis,
    pace, energy, yaw: f32,
    tuning: Ace_Tuning,
    derived: Ace_Derived_Tuning,
    modifiers: Model_Modifiers,
) -> Vec3 {
    world_up := Vec3{0, 1, 0}
    upright_alignment := clamp(linalg.dot(basis.up, world_up), -1, 1)
    knife_attitude := math.sqrt(max_f32(0, 1 - upright_alignment * upright_alignment))
    pace_range := max_f32(derived.cruise_pace - derived.minimum_pace, 1)
    pace_fraction := clamp((pace - derived.minimum_pace) / pace_range, 0, 1)
    skyward_rudder := clamp(ace_signed_fraction(yaw) * linalg.dot(basis.right, world_up), 0, 1)
    damage_authority: f32 = 1
    if modifiers.controls_damaged do damage_authority = .65
    control_authority := normalized_fraction(modifiers.control_authority) * damage_authority
    support :=
        knife_attitude *
        pace_fraction *
        normalized_fraction(energy) *
        skyward_rudder *
        control_authority *
        lerp(.12, .32, normalized_fraction(tuning.rudder_bite))
    return world_up * support
}

ace_step :: proc(
    body: ^Body_State,
    raw_command: Control_Command,
    raw_tuning: Ace_Tuning,
    runtime: ^Ace_Runtime,
    raw_modifiers: Model_Modifiers,
    delta_seconds: f32,
) -> Ace_Telemetry {
    if body == nil || runtime == nil do return {}
    if !(delta_seconds > 0) || delta_seconds > ACE_MAX_STEP_SECONDS || math.is_inf_f32(delta_seconds) {
        return {}
    }
    if !ace_angular_vector_is_finite(body.position) ||
       !ace_angular_vector_is_finite(body.velocity) ||
       !ace_angular_vector_is_finite(body.angular_velocity_world) ||
       !ace_orientation_is_finite(body.orientation) {
        return {}
    }

    current_pace := linalg.length(body.velocity)
    if math.is_inf_f32(current_pace) || current_pace != current_pace do return {}

    tuning := clamp_ace_tuning(raw_tuning)
    derived := derive_ace_tuning(tuning)
    command := ace_safe_command(raw_command)
    modifiers := ace_safe_modifiers(raw_modifiers)
    runtime.energy = normalized_fraction(runtime.energy)
    if runtime.edge_seconds != runtime.edge_seconds ||
       math.is_inf_f32(runtime.edge_seconds) ||
       runtime.edge_seconds < 0 {
        runtime.edge_seconds = 0
    }

    starting_basis := basis_from_orientation(body.orientation)
    current_track := ace_direction_or(body.velocity, starting_basis.forward)
    ace_update_edge_state(body, command, derived, runtime, current_track, current_pace, delta_seconds)

    ace_step_angular(body, command, derived, runtime, modifiers, delta_seconds)

    basis := basis_from_orientation(body.orientation)
    world_up := Vec3{0, 1, 0}
    horizontal_forward := ace_direction_or(
        {basis.forward.x, 0, basis.forward.z},
        ace_direction_or({current_track.x, 0, current_track.z}, Vec3{0, 0, -1}),
    )
    horizontal_right := ace_direction_or(linalg.cross(horizontal_forward, world_up), basis.right)
    demand := ace_input_demand(command)
    small_input := 1 - clamp(demand / .35, 0, 1)
    line_hold := small_input * clamp(derived.line_hold_response / 4, 0, 1)
    retention := clamp(derived.track_retention + line_hold * .25, 0, .85)
    energy_coupling := lerp(.45, 1, runtime.energy)
    bank := clamp(-linalg.dot(basis.right, world_up), -1, 1)
    bank_turn := horizontal_right * (bank * .24 * energy_coupling)
    damage_authority: f32 = 1
    if modifiers.controls_damaged do damage_authority = .65
    carve_authority := modifiers.control_authority * damage_authority
    yaw_carve :=
        horizontal_right * (command.yaw * lerp(.08, .2, tuning.rudder_bite) * energy_coupling * carve_authority)
    knife_support := ace_knife_edge_support(
        basis,
        current_pace,
        runtime.energy,
        command.yaw,
        tuning,
        derived,
        modifiers,
    )
    gravity_bias := lerp(.12, .025, clamp(current_pace / derived.cruise_pace, 0, 1)) * lerp(1, .35, line_hold)
    edge_bias: Vec3
    edge_track_response: f32 = 1
    switch runtime.edge_state {
    case .Free, .Warning:
    case .Hang:
        retention = clamp(retention + .15, 0, .9)
        edge_track_response = .65
    case .Break:
        break_side := sign(-runtime.local_rate.y + runtime.local_rate.z)
        edge_bias =
            horizontal_right * (break_side * derived.break_track_drama * .45) +
            world_up * (-derived.break_track_drama * .35)
        edge_track_response = lerp(1, 1.6, tuning.break_drama)
    case .Recovery:
        retention *= .5
        edge_track_response = 1 + derived.recovery_response * .1
    }
    desired_track := ace_direction_or(
        current_track * retention +
        basis.forward * (1 - retention) +
        bank_turn +
        yaw_carve +
        knife_support +
        world_up * -gravity_bias +
        edge_bias,
        current_track,
    )
    track_response := derived.track_grip_response * energy_coupling * edge_track_response
    track_alpha := clamp(1 - f32(math.exp(f64(-track_response * delta_seconds))), 0, .45)
    track := ace_direction_or(current_track + (desired_track - current_track) * track_alpha, current_track)
    attitude_track_angle := ace_track_angle(track, basis.forward)

    climb := clamp(track.y, 0, 1)
    dive := clamp(-track.y, 0, 1)
    slip := clamp(attitude_track_angle / f32(math.PI / 2), 0, 1)
    inverted := clamp(-linalg.dot(basis.up, world_up), 0, 1)
    edge_demand := ace_edge_energy_demand(runtime.edge_state)
    effective_throttle := command.throttle * modifiers.engine_output
    energy_change :=
        effective_throttle * derived.throttle_energy_gain +
        dive * derived.dive_energy_gain -
        climb * derived.climb_energy_cost -
        demand * demand * derived.turn_energy_cost -
        slip * slip * derived.slip_energy_cost -
        inverted * derived.inverted_energy_cost -
        edge_demand * derived.edge_energy_cost
    if runtime.edge_state == .Recovery {
        recovery_intent := clamp(effective_throttle + clamp(-basis.forward.y, 0, 1), 0, 1)
        energy_change += recovery_intent * derived.recovery_energy_gain
    }
    runtime.energy = clamp(runtime.energy + energy_change * delta_seconds, 0, 1)

    energy_supported_cruise := lerp(derived.minimum_pace, derived.cruise_pace, runtime.energy)
    target_pace := lerp(derived.minimum_pace, energy_supported_cruise, effective_throttle)
    target_pace = lerp(target_pace, derived.dive_pace, dive * runtime.energy)
    pace_loss := climb * derived.climb_pace_loss + demand * demand * derived.turn_pace_loss
    target_pace = derived.minimum_pace + (target_pace - derived.minimum_pace) * (1 - clamp(pace_loss, 0, .8))

    pace_response := derived.pace_punch_response
    if target_pace < current_pace {
        // Current command has throttle level but no distinct brake action.
        // Low throttle is therefore the temporary airborne braking intent.
        low_throttle := 1 - command.throttle
        pace_response = derived.pace_coast_loss_response + derived.pace_brake_response * low_throttle * low_throttle
    }
    pace_alpha := clamp(1 - f32(math.exp(f64(-pace_response * delta_seconds))), 0, 1)
    pace := lerp(current_pace, target_pace, pace_alpha)
    if !(pace > 0) || pace != pace || math.is_inf_f32(pace) do pace = derived.minimum_pace

    body.velocity = track * pace
    body.position += body.velocity * delta_seconds

    return {
        pace = pace,
        energy = runtime.energy,
        track_grip = clamp(track_response / 5, 0, 1),
        attitude_track_angle = attitude_track_angle,
        edge_state = runtime.edge_state,
    }
}
