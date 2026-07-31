package vehicles

import "core:testing"

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
