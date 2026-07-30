package main

import atmosphere "../packages/atmosphere"
import branch_mesh "../packages/branch_mesh"
import flower_mesh "../packages/flower_mesh"
import fountains "../packages/fountains"
import leaf_mesh "../packages/leaf_mesh"
import lsystem "../packages/lsystem"
import plants "../packages/plants"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import rl "zelda_engine:canvas2d"

Garden_Style :: enum u8 {
    Courtyard,
    Kitchen,
    Wild,
}

Garden_Plant_Kind :: enum u8 {
    Cypress,
    Citrus,
    Shrub,
    Flower,
    Herb,
    Stone_Pine,
    Olive_Tree,
    Succulent,
    Groundcover,
}

Garden_Plant :: struct {
    position: third_person.Vec3,
    kind:     Garden_Plant_Kind,
    scale:    f32,
    color:    rl.Color,
}

Garden_Plan :: struct {
    style:       Garden_Style,
    seed:        u32,
    plants:      [128]Garden_Plant,
    plant_count: int,
    fountain:    fountains.Plan,
    fountain_at: third_person.Vec3,
}

garden_lab_seed := u32(73)
garden_lab_style := Garden_Style.Courtyard
garden_lab_plan: Garden_Plan
garden_lab_lsystem_plants: [13][4]plants.Generate_Result
garden_lab_lsystem_ready: [13][4]bool
garden_lab_branch_meshes: [13][4]branch_mesh.Mesh
garden_lab_branch_mesh_ready: [13][4]bool
garden_lab_leaf_meshes: [13][4]leaf_mesh.Mesh
garden_lab_arch_plant: plants.Generate_Result
garden_lab_arch_ready: bool
garden_lab_arch_branch_mesh: branch_mesh.Mesh
garden_lab_arch_branch_ready: bool
garden_lab_arch_leaf_meshes: [4]leaf_mesh.Mesh
garden_lab_kitchen_vine: plants.Generate_Result
garden_lab_kitchen_vine_ready: bool
garden_lab_kitchen_vine_branch_mesh: branch_mesh.Mesh
garden_lab_kitchen_vine_branch_ready: bool
garden_lab_kitchen_vine_leaf_meshes: [4]leaf_mesh.Mesh
garden_lab_flower_meshes: [4]flower_mesh.Mesh
garden_lab_mesh_vertices: [dynamic]World_Vertex
garden_lab_mesh_indices: [dynamic]u32
garden_lab_mesh_valid: bool
garden_lab_mesh_source_vertices: int
garden_lab_mesh_optimized_vertices: int
garden_lab_branch_instance_meshes: [13][4]int
garden_lab_leaf_instance_meshes: [13][4]int
garden_lab_flower_instance_meshes: [4]int

GARDEN_SOIL := rl.Color{91, 66, 43, 255}
GARDEN_STONE := rl.Color{202, 192, 165, 255}
GARDEN_STONE_DARK := rl.Color{139, 133, 116, 255}
GARDEN_LEAF := rl.Color{61, 105, 55, 255}
GARDEN_LEAF_LIGHT := rl.Color{93, 135, 67, 255}
GARDEN_CYPRESS := rl.Color{38, 78, 52, 255}
GARDEN_TERRACOTTA := rl.Color{171, 83, 48, 255}

garden_hash :: proc(value: u32) -> u32 {
    result := value
    result = (result ~ (result >> 16)) * 0x7feb352d
    result = (result ~ (result >> 15)) * 0x846ca68b
    return result ~ (result >> 16)
}

garden_random01 :: proc(seed: u32, index: int, salt: u32 = 0) -> f32 {
    value := garden_hash(seed + u32(index) * 0x9e3779b9 + salt)
    return f32(value & 0xffff) / 65535
}

garden_style_name :: proc(style: Garden_Style) -> cstring {
    switch style {
    case .Courtyard:
        return "COURTYARD"
    case .Kitchen:
        return "KITCHEN"
    case .Wild:
        return "WILD"
    }
    return "COURTYARD"
}

garden_add_plant :: proc(plan: ^Garden_Plan, plant: Garden_Plant) {
    if plan == nil || plan.plant_count >= len(plan.plants) do return
    plan.plants[plan.plant_count] = plant
    plan.plant_count += 1
}

garden_generate :: proc(seed: u32, style: Garden_Style) -> Garden_Plan {
    plan := Garden_Plan {
        seed  = seed,
        style = style,
    }
    switch style {
    case .Courtyard:
        plan.fountain = fountains.generate(
            seed ~ 0xF017A17,
            {
                radius = 2.25,
                style = .Tiered,
                jet_count = 8 + int(garden_hash(seed) % 5),
                jet_height = 1.9 + garden_random01(seed, 0, 0xF0) * .7,
            },
        )
        // Four clipped corners frame a bright, formal central court.
        for index in 0 ..< 4 {
            x := index % 2 == 0 ? f32(-7.4) : f32(7.4)
            z := index < 2 ? f32(-5.4) : f32(5.4)
            garden_add_plant(&plan, {{x, 0, z}, .Cypress, .88 + garden_random01(seed, index) * .18, GARDEN_CYPRESS})
        }
        // Oleander is a middle-height backdrop, not a clipped bed hedge.
        // Unequal overlapping groups gather against the perimeter while gaps
        // keep the cross paths and fountain court visually open.
        oleander_centers := [4]third_person.Vec3 {
            {5.9, 0, 5.9}, // dominant flowering mass
            {-6.3, 0, 5.7}, // secondary north-west group
            {8.1, 0, 1.8}, // east-wall punctuation
            {-8.0, 0, -2.1}, // west-wall punctuation
        }
        oleander_counts := [4]int{6, 4, 3, 3}
        oleander_index := 0
        for center, cluster_index in oleander_centers {
            count := oleander_counts[cluster_index]
            for member in 0 ..< count {
                angle := f32(member) * 2.399963 + garden_random01(seed, oleander_index, 11) * .7
                radius := member == 0 ? f32(0) : .62 + garden_random01(seed, oleander_index, 13) * .82
                position := center + third_person.Vec3{math.cos(angle) * radius, 0, math.sin(angle) * radius * .72}
                garden_add_plant(
                    &plan,
                    {position, .Shrub, .84 + garden_random01(seed, oleander_index, 17) * .28, GARDEN_LEAF},
                )
                oleander_index += 1
            }
        }
        // Low aromatic drifts occupy the formal beds without competing with
        // the oleander backdrop. Their loose stagger keeps them botanical
        // while retaining the courtyard's geometric four-bed organization.
        aromatic_centers := [4]third_person.Vec3{{-4.4, 0, -3.8}, {4.4, 0, -3.8}, {-4.4, 0, 3.8}, {4.4, 0, 3.8}}
        for center, bed_index in aromatic_centers {
            for member in 0 ..< 5 {
                column := member % 3
                row := member / 3
                jitter_x := (garden_random01(seed, bed_index * 5 + member, 31) - .5) * .22
                jitter_z := (garden_random01(seed, bed_index * 5 + member, 37) - .5) * .20
                garden_add_plant(
                    &plan,
                    {
                        center +
                        third_person.Vec3{(f32(column) - 1) * 1.05 + jitter_x, 0, (f32(row) - .5) * .92 + jitter_z},
                        .Groundcover,
                        .42 + garden_random01(seed, bed_index * 5 + member, 41) * .14,
                        {77, 111, 66, 255},
                    },
                )
            }
        }
        for index in 0 ..< 24 {
            angle := f32(index) / 24 * math.PI * 2
            radius := 3.05 + (garden_random01(seed, index, 23) - .5) * .32
            palette := [3]rl.Color{{201, 76, 68, 255}, {237, 188, 71, 255}, {202, 116, 163, 255}}
            garden_add_plant(
                &plan,
                {
                    {math.cos(angle) * radius, 0, math.sin(angle) * radius},
                    .Flower,
                    .75 + garden_random01(seed, index, 29) * .35,
                    palette[index % len(palette)],
                },
            )
        }
    case .Kitchen:
        plan.fountain_at = {7.8, 0, -6.7}
        plan.fountain = fountains.generate(
            seed ~ 0xC157E12,
            {radius = 2.2, style = .Bowl, jet_count = 1, jet_height = .75},
        )
        for index in 0 ..< 60 {
            bed := index / 15
            slot := index % 15
            // Aromatic beds are close-planted cultivated masses. Fifteen
            // independent L-systems per row let neighboring SDF crowns meet
            // without replacing them with a continuous hedge primitive.
            stagger := bed % 2 == 0 ? f32(0) : f32(.18)
            x := -6.6 + f32(slot) * (13.2 / 14) + stagger
            z := -4.5 + f32(bed) * 3
            color := bed % 2 == 0 ? GARDEN_LEAF_LIGHT : rl.Color{82, 119, 64, 255}
            garden_add_plant(&plan, {{x, 0, z}, .Herb, .7 + garden_random01(seed, index) * .45, color})
        }
        for index in 0 ..< 2 {
            garden_add_plant(
                &plan,
                {
                    {index == 0 ? f32(-7.2) : f32(7.2), 0, -6.1},
                    .Citrus,
                    .8 + garden_random01(seed, index, 51) * .16,
                    GARDEN_LEAF,
                },
            )
        }
    case .Wild:
        // Sparse upper-story anchors keep the maquis from collapsing into one
        // low shrub band. These remain generated catalog plants, not authored
        // stand-in geometry.
        garden_add_plant(&plan, {{-7.1, 0, -5.3}, .Stone_Pine, 1.05, {57, 92, 53, 255}})
        garden_add_plant(&plan, {{7.0, 0, 4.9}, .Olive_Tree, .92, {67, 101, 59, 255}})
        garden_add_plant(&plan, {{-6.7, 0, 4.8}, .Stone_Pine, .78, {77, 105, 67, 255}})
        for index in 0 ..< 5 {
            side := index % 2 == 0 ? f32(-1) : f32(1)
            garden_add_plant(
                &plan,
                {
                    {side * (5.7 + garden_random01(seed, index, 83) * 1.8), 0, -3.8 + f32(index) * 1.8},
                    .Succulent,
                    .72 + garden_random01(seed, index, 89) * .28,
                    {73, 116, 72, 255},
                },
            )
        }
        for station in 0 ..< 12 {
            z := -5.5 + f32(station)
            path_x := math.sin(z * .34) * 1.5
            for side in ([2]f32{-1, 1}) {
                side_index := side < 0 ? 0 : 1
                jitter := (garden_random01(seed, station * 2 + side_index, 97) - .5) * .14
                garden_add_plant(
                    &plan,
                    {
                        {path_x + side * (1.42 + jitter), 0, z},
                        .Groundcover,
                        .54 + garden_random01(seed, station * 2 + side_index, 99) * .18,
                        {77, 111, 66, 255},
                    },
                )
            }
        }
        for index in 0 ..< 72 {
            x := -8.5 + garden_random01(seed, index, 61) * 17
            z := -6.5 + garden_random01(seed, index, 67) * 13
            // Preserve a loose S-shaped walking route through the meadow.
            path_x := math.sin(z * .34) * 1.5
            if abs(x - path_x) < 1.15 do continue
            palette := [4]rl.Color {
                {220, 178, 61, 255},
                {188, 82, 105, 255},
                {224, 220, 184, 255},
                {112, 130, 185, 255},
            }
            kind := garden_random01(seed, index, 71) > .82 ? Garden_Plant_Kind.Shrub : Garden_Plant_Kind.Flower
            color := kind == .Shrub ? GARDEN_LEAF : palette[index % len(palette)]
            garden_add_plant(&plan, {{x, 0, z}, kind, .65 + garden_random01(seed, index, 79) * .75, color})
        }
    }
    return plan
}

garden_lab_rebuild :: proc() {
    garden_lab_plan = garden_generate(garden_lab_seed, garden_lab_style)
    garden_lab_rebuild_lsystem()
    garden_lab_mesh_valid = false
    garden_lab_mesh_source_vertices = 0
    garden_lab_mesh_optimized_vertices = 0
    clear(&garden_lab_mesh_vertices)
    clear(&garden_lab_mesh_indices)
    world_instance_meshes_clear()
    for stage in 0 ..< 4 do garden_lab_flower_instance_meshes[stage] = -1
    garden_lab_branch_instance_meshes = {}
    garden_lab_leaf_instance_meshes = {}
    for kind in 0 ..< 13 {
        for variant in 0 ..< 4 {
            garden_lab_branch_instance_meshes[kind][variant] = -1
            garden_lab_leaf_instance_meshes[kind][variant] = -1
        }
    }
}

garden_lab_destroy_lsystem :: proc() {
    for kind in 0 ..< len(garden_lab_lsystem_plants) {
        for variant in 0 ..< len(garden_lab_lsystem_plants[kind]) {
            if garden_lab_lsystem_ready[kind][variant] {
                plants.destroy(&garden_lab_lsystem_plants[kind][variant])
                garden_lab_lsystem_ready[kind][variant] = false
            }
            if garden_lab_branch_mesh_ready[kind][variant] {
                branch_mesh.destroy(&garden_lab_branch_meshes[kind][variant])
                garden_lab_branch_mesh_ready[kind][variant] = false
            }
        }
    }
    if garden_lab_arch_ready {
        plants.destroy(&garden_lab_arch_plant)
        garden_lab_arch_ready = false
    }
    if garden_lab_arch_branch_ready {
        branch_mesh.destroy(&garden_lab_arch_branch_mesh)
        garden_lab_arch_branch_ready = false
    }
    if garden_lab_kitchen_vine_ready {
        plants.destroy(&garden_lab_kitchen_vine)
        garden_lab_kitchen_vine_ready = false
    }
    if garden_lab_kitchen_vine_branch_ready {
        branch_mesh.destroy(&garden_lab_kitchen_vine_branch_mesh)
        garden_lab_kitchen_vine_branch_ready = false
    }
    delete(garden_lab_mesh_vertices)
    delete(garden_lab_mesh_indices)
    garden_lab_mesh_vertices = nil
    garden_lab_mesh_indices = nil
    garden_lab_mesh_valid = false
    world_instance_meshes_clear()
}

garden_species_display_scale :: proc(kind: int) -> f32 {
    switch kind {
    case 0:
        return .43
    case 1:
        return 1.65
    case 2:
        return 1.65
    case 3:
        return .95
    case 4:
        return 1.05
    case 5:
        return 1.55
    case 6:
        return 1.15
    case 7:
        return 1.45
    case 8:
        return 1.4
    case 9:
        return .95
    case 10:
        return 1.15
    case 11:
        return 1.8
    case 12:
        return 1.3
    }
    return 1
}

garden_local_crown :: proc(kind: int) -> (center, radii: lsystem.Vec3) {
    display_scale := garden_species_display_scale(kind)
    switch kind {
    case 0:
        return {0, 1.55 / display_scale, 0}, {.56 / display_scale, 1.85 / display_scale, .56 / display_scale}
    case 1:
        return {0, 1.05 / display_scale, 0}, {1.18 / display_scale, 1.08 / display_scale, 1.18 / display_scale}
    case 2:
        return {0, .38 / display_scale, 0}, {.88 / display_scale, .46 / display_scale, .88 / display_scale}
    case 3:
        return {0, .32 / display_scale, 0}, {.72 / display_scale, .38 / display_scale, .72 / display_scale}
    case 4:
        return {0, .36 / display_scale, 0}, {.76 / display_scale, .44 / display_scale, .76 / display_scale}
    case 5:
        return {0, .24 / display_scale, 0}, {.66 / display_scale, .28 / display_scale, .66 / display_scale}
    case 6:
        return {0, .36 / display_scale, 0}, {.72 / display_scale, .46 / display_scale, .72 / display_scale}
    case 7:
        return {0, .42 / display_scale, 0}, {.78 / display_scale, .54 / display_scale, .78 / display_scale}
    case 8:
        return {0, .38 / display_scale, 0}, {.84 / display_scale, .48 / display_scale, .84 / display_scale}
    case 9:
        return {0, 2.15 / display_scale, 0}, {1.8 / display_scale, .68 / display_scale, 1.8 / display_scale}
    case 10:
        return {0, 1.2 / display_scale, 0}, {1.45 / display_scale, 1.05 / display_scale, 1.45 / display_scale}
    case 11:
        return {0, .45 / display_scale, 0}, {.9 / display_scale, .55 / display_scale, .75 / display_scale}
    case 12:
        return {0, .32 / display_scale, 0}, {.62 / display_scale, .4 / display_scale, .62 / display_scale}
    }
    return {}, {1, 1, 1}
}

garden_clip_segment_to_crown :: proc(source: lsystem.Segment, kind: int) -> (result: lsystem.Segment, visible: bool) {
    center, radii := garden_local_crown(kind)
    // Preserve only the structural leader beneath an elevated tree crown.
    // Once it enters the canopy, it is clipped with the lateral growth; keeping
    // every depth-zero segment produced a bare spike above the foliage.
    if (kind == 9 || kind == 10) && source.depth == 0 && source.start[1] <= center[1] - radii[1] {
        result = source
        crown_top := center[1] + radii[1]
        if source.end[1] > crown_top {
            t := clamp((crown_top - source.start[1]) / max(source.end[1] - source.start[1], f32(.001)), f32(0), f32(1))
            result.end = source.start + (source.end - source.start) * t
            result.radius_end = source.radius_start + (source.radius_end - source.radius_start) * t
        }
        return result, true
    }
    a := (source.start - center) / radii
    b := (source.end - center) / radii
    direction := b - a
    coefficient_a := linalg.dot(direction, direction)
    coefficient_b := 2 * linalg.dot(a, direction)
    coefficient_c := linalg.dot(a, a) - 1
    start_inside := linalg.dot(a, a) <= 1
    end_inside := linalg.dot(b, b) <= 1
    if start_inside && end_inside do return source, true
    if coefficient_a < .000001 do return {}, false
    discriminant := coefficient_b * coefficient_b - 4 * coefficient_a * coefficient_c
    if discriminant < 0 do return {}, false
    root := f32(math.sqrt(f64(discriminant)))
    t0 := (-coefficient_b - root) / (2 * coefficient_a)
    t1 := (-coefficient_b + root) / (2 * coefficient_a)
    entry := clamp(min(t0, t1), f32(0), f32(1))
    exit := clamp(max(t0, t1), f32(0), f32(1))
    if exit <= entry do return {}, false
    start_t := start_inside ? f32(0) : entry
    end_t := end_inside ? f32(1) : exit
    if end_t <= start_t do return {}, false
    result = source
    result.start = source.start + (source.end - source.start) * start_t
    result.end = source.start + (source.end - source.start) * end_t
    result.radius_start = source.radius_start + (source.radius_end - source.radius_start) * start_t
    result.radius_end = source.radius_start + (source.radius_end - source.radius_start) * end_t
    return result, true
}

garden_lab_rebuild_lsystem :: proc() {
    garden_lab_destroy_lsystem()
    flower_config := flower_mesh.defaults()
    flower_config.petal_shape = .Rounded
    flower_config.petal_count = 5
    flower_config.segments = 7
    flower_config.center_segments = 10
    flower_config.petal_length = .14
    flower_config.petal_width = .09
    flower_config.base_radius = .018
    flower_config.center_radius = .035
    flower_config.center_height = .022
    flower_stages := [4]flower_mesh.Lifecycle_Stage{.Bud, .Opening, .Half_Open, .Bloom}
    for flower_stage, stage_index in flower_stages {
        garden_lab_flower_meshes[stage_index] = flower_mesh.generate_lifecycle(
            {stage = flower_stage, flower = flower_config, fruit = flower_mesh.fruit_defaults()},
        )
    }
    species := [13]plants.Species {
        .Italian_Cypress,
        .Lemon,
        .Oleander,
        .Rosemary,
        .Lavender,
        .Thyme,
        .Sage,
        .Myrtle,
        .Mastic,
        .Stone_Pine,
        .Olive,
        .Prickly_Pear,
        .Pelargonium,
    }
    for kind in 0 ..< len(garden_lab_lsystem_plants) {
        for variant in 0 ..< len(garden_lab_lsystem_plants[kind]) {
            generated := plants.generate(
                {
                    species = species[kind],
                    seed = u64(garden_lab_seed) + u64(kind * 313 + variant * 1013),
                    maturity = 1,
                    detail = .Medium,
                    habit = .Free_Standing,
                },
            )
            if generated.error != .None do continue
            garden_lab_lsystem_plants[kind][variant] = generated
            garden_lab_lsystem_ready[kind][variant] = true
            clipped_segments := make([dynamic]lsystem.Segment, 0, len(generated.plant.segments))
            for segment in generated.plant.segments {
                clipped, visible := garden_clip_segment_to_crown(segment, kind)
                if visible do append(&clipped_segments, clipped)
            }
            garden_lab_branch_meshes[kind][variant] = branch_mesh.generate(
                clipped_segments[:],
                {radial_segments = 6, samples_per_segment = 2, minimum_radius = .018},
            )
            delete(clipped_segments)
            garden_lab_branch_mesh_ready[kind][variant] = len(garden_lab_branch_meshes[kind][variant].indices) > 0
            traits := plants.leaf_traits(species[kind], u8(variant), 1)
            leaf_config := leaf_mesh.defaults(traits.shape)
            leaf_config.length = traits.length
            leaf_config.width = traits.width
            leaf_config.serration = traits.serration
            leaf_config.curl = traits.curl
            leaf_config.cup = traits.cup
            leaf_config.segments = kind == 0 ? 4 : 6
            garden_lab_leaf_meshes[kind][variant] = leaf_mesh.generate(leaf_config)
        }
    }
    arch_opening := [1]plants.Rect{{-1.18, 0, 1.18, 2.78}}
    arch_support := plants.Support_Surface {
        width      = 3.25,
        height     = 3.55,
        plane_z    = 0,
        root_x     = -1.48,
        exclusions = arch_opening[:],
        signature  = 0x67617264656e6172,
    }
    arch := plants.generate(
        {
            species = .Bougainvillea,
            seed = u64(garden_lab_seed) + 0xb067,
            maturity = 1,
            detail = .Near,
            habit = .Wall_Trained,
            support = &arch_support,
        },
    )
    if arch.error == .None {
        garden_lab_arch_plant = arch
        garden_lab_arch_ready = true
        garden_lab_arch_branch_mesh = branch_mesh.generate(
            arch.plant.segments[:],
            {
                radial_segments = 5,
                samples_per_segment = 2,
                minimum_radius = .014,
                radial_irregularity = .08,
                twist = .35,
                seed = u64(garden_lab_seed),
            },
        )
        garden_lab_arch_branch_ready = len(garden_lab_arch_branch_mesh.indices) > 0
        for variant in 0 ..< len(garden_lab_arch_leaf_meshes) {
            traits := plants.leaf_traits(.Bougainvillea, u8(variant), 1)
            config := leaf_mesh.defaults(traits.shape)
            config.length = traits.length
            config.width = traits.width
            config.serration = traits.serration
            config.curl = traits.curl
            config.cup = traits.cup
            config.segments = 6
            garden_lab_arch_leaf_meshes[variant] = leaf_mesh.generate(config)
        }
    }
    vine_support := plants.Support_Surface {
        width     = 5.8,
        height    = 2.65,
        plane_z   = 0,
        root_x    = -2.62,
        signature = 0x6772617065747265,
    }
    vine := plants.generate(
        {
            species = .Grapevine,
            seed = u64(garden_lab_seed) + 0x67726170,
            maturity = 1,
            detail = .Near,
            habit = .Trellised,
            support = &vine_support,
        },
    )
    mirror_support := vine_support
    mirror_support.root_x = 2.62
    mirror_support.signature = 0x6772617065747266
    mirror_vine := plants.generate(
        {
            species = .Grapevine,
            seed = u64(garden_lab_seed) + 0x67726171,
            maturity = 1,
            detail = .Near,
            habit = .Trellised,
            support = &mirror_support,
        },
    )
    if vine.error == .None && mirror_vine.error == .None {
        append(&vine.plant.segments, ..mirror_vine.plant.segments[:])
        append(&vine.plant.attachments, ..mirror_vine.plant.attachments[:])
    }
    plants.destroy(&mirror_vine)
    if vine.error == .None {
        garden_lab_kitchen_vine = vine
        garden_lab_kitchen_vine_ready = true
        garden_lab_kitchen_vine_branch_mesh = branch_mesh.generate(
            vine.plant.segments[:],
            {
                radial_segments = 5,
                samples_per_segment = 2,
                minimum_radius = .012,
                radial_irregularity = .12,
                twist = .5,
                seed = u64(garden_lab_seed) + 91,
            },
        )
        garden_lab_kitchen_vine_branch_ready = len(garden_lab_kitchen_vine_branch_mesh.indices) > 0
        for variant in 0 ..< len(garden_lab_kitchen_vine_leaf_meshes) {
            traits := plants.leaf_traits(.Grapevine, u8(variant), 1)
            config := leaf_mesh.defaults(traits.shape)
            config.length = traits.length
            config.width = traits.width
            config.serration = traits.serration
            config.curl = traits.curl
            config.cup = traits.cup
            config.segments = 8
            garden_lab_kitchen_vine_leaf_meshes[variant] = leaf_mesh.generate(config)
        }
    }
}

garden_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    garden_lab_seed = 73
    garden_lab_style = .Courtyard
    focus_arch := target == "arch" || target == "climber"
    focus_trellis := target == "trellis" || target == "grapevine"
    focus_herbs := target == "herbs" || target == "aromatics"
    focus_shrubs := target == "shrubs" || target == "maquis"
    focus_trees := target == "trees" || target == "anchors"
    focus_path := target == "path" || target == "groundcover"
    focus_flowers := target == "flowers" || target == "pelargonium"
    switch target {
    case "kitchen":
        garden_lab_style = .Kitchen
    case "trellis", "grapevine":
        garden_lab_style = .Kitchen
    case "herbs", "aromatics":
        garden_lab_style = .Kitchen
    case "wild", "meadow":
        garden_lab_style = .Wild
    case "shrubs", "maquis":
        garden_lab_style = .Wild
    case "trees", "anchors":
        garden_lab_style = .Wild
    case "path", "groundcover":
        garden_lab_style = .Wild
    case "wild-alt", "meadow-alt":
        garden_lab_style = .Wild
        garden_lab_seed = 211
    case "flowers", "pelargonium":
        garden_lab_style = .Courtyard
    case "alternate":
        garden_lab_seed = 211
    }
    garden_lab_rebuild()
    editor.in_map = true
    editor.capture_world_only = false
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    editor.project.sea_level = -20
    atmosphere.set_world_minutes(&editor.atmosphere, 9 * 60 + 35)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    camera_position := third_person.Vec3{0, 5.7, 13.4}
    camera_target := third_person.Vec3{0, .8, 0}
    switch garden_lab_style {
    case .Courtyard:
        camera_position = {5.4, 4.5, 12.1}
        camera_target = {0, .9, -.45}
    case .Kitchen:
        camera_position = {7.8, 3.9, 9.7}
        camera_target = {0, .72, -.5}
    case .Wild:
        camera_position = {7.2, 3.3, 9.7}
        camera_target = {0, .65, -.7}
    }
    if focus_arch {
        camera_position = {4.6, 2.8, -11.5}
        camera_target = {0, 1.82, -7.65}
    }
    if focus_trellis {
        camera_position = {4.8, 2.7, -11.2}
        camera_target = {0, 1.3, -6.95}
    }
    if focus_herbs {
        camera_position = {6.2, 2.25, 5.2}
        camera_target = {0, .32, -.35}
    }
    if focus_shrubs {
        camera_position = {6.0, 2.15, 5.0}
        camera_target = {1.0, .52, -1.5}
    }
    if focus_trees {
        camera_position = {10.4, 3.0, 8.4}
        camera_target = {7.0, 1.45, 4.9}
    }
    if focus_path {
        camera_position = {5.6, 2.05, 6.8}
        camera_target = {0, .22, -.2}
    }
    if focus_flowers {
        camera_position = {5.0, 2.15, 5.2}
        camera_target = {0, .3, 0}
    }
    editor.camera_pose = third_person.camera_look_at(camera_position, camera_target)
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

garden_lab_process_input :: proc(_: ^Editor) {
    changed := false
    if rl.IsKeyPressed(.R) {
        garden_lab_seed += 1
        changed = true
    }
    if rl.IsKeyPressed(.ONE) {
        garden_lab_style = .Courtyard
        changed = true
    }
    if rl.IsKeyPressed(.TWO) {
        garden_lab_style = .Kitchen
        changed = true
    }
    if rl.IsKeyPressed(.THREE) {
        garden_lab_style = .Wild
        changed = true
    }
    if changed do garden_lab_rebuild()
}

garden_lab_exit :: proc(_: ^Editor) {
    garden_lab_destroy_lsystem()
}

garden_draw_path_tile :: proc(x, z, width, depth: f32) {
    world_box({x, .035, z}, {width, .07, depth}, GARDEN_STONE)
}

garden_lsystem_point :: proc(base: third_person.Vec3, source: lsystem.Vec3, scale, yaw: f32) -> third_person.Vec3 {
    c, s := math.cos(yaw), math.sin(yaw)
    x, z := source[0] * scale, source[2] * scale
    return {base.x + x * c - z * s, base.y + source[1] * scale, base.z + x * s + z * c}
}

// The species crown is an implicit ellipsoidal hull. L-system leaves grow
// inside it, then move toward its zero surface and inherit the SDF gradient as
// their presentation normal. This preserves an authored species silhouette
// without replacing the generated internal branching topology.
garden_crown_parameters :: proc(plant: Garden_Plant, cache_kind: int) -> (center, radii: third_person.Vec3) {
    center = {plant.position.x, plant.position.y + .58 * plant.scale, plant.position.z}
    radii = {.82 * plant.scale, .58 * plant.scale, .82 * plant.scale}
    switch cache_kind {
    case 0:
        center.y = plant.position.y + 1.55 * plant.scale
        radii = {.56 * plant.scale, 1.85 * plant.scale, .56 * plant.scale}
    case 1:
        center.y = plant.position.y + 1.05 * plant.scale
        radii = {1.18 * plant.scale, 1.08 * plant.scale, 1.18 * plant.scale}
    case 2:
        center.y = plant.position.y + .38 * plant.scale
        radii = {.88 * plant.scale, .46 * plant.scale, .88 * plant.scale}
    case 3:
        center.y = plant.position.y + .32 * plant.scale
        radii = {.72 * plant.scale, .38 * plant.scale, .72 * plant.scale}
    case 4:
        center.y = plant.position.y + .36 * plant.scale
        radii = {.76 * plant.scale, .44 * plant.scale, .76 * plant.scale}
    case 5:
        center.y = plant.position.y + .24 * plant.scale
        radii = {.66 * plant.scale, .28 * plant.scale, .66 * plant.scale}
    case 6:
        center.y = plant.position.y + .36 * plant.scale
        radii = {.72 * plant.scale, .46 * plant.scale, .72 * plant.scale}
    case 7:
        center.y = plant.position.y + .42 * plant.scale
        radii = {.78 * plant.scale, .54 * plant.scale, .78 * plant.scale}
    case 8:
        center.y = plant.position.y + .38 * plant.scale
        radii = {.84 * plant.scale, .48 * plant.scale, .84 * plant.scale}
    case 9:
        center.y = plant.position.y + 2.15 * plant.scale
        radii = {1.8 * plant.scale, .68 * plant.scale, 1.8 * plant.scale}
    case 10:
        center.y = plant.position.y + 1.2 * plant.scale
        radii = {1.45 * plant.scale, 1.05 * plant.scale, 1.45 * plant.scale}
    case 11:
        center.y = plant.position.y + .45 * plant.scale
        radii = {.9 * plant.scale, .55 * plant.scale, .75 * plant.scale}
    case 12:
        center.y = plant.position.y + .32 * plant.scale
        radii = {.62 * plant.scale, .4 * plant.scale, .62 * plant.scale}
    }
    return
}

garden_crown_surface :: proc(
    plant: Garden_Plant,
    cache_kind: int,
    candidate: third_person.Vec3,
) -> (
    point, normal: third_person.Vec3,
) {
    center, radii := garden_crown_parameters(plant, cache_kind)
    delta := candidate - center
    q := third_person.Vec3 {
        delta.x / max(radii.x, f32(.001)),
        delta.y / max(radii.y, f32(.001)),
        delta.z / max(radii.z, f32(.001)),
    }
    q_length := f32(math.sqrt(f64(q.x * q.x + q.y * q.y + q.z * q.z)))
    if q_length < .001 {
        return {center.x, center.y + radii.y, center.z}, {0, 1, 0}
    }
    surface := center + delta / q_length
    point = surface
    gradient := third_person.Vec3 {
        (surface.x - center.x) / max(radii.x * radii.x, f32(.001)),
        (surface.y - center.y) / max(radii.y * radii.y, f32(.001)),
        (surface.z - center.z) / max(radii.z * radii.z, f32(.001)),
    }
    normal = linalg.normalize0(gradient)
    return
}

garden_crown_contains :: proc(plant: Garden_Plant, cache_kind: int, point: third_person.Vec3) -> bool {
    center, radii := garden_crown_parameters(plant, cache_kind)
    delta := point - center
    qx := delta.x / max(radii.x, f32(.001))
    qy := delta.y / max(radii.y, f32(.001))
    qz := delta.z / max(radii.z, f32(.001))
    return qx * qx + qy * qy + qz * qz <= 1
}

garden_crown_segment_intersection :: proc(
    plant: Garden_Plant,
    cache_kind: int,
    a, b: third_person.Vec3,
    entering: bool,
) -> (
    third_person.Vec3,
    bool,
) {
    center, radii := garden_crown_parameters(plant, cache_kind)
    qa := third_person.Vec3 {
        (a.x - center.x) / max(radii.x, f32(.001)),
        (a.y - center.y) / max(radii.y, f32(.001)),
        (a.z - center.z) / max(radii.z, f32(.001)),
    }
    qb := third_person.Vec3 {
        (b.x - center.x) / max(radii.x, f32(.001)),
        (b.y - center.y) / max(radii.y, f32(.001)),
        (b.z - center.z) / max(radii.z, f32(.001)),
    }
    direction := qb - qa
    coefficient_a := linalg.dot(direction, direction)
    coefficient_b := 2 * linalg.dot(qa, direction)
    coefficient_c := linalg.dot(qa, qa) - 1
    discriminant := coefficient_b * coefficient_b - 4 * coefficient_a * coefficient_c
    if coefficient_a < .000001 || discriminant < 0 do return {}, false
    root := f32(math.sqrt(f64(discriminant)))
    t0 := (-coefficient_b - root) / (2 * coefficient_a)
    t1 := (-coefficient_b + root) / (2 * coefficient_a)
    t := entering ? min(t0, t1) : max(t0, t1)
    if t < 0 || t > 1 {
        t = entering ? max(t0, t1) : min(t0, t1)
    }
    if t < 0 || t > 1 do return {}, false
    return a + (b - a) * t, true
}

garden_draw_leaf_plane :: proc(
    center, normal, horizontal, vertical: third_person.Vec3,
    width, height: f32,
    color: rl.Color,
) {
    right := horizontal * (width * .5)
    up := vertical * (height * .5)
    a, b, c, d := center - right - up, center + right - up, center + right + up, center - right + up
    world_triangle_foliage(a, b, c, color, color, color, normal, normal, normal)
    world_triangle_foliage(a, c, d, color, color, color, normal, normal, normal)
    world_triangle_foliage(c, b, a, color, color, color, -normal, -normal, -normal)
    world_triangle_foliage(d, c, a, color, color, color, -normal, -normal, -normal)
}

garden_draw_hull_leaf :: proc(center, normal: third_person.Vec3, width, height: f32, color: rl.Color) {
    tangent := linalg.normalize0(linalg.cross(normal, third_person.Vec3{0, 1, 0}))
    if linalg.dot(tangent, tangent) < .1 {
        tangent = linalg.normalize0(linalg.cross(normal, third_person.Vec3{1, 0, 0}))
    }
    bitangent := linalg.normalize0(linalg.cross(tangent, normal))
    garden_draw_leaf_plane(center, normal, tangent, bitangent, width, height, color)
    // An L-system bud represents a leaf cluster, not a single infinitely thin
    // billboard. Two smaller radial planes preserve the harvested hull normal
    // for lighting while keeping the cluster legible from side and oblique
    // views.
    garden_draw_leaf_plane(center, normal, tangent, normal, width * .72, height * .58, color)
    garden_draw_leaf_plane(center, normal, bitangent, normal, width * .58, height * .66, color)
}

garden_mesh_instance :: proc(
    x_axis, y_axis, z_axis, translation: third_person.Vec3,
    color: rl.Color,
    normal_override: third_person.Vec3 = {},
    override_normal: bool = false,
) -> World_Mesh_Instance {
    return {
        basis_x_translation_x = {x_axis.x, x_axis.y, x_axis.z, translation.x},
        basis_y_translation_y = {y_axis.x, y_axis.y, y_axis.z, translation.y},
        basis_z_translation_z = {z_axis.x, z_axis.y, z_axis.z, translation.z},
        color = world_color(color),
        normal_override = {normal_override.x, normal_override.y, normal_override.z, override_normal ? f32(1) : f32(0)},
    }
}

garden_instance_leaf_mesh_ensure :: proc(cache_kind, variant: int, mesh: ^leaf_mesh.Mesh) -> int {
    existing := garden_lab_leaf_instance_meshes[cache_kind][variant]
    if existing >= 0 do return existing
    if mesh == nil || mesh.index_count <= 0 do return -1
    vertices := make([dynamic]World_Vertex, len(mesh.vertices))
    defer delete(vertices)
    for vertex, index in mesh.vertices {
        vertices[index] = {
            position = vertex.position,
            color    = {1, 1, 1, 1},
            kind     = .Leaf,
            normal   = vertex.normal,
            material = {0, .82},
        }
    }
    indices := make([dynamic]u32, 0, mesh.index_count * 2)
    defer delete(indices)
    for first := 0; first + 2 < mesh.index_count; first += 3 {
        a := u32(mesh.indices[first])
        b := u32(mesh.indices[first + 1])
        c := u32(mesh.indices[first + 2])
        append(&indices, a, b, c, c, b, a)
    }
    result := world_instance_mesh_add(vertices[:], indices[:])
    garden_lab_leaf_instance_meshes[cache_kind][variant] = result
    return result
}

garden_instance_flower_mesh_ensure :: proc(stage_index: int) -> int {
    if garden_lab_flower_instance_meshes[stage_index] >= 0 do return garden_lab_flower_instance_meshes[stage_index]
    mesh := &garden_lab_flower_meshes[stage_index]
    if mesh.index_count <= 0 do return -1
    vertices := make([dynamic]World_Vertex, len(mesh.vertices))
    defer delete(vertices)
    for vertex, index in mesh.vertices {
        vertices[index] = {
            position = {vertex.position[0], vertex.position[2], vertex.position[1]},
            color    = {1, 1, 1, 1},
            kind     = .Petal,
            normal   = {vertex.normal[0], vertex.normal[2], vertex.normal[1]},
            material = {0, .88},
        }
    }
    indices := make([dynamic]u32, mesh.index_count)
    defer delete(indices)
    for index in 0 ..< mesh.index_count do indices[index] = u32(mesh.indices[index])
    garden_lab_flower_instance_meshes[stage_index] = world_instance_mesh_add(vertices[:], indices[:])
    return garden_lab_flower_instance_meshes[stage_index]
}

garden_instance_branch_mesh_ensure :: proc(cache_kind, variant: int, mesh: ^branch_mesh.Mesh) -> int {
    existing := garden_lab_branch_instance_meshes[cache_kind][variant]
    if existing >= 0 do return existing
    if mesh == nil || len(mesh.indices) <= 0 do return -1
    vertices := make([dynamic]World_Vertex, len(mesh.vertices))
    defer delete(vertices)
    for vertex, index in mesh.vertices {
        vertices[index] = {
            position = vertex.position,
            color    = {1, 1, 1, 1},
            kind     = .BRDF,
            normal   = vertex.normal,
            material = {0, .78},
        }
    }
    indices := make([dynamic]u32, len(mesh.indices))
    defer delete(indices)
    for index in 0 ..< len(mesh.indices) do indices[index] = u32(mesh.indices[index])
    result := world_instance_mesh_add(vertices[:], indices[:])
    garden_lab_branch_instance_meshes[cache_kind][variant] = result
    return result
}

garden_draw_generated_leaf :: proc(
    position, normal: third_person.Vec3,
    leaf_forward, leaf_up: lsystem.Vec3,
    yaw: f32,
    mesh: ^leaf_mesh.Mesh,
    scale: f32,
    color: rl.Color,
    cache_kind: int = -1,
    variant: int = -1,
) {
    if mesh == nil || mesh.index_count <= 0 do return
    outward := linalg.normalize0(normal)
    cosine, sine := math.cos(yaw), math.sin(yaw)
    forward := linalg.normalize0(
        third_person.Vec3 {
            leaf_forward[0] * cosine - leaf_forward[2] * sine,
            leaf_forward[1],
            leaf_forward[0] * sine + leaf_forward[2] * cosine,
        },
    )
    up := linalg.normalize0(
        third_person.Vec3 {
            leaf_up[0] * cosine - leaf_up[2] * sine,
            leaf_up[1],
            leaf_up[0] * sine + leaf_up[2] * cosine,
        },
    )
    right := linalg.normalize0(linalg.cross(forward, up))
    if linalg.dot(right, right) < .001 {
        reference := math.abs(forward.y) > .86 ? third_person.Vec3{1, 0, 0} : third_person.Vec3{0, 1, 0}
        right = linalg.normalize0(linalg.cross(reference, forward))
    }
    up = linalg.normalize0(linalg.cross(right, forward))
    if cache_kind >= 0 && variant >= 0 {
        mesh_index := garden_instance_leaf_mesh_ensure(cache_kind, variant, mesh)
        world_instance_mesh_emit(
            mesh_index,
            garden_mesh_instance(right * scale, forward * scale, up * scale, position, color, outward, true),
        )
        return
    }
    for first := 0; first + 2 < mesh.index_count; first += 3 {
        points: [3]third_person.Vec3
        for point_index in 0 ..< 3 {
            source := mesh.vertices[mesh.indices[first + point_index]].position
            points[point_index] =
                position + right * source[0] * scale + forward * source[1] * scale + up * source[2] * scale
        }
        world_triangle_foliage(points[0], points[1], points[2], color, color, color, outward, outward, outward, .Leaf)
        world_triangle_foliage(
            points[2],
            points[1],
            points[0],
            color,
            color,
            color,
            -outward,
            -outward,
            -outward,
            .Leaf,
        )
    }
}

garden_draw_attachment_flower :: proc(
    position: third_person.Vec3,
    scale: f32,
    color: rl.Color,
    stage: plants.Attachment_Stage = .Bloom,
) {
    stage_index := 3
    #partial switch stage {
    case .Bud:
        stage_index = 0
    case .Opening:
        stage_index = 1
    case .Half_Open:
        stage_index = 2
    case .Bloom, .None:
        stage_index = 3
    case .Fruit_Set, .Immature_Fruit, .Ripening_Fruit, .Ripe_Fruit:
    }
    mesh := &garden_lab_flower_meshes[stage_index]
    if mesh.index_count <= 0 do return
    mesh_index := garden_instance_flower_mesh_ensure(stage_index)
    axis_scale := third_person.Vec3{scale, 0, 0}
    world_instance_mesh_emit(
        mesh_index,
        garden_mesh_instance(axis_scale, {0, scale, 0}, {0, 0, scale}, position, color),
    )
}

garden_draw_lsystem_plant :: proc(plant: Garden_Plant, cache_kind: int) {
    location_hash := u32(abs(plant.position.x * 17 + plant.position.z * 29))
    variant := int(garden_hash(garden_lab_seed + location_hash) % 4)
    if !garden_lab_lsystem_ready[cache_kind][variant] do return
    generated := &garden_lab_lsystem_plants[cache_kind][variant].plant
    yaw := garden_random01(garden_lab_seed, variant, location_hash) * math.PI * 2
    wood := rl.Color{103, 70, 43, 255}
    scale := plant.scale * garden_species_display_scale(cache_kind)
    if garden_lab_branch_mesh_ready[cache_kind][variant] {
        mesh := &garden_lab_branch_meshes[cache_kind][variant]
        cosine, sine := math.cos(yaw), math.sin(yaw)
        vertical_scale := f32(1)
        mesh_index := garden_instance_branch_mesh_ensure(cache_kind, variant, mesh)
        world_instance_mesh_emit(
            mesh_index,
            garden_mesh_instance(
                {cosine * scale, 0, sine * scale},
                {0, scale * vertical_scale, 0},
                {-sine * scale, 0, cosine * scale},
                plant.position,
                wood,
            ),
        )
    }
    for leaf, leaf_index in generated.attachments {
        candidate := garden_lsystem_point(plant.position, leaf.position, scale, yaw)
        surface, hull_normal := garden_crown_surface(plant, cache_kind, candidate)
        position := garden_crown_contains(plant, cache_kind, candidate) ? candidate : surface
        if leaf.kind == .Fruit {
            fruit_color := rl.Color{171, 62, 52, 255}
            switch cache_kind {
            case 1:
                fruit_color = {226, 157, 43, 255}
            case 7:
                fruit_color = {54, 62, 84, 255}
            case 8:
                fruit_color = {180, 67, 55, 255}
            case 9:
                fruit_color = {104, 77, 49, 255}
            case 10:
                fruit_color = {68, 72, 49, 255}
            case 11:
                fruit_color = {194, 67, 72, 255}
            }
            fruit_scale := f32(.055)
            switch cache_kind {
            case 1:
                fruit_scale = .11
            case 7:
                fruit_scale = .032
            case 8:
                fruit_scale = .038
            case 9:
                fruit_scale = .06
            case 10:
                fruit_scale = .034
            case 11:
                fruit_scale = .105
            }
            stage_scale: f32 = 1
            #partial switch leaf.stage {
            case .Fruit_Set:
                stage_scale = .46
            case .Immature_Fruit:
                stage_scale = .68
            case .Ripening_Fruit:
                stage_scale = .86
            case .Ripe_Fruit, .None:
                stage_scale = 1
            case .Bud, .Opening, .Half_Open, .Bloom:
            }
            fruit_scale *= stage_scale
            fruit_color = plant_generator_stage_color(fruit_color, leaf.stage)
            world_ellipsoid_rotated(
                position,
                fruit_scale * plant.scale,
                fruit_scale * 1.22 * plant.scale,
                fruit_scale * plant.scale,
                yaw + f32(leaf_index) * .37,
                fruit_color,
            )
            continue
        }
        if leaf.kind == .Flower {
            flower_color := rl.Color{242, 224, 190, 255}
            switch cache_kind {
            case 2:
                flower_color = {226, 121, 157, 255}
            case 4:
                flower_color = {137, 103, 190, 255}
            case 5:
                flower_color = {206, 128, 173, 255}
            case 6:
                flower_color = {151, 111, 187, 255}
            case 12:
                flower_color = plant.color
            }
            if cache_kind == 12 {
                // A generated pelargonium flower marker represents an umbel,
                // not a lone bloom. Expand it into five compact florets while
                // keeping their center anchored to the L-system attachment.
                phase := f32(leaf_index) * .73 + yaw
                for floret in 0 ..< 5 {
                    angle := phase + f32(floret) * math.PI * 2 / 5
                    radius := floret == 0 ? f32(0) : .062 * plant.scale
                    floret_position :=
                        position +
                        third_person.Vec3 {
                                math.cos(angle) * radius,
                                (floret == 0 ? f32(.13) : f32(.105)) * plant.scale,
                                math.sin(angle) * radius,
                            }
                    garden_draw_attachment_flower(
                        floret_position,
                        .78 * plant.scale,
                        plant_generator_stage_color(flower_color, leaf.stage),
                        leaf.stage,
                    )
                }
                continue
            }
            flower_scale := plant.scale
            if cache_kind == 4 || cache_kind == 5 do flower_scale *= 1.6
            if cache_kind == 6 do flower_scale *= 1.3
            garden_draw_attachment_flower(
                position,
                flower_scale,
                plant_generator_stage_color(flower_color, leaf.stage),
                leaf.stage,
            )
            continue
        }
        if leaf.kind != .Leaf do continue
        color := leaf_index % 7 == 0 ? GARDEN_LEAF_LIGHT : plant.color
        if cache_kind == 0 {
            color = leaf_index % 5 == 0 ? rl.Color{67, 111, 76, 255} : rl.Color{42, 86, 58, 255}
        } else if cache_kind == 12 {
            color = leaf_index % 5 == 0 ? rl.Color{83, 126, 72, 255} : rl.Color{61, 106, 61, 255}
        }
        // An L token is a foliage attachment site. At garden overview
        // distance, render its botanical mesh as a small species cluster so
        // sub-pixel cypress scales and rosemary needles remain legible.
        cluster_scale := scale * clamp(1 - f32(leaf.depth) * .045, .72, 1)
        switch cache_kind {
        case 0:
            cluster_scale *= 18
        case 1:
            cluster_scale *= 3.2
        case 2:
            cluster_scale *= 1.8
        case 3:
            cluster_scale *= 9
        case 4:
            cluster_scale *= 8
        case 5:
            cluster_scale *= 20
        case 6:
            cluster_scale *= 1.8
        case 7:
            cluster_scale *= 3.2
        case 8:
            cluster_scale *= 3
        case 9:
            cluster_scale *= 2.6
        case 10:
            cluster_scale *= 2.8
        case 11:
            cluster_scale *= 1.35
        case 12:
            cluster_scale *= 1.15
        }
        garden_draw_generated_leaf(
            position,
            hull_normal,
            leaf.forward,
            leaf.up,
            yaw,
            &garden_lab_leaf_meshes[cache_kind][variant],
            cluster_scale,
            color,
            cache_kind,
            variant,
        )
    }
}

garden_draw_plant :: proc(plant: Garden_Plant) {
    switch plant.kind {
    case .Cypress:
        garden_draw_lsystem_plant(plant, 0)
    case .Citrus:
        garden_draw_lsystem_plant(plant, 1)
    case .Shrub:
        cache_kind := 2
        if garden_lab_style == .Wild {
            location_hash := u32(abs(plant.position.x * 43 + plant.position.z * 71))
            shrub_kinds := [3]int{2, 7, 8}
            cache_kind = shrub_kinds[int(garden_hash(garden_lab_seed + location_hash) % len(shrub_kinds))]
        }
        garden_draw_lsystem_plant(plant, cache_kind)
    case .Flower:
        if garden_lab_style == .Wild {
            // Meadow color comes from real flowering catalog plants. The
            // previous one-stem ellipsoid marker remained the last fake
            // vegetation form in the wild garden.
            meadow := plant
            location_hash := u32(abs(plant.position.x * 59 + plant.position.z * 83))
            cache_kind := 4 + int(garden_hash(garden_lab_seed + location_hash) % 3)
            meadow_colors := [3]rl.Color{{76, 105, 82, 255}, {68, 108, 62, 255}, {101, 124, 91, 255}}
            meadow_scales := [3]f32{.74, .66, .68}
            meadow.color = meadow_colors[cache_kind - 4]
            meadow.scale *= meadow_scales[cache_kind - 4]
            garden_draw_lsystem_plant(meadow, cache_kind)
        } else {
            garden_draw_lsystem_plant(plant, 12)
        }
    case .Herb:
        herb := plant
        bed := clamp(int((plant.position.z + 4.5) / 3 + .5), 0, 3)
        cache_kind := 3 + bed
        scales := [4]f32{.8, .88, .85, .86}
        colors := [4]rl.Color{{64, 105, 72, 255}, {76, 105, 82, 255}, {68, 108, 62, 255}, {101, 124, 91, 255}}
        herb.scale *= scales[bed]
        herb.color = colors[bed]
        garden_draw_lsystem_plant(herb, cache_kind)
    case .Stone_Pine:
        garden_draw_lsystem_plant(plant, 9)
    case .Olive_Tree:
        garden_draw_lsystem_plant(plant, 10)
    case .Succulent:
        garden_draw_lsystem_plant(plant, 11)
    case .Groundcover:
        garden_draw_lsystem_plant(plant, 5)
    }
}

garden_draw_potting_bench :: proc(center: third_person.Vec3) {
    timber := rl.Color{126, 82, 47, 255}
    world_box({center.x, center.y + .82, center.z}, {3.4, .16, .8}, timber)
    world_box({center.x, center.y + 1.72, center.z + .34}, {3.4, 1.65, .14}, {151, 101, 59, 255})
    for x in ([2]f32{-1.42, 1.42}) {
        world_box({center.x + x, center.y + .4, center.z}, {.14, .8, .64}, timber)
    }
    for x in ([3]f32{-1.0, 0, 1.0}) {
        world_vertical_prism({center.x + x, center.y + 1.04, center.z}, .34, .34, .35, math.PI / 8, GARDEN_TERRACOTTA)
        world_vertical_prism({center.x + x, center.y + 1.31, center.z}, .30, .25, .30, f32(x) * .7, GARDEN_LEAF_LIGHT)
    }
}

garden_draw_bench :: proc(center: third_person.Vec3) {
    timber := rl.Color{137, 91, 50, 255}
    for z in ([3]f32{-.28, 0, .28}) {
        world_box({center.x, center.y + .48, center.z + z}, {2.8, .13, .22}, timber)
    }
    for x in ([2]f32{-1.12, 1.12}) {
        world_box({center.x + x, center.y + .24, center.z}, {.13, .48, .55}, GARDEN_STONE_DARK)
    }
}

garden_draw_garden_arch :: proc(center: third_person.Vec3) {
    iron := rl.Color{58, 74, 62, 255}
    for x in ([2]f32{-1.55, 1.55}) {
        world_box({center.x + x, center.y + 1.75, center.z}, {.16, 3.5, .16}, iron)
    }
    world_box({center.x, center.y + 3.45, center.z}, {3.25, .16, .16}, iron)
}

garden_draw_arch_climber :: proc(center: third_person.Vec3) {
    if !garden_lab_arch_ready do return
    wood := rl.Color{102, 71, 48, 255}
    if garden_lab_arch_branch_ready {
        mesh := &garden_lab_arch_branch_mesh
        for first := 0; first + 2 < len(mesh.indices); first += 3 {
            points: [3]third_person.Vec3
            normals: [3]third_person.Vec3
            for point_index in 0 ..< 3 {
                vertex := mesh.vertices[mesh.indices[first + point_index]]
                points[point_index] =
                    center + third_person.Vec3{vertex.position[0], vertex.position[1], vertex.position[2]}
                normals[point_index] = linalg.normalize0(
                    third_person.Vec3{vertex.normal[0], vertex.normal[1], vertex.normal[2]},
                )
            }
            world_triangle_smooth_lit(
                points[0],
                points[1],
                points[2],
                normals[0],
                normals[1],
                normals[2],
                wood,
                wood,
                wood,
                .76,
            )
        }
    }
    for attachment in garden_lab_arch_plant.plant.attachments {
        position := center + third_person.Vec3{attachment.position[0], attachment.position[1], attachment.position[2]}
        if attachment.kind == .Flower {
            // Bougainvillea's large-scale color comes from three papery
            // modified leaves surrounding a very small true flower. Reuse the
            // generated ovate leaf mesh at this L-system attachment site so
            // the bracts share its support frame instead of substituting a
            // synthetic foliage block.
            normal := linalg.normalize0(third_person.Vec3{attachment.up[0], attachment.up[1], attachment.up[2]})
            bract_palette := [3]rl.Color{{220, 53, 133, 255}, {237, 72, 145, 255}, {196, 46, 122, 255}}
            for bract in 0 ..< 3 {
                garden_draw_generated_leaf(
                    position,
                    normal,
                    attachment.forward,
                    attachment.up,
                    f32(bract) * math.PI * 2 / 3 + f32(attachment.variant) * .17,
                    &garden_lab_arch_leaf_meshes[int(attachment.variant)],
                    2.05,
                    bract_palette[bract],
                )
            }
            garden_draw_attachment_flower(
                position,
                .58,
                plant_generator_stage_color({244, 229, 181, 255}, attachment.stage),
                attachment.stage,
            )
            continue
        }
        if attachment.kind != .Leaf do continue
        normal := linalg.normalize0(third_person.Vec3{attachment.up[0], attachment.up[1], attachment.up[2]})
        garden_draw_generated_leaf(
            position,
            normal,
            attachment.forward,
            attachment.up,
            0,
            &garden_lab_arch_leaf_meshes[int(attachment.variant)],
            3.0,
            GARDEN_LEAF,
        )
    }
}

garden_draw_kitchen_trellis :: proc(center: third_person.Vec3) {
    iron := rl.Color{72, 76, 61, 255}
    for x in ([2]f32{-2.9, 2.9}) {
        world_box({center.x + x, center.y + 1.32, center.z}, {.12, 2.64, .12}, iron)
    }
    for tier in 0 ..< 4 {
        height := .55 + f32(tier) * (2.65 * .96 - .55) / 3
        world_box({center.x, center.y + height, center.z}, {5.8, .055, .055}, iron)
    }
}

garden_draw_kitchen_vine :: proc(center: third_person.Vec3) {
    if !garden_lab_kitchen_vine_ready do return
    wood := rl.Color{99, 66, 46, 255}
    if garden_lab_kitchen_vine_branch_ready {
        mesh := &garden_lab_kitchen_vine_branch_mesh
        for first := 0; first + 2 < len(mesh.indices); first += 3 {
            points: [3]third_person.Vec3
            normals: [3]third_person.Vec3
            for point_index in 0 ..< 3 {
                vertex := mesh.vertices[mesh.indices[first + point_index]]
                points[point_index] =
                    center + third_person.Vec3{vertex.position[0], vertex.position[1], vertex.position[2]}
                normals[point_index] = linalg.normalize0(
                    third_person.Vec3{vertex.normal[0], vertex.normal[1], vertex.normal[2]},
                )
            }
            world_triangle_smooth_lit(
                points[0],
                points[1],
                points[2],
                normals[0],
                normals[1],
                normals[2],
                wood,
                wood,
                wood,
                .76,
            )
        }
    }
    for attachment, attachment_index in garden_lab_kitchen_vine.plant.attachments {
        position := center + third_person.Vec3{attachment.position[0], attachment.position[1], attachment.position[2]}
        if attachment.kind == .Fruit {
            grape := plant_generator_stage_color(rl.Color{87, 54, 112, 255}, attachment.stage)
            stage_scale: f32 = 1
            #partial switch attachment.stage {
            case .Fruit_Set:
                stage_scale = .46
            case .Immature_Fruit:
                stage_scale = .68
            case .Ripening_Fruit:
                stage_scale = .86
            case .Ripe_Fruit, .None:
                stage_scale = 1
            case .Bud, .Opening, .Half_Open, .Bloom:
            }
            for berry in 0 ..< 5 {
                angle := f32(berry) * 2.4 + f32(attachment_index) * .31
                offset := third_person.Vec3 {
                    math.cos(angle) * .055,
                    -.04 - f32(berry / 3) * .07,
                    math.sin(angle) * .035,
                }
                world_ellipsoid_rotated(
                    position + offset,
                    .045 * stage_scale,
                    .052 * stage_scale,
                    .045 * stage_scale,
                    angle,
                    grape,
                )
            }
            continue
        }
        if attachment.kind != .Leaf do continue
        normal := linalg.normalize0(third_person.Vec3{attachment.up[0], attachment.up[1], attachment.up[2]})
        garden_draw_generated_leaf(
            position,
            normal,
            attachment.forward,
            attachment.up,
            0,
            &garden_lab_kitchen_vine_leaf_meshes[int(attachment.variant)],
            2.5,
            rl.Color{66, 111, 55, 255},
        )
    }
}

garden_lab_append_optimized_mesh :: proc() {
    if len(garden_lab_mesh_vertices) == 0 || len(garden_lab_mesh_indices) == 0 do return
    vertex_base := u32(len(world_renderer.static_vertices))
    append(&world_renderer.static_vertices, ..garden_lab_mesh_vertices[:])
    reserve(&world_renderer.static_indices, len(world_renderer.static_indices) + len(garden_lab_mesh_indices))
    for index in garden_lab_mesh_indices {
        append(&world_renderer.static_indices, vertex_base + index)
    }
}

garden_lab_draw_optimized_plants :: proc() {
    if garden_lab_mesh_valid {
        garden_lab_append_optimized_mesh()
        return
    }
    first := len(world_renderer.vertices)
    for plant_index in 0 ..< garden_lab_plan.plant_count {
        garden_draw_plant(garden_lab_plan.plants[plant_index])
    }
    if garden_lab_style == .Courtyard do garden_draw_arch_climber({0, 0, -7.65})
    if garden_lab_style == .Kitchen do garden_draw_kitchen_vine({0, 0, -6.95})
    source := world_renderer.vertices[first:]
    garden_lab_mesh_source_vertices = len(source)
    if len(source) == 0 {
        garden_lab_mesh_valid = true
        return
    }
    resize(&garden_lab_mesh_vertices, len(source))
    resize(&garden_lab_mesh_indices, len(source))
    optimized_count := adriatic_optimize_unindexed_mesh(
        raw_data(garden_lab_mesh_vertices),
        raw_data(garden_lab_mesh_indices),
        raw_data(source),
        u32(len(source)),
        u32(size_of(World_Vertex)),
    )
    if optimized_count == 0 do return
    resize(&garden_lab_mesh_vertices, int(optimized_count))
    garden_lab_mesh_optimized_vertices = int(optimized_count)
    resize(&world_renderer.vertices, first)
    garden_lab_mesh_valid = true
    garden_lab_append_optimized_mesh()
}

world_garden_lab :: proc(_: ^Editor) {
    world_box({0, -.22, 0}, {21, .42, 16}, {113, 133, 82, 255})
    // Low dry-stone enclosure and a framed entrance.
    world_box({0, .32, -8}, {21.4, .64, .42}, GARDEN_STONE_DARK)
    world_box({-10.5, .32, 0}, {.42, .64, 16.4}, GARDEN_STONE_DARK)
    world_box({10.5, .32, 0}, {.42, .64, 16.4}, GARDEN_STONE_DARK)
    world_box({-6.2, .23, 8}, {8.2, .46, .42}, GARDEN_STONE_DARK)
    world_box({6.2, .23, 8}, {8.2, .46, .42}, GARDEN_STONE_DARK)

    switch garden_lab_style {
    case .Courtyard:
        for x in ([2]f32{-4.75, 4.75}) {
            for z in ([2]f32{-3.65, 3.65}) {
                world_box({x, .005, z}, {7.0, .06, 4.9}, GARDEN_SOIL)
                world_box({x, .055, z - 2.48}, {7.15, .11, .16}, GARDEN_TERRACOTTA)
                world_box({x, .055, z + 2.48}, {7.15, .11, .16}, GARDEN_TERRACOTTA)
            }
        }
        for x in -7 ..= 7 do garden_draw_path_tile(f32(x) * 1.35, 0, 1.22, 1.1)
        for z in -5 ..= 5 do garden_draw_path_tile(0, f32(z) * 1.35, 1.1, 1.22)
        world_fountain(&garden_lab_plan.fountain, garden_lab_plan.fountain_at)
        garden_draw_garden_arch({0, 0, -7.65})
        garden_draw_bench({-7.8, 0, 0})
        garden_draw_bench({7.8, 0, 0})
    case .Kitchen:
        for bed in 0 ..< 4 {
            z := -4.5 + f32(bed) * 3
            world_box({0, .13, z}, {14.6, .26, 1.55}, GARDEN_SOIL)
            world_box({0, .08, z - .86}, {15.1, .16, .14}, GARDEN_TERRACOTTA)
            world_box({0, .08, z + .86}, {15.1, .16, .14}, GARDEN_TERRACOTTA)
        }
        for z in -5 ..= 5 do garden_draw_path_tile(0, f32(z) * 1.35, 1.15, 1.22)
        garden_draw_potting_bench({-7.9, 0, -6.9})
        garden_draw_kitchen_trellis({0, 0, -6.95})
        world_fountain(&garden_lab_plan.fountain, garden_lab_plan.fountain_at)
    case .Wild:
        for z in -5 ..= 5 {
            fz := f32(z) * 1.35
            jitter := garden_random01(garden_lab_seed, z + 5, 149) - .5
            x := math.sin(fz * .34) * 1.5 + jitter * .24
            world_ellipsoid_rotated(
                {x, .015, fz},
                .78 + garden_random01(garden_lab_seed, z + 5, 151) * .16,
                .055,
                .51 + garden_random01(garden_lab_seed, z + 5, 157) * .12,
                -.18 + garden_random01(garden_lab_seed, z + 5, 163) * .36,
                z % 3 == 0 ? GARDEN_STONE_DARK : GARDEN_STONE,
            )
        }
        for grid_z in -15 ..= 15 {
            for grid_x in -20 ..= 20 {
                index := (grid_z + 15) * 41 + grid_x + 20
                x := f32(grid_x) * .48 + (garden_random01(garden_lab_seed, index, 101) - .5) * .35
                z := f32(grid_z) * .48 + (garden_random01(garden_lab_seed, index, 103) - .5) * .35
                path_x := math.sin(z * .34) * 1.5
                if abs(x - path_x) < 1.15 do continue
                // Modulate the hashed samples with a broad deterministic
                // field so grass gathers in ecological patches instead of
                // revealing the candidate grid. Keep the path edge shorter,
                // then let tufts rise into the open meadow.
                patch_density := clamp(
                    .52 + math.sin(x * .71 + z * .29) * .20 + math.sin(z * .91 - x * .24) * .15,
                    f32(.20),
                    f32(.86),
                )
                if garden_random01(garden_lab_seed, index, 107) > patch_density do continue
                path_distance := abs(x - path_x) - 1.15
                edge_height := clamp(.66 + path_distance * .16, f32(.66), f32(1.12))
                height := (.28 + garden_random01(garden_lab_seed, index, 109) * .34) * edge_height
                color := rl.Color {
                    u8(58 + garden_random01(garden_lab_seed, index, 113) * 24),
                    u8(105 + garden_random01(garden_lab_seed, index, 127) * 29),
                    u8(55 + garden_random01(garden_lab_seed, index, 131) * 18),
                    255,
                }
                world_grass_card({x, height * .5, z}, height * .58, height, index % 16, color)
            }
        }
        garden_draw_bench({-6.8, 0, -6.6})
    }
    garden_lab_draw_optimized_plants()
}

garden_lab_draw_ui :: proc(_: ^Editor, width, _: i32) {
    panel := rl.Rectangle{24, 24, 430, 142}
    rl.DrawRectangleRounded(panel, .16, 8, {19, 31, 27, 226})
    rl.DrawRectangleRoundedLinesEx(panel, .16, 8, 1, {111, 146, 111, 255})
    rl.DrawTextEx(rl.Font{}, "GARDEN GENERATOR", {38, 38}, 18, 1, {232, 224, 189, 255})
    summary := fmt.ctprintf(
        "%s  /  SEED %d  /  %d PLANTS",
        garden_style_name(garden_lab_style),
        garden_lab_seed,
        garden_lab_plan.plant_count,
    )
    rl.DrawTextEx(rl.Font{}, summary, {38, 65}, 13, 1, {174, 207, 160, 255})
    rl.DrawTextEx(rl.Font{}, "1 COURTYARD   2 KITCHEN   3 WILD   R REGENERATE", {38, 91}, 11, 1, {184, 191, 174, 255})
    species_summary: cstring
    switch garden_lab_style {
    case .Courtyard:
        species_summary = "CYPRESS / OLEANDER / PELARGONIUM / BOUGAINVILLEA"
    case .Kitchen:
        species_summary = "ROSEMARY / LAVENDER / THYME / SAGE / GRAPEVINE / LEMON"
    case .Wild:
        species_summary = "STONE PINE / OLIVE / MAQUIS / LAVENDER / THYME / SAGE"
    }
    rl.DrawTextEx(rl.Font{}, species_summary, {38, 110}, 10, 1, {174, 207, 160, 255})
    mesh_summary := fmt.ctprintf(
        "SDF-CLIPPED GROWTH + HULL NORMALS  /  MESHOPT %d -> %d",
        garden_lab_mesh_source_vertices,
        garden_lab_mesh_optimized_vertices,
    )
    rl.DrawTextEx(rl.Font{}, mesh_summary, {38, 128}, 10, 1, {139, 181, 173, 255})
    _ = width
}
