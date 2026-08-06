package tests

import dither "zelda_engine:dither"
import "core:math"
import "core:testing"

@(test)
dither_mode_labels_and_offsets :: proc(t: ^testing.T) {
    testing.expect_value(t, dither.mode_label(.Off), cstring("OFF"))
    testing.expect_value(t, dither.mode_label(.Bayer), cstring("BAYER"))
    testing.expect_value(t, dither.mode_label(.Blue_Noise), cstring("BLUE"))
    testing.expect_value(t, dither.mode_label(.Matriax_8), cstring("MATRIAX 8"))
    testing.expect_value(t, dither.pattern_offset(0, 1, 1280, 8), 0)
    testing.expect_value(t, dither.pattern_offset(1, 1, 1280, 8), 0)
    testing.expect_value(t, dither.pattern_offset(-1.0 / 1280, 1, 1280, 8), 7)
    testing.expect_value(t, dither.adjust_mode(.Off, -1), dither.Mode.Off)
    testing.expect_value(t, dither.adjust_mode(.Bayer, 1), dither.Mode.Blue_Noise)
    testing.expect_value(t, dither.adjust_mode(.Blue_Noise, 1), dither.Mode.Matriax_8)
    testing.expect_value(t, dither.next_mode(.Matriax_8), dither.Mode.Off)
    testing.expect_value(t, dither.pixel_phase_delta(.1, 1, 100), f32(10))
    testing.expect_value(t, dither.wrap_pixel_phase(-1, 8), 7)
}

@(test)
dither_angle_wrapping_uses_shortest_rotation :: proc(t: ^testing.T) {
    wrapped := dither.wrap_angle(f32(math.PI * 2 - .125))
    testing.expect(t, math.abs(wrapped + .125) < .0001)
}
