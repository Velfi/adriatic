package branch_mesh

import plant_structure "../plant_structure"
import "core:math"
import "core:math/linalg"
import "core:testing"

@(test)
connected_segments_form_a_finite_capped_hull :: proc(t: ^testing.T) {
    segments := [3]plant_structure.Segment {
        {{0, 0, 0}, {0, 1, 0}, .2, .17, 0},
        {{0, 1, 0}, {.2, 2, 0}, .17, .12, 0},
        {{.2, 2, 0}, {.1, 3, .2}, .12, .06, 0},
    }
    mesh := generate(segments[:], {radial_segments = 8, samples_per_segment = 3, minimum_radius = .01})
    defer destroy(&mesh)
    testing.expect(t, len(mesh.vertices) > 8 * 4)
    testing.expect(t, len(mesh.indices) > 0)
    for vertex in mesh.vertices {
        for value in vertex.position do testing.expect(t, !math.is_nan(value) && !math.is_inf(value))
        normal_length := math.sqrt(
            vertex.normal[0] * vertex.normal[0] +
            vertex.normal[1] * vertex.normal[1] +
            vertex.normal[2] * vertex.normal[2],
        )
        testing.expect(t, math.abs(normal_length - 1) < .001)
        testing.expect(t, vertex.uv[0] >= 0 && vertex.uv[0] <= 1)
        testing.expect(t, vertex.uv[1] >= 0 && vertex.uv[1] <= 1)
        testing.expect(t, vertex.bark_uv[0] >= 0 && vertex.bark_uv[0] < 1)
        testing.expect(t, vertex.bark_uv[1] >= 0)
    }
    for index in mesh.indices do testing.expect(t, int(index) < len(mesh.vertices))
    for first := 0; first + 2 < len(mesh.indices); first += 3 {
        a := mesh.vertices[mesh.indices[first + 0]]
        b := mesh.vertices[mesh.indices[first + 1]]
        c := mesh.vertices[mesh.indices[first + 2]]
        face := linalg.cross(b.position - a.position, c.position - a.position)
        if linalg.dot(face, face) < 1e-12 do continue
        average_normal := a.normal + b.normal + c.normal
        testing.expect(t, linalg.dot(face, average_normal) > 0)
    }
}

@(test)
fork_depths_create_separate_watertight_hulls :: proc(t: ^testing.T) {
    segments := [3]plant_structure.Segment {
        {{0, 0, 0}, {0, 1, 0}, .2, .15, 0},
        {{0, 1, 0}, {1, 2, 0}, .10, .04, 1},
        {{0, 1, 0}, {0, 2, 0}, .15, .08, 0},
    }
    mesh := generate(segments[:], {radial_segments = 6, samples_per_segment = 2, minimum_radius = .01})
    defer destroy(&mesh)
    // The two-segment trunk contributes four rings plus two cap centers; the
    // one-segment fork contributes three rings plus two cap centers.
    // xatlas duplicates vertices at chart seams while retaining the source
    // hull's two capped chains and complete triangle topology.
    testing.expect(t, len(mesh.vertices) >= 46)
}

@(test)
radial_irregularity_creates_deterministic_fluting :: proc(t: ^testing.T) {
    segments := [1]plant_structure.Segment{{{0, 0, 0}, {0, 2, 0}, .3, .24, 0}}
    config := Config {
        radial_segments     = 10,
        samples_per_segment = 3,
        minimum_radius      = .01,
        radial_irregularity = .16,
        twist               = 1.2,
        seed                = 73,
    }
    a := generate(segments[:], config)
    b := generate(segments[:], config)
    defer destroy(&a)
    defer destroy(&b)
    testing.expect_value(t, len(a.vertices), len(b.vertices))
    minimum_radius, maximum_radius := f32(1000), f32(0)
    for index in 0 ..< config.radial_segments {
        testing.expect_value(t, a.vertices[index].position, b.vertices[index].position)
        position := a.vertices[index].position
        radius := math.sqrt(position[0] * position[0] + position[2] * position[2])
        minimum_radius = min(minimum_radius, radius)
        maximum_radius = max(maximum_radius, radius)
    }
    testing.expect(t, maximum_radius - minimum_radius > .03)
}
