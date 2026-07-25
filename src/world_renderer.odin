package main

import architecture "../packages/architecture"
import atmosphere "../packages/atmosphere"
import mouse_tail "../packages/mouse_tail"
import particles "../packages/particles"
import render_graph "../packages/render_graph"
import roads "../packages/roads"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:math"
import "core:mem"
import vk "vendor:vulkan"
import rl "zelda_engine:canvas2d"
import engine "zelda_engine:engine"
import render3d "zelda_engine:render3d"
import resources "zelda_engine:render_resources"

WORLD_VERTEX_CAPACITY :: 480_000
ROAD_VERTEX_CAPACITY :: 320_000
FOLIAGE_VERTEX_CAPACITY :: 24_000
CLIPMAP_GRID_RESOLUTION :: (terrain.RING_RESOLUTION - 1) / 2 + 2
CLIPMAP_VERTEX_COUNT :: CLIPMAP_GRID_RESOLUTION * CLIPMAP_GRID_RESOLUTION
CLIPMAP_FULL_INDEX_COUNT :: (CLIPMAP_GRID_RESOLUTION - 1) * (CLIPMAP_GRID_RESOLUTION - 1) * 6

// Keep the world pass useful beyond the immediate flight envelope. The
// clipmap already provides this coverage; these values prevent the camera
// projection, fog, and ocean fallback from hiding it prematurely.
WORLD_FAR_CLIP :: f32(12000)
WORLD_PLAY_NEAR_CLIP :: f32(.08)
WORLD_FLIGHT_NEAR_CLIP :: f32(.5)
WORLD_EDITOR_NEAR_CLIP :: f32(100)
WORLD_FOG_START :: f32(4500)
WORLD_FOG_END :: f32(11000)

World_Vertex :: struct {
    position: [3]f32,
    color:    [4]f32,
    kind:     f32,
    normal:   [3]f32,
}

Foliage_Vertex :: struct {
    position: [3]f32,
    uv:       [2]f32,
    color:    [4]f32,
}

World_Push :: struct {
    camera_position: [4]f32,
    camera_right:    [4]f32,
    camera_up:       [4]f32,
    camera_forward:  [4]f32,
    projection:      [4]f32,
    fog_color:       [4]f32,
    water:           [4]f32,
    sun:             [4]f32,
}

Sky_Push :: struct {
    camera_right:   [4]f32,
    camera_up:      [4]f32,
    camera_forward: [4]f32,
    sun_direction:  [4]f32,
    time_light:     [4]f32,
    wind_cloud:     [4]f32,
    haze_severity:  [4]f32,
}

World_Renderer :: struct {
    editor:                    ^Editor,
    ctx:                       ^engine.Vk_Context,
    pipelines:                 [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    road_pipelines:            [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    sky_pipelines:             [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    particle_pipelines:        [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    foliage_pipelines:         [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    layout:                    vk.PipelineLayout,
    sky_layout:                vk.PipelineLayout,
    foliage_layout:            vk.PipelineLayout,
    foliage_descriptor_layout: vk.DescriptorSetLayout,
    foliage_descriptor_pool:   vk.DescriptorPool,
    foliage_descriptor:        vk.DescriptorSet,
    foliage_atlas:             resources.Image,
    vertex:                    [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    road_vertex:               [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    foliage_vertex:            [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    vertices:                  [dynamic]World_Vertex,
    road_vertices:             [dynamic]World_Vertex,
    foliage_vertices:          [dynamic]Foliage_Vertex,
    clipmap_vertex:            [engine.MAX_FRAMES_IN_FLIGHT][terrain.CLIPMAP_LEVELS]engine.Vk_Buffer,
    clipmap_index:             engine.Vk_Buffer,
    clipmap_full_indices:      u32,
    clipmap_ring_first:        u32,
    clipmap_ring_indices:      u32,
    clipmap_revision:          [engine.MAX_FRAMES_IN_FLIGHT]u64,
    clipmap_center:            [engine.MAX_FRAMES_IN_FLIGHT][terrain.CLIPMAP_LEVELS][2]f32,
    clipmap_valid:             [engine.MAX_FRAMES_IN_FLIGHT][terrain.CLIPMAP_LEVELS]bool,
    road_mesh:                 roads.Mesh,
    road_revision:             u64,
    initialized:               bool,
}

world_renderer: World_Renderer

#assert(size_of(World_Push) == 128)
#assert(size_of(Sky_Push) == 112)
#assert(offset_of(Sky_Push, sun_direction) == 48)
#assert(offset_of(Sky_Push, time_light) == 64)
#assert(offset_of(Sky_Push, wind_cloud) == 80)
#assert(offset_of(Sky_Push, haze_severity) == 96)

world_color :: proc(color: rl.Color) -> [4]f32 {
    return {f32(color.r) / 255, f32(color.g) / 255, f32(color.b) / 255, f32(color.a) / 255}
}

world_sky_horizon_color :: proc(sky: atmosphere.Sky_State) -> rl.Color {
    horizon := rl.Color{184, 209, 209, 255}
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

world_vertex :: proc(point: third_person.Vec3, color: rl.Color) -> World_Vertex {
    return {{point.x, point.y, point.z}, world_color(color), 0, {0, 1, 0}}
}

world_water_vertex :: proc(point: third_person.Vec3, color: rl.Color) -> World_Vertex {
    return {{point.x, point.y, point.z}, world_color(color), 1, {0, 1, 0}}
}

world_foliage_vertex :: proc(point: third_person.Vec3, color: rl.Color, normal: third_person.Vec3) -> World_Vertex {
    return {{point.x, point.y, point.z}, world_color(color), 3, {normal.x, normal.y, normal.z}}
}

world_triangle :: proc(a, b, c: third_person.Vec3, color: rl.Color) {
    if len(world_renderer.vertices) + 3 > WORLD_VERTEX_CAPACITY do return
    append(&world_renderer.vertices, world_vertex(a, color), world_vertex(b, color), world_vertex(c, color))
}

world_triangle_colored :: proc(a, b, c: third_person.Vec3, color_a, color_b, color_c: rl.Color) {
    if len(world_renderer.vertices) + 3 > WORLD_VERTEX_CAPACITY do return
    append(&world_renderer.vertices, world_vertex(a, color_a), world_vertex(b, color_b), world_vertex(c, color_c))
}

world_greek_asset_vertex :: proc(
    point: third_person.Vec3,
    color: rl.Color,
    normal: third_person.Vec3,
) -> World_Vertex {
    return {{point.x, point.y, point.z}, world_color(color), 0, {normal.x, normal.y, normal.z}}
}

world_greek_asset_mesh :: proc(asset: Greek_Asset, placement: Greek_Placement, alpha: u8) {
    if !asset.ready do return
    color := asset.color
    color.a = alpha
    for index := 0; index + 2 < len(asset.mesh.indices); index += 3 {
        ia, ib, ic := asset.mesh.indices[index], asset.mesh.indices[index + 1], asset.mesh.indices[index + 2]
        if ia >= u32(len(asset.mesh.vertices)) || ib >= u32(len(asset.mesh.vertices)) || ic >= u32(len(asset.mesh.vertices)) do continue
        a := greek_asset_local_to_world(asset, placement, asset.mesh.vertices[ia])
        b := greek_asset_local_to_world(asset, placement, asset.mesh.vertices[ib])
        c := greek_asset_local_to_world(asset, placement, asset.mesh.vertices[ic])
        normal := vec_normalize(
            vec_cross({x = b.x - a.x, y = b.y - a.y, z = b.z - a.z}, {x = c.x - a.x, y = c.y - a.y, z = c.z - a.z}),
        )
        if len(world_renderer.vertices) + 3 > WORLD_VERTEX_CAPACITY do return
        append(
            &world_renderer.vertices,
            world_greek_asset_vertex(a, color, normal),
            world_greek_asset_vertex(b, color, normal),
            world_greek_asset_vertex(c, color, normal),
        )
    }
}

world_greek_assets :: proc(editor: ^Editor) {
    if editor == nil do return
    for placement in editor.greek_placements[:editor.greek_placement_count] {
        if placement.asset_index < 0 || placement.asset_index >= GREEK_ASSET_CAPACITY do continue
        world_greek_asset_mesh(editor.greek_assets[placement.asset_index], placement, 255)
    }
    if editor.greek_placement_mode && editor.cursor_hit && greek_asset_selected_ready(editor) {
        preview := Greek_Placement {
            asset_index = editor.greek_asset_selected,
            x           = editor.cursor_world_x,
            z           = editor.cursor_world_z,
            base_y      = terrain.sample_height(&editor.project, 0, editor.cursor_world_x, editor.cursor_world_z),
            rotation    = editor.greek_asset_rotation,
            scale       = editor.greek_asset_scale,
        }
        world_greek_asset_mesh(editor.greek_assets[editor.greek_asset_selected], preview, 128)
    }
}

world_triangle_foliage :: proc(
    a, b, c: third_person.Vec3,
    color_a, color_b, color_c: rl.Color,
    normal_a, normal_b, normal_c: third_person.Vec3,
) {
    if len(world_renderer.vertices) + 3 > WORLD_VERTEX_CAPACITY do return
    append(
        &world_renderer.vertices,
        world_foliage_vertex(a, color_a, normal_a),
        world_foliage_vertex(b, color_b, normal_b),
        world_foliage_vertex(c, color_c, normal_c),
    )
}

world_quad :: proc(a, b, c, d: third_person.Vec3, color: rl.Color) {
    world_triangle(a, b, c, color)
    world_triangle(a, c, d, color)
}

world_quad_colored :: proc(a, b, c, d: third_person.Vec3, color_a, color_b, color_c, color_d: rl.Color) {
    world_triangle_colored(a, b, c, color_a, color_b, color_c)
    world_triangle_colored(a, c, d, color_a, color_c, color_d)
}

world_water_quad :: proc(a, b, c, d: third_person.Vec3, color: rl.Color) {
    if len(world_renderer.vertices) + 6 > WORLD_VERTEX_CAPACITY do return
    append(
        &world_renderer.vertices,
        world_water_vertex(a, color),
        world_water_vertex(b, color),
        world_water_vertex(c, color),
        world_water_vertex(a, color),
        world_water_vertex(c, color),
        world_water_vertex(d, color),
    )
}

road_world_point :: proc(editor: ^Editor, vertex: roads.Vertex) -> third_person.Vec3 {
    clearance := f32(.12)
    if vertex.surface == .Shoulder {
        clearance = .05
    } else if vertex.surface == .Verge {
        clearance = .018
    }
    terrain_y := terrain.sample_height(&editor.project, 0, vertex.position.x, vertex.position.z)
    return {vertex.position.x, max(vertex.position.y, terrain_y + clearance), vertex.position.z}
}

road_surface_color :: proc(surface: roads.Surface, pavement: roads.Pavement) -> rl.Color {
    if surface == .Verge {
        // Outer verge vertices are transparent and interpolate into the opaque
        // shoulder, revealing terrain through a soft, pavement-aware tint.
        switch pavement {
        case .Asphalt:
            return {82, 111, 67, 0}
        case .Gravel:
            return {105, 119, 70, 0}
        case .Cobblestone:
            return {92, 112, 69, 0}
        case .Dirt:
            return {118, 101, 58, 0}
        }
    }
    if surface == .Shoulder {
        switch pavement {
        case .Asphalt:
            return {164, 148, 116, 255}
        case .Gravel:
            return {183, 163, 126, 255}
        case .Cobblestone:
            return {151, 146, 126, 255}
        case .Dirt:
            return {139, 96, 61, 255}
        }
    }
    switch pavement {
    case .Asphalt:
        return surface == .Junction ? rl.Color{86, 92, 86, 255} : rl.Color{91, 97, 90, 255}
    case .Gravel:
        return {158, 143, 111, 255}
    case .Cobblestone:
        return {119, 130, 124, 255}
    case .Dirt:
        return {158, 104, 61, 255}
    }
    return {91, 97, 90, 255}
}

world_road_editor_link :: proc(a, b: roads.Vec3, width: f32, color: rl.Color) {
    dx, dz := b.x - a.x, b.z - a.z
    length := f32(math.sqrt(f64(dx * dx + dz * dz)))
    if length <= .001 do return
    side_x, side_z := -dz / length * width * .5, dx / length * width * .5
    lift := f32(.12)
    world_quad(
        {a.x - side_x, a.y + lift, a.z - side_z},
        {b.x - side_x, b.y + lift, b.z - side_z},
        {b.x + side_x, b.y + lift, b.z + side_z},
        {a.x + side_x, a.y + lift, a.z + side_z},
        color,
    )
}

world_road_vertex :: proc(editor: ^Editor, vertex: roads.Vertex, color: rl.Color) -> World_Vertex {
    point := road_world_point(editor, vertex)
    // Road UV and pavement live in the normal channel because the dedicated
    // road pass does not need the generic mesh normal. This keeps the existing
    // compact vertex format and draw call while giving the fragment shader
    // stable material-space coordinates.
    return {{point.x, point.y, point.z}, world_color(color), 4, {vertex.uv[0], vertex.uv[1], f32(vertex.pavement)}}
}

world_road_triangle_colored :: proc(editor: ^Editor, a, b, c: roads.Vertex, color_a, color_b, color_c: rl.Color) {
    if len(world_renderer.road_vertices) + 3 > ROAD_VERTEX_CAPACITY do return
    append(
        &world_renderer.road_vertices,
        world_road_vertex(editor, a, color_a),
        world_road_vertex(editor, b, color_b),
        world_road_vertex(editor, c, color_c),
    )
}

world_roads :: proc(editor: ^Editor) {
    if editor == nil do return
    graph := &editor.project.road_graph
    if world_renderer.road_revision != editor.project.revision {
        roads.mesh_destroy(&world_renderer.road_mesh)
        if graph.edge_count > 0 do world_renderer.road_mesh = roads.bake(graph)
        world_renderer.road_revision = editor.project.revision
    }
    mesh := &world_renderer.road_mesh
    if len(mesh.indices) > 0 {
        for triangle in 0 ..< len(mesh.indices) / 3 {
            a := mesh.vertices[mesh.indices[triangle * 3]]
            b := mesh.vertices[mesh.indices[triangle * 3 + 1]]
            c := mesh.vertices[mesh.indices[triangle * 3 + 2]]
            world_road_triangle_colored(
                editor,
                a,
                b,
                c,
                road_surface_color(a.surface, a.pavement),
                road_surface_color(b.surface, b.pavement),
                road_surface_color(c.surface, c.pavement),
            )
        }
    }
    if editor.in_map || !editor.road_mode || editor.capture_world_only do return
    for node, index in graph.nodes[:graph.node_count] {
        selected := index == editor.road_selected_node
        color: rl.Color = selected ? {244, 216, 103, 255} : {101, 226, 203, 255}
        size := selected ? f32(4.5) : f32(3.2)
        world_box({node.position.x, node.position.y + 1.3, node.position.z}, {size, 2.6, size}, color)
    }
    if editor.road_selected_node < 0 || editor.road_selected_node >= graph.node_count do return
    for edge in graph.edges[:graph.edge_count] {
        if edge.from != editor.road_selected_node && edge.to != editor.road_selected_node do continue
        start := graph.nodes[edge.from].position
        end := graph.nodes[edge.to].position
        world_road_editor_link(start, edge.control_from, .75, {76, 196, 191, 230})
        world_road_editor_link(end, edge.control_to, .75, {76, 196, 191, 230})
        world_box(
            {edge.control_from.x, edge.control_from.y + 1.1, edge.control_from.z},
            {3, 2.2, 3},
            {83, 232, 225, 255},
        )
        world_box({edge.control_to.x, edge.control_to.y + 1.1, edge.control_to.z}, {3, 2.2, 3}, {83, 232, 225, 255})
    }
}

world_ocean :: proc(editor: ^Editor) {
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    extent := editor.in_map ? f32(12000) : f32(15000)
    divisions := editor.in_map ? 48 : 32
    cell := extent * 2 / f32(divisions)
    // A snapped tiled field surrounds the camera in every direction. Unlike the
    // former forward slab, it has no near edge for a high, downward-looking
    // camera to expose at the bottom of the viewport.
    center_x := f32(math.floor(f64(camera.position.x / cell))) * cell
    center_z := f32(math.floor(f64(camera.position.z / cell))) * cell
    ocean_y := editor.project.sea_level - (editor.in_map ? f32(.08) : f32(2))
    color := rl.Color{48, 112, 142, 255}
    for z_index in 0 ..< divisions {
        z0 := center_z - extent + f32(z_index) * cell
        z1 := z0 + cell
        for x_index in 0 ..< divisions {
            x0 := center_x - extent + f32(x_index) * cell
            x1 := x0 + cell
            // Reverse winding so the ocean's upward face is the front (CCW) face
            // and survives back-face culling from a downward-looking camera.
            world_water_quad({x0, ocean_y, z0}, {x0, ocean_y, z1}, {x1, ocean_y, z1}, {x1, ocean_y, z0}, color)
        }
    }
}

world_box :: proc(center, size: third_person.Vec3, color: rl.Color) {
    x, y, z := size.x * .5, size.y * .5, size.z * .5
    p := [8]third_person.Vec3 {
        {center.x - x, center.y - y, center.z - z},
        {center.x + x, center.y - y, center.z - z},
        {center.x + x, center.y + y, center.z - z},
        {center.x - x, center.y + y, center.z - z},
        {center.x - x, center.y - y, center.z + z},
        {center.x + x, center.y - y, center.z + z},
        {center.x + x, center.y + y, center.z + z},
        {center.x - x, center.y + y, center.z + z},
    }
    world_quad(p[0], p[3], p[2], p[1], color)
    world_quad(p[4], p[5], p[6], p[7], color)
    world_quad(p[0], p[4], p[7], p[3], color)
    world_quad(p[1], p[2], p[6], p[5], color)
    world_quad(p[3], p[7], p[6], p[2], color)
    world_quad(p[0], p[1], p[5], p[4], color)
}

clipmap_vertex_color :: proc(editor: ^Editor, level: int, x, z, height: f32) -> rl.Color {
    cell := editor.project.levels[level].cell_size
    left := terrain.sample_height(&editor.project, level, x - cell, z)
    right := terrain.sample_height(&editor.project, level, x + cell, z)
    back := terrain.sample_height(&editor.project, level, x, z - cell)
    front := terrain.sample_height(&editor.project, level, x, z + cell)
    normal := vec_normalize(vec_cross({y = front - back, z = cell * 2}, {x = cell * 2, y = right - left}))
    light := vec_normalize(third_person.Vec3{x = -.45, y = .85, z = -.3})
    shade := clamp(.48 + max(vec_dot(normal, light), 0) * .52, .42, 1.05)
    base := terrain_color(
        max(height, editor.project.sea_level + .12),
        terrain.sample_material(&editor.project, level, x, z),
        editor.project.sea_level,
    )
    return {
        u8(clamp(f32(base.r) * shade, 0, 255)),
        u8(clamp(f32(base.g) * shade, 0, 255)),
        u8(clamp(f32(base.b) * shade, 0, 255)),
        255,
    }
}

clipmap_update_level :: proc(editor: ^Editor, frame_index, level: int, center: [2]f32) {
    buffer := &world_renderer.clipmap_vertex[frame_index][level]
    vertices := cast([^]World_Vertex)buffer.mapped
    data := &editor.project.levels[level]
    grid_cell := data.cell_size * 2
    half_grid := f32(CLIPMAP_GRID_RESOLUTION - 1) * .5
    for z in 0 ..< CLIPMAP_GRID_RESOLUTION {
        world_z := center[1] + (f32(z) - half_grid) * grid_cell
        for x in 0 ..< CLIPMAP_GRID_RESOLUTION {
            world_x := center[0] + (f32(x) - half_grid) * grid_cell
            height := terrain.sample_height(&editor.project, level, world_x, world_z)
            vertex := world_vertex(
                {world_x, height, world_z},
                clipmap_vertex_color(editor, level, world_x, world_z, height),
            )
            vertex.kind = 2
            vertices[z * CLIPMAP_GRID_RESOLUTION + x] = vertex
        }
    }
}

clipmap_update :: proc(editor: ^Editor, frame_index: int) {
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && editor.pilot.mode == .Driving ? editor.flight_camera.focal_length : 1.35,
    )
    revision_changed := world_renderer.clipmap_revision[frame_index] != editor.project.revision
    snap := editor.project.levels[0].cell_size * 2
    center := [2]f32 {
        f32(math.round(f64(camera.position.x / snap))) * snap,
        f32(math.round(f64(camera.position.z / snap))) * snap,
    }
    for level in 0 ..< terrain.CLIPMAP_LEVELS {
        if revision_changed ||
           !world_renderer.clipmap_valid[frame_index][level] ||
           world_renderer.clipmap_center[frame_index][level] != center {
            clipmap_update_level(editor, frame_index, level, center)
            world_renderer.clipmap_center[frame_index][level] = center
            world_renderer.clipmap_valid[frame_index][level] = true
        }
    }
    world_renderer.clipmap_revision[frame_index] = editor.project.revision
}

clipmap_append_cell :: proc(indices: ^[dynamic]u32, x, z: int) {
    row := CLIPMAP_GRID_RESOLUTION
    a := u32(z * row + x)
    b := u32(z * row + x + 1)
    c := u32((z + 1) * row + x + 1)
    d := u32((z + 1) * row + x)
    // Wound so the upward-facing terrain surface is the front (CCW) face, so it
    // survives back-face culling when viewed from above.
    append(indices, a, c, b, a, d, c)
}

clipmap_create_indices :: proc(ctx: ^engine.Vk_Context) -> bool {
    indices := make([dynamic]u32, 0, CLIPMAP_FULL_INDEX_COUNT * 2)
    defer delete(indices)
    for z in 0 ..< CLIPMAP_GRID_RESOLUTION - 1 {
        for x in 0 ..< CLIPMAP_GRID_RESOLUTION - 1 {
            clipmap_append_cell(&indices, x, z)
        }
    }
    world_renderer.clipmap_full_indices = u32(len(indices))
    world_renderer.clipmap_ring_first = u32(len(indices))
    hole_min := CLIPMAP_GRID_RESOLUTION / 4
    hole_max := CLIPMAP_GRID_RESOLUTION - hole_min - 1
    for z in 0 ..< CLIPMAP_GRID_RESOLUTION - 1 {
        for x in 0 ..< CLIPMAP_GRID_RESOLUTION - 1 {
            if x >= hole_min && x < hole_max && z >= hole_min && z < hole_max do continue
            clipmap_append_cell(&indices, x, z)
        }
    }
    world_renderer.clipmap_ring_indices = u32(len(indices)) - world_renderer.clipmap_ring_first
    if !engine.vk_create_host_buffer(
        ctx,
        vk.DeviceSize(len(indices) * size_of(u32)),
        {.INDEX_BUFFER},
        &world_renderer.clipmap_index,
    ) {
        return false
    }
    mem.copy_non_overlapping(world_renderer.clipmap_index.mapped, raw_data(indices[:]), len(indices) * size_of(u32))
    return true
}

world_infrastructure :: proc(editor: ^Editor) {
    half := f32(terrain.RING_RESOLUTION - 1) * editor.project.levels[0].cell_size * .5
    for sign in terrain.DEFAULT_ISLAND_SIGNS {
        x, z := sign * half * terrain.DEFAULT_ISLAND_OFFSET, sign * half * terrain.DEFAULT_ISLAND_OFFSET
        run_l, run_w := half * terrain.DEFAULT_RUNWAY_HALF_LENGTH, half * terrain.DEFAULT_RUNWAY_HALF_WIDTH
        y := terrain.sample_height(&editor.project, 0, x, z) + .05
        world_box({x, y, z}, {run_l * 2, .08, run_w * 2}, {60, 66, 67, 255})
        for marker in -3 ..= 3 {
            mx := x + f32(marker) * run_l * .22
            world_box({mx, y + .06, z}, {run_l * .11, .025, .12}, {238, 232, 186, 255})
        }
        // Run straight out from the island's outer shoreline. The former
        // diagonal endpoints crossed the coast at different Z coordinates,
        // which made the deck read as a detached triangular wedge.
        ix := x + sign * half * terrain.DEFAULT_ISLAND_RADIUS * .62
        ox := x + sign * half * terrain.DEFAULT_ISLAND_RADIUS * 1.18
        iz, oz := z, z
        // Keep the deck level from land to water. Sloping it down to sea level
        // buried most of the mesh inside the island and left only its far tip.
        deck_height := f32(terrain.DEFAULT_ISLAND_HEIGHT + .24)
        iy, oy := deck_height, deck_height
        w := half * .018
        world_quad({ix, iy, iz - w}, {ox, oy, oz - w}, {ox, oy, oz + w}, {ix, iy, iz + w}, {137, 89, 48, 255})
    }
}

formation_face_color :: proc(base: rl.Color, angle: f32, layer: int) -> rl.Color {
    light := math.cos(angle) * -.45 + math.sin(angle) * -.30
    if base.r > 175 && base.g > 165 && base.b > 135 {
        // Adriatic limestone is pale and cool, with stronger facet separation
        // than the generic formation palette.
        shade := clamp(.78 + light * .38 + f32(layer) * .055, .52, 1.18)
        return {
            r = u8(clamp(f32(base.r) * shade, 0, 255)),
            g = u8(clamp(f32(base.g) * shade * 1.01, 0, 255)),
            b = u8(clamp(f32(base.b) * shade * 1.03, 0, 255)),
            a = base.a,
        }
    }
    shade := clamp(.67 + light * .28 + f32(layer) * .035, .42, 1.05)
    return {
        r = u8(clamp(f32(base.r) * shade, 0, 255)),
        g = u8(clamp(f32(base.g) * shade, 0, 255)),
        b = u8(clamp(f32(base.b) * shade, 0, 255)),
        a = base.a,
    }
}

world_rotate_xz :: proc(center_x, center_z, x, z, rotation: f32) -> (f32, f32) {
    cosine, sine := math.cos(rotation), math.sin(rotation)
    return center_x + x * cosine - z * sine, center_z + x * sine + z * cosine
}

world_box_rotated :: proc(center: third_person.Vec3, size: third_person.Vec3, rotation: f32, color: rl.Color) {
    x, y, z := size.x * .5, size.y * .5, size.z * .5
    p: [8]third_person.Vec3
    local := [8][3]f32 {
        {-x, -y, -z},
        {x, -y, -z},
        {x, y, -z},
        {-x, y, -z},
        {-x, -y, z},
        {x, -y, z},
        {x, y, z},
        {-x, y, z},
    }
    for index in 0 ..< 8 {
        world_x, world_z := world_rotate_xz(center.x, center.z, local[index][0], local[index][2], rotation)
        p[index] = {world_x, center.y + local[index][1], world_z}
    }
    world_quad(p[0], p[3], p[2], p[1], color)
    world_quad(p[4], p[5], p[6], p[7], color)
    world_quad(p[0], p[4], p[7], p[3], color)
    world_quad(p[1], p[2], p[6], p[5], color)
    world_quad(p[3], p[7], p[6], p[2], color)
    world_quad(p[0], p[1], p[5], p[4], color)
}

world_tapered_box_rotated :: proc(
    center: third_person.Vec3,
    height, bottom_width, bottom_depth, top_width, top_depth, rotation: f32,
    color: rl.Color,
) {
    half_height := height * .5
    local := [8][3]f32 {
        {-bottom_width * .5, -half_height, -bottom_depth * .5},
        {bottom_width * .5, -half_height, -bottom_depth * .5},
        {top_width * .5, half_height, -top_depth * .5},
        {-top_width * .5, half_height, -top_depth * .5},
        {-bottom_width * .5, -half_height, bottom_depth * .5},
        {bottom_width * .5, -half_height, bottom_depth * .5},
        {top_width * .5, half_height, top_depth * .5},
        {-top_width * .5, half_height, top_depth * .5},
    }
    p: [8]third_person.Vec3
    for index in 0 ..< 8 {
        world_x, world_z := world_rotate_xz(center.x, center.z, local[index][0], local[index][2], rotation)
        p[index] = {world_x, center.y + local[index][1], world_z}
    }
    world_quad(p[0], p[3], p[2], p[1], color)
    world_quad(p[4], p[5], p[6], p[7], color)
    world_quad(p[0], p[4], p[7], p[3], color)
    world_quad(p[1], p[2], p[6], p[5], color)
    world_quad(p[3], p[7], p[6], p[2], color)
    world_quad(p[0], p[1], p[5], p[4], color)
}

world_vertical_prism :: proc(center: third_person.Vec3, radius_x, radius_z, height, rotation: f32, color: rl.Color) {
    SEGMENTS :: 8
    bottom, top: [SEGMENTS]third_person.Vec3
    half_height := height * .5
    for segment in 0 ..< SEGMENTS {
        angle := (f32(segment) + .5) * math.PI * 2 / f32(SEGMENTS)
        local_x := math.cos(angle) * radius_x
        local_z := math.sin(angle) * radius_z
        world_x, world_z := world_rotate_xz(center.x, center.z, local_x, local_z, rotation)
        bottom[segment] = {world_x, center.y - half_height, world_z}
        top[segment] = {world_x, center.y + half_height, world_z}
    }
    bottom_center := third_person.Vec3{center.x, center.y - half_height, center.z}
    top_center := third_person.Vec3{center.x, center.y + half_height, center.z}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_quad(bottom[segment], top[segment], top[next], bottom[next], color)
        world_triangle(bottom_center, bottom[segment], bottom[next], color)
        world_triangle(top_center, top[next], top[segment], color)
    }
}

world_vertical_disc_rotated :: proc(
    center: third_person.Vec3,
    radius_x, radius_y, depth, rotation: f32,
    color: rl.Color,
) {
    SEGMENTS :: 12
    back, front: [SEGMENTS]third_person.Vec3
    half_depth := depth * .5
    back_x, back_z := world_rotate_xz(center.x, center.z, 0, -half_depth, rotation)
    front_x, front_z := world_rotate_xz(center.x, center.z, 0, half_depth, rotation)
    back_center := third_person.Vec3{back_x, center.y, back_z}
    front_center := third_person.Vec3{front_x, center.y, front_z}
    for segment in 0 ..< SEGMENTS {
        angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
        local_x := math.cos(angle) * radius_x
        local_y := math.sin(angle) * radius_y
        back_world_x, back_world_z := world_rotate_xz(center.x, center.z, local_x, -half_depth, rotation)
        front_world_x, front_world_z := world_rotate_xz(center.x, center.z, local_x, half_depth, rotation)
        back[segment] = {back_world_x, center.y + local_y, back_world_z}
        front[segment] = {front_world_x, center.y + local_y, front_world_z}
    }
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(back_center, back[next], back[segment], color)
        world_triangle(front_center, front[segment], front[next], color)
        world_quad(back[segment], back[next], front[next], front[segment], color)
    }
}

world_tapered_disc_depth_rotated :: proc(
    center: third_person.Vec3,
    back_radius_x, back_radius_y, front_radius_x, front_radius_y, depth, rotation: f32,
    color: rl.Color,
) {
    SEGMENTS :: 12
    back, front: [SEGMENTS]third_person.Vec3
    half_depth := depth * .5
    back_x, back_z := world_rotate_xz(center.x, center.z, 0, -half_depth, rotation)
    front_x, front_z := world_rotate_xz(center.x, center.z, 0, half_depth, rotation)
    back_center := third_person.Vec3{back_x, center.y, back_z}
    front_center := third_person.Vec3{front_x, center.y, front_z}
    for segment in 0 ..< SEGMENTS {
        angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
        cosine, sine := math.cos(angle), math.sin(angle)
        back_world_x, back_world_z := world_rotate_xz(
            center.x,
            center.z,
            cosine * back_radius_x,
            -half_depth,
            rotation,
        )
        front_world_x, front_world_z := world_rotate_xz(
            center.x,
            center.z,
            cosine * front_radius_x,
            half_depth,
            rotation,
        )
        back[segment] = {back_world_x, center.y + sine * back_radius_y, back_world_z}
        front[segment] = {front_world_x, center.y + sine * front_radius_y, front_world_z}
    }
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(back_center, back[next], back[segment], color)
        world_triangle(front_center, front[segment], front[next], color)
        world_quad(back[segment], back[next], front[next], front[segment], color)
    }
}

world_tube_between :: proc(a, b, forward: third_person.Vec3, radius_x, radius_z: f32, color: rl.Color) {
    SEGMENTS :: 8
    delta := third_person.Vec3{b.x - a.x, b.y - a.y, b.z - a.z}
    length := f32(math.sqrt(f64(vec_dot(delta, delta))))
    if length <= .0001 do return
    axis_y := third_person.Vec3{delta.x / length, delta.y / length, delta.z / length}
    reference := vec_normalize(forward)
    projection := vec_dot(reference, axis_y)
    axis_z_candidate := third_person.Vec3 {
        reference.x - axis_y.x * projection,
        reference.y - axis_y.y * projection,
        reference.z - axis_y.z * projection,
    }
    // Tail links often point exactly opposite model-forward. In that case
    // Gram-Schmidt with `forward` produces a zero radial axis and collapses
    // the tube into invisible, zero-area triangles. Choose a stable fallback
    // reference for any collinear segment.
    if vec_dot(axis_z_candidate, axis_z_candidate) < .0001 {
        fallback := third_person.Vec3 {
            y = 1,
        }
        if math.abs(axis_y.y) > .90 do fallback = {
            x = 1,
        }
        fallback_projection := vec_dot(fallback, axis_y)
        axis_z_candidate = {
            fallback.x - axis_y.x * fallback_projection,
            fallback.y - axis_y.y * fallback_projection,
            fallback.z - axis_y.z * fallback_projection,
        }
    }
    axis_z := vec_normalize(axis_z_candidate)
    axis_x := vec_normalize(vec_cross(axis_y, axis_z))
    ring_a, ring_b: [SEGMENTS]third_person.Vec3
    for segment in 0 ..< SEGMENTS {
        angle := (f32(segment) + .5) * math.PI * 2 / f32(SEGMENTS)
        x, z := math.cos(angle) * radius_x, math.sin(angle) * radius_z
        offset := third_person.Vec3 {
            axis_x.x * x + axis_z.x * z,
            axis_x.y * x + axis_z.y * z,
            axis_x.z * x + axis_z.z * z,
        }
        ring_a[segment] = {a.x + offset.x, a.y + offset.y, a.z + offset.z}
        ring_b[segment] = {b.x + offset.x, b.y + offset.y, b.z + offset.z}
    }
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(a, ring_a[segment], ring_a[next], color)
        world_triangle(b, ring_b[next], ring_b[segment], color)
        world_quad(ring_a[segment], ring_b[segment], ring_b[next], ring_a[next], color)
    }
}

world_mouse_limb_hull :: proc(
    points: []third_person.Vec3,
    radii: []f32,
    colors: []rl.Color,
    forward: third_person.Vec3,
) {
    MAX_RINGS :: 16
    SEGMENTS :: 12
    if len(points) < 2 || len(points) > MAX_RINGS || len(radii) != len(points) || len(colors) != len(points) {
        return
    }

    rings: [MAX_RINGS][SEGMENTS]third_person.Vec3
    reference := vec_normalize(forward)
    previous_axis_x, previous_axis_z: third_person.Vec3
    for ring_index in 0 ..< len(points) {
        previous := max(ring_index - 1, 0)
        next := min(ring_index + 1, len(points) - 1)
        tangent := third_person.Vec3 {
            points[next].x - points[previous].x,
            points[next].y - points[previous].y,
            points[next].z - points[previous].z,
        }
        axis_y := vec_normalize(tangent)
        frame_reference := reference
        if ring_index > 0 do frame_reference = previous_axis_z
        projection := vec_dot(frame_reference, axis_y)
        axis_z_candidate := third_person.Vec3 {
            frame_reference.x - axis_y.x * projection,
            frame_reference.y - axis_y.y * projection,
            frame_reference.z - axis_y.z * projection,
        }
        if vec_dot(axis_z_candidate, axis_z_candidate) < .0001 {
            fallback := ring_index > 0 ? previous_axis_x : third_person.Vec3{y = 1}
            if ring_index == 0 && math.abs(axis_y.y) > .90 do fallback = {
                x = 1,
            }
            fallback_projection := vec_dot(fallback, axis_y)
            axis_z_candidate = {
                fallback.x - axis_y.x * fallback_projection,
                fallback.y - axis_y.y * fallback_projection,
                fallback.z - axis_y.z * fallback_projection,
            }
        }
        axis_z := vec_normalize(axis_z_candidate)
        axis_x := vec_normalize(vec_cross(axis_y, axis_z))
        // Projecting the previous radial axis onto the new tangent plane is a
        // discrete parallel transport: ring indices retain their orientation
        // through bends instead of independently choosing a frame/sign.
        previous_axis_x, previous_axis_z = axis_x, axis_z
        for segment in 0 ..< SEGMENTS {
            angle := (f32(segment) + .5) * math.PI * 2 / f32(SEGMENTS)
            cosine, sine := math.cos(angle), math.sin(angle)
            radius := radii[ring_index]
            offset := third_person.Vec3 {
                axis_x.x * cosine * radius + axis_z.x * sine * radius,
                axis_x.y * cosine * radius + axis_z.y * sine * radius,
                axis_x.z * cosine * radius + axis_z.z * sine * radius,
            }
            rings[ring_index][segment] = {
                points[ring_index].x + offset.x,
                points[ring_index].y + offset.y,
                points[ring_index].z + offset.z,
            }
        }
    }

    for ring_index in 0 ..< len(points) - 1 {
        for segment in 0 ..< SEGMENTS {
            next_segment := (segment + 1) % SEGMENTS
            a, b := rings[ring_index][segment], rings[ring_index][next_segment]
            c, d := rings[ring_index + 1][next_segment], rings[ring_index + 1][segment]
            world_triangle_colored(a, d, c, colors[ring_index], colors[ring_index + 1], colors[ring_index + 1])
            world_triangle_colored(a, c, b, colors[ring_index], colors[ring_index + 1], colors[ring_index])
        }
    }
    last := len(points) - 1
    for segment in 0 ..< SEGMENTS {
        next_segment := (segment + 1) % SEGMENTS
        world_triangle(points[0], rings[0][segment], rings[0][next_segment], colors[0])
        world_triangle(points[last], rings[last][next_segment], rings[last][segment], colors[last])
    }
}

world_box_between :: proc(a, b, forward: third_person.Vec3, width, depth: f32, color: rl.Color) {
    delta := third_person.Vec3{b.x - a.x, b.y - a.y, b.z - a.z}
    length := f32(math.sqrt(f64(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)))
    if length <= .0001 do return
    axis_y := third_person.Vec3{delta.x / length, delta.y / length, delta.z / length}
    axis_z := vec_normalize(forward)
    axis_x := vec_normalize(vec_cross(axis_y, axis_z))
    center := third_person.Vec3{(a.x + b.x) * .5, (a.y + b.y) * .5, (a.z + b.z) * .5}
    signs := [8][3]f32 {
        {-1, -1, -1},
        {1, -1, -1},
        {1, 1, -1},
        {-1, 1, -1},
        {-1, -1, 1},
        {1, -1, 1},
        {1, 1, 1},
        {-1, 1, 1},
    }
    p: [8]third_person.Vec3
    for index in 0 ..< 8 {
        x := signs[index][0] * width * .5
        y := signs[index][1] * length * .5
        z := signs[index][2] * depth * .5
        p[index] = {
            center.x + axis_x.x * x + axis_y.x * y + axis_z.x * z,
            center.y + axis_x.y * x + axis_y.y * y + axis_z.y * z,
            center.z + axis_x.z * x + axis_y.z * y + axis_z.z * z,
        }
    }
    world_quad(p[0], p[3], p[2], p[1], color)
    world_quad(p[4], p[5], p[6], p[7], color)
    world_quad(p[0], p[4], p[7], p[3], color)
    world_quad(p[1], p[2], p[6], p[5], color)
    world_quad(p[3], p[7], p[6], p[2], color)
    world_quad(p[0], p[1], p[5], p[4], color)
}

world_shadow_fade :: proc(color: rl.Color, factor: f32) -> rl.Color {
    return {color.r, color.g, color.b, u8(clamp(f32(color.a) * factor, 0, 255))}
}

world_vehicle_shadow_point :: proc(
    point: third_person.Vec3,
    sun_direction: [3]f32,
    project: ^terrain.Project,
) -> (
    projected: third_person.Vec3,
    on_land: bool,
) {
    projected = point
    sun_y := max(sun_direction[1], f32(.12))
    // Refine the receiver height because the ray can cross several terrain
    // cells before it reaches the ground.
    for _ in 0 ..< 3 {
        ground := terrain.sample_height(project, 0, projected.x, projected.z)
        ray_distance := min(max(point.y - ground, f32(0)) / sun_y, f32(300))
        projected.x = point.x - sun_direction[0] * ray_distance
        projected.z = point.z - sun_direction[2] * ray_distance
    }
    ground := terrain.sample_height(project, 0, projected.x, projected.z)
    projected.y = ground + .145
    return projected, ground > project.sea_level + .04
}

world_vehicle_shadow_triangle :: proc(
    a, b, c: third_person.Vec3,
    sun_direction: [3]f32,
    cloud_cover: f32,
    project: ^terrain.Project,
) {
    daylight := clamp(sun_direction[1], 0, 1)
    if daylight <= .08 do return
    projected_a, land_a := world_vehicle_shadow_point(a, sun_direction, project)
    projected_b, land_b := world_vehicle_shadow_point(b, sun_direction, project)
    projected_c, land_c := world_vehicle_shadow_point(c, sun_direction, project)
    if !land_a && !land_b && !land_c do return

    cloud := clamp(cloud_cover, 0, 1)
    shade := u8(clamp(17 + cloud * 28 + (1 - daylight) * 8, 17, 53))
    // Opaque projected faces merge into one clean, hard-edged silhouette.
    // Vary the tone instead of alpha so overlapping mesh components cannot
    // create accidental dark facets inside the shadow.
    world_triangle(projected_a, projected_b, projected_c, {shade, shade + 2, shade + 3, 255})
}

world_structure_shadow_layer :: proc(
    structure: terrain.Structure,
    project: ^terrain.Project,
    offset_x, offset_z, footprint_scale: f32,
    lift: f32,
    shadow: rl.Color,
) {
    local_corners := [4][2]f32 {
        {-structure.width * footprint_scale * .5, -structure.depth * footprint_scale * .5},
        {structure.width * footprint_scale * .5, -structure.depth * footprint_scale * .5},
        {structure.width * footprint_scale * .5, structure.depth * footprint_scale * .5},
        {-structure.width * footprint_scale * .5, structure.depth * footprint_scale * .5},
    }
    base: [4]third_person.Vec3
    projected: [4]third_person.Vec3
    land_threshold := project.sea_level + .04
    projected_land := false
    for index in 0 ..< 4 {
        x, z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_corners[index][0],
            local_corners[index][1],
            structure.rotation,
        )
        base[index] = {x, terrain.sample_height(project, 0, x, z) + lift, z}
        projected[index] = {
            x + offset_x,
            terrain.sample_height(project, 0, x + offset_x, z + offset_z) + lift,
            z + offset_z,
        }
        if projected[index].y > land_threshold do projected_land = true
    }
    far_shadow := world_shadow_fade(shadow, f32(.48))
    for index in 0 ..< 4 {
        next := (index + 1) % 4
        base_on_land := base[index].y > land_threshold || base[next].y > land_threshold
        projected_on_land := projected[index].y > land_threshold || projected[next].y > land_threshold
        if !base_on_land && !projected_on_land do continue
        // Shadow decals lie flat on the ground; wind them so the upward face is
        // the front (CCW) face and they survive back-face culling from above.
        world_quad_colored(
            projected[index],
            projected[next],
            base[next],
            base[index],
            far_shadow,
            far_shadow,
            shadow,
            shadow,
        )
    }
    if projected_land {
        center_x := (projected[0].x + projected[1].x + projected[2].x + projected[3].x) * .25
        center_z := (projected[0].z + projected[1].z + projected[2].z + projected[3].z) * .25
        center := third_person.Vec3{center_x, terrain.sample_height(project, 0, center_x, center_z) + lift, center_z}
        for index in 0 ..< 4 {
            next := (index + 1) % 4
            world_triangle_colored(projected[next], projected[index], center, far_shadow, far_shadow, shadow)
        }
    }
}

world_foliage_shadow_layer :: proc(
    structure: terrain.Structure,
    project: ^terrain.Project,
    offset_x, offset_z, footprint_scale: f32,
    lift: f32,
    shadow: rl.Color,
    segments: int,
) {
    // The silhouette resolution is picked per structure by camera distance in
    // world_structure_shadow: near canopies round out their penumbra while
    // distant ones shed segments once the projected footprint covers only a
    // few ground pixels.
    MAX_SEGMENTS :: 16
    seg := clamp(segments, 6, MAX_SEGMENTS)
    base: [MAX_SEGMENTS]third_person.Vec3
    projected: [MAX_SEGMENTS]third_person.Vec3
    land_threshold := project.sea_level + .04
    projected_land := false
    center_x, center_z := f32(0), f32(0)

    for index in 0 ..< seg {
        angle := f32(index) * math.PI * 2 / f32(seg)
        irregularity := 1 + f32(math.sin(f64(f32(structure.seed) * .009 + f32(index) * 2.23))) * .075
        local_x := math.cos(angle) * structure.width * footprint_scale * .5 * irregularity
        local_z := math.sin(angle) * structure.depth * footprint_scale * .5 * irregularity
        x, z := world_rotate_xz(structure.center_x, structure.center_z, local_x, local_z, structure.rotation)
        base[index] = {x, terrain.sample_height(project, 0, x, z) + lift, z}
        projected[index] = {
            x + offset_x,
            terrain.sample_height(project, 0, x + offset_x, z + offset_z) + lift,
            z + offset_z,
        }
        center_x += projected[index].x
        center_z += projected[index].z
        if projected[index].y > land_threshold do projected_land = true
    }

    far_shadow := world_shadow_fade(shadow, f32(.42))
    for index in 0 ..< seg {
        next := (index + 1) % seg
        base_on_land := base[index].y > land_threshold || base[next].y > land_threshold
        projected_on_land := projected[index].y > land_threshold || projected[next].y > land_threshold
        if !base_on_land && !projected_on_land do continue
        // Flat ground decal: wind the upward face as front (CCW) so culling keeps it.
        world_quad_colored(
            projected[index],
            projected[next],
            base[next],
            base[index],
            far_shadow,
            far_shadow,
            shadow,
            shadow,
        )
    }
    if projected_land {
        center_x /= f32(seg)
        center_z /= f32(seg)
        center := third_person.Vec3{center_x, terrain.sample_height(project, 0, center_x, center_z) + lift, center_z}
        // The cap fills the projected silhouette. Contact layers (no sun
        // offset) sit directly under the plant, so a dark center reads as the
        // grounded core of the shadow. Offset body/penumbra layers put this
        // cap at the far tip, where the walls already faded to far_shadow;
        // darkening the tip center there leaves an unnatural dark blob past a
        // lighter waist, so the tip must keep fading outward instead.
        is_contact := abs(offset_x) < .001 && abs(offset_z) < .001
        cap_center := is_contact ? shadow : far_shadow
        for index in 0 ..< seg {
            next := (index + 1) % seg
            world_triangle_colored(projected[next], projected[index], center, far_shadow, far_shadow, cap_center)
        }
    }
}

world_structure_shadow :: proc(
    structure: terrain.Structure,
    sun_direction: [3]f32,
    cloud_cover: f32,
    project: ^terrain.Project,
) {
    daylight := clamp(sun_direction[1], 0, 1)
    if daylight <= .08 do return

    horizontal_length := f32(math.sqrt(f64(sun_direction[0] * sun_direction[0] + sun_direction[2] * sun_direction[2])))
    if horizontal_length <= .01 do return
    shadow_height := structure.height
    if structure.kind == .Architecture {
        roof_rise := structure.width * .34
        if structure.height > 60 {
            roof_rise = structure.width * .72
        } else if architecture.roof_style_for_seed(structure.seed) == .Low_Gable {
            roof_rise = structure.width * .24
        }
        shadow_height += roof_rise
    }
    shadow_length := min(shadow_height / max(sun_direction[1], f32(.18)), max(structure.width, structure.depth) * 3.5)
    offset_x := -sun_direction[0] / horizontal_length * shadow_length
    offset_z := -sun_direction[2] / horizontal_length * shadow_length

    // A translucent penumbra around a denser core keeps the shadow from
    // reading as a hard rectangular decal at the editor's wide camera range.
    cloud := clamp(cloud_cover, 0, 1)
    shadow_visibility := 1 - cloud * .72
    outer_alpha := u8(clamp((24 + daylight * 24) * (1 + cloud * .65), 24, 62))
    inner_alpha := u8(clamp((64 + daylight * 46) * shadow_visibility, 18, 110))
    // Draw the broad penumbra first. Each layer gets a small, increasing lift
    // above the terrain so the translucent passes never fight for the same
    // depth value on flat ground or at the cap of a shadow.
    if structure.kind == .Foliage {
        // Match the canopy geometry's distance LOD (see world_foliage_lobe):
        // near shadows gain a rounder silhouette and an extra soft penumbra,
        // while distant shadows shed segments, split patches, and the contact
        // core once they resolve to a few pixels. The near-quality cost is
        // paid back by the distant savings, so the dense-forest frame budget
        // holds against the 60 FPS contract.
        camera_position := world_renderer.editor.camera_pose.position
        camera_delta_x := camera_position.x - structure.center_x
        camera_delta_z := camera_position.z - structure.center_z
        camera_distance := f32(math.sqrt(f64(camera_delta_x * camera_delta_x + camera_delta_z * camera_delta_z)))

        // Detail bands never drop below the previous fixed quality inside the
        // range where a shadow reads as a shape (< 260 m); they only add near
        // and subtract far.
        outer_segments := 12
        patch_segments := 12
        draw_contact := true
        soft_penumbra := false
        if camera_distance < 145 {
            outer_segments = 16
            patch_segments = 14
            soft_penumbra = true
        } else if camera_distance < 260 {
            outer_segments = 12
            patch_segments = 12
        } else if camera_distance < 520 {
            outer_segments = 10
            patch_segments = 8
        } else {
            outer_segments = 8
            patch_segments = 6
            draw_contact = false
        }

        // A wide, very translucent halo drawn only near the camera turns the
        // single hard penumbra step into a graduated soft edge, reading as a
        // diffuse leaf-shadow boundary instead of a scaled decal ring.
        if soft_penumbra {
            world_foliage_shadow_layer(
                structure,
                project,
                offset_x * 1.16,
                offset_z * 1.16,
                1.24,
                .028,
                {41, 57, 44, u8(f32(outer_alpha) * .55)},
                outer_segments,
            )
        }

        world_foliage_shadow_layer(
            structure,
            project,
            offset_x * 1.08,
            offset_z * 1.08,
            1.12,
            .035,
            {39, 55, 42, outer_alpha},
            outer_segments,
        )
        // Dense foliage shadow is composed from overlapping canopy lobes, not
        // two more copies of the full formation footprint. The shared outer
        // penumbra keeps the plant grounded; these smaller cores create broken
        // leafy edges and naturally darker overlap pockets.
        wide, narrow := max(structure.width, structure.depth), min(structure.width, structure.depth)
        hedge_shadow := wide / max(narrow, f32(.01)) >= 1.8
        patch_count := hedge_shadow ? 5 : 4
        // Distant clumps collapse to sub-pixel blotches; fewer patch lobes keep
        // the grounding read without paying for detail nobody can resolve.
        if camera_distance >= 520 do patch_count = hedge_shadow ? 3 : 2
        patch_inner_alpha := u8(f32(inner_alpha) * .70)
        patch_contact_alpha := u8(f32(inner_alpha) * .60)
        for patch_index in 0 ..< patch_count {
            patch := structure
            local_x, local_z := f32(0), f32(0)
            if hedge_shadow {
                fraction := (f32(patch_index) + .5) / f32(patch_count)
                along := (fraction - .5) * wide * .76
                cross := f32(math.sin(f64(f32(structure.seed) * .013 + f32(patch_index) * 2.17))) * narrow * .11
                local_x, local_z = along, cross
                patch.width = wide / f32(patch_count) * 1.62
                patch.depth = narrow * .86
                if structure.depth > structure.width {
                    local_x, local_z = cross, along
                    patch.width, patch.depth = patch.depth, patch.width
                }
            } else {
                angle := f32(patch_index) * 2.399963 + f32(structure.seed % 101) * .027
                radial := .16 + f32(patch_index % 2) * .10
                local_x = math.cos(angle) * structure.width * radial
                local_z = math.sin(angle) * structure.depth * radial
                patch.width = structure.width * (.50 + f32(patch_index % 2) * .06)
                patch.depth = structure.depth * (.48 + f32((patch_index + 1) % 2) * .07)
            }
            patch.center_x, patch.center_z = world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            patch.seed += u32(patch_index * 733 + 97)
            world_foliage_shadow_layer(
                patch,
                project,
                offset_x,
                offset_z,
                .96,
                .055 + f32(patch_index) * .001,
                {34, 49, 38, patch_inner_alpha},
                patch_segments,
            )
            if draw_contact {
                world_foliage_shadow_layer(
                    patch,
                    project,
                    0,
                    0,
                    .94,
                    .075 + f32(patch_index) * .001,
                    {30, 45, 35, patch_contact_alpha},
                    patch_segments,
                )
            }
        }
        return
    }
    world_structure_shadow_layer(
        structure,
        project,
        offset_x * 1.08,
        offset_z * 1.08,
        1.16,
        .035,
        {50, 45, 40, outer_alpha},
    )
    world_structure_shadow_layer(structure, project, offset_x, offset_z, 1, .055, {45, 40, 36, inner_alpha})
    world_structure_shadow_layer(structure, project, 0, 0, 1.02, .075, {40, 36, 33, inner_alpha})
}

world_roof_lerp :: proc(a, b: third_person.Vec3, fraction: f32) -> third_person.Vec3 {
    return {a.x + (b.x - a.x) * fraction, a.y + (b.y - a.y) * fraction, a.z + (b.z - a.z) * fraction}
}

world_roof_raise :: proc(point: third_person.Vec3, amount: f32) -> third_person.Vec3 {
    return {point.x, point.y + amount, point.z}
}

// A Greek tile roof reads through its repeated courses: each course runs from
// the lower edge toward the ridge, with small gaps that catch the light.
world_architecture_tile_slope :: proc(
    edge_a, edge_b, ridge_a, ridge_b: third_person.Vec3,
    courses, segments: int,
    seed: u32,
) {
    for course in 0 ..< courses {
        course_start := f32(course) / f32(courses)
        course_end := min(course_start + .78 / f32(courses), 1)
        relief := .035 + f32(course % 2) * .012
        for segment in 0 ..< segments {
            segment_start := f32(segment) / f32(segments)
            segment_end := f32(segment + 1) / f32(segments)
            // Offset alternate courses so the vertical joins do not line up.
            offset := course % 2 == 0 ? 0 : .035 / f32(segments)
            segment_start = clamp(segment_start + offset, 0, 1)
            segment_end = clamp(segment_end + offset, 0, 1)

            outer_a := world_roof_lerp(edge_a, edge_b, segment_start)
            outer_b := world_roof_lerp(edge_a, edge_b, segment_end)
            inner_a := world_roof_lerp(outer_a, ridge_a, course_start)
            inner_b := world_roof_lerp(outer_b, ridge_b, course_start)
            next_a := world_roof_lerp(outer_a, ridge_a, course_end)
            next_b := world_roof_lerp(outer_b, ridge_b, course_end)
            inner_a = world_roof_raise(inner_a, relief)
            inner_b = world_roof_raise(inner_b, relief)
            next_a = world_roof_raise(next_a, relief)
            next_b = world_roof_raise(next_b, relief)

            tone := int((seed + u32(course * 11 + segment * 3)) % 5)
            tile_bytes := architecture.architecture_roof_tile_color(seed, tone)
            tile := rl.Color{tile_bytes[0], tile_bytes[1], tile_bytes[2], tile_bytes[3]}
            world_quad(inner_a, inner_b, next_b, next_a, tile)
        }
    }
}

world_architecture_tile_face :: proc(edge_a, edge_b, ridge: third_person.Vec3, courses, segments: int, seed: u32) {
    world_architecture_tile_slope(edge_a, edge_b, ridge, ridge, courses, segments, seed)
}

world_architecture_roof :: proc(structure: terrain.Structure, landmark: bool) {
    eave_y := structure.base_y + structure.height
    roof_style := architecture.roof_style_for_seed(structure.seed)
    if !landmark && roof_style == .Parapet {
        roof_bytes := architecture.architecture_roof_color(structure.seed)
        terracotta := rl.Color{roof_bytes[0], roof_bytes[1], roof_bytes[2], roof_bytes[3]}
        world_box_rotated(
            {structure.center_x, eave_y + .25, structure.center_z},
            {structure.width + .8, .50, structure.depth + .8},
            structure.rotation,
            terracotta,
        )
        chimney_x, chimney_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            structure.width * .22,
            -structure.depth * .16,
            structure.rotation,
        )
        world_box_rotated(
            {chimney_x, eave_y + 1.25, chimney_z},
            {2.4, 2.0, 2.4},
            structure.rotation,
            {157, 112, 86, 255},
        )
        return
    }
    rise := landmark ? structure.width * .72 : structure.width * .34
    if !landmark && roof_style == .Low_Gable do rise = structure.width * .24
    depth := structure.depth * .58
    left_front_x, left_front_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        -structure.width * .54,
        -depth,
        structure.rotation,
    )
    right_front_x, right_front_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        structure.width * .54,
        -depth,
        structure.rotation,
    )
    left_back_x, left_back_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        -structure.width * .54,
        depth,
        structure.rotation,
    )
    right_back_x, right_back_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        structure.width * .54,
        depth,
        structure.rotation,
    )
    left_front := third_person.Vec3{left_front_x, eave_y, left_front_z}
    right_front := third_person.Vec3{right_front_x, eave_y, right_front_z}
    left_back := third_person.Vec3{left_back_x, eave_y, left_back_z}
    right_back := third_person.Vec3{right_back_x, eave_y, right_back_z}
    ridge_half_depth := depth
    if roof_style == .Hip do ridge_half_depth = depth * .50
    ridge_front_x, ridge_front_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        0,
        -ridge_half_depth,
        structure.rotation,
    )
    ridge_back_x, ridge_back_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        0,
        ridge_half_depth,
        structure.rotation,
    )
    ridge_front := third_person.Vec3{ridge_front_x, eave_y + rise, ridge_front_z}
    ridge_back := third_person.Vec3{ridge_back_x, eave_y + rise, ridge_back_z}
    left_apex_x, left_apex_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        -structure.width * .54,
        0,
        structure.rotation,
    )
    right_apex_x, right_apex_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        structure.width * .54,
        0,
        structure.rotation,
    )
    left_apex := third_person.Vec3{left_apex_x, eave_y + rise, left_apex_z}
    right_apex := third_person.Vec3{right_apex_x, eave_y + rise, right_apex_z}
    wall_left_front_x, wall_left_front_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        -structure.width * .5,
        -structure.depth * .5,
        structure.rotation,
    )
    wall_left_back_x, wall_left_back_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        -structure.width * .5,
        structure.depth * .5,
        structure.rotation,
    )
    wall_right_front_x, wall_right_front_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        structure.width * .5,
        -structure.depth * .5,
        structure.rotation,
    )
    wall_right_back_x, wall_right_back_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        structure.width * .5,
        structure.depth * .5,
        structure.rotation,
    )
    wall_left_front := third_person.Vec3{wall_left_front_x, eave_y, wall_left_front_z}
    wall_left_back := third_person.Vec3{wall_left_back_x, eave_y, wall_left_back_z}
    wall_right_front := third_person.Vec3{wall_right_front_x, eave_y, wall_right_front_z}
    wall_right_back := third_person.Vec3{wall_right_back_x, eave_y, wall_right_back_z}
    wall_front_left := third_person.Vec3{wall_left_front_x, eave_y, wall_left_front_z}
    wall_front_right := third_person.Vec3{wall_right_front_x, eave_y, wall_right_front_z}
    wall_back_left := third_person.Vec3{wall_left_back_x, eave_y, wall_left_back_z}
    wall_back_right := third_person.Vec3{wall_right_back_x, eave_y, wall_right_back_z}
    wall_front_apex := third_person.Vec3 {
        wall_left_front_x + (wall_right_front_x - wall_left_front_x) * .5,
        eave_y + rise,
        wall_left_front_z + (wall_right_front_z - wall_left_front_z) * .5,
    }
    wall_back_apex := third_person.Vec3 {
        wall_left_back_x + (wall_right_back_x - wall_left_back_x) * .5,
        eave_y + rise,
        wall_left_back_z + (wall_right_back_z - wall_left_back_z) * .5,
    }
    roof_bytes := architecture.architecture_roof_color(structure.seed, landmark)
    terracotta := rl.Color{roof_bytes[0], roof_bytes[1], roof_bytes[2], roof_bytes[3]}
    // The ridge follows the building depth. Gable roofs continue the left and
    // right walls to their ridge apexes; hip roofs close the front and rear
    // ends against the shortened ridge.
    wall := rl.Color{structure.color[0], structure.color[1], structure.color[2], structure.color[3]}
    if roof_style == .Gable || roof_style == .Low_Gable {
        world_triangle(wall_front_left, wall_front_right, wall_front_apex, wall)
        world_triangle(wall_back_right, wall_back_left, wall_back_apex, wall)
    } else if roof_style == .Hip || landmark {
        world_triangle(left_front, right_front, ridge_front, terracotta)
        world_triangle(right_back, left_back, ridge_back, formation_face_color(terracotta, 1.4, 0))
    }
    world_quad(left_front, left_back, ridge_back, ridge_front, terracotta)
    world_quad(right_back, right_front, ridge_front, ridge_back, formation_face_color(terracotta, 1.4, 0))
    fascia := formation_face_color(terracotta, math.PI, 0)
    front_fascia_x, front_fascia_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        0,
        -depth,
        structure.rotation,
    )
    back_fascia_x, back_fascia_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        0,
        depth,
        structure.rotation,
    )
    world_box_rotated(
        {front_fascia_x, eave_y + .05, front_fascia_z},
        {structure.width * 1.10, .24, .18},
        structure.rotation,
        fascia,
    )
    world_box_rotated(
        {back_fascia_x, eave_y + .05, back_fascia_z},
        {structure.width * 1.10, .24, .18},
        structure.rotation,
        fascia,
    )

    courses := clamp(int(structure.width / 5.5), 4, 7)
    segments := clamp(int(structure.depth / 7), 3, 6)
    world_architecture_tile_slope(
        left_front,
        left_back,
        ridge_front,
        ridge_back,
        courses,
        segments,
        structure.seed + 3,
    )
    world_architecture_tile_slope(
        right_back,
        right_front,
        ridge_back,
        ridge_front,
        courses,
        segments,
        structure.seed + 17,
    )
    if roof_style == .Hip {
        side_courses := clamp(int(structure.depth / 5), 3, 5)
        world_architecture_tile_slope(
            left_front,
            right_front,
            ridge_front,
            ridge_front,
            side_courses,
            2,
            structure.seed + 29,
        )
        world_architecture_tile_slope(
            right_back,
            left_back,
            ridge_back,
            ridge_back,
            side_courses,
            2,
            structure.seed + 41,
        )
    }
    if !landmark && roof_style != .Parapet && architecture.architecture_has_chimney(structure.seed) {
        chimney_local_x := roof_style == .Hip ? structure.width * .12 : structure.width * .22
        chimney_local_z := -structure.depth * .12
        chimney_x, chimney_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            chimney_local_x,
            chimney_local_z,
            structure.rotation,
        )
        chimney_base := eave_y + rise * .74
        world_box_rotated(
            {chimney_x, chimney_base + 1.45, chimney_z},
            {1.8, 2.9, 1.8},
            structure.rotation,
            {157, 112, 86, 255},
        )
        world_box_rotated(
            {chimney_x, chimney_base + 3.0, chimney_z},
            {2.1, .22, 2.1},
            structure.rotation,
            {184, 93, 61, 255},
        )
    }
    if landmark {
        world_box_rotated(
            {structure.center_x, eave_y + rise + 3.5, structure.center_z},
            {3.5, 7, 3.5},
            structure.rotation,
            {224, 219, 196, 255},
        )
    }
}

world_architecture :: proc(structure: terrain.Structure) {
    landmark := structure.height > 60
    facade_style := architecture.facade_style_for_seed(structure.seed)
    roof_style := architecture.roof_style_for_seed(structure.seed)
    stone := rl.Color{structure.color[0], structure.color[1], structure.color[2], structure.color[3]}
    world_box_rotated(
        {structure.center_x, structure.base_y + structure.height * .5, structure.center_z},
        {structure.width, structure.height, structure.depth},
        structure.rotation,
        stone,
    )
    // A shallow overhanging limestone plinth separates each façade from the
    // terrain and gives the compact blocks a believable masonry foundation.
    plinth := formation_face_color(stone, math.PI, 0)
    world_box_rotated(
        {structure.center_x, structure.base_y + .30, structure.center_z},
        {structure.width + .46, .60, structure.depth + .46},
        structure.rotation,
        plinth,
    )
    if !landmark && facade_style == 3 {
        wing_x, wing_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            structure.width * .28,
            -structure.depth * .05,
            structure.rotation,
        )
        wing_height := structure.height * .44
        world_box_rotated(
            {wing_x, structure.base_y + wing_height * .5, wing_z},
            {structure.width * .38, wing_height, structure.depth * .72},
            structure.rotation,
            stone,
        )
        world_box_rotated(
            {wing_x, structure.base_y + wing_height + .18, wing_z},
            {structure.width * .42, .36, structure.depth * .78},
            structure.rotation,
            {184, 93, 61, 255},
        )
    }
    world_architecture_roof(structure, landmark)
    // Dark inset windows and red shutters give the generated blocks a readable
    // Adriatic façade even at the editor's wide camera distance.
    window := facade_style == 2 ? rl.Color{42, 74, 82, 255} : rl.Color{48, 62, 64, 255}
    shutter :=
        facade_style == 2 ? rl.Color{43, 102, 126, 255} : facade_style == 3 ? rl.Color{236, 218, 179, 255} : rl.Color{167, 61, 53, 255}
    rows := landmark ? 4 : architecture.facade_floor_count(structure.height)
    columns := landmark ? 1 : 2
    if !landmark {
        door_x, door_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .18,
            structure.rotation,
        )
        door :=
            facade_style == 2 ? rl.Color{54, 91, 99, 255} : facade_style == 3 ? rl.Color{109, 75, 57, 255} : rl.Color{92, 66, 57, 255}
        world_box_rotated(
            {door_x, structure.base_y + structure.height * .14, door_z},
            {structure.width * .18, structure.height * .24, .24},
            structure.rotation,
            door,
        )
        step_x, step_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .28,
            structure.rotation,
        )
        step_color :=
            facade_style == 2 ? rl.Color{103, 130, 125, 255} : facade_style == 3 ? rl.Color{178, 127, 88, 255} : rl.Color{178, 127, 88, 255}
        world_box_rotated(
            {step_x, structure.base_y + structure.height * .035, step_z},
            {structure.width * .24, .20, .42},
            structure.rotation,
            step_color,
        )
    }
    for row in 0 ..< rows {
        for column in 0 ..< columns {
            x := columns == 1 ? 0 : (f32(column) - .5) * structure.width * .42
            y := structure.base_y + structure.height * (.24 + f32(row) * .16)
            local_z := structure.depth * .5 + .16
            wx, wz := world_rotate_xz(structure.center_x, structure.center_z, x, local_z, structure.rotation)
            world_box_rotated(
                {wx, y, wz},
                {structure.width * (columns == 1 ? .16 : .13), structure.height * .10, .22},
                structure.rotation,
                window,
            )
            if !landmark {
                if facade_style == 1 {
                    // A shallow balcony is a small silhouette break that reads
                    // clearly from the wide editor camera without needing a
                    // separate mesh asset.
                    balcony_x, balcony_z := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        x,
                        local_z + .08,
                        structure.rotation,
                    )
                    railing_x, railing_z := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        x,
                        local_z + .28,
                        structure.rotation,
                    )
                    world_box_rotated(
                        {balcony_x, y - structure.height * .065, balcony_z},
                        {structure.width * .34, .28, .48},
                        structure.rotation,
                        {178, 127, 88, 255},
                    )
                    world_box_rotated(
                        {railing_x, y + structure.height * .025, railing_z},
                        {structure.width * .28, structure.height * .09, .08},
                        structure.rotation,
                        {102, 76, 63, 255},
                    )
                } else if facade_style == 2 {
                    // Blue façades use small fabric awnings rather than
                    // balconies, giving this seed variant a distinct profile.
                    awning_x, awning_z := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        x,
                        local_z + .12,
                        structure.rotation,
                    )
                    world_box_rotated(
                        {awning_x, y + structure.height * .075, awning_z},
                        {structure.width * .20, .12, .34},
                        structure.rotation,
                        shutter,
                    )
                } else {
                    for side in -1 ..= 1 {
                        if side == 0 do continue
                        sx, sz := world_rotate_xz(wx, wz, f32(side) * structure.width * .085, 0, structure.rotation)
                        world_box_rotated(
                            {sx, y, sz},
                            {structure.width * .035, structure.height * .11, .28},
                            structure.rotation,
                            shutter,
                        )
                    }
                }
            }
        }
    }
    if !landmark && (roof_style == .Gable || roof_style == .Low_Gable) {
        // A single attic opening keeps the gable end from reading as an empty
        // triangle while staying small enough to preserve the roof silhouette.
        rise := roof_style == .Low_Gable ? structure.width * .24 : structure.width * .34
        attic_x, attic_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .58 + .18,
            structure.rotation,
        )
        world_box_rotated(
            {attic_x, structure.base_y + structure.height + rise * .40, attic_z},
            {structure.width * .16, structure.height * .12, .20},
            structure.rotation,
            window,
        )
        if facade_style != 1 {
            shutter_color := facade_style == 2 ? rl.Color{43, 102, 126, 255} : rl.Color{167, 61, 53, 255}
            for side in -1 ..= 1 {
                if side == 0 do continue
                shutter_x, shutter_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    f32(side) * structure.width * .075,
                    structure.depth * .58 + .18,
                    structure.rotation,
                )
                world_box_rotated(
                    {shutter_x, structure.base_y + structure.height + rise * .40, shutter_z},
                    {structure.width * .025, structure.height * .13, .23},
                    structure.rotation,
                    shutter_color,
                )
            }
        }
    }
    if !landmark {
        for row in 0 ..< rows {
            y := structure.base_y + structure.height * (.24 + f32(row) * .16)
            side_z := row % 2 == 0 ? -structure.depth * .16 : structure.depth * .16
            for side in -1 ..= 1 {
                if side == 0 do continue
                side_x := f32(side) * (structure.width * .5 + .14)
                wx, wz := world_rotate_xz(structure.center_x, structure.center_z, side_x, side_z, structure.rotation)
                world_box_rotated(
                    {wx, y, wz},
                    {.22, structure.height * .10, structure.depth * .14},
                    structure.rotation,
                    window,
                )
            }
        }
    }
}

world_structure_frame :: proc(structure: terrain.Structure, y: f32, color: rl.Color) {
    thickness := max(f32(.08), min(structure.width, structure.depth) * .035)
    left_x, left_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        -structure.width * .5 + thickness * .5,
        0,
        structure.rotation,
    )
    right_x, right_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        structure.width * .5 - thickness * .5,
        0,
        structure.rotation,
    )
    back_x, back_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        0,
        -structure.depth * .5 + thickness * .5,
        structure.rotation,
    )
    front_x, front_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        0,
        structure.depth * .5 - thickness * .5,
        structure.rotation,
    )
    world_box_rotated(
        {left_x, y + thickness * .5, left_z},
        {thickness, thickness, structure.depth + thickness * 2},
        structure.rotation,
        color,
    )
    world_box_rotated(
        {right_x, y + thickness * .5, right_z},
        {thickness, thickness, structure.depth + thickness * 2},
        structure.rotation,
        color,
    )
    world_box_rotated(
        {back_x, y + thickness * .5, back_z},
        {structure.width, thickness, thickness},
        structure.rotation,
        color,
    )
    world_box_rotated(
        {front_x, y + thickness * .5, front_z},
        {structure.width, thickness, thickness},
        structure.rotation,
        color,
    )
}

world_radial_formation :: proc(
    structure: terrain.Structure,
    radii: [4]f32,
    heights: [4]f32,
    z_scale, cap_height: f32,
) {
    segments := 8
    color := rl.Color{structure.color[0], structure.color[1], structure.color[2], structure.color[3]}
    vertices: [4][8]third_person.Vec3
    for layer in 0 ..< 4 {
        for segment in 0 ..< segments {
            angle := f32(segment) * math.PI * 2 / f32(segments)
            jitter := 1 + f32(math.sin(f64(f32(structure.seed) * .001 + f32(segment) * 2.17 + f32(layer) * .71))) * .11
            local_x := math.cos(angle) * structure.width * .5 * radii[layer] * jitter
            local_z := math.sin(angle) * structure.depth * .5 * radii[layer] * z_scale * jitter
            world_x, world_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            vertices[layer][segment] = {
                x = world_x,
                y = structure.base_y + structure.height * heights[layer],
                z = world_z,
            }
        }
    }
    for layer in 0 ..< 3 {
        for segment in 0 ..< segments {
            next := (segment + 1) % segments
            angle := (f32(segment) + .5) * math.PI * 2 / f32(segments)
            face_color := formation_face_color(color, angle, layer)
            world_triangle(
                vertices[layer][segment],
                vertices[layer + 1][segment],
                vertices[layer + 1][next],
                face_color,
            )
            world_triangle(vertices[layer][segment], vertices[layer + 1][next], vertices[layer][next], face_color)
        }
    }
    top := third_person.Vec3 {
        x = structure.center_x,
        y = structure.base_y + structure.height * cap_height,
        z = structure.center_z,
    }
    for segment in 0 ..< segments {
        next := (segment + 1) % segments
        world_triangle(
            vertices[3][segment],
            top,
            vertices[3][next],
            formation_face_color(color, f32(segment) * math.PI * 2 / f32(segments), 3),
        )
    }
}

world_formation :: proc(structure: terrain.Structure) {
    switch structure.kind {
    case .Box:
        world_box_rotated(
            {structure.center_x, structure.base_y + structure.height * .5, structure.center_z},
            {structure.width, structure.height, structure.depth},
            structure.rotation,
            rl.Color{structure.color[0], structure.color[1], structure.color[2], structure.color[3]},
        )
    case .Rock:
        world_radial_formation(structure, {1, .94, .62, .20}, {0, .24, .58, .88}, 1, .96)
    case .Spire:
        world_radial_formation(structure, {1, .62, .30, .07}, {0, .20, .46, .94}, 1, 1)
    case .Mountain:
        world_radial_formation(structure, {1, .94, .68, .24}, {0, .22, .54, .86}, 1, .99)
    case .Ridge:
        stone := structure
        stone.color = world_limestone_color(.Ridge)
        world_radial_formation(stone, {1, .92, .60, .14}, {0, .22, .50, .78}, .42, .90)
        world_foliage_tufts(stone)
    case .Cliff:
        stone := structure
        stone.color = world_limestone_color(.Cliff)
        world_cliff_formation(stone)
        world_foliage_tufts(stone)
    case .Foliage:
        world_foliage_formation(structure)
    case .Architecture:
        world_architecture(structure)
    }
}

world_structure_preview_cluster :: proc(editor: ^Editor) {
    if editor == nil do return
    preview := editor.structure_preview
    preview.color = {168, 239, 220, 255}
    world_formation(preview)
    world_structure_frame(preview, preview.base_y + .04, {190, 255, 229, 255})
    if !editor.structure_scatter_mode do return
    dx := editor.structure_preview_end_x - editor.structure_anchor_x
    dz := editor.structure_preview_end_z - editor.structure_anchor_z
    length := f32(math.sqrt(f64(dx * dx + dz * dz)))
    if length <= 0 do return
    direction_x, direction_z := dx / length, dz / length
    perpendicular_x, perpendicular_z := -direction_z, direction_x
    cell := editor.project.levels[0].cell_size
    for cluster_index in 0 ..< editor.structure_scatter_count - 1 {
        offset := f32(cluster_index) - f32(editor.structure_scatter_count - 2) * .5
        copy := preview
        copy.center_x += direction_x * offset * length * .22
        copy.center_z += direction_z * offset * length * .22
        jitter := f32(
            math.sin(
                f64(f32(cluster_index) * 2.31 + f32(editor.project.next_structure_id + u64(cluster_index + 1)) * .17),
            ),
        )
        copy.center_x += perpendicular_x * jitter * length * .10
        copy.center_z += perpendicular_z * jitter * length * .10
        copy.width = max(cell, copy.width * (.58 + f32(cluster_index % 2) * .12))
        copy.depth = max(cell, copy.depth * (.58 + f32((cluster_index + 1) % 2) * .12))
        copy.height = max(cell, copy.height * (.72 + f32(cluster_index) * .06))
        copy.base_y = terrain.sample_height(&editor.project, 0, copy.center_x, copy.center_z)
        copy.seed = u32(editor.project.next_structure_id + u64(cluster_index + 1)) * 747796405
        if editor.authoring_tool == .Foliage {
            copy.kind = .Foliage
        } else if !editor.structure_force_box && !editor.structure_cliff_mode {
            copy.kind = terrain.formation_kind_for_gesture(copy.width, copy.depth, copy.height)
        }
        copy.color = {168, 239, 220, 255}
        world_formation(copy)
        world_structure_frame(copy, copy.base_y + .04, {190, 255, 229, 255})
    }
}

world_curve_preview :: proc(editor: ^Editor) {
    if editor == nil || !editor.curve_drawing || editor.curve_point_count < 2 do return
    for index in 0 ..< editor.curve_point_count - 1 {
        preview := curve_segment_structure(editor, editor.curve_points[index], editor.curve_points[index + 1])
        preview.color = {168, 239, 220, 255}
        world_formation(preview)
        world_structure_frame(preview, preview.base_y + .04, {190, 255, 229, 255})
    }
}

world_cliff_formation :: proc(structure: terrain.Structure) {
    segments := 6
    color := rl.Color{structure.color[0], structure.color[1], structure.color[2], structure.color[3]}
    front_bottom: [7]third_person.Vec3
    front_top: [7]third_person.Vec3
    back_top: [7]third_person.Vec3
    back_bottom: [7]third_person.Vec3
    for segment in 0 ..= segments {
        fraction := f32(segment) / f32(segments)
        local_x := (fraction - .5) * structure.width
        top_jitter := f32(math.sin(f64(f32(structure.seed) * .001 + f32(segment) * 1.73))) * .055
        top_y := structure.base_y + structure.height * (.84 + top_jitter)
        front_x, front_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x,
            -structure.depth * .5,
            structure.rotation,
        )
        back_x, back_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x,
            structure.depth * .08,
            structure.rotation,
        )
        foot_x, foot_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x,
            structure.depth * .5,
            structure.rotation,
        )
        front_bottom[segment] = {front_x, structure.base_y, front_z}
        front_top[segment] = {front_x, top_y, front_z}
        back_top[segment] = {back_x, top_y, back_z}
        back_bottom[segment] = {foot_x, structure.base_y + structure.height * .14, foot_z}
    }
    for segment in 0 ..< segments {
        front_face := formation_face_color(color, -math.PI * .5, 0)
        top_face := formation_face_color(color, 0, 1)
        back_face := formation_face_color(color, math.PI * .5, 0)
        world_quad(
            front_bottom[segment],
            front_bottom[segment + 1],
            front_top[segment + 1],
            front_top[segment],
            front_face,
        )
        world_quad(front_top[segment], front_top[segment + 1], back_top[segment + 1], back_top[segment], top_face)
        world_quad(back_top[segment], back_top[segment + 1], back_bottom[segment + 1], back_bottom[segment], back_face)
    }
    world_quad(front_bottom[0], back_bottom[0], back_top[0], front_top[0], formation_face_color(color, -math.PI, 0))
    world_quad(
        front_bottom[segments],
        front_top[segments],
        back_top[segments],
        back_bottom[segments],
        formation_face_color(color, 0, 0),
    )
}

world_limestone_color :: proc(kind: terrain.Formation_Kind) -> [4]u8 {
    if kind == .Cliff do return {193, 191, 178, 255}
    return {215, 211, 193, 255}
}

world_foliage_card :: proc(
    center: third_person.Vec3,
    width, height: f32,
    tile: int,
    color: rl.Color,
    mirror: bool,
    flip_vertical := false,
) {
    if len(world_renderer.foliage_vertices) + 6 > FOLIAGE_VERTEX_CAPACITY do return
    editor := world_renderer.editor
    if editor == nil do return
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    right := third_person.Vec3{camera.right.x * width * .5, camera.right.y * width * .5, camera.right.z * width * .5}
    up := third_person.Vec3{camera.up.x * height * .5, camera.up.y * height * .5, camera.up.z * height * .5}
    p0 := third_person.Vec3{center.x - right.x - up.x, center.y - right.y - up.y, center.z - right.z - up.z}
    p1 := third_person.Vec3{center.x + right.x - up.x, center.y + right.y - up.y, center.z + right.z - up.z}
    p2 := third_person.Vec3{center.x + right.x + up.x, center.y + right.y + up.y, center.z + right.z + up.z}
    p3 := third_person.Vec3{center.x - right.x + up.x, center.y - right.y + up.y, center.z - right.z + up.z}

    atlas_tile := ((tile % 16) + 16) % 16
    column, row := atlas_tile % 4, atlas_tile / 4
    // A two-pixel inset prevents linear filtering from borrowing color from
    // the neighboring cell in the 1254px atlas.
    inset := f32(2.0 / 1254.0)
    u0 := f32(column) * .25 + inset
    v0 := f32(row) * .25 + inset
    u1 := f32(column + 1) * .25 - inset
    v1 := f32(row + 1) * .25 - inset
    if mirror {
        u0, u1 = u1, u0
    }
    if flip_vertical {
        v0, v1 = v1, v0
    }
    tint := world_color(color)
    append(
        &world_renderer.foliage_vertices,
        Foliage_Vertex{{p0.x, p0.y, p0.z}, {u0, v1}, tint},
        Foliage_Vertex{{p1.x, p1.y, p1.z}, {u1, v1}, tint},
        Foliage_Vertex{{p2.x, p2.y, p2.z}, {u1, v0}, tint},
        Foliage_Vertex{{p0.x, p0.y, p0.z}, {u0, v1}, tint},
        Foliage_Vertex{{p2.x, p2.y, p2.z}, {u1, v0}, tint},
        Foliage_Vertex{{p3.x, p3.y, p3.z}, {u0, v0}, tint},
    )
}

world_foliage_vertex_color :: proc(ring, variation: int) -> rl.Color {
    palette := ((variation % 4) + 4) % 4
    switch ring {
    case 0:
        colors := [4]rl.Color{{43, 72, 48, 255}, {48, 78, 44, 255}, {52, 82, 47, 255}, {45, 75, 52, 255}}
        return colors[palette]
    case 1:
        // A deliberately cool, low-value shoulder remains visible in the
        // narrow gaps between overlapping lobes, acting as painted contact
        // shadow without another texture lookup or render pass.
        colors := [4]rl.Color{{58, 92, 55, 255}, {64, 97, 47, 255}, {70, 101, 51, 255}, {60, 94, 60, 255}}
        return colors[palette]
    case 2:
        // Upper crown rings stay within one restrained body-color family.
        // Broad value grouping belongs to the continuous foliage shader;
        // large per-ring jumps expose the triangulated construction as bright
        // ribbons when a tree is viewed near eye level.
        colors := [4]rl.Color{{82, 121, 78, 255}, {100, 133, 64, 255}, {124, 150, 61, 255}, {88, 126, 85, 255}}
        return colors[palette]
    case 3:
        colors := [4]rl.Color{{88, 128, 82, 255}, {106, 139, 66, 255}, {133, 157, 64, 255}, {95, 133, 90, 255}}
        return colors[palette]
    case 4:
        colors := [4]rl.Color{{92, 132, 85, 255}, {111, 143, 68, 255}, {138, 162, 67, 255}, {99, 137, 94, 255}}
        return colors[palette]
    case 5:
        colors := [4]rl.Color{{96, 136, 88, 255}, {115, 146, 70, 255}, {142, 166, 70, 255}, {103, 141, 98, 255}}
        return colors[palette]
    case 6:
        colors := [4]rl.Color{{99, 139, 90, 255}, {118, 149, 72, 255}, {145, 169, 72, 255}, {106, 144, 101, 255}}
        return colors[palette]
    }
    return {78, 112, 53, 255}
}

world_foliage_clump_color :: proc(ring, variation: int, clump: f32) -> rl.Color {
    // Extend the ring palette with a clump-aligned temperature and value shift.
    // Troughs between the rounded bunches sink into a cooler, lower-value
    // pocket -- soft painted ambient occlusion in the crevices -- while the
    // crests lift toward a warmer sunlit accent. Both are derived from the
    // ring's own body color so every species and palette family stays
    // harmonized, and the shift stays gentle so the grouped painted planes
    // never resolve into bright ribbons that expose the triangulation.
    base := world_foliage_vertex_color(ring, variation)
    if clump < 0 {
        // Deeper occlusion on the lower shoulders, where overlapping boughs
        // trap shade; the upper crown plane keeps only a faint recess.
        pocket_amount := clamp(-clump, 0, 1) * (.42 - f32(ring) * .035)
        pocket := rl.Color{u8(f32(base.r) * .70), u8(f32(base.g) * .81), u8(f32(base.b) * .90), base.a}
        return color_lerp(base, pocket, clamp(pocket_amount, 0, 1))
    }
    crest_amount := clamp(clump, 0, 1) * .22
    crest := rl.Color {
        u8(min(f32(base.r) * 1.15, 255.0)),
        u8(min(f32(base.g) * 1.08, 255.0)),
        u8(f32(base.b) * .93),
        base.a,
    }
    return color_lerp(base, crest, crest_amount)
}

world_foliage_trunk :: proc(x, z, base_y, height, radius: f32, seed: u32) {
    // Eight sides are enough to remove the conspicuous hexagonal shaft at
    // walking distance while keeping mature forests inexpensive.
    SEGMENTS :: 8
    TRUNK_RINGS :: 4
    base: [SEGMENTS]third_person.Vec3
    top: [SEGMENTS]third_person.Vec3
    rings: [TRUNK_RINGS][SEGMENTS]third_person.Vec3
    lean_angle := f32(seed % 628) * .01
    lean_x := math.cos(lean_angle) * height * .045
    lean_z := math.sin(lean_angle) * height * .045
    bend_angle := lean_angle + math.PI * .5 + f32(seed % 17) * .037
    bend_x, bend_z := math.cos(bend_angle), math.sin(bend_angle)
    ring_fraction := [TRUNK_RINGS]f32{0, .34, .69, 1}
    ring_radius := [TRUNK_RINGS]f32{1, .91, .78, .66}
    for ring in 0 ..< TRUNK_RINGS {
        fraction := ring_fraction[ring]
        curve := f32(math.sin(f64(fraction * math.PI)))
        center_x := x + lean_x * fraction + bend_x * height * .027 * curve
        center_z := z + lean_z * fraction + bend_z * height * .027 * curve
        for segment in 0 ..< SEGMENTS {
            angle := f32(segment) * math.PI * 2 / SEGMENTS + f32(ring) * .025
            rings[ring][segment] = {
                center_x + math.cos(angle) * radius * ring_radius[ring],
                base_y + height * fraction,
                center_z + math.sin(angle) * radius * ring_radius[ring],
            }
        }
    }
    for segment in 0 ..< SEGMENTS {
        base[segment] = rings[0][segment]
        top[segment] = rings[TRUNK_RINGS - 1][segment]
    }
    bark_light := [TRUNK_RINGS - 1]rl.Color{{91, 72, 52, 255}, {97, 76, 54, 255}, {103, 80, 55, 255}}
    bark_shadow := [TRUNK_RINGS - 1]rl.Color{{62, 55, 46, 255}, {66, 58, 47, 255}, {71, 61, 48, 255}}
    // Neighboring patches should not all expose the same orange-brown posts.
    // Three restrained bark families give the woodland warm oak, cool
    // gray-bark, and muted umber notes while keeping every trunk subordinate
    // to the canopy. Moss is applied afterward and ties the families together.
    bark_family := seed % 3
    if bark_family == 1 {
        bark_light = {{91, 79, 62, 255}, {98, 84, 64, 255}, {105, 89, 66, 255}}
        bark_shadow = {{62, 58, 50, 255}, {66, 61, 51, 255}, {71, 65, 53, 255}}
    } else if bark_family == 2 {
        bark_light = {{102, 69, 49, 255}, {109, 73, 51, 255}, {116, 78, 53, 255}}
        bark_shadow = {{68, 52, 43, 255}, {73, 55, 44, 255}, {78, 58, 45, 255}}
    }
    moss_light := [TRUNK_RINGS - 1]rl.Color{{91, 94, 53, 255}, {94, 96, 55, 255}, {96, 98, 57, 255}}
    moss_shadow := [TRUNK_RINGS - 1]rl.Color{{59, 67, 45, 255}, {62, 69, 46, 255}, {65, 71, 47, 255}}
    for ring in 0 ..< TRUNK_RINGS - 1 {
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            // Let bark value travel continuously around the trunk instead of
            // assigning every third face a dark stripe. A seed phase keeps
            // neighboring trunks from repeating the identical highlight.
            face_angle := (f32(segment) + .5) * math.PI * 2 / SEGMENTS + f32(seed % 37) * .017
            bark_rhythm := f32(math.sin(f64(f32(segment) * 1.73 + f32(ring) * 2.11 + f32(seed % 29) * .19))) * .045
            face_light := clamp(.18 + (.5 + .5 * math.cos(face_angle - .72)) * .72 + bark_rhythm, .12, .94)
            lower_color := color_lerp(bark_shadow[ring], bark_light[ring], face_light)
            upper_index := min(ring + 1, TRUNK_RINGS - 2)
            upper_color := color_lerp(bark_shadow[upper_index], bark_light[upper_index], face_light)
            // Moss shares one broad, cool-facing side across the woodland,
            // with a small per-tree drift. Blending it into the existing
            // vertices keeps the shaft inexpensive and avoids pasted stripes.
            moss_angle := math.PI * 1.38 + f32(seed % 13) * .018
            moss_facing := .5 + .5 * math.cos(face_angle - moss_angle)
            moss_amount := clamp((moss_facing - .38) * .48, 0, .28) * (1 - f32(ring) * .19)
            lower_moss := color_lerp(moss_shadow[ring], moss_light[ring], face_light)
            upper_moss := color_lerp(moss_shadow[upper_index], moss_light[upper_index], face_light)
            lower_color = color_lerp(lower_color, lower_moss, moss_amount)
            upper_color = color_lerp(upper_color, upper_moss, moss_amount * .82)
            world_quad_colored(
                rings[ring][segment],
                rings[ring + 1][segment],
                rings[ring + 1][next],
                rings[ring][next],
                lower_color,
                upper_color,
                upper_color,
                lower_color,
            )
        }
    }

    // Sparse vertical brush strips keep the broad front faces from reading as
    // untextured orange posts. They sit just above the lower shaft and rotate
    // per tree; one dark bark split and one shorter moss stroke are enough to
    // imply surface rhythm without introducing another material or texture.
    for stroke in 0 ..< 2 {
        stroke_angle := f32(seed % 211) * .029 + f32(stroke) * 2.17
        outward_x, outward_z := math.cos(stroke_angle), math.sin(stroke_angle)
        tangent_x, tangent_z := -outward_z, outward_x
        stroke_width := radius * (stroke == 0 ? f32(.20) : f32(.27))
        stroke_bottom := base_y + height * (stroke == 0 ? f32(.12) : f32(.07))
        stroke_top := base_y + height * (stroke == 0 ? f32(.43) : f32(.28))
        lower_outset := radius * 1.018
        upper_radius :=
            radius *
            (ring_radius[1] +
                    (ring_radius[2] - ring_radius[1]) *
                        clamp(
                            ((stroke_top - base_y) / height - ring_fraction[1]) /
                            (ring_fraction[2] - ring_fraction[1]),
                            0,
                            1,
                        ))
        upper_outset := upper_radius * 1.018
        stroke_color := rl.Color{52, 49, 42, 220}
        if stroke == 1 do stroke_color = {64, 76, 49, 205}
        world_quad(
            {
                x + outward_x * lower_outset - tangent_x * stroke_width,
                stroke_bottom,
                z + outward_z * lower_outset - tangent_z * stroke_width,
            },
            {
                x +
                lean_x * (stroke_top - base_y) / height +
                outward_x * upper_outset -
                tangent_x * stroke_width * .68,
                stroke_top - height * .012,
                z +
                lean_z * (stroke_top - base_y) / height +
                outward_z * upper_outset -
                tangent_z * stroke_width * .68,
            },
            {
                x +
                lean_x * (stroke_top - base_y) / height +
                outward_x * upper_outset +
                tangent_x * stroke_width * .68,
                stroke_top,
                z +
                lean_z * (stroke_top - base_y) / height +
                outward_z * upper_outset +
                tangent_z * stroke_width * .68,
            },
            {
                x + outward_x * lower_outset + tangent_x * stroke_width,
                stroke_bottom + height * .018,
                z + outward_z * lower_outset + tangent_z * stroke_width,
            },
            stroke_color,
        )
    }

    // Three low buttress roots anchor the stylized trunk to the terrain.
    // Their uneven reach avoids a decorative star, and the wedges disappear
    // naturally beneath understory when viewed from above.
    ROOTS :: 3
    for root in 0 ..< ROOTS {
        angle :=
            lean_angle +
            f32(root) * math.PI * 2 / ROOTS +
            f32(math.sin(f64(f32(seed) * .023 + f32(root) * 1.71))) * .29
        direction_x, direction_z := math.cos(angle), math.sin(angle)
        side_x, side_z := -direction_z, direction_x
        root_reach := radius * (2.35 + f32(root % 2) * .62)
        root_half_width := radius * (.54 + f32((root + 1) % 2) * .12)
        shoulder := third_person.Vec3 {
            x + direction_x * radius * .72,
            base_y + radius * (1.75 + f32(root) * .16),
            z + direction_z * radius * .72,
        }
        left := third_person.Vec3 {
            x + direction_x * radius - side_x * root_half_width,
            base_y + .035,
            z + direction_z * radius - side_z * root_half_width,
        }
        right := third_person.Vec3 {
            x + direction_x * radius + side_x * root_half_width,
            base_y + .035,
            z + direction_z * radius + side_z * root_half_width,
        }
        tip := third_person.Vec3{x + direction_x * root_reach, base_y + .025, z + direction_z * root_reach}
        root_light := rl.Color{91, 71, 52, 255}
        root_shadow := rl.Color{62, 54, 46, 255}
        if bark_family == 1 {
            root_light = {87, 76, 61, 255}
            root_shadow = {59, 57, 51, 255}
        } else if bark_family == 2 {
            root_light = {96, 66, 50, 255}
            root_shadow = {65, 50, 43, 255}
        }
        if root % 2 == 1 {
            root_light = color_lerp(root_light, {67, 63, 52, 255}, .34)
            root_shadow = color_lerp(root_shadow, {49, 50, 45, 255}, .22)
        }
        world_triangle_colored(left, tip, shoulder, root_shadow, root_shadow, root_light)
        world_triangle_colored(tip, right, shoulder, root_shadow, root_light, root_light)
    }

    crown := third_person.Vec3{x + lean_x, base_y + height, z + lean_z}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(top[segment], crown, top[next], {65, 54, 39, 255})
    }

    // A few broad forked limbs turn the supporting pole into a tree. They
    // disappear into the crown from above but become an important readable
    // layer at walking height and across glade openings.
    LIMBS :: 3
    for limb in 0 ..< LIMBS {
        angle :=
            lean_angle +
            f32(limb) * math.PI * 2 / LIMBS +
            f32(math.sin(f64(f32(seed) * .017 + f32(limb) * 1.91))) * .34
        direction_x, direction_z := math.cos(angle), math.sin(angle)
        side_x, side_z := -direction_z, direction_x
        start_height := height * (.54 + f32(limb) * .055)
        start_fraction := start_height / height
        start_curve := f32(math.sin(f64(start_fraction * math.PI)))
        reach := radius * (2.75 + f32(limb % 2) * .58)
        start := third_person.Vec3 {
            x + lean_x * start_fraction + bend_x * height * .027 * start_curve,
            base_y + start_height,
            z + lean_z * start_fraction + bend_z * height * .027 * start_curve,
        }
        finish := third_person.Vec3 {
            x + lean_x * .92 + direction_x * reach,
            base_y + height * (.76 + f32(limb) * .035),
            z + lean_z * .92 + direction_z * reach,
        }
        start_half_width := radius * .58
        finish_half_width := radius * .28
        limb_color := rl.Color{80, 64, 49, 255}
        if bark_family == 1 do limb_color = {76, 69, 57, 255}
        if bark_family == 2 do limb_color = {88, 60, 46, 255}
        if limb % 2 == 1 {
            limb_color = color_lerp(limb_color, {55, 53, 47, 255}, .42)
        }
        world_quad(
            {start.x - side_x * start_half_width, start.y, start.z - side_z * start_half_width},
            {start.x + side_x * start_half_width, start.y, start.z + side_z * start_half_width},
            {finish.x + side_x * finish_half_width, finish.y, finish.z + side_z * finish_half_width},
            {finish.x - side_x * finish_half_width, finish.y, finish.z - side_z * finish_half_width},
            limb_color,
        )
    }
}

world_foliage_understory_tuft :: proc(x, z, base_y, width, height: f32, seed: u32) {
    FRONDS :: 6
    camera_position := world_renderer.editor.camera_pose.position
    camera_delta_x := camera_position.x - x
    camera_delta_z := camera_position.z - z
    leaflet_distance := f32(math.sqrt(f64(camera_delta_x * camera_delta_x + camera_delta_z * camera_delta_z)))
    // Leaflet tiers are a walking-distance silhouette feature. Beyond this
    // range they occupy sub-pixel space and would only consume world-mesh
    // capacity needed by the dense forest canopy.
    emit_leaflets := leaflet_distance < 220
    emit_lush_leaflets := leaflet_distance < 140
    for frond in 0 ..< FRONDS {
        angle := f32(frond) * math.PI * 2 / FRONDS + f32(seed % 113) * .037
        direction_x, direction_z := math.cos(angle), math.sin(angle)
        side_x, side_z := -direction_z, direction_x
        spread := width * (.24 + f32(frond % 2) * .055)
        if emit_lush_leaflets {
            // At walking distance the central triangle is only a narrow stem;
            // the tiered leaflets, not a giant spearhead, carry the fern.
            spread = width * (.065 + f32(frond % 2) * .018)
        }
        lean := width * (.18 + f32((frond + 1) % 3) * .045)
        blade_height := height * (.72 + f32(math.sin(f64(f32(seed) * .011 + f32(frond) * 1.83))) * .18)
        left := third_person.Vec3{x - side_x * spread, base_y + .08, z - side_z * spread}
        right := third_person.Vec3{x + side_x * spread, base_y + .08, z + side_z * spread}
        tip := third_person.Vec3{x + direction_x * lean, base_y + blade_height, z + direction_z * lean}
        color := rl.Color{46, 91, 60, 255}
        if frond % 3 == 1 do color = {58, 108, 64, 255}
        if frond % 3 == 2 do color = {39, 80, 59, 255}
        tip_color := color
        tip_color.r = u8(min(int(tip_color.r) + 12, 255))
        tip_color.g = u8(min(int(tip_color.g) + 16, 255))
        tip_color.b = u8(min(int(tip_color.b) + 5, 255))
        // Ground vertices carry a downward normal so the canopy wind weight is
        // zero; the upright tip carries the full weight. The same triangle
        // therefore bends like a rooted fern instead of sliding as one rigid
        // piece across the forest floor.
        base_normal := third_person.Vec3{0, -1, 0}
        tip_normal := vec_normalize({direction_x * .34, .94, direction_z * .34})
        world_triangle_foliage(left, tip, right, color, tip_color, color, base_normal, tip_normal, base_normal)

        // Walking-distance ferns carry three tapered leaflet tiers on every
        // frond. The middle LOD keeps one tier on alternating fronds, and the
        // distant LOD retains only the broad blade. This turns nearby cones
        // into layered woodland silhouettes without multiplying the stress
        // scene's sub-pixel geometry.
        tier_count := 0
        if emit_lush_leaflets {
            tier_count = 3
        } else if emit_leaflets && frond % 2 == 0 {
            tier_count = 1
        }
        lush_fractions := [3]f32{.29, .49, .68}
        lush_reaches := [3]f32{.32, .27, .20}
        for tier in 0 ..< tier_count {
            leaflet_fraction := f32(.56)
            if emit_lush_leaflets {
                leaflet_fraction = lush_fractions[tier]
            }
            stem_half_span := emit_lush_leaflets ? f32(.075) : f32(.08)
            stem_back_fraction := leaflet_fraction - stem_half_span
            stem_front_fraction := leaflet_fraction + stem_half_span
            stem_back := third_person.Vec3 {
                x + direction_x * lean * stem_back_fraction,
                base_y + blade_height * stem_back_fraction,
                z + direction_z * lean * stem_back_fraction,
            }
            stem_front := third_person.Vec3 {
                x + direction_x * lean * stem_front_fraction,
                base_y + blade_height * stem_front_fraction,
                z + direction_z * lean * stem_front_fraction,
            }
            leaflet_center_x := x + direction_x * lean * leaflet_fraction
            leaflet_center_z := z + direction_z * lean * leaflet_fraction
            leaflet_reach := width * (.23 + f32(frond % 2) * .035)
            if emit_lush_leaflets {
                leaflet_reach = width * lush_reaches[tier]
            }
            leaflet_lift := height * (.030 + f32((frond + tier + 1) % 2) * .012)
            left_leaflet := third_person.Vec3 {
                leaflet_center_x - side_x * leaflet_reach,
                base_y + blade_height * leaflet_fraction + leaflet_lift,
                leaflet_center_z - side_z * leaflet_reach,
            }
            right_leaflet := third_person.Vec3 {
                leaflet_center_x + side_x * leaflet_reach,
                base_y + blade_height * leaflet_fraction + leaflet_lift,
                leaflet_center_z + side_z * leaflet_reach,
            }
            leaflet_color := tip_color
            if tier == 0 {
                leaflet_color.r = u8(max(int(leaflet_color.r) - 6, 0))
                leaflet_color.g = u8(max(int(leaflet_color.g) - 7, 0))
            }
            stem_normal := vec_normalize({direction_x * .18, .44, direction_z * .18})
            leaflet_normal := vec_normalize({direction_x * .24, .68, direction_z * .24})
            world_triangle_foliage(
                stem_back,
                left_leaflet,
                stem_front,
                color,
                leaflet_color,
                leaflet_color,
                stem_normal,
                leaflet_normal,
                leaflet_normal,
            )
            world_triangle_foliage(
                stem_front,
                right_leaflet,
                stem_back,
                leaflet_color,
                leaflet_color,
                color,
                leaflet_normal,
                leaflet_normal,
                stem_normal,
            )
        }
    }
}

world_foliage_ground_rosette :: proc(x, z, base_y, width, height: f32, seed: u32) {
    camera_position := world_renderer.editor.camera_pose.position
    camera_delta_x := camera_position.x - x
    camera_delta_z := camera_position.z - z
    camera_distance := f32(math.sqrt(f64(camera_delta_x * camera_delta_x + camera_delta_z * camera_delta_z)))
    leaf_count := 4
    if camera_distance < 180 do leaf_count = 7
    for leaf in 0 ..< leaf_count {
        angle := f32(leaf) * math.PI * 2 / f32(leaf_count) + f32(seed % 137) * .031
        direction_x, direction_z := math.cos(angle), math.sin(angle)
        side_x, side_z := -direction_z, direction_x
        reach := width * (.34 + f32(math.sin(f64(f32(seed) * .013 + f32(leaf) * 1.79))) * .08)
        lift := height * (.56 + f32(math.sin(f64(f32(seed) * .019 + f32(leaf) * 2.17))) * .18)
        half_width := width * (.105 + f32(leaf % 2) * .018)
        root := third_person.Vec3{x, base_y + .07, z}
        left := third_person.Vec3 {
            x + direction_x * reach * .50 - side_x * half_width,
            base_y + lift * .72,
            z + direction_z * reach * .50 - side_z * half_width,
        }
        right := third_person.Vec3 {
            x + direction_x * reach * .50 + side_x * half_width,
            base_y + lift * .72,
            z + direction_z * reach * .50 + side_z * half_width,
        }
        tip := third_person.Vec3{x + direction_x * reach, base_y + lift * .38, z + direction_z * reach}
        root_color := rl.Color{38, 77, 53, 255}
        leaf_color := rl.Color{61, 111, 66, 255}
        tip_color := rl.Color{70, 118, 68, 255}
        if leaf % 3 == 1 {
            root_color = {43, 81, 48, 255}
            leaf_color = {72, 119, 62, 255}
            tip_color = {82, 128, 66, 255}
        } else if leaf % 3 == 2 {
            root_color = {35, 72, 56, 255}
            leaf_color = {53, 101, 71, 255}
            tip_color = {63, 111, 74, 255}
        }
        root_normal := third_person.Vec3{0, -1, 0}
        leaf_normal := vec_normalize({direction_x * .32, .88, direction_z * .32})
        tip_normal := vec_normalize({direction_x * .46, .76, direction_z * .46})
        world_triangle_foliage(
            root,
            left,
            tip,
            root_color,
            leaf_color,
            tip_color,
            root_normal,
            leaf_normal,
            tip_normal,
        )
        world_triangle_foliage(
            root,
            tip,
            right,
            root_color,
            tip_color,
            leaf_color,
            root_normal,
            tip_normal,
            leaf_normal,
        )
    }
}

world_foliage_ground_dapple :: proc(x, z, base_y, width, depth, rotation: f32, seed: u32) {
    SEGMENTS :: 7
    // Painted woodland floors need readable pools of bounced canopy light.
    // Keep the irregular edge fully transparent, but lift the center enough
    // to separate fern and trunk silhouettes from one uniform green plane.
    center_color := rl.Color{184, 166, 86, 101}
    if seed % 3 == 1 do center_color = {143, 154, 83, 92}
    if seed % 3 == 2 do center_color = {197, 172, 91, 98}
    edge_color := center_color
    edge_color.a = 0
    center := third_person.Vec3{x, base_y + .115, z}
    points: [SEGMENTS]third_person.Vec3
    for segment in 0 ..< SEGMENTS {
        angle := rotation + f32(segment) * math.PI * 2 / SEGMENTS
        irregularity := .82 + f32(math.sin(f64(f32(seed) * .019 + f32(segment) * 2.37))) * .18
        points[segment] = {
            x + math.cos(angle) * width * .5 * irregularity,
            base_y + .11,
            z + math.sin(angle) * depth * .5 * irregularity,
        }
    }
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle_colored(points[segment], points[next], center, edge_color, edge_color, center_color)
    }
}

world_foliage_lobe :: proc(
    structure: terrain.Structure,
    local_center_x, local_center_z, width, depth, height: f32,
    base_lift: f32,
    is_hedge: bool,
    variation: int,
    outline_angle: f32,
    emit_outline: bool,
) {
    // Smooth normals cannot repair a faceted outer contour. Eighteen sides
    // keep the long crown ridge and hanging skirt from resolving into obvious
    // straight runs at eye level. The deterministic radius and height rhythm
    // still does the silhouette design; the extra sides only let that rhythm
    // describe a soft painted edge.
    // Nearby crowns receive a finer silhouette while distant forest masses
    // retain the cheaper contour. This spends vertices where scallops occupy
    // multiple pixels instead of increasing every canopy in overview scenes.
    MAX_SEGMENTS :: 30
    segment_count := 18
    lobe_world_x, lobe_world_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        local_center_x,
        local_center_z,
        structure.rotation,
    )
    camera_position := world_renderer.editor.camera_pose.position
    camera_delta_x := camera_position.x - lobe_world_x
    camera_delta_z := camera_position.z - lobe_world_z
    camera_distance := f32(math.sqrt(f64(camera_delta_x * camera_delta_x + camera_delta_z * camera_delta_z)))
    if camera_distance < 260 do segment_count = 24
    if camera_distance < 145 do segment_count = MAX_SEGMENTS
    PROFILE_RINGS :: 7
    MAX_RINGS :: 10
    ring_count := PROFILE_RINGS
    if camera_distance < 260 do ring_count = 9
    if camera_distance < 145 do ring_count = MAX_RINGS
    is_forest_lobe := !is_hedge && max(structure.width, structure.depth) >= 105 && structure.height >= 58
    if is_forest_lobe && camera_distance >= 260 {
        // Dense stands contain dozens of tree-scale crowns. Eight sides and
        // four sampled profile rings are enough once those crowns merge into
        // a distant forest silhouette, while keeping the aggregate affordable.
        segment_count = 8
        ring_count = 4
    }
    // Near crowns keep the full medium and fine clump breakup; distant masses
    // shed it so their silhouette stays a calm, inexpensive composition of the
    // bold dominant bunches. The fade is continuous, so a crown morphs its
    // surface detail smoothly rather than popping at an LOD band boundary.
    clump_detail_fade := clamp((320 - camera_distance) / 175, 0, 1)
    // Canopy lobes are broad layered shelves, not inflated spheres. The
    // widest contour sits low, the upper shoulder stays full, and the shallow
    // cap produces a painted crown plane instead of a pointed balloon.
    ring_height := [PROFILE_RINGS]f32{.06, .15, .28, .43, .58, .71, .81}
    ring_radius := [PROFILE_RINGS]f32{.70, .86, .98, 1.0, .92, .69, .44}
    profile_width, profile_depth, profile_height := width, depth, height
    irregularity_strength := f32(.14)
    crown_base := f32(.90)
    species := int(structure.seed % 3)
    switch species {
    case 1:
        // Oak-like: a low, broad, rugged shelf with a full upper shoulder.
        ring_height = {.05, .14, .26, .39, .52, .64, .75}
        ring_radius = {.74, .88, .98, 1.0, .94, .74, .54}
        profile_width *= 1.09
        profile_depth *= 1.05
        profile_height *= .90
        irregularity_strength = .20
        crown_base = .85
    case 2:
        // Laurel-like: tighter upright bunches with a steeper shoulder and
        // smaller crown plane, useful as vertical accents in a mixed forest.
        ring_height = {.07, .18, .32, .47, .63, .77, .86}
        ring_radius = {.62, .82, .97, 1.0, .79, .52, .30}
        profile_width *= .84
        profile_depth *= .87
        profile_height *= 1.12
        irregularity_strength = .105
        crown_base = .96
    case:
    // Rounded broadleaf is the balanced default.
    }
    if base_lift > 0 {
        // Forest crowns join into broad, overlapping bough shelves. Keeping
        // their widest contour high and flattening the crown prevents a grove
        // from becoming a collection of upright gumdrops, while the stronger
        // irregularity preserves distinct hand-painted crown gestures.
        ring_height = {.04, .11, .21, .33, .46, .58, .69}
        ring_radius = {.78, .90, .98, 1.0, .94, .78, .58}
        profile_width *= 1.17
        profile_depth *= 1.10
        profile_height *= .79
        irregularity_strength = max(irregularity_strength, f32(.18))
        crown_base = .80
        switch species {
        case 1:
            // Mature oak shelves stay especially broad and low, with a full
            // shoulder and a gently recessed crown plane.
            ring_height = {.03, .09, .17, .28, .40, .52, .64}
            ring_radius = {.82, .93, .99, 1.0, .95, .79, .57}
            crown_base = .75
        case 2:
            // Laurel-like forest crowns keep a narrower, rising outer gesture
            // so mixed woods do not collapse into one repeated flat cushion.
            ring_height = {.05, .14, .25, .39, .54, .68, .79}
            ring_radius = {.70, .87, .98, 1.0, .87, .64, .40}
            crown_base = .89
        case:
        // Balanced broadleaf keeps the shared forest shelf.
        }
    } else if is_hedge {
        // A maintained hedge is one shallow rolling volume rather than a row
        // of miniature trees. Preserve soft crown undulation while keeping
        // the shoulders broad enough for neighboring lobes to disappear into.
        ring_height = {.04, .10, .19, .31, .43, .55, .66}
        ring_radius = {.80, .91, .98, 1.0, .94, .79, .58}
        profile_width *= 1.08
        profile_depth *= 1.04
        profile_height *= .78
        irregularity_strength = max(irregularity_strength, f32(.15))
        crown_base = .76
    }
    // The seven authored profile points remain the shape authority. Nearby
    // crowns interpolate two additional contours from that same curve instead
    // of changing species proportions or procedural phases with LOD.
    sampled_ring_height: [MAX_RINGS]f32
    sampled_ring_radius: [MAX_RINGS]f32
    for ring in 0 ..< ring_count {
        profile_position := f32(ring) * f32(PROFILE_RINGS - 1) / f32(max(ring_count - 1, 1))
        lower := clamp(int(profile_position), 0, PROFILE_RINGS - 1)
        upper := min(lower + 1, PROFILE_RINGS - 1)
        fraction := profile_position - f32(lower)
        sampled_ring_height[ring] = ring_height[lower] + (ring_height[upper] - ring_height[lower]) * fraction
        sampled_ring_radius[ring] = ring_radius[lower] + (ring_radius[upper] - ring_radius[lower]) * fraction
    }
    vertices: [MAX_RINGS][MAX_SEGMENTS]third_person.Vec3
    normals: [MAX_RINGS][MAX_SEGMENTS]third_person.Vec3
    // The signed clump field, sampled once per contour vertex, drives both the
    // rounded three-dimensional bulges and the crevice ambient occlusion baked
    // into the vertex colors, so the painted shade tracks the real mesh volume.
    clump_field: [MAX_RINGS][MAX_SEGMENTS]f32
    // One authored mass keeps a coherent species hue. Earlier per-lobe palette
    // cycling made close trees read as a patchwork of unrelated teal, olive,
    // and yellow polygons; lighting and brush marks already provide the
    // necessary internal variation.
    color_variation := int(structure.seed % 4)
    if is_hedge {
        // Dense clipped laurel lives in the cool palette families. Excluding
        // the hot yellow variant separates hedges from flowering bushes and
        // keeps a long formation from becoming one fluorescent stripe.
        color_variation = structure.seed % 2 == 0 ? 0 : 3
    }
    if base_lift > 0 {
        // Mature woods need broad color regions, not a checkerboard of random
        // lime and teal crowns. A slow world-space field lets neighboring
        // authored patches share a palette family while still drifting from
        // cool recesses through green into warm olive crowns. The hottest
        // yellow-green family remains available to standalone flowering
        // bushes; across a mature canopy it overexposes broad eye-level faces
        // and makes the underlying mesh transitions unnecessarily visible.
        palette_field :=
            f32(math.sin(f64(structure.center_x * .0092 + structure.center_z * .0049))) +
            f32(math.sin(f64(structure.center_x * -.0037 + structure.center_z * .0081 + 1.7))) * .62
        if palette_field < -.48 {
            color_variation = 0
        } else if palette_field < .16 {
            color_variation = 3
        } else if palette_field < .72 {
            color_variation = 1
        } else {
            color_variation = 1
        }
    }

    for ring in 0 ..< ring_count {
        profile_ring := f32(ring) * f32(PROFILE_RINGS - 1) / f32(max(ring_count - 1, 1))
        for segment in 0 ..< segment_count {
            // Slightly twist each contour so the facets do not stack into
            // continuous vertical seams. A deterministic phase keeps adjacent
            // lobes from sharing the same outline.
            contour_angle := f32(segment) * math.PI * 2 / f32(segment_count)
            angle :=
                contour_angle +
                profile_ring * .075 +
                f32(math.sin(f64(f32(variation) * 1.37 + profile_ring * 2.11))) * .045
            // Three correlated octaves compose the crown as bold, rounded
            // cumulus clumps with a clear big/medium/small nesting -- the
            // Ghibli canopy read -- rather than one uniform scallop frequency.
            // The dominant octave carves a few large bunches; the medium and
            // fine octaves only break their edges, and both quieter octaves
            // fade with distance so far masses stay calm while near crowns gain
            // hand-painted volume without changing topology or vertex cost.
            clump_dominant := f32(
                math.sin(
                    f64(f32(structure.seed) * .008 + f32(variation) * 1.63 + contour_angle * 1.8 + profile_ring * .42),
                ),
            )
            clump_medium := f32(
                math.sin(
                    f64(f32(structure.seed) * .013 + f32(variation) * 2.11 + contour_angle * 3.9 - profile_ring * .63),
                ),
            )
            clump_fine := f32(
                math.sin(
                    f64(f32(structure.seed) * .021 + f32(variation) * 2.67 + contour_angle * 7.1 + profile_ring * .94),
                ),
            )
            clump :=
                clump_dominant * .60 +
                clump_medium * .28 * (.5 + .5 * clump_detail_fade) +
                clump_fine * .14 * clump_detail_fade
            clump_field[ring][segment] = clump
            irregularity := 1 + clump * irregularity_strength
            local_x := local_center_x + math.cos(angle) * profile_width * .5 * sampled_ring_radius[ring] * irregularity
            local_z := local_center_z + math.sin(angle) * profile_depth * .5 * sampled_ring_radius[ring] * irregularity
            world_x, world_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            contour_lift :=
                f32(math.sin(f64(f32(structure.seed) * .007 + f32(variation) * 1.43 + contour_angle * 4.899))) *
                profile_height *
                (ring == 0 ? f32(.008) : f32(.026))
            // Bulge crests dome outward and upward while troughs carve soft
            // crevices, turning the wavy outline into rounded three-dimensional
            // bunches. The dome weight peaks on the mid and upper shoulder and
            // vanishes at the skirt so the hanging underside stays a clean
            // shelf rather than a rippled ceiling.
            dome_weight := sampled_ring_height[ring] * (1 - sampled_ring_height[ring]) * 4
            contour_lift += clump * profile_height * dome_weight * .055
            if base_lift > 0 && ring == 0 {
                // The lowest forest contour carries uneven hanging bough
                // pockets. A broad rhythm chooses the limbs while a smaller
                // ripple keeps their tips leafy, breaking the tabletop
                // underside without adding cards hidden inside the mesh.
                broad_droop := f32(
                    math.sin(f64(f32(structure.seed) * .017 + f32(variation) * 1.23 + contour_angle * 3.841)),
                )
                tip_droop := f32(
                    math.sin(f64(f32(structure.seed) * .029 + f32(variation) * 2.07 + contour_angle * 7.369 + .8)),
                )
                droop_wave := clamp(.5 + broad_droop * .34 + tip_droop * .16, 0, 1)
                contour_lift -= profile_height * (.010 + droop_wave * .068)
            }
            vertices[ring][segment] = {
                world_x,
                structure.base_y + base_lift + profile_height * sampled_ring_height[ring] + contour_lift,
                world_z,
            }
            local_normal_x := math.cos(angle) * profile_height / max(profile_width, f32(.01))
            local_normal_y := (sampled_ring_height[ring] - .30) * 1.68
            local_normal_z := math.sin(angle) * profile_height / max(profile_depth, f32(.01))
            if base_lift > 0 {
                // Nearby forest lobes should share the lighting flow of their
                // parent crown. Blend each small ellipsoid normal toward a
                // broad formation normal so overlaps read as leafy bunches,
                // not colliding independently lit balls.
                mass_normal_x := local_x * structure.height * 2 / max(structure.width * structure.width, f32(.01))
                mass_normal_z := local_z * structure.height * 2 / max(structure.depth * structure.depth, f32(.01))
                local_normal_x += (mass_normal_x - local_normal_x) * .46
                local_normal_z += (mass_normal_z - local_normal_z) * .46
            }
            cosine, sine := math.cos(structure.rotation), math.sin(structure.rotation)
            normals[ring][segment] = vec_normalize(
                {
                    local_normal_x * cosine - local_normal_z * sine,
                    local_normal_y,
                    local_normal_x * sine + local_normal_z * cosine,
                },
            )
        }
    }

    base_x, base_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        local_center_x,
        local_center_z,
        structure.rotation,
    )
    base_fraction := f32(.065)
    if base_lift > 0 {
        // Lift the middle of an elevated crown's underside into a shallow
        // bowl. A flat center at the perimeter height created broad black
        // shelves when trees were viewed from below; this curved closure
        // keeps the deep pocket while allowing a soft value roll toward it.
        base_fraction = .115
    }
    base := third_person.Vec3{base_x, structure.base_y + base_lift + profile_height * base_fraction, base_z}
    for segment in 0 ..< segment_count {
        next := (segment + 1) % segment_count
        if base_lift > 0 {
            world_triangle_foliage(
                vertices[0][next],
                base,
                vertices[0][segment],
                world_foliage_clump_color(0, color_variation, clump_field[0][next]),
                {39, 66, 48, 255},
                world_foliage_clump_color(0, color_variation, clump_field[0][segment]),
                normals[0][next],
                {0, -1, 0},
                normals[0][segment],
            )
        } else {
            world_triangle(vertices[0][next], base, vertices[0][segment], {34, 61, 45, 255})
        }
    }

    for ring in 0 ..< ring_count - 1 {
        lower_palette_ring := clamp(
            int(f32(ring) * f32(PROFILE_RINGS - 1) / f32(max(ring_count - 1, 1)) + .5),
            0,
            PROFILE_RINGS - 1,
        )
        upper_palette_ring := clamp(
            int(f32(ring + 1) * f32(PROFILE_RINGS - 1) / f32(max(ring_count - 1, 1)) + .5),
            0,
            PROFILE_RINGS - 1,
        )
        for segment in 0 ..< segment_count {
            next := (segment + 1) % segment_count
            // Paint soft ambient occlusion into the troughs between clumps and
            // a restrained warm lift onto their crests, per contour vertex, so
            // the grouped shade is anchored to the real mesh bulges instead of
            // a detached noise field. This is the crevice read that gives the
            // near canopy its rounded, hand-painted volume.
            lower_here := world_foliage_clump_color(lower_palette_ring, color_variation, clump_field[ring][segment])
            lower_next := world_foliage_clump_color(lower_palette_ring, color_variation, clump_field[ring][next])
            upper_here := world_foliage_clump_color(
                upper_palette_ring,
                color_variation,
                clump_field[ring + 1][segment],
            )
            upper_next := world_foliage_clump_color(upper_palette_ring, color_variation, clump_field[ring + 1][next])
            world_triangle_foliage(
                vertices[ring][segment],
                vertices[ring + 1][segment],
                vertices[ring + 1][next],
                lower_here,
                upper_here,
                upper_next,
                normals[ring][segment],
                normals[ring + 1][segment],
                normals[ring + 1][next],
            )
            world_triangle_foliage(
                vertices[ring][segment],
                vertices[ring + 1][next],
                vertices[ring][next],
                lower_here,
                upper_next,
                lower_next,
                normals[ring][segment],
                normals[ring + 1][next],
                normals[ring][next],
            )
        }
    }

    crown_x, crown_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        local_center_x + profile_width * f32(math.sin(f64(f32(variation) * 2.3))) * .035,
        local_center_z + profile_depth * f32(math.cos(f64(f32(variation) * 1.7))) * .035,
        structure.rotation,
    )
    crown_fraction := crown_base + f32(math.sin(f64(f32(structure.seed) * .005 + f32(variation) * 1.61))) * .035
    crown := third_person.Vec3{crown_x, structure.base_y + base_lift + profile_height * crown_fraction, crown_z}
    for segment in 0 ..< segment_count {
        next := (segment + 1) % segment_count
        world_triangle_foliage(
            vertices[ring_count - 1][segment],
            crown,
            vertices[ring_count - 1][next],
            world_foliage_clump_color(PROFILE_RINGS - 1, color_variation, clump_field[ring_count - 1][segment]),
            world_foliage_vertex_color(PROFILE_RINGS - 1, color_variation),
            world_foliage_clump_color(PROFILE_RINGS - 1, color_variation, clump_field[ring_count - 1][next]),
            normals[ring_count - 1][segment],
            {0, 1, 0},
            normals[ring_count - 1][next],
        )
    }

    // The atlas is primarily a silhouette accent. Perimeter boughs carry the
    // large sprays; clipped hedges also receive a few much smaller translucent
    // face clusters below so their long front plane does not stay textureless.
    if emit_outline {
        local_x := local_center_x + math.cos(outline_angle) * profile_width * .64
        local_z := local_center_z + math.sin(outline_angle) * profile_depth * .64
        card_x, card_z := world_rotate_xz(structure.center_x, structure.center_z, local_x, local_z, structure.rotation)
        focal_length := f32(1.35)
        if world_renderer.editor.in_map && driving_aircraft(world_renderer.editor) {
            focal_length = world_renderer.editor.flight_camera.focal_length
        }
        camera := perspective_camera(world_renderer.editor.camera_pose, focal_length)
        to_camera_x := camera.position.x - card_x
        to_camera_z := camera.position.z - card_z
        to_camera_length := max(f32(.001), f32(math.sqrt(f64(to_camera_x * to_camera_x + to_camera_z * to_camera_z))))
        outward_angle := outline_angle + structure.rotation
        view_alignment := math.abs(
            math.cos(outward_angle) * to_camera_x / to_camera_length +
            math.sin(outward_angle) * to_camera_z / to_camera_length,
        )

        // Only side-on perimeter boughs break the screen-space silhouette.
        // Front-facing billboards would lie across the crown and read as giant
        // flat polygons when the camera approaches tree height. The near band
        // is now admitted -- down to a few crown radii away -- so walking-height
        // and understory views gain a soft leafy contour instead of the bare
        // triangulated mesh edge. It stays side-on and is eased in very small,
        // so the sprig sits on the silhouette rather than sheeting across it,
        // and because only nearby lobes qualify the card budget stays bounded
        // (overview forest and stress scenes keep the existing far-only path).
        if view_alignment < .68 && to_camera_length > 34 {
            card_scale_factor := f32(.255 + f32(variation % 3) * .018)
            if is_hedge do card_scale_factor = .225 + f32(variation % 3) * .016
            if !is_hedge && base_lift <= 0 {
                card_scale_factor = .292 + f32(variation % 3) * .018
            }
            // Cards ease in small near the camera as leafy contour nicks, reach
            // full silhouette-breaking size by mid distance, and hold there.
            near_mix := clamp((to_camera_length - 34) / 78, 0, 1)
            far_mix := clamp((to_camera_length - 112) / 82, 0, 1)
            distance_scale := .52 + near_mix * .24 + far_mix * .24
            card_scale := card_scale_factor * max(profile_width, profile_depth)
            card_scale *= distance_scale
            card_y := structure.base_y + base_lift + profile_height * (.51 + f32(variation % 3) * .032)
            world_foliage_card(
                {card_x, card_y, card_z},
                card_scale,
                card_scale * .82,
                variation * 5 + 7,
                world_foliage_vertex_color(3, color_variation),
                (variation + int(structure.seed)) % 2 == 0,
            )

            // A smaller offset spray turns the single cutout into an uneven
            // leafy bunch. Offset both outward and along the contour so the
            // pair overlaps near its branch bases but separates at the tips,
            // breaking the parent mesh silhouette at two different scales.
            tangent_x, tangent_z := -math.sin(outward_angle), math.cos(outward_angle)
            echo_side := (variation + int(structure.seed)) % 2 == 0 ? f32(1) : f32(-1)
            echo_x := card_x + math.cos(outward_angle) * card_scale * .10 + tangent_x * card_scale * .17 * echo_side
            echo_z := card_z + math.sin(outward_angle) * card_scale * .10 + tangent_z * card_scale * .17 * echo_side
            echo_scale := card_scale * (.63 + f32(variation % 2) * .055)
            world_foliage_card(
                {echo_x, card_y + card_scale * (.09 + f32(variation % 3) * .018), echo_z},
                echo_scale,
                echo_scale * .88,
                variation * 7 + 3,
                world_foliage_vertex_color(2, color_variation + 1),
                (variation + int(structure.seed)) % 2 != 0,
            )

            // Alternating mature-forest boughs receive one inverted lower
            // spray. Its branch base stays buried in the dark shelf while the
            // painted tips trail below, breaking the long canopy-ceiling edge
            // without filling the open understory with billboard cards.
            hanging_selected := base_lift > 0 && to_camera_length > 76
            if hanging_selected {
                hanging_scale := card_scale * (.57 + f32(variation % 3) * .028)
                hanging_side := variation % 2 == 0 ? f32(1) : f32(-1)
                hanging_x :=
                    card_x + math.cos(outward_angle) * card_scale * .055 + tangent_x * card_scale * .11 * hanging_side
                hanging_z :=
                    card_z + math.sin(outward_angle) * card_scale * .055 + tangent_z * card_scale * .11 * hanging_side
                world_foliage_card(
                    {
                        hanging_x,
                        structure.base_y + base_lift + profile_height * (.175 + f32(variation % 2) * .026),
                        hanging_z,
                    },
                    hanging_scale,
                    hanging_scale * 1.18,
                    variation * 11 + 5,
                    world_foliage_vertex_color(2, color_variation),
                    hanging_side < 0,
                    true,
                )
            }
        }

        hedge_face_selected :=
            is_hedge && to_camera_length > 72 && to_camera_length < 430 && (variation + int(structure.seed)) % 2 == 0
        if hedge_face_selected {
            // Push the accent onto the camera-facing shoulder so depth testing
            // attaches it to the solid crown instead of hiding it inside the
            // lobe. Partial opacity and alternating placement keep these as
            // broken leaf suggestions rather than a repeated decal strip.
            face_offset := min(profile_width, profile_depth) * .47
            face_x := lobe_world_x + to_camera_x / to_camera_length * face_offset
            face_z := lobe_world_z + to_camera_z / to_camera_length * face_offset
            face_scale := min(profile_width, profile_depth) * (.235 + f32(variation % 3) * .016)
            face_tint := world_foliage_vertex_color(3, color_variation)
            face_tint.a = 198
            world_foliage_card(
                {face_x, structure.base_y + profile_height * (.49 + f32(variation % 3) * .045), face_z},
                face_scale,
                face_scale * .78,
                variation * 13 + 9,
                face_tint,
                (variation + int(structure.seed)) % 4 == 0,
            )
        }

        bush_face_selected :=
            !is_hedge &&
            base_lift <= 0 &&
            to_camera_length > 78 &&
            to_camera_length < 430 &&
            (variation + int(structure.seed)) % 3 != 0
        if bush_face_selected {
            // Standalone bushes can carry a little more leaf-scale surface
            // rhythm than distant forest masses. Keep the accents small and
            // translucent so several read as one painted bunch, not stickers.
            face_offset := min(profile_width, profile_depth) * .46
            face_x := lobe_world_x + to_camera_x / to_camera_length * face_offset
            face_z := lobe_world_z + to_camera_z / to_camera_length * face_offset
            face_scale := min(profile_width, profile_depth) * (.19 + f32(variation % 3) * .014)
            face_tint := world_foliage_vertex_color(3, color_variation)
            face_tint.a = 186
            world_foliage_card(
                {face_x, structure.base_y + profile_height * (.50 + f32(variation % 3) * .042), face_z},
                face_scale,
                face_scale * .84,
                variation * 17 + 1,
                face_tint,
                (variation + int(structure.seed)) % 2 == 0,
            )
        }
    }
}

world_foliage_formation :: proc(structure: terrain.Structure) {
    width := max(structure.width, terrain.BASE_CELL_SIZE)
    depth := max(structure.depth, terrain.BASE_CELL_SIZE)
    wide, narrow := max(width, depth), min(width, depth)
    aspect := wide / max(narrow, f32(.01))
    is_forest := aspect < 1.8 && wide >= 105 && structure.height >= 58
    // Keep forest patches dense by filling their area with tree-scale trees,
    // rather than stretching a handful of crowns across the footprint.
    forest_tree_count := is_forest ? clamp(int(width * depth / 460), 24, 36) : 0
    // A forest formation is a grove footprint, not one gigantic tree. Keep
    // the leaf ceiling around four character heights while individual crown
    // clusters supply the remaining tree height.
    canopy_lift := is_forest ? structure.height * .11 : f32(0)

    if is_forest {
        camera_position := world_renderer.editor.camera_pose.position
        camera_dx := camera_position.x - structure.center_x
        camera_dz := camera_position.z - structure.center_z
        formation_distance := f32(math.sqrt(f64(camera_dx * camera_dx + camera_dz * camera_dz)))
        walking_distance := formation_distance < 260
        dapple_count := 7
        for dapple in 0 ..< dapple_count {
            angle := f32(dapple) * 2.399963 + f32(structure.seed % 149) * .026
            radial := .12 + f32((dapple * 5 + 2) % 9) / 8 * .30
            local_x := math.cos(angle) * width * radial
            local_z := math.sin(angle) * depth * radial
            dapple_x, dapple_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            dapple_width := 13.0 + f32(dapple % 3) * 5.5
            dapple_depth := 9.5 + f32((dapple + 1) % 3) * 4.0
            dapple_rotation := angle * .47 + structure.rotation
            world_foliage_ground_dapple(
                dapple_x,
                dapple_z,
                structure.base_y,
                dapple_width,
                dapple_depth,
                dapple_rotation,
                structure.seed + u32(dapple * 1699),
            )
            // A smaller overlapping echo breaks the radial fan into a loose
            // painted pool. Offset it across the main ellipse rather than
            // scattering another isolated dot, so their shared center gains
            // light while the combined outer edge stays irregular and soft.
            echo_angle := dapple_rotation + 1.17 + f32(dapple % 2) * .41
            echo_x := dapple_x + math.cos(echo_angle) * dapple_width * .22
            echo_z := dapple_z + math.sin(echo_angle) * dapple_depth * .22
            world_foliage_ground_dapple(
                echo_x,
                echo_z,
                structure.base_y + .006,
                dapple_width * (.61 + f32(dapple % 2) * .07),
                dapple_depth * (.66 - f32(dapple % 2) * .05),
                dapple_rotation - .58,
                structure.seed + u32(dapple * 1699 + 947),
            )
        }

        understory_count := clamp(forest_tree_count * 2 / 3, 16, 24)
        if walking_distance {
            understory_count = clamp(forest_tree_count, 24, 32)
        }
        for tuft in 0 ..< understory_count {
            angle := f32(tuft) * 2.399963 + f32(structure.seed % 127) * .029
            radial := .28 + f32((tuft * 7) % 9) / 8 * .25
            local_x := math.cos(angle) * width * radial
            local_z := math.sin(angle) * depth * radial
            tuft_x, tuft_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            // Human-scale fern colonies: broad enough to read from the editor
            // camera, but roughly knee-to-chest high in third person.
            // Each placement represents an overlapping fern colony, not one
            // enormous plant: widen the fan while retaining human-scale
            // frond height so ground cover reads as painted patches.
            tuft_width := 2.05 + f32(tuft % 4) * .38
            tuft_height := 1.05 + f32((tuft + 2) % 5) * .22
            tuft_gesture := tuft % 4
            if tuft_gesture == 0 || tuft_gesture == 1 {
                // Broad, low fern fans are the dominant ground gesture. This
                // avoids a floor full of narrow conifer-like spikes while
                // preserving layered silhouettes between the trunks.
                tuft_width *= 1.28
                tuft_height *= .76
            } else if tuft_gesture == 3 {
                // Occasional upright clumps punctuate the fan rhythm without
                // becoming the default understory silhouette.
                tuft_width *= .90
                tuft_height *= 1.10
            }
            world_foliage_understory_tuft(
                tuft_x,
                tuft_z,
                structure.base_y,
                tuft_width,
                tuft_height,
                structure.seed + u32(tuft * 1301),
            )
        }

        // A quieter layer of low broadleaf rosettes bridges the empty ground
        // between fern fans. Their separate spiral and smaller radial range
        // produce loose colonies rather than a uniformly stamped carpet.
        ground_cover_count := clamp(forest_tree_count * 3 / 4, 18, 27)
        if walking_distance {
            ground_cover_count = clamp(forest_tree_count + 8, 30, 44)
        }
        for cover in 0 ..< ground_cover_count {
            angle := f32(cover) * 2.399963 + f32(structure.seed % 163) * .021 + .83
            radial := .09 + f32((cover * 5 + 3) % 11) / 10 * .41
            local_x := math.cos(angle) * width * radial
            local_z := math.sin(angle) * depth * radial
            cover_x, cover_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            cover_width := 1.25 + f32(cover % 4) * .28
            cover_height := .28 + f32((cover + 2) % 3) * .08
            world_foliage_ground_rosette(
                cover_x,
                cover_z,
                structure.base_y,
                cover_width,
                cover_height,
                structure.seed + u32(cover * 1877 + 431),
            )
        }

        // A low-discrepancy spiral makes a dense natural stand without rows.
        trunk_count := forest_tree_count
        for trunk in 0 ..< trunk_count {
            angle := f32(trunk) * 2.399963 + f32(structure.seed % 91) * .041
            radial := .06 + .43 * f32(math.sqrt(f64((f32(trunk) + .5) / f32(max(trunk_count, 1)))))
            local_x := math.cos(angle) * width * radial
            local_z := math.sin(angle) * depth * radial
            trunk_x, trunk_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            height_noise := .5 + .5 * f32(math.sin(f64(f32(structure.seed) * .013 + f32(trunk) * 1.73)))
            tree_canopy_lift := structure.height * (.075 + height_noise * .055)
            trunk_height := tree_canopy_lift + structure.height * (.040 + height_noise * .012)
            trunk_radius := max(
                f32(.42),
                min(width, depth) *
                (.0045 + (.5 + .5 * f32(math.sin(f64(f32(structure.seed) * .031 + f32(trunk) * 2.53)))) * .0025),
            )
            world_foliage_trunk(
                trunk_x,
                trunk_z,
                structure.base_y,
                trunk_height,
                trunk_radius,
                structure.seed + u32(trunk * 977),
            )
        }
    }

    if aspect >= 1.8 {
        // Long gestures become hedges. Shorter, more numerous crowns overlap
        // into a continuous mass while exposing a readable scalloped rhythm;
        // the earlier four very long lobes merged into smooth sausages.
        lobe_count := clamp(int(wide / max(narrow * 1.15, f32(1))) + 3, 4, 8)
        // A low recessed binder closes the dark gaps between crown beats. Most
        // of it remains concealed by the scallops, preserving one continuous
        // hedge gesture without returning to a single exposed sausage.
        binder_width, binder_depth := wide * .88, narrow * .76
        if depth > width do binder_width, binder_depth = binder_depth, binder_width
        world_foliage_lobe(structure, 0, 0, binder_width, binder_depth, structure.height * .44, 0, true, 19, 0, false)
        for lobe in 0 ..< lobe_count {
            fraction := (f32(lobe) + .5) / f32(lobe_count)
            along :=
                (fraction - .5) * wide * .82 +
                f32(math.sin(f64(f32(structure.seed) * .013 + f32(lobe) * 1.77))) * wide / f32(lobe_count) * .08
            cross := f32(math.sin(f64(f32(structure.seed) * .009 + f32(lobe) * 2.41))) * narrow * .12
            local_x, local_z := along, cross
            crown_scale := .90 + (.5 + .5 * f32(math.sin(f64(f32(structure.seed) * .027 + f32(lobe) * 1.87)))) * .20
            if lobe == int(structure.seed % u32(lobe_count)) do crown_scale *= 1.14
            lobe_width := max(wide / f32(lobe_count) * 1.72, narrow * 1.04) * crown_scale
            lobe_depth :=
                narrow *
                (.92 + f32(math.sin(f64(f32(structure.seed) * .021 + f32(lobe) * 1.31))) * .065) *
                (.96 + (crown_scale - 1) * .38)
            if depth > width {
                local_x, local_z = cross, along
                lobe_width, lobe_depth = lobe_depth, lobe_width
            }
            lobe_height :=
                structure.height *
                (.68 + f32(math.sin(f64(f32(structure.seed) * .017 + f32(lobe) * 1.63))) * .085) *
                (.95 + (crown_scale - 1) * .32)
            outward := f32(math.PI * .5)
            if depth > width do outward = 0
            if lobe % 2 != 0 do outward += math.PI
            world_foliage_lobe(
                structure,
                local_x,
                local_z,
                lobe_width,
                lobe_depth,
                lobe_height,
                0,
                true,
                lobe,
                outward,
                true,
            )
        }
        return
    }

    // Broad gestures become bushes or forest canopy patches. A deterministic
    // dominant crown and an opposing concave opening give each gesture a
    // composed silhouette instead of an evenly filled radial blob.
    lobe_count := clamp(int(wide / (terrain.BASE_CELL_SIZE * 1.5)) + 5, 5, 9)
    if is_forest do lobe_count = forest_tree_count
    outer_count := max(lobe_count - 1, 1)
    dominant_lobe := 1 + int(structure.seed % u32(outer_count))
    seed_phase := f32(structure.seed % 97) * .031
    dominant_angle := f32(dominant_lobe - 1) * 2.399963 + seed_phase
    opening_angle := dominant_angle + math.PI
    for lobe in 0 ..< lobe_count {
        local_x, local_z := f32(0), f32(0)
        radial := f32(0)
        angle := f32(0)
        opening_strength := f32(0)
        if lobe > 0 {
            angle = f32(lobe - 1) * 2.399963 + seed_phase
            radial = .18 + .27 * f32(math.sqrt(f64(f32(lobe) / f32(outer_count))))
            opening_delta := angle - opening_angle
            opening_distance := math.abs(math.atan2(math.sin(opening_delta), math.cos(opening_delta)))
            opening_strength = clamp(1 - opening_distance / .72, 0, 1)
            radial += opening_strength * .055
            if is_forest {
                // Forest positions are composed below from a shared tree
                // center plus one of three overlapping crown offsets. The
                // bush-specific concave opening must not shrink one crown in
                // every tree cluster.
                opening_strength = 0
            }
        }
        // The center only binds the patch together; it should not become one
        // dominant balloon. Mid-sized perimeter crowns now carry the canopy.
        scale := is_forest ? f32(.085) : f32(.59)
        if lobe > 0 {
            scale = .40 + (.5 + .5 * f32(math.sin(f64(f32(structure.seed) * .019 + f32(lobe) * 1.87)))) * .20
            if is_forest {
                scale = .075 + (.5 + .5 * f32(math.sin(f64(f32(structure.seed) * .019 + f32(lobe) * 1.87)))) * .035
            }
            scale *= 1 - opening_strength * .34
        }
        height_fraction := is_forest ? f32(.17) : f32(.80)
        if lobe > 0 {
            height_fraction = .62 + f32(math.sin(f64(f32(structure.seed) * .013 + f32(lobe) * 1.71))) * .15
            if is_forest {
                height_fraction = .15 + f32(math.sin(f64(f32(structure.seed) * .013 + f32(lobe) * 1.71))) * .028
            }
        }
        height_fraction *= 1 - opening_strength * .18
        if lobe == dominant_lobe {
            scale *= 1.16
            height_fraction *= 1.20
            radial *= .92
        }
        if lobe > 0 {
            if is_forest {
                // One irregular crown per trunk preserves density without
                // tripling the tessellation cost of every tree.
                tree_index := lobe
                tree_angle := f32(tree_index) * 2.399963 + f32(structure.seed % 91) * .041
                tree_radial := .06 + .43 * f32(math.sqrt(f64((f32(tree_index) + .5) / f32(max(forest_tree_count, 1)))))
                local_x = math.cos(tree_angle) * width * tree_radial
                local_z = math.sin(tree_angle) * depth * tree_radial
                angle = math.atan2(local_z / depth, local_x / width)
            } else {
                local_x = math.cos(angle) * width * radial
                local_z = math.sin(angle) * depth * radial
            }
        } else if is_forest {
            tree_angle := f32(structure.seed % 91) * .041
            tree_radial := .06 + .43 * f32(math.sqrt(f64(.5 / f32(max(forest_tree_count, 1)))))
            local_x = math.cos(tree_angle) * width * tree_radial
            local_z = math.sin(tree_angle) * depth * tree_radial
            angle = math.atan2(local_z / depth, local_x / width)
            scale = .075 + (.5 + .5 * f32(math.sin(f64(f32(structure.seed) * .019)))) * .035
            height_fraction = .15 + f32(math.sin(f64(f32(structure.seed) * .013))) * .028
        }
        lobe_height := structure.height * height_fraction
        outward := f32(0)
        if lobe > 0 do outward = math.atan2(local_z / depth, local_x / width)
        lobe_base_lift := canopy_lift
        if is_forest {
            // Layer saplings, middle crowns, and mature trees into one dense
            // stand. The matching expression in the trunk pass keeps every
            // crown attached to its own trunk.
            height_noise := .5 + .5 * f32(math.sin(f64(f32(structure.seed) * .013 + f32(lobe) * 1.73)))
            lobe_base_lift = structure.height * (.075 + height_noise * .055)
            lobe_height *= .82 + height_noise * .30
        }
        lobe_width, lobe_depth := width * scale, depth * scale
        lobe_structure := structure
        if is_forest {
            // A tree crown has its own dimensions; it must not inherit the
            // aspect ratio of the authored forest footprint. Per-tree seed
            // variation also mixes crown profiles and green families across
            // the stand instead of tinting the whole patch as one species.
            crown_noise := .5 + .5 * f32(math.sin(f64(f32(structure.seed) * .029 + f32(lobe) * 2.17)))
            crown_span := structure.height * (.17 + crown_noise * .075)
            crown_aspect := .84 + (.5 + .5 * f32(math.sin(f64(f32(structure.seed) * .041 + f32(lobe) * 1.31)))) * .34
            lobe_width = crown_span * crown_aspect
            lobe_depth = crown_span / crown_aspect
            lobe_structure.seed += u32(lobe * 977)
        }
        world_foliage_lobe(
            lobe_structure,
            local_x,
            local_z,
            lobe_width,
            lobe_depth,
            lobe_height,
            lobe_base_lift,
            false,
            lobe,
            outward,
            lobe > 0,
        )
    }
}

world_formation_top_fraction :: proc(structure: terrain.Structure, local_x, local_z: f32) -> f32 {
    if structure.kind == .Cliff {
        // Cliff tops follow the same segmented, lightly broken profile as the
        // rendered cliff mesh.
        segment := (local_x / max(structure.width, f32(.01)) + .5) * 6
        return .84 + f32(math.sin(f64(f32(structure.seed) * .001 + segment * 1.73))) * .055
    }
    // Ridge foliage sits on the radial ridge profile, not on a flat height
    // fraction. This keeps bushes on the shoulder from hovering in the air.
    radius_x := local_x / max(structure.width * .5, f32(.01))
    radius_z := local_z / max(structure.depth * .5 * .42, f32(.01))
    radius := f32(math.sqrt(f64(radius_x * radius_x + radius_z * radius_z)))
    if radius >= .92 do return clamp((1 - radius) / .08 * .22, 0, .22)
    if radius >= .60 do return .22 + (.92 - radius) / .32 * .28
    if radius >= .14 do return .50 + (.60 - radius) / .46 * .28
    return .78 + (.14 - radius) / .14 * .12
}

world_foliage_tufts :: proc(structure: terrain.Structure) {
    tuft_count := clamp(int(structure.width / 14), 4, 20)
    for tuft in 0 ..< tuft_count {
        fraction := (f32(tuft) + .5) / f32(tuft_count)
        jitter := f32(math.sin(f64(f32(structure.seed) * .013 + f32(tuft) * 2.41)))
        local_x := (fraction - .5) * structure.width + jitter * min(structure.width * .08, 3)
        local_z := f32(math.sin(f64(f32(structure.seed) * .007 + f32(tuft) * 1.73))) * structure.depth * .24
        base_y := structure.base_y + structure.height * world_formation_top_fraction(structure, local_x, local_z)
        bush_width := clamp(structure.depth * .50, 1.8, 10.0)
        bush_depth := clamp(structure.depth * .38, 1.3, 7.0)
        bush_height := clamp(structure.height * (.22 + f32(tuft % 3) * .035), 2.5, 10.0)
        // Cliff and ridge tufts now share the canopy palette, foliage normals,
        // and painterly lighting so a rocky shoulder reads with the same
        // rounded, warm-crowned Ghibli bushes as the lowland crowns. The vertex
        // count is unchanged from the former flat mound: six-sided shoulder and
        // crown rings plus a cap and one taller blade.
        variation := int((structure.seed + u32(tuft)) % 4)
        bottom: [6]third_person.Vec3
        top: [6]third_person.Vec3
        bottom_normal: [6]third_person.Vec3
        top_normal: [6]third_person.Vec3
        clump: [6]f32
        for segment in 0 ..< 6 {
            angle := f32(segment) * math.PI * 2 / 6
            // One rounded lobe wave per tuft carves the shoulder into a few
            // soft bunches and drives the same crevice shading as the crowns.
            lobe_wave := f32(math.sin(f64(f32(structure.seed) * .017 + f32(tuft) * 1.9 + angle * 2.0)))
            clump[segment] = lobe_wave
            jitter_scale := 1 + lobe_wave * .16
            local_bx := local_x + math.cos(angle) * bush_width * jitter_scale
            local_bz := local_z + math.sin(angle) * bush_depth * jitter_scale
            world_bx, world_bz := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_bx,
                local_bz,
                structure.rotation,
            )
            bottom[segment] = {world_bx, base_y, world_bz}
            // Keep the crown ring broad and let the crest lift it so the mound
            // domes into a rounded bush instead of tapering toward a cone.
            top_scale := .70 + lobe_wave * .06
            world_tx, world_tz := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x + math.cos(angle) * bush_width * top_scale,
                local_z + math.sin(angle) * bush_depth * top_scale,
                structure.rotation,
            )
            top[segment] = {world_tx, base_y + bush_height * (.60 + lobe_wave * .06), world_tz}
            nx, nz := math.cos(angle), math.sin(angle)
            // A near-horizontal shoulder normal keeps the base anchored (the
            // canopy wind weight rides normal.y), while the crown ring faces up.
            bottom_normal[segment] = vec_normalize({nx, .06, nz})
            top_normal[segment] = vec_normalize({nx * .62, 1.0, nz * .62})
        }
        for segment in 0 ..< 6 {
            next := (segment + 1) % 6
            lower_here := world_foliage_clump_color(1, variation, clump[segment])
            lower_next := world_foliage_clump_color(1, variation, clump[next])
            upper_here := world_foliage_clump_color(4, variation, clump[segment])
            upper_next := world_foliage_clump_color(4, variation, clump[next])
            world_triangle_foliage(
                bottom[segment],
                bottom[next],
                top[next],
                lower_here,
                lower_next,
                upper_next,
                bottom_normal[segment],
                bottom_normal[next],
                top_normal[next],
            )
            world_triangle_foliage(
                bottom[segment],
                top[next],
                top[segment],
                lower_here,
                upper_next,
                upper_here,
                bottom_normal[segment],
                top_normal[next],
                top_normal[segment],
            )
        }
        bush_cap := third_person.Vec3{0, base_y + bush_height, 0}
        bush_cap.x, bush_cap.z = world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x,
            local_z,
            structure.rotation,
        )
        cap_color := world_foliage_vertex_color(6, variation)
        for segment in 0 ..< 6 {
            next := (segment + 1) % 6
            world_triangle_foliage(
                top[segment],
                bush_cap,
                top[next],
                world_foliage_clump_color(5, variation, clump[segment]),
                cap_color,
                world_foliage_clump_color(5, variation, clump[next]),
                top_normal[segment],
                {0, 1, 0},
                top_normal[next],
            )
        }

        // A few taller blades break up the mound silhouette and keep the foliage
        // readable when the formation is viewed from far away.
        blade_width := clamp(structure.depth * .18, .45, 2.6)
        blade_height := clamp(structure.height * (.16 + f32(tuft % 3) * .035), 1.5, 6.5)
        left_x, left_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x - blade_width,
            local_z,
            structure.rotation,
        )
        right_x, right_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x + blade_width,
            local_z,
            structure.rotation,
        )
        tip_x, tip_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x + jitter * blade_width * .5,
            local_z,
            structure.rotation,
        )
        base_left := third_person.Vec3{left_x, base_y, left_z}
        base_right := third_person.Vec3{right_x, base_y, right_z}
        tip := third_person.Vec3{tip_x, base_y + blade_height, tip_z}
        blade_base := world_foliage_vertex_color(2, variation)
        blade_tip := world_foliage_vertex_color(5, variation)
        blade_base_normal := vec_normalize({0, .25, -1})
        blade_front_normal := vec_normalize({0, .25, 1})
        world_triangle_foliage(
            base_left,
            tip,
            base_right,
            blade_base,
            blade_tip,
            blade_base,
            blade_base_normal,
            {0, 1, 0},
            blade_front_normal,
        )
    }
}

world_architecture_cypress :: proc(x, z, base_y: f32, seed: u32) {
    tree := terrain.structure_make(x, z, 6.5, 6.5, base_y, 21)
    tree.seed = seed
    tree.color = {45, 93, 59, 255}
    world_box_rotated({x, base_y + 2.0, z}, {1.0, 4.0, 1.0}, 0, {108, 78, 48, 255})
    world_radial_formation(tree, {1, .68, .36, .08}, {0, .28, .58, .92}, .90, 1)
}

world_architecture_streets :: proc(editor: ^Editor, sun_direction: [3]f32, cloud_cover: f32) {
    if editor == nil || !editor.architecture_node_mode do return
    min_x, max_x := f32(1e9), f32(-1e9)
    min_z, max_z := f32(1e9), f32(-1e9)
    buildings := 0
    for structure in editor.project.structures[:editor.project.structure_count] {
        if structure.kind != .Architecture || structure.height > 60 do continue
        min_x = min(min_x, structure.center_x)
        max_x = max(max_x, structure.center_x)
        min_z = min(min_z, structure.center_z)
        max_z = max(max_z, structure.center_z)
        buildings += 1
    }
    if buildings < 4 || max_z <= min_z do return
    center_x := (min_x + max_x) * .5
    center_z := (min_z + max_z) * .5
    road_span := max(max_x - min_x + 36, 160)
    base_y := terrain.sample_height(&editor.project, 0, center_x, center_z)
    road := rl.Color{117, 119, 110, 255}
    shoulder := rl.Color{177, 164, 135, 255}
    for lane in 1 ..= 2 {
        lane_z := min_z + (max_z - min_z) * f32(lane) / 3
        world_box_rotated({center_x, base_y + .06, lane_z}, {road_span, .12, 5.5}, 0, road)
        for side in -1 ..= 1 {
            if side == 0 do continue
            world_box_rotated({center_x, base_y + .13, lane_z + f32(side) * 3.05}, {road_span, .05, .35}, 0, shoulder)
        }
    }
    world_box_rotated({center_x, base_y + .08, center_z}, {28, .16, 18}, 0, {151, 144, 126, 255})
    // Connect each frontage to the nearer lane so the generated streets read
    // as a walkable town rather than two unrelated strips of pavement.
    path_color := rl.Color{194, 184, 157, 255}
    for structure in editor.project.structures[:editor.project.structure_count] {
        if structure.kind != .Architecture || structure.height > 60 do continue
        lane_a := min_z + (max_z - min_z) / 3
        lane_b := min_z + (max_z - min_z) * 2 / 3
        door_x, door_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .22,
            structure.rotation,
        )
        front_x := -math.sin(structure.rotation)
        front_z := math.cos(structure.rotation)
        target_lane := f32(1e9)
        target_distance := f32(1e9)
        lanes := [2]f32{lane_a, lane_b}
        for candidate in lanes {
            candidate_dx := center_x - door_x
            candidate_dz := candidate - door_z
            // Only choose a lane in front of the actual entrance; a path to
            // the opposite side would tunnel through the generated building.
            if candidate_dx * front_x + candidate_dz * front_z < 0 do continue
            candidate_distance := candidate_dx * candidate_dx + candidate_dz * candidate_dz
            if candidate_distance < target_distance {
                target_lane = candidate
                target_distance = candidate_distance
            }
        }
        if target_distance >= 1e9 do continue
        lane_direction := target_lane >= door_z ? f32(1) : f32(-1)
        target_z := target_lane - lane_direction * 3.0
        path_dx := center_x - door_x
        path_dz := target_z - door_z
        path_length := f32(math.sqrt(f64(path_dx * path_dx + path_dz * path_dz)))
        if path_length <= 1.5 do continue
        path_center_x := (door_x + center_x) * .5
        path_center_z := (door_z + target_z) * .5
        path_y := terrain.sample_height(&editor.project, 0, path_center_x, path_center_z)
        world_box_rotated(
            {path_center_x, path_y + .08, path_center_z},
            {3.2, .12, path_length},
            math.atan2(path_dx, path_dz),
            path_color,
        )
    }
    // Cypress accents mark the two lane intersections and give the graph town
    // a readable Mediterranean scale cue without changing terrain data.
    for x_side in -1 ..= 1 {
        if x_side == 0 do continue
        for z_side in -1 ..= 1 {
            if z_side == 0 do continue
            tree_x := center_x + f32(x_side) * road_span * .42
            tree_z := center_z + f32(z_side) * ((max_z - min_z) * .5 + 7)
            tree_base := terrain.sample_height(&editor.project, 0, tree_x, tree_z)
            world_architecture_cypress(
                tree_x,
                tree_z,
                tree_base,
                u32((x_side + 2) * 37 + (z_side + 2) * 11 + buildings * 5),
            )
            tree := terrain.structure_make(tree_x, tree_z, 6.5, 6.5, tree_base, 21)
            world_structure_shadow(tree, sun_direction, cloud_cover, &editor.project)
        }
    }
}

world_structures :: proc(editor: ^Editor) {
    if editor == nil do return
    sky := atmosphere.sample(&editor.atmosphere)
    world_architecture_streets(editor, sky.sun_direction, sky.weather.cloud_cover)
    hovered_index := -1
    if editor.tool == .Structure &&
       !editor.road_mode &&
       editor.cursor_hit &&
       !editor.structure_placing &&
       !editor.structure_moving {
        hovered_index = terrain.structure_index_at(&editor.project, editor.cursor_world_x, editor.cursor_world_z)
    }
    for index in 0 ..< editor.project.structure_count {
        structure := editor.project.structures[index]
        if editor.architecture_painting &&
           structure.kind == .Architecture &&
           architecture.city_bounds_contains(
               architecture.city_bounds_expand(editor.architecture_dirty_bounds, 48),
               structure.center_x,
               structure.center_z,
           ) {
            continue
        }
        world_formation(structure)
        if index == editor.structure_selected && !editor.in_map && !editor.road_mode {
            world_structure_frame(structure, structure.base_y + structure.height, {244, 226, 122, 255})
        } else if index == hovered_index && !editor.in_map {
            world_structure_frame(structure, structure.base_y + structure.height + .02, {168, 239, 220, 255})
        }
    }
    if editor.structure_placing {
        world_structure_preview_cluster(editor)
    }
    world_curve_preview(editor)
    if editor.architecture_painting {
        for candidate in editor.architecture_preview_plan.structures[:editor.architecture_preview_plan.count] {
            preview := candidate
            preview.color = {168, 239, 220, 210}
            world_formation(preview)
            world_structure_frame(preview, preview.base_y + .05, {190, 255, 229, 210})
        }
    }
    world_greek_assets(editor)
}

world_city_density_overlay :: proc(editor: ^Editor) {
    if editor == nil || editor.in_map || !editor.architecture_paint_mode do return
    field := &editor.project.city_density
    if editor.architecture_painting do field = &editor.architecture_density_preview
    cell := terrain.BASE_CELL_SIZE
    half := f32(terrain.RING_RESOLUTION - 1) * .5
    // Reserve enough geometry for buildings and vehicles even when the whole
    // authored world has been painted.
    overlay_limit := WORLD_VERTEX_CAPACITY - 120_000
    for z in 0 ..< terrain.RING_RESOLUTION - 1 {
        for x in 0 ..< terrain.RING_RESOLUTION - 1 {
            density := f32(field[z * terrain.RING_RESOLUTION + x]) / 255
            if density <= .01 do continue
            if len(world_renderer.vertices) + 6 > overlay_limit do return
            x0, z0 := (f32(x) - half) * cell, (f32(z) - half) * cell
            x1, z1 := x0 + cell, z0 + cell
            lift := f32(.115)
            a := third_person.Vec3{x0, terrain.sample_height(&editor.project, 0, x0, z0) + lift, z0}
            b := third_person.Vec3{x1, terrain.sample_height(&editor.project, 0, x1, z0) + lift, z0}
            c := third_person.Vec3{x1, terrain.sample_height(&editor.project, 0, x1, z1) + lift, z1}
            d := third_person.Vec3{x0, terrain.sample_height(&editor.project, 0, x0, z1) + lift, z1}
            alpha := u8(28 + density * 112)
            world_quad(a, b, c, d, {22, 27, 31, alpha})
        }
    }
}

world_aircraft :: proc(editor: ^Editor) {
    sky := atmosphere.sample(&editor.atmosphere)
    if editor.postale_visible {
        mesh := vehicles.postale_mesh()
        vehicles.animate_postale_mesh(
            &mesh,
            editor.postale.flap_fraction,
            editor.flight_control.pitch,
            editor.flight_control.roll,
            editor.flight_control.yaw,
            editor.postale.propeller_turns,
        )
        for triangle in vehicles.mesh_triangles(&mesh) {
            world_vehicle_shadow_triangle(
                postale_vertex_world(&editor.postale, mesh.vertices[triangle.a].position, .68),
                postale_vertex_world(&editor.postale, mesh.vertices[triangle.b].position, .68),
                postale_vertex_world(&editor.postale, mesh.vertices[triangle.c].position, .68),
                sky.sun_direction,
                sky.weather.cloud_cover,
                &editor.project,
            )
        }
        for triangle in vehicles.mesh_triangles(&mesh) {
            a := mesh.vertices[triangle.a]
            b := mesh.vertices[triangle.b]
            c := mesh.vertices[triangle.c]
            world_triangle(
                postale_vertex_world(&editor.postale, a.position, .68),
                postale_vertex_world(&editor.postale, b.position, .68),
                postale_vertex_world(&editor.postale, c.position, .68),
                aircraft_part_color(a.part),
            )
        }
    }
    if editor.libellula_visible {
        vehicles.libellula_mesh_build(&editor.libellula_visual_mesh)
        libellula := &editor.libellula_visual_mesh
        vehicles.animate_libellula_mesh_pose(
            libellula,
            editor.libellula.rotor_turns.x,
            editor.libellula.rotor_turns.y,
            editor.libellula.rotor_turns.z,
            editor.libellula.pitch,
            editor.libellula.roll,
            0,
        )
        for triangle in vehicles.mesh_triangles(libellula) {
            world_vehicle_shadow_triangle(
                libellula_vertex_world(&editor.libellula, libellula.vertices[triangle.a].position, .72),
                libellula_vertex_world(&editor.libellula, libellula.vertices[triangle.b].position, .72),
                libellula_vertex_world(&editor.libellula, libellula.vertices[triangle.c].position, .72),
                sky.sun_direction,
                sky.weather.cloud_cover,
                &editor.project,
            )
        }
        for triangle in vehicles.mesh_triangles(libellula) {
            a := libellula.vertices[triangle.a]
            b := libellula.vertices[triangle.b]
            c := libellula.vertices[triangle.c]
            world_triangle(
                libellula_vertex_world(&editor.libellula, a.position, .72),
                libellula_vertex_world(&editor.libellula, b.position, .72),
                libellula_vertex_world(&editor.libellula, c.position, .72),
                aircraft_part_color(a.part),
            )
        }
    }
}

car_vertex_world :: proc(editor: ^Editor, position: [3]f32) -> third_person.Vec3 {
    origin := editor.car.position
    // The authored car faces local -Z. Apply restrained pitch and roll feedback
    // before rotating that axis onto the simulation's ground-plane heading.
    right, up, forward := position[0], position[1], -position[2]
    pitch_cos, pitch_sin := math.cos(editor.car_drive.body_pitch), math.sin(editor.car_drive.body_pitch)
    forward, up = forward * pitch_cos - up * pitch_sin, forward * pitch_sin + up * pitch_cos
    roll_cos, roll_sin := math.cos(editor.car_drive.body_roll), math.sin(editor.car_drive.body_roll)
    right, up = right * roll_cos - up * roll_sin, right * roll_sin + up * roll_cos
    heading_cos, heading_sin := math.cos(editor.car.yaw_radians), math.sin(editor.car.yaw_radians)
    return {
        x = origin.x + forward * heading_cos - right * heading_sin,
        y = origin.y + up,
        z = origin.z + forward * heading_sin + right * heading_cos,
    }
}

world_car :: proc(editor: ^Editor) {
    mesh := vehicles.simple_car_mesh()
    sky := atmosphere.sample(&editor.atmosphere)
    for triangle in vehicles.mesh_triangles(&mesh) {
        world_vehicle_shadow_triangle(
            car_vertex_world(editor, mesh.vertices[triangle.a].position),
            car_vertex_world(editor, mesh.vertices[triangle.b].position),
            car_vertex_world(editor, mesh.vertices[triangle.c].position),
            sky.sun_direction,
            sky.weather.cloud_cover,
            &editor.project,
        )
    }
    for triangle in vehicles.mesh_triangles(&mesh) {
        a := mesh.vertices[triangle.a]
        b := mesh.vertices[triangle.b]
        c := mesh.vertices[triangle.c]
        world_triangle(
            car_vertex_world(editor, a.position),
            car_vertex_world(editor, b.position),
            car_vertex_world(editor, c.position),
            aircraft_part_color(a.part),
        )
    }
}

player_animation_approach :: proc(current, target, rate, delta_seconds: f32) -> f32 {
    maximum_delta := max(rate, f32(.1)) * delta_seconds
    if current < target do return min(current + maximum_delta, target)
    return max(current - maximum_delta, target)
}

Mouse_Bone :: enum u8 {
    Pelvis,
    Spine,
    Chest,
    Neck,
    Head,
}

Mouse_Bone_Pose :: struct {
    parent:        i8,
    bind_position: third_person.Vec3,
    position:      third_person.Vec3,
    pitch:         f32,
    roll:          f32,
}

Mouse_Vertex_Group :: struct {
    bone:   Mouse_Bone,
    weight: f32,
}

Mouse_Skin_Vertex :: struct {
    bind_position: third_person.Vec3,
    groups:        [2]Mouse_Vertex_Group,
    color:         rl.Color,
}

mouse_skin_vertex :: proc(vertex: Mouse_Skin_Vertex, skeleton: ^[5]Mouse_Bone_Pose) -> third_person.Vec3 {
    skinned: third_person.Vec3
    weight_sum: f32
    for group in vertex.groups {
        if group.weight <= 0 do continue
        bone := skeleton[int(group.bone)]
        relative := third_person.Vec3 {
            vertex.bind_position.x - bone.bind_position.x,
            vertex.bind_position.y - bone.bind_position.y,
            vertex.bind_position.z - bone.bind_position.z,
        }
        pitch_cosine, pitch_sine := math.cos(bone.pitch), math.sin(bone.pitch)
        pitched_y := relative.y * pitch_cosine - relative.z * pitch_sine
        pitched_z := relative.y * pitch_sine + relative.z * pitch_cosine
        roll_cosine, roll_sine := math.cos(bone.roll), math.sin(bone.roll)
        transformed := third_person.Vec3 {
            bone.position.x + relative.x * roll_cosine - pitched_y * roll_sine,
            bone.position.y + relative.x * roll_sine + pitched_y * roll_cosine,
            bone.position.z + pitched_z,
        }
        skinned.x += transformed.x * group.weight
        skinned.y += transformed.y * group.weight
        skinned.z += transformed.z * group.weight
        weight_sum += group.weight
    }
    if weight_sum <= .0001 do return vertex.bind_position
    inverse_weight := 1 / weight_sum
    return {skinned.x * inverse_weight, skinned.y * inverse_weight, skinned.z * inverse_weight}
}

world_mouse_skinned_hull :: proc(
    origin: third_person.Vec3,
    rotation: f32,
    skeleton: ^[5]Mouse_Bone_Pose,
    fur, fur_light: rl.Color,
    breath: f32,
) {
    RINGS :: 10
    SEGMENTS :: 12
    ring_z := [RINGS]f32{-.78, -.70, -.52, -.28, -.04, .10, .20, .32, .47, .58}
    // A mouse's dorsal line is a soft arch over the pelvis and ribs, then
    // descends into the neck.  Keeping the belly locations nearly unchanged
    // while lifting and enlarging these middle rings avoids the flat-backed,
    // rectangular silhouette that the low running pose previously produced.
    ring_y := [RINGS]f32{.33, .37, .42, .47, .52, .59, .68, .64, .61, .62}
    radius_x := [RINGS]f32{.07, .19, .29, .30, .255, .205, .20, .17, .095, .025}
    radius_y := [RINGS]f32{.09, .22, .32, .35, .28, .21, .185, .125, .070, .022}
    primary := [RINGS]Mouse_Bone{.Pelvis, .Pelvis, .Pelvis, .Spine, .Chest, .Neck, .Head, .Head, .Head, .Head}
    secondary := [RINGS]Mouse_Bone{.Spine, .Spine, .Spine, .Pelvis, .Spine, .Chest, .Neck, .Neck, .Neck, .Neck}
    primary_weight := [RINGS]f32{.98, .92, .82, .76, .68, .66, .78, .88, .96, 1}

    vertices: [RINGS][SEGMENTS]Mouse_Skin_Vertex
    posed: [RINGS][SEGMENTS]third_person.Vec3
    rib_weights := [RINGS]f32{0, .02, .10, .55, 1, .45, 0, 0, 0, 0}
    for ring in 0 ..< RINGS {
        breath_scale := 1 + breath * rib_weights[ring]
        for segment in 0 ..< SEGMENTS {
            angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
            cosine, sine := math.cos(angle), math.sin(angle)
            belly_weight := clamp((-sine - .05) * .76, 0, .68)
            if ring >= 6 do belly_weight = max(belly_weight, f32(.48))
            dorsal_weight := clamp((sine - .10) * .30, 0, .27)
            if ring >= 6 do dorsal_weight *= .55
            coat_color := color_lerp(fur, fur_light, belly_weight)
            coat_color = color_lerp(coat_color, {91, 70, 57, 255}, dorsal_weight)
            vertices[ring][segment] = {
                bind_position = {
                    cosine * radius_x[ring] * breath_scale,
                    ring_y[ring] + sine * radius_y[ring] * breath_scale,
                    ring_z[ring],
                },
                groups        = {{primary[ring], primary_weight[ring]}, {secondary[ring], 1 - primary_weight[ring]}},
                color         = coat_color,
            }
            local := mouse_skin_vertex(vertices[ring][segment], skeleton)
            world_x, world_z := world_rotate_xz(origin.x, origin.z, local.x, local.z, rotation)
            posed[ring][segment] = {world_x, origin.y + local.y, world_z}
        }
    }

    for ring in 0 ..< RINGS - 1 {
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            a, b := posed[ring][segment], posed[ring][next]
            c, d := posed[ring + 1][next], posed[ring + 1][segment]
            world_triangle_colored(
                a,
                b,
                c,
                vertices[ring][segment].color,
                vertices[ring][next].color,
                vertices[ring + 1][next].color,
            )
            world_triangle_colored(
                a,
                c,
                d,
                vertices[ring][segment].color,
                vertices[ring + 1][next].color,
                vertices[ring + 1][segment].color,
            )
        }
    }

    rear_center_local := mouse_skin_vertex(
        {bind_position = {0, ring_y[0], ring_z[0]}, groups = {{.Pelvis, 1}, {.Spine, 0}}, color = fur},
        skeleton,
    )
    nose_center_local := mouse_skin_vertex(
        {
            bind_position = {0, ring_y[RINGS - 1], ring_z[RINGS - 1]},
            groups = {{.Head, 1}, {.Neck, 0}},
            color = fur_light,
        },
        skeleton,
    )
    rear_x, rear_z := world_rotate_xz(origin.x, origin.z, rear_center_local.x, rear_center_local.z, rotation)
    nose_x, nose_z := world_rotate_xz(origin.x, origin.z, nose_center_local.x, nose_center_local.z, rotation)
    rear_center := third_person.Vec3{rear_x, origin.y + rear_center_local.y, rear_z}
    nose_center := third_person.Vec3{nose_x, origin.y + nose_center_local.y, nose_z}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(rear_center, posed[0][next], posed[0][segment], fur)
        world_triangle(nose_center, posed[RINGS - 1][segment], posed[RINGS - 1][next], fur_light)
    }
}

mouse_ear_world_point :: proc(origin, center: third_person.Vec3, rotation, yaw, x, y, z: f32) -> third_person.Vec3 {
    cosine, sine := math.cos(yaw), math.sin(yaw)
    local_x := center.x + x * cosine + z * sine
    local_z := center.z - x * sine + z * cosine - y * .20
    world_x, world_z := world_rotate_xz(origin.x, origin.z, local_x, local_z, rotation)
    return {world_x, origin.y + center.y + y, world_z}
}

world_mouse_ear :: proc(
    origin: third_person.Vec3,
    rotation: f32,
    center: third_person.Vec3,
    side, twitch: f32,
    rim_color, inner_color: rl.Color,
) {
    SEGMENTS :: 16
    // Mouse pinnae face laterally.  A shallow yaw made them disappear into
    // edge-on slivers in the gameplay side view; this angle preserves their
    // broad oval silhouette while still separating the bilateral pair.
    yaw := side * (1.02 + twitch * 5)
    outer_back, outer_front, inner_rim: [SEGMENTS]third_person.Vec3
    for segment in 0 ..< SEGMENTS {
        angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
        cosine, sine := math.cos(angle), math.sin(angle)
        root_taper := .70 + .30 * clamp((sine + .55) / 1.55, 0, 1)
        outer_x := cosine * .101 * root_taper
        outer_y := sine * .108
        inner_x := cosine * .069 * root_taper
        inner_y := .006 + sine * .073
        outer_back[segment] = mouse_ear_world_point(origin, center, rotation, yaw, outer_x, outer_y, -.026)
        outer_front[segment] = mouse_ear_world_point(origin, center, rotation, yaw, outer_x, outer_y, .024)
        inner_rim[segment] = mouse_ear_world_point(origin, center, rotation, yaw, inner_x, inner_y, .030)
    }

    back_center := mouse_ear_world_point(origin, center, rotation, yaw, 0, 0, -.026)
    // Recessing the pink center behind its inner rim gives the pinna a shallow
    // bowl instead of reading as a sticker laid over a flat disc.
    cup_center := mouse_ear_world_point(origin, center, rotation, yaw, 0, .008, .002)
    // Thin mouse ears transmit some of their pink tone even from behind. This
    // keeps the far pinna recognizable instead of reducing it to a dark fur
    // bump when its cup faces away from the camera.
    back_color := color_lerp(rim_color, inner_color, .34)
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(back_center, outer_back[next], outer_back[segment], back_color)
        world_quad(outer_back[segment], outer_back[next], outer_front[next], outer_front[segment], rim_color)
        world_quad(outer_front[segment], outer_front[next], inner_rim[next], inner_rim[segment], rim_color)
        world_triangle(cup_center, inner_rim[segment], inner_rim[next], inner_color)
    }
}

player_animation_update :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil || delta_seconds <= 0 do return
    animation := &editor.tweak.player_animation
    horizontal_speed := f32(
        math.sqrt(
            f64(
                editor.player.velocity.x * editor.player.velocity.x +
                editor.player.velocity.z * editor.player.velocity.z,
            ),
        ),
    )
    gait_target := clamp(horizontal_speed / max(animation.walk_full_speed, f32(.1)), 0, 1)
    airborne_target := editor.player.grounded ? f32(0) : f32(1)
    vertical_target := f32(0)
    if !editor.player.grounded {
        vertical_target = clamp(editor.player.velocity.y / max(animation.vertical_full_speed, f32(.1)), -1, 1)
    }
    editor.player_gait_weight = player_animation_approach(
        editor.player_gait_weight,
        gait_target,
        animation.locomotion_blend_rate,
        delta_seconds,
    )
    editor.player_airborne_weight = player_animation_approach(
        editor.player_airborne_weight,
        airborne_target,
        animation.airborne_blend_rate,
        delta_seconds,
    )
    editor.player_vertical_pose = player_animation_approach(
        editor.player_vertical_pose,
        vertical_target,
        animation.vertical_blend_rate,
        delta_seconds,
    )
    editor.player_turn_pose = player_animation_approach(
        editor.player_turn_pose,
        editor.player.turn_amount,
        animation.turn_blend_rate,
        delta_seconds,
    )
    editor.player_brake_pose = player_animation_approach(
        editor.player_brake_pose,
        editor.player.brake_amount,
        animation.brake_blend_rate,
        delta_seconds,
    )
    if editor.player.grounded && horizontal_speed < .08 {
        editor.player_posted_idle_seconds += delta_seconds
    } else {
        editor.player_posted_idle_seconds = 0
    }
    posted_target := editor.player_posted_idle_seconds >= 2.75 ? f32(1) : f32(0)
    editor.player_posted_weight = player_animation_approach(
        editor.player_posted_weight,
        posted_target,
        2.6,
        delta_seconds,
    )
    if editor.player.grounded {
        editor.player_stride_phase +=
            horizontal_speed * delta_seconds * max(animation.stride_radians_per_meter, f32(.1))
        for editor.player_stride_phase >= math.PI * 2 do editor.player_stride_phase -= math.PI * 2
    }
}

mouse_surface_height :: proc(editor: ^Editor, x, z: f32) -> f32 {
    height := terrain.sample_height(&editor.project, 0, x, z)
    pavement := roads.pavement_at(&editor.project.road_graph, {x = x, y = height, z = z})
    if pavement.on_surface do height += .12
    return height
}

MOUSE_CONTACT_SKIN :: f32(.006)

mouse_ground_contact :: proc(
    editor: ^Editor,
    point: third_person.Vec3,
    half_height: f32,
    planted: bool,
) -> third_person.Vec3 {
    floor := mouse_surface_height(editor, point.x, point.z) + half_height + MOUSE_CONTACT_SKIN
    result := point
    result.y = planted ? floor : max(result.y, floor)
    return result
}

Mouse_Accessory :: enum {
    None,
    Goggles,
    Flower,
}

Mouse_Model :: struct {
    position:          third_person.Vec3,
    rotation:          f32,
    accessory:         Mouse_Accessory,
    player_controlled: bool,
    grounded:          bool,
}

world_mouse_model :: proc(editor: ^Editor, model: Mouse_Model) {
    p := model.position
    if model.grounded {
        raw_height := terrain.sample_height(&editor.project, 0, p.x, p.z)
        p.y += mouse_surface_height(editor, p.x, p.z) - raw_height
    }
    rotation := model.rotation
    local_point :: proc(origin: third_person.Vec3, rotation, x, y, z: f32) -> third_person.Vec3 {
        world_x, world_z := world_rotate_xz(origin.x, origin.z, x, z, rotation)
        return {world_x, origin.y + y, world_z}
    }

    fur: rl.Color = {132, 107, 84, 255}
    fur_dark: rl.Color = {91, 70, 57, 255}
    fur_light: rl.Color = {184, 164, 139, 255}
    ear: rl.Color = {188, 126, 123, 255}
    paw: rl.Color = {201, 146, 139, 255}
    features: rl.Color = {35, 32, 30, 255}
    nose: rl.Color = {161, 102, 101, 255}
    tooth: rl.Color = {232, 222, 189, 255}
    leather: rl.Color = {91, 55, 38, 255}
    leather_dark: rl.Color = {58, 38, 31, 255}
    brass: rl.Color = {204, 157, 72, 255}
    goggle_glass: rl.Color = {78, 157, 169, 255}
    model_forward := third_person.Vec3 {
        x = -math.sin(rotation),
        z = math.cos(rotation),
    }
    animation := &editor.tweak.player_animation
    turn_pose := model.player_controlled ? clamp(editor.player_turn_pose, -1, 1) : f32(0)
    brake_pose := model.player_controlled ? clamp(editor.player_brake_pose, 0, 1) : f32(0)
    if model.player_controlled && editor.capture_player_turn_left_pose do turn_pose = -1
    if model.player_controlled && editor.capture_player_turn_right_pose do turn_pose = 1
    if model.player_controlled && editor.capture_player_brake_pose do brake_pose = 1
    ground_normal := model.player_controlled ? editor.player.ground_normal : third_person.Vec3{y = 1}
    if ground_normal.y <= .1 do ground_normal = {
        y = 1,
    }
    model_right := third_person.Vec3 {
        x = math.cos(rotation),
        z = math.sin(rotation),
    }
    normal_forward := ground_normal.x * model_forward.x + ground_normal.z * model_forward.z
    normal_right := ground_normal.x * model_right.x + ground_normal.z * model_right.z
    slope_pitch := math.atan2(normal_forward, ground_normal.y) * animation.slope_alignment
    slope_roll := math.atan2(-normal_right, ground_normal.y) * animation.slope_alignment
    body_roll := slope_roll - turn_pose * animation.turn_lean_radians
    spine_side := turn_pose * animation.turn_spine_offset
    brake_compression := brake_pose * animation.brake_compression
    posted_weight := model.player_controlled ? clamp(editor.player_posted_weight, 0, 1) : f32(1)
    if model.player_controlled && editor.capture_player_posted_pose do posted_weight = 1

    airborne_weight := model.player_controlled ? editor.player_airborne_weight : f32(0)
    run_weight :=
        model.player_controlled ? editor.player_gait_weight * (1 - airborne_weight) + .88 * airborne_weight : f32(0)
    stride_phase := model.player_controlled ? editor.player_stride_phase : f32(0)
    if model.player_controlled && editor.capture_player_walk_pose {
        run_weight = 1
        stride_phase = math.PI * 1.75
    } else if model.player_controlled && editor.capture_player_run_compress_pose {
        run_weight = 1
        stride_phase = math.PI * .50
    } else if model.player_controlled &&
       (editor.capture_player_turn_left_pose || editor.capture_player_turn_right_pose) {
        run_weight = 1
        stride_phase = math.PI * 1.75
    } else if model.player_controlled && editor.capture_player_brake_pose {
        run_weight = 1
        stride_phase = math.PI * .50
    }
    vertical_pose := model.player_controlled ? editor.player_vertical_pose : f32(0)
    if model.player_controlled && (editor.capture_player_jump_pose || editor.capture_player_fall_pose) {
        airborne_weight = 1
        vertical_pose = clamp(
            editor.player.velocity.y / max(editor.tweak.player_animation.vertical_full_speed, f32(.1)),
            -1,
            1,
        )
    }
    jump_rise := vertical_pose * airborne_weight
    ascent_weight := max(jump_rise, f32(0))
    descent_weight := max(-jump_rise, f32(0))

    idle_phase := editor.map_time * 2.2
    bound := math.sin(stride_phase) * run_weight
    spine_extension := -bound
    body_bob :=
        (-bound * .018 + math.abs(math.sin(stride_phase * 2)) * .014) * run_weight +
        math.sin(idle_phase) * .006 * (1 - run_weight) +
        animation.run_body_lift * run_weight * (1 - airborne_weight)
    blink_period := f32(4.6)
    blink_time := editor.map_time - f32(math.floor(f64(editor.map_time / blink_period))) * blink_period
    blink_weight := clamp(1 - math.abs(blink_time - .10) / .10, 0, 1)
    if model.player_controlled && editor.capture_player_blink_pose do blink_weight = 1
    sniff := math.sin(editor.map_time * 5.4) * .008 * (1 - run_weight)
    breathing := math.sin(editor.map_time * 1.65) * .018 * (1 - run_weight) * (1 - airborne_weight)
    head_sway := math.sin(stride_phase) * .012 * run_weight
    ear_twitch := math.sin(idle_phase * 1.7) * .006 * (1 - run_weight) + math.abs(bound) * .008 + blink_weight * .009

    // One connected hull runs from rump to nose. Its rings carry named,
    // normalized vertex groups and are skinned by this five-bone mouse rig.
    head_y :=
        .57 -
        run_weight * .17 -
        spine_extension * .010 * run_weight +
        body_bob +
        airborne_weight * .015 -
        brake_compression * .72 +
        posted_weight * .27
    head_z := .02 + run_weight * .18 + spine_extension * .055 * run_weight - brake_pose * .025 - posted_weight * .035
    head_turn_x := spine_side * .24
    skeleton := [5]Mouse_Bone_Pose {
        {
            parent = -1,
            bind_position = {0, .40, -.48},
            position = {
                spine_side * .18,
                .36 - run_weight * .010 + body_bob - brake_compression * .48 - posted_weight * .015,
                -.48 - spine_extension * .035 * run_weight + brake_pose * .035,
            },
            pitch = bound * .035 + slope_pitch * .65 - posted_weight * .05,
            roll = body_roll * .82,
        },
        {
            parent = 0,
            bind_position = {0, .43, -.25},
            position = {
                spine_side * .48,
                .39 - run_weight * .035 + body_bob - brake_compression * .64 + posted_weight * .15,
                -.25 + spine_extension * .018 * run_weight + brake_pose * .025 - posted_weight * .035,
            },
            pitch = run_weight * .055 + bound * .045 + slope_pitch * .82 - posted_weight * .10,
            roll = body_roll,
        },
        {
            parent = 1,
            bind_position = {0, .50, -.04},
            position = {
                spine_side,
                .44 - run_weight * .085 + body_bob - brake_compression + posted_weight * .25,
                -.04 +
                run_weight * .06 +
                spine_extension * .040 * run_weight -
                brake_pose * .015 -
                posted_weight * .055,
            },
            pitch = run_weight * .075 + bound * .055 + slope_pitch - posted_weight * .14,
            roll = body_roll,
        },
        {
            parent = 2,
            bind_position = {0, .58, .10},
            position = {
                head_sway * .25 + spine_side * .62,
                .50 - run_weight * .135 + body_bob - brake_compression * .82 + posted_weight * .27,
                .10 + run_weight * .10 + spine_extension * .050 * run_weight - brake_pose * .02 - posted_weight * .055,
            },
            pitch = run_weight * .085 + bound * .035 + slope_pitch * .72 - posted_weight * .08,
            roll = body_roll * .58,
        },
        {
            parent = 3,
            bind_position = {0, .69, .20},
            position = {head_sway + head_turn_x, head_y, head_z + .20},
            pitch = run_weight * .055 - bound * .025 + slope_pitch * .42,
            roll = body_roll * .22,
        },
    }
    world_mouse_skinned_hull(p, rotation, &skeleton, fur, fur_light, breathing)

    ear_offsets := [2]f32{-.125, .125}
    for ear_x in ear_offsets {
        side := ear_x / .125
        side_motion := ear_twitch * side
        // Bilateral ears are rarely held in one perfectly coincident plane.
        // A small fore/aft stagger exposes the far pinna in profile, while the
        // low-frequency swivel keeps an alert posted mouse listening rather
        // than freezing both ears into a mirrored emblem.
        ear_swivel := math.sin(idle_phase * 1.18 + side * 1.05) * .010 * (1 - run_weight)
        ear_depth_stagger := side * .060 + ear_swivel
        ear_height_stagger := side < 0 ? f32(.045) : f32(-.005)
        world_mouse_ear(
            p,
            rotation,
            {
                ear_x + head_sway + head_turn_x,
                head_y +
                .145 +
                side_motion +
                ear_height_stagger -
                airborne_weight * .018 +
                ear_x * math.sin(body_roll) * .65,
                head_z + .045 + ear_depth_stagger - airborne_weight * .018,
            },
            side,
            side_motion,
            fur_dark,
            ear,
        )
    }

    muzzle_y := head_y - .045
    muzzle_z := head_z + .39 + sniff
    world_tapered_disc_depth_rotated(
        local_point(p, rotation, head_sway + head_turn_x, muzzle_y, muzzle_z + .19),
        .028,
        .022,
        .018,
        .015,
        .040,
        rotation,
        nose,
    )
    nostril_offsets := [2]f32{-.011, .011}
    for nostril_x in nostril_offsets {
        world_vertical_disc_rotated(
            local_point(p, rotation, nostril_x + head_sway + head_turn_x, muzzle_y + .003, muzzle_z + .213),
            .0045,
            .0035,
            .004,
            rotation,
            features,
        )
    }

    eye_offsets := [2]f32{-.18, .18}
    eye_radius_y := .004 + (1 - blink_weight) * .033
    for eye_x in eye_offsets {
        eye_side := eye_x / .18
        // Mouse eyes sit on the lateral skull, not on a forward-facing mask.
        // Cant each cornea toward its own side so the near eye remains the
        // dominant facial landmark in profile.
        eye_rotation := rotation - eye_side * (math.PI * .5)
        world_vertical_disc_rotated(
            local_point(
                p,
                rotation,
                eye_x + head_sway + head_turn_x,
                head_y + .018 + eye_x * math.sin(body_roll) * .32,
                head_z + .31,
            ),
            .030,
            eye_radius_y,
            .019,
            eye_rotation,
            features,
        )
        if blink_weight < .55 {
            // The catchlight belongs on the outward corneal cap. Offset it in
            // lateral-skull space rather than along model-forward, otherwise
            // a profile eye buries the highlight inside its own disc.
            world_box_rotated(
                local_point(
                    p,
                    rotation,
                    eye_x + eye_side * .035 + head_sway + head_turn_x,
                    head_y + .034 + eye_x * math.sin(body_roll) * .32,
                    head_z + .318,
                ),
                {.012 * (1 - blink_weight), .013 * (1 - blink_weight), .012 * (1 - blink_weight)},
                rotation,
                tooth,
            )
        }
    }

    if model.accessory == .Goggles {
        // The goggles rest above the eyes so the face stays expressive. Every
        // component follows head sway and the spine-driven running reach.
        goggle_y := head_y + .112
        goggle_z := head_z + .31
        goggle_roll_slope := math.sin(body_roll) * .32
        goggle_strap_left := local_point(
            p,
            rotation,
            -.25 + head_sway + head_turn_x,
            goggle_y - .25 * goggle_roll_slope,
            head_z + .285,
        )
        goggle_strap_right := local_point(
            p,
            rotation,
            .25 + head_sway + head_turn_x,
            goggle_y + .25 * goggle_roll_slope,
            head_z + .285,
        )
        world_box_between(goggle_strap_left, goggle_strap_right, model_forward, .032, .022, leather_dark)
        goggle_offsets := [2]f32{-.16, .16}
        for goggle_x in goggle_offsets {
            goggle_side := goggle_x / .16
            // The two cups follow the curved brow rather than sharing one
            // billboard plane. A restrained outward cant keeps the near lens
            // readable in profile while preserving their forward function.
            goggle_cant := f32(.85)
            goggle_rotation := rotation - goggle_side * goggle_cant
            goggle_normal_x := goggle_side * f32(math.sin(f64(goggle_cant)))
            goggle_normal_z := f32(math.cos(f64(goggle_cant)))
            world_vertical_disc_rotated(
                local_point(
                    p,
                    rotation,
                    goggle_x + head_sway + head_turn_x,
                    goggle_y + goggle_x * goggle_roll_slope,
                    goggle_z,
                ),
                .057,
                .047,
                .026,
                goggle_rotation,
                leather,
            )
            world_vertical_disc_rotated(
                local_point(
                    p,
                    rotation,
                    goggle_x + goggle_normal_x * .020 + head_sway + head_turn_x,
                    goggle_y + goggle_x * goggle_roll_slope,
                    goggle_z + goggle_normal_z * .020,
                ),
                .040,
                .031,
                .012,
                goggle_rotation,
                goggle_glass,
            )
            world_vertical_disc_rotated(
                local_point(
                    p,
                    rotation,
                    goggle_x + goggle_normal_x * .030 - goggle_side * .009 + head_sway + head_turn_x,
                    goggle_y + .010 + goggle_x * goggle_roll_slope,
                    goggle_z + goggle_normal_z * .030,
                ),
                .008,
                .008,
                .005,
                goggle_rotation,
                tooth,
            )

            // Curved side shields keep the headset identifiable when the
            // camera reaches a true profile. They share the cup's material and
            // glass, so this reads as wraparound goggles rather than a badge.
            side_window_rotation := rotation - goggle_side * (math.PI * .5)
            side_window_x := goggle_x + goggle_side * .045 + head_sway + head_turn_x
            side_window_y := goggle_y + goggle_x * goggle_roll_slope
            side_window_z := goggle_z - .008
            world_vertical_disc_rotated(
                local_point(p, rotation, side_window_x, side_window_y, side_window_z),
                .030,
                .025,
                .010,
                side_window_rotation,
                leather,
            )
            world_vertical_disc_rotated(
                local_point(p, rotation, side_window_x + goggle_side * .010, side_window_y, side_window_z),
                .021,
                .017,
                .006,
                side_window_rotation,
                goggle_glass,
            )
        }
        bridge_left := local_point(
            p,
            rotation,
            -.083 + head_sway + head_turn_x,
            goggle_y - .083 * goggle_roll_slope,
            goggle_z + .015,
        )
        bridge_right := local_point(
            p,
            rotation,
            .083 + head_sway + head_turn_x,
            goggle_y + .083 * goggle_roll_slope,
            goggle_z + .015,
        )
        world_box_between(bridge_left, bridge_right, model_forward, .018, .018, brass)
        // Side straps keep the goggles legible in profile and describe how the
        // frames actually wrap around the skull instead of hovering over it.
        strap_sides := [2]f32{-1, 1}
        for strap_side in strap_sides {
            strap_front := local_point(
                p,
                rotation,
                strap_side * .195 + head_sway + head_turn_x,
                goggle_y - .004,
                goggle_z - .018,
            )
            strap_crown := local_point(
                p,
                rotation,
                strap_side * .21 + head_sway + head_turn_x,
                head_y + .105,
                head_z + .17,
            )
            strap_back := local_point(
                p,
                rotation,
                strap_side * .18 + head_sway + head_turn_x,
                head_y + .065,
                head_z - .015,
            )
            world_box_between(strap_front, strap_crown, model_forward, .018, .012, leather_dark)
            world_box_between(strap_crown, strap_back, model_forward, .018, .012, leather_dark)
        }
    } else if model.accessory == .Flower {
        // Keep the flower tucked beside the left ear, but cant the whole bloom
        // outward so its petal plane clears the head instead of cutting
        // through it.
        flower_center_x := -.115 + head_sway + head_turn_x
        flower_center_y := head_y + .205
        flower_center_z := head_z + .095
        flower_cant := f32(.95)
        flower_yaw := rotation + flower_cant
        flower_plane_x := math.cos(flower_cant)
        flower_plane_z := math.sin(flower_cant)
        stem_bottom := local_point(p, rotation, flower_center_x + .045, head_y + .105, flower_center_z - .025)
        stem_top := local_point(p, rotation, flower_center_x, flower_center_y, flower_center_z)
        world_box_between(stem_bottom, stem_top, model_forward, .018, .012, {70, 123, 72, 255})
        petal_color: rl.Color = {238, 111, 137, 255}
        for petal_index in 0 ..< 5 {
            petal_angle := f32(petal_index) * math.PI * 2 / 5 + math.PI * .5
            petal_across := math.cos(petal_angle) * .052
            petal_x := flower_center_x + petal_across * flower_plane_x
            petal_y := flower_center_y + math.sin(petal_angle) * .052
            petal_z := flower_center_z + petal_across * flower_plane_z
            world_vertical_disc_rotated(
                local_point(p, rotation, petal_x, petal_y, petal_z),
                .044,
                .057,
                .018,
                flower_yaw,
                petal_color,
            )
        }
        world_vertical_disc_rotated(
            local_point(
                p,
                rotation,
                flower_center_x - math.sin(flower_cant) * .014,
                flower_center_y,
                flower_center_z + math.cos(flower_cant) * .014,
            ),
            .033,
            .033,
            .018,
            flower_yaw,
            {232, 180, 62, 255},
        )
    }

    world_box_rotated(
        local_point(p, rotation, -.008 + head_sway + head_turn_x, muzzle_y - .066, muzzle_z + .150),
        {.007, .010, .008},
        rotation,
        tooth,
    )
    world_box_rotated(
        local_point(p, rotation, .008 + head_sway + head_turn_x, muzzle_y - .066, muzzle_z + .150),
        {.007, .010, .008},
        rotation,
        tooth,
    )

    sides := [2]f32{-1, 1}
    for side_f in sides {
        whisker_root := local_point(p, rotation, side_f * .035 + head_sway + head_turn_x, muzzle_y, muzzle_z + .165)
        for whisker_index in 0 ..< 3 {
            whisker_phase := editor.map_time * 4.2 + f32(whisker_index) * .82 + side_f * .38 + stride_phase * .18
            whisker_flex := math.sin(whisker_phase) * (.010 + .005 * run_weight)
            whisker_y := muzzle_y - .055 + f32(whisker_index) * .048
            whisker_mid := local_point(
                p,
                rotation,
                side_f * (.19 + f32(whisker_index) * .012) + head_sway + head_turn_x,
                (muzzle_y + whisker_y) * .5 + whisker_flex,
                muzzle_z + .13,
            )
            whisker_tip := local_point(
                p,
                rotation,
                side_f * (.36 + f32(whisker_index) * .022 + whisker_flex) + head_sway + head_turn_x,
                whisker_y + whisker_flex,
                muzzle_z + .07 - f32(whisker_index) * .012,
            )
            world_box_between(whisker_root, whisker_mid, model_forward, .006, .006, fur_light)
            world_box_between(whisker_mid, whisker_tip, model_forward, .005, .005, fur_light)
        }
    }

    // A mouse bounds: the fore pair reaches together while the powerful hind
    // pair compresses and releases half a cycle later.
    air_tuck := airborne_weight * (.13 + ascent_weight * .05 - descent_weight * .085)
    for side_f in sides {
        // A small bilateral phase lag keeps the paws from landing as mirrored
        // mechanical pairs while preserving the mouse's bounding gait.
        front_cycle := -math.sin(stride_phase + side_f * .12) * run_weight
        rear_cycle := math.sin(stride_phase - side_f * .10) * run_weight
        front_lift := max(front_cycle, f32(0)) * .105 * run_weight
        scapula_slide := front_cycle * .038
        inside_turn := max(side_f * turn_pose, f32(0))
        outside_turn := max(-side_f * turn_pose, f32(0))
        paw_turn_reach := animation.turn_paw_offset * (outside_turn - inside_turn * .45)
        idle_fore_shoulder := third_person.Vec3{side_f * .12, .31, .04}
        run_fore_shoulder := third_person.Vec3{side_f * .13, .31, .075}
        fore_shoulder := local_point(
            p,
            rotation,
            idle_fore_shoulder.x * (1 - run_weight) +
            run_fore_shoulder.x * run_weight +
            side_f * paw_turn_reach * .35 -
            side_f * posted_weight * .020,
            idle_fore_shoulder.y * (1 - run_weight) +
            run_fore_shoulder.y * run_weight +
            body_bob -
            brake_compression * .72 -
            inside_turn * .025 +
            posted_weight * .29,
            idle_fore_shoulder.z * (1 - run_weight) +
            run_fore_shoulder.z * run_weight +
            scapula_slide +
            posted_weight * .055,
        )
        fore_elbow := local_point(
            p,
            rotation,
            side_f * (.095 * (1 - run_weight) + .125 * run_weight + paw_turn_reach * .6) -
            side_f * posted_weight * .018,
            .16 * (1 - run_weight) +
            .155 * run_weight +
            front_lift * .35 +
            air_tuck * .55 -
            brake_compression * .55 -
            inside_turn * .02 +
            posted_weight * .30,
            .17 * (1 - run_weight) +
            (.145 + front_cycle * .090) * run_weight +
            brake_pose * .055 +
            posted_weight * .015,
        )
        idle_groom := math.sin(idle_phase * .78 + side_f * .9) * .009 * (1 - run_weight)
        fore_paw_x :=
            side_f * (.09 * (1 - run_weight) + .105 * run_weight + descent_weight * .018 + paw_turn_reach) -
            side_f * posted_weight * .022
        fore_paw_y :=
            .038 * (1 - run_weight) +
            .042 * run_weight +
            front_lift +
            air_tuck +
            idle_groom -
            inside_turn * .018 +
            posted_weight * .405
        fore_paw_z :=
            .29 * (1 - run_weight) +
            (.235 + front_cycle * .205 + side_f * .014) * run_weight +
            idle_groom * side_f * .55 +
            brake_pose * .12 -
            posted_weight * .095
        fore_paw := local_point(p, rotation, fore_paw_x, fore_paw_y, fore_paw_z)
        fore_planted := model.grounded && front_lift < .025 && posted_weight < .5
        if model.grounded {
            fore_paw = mouse_ground_contact(editor, fore_paw, .024, fore_planted)
        }
        fore_wrist := third_person.Vec3 {
            fore_elbow.x * .30 + fore_paw.x * .70,
            fore_elbow.y * .30 + fore_paw.y * .70,
            fore_elbow.z * .30 + fore_paw.z * .70,
        }
        fore_points := [4]third_person.Vec3{fore_shoulder, fore_elbow, fore_wrist, fore_paw}
        fore_radii := [4]f32{.044, .035, .024, .017}
        fore_colors := [4]rl.Color{fur, fur_dark, paw, paw}
        world_mouse_limb_hull(fore_points[:], fore_radii[:], fore_colors[:], model_forward)
        // Paws are low pads lying in the ground plane. The former vertical
        // discs presented their extrusion as a rectangular bar in profile.
        world_vertical_prism(fore_paw, .044, .041, .030, rotation, paw)
        for digit in 0 ..< 3 {
            digit_x := fore_paw_x + side_f * (f32(digit) - 1) * .013
            digit_tip := local_point(
                p,
                rotation,
                digit_x,
                fore_paw_y - .036 * (1 - run_weight) - .006 * run_weight,
                fore_paw_z + .018 * (1 - run_weight) + .064 * run_weight,
            )
            if model.grounded {
                digit_tip = mouse_ground_contact(editor, digit_tip, .008, fore_planted)
            }
            world_tube_between(fore_paw, digit_tip, model_forward, .008, .008, paw)
        }

        hind_cycle := rear_cycle + side_f * math.cos(stride_phase) * .035 * run_weight
        hind_lift := max(hind_cycle, f32(0)) * .120 * run_weight
        pelvic_drive := hind_cycle * .028
        hind_hip := local_point(
            p,
            rotation,
            side_f * (.16 + paw_turn_reach * .25 + posted_weight * .030),
            .30 + body_bob - brake_compression * .48 - inside_turn * .025 - posted_weight * .010,
            -.47 + pelvic_drive + brake_pose * .035,
        )
        // The hind leg needs both a forward knee and a rear hock. Collapsing
        // those joints into one segment hides the entire chain inside the
        // haunch in side views and makes the paw appear disconnected.
        hind_knee := local_point(
            p,
            rotation,
            side_f * (.205 + descent_weight * .012 + paw_turn_reach * .48 + posted_weight * .035),
            .18 + hind_lift * .35 + air_tuck * .32 - brake_compression * .25 + posted_weight * .015,
            -.25 + hind_cycle * .13 * run_weight + brake_pose * .105 - posted_weight * .055,
        )
        hind_hock := local_point(
            p,
            rotation,
            side_f * (.22 + descent_weight * .018 + paw_turn_reach * .68 + posted_weight * .040),
            .075 + hind_lift * .60 + air_tuck * .48 - brake_compression * .22,
            -.43 - hind_cycle * .060 * run_weight + brake_pose * .075 - posted_weight * .12,
        )
        hind_paw_x := side_f * (.195 + descent_weight * .025 + paw_turn_reach + posted_weight * .045)
        hind_paw_y := .042 + hind_lift + air_tuck - inside_turn * .014
        // An alert mouse plants its long hind feet forward under the belly;
        // this exposes the toes and supports the raised torso instead of
        // balancing it on two vertical hocks.
        hind_paw_z :=
            -.16 + hind_cycle * .17 * run_weight + side_f * .018 * run_weight + brake_pose * .15 - posted_weight * .10
        hind_paw := local_point(p, rotation, hind_paw_x, hind_paw_y, hind_paw_z)
        hind_planted := model.grounded && hind_lift < .025
        if model.grounded {
            hind_paw = mouse_ground_contact(editor, hind_paw, .024, hind_planted)
        }
        hind_ankle := third_person.Vec3 {
            hind_hock.x * .42 + hind_paw.x * .58,
            hind_hock.y * .42 + hind_paw.y * .58,
            hind_hock.z * .42 + hind_paw.z * .58,
        }
        hind_points := [5]third_person.Vec3{hind_hip, hind_knee, hind_hock, hind_ankle, hind_paw}
        hind_radii := [5]f32{.065, .052, .041, .030, .022}
        hind_colors := [5]rl.Color{fur, fur, fur_dark, paw, paw}
        world_mouse_limb_hull(hind_points[:], hind_radii[:], hind_colors[:], model_forward)
        world_vertical_prism(hind_paw, .058, .058, .032, rotation, paw)
        for digit in 0 ..< 3 {
            digit_tip := local_point(
                p,
                rotation,
                hind_paw_x + side_f * (f32(digit) - 1) * .017,
                hind_paw_y - .008,
                hind_paw_z + .092,
            )
            if model.grounded {
                digit_tip = mouse_ground_contact(editor, digit_tip, .009, hind_planted)
            }
            world_tube_between(hind_paw, digit_tip, model_forward, .009, .009, paw)
        }
    }

    if model.player_controlled {
        tail_points: [mouse_tail.POINT_COUNT]third_person.Vec3
        tail_radii: [mouse_tail.POINT_COUNT]f32
        tail_colors: [mouse_tail.POINT_COUNT]rl.Color
        for point, tail_index in editor.player_tail.points {
            weight := f32(tail_index) / f32(len(editor.player_tail.points) - 1)
            tail_points[tail_index] = point.position
            // Preserve a readable sub-pixel-safe tip at gameplay distance.
            // The physical taper remains pronounced, but no longer vanishes
            // between low-poly radial facets when the tail lies on pavement.
            tail_radii[tail_index] = editor.tweak.player_tail.radius * (1 - weight * .48)
            tail_colors[tail_index] = paw
            tail_floor :=
                mouse_surface_height(editor, point.position.x, point.position.z) +
                tail_radii[tail_index] +
                MOUSE_CONTACT_SKIN
            tail_points[tail_index].y = max(tail_points[tail_index].y, tail_floor)
            // At the low gameplay camera, a mathematically tangent tail tip is
            // depth-occluded by the road crown several segments away. Feather
            // in a tiny clearance without lifting the root off the rump.
            tail_points[tail_index].y += weight * .018
        }
        world_mouse_limb_hull(tail_points[:], tail_radii[:], tail_colors[:], model_forward)
    } else {
        tail_points: [9]third_person.Vec3
        tail_radii: [9]f32
        tail_colors: [9]rl.Color
        tail_points[0] = local_point(p, rotation, 0, .28, -.78)
        tail_radii[0] = .027
        tail_colors[0] = paw
        for tail_index in 1 ..= 8 {
            weight := f32(tail_index) / 8
            tail_points[tail_index] = local_point(
                p,
                rotation,
                math.sin(weight * math.PI) * .13,
                .28 * (1 - weight) + .035 * weight,
                -.78 - weight * .82,
            )
            tail_radii[tail_index] = .027 * (1 - weight * .58)
            tail_colors[tail_index] = paw
            surface :=
                mouse_surface_height(editor, tail_points[tail_index].x, tail_points[tail_index].z) +
                tail_radii[tail_index] +
                MOUSE_CONTACT_SKIN
            tail_points[tail_index].y = max(tail_points[tail_index].y, surface)
        }
        world_mouse_limb_hull(tail_points[:], tail_radii[:], tail_colors[:], model_forward)
    }
}

world_character :: proc(editor: ^Editor) {
    if !editor.in_map || editor.pilot.mode != .On_Foot do return
    world_mouse_model(
        editor,
        {
            position = editor.player.position,
            rotation = math.PI - editor.player.facing_yaw_radians,
            accessory = .Goggles,
            player_controlled = true,
            grounded = editor.player.grounded,
        },
    )
}

world_marta :: proc(editor: ^Editor) {
    if !editor.in_map || !editor.libellula_visible do return
    delta := third_person.Vec3 {
        x = editor.player.position.x - editor.attendant_position.x,
        z = editor.player.position.z - editor.attendant_position.z,
    }
    facing := math.atan2(-delta.x, -delta.z)
    world_mouse_model(
        editor,
        {position = editor.attendant_position, rotation = math.PI - facing, accessory = .Flower, grounded = true},
    )
}

world_character_legacy :: proc(editor: ^Editor) {
    if !editor.in_map || editor.pilot.mode != .On_Foot do return
    p := editor.player.position
    rotation := math.PI - editor.player.facing_yaw_radians
    local_point :: proc(origin: third_person.Vec3, rotation, x, y, z: f32) -> third_person.Vec3 {
        world_x, world_z := world_rotate_xz(origin.x, origin.z, x, z, rotation)
        return {world_x, origin.y + y, world_z}
    }
    jacket: rl.Color = {35, 167, 162, 255}
    jacket_dark: rl.Color = {23, 112, 119, 255}
    shirt: rl.Color = {232, 222, 189, 255}
    scarf: rl.Color = {205, 79, 62, 255}
    fur: rl.Color = {145, 137, 128, 255}
    fur_light: rl.Color = {169, 161, 150, 255}
    fur_dark: rl.Color = {91, 84, 81, 255}
    ear: rl.Color = {184, 124, 123, 255}
    tail: rl.Color = {168, 111, 113, 255}
    trousers: rl.Color = {36, 55, 71, 255}
    boots: rl.Color = {73, 53, 43, 255}
    features: rl.Color = {35, 39, 42, 255}
    model_forward := third_person.Vec3 {
        x = -math.sin(rotation),
        z = math.cos(rotation),
    }
    gait_weight := editor.player_gait_weight
    airborne_weight := editor.player_airborne_weight
    vertical_pose := editor.player_vertical_pose
    if editor.capture_player_jump_pose || editor.capture_player_fall_pose {
        airborne_weight = 1
        vertical_pose = clamp(
            editor.player.velocity.y / max(editor.tweak.player_animation.vertical_full_speed, f32(.1)),
            -1,
            1,
        )
    }
    jump_rise := vertical_pose * airborne_weight
    ascent_weight := max(jump_rise, f32(0))
    descent_weight := max(-jump_rise, f32(0))
    gait_weight *= 1 - airborne_weight
    stride_phase := editor.player_stride_phase
    if editor.capture_player_walk_pose {
        gait_weight = 1
        stride_phase = math.PI * .34
    }
    stride := math.sin(stride_phase) * gait_weight
    p.y += math.abs(math.sin(stride_phase * 2)) * .018 * gait_weight
    idle_phase := editor.map_time * 2.2
    blink_period := f32(4.6)
    blink_time := editor.map_time - f32(math.floor(f64(editor.map_time / blink_period))) * blink_period
    blink_weight := clamp(1 - math.abs(blink_time - .10) / .10, 0, 1)
    if editor.capture_player_blink_pose do blink_weight = 1
    head_sway := math.sin(stride_phase) * .018 * gait_weight + math.sin(idle_phase * .55) * .006 * (1 - gait_weight)
    head_bob :=
        math.abs(math.sin(stride_phase * 2)) * .015 * gait_weight +
        math.sin(idle_phase) * .006 * (1 - gait_weight) +
        airborne_weight * .025
    ear_flutter :=
        math.abs(math.sin(stride_phase)) * .012 * gait_weight +
        math.sin(idle_phase * 1.7) * .006 * (1 - gait_weight) +
        blink_weight * .010
    sniff := math.sin(editor.map_time * 5.4) * .007 * (1 - gait_weight)
    tail_phase := idle_phase * .7 + stride_phase * .45 + descent_weight * 1.15
    tail_amplitude := .05 + .07 * gait_weight + .055 * airborne_weight
    tail_lift_amplitude := .025 + .035 * gait_weight + .075 * airborne_weight
    torso_sway := stride * .016
    torso_stretch := airborne_weight * (.018 + ascent_weight * .014 - descent_weight * .008)

    // Keep the practical islander's clothes and gait, but give the player a
    // mouse's compact proportions and unmistakable head-and-tail silhouette.
    world_vertical_disc_rotated(
        local_point(p, rotation, torso_sway, .91 + torso_stretch * .35, 0),
        .26 - torso_stretch * .35,
        .32 + torso_stretch,
        .30,
        rotation,
        jacket,
    )
    world_box_rotated(
        local_point(p, rotation, torso_sway, .98 + torso_stretch * .55, .166),
        {.17, .29 + torso_stretch, .026},
        rotation,
        shirt,
    )
    world_box_rotated(
        local_point(p, rotation, torso_sway, 1.18 + torso_stretch, .175),
        {.44, .105, .035},
        rotation,
        scarf,
    )
    world_vertical_disc_rotated(
        local_point(p, rotation, torso_sway * .35, .61, .005),
        .22,
        .055,
        .30,
        rotation,
        jacket_dark,
    )

    sides := [2]f32{-1, 1}
    for side_f in sides {
        leg_cycle := math.sin(stride_phase) * side_f * gait_weight
        leg_swing := leg_cycle * .14
        airborne_tuck := airborne_weight * (.22 - descent_weight * .18 + side_f * jump_rise * .020)
        foot_lift := max(leg_cycle, f32(0)) * .09 + airborne_tuck
        hip := local_point(p, rotation, side_f * .125, .61, 0)
        knee := local_point(
            p,
            rotation,
            side_f * (.15 - airborne_weight * .015 + descent_weight * .025),
            .36 + foot_lift * .55,
            side_f * -.018 + leg_swing * .42 - airborne_weight * .035,
        )
        ankle := local_point(
            p,
            rotation,
            side_f * (.14 - airborne_weight * .025 + descent_weight * .045),
            .13 + foot_lift,
            side_f * .025 + leg_swing - airborne_weight * .055,
        )
        world_tube_between(hip, knee, model_forward, .09, .115, trousers)
        world_tube_between(knee, ankle, model_forward, .082, .105, trousers)
        world_vertical_disc_rotated(
            local_point(
                p,
                rotation,
                side_f * (.135 + descent_weight * .050),
                .09 + foot_lift,
                .065 + leg_swing + descent_weight * .025,
            ),
            .12,
            .09,
            .33,
            rotation,
            boots,
        )

        arm_swing := -leg_swing * .92
        shoulder := local_point(p, rotation, side_f * .255 + torso_sway, 1.14 + torso_stretch, 0)
        elbow := local_point(
            p,
            rotation,
            side_f * (.325 + airborne_weight * .055 + descent_weight * .050) + torso_sway * .75,
            .89 + airborne_weight * .11 - descent_weight * .050,
            .015 + arm_swing * .48 - airborne_weight * .025,
        )
        wrist := local_point(
            p,
            rotation,
            side_f * (.29 + airborne_weight * .11 + descent_weight * .080) + torso_sway * .50,
            .66 + airborne_weight * .25 - descent_weight * .14,
            .055 + arm_swing - airborne_weight * .04 + descent_weight * .040,
        )
        world_tube_between(shoulder, elbow, model_forward, .08, .105, jacket_dark)
        world_tube_between(elbow, wrist, model_forward, .07, .095, jacket_dark)
        world_vertical_disc_rotated(wrist, .09, .078, .12, rotation, fur_light)
    }

    // The skull sits behind a long tapered rostrum: a mouse's face is a wedge,
    // not a flat circular mask. Keep the ears high and slightly behind the eyes.
    world_vertical_prism(
        local_point(p, rotation, head_sway * .45, 1.34 + head_bob * .35, 0),
        .09,
        .08,
        .18,
        rotation,
        fur_dark,
    )
    world_vertical_disc_rotated(
        local_point(p, rotation, head_sway, 1.53 + head_bob, -.055),
        .22,
        .215,
        .30,
        rotation,
        fur,
    )
    ear_offsets := [2]f32{-.18, .18}
    for ear_x in ear_offsets {
        side_motion := ear_flutter * (ear_x / .18)
        ear_drag := airborne_weight * (.042 + ascent_weight * .015 - descent_weight * .025)
        world_vertical_disc_rotated(
            local_point(
                p,
                rotation,
                ear_x + head_sway + side_motion * .16,
                1.72 + head_bob + side_motion - ear_drag,
                -.13 - ear_drag,
            ),
            .13,
            .135 + side_motion * .10,
            .09,
            rotation,
            fur_dark,
        )
        world_vertical_disc_rotated(
            local_point(
                p,
                rotation,
                ear_x + head_sway + side_motion * .16,
                1.72 + head_bob + side_motion - ear_drag,
                -.078 - ear_drag,
            ),
            .088,
            .094 + side_motion * .07,
            .018,
            rotation,
            ear,
        )
    }

    world_tapered_disc_depth_rotated(
        local_point(p, rotation, head_sway, 1.47 + head_bob, .215 + sniff),
        .145,
        .13,
        .032,
        .03,
        .42,
        rotation,
        fur_light,
    )
    world_vertical_disc_rotated(
        local_point(p, rotation, head_sway, 1.405 + head_bob, .255 + sniff * .45),
        .066,
        .045,
        .13,
        rotation,
        fur_light,
    )
    world_vertical_disc_rotated(
        local_point(p, rotation, head_sway, 1.47 + head_bob, .442 + sniff),
        .033,
        .026,
        .032,
        rotation,
        features,
    )
    world_box_rotated(
        local_point(p, rotation, -.027 + head_sway, 1.392 + head_bob, .385 + sniff * .35),
        {.025, .052, .020},
        rotation,
        shirt,
    )
    world_box_rotated(
        local_point(p, rotation, .027 + head_sway, 1.392 + head_bob, .385 + sniff * .35),
        {.025, .052, .020},
        rotation,
        shirt,
    )

    // Small lateral eyes sit behind the muzzle base, closer to the ears than
    // the nose. Their highlights remain tiny at this scale.
    eye_offsets := [2]f32{-.14, .14}
    eye_radius_y := .004 + (1 - blink_weight) * .030
    for eye_x in eye_offsets {
        world_vertical_disc_rotated(
            local_point(p, rotation, eye_x + head_sway, 1.56 + head_bob, .102),
            .028,
            eye_radius_y,
            .024,
            rotation,
            features,
        )
        if blink_weight < .55 {
            world_vertical_disc_rotated(
                local_point(p, rotation, eye_x - .007 + head_sway, 1.572 + head_bob, .117),
                .007,
                .009 * (1 - blink_weight),
                .008,
                rotation,
                shirt,
            )
        }
    }

    for side_f in sides {
        whisker_root := local_point(p, rotation, side_f * .038 + head_sway, 1.455 + head_bob, .39 + sniff)
        for whisker_index in 0 ..< 3 {
            whisker_phase := editor.map_time * 4.2 + f32(whisker_index) * .82 + side_f * .38 + stride_phase * .22
            whisker_flex := math.sin(whisker_phase) * (.010 + .006 * gait_weight)
            whisker_y := 1.40 + head_bob + f32(whisker_index) * .052
            whisker_mid := local_point(
                p,
                rotation,
                side_f * (.19 + f32(whisker_index) * .012) + head_sway,
                (1.455 + head_bob + whisker_y) * .5 + whisker_flex,
                .35 + sniff * .65,
            )
            whisker_tip := local_point(
                p,
                rotation,
                side_f * (.35 + f32(whisker_index) * .022 + whisker_flex * .7) + head_sway,
                whisker_y + whisker_flex * 1.35,
                .30 + sniff * .35 - f32(whisker_index) * .014 + whisker_flex * .3,
            )
            world_box_between(whisker_root, whisker_mid, model_forward, .007, .007, fur_light)
            world_box_between(whisker_mid, whisker_tip, model_forward, .006, .006, fur_light)
        }
    }

    // A phase delay along the articulated tail produces a traveling wave
    // rather than rotating the whole tail as one rigid prop.
    tail_base_x := [6]f32{0, .14, .34, .51, .57, .52}
    tail_base_y := [6]f32{.66, .49, .40, .42, .54, .67}
    tail_base_z := [6]f32{-.18, -.34, -.53, -.70, -.84, -.94}
    tail_points: [6]third_person.Vec3
    for tail_index in 0 ..< len(tail_points) {
        weight := f32(tail_index) / f32(len(tail_points) - 1)
        delayed_phase := tail_phase - f32(tail_index) * .52
        lateral_wave := math.sin(delayed_phase) * tail_amplitude * weight
        vertical_wave := math.cos(delayed_phase * 1.08 + .8) * tail_lift_amplitude * weight
        tail_points[tail_index] = local_point(
            p,
            rotation,
            tail_base_x[tail_index] + lateral_wave,
            tail_base_y[tail_index] + vertical_wave,
            tail_base_z[tail_index],
        )
    }
    for tail_index in 0 ..< len(tail_points) - 1 {
        radius := .050 - f32(tail_index) * .006
        world_tube_between(tail_points[tail_index], tail_points[tail_index + 1], model_forward, radius, radius, tail)
    }
}

world_brush_disc :: proc(editor: ^Editor, x, z, radius, height_offset: f32, color: rl.Color) {
    if editor == nil do return
    segments := 48
    center := third_person.Vec3 {
        x = x,
        y = terrain.sample_height(&editor.project, 0, x, z) + height_offset,
        z = z,
    }
    for i in 0 ..< segments {
        a0 := f32(i) * 2 * math.PI / f32(segments)
        a1 := f32(i + 1) * 2 * math.PI / f32(segments)
        p0 := third_person.Vec3 {
            x = x + math.cos(a0) * radius,
            z = z + math.sin(a0) * radius,
        }
        p1 := third_person.Vec3 {
            x = x + math.cos(a1) * radius,
            z = z + math.sin(a1) * radius,
        }
        p0.y = terrain.sample_height(&editor.project, 0, p0.x, p0.z) + height_offset
        p1.y = terrain.sample_height(&editor.project, 0, p1.x, p1.z) + height_offset
        // Ground decal fan: upward face front (CCW) so it survives culling.
        world_triangle(center, p1, p0, color)
    }
}

world_brush :: proc(editor: ^Editor) {
    if editor.in_map || (editor.tool == .Structure && !editor.architecture_paint_mode) do return
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    mouse, inside := rl.GetWorldMousePosition()
    if !inside do return
    x, z, hit := terrain_under_cursor_3d(editor, camera, mouse, ADRIATIC_WORLD_WIDTH, ADRIATIC_WORLD_HEIGHT)
    if !hit do return
    color: rl.Color = {230, 244, 218, 76}
    radius, hardness := editor.radius, editor.hardness
    switch editor.tool {
    case .Raise:
        color = {244, 214, 122, 88}
    case .Smooth:
        color = {176, 225, 236, 88}
    case .Paint:
        color = {168, 239, 220, 88}
    case .Structure:
        color = {90, 102, 112, 86}
        radius = editor.architecture_brush_radius
        hardness = editor.architecture_brush_hardness
    }
    if rl.IsMouseButtonDown(.RIGHT) do color = {245, 126, 112, 108}
    world_brush_disc(editor, x, z, radius, .09, color)
    // A denser inner disc makes the hardness setting legible at the cursor:
    // harder brushes have a larger, more opaque core while the outer disc
    // continues to show the full affected radius.
    inner_radius := radius * (.25 + hardness * .65)
    core := color
    core.a = u8(min(int(color.a) + 34, 180))
    world_brush_disc(editor, x, z, inner_radius, .105, core)
}

world_build :: proc(editor: ^Editor) {
    clear(&world_renderer.vertices)
    clear(&world_renderer.road_vertices)
    clear(&world_renderer.foliage_vertices)
    // Depth testing makes submission order independent. Put authored gameplay
    // meshes first so dense terrain can consume only the remaining capacity
    // instead of silently dropping vehicles at the end of the frame.
    world_ocean(editor)
    world_infrastructure(editor)
    world_roads(editor)
    world_city_density_overlay(editor)
    sky := atmosphere.sample(&editor.atmosphere)
    for structure in editor.project.structures[:editor.project.structure_count] {
        world_structure_shadow(structure, sky.sun_direction, sky.weather.cloud_cover, &editor.project)
    }

    if editor.in_map && editor.pilot.mode == .On_Foot {
        character_ground := terrain.sample_height(
            &editor.project,
            0,
            editor.player.position.x,
            editor.player.position.z,
        )
        character_shadow := terrain.structure_make(
            editor.player.position.x,
            editor.player.position.z,
            .72,
            1.72,
            character_ground,
            .78,
        )
        world_structure_shadow(character_shadow, sky.sun_direction, sky.weather.cloud_cover, &editor.project)
    }
    if editor.in_map && editor.libellula_visible {
        marta_ground := terrain.sample_height(
            &editor.project,
            0,
            editor.attendant_position.x,
            editor.attendant_position.z,
        )
        marta_shadow := terrain.structure_make(
            editor.attendant_position.x,
            editor.attendant_position.z,
            .72,
            1.72,
            marta_ground,
            .78,
        )
        world_structure_shadow(marta_shadow, sky.sun_direction, sky.weather.cloud_cover, &editor.project)
    }
    world_structures(editor)
    world_aircraft(editor)
    world_car(editor)
    world_marta(editor)
    world_character(editor)
    world_brush(editor)
    world_particles_cpu(editor)
    world_vehicle_particles(editor)
    world_wing_trails(editor)
    world_wind_streaks(editor)
}

world_particles_cpu :: proc(editor: ^Editor) {
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    for particle in editor.particles.particles[:editor.particles.count] {
        fade := clamp(particle.life / particle.max_life, 0, 1)
        color := rl.Color{u8(220 + 35 * fade), u8(120 + 90 * fade), u8(36 + 100 * fade), u8(110 + 145 * fade)}
        right := third_person.Vec3 {
            x = camera.right.x * particle.size,
            y = camera.right.y * particle.size,
            z = camera.right.z * particle.size,
        }
        up := third_person.Vec3 {
            x = camera.up.x * particle.size,
            y = camera.up.y * particle.size,
            z = camera.up.z * particle.size,
        }
        p := third_person.Vec3{particle.position.x, particle.position.y, particle.position.z}
        world_quad(
            {p.x - right.x - up.x, p.y - right.y - up.y, p.z - right.z - up.z},
            {p.x + right.x - up.x, p.y + right.y - up.y, p.z + right.z - up.z},
            {p.x + right.x + up.x, p.y + right.y + up.y, p.z + right.z + up.z},
            {p.x - right.x + up.x, p.y - right.y + up.y, p.z - right.z + up.z},
            color,
        )
    }
}

world_vehicle_particle :: proc(
    camera: Perspective_Camera,
    particle: particles.Vehicle_Particle,
    color: rl.Color,
    opacity_override: f32 = -1,
) {
    fade := clamp(particle.life / particle.max_life, 0, 1)
    age := 1 - fade
    rotation := particle.seed & 3
    cosine, sine := f32(1), f32(0)
    switch rotation {
    case 1:
        cosine, sine = .92388, .38268
    case 2:
        cosine, sine = .70711, .70711
    case 3:
        cosine, sine = .38268, .92388
    }
    width := particle.size * (.82 + f32((particle.seed >> 3) & 3) * .07) * (.78 + age * .46)
    height := particle.size * (.62 + f32((particle.seed >> 5) & 3) * .08) * (.78 + age * .46)
    right := third_person.Vec3 {
        x = (camera.right.x * cosine + camera.up.x * sine) * width,
        y = (camera.right.y * cosine + camera.up.y * sine) * width,
        z = (camera.right.z * cosine + camera.up.z * sine) * width,
    }
    up := third_person.Vec3 {
        x = (-camera.right.x * sine + camera.up.x * cosine) * height,
        y = (-camera.right.y * sine + camera.up.y * cosine) * height,
        z = (-camera.right.z * sine + camera.up.z * cosine) * height,
    }
    p := third_person.Vec3{particle.position.x, particle.position.y, particle.position.z}
    opacity := opacity_override < 0 ? fade : clamp(opacity_override, 0, 1)
    alpha := u8(f32(color.a) * opacity)
    shade := rl.Color{color.r, color.g, color.b, alpha}
    world_quad(
        {p.x - right.x - up.x, p.y - right.y - up.y, p.z - right.z - up.z},
        {p.x + right.x - up.x, p.y + right.y - up.y, p.z + right.z - up.z},
        {p.x + right.x + up.x, p.y + right.y + up.y, p.z + right.z + up.z},
        {p.x - right.x + up.x, p.y - right.y + up.y, p.z - right.z + up.z},
        shade,
    )
}

world_vehicle_particles :: proc(editor: ^Editor) {
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    for particle in editor.vehicle_effects.dust[:editor.vehicle_effects.dust_count] {
        color := rl.Color{112, 119, 116, 100}
        switch particle.surface {
        case .Asphalt:
            color = {116, 123, 124, 62}
        case .Gravel:
            color = {203, 181, 133, 178}
        case .Cobblestone:
            color = {156, 162, 157, 105}
        case .Dirt:
            color = {177, 111, 62, 190}
        case .Grass:
            color = {119, 126, 78, 132}
        case .Sand:
            color = {210, 192, 150, 150}
        }
        world_vehicle_particle(camera, particle, color)
    }
    for particle in editor.vehicle_effects.exhaust[:editor.vehicle_effects.exhaust_count] {
        world_vehicle_particle(
            camera,
            particle,
            {126, 132, 130, 168},
            particles.vehicle_exhaust_opacity(particle.life, particle.max_life),
        )
    }
}

world_wing_trail_segment :: proc(camera: Perspective_Camera, a, b: particles.Vec3, width: f32, color: rl.Color) {
    offset := third_person.Vec3 {
        x = camera.right.x * width,
        y = camera.right.y * width,
        z = camera.right.z * width,
    }
    world_quad(
        {a.x - offset.x, a.y - offset.y, a.z - offset.z},
        {a.x + offset.x, a.y + offset.y, a.z + offset.z},
        {b.x + offset.x, b.y + offset.y, b.z + offset.z},
        {b.x - offset.x, b.y - offset.y, b.z - offset.z},
        color,
    )
}

world_wing_trail_cap :: proc(camera: Perspective_Camera, center: particles.Vec3, radius: f32, color: rl.Color) {
    p := third_person.Vec3{center.x, center.y, center.z}
    for side in 0 ..< 8 {
        a0 := f32(side) * math.PI * 2 / 8
        a1 := f32(side + 1) * math.PI * 2 / 8
        p0 := third_person.Vec3 {
            x = p.x + (camera.right.x * math.cos(a0) + camera.up.x * math.sin(a0)) * radius,
            y = p.y + (camera.right.y * math.cos(a0) + camera.up.y * math.sin(a0)) * radius,
            z = p.z + (camera.right.z * math.cos(a0) + camera.up.z * math.sin(a0)) * radius,
        }
        p1 := third_person.Vec3 {
            x = p.x + (camera.right.x * math.cos(a1) + camera.up.x * math.sin(a1)) * radius,
            y = p.y + (camera.right.y * math.cos(a1) + camera.up.y * math.sin(a1)) * radius,
            z = p.z + (camera.right.z * math.cos(a1) + camera.up.z * math.sin(a1)) * radius,
        }
        world_triangle(p, p0, p1, color)
    }
}

world_wing_trails :: proc(editor: ^Editor) {
    if editor.wing_trails.count <= 0 do return
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    for side in 0 ..< 2 {
        previous: particles.Vec3
        has_previous := false
        for particle in editor.wing_trails.particles[:editor.wing_trails.count] {
            if int(particle.side) != side do continue
            fade := clamp(particle.life / particle.max_life, 0, 1)
            if has_previous {
                world_wing_trail_segment(
                    camera,
                    previous,
                    particle.position,
                    particle.size * (.8 + fade * .35),
                    {205, 239, 236, 255},
                )
            }
            world_wing_trail_cap(camera, particle.position, particle.size * (.8 + fade * .35), {205, 239, 236, 255})
            previous = particle.position
            has_previous = true
        }
    }
}

wind_streak_hash :: proc(index, salt: int) -> f32 {
    value := math.sin(f64(index * 127 + salt * 311) * 12.9898) * 43758.5453
    return f32(value - math.floor(value))
}

world_wind_streaks :: proc(editor: ^Editor) {
    if editor == nil || !editor.in_map || !driving_aircraft(editor) do return
    wind_x, wind_z := editor.atmosphere.weather.wind[0], editor.atmosphere.weather.wind[1]
    wind_speed := f32(math.sqrt(f64(wind_x * wind_x + wind_z * wind_z)))
    strength := clamp((wind_speed - 1) / 8, 0, 1)
    if strength <= .001 do return

    body := active_aircraft_body(editor)
    direction_x, direction_z := wind_x / wind_speed, wind_z / wind_speed
    side_x, side_z := -direction_z, direction_x
    time := editor.map_time
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    for index in 0 ..< 32 {
        speed_variation := .72 + wind_streak_hash(index, 1) * .56
        cycle := time * wind_speed * .035 * speed_variation + wind_streak_hash(index, 2)
        phase := cycle - f32(math.floor(f64(cycle)))
        along := (phase - .5) * 82
        lateral := (wind_streak_hash(index, 3) - .5) * 62
        vertical := (wind_streak_hash(index, 4) - .5) * 25 + 3
        center := particles.Vec3 {
            x = body.position.x + direction_x * along + side_x * lateral,
            y = body.position.y + vertical,
            z = body.position.z + direction_z * along + side_z * lateral,
        }
        streak_length := (1.4 + wind_speed * .58) * (.62 + wind_streak_hash(index, 5) * .58)
        tail := particles.Vec3 {
            x = center.x - direction_x * streak_length,
            y = center.y,
            z = center.z - direction_z * streak_length,
        }
        fade := math.sin(phase * math.PI)
        alpha := u8(clamp((22 + strength * 82) * fade, 0, 104))
        width := .018 + strength * .035
        offset := third_person.Vec3 {
            x = camera.up.x * width,
            y = camera.up.y * width,
            z = camera.up.z * width,
        }
        world_quad(
            {tail.x - offset.x, tail.y - offset.y, tail.z - offset.z},
            {center.x - offset.x, center.y - offset.y, center.z - offset.z},
            {center.x + offset.x, center.y + offset.y, center.z + offset.z},
            {tail.x + offset.x, tail.y + offset.y, tail.z + offset.z},
            {r = 205, g = 239, b = 236, a = alpha},
        )
    }
}

world_renderer_create :: proc(ctx: ^engine.Vk_Context) -> bool {
    pr := vk.PushConstantRange {
        stageFlags = {.VERTEX, .FRAGMENT},
        size       = u32(size_of(World_Push)),
    }
    li := vk.PipelineLayoutCreateInfo {
        sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
        pushConstantRangeCount = 1,
        pPushConstantRanges    = &pr,
    }
    if vk.CreatePipelineLayout(ctx.device, &li, nil, &world_renderer.layout) != .SUCCESS do return false
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
    foliage_pool_sizes := [2]vk.DescriptorPoolSize {
        {type = .SAMPLED_IMAGE, descriptorCount = 1},
        {type = .SAMPLER, descriptorCount = 1},
    }
    foliage_pool_info := vk.DescriptorPoolCreateInfo {
        sType         = .DESCRIPTOR_POOL_CREATE_INFO,
        maxSets       = 1,
        poolSizeCount = 2,
        pPoolSizes    = raw_data(foliage_pool_sizes[:]),
    }
    if vk.CreateDescriptorPool(ctx.device, &foliage_pool_info, nil, &world_renderer.foliage_descriptor_pool) !=
       .SUCCESS {
        return false
    }
    foliage_allocate := vk.DescriptorSetAllocateInfo {
        sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool     = world_renderer.foliage_descriptor_pool,
        descriptorSetCount = 1,
        pSetLayouts        = &world_renderer.foliage_descriptor_layout,
    }
    if vk.AllocateDescriptorSets(ctx.device, &foliage_allocate, &world_renderer.foliage_descriptor) != .SUCCESS {
        return false
    }
    if !resources.texture_load_file(
        ctx,
        "assets/textures/foliage/leaf-branches-atlas.png",
        &world_renderer.foliage_atlas,
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
    foliage_writes := [2]vk.WriteDescriptorSet {
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
    }
    vk.UpdateDescriptorSets(ctx.device, 2, raw_data(foliage_writes[:]), 0, nil)
    foliage_layout_info := li
    foliage_layout_info.setLayoutCount = 1
    foliage_layout_info.pSetLayouts = &world_renderer.foliage_descriptor_layout
    if vk.CreatePipelineLayout(ctx.device, &foliage_layout_info, nil, &world_renderer.foliage_layout) != .SUCCESS {
        return false
    }
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
    vert, frag: engine.Vk_Shader_Module
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
    attrs := [4]vk.VertexInputAttributeDescription {
        {location = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(World_Vertex, position))},
        {location = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(World_Vertex, color))},
        {location = 2, format = .R32_SFLOAT, offset = u32(offset_of(World_Vertex, kind))},
        {location = 3, format = .R32G32B32_SFLOAT, offset = u32(offset_of(World_Vertex, normal))},
    }
    vi := vk.PipelineVertexInputStateCreateInfo {
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount   = 1,
        pVertexBindingDescriptions      = &binding,
        vertexAttributeDescriptionCount = 4,
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
    if !render3d.create_color_pipeline_variants(ctx, &info, .D32_SFLOAT, &world_renderer.pipelines) do return false
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
    foliage_attributes := [3]vk.VertexInputAttributeDescription {
        {location = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Foliage_Vertex, position))},
        {location = 1, format = .R32G32_SFLOAT, offset = u32(offset_of(Foliage_Vertex, uv))},
        {location = 2, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(Foliage_Vertex, color))},
    }
    foliage_vi := vk.PipelineVertexInputStateCreateInfo {
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount   = 1,
        pVertexBindingDescriptions      = &foliage_binding,
        vertexAttributeDescriptionCount = 3,
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
    info.pVertexInputState = &sky_vi
    info.pDepthStencilState = &sky_depth
    info.layout = world_renderer.sky_layout
    if !render3d.create_color_pipeline_variants(ctx, &info, .D32_SFLOAT, &world_renderer.sky_pipelines) do return false
    for &buffer in world_renderer.vertex {
        if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(WORLD_VERTEX_CAPACITY * size_of(World_Vertex)), {.VERTEX_BUFFER}, &buffer) do return false
    }
    for &buffer in world_renderer.road_vertex {
        if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(ROAD_VERTEX_CAPACITY * size_of(World_Vertex)), {.VERTEX_BUFFER}, &buffer) do return false
    }
    for &buffer in world_renderer.foliage_vertex {
        if !engine.vk_create_host_buffer(
            ctx,
            vk.DeviceSize(FOLIAGE_VERTEX_CAPACITY * size_of(Foliage_Vertex)),
            {.VERTEX_BUFFER},
            &buffer,
        ) {
            return false
        }
    }
    for frame in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
        for level in 0 ..< terrain.CLIPMAP_LEVELS {
            if !engine.vk_create_host_buffer(
                ctx,
                vk.DeviceSize(CLIPMAP_VERTEX_COUNT * size_of(World_Vertex)),
                {.VERTEX_BUFFER},
                &world_renderer.clipmap_vertex[frame][level],
            ) {
                return false
            }
        }
    }
    if !clipmap_create_indices(ctx) do return false
    world_renderer.vertices = make([dynamic]World_Vertex, 0, WORLD_VERTEX_CAPACITY)
    world_renderer.road_vertices = make([dynamic]World_Vertex, 0, ROAD_VERTEX_CAPACITY)
    world_renderer.foliage_vertices = make([dynamic]Foliage_Vertex, 0, FOLIAGE_VERTEX_CAPACITY)
    world_renderer.ctx = ctx
    world_renderer.initialized = true
    return true
}

world_pass_legacy :: proc(pass: ^rl.World_Pass_Context, _: rawptr) {
    if !world_renderer.initialized && !world_renderer_create(pass.ctx) do return
    editor := world_renderer.editor
    if editor == nil do return
    world_build(editor)
    clipmap_update(editor, int(pass.frame.frame_index))
    buffer := &world_renderer.vertex[pass.frame.frame_index]
    road_buffer := &world_renderer.road_vertex[pass.frame.frame_index]
    foliage_buffer := &world_renderer.foliage_vertex[pass.frame.frame_index]
    if len(world_renderer.vertices) > 0 {
        mem.copy_non_overlapping(
            buffer.mapped,
            raw_data(world_renderer.vertices[:]),
            len(world_renderer.vertices) * size_of(World_Vertex),
        )
    }
    if len(world_renderer.road_vertices) > 0 {
        mem.copy_non_overlapping(
            road_buffer.mapped,
            raw_data(world_renderer.road_vertices[:]),
            len(world_renderer.road_vertices) * size_of(World_Vertex),
        )
    }
    if len(world_renderer.foliage_vertices) > 0 {
        mem.copy_non_overlapping(
            foliage_buffer.mapped,
            raw_data(world_renderer.foliage_vertices[:]),
            len(world_renderer.foliage_vertices) * size_of(Foliage_Vertex),
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
    pipeline_index := pass.color_format == vk.Format.R16G16B16A16_SFLOAT ? 1 : 0
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    sky := atmosphere.sample(&editor.atmosphere)
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
        sun             = {sky.sun_direction[0], sky.sun_direction[1], sky.sun_direction[2], sky.daylight},
    }
    sky_push := Sky_Push {
        camera_right   = {
            camera.right.x,
            camera.right.y,
            camera.right.z,
            f32(pass.framebuffer_extent.width) / f32(max(pass.framebuffer_extent.height, 1)),
        },
        camera_up      = {camera.up.x, camera.up.y, camera.up.z, camera.focal_length},
        camera_forward = {camera.forward.x, camera.forward.y, camera.forward.z, 0},
        sun_direction  = {sky.sun_direction[0], sky.sun_direction[1], sky.sun_direction[2], f32(sky.cloud_seed)},
        time_light     = {sky.world_minutes, sky.cloud_time_seconds, sky.daylight, sky.twilight},
        wind_cloud     = {
            sky.weather.wind[0],
            sky.weather.wind[1],
            sky.weather.cloud_cover,
            sky.weather.precipitation,
        },
        haze_severity  = {sky.weather.haze, sky.weather.severity, 0, 0},
    }
    vk.CmdPushConstants(
        pass.frame.command_buffer,
        world_renderer.sky_layout,
        {.VERTEX, .FRAGMENT},
        0,
        u32(size_of(sky_push)),
        &sky_push,
    )
    vk.CmdBindPipeline(pass.frame.command_buffer, .GRAPHICS, world_renderer.sky_pipelines[pipeline_index])
    vk.CmdDraw(pass.frame.command_buffer, 3, 1, 0, 0)
    vk.CmdBindPipeline(pass.frame.command_buffer, .GRAPHICS, world_renderer.pipelines[pipeline_index])
    vk.CmdPushConstants(
        pass.frame.command_buffer,
        world_renderer.layout,
        {.VERTEX, .FRAGMENT},
        0,
        u32(size_of(world_push)),
        &world_push,
    )
    offset := vk.DeviceSize(0)
    if len(world_renderer.vertices) > 0 {
        vk.CmdBindVertexBuffers(pass.frame.command_buffer, 0, 1, &buffer.handle, &offset)
        vk.CmdDraw(pass.frame.command_buffer, u32(len(world_renderer.vertices)), 1, 0, 0)
    }
    vk.CmdBindPipeline(pass.frame.command_buffer, .GRAPHICS, world_renderer.particle_pipelines[pipeline_index])
    vk.CmdPushConstants(
        pass.frame.command_buffer,
        world_renderer.layout,
        {.VERTEX, .FRAGMENT},
        0,
        u32(size_of(world_push)),
        &world_push,
    )
    vk.CmdDraw(pass.frame.command_buffer, 6 * 512, 1, 0, 0)
    // The particle pass uses a vertex-id-only pipeline. Rebind the terrain
    // pipeline before submitting indexed clipmap vertices.
    vk.CmdBindPipeline(pass.frame.command_buffer, .GRAPHICS, world_renderer.pipelines[pipeline_index])
    vk.CmdPushConstants(
        pass.frame.command_buffer,
        world_renderer.layout,
        {.VERTEX, .FRAGMENT},
        0,
        u32(size_of(world_push)),
        &world_push,
    )
    vk.CmdBindIndexBuffer(pass.frame.command_buffer, world_renderer.clipmap_index.handle, 0, .UINT32)
    for level in 0 ..< terrain.CLIPMAP_LEVELS {
        level_buffer := &world_renderer.clipmap_vertex[pass.frame.frame_index][level]
        vk.CmdBindVertexBuffers(pass.frame.command_buffer, 0, 1, &level_buffer.handle, &offset)
        if level == 0 {
            vk.CmdDrawIndexed(pass.frame.command_buffer, world_renderer.clipmap_full_indices, 1, 0, 0, 0)
        } else {
            vk.CmdDrawIndexed(
                pass.frame.command_buffer,
                world_renderer.clipmap_ring_indices,
                1,
                world_renderer.clipmap_ring_first,
                0,
                0,
            )
        }
    }
}

world_pass :: proc(pass: ^rl.World_Pass_Context, _: rawptr) {
    if !world_renderer.initialized && !world_renderer_create(pass.ctx) do return
    editor := world_renderer.editor
    if editor == nil do return
    world_build(editor)
    clipmap_update(editor, int(pass.frame.frame_index))
    buffer := &world_renderer.vertex[pass.frame.frame_index]
    road_buffer := &world_renderer.road_vertex[pass.frame.frame_index]
    foliage_buffer := &world_renderer.foliage_vertex[pass.frame.frame_index]
    if len(world_renderer.vertices) > 0 {
        mem.copy_non_overlapping(
            buffer.mapped,
            raw_data(world_renderer.vertices[:]),
            len(world_renderer.vertices) * size_of(World_Vertex),
        )
    }
    if len(world_renderer.road_vertices) > 0 {
        mem.copy_non_overlapping(
            road_buffer.mapped,
            raw_data(world_renderer.road_vertices[:]),
            len(world_renderer.road_vertices) * size_of(World_Vertex),
        )
    }
    if len(world_renderer.foliage_vertices) > 0 {
        mem.copy_non_overlapping(
            foliage_buffer.mapped,
            raw_data(world_renderer.foliage_vertices[:]),
            len(world_renderer.foliage_vertices) * size_of(Foliage_Vertex),
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
    pipeline_index := pass.color_format == vk.Format.R16G16B16A16_SFLOAT ? 1 : 0
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    sky := atmosphere.sample(&editor.atmosphere)
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
        sun             = {sky.sun_direction[0], sky.sun_direction[1], sky.sun_direction[2], sky.daylight},
    }
    sky_push := Sky_Push {
        camera_right   = {
            camera.right.x,
            camera.right.y,
            camera.right.z,
            f32(pass.framebuffer_extent.width) / f32(max(pass.framebuffer_extent.height, 1)),
        },
        camera_up      = {camera.up.x, camera.up.y, camera.up.z, camera.focal_length},
        camera_forward = {camera.forward.x, camera.forward.y, camera.forward.z, 0},
        sun_direction  = {sky.sun_direction[0], sky.sun_direction[1], sky.sun_direction[2], f32(sky.cloud_seed)},
        time_light     = {sky.world_minutes, sky.cloud_time_seconds, sky.daylight, sky.twilight},
        wind_cloud     = {
            sky.weather.wind[0],
            sky.weather.wind[1],
            sky.weather.cloud_cover,
            sky.weather.precipitation,
        },
        haze_severity  = {sky.weather.haze, sky.weather.severity, 0, 0},
    }
    offset := vk.DeviceSize(0)
    graph_context := Render_Graph_Context {
        pass           = pass,
        buffer         = buffer,
        road_buffer    = road_buffer,
        foliage_buffer = foliage_buffer,
        offset         = offset,
        pipeline_index = pipeline_index,
        world_push     = world_push,
        sky_push       = sky_push,
    }
    if !world_render_graph_ready {
        world_render_graph_ready = adriatic_render_graph(&world_render_graph)
    }
    if world_render_graph_ready do _ = render_graph.execute(&world_render_graph, &graph_context)
}

world_renderer_attach :: proc(editor: ^Editor) {
    world_renderer.editor = editor
    rl.SetWorldPass(world_pass)
    rl.SetUIPass(imgui_ui_pass)
}

world_renderer_destroy :: proc() {
    if !world_renderer.initialized do return
    _ = vk.DeviceWaitIdle(world_renderer.ctx.device)
    imgui_destroy()
    for &buffer in world_renderer.vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.road_vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.foliage_vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for frame in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
        for level in 0 ..< terrain.CLIPMAP_LEVELS {
            engine.vk_destroy_buffer(world_renderer.ctx, &world_renderer.clipmap_vertex[frame][level])
        }
    }
    engine.vk_destroy_buffer(world_renderer.ctx, &world_renderer.clipmap_index)
    roads.mesh_destroy(&world_renderer.road_mesh)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.road_pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.sky_pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.particle_pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.foliage_pipelines)
    resources.image_destroy(&world_renderer.foliage_atlas, world_renderer.ctx)
    if world_renderer.layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(world_renderer.ctx.device, world_renderer.layout, nil)
    if world_renderer.sky_layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(world_renderer.ctx.device, world_renderer.sky_layout, nil)
    if world_renderer.foliage_layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(world_renderer.ctx.device, world_renderer.foliage_layout, nil)
    if world_renderer.foliage_descriptor_pool != vk.DescriptorPool(0) {
        vk.DestroyDescriptorPool(world_renderer.ctx.device, world_renderer.foliage_descriptor_pool, nil)
    }
    if world_renderer.foliage_descriptor_layout != vk.DescriptorSetLayout(0) {
        vk.DestroyDescriptorSetLayout(world_renderer.ctx.device, world_renderer.foliage_descriptor_layout, nil)
    }
    delete(world_renderer.vertices)
    delete(world_renderer.road_vertices)
    delete(world_renderer.foliage_vertices)
    world_renderer = {}
}
