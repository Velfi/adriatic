package main

import "core:testing"

when ODIN_TEST {
    @(test)
    crunchiness_render_width_preserves_viewport_aspect_ratio :: proc(t: ^testing.T) {
        testing.expect_value(t, crunchiness_render_width(720, 1280, 720), u32(1280))
        testing.expect_value(t, crunchiness_render_width(480, 1920, 1080), u32(853))
        testing.expect_value(t, crunchiness_render_width(480, 1024, 768), u32(640))
        testing.expect_value(t, crunchiness_render_width(240, 3440, 1440), u32(573))
    }

    @(test)
    crunchiness_render_width_rejects_invalid_viewports :: proc(t: ^testing.T) {
        testing.expect_value(t, crunchiness_render_width(480, 0, 720), u32(0))
        testing.expect_value(t, crunchiness_render_width(480, 1280, 0), u32(0))
    }
}
