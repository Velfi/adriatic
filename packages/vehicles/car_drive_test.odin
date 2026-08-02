package vehicles

import "core:testing"

@(test)
racer_arcade_preserves_calm_straight_line :: proc(t: ^testing.T) {
    runtime: Car_Racer_Runtime
    assist := car_racer_arcade_assist(&runtime, 0, 18, 0, 0, false, 1.0 / 60)
    testing.expect_value(t, assist.steering, f32(0))
    testing.expect_value(t, assist.drift_amount, f32(0))
    testing.expect_value(t, assist.rear_grip_scale, f32(1))
    testing.expect_value(t, assist.target_lateral_velocity, f32(0))
}

@(test)
racer_arcade_brake_and_steer_opens_drift :: proc(t: ^testing.T) {
    runtime: Car_Racer_Runtime
    assist: Car_Racer_Assist
    for _ in 0 ..< 12 {
        assist = car_racer_arcade_assist(&runtime, .8, 18, 0, 1, false, 1.0 / 60)
    }
    testing.expect(t, assist.drift_amount > .7)
    testing.expect(t, assist.rear_grip_scale < .5)
    testing.expect(t, assist.target_lateral_velocity > 0)
}

@(test)
racer_arcade_handbrake_opens_drift_without_brake :: proc(t: ^testing.T) {
    runtime: Car_Racer_Runtime
    assist: Car_Racer_Assist
    for _ in 0 ..< 12 {
        assist = car_racer_arcade_assist(&runtime, -.7, 14, 0, 0, true, 1.0 / 60)
    }
    testing.expect(t, assist.drift_amount > .5)
    testing.expect(t, assist.target_lateral_velocity < 0)
}

@(test)
racer_arcade_slip_sustains_after_brake_release :: proc(t: ^testing.T) {
    runtime := Car_Racer_Runtime{drift_amount = .8}
    assist := car_racer_arcade_assist(&runtime, .55, 18, 2.6, 0, false, 1.0 / 60)
    testing.expect(t, assist.drift_amount > .78)
    testing.expect(t, assist.rear_grip_scale < .5)
}

@(test)
racer_arcade_countersteer_releases_drift :: proc(t: ^testing.T) {
    runtime := Car_Racer_Runtime{drift_amount = .8}
    for _ in 0 ..< 30 {
        _ = car_racer_arcade_assist(&runtime, -.5, 18, 2.6, 0, false, 1.0 / 60)
    }
    testing.expect(t, runtime.drift_amount < .2)
}
