#+feature using-stmt
package main

import atmosphere "../packages/atmosphere"
import boats "../packages/boats"
import chase_camera "../packages/chase_camera"
import dio "../packages/dio"
import engine_sound "../packages/engine_sound"
import flight "../packages/flight"
import game_input "../packages/game_input"
import libellula_game "../packages/libellula"
import ocean_audio "../packages/ocean_audio"
import particle_systems "../packages/particles"
import postale_game "../packages/postale"
import roads "../packages/roads"
import rondine_game "../packages/rondine"
import scene_stack "../packages/scene_stack"
import spray_audio "../packages/spray_audio"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import wind_audio "../packages/wind_audio"
import "core:fmt"
import "core:math"
import "core:time"
import sdl "vendor:sdl3"
import canvas2d "zelda_engine:canvas2d"
import physics "zelda_engine:physics"

run_frame_prepare_input :: proc(using run: ^Run_State, using frame_state: ^Run_Frame_State) {
    benchmark_frame_start = canvas2d.GetTime()
    frame_now := canvas2d.GetTime()
    frame_delta = frame == 0 ? f32(0) : min(f32(frame_now - editor.last_frame_time), f32(.1))
    if cinematic_export_active {
        frame_delta = 1 / f32(max(request.sequence_fps, 1))
        cinematic_export_time = f32(max(frame - capture_frame, 0)) / f32(max(request.sequence_fps, 1))
    }
    editor.last_frame_time = frame_now
    // map_time drives low-frequency presentation animation. Keep it
    // separate from the f64 clock used for simulation deltas: subtracting
    // absolute f32 timestamps loses frame-scale precision as uptime grows.
    editor.map_time = f32(frame_now)
    driving = editor.pilot.mode == .Driving
    dialogue_was_open = editor.attendant_dialogue_open
    width, height = canvas2d.GetScreenWidth(), canvas2d.GetScreenHeight()
    // A resized window changes the user's aspect ratio. Reapplying the
    // selected vertical-resolution preset keeps the world target in step.
    crunchiness_apply(editor.gameplay_options.crunchiness)
    input_result := runtime_input_update(editor)
    if input_result.pause_for_disconnect {
        editor.controller_disconnect_notice = true
        if !pause_menu_is_open(editor) do pause_menu_open(editor)
    }
    if !pause_menu_is_open(editor) do game_input.reset_menu_repeat(&editor.runtime_input)
    was_paused := pause_menu_is_open(editor)
    tweak_panel_console_key := tweak_panel_console_key_pressed(editor)
    if !pause_menu_is_open(editor) && tweak_panel_console_key {
        editor.tweak_panel_visible = !editor.tweak_panel_visible
    }
    pause_menu_process_input(editor, width, height, frame_delta)
    scene_stack.update(&editor.menu_scene_stack, frame_delta)
    runtime_pointer_sync(editor)
    attendant_dialogue_process_input(editor, width, height, frame_delta)
    simulation_delta = was_paused || pause_menu_is_open(editor) ? f32(0) : frame_delta
    friendship_notice_step(editor, simulation_delta)
    atmosphere.step(&editor.atmosphere, simulation_delta)
    surface_weather_step(editor, simulation_delta)
    if lab_scene_is_active(editor, "rainbow") {
        // The rainbow lab intentionally authors a sun-shower between the
        // built-in presets. Keep that state authoritative instead of
        // replacing it with the uniform Storm override sampled below.
        rainbow_lab_apply_weather(editor)
    } else {
        observer_weather := atmosphere_local_weather(editor, editor.camera_pose.position)
        editor.atmosphere.weather = {
            observer_weather.cloud_cover,
            observer_weather.precipitation,
            observer_weather.haze,
            observer_weather.severity,
            {observer_weather.wind[0], observer_weather.wind[2]},
        }
    }
    boats.step(&editor.boat_traffic, simulation_delta, editor.atmosphere.world_minutes)
    boats.ocean_traffic_step(&editor.ocean_traffic, simulation_delta)
    world_flocks_step(editor, simulation_delta)
    gameplay_physics_sync_boats(editor, simulation_delta)
    markov_marina_buoy_physics_step(editor, simulation_delta)
    wind_x, wind_z := editor.atmosphere.weather.wind[0], editor.atmosphere.weather.wind[1]
    wind_speed := f32(math.sqrt(f64(wind_x * wind_x + wind_z * wind_z)))
    listener_yaw = editor.in_map ? editor.camera.yaw_radians : editor.editor_camera.yaw_radians
    listener_velocity_x, listener_velocity_y, listener_velocity_z := f32(0), f32(0), f32(0)
    if editor.in_map {
        if driving_aircraft(editor) {
            listener_body := active_aircraft_body(editor)
            listener_velocity_x, listener_velocity_y, listener_velocity_z =
                listener_body.velocity.x, listener_body.velocity.y, listener_body.velocity.z
        } else if driving_car(editor) {
            listener_velocity_x, listener_velocity_z =
                editor.car_drive.velocity.x * .35, editor.car_drive.velocity.z * .35
        } else {
            listener_velocity_x, listener_velocity_z = editor.player.velocity.x * .55, editor.player.velocity.z * .55
        }
    }
    apparent_airflow_speed := wind_audio.apparent_airflow_speed(
        wind_x,
        wind_z,
        listener_velocity_x,
        listener_velocity_z,
        listener_velocity_y,
    )
    wind_direction := wind_audio.apparent_lateral_direction(
        wind_x,
        wind_z,
        listener_velocity_x,
        listener_velocity_z,
        listener_yaw,
    )
    if wind_audio_ready {
        wind_audio.update(
            &wind_sound_state,
            wind_speed,
            0,
            editor.atmosphere.weather.precipitation,
            editor.atmosphere.weather.severity,
            wind_direction,
            sound_fx_muted(editor),
            wind_audio.apparent_airflow_strength(apparent_airflow_speed, wind_speed),
        )
    }
    if ocean_audio_ready {
        listener_height_above_sea := f32(0)
        listener_x, listener_z := f32(0), f32(0)
        if editor.in_map {
            if driving_aircraft(editor) {
                listener_body := active_aircraft_body(editor)
                listener_height_above_sea = listener_body.position.y - editor.project.sea_level
                listener_x, listener_z = listener_body.position.x, listener_body.position.z
            } else if driving_car(editor) {
                listener_height_above_sea = editor.car.position.y - editor.project.sea_level
                listener_x, listener_z = editor.car.position.x, editor.car.position.z
            } else {
                listener_height_above_sea = editor.player.position.y - editor.project.sea_level
                listener_x, listener_z = editor.player.position.x, editor.player.position.z
            }
        } else {
            listener_height_above_sea = editor.camera_pose.position.y - editor.project.sea_level
            listener_x, listener_z = editor.camera_pose.position.x, editor.camera_pose.position.z
        }
        shore_proximity := ocean_shore_proximity(editor, listener_x, listener_z)
        ocean_direction := wind_audio.wind_lateral_direction(wind_x, wind_z, listener_yaw)
        ocean_audio.update(
            &ocean_sound_state,
            wind_speed,
            editor.atmosphere.weather.severity,
            sound_fx_muted(editor),
            listener_height_above_sea,
            shore_proximity,
            ocean_direction,
        )
    }
    if spray_audio_ready {
        spray_active := editor.vehicle_paint_scene && f32(canvas2d.GetTime()) < editor.vehicle_paint_sound_until
        spray_intensity := .45 + f32(editor.vehicle_paint_brush_radius) / 40 * .55
        spray_pan := f32(0)
        screen_width := canvas2d.GetScreenWidth()
        if screen_width > 0 {
            spray_pan = clamp(canvas2d.GetMousePosition().x / f32(screen_width) * 2 - 1, -1, 1)
        }
        spray_audio.update(&spray_sound_state, spray_active, spray_intensity, spray_pan, sound_fx_muted(editor))
    }
    if !pause_menu_is_open(editor) && editor.active_lab_scene != "" {
        _ = lab_scene_process_input(editor)
    } else if !pause_menu_is_open(editor) {
        if canvas2d.IsKeyPressed(.P) do editor.atmosphere.paused = !editor.atmosphere.paused
        if canvas2d.IsKeyDown(.LEFT) do atmosphere.set_world_minutes(&editor.atmosphere, editor.atmosphere.world_minutes - frame_delta * 180)
        if canvas2d.IsKeyDown(.RIGHT) do atmosphere.set_world_minutes(&editor.atmosphere, editor.atmosphere.world_minutes + frame_delta * 180)
        if !town_mouse_wheel_mounted {
            if canvas2d.IsKeyPressed(.FOUR) do atmosphere.set_weather_override(&editor.atmosphere, .Automatic)
            if canvas2d.IsKeyPressed(.ONE) do atmosphere.set_weather_override(&editor.atmosphere, .Clear)
            if canvas2d.IsKeyPressed(.TWO) do atmosphere.set_weather_override(&editor.atmosphere, .Windy)
            if canvas2d.IsKeyPressed(.THREE) do atmosphere.set_weather_override(&editor.atmosphere, .Storm)
        }
    }
    if !pause_menu_is_open(editor) && editor_debug_toggle_pressed(editor) {
        editor.tweak_panel_visible = !editor.tweak_panel_visible
    }
    if !editor.in_map && !pause_menu_is_open(editor) do editor_ui_process_input(editor, width, height)
    if !editor.in_map && !pause_menu_is_open(editor) {
        if editor.authoring_tool == .ClimbingLeaves {
            editor.plant_stamp_mode = .Climbing
            authoring_select_tool(editor, .Foliage)
        }
        if !fixture_editor_file_dialog_is_open(editor) {
            if !imgui_captures_keyboard() && canvas2d.IsKeyPressed(.ESCAPE) do editor_cancel_interaction(editor)
            if !imgui_captures_keyboard() {
                if canvas2d.IsKeyPressed(.S) && !control_key_down() do authoring_select_selection_tool(editor)
                if canvas2d.IsKeyPressed(.T) do authoring_select_tool(editor, .Paint)
                if canvas2d.IsKeyPressed(.B) do authoring_select_tool(editor, .Formations)
                if canvas2d.IsKeyPressed(.H) {
                    editor.plant_stamp_mode = .Ground
                    authoring_select_tool(editor, .Foliage)
                }
                if !control_key_down() && canvas2d.IsKeyPressed(.Z) do authoring_select_tool(editor, .Ridge)
                if !control_key_down() && canvas2d.IsKeyPressed(.C) do authoring_select_tool(editor, .Cliff)
                if !control_key_down() && canvas2d.IsKeyPressed(.N) do authoring_select_tool(editor, .Building)
                if !control_key_down() && canvas2d.IsKeyPressed(.J) do authoring_select_tool(editor, .Marina)
                if !control_key_down() && !editor.road_mode && canvas2d.IsKeyPressed(.K) {
                    authoring_select_tool(editor, .Farm)
                }
                if !control_key_down() && canvas2d.IsKeyPressed(.V) do authoring_select_tool(editor, .Wreck)
                if !control_key_down() && canvas2d.IsKeyPressed(.L) do authoring_select_tool(editor, .ClimbingLeaves)
                if canvas2d.IsKeyPressed(.M) do authoring_select_tool(editor, .Roads)
                if !control_key_down() && canvas2d.IsKeyPressed(.G) do authoring_select_tool(editor, .GreekAssets)
            }
            if !imgui_captures_keyboard() && canvas2d.IsKeyPressed(.F) do editor_focus_terrain(editor)
            if !imgui_captures_keyboard() && control_key_down() && canvas2d.IsKeyPressed(.S) {
                if editor.terrain_sculpt.session.active do terrain_sculpt_cancel(editor)
                map_editor_save(editor)
            }
            if !imgui_captures_keyboard() && control_key_down() && canvas2d.IsKeyPressed(.O) {
                if editor.terrain_sculpt.session.active do terrain_sculpt_cancel(editor)
                map_editor_load(editor)
            }
            if !imgui_captures_keyboard() &&
               editor.tool != .Structure &&
               control_key_down() &&
               canvas2d.IsKeyPressed(.Z) {
                terrain_undo(editor)
            }
            if !imgui_captures_keyboard() &&
               editor.tool != .Structure &&
               control_key_down() &&
               canvas2d.IsKeyPressed(.Y) {
                terrain_redo(editor)
            }
            if !imgui_captures_keyboard() && editor.road_mode && control_key_down() && canvas2d.IsKeyPressed(.Z) {
                road_history_undo(editor)
                editor.road_drag_node = -1
                editor.road_drag_node_previous_selection = -1
                editor.road_drag_node_moved = false
                editor.road_drag_edge = -1
                editor.road_drag_handle = -1
            }
            if !imgui_captures_keyboard() && editor.road_mode && control_key_down() && canvas2d.IsKeyPressed(.Y) {
                road_history_redo(editor)
                editor.road_drag_node = -1
                editor.road_drag_node_previous_selection = -1
                editor.road_drag_node_moved = false
                editor.road_drag_edge = -1
                editor.road_drag_handle = -1
            }
            if !imgui_captures_keyboard() &&
               (editor.marina_paint_mode || editor.farm_paint_mode || editor.wreck_paint_mode) &&
               control_key_down() &&
               canvas2d.IsKeyPressed(.Z) {
                structure_undo(editor)
            }
            if !imgui_captures_keyboard() &&
               (editor.marina_paint_mode || editor.farm_paint_mode || editor.wreck_paint_mode) &&
               control_key_down() &&
               canvas2d.IsKeyPressed(.Y) {
                structure_redo(editor)
            }
            if !imgui_captures_keyboard() &&
               editor.authoring_tool == .Formations &&
               !editor.rock_placement_mode &&
               canvas2d.IsKeyPressed(.V) {
                structure_cycle_kind(editor)
            }
            if !imgui_captures_keyboard() &&
               editor.authoring_tool == .Formations &&
               !editor.rock_placement_mode &&
               canvas2d.IsKeyPressed(.X) {
                editor.structure_auto_kind = true
            }
            if !imgui_captures_keyboard() && editor.road_mode && canvas2d.IsKeyPressed(.BACKSPACE) {
                road_delete_selected(editor)
            }
            if !imgui_captures_keyboard() && editor.road_mode && canvas2d.IsKeyPressed(.K) {
                road_cycle_pavement(editor)
            }
        }
        viewport_ui_hit := editor_ui_hit(editor, canvas2d.GetMousePosition(), width, height)
        update_editor_camera(editor, min(frame_delta, f32(.05)))
        viewport_wheel := viewport_ui_hit ? f32(0) : canvas2d.GetMouseWheelMove()
        if editor.road_mode {
            wheel := viewport_wheel
            if shift_key_down() && editor.road_selected_node >= 0 {
                node := &editor.project.road_graph.nodes[editor.road_selected_node]
                if wheel != 0 do structure_history_push_undo(editor)
                node.junction_radius = clamp(node.junction_radius + wheel, f32(1), f32(40))
                if wheel != 0 do editor.project.revision += 1
            } else if alt_key_down() {
                editor.road_width = clamp(editor.road_width + wheel, f32(2.5), f32(24))
                if wheel != 0 && editor.road_selected_node >= 0 {
                    structure_history_push_undo(editor)
                    for &edge in editor.project.road_graph.edges[:editor.project.road_graph.edge_count] {
                        if edge.from == editor.road_selected_node || edge.to == editor.road_selected_node {
                            edge.half_width = editor.road_width * .5
                        }
                    }
                    editor.project.revision += 1
                }
            }
        } else if editor.tool == .Structure && editor.curve_drawing {
            cell := editor.project.levels[0].cell_size
            wheel := viewport_wheel
            if shift_key_down() {
                editor.curve_width = max(cell, editor.curve_width + wheel * cell)
                editor.curve_height = max(cell, editor.curve_height + wheel * cell)
            }
        } else if editor.tool == .Structure && editor.architecture_paint_mode {
            wheel := viewport_wheel
            if shift_key_down() {
                editor.architecture_brush_strength = clamp(editor.architecture_brush_strength + wheel * .04, .02, 1)
            } else if alt_key_down() {
                editor.architecture_brush_hardness = clamp(editor.architecture_brush_hardness + wheel * .04, 0, 1)
            }
        } else if editor.tool == .Structure && editor.climbing_leaf_paint_mode {
            wheel := viewport_wheel
            if shift_key_down() {
                editor.climbing_leaf_brush_strength = clamp(editor.climbing_leaf_brush_strength + wheel * .04, .02, 1)
            } else if alt_key_down() {
                editor.climbing_leaf_brush_hardness = clamp(editor.climbing_leaf_brush_hardness + wheel * .04, 0, 1)
            }
        } else if editor.tool == .Structure &&
           !editor.selection_tool_active &&
           (editor.authoring_tool == .Formations || editor.authoring_tool == .Foliage) {
            wheel := viewport_wheel
            if shift_key_down() {
                editor.formation_brush_strength = clamp(editor.formation_brush_strength + wheel * .04, .02, 1)
            } else if alt_key_down() {
                editor.formation_brush_hardness = clamp(editor.formation_brush_hardness + wheel * .04, 0, 1)
            }
        } else if editor.tool == .Structure && (shift_key_down() || alt_key_down()) {
            structure_adjust_with_wheel(editor, viewport_wheel)
        } else if alt_key_down() && (editor.tool == .Raise || editor.tool == .Smooth || editor.tool == .Paint) {
            editor.hardness = clamp(editor.hardness + viewport_wheel * .02, 0, 1)
        } else if shift_key_down() && (editor.tool == .Raise || editor.tool == .Smooth || editor.tool == .Paint) {
            editor.strength = clamp(editor.strength + viewport_wheel * .02, 0, 1)
        }
    }
    // Cursor picking and rendering must use the same editor camera pose.
    // At close zooms the orbit camera can dip below uneven terrain; if we
    // correct it only later in the frame, the brush is applied at the ray
    // from the old pose but drawn at the ray from the corrected pose.
    if !editor.in_map {
        camera_ground := terrain.sample_surface_height(
            &editor.project,
            0,
            editor.camera_pose.position.x,
            editor.camera_pose.position.z,
        )
        editor.camera_pose = third_person.camera_above_height(editor.camera_pose, camera_ground, .35)
    }
    focal_length := editor.vehicle_showcase_scene ? VEHICLE_SHOWCASE_FOCAL_LENGTH : f32(1.35)
    if !editor.vehicle_showcase_scene && editor.in_map && driving_aircraft(editor) {
        focal_length = editor.flight_camera.focal_length
    }
    editor_view_camera := perspective_camera(editor.camera_pose, focal_length)
    world_mouse, world_mouse_inside := canvas2d.GetWorldMousePosition()
    world_render_width, world_render_height := canvas2d.GetWorldRenderSize()
    world_x, world_z, cursor_hit = terrain_under_cursor_3d(
        editor,
        editor_view_camera,
        world_mouse,
        world_render_width,
        world_render_height,
    )
    cursor_hit = cursor_hit && world_mouse_inside
    ui_hit = editor_ui_hit(editor, canvas2d.GetMousePosition(), width, height)
    editor.cursor_world_x = world_x
    editor.cursor_world_z = world_z
    editor.cursor_hit = cursor_hit && !ui_hit && !editor.in_map
    if editor.cursor_hit {
        cursor_height, cursor_material, land_found := terrain.sample_land(&editor.project, 0, world_x, world_z)
        if !land_found {
            editor.cursor_hit = false
        } else {
            editor.cursor_height = cursor_height
            editor.cursor_material = cursor_material
        }
    }
    teleport_consumes_input := false
    if editor.tweak_teleport_on_click {
        // While armed, this one-shot tool owns world clicks so an authoring
        // brush cannot also modify the destination terrain.
        teleport_consumes_input = true
        if canvas2d.IsKeyPressed(.ESCAPE) || canvas2d.IsMouseButtonPressed(.RIGHT) {
            editor.tweak_teleport_on_click = false
        } else if cursor_hit && !ui_hit && !imgui_captures_mouse() && canvas2d.IsMouseButtonPressed(.LEFT) {
            ground_y := terrain.sample_surface_height(&editor.project, 0, world_x, world_z)
            player_place(editor, {world_x, ground_y, world_z}, .Teleport, editor.player.facing_yaw_radians)
            editor.tweak_teleport_on_click = false
        }
    }
    note_placement_consumes_input :=
        teleport_consumes_input || fixture_note_placement_process_input(editor, cursor_hit && !ui_hit)
    terrain_sculpt_consumes_input :=
        teleport_consumes_input || terrain_sculpt_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
    if !teleport_consumes_input && !note_placement_consumes_input && !terrain_sculpt_consumes_input {
        architecture_paint_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        airport_stamp_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        marina_brush_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        farm_stamp_update_preview(editor, world_x, world_z, cursor_hit && !ui_hit)
        farm_brush_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        wreck_stamp_update_preview(editor, world_x, world_z, cursor_hit && !ui_hit)
        wreck_brush_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        plant_stamp_update_target(
            editor,
            editor_view_camera,
            world_mouse,
            world_render_width,
            world_render_height,
            world_mouse_inside && !ui_hit,
        )
        climbing_leaf_paint_process_input(editor, world_x, world_z, editor.plant_stamp_target_valid && !ui_hit)
        formation_brush_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        ruin_stamp_update_preview(editor, world_x, world_z, cursor_hit && !ui_hit)
        ruin_stamp_process_input(editor, cursor_hit && !ui_hit)
        curve_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        road_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
    }
    if !note_placement_consumes_input &&
       !editor.architecture_paint_mode &&
       !editor.marina_paint_mode &&
       !editor.farm_paint_mode &&
       !editor.wreck_paint_mode &&
       !editor.climbing_leaf_paint_mode &&
       !editor.selection_tool_active &&
       editor.authoring_tool != .Formations &&
       (editor.authoring_tool != .Foliage || editor.foliage_hedgerow_mode) &&
       !editor.road_mode &&
       !editor.curve_mode &&
       !editor.curve_drawing &&
       editor.curve_point_count == 0 {
        structure_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
    }
    if !note_placement_consumes_input && editor.selection_tool_active {
        structure_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
    }
}
