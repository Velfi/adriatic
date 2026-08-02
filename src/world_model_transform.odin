package main

import third_person "../packages/third_person"
import linalg "core:math/linalg"

World_Model_Transform :: struct {
    origin:        third_person.Vec3,
    right_basis:   third_person.Vec3,
    up_basis:      third_person.Vec3,
    forward_basis: third_person.Vec3,
    basis_matrix:  linalg.Matrix3f32,
}

world_model_transform_from_basis :: #force_inline proc(
    origin, right, up, forward: third_person.Vec3,
) -> World_Model_Transform {
    return {
        origin = origin,
        right_basis = right,
        up_basis = up,
        forward_basis = forward,
        basis_matrix = linalg.Matrix3f32 {
            right.x,
            right.y,
            right.z,
            up.x,
            up.y,
            up.z,
            -forward.x,
            -forward.y,
            -forward.z,
        },
    }
}

world_model_vertex_world :: #force_inline proc(
    transform: World_Model_Transform,
    position: [3]f32,
) -> third_person.Vec3 {
    return transform.origin + linalg.mul(transform.basis_matrix, third_person.Vec3(position))
}

world_model_normal_world :: #force_inline proc(transform: World_Model_Transform, normal: [3]f32) -> third_person.Vec3 {
    return linalg.mul(transform.basis_matrix, third_person.Vec3(normal))
}
