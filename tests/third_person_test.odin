package tests

import third_person "../packages/third_person"
import "core:testing"

@(test)
third_person_moves_relative_to_the_camera :: proc(t: ^testing.T) {
    state := third_person.State{}
    config := third_person.default_config()
    third_person.step(&state, {move_y = 1, grounded = true}, config, 1.0 / 6.0)
    testing.expect(t, state.velocity.z < 0 && state.position.z < 0)
    testing.expect(t, state.facing_yaw_radians == 0)
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
