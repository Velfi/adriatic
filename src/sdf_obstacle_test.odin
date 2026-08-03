package main

import flight "../packages/flight"
import third_person "../packages/third_person"
import "core:math"
import "core:testing"

@(test)
sdf_obstacle_crud_preserves_the_compact_fixture_array :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)

    testing.expect_value(t, sdf_obstacle_add_at(editor, {1, 2, 3}), 0)
    testing.expect_value(t, sdf_obstacle_add_at(editor, {4, 5, 6}), 1)
    testing.expect_value(t, sdf_obstacle_add_at(editor, {7, 8, 9}), 2)
    testing.expect(t, editor.sdf_obstacle_count == 3 && editor.sdf_obstacle_selected == 2)
    testing.expect(t, editor.sdf_obstacles[0].rotation == flight.identity_orientation())
    testing.expect(t, editor.sdf_obstacles[0].scale == flight.Vec3{1, 1, 1})
    testing.expect(t, editor.sdf_obstacles[0].color != editor.sdf_obstacles[1].color)

    testing.expect(t, sdf_obstacle_select(editor, 1))
    testing.expect(t, sdf_obstacle_delete_selected(editor))
    testing.expect(t, editor.sdf_obstacle_count == 2 && editor.sdf_obstacle_selected == 1)
    testing.expect(t, editor.sdf_obstacles[1].position == flight.Vec3{7, 8, 9})

    editor.sdf_obstacle_count = SDF_OBSTACLE_CAPACITY
    testing.expect_value(t, sdf_obstacle_add_at(editor, {}), -1)
}

@(test)
sdf_obstacle_sdf_and_ray_pick_choose_the_nearest_torus :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)

    near := sdf_obstacle_default({}, 0)
    far := sdf_obstacle_default({0, 0, 8}, 1)
    editor.sdf_obstacles[0] = near
    editor.sdf_obstacles[1] = far
    editor.sdf_obstacle_count = 2

    testing.expect(t, math.abs(sdf_obstacle_world_distance(near, {3.75, 0, 0})) < .0001)
    hit_distance, hit := sdf_obstacle_ray_hit(near, third_person.Vec3{0, 0, -10}, {0, 0, 1}, 100)
    testing.expect(t, hit && hit_distance > 6 && hit_distance < 7)
    testing.expect_value(t, sdf_obstacle_pick_ray(editor, {0, 0, -10}, {0, 0, 1}), 0)
}
