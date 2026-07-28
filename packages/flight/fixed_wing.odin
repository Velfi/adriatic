package flight

import "core:math"
import "core:math/linalg"

// Product-owned airframe tuning. Units: kg, m, seconds, Newtons, and degrees.
Airframe :: struct {
    // `fixed_wing_layout` and `tri_rotor_vtol_layout` select the applicable
    // integrator. The airframe remains product-owned tuning, not engine policy.
    flight_layout:                                                                                                                       u8,
    mass_kg, maximum_gross_mass_kg:                                                                                                      f32,
    wing_area, lift_scale, drag_scale, parasitic_drag_area:                                                                              f32,
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
    flap_fraction:              f32,
}
Runtime :: struct {
    engine_output, control_authority, drag_multiplier: f32,
    controls_damaged:                                  bool,
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
        parasitic_drag_area = 7,
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
        flight_layout                   = fixed_wing_layout,
        mass_kg                         = 3300,
        maximum_gross_mass_kg           = 3800,
        wing_area                       = 42,
        lift_scale                      = 1.45,
        drag_scale                      = 1,
        parasitic_drag_area             = 1.33,
        rated_power_per_engine_kw       = 560,
        propeller_efficiency            = .78,
        static_thrust_per_engine        = 12000,
        engine_count                    = 1,
        wing_incidence_degrees          = 4,
        lift_curve_slope_per_degree     = .095,
        zero_lift_angle_degrees         = -1.25,
        critical_angle_degrees          = 17,
        negative_critical_angle_degrees = -15,
        post_stall_angle_degrees        = 32,
        post_stall_lift_coefficient     = .55,
        induced_drag_factor             = .045,
        // Keep neutral cruise lift near level flight; the wing incidence and
        // Postale lift multiplier already provide ample takeoff authority.
        trim_angle_of_attack_degrees    = 1.5,
        pitch_stability                 = 145000,
        pitch_damping                   = 27500,
        roll_stability                  = 24000,
        roll_damping                    = 14500,
        yaw_stability                   = 82000,
        yaw_damping                     = 10500,
        pitch_control_scale             = .95,
        roll_control_scale              = 1.35,
        yaw_control_scale               = .55,
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
        parasitic_drag_area = 7,
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

default_runtime :: proc() -> Runtime {return {engine_output = 1, control_authority = 1, drag_multiplier = 1}}
effective_stall_speed :: proc(mass: f32, airframe: Airframe, flap: f32 = 0) -> f32 {
    weight := max_f32(mass, 1) * 9.81
    flap_fraction := clamp(flap, 0, 1)
    maximum_lift_coefficient := max_f32(
        lift_coefficient(airframe.critical_angle_degrees, airframe) *
        (1 + flap_fraction * .12) *
        max_f32(airframe.lift_scale, .01),
        .01,
    )
    lifting_area := max_f32(airframe.wing_area, .01)
    return f32(math.sqrt(f64(2 * weight / (1.225 * lifting_area * maximum_lift_coefficient))))
}
drag_force_at_speed :: proc(speed: f32, airframe: Airframe) -> f32 {return(
        .5 *
        1.225 *
        speed *
        speed *
        max_f32(airframe.parasitic_drag_area, .01) *
        airframe.drag_scale \
    )}
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
    speed := linalg.length(air_velocity); stall := effective_stall_speed(mass, airframe, flap)
    if speed < .5 do return {}, {effective_stall_speed = stall}
    basis := orthonormalize(
        basis_input,
    ); forward_speed := linalg.dot(air_velocity, basis.forward); vertical_speed := linalg.dot(air_velocity, basis.up)
    aoa := degrees(
        math.atan2(-vertical_speed, forward_speed),
    ); if aoa > 90 { aoa = 180 - aoa } else if aoa < -90 { aoa = -180 - aoa }
    wing_speed := math.sqrt(
        forward_speed * forward_speed + vertical_speed * vertical_speed,
    ); effective_aoa := aoa + airframe.wing_incidence_degrees + flap * 5.2
    cl :=
        lift_coefficient(effective_aoa, airframe) * (1 + flap * .12); pressure := .5 * 1.225 * wing_speed * wing_speed
    lift_direction := linalg.normalize0(basis.up * forward_speed - basis.forward * vertical_speed)
    if linalg.dot(lift_direction, lift_direction) < .0001 do lift_direction = basis.up
    velocity_direction := linalg.normalize0(air_velocity)
    parasitic := drag_force_at_speed(speed, airframe) * drag_multiplier * (1 + flap * .34)
    induced := pressure * airframe.wing_area * airframe.induced_drag_factor * cl * cl * drag_multiplier
    lateral_speed := linalg.dot(
        air_velocity,
        basis.right,
    ); lateral := drag_force_at_speed(math.abs(lateral_speed), airframe) * 3.2 * drag_multiplier
    forces := Forces {
        lift           = lift_direction * (pressure * airframe.wing_area * cl * airframe.lift_scale),
        parasitic_drag = velocity_direction * -parasitic,
        induced_drag   = velocity_direction * -induced,
        lateral_drag   = basis.right * (-sign(lateral_speed) * lateral),
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

assistance_scale :: proc(control: f32) -> f32 {t := clamp((math.abs(control) - .35) / .45, 0, 1)
    return 1 - t * t * (3 - 2 * t)}

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
        command_input; command.pitch = clamp(command.pitch, -1, 1); command.roll = clamp(command.roll, -1, 1); command.yaw = clamp(command.yaw, -1, 1); command.throttle = clamp(command.throttle, 0, 1); flap := clamp(command.flap_fraction, 0, 1)
    state.basis = orthonormalize(
        state.basis,
    ); air_velocity := state.velocity - wind; mass := max_f32(airframe.mass_kg, 1); forces, telemetry := calculate_forces(air_velocity, state.basis, mass, airframe, max_f32(runtime.drag_multiplier, .1), flap)
    thrust_per_engine := propeller_thrust(
        airframe.rated_power_per_engine_kw * 1000,
        airframe.propeller_efficiency,
        airframe.static_thrust_per_engine,
        telemetry.airspeed,
        command.throttle,
    )
    thrust := thrust_per_engine * max_f32(1, airframe.engine_count) * clamp(runtime.engine_output, 0, 1)
    total :=
        forces.lift + forces.parasitic_drag + forces.induced_drag + forces.lateral_drag + state.basis.forward * thrust
    state.velocity += (total + {0, -9.81 * mass, 0}) * (delta_seconds / mass)
    state.position += state.velocity * delta_seconds
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
    ); target := Vec3{target_pitch * handling, (-command.yaw * airframe.yaw_control_scale * .72 - command.roll * airframe.roll_control_scale * .34 * clamp(speed_ratio, 0, 1.2)) * bite * handling, command.roll * airframe.roll_control_scale * 2.05 * handling}
    damage: f32 = 1; if runtime.controls_damaged do damage = .55; torque_local := Vec3{(target.x - local_rate.x) * 52000 * pitch_bite * damage, target.y * 39000 * damage, (target.z - local_rate.z) * 47000 * bite * damage}
    roll_angle := math.atan2(
        linalg.dot(state.basis.right, Vec3{0, 1, 0}),
        linalg.dot(state.basis.up, Vec3{0, 1, 0}),
    ); authority := clamp(speed_ratio * speed_ratio, 0, 1.8); trim := airframe.trim_angle_of_attack_degrees; stability := Vec3{(degrees_to_radians(clamp(trim - telemetry.angle_of_attack_degrees, -18, 18)) * airframe.pitch_stability - local_rate.x * airframe.pitch_damping) * authority, (-degrees_to_radians(clamp(degrees(math.asin(clamp(linalg.dot(linalg.normalize0(air_velocity), state.basis.right), -1, 1))), -35, 35)) * airframe.yaw_stability - local_rate.y * airframe.yaw_damping) * authority, (-sign(roll_angle) * max_f32(0, math.abs(roll_angle) - .95993) * airframe.roll_stability - local_rate.z * airframe.roll_damping) * authority}
    torque_local += Vec3 {
        stability.x * assistance_scale(command.pitch),
        stability.y,
        stability.z * assistance_scale(command.roll),
    }
    state.angular_velocity += local_to_world(state.basis, torque_local) * (delta_seconds / (mass * 12))
    state.basis.forward += linalg.cross(state.angular_velocity, state.basis.forward) * delta_seconds
    state.basis.up += linalg.cross(state.angular_velocity, state.basis.up) * delta_seconds
    state.basis = orthonormalize(state.basis)
    return telemetry
}

propeller_thrust :: proc(
    rated_power_watts, efficiency, static_thrust, airspeed, throttle: f32,
) -> f32 {
    power_fraction := clamp(throttle, 0, 1)
    if power_fraction <= 0 do return 0
    available_power :=
        max_f32(rated_power_watts, 0) *
        clamp(efficiency, 0, 1) *
        power_fraction
    static_available := max_f32(static_thrust, 0) * f32(math.sqrt(f64(power_fraction)))
    if available_power <= 0 || static_available <= 0 do return 0
    induced_speed := available_power / static_available
    effective_speed := f32(
        math.sqrt(
            f64(
                max_f32(airspeed, 0) * max_f32(airspeed, 0) +
                induced_speed * induced_speed,
            ),
        ),
    )
    return available_power / max_f32(effective_speed, .01)
}

min_f32 :: proc(a, b: f32) -> f32 { if a < b do return a; return b }
degrees_to_radians :: proc(value: f32) -> f32 { return value * .0174532925 }
