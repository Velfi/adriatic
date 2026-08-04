package main

import leaf_mesh "../packages/leaf_mesh"
import plant_bark "../packages/plant_bark"
import plant_structure "../packages/plant_structure"
import plants "../packages/plants"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

GENERATED_PLANT_CACHE_CAPACITY :: (SETTLEMENT_PATIO_CAPACITY * 2 + MARINA_GEOMETRY_CACHE_CAPACITY * 3) * 3
GENERATED_PLANT_MATURITY_STEPS :: 5

Generated_Plant_Cache_Entry :: struct {
    species:           plants.Species,
    seed:              u64,
    detail:            plants.Detail_Level,
    habit:             plants.Growth_Habit,
    support_signature: u64,
    site_signature:    u64,
    maturity_step:     u8,
    result:            plants.Generate_Result,
    bark_topology:     []Generated_Bark_Segment_Topology,
}

Generated_Bark_Segment_Topology :: struct {
    distance:   f32,
    has_parent: bool,
    has_child:  bool,
}

Generated_Plant_Transform :: struct {
    base:               third_person.Vec3,
    cosine, sine:       f32,
    scale, along_grade: f32,
}

Generated_Plant_World_Cache_Entry :: struct {
    species:           plants.Species,
    seed:              u64,
    detail:            plants.Detail_Level,
    render_lod:        Generated_Plant_Render_LOD,
    foliage_mode:      Generated_Plant_Foliage_Mode,
    habit:             plants.Growth_Habit,
    support_signature: u64,
    site_signature:    u64,
    maturity_step:     u8,
    base:              third_person.Vec3,
    scale, yaw:        f32,
    along_grade:       f32,
    vertices:          [dynamic]World_Vertex,
    shadow_min:        third_person.Vec3,
    shadow_max:        third_person.Vec3,
    shadow_all_cast:   bool,
}

generated_plant_cache: [GENERATED_PLANT_CACHE_CAPACITY]Generated_Plant_Cache_Entry
generated_plant_cache_count: int
generated_plant_world_cache: [dynamic]Generated_Plant_World_Cache_Entry

Generated_Plant_Render_LOD :: enum u8 {
    Hero,
    Near,
    Medium,
    Far,
    Distant,
}

Generated_Plant_Foliage_Mode :: enum u8 {
    Leaves,
    Density_Clumps,
}

Generated_Plant_Leaf_Clump :: struct {
    weighted_center: third_person.Vec3,
    minimum:         third_person.Vec3,
    maximum:         third_person.Vec3,
    projected_area:  f32,
    red, green, blue: f32,
    count:           int,
}

generated_plant_middle_branch_mesh := -1
generated_plant_middle_clump_mesh := -1
generated_plant_leaf_meshes: [leaf_mesh.SHAPE_COUNT * 2]int

generated_plant_maturity_step :: #force_inline proc(maturity: f32) -> u8 {
    return u8(
        clamp(
            int(math.round(f64(clamp(maturity, f32(0), f32(1)) * GENERATED_PLANT_MATURITY_STEPS))),
            0,
            GENERATED_PLANT_MATURITY_STEPS,
        ),
    )
}

generated_plant_maturity_value :: #force_inline proc(step: u8) -> f32 {
    return f32(min(int(step), GENERATED_PLANT_MATURITY_STEPS)) / GENERATED_PLANT_MATURITY_STEPS
}

generated_plant_site_context :: proc(editor: ^Editor, base: third_person.Vec3) -> plants.Site_Context {
    if editor == nil do return {}
    terrain_context := atmosphere_terrain_context(editor, base)
    local := atmosphere_local_weather(editor, base)
    slope := clamp(
        f32(math.sqrt(f64(
            terrain_context.terrain_gradient[0] * terrain_context.terrain_gradient[0] +
            terrain_context.terrain_gradient[1] * terrain_context.terrain_gradient[1],
        ))) / .45,
        f32(0),
        f32(1),
    )
    coast_distance := clamp(terrain_context.coast_distance, f32(0), f32(1800))
    coastal_influence := 1 - coast_distance / 1800
    surface := terrain.ground_surface_at(&editor.project, 0, base.x, base.z)
    terrain_material := terrain.sample_material(&editor.project, 0, base.x, base.z)
    substrate := plants.Site_Substrate.Soil
    substrate_aridity := f32(0)
    switch surface {
    case .Sand:
        substrate = .Sand
        substrate_aridity = .16
    case .Dirt:
        substrate = .Soil
        substrate_aridity = .07
    case .Grass:
        substrate = .Soil
        substrate_aridity = -.08
    }
    if terrain_material > .72 && slope > .30 {
        substrate = .Rock
        substrate_aridity = .13
    }
    exposure := clamp(slope * .48 + terrain_context.terrain_channel * .34 + local.rain_shadow * .32, 0, 1)
    aridity := clamp(
        .42 + substrate_aridity + local.rain_shadow * .30 + exposure * .15 - coastal_influence * .12,
        f32(0),
        f32(1),
    )
    return {
        valid            = terrain_context.valid,
        aridity          = aridity,
        exposure         = exposure,
        slope            = slope,
        elevation_meters = max(terrain_context.terrain_height - terrain_context.sea_level, f32(0)),
        coast_distance_m = coast_distance,
        substrate        = substrate,
    }
}

generated_plant_drought_resistance :: proc(species: plants.Species) -> f32 {
    #partial switch species {
    case .Olive, .Rosemary, .Lavender, .Thyme, .Sage, .Mastic, .Carob,
         .Prickly_Pear, .Golden_Barrel, .Agave, .Aloe, .Aeonium,
         .Echeveria, .Jade_Plant, .Stonecrop, .Blue_Chalk_Sticks,
         .Golden_Torch_Cactus:
        return .82
    case .Grapevine, .Fig, .Pomegranate, .Stone_Pine, .Bay_Laurel:
        return .58
    case .Hydrangea_Bush, .Hydrangea_Tree, .White_Poplar:
        return .18
    }
    return .42
}

generated_plant_site_leaf_color :: proc(
    species: plants.Species,
    color: canvas2d.Color,
    site: plants.Site_Context,
    variant: u8,
) -> canvas2d.Color {
    if !site.valid do return color
    stress := clamp((site.aridity - .38) / .62, 0, 1) * (1 - generated_plant_drought_resistance(species))
    stress *= .82 + f32(variant % 4) * .06
    dry := canvas2d.Color{151, 132, 73, color.a}
    return color_lerp(color, dry, stress * .58)
}

generated_plant_cached :: proc(
    species: plants.Species,
    seed: u64,
    detail: plants.Detail_Level,
    habit: plants.Growth_Habit = .Free_Standing,
    support: ^plants.Support_Surface = nil,
    maturity: f32 = 1,
    site: plants.Site_Context = {},
) -> ^Generated_Plant_Cache_Entry {
    support_signature: u64
    if support != nil do support_signature = plants.support_hash(support^)
    site_signature := plants.site_context_signature(site)
    maturity_step := generated_plant_maturity_step(maturity)
    for index in 0 ..< generated_plant_cache_count {
        entry := &generated_plant_cache[index]
        if entry.species == species &&
           entry.seed == seed &&
           entry.detail == detail &&
           entry.habit == habit &&
           entry.support_signature == support_signature &&
           entry.site_signature == site_signature &&
           entry.maturity_step == maturity_step {
            return entry
        }
    }
    if generated_plant_cache_count >= len(generated_plant_cache) do return nil
    result := plants.generate(
        {
            species = species,
            seed = seed,
            maturity = generated_plant_maturity_value(maturity_step),
            detail = detail,
            habit = habit,
            support = support,
            site = site,
        },
    )
    if result.error != .None {
        plants.destroy(&result)
        return nil
    }
    entry := &generated_plant_cache[generated_plant_cache_count]
    entry^ = {
        species           = species,
        seed              = seed,
        detail            = detail,
        habit             = habit,
        support_signature = support_signature,
        site_signature    = site_signature,
        maturity_step     = maturity_step,
        result            = result,
    }
    entry.bark_topology = make([]Generated_Bark_Segment_Topology, len(result.plant.segments))
    for segment, segment_index in result.plant.segments {
        parent_index := result.plant.segment_parents[segment_index]
        if parent_index >= 0 {
            parent := result.plant.segments[parent_index]
            parent_delta := parent.end - parent.start
            parent_length := f32(math.sqrt(f64(linalg.dot(parent_delta, parent_delta))))
            entry.bark_topology[segment_index].distance = entry.bark_topology[parent_index].distance + parent_length
            entry.bark_topology[segment_index].has_parent = true
            entry.bark_topology[parent_index].has_child = true
        }
    }
    generated_plant_cache_count += 1
    return entry
}

generated_plant_cache_destroy :: proc() {
    for index in 0 ..< generated_plant_cache_count {
        plants.destroy(&generated_plant_cache[index].result)
        delete(generated_plant_cache[index].bark_topology)
    }
    generated_plant_cache = {}
    generated_plant_cache_count = 0
}

@(no_instrumentation)
generated_plant_world_cache_find :: proc(
    species: plants.Species,
    seed: u64,
    detail: plants.Detail_Level,
    render_lod: Generated_Plant_Render_LOD,
    foliage_mode: Generated_Plant_Foliage_Mode,
    habit: plants.Growth_Habit,
    support_signature: u64,
    site_signature: u64,
    maturity_step: u8,
    base: third_person.Vec3,
    scale, yaw, along_grade: f32,
) -> ^Generated_Plant_World_Cache_Entry {
    for index in 0 ..< len(generated_plant_world_cache) {
        entry := &generated_plant_world_cache[index]
        if entry.species == species &&
           entry.seed == seed &&
           entry.detail == detail &&
           entry.render_lod == render_lod &&
           entry.foliage_mode == foliage_mode &&
           entry.habit == habit &&
           entry.support_signature == support_signature &&
           entry.site_signature == site_signature &&
           entry.maturity_step == maturity_step &&
           entry.base == base &&
           entry.scale == scale &&
           entry.yaw == yaw &&
           entry.along_grade == along_grade {
            return entry
        }
    }
    return nil
}

@(no_instrumentation)
generated_plant_world_cache_store :: proc(
    species: plants.Species,
    seed: u64,
    detail: plants.Detail_Level,
    render_lod: Generated_Plant_Render_LOD,
    foliage_mode: Generated_Plant_Foliage_Mode,
    habit: plants.Growth_Habit,
    support_signature: u64,
    site_signature: u64,
    maturity_step: u8,
    base: third_person.Vec3,
    scale, yaw, along_grade: f32,
    vertices: []World_Vertex,
) {
    if len(vertices) == 0 do return
    entry := Generated_Plant_World_Cache_Entry {
        species           = species,
        seed              = seed,
        detail            = detail,
        render_lod        = render_lod,
        foliage_mode      = foliage_mode,
        habit             = habit,
        support_signature = support_signature,
        site_signature    = site_signature,
        maturity_step     = maturity_step,
        base              = base,
        scale             = scale,
        yaw               = yaw,
        along_grade       = along_grade,
        vertices          = make([dynamic]World_Vertex, 0, len(vertices)),
    }
    append(&entry.vertices, ..vertices)
    entry.shadow_min = {1e30, 1e30, 1e30}
    entry.shadow_max = {-1e30, -1e30, -1e30}
    entry.shadow_all_cast = true
    for vertex in vertices {
        entry.shadow_min.x = min(entry.shadow_min.x, vertex.position[0])
        entry.shadow_min.y = min(entry.shadow_min.y, vertex.position[1])
        entry.shadow_min.z = min(entry.shadow_min.z, vertex.position[2])
        entry.shadow_max.x = max(entry.shadow_max.x, vertex.position[0])
        entry.shadow_max.y = max(entry.shadow_max.y, vertex.position[1])
        entry.shadow_max.z = max(entry.shadow_max.z, vertex.position[2])
        if !dynamic_shadow_material_casts(vertex.kind) do entry.shadow_all_cast = false
    }
    append(&generated_plant_world_cache, entry)
}

generated_plant_world_cache_clear :: proc() {
    for &entry in generated_plant_world_cache do delete(entry.vertices)
    clear(&generated_plant_world_cache)
}

generated_plant_world_cache_destroy :: proc() {
    generated_plant_world_cache_clear()
    delete(generated_plant_world_cache)
}

generated_plant_world_cache_invalidate_bounds :: proc(min_x, min_z, max_x, max_z: f32) {
    write := 0
    for entry in generated_plant_world_cache {
        if entry.base.x >= min_x && entry.base.x <= max_x && entry.base.z >= min_z && entry.base.z <= max_z {
            delete(entry.vertices)
            continue
        }
        generated_plant_world_cache[write] = entry
        write += 1
    }
    resize(&generated_plant_world_cache, write)
}

@(no_instrumentation)
generated_plant_transform_make :: #force_inline proc(
    base: third_person.Vec3,
    yaw, scale, along_grade: f32,
) -> Generated_Plant_Transform {
    return {base = base, cosine = math.cos(yaw), sine = math.sin(yaw), scale = scale, along_grade = along_grade}
}

@(no_instrumentation)
generated_plant_point :: #force_inline proc(
    transform: Generated_Plant_Transform,
    point: plant_structure.Vec3,
) -> third_person.Vec3 {
    return {
        transform.base.x + (point[0] * transform.cosine - point[2] * transform.sine) * transform.scale,
        transform.base.y + (point[1] + point[0] * transform.along_grade) * transform.scale,
        transform.base.z + (point[0] * transform.sine + point[2] * transform.cosine) * transform.scale,
    }
}

@(no_instrumentation)
generated_plant_vector :: #force_inline proc(
    transform: Generated_Plant_Transform,
    vector: plant_structure.Vec3,
) -> third_person.Vec3 {
    return {
        vector[0] * transform.cosine - vector[2] * transform.sine,
        vector[1] + vector[0] * transform.along_grade,
        vector[0] * transform.sine + vector[2] * transform.cosine,
    }
}

generated_plant_mark_wind_attachment :: #force_inline proc(
    first_vertex: int,
    origin, anchor: third_person.Vec3,
) {
    for &vertex in world_renderer.vertices[first_vertex:] {
        vertex.wind_origin = {origin.x, origin.y, origin.z}
        vertex.wind_anchor = {anchor.x, anchor.y, anchor.z}
        vertex.wind_enabled = 1
    }
}

generated_plant_mark_wind_branch :: #force_inline proc(
    first_vertex: int,
    origin, start, end: third_person.Vec3,
) {
    axis := end - start
    axis_length_squared := linalg.dot(axis, axis)
    for &vertex in world_renderer.vertices[first_vertex:] {
        point := third_person.Vec3{vertex.position[0], vertex.position[1], vertex.position[2]}
        fraction := f32(0)
        if axis_length_squared > 1e-8 {
            fraction = clamp(linalg.dot(point - start, axis) / axis_length_squared, f32(0), f32(1))
        }
        anchor := start + axis * fraction
        vertex.wind_origin = {origin.x, origin.y, origin.z}
        vertex.wind_anchor = {anchor.x, anchor.y, anchor.z}
        vertex.wind_enabled = 1
    }
}

generated_plant_render_lod :: #force_inline proc(
    camera_position, plant_position: third_person.Vec3,
) -> Generated_Plant_Render_LOD {
    dx := camera_position.x - plant_position.x
    dz := camera_position.z - plant_position.z
    distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
    if distance < 8 do return .Hero
    if distance < 32 do return .Near
    if distance < 72 do return .Medium
    if distance < 144 do return .Far
    return .Distant
}

generated_plant_catalog_detail :: #force_inline proc(lod: Generated_Plant_Render_LOD) -> plants.Detail_Level {
    switch lod {
    case .Hero, .Near:
        return .Near
    case .Medium:
        return .Medium
    case .Far, .Distant:
        return .Far
    }
    return .Far
}

generated_plant_uses_hero_geometry :: #force_inline proc(lod: Generated_Plant_Render_LOD) -> bool {
    return lod == .Hero
}

// Generated leaf frames carry an authored surface normal in `up`. Keep each
// front facet in that hemisphere instead of relying on vertex winding, then
// emit the reverse face with the opposite normal for two-sided lighting.
world_generated_leaf_facet :: #force_inline proc(a, b, c, surface_normal: third_person.Vec3, color: canvas2d.Color) {
    normal := linalg.normalize0(linalg.cross(b - a, c - a))
    if linalg.dot(normal, surface_normal) < 0 do normal = -normal
    world_triangle_foliage(a, b, c, color, color, color, normal, normal, normal, .Leaf)
    world_triangle_foliage(c, b, a, color, color, color, -normal, -normal, -normal, .Leaf)
}

world_generated_leaf_textured_facet :: #force_inline proc(
    a, b, c: third_person.Vec3,
    uv_a, uv_b, uv_c: [2]f32,
    surface_normal: third_person.Vec3,
    color: canvas2d.Color,
    shape: u32,
) {
    normal := linalg.normalize0(linalg.cross(b - a, c - a))
    if linalg.dot(normal, surface_normal) < 0 do normal = -normal
    world_triangle_leaf_textured(a, b, c, color, color, color, normal, normal, normal, uv_a, uv_b, uv_c, shape)
    world_triangle_leaf_textured(c, b, a, color, color, color, -normal, -normal, -normal, uv_c, uv_b, uv_a, shape)
}

world_generated_leaf_smooth_facet :: #force_inline proc(
    a, b, c: third_person.Vec3,
    normal_a, normal_b, normal_c: third_person.Vec3,
    color: canvas2d.Color,
) {
    world_triangle_foliage(a, b, c, color, color, color, normal_a, normal_b, normal_c, .Leaf)
    world_triangle_foliage(c, b, a, color, color, color, -normal_c, -normal_b, -normal_a, .Leaf)
}

generated_plant_apply_detail_floor :: #force_inline proc(detail, floor: plants.Detail_Level) -> plants.Detail_Level {
    return int(detail) < int(floor) ? floor : detail
}

generated_plant_instance :: #force_inline proc(
    x_axis, y_axis, z_axis, translation: third_person.Vec3,
    color: canvas2d.Color,
) -> World_Mesh_Instance {
    return {
        basis_x_translation_x = {x_axis.x, x_axis.y, x_axis.z, translation.x},
        basis_y_translation_y = {y_axis.x, y_axis.y, y_axis.z, translation.y},
        basis_z_translation_z = {z_axis.x, z_axis.y, z_axis.z, translation.z},
        color = world_color(color),
    }
}

generated_plant_optimized_instance_mesh :: proc(
    vertices: []World_Vertex,
    source_indices: []u16,
) -> int {
    if len(vertices) == 0 || len(source_indices) == 0 do return -1
    optimized := make([dynamic]u16, len(source_indices))
    defer delete(optimized)
    adriatic_optimize_index_buffer(
        raw_data(optimized),
        raw_data(source_indices),
        u32(len(source_indices)),
        u32(len(vertices)),
    )
    indices := make([dynamic]u32, len(optimized))
    defer delete(indices)
    for index in 0 ..< len(optimized) do indices[index] = u32(optimized[index])
    // This representation begins beyond the close tree band. Expanding every
    // instance back into CPU shadow triangles defeats instancing and adds no
    // useful contact shadow at this range.
    return world_instance_mesh_add(vertices, indices[:], false)
}

generated_plant_middle_meshes_ensure :: proc() {
    if generated_plant_middle_branch_mesh >= 0 && generated_plant_middle_clump_mesh >= 0 do return

    BRANCH_SIDES :: 8
    branch_vertices: [BRANCH_SIDES * 2]World_Vertex
    for side in 0 ..< BRANCH_SIDES {
        angle := f32(side) * math.TAU / BRANCH_SIDES
        normal := third_person.Vec3{math.cos(angle), 0, math.sin(angle)}
        branch_vertices[side] = world_vertex(normal, {255, 255, 255, 255})
        branch_vertices[side].position = {normal.x, 0, normal.z}
        branch_vertices[side].normal = {normal.x, normal.y, normal.z}
        branch_vertices[side].kind = .Bark
        branch_vertices[side + BRANCH_SIDES] = branch_vertices[side]
        branch_vertices[side + BRANCH_SIDES].position = {normal.x * .62, 1, normal.z * .62}
    }
    branch_indices: [BRANCH_SIDES * 6]u16
    for side in 0 ..< BRANCH_SIDES {
        next := (side + 1) % BRANCH_SIDES
        first := side * 6
        branch_indices[first + 0] = u16(side)
        branch_indices[first + 1] = u16(next)
        branch_indices[first + 2] = u16(next + BRANCH_SIDES)
        branch_indices[first + 3] = u16(side)
        branch_indices[first + 4] = u16(next + BRANCH_SIDES)
        branch_indices[first + 5] = u16(side + BRANCH_SIDES)
    }
    generated_plant_middle_branch_mesh = generated_plant_optimized_instance_mesh(
        branch_vertices[:],
        branch_indices[:],
    )

    CLUMP_SIDES :: 8
    CLUMP_VERTICES :: CLUMP_SIDES * 2 + 2
    CLUMP_INDICES :: CLUMP_SIDES * 12
    clump_vertices: [CLUMP_VERTICES]World_Vertex
    clump_vertices[0] = world_vertex({0, .82, 0}, {255, 255, 255, 255})
    clump_vertices[0].normal = {0, 1, 0}
    clump_vertices[0].kind = .Foliage
    clump_vertices[CLUMP_VERTICES - 1] = world_vertex({0, -.62, 0}, {255, 255, 255, 255})
    clump_vertices[CLUMP_VERTICES - 1].normal = {0, -1, 0}
    clump_vertices[CLUMP_VERTICES - 1].kind = .Foliage
    for side in 0 ..< CLUMP_SIDES {
        angle := f32(side) * math.TAU / CLUMP_SIDES
        cosine, sine := math.cos(angle), math.sin(angle)
        upper := 1 + side
        lower := 1 + CLUMP_SIDES + side
        clump_vertices[upper] = world_vertex({cosine * .78, .30, sine * .78}, {255, 255, 255, 255})
        clump_vertices[upper].normal = {cosine * .72, .48, sine * .72}
        clump_vertices[upper].kind = .Foliage
        clump_vertices[lower] = world_vertex({cosine, -.20, sine}, {255, 255, 255, 255})
        clump_vertices[lower].normal = {cosine * .82, -.30, sine * .82}
        clump_vertices[lower].kind = .Foliage
    }
    clump_indices: [CLUMP_INDICES]u16
    for side in 0 ..< CLUMP_SIDES {
        next := (side + 1) % CLUMP_SIDES
        upper, upper_next := 1 + side, 1 + next
        lower, lower_next := 1 + CLUMP_SIDES + side, 1 + CLUMP_SIDES + next
        first := side * 12
        clump_indices[first + 0] = 0
        clump_indices[first + 1] = u16(upper)
        clump_indices[first + 2] = u16(upper_next)
        clump_indices[first + 3] = u16(upper)
        clump_indices[first + 4] = u16(lower)
        clump_indices[first + 5] = u16(lower_next)
        clump_indices[first + 6] = u16(upper)
        clump_indices[first + 7] = u16(lower_next)
        clump_indices[first + 8] = u16(upper_next)
        clump_indices[first + 9] = u16(CLUMP_VERTICES - 1)
        clump_indices[first + 10] = u16(lower_next)
        clump_indices[first + 11] = u16(lower)
    }
    generated_plant_middle_clump_mesh = generated_plant_optimized_instance_mesh(
        clump_vertices[:],
        clump_indices[:],
    )
}

generated_plant_leaf_mesh_ensure :: proc(shape: leaf_mesh.Shape, hero: bool) -> int {
    shape_index := int(shape)
    if shape_index < 0 || shape_index >= leaf_mesh.SHAPE_COUNT do return -1
    cache_index := shape_index * 2 + (hero ? 1 : 0)
    if generated_plant_leaf_meshes[cache_index] > 0 {
        return generated_plant_leaf_meshes[cache_index] - 1
    }

    config := leaf_mesh.defaults(shape)
    config.length = 1
    config.width = 2
    config.stem = 0
    config.segments = hero ? 10 : 6
    config.curl *= .12
    config.cup *= .12
    mesh := leaf_mesh.generate(config)
    if mesh.vertex_count == 0 || mesh.index_count == 0 do return -1

    vertices := make([dynamic]World_Vertex, mesh.vertex_count * 2)
    defer delete(vertices)
    for index in 0 ..< mesh.vertex_count {
        source := mesh.vertices[index]
        front := world_vertex(source.position, {255, 255, 255, 255})
        front.normal = source.normal
        front.kind = .Leaf
        front.uv = source.uv
        front.material = {f32(shape_index), 1}
        vertices[index] = front
        back := front
        back.normal = -source.normal
        vertices[index + mesh.vertex_count] = back
    }
    indices := make([dynamic]u16, mesh.index_count * 2)
    defer delete(indices)
    for index in 0 ..< mesh.index_count {
        indices[index] = mesh.indices[index]
    }
    for triangle := 0; triangle + 2 < mesh.index_count; triangle += 3 {
        target := mesh.index_count + triangle
        offset := u16(mesh.vertex_count)
        indices[target + 0] = mesh.indices[triangle + 2] + offset
        indices[target + 1] = mesh.indices[triangle + 1] + offset
        indices[target + 2] = mesh.indices[triangle + 0] + offset
    }
    mesh_index := generated_plant_optimized_instance_mesh(vertices[:], indices[:])
    if mesh_index >= 0 do generated_plant_leaf_meshes[cache_index] = mesh_index + 1
    return mesh_index
}

generated_plant_leaf_emit :: proc(
    center, forward, up, right: third_person.Vec3,
    width, length: f32,
    shape: leaf_mesh.Shape,
    color: canvas2d.Color,
    hero: bool,
) -> bool {
    mesh_index := generated_plant_leaf_mesh_ensure(shape, hero)
    if mesh_index < 0 do return false
    world_instance_mesh_emit(
        mesh_index,
        generated_plant_instance(right * width, forward * length, up * width, center, color),
    )
    return true
}

generated_plant_middle_branch_emit :: proc(
    segment: plant_structure.Segment,
    transform: Generated_Plant_Transform,
    color: canvas2d.Color,
) {
    generated_plant_middle_meshes_ensure()
    start := generated_plant_point(transform, segment.start)
    end := generated_plant_point(transform, segment.end)
    axis := end - start
    if linalg.dot(axis, axis) < 1e-8 do return
    direction := linalg.normalize0(axis)
    reference := math.abs(direction.y) > .9 ? third_person.Vec3{1, 0, 0} : third_person.Vec3{0, 1, 0}
    right := linalg.normalize0(linalg.cross(reference, direction))
    forward := linalg.normalize0(linalg.cross(direction, right))
    radius := max(segment.radius_start * transform.scale, f32(.006))
    world_instance_mesh_emit(
        generated_plant_middle_branch_mesh,
        generated_plant_instance(right * radius, axis, forward * radius, start, color),
    )
}

generated_plant_middle_clump_emit :: proc(
    center: third_person.Vec3,
    radius_x, radius_y, radius_z, rotation: f32,
    color: canvas2d.Color,
) {
    generated_plant_middle_meshes_ensure()
    cosine, sine := math.cos(rotation), math.sin(rotation)
    x_axis := third_person.Vec3{cosine * radius_x, 0, sine * radius_x}
    z_axis := third_person.Vec3{-sine * radius_z, 0, cosine * radius_z}
    world_instance_mesh_emit(
        generated_plant_middle_clump_mesh,
        generated_plant_instance(x_axis, {0, radius_y, 0}, z_axis, center, color),
    )
}

// Draw a generated branch with the catalog bark sampled in plant-local
// coordinates. Local sampling keeps the result stable when an instance moves
// or rotates and makes adjacent LOD rebuilds retain the same visual identity.
world_generated_bark_segment :: proc(
    segment: plant_structure.Segment,
    bark: plant_bark.Profile,
    seed: u64,
    transform: Generated_Plant_Transform,
    detail_strength: f32 = 1,
    distance_start: f32 = 0,
    distance_end: f32 = -1,
    cap_start: bool = true,
    cap_end: bool = true,
) {
    SEGMENTS :: 8
    local_delta := segment.end - segment.start
    local_axis := linalg.normalize0(local_delta)
    if linalg.dot(local_axis, local_axis) < .001 do return
    end_distance := distance_end
    if end_distance < distance_start {
        end_distance = distance_start + f32(math.sqrt(f64(linalg.dot(local_delta, local_delta))))
    }
    pattern_hash := (seed + 1) * 0x9e3779b97f4a7c15
    u_phase := f32((pattern_hash >> 40) & 0xffff) / 65535 * bark.scale
    v_phase := f32((pattern_hash >> 16) & 0xffff) / 65535 * bark.scale * 3
    reference := math.abs(local_axis[1]) > .90 ? plant_structure.Vec3{1, 0, 0} : plant_structure.Vec3{0, 1, 0}
    local_right := linalg.normalize0(linalg.cross(reference, local_axis))
    local_up := linalg.normalize0(linalg.cross(local_axis, local_right))
    points_a, points_b: [SEGMENTS]third_person.Vec3
    normals: [SEGMENTS]third_person.Vec3
    uvs_a, uvs_b: [SEGMENTS][2]f32
    radius_a := max(segment.radius_start, f32(.006) / max(transform.scale, f32(.001)))
    radius_b := max(segment.radius_end, f32(.004) / max(transform.scale, f32(.001)))
    for side in 0 ..< SEGMENTS {
        angle := (f32(side) + .5) * math.PI * 2 / SEGMENTS
        local_normal := linalg.normalize0(local_right * math.cos(angle) + local_up * math.sin(angle))
        local_a := segment.start + local_normal * radius_a
        local_b := segment.end + local_normal * radius_b
        points_a[side] = generated_plant_point(transform, local_a)
        points_b[side] = generated_plant_point(transform, local_b)
        normals[side] = linalg.normalize0(generated_plant_vector(transform, local_normal))
        u := f32(side) / SEGMENTS * bark.scale + u_phase
        uvs_a[side] = {u, distance_start * bark.scale + v_phase}
        uvs_b[side] = {u, end_distance * bark.scale + v_phase}
    }
    bark_color := canvas2d.Color{bark.base_color[0], bark.base_color[1], bark.base_color[2], 255}
    pattern := f32(int(bark.pattern))
    for side in 0 ..< SEGMENTS {
        next := (side + 1) % SEGMENTS
        next_u := next == 0 ? bark.scale + u_phase : uvs_a[next].x
        next_a := [2]f32{next_u, uvs_a[next].y}
        next_b := [2]f32{next_u, uvs_b[next].y}
        world_triangle_bark(
            points_a[side],
            points_b[next],
            points_b[side],
            normals[side],
            normals[next],
            normals[side],
            bark_color,
            bark_color,
            bark_color,
            uvs_a[side],
            next_b,
            uvs_b[side],
            pattern,
            bark.roughness,
            detail_strength,
        )
        world_triangle_bark(
            points_a[side],
            points_a[next],
            points_b[next],
            normals[side],
            normals[next],
            normals[next],
            bark_color,
            bark_color,
            bark_color,
            uvs_a[side],
            next_a,
            next_b,
            pattern,
            bark.roughness,
            detail_strength,
        )
    }
    if cap_start || cap_end {
        center_a := generated_plant_point(transform, segment.start)
        center_b := generated_plant_point(transform, segment.end)
        normal_a := linalg.normalize0(generated_plant_vector(transform, -local_axis))
        normal_b := linalg.normalize0(generated_plant_vector(transform, local_axis))
        for side in 0 ..< SEGMENTS {
            next := (side + 1) % SEGMENTS
            next_u := next == 0 ? bark.scale + u_phase : uvs_a[next].x
            if cap_start {
                world_triangle_bark(
                    center_a,
                    points_a[side],
                    points_a[next],
                    normal_a,
                    normal_a,
                    normal_a,
                    bark_color,
                    bark_color,
                    bark_color,
                    uvs_a[side],
                    uvs_a[side],
                    {next_u, uvs_a[next].y},
                    pattern,
                    bark.roughness,
                    detail_strength,
                )
            }
            if cap_end {
                world_triangle_bark(
                    center_b,
                    points_b[next],
                    points_b[side],
                    normal_b,
                    normal_b,
                    normal_b,
                    bark_color,
                    bark_color,
                    bark_color,
                    uvs_b[side],
                    {next_u, uvs_b[next].y},
                    uvs_b[side],
                    pattern,
                    bark.roughness,
                    detail_strength,
                )
            }
        }
    }
}

world_generated_grape_leaf_3d :: proc(
    center, forward, up, right: third_person.Vec3,
    width, length: f32,
    color: canvas2d.Color,
    hero: bool = false,
) {
    // A grape leaf is broad enough that one diamond reads as a paper cutout.
    // Fold five lobed facets around a raised midrib to give the bunch visible
    // thickness and changing light across both sides without a heavy leaf mesh.
    shoulder := center + forward * length * .42
    stem_left := center - right * width * .28
    stem_right := center + right * width * .28
    left := shoulder - right * width
    right_point := shoulder + right * width
    tip := center + forward * length + up * width * .04
    ridge := shoulder + up * width * .24
    lit := color_lerp(color, {186, 204, 118, 255}, .10)
    shade := color_lerp(color, {25, 61, 31, 255}, .14)

    shape := u32(leaf_mesh.Shape.Grapevine)
    world_generated_leaf_textured_facet(stem_left, left, ridge, {.36, 0}, {0, .42}, {.5, .42}, up, shade, shape)
    world_generated_leaf_textured_facet(stem_left, ridge, stem_right, {.36, 0}, {.5, .42}, {.64, 0}, up, color, shape)
    world_generated_leaf_textured_facet(left, tip, ridge, {0, .42}, {.5, 1}, {.5, .42}, up, lit, shape)
    world_generated_leaf_textured_facet(ridge, tip, right_point, {.5, .42}, {.5, 1}, {1, .42}, up, color, shape)
    world_generated_leaf_textured_facet(
        stem_right,
        ridge,
        right_point,
        {.64, 0},
        {.5, .42},
        {1, .42},
        up,
        shade,
        shape,
    )

    if hero {
        // The catalog's Near architecture is shared by Hero and Near, so the
        // closest tier adds the raised vein that is large enough to read at
        // arm's length. This makes Hero visually distinct without adding a
        // serialized plant-detail tier or duplicating cached architectures.
        world_tube_between(center, tip, forward, max(width * .032, f32(.003)), max(width * .014, f32(.0015)), shade)
    }
}

world_generated_leaf_hero :: proc(
    center, forward, up, right: third_person.Vec3,
    width, length: f32,
    shape: u32,
    color: canvas2d.Color,
) {
    tip := center + forward * length
    shoulder := center + forward * length * .42
    left := shoulder - right * width
    right_point := shoulder + right * width
    ridge := shoulder + up * width * .18
    stem_left := center - right * width * .35
    stem_right := center + right * width * .35
    lit := color_lerp(color, {181, 207, 126, 255}, .08)
    shade := color_lerp(color, {24, 65, 33, 255}, .12)

    world_generated_leaf_textured_facet(stem_left, left, ridge, {.32, 0}, {0, .42}, {.5, .42}, up, shade, shape)
    world_generated_leaf_textured_facet(stem_left, ridge, stem_right, {.32, 0}, {.5, .42}, {.68, 0}, up, color, shape)
    world_generated_leaf_textured_facet(left, tip, ridge, {0, .42}, {.5, 1}, {.5, .42}, up, lit, shape)
    world_generated_leaf_textured_facet(ridge, tip, right_point, {.5, .42}, {.5, 1}, {1, .42}, up, color, shape)
    world_generated_leaf_textured_facet(
        stem_right,
        ridge,
        right_point,
        {.68, 0},
        {.5, .42},
        {1, .42},
        up,
        shade,
        shape,
    )
}

world_generated_pine_needle_clump :: proc(
    center, forward, up, right: third_person.Vec3,
    spread, length: f32,
    color: canvas2d.Color,
    hero: bool,
) {
    // One attachment represents a tuft, not one botanical fascicle. Enough
    // crossed ribbons and a game-scale minimum width keep the clump legible in
    // a full-tree view while the open radial construction preserves air.
    needle_count := hero ? 14 : 8
    needle_half_width := max(spread * .11, f32(.0032))
    for needle in 0 ..< needle_count {
        angle := f32(needle) * math.PI * 2 / f32(needle_count) + f32(needle % 2) * .19
        radial := right * math.cos(angle) + up * math.sin(angle)
        tangent := linalg.normalize0(linalg.cross(forward, radial))
        if linalg.dot(tangent, tangent) < .001 do tangent = right
        needle_length := length * (.88 + f32((needle * 7) % 5) * .03)
        root := center + radial * spread * .035
        shoulder := root + forward * needle_length * .48 + radial * spread * .18
        tip := root + forward * needle_length + radial * spread * (.62 + f32(needle % 3) * .08)
        shade := color_lerp(color, {21, 54, 30, 255}, f32(needle % 3) * .035)
        world_generated_leaf_facet(
            root - tangent * needle_half_width,
            shoulder - tangent * needle_half_width * .72,
            shoulder + tangent * needle_half_width * .72,
            radial,
            shade,
        )
        world_generated_leaf_facet(
            root - tangent * needle_half_width,
            shoulder + tangent * needle_half_width * .72,
            root + tangent * needle_half_width,
            radial,
            shade,
        )
        world_generated_leaf_facet(
            shoulder - tangent * needle_half_width * .72,
            tip,
            shoulder + tangent * needle_half_width * .72,
            radial,
            color,
        )
    }
}

world_generated_fleshy_node :: proc(
    center, forward, up, right: third_person.Vec3,
    width, length, thickness: f32,
    color: canvas2d.Color,
    smooth_shading: bool = false,
) {
    shoulder := center + forward * length * .46
    tip := center + forward * length
    half_depth := max(thickness * .5, f32(.002))
    base_front, base_back := center + up * half_depth, center - up * half_depth
    left_front, left_back := shoulder - right * width + up * half_depth, shoulder - right * width - up * half_depth
    right_front, right_back := shoulder + right * width + up * half_depth, shoulder + right * width - up * half_depth
    tip_front, tip_back := tip + up * half_depth * .12, tip - up * half_depth * .12
    shade := color_lerp(color, {25, 66, 39, 255}, .12)

    if smooth_shading {
        // Agave blades have a continuous waxy skin. Share rounded normals
        // across the coarse silhouette mesh so its construction triangles do
        // not read as separate planar lobes under directional light.
        base_front_normal := linalg.normalize0(up - forward * .18)
        base_back_normal := linalg.normalize0(-up - forward * .18)
        left_front_normal := linalg.normalize0(up - right)
        left_back_normal := linalg.normalize0(-up - right)
        right_front_normal := linalg.normalize0(up + right)
        right_back_normal := linalg.normalize0(-up + right)
        tip_front_normal := linalg.normalize0(up + forward * .28)
        tip_back_normal := linalg.normalize0(-up + forward * .28)

        world_generated_leaf_smooth_facet(
            base_front,
            left_front,
            tip_front,
            base_front_normal,
            left_front_normal,
            tip_front_normal,
            color,
        )
        world_generated_leaf_smooth_facet(
            base_front,
            tip_front,
            right_front,
            base_front_normal,
            tip_front_normal,
            right_front_normal,
            color,
        )
        world_generated_leaf_smooth_facet(
            base_back,
            tip_back,
            left_back,
            base_back_normal,
            tip_back_normal,
            left_back_normal,
            shade,
        )
        world_generated_leaf_smooth_facet(
            base_back,
            right_back,
            tip_back,
            base_back_normal,
            right_back_normal,
            tip_back_normal,
            shade,
        )
        world_generated_leaf_smooth_facet(
            base_front,
            base_back,
            left_back,
            base_front_normal,
            base_back_normal,
            left_back_normal,
            shade,
        )
        world_generated_leaf_smooth_facet(
            base_front,
            left_back,
            left_front,
            base_front_normal,
            left_back_normal,
            left_front_normal,
            shade,
        )
        world_generated_leaf_smooth_facet(
            right_front,
            right_back,
            base_back,
            right_front_normal,
            right_back_normal,
            base_back_normal,
            color,
        )
        world_generated_leaf_smooth_facet(
            right_front,
            base_back,
            base_front,
            right_front_normal,
            base_back_normal,
            base_front_normal,
            color,
        )
        world_generated_leaf_smooth_facet(
            left_front,
            left_back,
            tip_back,
            left_front_normal,
            left_back_normal,
            tip_back_normal,
            shade,
        )
        world_generated_leaf_smooth_facet(
            left_front,
            tip_back,
            tip_front,
            left_front_normal,
            tip_back_normal,
            tip_front_normal,
            shade,
        )
        world_generated_leaf_smooth_facet(
            tip_front,
            tip_back,
            right_back,
            tip_front_normal,
            tip_back_normal,
            right_back_normal,
            color,
        )
        world_generated_leaf_smooth_facet(
            tip_front,
            right_back,
            right_front,
            tip_front_normal,
            right_back_normal,
            right_front_normal,
            color,
        )
        return
    }

    world_generated_leaf_facet(base_front, left_front, tip_front, up, color)
    world_generated_leaf_facet(base_front, tip_front, right_front, up, color)
    world_generated_leaf_facet(base_back, tip_back, left_back, -up, shade)
    world_generated_leaf_facet(base_back, right_back, tip_back, -up, shade)
    world_generated_leaf_facet(base_front, base_back, left_back, -right, shade)
    world_generated_leaf_facet(base_front, left_back, left_front, -right, shade)
    world_generated_leaf_facet(right_front, right_back, base_back, right, color)
    world_generated_leaf_facet(right_front, base_back, base_front, right, color)
    world_generated_leaf_facet(left_front, left_back, tip_back, -right, shade)
    world_generated_leaf_facet(left_front, tip_back, tip_front, -right, shade)
    world_generated_leaf_facet(tip_front, tip_back, right_back, right, color)
    world_generated_leaf_facet(tip_front, right_back, right_front, right, color)
}

world_generated_plant_flower_hero :: proc(center: third_person.Vec3, radius, scale: f32, color: canvas2d.Color) {
    // A close flower needs a radial silhouette. The ordinary LOD's single
    // upright prism is deliberately retained outside arm's reach.
    petal_radius := radius * scale * .62
    spread := radius * scale * .72
    for petal in 0 ..< 5 {
        angle := f32(petal) * math.PI * 2 / 5
        petal_center := center + third_person.Vec3{math.cos(angle) * spread, 0, math.sin(angle) * spread}
        world_vertical_prism(petal_center, petal_radius, petal_radius * .72, petal_radius * .72, angle, color)
    }
    world_vertical_prism(center, petal_radius * .68, petal_radius * .68, petal_radius, 0, color)
}

world_generated_ornamental_flower :: proc(
    species: plants.Species,
    center: third_person.Vec3,
    radius, scale: f32,
    color: canvas2d.Color,
) -> bool {
    switch species {
    case .Hydrangea_Bush, .Hydrangea_Tree:
        // Hydrangea inflorescences read as broad mopheads, not individual
        // flowers. A shallow Fibonacci dome stays legible from every angle.
        for floret in 0 ..< 13 {
            t := f32(floret) / 12
            angle := f32(floret) * 2.399963
            ring := math.sqrt(t) * radius * scale * 2.7
            floret_center :=
                center +
                third_person.Vec3{math.cos(angle) * ring, (1 - t) * radius * scale * .9, math.sin(angle) * ring}
            world_vertical_prism(
                floret_center,
                radius * scale * .72,
                radius * scale * .72,
                radius * scale * .38,
                angle,
                color,
            )
        }
        return true
    case .Agapanthus:
        // Tall stems terminate in open radial umbels.
        for floret in 0 ..< 9 {
            angle := f32(floret) * math.PI * 2 / 9
            floret_center :=
                center +
                third_person.Vec3 {
                        math.cos(angle) * radius * scale * 2.5,
                        radius * scale * (.5 + f32(floret & 1) * .35),
                        math.sin(angle) * radius * scale * 2.5,
                    }
            world_vertical_prism(
                floret_center,
                radius * scale * .62,
                radius * scale * .62,
                radius * scale,
                angle,
                color,
            )
        }
        return true
    case .Wisteria:
        // Repeated descending florets turn distributed attachment sites into
        // the hanging racemes that distinguish wisteria from other climbers.
        for floret in 0 ..< 5 {
            floret_center :=
                center +
                third_person.Vec3 {
                        math.sin(f32(floret) * 2.4) * radius * scale * .7,
                        -f32(floret) * radius * scale * 1.25,
                        math.cos(f32(floret) * 2.4) * radius * scale * .55,
                    }
            taper := 1 - f32(floret) * .11
            world_vertical_prism(
                floret_center,
                radius * scale * taper,
                radius * scale * taper,
                radius * scale * .9,
                0,
                color,
            )
        }
        return true
    case .Olive,
         .Italian_Cypress,
         .Grapevine,
         .Fig,
         .Lemon,
         .Pomegranate,
         .Almond,
         .Oleander,
         .Bougainvillea,
         .Rosemary,
         .Stone_Pine,
         .Bay_Laurel,
         .Carob,
         .Strawberry_Tree,
         .Myrtle,
         .Mastic,
         .Lavender,
         .Thyme,
         .Sage,
         .Prickly_Pear,
         .Pelargonium,
         .Climbing_Rose,
         .Star_Jasmine,
         .Holm_Oak,
         .Oriental_Plane,
         .European_Hackberry,
         .White_Poplar,
         .Golden_Barrel,
         .Agave,
         .Aloe,
         .Aeonium,
         .Echeveria,
         .Jade_Plant,
         .Stonecrop,
         .Blue_Chalk_Sticks,
         .Golden_Torch_Cactus:
    }
    return false
}

// world_generated_plant is the lightweight world-facing consumer of the plant
// catalog. Labs can retain their high-detail meshes, while generated places
// use the same botanical architecture and attachment data at camera-appropriate
// detail levels.
world_generated_plant :: proc(
    species: plants.Species,
    seed: u64,
    base: third_person.Vec3,
    scale: f32 = 1,
    yaw: f32 = 0,
    habit: plants.Growth_Habit = .Free_Standing,
    support: ^plants.Support_Surface = nil,
    detail_floor: plants.Detail_Level = .Near,
    along_grade: f32 = 0,
    maturity: f32 = 1,
    cache_geometry: bool = false,
    site: plants.Site_Context = {},
    foliage_mode: Generated_Plant_Foliage_Mode = .Leaves,
) -> bool {
    render_lod := Generated_Plant_Render_LOD.Hero
    if world_renderer.editor != nil {
        render_lod = generated_plant_render_lod(world_renderer.editor.camera_pose.position, base)
    }
    hero_geometry := generated_plant_uses_hero_geometry(render_lod)
    detail := generated_plant_catalog_detail(render_lod)
    detail = generated_plant_apply_detail_floor(detail, detail_floor)
    support_signature: u64
    if support != nil do support_signature = plants.support_hash(support^)
    resolved_site := site
    if !resolved_site.valid && world_renderer.editor != nil do resolved_site = generated_plant_site_context(world_renderer.editor, base)
    site_signature := plants.site_context_signature(resolved_site)
    maturity_step := generated_plant_maturity_step(maturity)
    shadow_first := len(world_renderer.vertices)
    if cache_geometry {
        cached := generated_plant_world_cache_find(
            species,
            seed,
            detail,
            render_lod,
            foliage_mode,
            habit,
            support_signature,
            site_signature,
            maturity_step,
            base,
            scale,
            yaw,
            along_grade,
        )
        if cached != nil {
            append(&world_renderer.vertices, ..cached.vertices[:])
            if cached.shadow_all_cast {
                world_register_static_shadow_caster(
                    shadow_first,
                    len(cached.vertices),
                    cached.shadow_min,
                    cached.shadow_max,
                )
            } else {
                world_register_shadow_caster(shadow_first)
            }
            return true
        }
    }
    generated_entry := generated_plant_cached(species, seed, detail, habit, support, maturity, resolved_site)
    if generated_entry == nil do return false
    generated := &generated_entry.result
    density_area_scale := f32(1)
    if foliage_mode == .Density_Clumps {
        // Far attachments are botanical cluster representatives. Restore the
        // projected density encoded by the catalog's Near/Far cluster ratio
        // without allocating a second full Near architecture for every tree.
        near_cluster_size := plants.leaf_cluster_size(species, .Near, maturity)
        far_cluster_size := plants.leaf_cluster_size(species, .Far, maturity)
        density_area_scale = f32(near_cluster_size) / f32(max(far_cluster_size, 1))
    }
    transform := generated_plant_transform_make(base, yaw, scale, along_grade)

    _, leaf_color, accent := plant_generator_colors(species)
    bark := plant_bark.profile(species)
    bark_detail_strength: f32 = 1
    switch render_lod {
    case .Hero:
        bark_detail_strength = 1
    case .Near:
        bark_detail_strength = .82
    case .Medium:
        bark_detail_strength = .52
    case .Far:
        bark_detail_strength = .24
    case .Distant:
        bark_detail_strength = .10
    }
    for segment, segment_index in generated.plant.segments {
        if species == .Prickly_Pear ||
           species == .Golden_Barrel ||
           species == .Agave ||
           species == .Aloe ||
           species == .Echeveria ||
           species == .Stonecrop ||
           species == .Blue_Chalk_Sticks ||
           species == .Golden_Torch_Cactus {
            continue
        }
        segment_delta := segment.end - segment.start
        segment_length := f32(math.sqrt(f64(linalg.dot(segment_delta, segment_delta))))
        bark_segment := generated_entry.bark_topology[segment_index]
        generated_plant_middle_branch_emit(
            segment,
            transform,
            {bark.base_color[0], bark.base_color[1], bark.base_color[2], 255},
        )
    }

    LEAF_CLUMP_COUNT :: 4
    leaf_clumps: [LEAF_CLUMP_COUNT]Generated_Plant_Leaf_Clump
    for &clump in leaf_clumps {
        clump.minimum = {1e30, 1e30, 1e30}
        clump.maximum = {-1e30, -1e30, -1e30}
    }
    for attachment, attachment_index in generated.plant.attachments {
        if foliage_mode == .Density_Clumps && attachment.kind != .Leaf do continue
        center := generated_plant_point(transform, attachment.position)
        if attachment.kind == .Fruit || attachment.kind == .Flower {
            radius := attachment.kind == .Fruit ? f32(.07) : f32(.045)
            stage_scale: f32 = 1
            #partial switch attachment.stage {
            case .Bud, .Fruit_Set:
                stage_scale = .46
            case .Opening, .Immature_Fruit:
                stage_scale = .68
            case .Half_Open, .Ripening_Fruit:
                stage_scale = .86
            case .Bloom, .Ripe_Fruit, .None:
                stage_scale = 1
            }
            reproductive_color := accent
            if attachment.kind == .Flower {
                reproductive_color = plant_generator_flower_color(
                    species,
                    seed,
                    attachment.variant,
                    reproductive_color,
                )
            }
            reproductive_color = plant_generator_stage_color(reproductive_color, attachment.stage)
            radius *= stage_scale
            if attachment.kind == .Flower &&
               world_generated_ornamental_flower(species, center, radius, scale, reproductive_color) {
                continue
            }
            if species == .Grapevine && attachment.kind == .Fruit && render_lod != .Distant {
                berry_count := render_lod == .Hero || render_lod == .Near ? 5 : 3
                for berry in 0 ..< berry_count {
                    angle := f32(berry) * 2.4 + f32(attachment_index) * .31
                    ring := berry % 3
                    offset := third_person.Vec3 {
                        math.cos(angle) * (.050 - f32(ring) * .006) * scale,
                        (-.035 - f32(berry / 3) * .065) * scale,
                        math.sin(angle) * .032 * scale,
                    }
                    world_ellipsoid_rotated(
                        center + offset,
                        .042 * stage_scale * scale,
                        .049 * stage_scale * scale,
                        .042 * stage_scale * scale,
                        angle + yaw,
                        reproductive_color,
                    )
                }
                continue
            }
            if attachment.kind == .Flower && render_lod == .Hero {
                world_generated_plant_flower_hero(center, radius, scale, reproductive_color)
                continue
            }
            if render_lod == .Distant do continue
            world_vertical_prism(center, radius * scale, radius * scale, radius * scale * 1.6, 0, reproductive_color)
            continue
        }
        if attachment.kind != .Leaf do continue

        leaf_first := len(world_renderer.vertices)
        forward := linalg.normalize0(generated_plant_vector(transform, attachment.forward))
        up := linalg.normalize0(generated_plant_vector(transform, attachment.up))
        right := linalg.normalize0(linalg.cross(forward, up))
        if linalg.dot(right, right) < .001 do right = {1, 0, 0}
        width := max(attachment.leaf.width * scale * 1.8, f32(.018))
        length := max(attachment.leaf.length * scale * 1.8, f32(.035))
        color := plant_generator_leaf_color(species, attachment.variant, leaf_color)
        color = generated_plant_site_leaf_color(species, color, resolved_site, attachment.variant)
        if foliage_mode == .Density_Clumps && attachment.leaf.thickness <= 0 {
            local_angle := math.atan2(attachment.position[2], attachment.position[0])
            angle_unit := (local_angle + math.PI) / math.TAU
            clump_index := clamp(int(angle_unit * LEAF_CLUMP_COUNT), 0, LEAF_CLUMP_COUNT - 1)
            clump := &leaf_clumps[clump_index]
            area := max(width * length * .72 * density_area_scale, f32(.0001))
            clump.weighted_center += center * area
            clump.projected_area += area
            clump.red += f32(color.r) * area
            clump.green += f32(color.g) * area
            clump.blue += f32(color.b) * area
            clump.minimum.x = min(clump.minimum.x, center.x - width)
            clump.minimum.y = min(clump.minimum.y, center.y - width * .35)
            clump.minimum.z = min(clump.minimum.z, center.z - width)
            clump.maximum.x = max(clump.maximum.x, center.x + width)
            clump.maximum.y = max(clump.maximum.y, center.y + length * .45)
            clump.maximum.z = max(clump.maximum.z, center.z + width)
            clump.count += 1
            continue
        }
        if attachment.leaf.thickness > 0 {
            world_generated_fleshy_node(
                center,
                forward,
                up,
                right,
                width,
                length,
                attachment.leaf.thickness * scale * 1.8,
                color,
                species == .Agave,
            )
            generated_plant_mark_wind_attachment(leaf_first, transform.base, center)
            continue
        }
        if species == .Grapevine {
            world_generated_grape_leaf_3d(center, forward, up, right, width, length, color, hero_geometry)
            generated_plant_mark_wind_attachment(leaf_first, transform.base, center)
            continue
        }
        if generated_plant_leaf_emit(
            center,
            forward,
            up,
            right,
            width,
            length,
            attachment.leaf.shape,
            color,
            hero_geometry,
        ) {
            continue
        }
        tip := center + forward * length
        shoulder := center + forward * length * .42
        a, b := center - right * width * .35, shoulder - right * width
        c, d := tip, shoulder + right * width
        shape := u32(attachment.leaf.shape)
        world_generated_leaf_textured_facet(a, b, c, {.32, 0}, {0, .42}, {.5, 1}, up, color, shape)
        world_generated_leaf_textured_facet(a, c, d, {.32, 0}, {.5, 1}, {1, .42}, up, color, shape)
        generated_plant_mark_wind_attachment(leaf_first, transform.base, center)
    }
    if foliage_mode == .Density_Clumps {
        total_projected_area := f32(0)
        for clump in leaf_clumps do total_projected_area += clump.projected_area
        profile := plants.garden_profile(species)
        mature_spread := profile.mature_spread * transform.scale
        target_projected_area := mature_spread * mature_spread * .32
        area_normalization := clamp(
            target_projected_area / max(total_projected_area, f32(.0001)),
            f32(1),
            f32(4),
        )
        proxy_minimum := third_person.Vec3{1e30, 1e30, 1e30}
        proxy_maximum := third_person.Vec3{-1e30, -1e30, -1e30}
        for clump, clump_index in leaf_clumps {
            if clump.count == 0 || clump.projected_area <= 0 do continue
            center := clump.weighted_center / clump.projected_area
            span := clump.maximum - clump.minimum
            // Match the summed projected area of the replaced cards while
            // retaining the branch cluster's authored spatial envelope.
            area_radius := f32(math.sqrt(f64(clump.projected_area * area_normalization * .34 / math.PI)))
            radius_x := max(area_radius * 1.12, span.x * .34)
            radius_y := max(area_radius * .54, span.y * .28)
            radius_z := max(area_radius * .92, span.z * .34)
            proxy_minimum.x = min(proxy_minimum.x, center.x - radius_x)
            proxy_minimum.y = min(proxy_minimum.y, center.y - radius_y)
            proxy_minimum.z = min(proxy_minimum.z, center.z - radius_z)
            proxy_maximum.x = max(proxy_maximum.x, center.x + radius_x)
            proxy_maximum.y = max(proxy_maximum.y, center.y + radius_y)
            proxy_maximum.z = max(proxy_maximum.z, center.z + radius_z)
            color := canvas2d.Color {
                u8(clamp(clump.red / clump.projected_area, f32(0), f32(255))),
                u8(clamp(clump.green / clump.projected_area, f32(0), f32(255))),
                u8(clamp(clump.blue / clump.projected_area, f32(0), f32(255))),
                255,
            }
            generated_plant_middle_clump_emit(
                center,
                radius_x,
                radius_y,
                radius_z,
                yaw + f32(clump_index) * .37,
                color,
            )
        }
        if proxy_minimum.x < proxy_maximum.x {
            proxy_center := (proxy_minimum + proxy_maximum) * .5
            proxy_radius := (proxy_maximum - proxy_minimum) * .5
            append(
                &world_renderer.middle_tree_shadow_proxies,
                Middle_Tree_Shadow_Proxy {
                    center = proxy_center,
                    radius_x = proxy_radius.x,
                    radius_y = max(proxy_radius.y, f32(.18)),
                    radius_z = proxy_radius.z,
                },
            )
        }
    }
    if cache_geometry {
        generated_plant_world_cache_store(
            species,
            seed,
            detail,
            render_lod,
            foliage_mode,
            habit,
            support_signature,
            site_signature,
            maturity_step,
            base,
            scale,
            yaw,
            along_grade,
            world_renderer.vertices[shadow_first:],
        )
    }
    world_register_shadow_caster(shadow_first)
    return true
}
