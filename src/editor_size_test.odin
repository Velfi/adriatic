package main

import "core:testing"

@(test)
editor_runtime_state_stays_indirect :: proc(t: ^testing.T) {
    testing.expectf(
        t,
        size_of(Editor) < 40 * 1024 * 1024,
        "Editor retains %d bytes inline; keep runtime histories and paint storage indirect",
        size_of(Editor),
    )
}

@(test)
editor_history_storage_is_lazy_and_released :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)

    testing.expect(t, editor.structure_undo[0] == nil && editor.terrain_undo[0] == nil)
    structure_history_push_undo(editor)
    terrain_history_push_undo(editor)
    testing.expect(t, editor.structure_undo_count == 1 && editor.structure_undo[0] != nil)
    testing.expect(t, editor.terrain_undo_count == 1 && editor.terrain_undo[0] != nil)

    structure_history_storage_destroy(editor)
    testing.expect(t, editor.structure_undo_count == 0 && editor.structure_undo[0] == nil)
    testing.expect(t, editor.terrain_undo_count == 0 && editor.terrain_undo[0] == nil)
}

@(test)
terrain_history_capacity_reuses_the_oldest_allocation :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)
    defer structure_history_storage_destroy(editor)

    terrain_history_push_undo(editor)
    oldest := editor.terrain_undo[0]
    for _ in 1 ..= TERRAIN_HISTORY_CAPACITY do terrain_history_push_undo(editor)

    testing.expect(t, editor.terrain_undo_count == TERRAIN_HISTORY_CAPACITY)
    testing.expect(t, editor.terrain_undo[TERRAIN_HISTORY_CAPACITY - 1] == oldest)
    for state, index in editor.terrain_undo {
        testing.expect(t, state != nil)
        for other in index + 1 ..< TERRAIN_HISTORY_CAPACITY {
            testing.expect(t, state != editor.terrain_undo[other])
        }
    }
}
