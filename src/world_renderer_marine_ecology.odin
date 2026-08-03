package main

import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vk "vendor:vulkan"
import canvas2d "zelda_engine:canvas2d"
import resources "zelda_engine:render_resources"

MARINE_ECOLOGY_ATLAS_COLUMNS :: 32
MARINE_ECOLOGY_ATLAS_ROWS :: 32
MARINE_ECOLOGY_ATLAS_CAPACITY :: MARINE_ECOLOGY_ATLAS_COLUMNS * MARINE_ECOLOGY_ATLAS_ROWS
MARINE_ECOLOGY_TILE_SIZE :: terrain.BATHYMETRY_CHUNK_RESOLUTION
MARINE_ECOLOGY_ATLAS_WIDTH :: MARINE_ECOLOGY_ATLAS_COLUMNS * MARINE_ECOLOGY_TILE_SIZE
MARINE_ECOLOGY_ATLAS_HEIGHT :: MARINE_ECOLOGY_ATLAS_ROWS * MARINE_ECOLOGY_TILE_SIZE

marine_ecology_signature :: proc(project: ^terrain.Project) -> u64 {
    if project == nil do return 0
    signature := u64(len(project.marine_habitat_chunks)) * 0x9e3779b97f4a7c15
    for &chunk in project.marine_habitat_chunks {
        signature = (signature ~ chunk.revision ~ (chunk.source_bathymetry_revision << 1)) * 0xbf58476d1ce4e5b9
        signature = signature ~ u64(u32(chunk.chunk_x)) * 0x94d049bb133111eb
        signature = signature ~ u64(u32(chunk.chunk_z)) * 0x369dea0f31a53f85
    }
    return signature
}

marine_ecology_descriptors_update :: proc(image: ^resources.Image) {
    if image == nil || image.view == vk.ImageView(0) || image.sampler == vk.Sampler(0) do return
    image_info := vk.DescriptorImageInfo {
        imageView = image.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    sampler_info := vk.DescriptorImageInfo{sampler = image.sampler}
    writes := [2]vk.WriteDescriptorSet {
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.vehicle_paint_descriptor,
            dstBinding = 16,
            descriptorCount = 1,
            descriptorType = .SAMPLED_IMAGE,
            pImageInfo = &image_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.vehicle_paint_descriptor,
            dstBinding = 17,
            descriptorCount = 1,
            descriptorType = .SAMPLER,
            pImageInfo = &sampler_info,
        },
    }
    vk.UpdateDescriptorSets(world_renderer.ctx.device, 2, raw_data(writes[:]), 0, nil)
}

marine_ecology_atlas_update :: proc(editor: ^Editor) -> bool {
    if editor == nil || world_renderer.ctx == nil do return false
    signature := marine_ecology_signature(&editor.project)
    chunk_count := min(len(editor.project.marine_habitat_chunks), MARINE_ECOLOGY_ATLAS_CAPACITY)
    if signature == world_renderer.marine_ecology_atlas_signature &&
       chunk_count == world_renderer.marine_ecology_atlas_chunk_count {
        return chunk_count > 0
    }
    if chunk_count <= 0 {
        world_renderer.marine_ecology_atlas_signature = signature
        world_renderer.marine_ecology_atlas_chunk_count = 0
        return false
    }
    pixel_count := MARINE_ECOLOGY_ATLAS_WIDTH * MARINE_ECOLOGY_ATLAS_HEIGHT
    pixels := make([]u8, pixel_count * 4, context.temp_allocator)
    for chunk_index in 0 ..< chunk_count {
        chunk := &editor.project.marine_habitat_chunks[chunk_index]
        if len(chunk.cells) != terrain.BATHYMETRY_CHUNK_SAMPLES do continue
        tile_x := chunk_index % MARINE_ECOLOGY_ATLAS_COLUMNS
        tile_y := chunk_index / MARINE_ECOLOGY_ATLAS_COLUMNS
        for z in 0 ..< MARINE_ECOLOGY_TILE_SIZE {
            for x in 0 ..< MARINE_ECOLOGY_TILE_SIZE {
                source := chunk.cells[z * MARINE_ECOLOGY_TILE_SIZE + x]
                destination :=
                    ((tile_y * MARINE_ECOLOGY_TILE_SIZE + z) * MARINE_ECOLOGY_ATLAS_WIDTH +
                        tile_x * MARINE_ECOLOGY_TILE_SIZE + x) * 4
                pixels[destination + 0] = source.seagrass
                pixels[destination + 1] = source.macroalgae
                pixels[destination + 2] = source.coralligenous
                pixels[destination + 3] = source.disturbance
            }
        }
    }
    replacement: resources.Image
    if !resources.texture_upload_rgba8(
        world_renderer.ctx,
        pixels,
        MARINE_ECOLOGY_ATLAS_WIDTH,
        MARINE_ECOLOGY_ATLAS_HEIGHT,
        &replacement,
        {address_mode = .CLAMP_TO_EDGE, linear_color = true},
    ) {
        return false
    }
    // Atlas replacement is rare (map load or authored bathymetry revision).
    // Wait before retiring the descriptor's previous image; ordinary frames
    // only sample the stable atlas and incur no upload or synchronization.
    previous := world_renderer.marine_ecology_atlas
    if previous.width > 1 || previous.height > 1 {
        _ = vk.DeviceWaitIdle(world_renderer.ctx.device)
    }
    world_renderer.marine_ecology_atlas = replacement
    marine_ecology_descriptors_update(&world_renderer.marine_ecology_atlas)
    resources.image_destroy(&previous, world_renderer.ctx)
    world_renderer.marine_ecology_atlas_signature = signature
    world_renderer.marine_ecology_atlas_chunk_count = chunk_count
    return true
}

marine_ecology_vertex :: #force_inline proc(position: third_person.Vec3, uv: [2]f32) -> World_Vertex {
    vertex := world_vertex(position, canvas2d.Color{48, 112, 142, 255})
    vertex.kind = .Marine_Water
    vertex.normal = {0, 1, 0}
    vertex.uv = uv
    return vertex
}

world_marine_ecology :: proc(editor: ^Editor) {
    if editor == nil || editor.camera_pose.position.y <= editor.project.sea_level + .08 do return
    if !marine_ecology_atlas_update(editor) do return
    count := world_renderer.marine_ecology_atlas_chunk_count
    surface_y := editor.project.sea_level - 1.90
    for chunk_index in 0 ..< count {
        chunk := &editor.project.marine_habitat_chunks[chunk_index]
        if len(chunk.cells) != terrain.BATHYMETRY_CHUNK_SAMPLES do continue
        origin_x := f32(chunk.chunk_x) * terrain.BATHYMETRY_CHUNK_SIZE
        origin_z := f32(chunk.chunk_z) * terrain.BATHYMETRY_CHUNK_SIZE
        if owner_index, owned := terrain.island_index(chunk.owner); owned {
            transform := terrain.island_transform_at(&editor.project, owner_index)
            origin_x += transform.current_x - transform.source_x
            origin_z += transform.current_z - transform.source_z
        }
        if abs(origin_x + terrain.BATHYMETRY_CHUNK_SIZE * .5 - editor.camera_pose.position.x) > 1800 ||
           abs(origin_z + terrain.BATHYMETRY_CHUNK_SIZE * .5 - editor.camera_pose.position.z) > 1800 {
            continue
        }
        tile_x := chunk_index % MARINE_ECOLOGY_ATLAS_COLUMNS
        tile_y := chunk_index / MARINE_ECOLOGY_ATLAS_COLUMNS
        u0 := (f32(tile_x * MARINE_ECOLOGY_TILE_SIZE) + .5) / f32(MARINE_ECOLOGY_ATLAS_WIDTH)
        v0 := (f32(tile_y * MARINE_ECOLOGY_TILE_SIZE) + .5) / f32(MARINE_ECOLOGY_ATLAS_HEIGHT)
        u1 := (f32((tile_x + 1) * MARINE_ECOLOGY_TILE_SIZE) - .5) / f32(MARINE_ECOLOGY_ATLAS_WIDTH)
        v1 := (f32((tile_y + 1) * MARINE_ECOLOGY_TILE_SIZE) - .5) / f32(MARINE_ECOLOGY_ATLAS_HEIGHT)
        x1, z1 := origin_x + terrain.BATHYMETRY_CHUNK_SIZE, origin_z + terrain.BATHYMETRY_CHUNK_SIZE
        append(
            &world_renderer.vertices,
            marine_ecology_vertex({origin_x, surface_y, origin_z}, {u0, v0}),
            marine_ecology_vertex({origin_x, surface_y, z1}, {u0, v1}),
            marine_ecology_vertex({x1, surface_y, z1}, {u1, v1}),
            marine_ecology_vertex({origin_x, surface_y, origin_z}, {u0, v0}),
            marine_ecology_vertex({x1, surface_y, z1}, {u1, v1}),
            marine_ecology_vertex({x1, surface_y, origin_z}, {u1, v0}),
        )
    }
}
