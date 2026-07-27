package tests

import vehicles "../packages/vehicles"
import "core:math/linalg"
import "core:testing"

valid_edges :: proc(t: ^testing.T, model: vehicles.Aircraft_Wireframe) {
    for edge in model.edges {
        testing.expect(t, edge.a >= 0 && edge.a < len(model.vertices))
        testing.expect(t, edge.b >= 0 && edge.b < len(model.vertices))
    }
}

@(test)
aircraft_wireframes_express_airframe_roles :: proc(t: ^testing.T) {
    postale := vehicles.postale_wireframe(
        
    ); pelican := vehicles.pelican_wireframe(); libellula := vehicles.libellula_wireframe()
    valid_edges(t, postale); valid_edges(t, pelican); valid_edges(t, libellula)
    // The Postale's high wing, Pelican's twin engines/pontoons, and Libellula's
    // triangular rotor plan are intentionally inspectable from their wireframes.
    testing.expect(t, postale.vertices[8].position[1] > postale.vertices[4].position[1])
    testing.expect(t, pelican.vertices[16].position[0] < -3 && pelican.vertices[18].position[0] > 3)
    testing.expect(
        t,
        libellula.vertices[0].position[0] < 0 &&
        libellula.vertices[1].position[0] > 0 &&
        libellula.vertices[2].position[2] > 4,
    )
}

@(test)
aircraft_wireframes_animate_flaps_and_propellers :: proc(t: ^testing.T) {
    postale := vehicles.postale_wireframe(); vehicles.animate_postale(&postale, 1, .25)
    testing.expect(t, postale.vertices[10].position[1] < .4 && postale.vertices[10].position[2] > .9)
    testing.expect(t, postale.vertices[19].position[1] < -.2)
    pelican := vehicles.pelican_wireframe(); vehicles.animate_pelican(&pelican, 1, .125)
    testing.expect(t, pelican.vertices[10].position[1] < .6 && pelican.vertices[12].position[1] < .2)
    libellula := vehicles.libellula_wireframe(); vehicles.animate_libellula(&libellula, .25)
    testing.expect(t, libellula.vertices[3].position[2] < -2 && libellula.vertices[5].position[2] > -.5)
}

valid_triangle_mesh :: proc(t: ^testing.T, mesh: ^$Mesh) {
    testing.expect(t, mesh.vertex_count > 0)
    testing.expect(t, mesh.triangle_count > 0)
    testing.expect(t, mesh.vertex_count < mesh.triangle_count * 3)
    testing.expect(t, mesh.vertex_count < len(mesh.vertices))
    testing.expect(t, mesh.triangle_count < len(mesh.triangles))
    for triangle in vehicles.mesh_triangles(mesh) {
        testing.expect(t, int(triangle.a) < mesh.vertex_count)
        testing.expect(t, int(triangle.b) < mesh.vertex_count)
        testing.expect(t, int(triangle.c) < mesh.vertex_count)
    }
    uv_area := f32(0)
    for triangle in vehicles.mesh_triangles(mesh) {
        a := mesh.vertices[triangle.a].uv
        b := mesh.vertices[triangle.b].uv
        c := mesh.vertices[triangle.c].uv
        testing.expect(t, a[0] >= 0 && a[0] <= 1 && a[1] >= 0 && a[1] <= 1)
        uv_area += abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
    }
    testing.expect(t, uv_area > .01)
}

triangle_normal :: proc(a, b, c: [3]f32) -> [3]f32 {
    ab := b - a
    ac := c - a
    return linalg.cross(ab, ac)
}

@(test)
ring_mesh_winds_sides_and_caps_outward :: proc(t: ^testing.T) {
    mesh: vehicles.Aircraft_Mesh
    rings := [2]vehicles.Mesh_Ring{{-1, 1, 0, 1}, {1, 1, 0, 1}}
    sides := 12
    vehicles.add_ring_mesh(&mesh, rings[:], sides, .Engine)

    // Side normals must point away from the ring axis. This is the shared
    // construction used by the Postale cowling, tires, and wheel hubs.
    for triangle_index in 0 ..< sides * 2 {
        triangle := mesh.triangles[triangle_index]
        a := mesh.vertices[triangle.a].position
        b := mesh.vertices[triangle.b].position
        c := mesh.vertices[triangle.c].position
        normal := triangle_normal(a, b, c)
        center := (a + b + c) / 3
        testing.expect(t, normal[0] * center[0] + normal[1] * center[1] > 0)
    }

    for side in 0 ..< sides {
        front_triangle := mesh.triangles[sides * 2 + side * 2]
        front_normal := triangle_normal(
            mesh.vertices[front_triangle.a].position,
            mesh.vertices[front_triangle.b].position,
            mesh.vertices[front_triangle.c].position,
        )
        testing.expect(t, front_normal[2] < 0)

        rear_triangle := mesh.triangles[sides * 2 + side * 2 + 1]
        rear_normal := triangle_normal(
            mesh.vertices[rear_triangle.a].position,
            mesh.vertices[rear_triangle.b].position,
            mesh.vertices[rear_triangle.c].position,
        )
        testing.expect(t, rear_normal[2] > 0)
    }
}

@(test)
section_mesh_winds_sides_and_caps_outward :: proc(t: ^testing.T) {
    mesh: vehicles.Aircraft_Mesh
    sections := [2]vehicles.Mesh_Section{{-1, -1, 1, .1}, {1, -1, 1, .1}}
    vehicles.add_section_mesh(&mesh, sections[:], 0, .Wing)

    expected_axes := [12][2]int {
        {1, -1},
        {1, -1},
        {1, 1},
        {1, 1},
        {2, 1},
        {2, 1},
        {2, -1},
        {2, -1},
        {0, -1},
        {0, -1},
        {0, 1},
        {0, 1},
    }
    testing.expect(t, mesh.triangle_count == len(expected_axes))
    for triangle_index in 0 ..< mesh.triangle_count {
        triangle := mesh.triangles[triangle_index]
        normal := triangle_normal(
            mesh.vertices[triangle.a].position,
            mesh.vertices[triangle.b].position,
            mesh.vertices[triangle.c].position,
        )
        expected := expected_axes[triangle_index]
        testing.expect(t, normal[expected[0]] * f32(expected[1]) > 0)
    }
}

@(test)
procedural_player_aircraft_build_closed_triangle_surfaces :: proc(t: ^testing.T) {
    postale := vehicles.postale_mesh()
    valid_triangle_mesh(t, &postale)
    testing.expect(t, postale.triangle_count > 300)

    pelican := vehicles.pelican_mesh()
    valid_triangle_mesh(t, &pelican)
    testing.expect(t, pelican.triangle_count > 300)

    libellula := vehicles.libellula_mesh()
    defer vehicles.libellula_mesh_destroy(&libellula)
    valid_triangle_mesh(t, &libellula)
    testing.expect(t, libellula.triangle_count > 18_000)
}

first_mesh_part_position :: proc(mesh: ^$Mesh, part: vehicles.Aircraft_Mesh_Part) -> [3]f32 {
    for vertex in vehicles.mesh_vertices(mesh) {
        if vertex.part == part do return vertex.position
    }
    return {}
}

furthest_mesh_part_position :: proc(mesh: ^$Mesh, part: vehicles.Aircraft_Mesh_Part, pivot: [3]f32) -> [3]f32 {
    result: [3]f32
    greatest_radius_squared := f32(-1)
    for vertex in vehicles.mesh_vertices(mesh) {
        if vertex.part != part do continue
        dx := vertex.position[0] - pivot[0]
        dz := vertex.position[2] - pivot[2]
        radius_squared := dx * dx + dz * dz
        if radius_squared > greatest_radius_squared {
            greatest_radius_squared = radius_squared
            result = vertex.position
        }
    }
    return result
}

@(test)
procedural_player_aircraft_meshes_pose_props_and_control_surfaces :: proc(t: ^testing.T) {
    postale := vehicles.postale_mesh()
    postale_flap := first_mesh_part_position(&postale, .Left_Flap)
    postale_aileron := first_mesh_part_position(&postale, .Left_Aileron)
    postale_elevator := first_mesh_part_position(&postale, .Elevator)
    postale_rudder := first_mesh_part_position(&postale, .Rudder)
    postale_prop := first_mesh_part_position(&postale, .Propeller)
    vehicles.animate_postale_mesh(&postale, 1, 1, 1, 1, .25)
    testing.expect(t, first_mesh_part_position(&postale, .Left_Flap) != postale_flap)
    testing.expect(t, first_mesh_part_position(&postale, .Left_Aileron) != postale_aileron)
    testing.expect(t, first_mesh_part_position(&postale, .Elevator) != postale_elevator)
    testing.expect(t, first_mesh_part_position(&postale, .Rudder) != postale_rudder)
    testing.expect(t, first_mesh_part_position(&postale, .Propeller) != postale_prop)

    pelican := vehicles.pelican_mesh()
    left_prop := first_mesh_part_position(&pelican, .Left_Propeller)
    right_prop := first_mesh_part_position(&pelican, .Right_Propeller)
    elevator := first_mesh_part_position(&pelican, .Elevator)
    vehicles.animate_pelican_mesh(&pelican, .5, 1, 1, 1, .125, .125)
    testing.expect(t, first_mesh_part_position(&pelican, .Left_Propeller) != left_prop)
    testing.expect(t, first_mesh_part_position(&pelican, .Right_Propeller) != right_prop)
    testing.expect(t, first_mesh_part_position(&pelican, .Elevator) != elevator)

    libellula := vehicles.libellula_mesh()
    defer vehicles.libellula_mesh_destroy(&libellula)
    left_pivot := [3]f32{-3.2, 1.55, -1}
    right_pivot := [3]f32{3.2, 1.55, -1}
    left_rotor := furthest_mesh_part_position(&libellula, .Left_Rotor, left_pivot)
    right_rotor := furthest_mesh_part_position(&libellula, .Right_Rotor, right_pivot)
    vehicles.animate_libellula_mesh(&libellula, .25, .25, .25)
    testing.expect(t, furthest_mesh_part_position(&libellula, .Left_Rotor, left_pivot) != left_rotor)
    testing.expect(t, furthest_mesh_part_position(&libellula, .Right_Rotor, right_pivot) != right_rotor)
}

mesh_has_part :: proc(mesh: ^$Mesh, part: vehicles.Aircraft_Mesh_Part) -> bool {
    for vertex in vehicles.mesh_vertices(mesh) {
        if vertex.part == part do return true
    }
    return false
}

mesh_group_position :: proc(mesh: ^$Mesh, group: vehicles.Mesh_Animation_Group) -> [3]f32 {
    for vertex in vehicles.mesh_vertices(mesh) {
        if vertex.animation_group == group do return vertex.position
    }
    return {}
}

@(test)
full_libellula_mesh_contains_authored_material_and_suspension_assemblies :: proc(t: ^testing.T) {
    mesh := vehicles.libellula_mesh()
    defer vehicles.libellula_mesh_destroy(&mesh)
    parts := [9]vehicles.Aircraft_Mesh_Part {
        .Ivory,
        .Red_Paint,
        .Dark_Metal,
        .Steel,
        .Brass,
        .Strap,
        .Rotor_Blade,
        .Rotor_Tip,
        .Glass,
    }
    for part in parts do testing.expect(t, mesh_has_part(&mesh, part))
    groups := [7]vehicles.Mesh_Animation_Group {
        .Libellula_Carriage,
        .Libellula_Strap_Left,
        .Libellula_Strap_Right,
        .Libellula_Strap_Rear,
        .Libellula_Kingpost_Outer,
        .Libellula_Left_Rotor,
        .Libellula_Rear_Rotor,
    }
    for group in groups do testing.expect(t, mesh_group_position(&mesh, group) != [3]f32{})
}

@(test)
full_libellula_mesh_poses_suspended_carriage_and_load_paths :: proc(t: ^testing.T) {
    mesh := vehicles.libellula_mesh()
    defer vehicles.libellula_mesh_destroy(&mesh)
    carriage := mesh_group_position(&mesh, .Libellula_Carriage)
    strap := mesh_group_position(&mesh, .Libellula_Strap_Left)
    kingpost := mesh_group_position(&mesh, .Libellula_Kingpost_Inner)
    vehicles.animate_libellula_mesh_pose(&mesh, 0, 0, 0, .8, -.65, .12)
    testing.expect(t, mesh_group_position(&mesh, .Libellula_Carriage) != carriage)
    testing.expect(t, mesh_group_position(&mesh, .Libellula_Strap_Left) != strap)
    testing.expect(t, mesh_group_position(&mesh, .Libellula_Kingpost_Inner) != kingpost)
}

Mesh_Edge_Key :: struct {
    low, high: [3]i64,
}

Mesh_Edge_State :: struct {
    balance, count: int,
}

// Independently rotated shared vertices differ by a few floating-point ULPs.
MESH_EDGE_QUANTIZATION_SCALE :: f32(100_000)

quantized_position :: proc(value: [3]f32) -> [3]i64 {
    return {
        i64(value[0] * MESH_EDGE_QUANTIZATION_SCALE + (value[0] >= 0 ? .5 : -.5)),
        i64(value[1] * MESH_EDGE_QUANTIZATION_SCALE + (value[1] >= 0 ? .5 : -.5)),
        i64(value[2] * MESH_EDGE_QUANTIZATION_SCALE + (value[2] >= 0 ? .5 : -.5)),
    }
}

position_less :: proc(a, b: [3]i64) -> bool {
    if a[0] != b[0] do return a[0] < b[0]
    if a[1] != b[1] do return a[1] < b[1]
    return a[2] < b[2]
}

record_mesh_edge :: proc(edges: ^map[Mesh_Edge_Key]Mesh_Edge_State, a, b: [3]f32) {
    qa, qb := quantized_position(a), quantized_position(b)
    if qa == qb do return
    key := Mesh_Edge_Key {
        low  = qa,
        high = qb,
    }
    direction := 1
    if position_less(qb, qa) {
        key = {
            low  = qb,
            high = qa,
        }
        direction = -1
    }
    state := edges[key]
    state.balance += direction
    state.count += 1
    edges[key] = state
}

@(test)
full_libellula_mesh_is_non_degenerate_and_consistently_wound :: proc(t: ^testing.T) {
    mesh := vehicles.libellula_mesh()
    defer vehicles.libellula_mesh_destroy(&mesh)
    edges := make(map[Mesh_Edge_Key]Mesh_Edge_State)
    defer delete(edges)
    for triangle in vehicles.mesh_triangles(&mesh) {
        a := mesh.vertices[triangle.a].position
        b := mesh.vertices[triangle.b].position
        c := mesh.vertices[triangle.c].position
        ab := b - a
        ac := c - a
        normal := linalg.cross(ab, ac)
        testing.expect(t, linalg.dot(normal, normal) > 1e-12)
        if mesh.vertices[triangle.a].part == .Marking do continue
        record_mesh_edge(&edges, a, b)
        record_mesh_edge(&edges, b, c)
        record_mesh_edge(&edges, c, a)
    }
    for _, edge in edges {
        testing.expect(t, edge.balance == 0)
        testing.expect(t, edge.count % 2 == 0)
    }
}

@(test)
libellula_mesh_reuses_heap_storage_and_releases_it :: proc(t: ^testing.T) {
    mesh: vehicles.Libellula_Mesh
    vehicles.libellula_mesh_init(&mesh)
    vertex_storage := raw_data(mesh.vertices)
    triangle_storage := raw_data(mesh.triangles)
    vehicles.libellula_mesh_build(&mesh)
    first_triangle_count := mesh.triangle_count
    vehicles.libellula_mesh_build(&mesh)
    testing.expect(t, raw_data(mesh.vertices) == vertex_storage)
    testing.expect(t, raw_data(mesh.triangles) == triangle_storage)
    testing.expect(t, mesh.triangle_count == first_triangle_count)
    vehicles.libellula_mesh_destroy(&mesh)
    testing.expect(t, mesh.vertices == nil)
    testing.expect(t, mesh.triangles == nil)
}
