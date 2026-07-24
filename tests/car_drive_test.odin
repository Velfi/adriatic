package tests

import vehicles "../packages/vehicles"
import "core:math"
import "core:testing"

@(test)
car_drive_has_progressive_forward_and_reverse_motion :: proc(t: ^testing.T) {
	car := vehicles.default_vehicle({})
	state: vehicles.Car_Drive_State
	for _ in 0 ..< 120 {
		vehicles.car_drive_step(&state, &car, {throttle = 1}, 0, 1.0 / 60)
	}
	testing.expect(t, car.position.x > 4)
	testing.expect(t, state.wheel_speed > 5)
	for _ in 0 ..< 180 {
		vehicles.car_drive_step(&state, &car, {throttle = -1}, 0, 1.0 / 60)
	}
	testing.expect(t, state.wheel_speed < 0)
}

@(test)
car_drive_steers_with_travel_and_handbrake_releases_lateral_grip :: proc(t: ^testing.T) {
	normal_car := vehicles.default_vehicle({})
	normal := vehicles.Car_Drive_State {
		velocity = {x = 12, z = 5},
		wheel_speed = 12,
	}
	loose_car := normal_car
	loose := normal
	for _ in 0 ..< 30 {
		vehicles.car_drive_step(&normal, &normal_car, {steering = 1}, 0, 1.0 / 60)
		vehicles.car_drive_step(&loose, &loose_car, {steering = 1, handbrake = true}, 0, 1.0 / 60)
	}
	testing.expect(t, normal_car.yaw_radians > 0)
	testing.expect(t, loose_car.yaw_radians > normal_car.yaw_radians)
	testing.expect(t, math.abs(loose.velocity.z) > math.abs(normal.velocity.z))
}

@(test)
car_drive_body_feedback_is_bounded :: proc(t: ^testing.T) {
	car := vehicles.default_vehicle({})
	state: vehicles.Car_Drive_State
	for _ in 0 ..< 240 {
		vehicles.car_drive_step(&state, &car, {throttle = 1, steering = 1}, 0, 1.0 / 60)
	}
	testing.expect(t, math.abs(state.body_roll) <= .106)
	testing.expect(t, math.abs(state.body_pitch) <= .046)
}
