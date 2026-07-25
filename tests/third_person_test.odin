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
    testing.expect(t, horizontal_speed(state) > 1.9 && horizontal_speed(state) < config.move_speed)

    state.velocity.z = -config.move_speed
    third_person.step(&state, {grounded = true, ground_normal = {y = 1}}, config, .1)
    testing.expect(t, state.velocity.z > -config.move_speed && state.velocity.z < 0)
    testing.expect(t, state.brake_amount > .9)
}

@(test)
third_person_carves_at_speed_and_limits_facing_rate :: proc(t: ^testing.T) {
    state := third_person.State{velocity = {z = -6}}
    left := third_person.State{velocity = {z = -6}}
    config := third_person.default_config()
    third_person.step(
        &state,
        {move_x = 1, grounded = true, ground_normal = {y = 1}},
        config,
        .1,
    )
    testing.expect(t, state.velocity.x > 0 && state.velocity.z < 0)
    testing.expect(t, state.turn_amount > 0)
    testing.expect(t, absolute(state.facing_yaw_radians) <= config.facing_turn_speed * .1 + .001)
    testing.expect(t, horizontal_speed(state) <= config.move_speed + .001)

    third_person.step(
        &left,
        {move_x = -1, grounded = true, ground_normal = {y = 1}},
        config,
        .1,
    )
    testing.expect(t, left.turn_amount < 0)
}

@(test)
third_person_brakes_before_reversing_but_pivots_when_slow :: proc(t: ^testing.T) {
    config := third_person.default_config()
    fast := third_person.State{velocity = {z = -config.move_speed}}
    third_person.step(
        &fast,
        {move_y = -1, grounded = true, ground_normal = {y = 1}},
        config,
        .1,
    )
    testing.expect(t, fast.velocity.z < 0 && fast.velocity.z > -config.move_speed)
    testing.expect(t, fast.brake_amount > .9)

    slow := third_person.State{velocity = {z = -.5}}
    third_person.step(
        &slow,
        {move_y = -1, grounded = true, ground_normal = {y = 1}},
        config,
        .1,
    )
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
    third_person.step(
        &uphill,
        {move_y = 1, grounded = true, ground_normal = {y = .98, z = .2}},
        config,
        .2,
    )
    third_person.step(
        &downhill,
        {move_y = 1, grounded = true, ground_normal = {y = .98, z = -.2}},
        config,
        .2,
    )
    testing.expect(t, -downhill.velocity.z > -uphill.velocity.z)
    testing.expect(t, downhill.ground_normal.y > .9)

    invalid := third_person.State{}
    third_person.step(&invalid, {grounded = true, ground_normal = {x = 2}}, config, .1)
    testing.expect(t, invalid.ground_normal.x == 0 && invalid.ground_normal.y == 1)
}

@(test)
third_person_motion_signals_decay_without_grounded_forces :: proc(t: ^testing.T) {
    state := third_person.State{turn_amount = 1, brake_amount = 1}
    third_person.step(&state, {}, third_person.default_config(), .05)
    testing.expect(t, state.turn_amount < 1 && state.turn_amount >= 0)
    testing.expect(t, state.brake_amount < 1 && state.brake_amount >= 0)
}

@(test)
third_person_fixed_steps_are_consistent_across_frame_rates :: proc(t: ^testing.T) {
    sixty, one_twenty: third_person.State
    config := third_person.default_config()
    for _ in 0 ..< 60 {
        third_person.step(
            &sixty,
            {move_y = 1, grounded = true, ground_normal = {y = 1}},
            config,
            1.0 / 60.0,
        )
    }
    for _ in 0 ..< 120 {
        third_person.step(
            &one_twenty,
            {move_y = 1, grounded = true, ground_normal = {y = 1}},
            config,
            1.0 / 120.0,
        )
    }
    testing.expect(t, absolute(sixty.velocity.z - one_twenty.velocity.z) < .01)
    testing.expect(t, absolute(sixty.position.z - one_twenty.position.z) < .06)
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
    pose := third_person.camera_pose({x = 2, y = 3, z = 4}, camera)
    testing.expect(t, pose.target.x == 2 && pose.target.y == 3 + camera.height && pose.target.z == 4)
    testing.expect(t, pose.position.z > pose.target.z)
}

@(test)
third_person_look_clamps_pitch_and_camera_follow_eases :: proc(t: ^testing.T) {
    camera := third_person.default_camera()
    third_person.look(&camera, 2, 100, .1)
    testing.expect(t, camera.yaw_radians == .2 && camera.pitch_radians == 1.2)
    current := third_person.Camera_Pose{}
    desired := third_person.camera_pose({x = 10}, camera)
    next := third_person.follow_camera(current, desired, 5, .1)
    testing.expect(t, next.target.x > 0 && next.target.x < desired.target.x)
}

@(test)
third_person_authored_camera_can_move_near_and_look_at_target :: proc(t: ^testing.T) {
    target := third_person.Vec3 {
        x = 4,
        y = 2,
        z = -3,
    }
    pose := third_person.camera_near(target, {y = 3, z = 8})
    testing.expect(t, pose.position.x == target.x && pose.position.y == 5 && pose.position.z == 5)
    testing.expect(t, pose.target.x == 4 && pose.target.y == 2 && pose.target.z == -3)
    pose = third_person.camera_look_at({x = -2, y = 7, z = 1}, target)
    testing.expect(t, pose.position.x == -2 && pose.position.y == 7 && pose.position.z == 1)
}

@(test)
third_person_camera_system_switches_named_slots :: proc(t: ^testing.T) {
    player := third_person.camera_look_at({x = 0, y = 2, z = 5}, {y = 1})
    system := third_person.camera_system(player)
    inspection := third_person.camera_near({x = 8, y = 1, z = -2}, {x = 4, y = 3, z = 4})
    third_person.camera_set_pose(&system, .Inspection, inspection)
    third_person.camera_set_active(&system, .Inspection)
    testing.expect(t, system.active == .Inspection && third_person.camera_active_pose(&system).position.x == 12)
    third_person.camera_set_active(&system, .Player)
    testing.expect(t, third_person.camera_active_pose(&system).position.z == 5)
}
