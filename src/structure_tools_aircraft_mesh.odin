package main

import architecture "../packages/architecture"
import flight "../packages/flight"
import game_input "../packages/game_input"
import libellula_game "../packages/libellula"
import postale_game "../packages/postale"
import rondine_game "../packages/rondine"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:c"
import "core:math"
import "core:math/linalg"
import sdl "vendor:sdl3"
import canvas2d "zelda_engine:canvas2d"
import physics "zelda_engine:physics"

plant_stamp_update_target :: proc(
    editor: ^Editor,
    camera: Perspective_Camera,
    mouse: canvas2d.Vector2,
    width, height: i32,
    enabled: bool,
) {
    if editor == nil {
        return
    }
    if editor.plant_stamp_target_locked do return
    editor.plant_stamp_target_valid = false
    editor.plant_stamp_target_index = -1
    if !enabled || width <= 0 || height <= 0 || editor.authoring_tool != .Foliage || editor.plant_stamp_mode != .Climbing do return
    screen_x := (mouse.x / f32(width) - .5) * 2
    screen_y := (.5 - mouse.y / f32(height)) * 2
    aspect := f32(width) / f32(height)
    direction := linalg.normalize0(
        third_person.Vec3 {
            camera.forward.x +
            camera.right.x * screen_x * aspect / camera.focal_length +
            camera.up.x * screen_y / camera.focal_length,
            camera.forward.y +
            camera.right.y * screen_x * aspect / camera.focal_length +
            camera.up.y * screen_y / camera.focal_length,
            camera.forward.z +
            camera.right.z * screen_x * aspect / camera.focal_length +
            camera.up.z * screen_y / camera.focal_length,
        },
    )
    best_distance := f32(1.0e30)
    padding := clamp(editor.climbing_leaf_brush_radius * .08, f32(.35), terrain.BASE_CELL_SIZE)
    for index in 0 ..< editor.project.structure_count {
        structure := editor.project.structures[index]
        if !plant_stamp_climbing_eligible(structure.kind) do continue
        distance, hit := plant_stamp_ray_structure_distance(structure, camera.position, direction, padding)
        if hit && distance < best_distance {
            best_distance = distance
            editor.plant_stamp_target_index = index
            editor.plant_stamp_target_valid = true
        }
    }
}

climbing_leaf_paint_stamp :: proc(editor: ^Editor, _: f32, _: f32, erase: bool) {
    if editor == nil do return
    if !editor.plant_stamp_target_valid ||
       editor.plant_stamp_target_index < 0 ||
       editor.plant_stamp_target_index >= editor.project.structure_count {
        return
    }
    target := editor.project.structures[editor.plant_stamp_target_index]
    // The editor radius controls target acquisition, not a terrain paint
    // splash. Keep the persistent stamp tight to the chosen footprint so a
    // nearby row of buildings does not all acquire the same climber.
    stamp_radius := max(terrain.BASE_CELL_SIZE, max(target.width, target.depth) * .62)
    stamp_x, stamp_z := terrain.island_source_position(&editor.project, target.center_x, target.center_z)
    _ = architecture.city_density_stamp(
        &editor.project.climbing_leaf_density,
        stamp_x,
        stamp_z,
        stamp_radius,
        editor.climbing_leaf_brush_strength * .08,
        editor.climbing_leaf_brush_hardness,
        erase,
    )
    editor.project.revision += 1
}

climbing_leaf_paint_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || editor.authoring_tool != .Foliage || editor.plant_stamp_mode != .Climbing do return
    if !cursor_hit || !editor.plant_stamp_target_valid {
        if canvas2d.IsMouseButtonReleased(.LEFT) || canvas2d.IsMouseButtonReleased(.RIGHT) do editor.climbing_leaf_painting = false
        return
    }
    pressed := canvas2d.IsMouseButtonPressed(.LEFT) || canvas2d.IsMouseButtonPressed(.RIGHT)
    down := canvas2d.IsMouseButtonDown(.LEFT) || canvas2d.IsMouseButtonDown(.RIGHT)
    if pressed {
        structure_history_push_undo(editor)
        editor.climbing_leaf_painting = true
        editor.climbing_leaf_last_x, editor.climbing_leaf_last_z = world_x, world_z
        climbing_leaf_paint_stamp(editor, world_x, world_z, canvas2d.IsMouseButtonDown(.RIGHT))
        editor.plant_stamp_last_stamped_id = editor.project.structures[editor.plant_stamp_target_index].id
    }
    if editor.climbing_leaf_painting && down && !pressed {
        target_id := editor.project.structures[editor.plant_stamp_target_index].id
        if target_id != editor.plant_stamp_last_stamped_id {
            climbing_leaf_paint_stamp(editor, world_x, world_z, canvas2d.IsMouseButtonDown(.RIGHT))
            editor.plant_stamp_last_stamped_id = target_id
        }
        editor.climbing_leaf_last_x, editor.climbing_leaf_last_z = world_x, world_z
    }
    if editor.climbing_leaf_painting &&
       (canvas2d.IsMouseButtonReleased(.LEFT) || canvas2d.IsMouseButtonReleased(.RIGHT)) {
        editor.climbing_leaf_painting = false
    }
}

structure_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || editor.tool != .Structure do return
    if imgui_captures_keyboard() do return
    cell := editor.project.levels[0].cell_size
    if control_key_down() && canvas2d.IsKeyPressed(.Z) {
        structure_undo(editor)
        editor.structure_placing = false
        editor.structure_moving = false
        return
    }
    if control_key_down() && canvas2d.IsKeyPressed(.Y) {
        structure_redo(editor)
        editor.structure_placing = false
        editor.structure_moving = false
        return
    }
    if canvas2d.IsKeyPressed(.BACKSPACE) && editor.structure_selected >= 0 && !editor.structure_placing {
        structure_history_push_undo(editor)
        terrain.remove_structure(&editor.project, editor.structure_selected)
        editor.structure_selected = -1
    }
    if control_key_down() && canvas2d.IsKeyPressed(.D) && editor.structure_selected >= 0 {
        structure_history_push_undo(editor)
        index := terrain.duplicate_structure(&editor.project, editor.structure_selected, cell * 2, cell * 2)
        if index >= 0 do editor.structure_selected = index
    }
    if canvas2d.IsKeyPressed(.R) {
        if editor.structure_placing {
            editor.structure_preview.rotation += math.PI / 12
        } else if editor.structure_selected >= 0 {
            structure_history_push_undo(editor)
            editor.project.structures[editor.structure_selected].rotation += math.PI / 12
            editor.project.revision += 1
        }
    }
    if !cursor_hit {
        if canvas2d.IsMouseButtonReleased(.LEFT) || canvas2d.IsMouseButtonReleased(.RIGHT) {
            editor.structure_placing = false
            editor.structure_moving = false
            editor.island_moving = false
        }
        return
    }
    if canvas2d.IsMouseButtonPressed(.LEFT) || canvas2d.IsMouseButtonPressed(.RIGHT) {
        index :=
            canvas2d.IsMouseButtonPressed(.LEFT) ? terrain.structure_index_at(&editor.project, world_x, world_z) : -1
        if index >= 0 {
            editor.structure_selected = index
            editor.island_selected = .World
            editor.structure_moving = true
            structure_history_push_undo(editor)
            editor.structure_grab_offset_x = editor.project.structures[index].center_x - world_x
            editor.structure_grab_offset_z = editor.project.structures[index].center_z - world_z
        } else {
            editor.structure_selected = -1
            if editor.selection_tool_active {
                selected_island := terrain.island_at(&editor.project, world_x, world_z)
                editor.island_selected = selected_island
                if selected_island != .World && canvas2d.IsMouseButtonPressed(.LEFT) {
                    center_x, center_z, center_ok := terrain.island_center(&editor.project, selected_island)
                    if center_ok {
                        structure_history_push_undo(editor)
                        editor.island_moving = true
                        editor.island_drag_start_x, editor.island_drag_start_z = world_x, world_z
                        editor.island_drag_center_x, editor.island_drag_center_z = center_x, center_z
                    }
                }
                return
            }
            editor.structure_placing = true
            editor.structure_anchor_x = structure_editor_snap(world_x, editor)
            editor.structure_anchor_z = structure_editor_snap(world_z, editor)
            editor.structure_preview_end_x = editor.structure_anchor_x
            editor.structure_preview_end_z = editor.structure_anchor_z
            editor.structure_preview = terrain.structure_make(
                editor.structure_anchor_x,
                editor.structure_anchor_z,
                cell,
                cell,
                0,
                editor.authoring_tool == .Foliage ? cell * 3 : cell * 12,
            )
            if editor.authoring_tool == .Foliage && editor.structure_kind == .Field {
                editor.structure_preview.height = 1.4
            }
            editor.structure_force_box = control_key_down()
            editor.structure_cliff_mode = canvas2d.IsMouseButtonPressed(.RIGHT)
            editor.structure_scatter_mode = alt_key_down()
            structure_update_preview_kind(editor)
            structure_update_base(editor, &editor.structure_preview)
        }
    }
    if editor.structure_placing {
        end_x := structure_editor_snap(world_x, editor)
        end_z := structure_editor_snap(world_z, editor)
        editor.structure_preview_end_x = end_x
        editor.structure_preview_end_z = end_z
        if editor.authoring_tool == .Foliage && editor.foliage_hedgerow_mode {
            dx, dz := end_x - editor.structure_anchor_x, end_z - editor.structure_anchor_z
            length := f32(math.sqrt(f64(dx * dx + dz * dz)))
            editor.structure_preview.center_x = (editor.structure_anchor_x + end_x) * .5
            editor.structure_preview.center_z = (editor.structure_anchor_z + end_z) * .5
            editor.structure_preview.width = max(length, cell)
            editor.structure_preview.depth = clamp(editor.formation_brush_radius * .25, cell, cell * 3)
            editor.structure_preview.height = clamp(editor.formation_brush_radius * .32, cell, cell * 4)
            if length > .001 do editor.structure_preview.rotation = math.atan2(dz, dx)
        } else {
            editor.structure_preview.center_x = (editor.structure_anchor_x + end_x) * .5
            editor.structure_preview.center_z = (editor.structure_anchor_z + end_z) * .5
            editor.structure_preview.width = max(math.abs(end_x - editor.structure_anchor_x), cell)
            editor.structure_preview.depth = max(math.abs(end_z - editor.structure_anchor_z), cell)
        }
        structure_update_preview_kind(editor)
        structure_update_base(editor, &editor.structure_preview)
        if canvas2d.IsMouseButtonReleased(.LEFT) || canvas2d.IsMouseButtonReleased(.RIGHT) {
            structure_history_push_undo(editor)
            index := structure_commit_placement(editor, world_x, world_z)
            if index >= 0 do editor.structure_selected = index
            editor.structure_placing = false
        }
    } else if editor.island_moving && editor.island_selected != .World {
        next_x := editor.island_drag_center_x + world_x - editor.island_drag_start_x
        next_z := editor.island_drag_center_z + world_z - editor.island_drag_start_z
        _ = editor_island_set_center(editor, editor.island_selected, next_x, next_z)
        if canvas2d.IsMouseButtonReleased(.LEFT) do editor.island_moving = false
    } else if editor.structure_moving && editor.structure_selected >= 0 {
        structure := &editor.project.structures[editor.structure_selected]
        structure.center_x = structure_editor_snap(world_x + editor.structure_grab_offset_x, editor)
        structure.center_z = structure_editor_snap(world_z + editor.structure_grab_offset_z, editor)
        structure_update_base(editor, structure)
        if canvas2d.IsMouseButtonReleased(.LEFT) do editor.structure_moving = false
    }
}

structure_adjust_with_wheel :: proc(editor: ^Editor, wheel: f32) {
    if editor == nil || editor.tool != .Structure || wheel == 0 do return
    cell := editor.project.levels[0].cell_size
    if editor.structure_placing {
        if editor.structure_scatter_mode && alt_key_down() {
            editor.structure_scatter_count = clamp(editor.structure_scatter_count + int(wheel), 2, 8)
        } else if shift_key_down() {
            editor.structure_preview.width = max(cell, editor.structure_preview.width + wheel * cell * 2)
            editor.structure_preview.depth = max(cell, editor.structure_preview.depth + wheel * cell * 2)
        } else {
            if editor.structure_preview.kind == .Architecture {
                editor.structure_preview.height = architecture.facade_step_height(
                    editor.structure_preview.height,
                    wheel > 0 ? 1 : -1,
                )
            } else {
                editor.structure_preview.height = max(cell, editor.structure_preview.height + wheel * cell * 2)
            }
        }
    } else if editor.structure_selected >= 0 {
        structure_history_push_undo(editor)
        selected_group := editor.project.structures[editor.structure_selected].group_id
        if shift_key_down() {
            for index in 0 ..< editor.project.structure_count {
                structure := &editor.project.structures[index]
                if structure.group_id != selected_group do continue
                structure.width = max(cell, structure.width + wheel * cell * 2)
                structure.depth = max(cell, structure.depth + wheel * cell * 2)
            }
        } else {
            for index in 0 ..< editor.project.structure_count {
                structure := &editor.project.structures[index]
                if structure.group_id != selected_group do continue
                if structure.kind == .Architecture {
                    structure.height = architecture.facade_step_height(structure.height, wheel > 0 ? 1 : -1)
                } else {
                    structure.height = max(cell, structure.height + wheel * cell * 2)
                }
            }
        }
        editor.project.revision += 1
    }
}

set_pointer_locked :: proc(locked: bool) {
    if window := sdl.GetKeyboardFocus(); window != nil {
        _ = sdl.SetWindowRelativeMouseMode(window, locked)
    }
}

project_point :: proc(x, z, height: f32, center: canvas2d.Vector2, scale: f32) -> canvas2d.Vector2 {
    return {center.x + (x - z) * scale, center.y + (x + z) * scale * .46 - height * scale}
}

Perspective_Camera :: struct {
    position, right, up, forward: third_person.Vec3,
    focal_length:                 f32,
}

Screen_Point :: struct {
    position: canvas2d.Vector2,
    depth:    f32,
    visible:  bool,
}

controller_stick_deadzone_active := f32(.16)
controller_trigger_deadzone_active := f32(.04)

controller_deadzone_apply :: proc(settings: Gameplay_Options) {
    controller_stick_deadzone_active = clamp(settings.controller_stick_deadzone, 0, .5)
    controller_trigger_deadzone_active = clamp(settings.controller_trigger_deadzone, 0, .5)
}

shape_flight_axis :: proc(value: f32, dead_zone: f32 = .16) -> f32 {
    magnitude := math.abs(value)
    if magnitude <= dead_zone do return 0
    return math.sign(value) * clamp((magnitude - dead_zone) / (1 - dead_zone), 0, 1)
}

gamepad_axis :: proc(axis: canvas2d.Gamepad_Axis) -> f32 {
    if !canvas2d.GamepadAvailable() do return 0
    dead_zone := controller_stick_deadzone_active
    if axis == .Left_Trigger || axis == .Right_Trigger {
        dead_zone = controller_trigger_deadzone_active
    }
    return shape_flight_axis(canvas2d.GetGamepadAxis(axis), dead_zone)
}

gamepad_pressed :: proc(button: canvas2d.Gamepad_Button) -> bool {
    return canvas2d.GamepadAvailable() && canvas2d.IsGamepadButtonPressed(button)
}

gamepad_down :: proc(button: canvas2d.Gamepad_Button) -> bool {
    return canvas2d.GamepadAvailable() && canvas2d.IsGamepadButtonDown(button)
}

aircraft_reset :: proc(editor: ^Editor) {
    if editor == nil do return
    if lab_scene_is_active(editor, "markov-wreck") && editor.aircraft.active == .Postale {
        _ = markov_wreck_reset_postale(editor)
        return
    }
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
    editor.aircraft_fixed_accumulator = 0
    editor.aircraft_previous_body_valid = false
    vehicles.sync_driver(&editor.pilot)
}

Input_Action :: enum {
    Pause,
    Journal,
    Jump,
    Run,
    Interact,
    Camera_Reset,
    Handbrake,
    Menu_Accept,
    Menu_Cancel,
}

input_action_pressed :: proc(action: Input_Action) -> bool {
    switch action {
    case .Pause:
        return (!shift_key_down() && canvas2d.IsKeyPressed(.ESCAPE)) || gamepad_pressed(.Start)
    case .Journal:
        return canvas2d.IsKeyPressed(.J) || gamepad_pressed(.Back)
    case .Jump:
        return canvas2d.IsKeyPressed(.SPACE) || gamepad_pressed(.South)
    case .Run:
        return canvas2d.IsKeyPressed(.LEFT_SHIFT) || canvas2d.IsKeyPressed(.RIGHT_SHIFT) || gamepad_pressed(.North)
    case .Interact:
        return canvas2d.IsKeyPressed(.F) || gamepad_pressed(.West)
    case .Camera_Reset:
        return canvas2d.IsKeyPressed(.C) || gamepad_pressed(.South)
    case .Menu_Accept:
        return canvas2d.IsKeyPressed(.ENTER) || gamepad_pressed(.South)
    case .Menu_Cancel:
        return (!shift_key_down() && canvas2d.IsKeyPressed(.ESCAPE)) || gamepad_pressed(.East)
    case .Handbrake:
        return canvas2d.IsKeyPressed(.SPACE) || gamepad_pressed(.Right_Shoulder)
    }
    return false
}

input_action_down :: proc(action: Input_Action) -> bool {
    #partial switch action {
    case .Jump:
        return canvas2d.IsKeyDown(.SPACE) || gamepad_down(.South)
    case .Handbrake:
        return canvas2d.IsKeyDown(.SPACE) || gamepad_down(.Right_Shoulder)
    case .Run:
        return shift_key_down() || gamepad_down(.North)
    }
    return input_action_pressed(action)
}

controller_journal_label :: proc(editor: ^Editor) -> cstring {
    if editor == nil do return "VIEW"
    switch editor.runtime_input.controller_style {
    case .Xbox:
        return "VIEW"
    case .PlayStation:
        return "SHARE"
    case .Nintendo:
        return "MINUS"
    case .Generic:
        return "BACK"
    }
    return "VIEW"
}

controller_prompt_active :: proc(editor: ^Editor) -> bool {
    return editor != nil && game_input.controller_active(&editor.runtime_input)
}

controller_face_label :: proc(editor: ^Editor, button: game_input.Face_Button) -> cstring {
    if editor == nil do return "BUTTON"
    return game_input.face_button_label(editor.runtime_input.controller_style, button)
}

controller_style_detect :: proc() -> game_input.Controller_Style {
    count: c.int
    ids := sdl.GetGamepads(&count)
    if ids == nil || count <= 0 do return .Generic
    defer sdl.free(ids)
    controller_type := sdl.GetRealGamepadTypeForID(ids[0])
    if controller_type == .UNKNOWN || controller_type == .STANDARD {
        controller_type = sdl.GetGamepadTypeForID(ids[0])
    }
    switch controller_type {
    case .XBOX360, .XBOXONE:
        return .Xbox
    case .PS3, .PS4, .PS5:
        return .PlayStation
    case .NINTENDO_SWITCH_PRO,
         .NINTENDO_SWITCH_JOYCON_LEFT,
         .NINTENDO_SWITCH_JOYCON_RIGHT,
         .NINTENDO_SWITCH_JOYCON_PAIR:
        return .Nintendo
    case .UNKNOWN, .STANDARD:
        return .Generic
    }
    return .Generic
}

runtime_input_sample :: proc() -> game_input.Sample {
    sample := game_input.Sample {
        now_seconds      = canvas2d.GetTime(),
        controller_found = canvas2d.GamepadAvailable(),
    }
    mouse_delta := canvas2d.GetMouseDelta()
    sample.mouse_activity =
        math.abs(mouse_delta.x) > 1.5 ||
        math.abs(mouse_delta.y) > 1.5 ||
        math.abs(canvas2d.GetMouseWheelMove()) > .01 ||
        canvas2d.IsMouseButtonPressed(.LEFT) ||
        canvas2d.IsMouseButtonPressed(.RIGHT) ||
        canvas2d.IsMouseButtonPressed(.MIDDLE)
    for key in canvas2d.KeyboardKey {
        if key == .COUNT do continue
        if canvas2d.IsKeyPressed(key) {
            sample.keyboard_activity = true
            break
        }
    }
    if sample.controller_found {
        for button in canvas2d.Gamepad_Button {
            if button == .Count do continue
            if canvas2d.IsGamepadButtonDown(button) {
                sample.button_activity = true
                break
            }
        }
        sample.axes = {
            canvas2d.GetGamepadAxis(.Left_X),
            canvas2d.GetGamepadAxis(.Left_Y),
            canvas2d.GetGamepadAxis(.Right_X),
            canvas2d.GetGamepadAxis(.Right_Y),
            canvas2d.GetGamepadAxis(.Left_Trigger),
            canvas2d.GetGamepadAxis(.Right_Trigger),
        }
    }
    return sample
}

runtime_input_update :: proc(editor: ^Editor) -> game_input.Update_Result {
    if editor == nil || !editor.in_map do return {}
    result := game_input.update(&editor.runtime_input, runtime_input_sample())
    if result.controller_connected {
        editor.runtime_input.controller_style = controller_style_detect()
    }
    return result
}

runtime_pointer_sync :: proc(editor: ^Editor) {
    if editor == nil do return
    if editor.active_lab_scene != "" {
        set_pointer_locked(false)
        _ = sdl.ShowCursor()
    } else if !editor.in_map {
        return
    } else if editor.vehicle_paint_scene {
        set_pointer_locked(false)
        _ = sdl.ShowCursor()
    } else if editor.tweak_panel_visible || pause_menu_is_open(editor) {
        set_pointer_locked(false)
        if controller_prompt_active(editor) {
            _ = sdl.HideCursor()
        } else {
            _ = sdl.ShowCursor()
        }
    } else if editor.attendant_dialogue_open {
        set_pointer_locked(false)
        _ = sdl.ShowCursor()
    } else {
        set_pointer_locked(true)
        _ = sdl.HideCursor()
    }
}

stronger_axis :: proc(first, second: f32) -> f32 {
    if math.abs(second) > math.abs(first) do return second
    return first
}

@(no_instrumentation)
control_key_down :: #force_inline proc() -> bool {
    keys := sdl.GetKeyboardState(nil)
    return keys[int(sdl.Scancode.LCTRL)] || keys[int(sdl.Scancode.RCTRL)]
}

@(no_instrumentation)
shift_key_down :: #force_inline proc() -> bool {
    keys := sdl.GetKeyboardState(nil)
    return keys[int(sdl.Scancode.LSHIFT)] || keys[int(sdl.Scancode.RSHIFT)]
}

@(no_instrumentation)
alt_key_down :: #force_inline proc() -> bool {
    keys := sdl.GetKeyboardState(nil)
    return keys[int(sdl.Scancode.LALT)] || keys[int(sdl.Scancode.RALT)]
}

editor_debug_toggle_pressed :: proc(editor: ^Editor) -> bool {
    if editor == nil do return false
    keys := sdl.GetKeyboardState(nil)
    shift := keys[int(sdl.Scancode.LSHIFT)] || keys[int(sdl.Scancode.RSHIFT)]
    down := shift && keys[int(sdl.Scancode.ESCAPE)]
    pressed := down && !editor.editor_ui.debug_key_down
    editor.editor_ui.debug_key_down = down
    return pressed
}

tweak_panel_console_key_pressed :: proc(editor: ^Editor) -> bool {
    if editor == nil do return false
    keys := sdl.GetKeyboardState(nil)
    down := keys[int(sdl.Scancode.GRAVE)]
    pressed := down && !editor.tweak_panel_toggle_down
    editor.tweak_panel_toggle_down = down
    return pressed
}

postale_spawn_position :: proc(editor: ^Editor) -> flight.Vec3 {
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    runway_x, runway_z := terrain.default_runway_center_for_project(&editor.project, 1)
    x := runway_x + half_extent * terrain.DEFAULT_RUNWAY_SPAWN_OFFSET
    z := runway_z
    ground := postale_game.drivable_surface_height(
        terrain.sample_surface_height(&editor.project, 0, x, z),
        editor.project.sea_level,
    )
    return {x, ground + postale_game.GROUND_CLEARANCE, z}
}

flight_to_world :: proc(value: flight.Vec3) -> third_person.Vec3 {
    return {value.x, value.y, value.z}
}

// The source Postale mesh is presented slightly larger so the cockpit and
// undercarriage fit the mouse pilot without changing gameplay physics.
POSTALE_PRESENTATION_SCALE :: f32(.714)
LIBELLULA_PRESENTATION_SCALE :: f32(.72)

// The rebuilt Postale wing tips are swept forward and rise with the wing's
// dihedral. Keep these anchors on the outer trailing-edge vertices so the
// streams do not appear behind, below, or outside the visible wing.
POSTALE_WING_TRAIL_LOCAL_X :: f32(4.96)
POSTALE_WING_TRAIL_LOCAL_Y :: f32(.08 + 4.96 * .045)
POSTALE_WING_TRAIL_LOCAL_Z :: f32(-.39)
RONDINE_WING_TRAIL_LOCAL_X :: f32(8.72)
RONDINE_WING_TRAIL_LOCAL_Y :: f32(.72)
RONDINE_WING_TRAIL_LOCAL_Z :: f32(1.22)

@(no_instrumentation)
postale_vertex_world :: #force_inline proc(
    runtime: ^postale_game.Runtime,
    position: [3]f32,
    scale: f32,
) -> third_person.Vec3 {
    return world_model_vertex_world(world_aircraft_transform(runtime.body, scale), position)
}
