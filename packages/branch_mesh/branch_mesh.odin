// Package branch_mesh turns an L-system segment tree into smooth, capped
// branch hulls. Same-depth connected segments become one spline so joints
// share rings and normals instead of appearing as stacked primitives.
package branch_mesh

import lsystem "../lsystem"
import "core:math"
import "core:math/linalg"

Vertex :: struct {
    position: [3]f32,
    normal:   [3]f32,
}

Mesh :: struct {
    vertices: [dynamic]Vertex,
    indices:  [dynamic]u32,
}

Config :: struct {
    radial_segments:     int,
    samples_per_segment: int,
    minimum_radius:      f32,
    radial_irregularity: f32,
    twist:               f32,
    seed:                u64,
}

destroy :: proc(mesh: ^Mesh) {
    if mesh == nil do return
    delete(mesh.vertices)
    delete(mesh.indices)
    mesh^ = {}
}

near :: proc(a, b: lsystem.Vec3) -> bool {
    delta := a - b
    return linalg.dot(delta, delta) < 1e-7
}

catmull_rom :: proc(a, b, c, d: lsystem.Vec3, t: f32) -> lsystem.Vec3 {
    t2, t3 := t * t, t * t * t
    return (b * 2 + (c - a) * t + (a * 2 - b * 5 + c * 4 - d) * t2 + (-a + b * 3 - c * 3 + d) * t3) * .5
}

append_ring :: proc(
    mesh: ^Mesh,
    center, tangent: lsystem.Vec3,
    radius: f32,
    radial_segments: int,
    previous_right: ^lsystem.Vec3,
    config: Config,
) -> u32 {
    unit_tangent := linalg.normalize0(tangent)
    reference := math.abs(unit_tangent[1]) > .88 ? lsystem.Vec3{1, 0, 0} : lsystem.Vec3{0, 1, 0}
    right := linalg.normalize0(linalg.cross(reference, unit_tangent))
    if linalg.dot(previous_right^, previous_right^) > .5 && linalg.dot(right, previous_right^) < 0 {
        right = -right
    }
    previous_right^ = right
    up := linalg.normalize0(linalg.cross(unit_tangent, right))
    first := u32(len(mesh.vertices))
    irregularity := clamp(config.radial_irregularity, f32(0), f32(.35))
    phase := f32(config.seed % 997) * .013 + center[1] * config.twist
    for side in 0 ..< radial_segments {
        angle := f32(side) * math.PI * 2 / f32(radial_segments)
        normal := linalg.normalize0(right * math.cos(angle) + up * math.sin(angle))
        lobing := math.sin(angle * 3 + phase) * .68 + math.sin(angle * 5 - phase * .73) * .32
        local_radius := radius * (1 + irregularity * lobing)
        append(&mesh.vertices, Vertex{position = center + normal * local_radius, normal = normal})
    }
    return first
}

append_chain :: proc(mesh: ^Mesh, chain: []lsystem.Segment, config: Config) {
    if mesh == nil || len(chain) == 0 do return
    radial := clamp(config.radial_segments, 3, 16)
    samples_per_segment := clamp(config.samples_per_segment, 1, 6)
    points := make([dynamic]lsystem.Vec3, 0, len(chain) + 1)
    radii := make([dynamic]f32, 0, len(chain) + 1)
    defer delete(points)
    defer delete(radii)
    append(&points, chain[0].start)
    append(&radii, max(chain[0].radius_start, config.minimum_radius))
    for segment in chain {
        append(&points, segment.end)
        append(&radii, max(segment.radius_end, config.minimum_radius))
    }

    previous_right: lsystem.Vec3
    previous_ring := u32(0)
    ring_count := 0
    for segment_index in 0 ..< len(points) - 1 {
        a := segment_index > 0 ? points[segment_index - 1] : points[segment_index]
        b := points[segment_index]
        c := points[segment_index + 1]
        d := segment_index + 2 < len(points) ? points[segment_index + 2] : c
        for sample in 0 ..< samples_per_segment {
            if segment_index > 0 && sample == 0 do continue
            t := f32(sample) / f32(samples_per_segment)
            center := catmull_rom(a, b, c, d, t)
            before := catmull_rom(a, b, c, d, max(t - .015, f32(0)))
            after := catmull_rom(a, b, c, d, min(t + .015, f32(1)))
            tangent := after - before
            radius := radii[segment_index] + (radii[segment_index + 1] - radii[segment_index]) * t
            ring := append_ring(mesh, center, tangent, radius, radial, &previous_right, config)
            if ring_count > 0 {
                for side in 0 ..< radial {
                    next := (side + 1) % radial
                    append(
                        &mesh.indices,
                        previous_ring + u32(side),
                        ring + u32(next),
                        ring + u32(side),
                        previous_ring + u32(side),
                        previous_ring + u32(next),
                        ring + u32(next),
                    )
                }
            }
            previous_ring = ring
            ring_count += 1
        }
    }
    last_tangent := points[len(points) - 1] - points[len(points) - 2]
    final_ring := append_ring(
        mesh,
        points[len(points) - 1],
        last_tangent,
        radii[len(radii) - 1],
        radial,
        &previous_right,
        config,
    )
    if ring_count > 0 {
        for side in 0 ..< radial {
            next := (side + 1) % radial
            append(
                &mesh.indices,
                previous_ring + u32(side),
                final_ring + u32(next),
                final_ring + u32(side),
                previous_ring + u32(side),
                previous_ring + u32(next),
                final_ring + u32(next),
            )
        }
    }

    start_center := u32(len(mesh.vertices))
    start_tangent := linalg.normalize0(points[1] - points[0])
    append(&mesh.vertices, Vertex{position = points[0], normal = -start_tangent})
    first_ring := start_center - u32(radial)
    // The first ring is at vertex zero only for the first chain; recover it
    // from the number of rings appended by this chain.
    chain_ring_vertices := u32((ring_count + 1) * radial)
    first_ring = start_center - chain_ring_vertices
    for side in 0 ..< radial {
        next := (side + 1) % radial
        append(&mesh.indices, start_center, first_ring + u32(next), first_ring + u32(side))
    }
    finish_center := u32(len(mesh.vertices))
    append(&mesh.vertices, Vertex{position = points[len(points) - 1], normal = linalg.normalize0(last_tangent)})
    for side in 0 ..< radial {
        next := (side + 1) % radial
        append(&mesh.indices, finish_center, final_ring + u32(side), final_ring + u32(next))
    }
}

generate :: proc(segments: []lsystem.Segment, config: Config) -> Mesh {
    mesh: Mesh
    if len(segments) == 0 do return mesh
    used := make([]bool, len(segments))
    defer delete(used)
    chain := make([dynamic]lsystem.Segment)
    defer delete(chain)
    for start_index in 0 ..< len(segments) {
        if used[start_index] do continue
        clear(&chain)
        current := start_index
        for {
            used[current] = true
            append(&chain, segments[current])
            next_index := -1
            for candidate in current + 1 ..< len(segments) {
                if used[candidate] || segments[candidate].depth != segments[current].depth do continue
                if near(segments[candidate].start, segments[current].end) {
                    next_index = candidate
                    break
                }
            }
            if next_index < 0 do break
            current = next_index
        }
        append_chain(&mesh, chain[:], config)
    }
    // Rebuild normals from the final spline topology. This keeps shading
    // consistent through tight bends where independently transported radial
    // frames can otherwise disagree with the actual triangle winding.
    for &vertex in mesh.vertices do vertex.normal = {}
    for first := 0; first + 2 < len(mesh.indices); first += 3 {
        ia := mesh.indices[first + 0]
        ib := mesh.indices[first + 1]
        ic := mesh.indices[first + 2]
        face := linalg.cross(
            mesh.vertices[ib].position - mesh.vertices[ia].position,
            mesh.vertices[ic].position - mesh.vertices[ia].position,
        )
        mesh.vertices[ia].normal += face
        mesh.vertices[ib].normal += face
        mesh.vertices[ic].normal += face
    }
    for &vertex in mesh.vertices {
        vertex.normal = linalg.normalize0(vertex.normal)
        if linalg.dot(vertex.normal, vertex.normal) < .001 do vertex.normal = {0, 1, 0}
    }
    return mesh
}
