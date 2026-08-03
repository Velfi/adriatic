package main

import architecture "../packages/architecture"
import atmosphere "../packages/atmosphere"
import boats "../packages/boats"
import circulation "../packages/circulation"
import dialogue_session "../packages/dialogue_session"
import dio "../packages/dio"
import engine_sound "../packages/engine_sound"
import flight "../packages/flight"
import game_input "../packages/game_input"
import libellula_game "../packages/libellula"
import ocean_audio "../packages/ocean_audio"
import particle_systems "../packages/particles"
import postale_game "../packages/postale"
import quest "../packages/quest"
import road_designer "../packages/road_designer"
import roads "../packages/roads"
import rondine_game "../packages/rondine"
import scene_stack "../packages/scene_stack"
import spray_audio "../packages/spray_audio"
import story "../packages/story"
import surface_weather "../packages/surface_weather"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import wind_audio "../packages/wind_audio"
import "core:math"
import sdl "vendor:sdl3"
import canvas2d "zelda_engine:canvas2d"
import physics "zelda_engine:physics"

Editor :: struct {
    using fixture:                      Fixture,
    menu_scene_stack:                   scene_stack.Stack `fixture:"-"`,
    road_construction_mode:             Road_Construction_Mode,
    road_construction_phase:            Road_Construction_Phase,
    road_preview_graph:                 roads.Graph,
    road_design_base_graph:             roads.Graph,
    road_preview_first_edge:            int,
    road_preview_target_node:           int,
    road_preview_status:                Road_Preview_Status,
    road_preview_snap:                  Road_Snap,
    road_preview_pending_snap:          Road_Snap,
    road_preview_pending_since:         f64,
    road_preview_start:                 roads.Vec3,
    road_preview_control_from:          roads.Vec3,
    road_preview_control_to:            roads.Vec3,
    road_preview_endpoint:              roads.Vec3,
    road_preview_distance:              f32,
    road_preview_angle:                 f32,
    road_preview_rise:                  f32,
    road_preview_maximum_grade:         f32,
    road_preview_cell_x:                int,
    road_preview_cell_z:                int,
    road_preview_cell_valid:            bool,
    road_design_optimizer:              ^road_designer.Optimizer,
    road_design_workspace:              ^road_designer.Workspace,
    road_design_heights:                [dynamic]f32,
    road_design_alternative:            road_designer.Named_Alternative,
    road_design_paused:                 bool,
    road_design_source_revision:        u64,
    road_design_terrain_revision:       u64,
    road_design_request_key:            u64,
    road_design_frame_budget:           int,
    road_design_preview_id:             u32,
    road_design_start_node:             int,
    road_design_target_node:            int,
    road_design_redesign_active:        bool,
    road_design_undo:                   [ROAD_EDIT_HISTORY_CAPACITY]Road_Edit_Transaction,
    road_design_redo:                   [ROAD_EDIT_HISTORY_CAPACITY]Road_Edit_Transaction,
    road_design_undo_count:             int,
    road_design_redo_count:             int,
    road_edit_sequence:                 u64,
    road_snap_nodes:                    bool,
    road_snap_edges:                    bool,
    road_snap_grid:                     bool,
    road_snap_angles:                   bool,
    road_snap_tangents:                 bool,
    road_snap_perpendiculars:           bool,
    vehicle_paint_layers:               [VEHICLE_PAINT_AIRCRAFT_COUNT][VEHICLE_PAINT_TEXTURE_BYTE_COUNT]u8,
    surface_weather:                    surface_weather.Field,
    fixture_owner:                      Fixture_Migration_Result `hs:"-"`,
    mouse_emote:                        Mouse_Emote_State,
    ruin_stamp_preview:                 terrain.Structure,
    ruin_stamp_preview_valid:           bool,
    ruin_stamp_seed_offset:             u32,
    ruin_stamp_aegean:                  bool,
    ruin_stamp_complex:                 bool,
    active_lab_scene:                   string `fixture:"-"`,
    dunes_lab_runtime:                  Dunes_Lab_Runtime `hs:"-" fixture:"-"`,
    ocean_traffic:                      boats.Ocean_Traffic,
    fixture_path:                       [FIXTURE_FILE_PATH_CAPACITY]u8 `fixture:"-"`,
    fixture_path_length:                int `fixture:"-"`,
    fixture_file_dialog:                Fixture_File_Dialog_State `fixture:"-"`,
    main_menu_active:                   bool,
    main_menu_focus:                    int,
    world_select_focus:                 int,
    world_select_weather:               bool,
    console:                            Game_Console,
    flame_graph:                        dio.Flame_Graph,
    capture_world_only:                 bool,
    capture_postale_bank_grid:          bool `fixture:"-"`,
    capture_postale_transform_parity:   bool `fixture:"-"`,
    capture_player_walk_pose:           bool,
    capture_player_run_compress_pose:   bool,
    capture_player_turn_left_pose:      bool,
    capture_player_turn_right_pose:     bool,
    capture_player_brake_pose:          bool,
    capture_player_jump_pose:           bool,
    capture_player_fall_pose:           bool,
    capture_player_blink_pose:          bool,
    capture_player_posted_pose:         bool,
    capture_player_mailbag_hidden:      bool,
    capture_bougainvillea_seed_enabled: bool,
    capture_bougainvillea_structure_id: u64,
    capture_bougainvillea_seed:         u32,
    plant_stamp_mode:                   Plant_Stamp_Mode,
    plant_stamp_target_index:           int,
    plant_stamp_target_valid:           bool,
    plant_stamp_target_locked:          bool,
    plant_stamp_last_stamped_id:        u64,
    benchmark_ground_grass_disabled:    bool,
    structure_undo:                     [STRUCTURE_HISTORY_CAPACITY]Structure_History_State,
    structure_redo:                     [STRUCTURE_HISTORY_CAPACITY]Structure_History_State,
    structure_undo_count:               int,
    structure_redo_count:               int,
    terrain_undo:                       [TERRAIN_HISTORY_CAPACITY]Terrain_History_State,
    terrain_redo:                       [TERRAIN_HISTORY_CAPACITY]Terrain_History_State,
    terrain_undo_count:                 int,
    terrain_redo_count:                 int,
    terrain_file_status:                cstring,
    terrain_file_status_until:          f32,
    terrain_saved_revision:             u64,
    last_frame_time:                    f64,
    aircraft_fixed_accumulator:         f64,
    aircraft_previous_body:             flight.Body_State,
    aircraft_previous_body_valid:       bool,
    bomber_mode:                        bool,
    bomber_payload_kind:                Bomber_Payload_Kind,
    bomber_drops:                       [BOMBER_DROP_CAPACITY]Bomber_Drop,
    bomber_drop_count:                  int,
    bomber_drop_serial:                 u32,
    bomber_drop_cooldown:               f32,
    bomber_release_flash:               f32,
    bomber_touchdown_flash:             f32,
    bomber_touchdown_kind:              Bomber_Payload_Kind,
    bomber_pip_pose:                    third_person.Camera_Pose,
    bomber_pip_seed:                    u32,
    bomber_pip_valid:                   bool,
    bomber_pip_handoff_seconds:         f32,
    gameplay_physics:                   Gameplay_Physics,
    player_placement_reason:            Player_Placement_Reason,
    player_placement_revision:          u64,
    mailbag_pouch_asset:                Mailbag_Pouch_Asset,
    car_physics_world:                  physics.World,
    car_physics_vehicle:                physics.Vehicle,
    car_physics_terrain:                [terrain.CLIPMAP_LEVELS]physics.Body_ID,
    car_physics_terrain_revision:       u64,
    car_physics_accumulator:            f64,
    car_physics_body_rotation:          physics.Quat `fixture:"-"`,
    car_physics_body_rotation_valid:    bool `fixture:"-"`,
    car_wheels:                         [4]physics.Wheel_State,
    car_impact_detector:                engine_sound.Vehicle_Impact_Detector,
    car_audio_damage:                   f32,
    engine_audio:                       engine_sound.Device,
    car_audio_gearbox:                  engine_sound.Car_Gearbox,
    landing_wheel_squeal:               f32,
    landing_wheel_speed:                f32,
    libellula_visual_mesh:              vehicles.Libellula_Mesh,
    libellula_mk2_visual_mesh:          vehicles.Libellula_Mesh,
    libellula_base_mesh:                vehicles.Libellula_Mesh,
    libellula_mk2_base_mesh:            vehicles.Libellula_Mesh,
    postale_base_mesh:                  ^vehicles.Aircraft_Mesh `hs:"-"`,
    car_base_mesh:                      ^vehicles.Aircraft_Mesh `hs:"-"`,
    libellula_projected_faces:          [dynamic]Projected_Aircraft_Face,
    gameplay_options:                   Gameplay_Options,
    runtime_input:                      game_input.State,
    control_hint_atlases:               Control_Hint_Atlases,
    vehicle_paint_tool_icons:           canvas2d.Texture,
    authoring_tool_atlas:               canvas2d.Texture,
    tarot_atlas:                        canvas2d.Texture,
    photo_filter_media_atlas:           canvas2d.Texture,
    photo_filter_lut_atlas:             canvas2d.Texture,
    controller_disconnect_notice:       bool,
    friendship_notice_initialized:      bool,
    friendship_notice_total:            int,
    friendship_notice_delta:            int,
    friendship_notice_age:              f32,
    pause_focus:                        int,
    photo_restore_pose:                 third_person.Camera_Pose,
    photo_restore_inspection:           third_person.Camera_Pose,
    photo_restore_slot:                 third_person.Camera_Slot,
    photo_yaw:                          f32,
    photo_pitch:                        f32,
    photo_capture_pending:              bool,
    photo_capture_notice_until:         f64,
    photo_filter:                       Photo_Filter_Settings,
    options_focus:                      int,
    options_scroll_y:                   f32,
    options_scroll_dragging:            bool,
    options_scroll_drag_offset:         f32,
    quit_requested:                     bool,
}

@(no_instrumentation)
editor_circulation_plan :: #force_inline proc(editor: ^Editor) -> ^circulation.Plan {
    if editor == nil do return nil
    if !editor.circulation_plan_valid || editor.circulation_revision != editor.project.revision {
        changed := !editor.circulation_plan_valid
        count := 0
        for structure in editor.project.structures[:editor.project.structure_count] {
            if structure.kind != .Architecture || structure.height > 60 do continue
            if count >= editor.circulation_structure_count || editor.circulation_structures[count] != structure {
                changed = true
            }
            if count < len(editor.circulation_structures) {
                editor.circulation_structures[count] = structure
            } else {
                append(&editor.circulation_structures, structure)
            }
            count += 1
        }
        resize(&editor.circulation_structures, count)
        if count != editor.circulation_structure_count do changed = true
        editor.circulation_structure_count = count
        if changed {
            editor.circulation_plan = architecture.circulation_plan(&editor.project)
            if editor.settlement_plan.valid {
                for edit in editor.settlement_plan.terrain_edits[:editor.settlement_plan.terrain_edit_count] {
                    if edit.kind != .Plaza do continue
                    _ = circulation.plan_add(
                        &editor.circulation_plan,
                        {
                            center_x = edit.center[0],
                            center_z = edit.center[1],
                            width = edit.half_extent[0] * 2,
                            length = edit.half_extent[1] * 2,
                            kind = .Plaza,
                            source = .Generated,
                            pavement = .Cobblestone,
                            walkable = true,
                        },
                    )
                }
            }
        }
        editor.circulation_revision = editor.project.revision
        editor.circulation_plan_valid = true
    }
    return &editor.circulation_plan
}

editor_spawn_into_world :: proc(editor: ^Editor) {
    if editor == nil || editor.in_map do return
    if editor.pilot.mode == .On_Foot {
        editor.player = {
            position = editor.pilot.position,
            grounded = true,
        }
    }
    editor.camera = third_person.default_camera()
    camera_target := editor.player.position
    if editor.pilot.mode == .Driving do camera_target = editor.pilot.vehicle.position
    editor.camera_pose = third_person.camera_pose(camera_target, editor.camera)
    editor.in_map = true
    editor.map_time = f32(canvas2d.GetTime())
    set_pointer_locked(true)
}

boat_spawn_is_water :: proc(project: ^terrain.Project, agent: ^boats.Agent, position: boats.Vec2) -> bool {
    if project == nil || agent == nil do return false
    spec := boats.specifications(agent.class)
    // Check the whole hull rather than only its origin. A center point just
    // offshore can still leave the bow or stern resting on the beach.
    forward := boats.Vec2{math.sin(agent.yaw), -math.cos(agent.yaw)}
    right := boats.Vec2{-forward.y, forward.x}
    half_length := spec.length * .5
    half_beam := spec.beam * .5
    samples := [9]boats.Vec2 {
        position,
        position + forward * half_length,
        position - forward * half_length,
        position + right * half_beam,
        position - right * half_beam,
        position + forward * half_length + right * half_beam,
        position + forward * half_length - right * half_beam,
        position - forward * half_length + right * half_beam,
        position - forward * half_length - right * half_beam,
    }
    for sample in samples {
        if terrain.sample_surface(project, 0, sample.x, sample.y) == .Land do return false
    }
    return true
}

new_world_boat_traffic :: proc(project: ^terrain.Project) -> boats.Traffic {
    traffic := boats.new_traffic()
    if project == nil do return traffic
    for &agent in traffic.agents[:traffic.count] {
        original := agent.position
        if boat_spawn_is_water(project, &agent, original) do continue

        found := false
        search_step := max(boats.specifications(agent.class).length, f32(12))
        for ring in 1 ..= 128 {
            radius := f32(ring) * search_step
            for spoke in 0 ..< 24 {
                angle := f32(spoke) * math.PI * 2 / 24
                candidate := original + boats.Vec2{math.cos(angle), math.sin(angle)} * radius
                if !boat_spawn_is_water(project, &agent, candidate) do continue
                offset := candidate - original
                agent.position = candidate
                agent.loiter_center += offset
                for route_index in 0 ..< agent.route_count do agent.route[route_index] += offset
                found = true
                break
            }
            if found do break
        }
        if !found {
            // No safe water exists in the bounded search area, so omit the
            // agent instead of visibly placing a boat on land.
            agent.position = original
        }
    }
    write := 0
    for &agent in traffic.agents[:traffic.count] {
        if boat_spawn_is_water(project, &agent, agent.position) {
            traffic.agents[write] = agent
            write += 1
        }
    }
    traffic.count = write
    return traffic
}

game_state_reset :: proc(editor: ^Editor) {
    if editor == nil do return

    spawn := runway_spawn_position(editor)
    player_place(editor, spawn, .Reset)
    editor.player_stride_phase = 0
    editor.player_gait_weight = 0
    editor.player_airborne_weight = 0
    editor.player_vertical_pose = 0
    editor.player_turn_pose = 0
    editor.player_brake_pose = 0
    editor.player_posted_idle_seconds = 0
    editor.player_posted_weight = 0
    editor.player_scurry_weight = 0
    editor.player_scurry_lean = 0
    editor.player_scurry_lean_velocity = 0
    editor.player_scurry_compression = 0
    editor.player_scurry_compression_velocity = 0
    editor.player_animation_previous_speed = 0
    editor.player_body_softness = {}
    editor.player_stop_spray_cooldown = 0
    editor.player_stop_spray_speed = 0
    editor.mouse_mailbag_yaw_lag = 0
    editor.mouse_mailbag_yaw_velocity = 0
    editor.mouse_mailbag_roll_lag = 0
    editor.mouse_mailbag_roll_velocity = 0
    editor.mouse_mailbag_vertical_lag = 0
    editor.mouse_mailbag_vertical_velocity = 0
    editor.player_paws = {}
    mouse_emote_reset(&editor.mouse_emote)

    editor.camera = third_person.default_camera()
    editor.cameras = {}
    editor.flight_camera = {}
    editor.flight_control = {}
    editor.camera_target_lock = false
    editor.aircraft_fixed_accumulator = 0
    editor.aircraft_previous_body = {}
    editor.aircraft_previous_body_valid = false
    editor.flight_throttle_overlay_value = 0
    editor.flight_throttle_overlay_changed_at = 0
    editor.flight_throttle_overlay_fade_started_at = 0
    editor.flight_throttle_overlay_initialized = false

    editor.postale = postale_game.new_runtime(postale_spawn_position(editor))
    libellula_spawn := libellula_spawn_position(editor)
    editor.libellula = libellula_game.new_runtime({libellula_spawn.x, libellula_spawn.y, libellula_spawn.z})
    editor.rondine = rondine_game.new_runtime(rondine_spawn_position(editor))
    editor.aircraft = {}
    vehicles.aircraft_fleet_add(&editor.aircraft, .Postale, "Postale", &editor.postale.vehicle, true)
    when LIBELLULA_MK1_ENABLED {
        vehicles.aircraft_fleet_add(&editor.aircraft, .Libellula, "Libellula", &editor.libellula.vehicle, false)
    }
    vehicles.aircraft_fleet_add(&editor.aircraft, .Libellula_Mk2, "Libellula Mk2", &editor.libellula.vehicle, false)
    vehicles.aircraft_fleet_add(&editor.aircraft, .Rondine, "Rondine", &editor.rondine.vehicle, false)
    editor.postale_visible = true
    editor.libellula_visible = true
    editor.rondine_visible = false
    editor.libellula.vehicle.locked = true

    editor.car = vehicles.default_vehicle(car_spawn_position(editor))
    editor.car.interaction_radius = 2.2
    editor.car.exit_distance = 1.1
    editor.car.yaw_radians = -math.PI * .5
    editor.car_drive = {}
    editor.car_wheels = {}
    editor.car_impact_detector = {}
    editor.car_audio_damage = 0
    editor.car_audio_gearbox = {}
    editor.car_physics_accumulator = 0
    car_physics_teleport(editor)
    editor.car_trailer = {}
    editor.car_trailer_attached = true
    editor.car_trailer_position = editor.car.position
    editor.car_trailer_yaw = editor.car.yaw_radians

    editor.story_state = {}
    editor.player_mail = {}
    story.init_quest_catalog(&editor.story_quest_catalog)
    _ = story.ensure_quest_progress(&editor.story_state)
    editor.tracked_quest_node = quest.no_node
    editor.quest_tracking_suppressed = false
    editor.quest_tracking_revision = editor.story_state.quest.revision
    editor.quest_log_tab = .Active
    editor.quest_log_focus = 0
    editor.quest_log_scroll = 0
    editor.player_mail_focus = 0
    editor.player_mail_last_collected = 0
    editor.player_mail_notice_until = 0
    editor.friendship_notice_initialized = true
    editor.friendship_notice_total = editor.story_state.friendship_points
    editor.friendship_notice_delta = 0
    editor.friendship_notice_age = FRIENDSHIP_NOTICE_DURATION
    editor.dialogue_resident = {}
    editor.attendant_position = attendant_spawn_position(editor, editor.libellula.vehicle.position)
    editor.gerta_position = gerta_spawn_position(editor)
    editor.attendant_dialogue = {}
    editor.attendant_dialogue_open = false
    editor.attendant_dialogue_focus = 0
    dialogue_session.clear(&editor.dialogue_session)
    editor.attendant_dialogue_vehicle_target = {}
    editor.attendant_dialogue_vehicle_choices = {}
    editor.attendant_dialogue_vehicle_choice_count = 0
    editor.marina_dinghy_borrowed = false
    editor.cinematic_playback = {}
    editor.story_cinematic_restore_pose = {}
    editor.story_meeting_cinematic_pending = false
    editor.story_cinematic_active = false

    markov_marina_buoy_physics_destroy(editor)
    editor.boat_traffic = new_world_boat_traffic(&editor.project)
    editor.ocean_traffic = boats.new_ocean_traffic()
    editor.atmosphere = atmosphere.new(0x41c10)
    surface_weather.initialize(&editor.surface_weather, terrain.WORLD_SIZE_METERS * .5)
    editor.vehicle_effects = particle_systems.new_vehicle_effects(0x72b7e4a1)
    editor.player_terrain_effects = particle_systems.new_vehicle_effects(0xa21c94d7)
    editor.wing_trails = particle_systems.new_wing_trails(0x1f123bb5)
    editor.petal_effects = particle_systems.new_petal_effects(0x6a09e667)
    editor.landing_wheel_squeal = 0
    editor.landing_wheel_speed = 0
}

hot_state_rebind_engine_audio :: proc(
    editor: ^Editor,
    stream: ^sdl.AudioStream,
    aux_mix: engine_sound.Aux_Mix_Callback = nil,
    aux_userdata: rawptr = nil,
) {
    if editor == nil do return
    editor.engine_audio.stream = stream
    editor.engine_audio.aux_mix = aux_mix
    editor.engine_audio.aux_userdata = aux_userdata
}

Ambient_Audio_Mix :: struct {
    wind:  ^wind_audio.Runtime,
    ocean: ^ocean_audio.Runtime,
    spray: ^spray_audio.Runtime,
}

ambient_audio_mix :: proc(userdata: rawptr, output: []f32) {
    mix := cast(^Ambient_Audio_Mix)userdata
    if mix == nil do return
    stereo: [engine_sound.BUFFER_SAMPLES * engine_sound.AUDIO_CHANNELS]f32
    stereo_samples := stereo[:len(output)]
    if mix.wind != nil {
        wind_audio.render(&mix.wind.synth, stereo_samples)
        for &sample, index in output do sample += stereo[index]
    }
    if mix.ocean != nil {
        ocean_audio.render(&mix.ocean.synth, stereo_samples)
        for &sample, index in output do sample += stereo[index]
    }
    if mix.spray != nil {
        spray_audio.render(&mix.spray.synth, stereo_samples)
        for &sample, index in output do sample += stereo[index]
    }
}

structure_history_capture :: proc(editor: ^Editor, state: ^Structure_History_State) {
    if editor == nil || state == nil do return
    state.count = editor.project.structure_count
    state.next_id = editor.project.next_structure_id
    state.road_graph = editor.project.road_graph
    state.city_density = editor.project.city_density
    state.climbing_leaf_density = editor.project.climbing_leaf_density
    state.marina_plan = editor.marina_authored_plan
    state.harbor_plan = editor.harbor_authored_plan
    state.harbor_intervention = editor.harbor_authored_intervention
    state.marina_authored = editor.marina_authored
    state.farms = editor.farms
    state.farm_count = editor.farm_count
    state.wrecks = editor.wrecks
    state.wreck_count = editor.wreck_count
    state.settlement_brush_pieces = editor.settlement_plan.brush_pieces
    state.settlement_brush_piece_count = editor.settlement_plan.brush_piece_count
    state.settlement_next_component_id = editor.settlement_plan.next_brush_component_id
    state.island_transforms = editor.project.island_transforms
    state.settlement_plan = editor.settlement_plan
    state.greek_placements = editor.greek_placements
    state.greek_placement_count = editor.greek_placement_count
    state.default_marinas = editor.default_marinas
    state.default_harbors = editor.default_harbors
    state.default_harbor_interventions = editor.default_harbor_interventions
    resize(&state.structures, state.count)
    copy(state.structures[:], editor.project.structures[:state.count])
}

structure_history_restore :: proc(editor: ^Editor, state: ^Structure_History_State) {
    if editor == nil || state == nil do return
    island_transform_changed := editor.project.island_transforms != state.island_transforms
    if island_transform_changed {
        for current, index in editor.project.island_transforms {
            target := state.island_transforms[index]
            dx, dz := target.current_x - current.current_x, target.current_z - current.current_z
            if math.abs(dx) <= .0001 && math.abs(dz) <= .0001 do continue
            editor_island_translate_dependent_state(editor, terrain.island_id_from_index(index), dx, dz)
        }
    }
    resize(&editor.project.structures, state.count)
    copy(editor.project.structures[:], state.structures[:state.count])
    editor.project.structure_count = state.count
    editor.project.next_structure_id = state.next_id
    editor.project.road_graph = state.road_graph
    editor.project.city_density = state.city_density
    editor.project.climbing_leaf_density = state.climbing_leaf_density
    editor.marina_authored_plan = state.marina_plan
    editor.harbor_authored_plan = state.harbor_plan
    editor.harbor_authored_intervention = state.harbor_intervention
    editor.marina_authored = state.marina_authored
    editor.farms = state.farms
    editor.farm_count = state.farm_count
    editor.wrecks = state.wrecks
    editor.wreck_count = state.wreck_count
    editor.settlement_plan.brush_pieces = state.settlement_brush_pieces
    editor.settlement_plan.brush_piece_count = state.settlement_brush_piece_count
    editor.settlement_plan.next_brush_component_id = state.settlement_next_component_id
    editor.project.island_transforms = state.island_transforms
    editor.settlement_plan = state.settlement_plan
    editor.greek_placements = state.greek_placements
    editor.greek_placement_count = state.greek_placement_count
    editor.default_marinas = state.default_marinas
    editor.default_harbors = state.default_harbors
    editor.default_harbor_interventions = state.default_harbor_interventions
    editor.project.revision += 1
    if editor.structure_selected >= editor.project.structure_count do editor.structure_selected = -1
    if editor.road_selected_node >= editor.project.road_graph.node_count do editor.road_selected_node = -1
    if island_transform_changed {
        editor.terrain_revision += 1
        world_renderer_fixture_invalidate(editor)
        gameplay_physics_rebuild_structures(editor)
        gameplay_physics_sync_revisions(editor)
    }
}

structure_history_push :: proc(
    history: ^[STRUCTURE_HISTORY_CAPACITY]Structure_History_State,
    count: ^int,
    editor: ^Editor,
) {
    if history == nil || count == nil || editor == nil do return
    if count^ < STRUCTURE_HISTORY_CAPACITY {
        structure_history_capture(editor, &history[count^])
        count^ += 1
        return
    }
    oldest := new(Structure_History_State)
    defer free(oldest)
    oldest^ = history[0]
    for index in 1 ..< STRUCTURE_HISTORY_CAPACITY {
        history[index - 1] = history[index]
    }
    history[STRUCTURE_HISTORY_CAPACITY - 1] = oldest^
    structure_history_capture(editor, &history[STRUCTURE_HISTORY_CAPACITY - 1])
}

structure_history_push_undo :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.road_edit_sequence += 1
    structure_history_push(&editor.structure_undo, &editor.structure_undo_count, editor)
    editor.structure_undo[editor.structure_undo_count - 1].sequence = editor.road_edit_sequence
    editor.structure_redo_count = 0
    road_design_history_clear(&editor.road_design_redo, &editor.road_design_redo_count)
}

structure_history_push_redo :: proc(editor: ^Editor) {
    if editor == nil do return
    structure_history_push(&editor.structure_redo, &editor.structure_redo_count, editor)
}

structure_undo :: proc(editor: ^Editor) {
    if editor == nil || editor.structure_undo_count <= 0 do return
    sequence := editor.structure_undo[editor.structure_undo_count - 1].sequence
    structure_history_push_redo(editor)
    editor.structure_redo[editor.structure_redo_count - 1].sequence = sequence
    editor.structure_undo_count -= 1
    structure_history_restore(editor, &editor.structure_undo[editor.structure_undo_count])
    if editor.structure_selected >= 0 && editor.structure_selected >= editor.project.structure_count {
        editor.structure_selected = -1
    }
}

structure_redo :: proc(editor: ^Editor) {
    if editor == nil || editor.structure_redo_count <= 0 do return
    sequence := editor.structure_redo[editor.structure_redo_count - 1].sequence
    structure_history_push(&editor.structure_undo, &editor.structure_undo_count, editor)
    editor.structure_undo[editor.structure_undo_count - 1].sequence = sequence
    editor.structure_redo_count -= 1
    structure_history_restore(editor, &editor.structure_redo[editor.structure_redo_count])
}

fixture_storage_destroy :: proc(fixture: ^Fixture) {
    if fixture == nil do return
    terrain.destroy_project(&fixture.project)
    architecture.city_plan_destroy(&fixture.architecture_preview_plan)
    architecture.city_plan_destroy(&fixture.architecture_city_plan)
    delete(fixture.circulation_structures)
    fixture.circulation_structures = nil
}

structure_history_storage_destroy :: proc(editor: ^Editor) {
    if editor == nil do return
    for &state in editor.structure_undo {
        delete(state.structures)
        state = {}
    }
    for &state in editor.structure_redo {
        delete(state.structures)
        state = {}
    }
    editor.structure_undo_count = 0
    editor.structure_redo_count = 0
    editor.terrain_undo_count = 0
    editor.terrain_redo_count = 0
}

structure_storage_destroy :: proc(editor: ^Editor) {
    if editor == nil do return
    road_design_runtime_destroy(editor)
    fixture_storage_destroy(&editor.fixture)
    structure_history_storage_destroy(editor)
}

terrain_history_capture :: proc(editor: ^Editor, state: ^Terrain_History_State) {
    if editor == nil || state == nil do return
    for level in 0 ..< terrain.CLIPMAP_LEVELS {
        state.levels[level] = editor.project.levels[level]
    }
    state.sea_level = editor.project.sea_level
    state.revision = editor.project.revision
}

terrain_history_restore :: proc(editor: ^Editor, state: ^Terrain_History_State) {
    if editor == nil || state == nil do return
    for level in 0 ..< terrain.CLIPMAP_LEVELS {
        editor.project.levels[level] = state.levels[level]
    }
    editor.project.sea_level = state.sea_level
    editor.project.revision = max(editor.project.revision, state.revision) + 1
    world_terrain_invalidate_all(editor)
}
