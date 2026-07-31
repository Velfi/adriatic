package tests

import chase_camera "../packages/chase_camera"
import flight "../packages/flight"
import "core:math"
import "core:testing"

@(test)
aircraft_chase_camera_sits_behind_and_looks_ahead :: proc(t: ^testing.T) {
    target := chase_camera.Target {
        basis = flight.identity_basis(),
    }
    pose := chase_camera.desired_pose(target, 0, 0)
    testing.expect(t, pose.position.z > target.position.z)
    testing.expect(t, pose.target.z < target.position.z)
    testing.expect(t, pose.position.y > pose.target.y)
    testing.expect(t, pose.position.y - target.position.y >= 7)
}

@(test)
aircraft_chase_camera_orbits_and_frames_vertical_attitudes :: proc(t: ^testing.T) {
    target := chase_camera.Target {
        basis = flight.identity_basis(),
    }
    neutral := chase_camera.desired_pose(target, 0, 0)
    orbit := chase_camera.desired_pose(target, .5, .25)
    testing.expect(t, orbit.position.x != neutral.position.x)
    testing.expect(t, orbit.position.y > neutral.position.y)
    testing.expect(t, neutral.target.y < target.position.y)

    camera_offset, focus_offset := chase_camera.vertical_framing(.9)
    testing.expect(t, camera_offset < 0 && focus_offset > 0)
}

@(test)
libellula_chase_camera_has_no_dynamic_framing_offsets :: proc(t: ^testing.T) {
    neutral := chase_camera.Target {
        basis         = flight.identity_basis(),
        fixed_framing = true,
    }
    offset := neutral
    offset.basis.forward = {0, .9, -.1}
    offset.basis.right = {1, 0, 0}
    offset.airspeed = 70
    offset.roll_input = 1
    offset.grounded = true

    neutral_pose := chase_camera.desired_pose(neutral, 0, 0)
    offset_pose := chase_camera.desired_pose(offset, 0, 0)
    testing.expect(t, offset_pose.position == neutral_pose.position)
    testing.expect(t, offset_pose.target == neutral_pose.target)
}

@(test)
aircraft_chase_camera_tracks_translation_exactly_and_smooths_speed_fov :: proc(t: ^testing.T) {
    state: chase_camera.State
    target := chase_camera.Target {
        basis = flight.identity_basis(),
    }
    chase_camera.reset(&state, target)
    start := state.pose.position
    target.position.x = 10
    chase_camera.step(&state, target, 1.0 / 60.0)
    testing.expect(t, math.abs(state.pose.position.x - (start.x + 10)) < .0001)
    testing.expect(t, chase_camera.desired_fov(70) > chase_camera.desired_fov(8))
}

@(test)
aircraft_chase_camera_speed_fov_has_quiet_cruise_and_strong_top_end :: proc(t: ^testing.T) {
    testing.expect(t, chase_camera.desired_fov(0) == 68)
    testing.expect(t, chase_camera.desired_fov(10) == 68)
    testing.expect(t, chase_camera.desired_fov(30) < 74)
    testing.expect(t, chase_camera.desired_fov(58) > 82)
    testing.expect(t, chase_camera.desired_fov(100) == 84)
}

@(test)
aircraft_chase_camera_does_not_steer_view_from_bank_input :: proc(t: ^testing.T) {
    target := chase_camera.Target {
        basis    = flight.identity_basis(),
        airspeed = 45,
    }
    neutral := chase_camera.desired_pose(target, 0, 0)
    target.roll_input = 1
    banking := chase_camera.desired_pose(target, 0, 0)
    testing.expect(t, banking == neutral)
}

@(test)
aircraft_chase_camera_shakes_near_large_flyby_volumes :: proc(t: ^testing.T) {
    target := chase_camera.Target {
        position = {13, 20, 0},
        basis    = flight.identity_basis(),
        airspeed = 62,
    }
    proximity := chase_camera.box_flyby_strength(target.position, {0, 15, 0}, {5, 15, 5}, 0, 12)
    testing.expect(t, proximity > 0)
    testing.expect(t, chase_camera.box_flyby_strength({80, 20, 0}, {0, 15, 0}, {5, 15, 5}, 0, 12) == 0)

    state: chase_camera.State
    chase_camera.reset(&state, target)
    unshaken := state.pose.position
    chase_camera.step(&state, target, 1.0 / 30.0, proximity)
    testing.expect(t, state.shake_intensity > 0)
    testing.expect(t, state.pose.position != unshaken)
}
