package libellula

import flight "../flight"
import third_person "zelda_engine:third_person"
import vehicles "../vehicles"
import "core:math"
import "core:math/linalg"

// Full TriRotorVisual geometry reaches 2.725 local metres below the frame
// origin. At Adriatic's .72 presentation scale, 1.98 keeps its skid pads clear.
GROUND_CLEARANCE :: f32(1.98)

Control :: struct {
    throttle_up, throttle_down: bool,
    pitch, roll, yaw:           f32,
}

Tuning :: struct {
    throttle_response:                     f32,
    climb_speed, descent_speed:            f32,
    vertical_speed_gain:                   f32,
    control_response, control_release:     f32,
    cyclic_scale, cyclic_expo, yaw_scale:  f32,
    maximum_tilt_radians:                  f32,
    attitude_gain, attitude_rate_gain:     f32,
    horizontal_damping:                    f32,
    ground_clearance, ground_friction:     f32,
    safe_touchdown_speed, safe_exit_speed: f32,
    rotor_idle_rate, rotor_full_rate:      f32,
}

Runtime :: struct {
    body:              flight.Body_State,
    vehicle:           vehicles.Vehicle,
    airframe:          flight.Tri_Rotor_Airframe,
    flight_runtime:    flight.Tri_Rotor_Runtime,
    telemetry:         flight.Tri_Rotor_Telemetry `fixture:"-"`,
    tuning:            Tuning,
    spawn_position:    flight.Vec3,
    spawn_orientation: quaternion128,
    throttle:          f32,
    pitch, roll, yaw:  f32,
    rotor_turns:       flight.Vec3,
    grounded:          bool,
    was_grounded:      bool,
    crashed:           bool,
    lift_active:       bool,
}

default_tuning :: proc() -> Tuning {
    return {
        throttle_response = 1.8,
        climb_speed = 3.5,
        descent_speed = 2.2,
        vertical_speed_gain = .065,
        control_response = 2.35,
        control_release = 4.6,
        cyclic_scale = .64,
        cyclic_expo = .55,
        yaw_scale = .7,
        maximum_tilt_radians = .28,
        attitude_gain = 1.5,
        attitude_rate_gain = .55,
        horizontal_damping = .55,
        ground_clearance = GROUND_CLEARANCE,
        ground_friction = 4.5,
        safe_touchdown_speed = 5,
        safe_exit_speed = 1.5,
        rotor_idle_rate = .35,
        rotor_full_rate = 6.5,
    }
}

new_runtime :: proc(spawn_position: flight.Vec3) -> Runtime {
    result := Runtime {
        airframe          = flight.libellula_airframe(),
        flight_runtime    = flight.default_tri_rotor_runtime(),
        tuning            = default_tuning(),
        spawn_position    = spawn_position,
        spawn_orientation = flight.orientation_from_forward_and_up({-1, 0, 0}, {0, 1, 0}),
    }
    // Product assistance owns pitch and roll attitude hold. The force model
    // still allocates the requested moments physically across all three rotors.
    result.flight_runtime.auto_level = false
    reset(&result, spawn_position.y - result.tuning.ground_clearance)
    return result
}

reset :: proc(runtime: ^Runtime, ground_height: f32) {
    if runtime == nil do return
    runtime.body = {
        position    = runtime.spawn_position,
        orientation = runtime.spawn_orientation,
    }
    runtime.body.position.y = ground_height + runtime.tuning.ground_clearance
    runtime.telemetry = {}
    runtime.throttle = 0
    runtime.pitch = 0
    runtime.roll = 0
    runtime.yaw = 0
    runtime.rotor_turns = {}
    runtime.grounded = true
    runtime.was_grounded = true
    runtime.crashed = false
    runtime.lift_active = false
    runtime.flight_runtime.ground_distance = 0
    sync_vehicle(runtime)
    runtime.vehicle.interaction_radius = 4.5
    runtime.vehicle.exit_distance = 2.8
}

step :: proc(runtime: ^Runtime, control: Control, ground_height, delta_seconds: f32, wind: flight.Vec3 = {}) {
    if runtime == nil || delta_seconds <= 0 do return
    dt := min_f32(delta_seconds, .05)
    if runtime.crashed {
        runtime.body.velocity *= max_f32(0, 1 - dt * 5)
        sync_vehicle(runtime)
        return
    }

    floor := ground_height + runtime.tuning.ground_clearance
    runtime.flight_runtime.ground_distance = max_f32(0, runtime.body.position.y - floor)
    if control.throttle_up do runtime.lift_active = true
    basis := flight.basis_from_orientation(runtime.body.orientation)

    throttle_target := f32(0)
    if runtime.lift_active {
        desired_vertical_speed := f32(0)
        if control.throttle_up && !control.throttle_down {
            desired_vertical_speed = runtime.tuning.climb_speed
        } else if control.throttle_down && !control.throttle_up {
            desired_vertical_speed = -runtime.tuning.descent_speed
        }
        upright := clamp(linalg.dot(basis.up, flight.Vec3{0, 1, 0}), .55, 1)
        ground_effect := f32(1)
        if runtime.flight_runtime.ground_distance < runtime.airframe.ground_effect_height {
            ground_effect +=
                runtime.airframe.ground_effect_bonus *
                (1 -
                        clamp(
                            runtime.flight_runtime.ground_distance /
                            max_f32(runtime.airframe.ground_effect_height, .01),
                            0,
                            1,
                        ))
        }
        hover_throttle :=
            runtime.airframe.mass_kg *
            9.81 /
            max_f32(runtime.airframe.maximum_collective_force * upright * ground_effect, 1)
        throttle_target =
            hover_throttle +
            (desired_vertical_speed - (runtime.body.velocity.y - wind.y)) * runtime.tuning.vertical_speed_gain
    }
    runtime.throttle = approach(runtime.throttle, clamp(throttle_target, 0, 1), runtime.tuning.throttle_response * dt)

    pitch_input := assisted_axis(control.pitch, 1, runtime.tuning.cyclic_expo)
    roll_input := assisted_axis(control.roll, 1, runtime.tuning.cyclic_expo)
    desired_pitch := pitch_input * runtime.tuning.maximum_tilt_radians
    desired_bank := -roll_input * runtime.tuning.maximum_tilt_radians
    current_pitch := math.asin(clamp(basis.forward.y, -1, 1))
    current_bank := bank_radians(basis)
    local_rate := flight.world_to_local(basis, runtime.body.angular_velocity_world)
    pitch_target := clamp(
        (desired_pitch - current_pitch) * runtime.tuning.attitude_gain -
        local_rate.x * runtime.tuning.attitude_rate_gain,
        -runtime.tuning.cyclic_scale,
        runtime.tuning.cyclic_scale,
    )
    // Positive local roll torque produces negative bank in this coordinate
    // system, hence the reversed attitude error.
    roll_target := clamp(
        (current_bank - desired_bank) * runtime.tuning.attitude_gain -
        local_rate.z * runtime.tuning.attitude_rate_gain,
        -runtime.tuning.cyclic_scale,
        runtime.tuning.cyclic_scale,
    )
    yaw_target := clamp(control.yaw, -1, 1) * runtime.tuning.yaw_scale
    runtime.pitch = slew(runtime.pitch, pitch_target, runtime.tuning, dt)
    runtime.roll = slew(runtime.roll, roll_target, runtime.tuning, dt)
    runtime.yaw = slew(runtime.yaw, yaw_target, runtime.tuning, dt)

    runtime.was_grounded = runtime.grounded
    vertical_before := runtime.body.velocity.y
    runtime.telemetry = flight.step_tri_rotor(
        &runtime.body,
        {throttle = runtime.throttle, pitch = runtime.pitch, roll = runtime.roll, yaw = runtime.yaw},
        runtime.airframe,
        runtime.flight_runtime,
        dt,
    )

    cyclic_release := 1 - max_f32(math.abs(pitch_input), math.abs(roll_input))
    horizontal_damping := clamp(runtime.tuning.horizontal_damping * cyclic_release * dt, 0, 1)
    // Rotor drag damps air-relative motion, so a sustained front advects the
    // lighter Libellula instead of behaving as camera-only shake.
    runtime.body.velocity.x -= (runtime.body.velocity.x - wind.x) * horizontal_damping
    runtime.body.velocity.z -= (runtime.body.velocity.z - wind.z) * horizontal_damping

    runtime.grounded = runtime.body.position.y <= floor
    if runtime.grounded {
        touched_down := !runtime.was_grounded
        if touched_down && -vertical_before > runtime.tuning.safe_touchdown_speed {
            runtime.crashed = true
        }
        runtime.body.position.y = floor
        if runtime.body.velocity.y < 0 do runtime.body.velocity.y = 0
        horizontal := flight.Vec3{runtime.body.velocity.x, 0, runtime.body.velocity.z}
        horizontal *= max_f32(0, 1 - runtime.tuning.ground_friction * dt)
        runtime.body.velocity.x = horizontal.x
        runtime.body.velocity.z = horizontal.z
        runtime.body.angular_velocity_world.x = 0
        runtime.body.angular_velocity_world.z = 0
        runtime.body.orientation = flight.level_preserving_heading(runtime.body.orientation)
        if !control.throttle_up {
            runtime.lift_active = false
        }
    }

    rpm := runtime.telemetry.rotor_rpm_normalized
    runtime.rotor_turns.x += dt * (runtime.tuning.rotor_idle_rate + rpm.x * runtime.tuning.rotor_full_rate)
    runtime.rotor_turns.y += dt * (runtime.tuning.rotor_idle_rate + rpm.y * runtime.tuning.rotor_full_rate)
    runtime.rotor_turns.z += dt * (runtime.tuning.rotor_idle_rate + rpm.z * runtime.tuning.rotor_full_rate)
    sync_vehicle(runtime)
}

can_exit :: proc(runtime: ^Runtime) -> bool {
    return(
        runtime != nil &&
        runtime.grounded &&
        !runtime.crashed &&
        linalg.length(runtime.body.velocity) < runtime.tuning.safe_exit_speed \
    )
}

sync_vehicle :: proc(runtime: ^Runtime) {
    if runtime == nil do return
    runtime.vehicle.position = to_third_person(runtime.body.position)
    runtime.vehicle.yaw_radians = yaw_radians(flight.basis_from_orientation(runtime.body.orientation))
}

to_third_person :: proc(value: flight.Vec3) -> third_person.Vec3 {
    return {value.x, value.y, value.z}
}

yaw_radians :: proc(basis: flight.Basis) -> f32 {
    return math.atan2(-basis.forward.x, -basis.forward.z)
}

bank_radians :: proc(basis: flight.Basis) -> f32 {
    return math.atan2(linalg.dot(basis.right, flight.Vec3{0, 1, 0}), linalg.dot(basis.up, flight.Vec3{0, 1, 0}))
}

slew :: proc(value, target: f32, tuning: Tuning, delta_seconds: f32) -> f32 {
    rate := tuning.control_response
    if math.abs(target) < math.abs(value) do rate = tuning.control_release
    if value < target do return min_f32(value + rate * delta_seconds, target)
    return max_f32(value - rate * delta_seconds, target)
}

assisted_axis :: proc(value, scale, expo: f32) -> f32 {
    x := clamp(value, -1, 1)
    shaped := x * (1 - expo) + x * x * x * expo
    return shaped * scale
}

approach :: proc(value, target, maximum_delta: f32) -> f32 {
    if value < target do return min_f32(value + maximum_delta, target)
    return max_f32(value - maximum_delta, target)
}

clamp :: proc(value, low, high: f32) -> f32 {
    if value < low do return low
    if value > high do return high
    return value
}

min_f32 :: proc(a, b: f32) -> f32 { if a < b do return a; return b }
max_f32 :: proc(a, b: f32) -> f32 { if a > b do return a; return b }
