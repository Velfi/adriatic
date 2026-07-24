package flight

import "core:math"

// Product-owned airframe tuning. Units: kg, m, seconds, Newtons, and degrees.
Airframe :: struct {
    // `fixed_wing_layout` and `tri_rotor_vtol_layout` select the applicable
    // integrator. The airframe remains product-owned tuning, not engine policy.
    flight_layout:                                                                                                                       u8,
    mass_kg, maximum_gross_mass_kg:                                                                                                      f32,
    wing_area, lift_scale, drag_scale:                                                                                                   f32,
    stall_speed, maximum_speed:                                                                                                          f32,
    rated_power_per_engine_kw, propeller_efficiency, static_thrust_per_engine, engine_count:                                             f32,
    wing_incidence_degrees, lift_curve_slope_per_degree, zero_lift_angle_degrees:                                                        f32,
    critical_angle_degrees, negative_critical_angle_degrees, post_stall_angle_degrees, post_stall_lift_coefficient, induced_drag_factor: f32,
    trim_angle_of_attack_degrees, pitch_stability, pitch_damping, roll_stability, roll_damping, yaw_stability, yaw_damping:              f32,
    pitch_control_scale, roll_control_scale, yaw_control_scale:                                                                          f32,
    water_capable:                                                                                                                       bool,
    water_planing_start_speed, water_planing_full_speed, water_planing_reference_speed, water_plow_drag_scale:                           f32,
}

fixed_wing_layout :: u8(0)
tri_rotor_vtol_layout :: u8(1)

Control_Command :: struct {
    pitch, roll, yaw, throttle: f32,
    flap_setting:               int,
}
Runtime :: struct {
    engine_output, control_authority, drag_multiplier, stall_speed_modifier: f32,
    controls_damaged:                                                        bool,
}
Body_State :: struct {
    position, velocity, angular_velocity: Vec3,
    basis:                                Basis,
}
Telemetry :: struct {
    airspeed, angle_of_attack_degrees, effective_stall_speed, lift_coefficient: f32,
    is_stalling:                                                                bool,
}
Forces :: struct {
    lift, parasitic_drag, induced_drag, lateral_drag: Vec3,
}

default_airframe :: proc() -> Airframe {
    return {
        mass_kg = 4200,
        maximum_gross_mass_kg = 6200,
        wing_area = 42,
        lift_scale = 1,
        drag_scale = 1,
        stall_speed = 30.3,
        maximum_speed = 70,
        rated_power_per_engine_kw = 400,
        propeller_efficiency = .78,
        static_thrust_per_engine = 10500,
        engine_count = 2,
        lift_curve_slope_per_degree = .095,
        zero_lift_angle_degrees = -1.25,
        critical_angle_degrees = 17,
        negative_critical_angle_degrees = -15,
        post_stall_angle_degrees = 32,
        post_stall_lift_coefficient = .55,
        induced_drag_factor = .045,
        trim_angle_of_attack_degrees = 8,
        pitch_stability = 100000,
        pitch_damping = 18000,
        roll_stability = 22000,
        roll_damping = 12000,
        yaw_stability = 85000,
        yaw_damping = 11000,
        pitch_control_scale = 1,
        roll_control_scale = 1,
        yaw_control_scale = 1,
    }
}

// Asteria PA-2 Postale: a short-field mailplane with transport-scale damping.
postale_airframe :: proc() -> Airframe {
    return {
        flight_layout = fixed_wing_layout,
        mass_kg = 2400,
        maximum_gross_mass_kg = 3800,
        wing_area = 42,
        lift_scale = 1.45,
        drag_scale = 1,
        stall_speed = 24,
        maximum_speed = 70,
        rated_power_per_engine_kw = 560,
        propeller_efficiency = .78,
        static_thrust_per_engine = 14500,
        engine_count = 1,
        wing_incidence_degrees = 4,
        lift_curve_slope_per_degree = .095,
        zero_lift_angle_degrees = -1.25,
        critical_angle_degrees = 17,
        negative_critical_angle_degrees = -15,
        post_stall_angle_degrees = 32,
        post_stall_lift_coefficient = .55,
        induced_drag_factor = .045,
        trim_angle_of_attack_degrees = 8,
        pitch_stability = 145000,
        pitch_damping = 27500,
        roll_stability = 24000,
        roll_damping = 14500,
        yaw_stability = 82000,
        yaw_damping = 10500,
        pitch_control_scale = .95,
        roll_control_scale = 1.05,
        yaw_control_scale = .55,
    }
}

// Asteria UC-4 Pelican: the twin-engine flying boat retains its water tuning
// alongside the normal fixed-wing values so callers can hand it to water physics.
pelican_airframe :: proc() -> Airframe {
    return {
        flight_layout = fixed_wing_layout,
        mass_kg = 2850,
        maximum_gross_mass_kg = 4300,
        wing_area = 42,
        lift_scale = 1.38,
        drag_scale = 1,
        stall_speed = 25.8,
        maximum_speed = 70,
        rated_power_per_engine_kw = 400,
        propeller_efficiency = .78,
        static_thrust_per_engine = 10500,
        engine_count = 2,
        wing_incidence_degrees = 3,
        lift_curve_slope_per_degree = .095,
        zero_lift_angle_degrees = -1.25,
        critical_angle_degrees = 17,
        negative_critical_angle_degrees = -15,
        post_stall_angle_degrees = 32,
        post_stall_lift_coefficient = .55,
        induced_drag_factor = .045,
        trim_angle_of_attack_degrees = 8,
        pitch_stability = 135000,
        pitch_damping = 24000,
        roll_stability = 30000,
        roll_damping = 15000,
        yaw_stability = 115000,
        yaw_damping = 15500,
        pitch_control_scale = 1.1,
        roll_control_scale = 1.25,
        yaw_control_scale = .85,
        water_capable = true,
        water_planing_start_speed = 11.5,
        water_planing_full_speed = 20.5,
        water_planing_reference_speed = 22,
        water_plow_drag_scale = .72,
    }
}

default_runtime :: proc() -> Runtime { return{
        engine_output = 1,
        control_authority = 1,
        drag_multiplier = 1,
        stall_speed_modifier = 1,
    } }
effective_stall_speed :: proc(mass: f32, airframe: Airframe) -> f32 { return(
        airframe.stall_speed *
        math.sqrt(clamp(mass / max_f32(airframe.maximum_gross_mass_kg, 1), .55, 1.1)) \
    ) }
drag_force_at_speed :: proc(speed: f32, airframe: Airframe) -> f32 { return(
        speed *
        speed *
        (airframe.static_thrust_per_engine *
                airframe.engine_count /
                (airframe.maximum_speed * airframe.maximum_speed)) *
        airframe.drag_scale \
    ) }
max_f32 :: proc(a, b: f32) -> f32 { if a > b do return a; return b }

lift_coefficient :: proc(angle: f32, airframe: Airframe) -> f32 {
    delta := angle - airframe.zero_lift_angle_degrees; s := sign(delta); magnitude := math.abs(delta)
    critical := airframe.negative_critical_angle_degrees + airframe.zero_lift_angle_degrees
    if s >= 0 do critical = airframe.critical_angle_degrees - airframe.zero_lift_angle_degrees
    critical = max_f32(1, math.abs(critical)); peak := airframe.lift_curve_slope_per_degree * critical
    if magnitude <= critical do return s * airframe.lift_curve_slope_per_degree * magnitude
    blend := clamp((magnitude - critical) / max_f32(1, airframe.post_stall_angle_degrees - critical), 0, 1)
    return s * lerp(peak, airframe.post_stall_lift_coefficient, blend * blend * (3 - 2 * blend))
}

calculate_forces :: proc(
    air_velocity: Vec3,
    basis_input: Basis,
    mass: f32,
    airframe: Airframe,
    drag_multiplier, flap: f32,
) -> (
    Forces,
    Telemetry,
) {
    speed := length(air_velocity); stall := effective_stall_speed(mass, airframe) * lerp(1, .88, flap)
    if speed < .5 do return {}, {effective_stall_speed = stall}
    basis := orthonormalize(
        basis_input,
    ); forward_speed := dot(air_velocity, basis.forward); vertical_speed := dot(air_velocity, basis.up)
    aoa := degrees(
        math.atan2(-vertical_speed, forward_speed),
    ); if aoa > 90 { aoa = 180 - aoa } else if aoa < -90 { aoa = -180 - aoa }
    wing_speed := math.sqrt(
        forward_speed * forward_speed + vertical_speed * vertical_speed,
    ); effective_aoa := aoa + airframe.wing_incidence_degrees + flap * 5.2
    cl :=
        lift_coefficient(effective_aoa, airframe) * (1 + flap * .12); pressure := .5 * 1.225 * wing_speed * wing_speed
    lift_direction := normalize(
        sub(scale(basis.up, forward_speed), scale(basis.forward, vertical_speed)),
    ); if length(lift_direction) < .01 do lift_direction = basis.up
    velocity_direction := normalize(
        air_velocity,
    ); parasitic := drag_force_at_speed(speed, airframe) * drag_multiplier * (1 + flap * .34)
    induced := pressure * airframe.wing_area * airframe.induced_drag_factor * cl * cl * drag_multiplier
    lateral_speed := dot(
        air_velocity,
        basis.right,
    ); lateral := drag_force_at_speed(math.abs(lateral_speed), airframe) * 3.2 * drag_multiplier
    forces := Forces {
        lift           = scale(lift_direction, pressure * airframe.wing_area * cl * airframe.lift_scale),
        parasitic_drag = scale(velocity_direction, -parasitic),
        induced_drag   = scale(velocity_direction, -induced),
        lateral_drag   = scale(basis.right, -sign(lateral_speed) * lateral),
    }
    return forces, {
        airspeed = speed,
        angle_of_attack_degrees = aoa,
        effective_stall_speed = stall,
        lift_coefficient = cl,
        is_stalling = effective_aoa >= airframe.critical_angle_degrees ||
        effective_aoa <= airframe.negative_critical_angle_degrees,
    }
}

assistance_scale :: proc(control: f32) -> f32 { t := clamp((math.abs(control) - .35) / .45, 0, 1); return(
        1 -
        t * t * (3 - 2 * t) \
    ) }

step :: proc(
    state: ^Body_State,
    command_input: Control_Command,
    airframe: Airframe,
    runtime: Runtime,
    wind: Vec3,
    delta_seconds: f32,
) -> Telemetry {
    if state == nil || delta_seconds <= 0 do return {}
    command :=
        command_input; command.pitch = clamp(command.pitch, -1, 1); command.roll = clamp(command.roll, -1, 1); command.yaw = clamp(command.yaw, -1, 1); command.throttle = clamp(command.throttle, 0, 1); flap := clamp(f32(command.flap_setting) / 2, 0, 1)
    tuned_airframe := airframe
    tuned_airframe.stall_speed *= max_f32(runtime.stall_speed_modifier, .1)
    state.basis = orthonormalize(
        state.basis,
    ); air_velocity := sub(state.velocity, wind); mass := max_f32(tuned_airframe.mass_kg, 1); forces, telemetry := calculate_forces(air_velocity, state.basis, mass, tuned_airframe, max_f32(runtime.drag_multiplier, .1), flap)
    shaft_power :=
        airframe.rated_power_per_engine_kw *
        1000 *
        airframe.propeller_efficiency *
        command.throttle; thrust_per_engine := min_f32(airframe.static_thrust_per_engine, shaft_power / max_f32(telemetry.airspeed, 12)); thrust := thrust_per_engine * max_f32(1, airframe.engine_count) * clamp(runtime.engine_output, 0, 1)
    total := add(
        add(add(forces.lift, forces.parasitic_drag), add(forces.induced_drag, forces.lateral_drag)),
        scale(state.basis.forward, thrust),
    ); state.velocity = add(state.velocity, scale(add(total, {y = -9.81 * mass}), delta_seconds / mass)); state.position = add(state.position, scale(state.velocity, delta_seconds))
    local_rate := world_to_local(
        state.basis,
        state.angular_velocity,
    ); speed_ratio := telemetry.airspeed / max_f32(telemetry.effective_stall_speed, 1); bite := clamp(speed_ratio * speed_ratio, 0, 1.25); propwash := math.sqrt(command.throttle * clamp(runtime.engine_output, 0, 1)) * 15; pitch_bite := clamp(max_f32(telemetry.airspeed, propwash) / max_f32(telemetry.effective_stall_speed, 1), 0, 1.25); pitch_bite *= pitch_bite
    protection :=
        clamp((1.08 - speed_ratio) / .32, 0, 1) *
        clamp((telemetry.angle_of_attack_degrees - 8) / 8, 0, 1) *
        assistance_scale(
            command.pitch,
        ); target_pitch := command.pitch * airframe.pitch_control_scale * lerp(1.25, .72, protection); if protection > 0 && command.pitch > 0 do target_pitch -= protection * .28
    handling := clamp(
        runtime.control_authority,
        0,
        1,
    ); target := vec3(target_pitch * handling, (-command.yaw * airframe.yaw_control_scale * .72 - command.roll * airframe.roll_control_scale * .34 * clamp(speed_ratio, 0, 1.2)) * bite * handling, command.roll * airframe.roll_control_scale * 2.05 * handling)
    damage: f32 = 1; if runtime.controls_damaged do damage = .55; torque_local := vec3((target.x - local_rate.x) * 52000 * pitch_bite * damage, target.y * 39000 * damage, (target.z - local_rate.z) * 47000 * bite * damage)
    roll_angle := math.atan2(
        dot(state.basis.right, {y = 1}),
        dot(state.basis.up, {y = 1}),
    ); authority := clamp(speed_ratio * speed_ratio, 0, 1.8); trim := airframe.trim_angle_of_attack_degrees; stability := vec3((degrees_to_radians(clamp(trim - telemetry.angle_of_attack_degrees, -18, 18)) * airframe.pitch_stability - local_rate.x * airframe.pitch_damping) * authority, (-degrees_to_radians(clamp(degrees(math.asin(clamp(dot(normalize(air_velocity), state.basis.right), -1, 1))), -35, 35)) * airframe.yaw_stability - local_rate.y * airframe.yaw_damping) * authority, (-sign(roll_angle) * max_f32(0, math.abs(roll_angle) - .95993) * airframe.roll_stability - local_rate.z * airframe.roll_damping) * authority)
    torque_local = add(
        torque_local,
        vec3(stability.x * assistance_scale(command.pitch), stability.y, stability.z * assistance_scale(command.roll)),
    ); state.angular_velocity = add(state.angular_velocity, scale(local_to_world(state.basis, torque_local), delta_seconds / (mass * 12)))
    state.basis.forward = add(
        state.basis.forward,
        scale(cross(state.angular_velocity, state.basis.forward), delta_seconds),
    ); state.basis.up = add(state.basis.up, scale(cross(state.angular_velocity, state.basis.up), delta_seconds)); state.basis = orthonormalize(state.basis)
    return telemetry
}

min_f32 :: proc(a, b: f32) -> f32 { if a < b do return a; return b }
degrees_to_radians :: proc(value: f32) -> f32 { return value * .0174532925 }
