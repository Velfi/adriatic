package vehicles

import third_person "../third_person"
import "core:math"

// Car_Drive_State keeps driveline speed separate from chassis momentum. That
// small distinction is what lets steering, braking, and the handbrake produce
// readable slip without requiring a full tire solver.
Car_Drive_State :: struct {
	velocity:                        third_person.Vec3,
	wheel_speed, steering, yaw_rate: f32,
	handbrake_amount:                f32,
	body_roll, body_pitch:           f32,
	acceleration_feedback:           f32,
}

Car_Drive_Input :: struct {
	throttle, steering: f32,
	handbrake:          bool,
}

Car_Drive_Tune :: struct {
	acceleration, brake, reverse_acceleration: f32,
	max_forward, max_reverse:                  f32,
	steering_response, yaw_response:           f32,
	lateral_grip, handbrake_grip:              f32,
	coast_deceleration:                        f32,
}

CAR_DRIVE_SEDAN_TUNE :: Car_Drive_Tune {
	acceleration         = 6.8,
	brake                = 14,
	reverse_acceleration = 5.2,
	max_forward          = 24,
	max_reverse          = 8.5,
	steering_response    = 7.5,
	yaw_response         = 5.5,
	lateral_grip         = 7.2,
	handbrake_grip       = 1.15,
	coast_deceleration   = 1.25,
}

car_drive_speed :: proc(state: Car_Drive_State) -> f32 {
	return f32(
		math.sqrt(f64(state.velocity.x * state.velocity.x + state.velocity.z * state.velocity.z)),
	)
}

car_drive_longitudinal_speed :: proc(state: Car_Drive_State, yaw: f32) -> f32 {
	return state.velocity.x * math.cos(yaw) + state.velocity.z * math.sin(yaw)
}

car_drive_approach :: proc(current, target, maximum_delta: f32) -> f32 {
	if current < target do return min(current + maximum_delta, target)
	return max(current - maximum_delta, target)
}

car_drive_angle_step :: proc(current, target, response: f32) -> f32 {
	delta := target - current
	for delta > math.PI do delta -= 2 * math.PI
	for delta < -math.PI do delta += 2 * math.PI
	return current + delta * clamp(response, 0, 1)
}

car_drive_step :: proc(
	state: ^Car_Drive_State,
	vehicle: ^Vehicle,
	input: Car_Drive_Input,
	ground_height, delta_seconds: f32,
	tune := CAR_DRIVE_SEDAN_TUNE,
) {
	if state == nil || vehicle == nil || delta_seconds <= 0 do return
	dt := min(delta_seconds, f32(.05))
	throttle := clamp(input.throttle, -1, 1)
	steer_input := clamp(input.steering, -1, 1)
	longitudinal_before := car_drive_longitudinal_speed(state^, vehicle.yaw_radians)

	if throttle > .01 {
		if state.wheel_speed < -.35 {
			state.wheel_speed = car_drive_approach(
				state.wheel_speed,
				0,
				tune.brake * throttle * dt,
			)
		} else {
			state.wheel_speed = car_drive_approach(
				state.wheel_speed,
				tune.max_forward * throttle,
				tune.acceleration * (.38 + .62 * throttle) * dt,
			)
		}
	} else if throttle < -.01 {
		load := -throttle
		if state.wheel_speed > .35 {
			state.wheel_speed = car_drive_approach(state.wheel_speed, 0, tune.brake * load * dt)
		} else {
			state.wheel_speed = car_drive_approach(
				state.wheel_speed,
				-tune.max_reverse * load,
				tune.reverse_acceleration * (.42 + .58 * load) * dt,
			)
		}
	} else {
		state.wheel_speed = car_drive_approach(state.wheel_speed, 0, tune.coast_deceleration * dt)
	}

	speed_ratio := clamp(car_drive_speed(state^) / tune.max_forward, 0, 1)
	steer_limit := 1 - speed_ratio * .48
	target_steering := steer_input * steer_limit
	state.steering += (target_steering - state.steering) * clamp(tune.steering_response * dt, 0, 1)
	handbrake_target := input.handbrake ? f32(1) : f32(0)
	handbrake_response := input.handbrake ? f32(11) : f32(4.5)
	state.handbrake_amount +=
		(handbrake_target - state.handbrake_amount) * clamp(handbrake_response * dt, 0, 1)

	forward_x := math.cos(vehicle.yaw_radians)
	forward_z := math.sin(vehicle.yaw_radians)
	right_x, right_z := -forward_z, forward_x
	longitudinal := state.velocity.x * forward_x + state.velocity.z * forward_z
	lateral := state.velocity.x * right_x + state.velocity.z * right_z
	travel_for_yaw := math.abs(longitudinal) < .08 ? f32(0) : longitudinal
	handbrake_yaw := 1 + state.handbrake_amount * .58
	target_yaw_rate := state.steering * travel_for_yaw * .044 * handbrake_yaw
	yaw_response := tune.yaw_response * (1 - state.handbrake_amount * .42)
	state.yaw_rate += (target_yaw_rate - state.yaw_rate) * clamp(yaw_response * dt, 0, 1)
	state.yaw_rate = clamp(state.yaw_rate, -1.35, 1.35)
	vehicle.yaw_radians += state.yaw_rate * dt

	forward_x = math.cos(vehicle.yaw_radians)
	forward_z = math.sin(vehicle.yaw_radians)
	right_x, right_z = -forward_z, forward_x
	longitudinal +=
		(state.wheel_speed - longitudinal) * clamp((5.8 - state.handbrake_amount * 1.8) * dt, 0, 1)
	grip := tune.lateral_grip + (tune.handbrake_grip - tune.lateral_grip) * state.handbrake_amount
	lateral *= 1 - clamp(grip * dt, 0, .95)
	state.velocity.x = forward_x * longitudinal + right_x * lateral
	state.velocity.z = forward_z * longitudinal + right_z * lateral
	vehicle.position.x += state.velocity.x * dt
	vehicle.position.z += state.velocity.z * dt
	vehicle.position.y = ground_height

	acceleration := (longitudinal - longitudinal_before) / max(dt, f32(.001))
	acceleration_target := clamp(acceleration / max(tune.acceleration, f32(1)), -1, 1)
	state.acceleration_feedback +=
		(acceleration_target - state.acceleration_feedback) * clamp(6 * dt, 0, 1)
	roll_target :=
		-state.steering *
		clamp(math.abs(longitudinal) / tune.max_forward, 0, 1) *
		(.07 + state.handbrake_amount * .035)
	pitch_target := state.acceleration_feedback * .045
	state.body_roll += (roll_target - state.body_roll) * clamp(7 * dt, 0, 1)
	state.body_pitch += (pitch_target - state.body_pitch) * clamp(6 * dt, 0, 1)
}
