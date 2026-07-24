package chase_camera

import flight "../flight"
import third_person "../third_person"
import "core:math"

FOLLOW_DISTANCE :: f32(16)
FOLLOW_HEIGHT :: f32(5.5)
LOOK_AHEAD :: f32(5)

State :: struct {
	pose:                   third_person.Camera_Pose,
	orbit_yaw, orbit_pitch: f32,
	focal_length:           f32,
	initialized:            bool,
}

Target :: struct {
	position:   flight.Vec3,
	basis:      flight.Basis,
	airspeed:   f32,
	roll_input: f32,
	grounded:   bool,
}

reset :: proc(state: ^State, target: Target) {
	if state == nil do return
	state.orbit_yaw = 0
	state.orbit_pitch = 0
	state.pose = desired_pose(target, 0, 0)
	state.focal_length = focal_length_for_fov(desired_fov(target.airspeed))
	state.initialized = true
}

look :: proc(state: ^State, mouse_x, mouse_y: f32) {
	if state == nil do return
	state.orbit_yaw = wrap_angle(state.orbit_yaw - mouse_x * .003)
	state.orbit_pitch = clamp(state.orbit_pitch - mouse_y * .0025, -.75, .75)
}

step :: proc(state: ^State, target: Target, delta_seconds: f32) {
	if state == nil do return
	desired := desired_pose(target, state.orbit_yaw, state.orbit_pitch)
	if !state.initialized || distance_squared(state.pose.position, desired.position) > 50 * 50 {
		state.pose = desired
		state.initialized = true
	} else {
		state.pose.position = lerp(
			state.pose.position,
			desired.position,
			exp_response(8, delta_seconds),
		)
		state.pose.target = lerp(
			state.pose.target,
			desired.target,
			exp_response(10, delta_seconds),
		)
	}
	state.focal_length = scalar_lerp(
		state.focal_length,
		focal_length_for_fov(desired_fov(target.airspeed)),
		exp_response(3.5, delta_seconds),
	)
}

desired_pose :: proc(target: Target, orbit_yaw, orbit_pitch: f32) -> third_person.Camera_Pose {
	forward := horizontal_forward(target.basis)
	behind := rotate_y(flight.scale(forward, -1), orbit_yaw)
	framing_camera, framing_focus := vertical_framing(target.basis.forward.y)
	position := flight.add(
		flight.add(target.position, flight.scale(behind, FOLLOW_DISTANCE)),
		{y = FOLLOW_HEIGHT + framing_camera + orbit_pitch * 8},
	)
	right := target.basis.right
	right.y = 0
	right = flight.normalize(right)
	look_ahead := LOOK_AHEAD + clamp(target.airspeed / 18, 0, 4)
	focus := flight.add(
		flight.add(target.position, flight.scale(forward, look_ahead)),
		flight.add(
			flight.scale(right, clamp(-target.roll_input * 3.2, -3.2, 3.2)),
			{y = 1 + framing_focus + (target.grounded ? -.35 : 0)},
		),
	)
	return {position = to_third_person(position), target = to_third_person(focus)}
}

vertical_framing :: proc(forward_up: f32) -> (f32, f32) {
	pitch := clamp(forward_up, -1, 1)
	engagement := smooth_step(clamp((math.abs(pitch) - .2) / .65, 0, 1))
	signed := engagement * math.sign(pitch)
	return -signed * 8, signed * 4
}

desired_fov :: proc(airspeed: f32) -> f32 {
	return scalar_lerp(70, 80, clamp((airspeed - 8) / 62, 0, 1))
}

focal_length_for_fov :: proc(fov_degrees: f32) -> f32 {
	return 1 / f32(math.tan(f64(fov_degrees * math.PI / 360)))
}

horizontal_forward :: proc(basis: flight.Basis) -> flight.Vec3 {
	forward := basis.forward
	forward.y = 0
	if flight.length(forward) > .001 do return flight.normalize(forward)
	right := basis.right
	right.y = 0
	if flight.length(right) <= .001 do return {z = -1}
	right = flight.normalize(right)
	return {-right.z, 0, right.x}
}

rotate_y :: proc(value: flight.Vec3, radians: f32) -> flight.Vec3 {
	sine, cosine := f32(math.sin(radians)), f32(math.cos(radians))
	return {value.x * cosine + value.z * sine, value.y, -value.x * sine + value.z * cosine}
}

to_third_person :: proc(value: flight.Vec3) -> third_person.Vec3 {
	return {value.x, value.y, value.z}
}

distance_squared :: proc(a, b: third_person.Vec3) -> f32 {
	x, y, z := b.x - a.x, b.y - a.y, b.z - a.z
	return x * x + y * y + z * z
}

lerp :: proc(a, b: third_person.Vec3, amount: f32) -> third_person.Vec3 {
	return {
		scalar_lerp(a.x, b.x, amount),
		scalar_lerp(a.y, b.y, amount),
		scalar_lerp(a.z, b.z, amount),
	}
}

exp_response :: proc(response, delta_seconds: f32) -> f32 {
	return 1 - f32(math.exp(f64(-response * max(delta_seconds, 0))))
}

smooth_step :: proc(value: f32) -> f32 {return value * value * (3 - 2 * value)}
scalar_lerp :: proc(a, b, amount: f32) -> f32 {return a + (b - a) * amount}
clamp :: proc(value, lower, upper: f32) -> f32 {return min(max(value, lower), upper)}
wrap_angle :: proc(value: f32) -> f32 {
	two_pi := f32(2 * math.PI)
	result := value
	for result > math.PI do result -= two_pi
	for result < -math.PI do result += two_pi
	return result
}
