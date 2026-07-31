package main

import "core:testing"

@(test)
rock_lab_is_registered_and_uses_stable_material_id :: proc(t: ^testing.T) {
    definition := lab_scene_find("rock")
    testing.expect(t, definition != nil)
    testing.expect(t, definition.configure != nil)
    testing.expect(t, definition.world_overlay != nil)
    testing.expect_value(t, u32(World_Material_Kind.Rock), u32(25))
}

@(test)
rock_lab_edge_control_has_true_off_state :: proc(t: ^testing.T) {
    rock_lab.edge_strength = 1
    rock_lab_set_slider(0, 0)
    testing.expect_value(t, rock_lab.edge_strength, f32(0))
}
