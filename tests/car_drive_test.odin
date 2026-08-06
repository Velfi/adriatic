package tests

import third_person "zelda_engine:third_person"
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
        velocity    = {12, 0, 5},
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
car_drive_arcade_input_has_precise_center_and_full_lock :: proc(t: ^testing.T) {
    testing.expect(t, vehicles.car_drive_arcade_steering(.25) > 0)
    testing.expect(t, vehicles.car_drive_arcade_steering(.25) < .25)
    testing.expect(t, vehicles.car_drive_arcade_steering(1) == 1)
    testing.expect(t, vehicles.car_drive_arcade_steering(-1) == -1)
}

@(test)
car_drive_physics_steering_loses_lock_at_speed_and_in_reverse :: proc(t: ^testing.T) {
    tune := vehicles.CAR_DRIVE_SEDAN_TUNE
    town := vehicles.car_drive_speed_sensitive_steering(1, 6, tune)
    fast := vehicles.car_drive_speed_sensitive_steering(1, tune.max_forward, tune)
    reverse := vehicles.car_drive_speed_sensitive_steering(1, -6, tune)
    testing.expect(t, town > fast)
    testing.expect(t, math.abs(fast - tune.high_speed_steering) < .001)
    testing.expect(t, reverse < town)
    testing.expect(t, vehicles.car_drive_speed_sensitive_steering(.25, 0, tune) < .25)
}

@(test)
car_drive_slip_telemetry_measures_angle_not_absolute_side_speed :: proc(t: ^testing.T) {
    testing.expect(t, vehicles.car_drive_slip_angle_amount(10, 0) == 0)
    testing.expect(t, math.abs(vehicles.car_drive_slip_angle_amount(1, 1) - 1) < .001)
    testing.expect(t, vehicles.car_drive_slip_angle_amount(4, 2) > vehicles.car_drive_slip_angle_amount(16, 2))
    testing.expect(t, vehicles.car_drive_slip_angle_amount(0, 20) == 1)
}

@(test)
car_drive_arcade_turning_is_quick_in_town_and_stable_at_speed :: proc(t: ^testing.T) {
    tune := vehicles.CAR_DRIVE_SEDAN_TUNE
    crawl_rate := math.abs(vehicles.car_drive_target_yaw_rate(1, 2, 0, tune))
    town_rate := math.abs(vehicles.car_drive_target_yaw_rate(1, 7, 0, tune))
    high_speed_rate := math.abs(vehicles.car_drive_target_yaw_rate(1, tune.max_forward, 0, tune))
    testing.expect(t, town_rate > crawl_rate)
    testing.expect(t, high_speed_rate < town_rate)
    testing.expect(t, high_speed_rate <= tune.max_yaw_rate * tune.high_speed_steering + .001)
}

@(test)
car_drive_cannot_pivot_and_reverse_steering_is_tamer :: proc(t: ^testing.T) {
    forward_rate := vehicles.car_drive_target_yaw_rate(1, 5, 0)
    reverse_rate := vehicles.car_drive_target_yaw_rate(1, -5, 0)
    testing.expect(t, vehicles.car_drive_target_yaw_rate(1, 0, 0) == 0)
    testing.expect(t, forward_rate > 0)
    testing.expect(t, reverse_rate < 0)
    testing.expect(t, math.abs(reverse_rate) < forward_rate)
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

@(test)
car_drive_surface_grip_changes_acceleration_and_lateral_slip :: proc(t: ^testing.T) {
    asphalt_car := vehicles.default_vehicle({})
    loose_car := vehicles.default_vehicle({})
    asphalt: vehicles.Car_Drive_State
    loose: vehicles.Car_Drive_State
    asphalt_surface := vehicles.CAR_DRIVE_DEFAULT_SURFACE
    loose_surface := vehicles.Car_Drive_Surface {
        longitudinal_grip  = .54,
        lateral_grip       = .46,
        rolling_resistance = 1.4,
    }

    for _ in 0 ..< 90 {
        vehicles.car_drive_step(&asphalt, &asphalt_car, {throttle = 1}, 0, 1.0 / 60, asphalt_surface)
        vehicles.car_drive_step(&loose, &loose_car, {throttle = 1}, 0, 1.0 / 60, loose_surface)
    }

    testing.expect(t, vehicles.car_drive_speed(asphalt) > vehicles.car_drive_speed(loose))
    testing.expect(t, loose.slip_amount > asphalt.slip_amount)
    testing.expect(t, loose.surface_lateral_grip < asphalt.surface_lateral_grip)

    asphalt_slide_car := vehicles.default_vehicle({})
    loose_slide_car := vehicles.default_vehicle({})
    asphalt_slide := vehicles.Car_Drive_State {
        velocity    = {8, 0, 4},
        wheel_speed = 8,
    }
    loose_slide := asphalt_slide
    for _ in 0 ..< 30 {
        vehicles.car_drive_step(&asphalt_slide, &asphalt_slide_car, {}, 0, 1.0 / 60, asphalt_surface)
        vehicles.car_drive_step(&loose_slide, &loose_slide_car, {}, 0, 1.0 / 60, loose_surface)
    }
    testing.expect(t, math.abs(loose_slide.velocity.z) > math.abs(asphalt_slide.velocity.z))
}

@(test)
car_drive_smooths_surface_transitions :: proc(t: ^testing.T) {
    car := vehicles.default_vehicle({})
    state: vehicles.Car_Drive_State
    for _ in 0 ..< 30 {
        vehicles.car_drive_step(&state, &car, {throttle = 1}, 0, 1.0 / 60)
    }
    before := state.surface_lateral_grip
    dirt := vehicles.Car_Drive_Surface {
        longitudinal_grip  = .62,
        lateral_grip       = .54,
        rolling_resistance = 1.3,
    }
    vehicles.car_drive_step(&state, &car, {throttle = 1}, 0, 1.0 / 60, dirt)
    testing.expect(t, state.surface_lateral_grip < before)
    testing.expect(t, state.surface_lateral_grip > dirt.lateral_grip)
}

@(test)
car_trailer_keeps_the_tow_ball_connected_without_spring_bounce :: proc(t: ^testing.T) {
    state: vehicles.Car_Trailer_State
    position := vehicles.car_spawn_near({})
    position.x = -2.84
    yaw: f32
    car_position := position
    car_position.x = 2.84

    for _ in 0 ..< 120 {
        car_position.x += 8.0 / 60
        vehicles.car_trailer_step(&state, &position, &yaw, car_position, 0, 0, {8, 0, 0}, true, 0, 1.0 / 60)
        car_hitch_x := car_position.x - 1.48
        trailer_hitch_x := position.x - math.cos(yaw) * 1.36
        trailer_hitch_z := position.z - math.sin(yaw) * 1.36
        testing.expect(t, math.abs(car_hitch_x - trailer_hitch_x) < .001)
        testing.expect(t, math.abs(car_position.z - trailer_hitch_z) < .001)
    }
    testing.expect(t, math.abs(yaw) < .001)
}

@(test)
car_trailer_turns_from_tow_ball_motion_and_cuts_inside :: proc(t: ^testing.T) {
    state: vehicles.Car_Trailer_State
    car_position := vehicles.car_spawn_near({})
    car_yaw: f32
    yaw: f32
    position := car_position
    position.x = car_position.x - 1.48 + 1.36
    speed := f32(7)
    yaw_rate := f32(.55)

    for _ in 0 ..< 90 {
        car_yaw += yaw_rate / 60
        car_velocity := third_person.Vec3{math.cos(car_yaw) * speed, 0, math.sin(car_yaw) * speed}
        car_position.x += car_velocity.x / 60
        car_position.z += car_velocity.z / 60
        vehicles.car_trailer_step(
            &state,
            &position,
            &yaw,
            car_position,
            car_yaw,
            yaw_rate,
            car_velocity,
            true,
            0,
            1.0 / 60,
        )
    }

    testing.expect(t, yaw > 0)
    testing.expect(t, yaw < car_yaw)
    testing.expect(t, car_yaw - yaw < 1.15)
}
