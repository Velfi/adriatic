package main

import atmosphere "../packages/atmosphere"
import boats "../packages/boats"
import libellula_game "../packages/libellula"
import particle_systems "../packages/particles"
import postale_game "../packages/postale"
import rondine_game "../packages/rondine"
import story "../packages/story"
import surface_weather "../packages/surface_weather"
import terrain "../packages/terrain"
import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import "core:os"
import "core:time"
import canvas2d "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

run_initialize_editor_defaults :: proc(
    editor: ^Editor,
    request: ^Capture_Request,
    capture_mode: bool,
    capture_target: string,
) {
    editor.authoring_tool = .Sculpt
    editor.tool = .Raise
    editor.radius = 48
    editor.strength = .10
    editor.hardness = .5
    terrain_authoring_defaults(&editor.terrain_sculpt, editor.project.sea_level)
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
    editor.road_hover_edge = -1
    editor.road_hover_handle = -1
    editor.road_construction_mode = .Terrain_Route
    editor.road_construction_phase = .Idle
    editor.road_preview_first_edge = -1
    editor.road_preview_status = .Idle
    editor.road_preview_cell_x = -0x3fffffff
    editor.road_preview_cell_z = -0x3fffffff
    editor.road_snap_nodes = true
    editor.road_snap_edges = true
    editor.road_snap_grid = true
    editor.road_snap_angles = true
    editor.road_snap_tangents = true
    editor.road_snap_perpendiculars = true
    editor.road_drag_node = -1
    editor.road_drag_node_previous_selection = -1
    editor.road_drag_edge = -1
    editor.road_drag_handle = -1
    editor.road_width = 7
    editor.road_shoulder_width = 1.25
    editor.road_pavement = .Asphalt
    editor.architecture_brush_shape = .Circle
    editor.architecture_brush_preset = .Small
    editor.architecture_brush_strength = .55
    editor.architecture_brush_hardness = .45
    editor.building_generator_width = 12
    editor.building_generator_depth = 16
    editor.building_generator_height = 10
    editor.building_generator_density = .55
    editor.building_generator_variation = 1
    editor.marina_brush_radius = 60
    editor.farm_brush_radius = 64
    editor.wreck_brush_size = 330
    editor.climbing_leaf_brush_radius = terrain.BASE_CELL_SIZE * 3.0
    editor.climbing_leaf_brush_strength = .55
    editor.climbing_leaf_brush_hardness = .50
    editor.ruin_stamp_aegean = true
    mailbag_pouch_asset_init(editor)
    editor.greek_placement_mode = false
    editor.atmosphere = atmosphere.new(0x41c10)
    surface_weather.initialize(&editor.surface_weather, terrain.WORLD_SIZE_METERS * .5)
    if regime, weather_capture := capture_weather_regime(capture_target); weather_capture {
        atmosphere.set_weather_override(&editor.atmosphere, .Automatic)
        atmosphere.set_climate_regime(&editor.atmosphere, regime)
        editor.atmosphere.weather = atmosphere.regime_weather(regime)
        editor.atmosphere.paused = true
    }
    editor.boat_traffic = new_world_boat_traffic(&editor.project)
    editor.ocean_traffic = boats.new_ocean_traffic()
    editor.vehicle_effects = particle_systems.new_vehicle_effects(0x72b7e4a1)
    editor.player_terrain_effects = particle_systems.new_vehicle_effects(0xa21c94d7)
    editor.wing_trails = particle_systems.new_wing_trails(0x1f123bb5)
    editor.petal_effects = particle_systems.new_petal_effects(0x6a09e667)
    editor.tweak = tweak_default_state()
    editor.tweak_status = .Defaults
    editor.tweak_panel_visible = false
    editor.tweak_teleport_on_click = false
    editor.gameplay_options = gameplay_options_default()
    if capture_mode {
        if request != nil {
            editor.gameplay_options.visual_style = request.visual_style
            editor.gameplay_options.dither_mode = request.dither_mode
            photo_filter_defaults(&editor.photo_filter)
            editor.photo_filter.mode = request.photo_filter_mode
            photo_filter_load_active(&editor.photo_filter)
            photo_filter_capture_enabled = request.photo_filter_enabled
            if request.player_outline_enabled {
                editor.tweak.player_outline.enabled = true
                editor.tweak.player_outline.width = request.player_outline_width
                editor.tweak.player_outline.strength = request.player_outline_strength
            }
        }
        // Preserve the existing environment hook for capture automation.
        capture_style := os.get_env("ADRIATIC_CAPTURE_STYLE", context.temp_allocator)
        switch capture_style {
        case "dither":
            visual_style_set(editor, .Dither)
        case "standard":
            visual_style_set(editor, .Standard)
        }
        capture_dither := os.get_env("ADRIATIC_CAPTURE_DITHER", context.temp_allocator)
        switch capture_dither {
        case "bayer":
            editor.gameplay_options.visual_style = .Dither
            editor.gameplay_options.dither_mode = .Bayer
        case "blue":
            editor.gameplay_options.visual_style = .Dither
            editor.gameplay_options.dither_mode = .Blue_Noise
        case "matriax8":
            editor.gameplay_options.visual_style = .Dither
            editor.gameplay_options.dither_mode = .Matriax_8
        }
    }
    editor.mouse_fur = .Chestnut
    editor.mouse_pattern = .Solid
    editor.mouse_headgear = .Goggles
    editor.mouse_scarf_enabled = false
    editor.mouse_scarf_color = {194, 35, 47, 255}
}

run_initialize_gameplay_actors :: proc(editor: ^Editor) -> f32 {
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
    editor.rondine = rondine_game.new_runtime(rondine_spawn_position(editor))
    editor.attendant_position = attendant_spawn_position(editor, editor.libellula.vehicle.position)
    editor.gerta_position = gerta_spawn_position(editor)
    vehicles.aircraft_fleet_add(&editor.aircraft, .Postale, "Postale", &editor.postale.vehicle, true)
    when LIBELLULA_MK1_ENABLED {
        vehicles.aircraft_fleet_add(&editor.aircraft, .Libellula, "Libellula", &editor.libellula.vehicle, false)
    }
    vehicles.aircraft_fleet_add(&editor.aircraft, .Libellula_Mk2, "Libellula Mk2", &editor.libellula.vehicle, false)
    vehicles.aircraft_fleet_add(&editor.aircraft, .Rondine, "Rondine", &editor.rondine.vehicle, false)
    editor.postale_visible = true
    editor.libellula_visible = true
    editor.rondine_visible = false
    editor.rondine.vehicle.locked = true
    editor.libellula.vehicle.locked = true
    editor.car = vehicles.default_vehicle(car_spawn_position(editor))
    editor.car.interaction_radius = 2.2
    editor.car.exit_distance = 1.1
    editor.car.yaw_radians = -math.PI * .5
    // The shared physics character is created from editor.player.position.
    // Seed both gameplay representations first so its authoritative body does
    // not begin at the world origin in the ocean and overwrite the runway
    // spawn on the first physics step.
    player_spawn := runway_spawn_position(editor)
    player_place(editor, player_spawn, .Startup)
    if !gameplay_physics_create(editor) {
        fmt.eprintln("adriatic could not create the shared gameplay physics world")
    }
    return island_center
}

run_finish_startup :: proc(
    editor: ^Editor,
    state_loaded, show_loading_screen: bool,
    initial_width, initial_height: i32,
    postcard: canvas2d.Texture,
) {
    story.init_catalog(&editor.story_catalog)
    story.init_quest_catalog(&editor.story_quest_catalog)
    _ = story.ensure_quest_progress(&editor.story_state)
    if !state_loaded do control_hints_load(editor)
    if show_loading_screen {
        draw_startup_loading_screen(initial_width, initial_height, 1, "Welcome to Adriatic", postcard)
        editor.main_menu_active = true
        editor.main_menu_focus = 0
        menu_scene_set(editor, .Closed)
        set_pointer_locked(false)
    }
}

run_hot_reload_paths :: proc() -> (library_path, state_path: string, library_mtime: i64) {
    when HOT_RELOAD {
        library_path = os.get_env(HOT_LIBRARY_ENV, context.temp_allocator)
        state_path = os.get_env("ADRIATIC_HOT_STATE", context.temp_allocator)
        if library_path != "" {
            if modified, err := os.modification_time_by_path(library_path); err == nil {
                library_mtime = time.time_to_unix_nano(modified)
            }
        }
    }
    return
}
