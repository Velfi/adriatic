package main

import "core:math"
import "core:testing"

@(test)
vehicle_paint_brush_uses_equal_normalized_uv_radii :: proc(t: ^testing.T) {
    radius_x, radius_y := vehicle_paint_brush_texel_radii(14)
    horizontal_uv_radius := f32(radius_x) / f32(VEHICLE_PAINT_TEXTURE_WIDTH)
    vertical_uv_radius := f32(radius_y) / f32(VEHICLE_PAINT_TEXTURE_HEIGHT)

    testing.expect(t, math.abs(horizontal_uv_radius - vertical_uv_radius) < .000001)
    testing.expect(t, math.abs(vehicle_paint_brush_distance(radius_x, 0, radius_x, radius_y) - 1) < .000001)
    testing.expect(t, math.abs(vehicle_paint_brush_distance(0, radius_y, radius_x, radius_y) - 1) < .000001)
}
