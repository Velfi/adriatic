package main

import atmosphere "../packages/atmosphere"
import render_graph "../packages/render_graph"
import terrain "../packages/terrain"
import vk "vendor:vulkan"
import canvas2d "zelda_engine:canvas2d"
import engine "zelda_engine:engine"

Render_Graph_Context :: struct {
    pass:                     ^canvas2d.World_Pass_Context,
    buffer:                   ^engine.Vk_Buffer,
    static_vertex_buffer:     ^engine.Vk_Buffer,
    static_index_buffer:      ^engine.Vk_Buffer,
    static_indirect_buffer:   ^engine.Vk_Buffer,
    road_buffer:              ^engine.Vk_Buffer,
    road_indirect_buffer:     ^engine.Vk_Buffer,
    foliage_buffer:           ^engine.Vk_Buffer,
    bougainvillea_buffer:     ^engine.Vk_Buffer,
    grass_instance_buffer:    ^engine.Vk_Buffer,
    instance_vertex_buffer:   ^engine.Vk_Buffer,
    instance_index_buffer:    ^engine.Vk_Buffer,
    instance_data_buffer:     ^engine.Vk_Buffer,
    wing_trail_vertex_buffer: ^engine.Vk_Buffer,
    wing_trail_index_buffer:  ^engine.Vk_Buffer,
    offset:                   vk.DeviceSize,
    pipeline_index:           int,
    world_push:               World_Push,
    sky_push:                 Sky_Push,
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
    vk.CmdBindDescriptorSets(
        cmd,
        .GRAPHICS,
        world_renderer.layout,
        0,
        1,
        &world_renderer.vehicle_paint_descriptor,
        0,
        nil,
    )
    vk.CmdBindDescriptorSets(
        cmd,
        .GRAPHICS,
        world_renderer.layout,
        1,
        1,
        &world_renderer.dynamic_shadow.descriptors[ctx.pass.frame.frame_index],
        0,
        nil,
    )
    vk.CmdPushConstants(
        cmd,
        world_renderer.layout,
        {.VERTEX, .FRAGMENT},
        0,
        u32(size_of(ctx.world_push)),
        &ctx.world_push,
    )
    world_vertex_count := len(world_renderer.vertices) - world_renderer.late_transparent_count
    if world_vertex_count > 0 {
        vk.CmdBindVertexBuffers(cmd, 0, 1, &ctx.buffer.handle, &ctx.offset)
        vk.CmdDraw(cmd, u32(world_vertex_count), 1, 0, 0)
    }
    if len(world_renderer.static_draw_commands) > 0 {
        vk.CmdBindVertexBuffers(cmd, 0, 1, &ctx.static_vertex_buffer.handle, &ctx.offset)
        vk.CmdBindIndexBuffer(cmd, ctx.static_index_buffer.handle, 0, .UINT32)
        for command_index in 0 ..< len(world_renderer.static_draw_commands) {
            vk.CmdDrawIndexedIndirect(
                cmd,
                ctx.static_indirect_buffer.handle,
                vk.DeviceSize(command_index * size_of(vk.DrawIndexedIndirectCommand)),
                1,
                u32(size_of(vk.DrawIndexedIndirectCommand)),
            )
        }
    }
    if len(world_renderer.instance_flattened) > 0 {
        vk.CmdBindPipeline(cmd, .GRAPHICS, world_renderer.instance_pipelines[ctx.pipeline_index])
        buffers := [2]vk.Buffer{ctx.instance_vertex_buffer.handle, ctx.instance_data_buffer.handle}
        offsets := [2]vk.DeviceSize{0, 0}
        vk.CmdBindVertexBuffers(cmd, 0, 2, raw_data(buffers[:]), raw_data(offsets[:]))
        vk.CmdBindIndexBuffer(cmd, ctx.instance_index_buffer.handle, 0, .UINT32)
        for mesh in world_renderer.instance_meshes {
            if len(mesh.instances) == 0 do continue
            vk.CmdDrawIndexed(
                cmd,
                mesh.index_count,
                u32(len(mesh.instances)),
                mesh.first_index,
                i32(mesh.first_vertex),
                mesh.first_instance,
            )
        }
        vk.CmdBindPipeline(cmd, .GRAPHICS, world_renderer.pipelines[ctx.pipeline_index])
    }
    if len(world_renderer.wing_trail_optimized_indices) > 0 {
        vk.CmdBindVertexBuffers(cmd, 0, 1, &ctx.wing_trail_vertex_buffer.handle, &ctx.offset)
        vk.CmdBindIndexBuffer(cmd, ctx.wing_trail_index_buffer.handle, 0, .UINT16)
        vk.CmdDrawIndexed(cmd, u32(len(world_renderer.wing_trail_optimized_indices)), 1, 0, 0, 0)
    }
    render_graph_stage_end(ctx)
}

render_graph_foliage :: proc(user_data: rawptr) {
    ctx := cast(^Render_Graph_Context)user_data
    if len(world_renderer.foliage_vertices) <= 0 &&
       len(world_renderer.bougainvillea_vertices) <= 0 &&
       len(world_renderer.terrain_particle_vertices) <= 0 &&
       len(world_renderer.bougainvillea_instances) <= 0 &&
       len(world_renderer.grass_instances) <= 0 &&
       len(world_renderer.wildflower_instances) <= 0 &&
       len(world_renderer.marsh_instances) <= 0 {
        return
    }
    cmd := ctx.pass.frame.command_buffer
    render_graph_stage_label(ctx, "Adriatic / Foliage Atlas")
    vk.CmdBindPipeline(cmd, .GRAPHICS, world_renderer.foliage_pipelines[ctx.pipeline_index])
    vk.CmdBindDescriptorSets(
        cmd,
        .GRAPHICS,
        world_renderer.foliage_layout,
        1,
        1,
        &world_renderer.dynamic_shadow.descriptors[ctx.pass.frame.frame_index],
        0,
        nil,
    )
    vk.CmdPushConstants(
        cmd,
        world_renderer.foliage_layout,
        {.VERTEX, .FRAGMENT},
        0,
        u32(size_of(ctx.world_push)),
        &ctx.world_push,
    )
    vk.CmdBindVertexBuffers(cmd, 0, 1, &ctx.foliage_buffer.handle, &ctx.offset)
    if len(world_renderer.foliage_vertices) > 0 {
        vk.CmdBindDescriptorSets(
            cmd,
            .GRAPHICS,
            world_renderer.foliage_layout,
            0,
            1,
            &world_renderer.foliage_descriptor,
            0,
            nil,
        )
        vk.CmdDraw(cmd, u32(len(world_renderer.foliage_vertices)), 1, 0, 0)
    }
    if len(world_renderer.bougainvillea_vertices) > 0 {
        vk.CmdBindDescriptorSets(
            cmd,
            .GRAPHICS,
            world_renderer.foliage_layout,
            0,
            1,
            &world_renderer.bougainvillea_descriptor,
            0,
            nil,
        )
        vk.CmdDraw(
            cmd,
            u32(len(world_renderer.bougainvillea_vertices)),
            1,
            u32(len(world_renderer.foliage_vertices)),
            0,
        )
    }
    if len(world_renderer.terrain_particle_vertices) > 0 {
        vk.CmdBindDescriptorSets(
            cmd,
            .GRAPHICS,
            world_renderer.foliage_layout,
            0,
            1,
            &world_renderer.terrain_particle_descriptor,
            0,
            nil,
        )
        vk.CmdDraw(
            cmd,
            u32(len(world_renderer.terrain_particle_vertices)),
            1,
            u32(len(world_renderer.foliage_vertices) + len(world_renderer.bougainvillea_vertices)),
            0,
        )
    }
    if len(world_renderer.bougainvillea_instances) > 0 {
        vk.CmdBindPipeline(cmd, .GRAPHICS, world_renderer.bougainvillea_pipelines[ctx.pipeline_index])
        vk.CmdBindVertexBuffers(cmd, 0, 1, &ctx.bougainvillea_buffer.handle, &ctx.offset)
        vk.CmdBindDescriptorSets(
            cmd,
            .GRAPHICS,
            world_renderer.foliage_layout,
            0,
            1,
            &world_renderer.bougainvillea_descriptor,
            0,
            nil,
        )
        vk.CmdDraw(cmd, 24, u32(len(world_renderer.bougainvillea_instances)), 0, 0)
    }
    if len(world_renderer.grass_instances) > 0 {
        vk.CmdBindPipeline(cmd, .GRAPHICS, world_renderer.grass_pipelines[ctx.pipeline_index])
        vk.CmdBindVertexBuffers(cmd, 0, 1, &ctx.grass_instance_buffer.handle, &ctx.offset)
        vk.CmdBindDescriptorSets(
            cmd,
            .GRAPHICS,
            world_renderer.foliage_layout,
            0,
            1,
            &world_renderer.grass_descriptor,
            0,
            nil,
        )
        vk.CmdDraw(cmd, 6, u32(len(world_renderer.grass_instances)), 0, 0)
    }
    if len(world_renderer.wildflower_instances) > 0 {
        vk.CmdBindPipeline(cmd, .GRAPHICS, world_renderer.grass_pipelines[ctx.pipeline_index])
        vk.CmdBindVertexBuffers(cmd, 0, 1, &ctx.grass_instance_buffer.handle, &ctx.offset)
        vk.CmdBindDescriptorSets(
            cmd,
            .GRAPHICS,
            world_renderer.foliage_layout,
            0,
            1,
            &world_renderer.wildflower_descriptor,
            0,
            nil,
        )
        vk.CmdDraw(cmd, 6, u32(len(world_renderer.wildflower_instances)), 0, u32(len(world_renderer.grass_instances)))
    }
    if len(world_renderer.marsh_instances) > 0 {
        vk.CmdBindPipeline(cmd, .GRAPHICS, world_renderer.grass_pipelines[ctx.pipeline_index])
        vk.CmdBindVertexBuffers(cmd, 0, 1, &ctx.grass_instance_buffer.handle, &ctx.offset)
        vk.CmdBindDescriptorSets(
            cmd,
            .GRAPHICS,
            world_renderer.foliage_layout,
            0,
            1,
            &world_renderer.marsh_descriptor,
            0,
            nil,
        )
        first := len(world_renderer.grass_instances) + len(world_renderer.wildflower_instances)
        vk.CmdDraw(cmd, 6, u32(len(world_renderer.marsh_instances)), 0, u32(first))
    }
    render_graph_stage_end(ctx)
}

render_graph_terrain :: proc(user_data: rawptr) {
    ctx := cast(^Render_Graph_Context)user_data
    if world_renderer.editor != nil &&
       (world_renderer.editor.pause_screen == .Customization ||
               world_renderer.editor.vehicle_showcase_scene ||
               world_renderer.editor.wildflower_lab_scene ||
               lab_scene_replaces_world(world_renderer.editor)) {
        return
    }
    cmd := ctx.pass.frame.command_buffer
    render_graph_stage_label(ctx, "Adriatic / Terrain Clipmap")
    vk.CmdBindPipeline(cmd, .GRAPHICS, world_renderer.pipelines[ctx.pipeline_index])
    vk.CmdBindDescriptorSets(
        cmd,
        .GRAPHICS,
        world_renderer.layout,
        0,
        1,
        &world_renderer.vehicle_paint_descriptor,
        0,
        nil,
    )
    vk.CmdBindDescriptorSets(
        cmd,
        .GRAPHICS,
        world_renderer.layout,
        1,
        1,
        &world_renderer.dynamic_shadow.descriptors[ctx.pass.frame.frame_index],
        0,
        nil,
    )
    vk.CmdPushConstants(
        cmd,
        world_renderer.layout,
        {.VERTEX, .FRAGMENT},
        0,
        u32(size_of(ctx.world_push)),
        &ctx.world_push,
    )
    first_level := world_renderer.clipmap_first_level
    for level in first_level ..< terrain.CLIPMAP_LEVELS {
        level_buffer := &world_renderer.clipmap_vertex[ctx.pass.frame.frame_index][level]
        vk.CmdBindVertexBuffers(cmd, 0, 1, &level_buffer.handle, &ctx.offset)
        if level == first_level {
            index_buffer := first_level == 0 ? &world_renderer.clipmap_index : &world_renderer.clipmap_outer_full_index
            index_count := first_level == 0 ? world_renderer.clipmap_full_indices : world_renderer.clipmap_outer_full_indices
            vk.CmdBindIndexBuffer(cmd, index_buffer.handle, 0, .UINT32)
            vk.CmdDrawIndexed(cmd, index_count, 1, 0, 0, 0)
        } else {
            variant := clipmap_ring_variant(int(ctx.pass.frame.frame_index), level)
            ring := &world_renderer.clipmap_ring_index[variant[1]][variant[0]]
            index_count := world_renderer.clipmap_ring_indices
            // Level 1 now uses its native two-metre grid and therefore the
            // ordinary 2× hole beneath the half-metre inner patch. The 4×
            // coverage jump occurs between levels 1 and 2, safely farther
            // from the camera, and uses the narrower sparse-ring hole.
            if level == 2 {
                ring = &world_renderer.clipmap_inner_ring_index[variant[1]][variant[0]]
                index_count = world_renderer.clipmap_inner_ring_indices
            }
            vk.CmdBindIndexBuffer(cmd, ring.handle, 0, .UINT32)
            vk.CmdDrawIndexed(cmd, index_count, 1, 0, 0, 0)
        }
    }
    render_graph_stage_end(ctx)
}

render_graph_roads :: proc(user_data: rawptr) {
    ctx := cast(^Render_Graph_Context)user_data
    if len(world_renderer.road_draw_commands) <= 0 do return
    cmd := ctx.pass.frame.command_buffer
    render_graph_stage_label(ctx, "Adriatic / Roads")
    vk.CmdBindDescriptorSets(
        cmd,
        .GRAPHICS,
        world_renderer.layout,
        0,
        1,
        &world_renderer.vehicle_paint_descriptor,
        0,
        nil,
    )
    vk.CmdBindDescriptorSets(
        cmd,
        .GRAPHICS,
        world_renderer.layout,
        1,
        1,
        &world_renderer.dynamic_shadow.descriptors[ctx.pass.frame.frame_index],
        0,
        nil,
    )
    vk.CmdBindPipeline(cmd, .GRAPHICS, world_renderer.road_pipelines[ctx.pipeline_index])
    vk.CmdPushConstants(
        cmd,
        world_renderer.layout,
        {.VERTEX, .FRAGMENT},
        0,
        u32(size_of(ctx.world_push)),
        &ctx.world_push,
    )
    vk.CmdBindVertexBuffers(cmd, 0, 1, &ctx.road_buffer.handle, &ctx.offset)
    for command_index in 0 ..< len(world_renderer.road_draw_commands) {
        vk.CmdDrawIndirect(
            cmd,
            ctx.road_indirect_buffer.handle,
            vk.DeviceSize(command_index * size_of(vk.DrawIndirectCommand)),
            1,
            u32(size_of(vk.DrawIndirectCommand)),
        )
    }
    render_graph_stage_end(ctx)
}

render_graph_transparent :: proc(user_data: rawptr) {
    ctx := cast(^Render_Graph_Context)user_data
    if world_renderer.late_transparent_count <= 0 do return
    cmd := ctx.pass.frame.command_buffer
    render_graph_stage_label(ctx, "Adriatic / Transparent World Effects")
    vk.CmdBindPipeline(cmd, .GRAPHICS, world_renderer.transparent_pipelines[ctx.pipeline_index])
    vk.CmdBindDescriptorSets(
        cmd,
        .GRAPHICS,
        world_renderer.layout,
        0,
        1,
        &world_renderer.vehicle_paint_descriptor,
        0,
        nil,
    )
    vk.CmdBindDescriptorSets(
        cmd,
        .GRAPHICS,
        world_renderer.layout,
        1,
        1,
        &world_renderer.dynamic_shadow.descriptors[ctx.pass.frame.frame_index],
        0,
        nil,
    )
    vk.CmdPushConstants(
        cmd,
        world_renderer.layout,
        {.VERTEX, .FRAGMENT},
        0,
        u32(size_of(ctx.world_push)),
        &ctx.world_push,
    )
    vk.CmdBindVertexBuffers(cmd, 0, 1, &ctx.buffer.handle, &ctx.offset)
    vk.CmdDraw(cmd, u32(world_renderer.late_transparent_count), 1, u32(world_renderer.late_transparent_first), 0)
    render_graph_stage_end(ctx)
}

adriatic_render_graph :: proc(graph: ^render_graph.Graph) -> bool {
    if graph == nil do return false
    render_graph.reset(graph)
    sky := render_graph.add_pass(graph, "sky", render_graph_sky)
    geometry := render_graph.add_pass(graph, "geometry", render_graph_geometry)
    foliage := render_graph.add_pass(graph, "foliage", render_graph_foliage)
    terrain := render_graph.add_pass(graph, "terrain", render_graph_terrain)
    roads := render_graph.add_pass(graph, "roads", render_graph_roads)
    transparent := render_graph.add_pass(graph, "transparent", render_graph_transparent)
    return(
        render_graph.depends_on(graph, terrain, sky) &&
        render_graph.depends_on(graph, geometry, terrain) &&
        render_graph.depends_on(graph, foliage, geometry) &&
        render_graph.depends_on(graph, roads, foliage) &&
        render_graph.depends_on(graph, transparent, roads) \
    )
}

world_bomber_pip_render :: proc(ctx: ^Render_Graph_Context) {
    if ctx == nil || world_renderer.editor == nil do return
    editor := world_renderer.editor
    if !editor.in_map || !driving_aircraft(editor) || !editor.bomber_mode do return
    tracked := bomber_pip_drop(editor)
    if tracked == nil do return

    framebuffer_width := f32(ctx.pass.framebuffer_extent.width)
    framebuffer_height := f32(ctx.pass.framebuffer_extent.height)
    logical_width := max(f32(canvas2d.GetScreenWidth()), f32(1))
    logical_height := max(f32(canvas2d.GetScreenHeight()), f32(1))
    scale_x := framebuffer_width / logical_width
    scale_y := framebuffer_height / logical_height
    logical_rect := bomber_pip_layout(logical_width, logical_height)
    pip_width := logical_rect.width * scale_x
    pip_height := logical_rect.height * scale_y
    rect := vk.Rect2D {
        offset = {i32(max(logical_rect.x * scale_x, f32(0))), i32(max(logical_rect.y * scale_y, f32(0)))},
        extent = {u32(max(pip_width, f32(1))), u32(max(pip_height, f32(1)))},
    }
    if u32(rect.offset.x) + rect.extent.width > ctx.pass.framebuffer_extent.width {
        rect.extent.width = ctx.pass.framebuffer_extent.width - u32(rect.offset.x)
    }
    if u32(rect.offset.y) + rect.extent.height > ctx.pass.framebuffer_extent.height {
        rect.extent.height = ctx.pass.framebuffer_extent.height - u32(rect.offset.y)
    }
    clear_attachment := vk.ClearAttachment {
        aspectMask = {.DEPTH},
        clearValue = {depthStencil = {depth = 1}},
    }
    clear_rect := vk.ClearRect {
        rect           = rect,
        baseArrayLayer = 0,
        layerCount     = 1,
    }
    vk.CmdClearAttachments(ctx.pass.frame.command_buffer, 1, &clear_attachment, 1, &clear_rect)
    viewport := vk.Viewport {
        x        = f32(rect.offset.x),
        y        = f32(rect.offset.y),
        width    = f32(rect.extent.width),
        height   = f32(rect.extent.height),
        minDepth = 0,
        maxDepth = 1,
    }
    vk.CmdSetViewport(ctx.pass.frame.command_buffer, 0, 1, &viewport)
    vk.CmdSetScissor(ctx.pass.frame.command_buffer, 0, 1, &rect)

    pose := editor.bomber_pip_valid ? editor.bomber_pip_pose : bomber_pip_camera_pose(editor, tracked)
    camera := perspective_camera(pose, 1.55)
    sky := atmosphere_sky(editor)
    ctx.world_push.camera_position = {
        camera.position.x,
        camera.position.y,
        camera.position.z,
        world_camera_near_clip(editor),
    }
    ctx.world_push.camera_right = {camera.right.x, camera.right.y, camera.right.z, WORLD_FAR_CLIP}
    ctx.world_push.camera_up = {camera.up.x, camera.up.y, camera.up.z, 0}
    ctx.world_push.camera_forward = {camera.forward.x, camera.forward.y, camera.forward.z, 0}
    ctx.world_push.projection = {
        camera.focal_length,
        f32(rect.extent.width) / f32(max(rect.extent.height, 1)),
        WORLD_FOG_START,
        WORLD_FOG_END,
    }
    ctx.sky_push.camera_right = {
        camera.right.x,
        camera.right.y,
        camera.right.z,
        f32(rect.extent.width) / f32(max(rect.extent.height, 1)),
    }
    ctx.sky_push.camera_up = {camera.up.x, camera.up.y, camera.up.z, camera.focal_length}
    ctx.sky_push.camera_forward = {camera.forward.x, camera.forward.y, camera.forward.z, 0}
    ctx.sky_push.sun_direction = {
        sky.sun_direction[0],
        sky.sun_direction[1],
        sky.sun_direction[2],
        f32(sky.cloud_seed),
    }
    _ = render_graph.execute(&world_render_graph, ctx)

    full_viewport := vk.Viewport {
        width    = framebuffer_width,
        height   = framebuffer_height,
        minDepth = 0,
        maxDepth = 1,
    }
    full_scissor := vk.Rect2D {
        extent = ctx.pass.framebuffer_extent,
    }
    vk.CmdSetViewport(ctx.pass.frame.command_buffer, 0, 1, &full_viewport)
    vk.CmdSetScissor(ctx.pass.frame.command_buffer, 0, 1, &full_scissor)
}
