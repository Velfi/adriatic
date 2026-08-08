package flight

import "core:math"
import "core:math/linalg"

// Asteria TR-3 Libellula's fixed triangular rotor frame.  Rotor force is
// allocated physically at the mounts; a failed or saturated rotor is never
// replaced by invisible attitude torque.
Tri_Rotor_Airframe :: struct {
    mass_kg, maximum_gross_mass_kg:                                                            f32,
    maximum_collective_force, attitude_torque, yaw_torque, leveling_strength, angular_damping: f32,
    maximum_tilt_angle:                                                                        f32,
    ground_effect_height, ground_effect_bonus, safe_landing_speed:                             f32,
}

Tri_Rotor_Runtime :: struct {
    left_engine_output, right_engine_output, rear_engine_output: f32,
    auto_level:                                                  bool,
    ground_distance:                                             f32,
}
Tri_Rotor_Solution :: struct {
    thrusts:                                 Vec3,
    total_thrust, pitch_moment, roll_moment: f32,
}
Tri_Rotor_Telemetry :: struct {
    rotor_thrusts, rotor_rpm_normalized: Vec3,
    total_thrust:                        f32,
}

tri_rotor_left_mount :: Vec3{-3.2, 1.17, -1}
tri_rotor_right_mount :: Vec3{3.2, 1.17, -1}
tri_rotor_rear_mount :: Vec3{0, 1.17, 4.5425625}

libellula_airframe :: proc() -> Tri_Rotor_Airframe {
    return {
        mass_kg = 1180,
        maximum_gross_mass_kg = 1780,
        maximum_collective_force = 23500,
        attitude_torque = 42000,
        yaw_torque = 19000,
        leveling_strength = 26000,
        angular_damping = 8500,
        maximum_tilt_angle = .55,
        ground_effect_height = 5.5,
        ground_effect_bonus = .14,
        safe_landing_speed = 5,
    }
}

default_tri_rotor_runtime :: proc() -> Tri_Rotor_Runtime {return {
        left_engine_output = 1,
        right_engine_output = 1,
        rear_engine_output = 1,
        auto_level = true,
        ground_distance = 999999,
    }}

solve_tri_rotor :: proc(
    total_thrust, pitch_moment, roll_moment: f32,
    center_of_mass, maximum_forces: Vec3,
) -> Tri_Rotor_Solution {
    // Solve the three equations directly: collective, pitch, and roll. The rotor
    // triangle is symmetric so the resulting coefficients remain easy to audit.
    left := tri_rotor_left_mount - center_of_mass
    right := tri_rotor_right_mount - center_of_mass
    rear := tri_rotor_rear_mount - center_of_mass
    a11, a12, a13 := f32(1), f32(1), f32(1)
    a21, a22, a23 := -left.z, -right.z, -rear.z
    a31, a32, a33 := left.x, right.x, rear.x
    det := a11 * (a22 * a33 - a23 * a32) - a12 * (a21 * a33 - a23 * a31) + a13 * (a21 * a32 - a22 * a31)
    if math.abs(det) < .0001 do return {}
    b1, b2, b3 := max_f32(0, total_thrust), pitch_moment, roll_moment
    l := (b1 * (a22 * a33 - a23 * a32) - a12 * (b2 * a33 - a23 * b3) + a13 * (b2 * a32 - a22 * b3)) / det
    r := (a11 * (b2 * a33 - a23 * b3) - b1 * (a21 * a33 - a23 * a31) + a13 * (a21 * b3 - b2 * a31)) / det
    re := (a11 * (a22 * b3 - b2 * a32) - a12 * (a21 * b3 - b2 * a31) + b1 * (a21 * a32 - a22 * a31)) / det
    forces := Vec3 {
        clamp(l, 0, max_f32(0, maximum_forces.x)),
        clamp(r, 0, max_f32(0, maximum_forces.y)),
        clamp(re, 0, max_f32(0, maximum_forces.z)),
    }
    return {
        thrusts = forces,
        total_thrust = forces.x + forces.y + forces.z,
        pitch_moment = -left.z * forces.x - right.z * forces.y - rear.z * forces.z,
        roll_moment = left.x * forces.x + right.x * forces.y + rear.x * forces.z,
    }
}

vtol_yaw_reaction :: proc(yaw_input, local_yaw_rate, damping_scale, authority, yaw_torque: f32) -> f32 {return(
        (-yaw_input * yaw_torque - local_yaw_rate * damping_scale) *
        authority \
    )}

step_tri_rotor :: proc(
    state: ^Body_State,
    command_input: Control_Command,
    airframe: Tri_Rotor_Airframe,
    runtime: Tri_Rotor_Runtime,
    delta_seconds: f32,
) -> Tri_Rotor_Telemetry {
    if state == nil || delta_seconds <= 0 do return {}
    command :=
        command_input; command.pitch = clamp(command.pitch, -1, 1); command.roll = clamp(command.roll, -1, 1); command.yaw = clamp(command.yaw, -1, 1); command.throttle = clamp(command.throttle, 0, 1)
    state.orientation = normalize_orientation(state.orientation)
    basis := basis_from_orientation(state.orientation)
    mass := max_f32(airframe.mass_kg, 1)
    caps :=
        Vec3 {
            clamp(runtime.left_engine_output, 0, 1),
            clamp(runtime.right_engine_output, 0, 1),
            clamp(runtime.rear_engine_output, 0, 1),
        } *
        (airframe.maximum_collective_force / 3)
    collective :=
        command.throttle *
        (caps.x +
                caps.y +
                caps.z); local_rate := world_to_local(basis, state.angular_velocity_world); authority := clamp(collective / (mass * 9.81), .62, 1)
    level_axis := linalg.cross(
        basis.up,
        Vec3{0, 1, 0},
    ); local_level := world_to_local(basis, level_axis); damping := airframe.angular_damping
    pitch_moment, roll_moment: f32
    if runtime.auto_level {
        // Assisted cyclic commands a bounded lean angle rather than a raw
        // torque. The airframe holds the requested tilt to translate and
        // returns to level when released, so forward flight can no longer
        // integrate into an ever-increasing pitch rate that flips the craft.
        leveling := airframe.leveling_strength * 2.5
        max_tilt := math.sin(airframe.maximum_tilt_angle)
        target_pitch_level := -command.pitch * max_tilt
        target_roll_level := -command.roll * max_tilt
        pitch_moment = (local_level.x - target_pitch_level) * leveling - local_rate.x * damping
        roll_moment = (local_level.z - target_roll_level) * leveling - local_rate.z * damping
    } else {
        pitch_moment = command.pitch * airframe.attitude_torque - local_rate.x * damping
        roll_moment = command.roll * airframe.attitude_torque - local_rate.z * damping
    }
    solution := solve_tri_rotor(
        collective,
        pitch_moment * authority,
        roll_moment * authority,
        {},
        caps,
    ); ground_bonus := f32(0); if runtime.ground_distance < airframe.ground_effect_height do ground_bonus = airframe.ground_effect_bonus * (1 - clamp(runtime.ground_distance / max_f32(airframe.ground_effect_height, .01), 0, 1))
    up_force := basis.up * (solution.total_thrust * (1 + ground_bonus))
    total := up_force + {0, -9.81 * mass, 0}
    state.velocity += total * (delta_seconds / mass)
    state.position += state.velocity * delta_seconds
    yaw_damping := damping; if runtime.auto_level do yaw_damping *= 1.4
    yaw := vtol_yaw_reaction(
        command.yaw,
        local_rate.y,
        yaw_damping,
        authority,
        airframe.yaw_torque,
    ); torque_local := Vec3{solution.pitch_moment, yaw, solution.roll_moment}; state.angular_velocity_world += local_to_world(basis, torque_local) * (delta_seconds / (mass * 12)); state.orientation = integrate_orientation(state.orientation, state.angular_velocity_world, delta_seconds)
    per_rotor := airframe.maximum_collective_force / 3
    return {
        rotor_thrusts = solution.thrusts,
        rotor_rpm_normalized = Vec3 {
            math.sqrt(solution.thrusts.x / per_rotor),
            math.sqrt(solution.thrusts.y / per_rotor),
            math.sqrt(solution.thrusts.z / per_rotor),
        },
        total_thrust = solution.total_thrust,
    }
}
