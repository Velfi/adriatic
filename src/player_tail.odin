package main

import mouse_tail "../packages/mouse_tail"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math"
import "core:math/linalg"
import physics "zelda_engine:physics"

player_tail_step_shared_world :: proc(ctx: rawptr, _: physics.World, delta_seconds: f32) {
    editor := cast(^Editor)ctx
    gameplay_physics_step_world(editor, delta_seconds)
}

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

    bound := math.sin(stride_phase) * run_weight * (.16 + .84 * bound_weight)
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
        editor.player.position.x + local_x * cosine - local_z * sine,
        editor.player.position.y +
        local_y +
        mouse_surface_height(editor, editor.player.position.x, editor.player.position.z) -
        terrain.sample_height(&editor.project, 0, editor.player.position.x, editor.player.position.z),
        editor.player.position.z + local_x * sine + local_z * cosine,
    }
    // Turning shifts the tail's preferred first segment to the outside of the
    // curve. The remaining Verlet chain still lags and collides freely, so this
    // is a weight-shift bias rather than a canned tail pose.
    model_right := third_person.Vec3{cosine, 0, sine}
    counterbalance := turn_pose * editor.tweak.player_animation.tail_counterbalance
    backward = {sine - model_right.x * counterbalance, 0, -cosine - model_right.z * counterbalance}
    return
}

player_tail_update :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil || !editor.in_map || editor.pilot.mode != .On_Foot do return
    player_scarf_rotation_update(editor, delta_seconds)
    mouse_tail.attach_world(&editor.player_tail, editor.gameplay_physics.world)
    root, backward := player_tail_root(editor)
    backward_direction := linalg.normalize0(third_person.Vec3{backward.x, 0, backward.z})
    if linalg.dot(backward_direction, backward_direction) <= .000001 {
        backward_direction = {0, 0, 1}
    }
    // A small rump capsule ends at the tail socket, leaving both pinned base
    // vertices outside the proxy while the free strand can contact the body.
    proxy_position := root - backward_direction * .22 + third_person.Vec3{0, .03, 0}
    proxy := editor.gameplay_physics.player_tail_proxy
    if proxy == physics.INVALID_BODY {
        proxy = physics.add_capsule_layered(
            editor.gameplay_physics.world,
            .12,
            .22,
            {proxy_position.x, proxy_position.y, proxy_position.z},
            .Kinematic,
            user_data = 2,
            layer = .Character_Proxy,
            friction = .18,
        )
        editor.gameplay_physics.player_tail_proxy = proxy
    } else if delta_seconds > 0 {
        root_delta := root - editor.player_tail.last_root
        if linalg.dot(root_delta, root_delta) > 4 {
            physics.set_transform(
                editor.gameplay_physics.world,
                proxy,
                {proxy_position.x, proxy_position.y, proxy_position.z},
            )
        } else {
            physics.move_kinematic(
                editor.gameplay_physics.world,
                proxy,
                {proxy_position.x, proxy_position.y, proxy_position.z},
                {0, 0, 0, 1},
                min(delta_seconds, f32(.05)),
            )
        }
    }
    mouse_tail.step(
        &editor.player_tail,
        root,
        backward,
        &editor.project,
        editor.tweak.player_tail,
        delta_seconds,
        editor_circulation_plan(editor),
        player_tail_step_shared_world,
        editor,
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
