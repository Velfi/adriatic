#+feature using-stmt
package main

import atmosphere "../packages/atmosphere"
import boats "../packages/boats"
import chase_camera "../packages/chase_camera"
import dialogue "../packages/dialogue"
import flight "../packages/flight"
import fog_field "../packages/fog_field"
import harbor "../packages/harbor"
import libellula_game "../packages/libellula"
import particle_systems "../packages/particles"
import postale_game "../packages/postale"
import roads "../packages/roads"
import rondine_game "../packages/rondine"
import story "../packages/story"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import "core:strconv"
import canvas2d "zelda_engine:canvas2d"
import physics "zelda_engine:physics"

Run_Config :: struct {
    request:                                                                                      ^Capture_Request,
    benchmark_mode:                                                                               bool,
    benchmark_scenario:                                                                           string,
    capture_kind:                                                                                 Capture_Kind,
    capture_mode, capture_editor_mode, legacy_shadow_lab_mode:                                    bool,
    capture_sky_mode, capture_map_mode, capture_flight_mode, capture_car_mode:                    bool,
    capture_vehicle_showcase_mode, capture_gameplay_mode:                                         bool,
    capture_road_mode, capture_road_dust_mode, capture_road_grip_mode, capture_terrain_grip_mode: bool,
    capture_building_mode, capture_story_meeting_mode, capture_foliage_mode:                      bool,
    capture_foliage_forest_mode, capture_foliage_motion_mode, capture_foliage_golden_mode:        bool,
    capture_foliage_low_mode, capture_foliage_understory_mode, capture_foliage_stress_mode:       bool,
    capture_grass_wind_mode, capture_markov_town_mode, capture_lab_mode:                          bool,
    capture_lab_name, capture_target:                                                             string,
    clean_settlement_capture:                                                                     bool,
    interactive_lab_mode:                                                                         bool,
    interactive_lab_request:                                                                      Lab_Scene_Request,
    fog_capture:                                                                                  bool,
    capture_paint_mode, vehicle_showcase_mode:                                                    bool,
    showcase_target:                                                                              string,
    island_center:                                                                                f32,
}

run_capture_selector :: proc(
    editor: ^Editor,
    request: ^Capture_Request,
    capture_mode: bool,
) -> (
    pose: third_person.Camera_Pose,
    pose_set, ok: bool,
) {
    if !capture_mode || request == nil || request.selector == "" do return {}, false, true

    selector_pose, selector_subject, selector_error, selector_ok := capture_selector_pose(
        editor,
        request.selector,
        request.selector_filters,
        request.selector_filter_count,
        request.selector_pick,
        request.presentation,
    )
    if !selector_ok {
        request.selector_failed = true
        fmt.eprintf("capture selector %s: %s\n", request.selector, selector_error)
        return {}, false, false
    }
    fmt.printf(
        "capture selector %s matched %s (id %d)\n",
        request.selector,
        selector_subject.name,
        selector_subject.id,
    )
    return selector_pose, true, true
}

run_prepare_capture_world :: proc(editor: ^Editor, using config: ^Run_Config) -> bool {
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
                return false
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
            if capture_target == "dialogue-opening" ||
               capture_target == "dialogue-warm" ||
               capture_target == "dialogue-discreet" {
                editor.in_map = true
                editor.map_time = f32(canvas2d.GetTime())
                editor.player.grounded = true
                if open_story_dialogue(editor, .Niko) {
                    _ = dialogue.choose(&editor.attendant_dialogue, 0)
                    if capture_target == "dialogue-warm" {
                        _ = dialogue.choose(&editor.attendant_dialogue, 0)
                    } else if capture_target == "dialogue-discreet" {
                        _ = dialogue.choose(&editor.attendant_dialogue, 1)
                    }
                    dialogue_view_reset(editor)
                    dialogue_view_complete_reveal(editor)
                }
            }
        } else if capture_building_mode {
            if capture_target == "mouse-town" ||
               capture_target == "west-town-review" ||
               capture_target == "east-town-review" {
                seed_default_island_towns(editor)
                authoring_select_tool(editor, .Building)
                editor.structure_selected = -1
            } else {
                seed_city_capture(editor, capture_target)
            }
        } else {
            // The dune QA target inspects untouched generated coastline.
            // Procedural settlement seeding is both visually distracting and
            // substantially more expensive under ASAN, and infrastructure
            // integration remains covered by the normal editor capture.
            if !(capture_editor_mode && capture_target_is_generated_dunes(capture_target)) {
                seed_default_island_towns(editor)
            }
            // Keep the flight capture exercising distant road depth precision
            // as the chase camera climbs away from the authored island.
            if capture_flight_mode do seed_road_capture(editor)
        }
        if !capture_foliage_stress_mode && !capture_foliage_forest_mode && !capture_story_meeting_mode {
            editor.editor_camera.distance = 260
            editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
        }
        if capture_editor_mode && capture_target == "rock-tool" {
            authoring_select_rock_tool(editor)
            editor.formation_brush_radius = 36
            editor.formation_brush_strength = .58
            editor.formation_brush_hardness = .72
            center_x, center_z := editor.editor_focus.x, editor.editor_focus.z
            _ = capture_add_formation(editor, center_x - 12, center_z, 18, 14, 16, .Rock)
            _ = capture_add_formation(editor, center_x + 8, center_z + 3, 14, 19, 22, .Rock)
            _ = capture_add_formation(editor, center_x + 23, center_z - 5, 24, 15, 11, .Rock)
            for structure_index := editor.project.structure_count - 3;
                structure_index < editor.project.structure_count;
                structure_index += 1 {
                if structure_index >= 0 do editor.project.structures[structure_index].color = rock_tool_color(editor)
            }
            editor.editor_focus.y = terrain.sample_surface_height(&editor.project, 0, center_x, center_z) + 7
            editor.editor_camera.distance = 62
            editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
        }
        if capture_editor_mode && capture_target == "plant-stamp" {
            authoring_select_tool(editor, .Foliage)
            editor.plant_stamp_mode = .Climbing
            editor.climbing_leaf_paint_mode = true
            editor.climbing_leaf_brush_radius = 30
            editor.climbing_leaf_brush_strength = .62
            center_x, center_z := editor.editor_focus.x, editor.editor_focus.z
            target_index := capture_add_formation(editor, center_x, center_z, 24, 13, 17, .Rock)
            if target_index >= 0 {
                editor.project.structures[target_index].color = rock_tool_color(editor)
                editor.plant_stamp_target_index = target_index
                editor.plant_stamp_target_valid = true
                editor.plant_stamp_target_locked = true
            }
            editor.editor_focus = {
                center_x,
                terrain.sample_surface_height(&editor.project, 0, center_x, center_z) + 6,
                center_z,
            }
            editor.editor_camera.pitch_radians = .34
            editor.editor_camera.distance = 54
            editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
        }
        if capture_editor_mode && capture_target == "road-tool" {
            editor.project.road_graph = {}
            seed_road_capture(editor)
            authoring_select_tool(editor, .Roads)
            // Frame the four-way junction rather than a distant endpoint so
            // the deterministic screenshot actually exercises curve handles.
            editor.road_selected_node = editor.project.road_graph.node_count > 1 ? 1 : -1
            editor.road_construction_mode = .Terrain_Route
            editor.road_construction_phase = .Idle
            if editor.road_selected_node >= 0 {
                start := editor.project.road_graph.nodes[editor.road_selected_node].position
                // Pull the selected junction's four owned tangents into a
                // compact review layout. This is capture-only presentation;
                // the durable seeded graph remains representative elsewhere.
                offsets := [4]roads.Vec3{{-27, 0, 18}, {30, 0, -18}, {-22, 0, -28}, {21, 0, 29}}
                for &edge, edge_index in editor.project.road_graph.edges[:editor.project.road_graph.edge_count] {
                    control := start + offsets[edge_index]
                    control.y = terrain.sample_surface_height(&editor.project, 0, control.x, control.z) + .08
                    if edge.from == editor.road_selected_node {
                        edge.control_from = control
                    } else if edge.to == editor.road_selected_node {
                        edge.control_to = control
                    }
                }
                editor.editor_focus = {start.x + 3, start.y + 1, start.z + 1}
                editor.editor_camera.pitch_radians = .52
                editor.editor_camera.distance = 68
                editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
            }
        }
        if capture_editor_mode && capture_target_is_generated_dunes(capture_target) {
            _ = configure_generated_dune_capture_camera(
                editor,
                capture_target == "dunes-west" ? f32(-1) : f32(1),
                capture_target == "dunes-blowout",
            )
        }
        if capture_building_mode {
            _ = configure_building_capture_camera(editor, capture_target)
            if capture_target_is_storefront_night(capture_target) ||
               capture_target == "municipal-route-night" ||
               capture_target == "municipal-route-night-storm" ||
               capture_target == "plaza-night" ||
               capture_target == "plaza-night-new-moon" ||
               capture_target == "plaza-night-full-moon" ||
               capture_target == "plaza-night-storm" {
                atmosphere.set_world_minutes(&editor.atmosphere, 21 * 60)
                night_weather := atmosphere.Weather_Preset.Clear
                if capture_target == "plaza-night-storm" ||
                   capture_target == "storefront-night-storm" ||
                   capture_target == "municipal-route-night-storm" {
                    night_weather = .Storm
                }
                atmosphere.set_weather_override(&editor.atmosphere, night_weather)
                editor.atmosphere.weather = atmosphere.weather_for(night_weather)
                editor.atmosphere.paused = true
            }
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
        if capture_foliage_forest_mode {
            // Forest captures compare canopy value shapes across LODs;
            // gameplay HUD and tracked-errand panels would cover the subject.
            editor.capture_world_only = true
        }
    }
    if capture_lab_mode {
        _ = lab_scene_load(editor, {definition = lab_scene_find(capture_lab_name), target = capture_target})
        if capture_markov_town_mode && clean_settlement_capture {
            editor.settlement_diagnostic_layer = -1
            editor.capture_world_only = true
        }
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
        case .Sky_Sunrise:
            minutes = 6 * 60
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
    config.fog_capture =
        (capture_kind == .Map || capture_kind == .Flight) &&
        (capture_target == "fog-approach" ||
                capture_target == "fog-boundary" ||
                capture_target == "fog-inside" ||
                capture_target == "fog-above")
    if config.fog_capture {
        atmosphere.set_world_minutes(&editor.atmosphere, 10 * 60 + 20)
        atmosphere.set_weather_override(&editor.atmosphere, .Storm)
        editor.atmosphere.weather = atmosphere.weather_for(.Storm)
        editor.atmosphere.front_seconds = 31.25
        editor.atmosphere.paused = true
        half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
        field := fog_field.generate(
            editor.atmosphere.seed,
            editor.atmosphere.front_seconds,
            editor.atmosphere.weather,
            {{-half_extent, -half_extent}, {half_extent, half_extent}},
            editor.atmosphere.climate.current,
        )
        bank := field.banks[0]
        center := third_person.Vec3{bank.center.x, bank.top_altitude * .42, bank.center.y}
        offset := third_person.Vec3{bank.axis.x * bank.radii.x, 0, bank.axis.y * bank.radii.x}
        camera_position := center + offset * 1.75 + third_person.Vec3{0, 70, 0}
        if capture_target == "fog-boundary" do camera_position = center + offset * 1.02 + third_person.Vec3{0, 20, 0}
        if capture_target == "fog-inside" do camera_position = center + third_person.Vec3{0, 8, 0}
        if capture_target == "fog-above" do camera_position = center + third_person.Vec3{0, bank.top_altitude + 180, 0}
        editor.camera_pose = third_person.camera_look_at(camera_position, center)
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
        building_capture_minutes := f32(16 * 60 + 45)
        if capture_target_is_storefront_night(capture_target) ||
           capture_target == "plaza-night" ||
           capture_target == "plaza-night-new-moon" ||
           capture_target == "plaza-night-full-moon" ||
           capture_target == "plaza-night-storm" ||
           capture_target == "municipal-route-night" ||
           capture_target == "municipal-route-night-storm" {
            building_capture_minutes = 21 * 60
        }
        atmosphere.set_world_minutes(&editor.atmosphere, building_capture_minutes)
        if capture_target == "plaza-night-new-moon" {
            atmosphere.set_lunar_age(&editor.atmosphere, 0)
        } else if capture_target == "plaza-night-full-moon" {
            atmosphere.set_lunar_age(&editor.atmosphere, atmosphere.SYNODIC_MONTH_DAYS * .5)
        }
        building_weather := atmosphere.Weather_Preset.Clear
        if capture_target == "plaza-night-storm" ||
           capture_target == "storefront-night-storm" ||
           capture_target == "municipal-route-night-storm" {
            building_weather = .Storm
        }
        atmosphere.set_weather_override(&editor.atmosphere, building_weather)
        editor.atmosphere.weather = atmosphere.weather_for(building_weather)
        editor.atmosphere.front_seconds = .75
        editor.atmosphere.paused = true
    }
    if benchmark_mode {
        if !benchmark_seed_scene(editor, benchmark_scenario) {
            fmt.eprintf("unknown benchmark scenario: %s\n", benchmark_scenario)
            return false
        }
        gameplay_physics_sync_revisions(editor)
        gameplay_physics_rebuild_boats(editor)
        gameplay_physics_teleport_player(editor)
        car_physics_teleport(editor)
        benchmark_minutes := f32(9 * 60 + 30)
        if benchmark_scenario == "architecture_night" ||
           benchmark_scenario == "municipal_route_night" ||
           benchmark_scenario == "municipal_route_night_storm" {
            benchmark_minutes = 21 * 60
        }
        atmosphere.set_world_minutes(&editor.atmosphere, benchmark_minutes)
        benchmark_weather := atmosphere.Weather_Preset.Clear
        if benchmark_scenario == "municipal_route_night_storm" {
            benchmark_weather = .Storm
        }
        if benchmark_scenario == "fog_banks" {
            benchmark_weather = .Storm
            editor.atmosphere.front_seconds = 31.25
        }
        atmosphere.set_weather_override(&editor.atmosphere, benchmark_weather)
        editor.atmosphere.weather = atmosphere.weather_for(benchmark_weather)
        editor.atmosphere.paused = true
    }
    return true
}


run_prepare_gameplay_capture :: proc(editor: ^Editor, config: ^Run_Config) {
    if !config.capture_gameplay_mode do return
    run_prepare_world_and_flight_capture(editor, config)
    run_prepare_vehicle_and_marta_capture(editor, config)
    run_prepare_story_capture(editor, config)
    run_prepare_player_capture(editor, config)
    run_prepare_environment_and_menu_capture(editor, config)
}
