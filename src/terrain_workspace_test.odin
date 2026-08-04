package main

import terrain "../packages/terrain"
import "core:testing"

@(test)
terrain_workspace_defaults_keep_seabed_policy_tool_specific :: proc(t: ^testing.T) {
    state: Terrain_Sculpt_State
    terrain_authoring_defaults(&state, 3)
    testing.expect_value(t, state.family, Terrain_Family.Landmass)
    testing.expect_value(t, state.action, Terrain_Action.Coast)
    testing.expect(t, state.settings[int(Terrain_Action.Coast)].affect_seabed)
    testing.expect(t, state.settings[int(Terrain_Action.Shelf)].affect_seabed)
    testing.expect(t, !state.settings[int(Terrain_Action.Ridge)].affect_seabed)
    testing.expect_value(t, state.settings[int(Terrain_Action.Coast)].brush_strength, f32(.10))
    testing.expect_value(t, state.settings[int(Terrain_Action.Terrace)].terrace_reference, f32(3))
}

@(test)
terrain_workspace_normalizes_legacy_tools_without_fixture_schema_changes :: proc(t: ^testing.T) {
    editor := new(Editor); defer free(editor)
    editor.authoring_tool = .Smooth
    terrain_authoring_normalize_legacy_selection(editor)
    testing.expect_value(t, editor.authoring_tool, Authoring_Tool.Sculpt)
    testing.expect_value(t, editor.terrain_sculpt.family, Terrain_Family.Surface)
    testing.expect_value(t, editor.terrain_sculpt.action, Terrain_Action.Relax)
    editor.authoring_tool = .Cliff
    terrain_authoring_normalize_legacy_selection(editor)
    testing.expect_value(t, editor.terrain_sculpt.action, Terrain_Action.Ridge)
    testing.expect_value(
        t,
        editor.terrain_sculpt.settings[int(Terrain_Action.Ridge)].profile,
        terrain.Authoring_Profile.Cliff,
    )
}

@(test)
terrain_workspace_classifies_brush_spline_and_area_actions :: proc(t: ^testing.T) {
    testing.expect(t, terrain_action_is_spline(.Ridge))
    testing.expect(t, terrain_action_is_spline(.Grade))
    testing.expect(t, !terrain_action_is_spline(.Erode))
    testing.expect(t, terrain_action_is_area(.Pad))
    testing.expect(t, !terrain_action_is_area(.Terrace))
}
