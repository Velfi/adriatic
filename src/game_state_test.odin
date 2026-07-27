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
}
