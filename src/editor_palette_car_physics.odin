package main

import libellula_game "../packages/libellula"
import postale_game "../packages/postale"
import rondine_game "../packages/rondine"
import terrain "../packages/terrain"
import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"
import physics "zelda_engine:physics"
import third_person "zelda_engine:third_person"

editor_palette_button_bounds :: proc(index: int) -> canvas2d.Rectangle {
    palette := editor_palette_bounds()
    gap := f32(5)
    button_width := (palette.width - gap * 8) / 9
    return {
        x = palette.x + f32(index) * (button_width + gap),
        y = palette.y,
        width = button_width,
        height = palette.height,
    }
}

editor_palette_tool :: proc(index: int) -> terrain.Tool {
    switch index {
    case 0:
        return .Raise
    case 1:
        return .Smooth
    case 2:
        return .Paint
    case 3, 4, 5, 6, 7, 8:
        return .Structure
    }
    return .Raise
}

editor_palette_curve_mode :: proc(index: int) -> bool {
    return index == 4 || index == 5
}

editor_palette_architecture_mode :: proc(index: int) -> bool { return index == 6 }
editor_palette_climbing_leaves_mode :: proc(index: int) -> bool { return index == 7 }
editor_palette_road_mode :: proc(index: int) -> bool { return index == 8 }

editor_palette_index :: proc(position: canvas2d.Vector2) -> int {
    for index in 0 ..< 9 {
        if canvas2d.CheckCollisionPointRec(position, editor_palette_button_bounds(index)) do return index
    }
    return -1
}

draw_editor_palette :: proc(editor: ^Editor) {
    palette := editor_palette_bounds()
    canvas2d.DrawRectangleRounded(palette, .16, 8, {r = 8, g = 28, b = 45, a = 242})
    labels := [?]cstring {
        "SCULPT [Q]",
        "SMOOTH [E]",
        "PAINT [T]",
        "FORMATIONS [B]",
        "RIDGE [Z]",
        "CLIFF [C]",
        "CITY [N]",
        "PLANTS [H/L]",
        "ROADS [M]",
    }
    for index in 0 ..< 9 {
        button := editor_palette_button_bounds(index)
        selected :=
            editor.tool == editor_palette_tool(index) &&
            ((editor_palette_curve_mode(index) && editor.curve_mode && (index == 5) == editor.curve_cliff_mode) ||
                    (editor_palette_architecture_mode(index) && editor.architecture_paint_mode) ||
                    (editor_palette_climbing_leaves_mode(index) &&
                            editor.authoring_tool == .Foliage &&
                            editor.plant_stamp_mode == .Climbing) ||
                    (editor_palette_road_mode(index) && editor.road_mode) ||
                    (!editor_palette_curve_mode(index) &&
                            !editor_palette_architecture_mode(index) &&
                            !editor_palette_climbing_leaves_mode(index) &&
                            !editor_palette_road_mode(index) &&
                            !editor.curve_mode &&
                            !editor.architecture_paint_mode &&
                            !editor.climbing_leaf_paint_mode &&
                            !editor.road_mode))
        hovered := canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), button)
        fill: canvas2d.Color = {
            r = 18,
            g = 53,
            b = 67,
            a = 255,
        }
        if hovered do fill = {
            r = 35,
            g = 83,
            b = 93,
            a = 255,
        }
        if selected do fill = {
            r = 59,
            g = 137,
            b = 129,
            a = 255,
        }
        border: canvas2d.Color = {
            r = 86,
            g = 153,
            b = 158,
            a = 255,
        }
        if selected do border = {
            r = 211,
            g = 250,
            b = 242,
            a = 255,
        }
        canvas2d.DrawRectangleRounded(button, .14, 8, fill)
        canvas2d.DrawRectangleRoundedLinesEx(button, .14, 8, selected ? 2 : 1, border)
        text_width := ui_measure_text(.Label, labels[index], 1).x
        ui_draw_text(
            .Label,
            labels[index],
            {button.x + (button.width - text_width) * .5, button.y + 11},
            1,
            {r = 239, g = 255, b = 250, a = 255},
        )
    }
}

spawn_button_bounds :: proc() -> canvas2d.Rectangle { return {x = 20, y = 164, width = 170, height = 34} }

editor_overlay_hit :: proc(position: canvas2d.Vector2, width, height: i32) -> bool {
    // These regions are drawn above the viewport and must be treated as UI even
    // when they contain only status text. Otherwise a press on the HUD can
    // begin a terrain stroke through the transparent parts of the overlay.
    if canvas2d.CheckCollisionPointRec(position, {x = 14, y = 14, width = 826, height = 96}) do return true
    if canvas2d.CheckCollisionPointRec(position, {x = f32(width) - 560, y = 14, width = 546, height = 40}) do return true
    if canvas2d.CheckCollisionPointRec(position, {x = 20, y = 210, width = 830, height = 30}) do return true
    return false
}

draw_spawn_button :: proc() {
    bounds := spawn_button_bounds()
    hovered := canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), bounds)
    fill := canvas2d.Color {
        r = 43,
        g = 112,
        b = 119,
        a = 255,
    }
    if hovered do fill = {
        r = 58,
        g = 142,
        b = 150,
        a = 255,
    }
    canvas2d.DrawRectangleRounded(bounds, .18, 8, fill)
    canvas2d.DrawRectangleRoundedLinesEx(bounds, .18, 8, 1, {r = 176, g = 239, b = 230, a = 255})
    ui_draw_text(.Body, "ENTER WORLD", {bounds.x + 28, bounds.y + 9}, 1, {r = 245, g = 255, b = 247, a = 255})
}

draw_editor_context :: proc(editor: ^Editor) {
    if editor == nil || editor.in_map do return
    message: string = ""
    if editor.road_mode {
        if editor.road_drag_node >= 0 && editor.road_drag_node_moved {
            message = "MOVING ROAD NODE  |  LMB release commit  Ctrl+Z undo"
        } else if editor.road_drag_edge >= 0 {
            message = "CURVING ROAD  |  drag handle  LMB release commit  Esc cancel"
        } else if editor.road_selected_node >= 0 {
            message = fmt.tprintf(
                "NODE %d  |  drag node or handles  LMB add/connect  K surface  Alt width  Shift radius",
                editor.road_selected_node + 1,
            )
        } else {
            message = "ROAD NETWORK  |  LMB starts/extends  click nodes to branch  K surface  RMB ends chain"
        }
    } else if editor.tool == .Structure && editor.structure_placing {
        message = fmt.tprintf(
            "PLACING %s  %.0f x %.0f x %.0f m  |  Wheel zoom  Shift size  Alt height/scatter  Esc cancel",
            formation_kind_name(editor.structure_preview.kind),
            editor.structure_preview.width,
            editor.structure_preview.depth,
            editor.structure_preview.height,
        )
    } else if editor.architecture_painting {
        message = fmt.tprintf(
            "PAINTING CITY DENSITY  radius %.0f m  |  LMB darken  RMB lighten  Wheel zoom  Shift flow  Alt hardness",
            settlement_brush_preset_span(editor.architecture_brush_preset) * .5,
        )
    } else if editor.climbing_leaf_painting {
        message = fmt.tprintf(
            "ATTACHING CLIMBER  radius %.0f m  |  LMB stamp  RMB erase  Shift growth  Alt hardness",
            editor.climbing_leaf_brush_radius,
        )
    } else if editor.tool == .Structure &&
       editor.structure_selected >= 0 &&
       editor.structure_selected < editor.project.structure_count {
        structure := editor.project.structures[editor.structure_selected]
        state: cstring = editor.structure_moving ? "MOVING" : "SELECTED"
        message = fmt.tprintf(
            "%s %s  %.0f x %.0f x %.0f m  |  F focus  R rotate  Wheel zoom  Alt height  Shift size  Backspace delete",
            state,
            formation_kind_name(structure.kind),
            structure.width,
            structure.depth,
            structure.height,
        )
    } else if editor.cursor_hit {
        message = fmt.tprintf(
            "CURSOR  X %.0f  Z %.0f  HEIGHT %.2f m  MATERIAL %.2f  |  LMB/RMB sculpt  Wheel zoom  Shift strength  Alt hardness",
            editor.cursor_world_x,
            editor.cursor_world_z,
            editor.cursor_height,
            editor.cursor_material,
        )
    }
    if message == "" do return
    canvas2d.DrawRectangleRounded({20, 210, 830, 30}, .14, 8, {r = 8, g = 28, b = 45, a = 230})
    ui_draw_text(.Data, fmt.ctprintf("%s", message), {30, 219}, 1, {r = 255, g = 244, b = 190, a = 255})
}

runway_spawn_position :: proc(editor: ^Editor) -> third_person.Vec3 {
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    runway_x, runway_z := terrain.default_runway_center_for_project(&editor.project, 1)
    x := runway_x + half_extent * terrain.DEFAULT_RUNWAY_SPAWN_OFFSET
    // Start beside the parked aircraft so the default camera presents it and
    // the runway immediately instead of placing the character inside its mesh.
    z := runway_z + 2.2
    return {x, terrain.sample_surface_height(&editor.project, 0, x, z), z}
}

nearest_town_spawn_position :: proc(editor: ^Editor, from: third_person.Vec3) -> third_person.Vec3 {
    if editor == nil do return {}
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    best := third_person.Vec3{}
    best_distance_squared := f32(3.402823e38)
    for sign in terrain.DEFAULT_ISLAND_SIGNS {
        town_x, town_z := terrain.default_town_center_for_project(&editor.project, sign)
        town := third_person.Vec3{town_x, 0, town_z}
        delta_x := town.x - from.x
        delta_z := town.z - from.z
        distance_squared := delta_x * delta_x + delta_z * delta_z
        if distance_squared < best_distance_squared {
            best = town
            best_distance_squared = distance_squared
        }
    }
    best.y = terrain.sample_surface_height(&editor.project, 0, best.x, best.z)
    return best
}

crash_recovery_active :: proc(editor: ^Editor) -> bool {
    return editor != nil && editor.crash_recovery_phase != .Inactive
}

crash_recovery_begin :: proc(
    editor: ^Editor,
    crash_position: third_person.Vec3,
    cause: Crash_Recovery_Cause = .Crash,
) {
    if editor == nil || crash_recovery_active(editor) do return
    editor.crash_recovery_phase = .Message
    editor.crash_recovery_seconds = 0
    editor.crash_recovery_position = crash_position
    editor.crash_recovery_cause = cause
    editor.flight_control = {}
}

crash_recovery_relocate :: proc(editor: ^Editor) {
    if editor == nil do return

    if editor.pilot.vehicle != nil {
        editor.pilot.vehicle.driver = nil
    }
    editor.pilot.vehicle = nil
    editor.pilot.mode = .On_Foot

    if editor.aircraft.active == .Rondine {
        rondine_game.reset(&editor.rondine, editor.project.sea_level)
    } else if editor.aircraft.active != .Postale {
        ground := terrain.sample_surface_height(
            &editor.project,
            0,
            editor.libellula.spawn_position.x,
            editor.libellula.spawn_position.z,
        )
        libellula_game.reset(&editor.libellula, ground)
    } else {
        ground := postale_game.drivable_surface_height(
            terrain.sample_surface_height(
                &editor.project,
                0,
                editor.postale.spawn_position.x,
                editor.postale.spawn_position.z,
            ),
            editor.project.sea_level,
        )
        postale_game.reset(&editor.postale, ground)
    }

    west_clinic, west_rotation, west_found := world_story_resident_home_pose(editor, .Vesna)
    east_clinic, east_rotation, east_found := world_story_resident_home_pose(editor, .Anica)
    clinic, clinic_rotation, clinic_found := west_clinic, west_rotation, west_found
    if east_found {
        west_distance := f32(3.402823e38)
        if west_found {
            west_delta := west_clinic - editor.crash_recovery_position
            west_distance = linalg.dot(west_delta, west_delta)
        }
        east_delta := east_clinic - editor.crash_recovery_position
        east_distance := linalg.dot(east_delta, east_delta)
        if !west_found || east_distance < west_distance {
            clinic, clinic_rotation, clinic_found = east_clinic, east_rotation, true
        }
    }
    if !clinic_found {
        clinic = nearest_town_spawn_position(editor, editor.crash_recovery_position)
    } else {
        clinic.x += -math.sin(clinic_rotation) * 1.6
        clinic.z += math.cos(clinic_rotation) * 1.6
        clinic.y = terrain.sample_surface_height(&editor.project, 0, clinic.x, clinic.z)
    }
    player_place(editor, clinic, .Crash_Recovery)
    editor.story_state.clinic_visits += 1
    editor.story_state.last_clinic_visit_was_tumble = editor.crash_recovery_cause == .Tumble
    editor.flight_control = {}
    editor.aircraft_fixed_accumulator = 0
    editor.aircraft_previous_body_valid = false
    editor.camera = third_person.default_camera()
    editor.camera_pose = third_person.camera_pose(clinic, editor.camera)
    third_person.camera_set_pose(&editor.cameras, .Player, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Player)
}

crash_recovery_update :: proc(editor: ^Editor, delta_seconds: f32) {
    if !crash_recovery_active(editor) do return
    editor.crash_recovery_seconds += max(delta_seconds, f32(0))
    switch editor.crash_recovery_phase {
    case .Message:
        if editor.crash_recovery_seconds >= CRASH_MESSAGE_SECONDS {
            editor.crash_recovery_phase = .Fade_Out
            editor.crash_recovery_seconds = 0
        }
    case .Fade_Out:
        if editor.crash_recovery_seconds >= CRASH_FADE_OUT_SECONDS {
            crash_recovery_relocate(editor)
            editor.crash_recovery_phase = .Fade_In
            editor.crash_recovery_seconds = 0
        }
    case .Fade_In:
        if editor.crash_recovery_seconds >= CRASH_FADE_IN_SECONDS {
            editor.crash_recovery_phase = .Inactive
            editor.crash_recovery_seconds = 0
        }
    case .Inactive:
    }
}

crash_recovery_draw :: proc(editor: ^Editor, width, height: i32) {
    if !crash_recovery_active(editor) do return
    fade := f32(0)
    if editor.crash_recovery_phase == .Fade_Out {
        fade = clamp(editor.crash_recovery_seconds / CRASH_FADE_OUT_SECONDS, 0, 1)
    } else if editor.crash_recovery_phase == .Fade_In {
        fade = 1 - clamp(editor.crash_recovery_seconds / CRASH_FADE_IN_SECONDS, 0, 1)
    }
    if fade > 0 {
        canvas2d.DrawRectangle(0, 0, width, height, {5, 8, 12, u8(clamp(fade * 255, 0, 255))})
    }
    if editor.crash_recovery_phase == .Message || editor.crash_recovery_phase == .Fade_Out {
        label: cstring = editor.crash_recovery_cause == .Tumble ? "YOU TOOK A TUMBLE" : "YOU CRASHED"
        size := canvas2d.MeasureTextEx(canvas2d.Font{}, label, 34, 2)
        text_alpha := u8(clamp((1 - fade) * 255, 0, 255))
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            label,
            {f32(width) * .5 - size.x * .5, f32(height) * .5 - size.y * .5},
            34,
            2,
            {255, 226, 205, text_alpha},
        )
    }
}

car_spawn_position :: proc(editor: ^Editor) -> third_person.Vec3 {
    // Park the car on the apron beside the runway rather than on the flight
    // surface. This keeps the aircraft arrival lane clear while leaving the car
    // close enough to reach from the default player spawn.
    runway := runway_spawn_position(editor)
    spawn := vehicles.car_spawn_near({runway.x + 8, runway.y, runway.z + 4})
    spawn.y = terrain.sample_surface_height(&editor.project, 0, spawn.x, spawn.z)
    return spawn
}

@(no_instrumentation)
driving_aircraft :: #force_inline proc(editor: ^Editor) -> bool {
    if editor == nil || editor.pilot.mode != .Driving do return false
    return(
        editor.pilot.vehicle == &editor.postale.vehicle ||
        editor.pilot.vehicle == &editor.libellula.vehicle ||
        editor.pilot.vehicle == &editor.rondine.vehicle \
    )
}

driving_car :: proc(editor: ^Editor) -> bool {
    return editor != nil && editor.pilot.mode == .Driving && editor.pilot.vehicle == &editor.car
}

car_physics_rotation :: proc(yaw: f32) -> physics.Quat {
    jolt_yaw := math.PI * .5 - yaw
    return {0, math.sin(jolt_yaw * .5), 0, math.cos(jolt_yaw * .5)}
}

car_physics_yaw :: proc(rotation: physics.Quat) -> f32 {
    jolt_yaw := math.atan2(
        2 * (rotation[3] * rotation[1] + rotation[0] * rotation[2]),
        1 - 2 * (rotation[1] * rotation[1] + rotation[2] * rotation[2]),
    )
    return math.PI * .5 - jolt_yaw
}

car_physics_rotate_vector :: proc(rotation: physics.Quat, vector: physics.Vec3) -> physics.Vec3 {
    q := physics.Vec3{rotation[0], rotation[1], rotation[2]}
    uv := physics.Vec3 {
        q[1] * vector[2] - q[2] * vector[1],
        q[2] * vector[0] - q[0] * vector[2],
        q[0] * vector[1] - q[1] * vector[0],
    }
    uuv := physics.Vec3{q[1] * uv[2] - q[2] * uv[1], q[2] * uv[0] - q[0] * uv[2], q[0] * uv[1] - q[1] * uv[0]}
    scale := 2 * rotation[3]
    return vector + uv * scale + uuv * 2
}

car_physics_level_heights :: proc(editor: ^Editor, level_index: int, result: []f32) {
    if editor == nil ||
       level_index < 0 ||
       level_index >= terrain.CLIPMAP_LEVELS ||
       len(result) < terrain.SAMPLES_PER_LEVEL {
        return
    }
    level := &editor.project.levels[level_index]
    // Island transforms leave authored height samples in source space. Jolt's
    // height fields are world-space objects, so resolve each collision sample
    // through the terrain transform instead of stranding collision at the
    // islands' original coordinates.
    for z in 0 ..< terrain.TERRAIN_RESOLUTION {
        world_z := level.origin_z + f32(z) * level.cell_size
        for x in 0 ..< terrain.TERRAIN_RESOLUTION {
            world_x := level.origin_x + f32(x) * level.cell_size
            result[terrain.sample_index(x, z)] = terrain.sample_surface_height(
                &editor.project,
                level_index,
                world_x,
                world_z,
            )
        }
    }
    if level_index == 0 do return
    finer := &editor.project.levels[level_index - 1]
    // Preserve one coarse-cell apron. Since even-sized grids at successive
    // resolutions cannot share both boundary vertices exactly, the overlap is
    // safer than allowing no-collision vertices to remove the seam triangles.
    apron := level.cell_size
    finer_extent := f32(terrain.TERRAIN_RESOLUTION - 1) * finer.cell_size
    for z in 0 ..< terrain.TERRAIN_RESOLUTION {
        world_z := level.origin_z + f32(z) * level.cell_size
        for x in 0 ..< terrain.TERRAIN_RESOLUTION {
            world_x := level.origin_x + f32(x) * level.cell_size
            if world_x >= finer.origin_x + apron &&
               world_x <= finer.origin_x + finer_extent - apron &&
               world_z >= finer.origin_z + apron &&
               world_z <= finer.origin_z + finer_extent - apron {
                result[terrain.sample_index(x, z)] = math.F32_MAX
            }
        }
    }
}

CAR_PHYSICS_MASS :: f32(720)

car_physics_create :: proc(editor: ^Editor) {
    if editor == nil || editor.car_physics_world != nil do return
    if editor.gameplay_physics.world == nil && !gameplay_physics_create(editor) do return
    editor.car_physics_world = editor.gameplay_physics.world
    ground := terrain.sample_surface_height(&editor.project, 0, editor.car.position.x, editor.car.position.z)
    for level_index in 0 ..< terrain.CLIPMAP_LEVELS {
        editor.car_physics_terrain[level_index] = editor.gameplay_physics.terrain[level_index]
    }
    editor.car_physics_terrain_revision = editor.terrain_revision
    editor.car_physics_vehicle = physics.create_vehicle(
        editor.car_physics_world,
        {
            half_width              = .67,
            half_height             = .25,
            half_length             = 1.22,
            mass                    = CAR_PHYSICS_MASS,
            center_of_mass_offset_y = -.18,
            wheel_x                 = vehicles.CAR_WHEEL_TRACK_HALF,
            front_wheel_z           = vehicles.CAR_WHEELBASE_HALF,
            rear_wheel_z            = -vehicles.CAR_WHEELBASE_HALF,
            wheel_y                 = -.20,
            wheel_radius            = vehicles.CAR_WHEEL_RADIUS,
            wheel_width             = vehicles.CAR_WHEEL_WIDTH,
            suspension_min          = .08,
            // Keep the suspension cast beyond the chassis' resting plane so
            // terrain contact is established before the chassis bottoms out.
            suspension_max          = .38,
            suspension_frequency    = 2.4,
            suspension_damping      = .9,
            max_steer_angle         = math.PI * .19,
            max_engine_torque       = 520,
            max_brake_torque        = 1100,
            max_handbrake_torque    = 1400,
            four_wheel_drive        = false,
        },
        {editor.car.position.x, ground + .74, editor.car.position.z},
        car_physics_rotation(editor.car.yaw_radians),
    )
    editor.car_physics_body_rotation = car_physics_rotation(editor.car.yaw_radians)
    editor.car_physics_body_rotation_valid = editor.car_physics_vehicle != nil
    if editor.car_physics_vehicle == nil {
        editor.car_physics_world = nil
        for level_index in 0 ..< terrain.CLIPMAP_LEVELS {
            editor.car_physics_terrain[level_index] = physics.INVALID_BODY
        }
    }
}

car_physics_destroy :: proc(editor: ^Editor) {
    if editor == nil || editor.car_physics_world == nil do return
    if editor.car_physics_vehicle != nil {
        physics.destroy_vehicle(editor.car_physics_world, editor.car_physics_vehicle)
    }
    editor.car_physics_world = nil
    editor.car_physics_vehicle = nil
    editor.car_physics_body_rotation = physics.IDENTITY_ROTATION
    editor.car_physics_body_rotation_valid = false
    for level_index in 0 ..< terrain.CLIPMAP_LEVELS {
        editor.car_physics_terrain[level_index] = physics.INVALID_BODY
    }
    editor.car_physics_terrain_revision = 0
}

car_physics_teleport :: proc(editor: ^Editor, reset_velocity: bool = true) {
    if editor == nil || editor.car_physics_world == nil || editor.car_physics_vehicle == nil do return
    physics.set_vehicle_transform(
        editor.car_physics_world,
        editor.car_physics_vehicle,
        {editor.car.position.x, editor.car.position.y + .74, editor.car.position.z},
        car_physics_rotation(editor.car.yaw_radians),
        reset_velocity,
    )
    editor.car_physics_body_rotation = car_physics_rotation(editor.car.yaw_radians)
    editor.car_physics_body_rotation_valid = true
    if reset_velocity {
        editor.car_drive = {}
        editor.car_physics_accumulator = 0
    }
}
