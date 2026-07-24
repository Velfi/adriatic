package tests

import chase_camera "../packages/chase_camera"
import flight "../packages/flight"
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

    camera_offset, focus_offset := chase_camera.vertical_framing(.9)
    testing.expect(t, camera_offset < 0 && focus_offset > 0)
}

@(test)
aircraft_chase_camera_smooths_motion_and_speed_fov :: proc(t: ^testing.T) {
    state: chase_camera.State
    target := chase_camera.Target {
        basis = flight.identity_basis(),
    }
    chase_camera.reset(&state, target)
    start := state.pose.position
    target.position.x = 10
    chase_camera.step(&state, target, 1.0 / 60.0)
    testing.expect(t, state.pose.position.x > start.x && state.pose.position.x < 10)
    testing.expect(t, chase_camera.desired_fov(70) > chase_camera.desired_fov(8))
}
