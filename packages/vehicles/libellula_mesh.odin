package vehicles

import "core:math"
import "core:math/linalg"

// Faithful product-local port of ArchipelagoGame's TriRotorVisual. The source
// builds the aircraft from Godot primitives; this file emits the same authored
// assemblies into Adriatic's single triangle mesh.

LIBELLULA_LEFT_HUB :: [3]f32{-3.2, 1.17, -1}
LIBELLULA_RIGHT_HUB :: [3]f32{3.2, 1.17, -1}
LIBELLULA_REAR_HUB :: [3]f32{0, 1.17, 4.5425625}
LIBELLULA_CENTROID :: [3]f32{0, 1.17, .8475208}
LIBELLULA_SUSPENSION_CENTER_Z :: f32(1.8475208)
LIBELLULA_CARRIAGE_OFFSET :: [3]f32{0, -1.1, 1.6475208}
libellula_axis_basis :: proc(axis: [3]f32) -> (n, tangent, bitangent: [3]f32) {
    n = linalg.normalize0(axis)
    if linalg.dot(n, n) < .0000000001 do n = {0, 1, 0}
    reference := [3]f32{0, 1, 0}
    if math.abs(linalg.dot(n, reference)) > .92 do reference = {1, 0, 0}
    tangent = linalg.normalize0(linalg.cross(reference, n))
    if linalg.dot(tangent, tangent) < .0000000001 do tangent = {0, 1, 0}
    bitangent = linalg.normalize0(linalg.cross(n, tangent))
    if linalg.dot(bitangent, bitangent) < .0000000001 do bitangent = {0, 1, 0}
    return
}

libellula_add_cylinder :: proc(
    mesh: ^Libellula_Mesh,
    center, axis: [3]f32,
    bottom_radius, top_radius, height: f32,
    sides: int,
    part: Aircraft_Mesh_Part,
) {
    if sides < 3 || height <= 0 do return
    n, tangent, bitangent := libellula_axis_basis(axis)
    bottom_center := (center - (n * height * .5))
    top_center := (center + (n * height * .5))
    for side in 0 ..< sides {
        next := (side + 1) % sides
        a0 := f32(side) * 2 * math.PI / f32(sides)
        a1 := f32(next) * 2 * math.PI / f32(sides)
        radial0 := ((tangent * math.cos(a0)) + (bitangent * math.sin(a0)))
        radial1 := ((tangent * math.cos(a1)) + (bitangent * math.sin(a1)))
        b0 := (bottom_center + (radial0 * bottom_radius))
        b1 := (bottom_center + (radial1 * bottom_radius))
        t1 := (top_center + (radial1 * top_radius))
        t0 := (top_center + (radial0 * top_radius))
        mesh_quad(mesh, b0, b1, t1, t0, part)
        mesh_triangle(mesh, bottom_center, b0, b1, part)
        mesh_triangle(mesh, top_center, t1, t0, part)
    }
}

libellula_add_beam :: proc(mesh: ^Libellula_Mesh, a, b: [3]f32, radius: f32, part: Aircraft_Mesh_Part) {
    delta := (b - a)
    length := linalg.length(delta)
    if length < .0001 do return
    libellula_add_cylinder(mesh, linalg.lerp(a, b, .5), delta, radius, radius, length, 8, part)
}

libellula_add_sphere :: proc(
    mesh: ^Libellula_Mesh,
    center: [3]f32,
    radius: f32,
    sides, rings: int,
    part: Aircraft_Mesh_Part,
) {
    if sides < 3 || rings < 2 do return
    for ring in 0 ..< rings {
        phi0 := -math.PI * .5 + f32(ring) * math.PI / f32(rings)
        phi1 := -math.PI * .5 + f32(ring + 1) * math.PI / f32(rings)
        for side in 0 ..< sides {
            theta0 := f32(side) * 2 * math.PI / f32(sides)
            theta1 := f32(side + 1) * 2 * math.PI / f32(sides)
            p00 := [3]f32 {
                center[0] + radius * math.cos(phi0) * math.cos(theta0),
                center[1] + radius * math.sin(phi0),
                center[2] + radius * math.cos(phi0) * math.sin(theta0),
            }
            p01 := [3]f32 {
                center[0] + radius * math.cos(phi0) * math.cos(theta1),
                center[1] + radius * math.sin(phi0),
                center[2] + radius * math.cos(phi0) * math.sin(theta1),
            }
            p11 := [3]f32 {
                center[0] + radius * math.cos(phi1) * math.cos(theta1),
                center[1] + radius * math.sin(phi1),
                center[2] + radius * math.cos(phi1) * math.sin(theta1),
            }
            p10 := [3]f32 {
                center[0] + radius * math.cos(phi1) * math.cos(theta0),
                center[1] + radius * math.sin(phi1),
                center[2] + radius * math.cos(phi1) * math.sin(theta0),
            }
            if ring == 0 {
                mesh_triangle(mesh, p00, p10, p11, part)
            } else if ring == rings - 1 {
                mesh_triangle(mesh, p00, p11, p01, part)
            } else {
                mesh_quad(mesh, p00, p01, p11, p10, part)
            }
        }
    }
}

libellula_add_torus :: proc(
    mesh: ^Libellula_Mesh,
    center, axis: [3]f32,
    inner_radius, outer_radius: f32,
    sides, tube_sides: int,
    part: Aircraft_Mesh_Part,
) {
    n, tangent, bitangent := libellula_axis_basis(axis)
    major := (inner_radius + outer_radius) * .5
    tube := (outer_radius - inner_radius) * .5
    for side in 0 ..< sides {
        a0 := f32(side) * 2 * math.PI / f32(sides)
        a1 := f32(side + 1) * 2 * math.PI / f32(sides)
        radial0 := ((tangent * math.cos(a0)) + (bitangent * math.sin(a0)))
        radial1 := ((tangent * math.cos(a1)) + (bitangent * math.sin(a1)))
        for tube_side in 0 ..< tube_sides {
            b0 := f32(tube_side) * 2 * math.PI / f32(tube_sides)
            b1 := f32(tube_side + 1) * 2 * math.PI / f32(tube_sides)
            p00 := (center + ((radial0 * major + tube * math.cos(b0)) + (n * tube * math.sin(b0))))
            p01 := (center + ((radial1 * major + tube * math.cos(b0)) + (n * tube * math.sin(b0))))
            p11 := (center + ((radial1 * major + tube * math.cos(b1)) + (n * tube * math.sin(b1))))
            p10 := (center + ((radial0 * major + tube * math.cos(b1)) + (n * tube * math.sin(b1))))
            mesh_quad(mesh, p00, p01, p11, p10, part)
        }
    }
}

libellula_add_box_rotated :: proc(
    mesh: ^Libellula_Mesh,
    center, size, rotation_degrees: [3]f32,
    part: Aircraft_Mesh_Part,
) {
    first := mesh.vertex_count
    add_box(mesh, center, size, part)
    rotate_new_vertices_x(mesh, first, center, rotation_degrees[0] * math.PI / 180)
    rotate_new_vertices_y(mesh, first, center, rotation_degrees[1] * math.PI / 180)
    rotate_new_vertices_z(mesh, first, center, rotation_degrees[2] * math.PI / 180)
}

libellula_glyph_row :: proc(character: rune, row: int) -> u8 {
    switch character {
    case 'A':
        rows := [5]u8{0b01110, 0b10001, 0b11111, 0b10001, 0b10001}
        return rows[row]
    case 'B':
        rows := [5]u8{0b11110, 0b10001, 0b11110, 0b10001, 0b11110}
        return rows[row]
    case 'E':
        rows := [5]u8{0b11111, 0b10000, 0b11110, 0b10000, 0b11111}
        return rows[row]
    case 'I':
        rows := [5]u8{0b11111, 0b00100, 0b00100, 0b00100, 0b11111}
        return rows[row]
    case 'L':
        rows := [5]u8{0b10000, 0b10000, 0b10000, 0b10000, 0b11111}
        return rows[row]
    case 'R':
        rows := [5]u8{0b11110, 0b10001, 0b11110, 0b10100, 0b10010}
        return rows[row]
    case 'S':
        rows := [5]u8{0b01111, 0b10000, 0b01110, 0b00001, 0b11110}
        return rows[row]
    case 'T':
        rows := [5]u8{0b11111, 0b00100, 0b00100, 0b00100, 0b00100}
        return rows[row]
    case 'U':
        rows := [5]u8{0b10001, 0b10001, 0b10001, 0b10001, 0b01110}
        return rows[row]
    case '3':
        rows := [5]u8{0b11110, 0b00001, 0b01110, 0b00001, 0b11110}
        return rows[row]
    case '-':
        rows := [5]u8{0, 0, 0b11111, 0, 0}
        return rows[row]
    }
    return 0
}

libellula_add_marking_text :: proc(mesh: ^Libellula_Mesh, text: string, center_y, center_z, pixel: f32) {
    width := f32(len(text) * 6 - 1) * pixel
    marking_sides := [2]f32{-1, 1}
    for side_sign in marking_sides {
        side := side_sign * .802
        for character, glyph_index in text {
            for row in 0 ..< 5 {
                bits := libellula_glyph_row(character, row)
                for column in 0 ..< 5 {
                    if bits & (u8(1) << u8(4 - column)) == 0 do continue
                    z := center_z - width * .5 + f32(glyph_index * 6 + column) * pixel
                    y := center_y + f32(2 - row) * pixel
                    half := pixel * .41
                    a := [3]f32{side, y - half, z - half}
                    b := [3]f32{side, y - half, z + half}
                    c := [3]f32{side, y + half, z + half}
                    d := [3]f32{side, y + half, z - half}
                    if side_sign > 0 {
                        mesh_quad(mesh, a, b, c, d, .Marking)
                    } else {
                        mesh_quad(mesh, a, d, c, b, .Marking)
                    }
                }
            }
        }
    }
}

libellula_add_blade_segment :: proc(
    mesh: ^Libellula_Mesh,
    hub: [3]f32,
    angle, root_z, tip_z, root_chord, tip_chord, root_sweep, tip_sweep, root_thickness, tip_thickness: f32,
    part: Aircraft_Mesh_Part,
) {
    rt, tt := root_thickness * .5, tip_thickness * .5
    points := [8][3]f32 {
        {root_sweep - root_chord * .5, rt, root_z},
        {root_sweep + root_chord * .5, rt, root_z},
        {tip_sweep + tip_chord * .5, tt, tip_z},
        {tip_sweep - tip_chord * .5, tt, tip_z},
        {root_sweep - root_chord * .5, -rt, root_z},
        {root_sweep + root_chord * .5, -rt, root_z},
        {tip_sweep + tip_chord * .5, -tt, tip_z},
        {tip_sweep - tip_chord * .5, -tt, tip_z},
    }
    c, s := math.cos(angle), math.sin(angle)
    pitch_c, pitch_s := math.cos(f32(1.6) * math.PI / 180), math.sin(f32(1.6) * math.PI / 180)
    for &p in points {
        x, y, z := p[0], p[1], p[2]
        y, z = y * pitch_c - z * pitch_s, y * pitch_s + z * pitch_c
        p = {hub[0] + x * c - z * s, hub[1] + y, hub[2] + x * s + z * c}
    }
    mesh_quad(mesh, points[0], points[1], points[2], points[3], part)
    mesh_quad(mesh, points[7], points[6], points[5], points[4], part)
    mesh_quad(mesh, points[1], points[5], points[6], points[2], part)
    mesh_quad(mesh, points[3], points[2], points[6], points[7], part)
    mesh_quad(mesh, points[0], points[3], points[7], points[4], part)
    mesh_quad(mesh, points[4], points[5], points[1], points[0], part)
}

libellula_add_rotor :: proc(
    mesh: ^Libellula_Mesh,
    position: [3]f32,
    unit: int,
    rotor_part: Aircraft_Mesh_Part,
    rotor_group: Mesh_Animation_Group,
) {
    // Governed power unit: case, cooling bands, hardware, exhaust and swashplate.
    libellula_add_cylinder(mesh, position, {0, 1, 0}, .5, .42, .58, 16, .Dark_Metal)
    cooling_band_ys := [3]f32{-.2, -.04, .12}
    for y in cooling_band_ys {
        libellula_add_torus(mesh, (position + {0, y, 0}), {0, 1, 0}, .43, .51, 12, 5, .Steel)
    }
    libellula_add_torus(mesh, (position + {0, .12, 0}), {0, 1, 0}, .39, .55, 14, 6, .Red_Paint)
    for index in 0 ..< 4 {
        angle := f32(index) * math.PI * .5
        libellula_add_box_rotated(
            mesh,
            (position + {math.sin(angle) * .43, -.08, math.cos(angle) * .43}),
            {.13, .2, .035},
            {0, angle * 180 / math.PI, 0},
            .Dark_Metal,
        )
    }
    add_box(mesh, (position + {.42, -.24, 0}), {.26, .08, .13}, .Brass)
    add_box(mesh, (position + {-.39, -.12, 0}), {.18, .16, .24}, .Steel)
    libellula_add_cylinder(mesh, (position + {-.5, .02, 0}), {0, 1, 0}, .075, .055, .16, 8, .Brass)
    exhaust := [3]f32{-1, 0, 0}
    exhaust_axis := [3]f32{1, 0, 0}
    if unit == 1 {
        exhaust = {1, 0, 0}
    } else if unit == 2 {
        exhaust = {0, 0, 1}
        exhaust_axis = {0, 0, 1}
    }
    exhaust_a := (position + ({0, -.14, 0} + (exhaust * .34)))
    exhaust_b := (position + ({0, -.22, 0} + (exhaust * .68)))
    libellula_add_beam(mesh, exhaust_a, exhaust_b, .07, .Steel)
    libellula_add_torus(mesh, (position + ({0, -.22, 0} + (exhaust * .7))), exhaust_axis, .055, .085, 10, 5, .Brass)
    libellula_add_cylinder(mesh, (position + {0, .29, 0}), {0, 1, 0}, .105, .075, .42, 10, .Steel)
    libellula_add_torus(mesh, (position + {0, .29, 0}), {0, 1, 0}, .2, .29, 12, 5, .Steel)
    for index in 0 ..< 3 {
        angle := f32(index) * 2 * math.PI / 3
        radial := [3]f32{math.sin(angle), 0, math.cos(angle)}
        link_a := (position + ((radial * .32) + {0, .1, 0}))
        link_b := (position + ((radial * .24) + {0, .28, 0}))
        libellula_add_beam(mesh, link_a, link_b, .022, .Brass)
        libellula_add_sphere(mesh, link_b, .035, 8, 4, .Steel)
    }

    rotor_center := (position + {0, .38, 0})
    rotating_first := mesh.vertex_count
    libellula_add_torus(mesh, (rotor_center + {0, -.055, 0}), {0, 1, 0}, .2, .29, 12, 5, .Brass)
    libellula_add_cylinder(mesh, (rotor_center + {0, .13, 0}), {0, 1, 0}, .21, .14, .3, 12, .Brass)
    libellula_add_cylinder(mesh, (rotor_center + {0, .11, 0}), {0, 1, 0}, .065, .065, .42, 10, .Steel)
    for blade in 0 ..< 3 {
        angle := f32(blade) * 2 * math.PI / 3
        direction := [3]f32{-math.sin(angle), 0, -math.cos(angle)}
        cuff_center := (rotor_center + (direction * .31))
        libellula_add_cylinder(mesh, cuff_center, direction, .13, .13, .72, 10, rotor_part)
        libellula_add_blade_segment(mesh, rotor_center, angle, -.52, -2.01, .31, .17, 0, .08, .078, .046, .Rotor_Blade)
        libellula_add_blade_segment(
            mesh,
            rotor_center,
            angle,
            -2.01,
            -2.3,
            .17,
            .115,
            .08,
            .13,
            .046,
            .034,
            .Rotor_Tip,
        )
        pin := (rotor_center + (direction * .18))
        libellula_add_cylinder(mesh, pin, direction, .072, .072, .3, 8, .Steel)
        horn := (rotor_center + ((direction * .39) + {0, .075, 0}))
        link_base := (rotor_center + ((direction * .2) + {0, -.045, 0}))
        libellula_add_beam(mesh, link_base, horn, .021, .Brass)
        libellula_add_sphere(mesh, horn, .038, 8, 4, .Steel)
    }
    mark_new_vertices(mesh, rotating_first, rotor_group)
}

libellula_add_carriage_geometry :: proc(mesh: ^Libellula_Mesh) {
    first := mesh.vertex_count
    // Individually replaceable pressure-vessel barrel sections and end shells.
    sections := [5][3]f32{{-1.12, .58, .72}, {-.54, .58, .76}, {.04, .58, .77}, {.62, .58, .76}, {1.2, .58, .72}}
    for section in sections {
        libellula_add_cylinder(mesh, {0, -.56, section[0]}, {0, 0, 1}, section[2], section[2], section[1], 18, .Ivory)
    }
    libellula_add_cylinder(mesh, {0, -.56, -1.7}, {0, 0, 1}, .49, .72, .58, 18, .Ivory)
    libellula_add_cylinder(mesh, {0, -.56, 1.79}, {0, 0, 1}, .72, .48, .62, 18, .Red_Paint)
    station_zs := [6]f32{-1.41, -.83, -.25, .33, .91, 1.49}
    for z in station_zs {
        libellula_add_torus(mesh, {0, -.56, z}, {0, 0, 1}, .715, .775, 14, 5, .Steel)
        for index in 0 ..< 4 {
            angle := f32(45 + index * 90) * math.PI / 180
            libellula_add_box_rotated(
                mesh,
                {math.cos(angle) * .74, -.56 + math.sin(angle) * .74, z},
                {.12, .065, .08},
                {0, 0, angle * 180 / math.PI},
                .Brass,
            )
        }
    }
    longeron_angles := [4]f32{42, 138, 222, 318}
    for angle_degrees in longeron_angles {
        angle := angle_degrees * math.PI / 180
        libellula_add_box_rotated(
            mesh,
            {math.cos(angle) * .755, -.56 + math.sin(angle) * .755, .04},
            {.075, .075, 2.9},
            {0, 0, angle_degrees},
            .Steel,
        )
    }

    // Cockpit bubble, structural glazing, lights, side windows and cargo doors.
    libellula_add_sphere(mesh, {0, -.34, -1.88}, .7, 16, 8, .Glass)
    libellula_add_torus(mesh, {0, -.34, -1.86}, {0, 0, 1}, .67, .76, 14, 5, .Ivory)
    libellula_add_beam(mesh, {0, .13, -2.37}, {0, -.18, -2.4}, .032, .Steel)
    libellula_add_beam(mesh, {0, -.18, -2.4}, {-.53, -.72, -2.28}, .034, .Steel)
    libellula_add_beam(mesh, {0, -.18, -2.4}, {.53, -.72, -2.28}, .034, .Steel)
    libellula_add_beam(mesh, {-.48, .02, -2.3}, {.48, .02, -2.3}, .035, .Ivory)
    libellula_add_beam(mesh, {-.53, -.72, -2.28}, {.53, -.72, -2.28}, .04, .Dark_Metal)
    headlight_xs := [2]f32{-.44, .44}
    for x in headlight_xs {
        libellula_add_cylinder(mesh, {x, -.86, -2.05}, {0, 0, 1}, .17, .13, .18, 10, .Dark_Metal)
        libellula_add_cylinder(mesh, {x, -.86, -2.155}, {0, 0, 1}, .105, .105, .025, 10, .Headlight)
    }
    side_signs := [2]f32{-1, 1}
    for side_sign in side_signs {
        side := side_sign * .785
        add_box(mesh, {side, -.3, -1.43}, {.035, .54, .7}, .Glass)
        libellula_add_beam(mesh, {side, -.02, -1.78}, {side, -.02, -1.08}, .025, .Brass)
        libellula_add_beam(mesh, {side, -.58, -1.78}, {side, -.58, -1.08}, .025, .Steel)
        libellula_add_beam(mesh, {side, -.02, -1.78}, {side, -.58, -1.78}, .025, .Steel)
        libellula_add_beam(mesh, {side, -.02, -1.08}, {side, -.58, -1.08}, .025, .Steel)
        porthole_zs := [2]f32{-.48, .5}
        for z in porthole_zs {
            libellula_add_cylinder(mesh, {side, -.34, z}, {1, 0, 0}, .235, .235, .035, 14, .Glass)
            libellula_add_torus(mesh, {side * 1.015, -.34, z}, {1, 0, 0}, .235, .3, 14, 5, .Brass)
            for bolt in 0 ..< 4 {
                angle := f32(bolt) * math.PI * .5
                libellula_add_sphere(
                    mesh,
                    {side * 1.025, -.34 + math.sin(angle) * .27, z + math.cos(angle) * .27},
                    .025,
                    6,
                    3,
                    .Steel,
                )
            }
        }
        add_box(mesh, {side * 1.01, -.65, -.33}, {.05, .055, 2.18}, .Steel)
        add_box(mesh, {side * 1.015, -.73, .12}, {.052, .115, 2.72}, .Red_Paint)
        libellula_add_beam(mesh, {side, -.06, .12}, {side, -.06, 1.12}, .025, .Steel)
        libellula_add_beam(mesh, {side, -.9, .12}, {side, -.9, 1.12}, .025, .Steel)
        libellula_add_beam(mesh, {side, -.06, .12}, {side, -.9, .12}, .025, .Steel)
        libellula_add_beam(mesh, {side, -.06, 1.12}, {side, -.9, 1.12}, .025, .Steel)
        add_box(mesh, {side * 1.03, -.5, .94}, {.035, .055, .2}, .Brass)
    }

    // Rear service bulkhead, working hatch, inspection pane and service hardware.
    libellula_add_box_rotated(mesh, {0, -.72, 1.65}, {1.64, .62, 1.2}, {9, 0, 0}, .Red_Paint)
    libellula_add_box_rotated(mesh, {0, -1.12, 1.82}, {1.28, .1, .92}, {14, 0, 0}, .Brass)
    libellula_add_box_rotated(mesh, {0, -.66, 2.24}, {1.1, .64, .055}, {9, 0, 0}, .Ivory)
    libellula_add_torus(mesh, {0, -.48, 2.285}, {0, 0, 1}, .18, .27, 12, 5, .Dark_Metal)
    libellula_add_cylinder(mesh, {0, -.48, 2.292}, {0, 0, 1}, .18, .18, .035, 12, .Glass)
    hatch_bar_xs := [2]f32{-.42, .42}
    for x in hatch_bar_xs {
        libellula_add_box_rotated(mesh, {x, -.7, 2.29}, {.055, .48, .04}, {9, 0, 0}, .Dark_Metal)
        libellula_add_sphere(mesh, {x, -.98, 2.27}, .045, 8, 4, .Brass)
    }
    libellula_add_sphere(mesh, {-.55, -.52, 2.32}, .075, 8, 4, .Tail_Light)
    libellula_add_sphere(mesh, {.55, -.52, 2.32}, .075, 8, 4, .Headlight)
    hatch_hinge_xs := [2]f32{-.32, .32}
    for x in hatch_hinge_xs {
        add_box(mesh, {x, -.29, 2.335}, {.2, .1, .075}, .Dark_Metal)
        libellula_add_cylinder(mesh, {x, -.27, 2.37}, {1, 0, 0}, .035, .035, .26, 8, .Brass)
    }
    libellula_add_torus(mesh, {0, -.78, 2.385}, {0, 0, 1}, .075, .13, 10, 5, .Dark_Metal)
    for spoke in 0 ..< 3 {
        angle := f32(spoke) * 2 * math.PI / 3
        libellula_add_beam(
            mesh,
            {0, -.78, 2.39},
            {math.sin(angle) * .11, -.78 + math.cos(angle) * .11, 2.39},
            .014,
            .Brass,
        )
    }
    add_box(mesh, {-.68, -.78, 2.28}, {.22, .25, .09}, .Dark_Metal)
    add_box(mesh, {.68, -.77, 2.285}, {.23, .27, .085}, .Red_Paint)
    grille_ys := [3]f32{-.68, -.76, -.84}
    for y in grille_ys {
        add_box(mesh, {.7, y, 2.35}, {.15, .022, .035}, .Dark_Metal)
    }
    libellula_add_beam(mesh, {-.62, -1.14, 1.65}, {-.78, -1.38, 2.35}, .055, .Dark_Metal)
    libellula_add_beam(mesh, {.62, -1.14, 1.65}, {.78, -1.38, 2.35}, .055, .Dark_Metal)
    libellula_add_beam(mesh, {-.78, -1.38, 2.35}, {.78, -1.38, 2.35}, .06, .Dark_Metal)
    add_box(mesh, {0, -1.34, 2.2}, {1.3, .055, .3}, .Brass)
    bumper_rib_xs := [5]f32{-.5, -.25, 0, .25, .5}
    for x in bumper_rib_xs {
        add_box(mesh, {x, -1.305, 2.2}, {.035, .02, .23}, .Dark_Metal)
    }

    // Roof spine, access caps, aerial, carriage skids and boarding step.
    add_box(mesh, {0, .12, .12}, {1.25, .12, 3.2}, .Red_Paint)
    libellula_add_cylinder(mesh, {0, .25, .18}, {0, 1, 0}, .38, .27, .2, 12, .Red_Paint)
    roof_cap_zs := [2]f32{-.78, .92}
    for z in roof_cap_zs {
        libellula_add_cylinder(mesh, {0, .205, z}, {0, 1, 0}, .19, .19, .045, 12, .Steel)
        libellula_add_torus(mesh, {0, .23, z}, {0, 1, 0}, .17, .23, 12, 5, .Brass)
        add_box(mesh, {0, .265, z}, {.08, .035, .26}, .Dark_Metal)
    }
    libellula_add_cylinder(mesh, {0, .58, .55}, {0, 1, .14}, .07, .055, .58, 8, .Dark_Metal)
    skid_xs := [2]f32{-1.02, 1.02}
    strut_zs := [2]f32{-.85, .9}
    for x in skid_xs {
        for z in strut_zs {
            libellula_add_cylinder(mesh, {x, -1.04, z}, {x * .292, 1, 0}, .075, .055, 1.05, 8, .Wheel)
            libellula_add_cylinder(mesh, {x, -1.12, z}, {1, 0, 0}, .08, .08, .28, 8, .Wheel)
        }
        libellula_add_cylinder(mesh, {x, -1.52, .15}, {0, 0, 1}, .105, .105, 3.65, 10, .Wheel)
        libellula_add_beam(mesh, {x, -1.52, -1.67}, {x, -1.34, -2.02}, .105, .Wheel)
        libellula_add_beam(mesh, {x, -1.52, 1.97}, {x, -1.34, 2.28}, .105, .Wheel)
        libellula_add_sphere(mesh, {x, -1.34, -2.03}, .115, 8, 4, .Brass)
        libellula_add_sphere(mesh, {x, -1.34, 2.29}, .105, 8, 4, .Brass)
        add_box(mesh, {x, -1.625, .12}, {.18, .035, 1.7}, .Bumper)
    }
    cross_tube_zs := [2]f32{-.92, .95}
    for z in cross_tube_zs {
        libellula_add_cylinder(mesh, {0, -1.48, z}, {1, 0, 0}, .055, .055, 2.05, 8, .Wheel)
    }
    libellula_add_beam(mesh, {-1.02, -1.48, -.92}, {1.02, -1.48, .95}, .035, .Wheel)
    libellula_add_beam(mesh, {1.02, -1.48, -.92}, {-1.02, -1.48, .95}, .035, .Wheel)
    libellula_add_beam(mesh, {.79, -.85, .68}, {1.22, -1.22, .68}, .045, .Dark_Metal)
    libellula_add_beam(mesh, {.79, -.85, 1.02}, {1.22, -1.22, 1.02}, .045, .Dark_Metal)
    add_box(mesh, {1.22, -1.24, .85}, {.48, .045, .42}, .Brass)
    libellula_add_sphere(mesh, {0, -1.02, -2.12}, .09, 8, 4, .Headlight)
    libellula_add_sphere(mesh, {0, -.72, 2.18}, .08, 8, 4, .Tail_Light)

    // Mirrored hero-machine markings and the small dragonfly service badge.
    libellula_add_marking_text(mesh, "ASTERIA", -.18, .21, .025)
    libellula_add_marking_text(mesh, "TR-3", -.58, 1.65, .032)
    libellula_add_marking_text(mesh, "LIBELLULA", -.73, .18, .021)
    badge_sides := [2]f32{-1, 1}
    for side_sign in badge_sides {
        side := side_sign * .807
        add_box(mesh, {side, -.83, -.92}, {.022, .035, .38}, .Dark_Metal)
        add_box(mesh, {side, -.83, -.92}, {.024, .2, .035}, .Brass)
        libellula_add_box_rotated(mesh, {side, -.83, -1}, {.026, .1, .23}, {side_sign * 28, 0, side_sign * 22}, .Brass)
        libellula_add_box_rotated(
            mesh,
            {side, -.83, -.84},
            {.026, .1, .23},
            {side_sign * 28, 0, side_sign * 22},
            .Brass,
        )
    }

    // Three reinforced lower suspension eyes remain attached to the moving pod.
    carriage_anchors := [3][3]f32{{-.58, .36, -1.25}, {.58, .36, -1.25}, {0, .36, 1.55}}
    for anchor in carriage_anchors {
        add_box(mesh, {anchor[0], .17, anchor[2]}, {.42, .11, .42}, .Steel)
        add_box(mesh, (anchor + {-.13, -.07, 0}), {.045, .28, .25}, .Brass)
        add_box(mesh, (anchor + {.13, -.07, 0}), {.045, .28, .25}, .Brass)
        libellula_add_cylinder(mesh, anchor, {1, 0, 0}, .06, .06, .38, 8, .Steel)
        libellula_add_torus(mesh, (anchor + {0, .04, 0}), {1, 0, 0}, .065, .115, 10, 5, .Strap)
    }
    libellula_add_sphere(mesh, {0, .36, .12}, .14, 10, 5, .Brass)

    translate_new_vertices(mesh, first, LIBELLULA_CARRIAGE_OFFSET)
    mark_new_vertices(mesh, first, .Libellula_Carriage)
}

libellula_add_dynamic_beam :: proc(
    mesh: ^Libellula_Mesh,
    a, b: [3]f32,
    radius: f32,
    part: Aircraft_Mesh_Part,
    group: Mesh_Animation_Group,
) {
    first := mesh.vertex_count
    libellula_add_beam(mesh, a, b, radius, part)
    mark_new_vertices(mesh, first, group)
}

libellula_mesh_build :: proc(mesh: ^Libellula_Mesh) {
    if mesh == nil do return
    if mesh.vertices == nil do libellula_mesh_init(mesh)
    mesh.vertex_count = 0
    mesh.triangle_count = 0
    hubs := [3][3]f32{LIBELLULA_LEFT_HUB, LIBELLULA_RIGHT_HUB, LIBELLULA_REAR_HUB}
    top_nodes := [3][3]f32 {
        {LIBELLULA_LEFT_HUB[0], 1.02, LIBELLULA_LEFT_HUB[2]},
        {LIBELLULA_RIGHT_HUB[0], 1.02, LIBELLULA_RIGHT_HUB[2]},
        {LIBELLULA_REAR_HUB[0], 1.02, LIBELLULA_REAR_HUB[2]},
    }
    lower_nodes: [3][3]f32
    for node, index in top_nodes {
        radial := (node - {LIBELLULA_CENTROID[0], node[1], LIBELLULA_CENTROID[2]})
        lower_nodes[index] = ({LIBELLULA_CENTROID[0], .55, LIBELLULA_CENTROID[2]} + (radial * .84))
    }
    for index in 0 ..< 3 {
        next := (index + 1) % 3
        libellula_add_beam(mesh, top_nodes[index], top_nodes[next], .115, .Lift_Frame)
        libellula_add_beam(mesh, lower_nodes[index], lower_nodes[next], .082, .Lift_Frame)
        libellula_add_beam(mesh, top_nodes[index], lower_nodes[next], .06, .Lift_Frame)
        libellula_add_beam(mesh, top_nodes[index], lower_nodes[index], .074, .Lift_Frame)
        inward := linalg.normalize0(
            ([3]f32{LIBELLULA_CENTROID[0], hubs[index][1], LIBELLULA_CENTROID[2]} - hubs[index]),
        )
        if linalg.dot(inward, inward) < .0000000001 do inward = {0, 1, 0}
        lateral := linalg.normalize0(linalg.cross([3]f32{0, 1, 0}, inward))
        if linalg.dot(lateral, lateral) < .0000000001 do lateral = {0, 1, 0}
        fork_sides := [2]f32{-.16, .16}
        for side in fork_sides {
            libellula_add_beam(
                mesh,
                (lower_nodes[index] + (lateral * side)),
                ((hubs[index] + {0, -.2, 0}) + (lateral * side)),
                .07,
                .Lift_Frame,
            )
        }
        libellula_add_cylinder(mesh, {hubs[index][0], .98, hubs[index][2]}, {0, 1, 0}, .34, .34, .11, 8, .Lift_Frame)
        libellula_add_torus(mesh, {hubs[index][0], 1.045, hubs[index][2]}, {0, 1, 0}, .2, .29, 12, 5, .Brass)
        libellula_add_cylinder(mesh, {hubs[index][0], 1.06, hubs[index][2]}, {0, 1, 0}, .08, .08, .15, 8, .Steel)
    }

    manifold := [3]f32{LIBELLULA_CENTROID[0], .9, LIBELLULA_CENTROID[2]}
    libellula_add_cylinder(mesh, manifold, {0, 1, 0}, .24, .2, .24, 12, .Steel)
    libellula_add_torus(mesh, (manifold + {0, .08, 0}), {0, 1, 0}, .16, .23, 12, 5, .Brass)
    libellula_add_cylinder(mesh, (manifold + {0, .15, 0}), {0, 1, 0}, .08, .08, .04, 8, .Red_Paint)
    for hub in hubs {
        target := [3]f32{hub[0], .82, hub[2]}
        direction := linalg.normalize0(target - manifold)
        if linalg.dot(direction, direction) < .0000000001 do direction = {0, 1, 0}
        side := (linalg.normalize0(linalg.cross([3]f32{0, 1, 0}, direction)) * .045)
        if linalg.dot(side, side) < .0000000001 do side = {0, 1, 0} * .045
        elbow := ((manifold + (target - manifold) * .54) + {0, -.07, 0})
        libellula_add_beam(mesh, (manifold + side), (elbow + side), .018, .Red_Paint)
        libellula_add_beam(mesh, (elbow + side), (target + side), .018, .Red_Paint)
        libellula_add_beam(mesh, (manifold - side), (elbow - side), .016, .Brass)
        libellula_add_beam(mesh, (elbow - side), (target - side), .016, .Brass)
        libellula_add_sphere(mesh, elbow, .045, 6, 3, .Steel)
        libellula_add_torus(mesh, target, {0, 1, 0}, .035, .065, 8, 4, .Brass)
    }

    frame_anchors := [3][3]f32{{-1.16, .86, .65}, {1.16, .86, .65}, {0, .86, 3.05}}
    for anchor, index in frame_anchors {
        next := (index + 1) % 3
        libellula_add_beam(mesh, anchor, frame_anchors[next], .055, .Lift_Frame)
        libellula_add_beam(mesh, anchor, lower_nodes[index], .052, .Lift_Frame)
        libellula_add_cylinder(mesh, anchor, {0, 1, 0}, .19, .16, .12, 8, .Lift_Frame)
        libellula_add_torus(mesh, (anchor + {0, .065, 0}), {0, 1, 0}, .085, .145, 10, 5, .Brass)
        add_box(mesh, (anchor + {-.12, -.06, 0}), {.045, .22, .2}, .Lift_Frame)
        add_box(mesh, (anchor + {.12, -.06, 0}), {.045, .22, .2}, .Lift_Frame)
        libellula_add_cylinder(mesh, (anchor + {0, .02, 0}), {1, 0, 0}, .055, .055, .36, 8, .Steel)
    }

    libellula_add_rotor(mesh, hubs[0], 0, .Left_Rotor, .Libellula_Left_Rotor)
    libellula_add_rotor(mesh, hubs[1], 1, .Right_Rotor, .Libellula_Right_Rotor)
    libellula_add_rotor(mesh, hubs[2], 2, .Rear_Rotor, .Libellula_Rear_Rotor)

    // Four tall frame landing legs and their structural shoes.
    mounts := [4][3]f32{{-1.25, .72, .45}, {1.25, .72, .45}, {-1.25, .72, 2.25}, {1.25, .72, 2.25}}
    feet := [4][3]f32{{-2.85, -2.55, -.8}, {2.85, -2.55, -.8}, {-2.85, -2.55, 3.4}, {2.85, -2.55, 3.4}}
    for mount, index in mounts {
        foot := feet[index]
        knee := (mount + (foot - mount) * .58)
        fore_aft := f32(-1)
        if index >= 2 do fore_aft = 1
        side_shift := f32(.18)
        if mount[0] > 0 do side_shift = -.18
        second_root := (mount + {side_shift, .08, fore_aft * .46})
        libellula_add_beam(mesh, mount, knee, .095, .Wheel)
        libellula_add_beam(mesh, second_root, knee, .052, .Wheel)
        libellula_add_beam(mesh, knee, foot, .072, .Wheel)
        libellula_add_beam(mesh, mount, second_root, .06, .Lift_Frame)
        add_box(mesh, (mount + (second_root - mount) * .5), {.42, .12, .34}, .Lift_Frame)
        libellula_add_torus(mesh, mount, {0, 1, 0}, .09, .145, 10, 5, .Brass)
        libellula_add_cylinder(mesh, knee, (foot - knee), .115, .115, .16, 8, .Red_Paint)
        add_box(mesh, foot, {.58, .13, .46}, .Wheel)
        add_box(mesh, (foot + {0, -.075, 0}), {.48, .025, .36}, .Bumper)
    }

    libellula_add_carriage_geometry(mesh)

    carriage_anchors_local := [3][3]f32{{-.58, .36, -1.25}, {.58, .36, -1.25}, {0, .36, 1.55}}
    strap_groups := [3]Mesh_Animation_Group{.Libellula_Strap_Left, .Libellula_Strap_Right, .Libellula_Strap_Rear}
    for anchor, index in frame_anchors {
        lower := (LIBELLULA_CARRIAGE_OFFSET + carriage_anchors_local[index])
        libellula_add_dynamic_beam(mesh, anchor, lower, .105, .Strap, strap_groups[index])
    }
    kingpost_upper := [3]f32{0, .76, LIBELLULA_SUSPENSION_CENTER_Z - .03}
    kingpost_lower := (LIBELLULA_CARRIAGE_OFFSET + {0, .36, .12})
    span := (kingpost_lower - kingpost_upper)
    libellula_add_sphere(mesh, kingpost_upper, .14, 10, 5, .Brass)
    libellula_add_dynamic_beam(
        mesh,
        kingpost_upper,
        (kingpost_upper + (span * .62)),
        .105,
        .Steel,
        .Libellula_Kingpost_Outer,
    )
    libellula_add_dynamic_beam(
        mesh,
        (kingpost_upper + (span * .42)),
        kingpost_lower,
        .065,
        .Brass,
        .Libellula_Kingpost_Inner,
    )
    libellula_add_dynamic_beam(
        mesh,
        (kingpost_upper + (span * .58)),
        (kingpost_upper + (span * .7)),
        .14,
        .Red_Paint,
        .Libellula_Kingpost_Stop,
    )
    cable_groups := [2][2]Mesh_Animation_Group {
        {.Libellula_Umbilical_1_Upper, .Libellula_Umbilical_1_Lower},
        {.Libellula_Umbilical_2_Upper, .Libellula_Umbilical_2_Lower},
    }
    umbilical_xs := [2]f32{-.14, .14}
    for x, index in umbilical_xs {
        upper := [3]f32{x, .72, LIBELLULA_SUSPENSION_CENTER_Z - .03}
        lower := (LIBELLULA_CARRIAGE_OFFSET + {x, .29, .12})
        sag := ((upper + (lower - upper) * .5) + {0, -.16, 0})
        part := Aircraft_Mesh_Part.Red_Paint
        if index == 1 do part = .Steel
        libellula_add_dynamic_beam(mesh, upper, sag, .018, part, cable_groups[index][0])
        libellula_add_dynamic_beam(mesh, sag, lower, .018, part, cable_groups[index][1])
    }
    mesh_finalize(
        mesh,
        &libellula_mesh_cache,
        libellula_uvs[:],
        libellula_sources[:],
        libellula_indices[:],
        libellula_scratch[:],
    )
}

libellula_mesh :: proc(allocator := context.allocator) -> Libellula_Mesh {
    mesh: Libellula_Mesh
    libellula_mesh_init(&mesh, allocator)
    libellula_mesh_build(&mesh)
    return mesh
}
