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

animate_libellula_mesh :: proc(mesh: ^Aircraft_Mesh, left_turns, right_turns, rear_turns: f32) {
    rotate_mesh_part_y(mesh, .Left_Rotor, {-3.65, 1.96, -.75}, left_turns * 2 * math.PI)
    rotate_mesh_part_y(mesh, .Right_Rotor, {3.65, 1.96, -.75}, -right_turns * 2 * math.PI)
    rotate_mesh_part_y(mesh, .Rear_Rotor, {0, 1.96, 3.05}, rear_turns * 2 * math.PI)
}
