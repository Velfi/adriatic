package main

import "core:testing"
import third_person "zelda_engine:third_person"

when ODIN_TEST {
    @(test)
    world_model_transform_maps_authored_axes_to_named_basis :: proc(t: ^testing.T) {
        origin := third_person.Vec3{10, 20, 30}
        right := third_person.Vec3{0, 0, -1}
        up := third_person.Vec3{0, 1, 0}
        forward := third_person.Vec3{-1, 0, 0}
        transform := world_model_transform_from_basis(origin, right, up, forward)

        testing.expect_value(t, world_model_vertex_world(transform, {1, 0, 0}), origin + right)
        testing.expect_value(t, world_model_vertex_world(transform, {0, 1, 0}), origin + up)
        testing.expect_value(t, world_model_vertex_world(transform, {0, 0, -1}), origin + forward)
        testing.expect_value(t, world_model_normal_world(transform, {0, 0, -1}), forward)
    }
}
