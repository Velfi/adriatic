package tests

import flight "../packages/flight"
import libellula "../packages/libellula"
import "core:testing"

@(test)
fixed_wing_aerodynamics :: proc(t: ^testing.T) {
    airframe := flight.default_airframe(); mass := airframe.maximum_gross_mass_kg
    forces, telemetry := flight.calculate_forces({z = -40}, flight.identity_basis(), mass, airframe, 1, 0)
    testing.expect(t, telemetry.airspeed == 40)
    testing.expect(t, forces.parasitic_drag.z > 0)
    testing.expect(t, !telemetry.is_stalling)
}

@(test)
fixed_wing_step_produces_thrust :: proc(t: ^testing.T) {
    state := flight.Body_State {
        basis = flight.identity_basis(),
    }; airframe := flight.default_airframe(); runtime := flight.default_runtime()
    flight.step(&state, {throttle = 1}, airframe, runtime, {}, 1.0 / 60.0)
    testing.expect(t, state.velocity.z < 0)
}

@(test)
fixed_wing_runtime_stall_modifier_changes_effective_stall_speed :: proc(t: ^testing.T) {
    state := flight.Body_State {
        velocity = {z = -20},
        basis = flight.identity_basis(),
    }
    airframe := flight.postale_airframe()
    runtime := flight.default_runtime()
    baseline := flight.step(&state, {}, airframe, runtime, {}, 1.0 / 60.0)
    state = {
        velocity = {z = -20},
        basis = flight.identity_basis(),
    }
    runtime.stall_speed_modifier = .5
    assisted := flight.step(&state, {}, airframe, runtime, {}, 1.0 / 60.0)
    testing.expect(t, assisted.effective_stall_speed < baseline.effective_stall_speed)
}

@(test)
postale_and_pelican_tuning :: proc(t: ^testing.T) {
    postale := flight.postale_airframe(); pelican := flight.pelican_airframe()
    testing.expect(t, postale.stall_speed == 24 && postale.engine_count == 1)
    testing.expect(t, postale.pitch_damping == 27500 && postale.roll_control_scale == 1.05)
    testing.expect(t, pelican.water_capable && pelican.engine_count == 2)
    testing.expect(t, pelican.water_planing_start_speed == 11.5 && pelican.water_plow_drag_scale == .72)
}

@(test)
libellula_rotors_allocate_collective :: proc(t: ^testing.T) {
    airframe := flight.libellula_airframe(
        
    ); caps := flight.vec3(airframe.maximum_collective_force / 3, airframe.maximum_collective_force / 3, airframe.maximum_collective_force / 3)
    solution := flight.solve_tri_rotor(18000, 0, 0, {}, caps)
    testing.expect(t, solution.total_thrust == 18000)
    testing.expect(t, solution.thrusts.x == solution.thrusts.y && solution.thrusts.z > 0)
    state := flight.Body_State {
        basis = flight.identity_basis(),
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
    runtime := libellula.new_runtime({x = 4, y = ground + libellula.GROUND_CLEARANCE, z = 7})
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
    runtime := libellula.new_runtime({y = ground + libellula.GROUND_CLEARANCE})
    libellula.step(&runtime, {}, ground, 1.0 / 60.0)
    testing.expect(t, runtime.grounded)
    testing.expect(t, runtime.body.position.y == ground + libellula.GROUND_CLEARANCE)
    testing.expect(t, libellula.can_exit(&runtime))
}

@(test)
libellula_auto_level_preserves_pilot_cyclic_input :: proc(t: ^testing.T) {
    state := flight.Body_State {
        position = {y = 50},
        basis = flight.identity_basis(),
    }
    runtime := flight.default_tri_rotor_runtime()
    for _ in 0 ..< 30 {
        flight.step_tri_rotor(&state, {throttle = .7, pitch = 1}, flight.libellula_airframe(), runtime, 1.0 / 60.0)
    }
    testing.expect(t, state.basis.forward.y != 0)
}
