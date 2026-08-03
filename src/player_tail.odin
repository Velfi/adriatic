package main

import mouse_tail "../packages/mouse_tail"
import mouse_gait "../packages/mouse_gait"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math"

player_tail_root :: proc(editor: ^Editor) -> (root, backward: third_person.Vec3) {
    if editor == nil do return
    rotation := math.PI - editor.player.facing_yaw_radians
    run_weight := editor.player_gait_weight * (1 - editor.player_airborne_weight) + .88 * editor.player_airborne_weight
    stride_phase := editor.player_stride_phase
    horizontal_speed := f32(
        math.sqrt(
            f64(
                editor.player.velocity.x * editor.player.velocity.x +
                editor.player.velocity.z * editor.player.velocity.z,
            ),
        ),
    )
    gait := mouse_gait_weights(&editor.tweak.player_animation, horizontal_speed, editor.player_airborne_weight)
    bound_weight := gait.bound
    if editor.capture_player_walk_pose ||
       editor.capture_player_turn_left_pose ||
       editor.capture_player_turn_right_pose {
        run_weight = 1
        stride_phase = math.PI * 1.75
        bound_weight = editor.capture_player_walk_pose ? f32(0) : f32(1)
    } else if editor.capture_player_run_compress_pose || editor.capture_player_brake_pose {
        run_weight = 1
        stride_phase = math.PI * .50
        bound_weight = 1
    }
    if editor.capture_player_jump_pose || editor.capture_player_fall_pose do bound_weight = 1
    turn_pose := clamp(editor.player_turn_pose, -1, 1)
    brake_pose := clamp(editor.player_brake_pose, 0, 1)
    if editor.capture_player_turn_left_pose do turn_pose = -1
    if editor.capture_player_turn_right_pose do turn_pose = 1
    if editor.capture_player_brake_pose do brake_pose = 1

    bound_phase := mouse_gait.bound_animation_phase(stride_phase, bound_weight)
    bound := math.sin(bound_phase) * run_weight * mouse_gait.axial_flex_scale(gait)
    spine_extension := -bound
    airborne_weight := editor.player_airborne_weight
    scurry_weight := clamp(editor.player_scurry_weight, 0, 1)
    scurry_lean := clamp(editor.player_scurry_lean, -.12, .32)
    scurry_compression := clamp(
        editor.player_scurry_compression,
        -.025,
        editor.tweak.player_animation.scurry_compression * 1.35,
    )
    scurry_support_phase := math.sin(stride_phase * 2)
    scurry_support_shift := scurry_support_phase * scurry_weight * .030 * (1 - airborne_weight)
    scurry_support_roll := scurry_support_phase * scurry_weight * .055 * (1 - airborne_weight)
    bound_aerial_lift := mouse_gait.bound_aerial_weight(bound_phase) * bound_weight * run_weight * .085
    body_bob :=
        (-bound * .018 +
                math.abs(math.sin(stride_phase * 2)) * mouse_gait.vertical_bob_scale(gait) +
                bound_aerial_lift) *
            run_weight +
        math.sin(editor.map_time * 2.2) * .006 * (1 - run_weight) +
        editor.tweak.player_animation.run_body_lift * run_weight * (1 - editor.player_airborne_weight)
    body_bob -= scurry_compression
    posted_weight := clamp(editor.player_posted_weight, 0, 1)
    if editor.capture_player_posted_pose do posted_weight = 1
    animation := &editor.tweak.player_animation
    spine_side := turn_pose * animation.turn_spine_offset
    brake_compression := brake_pose * animation.brake_compression
    ground_normal := editor.player.ground_normal
    if ground_normal.y <= .1 do ground_normal = {0, 1, 0}
    cosine, sine := math.cos(rotation), math.sin(rotation)
    model_forward := third_person.Vec3{-sine, 0, cosine}
    model_right := third_person.Vec3{cosine, 0, sine}
    normal_forward := ground_normal.x * model_forward.x + ground_normal.z * model_forward.z
    normal_right := ground_normal.x * model_right.x + ground_normal.z * model_right.z
    slope_pitch := math.atan2(normal_forward, ground_normal.y) * animation.slope_alignment
    slope_roll := math.atan2(-normal_right, ground_normal.y) * animation.slope_alignment
    body_roll := slope_roll - turn_pose * animation.turn_lean_radians + scurry_support_roll

    // Skin the authored socket through the same pelvis pose used by the body
    // renderer. Keeping this transform here makes the simulated first point
    // coincide with the rump instead of drifting sideways or vertically as
    // gait pitch, slope alignment, and body roll move the torso around it.
    pelvis_x := spine_side * .18 - scurry_support_shift
    pelvis_y :=
        .36 - run_weight * .010 + body_bob - bound * .018 - brake_compression * .48 - posted_weight * .015
    pelvis_z := -.48 - spine_extension * .070 * run_weight + brake_pose * .035
    pelvis_pitch := bound * .075 + slope_pitch * .65 - posted_weight * .05 + scurry_lean * .45
    pelvis_yaw: f32
    pelvis_roll := body_roll * .82 - scurry_support_roll * .22
    emote_pose := mouse_emote_pose(&editor.mouse_emote)
    pelvis_emote := emote_pose.bones[0]
    pelvis_emote_weight := clamp(pelvis_emote.weight, 0, 1)
    pelvis_x += pelvis_emote.position.x * pelvis_emote_weight
    pelvis_y +=
        pelvis_emote.position.y * pelvis_emote_weight +
        emote_pose.body_height - emote_pose.body_compression
    pelvis_z += pelvis_emote.position.z * pelvis_emote_weight
    pelvis_pitch += pelvis_emote.pitch * pelvis_emote_weight
    pelvis_yaw += pelvis_emote.yaw * pelvis_emote_weight
    pelvis_roll += pelvis_emote.roll * pelvis_emote_weight
    socket_relative := third_person.Vec3{0, -.12, -.30}
    pitch_cosine, pitch_sine := math.cos(pelvis_pitch), math.sin(pelvis_pitch)
    pitched_y := socket_relative.y * pitch_cosine - socket_relative.z * pitch_sine
    pitched_z := socket_relative.y * pitch_sine + socket_relative.z * pitch_cosine
    yaw_cosine, yaw_sine := math.cos(pelvis_yaw), math.sin(pelvis_yaw)
    yawed_x := socket_relative.x * yaw_cosine + pitched_z * yaw_sine
    yawed_z := -socket_relative.x * yaw_sine + pitched_z * yaw_cosine
    roll_cosine, roll_sine := math.cos(pelvis_roll), math.sin(pelvis_roll)
    local_x := pelvis_x + yawed_x * roll_cosine - pitched_y * roll_sine
    local_y := pelvis_y + yawed_x * roll_sine + pitched_y * roll_cosine
    local_z := pelvis_z + yawed_z
    root = {
        editor.player.position.x + local_x * cosine - local_z * sine,
        editor.player.position.y +
        local_y +
        mouse_surface_height(editor, editor.player.position.x, editor.player.position.z) -
        terrain.sample_surface_height(&editor.project, 0, editor.player.position.x, editor.player.position.z),
        editor.player.position.z + local_x * sine + local_z * cosine,
    }
    // Turning shifts the tail's preferred first segment to the outside of the
    // curve. The remaining Verlet chain still lags and collides freely, so this
    // is a weight-shift bias rather than a canned tail pose.
    counterbalance := turn_pose * editor.tweak.player_animation.tail_counterbalance
    backward = {sine - model_right.x * counterbalance, 0, -cosine - model_right.z * counterbalance}
    // Rendering evaluates the complete hierarchy, including authored emote
    // channels and joint constraints. Consume that attachment on the next
    // simulation step so the physical tail cannot drift from a separately
    // reconstructed pelvis pose.
    if editor.player_tail.attachment_valid do root = editor.player_tail.evaluated_attachment
    emote_tail := emote_pose.tail
    emote_weight := clamp(emote_tail.weight, 0, 1)
    if emote_weight > 0 {
        local := emote_tail.local_direction
        desired := third_person.Vec3 {
            local.x * cosine - local.z * sine,
            local.y,
            local.x * sine + local.z * cosine,
        }
        backward = backward * (1 - emote_weight) + desired * emote_weight
        root.y += emote_tail.lift * emote_weight * .35
    }
    return
}

player_tail_update :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil || !editor.in_map || editor.pilot.mode != .On_Foot do return
    player_scarf_rotation_update(editor, delta_seconds)
    player_mailbag_motion_update(editor, delta_seconds)
    root, backward := player_tail_root(editor)
    mouse_tail.step(
        &editor.player_tail,
        root,
        backward,
        &editor.project,
        editor.tweak.player_tail,
        delta_seconds,
        editor_circulation_plan(editor),
    )
}

player_mailbag_motion_update :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil || delta_seconds <= 0 do return
    delta := min(delta_seconds, f32(.05))
    // The fitted harness turns with the torso. Only the pouch mass lags, and
    // only by a few centimetres, so the accessory reads as loaded canvas
    // without sliding freely over the animal's back.
    yaw_target := clamp(-editor.player.turn_amount * .075, -.085, .085)
    roll_target := clamp(-editor.player_turn_pose * .045, -.055, .055)
    vertical_target := clamp(-editor.player.velocity.y * .0035, -.018, .018)
    player_animation_spring(
        &editor.mouse_mailbag_yaw_lag,
        &editor.mouse_mailbag_yaw_velocity,
        yaw_target,
        42,
        12,
        delta,
    )
    player_animation_spring(
        &editor.mouse_mailbag_roll_lag,
        &editor.mouse_mailbag_roll_velocity,
        roll_target,
        48,
        13,
        delta,
    )
    player_animation_spring(
        &editor.mouse_mailbag_vertical_lag,
        &editor.mouse_mailbag_vertical_velocity,
        vertical_target,
        55,
        14,
        delta,
    )
}

player_scarf_rotation_update :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil || delta_seconds <= 0 do return
    delta := min(delta_seconds, f32(.1))
    if !editor.mouse_scarf_enabled {
        editor.mouse_scarf_angular_velocity *= f32(math.exp(f64(-delta * 3)))
        return
    }

    rotation := math.PI - editor.player.facing_yaw_radians
    right_x, right_z := math.cos(rotation), math.sin(rotation)
    wind_right := editor.atmosphere.weather.wind[0] * right_x + editor.atmosphere.weather.wind[1] * right_z
    velocity_right := editor.player.velocity.x * right_x + editor.player.velocity.z * right_z
    relative_air_right := wind_right - velocity_right
    torque := clamp(relative_air_right * .22 - editor.player.turn_amount * 1.15, -3.2, 3.2)
    editor.mouse_scarf_angular_velocity += torque * delta
    editor.mouse_scarf_angular_velocity *= f32(math.exp(f64(-delta * .85)))
    editor.mouse_scarf_angular_velocity = clamp(editor.mouse_scarf_angular_velocity, -2.8, 2.8)
    editor.mouse_scarf_rotation += editor.mouse_scarf_angular_velocity * delta
    for editor.mouse_scarf_rotation > math.PI do editor.mouse_scarf_rotation -= math.PI * 2
    for editor.mouse_scarf_rotation < -math.PI do editor.mouse_scarf_rotation += math.PI * 2
}
