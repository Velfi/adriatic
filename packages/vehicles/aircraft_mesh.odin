package vehicles

import "core:math"

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
    Left_Propeller,
    Right_Propeller,
    Left_Rotor,
    Right_Rotor,
    Rear_Rotor,
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
}

Mesh_Vertex :: struct {
    position: [3]f32,
    part:     Aircraft_Mesh_Part,
}

Mesh_Triangle :: struct {
    a, b, c: u16,
}

AIRCRAFT_MESH_VERTEX_CAPACITY :: 4096
AIRCRAFT_MESH_TRIANGLE_CAPACITY :: 2048

Aircraft_Mesh :: struct {
    vertices:       [AIRCRAFT_MESH_VERTEX_CAPACITY]Mesh_Vertex,
    triangles:      [AIRCRAFT_MESH_TRIANGLE_CAPACITY]Mesh_Triangle,
    vertex_count:   int,
    triangle_count: int,
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

mesh_vertices :: proc(mesh: ^Aircraft_Mesh) -> []Mesh_Vertex {
    if mesh == nil do return nil
    return mesh.vertices[:mesh.vertex_count]
}

mesh_triangles :: proc(mesh: ^Aircraft_Mesh) -> []Mesh_Triangle {
    if mesh == nil do return nil
    return mesh.triangles[:mesh.triangle_count]
}

mesh_triangle :: proc(mesh: ^Aircraft_Mesh, a, b, c: [3]f32, part: Aircraft_Mesh_Part) {
    if mesh == nil ||
       mesh.vertex_count + 3 > AIRCRAFT_MESH_VERTEX_CAPACITY ||
       mesh.triangle_count >= AIRCRAFT_MESH_TRIANGLE_CAPACITY {
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

mesh_quad :: proc(mesh: ^Aircraft_Mesh, a, b, c, d: [3]f32, part: Aircraft_Mesh_Part) {
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
                ring_point(rings[ring_index], next, sides),
                ring_point(rings[ring_index + 1], next, sides),
                ring_point(rings[ring_index + 1], side, sides),
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
        mesh_quad(mesh, p0, q0, q1, p1, part); mesh_quad(mesh, p3, p2, q2, q3, part)
        mesh_quad(mesh, p1, q1, q2, p2, part); mesh_quad(mesh, p0, p3, q3, q0, part)
        if index == 0 do mesh_quad(mesh, p0, p1, p2, p3, part)
        if index == len(sections) - 2 do mesh_quad(mesh, q0, q3, q2, q1, part)
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

add_box :: proc(mesh: ^Aircraft_Mesh, center, size: [3]f32, part: Aircraft_Mesh_Part) {
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

rotate_new_vertices_z :: proc(mesh: ^Aircraft_Mesh, first: int, pivot: [3]f32, angle: f32) {
    c := math.cos(angle); s := math.sin(angle)
    for index in first ..< mesh.vertex_count {
        x := mesh.vertices[index].position[0] - pivot[0]; y := mesh.vertices[index].position[1] - pivot[1]
        mesh.vertices[index].position[0] = pivot[0] + x * c - y * s
        mesh.vertices[index].position[1] = pivot[1] + x * s + y * c
    }
}

rotate_new_vertices_y :: proc(mesh: ^Aircraft_Mesh, first: int, pivot: [3]f32, angle: f32) {
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
    add_ring_mesh(mesh, hub[:], 10, .Engine)
    rotate_new_vertices_y(mesh, first, {0, 0, 0}, math.PI * .5)
    for index in first ..< mesh.vertex_count {
        mesh.vertices[index].position += center
    }

    for tread in 0 ..< 12 {
        angle := f32(tread) * 2 * math.PI / 12
        add_box(
            mesh,
            {center[0], center[1] + math.cos(angle) * radius * .91, center[2] + math.sin(angle) * radius * .91},
            {thickness * 1.12, radius * .12, radius * .18},
            .Wheel,
        )
    }
}

postale_mesh :: proc() -> Aircraft_Mesh {
    mesh: Aircraft_Mesh
    fuselage := [8]Mesh_Ring {
        {-3.12, .3, .12, .35},
        {-2.78, .58, .12, .58},
        {-2.15, .66, .14, .83},
        {-.65, .68, .1, .87},
        {.55, .62, .12, .72},
        {1.65, .45, .18, .5},
        {2.55, .25, .28, .28},
        {3.12, .07, .35, .08},
    }
    cowling := [4]Mesh_Ring {
        {-3.22, .51, .12, .51},
        {-3.08, .62, .12, .62},
        {-2.73, .68, .12, .67},
        {-2.48, .63, .12, .64},
    }
    wing := [7]Mesh_Section {
        {-5.65, -1.15, .64, .035},
        {-4.9, -1.32, .58, .06},
        {-2.25, -1.55, .48, .1},
        {0, -1.62, .44, .14},
        {2.25, -1.55, .48, .1},
        {4.9, -1.32, .58, .06},
        {5.65, -1.15, .64, .035},
    }
    tail := [5]Mesh_Section {
        {-2.18, 2.46, 3.08, .035},
        {-1.55, 2.35, 3.14, .055},
        {0, 2.22, 3.2, .085},
        {1.55, 2.35, 3.14, .055},
        {2.18, 2.46, 3.08, .035},
    }
    fin := [5]Mesh_Profile_Point{{2.28, .38}, {2.5, 1.85}, {2.87, 2.45}, {3.16, 2.3}, {3.18, .4}}
    add_ring_mesh(&mesh, fuselage[:], 10, .Body); add_ring_mesh(&mesh, cowling[:], 14, .Engine)
    add_section_mesh(&mesh, wing[:], 1.05, .Wing); add_section_mesh(&mesh, tail[:], .55, .Tail)
    add_profile_prism(&mesh, fin[:], .065, .Tail)
    add_box(
        &mesh,
        {-2.35, .99, .48},
        {2.75, .085, .47},
        .Left_Flap,
    ); add_box(&mesh, {2.35, .99, .48}, {2.75, .085, .47}, .Right_Flap)
    add_box(
        &mesh,
        {-4.55, 1.035, .5},
        {1.75, .065, .34},
        .Left_Aileron,
    ); add_box(&mesh, {4.55, 1.035, .5}, {1.75, .065, .34}, .Right_Aileron)
    add_box(
        &mesh,
        {-1.12, .56, 3.05},
        {1.72, .055, .24},
        .Elevator,
    ); add_box(&mesh, {1.12, .56, 3.05}, {1.72, .055, .24}, .Elevator)
    rudder := [5]Mesh_Profile_Point{{2.96, .48}, {2.94, 1.72}, {3.02, 2.22}, {3.16, 2.3}, {3.18, .5}}
    add_profile_prism(&mesh, rudder[:], .073, .Rudder)
    // Positions and radii match AmbientMailPlane.cs: two main gravel wheels
    // under the wing and a smaller tail wheel under the rear fuselage.
    add_wheel(&mesh, {-1.45, -1.18, -.48}, .47, .24)
    add_wheel(&mesh, {1.45, -1.18, -.48}, .47, .24)
    add_wheel(&mesh, {0, -.91, 2.96}, .24, .18)
    // Main struts run from the lower wing skin (about y=.9) to each axle;
    // keeping the full span here prevents the tires from appearing detached.
    add_box(&mesh, {-1.45, -.14, -.48}, {.13, 2.08, .13}, .Frame)
    add_box(&mesh, {1.45, -.14, -.48}, {.13, 2.08, .13}, .Frame)
    // The tail strut reaches up into the rear fuselage instead of stopping
    // halfway between the tail wheel and the airframe.
    add_box(&mesh, {0, -.28, 2.72}, {.11, 1.26, .11}, .Frame)
    add_propeller(&mesh, {0, .12, -3.42}, 1.58, .2, .08, .Propeller)
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
    return mesh
}

libellula_mesh :: proc() -> Aircraft_Mesh {
    mesh: Aircraft_Mesh
    // The hero mesh's structural plan: triangular rotor frame over a suspended
    // carriage. Boxes retain the authored dimensions while rotor blades use the
    // exact tapered-prism construction from TriRotorVisual.
    segments := [3][2][3]f32 {
        {{-3.65, 1.2, -.75}, {3.65, 1.2, -.75}},
        {{3.65, 1.2, -.75}, {0, 1.2, 3.05}},
        {{0, 1.2, 3.05}, {-3.65, 1.2, -.75}},
    }
    for segment in segments {
        add_horizontal_beam(&mesh, segment[0], segment[1], .16, .Frame)
    }
    // Lower spaceframe chord and Warren-style web, matching the source visual's
    // separated lift frame instead of leaving the rotor triangle as a flat plate.
    lower := [3][3]f32{{-3.05, .55, -.75}, {3.05, .55, -.75}, {0, .55, 2.72}}
    for index in 0 ..< 3 {
        next := (index + 1) % 3
        add_horizontal_beam(&mesh, lower[index], lower[next], .11, .Frame)
        add_horizontal_beam(&mesh, segments[index][0], lower[next], .075, .Frame)
        add_horizontal_beam(&mesh, segments[index][0], lower[index], .075, .Frame)
    }
    add_box(&mesh, {0, -.55, .55}, {1.65, 1.15, 3.35}, .Carriage)
    // Pressure-carriage roof, cockpit glazing, service spine and rear bumper.
    add_box(&mesh, {0, .16, .18}, {1.25, .12, 3.2}, .Carriage)
    add_box(&mesh, {0, .02, -1.35}, {1.42, .52, .12}, .Glass)
    add_box(&mesh, {0, -.10, -1.52}, {1.18, .14, .08}, .Frame)
    add_box(&mesh, {0, .28, .18}, {.55, .22, .42}, .Engine)
    add_box(&mesh, {0, -.98, 2.20}, {1.3, .08, .30}, .Frame)
    add_box(&mesh, {0, -.70, 2.34}, {.34, .07, .05}, .Frame)
    // Suspension straps and kingpost are intentionally non-collinear so the
    // carriage reads as hanging from the lift frame in side and rear views.
    strap_x := [2]f32{-.72, .72}
    for x in strap_x {
        add_box(&mesh, {x, .05, .30}, {.055, .72, .06}, .Frame)
        add_box(&mesh, {x, -.18, 1.15}, {.055, .48, .06}, .Frame)
    }
    add_box(&mesh, {0, .43, 1.55}, {.16, .68, .16}, .Frame)
    add_box(&mesh, {0, .08, .18}, {.24, .12, .24}, .Engine)
    // Four splayed landing legs, two longitudinal skids, and cross-braces.
    leg_x := [2]f32{-1.02, 1.02}
    for x in leg_x {
        add_box(&mesh, {x, -1.18, -.78}, {.13, .95, .13}, .Wheel)
        add_box(&mesh, {x, -1.18, 1.55}, {.13, .95, .13}, .Wheel)
        add_box(&mesh, {x, -1.56, .15}, {.18, .10, 3.65}, .Wheel)
    }
    add_horizontal_beam(&mesh, {-1.02, -1.46, -.92}, {1.02, -1.46, .95}, .06, .Wheel)
    add_horizontal_beam(&mesh, {1.02, -1.46, -.92}, {-1.02, -1.46, .95}, .06, .Wheel)
    // Nacelle housings, cooling bands, exhaust blocks, and mast collars.
    rotors := [3][3]f32{{-3.65, 1.58, -.75}, {3.65, 1.58, -.75}, {0, 1.58, 3.05}}
    rotor_parts := [3]Aircraft_Mesh_Part{.Left_Rotor, .Right_Rotor, .Rear_Rotor}
    for rotor, rotor_index in rotors {
        nacelle := [2]Mesh_Ring{{rotor[2] - .29, .5, rotor[1], .5}, {rotor[2] + .29, .42, rotor[1], .42}}
        add_ring_mesh_at_x(&mesh, nacelle[:], 16, rotor[0], .Engine)
        add_box(&mesh, {rotor[0], rotor[1] - .28, rotor[2]}, {.75, .16, .58}, .Engine)
        add_box(&mesh, {rotor[0], rotor[1] + .34, rotor[2]}, {.32, .12, .32}, .Frame)
        add_box(&mesh, {rotor[0], rotor[1] - .42, rotor[2]}, {.16, .10, .24}, .Carriage)
        for blade in 0 ..< 3 {
            angle := f32(blade) * 2 * math.PI / 3; c := math.cos(angle); s := math.sin(angle)
            root_left := [3]f32 {
                -.155,
                .039,
                -.52,
            }; root_right := [3]f32{.155, .039, -.52}; tip_right := [3]f32{.165, .023, -2.3}; tip_left := [3]f32{.015, .023, -2.3}
            top := [4][3]f32{root_left, root_right, tip_right, tip_left}
            bottom := top
            for &p in bottom { p[1] = -p[1] }
            for &p in top {x := p[0]; z := p[2]; p[0] = rotor[0] + x * c - z * s
                p[1] += rotor[1] + .38
                p[2] = rotor[2] + x * s + z * c}
            for &p in bottom {x := p[0]; z := p[2]; p[0] = rotor[0] + x * c - z * s
                p[1] += rotor[1] + .38
                p[2] = rotor[2] + x * s + z * c}
            part := rotor_parts[rotor_index]
            mesh_quad(
                &mesh,
                top[0],
                top[1],
                top[2],
                top[3],
                part,
            ); mesh_quad(&mesh, bottom[3], bottom[2], bottom[1], bottom[0], part)
            mesh_quad(
                &mesh,
                top[0],
                bottom[0],
                bottom[1],
                top[1],
                part,
            ); mesh_quad(&mesh, top[1], bottom[1], bottom[2], top[2], part)
            mesh_quad(
                &mesh,
                top[2],
                bottom[2],
                bottom[3],
                top[3],
                part,
            ); mesh_quad(&mesh, top[3], bottom[3], bottom[0], top[0], part)
        }
    }
    return mesh
}
