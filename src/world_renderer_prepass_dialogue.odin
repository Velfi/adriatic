package main
import "core:math"
import "core:mem"

import dio "../packages/dio"
import story "../packages/story"
import third_person "../packages/third_person"
import vk "vendor:vulkan"
import canvas2d "zelda_engine:canvas2d"
import engine "zelda_engine:engine"

world_pre_pass :: proc(pass: ^canvas2d.World_Pass_Context, _: rawptr) {
    if !world_renderer.initialized && !world_renderer_create(pass.ctx) do return
    editor := world_renderer.editor
    if editor == nil do return
    frame_index := int(pass.frame.frame_index)
    world_prepare(editor, pass.frame.command_buffer, frame_index)
    if !world_dynamic_vertex_buffer_upload(frame_index) do return
    world_renderer.dynamic_shadow.frame_prepared = true
    if !world_renderer.dynamic_shadow.enabled do return
    // Build before the canvas begins its color rendering scope so the same
    // animated frame can be submitted to the independent depth-only pass.
    world_renderer.dynamic_shadow.anchor = dynamic_shadow_resolve_anchor(editor)
    dynamic_shadow_build_casters(editor)
    transform_scope := dio.flame_graph_begin(dio.flame_graph_current(), "shadow_transform")
    dynamic_shadow_update_transform(editor, frame_index)
    _ = dio.flame_graph_end(dio.flame_graph_current(), transform_scope)
    if len(world_renderer.shadow_vertices) > 0 {
        required := vk.DeviceSize(len(world_renderer.shadow_vertices) * size_of(World_Vertex))
        if !world_host_buffer_ensure(
            world_renderer.ctx,
            &world_renderer.shadow_vertex[frame_index],
            required,
            {.VERTEX_BUFFER},
            "world shadow vertex buffer",
        ) {
            return
        }
        upload_scope := dio.flame_graph_begin(dio.flame_graph_current(), "shadow_vertex_upload")
        mem.copy_non_overlapping(
            world_renderer.shadow_vertex[frame_index].mapped,
            raw_data(world_renderer.shadow_vertices[:]),
            int(required),
        )
        _ = dio.flame_graph_end(dio.flame_graph_current(), upload_scope)
    }
    render_scope := dio.flame_graph_begin(dio.flame_graph_current(), "shadow_render")
    dynamic_shadow_render(pass, frame_index)
    _ = dio.flame_graph_end(dio.flame_graph_current(), render_scope)
}

dialogue_portrait_mouse_model :: proc(editor: ^Editor, resident: story.Resident, player: bool) -> Mouse_Model {
    animation_time :=
        f32(math.floor(f64(editor.map_time * TOWN_MOUSE_PORTRAIT_ANIMATION_HZ))) / TOWN_MOUSE_PORTRAIT_ANIMATION_HZ
    idle := f32(math.sin(f64(animation_time * 2.1 + (player ? 0 : 1.7)))) * .025
    model := Mouse_Model {
        position = {0, idle, 0},
        rotation = math.PI,
        preview  = true,
    }
    if player {
        model.fur = editor.mouse_fur
        model.pattern = editor.mouse_pattern
        model.accessory = editor.mouse_headgear
        model.scarf_enabled = editor.mouse_scarf_enabled
        model.scarf_color = editor.mouse_scarf_color
        model.player_controlled = true
        return model
    }
    switch resident {
    case .Marta:
        model.build, model.snout_length = .88, 1.12
        model.accessory, model.fur, model.pattern = .Flower, .Chestnut, .Pale_Belly
    case .Gerta:
        model.build, model.snout_length = 1.16, .92
        model.accessory, model.accessory_side = .Flower, 1
        model.fur, model.pattern = .Silver, .Solid
    case .Niko:
        model.build, model.snout_length = 1.12, .94
        model.accessory, model.fur, model.pattern = .Acorn_Cap, .Chestnut, .Pale_Belly
    case .Iva:
        model.build, model.snout_length = .86, 1.16
        model.accessory, model.fur, model.pattern = .Flower, .Cream, .Piebald
        model.scarf_enabled, model.scarf_color = true, {177, 65, 73, 255}
    case .Bojan:
        model.build, model.snout_length = 1.22, .88
        model.accessory, model.fur, model.pattern = .Bottle_Cap, .Soot, .Solid
        model.scarf_enabled, model.scarf_color = true, {61, 112, 139, 255}
    case .Zora:
        model.build, model.snout_length = 1.18, 1.10
        model.fur, model.pattern = .Russet, .Piebald
        model.scarf_enabled, model.scarf_color = true, {205, 151, 52, 255}
    case .Vesna:
        model.build, model.snout_length = 1.08, 1.02
        model.accessory, model.fur, model.pattern = .Chef_Hat, .White, .Pale_Belly
    case .Petar:
        model.build, model.snout_length = .82, .90
        model.accessory, model.fur, model.pattern = .Goggles, .Chestnut, .Hooded
    case .Anica:
        model.build, model.snout_length = .96, 1.08
        model.accessory, model.fur, model.pattern = .Flower, .Silver, .Pale_Belly
        model.scarf_enabled, model.scarf_color = true, {73, 126, 132, 255}
    case .Toma:
        model.build, model.snout_length = 1.06, .96
        model.accessory, model.fur, model.pattern = .Paper_Boat, .Chestnut, .Hooded
        model.scarf_enabled, model.scarf_color = true, {45, 73, 104, 255}
    case .Lena:
        model.build, model.snout_length = .92, 1.10
        model.accessory, model.fur, model.pattern = .Paper_Boat, .Cream, .Piebald
        model.scarf_enabled, model.scarf_color = true, {154, 54, 52, 255}
    case .Mirna:
        model.build, model.snout_length = .90, 1.04
        model.accessory, model.fur, model.pattern = .Goggles, .Soot, .Piebald
        model.scarf_enabled, model.scarf_color = true, {77, 168, 151, 255}
    }
    return model
}

world_dialogue_portrait_model_cached :: proc(editor: ^Editor, model: Mouse_Model, portrait_index: int) {
    if portrait_index < 0 || portrait_index >= len(world_renderer.dialogue_portrait_geometry_cache) {
        world_mouse_model(editor, model)
        return
    }
    entry := &world_renderer.dialogue_portrait_geometry_cache[portrait_index]
    if entry.valid && entry.model == model {
        append(&world_renderer.vertices, ..entry.vertices[:])
        return
    }
    first := len(world_renderer.vertices)
    world_mouse_model(editor, model)
    clear(&entry.vertices)
    if first < len(world_renderer.vertices) {
        append(&entry.vertices, ..world_renderer.vertices[first:])
    }
    entry.valid = true
    entry.model = model
}

dialogue_portrait_world_push :: proc(editor: ^Editor, aspect: f32, player: bool) -> World_Push {
    target := third_person.Vec3{0, .62, 0}
    // Keep the expressive edge bias without letting ears, paws, or whiskers
    // touch the narrow portrait viewport at the reference aspect ratio.
    camera_offset := third_person.Vec3{player ? f32(-.03) : f32(.03), .10, -1.62}
    pose := third_person.camera_near(target, camera_offset)
    camera := perspective_camera(pose, 1.72)
    sky := atmosphere_sky(editor)
    return {
        camera_position = {camera.position.x, camera.position.y, camera.position.z, .04},
        camera_right = {camera.right.x, camera.right.y, camera.right.z, 12},
        camera_up = {camera.up.x, camera.up.y, camera.up.z, 0},
        camera_forward = {camera.forward.x, camera.forward.y, camera.forward.z, 0},
        projection = {camera.focal_length, max(aspect, f32(.1)), 40, 80},
        fog_color = world_color({16, 43, 55, 255}),
        water = {sky.cloud_time_seconds, 0, 0, 0},
        sun = {-.42, .78, -.46, 1.35},
    }
}

dialogue_portrait_backdrop :: proc(aspect: f32) {
    // This quad is drawn after the world scene but before the portrait mesh.
    // Its alpha therefore dims the scene behind the mouse without tinting the
    // model itself.
    half_height := f32(1.55)
    half_width := half_height * max(aspect, f32(.1))
    z := f32(.38)
    color := canvas2d.Color{18, 15, 12, 176}
    a := third_person.Vec3{-half_width, -.35, z}
    b := third_person.Vec3{-half_width, -.35 + half_height * 2, z}
    c := third_person.Vec3{half_width, -.35 + half_height * 2, z}
    d := third_person.Vec3{half_width, -.35, z}
    world_quad(a, b, c, d, color)
    world_quad(d, c, b, a, color)
}

dialogue_portrait_render :: proc(
    pass: ^canvas2d.World_Pass_Context,
    buffer: ^engine.Vk_Buffer,
    pipeline_index: int,
    editor: ^Editor,
) {
    if editor == nil || !editor.attendant_dialogue_open do return
    logical_w, logical_h := pass.logical_extent[0], pass.logical_extent[1]
    if logical_w <= 0 || logical_h <= 0 do return
    layout := dialogue_tv_layout(logical_w, logical_h)
    cards := [2]canvas2d.Rectangle{layout.player_card, layout.npc_card}
    players := [2]bool{true, false}
    main_count := len(world_renderer.vertices)
    model_firsts, model_counts: [2]int
    for player, portrait_index in players {
        model_firsts[portrait_index] = len(world_renderer.vertices)
        world_dialogue_portrait_model_cached(
            editor,
            dialogue_portrait_mouse_model(editor, editor.dialogue_resident, player),
            portrait_index,
        )
        model_counts[portrait_index] = len(world_renderer.vertices) - model_firsts[portrait_index]
    }
    portrait_count := len(world_renderer.vertices) - main_count
    required_size := vk.DeviceSize(len(world_renderer.vertices) * size_of(World_Vertex))
    if portrait_count <= 0 || required_size > buffer.size {
        resize(&world_renderer.vertices, main_count)
        return
    }
    destination := cast(rawptr)(cast(uintptr)buffer.mapped + uintptr(main_count * size_of(World_Vertex)))
    mem.copy_non_overlapping(
        destination,
        raw_data(world_renderer.vertices[main_count:]),
        portrait_count * size_of(World_Vertex),
    )
    cmd := pass.frame.command_buffer
    vk.CmdBindPipeline(cmd, .GRAPHICS, world_renderer.pipelines[pipeline_index])
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
        &world_renderer.dynamic_shadow.descriptors[pass.frame.frame_index],
        0,
        nil,
    )
    offset := vk.DeviceSize(0)
    vk.CmdBindVertexBuffers(cmd, 0, 1, &buffer.handle, &offset)
    sx := f32(pass.framebuffer_extent.width) / f32(logical_w)
    sy := f32(pass.framebuffer_extent.height) / f32(logical_h)
    for card, portrait_index in cards {
        inset_x, inset_top, inset_bottom := 10 * layout.scale, 54 * layout.scale, 78 * layout.scale
        card_x := max(i32(card.x * sx), 0)
        card_y := max(i32(card.y * sy), 0)
        card_w := max(u32(card.width * sx), 1)
        card_h := max(u32(card.height * sy), 1)
        x := max(i32((card.x + inset_x) * sx), 0)
        y := max(i32((card.y + inset_top) * sy), 0)
        w := max(u32((card.width - inset_x * 2) * sx), 1)
        h := max(u32((card.height - inset_top - inset_bottom) * sy), 1)
        card_rect := vk.Rect2D {
            offset = {card_x, card_y},
            extent = {card_w, card_h},
        }
        view_rect := vk.Rect2D {
            offset = {x, y},
            extent = {w, h},
        }
        clear_attachment := vk.ClearAttachment {
            aspectMask = {.DEPTH},
            clearValue = {depthStencil = {depth = 1}},
        }
        clear_rect := vk.ClearRect {
            rect           = card_rect,
            baseArrayLayer = 0,
            layerCount     = 1,
        }
        vk.CmdClearAttachments(cmd, 1, &clear_attachment, 1, &clear_rect)
        card_viewport := vk.Viewport {
            x        = f32(card_x),
            y        = f32(card_y),
            width    = f32(card_w),
            height   = f32(card_h),
            minDepth = 0,
            maxDepth = 1,
        }
        vk.CmdSetViewport(cmd, 0, 1, &card_viewport)
        vk.CmdSetScissor(cmd, 0, 1, &card_rect)
        viewport := vk.Viewport {
            x        = f32(x),
            y        = f32(y),
            width    = f32(w),
            height   = f32(h),
            minDepth = 0,
            maxDepth = 1,
        }
        vk.CmdSetViewport(cmd, 0, 1, &viewport)
        vk.CmdSetScissor(cmd, 0, 1, &view_rect)
        push := dialogue_portrait_world_push(editor, f32(w) / f32(h), players[portrait_index])
        vk.CmdPushConstants(cmd, world_renderer.layout, {.VERTEX, .FRAGMENT}, 0, u32(size_of(push)), &push)
        vk.CmdDraw(cmd, u32(model_counts[portrait_index]), 1, u32(model_firsts[portrait_index]), 0)
    }
    resize(&world_renderer.vertices, main_count)
}

world_camera_focal_length :: proc(editor: ^Editor) -> f32 {
    if editor == nil do return 1.35
    focal_length :=
        editor.vehicle_showcase_scene ? VEHICLE_SHOWCASE_FOCAL_LENGTH : (editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35)
    if editor.cinematic_playback.script != nil || editor.active_lab_scene == "mouse-theater" {
        focal_length = max(editor.cinematic_focal_length, f32(.01))
    }
    return focal_length
}
