package main

import atmosphere "../packages/atmosphere"
import back "../packages/back"
import boats "../packages/boats"
import chase_camera "../packages/chase_camera"
import dialogue "../packages/dialogue"
import dio "../packages/dio"
import engine_sound "../packages/engine_sound"
import flight "../packages/flight"
import fog_field "../packages/fog_field"
import game_input "../packages/game_input"
import harbor "../packages/harbor"
import hot_abi "../packages/hot_abi"
import libellula_game "../packages/libellula"
import ocean_audio "../packages/ocean_audio"
import particle_systems "../packages/particles"
import postale_game "../packages/postale"
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
import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:time"
import sdl "vendor:sdl3"
import canvas2d "zelda_engine:canvas2d"
import physics "zelda_engine:physics"

adriatic_run :: proc(
    persistent_canvas_state: rawptr,
    args: []string = os.args,
    request: ^Capture_Request = nil,
    startup_started_at: time.Tick = {},
) -> hot_abi.Run_Result {
    startup_failed = false
    effective_startup_started_at := startup_started_at
    if effective_startup_started_at == (time.Tick{}) {
        effective_startup_started_at = time.tick_now()
    }
    startup_timings := Startup_Timings {
        started_at = effective_startup_started_at,
        checkpoint = effective_startup_started_at,
    }
    tracking: back.Tracking_Allocator
    back.tracking_allocator_init(&tracking, context.allocator)
    defer back.tracking_allocator_destroy(&tracking)
    context.allocator = back.tracking_allocator(&tracking)
    defer back.tracking_allocator_print_results(&tracking)

    first_start := persistent_canvas_state == nil
    canvas2d.SetPersistentState(persistent_canvas_state)
    assert(canvas2d.SetRendererDescriptor(ADRIATIC_RENDERER_DESCRIPTOR))
    benchmark_requested := len(args) >= 2 && args[1] == "--benchmark"
    if benchmark_requested && len(args) < 9 {
        fmt.eprintln(
            "usage: adriatic --benchmark <scenario> <warmup_frames> <sample_frames> <window_width> <window_height> <world_width> <world_height>",
        )
        return .Quit
    }
    benchmark_mode := benchmark_requested && len(args) >= 9
    instrument_duration_seconds: f64
    instrument_window_width, instrument_window_height := 1280, 720
    instrument_world_width, instrument_world_height := ADRIATIC_WORLD_WIDTH, ADRIATIC_WORLD_HEIGHT
    if len(args) >= 3 && args[1] == "--instrument-seconds" {
        parsed, ok := strconv.parse_f64(args[2])
        if ok do instrument_duration_seconds = max(parsed, 0)
        if len(args) >= 7 {
            parsed_int, parsed_ok := strconv.parse_int(args[3])
            if parsed_ok do instrument_window_width = clamp(int(parsed_int), 320, 7680)
            parsed_int, parsed_ok = strconv.parse_int(args[4])
            if parsed_ok do instrument_window_height = clamp(int(parsed_int), 240, 4320)
            parsed_int, parsed_ok = strconv.parse_int(args[5])
            if parsed_ok do instrument_world_width = parsed_int == 0 ? 0 : clamp(int(parsed_int), 320, 7680)
            parsed_int, parsed_ok = strconv.parse_int(args[6])
            if parsed_ok do instrument_world_height = parsed_int == 0 ? 0 : clamp(int(parsed_int), 180, 4320)
        }
    }
    loading_preview_mode := len(args) >= 3 && args[1] == "--loading-preview"
    loading_preview_output := loading_preview_mode ? args[2] : ""
    loading_lab_mode := len(args) >= 3 && args[1] == "--lab" && args[2] == "loading-screen"
    requested_map_path := ""
    if len(args) >= 3 && args[1] == "--map" do requested_map_path = args[2]
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
    flags := canvas2d.ConfigFlags{.WINDOW_RESIZABLE}
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
    if capture_kind == .Rock_Lab do capture_lab_name = "rock"
    if capture_kind == .Screen_Pops_Lab do capture_lab_name = "screen-pops"
    if capture_wildflower_lab_mode do capture_lab_name = "wildflower"
    if capture_kind == .Rainbow_Lab do capture_lab_name = "rainbow"
    if capture_kind == .Boat_Lab do capture_lab_name = "boat"
    if capture_kind == .Boid_Lab do capture_lab_name = "boid"
    if capture_kind == .Car do capture_lab_name = "car"
    if capture_kind == .Car_Generator_Lab do capture_lab_name = "car-generator"
    if capture_kind == .Patio_Lab do capture_lab_name = "patio"
    if capture_kind == .Garden_Lab do capture_lab_name = "garden"
    if capture_kind == .Plant_Generator_Lab do capture_lab_name = "plant-generator"
    if capture_kind == .Leaf_Generator_Lab do capture_lab_name = "leaf-generator"
    if capture_kind == .Flower_Generator_Lab do capture_lab_name = "flower-generator"
    if capture_kind == .Window_Generator_Lab do capture_lab_name = "window-generator"
    if capture_kind == .Bridge_Generator_Lab do capture_lab_name = "bridge-generator"
    if capture_kind == .Fountain_Generator_Lab do capture_lab_name = "fountain-generator"
    if capture_kind == .Cemetery_Generator_Lab do capture_lab_name = "cemetery-generator"
    if capture_kind == .Estuary_Delta_Lab do capture_lab_name = "estuary-delta"
    if capture_kind == .Rocky_Beach_Lab do capture_lab_name = "coastal-ecology"
    if capture_kind == .Windmill_Generator_Lab do capture_lab_name = "windmill-generator"
    if capture_kind == .Hero_Building_Lab do capture_lab_name = "hero-building"
    if capture_kind == .Lighthouse_Lab do capture_lab_name = "lighthouse"
    if capture_kind == .Mouse_Gait_Lab do capture_lab_name = "mouse-gait"
    if capture_kind == .Mouse_Theater do capture_lab_name = "mouse-theater"
    if capture_kind == .Rondine_Movement_Lab do capture_lab_name = "rondine-movement"
    if capture_kind == .Aircraft_Transform_Lab do capture_lab_name = "aircraft-transform"
    if capture_kind == .Markov_Wreck do capture_lab_name = "markov-wreck"
    if capture_kind == .Markov_Marina do capture_lab_name = "markov-marina"
    if capture_kind == .Markov_Farmland do capture_lab_name = "markov-farmland"
    if capture_kind == .Ruins_Lab do capture_lab_name = "ruins"
    capture_lab_mode := capture_lab_name != ""
    capture_map_mode =
        capture_map_mode ||
        capture_grass_wind_mode ||
        capture_wildflower_lab_mode ||
        capture_markov_town_mode ||
        capture_kind == .Screen_Pops_Lab ||
        capture_kind == .Rainbow_Lab ||
        capture_kind == .Shadow_Lab ||
        capture_kind == .Rock_Lab ||
        capture_kind == .Boat_Lab ||
        capture_kind == .Boid_Lab ||
        capture_kind == .Car_Generator_Lab ||
        capture_kind == .Patio_Lab ||
        capture_kind == .Garden_Lab ||
        capture_kind == .Plant_Generator_Lab ||
        capture_kind == .Leaf_Generator_Lab ||
        capture_kind == .Flower_Generator_Lab ||
        capture_kind == .Window_Generator_Lab ||
        capture_kind == .Bridge_Generator_Lab ||
        capture_kind == .Fountain_Generator_Lab ||
        capture_kind == .Cemetery_Generator_Lab ||
        capture_kind == .Estuary_Delta_Lab ||
        capture_kind == .Rocky_Beach_Lab ||
        capture_kind == .Windmill_Generator_Lab ||
        capture_kind == .Hero_Building_Lab ||
        capture_kind == .Lighthouse_Lab ||
        capture_kind == .Mouse_Gait_Lab ||
        capture_kind == .Mouse_Theater ||
        capture_kind == .Rondine_Movement_Lab ||
        capture_kind == .Markov_Wreck ||
        capture_kind == .Markov_Marina ||
        capture_kind == .Markov_Farmland ||
        capture_kind == .Ruins_Lab
    capture_target := request != nil ? request.target : (capture_mode && len(args) >= 4 ? args[3] : "")
    clean_settlement_capture := false
    CLEAN_SETTLEMENT_CAPTURE_PREFIX :: "clean-"
    if capture_markov_town_mode &&
       len(capture_target) >= len(CLEAN_SETTLEMENT_CAPTURE_PREFIX) &&
       capture_target[:len(CLEAN_SETTLEMENT_CAPTURE_PREFIX)] == CLEAN_SETTLEMENT_CAPTURE_PREFIX {
        clean_settlement_capture = true
        capture_target = capture_target[len(CLEAN_SETTLEMENT_CAPTURE_PREFIX):]
    }
    capture_output := request != nil ? request.output_path : (capture_mode && len(args) >= 3 ? args[2] : "")
    showcase_target := showcase_interactive_mode ? (len(args) >= 3 ? args[2] : "") : capture_target
    capture_player_mode := capture_kind == .Map && capture_target != ""
    if capture_mode do flags += {.WINDOW_NOT_FOCUSABLE}
    if loading_preview_mode do flags += {.WINDOW_NOT_FOCUSABLE}
    canvas2d.SetConfigFlags(flags)
    canvas2d.SetWorldRenderSize(
        u32(
            benchmark_mode ? benchmark_world_width : instrument_duration_seconds > 0 ? instrument_world_width : ADRIATIC_WORLD_WIDTH,
        ),
        u32(
            benchmark_mode ? benchmark_world_height : instrument_duration_seconds > 0 ? instrument_world_height : ADRIATIC_WORLD_HEIGHT,
        ),
    )
    initial_width := i32(
        benchmark_mode ? benchmark_window_width : instrument_duration_seconds > 0 ? instrument_window_width : 1280,
    )
    initial_height := i32(
        benchmark_mode ? benchmark_window_height : instrument_duration_seconds > 0 ? instrument_window_height : 720,
    )
    if capture_kind == .Narrow do initial_width = 1000
    if capture_kind == .Compact do initial_width = 760
    if capture_target == "quest-log-480" {
        initial_width = 854
        initial_height = 480
    }
    if request != nil && request.window_width > 0 do initial_width = i32(request.window_width)
    if request != nil && request.window_height > 0 do initial_height = i32(request.window_height)
    startup_timings.config_ms = startup_checkpoint(&startup_timings)
    _ = canvas2d.SetBodyFontPath("assets/fonts/NotoSans-Regular.ttf")
    _ = canvas2d.SetDisplayFontPath("assets/fonts/NotoSerif-Regular.ttf")
    unicode_fallbacks := [?]cstring {
        "assets/fonts/fallback/NotoSansArabic-Regular.ttf",
        "assets/fonts/fallback/NotoSansHebrew-Regular.ttf",
        "assets/fonts/fallback/NotoSansDevanagari-Regular.ttf",
        "assets/fonts/fallback/NotoSansBengali-Regular.ttf",
        "assets/fonts/fallback/NotoSansGurmukhi-Regular.ttf",
        "assets/fonts/fallback/NotoSansGujarati-Regular.ttf",
        "assets/fonts/fallback/NotoSansOriya-Regular.ttf",
        "assets/fonts/fallback/NotoSansTamil-Regular.ttf",
        "assets/fonts/fallback/NotoSansTelugu-Regular.ttf",
        "assets/fonts/fallback/NotoSansKannada-Regular.ttf",
        "assets/fonts/fallback/NotoSansMalayalam-Regular.ttf",
        "assets/fonts/fallback/NotoSansSinhala-Regular.ttf",
        "assets/fonts/fallback/NotoSansThai-Regular.ttf",
        "assets/fonts/fallback/NotoSansLao-Regular.ttf",
        "assets/fonts/fallback/NotoSansArmenian-Regular.ttf",
        "assets/fonts/fallback/NotoSansGeorgian-Regular.ttf",
        "assets/fonts/fallback/NotoSansEthiopic-Regular.ttf",
        "assets/fonts/fallback/NotoSansSymbols2-Regular.ttf",
        "assets/fonts/fallback/NotoEmoji-Regular.ttf",
    }
    for path in unicode_fallbacks {
        _ = canvas2d.AddBodyFontFallbackPath(path)
        _ = canvas2d.AddDisplayFontFallbackPath(path)
    }
    if !canvas2d.InitWindow(initial_width, initial_height, "Adriatic — Clipmap Terrain Authoring") {
        fmt.eprintln("canvas window initialization failed")
        startup_failed = true
        canvas2d.DestroyPersistentState()
        return .Quit
    }
    startup_timings.window_ms = startup_checkpoint(&startup_timings)
    show_loading_screen := SHOW_STARTUP_MENU && first_start && !capture_mode && !benchmark_mode
    postcard: canvas2d.Texture
    needs_postcard := loading_lab_mode || loading_preview_mode || (!capture_mode && !benchmark_mode)
    if needs_postcard {
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
        postcard = canvas2d.LoadTexture(loading_postcard_path(postcard_period))
        if !postcard.ready {
            fmt.eprintln("loading postcard texture failed")
            startup_failed = true
            return .Quit
        }
    }
    if loading_lab_mode {
        defer canvas2d.CloseWindow()
        for !canvas2d.WindowShouldClose() {
            draw_startup_loading_screen(initial_width, initial_height, .62, "Wish you were here...", postcard)
        }
        return .Quit
    }
    if loading_preview_mode {
        defer canvas2d.CloseWindow()
        for preview_frame in 0 ..< 33 {
            draw_startup_loading_screen(initial_width, initial_height, .62, "Raising the islands...", postcard)
            if preview_frame == 2 do canvas2d.TakeScreenshot(fmt.ctprintf("%s", loading_preview_output))
        }
        return .Quit
    }
    if show_loading_screen {
        draw_startup_loading_screen(initial_width, initial_height, .04, "Opening the harbor...", postcard)
    }
    reload_requested := false
    defer if !reload_requested do canvas2d.DestroyPersistentState()
    wind_sound: wind_audio.Runtime
    wind_audio_ready := !capture_mode && !benchmark_mode
    if wind_audio_ready do wind_sound.synth = wind_audio.new_synth()
    ocean_sound: ocean_audio.Runtime
    ocean_audio_ready := !capture_mode && !benchmark_mode
    if ocean_audio_ready do ocean_sound.synth = ocean_audio.new_synth()
    spray_sound: spray_audio.Runtime
    spray_audio_ready := !capture_mode && !benchmark_mode
    if spray_audio_ready do spray_sound.synth = spray_audio.new_synth()
    if show_loading_screen {
        draw_startup_loading_screen(initial_width, initial_height, .20, "Tuning the sea and wind...", postcard)
    }
    editor := new(Editor)
    editor.menu_scene_stack = scene_stack.new(
        scene_stack.Context{data = rawptr(editor)},
        scene_stack.default_transition(0),
    )
    defer free(editor)
    defer scene_stack.destroy(&editor.menu_scene_stack)
    defer fixture_notes_flush_autosave(editor)
    cliff_rock_assets_init()
    defer cliff_rock_assets_destroy()
    defer fixture_migration_result_dispose(&editor.fixture_owner)
    defer attendant_dialogue_definition_release(editor)
    defer structure_storage_destroy(editor)
    defer lab_scene_destroy_active(editor)
    defer dio.flame_graph_destroy(&editor.flame_graph)
    defer garden_lab_destroy_lsystem()
    defer plant_generator_destroy()
    defer mailbag_pouch_asset_destroy(editor)
    story.init_catalog(&editor.story_catalog)
    story.init_quest_catalog(&editor.story_quest_catalog)
    _ = story.ensure_quest_progress(&editor.story_state)
    // Keep one reliable SDL stream until ambient synthesis joins the master mixer.
    engine_audio_ready := !capture_mode && !benchmark_mode && engine_sound.open(&editor.engine_audio)
    engine_audio_stream := editor.engine_audio.stream
    defer if engine_audio_ready do engine_sound.close(&editor.engine_audio)
    fmt.eprintf(
        "audio init: ready=%v stream=%v device=%d paused=%v gain=%.3f error=%s\n",
        engine_audio_ready,
        editor.engine_audio.stream != nil,
        editor.engine_audio.stream != nil ? sdl.GetAudioStreamDevice(editor.engine_audio.stream) : 0,
        editor.engine_audio.stream != nil ? sdl.AudioStreamDevicePaused(editor.engine_audio.stream) : true,
        editor.engine_audio.stream != nil ? sdl.GetAudioStreamGain(editor.engine_audio.stream) : 0,
        sdl.GetError(),
    )
    startup_timings.audio_ms = startup_checkpoint(&startup_timings)
    ambient_mix := Ambient_Audio_Mix{&wind_sound, &ocean_sound, &spray_sound}
    if engine_audio_ready {
        editor.engine_audio.aux_mix = ambient_audio_mix
        editor.engine_audio.aux_userdata = &ambient_mix
    }
    vehicle_paint_history_init(editor)
    defer fixture_editor_paint_history_destroy(editor)
    when LIBELLULA_MK1_ENABLED {
        vehicles.libellula_mesh_init(&editor.libellula_visual_mesh)
        defer vehicles.libellula_mesh_destroy(&editor.libellula_visual_mesh)
    }
    vehicles.libellula_mesh_init(&editor.libellula_mk2_visual_mesh)
    defer vehicles.libellula_mesh_destroy(&editor.libellula_mk2_visual_mesh)
    when LIBELLULA_MK1_ENABLED {
        vehicles.libellula_mesh_init(&editor.libellula_base_mesh)
        defer vehicles.libellula_mesh_destroy(&editor.libellula_base_mesh)
    }
    vehicles.libellula_mesh_init(&editor.libellula_mk2_base_mesh)
    defer vehicles.libellula_mesh_destroy(&editor.libellula_mk2_base_mesh)
    when LIBELLULA_MK1_ENABLED {
        vehicles.libellula_mesh_build(&editor.libellula_base_mesh)
        vehicles.libellula_mesh_copy(&editor.libellula_visual_mesh, &editor.libellula_base_mesh)
    }
    mk2_mesh_cache_path, mk2_mesh_cache_path_ok := vehicle_mesh_cache_path(context.temp_allocator)
    mk2_mesh_cache_hit :=
        mk2_mesh_cache_path_ok && vehicle_mesh_cache_load(&editor.libellula_mk2_base_mesh, mk2_mesh_cache_path)
    if !mk2_mesh_cache_hit {
        vehicles.libellula_mk2_mesh_build(&editor.libellula_mk2_base_mesh)
        if mk2_mesh_cache_path_ok {
            _ = vehicle_mesh_cache_store(&editor.libellula_mk2_base_mesh, mk2_mesh_cache_path)
        }
    }
    fmt.eprintf("vehicle mesh cache: libellula-mk2 source=%s\n", mk2_mesh_cache_hit ? "disk" : "generated")
    vehicles.libellula_mesh_copy(&editor.libellula_mk2_visual_mesh, &editor.libellula_mk2_base_mesh)
    editor.postale_base_mesh = new(vehicles.Aircraft_Mesh)
    defer free(editor.postale_base_mesh)
    postale_cache_path, postale_cache_path_ok := aircraft_mesh_cache_path(
        "postale",
        POSTALE_MESH_CACHE_VERSION,
        context.temp_allocator,
    )
    postale_cache_hit :=
        postale_cache_path_ok &&
        aircraft_mesh_cache_load(editor.postale_base_mesh, postale_cache_path, POSTALE_MESH_CACHE_VERSION)
    if !postale_cache_hit {
        free(editor.postale_base_mesh)
        editor.postale_base_mesh = vehicles.postale_mesh()
        vehicles.mesh_generate_smooth_normals(editor.postale_base_mesh)
        if postale_cache_path_ok {
            _ = aircraft_mesh_cache_store(editor.postale_base_mesh, postale_cache_path, POSTALE_MESH_CACHE_VERSION)
        }
    }
    editor.car_base_mesh = new(vehicles.Aircraft_Mesh)
    defer free(editor.car_base_mesh)
    car_cache_path, car_cache_path_ok := aircraft_mesh_cache_path(
        "car",
        CAR_MESH_CACHE_VERSION,
        context.temp_allocator,
    )
    car_cache_hit :=
        car_cache_path_ok && aircraft_mesh_cache_load(editor.car_base_mesh, car_cache_path, CAR_MESH_CACHE_VERSION)
    if !car_cache_hit {
        free(editor.car_base_mesh)
        editor.car_base_mesh = vehicles.simple_car_mesh()
        vehicles.mesh_generate_smooth_normals(editor.car_base_mesh)
        if car_cache_path_ok {
            _ = aircraft_mesh_cache_store(editor.car_base_mesh, car_cache_path, CAR_MESH_CACHE_VERSION)
        }
    }
    fmt.eprintf(
        "vehicle mesh cache: postale=%s car=%s\n",
        postale_cache_hit ? "disk" : "generated",
        car_cache_hit ? "disk" : "generated",
    )
    startup_timings.meshes_ms = startup_checkpoint(&startup_timings)
    if show_loading_screen {
        draw_startup_loading_screen(initial_width, initial_height, .42, "Preparing aircraft and boats...", postcard)
    }
    editor.libellula_projected_faces = make(
        [dynamic]Projected_Aircraft_Face,
        0,
        vehicles.LIBELLULA_MESH_TRIANGLE_CAPACITY,
    )
    defer delete(editor.libellula_projected_faces)
    map_path := requested_map_path != "" ? requested_map_path : DEFAULT_MAP_ARTIFACT_PATH
    map_source := "generated"
    map_load_started_at := time.tick_now()
    use_baked_map := !capture_mode && !interactive_lab_mode && !benchmark_mode
    map_loaded := false
    if use_baked_map {
        artifact, map_error, map_read := map_artifact_read(map_path)
        if map_read {
            apply_error: Map_Artifact_Error
            apply_error, map_loaded = map_artifact_apply(editor, artifact)
            map_artifact_destroy(artifact)
            if !map_loaded do map_error = apply_error
            if map_loaded do map_source = "baked"
        }
        if !map_loaded {
            fmt.eprintf(
                "map load failed: path=%s error=%v %s; bake with: build/dev/adriatic map bake %s\n",
                map_path,
                map_error.kind,
                map_error.message,
                map_path,
            )
            map_artifact_error_dispose(&map_error)
            if !MAP_DEVELOPMENT_FALLBACK {
                fmt.eprintln("release startup requires a valid baked map")
                startup_failed = true
                return .Quit
            }
        }
    }
    if !map_loaded {
        terrain.init_project(&editor.project)
        editor.terrain_revision = 1
        editor.default_map_regeneration_seeds = terrain.DEFAULT_ISLAND_SEEDS
        if !capture_mode &&
           !interactive_lab_mode &&
           (!benchmark_mode ||
                   benchmark_scenario == "editor" ||
                   benchmark_scenario == "terrain_edit" ||
                   benchmark_scenario == "formation_edit") {
            seed_default_island_marinas(editor)
            seed_default_island_towns(editor)
        }
    }
    startup_timings.map_load_ms = startup_elapsed_ms(map_load_started_at, time.tick_now())
    startup_timings.terrain_ms = startup_checkpoint(&startup_timings)
    if show_loading_screen {
        draw_startup_loading_screen(initial_width, initial_height, .62, "Raising the islands...", postcard)
    }
    run_initialize_editor_defaults(editor, request, capture_mode, capture_target)
    if !capture_mode {
        _ = mouse_preference_load(editor)
        // Persist final values on every exit, including window close and hot reload;
        // preference durability must not depend on a particular menu input path.
        defer {
            if !mouse_preference_save(editor) {
                fmt.eprintln("adriatic could not save gameplay preferences")
            }
        }
    }
    crunchiness_apply(editor.gameplay_options.crunchiness)
    anti_aliasing_apply(editor.gameplay_options.anti_aliasing)
    dither_apply(editor)
    ui_theme_set_mode(editor.gameplay_options.theme_mode)
    editor.runtime_input = game_input.default_state()
    editor.vehicle_paint_tool_icons = canvas2d.LoadTexture("assets/icons/control-hints/keyboard-mouse.png")
    if !editor.vehicle_paint_tool_icons.ready {
        fmt.eprintln("vehicle paint tool icon atlas failed to load")
    }
    editor.authoring_tool_atlas = canvas2d.LoadTexture("assets/textures/ui/authoring-tools-atlas.png")
    if !editor.authoring_tool_atlas.ready {
        fmt.eprintln("authoring tool icon atlas failed to load")
    }
    editor.tarot_atlas = canvas2d.LoadTexture("assets/textures/ui/tarot-atlas-v4.png")
    if !editor.tarot_atlas.ready {
        fmt.eprintln("tarot card atlas failed to load")
    }
    editor.photo_filter_media_atlas = canvas2d.LoadTexture("assets/textures/photo_filters/clean-room-media-atlas.png")
    editor.photo_filter_lut_atlas = canvas2d.LoadTexture("assets/textures/photo_filters/clean-room-lut-atlas.png")
    if editor.photo_filter_media_atlas.ready && editor.photo_filter_lut_atlas.ready {
        canvas2d.SetWorldPostAuxTextures(editor.photo_filter_media_atlas, editor.photo_filter_lut_atlas)
    } else {
        fmt.eprintln("photo filter auxiliary atlases failed to load")
    }
    control_hints_load(editor)
    _ = vehicle_paint_load(editor)
    island_center := run_initialize_gameplay_actors(editor)
    car_physics_create(editor)
    startup_timings.physics_ms = startup_checkpoint(&startup_timings)
    if show_loading_screen {
        draw_startup_loading_screen(initial_width, initial_height, .78, "Setting the world in motion...", postcard)
    }
    defer gameplay_physics_destroy(editor)
    defer car_physics_destroy(editor)
    defer markov_marina_buoy_physics_destroy(editor)
    editor.car_trailer_attached = true
    editor.car_trailer_position = editor.car.position
    editor.car_trailer_yaw = editor.car.yaw_radians
    run_config := Run_Config {
        request                         = request,
        benchmark_mode                  = benchmark_mode,
        benchmark_scenario              = benchmark_scenario,
        capture_kind                    = capture_kind,
        capture_mode                    = capture_mode,
        capture_editor_mode             = capture_editor_mode,
        legacy_shadow_lab_mode          = legacy_shadow_lab_mode,
        capture_sky_mode                = capture_sky_mode,
        capture_map_mode                = capture_map_mode,
        capture_flight_mode             = capture_flight_mode,
        capture_car_mode                = capture_car_mode,
        capture_vehicle_showcase_mode   = capture_vehicle_showcase_mode,
        capture_gameplay_mode           = capture_gameplay_mode,
        capture_road_mode               = capture_road_mode,
        capture_road_dust_mode          = capture_road_dust_mode,
        capture_road_grip_mode          = capture_road_grip_mode,
        capture_terrain_grip_mode       = capture_terrain_grip_mode,
        capture_building_mode           = capture_building_mode,
        capture_story_meeting_mode      = capture_story_meeting_mode,
        capture_foliage_mode            = capture_foliage_mode,
        capture_foliage_forest_mode     = capture_foliage_forest_mode,
        capture_foliage_motion_mode     = capture_foliage_motion_mode,
        capture_foliage_golden_mode     = capture_foliage_golden_mode,
        capture_foliage_low_mode        = capture_foliage_low_mode,
        capture_foliage_understory_mode = capture_foliage_understory_mode,
        capture_foliage_stress_mode     = capture_foliage_stress_mode,
        capture_grass_wind_mode         = capture_grass_wind_mode,
        capture_markov_town_mode        = capture_markov_town_mode,
        capture_lab_mode                = capture_lab_mode,
        capture_lab_name                = capture_lab_name,
        capture_target                  = capture_target,
        clean_settlement_capture        = clean_settlement_capture,
        interactive_lab_mode            = interactive_lab_mode,
        interactive_lab_request         = interactive_lab_request,
    }
    if !run_prepare_capture_world(editor, &run_config) do return .Quit
    hot_library_path, hot_state_path, hot_library_mtime := run_hot_reload_paths()
    state_loaded := false
    world_renderer_attach(editor)
    startup_timings.renderer_ms = startup_checkpoint(&startup_timings)
    if show_loading_screen {
        draw_startup_loading_screen(initial_width, initial_height, .92, "Lighting the coast...", postcard)
    }
    defer world_renderer_destroy()
    run_prepare_gameplay_capture(editor, &run_config)
    run_config.capture_paint_mode = capture_paint_mode
    run_config.vehicle_showcase_mode = vehicle_showcase_mode
    run_config.showcase_target = showcase_target
    run_config.island_center = island_center
    if !run_prepare_showcase(editor, &run_config) do return .Quit
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
    if state_loaded && editor.lab.kind != .Dunes &&
       !capture_mode &&
       !interactive_lab_mode &&
       (!benchmark_mode ||
               benchmark_scenario == "editor" ||
               benchmark_scenario == "terrain_edit" ||
               benchmark_scenario == "formation_edit") {
        seed_default_island_marinas(editor)
    }
    if state_loaded {
        hot_state_rebind_engine_audio(editor, engine_audio_stream, ambient_audio_mix, &ambient_mix)
    }
    run_finish_startup(editor, state_loaded, show_loading_screen, initial_width, initial_height, postcard)
    startup_timings.ready_ms = startup_checkpoint(&startup_timings)
    capture_frame :=
        capture_flight_mode || capture_player_mode || capture_kind == .Screen_Pops_Lab || capture_kind == .Shadow_Lab || capture_kind == .Rock_Lab || capture_kind == .Boat_Lab || capture_kind == .Car_Generator_Lab || capture_kind == .Patio_Lab || capture_kind == .Garden_Lab || capture_kind == .Plant_Generator_Lab || capture_kind == .Leaf_Generator_Lab || capture_kind == .Flower_Generator_Lab || capture_kind == .Window_Generator_Lab || capture_kind == .Bridge_Generator_Lab || capture_kind == .Fountain_Generator_Lab || capture_kind == .Cemetery_Generator_Lab || capture_kind == .Rocky_Beach_Lab || capture_kind == .Windmill_Generator_Lab || capture_kind == .Hero_Building_Lab || capture_kind == .Lighthouse_Lab || capture_kind == .Mouse_Gait_Lab || capture_kind == .Mouse_Theater || capture_kind == .Rondine_Movement_Lab || capture_kind == .Markov_Marina || capture_kind == .Ruins_Lab ? 20 : 2
    if request != nil && request.settle_frames >= 0 do capture_frame = request.settle_frames
    selector_capture_pose, selector_capture_pose_set, selector_ok := run_capture_selector(
        editor,
        request,
        capture_mode,
    )
    if !selector_ok do return .Quit
    cinematic_export_active = request != nil && request.sequence_frames > 0
    cinematic_export_time = 0
    defer {
        cinematic_export_active = false
        cinematic_export_time = 0
    }
    run := Run_State {
        editor                       = editor,
        request                      = request,
        startup_timings              = startup_timings,
        first_start                  = first_start,
        benchmark_mode               = benchmark_mode,
        instrument_duration_seconds  = instrument_duration_seconds,
        benchmark_scenario           = benchmark_scenario,
        benchmark_warmup             = benchmark_warmup,
        benchmark_frames             = benchmark_frames,
        benchmark_window_width       = benchmark_window_width,
        benchmark_window_height      = benchmark_window_height,
        benchmark_world_width        = benchmark_world_width,
        benchmark_world_height       = benchmark_world_height,
        interactive_lab_mode         = interactive_lab_mode,
        capture_mode                 = capture_mode,
        capture_car_mode             = capture_car_mode,
        capture_story_meeting_mode   = capture_story_meeting_mode,
        capture_wildflower_lab_mode  = capture_wildflower_lab_mode,
        capture_target               = capture_target,
        capture_output               = capture_output,
        postcard                     = postcard,
        wind_sound_state             = wind_sound,
        wind_audio_ready             = wind_audio_ready,
        ocean_sound_state            = ocean_sound,
        ocean_audio_ready            = ocean_audio_ready,
        spray_sound_state            = spray_sound,
        spray_audio_ready            = spray_audio_ready,
        engine_audio_ready           = engine_audio_ready,
        map_path                     = map_path,
        map_source                   = map_source,
        hot_library_path             = hot_library_path,
        hot_state_path               = hot_state_path,
        hot_library_mtime            = hot_library_mtime,
        capture_frame                = capture_frame,
        selector_capture_pose        = selector_capture_pose,
        selector_capture_pose_set    = selector_capture_pose_set,
        instrument_started_at        = canvas2d.GetTime(),
        turntable_capture_stride     = 12,
        turntable_last_capture_frame = capture_frame,
        sequence_last_capture_frame  = capture_frame,
    }
    adriatic_frame_loop(&run)
    return run.reload_requested ? .Reload : .Quit
}
