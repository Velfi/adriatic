package main

import engine "zelda_engine:engine"
import render3d "zelda_engine:render3d"
import vk "vendor:vulkan"

world_renderer_create_plant_pipeline :: proc(
    ctx: ^engine.Vk_Context,
    stages: [2]vk.PipelineShaderStageCreateInfo,
    info: vk.GraphicsPipelineCreateInfo,
) -> bool {
    plant_vert: engine.Vk_Shader_Module
    if !engine.vk_load_shader_module_with_fallback(
        ctx, "assets/shaders/world.slang", "shaders/plant.vert", .Vertex, "plant_vertex_main", &plant_vert,
    ) {
        return false
    }
    defer engine.vk_destroy_shader_module(ctx, &plant_vert)
    plant_stages := stages
    plant_stages[0].module = plant_vert.handle
    bindings := [2]vk.VertexInputBindingDescription {
        {binding = 0, stride = u32(size_of(Plant_Vertex)), inputRate = .VERTEX},
        {binding = 1, stride = u32(size_of(World_Mesh_Instance)), inputRate = .INSTANCE},
    }
    attrs := [20]vk.VertexInputAttributeDescription {
        {location = 0, binding = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Plant_Vertex, position))},
        {location = 1, binding = 0, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(Plant_Vertex, color))},
        {location = 2, binding = 0, format = .R32_UINT, offset = u32(offset_of(Plant_Vertex, kind))},
        {location = 3, binding = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Plant_Vertex, normal))},
        {location = 4, binding = 0, format = .R32G32_SFLOAT, offset = u32(offset_of(Plant_Vertex, material))},
        {location = 5, binding = 0, format = .R32G32_SFLOAT, offset = u32(offset_of(Plant_Vertex, uv))},
        {location = 6, binding = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Plant_Vertex, primary_anchor))},
        {location = 7, binding = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Plant_Vertex, secondary_anchor))},
        {location = 8, binding = 0, format = .R32G32_SFLOAT, offset = u32(offset_of(Plant_Vertex, axis_position))},
        {location = 9, binding = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Plant_Vertex, leaf_pivot))},
        {location = 10, binding = 0, format = .R32_SFLOAT, offset = u32(offset_of(Plant_Vertex, flutter))},
        {location = 11, binding = 0, format = .R32_UINT, offset = u32(offset_of(Plant_Vertex, hierarchy_depth))},
        {location = 12, binding = 0, format = .R32_SFLOAT, offset = u32(offset_of(Plant_Vertex, phase))},
        {location = 13, binding = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(World_Mesh_Instance, basis_x_translation_x))},
        {location = 14, binding = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(World_Mesh_Instance, basis_y_translation_y))},
        {location = 15, binding = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(World_Mesh_Instance, basis_z_translation_z))},
        {location = 16, binding = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(World_Mesh_Instance, color))},
        {location = 17, binding = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(World_Mesh_Instance, normal_override))},
        {location = 18, binding = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(World_Mesh_Instance, plant_root_compliance))},
        {location = 19, binding = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(World_Mesh_Instance, plant_motion))},
    }
    vertex_input := vk.PipelineVertexInputStateCreateInfo {
        sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount = 2,
        pVertexBindingDescriptions = raw_data(bindings[:]),
        vertexAttributeDescriptionCount = u32(len(attrs)),
        pVertexAttributeDescriptions = raw_data(attrs[:]),
    }
    plant_info := info
    plant_info.pStages = raw_data(plant_stages[:])
    plant_info.pVertexInputState = &vertex_input
    return render3d.create_color_pipeline_variants(ctx, &plant_info, .D32_SFLOAT, &world_renderer.plant_pipelines)
}
