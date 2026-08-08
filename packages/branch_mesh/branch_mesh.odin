// Package branch_mesh turns a plant architecture segment tree into smooth, capped
// branch hulls. Same-depth connected segments become one spline so joints
// share rings and normals instead of appearing as stacked primitives.
package branch_mesh

import plant_structure "../plant_structure"
import "core:math"
import "core:math/linalg"

when ODIN_OS == .Windows {
    foreign import adriatic_mesh "system:adriatic_mesh.lib"
} else {
    foreign import adriatic_mesh "system:adriatic_mesh"
}

foreign adriatic_mesh {
    adriatic_generate_uv_atlas :: proc(positions: ^f32, vertex_count: u32, indices: ^u32, index_count: u32, source_by_atlas_vertex: ^u32, uv_by_atlas_vertex: ^f32, atlas_indices: ^u32, output_vertex_capacity: u32) -> u32 ---
}

Vertex :: struct {
    position: [3]f32,
    normal:   [3]f32,
    uv:       [2]f32,
    // Continuous cylindrical coordinates authored from the generating
    // spline. Unlike the xatlas UV above, this follows branch direction and
    // survives chart duplication for procedural bark sampling.
    bark_uv:  [2]f32,
}

generate_uv_atlas :: proc(mesh: ^Mesh) {
    if mesh == nil || len(mesh.vertices) == 0 || len(mesh.indices) == 0 do return
    capacity := len(mesh.indices)
    sources := make([]u32, capacity)
    uvs := make([]f32, capacity * 2)
    indices := make([]u32, len(mesh.indices))
    positions := make([][3]f32, len(mesh.vertices))
    defer delete(sources)
    defer delete(uvs)
    defer delete(indices)
    defer delete(positions)
    for vertex, index in mesh.vertices do positions[index] = vertex.position
    atlas_vertex_count := int(
        adriatic_generate_uv_atlas(
            &positions[0][0],
            u32(len(mesh.vertices)),
            raw_data(mesh.indices),
            u32(len(mesh.indices)),
            raw_data(sources),
            raw_data(uvs),
            raw_data(indices),
            u32(capacity),
        ),
    )
    if atlas_vertex_count <= 0 do return
    for atlas_index in 0 ..< atlas_vertex_count {
        if int(sources[atlas_index]) >= len(mesh.vertices) do return
    }
    vertices := make([dynamic]Vertex, atlas_vertex_count)
    for atlas_index in 0 ..< atlas_vertex_count {
        source_index := int(sources[atlas_index])
        vertices[atlas_index] = mesh.vertices[source_index]
        vertices[atlas_index].uv = {uvs[atlas_index * 2], uvs[atlas_index * 2 + 1]}
    }
    delete(mesh.vertices)
    delete(mesh.indices)
    mesh.vertices = vertices
    mesh.indices = make([dynamic]u32, len(indices))
    copy(mesh.indices[:], indices[:])
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
    // Optional explicit topology from plants.Generated_Plant. When supplied,
    // chains are grouped by botanical axis instead of inferred from renderer
    // depth and storage adjacency.
    axis_ids:            []int,
    parent_ids:          []int,
}

destroy :: proc(mesh: ^Mesh) {
    if mesh == nil do return
    delete(mesh.vertices)
    delete(mesh.indices)
    mesh^ = {}
}

near :: proc(a, b: plant_structure.Vec3) -> bool {
    delta := a - b
    return linalg.dot(delta, delta) < 1e-7
}

catmull_rom :: proc(a, b, c, d: plant_structure.Vec3, t: f32) -> plant_structure.Vec3 {
    t2, t3 := t * t, t * t * t
    return (b * 2 + (c - a) * t + (a * 2 - b * 5 + c * 4 - d) * t2 + (-a + b * 3 - c * 3 + d) * t3) * .5
}

append_ring :: proc(
    mesh: ^Mesh,
    center, tangent: plant_structure.Vec3,
    radius: f32,
    radial_segments: int,
    previous_right: ^plant_structure.Vec3,
    config: Config,
    along: f32,
) -> u32 {
    unit_tangent := linalg.normalize0(tangent)
    right: plant_structure.Vec3
    if linalg.dot(previous_right^, previous_right^) > .5 {
        // Rotation-minimizing transport: project the previous frame onto the
        // new tangent plane. This avoids the roll and occasional frame flip
        // caused by rebuilding every ring from a fixed world axis.
        transported := previous_right^ - unit_tangent * linalg.dot(previous_right^, unit_tangent)
        if linalg.dot(transported, transported) > 1e-8 {
            right = linalg.normalize0(transported)
        }
    }
    if linalg.dot(right, right) < .5 {
        reference := math.abs(unit_tangent[1]) > .88 ? plant_structure.Vec3{1, 0, 0} : plant_structure.Vec3{0, 1, 0}
        right = linalg.normalize0(linalg.cross(reference, unit_tangent))
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
        append(&mesh.vertices, Vertex {
            position = center + normal * local_radius,
            normal   = normal,
            bark_uv  = {f32(side) / f32(radial_segments), along},
        })
    }
    return first
}

append_chain :: proc(mesh: ^Mesh, chain: []plant_structure.Segment, config: Config, parent_overlap: f32) {
    if mesh == nil || len(chain) == 0 do return
    radial := clamp(config.radial_segments, 3, 16)
    samples_per_segment := clamp(config.samples_per_segment, 1, 6)
    points := make([dynamic]plant_structure.Vec3, 0, len(chain) + 1)
    radii := make([dynamic]f32, 0, len(chain) + 1)
    defer delete(points)
    defer delete(radii)
    append(&points, chain[0].start)
    append(&radii, max(chain[0].radius_start, config.minimum_radius))
    for segment in chain {
        append(&points, segment.end)
        append(&radii, max(segment.radius_end, config.minimum_radius))
    }
    has_parent := parent_overlap > 0
    if has_parent && len(points) > 1 {
        direction := linalg.normalize0(points[1] - points[0])
        points[0] -= direction * max(parent_overlap, config.minimum_radius * 2)
    }

    previous_right: plant_structure.Vec3
    previous_ring := u32(0)
    ring_count := 0
    along: f32
    previous_center: plant_structure.Vec3
    has_previous_center := false
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
            if has_previous_center {
                delta := center - previous_center
                along += math.sqrt(linalg.dot(delta, delta))
            }
            ring := append_ring(mesh, center, tangent, radius, radial, &previous_right, config, along)
            previous_center = center
            has_previous_center = true
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
    final_center := points[len(points) - 1]
    if has_previous_center {
        delta := final_center - previous_center
        along += math.sqrt(linalg.dot(delta, delta))
    }
    final_ring := append_ring(
        mesh,
        final_center,
        last_tangent,
        radii[len(radii) - 1],
        radial,
        &previous_right,
        config,
        along,
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

    if !has_parent {
        start_center := u32(len(mesh.vertices))
        start_tangent := linalg.normalize0(points[1] - points[0])
        append(&mesh.vertices, Vertex{position = points[0], normal = -start_tangent, bark_uv = {.5, 0}})
        chain_ring_vertices := u32((ring_count + 1) * radial)
        first_ring := start_center - chain_ring_vertices
        for side in 0 ..< radial {
            next := (side + 1) % radial
            append(&mesh.indices, start_center, first_ring + u32(next), first_ring + u32(side))
        }
    }
    finish_center := u32(len(mesh.vertices))
    append(
        &mesh.vertices,
        Vertex{position = points[len(points) - 1], normal = linalg.normalize0(last_tangent), bark_uv = {.5, along}},
    )
    for side in 0 ..< radial {
        next := (side + 1) % radial
        append(&mesh.indices, finish_center, final_ring + u32(side), final_ring + u32(next))
    }
}

generate :: proc(segments: []plant_structure.Segment, config: Config) -> Mesh {
    mesh: Mesh
    if len(segments) == 0 do return mesh
    used := make([]bool, len(segments))
    defer delete(used)
    chain := make([dynamic]plant_structure.Segment)
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
                if used[candidate] do continue
                same_axis := segments[candidate].depth == segments[current].depth
                if len(config.axis_ids) == len(segments) {
                    same_axis = config.axis_ids[candidate] == config.axis_ids[current]
                }
                if !same_axis do continue
                if near(segments[candidate].start, segments[current].end) {
                    next_index = candidate
                    break
                }
            }
            if next_index < 0 do break
            current = next_index
        }
        parent_overlap := f32(0)
        if len(config.parent_ids) == len(segments) {
            parent := config.parent_ids[start_index]
            if parent >= 0 && parent < len(segments) {
                parent_overlap = max(segments[parent].radius_end * 1.15, segments[start_index].radius_start * 1.35)
            }
        }
        append_chain(&mesh, chain[:], config, parent_overlap)
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
    generate_uv_atlas(&mesh)
    return mesh
}
