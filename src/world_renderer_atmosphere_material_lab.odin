package main
import "core:math"
import "core:mem"

import air_effects "../packages/air_effects"
import atmosphere "../packages/atmosphere"
import fog_field "../packages/fog_field"
import particles "../packages/particles"
import terrain "../packages/terrain"
import "core:math/linalg"
import vk "vendor:vulkan"
import engine "zelda_engine:engine"
import resources "zelda_engine:render_resources"
import third_person "zelda_engine:third_person"

world_rain_streaks :: proc(editor: ^Editor) {
    if editor == nil || !editor.in_map || !driving_aircraft(editor) do return
    wind_x, wind_z := editor.atmosphere.weather.wind[0], editor.atmosphere.weather.wind[1]
    wind_speed := f32(math.sqrt(f64(wind_x * wind_x + wind_z * wind_z)))
    strength := air_effects.eased_range(wind_speed, 1, 9)
    if strength <= .001 do return

    body := active_aircraft_body(editor)
    direction_x, direction_z := wind_x / wind_speed, wind_z / wind_speed
    side_x, side_z := -direction_z, direction_x
    time := editor.map_time
    streak_count := air_effects.world_rain_streak_count(wind_speed)
    for index in 0 ..< streak_count {
        speed_variation := .72 + wind_streak_hash(index, 1) * .56
        gust_phase := time * .72 + wind_streak_hash(index, 6) * math.PI * 2
        gust := .75 + (.5 + .5 * f32(math.sin(f64(gust_phase)))) * .25
        cycle := wind_streak_cycle(
            time,
            wind_speed,
            speed_variation,
            wind_streak_hash(index, 2),
            wind_streak_hash(index, 6),
        )
        phase := cycle - f32(math.floor(f64(cycle)))
        along := (phase - .5) * 82
        lateral := (wind_streak_hash(index, 3) - .5) * 62
        vertical := (wind_streak_hash(index, 4) - .5) * 25 + 3
        center := particles.Vec3 {
            body.position.x + direction_x * along + side_x * lateral,
            body.position.y + vertical,
            body.position.z + direction_z * along + side_z * lateral,
        }
        local_weather := atmosphere.sample_at(&editor.atmosphere, {center.x, center.y, center.z}, center.y)
        rain_visibility := air_effects.rain_streak_visibility(local_weather.precipitation)
        if rain_visibility <= .001 do continue
        streak_length := (1.4 + wind_speed * .58) * (.62 + wind_streak_hash(index, 5) * .58) * (.84 + gust * .18)
        center_camera_distance := linalg.length(
            editor.camera_pose.position - third_person.Vec3{center.x, center.y, center.z},
        )
        streak_length = wind_streak_perspective_length(streak_length, center_camera_distance)
        tail := particles.Vec3 {
            center.x - direction_x * streak_length,
            center.y,
            center.z - direction_z * streak_length,
        }
        streak_center := third_person.Vec3 {
            (center.x + tail.x) * .5,
            (center.y + tail.y) * .5,
            (center.z + tail.z) * .5,
        }
        // Keep the whole stream alive just beyond the viewport. Exact
        // frustum culling makes these sparse, fast-moving streaks visibly
        // blink out at the screen edge before their fade reads as complete.
        if !world_sphere_in_view(editor, streak_center, streak_length * .5 + .15, 3) do continue
        camera_offset := editor.camera_pose.position - streak_center
        camera_distance := linalg.length(camera_offset)
        closest_camera_distance := wind_streak_camera_distance(
            editor.camera_pose.position,
            {tail.x, tail.y, tail.z},
            {center.x, center.y, center.z},
        )
        near_fade := clamp((closest_camera_distance - 4) / 6, 0, 1)
        near_fade = near_fade * near_fade * (3 - 2 * near_fade)
        fade := math.sin(phase * math.PI)
        alpha := u8(clamp((28 + strength * 104) * fade * (.70 + gust * .30) * near_fade * rain_visibility, 0, 132))
        tail_alpha := u8(clamp(f32(alpha) * .16, 0, 24))
        width := (.020 + strength * .042) * clamp(camera_distance / 24, .20, 1)
        line_direction := third_person.Vec3{direction_x, 0, direction_z}
        to_camera := linalg.normalize0(camera_offset)
        // Build a true camera-facing ribbon. Offsetting along camera.up makes a
        // horizontal wind direction collapse edge-on at common flight-camera
        // angles, and its winding can face away from the back-face culled pass.
        ribbon_right := linalg.normalize0(linalg.cross(to_camera, line_direction)) * width
        vertices := [6]World_Vertex {
            world_vertex({tail.x, tail.y, tail.z}, {137, 218, 235, tail_alpha}),
            world_vertex(
                {center.x - ribbon_right.x, center.y - ribbon_right.y, center.z - ribbon_right.z},
                {178, 235, 246, alpha},
            ),
            world_vertex(
                {center.x + ribbon_right.x, center.y + ribbon_right.y, center.z + ribbon_right.z},
                {178, 235, 246, alpha},
            ),
            world_vertex({tail.x, tail.y, tail.z}, {137, 218, 235, tail_alpha}),
            world_vertex(
                {center.x + ribbon_right.x, center.y + ribbon_right.y, center.z + ribbon_right.z},
                {178, 235, 246, alpha},
            ),
            world_vertex(
                {center.x - ribbon_right.x, center.y - ribbon_right.y, center.z - ribbon_right.z},
                {178, 235, 246, alpha},
            ),
        }
        append(
            &world_renderer.late_transparent_vertices,
            ..vertices[:],
            // Cool blue distinguishes rain moving through world space from
            // the warm radial speed lines drawn in the flight overlay.
        )
    }
}

world_fog_shell_bank :: proc(editor: ^Editor, bank: fog_field.Fog_Bank, weight, global_density: f32) {
    alpha_scale := clamp(weight * global_density * bank.peak_density, 0, 1)
    if alpha_scale <= .01 do return
    camera := editor.camera_pose.position
    camera_density := fog_field.sample_bank(bank, {camera.x, camera.y, camera.z})
    altitude_fade := 1 - clamp((camera.y - bank.top_altitude - 80) / 240, 0, 1)
    alpha_scale *= (1 - camera_density * .86) * altitude_fade
    if alpha_scale <= .01 do return
    SEGMENTS :: 48
    BANDS :: 3
    side := fog_field.Vec2{-bank.axis.y, bank.axis.x}
    for band in 0 ..< BANDS {
        y0 := bank.base_altitude + (bank.top_altitude - bank.base_altitude) * f32(band) / BANDS
        y1 := bank.base_altitude + (bank.top_altitude - bank.base_altitude) * f32(band + 1) / BANDS
        band_fade := band == BANDS - 1 ? f32(.55) : f32(1)
        alpha := u8(clamp(38 * alpha_scale * band_fade, 0, 52))
        for segment in 0 ..< SEGMENTS {
            angle0 := f32(segment) / SEGMENTS * 2 * f32(math.PI)
            angle1 := f32(segment + 1) / SEGMENTS * 2 * f32(math.PI)
            c0, s0 := f32(math.cos(f64(angle0))), f32(math.sin(f64(angle0)))
            c1, s1 := f32(math.cos(f64(angle1))), f32(math.sin(f64(angle1)))
            x0 := bank.center.x + bank.axis.x * c0 * bank.radii.x + side.x * s0 * bank.radii.y
            z0 := bank.center.y + bank.axis.y * c0 * bank.radii.x + side.y * s0 * bank.radii.y
            x1 := bank.center.x + bank.axis.x * c1 * bank.radii.x + side.x * s1 * bank.radii.y
            z1 := bank.center.y + bank.axis.y * c1 * bank.radii.x + side.y * s1 * bank.radii.y
            top0, top1 := y1, y1
            if band == BANDS - 1 {
                crown0 := .72 + .28 * (.5 + .5 * f32(math.sin(f64(angle0 * 3.0 + bank.axis.x * 5.7))))
                crown1 := .72 + .28 * (.5 + .5 * f32(math.sin(f64(angle1 * 3.0 + bank.axis.x * 5.7))))
                top0 = bank.base_altitude + (bank.top_altitude - bank.base_altitude) * crown0
                top1 = bank.base_altitude + (bank.top_altitude - bank.base_altitude) * crown1
            }
            vertices := [6]World_Vertex {
                world_vertex({x0, y0, z0}, {190, 208, 210, 0}),
                world_vertex({x1, y0, z1}, {190, 208, 210, 0}),
                world_vertex({x1, top1, z1}, {198, 214, 215, alpha}),
                world_vertex({x0, y0, z0}, {190, 208, 210, 0}),
                world_vertex({x1, top1, z1}, {198, 214, 215, alpha}),
                world_vertex({x0, top0, z0}, {198, 214, 215, alpha}),
            }
            bottom_v, top_v := f32(band) / BANDS, f32(band + 1) / BANDS
            vertices[0].uv = {f32(segment) / SEGMENTS, bottom_v}
            vertices[1].uv = {f32(segment + 1) / SEGMENTS, bottom_v}
            vertices[2].uv = {f32(segment + 1) / SEGMENTS, top_v}
            vertices[3].uv = {f32(segment) / SEGMENTS, bottom_v}
            vertices[4].uv = {f32(segment + 1) / SEGMENTS, top_v}
            vertices[5].uv = {f32(segment) / SEGMENTS, top_v}
            for &vertex in vertices do vertex.kind = .Fog_Shell
            append(&world_renderer.late_transparent_vertices, ..vertices[:])
            // The camera may approach an ellipse from either side, and the
            // transparent world pipeline retains back-face culling.
            reverse := [6]World_Vertex{vertices[0], vertices[2], vertices[1], vertices[3], vertices[5], vertices[4]}
            append(&world_renderer.late_transparent_vertices, ..reverse[:])
        }
    }
}

world_fog_shells :: proc(editor: ^Editor) {
    if editor == nil || !editor.in_map || !fog_debug_enabled || !fog_debug_shells do return
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    field := fog_field.generate(
        editor.atmosphere.seed,
        editor.atmosphere.front_seconds,
        editor.atmosphere.weather,
        {{-half_extent, -half_extent}, {half_extent, half_extent}},
        editor.atmosphere.climate.current,
    )
    for index in 0 ..< fog_field.MAX_BANKS {
        if field.blend < 1 do world_fog_shell_bank(editor, field.previous_banks[index], 1 - field.blend, field.global_density)
        world_fog_shell_bank(editor, field.banks[index], field.blend, field.global_density)
    }
}

vehicle_paint_atlas_create :: proc(ctx: ^engine.Vk_Context, out: ^resources.Image) -> bool {
    if ctx == nil || out == nil do return false
    if !resources.image_array_create(
        ctx,
        VEHICLE_PAINT_TEXTURE_WIDTH,
        VEHICLE_PAINT_TEXTURE_HEIGHT,
        VEHICLE_PAINT_AIRCRAFT_COUNT,
        .R8G8B8A8_SRGB,
        {.TRANSFER_DST, .SAMPLED},
        {.COLOR},
        .D2_ARRAY,
        false,
        out,
        "vehicle paint texture array",
    ) {
        return false
    }
    staging: engine.Vk_Buffer
    total_size := VEHICLE_PAINT_TEXTURE_BYTE_COUNT * VEHICLE_PAINT_AIRCRAFT_COUNT
    if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(total_size), {.TRANSFER_SRC}, &staging) {
        resources.image_destroy(out, ctx)
        return false
    }
    defer engine.vk_destroy_buffer(ctx, &staging)
    pixels := mem.slice_ptr(cast([^]u8)staging.mapped, total_size)
    for &pixel in pixels do pixel = 0
    cmd, begun := engine.vk_begin_upload_commands(ctx)
    if !begun {
        resources.image_destroy(out, ctx)
        return false
    }
    barrier := vk.ImageMemoryBarrier2 {
        sType = .IMAGE_MEMORY_BARRIER_2,
        srcStageMask = {.TOP_OF_PIPE},
        dstStageMask = {.TRANSFER},
        dstAccessMask = {.TRANSFER_WRITE},
        oldLayout = .UNDEFINED,
        newLayout = .TRANSFER_DST_OPTIMAL,
        srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        image = out.image,
        subresourceRange = {
            aspectMask = {.COLOR},
            baseMipLevel = 0,
            levelCount = 1,
            baseArrayLayer = 0,
            layerCount = VEHICLE_PAINT_AIRCRAFT_COUNT,
        },
    }
    dependency := vk.DependencyInfo {
        sType                   = .DEPENDENCY_INFO,
        imageMemoryBarrierCount = 1,
        pImageMemoryBarriers    = &barrier,
    }
    vk.CmdPipelineBarrier2(cmd, &dependency)
    region := vk.BufferImageCopy {
        imageSubresource = {
            aspectMask = {.COLOR},
            mipLevel = 0,
            baseArrayLayer = 0,
            layerCount = VEHICLE_PAINT_AIRCRAFT_COUNT,
        },
        imageExtent = {VEHICLE_PAINT_TEXTURE_WIDTH, VEHICLE_PAINT_TEXTURE_HEIGHT, 1},
    }
    vk.CmdCopyBufferToImage(cmd, staging.handle, out.image, .TRANSFER_DST_OPTIMAL, 1, &region)
    barrier.srcStageMask = {.TRANSFER}
    barrier.srcAccessMask = {.TRANSFER_WRITE}
    barrier.dstStageMask = {.FRAGMENT_SHADER}
    barrier.dstAccessMask = {.SHADER_READ}
    barrier.oldLayout = .TRANSFER_DST_OPTIMAL
    barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
    vk.CmdPipelineBarrier2(cmd, &dependency)
    if !engine.vk_submit_upload_commands(ctx) {
        resources.image_destroy(out, ctx)
        return false
    }
    sampler_info := vk.SamplerCreateInfo {
        sType        = .SAMPLER_CREATE_INFO,
        magFilter    = .LINEAR,
        minFilter    = .LINEAR,
        mipmapMode   = .LINEAR,
        addressModeU = .CLAMP_TO_EDGE,
        addressModeV = .CLAMP_TO_EDGE,
        addressModeW = .CLAMP_TO_EDGE,
        minLod       = 0,
        maxLod       = 0,
    }
    if vk.CreateSampler(ctx.device, &sampler_info, nil, &out.sampler) != .SUCCESS {
        resources.image_destroy(out, ctx)
        return false
    }
    engine.vk_set_debug_name(ctx, .SAMPLER, auto_cast out.sampler, "vehicle paint sampler")
    return true
}

vehicle_paint_atlas_invalidate_all :: proc() {
    for &dirty in world_renderer.vehicle_paint_dirty_layers do dirty = true
}

vehicle_paint_atlas_flush :: proc(editor: ^Editor, cmd: vk.CommandBuffer, frame_index: int) {
    pending_layer := -1
    for dirty, layer in world_renderer.vehicle_paint_dirty_layers {
        if dirty {
            pending_layer = layer
            break
        }
    }
    if editor == nil ||
       (!editor.vehicle_paint_texture_dirty && !editor.vehicle_paint_preview_texture_dirty && pending_layer < 0) ||
       cmd == nil ||
       frame_index < 0 ||
       frame_index >= engine.MAX_FRAMES_IN_FLIGHT {
        return
    }
    staging := &world_renderer.vehicle_paint_staging[frame_index]
    if staging.handle == vk.Buffer(0) || staging.mapped == nil do return
    active_layer := vehicle_paint_layer_index(editor.aircraft.active)
    layer_index := active_layer
    if !editor.vehicle_paint_texture_dirty && !editor.vehicle_paint_preview_texture_dirty && pending_layer >= 0 {
        layer_index = pending_layer
    }
    mem.copy_non_overlapping(
        staging.mapped,
        raw_data(vehicle_paint_layer(editor, layer_index)),
        VEHICLE_PAINT_TEXTURE_BYTE_COUNT,
    )
    staging_pixels := mem.slice_ptr(cast([^]u8)staging.mapped, VEHICLE_PAINT_TEXTURE_BYTE_COUNT)
    if layer_index == active_layer {
        for preview_alpha, byte_index in editor.vehicle_paint_preview_pixels {
            if byte_index % 4 != 3 || preview_alpha == 0 do continue
            pixel := byte_index - 3
            blend := f32(preview_alpha) / 255
            staging_pixels[pixel] = u8(
                f32(editor.vehicle_paint_preview_pixels[pixel]) * blend + f32(staging_pixels[pixel]) * (1 - blend),
            )
            staging_pixels[pixel + 1] = u8(
                f32(editor.vehicle_paint_preview_pixels[pixel + 1]) * blend +
                f32(staging_pixels[pixel + 1]) * (1 - blend),
            )
            staging_pixels[pixel + 2] = u8(
                f32(editor.vehicle_paint_preview_pixels[pixel + 2]) * blend +
                f32(staging_pixels[pixel + 2]) * (1 - blend),
            )
            staging_pixels[pixel + 3] = max(staging_pixels[pixel + 3], preview_alpha)
        }
    }
    layer := u32(layer_index)
    barrier := vk.ImageMemoryBarrier2 {
        sType = .IMAGE_MEMORY_BARRIER_2,
        srcStageMask = {.FRAGMENT_SHADER},
        srcAccessMask = {.SHADER_READ},
        dstStageMask = {.TRANSFER},
        dstAccessMask = {.TRANSFER_WRITE},
        oldLayout = .SHADER_READ_ONLY_OPTIMAL,
        newLayout = .TRANSFER_DST_OPTIMAL,
        srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        image = world_renderer.vehicle_paint_atlas.image,
        subresourceRange = {
            aspectMask = {.COLOR},
            baseMipLevel = 0,
            levelCount = 1,
            baseArrayLayer = layer,
            layerCount = 1,
        },
    }
    dependency := vk.DependencyInfo {
        sType                   = .DEPENDENCY_INFO,
        imageMemoryBarrierCount = 1,
        pImageMemoryBarriers    = &barrier,
    }
    vk.CmdPipelineBarrier2(cmd, &dependency)
    region := vk.BufferImageCopy {
        imageSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = layer, layerCount = 1},
        imageExtent = {VEHICLE_PAINT_TEXTURE_WIDTH, VEHICLE_PAINT_TEXTURE_HEIGHT, 1},
    }
    vk.CmdCopyBufferToImage(
        cmd,
        staging.handle,
        world_renderer.vehicle_paint_atlas.image,
        .TRANSFER_DST_OPTIMAL,
        1,
        &region,
    )
    barrier.srcStageMask = {.TRANSFER}
    barrier.srcAccessMask = {.TRANSFER_WRITE}
    barrier.dstStageMask = {.FRAGMENT_SHADER}
    barrier.dstAccessMask = {.SHADER_READ}
    barrier.oldLayout = .TRANSFER_DST_OPTIMAL
    barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
    vk.CmdPipelineBarrier2(cmd, &dependency)
    world_renderer.vehicle_paint_dirty_layers[layer_index] = false
    if layer_index == active_layer {
        editor.vehicle_paint_texture_dirty = false
        editor.vehicle_paint_preview_texture_dirty = false
    }
}

material_lab_gpu_map_load :: proc(
    ctx: ^engine.Vk_Context,
    kind: Material_Lab_Map_Kind,
    out: ^resources.Image,
) -> bool {
    material := material_lab_current()
    path := material_lab_map_path(material, kind)
    linear := kind != .Albedo
    if path != "" && resources.texture_load_file(ctx, path, out, {address_mode = .REPEAT, linear_color = linear}) {
        return true
    }
    pixels := [4]u8{255, 255, 255, 255}
    if material != nil {
        switch kind {
        case .Specular:
            value := u8(clamp(material.metallic, 0, 1) * 255)
            pixels = {value, value, value, 255}
        case .Roughness:
            value := u8(clamp(material.roughness, 0, 1) * 255)
            pixels = {value, value, value, 255}
        case .Normal:
            pixels = {128, 128, 255, 255}
        case .Albedo:
        }
    }
    return resources.texture_upload_rgba8(ctx, pixels[:], 1, 1, out, {address_mode = .REPEAT, linear_color = linear})
}

material_lab_gpu_descriptors_update :: proc(ctx: ^engine.Vk_Context) {
    image_infos: [MATERIAL_LAB_MAP_COUNT]vk.DescriptorImageInfo
    sampler_infos: [MATERIAL_LAB_MAP_COUNT]vk.DescriptorImageInfo
    writes: [MATERIAL_LAB_MAP_COUNT * 2]vk.WriteDescriptorSet
    for index in 0 ..< MATERIAL_LAB_MAP_COUNT {
        image_infos[index] = {
            imageView   = world_renderer.material_lab_maps[index].view,
            imageLayout = .SHADER_READ_ONLY_OPTIMAL,
        }
        sampler_infos[index] = {
            sampler = world_renderer.material_lab_maps[index].sampler,
        }
        writes[index * 2] = {
            sType           = .WRITE_DESCRIPTOR_SET,
            dstSet          = world_renderer.vehicle_paint_descriptor,
            dstBinding      = u32(8 + index * 2),
            descriptorCount = 1,
            descriptorType  = .SAMPLED_IMAGE,
            pImageInfo      = &image_infos[index],
        }
        writes[index * 2 + 1] = {
            sType           = .WRITE_DESCRIPTOR_SET,
            dstSet          = world_renderer.vehicle_paint_descriptor,
            dstBinding      = u32(9 + index * 2),
            descriptorCount = 1,
            descriptorType  = .SAMPLER,
            pImageInfo      = &sampler_infos[index],
        }
    }
    vk.UpdateDescriptorSets(ctx.device, MATERIAL_LAB_MAP_COUNT * 2, raw_data(writes[:]), 0, nil)
}

material_lab_gpu_maps_reload :: proc(ctx: ^engine.Vk_Context) -> bool {
    replacement: [MATERIAL_LAB_MAP_COUNT]resources.Image
    for index in 0 ..< MATERIAL_LAB_MAP_COUNT {
        if !material_lab_gpu_map_load(ctx, Material_Lab_Map_Kind(index), &replacement[index]) {
            for &loaded in replacement do resources.image_destroy(&loaded, ctx)
            return false
        }
    }
    _ = vk.DeviceWaitIdle(ctx.device)
    for index in 0 ..< MATERIAL_LAB_MAP_COUNT {
        resources.image_destroy(&world_renderer.material_lab_maps[index], ctx)
        world_renderer.material_lab_maps[index] = replacement[index]
    }
    material_lab_gpu_descriptors_update(ctx)
    world_renderer.material_lab_map_revision = material_lab.map_revision
    return true
}
