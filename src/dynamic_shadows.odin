package main

import atmosphere "../packages/atmosphere"
import dio "../packages/dio"
import fog_field "../packages/fog_field"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:testing"
import vk "vendor:vulkan"
import canvas2d "zelda_engine:canvas2d"
import engine "zelda_engine:engine"
import resources "zelda_engine:render_resources"

DYNAMIC_SHADOW_CASCADE_COUNT :: 3
DYNAMIC_SHADOW_RESOLUTIONS := [DYNAMIC_SHADOW_CASCADE_COUNT]u32{2048, 1024, 1024}
DYNAMIC_SHADOW_COVERAGES := [DYNAMIC_SHADOW_CASCADE_COUNT]f32{48, 128, 320}
DYNAMIC_SHADOW_PROXY_RADIUS :: f32(160)
DYNAMIC_SHADOW_TERRAIN_GRID_CELLS :: 64
DYNAMIC_SHADOW_TERRAIN_VERTEX_COUNT :: DYNAMIC_SHADOW_TERRAIN_GRID_CELLS * DYNAMIC_SHADOW_TERRAIN_GRID_CELLS * 6

Dynamic_Shadow_Cascade_Uniform :: struct {
    right:   [4]f32,
    up:      [4]f32,
    forward: [4]f32,
    params:  [4]f32,
}

Dynamic_Shadow_Uniform :: struct {
    cascades:       [DYNAMIC_SHADOW_CASCADE_COUNT]Dynamic_Shadow_Cascade_Uniform,
    // Cascade selection distances from origin, final shadow strength.
    settings:       [4]f32,
    // Authoritative world-space origin shared by caster culling and receivers.
    origin:         [4]f32,
    // Shared scene-atmosphere data. Keeping this in the existing per-frame
    // scene uniform avoids growing the already-full 128-byte push block.
    fog_bank_a:     [fog_field.MAX_BANKS][4]f32,
    fog_bank_b:     [fog_field.MAX_BANKS][4]f32,
    fog_bank_c:     [fog_field.MAX_BANKS][4]f32,
    fog_previous_a: [fog_field.MAX_BANKS][4]f32,
    fog_previous_b: [fog_field.MAX_BANKS][4]f32,
    fog_previous_c: [fog_field.MAX_BANKS][4]f32,
    fog_settings:   [4]f32,
}

Dynamic_Shadow_Push :: struct {
    cascade: u32,
}

#assert(size_of(Dynamic_Shadow_Cascade_Uniform) == 64)
#assert(offset_of(Dynamic_Shadow_Uniform, settings) == 192)
#assert(offset_of(Dynamic_Shadow_Uniform, origin) == 208)
#assert(offset_of(Dynamic_Shadow_Uniform, fog_bank_a) == 224)
#assert(size_of(Dynamic_Shadow_Push) == 4)

Dynamic_Shadow_State :: struct {
    images:            [engine.MAX_FRAMES_IN_FLIGHT][DYNAMIC_SHADOW_CASCADE_COUNT]resources.Image,
    uniform:           [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    descriptors:       [engine.MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
    image_initialized: [engine.MAX_FRAMES_IN_FLIGHT][DYNAMIC_SHADOW_CASCADE_COUNT]bool,
    descriptor_layout: vk.DescriptorSetLayout,
    empty_layout:      vk.DescriptorSetLayout,
    descriptor_pool:   vk.DescriptorPool,
    sampler:           vk.Sampler,
    pipeline_layout:   vk.PipelineLayout,
    pipeline:          vk.Pipeline,
    transform:         Dynamic_Shadow_Uniform,
    anchor:            third_person.Vec3,
    caster_min_depth:  f32,
    caster_max_depth:  f32,
    enabled:           bool,
    frame_prepared:    bool,
}

dynamic_shadow_create_pipeline :: proc(state: ^Dynamic_Shadow_State, ctx: ^engine.Vk_Context) -> bool {
    shader: engine.Vk_Shader_Module
    if !engine.vk_load_shader_module_with_fallback(
        ctx,
        "assets/shaders/world.slang",
        "shaders/dynamic-shadow.vert",
        .Vertex,
        "dynamic_shadow_vertex",
        &shader,
    ) {
        return false
    }
    defer engine.vk_destroy_shader_module(ctx, &shader)

    stage := vk.PipelineShaderStageCreateInfo {
        sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage  = {.VERTEX},
        module = shader.handle,
        pName  = "main",
    }
    binding := vk.VertexInputBindingDescription {
        stride    = u32(size_of(World_Vertex)),
        inputRate = .VERTEX,
    }
    attribute := vk.VertexInputAttributeDescription {
        location = 0,
        format   = .R32G32B32_SFLOAT,
        offset   = u32(offset_of(World_Vertex, position)),
    }
    vertex_input := vk.PipelineVertexInputStateCreateInfo {
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount   = 1,
        pVertexBindingDescriptions      = &binding,
        vertexAttributeDescriptionCount = 1,
        pVertexAttributeDescriptions    = &attribute,
    }
    input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
        sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology = .TRIANGLE_LIST,
    }
    viewport_state := vk.PipelineViewportStateCreateInfo {
        sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount = 1,
        scissorCount  = 1,
    }
    raster := vk.PipelineRasterizationStateCreateInfo {
        sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        polygonMode             = .FILL,
        cullMode                = {.BACK},
        frontFace               = .COUNTER_CLOCKWISE,
        depthBiasEnable         = true,
        // Keep the stored depth close to the caster. Receiver-side normal bias
        // handles grazing surfaces; larger values here visibly detached feet,
        // tires, posts, and swing chains from their shadows.
        depthBiasConstantFactor = .35,
        depthBiasSlopeFactor    = .75,
        lineWidth               = 1,
    }
    multisample := vk.PipelineMultisampleStateCreateInfo {
        sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        rasterizationSamples = {._1},
    }
    depth := vk.PipelineDepthStencilStateCreateInfo {
        sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        depthTestEnable  = true,
        depthWriteEnable = true,
        depthCompareOp   = .LESS_OR_EQUAL,
    }
    dynamic_states := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}
    dynamic_state := vk.PipelineDynamicStateCreateInfo {
        sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        dynamicStateCount = 2,
        pDynamicStates    = raw_data(dynamic_states[:]),
    }
    depth_format := vk.Format.D32_SFLOAT
    rendering := vk.PipelineRenderingCreateInfo {
        sType                 = .PIPELINE_RENDERING_CREATE_INFO,
        colorAttachmentCount  = 0,
        depthAttachmentFormat = depth_format,
    }
    info := vk.GraphicsPipelineCreateInfo {
        sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
        pNext               = &rendering,
        stageCount          = 1,
        pStages             = &stage,
        pVertexInputState   = &vertex_input,
        pInputAssemblyState = &input_assembly,
        pViewportState      = &viewport_state,
        pRasterizationState = &raster,
        pMultisampleState   = &multisample,
        pDepthStencilState  = &depth,
        pDynamicState       = &dynamic_state,
        layout              = state.pipeline_layout,
    }
    if vk.CreateGraphicsPipelines(ctx.device, vk.PipelineCache(0), 1, &info, nil, &state.pipeline) != .SUCCESS {
        return false
    }
    engine.vk_set_debug_name(ctx, .PIPELINE, auto_cast state.pipeline, "dynamic sun shadow depth pipeline")
    return true
}

dynamic_shadow_create :: proc(state: ^Dynamic_Shadow_State, ctx: ^engine.Vk_Context) -> bool {
    if state == nil || ctx == nil do return false
    state^ = {}
    bindings := [5]vk.DescriptorSetLayoutBinding {
        {binding = 0, descriptorType = .UNIFORM_BUFFER, descriptorCount = 1, stageFlags = {.VERTEX, .FRAGMENT}},
        {binding = 1, descriptorType = .SAMPLED_IMAGE, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 2, descriptorType = .SAMPLED_IMAGE, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 3, descriptorType = .SAMPLED_IMAGE, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 4, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
    }
    layout_info := vk.DescriptorSetLayoutCreateInfo {
        sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        bindingCount = 5,
        pBindings    = raw_data(bindings[:]),
    }
    if vk.CreateDescriptorSetLayout(ctx.device, &layout_info, nil, &state.descriptor_layout) != .SUCCESS {
        return false
    }
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_SET_LAYOUT,
        auto_cast state.descriptor_layout,
        "dynamic shadow descriptor layout",
    )
    pool_sizes := [3]vk.DescriptorPoolSize {
        {type = .UNIFORM_BUFFER, descriptorCount = engine.MAX_FRAMES_IN_FLIGHT},
        {type = .SAMPLED_IMAGE, descriptorCount = engine.MAX_FRAMES_IN_FLIGHT * DYNAMIC_SHADOW_CASCADE_COUNT},
        {type = .SAMPLER, descriptorCount = engine.MAX_FRAMES_IN_FLIGHT},
    }
    pool_info := vk.DescriptorPoolCreateInfo {
        sType         = .DESCRIPTOR_POOL_CREATE_INFO,
        maxSets       = engine.MAX_FRAMES_IN_FLIGHT,
        poolSizeCount = 3,
        pPoolSizes    = raw_data(pool_sizes[:]),
    }
    if vk.CreateDescriptorPool(ctx.device, &pool_info, nil, &state.descriptor_pool) != .SUCCESS {
        dynamic_shadow_destroy(state, ctx)
        return false
    }
    engine.vk_set_debug_name(ctx, .DESCRIPTOR_POOL, auto_cast state.descriptor_pool, "dynamic shadow descriptor pool")
    layouts: [engine.MAX_FRAMES_IN_FLIGHT]vk.DescriptorSetLayout
    for &layout in layouts do layout = state.descriptor_layout
    allocate := vk.DescriptorSetAllocateInfo {
        sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool     = state.descriptor_pool,
        descriptorSetCount = engine.MAX_FRAMES_IN_FLIGHT,
        pSetLayouts        = raw_data(layouts[:]),
    }
    if vk.AllocateDescriptorSets(ctx.device, &allocate, raw_data(state.descriptors[:])) != .SUCCESS {
        dynamic_shadow_destroy(state, ctx)
        return false
    }
    sampler_info := vk.SamplerCreateInfo {
        sType         = .SAMPLER_CREATE_INFO,
        magFilter     = .LINEAR,
        minFilter     = .LINEAR,
        addressModeU  = .CLAMP_TO_BORDER,
        addressModeV  = .CLAMP_TO_BORDER,
        addressModeW  = .CLAMP_TO_BORDER,
        borderColor   = .FLOAT_OPAQUE_WHITE,
        compareEnable = true,
        compareOp     = .LESS_OR_EQUAL,
        minLod        = 0,
        maxLod        = 0,
    }
    if vk.CreateSampler(ctx.device, &sampler_info, nil, &state.sampler) != .SUCCESS {
        dynamic_shadow_destroy(state, ctx)
        return false
    }
    engine.vk_set_debug_name(ctx, .SAMPLER, auto_cast state.sampler, "dynamic shadow comparison sampler")
    for frame in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
        for cascade in 0 ..< DYNAMIC_SHADOW_CASCADE_COUNT {
            resolution := DYNAMIC_SHADOW_RESOLUTIONS[cascade]
            if !resources.image_create(
                ctx,
                resolution,
                resolution,
                .D32_SFLOAT,
                {.DEPTH_STENCIL_ATTACHMENT, .SAMPLED},
                {.DEPTH},
                {._1},
                &state.images[frame][cascade],
                "dynamic sun shadow cascade",
            ) {
                dynamic_shadow_destroy(state, ctx)
                return false
            }
        }
        if !engine.vk_create_host_buffer(
            ctx,
            vk.DeviceSize(size_of(Dynamic_Shadow_Uniform)),
            {.UNIFORM_BUFFER},
            &state.uniform[frame],
        ) {
            dynamic_shadow_destroy(state, ctx)
            return false
        }
        engine.vk_set_debug_name(
            ctx,
            .DESCRIPTOR_SET,
            auto_cast state.descriptors[frame],
            "dynamic shadow descriptor set",
        )
        buffer_info := vk.DescriptorBufferInfo {
            buffer = state.uniform[frame].handle,
            range  = vk.DeviceSize(size_of(Dynamic_Shadow_Uniform)),
        }
        image_infos: [DYNAMIC_SHADOW_CASCADE_COUNT]vk.DescriptorImageInfo
        for cascade in 0 ..< DYNAMIC_SHADOW_CASCADE_COUNT {
            image_infos[cascade] = {
                imageView   = state.images[frame][cascade].view,
                imageLayout = .DEPTH_READ_ONLY_OPTIMAL,
            }
        }
        sampler_descriptor := vk.DescriptorImageInfo {
            sampler = state.sampler,
        }
        writes: [5]vk.WriteDescriptorSet
        writes[0] = {
            sType           = .WRITE_DESCRIPTOR_SET,
            dstSet          = state.descriptors[frame],
            dstBinding      = 0,
            descriptorCount = 1,
            descriptorType  = .UNIFORM_BUFFER,
            pBufferInfo     = &buffer_info,
        }
        for cascade in 0 ..< DYNAMIC_SHADOW_CASCADE_COUNT {
            writes[cascade + 1] = {
                sType           = .WRITE_DESCRIPTOR_SET,
                dstSet          = state.descriptors[frame],
                dstBinding      = u32(cascade + 1),
                descriptorCount = 1,
                descriptorType  = .SAMPLED_IMAGE,
                pImageInfo      = &image_infos[cascade],
            }
        }
        writes[4] = {
            sType           = .WRITE_DESCRIPTOR_SET,
            dstSet          = state.descriptors[frame],
            dstBinding      = 4,
            descriptorCount = 1,
            descriptorType  = .SAMPLER,
            pImageInfo      = &sampler_descriptor,
        }
        vk.UpdateDescriptorSets(ctx.device, 5, raw_data(writes[:]), 0, nil)
    }
    push_range := vk.PushConstantRange {
        stageFlags = {.VERTEX},
        size       = u32(size_of(Dynamic_Shadow_Push)),
    }
    pipeline_layout_info := vk.PipelineLayoutCreateInfo {
        sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
        pushConstantRangeCount = 1,
        pPushConstantRanges    = &push_range,
    }
    empty_layout_info := vk.DescriptorSetLayoutCreateInfo {
        sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    }
    if vk.CreateDescriptorSetLayout(ctx.device, &empty_layout_info, nil, &state.empty_layout) != .SUCCESS {
        dynamic_shadow_destroy(state, ctx)
        return false
    }
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_SET_LAYOUT,
        auto_cast state.empty_layout,
        "dynamic shadow empty set layout",
    )
    pipeline_set_layouts := [2]vk.DescriptorSetLayout{state.empty_layout, state.descriptor_layout}
    pipeline_layout_info.setLayoutCount = 2
    pipeline_layout_info.pSetLayouts = raw_data(pipeline_set_layouts[:])
    if vk.CreatePipelineLayout(ctx.device, &pipeline_layout_info, nil, &state.pipeline_layout) != .SUCCESS {
        dynamic_shadow_destroy(state, ctx)
        return false
    }
    engine.vk_set_debug_name(ctx, .PIPELINE_LAYOUT, auto_cast state.pipeline_layout, "dynamic shadow pipeline layout")
    state.enabled = dynamic_shadow_create_pipeline(state, ctx)
    return true
}

dynamic_shadow_destroy :: proc(state: ^Dynamic_Shadow_State, ctx: ^engine.Vk_Context) {
    if state == nil || ctx == nil do return
    if state.pipeline != vk.Pipeline(0) do vk.DestroyPipeline(ctx.device, state.pipeline, nil)
    if state.pipeline_layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(ctx.device, state.pipeline_layout, nil)
    for frame in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
        for cascade in 0 ..< DYNAMIC_SHADOW_CASCADE_COUNT {
            resources.image_destroy(&state.images[frame][cascade], ctx)
        }
        engine.vk_destroy_buffer(ctx, &state.uniform[frame])
    }
    if state.sampler != vk.Sampler(0) do vk.DestroySampler(ctx.device, state.sampler, nil)
    if state.descriptor_pool != vk.DescriptorPool(0) do vk.DestroyDescriptorPool(ctx.device, state.descriptor_pool, nil)
    if state.descriptor_layout != vk.DescriptorSetLayout(0) do vk.DestroyDescriptorSetLayout(ctx.device, state.descriptor_layout, nil)
    if state.empty_layout != vk.DescriptorSetLayout(0) do vk.DestroyDescriptorSetLayout(ctx.device, state.empty_layout, nil)
    state^ = {}
}

shadow_append_triangle :: proc(a, b, c: third_person.Vec3) {
    color := world_color(canvas2d.Color{255, 255, 255, 255})
    append(
        &world_renderer.shadow_vertices,
        World_Vertex{{a.x, a.y, a.z}, color, .Unshaded, {0, 1, 0}, {}, {}},
        World_Vertex{{b.x, b.y, b.z}, color, .Unshaded, {0, 1, 0}, {}, {}},
        World_Vertex{{c.x, c.y, c.z}, color, .Unshaded, {0, 1, 0}, {}, {}},
    )
}

shadow_append_box :: proc(structure: terrain.Structure) {
    center := third_person.Vec3{structure.center_x, structure.base_y + structure.height * .5, structure.center_z}
    x, y, z := structure.width * .5, structure.height * .5, structure.depth * .5
    cosine, sine := f32(math.cos(f64(structure.rotation))), f32(math.sin(f64(structure.rotation)))
    local := [8]third_person.Vec3 {
        {-x, -y, -z},
        {x, -y, -z},
        {x, y, -z},
        {-x, y, -z},
        {-x, -y, z},
        {x, -y, z},
        {x, y, z},
        {-x, y, z},
    }
    p: [8]third_person.Vec3
    for value, index in local {
        p[index] = {
            center.x + value.x * cosine - value.z * sine,
            center.y + value.y,
            center.z + value.x * sine + value.z * cosine,
        }
    }
    faces := [12][3]int {
        {0, 2, 1},
        {0, 3, 2},
        {4, 5, 6},
        {4, 6, 7},
        {0, 4, 7},
        {0, 7, 3},
        {1, 2, 6},
        {1, 6, 5},
        {3, 7, 6},
        {3, 6, 2},
        {0, 1, 5},
        {0, 5, 4},
    }
    for face in faces do shadow_append_triangle(p[face[0]], p[face[1]], p[face[2]])
}

shadow_append_indexed :: proc(vertices: []World_Vertex, indices: []u32) -> bool {
    if len(vertices) == 0 || len(indices) < 3 do return false
    appended := false
    for triangle := 0; triangle + 2 < len(indices); triangle += 3 {
        a, b, c := int(indices[triangle]), int(indices[triangle + 1]), int(indices[triangle + 2])
        if a < 0 || b < 0 || c < 0 || a >= len(vertices) || b >= len(vertices) || c >= len(vertices) {
            continue
        }
        if !dynamic_shadow_material_casts(vertices[a].kind) ||
           !dynamic_shadow_material_casts(vertices[b].kind) ||
           !dynamic_shadow_material_casts(vertices[c].kind) {
            continue
        }
        append(&world_renderer.shadow_vertices, vertices[a], vertices[b], vertices[c])
        appended = true
    }
    return appended
}

shadow_instance_position :: proc(
    vertex: World_Vertex,
    instance: World_Mesh_Instance,
    wind_time, severity, wind_x, wind_z: f32,
) -> [3]f32 {
    position := third_person.Vec3 {
        instance.basis_x_translation_x[0] * vertex.position[0] +
        instance.basis_y_translation_y[0] * vertex.position[1] +
        instance.basis_z_translation_z[0] * vertex.position[2] +
        instance.basis_x_translation_x[3],
        instance.basis_x_translation_x[1] * vertex.position[0] +
        instance.basis_y_translation_y[1] * vertex.position[1] +
        instance.basis_z_translation_z[1] * vertex.position[2] +
        instance.basis_y_translation_y[3],
        instance.basis_x_translation_x[2] * vertex.position[0] +
        instance.basis_y_translation_y[2] * vertex.position[1] +
        instance.basis_z_translation_z[2] * vertex.position[2] +
        instance.basis_z_translation_z[3],
    }
    compliance := instance.plant_root_compliance[3]
    if compliance <= 0 do return {position.x, position.y, position.z}
    wind := third_person.Vec3{wind_x, 0, wind_z}
    wind_speed := f32(math.sqrt(f64(wind_x * wind_x + wind_z * wind_z)))
    wind_direction := wind_speed > .001 ? wind / wind_speed : third_person.Vec3{1, 0, 0}
    wind_across := third_person.Vec3{-wind_direction.z, 0, wind_direction.x}
    origin := third_person.Vec3 {
        instance.basis_x_translation_x[3],
        instance.basis_y_translation_y[3],
        instance.basis_z_translation_z[3],
    }
    root := third_person.Vec3 {
        instance.plant_root_compliance[0],
        instance.plant_root_compliance[1],
        instance.plant_root_compliance[2],
    }
    is_leaf := vertex.kind == .Leaf || vertex.kind == .Petal
    sample := is_leaf ? origin : position
    rooted := sample - root
    reach := f32(math.sqrt(f64(linalg.dot(rooted, rooted))))
    height_weight := clamp(rooted.y / max(reach, f32(.001)), f32(0), f32(1))
    bend_weight := (1 - f32(math.exp(f64(-reach * .72)))) * linalg.lerp(f32(.68), f32(1), height_weight)
    phase := wind_time * (.34 + wind_speed * .012) + instance.plant_motion[0]
    phase += (root.x * wind_direction.x + root.z * wind_direction.z) * .018
    phase += (root.x * wind_across.x + root.z * wind_across.z) * .006
    broad := math.sin(phase) + math.sin(phase * .47 + 1.9) * .34
    amplitude := linalg.lerp(f32(.08), f32(.48), clamp(wind_speed / 14 + severity * .24, f32(0), f32(1)))
    amplitude *= compliance * max(instance.plant_motion[1], f32(.05))
    broad_offset :=
        wind_direction * broad * amplitude * bend_weight +
        wind_across * math.sin(phase * 1.31 + 4.2) * amplitude * .07 * bend_weight
    broad_offset.y = -amplitude * .025 * bend_weight
    if is_leaf {
        flutter := math.sin(phase * 3.1 + instance.plant_motion[0] * 2.7)
        angle := flutter * amplitude * instance.plant_motion[2] * .12
        pivot_axis := linalg.normalize0(
            third_person.Vec3 {
                instance.basis_x_translation_x[0],
                instance.basis_x_translation_x[1],
                instance.basis_x_translation_x[2],
            },
        )
        from_pivot := position - origin
        cosine, sine := math.cos(angle), math.sin(angle)
        rotated :=
            from_pivot * cosine +
            linalg.cross(pivot_axis, from_pivot) * sine +
            pivot_axis * linalg.dot(pivot_axis, from_pivot) * (1 - cosine)
        position = origin + rotated + broad_offset
    } else {
        position += broad_offset
    }
    return {position.x, position.y, position.z}
}

shadow_plant_position :: proc(
    vertex: Plant_Vertex,
    instance: World_Mesh_Instance,
    wind_time, severity, wind_x, wind_z: f32,
) -> [3]f32 {
    transform := proc(value: [3]f32, instance: World_Mesh_Instance) -> third_person.Vec3 {
        return {
            instance.basis_x_translation_x[0] * value[0] +
            instance.basis_y_translation_y[0] * value[1] +
            instance.basis_z_translation_z[0] * value[2] +
            instance.basis_x_translation_x[3],
            instance.basis_x_translation_x[1] * value[0] +
            instance.basis_y_translation_y[1] * value[1] +
            instance.basis_z_translation_z[1] * value[2] +
            instance.basis_y_translation_y[3],
            instance.basis_x_translation_x[2] * value[0] +
            instance.basis_y_translation_y[2] * value[1] +
            instance.basis_z_translation_z[2] * value[2] +
            instance.basis_z_translation_z[3],
        }
    }
    position := transform(vertex.position, instance)
    root := third_person.Vec3 {
        instance.plant_root_compliance[0],
        instance.plant_root_compliance[1],
        instance.plant_root_compliance[2],
    }
    compliance := instance.plant_root_compliance[3]
    if compliance <= 0 do return position
    primary := transform(vertex.primary_anchor, instance)
    secondary := transform(vertex.secondary_anchor, instance)
    wind_speed := f32(math.sqrt(f64(wind_x * wind_x + wind_z * wind_z)))
    direction :=
        wind_speed > .001 ? third_person.Vec3{wind_x / wind_speed, 0, wind_z / wind_speed} : third_person.Vec3{1, 0, 0}
    across := third_person.Vec3{-direction.z, 0, direction.x}
    phase := wind_time * (.34 + wind_speed * .012) + instance.plant_motion[0]
    phase += (root.x * direction.x + root.z * direction.z) * .018
    amplitude := linalg.lerp(f32(.08), f32(.48), clamp(wind_speed / 14 + severity * .24, f32(0), f32(1)))
    amplitude *= compliance * max(instance.plant_motion[1], f32(.05))
    rooted, primary_offset, secondary_offset := position - root, position - primary, position - secondary
    root_weight := 1 - f32(math.exp(f64(-f32(math.sqrt(f64(linalg.dot(rooted, rooted)))) * .72)))
    primary_weight := 1 - f32(math.exp(f64(-f32(math.sqrt(f64(linalg.dot(primary_offset, primary_offset)))) * .92)))
    depth_weight := clamp(f32(vertex.hierarchy_depth) / 4, f32(0), f32(1))
    secondary_weight :=
        (1 - f32(math.exp(f64(-f32(math.sqrt(f64(linalg.dot(secondary_offset, secondary_offset)))) * 1.35)))) *
        depth_weight
    structural_compliance := linalg.lerp(f32(.35), f32(1.15), clamp(1 - vertex.stiffness, f32(0), f32(1)))
    broad := math.sin(phase) + math.sin(phase * .47 + 1.9) * .34
    position +=
        direction * broad * amplitude * structural_compliance *
        (root_weight * .55 + primary_weight * .32 + secondary_weight * .18)
    position +=
        across * math.sin(phase * 1.31 + vertex.phase + 4.2) * amplitude * structural_compliance * .07 *
        (primary_weight + secondary_weight)
    position.y -= amplitude * structural_compliance * .018 * root_weight
    if vertex.flutter > 0 && instance.plant_motion[2] > 0 {
        pivot := transform(vertex.leaf_pivot, instance)
        axis := linalg.normalize0(
            third_person.Vec3 {
                instance.basis_x_translation_x[0],
                instance.basis_x_translation_x[1],
                instance.basis_x_translation_x[2],
            },
        )
        angle :=
            math.sin(phase * 3.1 + vertex.phase * 2.7) * amplitude * vertex.flutter * instance.plant_motion[2] * .12
        from_pivot := position - pivot
        cosine, sine := math.cos(angle), math.sin(angle)
        position =
            pivot +
            from_pivot * cosine +
            linalg.cross(axis, from_pivot) * sine +
            axis * linalg.dot(axis, from_pivot) * (1 - cosine)
    }
    return position
}

shadow_plant_transition_visible :: proc(a, b, c: third_person.Vec3, opacity: f32) -> bool {
    if opacity >= .999 do return true
    if opacity <= .001 do return false
    x := f32(math.floor(f64((a.x + b.x + c.x) / 3 * 3.5))) + 17.3
    y := f32(math.floor(f64((a.z + b.z + c.z) / 3 * 3.5))) + 41.7
    fract := proc(value: f32) -> f32 {return value - f32(math.floor(f64(value)))}
    p3 := third_person.Vec3{fract(x * .1031), fract(y * .1031), fract(x * .1031)}
    dot_value := p3.x * (p3.y + 33.33) + p3.y * (p3.z + 33.33) + p3.z * (p3.x + 33.33)
    p3 += third_person.Vec3{dot_value, dot_value, dot_value}
    threshold := fract((p3.x + p3.y) * p3.z)
    return threshold <= clamp(opacity, f32(0), f32(1))
}

shadow_append_instances :: proc() {
    sky := atmosphere_sky(world_renderer.editor)
    for &mesh in world_renderer.instance_meshes {
        if !mesh.casts_shadow do continue
        vertex_first := int(mesh.first_vertex)
        index_first := int(mesh.first_index)
        index_count := int(mesh.index_count)
        if vertex_first < 0 ||
           index_first < 0 ||
           index_count < 3 ||
           index_first + index_count > len(world_renderer.instance_indices) {
            continue
        }
        for instance in mesh.instances {
            for triangle := index_first; triangle + 2 < index_first + index_count; triangle += 3 {
                a := vertex_first + int(world_renderer.instance_indices[triangle])
                b := vertex_first + int(world_renderer.instance_indices[triangle + 1])
                c := vertex_first + int(world_renderer.instance_indices[triangle + 2])
                if a < vertex_first ||
                   b < vertex_first ||
                   c < vertex_first ||
                   a >= len(world_renderer.instance_vertices) ||
                   b >= len(world_renderer.instance_vertices) ||
                   c >= len(world_renderer.instance_vertices) {
                    continue
                }
                pa := shadow_instance_position(
                    world_renderer.instance_vertices[a],
                    instance,
                    sky.cloud_time_seconds,
                    sky.weather.severity,
                    sky.weather.wind[0],
                    sky.weather.wind[1],
                )
                pb := shadow_instance_position(
                    world_renderer.instance_vertices[b],
                    instance,
                    sky.cloud_time_seconds,
                    sky.weather.severity,
                    sky.weather.wind[0],
                    sky.weather.wind[1],
                )
                pc := shadow_instance_position(
                    world_renderer.instance_vertices[c],
                    instance,
                    sky.cloud_time_seconds,
                    sky.weather.severity,
                    sky.weather.wind[0],
                    sky.weather.wind[1],
                )
                shadow_append_triangle({pa[0], pa[1], pa[2]}, {pb[0], pb[1], pb[2]}, {pc[0], pc[1], pc[2]})
            }
        }
    }
    for &mesh in world_renderer.plant_meshes {
        if !mesh.casts_shadow do continue
        vertex_first, index_first, index_count := int(mesh.first_vertex), int(mesh.first_index), int(mesh.index_count)
        if index_count < 3 || index_first < 0 || index_first + index_count > len(world_renderer.instance_indices) do continue
        for instance in mesh.instances {
            for triangle := index_first; triangle + 2 < index_first + index_count; triangle += 3 {
                a := vertex_first + int(world_renderer.instance_indices[triangle])
                b := vertex_first + int(world_renderer.instance_indices[triangle + 1])
                c := vertex_first + int(world_renderer.instance_indices[triangle + 2])
                if a < vertex_first || b < vertex_first || c < vertex_first || a >= len(world_renderer.plant_vertices) || b >= len(world_renderer.plant_vertices) || c >= len(world_renderer.plant_vertices) do continue
                pa := shadow_plant_position(
                    world_renderer.plant_vertices[a],
                    instance,
                    sky.cloud_time_seconds,
                    sky.weather.severity,
                    sky.weather.wind[0],
                    sky.weather.wind[1],
                )
                pb := shadow_plant_position(
                    world_renderer.plant_vertices[b],
                    instance,
                    sky.cloud_time_seconds,
                    sky.weather.severity,
                    sky.weather.wind[0],
                    sky.weather.wind[1],
                )
                pc := shadow_plant_position(
                    world_renderer.plant_vertices[c],
                    instance,
                    sky.cloud_time_seconds,
                    sky.weather.severity,
                    sky.weather.wind[0],
                    sky.weather.wind[1],
                )
                if !shadow_plant_transition_visible(pa, pb, pc, instance.plant_motion[3]) do continue
                shadow_append_triangle(pa, pb, pc)
            }
        }
    }
}

shadow_append_middle_tree_proxies :: proc() {
    for proxy in world_renderer.middle_tree_shadow_proxies {
        dx := proxy.center.x - world_renderer.dynamic_shadow.anchor.x
        dz := proxy.center.z - world_renderer.dynamic_shadow.anchor.z
        permitted := DYNAMIC_SHADOW_PROXY_RADIUS + max(proxy.radius_x, proxy.radius_z)
        if dx * dx + dz * dz > permitted * permitted do continue
        top := proxy.center + third_person.Vec3{0, proxy.radius_y, 0}
        bottom := proxy.center - third_person.Vec3{0, proxy.radius_y, 0}
        east := proxy.center + third_person.Vec3{proxy.radius_x, 0, 0}
        west := proxy.center - third_person.Vec3{proxy.radius_x, 0, 0}
        north := proxy.center + third_person.Vec3{0, 0, proxy.radius_z}
        south := proxy.center - third_person.Vec3{0, 0, proxy.radius_z}
        shadow_append_triangle(top, east, north)
        shadow_append_triangle(top, north, west)
        shadow_append_triangle(top, west, south)
        shadow_append_triangle(top, south, east)
        shadow_append_triangle(bottom, north, east)
        shadow_append_triangle(bottom, west, north)
        shadow_append_triangle(bottom, south, west)
        shadow_append_triangle(bottom, east, south)
    }
}

shadow_append_raised_roads :: proc(editor: ^Editor) {
    vertices := world_renderer.road_geometry_cache[:]
    for triangle := 0; triangle + 2 < len(vertices); triangle += 3 {
        a, b, c := vertices[triangle], vertices[triangle + 1], vertices[triangle + 2]
        center_x := (a.position[0] + b.position[0] + c.position[0]) / 3
        center_z := (a.position[2] + b.position[2] + c.position[2]) / 3
        dx := center_x - world_renderer.dynamic_shadow.anchor.x
        dz := center_z - world_renderer.dynamic_shadow.anchor.z
        if dx * dx + dz * dz > DYNAMIC_SHADOW_PROXY_RADIUS * DYNAMIC_SHADOW_PROXY_RADIUS do continue
        terrain_a := terrain.sample_surface_height(&editor.project, 0, a.position[0], a.position[2])
        terrain_b := terrain.sample_surface_height(&editor.project, 0, b.position[0], b.position[2])
        terrain_c := terrain.sample_surface_height(&editor.project, 0, c.position[0], c.position[2])
        clearance := max(a.position[1] - terrain_a, max(b.position[1] - terrain_b, c.position[1] - terrain_c))
        vertical_span :=
            max(a.position[1], max(b.position[1], c.position[1])) -
            min(a.position[1], min(b.position[1], c.position[1]))
        // Ordinary pavement hugs the receiver and would only introduce acne.
        // Elevated decks, curbs, retaining faces, and bridge details clear
        // this threshold and cast their actual cached triangles.
        if clearance <= .045 && vertical_span <= .08 do continue
        append(&world_renderer.shadow_vertices, a, b, c)
    }
}

dynamic_shadow_terrain_cache_matches :: #force_inline proc(
    cache: ^Dynamic_Shadow_Terrain_Cache,
    project_revision, terrain_revision: u64,
    start_x, start_z: f32,
) -> bool {
    return(
        cache != nil &&
        cache.valid &&
        cache.project_revision == project_revision &&
        cache.terrain_revision == terrain_revision &&
        cache.start_x == start_x &&
        cache.start_z == start_z \
    )
}

when ODIN_TEST {
    @(test)
    dynamic_shadow_terrain_cache_keys_world_revision_and_grid_origin :: proc(t: ^testing.T) {
        cache := Dynamic_Shadow_Terrain_Cache {
            valid            = true,
            project_revision = 7,
            terrain_revision = 11,
            start_x          = -160,
            start_z          = 75,
        }
        testing.expect(t, dynamic_shadow_terrain_cache_matches(&cache, 7, 11, -160, 75))
        testing.expect(t, !dynamic_shadow_terrain_cache_matches(&cache, 8, 11, -160, 75))
        testing.expect(t, !dynamic_shadow_terrain_cache_matches(&cache, 7, 12, -160, 75))
        testing.expect(t, !dynamic_shadow_terrain_cache_matches(&cache, 7, 11, -155, 75))
        testing.expect(t, !dynamic_shadow_terrain_cache_matches(&cache, 7, 11, -160, 80))
    }
}

shadow_append_terrain :: proc(editor: ^Editor) {
    // One sun-space terrain mesh is shared by all cascades. A five-metre grid
    // resolves the large landforms that produce meaningful cast shadows while
    // avoiding a second full clipmap build in the CPU submission path.
    coverage := DYNAMIC_SHADOW_COVERAGES[DYNAMIC_SHADOW_CASCADE_COUNT - 1]
    step := coverage / DYNAMIC_SHADOW_TERRAIN_GRID_CELLS
    start_x := math.floor((world_renderer.dynamic_shadow.anchor.x - coverage * .5) / step) * step
    start_z := math.floor((world_renderer.dynamic_shadow.anchor.z - coverage * .5) / step) * step
    cache := &world_renderer.dynamic_shadow_terrain_cache
    if dynamic_shadow_terrain_cache_matches(
        cache,
        editor.project.revision,
        editor.terrain_revision,
        start_x,
        start_z,
    ) {
        world_renderer.dynamic_shadow_terrain_cache_reuses += 1
        profile := dio.flame_graph_begin(dio.flame_graph_current(), "shadow_terrain_cache_reuse")
        append(&world_renderer.shadow_vertices, ..cache.vertices[:])
        _ = dio.flame_graph_end(dio.flame_graph_current(), profile)
        return
    }
    world_renderer.dynamic_shadow_terrain_cache_builds += 1
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "shadow_terrain_cache_build")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    first := len(world_renderer.shadow_vertices)
    heights: [DYNAMIC_SHADOW_TERRAIN_GRID_CELLS + 1][DYNAMIC_SHADOW_TERRAIN_GRID_CELLS + 1]f32
    for z in 0 ..= DYNAMIC_SHADOW_TERRAIN_GRID_CELLS {
        for x in 0 ..= DYNAMIC_SHADOW_TERRAIN_GRID_CELLS {
            world_x := start_x + f32(x) * step
            world_z := start_z + f32(z) * step
            heights[z][x] = terrain.sample_surface_height(&editor.project, 0, world_x, world_z)
        }
    }
    for z in 0 ..< DYNAMIC_SHADOW_TERRAIN_GRID_CELLS {
        for x in 0 ..< DYNAMIC_SHADOW_TERRAIN_GRID_CELLS {
            x0, x1 := start_x + f32(x) * step, start_x + f32(x + 1) * step
            z0, z1 := start_z + f32(z) * step, start_z + f32(z + 1) * step
            a := third_person.Vec3{x0, heights[z][x], z0}
            b := third_person.Vec3{x1, heights[z][x + 1], z0}
            c := third_person.Vec3{x1, heights[z + 1][x + 1], z1}
            d := third_person.Vec3{x0, heights[z + 1][x], z1}
            shadow_append_triangle(a, c, b)
            shadow_append_triangle(a, d, c)
        }
    }
    clear(&cache.vertices)
    append(&cache.vertices, ..world_renderer.shadow_vertices[first:])
    cache.start_x = start_x
    cache.start_z = start_z
    cache.project_revision = editor.project.revision
    cache.terrain_revision = editor.terrain_revision
    cache.valid = true
}

shadow_append_grass_cards :: proc(editor: ^Editor, instances: []Grass_Instance, radius, density: f32) {
    sky := atmosphere_sky(editor)
    sun_x, sun_z := sky.sun_direction[0], sky.sun_direction[2]
    horizontal := f32(math.sqrt(f64(sun_x * sun_x + sun_z * sun_z)))
    right := third_person.Vec3{1, 0, 0}
    if horizontal > .001 do right = {-sun_z / horizontal, 0, sun_x / horizontal}
    radius_squared := radius * radius
    for instance in instances {
        dx := instance.center[0] - world_renderer.dynamic_shadow.anchor.x
        dz := instance.center[2] - world_renderer.dynamic_shadow.anchor.z
        if dx * dx + dz * dz > radius_squared do continue
        if instance.cull_params[0] > density do continue
        half_width := max(instance.size[0] * .16, f32(.015))
        height := max(instance.size[1] * .88, f32(.04))
        base := third_person.Vec3{instance.center[0], instance.center[1] - instance.size[1] * .5, instance.center[2]}
        a, b := base - right * half_width, base + right * half_width
        c, d := b + third_person.Vec3{0, height, 0}, a + third_person.Vec3{0, height, 0}
        shadow_append_triangle(a, c, b)
        shadow_append_triangle(a, d, c)
        shadow_append_triangle(b, c, a)
        shadow_append_triangle(c, d, a)
    }
}

dynamic_shadow_resolve_anchor :: proc(editor: ^Editor) -> third_person.Vec3 {
    if lab_scene_is_active(editor, "boat") {
        // The inspection camera is outside the fleet. Keep shadow allocation,
        // caster culling, and receiver cascade selection centered on the map.
        return {0, editor.project.sea_level, 0}
    }
    anchor := editor.camera_pose.position
    anchor.y = terrain.sample_surface_height(&editor.project, 0, anchor.x, anchor.z)
    return anchor
}

dynamic_shadow_range_is_covered :: #force_inline proc(candidate, covering: World_Shadow_Caster_Range) -> bool {
    return(
        candidate.count > 0 &&
        candidate.first >= covering.first &&
        candidate.first + candidate.count <= covering.first + covering.count \
    )
}

world_register_shadow_caster :: #force_inline proc(first: int) {
    count := len(world_renderer.vertices) - first
    if first < 0 || count <= 0 do return
    candidate := World_Shadow_Caster_Range {
        first = first,
        count = count,
    }
    for &existing in world_renderer.explicit_shadow_caster_ranges {
        if dynamic_shadow_range_is_covered(candidate, existing) do return
        if dynamic_shadow_range_is_covered(existing, candidate) {
            existing = candidate
            return
        }
    }
    append(&world_renderer.explicit_shadow_caster_ranges, candidate)
}

world_register_static_shadow_caster :: #force_inline proc(first, count: int, minimum, maximum: third_person.Vec3) {
    if first < 0 || count < 3 do return
    append(
        &world_renderer.static_shadow_caster_ranges,
        World_Static_Shadow_Caster_Range{first = first, count = count, minimum = minimum, maximum = maximum},
    )
}

dynamic_shadow_material_casts :: #force_inline proc(kind: World_Material_Kind) -> bool {
    #partial switch kind {
    case .Unshaded,
         .Water,
         .Emissive,
         .Emissive_Pool,
         .Glass,
         .Emissive_Halo,
         .Lighthouse_Glitter,
         .Fountain_Water,
         .Fog_Shell:
        return false
    }
    return true
}

shadow_append_world_draw_range :: #force_inline proc(first, count: int) {
    if count <= 0 do return
    if len(world_renderer.shadow_world_ranges) > 0 {
        previous := &world_renderer.shadow_world_ranges[len(world_renderer.shadow_world_ranges) - 1]
        if previous.first + previous.count == first {
            previous.count += count
            return
        }
    }
    append(&world_renderer.shadow_world_ranges, World_Shadow_Caster_Range{first = first, count = count})
}

shadow_depth_include :: #force_inline proc(
    vertex: World_Vertex,
    forward: third_person.Vec3,
    min_depth, max_depth: ^f32,
) {
    depth := vertex.position[0] * forward.x + vertex.position[1] * forward.y + vertex.position[2] * forward.z
    min_depth^ = min(min_depth^, depth)
    max_depth^ = max(max_depth^, depth)
}

shadow_depth_include_bounds :: #force_inline proc(
    minimum, maximum: third_person.Vec3,
    forward: third_person.Vec3,
    min_depth, max_depth: ^f32,
) {
    xs := [2]f32{minimum.x, maximum.x}
    ys := [2]f32{minimum.y, maximum.y}
    zs := [2]f32{minimum.z, maximum.z}
    for x in xs {
        for y in ys {
            for z in zs {
                depth := x * forward.x + y * forward.y + z * forward.z
                min_depth^ = min(min_depth^, depth)
                max_depth^ = max(max_depth^, depth)
            }
        }
    }
}

shadow_append_world_range :: proc(first, count: int, forward: third_person.Vec3, min_depth, max_depth: ^f32) {
    if first < 0 || count < 3 || first + count > len(world_renderer.vertices) do return
    end := first + count
    run_first := -1
    for triangle := first; triangle + 2 < end; triangle += 3 {
        a, b, c :=
            world_renderer.vertices[triangle],
            world_renderer.vertices[triangle + 1],
            world_renderer.vertices[triangle + 2]
        if !dynamic_shadow_material_casts(a.kind) ||
           !dynamic_shadow_material_casts(b.kind) ||
           !dynamic_shadow_material_casts(c.kind) {
            if run_first >= 0 {
                shadow_append_world_draw_range(run_first, triangle - run_first)
                run_first = -1
            }
            continue
        }
        if run_first < 0 do run_first = triangle
        shadow_depth_include(a, forward, min_depth, max_depth)
        shadow_depth_include(b, forward, min_depth, max_depth)
        shadow_depth_include(c, forward, min_depth, max_depth)
    }
    if run_first >= 0 do shadow_append_world_draw_range(run_first, end - run_first)
}

dynamic_shadow_build_casters :: proc(editor: ^Editor) {
    clear(&world_renderer.shadow_vertices)
    clear(&world_renderer.shadow_world_ranges)
    sky := atmosphere_sky(editor)
    forward := third_person.Vec3{-sky.sun_direction[0], -sky.sun_direction[1], -sky.sun_direction[2]}
    forward_length := f32(math.sqrt(f64(forward.x * forward.x + forward.y * forward.y + forward.z * forward.z)))
    if forward_length > .0001 {
        forward.x /= forward_length; forward.y /= forward_length; forward.z /= forward_length
    }
    min_depth, max_depth := f32(1e30), f32(-1e30)
    world_scope := dio.flame_graph_begin(dio.flame_graph_current(), "shadow_casters_world")
    first := world_renderer.dynamic_caster_first
    count := world_renderer.dynamic_caster_count
    dynamic_range := World_Shadow_Caster_Range {
        first = first,
        count = count,
    }
    if first >= 0 && count > 0 && first + count <= len(world_renderer.vertices) {
        shadow_append_world_range(first, count, forward, &min_depth, &max_depth)
    }
    // Generated plants and foliage register exact ranges because they can be
    // submitted outside the broad gameplay caster span. Avoid submitting a
    // range twice when gameplay already covers it completely.
    for caster_range in world_renderer.explicit_shadow_caster_ranges {
        if dynamic_shadow_range_is_covered(caster_range, dynamic_range) do continue
        if caster_range.first < 0 ||
           caster_range.count <= 0 ||
           caster_range.first + caster_range.count > len(world_renderer.vertices) {
            continue
        }
        shadow_append_world_range(caster_range.first, caster_range.count, forward, &min_depth, &max_depth)
    }
    for caster_range in world_renderer.static_shadow_caster_ranges {
        if dynamic_shadow_range_is_covered({first = caster_range.first, count = caster_range.count}, dynamic_range) {
            continue
        }
        shadow_append_world_draw_range(caster_range.first, caster_range.count)
        shadow_depth_include_bounds(caster_range.minimum, caster_range.maximum, forward, &min_depth, &max_depth)
    }
    _ = dio.flame_graph_end(dio.flame_graph_current(), world_scope)
    world_renderer.dynamic_shadow.caster_min_depth = min_depth
    world_renderer.dynamic_shadow.caster_max_depth = max_depth

    instances_scope := dio.flame_graph_begin(dio.flame_graph_current(), "shadow_casters_instances")
    shadow_append_instances()
    shadow_append_middle_tree_proxies()
    _ = dio.flame_graph_end(dio.flame_graph_current(), instances_scope)

    roads_scope := dio.flame_graph_begin(dio.flame_graph_current(), "shadow_casters_raised_roads")
    shadow_append_raised_roads(editor)
    _ = dio.flame_graph_end(dio.flame_graph_current(), roads_scope)

    terrain_scope := dio.flame_graph_begin(dio.flame_graph_current(), "shadow_casters_terrain")
    shadow_append_terrain(editor)
    _ = dio.flame_graph_end(dio.flame_graph_current(), terrain_scope)

    vegetation_scope := dio.flame_graph_begin(dio.flame_graph_current(), "shadow_casters_vegetation")
    shadow_append_grass_cards(editor, world_renderer.grass_instances[:], 36, .34)
    shadow_append_grass_cards(editor, world_renderer.wildflower_instances[:], 58, .68)
    shadow_append_grass_cards(editor, world_renderer.marsh_instances[:], 92, 1)
    _ = dio.flame_graph_end(dio.flame_graph_current(), vegetation_scope)

    structures_scope := dio.flame_graph_begin(dio.flame_graph_current(), "shadow_casters_structures")
    inverse_sun_y := 1 / max(sky.sun_direction[1], f32(.08))
    for structure, structure_index in editor.project.structures[:editor.project.structure_count] {
        if structure.kind == .Foliage do continue
        // Bound the complete ground-projected shadow segment, not merely the
        // caster center. At low sun angles an off-map building can still cast
        // well into the far receiver cascade.
        shadow_x := -sky.sun_direction[0] * structure.height * inverse_sun_y
        shadow_z := -sky.sun_direction[2] * structure.height * inverse_sun_y
        shadow_mid_x := structure.center_x + shadow_x * .5
        shadow_mid_z := structure.center_z + shadow_z * .5
        half_shadow_length := f32(math.sqrt(f64(shadow_x * shadow_x + shadow_z * shadow_z))) * .5
        caster_radius :=
            f32(math.sqrt(f64(structure.width * structure.width + structure.depth * structure.depth))) * .5
        conservative_radius := DYNAMIC_SHADOW_PROXY_RADIUS + half_shadow_length + caster_radius
        dx := shadow_mid_x - world_renderer.dynamic_shadow.anchor.x
        dz := shadow_mid_z - world_renderer.dynamic_shadow.anchor.z
        if dx * dx + dz * dz > conservative_radius * conservative_radius do continue
        exact := false
        if structure_index >= 0 && structure_index < len(world_renderer.static_geometry_cache) {
            entry := &world_renderer.static_geometry_cache[structure_index]
            if entry.valid && entry.structure == structure {
                exact = shadow_append_indexed(entry.world_vertices[:], entry.world_indices[:])
            }
        }
        // Off-camera structures may not have a retained mesh yet. Keep a
        // conservative proxy until their exact cache becomes available so a
        // low sun cannot reveal a missing caster at the cascade edge.
        if !exact do shadow_append_box(structure)
    }
    _ = dio.flame_graph_end(dio.flame_graph_current(), structures_scope)
}

dynamic_shadow_update_transform :: proc(editor: ^Editor, frame_index: int) {
    state := &world_renderer.dynamic_shadow
    sky := atmosphere_sky(editor)
    anchor := state.anchor
    sun := third_person.Vec3{sky.sun_direction[0], sky.sun_direction[1], sky.sun_direction[2]}
    forward := third_person.Vec3{-sun.x, -sun.y, -sun.z}
    forward_length := f32(math.sqrt(f64(forward.x * forward.x + forward.y * forward.y + forward.z * forward.z)))
    if forward_length > .0001 {
        forward.x /= forward_length; forward.y /= forward_length; forward.z /= forward_length
    }
    right := third_person.Vec3{forward.z, 0, -forward.x}
    right_length := f32(math.sqrt(f64(right.x * right.x + right.z * right.z)))
    if right_length < .001 {
        right = {1, 0, 0}
    } else {
        right.x /= right_length; right.z /= right_length
    }
    up := third_person.Vec3 {
        forward.y * right.z - forward.z * right.y,
        forward.z * right.x - forward.x * right.z,
        forward.x * right.y - forward.y * right.x,
    }
    min_depth, max_depth := state.caster_min_depth, state.caster_max_depth
    depth_supplementary_scope := dio.flame_graph_begin(dio.flame_graph_current(), "shadow_depth_bounds_supplementary")
    for vertex in world_renderer.shadow_vertices {
        depth := vertex.position[0] * forward.x + vertex.position[1] * forward.y + vertex.position[2] * forward.z
        min_depth = min(min_depth, depth)
        max_depth = max(max_depth, depth)
    }
    _ = dio.flame_graph_end(dio.flame_graph_current(), depth_supplementary_scope)
    if min_depth > max_depth {
        min_depth, max_depth = -100, 100
    }
    min_depth -= 24
    max_depth += 24
    strength := f32(0)
    if sky.sun_direction[1] > .08 do strength = (1 - clamp(sky.weather.cloud_cover, f32(0), f32(1)) * .72)
    for cascade in 0 ..< DYNAMIC_SHADOW_CASCADE_COUNT {
        coverage := DYNAMIC_SHADOW_COVERAGES[cascade]
        resolution := DYNAMIC_SHADOW_RESOLUTIONS[cascade]
        anchor_right := anchor.x * right.x + anchor.y * right.y + anchor.z * right.z
        anchor_up := anchor.x * up.x + anchor.y * up.y + anchor.z * up.z
        texel_world := coverage / f32(resolution)
        anchor_right = math.floor(anchor_right / texel_world) * texel_world
        anchor_up = math.floor(anchor_up / texel_world) * texel_world
        state.transform.cascades[cascade] = {
            right   = {right.x, right.y, right.z, anchor_right},
            up      = {up.x, up.y, up.z, anchor_up},
            forward = {forward.x, forward.y, forward.z, min_depth},
            params  = {coverage, 1 / max(max_depth - min_depth, f32(1)), strength, 1 / f32(resolution)},
        }
    }
    state.transform.settings = {
        DYNAMIC_SHADOW_COVERAGES[0] * .42,
        DYNAMIC_SHADOW_COVERAGES[1] * .42,
        DYNAMIC_SHADOW_COVERAGES[2] * .42,
        strength,
    }
    state.transform.origin = {anchor.x, anchor.y, anchor.z, 0}
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    field := fog_field.generate(
        editor.atmosphere.seed,
        editor.atmosphere.front_seconds,
        editor.atmosphere.weather,
        {{-half_extent, -half_extent}, {half_extent, half_extent}},
        editor.atmosphere.climate.current,
    )
    for bank, index in field.banks {
        state.transform.fog_bank_a[index] = {bank.center.x, bank.center.y, bank.radii.x, bank.radii.y}
        state.transform.fog_bank_b[index] = {bank.axis.x, bank.axis.y, bank.base_altitude, bank.top_altitude}
        state.transform.fog_bank_c[index] = {bank.edge_softness, bank.peak_density, 0, 0}
        previous := field.previous_banks[index]
        state.transform.fog_previous_a[index] = {
            previous.center.x,
            previous.center.y,
            previous.radii.x,
            previous.radii.y,
        }
        state.transform.fog_previous_b[index] = {
            previous.axis.x,
            previous.axis.y,
            previous.base_altitude,
            previous.top_altitude,
        }
        state.transform.fog_previous_c[index] = {previous.edge_softness, previous.peak_density, 0, 0}
    }
    state.transform.fog_settings = {
        field.global_density * (fog_debug_enabled ? fog_debug_density_multiplier : 0),
        field.blend,
        field.time_seconds,
        clamp(editor.atmosphere.weather.severity, 0, 1),
    }
    mem.copy_non_overlapping(state.uniform[frame_index].mapped, &state.transform, size_of(Dynamic_Shadow_Uniform))
}

dynamic_shadow_render :: proc(pass: ^canvas2d.World_Pass_Context, frame_index: int) {
    state := &world_renderer.dynamic_shadow
    if !state.enabled ||
       state.transform.settings[3] <= 0 ||
       (len(world_renderer.shadow_vertices) == 0 && len(world_renderer.shadow_world_ranges) == 0) {
        return
    }
    cmd := pass.frame.command_buffer
    vk.CmdBindPipeline(cmd, .GRAPHICS, state.pipeline)
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, state.pipeline_layout, 1, 1, &state.descriptors[frame_index], 0, nil)
    offset := vk.DeviceSize(0)
    for cascade in 0 ..< DYNAMIC_SHADOW_CASCADE_COUNT {
        image := &state.images[frame_index][cascade]
        initialized := state.image_initialized[frame_index][cascade]
        engine.vk_cmd_image_barrier2(
            pass.ctx,
            cmd,
            image.image,
            initialized ? vk.PipelineStageFlags2{.FRAGMENT_SHADER} : vk.PipelineStageFlags2{.TOP_OF_PIPE},
            {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS},
            initialized ? vk.AccessFlags2{.SHADER_READ} : vk.AccessFlags2{},
            {.DEPTH_STENCIL_ATTACHMENT_WRITE},
            initialized ? vk.ImageLayout.DEPTH_READ_ONLY_OPTIMAL : vk.ImageLayout.UNDEFINED,
            .DEPTH_ATTACHMENT_OPTIMAL,
            {.DEPTH},
        )
        clear := vk.ClearValue {
            depthStencil = {depth = 1},
        }
        attachment := vk.RenderingAttachmentInfo {
            sType       = .RENDERING_ATTACHMENT_INFO,
            imageView   = image.view,
            imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
            loadOp      = .CLEAR,
            storeOp     = .STORE,
            clearValue  = clear,
        }
        resolution := DYNAMIC_SHADOW_RESOLUTIONS[cascade]
        rendering := vk.RenderingInfo {
            sType = .RENDERING_INFO,
            renderArea = {extent = {resolution, resolution}},
            layerCount = 1,
            pDepthAttachment = &attachment,
        }
        vk.CmdBeginRendering(cmd, &rendering)
        viewport := vk.Viewport {
            width    = f32(resolution),
            height   = f32(resolution),
            minDepth = 0,
            maxDepth = 1,
        }
        scissor := vk.Rect2D {
            extent = {resolution, resolution},
        }
        vk.CmdSetViewport(cmd, 0, 1, &viewport)
        vk.CmdSetScissor(cmd, 0, 1, &scissor)
        push := Dynamic_Shadow_Push {
            cascade = u32(cascade),
        }
        vk.CmdPushConstants(cmd, state.pipeline_layout, {.VERTEX}, 0, u32(size_of(Dynamic_Shadow_Push)), &push)
        if len(world_renderer.shadow_world_ranges) > 0 {
            vk.CmdBindVertexBuffers(cmd, 0, 1, &world_renderer.vertex[frame_index].handle, &offset)
            for caster_range in world_renderer.shadow_world_ranges {
                vk.CmdDraw(cmd, u32(caster_range.count), 1, u32(caster_range.first), 0)
            }
        }
        if len(world_renderer.shadow_vertices) > 0 {
            vk.CmdBindVertexBuffers(cmd, 0, 1, &world_renderer.shadow_vertex[frame_index].handle, &offset)
            vk.CmdDraw(cmd, u32(len(world_renderer.shadow_vertices)), 1, 0, 0)
        }
        vk.CmdEndRendering(cmd)
        engine.vk_cmd_image_barrier2(
            pass.ctx,
            cmd,
            image.image,
            {.LATE_FRAGMENT_TESTS},
            {.FRAGMENT_SHADER},
            {.DEPTH_STENCIL_ATTACHMENT_WRITE},
            {.SHADER_READ},
            .DEPTH_ATTACHMENT_OPTIMAL,
            .DEPTH_READ_ONLY_OPTIMAL,
            {.DEPTH},
        )
        state.image_initialized[frame_index][cascade] = true
    }
}
