package main

import lsystem "../packages/lsystem"
import plants "../packages/plants"
import third_person "../packages/third_person"
import "core:math"
import "core:math/linalg"
import rl "zelda_engine:canvas2d"

GENERATED_PLANT_CACHE_CAPACITY :: (SETTLEMENT_PATIO_CAPACITY * 2 + MARINA_GEOMETRY_CACHE_CAPACITY * 3) * 3

Generated_Plant_Cache_Entry :: struct {
    species: plants.Species,
    seed:    u64,
    detail:  plants.Detail_Level,
    result:  plants.Generate_Result,
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

generated_plant_cached :: proc(
    species: plants.Species,
    seed: u64,
    detail: plants.Detail_Level,
) -> ^plants.Generate_Result {
    for index in 0 ..< generated_plant_cache_count {
        entry := &generated_plant_cache[index]
        if entry.species == species && entry.seed == seed && entry.detail == detail do return &entry.result
    }
    if generated_plant_cache_count >= len(generated_plant_cache) do return nil
    result := plants.generate(
        {
            species = species,
            seed = seed,
            maturity = 1,
            detail = detail,
            habit = .Free_Standing,
        },
    )
    if result.error != .None {
        plants.destroy(&result)
        return nil
    }
    entry := &generated_plant_cache[generated_plant_cache_count]
    entry^ = {species = species, seed = seed, detail = detail, result = result}
    generated_plant_cache_count += 1
    return &entry.result
}

generated_plant_cache_destroy :: proc() {
    for index in 0 ..< generated_plant_cache_count {
        plants.destroy(&generated_plant_cache[index].result)
    }
    generated_plant_cache = {}
    generated_plant_cache_count = 0
}

generated_plant_point :: #force_inline proc(
    base: third_person.Vec3,
    point: lsystem.Vec3,
    yaw, scale: f32,
) -> third_person.Vec3 {
    cosine, sine := math.cos(yaw), math.sin(yaw)
    return {
        base.x + (point[0] * cosine - point[2] * sine) * scale,
        base.y + point[1] * scale,
        base.z + (point[0] * sine + point[2] * cosine) * scale,
    }
}

generated_plant_vector :: #force_inline proc(vector: lsystem.Vec3, yaw: f32) -> third_person.Vec3 {
    cosine, sine := math.cos(yaw), math.sin(yaw)
    return {
        vector[0] * cosine - vector[2] * sine,
        vector[1],
        vector[0] * sine + vector[2] * cosine,
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

world_generated_plant_flower_hero :: proc(
    center: third_person.Vec3,
    radius, scale: f32,
    color: rl.Color,
) {
    // A close flower needs a radial silhouette. The ordinary LOD's single
    // upright prism is deliberately retained outside arm's reach.
    petal_radius := radius * scale * .62
    spread := radius * scale * .72
    for petal in 0 ..< 5 {
        angle := f32(petal) * math.PI * 2 / 5
        petal_center := center + third_person.Vec3{math.cos(angle) * spread, 0, math.sin(angle) * spread}
        world_vertical_prism(
            petal_center,
            petal_radius,
            petal_radius * .72,
            petal_radius * .72,
            angle,
            color,
        )
    }
    world_vertical_prism(center, petal_radius * .68, petal_radius * .68, petal_radius, 0, color)
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
) -> bool {
    render_lod := Generated_Plant_Render_LOD.Hero
    if world_renderer.editor != nil {
        render_lod = generated_plant_render_lod(world_renderer.editor.camera_pose.position, base)
    }
    detail := generated_plant_catalog_detail(render_lod)
    generated := generated_plant_cached(species, seed, detail)
    if generated == nil do return false

    wood, leaf_color, accent := plant_generator_colors(species)
    for segment in generated.plant.segments {
        start := generated_plant_point(base, segment.start, yaw, scale)
        end := generated_plant_point(base, segment.end, yaw, scale)
        forward := linalg.normalize0(end - start)
        if linalg.dot(forward, forward) < .001 do continue
        world_tube_between(
            start,
            end,
            forward,
            max(segment.radius_start * scale, f32(.006)),
            max(segment.radius_end * scale, f32(.004)),
            wood,
        )
    }

    for attachment in generated.plant.attachments {
        center := generated_plant_point(base, attachment.position, yaw, scale)
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
            reproductive_color := plant_generator_stage_color(accent, attachment.stage)
            radius *= stage_scale
            if attachment.kind == .Flower && render_lod == .Hero {
                world_generated_plant_flower_hero(center, radius, scale, reproductive_color)
                continue
            }
            if render_lod == .Distant do continue
            world_vertical_prism(
                center,
                radius * scale,
                radius * scale,
                radius * scale * 1.6,
                0,
                reproductive_color,
            )
            continue
        }
        if attachment.kind != .Leaf do continue

        forward := linalg.normalize0(generated_plant_vector(attachment.forward, yaw))
        up := linalg.normalize0(generated_plant_vector(attachment.up, yaw))
        right := linalg.normalize0(linalg.cross(forward, up))
        if linalg.dot(right, right) < .001 do right = {1, 0, 0}
        width := max(attachment.leaf.width * scale * 1.8, f32(.018))
        length := max(attachment.leaf.length * scale * 1.8, f32(.035))
        tip := center + forward * length
        shoulder := center + forward * length * .42
        a, b := center - right * width * .35, shoulder - right * width
        c, d := tip, shoulder + right * width
        color := plant_generator_leaf_color(species, attachment.variant, leaf_color)
        world_quad(a, b, c, d, color)
        world_quad(d, c, b, a, color)
    }
    return true
}
