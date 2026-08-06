package main

import third_person "zelda_engine:third_person"
import canvas2d "zelda_engine:canvas2d"

fixture_note_placement_index := -1
fixture_note_placement_original: Fixture_Note
fixture_notes_dirty := false
fixture_notes_save_due_at: f64
fixture_notes_save_failed := false

FIXTURE_NOTES_AUTOSAVE_DEBOUNCE_SECONDS :: 0.65
FIXTURE_NOTES_AUTOSAVE_RETRY_SECONDS :: 3.0

fixture_notes_mark_dirty :: #force_inline proc() {
    fixture_notes_dirty = true
    fixture_notes_save_failed = false
    fixture_notes_save_due_at = canvas2d.GetTime() + FIXTURE_NOTES_AUTOSAVE_DEBOUNCE_SECONDS
}

fixture_notes_mark_saved :: #force_inline proc() {
    fixture_notes_dirty = false
    fixture_notes_save_failed = false
    fixture_notes_save_due_at = 0
}

fixture_note_placement_active :: #force_inline proc() -> bool {
    return fixture_note_placement_index >= 0
}

fixture_note_structure_position :: proc(editor: ^Editor, target_id: u64) -> (third_person.Vec3, bool) {
    if editor == nil || target_id == 0 do return {}, false
    for index in 0 ..< editor.project.structure_count {
        structure := &editor.project.structures[index]
        if structure.id == target_id {
            return {structure.center_x, structure.base_y + structure.height + 2, structure.center_z}, true
        }
    }
    return {}, false
}

fixture_note_target_position :: proc(editor: ^Editor, note: ^Fixture_Note) -> third_person.Vec3 {
    if note.target == .Structure {
        if position, ok := fixture_note_structure_position(editor, note.target_id); ok do return position
    }
    return note.fallback_position
}

fixture_note_add :: proc(editor: ^Editor, target: Fixture_Note_Target) -> ^Fixture_Note {
    if editor == nil || editor.note_count < 0 || editor.note_count >= FIXTURE_NOTE_CAPACITY do return nil
    note := &editor.notes[editor.note_count]
    note^ = {
        target            = target,
        fallback_position = editor.editor_focus,
    }
    if target == .Structure &&
       editor.structure_selected >= 0 &&
       editor.structure_selected < editor.project.structure_count {
        structure := &editor.project.structures[editor.structure_selected]
        note.target_id = structure.id
        note.fallback_position = {structure.center_x, structure.base_y + structure.height + 2, structure.center_z}
    }
    editor.note_count += 1
    fixture_notes_mark_dirty()
    return note
}

fixture_note_remove :: proc(editor: ^Editor, index: int) {
    if editor == nil || index < 0 || index >= editor.note_count do return
    for move_index in index + 1 ..< editor.note_count do editor.notes[move_index - 1] = editor.notes[move_index]
    editor.note_count -= 1
    editor.notes[editor.note_count] = {}
    fixture_notes_mark_dirty()
}

fixture_note_retarget :: proc(editor: ^Editor, note: ^Fixture_Note, target: Fixture_Note_Target) -> bool {
    if editor == nil || note == nil do return false
    if target == .Structure {
        if editor.structure_selected < 0 || editor.structure_selected >= editor.project.structure_count do return false
        structure := &editor.project.structures[editor.structure_selected]
        note.target = .Structure
        note.target_id = structure.id
        note.fallback_position = {structure.center_x, structure.base_y + structure.height + 2, structure.center_z}
    } else {
        note.target = .Scene
        note.target_id = 0
        note.fallback_position = editor.editor_focus
    }
    fixture_notes_mark_dirty()
    return true
}

fixture_note_focus :: proc(editor: ^Editor, note: ^Fixture_Note) {
    if editor == nil || note == nil do return
    editor.editor_focus = fixture_note_target_position(editor, note)
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
}

fixture_note_placement_begin :: proc(editor: ^Editor, index: int) -> bool {
    if editor == nil || index < 0 || index >= editor.note_count do return false
    fixture_note_placement_index = index
    fixture_note_placement_original = editor.notes[index]
    editor.notes_visible = true
    return true
}

fixture_note_placement_cancel :: proc(editor: ^Editor) {
    if editor != nil && fixture_note_placement_index >= 0 && fixture_note_placement_index < editor.note_count {
        editor.notes[fixture_note_placement_index] = fixture_note_placement_original
    }
    fixture_note_placement_index = -1
    fixture_note_placement_original = {}
}

fixture_note_placement_process_input :: proc(editor: ^Editor, cursor_hit: bool) -> bool {
    if !fixture_note_placement_active() do return false
    index := fixture_note_placement_index
    if editor == nil || index >= editor.note_count {
        fixture_note_placement_cancel(editor)
        return true
    }
    if canvas2d.IsKeyPressed(.ESCAPE) || canvas2d.IsMouseButtonPressed(.RIGHT) {
        fixture_note_placement_cancel(editor)
        return true
    }
    if cursor_hit {
        note := &editor.notes[index]
        note.target = .Scene
        note.target_id = 0
        note.fallback_position = {editor.cursor_world_x, editor.cursor_height + 2, editor.cursor_world_z}
        if canvas2d.IsMouseButtonPressed(.LEFT) {
            fixture_note_placement_index = -1
            fixture_note_placement_original = {}
            fixture_notes_mark_dirty()
        }
    }
    return true
}

fixture_notes_before_fixture_replace :: proc(editor: ^Editor) {
    if fixture_note_placement_active() do fixture_note_placement_cancel(editor)
}

fixture_notes_after_fixture_replace :: proc() {
    fixture_note_placement_index = -1
    fixture_note_placement_original = {}
    fixture_notes_mark_saved()
}

fixture_notes_save :: proc(editor: ^Editor) -> bool {
    if editor == nil do return false
    path := fixture_editor_current_path(editor)
    if path == "" {
        default_path, _, resolved := fixture_editor_store_default_path(context.temp_allocator)
        if !resolved {
            fixture_notes_save_failed = true
            fixture_notes_save_due_at = canvas2d.GetTime() + FIXTURE_NOTES_AUTOSAVE_RETRY_SECONDS
            terrain_file_feedback(editor, "FIXTURE NOTES SAVE FAILED")
            return false
        }
        path = default_path
    }
    saved := fixture_editor_save_path(editor, path)
    if saved {
        fixture_notes_mark_saved()
    } else {
        fixture_notes_save_failed = true
        fixture_notes_save_due_at = canvas2d.GetTime() + FIXTURE_NOTES_AUTOSAVE_RETRY_SECONDS
        terrain_file_feedback(editor, "FIXTURE NOTES SAVE FAILED")
    }
    return saved
}

fixture_notes_process_autosave :: proc(editor: ^Editor) {
    if editor == nil ||
       !fixture_notes_dirty ||
       fixture_note_placement_active() ||
       canvas2d.GetTime() < fixture_notes_save_due_at {
        return
    }
    _ = fixture_notes_save(editor)
}

fixture_notes_flush_autosave :: proc(editor: ^Editor) {
    if editor == nil do return
    if fixture_note_placement_active() do fixture_note_placement_cancel(editor)
    if fixture_notes_dirty do _ = fixture_notes_save(editor)
}

fixture_notes_draw :: proc(editor: ^Editor, width, height: i32) {
    if editor == nil || !editor.notes_visible || editor.note_count <= 0 do return
    camera := perspective_camera(editor.camera_pose)
    for index in 0 ..< min(editor.note_count, FIXTURE_NOTE_CAPACITY) {
        note := &editor.notes[index]
        placing := index == fixture_note_placement_index
        if note.text[0] == 0 && !placing do continue
        projected := project_3d(camera, fixture_note_target_position(editor, note), width, height)
        on_screen :=
            projected.visible &&
            projected.position.x >= -280 &&
            projected.position.x <= f32(width) + 20 &&
            projected.position.y >= -80 &&
            projected.position.y <= f32(height) + 20
        if !on_screen do continue
        text: cstring = placing && note.text[0] == 0 ? "Click to place note" : cstring(&note.text[0])
        font := canvas2d.Font{}
        font_size, spacing, line_height := f32(13), f32(1), f32(17)
        text_max_width, panel_max_height := f32(320), f32(140)
        measured := canvas2d.MeasureTextWrappedEx(font, text, font_size, spacing, text_max_width, line_height)
        panel_width := max(measured.size.x + 20, f32(110))
        panel_height := min(max(measured.size.y + 18, f32(34)), panel_max_height)
        panel_x := clamp(projected.position.x + 10, f32(8), max(f32(width) - panel_width - 8, f32(8)))
        panel_y := clamp(projected.position.y - panel_height * .5, f32(8), max(f32(height) - panel_height - 8, f32(8)))
        panel := canvas2d.Rectangle{panel_x, panel_y, panel_width, panel_height}
        canvas2d.DrawLineEx(projected.position, {panel.x, panel.y + panel.height * .5}, 2, {245, 194, 82, 220})
        canvas2d.DrawCircleHatched(projected.position, 4, {255, 215, 105, 255}, canvas2d.HATCH_DISABLED, 20)
        canvas2d.DrawRectangleRounded(panel, .18, 6, {20, 25, 30, 228})
        canvas2d.DrawRectangleRoundedLinesEx(panel, .18, 6, 1, {245, 194, 82, 235})
        _ = canvas2d.DrawTextWrappedEx(
            font,
            text,
            {panel.x + 10, panel.y + 9, panel.width - 20, panel.height - 18},
            font_size,
            spacing,
            line_height,
            {245, 241, 223, 255},
        )
    }
}
