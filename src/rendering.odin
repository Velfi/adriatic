package main

import canvas2d "zelda_engine:canvas2d"
import render2d "zelda_engine:render2d"

ATTITUDE_GAUGE_EFFECT :: u32(1)

Attitude_Gauge_Effect :: struct {
    pitch_offset: f32,
    bank:         f32,
    scale:        f32,
}

encode_canvas_batch_payload :: proc(destination: []u8, batch_data: rawptr, user_data: rawptr) -> bool {
    if len(destination) < size_of(canvas2d.Push) || batch_data == nil do return false
    batch := cast(^canvas2d.Batch)batch_data
    if batch.effect.kind != ATTITUDE_GAUGE_EFFECT || batch.effect.size != size_of(Attitude_Gauge_Effect) do return false
    effect := cast(^Attitude_Gauge_Effect)raw_data(batch.effect.bytes[:])
    push := cast(^canvas2d.Push)raw_data(destination)
    push.texture_hatch[1] = f32(ATTITUDE_GAUGE_EFFECT)
    push.hatch_shape = {effect.pitch_offset, effect.bank, effect.scale, 0}
    return true
}

ADRIATIC_RENDERER_DESCRIPTOR := render2d.Renderer_Descriptor {
    pipeline = {
        vertex = {"assets/shaders/canvas.vert", .Vertex, "main", "shaders/canvas.vert"},
        fragment = {"assets/shaders/canvas.frag", .Fragment, "main", "shaders/canvas.frag"},
        post_vertex = {"assets/shaders/canvas-post.vert", .Vertex, "main", "shaders/canvas-post.vert"},
        post_fragment = {"assets/shaders/canvas-post.frag", .Fragment, "main", "shaders/canvas-post.frag"},
        push_constant_size = size_of(canvas2d.Push),
        post_process_enabled = true,
    },
    user_data = &world_renderer,
    encode_batch_payload = encode_canvas_batch_payload,
    encode_world_post_push = dither_encode_world_post_push,
}
