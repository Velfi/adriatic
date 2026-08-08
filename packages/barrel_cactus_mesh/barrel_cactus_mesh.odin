// Package barrel_cactus_mesh generates closed, renderer-independent ribbed
// cactus bodies. It owns botanical body topology; spines and flowers remain
// optional presentation attachments for consumers.
package barrel_cactus_mesh

import "core:math"
import "core:math/linalg"

Config :: struct {
    radius:           f32,
    height:           f32,
    ribs:             int,
    vertical_rings:   int,
    samples_per_rib:  int,
    rib_depth:        f32,
    crown_depression: f32,
    base_taper:       f32,
    crown_taper:      f32,
}

Vertex :: struct {
    position: [3]f32,
    normal:   [3]f32,
    uv:       [2]f32,
    rib:      u16,
}

Mesh :: struct {
    vertices: [dynamic]Vertex,
    indices:  [dynamic]u32,
}

defaults :: proc() -> Config {
    return {
        radius = .32,
        height = .52,
        ribs = 20,
        vertical_rings = 12,
        samples_per_rib = 2,
        rib_depth = .085,
        crown_depression = .045,
        base_taper = .18,
        crown_taper = .24,
    }
}

destroy :: proc(mesh: ^Mesh) {
    if mesh == nil do return
    delete(mesh.vertices)
    delete(mesh.indices)
    mesh^ = {}
}

body_radius :: proc(config: Config, t, angle: f32) -> f32 {
    belly := .86 + .14 * math.sin(math.PI * t)
    base := 1 - clamp(config.base_taper, f32(0), f32(.8)) * (1 - math.smoothstep(f32(0), f32(.18), t))
    crown := 1 - clamp(config.crown_taper, f32(0), f32(.8)) * math.smoothstep(f32(.68), f32(1), t)
    ribs := 1 + clamp(config.rib_depth, f32(0), f32(.24)) * math.cos(angle * f32(config.ribs))
    return config.radius * belly * base * crown * ribs
}

position_at :: proc(config: Config, ring, radial_segments: int, side: int) -> [3]f32 {
    t := f32(ring) / f32(config.vertical_rings)
    angle := f32(side) * math.PI * 2 / f32(radial_segments)
    radius := body_radius(config, t, angle)
    return {math.cos(angle) * radius, t * config.height, math.sin(angle) * radius}
}

generate :: proc(source: Config) -> Mesh {
    config := source
    config.radius = max(config.radius, f32(.01))
    config.height = max(config.height, f32(.01))
    config.ribs = clamp(config.ribs, 5, 48)
    config.vertical_rings = clamp(config.vertical_rings, 3, 48)
    config.samples_per_rib = clamp(config.samples_per_rib, 2, 4)
    radial_segments := config.ribs * config.samples_per_rib
    mesh := Mesh {
        vertices = make([dynamic]Vertex, 0, (config.vertical_rings + 1) * radial_segments + 2),
        indices  = make([dynamic]u32, 0, config.vertical_rings * radial_segments * 6 + radial_segments * 6),
    }

    for ring in 0 ..= config.vertical_rings {
        t := f32(ring) / f32(config.vertical_rings)
        for side in 0 ..< radial_segments {
            position := position_at(config, ring, radial_segments, side)
            previous := position_at(config, ring, radial_segments, (side + radial_segments - 1) % radial_segments)
            next := position_at(config, ring, radial_segments, (side + 1) % radial_segments)
            below := position_at(config, max(ring - 1, 0), radial_segments, side)
            above := position_at(config, min(ring + 1, config.vertical_rings), radial_segments, side)
            tangent_around := next - previous
            tangent_up := above - below
            normal := linalg.normalize0(linalg.cross(tangent_around, tangent_up))
            radial := linalg.normalize0([3]f32{position[0], 0, position[2]})
            if linalg.dot(normal, radial) < 0 do normal = -normal
            append(&mesh.vertices, Vertex {
                position = position,
                normal   = normal,
                uv       = {f32(side) / f32(radial_segments), t},
                rib      = u16(side / config.samples_per_rib),
            })
        }
    }
    for ring in 0 ..< config.vertical_rings {
        for side in 0 ..< radial_segments {
            next := (side + 1) % radial_segments
            a := u32(ring * radial_segments + side)
            b := u32((ring + 1) * radial_segments + side)
            c := u32((ring + 1) * radial_segments + next)
            d := u32(ring * radial_segments + next)
            append(&mesh.indices, a, b, c, a, c, d)
        }
    }

    base_center := u32(len(mesh.vertices))
    append(&mesh.vertices, Vertex{position = {0, 0, 0}, normal = {0, -1, 0}, uv = {.5, .5}})
    crown_center := u32(len(mesh.vertices))
    append(&mesh.vertices, Vertex {
        position = {0, config.height - clamp(config.crown_depression, f32(0), config.height * .45), 0},
        normal   = {0, 1, 0},
        uv       = {.5, .5},
    })
    crown_first := u32(config.vertical_rings * radial_segments)
    for side in 0 ..< radial_segments {
        next := (side + 1) % radial_segments
        append(&mesh.indices, base_center, u32(side), u32(next))
        append(&mesh.indices, crown_center, crown_first + u32(next), crown_first + u32(side))
    }
    return mesh
}
