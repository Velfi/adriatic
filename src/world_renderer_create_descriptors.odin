package main

import particles "../packages/particles"
import terrain "../packages/terrain"
import "core:fmt"
import vk "vendor:vulkan"
import engine "zelda_engine:engine"
import resources "zelda_engine:render_resources"

world_renderer_create_descriptors :: proc(ctx: ^engine.Vk_Context, failure_stage: ^string) -> bool {
    paint_bindings := [16]vk.DescriptorSetLayoutBinding {
        {binding = 0, descriptorType = .SAMPLED_IMAGE, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 1, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 2, descriptorType = .SAMPLED_IMAGE, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 3, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 4, descriptorType = .SAMPLED_IMAGE, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 5, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 6, descriptorType = .SAMPLED_IMAGE, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 7, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 8, descriptorType = .SAMPLED_IMAGE, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 9, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 10, descriptorType = .SAMPLED_IMAGE, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 11, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 12, descriptorType = .SAMPLED_IMAGE, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 13, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 14, descriptorType = .SAMPLED_IMAGE, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 15, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
    }
    paint_layout_info := vk.DescriptorSetLayoutCreateInfo {
        sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        bindingCount = 16,
        pBindings    = raw_data(paint_bindings[:]),
    }
    if vk.CreateDescriptorSetLayout(ctx.device, &paint_layout_info, nil, &world_renderer.vehicle_paint_descriptor_layout) != .SUCCESS do return false
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_SET_LAYOUT,
        auto_cast world_renderer.vehicle_paint_descriptor_layout,
        "vehicle paint descriptor set layout",
    )
    paint_pool_sizes := [2]vk.DescriptorPoolSize {
        {type = .SAMPLED_IMAGE, descriptorCount = 8},
        {type = .SAMPLER, descriptorCount = 8},
    }
    paint_pool_info := vk.DescriptorPoolCreateInfo {
        sType         = .DESCRIPTOR_POOL_CREATE_INFO,
        maxSets       = 1,
        poolSizeCount = 2,
        pPoolSizes    = raw_data(paint_pool_sizes[:]),
    }
    if vk.CreateDescriptorPool(ctx.device, &paint_pool_info, nil, &world_renderer.vehicle_paint_descriptor_pool) != .SUCCESS do return false
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_POOL,
        auto_cast world_renderer.vehicle_paint_descriptor_pool,
        "vehicle paint descriptor pool",
    )
    paint_allocate := vk.DescriptorSetAllocateInfo {
        sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool     = world_renderer.vehicle_paint_descriptor_pool,
        descriptorSetCount = 1,
        pSetLayouts        = &world_renderer.vehicle_paint_descriptor_layout,
    }
    if vk.AllocateDescriptorSets(ctx.device, &paint_allocate, &world_renderer.vehicle_paint_descriptor) != .SUCCESS do return false
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_SET,
        auto_cast world_renderer.vehicle_paint_descriptor,
        "vehicle paint descriptor set",
    )
    failure_stage^ = "vehicle paint atlas"
    if !vehicle_paint_atlas_create(ctx, &world_renderer.vehicle_paint_atlas) do return false
    failure_stage^ = "soda cap texture"
    if !resources.texture_load_file(
        ctx,
        "assets/textures/accessories/soda-cap-logo.png",
        &world_renderer.soda_cap_logo,
        {address_mode = .CLAMP_TO_EDGE},
    ) {
        return false
    }
    failure_stage^ = "architecture material atlas"
    if !resources.texture_load_file(
        ctx,
        "assets/textures/architecture/material-atlas.png",
        &world_renderer.architecture_material_atlas,
        {address_mode = .CLAMP_TO_EDGE},
    ) {
        // Architecture texturing is optional presentation detail. Do not let a
        // malformed, oversized, or temporarily unavailable authoring atlas
        // disable the terrain and the rest of the world renderer.
        fallback_pixels := [4]u8{190, 190, 190, 255}
        if !resources.texture_upload_rgba8(
            ctx,
            fallback_pixels[:],
            1,
            1,
            &world_renderer.architecture_material_atlas,
            {address_mode = .CLAMP_TO_EDGE},
        ) {
            return false
        }
        fmt.eprintln("architecture material atlas failed to load; using neutral fallback")
    }
    failure_stage^ = "business sign atlas"
    if !resources.texture_load_file(
        ctx,
        "assets/textures/signs/business-sign-atlas.png",
        &world_renderer.business_sign_atlas,
        {address_mode = .CLAMP_TO_EDGE},
    ) {
        return false
    }
    paint_image_info := vk.DescriptorImageInfo {
        imageView   = world_renderer.vehicle_paint_atlas.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    paint_sampler_info := vk.DescriptorImageInfo {
        sampler = world_renderer.vehicle_paint_atlas.sampler,
    }
    soda_logo_image_info := vk.DescriptorImageInfo {
        imageView   = world_renderer.soda_cap_logo.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    soda_logo_sampler_info := vk.DescriptorImageInfo {
        sampler = world_renderer.soda_cap_logo.sampler,
    }
    architecture_material_image_info := vk.DescriptorImageInfo {
        imageView   = world_renderer.architecture_material_atlas.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    architecture_material_sampler_info := vk.DescriptorImageInfo {
        sampler = world_renderer.architecture_material_atlas.sampler,
    }
    business_sign_image_info := vk.DescriptorImageInfo {
        imageView   = world_renderer.business_sign_atlas.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    business_sign_sampler_info := vk.DescriptorImageInfo {
        sampler = world_renderer.business_sign_atlas.sampler,
    }
    paint_writes := [8]vk.WriteDescriptorSet {
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.vehicle_paint_descriptor,
            dstBinding = 0,
            descriptorCount = 1,
            descriptorType = .SAMPLED_IMAGE,
            pImageInfo = &paint_image_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.vehicle_paint_descriptor,
            dstBinding = 1,
            descriptorCount = 1,
            descriptorType = .SAMPLER,
            pImageInfo = &paint_sampler_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.vehicle_paint_descriptor,
            dstBinding = 2,
            descriptorCount = 1,
            descriptorType = .SAMPLED_IMAGE,
            pImageInfo = &soda_logo_image_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.vehicle_paint_descriptor,
            dstBinding = 3,
            descriptorCount = 1,
            descriptorType = .SAMPLER,
            pImageInfo = &soda_logo_sampler_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.vehicle_paint_descriptor,
            dstBinding = 4,
            descriptorCount = 1,
            descriptorType = .SAMPLED_IMAGE,
            pImageInfo = &architecture_material_image_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.vehicle_paint_descriptor,
            dstBinding = 5,
            descriptorCount = 1,
            descriptorType = .SAMPLER,
            pImageInfo = &architecture_material_sampler_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.vehicle_paint_descriptor,
            dstBinding = 6,
            descriptorCount = 1,
            descriptorType = .SAMPLED_IMAGE,
            pImageInfo = &business_sign_image_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.vehicle_paint_descriptor,
            dstBinding = 7,
            descriptorCount = 1,
            descriptorType = .SAMPLER,
            pImageInfo = &business_sign_sampler_info,
        },
    }
    vk.UpdateDescriptorSets(ctx.device, 8, raw_data(paint_writes[:]), 0, nil)
    failure_stage^ = "material lab textures"
    for index in 0 ..< MATERIAL_LAB_MAP_COUNT {
        if !material_lab_gpu_map_load(ctx, Material_Lab_Map_Kind(index), &world_renderer.material_lab_maps[index]) {
            return false
        }
    }
    material_lab_gpu_descriptors_update(ctx)
    world_renderer.material_lab_map_revision = material_lab.map_revision
    pr := vk.PushConstantRange {
        stageFlags = {.VERTEX, .FRAGMENT},
        size       = u32(size_of(World_Push)),
    }
    world_set_layouts := [2]vk.DescriptorSetLayout {
        world_renderer.vehicle_paint_descriptor_layout,
        world_renderer.dynamic_shadow.descriptor_layout,
    }
    li := vk.PipelineLayoutCreateInfo {
        sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
        pushConstantRangeCount = 1,
        pPushConstantRanges    = &pr,
        setLayoutCount         = 2,
        pSetLayouts            = raw_data(world_set_layouts[:]),
    }
    failure_stage^ = "world pipeline layout"
    if vk.CreatePipelineLayout(ctx.device, &li, nil, &world_renderer.layout) != .SUCCESS do return false
    engine.vk_set_debug_name(ctx, .PIPELINE_LAYOUT, auto_cast world_renderer.layout, "world pipeline layout")
    foliage_bindings := [2]vk.DescriptorSetLayoutBinding {
        {binding = 0, descriptorType = .SAMPLED_IMAGE, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 1, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
    }
    foliage_descriptor_info := vk.DescriptorSetLayoutCreateInfo {
        sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        bindingCount = 2,
        pBindings    = raw_data(foliage_bindings[:]),
    }
    if vk.CreateDescriptorSetLayout(
           ctx.device,
           &foliage_descriptor_info,
           nil,
           &world_renderer.foliage_descriptor_layout,
       ) !=
       .SUCCESS {
        return false
    }
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_SET_LAYOUT,
        auto_cast world_renderer.foliage_descriptor_layout,
        "foliage descriptor set layout",
    )
    foliage_pool_sizes := [2]vk.DescriptorPoolSize {
        {type = .SAMPLED_IMAGE, descriptorCount = 6},
        {type = .SAMPLER, descriptorCount = 6},
    }
    foliage_pool_info := vk.DescriptorPoolCreateInfo {
        sType         = .DESCRIPTOR_POOL_CREATE_INFO,
        maxSets       = 6,
        poolSizeCount = 2,
        pPoolSizes    = raw_data(foliage_pool_sizes[:]),
    }
    if vk.CreateDescriptorPool(ctx.device, &foliage_pool_info, nil, &world_renderer.foliage_descriptor_pool) !=
       .SUCCESS {
        return false
    }
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_POOL,
        auto_cast world_renderer.foliage_descriptor_pool,
        "foliage descriptor pool",
    )
    foliage_layouts := [6]vk.DescriptorSetLayout {
        world_renderer.foliage_descriptor_layout,
        world_renderer.foliage_descriptor_layout,
        world_renderer.foliage_descriptor_layout,
        world_renderer.foliage_descriptor_layout,
        world_renderer.foliage_descriptor_layout,
        world_renderer.foliage_descriptor_layout,
    }
    foliage_descriptors: [6]vk.DescriptorSet
    foliage_allocate := vk.DescriptorSetAllocateInfo {
        sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool     = world_renderer.foliage_descriptor_pool,
        descriptorSetCount = 6,
        pSetLayouts        = raw_data(foliage_layouts[:]),
    }
    if vk.AllocateDescriptorSets(ctx.device, &foliage_allocate, raw_data(foliage_descriptors[:])) != .SUCCESS {
        return false
    }
    world_renderer.foliage_descriptor = foliage_descriptors[0]
    world_renderer.bougainvillea_descriptor = foliage_descriptors[1]
    world_renderer.grass_descriptor = foliage_descriptors[2]
    world_renderer.wildflower_descriptor = foliage_descriptors[3]
    world_renderer.marsh_descriptor = foliage_descriptors[4]
    world_renderer.terrain_particle_descriptor = foliage_descriptors[5]
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_SET,
        auto_cast world_renderer.foliage_descriptor,
        "foliage descriptor set",
    )
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_SET,
        auto_cast world_renderer.bougainvillea_descriptor,
        "bougainvillea descriptor set",
    )
    engine.vk_set_debug_name(ctx, .DESCRIPTOR_SET, auto_cast world_renderer.grass_descriptor, "grass descriptor set")
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_SET,
        auto_cast world_renderer.wildflower_descriptor,
        "wildflower descriptor set",
    )
    engine.vk_set_debug_name(ctx, .DESCRIPTOR_SET, auto_cast world_renderer.marsh_descriptor, "marsh descriptor set")
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_SET,
        auto_cast world_renderer.terrain_particle_descriptor,
        "terrain particle descriptor set",
    )
    failure_stage^ = "foliage textures and descriptors"
    if !resources.texture_load_file(
        ctx,
        "assets/textures/foliage/leaf-branches-atlas.png",
        &world_renderer.foliage_atlas,
        {address_mode = .CLAMP_TO_EDGE},
    ) {
        return false
    }
    if !resources.texture_load_file(
        ctx,
        "assets/textures/particles/terrain-particle-atlas.png",
        &world_renderer.terrain_particle_atlas,
        {address_mode = .CLAMP_TO_EDGE},
    ) {
        return false
    }
    if !resources.texture_load_file(
        ctx,
        "assets/textures/foliage/bougainvillea-clumps-atlas-v2.png",
        &world_renderer.bougainvillea_atlas,
        {address_mode = .CLAMP_TO_EDGE},
    ) {
        return false
    }
    if !resources.texture_load_file(
        ctx,
        "assets/textures/foliage/grass-tufts-atlas.png",
        &world_renderer.grass_atlas,
        {address_mode = .CLAMP_TO_EDGE},
    ) {
        return false
    }
    if !resources.texture_load_file(
        ctx,
        "assets/textures/foliage/wildflower-billboards-atlas.png",
        &world_renderer.wildflower_atlas,
        {address_mode = .CLAMP_TO_EDGE},
    ) {
        return false
    }
    if !resources.texture_load_file(
        ctx,
        "assets/textures/foliage/marsh-tidal-rushes-atlas.png",
        &world_renderer.marsh_atlas,
        {address_mode = .CLAMP_TO_EDGE},
    ) {
        return false
    }
    foliage_image_info := vk.DescriptorImageInfo {
        imageView   = world_renderer.foliage_atlas.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    foliage_sampler_info := vk.DescriptorImageInfo {
        sampler = world_renderer.foliage_atlas.sampler,
    }
    bougainvillea_image_info := vk.DescriptorImageInfo {
        imageView   = world_renderer.bougainvillea_atlas.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    bougainvillea_sampler_info := vk.DescriptorImageInfo {
        sampler = world_renderer.bougainvillea_atlas.sampler,
    }
    grass_image_info := vk.DescriptorImageInfo {
        imageView   = world_renderer.grass_atlas.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    grass_sampler_info := vk.DescriptorImageInfo {
        sampler = world_renderer.grass_atlas.sampler,
    }
    wildflower_image_info := vk.DescriptorImageInfo {
        imageView   = world_renderer.wildflower_atlas.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    wildflower_sampler_info := vk.DescriptorImageInfo {
        sampler = world_renderer.wildflower_atlas.sampler,
    }
    marsh_image_info := vk.DescriptorImageInfo {
        imageView   = world_renderer.marsh_atlas.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    marsh_sampler_info := vk.DescriptorImageInfo {
        sampler = world_renderer.marsh_atlas.sampler,
    }
    terrain_particle_image_info := vk.DescriptorImageInfo {
        imageView   = world_renderer.terrain_particle_atlas.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    terrain_particle_sampler_info := vk.DescriptorImageInfo {
        sampler = world_renderer.terrain_particle_atlas.sampler,
    }
    foliage_writes := [12]vk.WriteDescriptorSet {
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.foliage_descriptor,
            dstBinding = 0,
            descriptorCount = 1,
            descriptorType = .SAMPLED_IMAGE,
            pImageInfo = &foliage_image_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.foliage_descriptor,
            dstBinding = 1,
            descriptorCount = 1,
            descriptorType = .SAMPLER,
            pImageInfo = &foliage_sampler_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.bougainvillea_descriptor,
            dstBinding = 0,
            descriptorCount = 1,
            descriptorType = .SAMPLED_IMAGE,
            pImageInfo = &bougainvillea_image_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.bougainvillea_descriptor,
            dstBinding = 1,
            descriptorCount = 1,
            descriptorType = .SAMPLER,
            pImageInfo = &bougainvillea_sampler_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.grass_descriptor,
            dstBinding = 0,
            descriptorCount = 1,
            descriptorType = .SAMPLED_IMAGE,
            pImageInfo = &grass_image_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.grass_descriptor,
            dstBinding = 1,
            descriptorCount = 1,
            descriptorType = .SAMPLER,
            pImageInfo = &grass_sampler_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.wildflower_descriptor,
            dstBinding = 0,
            descriptorCount = 1,
            descriptorType = .SAMPLED_IMAGE,
            pImageInfo = &wildflower_image_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.wildflower_descriptor,
            dstBinding = 1,
            descriptorCount = 1,
            descriptorType = .SAMPLER,
            pImageInfo = &wildflower_sampler_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.marsh_descriptor,
            dstBinding = 0,
            descriptorCount = 1,
            descriptorType = .SAMPLED_IMAGE,
            pImageInfo = &marsh_image_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.marsh_descriptor,
            dstBinding = 1,
            descriptorCount = 1,
            descriptorType = .SAMPLER,
            pImageInfo = &marsh_sampler_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.terrain_particle_descriptor,
            dstBinding = 0,
            descriptorCount = 1,
            descriptorType = .SAMPLED_IMAGE,
            pImageInfo = &terrain_particle_image_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.terrain_particle_descriptor,
            dstBinding = 1,
            descriptorCount = 1,
            descriptorType = .SAMPLER,
            pImageInfo = &terrain_particle_sampler_info,
        },
    }
    vk.UpdateDescriptorSets(ctx.device, 12, raw_data(foliage_writes[:]), 0, nil)
    foliage_layout_info := li
    foliage_layout_info.setLayoutCount = 1
    foliage_set_layouts := [2]vk.DescriptorSetLayout {
        world_renderer.foliage_descriptor_layout,
        world_renderer.dynamic_shadow.descriptor_layout,
    }
    foliage_layout_info.setLayoutCount = 2
    foliage_layout_info.pSetLayouts = raw_data(foliage_set_layouts[:])
    if vk.CreatePipelineLayout(ctx.device, &foliage_layout_info, nil, &world_renderer.foliage_layout) != .SUCCESS {
        return false
    }
    engine.vk_set_debug_name(ctx, .PIPELINE_LAYOUT, auto_cast world_renderer.foliage_layout, "foliage pipeline layout")
    return true
}
