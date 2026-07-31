package rondine

import flight "../flight"
import "core:math"
import "core:math/linalg"
import "core:testing"

@(test)
rondine_turns_and_generates_asymmetric_wake :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE, 0})
    initial_basis := flight.basis_from_orientation(runtime.body.orientation)
    initial_forward := initial_basis.forward
    initial_right := initial_basis.right
    for _ in 0 ..< 600 {
        step(&runtime, {throttle_up = true, roll = 1}, 0, 1.0 / 120.0)
    }
    testing.expect(t, runtime.telemetry.speed > 25)
    testing.expect(t, math.abs(runtime.telemetry.turn_rate) > .01)
    testing.expect(t, runtime.telemetry.turn_rate < 0)
    basis := flight.basis_from_orientation(runtime.body.orientation)
    testing.expect(
        t,
        basis.forward.x * initial_right.x + basis.forward.z * initial_right.z >
        initial_forward.x * initial_right.x + initial_forward.z * initial_right.z,
    )
    testing.expect(t, runtime.wake_count > 0)
    testing.expect(t, runtime.wake[runtime.wake_count - 1].turn > .5)
}

@(test)
rondine_assisted_height_stays_in_ground_effect :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE, 0})
    for _ in 0 ..< 1800 {
        step(&runtime, {throttle_up = true}, 0, 1.0 / 120.0)
    }
    testing.expect(t, runtime.telemetry.speed > 60)
    testing.expect(t, runtime.telemetry.height > 2)
    testing.expect(t, runtime.telemetry.height < 4)
    testing.expect(t, runtime.telemetry.spray_intensity < .02)
    testing.expect(t, runtime.telemetry.speed <= runtime.tuning.maximum_speed + .01)
}

@(test)
rondine_responds_gradually_to_crosswind :: proc(t: ^testing.T) {
    calm := new_runtime({0, GROUND_CLEARANCE, 0})
    windy := calm
    for _ in 0 ..< 240 {
        step(&calm, {}, 0, 1.0 / 120.0)
        step(&windy, {}, 0, 1.0 / 120.0, {0, 0, 12})
    }
    testing.expect(t, windy.body.position.z > calm.body.position.z + 1)
    testing.expect(t, windy.body.velocity.z > calm.body.velocity.z)
    testing.expect(t, windy.body.velocity.z < 12)
}

@(test)
rondine_speed_cap_and_telemetry_are_air_relative :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE + 10, 0})
    runtime.grounded = false
    basis := flight.basis_from_orientation(runtime.body.orientation)
    wind := basis.forward * 18
    runtime.body.velocity = wind + basis.forward * (runtime.tuning.maximum_speed + 20)

    step(&runtime, {}, 0, 1.0 / 120.0, wind)

    air_velocity := runtime.body.velocity - wind
    testing.expect(t, linalg.length(air_velocity) <= runtime.tuning.maximum_speed + .01)
    testing.expect(t, runtime.telemetry.speed <= runtime.tuning.maximum_speed + .01)
    testing.expect(t, linalg.length(runtime.body.velocity) > runtime.telemetry.speed + 10)
}

@(test)
rondine_contact_spray_peaks_before_liftoff :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE, 0})
    for _ in 0 ..< 300 {
        step(&runtime, {throttle_up = true}, 0, 1.0 / 120.0)
    }
    testing.expect(t, runtime.grounded)
    testing.expect(t, runtime.telemetry.speed > 8)
    testing.expect(t, runtime.telemetry.spray_intensity > .1)
}

@(test)
rondine_propeller_phase_tracks_power_and_reset :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE, 0})
    for _ in 0 ..< 30 {
        step(&runtime, {throttle_up = true}, 0, 1.0 / 120.0)
    }
    testing.expect(t, runtime.throttle > 0)
    testing.expect(t, runtime.propeller_turns > 0)
    testing.expect(t, runtime.propeller_turns < 1)
    reset(&runtime, 0)
    testing.expect_value(t, runtime.propeller_turns, f32(0))
}

@(test)
rondine_hard_surface_turn_breaks_into_a_drift :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE, 0})
    runtime.tuning.takeoff_speed = 200
    for _ in 0 ..< 720 {
        step(&runtime, {throttle_up = true, roll = 1}, 0, 1.0 / 120.0)
    }
    testing.expect(t, runtime.grounded)
    testing.expect(t, runtime.telemetry.speed > 25)
    testing.expect(t, runtime.telemetry.drift_intensity > .35)
    testing.expect(t, math.abs(runtime.telemetry.lateral_speed) > 3)
    testing.expect(t, runtime.telemetry.wake_intensity > .5)
}

@(test)
rondine_drift_hooks_up_when_the_pilot_straightens :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE, 0})
    runtime.tuning.takeoff_speed = 200
    for _ in 0 ..< 540 {
        step(&runtime, {throttle_up = true, roll = 1}, 0, 1.0 / 120.0)
    }
    peak_drift := runtime.telemetry.drift_intensity
    peak_hookup := f32(0)
    recorded_hookup := false
    for _ in 0 ..< 360 {
        step(&runtime, {throttle_up = true}, 0, 1.0 / 120.0)
        peak_hookup = max(peak_hookup, runtime.telemetry.hookup_kick)
        if runtime.wake_count > 0 && runtime.wake[runtime.wake_count - 1].hookup > .1 {
            recorded_hookup = true
        }
    }
    testing.expect(t, peak_drift > .35)
    testing.expect(t, peak_hookup > .2)
    testing.expect(t, recorded_hookup)
    testing.expect(t, runtime.telemetry.drift_intensity < peak_drift * .35)
    testing.expect(t, runtime.telemetry.hookup_kick < peak_hookup * .1)
}

@(test)
rondine_countersteer_reads_only_when_input_opposes_established_slip :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE, 0})
    runtime.tuning.takeoff_speed = 200
    for _ in 0 ..< 540 {
        step(&runtime, {throttle_up = true, roll = 1}, 0, 1.0 / 120.0)
    }
    testing.expect(t, runtime.telemetry.drift_intensity > .35)
    testing.expect(t, runtime.telemetry.countersteer < .02)
    peak_countersteer := f32(0)
    recorded_countersteer := false
    for _ in 0 ..< 90 {
        step(&runtime, {throttle_up = true, roll = -1}, 0, 1.0 / 120.0)
        peak_countersteer = max(peak_countersteer, runtime.telemetry.countersteer)
        if runtime.wake_count > 0 && runtime.wake[runtime.wake_count - 1].countersteer > .1 {
            recorded_countersteer = true
        }
    }
    testing.expect(t, peak_countersteer > .2)
    testing.expect(t, recorded_countersteer)

    mirrored := new_runtime({0, GROUND_CLEARANCE, 0})
    mirrored.tuning.takeoff_speed = 200
    for _ in 0 ..< 540 {
        step(&mirrored, {throttle_up = true, roll = -1}, 0, 1.0 / 120.0)
    }
    testing.expect(t, mirrored.telemetry.drift_intensity > .35)
    testing.expect(t, mirrored.telemetry.countersteer < .02)
    mirrored_peak := f32(0)
    for _ in 0 ..< 90 {
        step(&mirrored, {throttle_up = true, roll = 1}, 0, 1.0 / 120.0)
        mirrored_peak = max(mirrored_peak, mirrored.telemetry.countersteer)
    }
    testing.expect(t, mirrored_peak > .2)
    testing.expect(t, math.abs(peak_countersteer - mirrored_peak) < .08)
}

@(test)
rondine_wake_samples_keep_stable_serials_when_the_buffer_rolls :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE, 0})
    runtime.tuning.takeoff_speed = 200
    for _ in 0 ..< 3000 {
        step(&runtime, {throttle_up = true, roll = .7}, 0, 1.0 / 120.0)
    }
    testing.expect(t, runtime.wake_serial > MAX_WAKE_SAMPLES)
    testing.expect(t, runtime.wake_count > 1)
    testing.expect(t, runtime.wake_count <= MAX_WAKE_SAMPLES)
    for index in 1 ..< runtime.wake_count {
        testing.expect(t, runtime.wake[index - 1].serial < runtime.wake[index].serial)
    }
    testing.expect_value(t, runtime.wake[runtime.wake_count - 1].serial, runtime.wake_serial)
    reset(&runtime, 0)
    testing.expect_value(t, runtime.wake_serial, u32(0))
}

@(test)
rondine_wake_spacing_stays_uniform_at_low_frame_rates :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE, 0})
    runtime.tuning.takeoff_speed = 200
    for _ in 0 ..< 600 {
        step(&runtime, {throttle_up = true, roll = .45}, 0, .05)
    }
    testing.expect(t, runtime.wake_count > 2)
    for index in 1 ..< runtime.wake_count {
        delta := runtime.wake[index].position - runtime.wake[index - 1].position
        distance := f32(math.sqrt(f64(delta.x * delta.x + delta.z * delta.z)))
        testing.expect(t, distance > .65)
        testing.expect(t, distance < 1.65)
    }
}

@(test)
rondine_drift_kick_spikes_on_breakaway_and_decays :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE, 0})
    runtime.tuning.takeoff_speed = 200
    for _ in 0 ..< 520 {
        step(&runtime, {throttle_up = true}, 0, 1.0 / 120.0)
    }
    peak_kick := f32(0)
    for _ in 0 ..< 180 {
        step(&runtime, {throttle_up = true, roll = 1}, 0, 1.0 / 120.0)
        peak_kick = max(peak_kick, runtime.telemetry.drift_kick)
    }
    testing.expect(t, runtime.telemetry.drift_intensity > .35)
    testing.expect(t, peak_kick > .25)
    kick_markers := 0
    for sample in runtime.wake[:runtime.wake_count] {
        if sample.kick > 0 do kick_markers += 1
    }
    testing.expect_value(t, kick_markers, 1)
    for frame in 0 ..< 48 {
        jitter_roll := f32(1)
        if frame % 16 < 8 do jitter_roll = .82
        step(&runtime, {throttle_up = true, roll = jitter_roll}, 0, 1.0 / 120.0)
    }
    kick_markers = 0
    for sample in runtime.wake[:runtime.wake_count] {
        if sample.kick > 0 do kick_markers += 1
    }
    testing.expect_value(t, kick_markers, 1)
    for _ in 0 ..< 180 {
        step(&runtime, {throttle_up = true, roll = 1}, 0, 1.0 / 120.0)
    }
    testing.expect(t, runtime.telemetry.drift_kick < peak_kick * .2)
}

@(test)
rondine_airborne_drift_loss_does_not_trigger_hookup_spray :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE, 0})
    runtime.tuning.takeoff_speed = 200
    for _ in 0 ..< 540 {
        step(&runtime, {throttle_up = true, roll = 1}, 0, 1.0 / 120.0)
    }
    testing.expect(t, runtime.telemetry.drift_intensity > .35)
    runtime.body.position.y = GROUND_CLEARANCE + 4
    runtime.drift_kick = 1
    runtime.hookup_kick = 0
    runtime.telemetry.drift_kick = 1
    runtime.telemetry.hookup_kick = 0
    step(&runtime, {throttle_up = true}, 0, 1.0 / 120.0)
    testing.expect_value(t, runtime.telemetry.drift_kick, f32(0))
    testing.expect_value(t, runtime.telemetry.hookup_kick, f32(0))
}

@(test)
rondine_surface_impact_is_sampled_on_landing_and_decays :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE, 0})
    runtime.tuning.takeoff_speed = 200
    runtime.body.position.y = GROUND_CLEARANCE + .2
    runtime.body.velocity = flight.basis_from_orientation(runtime.body.orientation).forward * 35
    runtime.body.velocity.y = -8
    runtime.grounded = false
    runtime.wake_distance = 1.2
    step(&runtime, {throttle_up = true}, 0, .05)
    testing.expect(t, runtime.grounded)
    testing.expect(t, runtime.telemetry.surface_impact > .5)
    testing.expect(t, runtime.wake_count > 0)
    initial_impact_markers := 0
    for sample in runtime.wake[:runtime.wake_count] {
        if sample.impact > .5 do initial_impact_markers += 1
    }
    testing.expect_value(t, initial_impact_markers, 1)
    peak_impact := runtime.telemetry.surface_impact
    for _ in 0 ..< 24 {
        step(&runtime, {throttle_up = true}, 0, 1.0 / 120.0)
    }
    impact_markers := 0
    for sample in runtime.wake[:runtime.wake_count] {
        if sample.impact > 0 do impact_markers += 1
    }
    testing.expect_value(t, impact_markers, 1)
    for _ in 0 ..< 96 {
        step(&runtime, {throttle_up = true}, 0, 1.0 / 120.0)
    }
    testing.expect(t, runtime.telemetry.surface_impact < peak_impact * .08)
}

@(test)
rondine_surface_release_is_sampled_once_on_liftoff_and_decays :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE, 0})
    runtime.tuning.takeoff_speed = 200
    for _ in 0 ..< 480 {
        step(&runtime, {throttle_up = true}, 0, 1.0 / 120.0)
    }
    testing.expect(t, runtime.grounded)
    runtime.tuning.takeoff_speed = 22
    peak_release := f32(0)
    for _ in 0 ..< 36 {
        step(&runtime, {throttle_up = true}, 0, 1.0 / 120.0)
        peak_release = max(peak_release, runtime.telemetry.surface_release)
    }
    testing.expect(t, !runtime.grounded)
    testing.expect(t, peak_release > .35)
    release_markers := 0
    for sample in runtime.wake[:runtime.wake_count] {
        if sample.release > 0 do release_markers += 1
    }
    testing.expect_value(t, release_markers, 1)
    for _ in 0 ..< 72 {
        step(&runtime, {throttle_up = true}, 0, 1.0 / 120.0)
    }
    release_markers = 0
    for sample in runtime.wake[:runtime.wake_count] {
        if sample.release > 0 do release_markers += 1
    }
    testing.expect_value(t, release_markers, 1)
    testing.expect(t, runtime.telemetry.surface_release < peak_release * .16)
}

@(test)
rondine_surface_surge_tracks_acceleration_and_retires_at_cruise :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE, 0})
    runtime.tuning.takeoff_speed = 200
    peak_surge := f32(0)
    for _ in 0 ..< 2400 {
        step(&runtime, {throttle_up = true}, 0, 1.0 / 120.0)
        peak_surge = max(peak_surge, runtime.telemetry.surge_intensity)
    }
    testing.expect(t, peak_surge > .55)
    testing.expect(t, runtime.telemetry.speed > 60)
    testing.expect(t, runtime.telemetry.acceleration < 2.5)
    testing.expect(t, runtime.telemetry.surge_intensity < peak_surge * .22)
}

@(test)
rondine_surface_brake_tracks_deceleration_and_retires :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE, 0})
    runtime.tuning.takeoff_speed = 200
    for _ in 0 ..< 600 {
        step(&runtime, {throttle_up = true}, 0, 1.0 / 120.0)
    }
    peak_brake := f32(0)
    lowest_acceleration := f32(0)
    for _ in 0 ..< 90 {
        step(&runtime, {throttle_down = true}, 0, 1.0 / 120.0)
        peak_brake = max(peak_brake, runtime.telemetry.brake_intensity)
        lowest_acceleration = min(lowest_acceleration, runtime.telemetry.acceleration)
    }
    testing.expect(t, peak_brake > .45)
    testing.expect(t, lowest_acceleration < -4)
    for _ in 0 ..< 240 {
        step(&runtime, {}, 0, 1.0 / 120.0)
    }
    testing.expect(t, runtime.telemetry.brake_intensity < peak_brake * .2)
}

@(test)
rondine_brake_flick_combines_deceleration_and_steering :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE, 0})
    runtime.tuning.takeoff_speed = 200
    for _ in 0 ..< 600 {
        step(&runtime, {throttle_up = true}, 0, 1.0 / 120.0)
    }
    for _ in 0 ..< 42 {
        step(&runtime, {throttle_down = true, roll = 1}, 0, 1.0 / 120.0)
    }
    testing.expect(t, runtime.telemetry.brake_intensity > .45)
    testing.expect(t, math.abs(runtime.steering) > .2)
    testing.expect(t, runtime.telemetry.drift_intensity > .12)
}

@(test)
rondine_power_over_combines_acceleration_and_drift :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE, 0})
    runtime.tuning.takeoff_speed = 200
    for _ in 0 ..< 260 {
        step(&runtime, {throttle_up = true}, 0, 1.0 / 120.0)
    }
    peak_power_over := f32(0)
    for _ in 0 ..< 72 {
        step(&runtime, {throttle_up = true, roll = 1}, 0, 1.0 / 120.0)
        peak_power_over = max(peak_power_over, runtime.telemetry.surge_intensity * runtime.telemetry.drift_intensity)
    }
    testing.expect(t, runtime.telemetry.acceleration > 4)
    testing.expect(t, runtime.telemetry.drift_intensity > .2)
    testing.expect(t, peak_power_over > .12)
}

@(test)
rondine_switchback_pulses_when_loaded_slip_changes_side :: proc(t: ^testing.T) {
    runtime := new_runtime({0, GROUND_CLEARANCE, 0})
    runtime.tuning.takeoff_speed = 200
    for _ in 0 ..< 540 {
        step(&runtime, {throttle_up = true, roll = 1}, 0, 1.0 / 120.0)
    }
    initial_side := runtime.slip_side
    peak_transition := f32(0)
    marker_serial: u32
    marker_x, marker_z: f32
    for _ in 0 ..< 360 {
        step(&runtime, {throttle_up = true, roll = -1}, 0, 1.0 / 120.0)
        peak_transition = max(peak_transition, runtime.telemetry.drift_transition)
        for sample in runtime.wake[:runtime.wake_count] {
            if sample.transition <= 0 do continue
            marker_serial = sample.serial
            marker_x = sample.position.x
            marker_z = sample.position.z
            break
        }
        if marker_serial != 0 do break
    }
    testing.expect(t, initial_side != 0)
    testing.expect(t, runtime.slip_side == -initial_side)
    testing.expect(t, peak_transition > .5)
    testing.expect(t, marker_serial != 0)
    marker_count := 0
    for sample in runtime.wake[:runtime.wake_count] {
        if sample.transition > 0 do marker_count += 1
    }
    testing.expect_value(t, marker_count, 1)
    for _ in 0 ..< 30 {
        step(&runtime, {throttle_up = true, roll = -1}, 0, 1.0 / 120.0)
    }
    marker_found := false
    for sample in runtime.wake[:runtime.wake_count] {
        if sample.serial != marker_serial do continue
        marker_found = true
        testing.expect(t, math.abs(sample.position.x - marker_x) < .0001)
        testing.expect(t, math.abs(sample.position.z - marker_z) < .0001)
    }
    testing.expect(t, marker_found)
    for _ in 0 ..< 300 {
        step(&runtime, {throttle_up = true}, 0, 1.0 / 120.0)
    }
    testing.expect(t, runtime.telemetry.drift_transition < peak_transition * .15)
}

@(test)
rondine_drift_wake_persists_longer_than_planing_wake :: proc(t: ^testing.T) {
    planing := new_runtime({0, GROUND_CLEARANCE, 0})
    drifting := new_runtime({0, GROUND_CLEARANCE, 0})
    planing.tuning.takeoff_speed = 200
    drifting.tuning.takeoff_speed = 200
    for _ in 0 ..< 720 {
        step(&planing, {throttle_up = true}, 0, 1.0 / 120.0)
        step(&drifting, {throttle_up = true, roll = 1}, 0, 1.0 / 120.0)
    }
    testing.expect(t, planing.wake_count > 0)
    testing.expect(t, drifting.wake_count > 0)
    planing_lifetime := planing.wake[planing.wake_count - 1].lifetime
    drift_lifetime := drifting.wake[drifting.wake_count - 1].lifetime
    testing.expect(t, drift_lifetime > planing_lifetime + .25)
    testing.expect(t, drift_lifetime <= 2.75)
}
