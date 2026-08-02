package main
import "core:math"

import boats "../packages/boats"
import roads "../packages/roads"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

@(no_instrumentation)
world_settlement_material_quad :: #force_inline proc(
    a, b, c, d: third_person.Vec3,
    material: Settlement_Material,
    uv_width, uv_height: f32,
    uv_origin: [2]f32 = {},
) {
    white := canvas2d.Color{255, 255, 255, 255}
    vertices := [6]World_Vertex {
        world_vertex(a, white),
        world_vertex(b, white),
        world_vertex(c, white),
        world_vertex(a, white),
        world_vertex(c, white),
        world_vertex(d, white),
    }
    u0, v0 := uv_origin.x, uv_origin.y
    u1, v1 := u0 + uv_width, v0 + uv_height
    uvs := [6][2]f32{{u0, v1}, {u1, v1}, {u1, v0}, {u0, v1}, {u1, v0}, {u0, v0}}
    normal := linalg.normalize0(linalg.cross(b - a, c - a))
    for &vertex, index in vertices {
        vertex.kind = .Settlement_Material
        vertex.normal = {normal.x, normal.y, normal.z}
        vertex.material = {f32(material), 0}
        vertex.uv = uvs[index]
    }
    append(&world_renderer.vertices, ..vertices[:])
}

@(no_instrumentation)
world_ellipse_material_uv :: proc(
    center: third_person.Vec3,
    radius_x, radius_z, rotation: f32,
    color: canvas2d.Color,
    kind: World_Material_Kind,
    slope_x: f32 = 0,
    slope_z: f32 = 0,
    directionality: f32 = 0,
    project: ^terrain.Project = nil,
    terrain_lift: f32 = 0,
    surface_editor: ^Editor = nil,
) {
    segments := 12
    // Circumscribe the support polygon around the analytic ellipse. With an
    // inscribed fan, the midpoint of every chord lies inside UV radius one and
    // retains non-zero alpha, revealing twelve straight pool edges. Extending
    // both position and UV radius by sec(pi / n) places the shader's zero-alpha
    // ellipse inside every edge; corner fragments are discarded.
    edge_scale := f32(1) / math.cos(f32(math.PI) / f32(segments))
    ring: [12]third_person.Vec3
    ring_uv: [12][2]f32
    for segment in 0 ..< segments {
        angle := f32(segment) / f32(segments) * 2 * f32(math.PI)
        point_x, point_z := world_rotate_xz(
            center.x,
            center.z,
            math.cos(angle) * radius_x * edge_scale,
            math.sin(angle) * radius_z * edge_scale,
            rotation,
        )
        point_y := center.y + (point_x - center.x) * slope_x + (point_z - center.z) * slope_z
        if surface_editor != nil {
            point_y = mouse_surface_height(surface_editor, point_x, point_z) + terrain_lift
        } else if project != nil {
            point_y = terrain.sample_height(project, 0, point_x, point_z) + terrain_lift
        }
        ring[segment] = {point_x, point_y, point_z}
        ring_uv[segment] = {.5 + math.cos(angle) * .5 * edge_scale, .5 + math.sin(angle) * .5 * edge_scale}
    }
    for segment in 0 ..< segments {
        next := (segment + 1) % segments
        vertices := [3]World_Vertex {
            world_vertex(center, color),
            world_vertex(ring[next], color),
            world_vertex(ring[segment], color),
        }
        vertices[0].uv = {.5, .5}
        vertices[1].uv = ring_uv[next]
        vertices[2].uv = ring_uv[segment]
        for &vertex in vertices {
            vertex.kind = kind
            vertex.material[0] = directionality
        }
        append(&world_renderer.vertices, ..vertices[:])
    }
}

world_disc_material_uv :: proc(
    center: third_person.Vec3,
    radius: f32,
    color: canvas2d.Color,
    kind: World_Material_Kind,
) {
    world_ellipse_material_uv(center, radius, radius, 0, color, kind)
}

world_billboard_material_uv :: proc(
    editor: ^Editor,
    center: third_person.Vec3,
    width, height: f32,
    color: canvas2d.Color,
    kind: World_Material_Kind,
    late_submit: bool = false,
) {
    if editor == nil do return
    if kind == .Emissive_Halo {
        // Match the fragment shader's off threshold on the CPU. A discarded
        // transparent card still has no visual purpose in daylight, and older
        // depth-writing paths could expose it as a sky-colored façade window.
        if world_renderer.scene_daylight >= .34 do return
        camera_position := editor.camera_pose.position
        dx, dy, dz := center.x - camera_position.x, center.y - camera_position.y, center.z - camera_position.z
        distance_squared := dx * dx + dy * dy + dz * dz
        // Inside five metres the lantern geometry fills enough pixels to read
        // without a bloom card. Beyond that, retain a compact aureole so the
        // bright source connects perceptually to its much broader ground pool.
        // Match the fragment fade's zero point and avoid submitting vertices
        // that can only be discarded.
        // The matching far cutoff prevents sub-pixel lamps from forming an
        // equally bright horizon constellation and omits cards once their
        // shader visibility has reached zero.
        if distance_squared < 5 * 5 || distance_squared > 225 * 225 do return
    }
    focal_length := editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : f32(1.35)
    camera := perspective_camera(editor.camera_pose, focal_length)
    right := third_person.Vec3{camera.right.x * width * .5, camera.right.y * width * .5, camera.right.z * width * .5}
    up := third_person.Vec3{camera.up.x * height * .5, camera.up.y * height * .5, camera.up.z * height * .5}
    p0 := third_person.Vec3{center.x - right.x - up.x, center.y - right.y - up.y, center.z - right.z - up.z}
    p1 := third_person.Vec3{center.x + right.x - up.x, center.y + right.y - up.y, center.z + right.z - up.z}
    p2 := third_person.Vec3{center.x + right.x + up.x, center.y + right.y + up.y, center.z + right.z + up.z}
    p3 := third_person.Vec3{center.x - right.x + up.x, center.y - right.y + up.y, center.z - right.z + up.z}
    vertices := [6]World_Vertex {
        world_vertex(p0, color),
        world_vertex(p1, color),
        world_vertex(p2, color),
        world_vertex(p0, color),
        world_vertex(p2, color),
        world_vertex(p3, color),
    }
    vertices[0].uv = {0, 1}
    vertices[1].uv = {1, 1}
    vertices[2].uv = {1, 0}
    vertices[3].uv = {0, 1}
    vertices[4].uv = {1, 0}
    vertices[5].uv = {0, 0}
    for &vertex in vertices do vertex.kind = kind
    if late_submit {
        append(&world_renderer.late_transparent_vertices, ..vertices[:])
    } else {
        append(&world_renderer.vertices, ..vertices[:])
    }
}

world_municipal_light_pool :: proc(
    x, y, z: f32,
    project: ^terrain.Project,
    surface_lift: f32 = .20,
    radius_x: f32 = 3.75,
    radius_z: f32 = 3.75,
    rotation: f32 = 0,
    alpha: u8 = 62,
    directionality: f32 = 0,
    pool_color: canvas2d.Color = {255, 210, 145, 255},
    surface_editor: ^Editor = nil,
    late_submit: bool = false,
) {
    // A shader-shaped dodecagon keeps transparent overdraw close to the visible
    // pool while using only 36 vertices for a continuous radial falloff.
    pool_y := y
    if surface_editor != nil {
        pool_y = mouse_surface_height(surface_editor, x, z)
    } else if project != nil {
        pool_y = terrain.sample_height(project, 0, x, z)
    }
    effective_lift := surface_lift + .025
    first_vertex := len(world_renderer.vertices)
    world_ellipse_material_uv(
        {x, pool_y + effective_lift, z},
        radius_x,
        radius_z,
        rotation,
        {pool_color.r, pool_color.g, pool_color.b, alpha},
        .Emissive_Pool,
        0,
        0,
        directionality,
        project,
        effective_lift,
        surface_editor,
    )
    if late_submit {
        append(&world_renderer.late_transparent_vertices, ..world_renderer.vertices[first_vertex:])
        resize(&world_renderer.vertices, first_vertex)
    }
}

world_quad_colored :: proc(a, b, c, d: third_person.Vec3, color_a, color_b, color_c, color_d: canvas2d.Color) {
    world_triangle_colored(a, b, c, color_a, color_b, color_c)
    world_triangle_colored(a, c, d, color_a, color_c, color_d)
}

@(no_instrumentation)
world_quad_colored_smooth_lit :: #force_inline proc(
    a, b, c, d: third_person.Vec3,
    normal_a, normal_b, normal_c, normal_d: third_person.Vec3,
    color_a, color_b, color_c, color_d: canvas2d.Color,
    roughness: f32 = .9,
) {
    world_triangle_smooth_lit(a, b, c, normal_a, normal_b, normal_c, color_a, color_b, color_c, roughness)
    world_triangle_smooth_lit(a, c, d, normal_a, normal_c, normal_d, color_a, color_c, color_d, roughness)
}

@(no_instrumentation)
world_water_quad :: #force_inline proc(a, b, c, d: third_person.Vec3, color: canvas2d.Color) {
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

@(no_instrumentation)
world_ocean_quad :: #force_inline proc(editor: ^Editor, a, b, c, d: third_person.Vec3, color: canvas2d.Color) {
    append(
        &world_renderer.vertices,
        world_ocean_vertex(editor, a, color),
        world_ocean_vertex(editor, b, color),
        world_ocean_vertex(editor, c, color),
        world_ocean_vertex(editor, a, color),
        world_ocean_vertex(editor, c, color),
        world_ocean_vertex(editor, d, color),
    )
}

@(no_instrumentation)
world_water_triangle_colored :: #force_inline proc(
    a, b, c: third_person.Vec3,
    color_a, color_b, color_c: canvas2d.Color,
) {
    append(
        &world_renderer.vertices,
        world_water_vertex(a, color_a),
        world_water_vertex(b, color_b),
        world_water_vertex(c, color_c),
    )
}

@(no_instrumentation)
world_fountain_water_triangle_colored :: #force_inline proc(
    a, b, c: third_person.Vec3,
    color_a, color_b, color_c: canvas2d.Color,
) {
    append(
        &world_renderer.vertices,
        world_fountain_water_vertex(a, color_a),
        world_fountain_water_vertex(b, color_b),
        world_fountain_water_vertex(c, color_c),
    )
}

@(no_instrumentation)
world_boat_part_color :: proc(class: boats.Class, part: boats.Part) -> canvas2d.Color {
    switch part {
    case .Hull:
        switch class {
        case .Dinghy:
            return {211, 204, 169, 255}
        case .Motor:
            return {226, 231, 220, 255}
        case .Sail:
            return {215, 224, 217, 255}
        case .Fishing:
            return {56, 115, 129, 255}
        case .Tug:
            return {151, 48, 37, 255}
        }
    case .Deck:
        return {214, 199, 166, 255}
    case .Cabin:
        return class == .Tug ? canvas2d.Color{235, 205, 119, 255} : canvas2d.Color{225, 224, 205, 255}
    case .Glass:
        return {67, 115, 133, 255}
    case .Metal:
        return {68, 73, 71, 255}
    case .Sail:
        return {241, 233, 205, 255}
    case .Accent:
        return class == .Sail ? canvas2d.Color{189, 74, 51, 255} : canvas2d.Color{204, 119, 50, 255}
    case .Tire:
        return {35, 39, 38, 255}
    }
    return {220, 220, 210, 255}
}

@(no_instrumentation)
world_boat_point :: #force_inline proc(
    local: [3]f32,
    position: third_person.Vec3,
    yaw_cos, yaw_sin: f32,
) -> third_person.Vec3 {
    c, s := yaw_cos, yaw_sin
    return {position.x + local.x * c - local.z * s, position.y + local.y, position.z + local.x * s + local.z * c}
}

@(no_instrumentation)
world_boat_triangle :: proc(a, b, c: third_person.Vec3, color: canvas2d.Color, part: boats.Part) {
    normal := linalg.normalize0(linalg.cross(b - a, c - a))
    metallic := part == .Metal ? f32(.62) : f32(0)
    roughness := part == .Glass ? f32(.24) : f32(.78)
    vertex_a := world_vertex(a, color)
    vertex_b := world_vertex(b, color)
    vertex_c := world_vertex(c, color)
    vertices := [3]^World_Vertex{&vertex_a, &vertex_b, &vertex_c}
    for vertex in vertices {
        vertex.kind = .BRDF
        vertex.normal = {normal.x, normal.y, normal.z}
        vertex.material = {metallic, roughness}
    }
    append(&world_renderer.vertices, vertex_a, vertex_b, vertex_c)
}

world_npc_boat :: proc(class: boats.Class, position: third_person.Vec3, yaw: f32, sails_raised: bool = true) {
    mesh := boats.cached_mesh(class)
    if mesh == nil do return
    yaw_cos, yaw_sin := math.cos(yaw), math.sin(yaw)
    for face in boats.triangles(mesh) {
        a, b, c := mesh.vertices[face.a], mesh.vertices[face.b], mesh.vertices[face.c]
        if class == .Sail && !sails_raised && (a.part == .Sail || a.part == .Accent) {
            continue
        }
        world_boat_triangle(
            world_boat_point(a.position, position, yaw_cos, yaw_sin),
            world_boat_point(b.position, position, yaw_cos, yaw_sin),
            world_boat_point(c.position, position, yaw_cos, yaw_sin),
            world_boat_part_color(class, a.part),
            a.part,
        )
    }
}

world_npc_boats :: proc(editor: ^Editor) {
    if editor == nil do return
    for agent in editor.boat_traffic.agents[:editor.boat_traffic.count] {
        position := third_person.Vec3{agent.position.x, editor.project.sea_level + .03, agent.position.y}
        bob := math.sin(editor.map_time * .72 + f32(agent.class) * 1.31) * (.025 + agent.speed * .004)
        position.y += bob
        spec := boats.specifications(agent.class)
        radius :=
            f32(
                math.sqrt(
                    f64(
                        spec.length * spec.length +
                        spec.beam * spec.beam +
                        spec.height_or_clearance * spec.height_or_clearance,
                    ),
                ),
            ) *
            .5
        if !world_sphere_in_view(
            editor,
            {position.x, position.y + spec.height_or_clearance * .5, position.z},
            radius,
        ) {
            continue
        }
        world_npc_boat(agent.class, position, agent.yaw, agent.behavior != .Moored)
    }
}

world_ocean_ship_part_color :: proc(class: boats.Ocean_Class, part: boats.Part) -> canvas2d.Color {
    if class == .Product_Tanker {
        #partial switch part {
        case .Hull:
            return {54, 63, 66, 255}
        case .Deck:
            return {152, 48, 38, 255}
        case .Cabin:
            return {224, 220, 202, 255}
        case .Accent:
            return {192, 151, 54, 255}
        case .Glass:
            return {55, 91, 106, 255}
        case .Metal:
            return {76, 79, 76, 255}
        case:
        }
    } else {
        #partial switch part {
        case .Hull:
            return {218, 222, 216, 255}
        case .Deck:
            return {184, 180, 164, 255}
        case .Cabin:
            return {232, 231, 218, 255}
        case .Accent:
            return {53, 79, 112, 255}
        case .Glass:
            return {45, 80, 102, 255}
        case .Metal:
            return {75, 78, 78, 255}
        case:
        }
    }
    return {210, 210, 200, 255}
}

world_ocean_ship :: proc(editor: ^Editor) {
    if editor == nil || !editor.ocean_traffic.agent.active do return
    agent := &editor.ocean_traffic.agent
    spec := boats.ocean_specifications(agent.class)
    position := third_person.Vec3{agent.position.x, editor.project.sea_level + .03, agent.position.y}
    radius := f32(math.sqrt(f64(spec.length * spec.length + spec.beam * spec.beam + spec.height * spec.height))) * .5
    if !world_sphere_in_view(editor, {position.x, position.y + spec.height * .5, position.z}, radius) do return

    mesh := boats.ocean_mesh(agent.class)
    if mesh == nil do return
    yaw_cos, yaw_sin := math.cos(agent.yaw), math.sin(agent.yaw)
    for face in boats.triangles(mesh) {
        a, b, c := mesh.vertices[face.a], mesh.vertices[face.b], mesh.vertices[face.c]
        world_boat_triangle(
            world_boat_point(a.position, position, yaw_cos, yaw_sin),
            world_boat_point(b.position, position, yaw_cos, yaw_sin),
            world_boat_point(c.position, position, yaw_cos, yaw_sin),
            world_ocean_ship_part_color(agent.class, a.part),
            a.part,
        )
    }
}

world_ocean_ship_wake :: proc(editor: ^Editor) {
    if editor == nil || !editor.ocean_traffic.agent.active do return
    agent := &editor.ocean_traffic.agent
    spec := boats.ocean_specifications(agent.class)
    y := editor.project.sea_level + .06
    for sample in agent.wake[:agent.wake_count] {
        fade := clamp(1 - sample.age / sample.lifetime, 0, 1)
        if fade <= .01 do continue
        // The shoulders diverge slowly inside the Kelvin envelope while the
        // propeller/rudder churn holds a bright center ribbon astern.
        right := boats.Vec2{-sample.direction.y, sample.direction.x}
        spread := sample.width * .28 + sample.age * spec.cruise_speed_mps * .055
        shoulder_width := sample.width * (.035 + fade * .028)
        segment_length := sample.width * .20
        alpha := u8(clamp(178 * sample.strength * fade * fade, 0, 178))
        foam := canvas2d.Color{218, 241, 236, alpha}
        world_boat_wake_quad(
            sample.position + right * spread,
            sample.direction,
            shoulder_width,
            segment_length,
            foam,
            y,
        )
        world_boat_wake_quad(
            sample.position - right * spread,
            sample.direction,
            shoulder_width,
            segment_length,
            foam,
            y,
        )
        center_width := sample.width * (.11 + fade * .10)
        center_alpha := u8(f32(alpha) * (agent.class == .Product_Tanker ? f32(.56) : f32(.42)))
        world_boat_wake_quad(
            sample.position,
            sample.direction,
            center_width,
            segment_length * 1.18,
            {224, 243, 238, center_alpha},
            y + .002,
        )
    }
}

world_boat_wake_quad :: proc(
    center: boats.Vec2,
    direction: boats.Vec2,
    half_width, half_length: f32,
    color: canvas2d.Color,
    y: f32,
) {
    right := boats.Vec2{-direction.y, direction.x}
    p0 := center - right * half_width - direction * half_length
    p1 := center - right * half_width + direction * half_length
    p2 := center + right * half_width + direction * half_length
    p3 := center + right * half_width - direction * half_length
    // Reverse the planar order so the foam faces upward under CCW culling.
    world_quad({p0.x, y, p0.y}, {p3.x, y, p3.y}, {p2.x, y, p2.y}, {p1.x, y, p1.y}, color)
}

world_boat_wakes :: proc(editor: ^Editor) {
    if editor == nil do return
    y := editor.project.sea_level + .055
    for agent in editor.boat_traffic.agents[:editor.boat_traffic.count] {
        spec := boats.specifications(agent.class)
        for sample_index in 0 ..< agent.wake_count {
            sample := agent.wake[sample_index]
            fade := clamp(1 - sample.age / sample.lifetime, 0, 1)
            if fade <= .01 do continue
            age_spread := sample.age * (.18 + sample.strength * .32)
            right := boats.Vec2{-sample.direction.y, sample.direction.x}
            arm_offset := sample.width * .48 + age_spread
            arm_width := clamp(sample.width * (.045 + fade * .045), f32(.055), f32(.46))
            arm_length := clamp(spec.beam * (.10 + sample.strength * .12), f32(.22), f32(1.75))
            wake_radius := arm_offset + arm_length + max(arm_width, f32(.62))
            if !world_sphere_in_view(editor, {sample.position.x, y, sample.position.y}, wake_radius) {
                continue
            }
            alpha := u8(clamp(92 * sample.strength * fade * fade, 0, 92))
            foam := canvas2d.Color{210, 237, 232, alpha}
            port := sample.position + right * arm_offset
            starboard := sample.position - right * arm_offset
            world_boat_wake_quad(port, sample.direction, arm_width, arm_length, foam, y)
            world_boat_wake_quad(starboard, sample.direction, arm_width, arm_length, foam, y)
            // Heavy displacement leaves a softer centerline boil; high-power
            // planing craft emphasize the divergent arms instead.
            displacement_mix := clamp(spec.displacement_kg / 350000, 0, 1)
            center_alpha := u8(f32(alpha) * (.12 + displacement_mix * .24))
            world_boat_wake_quad(
                sample.position,
                sample.direction,
                min(arm_width * (1.1 + displacement_mix * .45), f32(.62)),
                min(arm_length * .62, f32(1.05)),
                {220, 240, 235, center_alpha},
                y + .002,
            )
        }
    }
}

road_bridge_deck_height :: proc(editor: ^Editor, edge_index: int, t: f32) -> (f32, bool) {
    if editor == nil || edge_index < 0 || edge_index >= editor.project.road_graph.edge_count do return 0, false
    graph := &editor.project.road_graph
    edge := graph.edges[edge_index]
    center := roads.edge_point(graph, edge, t)
    bed_height := terrain.sample_height(&editor.project, 0, center.x, center.z)
    if edge.engineering_designed {
        if edge.structure_kind == .Bridge do return center.y, true
        return bed_height, false
    }
    if !terrain.active_waterway_at(&editor.project, 0, center.x, center.z) do return bed_height, false

    approximate_length := max(roads.edge_control_polygon_length(graph, edge), f32(1))
    bank_height := f32(-1e30)
    bank_count := 0
    directions := [2]f32{-1, 1}
    // Search along the road centerline, rather than radially from each lateral
    // vertex. Every lane at this station therefore receives the same datum.
    for direction in directions {
        for distance := f32(2); distance <= 64; distance += 2 {
            sample_t := clamp(t + direction * distance / approximate_length, 0, 1)
            point := roads.edge_point(graph, edge, sample_t)
            if terrain.active_waterway_at(&editor.project, 0, point.x, point.z) {
                if sample_t == 0 || sample_t == 1 do break
                continue
            }
            bank_height = max(bank_height, terrain.sample_height(&editor.project, 0, point.x, point.z))
            bank_count += 1
            break
        }
    }
    if bank_count == 0 do bank_height = bed_height + .8
    return max(bed_height + .8, bank_height + .45), true
}

@(no_instrumentation)
road_world_point :: #force_inline proc(editor: ^Editor, vertex: roads.Vertex) -> third_person.Vec3 {
    clearance := f32(.12)
    if vertex.surface == .Shoulder {
        clearance = .05
    } else if vertex.surface == .Verge {
        clearance = .018
    }
    terrain_y := terrain.sample_height(&editor.project, 0, vertex.position.x, vertex.position.z)
    if vertex.source_edge > 0 && vertex.source_edge <= editor.project.road_graph.edge_count {
        edge := editor.project.road_graph.edges[vertex.source_edge - 1]
        if edge.engineering_designed && edge.authored_profile {
            terrain_y = vertex.position.y
            bank := edge.superelevation_from + (edge.superelevation_to - edge.superelevation_from) * vertex.edge_t
            lateral := (vertex.uv[0] - .5) * edge.half_width * 2
            terrain_y += math.tan(bank) * lateral
        }
    }
    if deck_y, bridge := road_bridge_deck_height(editor, vertex.source_edge - 1, vertex.edge_t); bridge {
        terrain_y = deck_y
    }
    // The baked edge height only describes its control spline. Long generated
    // airport and marina links otherwise bridge every downhill section when
    // authored Y is used as a lower bound. Roads are terrain overlays, so fit
    // every rendered vertex to the current heightfield.
    return {vertex.position.x, terrain_y + clearance, vertex.position.z}
}

world_triangle_to :: #force_inline proc(
    destination: ^[dynamic]World_Vertex,
    a, b, c: third_person.Vec3,
    color: canvas2d.Color,
) {
    vertices := [3]World_Vertex{world_vertex(a, color), world_vertex(b, color), world_vertex(c, color)}
    normal := linalg.normalize0(linalg.cross(b - a, c - a))
    for &vertex in vertices {
        vertex.kind = .BRDF
        vertex.normal = {normal.x, normal.y, normal.z}
        vertex.material = {0, .9}
    }
    append(destination, ..vertices[:])
}
