package tests

import game_input "zelda_engine:game_input"
import "core:testing"

@(test)
input_starts_with_mouse_and_keyboard_active :: proc(t: ^testing.T) {
    state := game_input.default_state()
    testing.expect(t, state.active_device == .Mouse_Keyboard)
    testing.expect(t, !game_input.controller_active(&state))
}

@(test)
meaningful_activity_switches_devices_without_connection_bias :: proc(t: ^testing.T) {
    state := game_input.default_state()
    result := game_input.update(&state, {now_seconds = 1, controller_found = true, button_activity = true})
    testing.expect(t, result.controller_connected)
    testing.expect(t, result.device_changed)
    testing.expect(t, game_input.controller_active(&state))

    result = game_input.update(&state, {now_seconds = 2, controller_found = true, mouse_activity = true})
    testing.expect(t, result.device_changed)
    testing.expect(t, state.active_device == .Mouse_Keyboard)
}

@(test)
small_stick_noise_does_not_change_the_active_device :: proc(t: ^testing.T) {
    state := game_input.default_state()
    _ = game_input.update(&state, {now_seconds = 1, controller_found = true, axes = {.08, -.11, .04, 0, 0, 0}})
    testing.expect(t, state.active_device == .Mouse_Keyboard)
}

@(test)
held_stick_activity_keeps_controller_prompts_during_mouse_jitter :: proc(t: ^testing.T) {
    state := game_input.default_state()
    _ = game_input.update(&state, {now_seconds = 1, controller_found = true, axes = {.8, 0, 0, 0, 0, 0}})
    testing.expect(t, game_input.controller_active(&state))

    _ = game_input.update(
        &state,
        {now_seconds = 2, controller_found = true, mouse_activity = true, axes = {.8, 0, 0, 0, 0, 0}},
    )
    testing.expect(t, game_input.controller_active(&state))
}

@(test)
disconnect_only_requests_pause_for_the_active_controller :: proc(t: ^testing.T) {
    state := game_input.default_state()
    _ = game_input.update(&state, {now_seconds = 1, controller_found = true, button_activity = true})
    result := game_input.update(&state, {now_seconds = 2})
    testing.expect(t, result.controller_disconnected)
    testing.expect(t, result.pause_for_disconnect)

    state = game_input.default_state()
    _ = game_input.update(&state, {now_seconds = 1, controller_found = true})
    result = game_input.update(&state, {now_seconds = 2})
    testing.expect(t, result.controller_disconnected)
    testing.expect(t, !result.pause_for_disconnect)
}

@(test)
menu_axis_has_press_release_and_repeat_hysteresis :: proc(t: ^testing.T) {
    repeater: game_input.Axis_Repeater
    testing.expect(t, game_input.axis_repeat_step(&repeater, .7, 0) == 1)
    testing.expect(t, game_input.axis_repeat_step(&repeater, .7, .2) == 0)
    testing.expect(t, game_input.axis_repeat_step(&repeater, .7, .15) == 1)
    testing.expect(t, game_input.axis_repeat_step(&repeater, .4, .05) == 0)
    testing.expect(t, game_input.axis_repeat_step(&repeater, .1, .05) == 0)
    testing.expect(t, game_input.axis_repeat_step(&repeater, -.8, 0) == -1)
}

@(test)
face_labels_follow_controller_layout :: proc(t: ^testing.T) {
    testing.expect(t, game_input.face_button_label(.Xbox, .South) == "A")
    testing.expect(t, game_input.face_button_label(.PlayStation, .West) == "SQUARE")
    testing.expect(t, game_input.face_button_label(.Nintendo, .South) == "B")
}
