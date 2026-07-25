package vehicles

import "core:math"

// Apply absolute poses to freshly constructed procedural meshes. Commands are
// normalized to -1..1, flap_fraction to 0..1, and turns are revolutions.

rotate_mesh_part_x :: proc(mesh: ^Aircraft_Mesh, part: Aircraft_Mesh_Part, pivot: [3]f32, angle: f32) {
    if mesh == nil do return
    c := math.cos(angle); s := math.sin(angle)
    for &vertex in mesh.vertices[:mesh.vertex_count] {
        if vertex.part != part do continue
        y := vertex.position[1] - pivot[1]; z := vertex.position[2] - pivot[2]
        vertex.position[1] = pivot[1] + y * c - z * s; vertex.position[2] = pivot[2] + y * s + z * c
    }
}

rotate_mesh_part_y :: proc(mesh: ^Aircraft_Mesh, part: Aircraft_Mesh_Part, pivot: [3]f32, angle: f32) {
    if mesh == nil do return
    c := math.cos(angle); s := math.sin(angle)
    for &vertex in mesh.vertices[:mesh.vertex_count] {
        if vertex.part != part do continue
        x := vertex.position[0] - pivot[0]; z := vertex.position[2] - pivot[2]
        vertex.position[0] = pivot[0] + x * c + z * s; vertex.position[2] = pivot[2] - x * s + z * c
    }
}

rotate_mesh_part_z :: proc(mesh: ^Aircraft_Mesh, part: Aircraft_Mesh_Part, pivot: [3]f32, angle: f32) {
    if mesh == nil do return
    c := math.cos(angle); s := math.sin(angle)
    for &vertex in mesh.vertices[:mesh.vertex_count] {
        if vertex.part != part do continue
        x := vertex.position[0] - pivot[0]; y := vertex.position[1] - pivot[1]
        vertex.position[0] = pivot[0] + x * c - y * s; vertex.position[1] = pivot[1] + x * s + y * c
    }
}

rotate_mesh_group_y :: proc(mesh: ^Libellula_Mesh, group: Mesh_Animation_Group, pivot: [3]f32, angle: f32) {
    if mesh == nil do return
    c := math.cos(angle)
    s := math.sin(angle)
    for &vertex in mesh.vertices[:mesh.vertex_count] {
        if vertex.animation_group != group do continue
        x := vertex.position[0] - pivot[0]
        z := vertex.position[2] - pivot[2]
        vertex.position[0] = pivot[0] + x * c + z * s
        vertex.position[2] = pivot[2] - x * s + z * c
    }
}

libellula_carriage_point :: proc(local: [3]f32, pitch, roll, heave: f32) -> [3]f32 {
    // Match TriRotorVisual's pitch-cradle -> roll-gimbal hierarchy.
    roll_angle := clamp_unit(roll) * degrees(15)
    pitch_angle := clamp_unit(pitch) * degrees(15)
    roll_c, roll_s := math.cos(roll_angle), math.sin(roll_angle)
    pitch_c, pitch_s := math.cos(pitch_angle), math.sin(pitch_angle)
    rolled := [3]f32{local[0] * roll_c - local[1] * roll_s, local[0] * roll_s + local[1] * roll_c, local[2]}
    cradle_local := [3]f32{rolled[0], rolled[1] - .78 + heave, rolled[2]}
    pitched := [3]f32 {
        cradle_local[0],
        cradle_local[1] * pitch_c - cradle_local[2] * pitch_s,
        cradle_local[1] * pitch_s + cradle_local[2] * pitch_c,
    }
    return lib_vadd(lib_vadd(LIBELLULA_CARRIAGE_OFFSET, {0, .78, 0}), pitched)
}

pose_libellula_carriage :: proc(mesh: ^Libellula_Mesh, pitch, roll, heave: f32) {
    if mesh == nil do return
    for &vertex in mesh.vertices[:mesh.vertex_count] {
        if vertex.animation_group != .Libellula_Carriage do continue
        local := lib_vsub(vertex.position, LIBELLULA_CARRIAGE_OFFSET)
        vertex.position = libellula_carriage_point(local, pitch, roll, heave)
    }
}

realign_mesh_group :: proc(
    mesh: ^Libellula_Mesh,
    group: Mesh_Animation_Group,
    source_a, source_b, target_a, target_b: [3]f32,
) {
    source_span := lib_vsub(source_b, source_a)
    target_span := lib_vsub(target_b, target_a)
    source_length := lib_vlength(source_span)
    target_length := lib_vlength(target_span)
    if mesh == nil || source_length < .0001 || target_length < .0001 do return
    source_n, source_t, source_bi := libellula_axis_basis(source_span)
    target_n, target_t, target_bi := libellula_axis_basis(target_span)
    source_mid := lib_vlerp(source_a, source_b, .5)
    target_mid := lib_vlerp(target_a, target_b, .5)
    for &vertex in mesh.vertices[:mesh.vertex_count] {
        if vertex.animation_group != group do continue
        relative := lib_vsub(vertex.position, source_mid)
        along := lib_vdot(relative, source_n) * target_length / source_length
        tangent := lib_vdot(relative, source_t)
        bitangent := lib_vdot(relative, source_bi)
        vertex.position = lib_vadd(
            target_mid,
            lib_vadd(
                lib_vscale(target_n, along),
                lib_vadd(lib_vscale(target_t, tangent), lib_vscale(target_bi, bitangent)),
            ),
        )
    }
}

degrees :: proc(value: f32) -> f32 { return value * math.PI / 180 }

animate_postale_mesh :: proc(mesh: ^Aircraft_Mesh, flap_fraction, pitch, roll, yaw, propeller_turns: f32) {
    flap := degrees(clamp_unit(flap_fraction) * 35)
    rotate_mesh_part_x(
        mesh,
        .Left_Flap,
        {-2.35, .99, .245},
        flap,
    ); rotate_mesh_part_x(mesh, .Right_Flap, {2.35, .99, .245}, flap)
    rotate_mesh_part_x(
        mesh,
        .Left_Aileron,
        {-4.55, 1.035, .33},
        degrees(-4 - roll * 16),
    ); rotate_mesh_part_x(mesh, .Right_Aileron, {4.55, 1.035, .33}, degrees(-4 + roll * 16))
    rotate_mesh_part_x(
        mesh,
        .Elevator,
        {0, .56, 2.93},
        degrees(-pitch * 18),
    ); rotate_mesh_part_y(mesh, .Rudder, {0, 1.26, 2.96}, degrees(yaw * 20))
    rotate_mesh_part_z(mesh, .Propeller, {0, .12, -3.42}, propeller_turns * 2 * math.PI)
}

animate_pelican_mesh :: proc(
    mesh: ^Aircraft_Mesh,
    flap_fraction, pitch, roll, yaw, left_propeller_turns, right_propeller_turns: f32,
) {
    flap := degrees(clamp_unit(flap_fraction) * 35)
    rotate_mesh_part_x(
        mesh,
        .Left_Flap,
        {-2.475, 2.3, 0},
        flap,
    ); rotate_mesh_part_x(mesh, .Right_Flap, {2.475, 2.3, 0}, flap)
    rotate_mesh_part_x(
        mesh,
        .Left_Aileron,
        {-5.55, 2.3, .12},
        degrees(-roll * 16),
    ); rotate_mesh_part_x(mesh, .Right_Aileron, {5.55, 2.3, .12}, degrees(roll * 16))
    rotate_mesh_part_x(
        mesh,
        .Elevator,
        {0, 1.28, 5.72},
        degrees(-pitch * 18),
    ); rotate_mesh_part_y(mesh, .Rudder, {0, 2.28, 5.7}, degrees(yaw * 20))
    rotate_mesh_part_z(
        mesh,
        .Left_Propeller,
        {-3.45, 2.13, -2.75},
        -left_propeller_turns * 2 * math.PI,
    ); rotate_mesh_part_z(mesh, .Right_Propeller, {3.45, 2.13, -2.75}, right_propeller_turns * 2 * math.PI)
}

animate_libellula_mesh :: proc(mesh: ^Libellula_Mesh, left_turns, right_turns, rear_turns: f32) {
    animate_libellula_mesh_pose(mesh, left_turns, right_turns, rear_turns, 0, 0, 0)
}

animate_libellula_mesh_pose :: proc(
    mesh: ^Libellula_Mesh,
    left_turns, right_turns, rear_turns, pitch, roll, heave: f32,
) {
    rotate_mesh_group_y(
        mesh,
        .Libellula_Left_Rotor,
        lib_vadd(LIBELLULA_LEFT_HUB, {0, .38, 0}),
        left_turns * 2 * math.PI,
    )
    rotate_mesh_group_y(
        mesh,
        .Libellula_Right_Rotor,
        lib_vadd(LIBELLULA_RIGHT_HUB, {0, .38, 0}),
        -right_turns * 2 * math.PI,
    )
    rotate_mesh_group_y(
        mesh,
        .Libellula_Rear_Rotor,
        lib_vadd(LIBELLULA_REAR_HUB, {0, .38, 0}),
        rear_turns * 2 * math.PI,
    )
    pose_libellula_carriage(mesh, pitch, roll, heave)

    frame_anchors := [3][3]f32{{-1.16, .86, .65}, {1.16, .86, .65}, {0, .86, 3.05}}
    carriage_anchors := [3][3]f32{{-.58, .36, -1.25}, {.58, .36, -1.25}, {0, .36, 1.55}}
    strap_groups := [3]Mesh_Animation_Group{.Libellula_Strap_Left, .Libellula_Strap_Right, .Libellula_Strap_Rear}
    for frame_anchor, index in frame_anchors {
        source_lower := lib_vadd(LIBELLULA_CARRIAGE_OFFSET, carriage_anchors[index])
        target_lower := libellula_carriage_point(carriage_anchors[index], pitch, roll, heave)
        realign_mesh_group(mesh, strap_groups[index], frame_anchor, source_lower, frame_anchor, target_lower)
    }

    kingpost_upper := [3]f32{0, .76, LIBELLULA_SUSPENSION_CENTER_Z - .03}
    source_lower := lib_vadd(LIBELLULA_CARRIAGE_OFFSET, {0, .36, .12})
    target_lower := libellula_carriage_point({0, .36, .12}, pitch, roll, heave)
    source_span := lib_vsub(source_lower, kingpost_upper)
    target_span := lib_vsub(target_lower, kingpost_upper)
    realign_mesh_group(
        mesh,
        .Libellula_Kingpost_Outer,
        kingpost_upper,
        lib_vadd(kingpost_upper, lib_vscale(source_span, .62)),
        kingpost_upper,
        lib_vadd(kingpost_upper, lib_vscale(target_span, .62)),
    )
    realign_mesh_group(
        mesh,
        .Libellula_Kingpost_Inner,
        lib_vadd(kingpost_upper, lib_vscale(source_span, .42)),
        source_lower,
        lib_vadd(kingpost_upper, lib_vscale(target_span, .42)),
        target_lower,
    )
    realign_mesh_group(
        mesh,
        .Libellula_Kingpost_Stop,
        lib_vadd(kingpost_upper, lib_vscale(source_span, .58)),
        lib_vadd(kingpost_upper, lib_vscale(source_span, .7)),
        lib_vadd(kingpost_upper, lib_vscale(target_span, .58)),
        lib_vadd(kingpost_upper, lib_vscale(target_span, .7)),
    )

    cable_groups := [2][2]Mesh_Animation_Group {
        {.Libellula_Umbilical_1_Upper, .Libellula_Umbilical_1_Lower},
        {.Libellula_Umbilical_2_Upper, .Libellula_Umbilical_2_Lower},
    }
    umbilical_xs := [2]f32{-.14, .14}
    for x, index in umbilical_xs {
        upper := [3]f32{x, .72, LIBELLULA_SUSPENSION_CENTER_Z - .03}
        old_lower := lib_vadd(LIBELLULA_CARRIAGE_OFFSET, {x, .29, .12})
        new_lower := libellula_carriage_point({x, .29, .12}, pitch, roll, heave)
        old_sag := lib_vadd(lib_vlerp(upper, old_lower, .5), {0, -.16, 0})
        new_sag := lib_vadd(lib_vlerp(upper, new_lower, .5), {0, -.16, 0})
        realign_mesh_group(mesh, cable_groups[index][0], upper, old_sag, upper, new_sag)
        realign_mesh_group(mesh, cable_groups[index][1], old_sag, old_lower, new_sag, new_lower)
    }
}
