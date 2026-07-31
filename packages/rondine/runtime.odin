package rondine

import flight "../flight"
import third_person "../third_person"
import vehicles "../vehicles"
import "core:math"
import "core:math/linalg"

GROUND_CLEARANCE :: f32(1.05)
TARGET_SKIM_HEIGHT :: f32(3)
MAX_WAKE_SAMPLES :: 96

Control :: struct {
    throttle_up, throttle_down: bool,
    pitch, roll, yaw:           f32,
}

Tuning :: struct {
    thrust_acceleration: f32,
    maximum_speed:       f32,
    cruise_speed:        f32,
    takeoff_speed:       f32,
    throttle_up_rate:    f32,
    throttle_down_rate:  f32,
    turn_rate:           f32,
    yaw_rate:            f32,
    lateral_grip:        f32,
    height_gain:         f32,
    height_damping:      f32,
}

Telemetry :: struct {
    speed:            f32,
    forward_speed:    f32,
    lateral_speed:    f32,
    acceleration:     f32,
    surge_intensity:  f32,
    brake_intensity:  f32,
    drift_transition: f32,
    slip:             f32,
    drift_intensity:  f32,
    countersteer:     f32,
    drift_kick:       f32,
    hookup_kick:      f32,
    surface_impact:   f32,
    surface_release:  f32,
    turn_rate:        f32,
    height:           f32,
    wake_intensity:   f32,
    spray_intensity:  f32,
}

Wake_Sample :: struct {
    serial:        u32,
    position:      flight.Vec3,
    forward:       flight.Vec3,
    right:         flight.Vec3,
    age, lifetime: f32,
    strength:      f32,
    slip:          f32,
    turn:          f32,
    countersteer:  f32,
    kick:          f32,
    hookup:        f32,
    impact:        f32,
    release:       f32,
    transition:    f32,
}

Runtime :: struct {
    body:                    flight.Body_State,
    vehicle:                 vehicles.Vehicle,
    tuning:                  Tuning,
    telemetry:               Telemetry,
    spawn_position:          flight.Vec3,
    spawn_basis:             flight.Basis,
    throttle:                f32,
    propeller_turns:         f32,
    steering:                f32,
    target_height:           f32,
    grounded:                bool,
    crashed:                 bool,
    wake:                    [MAX_WAKE_SAMPLES]Wake_Sample,
    wake_count:              int,
    wake_distance:           f32,
    wake_serial:             u32,
    drift_kick:              f32,
    hookup_kick:             f32,
    surface_impact:          f32,
    surface_release:         f32,
    surge_intensity:         f32,
    brake_intensity:         f32,
    drift_transition:        f32,
    slip_side:               f32,
    kick_marker_armed:       bool,
    impact_marker_armed:     bool,
    release_marker_armed:    bool,
    transition_marker_armed: bool,
}

default_tuning :: proc() -> Tuning {
    return {
        thrust_acceleration = 17,
        maximum_speed = 90,
        cruise_speed = 75,
        takeoff_speed = 25,
        throttle_up_rate = .55,
        throttle_down_rate = .85,
        turn_rate = .34,
        yaw_rate = .25,
        lateral_grip = .72,
        height_gain = 5.4,
        height_damping = 3.2,
    }
}

new_runtime :: proc(spawn_position: flight.Vec3) -> Runtime {
    result := Runtime {
        tuning = default_tuning(),
        spawn_position = spawn_position,
        spawn_basis = {forward = {-1, 0, 0}, up = {0, 1, 0}, right = {0, 0, -1}},
        target_height = TARGET_SKIM_HEIGHT,
    }
    reset(&result, spawn_position.y - GROUND_CLEARANCE)
    return result
}

reset :: proc(runtime: ^Runtime, sea_level: f32) {
    if runtime == nil do return
    runtime.body = {
        position    = runtime.spawn_position,
        orientation = flight.orientation_from_basis(runtime.spawn_basis),
    }
    runtime.body.position.y = sea_level + GROUND_CLEARANCE
    runtime.body.velocity = {}
    runtime.body.angular_velocity_world = {}
    runtime.throttle = 0
    runtime.propeller_turns = 0
    runtime.steering = 0
    runtime.target_height = TARGET_SKIM_HEIGHT
    runtime.telemetry = {}
    runtime.grounded = true
    runtime.crashed = false
    runtime.wake_count = 0
    runtime.wake_distance = 0
    runtime.wake_serial = 0
    runtime.drift_kick = 0
    runtime.hookup_kick = 0
    runtime.surface_impact = 0
    runtime.surface_release = 0
    runtime.surge_intensity = 0
    runtime.brake_intensity = 0
    runtime.drift_transition = 0
    runtime.slip_side = 0
    runtime.kick_marker_armed = true
    runtime.impact_marker_armed = true
    runtime.release_marker_armed = true
    runtime.transition_marker_armed = false
    sync_vehicle(runtime)
    runtime.vehicle.interaction_radius = 5.5
    runtime.vehicle.exit_distance = 3.4
}

step :: proc(runtime: ^Runtime, control: Control, sea_level, delta_seconds: f32, wind: flight.Vec3 = {}) {
    if runtime == nil || delta_seconds <= 0 do return
    dt := min(delta_seconds, f32(.05))
    previous_drift_intensity := runtime.telemetry.drift_intensity
    previous_slip_side := runtime.slip_side
    previous_forward_speed := runtime.telemetry.forward_speed
    was_grounded := runtime.grounded
    step_wake(runtime, dt)
    if runtime.crashed {
        runtime.body.velocity *= max(f32(0), 1 - dt * 3)
        sync_vehicle(runtime)
        return
    }

    if control.throttle_up do runtime.throttle += runtime.tuning.throttle_up_rate * dt
    if control.throttle_down do runtime.throttle -= runtime.tuning.throttle_down_rate * dt
    runtime.throttle = clamp(runtime.throttle, 0, 1)
    runtime.propeller_turns = math.mod(
        runtime.propeller_turns + runtime.throttle * (4 + runtime.throttle * 18) * dt,
        f32(1),
    )
    runtime.steering = approach(runtime.steering, clamp(control.roll + control.yaw * .35, -1, 1), dt * 2.8)
    runtime.target_height = clamp(runtime.target_height - control.pitch * dt * 2.4, f32(1.5), f32(6))

    basis := flight.basis_from_orientation(runtime.body.orientation)
    forward := basis.forward
    right := basis.right
    air_velocity := runtime.body.velocity - wind
    forward_speed := linalg.dot(air_velocity, forward)
    lateral_speed := linalg.dot(air_velocity, right)
    speed_fraction := clamp(math.abs(forward_speed) / runtime.tuning.maximum_speed, 0, 1)
    turn_authority := clamp((math.abs(forward_speed) - 6) / 24, 0, 1) * (1 - speed_fraction * .45)
    surface_fraction := clamp(1 - (runtime.body.position.y - sea_level - GROUND_CLEARANCE) / 1.8, 0, 1)
    drift_input :=
        clamp((math.abs(runtime.steering) - .38) / .62, 0, 1) *
        clamp((math.abs(forward_speed) - 15) / 28, 0, 1) *
        surface_fraction
    // Positive roll/yaw input is pilot-right. The Rondine basis has right =
    // cross(forward, up), so a right turn is a negative world-yaw rotation.
    yaw_delta := -runtime.steering * runtime.tuning.turn_rate * turn_authority * (1 + drift_input * .7) * dt
    runtime.body.orientation = flight.rotate_level_heading(runtime.body.orientation, yaw_delta)
    basis = flight.basis_from_orientation(runtime.body.orientation)
    forward = basis.forward
    right = basis.right

    thrust := runtime.throttle * runtime.tuning.thrust_acceleration
    overspeed := clamp(
        (math.abs(forward_speed) - runtime.tuning.cruise_speed) /
        max(runtime.tuning.maximum_speed - runtime.tuning.cruise_speed, f32(1)),
        0,
        1,
    )
    thrust *= 1 - overspeed * .94
    runtime.body.velocity += forward * (thrust * dt)
    drift_grip := runtime.tuning.lateral_grip * (1 - drift_input * .78)
    runtime.body.velocity -= right * (lateral_speed * drift_grip * dt)
    runtime.body.velocity += right * (runtime.steering * drift_input * math.abs(forward_speed) * .19 * dt)
    // The Rondine is deliberately less wind-responsive than the rotorcraft;
    // broad fronts move it gradually while its surface handling stays heavy.
    wind_response := clamp(dt * .22, 0, 1)
    runtime.body.velocity.x += wind.x * wind_response
    runtime.body.velocity.z += wind.z * wind_response
    runtime.body.velocity.y += wind.y * dt * .18
    runtime.body.velocity *= max(f32(0), 1 - (.012 + speed_fraction * speed_fraction * .018) * dt)

    current_speed := linalg.length(runtime.body.velocity)
    if current_speed > runtime.tuning.maximum_speed {
        runtime.body.velocity *= runtime.tuning.maximum_speed / current_speed
    }

    height := runtime.body.position.y - sea_level - GROUND_CLEARANCE
    airborne_fraction := clamp((math.abs(forward_speed) - runtime.tuning.takeoff_speed) / 12, 0, 1)
    desired_height := runtime.target_height * airborne_fraction
    vertical_acceleration :=
        (desired_height - height) * runtime.tuning.height_gain -
        runtime.body.velocity.y * runtime.tuning.height_damping
    runtime.body.velocity.y += vertical_acceleration * dt
    runtime.body.position += runtime.body.velocity * dt
    floor := sea_level + GROUND_CLEARANCE
    landing_impact := f32(0)
    liftoff_release := f32(0)
    if runtime.body.position.y <= floor {
        if !was_grounded {
            downward_speed := max(-runtime.body.velocity.y, f32(0))
            landing_impact = clamp((downward_speed - .35) / 3.4, 0, 1)
        }
        runtime.body.position.y = floor
        runtime.body.velocity.y = max(runtime.body.velocity.y, f32(0))
        runtime.grounded = true
        runtime.release_marker_armed = true
        runtime.body.velocity.x *= max(f32(0), 1 - dt * (control.throttle_down ? f32(1.8) : f32(.18)))
        runtime.body.velocity.z *= max(f32(0), 1 - dt * (control.throttle_down ? f32(1.8) : f32(.18)))
    } else {
        runtime.grounded = false
        runtime.impact_marker_armed = true
        if was_grounded {
            liftoff_release = clamp(
                .48 +
                max(runtime.body.velocity.y, f32(0)) * .24 +
                clamp((math.abs(forward_speed) - runtime.tuning.takeoff_speed) / 20, 0, 1) * .30,
                0,
                1,
            )
        }
    }

    forward_speed = linalg.dot(runtime.body.velocity, basis.forward)
    lateral_speed = linalg.dot(runtime.body.velocity, basis.right)
    longitudinal_acceleration := (forward_speed - previous_forward_speed) / dt
    surge_target :=
        clamp((longitudinal_acceleration - 1.2) / 6.8, 0, 1) *
        clamp((math.abs(forward_speed) - 7) / 18, 0, 1) *
        surface_fraction
    runtime.surge_intensity = max(runtime.surge_intensity * max(f32(0), 1 - dt * 4.2), surge_target)
    brake_target :=
        clamp((-longitudinal_acceleration - 1.0) / 7.5, 0, 1) *
        clamp((math.abs(forward_speed) - 12) / 24, 0, 1) *
        surface_fraction *
        (control.throttle_down ? f32(1) : f32(.45))
    runtime.brake_intensity = max(runtime.brake_intensity * max(f32(0), 1 - dt * 4.8), brake_target)
    slip := clamp(lateral_speed / max(math.abs(forward_speed), f32(8)), -1, 1)
    drift_intensity := clamp(math.abs(slip) * 2.8 + drift_input * .45, 0, 1) * surface_fraction
    if math.abs(slip) > .035 do runtime.slip_side = math.sign(slip)
    transition_target := f32(0)
    if previous_slip_side != 0 &&
       runtime.slip_side != previous_slip_side &&
       max(previous_drift_intensity, drift_intensity) > .2 &&
       surface_fraction > .4 {
        transition_target = clamp(.58 + max(previous_drift_intensity, drift_intensity) * .42, 0, 1)
        runtime.transition_marker_armed = true
    }
    runtime.drift_transition = max(runtime.drift_transition * max(f32(0), 1 - dt * 2.8), transition_target)
    countersteer := clamp(runtime.steering * slip * 4.2, 0, 1) * drift_intensity
    drift_rise_rate := max(f32(0), drift_intensity - previous_drift_intensity) / dt
    drift_fall_rate := max(f32(0), previous_drift_intensity - drift_intensity) / dt
    drift_kick_target := clamp((drift_rise_rate - .25) / 2.75, 0, 1)
    hookup_kick_target := f32(0)
    if previous_drift_intensity > .3 && surface_fraction > .4 && math.abs(runtime.steering) < .8 {
        hookup_kick_target = clamp((drift_fall_rate - .18) / 2.35, 0, 1)
    }
    runtime.drift_kick = max(runtime.drift_kick * max(f32(0), 1 - dt * 2.2), drift_kick_target)
    runtime.hookup_kick = max(runtime.hookup_kick * max(f32(0), 1 - dt * 3.0), hookup_kick_target)
    runtime.surface_impact = max(runtime.surface_impact * max(f32(0), 1 - dt * 3.6), landing_impact)
    runtime.surface_release = max(runtime.surface_release * max(f32(0), 1 - dt * 3.2), liftoff_release)
    if surface_fraction <= .1 {
        runtime.drift_kick = 0
        runtime.hookup_kick = 0
        runtime.drift_transition = 0
        runtime.slip_side = 0
    }
    if drift_intensity < .18 do runtime.kick_marker_armed = true
    runtime.body.angular_velocity_world = {0, yaw_delta / dt, 0}
    runtime.telemetry = {
        speed            = linalg.length(runtime.body.velocity),
        forward_speed    = forward_speed,
        lateral_speed    = lateral_speed,
        acceleration     = longitudinal_acceleration,
        surge_intensity  = runtime.surge_intensity,
        brake_intensity  = runtime.brake_intensity,
        drift_transition = runtime.drift_transition,
        slip             = slip,
        drift_intensity  = drift_intensity,
        countersteer     = countersteer,
        drift_kick       = runtime.drift_kick,
        hookup_kick      = runtime.hookup_kick,
        surface_impact   = runtime.surface_impact,
        surface_release  = runtime.surface_release,
        turn_rate        = runtime.body.angular_velocity_world.y,
        height           = max(f32(0), runtime.body.position.y - sea_level - GROUND_CLEARANCE),
        wake_intensity   = clamp(
            (math.abs(forward_speed) - 12) / 48 + drift_intensity * .42,
            0,
            1,
        ) * clamp(1 - height / 8, 0, 1),
        spray_intensity  = clamp(
            (math.abs(forward_speed) - 4) / 28,
            0,
            1,
        ) * clamp(1 - height / 1.6, 0, 1) * (1 + drift_intensity * .75),
    }
    maybe_spawn_wake(runtime, dt)
    sync_vehicle(runtime)
}

can_exit :: proc(runtime: ^Runtime) -> bool {
    return runtime != nil && !runtime.crashed && runtime.telemetry.speed <= 1.5
}

crash :: proc(runtime: ^Runtime) {
    if runtime != nil do runtime.crashed = true
}

maybe_spawn_wake :: proc(runtime: ^Runtime, dt: f32) {
    strength := runtime.telemetry.wake_intensity
    if strength <= .02 do return
    runtime.wake_distance += runtime.telemetry.speed * dt
    spacing := f32(1.25)
    if runtime.wake_distance < spacing do return
    horizontal_speed := f32(
        math.sqrt(
            f64(runtime.body.velocity.x * runtime.body.velocity.x + runtime.body.velocity.z * runtime.body.velocity.z),
        ),
    )
    basis := flight.basis_from_orientation(runtime.body.orientation)
    travel_direction := basis.forward
    if horizontal_speed > .01 {
        travel_direction = {runtime.body.velocity.x / horizontal_speed, 0, runtime.body.velocity.z / horizontal_speed}
    }
    for runtime.wake_distance >= spacing {
        // Place catch-up samples back along this frame's travelled segment.
        // This keeps the strip spatially uniform after a slow frame instead
        // of stacking several samples at the current body position.
        overshoot := runtime.wake_distance - spacing
        position := runtime.body.position - travel_direction * overshoot
        runtime.wake_distance -= spacing
        if runtime.wake_count >= MAX_WAKE_SAMPLES {
            for index in 1 ..< runtime.wake_count do runtime.wake[index - 1] = runtime.wake[index]
            runtime.wake_count -= 1
        }
        runtime.wake_serial += 1
        kick_marker := f32(0)
        if runtime.kick_marker_armed && runtime.telemetry.drift_intensity > .3 && runtime.telemetry.drift_kick > .45 {
            kick_marker = runtime.telemetry.drift_kick
            runtime.kick_marker_armed = false
        }
        impact_marker := f32(0)
        if runtime.impact_marker_armed && runtime.grounded && runtime.telemetry.surface_impact > .2 {
            impact_marker = runtime.telemetry.surface_impact
            runtime.impact_marker_armed = false
        }
        release_marker := f32(0)
        if runtime.release_marker_armed && !runtime.grounded && runtime.telemetry.surface_release > .2 {
            release_marker = runtime.telemetry.surface_release
            runtime.release_marker_armed = false
        }
        transition_marker := f32(0)
        if runtime.transition_marker_armed && runtime.telemetry.drift_transition > .45 {
            transition_marker = runtime.telemetry.drift_transition
            runtime.transition_marker_armed = false
        }
        lifetime := clamp(
            1.15 +
            strength * .85 +
            math.abs(runtime.telemetry.slip) * .9 +
            runtime.telemetry.countersteer * .22 +
            kick_marker * .45 +
            runtime.telemetry.hookup_kick * .28 +
            impact_marker * .42 +
            release_marker * .38 +
            transition_marker * .36,
            1.2,
            2.75,
        )
        runtime.wake[runtime.wake_count] = {
            serial       = runtime.wake_serial,
            position     = position,
            forward      = basis.forward,
            right        = basis.right,
            lifetime     = lifetime,
            strength     = strength,
            slip         = runtime.telemetry.slip,
            turn         = clamp(runtime.steering, -1, 1),
            countersteer = runtime.telemetry.countersteer,
            kick         = kick_marker,
            hookup       = runtime.telemetry.hookup_kick,
            impact       = impact_marker,
            release      = release_marker,
            transition   = transition_marker,
        }
        runtime.wake_count += 1
    }
}

step_wake :: proc(runtime: ^Runtime, dt: f32) {
    write := 0
    for read in 0 ..< runtime.wake_count {
        sample := runtime.wake[read]
        sample.age += dt
        if sample.age >= sample.lifetime do continue
        if write != read do runtime.wake[write] = sample
        else do runtime.wake[write] = sample
        write += 1
    }
    runtime.wake_count = write
}

sync_vehicle :: proc(runtime: ^Runtime) {
    runtime.vehicle.position = {runtime.body.position.x, runtime.body.position.y, runtime.body.position.z}
    basis := flight.basis_from_orientation(runtime.body.orientation)
    runtime.vehicle.yaw_radians = math.atan2(-basis.forward.z, -basis.forward.x)
}

approach :: proc(value, target, amount: f32) -> f32 {
    if value < target do return min(value + amount, target)
    return max(value - amount, target)
}
