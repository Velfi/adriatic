package main

import third_person "zelda_engine:third_person"
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
    // Model space uses +X right, +Y up, and -Z forward. Compose from the
    // named basis vectors directly so mixed pitch/roll cannot transpose the
    // frame through matrix storage-order assumptions.
    return(
        transform.origin +
        transform.right_basis * position.x +
        transform.up_basis * position.y -
        transform.forward_basis * position.z \
    )
}

world_model_normal_world :: #force_inline proc(transform: World_Model_Transform, normal: [3]f32) -> third_person.Vec3 {
    return transform.right_basis * normal.x + transform.up_basis * normal.y - transform.forward_basis * normal.z
}
