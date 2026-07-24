package tests

import wireframe "../packages/wireframe"
import "core:testing"

@(test)
wireframe_interpolates_vertex_color :: proc(t: ^testing.T) {
    pixels: [25]wireframe.Color; depth: [25]f32
    target := wireframe.Target {
        width  = 5,
        height = 5,
        pixels = pixels[:],
        depth  = depth[:],
    }; wireframe.clear(&target, {})
    camera := wireframe.default_camera(
        
    ); vertices := [2]wireframe.Vertex{{position = {-1, 0, -2}, color = {r = 1}}, {position = {1, 0, -2}, color = {b = 1}}}; edges := [1]wireframe.Edge{{0, 1}}
    wireframe.draw_model(&target, camera, vertices[:], edges[:]); middle := target.pixels[2 + 2 * 5]
    testing.expect(t, middle.r > 80 && middle.b > 80)
}

@(test)
wireframe_depth_occludes_far_edge :: proc(t: ^testing.T) {
    pixels: [25]wireframe.Color; depth: [25]f32
    target := wireframe.Target {
        width  = 5,
        height = 5,
        pixels = pixels[:],
        depth  = depth[:],
    }; wireframe.clear(&target, {})
    camera := wireframe.default_camera(
        
    ); far := [2]wireframe.Vertex{{position = {-1, 0, -4}, color = {r = 1}}, {position = {1, 0, -4}, color = {r = 1}}}; near := [2]wireframe.Vertex{{position = {-1, 0, -2}, color = {g = 1}}, {position = {1, 0, -2}, color = {g = 1}}}; edge := [1]wireframe.Edge{{0, 1}}
    wireframe.draw_model(
        &target,
        camera,
        far[:],
        edge[:],
    ); wireframe.draw_model(&target, camera, near[:], edge[:]); middle := target.pixels[2 + 2 * 5]
    testing.expect(t, middle.g > 200 && middle.r == 0)
}
