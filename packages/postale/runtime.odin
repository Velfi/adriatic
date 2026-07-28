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
TAKEOFF_STALL_SPEED_SCALE :: f32(.68)
GRAVITY :: f32(9.81)

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
    takeoff_stall_speed_scale: f32,
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
    takeoff_vertical_assist:   f32,
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
        takeoff_stall_speed_scale = TAKEOFF_STALL_SPEED_SCALE,
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
        ground_brake = 3.2,
        ground_coast = .12,
        ground_steer_fast = .8,
        ground_steer_slow = .22,
        takeoff_throttle = .8,
        takeoff_speed_scale = .9,
        takeoff_pitch = .2,
        takeoff_ground_time = .2,
        takeoff_vertical_assist = 2.4,
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
    takeoff_armed:            bool,
    gear_compression:         f32,
    gear_force:               f32,
    structural_damage:        f32,
    last_landing:             Landing_Impact,
    landing_feedback_seconds: f32,
    spawn_position:           flight.Vec3,
    spawn_basis:              flight.Basis,
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
        airframe = flight.postale_airframe(),
        flight_runtime = flight.default_runtime(),
        tuning = default_tuning(),
        spawn_position = spawn_position,
        spawn_basis = {forward = {-1, 0, 0}, up = {0, 1, 0}, right = {0, 0, -1}},
    }
    result.flight_runtime.stall_speed_modifier = result.tuning.takeoff_stall_speed_scale
    reset(&result, spawn_position.y - result.tuning.ground_clearance)
    return result
}

reset :: proc(runtime: ^Runtime, ground_height: f32) {
    if runtime == nil do return
    // Crash damage also disables the aerodynamic controls and engine. Reset
    // that underlying state with the visible damage, otherwise a repaired
    // aircraft can still have zero elevator, aileron, and throttle authority.
    runtime.flight_runtime = flight.default_runtime()
    runtime.flight_runtime.stall_speed_modifier = runtime.tuning.takeoff_stall_speed_scale
    runtime.body = {
        position = runtime.spawn_position,
        basis    = runtime.spawn_basis,
    }
    runtime.gear_compression = static_gear_compression(runtime)
    runtime.gear_force = runtime.airframe.mass_kg * GRAVITY
    runtime.body.position.y = ground_height + runtime.tuning.ground_clearance - runtime.gear_compression
    runtime.vehicle.position = to_third_person(runtime.body.position)
    runtime.vehicle.yaw_radians = yaw_radians(runtime.body.basis)
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
    runtime.takeoff_armed = true
    runtime.structural_damage = 0
    runtime.last_landing = {}
    runtime.landing_feedback_seconds = 0
    runtime.crashed = false
}

step :: proc(runtime: ^Runtime, control: Control, ground_height, delta_seconds: f32) -> Ground_Result {
    if runtime == nil || delta_seconds <= 0 do return {}
    dt := min_f32(delta_seconds, .05)
    runtime.landing_feedback_seconds = max_f32(0, runtime.landing_feedback_seconds - dt)
    if runtime.crashed {
        runtime.body.velocity *= max_f32(0, 1 - dt * 5)
        sync_vehicle(runtime)
        return {grounded = runtime.grounded, crashed = true}
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
    flap_target: f32
    if runtime.grounded ||
       (runtime.throttle < runtime.tuning.flap_auto_throttle && speed < runtime.tuning.flap_auto_speed) {
        flap_target = 1
    }
    runtime.flap_fraction = approach(runtime.flap_fraction, flap_target, dt * runtime.tuning.flap_response)

    command := flight.Control_Command {
        pitch        = runtime.pitch,
        roll         = runtime.roll,
        yaw          = runtime.yaw,
        throttle     = runtime.throttle,
        flap_setting = int(math.round(f64(runtime.flap_fraction * 2))),
    }
    runtime.was_grounded = runtime.grounded
    vertical_before := runtime.body.velocity.y
    runtime.telemetry = flight.step(&runtime.body, command, runtime.airframe, runtime.flight_runtime, {}, dt)

    result := resolve_ground_contact(runtime, ground_height, vertical_before, dt)
    if runtime.grounded {
        if runtime.was_grounded {
            runtime.grounded_time += dt
        } else {
            runtime.grounded_time = 0
        }
        if runtime.pitch <= runtime.tuning.takeoff_pitch && runtime.grounded_time >= .5 {
            runtime.takeoff_armed = true
        }
        // Wheels remove lateral slip and make low-speed runway steering forgiving.
        forward_speed := linalg.dot(runtime.body.velocity, runtime.body.basis.forward)
        forward_speed *= max_f32(
            0,
            1 - dt * (control.throttle_down ? runtime.tuning.ground_brake : runtime.tuning.ground_coast),
        )
        vertical_speed := runtime.body.velocity.y
        runtime.body.velocity =
            runtime.body.basis.forward * max_f32(0, forward_speed) + flight.Vec3{0, vertical_speed, 0}
        runtime.body.angular_velocity.x = 0
        runtime.body.angular_velocity.z = 0
        steer :=
            runtime.yaw *
            dt *
            lerp(runtime.tuning.ground_steer_fast, runtime.tuning.ground_steer_slow, clamp(forward_speed / 20, 0, 1))
        rotate_ground_heading(&runtime.body.basis, steer)
        // Short-field assistance lets the authored runway reach flying speed.
        rotation_speed :=
            flight.effective_stall_speed(runtime.airframe.mass_kg, runtime.airframe) *
            runtime.tuning.takeoff_speed_scale
        if runtime.throttle > runtime.tuning.takeoff_throttle &&
           forward_speed > rotation_speed &&
           runtime.pitch > runtime.tuning.takeoff_pitch &&
           runtime.takeoff_armed &&
           runtime.grounded_time >= runtime.tuning.takeoff_ground_time {
            runtime.body.velocity.y = max_f32(runtime.body.velocity.y, runtime.tuning.takeoff_vertical_assist)
            runtime.grounded_time = 0
            runtime.takeoff_armed = false
        }
    } else {
        runtime.grounded_time = 0
    }
    runtime.propeller_turns +=
        dt * (runtime.tuning.propeller_base_rate + runtime.throttle * runtime.tuning.propeller_throttle_rate)
    sync_vehicle(runtime)
    result.crashed = runtime.crashed
    return result
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
        runtime.takeoff_armed = false
        runtime.last_landing = {
            outcome      = .Smooth,
            sink_speed   = max_f32(-vertical_speed_before, 0),
            weight_force = runtime.airframe.mass_kg * GRAVITY,
        }
        runtime.landing_feedback_seconds = 4
        if math.abs(bank_radians(runtime.body.basis)) > runtime.tuning.safe_bank_radians {
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

    if compression <= .001 && runtime.body.velocity.y > 0 && !runtime.takeoff_armed && !runtime.crashed {
        runtime.grounded = false
        runtime.gear_force = 0
        return {touched_down = touched_down, landing = landing}
    }
    if compression <= .001 && runtime.body.velocity.y > 0 && runtime.takeoff_armed {
        runtime.body.position.y = rest_height
        runtime.body.velocity.y = 0
    }

    runtime.grounded = true
    runtime.body.basis.up = {0, 1, 0}
    runtime.body.basis.forward.y = 0
    runtime.body.basis = flight.orthonormalize(runtime.body.basis)
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
    runtime.vehicle.yaw_radians = yaw_radians(runtime.body.basis)
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

rotate_ground_heading :: proc(basis: ^flight.Basis, radians: f32) {
    if basis == nil || radians == 0 do return
    c, s := math.cos(radians), math.sin(radians)
    forward := basis.forward
    basis.forward = {forward.x * c - forward.z * s, 0, forward.x * s + forward.z * c}
    basis.up = {0, 1, 0}
    basis^ = flight.orthonormalize(basis^)
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
