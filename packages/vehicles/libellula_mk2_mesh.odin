package vehicles

import "core:math"

// Libellula Mk2 is a separate airframe, not a dressed-up Libellula. It keeps
// the same product-neutral flight runtime, but its authored presentation is a
// rigid quad-rotor utility craft with a dedicated cargo winch.

LIBELLULA_MK2_FRONT_LEFT_HUB :: [3]f32{-4.15, 1.42, -1.85}
LIBELLULA_MK2_FRONT_RIGHT_HUB :: [3]f32{4.15, 1.42, -1.85}
LIBELLULA_MK2_REAR_LEFT_HUB :: [3]f32{-3.75, 1.42, 2.72}
LIBELLULA_MK2_REAR_RIGHT_HUB :: [3]f32{3.75, 1.42, 2.72}

libellula_mk2_mesh_build :: proc(mesh: ^Libellula_Mesh) {
    if mesh == nil do return
    if mesh.vertices == nil do libellula_mesh_init(mesh)
    mesh.vertex_count = 0
    mesh.triangle_count = 0

    hubs := [4][3]f32 {
        LIBELLULA_MK2_FRONT_LEFT_HUB,
        LIBELLULA_MK2_FRONT_RIGHT_HUB,
        LIBELLULA_MK2_REAR_LEFT_HUB,
        LIBELLULA_MK2_REAR_RIGHT_HUB,
    }

    // Broad square lift frame with a central service spine.
    for index in 0 ..< 4 {
        next := (index + 1) % 4
        libellula_add_beam(mesh, hubs[index], hubs[next], .14, .Lift_Frame)
        libellula_add_beam(mesh, hubs[index], {hubs[index][0], .72, hubs[index][2]}, .085, .Lift_Frame)
        libellula_add_cylinder(mesh, hubs[index], {0, 1, 0}, .34, .34, .16, 10, .Lift_Frame)
        libellula_add_torus(mesh, lib_vadd(hubs[index], {0, .10, 0}), {0, 1, 0}, .20, .29, 12, 5, .Brass)
    }
    libellula_add_beam(mesh, {0, 1.12, -1.85}, {0, 1.12, 2.72}, .12, .Lift_Frame)
    libellula_add_beam(mesh, {-4.15, 1.12, .42}, {4.15, 1.12, .42}, .10, .Lift_Frame)

    for hub, index in hubs {
        rotor_part := Aircraft_Mesh_Part.Left_Rotor
        group := Mesh_Animation_Group.Libellula_Left_Rotor
        if index == 1 {
            rotor_part = .Right_Rotor
            group = .Libellula_Right_Rotor
        } else if index == 2 {
            rotor_part = .Rear_Rotor
            group = .Libellula_Rear_Rotor
        } else if index == 3 {
            rotor_part = .Mk2_Rear_Rotor
            group = .Libellula_Mk2_Rear_Rotor
        }
        libellula_add_rotor(mesh, hub, index, rotor_part, group)
    }

    // Bus-like carriage: a raised floor, waist-high side panels, rear
    // bulkhead, canopy, and corner posts leave the front and upper cabin open.
    libellula_add_box_rotated(mesh, {0, -.70, .25}, {2.28, .22, 2.55}, {0, 0, 0}, .Dark_Metal)
    libellula_add_box_rotated(mesh, {-1.03, -.18, .25}, {.22, 1.18, 2.28}, {0, 0, 0}, .Red_Paint)
    libellula_add_box_rotated(mesh, {1.03, -.18, .25}, {.22, 1.18, 2.28}, {0, 0, 0}, .Red_Paint)
    libellula_add_box_rotated(mesh, {0, -.04, 1.34}, {2.28, 1.48, .24}, {0, 0, 0}, .Red_Paint)
    libellula_add_box_rotated(mesh, {0, .98, .25}, {2.42, .18, 2.42}, {0, 0, 0}, .Ivory)
    post_xs := [2]f32{-.98, .98}
    post_zs := [2]f32{-1.02, 1.02}
    for x in post_xs {
        for z in post_zs {
            libellula_add_beam(mesh, {x, -.62, z}, {x, .98, z}, .075, .Lift_Frame)
        }
    }
    libellula_add_box_rotated(mesh, {0, -.43, -.72}, {1.55, .16, .72}, {0, 0, 0}, .Ivory)
    libellula_add_box_rotated(mesh, {0, -.20, -.68}, {1.70, .16, .20}, {0, 0, 0}, .Brass)
    libellula_add_box_rotated(mesh, {0, -.40, 1.48}, {1.25, .12, .48}, {0, 0, 0}, .Brass)
    libellula_add_marking_text(mesh, "MK2", -.15, .42, .04)

    // Four splayed utility legs and skid shoes.
    feet := [4][3]f32{{-1.45, -2.05, -1.15}, {1.45, -2.05, -1.15}, {-1.45, -2.05, 1.55}, {1.45, -2.05, 1.55}}
    roots := [4][3]f32{{-.78, -.82, -.78}, {.78, -.82, -.78}, {-.78, -.82, 1.05}, {.78, -.82, 1.05}}
    for root, index in roots {
        foot := feet[index]
        libellula_add_beam(mesh, root, foot, .10, .Wheel)
        libellula_add_beam(mesh, lib_vadd(root, {0, 0, .28}), foot, .05, .Lift_Frame)
        add_box(mesh, foot, {.58, .13, .34}, .Wheel)
    }

    // Dedicated cargo winch below the centerline: drum, fairlead, cable,
    // swivel, and hook are all authored as Mk2-only geometry.
    winch := [3]f32{0, -1.24, .40}
    libellula_add_cylinder(mesh, winch, {1, 0, 0}, .34, .34, 1.25, 16, .Dark_Metal)
    libellula_add_torus(mesh, lib_vadd(winch, {-.48, 0, 0}), {1, 0, 0}, .27, .39, 12, 5, .Brass)
    libellula_add_torus(mesh, lib_vadd(winch, {.48, 0, 0}), {1, 0, 0}, .27, .39, 12, 5, .Brass)
    libellula_add_cylinder(mesh, {0, -1.52, .40}, {0, 1, 0}, .07, .07, .48, 10, .Steel)
    libellula_add_beam(mesh, {0, -1.78, .40}, {0, -4.18, .40}, .028, .Strap)
    libellula_add_torus(mesh, {0, -4.22, .40}, {0, 1, 0}, .14, .21, 10, 5, .Brass)
    libellula_add_sphere(mesh, {0, -4.35, .40}, .15, 10, 5, .Steel)
    mesh_finalize(
        mesh,
        &libellula_mk2_mesh_cache,
        libellula_mk2_uvs[:],
        libellula_mk2_sources[:],
        libellula_mk2_indices[:],
        libellula_mk2_scratch[:],
    )
}

animate_libellula_mk2_mesh :: proc(mesh: ^Libellula_Mesh, front_left, front_right, rear_left, rear_right: f32) {
    rotate_mesh_group_y(
        mesh,
        .Libellula_Left_Rotor,
        lib_vadd(LIBELLULA_MK2_FRONT_LEFT_HUB, {0, .38, 0}),
        front_left * 2 * math.PI,
    )
    rotate_mesh_group_y(
        mesh,
        .Libellula_Right_Rotor,
        lib_vadd(LIBELLULA_MK2_FRONT_RIGHT_HUB, {0, .38, 0}),
        -front_right * 2 * math.PI,
    )
    rotate_mesh_group_y(
        mesh,
        .Libellula_Rear_Rotor,
        lib_vadd(LIBELLULA_MK2_REAR_LEFT_HUB, {0, .38, 0}),
        rear_left * 2 * math.PI,
    )
    rotate_mesh_group_y(
        mesh,
        .Libellula_Mk2_Rear_Rotor,
        lib_vadd(LIBELLULA_MK2_REAR_RIGHT_HUB, {0, .38, 0}),
        -rear_right * 2 * math.PI,
    )
}
