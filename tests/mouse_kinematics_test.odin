package tests

import mouse_kinematics "../packages/mouse_kinematics"
import "core:math"
import "core:testing"

@(test)
joint_keeps_its_anatomical_branch_across_socket_crossing :: proc(t: ^testing.T) {
    root := mouse_kinematics.Vec3{0, .3, 0}
    forward := mouse_kinematics.Vec3{0, 0, 1}
    before := mouse_kinematics.solve_two_bone(root, {0, 0, -.01}, forward, .255, .245)
    under := mouse_kinematics.solve_two_bone(root, {0, 0, 0}, forward, .255, .245)
    after := mouse_kinematics.solve_two_bone(root, {0, 0, .01}, forward, .255, .245)
    testing.expect(t, before.z > 0)
    testing.expect(t, under.z > 0)
    testing.expect(t, after.z > 0)
    testing.expect(t, math.abs(before.z - after.z) < .02)
}

@(test)
mouse_joint_poles_follow_quadruped_anatomy :: proc(t: ^testing.T) {
    forward := mouse_kinematics.Vec3{0, 0, 1}
    testing.expect(t, mouse_kinematics.fore_elbow_pole(forward).z < 0)
    testing.expect(t, mouse_kinematics.hind_knee_pole(forward).z > 0)
    testing.expect(t, mouse_kinematics.hind_hock_pole(forward).z < 0)
}

@(test)
hind_distal_fold_stays_constant_through_ordinary_reach :: proc(t: ^testing.T) {
    short := mouse_kinematics.stable_distal_span(.30, .255, .210, .275)
    under := mouse_kinematics.stable_distal_span(.40, .255, .210, .275)
    long := mouse_kinematics.stable_distal_span(.50, .255, .210, .275)
    testing.expect(t, math.abs(short - under) < .0001)
    testing.expect(t, math.abs(under - long) < .0001)
}

@(test)
hind_distal_fold_respects_reach_limits :: proc(t: ^testing.T) {
    span := mouse_kinematics.stable_distal_span(.70, .255, .210, .275)
    testing.expect(t, span >= .70 - .255)
    testing.expect(t, span <= .210 + .275)
}

@(test)
two_bone_solution_preserves_segment_lengths :: proc(t: ^testing.T) {
    root := mouse_kinematics.Vec3{0, .3, 0}
    target := mouse_kinematics.Vec3{0, 0, .12}
    joint := mouse_kinematics.solve_two_bone(root, target, {0, 0, 1}, .255, .245)
    root_delta := joint - root
    tip_delta := target - joint
    root_length := math.sqrt(root_delta.x*root_delta.x + root_delta.y*root_delta.y + root_delta.z*root_delta.z)
    tip_length := math.sqrt(tip_delta.x*tip_delta.x + tip_delta.y*tip_delta.y + tip_delta.z*tip_delta.z)
    testing.expect(t, math.abs(root_length - .255) < .0001)
    testing.expect(t, math.abs(tip_length - .245) < .0001)
}
