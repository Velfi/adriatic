package main

import story "../packages/story"
import terrain "../packages/terrain"
import vehicles "../packages/vehicles"
import "core:testing"

when ODIN_TEST {
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
}
