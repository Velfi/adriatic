package main

import "core:testing"

when ODIN_TEST {
    @(test)
    console_executes_live_get_set_and_history :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        editor.project.sea_level = 1

        console_execute(editor, "set world.sea_level 4.5")
        testing.expect_value(t, editor.project.sea_level, f32(4.5))
        testing.expect_value(t, editor.project.revision, u64(1))
        testing.expect_value(t, editor.console.history_count, 1)
        testing.expect(t, editor.console.line_count >= 2)

        console_execute(editor, "get world.sea_level")
        testing.expect_value(t, editor.console.history_count, 2)
        latest := (editor.console.line_start + editor.console.line_count - 1) % CONSOLE_LINE_CAPACITY
        testing.expect_value(t, console_line_text(&editor.console.lines[latest]), "world.sea_level = 4.50")
    }

    @(test)
    console_autocomplete_and_history_are_deterministic :: proc(t: ^testing.T) {
        state: Game_Console
        console_set_input(&state, "tele")
        console_completion(&state, true)
        testing.expect_value(t, console_input_text(&state), "teleport ")

        console_push_history(&state, "status")
        console_push_history(&state, "get player.position")
        console_history_move(&state, -1)
        testing.expect_value(t, console_input_text(&state), "get player.position")
        console_history_move(&state, -1)
        testing.expect_value(t, console_input_text(&state), "status")
        console_history_move(&state, 1)
        testing.expect_value(t, console_input_text(&state), "get player.position")
    }

    @(test)
    console_backspace_removes_a_complete_utf8_rune :: proc(t: ^testing.T) {
        state: Game_Console
        console_set_input(&state, "café")
        console_remove_last_rune(&state)
        testing.expect_value(t, console_input_text(&state), "caf")
    }

    @(test)
    console_autocompletes_registered_lab_scenes :: proc(t: ^testing.T) {
        state: Game_Console
        console_set_input(&state, "lab markov-mar")
        console_completion(&state, true)
        testing.expect_value(t, console_input_text(&state), "lab markov-marina ")
        console_set_input(&state, "lab ex")
        console_completion(&state, true)
        testing.expect_value(t, console_input_text(&state), "lab exit ")
    }
}
