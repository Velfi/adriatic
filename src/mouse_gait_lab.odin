package main

import atmosphere "../packages/atmosphere"
import mouse_gait "../packages/mouse_gait"
import particle_systems "../packages/particles"
import third_person "zelda_engine:third_person"
import "core:fmt"
import "core:math"
import canvas2d "zelda_engine:canvas2d"
import physics "zelda_engine:physics"

MOUSE_GAIT_LAB_SPEEDS := [5]f32{2.6, 6.4, 9.0, 9.8, 11.2}
MOUSE_GAIT_LAB_NAMES := [5]string{"WALK", "TROT", "TROT / GALLOP", "GALLOP", "FULL BOUND"}
MOUSE_GAIT_LAB_TARGET_NAMES := [5]string{"walk", "trot", "transition", "gallop", "bound"}
MOUSE_GAIT_LAB_COLORS := [5]canvas2d.Color {
    {213, 190, 151, 255},
    {169, 91, 55, 255},
    {139, 145, 151, 255},
    {132, 107, 84, 255},
    {226, 224, 216, 255},
}
MOUSE_GAIT_PATH_COLORS := [4]canvas2d.Color {
    {64, 224, 238, 255}, // left fore
    {255, 158, 64, 255}, // right fore
    {236, 82, 190, 255}, // left hind
    {139, 224, 78, 255}, // right hind
}
MOUSE_GAIT_PATH_NAMES := [4]string{"LF", "RF", "LH", "RH"}

mouse_gait_lab_frozen: bool
mouse_gait_lab_phase: f32
mouse_gait_lab_focus_lane: int
mouse_gait_lab_oblique: bool
mouse_gait_lab_show_paths: bool
mouse_gait_lab_stop_spray: bool
mouse_gait_lab_scurry: bool
mouse_gait_lab_surface_course: bool
mouse_gait_lab_moving_platform: physics.Body_ID
mouse_gait_lab_course_world: physics.World
mouse_gait_lab_course_bodies: [6]physics.Body_ID
mouse_gait_lab_course_body_count: int
mouse_gait_lab_course_feature: int
mouse_gait_lab_course_actor_position: third_person.Vec3

mouse_gait_lab_course_clear :: proc(editor: ^Editor) {
    if editor != nil &&
       editor.gameplay_physics.world != nil &&
       editor.gameplay_physics.world == mouse_gait_lab_course_world {
        for body in mouse_gait_lab_course_bodies[:mouse_gait_lab_course_body_count] {
            if body != physics.INVALID_BODY do physics.remove_body(editor.gameplay_physics.world, body)
        }
    }
    mouse_gait_lab_course_world = nil
    mouse_gait_lab_course_bodies = {}
    mouse_gait_lab_course_body_count = 0
    mouse_gait_lab_moving_platform = physics.INVALID_BODY
    mouse_gait_lab_course_actor_position = {}
}

mouse_gait_lab_course_register :: proc(world: physics.World, body: physics.Body_ID) {
    if body == physics.INVALID_BODY || mouse_gait_lab_course_body_count >= len(mouse_gait_lab_course_bodies) do return
    mouse_gait_lab_course_world = world
    mouse_gait_lab_course_bodies[mouse_gait_lab_course_body_count] = body
    mouse_gait_lab_course_body_count += 1
}

mouse_gait_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    mouse_gait_lab_course_clear(editor)
    mouse_gait_lab_frozen = false
    mouse_gait_lab_phase = 0
    mouse_gait_lab_focus_lane = -1
    mouse_gait_lab_oblique = false
    mouse_gait_lab_show_paths = false
    mouse_gait_lab_stop_spray = target == "stop-spray"
    mouse_gait_lab_scurry = target == "scurry"
    mouse_gait_lab_surface_course = false
    mouse_gait_lab_course_feature = 2
    course_side_targets := [5]string {
        "surface-flat-side",
        "surface-ramp-side",
        "surface-steps-side",
        "surface-ledge-side",
        "surface-platform-side",
    }
    course_oblique_targets := [5]string {
        "surface-flat-oblique",
        "surface-ramp-oblique",
        "surface-steps-oblique",
        "surface-ledge-oblique",
        "surface-platform-oblique",
    }
    for feature in 0 ..< 5 {
        if target == course_side_targets[feature] || target == course_oblique_targets[feature] {
            mouse_gait_lab_surface_course = true
            mouse_gait_lab_course_feature = feature
            mouse_gait_lab_oblique = target == course_oblique_targets[feature]
        }
    }
    if target == "surface-course-side" || target == "surface-course-oblique" {
        mouse_gait_lab_surface_course = true
        mouse_gait_lab_oblique = target == "surface-course-oblique"
    }
    if mouse_gait_lab_stop_spray {
        mouse_gait_lab_frozen = true
        mouse_gait_lab_phase = .625
        mouse_gait_lab_focus_lane = 4
    }
    if mouse_gait_lab_scurry {
        mouse_gait_lab_frozen = false
        mouse_gait_lab_focus_lane = 4
    }
    phase_targets := [8]string{"phase-0", "phase-1", "phase-2", "phase-3", "phase-4", "phase-5", "phase-6", "phase-7"}
    for phase_target, index in phase_targets {
        if target == phase_target {
            mouse_gait_lab_frozen = true
            mouse_gait_lab_phase = f32(index) / f32(len(phase_targets))
            break
        }
    }
    for gait_target, lane in MOUSE_GAIT_LAB_TARGET_NAMES {
        for phase_index in 0 ..< 16 {
            if target == fmt.tprintf("%s-phase16-%d", gait_target, phase_index) {
                mouse_gait_lab_frozen = true
                mouse_gait_lab_phase = f32(phase_index) / 16
                mouse_gait_lab_focus_lane = lane
                break
            }
        }
        for phase_index in 0 ..< 8 {
            if target == fmt.tprintf("%s-phase-%d", gait_target, phase_index) {
                mouse_gait_lab_frozen = true
                mouse_gait_lab_phase = f32(phase_index) / 8
                mouse_gait_lab_focus_lane = lane
                break
            }
            if target == fmt.tprintf("%s-oblique-phase-%d", gait_target, phase_index) {
                mouse_gait_lab_frozen = true
                mouse_gait_lab_phase = f32(phase_index) / 8
                mouse_gait_lab_focus_lane = lane
                mouse_gait_lab_oblique = true
                break
            }
            if target == fmt.tprintf("%s-paths-phase-%d", gait_target, phase_index) {
                mouse_gait_lab_frozen = true
                mouse_gait_lab_phase = f32(phase_index) / 8
                mouse_gait_lab_focus_lane = lane
                mouse_gait_lab_show_paths = true
                break
            }
            if target == fmt.tprintf("%s-oblique-paths-phase-%d", gait_target, phase_index) {
                mouse_gait_lab_frozen = true
                mouse_gait_lab_phase = f32(phase_index) / 8
                mouse_gait_lab_focus_lane = lane
                mouse_gait_lab_oblique = true
                mouse_gait_lab_show_paths = true
                break
            }
        }
    }
    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.project.sea_level = -10
    for &level in editor.project.levels {
        for &height in level.heights do height = 0
    }
    atmosphere.set_world_minutes(&editor.atmosphere, 9 * 60 + 20)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    editor.player_terrain_effects = particle_systems.new_vehicle_effects(0xa21c94d7)
    if mouse_gait_lab_surface_course {
        mouse_gait_lab_focus_lane = 1
        if editor.gameplay_physics.world != nil || gameplay_physics_create(editor) {
            state := &editor.gameplay_physics
            ramp_angle := f32(12 * math.PI / 180)
            course := [5]physics.Body_ID {
                physics.add_box_layered(
                    state.world,
                    {1.15, .12, .7},
                    {-2.4, .12, 0},
                    rotation = {0, 0, math.sin(ramp_angle * .5), math.cos(ramp_angle * .5)},
                ),
                physics.add_box_layered(state.world, {.32, .10, .7}, {-.72, .10, 0}),
                physics.add_box_layered(state.world, {.32, .20, .7}, {-.08, .20, 0}),
                physics.add_box_layered(state.world, {.32, .30, .7}, {.56, .30, 0}),
                physics.add_box_layered(state.world, {.75, .34, .7}, {1.72, .34, 0}),
            }
            for body in course {
                mouse_gait_lab_course_register(state.world, body)
            }
            mouse_gait_lab_moving_platform = physics.add_box_layered(
                state.world,
                {.72, .12, .7},
                {3.55, .36, 0},
                motion = .Kinematic,
                layer = .Moving,
            )
            mouse_gait_lab_course_register(state.world, mouse_gait_lab_moving_platform)
        }
        course_positions := [5]third_person.Vec3 {
            {-4.25, 0, 0},
            {-2.4, .22, 0},
            {-.72, .20, 0},
            {1.72, .68, 0},
            {3.55, .48, 0},
        }
        course_position := course_positions[mouse_gait_lab_course_feature]
        mouse_gait_lab_course_actor_position = course_position
        player_place(editor, course_position, .Scene_Setup, -math.PI * .5)
        editor.player.running = true
        editor.player.grounded = true
        editor.player_gait_weight = 1
        editor.player_stride_phase = math.PI * 1.72
        editor.player.velocity = {}
        editor.camera_pose = third_person.camera_look_at(
            {course_position.x + 1.0, course_position.y + 1.8, 4.6},
            {course_position.x, course_position.y + .25, 0},
        )
        if mouse_gait_lab_oblique {
            editor.camera_pose = third_person.camera_look_at(
                {course_position.x + 3.4, course_position.y + 2.2, 3.6},
                {course_position.x, course_position.y + .25, 0},
            )
        }
    }
    if mouse_gait_lab_stop_spray {
        contact := particle_systems.Vehicle_Contact {
            position = {-.62, .01, 0},
            grounded = true,
            surface  = .Grass,
        }
        particle_systems.spawn_stop_spray(&editor.player_terrain_effects, contact, {1, 0, 0}, 1)
        empty_contacts: [4]particle_systems.Vehicle_Contact
        for _ in 0 ..< 3 {
            particle_systems.step_vehicle_effects(&editor.player_terrain_effects, .05, 0, 0, false, 0, empty_contacts)
        }
        editor.player_brake_pose = 1
    }
    if mouse_gait_lab_scurry {
        contact := particle_systems.Vehicle_Contact {
            position = {-.34, .01, 0},
            grounded = true,
            surface  = .Dirt,
        }
        empty_contacts: [4]particle_systems.Vehicle_Contact
        for _ in 0 ..< 5 {
            particle_systems.step_vehicle_effects(&editor.player_terrain_effects, .035, 0, 0, false, 0, empty_contacts)
            particle_systems.spawn_scrabble(&editor.player_terrain_effects, .05, contact, {1, 0, 0}, 1)
        }
        editor.player.running = true
        editor.player.grounded = true
        editor.player.velocity = {.65, 0, 0}
        editor.player_scurry_weight = 1
        editor.player_scurry_lean = editor.tweak.player_animation.scurry_lean_radians
        editor.player_scurry_compression = editor.tweak.player_animation.scurry_compression * .72
    }
    editor.camera_pose = third_person.camera_look_at({6.2, 4.1, 9.2}, {0, .30, 0})
    if mouse_gait_lab_focus_lane >= 0 {
        editor.camera_pose = third_person.camera_look_at({-.05, .72, 1.95}, {-.05, .27, 0})
        if mouse_gait_lab_oblique {
            editor.camera_pose = third_person.camera_look_at({1.35, 1.02, 1.55}, {-.05, .25, 0})
        }
    }
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

mouse_gait_lab_stride_rate :: proc(editor: ^Editor, speed: f32) -> f32 {
    animation := &editor.tweak.player_animation
    gait := mouse_gait_weights(animation, speed, 0)
    return(
        animation.stride_radians_per_meter * gait.walk +
        animation.trot_stride_radians_per_meter * gait.trot +
        animation.bound_stride_radians_per_meter * gait.bound \
    )
}

mouse_gait_lab_paw_path_point :: proc(editor: ^Editor, speed, phase, side: f32, front: bool) -> third_person.Vec3 {
    animation := &editor.tweak.player_animation
    gait := mouse_gait_weights(animation, speed, 0)
    left_side := side < 0
    walk_offset := left_side ? f32(.25) : f32(.75)
    trot_offset := left_side ? f32(.50) : f32(0)
    if front {
        walk_offset = left_side ? f32(0) : f32(.50)
        trot_offset = left_side ? f32(0) : f32(.50)
    }
    lag := side * mouse_gait.bound_bilateral_lag(gait.bound)
    bound_offset := .50 + mouse_gait.BOUND_PHASE_OFFSET - lag
    if front do bound_offset = mouse_gait.BOUND_PHASE_OFFSET + lag
    motion := mouse_gait.blend_scaled(
        phase,
        walk_offset,
        trot_offset,
        bound_offset,
        gait,
        front ? f32(.68) : f32(.76),
        front ? f32(.56) : f32(.60),
        front ? f32(.34) : f32(.36),
        animation.stride_radians_per_meter,
        animation.trot_stride_radians_per_meter,
        animation.bound_stride_radians_per_meter,
    )
    lift_scale := .090 * gait.walk + .105 * gait.trot + .165 * gait.bound
    if front do lift_scale = .075 * gait.walk + .088 * gait.trot + .145 * gait.bound
    if front {
        return {side * .105, .030 + motion.lift * lift_scale, .235 + motion.reach + side * .014}
    }
    return {side * .195, .030 + motion.lift * lift_scale, -.16 + motion.reach + side * .018}
}

mouse_gait_lab_world_point :: proc(local: third_person.Vec3, lane_z, rotation: f32) -> third_person.Vec3 {
    x, z := world_rotate_xz(0, lane_z, local.x, local.z, rotation)
    return {x, local.y, z}
}

world_mouse_gait_paw_paths :: proc(editor: ^Editor, speed, lane_z, rotation: f32) {
    path_forward := third_person.Vec3{-math.sin(rotation), 0, math.cos(rotation)}
    sides := [2]f32{-1, 1}
    for front_index in 0 ..< 2 {
        front := front_index == 0
        for side, side_index in sides {
            path_index := front_index * 2 + side_index
            previous := mouse_gait_lab_world_point(
                mouse_gait_lab_paw_path_point(editor, speed, 0, side, front),
                lane_z,
                rotation,
            )
            for sample in 1 ..= 48 {
                phase := f32(sample) / 48 * math.PI * 2
                point := mouse_gait_lab_world_point(
                    mouse_gait_lab_paw_path_point(editor, speed, phase, side, front),
                    lane_z,
                    rotation,
                )
                world_tube_between(previous, point, path_forward, .007, .007, MOUSE_GAIT_PATH_COLORS[path_index])
                previous = point
            }
        }
    }
}

world_mouse_gait_lab :: proc(editor: ^Editor) {
    if editor == nil do return
    if mouse_gait_lab_surface_course {
        ramp_angle := f32(12 * math.PI / 180)
        world_box_rotated({-4.25, -.08, 0}, {1.4, .16, 1.4}, 0, {171, 174, 161, 255})
        for slice in 0 ..< 12 {
            x := -3.5 + (f32(slice) + .5) * .19
            height := .04 + (x + 3.5) * math.tan(ramp_angle)
            world_box_rotated({x, height * .5, 0}, {.20, height, 1.4}, 0, {154, 158, 149, 255})
        }
        world_box_rotated({-.72, .10, 0}, {.64, .20, 1.4}, 0, {139, 145, 151, 255})
        world_box_rotated({-.08, .20, 0}, {.64, .40, 1.4}, 0, {139, 145, 151, 255})
        world_box_rotated({.56, .30, 0}, {.64, .60, 1.4}, 0, {139, 145, 151, 255})
        world_box_rotated({1.72, .34, 0}, {1.50, .68, 1.4}, 0, {132, 107, 84, 255})
        platform_y := .36 + math.sin(editor.map_time * 1.7) * .18
        world_box_rotated({3.55, platform_y, 0}, {1.44, .24, 1.4}, 0, {169, 91, 55, 255})
        // Keep the inspection actor near the optical center. The former flat-
        // ground placement at x=-4.25 fell outside the authored camera's
        // horizontal frustum even though the course itself remained visible.
        world_mouse_model(
            editor,
            {
                position = mouse_gait_lab_course_actor_position,
                rotation = editor.player.facing_yaw_radians,
                fur = Mouse_Fur(1),
                pattern = .Solid,
                grounded = true,
                player_controlled = true,
                track_paw_plants = true,
                gait_preview = true,
                gait_speed = 2.6,
                gait_phase = math.PI * 1.72,
            },
        )
        return
    }
    track_length := f32(12)
    track_start := -track_length * .5
    for lane in 0 ..< len(MOUSE_GAIT_LAB_SPEEDS) {
        if mouse_gait_lab_focus_lane >= 0 && lane != mouse_gait_lab_focus_lane do continue
        z := mouse_gait_lab_focus_lane >= 0 ? f32(0) : -4 + f32(lane) * 2
        lane_color := lane % 2 == 0 ? canvas2d.Color{171, 174, 161, 255} : canvas2d.Color{151, 158, 151, 255}
        if mouse_gait_lab_scurry do lane_color = {143, 111, 83, 255}
        world_box_rotated({0, -.08, z}, {track_length + 1, .16, 1.62}, 0, lane_color)

        speed := MOUSE_GAIT_LAB_SPEEDS[lane]
        distance := editor.map_time * speed
        phase := math.mod(distance * mouse_gait_lab_stride_rate(editor, speed), math.PI * 2)
        if mouse_gait_lab_frozen {
            phase = mouse_gait_lab_phase * math.PI * 2
        }
        // Keep the animal in an inspection frame and move a ruler-like ground
        // beneath it. A planted paw should remain aligned with one passing
        // marker during stance; any mismatch is visible as foot skating.
        marker_travel := distance
        if mouse_gait_lab_frozen {
            marker_travel = mouse_gait_lab_phase * math.PI * 2 / mouse_gait_lab_stride_rate(editor, speed)
        }
        for marker in 0 ..< 8 {
            marker_offset := f32(marker) * track_length / 8
            wrapped := math.mod(marker_offset - marker_travel, track_length)
            if wrapped < 0 do wrapped += track_length
            marker_x := track_start + wrapped
            world_box_rotated(
                {marker_x, .012, z},
                {.055, .025, 1.42},
                0,
                lane % 2 == 0 ? canvas2d.Color{111, 121, 119, 255} : canvas2d.Color{103, 115, 113, 255},
            )
        }
        if mouse_gait_lab_focus_lane >= 0 && mouse_gait_lab_show_paths {
            world_mouse_gait_paw_paths(editor, speed, z, -math.PI * .5)
        }
        world_mouse_model(
            editor,
            {
                position = {0, 0, z},
                rotation = -math.PI * .5,
                fur = Mouse_Fur(lane),
                pattern = .Solid,
                grounded = true,
                gait_preview = true,
                gait_speed = speed,
                gait_phase = phase,
                player_controlled = mouse_gait_lab_stop_spray || mouse_gait_lab_scurry,
            },
        )
    }
    if mouse_gait_lab_stop_spray || mouse_gait_lab_scurry do world_player_terrain_particles(editor)
}

mouse_gait_lab_draw_ui :: proc(editor: ^Editor, width, height: i32) {
    focused := mouse_gait_lab_focus_lane >= 0
    panel_height := f32(190)
    if focused {
        panel_height = mouse_gait_lab_show_paths ? f32(118) : f32(92)
    }
    panel := canvas2d.Rectangle {
        x      = 22,
        y      = 22,
        width  = 430,
        height = panel_height,
    }
    canvas2d.DrawRectangleRounded(panel, .08, 8, {12, 24, 30, 232})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .08, 8, 1, {116, 174, 183, 255})
    title: cstring = "MOUSE GAIT COMPARISON"
    if mouse_gait_lab_stop_spray do title = "SUDDEN STOP / TERRAIN SPRAY"
    if mouse_gait_lab_scurry do title = "SCURRY / PAW SCRABBLE"
    canvas2d.DrawTextEx(canvas2d.Font{}, title, {38, 38}, 20, 1, {245, 238, 197, 255})
    if mouse_gait_lab_frozen && !mouse_gait_lab_stop_spray && !mouse_gait_lab_scurry {
        phase_label := fmt.ctprintf("FROZEN STRIDE PHASE %.0f%%", mouse_gait_lab_phase * 100)
        canvas2d.DrawTextEx(canvas2d.Font{}, phase_label, {244, 42}, 12, 1, {184, 211, 218, 255})
    }
    if focused && mouse_gait_lab_show_paths {
        for path_name, index in MOUSE_GAIT_PATH_NAMES {
            legend_x := 38 + f32(index) * 72
            canvas2d.DrawRectangle(i32(legend_x), 116, 12, 4, MOUSE_GAIT_PATH_COLORS[index])
            canvas2d.DrawTextEx(
                canvas2d.Font{},
                fmt.ctprintf("%s PATH", path_name),
                {legend_x + 17, 110},
                11,
                1,
                MOUSE_GAIT_PATH_COLORS[index],
            )
        }
    }
    for speed, lane in MOUSE_GAIT_LAB_SPEEDS {
        if focused && lane != mouse_gait_lab_focus_lane do continue
        gait := mouse_gait_weights(&editor.tweak.player_animation, speed, 0)
        label := fmt.ctprintf(
            "%s  GROUND %.1f u/s   W %.0f%%  T %.0f%%  B %.0f%%",
            MOUSE_GAIT_LAB_NAMES[lane],
            speed,
            gait.walk * 100,
            gait.trot * 100,
            gait.bound * 100,
        )
        label_y := focused ? f32(72) : 72 + f32(lane) * 23
        canvas2d.DrawTextEx(canvas2d.Font{}, label, {38, label_y}, 13, 1, MOUSE_GAIT_LAB_COLORS[lane])
    }
    _ = width
    _ = height
}
