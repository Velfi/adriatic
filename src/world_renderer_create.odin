package main
import "core:fmt"

import particles "../packages/particles"
import terrain "../packages/terrain"
import vk "vendor:vulkan"
import engine "zelda_engine:engine"
import render3d "zelda_engine:render3d"
import resources "zelda_engine:render_resources"

world_renderer_create :: proc(ctx: ^engine.Vk_Context) -> bool {
    failure_stage := "dynamic shadow"
    defer if !world_renderer.initialized {
        fmt.eprintf("world renderer initialization failed during %s\n", failure_stage)
    }
    if !dynamic_shadow_create(&world_renderer.dynamic_shadow, ctx) do return false
    failure_stage = "vehicle paint descriptors"
    if !world_renderer_create_descriptors(ctx, &failure_stage) do return false
    sky_pr := vk.PushConstantRange {
        stageFlags = {.VERTEX, .FRAGMENT},
        size       = u32(size_of(Sky_Push)),
    }
    sky_li := vk.PipelineLayoutCreateInfo {
        sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
        pushConstantRangeCount = 1,
        pPushConstantRanges    = &sky_pr,
    }
    if vk.CreatePipelineLayout(ctx.device, &sky_li, nil, &world_renderer.sky_layout) != .SUCCESS do return false
    engine.vk_set_debug_name(ctx, .PIPELINE_LAYOUT, auto_cast world_renderer.sky_layout, "sky pipeline layout")
    vert, frag: engine.Vk_Shader_Module
    failure_stage = "world shaders"
    if !engine.vk_load_shader_module_with_fallback(ctx, "assets/shaders/world.slang", "shaders/world.vert", .Vertex, "vertex_main", &vert) do return false
    defer engine.vk_destroy_shader_module(ctx, &vert)
    if !engine.vk_load_shader_module_with_fallback(ctx, "assets/shaders/world.slang", "shaders/world.frag", .Fragment, "fragment_main", &frag) do return false
    defer engine.vk_destroy_shader_module(ctx, &frag)
    stages := [2]vk.PipelineShaderStageCreateInfo {
        {sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.VERTEX}, module = vert.handle, pName = "main"},
        {sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.FRAGMENT}, module = frag.handle, pName = "main"},
    }
    binding := vk.VertexInputBindingDescription {
        stride    = u32(size_of(World_Vertex)),
        inputRate = .VERTEX,
    }
    attrs := [6]vk.VertexInputAttributeDescription {
        {location = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(World_Vertex, position))},
        {location = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(World_Vertex, color))},
        {location = 2, format = .R32_UINT, offset = u32(offset_of(World_Vertex, kind))},
        {location = 3, format = .R32G32B32_SFLOAT, offset = u32(offset_of(World_Vertex, normal))},
        {location = 4, format = .R32G32_SFLOAT, offset = u32(offset_of(World_Vertex, material))},
        {location = 5, format = .R32G32_SFLOAT, offset = u32(offset_of(World_Vertex, uv))},
    }
    vi := vk.PipelineVertexInputStateCreateInfo {
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount   = 1,
        pVertexBindingDescriptions      = &binding,
        vertexAttributeDescriptionCount = 6,
        pVertexAttributeDescriptions    = raw_data(attrs[:]),
    }
    ia := vk.PipelineInputAssemblyStateCreateInfo {
        sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology = .TRIANGLE_LIST,
    }
    vp := vk.PipelineViewportStateCreateInfo {
        sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount = 1,
        scissorCount  = 1,
    }
    rs := vk.PipelineRasterizationStateCreateInfo {
        sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        polygonMode = .FILL,
        cullMode    = {.BACK},
        frontFace   = .COUNTER_CLOCKWISE,
        lineWidth   = 1,
    }
    ms := vk.PipelineMultisampleStateCreateInfo {
        sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        rasterizationSamples = {._1},
    }
    depth := vk.PipelineDepthStencilStateCreateInfo {
        sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        depthTestEnable  = true,
        depthWriteEnable = true,
        depthCompareOp   = .LESS,
    }
    ca := vk.PipelineColorBlendAttachmentState {
        // World vertices are mostly opaque, but authored shadows use their
        // alpha for a soft penumbra. Keep alpha-one geometry unchanged while
        // allowing those shadow layers to composite over the terrain.
        blendEnable         = true,
        srcColorBlendFactor = .SRC_ALPHA,
        dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
        colorBlendOp        = .ADD,
        srcAlphaBlendFactor = .ONE,
        dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
        alphaBlendOp        = .ADD,
        colorWriteMask      = {.R, .G, .B, .A},
    }
    cb := vk.PipelineColorBlendStateCreateInfo {
        sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        attachmentCount = 1,
        pAttachments    = &ca,
    }
    ds := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}
    di := vk.PipelineDynamicStateCreateInfo {
        sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        dynamicStateCount = 2,
        pDynamicStates    = raw_data(ds[:]),
    }
    info := vk.GraphicsPipelineCreateInfo {
        sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
        stageCount          = 2,
        pStages             = raw_data(stages[:]),
        pVertexInputState   = &vi,
        pInputAssemblyState = &ia,
        pViewportState      = &vp,
        pRasterizationState = &rs,
        pMultisampleState   = &ms,
        pDepthStencilState  = &depth,
        pColorBlendState    = &cb,
        pDynamicState       = &di,
        layout              = world_renderer.layout,
    }
    failure_stage = "world graphics pipelines"
    if !render3d.create_color_pipeline_variants(ctx, &info, .D32_SFLOAT, &world_renderer.pipelines) do return false
    instance_vert: engine.Vk_Shader_Module
    if !engine.vk_load_shader_module_with_fallback(
        ctx,
        "assets/shaders/world.slang",
        "shaders/world-instance.vert",
        .Vertex,
        "instance_vertex_main",
        &instance_vert,
    ) {
        return false
    }
    defer engine.vk_destroy_shader_module(ctx, &instance_vert)
    instance_stages := stages
    instance_stages[0].module = instance_vert.handle
    instance_bindings := [2]vk.VertexInputBindingDescription {
        {binding = 0, stride = u32(size_of(World_Vertex)), inputRate = .VERTEX},
        {binding = 1, stride = u32(size_of(World_Mesh_Instance)), inputRate = .INSTANCE},
    }
    instance_attrs := [11]vk.VertexInputAttributeDescription {
        {location = 0, binding = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(World_Vertex, position))},
        {location = 1, binding = 0, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(World_Vertex, color))},
        {location = 2, binding = 0, format = .R32_UINT, offset = u32(offset_of(World_Vertex, kind))},
        {location = 3, binding = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(World_Vertex, normal))},
        {location = 4, binding = 0, format = .R32G32_SFLOAT, offset = u32(offset_of(World_Vertex, material))},
        {location = 5, binding = 0, format = .R32G32_SFLOAT, offset = u32(offset_of(World_Vertex, uv))},
        {
            location = 6,
            binding = 1,
            format = .R32G32B32A32_SFLOAT,
            offset = u32(offset_of(World_Mesh_Instance, basis_x_translation_x)),
        },
        {
            location = 7,
            binding = 1,
            format = .R32G32B32A32_SFLOAT,
            offset = u32(offset_of(World_Mesh_Instance, basis_y_translation_y)),
        },
        {
            location = 8,
            binding = 1,
            format = .R32G32B32A32_SFLOAT,
            offset = u32(offset_of(World_Mesh_Instance, basis_z_translation_z)),
        },
        {
            location = 9,
            binding = 1,
            format = .R32G32B32A32_SFLOAT,
            offset = u32(offset_of(World_Mesh_Instance, color)),
        },
        {
            location = 10,
            binding = 1,
            format = .R32G32B32A32_SFLOAT,
            offset = u32(offset_of(World_Mesh_Instance, normal_override)),
        },
    }
    instance_vi := vk.PipelineVertexInputStateCreateInfo {
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount   = 2,
        pVertexBindingDescriptions      = raw_data(instance_bindings[:]),
        vertexAttributeDescriptionCount = 11,
        pVertexAttributeDescriptions    = raw_data(instance_attrs[:]),
    }
    instance_info := info
    instance_info.pStages = raw_data(instance_stages[:])
    instance_info.pVertexInputState = &instance_vi
    if !render3d.create_color_pipeline_variants(ctx, &instance_info, .D32_SFLOAT, &world_renderer.instance_pipelines) {
        return false
    }
    transparent_depth := depth
    transparent_depth.depthWriteEnable = false
    transparent_info := info
    transparent_info.pDepthStencilState = &transparent_depth
    if !render3d.create_color_pipeline_variants(
        ctx,
        &transparent_info,
        .D32_SFLOAT,
        &world_renderer.transparent_pipelines,
    ) {
        return false
    }
    shadow_vert, shadow_frag: engine.Vk_Shader_Module
    if !engine.vk_load_shader_module_with_fallback(
        ctx,
        "assets/shaders/world.slang",
        "shaders/player-shadow.vert",
        .Vertex,
        "shadow_vertex",
        &shadow_vert,
    ) {
        return false
    }
    defer engine.vk_destroy_shader_module(ctx, &shadow_vert)
    if !engine.vk_load_shader_module_with_fallback(
        ctx,
        "assets/shaders/world.slang",
        "shaders/player-shadow.frag",
        .Fragment,
        "shadow_fragment",
        &shadow_frag,
    ) {
        return false
    }
    defer engine.vk_destroy_shader_module(ctx, &shadow_frag)
    shadow_stages := stages
    shadow_stages[0].module = shadow_vert.handle
    shadow_stages[1].module = shadow_frag.handle
    shadow_rs := rs
    shadow_rs.cullMode = {}
    shadow_rs.depthBiasEnable = true
    // The character shadow lies almost coplanar with roads and terrain.
    // A one-unit bias still produces horizontal depth-fighting gaps at the
    // low gameplay camera, especially on road crowns. Pull the shadow toward
    // the camera in depth only so its silhouette remains continuous without
    // visibly lifting the projected geometry away from the ground.
    shadow_rs.depthBiasConstantFactor = -8
    shadow_rs.depthBiasSlopeFactor = -2
    shadow_depth := depth
    shadow_depth.depthCompareOp = .LESS_OR_EQUAL
    shadow_info := info
    shadow_info.pStages = raw_data(shadow_stages[:])
    shadow_info.pRasterizationState = &shadow_rs
    shadow_info.pDepthStencilState = &shadow_depth
    if !render3d.create_color_pipeline_variants(ctx, &shadow_info, .D32_SFLOAT, &world_renderer.shadow_pipelines) {
        return false
    }
    // Roads are submitted after the terrain. A small negative polygon offset
    // pulls only their fragments toward the camera under the conventional
    // LESS depth convention, preventing coplanar flicker at grazing angles
    // without making unrelated world geometry bleed through terrain.
    road_rs := rs
    // Roads are a thin authored terrain overlay and legacy edge, cap, and
    // junction builders do not share one winding convention. Keep only this
    // dedicated pass two-sided so back-face culling cannot erase long strips.
    road_rs.cullMode = {}
    road_rs.depthBiasEnable = true
    road_rs.depthBiasConstantFactor = -1
    road_rs.depthBiasSlopeFactor = -1
    road_depth := depth
    road_depth.depthCompareOp = .LESS_OR_EQUAL
    road_info := info
    road_info.pRasterizationState = &road_rs
    road_info.pDepthStencilState = &road_depth
    if !render3d.create_color_pipeline_variants(ctx, &road_info, .D32_SFLOAT, &world_renderer.road_pipelines) do return false
    foliage_vert, foliage_frag: engine.Vk_Shader_Module
    if !engine.vk_load_shader_module_with_fallback(
        ctx,
        "assets/shaders/foliage.slang",
        "shaders/foliage.vert",
        .Vertex,
        "vertex_main",
        &foliage_vert,
    ) {
        return false
    }
    defer engine.vk_destroy_shader_module(ctx, &foliage_vert)
    if !engine.vk_load_shader_module_with_fallback(
        ctx,
        "assets/shaders/foliage.slang",
        "shaders/foliage.frag",
        .Fragment,
        "fragment_main",
        &foliage_frag,
    ) {
        return false
    }
    defer engine.vk_destroy_shader_module(ctx, &foliage_frag)
    foliage_stages := stages
    foliage_stages[0].module = foliage_vert.handle
    foliage_stages[1].module = foliage_frag.handle
    foliage_binding := vk.VertexInputBindingDescription {
        stride    = u32(size_of(Foliage_Vertex)),
        inputRate = .VERTEX,
    }
    foliage_attributes := [4]vk.VertexInputAttributeDescription {
        {location = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Foliage_Vertex, position))},
        {location = 1, format = .R32G32_SFLOAT, offset = u32(offset_of(Foliage_Vertex, uv))},
        {location = 2, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(Foliage_Vertex, color))},
        {location = 3, format = .R32_UINT, offset = u32(offset_of(Foliage_Vertex, kind))},
    }
    foliage_vi := vk.PipelineVertexInputStateCreateInfo {
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount   = 1,
        pVertexBindingDescriptions      = &foliage_binding,
        vertexAttributeDescriptionCount = 4,
        pVertexAttributeDescriptions    = raw_data(foliage_attributes[:]),
    }
    foliage_depth := depth
    foliage_depth.depthCompareOp = .LESS_OR_EQUAL
    foliage_info := info
    foliage_info.pStages = raw_data(foliage_stages[:])
    foliage_info.pVertexInputState = &foliage_vi
    foliage_info.pDepthStencilState = &foliage_depth
    foliage_info.layout = world_renderer.foliage_layout
    if !render3d.create_color_pipeline_variants(ctx, &foliage_info, .D32_SFLOAT, &world_renderer.foliage_pipelines) {
        return false
    }
    bougainvillea_vert: engine.Vk_Shader_Module
    if !engine.vk_load_shader_module_with_fallback(
        ctx,
        "assets/shaders/foliage.slang",
        "shaders/bougainvillea.vert",
        .Vertex,
        "bougainvillea_vertex_main",
        &bougainvillea_vert,
    ) {
        return false
    }
    defer engine.vk_destroy_shader_module(ctx, &bougainvillea_vert)
    bougainvillea_stages := foliage_stages
    bougainvillea_stages[0].module = bougainvillea_vert.handle
    bougainvillea_binding := vk.VertexInputBindingDescription {
        stride    = u32(size_of(Bougainvillea_Instance)),
        inputRate = .INSTANCE,
    }
    bougainvillea_attributes := [5]vk.VertexInputAttributeDescription {
        {location = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Bougainvillea_Instance, center))},
        {location = 1, format = .R32G32_SFLOAT, offset = u32(offset_of(Bougainvillea_Instance, size))},
        {location = 2, format = .R32_UINT, offset = u32(offset_of(Bougainvillea_Instance, tile))},
        {location = 3, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(Bougainvillea_Instance, params))},
        {location = 4, format = .R32_SFLOAT, offset = u32(offset_of(Bougainvillea_Instance, yaw_bias))},
    }
    bougainvillea_vi := vk.PipelineVertexInputStateCreateInfo {
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount   = 1,
        pVertexBindingDescriptions      = &bougainvillea_binding,
        vertexAttributeDescriptionCount = 5,
        pVertexAttributeDescriptions    = raw_data(bougainvillea_attributes[:]),
    }
    bougainvillea_info := foliage_info
    bougainvillea_info.pStages = raw_data(bougainvillea_stages[:])
    bougainvillea_info.pVertexInputState = &bougainvillea_vi
    if !render3d.create_color_pipeline_variants(
        ctx,
        &bougainvillea_info,
        .D32_SFLOAT,
        &world_renderer.bougainvillea_pipelines,
    ) {
        return false
    }
    grass_vert: engine.Vk_Shader_Module
    if !engine.vk_load_shader_module_with_fallback(
        ctx,
        "assets/shaders/foliage.slang",
        "shaders/grass.vert",
        .Vertex,
        "grass_vertex_main",
        &grass_vert,
    ) {
        return false
    }
    defer engine.vk_destroy_shader_module(ctx, &grass_vert)
    grass_stages := foliage_stages
    grass_stages[0].module = grass_vert.handle
    grass_binding := vk.VertexInputBindingDescription {
        stride    = u32(size_of(Grass_Instance)),
        inputRate = .INSTANCE,
    }
    grass_attributes := [6]vk.VertexInputAttributeDescription {
        {location = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Grass_Instance, center))},
        {location = 1, format = .R32G32_SFLOAT, offset = u32(offset_of(Grass_Instance, size))},
        {location = 2, format = .R32_UINT, offset = u32(offset_of(Grass_Instance, tile))},
        {location = 3, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(Grass_Instance, color))},
        {location = 4, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(Grass_Instance, ground_color))},
        {location = 5, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(Grass_Instance, cull_params))},
    }
    grass_vi := vk.PipelineVertexInputStateCreateInfo {
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount   = 1,
        pVertexBindingDescriptions      = &grass_binding,
        vertexAttributeDescriptionCount = 6,
        pVertexAttributeDescriptions    = raw_data(grass_attributes[:]),
    }
    grass_info := foliage_info
    grass_info.pStages = raw_data(grass_stages[:])
    grass_info.pVertexInputState = &grass_vi
    if !render3d.create_color_pipeline_variants(ctx, &grass_info, .D32_SFLOAT, &world_renderer.grass_pipelines) {
        return false
    }
    particle_vert, particle_frag: engine.Vk_Shader_Module
    if !engine.vk_load_shader_module_with_fallback(ctx, "assets/shaders/particles.slang", "shaders/particles.vert", .Vertex, "vertex_main", &particle_vert) do return false
    defer engine.vk_destroy_shader_module(ctx, &particle_vert)
    if !engine.vk_load_shader_module_with_fallback(ctx, "assets/shaders/particles.slang", "shaders/particles.frag", .Fragment, "fragment_main", &particle_frag) do return false
    defer engine.vk_destroy_shader_module(ctx, &particle_frag)
    particle_stages := stages
    particle_stages[0].module = particle_vert.handle
    particle_stages[1].module = particle_frag.handle
    particle_info := info
    particle_info.pStages = raw_data(particle_stages[:])
    particle_vi := vk.PipelineVertexInputStateCreateInfo {
        sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    }
    particle_info.pVertexInputState = &particle_vi
    particle_info.pInputAssemblyState = &ia
    particle_info.pInputAssemblyState.topology = .TRIANGLE_LIST
    particle_info.pDepthStencilState = &depth
    particle_info.layout = world_renderer.layout
    if !render3d.create_color_pipeline_variants(ctx, &particle_info, .D32_SFLOAT, &world_renderer.particle_pipelines) do return false
    sky_vert, sky_frag: engine.Vk_Shader_Module
    if !engine.vk_load_shader_module_with_fallback(ctx, "assets/shaders/sky.slang", "shaders/world-sky.vert", .Vertex, "sky_vertex", &sky_vert) do return false
    defer engine.vk_destroy_shader_module(ctx, &sky_vert)
    if !engine.vk_load_shader_module_with_fallback(ctx, "assets/shaders/sky.slang", "shaders/world-sky.frag", .Fragment, "sky_fragment", &sky_frag) do return false
    defer engine.vk_destroy_shader_module(ctx, &sky_frag)
    stages[0].module = sky_vert.handle
    stages[1].module = sky_frag.handle
    sky_vi := vk.PipelineVertexInputStateCreateInfo {
        sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    }
    sky_depth := vk.PipelineDepthStencilStateCreateInfo {
        sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        depthTestEnable  = false,
        depthWriteEnable = false,
    }
    // The sky writes alpha zero as a classification marker for the world
    // palette post-process. It must not alpha-blend against the cleared target,
    // or the marker would also attenuate the sky color.
    sky_ca := ca
    sky_ca.blendEnable = false
    sky_cb := cb
    sky_cb.pAttachments = &sky_ca
    sky_rs := rs
    sky_rs.cullMode = {}
    sky_info := info
    sky_info.pVertexInputState = &sky_vi
    sky_info.pDepthStencilState = &sky_depth
    sky_info.pColorBlendState = &sky_cb
    sky_info.pRasterizationState = &sky_rs
    sky_info.layout = world_renderer.sky_layout
    if !render3d.create_color_pipeline_variants(ctx, &sky_info, .D32_SFLOAT, &world_renderer.sky_pipelines) do return false
    for &buffer in world_renderer.vertex {
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(WORLD_VERTEX_INITIAL_CAPACITY * size_of(World_Vertex)),
            {.VERTEX_BUFFER},
            &buffer,
            "world dynamic vertex buffer",
        ) {
            return false
        }
    }
    for frame in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(WORLD_VERTEX_INITIAL_CAPACITY * size_of(World_Vertex)),
            {.VERTEX_BUFFER},
            &world_renderer.static_vertex[frame],
            "world static vertex buffer",
        ) {
            return false
        }
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(WORLD_VERTEX_INITIAL_CAPACITY * size_of(u32)),
            {.INDEX_BUFFER},
            &world_renderer.static_index[frame],
            "world static index buffer",
        ) {
            return false
        }
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(512 * size_of(vk.DrawIndexedIndirectCommand)),
            {.INDIRECT_BUFFER},
            &world_renderer.static_indirect[frame],
            "world static indirect buffer",
        ) {
            return false
        }
    }
    for &buffer in world_renderer.road_vertex {
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(ROAD_VERTEX_INITIAL_CAPACITY * size_of(World_Vertex)),
            {.VERTEX_BUFFER},
            &buffer,
            "world road vertex buffer",
        ) {
            return false
        }
    }
    for &buffer in world_renderer.road_indirect {
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(512 * size_of(vk.DrawIndirectCommand)),
            {.INDIRECT_BUFFER},
            &buffer,
            "world road indirect buffer",
        ) {
            return false
        }
    }
    for &buffer in world_renderer.foliage_vertex {
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(
                (FOLIAGE_VERTEX_INITIAL_CAPACITY + BOUGAINVILLEA_VERTEX_INITIAL_CAPACITY) * size_of(Foliage_Vertex),
            ),
            {.VERTEX_BUFFER},
            &buffer,
            "world foliage vertex buffer",
        ) {
            return false
        }
    }
    for &buffer in world_renderer.bougainvillea_instance {
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(2_000 * size_of(Bougainvillea_Instance)),
            {.VERTEX_BUFFER},
            &buffer,
            "world bougainvillea instance buffer",
        ) {
            return false
        }
    }
    for &buffer in world_renderer.grass_instance {
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(
                (GRASS_INSTANCE_INITIAL_CAPACITY +
                    WILDFLOWER_INSTANCE_INITIAL_CAPACITY +
                    MARSH_INSTANCE_INITIAL_CAPACITY) *
                size_of(Grass_Instance),
            ),
            {.VERTEX_BUFFER},
            &buffer,
            "world grass instance buffer",
        ) {
            return false
        }
    }
    for &buffer in world_renderer.vehicle_paint_staging {
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(VEHICLE_PAINT_TEXTURE_BYTE_COUNT),
            {.TRANSFER_SRC},
            &buffer,
            "vehicle paint staging buffer",
        ) {
            return false
        }
    }
    for frame in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(WING_TRAIL_VERTEX_CAPACITY * size_of(World_Vertex)),
            {.VERTEX_BUFFER},
            &world_renderer.wing_trail_vertex[frame],
            "wing trail vertex buffer",
        ) {
            return false
        }
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(WING_TRAIL_INDEX_CAPACITY * size_of(u16)),
            {.INDEX_BUFFER},
            &world_renderer.wing_trail_index[frame],
            "wing trail index buffer",
        ) {
            return false
        }
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(SHADOW_VERTEX_INITIAL_CAPACITY * size_of(World_Vertex)),
            {.VERTEX_BUFFER},
            &world_renderer.shadow_vertex[frame],
            "world shadow vertex buffer",
        ) {
            return false
        }
    }
    for frame in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
        for level in 0 ..< terrain.CLIPMAP_LEVELS {
            vertex_count := clipmap_grid_resolution(level) * clipmap_grid_resolution(level)
            if !world_host_buffer_create(
                ctx,
                vk.DeviceSize(vertex_count * size_of(World_Vertex)),
                {.VERTEX_BUFFER},
                &world_renderer.clipmap_vertex[frame][level],
                "world clipmap vertex buffer",
            ) {
                return false
            }
        }
    }
    failure_stage = "clipmap buffers"
    if !clipmap_create_indices(ctx) do return false
    world_renderer.vertices = make([dynamic]World_Vertex, 0, WORLD_VERTEX_INITIAL_CAPACITY)
    world_renderer.static_vertices = make([dynamic]World_Vertex, 0, WORLD_VERTEX_INITIAL_CAPACITY)
    world_renderer.static_indices = make([dynamic]u32, 0, WORLD_VERTEX_INITIAL_CAPACITY)
    world_renderer.retained_static_draws = make([dynamic]Retained_Static_Draw, 0, 256)
    world_renderer.static_draw_commands = make([dynamic]vk.DrawIndexedIndirectCommand, 0, 256)
    world_renderer.retained_static_dirty = true
    world_renderer.retained_patio_vertices = make([dynamic]World_Vertex, 0, 4096)
    world_renderer.retained_patio_indices = make([dynamic]u32, 0, 4096)
    world_renderer.retained_patio_dirty = true
    world_renderer.road_vertices = make([dynamic]World_Vertex, 0, ROAD_VERTEX_INITIAL_CAPACITY)
    world_renderer.road_draw_commands = make([dynamic]vk.DrawIndirectCommand, 0, 256)
    world_renderer.foliage_vertices = make([dynamic]Foliage_Vertex, 0, FOLIAGE_VERTEX_INITIAL_CAPACITY)
    world_renderer.bougainvillea_vertices = make([dynamic]Foliage_Vertex, 0, BOUGAINVILLEA_VERTEX_INITIAL_CAPACITY)
    world_renderer.bougainvillea_instances = make([dynamic]Bougainvillea_Instance, 0, 2_000)
    world_renderer.grass_instances = make([dynamic]Grass_Instance, 0, GRASS_INSTANCE_INITIAL_CAPACITY)
    world_renderer.wildflower_instances = make([dynamic]Grass_Instance, 0, WILDFLOWER_INSTANCE_INITIAL_CAPACITY)
    world_renderer.marsh_instances = make([dynamic]Grass_Instance, 0, MARSH_INSTANCE_INITIAL_CAPACITY)
    world_renderer.grass_stream_dirty = true
    world_renderer.terrain_particle_vertices = make([dynamic]Foliage_Vertex, 0, 1_536)
    world_renderer.wing_trail_vertices = make([dynamic]World_Vertex, 0, WING_TRAIL_VERTEX_CAPACITY)
    world_renderer.wing_trail_indices = make([dynamic]u16, 0, WING_TRAIL_INDEX_CAPACITY)
    world_renderer.wing_trail_optimized_indices = make([dynamic]u16, 0, WING_TRAIL_INDEX_CAPACITY)
    world_renderer.land_surface_samples = make([dynamic]World_Land_Surface_Sample, 0, 256)
    world_renderer.shadow_vertices = make([dynamic]World_Vertex, 0, SHADOW_VERTEX_INITIAL_CAPACITY)
    world_renderer.shadow_world_ranges = make([dynamic]World_Shadow_Caster_Range, 0, 256)
    world_renderer.dynamic_shadow_terrain_cache.vertices =
        make([dynamic]World_Vertex, 0, DYNAMIC_SHADOW_TERRAIN_VERTEX_COUNT)
    world_renderer.explicit_shadow_caster_ranges = make([dynamic]World_Shadow_Caster_Range, 0, 256)
    world_spatial_index_init(&world_renderer.spatial_index)
    world_renderer.ctx = ctx
    world_renderer.initialized = true
    return true
}
