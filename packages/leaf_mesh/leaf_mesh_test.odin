package leaf_mesh

import "core:math"
import "core:math/linalg"
import "core:testing"

@(test)
generates_valid_meshes_for_every_shape :: proc(t: ^testing.T) {
    for index in 0 ..< SHAPE_COUNT {
        config := defaults(Shape(index))
        mesh := generate(config)
        testing.expect(t, mesh.vertex_count > 3)
        testing.expect(t, mesh.index_count >= 3)
        if is_palmate(config.shape) {
            testing.expect(t, mesh.index_count == (mesh.vertex_count - 2) * 3)
        } else {
            testing.expect(t, mesh.vertex_count == (config.segments + 1) * 3)
            testing.expect(t, mesh.index_count == config.segments * 12)
        }
        for vertex_index in mesh.indices[:mesh.index_count] {
            testing.expect(t, int(vertex_index) < mesh.vertex_count)
        }
    }
}

@(test)
serration_changes_edge_without_moving_midrib :: proc(t: ^testing.T) {
    plain := defaults(.Elliptic)
    toothed := plain
    toothed.serration = .2
    a := generate(plain)
    b := generate(toothed)
    row := 7
    testing.expect(t, a.vertices[row * 3].position != b.vertices[row * 3].position)
    testing.expect(t, a.vertices[row * 3 + 1].position == b.vertices[row * 3 + 1].position)
}

@(test)
curved_mesh_has_unit_varying_normals :: proc(t: ^testing.T) {
    config := defaults(.Fig)
    config.curl = .28
    config.cup = .16
    mesh := generate(config)
    first := mesh.vertices[0].normal
    varied := false
    for vertex in mesh.vertices[:mesh.vertex_count] {
        testing.expect(t, linalg.dot(vertex.normal, vertex.normal) > .99)
        testing.expect(t, vertex.normal[2] > 0)
        if linalg.dot(vertex.normal - first, vertex.normal - first) > .0001 do varied = true
    }
    testing.expect(t, varied)
}

@(test)
cypress_spray_has_repeated_scale_lobes :: proc(t: ^testing.T) {
    config := defaults(.Cypress_Spray)
    config.segments = 24
    mesh := generate(config)
    // Adjacent stations repeatedly widen and narrow instead of describing
    // one smooth broadleaf blade.
    reversals := 0
    previous_delta := f32(0)
    for row in 1 ..= config.segments {
        previous_width := math.abs(mesh.vertices[(row - 1) * 3].position[0])
        width := math.abs(mesh.vertices[row * 3].position[0])
        delta := width - previous_width
        if row > 1 && delta * previous_delta < 0 do reversals += 1
        if math.abs(delta) > .00001 do previous_delta = delta
    }
    testing.expect(t, reversals >= 6)
}
