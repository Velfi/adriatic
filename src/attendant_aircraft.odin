package main

import dialogue "../packages/dialogue"
import dialogue_session "../packages/dialogue_session"
import engine_sound "../packages/engine_sound"
import flight "../packages/flight"
import game_input "../packages/game_input"
import libellula_game "../packages/libellula"
import marina "../packages/marina"
import postale_game "../packages/postale"
import rondine_game "../packages/rondine"
import story "../packages/story"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:c"
import "core:math"
import "core:math/linalg"
import "core:slice"
import sdl "vendor:sdl3"
import canvas2d "zelda_engine:canvas2d"

attendant_dialogue_close :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.attendant_dialogue_open = false
    engine_sound.dialogue_voice_stop(&editor.engine_audio)
    attendant_dialogue_definition_release(editor)
    game_input.reset_menu_repeat(&editor.runtime_input)
    set_pointer_locked(true)
    _ = sdl.HideCursor()
}

marta_select_aircraft :: proc(editor: ^Editor, target: vehicles.Aircraft_Kind) {
    if editor == nil do return
    if !vehicles.aircraft_fleet_unlock(&editor.aircraft, target) ||
       !vehicles.aircraft_fleet_switch(&editor.aircraft, target) {
        return
    }
    line_position := libellula_spawn_position(editor)
    editor.postale_visible = target == .Postale
    editor.libellula_visible = target == .Libellula || target == .Libellula_Mk2
    editor.postale.vehicle.locked = target != .Postale
    editor.libellula.vehicle.locked = target == .Postale
    line_ground := terrain.sample_height(&editor.project, 0, line_position.x, line_position.z)
    if target != .Postale {
        editor.libellula.spawn_position = {line_position.x, line_position.y, line_position.z}
        libellula_game.reset(&editor.libellula, line_ground)
    } else {
        editor.postale.spawn_position = {line_position.x, line_position.y, line_position.z}
        postale_game.reset(
            &editor.postale,
            postale_game.drivable_surface_height(line_ground, editor.project.sea_level),
        )
    }
    player_place(
        editor,
        {
            line_position.x,
            terrain.sample_height(&editor.project, 0, line_position.x, line_position.z + 1.8),
            line_position.z + 1.8,
        },
        .Aircraft_Selection,
    )
}

rondine_footprint_is_clear_water :: proc(editor: ^Editor, position: flight.Vec3, basis: flight.Basis) -> bool {
    if editor == nil do return false
    forward_samples := [4]f32{-4.5, -1.5, 1.5, 4.5}
    lateral_samples := [5]f32{-8.3, -4.2, 0, 4.2, 8.3}
    for forward_offset in forward_samples {
        for lateral_offset in lateral_samples {
            x := position.x + basis.forward.x * forward_offset + basis.right.x * lateral_offset
            z := position.z + basis.forward.z * forward_offset + basis.right.z * lateral_offset
            terrain_height := terrain.sample_height(&editor.project, 0, x, z)
            surface := terrain.structure_collision_surface_height(&editor.project, x, z, terrain_height)
            if surface > editor.project.sea_level + .15 do return false
        }
    }
    return true
}

rondine_marina_spawn :: proc(
    editor: ^Editor,
    plan: ^marina.Plan,
) -> (
    position: flight.Vec3,
    basis: flight.Basis,
    found: bool,
) {
    if editor == nil || plan == nil || plan.route.count < 2 do return
    outer := marina.plan_world_position(plan, plan.route.points[0])
    inner := marina.plan_world_position(plan, plan.route.points[1])
    outward := flight.Vec3{outer.x - inner.x, 0, outer.z - inner.z}
    length := linalg.length(outward)
    if length <= .01 do return
    outward /= length
    right := linalg.cross(outward, flight.Vec3{0, 1, 0})
    basis = {
        forward = outward,
        up      = {0, 1, 0},
        right   = right,
    }
    // Search progressively farther outside the entrance, then fan sideways.
    // Every candidate clears the complete hull and wing footprint.
    lateral_offsets := [5]f32{0, -14, 14, -28, 28}
    for distance in 18 ..= 90 {
        if distance % 6 != 0 do continue
        for lateral in lateral_offsets {
            candidate := flight.Vec3 {
                outer.x + outward.x * f32(distance) + right.x * lateral,
                editor.project.sea_level + rondine_game.GROUND_CLEARANCE,
                outer.z + outward.z * f32(distance) + right.z * lateral,
            }
            if rondine_footprint_is_clear_water(editor, candidate, basis) {
                return candidate, basis, true
            }
        }
    }
    return
}

stage_rondine :: proc(editor: ^Editor) {
    if editor == nil do return
    plan := east_marina_plan(editor)
    if lab_scene_is_active(editor, "markov-marina") {
        plan = &markov_marina_plan
    }
    spawn, basis, found := rondine_marina_spawn(editor, plan)
    if !found do return
    editor.rondine.spawn_position = spawn
    editor.rondine.spawn_basis = basis
    rondine_game.reset(&editor.rondine, editor.project.sea_level)
    _ = vehicles.aircraft_fleet_unlock(&editor.aircraft, .Rondine)
    _ = vehicles.aircraft_fleet_switch(&editor.aircraft, .Rondine)
    editor.rondine_visible = true
    editor.rondine.vehicle.locked = false
    editor.postale.vehicle.locked = true
    editor.libellula.vehicle.locked = true
}

attendant_dialogue_activate :: proc(editor: ^Editor, choice_index: int) {
    if editor == nil || !editor.attendant_dialogue_open do return
    romance_before := editor.story_state.romance
    session_kind := editor.dialogue_session.kind
    editor.dialogue_session.airfield = .None
    editor.dialogue_session.marina = .None
    current_node := dialogue.current(&editor.attendant_dialogue)
    if session_kind == .Airfield_Services &&
       current_node != nil &&
       current_node.id == "aircraft" &&
       choice_index >= 0 &&
       choice_index < editor.attendant_dialogue_vehicle_choice_count {
        editor.attendant_dialogue_vehicle_target = editor.attendant_dialogue_vehicle_choices[choice_index]
        _ = dialogue_session.set_airfield(&editor.dialogue_session, .Select_Aircraft)
    }
    if !dialogue.choose(&editor.attendant_dialogue, choice_index) do return
    if romance_before != .Meeting && editor.story_state.romance == .Meeting {
        editor.story_meeting_cinematic_pending = true
    }

    airfield_result := editor.dialogue_session.airfield
    marina_result := editor.dialogue_session.marina
    vehicle_target := editor.attendant_dialogue_vehicle_target
    has_result :=
        session_kind == .Airfield_Services && airfield_result != .None ||
        session_kind == .Marina_Dockmaster && marina_result != .None
    if !has_result {
        if editor.attendant_dialogue.ended {
            attendant_dialogue_close(editor)
            if editor.story_meeting_cinematic_pending {
                editor.story_meeting_cinematic_pending = false
                _ = story_meeting_cinematic_play(editor)
            }
            return
        }
        // A submenu transition (including Back) keeps the conversation open.
        editor.attendant_dialogue_focus = 0
        return
    }

    attendant_dialogue_close(editor)
    switch session_kind {
    case .Airfield_Services:
        switch airfield_result {
        case .Paint_Aircraft:
            vehicle_paint_open(editor)
        case .Select_Aircraft:
            marta_select_aircraft(editor, vehicle_target)
        case .None, .Close:
        }
    case .Marina_Dockmaster:
        switch marina_result {
        case .Borrow_Dinghy:
            editor.marina_dinghy_borrowed = true
        case .Stage_Rondine:
            stage_rondine(editor)
        case .None, .Close:
        }
    case .None, .Story:
    }
}

attendant_dialogue_process_input :: proc(editor: ^Editor, width, height: i32, delta_seconds: f32) {
    if editor == nil || !editor.attendant_dialogue_open || pause_menu_is_open(editor) do return
    dialogue_view_update(editor, delta_seconds)
    layout := dialogue_tv_layout(width, height, dialogue.available_count(&editor.attendant_dialogue))
    visible_rows := dialogue_choice_visible_rows(layout)
    dialogue_choice_scroll_focus(editor, visible_rows)
    mouse := canvas2d.GetMousePosition()
    mouse_delta := canvas2d.GetMouseDelta()
    mouse_active :=
        canvas2d.IsMouseButtonPressed(.LEFT) || math.abs(mouse_delta.x) > .01 || math.abs(mouse_delta.y) > .01

    horizontal, vertical := game_input.menu_steps(
        &editor.runtime_input,
        gamepad_axis(.Left_X),
        gamepad_axis(.Left_Y),
        delta_seconds,
    )
    direction := 0
    if canvas2d.IsKeyPressed(.UP) || gamepad_pressed(.Dpad_Up) do direction -= 1
    if canvas2d.IsKeyPressed(.DOWN) || gamepad_pressed(.Dpad_Down) do direction += 1
    if direction == 0 do direction = vertical
    if direction == 0 do direction = horizontal
    choice_count := dialogue.available_count(&editor.attendant_dialogue)
    revealing := dialogue_view_revealing(editor)
    wheel := canvas2d.GetMouseWheelMove()
    speech_current := dialogue.current(&editor.attendant_dialogue)
    speech_bounds := layout.speech
    if speech_current != nil && speech_current.id == "zora-reading" && editor.story_state.tarot_layout.count > 0 {
        speech_bounds.height -= 108 * layout.scale
    }
    speech_text := speech_current != nil ? speech_current.text(&editor.attendant_dialogue.ctx) : ""
    speech_visible_end := clamp(editor.attendant_dialogue_view.revealed_bytes, 0, len(speech_text))
    speech_line_height := 39 * layout.scale
    speech_visible_lines := max(int(speech_bounds.height / speech_line_height), 0)
    speech_line_count := dialogue_wrapped_line_count(
        speech_text[:speech_visible_end],
        speech_bounds,
        29 * layout.scale,
        1 * layout.scale,
    )
    if speech_line_count > speech_visible_lines {
        speech_bounds.width -= 14 * layout.scale
        speech_line_count = dialogue_wrapped_line_count(
            speech_text[:speech_visible_end],
            speech_bounds,
            29 * layout.scale,
            1 * layout.scale,
        )
    }
    dialogue_speech_scroll_sync(editor, speech_line_count, speech_visible_lines)
    speech_max_first := max(speech_line_count - speech_visible_lines, 0)
    stick_scroll := game_input.axis_repeat_step(
        &editor.attendant_dialogue_view.speech_scroll_axis,
        gamepad_axis(.Right_Y),
        delta_seconds,
    )
    if speech_max_first > 0 && stick_scroll != 0 {
        editor.attendant_dialogue_view.first_speech_line = clamp(
            editor.attendant_dialogue_view.first_speech_line + stick_scroll,
            0,
            speech_max_first,
        )
    }
    wheel_over_speech := wheel != 0 && canvas2d.CheckCollisionPointRec(mouse, speech_bounds) && speech_max_first > 0
    if wheel_over_speech {
        editor.attendant_dialogue_view.first_speech_line = clamp(
            editor.attendant_dialogue_view.first_speech_line - int(wheel),
            0,
            speech_max_first,
        )
    } else if !revealing && wheel != 0 && choice_count > visible_rows {
        editor.attendant_dialogue_view.first_choice = clamp(
            editor.attendant_dialogue_view.first_choice - int(wheel),
            0,
            max(choice_count - visible_rows, 0),
        )
        editor.attendant_dialogue_focus = clamp(
            editor.attendant_dialogue_focus,
            editor.attendant_dialogue_view.first_choice,
            min(editor.attendant_dialogue_view.first_choice + visible_rows - 1, choice_count - 1),
        )
    }
    if !revealing && direction != 0 {
        editor.attendant_dialogue_focus = clamp(
            editor.attendant_dialogue_focus + direction,
            0,
            max(choice_count - 1, 0),
        )
        dialogue_choice_scroll_focus(editor, visible_rows)
    }

    if !revealing && mouse_active {
        first := editor.attendant_dialogue_view.first_choice
        last := min(first + visible_rows, choice_count)
        for index in first ..< last {
            if canvas2d.CheckCollisionPointRec(mouse, dialogue_choice_bounds(layout, index - first)) {
                editor.attendant_dialogue_focus = index
            }
        }
    }

    activated := -1
    accept_pressed := input_action_pressed(.Menu_Accept)
    if accept_pressed {
        if revealing {
            dialogue_view_complete_reveal(editor)
        } else if choice_count == 0 {
            if current := dialogue.current(&editor.attendant_dialogue); current != nil {
                remaining := max(current.auto_delay - editor.attendant_dialogue.elapsed, 0)
                _ = dialogue.update(&editor.attendant_dialogue, remaining)
                if editor.attendant_dialogue.ended do attendant_dialogue_close(editor)
            }
        } else {
            activated = editor.attendant_dialogue_focus
        }
    }
    if input_action_pressed(.Menu_Cancel) do activated = max(choice_count - 1, 0)
    if !revealing && canvas2d.IsMouseButtonPressed(.LEFT) {
        first := editor.attendant_dialogue_view.first_choice
        last := min(first + visible_rows, choice_count)
        for index in first ..< last {
            if canvas2d.CheckCollisionPointRec(mouse, dialogue_choice_bounds(layout, index - first)) {
                activated = index
            }
        }
    }
    if activated >= 0 do attendant_dialogue_activate(editor, activated)
}

libellula_attendant_near :: proc(editor: ^Editor) -> bool {
    _, _, found := nearest_service_attendant(editor)
    return found
}

nearest_service_attendant :: proc(editor: ^Editor) -> (resident: story.Resident, distance_squared: f32, found: bool) {
    if editor == nil || editor.pilot.mode != .On_Foot || !editor.libellula_visible do return {}, 0, false
    positions := [2]third_person.Vec3 {
        airport_service_position(editor.attendant_position),
        airport_service_position(editor.gerta_position),
    }
    residents := [2]story.Resident{.Marta, .Gerta}
    best_distance := f32(2.25 * 2.25)
    for position, index in positions {
        delta := editor.player.position - position
        distance := linalg.dot(delta, delta)
        if distance <= best_distance {
            resident, best_distance, found = residents[index], distance, true
        }
    }
    return resident, best_distance, found
}

nearest_story_resident :: proc(
    editor: ^Editor,
    require_action := false,
) -> (
    resident: story.Resident,
    distance_squared: f32,
    found: bool,
) {
    if editor == nil || editor.pilot.mode != .On_Foot do return {}, 0, false
    best_distance := f32(2.25 * 2.25)
    candidates := [10]story.Resident{.Niko, .Iva, .Bojan, .Zora, .Vesna, .Petar, .Anica, .Toma, .Lena, .Mirna}
    for candidate in candidates {
        postal := candidate == .Toma || candidate == .Lena
        if require_action && !postal && !story.resident_has_action(&editor.story_state, candidate) do continue
        position, placed := world_story_resident_position(editor, candidate)
        if !placed do continue
        delta := editor.player.position - position
        distance := linalg.dot(delta, delta)
        if distance <= best_distance {
            resident, best_distance, found = candidate, distance, true
        }
    }
    return resident, best_distance, found
}

draw_libellula_3d :: proc(editor: ^Editor, camera: Perspective_Camera, width, height: i32) {
    mesh := &editor.libellula_visual_mesh
    if editor.aircraft.active == .Libellula_Mk2 {
        vehicles.libellula_mesh_copy(&editor.libellula_mk2_visual_mesh, &editor.libellula_mk2_base_mesh)
        mesh = &editor.libellula_mk2_visual_mesh
        vehicles.animate_libellula_mk2_mesh(
            mesh,
            editor.libellula.rotor_turns.x,
            editor.libellula.rotor_turns.y,
            editor.libellula.rotor_turns.z,
            editor.libellula.rotor_turns.z,
        )
    } else {
        vehicles.libellula_mesh_copy(mesh, &editor.libellula_base_mesh)
        vehicles.animate_libellula_mesh_pose(
            mesh,
            editor.libellula.rotor_turns.x,
            editor.libellula.rotor_turns.y,
            editor.libellula.rotor_turns.z,
            editor.libellula.pitch,
            editor.libellula.roll,
            0,
        )
    }
    clear(&editor.libellula_projected_faces)
    for triangle in vehicles.mesh_triangles(mesh) {
        a := mesh.vertices[triangle.a]
        b := mesh.vertices[triangle.b]
        c := mesh.vertices[triangle.c]
        pa := project_3d(
            camera,
            libellula_vertex_world(&editor.libellula, a.position, LIBELLULA_PRESENTATION_SCALE),
            width,
            height,
        )
        pb := project_3d(
            camera,
            libellula_vertex_world(&editor.libellula, b.position, LIBELLULA_PRESENTATION_SCALE),
            width,
            height,
        )
        pc := project_3d(
            camera,
            libellula_vertex_world(&editor.libellula, c.position, LIBELLULA_PRESENTATION_SCALE),
            width,
            height,
        )
        if !(pa.visible && pb.visible && pc.visible) do continue
        append(
            &editor.libellula_projected_faces,
            Projected_Aircraft_Face {
                a = pa.position,
                b = pb.position,
                c = pc.position,
                depth = (pa.depth + pb.depth + pc.depth) / 3,
                color = aircraft_part_color(a.part),
            },
        )
    }
    faces := editor.libellula_projected_faces[:]
    face_count := len(faces)
    slice.stable_sort_by(faces, proc(a, b: Projected_Aircraft_Face) -> bool { return a.depth > b.depth })
    for face in faces[:face_count] {
        canvas2d.DrawQuadHatched(face.a, face.b, face.c, face.c, face.color, canvas2d.HATCH_DISABLED)
    }
    label := project_3d(
        camera,
        {editor.libellula.body.position.x, editor.libellula.body.position.y + 3.2, editor.libellula.body.position.z},
        width,
        height,
    )
    if label.visible do canvas2d.DrawTextEx(canvas2d.Font{}, "LIBELLULA", {label.position.x - 35, label.position.y - 12}, 13, 1, {r = 255, g = 239, b = 192, a = 255})
}

draw_postale_3d :: proc(editor: ^Editor, camera: Perspective_Camera, width, height: i32) {
    mesh := vehicles.postale_mesh()
    defer free(mesh)
    vehicles.animate_postale_mesh(
        mesh,
        editor.postale.flap_fraction,
        editor.flight_control.pitch,
        editor.flight_control.roll,
        editor.flight_control.yaw,
        editor.postale.propeller_turns,
        editor.postale.gear_compression / POSTALE_PRESENTATION_SCALE,
    )
    // The canvas renderer is painter ordered, so submit the generated aircraft
    // faces back-to-front just like the terrain cells.
    faces: [vehicles.AIRCRAFT_MESH_TRIANGLE_CAPACITY]Projected_Aircraft_Face
    face_count := 0
    for triangle in vehicles.mesh_triangles(mesh) {
        a := mesh.vertices[triangle.a]
        b := mesh.vertices[triangle.b]
        c := mesh.vertices[triangle.c]
        if a.part == .Propeller_Blur && aircraft_propeller_blur_amount(editor.postale.throttle) <= .01 do continue
        pa := project_3d(
            camera,
            postale_vertex_world(&editor.postale, a.position, POSTALE_PRESENTATION_SCALE),
            width,
            height,
        )
        pb := project_3d(
            camera,
            postale_vertex_world(&editor.postale, b.position, POSTALE_PRESENTATION_SCALE),
            width,
            height,
        )
        pc := project_3d(
            camera,
            postale_vertex_world(&editor.postale, c.position, POSTALE_PRESENTATION_SCALE),
            width,
            height,
        )
        if !(pa.visible && pb.visible && pc.visible) do continue
        faces[face_count] = {
            a     = pa.position,
            b     = pb.position,
            c     = pc.position,
            depth = (pa.depth + pb.depth + pc.depth) / 3,
            color = aircraft_postale_part_color_with_paint(editor, a.part, editor.postale.throttle),
        }
        face_count += 1
    }
    slice.stable_sort_by(faces[:face_count], proc(a, b: Projected_Aircraft_Face) -> bool { return a.depth > b.depth })
    for face in faces[:face_count] {
        canvas2d.DrawQuadHatched(face.a, face.b, face.c, face.c, face.color, canvas2d.HATCH_DISABLED)
    }
}

Projected_Aircraft_Face :: struct {
    a, b, c: canvas2d.Vector2,
    depth:   f32,
    color:   canvas2d.Color,
}

@(no_instrumentation)
aircraft_part_color :: #force_inline proc(part: vehicles.Aircraft_Mesh_Part) -> canvas2d.Color {
    #partial switch part {
    case .Wing, .Wing_Root_Fillet, .Tail, .Left_Flap, .Right_Flap, .Left_Aileron, .Right_Aileron, .Elevator, .Rudder:
        return {r = 238, g = 207, b = 120, a = 255}
    case .Glass:
        return {r = 142, g = 207, b = 220, a = 255}
    case .Engine:
        return {r = 177, g = 54, b = 39, a = 255}
    case .Propeller, .Left_Propeller, .Right_Propeller, .Left_Rotor, .Right_Rotor, .Rear_Rotor:
        return {r = 54, g = 43, b = 35, a = 255}
    case .Propeller_Blur:
        return {r = 54, g = 43, b = 35, a = 0}
    case .Float, .Frame:
        return {r = 63, g = 145, b = 160, a = 255}
    case .Carriage:
        return {r = 190, g = 78, b = 48, a = 255}
    case .Wheel:
        return {r = 25, g = 31, b = 36, a = 255}
    case .Bumper, .Rounded_Chrome:
        return {r = 174, g = 184, b = 188, a = 255}
    case .Headlight:
        return {r = 255, g = 239, b = 164, a = 255}
    case .Tail_Light:
        return {r = 211, g = 43, b = 42, a = 255}
    case .Ivory, .Rounded_Ivory:
        return {r = 216, g = 203, b = 180, a = 255}
    case .Red_Paint:
        return {r = 166, g = 65, b = 54, a = 255}
    case .Dark_Metal:
        return {r = 41, g = 44, b = 43, a = 255}
    case .Steel:
        return {r = 118, g = 111, b = 99, a = 255}
    case .Brass, .Rotor_Tip:
        return {r = 195, g = 173, b = 123, a = 255}
    case .Strap:
        return {r = 63, g = 55, b = 48, a = 255}
    case .Rotor_Blade:
        return {r = 61, g = 57, b = 49, a = 255}
    case .Marking:
        return {r = 222, g = 215, b = 195, a = 255}
    case .Lift_Frame:
        return {r = 52, g = 56, b = 55, a = 255}
    case:
        return {r = 34, g = 166, b = 204, a = 255}
    }
}

@(no_instrumentation)
aircraft_propeller_blur_amount :: #force_inline proc(throttle: f32) -> f32 {
    // Match the reference's blade-to-disk handoff: the disk only appears
    // once the propeller is moving quickly enough to read as a volume.
    normalized_rpm := clamp((1.5 + clamp(throttle, 0, 1) * 18) / 19.5, 0, 1)
    return clamp((normalized_rpm - .42) / .36, 0, 1)
}
