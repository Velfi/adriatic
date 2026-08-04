package main

import architecture "../packages/architecture"
import atmosphere "../packages/atmosphere"
import boats "../packages/boats"
import chase_camera "../packages/chase_camera"
import cinematic "../packages/cinematic"
import circulation "../packages/circulation"
import dialogue "../packages/dialogue"
import dialogue_session "../packages/dialogue_session"
import flight "../packages/flight"
import flocks "../packages/flocks"
import harbor "../packages/harbor"
import libellula_game "../packages/libellula"
import marina "../packages/marina"
import mouse_paws "../packages/mouse_paws"
import mouse_tail "../packages/mouse_tail"
import particle_systems "../packages/particles"
import player_mail "../packages/player_mail"
import postale_game "../packages/postale"
import quest "../packages/quest"
import roads "../packages/roads"
import rondine_game "../packages/rondine"
import story "../packages/story"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:time"
import canvas2d "zelda_engine:canvas2d"

HOT_RELOAD :: #config(HOT_RELOAD, false)
SHOW_STARTUP_MENU :: #config(SHOW_STARTUP_MENU, false)
MAP_DEVELOPMENT_FALLBACK :: #config(MAP_DEVELOPMENT_FALLBACK, true)
LIBELLULA_MK1_ENABLED :: #config(LIBELLULA_MK1_ENABLED, false)
HOT_LIBRARY_ENV :: "ADRIATIC_HOT_LIBRARY"

startup_failed: bool

ADRIATIC_WORLD_WIDTH :: 854
ADRIATIC_WORLD_HEIGHT :: 480
STRUCTURE_HISTORY_CAPACITY :: 24
TERRAIN_HISTORY_CAPACITY :: 12
FORMATION_EDIT_BENCHMARK_STRUCTURES :: terrain.LEGACY_STRUCTURE_CAPACITY + 144
TERRAIN_PROJECT_PATH :: "adriatic.terrain"
MARINA_BRUSH_MINIMUM_SUITABILITY :: f32(.70)
VEHICLE_SHOWCASE_FOCAL_LENGTH :: f32(2.0)
AIRCRAFT_FIXED_STEP :: f64(1.0 / 120.0)
AIRCRAFT_MAX_CATCH_UP :: f64(.1)
CRASH_MESSAGE_SECONDS :: f32(1.15)
CRASH_FADE_OUT_SECONDS :: f32(.65)
CRASH_FADE_IN_SECONDS :: f32(.85)
PLAYER_FALL_RECOVERY_DEPTH :: f32(30)

Startup_Timings :: struct {
    started_at:  time.Tick,
    checkpoint:  time.Tick,
    config_ms:   f64,
    window_ms:   f64,
    audio_ms:    f64,
    meshes_ms:   f64,
    terrain_ms:  f64,
    map_load_ms: f64,
    physics_ms:  f64,
    renderer_ms: f64,
    ready_ms:    f64,
}

startup_elapsed_ms :: #force_inline proc(start, end: time.Tick) -> f64 {
    return time.duration_seconds(time.tick_diff(start, end)) * 1000
}

startup_checkpoint :: #force_inline proc(timings: ^Startup_Timings) -> f64 {
    now := time.tick_now()
    elapsed_ms := startup_elapsed_ms(timings.checkpoint, now)
    timings.checkpoint = now
    return elapsed_ms
}

Crash_Recovery_Cause :: enum u8 {
    Crash,
    Tumble,
}

Crash_Recovery_Phase :: enum u8 {
    Inactive,
    Message,
    Fade_Out,
    Fade_In,
}

Default_Map_Regeneration_Stage :: enum u8 {
    Terrain,
    Marinas,
    Towns,
    Finalize,
}

Structure_History_State :: struct {
    sequence:                     u64,
    structures:                   [dynamic]terrain.Structure,
    count:                        int,
    next_id:                      u64,
    road_graph:                   roads.Graph,
    city_density:                 [terrain.CITY_DENSITY_SAMPLES]u8,
    climbing_leaf_density:        [terrain.CITY_DENSITY_SAMPLES]u8,
    marina_plan:                  marina.Plan,
    harbor_plan:                  harbor.Harbor_Plan,
    harbor_intervention:          harbor.Harbor_Intervention,
    marina_authored:              bool,
    farms:                        [FARM_INSTANCE_CAPACITY]Farm_Instance,
    farm_count:                   int,
    wrecks:                       [WRECK_INSTANCE_CAPACITY]Wreck_Instance,
    wreck_count:                  int,
    settlement_brush_pieces:      [SETTLEMENT_BRUSH_PIECE_CAPACITY]Settlement_Brush_Piece,
    settlement_brush_piece_count: int,
    settlement_next_component_id: u32,
    island_transforms:            [terrain.ISLAND_COUNT]terrain.Island_Transform,
    settlement_plan:              Settlement_Plan,
    greek_placements:             [GREEK_PLACEMENT_CAPACITY]Greek_Placement,
    greek_placement_count:        int,
    mouse_placements:             [MOUSE_PLACEMENT_CAPACITY]Mouse_Placement,
    mouse_placement_count:        int,
    default_marinas:              [terrain.ISLAND_COUNT]marina.Plan,
    default_harbors:              [terrain.ISLAND_COUNT]harbor.Harbor_Plan,
    default_harbor_interventions: [terrain.ISLAND_COUNT]harbor.Harbor_Intervention,
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
FIXTURE_NOTE_CAPACITY :: 64
FIXTURE_NOTE_TEXT_CAPACITY :: 256
CURVE_MERGE_MINIMUM_COSINE :: f32(0.9961947) // 5 degrees

Curve_Point :: struct {
    x, z: f32,
}

Road_Construction_Mode :: enum u8 {
    Straight,
    Terrain_Route,
    Authored_Curve,
}

Road_Construction_Phase :: enum u8 {
    Idle,
    Choose_End,
    Drag_Start_Tangent,
    Drag_End_Tangent,
}

Road_Snap_Kind :: enum u8 {
    Raw,
    Grid,
    Angle,
    Tangent,
    Perpendicular,
    Edge,
    Node,
}

Road_Snap :: struct {
    kind:       Road_Snap_Kind,
    position:   roads.Vec3,
    node:       int,
    edge:       int,
    edge_t:     f32,
    guide_from: roads.Vec3,
    valid:      bool,
}

Road_Preview_Status :: enum u8 {
    Idle,
    Valid,
    Stale,
    Degenerate,
    No_Route,
    Capacity,
    Invalid_Junction,
}

Fixture_Note_Target :: enum u8 {
    Scene,
    Structure,
}

Fixture_Note :: struct {
    text:              [FIXTURE_NOTE_TEXT_CAPACITY]u8,
    target:            Fixture_Note_Target,
    target_id:         u64,
    fallback_position: third_person.Vec3,
}

SDF_OBSTACLE_CAPACITY :: 64

SDF_Torus_Obstacle :: struct {
    position:     flight.Vec3,
    rotation:     quaternion128,
    scale:        flight.Vec3,
    major_radius: f32,
    tube_radius:  f32,
    color:        [4]u8,
}

SDF_Obstacle_Gizmo_Mode :: enum {
    None,
    Translate,
    Rotate,
    Scale,
}

SDF_Obstacle_Axis :: enum {
    None,
    X,
    Y,
    Z,
}

SDF_Obstacle_Interaction :: struct {
    hovered:                  int,
    list_scroll:              int,
    gizmo_mode:               SDF_Obstacle_Gizmo_Mode,
    constrained_axis:         SDF_Obstacle_Axis,
    drag_anchor_world:        flight.Vec3,
    drag_anchor_screen:       [2]f32,
    transform_snapshot:       SDF_Torus_Obstacle,
    transform_snapshot_valid: bool,
    transform_snapshot_slot:  int,
    inspector_euler:          flight.Vec3,
    inspector_euler_valid:    bool,
}

FIXTURE_MAP_SIDECAR_BASENAME_CAPACITY :: 128

Fixture_Map_Source_Kind :: enum u8 {
    Inline,
    Sidecar,
}

Fixture_Map_Sidecar :: struct {
    basename:          [FIXTURE_MAP_SIDECAR_BASENAME_CAPACITY]byte,
    basename_count:    int,
    container_version: u16,
    format_version:    u32,
    generator_version: u64,
    encoded_sha256:    [32]byte,
}

Fixture_Map_Source :: struct {
    kind:         Fixture_Map_Source_Kind,
    inline_bytes: [dynamic]u8,
    sidecar:      Fixture_Map_Sidecar,
}

Fixture :: struct {
    project:                                        terrain.Project `fixture:"-" fixture_map:"-"`,
    terrain_revision:                               u64 `fixture:"-"`,
    circulation_plan:                               circulation.Plan `fixture:"-"`,
    circulation_revision:                           u64 `fixture:"-"`,
    circulation_plan_valid:                         bool `fixture:"-"`,
    circulation_structures:                         [dynamic]terrain.Structure `fixture:"-"`,
    circulation_structure_count:                    int `fixture:"-"`,
    authoring_tool:                                 Authoring_Tool,
    selection_tool_active:                          bool `fixture:"-"`,
    marine_ecology_paint:                           bool `fixture:"-"`,
    marine_ecology_paint_kind:                      terrain.Marine_Habitat_Kind `fixture:"-"`,
    land_paint_kind:                                Land_Paint_Kind `fixture:"-"`,
    editor_ui:                                      Editor_UI_State,
    sdf_obstacles:                                  [SDF_OBSTACLE_CAPACITY]SDF_Torus_Obstacle,
    sdf_obstacle_count:                             int,
    sdf_obstacle_selected:                          int,
    sdf_obstacle_interaction:                       SDF_Obstacle_Interaction `fixture:"-"`,
    tool:                                           terrain.Tool,
    radius:                                         f32,
    strength:                                       f32,
    hardness:                                       f32,
    structure_selected:                             int,
    island_selected:                                terrain.Island_ID `fixture:"-"`,
    island_moving:                                  bool `fixture:"-"`,
    island_drag_start_x, island_drag_start_z:       f32 `fixture:"-"`,
    island_drag_center_x, island_drag_center_z:     f32 `fixture:"-"`,
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
    rock_placement_mode:                            bool `fixture:"-"`,
    rock_material_variant:                          int `fixture:"-"`,
    foliage_hedgerow_mode:                          bool,
    architecture_node_mode:                         bool,
    architecture_paint_mode:                        bool,
    architecture_painting:                          bool `fixture:"-"`,
    architecture_density_preview:                   [terrain.CITY_DENSITY_SAMPLES]u8 `fixture:"-"`,
    architecture_preview_plan:                      architecture.City_Plan `fixture:"-"`,
    architecture_city_plan:                         architecture.City_Plan,
    architecture_dirty_bounds:                      architecture.City_Bounds `fixture:"-"`,
    architecture_last_x, architecture_last_z:       f32 `fixture:"-"`,
    architecture_drag_x, architecture_drag_z:       f32 `fixture:"-"`,
    architecture_brush_rotation:                    f32 `fixture:"-"`,
    architecture_brush_shape:                       Settlement_Brush_Shape,
    architecture_brush_preset:                      Settlement_Brush_Preset,
    architecture_brush_strength:                    f32,
    architecture_brush_hardness:                    f32,
    building_generator_width:                       f32 `fixture:"-"`,
    building_generator_depth:                       f32 `fixture:"-"`,
    building_generator_height:                      f32 `fixture:"-"`,
    building_generator_density:                     f32 `fixture:"-"`,
    building_generator_variation:                   f32 `fixture:"-"`,
    building_generator_kind:                        Building_Generator_Kind `fixture:"-"`,
    building_generator_preview_valid:               bool `fixture:"-"`,
    airport_stamp_mode:                             bool `fixture:"-"`,
    airport_preview_valid:                          bool `fixture:"-"`,
    airport_preview_x, airport_preview_z:           f32 `fixture:"-"`,
    airport_stamp_yaw:                              f32 `fixture:"-"`,
    marina_paint_mode:                              bool,
    marina_authored:                                bool `fixture:"-" fixture_map:"-"`,
    marina_authored_plan:                           marina.Plan `fixture:"-" fixture_map:"-"`,
    marina_preview_plan:                            marina.Plan `fixture:"-"`,
    harbor_authored_plan:                           harbor.Harbor_Plan `fixture:"-" fixture_map:"-"`,
    harbor_preview_plan:                            harbor.Harbor_Plan `fixture:"-"`,
    harbor_authored_intervention:                   harbor.Harbor_Intervention `fixture:"-" fixture_map:"-"`,
    harbor_preview_intervention:                    harbor.Harbor_Intervention `fixture:"-"`,
    marina_preview_valid:                           bool `fixture:"-"`,
    marina_preview_x, marina_preview_z:             f32 `fixture:"-"`,
    marina_preview_variation:                       u32 `fixture:"-"`,
    marina_brush_radius:                            f32,
    marina_brush_status:                            Marina_Brush_Status `fixture:"-"`,
    marina_brush_suitability:                       f32 `fixture:"-"`,
    marina_brush_attempts:                          int `fixture:"-"`,
    farm_paint_mode:                                bool,
    farm_brush_radius:                              f32,
    farms:                                          [FARM_INSTANCE_CAPACITY]Farm_Instance `fixture:"-" fixture_map:"-"`,
    farm_count:                                     int `fixture:"-" fixture_map:"-"`,
    farm_preview:                                   Farm_Instance `fixture:"-"`,
    farm_preview_valid:                             bool `fixture:"-"`,
    farm_preview_score:                             f32 `fixture:"-"`,
    farm_preview_site_score:                        f32 `fixture:"-"`,
    farm_preview_generation_score:                  f32 `fixture:"-"`,
    farm_preview_x:                                 f32 `fixture:"-"`,
    farm_preview_z:                                 f32 `fixture:"-"`,
    farm_preview_revision:                          u64 `fixture:"-"`,
    farm_preview_seed_offset:                       u32 `fixture:"-"`,
    farm_brush_yaw:                                 f32,
    wreck_paint_mode:                               bool,
    wreck_brush_size:                               f32,
    wreck_brush_yaw:                                f32,
    wrecks:                                         [WRECK_INSTANCE_CAPACITY]Wreck_Instance `fixture:"-" fixture_map:"-"`,
    wreck_count:                                    int `fixture:"-" fixture_map:"-"`,
    wreck_preview:                                  Wreck_Instance `fixture:"-"`,
    wreck_preview_valid:                            bool `fixture:"-"`,
    wreck_preview_x, wreck_preview_z:               f32 `fixture:"-"`,
    wreck_preview_revision:                         u64 `fixture:"-"`,
    wreck_preview_seed_offset:                      u32 `fixture:"-"`,
    default_marinas:                                [len(
        terrain.DEFAULT_ISLAND_SIGNS,
    )]marina.Plan `hs:"-" fixture:"-" fixture_map:"-"`,
    default_harbors:                                [len(
        terrain.DEFAULT_ISLAND_SIGNS,
    )]harbor.Harbor_Plan `hs:"-" fixture:"-" fixture_map:"-"`,
    default_harbor_interventions:                   [len(
        terrain.DEFAULT_ISLAND_SIGNS,
    )]harbor.Harbor_Intervention `hs:"-" fixture:"-" fixture_map:"-"`,
    default_marina_islands:                         [len(
        terrain.DEFAULT_ISLAND_SIGNS,
    )]story.Island `hs:"-" fixture:"-" fixture_map:"-"`,
    default_marina_count:                           int `hs:"-" fixture:"-" fixture_map:"-"`,
    climbing_leaf_paint_mode:                       bool,
    climbing_leaf_painting:                         bool `fixture:"-"`,
    climbing_leaf_last_x, climbing_leaf_last_z:     f32 `fixture:"-"`,
    climbing_leaf_brush_radius:                     f32,
    climbing_leaf_brush_strength:                   f32,
    climbing_leaf_brush_hardness:                   f32,
    greek_asset_selected:                           int,
    greek_asset_rotation:                           f32,
    greek_asset_scale:                              f32,
    greek_placements:                               [GREEK_PLACEMENT_CAPACITY]Greek_Placement `fixture:"-" fixture_map:"-"`,
    greek_placement_count:                          int `fixture:"-" fixture_map:"-"`,
    greek_placement_selected:                       int,
    greek_placement_mode:                           bool,
    mouse_placements:                               [MOUSE_PLACEMENT_CAPACITY]Mouse_Placement,
    mouse_placement_count:                          int,
    mouse_placement_selected:                       int `fixture:"-"`,
    mouse_placement_rotation:                       f32,
    mouse_placement_mode:                           bool `fixture:"-"`,
    curve_points:                                   [CURVE_POINT_CAPACITY]Curve_Point,
    curve_point_count:                              int,
    curve_drawing:                                  bool `fixture:"-"`,
    curve_mode:                                     bool,
    curve_cliff_mode:                               bool,
    curve_width:                                    f32,
    curve_height:                                   f32,
    cliff_elevation_mode:                           terrain.Cliff_Elevation_Mode,
    road_mode:                                      bool,
    road_selected_node:                             int,
    road_drag_node:                                 int `fixture:"-"`,
    road_drag_node_previous_selection:              int `fixture:"-"`,
    road_drag_node_moved:                           bool `fixture:"-"`,
    road_drag_edge:                                 int `fixture:"-"`,
    road_drag_handle:                               int `fixture:"-"`,
    road_hover_edge:                                int `fixture:"-"`,
    road_hover_handle:                              int `fixture:"-"`,
    road_drag_handle_moved:                         bool `fixture:"-"`,
    road_width:                                     f32,
    road_shoulder_width:                            f32,
    road_pavement:                                  roads.Pavement,
    in_map:                                         bool,
    crash_recovery_phase:                           Crash_Recovery_Phase `fixture:"-"`,
    crash_recovery_seconds:                         f32 `fixture:"-"`,
    crash_recovery_position:                        third_person.Vec3 `fixture:"-"`,
    crash_recovery_cause:                           Crash_Recovery_Cause `fixture:"-"`,
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
    player_body_softness:                           Mouse_Body_Softness_State `fixture:"-"`,
    player_stop_spray_cooldown:                     f32 `fixture:"-"`,
    player_stop_spray_speed:                        f32 `fixture:"-"`,
    player_paws:                                    mouse_paws.Rig `fixture:"-"`,
    player_tail:                                    mouse_tail.State `fixture:"-"`,
    camera:                                         third_person.Camera,
    camera_pose:                                    third_person.Camera_Pose,
    cameras:                                        third_person.Camera_System,
    cinematic_playback:                             cinematic.Playback `fixture:"-"`,
    cinematic_focal_length:                         f32 `fixture:"-"`,
    story_cinematic_shots:                          [3]cinematic.Shot `fixture:"-"`,
    story_cinematic_script:                         cinematic.Script `fixture:"-"`,
    story_cinematic_restore_pose:                   third_person.Camera_Pose `fixture:"-"`,
    story_meeting_cinematic_pending:                bool `fixture:"-"`,
    story_cinematic_active:                         bool `fixture:"-"`,
    flight_camera:                                  chase_camera.State,
    flight_throttle_overlay_value:                  f32 `fixture:"-"`,
    flight_throttle_overlay_changed_at:             f64 `fixture:"-"`,
    flight_throttle_overlay_fade_started_at:        f64 `fixture:"-"`,
    flight_throttle_overlay_initialized:            bool `fixture:"-"`,
    editor_camera:                                  third_person.Camera,
    editor_focus:                                   third_person.Vec3,
    cursor_world_x, cursor_world_z:                 f32 `fixture:"-"`,
    cursor_height, cursor_material:                 f32 `fixture:"-"`,
    cursor_hit:                                     bool `fixture:"-"`,
    map_time:                                       f32 `fixture:"-"`,
    boat_traffic:                                   boats.Traffic,
    bird_flocks:                                    flocks.System `hs:"-" fixture:"-"`,
    ground_bird_flocks:                             flocks.System `hs:"-" fixture:"-"`,
    marina_dinghy_borrowed:                         bool,
    marina_buoys:                                   Marina_Buoy_Physics `fixture:"-"`,
    occupant:                                       vehicles.Fixture_Occupant,
    pilot:                                          vehicles.Character,
    car:                                            vehicles.Vehicle,
    car_handling_model:                             vehicles.Car_Handling_Model,
    car_drive:                                      vehicles.Car_Drive_State,
    car_trailer:                                    vehicles.Car_Trailer_State,
    car_trailer_attached:                           bool,
    car_trailer_position:                           third_person.Vec3,
    car_trailer_yaw:                                f32,
    postale:                                        postale_game.Runtime,
    libellula:                                      libellula_game.Runtime,
    rondine:                                        rondine_game.Runtime,
    aircraft:                                       vehicles.Aircraft_Fleet,
    postale_visible:                                bool,
    libellula_visible:                              bool,
    rondine_visible:                                bool,
    vehicle_showcase_scene:                         bool,
    wildflower_lab_scene:                           bool,
    vehicle_showcase_target:                        string,
    shadow_lab_scene:                               bool,
    lab:                                            Lab_Fixture_State,
    settlement_vertical_map:                        bool,
    settlement_plan:                                Settlement_Plan `fixture:"-" fixture_map:"-"`,
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
    vehicle_paint_propeller_color:                  canvas2d.Color `fixture:"-"`,
    vehicle_paint_preview_texture_dirty:            bool `fixture:"-"`,
    vehicle_paint_save_pending:                     bool `fixture:"-"`,
    vehicle_paint_save_due_at:                      f32 `fixture:"-"`,
    vehicle_paint_save_failed:                      bool `fixture:"-"`,
    vehicle_paint_clear_confirm_until:              f32 `fixture:"-"`,
    vehicle_paint_sound_until:                      f32 `fixture:"-"`,
    vehicle_paint_saved_postale_position:           flight.Vec3,
    vehicle_paint_saved_libellula_position:         flight.Vec3,
    vehicle_paint_postale_mesh:                     ^vehicles.Aircraft_Mesh `hs:"-" fixture:"-"`,
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
    vehicle_paint_tool_drag_start_position:         [3]f32 `fixture:"-"`,
    vehicle_paint_tool_drag_start_normal:           [3]f32 `fixture:"-"`,
    vehicle_paint_tool_drag_start_screen:           canvas2d.Vector2 `fixture:"-"`,
    vehicle_paint_tool_drag_part:                   vehicles.Aircraft_Mesh_Part `fixture:"-"`,
    vehicle_paint_tool_drag_component:              int `fixture:"-"`,
    vehicle_paint_scope_component:                  bool `fixture:"-"`,
    vehicle_paint_selection_texels:                 []u8 `fixture:"-"`,
    vehicle_paint_selection_active:                 bool `fixture:"-"`,
    vehicle_paint_selection_level:                  int `fixture:"-"`,
    vehicle_paint_selection_last_click_at:          f32 `fixture:"-"`,
    vehicle_paint_selection_next_sweep_at:          f32 `fixture:"-"`,
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
    attendant_dialogue_view:                        Dialogue_View_State `fixture:"-"`,
    dialogue_session:                               dialogue_session.State `fixture:"-"`,
    attendant_dialogue_vehicle_target:              vehicles.Aircraft_Kind `fixture:"-"`,
    attendant_dialogue_vehicle_choices:             [8]vehicles.Aircraft_Kind `fixture:"-"`,
    attendant_dialogue_vehicle_choice_count:        int `fixture:"-"`,
    gerta_position:                                 third_person.Vec3,
    story_state:                                    story.State,
    player_mail:                                    player_mail.State,
    story_catalog:                                  story.Catalog `fixture:"-"`,
    story_quest_catalog:                            story.Quest_Catalog `fixture:"-"`,
    tracked_quest_node:                             quest.Node_ID,
    quest_tracking_suppressed:                      bool,
    quest_tracking_revision:                        u64,
    quest_log_tab:                                  Quest_Log_Tab `fixture:"-"`,
    quest_log_focus:                                int `fixture:"-"`,
    quest_log_scroll:                               int `fixture:"-"`,
    player_mail_focus:                              int `fixture:"-"`,
    player_mail_last_collected:                     int `fixture:"-"`,
    player_mail_notice_until:                       f64 `fixture:"-"`,
    dialogue_resident:                              story.Resident `fixture:"-"`,
    camera_target_lock:                             bool `fixture:"-"`,
    flight_control:                                 postale_game.Control `fixture:"-"`,
    atmosphere:                                     atmosphere.Atmosphere,
    vehicle_effects:                                particle_systems.Vehicle_Effects,
    player_terrain_effects:                         particle_systems.Vehicle_Effects `fixture:"-"`,
    wing_trails:                                    particle_systems.Wing_Trails,
    petal_effects:                                  particle_systems.Petal_Effects,
    tweak:                                          Tweak_State,
    tweak_status:                                   Tweak_Status `fixture:"-"`,
    tweak_panel_visible:                            bool `fixture:"-"`,
    tweak_panel_toggle_down:                        bool `fixture:"-"`,
    tweak_teleport_on_click:                        bool `fixture:"-"`,
    notes_visible:                                  bool `fixture:"-"`,
    default_map_regeneration_active:                bool `hs:"-" fixture:"-"`,
    default_map_regeneration_loading_ready:         bool `hs:"-" fixture:"-"`,
    default_map_regeneration_stage:                 Default_Map_Regeneration_Stage `hs:"-" fixture:"-"`,
    default_map_regeneration_seeds:                 [len(
        terrain.DEFAULT_ISLAND_SEEDS,
    )]u32 `hs:"-" fixture:"-" fixture_map:"-"`,
    dither_state:                                   Dither_State `fixture:"-"`,
    mouse_fur:                                      Mouse_Fur,
    mouse_pattern:                                  Mouse_Fur_Pattern,
    mouse_headgear:                                 Mouse_Accessory,
    mouse_scarf_enabled:                            bool,
    mouse_scarf_color:                              canvas2d.Color,
    mouse_scarf_rotation:                           f32,
    mouse_scarf_angular_velocity:                   f32,
    mouse_mailbag_yaw_lag:                          f32 `fixture:"-"`,
    mouse_mailbag_yaw_velocity:                     f32 `fixture:"-"`,
    mouse_mailbag_roll_lag:                         f32 `fixture:"-"`,
    mouse_mailbag_roll_velocity:                    f32 `fixture:"-"`,
    mouse_mailbag_vertical_lag:                     f32 `fixture:"-"`,
    mouse_mailbag_vertical_velocity:                f32 `fixture:"-"`,
    customization_focus:                            int `fixture:"-"`,
    customization_slider_drag:                      int `fixture:"-"`,
    customization_preview_dragging:                 bool `fixture:"-"`,
    customization_preview_drag_x:                   f32 `fixture:"-"`,
    customization_preview_yaw:                      f32 `fixture:"-"`,
    notes:                                          [FIXTURE_NOTE_CAPACITY]Fixture_Note,
    note_count:                                     int,
    map_source:                                     Fixture_Map_Source,
}

FIXTURE_SCHEMA_VERSION :: 23
