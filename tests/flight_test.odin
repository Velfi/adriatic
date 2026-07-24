package tests

import flight "../packages/flight"
import "core:testing"

@(test)
fixed_wing_aerodynamics :: proc(t: ^testing.T) {
	airframe := flight.default_airframe(); mass := airframe.maximum_gross_mass_kg
	forces, telemetry := flight.calculate_forces(
		{z = -40},
		flight.identity_basis(),
		mass,
		airframe,
		1,
		0,
	)
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
	testing.expect(
		t,
		pelican.water_planing_start_speed == 11.5 && pelican.water_plow_drag_scale == .72,
	)
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
