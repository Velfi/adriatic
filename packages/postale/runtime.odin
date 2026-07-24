package postale

import flight "../flight"
import third_person "../third_person"
import vehicles "../vehicles"
import "core:math"

// The generated Postale mesh extends roughly .55 world units below its body
// origin at the presentation scale. Keep a small runway gap so its belly and
// propeller do not start inside uneven terrain.
GROUND_CLEARANCE :: f32(.62)
SAFE_TOUCHDOWN_SPEED :: f32(5)
SAFE_BANK_RADIANS :: f32(.4363323)
SAFE_EXIT_SPEED :: f32(1)
TAKEOFF_STALL_SPEED_SCALE :: f32(.68)

Runtime :: struct {
	body:            flight.Body_State,
	vehicle:         vehicles.Vehicle,
	airframe:        flight.Airframe,
	flight_runtime:  flight.Runtime,
	telemetry:       flight.Telemetry,
	throttle:        f32,
	flap_fraction:   f32,
	propeller_turns: f32,
	pitch:           f32,
	roll:            f32,
	yaw:             f32,
	grounded:        bool,
	crashed:         bool,
	was_grounded:    bool,
	spawn_position:  flight.Vec3,
	spawn_basis:     flight.Basis,
}

Control :: struct {
	throttle_up, throttle_down: bool,
	pitch, roll, yaw:           f32,
}

Ground_Result :: struct {
	grounded, crashed, touched_down: bool,
}

new_runtime :: proc(spawn_position: flight.Vec3) -> Runtime {
	result := Runtime {
		airframe = flight.postale_airframe(),
		flight_runtime = flight.default_runtime(),
		spawn_position = spawn_position,
		spawn_basis = {forward = {-1, 0, 0}, up = {0, 1, 0}, right = {0, 0, -1}},
	}
	result.flight_runtime.stall_speed_modifier = TAKEOFF_STALL_SPEED_SCALE
	reset(&result, spawn_position.y - GROUND_CLEARANCE)
	return result
}

reset :: proc(runtime: ^Runtime, ground_height: f32) {
	if runtime == nil do return
	runtime.body = {
		position = runtime.spawn_position,
		basis    = runtime.spawn_basis,
	}
	runtime.body.position.y = ground_height + GROUND_CLEARANCE
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
	runtime.crashed = false
}

step :: proc(
	runtime: ^Runtime,
	control: Control,
	ground_height, delta_seconds: f32,
) -> Ground_Result {
	if runtime == nil || delta_seconds <= 0 do return {}
	dt := min_f32(delta_seconds, .05)
	if runtime.crashed {
		runtime.body.velocity = flight.scale(runtime.body.velocity, max_f32(0, 1 - dt * 5))
		sync_vehicle(runtime)
		return {grounded = runtime.grounded, crashed = true}
	}

	throttle_target := runtime.throttle
	if control.throttle_up do throttle_target += dt * .45
	if control.throttle_down do throttle_target -= dt * .65
	runtime.throttle = clamp(throttle_target, 0, 1)

	speed := flight.length(runtime.body.velocity)
	pitch_rate := math.abs(control.pitch) < math.abs(runtime.pitch) ? f32(5.5) : f32(3.8)
	roll_rate := math.abs(control.roll) < math.abs(runtime.roll) ? f32(6.5) : f32(4.8)
	runtime.pitch = approach(runtime.pitch, clamp(control.pitch, -1, 1), pitch_rate * dt)
	runtime.roll = approach(runtime.roll, clamp(control.roll, -1, 1), roll_rate * dt)
	runtime.yaw = slew_control(runtime.yaw, clamp(control.yaw, -1, 1), 4.2, 6.8, dt)
	flap_target: f32
	if runtime.grounded || (runtime.throttle < .35 && speed < 28) do flap_target = 1
	runtime.flap_fraction = approach(runtime.flap_fraction, flap_target, dt * 1.5)

	command := flight.Control_Command {
		pitch        = runtime.pitch,
		roll         = runtime.roll,
		yaw          = runtime.yaw,
		throttle     = runtime.throttle,
		flap_setting = int(math.round(f64(runtime.flap_fraction * 2))),
	}
	runtime.was_grounded = runtime.grounded
	vertical_before := runtime.body.velocity.y
	runtime.telemetry = flight.step(
		&runtime.body,
		command,
		runtime.airframe,
		runtime.flight_runtime,
		{},
		dt,
	)

	result := resolve_ground_contact(runtime, ground_height, vertical_before)
	if runtime.grounded {
		// Wheels remove lateral slip and make low-speed runway steering forgiving.
		forward_speed := flight.dot(runtime.body.velocity, runtime.body.basis.forward)
		forward_speed *= max_f32(0, 1 - dt * (control.throttle_down ? 3.2 : .55))
		runtime.body.velocity = flight.scale(runtime.body.basis.forward, max_f32(0, forward_speed))
		runtime.body.angular_velocity.x = 0
		runtime.body.angular_velocity.z = 0
		steer := runtime.yaw * dt * lerp(.8, .22, clamp(forward_speed / 20, 0, 1))
		rotate_ground_heading(&runtime.body.basis, steer)
		// Short-field assistance lets the authored runway reach flying speed.
		if runtime.throttle > .8 && forward_speed > runtime.telemetry.effective_stall_speed * .72 {
			runtime.body.velocity.y = max_f32(runtime.body.velocity.y, 2.4)
			runtime.grounded = false
			result.grounded = false
		}
	}
	runtime.propeller_turns += dt * (1.5 + runtime.throttle * 18)
	sync_vehicle(runtime)
	result.crashed = runtime.crashed
	return result
}

resolve_ground_contact :: proc(
	runtime: ^Runtime,
	ground_height, vertical_speed_before: f32,
) -> Ground_Result {
	if runtime == nil do return {}
	floor := ground_height + GROUND_CLEARANCE
	if runtime.body.position.y > floor do return {}
	touched_down := !runtime.was_grounded
	bank := bank_radians(runtime.body.basis)
	if touched_down &&
	   (-vertical_speed_before > SAFE_TOUCHDOWN_SPEED || math.abs(bank) > SAFE_BANK_RADIANS) {
		runtime.crashed = true
	}
	runtime.body.position.y = floor
	if runtime.body.velocity.y < 0 do runtime.body.velocity.y = 0
	runtime.grounded = true
	runtime.body.basis.up = {0, 1, 0}
	runtime.body.basis.forward.y = 0
	runtime.body.basis = flight.orthonormalize(runtime.body.basis)
	return {grounded = true, crashed = runtime.crashed, touched_down = touched_down}
}

can_exit :: proc(runtime: ^Runtime) -> bool {
	return(
		runtime != nil &&
		runtime.grounded &&
		!runtime.crashed &&
		flight.length(runtime.body.velocity) < SAFE_EXIT_SPEED \
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
	return math.atan2(flight.dot(basis.right, {y = 1}), flight.dot(basis.up, {y = 1}))
}

rotate_ground_heading :: proc(basis: ^flight.Basis, radians: f32) {
	if basis == nil || radians == 0 do return
	c, s := math.cos(radians), math.sin(radians)
	forward := basis.forward
	basis.forward = {
		x = forward.x * c - forward.z * s,
		z = forward.x * s + forward.z * c,
	}
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

lerp :: proc(a, b, t: f32) -> f32 {return a + (b - a) * clamp(t, 0, 1)}
min_f32 :: proc(a, b: f32) -> f32 {if a < b do return a; return b}
max_f32 :: proc(a, b: f32) -> f32 {if a > b do return a; return b}
