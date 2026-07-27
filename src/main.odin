package main

import architecture "../packages/architecture"
import atmosphere "../packages/atmosphere"
import back "../packages/back"
import boats "../packages/boats"
import chase_camera "../packages/chase_camera"
import cinematic "../packages/cinematic"
import circulation "../packages/circulation"
import dialogue "../packages/dialogue"
import dio "../packages/dio"
import engine_sound "../packages/engine_sound"
import farmland "../packages/farmland"
import flight "../packages/flight"
import game_input "../packages/game_input"
import hot_abi "../packages/hot_abi"
import hs "../packages/hs"
import libellula_game "../packages/libellula"
import marina "../packages/marina"
import mouse_tail "../packages/mouse_tail"
import ocean_audio "../packages/ocean_audio"
import particle_systems "../packages/particles"
import postale_game "../packages/postale"
import roads "../packages/roads"
import spray_audio "../packages/spray_audio"
import story "../packages/story"
import tarot "../packages/tarot"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import wind_audio "../packages/wind_audio"
import "core:c"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"
import timezone "core:time/timezone"
import sdl "vendor:sdl3"
import rl "zelda_engine:canvas2d"
import physics "zelda_engine:physics"

HOT_RELOAD :: #config(HOT_RELOAD, false)
SHOW_STARTUP_MENU :: #config(SHOW_STARTUP_MENU, false)
HOT_LIBRARY_ENV :: "ADRIATIC_HOT_LIBRARY"

ADRIATIC_WORLD_WIDTH :: 854
ADRIATIC_WORLD_HEIGHT :: 480
STRUCTURE_HISTORY_CAPACITY :: 24
TERRAIN_HISTORY_CAPACITY :: 12
TERRAIN_PROJECT_PATH :: "adriatic.terrain"
MARINA_BRUSH_MINIMUM_SUITABILITY :: f32(.70)
VEHICLE_SHOWCASE_FOCAL_LENGTH :: f32(2.0)
AIRCRAFT_FIXED_STEP :: f64(1.0 / 120.0)
AIRCRAFT_MAX_CATCH_UP :: f64(.1)

Structure_History_State :: struct {
    structures:            [terrain.STRUCTURE_CAPACITY]terrain.Structure,
    count:                 int,
    next_id:               u64,
    road_graph:            roads.Graph,
    city_density:          [terrain.CITY_DENSITY_SAMPLES]u8,
    climbing_leaf_density: [terrain.CITY_DENSITY_SAMPLES]u8,
    marina_plan:           marina.Plan,
    marina_authored:       bool,
    farms:                 [FARM_INSTANCE_CAPACITY]Farm_Instance,
    farm_count:            int,
}

Terrain_History_State :: struct {
    levels:    [terrain.CLIPMAP_LEVELS]terrain.Clipmap_Level,
    sea_level: f32,
    revision:  u64,
}

Marina_Brush_Status :: enum {
    Idle,
    Preview,
    Placed,
    Unsuitable,
    No_Valid_Layout,
    Removed,
}

CURVE_POINT_CAPACITY :: 48
CURVE_MERGE_MINIMUM_COSINE :: f32(0.9961947) // 5 degrees

Curve_Point :: struct {
    x, z: f32,
}

Fixture :: struct {
    project:                                        terrain.Project,
    circulation_plan:                               circulation.Plan,
    circulation_revision:                           u64,
    circulation_plan_valid:                         bool,
    authoring_tool:                                 Authoring_Tool,
    editor_ui:                                      Editor_UI_State,
    tool:                                           terrain.Tool,
    radius:                                         f32,
    strength:                                       f32,
    hardness:                                       f32,
    structure_selected:                             int,
    structure_placing:                              bool `fixture:"-"`,
    structure_moving:                               bool `fixture:"-"`,
    structure_anchor_x:                             f32 `fixture:"-"`,
    structure_anchor_z:                             f32 `fixture:"-"`,
    structure_preview_end_x:                        f32 `fixture:"-"`,
    structure_preview_end_z:                        f32 `fixture:"-"`,
    structure_grab_offset_x:                        f32 `fixture:"-"`,
    structure_grab_offset_z:                        f32 `fixture:"-"`,
    structure_preview:                              terrain.Structure `fixture:"-"`,
    structure_kind:                                 terrain.Formation_Kind,
    structure_auto_kind:                            bool,
    structure_force_box:                            bool,
    structure_cliff_mode:                           bool,
    structure_scatter_mode:                         bool,
    structure_scatter_count:                        int,
    formation_brush_painting:                       bool `fixture:"-"`,
    formation_brush_group_id:                       u64 `fixture:"-"`,
    formation_brush_last_x, formation_brush_last_z: f32 `fixture:"-"`,
    formation_brush_radius:                         f32,
    formation_brush_strength:                       f32,
    formation_brush_hardness:                       f32,
    foliage_hedgerow_mode:                          bool,
    architecture_node_mode:                         bool,
    architecture_paint_mode:                        bool,
    architecture_painting:                          bool `fixture:"-"`,
    architecture_density_preview:                   [terrain.CITY_DENSITY_SAMPLES]u8 `fixture:"-"`,
    architecture_preview_plan:                      architecture.City_Plan `fixture:"-"`,
    architecture_city_plan:                         architecture.City_Plan,
    architecture_dirty_bounds:                      architecture.City_Bounds `fixture:"-"`,
    architecture_last_x, architecture_last_z:       f32 `fixture:"-"`,
    architecture_brush_radius:                      f32,
    architecture_brush_strength:                    f32,
    architecture_brush_hardness:                    f32,
    marina_paint_mode:                              bool,
    marina_authored:                                bool,
    marina_authored_plan:                           marina.Plan,
    marina_preview_plan:                            marina.Plan,
    marina_preview_valid:                           bool,
    marina_preview_x, marina_preview_z:             f32,
    marina_preview_variation:                       u32,
    marina_brush_radius:                            f32,
    marina_brush_status:                            Marina_Brush_Status,
    marina_brush_suitability:                       f32,
    marina_brush_attempts:                          int,
    farm_paint_mode:                                bool,
    farm_brush_radius:                              f32,
    farms:                                          [FARM_INSTANCE_CAPACITY]Farm_Instance,
    farm_count:                                     int,
    farm_preview:                                   Farm_Instance,
    farm_preview_valid:                             bool,
    farm_preview_score:                             f32,
    farm_preview_site_score:                        f32,
    farm_preview_generation_score:                  f32,
    farm_preview_x:                                 f32,
    farm_preview_z:                                 f32,
    farm_preview_revision:                          u64,
    farm_preview_seed_offset:                       u32,
    default_marinas:                                [len(terrain.DEFAULT_ISLAND_SIGNS)]marina.Plan,
    default_marina_count:                           int,
    climbing_leaf_paint_mode:                       bool,
    climbing_leaf_painting:                         bool `fixture:"-"`,
    climbing_leaf_last_x, climbing_leaf_last_z:     f32 `fixture:"-"`,
    climbing_leaf_brush_radius:                     f32,
    climbing_leaf_brush_strength:                   f32,
    climbing_leaf_brush_hardness:                   f32,
    greek_asset_selected:                           int,
    greek_asset_rotation:                           f32,
    greek_asset_scale:                              f32,
    greek_placements:                               [GREEK_PLACEMENT_CAPACITY]Greek_Placement,
    greek_placement_count:                          int,
    greek_placement_selected:                       int,
    greek_placement_mode:                           bool,
    curve_points:                                   [CURVE_POINT_CAPACITY]Curve_Point,
    curve_point_count:                              int,
    curve_drawing:                                  bool `fixture:"-"`,
    curve_mode:                                     bool,
    curve_cliff_mode:                               bool,
    curve_width:                                    f32,
    curve_height:                                   f32,
    road_mode:                                      bool,
    road_selected_node:                             int,
    road_drag_edge:                                 int `fixture:"-"`,
    road_drag_handle:                               int `fixture:"-"`,
    road_width:                                     f32,
    road_shoulder_width:                            f32,
    road_pavement:                                  roads.Pavement,
    capture_world_only:                             bool,
    capture_player_walk_pose:                       bool,
    capture_player_run_compress_pose:               bool,
    capture_player_turn_left_pose:                  bool,
    capture_player_turn_right_pose:                 bool,
    capture_player_brake_pose:                      bool,
    capture_player_jump_pose:                       bool,
    capture_player_fall_pose:                       bool,
    capture_player_blink_pose:                      bool,
    capture_player_posted_pose:                     bool,
    capture_bougainvillea_seed_enabled:             bool,
    capture_bougainvillea_structure_id:             u64,
    capture_bougainvillea_seed:                     u32,
    benchmark_ground_grass_disabled:                bool,
    structure_undo:                                 [STRUCTURE_HISTORY_CAPACITY]Structure_History_State,
    structure_redo:                                 [STRUCTURE_HISTORY_CAPACITY]Structure_History_State,
    structure_undo_count:                           int,
    structure_redo_count:                           int,
    terrain_undo:                                   [TERRAIN_HISTORY_CAPACITY]Terrain_History_State,
    terrain_redo:                                   [TERRAIN_HISTORY_CAPACITY]Terrain_History_State,
    terrain_undo_count:                             int,
    terrain_redo_count:                             int,
    terrain_file_status:                            cstring,
    terrain_file_status_until:                      f32,
    terrain_saved_revision:                         u64,
    in_map:                                         bool,
    player:                                         third_person.State,
    player_stride_phase:                            f32,
    player_gait_weight:                             f32,
    player_airborne_weight:                         f32,
    player_vertical_pose:                           f32,
    player_turn_pose:                               f32,
    player_brake_pose:                              f32,
    player_posted_idle_seconds:                     f32,
    player_posted_weight:                           f32,
    player_scurry_weight:                           f32,
    player_scurry_lean:                             f32,
    player_scurry_lean_velocity:                    f32,
    player_scurry_compression:                      f32,
    player_scurry_compression_velocity:             f32,
    player_animation_previous_speed:                f32,
    player_paw_plant_positions:                     [4]third_person.Vec3 `fixture:"-"`,
    player_paw_planted:                             [4]bool `fixture:"-"`,
    player_tail:                                    mouse_tail.State,
    camera:                                         third_person.Camera,
    camera_pose:                                    third_person.Camera_Pose,
    cameras:                                        third_person.Camera_System,
    cinematic_playback:                             cinematic.Playback,
    cinematic_focal_length:                         f32,
    story_cinematic_shots:                          [3]cinematic.Shot,
    story_cinematic_script:                         cinematic.Script,
    story_cinematic_restore_pose:                   third_person.Camera_Pose,
    story_meeting_cinematic_pending:                bool,
    story_cinematic_active:                         bool,
    flight_camera:                                  chase_camera.State,
    flight_throttle_overlay_value:                  f32,
    flight_throttle_overlay_changed_at:             f64,
    flight_throttle_overlay_initialized:            bool,
    editor_camera:                                  third_person.Camera,
    editor_focus:                                   third_person.Vec3,
    cursor_world_x, cursor_world_z:                 f32 `fixture:"-"`,
    cursor_height, cursor_material:                 f32 `fixture:"-"`,
    cursor_hit:                                     bool `fixture:"-"`,
    map_time:                                       f32,
    boat_traffic:                                   boats.Traffic,
    marina_dinghy_borrowed:                         bool,
    marina_buoys:                                   Marina_Buoy_Physics,
    pilot:                                          vehicles.Character,
    car:                                            vehicles.Vehicle,
    car_drive:                                      vehicles.Car_Drive_State,
    car_trailer:                                    vehicles.Car_Trailer_State,
    car_trailer_attached:                           bool,
    car_trailer_position:                           third_person.Vec3,
    car_trailer_yaw:                                f32,
    postale:                                        postale_game.Runtime,
    libellula:                                      libellula_game.Runtime,
    aircraft:                                       vehicles.Aircraft_Fleet,
    postale_visible:                                bool,
    libellula_visible:                              bool,
    vehicle_showcase_scene:                         bool,
    wildflower_lab_scene:                           bool,
    vehicle_showcase_target:                        string,
    shadow_lab_scene:                               bool,
    active_lab_scene:                               string,
    settlement_vertical_map:                        bool,
    settlement_plan:                                Settlement_Plan,
    settlement_diagnostic_layer:                    int,
    shadow_lab_collection:                          int,
    shadow_lab_lighting:                            int,
    vehicle_paint_scene:                            bool,
    vehicle_paint_yaw:                              f32,
    vehicle_paint_pitch:                            f32,
    vehicle_paint_distance:                         f32,
    vehicle_paint_settings_initialized:             bool `fixture:"-"`,
    vehicle_paint_panel_visible:                    bool,
    vehicle_paint_color:                            int,
    vehicle_paint_secondary_color:                  int,
    vehicle_paint_pattern:                          int,
    vehicle_paint_pattern_size:                     int,
    vehicle_paint_pattern_rotation:                 f32,
    vehicle_paint_shape_kind:                       int,
    vehicle_paint_shape_size:                       int,
    vehicle_paint_shape_rotation:                   f32,
    vehicle_paint_tool:                             Vehicle_Paint_Tool,
    vehicle_paint_component:                        int,
    vehicle_paint_component_mask:                   [5]bool,
    vehicle_paint_texture_dirty:                    bool `fixture:"-"`,
    vehicle_paint_propeller_color_dirty:            bool `fixture:"-"`,
    vehicle_paint_propeller_color_valid:            bool `fixture:"-"`,
    vehicle_paint_propeller_color:                  rl.Color `fixture:"-"`,
    vehicle_paint_preview_texture_dirty:            bool `fixture:"-"`,
    vehicle_paint_save_pending:                     bool `fixture:"-"`,
    vehicle_paint_save_due_at:                      f32 `fixture:"-"`,
    vehicle_paint_save_failed:                      bool `fixture:"-"`,
    vehicle_paint_clear_confirm_until:              f32 `fixture:"-"`,
    vehicle_paint_sound_until:                      f32 `fixture:"-"`,
    vehicle_paint_saved_postale_position:           flight.Vec3,
    vehicle_paint_saved_libellula_position:         flight.Vec3,
    vehicle_paint_postale_mesh:                     vehicles.Aircraft_Mesh `fixture:"-"`,
    vehicle_paint_cursor_x:                         f32 `fixture:"-"`,
    vehicle_paint_cursor_y:                         f32 `fixture:"-"`,
    vehicle_paint_orbit_drag_active:                bool `fixture:"-"`,
    vehicle_paint_brush_radius:                     int,
    vehicle_paint_brush_hardness:                   f32,
    vehicle_paint_brush_strength:                   f32,
    vehicle_paint_brush_slider_active:              int `fixture:"-"`,
    vehicle_paint_erase:                            bool,
    vehicle_paint_symmetry:                         bool,
    vehicle_paint_stroke_active:                    bool `fixture:"-"`,
    vehicle_paint_stroke_uv_valid:                  bool `fixture:"-"`,
    vehicle_paint_stroke_uv:                        [2]f32 `fixture:"-"`,
    vehicle_paint_stroke_part:                      vehicles.Aircraft_Mesh_Part `fixture:"-"`,
    vehicle_paint_stroke_mirror_valid:              bool `fixture:"-"`,
    vehicle_paint_stroke_mirror_uv:                 [2]f32 `fixture:"-"`,
    vehicle_paint_stroke_mirror_part:               vehicles.Aircraft_Mesh_Part `fixture:"-"`,
    vehicle_paint_tool_drag_active:                 bool `fixture:"-"`,
    vehicle_paint_tool_drag_start_uv:               [2]f32 `fixture:"-"`,
    vehicle_paint_tool_drag_start_screen:           rl.Vector2 `fixture:"-"`,
    vehicle_paint_tool_drag_part:                   vehicles.Aircraft_Mesh_Part `fixture:"-"`,
    vehicle_paint_tool_drag_texels:                 [dynamic]int `fixture:"-"`,
    vehicle_paint_tool_drag_mirror_valid:           bool `fixture:"-"`,
    vehicle_paint_tool_drag_mirror_start_uv:        [2]f32 `fixture:"-"`,
    vehicle_paint_tool_drag_mirror_part:            vehicles.Aircraft_Mesh_Part `fixture:"-"`,
    vehicle_paint_tool_drag_mirror_texels:          [dynamic]int `fixture:"-"`,
    vehicle_paint_hover_hit:                        bool `fixture:"-"`,
    vehicle_paint_hover_component:                  int `fixture:"-"`,
    vehicle_paint_hover_uv:                         [2]f32 `fixture:"-"`,
    vehicle_paint_history_capturing:                bool `fixture:"-"`,
    vehicle_paint_open_pixels:                      []u8 `fixture:"-"`,
    vehicle_paint_layers:                           [VEHICLE_PAINT_AIRCRAFT_COUNT][VEHICLE_PAINT_TEXTURE_BYTE_COUNT]u8,
    vehicle_paint_preview_pixels:                   [VEHICLE_PAINT_TEXTURE_BYTE_COUNT]u8 `fixture:"-"`,
    vehicle_paint_history_pixels:                   [VEHICLE_PAINT_TEXTURE_BYTE_COUNT]u8 `fixture:"-"`,
    vehicle_paint_undo:                             [VEHICLE_PAINT_AIRCRAFT_COUNT][dynamic]Vehicle_Paint_History_Entry `fixture:"-"`,
    vehicle_paint_redo:                             [VEHICLE_PAINT_AIRCRAFT_COUNT][dynamic]Vehicle_Paint_History_Entry `fixture:"-"`,
    vehicle_paint_texel_part:                       [VEHICLE_PAINT_TEXTURE_WIDTH * VEHICLE_PAINT_TEXTURE_HEIGHT]u8 `fixture:"-"`,
    vehicle_paint_components:                       [5]bool,
    attendant_position:                             third_person.Vec3,
    attendant_dialogue:                             dialogue.Conversation `fixture:"-"`,
    attendant_dialogue_open:                        bool `fixture:"-"`,
    attendant_dialogue_focus:                       int `fixture:"-"`,
    attendant_dialogue_action:                      Marta_Menu_Action `fixture:"-"`,
    attendant_dialogue_vehicle_target:              vehicles.Aircraft_Kind `fixture:"-"`,
    attendant_dialogue_vehicle_choices:             [8]vehicles.Aircraft_Kind `fixture:"-"`,
    attendant_dialogue_vehicle_choice_count:        int `fixture:"-"`,
    gerta_position:                                 third_person.Vec3,
    story_state:                                    story.State,
    story_catalog:                                  story.Catalog,
    dialogue_resident:                              story.Resident,
    camera_target_lock:                             bool,
    flight_control:                                 postale_game.Control `fixture:"-"`,
    atmosphere:                                     atmosphere.Atmosphere,
    vehicle_effects:                                particle_systems.Vehicle_Effects,
    wing_trails:                                    particle_systems.Wing_Trails,
    petal_effects:                                  particle_systems.Petal_Effects,
    tweak:                                          Tweak_State,
    tweak_status:                                   Tweak_Status `fixture:"-"`,
    tweak_panel_visible:                            bool `fixture:"-"`,
    pause_screen:                                   Pause_Screen `fixture:"-"`,
    dither_state:                                   Dither_State `fixture:"-"`,
    main_menu_active:                               bool,
    main_menu_focus:                                int,
    console:                                        Game_Console,
    mouse_fur:                                      Mouse_Fur,
    mouse_pattern:                                  Mouse_Fur_Pattern,
    mouse_headgear:                                 Mouse_Accessory,
    mouse_scarf_enabled:                            bool,
    mouse_scarf_color:                              rl.Color,
    mouse_scarf_rotation:                           f32,
    mouse_scarf_angular_velocity:                   f32,
    customization_focus:                            int `fixture:"-"`,
    customization_slider_drag:                      int,
    customization_preview_dragging:                 bool,
    customization_preview_drag_x:                   f32,
    customization_preview_yaw:                      f32,
}

Editor :: struct {
    using fixture:                Fixture,
    flame_graph:                  dio.Flame_Graph,
    last_frame_time:              f64,
    aircraft_fixed_accumulator:   f64,
    aircraft_previous_body:       flight.Body_State,
    aircraft_previous_body_valid: bool,
    greek_assets:                 [GREEK_ASSET_CAPACITY]Greek_Asset,
    greek_asset_count:            int,
    car_physics_world:            physics.World,
    car_physics_vehicle:          physics.Vehicle,
    car_physics_terrain:          [terrain.CLIPMAP_LEVELS]physics.Body_ID,
    car_physics_terrain_revision: u64,
    car_physics_accumulator:      f64,
    car_wheels:                   [4]physics.Wheel_State,
    car_impact_detector:          engine_sound.Vehicle_Impact_Detector,
    car_audio_damage:             f32,
    engine_audio:                 engine_sound.Device,
    car_audio_gearbox:            engine_sound.Car_Gearbox,
    landing_wheel_squeal:         f32,
    landing_wheel_speed:          f32,
    libellula_visual_mesh:        vehicles.Libellula_Mesh,
    libellula_mk2_visual_mesh:    vehicles.Libellula_Mesh,
    libellula_base_mesh:          vehicles.Libellula_Mesh,
    libellula_mk2_base_mesh:      vehicles.Libellula_Mesh,
    postale_base_mesh:            vehicles.Aircraft_Mesh,
    libellula_projected_faces:    [dynamic]Projected_Aircraft_Face,
    gameplay_options:             Gameplay_Options,
    runtime_input:                game_input.State,
    control_hint_atlases:         Control_Hint_Atlases,
    vehicle_paint_tool_icons:     rl.Texture,
    tarot_atlas:                  rl.Texture,
    controller_disconnect_notice: bool,
    pause_focus:                  int,
    options_focus:                int,
    options_scroll_y:             f32,
    options_scroll_dragging:      bool,
    options_scroll_drag_offset:   f32,
    quit_requested:               bool,
}

@(no_instrumentation)
editor_circulation_plan :: #force_inline proc(editor: ^Editor) -> ^circulation.Plan {
    if editor == nil do return nil
    if !editor.circulation_plan_valid || editor.circulation_revision != editor.project.revision {
        editor.circulation_plan = architecture.circulation_plan(&editor.project)
        editor.circulation_revision = editor.project.revision
        editor.circulation_plan_valid = true
    }
    return &editor.circulation_plan
}

Marta_Menu_Action :: enum {
    None,
    Paint_Aircraft,
    Select_Aircraft,
    Borrow_Dinghy,
    Close,
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
    editor.map_time = f32(rl.GetTime())
    set_pointer_locked(true)
}

structure_history_capture :: proc(editor: ^Editor) -> Structure_History_State {
    state: Structure_History_State
    if editor == nil do return state
    state.count = editor.project.structure_count
    state.next_id = editor.project.next_structure_id
    state.road_graph = editor.project.road_graph
    state.city_density = editor.project.city_density
    state.climbing_leaf_density = editor.project.climbing_leaf_density
    state.marina_plan = editor.marina_authored_plan
    state.marina_authored = editor.marina_authored
    state.farms = editor.farms
    state.farm_count = editor.farm_count
    for index in 0 ..< terrain.STRUCTURE_CAPACITY {
        state.structures[index] = editor.project.structures[index]
    }
    return state
}

structure_history_restore :: proc(editor: ^Editor, state: Structure_History_State) {
    if editor == nil do return
    for index in 0 ..< terrain.STRUCTURE_CAPACITY {
        editor.project.structures[index] = state.structures[index]
    }
    editor.project.structure_count = state.count
    editor.project.next_structure_id = state.next_id
    editor.project.road_graph = state.road_graph
    editor.project.city_density = state.city_density
    editor.project.climbing_leaf_density = state.climbing_leaf_density
    editor.marina_authored_plan = state.marina_plan
    editor.marina_authored = state.marina_authored
    editor.farms = state.farms
    editor.farm_count = state.farm_count
    editor.project.revision += 1
    if editor.structure_selected >= editor.project.structure_count do editor.structure_selected = -1
    if editor.road_selected_node >= editor.project.road_graph.node_count do editor.road_selected_node = -1
}

structure_history_push_undo :: proc(editor: ^Editor) {
    if editor == nil do return
    if editor.structure_undo_count < STRUCTURE_HISTORY_CAPACITY {
        editor.structure_undo[editor.structure_undo_count] = structure_history_capture(editor)
        editor.structure_undo_count += 1
    } else {
        for index in 1 ..< STRUCTURE_HISTORY_CAPACITY {
            editor.structure_undo[index - 1] = editor.structure_undo[index]
        }
        editor.structure_undo[STRUCTURE_HISTORY_CAPACITY - 1] = structure_history_capture(editor)
    }
    editor.structure_redo_count = 0
}

structure_history_push_redo :: proc(editor: ^Editor) {
    if editor == nil do return
    if editor.structure_redo_count < STRUCTURE_HISTORY_CAPACITY {
        editor.structure_redo[editor.structure_redo_count] = structure_history_capture(editor)
        editor.structure_redo_count += 1
    } else {
        for index in 1 ..< STRUCTURE_HISTORY_CAPACITY {
            editor.structure_redo[index - 1] = editor.structure_redo[index]
        }
        editor.structure_redo[STRUCTURE_HISTORY_CAPACITY - 1] = structure_history_capture(editor)
    }
}

structure_undo :: proc(editor: ^Editor) {
    if editor == nil || editor.structure_undo_count <= 0 do return
    structure_history_push_redo(editor)
    editor.structure_undo_count -= 1
    structure_history_restore(editor, editor.structure_undo[editor.structure_undo_count])
    if editor.structure_selected >= 0 && editor.structure_selected >= editor.project.structure_count {
        editor.structure_selected = -1
    }
}

structure_redo :: proc(editor: ^Editor) {
    if editor == nil || editor.structure_redo_count <= 0 do return
    if editor.structure_undo_count < STRUCTURE_HISTORY_CAPACITY {
        editor.structure_undo[editor.structure_undo_count] = structure_history_capture(editor)
        editor.structure_undo_count += 1
    } else {
        for index in 1 ..< STRUCTURE_HISTORY_CAPACITY {
            editor.structure_undo[index - 1] = editor.structure_undo[index]
        }
        editor.structure_undo[STRUCTURE_HISTORY_CAPACITY - 1] = structure_history_capture(editor)
    }
    editor.structure_redo_count -= 1
    structure_history_restore(editor, editor.structure_redo[editor.structure_redo_count])
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
}

terrain_history_push_undo :: proc(editor: ^Editor) {
    if editor == nil do return
    if editor.terrain_undo_count < TERRAIN_HISTORY_CAPACITY {
        terrain_history_capture(editor, &editor.terrain_undo[editor.terrain_undo_count])
        editor.terrain_undo_count += 1
    } else {
        for index in 1 ..< TERRAIN_HISTORY_CAPACITY {
            editor.terrain_undo[index - 1] = editor.terrain_undo[index]
        }
        terrain_history_capture(editor, &editor.terrain_undo[TERRAIN_HISTORY_CAPACITY - 1])
    }
    editor.terrain_redo_count = 0
}

terrain_history_push_redo :: proc(editor: ^Editor) {
    if editor == nil do return
    if editor.terrain_redo_count < TERRAIN_HISTORY_CAPACITY {
        terrain_history_capture(editor, &editor.terrain_redo[editor.terrain_redo_count])
        editor.terrain_redo_count += 1
    } else {
        for index in 1 ..< TERRAIN_HISTORY_CAPACITY {
            editor.terrain_redo[index - 1] = editor.terrain_redo[index]
        }
        terrain_history_capture(editor, &editor.terrain_redo[TERRAIN_HISTORY_CAPACITY - 1])
    }
}

terrain_undo :: proc(editor: ^Editor) {
    if editor == nil || editor.terrain_undo_count <= 0 do return
    terrain_history_push_redo(editor)
    editor.terrain_undo_count -= 1
    terrain_history_restore(editor, &editor.terrain_undo[editor.terrain_undo_count])
}

terrain_redo :: proc(editor: ^Editor) {
    if editor == nil || editor.terrain_redo_count <= 0 do return
    if editor.terrain_undo_count < TERRAIN_HISTORY_CAPACITY {
        terrain_history_capture(editor, &editor.terrain_undo[editor.terrain_undo_count])
        editor.terrain_undo_count += 1
    } else {
        for index in 1 ..< TERRAIN_HISTORY_CAPACITY {
            editor.terrain_undo[index - 1] = editor.terrain_undo[index]
        }
        terrain_history_capture(editor, &editor.terrain_undo[TERRAIN_HISTORY_CAPACITY - 1])
    }
    editor.terrain_redo_count -= 1
    terrain_history_restore(editor, &editor.terrain_redo[editor.terrain_redo_count])
}

terrain_file_feedback :: proc(editor: ^Editor, message: cstring) {
    if editor == nil do return
    editor.terrain_file_status = message
    editor.terrain_file_status_until = f32(rl.GetTime()) + 2
}

terrain_project_save :: proc(editor: ^Editor) {
    if editor == nil do return
    if terrain.save_project(&editor.project, TERRAIN_PROJECT_PATH) {
        editor.terrain_saved_revision = editor.project.revision
        terrain_file_feedback(editor, "PROJECT SAVED")
    } else {
        terrain_file_feedback(editor, "SAVE FAILED")
    }
}

architecture_regenerate_all :: proc(editor: ^Editor) {
    if editor == nil do return
    bounds := architecture.city_density_bounds(&editor.project.city_density)
    if !bounds.valid {
        architecture.clear_architecture(&editor.project)
        editor.architecture_city_plan = {}
        return
    }
    plan := architecture.city_plan_density(&editor.project, &editor.project.city_density, bounds)
    _ = architecture.city_commit_plan(&editor.project, &editor.project.city_density, bounds, &plan)
    editor.architecture_city_plan = plan
}

terrain_project_load :: proc(editor: ^Editor) {
    if editor == nil do return
    if terrain.load_project(&editor.project, TERRAIN_PROJECT_PATH) {
        // Parcels are transient and deterministic. Refit all architecture to
        // the saved roads and density instead of persisting product-specific
        // lot data in terrain.Project.
        architecture_regenerate_all(editor)
        // Loading can restore the same authored revision number as the current
        // project. Advance it so revision-keyed render caches always rebuild.
        editor.project.revision += 1
        editor.structure_selected = -1
        editor.structure_placing = false
        editor.structure_moving = false
        editor.architecture_painting = false
        editor.architecture_preview_plan = {}
        editor.architecture_dirty_bounds = {}
        curve_reset(editor)
        editor.structure_undo_count = 0
        editor.structure_redo_count = 0
        editor.terrain_undo_count = 0
        editor.terrain_redo_count = 0
        editor.terrain_saved_revision = editor.project.revision
        terrain_file_feedback(editor, "PROJECT LOADED")
    } else {
        terrain_file_feedback(editor, "LOAD FAILED")
    }
}

formation_kind_name :: proc(kind: terrain.Formation_Kind) -> cstring {
    switch kind {
    case .Box:
        return "BOX"
    case .Rock:
        return "ROCK"
    case .Spire:
        return "SPIRE"
    case .Mountain:
        return "MOUNTAIN"
    case .Ridge:
        return "RIDGE"
    case .Cliff:
        return "CLIFF"
    case .Foliage:
        return "FOLIAGE"
    case .Architecture:
        return "ADRIATIC NODES"
    }
    return "FORMATION"
}

structure_cycle_kind :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.structure_auto_kind = false
    if editor.structure_selected >= 0 && !editor.structure_placing {
        structure_history_push_undo(editor)
        structure := &editor.project.structures[editor.structure_selected]
        structure.kind = terrain.formation_kind_next(structure.kind)
        editor.structure_kind = structure.kind
        editor.project.revision += 1
    } else {
        editor.structure_kind = terrain.formation_kind_next(editor.structure_kind)
        if editor.structure_placing do editor.structure_preview.kind = editor.structure_kind
    }
}

structure_update_preview_kind :: proc(editor: ^Editor) {
    if editor == nil || !editor.structure_placing do return
    if editor.authoring_tool == .Foliage {
        editor.structure_preview.kind = .Foliage
    } else if editor.structure_force_box {
        editor.structure_preview.kind = .Box
    } else if editor.structure_cliff_mode {
        editor.structure_preview.kind = .Cliff
    } else if editor.structure_auto_kind {
        editor.structure_preview.kind = terrain.formation_kind_for_gesture(
            editor.structure_preview.width,
            editor.structure_preview.depth,
            editor.structure_preview.height,
        )
    } else {
        editor.structure_preview.kind = editor.structure_kind
    }
}

structure_editor_snap :: proc(value: f32, editor: ^Editor) -> f32 {
    if shift_key_down() do return value
    return terrain.snap_to_grid(value, editor.project.levels[0].cell_size)
}

structure_update_base :: proc(editor: ^Editor, structure: ^terrain.Structure) {
    if editor == nil || structure == nil do return
    structure.base_y = terrain.sample_height(&editor.project, 0, structure.center_x, structure.center_z)
}

capture_add_formation :: proc(editor: ^Editor, x, z, width, depth, height: f32, kind: terrain.Formation_Kind) -> int {
    if editor == nil do return -1
    structure := terrain.structure_make(x, z, width, depth, 0, height)
    structure.kind = kind
    structure.base_y = terrain.sample_height(&editor.project, 0, x, z)
    return terrain.add_structure(&editor.project, structure)
}

structure_commit_placement :: proc(editor: ^Editor, end_x, end_z: f32) -> int {
    if editor == nil do return -1
    index := terrain.add_structure(&editor.project, editor.structure_preview)
    last_index := index
    if !editor.structure_scatter_mode || index < 0 do return index

    dx := end_x - editor.structure_anchor_x
    dz := end_z - editor.structure_anchor_z
    length := f32(math.sqrt(f64(dx * dx + dz * dz)))
    if length <= 0 do return index
    direction_x, direction_z := dx / length, dz / length
    perpendicular_x, perpendicular_z := -direction_z, direction_x
    cell := editor.project.levels[0].cell_size
    for cluster_index in 0 ..< editor.structure_scatter_count - 1 {
        offset := f32(cluster_index) - f32(editor.structure_scatter_count - 2) * .5
        copy := editor.structure_preview
        copy.center_x += direction_x * offset * length * .22
        copy.center_z += direction_z * offset * length * .22
        jitter := f32(math.sin(f64(f32(cluster_index) * 2.31 + f32(editor.project.next_structure_id) * .17)))
        copy.center_x += perpendicular_x * jitter * length * .10
        copy.center_z += perpendicular_z * jitter * length * .10
        copy.width = max(cell, copy.width * (.58 + f32(cluster_index % 2) * .12))
        copy.depth = max(cell, copy.depth * (.58 + f32((cluster_index + 1) % 2) * .12))
        copy.height = max(cell, copy.height * (.72 + f32(cluster_index) * .06))
        copy.base_y = terrain.sample_height(&editor.project, 0, copy.center_x, copy.center_z)
        if editor.authoring_tool == .Foliage {
            copy.kind = .Foliage
        } else if !editor.structure_force_box && !editor.structure_cliff_mode {
            copy.kind = terrain.formation_kind_for_gesture(copy.width, copy.depth, copy.height)
        }
        last_index = terrain.add_structure(&editor.project, copy)
    }
    return last_index
}

formation_brush_is_target :: proc(editor: ^Editor, kind: terrain.Formation_Kind) -> bool {
    if editor.authoring_tool == .Foliage do return kind == .Foliage
    return kind != .Foliage && kind != .Architecture
}

formation_brush_stamp :: proc(editor: ^Editor, world_x, world_z: f32, erase: bool) {
    if editor == nil do return
    radius := editor.formation_brush_radius
    if erase {
        for index := editor.project.structure_count - 1; index >= 0; index -= 1 {
            structure := editor.project.structures[index]
            if !formation_brush_is_target(editor, structure.kind) do continue
            dx, dz := structure.center_x - world_x, structure.center_z - world_z
            if dx * dx + dz * dz <= radius * radius {
                terrain.remove_structure(&editor.project, index)
            }
        }
        return
    }
    cell := editor.project.levels[0].cell_size
    stamp_count := max(1, 1 + int(editor.formation_brush_strength * 3))
    group_id := editor.formation_brush_group_id
    if group_id == 0 do group_id = editor.project.next_structure_id
    for stamp in 0 ..< stamp_count {
        // Stable noise keeps a stroke varied without making undo/redo or a
        // saved project depend on the runtime random-number stream.
        seed := f32(stamp) * 17.13 + world_x * .071 + world_z * .113 + f32(editor.project.next_structure_id) * .037
        radial_noise := f32(math.sin(f64(seed * 1.71))) * .5 + .5
        angle_noise := f32(math.sin(f64(seed * 2.43 + 4.1))) * .5 + .5
        radial_power := .55 + editor.formation_brush_hardness * 1.8
        radial := radius * f32(math.pow(f64(radial_noise), f64(radial_power)))
        angle := angle_noise * math.PI * 2
        x := world_x + math.cos(angle) * radial
        z := world_z + math.sin(angle) * radial
        size_noise := f32(math.sin(f64(seed * 3.19 + 1.7))) * .5 + .5
        width, depth, height: f32
        if editor.authoring_tool == .Foliage {
            width = max(cell, radius * (.18 + size_noise * .18))
            depth = max(cell, width * (.72 + size_noise * .42))
            height = max(cell, width * (.75 + size_noise * .8))
        } else {
            width = max(cell, radius * (.14 + size_noise * .16))
            depth = max(cell, width * (.72 + size_noise * .55))
            height = max(cell, radius * (.22 + size_noise * .44))
        }
        structure := terrain.structure_make(x, z, width, depth, 0, height)
        structure.rotation = angle + f32(math.sin(f64(seed * 1.13))) * .7
        structure.group_id = group_id
        structure.base_y = terrain.sample_height(&editor.project, 0, x, z)
        if editor.authoring_tool == .Foliage {
            structure.kind = .Foliage
        } else if editor.structure_auto_kind {
            structure.kind = terrain.formation_kind_for_gesture(width, depth, height)
        } else {
            structure.kind = editor.structure_kind
        }
        if editor.authoring_tool == .Foliage {
            if terrain.add_or_merge_foliage(&editor.project, structure, cell * .5) < 0 do return
        } else {
            merged_index := terrain.add_or_merge_formation(
                &editor.project,
                structure,
                cell * .5,
                editor.structure_auto_kind,
            )
            if merged_index < 0 do return
        }
    }
}

formation_brush_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || editor.tool != .Structure do return
    if editor.authoring_tool != .Formations && editor.authoring_tool != .Foliage do return
    if editor.authoring_tool == .Foliage && editor.foliage_hedgerow_mode do return
    if !cursor_hit {
        if rl.IsMouseButtonReleased(.LEFT) || rl.IsMouseButtonReleased(.RIGHT) {
            editor.formation_brush_painting = false
            editor.formation_brush_group_id = 0
        }
        return
    }
    pressed := rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT)
    down := rl.IsMouseButtonDown(.LEFT) || rl.IsMouseButtonDown(.RIGHT)
    erase := rl.IsMouseButtonDown(.RIGHT)
    if pressed {
        structure_history_push_undo(editor)
        editor.formation_brush_group_id = editor.project.next_structure_id
        editor.formation_brush_painting = true
        editor.formation_brush_last_x, editor.formation_brush_last_z = world_x, world_z
        formation_brush_stamp(editor, world_x, world_z, erase)
    }
    if editor.formation_brush_painting && down && !pressed {
        dx, dz := world_x - editor.formation_brush_last_x, world_z - editor.formation_brush_last_z
        distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
        step := max(editor.formation_brush_radius * .30, terrain.BASE_CELL_SIZE * .45)
        stamps := int(math.floor(f64(distance / step)))
        if stamps > 0 {
            direction_x, direction_z := dx / distance, dz / distance
            for stamp in 1 ..= stamps {
                travel := f32(stamp) * step
                x := editor.formation_brush_last_x + direction_x * travel
                z := editor.formation_brush_last_z + direction_z * travel
                formation_brush_stamp(editor, x, z, erase)
            }
            // Keep the unpainted tail so sub-step mouse movement accumulates
            // across frames instead of producing a stamp on every frame.
            editor.formation_brush_last_x += direction_x * f32(stamps) * step
            editor.formation_brush_last_z += direction_z * f32(stamps) * step
        }
    }
    if editor.formation_brush_painting && (rl.IsMouseButtonReleased(.LEFT) || rl.IsMouseButtonReleased(.RIGHT)) {
        editor.formation_brush_painting = false
        editor.formation_brush_group_id = 0
    }
}

curve_segment_structure :: proc(editor: ^Editor, start, end: Curve_Point) -> terrain.Structure {
    dx, dz := end.x - start.x, end.z - start.z
    length := f32(math.sqrt(f64(dx * dx + dz * dz)))
    cell := editor.project.levels[0].cell_size
    structure := terrain.structure_make(
        (start.x + end.x) * .5,
        (start.z + end.z) * .5,
        max(length + cell * .35, cell),
        max(editor.curve_width, cell),
        0,
        max(editor.curve_height, cell),
    )
    structure.rotation = math.atan2(dz, dx)
    structure.kind = editor.curve_cliff_mode ? .Cliff : .Ridge
    structure.base_y = terrain.sample_height(&editor.project, 0, structure.center_x, structure.center_z)
    return structure
}

curve_commit :: proc(editor: ^Editor) -> int {
    if editor == nil || editor.curve_point_count < 2 do return -1
    last_index := -1
    // Keep all segments from one freehand ridge in the same edit group so
    // post-placement sizing acts on the ridge as a whole.
    group_id := editor.project.next_structure_id
    segment_start := editor.curve_points[0]
    segment_end := editor.curve_points[1]
    for index in 2 ..< editor.curve_point_count {
        next := editor.curve_points[index]
        if terrain.formation_segments_can_merge(
            segment_start.x,
            segment_start.z,
            segment_end.x,
            segment_end.z,
            next.x,
            next.z,
            CURVE_MERGE_MINIMUM_COSINE,
        ) {
            segment_end = next
            continue
        }
        segment := curve_segment_structure(editor, segment_start, segment_end)
        segment.group_id = group_id
        last_index = terrain.add_structure(&editor.project, segment)
        if last_index < 0 do return last_index
        segment_start = segment_end
        segment_end = next
    }
    segment := curve_segment_structure(editor, segment_start, segment_end)
    segment.group_id = group_id
    last_index = terrain.add_structure(&editor.project, segment)
    return last_index
}

curve_reset :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.curve_point_count = 0
    editor.curve_drawing = false
}

road_node_at :: proc(editor: ^Editor, x, z: f32) -> int {
    if editor == nil do return -1
    graph := &editor.project.road_graph
    hit_radius := max(editor.road_width, terrain.BASE_CELL_SIZE * .35)
    best_distance := hit_radius * hit_radius
    best := -1
    for node, index in graph.nodes[:graph.node_count] {
        dx, dz := x - node.position.x, z - node.position.z
        distance := dx * dx + dz * dz
        if distance <= best_distance {
            best_distance = distance
            best = index
        }
    }
    return best
}

road_handle_at :: proc(editor: ^Editor, x, z: f32) -> (edge_index, handle_index: int) {
    edge_index, handle_index = -1, -1
    if editor == nil || editor.road_selected_node < 0 do return
    graph := &editor.project.road_graph
    hit_radius := max(editor.road_width * .65, terrain.BASE_CELL_SIZE * .25)
    best_distance := hit_radius * hit_radius
    for edge, index in graph.edges[:graph.edge_count] {
        if edge.from != editor.road_selected_node && edge.to != editor.road_selected_node do continue
        handles := [2]roads.Vec3{edge.control_from, edge.control_to}
        for candidate, handle in handles {
            dx, dz := x - candidate.x, z - candidate.z
            distance := dx * dx + dz * dz
            if distance <= best_distance {
                best_distance = distance
                edge_index = index
                handle_index = handle
            }
        }
    }
    return
}

road_add_node :: proc(editor: ^Editor, x, z: f32) -> int {
    if editor == nil do return -1
    snapped_x := structure_editor_snap(x, editor)
    snapped_z := structure_editor_snap(z, editor)
    y := terrain.sample_height(&editor.project, 0, snapped_x, snapped_z)
    return roads.add_node(
        &editor.project.road_graph,
        {snapped_x, y, snapped_z},
        max(editor.road_width * .8, terrain.BASE_CELL_SIZE * .35),
    )
}

road_connect :: proc(editor: ^Editor, from, to: int) -> int {
    if editor == nil || from == to do return -1
    graph := &editor.project.road_graph
    existing := roads.edge_between(graph, from, to)
    if existing >= 0 do return existing
    return roads.add_straight_edge(
        graph,
        from,
        to,
        editor.road_width,
        editor.road_shoulder_width,
        editor.road_pavement,
    )
}

road_set_pavement :: proc(editor: ^Editor, pavement: roads.Pavement) {
    if editor == nil || !editor.road_mode do return
    editor.road_pavement = pavement
    if editor.road_selected_node < 0 do return
    needs_change := false
    for edge in editor.project.road_graph.edges[:editor.project.road_graph.edge_count] {
        if (edge.from == editor.road_selected_node || edge.to == editor.road_selected_node) &&
           edge.pavement != pavement {
            needs_change = true
            break
        }
    }
    if !needs_change do return
    structure_history_push_undo(editor)
    for &edge in editor.project.road_graph.edges[:editor.project.road_graph.edge_count] {
        if edge.from == editor.road_selected_node || edge.to == editor.road_selected_node {
            edge.pavement = pavement
        }
    }
    editor.project.revision += 1
}

road_cycle_pavement :: proc(editor: ^Editor) {
    if editor == nil do return
    road_set_pavement(editor, roads.pavement_next(editor.road_pavement))
}

road_delete_selected :: proc(editor: ^Editor) {
    if editor == nil || editor.road_selected_node < 0 do return
    structure_history_push_undo(editor)
    if roads.remove_node(&editor.project.road_graph, editor.road_selected_node) {
        editor.project.revision += 1
        architecture_regenerate_all(editor)
    }
    editor.road_selected_node = -1
    editor.road_drag_edge = -1
    editor.road_drag_handle = -1
}

road_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || !editor.road_mode do return
    graph := &editor.project.road_graph
    if editor.road_drag_edge >= 0 {
        if rl.IsMouseButtonDown(.LEFT) && cursor_hit {
            edge := &graph.edges[editor.road_drag_edge]
            snapped_x := structure_editor_snap(world_x, editor)
            snapped_z := structure_editor_snap(world_z, editor)
            point := roads.Vec3 {
                snapped_x,
                terrain.sample_height(&editor.project, 0, snapped_x, snapped_z) + .08,
                snapped_z,
            }
            if editor.road_drag_handle == 0 {
                edge.control_from = point
            } else {
                edge.control_to = point
            }
            editor.project.revision += 1
            architecture_regenerate_all(editor)
        }
        if rl.IsMouseButtonReleased(.LEFT) {
            editor.road_drag_edge = -1
            editor.road_drag_handle = -1
        }
        return
    }
    if rl.IsMouseButtonPressed(.RIGHT) {
        editor.road_selected_node = -1
        return
    }
    if !cursor_hit || !rl.IsMouseButtonPressed(.LEFT) do return
    edge_index, handle_index := road_handle_at(editor, world_x, world_z)
    if edge_index >= 0 {
        structure_history_push_undo(editor)
        editor.road_drag_edge = edge_index
        editor.road_drag_handle = handle_index
        return
    }
    clicked_node := road_node_at(editor, world_x, world_z)
    if clicked_node >= 0 {
        if editor.road_selected_node >= 0 && editor.road_selected_node != clicked_node {
            if roads.edge_between(graph, editor.road_selected_node, clicked_node) < 0 {
                structure_history_push_undo(editor)
                _ = road_connect(editor, editor.road_selected_node, clicked_node)
                editor.project.revision += 1
                architecture_regenerate_all(editor)
            }
        }
        editor.road_selected_node = clicked_node
        return
    }
    structure_history_push_undo(editor)
    new_node := road_add_node(editor, world_x, world_z)
    if new_node >= 0 {
        if editor.road_selected_node >= 0 do _ = road_connect(editor, editor.road_selected_node, new_node)
        editor.road_selected_node = new_node
        editor.project.revision += 1
        architecture_regenerate_all(editor)
    }
}

editor_cancel_interaction :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.structure_placing = false
    editor.structure_moving = false
    editor.architecture_painting = false
    editor.architecture_preview_plan = {}
    editor.architecture_dirty_bounds = {}
    editor.road_selected_node = -1
    editor.road_drag_edge = -1
    editor.road_drag_handle = -1
    curve_reset(editor)
}

curve_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || editor.tool != .Structure || !editor.curve_mode do return
    if !cursor_hit {
        if rl.IsMouseButtonReleased(.LEFT) || rl.IsMouseButtonReleased(.RIGHT) do curve_reset(editor)
        return
    }
    cell := editor.project.levels[0].cell_size
    if rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) {
        structure_history_push_undo(editor)
        // RIDGE and CLIFF are persistent palette tools. Do not derive the
        // profile from the button used to begin the stroke, or a normal
        // left-click immediately turns the selected CLIFF tool into RIDGE.
        editor.curve_point_count = 1
        editor.curve_points[0] = {structure_editor_snap(world_x, editor), structure_editor_snap(world_z, editor)}
        editor.curve_drawing = true
    }
    if editor.curve_drawing && (rl.IsMouseButtonDown(.LEFT) || rl.IsMouseButtonDown(.RIGHT)) {
        if editor.curve_point_count < CURVE_POINT_CAPACITY {
            last := editor.curve_points[editor.curve_point_count - 1]
            x, z := structure_editor_snap(world_x, editor), structure_editor_snap(world_z, editor)
            dx, dz := x - last.x, z - last.z
            if dx * dx + dz * dz >= cell * cell * .45 {
                editor.curve_points[editor.curve_point_count] = {x, z}
                editor.curve_point_count += 1
            }
        }
    }
    if editor.curve_drawing && (rl.IsMouseButtonReleased(.LEFT) || rl.IsMouseButtonReleased(.RIGHT)) {
        if editor.curve_point_count >= 2 {
            last_index := curve_commit(editor)
            if last_index >= 0 do editor.structure_selected = last_index
        }
        curve_reset(editor)
    }
}

seed_formation_capture :: proc(editor: ^Editor) {
    if editor == nil do return
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    architecture.generate(&editor.project, center, center, 0xA71D3)
    editor.authoring_tool = .Formations
    editor.tool = .Structure
    editor.structure_selected = -1
    editor.structure_placing = false
    editor.structure_scatter_mode = false
    editor.structure_auto_kind = false
    editor.architecture_node_mode = true
    editor.architecture_paint_mode = false
    editor.road_mode = false
}

seed_foliage_capture :: proc(editor: ^Editor) {
    if editor == nil do return
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    _ = capture_add_formation(editor, center - 70, center + 35, 115, 92, 52, .Foliage)
    hedge := capture_add_formation(editor, center + 38, center + 58, 185, 42, 46, .Foliage)
    if hedge >= 0 do editor.project.structures[hedge].rotation = -.18
    _ = capture_add_formation(editor, center + 45, center - 72, 170, 145, 68, .Foliage)
    editor.authoring_tool = .Foliage
    editor.tool = .Structure
    editor.structure_kind = .Foliage
    editor.structure_auto_kind = false
    editor.structure_selected = -1
    editor.structure_placing = false
    editor.architecture_node_mode = false
    editor.architecture_paint_mode = false
    editor.road_mode = false
}

seed_foliage_stress :: proc(editor: ^Editor) {
    if editor == nil do return
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    for z_index in -3 ..= 3 {
        for x_index in -3 ..= 3 {
            index := (z_index + 3) * 7 + x_index + 3
            jitter_x := f32(math.sin(f64(index) * 2.17 + .4)) * 14
            jitter_z := f32(math.sin(f64(index) * 1.43 + 2.1)) * 14
            x := center + f32(x_index) * 68 + jitter_x
            z := center + f32(z_index) * 62 + jitter_z
            width := f32(92 + (index % 4) * 9)
            depth := f32(82 + ((index + 2) % 4) * 8)
            height := f32(42 + (index % 5) * 7)
            foliage := capture_add_formation(editor, x, z, width, depth, height, .Foliage)
            if foliage >= 0 {
                editor.project.structures[foliage].rotation = f32(math.sin(f64(index) * .73)) * .34
            }
        }
    }
    editor.authoring_tool = .Foliage
    editor.tool = .Structure
    editor.structure_kind = .Foliage
    editor.structure_auto_kind = false
    editor.structure_selected = -1
    editor.structure_placing = false
    editor.architecture_node_mode = false
    editor.architecture_paint_mode = false
    editor.road_mode = false
    editor.editor_camera.distance = 610
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
}

seed_foliage_forest_capture :: proc(editor: ^Editor) {
    if editor == nil do return
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)

    // Two deliberately uneven canopy tiers frame an open glade. The inner
    // crowns stay low enough to reveal the taller back line, while varying
    // widths and rotations keep the forest edge from resolving into a ring.
    for index in 0 ..< 8 {
        // Leave a camera-facing break so the glade reads as an invitation into
        // the forest and the taller back tier exposes occasional trunks.
        if index == 0 || index == 1 do continue
        angle := f32(index) * math.PI * 2 / 8 + .22
        radius := f32(102 + (index % 3) * 9)
        x := center + math.cos(angle) * radius
        z := center + math.sin(angle) * radius * .82
        width := f32(82 + (index % 4) * 9)
        depth := f32(76 + ((index + 2) % 4) * 8)
        height := f32(40 + (index % 3) * 7)
        if index % 2 == 0 {
            // Alternate young trees with the low glade shrubs. This exposes
            // trunks and forked limbs at eye level while keeping a soft,
            // inhabited forest edge rather than a uniform wall of canopy.
            width = f32(108 + (index % 3) * 8)
            depth = f32(101 + ((index + 1) % 3) * 7)
            height = f32(60 + (index % 3) * 6)
        }
        foliage := capture_add_formation(editor, x, z, width, depth, height, .Foliage)
        if foliage >= 0 do editor.project.structures[foliage].rotation = angle * .31 - .45
    }
    for index in 0 ..< 13 {
        angle := f32(index) * math.PI * 2 / 13 - .11
        radius := f32(198 + ((index * 7) % 5) * 11)
        x := center + math.cos(angle) * radius
        z := center + math.sin(angle) * radius * .76
        width := f32(112 + (index % 5) * 10)
        depth := f32(96 + ((index + 3) % 5) * 9)
        height := f32(59 + (index % 4) * 9)
        foliage := capture_add_formation(editor, x, z, width, depth, height, .Foliage)
        if foliage >= 0 do editor.project.structures[foliage].rotation = -.28 + f32(index % 5) * .14
    }

    editor.authoring_tool = .Foliage
    editor.tool = .Structure
    editor.structure_kind = .Foliage
    editor.structure_auto_kind = false
    editor.structure_selected = -1
    editor.structure_placing = false
    editor.architecture_node_mode = false
    editor.architecture_paint_mode = false
    editor.road_mode = false
    editor.editor_focus.y = 18
    editor.editor_camera.pitch_radians = .40
    editor.editor_camera.distance = 540
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
}

configure_foliage_understory_camera :: proc(editor: ^Editor) {
    if editor == nil do return
    island_center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    // Reuse one deterministic walking-distance view for screenshot and
    // performance regression so the measured workload matches visible roots,
    // trunks, canopy attachment, and the lush fern LOD.
    target_index := 3
    target_angle := f32(target_index) * math.PI * 2 / 13 - .11
    target_radius := f32(198 + ((target_index * 7) % 5) * 11)
    editor.editor_focus.x = island_center + math.cos(target_angle) * target_radius
    editor.editor_focus.z = island_center + math.sin(target_angle) * target_radius * .76
    editor.editor_focus.y = 7
    editor.editor_camera.pitch_radians = .035
    editor.editor_camera.distance = 72
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
}

seed_road_grip_benchmark :: proc(editor: ^Editor) {
    if editor == nil do return
    seed_road_capture(editor)
    if editor.project.road_graph.edge_count <= 0 do return
    edge := editor.project.road_graph.edges[0]
    point := roads.edge_point(&editor.project.road_graph, edge, .08)
    tangent := roads.edge_tangent(&editor.project.road_graph, edge, .08)
    editor.car.position = {point.x, point.y, point.z}
    editor.car.yaw_radians = math.atan2(tangent.z, tangent.x)
    car_physics_teleport(editor)
    editor.pilot.position = editor.car.position
    _, entered := vehicles.try_enter_nearest(&editor.pilot, []^vehicles.Vehicle{&editor.car})
    if !entered do return
    editor.in_map = true
    editor.map_time = f32(rl.GetTime())
    editor.camera = third_person.default_camera()
    editor.camera_pose = third_person.camera_pose(editor.car.position, editor.camera)
}

seed_terrain_grip_benchmark :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.project.road_graph = {}
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    center := half_extent * terrain.DEFAULT_ISLAND_OFFSET
    editor.car.position = {center + half_extent * terrain.DEFAULT_ISLAND_RADIUS, 0, center}
    editor.car.position.y = terrain.sample_height(&editor.project, 0, editor.car.position.x, editor.car.position.z)
    editor.car.yaw_radians = math.PI * .5
    car_physics_teleport(editor)
    editor.pilot.position = editor.car.position
    _, entered := vehicles.try_enter_nearest(&editor.pilot, []^vehicles.Vehicle{&editor.car})
    if !entered do return
    editor.in_map = true
    editor.map_time = f32(rl.GetTime())
    editor.camera = third_person.default_camera()
    editor.camera_pose = third_person.camera_pose(editor.car.position, editor.camera)
}

seed_player_benchmark :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.player = {
        position = runway_spawn_position(editor),
        grounded = true,
    }
    editor.player.position.x += 24
    editor.player.position.z += 20
    editor.player.position.y = terrain.sample_height(
        &editor.project,
        0,
        editor.player.position.x,
        editor.player.position.z,
    )
    editor.pilot.position = editor.player.position
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.in_map = true
    editor.map_time = f32(rl.GetTime())
    editor.camera = third_person.default_camera()
    editor.camera_pose = third_person.camera_pose(editor.player.position, editor.camera)
}

benchmark_seed_scene :: proc(editor: ^Editor, scenario: string) -> bool {
    if editor == nil do return false
    switch scenario {
    case "editor":
        return true
    case "foliage":
        seed_foliage_capture(editor)
    case "foliage_forest":
        seed_foliage_forest_capture(editor)
    case "foliage_understory":
        seed_foliage_forest_capture(editor)
        configure_foliage_understory_camera(editor)
    case "foliage_stress":
        seed_foliage_stress(editor)
    case "formations":
        seed_formation_capture(editor)
    case "roads":
        seed_road_capture(editor)
    case "road_dust":
        seed_road_capture(editor)
        seed_road_dust_capture(editor)
    case "road_grip":
        seed_road_grip_benchmark(editor)
    case "terrain_grip":
        seed_terrain_grip_benchmark(editor)
    case "player":
        seed_player_benchmark(editor)
    case "grass":
        seed_player_benchmark(editor)
    case "grass_disabled":
        seed_player_benchmark(editor)
        editor.benchmark_ground_grass_disabled = true
    case "architecture":
        seed_city_capture(editor)
    case "shadow_lab":
        _ = lab_scene_load(editor, {definition = lab_scene_find("shadow")})
    case:
        return false
    }
    if scenario != "foliage_stress" &&
       scenario != "foliage_forest" &&
       scenario != "foliage_understory" &&
       scenario != "road_grip" &&
       scenario != "terrain_grip" &&
       scenario != "player" &&
       scenario != "grass" &&
       scenario != "grass_disabled" &&
       scenario != "shadow_lab" {
        editor.editor_camera.distance = 260
        editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    }
    return true
}

benchmark_percentile :: proc(sorted_samples: []f64, fraction: f64) -> f64 {
    if len(sorted_samples) <= 0 do return 0
    index := int(math.ceil(fraction * f64(len(sorted_samples)))) - 1
    return sorted_samples[clamp(index, 0, len(sorted_samples) - 1)]
}

benchmark_report :: proc(
    scenario: string,
    samples: []f64,
    window_width, window_height, world_width, world_height: int,
) {
    if len(samples) <= 0 do return
    sorted := make([]f64, len(samples))
    defer delete(sorted)
    copy(sorted, samples)
    slice.sort(sorted)
    total := f64(0)
    for sample in sorted do total += sample
    median := benchmark_percentile(sorted, .50)
    p95 := benchmark_percentile(sorted, .95)
    p99 := benchmark_percentile(sorted, .99)
    maximum := sorted[len(sorted) - 1]
    world_vertex_count := len(world_renderer.vertices)
    road_vertex_count := len(world_renderer.road_vertices)
    foliage_vertex_count :=
        len(world_renderer.foliage_vertices) +
        len(world_renderer.bougainvillea_vertices) +
        (len(world_renderer.grass_instances) + len(world_renderer.wildflower_instances)) * 6
    world_vertex_utilization := f64(world_vertex_count) / f64(max(WORLD_VERTEX_CAPACITY, 1))
    foliage_vertex_capacity :=
        FOLIAGE_VERTEX_CAPACITY +
        BOUGAINVILLEA_VERTEX_CAPACITY +
        (GRASS_INSTANCE_CAPACITY + WILDFLOWER_INSTANCE_CAPACITY) * 6
    foliage_vertex_utilization := f64(foliage_vertex_count) / f64(max(foliage_vertex_capacity, 1))
    road_vertex_utilization := f64(road_vertex_count) / f64(max(ROAD_VERTEX_CAPACITY, 1))
    fmt.printf(
        "BENCHMARK_RESULT {{\"scenario\":\"%s\",\"samples\":%d,\"window\":[%d,%d],\"world\":[%d,%d],\"mean_ms\":%.4f,\"median_ms\":%.4f,\"p95_ms\":%.4f,\"p99_ms\":%.4f,\"max_ms\":%.4f,\"median_fps\":%.2f,\"geometry\":{{\"world_vertices\":%d,\"world_capacity\":%d,\"world_utilization\":%.6f,\"road_vertices\":%d,\"road_capacity\":%d,\"road_utilization\":%.6f,\"foliage_vertices\":%d,\"foliage_capacity\":%d,\"foliage_utilization\":%.6f}}}}\n",
        scenario,
        len(sorted),
        window_width,
        window_height,
        world_width,
        world_height,
        total / f64(len(sorted)) * 1000,
        median * 1000,
        p95 * 1000,
        p99 * 1000,
        maximum * 1000,
        1 / max(median, f64(.000001)),
        world_vertex_count,
        WORLD_VERTEX_CAPACITY,
        world_vertex_utilization,
        road_vertex_count,
        ROAD_VERTEX_CAPACITY,
        road_vertex_utilization,
        foliage_vertex_count,
        foliage_vertex_capacity,
        foliage_vertex_utilization,
    )
}

seed_road_capture :: proc(editor: ^Editor) {
    if editor == nil do return
    graph := &editor.project.road_graph
    graph^ = {}
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    node_positions := [5]roads.Vec3 {
        {center - 145, 0, center + 80},
        {center - 45, 0, center + 20},
        {center + 105, 0, center - 45},
        {center - 15, 0, center - 125},
        {center - 15, 0, center + 135},
    }
    for &position in node_positions {
        position.y = terrain.sample_height(&editor.project, 0, position.x, position.z)
    }
    west := roads.add_node(graph, node_positions[0], 7)
    junction := roads.add_node(graph, node_positions[1], 10)
    east := roads.add_node(graph, node_positions[2], 7)
    south := roads.add_node(graph, node_positions[3], 7)
    north := roads.add_node(graph, node_positions[4], 7)
    _ = roads.add_edge(
        graph,
        west,
        junction,
        {center - 115, node_positions[0].y, center + 40},
        {center - 78, node_positions[1].y, center + 62},
        12,
        2.2,
        .Asphalt,
    )
    _ = roads.add_edge(
        graph,
        junction,
        east,
        {center + 5, node_positions[1].y, center - 15},
        {center + 58, node_positions[2].y, center + 2},
        11,
        2.1,
        .Cobblestone,
    )
    _ = roads.add_edge(
        graph,
        junction,
        south,
        {center - 70, node_positions[1].y, center - 35},
        {center - 55, node_positions[3].y, center - 92},
        9,
        1.9,
        .Dirt,
    )
    _ = roads.add_edge(
        graph,
        junction,
        north,
        {center - 70, node_positions[1].y, center + 65},
        {center - 45, node_positions[4].y, center + 100},
        10,
        2,
        .Gravel,
    )
    editor.authoring_tool = .Roads
    editor.tool = .Structure
    editor.road_mode = true
    editor.architecture_node_mode = false
    editor.road_selected_node = junction
    editor.project.revision += 1
}

seed_road_dust_capture :: proc(editor: ^Editor) {
    if editor == nil do return
    for edge in editor.project.road_graph.edges[:editor.project.road_graph.edge_count] {
        point := roads.edge_point(&editor.project.road_graph, edge, .58)
        surface := particle_systems.Dust_Surface.Grass
        switch edge.pavement {
        case .Asphalt:
            surface = .Asphalt
        case .Gravel:
            surface = .Gravel
        case .Cobblestone:
            surface = .Cobblestone
        case .Dirt:
            surface = .Dirt
        }
        contact := particle_systems.Vehicle_Contact {
            position = {point.x, point.y + .12, point.z},
            grounded = true,
            surface  = surface,
        }
        first_particle := editor.vehicle_effects.dust_count
        for preview_index in 0 ..< 48 {
            angle := f32(preview_index) * math.PI * 2 / 48
            radius := f32(preview_index % 9) * .28
            preview_contact := contact
            preview_contact.position.x += math.cos(angle) * radius
            preview_contact.position.z += math.sin(angle) * radius
            particle_systems.spawn_dust(&editor.vehicle_effects, preview_contact, 1.15)
        }
        // The overview camera sees all four materials at once, so magnify only
        // its diagnostic billboards while preserving each runtime profile.
        for index in first_particle ..< editor.vehicle_effects.dust_count {
            editor.vehicle_effects.dust[index].size *= 5.5
        }
    }
    empty_contacts: [4]particle_systems.Vehicle_Contact
    particle_systems.step_vehicle_effects(&editor.vehicle_effects, .05, 0, 0, false, 0, empty_contacts)
    particle_systems.step_vehicle_effects(&editor.vehicle_effects, .05, 0, 0, false, 0, empty_contacts)
}

seed_road_grip_capture :: proc(editor: ^Editor) {
    if editor == nil do return
    seed_road_capture(editor)
    dirt_edge := -1
    for edge, index in editor.project.road_graph.edges[:editor.project.road_graph.edge_count] {
        if edge.pavement == .Dirt {
            dirt_edge = index
            break
        }
    }
    if dirt_edge < 0 do return
    edge := editor.project.road_graph.edges[dirt_edge]
    point := roads.edge_point(&editor.project.road_graph, edge, .18)
    tangent := roads.edge_tangent(&editor.project.road_graph, edge, .18)
    editor.car.position = {point.x, point.y, point.z}
    editor.car.yaw_radians = math.atan2(tangent.z, tangent.x)
    dirt_grip := roads.pavement_grip(.Dirt)
    drive_surface := vehicles.Car_Drive_Surface {
        longitudinal_grip  = dirt_grip.longitudinal,
        lateral_grip       = dirt_grip.lateral,
        rolling_resistance = dirt_grip.rolling_resistance,
    }
    contacts: [4]particle_systems.Vehicle_Contact
    for _ in 0 ..< 105 {
        ground := terrain.sample_height(&editor.project, 0, editor.car.position.x, editor.car.position.z)
        vehicles.car_drive_step(
            &editor.car_drive,
            &editor.car,
            {throttle = 1, steering = .78},
            ground,
            1.0 / 60,
            drive_surface,
        )
        for index in 0 ..< 4 {
            contacts[index] = {
                position = {editor.car.position.x, editor.car.position.y + .08, editor.car.position.z},
                grounded = true,
                surface  = .Dirt,
            }
        }
        particle_systems.step_vehicle_effects(
            &editor.vehicle_effects,
            1.0 / 60,
            vehicles.car_drive_speed(editor.car_drive),
            editor.car_drive.steering,
            false,
            editor.car_drive.slip_amount,
            contacts,
        )
    }
    for index in 0 ..< editor.vehicle_effects.dust_count {
        editor.vehicle_effects.dust[index].size *= 2.8
    }
    car_physics_teleport(editor)
}

seed_terrain_grip_capture :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.project.road_graph = {}
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    center := half_extent * terrain.DEFAULT_ISLAND_OFFSET
    shore_x := center + half_extent * terrain.DEFAULT_ISLAND_RADIUS
    shore_z := center
    ground := terrain.sample_height(&editor.project, 0, shore_x, shore_z)
    editor.car.position = {shore_x, ground, shore_z}
    editor.car.yaw_radians = math.PI * .5
    sand_grip := terrain.ground_grip(.Sand)
    drive_surface := vehicles.Car_Drive_Surface {
        longitudinal_grip  = sand_grip.longitudinal,
        lateral_grip       = sand_grip.lateral,
        rolling_resistance = sand_grip.rolling_resistance,
    }
    contacts: [4]particle_systems.Vehicle_Contact
    for _ in 0 ..< 105 {
        ground = terrain.sample_height(&editor.project, 0, editor.car.position.x, editor.car.position.z)
        vehicles.car_drive_step(
            &editor.car_drive,
            &editor.car,
            {throttle = 1, steering = .72},
            ground,
            1.0 / 60,
            drive_surface,
        )
        for index in 0 ..< 4 {
            contacts[index] = {
                position = {editor.car.position.x, editor.car.position.y + .08, editor.car.position.z},
                grounded = true,
                surface  = .Sand,
            }
        }
        particle_systems.step_vehicle_effects(
            &editor.vehicle_effects,
            1.0 / 60,
            vehicles.car_drive_speed(editor.car_drive),
            editor.car_drive.steering,
            false,
            editor.car_drive.slip_amount,
            contacts,
        )
    }
    for index in 0 ..< editor.vehicle_effects.dust_count {
        editor.vehicle_effects.dust[index].size *= 2.8
    }
    car_physics_teleport(editor)
}

// terrain_dust_surface maps the terrain classifier's discrete ground band onto
// the particle system's surface vocabulary. Terrain has no dedicated asphalt or
// gravel, so it reuses the existing Dirt/Grass profiles and the new Sand one.
terrain_dust_surface :: proc(surface: terrain.Ground_Surface) -> particle_systems.Dust_Surface {
    switch surface {
    case .Sand:
        return .Sand
    case .Dirt:
        return .Dirt
    case .Grass:
        return .Grass
    }
    return .Grass
}

footstep_surface_from_dust :: proc(surface: particle_systems.Dust_Surface) -> engine_sound.Footstep_Surface {
    switch surface {
    case .Asphalt:
        return .Asphalt
    case .Cobblestone:
        return .Cobblestone
    case .Gravel:
        return .Gravel
    case .Dirt:
        return .Dirt
    case .Sand:
        return .Sand
    case .Grass:
        return .Grass
    }
    return .Grass
}

crash_surface_from_dust :: proc(surface: particle_systems.Dust_Surface) -> engine_sound.Crash_Surface {
    switch surface {
    case .Asphalt:
        return .Asphalt
    case .Cobblestone:
        return .Cobblestone
    case .Gravel:
        return .Gravel
    case .Dirt:
        return .Dirt
    case .Sand:
        return .Sand
    case .Grass:
        return .Grass
    }
    return .Dirt
}

ocean_shore_proximity :: proc(editor: ^Editor, x, z: f32) -> f32 {
    if editor == nil do return 1
    sea_level := editor.project.sea_level
    if terrain.sample_height(&editor.project, 0, x, z) < sea_level do return 1
    directions := [8][2]f32 {
        {1, 0},
        {-1, 0},
        {0, 1},
        {0, -1},
        {.707, .707},
        {-.707, .707},
        {.707, -.707},
        {-.707, -.707},
    }
    radii := [3]f32{30, 80, 160}
    proximity := [3]f32{1, .68, .34}
    for ring in 0 ..< len(radii) {
        for direction in directions {
            if terrain.sample_height(
                   &editor.project,
                   0,
                   x + direction[0] * radii[ring],
                   z + direction[1] * radii[ring],
               ) <
               sea_level {
                return proximity[ring]
            }
        }
    }
    return .12
}

tire_roughness_from_dust :: proc(surface: particle_systems.Dust_Surface) -> f32 {
    switch surface {
    case .Asphalt:
        return .12
    case .Cobblestone:
        return .72
    case .Gravel:
        return .9
    case .Dirt:
        return .62
    case .Sand:
        return .48
    case .Grass:
        return .38
    }
    return .38
}

road_car_surface :: proc(
    editor: ^Editor,
    position: roads.Vec3,
) -> (
    particle_systems.Dust_Surface,
    vehicles.Car_Drive_Surface,
) {
    dust_surface := particle_systems.Dust_Surface.Grass
    grip := roads.offroad_grip()
    if editor != nil {
        plan := editor_circulation_plan(editor)
        hit := circulation.surface_at(&editor.project.road_graph, plan, position)
        if hit.on_surface {
            grip = roads.pavement_grip(hit.pavement)
            switch hit.pavement {
            case .Asphalt:
                dust_surface = .Asphalt
            case .Gravel:
                dust_surface = .Gravel
            case .Cobblestone:
                dust_surface = .Cobblestone
            case .Dirt:
                dust_surface = .Dirt
            }
        } else {
            // Off pavement the ground itself drives the effect: classify the
            // terrain under the wheel instead of always falling back to Grass.
            ground := terrain.ground_surface_at(&editor.project, 0, position.x, position.z)
            dust_surface = terrain_dust_surface(ground)
            grip = terrain.ground_grip(ground)
        }
    }
    return dust_surface, {
        longitudinal_grip = grip.longitudinal,
        lateral_grip = grip.lateral,
        rolling_resistance = grip.rolling_resistance,
    }
}

seed_city_capture :: proc(editor: ^Editor) {
    if editor == nil do return
    seed_road_capture(editor)
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    radius := f32(76)
    _ = architecture.city_density_stamp(&editor.project.city_density, center - 92, center + 34, radius, .28, .72)
    _ = architecture.city_density_stamp(&editor.project.city_density, center, center + 34, radius, .58, .72)
    _ = architecture.city_density_stamp(&editor.project.city_density, center + 92, center + 34, radius, 1, .72)
    bounds := architecture.City_Bounds{center - 190, center - 70, center + 190, center + 140, true}
    plan := architecture.city_plan_density(&editor.project, &editor.project.city_density, bounds)
    _ = architecture.city_commit_plan(&editor.project, &editor.project.city_density, bounds, &plan)
    // Give the architectural capture a restrained, deterministic vine pass so
    // surface attachment is visible without requiring interactive brush input.
    for structure in editor.project.structures[:editor.project.structure_count] {
        if structure.kind != .Architecture || structure.height > 52 do continue
        _ = architecture.city_density_stamp(
            &editor.project.climbing_leaf_density,
            structure.center_x,
            structure.center_z,
            max(structure.width, structure.depth) * .42,
            .72,
            .68,
        )
    }
    authoring_select_tool(editor, .Building)
    editor.structure_selected = -1
}

seed_default_island_towns :: proc(editor: ^Editor) {
    if editor == nil do return
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    // Put each settlement across the island from its runway apron. A short
    // cobblestone frontage gives the ordinary painted-density parcel planner
    // the same street skeleton it receives from an authored road.
    for sign, island_index in terrain.DEFAULT_ISLAND_SIGNS {
        island_center := sign * half_extent * terrain.DEFAULT_ISLAND_OFFSET
        town_z := island_center + sign * terrain.DEFAULT_TOWN_OFFSET
        seed := u32(0xA71D3 + island_index * 0x31F29)
        road_start_x, road_finish_x := island_center - 78, island_center + 78
        road_start_y := terrain.sample_height(&editor.project, 0, road_start_x, town_z)
        road_finish_y := terrain.sample_height(&editor.project, 0, road_finish_x, town_z)
        road_start := roads.add_node(&editor.project.road_graph, {road_start_x, road_start_y, town_z}, 0)
        road_finish := roads.add_node(&editor.project.road_graph, {road_finish_x, road_finish_y, town_z}, 0)
        if road_start >= 0 && road_finish >= 0 {
            _ = roads.add_straight_edge(&editor.project.road_graph, road_start, road_finish, 5.5, 1.4, .Cobblestone)
        }

        town_bounds := architecture.City_Bounds {
            island_center - 108,
            town_z - 68,
            island_center + 108,
            town_z + 68,
            true,
        }
        _ = architecture.city_density_stamp(&editor.project.city_density, island_center, town_z, 82, .20, .70)
        plan := architecture.city_plan_density(&editor.project, &editor.project.city_density, town_bounds, seed)
        first_structure := editor.project.structure_count
        _ = architecture.city_commit_plan(&editor.project, &editor.project.city_density, town_bounds, &plan)
        for structure in editor.project.structures[first_structure:editor.project.structure_count] {
            if structure.kind != .Architecture || structure.height > 60 do continue
            _ = architecture.city_density_stamp(
                &editor.project.climbing_leaf_density,
                structure.center_x,
                structure.center_z,
                max(structure.width, structure.depth) * .56,
                .78,
                .68,
            )
        }
    }
    editor.architecture_node_mode = true
}

seed_default_island_marinas :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.default_marina_count = 0
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    island_radius := half_extent * terrain.DEFAULT_ISLAND_RADIUS
    diagonal := f32(.70710678)
    for sign, island_index in terrain.DEFAULT_ISLAND_SIGNS {
        center := sign * half_extent * terrain.DEFAULT_ISLAND_OFFSET
        // Move from the island center toward the channel between the islands.
        // The site search then rotates the full marina footprint to match the
        // locally sampled shoreline rather than assuming a circular coast.
        shoreline_anchor := markov_marina_find_shoreline_along_ray(
            &editor.project,
            {center, center},
            {-sign * diagonal, -sign * diagonal},
            island_radius * 1.8,
        )
        site, suitability := markov_marina_find_world_site(&editor.project, shoreline_anchor)
        if suitability <= 0 do continue
        seed := u32(0x4d415249 + island_index * 0x9e3779b9)
        plan, _ := markov_marina_generate_valid_for_site(seed, &site)
        if !plan.valid do continue
        editor.default_marinas[editor.default_marina_count] = plan
        editor.default_marina_count += 1
    }
}

configure_building_capture_camera :: proc(editor: ^Editor, target_arg: string = "") -> bool {
    if editor == nil do return false
    bougainvillea_seed_override := -1
    ground_level_capture := false
    ordinal_arg := target_arg
    ground_prefix := "ground-"
    if len(target_arg) > len(ground_prefix) && target_arg[:len(ground_prefix)] == ground_prefix {
        ground_level_capture = true
        ordinal_arg = target_arg[len(ground_prefix):]
    }
    bougainvillea_prefix := "bougainvillea-"
    if len(target_arg) > len(bougainvillea_prefix) && target_arg[:len(bougainvillea_prefix)] == bougainvillea_prefix {
        parsed, ok := strconv.parse_int(target_arg[len(bougainvillea_prefix):])
        if ok && parsed >= 0 && parsed <= 0xffffffff {
            bougainvillea_seed_override = int(parsed)
        }
    }
    if target_arg == "cypress" {
        min_x, max_x := f32(1e9), f32(-1e9)
        min_z, max_z := f32(1e9), f32(-1e9)
        buildings := 0
        for structure in editor.project.structures[:editor.project.structure_count] {
            if structure.kind != .Architecture || structure.height > 60 do continue
            min_x = min(min_x, structure.center_x)
            max_x = max(max_x, structure.center_x)
            min_z = min(min_z, structure.center_z)
            max_z = max(max_z, structure.center_z)
            buildings += 1
        }
        if buildings >= 4 {
            center_x, center_z := (min_x + max_x) * .5, (min_z + max_z) * .5
            road_span := max(max_x - min_x + 36, 160)
            tree_x := center_x + road_span * .42
            tree_z := center_z + (max_z - min_z) * .5 + 7
            tree_y := terrain.sample_height(&editor.project, 0, tree_x, tree_z)
            // The cypress is taller than a façade, so pull the verification
            // camera back and aim through its middle instead of clipping the
            // crown from an eye-level close-up.
            eye_x, eye_z := tree_x - 30, tree_z - 30
            eye_y := terrain.sample_height(&editor.project, 0, eye_x, eye_z) + 4.0
            editor.capture_world_only = true
            editor.architecture_node_mode = true
            editor.editor_camera.distance = 36
            editor.editor_focus = {tree_x, tree_y + 20.0, tree_z}
            editor.camera_pose = third_person.camera_look_at({eye_x, eye_y, eye_z}, editor.editor_focus)
            return true
        }
    }
    target_index := -1
    // Seed-matrix captures use the same close façade as the long-running
    // architectural validation shot, changing only the plant seed. This keeps
    // palette and habit comparisons from being confounded by camera/building
    // selection.
    requested_ordinal := bougainvillea_seed_override >= 0 ? 4 : -1
    if ordinal_arg != "" && bougainvillea_seed_override < 0 {
        parsed, ok := strconv.parse_int(ordinal_arg)
        if ok && parsed >= 0 do requested_ordinal = int(parsed)
    }

    // Explicit targets use a stable zero-based ordinal over architecture
    // structures, independent of roads, foliage, and other authored items.
    if requested_ordinal >= 0 {
        ordinal := 0
        for structure, index in editor.project.structures[:editor.project.structure_count] {
            if structure.kind != .Architecture do continue
            if ordinal == requested_ordinal {
                target_index = index
                break
            }
            ordinal += 1
        }
    }

    // Auto-target a normal building on the camera-facing edge of the town.
    // That keeps intervening rows out of the shot as generated layouts change.
    if target_index < 0 {
        center_x, building_count := f32(0), 0
        for structure in editor.project.structures[:editor.project.structure_count] {
            if structure.kind != .Architecture || structure.height > 60 do continue
            center_x += structure.center_x
            building_count += 1
        }
        if building_count > 0 do center_x /= f32(building_count)
        best_score := -f32(1e30)
        for structure, index in editor.project.structures[:editor.project.structure_count] {
            if structure.kind != .Architecture || structure.height > 60 do continue
            score := structure.center_z - abs(structure.center_x - center_x) * .16 + structure.width * .08
            if score > best_score {
                best_score = score
                target_index = index
            }
        }
    }
    if target_index < 0 do return false

    building := editor.project.structures[target_index]
    if bougainvillea_seed_override >= 0 {
        editor.capture_bougainvillea_seed_enabled = true
        editor.capture_bougainvillea_structure_id = building.id
        editor.capture_bougainvillea_seed = u32(bougainvillea_seed_override)
    }
    facade_x, facade_z := -math.sin(building.rotation), math.cos(building.rotation)
    // Move the architectural capture into the lane so balconies and laundry
    // read as the subject instead of small details in a town-wide shot.
    camera_distance := building.depth * .5 + max(f32(9), building.height * .54)
    if ground_level_capture {
        camera_distance = building.depth * .5 + max(f32(10), building.width * .48)
    }
    minimum_distance := building.depth * .5 + 6
    for camera_distance > minimum_distance {
        dry_approach := true
        facade_distance := building.depth * .5 + .75
        for sample in 1 ..= 12 {
            sample_distance := facade_distance + (camera_distance - facade_distance) * f32(sample) / 12
            sample_x := building.center_x + facade_x * sample_distance
            sample_z := building.center_z + facade_z * sample_distance
            sample_ground := terrain.sample_height(&editor.project, 0, sample_x, sample_z)
            if sample_ground <= editor.project.sea_level + .35 {
                dry_approach = false
                break
            }
        }
        if dry_approach do break
        camera_distance = max(minimum_distance, camera_distance - 4)
    }
    eye_x := building.center_x + facade_x * camera_distance
    eye_z := building.center_z + facade_z * camera_distance
    // A modest lateral offset reveals the balcony depth instead of flattening
    // every railing into a line across the window.
    side_offset := ground_level_capture ? min(f32(5), building.width * .16) : min(f32(8), building.width * .24)
    eye_x += facade_z * side_offset
    eye_z -= facade_x * side_offset
    eye_y := terrain.sample_height(&editor.project, 0, eye_x, eye_z) + 3.2
    target_y :=
        ground_level_capture ? building.base_y + 2.4 : building.base_y + clamp(building.height * .50, f32(7), f32(18))
    editor.capture_world_only = true
    // Keep the procedural street dressing in the architectural capture so
    // façades read as a walkable Mediterranean neighborhood, not isolated
    // blocks floating on a blank field.
    editor.architecture_node_mode = true
    // The pose is explicit; keep the editor-orbit distance low only so its
    // near-clip heuristic does not cut away the street under this camera.
    editor.editor_camera.distance = min(camera_distance, f32(36))
    editor.editor_focus = {building.center_x, target_y, building.center_z}
    editor.camera_pose = third_person.camera_look_at({eye_x, eye_y, eye_z}, editor.editor_focus)
    return true
}

architecture_paint_commit :: proc(editor: ^Editor) {
    if editor == nil || !editor.architecture_painting do return
    structure_history_push_undo(editor)
    rebuild_bounds := architecture.city_bounds_expand(editor.architecture_dirty_bounds, 48)
    _ = architecture.city_commit_plan(
        &editor.project,
        &editor.architecture_density_preview,
        rebuild_bounds,
        &editor.architecture_preview_plan,
    )
    // Reconstruct the full transient parcel/alley cache after the bounded
    // paint commit so previously generated districts remain visible.
    architecture_regenerate_all(editor)
    editor.architecture_painting = false
    editor.architecture_preview_plan = {}
    editor.architecture_dirty_bounds = {}
}

architecture_paint_refresh_preview :: proc(editor: ^Editor) {
    if editor == nil do return
    rebuild_bounds := architecture.city_bounds_expand(editor.architecture_dirty_bounds, 48)
    editor.architecture_preview_plan = architecture.city_plan_density(
        &editor.project,
        &editor.architecture_density_preview,
        rebuild_bounds,
    )
}

architecture_paint_stamp :: proc(editor: ^Editor, world_x, world_z: f32, erase: bool, refresh: bool = true) {
    if editor == nil do return
    bounds := architecture.city_density_stamp(
        &editor.architecture_density_preview,
        world_x,
        world_z,
        editor.architecture_brush_radius,
        editor.architecture_brush_strength * .08,
        editor.architecture_brush_hardness,
        erase,
    )
    editor.architecture_dirty_bounds = architecture.city_bounds_union(editor.architecture_dirty_bounds, bounds)
    if refresh do architecture_paint_refresh_preview(editor)
}

architecture_paint_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || !editor.architecture_paint_mode do return
    if !cursor_hit {
        if rl.IsMouseButtonReleased(.LEFT) || rl.IsMouseButtonReleased(.RIGHT) do architecture_paint_commit(editor)
        return
    }
    pressed := rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT)
    down := rl.IsMouseButtonDown(.LEFT) || rl.IsMouseButtonDown(.RIGHT)
    if pressed {
        editor.architecture_painting = true
        editor.architecture_density_preview = editor.project.city_density
        editor.architecture_preview_plan = {}
        editor.architecture_dirty_bounds = {}
        editor.architecture_last_x, editor.architecture_last_z = world_x, world_z
        architecture_paint_stamp(editor, world_x, world_z, rl.IsMouseButtonDown(.RIGHT))
    }
    if editor.architecture_painting && down && !pressed {
        dx, dz := world_x - editor.architecture_last_x, world_z - editor.architecture_last_z
        distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
        step := max(editor.architecture_brush_radius * .22, terrain.BASE_CELL_SIZE * .35)
        stamps := max(int(math.ceil(f64(distance / step))), 1)
        for stamp in 1 ..= stamps {
            amount := f32(stamp) / f32(stamps)
            x := editor.architecture_last_x + dx * amount
            z := editor.architecture_last_z + dz * amount
            architecture_paint_stamp(editor, x, z, rl.IsMouseButtonDown(.RIGHT), false)
        }
        architecture_paint_refresh_preview(editor)
        editor.architecture_last_x, editor.architecture_last_z = world_x, world_z
    }
    if editor.architecture_painting && (rl.IsMouseButtonReleased(.LEFT) || rl.IsMouseButtonReleased(.RIGHT)) {
        architecture_paint_commit(editor)
    }
}

marina_brush_refresh_preview :: proc(editor: ^Editor, world_x, world_z: f32, reroll: bool) {
    if editor == nil do return
    if reroll {
        editor.marina_preview_variation += 1
    } else {
        editor.marina_preview_variation = 0
    }
    shoreline := marina.Vec2{world_x, world_z}
    site, suitability := markov_marina_find_world_site(&editor.project, shoreline)
    editor.marina_brush_suitability = suitability
    editor.marina_brush_attempts = 0
    editor.marina_preview_x, editor.marina_preview_z = world_x, world_z
    editor.marina_preview_valid = false
    editor.marina_preview_plan = {}
    if suitability < MARINA_BRUSH_MINIMUM_SUITABILITY {
        editor.marina_brush_status = .Unsuitable
        return
    }
    seed := u32(abs(int(world_x * 17))) ~ u32(abs(int(world_z * 31))) ~ editor.marina_preview_variation * 0x85ebca6b
    candidate, attempts := markov_marina_generate_valid_for_site(seed, &site)
    editor.marina_brush_attempts = attempts
    if !candidate.valid {
        editor.marina_brush_status = .No_Valid_Layout
        return
    }
    editor.marina_preview_plan = candidate
    editor.marina_preview_valid = true
    editor.marina_brush_status = .Preview
}

marina_brush_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || !editor.marina_paint_mode || !cursor_hit do return
    dx, dz := world_x - editor.marina_preview_x, world_z - editor.marina_preview_z
    refresh_distance := editor.marina_brush_radius * .22
    moved := dx * dx + dz * dz > refresh_distance * refresh_distance
    if !editor.marina_preview_valid && editor.marina_brush_status == .Idle || moved {
        marina_brush_refresh_preview(editor, world_x, world_z, false)
    }
    if rl.IsMouseButtonPressed(.RIGHT) {
        marina_brush_refresh_preview(editor, editor.marina_preview_x, editor.marina_preview_z, true)
        return
    }
    if !rl.IsMouseButtonPressed(.LEFT) || !editor.marina_preview_valid do return
    structure_history_push_undo(editor)
    editor.marina_authored_plan = editor.marina_preview_plan
    editor.marina_authored = true
    editor.marina_preview_valid = false
    editor.project.revision += 1
    editor.marina_brush_status = .Placed
}

farm_generation_score :: proc(plan: ^farmland.Plan) -> f32 {
    if plan == nil || !plan.valid || plan.parcel_count <= 0 do return 0
    crops: [5]bool
    smallest_area, largest_area := 1 << 30, 0
    elongated := 0
    for parcel in plan.parcels[:plan.parcel_count] {
        crops[int(parcel.crop)] = true
        width, depth := parcel.max_x - parcel.min_x, parcel.max_z - parcel.min_z
        area := width * depth
        smallest_area = min(smallest_area, area)
        largest_area = max(largest_area, area)
        if max(width, depth) >= min(width, depth) * 2 do elongated += 1
    }
    crop_count := 0
    for present in crops do if present do crop_count += 1
    diversity := f32(crop_count) / f32(len(crops))
    balance := f32(smallest_area) / f32(max(largest_area, 1))
    shape_mix := 1 - math.abs(f32(elongated) / f32(plan.parcel_count) - .35)
    return clamp(diversity * .46 + balance * .24 + shape_mix * .30, 0, 1)
}

farm_site_score :: proc(editor: ^Editor, origin_x, origin_z, yaw: f32) -> (f32, bool) {
    if editor == nil do return 0, false
    cosine, sine := math.cos(yaw), math.sin(yaw)
    land, clear, samples := 0, 0, 0
    slope_total := f32(0)
    for z_index in -3 ..= 3 {
        for x_index in -4 ..= 4 {
            local_x := f32(x_index) / 4 * f32(farmland.GRID_WIDTH) * farmland.CELL_METERS * .48
            local_z := f32(z_index) / 3 * f32(farmland.GRID_HEIGHT) * farmland.CELL_METERS * .48
            x := origin_x + local_x * cosine - local_z * sine
            z := origin_z + local_x * sine + local_z * cosine
            height := terrain.sample_height(&editor.project, 0, x, z)
            if height > editor.project.sea_level + .35 do land += 1
            blocked := terrain.structure_index_at(&editor.project, x, z) >= 0
            for farm in editor.farms[:editor.farm_count] {
                farm_dx, farm_dz := x - farm.origin_x, z - farm.origin_z
                if farm_dx * farm_dx + farm_dz * farm_dz < 68 * 68 {
                    blocked = true
                    break
                }
            }
            pavement := roads.pavement_at(&editor.project.road_graph, {x, height, z})
            if !blocked && !pavement.on_surface do clear += 1
            sample := f32(4)
            rise_x :=
                terrain.sample_height(&editor.project, 0, x + sample, z) -
                terrain.sample_height(&editor.project, 0, x - sample, z)
            rise_z :=
                terrain.sample_height(&editor.project, 0, x, z + sample) -
                terrain.sample_height(&editor.project, 0, x, z - sample)
            slope_total += f32(math.sqrt(f64(rise_x * rise_x + rise_z * rise_z))) / (sample * 2)
            samples += 1
        }
    }
    land_ratio := f32(land) / f32(samples)
    clear_ratio := f32(clear) / f32(samples)
    average_slope := slope_total / f32(samples)
    slope_score := 1 - clamp((average_slope - .04) / .34, 0, 1)
    score := land_ratio * .48 + clear_ratio * .27 + slope_score * .25
    valid := land_ratio >= .94 && clear_ratio >= .88 && average_slope <= .34
    return clamp(score, 0, 1), valid
}

farm_stamp_update_preview :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || !editor.farm_paint_mode || editor.in_map || !cursor_hit {
        if editor != nil do editor.farm_preview_valid = false
        return
    }
    snap := f32(8)
    preview_x := f32(math.round(f64(world_x / snap))) * snap
    preview_z := f32(math.round(f64(world_z / snap))) * snap
    if preview_x != editor.farm_preview_x || preview_z != editor.farm_preview_z {
        editor.farm_preview_seed_offset = 0
    }
    if preview_x == editor.farm_preview_x &&
       preview_z == editor.farm_preview_z &&
       editor.farm_preview_revision == editor.project.revision {
        return
    }
    editor.farm_preview_x = preview_x
    editor.farm_preview_z = preview_z
    editor.farm_preview_revision = editor.project.revision
    editor.farm_preview_valid = false
    editor.farm_preview_score = 0
    best_score := f32(-1)
    base_seed :=
        u32(abs(int(preview_x * 17))) ~
        u32(abs(int(preview_z * 31))) ~
        u32(editor.project.revision * 0x9e3779b9) ~
        editor.farm_preview_seed_offset * u32(0x27d4eb2d)
    for orientation in 0 ..< 8 {
        yaw := f32(orientation) * math.PI / 8 - math.PI * .5
        site_score, site_valid := farm_site_score(editor, preview_x, preview_z, yaw)
        if !site_valid do continue
        for variant in 0 ..< 2 {
            seed := base_seed ~ u32(orientation + 1) * u32(0x85ebca6b) ~ u32(variant + 1) * u32(0xc2b2ae35)
            candidate := farmland.generate(seed, context.temp_allocator)
            generation_score := farm_generation_score(&candidate)
            combined := site_score * .72 + generation_score * .28
            if combined <= best_score do continue
            best_score = combined
            editor.farm_preview = {
                plan     = candidate,
                origin_x = preview_x,
                origin_z = preview_z,
                yaw      = yaw,
            }
            editor.farm_preview_valid = true
            editor.farm_preview_score = combined
            editor.farm_preview_site_score = site_score
            editor.farm_preview_generation_score = generation_score
        }
    }
}

farm_brush_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || !editor.farm_paint_mode || !cursor_hit do return
    if rl.IsMouseButtonPressed(.RIGHT) {
        editor.farm_preview_seed_offset += 1
        editor.farm_preview_revision = 0
        editor.farm_preview_valid = false
        return
    }
    if !rl.IsMouseButtonPressed(.LEFT) || editor.farm_count >= FARM_INSTANCE_CAPACITY || !editor.farm_preview_valid {
        return
    }
    structure_history_push_undo(editor)
    editor.farms[editor.farm_count] = editor.farm_preview
    editor.farm_count += 1
    editor.project.revision += 1
    editor.farm_preview_valid = false
    editor.farm_preview_seed_offset = 0
}

climbing_leaf_paint_stamp :: proc(editor: ^Editor, world_x, world_z: f32, erase: bool) {
    if editor == nil do return
    _ = architecture.city_density_stamp(
        &editor.project.climbing_leaf_density,
        world_x,
        world_z,
        editor.climbing_leaf_brush_radius,
        editor.climbing_leaf_brush_strength * .08,
        editor.climbing_leaf_brush_hardness,
        erase,
    )
    editor.project.revision += 1
}

climbing_leaf_paint_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || !editor.climbing_leaf_paint_mode do return
    if !cursor_hit {
        if rl.IsMouseButtonReleased(.LEFT) || rl.IsMouseButtonReleased(.RIGHT) do editor.climbing_leaf_painting = false
        return
    }
    pressed := rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT)
    down := rl.IsMouseButtonDown(.LEFT) || rl.IsMouseButtonDown(.RIGHT)
    if pressed {
        structure_history_push_undo(editor)
        editor.climbing_leaf_painting = true
        editor.climbing_leaf_last_x, editor.climbing_leaf_last_z = world_x, world_z
        climbing_leaf_paint_stamp(editor, world_x, world_z, rl.IsMouseButtonDown(.RIGHT))
    }
    if editor.climbing_leaf_painting && down && !pressed {
        dx, dz := world_x - editor.climbing_leaf_last_x, world_z - editor.climbing_leaf_last_z
        distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
        step := max(editor.climbing_leaf_brush_radius * .22, terrain.BASE_CELL_SIZE * .35)
        stamps := max(int(math.ceil(f64(distance / step))), 1)
        for stamp in 1 ..= stamps {
            amount := f32(stamp) / f32(stamps)
            x := editor.climbing_leaf_last_x + dx * amount
            z := editor.climbing_leaf_last_z + dz * amount
            climbing_leaf_paint_stamp(editor, x, z, rl.IsMouseButtonDown(.RIGHT))
        }
        editor.climbing_leaf_last_x, editor.climbing_leaf_last_z = world_x, world_z
    }
    if editor.climbing_leaf_painting && (rl.IsMouseButtonReleased(.LEFT) || rl.IsMouseButtonReleased(.RIGHT)) {
        editor.climbing_leaf_painting = false
    }
}

structure_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || editor.tool != .Structure do return
    if imgui_captures_keyboard() do return
    cell := editor.project.levels[0].cell_size
    if control_key_down() && rl.IsKeyPressed(.Z) {
        structure_undo(editor)
        editor.structure_placing = false
        editor.structure_moving = false
        return
    }
    if control_key_down() && rl.IsKeyPressed(.Y) {
        structure_redo(editor)
        editor.structure_placing = false
        editor.structure_moving = false
        return
    }
    if rl.IsKeyPressed(.BACKSPACE) && editor.structure_selected >= 0 && !editor.structure_placing {
        structure_history_push_undo(editor)
        terrain.remove_structure(&editor.project, editor.structure_selected)
        editor.structure_selected = -1
    }
    if control_key_down() && rl.IsKeyPressed(.D) && editor.structure_selected >= 0 {
        structure_history_push_undo(editor)
        index := terrain.duplicate_structure(&editor.project, editor.structure_selected, cell * 2, cell * 2)
        if index >= 0 do editor.structure_selected = index
    }
    if rl.IsKeyPressed(.R) {
        if editor.structure_placing {
            editor.structure_preview.rotation += math.PI / 12
        } else if editor.structure_selected >= 0 {
            structure_history_push_undo(editor)
            editor.project.structures[editor.structure_selected].rotation += math.PI / 12
            editor.project.revision += 1
        }
    }
    if !cursor_hit {
        if rl.IsMouseButtonReleased(.LEFT) || rl.IsMouseButtonReleased(.RIGHT) {
            editor.structure_placing = false
            editor.structure_moving = false
        }
        return
    }
    if rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) {
        index := rl.IsMouseButtonPressed(.LEFT) ? terrain.structure_index_at(&editor.project, world_x, world_z) : -1
        if index >= 0 {
            editor.structure_selected = index
            editor.structure_moving = true
            structure_history_push_undo(editor)
            editor.structure_grab_offset_x = editor.project.structures[index].center_x - world_x
            editor.structure_grab_offset_z = editor.project.structures[index].center_z - world_z
        } else {
            editor.structure_selected = -1
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
            editor.structure_force_box = control_key_down()
            editor.structure_cliff_mode = rl.IsMouseButtonPressed(.RIGHT)
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
        if rl.IsMouseButtonReleased(.LEFT) || rl.IsMouseButtonReleased(.RIGHT) {
            structure_history_push_undo(editor)
            index := structure_commit_placement(editor, world_x, world_z)
            if index >= 0 do editor.structure_selected = index
            editor.structure_placing = false
        }
    } else if editor.structure_moving && editor.structure_selected >= 0 {
        structure := &editor.project.structures[editor.structure_selected]
        structure.center_x = structure_editor_snap(world_x + editor.structure_grab_offset_x, editor)
        structure.center_z = structure_editor_snap(world_z + editor.structure_grab_offset_z, editor)
        structure_update_base(editor, structure)
        if rl.IsMouseButtonReleased(.LEFT) do editor.structure_moving = false
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
            editor.structure_preview.height = max(cell, editor.structure_preview.height + wheel * cell * 2)
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
                structure.height = max(cell, structure.height + wheel * cell * 2)
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

project_point :: proc(x, z, height: f32, center: rl.Vector2, scale: f32) -> rl.Vector2 {
    return {center.x + (x - z) * scale, center.y + (x + z) * scale * .46 - height * scale}
}

Perspective_Camera :: struct {
    position, right, up, forward: third_person.Vec3,
    focal_length:                 f32,
}

Screen_Point :: struct {
    position: rl.Vector2,
    depth:    f32,
    visible:  bool,
}

player_ground_normal :: proc(editor: ^Editor, position: third_person.Vec3) -> third_person.Vec3 {
    if editor == nil do return third_person.Vec3{0, 1, 0}
    SAMPLE_DISTANCE :: f32(.35)
    height_left := terrain.sample_height(&editor.project, 0, position.x - SAMPLE_DISTANCE, position.z)
    height_right := terrain.sample_height(&editor.project, 0, position.x + SAMPLE_DISTANCE, position.z)
    height_back := terrain.sample_height(&editor.project, 0, position.x, position.z - SAMPLE_DISTANCE)
    height_front := terrain.sample_height(&editor.project, 0, position.x, position.z + SAMPLE_DISTANCE)
    return linalg.normalize0(
        third_person.Vec3{height_left - height_right, SAMPLE_DISTANCE * 2, height_back - height_front},
    )
}

shape_flight_axis :: proc(value: f32) -> f32 {
    dead_zone := f32(.16)
    magnitude := math.abs(value)
    if magnitude <= dead_zone do return 0
    return math.sign(value) * clamp((magnitude - dead_zone) / (1 - dead_zone), 0, 1)
}

gamepad_axis :: proc(axis: rl.Gamepad_Axis) -> f32 {
    if !rl.GamepadAvailable() do return 0
    return shape_flight_axis(rl.GetGamepadAxis(axis))
}

gamepad_pressed :: proc(button: rl.Gamepad_Button) -> bool {
    return rl.GamepadAvailable() && rl.IsGamepadButtonPressed(button)
}

gamepad_down :: proc(button: rl.Gamepad_Button) -> bool {
    return rl.GamepadAvailable() && rl.IsGamepadButtonDown(button)
}

Input_Action :: enum {
    Pause,
    Jump,
    Run,
    Interact,
    Camera_Reset,
    Vehicle_Reset,
    Handbrake,
    Menu_Accept,
    Menu_Cancel,
}

input_action_pressed :: proc(action: Input_Action) -> bool {
    switch action {
    case .Pause:
        return (!shift_key_down() && rl.IsKeyPressed(.ESCAPE)) || gamepad_pressed(.Start)
    case .Jump:
        return rl.IsKeyPressed(.SPACE) || gamepad_pressed(.South)
    case .Run:
        return rl.IsKeyPressed(.LEFT_SHIFT) || rl.IsKeyPressed(.RIGHT_SHIFT) || gamepad_pressed(.North)
    case .Interact:
        return rl.IsKeyPressed(.F) || gamepad_pressed(.West)
    case .Camera_Reset:
        return rl.IsKeyPressed(.C) || gamepad_pressed(.South)
    case .Vehicle_Reset:
        return rl.IsKeyPressed(.R) || gamepad_pressed(.North)
    case .Menu_Accept:
        return rl.IsKeyPressed(.ENTER) || gamepad_pressed(.South)
    case .Menu_Cancel:
        return (!shift_key_down() && rl.IsKeyPressed(.ESCAPE)) || gamepad_pressed(.East)
    case .Handbrake:
        return rl.IsKeyPressed(.SPACE) || gamepad_pressed(.Right_Shoulder)
    }
    return false
}

input_action_down :: proc(action: Input_Action) -> bool {
    #partial switch action {
    case .Jump:
        return rl.IsKeyDown(.SPACE) || gamepad_down(.South)
    case .Handbrake:
        return rl.IsKeyDown(.SPACE) || gamepad_down(.Right_Shoulder)
    case .Run:
        return shift_key_down() || gamepad_down(.North)
    }
    return input_action_pressed(action)
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
        now_seconds      = rl.GetTime(),
        controller_found = rl.GamepadAvailable(),
    }
    mouse_delta := rl.GetMouseDelta()
    sample.mouse_activity =
        math.abs(mouse_delta.x) > 1.5 ||
        math.abs(mouse_delta.y) > 1.5 ||
        math.abs(rl.GetMouseWheelMove()) > .01 ||
        rl.IsMouseButtonPressed(.LEFT) ||
        rl.IsMouseButtonPressed(.RIGHT) ||
        rl.IsMouseButtonPressed(.MIDDLE)
    for key in rl.KeyboardKey {
        if key == .COUNT do continue
        if rl.IsKeyPressed(key) {
            sample.keyboard_activity = true
            break
        }
    }
    if sample.controller_found {
        for button in rl.Gamepad_Button {
            if button == .Count do continue
            if rl.IsGamepadButtonDown(button) {
                sample.button_activity = true
                break
            }
        }
        sample.axes = {
            rl.GetGamepadAxis(.Left_X),
            rl.GetGamepadAxis(.Left_Y),
            rl.GetGamepadAxis(.Right_X),
            rl.GetGamepadAxis(.Right_Y),
            rl.GetGamepadAxis(.Left_Trigger),
            rl.GetGamepadAxis(.Right_Trigger),
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
    if editor == nil || !editor.in_map do return
    if editor.vehicle_paint_scene {
        set_pointer_locked(false)
        _ = sdl.ShowCursor()
    } else if editor.console.open || pause_menu_is_open(editor) {
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

postale_spawn_position :: proc(editor: ^Editor) -> flight.Vec3 {
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    x := half_extent * terrain.DEFAULT_ISLAND_OFFSET + half_extent * terrain.DEFAULT_RUNWAY_SPAWN_OFFSET
    z := half_extent * terrain.DEFAULT_ISLAND_OFFSET
    ground := postale_game.drivable_surface_height(
        terrain.sample_height(&editor.project, 0, x, z),
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

@(no_instrumentation)
postale_vertex_world :: #force_inline proc(
    runtime: ^postale_game.Runtime,
    position: [3]f32,
    scale: f32,
) -> third_person.Vec3 {
    body := runtime.body
    return {
        body.position.x +
        body.basis.right.x * position[0] * scale +
        body.basis.up.x * position[1] * scale -
        body.basis.forward.x * position[2] * scale,
        body.position.y +
        body.basis.right.y * position[0] * scale +
        body.basis.up.y * position[1] * scale -
        body.basis.forward.y * position[2] * scale,
        body.position.z +
        body.basis.right.z * position[0] * scale +
        body.basis.up.z * position[1] * scale -
        body.basis.forward.z * position[2] * scale,
    }
}

@(no_instrumentation)
postale_normal_world :: #force_inline proc(runtime: ^postale_game.Runtime, normal: [3]f32) -> third_person.Vec3 {
    basis := runtime.body.basis
    return {
        basis.right.x * normal[0] + basis.up.x * normal[1] - basis.forward.x * normal[2],
        basis.right.y * normal[0] + basis.up.y * normal[1] - basis.forward.y * normal[2],
        basis.right.z * normal[0] + basis.up.z * normal[1] - basis.forward.z * normal[2],
    }
}

aircraft_camera_target :: proc(editor: ^Editor) -> chase_camera.Target {
    body := aircraft_render_body(editor)
    if editor.aircraft.active != .Postale {
        return {
            position = body.position,
            basis = body.basis,
            airspeed = linalg.length(body.velocity),
            roll_input = editor.flight_control.roll,
            grounded = editor.libellula.grounded,
        }
    }
    return {
        position        = body.position,
        basis           = body.basis,
        airspeed        = editor.postale.telemetry.airspeed,
        roll_input      = editor.flight_control.roll,
        grounded        = editor.postale.grounded,
        // The Postale's broad parasol wing needs a low, long-lens-like rear
        // view. The generic close/high framing flattened it into a top-down
        // silhouette and made the aircraft read as a toy.
        follow_distance = 12.5,
        follow_height   = 3.35,
        focus_height    = .65,
    }
}

aircraft_render_body :: proc(editor: ^Editor) -> flight.Body_State {
    body := active_aircraft_body(editor)^
    if !editor.aircraft_previous_body_valid do return body
    alpha := f32(editor.aircraft_fixed_accumulator / AIRCRAFT_FIXED_STEP)
    previous := editor.aircraft_previous_body
    result := body
    result.position = linalg.lerp(previous.position, body.position, alpha)
    result.velocity = linalg.lerp(previous.velocity, body.velocity, alpha)
    result.angular_velocity = linalg.lerp(previous.angular_velocity, body.angular_velocity, alpha)
    result.basis = flight.orthonormalize({
        forward = linalg.lerp(previous.basis.forward, body.basis.forward, alpha),
        up      = linalg.lerp(previous.basis.up, body.basis.up, alpha),
    })
    return result
}

@(no_instrumentation)
active_aircraft_body :: #force_inline proc(editor: ^Editor) -> ^flight.Body_State {
    if editor != nil && editor.aircraft.active != .Postale do return &editor.libellula.body
    if editor == nil do return nil
    return &editor.postale.body
}

active_aircraft_vehicle :: proc(editor: ^Editor) -> ^vehicles.Vehicle {
    if editor == nil do return nil
    slot := vehicles.aircraft_fleet_active(&editor.aircraft)
    if slot == nil do return nil
    return slot.vehicle
}

active_aircraft_throttle :: proc(editor: ^Editor) -> f32 {
    if editor != nil && editor.aircraft.active != .Postale do return editor.libellula.throttle
    if editor == nil do return 0
    return editor.postale.throttle
}

active_aircraft_airspeed :: proc(editor: ^Editor) -> f32 {
    if editor != nil && editor.aircraft.active != .Postale do return linalg.length(editor.libellula.body.velocity)
    if editor == nil do return 0
    return editor.postale.telemetry.airspeed
}

postale_flyby_shake :: proc(editor: ^Editor) -> f32 {
    if editor == nil || editor.aircraft.active != .Postale || editor.postale.grounded || editor.postale.crashed {
        return 0
    }
    speed_strength := clamp((editor.postale.telemetry.airspeed - 32) / 30, 0, 1)
    if speed_strength <= 0 do return 0
    position := editor.postale.body.position
    strongest := f32(0)
    for structure in editor.project.structures[:editor.project.structure_count] {
        longest := max(max(structure.width, structure.depth), structure.height)
        if longest < 18 do continue
        center := flight.Vec3{structure.center_x, structure.base_y + structure.height * .5, structure.center_z}
        extent := flight.Vec3{structure.width * .5, structure.height * .5, structure.depth * .5}
        response_range := 10 + clamp(longest * .08, 2, 18)
        proximity := chase_camera.box_flyby_strength(position, center, extent, structure.rotation, response_range)
        size_strength := clamp((longest - 12) / 48, .25, 1)
        strongest = max(strongest, proximity * size_strength)
    }
    return strongest * speed_strength
}

active_aircraft_ground_clearance :: proc(editor: ^Editor) -> f32 {
    if editor != nil && editor.aircraft.active != .Postale do return editor.libellula.tuning.ground_clearance
    return postale_game.GROUND_CLEARANCE
}

libellula_spawn_position :: proc(editor: ^Editor) -> third_person.Vec3 {
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    x := half_extent * terrain.DEFAULT_ISLAND_OFFSET + half_extent * terrain.DEFAULT_RUNWAY_SPAWN_OFFSET + 12
    z := half_extent * terrain.DEFAULT_ISLAND_OFFSET + 8
    return {x, terrain.sample_height(&editor.project, 0, x, z) + 2.1, z}
}

attendant_spawn_position :: proc(editor: ^Editor, _: third_person.Vec3) -> third_person.Vec3 {
    runway := runway_spawn_position(editor)
    // Keep the kiosk off the active strip, but close enough to be visible from
    // the arrival point. The attendant stands at its open service counter.
    x := runway.x + 5.5
    z := runway.z + 10.5
    return {x, terrain.sample_height(&editor.project, 0, x, z), z}
}

@(no_instrumentation)
libellula_vertex_world :: #force_inline proc(
    runtime: ^libellula_game.Runtime,
    position: [3]f32,
    scale: f32,
) -> third_person.Vec3 {
    body := runtime.body
    return {
        body.position.x +
        body.basis.right.x * position[0] * scale +
        body.basis.up.x * position[1] * scale -
        body.basis.forward.x * position[2] * scale,
        body.position.y +
        body.basis.right.y * position[0] * scale +
        body.basis.up.y * position[1] * scale -
        body.basis.forward.y * position[2] * scale,
        body.position.z +
        body.basis.right.z * position[0] * scale +
        body.basis.up.z * position[1] * scale -
        body.basis.forward.z * position[2] * scale,
    }
}

gerta_spawn_position :: proc(editor: ^Editor) -> third_person.Vec3 {
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    island_center := -half_extent * terrain.DEFAULT_ISLAND_OFFSET
    // Mirror Marta's relationship to the runway on the opposite island.
    x := island_center - half_extent * terrain.DEFAULT_RUNWAY_SPAWN_OFFSET - 5.5
    z := island_center - 10.5
    return {x, terrain.sample_height(&editor.project, 0, x, z), z}
}

attendant_speaker :: proc(_: ^dialogue.Context) -> string { return "MARTA" }
gerta_speaker :: proc(_: ^dialogue.Context) -> string { return "GERTA" }
attendant_menu_text :: proc(_: ^dialogue.Context) -> string {
    return "Ciao. How kann ich vous aider?"
}
gerta_menu_text :: proc(_: ^dialogue.Context) -> string {
    return "Dobar dan. Marta gère l'apron est; what peut faire ihre Schwester pour toi?"
}
attendant_aircraft_text :: proc(_: ^dialogue.Context) -> string {
    return "Which aeroplano soll ich mettre sulla linea?"
}

attendant_context_editor :: proc(ctx: ^dialogue.Context) -> ^Editor {
    if ctx == nil || ctx.data == nil do return nil
    return cast(^Editor)ctx.data
}

attendant_local_news_text :: proc(ctx: ^dialogue.Context) -> string {
    editor := attendant_context_editor(ctx)
    if editor == nil do return "Les isole sono tranquille, ce qui niemals signifie que niemand ist occupé."
    gerta := ctx.resident_index == int(story.Resident.Gerta)
    switch editor.story_state.romance {
    case .Unintroduced:
        if gerta do return "Niko allume die forni avant les mouettes.\nÚltimamente il regarde la lampe est entre deux plateaux."
        return "Iva prépare la lampe del faro muy tôt.\nDue lampi avant alba, réguliers wie una promessa."
    case .First_Letter:
        if gerta do return "Niko hat farina sulle manches, mais zéro sur la boîte de cardamomo.\nFais-en lo que quieras."
        return "Iva ha reçu posta dall'isola west.\nLe phare n'est pas plus lumineux, obwohl sie insiste."
    case .Corresponding:
        if gerta do return "Les tende de la regatta gehen hoch.\nNiko inspecte la blu assez souvent pour appeler ça Wartung."
        return(
            "Le lettere cruzan la baia plus vite que les barche da pesca.\nIva les sigilla encore bene, avant que tu demandes." \
        )
    case .Invitation:
        if editor.story_state.repair == .Repaired {
            if gerta do return "L'aereo de Bojan ist wieder sano.\nHa pulito el asiento passagero, donc ce vol compte."
            return(
                "Iva peut faire la regatta, jetzt que l'ala de Bojan ist réparée.\nElle a contrôlé il meteo dreimal." \
            )
        }
        if gerta do return "L'ala di tela de Bojan braucht lavoro honnête.\nLa spiegazione malhonnête, il l'a déjà fournie."
        return "Iva doit être quelque part oltre il mare.\nL'aereo de Bojan porte encore daylight durch una ala."
    case .Meeting:
        if gerta do return "Iva ist arrivée sana e salva.\nNiko appelle l'extra pane un erreur de contabilità."
        return "Iva dit que la vue sous la tenda blu dell'isola west\nist quasi assez belle pour remplacer sa lampe."
    case .Together:
        if gerta do return "Niko und Iva mandent encore pacchi oltre la baia.\nApparemment, rencontrer qualcuno améliore seulement la posta."
        return "Pane va est, verre de lampe va west.\nSolo il corriere ne sait pas cosa dit la nota de cena."
    }
    return ""
}

attendant_weather_text :: proc(ctx: ^dialogue.Context) -> string {
    editor := attendant_context_editor(ctx)
    if editor == nil do return "Regarde il mare avant de croire irgendeine prévision."
    weather := editor.atmosphere.weather
    wind_speed := f32(math.sqrt(f64(weather.wind[0] * weather.wind[0] + weather.wind[1] * weather.wind[1])))
    gerta := ctx.resident_index == int(story.Resident.Gerta)
    if weather.precipitation > .55 || weather.severity > .72 {
        if gerta do return "Un fronte duro attraversa la baia.\nBleib unter les nuages et laisse la fierté am apron."
        return "La pluie de tempesta approche.\nLe phare travaille; eso ne signifie pas que tu dois le tester."
    }
    if wind_speed > 7 || weather.cloud_cover > .48 {
        if gerta do return "Der vento ist vivant sopra la crête west.\nDonne spazio aux falaises et attends un crosswind au retour."
        return "Nuages cassés und vento ferme sur la baia.\nVolable, si tu laisses l'aria dire l'ultima parola."
    }
    if editor.atmosphere.world_minutes < 6 * 60 || editor.atmosphere.world_minutes > 19 * 60 {
        if gerta do return "Aria nocturna chiara; les lumières de pista verdienen ihr Geld.\nAttenzione alla brume sur il mare oscuro."
        return "La notte ist calme.\nGarde la lampe d'Iva à gauche quando voli verso est."
    }
    if gerta do return "Assez clair pour voir l'isola est vom apron west.\nLa baia ist heute très coopérative."
    return "Vento leggero und mare aperto.\nBuen día pour voler, aunque les mouettes prendront le crédit."
}

marta_menu_set_action :: proc(ctx: ^dialogue.Context, action: Marta_Menu_Action) {
    if ctx == nil || ctx.data == nil do return
    editor := cast(^Editor)ctx.data
    editor.attendant_dialogue_action = action
}

marta_menu_paint :: proc(ctx: ^dialogue.Context) { marta_menu_set_action(ctx, .Paint_Aircraft) }
marta_menu_close :: proc(ctx: ^dialogue.Context) { marta_menu_set_action(ctx, .Close) }

open_attendant_dialogue :: proc(editor: ^Editor, resident: story.Resident = .Marta) {
    if editor == nil || (resident != .Marta && resident != .Gerta) do return
    menu_choices := make([]dialogue.Choice, 5)
    menu_choices[0] = dialogue.choice("Peindre un aeroplano", dialogue.no_next_node, effect = marta_menu_paint)
    menu_choices[1] = dialogue.choice("Choose un aeroplano", 1)
    menu_choices[2] = dialogue.choice("Any novosti locale?", 2)
    menu_choices[3] = dialogue.choice("How va il meteo?", 3)
    menu_choices[4] = dialogue.choice("Niente, grazie", dialogue.no_next_node, effect = marta_menu_close)

    editor.attendant_dialogue_vehicle_choice_count = 0
    aircraft_choices := make([]dialogue.Choice, editor.aircraft.count + 1)
    for slot, index in editor.aircraft.slots[:editor.aircraft.count] {
        aircraft_choices[index] = dialogue.choice(slot.name, dialogue.no_next_node)
        editor.attendant_dialogue_vehicle_choices[index] = slot.kind
        editor.attendant_dialogue_vehicle_choice_count += 1
    }
    aircraft_choices[editor.aircraft.count] = dialogue.choice("Back", 0)
    back_choices := make([]dialogue.Choice, 1)
    back_choices[0] = dialogue.choice("Grazie. Anything else?", 0)

    nodes := make([]dialogue.Node, 4)
    speaker := resident == .Gerta ? gerta_speaker : attendant_speaker
    menu_text := resident == .Gerta ? gerta_menu_text : attendant_menu_text
    nodes[0] = dialogue.node("services", menu_text, menu_choices, speaker)
    nodes[1] = dialogue.node("aircraft", attendant_aircraft_text, aircraft_choices, speaker)
    nodes[2] = dialogue.node("local-news", attendant_local_news_text, back_choices, speaker)
    nodes[3] = dialogue.node("weather", attendant_weather_text, back_choices, speaker)
    definition := new(dialogue.Definition)
    definition^ = {
        id         = resident == .Gerta ? "gerta_services" : "marta_services",
        start_node = 0,
        nodes      = nodes,
    }
    conversation, opened := dialogue.open(
        definition,
        {data = rawptr(editor), location_id = "airfield", resident_index = int(resident)},
    )
    if opened {
        editor.dialogue_resident = resident
        editor.attendant_dialogue = conversation
        editor.attendant_dialogue_open = true
        editor.attendant_dialogue_focus = 0
        editor.attendant_dialogue_action = .None
        game_input.reset_menu_repeat(&editor.runtime_input)
        set_pointer_locked(false)
        _ = sdl.ShowCursor()
    }
}

open_story_dialogue :: proc(editor: ^Editor, resident: story.Resident) -> bool {
    if editor == nil || resident == .Marta || resident == .Gerta do return false
    definition: ^dialogue.Definition
    switch resident {
    case .Niko:
        definition = &editor.story_catalog.niko
    case .Iva:
        definition = &editor.story_catalog.iva
    case .Bojan:
        definition = &editor.story_catalog.bojan
    case .Zora:
        definition = &editor.story_catalog.zora
    case .Marta, .Gerta:
        return false
    }
    conversation, opened := dialogue.open(definition, {
        data           = rawptr(&editor.story_state),
        location_id    = resident == .Iva || resident == .Zora ? "east_island" : "west_island",
        resident_index = int(resident),
    })
    if !opened do return false
    editor.attendant_dialogue = conversation
    editor.attendant_dialogue_open = true
    editor.attendant_dialogue_focus = 0
    editor.attendant_dialogue_action = .None
    editor.dialogue_resident = resident
    game_input.reset_menu_repeat(&editor.runtime_input)
    set_pointer_locked(false)
    _ = sdl.ShowCursor()
    return true
}

attendant_dialogue_panel :: proc(editor: ^Editor, width, height: i32) -> rl.Rectangle {
    choice_count := 1
    if editor != nil do choice_count = max(dialogue.available_count(&editor.attendant_dialogue), 1)
    panel_height := min(f32(height) - 96, 146 + f32(choice_count) * 42)
    return {x = f32(width) * .5 - 310, y = f32(height) - panel_height - 48, width = 620, height = panel_height}
}

attendant_dialogue_choice_bounds :: proc(panel: rl.Rectangle, index: int) -> rl.Rectangle {
    return {x = panel.x + 24, y = panel.y + 126 + f32(index) * 42, width = panel.width - 48, height = 34}
}

tarot_layout_draw :: proc(editor: ^Editor, panel: rl.Rectangle) {
    if editor == nil || editor.dialogue_resident != .Zora do return
    current := dialogue.current(&editor.attendant_dialogue)
    if current == nil || current.id != "zora-reading" do return
    layout := &editor.story_state.tarot_layout
    if layout.count == 0 do return
    columns := layout.count <= 3 ? layout.count : 5
    card_width := layout.count <= 3 ? f32(126) : f32(100)
    art_height := card_width * 158 / 108
    label_height := layout.count <= 3 ? f32(46) : f32(40)
    gap := f32(10)
    card_height := art_height + label_height
    board_width := f32(columns) * card_width + f32(columns - 1) * gap + 24
    rows := (layout.count + columns - 1) / columns
    board_height := f32(rows) * card_height + f32(rows - 1) * gap + 42
    board := rl.Rectangle {
        x      = panel.x + (panel.width - board_width) * .5,
        y      = max(f32(18), panel.y - board_height - 12),
        width  = board_width,
        height = board_height,
    }
    rl.DrawRectangleRounded(board, .06, 8, {24, 18, 42, 244})
    rl.DrawRectangleRoundedLinesEx(board, .06, 8, 1, {185, 145, 77, 255})
    title := fmt.ctprintf("%s", tarot.spread_name(layout.spread))
    title_size := rl.MeasureTextEx(rl.Font{}, title, 14, 1)
    rl.DrawTextEx(
        rl.Font{},
        title,
        {board.x + (board.width - title_size.x) * .5, board.y + 10},
        14,
        1,
        {245, 220, 151, 255},
    )
    for placement, index in layout.placements[:layout.count] {
        column, row := index % columns, index / columns
        bounds := rl.Rectangle {
            x      = board.x + 12 + f32(column) * (card_width + gap),
            y      = board.y + 32 + f32(row) * (card_height + gap),
            width  = card_width,
            height = card_height,
        }
        art_bounds := rl.Rectangle{bounds.x, bounds.y, bounds.width, art_height}
        reversed := placement.orientation == .Reversed
        if editor.tarot_atlas.ready {
            card_id := int(placement.card)
            atlas_row, atlas_column := 0, 0
            if card_id < 14 {
                atlas_column = card_id
            } else if card_id < 22 {
                atlas_row = 1
                atlas_column = card_id - 14
            } else {
                minor := card_id - 22
                atlas_row = 2 + minor / 14
                atlas_column = minor % 14
            }
            source := rl.Rectangle {
                x      = f32(atlas_column * 108),
                y      = f32(atlas_row * 158),
                width  = 108,
                height = 158,
            }
            if reversed {
                source.x += source.width
                source.y += source.height
                source.width = -source.width
                source.height = -source.height
            }
            rl.DrawTexturePro(editor.tarot_atlas, source, art_bounds, {255, 255, 255, 255})
        } else {
            rl.DrawRectangleRounded(art_bounds, .08, 6, {240, 226, 186, 255})
        }
        position_label := fmt.ctprintf("%s%s", placement.position, reversed ? " · REVERSED" : "")
        available_width := bounds.width - 8
        position_font_size := layout.count <= 3 ? f32(11) : f32(9)
        position_measured := rl.MeasureTextEx(rl.Font{}, position_label, position_font_size, .5)
        if position_measured.x > available_width {
            position_font_size *= available_width / position_measured.x
        }
        rl.DrawTextEx(
            rl.Font{},
            position_label,
            {bounds.x + 4, bounds.y + art_height + 5},
            position_font_size,
            .5,
            {181, 190, 183, 255},
        )
        card_label := fmt.ctprintf("%s", tarot.card_name(placement.card))
        card_font_size := layout.count <= 3 ? f32(13) : f32(10)
        measured := rl.MeasureTextEx(rl.Font{}, card_label, card_font_size, .5)
        if measured.x > available_width {
            card_font_size *= available_width / measured.x
            card_font_size = max(card_font_size, layout.count <= 3 ? f32(10) : f32(8))
        }
        rl.DrawTextEx(
            rl.Font{},
            card_label,
            {bounds.x + 4, bounds.y + art_height + 23},
            card_font_size,
            .5,
            {245, 220, 151, 255},
        )
    }
}

attendant_dialogue_close :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.attendant_dialogue_open = false
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
    editor.libellula_visible = true
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
    editor.player.position = {
        line_position.x,
        terrain.sample_height(&editor.project, 0, line_position.x, line_position.z + 1.8),
        line_position.z + 1.8,
    }
    editor.pilot.position = editor.player.position
}

attendant_dialogue_activate :: proc(editor: ^Editor, choice_index: int) {
    if editor == nil || !editor.attendant_dialogue_open do return
    romance_before := editor.story_state.romance
    editor.attendant_dialogue_action = .None
    if editor.attendant_dialogue.current_node == 1 &&
       choice_index >= 0 &&
       choice_index < editor.attendant_dialogue_vehicle_choice_count {
        editor.attendant_dialogue_vehicle_target = editor.attendant_dialogue_vehicle_choices[choice_index]
        editor.attendant_dialogue_action = .Select_Aircraft
    }
    if !dialogue.choose(&editor.attendant_dialogue, choice_index) do return
    if romance_before != .Meeting && editor.story_state.romance == .Meeting {
        editor.story_meeting_cinematic_pending = true
    }

    action := editor.attendant_dialogue_action
    if action == .None {
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
    switch action {
    case .Paint_Aircraft:
        vehicle_paint_open(editor)
    case .Select_Aircraft:
        marta_select_aircraft(editor, editor.attendant_dialogue_vehicle_target)
    case .Borrow_Dinghy:
        editor.marina_dinghy_borrowed = true
    case .None, .Close:
    }
}

attendant_dialogue_process_input :: proc(editor: ^Editor, width, height: i32, delta_seconds: f32) {
    if editor == nil || !editor.attendant_dialogue_open || pause_menu_is_open(editor) do return
    panel := attendant_dialogue_panel(editor, width, height)
    mouse := rl.GetMousePosition()
    mouse_delta := rl.GetMouseDelta()
    mouse_active := rl.IsMouseButtonPressed(.LEFT) || math.abs(mouse_delta.x) > .01 || math.abs(mouse_delta.y) > .01

    horizontal, vertical := game_input.menu_steps(
        &editor.runtime_input,
        gamepad_axis(.Left_X),
        gamepad_axis(.Left_Y),
        delta_seconds,
    )
    direction := 0
    if rl.IsKeyPressed(.UP) || gamepad_pressed(.Dpad_Up) do direction -= 1
    if rl.IsKeyPressed(.DOWN) || gamepad_pressed(.Dpad_Down) do direction += 1
    if direction == 0 do direction = vertical
    if direction == 0 do direction = horizontal
    choice_count := dialogue.available_count(&editor.attendant_dialogue)
    if direction != 0 {
        editor.attendant_dialogue_focus = clamp(
            editor.attendant_dialogue_focus + direction,
            0,
            max(choice_count - 1, 0),
        )
    }

    if mouse_active {
        for index in 0 ..< choice_count {
            if rl.CheckCollisionPointRec(mouse, attendant_dialogue_choice_bounds(panel, index)) {
                editor.attendant_dialogue_focus = index
            }
        }
    }

    activated := -1
    if input_action_pressed(.Menu_Accept) do activated = editor.attendant_dialogue_focus
    if input_action_pressed(.Menu_Cancel) do activated = max(choice_count - 1, 0)
    if rl.IsMouseButtonPressed(.LEFT) {
        for index in 0 ..< choice_count {
            if rl.CheckCollisionPointRec(mouse, attendant_dialogue_choice_bounds(panel, index)) {
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
    positions := [2]third_person.Vec3{editor.attendant_position, editor.gerta_position}
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
    candidates := [4]story.Resident{.Niko, .Iva, .Bojan, .Zora}
    for candidate in candidates {
        if require_action && !story.resident_has_action(&editor.story_state, candidate) do continue
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
        append(&editor.libellula_projected_faces, Projected_Aircraft_Face {
            a     = pa.position,
            b     = pb.position,
            c     = pc.position,
            depth = (pa.depth + pb.depth + pc.depth) / 3,
            color = aircraft_part_color(a.part),
        })
    }
    faces := editor.libellula_projected_faces[:]
    face_count := len(faces)
    slice.stable_sort_by(faces, proc(a, b: Projected_Aircraft_Face) -> bool { return a.depth > b.depth })
    for face in faces[:face_count] {
        rl.DrawQuadHatched(face.a, face.b, face.c, face.c, face.color, rl.HATCH_DISABLED)
    }
    label := project_3d(
        camera,
        {editor.libellula.body.position.x, editor.libellula.body.position.y + 3.2, editor.libellula.body.position.z},
        width,
        height,
    )
    if label.visible do rl.DrawTextEx(rl.Font{}, "LIBELLULA", {label.position.x - 35, label.position.y - 12}, 13, 1, {r = 255, g = 239, b = 192, a = 255})
}

draw_postale_3d :: proc(editor: ^Editor, camera: Perspective_Camera, width, height: i32) {
    mesh := vehicles.postale_mesh()
    vehicles.animate_postale_mesh(
        &mesh,
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
    for triangle in vehicles.mesh_triangles(&mesh) {
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
        rl.DrawQuadHatched(face.a, face.b, face.c, face.c, face.color, rl.HATCH_DISABLED)
    }
}

Projected_Aircraft_Face :: struct {
    a, b, c: rl.Vector2,
    depth:   f32,
    color:   rl.Color,
}

@(no_instrumentation)
aircraft_part_color :: #force_inline proc(part: vehicles.Aircraft_Mesh_Part) -> rl.Color {
    #partial switch part {
    case .Wing, .Tail, .Left_Flap, .Right_Flap, .Left_Aileron, .Right_Aileron, .Elevator, .Rudder:
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
    case .Bumper:
        return {r = 174, g = 184, b = 188, a = 255}
    case .Headlight:
        return {r = 255, g = 239, b = 164, a = 255}
    case .Tail_Light:
        return {r = 211, g = 43, b = 42, a = 255}
    case .Ivory:
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

@(no_instrumentation)
aircraft_postale_part_color :: #force_inline proc(part: vehicles.Aircraft_Mesh_Part, throttle: f32) -> rl.Color {
    color: rl.Color
    #partial switch part {
    case .Body:
        color = {
            r = 70,
            g = 103,
            b = 76,
            a = 255,
        }
    case .Wing, .Tail, .Left_Flap, .Right_Flap, .Left_Aileron, .Right_Aileron, .Elevator, .Rudder:
        color = {
            r = 222,
            g = 197,
            b = 126,
            a = 255,
        }
    case .Engine:
        color = {
            r = 164,
            g = 61,
            b = 48,
            a = 255,
        }
    case .Propeller:
        color = {
            r = 104,
            g = 70,
            b = 42,
            a = 255,
        }
    case .Frame:
        color = {
            r = 65,
            g = 72,
            b = 68,
            a = 255,
        }
    case .Glass:
        color = {
            r = 142,
            g = 218,
            b = 230,
            a = 190,
        }
    case .Strap:
        color = {
            r = 101,
            g = 61,
            b = 39,
            a = 255,
        }
    case .Marking:
        color = {
            r = 237,
            g = 226,
            b = 192,
            a = 255,
        }
    case .Red_Paint:
        color = {
            r = 188,
            g = 55,
            b = 45,
            a = 255,
        }
    case:
        color = aircraft_part_color(part)
    }
    blur := aircraft_propeller_blur_amount(throttle)
    if part == .Propeller || part == .Left_Propeller || part == .Right_Propeller {
        color.a = u8(clamp(255 * (1 - blur * .84), 0, 255))
    } else if part == .Propeller_Blur {
        color.a = u8(clamp(18 + blur * 26, 0, 255))
    }
    return color
}

@(no_instrumentation)
aircraft_postale_part_color_with_paint :: #force_inline proc(
    editor: ^Editor,
    part: vehicles.Aircraft_Mesh_Part,
    throttle: f32,
) -> rl.Color {
    color := aircraft_postale_part_color(part, throttle)
    if part == .Propeller_Blur {
        painted := vehicle_paint_propeller_color(editor)
        color.r, color.g, color.b = painted.r, painted.g, painted.b
    }
    return color
}

@(no_instrumentation)
color_lerp :: #force_inline proc(a, b: rl.Color, amount: f32) -> rl.Color {
    t := clamp(amount, 0, 1)
    return {
        r = u8(f32(a.r) + (f32(b.r) - f32(a.r)) * t),
        g = u8(f32(a.g) + (f32(b.g) - f32(a.g)) * t),
        b = u8(f32(a.b) + (f32(b.b) - f32(a.b)) * t),
        a = u8(f32(a.a) + (f32(b.a) - f32(a.a)) * t),
    }
}

draw_antialiased_disc :: proc(center: rl.Vector2, radius: f32, color: rl.Color) {
    feather := color
    feather.a = u8(f32(color.a) * .18)
    shoulder := color
    shoulder.a = u8(f32(color.a) * .48)
    rl.DrawCircleHatched(center, radius + 1.25, feather, rl.HATCH_DISABLED, 96)
    rl.DrawCircleHatched(center, radius + .55, shoulder, rl.HATCH_DISABLED, 96)
    rl.DrawCircleHatched(center, radius, color, rl.HATCH_DISABLED, 96)
}

draw_antialiased_line :: proc(a, b: rl.Vector2, thickness: f32, color: rl.Color) {
    feather := color
    feather.a = u8(f32(color.a) * .22)
    rl.DrawLineEx(a, b, thickness + 1.5, feather)
    rl.DrawLineEx(a, b, thickness, color)
}

draw_instrument_text :: proc(text: cstring, position: rl.Vector2, size, spacing: f32, color: rl.Color) {
    shadow := rl.Color {
        r = 0,
        g = 7,
        b = 12,
        a = u8(235 * f32(color.a) / 255),
    }
    rl.DrawTextEx(rl.Font{}, text, {position.x + 1.5, position.y + 1.5}, size, spacing, shadow)
    rl.DrawTextEx(rl.Font{}, text, position, size, spacing, color)
}

draw_flight_console_panel :: proc(bounds: rl.Rectangle, corner_radius: f32, color: rl.Color) {
    radius := clamp(corner_radius, 0, min(bounds.width * .5, bounds.height))
    // Scan the upper quarter-arcs into horizontal subpixel lines. Unlike whole
    // discs, this keeps very large radii clipped to the upper corners and
    // guarantees that the installed console's lower edge remains square.
    rows := max(1, int(math.ceil(f64(radius))))
    for row in 0 ..< rows {
        vertical := radius - min(f32(row) + .5, radius)
        horizontal := f32(math.sqrt(f64(max(radius * radius - vertical * vertical, 0))))
        inset := radius - horizontal
        y := bounds.y + f32(row) + .5
        draw_antialiased_line({bounds.x + inset, y}, {bounds.x + bounds.width - inset, y}, 1, color)
    }
    rl.DrawRectangle(i32(bounds.x), i32(bounds.y + radius), i32(bounds.width), i32(bounds.height - radius), color)

    // Trace the curved shoulder as one continuous padded coaming. The warm
    // leather edge ties the panel to the Postale's cockpit upholstery while a
    // narrow cool highlight keeps the contour readable against dark scenery.
    coaming := rl.Color {
        r = 84,
        g = 55,
        b = 39,
        a = 255,
    }
    edge := rl.Color {
        r = 139,
        g = 115,
        b = 86,
        a = 210,
    }
    previous_left := rl.Vector2{bounds.x + radius, bounds.y + .5}
    previous_right := rl.Vector2{bounds.x + bounds.width - radius, bounds.y + .5}
    draw_antialiased_line(previous_left, previous_right, 4.5, coaming)
    draw_antialiased_line(previous_left, previous_right, 1.2, edge)
    for row in 1 ..< rows {
        vertical := radius - min(f32(row) + .5, radius)
        horizontal := f32(math.sqrt(f64(max(radius * radius - vertical * vertical, 0))))
        inset := radius - horizontal
        y := bounds.y + f32(row) + .5
        left := rl.Vector2{bounds.x + inset, y}
        right := rl.Vector2{bounds.x + bounds.width - inset, y}
        draw_antialiased_line(previous_left, left, 4.5, coaming)
        draw_antialiased_line(previous_right, right, 4.5, coaming)
        draw_antialiased_line(previous_left, left, 1.1, edge)
        draw_antialiased_line(previous_right, right, 1.1, edge)
        previous_left = left
        previous_right = right
    }
    draw_antialiased_line(
        {bounds.x + 18, bounds.y + bounds.height - 1},
        {bounds.x + bounds.width - 18, bounds.y + bounds.height - 1},
        1.2,
        {r = 2, g = 8, b = 11, a = 230},
    )
    screw := rl.Color {
        r = 151,
        g = 160,
        b = 149,
        a = 230,
    }
    screw_shadow := rl.Color {
        r = 3,
        g = 9,
        b = 11,
        a = 240,
    }
    screw_positions := [4]rl.Vector2 {
        {bounds.x + 18, bounds.y + bounds.height - 17},
        {bounds.x + bounds.width - 18, bounds.y + bounds.height - 17},
        {bounds.x + radius * .72, bounds.y + radius * .72},
        {bounds.x + bounds.width - radius * .72, bounds.y + radius * .72},
    }
    for position in screw_positions {
        draw_antialiased_disc(position, 3.2, screw_shadow)
        draw_antialiased_disc(position, 1.8, screw)
        draw_antialiased_line(
            {position.x - 1.2, position.y + 1.2},
            {position.x + 1.2, position.y - 1.2},
            .8,
            screw_shadow,
        )
    }
}

draw_instrument_bezel :: proc(center: rl.Vector2, radius: f32) {
    shadow := rl.Color {
        r = 2,
        g = 8,
        b = 11,
        a = 235,
    }
    outer := rl.Color {
        r = 42,
        g = 57,
        b = 59,
        a = 255,
    }
    metal := rl.Color {
        r = 104,
        g = 132,
        b = 132,
        a = 235,
    }
    inner := rl.Color {
        r = 19,
        g = 31,
        b = 37,
        a = 255,
    }
    face := rl.Color {
        r = 9,
        g = 21,
        b = 29,
        a = 255,
    }
    draw_antialiased_disc({center.x + 1.5, center.y + 2}, radius + 7, shadow)
    draw_antialiased_disc(center, radius + 6, outer)
    draw_antialiased_disc(center, radius + 4, metal)
    draw_antialiased_disc(center, radius + 1.5, inner)
    draw_antialiased_disc(center, radius, face)
}

draw_instrument_glass :: proc(center: rl.Vector2, radius: f32) {
    reflection := rl.Color {
        r = 196,
        g = 236,
        b = 235,
        a = 42,
    }
    // Restrained diagonal glints imply convex glass without washing out the
    // markings or introducing a large translucent overlay.
    draw_antialiased_line(
        {center.x - radius * .56, center.y - radius * .58},
        {center.x - radius * .18, center.y - radius * .78},
        1.5,
        reflection,
    )
    draw_antialiased_line(
        {center.x - radius * .61, center.y - radius * .48},
        {center.x - radius * .44, center.y - radius * .57},
        1,
        reflection,
    )
}

draw_rounded_inset :: proc(bounds: rl.Rectangle, corner_radius: f32, color: rl.Color) {
    radius := clamp(corner_radius, 0, min(bounds.width, bounds.height) * .5)
    rows := max(1, int(math.ceil(f64(bounds.height))))
    for row in 0 ..< rows {
        y_local := min(f32(row) + .5, bounds.height - .5)
        inset := f32(0)
        if y_local < radius {
            vertical := radius - y_local
            inset = radius - f32(math.sqrt(f64(max(radius * radius - vertical * vertical, 0))))
        } else if y_local > bounds.height - radius {
            vertical := y_local - (bounds.height - radius)
            inset = radius - f32(math.sqrt(f64(max(radius * radius - vertical * vertical, 0))))
        }
        rl.DrawLineEx(
            {bounds.x + inset, bounds.y + y_local},
            {bounds.x + bounds.width - inset, bounds.y + y_local},
            1.2,
            color,
        )
    }
}

draw_rectangular_instrument_bezel :: proc(bounds: rl.Rectangle, radius: f32) -> rl.Rectangle {
    draw_rounded_inset(
        {x = bounds.x + 1.5, y = bounds.y + 2, width = bounds.width, height = bounds.height},
        radius,
        {r = 2, g = 8, b = 11, a = 235},
    )
    draw_rounded_inset(bounds, radius, {r = 45, g = 60, b = 62, a = 255})
    metal_bounds := rl.Rectangle {
        x      = bounds.x + 2,
        y      = bounds.y + 2,
        width  = bounds.width - 4,
        height = bounds.height - 4,
    }
    draw_rounded_inset(metal_bounds, max(radius - 2, f32(1)), {r = 104, g = 132, b = 132, a = 235})
    face_bounds := rl.Rectangle {
        x      = bounds.x + 4,
        y      = bounds.y + 4,
        width  = bounds.width - 8,
        height = bounds.height - 8,
    }
    draw_rounded_inset(face_bounds, max(radius - 4, f32(1)), {r = 7, g = 19, b = 27, a = 255})
    return face_bounds
}

draw_instrument_dial :: proc(
    center: rl.Vector2,
    radius: f32,
    label: cstring,
    value, minimum, maximum: f32,
    value_text: cstring,
    value_y_offset: f32 = 27,
    range_start: f32 = -1,
    range_end: f32 = -1,
) {
    mark := rl.Color {
        r = 232,
        g = 247,
        b = 245,
        a = 255,
    }
    accent := rl.Color {
        r = 239,
        g = 203,
        b = 111,
        a = 255,
    }
    draw_instrument_bezel(center, radius)
    sweep_start := f32(math.PI * .75)
    sweep_range := f32(math.PI * 1.5)
    for tick in 0 ..= 14 {
        angle := sweep_start + f32(tick) / 14 * sweep_range
        outer := rl.Vector2{center.x + math.cos(angle) * (radius - 7), center.y + math.sin(angle) * (radius - 7)}
        major := tick % 7 == 0
        inner_radius := radius - (major ? f32(18) : f32(13))
        inner := rl.Vector2{center.x + math.cos(angle) * inner_radius, center.y + math.sin(angle) * inner_radius}
        draw_antialiased_line(inner, outer, major ? f32(2.6) : f32(1.5), mark)
    }
    if range_start >= minimum && range_end > range_start {
        start_fraction := clamp((range_start - minimum) / max(maximum - minimum, f32(.001)), 0, 1)
        end_fraction := clamp((range_end - minimum) / max(maximum - minimum, f32(.001)), 0, 1)
        band_radius := radius - 19
        band_color := rl.Color {
            r = 92,
            g = 219,
            b = 213,
            a = 180,
        }
        previous_angle := sweep_start + start_fraction * sweep_range
        previous := rl.Vector2 {
            center.x + math.cos(previous_angle) * band_radius,
            center.y + math.sin(previous_angle) * band_radius,
        }
        for segment in 1 ..= 14 {
            fraction := start_fraction + (end_fraction - start_fraction) * f32(segment) / 14
            angle := sweep_start + fraction * sweep_range
            point := rl.Vector2{center.x + math.cos(angle) * band_radius, center.y + math.sin(angle) * band_radius}
            draw_antialiased_line(previous, point, 2, band_color)
            previous = point
        }
    }
    // Three quiet scale anchors make needle position readable at a glance
    // without crowding the compact face with a full ring of numerals.
    scale_values := [3]f32{minimum, (minimum + maximum) * .5, maximum}
    scale_fractions := [3]f32{0, .5, 1}
    for index in 0 ..< len(scale_values) {
        angle := sweep_start + scale_fractions[index] * sweep_range
        anchor_radius := radius - 20
        text := fmt.ctprintf("%.0f", scale_values[index])
        size := rl.MeasureTextEx(rl.Font{}, text, 9, 0)
        position := rl.Vector2 {
            center.x + math.cos(angle) * anchor_radius - size.x * .5,
            center.y + math.sin(angle) * anchor_radius - size.y * .5,
        }
        draw_instrument_text(text, position, 9, 0, {r = 182, g = 207, b = 205, a = 230})
    }
    fraction := clamp((value - minimum) / max(f32(.001), maximum - minimum), 0, 1)
    needle_angle := sweep_start + fraction * sweep_range
    needle_length := radius - 23
    needle_end := rl.Vector2 {
        center.x + math.cos(needle_angle) * needle_length,
        center.y + math.sin(needle_angle) * needle_length,
    }
    needle_shadow := rl.Color {
        r = 1,
        g = 7,
        b = 10,
        a = 220,
    }
    draw_antialiased_line(
        {center.x + 1.5, center.y + 1.5},
        {needle_end.x + 1.5, needle_end.y + 1.5},
        4.2,
        needle_shadow,
    )
    draw_antialiased_line(center, needle_end, 3.5, accent)
    counterweight := rl.Vector2{center.x - math.cos(needle_angle) * 10, center.y - math.sin(needle_angle) * 10}
    draw_antialiased_line(center, counterweight, 2.4, accent)
    draw_antialiased_disc(center, 6.2, needle_shadow)
    draw_antialiased_disc(center, 4.2, accent)
    label_size := rl.MeasureTextEx(rl.Font{}, label, 14, 1)
    value_size := rl.MeasureTextEx(rl.Font{}, value_text, 18, 1)
    draw_instrument_text(label, {center.x - label_size.x * .5, center.y - 18}, 14, 1, mark)
    draw_instrument_text(value_text, {center.x - value_size.x * .5, center.y + value_y_offset}, 18, 1, accent)
    draw_instrument_glass(center, radius)
}

draw_attitude_indicator :: proc(center: rl.Vector2, radius, pitch, bank: f32) {
    sky := rl.Color {
        r = 35,
        g = 91,
        b = 128,
        a = 255,
    }
    sky_horizon := rl.Color {
        r = 74,
        g = 158,
        b = 184,
        a = 255,
    }
    earth := rl.Color {
        r = 91,
        g = 57,
        b = 37,
        a = 255,
    }
    earth_horizon := rl.Color {
        r = 163,
        g = 111,
        b = 62,
        a = 255,
    }
    mark := rl.Color {
        r = 240,
        g = 248,
        b = 235,
        a = 255,
    }
    accent := rl.Color {
        r = 239,
        g = 203,
        b = 111,
        a = 255,
    }
    draw_instrument_bezel(center, radius)

    // Rasterize the moving card as rotated chords. Each chord is constrained
    // to the dial circle, so bank and pitch never produce the rectangular
    // color bars that made the old indicator read like a placeholder.
    scale := radius / 48
    inner_radius := radius - 4
    pitch_offset := clamp(pitch * 42 * scale, -inner_radius * .72, inner_radius * .72)
    c, s := math.cos(bank), math.sin(bank)
    scan_count := max(1, int(math.ceil(f64(inner_radius * 2))))
    for scan in 0 ..< scan_count {
        card_y := -inner_radius + (f32(scan) + .5) * inner_radius * 2 / f32(scan_count)
        half_chord := f32(math.sqrt(f64(max(inner_radius * inner_radius - card_y * card_y, 0))))
        line_center := rl.Vector2{center.x + s * card_y, center.y - c * card_y}
        left := rl.Vector2{line_center.x - c * half_chord, line_center.y - s * half_chord}
        right := rl.Vector2{line_center.x + c * half_chord, line_center.y + s * half_chord}
        distance_from_horizon := clamp(math.abs(card_y - pitch_offset) / max(inner_radius * .85, f32(1)), 0, 1)
        card_color := color_lerp(earth_horizon, earth, distance_from_horizon)
        if card_y >= pitch_offset {
            card_color = color_lerp(sky_horizon, sky, distance_from_horizon)
        }
        rl.DrawLineEx(left, right, 1.35, card_color)
    }

    tangent := rl.Vector2{c, s}
    normal := rl.Vector2{s, -c}
    horizon_center := rl.Vector2{center.x + normal.x * pitch_offset, center.y + normal.y * pitch_offset}
    horizon_half := f32(math.sqrt(f64(max(inner_radius * inner_radius - pitch_offset * pitch_offset, 0))))
    draw_antialiased_line(
        {horizon_center.x - tangent.x * horizon_half, horizon_center.y - tangent.y * horizon_half},
        {horizon_center.x + tangent.x * horizon_half, horizon_center.y + tangent.y * horizon_half},
        2,
        mark,
    )

    // Ten-degree pitch ladder, attached to the moving card.
    ladder_spacing := 10 * scale
    for step in -2 ..= 2 {
        if step == 0 do continue
        ladder_y := pitch_offset + f32(step) * ladder_spacing
        if math.abs(ladder_y) >= inner_radius - 8 do continue
        ladder_half := (step % 2 == 0 ? f32(16) : f32(10)) * scale
        ladder_center := rl.Vector2{center.x + normal.x * ladder_y, center.y + normal.y * ladder_y}
        draw_antialiased_line(
            {ladder_center.x - tangent.x * ladder_half, ladder_center.y - tangent.y * ladder_half},
            {ladder_center.x + tangent.x * ladder_half, ladder_center.y + tangent.y * ladder_half},
            1.3,
            mark,
        )
    }

    // Fixed bank scale and lubber pointer make roll readable even when the
    // horizon is near the edge of the dial.
    bank_marks := [5]f32{-60, -30, 0, 30, 60}
    for degrees in bank_marks {
        angle := -math.PI * .5 + degrees * math.PI / 180
        outer := rl.Vector2{center.x + math.cos(angle) * (radius - 7), center.y + math.sin(angle) * (radius - 7)}
        inner := rl.Vector2 {
            center.x + math.cos(angle) * (radius - (degrees == 0 ? f32(16) : f32(12))),
            center.y + math.sin(angle) * (radius - (degrees == 0 ? f32(16) : f32(12))),
        }
        draw_antialiased_line(inner, outer, degrees == 0 ? f32(2.5) : f32(1.5), mark)
    }

    // The white chevron belongs to the moving card. Against the fixed bank
    // scale it gives an immediate, mechanical read of roll direction.
    bank_tip := rl.Vector2{center.x + normal.x * (radius - 15), center.y + normal.y * (radius - 15)}
    bank_base := rl.Vector2{center.x + normal.x * (radius - 23), center.y + normal.y * (radius - 23)}
    draw_antialiased_line({bank_base.x - tangent.x * 4, bank_base.y - tangent.y * 4}, bank_tip, 1.8, mark)
    draw_antialiased_line(bank_tip, {bank_base.x + tangent.x * 4, bank_base.y + tangent.y * 4}, 1.8, mark)

    // Fixed miniature-aircraft symbol.
    draw_antialiased_line({center.x - 29 * scale, center.y}, {center.x - 8 * scale, center.y}, 3.5, accent)
    draw_antialiased_line({center.x + 8 * scale, center.y}, {center.x + 29 * scale, center.y}, 3.5, accent)
    draw_antialiased_line({center.x - 8 * scale, center.y}, {center.x, center.y + 5 * scale}, 3, accent)
    draw_antialiased_line({center.x + 8 * scale, center.y}, {center.x, center.y + 5 * scale}, 3, accent)
    draw_antialiased_disc({center.x, center.y + 5 * scale}, 3.5 * scale, accent)
    draw_instrument_glass(center, radius)
}

compass_tick_label :: proc(degrees: int) -> cstring {
    heading := degrees % 360
    if heading < 0 do heading += 360
    switch heading {
    case 0:
        return "N"
    case 90:
        return "E"
    case 180:
        return "S"
    case 270:
        return "W"
    case:
        return fmt.ctprintf("%02d", heading / 10)
    }
}

draw_heading_compass :: proc(center: rl.Vector2, width, heading_degrees: f32) {
    height := f32(42)
    outer := rl.Rectangle {
        x      = center.x - width * .5,
        y      = center.y - height * .5,
        width  = width,
        height = height,
    }
    face := draw_rectangular_instrument_bezel(outer, 8)
    accent := rl.Color {
        r = 239,
        g = 203,
        b = 111,
        a = 255,
    }
    nearest := int(math.round(f64(heading_degrees / 15))) * 15
    half_range := f32(52.5)
    for offset := -4; offset <= 4; offset += 1 {
        tick_heading := nearest + offset * 15
        delta := f32(tick_heading) - heading_degrees
        for delta > 180 do delta -= 360
        for delta < -180 do delta += 360
        if math.abs(delta) > half_range do continue
        x := center.x + delta / half_range * (face.width * .46)
        major := tick_heading % 30 == 0
        tick_top := face.y + (major ? f32(3) : f32(7))
        draw_antialiased_line({x, tick_top}, {x, face.y + 13}, major ? f32(1.8) : f32(1), {220, 239, 238, 255})
        if major {
            label := compass_tick_label(tick_heading)
            label_size := rl.MeasureTextEx(rl.Font{}, label, 11, 1)
            normalized := tick_heading % 360
            if normalized < 0 do normalized += 360
            label_color := normalized % 90 == 0 ? accent : rl.Color{235, 248, 246, 255}
            draw_instrument_text(label, {x - label_size.x * .5, face.y + 15}, 11, 1, label_color)
        }
    }

    // A fixed brass lubber index sits proud of the moving heading card.
    pointer_top := outer.y + 1
    draw_antialiased_line({center.x, pointer_top + 1}, {center.x, pointer_top + 12}, 2.5, accent)
    draw_antialiased_line({center.x - 5, pointer_top + 3}, {center.x, pointer_top + 9}, 2, accent)
    draw_antialiased_line({center.x + 5, pointer_top + 3}, {center.x, pointer_top + 9}, 2, accent)
    draw_antialiased_line(
        {face.x + 12, face.y + 3},
        {face.x + face.width * .28, face.y + 3},
        1,
        {r = 196, g = 236, b = 235, a = 34},
    )
}

draw_throttle_overlay :: proc(editor: ^Editor, width, height: i32, power: f32) {
    if editor == nil do return
    normalized := clamp(power, 0, 1)
    now := rl.GetTime()
    if !editor.flight_throttle_overlay_initialized {
        editor.flight_throttle_overlay_value = normalized
        editor.flight_throttle_overlay_changed_at = now
        editor.flight_throttle_overlay_initialized = true
    } else if math.abs(normalized - editor.flight_throttle_overlay_value) > .001 {
        editor.flight_throttle_overlay_value = normalized
        editor.flight_throttle_overlay_changed_at = now
    }

    age := f32(now - editor.flight_throttle_overlay_changed_at)
    if age >= 3 do return
    fade_in := clamp(age / .14, 0, 1)
    fade_out := clamp((3 - age) / .65, 0, 1)
    visibility := fade_in * fade_out
    alpha := u8(clamp(255 * visibility, 0, 255))

    overlay_height := min(f32(height) * .68, f32(500))
    overlay_width := f32(52)
    outer := rl.Rectangle {
        x      = f32(width) - overlay_width - 22,
        y      = (f32(height) - overlay_height) * .5,
        width  = overlay_width,
        height = overlay_height,
    }
    draw_rounded_inset(outer, 15, {r = 3, g = 12, b = 18, a = u8(f32(alpha) * .72)})
    edge := rl.Color {
        r = 104,
        g = 132,
        b = 132,
        a = u8(f32(alpha) * .72),
    }
    draw_antialiased_line({outer.x + 10, outer.y + 1}, {outer.x + outer.width - 10, outer.y + 1}, 1.2, edge)

    track_top := outer.y + 45
    track_bottom := outer.y + outer.height - 30
    track_x := outer.x + outer.width * .5
    track_height := track_bottom - track_top
    draw_antialiased_line(
        {track_x, track_top},
        {track_x, track_bottom},
        8,
        {r = 7, g = 20, b = 28, a = u8(f32(alpha) * .92)},
    )
    level_y := track_bottom - normalized * track_height
    fill_color := color_lerp({r = 190, g = 132, b = 67, a = 255}, {r = 246, g = 211, b = 111, a = 255}, normalized)
    fill_color.a = alpha
    draw_antialiased_line({track_x, track_bottom}, {track_x, level_y}, 5, fill_color)
    tick_color := rl.Color {
        r = 190,
        g = 211,
        b = 207,
        a = u8(f32(alpha) * .78),
    }
    for detent in 0 ..= 8 {
        y := track_top + f32(detent) / 8 * track_height
        major := detent % 2 == 0
        draw_antialiased_line(
            {track_x - (major ? f32(13) : f32(9)), y},
            {track_x - 6, y},
            major ? f32(1.3) : f32(.8),
            tick_color,
        )
    }

    // The bright sliding handle is the primary feedback; the percentage is a
    // secondary confirmation and disappears with the rest of the overlay.
    draw_antialiased_disc({track_x, level_y}, 8, {r = 6, g = 17, b = 22, a = alpha})
    draw_antialiased_line({track_x - 12, level_y}, {track_x + 12, level_y}, 4, fill_color)
    label: cstring = "THR"
    value := fmt.ctprintf("%.0f%%", normalized * 100)
    label_size := rl.MeasureTextEx(rl.Font{}, label, 11, 1)
    value_size := rl.MeasureTextEx(rl.Font{}, value, 13, 1)
    text_color := rl.Color {
        r = 231,
        g = 245,
        b = 243,
        a = alpha,
    }
    draw_instrument_text(label, {track_x - label_size.x * .5, outer.y + 13}, 11, 1, text_color)
    draw_instrument_text(value, {track_x - value_size.x * .5, outer.y + outer.height - 21}, 13, 1, fill_color)
}

draw_vsi_inset :: proc(center: rl.Vector2, radius, vertical_speed: f32) {
    track_x := center.x + radius * .55
    track_half_height := radius * .34
    capsule := rl.Rectangle {
        x      = track_x - 10,
        y      = center.y - track_half_height - 5,
        width  = 20,
        height = track_half_height * 2 + 10,
    }
    draw_rounded_inset(capsule, 8, {r = 45, g = 60, b = 62, a = 245})
    face := rl.Rectangle {
        x      = capsule.x + 2,
        y      = capsule.y + 2,
        width  = capsule.width - 4,
        height = capsule.height - 4,
    }
    draw_rounded_inset(face, 6, {r = 5, g = 17, b = 24, a = 255})

    track := rl.Color {
        r = 126,
        g = 164,
        b = 168,
        a = 210,
    }
    climb := rl.Color {
        r = 92,
        g = 219,
        b = 213,
        a = 255,
    }
    draw_antialiased_line({track_x, center.y - track_half_height}, {track_x, center.y + track_half_height}, 1.2, track)
    for tick in -2 ..= 2 {
        y := center.y + f32(tick) * track_half_height * .5
        tick_half := tick == 0 ? f32(5) : f32(3)
        draw_antialiased_line({track_x - tick_half, y}, {track_x + tick_half, y}, 1, track)
    }
    end_y := center.y - clamp(vertical_speed / 10, -1, 1) * track_half_height
    draw_antialiased_line({track_x, center.y}, {track_x, end_y}, 3, climb)
    draw_antialiased_line({track_x - 6, end_y}, {track_x + 6, end_y}, 2.5, climb)

    // Keep the signed rate close to its pointer rather than laying a second
    // line of text across the altimeter's main scale.
    readout := fmt.ctprintf("%+.0f", vertical_speed)
    readout_size := rl.MeasureTextEx(rl.Font{}, readout, 8, 0)
    readout_y := clamp(end_y - 5, capsule.y + 5, capsule.y + capsule.height - 12)
    draw_instrument_text(readout, {capsule.x - readout_size.x - 3, readout_y}, 8, 0, climb)
}

draw_flight_instruments :: proc(editor: ^Editor, width, height: i32, altitude: f32) {
    panel_width := min(f32(width) - 32, f32(620))
    panel_height := f32(184)
    panel_left := f32(width) * .5 - panel_width * .5
    panel_top := f32(height) - panel_height - 14
    draw_flight_console_panel(
        {x = panel_left, y = panel_top, width = panel_width, height = panel_height},
        112,
        {r = 10, g = 21, b = 21, a = 246},
    )
    body := active_aircraft_body(editor)
    airspeed := active_aircraft_airspeed(editor)
    vertical_speed := body.velocity.y
    bank := postale_game.bank_radians(body.basis)
    pitch := math.asin(clamp(body.basis.forward.y, -1, 1))
    heading := postale_game.yaw_radians(body.basis) * 180 / math.PI
    if heading < 0 do heading += 360
    dial_spacing := panel_width / 3
    dial_radius := clamp(dial_spacing * .30, 54, 64)
    y := panel_top + 68
    draw_instrument_dial(
        {panel_left + dial_spacing * .5, y},
        dial_radius,
        "AIRSPEED",
        airspeed,
        0,
        70,
        fmt.ctprintf("%.0f m/s", airspeed),
        range_start = 24,
        range_end = 70,
    )
    draw_attitude_indicator({panel_left + dial_spacing * 1.5, y}, dial_radius, pitch, bank)
    draw_instrument_dial(
        {panel_left + dial_spacing * 2.5, y},
        dial_radius,
        "ALTITUDE",
        altitude,
        0,
        500,
        fmt.ctprintf("%.0f m", altitude),
        dial_radius * .62,
    )
    draw_vsi_inset({panel_left + dial_spacing * 2.5, y}, dial_radius, vertical_speed)
    compass_y := panel_top + 151
    draw_heading_compass({f32(width) * .5, compass_y}, 276, heading)
    draw_throttle_overlay(editor, width, height, active_aircraft_throttle(editor))
}

draw_postale_speed_effects :: proc(editor: ^Editor, width, height: i32, time: f32) {
    if editor == nil ||
       !editor.in_map ||
       !driving_aircraft(editor) ||
       editor.aircraft.active != .Postale ||
       editor.postale.grounded ||
       editor.postale.crashed {
        return
    }
    intensity := clamp((editor.postale.telemetry.airspeed - 34) / 34, 0, 1)
    if intensity <= .001 do return

    center := rl.Vector2 {
        x = f32(width) * .5 - editor.flight_control.roll * 34,
        y = f32(height) * .46 + editor.flight_control.pitch * 22,
    }
    short_side := min(f32(width), f32(height))
    long_side := max(f32(width), f32(height))
    for index in 0 ..< 42 {
        seed := f32(index) * 2.399963
        speed_variation := .72 + f32(math.sin(f64(seed * 2.17))) * .18
        cycle := time * (1.05 + intensity * 1.8) * speed_variation + f32(index) * .173
        progress := cycle - f32(math.floor(f64(cycle)))
        eased := progress * progress
        inner := short_side * (.10 + .16 * (.5 + .5 * f32(math.sin(f64(seed * 1.31)))))
        distance := inner + (long_side * .72 - inner) * eased
        ray_x := f32(math.cos(f64(seed)))
        ray_y := f32(math.sin(f64(seed))) * .64
        variation := math.abs(f32(math.sin(f64(seed * 3.07))))
        streak_length := (12 + intensity * 76) * (.65 + .35 * variation)
        fade := 1 - math.abs(progress * 2 - 1)
        alpha := u8(clamp((18 + intensity * 108) * fade, 0, 126))
        // The leading edge is always the point farthest from the vanishing
        // point. Fade and taper the trail toward its inner end so a streak can
        // never read as moving back toward the aircraft.
        trail_segments :: 4
        for segment in 0 ..< trail_segments {
            inner_amount := f32(segment) / f32(trail_segments)
            outer_amount := f32(segment + 1) / f32(trail_segments)
            start_distance := distance + streak_length * inner_amount
            finish_distance := distance + streak_length * outer_amount
            start := rl.Vector2{center.x + ray_x * start_distance, center.y + ray_y * start_distance}
            finish := rl.Vector2{center.x + ray_x * finish_distance, center.y + ray_y * finish_distance}
            segment_alpha := u8(clamp(f32(alpha) * (.28 + outer_amount * .72), 0, 126))
            segment_width := (.8 + intensity * 1.35) * (.72 + outer_amount * .28)
            // Speed is a warm, screen-space effect radiating from the flight
            // vanishing point. Wind remains cool and world-aligned.
            rl.DrawLineEx(start, finish, segment_width, {244, 213, 142, segment_alpha})
        }
        head_distance := distance + streak_length
        head := rl.Vector2{center.x + ray_x * head_distance, center.y + ray_y * head_distance}
        rl.DrawCircleV(head, .65 + intensity * .65, {255, 235, 174, alpha})
    }

    // A quiet edge wash sells peripheral blur without obscuring the aircraft or
    // instruments. Its stepped bands avoid requiring a post-process shader.
    for band in 0 ..< 5 {
        inset := i32(band * 7)
        alpha := u8((5 - band) * int(3 + intensity * 3))
        rl.DrawRectangle(inset, inset, width - inset * 2, 3, {225, 194, 126, alpha})
        rl.DrawRectangle(inset, height - inset - 3, width - inset * 2, 3, {225, 194, 126, alpha})
        rl.DrawRectangle(inset, inset, 3, height - inset * 2, {225, 194, 126, alpha})
        rl.DrawRectangle(width - inset - 3, inset, 3, height - inset * 2, {225, 194, 126, alpha})
    }
}

@(no_instrumentation)
perspective_camera :: #force_inline proc(
    pose: third_person.Camera_Pose,
    focal_length: f32 = 1.35,
) -> Perspective_Camera {
    forward := linalg.normalize0((pose.target - pose.position))
    right := linalg.normalize0(linalg.cross(forward, third_person.Vec3{0, 1, 0}))
    return {
        position = pose.position,
        forward = forward,
        right = right,
        up = linalg.cross(right, forward),
        focal_length = focal_length,
    }
}

project_3d :: proc(camera: Perspective_Camera, point: third_person.Vec3, width, height: i32) -> Screen_Point {
    view := (point - camera.position)
    depth := linalg.dot(view, camera.forward)
    if depth <= .08 do return {}
    x := linalg.dot(view, camera.right) * camera.focal_length / depth
    y := linalg.dot(view, camera.up) * camera.focal_length / depth
    // Use the viewport height for both axes so pixels remain square on
    // widescreen targets. Scaling X by width stretches projected geometry by
    // the display aspect ratio.
    half_height := f32(height) * .5
    return {
        position = {f32(width) * .5 + x * half_height, f32(height) * .5 - y * half_height},
        depth = depth,
        visible = true,
    }
}

world_under_cursor :: proc(mouse, center: rl.Vector2, scale: f32) -> (f32, f32) {
    a := (mouse.x - center.x) / scale
    b := (mouse.y - center.y) / (scale * .46)
    return (a + b) * .5, (b - a) * .5
}

@(no_instrumentation)
terrain_color_variation :: #force_inline proc(color: rl.Color, x, z: f32) -> rl.Color {
    // Broad, overlapping waves read as irregular patches instead of a repeated
    // per-cell pattern. World-space sampling keeps the color stable as clipmap
    // levels and the camera move.
    broad := f32(math.sin(f64(x * .021 + z * .013)))
    cross := f32(math.sin(f64(x * -.047 + z * .039 + 1.7)))
    detail := f32(math.sin(f64(x * .113 + z * -.097 + broad * 1.4)))
    variation := broad * .52 + cross * .31 + detail * .17

    // A slight warm/cool shift varies hue as well as brightness. Keeping the
    // range restrained preserves the authored material identity.
    warm := max(variation, 0)
    cool := max(-variation, 0)
    return {
        u8(clamp(f32(color.r) * (1 + variation * .075) + warm * 3, 0, 255)),
        u8(clamp(f32(color.g) * (1 + variation * .055) + cool * 2, 0, 255)),
        u8(clamp(f32(color.b) * (1 + variation * .035) + cool * 4, 0, 255)),
        color.a,
    }
}

@(no_instrumentation)
terrain_color :: #force_inline proc(height, painted, sea_level, x, z: f32) -> rl.Color {
    water := rl.Color {
        r = 26,
        g = 80,
        b = 104,
        a = 255,
    }
    sand := rl.Color {
        r = 205,
        g = 183,
        b = 126,
        a = 255,
    }
    soil := rl.Color {
        r = 145,
        g = 101,
        b = 61,
        a = 255,
    }
    grass := rl.Color {
        r = 70,
        g = 133,
        b = 80,
        a = 255,
    }
    if height <= sea_level do return water
    if painted > .5 do return terrain_color_variation(soil, x, z)

    elevation := height - sea_level
    // Broad blends keep the elevation bands from turning the heightfield cells
    // into hard material rings. The normal-based light applied by each renderer
    // then provides the small-scale shape and slope definition.
    if elevation < .9 {
        base := color_lerp(sand, soil, clamp((elevation - .18) / .72, 0, 1))
        return terrain_color_variation(base, x, z)
    }
    base := color_lerp(soil, grass, clamp((elevation - .9) / 3.1, 0, 1))
    return terrain_color_variation(base, x, z)
}

draw_line_3d :: proc(
    camera: Perspective_Camera,
    a, b: third_person.Vec3,
    width, height: i32,
    thickness: f32,
    color: rl.Color,
) {
    pa := project_3d(camera, a, width, height)
    pb := project_3d(camera, b, width, height)
    if pa.visible && pb.visible do rl.DrawLineEx(pa.position, pb.position, thickness, color)
}

draw_quad_3d :: proc(camera: Perspective_Camera, a, b, c, d: third_person.Vec3, width, height: i32, color: rl.Color) {
    pa := project_3d(camera, a, width, height)
    pb := project_3d(camera, b, width, height)
    pc := project_3d(camera, c, width, height)
    pd := project_3d(camera, d, width, height)
    if pa.visible && pb.visible && pc.visible && pd.visible {
        rl.DrawQuadHatched(pa.position, pb.position, pc.position, pd.position, color, rl.HATCH_DISABLED)
    }
}

world_under_cursor_3d :: proc(
    camera: Perspective_Camera,
    mouse: rl.Vector2,
    width, height: i32,
    plane_height: f32,
) -> (
    f32,
    f32,
    bool,
) {
    if width <= 0 || height <= 0 do return 0, 0, false
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
    if math.abs(direction.y) < .0001 do return 0, 0, false
    distance := (plane_height - camera.position.y) / direction.y
    if distance <= 0 do return 0, 0, false
    return camera.position.x + direction.x * distance, camera.position.z + direction.z * distance, true
}

terrain_under_cursor_3d :: proc(
    editor: ^Editor,
    camera: Perspective_Camera,
    mouse: rl.Vector2,
    width, height: i32,
) -> (
    f32,
    f32,
    bool,
) {
    if editor == nil || width <= 0 || height <= 0 do return 0, 0, false
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
    step := max(f32(terrain.BASE_CELL_SIZE * .5), f32(2))
    half := f32(terrain.WORLD_SIZE_METERS * .5)
    previous_distance := f32(.1)
    previous_delta := f32(1.0e30)
    for distance := step; distance <= terrain.WORLD_SIZE_METERS * 2; distance += step {
        x := camera.position.x + direction.x * distance
        y := camera.position.y + direction.y * distance
        z := camera.position.z + direction.z * distance
        if math.abs(x) > half || math.abs(z) > half {
            previous_distance = distance
            continue
        }
        delta := y - terrain.sample_height(&editor.project, 0, x, z)
        if delta <= 0 && previous_delta > 0 {
            low, high := previous_distance, distance
            for _ in 0 ..< 10 {
                mid := (low + high) * .5
                mx := camera.position.x + direction.x * mid
                my := camera.position.y + direction.y * mid
                mz := camera.position.z + direction.z * mid
                if my > terrain.sample_height(&editor.project, 0, mx, mz) {
                    low = mid
                } else {
                    high = mid
                }
            }
            hit_distance := (low + high) * .5
            return camera.position.x + direction.x * hit_distance, camera.position.z + direction.z * hit_distance, true
        }
        previous_distance = distance
        previous_delta = delta
    }
    return 0, 0, false
}

update_editor_camera :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil do return
    if editor_ui_hit(editor, rl.GetMousePosition(), rl.GetScreenWidth(), rl.GetScreenHeight()) do return
    if rl.IsMouseButtonDown(.MIDDLE) {
        mouse_delta := rl.GetMouseDelta()
        third_person.look(&editor.editor_camera, -mouse_delta.x, mouse_delta.y, .006)
    }
    if !imgui_captures_keyboard() {
        rotate_direction := f32(0)
        if rl.IsKeyDown(.Q) do rotate_direction -= 1
        if rl.IsKeyDown(.E) do rotate_direction += 1
        editor.editor_camera.yaw_radians += rotate_direction * 1.5 * delta_seconds
    }
    wheel := rl.GetMouseWheelMove()
    if wheel != 0 && !shift_key_down() && !alt_key_down() {
        editor.editor_camera.distance = clamp(
            editor.editor_camera.distance * f32(math.pow(0.82, f64(wheel))),
            80,
            5000,
        )
    }
    move_x, move_z := f32(0), f32(0)
    if rl.IsKeyDown(.D) do move_x += 1
    if rl.IsKeyDown(.A) do move_x -= 1
    if rl.IsKeyDown(.W) do move_z += 1
    if rl.IsKeyDown(.S) do move_z -= 1
    yaw := editor.editor_camera.yaw_radians
    forward := third_person.Vec3{-math.sin(yaw), 0, -math.cos(yaw)}
    right := third_person.Vec3{math.cos(yaw), 0, -math.sin(yaw)}
    speed := clamp(editor.editor_camera.distance * .8, 80, 1600)
    if shift_key_down() do speed *= 2
    editor.editor_focus.x += (forward.x * move_z + right.x * move_x) * speed * delta_seconds
    editor.editor_focus.z += (forward.z * move_z + right.z * move_x) * speed * delta_seconds
    half := f32(terrain.WORLD_SIZE_METERS * .5)
    editor.editor_focus.x = clamp(editor.editor_focus.x, -half, half)
    editor.editor_focus.z = clamp(editor.editor_focus.z, -half, half)
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    editor.cameras = third_person.camera_system(editor.camera_pose)
}

editor_focus_terrain :: proc(editor: ^Editor) {
    if editor == nil do return
    focus := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    editor.editor_focus = {focus, 0, focus}
    editor.editor_camera.distance = 900
    if editor.structure_selected >= 0 && editor.structure_selected < editor.project.structure_count {
        structure := editor.project.structures[editor.structure_selected]
        editor.editor_focus = {structure.center_x, structure.base_y + structure.height * .35, structure.center_z}
        editor.editor_camera.distance = clamp(max(structure.width, structure.depth) * 4.5, 180, 1800)
    }
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    editor.cameras = third_person.camera_system(editor.camera_pose)
}

draw_infrastructure_3d :: proc(editor: ^Editor, camera: Perspective_Camera, width, height: i32) {
    level := 0
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    for sign in terrain.DEFAULT_ISLAND_SIGNS {
        island_x := sign * half_extent * terrain.DEFAULT_ISLAND_OFFSET
        island_z := sign * half_extent * terrain.DEFAULT_ISLAND_OFFSET

        pier_inner_x := island_x + sign * half_extent * terrain.DEFAULT_PIER_INNER_OFFSET
        pier_inner_z := island_z - sign * half_extent * .08
        pier_outer_x := island_x + sign * half_extent * terrain.DEFAULT_ISLAND_RADIUS
        pier_outer_z := island_z - sign * half_extent * .16
        pier_width := half_extent * .035
        pier_inner_height := terrain.sample_height(&editor.project, level, pier_inner_x, pier_inner_z) + .09
        pier_outer_height := editor.project.sea_level + .09
        draw_quad_3d(
            camera,
            {pier_inner_x, pier_inner_height, pier_inner_z - pier_width},
            {pier_outer_x, pier_outer_height, pier_outer_z - pier_width},
            {pier_outer_x, pier_outer_height, pier_outer_z + pier_width},
            {pier_inner_x, pier_inner_height, pier_inner_z + pier_width},
            width,
            height,
            {r = 137, g = 89, b = 48, a = 255},
        )
    }

    if editor.postale_visible do draw_postale_3d(editor, camera, width, height)
    // The spawned inspection craft is a world object; keep it in the
    // infrastructure pass even when the parked-vehicle presentation toggles.
    draw_libellula_3d(editor, camera, width, height)
}

draw_terrain_3d :: proc(editor: ^Editor, width, height: i32) {
    sky := atmosphere.sample(&editor.atmosphere)
    horizon_day := rl.Color {
        r = 154,
        g = 205,
        b = 224,
        a = 255,
    }
    horizon_night := rl.Color {
        r = 19,
        g = 28,
        b = 55,
        a = 255,
    }
    sky_color := color_lerp(horizon_night, horizon_day, sky.daylight)
    storm_horizon := rl.Color {
        r = 104,
        g = 122,
        b = 130,
        a = 255,
    }
    sky_color = color_lerp(sky_color, storm_horizon, sky.weather.severity * .72)
    // The fallback extends the ocean beyond the finite detail mesh. Match the
    // lit water presentation so the near-plane edge never becomes visible.
    ocean_color := rl.Color {
        r = 86,
        g = 146,
        b = 165,
        a = 255,
    }
    rl.ClearBackground(ocean_color)
    camera := perspective_camera(editor.camera_pose)
    // Build terrain in camera-space order: far rows first give the canvas pass
    // stable painter's depth while each face is still perspective-projected.
    forward_flat := linalg.normalize0(third_person.Vec3{camera.forward.x, 0, camera.forward.z})
    right_flat := linalg.normalize0(third_person.Vec3{camera.right.x, 0, camera.right.z})
    horizon := project_3d(
        camera,
        {
            camera.position.x + forward_flat.x * 10000,
            editor.project.sea_level,
            camera.position.z + forward_flat.z * 10000,
        },
        width,
        height,
    )
    if horizon.visible {
        horizon_y := i32(clamp(horizon.position.y, 0, f32(height)))
        rl.DrawRectangle(0, 0, width, horizon_y + 1, sky_color)
    }
    // Match the finest clipmap spacing. Sampling every other heightfield point
    // made nearby slopes visibly faceted and discarded half of the authored
    // terrain detail.
    cell_size := editor.project.levels[0].cell_size
    // Keep the same world-space coverage as the former two-unit grid.
    near_rows := 48
    far_rows := 176
    side_rows := 180
    light_direction := linalg.normalize0(third_person.Vec3{-.45, .85, -.3})
    fog_start := f32(terrain.WORLD_SIZE_METERS * .55)
    fog_end := f32(terrain.WORLD_SIZE_METERS * 1.5)
    for depth_order in 0 ..< near_rows + far_rows {
        depth_index := near_rows + far_rows - 1 - depth_order
        depth := f32(depth_index - near_rows) * cell_size
        for side_index in -side_rows ..= side_rows {
            side := f32(side_index) * cell_size
            base_x := editor.camera_pose.target.x + forward_flat.x * depth + right_flat.x * side
            base_z := editor.camera_pose.target.z + forward_flat.z * depth + right_flat.z * side
            next_x := base_x + right_flat.x * cell_size
            next_z := base_z + right_flat.z * cell_size
            far_x := base_x + forward_flat.x * cell_size
            far_z := base_z + forward_flat.z * cell_size
            far_next_x := far_x + right_flat.x * cell_size
            far_next_z := far_z + right_flat.z * cell_size
            h00 := terrain.sample_height(&editor.project, 0, base_x, base_z)
            h10 := terrain.sample_height(&editor.project, 0, next_x, next_z)
            h01 := terrain.sample_height(&editor.project, 0, far_x, far_z)
            h11 := terrain.sample_height(&editor.project, 0, far_next_x, far_next_z)
            p00 := project_3d(camera, {base_x, h00, base_z}, width, height)
            p10 := project_3d(camera, {next_x, h10, next_z}, width, height)
            p11 := project_3d(camera, {far_next_x, h11, far_next_z}, width, height)
            p01 := project_3d(camera, {far_x, h01, far_z}, width, height)
            if !(p00.visible && p10.visible && p11.visible && p01.visible) do continue
            average_height := (h00 + h10 + h11 + h01) * .25
            surface_right := third_person.Vec3{next_x - base_x, h10 - h00, next_z - base_z}
            surface_forward := third_person.Vec3{far_x - base_x, h01 - h00, far_z - base_z}
            surface_normal := linalg.normalize0(linalg.cross(surface_right, surface_forward))
            diffuse := max(linalg.dot(surface_normal, light_direction), 0)
            shade := clamp(.52 + diffuse * .48 + average_height * .012, .42, 1.05)
            base_color := terrain_color(
                average_height,
                terrain.sample_material(&editor.project, 0, base_x, base_z),
                editor.project.sea_level,
                (base_x + far_next_x) * .5,
                (base_z + far_next_z) * .5,
            )
            color := rl.Color {
                r = u8(f32(base_color.r) * shade),
                g = u8(f32(base_color.g) * shade),
                b = u8(f32(base_color.b) * shade),
                a = 255,
            }
            average_depth := (p00.depth + p10.depth + p11.depth + p01.depth) * .25
            fog := clamp((average_depth - fog_start) / (fog_end - fog_start), 0, 1)
            color = color_lerp(color, sky_color, fog)
            rl.DrawQuadHatched(p00.position, p10.position, p11.position, p01.position, color, rl.HATCH_DISABLED)
        }
    }

    draw_infrastructure_3d(editor, camera, width, height)

    if editor.in_map && editor.pilot.mode == .On_Foot {
        // A compact articulated silhouette grounds the character in the 3D world.
        p := editor.player.position
        body := rl.Color {
            r = 42,
            g = 213,
            b = 201,
            a = 255,
        }
        skin := rl.Color {
            r = 247,
            g = 221,
            b = 167,
            a = 255,
        }
        draw_line_3d(camera, {p.x, p.y + .2, p.z}, {p.x, p.y + 1.35, p.z}, width, height, 7, body)
        draw_line_3d(camera, {p.x, p.y + 1.35, p.z}, {p.x, p.y + 1.62, p.z}, width, height, 12, skin)
        forward := third_person.Vec3 {
            -math.sin(editor.player.facing_yaw_radians),
            0,
            -math.cos(editor.player.facing_yaw_radians),
        }
        draw_line_3d(
            camera,
            {p.x, p.y + 1.12, p.z},
            {p.x + forward.x * .48, p.y + 1.12, p.z + forward.z * .48},
            width,
            height,
            4,
            skin,
        )

    }

    if editor.in_map && !editor.capture_world_only {
        flying := driving_aircraft(editor)
        in_car := driving_car(editor)
        driving := flying || in_car
        panel_width := driving ? i32(650) : i32(430)
        if flying && editor.aircraft.active != .Postale do panel_width = 800
        help_text: cstring = "WASD move  Mouse look  Wheel zoom  Space jump  Esc pause"
        if controller_prompt_active(editor) {
            panel_width = 790
            help_text = fmt.ctprintf(
                "LS move  RS look  LT/RT zoom  %s jump/drift  %s run  %s interact  Start pause",
                controller_face_label(editor, .South),
                controller_face_label(editor, .North),
                controller_face_label(editor, .West),
            )
        }
        if flying {
            help_text = "W/S pitch  A/D roll  Q/E yaw  Mouse orbit  C camera  Shift/Ctrl power  F exit  R reset"
            if controller_prompt_active(editor) {
                panel_width = 940
                help_text = fmt.ctprintf(
                    "LS fly  RS camera  LB/RB yaw  LT/RT power  %s recenter  %s exit  %s reset",
                    controller_face_label(editor, .South),
                    controller_face_label(editor, .West),
                    controller_face_label(editor, .North),
                )
            }
            if editor.aircraft.active != .Postale {
                help_text = "W/S pitch  A/D roll  Q/E yaw  Shift climb  Ctrl descend  Release to hover  F exit  R reset"
                if controller_prompt_active(editor) {
                    help_text = fmt.ctprintf(
                        "LS fly  RS camera  LB/RB yaw  LT/RT altitude  %s recenter  %s exit  %s reset",
                        controller_face_label(editor, .South),
                        controller_face_label(editor, .West),
                        controller_face_label(editor, .North),
                    )
                }
            }
        }
        if in_car {
            help_text = "W/S drive  A/D steer  Space handbrake  F exit  Esc pause"
            if controller_prompt_active(editor) {
                panel_width = 760
                help_text = fmt.ctprintf(
                    "LT/RT drive  LS steer  RS look  RB handbrake  %s exit  Start pause",
                    controller_face_label(editor, .West),
                )
            }
        }
        panel_width = min(panel_width, width - 28)
        rl.DrawRectangle(14, 14, panel_width, 72, {r = 8, g = 28, b = 45, a = 210})
        rl.DrawTextEx(
            rl.Font{},
            flying ? fmt.ctprintf("%s FLIGHT", vehicles.aircraft_kind_name(editor.aircraft.active)) : (in_car ? "DRIVING" : "ON FOOT"),
            {26, 25},
            19,
            1,
            {r = 211, g = 250, b = 242, a = 255},
        )
        rl.DrawTextEx(rl.Font{}, help_text, {26, 49}, 13, 1, {r = 183, g = 219, b = 221, a = 255})
        if flying {
            aircraft_body := active_aircraft_body(editor)
            ground := postale_game.drivable_surface_height(
                terrain.sample_height(&editor.project, 0, aircraft_body.position.x, aircraft_body.position.z),
                editor.project.sea_level,
            )
            altitude := max(f32(0), aircraft_body.position.y - ground - active_aircraft_ground_clearance(editor))
            hud := fmt.tprintf(
                "THR %3.0f%%   AIR %3.0f m/s   ALT %3.0f m",
                active_aircraft_throttle(editor) * 100,
                active_aircraft_airspeed(editor),
                altitude,
            )
            rl.DrawTextEx(rl.Font{}, fmt.ctprintf("%s", hud), {26, 68}, 13, 1, {r = 236, g = 239, b = 190, a = 255})
            draw_flight_instruments(editor, width, height, altitude)
            crashed := editor.aircraft.active != .Postale ? editor.libellula.crashed : editor.postale.crashed
            if editor.aircraft.active == .Postale &&
               editor.postale.landing_feedback_seconds > 0 &&
               editor.postale.last_landing.outcome != .None {
                landing := editor.postale.last_landing
                color := rl.Color{92, 219, 213, 255}
                if landing.outcome == .Landed do color = {239, 203, 111, 255}
                if landing.outcome == .Hard_Landing do color = {255, 151, 83, 255}
                label := postale_game.landing_outcome_label(landing.outcome)
                detail := fmt.ctprintf(
                    "%.1f g   %.0f kN   DAMAGE %.0f%%",
                    landing.load_factor,
                    landing.impact_force / 1000,
                    editor.postale.structural_damage * 100,
                )
                label_size := rl.MeasureTextEx(rl.Font{}, label, 22, 1)
                detail_size := rl.MeasureTextEx(rl.Font{}, detail, 13, 1)
                rl.DrawTextEx(rl.Font{}, label, {f32(width) * .5 - label_size.x * .5, 28}, 22, 1, color)
                rl.DrawTextEx(rl.Font{}, detail, {f32(width) * .5 - detail_size.x * .5, 54}, 13, 1, color)
            }
            if crashed {
                rl.DrawRectangle(width / 2 - 155, height / 2 - 35, 310, 70, {r = 71, g = 18, b = 20, a = 225})
                reset_key: cstring = controller_prompt_active(editor) ? controller_face_label(editor, .North) : "R"
                rl.DrawTextEx(
                    rl.Font{},
                    fmt.ctprintf(
                        "%s CRASHED — PRESS %s TO RESET",
                        vehicles.aircraft_kind_name(editor.aircraft.active),
                        reset_key,
                    ),
                    {f32(width / 2 - 139), f32(height / 2 - 8)},
                    16,
                    1,
                    {r = 255, g = 221, b = 195, a = 255},
                )
            } else if editor.aircraft.active == .Postale && editor.postale.telemetry.is_stalling {
                rl.DrawTextEx(
                    rl.Font{},
                    "STALL",
                    {f32(width / 2 - 28), 28},
                    22,
                    1,
                    {r = 255, g = 110, b = 83, a = 255},
                )
            }
        } else {
            delta := (editor.player.position - editor.postale.vehicle.position)
            if linalg.dot(delta, delta) <=
               editor.postale.vehicle.interaction_radius * editor.postale.vehicle.interaction_radius {
                rl.DrawRectangle(width / 2 - 116, height - 92, 232, 42, {r = 8, g = 28, b = 45, a = 220})
                entry_prompt: cstring = "PRESS F TO ENTER POSTALE"
                if controller_prompt_active(editor) {
                    entry_prompt = fmt.ctprintf("PRESS %s TO ENTER POSTALE", controller_face_label(editor, .West))
                }
                rl.DrawTextEx(
                    rl.Font{},
                    entry_prompt,
                    {f32(width / 2 - 99), f32(height - 77)},
                    15,
                    1,
                    {r = 245, g = 239, b = 192, a = 255},
                )
            }
        }
    } else {
        world_x, world_z, hit := world_under_cursor_3d(
            camera,
            rl.GetMousePosition(),
            width,
            height,
            terrain.DEFAULT_ISLAND_HEIGHT,
        )
        if hit {
            brush_height := terrain.sample_height(&editor.project, 0, world_x, world_z) + .08
            brush_center := project_3d(camera, {world_x, brush_height, world_z}, width, height)
            brush_edge := project_3d(camera, {world_x + editor.radius, brush_height, world_z}, width, height)
            if brush_center.visible && brush_edge.visible {
                brush_radius := f32(
                    math.sqrt(
                        f64(
                            (brush_edge.position.x - brush_center.position.x) *
                                (brush_edge.position.x - brush_center.position.x) +
                            (brush_edge.position.y - brush_center.position.y) *
                                (brush_edge.position.y - brush_center.position.y),
                        ),
                    ),
                )
                rl.DrawCircleV(brush_center.position, brush_radius, {r = 230, g = 244, b = 218, a = 55})
            }
        }
        rl.DrawRectangle(14, 14, 520, 42, {r = 8, g = 28, b = 45, a = 210})
        rl.DrawTextEx(
            rl.Font{},
            "WASD pan  Q/E rotate  Middle orbit  Wheel zoom  Shift+wheel strength  Left/Right brush",
            {26, 29},
            12,
            1,
            {r = 183, g = 219, b = 221, a = 255},
        )
        draw_spawn_button()
    }
    minutes := int(sky.world_minutes)
    weather_label := atmosphere.preset_name(editor.atmosphere.override)
    clock := fmt.tprintf(
        "%02d:%02d  %s%s  [P] pause  [←/→] time  [4] auto  [1/2/3] weather",
        minutes / 60,
        minutes % 60,
        weather_label,
        editor.atmosphere.paused ? " PAUSED" : "",
    )
    rl.DrawTextEx(
        rl.Font{},
        fmt.ctprintf("%s", clock),
        {f32(width) - 545, 18},
        13,
        1,
        {r = 224, g = 239, b = 231, a = 240},
    )
}

draw_default_infrastructure :: proc(editor: ^Editor, center: rl.Vector2, scale: f32) {
    level := 0
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    for sign in terrain.DEFAULT_ISLAND_SIGNS {
        island_x := sign * half_extent * terrain.DEFAULT_ISLAND_OFFSET
        island_z := sign * half_extent * terrain.DEFAULT_ISLAND_OFFSET

        // A short wooden pier points from the island toward its nearby map edge.
        pier_inner_x := island_x + sign * half_extent * terrain.DEFAULT_PIER_INNER_OFFSET
        pier_inner_z := island_z - sign * half_extent * .08
        // End at the shoreline without extending beyond the finite terrain map.
        pier_outer_x := island_x + sign * half_extent * terrain.DEFAULT_ISLAND_RADIUS
        pier_outer_z := island_z - sign * half_extent * .16
        pier_width := half_extent * .035
        p0 := project_point(
            pier_inner_x,
            pier_inner_z - pier_width,
            terrain.sample_height(&editor.project, level, pier_inner_x, pier_inner_z) + .08,
            center,
            scale,
        )
        p1 := project_point(pier_outer_x, pier_outer_z - pier_width, editor.project.sea_level + .08, center, scale)
        p2 := project_point(pier_outer_x, pier_outer_z + pier_width, editor.project.sea_level + .08, center, scale)
        p3 := project_point(
            pier_inner_x,
            pier_inner_z + pier_width,
            terrain.sample_height(&editor.project, level, pier_inner_x, pier_inner_z) + .08,
            center,
            scale,
        )
        rl.DrawQuadHatched(p0, p1, p2, p3, {r = 137, g = 89, b = 48, a = 255}, rl.HATCH_DISABLED)
    }
}

draw_infinite_ocean :: proc(width, height: i32, time: f32) {
    rl.ClearBackground({r = 14, g = 54, b = 79, a = 255})
    for row in 0 ..< 24 {
        y := f32(row) * f32(height) / 23
        phase := f32(math.sin(f64(time * .9 + f32(row) * .73)))
        rl.DrawLineEx({0, y}, {f32(width), y + phase * 3}, 1, {r = 35, g = 102, b = 128, a = 110})
    }
}

editor_palette_bounds :: proc() -> rl.Rectangle {
    return {x = 20, y = 116, width = 830, height = 38}
}

editor_palette_button_bounds :: proc(index: int) -> rl.Rectangle {
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

editor_palette_index :: proc(position: rl.Vector2) -> int {
    for index in 0 ..< 9 {
        if rl.CheckCollisionPointRec(position, editor_palette_button_bounds(index)) do return index
    }
    return -1
}

draw_editor_palette :: proc(editor: ^Editor) {
    palette := editor_palette_bounds()
    rl.DrawRectangleRounded(palette, .16, 8, {r = 8, g = 28, b = 45, a = 242})
    labels := [?]cstring {
        "SCULPT [Q]",
        "SMOOTH [E]",
        "PAINT [T]",
        "FORMATIONS [B]",
        "RIDGE [Z]",
        "CLIFF [C]",
        "CITY [N]",
        "VINES [L]",
        "ROADS [M]",
    }
    for index in 0 ..< 9 {
        button := editor_palette_button_bounds(index)
        selected :=
            editor.tool == editor_palette_tool(index) &&
            ((editor_palette_curve_mode(index) && editor.curve_mode && (index == 5) == editor.curve_cliff_mode) ||
                    (editor_palette_architecture_mode(index) && editor.architecture_paint_mode) ||
                    (editor_palette_climbing_leaves_mode(index) && editor.climbing_leaf_paint_mode) ||
                    (editor_palette_road_mode(index) && editor.road_mode) ||
                    (!editor_palette_curve_mode(index) &&
                            !editor_palette_architecture_mode(index) &&
                            !editor_palette_climbing_leaves_mode(index) &&
                            !editor_palette_road_mode(index) &&
                            !editor.curve_mode &&
                            !editor.architecture_paint_mode &&
                            !editor.climbing_leaf_paint_mode &&
                            !editor.road_mode))
        hovered := rl.CheckCollisionPointRec(rl.GetMousePosition(), button)
        fill: rl.Color = {
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
        border: rl.Color = {
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
        rl.DrawRectangleRounded(button, .14, 8, fill)
        rl.DrawRectangleRoundedLinesEx(button, .14, 8, selected ? 2 : 1, border)
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

spawn_button_bounds :: proc() -> rl.Rectangle { return {x = 20, y = 164, width = 170, height = 34} }

editor_overlay_hit :: proc(position: rl.Vector2, width, height: i32) -> bool {
    // These regions are drawn above the viewport and must be treated as UI even
    // when they contain only status text. Otherwise a press on the HUD can
    // begin a terrain stroke through the transparent parts of the overlay.
    if rl.CheckCollisionPointRec(position, {x = 14, y = 14, width = 826, height = 96}) do return true
    if rl.CheckCollisionPointRec(position, {x = f32(width) - 560, y = 14, width = 546, height = 40}) do return true
    if rl.CheckCollisionPointRec(position, {x = 20, y = 210, width = 830, height = 30}) do return true
    return false
}

draw_spawn_button :: proc() {
    bounds := spawn_button_bounds()
    hovered := rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds)
    fill := rl.Color {
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
    rl.DrawRectangleRounded(bounds, .18, 8, fill)
    rl.DrawRectangleRoundedLinesEx(bounds, .18, 8, 1, {r = 176, g = 239, b = 230, a = 255})
    ui_draw_text(.Body, "ENTER WORLD", {bounds.x + 28, bounds.y + 9}, 1, {r = 245, g = 255, b = 247, a = 255})
}

draw_editor_context :: proc(editor: ^Editor) {
    if editor == nil || editor.in_map do return
    message: string = ""
    if editor.road_mode {
        if editor.road_drag_edge >= 0 {
            message = "CURVING ROAD  |  drag handle  LMB release commit  Esc cancel"
        } else if editor.road_selected_node >= 0 {
            message = fmt.tprintf(
                "NODE %d  |  LMB add/connect  drag handles  K surface  Wheel zoom  Alt width  Shift radius",
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
            editor.architecture_brush_radius,
        )
    } else if editor.climbing_leaf_painting {
        message = fmt.tprintf(
            "PAINTING CLIMBING LEAVES  radius %.0f m  |  LMB spread  RMB erase  Wheel zoom  Shift spread  Alt hardness",
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
    rl.DrawRectangleRounded({20, 210, 830, 30}, .14, 8, {r = 8, g = 28, b = 45, a = 230})
    ui_draw_text(.Data, fmt.ctprintf("%s", message), {30, 219}, 1, {r = 255, g = 244, b = 190, a = 255})
}

runway_spawn_position :: proc(editor: ^Editor) -> third_person.Vec3 {
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    x := half_extent * terrain.DEFAULT_ISLAND_OFFSET + half_extent * terrain.DEFAULT_RUNWAY_SPAWN_OFFSET
    // Start beside the parked aircraft so the default camera presents it and
    // the runway immediately instead of placing the character inside its mesh.
    z := half_extent * terrain.DEFAULT_ISLAND_OFFSET + 2.2
    return {x, terrain.sample_height(&editor.project, 0, x, z), z}
}

car_spawn_position :: proc(editor: ^Editor) -> third_person.Vec3 {
    // Park the car on the apron beside the runway rather than on the flight
    // surface. This keeps the aircraft arrival lane clear while leaving the car
    // close enough to reach from the default player spawn.
    runway := runway_spawn_position(editor)
    spawn := vehicles.car_spawn_near({runway.x + 8, runway.y, runway.z + 4})
    spawn.y = terrain.sample_height(&editor.project, 0, spawn.x, spawn.z)
    return spawn
}

@(no_instrumentation)
driving_aircraft :: #force_inline proc(editor: ^Editor) -> bool {
    if editor == nil || editor.pilot.mode != .Driving do return false
    return editor.pilot.vehicle == &editor.postale.vehicle || editor.pilot.vehicle == &editor.libellula.vehicle
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

car_physics_level_heights :: proc(editor: ^Editor, level_index: int, result: []f32) {
    if editor == nil ||
       level_index < 0 ||
       level_index >= terrain.CLIPMAP_LEVELS ||
       len(result) < terrain.SAMPLES_PER_LEVEL {
        return
    }
    level := &editor.project.levels[level_index]
    copy(result, level.heights[:])
    if level_index == 0 do return
    finer := &editor.project.levels[level_index - 1]
    // Preserve one coarse-cell apron. Since even-sized grids at successive
    // resolutions cannot share both boundary vertices exactly, the overlap is
    // safer than allowing no-collision vertices to remove the seam triangles.
    apron := level.cell_size
    finer_extent := f32(terrain.RING_RESOLUTION - 1) * finer.cell_size
    for z in 0 ..< terrain.RING_RESOLUTION {
        world_z := level.origin_z + f32(z) * level.cell_size
        for x in 0 ..< terrain.RING_RESOLUTION {
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

car_physics_create :: proc(editor: ^Editor) {
    if editor == nil || editor.car_physics_world != nil do return
    editor.car_physics_world = physics.create_world(128, 1)
    physics.set_gravity(editor.car_physics_world, {0, -9.81, 0})
    ground := terrain.sample_height(&editor.project, 0, editor.car.position.x, editor.car.position.z)
    collision_heights := make([]f32, terrain.SAMPLES_PER_LEVEL)
    defer delete(collision_heights)
    for level_index in 0 ..< terrain.CLIPMAP_LEVELS {
        level := &editor.project.levels[level_index]
        car_physics_level_heights(editor, level_index, collision_heights)
        editor.car_physics_terrain[level_index] = physics.add_height_field(
            editor.car_physics_world,
            collision_heights,
            terrain.RING_RESOLUTION,
            {level.origin_x, 0, level.origin_z},
            {level.cell_size, 1, level.cell_size},
            4,
            8,
        )
        if editor.car_physics_terrain[level_index] == physics.INVALID_BODY {
            physics.destroy_world(editor.car_physics_world)
            editor.car_physics_world = nil
            return
        }
    }
    editor.car_physics_terrain_revision = editor.project.revision
    editor.car_physics_vehicle = physics.create_vehicle(editor.car_physics_world, {
            half_width              = .67,
            half_height             = .25,
            half_length             = 1.22,
            mass                    = 720,
            center_of_mass_offset_y = -.18,
            wheel_x                 = vehicles.CAR_WHEEL_TRACK_HALF,
            front_wheel_z           = vehicles.CAR_WHEELBASE_HALF,
            rear_wheel_z            = -vehicles.CAR_WHEELBASE_HALF,
            wheel_y                 = -.20,
            wheel_radius            = vehicles.CAR_WHEEL_RADIUS,
            wheel_width             = vehicles.CAR_WHEEL_WIDTH,
            suspension_min          = .08,
            suspension_max          = .30,
            suspension_frequency    = 2.4,
            suspension_damping      = .9,
            max_steer_angle         = math.PI * .19,
            max_engine_torque       = 520,
            max_brake_torque        = 1100,
            max_handbrake_torque    = 1400,
            four_wheel_drive        = false,
        }, {editor.car.position.x, ground + .74, editor.car.position.z}, car_physics_rotation(editor.car.yaw_radians))
    if editor.car_physics_vehicle == nil {
        physics.destroy_world(editor.car_physics_world)
        editor.car_physics_world = nil
        for level_index in 0 ..< terrain.CLIPMAP_LEVELS {
            editor.car_physics_terrain[level_index] = physics.INVALID_BODY
        }
    }
}

car_physics_destroy :: proc(editor: ^Editor) {
    if editor == nil || editor.car_physics_world == nil do return
    physics.destroy_world(editor.car_physics_world)
    editor.car_physics_world = nil
    editor.car_physics_vehicle = nil
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
    if reset_velocity {
        editor.car_drive = {}
        editor.car_physics_accumulator = 0
    }
}

car_physics_step :: proc(
    editor: ^Editor,
    throttle, steering: f32,
    handbrake: bool,
    surface: vehicles.Car_Drive_Surface,
    delta_seconds: f32,
) -> (
    impact_severity, impact_slide_speed, impact_obliqueness: f32,
) {
    if editor == nil || editor.car_physics_vehicle == nil || delta_seconds <= 0 do return
    body := physics.vehicle_body(editor.car_physics_vehicle)
    velocity := physics.get_linear_velocity(editor.car_physics_world, body)
    velocity_before := velocity
    forward := physics.Vec3{math.cos(editor.car.yaw_radians), 0, math.sin(editor.car.yaw_radians)}
    longitudinal := velocity[0] * forward[0] + velocity[2] * forward[2]
    brake := f32(0)
    drive := throttle
    if throttle > .01 && longitudinal < -.5 {
        brake, drive = throttle, 0
    } else if throttle < -.01 && longitudinal > .5 {
        brake, drive = -throttle, 0
    }
    physics.set_vehicle_input(
        editor.car_physics_world,
        editor.car_physics_vehicle,
        drive,
        steering,
        brake,
        handbrake ? 1 : 0,
    )
    physics.set_vehicle_grip(
        editor.car_physics_vehicle,
        surface.longitudinal_grip,
        surface.lateral_grip * (handbrake ? f32(.22) : f32(1)),
    )

    if editor.project.revision != editor.car_physics_terrain_revision {
        updated := true
        collision_heights := make([]f32, terrain.SAMPLES_PER_LEVEL)
        defer delete(collision_heights)
        for level_index in 0 ..< terrain.CLIPMAP_LEVELS {
            level := &editor.project.levels[level_index]
            car_physics_level_heights(editor, level_index, collision_heights)
            updated =
                physics.update_height_field(
                    editor.car_physics_world,
                    editor.car_physics_terrain[level_index],
                    0,
                    0,
                    terrain.RING_RESOLUTION,
                    terrain.RING_RESOLUTION,
                    collision_heights,
                    terrain.RING_RESOLUTION,
                ) &&
                updated
        }
        if updated {
            editor.car_physics_terrain_revision = editor.project.revision
        }
    }
    editor.car_physics_accumulator = min(editor.car_physics_accumulator + f64(delta_seconds), f64(.1))
    for editor.car_physics_accumulator >= 1.0 / 120.0 {
        physics.step(editor.car_physics_world, 1.0 / 120.0, 2)
        editor.car_physics_accumulator -= 1.0 / 120.0
    }

    position, body_rotation, body_ok := physics.get_transform(editor.car_physics_world, body)
    if !body_ok do return
    velocity = physics.get_linear_velocity(editor.car_physics_world, body)
    impact_severity, impact_slide_speed, impact_obliqueness = engine_sound.detect_vehicle_impact(
        &editor.car_impact_detector,
        velocity_before[0],
        velocity_before[1],
        velocity_before[2],
        velocity[0],
        velocity[1],
        velocity[2],
        delta_seconds,
    )
    previous_yaw := editor.car.yaw_radians
    editor.car.position = {position[0], position[1] - .74, position[2]}
    editor.car.yaw_radians = car_physics_yaw(body_rotation)
    x, y, z, w := body_rotation[0], body_rotation[1], body_rotation[2], body_rotation[3]
    editor.car_drive.body_pitch = math.asin(clamp(2 * (y * z - w * x), -1, 1))
    editor.car_drive.body_roll = math.asin(clamp(2 * (x * y + w * z), -1, 1))
    dt := max(delta_seconds, f32(.001))
    longitudinal_after := velocity[0] * forward[0] + velocity[2] * forward[2]
    acceleration_target := clamp(
        (longitudinal_after - longitudinal) / dt / max(vehicles.CAR_DRIVE_SEDAN_TUNE.acceleration, f32(1)),
        -1,
        1,
    )
    editor.car_drive.acceleration_feedback +=
        (acceleration_target - editor.car_drive.acceleration_feedback) * clamp(6 * dt, 0, 1)
    editor.car_drive.velocity = {velocity[0], velocity[1], velocity[2]}
    editor.car_drive.wheel_speed = longitudinal
    editor.car_drive.steering += (steering - editor.car_drive.steering) * clamp(10 * dt, 0, 1)
    yaw_delta := editor.car.yaw_radians - previous_yaw
    for yaw_delta > math.PI do yaw_delta -= 2 * math.PI
    for yaw_delta < -math.PI do yaw_delta += 2 * math.PI
    editor.car_drive.yaw_rate = yaw_delta / dt
    editor.car_drive.handbrake_amount +=
        ((handbrake ? f32(1) : f32(0)) - editor.car_drive.handbrake_amount) * clamp(8 * dt, 0, 1)
    lateral := velocity[0] * -forward[2] + velocity[2] * forward[0]
    editor.car_drive.slip_amount +=
        (clamp(math.abs(lateral) / 8, 0, 1) - editor.car_drive.slip_amount) * clamp(8 * dt, 0, 1)
    for index in 0 ..< 4 {
        wheel_state, wheel_ok := physics.get_wheel_state(editor.car_physics_vehicle, u32(index))
        if !wheel_ok do continue
        editor.car_wheels[index] = wheel_state
        wheel := editor.car_wheels[index]
        _, wheel_surface := road_car_surface(editor, {wheel.position[0], wheel.position[1], wheel.position[2]})
        physics.set_vehicle_wheel_grip(
            editor.car_physics_vehicle,
            u32(index),
            wheel_surface.longitudinal_grip,
            wheel_surface.lateral_grip,
        )
    }
    return
}

car_trailer_hitch_position :: proc(editor: ^Editor, trailer: bool = false) -> third_person.Vec3 {
    if editor == nil do return {}
    origin := editor.car.position
    yaw := editor.car.yaw_radians
    if trailer && !editor.car_trailer_attached {
        origin = editor.car_trailer_position
        yaw = editor.car_trailer_yaw
    }
    hitch_z := trailer ? f32(1.36) : f32(1.48)
    return {origin.x - math.cos(yaw) * hitch_z, origin.y, origin.z - math.sin(yaw) * hitch_z}
}

car_trailer_can_attach :: proc(editor: ^Editor) -> bool {
    if editor == nil || editor.car_trailer_attached do return false
    delta := (car_trailer_hitch_position(editor) - car_trailer_hitch_position(editor, true))
    close := delta.x * delta.x + delta.z * delta.z <= .72 * .72
    yaw_delta := editor.car.yaw_radians - editor.car_trailer_yaw
    for yaw_delta > math.PI do yaw_delta -= math.PI * 2
    for yaw_delta < -math.PI do yaw_delta += math.PI * 2
    return close && math.abs(yaw_delta) <= .48
}

car_trailer_interaction_near :: proc(editor: ^Editor) -> bool {
    if editor == nil || editor.pilot.mode != .On_Foot do return false
    hitch := car_trailer_hitch_position(editor, !editor.car_trailer_attached)
    delta := (editor.player.position - hitch)
    return delta.x * delta.x + delta.z * delta.z <= 1.45 * 1.45
}

car_trailer_interact :: proc(editor: ^Editor) -> bool {
    if editor == nil || !car_trailer_interaction_near(editor) do return false
    if editor.car_trailer_attached {
        editor.car_trailer_position = editor.car.position
        editor.car_trailer_yaw = editor.car.yaw_radians
        editor.car_trailer.velocity = editor.car_drive.velocity
        editor.car_trailer.yaw_rate = editor.car_drive.yaw_rate
        editor.car_trailer_attached = false
        return true
    }
    if !car_trailer_can_attach(editor) do return false
    editor.car_trailer_position = editor.car.position
    editor.car_trailer_yaw = editor.car.yaw_radians
    editor.car_trailer.velocity = editor.car_drive.velocity
    editor.car_trailer.yaw_rate = editor.car_drive.yaw_rate
    editor.car_trailer_attached = true
    return true
}

vehicle_entry_prompt :: proc(editor: ^Editor) -> cstring {
    if editor == nil || editor.pilot.mode != .On_Foot do return nil
    car_delta := (editor.player.position - editor.car.position)
    car_distance := linalg.dot(car_delta, car_delta)
    car_radius := editor.car.interaction_radius
    if car_radius <= 0 do car_radius = 2.5
    aircraft := active_aircraft_vehicle(editor)
    aircraft_delta := (editor.player.position - aircraft.position)
    aircraft_distance := linalg.dot(aircraft_delta, aircraft_delta)
    aircraft_radius := aircraft.interaction_radius
    if aircraft_radius <= 0 do aircraft_radius = 2.5
    attendant_resident, _, attendant_near := nearest_service_attendant(editor)
    dockmaster_near := markov_marina_dockmaster_near(editor)
    story_resident, _, story_near := nearest_story_resident(editor, require_action = true)
    trailer_near := car_trailer_interaction_near(editor)
    car_near := car_distance <= car_radius * car_radius
    aircraft_near := aircraft_distance <= aircraft_radius * aircraft_radius
    if trailer_near {
        if editor.car_trailer_attached do return "PRESS F TO DETACH TRAILER"
        if car_trailer_can_attach(editor) do return "PRESS F TO ATTACH TRAILER"
        return "ALIGN CAR TO ATTACH TRAILER"
    }
    if dockmaster_near {
        if controller_prompt_active(editor) {
            return fmt.ctprintf("PRESS %s TO TALK TO VESNA", controller_face_label(editor, .West))
        }
        return "PRESS F TO TALK TO VESNA"
    }
    if story_near {
        if controller_prompt_active(editor) {
            return fmt.ctprintf(
                "PRESS %s TO TALK TO %s",
                controller_face_label(editor, .West),
                story.resident_name(story_resident),
            )
        }
        return fmt.ctprintf("PRESS F TO TALK TO %s", story.resident_name(story_resident))
    }
    if car_near && (!aircraft_near || car_distance <= aircraft_distance) {
        if controller_prompt_active(editor) {
            return fmt.ctprintf("PRESS %s TO ENTER CAR", controller_face_label(editor, .West))
        }
        return "PRESS F TO ENTER CAR"
    }
    if aircraft_near {
        if controller_prompt_active(editor) {
            return fmt.ctprintf(
                "PRESS %s TO ENTER %s",
                controller_face_label(editor, .West),
                vehicles.aircraft_kind_name(editor.aircraft.active),
            )
        }
        return fmt.ctprintf("PRESS F TO ENTER %s", vehicles.aircraft_kind_name(editor.aircraft.active))
    }
    if attendant_near {
        if controller_prompt_active(editor) {
            return fmt.ctprintf(
                "PRESS %s TO TALK TO %s",
                controller_face_label(editor, .West),
                story.resident_name(attendant_resident),
            )
        }
        return fmt.ctprintf("PRESS F TO TALK TO %s", story.resident_name(attendant_resident))
    }
    return nil
}

vehicle_showcase_camera_step :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil do return
    if rl.IsMouseButtonDown(.MIDDLE) {
        mouse_delta := rl.GetMouseDelta()
        third_person.look(&editor.camera, -mouse_delta.x, mouse_delta.y, .006)
    }
    editor.camera.distance = clamp(editor.camera.distance - rl.GetMouseWheelMove() * .7, 2.5, 30)
    editor.camera_pose = third_person.camera_pose(third_person.Vec3{0, editor.camera.height, 0}, editor.camera)
}

editor_camera_pose :: proc() -> third_person.Camera_Pose {
    island_center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    return {position = {island_center + 650, 720, island_center + 650}, target = {island_center, 1.5, island_center}}
}

draw_terrain :: proc(editor: ^Editor, width, height: i32, time: f32) {
    // The depth-tested world pass has already drawn the game/editor scene.
    // Canvas commands from here onward are deliberately UI-only.
    rl.ClearBackground({r = 104, g = 154, b = 181, a = 255})
    if editor.pause_screen == .Customization do return
    if editor.vehicle_paint_scene {
        vehicle_paint_draw(editor, width, height)
        return
    }
    if editor.vehicle_showcase_scene {
        // Vehicles and occupants are already rendered together in the
        // depth-tested world pass. Drawing a second canvas copy here would
        // cover occupants wherever they overlap the vehicle silhouette.
        return
    }
    if lab_scene_draw_ui(editor, width, height) do return
    draw_postale_speed_effects(editor, width, height, time)
    control_hint_draw_gameplay_hud(editor, width)
    if editor.in_map {
        flying := driving_aircraft(editor)
        if flying && editor.gameplay_options.show_hud {
            body := active_aircraft_body(editor)
            ground := postale_game.drivable_surface_height(
                terrain.sample_height(&editor.project, 0, body.position.x, body.position.z),
                editor.project.sea_level,
            )
            altitude := max(f32(0), body.position.y - ground - active_aircraft_ground_clearance(editor))
            draw_flight_instruments(editor, width, height, altitude)
        } else if editor.attendant_dialogue_open {
            panel := attendant_dialogue_panel(editor, width, height)
            tarot_layout_draw(editor, panel)
            rl.DrawRectangleRounded(panel, .08, 10, {8, 28, 45, 238})
            rl.DrawRectangleRoundedLinesEx(panel, .08, 10, 1, {86, 153, 158, 255})
            conversation := &editor.attendant_dialogue
            if current := dialogue.current(conversation); current != nil {
                rl.DrawTextEx(
                    rl.Font{},
                    fmt.ctprintf("%s", current.speaker(&conversation.ctx)),
                    {panel.x + 24, panel.y + 20},
                    15,
                    1,
                    {211, 250, 242, 255},
                )
                rl.DrawTextEx(
                    rl.Font{},
                    fmt.ctprintf("%s", current.text(&conversation.ctx)),
                    {panel.x + 24, panel.y + 50},
                    14,
                    1,
                    {245, 239, 192, 255},
                )
                mouse := rl.GetMousePosition()
                for index in 0 ..< dialogue.available_count(conversation) {
                    bounds := attendant_dialogue_choice_bounds(panel, index)
                    hovered := rl.CheckCollisionPointRec(mouse, bounds)
                    focused := editor.attendant_dialogue_focus == index
                    fill: rl.Color = {20, 57, 70, 255}
                    border: rl.Color = {86, 153, 158, 255}
                    if hovered do fill = {39, 91, 96, 255}
                    if focused {
                        fill = {43, 112, 119, 255}
                        border = {211, 250, 242, 255}
                    }
                    rl.DrawRectangleRounded(bounds, .16, 8, fill)
                    rl.DrawRectangleRoundedLinesEx(bounds, .16, 8, focused ? 2 : 1, border)
                    if response := dialogue.available_at(conversation, index); response != nil {
                        label := fmt.ctprintf("%s", response.text)
                        size := rl.MeasureTextEx(rl.Font{}, label, 14, 1)
                        rl.DrawTextEx(
                            rl.Font{},
                            label,
                            {bounds.x + (bounds.width - size.x) * .5, bounds.y + 10},
                            14,
                            1,
                            {239, 255, 250, 255},
                        )
                    }
                }
            }
        } else if editor.gameplay_options.show_hud {
            if prompt := vehicle_entry_prompt(editor); prompt != nil {
                rl.DrawRectangle(width / 2 - 116, height - 92, 232, 42, {8, 28, 45, 220})
                rl.DrawTextEx(rl.Font{}, prompt, {f32(width / 2 - 99), f32(height - 77)}, 15, 1, {245, 239, 192, 255})
            }
        }
    }
    if !editor.in_map && !editor.capture_world_only {
        editor_ui_draw(editor, width, height)
    }
}

hot_reload_requested :: proc(library_path: string, loaded_mtime: i64) -> bool {
    if library_path == "" do return false
    modified, err := os.modification_time_by_path(library_path)
    if err != nil do return false
    modified_mtime := time.time_to_unix_nano(modified)
    return modified_mtime > loaded_mtime
}

Loading_Postcard_Period :: enum {
    Dawn,
    Morning,
    Midday,
    Golden_Hour,
    Dusk,
    Night,
}

loading_postcard_period_for_hour :: proc(hour: int) -> Loading_Postcard_Period {
    normalized_hour := ((hour % 24) + 24) % 24
    switch normalized_hour {
    case 4 ..= 6:
        return .Dawn
    case 7 ..= 10:
        return .Morning
    case 11 ..= 15:
        return .Midday
    case 16 ..= 18:
        return .Golden_Hour
    case 19 ..= 21:
        return .Dusk
    case:
        return .Night
    }
}

loading_postcard_period_from_name :: proc(name: string) -> (Loading_Postcard_Period, bool) {
    switch name {
    case "dawn":
        return .Dawn, true
    case "morning":
        return .Morning, true
    case "midday":
        return .Midday, true
    case "golden-hour", "golden":
        return .Golden_Hour, true
    case "dusk":
        return .Dusk, true
    case "night":
        return .Night, true
    case:
        return {}, false
    }
}

loading_postcard_path :: proc(period: Loading_Postcard_Period) -> string {
    switch period {
    case .Dawn:
        return "assets/textures/ui/loading-postcard-dawn.png"
    case .Morning:
        return "assets/textures/ui/loading-postcard-morning.png"
    case .Midday:
        return "assets/textures/ui/loading-postcard-midday.png"
    case .Golden_Hour:
        return "assets/textures/ui/loading-postcard-golden-hour.png"
    case .Dusk:
        return "assets/textures/ui/loading-postcard-dusk.png"
    case .Night:
        return "assets/textures/ui/loading-postcard-night.png"
    }
    return "assets/textures/ui/loading-postcard-midday.png"
}

loading_postcard_local_hour :: proc() -> int {
    now := time.now()
    utc_datetime, datetime_ok := time.time_to_datetime(now)
    if !datetime_ok {
        hour, _, _ := time.clock(now)
        return hour
    }
    local_region, region_ok := timezone.region_load("local", context.temp_allocator)
    if !region_ok {
        hour, _, _ := time.clock(now)
        return hour
    }
    defer timezone.region_destroy(local_region, context.temp_allocator)
    local_datetime, local_ok := timezone.datetime_to_tz(utc_datetime, local_region)
    if !local_ok {
        hour, _, _ := time.clock(now)
        return hour
    }
    return int(local_datetime.hour)
}

draw_startup_loading_screen :: proc(width, height: i32, progress: f32, message: cstring, postcard: rl.Texture = {}) {
    w, h := f32(width), f32(height)
    center := rl.Vector2{w * .5, h * .5}
    scale := min(w / 1280, h / 720)
    ui_scale := max(scale, f32(.85))
    animation_time := f32(rl.GetTime())
    normalized_progress := clamp(progress, 0, 1)
    horizon := h * .52
    sun := rl.Vector2{center.x + 178 * scale, horizon - 112 * scale}
    title: cstring = "ADRIATIC"
    greeting: cstring = "GREETINGS FROM"
    title_font_size := max(48 * scale, f32(32))
    greeting_font_size := max(14 * scale, f32(11))
    message_font_size := max(14 * scale, f32(13))
    title_size := rl.MeasureTextEx(rl.Font{}, title, title_font_size, 7 * scale)
    greeting_size := rl.MeasureTextEx(rl.Font{}, greeting, greeting_font_size, 3 * scale)
    message_size := rl.MeasureTextEx(rl.Font{}, message, message_font_size, 1)
    track_width := min(w - 96, 420 * ui_scale)
    track := rl.Rectangle {
        x      = center.x - track_width * .5,
        y      = h - 72 * ui_scale,
        width  = track_width,
        height = 7 * ui_scale,
    }

    if postcard.ready {
        rl.BeginDrawing()
        rl.DrawTexturePro(
            postcard,
            {0, 0, f32(postcard.width), f32(postcard.height)},
            {0, 0, w, h},
            {255, 255, 255, 255},
        )

        // Live ink strokes retain the gentle movement of the procedural
        // version without competing with the illustrated background.
        for ripple in 0 ..< 7 {
            ripple_y := h * .73 + f32(ripple) * 18 * scale
            ripple_x :=
                center.x -
                430 * scale +
                f32((ripple * 149) % 710) * scale +
                math.sin(animation_time * .8 + f32(ripple)) * 7 * scale
            rl.DrawLineEx(
                {ripple_x, ripple_y},
                {ripple_x + (25 + f32(ripple % 3) * 11) * scale, ripple_y},
                max(1, scale),
                {225, 207, 155, 75},
            )
        }

        boat_x := center.x - 390 * scale + normalized_progress * 245 * scale
        boat_y := h * .73 + math.sin(animation_time * 1.7) * 2.5 * scale
        rl.DrawLineEx({boat_x, boat_y - 42 * scale}, {boat_x, boat_y + 2 * scale}, 2 * scale, {54, 42, 36, 255})
        for sail_row in 0 ..< 9 {
            sail_y := boat_y - (38 - f32(sail_row) * 4) * scale
            sail_width := (2 + f32(sail_row) * 2.1) * scale
            rl.DrawLineEx(
                {boat_x + 2 * scale, sail_y},
                {boat_x + 2 * scale + sail_width, sail_y},
                3.5 * scale,
                {244, 224, 177, 245},
            )
        }
        rl.DrawLineEx(
            {boat_x - 16 * scale, boat_y + 4 * scale},
            {boat_x + 22 * scale, boat_y + 4 * scale},
            7 * scale,
            {135, 59, 43, 255},
        )
        for wake in 0 ..< 3 {
            wake_y := boat_y + (11 + f32(wake) * 6) * scale
            wake_half_width := (16 + f32(wake) * 9) * scale
            rl.DrawLineEx(
                {boat_x - wake_half_width, wake_y},
                {boat_x + wake_half_width, wake_y},
                max(1, scale),
                {226, 214, 174, u8(105 - wake * 22)},
            )
        }

        rl.DrawTextEx(
            rl.Font{},
            greeting,
            {center.x - greeting_size.x * .5, 55 * ui_scale},
            greeting_font_size,
            3 * scale,
            {246, 222, 172, 230},
        )
        rl.DrawTextEx(
            rl.Font{},
            title,
            {center.x - title_size.x * .5 + 2 * scale, 77 * ui_scale + 2 * scale},
            title_font_size,
            7 * scale,
            {154, 58, 49, 210},
        )
        rl.DrawTextEx(
            rl.Font{},
            title,
            {center.x - title_size.x * .5, 76 * ui_scale},
            title_font_size,
            7 * scale,
            {248, 239, 203, 255},
        )
        rl.DrawTextEx(
            rl.Font{},
            message,
            {center.x - message_size.x * .5, track.y - 29 * ui_scale},
            message_font_size,
            1,
            {226, 226, 204, 255},
        )
        rl.DrawRectangleRounded(track, 1, 8, {5, 24, 34, 220})
        if normalized_progress > 0 {
            fill := track
            fill.width *= normalized_progress
            rl.DrawRectangleRounded(fill, 1, 8, {241, 188, 93, 255})
            if fill.width > 24 * scale {
                glint_phase := math.sin(animation_time * 1.1) * .5 + .5
                glint_x := fill.x + 8 * scale + (fill.width - 16 * scale) * glint_phase
                rl.DrawLineEx(
                    {glint_x, fill.y + scale},
                    {glint_x, fill.y + fill.height - scale},
                    2 * scale,
                    {255, 238, 177, 180},
                )
            }
        }

        frame_width := max(10 * scale, f32(8))
        frame_color := rl.Color{238, 221, 181, 255}
        rl.DrawRectangle(0, 0, width, i32(frame_width), frame_color)
        rl.DrawRectangle(0, height - i32(frame_width), width, i32(frame_width), frame_color)
        rl.DrawRectangle(0, 0, i32(frame_width), height, frame_color)
        rl.DrawRectangle(width - i32(frame_width), 0, i32(frame_width), height, frame_color)
        rl.DrawRectangleRoundedLinesEx(
            {frame_width, frame_width, w - frame_width * 2, h - frame_width * 2},
            .01,
            2,
            max(1, 2 * scale),
            {104, 59, 49, 180},
        )
        rl.EndDrawing()
        return
    }

    rl.BeginDrawing()

    // A painted dawn built only from first-frame-safe primitives.
    sky_colors := [8]rl.Color {
        {8, 27, 43, 255},
        {10, 37, 54, 255},
        {15, 49, 64, 255},
        {25, 65, 76, 255},
        {53, 89, 91, 255},
        {104, 121, 105, 255},
        {166, 145, 112, 255},
        {218, 174, 123, 255},
    }
    sky_band_height := horizon / f32(len(sky_colors))
    for color, band in sky_colors {
        rl.DrawRectangle(0, i32(f32(band) * sky_band_height), width, i32(sky_band_height + 2), color)
    }

    sun_pulse := 1 + math.sin(animation_time * 1.4) * .035
    rl.DrawCircleV(sun, 52 * scale * sun_pulse, {239, 174, 93, 24})
    rl.DrawCircleV(sun, 37 * scale * sun_pulse, {245, 188, 99, 45})
    rl.DrawCircleV(sun, 21 * scale, {255, 213, 135, 255})

    cloud_color := rl.Color{227, 214, 184, 72}
    rl.DrawCircleV({center.x - 310 * scale, horizon - 176 * scale}, 18 * scale, cloud_color)
    rl.DrawCircleV({center.x - 286 * scale, horizon - 181 * scale}, 25 * scale, cloud_color)
    rl.DrawCircleV({center.x - 257 * scale, horizon - 174 * scale}, 17 * scale, cloud_color)
    rl.DrawRectangle(
        i32(center.x - 326 * scale),
        i32(horizon - 180 * scale),
        i32(88 * scale),
        i32(20 * scale),
        cloud_color,
    )
    bird_color := rl.Color{12, 43, 56, 150}
    for bird in 0 ..< 3 {
        bx := center.x - 58 * scale + f32(bird) * 37 * scale
        by := horizon - (142 + f32(bird % 2) * 11) * scale + math.sin(animation_time * 1.1 + f32(bird)) * 2.5 * scale
        rl.DrawLineEx({bx - 7 * scale, by}, {bx, by + 3 * scale}, 1.4 * scale, bird_color)
        rl.DrawLineEx({bx, by + 3 * scale}, {bx + 7 * scale, by - scale}, 1.4 * scale, bird_color)
    }

    // Distant land is drawn before the sea, leaving only its soft ridgeline.
    distant_island := rl.Color{29, 68, 70, 255}
    rl.DrawCircleV({center.x - 350 * scale, horizon + 34 * scale}, 92 * scale, distant_island)
    rl.DrawCircleV({center.x - 245 * scale, horizon + 55 * scale}, 118 * scale, distant_island)
    rl.DrawCircleV({center.x + 410 * scale, horizon + 43 * scale}, 104 * scale, distant_island)
    rl.DrawCircleV({center.x + 512 * scale, horizon + 62 * scale}, 128 * scale, distant_island)

    sea_colors := [5]rl.Color {
        {25, 88, 96, 255},
        {20, 78, 89, 255},
        {15, 65, 80, 255},
        {11, 52, 70, 255},
        {8, 40, 58, 255},
    }
    sea_band_height := (h - horizon) / f32(len(sea_colors))
    for color, band in sea_colors {
        rl.DrawRectangle(0, i32(horizon + f32(band) * sea_band_height), width, i32(sea_band_height + 2), color)
    }
    for reflection in 0 ..< 8 {
        reflection_width := (18 + f32(reflection) * 7) * scale
        reflection_y := horizon + (12 + f32(reflection) * 17) * scale
        reflection_drift := math.sin(animation_time * 1.8 + f32(reflection) * .8) * 5 * scale
        rl.DrawLineEx(
            {sun.x - reflection_width * .5 + f32(reflection % 2) * 8 * scale + reflection_drift, reflection_y},
            {sun.x + reflection_width * .5 + reflection_drift, reflection_y},
            max(1, 1.8 * scale),
            {246, 192, 111, u8(150 - reflection * 12)},
        )
    }
    for wave in 0 ..< 9 {
        wave_y := horizon + (34 + f32(wave) * 21) * scale
        wave_x :=
            center.x -
            530 * scale +
            f32((wave * 137) % 780) * scale +
            math.sin(animation_time * .9 + f32(wave)) * 8 * scale
        rl.DrawLineEx(
            {wave_x, wave_y},
            {wave_x + (28 + f32(wave % 3) * 12) * scale, wave_y},
            max(1, scale),
            {132, 190, 181, 80},
        )
    }

    // A close island village gives the screen a recognizable coastal identity.
    island_y := horizon + 52 * scale
    island_color := rl.Color{12, 45, 52, 255}
    rl.DrawCircleV({center.x - 118 * scale, island_y + 70 * scale}, 124 * scale, island_color)
    rl.DrawCircleV({center.x + 12 * scale, island_y + 83 * scale}, 148 * scale, island_color)
    rl.DrawCircleV({center.x + 148 * scale, island_y + 76 * scale}, 130 * scale, island_color)

    // Sparse terrace marks break the foreground into cultivated slopes while
    // retaining the bold silhouette of the screen-print layer.
    terrace_color := rl.Color{45, 91, 76, 175}
    terrace_specs := [5][3]f32{{-154, 32, 86}, {-86, 66, 128}, {48, 40, 104}, {72, 82, 142}, {-36, 112, 92}}
    for terrace in terrace_specs {
        terrace_x := center.x + terrace[0] * scale
        terrace_y := island_y + terrace[1] * scale
        terrace_width := terrace[2] * scale
        rl.DrawLineEx(
            {terrace_x - terrace_width * .5, terrace_y},
            {terrace_x + terrace_width * .5, terrace_y},
            max(1, 1.4 * scale),
            terrace_color,
        )
    }

    house_color := rl.Color{229, 212, 171, 255}
    roof_color := rl.Color{168, 74, 54, 255}
    window_dark := rl.Color{22, 62, 67, 255}

    // Cypress spires break up the roofline and make the settlement read as
    // Mediterranean at postcard scale.
    cypress_color := rl.Color{18, 63, 58, 255}
    cypress_positions := [5]f32{-172, -70, 44, 132, 202}
    for offset, tree in cypress_positions {
        tree_x := center.x + offset * scale
        tree_base_y := island_y - (2 + f32(tree % 3) * 6) * scale
        tree_height := (28 + f32((tree * 7) % 13)) * scale
        rl.DrawLineEx({tree_x, tree_base_y}, {tree_x, tree_base_y - tree_height}, 7 * scale, cypress_color)
        rl.DrawLineEx(
            {tree_x, tree_base_y - tree_height * .72},
            {tree_x, tree_base_y - tree_height},
            3 * scale,
            {26, 78, 66, 255},
        )
    }

    // Two compact bougainvillea clusters introduce the saturated postcard ink
    // accent without turning the quiet village into visual noise.
    bougainvillea_centers := [2]rl.Vector2 {
        {center.x - 185 * scale, island_y - 28 * scale},
        {center.x + 129 * scale, island_y - 47 * scale},
    }
    for cluster, cluster_index in bougainvillea_centers {
        sway := math.sin(animation_time * 1.3 + f32(cluster_index) * 1.7) * 1.2 * scale
        rl.DrawLineEx(
            {cluster.x, cluster.y + 18 * scale},
            {cluster.x + sway, cluster.y - 8 * scale},
            2 * scale,
            {47, 91, 65, 210},
        )
        for blossom in 0 ..< 11 {
            blossom_x := cluster.x + (f32((blossom * 11) % 27) - 13) * scale + sway * f32(blossom % 2)
            blossom_y := cluster.y + (f32((blossom * 7) % 25) - 12) * scale
            blossom_color := blossom % 3 == 0 ? rl.Color{232, 87, 112, 245} : rl.Color{190, 52, 91, 235}
            rl.DrawCircleV({blossom_x, blossom_y}, (3.5 + f32(blossom % 2) * 1.2) * scale, blossom_color)
        }
    }

    for house in 0 ..< 7 {
        house_x := center.x - 210 * scale + f32(house) * 63 * scale
        rise := f32((house * 17) % 38) * scale
        house_y := island_y - (12 * scale + rise)
        house_width := (34 + f32(house % 3) * 5) * scale
        house_height := (32 + f32((house + 1) % 3) * 8) * scale
        rl.DrawRectangle(i32(house_x), i32(house_y - house_height), i32(house_width), i32(house_height), house_color)
        rl.DrawLineEx(
            {house_x - 3 * scale, house_y - house_height},
            {house_x + house_width * .5, house_y - house_height - 10 * scale},
            5 * scale,
            roof_color,
        )
        rl.DrawLineEx(
            {house_x + house_width * .5, house_y - house_height - 10 * scale},
            {house_x + house_width + 3 * scale, house_y - house_height},
            5 * scale,
            roof_color,
        )
        window_color := normalized_progress >= f32(house + 1) / 8 ? rl.Color{246, 190, 91, 255} : window_dark
        rl.DrawRectangle(
            i32(house_x + house_width * .5 - 3 * scale),
            i32(house_y - house_height * .55),
            i32(6 * scale),
            i32(8 * scale),
            window_color,
        )
    }

    // A small campanile adds a vertical village landmark distinct from the
    // harbor lighthouse.
    campanile_x := center.x + 54 * scale
    campanile_base_y := island_y - 28 * scale
    rl.DrawRectangle(
        i32(campanile_x),
        i32(campanile_base_y - 55 * scale),
        i32(22 * scale),
        i32(55 * scale),
        {220, 202, 161, 255},
    )
    rl.DrawLineEx(
        {campanile_x - 3 * scale, campanile_base_y - 55 * scale},
        {campanile_x + 11 * scale, campanile_base_y - 67 * scale},
        5 * scale,
        roof_color,
    )
    rl.DrawLineEx(
        {campanile_x + 11 * scale, campanile_base_y - 67 * scale},
        {campanile_x + 25 * scale, campanile_base_y - 55 * scale},
        5 * scale,
        roof_color,
    )
    rl.DrawCircleV({campanile_x + 11 * scale, campanile_base_y - 43 * scale}, 4 * scale, window_dark)

    lighthouse_x := center.x + 223 * scale
    lighthouse_base_y := island_y - 22 * scale
    rl.DrawRectangle(
        i32(lighthouse_x),
        i32(lighthouse_base_y - 69 * scale),
        i32(18 * scale),
        i32(69 * scale),
        {236, 220, 181, 255},
    )
    rl.DrawRectangle(
        i32(lighthouse_x - 4 * scale),
        i32(lighthouse_base_y - 75 * scale),
        i32(26 * scale),
        i32(8 * scale),
        roof_color,
    )
    rl.DrawCircleV({lighthouse_x + 9 * scale, lighthouse_base_y - 71 * scale}, 4 * scale, {255, 211, 116, 255})
    beam_alpha := u8(18 + (math.sin(animation_time * 1.2) * .5 + .5) * 18)
    rl.DrawLineEx(
        {lighthouse_x + 12 * scale, lighthouse_base_y - 71 * scale},
        {lighthouse_x + 116 * scale, lighthouse_base_y - 88 * scale},
        9 * scale,
        {255, 221, 145, beam_alpha},
    )

    // The boat crosses the bay as work completes; the picture itself progresses.
    boat_x := center.x - 390 * scale + normalized_progress * 245 * scale
    boat_y := horizon + 88 * scale + math.sin(animation_time * 1.7) * 2.5 * scale
    rl.DrawLineEx({boat_x, boat_y - 42 * scale}, {boat_x, boat_y + 2 * scale}, 2 * scale, {66, 49, 40, 255})
    for sail_row in 0 ..< 9 {
        sail_y := boat_y - (38 - f32(sail_row) * 4) * scale
        sail_width := (2 + f32(sail_row) * 2.1) * scale
        rl.DrawLineEx(
            {boat_x + 2 * scale, sail_y},
            {boat_x + 2 * scale + sail_width, sail_y},
            3.5 * scale,
            {241, 229, 201, 240},
        )
    }
    rl.DrawLineEx(
        {boat_x - 16 * scale, boat_y + 4 * scale},
        {boat_x + 22 * scale, boat_y + 4 * scale},
        7 * scale,
        {117, 55, 43, 255},
    )
    for wake in 0 ..< 3 {
        wake_y := boat_y + (11 + f32(wake) * 6) * scale
        wake_half_width := (16 + f32(wake) * 9) * scale
        rl.DrawLineEx(
            {boat_x - wake_half_width, wake_y},
            {boat_x + wake_half_width, wake_y},
            max(1, scale),
            {184, 213, 193, u8(100 - wake * 22)},
        )
    }

    // A tiny quay visually ties the boat to the village instead of leaving it
    // floating against an abstract silhouette.
    quay_x := center.x - 246 * scale
    quay_y := horizon + 111 * scale
    rl.DrawLineEx({quay_x, quay_y}, {quay_x + 78 * scale, quay_y}, 7 * scale, {101, 70, 53, 255})
    for post in 0 ..< 3 {
        post_x := quay_x + f32(post) * 37 * scale
        rl.DrawLineEx({post_x, quay_y - 4 * scale}, {post_x, quay_y + 13 * scale}, 3 * scale, {76, 55, 46, 255})
    }

    // Sparse, fixed flecks soften the digital bands into a lightly weathered
    // screen-print surface without introducing an asset-loading dependency.
    for fleck in 0 ..< 72 {
        fleck_x := f32((fleck * 197 + 83) % max(int(width) - 28, 1) + 14)
        fleck_y := f32((fleck * 109 + 47) % max(int(height) - 28, 1) + 14)
        fleck_color := fleck % 3 == 0 ? rl.Color{244, 224, 184, 16} : rl.Color{5, 29, 38, 12}
        rl.DrawCircleV({fleck_x, fleck_y}, max(.55, scale * .7), fleck_color)
    }

    // Slightly offset ink layers mimic imperfect registration on a vintage
    // postcard, while the cream frame keeps the image feeling printed.
    rl.DrawTextEx(
        rl.Font{},
        greeting,
        {center.x - greeting_size.x * .5, 55 * ui_scale},
        greeting_font_size,
        3 * scale,
        {246, 222, 172, 230},
    )
    rl.DrawTextEx(
        rl.Font{},
        title,
        {center.x - title_size.x * .5 + 2 * scale, 77 * ui_scale + 2 * scale},
        title_font_size,
        7 * scale,
        {154, 58, 49, 210},
    )
    rl.DrawTextEx(
        rl.Font{},
        title,
        {center.x - title_size.x * .5, 76 * ui_scale},
        title_font_size,
        7 * scale,
        {248, 239, 203, 255},
    )
    rl.DrawTextEx(
        rl.Font{},
        message,
        {center.x - message_size.x * .5, track.y - 29 * ui_scale},
        message_font_size,
        1,
        {194, 221, 215, 255},
    )
    rl.DrawRectangleRounded(track, 1, 8, {5, 24, 34, 210})
    if normalized_progress > 0 {
        fill := track
        fill.width *= normalized_progress
        rl.DrawRectangleRounded(fill, 1, 8, {241, 188, 93, 255})
        if fill.width > 24 * scale {
            glint_phase := math.sin(animation_time * 1.1) * .5 + .5
            glint_x := fill.x + 8 * scale + (fill.width - 16 * scale) * glint_phase
            rl.DrawLineEx(
                {glint_x, fill.y + scale},
                {glint_x, fill.y + fill.height - scale},
                2 * scale,
                {255, 238, 177, 180},
            )
        }
    }

    frame_width := max(10 * scale, f32(8))
    frame_color := rl.Color{238, 221, 181, 255}
    rl.DrawRectangle(0, 0, width, i32(frame_width), frame_color)
    rl.DrawRectangle(0, height - i32(frame_width), width, i32(frame_width), frame_color)
    rl.DrawRectangle(0, 0, i32(frame_width), height, frame_color)
    rl.DrawRectangle(width - i32(frame_width), 0, i32(frame_width), height, frame_color)
    rl.DrawRectangleRoundedLinesEx(
        {frame_width, frame_width, w - frame_width * 2, h - frame_width * 2},
        .01,
        2,
        max(1, 2 * scale),
        {104, 59, 49, 180},
    )
    rl.EndDrawing()
}

Hot_State_File_Header :: struct {
    magic:        [8]u8,
    version:      u32,
    type_hash:    u64,
    payload_size: u64,
}

HOT_STATE_FILE_MAGIC :: [8]u8{'A', 'D', 'R', 'H', 'S', 'T', '1', 0}
HOT_STATE_FILE_VERSION :: u32(1)

Hot_State_Load_Result :: enum {
    Missing,
    Loaded,
    Invalid,
}

hot_state_header_valid :: proc(header: ^Hot_State_File_Header, payload_size: int) -> bool {
    if header == nil || payload_size < 0 do return false
    magic := HOT_STATE_FILE_MAGIC
    for i in 0 ..< len(HOT_STATE_FILE_MAGIC) {
        if header.magic[i] != magic[i] do return false
    }
    return header.version == HOT_STATE_FILE_VERSION && header.payload_size == u64(payload_size)
}

hot_state_save :: proc(editor: ^Editor, path: string) -> bool {
    if editor == nil || path == "" do return false

    state := new(Editor, context.temp_allocator)
    state^ = editor^
    state.pilot.vehicle = nil
    state.car.driver = nil
    state.car_physics_world = nil
    state.car_physics_vehicle = nil
    state.engine_audio.stream = nil
    state.postale.vehicle.driver = nil
    state.libellula.vehicle.driver = nil
    for &slot in state.aircraft.slots do slot.vehicle = nil

    // These values belong to the loaded dylib or the GPU. Never preserve their
    // pointers across an unload. Canvas textures live in the host-owned canvas
    // state and are intentionally serialized with the editor.
    state.libellula_visual_mesh = {}
    state.libellula_projected_faces = {}
    state.attendant_dialogue = {}
    state.attendant_dialogue_open = false

    payload := hs.serialize(state, {.Dynamics}, context.allocator)
    defer delete(payload)
    if len(payload) == 0 do return false

    header := Hot_State_File_Header {
        magic        = HOT_STATE_FILE_MAGIC,
        version      = HOT_STATE_FILE_VERSION,
        type_hash    = hs.type_hash(Editor),
        payload_size = u64(len(payload)),
    }
    output := make([dynamic]byte, 0, size_of(header) + len(payload), context.allocator)
    append(&output, ..mem.ptr_to_bytes(&header))
    append(&output, ..payload)
    defer delete(output)
    return os.write_entire_file(path, output[:]) == nil
}

hot_state_load :: proc(editor: ^Editor, path: string) -> Hot_State_Load_Result {
    if editor == nil || path == "" do return .Missing

    data, err := os.read_entire_file_from_path(path, context.temp_allocator)
    if err == .Not_Exist do return .Missing
    if err != nil || len(data) < size_of(Hot_State_File_Header) do return .Invalid

    header := cast(^Hot_State_File_Header)(&data[0])
    payload := data[size_of(Hot_State_File_Header):]
    if !hot_state_header_valid(header, len(payload)) do return .Invalid
    if len(payload) == 0 do return .Invalid

    // Existing allocations are runtime-owned. hs rebuilds dynamic data from
    // the blob, so release these before it replaces their descriptors.
    vehicles.libellula_mesh_destroy(&editor.libellula_visual_mesh)
    delete(editor.libellula_projected_faces)
    editor.attendant_dialogue = {}
    editor.attendant_dialogue_open = false

    identical := hs.deserialize(editor, payload, {.Dynamics}, context.allocator)
    _ = identical // hs already used mem.copy for every identical subtree.

    editor.libellula_visual_mesh = {}
    vehicles.libellula_mesh_init(&editor.libellula_visual_mesh)
    editor.libellula_projected_faces = make(
        [dynamic]Projected_Aircraft_Face,
        0,
        vehicles.LIBELLULA_MESH_TRIANGLE_CAPACITY,
    )
    editor.attendant_dialogue = {}
    editor.attendant_dialogue_open = false
    editor.quit_requested = false
    return .Loaded
}

adriatic_run :: proc(
    persistent_canvas_state: rawptr,
    args: []string = os.args,
    request: ^Capture_Request = nil,
) -> hot_abi.Run_Result {
    tracking: back.Tracking_Allocator
    back.tracking_allocator_init(&tracking, context.allocator)
    defer back.tracking_allocator_destroy(&tracking)
    context.allocator = back.tracking_allocator(&tracking)
    defer back.tracking_allocator_print_results(&tracking)

    first_start := persistent_canvas_state == nil
    rl.SetPersistentState(persistent_canvas_state)
    assert(rl.SetRendererDescriptor(ADRIATIC_RENDERER_DESCRIPTOR))
    benchmark_requested := len(args) >= 2 && args[1] == "--benchmark"
    if benchmark_requested && len(args) < 9 {
        fmt.eprintln(
            "usage: adriatic --benchmark <scenario> <warmup_frames> <sample_frames> <window_width> <window_height> <world_width> <world_height>",
        )
        return .Quit
    }
    benchmark_mode := benchmark_requested && len(args) >= 9
    loading_preview_mode := len(args) >= 3 && args[1] == "--loading-preview"
    loading_preview_output := loading_preview_mode ? args[2] : ""
    loading_lab_mode := len(args) >= 3 && args[1] == "--lab" && args[2] == "loading-screen"
    benchmark_scenario := benchmark_mode ? args[2] : ""
    benchmark_warmup, benchmark_frames := 0, 0
    benchmark_window_width, benchmark_window_height := 1280, 720
    benchmark_world_width, benchmark_world_height := ADRIATIC_WORLD_WIDTH, ADRIATIC_WORLD_HEIGHT
    if benchmark_mode {
        parsed, ok := strconv.parse_int(args[3])
        if ok do benchmark_warmup = clamp(int(parsed), 0, 4096)
        parsed, ok = strconv.parse_int(args[4])
        if ok do benchmark_frames = clamp(int(parsed), 1, 4096)
        parsed, ok = strconv.parse_int(args[5])
        if ok do benchmark_window_width = clamp(int(parsed), 320, 7680)
        parsed, ok = strconv.parse_int(args[6])
        if ok do benchmark_window_height = clamp(int(parsed), 240, 4320)
        parsed, ok = strconv.parse_int(args[7])
        if ok do benchmark_world_width = parsed == 0 ? 0 : clamp(int(parsed), 320, 7680)
        parsed, ok = strconv.parse_int(args[8])
        if ok do benchmark_world_height = parsed == 0 ? 0 : clamp(int(parsed), 180, 4320)
    }
    flags := rl.ConfigFlags{.WINDOW_RESIZABLE}
    if !benchmark_mode do flags += {.VSYNC_HINT}
    capture_kind := request != nil ? request.kind : Capture_Kind.None
    if request == nil && len(args) >= 3 do capture_kind = capture_kind_from_arg(args[1])
    capture_mode := capture_kind != .None
    capture_editor_mode := capture_kind == .Editor
    showcase_interactive_mode := len(args) >= 2 && args[1] == "--vehicle-showcase"
    interactive_lab_request, interactive_lab_mode := lab_scene_request_from_args(args)
    legacy_shadow_lab_mode := len(args) >= 2 && args[1] == "--shadow-lab"
    capture_sky_mode := capture_kind in CAPTURE_SKY_KINDS
    capture_map_mode := capture_kind == .Map || capture_sky_mode
    capture_flight_mode := capture_kind == .Flight
    capture_car_mode := capture_kind == .Car
    capture_vehicle_showcase_mode := capture_kind == .Vehicle_Showcase
    capture_paint_mode := capture_kind == .Paint_Mode
    vehicle_showcase_mode := capture_vehicle_showcase_mode || capture_paint_mode || showcase_interactive_mode
    capture_gameplay_mode :=
        capture_mode && !capture_editor_mode && !capture_vehicle_showcase_mode && !capture_paint_mode
    capture_road_mode := capture_kind == .Road || capture_kind == .Road_Dust
    capture_road_dust_mode := capture_kind == .Road_Dust
    capture_road_grip_mode := capture_kind == .Road_Grip
    capture_terrain_grip_mode := capture_kind == .Terrain_Grip
    capture_building_mode := capture_kind == .Building
    capture_story_meeting_mode := capture_kind == .Story_Meeting
    capture_foliage_mode := capture_kind == .Foliage
    capture_foliage_forest_mode := capture_kind in CAPTURE_FOLIAGE_FOREST_KINDS
    capture_foliage_motion_mode := capture_kind in CAPTURE_FOLIAGE_MOTION_KINDS
    capture_foliage_golden_mode := capture_kind == .Foliage_Golden
    capture_foliage_low_mode := capture_kind in CAPTURE_FOLIAGE_LOW_KINDS
    capture_foliage_understory_mode := capture_kind == .Foliage_Understory
    capture_foliage_stress_mode := capture_kind == .Foliage_Stress
    capture_grass_wind_mode := capture_kind == .Grass_Wind
    capture_wildflower_lab_mode := capture_kind == .Wildflower_Lab
    capture_markov_town_mode :=
        capture_kind in
        bit_set[Capture_Kind]{.Markov_Town, .Markov_City, .Markov_Village, .Aegean_City, .Aegean_Town, .Aegean_Village}
    capture_lab_name := ""
    #partial switch capture_kind {
    case .Markov_Town:
        capture_lab_name = "markov-town"
    case .Markov_City:
        capture_lab_name = "markov-city"
    case .Markov_Village:
        capture_lab_name = "markov-village"
    case .Aegean_City:
        capture_lab_name = "aegean-city"
    case .Aegean_Town:
        capture_lab_name = "aegean-town"
    case .Aegean_Village:
        capture_lab_name = "aegean-village"
    }
    if capture_kind == .Shadow_Lab do capture_lab_name = "shadow"
    if capture_wildflower_lab_mode do capture_lab_name = "wildflower"
    if capture_kind == .Boat_Lab do capture_lab_name = "boat"
    if capture_kind == .Markov_Wreck do capture_lab_name = "markov-wreck"
    if capture_kind == .Markov_Marina do capture_lab_name = "markov-marina"
    if capture_kind == .Markov_Farmland do capture_lab_name = "markov-farmland"
    capture_lab_mode := capture_lab_name != ""
    capture_map_mode =
        capture_map_mode ||
        capture_grass_wind_mode ||
        capture_wildflower_lab_mode ||
        capture_markov_town_mode ||
        capture_kind == .Shadow_Lab ||
        capture_kind == .Boat_Lab ||
        capture_kind == .Markov_Wreck ||
        capture_kind == .Markov_Marina ||
        capture_kind == .Markov_Farmland
    capture_target := request != nil ? request.target : (capture_mode && len(args) >= 4 ? args[3] : "")
    capture_output := request != nil ? request.output_path : (capture_mode && len(args) >= 3 ? args[2] : "")
    showcase_target := showcase_interactive_mode ? (len(args) >= 3 ? args[2] : "") : capture_target
    capture_player_mode := capture_kind == .Map && capture_target != ""
    if capture_mode do flags += {.WINDOW_NOT_FOCUSABLE}
    if benchmark_mode do flags += {.WINDOW_NOT_FOCUSABLE}
    if loading_preview_mode do flags += {.WINDOW_NOT_FOCUSABLE}
    rl.SetConfigFlags(flags)
    rl.SetWorldRenderSize(
        u32(benchmark_mode ? benchmark_world_width : ADRIATIC_WORLD_WIDTH),
        u32(benchmark_mode ? benchmark_world_height : ADRIATIC_WORLD_HEIGHT),
    )
    initial_width := i32(benchmark_mode ? benchmark_window_width : 1280)
    initial_height := i32(benchmark_mode ? benchmark_window_height : 720)
    if capture_kind == .Narrow do initial_width = 1000
    if capture_kind == .Compact do initial_width = 760
    rl.InitWindow(initial_width, initial_height, "Adriatic — Clipmap Terrain Authoring")
    show_loading_screen := SHOW_STARTUP_MENU && first_start && !capture_mode && !benchmark_mode
    postcard: rl.Texture
    if loading_lab_mode || loading_preview_mode || show_loading_screen {
        postcard_period := loading_postcard_period_for_hour(loading_postcard_local_hour())
        period_override := ""
        if loading_lab_mode && len(args) >= 4 do period_override = args[3]
        if loading_preview_mode && len(args) >= 4 do period_override = args[3]
        if period_override != "" {
            if override, known := loading_postcard_period_from_name(period_override); known {
                postcard_period = override
            } else {
                fmt.eprintf(
                    "unknown loading postcard period %s; expected dawn, morning, midday, golden-hour, dusk, or night\n",
                    period_override,
                )
            }
        }
        draw_startup_loading_screen(initial_width, initial_height, .02, "Opening the harbor...")
        postcard = rl.LoadTexture(loading_postcard_path(postcard_period))
        if !postcard.ready do fmt.eprintln("loading postcard texture failed; using procedural fallback")
    }
    if loading_lab_mode {
        defer rl.CloseWindow()
        for !rl.WindowShouldClose() {
            draw_startup_loading_screen(initial_width, initial_height, .62, "Wish you were here...", postcard)
        }
        return .Quit
    }
    if loading_preview_mode {
        defer rl.CloseWindow()
        for preview_frame in 0 ..< 33 {
            draw_startup_loading_screen(initial_width, initial_height, .62, "Raising the islands...", postcard)
            if preview_frame == 2 do rl.TakeScreenshot(fmt.ctprintf("%s", loading_preview_output))
        }
        return .Quit
    }
    if show_loading_screen {
        draw_startup_loading_screen(initial_width, initial_height, .04, "Opening the harbor...", postcard)
    }
    reload_requested := false
    defer if !reload_requested do rl.DestroyPersistentState()
    wind_sound: wind_audio.Runtime
    wind_audio_ready := false
    if !capture_mode && !benchmark_mode {
        wind_audio_ready = wind_audio.init(&wind_sound)
        if wind_audio_ready {
            defer wind_audio.destroy(&wind_sound)
        } else {
            fmt.eprintf("wind audio unavailable: %s\n", sdl.GetError())
        }
    }
    ocean_sound: ocean_audio.Runtime
    ocean_audio_ready := false
    if !capture_mode && !benchmark_mode {
        ocean_audio_ready = ocean_audio.init(&ocean_sound)
        if ocean_audio_ready {
            defer ocean_audio.destroy(&ocean_sound)
        } else {
            fmt.eprintf("ocean audio unavailable: %s\n", sdl.GetError())
        }
    }
    spray_sound: spray_audio.Runtime
    spray_audio_ready := false
    if !capture_mode && !benchmark_mode {
        spray_audio_ready = spray_audio.init(&spray_sound)
        if spray_audio_ready {
            defer spray_audio.destroy(&spray_sound)
        } else {
            fmt.eprintf("spray audio unavailable: %s\n", sdl.GetError())
        }
    }
    if show_loading_screen {
        draw_startup_loading_screen(initial_width, initial_height, .20, "Tuning the sea and wind...", postcard)
    }
    editor := new(Editor)
    defer free(editor)
    defer dio.flame_graph_destroy(&editor.flame_graph)
    defer greek_asset_destroy(editor)
    story.init_catalog(&editor.story_catalog)
    engine_audio_ready := !capture_mode && !benchmark_mode && engine_sound.open(&editor.engine_audio)
    if engine_audio_ready do defer engine_sound.close(&editor.engine_audio)
    vehicle_paint_history_init(editor)
    defer vehicle_paint_history_destroy(editor)
    vehicles.libellula_mesh_init(&editor.libellula_visual_mesh)
    defer vehicles.libellula_mesh_destroy(&editor.libellula_visual_mesh)
    vehicles.libellula_mesh_init(&editor.libellula_mk2_visual_mesh)
    defer vehicles.libellula_mesh_destroy(&editor.libellula_mk2_visual_mesh)
    vehicles.libellula_mesh_init(&editor.libellula_base_mesh)
    defer vehicles.libellula_mesh_destroy(&editor.libellula_base_mesh)
    vehicles.libellula_mesh_init(&editor.libellula_mk2_base_mesh)
    defer vehicles.libellula_mesh_destroy(&editor.libellula_mk2_base_mesh)
    vehicles.libellula_mesh_build(&editor.libellula_base_mesh)
    vehicles.libellula_mk2_mesh_build(&editor.libellula_mk2_base_mesh)
    vehicles.libellula_mesh_copy(&editor.libellula_visual_mesh, &editor.libellula_base_mesh)
    vehicles.libellula_mesh_copy(&editor.libellula_mk2_visual_mesh, &editor.libellula_mk2_base_mesh)
    editor.postale_base_mesh = vehicles.postale_mesh()
    vehicles.mesh_generate_smooth_normals(&editor.postale_base_mesh)
    if show_loading_screen {
        draw_startup_loading_screen(initial_width, initial_height, .42, "Preparing aircraft and boats...", postcard)
    }
    editor.libellula_projected_faces = make(
        [dynamic]Projected_Aircraft_Face,
        0,
        vehicles.LIBELLULA_MESH_TRIANGLE_CAPACITY,
    )
    defer delete(editor.libellula_projected_faces)
    terrain.init_project(&editor.project)
    if !capture_mode && !interactive_lab_mode && (!benchmark_mode || benchmark_scenario == "editor") {
        seed_default_island_towns(editor)
        seed_default_island_marinas(editor)
    }
    if show_loading_screen {
        draw_startup_loading_screen(initial_width, initial_height, .62, "Raising the islands...", postcard)
    }
    editor.authoring_tool = .Sculpt
    editor.tool = .Raise
    editor.radius = 48
    editor.strength = .10
    editor.hardness = .5
    editor.structure_selected = -1
    editor.structure_kind = .Box
    editor.structure_auto_kind = true
    editor.structure_scatter_count = 4
    editor.formation_brush_radius = terrain.BASE_CELL_SIZE * 3.5
    editor.formation_brush_strength = .55
    editor.formation_brush_hardness = .45
    editor.curve_width = terrain.BASE_CELL_SIZE * 2.5
    editor.curve_height = terrain.BASE_CELL_SIZE * 2.0
    editor.road_selected_node = -1
    editor.road_drag_edge = -1
    editor.road_drag_handle = -1
    editor.road_width = 7
    editor.road_shoulder_width = 1.25
    editor.road_pavement = .Asphalt
    editor.architecture_brush_radius = terrain.BASE_CELL_SIZE * 4.0
    editor.architecture_brush_strength = .55
    editor.architecture_brush_hardness = .45
    editor.marina_brush_radius = 60
    editor.farm_brush_radius = 64
    editor.climbing_leaf_brush_radius = terrain.BASE_CELL_SIZE * 3.0
    editor.climbing_leaf_brush_strength = .55
    editor.climbing_leaf_brush_hardness = .50
    greek_asset_init(editor)
    editor.greek_placement_mode = false
    editor.atmosphere = atmosphere.new(0x41c10)
    editor.boat_traffic = boats.new_traffic()
    editor.vehicle_effects = particle_systems.new_vehicle_effects(0x72b7e4a1)
    editor.wing_trails = particle_systems.new_wing_trails(0x1f123bb5)
    editor.petal_effects = particle_systems.new_petal_effects(0x6a09e667)
    editor.tweak = tweak_default_state()
    editor.tweak_status = .Defaults
    editor.tweak_panel_visible = false
    editor.gameplay_options = gameplay_options_default()
    if capture_mode {
        capture_dither := os.get_env("ADRIATIC_CAPTURE_DITHER", context.temp_allocator)
        switch capture_dither {
        case "bayer":
            editor.gameplay_options.dither_mode = .Bayer
        case "blue":
            editor.gameplay_options.dither_mode = .Blue_Noise
        case "matriax8":
            editor.gameplay_options.dither_mode = .Matriax_8
        }
    }
    dither_apply(editor)
    editor.mouse_fur = .Chestnut
    editor.mouse_pattern = .Solid
    editor.mouse_headgear = .Goggles
    editor.mouse_scarf_enabled = false
    editor.mouse_scarf_color = {194, 35, 47, 255}
    if !capture_mode do _ = mouse_preference_load(editor)
    editor.runtime_input = game_input.default_state()
    editor.vehicle_paint_tool_icons = rl.LoadTexture("assets/icons/control-hints/keyboard-mouse.png")
    if !editor.vehicle_paint_tool_icons.ready {
        fmt.eprintln("vehicle paint tool icon atlas failed to load")
    }
    editor.tarot_atlas = rl.LoadTexture("assets/textures/ui/tarot-atlas-v4.png")
    if !editor.tarot_atlas.ready {
        fmt.eprintln("tarot card atlas failed to load")
    }
    control_hints_load(editor)
    _ = vehicle_paint_load(editor)
    island_center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    editor.editor_focus = third_person.Vec3{island_center, 0, island_center}
    editor.editor_camera = {
        yaw_radians   = math.PI * .25,
        pitch_radians = .58,
        distance      = 900,
    }
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    editor.postale = postale_game.new_runtime(postale_spawn_position(editor))
    libellula_spawn := libellula_spawn_position(editor)
    editor.libellula = libellula_game.new_runtime({libellula_spawn.x, libellula_spawn.y, libellula_spawn.z})
    editor.attendant_position = attendant_spawn_position(editor, editor.libellula.vehicle.position)
    editor.gerta_position = gerta_spawn_position(editor)
    vehicles.aircraft_fleet_add(&editor.aircraft, .Postale, "Postale", &editor.postale.vehicle, true)
    vehicles.aircraft_fleet_add(&editor.aircraft, .Libellula, "Libellula", &editor.libellula.vehicle, false)
    vehicles.aircraft_fleet_add(&editor.aircraft, .Libellula_Mk2, "Libellula Mk2", &editor.libellula.vehicle, false)
    editor.postale_visible = true
    editor.libellula_visible = true
    editor.libellula.vehicle.locked = true
    editor.car = vehicles.default_vehicle(car_spawn_position(editor))
    editor.car.interaction_radius = 2.2
    editor.car.exit_distance = 1.1
    editor.car.yaw_radians = -math.PI * .5
    car_physics_create(editor)
    if show_loading_screen {
        draw_startup_loading_screen(initial_width, initial_height, .78, "Setting the world in motion...", postcard)
    }
    defer car_physics_destroy(editor)
    defer markov_marina_buoy_physics_destroy(editor)
    editor.car_trailer_attached = true
    editor.car_trailer_position = editor.car.position
    editor.car_trailer_yaw = editor.car.yaw_radians
    editor.pilot.position = runway_spawn_position(editor)
    if capture_mode && !capture_map_mode {
        if capture_foliage_stress_mode {
            seed_foliage_stress(editor)
        } else if capture_foliage_forest_mode {
            seed_foliage_forest_capture(editor)
        } else if capture_foliage_mode {
            seed_foliage_capture(editor)
        } else if capture_road_grip_mode {
            seed_road_grip_capture(editor)
        } else if capture_terrain_grip_mode {
            seed_terrain_grip_capture(editor)
        } else if capture_road_mode {
            seed_road_capture(editor)
            if capture_road_dust_mode do seed_road_dust_capture(editor)
        } else if capture_story_meeting_mode {
            seed_default_island_towns(editor)
            editor.story_state = {
                romance = .Meeting,
                repair  = .Repaired,
            }
            niko, iva, center, rotation, found := world_story_meeting_pose(editor)
            if !found {
                fmt.eprintln("story meeting capture could not find Niko's town façade")
                return .Quit
            }
            side := third_person.Vec3{math.cos(rotation), 0, math.sin(rotation)}
            outward := third_person.Vec3{-math.sin(rotation), 0, math.cos(rotation)}
            target := third_person.Vec3{(niko.x + iva.x) * .5, max(niko.y, iva.y) + .72, (niko.z + iva.z) * .5}
            editor.editor_focus = target
            editor.camera_pose = third_person.camera_look_at(
                {
                    center.x + outward.x * 2.55 + side.x * 1.05,
                    center.y + 1.72,
                    center.z + outward.z * 2.55 + side.z * 1.05,
                },
                target,
            )
            atmosphere.set_world_minutes(&editor.atmosphere, 17 * 60)
            atmosphere.set_weather_override(&editor.atmosphere, .Clear)
            editor.atmosphere.weather = atmosphere.weather_for(.Clear)
            editor.atmosphere.paused = true
        } else if capture_building_mode {
            if capture_target == "mouse-town" {
                seed_default_island_towns(editor)
                authoring_select_tool(editor, .Building)
                editor.structure_selected = -1
            } else {
                seed_city_capture(editor)
            }
        } else {
            seed_formation_capture(editor)
            // Keep the flight capture exercising distant road depth precision
            // as the chase camera climbs away from the authored island.
            if capture_flight_mode do seed_road_capture(editor)
        }
        if !capture_foliage_stress_mode && !capture_foliage_forest_mode && !capture_story_meeting_mode {
            editor.editor_camera.distance = 260
            editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
        }
        if capture_building_mode {
            _ = configure_building_capture_camera(editor, capture_target)
        }
        if capture_foliage_low_mode {
            // A near-canopy cinematic angle verifies that authored forest
            // patches read as trees, not merely attractive shapes from above.
            editor.editor_focus.y = 22
            editor.editor_camera.pitch_radians = .08
            editor.editor_camera.distance = 350
            editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
        }
        if capture_foliage_understory_mode {
            configure_foliage_understory_camera(editor)
        }
    }
    if capture_lab_mode {
        _ = lab_scene_load(editor, {definition = lab_scene_find(capture_lab_name), target = capture_target})
        if capture_markov_town_mode && capture_target == "night" {
            editor.settlement_diagnostic_layer = -1
            editor.capture_world_only = true
            atmosphere.set_world_minutes(&editor.atmosphere, 0)
            atmosphere.set_weather_override(&editor.atmosphere, .Clear)
            editor.atmosphere.weather = atmosphere.weather_for(.Clear)
            editor.atmosphere.paused = true
        }
    } else if interactive_lab_mode {
        _ = lab_scene_load(editor, interactive_lab_request)
    } else if legacy_shadow_lab_mode {
        _ = lab_scene_load(editor, {definition = lab_scene_find("shadow")})
    }
    if capture_sky_mode {
        preset := atmosphere.Weather_Preset.Clear
        minutes := f32(12 * 60)
        #partial switch capture_kind {
        case .Sky_Sunset:
            minutes = 18 * 60
        case .Sky_Storm:
            minutes = 13 * 60
            preset = .Storm
        case .Sky_Night:
            minutes = 0
        }
        if capture_target == "moon" do minutes = 2 * 60
        atmosphere.set_world_minutes(&editor.atmosphere, minutes)
        if capture_target == "moon" {
            atmosphere.set_lunar_age(&editor.atmosphere, atmosphere.SYNODIC_MONTH_DAYS * .5)
        } else if capture_target == "stars" {
            atmosphere.set_lunar_age(&editor.atmosphere, 0)
        }
        atmosphere.set_weather_override(&editor.atmosphere, preset)
        editor.atmosphere.weather = atmosphere.weather_for(preset)
        if capture_target == "sun" ||
           capture_target == "sun-air" ||
           capture_target == "sun-away" ||
           capture_target == "moon" ||
           capture_target == "stars" {
            editor.atmosphere.weather.cloud_cover = 0
        }
        editor.atmosphere.paused = true
    }
    if capture_foliage_motion_mode {
        atmosphere.set_world_minutes(&editor.atmosphere, 9 * 60 + 30)
        atmosphere.set_weather_override(&editor.atmosphere, .Windy)
        editor.atmosphere.weather = atmosphere.weather_for(.Windy)
        editor.atmosphere.front_seconds = 0
        if capture_kind == .Foliage_Wind_B || capture_kind == .Foliage_Low_Wind_B {
            editor.atmosphere.front_seconds = 4.25
        }
        editor.atmosphere.paused = true
    }
    if capture_grass_wind_mode {
        atmosphere.set_world_minutes(&editor.atmosphere, 10 * 60 + 15)
        atmosphere.set_weather_override(&editor.atmosphere, .Windy)
        editor.atmosphere.weather = atmosphere.weather_for(.Windy)
        editor.atmosphere.front_seconds = 2.4
        editor.atmosphere.paused = true
    }
    if capture_foliage_golden_mode {
        atmosphere.set_world_minutes(&editor.atmosphere, 17 * 60)
        atmosphere.set_weather_override(&editor.atmosphere, .Clear)
        editor.atmosphere.weather = atmosphere.weather_for(.Clear)
        editor.atmosphere.front_seconds = 2.75
        editor.atmosphere.paused = true
    }
    if capture_foliage_low_mode && !capture_foliage_motion_mode {
        atmosphere.set_world_minutes(&editor.atmosphere, 16 * 60 + 15)
        atmosphere.set_weather_override(&editor.atmosphere, .Clear)
        editor.atmosphere.weather = atmosphere.weather_for(.Clear)
        editor.atmosphere.front_seconds = 1.75
        editor.atmosphere.paused = true
    }
    if capture_building_mode {
        // A warm, still late-afternoon preset gives stucco and terracotta a
        // hand-painted Mediterranean glow while keeping the capture stable.
        atmosphere.set_world_minutes(&editor.atmosphere, 16 * 60 + 45)
        atmosphere.set_weather_override(&editor.atmosphere, .Clear)
        editor.atmosphere.weather = atmosphere.weather_for(.Clear)
        editor.atmosphere.front_seconds = .75
        editor.atmosphere.paused = true
    }
    if benchmark_mode {
        if !benchmark_seed_scene(editor, benchmark_scenario) {
            fmt.eprintf("unknown benchmark scenario: %s\n", benchmark_scenario)
            return .Quit
        }
        atmosphere.set_world_minutes(&editor.atmosphere, 9 * 60 + 30)
        atmosphere.set_weather_override(&editor.atmosphere, .Clear)
        editor.atmosphere.weather = atmosphere.weather_for(.Clear)
        editor.atmosphere.paused = true
    }
    hot_library_path := ""
    hot_state_path := ""
    hot_library_mtime: i64
    state_loaded := false
    when HOT_RELOAD {
        hot_library_path = os.get_env(HOT_LIBRARY_ENV, context.temp_allocator)
        hot_state_path = os.get_env("ADRIATIC_HOT_STATE", context.temp_allocator)
        if hot_library_path != "" {
            modified, err := os.modification_time_by_path(hot_library_path)
            if err == nil do hot_library_mtime = time.time_to_unix_nano(modified)
        }
    }
    world_renderer_attach(editor)
    if show_loading_screen {
        draw_startup_loading_screen(initial_width, initial_height, .92, "Lighting the coast...", postcard)
    }
    defer world_renderer_destroy()
    if capture_gameplay_mode {
        if (capture_map_mode && !capture_lab_mode) || capture_flight_mode || capture_car_mode {
            editor.player = {
                position = runway_spawn_position(editor),
                grounded = true,
            }
            editor.camera = third_person.default_camera()
            editor.camera_pose = third_person.camera_pose(editor.player.position, editor.camera)
        } else {
            // Scene-specific captures author their framing before the renderer
            // attaches. Enter gameplay without replacing that camera, and put
            // the player at its focus so range-limited gameplay vegetation is
            // populated around what the capture is actually inspecting.
            editor.player = {
                position = {
                    editor.editor_focus.x,
                    terrain.sample_height(&editor.project, 0, editor.editor_focus.x, editor.editor_focus.z),
                    editor.editor_focus.z,
                },
                grounded = true,
            }
            editor.camera = third_person.default_camera()
            third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
            third_person.camera_set_active(&editor.cameras, .Inspection)
            editor.capture_world_only = true
        }
        if capture_sky_mode &&
           (capture_target == "sun" ||
                   capture_target == "sun-air" ||
                   capture_target == "sun-away" ||
                   capture_target == "moon" ||
                   capture_target == "stars") {
            sky_capture := atmosphere.sample(&editor.atmosphere)
            // Observer elevation materially changes the required reflecting
            // slopes, so retain matched on-foot and airborne verification
            // views instead of tuning the BRDF to either camera.
            eye_height := capture_target == "sun-air" ? f32(180) : f32(3.2)
            eye := third_person.Vec3{0, eye_height, 0}
            view_sign := capture_target == "sun-away" ? f32(-1) : f32(1)
            view_direction := sky_capture.sun_direction
            if capture_target == "moon" do view_direction = sky_capture.moon_direction
            if capture_target == "stars" do view_direction = {0, .64, .77}
            editor.camera_pose = third_person.camera_look_at(
                eye,
                {
                    eye.x + view_direction[0] * 100 * view_sign,
                    eye.y + view_direction[1] * 100 + 1.2,
                    eye.z + view_direction[2] * 100 * view_sign,
                },
            )
            third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
            third_person.camera_set_active(&editor.cameras, .Inspection)
            editor.capture_world_only = true
        }
        editor.pilot.position = editor.player.position
        editor.in_map = true
        editor.map_time = f32(rl.GetTime())
        if capture_flight_mode {
            _, entered := vehicles.try_enter_nearest(&editor.pilot, []^vehicles.Vehicle{&editor.postale.vehicle})
            if entered {
                // Give the flight capture a reproducible airborne state so visual
                // verification exercises the wing-trail and wind-response systems.
                editor.postale.body.position.y += 85
                editor.postale.body.velocity = editor.postale.body.basis.forward * 58
                editor.postale.grounded = false
                editor.postale.was_grounded = false
                editor.postale.throttle = .82
                atmosphere.set_weather_override(&editor.atmosphere, .Windy)
                editor.atmosphere.weather = atmosphere.weather_for(.Windy)
                editor.atmosphere.paused = true
                chase_camera.reset(&editor.flight_camera, aircraft_camera_target(editor))
                editor.camera_pose = editor.flight_camera.pose
            }
        }
        if capture_car_mode {
            car := car_spawn_position(editor)
            editor.player.position = {car.x + 100, car.y, car.z + 100}
            editor.pilot.position = editor.player.position
            editor.camera_pose = {
                position = {car.x - 7.5, car.y + 4.6, car.z + 7.5},
                target   = {car.x, car.y + .65, car.z},
            }
        }
        if !capture_vehicle_showcase_mode && capture_target == "libellula" {
            editor.camera_target_lock = true
            // Keep the deterministic model-inspection capture focused on the
            // Libellula instead of allowing the default car and Postale spawns
            // to overlap its suspension and landing gear.
            editor.postale_visible = false
            editor.car.position.x += 100
            editor.car.position.z += 100
            editor.player.position = {
                editor.libellula.vehicle.position.x + 12,
                terrain.sample_height(
                    &editor.project,
                    0,
                    editor.libellula.vehicle.position.x + 12,
                    editor.libellula.vehicle.position.z + 12,
                ),
                editor.libellula.vehicle.position.z + 12,
            }
            editor.pilot.position = editor.player.position
            inspection_pose := third_person.camera_near(editor.libellula.vehicle.position, {6, 3.5, 6})
            third_person.camera_set_pose(&editor.cameras, .Inspection, inspection_pose)
            third_person.camera_set_active(&editor.cameras, .Inspection)
            editor.camera_pose = inspection_pose
        }
        if !capture_vehicle_showcase_mode && capture_target == "postale" {
            editor.camera_target_lock = true
            postale_position := third_person.Vec3 {
                editor.postale.body.position.x,
                editor.postale.body.position.y,
                editor.postale.body.position.z,
            }
            editor.player.position = {
                postale_position.x + 12,
                terrain.sample_height(&editor.project, 0, postale_position.x + 12, postale_position.z + 12),
                postale_position.z + 12,
            }
            editor.pilot.position = editor.player.position
            inspection_pose := third_person.camera_near(postale_position, {4.5, 2.6, 4.5})
            third_person.camera_set_pose(&editor.cameras, .Inspection, inspection_pose)
            third_person.camera_set_active(&editor.cameras, .Inspection)
            editor.camera_pose = inspection_pose
        }
        if !capture_vehicle_showcase_mode && (capture_target == "marta" || capture_target == "gerta") {
            editor.camera_target_lock = false
            editor.postale_visible = false
            attendant := capture_target == "gerta" ? editor.gerta_position : editor.attendant_position
            editor.player.position = {
                attendant.x + 20,
                terrain.sample_height(&editor.project, 0, attendant.x + 20, attendant.z),
                attendant.z,
            }
            editor.pilot.position = editor.player.position
            inspection_pose := third_person.camera_near(
                {attendant.x, attendant.y + .48, attendant.z},
                {1.35, .62, 1.35},
            )
            third_person.camera_set_pose(&editor.cameras, .Inspection, inspection_pose)
            third_person.camera_set_active(&editor.cameras, .Inspection)
            editor.camera_pose = inspection_pose
        }
        if capture_target == "niko" ||
           capture_target == "iva" ||
           capture_target == "bojan" ||
           capture_target == "zora" ||
           capture_target == "zora-reading" {
            seed_default_island_towns(editor)
            resident := story.Resident.Niko
            switch capture_target {
            case "iva":
                resident = .Iva
            case "bojan":
                resident = .Bojan
            case "zora", "zora-reading":
                resident = .Zora
            }
            position, found := world_story_resident_position(editor, resident)
            if found {
                editor.camera_target_lock = false
                editor.postale_visible = false
                editor.libellula_visible = false
                editor.player.position = {
                    position.x + 20,
                    terrain.sample_height(&editor.project, 0, position.x + 20, position.z),
                    position.z,
                }
                editor.pilot.position = editor.player.position
                inspection_pose := third_person.camera_near(
                    {position.x, position.y + .48, position.z},
                    {1.35, .62, 1.35},
                )
                third_person.camera_set_pose(&editor.cameras, .Inspection, inspection_pose)
                third_person.camera_set_active(&editor.cameras, .Inspection)
                editor.camera_pose = inspection_pose
            }
            if capture_target == "zora-reading" && open_story_dialogue(editor, .Zora) {
                _ = dialogue.choose(&editor.attendant_dialogue, 1)
            }
        }
        if capture_target == "player" ||
           capture_target == "player-front" ||
           capture_target == "player-three-quarter" ||
           capture_target == "player-profile" ||
           capture_target == "player-walk" ||
           capture_target == "player-run-compress" ||
           capture_target == "player-turn-left" ||
           capture_target == "player-turn-right" ||
           capture_target == "player-brake" ||
           capture_target == "player-jump" ||
           capture_target == "player-fall" ||
           capture_target == "player-blink" ||
           capture_target == "player-posted" ||
           capture_target == "player-customization" ||
           capture_target == "player-hat-acorn" ||
           capture_target == "player-hat-acorn-front" ||
           capture_target == "player-hat-acorn-profile" ||
           capture_target == "player-hat-bottle-cap" ||
           capture_target == "player-hat-bottle-cap-front" ||
           capture_target == "player-hat-bottle-cap-profile" ||
           capture_target == "player-hat-bottle-cap-top" ||
           capture_target == "player-hat-paper-boat" ||
           capture_target == "player-hat-chef" ||
           capture_target == "player-hat-ushanka" ||
           capture_target == "player-hat-ushanka-three-quarter" ||
           capture_target == "player-hat-ushanka-profile" ||
           capture_target == "player-hat-beret" ||
           capture_target == "player-hat-beret-front" ||
           capture_target == "player-hat-beret-profile" ||
           capture_target == "player-hat-beret-walk" ||
           capture_target == "player-hat-beret-turn-left" ||
           capture_target == "player-hat-alpine" ||
           capture_target == "player-hat-alpine-front" ||
           capture_target == "player-hat-alpine-profile" ||
           capture_target == "player-hat-flat-cap" ||
           capture_target == "player-hat-flat-cap-front" ||
           capture_target == "player-hat-flat-cap-three-quarter" ||
           capture_target == "player-hat-flat-cap-profile" {
            editor.camera_target_lock = false
            editor.postale_visible = false
            editor.libellula_visible = false
            editor.player.position.x += 24
            editor.player.position.z += 20
            editor.player.position.y = terrain.sample_height(
                &editor.project,
                0,
                editor.player.position.x,
                editor.player.position.z,
            )
            editor.pilot.position = editor.player.position
            editor.player.facing_yaw_radians = -.70
            editor.pilot.facing_yaw_radians = editor.player.facing_yaw_radians
            editor.capture_player_walk_pose =
                capture_target == "player-walk" || capture_target == "player-hat-beret-walk"
            editor.capture_player_run_compress_pose = capture_target == "player-run-compress"
            editor.capture_player_turn_left_pose =
                capture_target == "player-turn-left" || capture_target == "player-hat-beret-turn-left"
            editor.capture_player_turn_right_pose = capture_target == "player-turn-right"
            editor.capture_player_brake_pose = capture_target == "player-brake"
            editor.capture_player_jump_pose = capture_target == "player-jump"
            editor.capture_player_fall_pose = capture_target == "player-fall"
            editor.capture_player_blink_pose = capture_target == "player-blink"
            editor.capture_player_posted_pose = capture_target == "player-posted"
            if capture_target == "player-customization" ||
               capture_target == "player-hat-acorn" ||
               capture_target == "player-hat-acorn-front" ||
               capture_target == "player-hat-acorn-profile" ||
               capture_target == "player-hat-bottle-cap" ||
               capture_target == "player-hat-bottle-cap-front" ||
               capture_target == "player-hat-bottle-cap-profile" ||
               capture_target == "player-hat-bottle-cap-top" ||
               capture_target == "player-hat-paper-boat" ||
               capture_target == "player-hat-chef" ||
               capture_target == "player-hat-ushanka" ||
               capture_target == "player-hat-ushanka-three-quarter" ||
               capture_target == "player-hat-ushanka-profile" ||
               capture_target == "player-hat-beret" ||
               capture_target == "player-hat-beret-front" ||
               capture_target == "player-hat-beret-profile" ||
               capture_target == "player-hat-beret-walk" ||
               capture_target == "player-hat-beret-turn-left" ||
               capture_target == "player-hat-alpine" ||
               capture_target == "player-hat-alpine-front" ||
               capture_target == "player-hat-alpine-profile" ||
               capture_target == "player-hat-flat-cap" ||
               capture_target == "player-hat-flat-cap-front" ||
               capture_target == "player-hat-flat-cap-three-quarter" ||
               capture_target == "player-hat-flat-cap-profile" {
                editor.mouse_fur = .Silver
                editor.mouse_pattern = .Piebald
                switch capture_target {
                case "player-hat-acorn", "player-hat-acorn-front", "player-hat-acorn-profile":
                    editor.mouse_headgear = .Acorn_Cap
                case "player-hat-bottle-cap",
                     "player-hat-bottle-cap-front",
                     "player-hat-bottle-cap-profile",
                     "player-hat-bottle-cap-top":
                    editor.mouse_headgear = .Bottle_Cap
                case "player-hat-paper-boat":
                    editor.mouse_headgear = .Paper_Boat
                case "player-hat-ushanka", "player-hat-ushanka-three-quarter", "player-hat-ushanka-profile":
                    editor.mouse_headgear = .Ushanka
                case "player-hat-beret",
                     "player-hat-beret-front",
                     "player-hat-beret-profile",
                     "player-hat-beret-walk",
                     "player-hat-beret-turn-left":
                    editor.mouse_headgear = .Beret
                case "player-hat-alpine", "player-hat-alpine-front", "player-hat-alpine-profile":
                    editor.mouse_headgear = .Alpine_Hat
                case "player-hat-flat-cap",
                     "player-hat-flat-cap-front",
                     "player-hat-flat-cap-three-quarter",
                     "player-hat-flat-cap-profile":
                    editor.mouse_headgear = .Flat_Cap
                case:
                    editor.mouse_headgear = .Chef_Hat
                }
            }
            if editor.capture_player_jump_pose || editor.capture_player_fall_pose {
                editor.player.position.y += .42
                editor.player.velocity.y = editor.capture_player_jump_pose ? f32(3.2) : f32(-3.2)
                editor.player.grounded = false
                editor.pilot.position = editor.player.position
            }
            capture_forward := third_person.Vec3 {
                -math.sin(editor.player.facing_yaw_radians),
                0,
                -math.cos(editor.player.facing_yaw_radians),
            }
            capture_run_pose :=
                capture_target == "player-walk" ||
                capture_target == "player-run-compress" ||
                capture_target == "player-hat-beret-walk"
            capture_posted_pose := capture_target == "player-posted"
            capture_front_view :=
                capture_target == "player-front" ||
                capture_target == "player-hat-acorn-front" ||
                capture_target == "player-hat-bottle-cap-front" ||
                capture_target == "player-hat-beret-front" ||
                capture_target == "player-hat-alpine-front" ||
                capture_target == "player-hat-flat-cap-front"
            capture_three_quarter_view :=
                capture_target == "player-three-quarter" ||
                capture_target == "player-hat-ushanka-three-quarter" ||
                capture_target == "player-hat-flat-cap-three-quarter"
            capture_profile_view :=
                capture_target == "player-profile" ||
                capture_target == "player-hat-acorn-profile" ||
                capture_target == "player-hat-bottle-cap-profile" ||
                capture_target == "player-hat-ushanka-profile" ||
                capture_target == "player-hat-beret-profile" ||
                capture_target == "player-hat-alpine-profile" ||
                capture_target == "player-hat-flat-cap-profile"
            capture_top_view := capture_target == "player-hat-bottle-cap-top"
            // Track the moving profile from its longitudinal center so the
            // body and body-length tail share one depth plane in the capture.
            capture_front_distance := capture_run_pose ? f32(-.45) : (capture_posted_pose ? f32(1.32) : f32(1.95))
            capture_side_distance := capture_run_pose ? f32(2.45) : (capture_posted_pose ? f32(1.20) : f32(.40))
            if capture_front_view {
                capture_front_distance = 1.95
                capture_side_distance = 0
            }
            if capture_three_quarter_view {
                capture_front_distance = 1.72
                capture_side_distance = .92
            }
            if capture_profile_view {
                capture_front_distance = 0
                capture_side_distance = 1.95
            }
            capture_height := capture_run_pose ? f32(.62) : (capture_posted_pose ? f32(.90) : f32(.78))
            inspection_pose := third_person.Camera_Pose {
                position = {
                    editor.player.position.x +
                    capture_forward.x * capture_front_distance +
                    capture_forward.z * capture_side_distance,
                    editor.player.position.y + capture_height,
                    editor.player.position.z +
                    capture_forward.z * capture_front_distance -
                    capture_forward.x * capture_side_distance,
                },
                target   = {
                    editor.player.position.x - capture_forward.x * (capture_run_pose ? f32(.52) : f32(.18)),
                    editor.player.position.y + (capture_posted_pose ? f32(.48) : f32(.34)),
                    editor.player.position.z - capture_forward.z * (capture_run_pose ? f32(.52) : f32(.18)),
                },
            }
            if capture_top_view {
                // A slightly oblique overhead view avoids the camera-up
                // singularity while keeping the printed crown face dominant.
                inspection_pose.position = {
                    editor.player.position.x - capture_forward.x * .22,
                    editor.player.position.y + 2.05,
                    editor.player.position.z - capture_forward.z * .22,
                }
                inspection_pose.target = {
                    editor.player.position.x,
                    editor.player.position.y + .54,
                    editor.player.position.z,
                }
            }
            third_person.camera_set_pose(&editor.cameras, .Inspection, inspection_pose)
            third_person.camera_set_active(&editor.cameras, .Inspection)
            editor.camera_pose = inspection_pose
        }
        if capture_grass_wind_mode || capture_target == "grass" {
            editor.capture_world_only = true
            editor.postale_visible = false
            editor.libellula_visible = false
            editor.player.position.x += 24
            // Clear the runway and its shoulder so the full radial grass
            // population falloff is visible against uninterrupted terrain.
            editor.player.position.z += 60
            editor.player.position.y = terrain.sample_height(
                &editor.project,
                0,
                editor.player.position.x,
                editor.player.position.z,
            )
            editor.pilot.position = editor.player.position
            grass_pose := third_person.camera_look_at(
                {editor.player.position.x + 8, editor.player.position.y + 1.65, editor.player.position.z + 15},
                {editor.player.position.x - 2, editor.player.position.y + .55, editor.player.position.z - 9},
            )
            third_person.camera_set_pose(&editor.cameras, .Inspection, grass_pose)
            third_person.camera_set_active(&editor.cameras, .Inspection)
            editor.camera_pose = grass_pose
        }
        if capture_target == "pause" do editor.pause_screen = .Pause
        if capture_target == "options" do editor.pause_screen = .Options
        if capture_target == "options-hdr" {
            editor.pause_screen = .Options
            editor.options_focus = 7
            editor.options_scroll_y = 300
        }
        if capture_target == "customization" {
            editor.pause_screen = .Customization
            editor.mouse_fur = .Russet
            editor.mouse_pattern = .Piebald
            editor.mouse_headgear = .Acorn_Cap
        }
        if capture_target == "options-240" {
            editor.pause_screen = .Options
            editor.gameplay_options.crunchiness = .P240
            crunchiness_apply(editor.gameplay_options.crunchiness)
        }
    }
    if vehicle_showcase_mode {
        target := showcase_target
        if target == "" do target = "postale"
        showcase_view := target
        if target == "postale-overhead" || target == "postale-overhead-front" || target == "postale-overhead-rear" {
            target = "postale"
        }
        if target != "postale" && target != "libellula" && target != "libellula-mk2" && target != "car" {
            fmt.eprintf(
                "vehicle showcase target must be postale, postale-overhead[-front|-rear], libellula, libellula-mk2, or car\n",
            )
            return .Quit
        }
        editor.vehicle_showcase_scene = true
        editor.vehicle_showcase_target = target
        editor.in_map = true
        editor.map_time = 0
        if target == "postale" do editor.aircraft.active = .Postale
        if target == "libellula" do editor.aircraft.active = .Libellula
        if target == "libellula-mk2" do editor.aircraft.active = .Libellula_Mk2
        editor.postale_visible = target == "postale"
        editor.libellula_visible = target == "libellula" || target == "libellula-mk2"
        editor.libellula.vehicle.locked = false
        editor.postale.body.position = {0, postale_game.GROUND_CLEARANCE, 0}
        editor.postale.vehicle.position = {0, postale_game.GROUND_CLEARANCE, 0}
        editor.libellula.body.position = {0, libellula_game.GROUND_CLEARANCE, 0}
        editor.libellula.vehicle.position = {0, libellula_game.GROUND_CLEARANCE, 0}
        editor.car.position = {}
        editor.car.yaw_radians = -math.PI * .5
        // Default showcase framing: aligned with the vehicle's forward axis,
        // with a modest elevation for the isometric presentation.
        editor.camera = {
            yaw_radians   = -math.PI * .38,
            pitch_radians = .18,
            distance      = 6.2,
            height        = 1,
        }
        editor.pilot.position = {}
        if target == "postale" do editor.pilot.position.y = postale_game.GROUND_CLEARANCE
        if target == "libellula" || target == "libellula-mk2" do editor.pilot.position.y = libellula_game.GROUND_CLEARANCE
        editor.pilot.mode = .On_Foot
        editor.pilot.vehicle = nil
        if target == "postale" {
            _, entered := vehicles.try_enter_nearest(&editor.pilot, []^vehicles.Vehicle{&editor.postale.vehicle})
            if !entered do return .Quit
            switch showcase_view {
            case "postale-overhead":
                // A tiny longitudinal offset keeps the camera basis stable
                // while remaining visually indistinguishable from a true
                // orthographic-style plan view.
                editor.camera_pose = third_person.camera_look_at({.01, 8.2, .35}, {0, .15, 0})
            case "postale-overhead-front":
                editor.camera_pose = third_person.camera_look_at({0, 7.5, -3.0}, {0, .15, 0})
            case "postale-overhead-rear":
                editor.camera_pose = third_person.camera_look_at({0, 7.5, 3.0}, {0, .15, 0})
            case:
                editor.camera_pose = third_person.camera_look_at({10.5, 5.7, 10.5}, {0, .45, 0})
            }
        } else if target == "libellula" || target == "libellula-mk2" {
            _, entered := vehicles.try_enter_nearest(&editor.pilot, []^vehicles.Vehicle{&editor.libellula.vehicle})
            if !entered do return .Quit
            editor.camera_pose = third_person.camera_look_at({6, 5.8, 10}, {0, 1.2, 0})
        } else {
            _, entered := vehicles.try_enter_nearest(&editor.pilot, []^vehicles.Vehicle{&editor.car})
            if !entered do return .Quit
            // A true side elevation makes the wheelbase, overhangs, beltline,
            // and mouse-to-car scale directly comparable in capture reviews.
            editor.camera_pose = third_person.camera_look_at({5.4, 2.0, 0}, {0, .56, 0})
        }
        third_person.camera_set_pose(&editor.cameras, .Player, editor.camera_pose)
        third_person.camera_set_active(&editor.cameras, .Player)
        atmosphere.set_world_minutes(&editor.atmosphere, 16 * 60 + 45)
        atmosphere.set_weather_override(&editor.atmosphere, .Clear)
        editor.atmosphere.weather = atmosphere.weather_for(.Clear)
        editor.atmosphere.paused = true
        if capture_paint_mode {
            if target == "car" {
                fmt.eprintf("paint mode target must be postale, libellula, or libellula-mk2\n")
                return .Quit
            }
            vehicle_paint_open(editor)
            if os.get_env("ADRIATIC_CAPTURE_PAINT_PANEL", context.temp_allocator) == "hidden" {
                editor.vehicle_paint_panel_visible = false
            }
        }
    }
    if capture_road_mode {
        editor.capture_world_only = true
        editor.editor_camera.distance = capture_road_dust_mode ? 165 : 210
        editor.editor_focus.x = island_center - 20
        editor.editor_focus.z = island_center - 5
        if capture_road_dust_mode && capture_target != "" {
            target_pavement := roads.Pavement.Asphalt
            switch capture_target {
            case "gravel":
                target_pavement = .Gravel
            case "cobble":
                target_pavement = .Cobblestone
            case "dirt":
                target_pavement = .Dirt
            }
            for edge in editor.project.road_graph.edges[:editor.project.road_graph.edge_count] {
                if edge.pavement != target_pavement do continue
                point := roads.edge_point(&editor.project.road_graph, edge, .58)
                editor.editor_focus = {point.x, point.y + .5, point.z}
                editor.editor_camera.distance = 34
                editor.editor_camera.pitch_radians = .28
                break
            }
        }
        editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    }
    if capture_road_grip_mode {
        editor.capture_world_only = true
        editor.editor_focus = {editor.car.position.x, editor.car.position.y + .75, editor.car.position.z}
        editor.editor_camera = {
            yaw_radians   = math.PI * .72,
            pitch_radians = .48,
            distance      = 52,
        }
        editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    }
    if capture_terrain_grip_mode {
        editor.capture_world_only = true
        editor.editor_focus = {editor.car.position.x, editor.car.position.y + .75, editor.car.position.z}
        editor.editor_camera = {
            yaw_radians   = math.PI * .72,
            pitch_radians = .48,
            distance      = 48,
        }
        editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    }
    when HOT_RELOAD {
        switch hot_state_load(editor, hot_state_path) {
        case .Invalid:
            fmt.eprintln("adriatic hot reload state is irreparable; starting clean")
            return .Restart
        case .Loaded:
            state_loaded = true
        case .Missing:
        }
    }
    // Catalog slices point into this Editor instance and must never retain
    // addresses serialized from a previous hot-loaded dylib.
    story.init_catalog(&editor.story_catalog)
    if !state_loaded do control_hints_load(editor)
    if show_loading_screen {
        draw_startup_loading_screen(initial_width, initial_height, 1, "Welcome to Adriatic", postcard)
        editor.main_menu_active = true
        editor.main_menu_focus = 0
        editor.pause_screen = .Closed
        set_pointer_locked(false)
    }
    benchmark_samples: [4096]f64
    benchmark_sample_count := 0
    frame := 0
    for !rl.WindowShouldClose() && !editor.quit_requested {
        dio.flame_graph_begin_frame(&editor.flame_graph)
        benchmark_frame_start := rl.GetTime()
        frame_now := rl.GetTime()
        frame_delta := frame == 0 ? f32(0) : min(f32(frame_now - editor.last_frame_time), f32(.1))
        editor.last_frame_time = frame_now
        // map_time drives low-frequency presentation animation. Keep it
        // separate from the f64 clock used for simulation deltas: subtracting
        // absolute f32 timestamps loses frame-scale precision as uptime grows.
        editor.map_time = f32(frame_now)
        driving := editor.pilot.mode == .Driving
        dialogue_was_open := editor.attendant_dialogue_open
        width, height := rl.GetScreenWidth(), rl.GetScreenHeight()
        input_result := runtime_input_update(editor)
        if input_result.pause_for_disconnect {
            editor.controller_disconnect_notice = true
            if !pause_menu_is_open(editor) do pause_menu_open(editor)
        }
        if !pause_menu_is_open(editor) do game_input.reset_menu_repeat(&editor.runtime_input)
        was_paused := pause_menu_is_open(editor)
        console_process_input(editor, width, height)
        if !editor.console.open do pause_menu_process_input(editor, width, height, frame_delta)
        runtime_pointer_sync(editor)
        attendant_dialogue_process_input(editor, width, height, frame_delta)
        simulation_delta := was_paused || pause_menu_is_open(editor) ? f32(0) : frame_delta
        atmosphere.step(&editor.atmosphere, simulation_delta)
        boats.step(&editor.boat_traffic, simulation_delta, editor.atmosphere.world_minutes)
        markov_marina_buoy_physics_step(editor, simulation_delta)
        wind_x, wind_z := editor.atmosphere.weather.wind[0], editor.atmosphere.weather.wind[1]
        wind_speed := f32(math.sqrt(f64(wind_x * wind_x + wind_z * wind_z)))
        listener_yaw := editor.in_map ? editor.camera.yaw_radians : editor.editor_camera.yaw_radians
        listener_velocity_x, listener_velocity_z := f32(0), f32(0)
        if editor.in_map {
            if driving_aircraft(editor) {
                listener_body := active_aircraft_body(editor)
                listener_velocity_x, listener_velocity_z = listener_body.velocity.x, listener_body.velocity.z
            } else if driving_car(editor) {
                listener_velocity_x, listener_velocity_z =
                    editor.car_drive.velocity.x * .35, editor.car_drive.velocity.z * .35
            } else {
                listener_velocity_x, listener_velocity_z =
                    editor.player.velocity.x * .55, editor.player.velocity.z * .55
            }
        }
        apparent_airflow_speed := wind_audio.apparent_airflow_speed(
            wind_x,
            wind_z,
            listener_velocity_x,
            listener_velocity_z,
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
                &wind_sound,
                apparent_airflow_speed,
                0,
                editor.atmosphere.weather.precipitation,
                editor.atmosphere.weather.severity,
                wind_direction,
                pause_menu_is_open(editor),
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
                &ocean_sound,
                wind_speed,
                editor.atmosphere.weather.severity,
                pause_menu_is_open(editor),
                listener_height_above_sea,
                shore_proximity,
                ocean_direction,
            )
        }
        if spray_audio_ready {
            spray_active := editor.vehicle_paint_scene && f32(rl.GetTime()) < editor.vehicle_paint_sound_until
            spray_intensity := .45 + f32(editor.vehicle_paint_brush_radius) / 40 * .55
            spray_pan := f32(0)
            screen_width := rl.GetScreenWidth()
            if screen_width > 0 {
                spray_pan = clamp(rl.GetMousePosition().x / f32(screen_width) * 2 - 1, -1, 1)
            }
            spray_audio.update(&spray_sound, spray_active, spray_intensity, spray_pan, pause_menu_is_open(editor))
        }
        if !pause_menu_is_open(editor) && editor.active_lab_scene != "" {
            _ = lab_scene_process_input(editor)
        } else if !pause_menu_is_open(editor) {
            if rl.IsKeyPressed(.P) do editor.atmosphere.paused = !editor.atmosphere.paused
            if rl.IsKeyDown(.LEFT) do atmosphere.set_world_minutes(&editor.atmosphere, editor.atmosphere.world_minutes - frame_delta * 180)
            if rl.IsKeyDown(.RIGHT) do atmosphere.set_world_minutes(&editor.atmosphere, editor.atmosphere.world_minutes + frame_delta * 180)
            if rl.IsKeyPressed(.FOUR) do atmosphere.set_weather_override(&editor.atmosphere, .Automatic)
            if rl.IsKeyPressed(.ONE) do atmosphere.set_weather_override(&editor.atmosphere, .Clear)
            if rl.IsKeyPressed(.TWO) do atmosphere.set_weather_override(&editor.atmosphere, .Windy)
            if rl.IsKeyPressed(.THREE) do atmosphere.set_weather_override(&editor.atmosphere, .Storm)
        }
        if !pause_menu_is_open(editor) && editor_debug_toggle_pressed(editor) {
            editor.tweak_panel_visible = !editor.tweak_panel_visible
        }
        if !editor.in_map && !pause_menu_is_open(editor) do editor_ui_process_input(editor, width, height)
        if !editor.in_map && !pause_menu_is_open(editor) {
            if !imgui_captures_keyboard() && rl.IsKeyPressed(.ESCAPE) do editor_cancel_interaction(editor)
            if !imgui_captures_keyboard() {
                if rl.IsKeyPressed(.T) do authoring_select_tool(editor, .Paint)
                if rl.IsKeyPressed(.B) do authoring_select_tool(editor, .Formations)
                if rl.IsKeyPressed(.H) do authoring_select_tool(editor, .Foliage)
                if !control_key_down() && rl.IsKeyPressed(.Z) do authoring_select_tool(editor, .Ridge)
                if !control_key_down() && rl.IsKeyPressed(.C) do authoring_select_tool(editor, .Cliff)
                if !control_key_down() && rl.IsKeyPressed(.N) do authoring_select_tool(editor, .Building)
                if !control_key_down() && rl.IsKeyPressed(.J) do authoring_select_tool(editor, .Marina)
                if !control_key_down() && rl.IsKeyPressed(.K) do authoring_select_tool(editor, .Farm)
                if !control_key_down() && rl.IsKeyPressed(.L) do authoring_select_tool(editor, .ClimbingLeaves)
                if rl.IsKeyPressed(.M) do authoring_select_tool(editor, .Roads)
                if !control_key_down() && rl.IsKeyPressed(.G) do authoring_select_tool(editor, .GreekAssets)
            }
            if !imgui_captures_keyboard() && control_key_down() && rl.IsKeyPressed(.G) {
                center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
                architecture.generate(&editor.project, center, center, 0xA71D3)
                editor.authoring_tool = .Formations
                editor.tool = .Structure
                editor.road_mode = false
                editor.curve_mode = false
                curve_reset(editor)
                editor.structure_selected = -1
                editor.architecture_node_mode = true
                editor.architecture_paint_mode = false
            }
            if !imgui_captures_keyboard() && rl.IsKeyPressed(.F) do editor_focus_terrain(editor)
            if control_key_down() && rl.IsKeyPressed(.S) do terrain_project_save(editor)
            if control_key_down() && rl.IsKeyPressed(.O) do terrain_project_load(editor)
            if !imgui_captures_keyboard() && editor.tool != .Structure && control_key_down() && rl.IsKeyPressed(.Z) {
                terrain_undo(editor)
            }
            if !imgui_captures_keyboard() && editor.tool != .Structure && control_key_down() && rl.IsKeyPressed(.Y) {
                terrain_redo(editor)
            }
            if !imgui_captures_keyboard() && editor.road_mode && control_key_down() && rl.IsKeyPressed(.Z) {
                structure_undo(editor)
                editor.road_drag_edge = -1
                editor.road_drag_handle = -1
            }
            if !imgui_captures_keyboard() && editor.road_mode && control_key_down() && rl.IsKeyPressed(.Y) {
                structure_redo(editor)
                editor.road_drag_edge = -1
                editor.road_drag_handle = -1
            }
            if !imgui_captures_keyboard() &&
               (editor.marina_paint_mode || editor.farm_paint_mode) &&
               control_key_down() &&
               rl.IsKeyPressed(.Z) {
                structure_undo(editor)
            }
            if !imgui_captures_keyboard() &&
               (editor.marina_paint_mode || editor.farm_paint_mode) &&
               control_key_down() &&
               rl.IsKeyPressed(.Y) {
                structure_redo(editor)
            }
            if !imgui_captures_keyboard() && editor.authoring_tool == .Formations && rl.IsKeyPressed(.V) {
                structure_cycle_kind(editor)
            }
            if !imgui_captures_keyboard() && editor.authoring_tool == .Formations && rl.IsKeyPressed(.X) {
                editor.structure_auto_kind = true
            }
            if !imgui_captures_keyboard() && editor.road_mode && rl.IsKeyPressed(.BACKSPACE) {
                road_delete_selected(editor)
            }
            if !imgui_captures_keyboard() && editor.road_mode && rl.IsKeyPressed(.K) {
                road_cycle_pavement(editor)
            }
            viewport_ui_hit := editor_ui_hit(editor, rl.GetMousePosition(), width, height)
            update_editor_camera(editor, min(frame_delta, f32(.05)))
            viewport_wheel := viewport_ui_hit ? f32(0) : rl.GetMouseWheelMove()
            if editor.greek_placement_mode {
                wheel := viewport_wheel
                if shift_key_down() {
                    editor.greek_asset_scale = clamp(editor.greek_asset_scale + wheel * .05, .25, 3.0)
                } else if alt_key_down() && wheel != 0 {
                    editor.greek_asset_rotation += wheel * .18
                }
            } else if editor.road_mode {
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
                    editor.architecture_brush_strength = clamp(
                        editor.architecture_brush_strength + wheel * .04,
                        .02,
                        1,
                    )
                } else if alt_key_down() {
                    editor.architecture_brush_hardness = clamp(editor.architecture_brush_hardness + wheel * .04, 0, 1)
                }
            } else if editor.tool == .Structure && editor.climbing_leaf_paint_mode {
                wheel := viewport_wheel
                if shift_key_down() {
                    editor.climbing_leaf_brush_strength = clamp(
                        editor.climbing_leaf_brush_strength + wheel * .04,
                        .02,
                        1,
                    )
                } else if alt_key_down() {
                    editor.climbing_leaf_brush_hardness = clamp(
                        editor.climbing_leaf_brush_hardness + wheel * .04,
                        0,
                        1,
                    )
                }
            } else if editor.tool == .Structure &&
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
        focal_length := editor.vehicle_showcase_scene ? VEHICLE_SHOWCASE_FOCAL_LENGTH : f32(1.35)
        if !editor.vehicle_showcase_scene && editor.in_map && driving_aircraft(editor) {
            focal_length = editor.flight_camera.focal_length
        }
        editor_view_camera := perspective_camera(editor.camera_pose, focal_length)
        world_mouse, world_mouse_inside := rl.GetWorldMousePosition()
        world_x, world_z, cursor_hit := terrain_under_cursor_3d(
            editor,
            editor_view_camera,
            world_mouse,
            ADRIATIC_WORLD_WIDTH,
            ADRIATIC_WORLD_HEIGHT,
        )
        cursor_hit = cursor_hit && world_mouse_inside
        ui_hit := editor_ui_hit(editor, rl.GetMousePosition(), width, height)
        editor.cursor_world_x = world_x
        editor.cursor_world_z = world_z
        editor.cursor_hit = cursor_hit && !ui_hit && !editor.in_map
        if editor.cursor_hit {
            editor.cursor_height = terrain.sample_height(&editor.project, 0, world_x, world_z)
            editor.cursor_material = terrain.sample_material(&editor.project, 0, world_x, world_z)
        }
        architecture_paint_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        marina_brush_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        farm_stamp_update_preview(editor, world_x, world_z, cursor_hit && !ui_hit)
        farm_brush_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        climbing_leaf_paint_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        formation_brush_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        greek_placement_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        curve_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        road_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        if !editor.architecture_paint_mode &&
           !editor.marina_paint_mode &&
           !editor.farm_paint_mode &&
           !editor.climbing_leaf_paint_mode &&
           editor.authoring_tool != .Formations &&
           (editor.authoring_tool != .Foliage || editor.foliage_hedgerow_mode) &&
           !editor.greek_placement_mode &&
           !editor.road_mode &&
           !editor.curve_mode &&
           !editor.curve_drawing &&
           editor.curve_point_count == 0 {
            structure_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        }
        crash_severity := f32(0)
        crash_water_mix := f32(0)
        crash_slide_speed := f32(0)
        crash_surface := engine_sound.Crash_Surface.Dirt
        crash_profile := engine_sound.Crash_Profile.Car
        crash_wetness := clamp(editor.atmosphere.weather.precipitation, 0, 1)
        crash_obliqueness := f32(0)
        footstep_triggered := false
        footstep_intensity := f32(0)
        footstep_surface := engine_sound.Footstep_Surface.Grass
        footstep_landing := false
        footstep_slide := f32(0)
        if editor.in_map && !pause_menu_is_open(editor) && !capture_car_mode && !cinematic_is_playing(editor) {
            delta_seconds := frame_delta
            if editor.vehicle_paint_scene {
                vehicle_paint_process_input(editor, width, height, min(delta_seconds, .05))
            } else if editor.vehicle_showcase_scene {
                // Capture setup installs a deterministic target-specific pose.
                // Preserve it instead of replacing it with the interactive
                // orbit camera on the first frame.
                if !capture_mode do vehicle_showcase_camera_step(editor, min(delta_seconds, .05))
            } else {
                mouse_delta := rl.GetMouseDelta()
                look_scale := editor.gameplay_options.look_sensitivity / .012
                look_x := editor.gameplay_options.invert_look_x ? -mouse_delta.x : mouse_delta.x
                look_y := editor.gameplay_options.invert_look_y ? -mouse_delta.y : mouse_delta.y
                flying := driving_aircraft(editor)
                in_car := driving_car(editor)
                if flying {
                    flight_stick_x := gamepad_axis(.Right_X) * 700 * delta_seconds
                    if editor.gameplay_options.invert_look_x do flight_stick_x = -flight_stick_x
                    flight_stick_y := gamepad_axis(.Right_Y) * 700 * delta_seconds
                    if editor.gameplay_options.invert_look_y do flight_stick_y = -flight_stick_y
                    flight_look_x := look_x * look_scale + flight_stick_x
                    flight_look_y := look_y * look_scale + flight_stick_y
                    chase_camera.look(&editor.flight_camera, flight_look_x, flight_look_y)
                    if input_action_pressed(.Camera_Reset) {
                        chase_camera.reset(&editor.flight_camera, aircraft_camera_target(editor))
                    }
                    if input_action_pressed(.Vehicle_Reset) {
                        if editor.aircraft.active != .Postale {
                            ground := terrain.sample_height(
                                &editor.project,
                                0,
                                editor.libellula.spawn_position.x,
                                editor.libellula.spawn_position.z,
                            )
                            libellula_game.reset(&editor.libellula, ground)
                        } else {
                            ground := postale_game.drivable_surface_height(
                                terrain.sample_height(
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
                    control := postale_game.Control {
                        throttle_up   = rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT),
                        throttle_down = control_key_down(),
                    }
                    if rl.IsKeyDown(.S) do control.pitch += 1
                    if rl.IsKeyDown(.W) do control.pitch -= 1
                    if rl.IsKeyDown(.D) do control.roll += 1
                    if rl.IsKeyDown(.A) do control.roll -= 1
                    if rl.IsKeyDown(.E) do control.yaw += 1
                    if rl.IsKeyDown(.Q) do control.yaw -= 1
                    if rl.GamepadAvailable() {
                        control.pitch = stronger_axis(control.pitch, gamepad_axis(.Left_Y))
                        control.roll = stronger_axis(control.roll, gamepad_axis(.Left_X))
                        if gamepad_down(.Right_Shoulder) do control.yaw += 1
                        if gamepad_down(.Left_Shoulder) do control.yaw -= 1
                        control.throttle_up = control.throttle_up || gamepad_axis(.Right_Trigger) > 0
                        control.throttle_down = control.throttle_down || gamepad_axis(.Left_Trigger) > 0
                    }
                    if editor.gameplay_options.invert_flight_pitch do control.pitch = -control.pitch
                    control.pitch = clamp(control.pitch, -1, 1)
                    control.roll = clamp(control.roll, -1, 1)
                    control.yaw = clamp(control.yaw, -1, 1)
                    editor.flight_control = control
                    editor.aircraft_fixed_accumulator = min(
                        editor.aircraft_fixed_accumulator + f64(delta_seconds),
                        AIRCRAFT_MAX_CATCH_UP,
                    )
                    for editor.aircraft_fixed_accumulator >= AIRCRAFT_FIXED_STEP {
                        body := active_aircraft_body(editor)
                        was_crashed := editor.postale.crashed
                        if editor.aircraft.active != .Postale {
                            was_crashed = editor.libellula.crashed
                        }
                        impact_vertical_speed := max(-body.velocity.y, f32(0))
                        editor.aircraft_previous_body = body^
                        editor.aircraft_previous_body_valid = true
                        touchdown_speed := f32(
                            math.sqrt(f64(body.velocity.x * body.velocity.x + body.velocity.z * body.velocity.z)),
                        )
                        terrain_height := terrain.sample_height(&editor.project, 0, body.position.x, body.position.z)
                        ground := postale_game.drivable_surface_height(terrain_height, editor.project.sea_level)
                        if editor.aircraft.active != .Postale {
                            libellula_game.step(&editor.libellula, {
                                    throttle_up   = control.throttle_up,
                                    throttle_down = control.throttle_down,
                                    pitch         = control.pitch,
                                    roll          = control.roll,
                                    yaw           = control.yaw,
                                }, ground, f32(AIRCRAFT_FIXED_STEP))
                        } else {
                            ground_result := postale_game.step(
                                &editor.postale,
                                control,
                                ground,
                                f32(AIRCRAFT_FIXED_STEP),
                            )
                            wheels_on_land := terrain_height >= editor.project.sea_level
                            if ground_result.touched_down && wheels_on_land {
                                editor.landing_wheel_squeal = max(
                                    editor.landing_wheel_squeal,
                                    clamp((touchdown_speed - 3) / 18, 0, 1),
                                )
                                editor.landing_wheel_speed = touchdown_speed
                            }
                            _ = markov_wreck_aircraft_collision_step(editor)
                        }
                        is_crashed := editor.postale.crashed
                        if editor.aircraft.active != .Postale {
                            is_crashed = editor.libellula.crashed
                        }
                        if !was_crashed && is_crashed {
                            crash_profile =
                                editor.aircraft.active == .Postale ? engine_sound.Crash_Profile.Fixed_Wing : engine_sound.Crash_Profile.Rotorcraft
                            crash_severity = max(
                                crash_severity,
                                clamp(impact_vertical_speed / 18 + touchdown_speed / 75, .2, 1),
                            )
                            crash_slide_speed = clamp(touchdown_speed / 60, 0, 1)
                            dust_surface, _ := road_car_surface(
                                editor,
                                {body.position.x, body.position.y, body.position.z},
                            )
                            crash_surface = crash_surface_from_dust(dust_surface)
                            crash_water_mix = 0
                            if terrain_height < editor.project.sea_level {
                                crash_water_mix = 1
                            }
                        }
                        editor.aircraft_fixed_accumulator -= AIRCRAFT_FIXED_STEP
                    }
                    if editor.aircraft.active == .Postale {
                        left_tip := postale_vertex_world(
                            &editor.postale,
                            {-POSTALE_WING_TRAIL_LOCAL_X, POSTALE_WING_TRAIL_LOCAL_Y, POSTALE_WING_TRAIL_LOCAL_Z},
                            POSTALE_PRESENTATION_SCALE,
                        )
                        right_tip := postale_vertex_world(
                            &editor.postale,
                            {POSTALE_WING_TRAIL_LOCAL_X, POSTALE_WING_TRAIL_LOCAL_Y, POSTALE_WING_TRAIL_LOCAL_Z},
                            POSTALE_PRESENTATION_SCALE,
                        )
                        particle_systems.step_wing_trails(
                            &editor.wing_trails,
                            min(delta_seconds, .05),
                            particle_systems.Vec3{left_tip.x, left_tip.y, left_tip.z},
                            particle_systems.Vec3{right_tip.x, right_tip.y, right_tip.z},
                            particle_systems.Vec3 {
                                editor.postale.body.basis.forward.x,
                                editor.postale.body.basis.forward.y,
                                editor.postale.body.basis.forward.z,
                            },
                            particle_systems.Vec3 {
                                editor.postale.body.basis.up.x,
                                editor.postale.body.basis.up.y,
                                editor.postale.body.basis.up.z,
                            },
                            particle_systems.Vec3 {
                                editor.atmosphere.weather.wind[0],
                                0,
                                editor.atmosphere.weather.wind[1],
                            },
                            editor.postale.telemetry.airspeed,
                        )
                    }
                    vehicles.sync_driver(&editor.pilot)
                    can_exit := postale_game.can_exit(&editor.postale)
                    if editor.aircraft.active != .Postale {
                        can_exit = libellula_game.can_exit(&editor.libellula)
                    }
                    if input_action_pressed(.Interact) && can_exit {
                        if vehicles.try_exit(&editor.pilot, true) {
                            editor.flight_control = {}
                            editor.player.position = editor.pilot.position
                            editor.player.velocity = {}
                            editor.player.grounded = true
                            editor.camera = third_person.default_camera()
                        }
                    }
                    chase_camera.step(
                        &editor.flight_camera,
                        aircraft_camera_target(editor),
                        min(delta_seconds, .05),
                        postale_flyby_shake(editor),
                    )
                    editor.camera_pose = editor.flight_camera.pose
                } else {
                    editor.aircraft_fixed_accumulator = 0
                    editor.aircraft_previous_body_valid = false
                }
                if in_car {
                    if input_action_pressed(.Interact) {
                        if vehicles.try_exit(&editor.pilot, true) {
                            editor.player.position = editor.pilot.position
                            editor.player.velocity = {}
                            editor.player.grounded = true
                            editor.camera = third_person.default_camera()
                        }
                    } else {
                        throttle, steering := f32(0), f32(0)
                        if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) do throttle += 1
                        if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN) do throttle -= 1
                        if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) do steering -= 1
                        if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) do steering += 1
                        if rl.GamepadAvailable() {
                            throttle += max(gamepad_axis(.Right_Trigger), f32(0))
                            throttle -= max(gamepad_axis(.Left_Trigger), f32(0))
                            steering = stronger_axis(steering, gamepad_axis(.Left_X))
                        }
                        if benchmark_mode &&
                           (benchmark_scenario == "road_grip" || benchmark_scenario == "terrain_grip") {
                            throttle = 1
                            steering = math.sin(f32(frame) * .032) * .72
                        }
                        handbrake := input_action_down(.Handbrake)
                        dust_surface, drive_surface := road_car_surface(
                            editor,
                            {editor.car.position.x, editor.car.position.y, editor.car.position.z},
                        )
                        car_impact_severity, car_impact_slide_speed, car_impact_obliqueness := car_physics_step(
                            editor,
                            clamp(throttle, -1, 1),
                            clamp(steering, -1, 1),
                            handbrake,
                            drive_surface,
                            min(delta_seconds, .05),
                        )
                        if car_impact_severity > 0 {
                            crash_severity = max(crash_severity, car_impact_severity)
                            crash_slide_speed = car_impact_slide_speed
                            crash_obliqueness = car_impact_obliqueness
                            crash_surface = crash_surface_from_dust(dust_surface)
                            terrain_height := terrain.sample_height(
                                &editor.project,
                                0,
                                editor.car.position.x,
                                editor.car.position.z,
                            )
                            crash_water_mix = terrain_height < editor.project.sea_level ? 1 : 0
                        }
                        forward_x, forward_z := math.cos(editor.car.yaw_radians), math.sin(editor.car.yaw_radians)
                        right_x, right_z := -forward_z, forward_x
                        contacts := [4]particle_systems.Vehicle_Contact{}
                        wheel_x := [2]f32{-vehicles.CAR_WHEEL_TRACK_HALF, vehicles.CAR_WHEEL_TRACK_HALF}
                        wheel_z := [2]f32{-vehicles.CAR_WHEELBASE_HALF, vehicles.CAR_WHEELBASE_HALF}
                        contact_index := 0
                        for x in wheel_x {
                            for z in wheel_z {
                                contact_x := editor.car.position.x + right_x * x - forward_x * z
                                contact_z := editor.car.position.z + right_z * x - forward_z * z
                                contacts[contact_index] = {
                                    position = {
                                        contact_x,
                                        terrain.sample_height(&editor.project, 0, contact_x, contact_z),
                                        contact_z,
                                    },
                                    grounded = true,
                                    surface  = dust_surface,
                                }
                                contact_index += 1
                            }
                        }
                        particle_systems.step_vehicle_effects(
                            &editor.vehicle_effects,
                            min(delta_seconds, .05),
                            vehicles.car_drive_speed(editor.car_drive),
                            editor.car_drive.steering,
                            handbrake,
                            editor.car_drive.slip_amount,
                            contacts,
                        )
                        vehicles.sync_driver(&editor.pilot)
                        speed_ratio := clamp(
                            vehicles.car_drive_speed(editor.car_drive) / vehicles.CAR_DRIVE_SEDAN_TUNE.max_forward,
                            0,
                            1,
                        )
                        // The chase still recenters behind the car, while the right
                        // stick gives the player a temporary look around it.
                        car_look_x := gamepad_axis(.Right_X)
                        if editor.gameplay_options.invert_look_x do car_look_x = -car_look_x
                        target_yaw := -math.PI * .5 - editor.car.yaw_radians + car_look_x * .85
                        editor.camera.yaw_radians = vehicles.car_drive_angle_step(
                            editor.camera.yaw_radians,
                            target_yaw,
                            clamp((3.8 + speed_ratio * 2.2) * min(delta_seconds, .05), 0, 1),
                        )
                        editor.camera.pitch_radians = clamp(.24 - gamepad_axis(.Right_Y) * .38, -.2, .75)
                        editor.camera.distance = 5.2 + speed_ratio * 1.8
                        editor.camera.height = 1.15 + speed_ratio * .32
                        desired_camera := third_person.camera_pose(editor.car.position, editor.camera)
                        editor.camera_pose = third_person.follow_camera(
                            editor.camera_pose,
                            desired_camera,
                            8,
                            min(delta_seconds, .05),
                        )
                    }
                }
                // `driving` is the mode captured at the start of this frame. After
                // an exit, defer on-foot input until the next frame so the same F
                // press cannot immediately enter the nearby vehicle again.
                if editor.pilot.mode == .On_Foot && !driving {
                    if !dialogue_was_open && !editor.attendant_dialogue_open {
                        stick_look_x := gamepad_axis(.Right_X) * 180 * delta_seconds
                        stick_look_y := gamepad_axis(.Right_Y) * 180 * delta_seconds
                        if editor.gameplay_options.invert_look_x do stick_look_x = -stick_look_x
                        if editor.gameplay_options.invert_look_y do stick_look_y = -stick_look_y
                        third_person.look(
                            &editor.camera,
                            look_x + stick_look_x,
                            -look_y - stick_look_y,
                            editor.gameplay_options.look_sensitivity,
                        )
                        controller_zoom :=
                            (gamepad_axis(.Left_Trigger) - gamepad_axis(.Right_Trigger)) * 4 * delta_seconds
                        editor.camera.distance = clamp(
                            editor.camera.distance - rl.GetMouseWheelMove() * .5 + controller_zoom,
                            3,
                            12,
                        )
                        move_x, move_y := f32(0), f32(0)
                        if rl.IsKeyDown(.D) do move_x += 1
                        if rl.IsKeyDown(.A) do move_x -= 1
                        if rl.IsKeyDown(.W) do move_y += 1
                        if rl.IsKeyDown(.S) do move_y -= 1
                        move_x = stronger_axis(move_x, gamepad_axis(.Left_X))
                        move_y = stronger_axis(move_y, -gamepad_axis(.Left_Y))
                        ground_height := terrain.sample_height(
                            &editor.project,
                            0,
                            editor.player.position.x,
                            editor.player.position.z,
                        )
                        input := third_person.Input {
                            move_x             = move_x,
                            move_y             = move_y,
                            run_toggle_pressed = input_action_pressed(.Run),
                            jump_pressed       = input_action_pressed(.Jump),
                            jump_held          = input_action_down(.Jump),
                            grounded           = editor.player.position.y <= ground_height + .01,
                            camera_yaw_radians = editor.camera.yaw_radians,
                            ground_normal      = player_ground_normal(editor, editor.player.position),
                        }
                        frame_seconds := min(delta_seconds, .05)
                        stride_phase_before := editor.player_stride_phase
                        player_was_grounded := editor.player.grounded
                        player_vertical_speed_before := editor.player.velocity.y
                        third_person.step(&editor.player, input, editor.tweak.player, frame_seconds)
                        player_animation_update(editor, frame_seconds)
                        ground_height = terrain.sample_height(
                            &editor.project,
                            0,
                            editor.player.position.x,
                            editor.player.position.z,
                        )
                        if editor.player.position.y <= ground_height {
                            editor.player.position.y = ground_height
                            editor.player.grounded = true
                        }
                        player_horizontal_speed := f32(
                            math.sqrt(
                                f64(
                                    editor.player.velocity.x * editor.player.velocity.x +
                                    editor.player.velocity.z * editor.player.velocity.z,
                                ),
                            ),
                        )
                        if editor.player.grounded &&
                           player_horizontal_speed > .12 &&
                           engine_sound.footstep_phase_crossed(stride_phase_before, editor.player_stride_phase) {
                            footstep_triggered = true
                            footstep_intensity = clamp(
                                .2 +
                                player_horizontal_speed /
                                    max(editor.tweak.player_animation.bound_full_speed, f32(.1)) *
                                    .8,
                                .2,
                                1,
                            )
                        }
                        if !player_was_grounded && editor.player.grounded && player_vertical_speed_before < -.5 {
                            footstep_triggered = true
                            footstep_landing = true
                            footstep_intensity = clamp((-player_vertical_speed_before - .5) / 7, .35, 1)
                            footstep_slide = clamp(
                                player_horizontal_speed / max(editor.tweak.player_animation.bound_full_speed, f32(.1)),
                                0,
                                1,
                            )
                        }
                        if footstep_triggered {
                            dust_surface, _ := road_car_surface(
                                editor,
                                {editor.player.position.x, editor.player.position.y, editor.player.position.z},
                            )
                            footstep_surface = footstep_surface_from_dust(dust_surface)
                        }
                        player_tail_update(editor, frame_seconds)
                        editor.pilot.position = editor.player.position
                        editor.pilot.facing_yaw_radians = editor.player.facing_yaw_radians
                        if input_action_pressed(.Interact) {
                            dockmaster_interacted := open_markov_marina_dockmaster_dialogue(editor)
                            resident, _, story_near := nearest_story_resident(editor, require_action = true)
                            story_interacted :=
                                !dockmaster_interacted && story_near && open_story_dialogue(editor, resident)
                            trailer_interacted := false
                            entered := false
                            if !dockmaster_interacted && !story_interacted {
                                trailer_interacted = car_trailer_interact(editor)
                            }
                            if !dockmaster_interacted && !story_interacted && !trailer_interacted {
                                _, entered = vehicles.try_enter_nearest(
                                    &editor.pilot,
                                    []^vehicles.Vehicle{&editor.car, active_aircraft_vehicle(editor)},
                                )
                            }
                            if entered {
                                editor.player.running = false
                                editor.flight_control = {}
                                if driving_aircraft(editor) {
                                    chase_camera.reset(&editor.flight_camera, aircraft_camera_target(editor))
                                }
                            } else if !dockmaster_interacted &&
                               !story_interacted &&
                               !trailer_interacted &&
                               libellula_attendant_near(editor) {
                                attendant, _, attendant_near := nearest_service_attendant(editor)
                                if attendant_near do open_attendant_dialogue(editor, attendant)
                            }
                        }
                        if editor.camera_target_lock {
                            editor.camera_pose = third_person.camera_near(editor.libellula.vehicle.position, {8, 5, 8})
                        } else {
                            desired_camera := third_person.camera_pose(editor.player.position, editor.camera)
                            editor.camera_pose = third_person.follow_camera(
                                editor.camera_pose,
                                desired_camera,
                                12,
                                min(delta_seconds, .05),
                            )
                        }
                    }
                }
            }
        }
        if editor.in_map && !editor.vehicle_showcase_scene && !editor.vehicle_paint_scene {
            trailer_ground := terrain.sample_height(
                &editor.project,
                0,
                editor.car_trailer_position.x,
                editor.car_trailer_position.z,
            )
            vehicles.car_trailer_step(
                &editor.car_trailer,
                &editor.car_trailer_position,
                &editor.car_trailer_yaw,
                editor.car.position,
                editor.car.yaw_radians,
                editor.car_drive.yaw_rate,
                editor.car_drive.velocity,
                editor.car_trailer_attached,
                trailer_ground,
                min(frame_delta, .05),
            )
            if editor.car_trailer_attached {
                editor.car_drive.velocity.x += editor.car_trailer.reaction_force.x * min(frame_delta, .05)
                editor.car_drive.velocity.z += editor.car_trailer.reaction_force.z * min(frame_delta, .05)
                if editor.car_physics_vehicle != nil {
                    physics.set_linear_velocity(
                        editor.car_physics_world,
                        physics.vehicle_body(editor.car_physics_vehicle),
                        {editor.car_drive.velocity.x, editor.car_drive.velocity.y, editor.car_drive.velocity.z},
                    )
                }
            }
        }
        if editor.cameras.active != .Player {
            editor.camera_pose = third_person.camera_active_pose(&editor.cameras)
        }
        wildflower_effects_step(editor, simulation_delta)
        if capture_wildflower_lab_mode {
            wind := editor.atmosphere.weather.wind
            particle_systems.step_petals(
                &editor.petal_effects,
                min(frame_delta, .05),
                {editor.player.position.x + 1.1, editor.player.position.y, editor.player.position.z},
                {8, 0, 1.5},
                {wind[0], 0, wind[1]},
                1,
            )
        }
        if !editor.vehicle_showcase_scene && !driving_aircraft(editor) {
            camera_ground := terrain.sample_height(
                &editor.project,
                0,
                editor.camera_pose.position.x,
                editor.camera_pose.position.z,
            )
            editor.camera_pose = third_person.camera_above_height(editor.camera_pose, camera_ground, .35)
        }
        if !editor.in_map && editor.tool != .Structure && cursor_hit && !ui_hit {
            if rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) {
                terrain_history_push_undo(editor)
            }
            stroke_strength := editor.strength * min(frame_delta, f32(.05)) * 4
            if rl.IsMouseButtonDown(.LEFT) do terrain.apply_stroke_with_hardness(&editor.project, editor.tool, world_x, world_z, editor.radius, stroke_strength, 1, editor.hardness)
            if rl.IsMouseButtonDown(.RIGHT) do terrain.apply_stroke_with_hardness(&editor.project, editor.tool, world_x, world_z, editor.radius, stroke_strength, -1, editor.hardness)
        }
        saved_aircraft_body: flight.Body_State
        cinematic_update(editor, simulation_delta)
        render_aircraft_body := active_aircraft_body(editor)
        interpolate_aircraft := driving_aircraft(editor) && editor.aircraft_previous_body_valid
        if interpolate_aircraft {
            saved_aircraft_body = render_aircraft_body^
            render_aircraft_body^ = aircraft_render_body(editor)
        }
        rl.BeginDrawing()
        draw_terrain(editor, width, height, f32(rl.GetTime()))
        pause_menu_draw(editor, width, height, postcard)
        console_draw(editor, width, height)
        cinematic_draw_wipe(editor, width, height)
        live_capture_poll()
        rl.EndDrawing()
        gpu_frame_ms, gpu_frame_available := rl.GetGpuFrameTimeMs()
        dio.flame_graph_set_frame_metrics(&editor.flame_graph, 0, 0, f32(gpu_frame_ms), gpu_frame_available)
        dio.flame_graph_end_frame(&editor.flame_graph)
        if interpolate_aircraft {
            render_aircraft_body^ = saved_aircraft_body
        }
        car_damage_impact := f32(0)
        if driving_car(editor) do car_damage_impact = crash_severity
        editor.car_audio_damage = engine_sound.vehicle_audio_damage_step(
            editor.car_audio_damage,
            car_damage_impact,
            simulation_delta,
        )
        engine_controls := engine_sound.Controls{}
        if editor.pilot.mode == .Driving {
            engine_controls.active = true
            if driving_aircraft(editor) {
                if editor.aircraft.active == .Postale {
                    engine_controls.rate = .12 + editor.postale.throttle * .88
                    engine_controls.power =
                        editor.postale.throttle * clamp(editor.postale.flight_runtime.engine_output, 0, 1)
                    engine_controls.propeller_mix = 1
                    engine_controls.propeller_airspeed = clamp(editor.postale.telemetry.airspeed / 65, 0, 1)
                } else {
                    rotor_rate :=
                        (editor.libellula.telemetry.rotor_rpm_normalized.x +
                            editor.libellula.telemetry.rotor_rpm_normalized.y +
                            editor.libellula.telemetry.rotor_rpm_normalized.z) /
                        3
                    available_power :=
                        (editor.libellula.flight_runtime.left_engine_output +
                            editor.libellula.flight_runtime.right_engine_output +
                            editor.libellula.flight_runtime.rear_engine_output) /
                        3
                    engine_controls.rate = .16 + clamp(rotor_rate, 0, 1) * .84
                    engine_controls.rotor_rate_a = clamp(editor.libellula.telemetry.rotor_rpm_normalized.x, 0, 1)
                    engine_controls.rotor_rate_b = clamp(editor.libellula.telemetry.rotor_rpm_normalized.y, 0, 1)
                    engine_controls.rotor_rate_c = clamp(editor.libellula.telemetry.rotor_rpm_normalized.z, 0, 1)
                    engine_controls.power = editor.libellula.throttle * clamp(available_power, 0, 1)
                    engine_controls.rotor_mix = 1
                }
                if editor.aircraft.active == .Postale {
                    engine_controls.damage = editor.postale.structural_damage
                } else {
                    engine_controls.damage = editor.libellula.crashed ? 1 : 0
                }
            } else if driving_car(editor) {
                car_reversing := editor.car_drive.wheel_speed < 0
                normalized_wheel_speed :=
                    math.abs(editor.car_drive.wheel_speed) / vehicles.CAR_DRIVE_SEDAN_TUNE.max_forward
                if car_reversing {
                    normalized_wheel_speed =
                        math.abs(editor.car_drive.wheel_speed) / vehicles.CAR_DRIVE_SEDAN_TUNE.max_reverse
                    engine_controls.reverse_mix = 1
                }
                engine_controls.rate = engine_sound.car_rate_step(
                    &editor.car_audio_gearbox,
                    normalized_wheel_speed,
                    car_reversing,
                )
                engine_controls.shift = editor.car_audio_gearbox.shifted
                engine_controls.transmission_mix = 1
                engine_controls.gear = editor.car_audio_gearbox.gear
                engine_controls.damage = editor.car_audio_damage
                wheel_load := math.abs(
                    editor.car_drive.wheel_speed -
                    vehicles.car_drive_longitudinal_speed(editor.car_drive, editor.car.yaw_radians),
                )
                engine_controls.power = clamp(
                    math.abs(editor.car_drive.acceleration_feedback) * .65 +
                    wheel_load / vehicles.CAR_DRIVE_SEDAN_TUNE.max_forward,
                    0,
                    1,
                )
            }
        }
        wheel_slip_controls := engine_sound.Slip_Controls{}
        tire_wetness := clamp(editor.atmosphere.weather.precipitation, 0, 1)
        tire_surface := particle_systems.Dust_Surface.Grass
        postale_wheels_on_land := false
        if driving_aircraft(editor) && editor.aircraft.active == .Postale && editor.postale.grounded {
            terrain_height := terrain.sample_height(
                &editor.project,
                0,
                editor.postale.body.position.x,
                editor.postale.body.position.z,
            )
            postale_wheels_on_land = terrain_height >= editor.project.sea_level
            if postale_wheels_on_land {
                tire_surface, _ = road_car_surface(
                    editor,
                    {editor.postale.body.position.x, editor.postale.body.position.y, editor.postale.body.position.z},
                )
            }
        }
        if driving_car(editor) && !pause_menu_is_open(editor) {
            tire_surface, _ = road_car_surface(
                editor,
                {editor.car.position.x, editor.car.position.y, editor.car.position.z},
            )
            wheel_slip_controls.active = true
            wheel_slip_controls.wetness = tire_wetness
            wheel_slip_controls.surface = footstep_surface_from_dust(tire_surface)
            wheel_slip_controls.amount = editor.car_drive.slip_amount
            wheel_slip_controls.speed = clamp(
                vehicles.car_drive_speed(editor.car_drive) / vehicles.CAR_DRIVE_SEDAN_TUNE.max_forward,
                0,
                1,
            )
        } else if driving_aircraft(editor) &&
           editor.aircraft.active == .Postale &&
           postale_wheels_on_land &&
           editor.landing_wheel_squeal > 0 &&
           !pause_menu_is_open(editor) {
            wheel_slip_controls.active = true
            wheel_slip_controls.wetness = tire_wetness
            wheel_slip_controls.surface = footstep_surface_from_dust(tire_surface)
            wheel_slip_controls.amount = editor.landing_wheel_squeal
            wheel_slip_controls.speed = clamp(editor.landing_wheel_speed / 32, 0, 1)
        }
        tire_roll_controls := engine_sound.Roll_Controls{}
        if driving_car(editor) && !pause_menu_is_open(editor) {
            tire_roll_controls.active = true
            tire_roll_controls.wetness = tire_wetness
            tire_roll_controls.damage = editor.car_audio_damage
            tire_roll_controls.speed = clamp(
                vehicles.car_drive_speed(editor.car_drive) / vehicles.CAR_DRIVE_SEDAN_TUNE.max_forward,
                0,
                1,
            )
            tire_roll_controls.surface = footstep_surface_from_dust(tire_surface)
            tire_roll_controls.roughness = tire_roughness_from_dust(tire_surface)
        } else if driving_aircraft(editor) && !pause_menu_is_open(editor) {
            if postale_wheels_on_land {
                tire_roll_controls.active = true
                tire_roll_controls.wetness = tire_wetness
                tire_roll_controls.damage = editor.postale.structural_damage
                tire_roll_controls.speed = clamp(editor.postale.telemetry.airspeed / 45, 0, 1)
                tire_roll_controls.surface = footstep_surface_from_dust(tire_surface)
                tire_roll_controls.roughness = tire_roughness_from_dust(tire_surface)
            }
        }
        if engine_audio_ready {
            engine_sound.update(
                &editor.engine_audio,
                engine_controls,
                wheel_slip_controls,
                tire_roll_controls,
                crash_severity,
                crash_water_mix,
                crash_slide_speed,
                crash_surface,
                footstep_triggered,
                footstep_intensity,
                footstep_surface,
                footstep_landing,
                tire_wetness,
                crash_profile,
                crash_wetness,
                crash_obliqueness,
                footstep_slide,
                pause_menu_is_open(editor),
            )
        }
        editor.landing_wheel_squeal = max(0, editor.landing_wheel_squeal - simulation_delta * 1.65)
        if benchmark_mode && frame >= benchmark_warmup {
            benchmark_samples[benchmark_sample_count] = rl.GetTime() - benchmark_frame_start
            benchmark_sample_count += 1
            if benchmark_sample_count >= benchmark_frames {
                benchmark_report(
                    benchmark_scenario,
                    benchmark_samples[:benchmark_sample_count],
                    benchmark_window_width,
                    benchmark_window_height,
                    benchmark_world_width,
                    benchmark_world_height,
                )
                break
            }
        }
        // Player captures wait long enough for the Verlet tail and pose blends
        // to settle; frame two only showed the first few links as a short nub.
        capture_frame :=
            capture_flight_mode || capture_player_mode || capture_kind == .Shadow_Lab || capture_kind == .Boat_Lab || capture_kind == .Markov_Marina ? 20 : 2
        if capture_mode && frame == capture_frame do rl.TakeScreenshot(fmt.ctprintf("%s", capture_output))
        // Vulkan screenshot readback completes asynchronously; retain several
        // presented frames after the request so capture mode always writes its PNG.
        if capture_mode && frame >= 32 do break
        if HOT_RELOAD && hot_reload_requested(hot_library_path, hot_library_mtime) {
            if !hot_state_save(editor, hot_state_path) {
                fmt.eprintln("adriatic hot reload could not save state")
                return .Quit
            }
            reload_requested = true
            break
        }
        frame += 1
    }
    return reload_requested ? .Reload : .Quit
}

@(export)
abi_version :: proc() -> u64 {
    return hot_abi.type_hash(hot_abi.Contract)
}

@(export)
run :: proc(persistent_canvas_state: rawptr) -> hot_abi.Run_Result {
    return adriatic_run(persistent_canvas_state)
}

@(export)
canvas_state :: proc() -> rawptr {
    return rl.PersistentState()
}

@(export)
canvas_state_abi_version :: proc() -> u64 {
    return rl.State_Abi_Version()
}

@(export)
close_canvas :: proc() {
    rl.DestroyPersistentState()
}

when !HOT_RELOAD {
    main :: proc() {
        handled, success := adriatic_cli(os.args)
        if handled {
            if !success do os.exit(1)
            return
        }
        _ = adriatic_run(nil)
    }
}
