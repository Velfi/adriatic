package main

import terrain "../packages/terrain"
import "core:testing"

@(test)
rock_tool_selects_a_constrained_rock_brush :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)
    editor.structure_auto_kind = true
    editor.structure_kind = .Mountain

    authoring_select_rock_tool(editor)

    testing.expect_value(t, editor.authoring_tool, Authoring_Tool.Formations)
    testing.expect(t, editor.rock_placement_mode)
    testing.expect(t, !editor.structure_auto_kind)
    testing.expect_value(t, editor.structure_kind, terrain.Formation_Kind.Rock)
    testing.expect_value(t, editor.tool, terrain.Tool.Structure)
}

@(test)
rock_tool_targets_only_rocks_for_erasure :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)
    authoring_select_rock_tool(editor)

    testing.expect(t, formation_brush_is_target(editor, .Rock))
    testing.expect(t, !formation_brush_is_target(editor, .Mountain))
    testing.expect(t, !formation_brush_is_target(editor, .Foliage))
    testing.expect(t, !formation_brush_is_target(editor, .Architecture))
}

@(test)
selecting_another_tool_exits_rock_placement :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)
    authoring_select_rock_tool(editor)
    authoring_select_tool(editor, .Paint)

    testing.expect(t, !editor.rock_placement_mode)
    testing.expect_value(t, editor.authoring_tool, Authoring_Tool.Paint)
}

@(test)
selection_tool_is_selection_only_session_state :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)
    editor.authoring_tool = .Paint
    editor.tool = .Paint
    editor.structure_placing = true
    editor.structure_moving = true

    authoring_select_selection_tool(editor)

    testing.expect(t, editor.selection_tool_active)
    testing.expect_value(t, editor.tool, terrain.Tool.Structure)
    testing.expect(t, !editor.structure_placing)
    testing.expect(t, !editor.structure_moving)

    authoring_select_tool(editor, .Paint)
    testing.expect(t, !editor.selection_tool_active)
}

@(test)
rock_tool_uses_the_authored_mesh_marker_and_complete_catalog :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)
    for variant in 0 ..< 3 {
        editor.rock_material_variant = variant
        testing.expect_value(t, rock_tool_color(editor)[3], u8(254))
    }
    testing.expect_value(t, len(CLIFF_ROCK_ASSET_PATHS), CLIFF_ROCK_ASSET_COUNT)
}
