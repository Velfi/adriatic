package main
import "core:math"
import "core:mem"

import atmosphere "../packages/atmosphere"
import cinematic "../packages/cinematic"
import render_graph "../packages/render_graph"
import roads "../packages/roads"
import terrain "../packages/terrain"
import vk "vendor:vulkan"
import canvas2d "zelda_engine:canvas2d"
import engine "zelda_engine:engine"
import render3d "zelda_engine:render3d"
import resources "zelda_engine:render_resources"

world_pass :: proc(pass: ^canvas2d.World_Pass_Context, _: rawptr) {
    if !world_renderer.initialized do return
    editor := world_renderer.editor
    if editor == nil do return
    if !world_renderer.dynamic_shadow.frame_prepared {
        world_prepare(editor, pass.frame.command_buffer, int(pass.frame.frame_index))
    }
    world_renderer.dynamic_shadow.frame_prepared = false
    focal_length := world_camera_focal_length(editor)
    if !editor.vehicle_showcase_scene && (!lab_scene_replaces_world(editor) || editor.lab_flat_terrain.enabled) {
        clipmap_update(editor, int(pass.frame.frame_index), i32(pass.framebuffer_extent.height), focal_length)
    }
    frame_index := int(pass.frame.frame_index)
    world_instances_flatten()
    if !world_frame_geometry_buffers_ensure(frame_index) do return
    if !world_dynamic_vertex_buffer_upload(frame_index) do return
    buffer := &world_renderer.vertex[frame_index]
    static_vertex_buffer := &world_renderer.static_vertex[frame_index]
    static_index_buffer := &world_renderer.static_index[frame_index]
    static_indirect_buffer := &world_renderer.static_indirect[frame_index]
    road_buffer := &world_renderer.road_vertex[frame_index]
    road_indirect_buffer := &world_renderer.road_indirect[frame_index]
    foliage_buffer := &world_renderer.foliage_vertex[frame_index]
    bougainvillea_buffer := &world_renderer.bougainvillea_instance[frame_index]
    grass_instance_buffer := &world_renderer.grass_instance[frame_index]
    instance_vertex_buffer := &world_renderer.instance_vertex[frame_index]
    plant_vertex_buffer := &world_renderer.plant_vertex[frame_index]
    instance_index_buffer := &world_renderer.instance_index[frame_index]
    instance_data_buffer := &world_renderer.instance_data[frame_index]
    wing_trail_vertex_buffer := &world_renderer.wing_trail_vertex[frame_index]
    wing_trail_index_buffer := &world_renderer.wing_trail_index[frame_index]
    static_upload_required :=
        world_renderer.retained_static_uploaded_revision[frame_index] != world_renderer.retained_static_revision
    if static_upload_required && len(world_renderer.static_vertices) > 0 {
        mem.copy_non_overlapping(
            static_vertex_buffer.mapped,
            raw_data(world_renderer.static_vertices[:]),
            len(world_renderer.static_vertices) * size_of(World_Vertex),
        )
        world_renderer.static_bytes_uploaded += u64(len(world_renderer.static_vertices) * size_of(World_Vertex))
    }
    if static_upload_required && len(world_renderer.static_indices) > 0 {
        mem.copy_non_overlapping(
            static_index_buffer.mapped,
            raw_data(world_renderer.static_indices[:]),
            len(world_renderer.static_indices) * size_of(u32),
        )
        world_renderer.static_bytes_uploaded += u64(len(world_renderer.static_indices) * size_of(u32))
    }
    if static_upload_required {
        world_renderer.retained_static_uploaded_revision[frame_index] = world_renderer.retained_static_revision
    }
    if len(world_renderer.static_draw_commands) > 0 {
        mem.copy_non_overlapping(
            static_indirect_buffer.mapped,
            raw_data(world_renderer.static_draw_commands[:]),
            len(world_renderer.static_draw_commands) * size_of(vk.DrawIndexedIndirectCommand),
        )
    }
    road_upload_required :=
        world_renderer.road_geometry_uploaded_revision[frame_index] != world_renderer.road_geometry_gpu_revision
    if road_upload_required && len(world_renderer.road_geometry_cache) > 0 {
        mem.copy_non_overlapping(
            road_buffer.mapped,
            raw_data(world_renderer.road_geometry_cache[:]),
            len(world_renderer.road_geometry_cache) * size_of(World_Vertex),
        )
        world_renderer.static_bytes_uploaded += u64(len(world_renderer.road_geometry_cache) * size_of(World_Vertex))
    }
    if road_upload_required {
        world_renderer.road_geometry_uploaded_revision[frame_index] = world_renderer.road_geometry_gpu_revision
    }
    if len(world_renderer.road_draw_commands) > 0 {
        mem.copy_non_overlapping(
            road_indirect_buffer.mapped,
            raw_data(world_renderer.road_draw_commands[:]),
            len(world_renderer.road_draw_commands) * size_of(vk.DrawIndirectCommand),
        )
    }
    if len(world_renderer.foliage_vertices) > 0 {
        mem.copy_non_overlapping(
            foliage_buffer.mapped,
            raw_data(world_renderer.foliage_vertices[:]),
            len(world_renderer.foliage_vertices) * size_of(Foliage_Vertex),
        )
    }
    if len(world_renderer.bougainvillea_vertices) > 0 {
        destination := cast(rawptr)(cast(uintptr)foliage_buffer.mapped +
            uintptr(len(world_renderer.foliage_vertices) * size_of(Foliage_Vertex)))
        mem.copy_non_overlapping(
            destination,
            raw_data(world_renderer.bougainvillea_vertices[:]),
            len(world_renderer.bougainvillea_vertices) * size_of(Foliage_Vertex),
        )
    }
    if len(world_renderer.terrain_particle_vertices) > 0 {
        destination := cast(rawptr)(cast(uintptr)foliage_buffer.mapped +
            uintptr(
                (len(world_renderer.foliage_vertices) + len(world_renderer.bougainvillea_vertices)) *
                size_of(Foliage_Vertex),
            ))
        mem.copy_non_overlapping(
            destination,
            raw_data(world_renderer.terrain_particle_vertices[:]),
            len(world_renderer.terrain_particle_vertices) * size_of(Foliage_Vertex),
        )
    }
    if len(world_renderer.bougainvillea_instances) > 0 {
        mem.copy_non_overlapping(
            bougainvillea_buffer.mapped,
            raw_data(world_renderer.bougainvillea_instances[:]),
            len(world_renderer.bougainvillea_instances) * size_of(Bougainvillea_Instance),
        )
    }
    if len(world_renderer.grass_instances) > 0 {
        mem.copy_non_overlapping(
            grass_instance_buffer.mapped,
            raw_data(world_renderer.grass_instances[:]),
            len(world_renderer.grass_instances) * size_of(Grass_Instance),
        )
    }
    if len(world_renderer.wildflower_instances) > 0 {
        destination := cast(rawptr)(cast(uintptr)grass_instance_buffer.mapped +
            uintptr(len(world_renderer.grass_instances) * size_of(Grass_Instance)))
        mem.copy_non_overlapping(
            destination,
            raw_data(world_renderer.wildflower_instances[:]),
            len(world_renderer.wildflower_instances) * size_of(Grass_Instance),
        )
    }
    if len(world_renderer.marsh_instances) > 0 {
        first := len(world_renderer.grass_instances) + len(world_renderer.wildflower_instances)
        destination := cast(rawptr)(cast(uintptr)grass_instance_buffer.mapped +
            uintptr(first * size_of(Grass_Instance)))
        mem.copy_non_overlapping(
            destination,
            raw_data(world_renderer.marsh_instances[:]),
            len(world_renderer.marsh_instances) * size_of(Grass_Instance),
        )
    }
    if len(world_renderer.instance_vertices) > 0 {
        mem.copy_non_overlapping(
            instance_vertex_buffer.mapped,
            raw_data(world_renderer.instance_vertices[:]),
            len(world_renderer.instance_vertices) * size_of(World_Vertex),
        )
    }
    if len(world_renderer.plant_vertices) > 0 {
        mem.copy_non_overlapping(
            plant_vertex_buffer.mapped,
            raw_data(world_renderer.plant_vertices[:]),
            len(world_renderer.plant_vertices) * size_of(Plant_Vertex),
        )
    }
    if len(world_renderer.instance_indices) > 0 {
        mem.copy_non_overlapping(
            instance_index_buffer.mapped,
            raw_data(world_renderer.instance_indices[:]),
            len(world_renderer.instance_indices) * size_of(u32),
        )
    }
    if len(world_renderer.instance_flattened) > 0 {
        mem.copy_non_overlapping(
            instance_data_buffer.mapped,
            raw_data(world_renderer.instance_flattened[:]),
            len(world_renderer.instance_flattened) * size_of(World_Mesh_Instance),
        )
    }
    if len(world_renderer.wing_trail_vertices) > 0 {
        mem.copy_non_overlapping(
            wing_trail_vertex_buffer.mapped,
            raw_data(world_renderer.wing_trail_vertices),
            len(world_renderer.wing_trail_vertices) * size_of(World_Vertex),
        )
        mem.copy_non_overlapping(
            wing_trail_index_buffer.mapped,
            raw_data(world_renderer.wing_trail_optimized_indices),
            len(world_renderer.wing_trail_optimized_indices) * size_of(u16),
        )
    }
    viewport := vk.Viewport {
        width    = f32(pass.framebuffer_extent.width),
        height   = f32(pass.framebuffer_extent.height),
        minDepth = 0,
        maxDepth = 1,
    }
    scissor := vk.Rect2D {
        extent = pass.framebuffer_extent,
    }
    vk.CmdSetViewport(pass.frame.command_buffer, 0, 1, &viewport)
    vk.CmdSetScissor(pass.frame.command_buffer, 0, 1, &scissor)
    pipeline_index := render3d.color_pipeline_variant_index(pass.color_format, pass.sample_count)
    render_camera_pose :=
        menu_scene_current(editor) == .Customization ? customization_preview_camera_pose() : editor.camera_pose
    camera := perspective_camera(render_camera_pose, focal_length)
    sky := atmosphere_sky(editor)
    sky_front := atmosphere.sky_front_field(
        &editor.atmosphere,
        {camera.position.x, camera.position.y, camera.position.z},
    )
    fog := world_sky_horizon_color(sky)
    world_push := World_Push {
        camera_position = {camera.position.x, camera.position.y, camera.position.z, world_camera_near_clip(editor)},
        camera_right    = {camera.right.x, camera.right.y, camera.right.z, WORLD_FAR_CLIP},
        camera_up       = {camera.up.x, camera.up.y, camera.up.z, 0},
        camera_forward  = {camera.forward.x, camera.forward.y, camera.forward.z, 0},
        projection      = {
            camera.focal_length,
            f32(pass.framebuffer_extent.width) / f32(max(pass.framebuffer_extent.height, 1)),
            WORLD_FOG_START,
            WORLD_FOG_END,
        },
        fog_color       = world_color(fog),
        water           = {sky.cloud_time_seconds, sky.weather.severity, sky.weather.wind[0], sky.weather.wind[1]},
        sun             = world_scene_sun(editor, sky),
    }
    if lab_scene_is_active(editor, "mouse-theater") {
        // The two otherwise-unused camera vector components carry intensity
        // and footprint radius without growing the 128-byte push-constant
        // block. The theater instrument has a fixed rig position in the shader
        // so water/weather inputs remain valid for its emissive floor pool.
        world_push.camera_up[3] = 2.35
        world_push.camera_forward[3] = 3.05
    }
    world_push.fog_color[3] = world_scene_moonlight(sky)
    sky_wind := sky.weather.wind
    if sky_front.active {
        // Terrain and gust sampling can rotate the observer-local wind away
        // from the analytic front. Preserve its speed for cloud drift while
        // using the front's canonical direction to keep the dome aligned with
        // the same geographic weather band sampled by gameplay.
        sky_wind_speed := f32(math.sqrt(f64(sky_wind[0] * sky_wind[0] + sky_wind[1] * sky_wind[1])))
        sky_wind = sky_front.direction * sky_wind_speed
    }
    sky_push := Sky_Push {
        camera_right   = {
            camera.right.x,
            camera.right.y,
            camera.right.z,
            f32(pass.framebuffer_extent.width) / f32(max(pass.framebuffer_extent.height, 1)),
        },
        camera_up      = {camera.up.x, camera.up.y, camera.up.z, camera.focal_length},
        camera_forward = {camera.forward.x, camera.forward.y, camera.forward.z, sky_front.signed_distance_widths},
        sun_direction  = {sky.sun_direction[0], sky.sun_direction[1], sky.sun_direction[2], f32(sky.cloud_seed)},
        moon_direction = {sky.moon_direction[0], sky.moon_direction[1], sky.moon_direction[2], sky.moon_illumination},
        time_light     = {sky.world_minutes, sky.cloud_time_seconds, sky.daylight, sky.twilight},
        wind_cloud     = {sky_wind[0], sky_wind[1], sky.weather.cloud_cover, sky.weather.precipitation},
        haze_severity  = {
            sky.weather.haze,
            sky.weather.severity,
            sky.world_days,
            sky_front.active ? sky_front.horizon_ray_widths : f32(-1),
        },
    }
    offset := vk.DeviceSize(0)
    graph_context := Render_Graph_Context {
        pass                     = pass,
        buffer                   = buffer,
        static_vertex_buffer     = static_vertex_buffer,
        static_index_buffer      = static_index_buffer,
        static_indirect_buffer   = static_indirect_buffer,
        road_buffer              = road_buffer,
        road_indirect_buffer     = road_indirect_buffer,
        foliage_buffer           = foliage_buffer,
        bougainvillea_buffer     = bougainvillea_buffer,
        grass_instance_buffer    = grass_instance_buffer,
        instance_vertex_buffer   = instance_vertex_buffer,
        plant_vertex_buffer      = plant_vertex_buffer,
        instance_index_buffer    = instance_index_buffer,
        instance_data_buffer     = instance_data_buffer,
        wing_trail_vertex_buffer = wing_trail_vertex_buffer,
        wing_trail_index_buffer  = wing_trail_index_buffer,
        offset                   = offset,
        pipeline_index           = pipeline_index,
        world_push               = world_push,
        sky_push                 = sky_push,
    }
    if !world_render_graph_ready {
        world_render_graph_ready = adriatic_render_graph(&world_render_graph)
    }
    if world_render_graph_ready {
        wipe_rects: [128]vk.Rect2D
        wipe_rect_count := 0
        wipe_sample: cinematic.Sample
        if editor.cinematic_playback.script != nil {
            wipe_sample = cinematic.sample(&editor.cinematic_playback)
            wipe_rect_count = cinematic_wipe_rects(
                pass.framebuffer_extent,
                wipe_sample.wipe.kind,
                wipe_sample.wipe_progress,
                &wipe_rects,
            )
        }
        if wipe_rect_count > 0 {
            cinematic_render_camera(&graph_context, wipe_sample.camera_from)
            _ = render_graph.execute(&world_render_graph, &graph_context)

            mask_attachment := vk.ClearAttachment {
                aspectMask = {.DEPTH},
                clearValue = {depthStencil = {depth = 1}},
            }
            full_attachment := vk.ClearAttachment {
                aspectMask = {.DEPTH},
                clearValue = {depthStencil = {depth = 0}},
            }
            full_rect := vk.ClearRect {
                rect = {extent = pass.framebuffer_extent},
                baseArrayLayer = 0,
                layerCount = 1,
            }
            vk.CmdClearAttachments(pass.frame.command_buffer, 1, &full_attachment, 1, &full_rect)
            mask_rects: [128]vk.ClearRect
            for index in 0 ..< wipe_rect_count {
                mask_rects[index] = {
                    rect           = wipe_rects[index],
                    baseArrayLayer = 0,
                    layerCount     = 1,
                }
            }
            vk.CmdClearAttachments(
                pass.frame.command_buffer,
                1,
                &mask_attachment,
                u32(wipe_rect_count),
                &mask_rects[0],
            )
            cinematic_render_camera(&graph_context, wipe_sample.camera_to)
            for index in 0 ..< wipe_rect_count {
                vk.CmdSetScissor(pass.frame.command_buffer, 0, 1, &wipe_rects[index])
                render_graph_sky(&graph_context)
            }

            full_scissor := vk.Rect2D {
                extent = pass.framebuffer_extent,
            }
            vk.CmdSetScissor(pass.frame.command_buffer, 0, 1, &full_scissor)
            cinematic_render_world_without_sky(&graph_context)
        } else {
            _ = render_graph.execute(&world_render_graph, &graph_context)
        }
        world_bomber_pip_render(&graph_context)
    }
    dialogue_portrait_render(pass, buffer, pipeline_index, editor)
}

world_renderer_attach :: proc(editor: ^Editor) {
    world_renderer.editor = editor
    canvas2d.SetWorldPrePass(world_pre_pass)
    canvas2d.SetWorldPass(world_pass)
    canvas2d.SetUIPass(imgui_ui_pass)
}

world_renderer_destroy :: proc() {
    if !world_renderer.initialized do return
    _ = vk.DeviceWaitIdle(world_renderer.ctx.device)
    generated_plant_cache_destroy()
    world_spatial_index_destroy(&world_renderer.spatial_index)
    imgui_destroy()
    for &buffer in world_renderer.vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.static_vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.static_index do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.static_indirect do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.road_vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.road_indirect do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.foliage_vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.bougainvillea_instance do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.grass_instance do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.instance_vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.plant_vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.instance_index do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.instance_data do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.vehicle_paint_staging do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.wing_trail_vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.wing_trail_index do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.shadow_vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for frame in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
        for level in 0 ..< terrain.CLIPMAP_LEVELS {
            engine.vk_destroy_buffer(world_renderer.ctx, &world_renderer.clipmap_vertex[frame][level])
        }
    }
    engine.vk_destroy_buffer(world_renderer.ctx, &world_renderer.clipmap_index)
    engine.vk_destroy_buffer(world_renderer.ctx, &world_renderer.clipmap_outer_full_index)
    for &row in world_renderer.clipmap_ring_index {
        for &buffer in row do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    }
    for &row in world_renderer.clipmap_inner_ring_index {
        for &buffer in row do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    }
    roads.mesh_destroy(&world_renderer.road_mesh)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.transparent_pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.shadow_pipelines)
    dynamic_shadow_destroy(&world_renderer.dynamic_shadow, world_renderer.ctx)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.road_pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.sky_pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.particle_pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.foliage_pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.bougainvillea_pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.grass_pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.instance_pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.plant_pipelines)
    resources.image_destroy(&world_renderer.foliage_atlas, world_renderer.ctx)
    resources.image_destroy(&world_renderer.bougainvillea_atlas, world_renderer.ctx)
    resources.image_destroy(&world_renderer.grass_atlas, world_renderer.ctx)
    resources.image_destroy(&world_renderer.wildflower_atlas, world_renderer.ctx)
    resources.image_destroy(&world_renderer.marsh_atlas, world_renderer.ctx)
    resources.image_destroy(&world_renderer.terrain_particle_atlas, world_renderer.ctx)
    resources.image_destroy(&world_renderer.vehicle_paint_atlas, world_renderer.ctx)
    resources.image_destroy(&world_renderer.soda_cap_logo, world_renderer.ctx)
    resources.image_destroy(&world_renderer.architecture_material_atlas, world_renderer.ctx)
    resources.image_destroy(&world_renderer.business_sign_atlas, world_renderer.ctx)
    for &material_map in world_renderer.material_lab_maps {
        resources.image_destroy(&material_map, world_renderer.ctx)
    }
    if world_renderer.layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(world_renderer.ctx.device, world_renderer.layout, nil)
    if world_renderer.sky_layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(world_renderer.ctx.device, world_renderer.sky_layout, nil)
    if world_renderer.foliage_layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(world_renderer.ctx.device, world_renderer.foliage_layout, nil)
    if world_renderer.foliage_descriptor_pool != vk.DescriptorPool(0) {
        vk.DestroyDescriptorPool(world_renderer.ctx.device, world_renderer.foliage_descriptor_pool, nil)
    }
    if world_renderer.foliage_descriptor_layout != vk.DescriptorSetLayout(0) {
        vk.DestroyDescriptorSetLayout(world_renderer.ctx.device, world_renderer.foliage_descriptor_layout, nil)
    }
    if world_renderer.vehicle_paint_descriptor_pool != vk.DescriptorPool(0) {
        vk.DestroyDescriptorPool(world_renderer.ctx.device, world_renderer.vehicle_paint_descriptor_pool, nil)
    }
    if world_renderer.vehicle_paint_descriptor_layout != vk.DescriptorSetLayout(0) {
        vk.DestroyDescriptorSetLayout(world_renderer.ctx.device, world_renderer.vehicle_paint_descriptor_layout, nil)
    }
    delete(world_renderer.vertices)
    delete(world_renderer.late_transparent_vertices)
    delete(world_renderer.static_vertices)
    delete(world_renderer.static_indices)
    delete(world_renderer.retained_static_draws)
    delete(world_renderer.static_draw_commands)
    delete(world_renderer.retained_patio_vertices)
    delete(world_renderer.retained_patio_indices)
    delete(world_renderer.road_vertices)
    delete(world_renderer.road_draw_commands)
    delete(world_renderer.road_geometry_cache)
    delete(world_renderer.road_geometry_chunks)
    delete(world_renderer.architecture_alley_render_cache)
    delete(world_renderer.architecture_alley_geometry_cache)
    delete(world_renderer.architecture_alley_geometry_plan)
    delete(world_renderer.architecture_alley_overlap_cache)
    delete(world_renderer.architecture_alley_overlap_plan)
    for &entry in world_renderer.architecture_street_area_cache do delete(entry.vertices)
    delete(world_renderer.architecture_street_area_cache)
    for &entry in world_renderer.settlement_fountain_geometry_cache do delete(entry.vertices)
    delete(world_renderer.settlement_fountain_geometry_cache)
    for &entry in world_renderer.airport_kiosk_geometry_cache {
        delete(entry.prefix_vertices)
        delete(entry.suffix_vertices)
    }
    delete(world_renderer.airport_kiosk_geometry_cache)
    delete(world_renderer.laundry_geometry_cache)
    delete(world_renderer.foliage_vertices)
    delete(world_renderer.bougainvillea_vertices)
    delete(world_renderer.bougainvillea_instances)
    delete(world_renderer.grass_instances)
    delete(world_renderer.wildflower_instances)
    delete(world_renderer.marsh_instances)
    delete(world_renderer.terrain_particle_vertices)
    world_instance_meshes_clear()
    delete(world_renderer.instance_vertices)
    delete(world_renderer.instance_indices)
    delete(world_renderer.instance_flattened)
    delete(world_renderer.instance_meshes)
    delete(world_renderer.plant_vertices)
    delete(world_renderer.plant_meshes)
    delete(world_renderer.middle_tree_shadow_proxies)
    ground_grass_cache_clear()
    delete(world_renderer.grass_chunk_cache)
    delete(world_renderer.grass_chunk_pool)
    delete(world_renderer.wing_trail_vertices)
    delete(world_renderer.wing_trail_indices)
    delete(world_renderer.wing_trail_optimized_indices)
    delete(world_renderer.land_surface_samples)
    delete(world_renderer.shadow_vertices)
    delete(world_renderer.shadow_world_ranges)
    delete(world_renderer.dynamic_shadow_terrain_cache.vertices)
    delete(world_renderer.explicit_shadow_caster_ranges)
    delete(world_renderer.static_shadow_caster_ranges)
    for &vertices in world_renderer.clipmap_cache_vertex do delete(vertices)
    for &vertices in world_renderer.clipmap_scratch_vertex do delete(vertices)
    for &entry in world_renderer.foliage_geometry_cache {
        delete(entry.world_vertices)
        delete(entry.foliage_vertices)
    }
    delete(world_renderer.foliage_geometry_cache)
    for &entry in world_renderer.static_geometry_cache {
        delete(entry.world_vertices)
        delete(entry.world_indices)
        delete(entry.foliage_vertices)
        delete(entry.bougainvillea_vertices)
        delete(entry.bougainvillea_cards)
    }
    delete(world_renderer.static_geometry_cache)
    for &entry in world_renderer.climbing_leaf_geometry_cache {
        delete(entry.world_vertices)
        delete(entry.bougainvillea_vertices)
        delete(entry.cards)
    }
    delete(world_renderer.climbing_leaf_geometry_cache)
    delete(world_renderer.static_visibility_classification)
    delete(world_renderer.structure_visibility_order)
    delete(world_renderer.overlay_chunk_bounds)
    delete(world_renderer.structure_building_spans)
    delete(world_renderer.structure_candidates)
    delete(world_renderer.ocean_geometry_cache)
    delete(world_renderer.ocean_sample_grid)
    delete(world_renderer.ocean_sample_grid_scratch)
    for &entry in world_renderer.bathymetry_geometry_cache do delete(entry.vertices)
    delete(world_renderer.bathymetry_geometry_cache)
    for &entry in world_renderer.town_mouse_geometry_cache {
        delete(entry.vertices)
    }
    for &entry in world_renderer.dialogue_portrait_geometry_cache {
        delete(entry.vertices)
    }
    delete(world_renderer.libellula_geometry_cache.vertices)
    if world_renderer.postale_pose_mesh != nil do free(world_renderer.postale_pose_mesh)
    if world_renderer.trailer_pose_mesh != nil do free(world_renderer.trailer_pose_mesh)
    for mesh in world_renderer.trailer_baked_meshes {
        if mesh != nil do free(mesh)
    }
    for &entry in world_renderer.marina_geometry_cache {
        delete(entry.world_vertices)
    }
    world_renderer = {}
}
