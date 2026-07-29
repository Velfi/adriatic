package tests

import third_person "../packages/third_person"
import "core:math"
import "core:testing"

horizontal_speed :: proc(state: third_person.State) -> f32 {
    return math.sqrt(state.velocity.x * state.velocity.x + state.velocity.z * state.velocity.z)
}

absolute :: proc(value: f32) -> f32 {
    if value < 0 do return -value
    return value
}

@(test)
third_person_moves_relative_to_the_camera :: proc(t: ^testing.T) {
    state := third_person.State{}
    config := third_person.default_config()
    third_person.step(&state, {move_y = 1, grounded = true}, config, 1.0 / 6.0)
    testing.expect(t, state.velocity.z < 0 && state.position.z < 0)
    testing.expect(t, state.facing_yaw_radians == 0)
}

@(test)
third_person_accelerates_and_coasts_with_weight :: proc(t: ^testing.T) {
    state := third_person.State{}
    config := third_person.default_config()
    third_person.step(&state, {move_y = 1, grounded = true}, config, .1)
    testing.expect(t, absolute(horizontal_speed(state) - config.ground_acceleration * .1) < .001)

    state.velocity.z = -config.move_speed
    third_person.step(&state, {grounded = true, ground_normal = {0, 1, 0}}, config, .1)
    testing.expect(t, state.velocity.z > -config.move_speed && state.velocity.z < 0)
    testing.expect(t, state.brake_amount > .9)
}

@(test)
third_person_carves_at_speed_and_limits_facing_rate :: proc(t: ^testing.T) {
    state := third_person.State {
        velocity = {0, 0, -6},
    }
    left := third_person.State {
        velocity = {0, 0, -6},
    }
    config := third_person.default_config()
    third_person.step(&state, {move_x = 1, grounded = true, ground_normal = {0, 1, 0}}, config, .1)
    testing.expect(t, state.velocity.x > 0 && state.velocity.z < 0)
    testing.expect(t, state.turn_amount > 0)
    testing.expect(t, absolute(state.facing_yaw_radians) <= config.facing_turn_speed * .1 + .001)
    testing.expect(t, horizontal_speed(state) <= config.move_speed + .001)

    third_person.step(&left, {move_x = -1, grounded = true, ground_normal = {0, 1, 0}}, config, .1)
    testing.expect(t, left.turn_amount < 0)
}

@(test)
third_person_shift_run_builds_speed_and_drifts_through_turns :: proc(t: ^testing.T) {
    config := third_person.default_config()
    accelerating := third_person.State{}
    for _ in 0 ..< 20 {
        accelerating.running = true
        third_person.step(&accelerating, {move_y = 1, grounded = true, ground_normal = {0, 1, 0}}, config, .05)
    }
    testing.expect(t, horizontal_speed(accelerating) > config.move_speed)
    testing.expect(t, horizontal_speed(accelerating) <= config.run_speed + .001)

    drifting := third_person.State {
        velocity = {0, 0, -config.run_speed},
        running  = true,
    }
    third_person.step(&drifting, {move_x = 1, grounded = true, ground_normal = {0, 1, 0}}, config, .1)
    velocity_yaw := math.atan2(-drifting.velocity.x, -drifting.velocity.z)
    testing.expect(t, drifting.velocity.x > 0 && drifting.velocity.z < 0)
    testing.expect(t, absolute(drifting.facing_yaw_radians) > absolute(velocity_yaw))
    testing.expect(t, drifting.turn_amount > .8)
}

@(test)
third_person_run_release_coasts_without_snapping_to_walk_speed :: proc(t: ^testing.T) {
    config := third_person.default_config()
    state := third_person.State {
        velocity = {0, 0, -config.run_speed},
        running  = true,
    }
    third_person.step(
        &state,
        {move_y = 1, run_toggle_pressed = true, grounded = true, ground_normal = {0, 1, 0}},
        config,
        .05,
    )
    testing.expect(t, horizontal_speed(state) < config.run_speed)
    testing.expect(t, horizontal_speed(state) > config.move_speed)
}

@(test)
third_person_run_release_has_a_long_but_bounded_glide :: proc(t: ^testing.T) {
    config := third_person.default_config()
    state := third_person.State {
        velocity = {0, 0, -config.run_speed},
        running  = true,
        grounded = true,
    }
    start_z := state.position.z
    elapsed: f32
    for horizontal_speed(state) > .1 && elapsed < 5 {
        third_person.step(&state, {grounded = true, ground_normal = {0, 1, 0}}, config, 1.0 / 60.0)
        elapsed += 1.0 / 60.0
    }
    glide_distance := start_z - state.position.z
    testing.expect(t, elapsed > 2 && elapsed < 3)
    testing.expect(t, glide_distance > 10.5 && glide_distance < 12.5)
}

@(test)
third_person_speed_hop_charges_drift_and_releases_a_boost :: proc(t: ^testing.T) {
    config := third_person.default_config()
    state := third_person.State {
        velocity = {0, 0, -config.run_speed},
        running  = true,
    }
    third_person.step(
        &state,
        {move_x = .5, move_y = 1, jump_pressed = true, jump_held = true, grounded = true, ground_normal = {0, 1, 0}},
        config,
        .05,
    )
    testing.expect(t, state.drifting)
    testing.expect(t, state.velocity.y == config.jump_speed)

    for _ in 0 ..< 20 {
        third_person.step(
            &state,
            {move_x = .5, move_y = 1, jump_held = true, grounded = true, ground_normal = {0, 1, 0}},
            config,
            .05,
        )
    }
    testing.expect(t, state.drift_charge >= .25)

    third_person.step(&state, {move_y = 1, grounded = true, ground_normal = {0, 1, 0}}, config, .05)
    testing.expect(t, !state.drifting && state.boost_seconds > 0)
    for _ in 0 ..< 8 {
        third_person.step(&state, {move_y = 1, grounded = true, ground_normal = {0, 1, 0}}, config, .05)
    }
    testing.expect(t, horizontal_speed(state) > config.run_speed)
}

@(test)
third_person_normal_jump_does_not_start_a_drift :: proc(t: ^testing.T) {
    state := third_person.State{}
    config := third_person.default_config()
    third_person.step(&state, {move_y = 1, jump_pressed = true, jump_held = true, grounded = true}, config, .05)
    testing.expect(t, !state.drifting && state.boost_seconds == 0)
    testing.expect(t, state.velocity.y == config.jump_speed)
}

@(test)
third_person_run_toggle_latches_and_clears_after_stopping :: proc(t: ^testing.T) {
    config := third_person.default_config()
    state := third_person.State{}
    third_person.step(
        &state,
        {move_y = 1, run_toggle_pressed = true, grounded = true, ground_normal = {0, 1, 0}},
        config,
        .1,
    )
    testing.expect(t, state.running)

    third_person.step(&state, {move_y = 1, grounded = true, ground_normal = {0, 1, 0}}, config, .1)
    testing.expect(t, state.running)

    for state.running {
        third_person.step(&state, {grounded = true, ground_normal = {0, 1, 0}}, config, .1)
    }
    testing.expect(t, horizontal_speed(state) <= .1)
}

@(test)
third_person_brakes_before_reversing_but_pivots_when_slow :: proc(t: ^testing.T) {
    config := third_person.default_config()
    fast := third_person.State {
        velocity = {0, 0, -config.move_speed},
    }
    third_person.step(&fast, {move_y = -1, grounded = true, ground_normal = {0, 1, 0}}, config, .1)
    testing.expect(t, fast.velocity.z < 0 && fast.velocity.z > -config.move_speed)
    testing.expect(t, fast.brake_amount > .9)

    slow := third_person.State {
        velocity = {0, 0, -.5},
    }
    third_person.step(&slow, {move_y = -1, grounded = true, ground_normal = {0, 1, 0}}, config, .1)
    testing.expect(t, slow.velocity.z > 0)
    testing.expect(t, absolute(slow.facing_yaw_radians) > .5)
}

@(test)
third_person_slope_gravity_distinguishes_uphill_and_downhill :: proc(t: ^testing.T) {
    config := third_person.default_config()
    uphill := third_person.State{}
    downhill := third_person.State{}
    // Forward is -Z. A normal tilted toward +Z describes ground rising in
    // that direction, so gravity opposes forward travel.
    third_person.step(&uphill, {move_y = 1, grounded = true, ground_normal = {0, .98, .2}}, config, .2)
    third_person.step(&downhill, {move_y = 1, grounded = true, ground_normal = {0, .98, -.2}}, config, .2)
    testing.expect(t, -downhill.velocity.z > -uphill.velocity.z)
    testing.expect(t, downhill.ground_normal.y > .9)

    invalid := third_person.State{}
    third_person.step(&invalid, {grounded = true, ground_normal = {2, 0, 0}}, config, .1)
    testing.expect(t, invalid.ground_normal.x == 0 && invalid.ground_normal.y == 1)
}

@(test)
third_person_ground_contact_follows_descending_surfaces_without_interrupting_jumps :: proc(t: ^testing.T) {
    grounded := third_person.State {
        position = {0, 4, 0},
        velocity = {0, 0, -3},
        grounded = true,
    }
    third_person.resolve_ground_contact(&grounded, 3.75)
    testing.expect(t, grounded.position.y == 3.75 && grounded.grounded)

    jumping := third_person.State {
        position = {0, 4, 0},
        velocity = {0, 7, -3},
        grounded = false,
    }
    third_person.resolve_ground_contact(&jumping, 3.75)
    testing.expect(t, jumping.position.y == 4 && !jumping.grounded && jumping.velocity.y == 7)

    falling := third_person.State {
        position = {0, 3.5, 0},
        velocity = {0, -4, -3},
    }
    third_person.resolve_ground_contact(&falling, 3.75)
    testing.expect(t, falling.position.y == 3.75 && falling.grounded && falling.velocity.y == 0)
}

@(test)
third_person_motion_signals_decay_without_grounded_forces :: proc(t: ^testing.T) {
    state := third_person.State {
        turn_amount  = 1,
        brake_amount = 1,
    }
    third_person.step(&state, {}, third_person.default_config(), .05)
    testing.expect(t, state.turn_amount < 1 && state.turn_amount >= 0)
    testing.expect(t, state.brake_amount < 1 && state.brake_amount >= 0)
}

@(test)
third_person_fixed_steps_are_consistent_across_frame_rates :: proc(t: ^testing.T) {
    sixty, one_twenty: third_person.State
    config := third_person.default_config()
    for _ in 0 ..< 60 {
        third_person.step(&sixty, {move_y = 1, grounded = true, ground_normal = {0, 1, 0}}, config, 1.0 / 60.0)
    }
    for _ in 0 ..< 120 {
        third_person.step(&one_twenty, {move_y = 1, grounded = true, ground_normal = {0, 1, 0}}, config, 1.0 / 120.0)
    }
    testing.expect(t, absolute(sixty.velocity.z - one_twenty.velocity.z) < .01)
    testing.expect(t, absolute(sixty.position.z - one_twenty.position.z) < .06)
}

@(test)
third_person_camera_stays_above_the_collision_floor :: proc(t: ^testing.T) {
    buried := third_person.Camera_Pose {
        position = {4, -3, 7},
        target   = {1, 2, 3},
    }
    constrained := third_person.camera_above_height(buried, 5, .35)
    testing.expect(t, absolute(constrained.position.y - 5.35) < .001)
    testing.expect(t, constrained.position.x == buried.position.x && constrained.position.z == buried.position.z)
    testing.expect(t, constrained.target == buried.target)

    clear := third_person.Camera_Pose {
        position = {0, 12, 0},
        target   = {0, 2, 0},
    }
    testing.expect(t, third_person.camera_above_height(clear, 5, .35) == clear)
}

@(test)
third_person_normalizes_diagonal_motion_and_jumps :: proc(t: ^testing.T) {
    state := third_person.State{}
    config := third_person.default_config()
    third_person.step(&state, {move_x = 1, move_y = 1, jump_pressed = true, grounded = true}, config, 1.0)
    speed_squared := state.velocity.x * state.velocity.x + state.velocity.z * state.velocity.z
    testing.expect(t, speed_squared <= config.move_speed * config.move_speed + .001)
    testing.expect(t, state.velocity.y == config.jump_speed && !state.grounded)
}

@(test)
third_person_orbit_camera_tracks_character :: proc(t: ^testing.T) {
    camera := third_person.default_camera()
    pose := third_person.camera_pose({2, 3, 4}, camera)
    testing.expect(t, pose.target.x == 2 && pose.target.y == 3 + camera.height && pose.target.z == 4)
    testing.expect(t, pose.position.z > pose.target.z)
}

@(test)
third_person_look_clamps_pitch_and_camera_follow_eases :: proc(t: ^testing.T) {
    camera := third_person.default_camera()
    third_person.look(&camera, 2, 100, .1)
    testing.expect(t, camera.yaw_radians == .2 && camera.pitch_radians == 1.2)
    current := third_person.camera_pose({}, third_person.default_camera())
    desired := third_person.camera_pose({10, 0, 0}, camera)
    next := third_person.follow_camera(current, desired, 5, .1)
    testing.expect(t, next.target == desired.target)
    testing.expect(t, next.position != desired.position)
}

@(test)
third_person_camera_follow_does_not_lag_steady_translation :: proc(t: ^testing.T) {
    camera := third_person.default_camera()
    current := third_person.camera_pose({}, camera)
    desired := third_person.camera_pose({10, 2, -4}, camera)
    next := third_person.follow_camera(current, desired, 8, 1.0 / 60.0)
    current_offset := current.position - current.target
    next_offset := next.position - next.target
    testing.expect(t, next.target == desired.target)
    testing.expect(t, next_offset == current_offset)
}

@(test)
third_person_authored_camera_can_move_near_and_look_at_target :: proc(t: ^testing.T) {
    target := third_person.Vec3{4, 2, -3}
    pose := third_person.camera_near(target, {0, 3, 8})
    testing.expect(t, pose.position.x == target.x && pose.position.y == 5 && pose.position.z == 5)
    testing.expect(t, pose.target.x == 4 && pose.target.y == 2 && pose.target.z == -3)
    pose = third_person.camera_look_at({-2, 7, 1}, target)
    testing.expect(t, pose.position.x == -2 && pose.position.y == 7 && pose.position.z == 1)
}

@(test)
third_person_camera_system_switches_named_slots :: proc(t: ^testing.T) {
    player := third_person.camera_look_at({0, 2, 5}, {0, 1, 0})
    system := third_person.camera_system(player)
    inspection := third_person.camera_near({8, 1, -2}, {4, 3, 4})
    third_person.camera_set_pose(&system, .Inspection, inspection)
    third_person.camera_set_active(&system, .Inspection)
    testing.expect(t, system.active == .Inspection && third_person.camera_active_pose(&system).position.x == 12)
    third_person.camera_set_active(&system, .Player)
    testing.expect(t, third_person.camera_active_pose(&system).position.z == 5)
}
@(test)
physics_backed_step_updates_velocity_without_preintegrating_position :: proc(t: ^testing.T) {
    state := third_person.State {
        position = {10, 4, -7},
        grounded = true,
    }
    start := state.position
    third_person.step(
        &state,
        {move_y = 1, grounded = true, ground_normal = {0, 1, 0}},
        third_person.default_config(),
        .1,
        integrate_position = false,
    )
    testing.expect_value(t, state.position, start)
    testing.expect(t, state.velocity.x != 0 || state.velocity.z != 0)
}
