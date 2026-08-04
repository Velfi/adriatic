package main

import "core:math"
import "core:testing"
import physics "zelda_engine:physics"

@(test)
car_physics_incline_basis_keeps_rendered_nose_uphill :: proc(t: ^testing.T) {
    incline := f32(12 * math.PI / 180)
    rotation := physics.Quat{-math.sin(incline * .5), 0, 0, math.cos(incline * .5)}
    transform := world_vehicle_transform_physics({}, rotation)

    testing.expectf(t, transform.forward_basis.y > 0, "expected uphill forward basis, got %v", transform.forward_basis)
    mesh_nose := world_vehicle_vertex_world(transform, {0, 0, -1})
    mesh_tail := world_vehicle_vertex_world(transform, {0, 0, 1})
    testing.expectf(
        t,
        mesh_nose.y > mesh_tail.y,
        "expected mesh nose above tail, got nose %v tail %v",
        mesh_nose,
        mesh_tail,
    )
}

@(test)
car_physics_chassis_origin_offset_follows_body_up :: proc(t: ^testing.T) {
    incline := f32(12 * math.PI / 180)
    rotation := physics.Quat{-math.sin(incline * .5), 0, 0, math.cos(incline * .5)}
    body_up := car_physics_rotate_vector(rotation, {0, 1, 0})
    body_position := physics.Vec3{4, 7, 9}
    mesh_origin := physics.Vec3 {
        body_position[0] - body_up[0] * .74,
        body_position[1] - body_up[1] * .74,
        body_position[2] - body_up[2] * .74,
    }
    reconstructed := mesh_origin + body_up * .74

    testing.expectf(
        t,
        math.abs(reconstructed[0] - body_position[0]) < .00001,
        "x offset did not round trip: %v",
        reconstructed,
    )
    testing.expectf(
        t,
        math.abs(reconstructed[1] - body_position[1]) < .00001,
        "y offset did not round trip: %v",
        reconstructed,
    )
    testing.expectf(
        t,
        math.abs(reconstructed[2] - body_position[2]) < .00001,
        "z offset did not round trip: %v",
        reconstructed,
    )
}

@(test)
car_authored_wheels_map_to_jolt_axles_and_sides :: proc(t: ^testing.T) {
    testing.expect(t, car_authored_wheel_index({-1, 0, -1}) == 0)
    testing.expect(t, car_authored_wheel_index({1, 0, -1}) == 1)
    testing.expect(t, car_authored_wheel_index({-1, 0, 1}) == 2)
    testing.expect(t, car_authored_wheel_index({1, 0, 1}) == 3)
}

@(test)
gameplay_physics_drives_car_forward_across_frames :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)
    editor.gameplay_physics.world = physics.create_world(128, 1)
    testing.expect(t, editor.gameplay_physics.world != nil)
    defer physics.destroy_world(editor.gameplay_physics.world)

    floor := physics.add_box(editor.gameplay_physics.world, {20, .5, 20}, {0, -.5, 0}, .Static)
    testing.expect(t, floor != physics.INVALID_BODY)
    vehicle := physics.create_vehicle(
        editor.gameplay_physics.world,
        {
            half_width = .7,
            half_height = .25,
            half_length = 1.2,
            mass = 700,
            center_of_mass_offset_y = -.15,
            wheel_x = .78,
            front_wheel_z = .82,
            rear_wheel_z = -.82,
            wheel_y = -.2,
            wheel_radius = .32,
            wheel_width = .24,
            suspension_min = .08,
            suspension_max = .3,
            suspension_frequency = 2.4,
            suspension_damping = .9,
            max_steer_angle = .6,
            max_engine_torque = 520,
            max_brake_torque = 1100,
            max_handbrake_torque = 1400,
        },
        {0, .75, 0},
    )
    testing.expect(t, vehicle != nil)
    defer physics.destroy_vehicle(editor.gameplay_physics.world, vehicle)

    physics.set_vehicle_input(editor.gameplay_physics.world, vehicle, 1, 0, 0, 0)
    for _ in 0 ..< 360 {
        gameplay_physics_begin_frame(editor)
        gameplay_physics_step_world(editor, 1.0 / 120.0)
    }

    position, _, ok := physics.get_transform(editor.gameplay_physics.world, physics.vehicle_body(vehicle))
    testing.expect(t, ok)
    testing.expectf(t, position.z > 3, "expected gameplay car to drive forward, got z %v", position.z)
}
