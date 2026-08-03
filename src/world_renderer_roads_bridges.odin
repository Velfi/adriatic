package main
import "core:math"

import bridges "../packages/bridges"
import dio "../packages/dio"
import roads "../packages/roads"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math/linalg"
import vk "vendor:vulkan"
import canvas2d "zelda_engine:canvas2d"

world_quad_to :: #force_inline proc(
    destination: ^[dynamic]World_Vertex,
    a, b, c, d: third_person.Vec3,
    color: canvas2d.Color,
) {
    world_triangle_to(destination, a, b, c, color)
    world_triangle_to(destination, a, c, d, color)
}

world_box_rotated_to :: proc(
    destination: ^[dynamic]World_Vertex,
    center, size: third_person.Vec3,
    rotation: f32,
    color: canvas2d.Color,
) {
    x, y, z := size.x * .5, size.y * .5, size.z * .5
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
    p: [8]third_person.Vec3
    for index in 0 ..< 8 {
        world_x, world_z := world_rotate_xz(center.x, center.z, local[index][0], local[index][2], rotation)
        p[index] = {world_x, center.y + local[index][1], world_z}
    }
    world_quad_to(destination, p[0], p[3], p[2], p[1], color)
    world_quad_to(destination, p[4], p[5], p[6], p[7], color)
    world_quad_to(destination, p[0], p[4], p[7], p[3], color)
    world_quad_to(destination, p[1], p[2], p[6], p[5], color)
    world_quad_to(destination, p[3], p[7], p[6], p[2], color)
    world_quad_to(destination, p[0], p[1], p[5], p[4], color)
}

world_settlement_bridge_plan :: proc(
    editor: ^Editor,
    center: roads.Vec3,
    length, width, clearance: f32,
    edge_index: int,
) -> (
    bridges.Plan,
    bool,
) {
    if editor == nil || !editor.settlement_plan.valid do return {}, false
    settlement := &editor.settlement_plan
    dx := center.x - settlement.request.center[0]
    dz := center.z - settlement.request.center[1]
    settlement_radius := settlement.request.radius * 1.35
    if dx * dx + dz * dz > settlement_radius * settlement_radius do return {}, false

    archetype := bridges.Archetype.Dalmatian_Multi_Arch
    if settlement.request.region == .Aegean {
        archetype = settlement.request.scale == .Village || length < 20 ? .Cycladic_Rural : .Aegean_Fortress
    } else if length < 18 && settlement.request.scale != .Village {
        archetype = .Venetian_Canal
    }
    config := bridges.defaults(archetype)
    config.length = clamp(length, f32(10), f32(80))
    config.width =
        settlement.request.region == .Aegean ? min(max(width, f32(2.2)), f32(4.5)) : clamp(width, f32(2.2), f32(10))
    config.clearance = clamp(clearance, f32(2.5), f32(16))
    if archetype == .Dalmatian_Multi_Arch {
        config.span_count = clamp(int(math.round(f64(config.length / 6))), 2, bridges.MAX_SPANS)
    }
    seed := settlement.request.seed ~ u32(edge_index + 1) * u32(0x9e3779b9)
    plan := bridges.generate(seed, config)
    return plan, plan.valid
}

world_road_bridge_extent :: proc(editor: ^Editor, graph: ^roads.Graph, edge_index: int) -> (f32, f32, bool) {
    if editor == nil || graph == nil || edge_index < 0 || edge_index >= graph.edge_count do return 0, 0, false
    edge := graph.edges[edge_index]
    if edge.engineering_designed {
        return 0, 1, edge.structure_kind == .Bridge
    }
    SAMPLES :: 48
    first, last := -1, -1
    for sample in 0 ..= SAMPLES {
        t := f32(sample) / f32(SAMPLES)
        point := roads.edge_point(graph, edge, t)
        if terrain.active_waterway_at(&editor.project, 0, point.x, point.z) {
            if first < 0 do first = sample
            last = sample
        }
    }
    if first < 0 do return 0, 0, false
    return max(f32(0), f32(first - 1) / f32(SAMPLES)), min(f32(1), f32(last + 1) / f32(SAMPLES)), true
}

world_road_bridge_arch_fraction :: proc(shape: bridges.Arch_Shape, u: f32) -> f32 {
    switch shape {
    case .Semicircular, .Segmental:
        return math.sqrt(max(f32(0), 1 - u * u))
    case .Slightly_Pointed:
        semicircle := math.sqrt(max(f32(0), 1 - u * u))
        return (semicircle + max(f32(0), 1 - abs(u)) * .20) / 1.20
    }
    return 0
}

world_road_bridges_build :: proc(editor: ^Editor, graph: ^roads.Graph) {
    if editor == nil || graph == nil do return
    stone := canvas2d.Color{133, 128, 112, 255}
    rail := canvas2d.Color{172, 165, 143, 255}
    for edge, edge_index in graph.edges[:graph.edge_count] {
        first_vertex := len(world_renderer.road_geometry_cache)
        if edge.engineering_designed && edge.structure_kind == .Culvert {
            center := roads.edge_point(graph, edge, .5)
            tangent := roads.edge_tangent(graph, edge, .5)
            yaw := f32(math.atan2(f64(-tangent.x), f64(tangent.z))) + math.PI * .5
            bed_y := terrain.sample_surface_height(&editor.project, 0, center.x, center.z)
            length := (edge.half_width + edge.shoulder_width) * 2 + 1.2
            // A dark barrel and pale headwalls make the persisted culvert
            // legible without introducing a second infrastructure system.
            world_box_rotated_to(
                &world_renderer.road_geometry_cache,
                {center.x, bed_y + .28, center.z},
                {length, .56, .72},
                yaw,
                {67, 72, 68, 255},
            )
            sides := [2]f32{-1, 1}
            side_x, side_z := tangent.z, -tangent.x
            for side in sides {
                world_box_rotated_to(
                    &world_renderer.road_geometry_cache,
                    {center.x + side_x * side * length * .5, bed_y + .44, center.z + side_z * side * length * .5},
                    {.24, .88, 1.18},
                    yaw,
                    stone,
                )
            }
            world_road_cache_chunk_finish(first_vertex)
            continue
        }
        approximate_length := roads.edge_control_polygon_length(graph, edge)
        bridge_from, bridge_to, has_bridge := world_road_bridge_extent(editor, graph, edge_index)
        if !has_bridge do continue
        crossing_length := max(approximate_length * (bridge_to - bridge_from), f32(1))
        crossing_center := roads.edge_point(graph, edge, (bridge_from + bridge_to) * .5)
        crossing_bed := terrain.sample_surface_height(&editor.project, 0, crossing_center.x, crossing_center.z)
        crossing_deck, _ := road_bridge_deck_height(editor, edge_index, (bridge_from + bridge_to) * .5)
        regional, regional_bridge := world_settlement_bridge_plan(
            editor,
            crossing_center,
            crossing_length,
            (edge.half_width + edge.shoulder_width * .45) * 2,
            crossing_deck - crossing_bed,
            edge_index,
        )
        bridge_stone, bridge_rail := stone, rail
        if regional_bridge {
            switch regional.material {
            case .Limestone:
                bridge_stone, bridge_rail = {174, 166, 143, 255}, {205, 198, 171, 255}
            case .Travertine:
                bridge_stone, bridge_rail = {146, 137, 112, 255}, {184, 174, 145, 255}
            case .Istrian_Stone:
                bridge_stone, bridge_rail = {190, 184, 166, 255}, {218, 211, 191, 255}
            case .Slate:
                bridge_stone, bridge_rail = {104, 107, 105, 255}, {142, 145, 139, 255}
            case .Fieldstone:
                bridge_stone, bridge_rail = {126, 116, 94, 255}, {158, 147, 117, 255}
            case .Timber:
                bridge_stone, bridge_rail = {91, 64, 41, 255}, {124, 88, 52, 255}
            case .Iron:
                bridge_stone, bridge_rail = {61, 67, 64, 255}, {88, 96, 92, 255}
            }
        }
        segment_count := clamp(int(math.ceil(f64(approximate_length / 2))), 2, 512)
        width := (edge.half_width + edge.shoulder_width * .45) * 2
        for segment_index in 0 ..< segment_count {
            t0 := f32(segment_index) / f32(segment_count)
            t1 := f32(segment_index + 1) / f32(segment_count)
            tm := (t0 + t1) * .5
            deck_y, bridge := road_bridge_deck_height(editor, edge_index, tm)
            if !bridge do continue
            p0, p1 := roads.edge_point(graph, edge, t0), roads.edge_point(graph, edge, t1)
            pm := roads.edge_point(graph, edge, tm)
            dx, dz := p1.x - p0.x, p1.z - p0.z
            length := f32(math.sqrt(f64(dx * dx + dz * dz)))
            if length <= .001 do continue
            yaw := f32(math.atan2(f64(-dx), f64(dz)))
            world_box_rotated_to(
                &world_renderer.road_geometry_cache,
                {pm.x, deck_y - .20, pm.z},
                {width, .38, length + .08},
                yaw,
                bridge_stone,
            )
            side_x, side_z := dz / length, -dx / length
            sides := [2]f32{-1, 1}
            for side in sides {
                world_box_rotated_to(
                    &world_renderer.road_geometry_cache,
                    {
                        pm.x + side_x * side * width * .48,
                        deck_y + (regional_bridge ? regional.parapet_height * .5 : f32(.22)),
                        pm.z + side_z * side * width * .48,
                    },
                    {
                        regional_bridge ? regional.parapet_width : f32(.16),
                        regional_bridge ? regional.parapet_height : f32(.72),
                        length + .10,
                    },
                    yaw,
                    bridge_rail,
                )
            }
            bed_y := terrain.sample_surface_height(&editor.project, 0, pm.x, pm.z)
            support_height := deck_y - .38 - bed_y
            pier_here := segment_index % 4 == 2
            pier_width := f32(.42)
            if regional_bridge && regional.construction != .Framed {
                crossing_t := clamp((tm - bridge_from) / max(bridge_to - bridge_from, f32(.001)), f32(0), f32(1))
                station := (crossing_t - .5) * regional.length
                span_index := clamp(
                    int(math.floor(f64((station + regional.length * .5) / regional.span_length))),
                    0,
                    regional.pier_count,
                )
                span_center := -regional.length * .5 + (f32(span_index) + .5) * regional.span_length
                u := clamp((station - span_center) / (regional.span_length * .43), f32(-1), f32(1))
                opening_y :=
                    deck_y -
                    regional.deck_thickness -
                    regional.arch_rise +
                    world_road_bridge_arch_fraction(regional.arch_shape, u) * regional.arch_rise
                spandrel_height := deck_y - regional.deck_thickness - opening_y
                if spandrel_height > .04 {
                    world_box_rotated_to(
                        &world_renderer.road_geometry_cache,
                        {pm.x, opening_y + spandrel_height * .5, pm.z},
                        {width, spandrel_height, length + .10},
                        yaw,
                        bridge_stone,
                    )
                }
                pier_here = false
                for pier in regional.piers[:regional.pier_count] {
                    if abs(station - pier.station) <= length * .65 {
                        pier_here = true
                        pier_width = pier.width
                        break
                    }
                }
            }
            if support_height > .7 && pier_here {
                world_box_rotated_to(
                    &world_renderer.road_geometry_cache,
                    {pm.x, bed_y + support_height * .5, pm.z},
                    {max(width * .72, f32(1)), support_height, pier_width},
                    yaw,
                    bridge_stone,
                )
            }
        }
        world_road_cache_chunk_finish(first_vertex)
    }
}

@(no_instrumentation)
road_surface_color :: #force_inline proc(surface: roads.Surface, pavement: roads.Pavement) -> canvas2d.Color {
    if surface == .Verge {
        // Outer verge vertices are transparent and interpolate into the opaque
        // shoulder, revealing terrain through a soft, pavement-aware tint.
        switch pavement {
        case .Asphalt:
            return {82, 111, 67, 0}
        case .Gravel:
            return {105, 119, 70, 0}
        case .Cobblestone:
            return {126, 122, 106, 0}
        case .Dirt:
            return {118, 101, 58, 0}
        case .Steps:
            return {126, 118, 91, 0}
        }
    }
    if surface == .Shoulder {
        switch pavement {
        case .Asphalt:
            return {164, 148, 116, 255}
        case .Gravel:
            return {183, 163, 126, 255}
        case .Cobblestone:
            return {174, 168, 150, 255}
        case .Dirt:
            return {139, 96, 61, 255}
        case .Steps:
            return {150, 137, 108, 255}
        }
    }
    switch pavement {
    case .Asphalt:
        return surface == .Junction ? canvas2d.Color{86, 92, 86, 255} : canvas2d.Color{91, 97, 90, 255}
    case .Gravel:
        return {158, 143, 111, 255}
    case .Cobblestone:
        return {151, 149, 138, 255}
    case .Dirt:
        return {158, 104, 61, 255}
    case .Steps:
        return {174, 158, 126, 255}
    }
    return {91, 97, 90, 255}
}

world_road_editor_link :: proc(a, b: roads.Vec3, width: f32, color: canvas2d.Color) {
    dx, dz := b.x - a.x, b.z - a.z
    length := f32(math.sqrt(f64(dx * dx + dz * dz)))
    if length <= .001 do return
    side_x, side_z := -dz / length * width * .5, dx / length * width * .5
    lift := f32(.12)
    world_quad(
        {b.x + side_x, b.y + lift, b.z + side_z},
        {a.x + side_x, a.y + lift, a.z + side_z},
        {a.x - side_x, a.y + lift, a.z - side_z},
        {b.x - side_x, b.y + lift, b.z - side_z},
        color,
    )
}

// Road tangent grips are horizontal screen-scaled discs: readable from the
// editor camera, visually distinct from graph nodes, and considerably less
// noisy than exposing the underlying cubic control points as world-space
// boxes. The dark center preserves contrast over every pavement and terrain.
world_road_editor_grip :: proc(editor: ^Editor, position: roads.Vec3, hovered, active: bool) {
    if editor == nil do return
    camera_forward := editor.camera_pose.target - editor.camera_pose.position
    camera_forward_length := linalg.length(camera_forward)
    if camera_forward_length > .001 do camera_forward /= camera_forward_length
    camera_to_grip := third_person.Vec3{position.x, position.y, position.z} - editor.camera_pose.position
    camera_depth := max(linalg.dot(camera_to_grip, camera_forward), f32(1))
    // Perspective size is proportional to camera-space depth. Unlike radial
    // distance, this keeps grips at a stable apparent size across the view.
    outer_radius := clamp(camera_depth * .024, f32(.65), f32(5.5))
    if hovered do outer_radius *= 1.12
    if active do outer_radius *= 1.18
    inner_radius := outer_radius * .62
    center_radius := outer_radius * .18
    color := canvas2d.Color{78, 211, 238, 255}
    if hovered do color = {239, 250, 252, 255}
    if active do color = {255, 205, 70, 255}
    center := third_person.Vec3{position.x, position.y + .78, position.z}
    segments := 32
    for segment in 0 ..< segments {
        angle_0 := f32(segment) * 2 * math.PI / f32(segments)
        angle_1 := f32(segment + 1) * 2 * math.PI / f32(segments)
        direction_0 := third_person.Vec3{math.cos(angle_0), 0, math.sin(angle_0)}
        direction_1 := third_person.Vec3{math.cos(angle_1), 0, math.sin(angle_1)}
        outer_0 := center + direction_0 * outer_radius
        outer_1 := center + direction_1 * outer_radius
        outer_bottom_0 := outer_0 - third_person.Vec3{0, .42, 0}
        outer_bottom_1 := outer_1 - third_person.Vec3{0, .42, 0}
        inner_0 := center + direction_0 * inner_radius + third_person.Vec3{0, .025, 0}
        inner_1 := center + direction_1 * inner_radius + third_person.Vec3{0, .025, 0}
        dot_0 := center + direction_0 * center_radius + third_person.Vec3{0, .05, 0}
        dot_1 := center + direction_1 * center_radius + third_person.Vec3{0, .05, 0}
        // Solid top with a dark inset reads as a ring; the short outer wall
        // keeps it legible from low editor-camera angles.
        world_triangle(center, outer_1, outer_0, color)
        world_quad(outer_bottom_0, outer_bottom_1, outer_1, outer_0, {color.r, color.g, color.b, 225})
        world_triangle(center + third_person.Vec3{0, .02, 0}, inner_1, inner_0, {20, 34, 39, 225})
        world_triangle(center + third_person.Vec3{0, .045, 0}, dot_1, dot_0, color)
    }
}

@(no_instrumentation)
world_road_vertex :: #force_inline proc(editor: ^Editor, vertex: roads.Vertex, color: canvas2d.Color) -> World_Vertex {
    point := road_world_point(editor, vertex)
    // Road UV and pavement live in the normal channel because the dedicated
    // road pass reconstructs its geometric normal. Half-width and a junction
    // flag travel in material. Road use intensity travels in the otherwise
    // unused UV channel; the shader already receives world position directly.
    return {
        {point.x, point.y, point.z},
        world_color(color),
        .Road,
        {vertex.uv[0], vertex.uv[1], f32(vertex.pavement)},
        {vertex.road_half_width, vertex.surface == .Junction ? 1 : 0},
        {vertex.use_intensity, 0},
    }
}

@(no_instrumentation)
world_road_triangle_colored :: #force_inline proc(
    editor: ^Editor,
    destination: ^[dynamic]World_Vertex,
    a, b, c: roads.Vertex,
    color_a, color_b, color_c: canvas2d.Color,
) {
    // Step splines use discrete terrain-fitted solids below rather than the
    // road baker's continuous ribbon.
    if a.pavement == .Steps || b.pavement == .Steps || c.pavement == .Steps do return
    requires_land := true
    source_edge := max(max(a.source_edge, b.source_edge), c.source_edge)
    if source_edge > 0 && source_edge <= editor.project.road_graph.edge_count {
        edge := editor.project.road_graph.edges[source_edge - 1]
        requires_land = !edge.engineering_designed
    }
    if requires_land {
        land_threshold := editor.project.sea_level + .04
        if terrain.sample_surface_height(&editor.project, 0, a.position.x, a.position.z) <= land_threshold ||
           terrain.sample_surface_height(&editor.project, 0, b.position.x, b.position.z) <= land_threshold ||
           terrain.sample_surface_height(&editor.project, 0, c.position.x, c.position.z) <= land_threshold {
            return
        }
    }
    append(
        destination,
        world_road_vertex(editor, a, color_a),
        world_road_vertex(editor, b, color_b),
        world_road_vertex(editor, c, color_c),
    )
}

world_spline_steps :: proc(editor: ^Editor, graph: ^roads.Graph) {
    if editor == nil || graph == nil do return
    for edge in graph.edges[:graph.edge_count] {
        if edge.pavement != .Steps do continue
        approximate_length := roads.edge_control_polygon_length(graph, edge)
        // A domestic exterior stair reads naturally around a 65 cm going.
        // Bound the tessellation so an accidentally world-scale spline cannot
        // overwhelm the shared world-geometry buffer.
        tread_count := clamp(int(math.ceil(f64(approximate_length / .65))), 2, 512)
        width := edge.half_width * 2
        for tread in 0 ..< tread_count {
            t0 := f32(tread) / f32(tread_count)
            t1 := f32(tread + 1) / f32(tread_count)
            tm := (t0 + t1) * .5
            p0 := roads.edge_point(graph, edge, t0)
            p1 := roads.edge_point(graph, edge, t1)
            pm := roads.edge_point(graph, edge, tm)
            ground_0 := terrain.sample_surface_height(&editor.project, 0, p0.x, p0.z)
            ground_1 := terrain.sample_surface_height(&editor.project, 0, p1.x, p1.z)
            ground_mid := terrain.sample_surface_height(&editor.project, 0, pm.x, pm.z)
            top := ground_mid + .12
            bottom := min(min(ground_0, ground_1), ground_mid) - .04
            height := max(top - bottom, f32(.12))
            dx, dz := p1.x - p0.x, p1.z - p0.z
            length := f32(math.sqrt(f64(dx * dx + dz * dz)))
            if length <= .001 do continue
            yaw := f32(math.atan2(f64(-dx), f64(dz)))
            color := canvas2d.Color{174, 158, 126, 255}
            if tread % 4 == 1 do color = {165, 149, 119, 255}
            world_box_rotated({pm.x, bottom + height * .5, pm.z}, {width, height, length + .04}, yaw, color)
        }
    }
}

world_road_cache_chunk_finish :: proc(first_vertex: int) {
    vertex_count := len(world_renderer.road_geometry_cache) - first_vertex
    if vertex_count <= 0 do return
    first_position := world_renderer.road_geometry_cache[first_vertex].position
    minimum, maximum := first_position, first_position
    for vertex in world_renderer.road_geometry_cache[first_vertex + 1:first_vertex + vertex_count] {
        for axis in 0 ..< 3 {
            minimum[axis] = min(minimum[axis], vertex.position[axis])
            maximum[axis] = max(maximum[axis], vertex.position[axis])
        }
    }
    center := third_person.Vec3 {
        (minimum[0] + maximum[0]) * .5,
        (minimum[1] + maximum[1]) * .5,
        (minimum[2] + maximum[2]) * .5,
    }
    radius_squared: f32
    for vertex in world_renderer.road_geometry_cache[first_vertex:first_vertex + vertex_count] {
        dx := vertex.position[0] - center.x
        dy := vertex.position[1] - center.y
        dz := vertex.position[2] - center.z
        radius_squared = max(radius_squared, dx * dx + dy * dy + dz * dz)
    }
    append(
        &world_renderer.road_geometry_chunks,
        Road_Geometry_Cache_Chunk {
            first_vertex = first_vertex,
            vertex_count = vertex_count,
            center = center,
            radius = f32(math.sqrt(f64(radius_squared))),
        },
    )
}

world_retained_roads_prepare :: proc(editor: ^Editor) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "retained_roads_prepare")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    if editor == nil do return
    graph := &editor.project.road_graph
    if !world_renderer.road_graph_valid || world_renderer.road_revision != editor.project.revision {
        if !world_renderer.road_graph_valid || world_renderer.road_graph != graph^ {
            roads.mesh_destroy(&world_renderer.road_mesh)
            if graph.edge_count > 0 do world_renderer.road_mesh = roads.bake(graph)
            world_renderer.road_graph = graph^
            world_renderer.road_graph_valid = true
        }
        world_renderer.road_revision = editor.project.revision
    }
    mesh := &world_renderer.road_mesh
    road_geometry_cached :=
        world_renderer.road_geometry_valid &&
        world_renderer.road_geometry_revision == editor.project.revision &&
        world_renderer.road_geometry_terrain_revision == editor.terrain_revision
    if !road_geometry_cached {
        clear(&world_renderer.road_geometry_cache)
        clear(&world_renderer.road_geometry_chunks)
        for mesh_chunk in mesh.chunks {
            first_vertex := len(world_renderer.road_geometry_cache)
            triangle_end := mesh_chunk.first_index + mesh_chunk.index_count
            for triangle_index := mesh_chunk.first_index; triangle_index < triangle_end; triangle_index += 3 {
                a := mesh.vertices[mesh.indices[triangle_index]]
                b := mesh.vertices[mesh.indices[triangle_index + 1]]
                c := mesh.vertices[mesh.indices[triangle_index + 2]]
                world_road_triangle_colored(
                    editor,
                    &world_renderer.road_geometry_cache,
                    a,
                    b,
                    c,
                    road_surface_color(a.surface, a.pavement),
                    road_surface_color(b.surface, b.pavement),
                    road_surface_color(c.surface, c.pavement),
                )
            }
            world_road_cache_chunk_finish(first_vertex)
        }
        // Bridge solids share the retained road cache and are rebuilt only
        // when road topology or terrain changes.
        world_road_bridges_build(editor, graph)
        world_renderer.road_geometry_revision = editor.project.revision
        world_renderer.road_geometry_terrain_revision = editor.terrain_revision
        world_renderer.road_geometry_valid = true
        world_renderer.road_geometry_gpu_revision += 1
        if world_renderer.road_geometry_gpu_revision == 0 {
            world_renderer.road_geometry_gpu_revision = 1
            world_renderer.road_geometry_uploaded_revision = {}
        }
    }
    for chunk in world_renderer.road_geometry_chunks {
        if !world_sphere_in_view(editor, chunk.center, chunk.radius, 1) do continue
        append(
            &world_renderer.road_draw_commands,
            vk.DrawIndirectCommand {
                vertexCount = u32(chunk.vertex_count),
                instanceCount = 1,
                firstVertex = u32(chunk.first_vertex),
            },
        )
    }
}
