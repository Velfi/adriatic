package main

import leaf_mesh "../packages/leaf_mesh"
import lsystem "../packages/lsystem"
import plant_bark "../packages/plant_bark"
import plants "../packages/plants"
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
    base:              third_person.Vec3,
    cosine, sine:      f32,
    scale, along_grade: f32,
}

generated_plant_cache: [GENERATED_PLANT_CACHE_CAPACITY]Generated_Plant_Cache_Entry
generated_plant_cache_count: int

Generated_Plant_Render_LOD :: enum u8 {
    Hero,
    Near,
    Medium,
    Far,
    Distant,
}

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

generated_plant_cached :: proc(
    species: plants.Species,
    seed: u64,
    detail: plants.Detail_Level,
    habit: plants.Growth_Habit = .Free_Standing,
    support: ^plants.Support_Surface = nil,
    maturity: f32 = 1,
) -> ^Generated_Plant_Cache_Entry {
    support_signature: u64
    if support != nil do support_signature = plants.support_hash(support^)
    maturity_step := generated_plant_maturity_step(maturity)
    for index in 0 ..< generated_plant_cache_count {
        entry := &generated_plant_cache[index]
        if entry.species == species &&
           entry.seed == seed &&
           entry.detail == detail &&
           entry.habit == habit &&
           entry.support_signature == support_signature &&
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
        maturity_step     = maturity_step,
        result            = result,
    }
    entry.bark_topology = make([]Generated_Bark_Segment_Topology, len(result.plant.segments))
    for segment, segment_index in result.plant.segments {
        for parent_index in 0 ..< segment_index {
            parent := result.plant.segments[parent_index]
            delta := parent.end - segment.start
            if linalg.dot(delta, delta) < 1e-8 {
                parent_delta := parent.end - parent.start
                parent_length := f32(math.sqrt(f64(linalg.dot(parent_delta, parent_delta))))
                entry.bark_topology[segment_index].distance =
                    entry.bark_topology[parent_index].distance + parent_length
                entry.bark_topology[segment_index].has_parent = true
                entry.bark_topology[parent_index].has_child = true
                break
            }
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
generated_plant_transform_make :: #force_inline proc(
    base: third_person.Vec3,
    yaw, scale, along_grade: f32,
) -> Generated_Plant_Transform {
    return {
        base        = base,
        cosine      = math.cos(yaw),
        sine        = math.sin(yaw),
        scale       = scale,
        along_grade = along_grade,
    }
}

@(no_instrumentation)
generated_plant_point :: #force_inline proc(
    transform: Generated_Plant_Transform,
    point: lsystem.Vec3,
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
    vector: lsystem.Vec3,
) -> third_person.Vec3 {
    return {
        vector[0] * transform.cosine - vector[2] * transform.sine,
        vector[1] + vector[0] * transform.along_grade,
        vector[0] * transform.sine + vector[2] * transform.cosine,
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

// Draw a generated branch with the catalog bark sampled in plant-local
// coordinates. Local sampling keeps the result stable when an instance moves
// or rotates and makes adjacent LOD rebuilds retain the same visual identity.
world_generated_bark_segment :: proc(
    segment: lsystem.Segment,
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
    reference := math.abs(local_axis[1]) > .90 ? lsystem.Vec3{1, 0, 0} : lsystem.Vec3{0, 1, 0}
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
        // The catalog's Near skeleton is shared by Hero and Near, so the
        // closest tier adds the raised vein that is large enough to read at
        // arm's length. This makes Hero visually distinct without adding a
        // serialized plant-detail tier or duplicating cached skeletons.
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
// use the same botanical skeleton and attachment data at camera-appropriate
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
) -> bool {
    render_lod := Generated_Plant_Render_LOD.Hero
    if world_renderer.editor != nil {
        render_lod = generated_plant_render_lod(world_renderer.editor.camera_pose.position, base)
    }
    hero_geometry := generated_plant_uses_hero_geometry(render_lod)
    detail := generated_plant_catalog_detail(render_lod)
    detail = generated_plant_apply_detail_floor(detail, detail_floor)
    generated_entry := generated_plant_cached(species, seed, detail, habit, support, maturity)
    if generated_entry == nil do return false
    generated := &generated_entry.result
    transform := generated_plant_transform_make(base, yaw, scale, along_grade)

    shadow_first := len(world_renderer.vertices)
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
        world_generated_bark_segment(
            segment,
            bark,
            seed,
            transform,
            bark_detail_strength,
            bark_segment.distance,
            bark_segment.distance + segment_length,
            !bark_segment.has_parent,
            !bark_segment.has_child,
        )
    }

    for attachment, attachment_index in generated.plant.attachments {
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

        forward := linalg.normalize0(generated_plant_vector(transform, attachment.forward))
        up := linalg.normalize0(generated_plant_vector(transform, attachment.up))
        right := linalg.normalize0(linalg.cross(forward, up))
        if linalg.dot(right, right) < .001 do right = {1, 0, 0}
        width := max(attachment.leaf.width * scale * 1.8, f32(.018))
        length := max(attachment.leaf.length * scale * 1.8, f32(.035))
        color := plant_generator_leaf_color(species, attachment.variant, leaf_color)
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
            continue
        }
        if species == .Grapevine {
            world_generated_grape_leaf_3d(center, forward, up, right, width, length, color, hero_geometry)
            continue
        }
        if hero_geometry {
            world_generated_leaf_hero(center, forward, up, right, width, length, u32(attachment.leaf.shape), color)
            continue
        }
        tip := center + forward * length
        shoulder := center + forward * length * .42
        a, b := center - right * width * .35, shoulder - right * width
        c, d := tip, shoulder + right * width
        shape := u32(attachment.leaf.shape)
        world_generated_leaf_textured_facet(a, b, c, {.32, 0}, {0, .42}, {.5, 1}, up, color, shape)
        world_generated_leaf_textured_facet(a, c, d, {.32, 0}, {.5, 1}, {1, .42}, up, color, shape)
    }
    world_register_shadow_caster(shadow_first)
    return true
}
