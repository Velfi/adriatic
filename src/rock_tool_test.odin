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
selection_move_gizmo_uses_the_group_bounds_and_axes :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)
    terrain.init_project(&editor.project)
    defer terrain.destroy_project(&editor.project)
    editor.selection_tool_active = true
    first := terrain.add_structure(&editor.project, terrain.Structure{center_x = 10, center_z = 20, width = 8, depth = 6, height = 4})
    second := terrain.add_structure(&editor.project, terrain.Structure{center_x = 30, center_z = 40, width = 10, depth = 12, height = 7})
    structure_selection_set_index(editor, first)
    structure_selection_add_group(editor, editor.project.structures[second].group_id)

    bounds, ok := structure_selection_bounds(editor)
    testing.expect(t, ok)
    testing.expect_value(t, bounds.minimum_x, f32(6))
    testing.expect_value(t, bounds.maximum_x, f32(35))
    testing.expect_value(t, bounds.minimum_z, f32(17))
    testing.expect_value(t, bounds.maximum_z, f32(46))

    center_x := (bounds.minimum_x + bounds.maximum_x) * .5
    center_z := (bounds.minimum_z + bounds.maximum_z) * .5
    size := structure_move_gizmo_size(editor, bounds)
    axis, hit := structure_move_gizmo_hit(editor, center_x + size * .7, center_z)
    testing.expect(t, hit)
    testing.expect_value(t, axis, u8(1))
    axis, hit = structure_move_gizmo_hit(editor, center_x, center_z + size * .7)
    testing.expect(t, hit)
    testing.expect_value(t, axis, u8(2))
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
