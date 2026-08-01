package main

import "core:testing"
import canvas2d "zelda_engine:canvas2d"

@(test)
fixture_notes_attach_to_stable_structure_identity_and_remove_compacts :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)
    defer fixture_storage_destroy(&editor.fixture)
    resize(&editor.project.structures, 1)
    editor.project.structure_count = 1
    editor.project.structures[0] = {
        id       = 42,
        center_x = 10,
        center_z = 20,
        base_y   = 3,
        height   = 7,
    }
    editor.structure_selected = 0

    attached := fixture_note_add(editor, .Structure)
    testing.expect(t, attached != nil)
    testing.expect(t, editor.note_count == 1)
    testing.expect(t, attached.target_id == 42)
    testing.expect(t, attached.fallback_position == [3]f32{10, 12, 20})

    scene := fixture_note_add(editor, .Scene)
    testing.expect(t, scene != nil)
    scene.text[0] = 's'
    fixture_note_remove(editor, 0)
    testing.expect(t, editor.note_count == 1)
    testing.expect(t, editor.notes[0].target == .Scene)
    testing.expect(t, editor.notes[0].text[0] == 's')
    testing.expect(t, editor.notes[1].text[0] == 0)
}

@(test)
fixture_notes_capacity_and_missing_structure_fallback_are_safe :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)
    editor.structure_selected = -1
    editor.editor_focus = {1, 2, 3}

    for _ in 0 ..< FIXTURE_NOTE_CAPACITY do testing.expect(t, fixture_note_add(editor, .Scene) != nil)
    testing.expect(t, fixture_note_add(editor, .Scene) == nil)

    note := Fixture_Note {
        target            = .Structure,
        target_id         = 999,
        fallback_position = {4, 5, 6},
    }
    testing.expect(t, fixture_note_target_position(editor, &note) == [3]f32{4, 5, 6})
}

@(test)
fixture_notes_can_be_retargeted_without_changing_fixture_shape :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)
    defer fixture_storage_destroy(&editor.fixture)
    resize(&editor.project.structures, 1)
    editor.project.structure_count = 1
    editor.project.structures[0] = {
        id       = 73,
        center_x = 8,
        center_z = 9,
        base_y   = 2,
        height   = 4,
    }
    editor.structure_selected = 0
    editor.editor_focus = {1, 2, 3}
    note := Fixture_Note{}

    testing.expect(t, fixture_note_retarget(editor, &note, .Structure))
    testing.expect(t, note.target == .Structure && note.target_id == 73)
    testing.expect(t, note.fallback_position == [3]f32{8, 8, 9})

    editor.editor_focus = {11, 12, 13}
    testing.expect(t, fixture_note_retarget(editor, &note, .Scene))
    testing.expect(t, note.target == .Scene && note.target_id == 0)
    testing.expect(t, note.fallback_position == [3]f32{11, 12, 13})
}

@(test)
fixture_note_placement_cancel_restores_the_original_anchor :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)
    editor.note_count = 1
    editor.notes[0] = {
        target            = .Structure,
        target_id         = 91,
        fallback_position = {3, 4, 5},
    }

    testing.expect(t, fixture_note_placement_begin(editor, 0))
    testing.expect(t, editor.notes_visible)
    editor.notes[0] = {
        target            = .Scene,
        fallback_position = {8, 9, 10},
    }
    fixture_note_placement_cancel(editor)

    testing.expect(t, !fixture_note_placement_active())
    testing.expect(t, editor.notes[0].target == .Structure)
    testing.expect(t, editor.notes[0].target_id == 91)
    testing.expect(t, editor.notes[0].fallback_position == [3]f32{3, 4, 5})
}

@(test)
fixture_notes_track_dirty_state_and_reset_after_fixture_replace :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)
    fixture_notes_mark_saved()

    testing.expect(t, !fixture_notes_dirty)
    testing.expect(t, fixture_note_add(editor, .Scene) != nil)
    testing.expect(t, fixture_notes_dirty)
    testing.expect(t, fixture_notes_save_due_at > canvas2d.GetTime())
    testing.expect(t, fixture_note_placement_begin(editor, 0))
    editor.notes[0].fallback_position = {20, 30, 40}

    fixture_notes_before_fixture_replace(editor)
    testing.expect(t, !fixture_note_placement_active())
    testing.expect(t, editor.notes[0].fallback_position == [3]f32{})
    fixture_notes_after_fixture_replace()
    testing.expect(t, !fixture_notes_dirty)
}
