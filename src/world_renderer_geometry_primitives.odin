package main
import "core:math"
import "core:mem"

import atmosphere "../packages/atmosphere"
import islands "../packages/islands"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math/linalg"
import vk "vendor:vulkan"
import canvas2d "zelda_engine:canvas2d"
import engine "zelda_engine:engine"

world_dynamic_vertex_buffer_upload :: proc(frame: int) -> bool {
    if frame < 0 || frame >= engine.MAX_FRAMES_IN_FLIGHT do return false
    if world_renderer.dynamic_vertex_uploaded do return true
    ctx := world_renderer.ctx
    if ctx == nil do return false
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.vertex[frame],
        vk.DeviceSize(len(world_renderer.vertices) * size_of(World_Vertex)),
        {.VERTEX_BUFFER},
        "world dynamic vertex buffer",
    ) {
        return false
    }
    if len(world_renderer.vertices) > 0 {
        mem.copy_non_overlapping(
            world_renderer.vertex[frame].mapped,
            raw_data(world_renderer.vertices[:]),
            len(world_renderer.vertices) * size_of(World_Vertex),
        )
    }
    world_renderer.dynamic_vertex_uploaded = true
    return true
}

world_frame_geometry_buffers_ensure :: proc(frame: int) -> bool {
    if frame < 0 || frame >= engine.MAX_FRAMES_IN_FLIGHT do return false
    ctx := world_renderer.ctx
    if ctx == nil do return false
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.vertex[frame],
        vk.DeviceSize(len(world_renderer.vertices) * size_of(World_Vertex)),
        {.VERTEX_BUFFER},
        "world dynamic vertex buffer",
    ) {
        return false
    }
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.static_vertex[frame],
        vk.DeviceSize(len(world_renderer.static_vertices) * size_of(World_Vertex)),
        {.VERTEX_BUFFER},
        "world static vertex buffer",
    ) {
        return false
    }
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.static_index[frame],
        vk.DeviceSize(len(world_renderer.static_indices) * size_of(u32)),
        {.INDEX_BUFFER},
        "world static index buffer",
    ) {
        return false
    }
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.static_indirect[frame],
        vk.DeviceSize(len(world_renderer.static_draw_commands) * size_of(vk.DrawIndexedIndirectCommand)),
        {.INDIRECT_BUFFER},
        "world static indirect buffer",
    ) {
        return false
    }
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.road_vertex[frame],
        vk.DeviceSize(len(world_renderer.road_geometry_cache) * size_of(World_Vertex)),
        {.VERTEX_BUFFER},
        "world road vertex buffer",
    ) {
        return false
    }
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.road_indirect[frame],
        vk.DeviceSize(len(world_renderer.road_draw_commands) * size_of(vk.DrawIndirectCommand)),
        {.INDIRECT_BUFFER},
        "world road indirect buffer",
    ) {
        return false
    }
    foliage_count :=
        len(world_renderer.foliage_vertices) +
        len(world_renderer.bougainvillea_vertices) +
        len(world_renderer.terrain_particle_vertices)
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.foliage_vertex[frame],
        vk.DeviceSize(foliage_count * size_of(Foliage_Vertex)),
        {.VERTEX_BUFFER},
        "world foliage vertex buffer",
    ) {
        return false
    }
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.bougainvillea_instance[frame],
        vk.DeviceSize(len(world_renderer.bougainvillea_instances) * size_of(Bougainvillea_Instance)),
        {.VERTEX_BUFFER},
        "world bougainvillea instance buffer",
    ) {
        return false
    }
    grass_count :=
        len(world_renderer.grass_instances) +
        len(world_renderer.wildflower_instances) +
        len(world_renderer.marsh_instances)
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.grass_instance[frame],
        vk.DeviceSize(grass_count * size_of(Grass_Instance)),
        {.VERTEX_BUFFER},
        "world grass instance buffer",
    ) {
        return false
    }
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.instance_vertex[frame],
        vk.DeviceSize(len(world_renderer.instance_vertices) * size_of(World_Vertex)),
        {.VERTEX_BUFFER},
        "world instance mesh vertex buffer",
    ) {
        return false
    }
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.instance_index[frame],
        vk.DeviceSize(len(world_renderer.instance_indices) * size_of(u32)),
        {.INDEX_BUFFER},
        "world instance mesh index buffer",
    ) {
        return false
    }
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.instance_data[frame],
        vk.DeviceSize(len(world_renderer.instance_flattened) * size_of(World_Mesh_Instance)),
        {.VERTEX_BUFFER},
        "world mesh instance buffer",
    ) {
        return false
    }
    return true
}

world_buffer_total_size :: proc(buffers: []engine.Vk_Buffer) -> u64 {
    total: u64
    for buffer in buffers do total += u64(buffer.size)
    return total
}

world_buffer_min_size :: proc(buffers: []engine.Vk_Buffer) -> u64 {
    if len(buffers) == 0 do return 0
    minimum := u64(buffers[0].size)
    for buffer in buffers[1:] do minimum = min(minimum, u64(buffer.size))
    return minimum
}

world_instance_meshes_clear :: proc() {
    for &mesh in world_renderer.instance_meshes do delete(mesh.instances)
    clear(&world_renderer.instance_meshes)
    clear(&world_renderer.instance_vertices)
    clear(&world_renderer.instance_indices)
    clear(&world_renderer.instance_flattened)
    generated_plant_middle_branch_mesh = -1
    generated_plant_middle_clump_mesh = -1
    generated_plant_leaf_meshes = {}
}

world_instance_mesh_instances_clear :: proc() {
    for &mesh in world_renderer.instance_meshes do clear(&mesh.instances)
    clear(&world_renderer.instance_flattened)
}

world_instance_mesh_add :: proc(vertices: []World_Vertex, indices: []u32, casts_shadow: bool = true) -> int {
    if len(vertices) == 0 || len(indices) == 0 do return -1
    mesh := World_Instance_Mesh {
        first_vertex    = u32(len(world_renderer.instance_vertices)),
        vertex_capacity = u32(len(vertices)),
        first_index     = u32(len(world_renderer.instance_indices)),
        index_count     = u32(len(indices)),
        index_capacity  = u32(len(indices)),
        casts_shadow    = casts_shadow,
        instances       = make([dynamic]World_Mesh_Instance, 0, 64),
    }
    append(&world_renderer.instance_vertices, ..vertices)
    append(&world_renderer.instance_indices, ..indices)
    append(&world_renderer.instance_meshes, mesh)
    return len(world_renderer.instance_meshes) - 1
}

world_instance_mesh_replace :: proc(
    mesh_index: int,
    vertices: []World_Vertex,
    indices: []u32,
    casts_shadow: bool = true,
) -> bool {
    if mesh_index < 0 || mesh_index >= len(world_renderer.instance_meshes) || len(vertices) == 0 || len(indices) == 0 {
        return false
    }
    mesh := &world_renderer.instance_meshes[mesh_index]
    if len(vertices) > int(mesh.vertex_capacity) || len(indices) > int(mesh.index_capacity) do return false
    first_vertex := int(mesh.first_vertex)
    first_index := int(mesh.first_index)
    copy(world_renderer.instance_vertices[first_vertex:first_vertex + len(vertices)], vertices)
    copy(world_renderer.instance_indices[first_index:first_index + len(indices)], indices)
    mesh.index_count = u32(len(indices))
    mesh.casts_shadow = casts_shadow
    clear(&mesh.instances)
    return true
}

world_instance_mesh_emit :: proc(mesh_index: int, instance: World_Mesh_Instance) {
    if mesh_index < 0 || mesh_index >= len(world_renderer.instance_meshes) do return
    append(&world_renderer.instance_meshes[mesh_index].instances, instance)
}

world_instances_flatten :: proc() {
    clear(&world_renderer.instance_flattened)
    for &mesh in world_renderer.instance_meshes {
        mesh.first_instance = u32(len(world_renderer.instance_flattened))
        append(&world_renderer.instance_flattened, ..mesh.instances[:])
    }
}

@(no_instrumentation)
world_color :: #force_inline proc(color: canvas2d.Color) -> [4]f32 {
    return {f32(color.r) / 255, f32(color.g) / 255, f32(color.b) / 255, f32(color.a) / 255}
}

world_srgb_to_linear_channel :: proc(value: f32) -> f32 {
    clamped := clamp(value, 0, 1)
    if clamped <= .04045 do return clamped / 12.92
    return f32(math.pow(f64((clamped + .055) / 1.055), 2.4))
}

world_linear_to_srgb_channel :: proc(value: f32) -> f32 {
    clamped := clamp(value, 0, 1)
    if clamped <= .0031308 do return clamped * 12.92
    return 1.055 * f32(math.pow(f64(clamped), 1.0 / 2.4)) - .055
}

world_gltf_material_color :: proc(tint: canvas2d.Color, factor: [4]f32, alpha: u8) -> [4]f32 {
    // glTF factors are linear while palette tints are authored as sRGB. Return
    // sRGB here because world.slang performs the shared vertex-color decode.
    return {
        world_linear_to_srgb_channel(world_srgb_to_linear_channel(f32(tint.r) / 255) * clamp(factor[0], 0, 1)),
        world_linear_to_srgb_channel(world_srgb_to_linear_channel(f32(tint.g) / 255) * clamp(factor[1], 0, 1)),
        world_linear_to_srgb_channel(world_srgb_to_linear_channel(f32(tint.b) / 255) * clamp(factor[2], 0, 1)),
        f32(tint.a) / 255 * clamp(factor[3], 0, 1) * f32(alpha) / 255,
    }
}

world_sky_horizon_color :: proc(sky: atmosphere.Sky_State) -> canvas2d.Color {
    horizon := canvas2d.Color{184, 209, 209, 255}
    storm := clamp(sky.weather.severity * .68 + sky.weather.precipitation * .52, 0, 1)
    storm_horizon := color_lerp({92, 110, 117, 255}, {112, 125, 128, 255}, sky.weather.haze * .55)
    horizon = color_lerp(horizon, storm_horizon, storm * .82)
    horizon = color_lerp({24, 40, 59, 255}, horizon, sky.daylight)
    return {
        u8(clamp(f32(horizon.r) + 255 * .34 * sky.twilight, 0, 255)),
        u8(clamp(f32(horizon.g) + 255 * .16 * sky.twilight, 0, 255)),
        u8(clamp(f32(horizon.b) + 255 * .08 * sky.twilight, 0, 255)),
        255,
    }
}

world_camera_near_clip :: proc(editor: ^Editor) -> f32 {
    if editor == nil do return WORLD_EDITOR_NEAR_CLIP
    if editor.in_map {
        return driving_aircraft(editor) ? WORLD_FLIGHT_NEAR_CLIP : WORLD_PLAY_NEAR_CLIP
    }
    // A fixed 100 m editor near plane is appropriate for island overviews but
    // clips the selected tree, roots, and understory when the author zooms in.
    // Scale with orbit distance while retaining the old cap for distant views.
    distance := editor.editor_camera.distance
    return clamp(distance * distance / 720, f32(2), WORLD_EDITOR_NEAR_CLIP)
}

world_sphere_in_view :: proc(editor: ^Editor, center: third_person.Vec3, radius: f32, margin: f32 = 0) -> bool {
    if editor == nil do return false
    focal_length := editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : f32(1.35)
    camera := perspective_camera(editor.camera_pose, focal_length)
    width := max(canvas2d.GetScreenWidth(), 1)
    height := max(canvas2d.GetScreenHeight(), 1)
    visible := static_sphere_in_frustum(
        camera,
        center,
        max(radius + margin, f32(0)),
        f32(width) / f32(height),
        world_camera_near_clip(editor),
        WORLD_FAR_CLIP,
    )
    if visible do return true
    // The PiP replays the world graph with a second camera, so retain scene
    // objects visible to that camera as well as those visible to the main view.
    if editor.in_map && driving_aircraft(editor) && editor.bomber_mode && editor.bomber_pip_valid {
        pip_camera := perspective_camera(editor.bomber_pip_pose, 1.55)
        return static_sphere_in_frustum(
            pip_camera,
            center,
            max(radius + margin, f32(0)),
            f32(16) / 9,
            WORLD_FLIGHT_NEAR_CLIP,
            WORLD_FAR_CLIP,
        )
    }
    return false
}

world_scene_sun :: proc(editor: ^Editor, sky: atmosphere.Sky_State) -> [4]f32 {
    if editor != nil && editor.vehicle_paint_scene {
        // The paint hangar uses a brighter studio key so colors and surface
        // coverage remain easy to judge around the full aircraft.
        return {.28, .88, .38, 1.6}
    }
    // Once the solar key has faded, reuse the directional-light slot for the
    // moon. World_Push is already at Vulkan's guaranteed 128-byte push-constant
    // limit, so moon strength travels in fog_color.w below.
    if sky.daylight <= .02 {
        return {sky.moon_direction[0], sky.moon_direction[1], sky.moon_direction[2], sky.daylight}
    }
    return {sky.sun_direction[0], sky.sun_direction[1], sky.sun_direction[2], sky.daylight}
}

world_scene_moonlight :: proc(sky: atmosphere.Sky_State) -> f32 {
    above_horizon := clamp((sky.moon_direction[1] + .04) / .18, 0, 1)
    night := 1 - sky.daylight
    cloud_occlusion := clamp(
        sky.weather.cloud_cover * .82 + sky.weather.precipitation * .72 + sky.weather.haze * .34,
        0,
        1,
    )
    // This is deliberately an art-directed readability value rather than a
    // physical lux ratio. Phase and horizon position still control whether a
    // lunar key exists at all, and weather can extinguish it.
    return sky.moon_illumination * above_horizon * night * (1 - cloud_occlusion)
}

@(no_instrumentation)
world_vertex :: #force_inline proc(point: third_person.Vec3, color: canvas2d.Color) -> World_Vertex {
    return {{point.x, point.y, point.z}, world_color(color), .BRDF, {0, 1, 0}, {0, .9}, {}}
}

@(no_instrumentation)
world_water_vertex :: #force_inline proc(point: third_person.Vec3, color: canvas2d.Color) -> World_Vertex {
    return {{point.x, point.y, point.z}, world_color(color), .Water, {0, 1, 0}, {}, {}}
}

@(no_instrumentation)
world_ocean_vertex :: #force_inline proc(
    editor: ^Editor,
    point: third_person.Vec3,
    color: canvas2d.Color,
) -> World_Vertex {
    vertex := world_water_vertex(point, color)
    // Ocean shading receives the actual heightfield elevation above sea level.
    // Interpolation across the local ocean grid turns that signal into a
    // shoreline band without baking the default islands into the shader.
    land_height, _, land_found := terrain.sample_land(&editor.project, 0, point.x, point.z)
    elevation := land_height - editor.project.sea_level
    if !land_found {
        depth := terrain.sample_water_interface(&editor.project, point.x, point.z).depth
        // Generated coastal bathymetry stores depth below sea level. Convert
        // the upper shelf into the positive shallowness signal expected by the
        // water shader and suppress broad breaking foam across that shelf.
        vertex.material.x = clamp(1 - depth / 13, 0, 1) * 1.35
        vertex.material.y = -1
    } else {
        // The ocean mesh extends beneath hidden dry land. Carry maximum
        // shallowness inland so mixed shoreline triangles interpolate
        // continuously from the submerged shelf. Passing the small positive
        // terrain elevation directly inverted the signal at the waterline and
        // produced conspicuous dark triangular teeth.
        vertex.material.x = 1.35
        // Match the submerged shelf marker. Interpolating this component from
        // +1 to -1 made abs(material.y) pass through zero inside every mixed
        // shoreline triangle, drawing a false deep-water diagonal.
        vertex.material.y = -1
    }
    if habitat, found := terrain.sample_marine_habitat(&editor.project, point.x, point.z); found {
        // A negative alpha is an internal vertex sentinel. The vertex shader
        // keeps these values linear and the water fragment path restores
        // opaque output after decoding disturbance from it.
        vertex.color = {habitat.seagrass, habitat.macroalgae, habitat.coralligenous, -1 - habitat.disturbance}
    }
    if lab_scene_is_active(editor, "dunes") {
        // Carry shallowness under the hidden landward part of the ocean grid
        // so interpolation reaches the exact waterline.
        shallowness := dunes_lab_water_shallowness(editor, point.x, point.z)
        // Negative Y preserves the shallow tint while suppressing the generic
        // breaking-shore foam mask across the full submerged shelf.
        vertex.material = {shallowness * 1.35, -1}
    }
    if lab_scene_is_active(editor, "markov-island") {
        // Give the silhouette lab an explicit, art-directed bathymetry signal.
        // The broad signed-distance shelf is wide enough for the local ocean
        // grid to interpolate smoothly, unlike the fine dry-land heightfield
        // whose signal produced a second polygonal coastline.
        nx := point.x / MARKOV_ISLAND_HALF_X
        nz := point.z / MARKOV_ISLAND_HALF_Z
        distance := islands.sample_signed_distance(&markov_island_plan, nx, nz)
        shelf_noise := markov_island_shelf_noise(nx, nz)
        shelf_width := MARKOV_ISLAND_SHELF_CELLS * (1 + shelf_noise * .12)
        shelf_weight := 1 - markov_island_smooth_weight(distance / shelf_width)
        // Negative Y marks an underwater color field rather than a breaking
        // shoreline; the water shader uses its magnitude for tinting but does
        // not generate an outer foam band.
        // Keep the signal within the shader's useful shallow-to-deep range so
        // the whole exaggerated shelf reads as a continuous turquoise-to-teal
        // gradient instead of a broad, uniformly bright patch.
        vertex.material = {shelf_weight * .82, -1}
    }
    return vertex
}

@(no_instrumentation)
world_fountain_water_vertex :: #force_inline proc(point: third_person.Vec3, color: canvas2d.Color) -> World_Vertex {
    return {{point.x, point.y, point.z}, world_color(color), .Fountain_Water, {0, 1, 0}, {}, {}}
}

@(no_instrumentation)
world_foliage_vertex :: #force_inline proc(
    point: third_person.Vec3,
    color: canvas2d.Color,
    normal: third_person.Vec3,
) -> World_Vertex {
    return {{point.x, point.y, point.z}, world_color(color), .Foliage, {normal.x, normal.y, normal.z}, {}, {}}
}

@(no_instrumentation)
world_eye_vertex :: #force_inline proc(
    point: third_person.Vec3,
    color: canvas2d.Color,
    normal: third_person.Vec3,
) -> World_Vertex {
    return {{point.x, point.y, point.z}, world_color(color), .Eye, {normal.x, normal.y, normal.z}, {}, {}}
}

@(no_instrumentation)
world_triangle :: #force_inline proc(a, b, c: third_person.Vec3, color: canvas2d.Color) {
    world_triangle_material(a, b, c, color, .BRDF)
}

@(no_instrumentation)
world_triangle_material :: #force_inline proc(
    a, b, c: third_person.Vec3,
    color: canvas2d.Color,
    kind: World_Material_Kind,
) {
    vertices := [3]World_Vertex{world_vertex(a, color), world_vertex(b, color), world_vertex(c, color)}
    normal := linalg.normalize0(linalg.cross(b - a, c - a))
    for &vertex in vertices {
        vertex.kind = kind
        vertex.normal = {normal.x, normal.y, normal.z}
        if kind == .BRDF {
            // Generic procedural solids are matte dielectric surfaces. Keep
            // callers on the shared material/lighting path without requiring
            // every primitive builder to repeat the default material values.
            vertex.material = {0, .9}
        } else if kind == .Car_Paint {
            vertex.material = {f32(Car_Paint_Finish.Opaque), .54}
        }
    }
    append(&world_renderer.vertices, ..vertices[:])
}

@(no_instrumentation)
world_triangle_smooth_lit :: #force_inline proc(
    a, b, c: third_person.Vec3,
    normal_a, normal_b, normal_c: third_person.Vec3,
    color_a, color_b, color_c: canvas2d.Color,
    roughness: f32 = .9,
    material_kind: World_Material_Kind = .BRDF,
    car_paint_finish: Car_Paint_Finish = .Opaque,
) {
    points := [3]third_person.Vec3{a, b, c}
    normals := [3]third_person.Vec3{normal_a, normal_b, normal_c}
    colors := [3]canvas2d.Color{color_a, color_b, color_c}
    vertices: [3]World_Vertex
    for index in 0 ..< 3 {
        vertices[index] = world_vertex(points[index], colors[index])
        vertices[index].kind = material_kind
        normal := linalg.normalize0(normals[index])
        vertices[index].normal = {normal.x, normal.y, normal.z}
        vertices[index].material = {material_kind == .Car_Paint ? f32(car_paint_finish) : 0, clamp(roughness, .04, 1)}
    }
    append(&world_renderer.vertices, ..vertices[:])
}

@(no_instrumentation)
world_triangle_bark :: #force_inline proc(
    a, b, c: third_person.Vec3,
    normal_a, normal_b, normal_c: third_person.Vec3,
    color_a, color_b, color_c: canvas2d.Color,
    uv_a, uv_b, uv_c: [2]f32,
    pattern, roughness: f32,
    detail_strength: f32 = 1,
) {
    points := [3]third_person.Vec3{a, b, c}
    normals := [3]third_person.Vec3{normal_a, normal_b, normal_c}
    colors := [3]canvas2d.Color{color_a, color_b, color_c}
    uvs := [3][2]f32{uv_a, uv_b, uv_c}
    vertices: [3]World_Vertex
    for index in 0 ..< 3 {
        vertices[index] = world_vertex(points[index], colors[index])
        vertices[index].kind = .Bark
        normal := linalg.normalize0(normals[index])
        vertices[index].normal = {normal.x, normal.y, normal.z}
        // Preserve the integer pattern in the whole part and carry the LOD
        // detail strength in two decimal digits. Bark has only two generic
        // material channels, and roughness needs the other one unchanged.
        vertices[index].material = {pattern + clamp(detail_strength, f32(0), f32(1)) * .01, clamp(roughness, .04, 1)}
        vertices[index].uv = uvs[index]
    }
    append(&world_renderer.vertices, ..vertices[:])
}

@(no_instrumentation)
world_aircraft_triangle :: #force_inline proc(
    a, b, c: third_person.Vec3,
    color: canvas2d.Color,
    uv_a, uv_b, uv_c: [2]f32,
    paint_layer: f32,
    paintable := true,
) {
    vertices := [3]World_Vertex{world_vertex(a, color), world_vertex(b, color), world_vertex(c, color)}
    normal := linalg.normalize0(linalg.cross((b - a), (c - a)))
    for &vertex in vertices {
        vertex.kind = .Vehicle
        vertex.material[0] = paintable ? 1 : 0
        vertex.material[1] = paint_layer
        vertex.normal = {normal.x, normal.y, normal.z}
    }
    vertices[0].uv = uv_a
    vertices[1].uv = uv_b
    vertices[2].uv = uv_c
    append(&world_renderer.vertices, ..vertices[:])
}

@(no_instrumentation)
world_aircraft_triangle_smooth :: #force_inline proc(
    a, b, c: third_person.Vec3,
    normal_a, normal_b, normal_c: third_person.Vec3,
    color: canvas2d.Color,
    uv_a, uv_b, uv_c: [2]f32,
    paint_layer: f32,
    paintable := true,
) {
    vertices := [3]World_Vertex{world_vertex(a, color), world_vertex(b, color), world_vertex(c, color)}
    normals := [3]third_person.Vec3{normal_a, normal_b, normal_c}
    uvs := [3][2]f32{uv_a, uv_b, uv_c}
    for index in 0 ..< 3 {
        vertices[index].kind = .Vehicle
        vertices[index].material[0] = paintable ? 1 : 0
        vertices[index].material[1] = paint_layer
        normal := linalg.normalize0(normals[index])
        vertices[index].normal = {normal.x, normal.y, normal.z}
        vertices[index].uv = uvs[index]
    }
    append(&world_renderer.vertices, ..vertices[:])
}

@(no_instrumentation)
world_triangle_colored :: #force_inline proc(a, b, c: third_person.Vec3, color_a, color_b, color_c: canvas2d.Color) {
    vertices := [3]World_Vertex{world_vertex(a, color_a), world_vertex(b, color_b), world_vertex(c, color_c)}
    normal := linalg.normalize0(linalg.cross(b - a, c - a))
    for &vertex in vertices {
        vertex.kind = .BRDF
        vertex.normal = {normal.x, normal.y, normal.z}
        vertex.material = {0, .9}
    }
    append(&world_renderer.vertices, ..vertices[:])
}

world_greek_asset_vertex :: proc(
    point: third_person.Vec3,
    color: [4]f32,
    normal: third_person.Vec3,
    metallic, roughness: f32,
) -> World_Vertex {
    return {
        {point.x, point.y, point.z},
        color,
        .BRDF,
        {normal.x, normal.y, normal.z},
        {clamp(metallic, 0, 1), clamp(roughness, .04, 1)},
        {},
    }
}

@(no_instrumentation)
world_triangle_foliage :: #force_inline proc(
    a, b, c: third_person.Vec3,
    color_a, color_b, color_c: canvas2d.Color,
    normal_a, normal_b, normal_c: third_person.Vec3,
    material_kind: World_Material_Kind = .Foliage,
) {
    vertices := [3]World_Vertex {
        world_foliage_vertex(a, color_a, normal_a),
        world_foliage_vertex(b, color_b, normal_b),
        world_foliage_vertex(c, color_c, normal_c),
    }
    for &vertex in vertices do vertex.kind = material_kind
    append(&world_renderer.vertices, ..vertices[:])
}

@(no_instrumentation)
world_triangle_leaf_textured :: #force_inline proc(
    a, b, c: third_person.Vec3,
    color_a, color_b, color_c: canvas2d.Color,
    normal_a, normal_b, normal_c: third_person.Vec3,
    uv_a, uv_b, uv_c: [2]f32,
    shape: u32,
) {
    vertices := [3]World_Vertex {
        world_foliage_vertex(a, color_a, normal_a),
        world_foliage_vertex(b, color_b, normal_b),
        world_foliage_vertex(c, color_c, normal_c),
    }
    uvs := [3][2]f32{uv_a, uv_b, uv_c}
    for &vertex, index in vertices {
        vertex.kind = .Leaf
        vertex.uv = uvs[index]
        vertex.material = {f32(shape), 1}
    }
    append(&world_renderer.vertices, ..vertices[:])
}

@(no_instrumentation)
world_quad :: #force_inline proc(a, b, c, d: third_person.Vec3, color: canvas2d.Color) {
    world_triangle(a, b, c, color)
    world_triangle(a, c, d, color)
}

@(no_instrumentation)
world_quad_material :: #force_inline proc(
    a, b, c, d: third_person.Vec3,
    color: canvas2d.Color,
    kind: World_Material_Kind,
) {
    vertices := [6]World_Vertex {
        world_vertex(a, color),
        world_vertex(b, color),
        world_vertex(c, color),
        world_vertex(a, color),
        world_vertex(c, color),
        world_vertex(d, color),
    }
    normal := linalg.normalize0(linalg.cross(b - a, c - a))
    for &vertex in vertices {
        vertex.kind = kind
        vertex.normal = {normal.x, normal.y, normal.z}
        if kind == .BRDF {
            vertex.material = {0, .9}
        } else if kind == .Car_Paint {
            vertex.material = {f32(Car_Paint_Finish.Opaque), .54}
        }
    }
    append(&world_renderer.vertices, ..vertices[:])
}
