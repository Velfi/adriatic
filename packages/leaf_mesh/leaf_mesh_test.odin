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
        if config.shape == .Cypress_Spray {
            testing.expect(t, mesh.vertex_count >= 36)
            testing.expect(t, mesh.index_count >= 54)
        } else if is_palmate(config.shape) {
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
cypress_spray_has_separated_paired_scales :: proc(t: ^testing.T) {
    config := defaults(.Cypress_Spray)
    config.segments = 24
    mesh := generate(config)
    // One shoot quad followed by independently pointed left/right scales.
    testing.expect_value(t, mesh.vertex_count, (1 + 16 * 2) * 4)
    testing.expect_value(t, mesh.index_count, (1 + 16 * 2) * 6)
    left_tips, right_tips, raised_tips := 0, 0, 0
    for scale := 1; scale < 33; scale += 1 {
        tip := mesh.vertices[scale * 4 + 2].position
        if tip[0] < 0 do left_tips += 1
        if tip[0] > 0 do right_tips += 1
        if tip[2] > 0 do raised_tips += 1
    }
    testing.expect_value(t, left_tips, 16)
    testing.expect_value(t, right_tips, 16)
    testing.expect_value(t, raised_tips, 32)
}

@(test)
fleshy_node_is_closed_thick_and_tapered :: proc(t: ^testing.T) {
    config := defaults(.Lanceolate)
    config.length = .58
    config.width = .115
    config.thickness = .038
    config.segments = 12
    mesh := generate(config)
    testing.expect_value(t, mesh.vertex_count, (config.segments + 1) * FLESHY_SIDES)
    testing.expect_value(
        t,
        mesh.index_count,
        config.segments * FLESHY_SIDES * 6 + (FLESHY_SIDES - 2) * 6,
    )

    minimum_z, maximum_z := f32(1e9), f32(-1e9)
    positive_z_normal, negative_z_normal := false, false
    for vertex in mesh.vertices[:mesh.vertex_count] {
        minimum_z = min(minimum_z, vertex.position[2])
        maximum_z = max(maximum_z, vertex.position[2])
        testing.expect(t, linalg.dot(vertex.normal, vertex.normal) > .99)
        if vertex.normal[2] > .2 do positive_z_normal = true
        if vertex.normal[2] < -.2 do negative_z_normal = true
    }
    testing.expect(t, maximum_z - minimum_z >= config.thickness * .95)
    testing.expect(t, positive_z_normal && negative_z_normal)
    middle := (config.segments / 2) * FLESHY_SIDES
    testing.expect(t, math.abs(mesh.vertices[middle].position[0]) > math.abs(mesh.vertices[0].position[0]) * 10)
}
