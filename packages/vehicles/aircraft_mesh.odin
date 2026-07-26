package vehicles

import "core:math"
import "core:mem"

// Product-local triangle meshes ported from Archipelago's procedural player
// aircraft. They contain geometry and presentation groups only: Godot nodes,
// shaders, paint damage and physics remain deliberately outside this package.

Aircraft_Mesh_Part :: enum u8 {
    Body,
    Wing,
    Tail,
    Glass,
    Engine,
    Propeller,
    Propeller_Blur,
    Left_Propeller,
    Right_Propeller,
    Left_Rotor,
    Right_Rotor,
    Rear_Rotor,
    Mk2_Rear_Rotor,
    Left_Flap,
    Right_Flap,
    Left_Aileron,
    Right_Aileron,
    Elevator,
    Rudder,
    Float,
    Frame,
    Carriage,
    Wheel,
    Bumper,
    Headlight,
    Tail_Light,
    Ivory,
    Red_Paint,
    Dark_Metal,
    Steel,
    Brass,
    Strap,
    Rotor_Blade,
    Rotor_Tip,
    Marking,
    Lift_Frame,
}

Mesh_Animation_Group :: enum u8 {
    None,
    Libellula_Carriage,
    Libellula_Strap_Left,
    Libellula_Strap_Right,
    Libellula_Strap_Rear,
    Libellula_Kingpost_Outer,
    Libellula_Kingpost_Inner,
    Libellula_Kingpost_Stop,
    Libellula_Umbilical_1_Upper,
    Libellula_Umbilical_1_Lower,
    Libellula_Umbilical_2_Upper,
    Libellula_Umbilical_2_Lower,
    Libellula_Left_Rotor,
    Libellula_Right_Rotor,
    Libellula_Rear_Rotor,
    Libellula_Mk2_Rear_Rotor,
}

Mesh_Vertex :: struct {
    position:        [3]f32,
    normal:          [3]f32,
    uv:              [2]f32,
    part:            Aircraft_Mesh_Part,
    animation_group: Mesh_Animation_Group,
}

Mesh_Triangle :: struct {
    a, b, c: u16,
}

AIRCRAFT_MESH_VERTEX_CAPACITY :: 6400
AIRCRAFT_MESH_TRIANGLE_CAPACITY :: 4096
LIBELLULA_MESH_VERTEX_CAPACITY :: 57344
LIBELLULA_MESH_TRIANGLE_CAPACITY :: 19114

Aircraft_Mesh :: struct {
    vertices:       [AIRCRAFT_MESH_VERTEX_CAPACITY]Mesh_Vertex,
    triangles:      [AIRCRAFT_MESH_TRIANGLE_CAPACITY]Mesh_Triangle,
    vertex_count:   int,
    triangle_count: int,
}

Libellula_Mesh :: struct {
    vertices:       []Mesh_Vertex,
    triangles:      []Mesh_Triangle,
    vertex_count:   int,
    triangle_count: int,
    allocator:      mem.Allocator,
}

libellula_mesh_init :: proc(mesh: ^Libellula_Mesh, allocator := context.allocator) {
    if mesh == nil || mesh.vertices != nil do return
    mesh.vertices = make([]Mesh_Vertex, LIBELLULA_MESH_VERTEX_CAPACITY, allocator)
    mesh.triangles = make([]Mesh_Triangle, LIBELLULA_MESH_TRIANGLE_CAPACITY, allocator)
    mesh.allocator = allocator
}

libellula_mesh_destroy :: proc(mesh: ^Libellula_Mesh) {
    if mesh == nil do return
    if mesh.vertices != nil do delete(mesh.vertices, mesh.allocator)
    if mesh.triangles != nil do delete(mesh.triangles, mesh.allocator)
    mesh^ = {}
}

libellula_mesh_copy :: proc(destination, source: ^Libellula_Mesh) {
    if destination == nil || source == nil || source.vertices == nil || source.triangles == nil do return
    if destination.vertices == nil do libellula_mesh_init(destination)
    destination.vertex_count = source.vertex_count
    destination.triangle_count = source.triangle_count
    copy(destination.vertices[:destination.vertex_count], source.vertices[:source.vertex_count])
    copy(destination.triangles[:destination.triangle_count], source.triangles[:source.triangle_count])
}

Mesh_Ring :: struct {
    z, width, center_y, height: f32,
}
Mesh_Section :: struct {
    x, leading, trailing, half_thickness: f32,
}
Mesh_Profile_Point :: struct {
    z, y: f32,
}

mesh_vertices :: proc(mesh: ^$Mesh) -> []Mesh_Vertex {
    if mesh == nil do return nil
    return mesh.vertices[:mesh.vertex_count]
}

mesh_triangles :: proc(mesh: ^$Mesh) -> []Mesh_Triangle {
    if mesh == nil do return nil
    return mesh.triangles[:mesh.triangle_count]
}

mesh_generate_smooth_normals :: proc(mesh: ^$Mesh) {
    if mesh == nil do return
    for vertex_index in 0 ..< mesh.vertex_count {
        vertex := &mesh.vertices[vertex_index]
        sum: [3]f32
        for triangle in mesh.triangles[:mesh.triangle_count] {
            a := mesh.vertices[triangle.a]
            if a.part != vertex.part do continue
            b := mesh.vertices[triangle.b]
            c := mesh.vertices[triangle.c]
            shares_position := false
            corners := [3]Mesh_Vertex{a, b, c}
            for corner in corners {
                delta := corner.position - vertex.position
                if delta[0] * delta[0] + delta[1] * delta[1] + delta[2] * delta[2] < .000001 {
                    shares_position = true
                    break
                }
            }
            if !shares_position do continue
            ab := b.position - a.position
            ac := c.position - a.position
            sum += [3]f32{ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0]}
        }
        length := f32(math.sqrt(f64(sum[0] * sum[0] + sum[1] * sum[1] + sum[2] * sum[2])))
        if length > .0001 do vertex.normal = sum / length
    }
}

aircraft_mesh_part_uses_smooth_normals :: proc(part: Aircraft_Mesh_Part) -> bool {
    #partial switch part {
    case .Body,
         .Wing,
         .Tail,
         .Engine,
         .Wheel,
         .Propeller,
         .Left_Flap,
         .Right_Flap,
         .Left_Aileron,
         .Right_Aileron,
         .Elevator,
         .Rudder:
        return true
    }
    return false
}

mesh_triangle :: proc(mesh: ^$Mesh, a, b, c: [3]f32, part: Aircraft_Mesh_Part) {
    if mesh == nil || mesh.vertex_count + 3 > len(mesh.vertices) || mesh.triangle_count >= len(mesh.triangles) {
        return
    }
    first := mesh.vertex_count
    mesh.vertices[first + 0] = {
        position = a,
        part     = part,
    }
    mesh.vertices[first + 1] = {
        position = b,
        part     = part,
    }
    mesh.vertices[first + 2] = {
        position = c,
        part     = part,
    }
    mesh.triangles[mesh.triangle_count] = {u16(first), u16(first + 1), u16(first + 2)}
    mesh.vertex_count += 3
    mesh.triangle_count += 1
}

mesh_quad :: proc(mesh: ^$Mesh, a, b, c, d: [3]f32, part: Aircraft_Mesh_Part) {
    mesh_triangle(mesh, a, c, b, part)
    mesh_triangle(mesh, a, d, c, part)
}

ring_point :: proc(ring: Mesh_Ring, side, sides: int) -> [3]f32 {
    angle := f32(side) * 2 * math.PI / f32(sides)
    return {math.cos(angle) * ring.width, ring.center_y + math.sin(angle) * ring.height, ring.z}
}

add_ring_mesh :: proc(mesh: ^Aircraft_Mesh, rings: []Mesh_Ring, sides: int, part: Aircraft_Mesh_Part) {
    if len(rings) < 2 || sides < 3 do return
    for ring_index in 0 ..< len(rings) - 1 {
        for side in 0 ..< sides {
            next := (side + 1) % sides
            mesh_quad(
                mesh,
                ring_point(rings[ring_index], side, sides),
                ring_point(rings[ring_index + 1], side, sides),
                ring_point(rings[ring_index + 1], next, sides),
                ring_point(rings[ring_index], next, sides),
                part,
            )
        }
    }
    front := [3]f32{0, rings[0].center_y, rings[0].z}
    rear := [3]f32{0, rings[len(rings) - 1].center_y, rings[len(rings) - 1].z}
    for side in 0 ..< sides {
        next := (side + 1) % sides
        mesh_triangle(mesh, front, ring_point(rings[0], next, sides), ring_point(rings[0], side, sides), part)
        mesh_triangle(
            mesh,
            rear,
            ring_point(rings[len(rings) - 1], side, sides),
            ring_point(rings[len(rings) - 1], next, sides),
            part,
        )
    }
}

add_compact_ring_mesh :: proc(mesh: ^Aircraft_Mesh, rings: []Mesh_Ring, sides: int, part: Aircraft_Mesh_Part) {
    if mesh == nil || len(rings) < 2 || sides < 3 do return
    required_vertices := len(rings) * sides + 2
    required_triangles := (len(rings) - 1) * sides * 2 + sides * 2
    if mesh.vertex_count + required_vertices > len(mesh.vertices) ||
       mesh.triangle_count + required_triangles > len(mesh.triangles) {
        return
    }

    first := mesh.vertex_count
    for ring in rings {
        for side in 0 ..< sides {
            mesh.vertices[mesh.vertex_count] = {
                position = ring_point(ring, side, sides),
                part     = part,
            }
            mesh.vertex_count += 1
        }
    }
    front_index := mesh.vertex_count
    mesh.vertices[mesh.vertex_count] = {
        position = {0, rings[0].center_y, rings[0].z},
        part     = part,
    }
    mesh.vertex_count += 1
    rear_index := mesh.vertex_count
    mesh.vertices[mesh.vertex_count] = {
        position = {0, rings[len(rings) - 1].center_y, rings[len(rings) - 1].z},
        part     = part,
    }
    mesh.vertex_count += 1

    for ring_index in 0 ..< len(rings) - 1 {
        for side in 0 ..< sides {
            next := (side + 1) % sides
            a := first + ring_index * sides + side
            b := first + (ring_index + 1) * sides + side
            c := first + (ring_index + 1) * sides + next
            d := first + ring_index * sides + next
            mesh.triangles[mesh.triangle_count] = {u16(a), u16(c), u16(b)}
            mesh.triangle_count += 1
            mesh.triangles[mesh.triangle_count] = {u16(a), u16(d), u16(c)}
            mesh.triangle_count += 1
        }
    }
    for side in 0 ..< sides {
        next := (side + 1) % sides
        front_side := first + side
        front_next := first + next
        rear_side := first + (len(rings) - 1) * sides + side
        rear_next := first + (len(rings) - 1) * sides + next
        mesh.triangles[mesh.triangle_count] = {u16(front_index), u16(front_next), u16(front_side)}
        mesh.triangle_count += 1
        mesh.triangles[mesh.triangle_count] = {u16(rear_index), u16(rear_side), u16(rear_next)}
        mesh.triangle_count += 1
    }
}

add_ring_mesh_at_x :: proc(mesh: ^Aircraft_Mesh, rings: []Mesh_Ring, sides: int, x: f32, part: Aircraft_Mesh_Part) {
    first := mesh.vertex_count
    add_ring_mesh(mesh, rings, sides, part)
    for index in first ..< mesh.vertex_count { mesh.vertices[index].position[0] += x }
}

add_section_mesh :: proc(mesh: ^Aircraft_Mesh, sections: []Mesh_Section, y: f32, part: Aircraft_Mesh_Part) {
    if len(sections) < 2 do return
    for index in 0 ..< len(sections) - 1 {
        a := sections[index]; b := sections[index + 1]
        p0 := [3]f32{a.x, y - a.half_thickness, a.leading}; p1 := [3]f32{a.x, y - a.half_thickness, a.trailing}
        p2 := [3]f32{a.x, y + a.half_thickness, a.trailing}; p3 := [3]f32{a.x, y + a.half_thickness, a.leading}
        q0 := [3]f32{b.x, y - b.half_thickness, b.leading}; q1 := [3]f32{b.x, y - b.half_thickness, b.trailing}
        q2 := [3]f32{b.x, y + b.half_thickness, b.trailing}; q3 := [3]f32{b.x, y + b.half_thickness, b.leading}
        mesh_quad(mesh, p0, p1, q1, q0, part); mesh_quad(mesh, p3, q3, q2, p2, part)
        mesh_quad(mesh, p1, p2, q2, q1, part); mesh_quad(mesh, p0, q0, q3, p3, part)
        if index == 0 do mesh_quad(mesh, p0, p3, p2, p1, part)
        if index == len(sections) - 2 do mesh_quad(mesh, q0, q1, q2, q3, part)
    }
}

add_profile_prism :: proc(
    mesh: ^Aircraft_Mesh,
    profile: []Mesh_Profile_Point,
    half_width: f32,
    part: Aircraft_Mesh_Part,
) {
    if len(profile) < 3 do return
    for index in 1 ..< len(profile) - 1 {
        mesh_triangle(
            mesh,
            {-half_width, profile[0].y, profile[0].z},
            {-half_width, profile[index + 1].y, profile[index + 1].z},
            {-half_width, profile[index].y, profile[index].z},
            part,
        )
        mesh_triangle(
            mesh,
            {half_width, profile[0].y, profile[0].z},
            {half_width, profile[index].y, profile[index].z},
            {half_width, profile[index + 1].y, profile[index + 1].z},
            part,
        )
    }
    for index in 0 ..< len(profile) {
        next := (index + 1) % len(profile)
        mesh_quad(
            mesh,
            {-half_width, profile[index].y, profile[index].z},
            {half_width, profile[index].y, profile[index].z},
            {half_width, profile[next].y, profile[next].z},
            {-half_width, profile[next].y, profile[next].z},
            part,
        )
    }
}

add_profile_prism_at_x :: proc(
    mesh: ^Aircraft_Mesh,
    profile: []Mesh_Profile_Point,
    half_width, x: f32,
    part: Aircraft_Mesh_Part,
) {
    first := mesh.vertex_count
    add_profile_prism(mesh, profile, half_width, part)
    for index in first ..< mesh.vertex_count do mesh.vertices[index].position[0] += x
}

add_box :: proc(mesh: ^$Mesh, center, size: [3]f32, part: Aircraft_Mesh_Part) {
    x := size[0] * .5; y := size[1] * .5; z := size[2] * .5
    p := [8][3]f32 {
        {center[0] - x, center[1] - y, center[2] - z},
        {center[0] + x, center[1] - y, center[2] - z},
        {center[0] + x, center[1] + y, center[2] - z},
        {center[0] - x, center[1] + y, center[2] - z},
        {center[0] - x, center[1] - y, center[2] + z},
        {center[0] + x, center[1] - y, center[2] + z},
        {center[0] + x, center[1] + y, center[2] + z},
        {center[0] - x, center[1] + y, center[2] + z},
    }
    mesh_quad(mesh, p[0], p[1], p[2], p[3], part); mesh_quad(mesh, p[5], p[4], p[7], p[6], part)
    mesh_quad(mesh, p[4], p[0], p[3], p[7], part); mesh_quad(mesh, p[1], p[5], p[6], p[2], part)
    mesh_quad(mesh, p[3], p[2], p[6], p[7], part); mesh_quad(mesh, p[4], p[5], p[1], p[0], part)
}

mark_new_vertices :: proc(mesh: ^$Mesh, first: int, group: Mesh_Animation_Group) {
    if mesh == nil do return
    for index in first ..< mesh.vertex_count {
        mesh.vertices[index].animation_group = group
    }
}

translate_new_vertices :: proc(mesh: ^$Mesh, first: int, offset: [3]f32) {
    if mesh == nil do return
    for index in first ..< mesh.vertex_count {
        mesh.vertices[index].position += offset
    }
}

rotate_new_vertices_x :: proc(mesh: ^$Mesh, first: int, pivot: [3]f32, angle: f32) {
    c := math.cos(angle)
    s := math.sin(angle)
    for index in first ..< mesh.vertex_count {
        y := mesh.vertices[index].position[1] - pivot[1]
        z := mesh.vertices[index].position[2] - pivot[2]
        mesh.vertices[index].position[1] = pivot[1] + y * c - z * s
        mesh.vertices[index].position[2] = pivot[2] + y * s + z * c
    }
}

rotate_new_vertices_z :: proc(mesh: ^$Mesh, first: int, pivot: [3]f32, angle: f32) {
    c := math.cos(angle); s := math.sin(angle)
    for index in first ..< mesh.vertex_count {
        x := mesh.vertices[index].position[0] - pivot[0]; y := mesh.vertices[index].position[1] - pivot[1]
        mesh.vertices[index].position[0] = pivot[0] + x * c - y * s
        mesh.vertices[index].position[1] = pivot[1] + x * s + y * c
    }
}

rotate_new_vertices_y :: proc(mesh: ^$Mesh, first: int, pivot: [3]f32, angle: f32) {
    c := math.cos(angle); s := math.sin(angle)
    for index in first ..< mesh.vertex_count {
        x := mesh.vertices[index].position[0] - pivot[0]
        z := mesh.vertices[index].position[2] - pivot[2]
        mesh.vertices[index].position[0] = pivot[0] + x * c + z * s
        mesh.vertices[index].position[2] = pivot[2] - x * s + z * c
    }
}

add_propeller :: proc(mesh: ^Aircraft_Mesh, pivot: [3]f32, radius, chord, thickness: f32, part: Aircraft_Mesh_Part) {
    for blade in 0 ..< 3 {
        first := mesh.vertex_count
        add_box(mesh, {pivot[0], pivot[1] + radius * .52, pivot[2]}, {chord, radius, thickness}, part)
        rotate_new_vertices_z(mesh, first, pivot, f32(blade) * 2 * math.PI / 3)
    }
}

add_postale_propeller :: proc(mesh: ^Aircraft_Mesh, pivot: [3]f32) {
    blade := proc(mesh: ^Aircraft_Mesh, pivot: [3]f32, angle: f32) {
        first := mesh.vertex_count
        root_y := pivot[1] + .24
        shoulder_y := pivot[1] + .62
        tip_y := pivot[1] + 1.44
        front_z := pivot[2] - .045
        back_z := pivot[2] + .045
        root_half := f32(.085)
        shoulder_half := f32(.125)
        tip_half := f32(.045)
        front := [6][3]f32 {
            {pivot[0] - root_half, root_y, front_z},
            {pivot[0] + root_half, root_y, front_z},
            {pivot[0] - shoulder_half, shoulder_y, front_z},
            {pivot[0] + shoulder_half, shoulder_y, front_z},
            {pivot[0] - tip_half, tip_y, front_z},
            {pivot[0] + tip_half, tip_y, front_z},
        }
        back := front
        for &point in back do point[2] = back_z
        mesh_quad(mesh, front[0], front[1], front[3], front[2], .Propeller)
        mesh_quad(mesh, front[2], front[3], front[5], front[4], .Propeller)
        mesh_quad(mesh, back[1], back[0], back[2], back[3], .Propeller)
        mesh_quad(mesh, back[3], back[2], back[4], back[5], .Propeller)
        mesh_quad(mesh, front[0], front[2], back[2], back[0], .Propeller)
        mesh_quad(mesh, front[2], front[4], back[4], back[2], .Propeller)
        mesh_quad(mesh, front[3], front[1], back[1], back[3], .Propeller)
        mesh_quad(mesh, front[5], front[3], back[3], back[5], .Propeller)
        mesh_quad(mesh, front[4], front[5], back[5], back[4], .Propeller)
        rotate_new_vertices_z(mesh, first, pivot, angle)
    }
    // Three broad blades give the compact radial nose a strong, readable
    // silhouette without parking a single bar across the engine opening.
    blade(mesh, pivot, 0)
    blade(mesh, pivot, math.PI * 2 / 3)
    blade(mesh, pivot, math.PI * 4 / 3)

    spinner := [4]Mesh_Ring {
        // Long, nearly pointed spinner with a restrained convex shoulder.
        // The previous short profile read as a red ball at gameplay distance.
        {pivot[2] - .50, .008, pivot[1], .008},
        {pivot[2] - .34, .060, pivot[1], .060},
        {pivot[2] - .17, .116, pivot[1], .116},
        {pivot[2] + .025, .172, pivot[1], .172},
    }
    add_compact_ring_mesh(mesh, spinner[:], 16, .Engine)
}

// A shallow translucent disk is the high-RPM propeller volume. It is kept as
// product geometry so the renderer can fade it independently from the solid
// blades, matching the airborne blur handoff used by the reference aircraft.
add_propeller_spin_volume :: proc(mesh: ^Aircraft_Mesh, pivot: [3]f32, radius, depth: f32) {
    SEGMENTS :: 24
    front_z := pivot[2] - depth * .5
    back_z := pivot[2] + depth * .5
    front_center := [3]f32{pivot[0], pivot[1], front_z}
    back_center := [3]f32{pivot[0], pivot[1], back_z}
    for index in 0 ..< SEGMENTS {
        next := (index + 1) % SEGMENTS
        angle := f32(index) * 2 * math.PI / f32(SEGMENTS)
        next_angle := f32(next) * 2 * math.PI / f32(SEGMENTS)
        front_a := [3]f32{pivot[0] + math.cos(angle) * radius, pivot[1] + math.sin(angle) * radius, front_z}
        front_b := [3]f32{pivot[0] + math.cos(next_angle) * radius, pivot[1] + math.sin(next_angle) * radius, front_z}
        back_a := [3]f32{pivot[0] + math.cos(angle) * radius, pivot[1] + math.sin(angle) * radius, back_z}
        back_b := [3]f32{pivot[0] + math.cos(next_angle) * radius, pivot[1] + math.sin(next_angle) * radius, back_z}
        // Both caps are emitted because the aircraft can be viewed from
        // either side of the propeller disk.
        mesh_triangle(mesh, front_center, front_b, front_a, .Propeller_Blur)
        mesh_triangle(mesh, back_center, back_a, back_b, .Propeller_Blur)
        mesh_quad(mesh, front_a, front_b, back_b, back_a, .Propeller_Blur)
    }
}

add_horizontal_beam :: proc(mesh: ^Aircraft_Mesh, a, b: [3]f32, width: f32, part: Aircraft_Mesh_Part) {
    dx := b[0] - a[0]; dz := b[2] - a[2]
    length := f32(math.sqrt(f64(dx * dx + dz * dz)))
    if length < .0001 do return
    sx := -dz / length * width * .5; sz := dx / length * width * .5; low := -width * .5; high := width * .5
    p := [8][3]f32 {
        {a[0] + sx, a[1] + low, a[2] + sz},
        {a[0] - sx, a[1] + low, a[2] - sz},
        {a[0] - sx, a[1] + high, a[2] - sz},
        {a[0] + sx, a[1] + high, a[2] + sz},
        {b[0] + sx, b[1] + low, b[2] + sz},
        {b[0] - sx, b[1] + low, b[2] - sz},
        {b[0] - sx, b[1] + high, b[2] - sz},
        {b[0] + sx, b[1] + high, b[2] + sz},
    }
    mesh_quad(mesh, p[0], p[1], p[2], p[3], part); mesh_quad(mesh, p[5], p[4], p[7], p[6], part)
    mesh_quad(mesh, p[4], p[0], p[3], p[7], part); mesh_quad(mesh, p[1], p[5], p[6], p[2], part)
    mesh_quad(mesh, p[3], p[2], p[6], p[7], part); mesh_quad(mesh, p[4], p[5], p[1], p[0], part)
}

add_strut :: proc(mesh: ^Aircraft_Mesh, a, b: [3]f32, width: f32, part: Aircraft_Mesh_Part) {
    dx := b[0] - a[0]
    dy := b[1] - a[1]
    dz := b[2] - a[2]
    length := f32(math.sqrt(f64(dx * dx + dy * dy + dz * dz)))
    if length < .0001 do return
    direction := [3]f32{dx / length, dy / length, dz / length}
    reference := [3]f32{0, 1, 0}
    if abs(direction[1]) > .92 do reference = {0, 0, 1}
    side := [3]f32 {
        direction[1] * reference[2] - direction[2] * reference[1],
        direction[2] * reference[0] - direction[0] * reference[2],
        direction[0] * reference[1] - direction[1] * reference[0],
    }
    side_length := f32(math.sqrt(f64(side[0] * side[0] + side[1] * side[1] + side[2] * side[2])))
    side *= width * .5 / side_length
    up := [3]f32 {
        direction[1] * side[2] - direction[2] * side[1],
        direction[2] * side[0] - direction[0] * side[2],
        direction[0] * side[1] - direction[1] * side[0],
    }
    up *= width * .5
    p := [8][3]f32 {
        a - side - up,
        a + side - up,
        a + side + up,
        a - side + up,
        b - side - up,
        b + side - up,
        b + side + up,
        b - side + up,
    }
    mesh_quad(mesh, p[0], p[1], p[2], p[3], part); mesh_quad(mesh, p[5], p[4], p[7], p[6], part)
    mesh_quad(mesh, p[4], p[0], p[3], p[7], part); mesh_quad(mesh, p[1], p[5], p[6], p[2], part)
    mesh_quad(mesh, p[3], p[2], p[6], p[7], part); mesh_quad(mesh, p[4], p[5], p[1], p[0], part)
}

add_cockpit_gauge :: proc(mesh: ^Aircraft_Mesh, center: [3]f32, radius: f32) {
    SEGMENTS :: 12
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        angle := f32(segment) * 2 * math.PI / f32(SEGMENTS)
        next_angle := f32(next) * 2 * math.PI / f32(SEGMENTS)
        mesh_triangle(
            mesh,
            center,
            {center[0] + math.cos(angle) * radius, center[1] + math.sin(angle) * radius, center[2]},
            {center[0] + math.cos(next_angle) * radius, center[1] + math.sin(next_angle) * radius, center[2]},
            .Brass,
        )
    }
}

add_ellipse_disc_z :: proc(mesh: ^Aircraft_Mesh, center: [3]f32, radius_x, radius_y: f32, part: Aircraft_Mesh_Part) {
    SEGMENTS :: 12
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        angle := f32(segment) * 2 * math.PI / f32(SEGMENTS)
        next_angle := f32(next) * 2 * math.PI / f32(SEGMENTS)
        a := [3]f32{center[0] + math.cos(angle) * radius_x, center[1] + math.sin(angle) * radius_y, center[2]}
        b := [3]f32 {
            center[0] + math.cos(next_angle) * radius_x,
            center[1] + math.sin(next_angle) * radius_y,
            center[2],
        }
        mesh_triangle(mesh, center, b, a, part)
    }
}

add_ellipse_annulus_z :: proc(
    mesh: ^Aircraft_Mesh,
    center: [3]f32,
    outer_x, outer_y, inner_x, inner_y: f32,
    part: Aircraft_Mesh_Part,
) {
    SEGMENTS :: 20
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        angle := f32(segment) * 2 * math.PI / f32(SEGMENTS)
        next_angle := f32(next) * 2 * math.PI / f32(SEGMENTS)
        outer_a := [3]f32{center[0] + math.cos(angle) * outer_x, center[1] + math.sin(angle) * outer_y, center[2]}
        outer_b := [3]f32 {
            center[0] + math.cos(next_angle) * outer_x,
            center[1] + math.sin(next_angle) * outer_y,
            center[2],
        }
        inner_a := [3]f32 {
            center[0] + math.cos(angle) * inner_x,
            center[1] + math.sin(angle) * inner_y,
            center[2] - .002,
        }
        inner_b := [3]f32 {
            center[0] + math.cos(next_angle) * inner_x,
            center[1] + math.sin(next_angle) * inner_y,
            center[2] - .002,
        }
        mesh_quad(mesh, outer_a, inner_a, inner_b, outer_b, part)
    }
}

// Postale's source model uses three exposed gravel wheels: two main wheels
// and a smaller tail wheel. Build them as low-poly rubber cylinders with
// visible hubs and tread blocks so they remain readable in the world mesh.
add_wheel :: proc(mesh: ^Aircraft_Mesh, center: [3]f32, radius, thickness: f32) {
    tire := [2]Mesh_Ring{{-.5 * thickness, radius, 0, radius}, {.5 * thickness, radius, 0, radius}}
    first := mesh.vertex_count
    add_ring_mesh(mesh, tire[:], 12, .Wheel)
    rotate_new_vertices_y(mesh, first, {0, 0, 0}, math.PI * .5)
    for index in first ..< mesh.vertex_count {
        mesh.vertices[index].position += center
    }

    hub := [2]Mesh_Ring {
        {-.56 * thickness, radius * .28, 0, radius * .28},
        {.56 * thickness, radius * .28, 0, radius * .28},
    }
    first = mesh.vertex_count
    add_ring_mesh(mesh, hub[:], 10, .Marking)
    rotate_new_vertices_y(mesh, first, {0, 0, 0}, math.PI * .5)
    for index in first ..< mesh.vertex_count {
        mesh.vertices[index].position += center
    }

    for tread in 0 ..< 6 {
        angle := f32(tread) * 2 * math.PI / 6
        add_box(
            mesh,
            {center[0], center[1] + math.cos(angle) * radius * .91, center[2] + math.sin(angle) * radius * .91},
            {thickness * 1.12, radius * .12, radius * .18},
            .Wheel,
        )
    }
}

// Build the Postale as one continuous skin from spinner to tail. The cockpit
// is a real opening in that skin: the upper facets are omitted through the
// seating bay and folded inward to a low cockpit sill. This keeps the body
// from reading as a stack of boxes while preserving a deliberately faceted,
// hand-built mailplane silhouette.
add_postale_hull :: proc(mesh: ^Aircraft_Mesh) {
    SIDES :: 12
    rings := [13]Mesh_Ring {
        {-3.28, .42, .10, .30},
        {-3.12, .64, .11, .47},
        {-2.72, .73, .12, .62},
        {-2.20, .70, .12, .78},
        {-1.55, .69, .10, .80},
        {-1.28, .68, .09, .78},
        {-.92, .67, .07, .75},
        {.28, .65, .10, .70},
        {.58, .61, .22, .72},
        {1.45, .48, .22, .53},
        {2.20, .34, .25, .37},
        {2.82, .18, .32, .21},
        {3.18, .055, .37, .065},
    }

    // Remove the broad upper crown through the seating bay. It is skinned back
    // in below around a tapered aperture; omitting these facets alone would
    // leave the long rectangular slot visible from above.
    for ring_index in 0 ..< len(rings) - 1 {
        cockpit_segment := ring_index >= 4 && ring_index <= 7
        hull_part := Aircraft_Mesh_Part.Body
        if ring_index < 2 do hull_part = .Engine
        for side in 0 ..< SIDES {
            if cockpit_segment && (side == 2 || side == 3) do continue
            next := (side + 1) % SIDES
            mesh_quad(
                mesh,
                ring_point(rings[ring_index], side, SIDES),
                ring_point(rings[ring_index + 1], side, SIDES),
                ring_point(rings[ring_index + 1], next, SIDES),
                ring_point(rings[ring_index], next, SIDES),
                hull_part,
            )
        }
    }

    // Five boundary sections form a compact teardrop opening: narrow at the
    // instrument panel, broad around the pilot, then pinched behind the seat.
    // Their Y values follow the crown of the elliptical fuselage sections.
    cockpit_right := [5][3]f32 {
        {.10, .891, -1.55},
        {.34, .766, -1.28},
        {.40, .672, -.92},
        {.34, .696, .28},
        {.10, .930, .58},
    }
    cockpit_left := cockpit_right
    for &point in cockpit_left do point[0] = -point[0]
    for segment in 0 ..< 4 {
        ring_index := segment + 4
        mesh_quad(
            mesh,
            ring_point(rings[ring_index], 2, SIDES),
            ring_point(rings[ring_index + 1], 2, SIDES),
            cockpit_right[segment + 1],
            cockpit_right[segment],
            .Body,
        )
        mesh_quad(
            mesh,
            cockpit_left[segment],
            cockpit_left[segment + 1],
            ring_point(rings[ring_index + 1], 4, SIDES),
            ring_point(rings[ring_index], 4, SIDES),
            .Body,
        )
    }

    nose := [3]f32{0, rings[0].center_y, rings[0].z}
    tail := [3]f32{0, rings[len(rings) - 1].center_y, rings[len(rings) - 1].z}
    for side in 0 ..< SIDES {
        next := (side + 1) % SIDES
        mesh_triangle(mesh, nose, ring_point(rings[0], next, SIDES), ring_point(rings[0], side, SIDES), .Dark_Metal)
        mesh_triangle(
            mesh,
            tail,
            ring_point(rings[len(rings) - 1], side, SIDES),
            ring_point(rings[len(rings) - 1], next, SIDES),
            .Body,
        )
    }

    // Fold the tapered skin edges down into the cockpit instead of covering
    // the opening with a separate rectangular coaming.
    sill_y := f32(.34)
    for segment in 0 ..< 4 {
        right_front := cockpit_right[segment]
        right_rear := cockpit_right[segment + 1]
        left_front := cockpit_left[segment]
        left_rear := cockpit_left[segment + 1]
        mesh_quad(
            mesh,
            right_front,
            right_rear,
            {right_rear[0], sill_y, right_rear[2]},
            {right_front[0], sill_y, right_front[2]},
            .Body,
        )
        mesh_quad(
            mesh,
            left_rear,
            left_front,
            {left_front[0], sill_y, left_front[2]},
            {left_rear[0], sill_y, left_rear[2]},
            .Body,
        )
    }
    mesh_quad(
        mesh,
        cockpit_left[0],
        cockpit_right[0],
        {cockpit_right[0][0], sill_y, cockpit_right[0][2]},
        {cockpit_left[0][0], sill_y, cockpit_left[0][2]},
        .Body,
    )
    mesh_quad(
        mesh,
        cockpit_right[4],
        cockpit_left[4],
        {cockpit_left[4][0], sill_y, cockpit_left[4][2]},
        {cockpit_right[4][0], sill_y, cockpit_right[4][2]},
        .Body,
    )

    // A recessed tub and seat complete the single-place cockpit. These are
    // interior fittings, not exterior hull primitives.
    mesh_quad(mesh, {-.42, -.48, -1.18}, {.42, -.48, -1.18}, {.42, -.48, .20}, {-.42, -.48, .20}, .Dark_Metal)
    add_box(mesh, {0, -.48, -.24}, {.62, .20, .52}, .Dark_Metal)
    add_box(mesh, {0, -.14, .08}, {.62, .68, .12}, .Dark_Metal)
    add_strut(mesh, {-.54, .42, -1.18}, {-.54, .46, .22}, .10, .Strap)
    add_strut(mesh, {.54, .42, -1.18}, {.54, .46, .22}, .10, .Strap)
    add_strut(mesh, {-.54, .42, -1.18}, {.54, .42, -1.18}, .10, .Strap)
    add_strut(mesh, {-.54, .46, .22}, {.54, .46, .22}, .10, .Strap)
    headrest := [2]Mesh_Ring{{.20, .28, .48, .34}, {.30, .28, .48, .34}}
    add_ring_mesh(mesh, headrest[:], 12, .Strap)
    mesh_quad(mesh, {-.45, .08, -1.05}, {.45, .08, -1.05}, {.40, .43, -1.10}, {-.40, .43, -1.10}, .Dark_Metal)
    add_cockpit_gauge(mesh, {-.23, .29, -1.105}, .095)
    add_cockpit_gauge(mesh, {0, .23, -1.108}, .09)
    add_cockpit_gauge(mesh, {.23, .29, -1.105}, .095)
    cowling_band := [2]Mesh_Ring{{-2.74, .736, .12, .626}, {-2.68, .718, .12, .638}}
    add_ring_mesh(mesh, cowling_band[:], 16, .Marking)
    // A dark recessed engine bay gives the cowl a readable opening at gameplay
    // distance. Nine broad, radial cylinder heads replace the former ring of
    // dots; their compressed vertical spacing follows the elliptical cowl.
    engine_face_center := [3]f32{0, .10, -3.305}
    add_ellipse_disc_z(mesh, engine_face_center, .355, .245, .Dark_Metal)
    for cylinder_index in 0 ..< 9 {
        angle := math.PI * .5 + f32(cylinder_index) * 2 * math.PI / 9
        inner_radius := f32(.145)
        outer_radius := f32(.305)
        inner := [3]f32{math.cos(angle) * inner_radius, .10 + math.sin(angle) * inner_radius * .70, -3.322}
        outer := [3]f32{math.cos(angle) * outer_radius, .10 + math.sin(angle) * outer_radius * .70, -3.322}
        add_strut(mesh, inner, outer, .082, .Steel)
    }
    // The thick forward lip hides the cylinder ends and makes the cowling feel
    // like a formed metal shell instead of a colored decal on the nose.
    add_ellipse_annulus_z(mesh, {0, .10, -3.338}, .455, .335, .345, .245, .Engine)
    for exhaust_index in 0 ..< 3 {
        z := -2.82 + f32(exhaust_index) * .24
        add_strut(mesh, {-.55, -.08, z}, {-.72, -.12, z + .04}, .075, .Dark_Metal)
    }
    chin_intake := [5]Mesh_Profile_Point{{-3.05, -.32}, {-2.88, -.53}, {-2.56, -.48}, {-2.43, -.30}, {-2.72, -.25}}
    add_profile_prism(mesh, chin_intake[:], .20, .Dark_Metal)

    screen_low_y := f32(.45)
    screen_high_y := f32(1.03)
    screen_low_z := f32(-1.18)
    screen_high_z := f32(-1.02)
    mesh_quad(
        mesh,
        {-.47, screen_low_y, screen_low_z},
        {-.20, screen_high_y, screen_high_z},
        {0, screen_high_y + .05, screen_high_z},
        {0, screen_low_y, screen_low_z},
        .Glass,
    )
    mesh_quad(
        mesh,
        {0, screen_low_y, screen_low_z},
        {0, screen_high_y + .05, screen_high_z},
        {.20, screen_high_y, screen_high_z},
        {.47, screen_low_y, screen_low_z},
        .Glass,
    )
    mesh_quad(
        mesh,
        {0, screen_low_y, screen_low_z},
        {0, screen_high_y + .05, screen_high_z},
        {-.20, screen_high_y, screen_high_z},
        {-.47, screen_low_y, screen_low_z},
        .Glass,
    )
    mesh_quad(
        mesh,
        {.47, screen_low_y, screen_low_z},
        {.20, screen_high_y, screen_high_z},
        {0, screen_high_y + .05, screen_high_z},
        {0, screen_low_y, screen_low_z},
        .Glass,
    )
    add_strut(mesh, {-.49, screen_low_y, screen_low_z}, {-.20, screen_high_y, screen_high_z}, .035, .Frame)
    add_strut(mesh, {-.20, screen_high_y, screen_high_z}, {0, screen_high_y + .05, screen_high_z}, .035, .Frame)
    add_strut(mesh, {0, screen_high_y + .05, screen_high_z}, {.20, screen_high_y, screen_high_z}, .035, .Frame)
    add_strut(mesh, {.20, screen_high_y, screen_high_z}, {.49, screen_low_y, screen_low_z}, .035, .Frame)
    add_strut(mesh, {-.49, screen_low_y, screen_low_z}, {.49, screen_low_y, screen_low_z}, .04, .Frame)
}

postale_mesh :: proc() -> Aircraft_Mesh {
    mesh: Aircraft_Mesh
    wing := [9]Mesh_Section {
        {-4.96, -.48, -.39, .025},
        {-4.86, -.82, -.10, .045},
        {-4.55, -1.12, .14, .07},
        {-2.05, -1.42, .39, .12},
        {0, -1.48, .43, .15},
        {2.05, -1.42, .39, .12},
        {4.55, -1.12, .14, .07},
        {4.86, -.82, -.10, .045},
        {4.96, -.48, -.39, .025},
    }
    tail := [7]Mesh_Section {
        {-2.20, 2.68, 2.78, .025},
        {-2.05, 2.52, 2.95, .04},
        {-1.55, 2.38, 3.12, .055},
        {0, 2.22, 3.2, .085},
        {1.55, 2.38, 3.12, .055},
        {2.05, 2.52, 2.95, .04},
        {2.20, 2.68, 2.78, .025},
    }
    fin := [7]Mesh_Profile_Point {
        {2.05, .38},
        {2.24, .78},
        {2.46, 1.28},
        {2.72, 1.62},
        {2.94, 1.68},
        {3.12, 1.50},
        {3.18, .4},
    }
    add_postale_hull(&mesh)

    POSTALE_WING_Y :: f32(.08)
    wing_first := mesh.vertex_count
    add_section_mesh(&mesh, wing[:], POSTALE_WING_Y, .Wing)
    for index in wing_first ..< mesh.vertex_count {
        mesh.vertices[index].position[1] += abs(mesh.vertices[index].position[0]) * .045
    }
    left_root_fillet := [3]Mesh_Section{{-1.10, -1.05, .20, .04}, {-.76, -1.25, .28, .12}, {-.52, -.90, .10, .20}}
    right_root_fillet := [3]Mesh_Section{{.52, -.90, .10, .20}, {.76, -1.25, .28, .12}, {1.10, -1.05, .20, .04}}
    add_section_mesh(&mesh, left_root_fillet[:], .17, .Body)
    add_section_mesh(&mesh, right_root_fillet[:], .17, .Body)
    add_section_mesh(&mesh, tail[:], .55, .Tail)
    add_profile_prism(&mesh, fin[:], .065, .Tail)
    left_flap := [3]Mesh_Section{{-3.25, .08, .30, .045}, {-1.90, .10, .40, .05}, {-.72, .10, .42, .055}}
    right_flap := [3]Mesh_Section{{.72, .10, .42, .055}, {1.90, .10, .40, .05}, {3.25, .08, .30, .045}}
    left_aileron := [4]Mesh_Section {
        {-4.76, -.22, -.08, .028},
        {-4.48, -.02, .16, .035},
        {-3.85, .04, .25, .04},
        {-3.24, .08, .30, .043},
    }
    right_aileron := [4]Mesh_Section {
        {3.24, .08, .30, .043},
        {3.85, .04, .25, .04},
        {4.48, -.02, .16, .035},
        {4.76, -.22, -.08, .028},
    }
    control_first := mesh.vertex_count
    add_section_mesh(&mesh, left_flap[:], POSTALE_WING_Y, .Left_Flap)
    add_section_mesh(&mesh, right_flap[:], POSTALE_WING_Y, .Right_Flap)
    add_section_mesh(&mesh, left_aileron[:], POSTALE_WING_Y, .Left_Aileron)
    add_section_mesh(&mesh, right_aileron[:], POSTALE_WING_Y, .Right_Aileron)
    for index in control_first ..< mesh.vertex_count {
        mesh.vertices[index].position[1] += abs(mesh.vertices[index].position[0]) * .045
    }
    left_elevator := [3]Mesh_Section{{-2.05, 2.76, 2.94, .028}, {-1.55, 2.76, 3.10, .04}, {-.08, 2.78, 3.18, .055}}
    right_elevator := [3]Mesh_Section{{.08, 2.78, 3.18, .055}, {1.55, 2.76, 3.10, .04}, {2.05, 2.76, 2.94, .028}}
    add_section_mesh(&mesh, left_elevator[:], .56, .Elevator)
    add_section_mesh(&mesh, right_elevator[:], .56, .Elevator)
    rudder := [6]Mesh_Profile_Point{{2.78, .48}, {2.76, 1.12}, {2.84, 1.54}, {2.96, 1.64}, {3.12, 1.47}, {3.18, .50}}
    add_profile_prism(&mesh, rudder[:], .074, .Rudder)
    // Compact, wide-track taildragger gear. Each axle is triangulated back to
    // two lower-fuselage hardpoints, so the undercarriage reads as a sprung
    // V-frame rather than a pair of posts hanging from the wing.
    left_axle := [3]f32{-1.34, -1.13, -.48}
    right_axle := [3]f32{1.34, -1.13, -.48}
    add_wheel(&mesh, left_axle, .45, .22)
    add_wheel(&mesh, right_axle, .45, .22)
    add_wheel(&mesh, {0, -.91, 2.96}, .24, .18)
    // Simple oval covers sit just outside each tire face. Keeping them thin
    // avoids the intersecting teardrop shell that left a black center notch.
    wheel_cover := [2]Mesh_Ring{{-.018, .34, 0, .42}, {.018, .34, 0, .42}}
    wheel_cover_centers := [2][3]f32 {
        {left_axle[0] - .13, left_axle[1], left_axle[2]},
        {right_axle[0] + .13, right_axle[1], right_axle[2]},
    }
    for center in wheel_cover_centers {
        first := mesh.vertex_count
        add_ring_mesh(&mesh, wheel_cover[:], 12, .Marking)
        rotate_new_vertices_y(&mesh, first, {0, 0, 0}, math.PI * .5)
        translate_new_vertices(&mesh, first, center)
    }
    add_strut(&mesh, left_axle, {-.42, -.39, -.82}, .13, .Frame)
    add_strut(&mesh, left_axle, {-.46, -.36, .02}, .13, .Frame)
    add_strut(&mesh, right_axle, {.42, -.39, -.82}, .13, .Frame)
    add_strut(&mesh, right_axle, {.46, -.36, .02}, .13, .Frame)
    add_strut(&mesh, left_axle, right_axle, .09, .Frame)
    add_strut(&mesh, {0, -.91, 2.96}, {0, -.05, 2.52}, .09, .Frame)
    add_postale_propeller(&mesh, {0, .12, -3.42})
    add_propeller_spin_volume(&mesh, {0, .12, -3.42}, 1.46, .018)
    mesh_finalize(
        &mesh,
        &postale_mesh_cache,
        postale_uvs[:],
        postale_sources[:],
        postale_indices[:],
        postale_scratch[:],
    )
    return mesh
}

pelican_hull_point :: proc(ring: Mesh_Ring, side, sides: int) -> [3]f32 {
    angle := f32(side) * 2 * math.PI / f32(sides); lateral := math.cos(angle); vertical := math.sin(angle)
    lower := vertical < 0; shaped := vertical
    if lower do shaped = -f32(math.pow(f64(-vertical), 1.55))
    factor := f32(1); if lower do factor = .52 + .48 * abs(lateral)
    x := lateral * ring.width * factor; y := ring.center_y + shaped * ring.height
    if lower do y = ring.center_y + shaped * ring.height * 1.12
    bow := clamp((-4.1 - ring.z) / 1.42, 0, 1)
    return {x, y, ring.z - bow * vertical * .24}
}

add_pelican_hull :: proc(mesh: ^Aircraft_Mesh, rings: []Mesh_Ring, sides: int, part: Aircraft_Mesh_Part) {
    for r in 0 ..< len(rings) -
        1 { for s in 0 ..< sides { n := (s + 1) % sides; mesh_quad(mesh, pelican_hull_point(rings[r], s, sides), pelican_hull_point(rings[r], n, sides), pelican_hull_point(rings[r + 1], n, sides), pelican_hull_point(rings[r + 1], s, sides), part) } }
}

pelican_mesh :: proc() -> Aircraft_Mesh {
    mesh: Aircraft_Mesh
    hull := [16]Mesh_Ring {
        {-5.62, .18, .55, .4},
        {-5.43, .38, .4, .62},
        {-5.12, .67, .2, .9},
        {-4.68, .98, .06, 1.16},
        {-4.08, 1.28, -.03, 1.34},
        {-3.28, 1.48, -.1, 1.46},
        {-2.15, 1.58, -.13, 1.5},
        {-.25, 1.58, -.12, 1.42},
        {.72, 1.5, -.02, 1.18},
        {.9, 1.46, .09, 1.07},
        {1.12, 1.38, .14, 1},
        {2.35, 1.24, .27, .86},
        {3.65, 1.02, .43, .7},
        {4.72, .7, .66, .53},
        {5.55, .34, .93, .3},
        {6.08, .1, 1.18, .1},
    }
    cabin := [5]Mesh_Ring {
        {-4.62, .72, .91, .3},
        {-4.23, 1.04, 1.04, .52},
        {-3.55, 1.18, 1.08, .64},
        {-2.68, 1.1, .95, .56},
        {-2.18, .7, .78, .27},
    }
    wing := [9]Mesh_Section {
        {-8.65, -.92, -.18, .045},
        {-7.55, -1.18, .02, .065},
        {-5.7, -1.5, .26, .085},
        {-3.65, -1.88, .58, .12},
        {0, -2.18, .86, .155},
        {3.65, -1.88, .58, .12},
        {5.7, -1.5, .26, .085},
        {7.55, -1.18, .02, .065},
        {8.65, -.92, -.18, .045},
    }
    tail := [5]Mesh_Section {
        {-3.7, 4.92, 5.66, .045},
        {-2.55, 4.68, 5.98, .065},
        {0, 4.4, 6.2, .09},
        {2.55, 4.68, 5.98, .065},
        {3.7, 4.92, 5.66, .045},
    }
    fin := [5]Mesh_Profile_Point{{4.6, 1.15}, {4.9, 3.7}, {5.45, 4.4}, {5.92, 4.2}, {6.08, 1.12}}
    add_pelican_hull(&mesh, hull[:], 12, .Body); add_ring_mesh(&mesh, cabin[:], 8, .Body)
    add_section_mesh(
        &mesh,
        wing[:],
        2.3,
        .Wing,
    ); add_section_mesh(&mesh, tail[:], 1.28, .Tail); add_profile_prism(&mesh, fin[:], .12, .Tail)
    engine_xs := [2]f32{-3.45, 3.45}
    for x in engine_xs {
        nacelle := [6]Mesh_Ring {
            {.4, .1, 2.13, .1},
            {-.07, .3, 2.13, .3},
            {-.67, .55, 2.13, .55},
            {-1.3, .7, 2.13, .7},
            {-1.83, .77, 2.13, .77},
            {-2.17, .74, 2.13, .74},
        }
        add_ring_mesh_at_x(&mesh, nacelle[:], 14, x, .Engine)
        propeller_part := Aircraft_Mesh_Part.Left_Propeller; if x > 0 do propeller_part = .Right_Propeller
        add_propeller(&mesh, {x, 2.13, -2.75}, 1.69, .17, .11, propeller_part)
    }
    add_box(
        &mesh,
        {-2.475, 2.3, .36},
        {1.55, .12, .72},
        .Left_Flap,
    ); add_box(&mesh, {2.475, 2.3, .36}, {1.55, .12, .72}, .Right_Flap)
    add_box(
        &mesh,
        {-5.55, 2.3, .33},
        {2.25, .055, .42},
        .Left_Aileron,
    ); add_box(&mesh, {5.55, 2.3, .33}, {2.25, .055, .42}, .Right_Aileron)
    add_box(
        &mesh,
        {0, 1.28, 5.96},
        {6.25, .055, .48},
        .Elevator,
    ); add_box(&mesh, {0, 2.28, 5.95}, {.055, 2.05, .5}, .Rudder)
    float_xs := [2]f32{-5.55, 5.55}
    for x in float_xs {
        floats := [4]Mesh_Ring {
            {-1.55, .04, -.55, .04},
            {-1.25, .32, -.58, .24},
            {.3, .38, -.62, .28},
            {.72, .18, -.58, .16},
        }
        add_ring_mesh_at_x(&mesh, floats[:], 8, x, .Float)
    }
    mesh_finalize(
        &mesh,
        &pelican_mesh_cache,
        pelican_uvs[:],
        pelican_sources[:],
        pelican_indices[:],
        pelican_scratch[:],
    )
    return mesh
}
