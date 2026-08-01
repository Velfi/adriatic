package vehicles

import "core:testing"

aircraft_mesh_uv_assignment_is_complete :: proc(t: ^testing.T, mesh: ^$Mesh) {
    testing.expect(t, mesh != nil && mesh.vertex_count > 0 && mesh.triangle_count > 0)
    if mesh == nil do return

    for triangle in mesh.triangles[:mesh.triangle_count] {
        a := mesh.vertices[triangle.a]
        b := mesh.vertices[triangle.b]
        c := mesh.vertices[triangle.c]
        testing.expect(t, a.part == b.part && a.part == c.part)
        corners := [3]Mesh_Vertex{a, b, c}
        for vertex in corners {
            testing.expect(t, vertex.uv[0] >= 0 && vertex.uv[0] <= 1)
            testing.expect(t, vertex.uv[1] >= 0 && vertex.uv[1] <= 1)
        }
        uv_area := abs(
            (b.uv[0] - a.uv[0]) * (c.uv[1] - a.uv[1]) -
            (b.uv[1] - a.uv[1]) * (c.uv[0] - a.uv[0]),
        )
        testing.expect(t, uv_area > 0)
    }
}

@(test)
player_aircraft_preserve_every_atlas_triangle_assignment :: proc(t: ^testing.T) {
    postale := postale_mesh()
    defer free(postale)
    aircraft_mesh_uv_assignment_is_complete(t, postale)

    libellula: Libellula_Mesh
    libellula_mesh_init(&libellula)
    defer libellula_mesh_destroy(&libellula)
    libellula_mesh_build(&libellula)
    aircraft_mesh_uv_assignment_is_complete(t, &libellula)

    mk2: Libellula_Mesh
    libellula_mesh_init(&mk2)
    defer libellula_mesh_destroy(&mk2)
    libellula_mk2_mesh_build(&mk2)
    aircraft_mesh_uv_assignment_is_complete(t, &mk2)
}

@(test)
postale_wing_stops_at_flap_hinges :: proc(t: ^testing.T) {
    mesh := postale_mesh()
    defer free(mesh)

    wing_vertices_in_flap_bays := 0
    for vertex in mesh.vertices[:mesh.vertex_count] {
        if vertex.part != .Wing do continue
        span := abs(vertex.position[0])
        if span <= .72 || span >= 3.25 do continue
        wing_vertices_in_flap_bays += 1
        testing.expect(t, vertex.position[2] <= .101)
    }
    testing.expect(t, wing_vertices_in_flap_bays > 0)
}
