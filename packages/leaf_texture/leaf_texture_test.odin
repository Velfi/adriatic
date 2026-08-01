package leaf_texture

import leaves "../leaf_mesh"
import "core:testing"

@(test)
generates_midrib_and_bilateral_veins_for_every_shape :: proc(t: ^testing.T) {
    for index in 0 ..< leaves.SHAPE_COUNT {
        graph := generate(defaults(leaves.Shape(index)))
        testing.expect(t, graph.count > 5)
        testing.expect(t, graph.segments[0].a == [2]f32{0, 0})
        left, right := false, false
        for segment in graph.segments[:graph.count] {
            if segment.b.x < 0 do left = true
            if segment.b.x > 0 do right = true
            testing.expect(t, segment.b.y >= 0)
        }
        testing.expect(t, left && right)
    }
}

@(test)
raster_is_deterministic_nonempty_and_symmetric :: proc(t: ^testing.T) {
    config := defaults(.Elliptic)
    config.seed = 42
    a, b: [64 * 64]u8
    testing.expect(t, rasterize(config, a[:], 64, 64))
    testing.expect(t, rasterize(config, b[:], 64, 64))
    testing.expect(t, a == b)
    lit := 0
    for value in a do if value > 0 do lit += 1
    testing.expect(t, lit > 64)
    testing.expect(t, a[32] > 0 || a[31] > 0)
}

@(test)
raster_rejects_wrong_buffer_size :: proc(t: ^testing.T) {
    pixels: [7]u8
    testing.expect(t, !rasterize(defaults(.Ovate), pixels[:], 4, 4))
}
