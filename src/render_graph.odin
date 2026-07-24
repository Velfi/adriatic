package main

import render_graph "../packages/render_graph"
import terrain "../packages/terrain"
import vk "vendor:vulkan"
import rl "zelda_engine:canvas2d"
import engine "zelda_engine:engine"

Render_Graph_Context :: struct {
    pass:           ^rl.World_Pass_Context,
    buffer:         ^engine.Vk_Buffer,
    offset:         vk.DeviceSize,
    pipeline_index: int,
    world_push:     World_Push,
    sky_push:       Sky_Push,
}

world_render_graph: render_graph.Graph
world_render_graph_ready: bool

render_graph_stage_label :: proc(ctx: ^Render_Graph_Context, name: cstring) {
    engine.vk_cmd_label_begin(ctx.pass.ctx, ctx.pass.frame.command_buffer, name)
}

render_graph_stage_end :: proc(ctx: ^Render_Graph_Context) {
    engine.vk_cmd_label_end(ctx.pass.ctx, ctx.pass.frame.command_buffer)
}

render_graph_sky :: proc(user_data: rawptr) {
    ctx := cast(^Render_Graph_Context)user_data
    cmd := ctx.pass.frame.command_buffer
    render_graph_stage_label(ctx, "Adriatic / Sky")
    vk.CmdPushConstants(
        cmd,
        world_renderer.sky_layout,
        {.VERTEX, .FRAGMENT},
        0,
        u32(size_of(ctx.sky_push)),
        &ctx.sky_push,
    )
    vk.CmdBindPipeline(cmd, .GRAPHICS, world_renderer.sky_pipelines[ctx.pipeline_index])
    vk.CmdDraw(cmd, 3, 1, 0, 0)
    render_graph_stage_end(ctx)
}

render_graph_geometry :: proc(user_data: rawptr) {
    ctx := cast(^Render_Graph_Context)user_data
    cmd := ctx.pass.frame.command_buffer
    render_graph_stage_label(ctx, "Adriatic / World Geometry")
    vk.CmdBindPipeline(cmd, .GRAPHICS, world_renderer.pipelines[ctx.pipeline_index])
    vk.CmdPushConstants(
        cmd,
        world_renderer.layout,
        {.VERTEX, .FRAGMENT},
        0,
        u32(size_of(ctx.world_push)),
        &ctx.world_push,
    )
    if len(world_renderer.vertices) > 0 {
        vk.CmdBindVertexBuffers(cmd, 0, 1, &ctx.buffer.handle, &ctx.offset)
        vk.CmdDraw(cmd, u32(len(world_renderer.vertices)), 1, 0, 0)
    }
    render_graph_stage_end(ctx)
}

render_graph_terrain :: proc(user_data: rawptr) {
    ctx := cast(^Render_Graph_Context)user_data
    cmd := ctx.pass.frame.command_buffer
    render_graph_stage_label(ctx, "Adriatic / Terrain Clipmap")
    vk.CmdBindPipeline(cmd, .GRAPHICS, world_renderer.pipelines[ctx.pipeline_index])
    vk.CmdPushConstants(
        cmd,
        world_renderer.layout,
        {.VERTEX, .FRAGMENT},
        0,
        u32(size_of(ctx.world_push)),
        &ctx.world_push,
    )
    vk.CmdBindIndexBuffer(cmd, world_renderer.clipmap_index.handle, 0, .UINT32)
    for level in 0 ..< terrain.CLIPMAP_LEVELS {
        level_buffer := &world_renderer.clipmap_vertex[ctx.pass.frame.frame_index][level]
        vk.CmdBindVertexBuffers(cmd, 0, 1, &level_buffer.handle, &ctx.offset)
        if level == 0 {
            vk.CmdDrawIndexed(cmd, world_renderer.clipmap_full_indices, 1, 0, 0, 0)
        } else {
            vk.CmdDrawIndexed(cmd, world_renderer.clipmap_ring_indices, 1, world_renderer.clipmap_ring_first, 0, 0)
        }
    }
    render_graph_stage_end(ctx)
}

adriatic_render_graph :: proc(graph: ^render_graph.Graph) -> bool {
    if graph == nil do return false
    render_graph.reset(graph)
    sky := render_graph.add_pass(graph, "sky", render_graph_sky)
    geometry := render_graph.add_pass(graph, "geometry", render_graph_geometry)
    terrain := render_graph.add_pass(graph, "terrain", render_graph_terrain)
    return(
        render_graph.depends_on(graph, geometry, sky) &&
        render_graph.depends_on(graph, terrain, geometry) \
    )
}
