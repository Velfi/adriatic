package main

import flight "../packages/flight"
import third_person "../packages/third_person"
import "core:math"
import "core:math/linalg"
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

@(test)
sdf_obstacle_selected_property_edits_are_bounded_and_stable :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)

    testing.expect_value(t, sdf_obstacle_add_at(editor, {}), 0)
    testing.expect(t, editor.sdf_obstacle_interaction.inspector_euler_valid)
    testing.expect(t, sdf_obstacle_set_position(editor, {SDF_OBSTACLE_POSITION_LIMIT * 2, -SDF_OBSTACLE_POSITION_LIMIT * 2, 17}))
    testing.expect_value(
        t,
        editor.sdf_obstacles[0].position,
        flight.Vec3{SDF_OBSTACLE_POSITION_LIMIT, -SDF_OBSTACLE_POSITION_LIMIT, 17},
    )
    testing.expect(t, sdf_obstacle_set_scale(editor, {-1, 3, .001}))
    testing.expect_value(
        t,
        editor.sdf_obstacles[0].scale,
        flight.Vec3{SDF_OBSTACLE_MINIMUM_SCALE, 3, SDF_OBSTACLE_MINIMUM_SCALE},
    )
    testing.expect(t, sdf_obstacle_set_major_radius(editor, -1))
    testing.expect(t, sdf_obstacle_set_tube_radius(editor, 999))
    testing.expect_value(t, editor.sdf_obstacles[0].major_radius, SDF_OBSTACLE_MINIMUM_RADIUS)
    testing.expect_value(t, editor.sdf_obstacles[0].tube_radius, SDF_OBSTACLE_MAXIMUM_RADIUS)
    testing.expect(t, sdf_obstacle_set_color_rgb(editor, {17, 31, 255}))
    testing.expect_value(t, editor.sdf_obstacles[0].color, [4]u8{17, 31, 255, 255})

    euler := flight.Vec3{20, 89.5, -15}
    testing.expect(t, sdf_obstacle_set_rotation_euler_degrees(editor, euler))
    rotation := editor.sdf_obstacles[0].rotation
    testing.expect(t, fixture_editor_orientation_valid(rotation))
    testing.expect(t, math.abs(linalg.dot(rotation, rotation) - 1) < .0001)
    testing.expect_value(t, editor.sdf_obstacle_interaction.inspector_euler, euler)
    testing.expect(t, sdf_obstacle_select(editor, 0))
    cached := editor.sdf_obstacle_interaction.inspector_euler
    rebuilt := linalg.quaternion_from_euler_angles(
        cached.x * f32(math.PI) / 180,
        cached.y * f32(math.PI) / 180,
        cached.z * f32(math.PI) / 180,
        .XYZ,
    )
    testing.expect(t, fixture_editor_vec3_finite(cached))
    testing.expect(t, math.abs(linalg.dot(rotation, flight.normalize_orientation(rebuilt))) > .9999)
    testing.expect(t, !sdf_obstacle_set_rotation_euler_degrees(editor, {math.QNAN_F32, 0, 0}))
    testing.expect_value(t, editor.sdf_obstacles[0].rotation, rotation)

    before := editor.sdf_obstacles[0]
    editor.sdf_obstacle_selected = -1
    testing.expect(t, !sdf_obstacle_set_position(editor, {1, 2, 3}))
    testing.expect(t, !sdf_obstacle_set_scale(editor, {2, 2, 2}))
    testing.expect(t, !sdf_obstacle_set_major_radius(editor, 2))
    testing.expect(t, !sdf_obstacle_set_tube_radius(editor, 2))
    testing.expect(t, !sdf_obstacle_set_color_rgb(editor, {1, 2, 3}))
    testing.expect(t, !sdf_obstacle_set_rotation_euler_degrees(editor, {1, 2, 3}))
    testing.expect_value(t, editor.sdf_obstacles[0], before)
}
