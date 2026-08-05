package main

import architecture "../packages/architecture"
import boats "../packages/boats"
import buildings "../packages/buildings"
import flight "../packages/flight"
import libellula_game "../packages/libellula"
import marina "../packages/marina"
import postale_game "../packages/postale"
import roads "../packages/roads"
import rondine_game "../packages/rondine"
import story "../packages/story"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:math"
import "core:testing"
import sdl "vendor:sdl3"

when ODIN_TEST {
    @(test)
    friendship_notice_tracks_changes_and_expires :: proc(t: ^testing.T) {
        editor := new(Editor)
        testing.expect(t, editor != nil)
        if editor == nil do return
        defer free(editor)

        editor.story_state.friendship_points = 4
        friendship_notice_step(editor, .1)
        testing.expect(t, editor.friendship_notice_initialized)
        testing.expect(t, editor.friendship_notice_total == 4)
        testing.expect(t, editor.friendship_notice_delta == 0)

        editor.story_state.friendship_points = 6
        friendship_notice_step(editor, .1)
        testing.expect(t, editor.friendship_notice_delta == 2)
        testing.expect(t, editor.friendship_notice_total == 6)
        testing.expect(t, editor.friendship_notice_age == 0)

        friendship_notice_step(editor, FRIENDSHIP_NOTICE_DURATION)
        testing.expect(t, editor.friendship_notice_age == FRIENDSHIP_NOTICE_DURATION)
    }

    @(test)
    coastal_grass_density_keeps_active_sand_sparse_and_breaks_up_colonies :: proc(t: ^testing.T) {
        active_peak := f32(0)
        stable_min, stable_max := f32(1), f32(0)
        for z := f32(-36); z <= 36; z += 6 {
            for x := f32(-36); x <= 36; x += 6 {
                active := coastal_grass_card_density(-.68, x, z)
                stable := coastal_grass_card_density(-.08, x, z)
                testing.expect(t, active >= 0 && active <= 1)
                testing.expect(t, stable >= 0 && stable <= 1)
                active_peak = max(active_peak, active)
                stable_min = min(stable_min, stable)
                stable_max = max(stable_max, stable)
            }
        }
        testing.expect(t, active_peak < .012)
        testing.expect(t, stable_max - stable_min > .25)
        testing.expect(t, stable_max < .52)
    }

    @(test)
    clipmap_center_offsets_map_positive_negative_and_diagonal_shifts :: proc(t: ^testing.T) {
        positive, valid := clipmap_center_offset({0, 0}, {2, 0}, 2)
        testing.expect(t, valid)
        testing.expect_value(t, positive, [2]int{1, 0})
        source, retained := clipmap_shift_source(0, 12, positive)
        testing.expect(t, retained)
        testing.expect_value(t, source, 12 * CLIPMAP_GRID_RESOLUTION + 1)

        negative, valid_negative := clipmap_center_offset({0, 0}, {-2, 0}, 2)
        testing.expect(t, valid_negative)
        testing.expect_value(t, negative, [2]int{-1, 0})
        _, retained_negative := clipmap_shift_source(0, 12, negative)
        testing.expect(t, !retained_negative)

        diagonal, valid_diagonal := clipmap_center_offset({4, 6}, {2, 10}, 2)
        testing.expect(t, valid_diagonal)
        testing.expect_value(t, diagonal, [2]int{-1, 2})
        diagonal_source, diagonal_retained := clipmap_shift_source(10, 10, diagonal)
        testing.expect(t, diagonal_retained)
        testing.expect_value(t, diagonal_source, 12 * CLIPMAP_GRID_RESOLUTION + 9)
    }

    @(test)
    clipmap_center_offsets_reject_large_and_unaligned_moves :: proc(t: ^testing.T) {
        _, large_valid := clipmap_center_offset({0, 0}, {f32(CLIPMAP_GRID_RESOLUTION) * 2, 0}, 2)
        testing.expect(t, !large_valid)
        _, unaligned_valid := clipmap_center_offset({0, 0}, {1, 0}, 2)
        testing.expect(t, !unaligned_valid)
    }

    @(test)
    inner_clipmap_shift_sources_use_the_dedicated_resolution :: proc(t: ^testing.T) {
        source, retained := clipmap_shift_source_for_resolution(0, 12, [2]int{1, 0}, CLIPMAP_INNER_GRID_RESOLUTION)
        testing.expect(t, retained)
        testing.expect_value(t, source, 12 * CLIPMAP_INNER_GRID_RESOLUTION + 1)
        _, rejected := clipmap_shift_source_for_resolution(0, 12, [2]int{-1, 0}, CLIPMAP_INNER_GRID_RESOLUTION)
        testing.expect(t, !rejected)
    }

    @(test)
    clipmap_level_center_snaps_to_requested_spacing :: proc(t: ^testing.T) {
        target := [2]f32{3, 3}
        testing.expect_value(t, clipmap_level_center(target, 2), [2]f32{4, 4})
        testing.expect_value(t, clipmap_level_center(target, 4), [2]f32{4, 4})
        testing.expect_value(t, clipmap_level_center(target, 8), [2]f32{0, 0})
    }

    @(test)
    clipmap_ring_holes_follow_all_fine_level_offsets :: proc(t: ^testing.T) {
        expected_width := CLIPMAP_GRID_RESOLUTION / 2 - 1
        for offset_z in -1 ..= 1 {
            for offset_x in -1 ..= 1 {
                hole := clipmap_ring_hole_bounds({offset_x, offset_z})
                testing.expect_value(t, hole[2] - hole[0], expected_width)
                testing.expect_value(t, hole[3] - hole[1], expected_width)
                testing.expect_value(t, hole[0], CLIPMAP_GRID_RESOLUTION / 4 + (offset_x > 0 ? 1 : 0))
                testing.expect_value(t, hole[1], CLIPMAP_GRID_RESOLUTION / 4 + (offset_z > 0 ? 1 : 0))
            }
        }
    }

    @(test)
    clipmap_levels_preserve_detail_and_double_world_coverage :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        terrain.init_project(&editor.project)
        defer terrain.destroy_project(&editor.project)
        expected_cells := [terrain.CLIPMAP_LEVELS]f32{.5, 2, 4, 8, 16, 32}
        for level in 0 ..< terrain.CLIPMAP_LEVELS {
            testing.expect_value(t, clipmap_grid_cell(editor, level), expected_cells[level])
        }
        testing.expect_value(t, clipmap_grid_resolution(0), CLIPMAP_INNER_GRID_RESOLUTION)
        testing.expect_value(t, clipmap_grid_resolution(1), CLIPMAP_GRID_RESOLUTION)
        inner_coverage := f32(clipmap_grid_resolution(0) - 1) * clipmap_grid_cell(editor, 0)
        former_coverage := f32(CLIPMAP_GRID_RESOLUTION - 1)
        testing.expect_value(t, inner_coverage, former_coverage)
        previous_coverage := inner_coverage
        for level in 1 ..< terrain.CLIPMAP_LEVELS {
            coverage := f32(clipmap_grid_resolution(level) - 1) * clipmap_grid_cell(editor, level)
            testing.expect_value(t, coverage, previous_coverage * 2)
            previous_coverage = coverage
        }
    }

    @(test)
    clipmap_detail_follows_projected_vertex_spacing_in_editor_and_gameplay :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        terrain.init_project(&editor.project)
        defer terrain.destroy_project(&editor.project)
        editor.camera_pose = third_person.camera_look_at({0, 900, 0}, {0, 0, 0})
        testing.expect_value(t, clipmap_first_render_level(editor, 1080), 1)
        editor.camera_pose = third_person.camera_look_at({0, 3000, 0}, {0, 0, 0})
        testing.expect_value(t, clipmap_first_render_level(editor, 1080), 3)
        editor.in_map = true
        editor.camera_pose = third_person.camera_look_at({0, 8, 12}, {0, 1, 0})
        testing.expect_value(t, clipmap_first_render_level(editor, 1080), 0)
        editor.in_map = false
        editor.camera_pose = third_person.camera_look_at({0, 21, 0}, {0, 0, 500})
        testing.expect_value(t, clipmap_first_render_level(editor, 1080), 0)
        editor.camera_pose = third_person.camera_look_at({0, 3008, 12}, {0, 3000, 0})
        testing.expect_value(t, clipmap_first_render_level(editor, 1080), 3)
    }

    @(test)
    clipmap_transition_widths_keep_the_same_world_space_blend :: proc(t: ^testing.T) {
        testing.expect_value(t, clipmap_transition_weight(0, 0, 100), f32(1))
        testing.expect_value(t, clipmap_transition_weight(0, CLIPMAP_TRANSITION_WIDTH * 2, 100), f32(0))
        testing.expect_value(t, clipmap_transition_weight(1, 0, 100), f32(1))
        testing.expect_value(t, clipmap_transition_weight(1, CLIPMAP_TRANSITION_WIDTH * 2, 100), f32(0))
        testing.expect_value(t, clipmap_transition_weight(2, CLIPMAP_TRANSITION_WIDTH, 100), f32(0))
    }

    @(test)
    beach_vertex_color_is_smooth_while_fragment_field_remains_bounded :: proc(t: ^testing.T) {
        previous_color := terrain_color(3.2, -.55, 0, 0, 18)
        previous_field := sand_color_field(0, 18)
        minimum_field, maximum_field := previous_field, previous_field
        for x := f32(.5); x <= 80; x += .5 {
            current_color := terrain_color(3.2, -.55, 0, x, 18)
            current_field := sand_color_field(x, 18)
            testing.expect_value(t, current_color, previous_color)
            testing.expect(t, abs(current_field - previous_field) < .2)
            testing.expect(t, current_field >= -1 && current_field <= 1)
            minimum_field = min(minimum_field, current_field)
            maximum_field = max(maximum_field, current_field)
            previous_color = current_color
            previous_field = current_field
        }
        testing.expect(t, maximum_field - minimum_field > .2)
        active_reference := terrain_color(3.2, -1, 0, 12, 9)
        transitional_reference := terrain_color(3.2, -.55, 0, 12, 9)
        stable_reference := terrain_color(3.2, -.001, 0, 12, 9)
        testing.expect(t, transitional_reference.r < active_reference.r)
        testing.expect(t, stable_reference.r < transitional_reference.r)

        dry := terrain_color(.3, -1, 0, 12, 9)
        wet := terrain_color(.3, -2, 0, 12, 9)
        dry_value := int(dry.r) + int(dry.g) + int(dry.b)
        wet_value := int(wet.r) + int(wet.g) + int(wet.b)
        testing.expect(t, wet_value < dry_value)
        testing.expect_value(t, terrain.classify_ground(-1, 3.2, 0), terrain.Ground_Surface.Sand)
    }

    returning_to_editor_resets_game_state_without_resetting_authored_world :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        terrain.init_project(&editor.project)
        revision := editor.project.revision
        sea_level := editor.project.sea_level

        editor.in_map = true
        editor.story_state.romance = .Meeting
        editor.marina_dinghy_borrowed = true
        editor.pilot.mode = .Driving
        editor.car_trailer_attached = false
        editor.postale_visible = false
        editor.libellula_visible = false

        editor.in_map = false
        game_state_reset(editor)

        testing.expect(t, !editor.in_map)
        testing.expect_value(t, editor.project.revision, revision)
        testing.expect_value(t, editor.project.sea_level, sea_level)
        testing.expect_value(t, editor.story_state, story.State{})
        testing.expect_value(t, editor.pilot.mode, vehicles.Occupancy_Mode.On_Foot)
        testing.expect(t, editor.car_trailer_attached)
        testing.expect(t, editor.postale_visible)
        testing.expect(t, editor.libellula_visible)
        testing.expect(t, !editor.marina_dinghy_borrowed)
    }

    @(test)
    world_boat_traffic_only_spawns_complete_hulls_over_water :: proc(t: ^testing.T) {
        project := terrain.new_project()
        defer terrain.free_project(project)

        traffic := new_world_boat_traffic(project)
        testing.expect(t, traffic.count > 0)
        for &agent in traffic.agents[:traffic.count] {
            testing.expect(t, boat_spawn_is_water(project, &agent, agent.position))
        }
    }

    @(test)
    player_placement_synchronizes_every_on_foot_representation :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        terrain.init_project(&editor.project)
        spawn := runway_spawn_position(editor)
        _ = mouse_emote_start(&editor.mouse_emote, .Synthetic_Test)
        player_place(editor, spawn, .Startup, .75)

        testing.expect_value(t, editor.player.position, spawn)
        testing.expect_value(t, editor.pilot.position, spawn)
        testing.expect_value(t, editor.player.facing_yaw_radians, f32(.75))
        testing.expect_value(t, editor.pilot.facing_yaw_radians, f32(.75))
        testing.expect_value(t, editor.pilot.mode, vehicles.Occupancy_Mode.On_Foot)
        testing.expect_value(t, editor.player_placement_reason, Player_Placement_Reason.Startup)
        testing.expect_value(t, editor.player_placement_revision, u64(1))
        testing.expect_value(t, editor.mouse_emote.action, Mouse_Emote.None)

        // This is the lifecycle guard that catches the original bug: a scene
        // position differing from the cached physics position must be
        // teleported before the next character step can overwrite it.
        testing.expect(t, gameplay_physics_player_needs_teleport(spawn, {}, true))
        testing.expect(t, !gameplay_physics_player_needs_teleport(spawn, spawn, true))
        testing.expect(t, gameplay_physics_player_needs_teleport(spawn, spawn, false))
    }

    @(test)
    moving_an_island_moves_its_player_spawn_and_vehicles :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        editor.project.island_transforms = terrain.default_island_transforms()
        defer terrain.destroy_project(&editor.project)

        east_x, east_z, east_ok := terrain.island_center(&editor.project, .East)
        testing.expect(t, east_ok)
        editor.player.position = {east_x + 4, 3, east_z + 5}
        editor.pilot.position = editor.player.position
        editor.postale = postale_game.new_runtime({east_x + 10, 8, east_z + 11})
        editor.libellula = libellula_game.new_runtime({east_x + 20, 9, east_z + 21})
        editor.rondine = rondine_game.new_runtime({east_x + 30, 10, east_z + 31})
        editor.car = vehicles.default_vehicle({east_x + 40, 2, east_z + 41})
        editor.car_trailer_attached = true
        editor.car_trailer_position = {east_x + 42, 2, east_z + 43}
        editor.attendant_position = {east_x + 50, 2, east_z + 51}
        editor.gerta_position = {-east_x, 2, -east_z}
        airport := terrain.structure_make(east_x + 60, east_z + 61, 40, 30, 2, 8)
        airport.kind = .Architecture
        airport.group_id = AIRPORT_STAMP_GROUP
        airport.seed = AIRPORT_STAMP_SEED
        airport_index := terrain.add_structure(&editor.project, airport)
        testing.expect(t, airport_index >= 0)
        editor.project.structures[airport_index].seed = AIRPORT_STAMP_SEED
        editor.architecture_city_plan.structures = make([dynamic]terrain.Structure, 1)
        editor.architecture_city_plan.structures[0] = airport
        editor.architecture_city_plan.count = 1
        editor.architecture_city_plan.parcels = make([dynamic]architecture.City_Parcel, 1)
        editor.architecture_city_plan.parcels[0].corners = {
            {east_x + 55, east_z + 55},
            {east_x + 65, east_z + 55},
            {east_x + 65, east_z + 65},
            {east_x + 55, east_z + 65},
        }
        editor.architecture_city_plan.parcel_count = 1
        editor.architecture_city_plan.lamps = make([dynamic]architecture.City_Lamp, 1)
        editor.architecture_city_plan.lamps[0] = {
            x = east_x + 62,
            z = east_z + 62,
        }
        editor.architecture_city_plan.lamp_count = 1
        defer architecture.city_plan_destroy(&editor.architecture_city_plan)
        editor.curve_points[0] = {east_x + 66, east_z + 66}
        editor.curve_point_count = 1
        editor.sdf_obstacles[0].position = {east_x + 68, 9, east_z + 68}
        editor.sdf_obstacle_count = 1
        editor.boat_traffic.count = 2
        editor.boat_traffic.agents[0] = {
            class          = .Fishing,
            position       = {east_x + 70, east_z + 71},
            route_count    = 2,
            loiter_center  = {east_x + 76, east_z + 77},
            schedule_count = 1,
            wake_count     = 1,
        }
        editor.boat_traffic.agents[0].route[0] = {east_x + 72, east_z + 73}
        editor.boat_traffic.agents[0].route[1] = {east_x + 74, east_z + 75}
        editor.boat_traffic.agents[0].schedule[0] = {0, 1440, .Patrol, .75}
        editor.boat_traffic.agents[0].wake[0] = {
            position = {east_x + 68, east_z + 69},
        }
        editor.boat_traffic.agents[1] = boats.Agent {
            class       = .Motor,
            position    = {-east_x, -east_z},
            route_count = 1,
        }
        editor.boat_traffic.agents[1].route[0] = {-east_x, -east_z}

        player_before := editor.player.position
        postale_before := editor.postale.body.position
        libellula_before := editor.libellula.body.position
        rondine_before := editor.rondine.body.position
        car_before := editor.car.position
        trailer_before := editor.car_trailer_position
        attendant_before := editor.attendant_position
        gerta_before := editor.gerta_position
        airport_before := editor.project.structures[airport_index]
        east_boat_before := editor.boat_traffic.agents[0]
        west_boat_before := editor.boat_traffic.agents[1]
        terrain_revision_before := editor.terrain_revision
        dx, dz := f32(-120), f32(-80)

        editor_island_translate_dependent_state(editor, .East, dx, dz)
        testing.expect(t, terrain.island_set_center(&editor.project, .East, east_x + dx, east_z + dz))
        editor.terrain_revision += 1

        testing.expect_value(t, editor.player.position.x, player_before.x + dx)
        testing.expect_value(t, editor.player.position.z, player_before.z + dz)
        testing.expect_value(t, editor.pilot.position, editor.player.position)
        testing.expect_value(t, editor.postale.body.position.x, postale_before.x + dx)
        testing.expect_value(t, editor.postale.body.position.z, postale_before.z + dz)
        testing.expect_value(t, editor.libellula.body.position.x, libellula_before.x + dx)
        testing.expect_value(t, editor.libellula.body.position.z, libellula_before.z + dz)
        testing.expect_value(t, editor.rondine.body.position.x, rondine_before.x + dx)
        testing.expect_value(t, editor.rondine.body.position.z, rondine_before.z + dz)
        testing.expect_value(t, editor.car.position.x, car_before.x + dx)
        testing.expect_value(t, editor.car.position.z, car_before.z + dz)
        testing.expect_value(t, editor.car_trailer_position.x, trailer_before.x + dx)
        testing.expect_value(t, editor.car_trailer_position.z, trailer_before.z + dz)
        testing.expect_value(t, editor.attendant_position.x, attendant_before.x + dx)
        testing.expect_value(t, editor.attendant_position.z, attendant_before.z + dz)
        testing.expect_value(t, editor.gerta_position, gerta_before)
        testing.expect_value(t, editor.project.structures[airport_index].center_x, airport_before.center_x + dx)
        testing.expect_value(t, editor.project.structures[airport_index].center_z, airport_before.center_z + dz)
        testing.expect_value(t, editor.boat_traffic.agents[0].position, east_boat_before.position + boats.Vec2{dx, dz})
        testing.expect_value(t, editor.boat_traffic.agents[0].route[0], east_boat_before.route[0] + boats.Vec2{dx, dz})
        testing.expect_value(
            t,
            editor.boat_traffic.agents[0].loiter_center,
            east_boat_before.loiter_center + boats.Vec2{dx, dz},
        )
        testing.expect_value(
            t,
            editor.boat_traffic.agents[0].wake[0].position,
            east_boat_before.wake[0].position + boats.Vec2{dx, dz},
        )
        testing.expect_value(t, editor.boat_traffic.agents[0].schedule, east_boat_before.schedule)
        testing.expect_value(t, editor.boat_traffic.agents[1], west_boat_before)
        testing.expect_value(t, editor.architecture_city_plan.structures[0].center_x, airport.center_x + dx)
        testing.expect_value(t, editor.architecture_city_plan.parcels[0].corners[0][0], east_x + 55 + dx)
        testing.expect_value(t, editor.architecture_city_plan.lamps[0].x, east_x + 62 + dx)
        testing.expect_value(t, editor.curve_points[0].x, east_x + 66 + dx)
        testing.expect_value(t, editor.sdf_obstacles[0].position.x, east_x + 68 + dx)
        testing.expect_value(t, editor.terrain_revision, terrain_revision_before + 1)
        testing.expect_value(t, editor.postale.spawn_position.x, postale_before.x + dx)
        testing.expect_value(t, editor.postale.spawn_position.z, postale_before.z + dz)

    }

    @(test)
    editor_island_move_rejects_overlapping_ownership_domains :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        editor.project.island_transforms = terrain.default_island_transforms()
        west_x, west_z, _ := terrain.island_center(&editor.project, .West)
        testing.expect(t, !editor_island_set_center(editor, .East, west_x, west_z))
    }

    @(test)
    default_map_respawn_repositions_player_and_vehicles_without_resetting_progress :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        terrain.init_project(&editor.project)
        defer terrain.destroy_project(&editor.project)

        editor.story_state.romance = .Meeting
        editor.postale = postale_game.new_runtime({100, 100, 100})
        editor.libellula = libellula_game.new_runtime({200, 200, 200})
        editor.rondine = rondine_game.new_runtime({300, 300, 300})
        vehicles.aircraft_fleet_add(&editor.aircraft, .Postale, "Postale", &editor.postale.vehicle, true)
        vehicles.aircraft_fleet_add(&editor.aircraft, .Libellula_Mk2, "Libellula Mk2", &editor.libellula.vehicle, true)
        vehicles.aircraft_fleet_add(&editor.aircraft, .Rondine, "Rondine", &editor.rondine.vehicle, false)
        editor.aircraft.active = .Libellula_Mk2
        editor.car = vehicles.default_vehicle({400, 400, 400})
        editor.pilot.mode = .Driving
        editor.pilot.vehicle = &editor.car
        editor.car.driver = &editor.pilot

        default_map_respawn_mobile_actors(editor)

        testing.expect_value(t, editor.story_state.romance, story.Romance_Stage.Meeting)
        testing.expect_value(t, editor.player.position, runway_spawn_position(editor))
        testing.expect_value(t, editor.pilot.mode, vehicles.Occupancy_Mode.On_Foot)
        testing.expect(t, editor.pilot.vehicle == nil)
        testing.expect_value(t, editor.postale.body.position, postale_spawn_position(editor))
        libellula_spawn := libellula_spawn_position(editor)
        testing.expect_value(
            t,
            editor.libellula.body.position,
            flight.Vec3{libellula_spawn.x, libellula_spawn.y, libellula_spawn.z},
        )
        testing.expect_value(t, editor.rondine.body.position, rondine_spawn_position(editor))
        testing.expect_value(t, editor.car.position, car_spawn_position(editor))
        testing.expect(t, editor.car_trailer_attached)
        testing.expect_value(t, editor.aircraft.active, vehicles.Aircraft_Kind.Libellula_Mk2)
        testing.expect(t, vehicles.aircraft_fleet_slot(&editor.aircraft, .Postale).vehicle == &editor.postale.vehicle)
        testing.expect(t, vehicles.aircraft_fleet_slot(&editor.aircraft, .Libellula_Mk2).available)
        testing.expect(t, !vehicles.aircraft_fleet_slot(&editor.aircraft, .Rondine).available)
    }

    @(test)
    east_marina_lookup_preserves_island_identity :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        editor.default_marina_count = 1
        editor.default_marina_islands[0] = .West
        testing.expect(t, east_marina_plan(editor) == nil)

        editor.default_marinas[0].seed = 17
        editor.default_marina_islands[0] = .East
        editor.default_marinas[1].seed = 29
        editor.default_marina_islands[1] = .West
        editor.default_marina_count = 2
        east := east_marina_plan(editor)
        testing.expect(t, east != nil)
        testing.expect_value(t, east.seed, u32(17))
    }

    @(test)
    generated_marinas_are_rebuilt_with_island_identity :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        terrain.init_project(&editor.project)
        defer terrain.destroy_project(&editor.project)

        seed_default_island_marinas(editor)

        testing.expect_value(t, editor.default_marina_count, len(terrain.DEFAULT_ISLAND_SIGNS))
        west_found, east_found := false, false
        for &plan, index in editor.default_marinas[:editor.default_marina_count] {
            testing.expect(t, plan.valid)
            sign := editor.default_marina_islands[index] == .West ? f32(-1) : f32(1)
            town_x, town_z := terrain.default_town_center_for_project(&editor.project, sign)
            testing.expect(t, default_marina_plan_clears_town(&plan, {town_x, town_z}))
            intervention := &editor.default_harbor_interventions[index]
            testing.expect(t, intervention.valid)
            if intervention.valid {
                dx := intervention.site.anchor.x - town_x
                dz := intervention.site.anchor.z - town_z
                testing.expect(t, dx * dx + dz * dz >= DEFAULT_MARINA_TOWN_SEPARATION * DEFAULT_MARINA_TOWN_SEPARATION)
                office := marina.plan_world_position(&plan, plan.office)
                marina_dx := intervention.site.anchor.x - office.x
                marina_dz := intervention.site.anchor.z - office.z
                testing.expect(
                    t,
                    marina_dx * marina_dx + marina_dz * marina_dz <=
                    DEFAULT_MARINA_HARBOR_ALIGNMENT * DEFAULT_MARINA_HARBOR_ALIGNMENT,
                )
            }
            harbor_plan := &editor.default_harbors[index]
            access, access_valid := default_marina_find_access_route(
                &editor.project,
                town_x,
                town_z,
                &plan,
                harbor_plan,
            )
            testing.expect(t, access_valid)
            testing.expect(t, !settlement_route_crosses_sea(&editor.project, access))
            _, _, maximum_grade := settlement_route_length_and_grade(&editor.project, access)
            testing.expect(t, maximum_grade <= settlement_route_grade_limit(.Street) + .001)
            west_found = west_found || editor.default_marina_islands[index] == .West
            east_found = east_found || editor.default_marina_islands[index] == .East
        }
        testing.expect(t, west_found)
        testing.expect(t, east_found)
        // Terrain generation contributes only the two runway surfaces. Each
        // marina adds at least one terrain-following network segment.
        testing.expect(t, editor.project.road_graph.edge_count >= 4)
    }

    @(test)
    runway_access_uses_terrain_routed_connectors :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        terrain.init_project(&editor.project)
        defer terrain.destroy_project(&editor.project)

        edges_before := editor.project.road_graph.edge_count
        for sign in terrain.DEFAULT_ISLAND_SIGNS {
            testing.expect(t, seed_default_runway_access(editor, sign))
        }
        testing.expect(t, editor.project.road_graph.edge_count > edges_before)
        for edge in editor.project.road_graph.edges[edges_before:editor.project.road_graph.edge_count] {
            testing.expect_value(t, edge.pavement, roads.Pavement.Gravel)
        }
    }

    @(test)
    town_streets_do_not_relocate_the_airport_terminal :: proc(t: ^testing.T) {
        project := new(terrain.Project)
        defer free(project)
        terrain.init_project(project)
        defer terrain.destroy_project(project)

        for sign in terrain.DEFAULT_ISLAND_SIGNS {
            nominal_x, nominal_z := terrain.default_airport_center(sign)
            town_x, town_z := terrain.default_town_center_for_project(project, sign)
            from := roads.add_node(&project.road_graph, {town_x - 40, 0, town_z}, 4)
            to := roads.add_node(&project.road_graph, {town_x + 40, 0, town_z}, 4)
            _ = roads.add_straight_edge(&project.road_graph, from, to, 4, 1, .Cobblestone, .8)

            airport_x, airport_z := terrain.default_airport_center_for_project(project, sign)
            testing.expect(t, math.abs(airport_x - nominal_x) < .01)
            testing.expect(t, math.abs(airport_z - nominal_z) < .01)
        }
    }

    @(test)
    regenerated_worlds_spawn_hero_buildings_on_the_road_network :: proc(t: ^testing.T) {
        seeds := terrain.DEFAULT_ISLAND_SEEDS
        for generation in 0 ..< 2 {
            if generation > 0 do seeds = terrain.next_default_island_seeds(seeds)
            editor := new(Editor)
            terrain.init_project_seeded(&editor.project, seeds)
            seed_default_island_marinas_seeded(editor, seeds)
            seed_default_island_towns_seeded(editor, seeds)

            for sign in terrain.DEFAULT_ISLAND_SIGNS {
                post_offices, clinics, lighthouses := 0, 0, 0
                island_x, island_z := terrain.default_island_center(sign)
                for structure in editor.project.structures[:editor.project.structure_count] {
                    if structure.kind != .Architecture do continue
                    dx, dz := structure.center_x - island_x, structure.center_z - island_z
                    if dx * dx + dz * dz > 1400 * 1400 do continue
                    identity := architecture.architecture_resolve_legacy_identity(structure)
                    if identity.archetype == .Post_Office || identity.archetype == .Clinic {
                        entrance := settlement_structure_front_door_point(structure, 1)
                        _, distance, found := default_road_nearest_point(&editor.project, entrance)
                        testing.expect(t, found && distance <= 16)
                    }
                    if identity.archetype == .Post_Office do post_offices += 1
                    if identity.archetype == .Clinic do clinics += 1
                    if identity.archetype == .Lighthouse {
                        lighthouses += 1
                        keeper, _, found := world_lighthouse_keeper_pose(editor, structure)
                        testing.expect(t, found && default_lighthouse_has_access(&editor.project, keeper.x, keeper.z))
                    }
                }
                testing.expect(t, post_offices >= 1)
                testing.expect(t, clinics >= 1)
                testing.expect_value(t, lighthouses, 1)
                airport_x, airport_z := terrain.default_airport_center_for_project(&editor.project, sign)
                for structure in editor.project.structures[:editor.project.structure_count] {
                    if structure.kind != .Architecture do continue
                    testing.expect(
                        t,
                        settlement_airport_terminals_clear(
                            &editor.project,
                            structure.center_x,
                            structure.center_z,
                            structure.width,
                            structure.depth,
                            structure.rotation,
                            2,
                        ),
                    )
                }
                _, airport_distance, airport_connected := default_road_nearest_point(
                    &editor.project,
                    {airport_x, airport_z},
                )
                testing.expect(t, airport_connected && airport_distance <= 8)
            }
            terrain.destroy_project(&editor.project)
            free(editor)
        }
    }

    @(test)
    default_islands_each_receive_one_lighthouse_and_keeper_pose :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        terrain.init_project(&editor.project)
        defer terrain.destroy_project(&editor.project)

        for sign, island_index in terrain.DEFAULT_ISLAND_SIGNS {
            edges_before := editor.project.road_graph.edge_count
            seed_default_island_lighthouse(editor, sign, island_index)
            edges_after_first_seed := editor.project.road_graph.edge_count
            // Re-seeding must remain idempotent.
            seed_default_island_lighthouse(editor, sign, island_index)
            testing.expect(t, edges_after_first_seed > edges_before)
            testing.expect_value(t, editor.project.road_graph.edge_count, edges_after_first_seed)
        }

        testing.expect_value(t, editor.project.structure_count, len(terrain.DEFAULT_ISLAND_SIGNS))
        island_signs := terrain.DEFAULT_ISLAND_SIGNS
        for structure, island_index in editor.project.structures[:editor.project.structure_count] {
            identity := architecture.architecture_resolve_legacy_identity(structure)
            testing.expect_value(t, identity.archetype, buildings.Archetype.Lighthouse)
            keeper, _, found := world_lighthouse_keeper_pose(editor, structure)
            testing.expect(t, found)
            testing.expect(t, keeper.y > editor.project.sea_level + .35)
            testing.expect(t, default_lighthouse_has_access(&editor.project, keeper.x, keeper.z))
            town_x, town_z := terrain.default_town_center(island_signs[island_index])
            dx, dz := structure.center_x - town_x, structure.center_z - town_z
            testing.expect(
                t,
                dx * dx + dz * dz >= DEFAULT_LIGHTHOUSE_TOWN_SEPARATION * DEFAULT_LIGHTHOUSE_TOWN_SEPARATION,
            )
        }
    }

    @(test)
    airport_stamp_adds_a_persistent_oriented_terminal_marker :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        terrain.init_project(&editor.project)
        defer terrain.destroy_project(&editor.project)
        x, z := terrain.default_town_center_for_project(&editor.project, 1)
        yaw := f32(math.PI) * .25
        testing.expect(t, airport_stamp_site_valid(editor, x, z, yaw))
        index := airport_stamp_add(editor, x, z, yaw)
        testing.expect(t, index >= 0)
        marker := editor.project.structures[index]
        testing.expect(t, airport_structure_is_stamp(marker))
        testing.expect_value(t, marker.rotation, yaw)
    }

    @(test)
    generated_world_places_complete_named_resident_roster :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        terrain.init_project(&editor.project)
        defer terrain.destroy_project(&editor.project)
        seed_default_island_towns(editor)

        residents := [10]story.Resident{.Niko, .Iva, .Bojan, .Zora, .Vesna, .Petar, .Anica, .Toma, .Lena, .Mirna}
        for resident in residents {
            position, found := world_story_resident_position(editor, resident)
            testing.expect(t, found)
            testing.expect(t, position.y > editor.project.sea_level + .35)
        }

        marta := attendant_spawn_position(editor, {})
        gerta := gerta_spawn_position(editor)
        testing.expect(t, marta.y > editor.project.sea_level + .35)
        testing.expect(t, gerta.y > editor.project.sea_level + .35)
    }

    @(test)
    rondine_marina_spawn_clears_full_footprint :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        terrain.init_project(&editor.project)
        plan := marina.generate(7123)
        position, basis, found := rondine_marina_spawn(editor, &plan)
        testing.expect(t, found)
        testing.expect(t, rondine_footprint_is_clear_water(editor, position, basis))
    }

    @(test)
    hot_state_engine_audio_rebind_restores_process_stream :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        stream := cast(^sdl.AudioStream)(uintptr(1))

        editor.engine_audio.stream = nil
        hot_state_rebind_engine_audio(editor, stream)

        testing.expect(t, editor.engine_audio.stream == stream)
    }
}
