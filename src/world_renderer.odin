package main

import atmosphere "../packages/atmosphere"
import particles "../packages/particles"
import render_graph "../packages/render_graph"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:math"
import "core:mem"
import vk "vendor:vulkan"
import rl "zelda_engine:canvas2d"
import engine "zelda_engine:engine"
import render3d "zelda_engine:render3d"

WORLD_VERTEX_CAPACITY :: 32_000
CLIPMAP_GRID_RESOLUTION :: (terrain.RING_RESOLUTION - 1) / 2 + 2
CLIPMAP_VERTEX_COUNT :: CLIPMAP_GRID_RESOLUTION * CLIPMAP_GRID_RESOLUTION
CLIPMAP_FULL_INDEX_COUNT :: (CLIPMAP_GRID_RESOLUTION - 1) * (CLIPMAP_GRID_RESOLUTION - 1) * 6

// Keep the world pass useful beyond the immediate flight envelope. The
// clipmap already provides this coverage; these values prevent the camera
// projection, fog, and ocean fallback from hiding it prematurely.
WORLD_FAR_CLIP :: f32(12000)
WORLD_FOG_START :: f32(4500)
WORLD_FOG_END :: f32(11000)

World_Vertex :: struct {
    position: [3]f32,
    color:    [4]f32,
    kind:     f32,
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
    editor:               ^Editor,
    ctx:                  ^engine.Vk_Context,
    pipelines:            [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    sky_pipelines:        [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    particle_pipelines:   [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    layout:               vk.PipelineLayout,
    sky_layout:           vk.PipelineLayout,
    vertex:               [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    vertices:             [dynamic]World_Vertex,
    clipmap_vertex:       [engine.MAX_FRAMES_IN_FLIGHT][terrain.CLIPMAP_LEVELS]engine.Vk_Buffer,
    clipmap_index:        engine.Vk_Buffer,
    clipmap_full_indices: u32,
    clipmap_ring_first:   u32,
    clipmap_ring_indices: u32,
    clipmap_revision:     [engine.MAX_FRAMES_IN_FLIGHT]u64,
    clipmap_center:       [engine.MAX_FRAMES_IN_FLIGHT][terrain.CLIPMAP_LEVELS][2]f32,
    clipmap_valid:        [engine.MAX_FRAMES_IN_FLIGHT][terrain.CLIPMAP_LEVELS]bool,
    initialized:          bool,
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

world_vertex :: proc(point: third_person.Vec3, color: rl.Color) -> World_Vertex {
    return {{point.x, point.y, point.z}, world_color(color), 0}
}

world_water_vertex :: proc(point: third_person.Vec3, color: rl.Color) -> World_Vertex {
    return {{point.x, point.y, point.z}, world_color(color), 1}
}

world_triangle :: proc(a, b, c: third_person.Vec3, color: rl.Color) {
    if len(world_renderer.vertices) + 3 > WORLD_VERTEX_CAPACITY do return
    append(&world_renderer.vertices, world_vertex(a, color), world_vertex(b, color), world_vertex(c, color))
}

world_triangle_colored :: proc(a, b, c: third_person.Vec3, color_a, color_b, color_c: rl.Color) {
    if len(world_renderer.vertices) + 3 > WORLD_VERTEX_CAPACITY do return
    append(&world_renderer.vertices, world_vertex(a, color_a), world_vertex(b, color_b), world_vertex(c, color_c))
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

world_ocean :: proc(editor: ^Editor) {
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_postale(editor) ? editor.flight_camera.focal_length : 1.35,
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
            world_water_quad({x0, ocean_y, z0}, {x1, ocean_y, z0}, {x1, ocean_y, z1}, {x0, ocean_y, z1}, color)
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
    append(indices, a, b, c, a, c, d)
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
        if !editor.structure_force_box && !editor.structure_cliff_mode {
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
        bottom: [6]third_person.Vec3
        top: [6]third_person.Vec3
        for segment in 0 ..< 6 {
            angle := f32(segment) * math.PI * 2 / 6
            jitter_scale := 1 + f32(math.sin(f64(f32(structure.seed) * .009 + f32(tuft) * 1.7 + f32(segment)))) * .12
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
            world_tx, world_tz := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x + math.cos(angle) * bush_width * .58,
                local_z + math.sin(angle) * bush_depth * .58,
                structure.rotation,
            )
            top[segment] = {world_tx, base_y + bush_height * .62, world_tz}
        }
        for segment in 0 ..< 6 {
            next := (segment + 1) % 6
            bush_color := segment % 2 == 0 ? rl.Color{67, 94, 38, 255} : rl.Color{91, 119, 44, 255}
            world_triangle(bottom[segment], bottom[next], top[next], bush_color)
            world_triangle(bottom[segment], top[next], top[segment], bush_color)
        }
        bush_cap := third_person.Vec3{0, base_y + bush_height, 0}
        bush_cap.x, bush_cap.z = world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x,
            local_z,
            structure.rotation,
        )
        for segment in 0 ..< 6 {
            world_triangle(top[segment], bush_cap, top[(segment + 1) % 6], {118, 143, 57, 255})
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
        foliage := tuft % 2 == 0 ? rl.Color{54, 111, 67, 255} : rl.Color{72, 132, 76, 255}
        world_triangle(base_left, tip, base_right, foliage)
    }
}

world_structures :: proc(editor: ^Editor) {
    if editor == nil do return
    for index in 0 ..< editor.project.structure_count {
        structure := editor.project.structures[index]
        world_formation(structure)
        if index == editor.structure_selected && !editor.in_map {
            world_structure_frame(structure, structure.base_y + structure.height, {244, 226, 122, 255})
        }
    }
    if editor.structure_placing {
        world_structure_preview_cluster(editor)
    }
    world_curve_preview(editor)
}

world_aircraft :: proc(editor: ^Editor) {
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
    libellula := vehicles.libellula_mesh()
    turns := f32(rl.GetTime()) * .35
    vehicles.animate_libellula_mesh(&libellula, turns, turns + .333, turns + .667)
    for triangle in vehicles.mesh_triangles(&libellula) {
        a := libellula.vertices[triangle.a]
        b := libellula.vertices[triangle.b]
        c := libellula.vertices[triangle.c]
        world_triangle(
            libellula_vertex_world(editor.libellula.position, a.position, .72),
            libellula_vertex_world(editor.libellula.position, b.position, .72),
            libellula_vertex_world(editor.libellula.position, c.position, .72),
            aircraft_part_color(a.part),
        )
    }
}

libellula_vertex_world :: proc(origin: third_person.Vec3, position: [3]f32, scale: f32) -> third_person.Vec3 {
    return {x = origin.x + position[0] * scale, y = origin.y + position[1] * scale, z = origin.z - position[2] * scale}
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
    origin := editor.car.position
    mesh := vehicles.simple_car_mesh()
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

world_character :: proc(editor: ^Editor) {
    if !editor.in_map || editor.pilot.mode != .On_Foot do return
    p := editor.player.position
    world_box({p.x, p.y + .72, p.z}, {.42, 1.15, .28}, {42, 213, 201, 255})
    world_box({p.x, p.y + 1.48, p.z}, {.34, .34, .34}, {247, 221, 167, 255})
    forward := third_person.Vec3 {
        x = -math.sin(editor.player.facing_yaw_radians),
        z = -math.cos(editor.player.facing_yaw_radians),
    }
    world_box({p.x + forward.x * .25, p.y + 1.16, p.z + forward.z * .25}, {.16, .16, .55}, {247, 221, 167, 255})
}

world_brush :: proc(editor: ^Editor) {
    if editor.in_map do return
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_postale(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    mouse, inside := rl.GetWorldMousePosition()
    if !inside do return
    x, z, hit := terrain_under_cursor_3d(editor, camera, mouse, ADRIATIC_WORLD_WIDTH, ADRIATIC_WORLD_HEIGHT)
    if !hit do return
    segments := 48
    color := rl.Color{230, 244, 218, 230}
    for i in 0 ..< segments {
        a0 := f32(i) * 2 * math.PI / f32(segments)
        a1 := f32(i + 1) * 2 * math.PI / f32(segments)
        p0 := third_person.Vec3 {
            x = x + math.cos(a0) * editor.radius,
            z = z + math.sin(a0) * editor.radius,
        }
        p1 := third_person.Vec3 {
            x = x + math.cos(a1) * editor.radius,
            z = z + math.sin(a1) * editor.radius,
        }
        p0.y = terrain.sample_height(&editor.project, 0, p0.x, p0.z) + .10
        p1.y = terrain.sample_height(&editor.project, 0, p1.x, p1.z) + .10
        center := third_person.Vec3 {
            x = x,
            y = terrain.sample_height(&editor.project, 0, x, z) + .09,
            z = z,
        }
        world_triangle(center, p0, p1, color)
    }
}

world_build :: proc(editor: ^Editor) {
    clear(&world_renderer.vertices)
    // Depth testing makes submission order independent. Put authored gameplay
    // meshes first so dense terrain can consume only the remaining capacity
    // instead of silently dropping vehicles at the end of the frame.
    world_ocean(editor)
    world_infrastructure(editor)
    world_structures(editor)
    world_aircraft(editor)
    world_car(editor)
    world_character(editor)
    world_brush(editor)
    world_particles_cpu(editor)
    world_vehicle_particles(editor)
    world_wing_trails(editor)
}

world_particles_cpu :: proc(editor: ^Editor) {
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_postale(editor) ? editor.flight_camera.focal_length : 1.35,
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

world_vehicle_particle :: proc(camera: Perspective_Camera, particle: particles.Vehicle_Particle, color: rl.Color) {
    fade := clamp(particle.life / particle.max_life, 0, 1)
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
    alpha := u8(f32(color.a) * fade)
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
        editor.in_map && driving_postale(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    for particle in editor.vehicle_effects.dust[:editor.vehicle_effects.dust_count] {
        world_vehicle_particle(camera, particle, {148, 105, 68, 155})
    }
    for particle in editor.vehicle_effects.exhaust[:editor.vehicle_effects.exhaust_count] {
        world_vehicle_particle(camera, particle, {112, 119, 116, 120})
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
        editor.in_map && driving_postale(editor) ? editor.flight_camera.focal_length : 1.35,
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
    attrs := [3]vk.VertexInputAttributeDescription {
        {location = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(World_Vertex, position))},
        {location = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(World_Vertex, color))},
        {location = 2, format = .R32_SFLOAT, offset = u32(offset_of(World_Vertex, kind))},
    }
    vi := vk.PipelineVertexInputStateCreateInfo {
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount   = 1,
        pVertexBindingDescriptions      = &binding,
        vertexAttributeDescriptionCount = 3,
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
        cullMode    = {},
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
        blendEnable    = false,
        colorWriteMask = {.R, .G, .B, .A},
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
    if len(world_renderer.vertices) > 0 {
        mem.copy_non_overlapping(
            buffer.mapped,
            raw_data(world_renderer.vertices[:]),
            len(world_renderer.vertices) * size_of(World_Vertex),
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
        editor.in_map && driving_postale(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    sky := atmosphere.sample(&editor.atmosphere)
    fog := world_sky_horizon_color(sky)
    world_push := World_Push {
        camera_position = {
            camera.position.x,
            camera.position.y,
            camera.position.z,
            editor.in_map ? f32(.08) : f32(100),
        },
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
    if len(world_renderer.vertices) > 0 {
        mem.copy_non_overlapping(
            buffer.mapped,
            raw_data(world_renderer.vertices[:]),
            len(world_renderer.vertices) * size_of(World_Vertex),
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
        editor.in_map && driving_postale(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    sky := atmosphere.sample(&editor.atmosphere)
    fog := world_sky_horizon_color(sky)
    world_push := World_Push {
        camera_position = {
            camera.position.x,
            camera.position.y,
            camera.position.z,
            editor.in_map ? f32(.08) : f32(100),
        },
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
}

world_renderer_destroy :: proc() {
    if !world_renderer.initialized do return
    _ = vk.DeviceWaitIdle(world_renderer.ctx.device)
    for &buffer in world_renderer.vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for frame in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
        for level in 0 ..< terrain.CLIPMAP_LEVELS {
            engine.vk_destroy_buffer(world_renderer.ctx, &world_renderer.clipmap_vertex[frame][level])
        }
    }
    engine.vk_destroy_buffer(world_renderer.ctx, &world_renderer.clipmap_index)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.sky_pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.particle_pipelines)
    if world_renderer.layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(world_renderer.ctx.device, world_renderer.layout, nil)
    if world_renderer.sky_layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(world_renderer.ctx.device, world_renderer.sky_layout, nil)
    delete(world_renderer.vertices)
    world_renderer = {}
}
