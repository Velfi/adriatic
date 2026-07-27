package tests

import flight "../packages/flight"
import libellula "../packages/libellula"
import "core:math"
import "core:testing"

@(test)
fixed_wing_aerodynamics :: proc(t: ^testing.T) {
    airframe := flight.default_airframe(); mass := airframe.maximum_gross_mass_kg
    forces, telemetry := flight.calculate_forces(flight.Vec3{0, 0, -40}, flight.identity_basis(), mass, airframe, 1, 0)
    testing.expect(t, telemetry.airspeed == 40)
    testing.expect(t, forces.parasitic_drag.z > 0)
    testing.expect(t, !telemetry.is_stalling)
}

@(test)
fixed_wing_step_produces_thrust :: proc(t: ^testing.T) {
    state := flight.Body_State {
        orientation = flight.identity_orientation(),
    }; airframe := flight.default_airframe(); runtime := flight.default_runtime()
    flight.step(&state, {throttle = 1}, airframe, runtime, {}, 1.0 / 60.0)
    testing.expect(t, state.velocity.z < 0)
}

@(test)
fixed_wing_propeller_thrust_is_continuous_and_power_aware :: proc(t: ^testing.T) {
    airframe := flight.postale_airframe()
    power := airframe.rated_power_per_engine_kw * 1000
    static := flight.propeller_thrust(power, airframe.propeller_efficiency, airframe.static_thrust_per_engine, 0, 1)
    cruise := flight.propeller_thrust(power, airframe.propeller_efficiency, airframe.static_thrust_per_engine, 40, 1)
    reduced_power := flight.propeller_thrust(
        power * .5,
        airframe.propeller_efficiency,
        airframe.static_thrust_per_engine,
        40,
        1,
    )
    testing.expect(
        t,
        flight.propeller_thrust(power, airframe.propeller_efficiency, airframe.static_thrust_per_engine, 0, 0) == 0,
    )
    testing.expect(t, math.abs(static - airframe.static_thrust_per_engine) < .01)
    testing.expect(t, cruise > 0 && cruise < static)
    testing.expect(t, reduced_power < cruise)
}

@(test)
fixed_wing_stall_speed_comes_from_weight_wing_and_flaps :: proc(t: ^testing.T) {
    airframe := flight.postale_airframe()
    baseline := flight.effective_stall_speed(airframe.mass_kg, airframe)
    loaded := flight.effective_stall_speed(airframe.maximum_gross_mass_kg, airframe)
    flapped := flight.effective_stall_speed(airframe.mass_kg, airframe, 1)
    testing.expect(t, loaded > baseline)
    testing.expect(t, flapped < baseline)
}

@(test)
postale_and_pelican_tuning :: proc(t: ^testing.T) {
    postale := flight.postale_airframe(); pelican := flight.pelican_airframe()
    testing.expect(t, postale.engine_count == 1)
    testing.expect(t, postale.pitch_damping == 27500 && postale.roll_control_scale == 1.35)
    testing.expect(t, pelican.water_capable && pelican.engine_count == 2)
    testing.expect(t, pelican.water_planing_start_speed == 11.5 && pelican.water_plow_drag_scale == .72)
}

@(test)
libellula_rotors_allocate_collective :: proc(t: ^testing.T) {
    airframe := flight.libellula_airframe(
        
    ); caps := flight.Vec3{airframe.maximum_collective_force / 3, airframe.maximum_collective_force / 3, airframe.maximum_collective_force / 3}
    solution := flight.solve_tri_rotor(18000, 0, 0, {}, caps)
    testing.expect(t, solution.total_thrust == 18000)
    testing.expect(t, solution.thrusts.x == solution.thrusts.y && solution.thrusts.z > 0)
    state := flight.Body_State {
        orientation = flight.identity_orientation(),
    }; telemetry := flight.step_tri_rotor(
        &state,
        {throttle = 1},
        airframe,
        flight.default_tri_rotor_runtime(),
        1.0 / 60.0,
    )
    testing.expect(t, telemetry.total_thrust > airframe.mass_kg * 9.81 && state.velocity.y > 0)
}

@(test)
libellula_runtime_takes_off_and_syncs_occupancy_vehicle :: proc(t: ^testing.T) {
    ground := f32(10)
    runtime := libellula.new_runtime(flight.Vec3{4, ground + libellula.GROUND_CLEARANCE, 7})
    for _ in 0 ..< 240 {
        libellula.step(&runtime, {throttle_up = true}, ground, 1.0 / 60.0)
    }
    testing.expect(t, !runtime.grounded)
    testing.expect(t, runtime.body.position.y > ground + libellula.GROUND_CLEARANCE + 1)
    testing.expect(t, runtime.vehicle.position == libellula.to_third_person(runtime.body.position))
    testing.expect(t, runtime.telemetry.total_thrust > runtime.airframe.mass_kg * 9.7)
    testing.expect(t, runtime.rotor_turns.x > 0 && runtime.rotor_turns.y > 0 && runtime.rotor_turns.z > 0)
}

@(test)
libellula_runtime_resolves_ground_and_allows_safe_exit :: proc(t: ^testing.T) {
    ground := f32(3)
    runtime := libellula.new_runtime(flight.Vec3{0, ground + libellula.GROUND_CLEARANCE, 0})
    libellula.step(&runtime, {}, ground, 1.0 / 60.0)
    testing.expect(t, runtime.grounded)
    testing.expect(t, runtime.body.position.y == ground + libellula.GROUND_CLEARANCE)
    testing.expect(t, libellula.can_exit(&runtime))
}

@(test)
libellula_auto_level_preserves_pilot_cyclic_input :: proc(t: ^testing.T) {
    state := flight.Body_State {
        position    = {0, 50, 0},
        orientation = flight.identity_orientation(),
    }
    runtime := flight.default_tri_rotor_runtime()
    for _ in 0 ..< 30 {
        flight.step_tri_rotor(&state, {throttle = .7, pitch = 1}, flight.libellula_airframe(), runtime, 1.0 / 60.0)
    }
    testing.expect(t, flight.basis_from_orientation(state.orientation).forward.y != 0)
}
