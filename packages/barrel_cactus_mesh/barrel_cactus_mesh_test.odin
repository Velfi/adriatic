package barrel_cactus_mesh

import "core:math"
import "core:math/linalg"
import "core:testing"

@(test)
generates_closed_ribbed_barrel :: proc(t: ^testing.T) {
    config := defaults()
    mesh := generate(config)
    defer destroy(&mesh)
    radial_segments := config.ribs * config.samples_per_rib
    testing.expect_value(t, len(mesh.vertices), (config.vertical_rings + 1) * radial_segments + 2)
    testing.expect_value(t, len(mesh.indices), config.vertical_rings * radial_segments * 6 + radial_segments * 6)
    for index in mesh.indices do testing.expect(t, int(index) < len(mesh.vertices))

    ridge := body_radius(config, .5, 0)
    valley := body_radius(config, .5, math.PI / f32(config.ribs))
    testing.expect(t, ridge > valley * 1.1)
    for vertex in mesh.vertices[:len(mesh.vertices) - 2] {
        testing.expect(t, linalg.dot(vertex.normal, vertex.normal) > .99)
    }
}

@(test)
crown_is_tapered_and_depressed :: proc(t: ^testing.T) {
    config := defaults()
    mesh := generate(config)
    defer destroy(&mesh)
    radial_segments := config.ribs * config.samples_per_rib
    middle_radius := math.abs(mesh.vertices[(config.vertical_rings / 2) * radial_segments].position[0])
    crown_radius := math.abs(mesh.vertices[config.vertical_rings * radial_segments].position[0])
    crown_center := mesh.vertices[len(mesh.vertices) - 1]
    testing.expect(t, crown_radius < middle_radius)
    testing.expect_value(t, crown_center.position[1], config.height - config.crown_depression)
    testing.expect(t, crown_center.normal[1] > .99)
}

@(test)
triangles_have_outward_winding :: proc(t: ^testing.T) {
    config := defaults()
    mesh := generate(config)
    defer destroy(&mesh)
    radial_segments := config.ribs * config.samples_per_rib
    side_index_count := config.vertical_rings * radial_segments * 6

    for first := 0; first < len(mesh.indices); first += 3 {
        a := mesh.vertices[mesh.indices[first]].position
        b := mesh.vertices[mesh.indices[first + 1]].position
        c := mesh.vertices[mesh.indices[first + 2]].position
        face_normal := linalg.normalize0(linalg.cross(b - a, c - a))
        if first < side_index_count {
            center := (a + b + c) / f32(3)
            radial := linalg.normalize0([3]f32{center[0], 0, center[2]})
            testing.expect(t, linalg.dot(face_normal, radial) > 0)
        } else {
            cap_triangle := (first - side_index_count) / 3
            if cap_triangle % 2 == 0 {
                testing.expect(t, face_normal[1] < 0)
            } else {
                testing.expect(t, face_normal[1] > 0)
            }
        }
    }
}
