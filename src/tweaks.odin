package main

import atmosphere "../packages/atmosphere"
import dio "../packages/dio"
import flight "../packages/flight"
import fog_field "../packages/fog_field"
import im "../packages/imgui"
import mouse_tail "../packages/mouse_tail"
import postale_game "../packages/postale"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import tweak_package "../packages/tweak"
import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import "core:math/linalg"

TWEAK_FILE_PATH :: "adriatic.tweak.toml"
TWEAK_FILE_VERSION :: i64(1)

Tweak_Status :: enum {
    Defaults,
    Loaded,
    Saved,
    Save_Failed,
}

Tweak_Page :: enum {
    Terrain,
    Weather_Time,
    Ocean_Fog,
    Lighting_Materials,
    Mouse,
    Car,
    Postale,
    Particles,
    Camera,
    Developer,
}

tweak_selected_page := Tweak_Page.Terrain
tweak_filter: im.TextFilter

Terrain_Tweak :: struct {
    tool:      terrain.Tool,
    radius:    f32 `tweak:"range=0..400;1"`,
    strength:  f32 `tweak:"range=0..1;.01"`,
    hardness:  f32 `tweak:"range=0..1;.01"`,
    sea_level: f32 `tweak:"range=-50..50;.1"`,
}

Vehicle_Tweak :: struct {
    interaction_radius: f32 `tweak:"range=0..20;.05"`,
    exit_distance:      f32 `tweak:"range=0..20;.05"`,
    locked:             bool,
}

Camera_Tweak :: struct {
    editor_camera:      third_person.Camera,
    editor_focus:       third_person.Vec3,
    player_camera:      third_person.Camera,
    flight_orbit_yaw:   f32,
    flight_orbit_pitch: f32,
}

Player_Animation_Tweak :: struct {
    stride_radians_per_meter:       f32 `tweak:"range=.1..16;.05"`,
    trot_stride_radians_per_meter:  f32 `tweak:"range=.1..16;.05"`,
    bound_stride_radians_per_meter: f32 `tweak:"range=.1..16;.05"`,
    walk_full_speed:                f32 `tweak:"range=.1..20;.05"`,
    trot_full_speed:                f32 `tweak:"range=.1..20;.05"`,
    bound_start_speed:              f32 `tweak:"range=.1..30;.05"`,
    bound_full_speed:               f32 `tweak:"range=.1..30;.05"`,
    vertical_full_speed:            f32 `tweak:"range=.1..20;.05"`,
    locomotion_blend_rate:          f32 `tweak:"range=.1..30;.1"`,
    airborne_blend_rate:            f32 `tweak:"range=.1..30;.1"`,
    vertical_blend_rate:            f32 `tweak:"range=.1..30;.1"`,
    turn_blend_rate:                f32 `tweak:"range=.1..30;.1"`,
    brake_blend_rate:               f32 `tweak:"range=.1..30;.1"`,
    turn_lean_radians:              f32 `tweak:"range=0..0.5;.005"`,
    turn_spine_offset:              f32 `tweak:"range=0..0.3;.005"`,
    turn_paw_offset:                f32 `tweak:"range=0..0.3;.005"`,
    run_body_lift:                  f32 `tweak:"range=0..0.2;.005"`,
    scurry_lean_radians:            f32 `tweak:"range=0..0.5;.005"`,
    scurry_acceleration_lean:       f32 `tweak:"range=0..0.05;.001"`,
    scurry_compression:             f32 `tweak:"range=0..0.2;.005"`,
    scurry_spring_stiffness:        f32 `tweak:"range=1..200;1"`,
    scurry_spring_damping:          f32 `tweak:"range=0..40;.5"`,
    brake_compression:              f32 `tweak:"range=0..0.3;.005"`,
    tail_counterbalance:            f32 `tweak:"range=0..0.5;.005"`,
    slope_alignment:                f32 `tweak:"range=0..1;.01"`,
    body_softness_strength:         f32 `tweak:"range=0..1;.01"`,
    body_softness_influence_radius: f32 `tweak:"range=.02..0.4;.005"`,
    body_softness_volume_return:    f32 `tweak:"range=0..1;.01"`,
    body_softness_stiffness:        f32 `tweak:"range=1..300;1"`,
    body_softness_damping:          f32 `tweak:"range=0..60;.5"`,
    body_softness_inertial_lag:     f32 `tweak:"range=0..1;.01"`,
    body_softness_max_displacement: f32 `tweak:"range=.005..0.15;.005"`,
}

World_Tweak :: struct {
    far_clip:               f32 `tweak:"range=100..50000;10"`,
    fog_start:              f32 `tweak:"range=0..50000;10"`,
    fog_end:                f32 `tweak:"range=1..50000;10"`,
    map_ocean_extent:       f32 `tweak:"range=100..50000;10"`,
    map_ocean_divisions:    int,
    editor_ocean_extent:    f32 `tweak:"range=100..50000;10"`,
    editor_ocean_divisions: int,
    map_ocean_depth:        f32 `tweak:"range=0..100;.01"`,
    editor_ocean_depth:     f32 `tweak:"range=0..100;.01"`,
}

Particle_CPU_Tweak :: struct {
    spawn_rate:             f32,
    origin_radius:          f32,
    radial_speed:           f32,
    radial_speed_variation: f32,
    lift_speed:             f32,
    lift_speed_variation:   f32,
    lifetime:               f32,
    lifetime_variation:     f32,
    size:                   f32,
    size_variation:         f32,
    gravity:                f32,
}

Particle_Vehicle_Tweak :: struct {
    dust_spawn_rate:         f32,
    dust_speed_divisor:      f32,
    dust_steering_divisor:   f32,
    dust_handbrake_bonus:    f32,
    dust_max_intensity:      f32,
    dust_spawn_threshold:    f32,
    dust_contact_spread:     f32,
    dust_height:             f32,
    dust_radial_speed:       f32,
    dust_intensity_speed:    f32,
    dust_lift:               f32,
    dust_lift_variation:     f32,
    dust_lifetime:           f32,
    dust_lifetime_variation: f32,
    dust_size:               f32,
    dust_intensity_size:     f32,
    dust_lift_size:          f32,
    dust_gravity:            f32,
}

Particle_Wing_Tweak :: struct {
    airspeed_start:     f32,
    airspeed_range:     f32,
    wind_strength:      f32,
    spawn_rate:         f32,
    forward_speed:      f32,
    forward_jitter:     f32,
    wind_velocity:      f32,
    vertical_jitter:    f32,
    lifetime:           f32,
    lifetime_variation: f32,
    wind_lifetime:      f32,
    size:               f32,
    strength_size:      f32,
    wind_size:          f32,
    curve:              f32,
    curve_variation:    f32,
    gravity:            f32,
}

Particle_GPU_Tweak :: struct {
    center:           [3]f32,
    radius_min:       f32,
    radius_range:     f32,
    cycle_rate_min:   f32,
    cycle_rate_range: f32,
    drift:            f32,
    size_min:         f32,
    size_range:       f32,
    fade:             f32,
    count:            int,
    color_start:      [3]f32 `tweak:"widget=color"`,
    color_end:        [3]f32 `tweak:"widget=color"`,
}

Particle_Tweak :: struct {
    cpu_seed:     u32,
    vehicle_seed: u32,
    wing_seed:    u32,
    cpu:          Particle_CPU_Tweak,
    vehicle:      Particle_Vehicle_Tweak,
    wing:         Particle_Wing_Tweak,
    gpu:          Particle_GPU_Tweak,
}

Presentation_Tweak :: struct {
    terrain_water:     [4]f32 `tweak:"widget=color"`,
    terrain_sand:      [4]f32 `tweak:"widget=color"`,
    terrain_soil:      [4]f32 `tweak:"widget=color"`,
    terrain_grass:     [4]f32 `tweak:"widget=color"`,
    painted_threshold: f32 `tweak:"range=0..1;.01"`,
    sand_start:        f32 `tweak:"range=0..10;.01"`,
    land_blend:        f32 `tweak:"range=.01..10;.01"`,
    grass_start:       f32 `tweak:"range=0..20;.01"`,
    grass_blend:       f32 `tweak:"range=.01..20;.01"`,
    light_direction:   [3]f32,
    shade_base:        f32 `tweak:"range=0..2;.01"`,
    shade_strength:    f32 `tweak:"range=0..2;.01"`,
    shade_min:         f32 `tweak:"range=0..2;.01"`,
    shade_max:         f32 `tweak:"range=0..2;.01"`,
    height_shade:      f32 `tweak:"range=-1..1;.001"`,
}

Tweak_State :: struct {
    terrain:          Terrain_Tweak,
    atmosphere:       atmosphere.Atmosphere,
    player:           third_person.Config,
    player_animation: Player_Animation_Tweak,
    player_tail:      mouse_tail.Config,
    camera:           Camera_Tweak,
    world:            World_Tweak,
    particles:        Particle_Tweak,
    car:              vehicles.Car_Drive_Tune,
    car_vehicle:      Vehicle_Tweak,
    postale_airframe: flight.Airframe,
    postale_runtime:  flight.Runtime,
    postale_tuning:   postale_game.Tuning,
    postale_vehicle:  Vehicle_Tweak,
    presentation:     Presentation_Tweak,
}

tweak_default_player :: proc() -> third_person.Config {
    player := third_person.default_config()
    // Start from dynamically similar scaled-mouse locomotion, then use a
    // modest gameplay multiplier to keep traversal responsive.
    player.move_speed = 3.2
    player.run_speed = 6.4
    return player
}

tweak_default_presentation :: proc() -> Presentation_Tweak {
    return {
        terrain_water = {26 / 255.0, 80 / 255.0, 104 / 255.0, 1},
        terrain_sand = {205 / 255.0, 183 / 255.0, 126 / 255.0, 1},
        terrain_soil = {145 / 255.0, 101 / 255.0, 61 / 255.0, 1},
        terrain_grass = {70 / 255.0, 133 / 255.0, 80 / 255.0, 1},
        painted_threshold = .5,
        sand_start = .18,
        land_blend = .72,
        grass_start = .9,
        grass_blend = 3.1,
        light_direction = {-.45, .85, -.3},
        shade_base = .48,
        shade_strength = .52,
        shade_min = .42,
        shade_max = 1.05,
        height_shade = .012,
    }
}

tweak_default_world :: proc() -> World_Tweak {
    return {
        far_clip = 12000,
        fog_start = 4500,
        fog_end = 11000,
        map_ocean_extent = 12000,
        map_ocean_divisions = 48,
        editor_ocean_extent = 15000,
        editor_ocean_divisions = 32,
        map_ocean_depth = .08,
        editor_ocean_depth = 2,
    }
}

tweak_default_particles :: proc() -> Particle_Tweak {
    return {
        cpu_seed = 0x9e3779b9,
        vehicle_seed = 0x72b7e4a1,
        wing_seed = 0x1f123bb5,
        cpu = {
            spawn_rate = 72,
            origin_radius = 1.8,
            radial_speed = .35,
            radial_speed_variation = .55,
            lift_speed = .45,
            lift_speed_variation = .75,
            lifetime = 1.2,
            lifetime_variation = 1.7,
            size = .08,
            size_variation = .14,
            gravity = .36,
        },
        vehicle = {
            dust_spawn_rate = 48,
            dust_speed_divisor = 12,
            dust_steering_divisor = 18,
            dust_handbrake_bonus = .65,
            dust_max_intensity = 1.5,
            dust_spawn_threshold = .18,
            dust_contact_spread = .18,
            dust_height = .045,
            dust_radial_speed = .35,
            dust_intensity_speed = 1,
            dust_lift = .18,
            dust_lift_variation = .32,
            dust_lifetime = .28,
            dust_lifetime_variation = .42,
            dust_size = .08,
            dust_intensity_size = .08,
            dust_lift_size = .10,
            dust_gravity = .22,
        },
        wing = {
            airspeed_start = 12,
            airspeed_range = 34,
            wind_strength = .025,
            spawn_rate = 72,
            forward_speed = .22,
            forward_jitter = .025,
            wind_velocity = .18,
            vertical_jitter = .08,
            lifetime = .55,
            lifetime_variation = .55,
            wind_lifetime = .02,
            size = .09,
            strength_size = .12,
            wind_size = .004,
            curve = .7,
            curve_variation = .3,
            gravity = .025,
        },
        gpu = {
            center = {1300, 6, 1300},
            radius_min = .6,
            radius_range = 2.4,
            cycle_rate_min = .18,
            cycle_rate_range = .22,
            drift = .35,
            size_min = .055,
            size_range = .12,
            fade = .25,
            count = 512,
            color_start = {.95, .65, .22},
            color_end = {1, .92, .55},
        },
    }
}

tweak_default_state :: proc() -> Tweak_State {
    return {
        terrain = {tool = .Raise, radius = 48, strength = .10, hardness = .5, sea_level = 0},
        atmosphere = atmosphere.new(0x41c10),
        player = tweak_default_player(),
        player_tail = mouse_tail.default_config(),
        player_animation = {
            stride_radians_per_meter = 6.0,
            trot_stride_radians_per_meter = 5.1,
            bound_stride_radians_per_meter = 5.7,
            walk_full_speed = 3.2,
            trot_full_speed = 4.8,
            bound_start_speed = 5.7,
            bound_full_speed = 6.4,
            vertical_full_speed = 5,
            locomotion_blend_rate = 8,
            airborne_blend_rate = 12,
            vertical_blend_rate = 8,
            turn_blend_rate = 10,
            brake_blend_rate = 12,
            turn_lean_radians = .21,
            turn_spine_offset = .08,
            turn_paw_offset = .075,
            run_body_lift = .065,
            scurry_lean_radians = .11,
            scurry_acceleration_lean = .009,
            scurry_compression = .055,
            scurry_spring_stiffness = 82,
            scurry_spring_damping = 15,
            brake_compression = .075,
            tail_counterbalance = .22,
            slope_alignment = .55,
            body_softness_strength = .42,
            body_softness_influence_radius = .16,
            body_softness_volume_return = .34,
            body_softness_stiffness = 110,
            body_softness_damping = 20,
            body_softness_inertial_lag = .035,
            body_softness_max_displacement = .055,
        },
        camera = {
            editor_camera = {yaw_radians = math.PI * .25, pitch_radians = .58, distance = 900},
            editor_focus = {
                terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET,
                0,
                terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET,
            },
            player_camera = third_person.default_camera(),
        },
        world = tweak_default_world(),
        particles = tweak_default_particles(),
        car = vehicles.CAR_DRIVE_SEDAN_TUNE,
        car_vehicle = {interaction_radius = 3, exit_distance = 1.45},
        postale_airframe = flight.postale_airframe(),
        postale_runtime = flight.default_runtime(),
        postale_tuning = postale_game.default_tuning(),
        postale_vehicle = {interaction_radius = 2.5, exit_distance = 2.2},
        presentation = tweak_default_presentation(),
    }
}

tweak_sync_from_editor :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.tweak.terrain = {
        tool      = editor.tool,
        radius    = editor.radius,
        strength  = editor.strength,
        hardness  = editor.hardness,
        sea_level = editor.project.sea_level,
    }
    editor.tweak.atmosphere = editor.atmosphere
    editor.tweak.camera.editor_camera = editor.editor_camera
    editor.tweak.camera.editor_focus = editor.editor_focus
    editor.tweak.camera.player_camera = editor.camera
    editor.tweak.camera.flight_orbit_yaw = editor.flight_camera.orbit_yaw
    editor.tweak.camera.flight_orbit_pitch = editor.flight_camera.orbit_pitch
    editor.tweak.car_vehicle = {
        interaction_radius = editor.car.interaction_radius,
        exit_distance      = editor.car.exit_distance,
        locked             = editor.car.locked,
    }
    editor.tweak.postale_airframe = editor.postale.airframe
    editor.tweak.postale_runtime = editor.postale.flight_runtime
    editor.tweak.postale_tuning = editor.postale.tuning
    editor.tweak.postale_vehicle = {
        interaction_radius = editor.postale.vehicle.interaction_radius,
        exit_distance      = editor.postale.vehicle.exit_distance,
        locked             = editor.postale.vehicle.locked,
    }
}

tweak_apply_to_editor :: proc(editor: ^Editor) {
    if editor == nil do return
    state := &editor.tweak
    editor.tool = state.terrain.tool
    if editor.tool != .Structure {
        editor.architecture_node_mode = false
        editor.architecture_paint_mode = false
        editor.road_mode = false
        editor.curve_mode = false
        curve_reset(editor)
        editor.structure_placing = false
        editor.structure_moving = false
    }
    editor.radius = clamp(state.terrain.radius, terrain.BASE_CELL_SIZE, 400)
    editor.strength = clamp(state.terrain.strength, 0, 1)
    editor.hardness = clamp(state.terrain.hardness, 0, 1)
    old_sea_level := editor.project.sea_level
    editor.project.sea_level = state.terrain.sea_level
    if editor.project.sea_level != old_sea_level do editor.project.revision += 1
    editor.atmosphere = state.atmosphere
    editor.camera = state.camera.player_camera
    editor.editor_camera = state.camera.editor_camera
    editor.editor_focus = state.camera.editor_focus
    editor.flight_camera.orbit_yaw = state.camera.flight_orbit_yaw
    editor.flight_camera.orbit_pitch = clamp(state.camera.flight_orbit_pitch, -.75, .75)
    editor.car.interaction_radius = state.car_vehicle.interaction_radius
    editor.car.exit_distance = state.car_vehicle.exit_distance
    editor.car.locked = state.car_vehicle.locked
    editor.postale.airframe = state.postale_airframe
    editor.postale.flight_runtime = state.postale_runtime
    editor.postale.tuning = state.postale_tuning
    editor.postale.vehicle.interaction_radius = state.postale_vehicle.interaction_radius
    editor.postale.vehicle.exit_distance = state.postale_vehicle.exit_distance
    editor.postale.vehicle.locked = state.postale_vehicle.locked
}

tweak_save_editor :: proc(editor: ^Editor) {
    if editor == nil do return
    tweak_sync_from_editor(editor)
    if err := tweak_package.save(TWEAK_FILE_PATH, TWEAK_FILE_VERSION, &editor.tweak); err != nil {
        editor.tweak_status = .Save_Failed
    } else {
        editor.tweak_status = .Saved
    }
}

tweak_load_editor :: proc(editor: ^Editor) {
    if editor == nil do return
    state := tweak_default_state()
    result := tweak_package.load(TWEAK_FILE_PATH, TWEAK_FILE_VERSION, &state, "Adriatic tweaks")
    editor.tweak = state
    tweak_apply_to_editor(editor)
    editor.tweak_status = result.loaded_sections > 0 ? .Loaded : .Defaults
    tweak_package.destroy_load_result(&result)
}

tweak_drag_f32 :: proc(label: cstring, value: ^f32, lower, upper, speed: f32) -> bool {
    return im.DragFloat(label, value, speed, lower, upper, "%.3f", im.SliderFlags_AlwaysClamp)
}

tweak_section :: proc(label: cstring, default_open := false) -> bool {
    im.SetNextItemOpen(default_open, im.Cond.FirstUseEver)
    return im.CollapsingHeader(label)
}

terrain_panel_select_brush :: proc(editor: ^Editor, tool: terrain.Tool) {
    if editor == nil do return
    switch tool {
    case .Raise:
        authoring_select_tool(editor, .Sculpt)
    case .Smooth:
        authoring_select_tool(editor, .Smooth)
    case .Paint:
        authoring_select_tool(editor, .Paint)
    case .Structure:
        authoring_select_tool(editor, .Formations)
    }
}

terrain_panel_undo :: proc(editor: ^Editor) {
    if editor == nil do return
    if editor.tool == .Structure {
        structure_undo(editor)
        editor.structure_placing = false
        editor.structure_moving = false
    } else {
        terrain_undo(editor)
    }
}

terrain_panel_redo :: proc(editor: ^Editor) {
    if editor == nil do return
    if editor.tool == .Structure {
        structure_redo(editor)
        editor.structure_placing = false
        editor.structure_moving = false
    } else {
        terrain_redo(editor)
    }
}

tweak_draw_terrain :: proc(editor: ^Editor) {
    state := &editor.tweak.terrain
    im.TextUnformatted("Brush")
    if im.RadioButton("Raise", state.tool == .Raise) do terrain_panel_select_brush(editor, .Raise)
    im.SameLine()
    if im.RadioButton("Smooth", state.tool == .Smooth) do terrain_panel_select_brush(editor, .Smooth)
    im.SameLine()
    if im.RadioButton("Paint", state.tool == .Paint) do terrain_panel_select_brush(editor, .Paint)
    im.SameLine()
    if im.RadioButton("Formations", state.tool == .Structure && !editor.road_mode) do terrain_panel_select_brush(editor, .Structure)
    im.SameLine()
    if im.RadioButton("Roads", editor.road_mode) {
        authoring_select_tool(editor, .Roads)
    }
    if state.tool == .Structure {
        if editor.road_mode {
            im.TextDisabled("LMB adds/connects nodes; drag handles curves; RMB ends chain")
            im.TextDisabled("Wheel zoom; Alt+wheel width; Shift+wheel radius; Backspace deletes")
            im.TextUnformatted("Surface")
            if im.RadioButton("Asphalt", editor.road_pavement == .Asphalt) {
                road_set_pavement(editor, .Asphalt)
            }
            im.SameLine()
            if im.RadioButton("Gravel", editor.road_pavement == .Gravel) {
                road_set_pavement(editor, .Gravel)
            }
            im.SameLine()
            if im.RadioButton("Cobblestone", editor.road_pavement == .Cobblestone) {
                road_set_pavement(editor, .Cobblestone)
            }
            im.SameLine()
            if im.RadioButton("Dirt", editor.road_pavement == .Dirt) {
                road_set_pavement(editor, .Dirt)
            }
            im.SameLine()
            if im.RadioButton("Steps", editor.road_pavement == .Steps) {
                road_set_pavement(editor, .Steps)
            }
        } else {
            im.TextDisabled("LMB places/selects; RMB makes cliffs; Esc cancels")
            im.TextDisabled("Wheel zoom; Alt+wheel height; Shift+wheel size; R rotates")
        }
        im.TextDisabled("Ctrl+Z/Y undoes or redoes formation edits")
    } else {
        tweak_drag_f32("Radius", &state.radius, terrain.BASE_CELL_SIZE, 400, 1)
        tweak_drag_f32("Strength", &state.strength, 0, 1, .01)
        tweak_drag_f32("Hardness", &state.hardness, 0, 1, .01)
        im.TextDisabled("Viewport: wheel zoom; Shift+wheel strength; Alt+wheel hardness")
        im.TextDisabled("LMB raises/paints, RMB lowers/erases")
        im.TextDisabled("Ctrl+Z/Y undoes or redoes the last terrain stroke")
    }
    im.TextDisabled("Ctrl+S saves the project; Ctrl+O loads it")
    history_kind: cstring = editor.tool == .Structure ? "formation" : "terrain"
    undo_count := editor.tool == .Structure ? editor.structure_undo_count : editor.terrain_undo_count
    redo_count := editor.tool == .Structure ? editor.structure_redo_count : editor.terrain_redo_count
    undo_label: cstring = editor.tool == .Structure ? "Undo formation" : "Undo terrain"
    redo_label: cstring = editor.tool == .Structure ? "Redo formation" : "Redo terrain"
    im.BeginDisabled(undo_count <= 0)
    if im.Button(undo_label) do terrain_panel_undo(editor)
    im.EndDisabled()
    im.SameLine()
    im.BeginDisabled(redo_count <= 0)
    if im.Button(redo_label) do terrain_panel_redo(editor)
    im.EndDisabled()
    im.TextDisabled("History: %d undo / %d redo %s steps", undo_count, redo_count, history_kind)
    tweak_drag_f32("Sea level", &state.sea_level, -50, 50, .1)
    if tweak_section("Navigation") {
        if im.Button("Focus terrain") {
            editor_focus_terrain(editor)
            // Preserve the button's camera change when the inspector applies its
            // synchronized state at the end of this frame.
            tweak_sync_from_editor(editor)
        }
        if editor.structure_selected >= 0 && editor.structure_selected < editor.project.structure_count {
            im.SameLine()
            im.TextDisabled("Selected formation")
        } else {
            im.TextDisabled("Frames the selected formation, or the default island")
        }
    }
    if tweak_section("Project file") {
        im.Text("File: %s", EDITOR_MAP_ARTIFACT_PATH)
        if im.Button("Save project") do terrain_project_save(editor)
        im.SameLine()
        if im.Button("Load project") {
            terrain_project_load(editor)
            // Keep the end-of-frame tweak application from restoring the old sea
            // level over the project we just loaded.
            tweak_sync_from_editor(editor)
        }
        project_state: cstring = editor.project.revision == editor.terrain_saved_revision ? "Saved" : "Unsaved"
        im.Text("State: %s", project_state)
        if editor.terrain_file_status != nil {
            im.TextDisabled("%s", editor.terrain_file_status)
        }
    }
    if tweak_section("Project diagnostics") {
        im.Text("Revision: %d", editor.project.revision)
        im.Text("Clipmap levels: %d", terrain.CLIPMAP_LEVELS)
        im.Text("World size: %.0f m", terrain.WORLD_SIZE_METERS)
    }
}

tweak_draw_atmosphere :: proc(editor: ^Editor) {
    a := &editor.tweak.atmosphere
    tweak_draw_time_of_day(editor)
    if !tweak_section("Weather", true) do return
    im.InputScalar("Seed", im.DataType.U32, rawptr(&a.seed), nil, nil, "%u")
    im.TextUnformatted("Weather override")
    if im.RadioButton("Automatic", a.override == .Automatic) do a.override = .Automatic
    im.SameLine()
    if im.RadioButton("Clear", a.override == .Clear) do a.override = .Clear
    im.SameLine()
    if im.RadioButton("Windy", a.override == .Windy) do a.override = .Windy
    im.SameLine()
    if im.RadioButton("Storm", a.override == .Storm) do a.override = .Storm
    im.SeparatorText("Adriatic climate")
    im.TextUnformatted(fmt.ctprintf(
        "Current %s  next %s  season %.1f%%",
        atmosphere.regime_name(a.climate.current),
        atmosphere.regime_name(a.climate.next),
        atmosphere.season_phase(a) * 100,
    ))
    if im.RadioButton("Maestral", a.climate.current == .Maestral) do atmosphere.set_climate_regime(a, .Maestral)
    im.SameLine()
    if im.RadioButton("Bura clear", a.climate.current == .Bura_Clear) do atmosphere.set_climate_regime(a, .Bura_Clear)
    im.SameLine()
    if im.RadioButton("Bura storm", a.climate.current == .Bura_Storm) do atmosphere.set_climate_regime(a, .Bura_Storm)
    if im.RadioButton("Jugo", a.climate.current == .Jugo) do atmosphere.set_climate_regime(a, .Jugo)
    im.SameLine()
    if im.RadioButton("Calm humid", a.climate.current == .Calm_Humid) do atmosphere.set_climate_regime(a, .Calm_Humid)
    im.SameLine()
    if im.RadioButton("Post front", a.climate.current == .Post_Front) do atmosphere.set_climate_regime(a, .Post_Front)
    im.SeparatorText("Front schedule")
    im.Text("Schedule: %s", a.override == .Automatic ? "RUNNING" : "PAUSED BY OVERRIDE")
    im.Text("Clock %.1f s  next/event %.1f s", a.schedule.elapsed_seconds, atmosphere.front_seconds_until_next(a))
    if a.schedule.front.active {
        front := &a.schedule.front
        im.Text(
            "Front %u  progress %.1f%%  heading %.2f, %.2f",
            front.event_id,
            atmosphere.front_progress(a) * 100,
            front.direction[0],
            front.direction[1],
        )
        im.Text("Width %.0f m  speed %.2f m/s  intensity %.2f", front.width, front.speed, front.intensity)
    } else {
        im.TextUnformatted("No active front")
    }
    if im.Button("Trigger deterministic front now") do atmosphere.trigger_front(a)
    im.SeparatorText("Current weather")
    tweak_drag_f32("Cloud cover", &a.weather.cloud_cover, 0, 1, .01)
    tweak_drag_f32("Precipitation", &a.weather.precipitation, 0, 1, .01)
    tweak_drag_f32("Haze", &a.weather.haze, 0, 1, .01)
    tweak_drag_f32("Severity", &a.weather.severity, 0, 1, .01)
    im.DragFloat2("Wind", &a.weather.wind, .05, -100, 100, "%.2f", im.SliderFlags_AlwaysClamp)
    im.SeparatorText("Procedural fog banks")
    im.Checkbox("Fog enabled", &fog_debug_enabled)
    im.Checkbox("Fog shells", &fog_debug_shells)
    im.SliderFloat("Fog density", &fog_debug_density_multiplier, 0, 2, "%.2f", im.SliderFlags_AlwaysClamp)
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    field := fog_field.generate(
        a.seed,
        a.front_seconds,
        a.weather,
        {{-half_extent, -half_extent}, {half_extent, half_extent}},
        a.climate.current,
    )
    for bank, index in field.banks {
        im.Text(
            "Bank %d: center %.0f, %.0f  radii %.0f, %.0f  top %.0f",
            index + 1,
            bank.center.x,
            bank.center.y,
            bank.radii.x,
            bank.radii.y,
            bank.top_altitude,
        )
    }
}

tweak_draw_time_of_day :: proc(editor: ^Editor) {
    a := &editor.tweak.atmosphere
    im.SeparatorText("Time of day")
    im.SliderFloat("##Time of day", &a.world_minutes, 0, atmosphere.DAY_MINUTES, "", im.SliderFlags_AlwaysClamp)
    total_minutes := int(a.world_minutes) % int(atmosphere.DAY_MINUTES)
    im.SameLine()
    im.Text("%02d:%02d", total_minutes / 60, total_minutes % 60)
    im.Checkbox("Pause time", &a.paused)
}

tweak_draw_player :: proc(editor: ^Editor) {
    c := &editor.tweak.player
    a := &editor.tweak.player_animation
    if tweak_section("Movement", true) {
        tweak_drag_f32("Move speed", &c.move_speed, 0, 100, .1)
        tweak_drag_f32("Run speed", &c.run_speed, 0, 100, .1)
        tweak_drag_f32("Ground acceleration", &c.ground_acceleration, 0, 200, .5)
        tweak_drag_f32("Ground deceleration", &c.ground_deceleration, 0, 200, .5)
        tweak_drag_f32("Run acceleration", &c.run_acceleration, 0, 200, .5)
        tweak_drag_f32("Run deceleration", &c.run_deceleration, 0, 200, .5)
        tweak_drag_f32("Run steering speed", &c.run_steering_speed, 0, 20, .05)
        tweak_drag_f32("Drift minimum speed", &c.drift_min_speed, 0, 100, .1)
        tweak_drag_f32("Drift charge seconds", &c.drift_charge_seconds, .05, 5, .05)
        tweak_drag_f32("Boost speed", &c.boost_speed, 0, 100, .1)
        tweak_drag_f32("Boost acceleration", &c.boost_acceleration, 0, 200, .5)
        tweak_drag_f32("Boost duration", &c.boost_duration, 0, 5, .05)
        tweak_drag_f32("Reversal braking", &c.reversal_braking, 0, 200, .5)
        tweak_drag_f32("Reversal speed", &c.reversal_speed, 0, 20, .05)
        tweak_drag_f32("Facing turn speed", &c.facing_turn_speed, 0, 40, .1)
        tweak_drag_f32("Air acceleration", &c.air_acceleration, 0, 200, .5)
        tweak_drag_f32("Jump speed", &c.jump_speed, 0, 50, .1)
        tweak_drag_f32("Gravity", &c.gravity, 0, 100, .1)
        tweak_drag_f32("Slope gravity scale", &c.slope_gravity_scale, 0, 2, .01)
        tweak_drag_f32("Max slope acceleration", &c.max_slope_acceleration, 0, 50, .1)
    }
    if tweak_section("Gait and animation", true) {
        tweak_drag_f32("Walk stride radians / meter", &a.stride_radians_per_meter, .1, 16, .05)
        tweak_drag_f32("Trot stride radians / meter", &a.trot_stride_radians_per_meter, .1, 16, .05)
        tweak_drag_f32("Bound stride radians / meter", &a.bound_stride_radians_per_meter, .1, 16, .05)
        tweak_drag_f32("Full walk speed", &a.walk_full_speed, .1, 20, .05)
        tweak_drag_f32("Full trot speed", &a.trot_full_speed, .1, 20, .05)
        tweak_drag_f32("Bound start speed", &a.bound_start_speed, .1, 30, .05)
        tweak_drag_f32("Full bound speed", &a.bound_full_speed, .1, 30, .05)
        tweak_drag_f32("Full vertical speed", &a.vertical_full_speed, .1, 20, .05)
        tweak_drag_f32("Locomotion blend rate", &a.locomotion_blend_rate, .1, 30, .1)
        tweak_drag_f32("Airborne blend rate", &a.airborne_blend_rate, .1, 30, .1)
        tweak_drag_f32("Jump / fall blend rate", &a.vertical_blend_rate, .1, 30, .1)
        tweak_drag_f32("Turn blend rate", &a.turn_blend_rate, .1, 30, .1)
        tweak_drag_f32("Brake blend rate", &a.brake_blend_rate, .1, 30, .1)
        tweak_drag_f32("Turn lean radians", &a.turn_lean_radians, 0, .5, .005)
        tweak_drag_f32("Turn spine offset", &a.turn_spine_offset, 0, .3, .005)
        tweak_drag_f32("Turn paw offset", &a.turn_paw_offset, 0, .3, .005)
        tweak_drag_f32("Running body lift", &a.run_body_lift, 0, .2, .005)
        tweak_drag_f32("Scurry lean radians", &a.scurry_lean_radians, 0, .5, .005)
        tweak_drag_f32("Scurry acceleration lean", &a.scurry_acceleration_lean, 0, .05, .001)
        tweak_drag_f32("Scurry compression", &a.scurry_compression, 0, .2, .005)
        tweak_drag_f32("Scurry spring stiffness", &a.scurry_spring_stiffness, 1, 200, 1)
        tweak_drag_f32("Scurry spring damping", &a.scurry_spring_damping, 0, 40, .5)
        tweak_drag_f32("Brake compression", &a.brake_compression, 0, .3, .005)
        tweak_drag_f32("Tail counterbalance", &a.tail_counterbalance, 0, .5, .005)
        tweak_drag_f32("Slope alignment", &a.slope_alignment, 0, 1, .01)
    }
    if tweak_section("Body softness") {
        tweak_drag_f32("Compression strength", &a.body_softness_strength, 0, 1, .01)
        tweak_drag_f32("Influence radius", &a.body_softness_influence_radius, .02, .4, .005)
        tweak_drag_f32("Volume return", &a.body_softness_volume_return, 0, 1, .01)
        tweak_drag_f32("Softness stiffness", &a.body_softness_stiffness, 1, 300, 1)
        tweak_drag_f32("Softness damping", &a.body_softness_damping, 0, 60, .5)
        tweak_drag_f32("Inertial lag", &a.body_softness_inertial_lag, 0, 1, .01)
        tweak_drag_f32("Maximum displacement", &a.body_softness_max_displacement, .005, .15, .005)
    }
    tail := &editor.tweak.player_tail
    if tweak_section("Tail physics") {
        tweak_drag_f32("Tail segment length", &tail.segment_length, .05, .5, .005)
        tweak_drag_f32("Tail collision radius", &tail.radius, .005, .1, .001)
        tweak_drag_f32("Tail gravity", &tail.gravity, 0, 40, .1)
        // mouse_tail.Config.damping stores retained velocity: higher values
        // preserve more rebound, so present it in the direction artists feel.
        tweak_drag_f32("Tail springiness", &tail.damping, 0, 1, .005)
        tweak_drag_f32("Tail root stiffness", &tail.root_stiffness, 0, 1, .01)
        tweak_drag_f32("Tail bend stiffness", &tail.bend_stiffness, 0, 1, .01)
        tweak_drag_f32("Tail surface friction", &tail.surface_friction, 0, 1, .01)
    }
    if tweak_section("Diagnostics") {
        im.Text(
            "Position: %.2f %.2f %.2f",
            editor.player.position.x,
            editor.player.position.y,
            editor.player.position.z,
        )
        im.Text("Grounded: %s", editor.player.grounded ? "yes" : "no")
        im.Text("Running: %s", editor.player.running ? "yes" : "no")
        im.Text(
            "Drift: %s  charge %.2f  boost %.2fs",
            editor.player.drifting ? "yes" : "no",
            editor.player.drift_charge,
            editor.player.boost_seconds,
        )
        im.Text(
            "Blend: walk %.2f  air %.2f  vertical %+.2f",
            editor.player_gait_weight,
            editor.player_airborne_weight,
            editor.player_vertical_pose,
        )
        im.Text(
            "Scurry: %.2f  lean %+.3f  compression %.3f",
            editor.player_scurry_weight,
            editor.player_scurry_lean,
            editor.player_scurry_compression,
        )
        im.Text(
            "Weight: turn %+.2f  brake %.2f  slope %.2f %.2f %.2f",
            editor.player_turn_pose,
            editor.player_brake_pose,
            editor.player.ground_normal.x,
            editor.player.ground_normal.y,
            editor.player.ground_normal.z,
        )
    }
}

tweak_draw_camera :: proc(editor: ^Editor) {
    c := &editor.tweak.camera
    im.SeparatorText("Editor camera")
    tweak_drag_f32("Editor yaw", &c.editor_camera.yaw_radians, -math.PI * 2, math.PI * 2, .01)
    tweak_drag_f32("Editor pitch", &c.editor_camera.pitch_radians, -.85, 1.2, .01)
    tweak_drag_f32("Editor distance", &c.editor_camera.distance, 80, 5000, 1)
    tweak_drag_f32("Editor height", &c.editor_camera.height, -100, 100, .1)
    tweak_drag_f32("Editor focus X", &c.editor_focus.x, -10000, 10000, 1)
    tweak_drag_f32("Editor focus Y", &c.editor_focus.y, -10000, 10000, 1)
    tweak_drag_f32("Editor focus Z", &c.editor_focus.z, -10000, 10000, 1)
    im.SeparatorText("Player camera")
    tweak_drag_f32("Player yaw", &c.player_camera.yaw_radians, -math.PI * 2, math.PI * 2, .01)
    tweak_drag_f32("Player pitch", &c.player_camera.pitch_radians, -.85, 1.2, .01)
    tweak_drag_f32("Player distance", &c.player_camera.distance, 3, 12, .05)
    tweak_drag_f32("Player height", &c.player_camera.height, 0, 10, .05)
    im.SeparatorText("Flight orbit")
    tweak_drag_f32("Flight yaw", &c.flight_orbit_yaw, -math.PI * 2, math.PI * 2, .01)
    tweak_drag_f32("Flight pitch", &c.flight_orbit_pitch, -.75, .75, .01)
}

tweak_draw_world :: proc(editor: ^Editor) {
    w := &editor.tweak.world
    if tweak_section("View distance and fog", true) {
        tweak_drag_f32("Far clip", &w.far_clip, 100, 50000, 10)
        tweak_drag_f32("Fog start", &w.fog_start, 0, 50000, 10)
        tweak_drag_f32("Fog end", &w.fog_end, 1, 50000, 10)
    }
    if tweak_section("Map ocean", true) {
        tweak_drag_f32("Map extent", &w.map_ocean_extent, 100, 50000, 10)
        im.InputScalar("Map divisions", im.DataType.S32, rawptr(&w.map_ocean_divisions), nil, nil, "%d")
        tweak_drag_f32("Map depth", &w.map_ocean_depth, 0, 100, .01)
    }
    if tweak_section("Editor ocean") {
        tweak_drag_f32("Editor extent", &w.editor_ocean_extent, 100, 50000, 10)
        im.InputScalar("Editor divisions", im.DataType.S32, rawptr(&w.editor_ocean_divisions), nil, nil, "%d")
        tweak_drag_f32("Editor depth", &w.editor_ocean_depth, 0, 100, .01)
    }
}

tweak_draw_particles :: proc(editor: ^Editor) {
    p := &editor.tweak.particles
    if tweak_section("General", true) {
        im.InputScalar("CPU seed", im.DataType.U32, rawptr(&p.cpu_seed), nil, nil, "%u")
        im.InputScalar("Vehicle seed", im.DataType.U32, rawptr(&p.vehicle_seed), nil, nil, "%u")
        im.InputScalar("Wing seed", im.DataType.U32, rawptr(&p.wing_seed), nil, nil, "%u")
    }
    if tweak_section("Ambient CPU particles", true) {
        tweak_drag_f32("CPU spawn rate", &p.cpu.spawn_rate, 0, 1000, 1)
        tweak_drag_f32("CPU origin radius", &p.cpu.origin_radius, 0, 20, .01)
        tweak_drag_f32("CPU radial speed", &p.cpu.radial_speed, 0, 20, .01)
        tweak_drag_f32("CPU radial variation", &p.cpu.radial_speed_variation, 0, 20, .01)
        tweak_drag_f32("CPU lift speed", &p.cpu.lift_speed, 0, 20, .01)
        tweak_drag_f32("CPU lift variation", &p.cpu.lift_speed_variation, 0, 20, .01)
        tweak_drag_f32("CPU lifetime", &p.cpu.lifetime, 0, 30, .01)
        tweak_drag_f32("CPU lifetime variation", &p.cpu.lifetime_variation, 0, 30, .01)
        tweak_drag_f32("CPU size", &p.cpu.size, 0, 2, .001)
        tweak_drag_f32("CPU size variation", &p.cpu.size_variation, 0, 2, .001)
        tweak_drag_f32("CPU gravity", &p.cpu.gravity, 0, 20, .01)
    }
    if tweak_section("Vehicle dust") {
        tweak_drag_f32("Dust spawn rate", &p.vehicle.dust_spawn_rate, 0, 500, 1)
        tweak_drag_f32("Dust speed divisor", &p.vehicle.dust_speed_divisor, .01, 200, .1)
        tweak_drag_f32("Dust steering divisor", &p.vehicle.dust_steering_divisor, .01, 200, .1)
        tweak_drag_f32("Dust handbrake bonus", &p.vehicle.dust_handbrake_bonus, 0, 5, .01)
        tweak_drag_f32("Dust max intensity", &p.vehicle.dust_max_intensity, 0, 10, .01)
        tweak_drag_f32("Dust spawn threshold", &p.vehicle.dust_spawn_threshold, 0, 2, .01)
        tweak_drag_f32("Dust contact spread", &p.vehicle.dust_contact_spread, 0, 5, .01)
        tweak_drag_f32("Dust height", &p.vehicle.dust_height, 0, 5, .01)
        tweak_drag_f32("Dust radial speed", &p.vehicle.dust_radial_speed, 0, 10, .01)
        tweak_drag_f32("Dust intensity speed", &p.vehicle.dust_intensity_speed, 0, 10, .01)
        tweak_drag_f32("Dust lift", &p.vehicle.dust_lift, 0, 10, .01)
        tweak_drag_f32("Dust lift variation", &p.vehicle.dust_lift_variation, 0, 10, .01)
        tweak_drag_f32("Dust lifetime", &p.vehicle.dust_lifetime, 0, 10, .01)
        tweak_drag_f32("Dust lifetime variation", &p.vehicle.dust_lifetime_variation, 0, 10, .01)
        tweak_drag_f32("Dust size", &p.vehicle.dust_size, 0, 2, .001)
        tweak_drag_f32("Dust intensity size", &p.vehicle.dust_intensity_size, 0, 2, .001)
        tweak_drag_f32("Dust lift size", &p.vehicle.dust_lift_size, 0, 2, .001)
        tweak_drag_f32("Dust gravity", &p.vehicle.dust_gravity, 0, 20, .01)
    }
    if tweak_section("Wing trails") {
        tweak_drag_f32("Trail airspeed start", &p.wing.airspeed_start, 0, 200, .1)
        tweak_drag_f32("Trail airspeed range", &p.wing.airspeed_range, .01, 200, .1)
        tweak_drag_f32("Trail wind strength", &p.wing.wind_strength, 0, 2, .001)
        tweak_drag_f32("Trail spawn rate", &p.wing.spawn_rate, 0, 500, 1)
        tweak_drag_f32("Trail forward speed", &p.wing.forward_speed, 0, 10, .01)
        tweak_drag_f32("Trail forward jitter", &p.wing.forward_jitter, 0, 2, .001)
        tweak_drag_f32("Trail wind velocity", &p.wing.wind_velocity, 0, 10, .01)
        tweak_drag_f32("Trail vertical jitter", &p.wing.vertical_jitter, 0, 2, .001)
        tweak_drag_f32("Trail lifetime", &p.wing.lifetime, 0, 10, .01)
        tweak_drag_f32("Trail lifetime variation", &p.wing.lifetime_variation, 0, 10, .01)
        tweak_drag_f32("Trail wind lifetime", &p.wing.wind_lifetime, 0, 2, .001)
        tweak_drag_f32("Trail size", &p.wing.size, 0, 2, .001)
        tweak_drag_f32("Trail strength size", &p.wing.strength_size, 0, 2, .001)
        tweak_drag_f32("Trail wind size", &p.wing.wind_size, 0, 2, .001)
        tweak_drag_f32("Trail curve", &p.wing.curve, 0, 5, .01)
        tweak_drag_f32("Trail curve variation", &p.wing.curve_variation, 0, 5, .01)
        tweak_drag_f32("Trail gravity", &p.wing.gravity, 0, 5, .01)
    }
    if tweak_section("GPU field") {
        im.DragFloat3("GPU center", &p.gpu.center, 1, -50000, 50000, "%.1f", im.SliderFlags_AlwaysClamp)
        tweak_drag_f32("GPU radius", &p.gpu.radius_min, 0, 100, .01)
        tweak_drag_f32("GPU radius range", &p.gpu.radius_range, 0, 100, .01)
        tweak_drag_f32("GPU cycle rate", &p.gpu.cycle_rate_min, 0, 10, .001)
        tweak_drag_f32("GPU cycle variation", &p.gpu.cycle_rate_range, 0, 10, .001)
        tweak_drag_f32("GPU drift", &p.gpu.drift, 0, 10, .01)
        tweak_drag_f32("GPU size", &p.gpu.size_min, 0, 2, .001)
        tweak_drag_f32("GPU size range", &p.gpu.size_range, 0, 2, .001)
        tweak_drag_f32("GPU fade", &p.gpu.fade, 0, 1, .01)
        im.InputScalar("GPU count", im.DataType.S32, rawptr(&p.gpu.count), nil, nil, "%d")
        im.DragFloat3("GPU color start", &p.gpu.color_start, .01, 0, 1, "%.2f", im.SliderFlags_AlwaysClamp)
        im.DragFloat3("GPU color end", &p.gpu.color_end, .01, 0, 1, "%.2f", im.SliderFlags_AlwaysClamp)
    }
}

tweak_draw_car :: proc(editor: ^Editor) {
    t := &editor.tweak.car
    if tweak_section("Driving", true) {
        tweak_drag_f32("Acceleration", &t.acceleration, 0, 100, .1)
        tweak_drag_f32("Brake", &t.brake, 0, 100, .1)
        tweak_drag_f32("Reverse acceleration", &t.reverse_acceleration, 0, 100, .1)
        tweak_drag_f32("Max forward", &t.max_forward, .1, 200, .1)
        tweak_drag_f32("Max reverse", &t.max_reverse, .1, 100, .1)
        tweak_drag_f32("Steering response", &t.steering_response, 0, 50, .1)
        tweak_drag_f32("Yaw response", &t.yaw_response, 0, 50, .1)
        tweak_drag_f32("Lateral grip", &t.lateral_grip, 0, 50, .1)
        tweak_drag_f32("Handbrake grip", &t.handbrake_grip, 0, 50, .1)
        tweak_drag_f32("Coast deceleration", &t.coast_deceleration, 0, 50, .1)
    }
    if tweak_section("Interaction") {
        tweak_drag_f32("Enter radius", &editor.tweak.car_vehicle.interaction_radius, 0, 20, .05)
        tweak_drag_f32("Exit distance", &editor.tweak.car_vehicle.exit_distance, 0, 20, .05)
        im.Checkbox("Locked", &editor.tweak.car_vehicle.locked)
    }
    if tweak_section("Diagnostics") {
        im.Text("Speed: %.2f", vehicles.car_drive_speed(editor.car_drive))
        im.Text("Yaw rate: %.2f", editor.car_drive.yaw_rate)
    }
}

tweak_draw_postale :: proc(editor: ^Editor) {
    a := &editor.tweak.postale_airframe
    if tweak_section("Flight model", true) {
        if im.Button("Reset active aircraft") do aircraft_reset(editor)
        if im.RadioButton("Current Aero", editor.postale.flight_model == .Current_Aero) {
            editor.postale.flight_model = .Current_Aero
        }
        im.SameLine()
        if im.RadioButton("Ace Arcade", editor.postale.flight_model == .Ace_Arcade) {
            editor.postale.flight_model = .Ace_Arcade
            editor.postale.ace_runtime = flight.default_ace_runtime(editor.postale.body, editor.postale.ace_tuning)
            editor.postale.ace_runtime.energy = .75
            editor.postale.ace_telemetry = {
                pace       = linalg.length(editor.postale.body.velocity),
                energy     = editor.postale.ace_runtime.energy,
                edge_state = editor.postale.ace_runtime.edge_state,
            }
        }
    }
    if tweak_section("Airframe", true) {
        im.Text("Layout: fixed wing (%d)", a.flight_layout)
        tweak_drag_f32("Mass kg", &a.mass_kg, 1, 50000, 1)
        tweak_drag_f32("Maximum gross mass kg", &a.maximum_gross_mass_kg, 1, 50000, 1)
        tweak_drag_f32("Wing area", &a.wing_area, .1, 500, .1)
        tweak_drag_f32("Lift scale", &a.lift_scale, 0, 10, .01)
        tweak_drag_f32("Drag scale", &a.drag_scale, 0, 10, .01)
        tweak_drag_f32("Parasitic drag area", &a.parasitic_drag_area, .01, 20, .01)
        tweak_drag_f32("Power per engine kw", &a.rated_power_per_engine_kw, 0, 5000, 1)
        tweak_drag_f32("Propeller efficiency", &a.propeller_efficiency, 0, 1, .01)
        tweak_drag_f32("Static thrust", &a.static_thrust_per_engine, 0, 100000, 10)
        tweak_drag_f32("Engine count", &a.engine_count, 1, 8, .1)
        tweak_drag_f32("Wing incidence deg", &a.wing_incidence_degrees, -30, 30, .1)
        tweak_drag_f32("Lift curve slope", &a.lift_curve_slope_per_degree, 0, 1, .001)
        tweak_drag_f32("Zero lift angle deg", &a.zero_lift_angle_degrees, -30, 30, .1)
        tweak_drag_f32("Critical angle deg", &a.critical_angle_degrees, 0, 90, .1)
        tweak_drag_f32("Negative critical angle deg", &a.negative_critical_angle_degrees, -90, 0, .1)
        tweak_drag_f32("Post stall angle deg", &a.post_stall_angle_degrees, 0, 120, .1)
        tweak_drag_f32("Post stall lift", &a.post_stall_lift_coefficient, 0, 2, .01)
        tweak_drag_f32("Induced drag", &a.induced_drag_factor, 0, 1, .001)
        tweak_drag_f32("Trim angle deg", &a.trim_angle_of_attack_degrees, -30, 30, .1)
        tweak_drag_f32("Pitch stability", &a.pitch_stability, 0, 1000000, 100)
        tweak_drag_f32("Pitch damping", &a.pitch_damping, 0, 1000000, 100)
        tweak_drag_f32("Roll stability", &a.roll_stability, 0, 1000000, 100)
        tweak_drag_f32("Roll damping", &a.roll_damping, 0, 1000000, 100)
        tweak_drag_f32("Yaw stability", &a.yaw_stability, 0, 1000000, 100)
        tweak_drag_f32("Yaw damping", &a.yaw_damping, 0, 1000000, 100)
        tweak_drag_f32("Pitch control", &a.pitch_control_scale, 0, 3, .01)
        tweak_drag_f32("Roll control", &a.roll_control_scale, 0, 3, .01)
        tweak_drag_f32("Yaw control", &a.yaw_control_scale, 0, 3, .01)
        im.Checkbox("Water capable", &a.water_capable)
        tweak_drag_f32("Planing start", &a.water_planing_start_speed, 0, 100, .1)
        tweak_drag_f32("Planing full", &a.water_planing_full_speed, 0, 100, .1)
        tweak_drag_f32("Planing reference", &a.water_planing_reference_speed, 0, 100, .1)
        tweak_drag_f32("Water plow drag", &a.water_plow_drag_scale, 0, 10, .01)
    }
    if tweak_section("Runtime modifiers") {
        tweak_drag_f32("Engine output", &editor.tweak.postale_runtime.engine_output, 0, 1, .01)
        tweak_drag_f32("Control authority", &editor.tweak.postale_runtime.control_authority, 0, 2, .01)
        tweak_drag_f32("Drag multiplier", &editor.tweak.postale_runtime.drag_multiplier, 0, 5, .01)
        im.Checkbox("Controls damaged", &editor.tweak.postale_runtime.controls_damaged)
    }
    if tweak_section("Safety") {
        tweak_drag_f32("Ground clearance", &editor.tweak.postale_tuning.ground_clearance, 0, 5, .01)
        tweak_drag_f32("Safe bank radians", &editor.tweak.postale_tuning.safe_bank_radians, 0, math.PI, .01)
        tweak_drag_f32(
            "Gear compression distance",
            &editor.tweak.postale_tuning.gear_compression_distance,
            .05,
            2,
            .01,
        )
        tweak_drag_f32("Gear damping ratio", &editor.tweak.postale_tuning.gear_damping_ratio, 0, 2, .01)
        tweak_drag_f32("Smooth landing load", &editor.tweak.postale_tuning.smooth_landing_load, 1, 10, .1)
        tweak_drag_f32("Hard landing load", &editor.tweak.postale_tuning.hard_landing_load, 1, 10, .1)
        tweak_drag_f32("Ultimate landing load", &editor.tweak.postale_tuning.ultimate_landing_load, 1, 15, .1)
        tweak_drag_f32("Safe exit speed", &editor.tweak.postale_tuning.safe_exit_speed, 0, 20, .1)
    }
    if tweak_section("Controls") {
        tweak_drag_f32("Throttle up rate", &editor.tweak.postale_tuning.throttle_up_rate, 0, 20, .01)
        tweak_drag_f32("Throttle down rate", &editor.tweak.postale_tuning.throttle_down_rate, 0, 20, .01)
        tweak_drag_f32("Pitch increase rate", &editor.tweak.postale_tuning.pitch_rate_increase, 0, 50, .01)
        tweak_drag_f32("Pitch decrease rate", &editor.tweak.postale_tuning.pitch_rate_decrease, 0, 50, .01)
        tweak_drag_f32("Roll increase rate", &editor.tweak.postale_tuning.roll_rate_increase, 0, 50, .01)
        tweak_drag_f32("Roll decrease rate", &editor.tweak.postale_tuning.roll_rate_decrease, 0, 50, .01)
        tweak_drag_f32("Yaw increase rate", &editor.tweak.postale_tuning.yaw_rate_increase, 0, 50, .01)
        tweak_drag_f32("Yaw decrease rate", &editor.tweak.postale_tuning.yaw_rate_decrease, 0, 50, .01)
        tweak_drag_f32("Flap response", &editor.tweak.postale_tuning.flap_response, 0, 20, .01)
        tweak_drag_f32("Flap auto throttle", &editor.tweak.postale_tuning.flap_auto_throttle, 0, 1, .01)
        tweak_drag_f32("Flap auto speed", &editor.tweak.postale_tuning.flap_auto_speed, 0, 200, .1)
    }
    if tweak_section("Ground and takeoff") {
        tweak_drag_f32("Ground brake", &editor.tweak.postale_tuning.ground_brake, 0, 20, .01)
        tweak_drag_f32("Ground coast", &editor.tweak.postale_tuning.ground_coast, 0, 20, .01)
        tweak_drag_f32("Ground steer fast", &editor.tweak.postale_tuning.ground_steer_fast, 0, 20, .01)
        tweak_drag_f32("Ground steer slow", &editor.tweak.postale_tuning.ground_steer_slow, 0, 20, .01)
        tweak_drag_f32("Takeoff throttle", &editor.tweak.postale_tuning.takeoff_throttle, 0, 1, .01)
        tweak_drag_f32("Takeoff speed scale", &editor.tweak.postale_tuning.takeoff_speed_scale, 0, 2, .01)
        tweak_drag_f32("Takeoff pitch", &editor.tweak.postale_tuning.takeoff_pitch, 0, 1, .01)
        tweak_drag_f32("Takeoff ground time", &editor.tweak.postale_tuning.takeoff_ground_time, 0, 2, .01)
    }
    if tweak_section("Propeller") {
        tweak_drag_f32("Propeller base rate", &editor.tweak.postale_tuning.propeller_base_rate, 0, 50, .01)
        tweak_drag_f32("Propeller throttle rate", &editor.tweak.postale_tuning.propeller_throttle_rate, 0, 100, .1)
    }
    if tweak_section("Diagnostics") {
        im.Text("Airspeed: %.2f", postale_game.selected_airspeed(&editor.postale))
        im.Text("AoA: %.2f deg", editor.postale.telemetry.angle_of_attack_degrees)
        im.Text("Stalling: %s", editor.postale.telemetry.is_stalling ? "yes" : "no")
    }
}

tweak_draw_presentation :: proc(editor: ^Editor) {
    p := &editor.tweak.presentation
    if tweak_section("Terrain materials", true) {
        im.ColorEdit4("Water", &p.terrain_water)
        im.ColorEdit4("Sand", &p.terrain_sand)
        im.ColorEdit4("Soil", &p.terrain_soil)
        im.ColorEdit4("Grass", &p.terrain_grass)
        tweak_drag_f32("Painted threshold", &p.painted_threshold, 0, 1, .01)
        tweak_drag_f32("Sand start", &p.sand_start, 0, 10, .01)
        tweak_drag_f32("Sand/soil blend", &p.land_blend, .01, 10, .01)
        tweak_drag_f32("Grass start", &p.grass_start, 0, 20, .01)
        tweak_drag_f32("Soil/grass blend", &p.grass_blend, .01, 20, .01)
    }
    if tweak_section("Lighting", true) {
        im.DragFloat3("Light direction", &p.light_direction, .01, -1, 1, "%.2f", im.SliderFlags_AlwaysClamp)
        tweak_drag_f32("Shade base", &p.shade_base, 0, 2, .01)
        tweak_drag_f32("Shade strength", &p.shade_strength, 0, 2, .01)
        tweak_drag_f32("Shade minimum", &p.shade_min, 0, 2, .01)
        tweak_drag_f32("Shade maximum", &p.shade_max, 0, 2, .01)
        tweak_drag_f32("Height shade", &p.height_shade, -1, 1, .001)
    }
}

tweak_draw_performance :: proc(editor: ^Editor) {
    when !dio.FLAME_GRAPH do return
    world_dynamic := world_buffer_total_size(world_renderer.vertex[:])
    world_static_vertices := world_buffer_total_size(world_renderer.static_vertex[:])
    world_static_indices := world_buffer_total_size(world_renderer.static_index[:])
    roads := world_buffer_total_size(world_renderer.road_vertex[:])
    foliage := world_buffer_total_size(world_renderer.foliage_vertex[:])
    grass := world_buffer_total_size(world_renderer.grass_instance[:])
    shadows := world_buffer_total_size(world_renderer.shadow_vertex[:])
    total := world_dynamic + world_static_vertices + world_static_indices + roads + foliage + grass + shadows
    im.SeparatorText("Geometry buffers - all frame slots")
    im.TextUnformatted(fmt.ctprintf("World dynamic: %M", world_dynamic))
    im.TextUnformatted(fmt.ctprintf("World static vertices: %M", world_static_vertices))
    im.TextUnformatted(fmt.ctprintf("World static indices: %M", world_static_indices))
    im.TextUnformatted(fmt.ctprintf("Roads: %M", roads))
    im.TextUnformatted(fmt.ctprintf("Foliage: %M", foliage))
    im.TextUnformatted(fmt.ctprintf("Grass: %M", grass))
    im.TextUnformatted(fmt.ctprintf("Shadows: %M", shadows))
    im.TextUnformatted(fmt.ctprintf("Total: %M", total))
    im.Separator()
    im.TextUnformatted("Frame instrumentation")
    dio.flame_graph_widget(&editor.flame_graph)
}

tweak_draw_lab_switcher :: proc(editor: ^Editor) {
    active_name := editor.active_lab_scene == "" ? "None" : editor.active_lab_scene
    if im.BeginCombo("Lab", fmt.ctprintf("%s", active_name)) {
        for &definition in LAB_SCENES {
            selected := editor.active_lab_scene == definition.name
            if im.Selectable(fmt.ctprintf("%s", definition.name), selected) {
                _ = lab_scene_load(editor, {definition = &definition})
            }
            if selected do im.SetItemDefaultFocus()
        }
        im.EndCombo()
    }
    if editor.active_lab_scene != "" {
        im.SameLine()
        if im.Button("Exit to main menu") do lab_scene_exit_to_main_menu(editor)
    }
}

tweak_page_select :: proc(label, searchable_text: cstring, page: Tweak_Page) -> bool {
    if !im.TextFilter_PassFilter(&tweak_filter, searchable_text) do return false
    if im.Selectable(label, tweak_selected_page == page) do tweak_selected_page = page
    return true
}

tweak_draw_navigation :: proc() {
    _ = im.TextFilter_Draw(&tweak_filter, "Search", -1)
    im.Spacing()
    environment_visible :=
        im.TextFilter_PassFilter(
            &tweak_filter,
            "Terrain brush sculpt smooth paint formations roads radius strength hardness sea level navigation project save load",
        ) ||
        im.TextFilter_PassFilter(
            &tweak_filter,
            "Weather Time atmosphere seed automatic clear windy storm cloud precipitation haze severity wind pause",
        ) ||
        im.TextFilter_PassFilter(&tweak_filter, "Ocean Fog world far clip map editor extent divisions depth") ||
        im.TextFilter_PassFilter(
            &tweak_filter,
            "Lighting Materials presentation water sand soil grass painted threshold blend direction shade",
        )
    if environment_visible do im.TextDisabled("ENVIRONMENT")
    _ = tweak_page_select(
        "Terrain",
        "Terrain brush sculpt smooth paint formations roads radius strength hardness sea level navigation project save load",
        .Terrain,
    )
    _ = tweak_page_select(
        "Weather & Time",
        "Weather Time atmosphere seed automatic clear windy storm cloud precipitation haze severity wind pause",
        .Weather_Time,
    )
    _ = tweak_page_select("Ocean & Fog", "Ocean Fog world far clip map editor extent divisions depth", .Ocean_Fog)
    _ = tweak_page_select(
        "Lighting & Materials",
        "Lighting Materials presentation water sand soil grass painted threshold blend direction shade",
        .Lighting_Materials,
    )
    im.Spacing()
    if im.TextFilter_PassFilter(
        &tweak_filter,
        "Mouse player movement speed acceleration drift boost jump gravity gait animation stride scurry body softness tail diagnostics",
    ) {
        im.TextDisabled("CHARACTERS")
    }
    _ = tweak_page_select(
        "Mouse",
        "Mouse player movement speed acceleration drift boost jump gravity gait animation stride scurry body softness tail diagnostics",
        .Mouse,
    )
    im.Spacing()
    vehicles_visible :=
        im.TextFilter_PassFilter(
            &tweak_filter,
            "Car driving acceleration brake reverse steering grip interaction diagnostics",
        ) ||
        im.TextFilter_PassFilter(
            &tweak_filter,
            "Postale aircraft flight model airframe lift drag thrust stability runtime safety controls ground takeoff propeller diagnostics",
        )
    if vehicles_visible do im.TextDisabled("VEHICLES")
    _ = tweak_page_select("Car", "Car driving acceleration brake reverse steering grip interaction diagnostics", .Car)
    _ = tweak_page_select(
        "Postale",
        "Postale aircraft flight model airframe lift drag thrust stability runtime safety controls ground takeoff propeller diagnostics",
        .Postale,
    )
    im.Spacing()
    if im.TextFilter_PassFilter(
        &tweak_filter,
        "Particles effects CPU ambient vehicle dust wing trails GPU seed spawn speed lift lifetime size gravity color",
    ) {
        im.TextDisabled("EFFECTS")
    }
    _ = tweak_page_select(
        "Particles",
        "Particles effects CPU ambient vehicle dust wing trails GPU seed spawn speed lift lifetime size gravity color",
        .Particles,
    )
    im.Spacing()
    if im.TextFilter_PassFilter(
        &tweak_filter,
        "Camera view editor player flight orbit yaw pitch distance height focus",
    ) {
        im.TextDisabled("VIEW")
    }
    _ = tweak_page_select("Camera", "Camera view editor player flight orbit yaw pitch distance height focus", .Camera)
    im.Spacing()
    if im.TextFilter_PassFilter(
        &tweak_filter,
        "Developer tools labs default map generation regenerate performance flame graph geometry buffers",
    ) {
        im.TextDisabled("TOOLS")
    }
    _ = tweak_page_select(
        "Developer",
        "Developer tools labs default map generation regenerate performance flame graph geometry buffers",
        .Developer,
    )
}

tweak_draw_developer :: proc(editor: ^Editor) {
    if tweak_section("Labs", true) do tweak_draw_lab_switcher(editor)
    if tweak_section("Default map generation") {
        im.TextWrapped("Replaces both islands, towns, roads, and marinas.")
        if im.Button("Regenerate Default Map") do im.OpenPopup("Regenerate default map?")
        if im.BeginPopupModal("Regenerate default map?", nil, {.AlwaysAutoResize}) {
            im.TextWrapped("This replaces both islands, towns, roads, and marinas.")
            im.Separator()
            if im.Button("Regenerate") {
                regenerate_default_map(editor)
                im.CloseCurrentPopup()
            }
            im.SameLine()
            if im.Button("Cancel") do im.CloseCurrentPopup()
            im.EndPopup()
        }
    }
    when dio.FLAME_GRAPH {
        if tweak_section("Performance") do tweak_draw_performance(editor)
    }
}

imgui_draw_tweaks :: proc(editor: ^Editor) {
    if editor == nil || !editor.tweak_panel_visible do return
    tweak_sync_from_editor(editor)
    // Set initial placement and size; ImGui persists later user changes.
    im.SetNextWindowPos({570, 150}, im.Cond.FirstUseEver)
    // Override any zero-sized geometry left by the old constraints once, then
    // leave the window freely resizable for the rest of the session.
    im.SetNextWindowSize({720, 620}, im.Cond.Once)
    if im.Begin("Adriatic Tweaks") {
        if im.Button("Save tweaks") do tweak_save_editor(editor)
        im.SameLine()
        if im.Button("Load tweaks") do tweak_load_editor(editor)
        im.SameLine()
        switch editor.tweak_status {
        case .Defaults:
            im.TextUnformatted("Defaults")
        case .Loaded:
            im.TextUnformatted("Loaded")
        case .Saved:
            im.TextUnformatted("Saved")
        case .Save_Failed:
            im.TextUnformatted("Save failed")
        }
        im.SameLine()
        im.TextDisabled("%s", TWEAK_FILE_PATH)
        if im.BeginChild("##tweak_navigation", {175, 0}, {.Borders, .ResizeX}) {
            tweak_draw_navigation()
        }
        im.EndChild()
        im.SameLine()
        if im.BeginChild("##tweak_content", {0, 0}) {
            switch tweak_selected_page {
            case .Terrain:
                im.SeparatorText("Terrain")
                tweak_draw_terrain(editor)
            case .Weather_Time:
                im.SeparatorText("Weather & Time")
                tweak_draw_atmosphere(editor)
            case .Ocean_Fog:
                im.SeparatorText("Ocean & Fog")
                tweak_draw_world(editor)
            case .Lighting_Materials:
                im.SeparatorText("Lighting & Materials")
                tweak_draw_presentation(editor)
            case .Mouse:
                im.SeparatorText("Mouse")
                tweak_draw_player(editor)
            case .Car:
                im.SeparatorText("Car")
                tweak_draw_car(editor)
            case .Postale:
                im.SeparatorText("Postale")
                tweak_draw_postale(editor)
            case .Particles:
                im.SeparatorText("Particles")
                tweak_draw_particles(editor)
            case .Camera:
                im.SeparatorText("Camera")
                tweak_draw_camera(editor)
            case .Developer:
                im.SeparatorText("Developer")
                tweak_draw_developer(editor)
            }
        }
        im.EndChild()
    }
    im.End()
    tweak_apply_to_editor(editor)
}
