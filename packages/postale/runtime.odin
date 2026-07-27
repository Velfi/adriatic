package postale

import flight "../flight"
import third_person "../third_person"
import vehicles "../vehicles"
import "core:math"
import "core:math/linalg"

// The generated Postale mesh includes exposed main wheels. Their tire bottoms
// sit roughly 1.12 world units below the body origin at presentation scale,
// so ground contact must lift the airframe enough to keep the wheels above the
// runway rather than burying them in it.
GROUND_CLEARANCE :: f32(1.14)
SAFE_BANK_RADIANS :: f32(.4363323)
SAFE_EXIT_SPEED :: f32(1)
GRAVITY :: f32(9.81)
LANDING_INTENT_HEIGHT :: f32(25)
LANDING_INTENT_CONFIRM_SECONDS :: f32(.45)
LANDING_INTENT_RELEASE_SECONDS :: f32(.2)
TAKEOFF_FLAP_FRACTION :: f32(.5)
MAX_GROUND_PITCH_RADIANS :: f32(.2094395)
GROUND_PITCH_RATE :: f32(.7)

Landing_Outcome :: enum {
    None,
    Smooth,
    Landed,
    Hard_Landing,
    Crash,
}

Landing_Impact :: struct {
    outcome:      Landing_Outcome,
    sink_speed:   f32,
    weight_force: f32,
    impact_force: f32,
    load_factor:  f32,
    damage:       f32,
}

Tuning :: struct {
    ground_clearance:          f32,
    safe_bank_radians:         f32,
    gear_compression_distance: f32,
    gear_damping_ratio:        f32,
    smooth_landing_load:       f32,
    hard_landing_load:         f32,
    ultimate_landing_load:     f32,
    safe_exit_speed:           f32,
    throttle_up_rate:          f32,
    throttle_down_rate:        f32,
    pitch_rate_increase:       f32,
    pitch_rate_decrease:       f32,
    roll_rate_increase:        f32,
    roll_rate_decrease:        f32,
    yaw_rate_increase:         f32,
    yaw_rate_decrease:         f32,
    flap_response:             f32,
    flap_auto_throttle:        f32,
    flap_auto_speed:           f32,
    ground_brake:              f32,
    ground_coast:              f32,
    ground_steer_fast:         f32,
    ground_steer_slow:         f32,
    takeoff_throttle:          f32,
    takeoff_speed_scale:       f32,
    takeoff_pitch:             f32,
    takeoff_ground_time:       f32,
    propeller_base_rate:       f32,
    propeller_throttle_rate:   f32,
}

default_tuning :: proc() -> Tuning {
    return {
        ground_clearance = GROUND_CLEARANCE,
        safe_bank_radians = SAFE_BANK_RADIANS,
        gear_compression_distance = .45,
        gear_damping_ratio = .32,
        smooth_landing_load = 1.8,
        hard_landing_load = 3.0,
        ultimate_landing_load = 5.0,
        safe_exit_speed = SAFE_EXIT_SPEED,
        throttle_up_rate = .45,
        throttle_down_rate = .65,
        pitch_rate_increase = 5.5,
        pitch_rate_decrease = 3.8,
        roll_rate_increase = 6.5,
        roll_rate_decrease = 4.8,
        yaw_rate_increase = 4.2,
        yaw_rate_decrease = 6.8,
        flap_response = 1.5,
        flap_auto_throttle = .35,
        flap_auto_speed = 28,
        ground_brake = 2.0,
        ground_coast = .12,
        ground_steer_fast = .8,
        ground_steer_slow = .22,
        takeoff_throttle = .8,
        takeoff_speed_scale = 1.015,
        takeoff_pitch = .2,
        takeoff_ground_time = .2,
        propeller_base_rate = 1.5,
        propeller_throttle_rate = 18,
    }
}

// For the current prototype, the ocean is a solid taxi/takeoff surface. Keep
// this product policy here rather than teaching the shared flight model about
// water.
drivable_surface_height :: proc(terrain_height, sea_level: f32) -> f32 {
    return max_f32(terrain_height, sea_level)
}

Runtime :: struct {
    body:                     flight.Body_State,
    vehicle:                  vehicles.Vehicle,
    airframe:                 flight.Airframe,
    flight_runtime:           flight.Runtime,
    telemetry:                flight.Telemetry,
    flight_model:             Flight_Model,
    ace_tuning:               flight.Ace_Tuning,
    ace_runtime:              flight.Ace_Runtime,
    ace_telemetry:            flight.Ace_Telemetry,
    throttle:                 f32,
    flap_fraction:            f32,
    propeller_turns:          f32,
    pitch:                    f32,
    roll:                     f32,
    yaw:                      f32,
    grounded:                 bool,
    crashed:                  bool,
    was_grounded:             bool,
    grounded_time:            f32,
    ground_pitch_radians:     f32,
    ground_brake_amount:      f32,
    gear_compression:         f32,
    gear_force:               f32,
    structural_damage:        f32,
    last_landing:             Landing_Impact,
    landing_feedback_seconds: f32,
    landing_intent_seconds:   f32,
    landing_intent:           bool,
    spawn_position:           flight.Vec3,
    spawn_orientation:        quaternion128,
    tuning:                   Tuning,
}

Control :: struct {
    throttle_up, throttle_down: bool,
    pitch, roll, yaw:           f32,
}

Ground_Result :: struct {
    grounded, crashed, touched_down: bool,
    landing:                         Landing_Impact,
}

new_runtime :: proc(spawn_position: flight.Vec3) -> Runtime {
    result := Runtime {
        airframe          = flight.postale_airframe(),
        flight_runtime    = flight.default_runtime(),
        ace_tuning        = ace_tuning_preset(),
        tuning            = default_tuning(),
        spawn_position    = spawn_position,
        spawn_orientation = flight.orientation_from_forward_and_up({-1, 0, 0}, {0, 1, 0}),
    }
    reset(&result, spawn_position.y - result.tuning.ground_clearance)
    return result
}

reset :: proc(runtime: ^Runtime, ground_height: f32) {
    if runtime == nil do return
    // Crash damage also disables the aerodynamic controls and engine. Reset
    // that underlying state with the visible damage, otherwise a repaired
    // aircraft can still have zero elevator, aileron, and throttle authority.
    runtime.flight_runtime = flight.default_runtime()
    runtime.body = {
        position    = runtime.spawn_position,
        orientation = runtime.spawn_orientation,
    }
    if runtime.flight_model != .Current_Aero && runtime.flight_model != .Ace_Arcade {
        runtime.flight_model = .Current_Aero
    }
    runtime.gear_compression = static_gear_compression(runtime)
    runtime.gear_force = runtime.airframe.mass_kg * GRAVITY
    runtime.body.position.y = ground_height + runtime.tuning.ground_clearance - runtime.gear_compression
    runtime.ace_runtime = flight.default_ace_runtime(runtime.body, runtime.ace_tuning)
    runtime.ace_telemetry = {}
    runtime.vehicle.position = to_third_person(runtime.body.position)
    runtime.vehicle.yaw_radians = yaw_radians(flight.basis_from_orientation(runtime.body.orientation))
    runtime.vehicle.interaction_radius = 2.5
    runtime.vehicle.exit_distance = 2.2
    runtime.telemetry = {}
    runtime.throttle = 0
    runtime.flap_fraction = 1
    runtime.propeller_turns = 0
    runtime.pitch = 0
    runtime.roll = 0
    runtime.yaw = 0
    runtime.grounded = true
    runtime.was_grounded = true
    runtime.grounded_time = 0
    runtime.ground_pitch_radians = 0
    runtime.ground_brake_amount = 0
    runtime.structural_damage = 0
    runtime.last_landing = {}
    runtime.landing_feedback_seconds = 0
    runtime.landing_intent_seconds = 0
    runtime.landing_intent = false
    runtime.crashed = false
}

landing_intent_candidate :: proc(runtime: ^Runtime, ground_height: f32) -> bool {
    if runtime == nil || runtime.grounded || runtime.crashed do return false
    height_agl := runtime.body.position.y - ground_height - runtime.tuning.ground_clearance
    if height_agl <= 0 || height_agl > LANDING_INTENT_HEIGHT do return false
    if runtime.body.velocity.y >= -.15 do return false
    if runtime.throttle > runtime.tuning.flap_auto_throttle do return false

    airspeed := linalg.length(runtime.body.velocity)
    stall_speed := flight.effective_stall_speed(runtime.airframe.mass_kg, runtime.airframe)
    if airspeed < stall_speed * 1.05 || airspeed > max_f32(runtime.tuning.flap_auto_speed, stall_speed * 1.75) {
        return false
    }
    basis := flight.basis_from_orientation(runtime.body.orientation)
    if math.abs(bank_radians(basis)) > runtime.tuning.safe_bank_radians do return false
    // A genuine approach points mostly along the airframe and remains settled.
    // Loops, spins, inverted passes, and tailslides fail one or more of these
    // tests even when they briefly pass through the landing altitude band.
    pitch_radians := math.asin(clamp(basis.forward.y, -1, 1))
    if math.abs(pitch_radians) > .4363323 do return false
    local_velocity := flight.world_to_local(basis, runtime.body.velocity)
    if local_velocity.z <= 0 || local_velocity.z < airspeed * .72 do return false
    local_rate := flight.world_to_local(basis, runtime.body.angular_velocity_world)
    if math.abs(local_rate.x) > .6 || math.abs(local_rate.y) > .6 || math.abs(local_rate.z) > .6 {
        return false
    }
    return true
}

update_landing_intent :: proc(runtime: ^Runtime, ground_height, delta_seconds: f32) {
    if runtime == nil || delta_seconds <= 0 do return
    dt := min_f32(delta_seconds, .05)
    // A takeoff roll or go-around must retract landing configuration promptly;
    // hysteresis is only for noisy measurements within an approach.
    if runtime.grounded || runtime.crashed || runtime.throttle > .55 || runtime.body.velocity.y > .5 {
        runtime.landing_intent_seconds = 0
        runtime.landing_intent = false
        return
    }
    if landing_intent_candidate(runtime, ground_height) {
        runtime.landing_intent_seconds = min_f32(LANDING_INTENT_CONFIRM_SECONDS, runtime.landing_intent_seconds + dt)
    } else {
        release_rate := LANDING_INTENT_CONFIRM_SECONDS / LANDING_INTENT_RELEASE_SECONDS
        runtime.landing_intent_seconds = max_f32(0, runtime.landing_intent_seconds - dt * release_rate)
    }
    runtime.landing_intent = runtime.landing_intent_seconds >= LANDING_INTENT_CONFIRM_SECONDS
}

step_airborne_model :: proc(
    runtime: ^Runtime,
    command: flight.Control_Command,
    delta_seconds: f32,
    wind: flight.Vec3 = {},
) {
    if runtime == nil || delta_seconds <= 0 do return
    modifiers := flight.model_modifiers_from_runtime(runtime.flight_runtime)
    switch runtime.flight_model {
    case .Current_Aero:
        runtime.telemetry = flight.step(
            &runtime.body,
            command,
            runtime.airframe,
            runtime.flight_runtime,
            wind,
            delta_seconds,
        )
    case .Ace_Arcade:
        runtime.ace_telemetry = flight.ace_step(
            &runtime.body,
            command,
            runtime.ace_tuning,
            &runtime.ace_runtime,
            modifiers,
            delta_seconds,
        )
    }
}

selected_airspeed :: proc(runtime: ^Runtime) -> f32 {
    if runtime == nil do return 0
    switch runtime.flight_model {
    case .Current_Aero:
        return runtime.telemetry.airspeed
    case .Ace_Arcade:
        return runtime.ace_telemetry.pace
    }
    return 0
}

step_normalized_command :: proc(
    runtime: ^Runtime,
    raw_command: flight.Control_Command,
    ground_height, delta_seconds: f32,
    wind: flight.Vec3 = {},
    ground_brake_requested: bool = false,
) -> Ground_Result {
    if runtime == nil || delta_seconds <= 0 do return {}
    dt := min_f32(delta_seconds, .05)
    runtime.landing_feedback_seconds = max_f32(0, runtime.landing_feedback_seconds - dt)
    if runtime.crashed {
        runtime.body.velocity *= max_f32(0, 1 - dt * 5)
        sync_vehicle(runtime)
        return {grounded = runtime.grounded, crashed = true}
    }

    command := flight.Control_Command {
        pitch         = clamp(raw_command.pitch, -1, 1),
        roll          = clamp(raw_command.roll, -1, 1),
        yaw           = clamp(raw_command.yaw, -1, 1),
        throttle      = clamp(raw_command.throttle, 0, 1),
        flap_fraction = clamp(raw_command.flap_fraction, 0, 1),
    }
    runtime.pitch = command.pitch
    runtime.roll = command.roll
    runtime.yaw = command.yaw
    runtime.throttle = command.throttle
    runtime.flap_fraction = command.flap_fraction

    runtime.was_grounded = runtime.grounded
    vertical_before := runtime.body.velocity.y
    step_airborne_model(runtime, command, dt, wind)

    result := resolve_ground_contact(runtime, ground_height, vertical_before, dt)
    brake_target := runtime.grounded && ground_brake_requested ? f32(1) : f32(0)
    // Hydraulic pressure and tire loading build over a fraction of a second:
    // enough to avoid a touchdown impulse without sacrificing the short
    // runway's usable braking distance.
    brake_response := brake_target > runtime.ground_brake_amount ? f32(8) : f32(5)
    runtime.ground_brake_amount = approach(runtime.ground_brake_amount, brake_target, dt * brake_response)
    if runtime.grounded {
        if runtime.was_grounded {
            runtime.grounded_time += dt
        } else {
            runtime.grounded_time = 0
        }
        // Tires remove slip through finite forces rather than deleting lateral
        // velocity on contact.
        ground_basis := flight.basis_from_orientation(runtime.body.orientation)
        forward_speed := linalg.dot(runtime.body.velocity, ground_basis.forward)
        lateral_speed := linalg.dot(runtime.body.velocity, ground_basis.right)
        // Treat rollout resistance as a constant acceleration. Multiplying
        // speed by a damping factor made the brakes strongest at touchdown
        // and could erase landing speed in about a second.
        forward_speed = approach(
            forward_speed,
            0,
            dt * lerp(runtime.tuning.ground_coast, runtime.tuning.ground_brake, runtime.ground_brake_amount),
        )
        lateral_speed = approach(lateral_speed, 0, dt * 7.5)
        vertical_speed := runtime.body.velocity.y
        runtime.body.velocity =
            ground_basis.forward * forward_speed +
            ground_basis.right * lateral_speed +
            flight.Vec3{0, vertical_speed, 0}
        runtime.body.angular_velocity_world.x *= max_f32(0, 1 - dt * 8)
        runtime.body.angular_velocity_world.z *= max_f32(0, 1 - dt * 8)
        steer :=
            runtime.yaw *
            dt *
            lerp(runtime.tuning.ground_steer_fast, runtime.tuning.ground_steer_slow, clamp(forward_speed / 20, 0, 1))
        runtime.body.orientation = rotate_ground_heading(runtime.body.orientation, steer)
    } else {
        runtime.grounded_time = 0
    }
    runtime.propeller_turns +=
        dt * (runtime.tuning.propeller_base_rate + runtime.throttle * runtime.tuning.propeller_throttle_rate)
    sync_vehicle(runtime)
    result.crashed = runtime.crashed
    return result
}

step :: proc(
    runtime: ^Runtime,
    control: Control,
    ground_height, delta_seconds: f32,
    wind: flight.Vec3 = {},
) -> Ground_Result {
    if runtime == nil || delta_seconds <= 0 do return {}
    dt := min_f32(delta_seconds, .05)
    if runtime.crashed {
        return step_normalized_command(runtime, {}, ground_height, dt, wind)
    }

    throttle_target := runtime.throttle
    if control.throttle_up do throttle_target += dt * runtime.tuning.throttle_up_rate
    if control.throttle_down do throttle_target -= dt * runtime.tuning.throttle_down_rate
    runtime.throttle = clamp(throttle_target, 0, 1)

    speed := linalg.length(runtime.body.velocity)
    pitch_rate := runtime.tuning.pitch_rate_decrease
    if math.abs(control.pitch) < math.abs(runtime.pitch) do pitch_rate = runtime.tuning.pitch_rate_increase
    roll_rate := runtime.tuning.roll_rate_decrease
    if math.abs(control.roll) < math.abs(runtime.roll) do roll_rate = runtime.tuning.roll_rate_increase
    runtime.pitch = approach(runtime.pitch, clamp(control.pitch, -1, 1), pitch_rate * dt)
    runtime.roll = approach(runtime.roll, clamp(control.roll, -1, 1), roll_rate * dt)
    runtime.yaw = slew_control(
        runtime.yaw,
        clamp(control.yaw, -1, 1),
        runtime.tuning.yaw_rate_increase,
        runtime.tuning.yaw_rate_decrease,
        dt,
    )
    update_landing_intent(runtime, ground_height, dt)
    flap_target: f32
    if runtime.grounded {
        flap_target = 1
        if runtime.throttle > .55 do flap_target = TAKEOFF_FLAP_FRACTION
    } else if (runtime.landing_intent || landing_intent_candidate(runtime, ground_height)) &&
       speed < runtime.tuning.flap_auto_speed {
        // Preserve the Postale's low-speed landing configuration, but only
        // after the motion itself looks like an approach. Low-speed aerobatics
        // and idle-power stunt passes keep a clean wing.
        flap_target = 1
    }
    runtime.flap_fraction = approach(runtime.flap_fraction, flap_target, dt * runtime.tuning.flap_response)

    if runtime.grounded {
        ground_basis := flight.basis_from_orientation(runtime.body.orientation)
        forward_speed := math.abs(linalg.dot(runtime.body.velocity, ground_basis.forward))
        rotation_speed :=
            flight.effective_stall_speed(runtime.airframe.mass_kg, runtime.airframe, runtime.flap_fraction) *
            runtime.tuning.takeoff_speed_scale
        rotation_fraction := clamp(
            (runtime.pitch - runtime.tuning.takeoff_pitch) / max_f32(1 - runtime.tuning.takeoff_pitch, .01),
            0,
            1,
        )
        speed_fraction := clamp((forward_speed - rotation_speed * .9) / max_f32(rotation_speed * .1, .01), 0, 1)
        ground_pitch_target := f32(0)
        if runtime.throttle > runtime.tuning.takeoff_throttle {
            ground_pitch_target = MAX_GROUND_PITCH_RADIANS * rotation_fraction * speed_fraction
        }
        runtime.ground_pitch_radians = approach(
            runtime.ground_pitch_radians,
            ground_pitch_target,
            GROUND_PITCH_RATE * dt,
        )
        runtime.body.orientation = set_ground_pitch(runtime.body.orientation, runtime.ground_pitch_radians)
    }

    command := flight.Control_Command {
        pitch         = runtime.pitch,
        roll          = runtime.roll,
        yaw           = runtime.yaw,
        throttle      = runtime.throttle,
        flap_fraction = runtime.flap_fraction,
    }
    return step_normalized_command(runtime, command, ground_height, dt, wind, control.throttle_down)
}

resolve_ground_contact :: proc(
    runtime: ^Runtime,
    ground_height, vertical_speed_before, delta_seconds: f32,
) -> Ground_Result {
    if runtime == nil do return {}
    rest_height := ground_height + runtime.tuning.ground_clearance
    if runtime.body.position.y > rest_height && !runtime.was_grounded {
        runtime.gear_compression = 0
        runtime.gear_force = 0
        return {}
    }

    touched_down := !runtime.was_grounded
    if touched_down {
        runtime.ground_pitch_radians = 0
        runtime.last_landing = {
            outcome      = .Smooth,
            sink_speed   = max_f32(-vertical_speed_before, 0),
            weight_force = runtime.airframe.mass_kg * GRAVITY,
        }
        runtime.landing_feedback_seconds = 4
        basis := flight.basis_from_orientation(runtime.body.orientation)
        if math.abs(bank_radians(basis)) > runtime.tuning.safe_bank_radians {
            runtime.last_landing.outcome = .Crash
            runtime.last_landing.damage = 1
        }
    }

    travel := max_f32(runtime.tuning.gear_compression_distance, .05)
    compression := clamp(rest_height - runtime.body.position.y, 0, travel)
    force := suspension_force(runtime, compression, vertical_speed_before)
    runtime.gear_compression = compression
    runtime.gear_force = force
    runtime.body.velocity.y += force / max_f32(runtime.airframe.mass_kg, 1) * delta_seconds

    bottom := rest_height - travel
    if runtime.body.position.y < bottom {
        runtime.body.position.y = bottom
        if runtime.body.velocity.y < 0 do runtime.body.velocity.y = 0
        runtime.gear_compression = travel
        runtime.gear_force = max_f32(
            runtime.gear_force,
            runtime.tuning.ultimate_landing_load * runtime.airframe.mass_kg * GRAVITY,
        )
    }

    landing := runtime.last_landing
    if landing.outcome != .None {
        previous_damage := landing.damage
        update_landing_impact(runtime, runtime.gear_force)
        damage_delta := max_f32(runtime.last_landing.damage - previous_damage, 0)
        runtime.structural_damage = clamp(
            runtime.structural_damage + damage_delta * (1 - runtime.structural_damage),
            0,
            1,
        )
        runtime.crashed = runtime.last_landing.outcome == .Crash
        runtime.flight_runtime.controls_damaged = runtime.structural_damage >= .2
        runtime.flight_runtime.control_authority = lerp(1, .68, runtime.structural_damage)
        runtime.flight_runtime.engine_output = lerp(1, .78, runtime.structural_damage)
        landing = runtime.last_landing
    }

    takeoff_speed := flight.effective_stall_speed(runtime.airframe.mass_kg, runtime.airframe, runtime.flap_fraction)
    takeoff_intent :=
        runtime.throttle > runtime.tuning.takeoff_throttle &&
        runtime.pitch > runtime.tuning.takeoff_pitch &&
        runtime.ground_pitch_radians > .0174533 &&
        selected_airspeed(runtime) >= takeoff_speed &&
        runtime.grounded_time >= runtime.tuning.takeoff_ground_time
    if compression <= .001 && runtime.body.velocity.y > 0 && takeoff_intent && !runtime.crashed {
        runtime.grounded = false
        runtime.gear_force = 0
        return {touched_down = touched_down, landing = landing}
    }
    if compression <= .001 && runtime.body.velocity.y > 0 && !takeoff_intent {
        runtime.body.position.y = rest_height
        runtime.body.velocity.y = 0
    }

    runtime.grounded = true
    runtime.body.orientation = set_ground_pitch(runtime.body.orientation, runtime.ground_pitch_radians)
    return {grounded = true, crashed = runtime.crashed, touched_down = touched_down, landing = landing}
}

static_gear_compression :: proc(runtime: ^Runtime) -> f32 {
    if runtime == nil do return 0
    travel := max_f32(runtime.tuning.gear_compression_distance, .05)
    return travel / max_f32(runtime.tuning.ultimate_landing_load, 1)
}

suspension_force :: proc(runtime: ^Runtime, compression, vertical_speed: f32) -> f32 {
    if runtime == nil do return 0
    mass := max_f32(runtime.airframe.mass_kg, 1)
    travel := max_f32(runtime.tuning.gear_compression_distance, .05)
    spring_rate := runtime.tuning.ultimate_landing_load * mass * GRAVITY / travel
    damping := 2 * clamp(runtime.tuning.gear_damping_ratio, 0, 2) * f32(math.sqrt(f64(spring_rate * mass)))
    return max_f32(0, spring_rate * clamp(compression, 0, travel) - damping * vertical_speed)
}

update_landing_impact :: proc(runtime: ^Runtime, measured_force: f32) {
    if runtime == nil || runtime.last_landing.outcome == .None do return
    impact := &runtime.last_landing
    impact.impact_force = max_f32(impact.impact_force, measured_force)
    impact.load_factor = impact.impact_force / max_f32(impact.weight_force, 1)
    if impact.load_factor >= runtime.tuning.ultimate_landing_load {
        impact.outcome = .Crash
        impact.damage = 1
    } else if impact.load_factor >= runtime.tuning.hard_landing_load {
        impact.outcome = .Hard_Landing
        impact.damage = clamp(
            (impact.load_factor - runtime.tuning.hard_landing_load) /
            max_f32(runtime.tuning.ultimate_landing_load - runtime.tuning.hard_landing_load, .1),
            .08,
            .85,
        )
    } else if impact.load_factor > runtime.tuning.smooth_landing_load {
        impact.outcome = .Landed
    } else {
        impact.outcome = .Smooth
    }
}

landing_outcome_label :: proc(outcome: Landing_Outcome) -> cstring {
    switch outcome {
    case .Smooth:
        return "SMOOTH LANDING"
    case .Landed:
        return "LANDED"
    case .Hard_Landing:
        return "HARD LANDING"
    case .Crash:
        return "CRASH"
    case .None:
        return ""
    }
    return ""
}

can_exit :: proc(runtime: ^Runtime) -> bool {
    return(
        runtime != nil &&
        runtime.grounded &&
        !runtime.crashed &&
        linalg.length(runtime.body.velocity) < runtime.tuning.safe_exit_speed \
    )
}

virtual_yoke_axis :: proc(displacement, dead_zone, full_deflection: f32) -> f32 {
    if full_deflection <= dead_zone || math.abs(displacement) <= dead_zone do return 0
    magnitude := (math.abs(displacement) - dead_zone) / (full_deflection - dead_zone)
    return math.sign(displacement) * clamp(magnitude, 0, 1)
}

sync_vehicle :: proc(runtime: ^Runtime) {
    runtime.vehicle.position = to_third_person(runtime.body.position)
    runtime.vehicle.yaw_radians = yaw_radians(flight.basis_from_orientation(runtime.body.orientation))
}

to_third_person :: proc(value: flight.Vec3) -> third_person.Vec3 {
    return {value.x, value.y, value.z}
}

to_flight :: proc(value: third_person.Vec3) -> flight.Vec3 {
    return {value.x, value.y, value.z}
}

yaw_radians :: proc(basis: flight.Basis) -> f32 {
    return math.atan2(-basis.forward.x, -basis.forward.z)
}

bank_radians :: proc(basis: flight.Basis) -> f32 {
    return math.atan2(linalg.dot(basis.right, flight.Vec3{0, 1, 0}), linalg.dot(basis.up, flight.Vec3{0, 1, 0}))
}

rotate_ground_heading :: proc(orientation: quaternion128, radians: f32) -> quaternion128 {
    if radians == 0 do return orientation
    basis := flight.basis_from_orientation(orientation)
    pitch := math.asin(clamp(basis.forward.y, -1, 1))
    return set_ground_pitch(flight.rotate_level_heading(orientation, radians), pitch)
}

set_ground_pitch :: proc(orientation: quaternion128, pitch_radians: f32) -> quaternion128 {
    basis := flight.basis_from_orientation(orientation)
    horizontal := linalg.normalize0(flight.Vec3{basis.forward.x, 0, basis.forward.z})
    if linalg.dot(horizontal, horizontal) < .001 {
        horizontal = {0, 0, -1}
    }
    pitch := clamp(pitch_radians, -MAX_GROUND_PITCH_RADIANS, MAX_GROUND_PITCH_RADIANS)
    c, s := math.cos(pitch), math.sin(pitch)
    forward := horizontal * c + flight.Vec3{0, s, 0}
    up := flight.Vec3{0, c, 0} - horizontal * s
    return flight.orientation_from_forward_and_up(forward, up)
}
approach :: proc(value, target, maximum_delta: f32) -> f32 {
    if value < target do return min_f32(value + maximum_delta, target)
    return max_f32(value - maximum_delta, target)
}

slew_control :: proc(value, target, engage_rate, release_rate, delta_seconds: f32) -> f32 {
    reversing := value != 0 && target != 0 && math.sign(value) != math.sign(target)
    rate := engage_rate
    if math.abs(target) < math.abs(value) || reversing do rate = release_rate
    return approach(value, target, rate * max_f32(delta_seconds, 0))
}

clamp :: proc(value, low, high: f32) -> f32 {
    if value < low do return low
    if value > high do return high
    return value
}

lerp :: proc(a, b, t: f32) -> f32 { return a + (b - a) * clamp(t, 0, 1) }
min_f32 :: proc(a, b: f32) -> f32 { if a < b do return a; return b }
max_f32 :: proc(a, b: f32) -> f32 { if a > b do return a; return b }
