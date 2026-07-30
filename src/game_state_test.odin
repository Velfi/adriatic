package main

import architecture "../packages/architecture"
import buildings "../packages/buildings"
import marina "../packages/marina"
import story "../packages/story"
import terrain "../packages/terrain"
import vehicles "../packages/vehicles"
import "core:testing"
import sdl "vendor:sdl3"

when ODIN_TEST {
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
    sparse_clipmap_transition_uses_a_quarter_width_coarse_hole :: proc(t: ^testing.T) {
        expected_width := CLIPMAP_GRID_RESOLUTION / 4 - 1
        for offset_z in -1 ..= 1 {
            for offset_x in -1 ..= 1 {
                hole := clipmap_ring_hole_bounds({offset_x, offset_z}, 4)
                testing.expect_value(t, hole[2] - hole[0], expected_width)
                testing.expect_value(t, hole[3] - hole[1], expected_width)
                testing.expect_value(t, hole[0], CLIPMAP_GRID_RESOLUTION * 3 / 8 + (offset_x > 0 ? 1 : 0))
                testing.expect_value(t, hole[1], CLIPMAP_GRID_RESOLUTION * 3 / 8 + (offset_z > 0 ? 1 : 0))
            }
        }
    }

    @(test)
    clipmap_inner_grid_doubles_resolution_without_reducing_coverage :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        terrain.init_project(&editor.project)
        defer terrain.destroy_project(&editor.project)
        testing.expect_value(t, clipmap_grid_cell(editor, 0), f32(.5))
        testing.expect_value(t, clipmap_grid_cell(editor, 1), f32(2))
        testing.expect_value(t, clipmap_grid_cell(editor, 2), f32(8))
        testing.expect_value(t, clipmap_grid_resolution(0), CLIPMAP_INNER_GRID_RESOLUTION)
        testing.expect_value(t, clipmap_grid_resolution(1), CLIPMAP_GRID_RESOLUTION)
        inner_coverage := f32(clipmap_grid_resolution(0) - 1) * clipmap_grid_cell(editor, 0)
        former_coverage := f32(CLIPMAP_GRID_RESOLUTION - 1)
        testing.expect_value(t, inner_coverage, former_coverage)
        level_one_coverage := f32(clipmap_grid_resolution(1) - 1) * clipmap_grid_cell(editor, 1)
        level_two_coverage := f32(clipmap_grid_resolution(2) - 1) * clipmap_grid_cell(editor, 2)
        testing.expect_value(t, level_one_coverage, inner_coverage * 2)
        testing.expect_value(t, level_two_coverage, level_one_coverage * 4)
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
    dune_vertex_color_is_smooth_while_fragment_field_remains_bounded :: proc(t: ^testing.T) {
        previous_color := terrain_color(3.2, -.55, 0, 0, 18)
        previous_field := dune_color_field(0, 18)
        minimum_field, maximum_field := previous_field, previous_field
        for x := f32(.5); x <= 80; x += .5 {
            current_color := terrain_color(3.2, -.55, 0, x, 18)
            current_field := dune_color_field(x, 18)
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
        defer terrain.destroy_project(&editor.project)

        seed_default_island_marinas(editor)

        testing.expect_value(t, editor.default_marina_count, len(terrain.DEFAULT_ISLAND_SIGNS))
        west_found, east_found := false, false
        for &plan, index in editor.default_marinas[:editor.default_marina_count] {
            testing.expect(t, plan.valid)
            sign := editor.default_marina_islands[index] == .West ? f32(-1) : f32(1)
            town_x, town_z := terrain.default_town_center(sign)
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
        // Six runway-airport-town links are created with the terrain. Each
        // marina adds one or more terrain-following connector segments.
        testing.expect(t, editor.project.road_graph.edge_count >= 8)
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
    generated_world_places_complete_named_resident_roster :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        terrain.init_project(&editor.project)
        defer terrain.destroy_project(&editor.project)
        seed_default_island_towns(editor)

        residents := [9]story.Resident{.Niko, .Iva, .Bojan, .Zora, .Vesna, .Petar, .Anica, .Toma, .Lena}
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
        testing.expect(t, vehicles.aircraft_fleet_slot(&editor.aircraft, .Postale).vehicle == &editor.postale.vehicle)
        testing.expect(
            t,
            vehicles.aircraft_fleet_slot(&editor.aircraft, .Libellula).vehicle == &editor.libellula.vehicle,
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
