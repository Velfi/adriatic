package tests

import "core:testing"
import flight "../packages/flight"

@(test)
fixed_wing_aerodynamics :: proc(t: ^testing.T) {
	airframe := flight.default_airframe(); mass := airframe.maximum_gross_mass_kg
	forces, telemetry := flight.calculate_forces({z=-40}, flight.identity_basis(), mass, airframe, 1, 0)
	testing.expect(t, telemetry.airspeed == 40)
	testing.expect(t, forces.parasitic_drag.z > 0)
	testing.expect(t, !telemetry.is_stalling)
}

@(test)
fixed_wing_step_produces_thrust :: proc(t: ^testing.T) {
	state := flight.Body_State {basis=flight.identity_basis()}; airframe := flight.default_airframe(); runtime := flight.default_runtime()
	flight.step(&state, {throttle=1}, airframe, runtime, {}, 1.0/60.0)
	testing.expect(t, state.velocity.z < 0)
}
