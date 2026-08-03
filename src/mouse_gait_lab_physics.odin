package main

import "core:math"
import physics "zelda_engine:physics"

mouse_gait_lab_physics_step :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil ||
       !mouse_gait_lab_surface_course ||
       mouse_gait_lab_moving_platform == physics.INVALID_BODY ||
       editor.gameplay_physics.world == nil {
        return
    }
    y := f32(.36 + math.sin(editor.map_time * 1.7) * .18)
    physics.move_kinematic(
        editor.gameplay_physics.world,
        mouse_gait_lab_moving_platform,
        {3.55, y, 0},
        physics.IDENTITY_ROTATION,
        max(delta_seconds, f32(1.0 / 120.0)),
    )
    if mouse_gait_lab_course_feature == 4 {
        mouse_gait_lab_course_actor_position.y = y + .12
    }
    // A deterministic inspection lab owns its actor placement. Ordinary
    // character integration can otherwise walk or settle the mouse outside
    // the authored feature camera before capture submission.
    editor.player.position = mouse_gait_lab_course_actor_position
    editor.player.velocity = {}
    editor.player.grounded = true
    gameplay_physics_teleport_player(editor)
}
