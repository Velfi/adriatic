package main

import story "../packages/story"
import terrain "../packages/terrain"
import vehicles "../packages/vehicles"
import marina "../packages/marina"
import "core:testing"
import sdl "vendor:sdl3"

when ODIN_TEST {
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
        _, large_valid := clipmap_center_offset(
            {0, 0},
            {f32(CLIPMAP_GRID_RESOLUTION) * 2, 0},
            2,
        )
        testing.expect(t, !large_valid)
        _, unaligned_valid := clipmap_center_offset({0, 0}, {1, 0}, 2)
        testing.expect(t, !unaligned_valid)
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
                testing.expect_value(
                    t,
                    hole[0],
                    CLIPMAP_GRID_RESOLUTION / 4 + (offset_x > 0 ? 1 : 0),
                )
                testing.expect_value(
                    t,
                    hole[1],
                    CLIPMAP_GRID_RESOLUTION / 4 + (offset_z > 0 ? 1 : 0),
                )
            }
        }
    }

    @(test)
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
        player_place(editor, spawn, .Startup, .75)

        testing.expect_value(t, editor.player.position, spawn)
        testing.expect_value(t, editor.pilot.position, spawn)
        testing.expect_value(t, editor.player.facing_yaw_radians, f32(.75))
        testing.expect_value(t, editor.pilot.facing_yaw_radians, f32(.75))
        testing.expect_value(t, editor.pilot.mode, vehicles.Occupancy_Mode.On_Foot)
        testing.expect_value(t, editor.player_placement_reason, Player_Placement_Reason.Startup)
        testing.expect_value(t, editor.player_placement_revision, u64(1))

        // This is the lifecycle guard that catches the original bug: a scene
        // position differing from the cached physics position must be
        // teleported before the next character step can overwrite it.
        testing.expect(t, gameplay_physics_player_needs_teleport(spawn, {}, true))
        testing.expect(t, !gameplay_physics_player_needs_teleport(spawn, spawn, true))
        testing.expect(t, gameplay_physics_player_needs_teleport(spawn, spawn, false))
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

        seed_default_island_marinas(editor)

        testing.expect_value(t, editor.default_marina_count, len(terrain.DEFAULT_ISLAND_SIGNS))
        west_found, east_found := false, false
        for plan, index in editor.default_marinas[:editor.default_marina_count] {
            testing.expect(t, plan.valid)
            west_found = west_found || editor.default_marina_islands[index] == .West
            east_found = east_found || editor.default_marina_islands[index] == .East
        }
        testing.expect(t, west_found)
        testing.expect(t, east_found)
    }

    @(test)
old_hot_state_aircraft_fleet_gains_rondine_and_rebinds_vehicles :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        terrain.init_project(&editor.project)
        editor.aircraft.count = 3
        editor.aircraft.slots[0] = {.Postale, "Postale", nil, true}
        editor.aircraft.slots[1] = {.Libellula, "Libellula", nil, true}
        editor.aircraft.slots[2] = {.Libellula_Mk2, "Libellula Mk2", nil, false}

        hot_state_rebind_aircraft_fleet(editor)

        testing.expect_value(t, editor.aircraft.count, 4)
        testing.expect(
            t,
            vehicles.aircraft_fleet_slot(&editor.aircraft, .Postale).vehicle ==
                &editor.postale.vehicle,
        )
        testing.expect(
            t,
            vehicles.aircraft_fleet_slot(&editor.aircraft, .Libellula).vehicle ==
                &editor.libellula.vehicle,
        )
        rondine := vehicles.aircraft_fleet_slot(&editor.aircraft, .Rondine)
        testing.expect(t, rondine != nil)
        testing.expect(t, rondine.vehicle == &editor.rondine.vehicle)
        testing.expect(t, !rondine.available)
        testing.expect(t, editor.rondine.vehicle.locked)
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
