package plants

import lsystem "../lsystem"
import "core:math"
import "core:math/linalg"

lemon_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0xd1b54a32d192ed03
    if random == 0 do random = 1
    foliage_random := seed ~ 0x94d049bb133111eb
    if foliage_random == 0 do foliage_random = 1
    scale := .24 + maturity * .76

    trunk_segments := clamp(2 + int(maturity * 2), 2, 4)
    trunk_position: lsystem.Vec3
    trunk_radius := .13 * (.30 + maturity * .70)
    crown_origins: [5]lsystem.Vec3
    for index in 0 ..< trunk_segments {
        crown_origins[index] = trunk_position
        drift := lsystem.Vec3{olive_random_signed(&random) * .025, .34, olive_random_signed(&random) * .025} * scale
        next := trunk_position + drift
        end_radius := trunk_radius * .84
        append(
            &result.plant.segments,
            lsystem.Segment {
                start = trunk_position,
                end = next,
                radius_start = trunk_radius,
                radius_end = end_radius,
                depth = 0,
            },
        )
        trunk_position = next
        trunk_radius = end_radius
    }
    crown_origins[trunk_segments] = trunk_position

    // Opposed radial scaffold pairs prevent every recursive generation from
    // inheriting the same two turtle planes without leaving an incomplete
    // spiral biased toward one side. Staggered origins and slight angular
    // jitter keep the crown from becoming a mechanical wagon wheel.
    branch_generations := generations <= 1 ? 0 : generations == 2 ? 1 : 2
    scaffold_count := generations == 0 ? 4 : generations == 1 ? 6 : 8
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    for scaffold_index in 0 ..< scaffold_count {
        azimuth :=
            phase + f32(scaffold_index) * math.PI * 2 / f32(scaffold_count) + olive_random_signed(&random) * .055
        radial := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        origin_index := clamp(trunk_segments - 2 + scaffold_index % 3, 1, trunk_segments)
        origin := crown_origins[origin_index]
        rise := .48 + f32(scaffold_index % 3) * .08
        direction := linalg.normalize0(radial * (.72 + olive_random_signed(&random) * .08) + lsystem.Vec3{0, rise, 0})
        pair_index := scaffold_index % max(scaffold_count / 2, 1)
        length_random := seed ~ (u64(pair_index + 1) * 0x94d049bb133111eb)
        if length_random == 0 do length_random = 1
        scaffold_length := .30 * scale * (1 + olive_random_signed(&length_random) * .14)
        lemon_grow_branch(
            &result.plant,
            &random,
            &foliage_random,
            origin,
            direction,
            scaffold_length,
            trunk_radius * .78,
            1,
            branch_generations,
        )
    }
    // A restrained center leader closes the crown without dominating its
    // radial scaffolds.
    lemon_grow_branch(
        &result.plant,
        &random,
        &foliage_random,
        trunk_position,
        {olive_random_signed(&random) * .08, 1, olive_random_signed(&random) * .08},
        .25 * scale,
        trunk_radius * .72,
        1,
        min(branch_generations, 1),
    )
    return result
}

prickly_pear_emit_pad :: proc(plant: ^lsystem.Plant, position: lsystem.Vec3, normal_azimuth: f32, depth: int) {
    if plant == nil do return
    normal := lsystem.Vec3{math.cos(normal_azimuth), 0, math.sin(normal_azimuth)}
    append(&plant.leaves, lsystem.Leaf{position = position, forward = {0, 1, 0}, up = normal, depth = depth})
}

prickly_pear_skeleton :: proc(seed: u64, maturity: f32) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0x8cb92baa3f3d8dd7
    if random == 0 do random = 1
    scale := .34 + maturity * .66
    basal_count := maturity < .34 ? 1 : maturity < .64 ? 2 : 3
    child_count := maturity < .42 ? 0 : maturity < .74 ? 1 : 2
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2

    for basal_index in 0 ..< basal_count {
        centered := f32(basal_index) - f32(basal_count - 1) * .5
        base := lsystem.Vec3{centered * .20 * scale, 0, olive_random_signed(&random) * .055 * scale}
        base_normal := phase + f32(basal_index) * .86 + olive_random_signed(&random) * .18
        prickly_pear_emit_pad(&result.plant, base, base_normal, 0)
        // Keep one tiny structural segment inside each basal pad so the
        // generated plant retains valid woody topology without exposing the
        // brown connector sticks that made the cactus look like saplings.
        append(
            &result.plant.segments,
            lsystem.Segment{base, base + lsystem.Vec3{0, .10 * scale, 0}, .012 * scale, .008 * scale, 0},
        )

        for child_index in 0 ..< child_count {
            side := child_index == 0 ? f32(-1) : f32(1)
            outward := centered == 0 ? side : (centered < 0 ? f32(-1) : f32(1))
            child_base :=
                base +
                lsystem.Vec3 {
                        outward * (.055 + .015 * f32(child_index)) * scale,
                        (.255 + .025 * f32((basal_index + child_index) % 2)) * scale,
                        side * (.055 + olive_random_signed(&random) * .018) * scale,
                    }
            child_normal := base_normal + side * (.48 + olive_random_signed(&random) * .14)
            prickly_pear_emit_pad(&result.plant, child_base, child_normal, 1)

            if maturity < .82 do continue
            top_side := (basal_index + child_index) % 2 == 0 ? f32(-1) : f32(1)
            top_base :=
                child_base +
                lsystem.Vec3 {
                        top_side * (.040 + math.abs(olive_random_signed(&random)) * .018) * scale,
                        (.215 + olive_random_signed(&random) * .015) * scale,
                        -side * .022 * scale,
                    }
            prickly_pear_emit_pad(
                &result.plant,
                top_base,
                child_normal + top_side * (.36 + olive_random_signed(&random) * .10),
                2,
            )
        }
    }
    return result
}

succulent_emit_rosette :: proc(
    plant: ^lsystem.Plant,
    center: lsystem.Vec3,
    count: int,
    phase, rise, spread: f32,
    depth: int,
) {
    if plant == nil || count <= 0 do return
    for index in 0 ..< count {
        angle := phase + f32(index) * math.PI * 2 / f32(count)
        radial := lsystem.Vec3{math.cos(angle), 0, math.sin(angle)}
        forward := linalg.normalize0(radial * spread + lsystem.Vec3{0, rise, 0})
        tangent := lsystem.Vec3{-radial[2], 0, radial[0]}
        append(&plant.leaves, lsystem.Leaf{position = center, forward = forward, up = tangent, depth = depth})
    }
}

fleshy_plant_skeleton :: proc(
    species: Species,
    seed: u64,
    maturity: f32,
    detail: Detail_Level,
) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0xa0761d6478bd642f
    if random == 0 do random = 1
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    growth := .28 + maturity * .72

    // A tiny hidden segment preserves the generator's topology contract. The
    // persistent visible structure is carried entirely by fleshy attachments.
    append(&result.plant.segments, lsystem.Segment{{}, {0, .06 * growth, 0}, .009, .006, 0})
    if species == .Golden_Barrel {
        rib_count := detail == .Near ? 20 : detail == .Medium ? 14 : 9
        radius := (.13 + maturity * .16)
        for index in 0 ..< rib_count {
            angle := phase + f32(index) * math.PI * 2 / f32(rib_count)
            radial := lsystem.Vec3{math.cos(angle), 0, math.sin(angle)}
            position := radial * radius
            append(
                &result.plant.leaves,
                lsystem.Leaf{position = position, forward = {0, 1, 0}, up = radial, depth = 0},
            )
        }
        return result
    }

    outer_count := detail == .Near ? 18 : detail == .Medium ? 12 : 8
    inner_count := detail == .Near ? 11 : detail == .Medium ? 7 : 5
    if species == .Agave {
        succulent_emit_rosette(&result.plant, {}, outer_count, phase, .30, 1.0, 0)
        if maturity >= .42 {
            succulent_emit_rosette(&result.plant, {0, .025 * growth, 0}, inner_count, phase + .31, .70, .72, 1)
        }
    } else {
        // Aloe is a narrower, more upright clumping rosette. Mature plants
        // add two small deterministic offsets instead of becoming one agave.
        succulent_emit_rosette(&result.plant, {}, outer_count, phase, .62, .78, 0)
        succulent_emit_rosette(&result.plant, {0, .025 * growth, 0}, inner_count, phase + .37, .88, .48, 1)
        if maturity >= .72 && detail != .Far {
            offset_count := detail == .Near ? 7 : 5
            succulent_emit_rosette(
                &result.plant,
                {.18 * growth, 0, -.10 * growth},
                offset_count,
                phase + 1.1,
                .72,
                .66,
                2,
            )
            succulent_emit_rosette(
                &result.plant,
                {-.16 * growth, 0, .12 * growth},
                offset_count,
                phase - .8,
                .75,
                .62,
                2,
            )
        }
    }
    return result
}

succulent_catalog_skeleton :: proc(
    species: Species,
    seed: u64,
    maturity: f32,
    detail: Detail_Level,
) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    phase := f32((seed ~ 0xe7037ed1a0b428db) % 10_000) / 10_000 * math.PI * 2
    growth := .25 + maturity * .75
    if species == .Echeveria {
        append(&result.plant.segments, lsystem.Segment{{}, {0, .025, 0}, .008, .005, 0})
        succulent_emit_rosette(&result.plant, {}, detail == .Near ? 18 : detail == .Medium ? 12 : 8, phase, .32, 1, 0)
        succulent_emit_rosette(
            &result.plant,
            {0, .018, 0},
            detail == .Near ? 11 : detail == .Medium ? 7 : 5,
            phase + .29,
            .68,
            .70,
            1,
        )
        if maturity > .68 && detail != .Far do succulent_emit_rosette(&result.plant, {.21 * growth, 0, -.13 * growth}, 7, phase + .8, .48, .78, 2)
        return result
    }
    if species == .Aeonium {
        height := .24 + maturity * .62
        tip := lsystem.Vec3{0, height, 0}
        append(&result.plant.segments, lsystem.Segment{{}, tip, .045 * growth, .026 * growth, 0})
        rosette_count := detail == .Near ? 16 : detail == .Medium ? 11 : 7
        succulent_emit_rosette(&result.plant, tip, rosette_count, phase, .12, 1, 1)
        if maturity > .48 {
            branch_count := detail == .Far ? 2 : 4
            for branch in 0 ..< branch_count {
                angle := phase + f32(branch) * math.PI * 2 / f32(branch_count)
                radial := lsystem.Vec3{math.cos(angle), 0, math.sin(angle)}
                start := lsystem.Vec3{0, height * (.48 + f32(branch & 1) * .10), 0}
                end := start + radial * .23 * growth + lsystem.Vec3{0, .18 * growth, 0}
                append(&result.plant.segments, lsystem.Segment{start, end, .025 * growth, .014 * growth, 1})
                succulent_emit_rosette(&result.plant, end, max(rosette_count - 4, 5), angle + .2, .18, 1, 2)
            }
        }
        return result
    }
    if species == .Jade_Plant {
        stem_count := detail == .Far ? 3 : 5
        node_count := detail == .Near ? 4 : detail == .Medium ? 3 : 2
        for stem in 0 ..< stem_count {
            angle := phase + f32(stem) * math.PI * 2 / f32(stem_count)
            radial := lsystem.Vec3{math.cos(angle), 0, math.sin(angle)}
            position := radial * .035
            for node in 0 ..< node_count {
                next := position + radial * (.030 + f32(node) * .008) * growth + lsystem.Vec3{0, .13 * growth, 0}
                append(
                    &result.plant.segments,
                    lsystem.Segment {
                        position,
                        next,
                        (.024 - f32(node) * .003) * growth,
                        (.021 - f32(node) * .003) * growth,
                        node,
                    },
                )
                tangent := lsystem.Vec3{-radial[2], 0, radial[0]}
                axis := node & 1 == 0 ? tangent : radial
                append(
                    &result.plant.leaves,
                    lsystem.Leaf {
                        position = next,
                        forward = linalg.normalize0(axis + lsystem.Vec3{0, .28, 0}),
                        up = radial,
                        depth = node,
                    },
                    lsystem.Leaf {
                        position = next,
                        forward = linalg.normalize0(-axis + lsystem.Vec3{0, .28, 0}),
                        up = -radial,
                        depth = node,
                    },
                )
                position = next
            }
        }
        return result
    }
    if species == .Stonecrop {
        runner_count := detail == .Near ? 12 : detail == .Medium ? 8 : 5
        nodes := detail == .Near ? 5 : detail == .Medium ? 4 : 3
        for runner in 0 ..< runner_count {
            angle := phase + f32(runner) * math.PI * 2 / f32(runner_count)
            radial := lsystem.Vec3{math.cos(angle), 0, math.sin(angle)}
            position: lsystem.Vec3
            for node in 0 ..< nodes {
                next := position + radial * .075 * growth + lsystem.Vec3{0, .010 + f32(node) * .004, 0}
                append(&result.plant.segments, lsystem.Segment{position, next, .006, .004, 0})
                append(
                    &result.plant.leaves,
                    lsystem.Leaf {
                        position = next,
                        forward = {-radial[2], .18, radial[0]},
                        up = {0, 1, 0},
                        depth = node,
                    },
                )
                position = next
            }
        }
        return result
    }
    if species == .Blue_Chalk_Sticks {
        append(&result.plant.segments, lsystem.Segment{{}, {0, .03, 0}, .008, .005, 0})
        count := detail == .Near ? 22 : detail == .Medium ? 14 : 8
        for index in 0 ..< count {
            angle := phase + f32(index) * 2.399963
            radial := lsystem.Vec3{math.cos(angle), 0, math.sin(angle)}
            append(
                &result.plant.leaves,
                lsystem.Leaf {
                    position = radial * (.035 + f32(index % 4) * .022),
                    forward = linalg.normalize0(radial * .26 + lsystem.Vec3{0, 1, 0}),
                    up = {-radial[2], 0, radial[0]},
                    depth = index % 3,
                },
            )
        }
        return result
    }
    rib_count := detail == .Near ? 18 : detail == .Medium ? 12 : 8
    append(&result.plant.segments, lsystem.Segment{{}, {0, .12 * growth, 0}, .012, .008, 0})
    for rib in 0 ..< rib_count {
        angle := phase + f32(rib) * math.PI * 2 / f32(rib_count)
        radial := lsystem.Vec3{math.cos(angle), 0, math.sin(angle)}
        append(
            &result.plant.leaves,
            lsystem.Leaf{position = radial * .13 * growth, forward = {0, 1, 0}, up = radial, depth = 0},
        )
    }
    return result
}

almond_grow_branch :: proc(
    plant: ^lsystem.Plant,
    random, foliage_random: ^u64,
    start, initial_direction: lsystem.Vec3,
    length, radius: f32,
    depth, generations: int,
) {
    direction := linalg.normalize0(initial_direction)
    position := start
    current_radius := radius
    roll_phase := f32(lsystem.random_next(random) % 10_000) / 10_000 * math.PI * 2
    for segment_index in 0 ..< 3 {
        side := linalg.normalize0(linalg.cross(direction, lsystem.Vec3{0, 1, 0}))
        if linalg.dot(side, side) < .2 do side = {1, 0, 0}
        binormal := linalg.normalize0(linalg.cross(side, direction))
        direction = linalg.normalize0(
            direction +
            side * olive_random_signed(random) * .065 +
            binormal * olive_random_signed(random) * .045 +
            lsystem.Vec3{0, .035, 0},
        )
        segment_length := length * (.98 - f32(segment_index) * .10) * (1 + olive_random_signed(random) * .055)
        next := position + direction * segment_length
        end_radius := current_radius * .74
        append(&plant.segments, lsystem.Segment{position, next, current_radius, end_radius, depth})
        lemon_emit_leaf(plant, foliage_random, linalg.lerp(position, next, .42), direction, depth)
        lemon_emit_leaf(plant, foliage_random, next, direction, depth)
        position = next
        current_radius = end_radius

        if generations <= 0 do continue
        // Almond shoots ramify with alternating laterals along their length,
        // not citrus-like three-way whorls collected at the terminal bud.
        // Golden-angle spacing gives three sequential branch sites full
        // radial coverage without placing them in a terminal whorl.
        azimuth := roll_phase + f32(segment_index) * 2.399963 + olive_random_signed(random) * .16
        radial := side * math.cos(azimuth) + binormal * math.sin(azimuth)
        child_direction := linalg.normalize0(
            direction * (.56 + olive_random_signed(random) * .045) +
            radial * (.65 + olive_random_signed(random) * .055) +
            lsystem.Vec3{0, .045, 0},
        )
        almond_grow_branch(
            plant,
            random,
            foliage_random,
            position,
            child_direction,
            length * (.64 + olive_random_signed(random) * .035),
            current_radius * .61,
            depth + 1,
            generations - 1,
        )
    }
}

almond_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0x8cb92baa7f3d8dd7
    if random == 0 do random = 1
    foliage_random := seed ~ 0x9e3779b97f4a7c15
    if foliage_random == 0 do foliage_random = 1
    scale := .24 + maturity * .76

    // Keep a short, uninterrupted trunk below the vase. Primary scaffolds
    // emerge from two adjacent heights so their bases remain legible instead
    // of collapsing into one procedural hub.
    trunk_segments := clamp(2 + int(maturity * 1.4), 2, 3)
    trunk_position: lsystem.Vec3
    trunk_radius := .14 * (.30 + maturity * .70)
    crown_origins: [4]lsystem.Vec3
    for index in 0 ..< trunk_segments {
        crown_origins[index] = trunk_position
        next :=
            trunk_position +
            lsystem.Vec3{olive_random_signed(&random) * .020, .38, olive_random_signed(&random) * .020} * scale
        end_radius := trunk_radius * .82
        append(&result.plant.segments, lsystem.Segment{trunk_position, next, trunk_radius, end_radius, 0})
        trunk_position = next
        trunk_radius = end_radius
    }
    crown_origins[trunk_segments] = trunk_position

    scaffold_count := maturity < .42 ? 3 : 5
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    for scaffold_index in 0 ..< scaffold_count {
        // Even radial sectors guarantee coverage around the trunk. Restrained
        // jitter preserves seed identity without allowing one empty half.
        azimuth := phase + f32(scaffold_index) * math.PI * 2 / f32(scaffold_count) + olive_random_signed(&random) * .10
        radial := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        origin_index := clamp(trunk_segments - 1 + scaffold_index % 2, 1, trunk_segments)
        direction := linalg.normalize0(
            radial * (.66 + olive_random_signed(&random) * .045) +
            lsystem.Vec3{0, .78 + olive_random_signed(&random) * .045, 0},
        )
        almond_grow_branch(
            &result.plant,
            &random,
            &foliage_random,
            crown_origins[origin_index],
            direction,
            .37 * scale * (1 + olive_random_signed(&random) * .05),
            trunk_radius * (.70 + olive_random_signed(&random) * .035),
            1,
            clamp(generations, 0, 2),
        )
    }
    return result
}

almond_orchard_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    result := almond_skeleton(seed, maturity, generations)
    // The shared radial topology also underpins substantially heavier trees.
    // Almond keeps the same complete vase but carries a lighter orchard trunk
    // and fine flowering scaffold, particularly visible below its open crown.
    for &segment in result.plant.segments {
        radius_scale := segment.depth == 0 ? f32(.72) : f32(.84)
        segment.radius_start *= radius_scale
        segment.radius_end *= radius_scale
    }
    return result
}

broadleaf_tree_skeleton :: proc(
    species: Species,
    seed: u64,
    maturity: f32,
    generations: int,
) -> lsystem.Interpret_Result {
    // These full-sized trees need radial scaffold authority. The generic
    // turtle grammar advances a single leader between branch whorls, which
    // produced disconnected foliage shelves and hourglass silhouettes.
    result := almond_skeleton(seed ~ 0xd1b54a32d192ed03, maturity, generations)
    horizontal_scale, vertical_scale, radius_scale := f32(1), f32(1), f32(1)
    #partial switch species {
    case .Holm_Oak:
        // Holm oak retains a broad evergreen crown, but it is a rounded mass
        // rather than the flat umbrella reserved for stone pine. Give the
        // existing radial scaffold enough vertical authority to stack its
        // foliage pads into a deep crown across seed variants.
        horizontal_scale, vertical_scale, radius_scale = 1.22, 1.90, 1.30
    case .Oriental_Plane:
        horizontal_scale, vertical_scale, radius_scale = 1.48, 1.46, 1.18
    case .European_Hackberry:
        horizontal_scale, vertical_scale, radius_scale = 1.30, 1.28, 1.05
    case .White_Poplar:
        // White poplar forms a broad irregular oval crown. The previous
        // Lombardy-like transform compressed the radial scaffold so severely
        // that the mature tree read as a bare pole with a narrow foliage
        // sleeve. Retain an ascending habit without losing lateral authority.
        horizontal_scale, vertical_scale, radius_scale = 1.80, 1.40, 1.08
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
         .Wisteria,
         .Climbing_Rose,
         .Hydrangea_Bush,
         .Hydrangea_Tree,
         .Agapanthus,
         .Star_Jasmine,
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
    for &segment in result.plant.segments {
        segment.start[0] *= horizontal_scale
        segment.start[1] *= vertical_scale
        segment.start[2] *= horizontal_scale
        segment.end[0] *= horizontal_scale
        segment.end[1] *= vertical_scale
        segment.end[2] *= horizontal_scale
        segment.radius_start *= radius_scale
        segment.radius_end *= radius_scale
    }
    for &leaf in result.plant.leaves {
        leaf.position[0] *= horizontal_scale
        leaf.position[1] *= vertical_scale
        leaf.position[2] *= horizontal_scale
    }
    return result
}

fig_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    // Figs and almonds share an orchard-tree vase, but figs are lower,
    // broader, and heavier-limbed. Reusing the balanced radial topology keeps
    // the species from falling back to the old one-sided turtle fan while
    // this deterministic transform supplies the distinct fig proportions.
    result := almond_skeleton(seed ~ 0x6a09e667f3bcc909, maturity, generations)
    for &segment in result.plant.segments {
        segment.start[0] *= 1.20
        segment.start[1] *= 1.15
        segment.start[2] *= 1.20
        segment.end[0] *= 1.20
        segment.end[1] *= 1.15
        segment.end[2] *= 1.20
        segment.radius_start *= 1.08
        segment.radius_end *= 1.08
    }
    for &leaf in result.plant.leaves {
        leaf.position[0] *= 1.20
        leaf.position[1] *= 1.15
        leaf.position[2] *= 1.20
    }
    return result
}

carob_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    result := fig_skeleton(seed ~ 0xa54ff53a5f1d36f1, maturity, generations)
    // Carobs mature into substantial, deep-crowned evergreens. Preserve the
    // balanced vase topology but give its persistent limbs more height and
    // weight than the lower, lighter fig.
    for &segment in result.plant.segments {
        segment.start[1] *= 1.08
        segment.end[1] *= 1.08
        segment.radius_start *= 1.16
        segment.radius_end *= 1.16
    }
    for &leaf in result.plant.leaves do leaf.position[1] *= 1.08
    return result
}

pomegranate_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0xbb67ae8584caa73b
    if random == 0 do random = 1
    foliage_random := seed ~ 0x3c6ef372fe94f82b
    if foliage_random == 0 do foliage_random = 1
    scale := .24 + maturity * .76
    stem_count := maturity < .42 ? 3 : generations < 2 ? 4 : 5
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    // One lateral generation is enough to clothe five renewing canes. A
    // second recursive almond-style generation explodes into a low tangled
    // mound and hides both the vase and its fruit.
    branch_generations := clamp(generations - 1, 0, 1)
    for stem_index in 0 ..< stem_count {
        // Pomegranates characteristically renew from several basal canes.
        // Even sectors guarantee a complete vase, while different lift and
        // reach keep those canes from becoming a mechanical radial whorl.
        azimuth := phase + f32(stem_index) * math.PI * 2 / f32(stem_count) + olive_random_signed(&random) * .12
        radial := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        direction := linalg.normalize0(
            radial * (.30 + olive_random_signed(&random) * .045) +
            lsystem.Vec3{0, 1.06 + olive_random_signed(&random) * .07, 0},
        )
        almond_grow_branch(
            &result.plant,
            &random,
            &foliage_random,
            radial * .025,
            direction,
            .38 * scale * (1 + olive_random_signed(&random) * .07),
            .050 * (.30 + maturity * .70),
            0,
            branch_generations,
        )
    }
    return result
}

strawberry_tree_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    result := pomegranate_skeleton(seed ~ 0xcbbb9d5dc1059ed8, maturity, generations)
    // Strawberry trees commonly form several red-barked leaders beneath a
    // taller rounded crown. Stretch the complete radial vase while retaining
    // enough width and fine ramification to avoid a detached top tuft.
    for &segment in result.plant.segments {
        segment.start[0] *= 1.22
        segment.start[1] *= 1.62
        segment.start[2] *= 1.22
        segment.end[0] *= 1.22
        segment.end[1] *= 1.62
        segment.end[2] *= 1.22
        segment.radius_start *= 1.08
        segment.radius_end *= 1.08
    }
    for &leaf in result.plant.leaves {
        leaf.position[0] *= 1.22
        leaf.position[1] *= 1.62
        leaf.position[2] *= 1.22
    }
    return result
}
