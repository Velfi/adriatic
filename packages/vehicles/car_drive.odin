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
    surface_longitudinal_grip:       f32,
    surface_lateral_grip:            f32,
    surface_rolling_resistance:      f32,
    slip_amount:                     f32,
}

Car_Drive_Input :: struct {
    throttle, steering: f32,
    handbrake:          bool,
}

Car_Drive_Tune :: struct {
    acceleration, brake, reverse_acceleration: f32,
    max_forward, max_reverse:                  f32,
    steering_response, yaw_response:           f32,
    turn_curvature, max_yaw_rate:              f32,
    high_speed_steering, reverse_steering:     f32,
    lateral_grip, handbrake_grip:              f32,
    coast_deceleration:                        f32,
}

Car_Drive_Surface :: struct {
    longitudinal_grip:  f32,
    lateral_grip:       f32,
    rolling_resistance: f32,
}

// Car_Trailer_State is the small rigid-body state needed by the product-local
// trailer. The car solver is intentionally arcade-oriented, so the trailer is
// solved as a planar body with a spring-damper hitch and a passive axle.
Car_Trailer_State :: struct {
    velocity:              third_person.Vec3,
    yaw_rate:              f32,
    reaction_force:        third_person.Vec3,
    body_roll, body_pitch: f32,
    wheel_rotation:        f32,
}

CAR_DRIVE_DEFAULT_SURFACE :: Car_Drive_Surface {
    longitudinal_grip  = 1,
    lateral_grip       = 1,
    rolling_resistance = 1,
}

CAR_DRIVE_SEDAN_TUNE :: Car_Drive_Tune {
    acceleration         = 6.8,
    brake                = 14,
    reverse_acceleration = 5.2,
    max_forward          = 24,
    max_reverse          = 8.5,
    steering_response    = 10,
    yaw_response         = 8.5,
    turn_curvature       = .18,
    max_yaw_rate         = 1.2,
    high_speed_steering  = .55,
    reverse_steering     = .78,
    lateral_grip         = 8.4,
    handbrake_grip       = .95,
    coast_deceleration   = 1.25,
}

car_drive_speed :: proc(state: Car_Drive_State) -> f32 {
    return f32(math.sqrt(f64(state.velocity.x * state.velocity.x + state.velocity.z * state.velocity.z)))
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

// GTA-like steering gives analog input a softer center without weakening full
// keyboard or stick lock. This makes small corrections calm at road speed but
// keeps the car immediately readable when the player commits to a turn.
car_drive_arcade_steering :: proc(steering: f32) -> f32 {
    magnitude := math.abs(clamp(steering, -1, 1))
    curved := magnitude * .35 + magnitude * magnitude * .65
    return math.sign(steering) * curved
}

car_drive_target_yaw_rate :: proc(
    steering, longitudinal_speed, handbrake_amount: f32,
    tune := CAR_DRIVE_SEDAN_TUNE,
) -> f32 {
    speed := math.abs(longitudinal_speed)
    if speed < .08 || tune.max_forward <= .01 do return 0

    speed_ratio := clamp(speed / tune.max_forward, 0, 1)
    // Curvature makes steering build naturally from a crawl. The separate yaw
    // cap then reduces authority at high speed, producing GTA's characteristic
    // stable lane changes without making city corners feel sluggish.
    curvature_rate := speed * tune.turn_curvature
    speed_limited_rate := tune.max_yaw_rate * (1 - speed_ratio * (1 - clamp(tune.high_speed_steering, 0, 1)))
    available_rate := min(curvature_rate, speed_limited_rate)
    if longitudinal_speed < 0 do available_rate *= tune.reverse_steering

    handbrake_boost := 1 + clamp(handbrake_amount, 0, 1) * .62
    direction := longitudinal_speed < 0 ? f32(-1) : f32(1)
    return car_drive_arcade_steering(steering) * available_rate * direction * handbrake_boost
}

car_drive_step :: proc(
    state: ^Car_Drive_State,
    vehicle: ^Vehicle,
    input: Car_Drive_Input,
    ground_height, delta_seconds: f32,
    surface := CAR_DRIVE_DEFAULT_SURFACE,
    tune := CAR_DRIVE_SEDAN_TUNE,
) {
    if state == nil || vehicle == nil || delta_seconds <= 0 do return
    dt := min(delta_seconds, f32(.05))
    throttle := clamp(input.throttle, -1, 1)
    steer_input := clamp(input.steering, -1, 1)
    longitudinal_before := car_drive_longitudinal_speed(state^, vehicle.yaw_radians)
    target_longitudinal_grip := clamp(surface.longitudinal_grip, f32(.2), f32(1.2))
    target_lateral_grip := clamp(surface.lateral_grip, f32(.2), f32(1.2))
    target_rolling_resistance := clamp(surface.rolling_resistance, f32(.65), f32(2))
    if state.surface_longitudinal_grip <= 0 {
        state.surface_longitudinal_grip = target_longitudinal_grip
        state.surface_lateral_grip = target_lateral_grip
        state.surface_rolling_resistance = target_rolling_resistance
    } else {
        surface_response := clamp(4.5 * dt, 0, 1)
        state.surface_longitudinal_grip +=
            (target_longitudinal_grip - state.surface_longitudinal_grip) * surface_response
        state.surface_lateral_grip += (target_lateral_grip - state.surface_lateral_grip) * surface_response
        state.surface_rolling_resistance +=
            (target_rolling_resistance - state.surface_rolling_resistance) * surface_response
    }

    if throttle > .01 {
        if state.wheel_speed < -.35 {
            state.wheel_speed = car_drive_approach(state.wheel_speed, 0, tune.brake * throttle * dt)
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
        state.wheel_speed = car_drive_approach(
            state.wheel_speed,
            0,
            tune.coast_deceleration * state.surface_rolling_resistance * dt,
        )
    }

    state.steering += (steer_input - state.steering) * clamp(tune.steering_response * dt, 0, 1)
    handbrake_target := input.handbrake ? f32(1) : f32(0)
    handbrake_response := input.handbrake ? f32(11) : f32(4.5)
    state.handbrake_amount += (handbrake_target - state.handbrake_amount) * clamp(handbrake_response * dt, 0, 1)

    forward_x := math.cos(vehicle.yaw_radians)
    forward_z := math.sin(vehicle.yaw_radians)
    right_x, right_z := -forward_z, forward_x
    longitudinal := state.velocity.x * forward_x + state.velocity.z * forward_z
    lateral := state.velocity.x * right_x + state.velocity.z * right_z
    steering_authority := .55 + state.surface_lateral_grip * .45
    target_yaw_rate :=
        car_drive_target_yaw_rate(state.steering, longitudinal, state.handbrake_amount, tune) * steering_authority
    yaw_response := tune.yaw_response * (1 - state.handbrake_amount * .42)
    state.yaw_rate += (target_yaw_rate - state.yaw_rate) * clamp(yaw_response * dt, 0, 1)
    state.yaw_rate = clamp(state.yaw_rate, -1.35, 1.35)
    vehicle.yaw_radians += state.yaw_rate * dt

    forward_x = math.cos(vehicle.yaw_radians)
    forward_z = math.sin(vehicle.yaw_radians)
    right_x, right_z = -forward_z, forward_x
    wheel_slip := state.wheel_speed - longitudinal
    longitudinal +=
        wheel_slip * clamp((5.8 - state.handbrake_amount * 1.8) * state.surface_longitudinal_grip * dt, 0, 1)
    grip := tune.lateral_grip + (tune.handbrake_grip - tune.lateral_grip) * state.handbrake_amount
    lateral_before := lateral
    lateral *= 1 - clamp(grip * state.surface_lateral_grip * dt, 0, .95)
    slip_target := clamp(math.abs(lateral_before) / 8 + math.abs(wheel_slip) / 18, 0, 1)
    state.slip_amount += (slip_target - state.slip_amount) * clamp(8 * dt, 0, 1)
    state.velocity.x = forward_x * longitudinal + right_x * lateral
    state.velocity.z = forward_z * longitudinal + right_z * lateral
    vehicle.position.x += state.velocity.x * dt
    vehicle.position.z += state.velocity.z * dt
    vehicle.position.y = ground_height

    acceleration := (longitudinal - longitudinal_before) / max(dt, f32(.001))
    acceleration_target := clamp(acceleration / max(tune.acceleration, f32(1)), -1, 1)
    state.acceleration_feedback += (acceleration_target - state.acceleration_feedback) * clamp(6 * dt, 0, 1)
    roll_target :=
        -state.steering *
        clamp(math.abs(longitudinal) / tune.max_forward, 0, 1) *
        (.07 + state.handbrake_amount * .035)
    pitch_target := state.acceleration_feedback * .045
    state.body_roll += (roll_target - state.body_roll) * clamp(7 * dt, 0, 1)
    state.body_pitch += (pitch_target - state.body_pitch) * clamp(6 * dt, 0, 1)
}

car_trailer_angle_delta :: proc(current, target: f32) -> f32 {
    delta := target - current
    for delta > math.PI do delta -= math.PI * 2
    for delta < -math.PI do delta += math.PI * 2
    return delta
}

// car_trailer_step advances a lightweight planar rigid body. While coupled, the
// tow ball is a positional constraint and the trailer's passive axle determines
// its yaw. This is deliberately different from steering the trailer toward the
// car's yaw: a real trailer follows the tow-ball path and naturally cuts inside
// a corner. Once detached, the same body coasts with axle drag.
car_trailer_step :: proc(
    state: ^Car_Trailer_State,
    position: ^third_person.Vec3,
    yaw: ^f32,
    car_position: third_person.Vec3,
    car_yaw, car_yaw_rate: f32,
    car_velocity: third_person.Vec3,
    attached: bool,
    ground_height, delta_seconds: f32,
) {
    if state == nil || position == nil || yaw == nil || delta_seconds <= 0 do return
    dt := min(delta_seconds, f32(.05))
    velocity_before := state.velocity
    if attached {
        car_cos, car_sin := math.cos(car_yaw), math.sin(car_yaw)
        car_hitch_distance := f32(1.48)
        trailer_hitch_distance := f32(1.36)
        hitch_x := car_position.x - car_cos * car_hitch_distance
        hitch_z := car_position.z - car_sin * car_hitch_distance

        forward_x, forward_z := math.cos(yaw^), math.sin(yaw^)
        right_x, right_z := -forward_z, forward_x
        // Include the tow ball's velocity around the car. Its lateral motion,
        // rather than the car body angle, is what rotates a passive trailer.
        hitch_velocity_x := car_velocity.x + car_yaw_rate * car_hitch_distance * car_sin
        hitch_velocity_z := car_velocity.z - car_yaw_rate * car_hitch_distance * car_cos
        hitch_longitudinal := hitch_velocity_x * forward_x + hitch_velocity_z * forward_z
        hitch_lateral := hitch_velocity_x * right_x + hitch_velocity_z * right_z

        // The authored trailer origin faces away from its tow ball, so lateral
        // tow-ball travel produces yaw with this sign. A small relaxation filters
        // frame-to-frame input noise without adding a second spring that can fight
        // the hitch constraint.
        target_yaw_rate := clamp(hitch_lateral / trailer_hitch_distance, f32(-1.8), f32(1.8))
        state.yaw_rate += (target_yaw_rate - state.yaw_rate) * clamp(12 * dt, 0, 1)
        yaw^ += state.yaw_rate * dt

        // Rebuild the trailer pose from the single, exact tow-ball constraint.
        // This removes the visible stretch/bounce produced by a stiff center
        // spring and remains stable across ordinary frame-rate variations.
        forward_x, forward_z = math.cos(yaw^), math.sin(yaw^)
        desired_x := hitch_x + forward_x * trailer_hitch_distance
        desired_z := hitch_z + forward_z * trailer_hitch_distance
        state.velocity.x = (desired_x - position.x) / dt
        state.velocity.z = (desired_z - position.z) / dt
        position.x = desired_x
        position.z = desired_z

        // Rolling drag is reported back to the arcade car without disturbing
        // the constrained trailer pose.
        rolling_load := hitch_longitudinal * .11
        state.reaction_force = {
            -forward_x * rolling_load,
            0,
            -forward_z * rolling_load,
        }
    } else {
        state.reaction_force = {}
        // Passive axle friction: retain forward roll, scrub lateral motion.
        forward_x, forward_z := math.cos(yaw^), math.sin(yaw^)
        right_x, right_z := -forward_z, forward_x
        longitudinal := state.velocity.x * forward_x + state.velocity.z * forward_z
        lateral := state.velocity.x * right_x + state.velocity.z * right_z
        longitudinal *= 1 - clamp(1.15 * dt, 0, .8)
        lateral *= 1 - clamp(5.5 * dt, 0, .9)
        state.velocity.x = forward_x * longitudinal + right_x * lateral
        state.velocity.z = forward_z * longitudinal + right_z * lateral
        state.yaw_rate *= 1 - clamp(1.8 * dt, 0, .8)
        yaw^ += state.yaw_rate * dt
    }

    acceleration_x := (state.velocity.x - velocity_before.x) / max(dt, f32(.001))
    acceleration_z := (state.velocity.z - velocity_before.z) / max(dt, f32(.001))
    forward_x, forward_z := math.cos(yaw^), math.sin(yaw^)
    longitudinal_speed := state.velocity.x * forward_x + state.velocity.z * forward_z
    state.wheel_rotation += longitudinal_speed * dt / .25
    longitudinal_acceleration := acceleration_x * forward_x + acceleration_z * forward_z
    pitch_target := attached ? clamp(-longitudinal_acceleration * .012, -.12, .12) : f32(0)
    roll_target := attached ? clamp(-state.yaw_rate * longitudinal_speed * .018, -.14, .14) : f32(0)
    state.body_pitch += (pitch_target - state.body_pitch) * clamp(8 * dt, 0, 1)
    state.body_roll += (roll_target - state.body_roll) * clamp(9 * dt, 0, 1)

    if !attached {
        position.x += state.velocity.x * dt
        position.z += state.velocity.z * dt
    }
    position.y = ground_height
    state.velocity.y = 0
}
