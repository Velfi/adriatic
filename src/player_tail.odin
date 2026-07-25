package main

import mouse_tail "../packages/mouse_tail"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math"

player_tail_root :: proc(editor: ^Editor) -> (root, backward: third_person.Vec3) {
    if editor == nil do return
    rotation := math.PI - editor.player.facing_yaw_radians
    run_weight := editor.player_gait_weight * (1 - editor.player_airborne_weight) + .88 * editor.player_airborne_weight
    stride_phase := editor.player_stride_phase
    if editor.capture_player_walk_pose ||
       editor.capture_player_turn_left_pose ||
       editor.capture_player_turn_right_pose {
        run_weight = 1
        stride_phase = math.PI * 1.75
    } else if editor.capture_player_run_compress_pose || editor.capture_player_brake_pose {
        run_weight = 1
        stride_phase = math.PI * .50
    }
    turn_pose := clamp(editor.player_turn_pose, -1, 1)
    brake_pose := clamp(editor.player_brake_pose, 0, 1)
    if editor.capture_player_turn_left_pose do turn_pose = -1
    if editor.capture_player_turn_right_pose do turn_pose = 1
    if editor.capture_player_brake_pose do brake_pose = 1

    bound := math.sin(stride_phase) * run_weight
    spine_extension := -bound
    body_bob :=
        (-bound * .018 + math.abs(math.sin(stride_phase * 2)) * .014) * run_weight +
        math.sin(editor.map_time * 2.2) * .006 * (1 - run_weight) +
        editor.tweak.player_animation.run_body_lift * run_weight * (1 - editor.player_airborne_weight)
    local_x := turn_pose * editor.tweak.player_animation.turn_spine_offset * .18
    posted_weight := clamp(editor.player_posted_weight, 0, 1)
    if editor.capture_player_posted_pose do posted_weight = 1
    local_y :=
        .31 -
        run_weight * .045 +
        body_bob -
        brake_pose * editor.tweak.player_animation.brake_compression * .48 +
        posted_weight * .010
    local_z := -.78 - spine_extension * .035 * run_weight + brake_pose * .035
    cosine, sine := math.cos(rotation), math.sin(rotation)
    root = {
        x = editor.player.position.x + local_x * cosine - local_z * sine,
        y = editor.player.position.y + local_y + mouse_surface_height(editor, editor.player.position.x, editor.player.position.z) - terrain.sample_height(&editor.project, 0, editor.player.position.x, editor.player.position.z),
        z = editor.player.position.z + local_x * sine + local_z * cosine,
    }
    // Turning shifts the tail's preferred first segment to the outside of the
    // curve. The remaining Verlet chain still lags and collides freely, so this
    // is a weight-shift bias rather than a canned tail pose.
    model_right := third_person.Vec3 {
        x = cosine,
        z = sine,
    }
    counterbalance := turn_pose * editor.tweak.player_animation.tail_counterbalance
    backward = {
        x = sine - model_right.x * counterbalance,
        z = -cosine - model_right.z * counterbalance,
    }
    return
}

player_tail_update :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil || !editor.in_map || editor.pilot.mode != .On_Foot do return
    root, backward := player_tail_root(editor)
    mouse_tail.step(&editor.player_tail, root, backward, &editor.project, editor.tweak.player_tail, delta_seconds)
}
