package main

import "core:testing"

@(test)
lab_mouse_controls_cover_remaining_keyboard_actions :: proc(t: ^testing.T) {
    _, road_count := lab_mouse_control_keys("road-planning")
    _, island_count := lab_mouse_control_keys("markov-island")
    _, rock_count := lab_mouse_control_keys("rock")
    _, estuary_count := lab_mouse_control_keys("estuary-delta")
    _, dialogue_count := lab_mouse_control_keys("dialogue-sound")
    _, material_count := lab_mouse_control_keys("material")

    testing.expect_value(t, road_count, 10)
    testing.expect_value(t, island_count, 2)
    testing.expect_value(t, rock_count, 3)
    testing.expect_value(t, estuary_count, 5)
    testing.expect_value(t, dialogue_count, 1)
    testing.expect_value(t, material_count, 1)
}

@(test)
lab_mouse_controls_paginate_inside_minimum_capture_size :: proc(t: ^testing.T) {
    keys, count := lab_mouse_control_keys("bridge-generator")
    columns, rows, capacity, button_width, left := lab_mouse_control_layout("bridge-generator", count, 320, 240)

    testing.expect_value(t, count, 16)
    testing.expect_value(t, columns, 1)
    testing.expect_value(t, rows, 4)
    testing.expect_value(t, capacity, 4)
    testing.expect(t, button_width >= 120)
    testing.expect(t, left >= 0)

    for index in 0 ..< capacity {
        bounds := lab_mouse_control_bounds("bridge-generator", index, capacity, 320, 240)
        testing.expect(t, bounds.x >= 0)
        testing.expect(t, bounds.x + bounds.width <= 320)
        testing.expect(t, bounds.y >= 0)
        testing.expect(t, bounds.y + bounds.height <= 240)
        testing.expect(t, keys[index] != .COUNT)
    }
}
