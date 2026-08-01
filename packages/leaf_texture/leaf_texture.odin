// Package leaf_texture generates deterministic, renderer-independent leaf vein
// graphs and raster masks for the silhouettes in leaf_mesh.
package leaf_texture

import leaves "../leaf_mesh"
import "core:math"

MAX_SEGMENTS :: 128

Config :: struct {
    shape:           leaves.Shape,
    length:          f32,
    width:           f32,
    secondary_pairs: int,
    reach:           f32,
    sweep:           f32,
    curvature:       f32,
    tertiary:        bool,
    seed:            u32,
}

Segment :: struct {
    a:     [2]f32,
    b:     [2]f32,
    width: f32,
    level: u8,
}

Graph :: struct {
    segments: [MAX_SEGMENTS]Segment,
    count:    int,
}

defaults :: proc(shape: leaves.Shape) -> Config {
    blade := leaves.defaults(shape)
    pairs := 7
    if shape == .Lanceolate do pairs = 9
    if leaves.is_palmate(shape) do pairs = 5
    if shape == .Cypress_Spray do pairs = 10
    return Config {
        shape = shape,
        length = blade.length,
        width = blade.width,
        secondary_pairs = pairs,
        reach = .88,
        sweep = .12,
        curvature = .16,
        tertiary = true,
        seed = 1,
    }
}

hash01 :: #force_inline proc(value: u32) -> f32 {
    x := value
    x = x ~ (x >> 16)
    x *= 0x7feb352d
    x = x ~ (x >> 15)
    x *= 0x846ca68b
    x = x ~ (x >> 16)
    return f32(x & 0xffff) / 65535
}

append_segment :: #force_inline proc(graph: ^Graph, a, b: [2]f32, width: f32, level: u8) {
    if graph.count >= MAX_SEGMENTS do return
    graph.segments[graph.count] = {
        a     = a,
        b     = b,
        width = width,
        level = level,
    }
    graph.count += 1
}

// generate returns a small line graph in leaf-local coordinates. Y runs from
// the petiole at zero to the leaf tip at config.length.
generate :: proc(config: Config) -> Graph {
    graph: Graph
    length := max(config.length, f32(.01))
    width := max(config.width, f32(.01))
    pair_count := clamp(config.secondary_pairs, 1, 24)
    append_segment(&graph, {0, 0}, {0, length}, width * .032, 0)

    for pair in 0 ..< pair_count {
        t := (.12 + f32(pair) * .76 / f32(max(pair_count - 1, 1)))
        jitter := (hash01(config.seed + u32(pair) * 17) - .5) * .035
        anchor_t := clamp(t + jitter, f32(.06), f32(.91))
        end_t := clamp(anchor_t + config.sweep * (1 - anchor_t), anchor_t, f32(.97))
        edge := leaves.half_width(config.shape, end_t) * width * clamp(config.reach, f32(.2), f32(1))
        anchor := [2]f32{0, anchor_t * length}
        bend_y := (anchor_t + (end_t - anchor_t) * (.48 + config.curvature * .28)) * length
        sides := [2]f32{-1, 1}
        for side in sides {
            bend := [2]f32{side * edge * (.48 - config.curvature * .12), bend_y}
            tip := [2]f32{side * edge, end_t * length}
            append_segment(&graph, anchor, bend, width * .016, 1)
            append_segment(&graph, bend, tip, width * .010, 1)
            if config.tertiary && pair > 0 && pair + 1 < pair_count {
                twig_t := clamp(end_t + .055, end_t, f32(.985))
                twig_edge := leaves.half_width(config.shape, twig_t) * width * clamp(config.reach, f32(.2), f32(1))
                twig := [2]f32{side * twig_edge, twig_t * length}
                append_segment(&graph, bend, twig, width * .006, 2)
            }
        }
    }
    return graph
}

distance_to_segment :: #force_inline proc(point, a, b: [2]f32) -> f32 {
    ab := b - a
    length_squared := ab.x * ab.x + ab.y * ab.y
    if length_squared <= 1e-8 do return math.sqrt((point.x - a.x) * (point.x - a.x) + (point.y - a.y) * (point.y - a.y))
    t := clamp(((point.x - a.x) * ab.x + (point.y - a.y) * ab.y) / length_squared, f32(0), f32(1))
    nearest := a + ab * t
    delta := point - nearest
    return math.sqrt(delta.x * delta.x + delta.y * delta.y)
}

// rasterize writes a single-channel vein mask. The caller owns the buffer;
// rows run from leaf base to tip and values use antialiased 0..255 coverage.
rasterize :: proc(config: Config, pixels: []u8, texture_width, texture_height: int) -> bool {
    if texture_width <= 0 || texture_height <= 0 || len(pixels) != texture_width * texture_height do return false
    for &pixel in pixels do pixel = 0
    graph := generate(config)
    length := max(config.length, f32(.01))
    width := max(config.width, f32(.01))
    pixel_size := max(width * 2 / f32(texture_width), length / f32(texture_height))
    for y in 0 ..< texture_height {
        local_y := (f32(y) + .5) / f32(texture_height) * length
        for x in 0 ..< texture_width {
            local_x := ((f32(x) + .5) / f32(texture_width) * 2 - 1) * width
            point := [2]f32{local_x, local_y}
            coverage: f32
            for segment in graph.segments[:graph.count] {
                radius := max(segment.width, pixel_size * .45)
                distance := distance_to_segment(point, segment.a, segment.b)
                coverage = max(coverage, clamp((radius + pixel_size - distance) / pixel_size, f32(0), f32(1)))
            }
            pixels[x + y * texture_width] = u8(coverage * 255)
        }
    }
    return true
}
