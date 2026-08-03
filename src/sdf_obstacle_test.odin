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
    testing.expect(t, !sdf_obstacle_modal_start_allowed(editor, false))
    testing.expect(t, sdf_obstacle_modal_start_allowed(editor, true))
    editor.sdf_obstacle_selected = -1
    testing.expect(t, !sdf_obstacle_set_position(editor, {1, 2, 3}))
    testing.expect(t, !sdf_obstacle_set_scale(editor, {2, 2, 2}))
    testing.expect(t, !sdf_obstacle_set_major_radius(editor, 2))
    testing.expect(t, !sdf_obstacle_set_tube_radius(editor, 2))
    testing.expect(t, !sdf_obstacle_set_color_rgb(editor, {1, 2, 3}))
    testing.expect(t, !sdf_obstacle_set_rotation_euler_degrees(editor, {1, 2, 3}))
    testing.expect_value(t, editor.sdf_obstacles[0], before)
}

@(test)
sdf_obstacle_translation_math_and_modal_lifecycle :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)
    testing.expect_value(t, sdf_obstacle_add_at(editor, {3, 4, 5}), 0)
    before := editor.sdf_obstacles[0]

    axis_position, axis_ok := sdf_obstacle_axis_drag_position(before.position, .X, {0, 8, -10}, {0, 0, 1})
    testing.expect(t, axis_ok)
    testing.expect_value(t, axis_position.y, before.position.y)
    testing.expect_value(t, axis_position.z, before.position.z)
    free_position, free_ok := sdf_obstacle_free_drag_position(before.position, {3, 4, -10}, {0, 0, 1}, {0, 0, 1})
    testing.expect(t, free_ok)
    testing.expect_value(t, free_position, before.position)

    projection_camera := Perspective_Camera{position = {}, right = {1, 0, 0}, up = {0, 1, 0}, forward = {0, 0, 1}, focal_length = 1.35}
    near := flight.Vec3{0, 0, 10}
    far := flight.Vec3{0, 0, 100}
    near_size := sdf_obstacle_gizmo_size(projection_camera, near, 1280, 720)
    far_size := sdf_obstacle_gizmo_size(projection_camera, far, 1280, 720)
    near_center := project_3d(projection_camera, near, 1280, 720)
    near_endpoint := project_3d(projection_camera, near + flight.Vec3{near_size, 0, 0}, 1280, 720)
    far_center := project_3d(projection_camera, far, 1280, 720)
    far_endpoint := project_3d(projection_camera, far + flight.Vec3{far_size, 0, 0}, 1280, 720)
    testing.expect(t, math.abs((near_endpoint.position.x - near_center.position.x) - SDF_OBSTACLE_GIZMO_AXIS_PIXELS) < .001)
    testing.expect(t, math.abs((far_endpoint.position.x - far_center.position.x) - SDF_OBSTACLE_GIZMO_AXIS_PIXELS) < .001)
    showcase_camera := projection_camera
    showcase_camera.focal_length = VEHICLE_SHOWCASE_FOCAL_LENGTH
    showcase_size := sdf_obstacle_gizmo_size(showcase_camera, far, 1280, 720)
    showcase_endpoint := project_3d(showcase_camera, far + flight.Vec3{showcase_size, 0, 0}, 1280, 720)
    testing.expect(t, math.abs((showcase_endpoint.position.x - far_center.position.x) - SDF_OBSTACLE_GIZMO_AXIS_PIXELS) < .001)

    testing.expect(t, sdf_obstacle_modal_begin(editor, .X))
    testing.expect(t, sdf_obstacle_modal_active(editor))
    testing.expect_value(t, editor.sdf_obstacle_interaction.transform_snapshot_slot, 0)
    testing.expect(t, sdf_obstacle_set_position(editor, {40, 40, 40}))
    sdf_obstacle_modal_finish(editor, true)
    testing.expect(t, !sdf_obstacle_modal_active(editor))
    testing.expect_value(t, editor.sdf_obstacles[0], before)

    testing.expect(t, sdf_obstacle_modal_begin(editor, .X))
    parallel_camera := Perspective_Camera{position = {3, 4, -10}}
    testing.expect(t, !sdf_obstacle_modal_update(editor, parallel_camera, {1, 0, 0}))
    sdf_obstacle_modal_finish(editor, true)
    testing.expect(t, !sdf_obstacle_modal_active(editor))

    testing.expect_value(t, sdf_obstacle_add_at(editor, {12, 13, 14}), 1)
    second_before := editor.sdf_obstacles[1]
    testing.expect(t, sdf_obstacle_select(editor, 0))
    testing.expect(t, sdf_obstacle_modal_begin(editor, .X))
    testing.expect(t, sdf_obstacle_set_position(editor, {40, 40, 40}))
    testing.expect(t, sdf_obstacle_select(editor, 1))
    testing.expect(t, !sdf_obstacle_modal_selection_matches(editor))
    sdf_obstacle_modal_finish(editor, true)
    testing.expect_value(t, editor.sdf_obstacles[0], before)
    testing.expect_value(t, editor.sdf_obstacles[1], second_before)
    testing.expect_value(t, editor.sdf_obstacle_interaction.transform_snapshot_slot, -1)

    testing.expect(t, sdf_obstacle_select(editor, 0))
    testing.expect(t, sdf_obstacle_modal_begin(editor, .None))
    camera := Perspective_Camera{position = {0, 8, -10}, forward = {0, 0, 1}}
    testing.expect(t, sdf_obstacle_modal_update(editor, camera, {0, 0, 1}))
    testing.expect_value(t, editor.sdf_obstacles[0].position, before.position)
    testing.expect(t, sdf_obstacle_modal_set_axis(editor, .X, camera, {0, 0, 1}))
    testing.expect_value(t, editor.sdf_obstacle_interaction.constrained_axis, SDF_Obstacle_Axis.X)
    testing.expect(t, sdf_obstacle_modal_update(editor, camera, {0, 0, 1}))
    testing.expect_value(t, editor.sdf_obstacles[0].position, before.position)
    sdf_obstacle_modal_finish(editor, false)
    testing.expect(t, sdf_obstacle_modal_begin(editor, .X))
    testing.expect(t, sdf_obstacle_modal_update(editor, camera, {0, 0, 1}))
    testing.expect_value(t, editor.sdf_obstacles[0].position, before.position)
    moved_camera := Perspective_Camera{position = {6, 8, -10}}
    testing.expect(t, sdf_obstacle_modal_update(editor, moved_camera, {0, 0, 1}))
    testing.expect_value(t, editor.sdf_obstacles[0].position, flight.Vec3{9, 4, 5})
    sdf_obstacle_modal_finish(editor, false)
    testing.expect_value(t, editor.sdf_obstacles[0].position, flight.Vec3{9, 4, 5})
}
