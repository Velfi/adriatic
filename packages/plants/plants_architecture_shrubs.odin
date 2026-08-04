package plants

import plant_structure "../plant_structure"
import "core:math"
import "core:math/linalg"

oleander_architecture :: proc(seed: u64, maturity: f32, detail: Detail_Level) -> plant_structure.Interpret_Result {
    result: plant_structure.Interpret_Result
    architecture_result_begin(&result)
    random := seed ~ 0x6f6c65616e646572
    if random == 0 do random = 1
    growth := .18 + maturity * .82
    cane_count := detail == .Near ? 9 : detail == .Medium ? 7 : 5
    active_count := clamp(3 + int(maturity * f32(cane_count - 2)), 3, cane_count)
    phase := f32(plant_structure.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    for cane_index in 0 ..< active_count {
        azimuth := phase + f32(cane_index) * math.PI * 2 / f32(active_count) + olive_random_signed(&random) * .10
        radial := plant_structure.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        direction := linalg.normalize0(
            radial * (.28 + olive_random_signed(&random) * .04) + plant_structure.Vec3{0, 1, 0},
        )
        position := radial * (.025 + f32(cane_index % 3) * .009)
        radius := .020 * (.24 + maturity * .76)
        node_count := detail == .Far ? 4 : detail == .Medium ? 5 : 6
        for node_index in 0 ..< node_count {
            // Oleander renews as independent basal canes carrying opposite or
            // three-leaf whorls. It is not a recursively forked miniature tree.
            bend := radial * olive_random_signed(&random) * .035 + plant_structure.Vec3{0, .015, 0}
            direction = linalg.normalize0(direction + bend)
            length := (.105 + f32(node_index) * .006) * growth
            next := position + direction * length
            append(&result.plant.segments, plant_structure.Segment{position, next, radius, radius * .84, cane_index})
            leaf_count := node_index & 1 == 0 ? 3 : 2
            tangent := linalg.normalize0(linalg.cross(direction, radial))
            if linalg.dot(tangent, tangent) < .1 do tangent = {1, 0, 0}
            binormal := linalg.normalize0(linalg.cross(tangent, direction))
            for leaf_index in 0 ..< leaf_count {
                leaf_angle := f32(leaf_index) * math.PI * 2 / f32(leaf_count) + f32(node_index & 1) * math.PI * .5
                leaf_forward := linalg.normalize0(
                    tangent * math.cos(leaf_angle) + binormal * math.sin(leaf_angle) + direction * .16,
                )
                append(&result.plant.leaves, plant_structure.Leaf{next, leaf_forward, direction, cane_index})
            }
            // Established canes carry short flowering laterals in the upper
            // third without converting the whole plant into a dichotomous fan.
            if maturity > .48 && node_index >= node_count - 2 && detail != .Far {
                side := cane_index & 1 == 0 ? tangent : -tangent
                lateral_end := next + linalg.normalize0(direction * .35 + side * .75) * .11 * growth
                append(
                    &result.plant.segments,
                    plant_structure.Segment{next, lateral_end, radius * .42, radius * .20, cane_index + 1},
                )
                append(&result.plant.leaves, plant_structure.Leaf{lateral_end, side, direction, -9})
            }
            position = next
            radius *= .84
        }
    }
    return result
}

oleander_graph :: proc(seed: u64, maturity: f32, detail: Detail_Level) -> Plant_Graph {
    builder := graph_builder_make(.Oleander, seed, maturity)
    random := seed ~ 0x6f6c65616e646572
    if random == 0 do random = 1
    growth := .18 + maturity * .82
    cane_count := detail == .Near ? 9 : detail == .Medium ? 7 : 5
    node_count := detail == .Far ? 4 : detail == .Medium ? 5 : 6
    phase := f32(plant_structure.random_next(&random) % 10_000) / 10_000 * math.TAU
    for cane in 0 ..< cane_count {
        key := 1000 + u64(cane)
        emergence := f32(cane) * .075
        angle := phase + f32(cane) * math.TAU / f32(cane_count)
        radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
        direction := linalg.normalize0(radial * .28 + plant_structure.Vec3{0, 1, 0})
        axis, unit, visible := graph_builder_axis(&builder, -1, -1, .Renewal_Cane, .Orthotropic, key, emergence)
        if !visible do continue
        position := radial * (.025 + f32(cane % 3) * .009)
        radius := .020 * (.24 + maturity * .76)
        parent := -1
        for node in 0 ..< node_count {
            next := position + direction * (.105 + f32(node) * .006) * growth
            parent = graph_builder_internode(
                &builder,
                axis,
                unit,
                parent,
                position,
                next,
                radius,
                radius * .84,
                key * 256 + u64(node),
                emergence + f32(node) * .025,
            )
            tangent := linalg.normalize0(linalg.cross(direction, radial))
            if linalg.dot(tangent, tangent) < .1 do tangent = {1, 0, 0}
            binormal := linalg.normalize0(linalg.cross(tangent, direction))
            whorl_count := node & 1 == 0 ? 3 : 2
            for leaf in 0 ..< whorl_count {
                leaf_angle := f32(leaf) * math.TAU / f32(whorl_count) + f32(node & 1) * math.PI * .5
                leaf_forward := linalg.normalize0(
                    tangent * math.cos(leaf_angle) + binormal * math.sin(leaf_angle) + direction * .16,
                )
                _ = graph_builder_organ(
                    &builder,
                    parent,
                    1,
                    .Leaf,
                    leaf_forward,
                    direction,
                    key * 4096 + u64(node) * 8 + u64(leaf),
                    emergence + f32(node) * .025,
                    u8(leaf),
                )
            }
            if detail != .Far && node >= node_count - 2 {
                side := cane & 1 == 0 ? tangent : -tangent
                flower_axis := graph_builder_shoot(
                    &builder,
                    parent,
                    linalg.normalize0(direction * .35 + side * .75),
                    .11 * growth,
                    radius * .42,
                    .Flowering_Shoot,
                    .Arching,
                    key * 64 + u64(node),
                    max(f32(.48), emergence + f32(node) * .025),
                )
                if flower_axis >= 0 {
                    flower_node := len(builder.graph.internodes) - 1
                    organ := graph_builder_reproductive(&builder, flower_node, 1, .Flower, key * 8192 + u64(node), .48)
                    if organ >= 0 do builder.graph.organs[organ].render_depth = -9
                }
            }
            position = next
            radius *= .84
        }
    }
    return graph_builder_take(&builder)
}

myrtle_architecture :: proc(seed: u64, maturity: f32, generations: int) -> plant_structure.Interpret_Result {
    // Myrtle and pomegranate are both renewing multi-cane shrubs, but Myrtle
    // is finer, narrower, and more continuously leafy. Reusing the balanced
    // radial cane topology removes the generic grammar's hollow V-shaped fan
    // while this transform keeps the two species visibly distinct.
    result := pomegranate_architecture(seed ~ 0xa54ff53a5f1d36f1, maturity, generations)
    for &segment in result.plant.segments {
        segment.start[0] *= 1.05
        segment.start[1] *= .98
        segment.start[2] *= 1.05
        segment.end[0] *= 1.05
        segment.end[1] *= .98
        segment.end[2] *= 1.05
        segment.radius_start *= .55
        segment.radius_end *= .55
    }
    for &leaf in result.plant.leaves {
        leaf.position[0] *= 1.05
        leaf.position[1] *= .98
        leaf.position[2] *= 1.05
    }
    return result
}

mastic_architecture :: proc(seed: u64, maturity: f32, generations: int) -> plant_structure.Interpret_Result {
    result: plant_structure.Interpret_Result
    architecture_result_begin(&result)
    random := seed ~ 0x3c6ef372fe94f82b
    if random == 0 do random = 1
    foliage_random := seed ~ 0xa54ff53a5f1d36f1
    if foliage_random == 0 do foliage_random = 1
    scale := .24 + maturity * .76
    stem_count := maturity < .42 ? 4 : 6
    phase := f32(plant_structure.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    branch_generations := clamp(generations - 1, 0, 2)
    for stem_index in 0 ..< stem_count {
        azimuth := phase + f32(stem_index) * math.PI * 2 / f32(stem_count) + olive_random_signed(&random) * .10
        radial := plant_structure.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        // Mastic stays broader and lower than Myrtle, but all six basal canes
        // still occupy distinct radial sectors rather than one planar fan.
        direction := linalg.normalize0(
            radial * (.43 + olive_random_signed(&random) * .04) +
            plant_structure.Vec3{0, .98 + olive_random_signed(&random) * .06, 0},
        )
        almond_grow_branch(
            &result.plant,
            &random,
            &foliage_random,
            radial * .025,
            direction,
            .34 * scale * (1 + olive_random_signed(&random) * .06),
            .026 * (.30 + maturity * .70),
            0,
            branch_generations,
        )
    }
    return result
}

agapanthus_architecture :: proc(seed: u64, maturity: f32, detail: Detail_Level) -> plant_structure.Interpret_Result {
    result: plant_structure.Interpret_Result
    architecture_result_begin(&result)
    random := seed ~ 0x510e527fade682d1
    if random == 0 do random = 1
    phase := f32(plant_structure.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    growth := .25 + maturity * .75

    // One hidden basal link preserves the non-empty topology contract. The
    // persistent vegetative mass is the explicit strap-leaf rosette below.
    append(&result.plant.segments, plant_structure.Segment{{}, {0, .025, 0}, .006, .004, 0})
    leaf_count := detail == .Near ? 22 : detail == .Medium ? 14 : 9
    for leaf_index in 0 ..< leaf_count {
        angle := phase + f32(leaf_index) * 2.399963 + olive_random_signed(&random) * .10
        radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
        ring := leaf_index % 3
        rise := f32(.32 + .12 * f32(ring))
        forward := linalg.normalize0(radial + plant_structure.Vec3{0, rise, 0})
        tangent := plant_structure.Vec3{-radial[2], 0, radial[0]}
        append(
            &result.plant.leaves,
            plant_structure.Leaf{position = radial * (.012 * f32(ring)), forward = forward, up = tangent, depth = 0},
        )
    }

    if maturity > .42 && detail != .Far {
        scape_count := detail == .Near ? 3 : 2
        for scape_index in 0 ..< scape_count {
            angle := phase + f32(scape_index) * math.PI * 2 / f32(scape_count) + olive_random_signed(&random) * .12
            radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
            start := radial * (.035 + f32(scape_index % 2) * .018)
            height := (.60 + f32(scape_index) * .055 + olive_random_signed(&random) * .020) * growth
            end := start + radial * .120 + plant_structure.Vec3{0, height, 0}
            append(&result.plant.segments, plant_structure.Segment{start, end, .009, .0045, 0})
            append(
                &result.plant.leaves,
                plant_structure.Leaf {
                    position = end,
                    forward = linalg.normalize0(radial + plant_structure.Vec3{0, .15, 0}),
                    up = {-radial[2], 0, radial[0]},
                    depth = -5,
                },
            )
        }
    }
    return result
}

agapanthus_graph :: proc(seed: u64, maturity: f32, detail: Detail_Level) -> Plant_Graph {
    builder := graph_builder_make(.Agapanthus, seed, maturity)
    random := seed ~ 0x510e527fade682d1
    if random == 0 do random = 1
    phase := f32(plant_structure.random_next(&random) % 10_000) / 10_000 * math.TAU
    growth := .25 + maturity * .75
    axis, unit, _ := graph_builder_axis(&builder, -1, -1, .Leader, .Orthotropic, 1)
    core := graph_builder_internode(&builder, axis, unit, -1, {}, {0, .025, 0}, .006, .004, 256)
    leaf_count := detail == .Near ? 22 : detail == .Medium ? 14 : 9
    for leaf in 0 ..< leaf_count {
        angle := phase + f32(leaf) * 2.399963
        radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
        ring := leaf % 3
        forward := linalg.normalize0(radial + plant_structure.Vec3{0, .32 + .12 * f32(ring), 0})
        _ = graph_builder_organ(
            &builder,
            core,
            0,
            .Rosette_Leaf,
            forward,
            {-radial[2], 0, radial[0]},
            1000 + u64(leaf),
            f32(leaf) * .006,
            u8(leaf & 3),
        )
    }
    if detail != .Far {
        scape_count := detail == .Near ? 3 : 2
        for scape in 0 ..< scape_count {
            key := 2000 + u64(scape)
            angle := phase + f32(scape) * math.TAU / f32(scape_count)
            radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
            start := radial * (.035 + f32(scape % 2) * .018)
            height := (.60 + f32(scape) * .055) * growth
            scape_axis, scape_unit, visible := graph_builder_axis(
                &builder,
                -1,
                -1,
                .Inflorescence,
                .Orthotropic,
                key,
                .42 + f32(scape) * .035,
            )
            if !visible do continue
            node := graph_builder_internode(
                &builder,
                scape_axis,
                scape_unit,
                -1,
                start,
                start + radial * .120 + plant_structure.Vec3{0, height, 0},
                .009,
                .0045,
                key * 256,
                .42 + f32(scape) * .035,
            )
            organ := graph_builder_reproductive(&builder, node, 1, .Flower, key * 256 + 1, .42)
            if organ >= 0 do builder.graph.organs[organ].render_depth = -5
        }
    }
    return graph_builder_take(&builder)
}

native_herb_graph :: proc(species: Species, seed: u64, maturity: f32, detail: Detail_Level) -> Plant_Graph {
    builder := graph_builder_make(species, seed, maturity)
    phase := f32((seed ~ 0x484552425f475241) % 10_000) / 10_000 * math.TAU
    growth := .22 + maturity * .78
    stem_count, node_count := 12, 3
    height, spread, radius := f32(.42), f32(.38), f32(.004)
    role := Axis_Role.Renewal_Cane
    flower_depth, flower_modulus := 0, 0
    flower_emergence := f32(2)
    #partial switch species {
    case .Rosemary:
        stem_count = detail == .Near ? 18 : detail == .Medium ? 12 : 8
        node_count, height, spread, radius = 4, .55, .36, .0032
    case .Lavender:
        stem_count = detail == .Near ? 24 : detail == .Medium ? 16 : 10
        node_count, height, spread, radius = 3, .34, .46, .0018
        flower_depth, flower_modulus, flower_emergence = -7, 3, .35
    case .Thyme:
        stem_count = detail == .Near ? 18 : detail == .Medium ? 12 : 8
        node_count, height, spread, radius = 3, .13, .82, .0014
        role = .Runner
        flower_depth, flower_modulus, flower_emergence = -8, 4, .32
    case .Sage:
        stem_count = detail == .Near ? 10 : detail == .Medium ? 8 : 6
        node_count, height, spread, radius = 4, .46, .40, .0048
        flower_depth, flower_modulus, flower_emergence = -6, 2, .35
    case:
        return graph_builder_take(&builder)
    }
    for stem in 0 ..< stem_count {
        key := 1000 + u64(stem)
        emergence := f32(stem) * .68 / f32(max(stem_count - 1, 1))
        angle := phase + f32(stem) * 2.399963
        radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
        tangent := plant_structure.Vec3{-radial[2], 0, radial[0]}
        orientation := role == .Runner ? Axis_Orientation.Prostrate : .Arching
        axis, unit, visible := graph_builder_axis(&builder, -1, -1, role, orientation, key, emergence)
        if !visible do continue
        position := radial * .018 * growth
        parent := -1
        current_radius := radius * (.30 + maturity * .70)
        for node in 0 ..< node_count {
            progress := f32(node + 1) / f32(node_count)
            next :=
                radial * spread * growth * progress +
                plant_structure.Vec3{0, height * growth * progress, 0} +
                tangent * math.sin(progress * math.PI) * .025 * growth
            parent = graph_builder_internode(
                &builder,
                axis,
                unit,
                parent,
                position,
                next,
                current_radius,
                current_radius * .72,
                key * 256 + u64(node),
                emergence + f32(node) * .055,
            )
            if parent >= 0 {
                leaf_tilt := species == .Rosemary || species == .Lavender ? f32(.30) : f32(.16)
                _ = graph_builder_organ(
                    &builder,
                    parent,
                    .72,
                    .Leaf,
                    linalg.normalize0(tangent + plant_structure.Vec3{0, leaf_tilt, 0}),
                    radial,
                    key * 1024 + u64(node) * 2,
                    emergence + f32(node) * .055,
                )
                _ = graph_builder_organ(
                    &builder,
                    parent,
                    .72,
                    .Leaf,
                    linalg.normalize0(-tangent + plant_structure.Vec3{0, leaf_tilt, 0}),
                    -radial,
                    key * 1024 + u64(node) * 2 + 1,
                    emergence + f32(node) * .055,
                    1,
                )
            }
            position = next
            current_radius *= .72
        }
        if flower_modulus > 0 && stem % flower_modulus != 0 && parent >= 0 && detail != .Far {
            organ := graph_builder_reproductive(
                &builder,
                parent,
                1,
                .Flower,
                key * 4096,
                max(flower_emergence, emergence),
            )
            if organ >= 0 do builder.graph.organs[organ].render_depth = flower_depth
        }
    }
    return graph_builder_take(&builder)
}

sage_architecture :: proc(seed: u64, maturity: f32, generations: int) -> plant_structure.Interpret_Result {
    result: plant_structure.Interpret_Result
    architecture_result_begin(&result)
    random := seed ~ 0x9b05688c2b3e6c1f
    if random == 0 do random = 1
    foliage_random := seed ~ 0x1f83d9abfb41bd6b
    if foliage_random == 0 do foliage_random = 1
    scale := .24 + maturity * .76
    stem_count := maturity < .42 ? 5 : 8
    phase := f32(plant_structure.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    branch_generations := clamp(generations - 1, 0, 1)
    for stem_index in 0 ..< stem_count {
        azimuth := phase + f32(stem_index) * math.PI * 2 / f32(stem_count) + olive_random_signed(&random) * .12
        radial := plant_structure.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        direction := linalg.normalize0(
            radial * (.38 + olive_random_signed(&random) * .04) +
            plant_structure.Vec3{0, .98 + olive_random_signed(&random) * .06, 0},
        )
        before := len(result.plant.segments)
        almond_grow_branch(
            &result.plant,
            &random,
            &foliage_random,
            radial * .018,
            direction,
            .23 * scale * (1 + olive_random_signed(&random) * .06),
            .008 * (.30 + maturity * .70),
            0,
            branch_generations,
        )
        if len(result.plant.segments) > before {
            terminal: plant_structure.Vec3
            for segment in result.plant.segments[before:] {
                if segment.depth == 0 && segment.end[1] > terminal[1] do terminal = segment.end
            }
            append(
                &result.plant.leaves,
                plant_structure.Leaf {
                    position = terminal,
                    forward = direction,
                    up = {-radial[2], 0, radial[0]},
                    depth = -6,
                },
            )
        }
    }
    return result
}

lavender_architecture :: proc(seed: u64, maturity: f32, generations: int) -> plant_structure.Interpret_Result {
    result: plant_structure.Interpret_Result
    architecture_result_begin(&result)
    random := seed ~ 0xa54ff53a5f1d36f1
    if random == 0 do random = 1
    scale := .24 + maturity * .76
    stem_count := maturity < .42 ? 14 : 30
    phase := f32(plant_structure.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    for stem_index in 0 ..< stem_count {
        azimuth := phase + f32(stem_index) * math.PI * 2 / f32(stem_count) + olive_random_signed(&random) * .11
        radial := plant_structure.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        ring := f32(stem_index % 6) / 5
        height_variation := 1 + olive_random_signed(&random) * .14
        start := radial * (.018 + ring * .030) * scale
        // A rounded leafy mound supports a smaller set of visibly emergent
        // flower stalks. Lower outer shoots prevent the old straight-sided
        // cylinder while irregular inner shoots soften the crown center.
        mound_height := (.105 - ring * .030) * scale * height_variation
        shoulder := start + radial * ((.050 + ring * .030) * scale) + plant_structure.Vec3{0, mound_height, 0}
        flowering := stem_index % 3 != 0
        flower_height := flowering ? (.105 + (1 - ring) * .030) * scale * height_variation : .025 * scale
        terminal := shoulder + radial * (.012 * scale) + plant_structure.Vec3{0, flower_height, 0}
        radius := .0018 * (.30 + maturity * .70)
        append(&result.plant.segments, plant_structure.Segment{start, shoulder, radius, radius * .72, 0})
        append(&result.plant.segments, plant_structure.Segment{shoulder, terminal, radius * .72, radius * .38, 1})
        if flowering {
            append(
                &result.plant.leaves,
                plant_structure.Leaf {
                    position = terminal,
                    forward = linalg.normalize0(radial * .18 + plant_structure.Vec3{0, 1, 0}),
                    up = {-radial[2], 0, radial[0]},
                    depth = -7,
                },
            )
        }
    }
    return result
}

thyme_architecture :: proc(seed: u64, maturity: f32, detail: Detail_Level) -> plant_structure.Interpret_Result {
    result: plant_structure.Interpret_Result
    architecture_result_begin(&result)
    random := seed ~ 0x5be0cd19137e2179
    if random == 0 do random = 1
    scale := .24 + maturity * .76
    cluster_count := detail == .Near ? 6 : detail == .Medium ? 4 : 3
    shoots_per_cluster := detail == .Near ? 4 : detail == .Medium ? 3 : 2
    leaf_fractions := [2]f32{.30, .72}
    phase := f32(plant_structure.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    for cluster_index in 0 ..< cluster_count {
        cluster_angle := phase + f32(cluster_index) * 2.399963 + olive_random_signed(&random) * .35
        cluster_distance := cluster_index == 0 ? f32(0) : (.030 + f32(cluster_index % 3) * .024) * scale
        center := plant_structure.Vec3 {
            math.cos(cluster_angle) * cluster_distance,
            (.014 + f32(cluster_index % 2) * .004) * scale,
            math.sin(cluster_angle) * cluster_distance,
        }
        // Close the crown over each rooting point. Thyme keeps foliage on
        // its short inner nodes; exposing every shared origin makes even an
        // irregular colony resolve back into a set of bare starbursts.
        for center_leaf_index in 0 ..< 6 {
            center_leaf_angle := cluster_angle + f32(center_leaf_index) * math.PI / 3
            center_forward := plant_structure.Vec3{math.cos(center_leaf_angle), .16, math.sin(center_leaf_angle)}
            append(
                &result.plant.leaves,
                plant_structure.Leaf {
                    position = center + plant_structure.Vec3{0, .006 * scale, 0},
                    forward = linalg.normalize0(center_forward),
                    up = {0, 1, 0},
                    depth = 0,
                },
            )
        }
        for shoot_index in 0 ..< shoots_per_cluster {
            angle :=
                cluster_angle +
                f32(shoot_index) * math.PI * 2 / f32(shoots_per_cluster) +
                olive_random_signed(&random) * .42
            position := center
            radius := .0009 * (.30 + maturity * .70)
            direction: plant_structure.Vec3
            for segment_index in 0 ..< 3 {
                angle += olive_random_signed(&random) * .32
                direction = linalg.normalize0(
                    plant_structure.Vec3{math.cos(angle), .08 + olive_random_signed(&random) * .035, math.sin(angle)},
                )
                next := position + direction * (.036 * scale * (1 + olive_random_signed(&random) * .16))
                append(
                    &result.plant.segments,
                    plant_structure.Segment{position, next, radius, radius * .72, segment_index},
                )
                tangent := plant_structure.Vec3{-direction[2], .08, direction[0]}
                for fraction in leaf_fractions {
                    leaf_position := linalg.lerp(position, next, fraction) + plant_structure.Vec3{0, .005 * scale, 0}
                    append(
                        &result.plant.leaves,
                        plant_structure.Leaf {
                            position = leaf_position,
                            forward = linalg.normalize0(tangent),
                            up = {0, 1, 0},
                            depth = segment_index,
                        },
                        plant_structure.Leaf {
                            position = leaf_position,
                            forward = linalg.normalize0(-tangent),
                            up = {0, 1, 0},
                            depth = segment_index,
                        },
                    )
                }
                position = next
                radius *= .72
            }
        }
        if detail != .Far {
            flower_shoot_count := maturity > .62 ? 2 : 1
            for flower_shoot_index in 0 ..< flower_shoot_count {
                flower_angle := cluster_angle + f32(flower_shoot_index) * 2.2 + olive_random_signed(&random) * .25
                flower_radial := plant_structure.Vec3{math.cos(flower_angle), 0, math.sin(flower_angle)}
                flower_base := center + flower_radial * (.018 * scale)
                flower_tip := flower_base + flower_radial * (.010 * scale) + plant_structure.Vec3{0, .050 * scale, 0}
                append(&result.plant.segments, plant_structure.Segment{flower_base, flower_tip, .0008, .00035, 2})
                append(
                    &result.plant.leaves,
                    plant_structure.Leaf {
                        position = flower_tip,
                        forward = linalg.normalize0(flower_radial * .12 + plant_structure.Vec3{0, 1, 0}),
                        up = {-flower_radial[2], 0, flower_radial[0]},
                        depth = -8,
                    },
                )
            }
        }
    }
    return result
}

bay_laurel_architecture :: proc(seed: u64, maturity: f32, generations: int) -> plant_structure.Interpret_Result {
    result := pomegranate_architecture(seed ~ 0x510e527fade682d1, maturity, generations)
    // Laurel forms a dense upright oval rather than pomegranate's open,
    // fruit-bearing vase. Compress the same complete radial coverage and
    // extend its cane height, preserving seed variation in three dimensions.
    for &segment in result.plant.segments {
        segment.start[0] *= .95
        segment.start[1] *= 1.08
        segment.start[2] *= .95
        segment.end[0] *= .95
        segment.end[1] *= 1.08
        segment.end[2] *= .95
        segment.radius_start *= .92
        segment.radius_end *= .92
    }
    for &leaf in result.plant.leaves {
        leaf.position[0] *= .95
        leaf.position[1] *= 1.08
        leaf.position[2] *= .95
    }
    return result
}

rosemary_clothe_scaffold :: proc(plant: ^plant_structure.Plant) {
    if plant == nil || len(plant.leaves) == 0 do return
    original_segment_count := len(plant.segments)
    fractions := [2]f32{.38, .70}
    replacement_count := 0
    for segment in plant.segments[:original_segment_count] {
        if segment.depth <= 1 do replacement_count += len(fractions)
    }
    replacement_ordinal := 0
    for segment in plant.segments[:original_segment_count] {
        // Only clothe the persistent basal leaders. Fine recursive shoots
        // already carry grammar-authored needles; duplicating those would
        // spend the attachment budget without improving the silhouette.
        if segment.depth > 1 do continue
        direction := linalg.normalize0(segment.end - segment.start)
        forward, up := olive_leaf_frame(direction)
        for fraction in fractions {
            // Spread replacement sites through the grammar output. Replacing
            // one contiguous tail block strips the terminal crown bare.
            replacement_index := (replacement_ordinal + 1) * len(plant.leaves) / (replacement_count + 1)
            plant.leaves[replacement_index] = {
                position = linalg.lerp(segment.start, segment.end, fraction),
                forward  = forward,
                up       = up,
                depth    = segment.depth,
            }
            replacement_ordinal += 1
        }
    }
}

myrtle_clothe_scaffold :: proc(plant: ^plant_structure.Plant) {
    if plant == nil || len(plant.segments) == 0 do return
    // Opposite pairs need several longitudinal stations to form Myrtle's
    // dense evergreen sprays. Add stations along the cane instead of
    // restoring the old three-way palmate cluster at a single node.
    fractions := [2]f32{.18, .70}
    for segment in plant.segments {
        direction := linalg.normalize0(segment.end - segment.start)
        forward, up := olive_leaf_frame(direction)
        for fraction in fractions {
            append(
                &plant.leaves,
                plant_structure.Leaf {
                    position = linalg.lerp(segment.start, segment.end, fraction),
                    forward = forward,
                    up = up,
                    depth = segment.depth,
                },
            )
        }
    }
}

lavender_clothe_scaffold :: proc(plant: ^plant_structure.Plant) {
    if plant == nil || len(plant.segments) == 0 do return
    // Lavender hides its fine basal framework beneath many close opposite
    // leaf pairs. Four stations per short link create that soft grey mound
    // while the separately authored terminal markers remain flower-only.
    for segment, segment_index in plant.segments {
        basal_fractions := [4]f32{.12, .38, .64, .86}
        stalk_fractions := [1]f32{.10}
        station_count := segment.depth == 0 ? len(basal_fractions) : len(stalk_fractions)
        for fraction_index in 0 ..< station_count {
            fraction := segment.depth == 0 ? basal_fractions[fraction_index] : stalk_fractions[fraction_index]
            position := linalg.lerp(segment.start, segment.end, fraction)
            azimuth := f32(segment_index) * 2.399963 + f32(fraction_index) * math.PI * .43
            outward := plant_structure.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
            forward := linalg.normalize0(outward * .96 + plant_structure.Vec3{0, .18, 0})
            up := plant_structure.Vec3{-outward[2], 0, outward[0]}
            append(
                &plant.leaves,
                plant_structure.Leaf{position = position, forward = forward, up = up, depth = segment.depth},
            )
        }
    }
}

stone_pine_clothe_scaffold :: proc(plant: ^plant_structure.Plant, detail: Detail_Level, maturity: f32) {
    if plant == nil || len(plant.segments) == 0 do return
    for segment in plant.segments {
        if segment.depth <= 0 do continue
        direction := linalg.normalize0(segment.end - segment.start)
        forward, up := olive_leaf_frame(direction)
        // The old uniform six-station run painted thin needles along every
        // scaffold and exposed the radial construction. Italian stone pines
        // retain visible inner arms but concentrate foliage into overlapping
        // pads on their terminal forks.
        primary_stations := [3]f32{.58, .78, .94}
        terminal_stations := [7]f32{.16, .30, .44, .58, .71, .84, .95}
        station_count := segment.depth == 1 ? len(primary_stations) : len(terminal_stations)
        for station_index in 0 ..< station_count {
            station := segment.depth == 1 ? primary_stations[station_index] : terminal_stations[station_index]
            row_count := 1
            right := linalg.normalize0(linalg.cross(forward, up))
            for row_index in 0 ..< row_count {
                row_side :=
                    row_index == 0 ? f32(0) : row_index % 2 == 1 ? f32((row_index + 1) / 2) : -f32(row_index / 2)
                row_position :=
                    linalg.lerp(segment.start, segment.end, station) +
                    right * row_side * .045 +
                    up * math.abs(row_side) * .016
                append(
                    &plant.leaves,
                    plant_structure.Leaf{position = row_position, forward = forward, up = up, depth = segment.depth},
                )
            }
        }
    }

    canopy_progress := clamp((maturity - .38) / .62, f32(0), f32(1))
    if canopy_progress <= 0 do return

    // Branch-bound fascicles preserve the pine texture and fringed edge, but
    // cannot form a continuous umbrella without exposing their radial layout.
    // Fill the shallow crown with overlapping foliage pads distributed over a
    // deterministic disc. These are still ordinary leaf attachments, so wind,
    // detail scaling, color variation, and bounds remain on the normal path.
    crown_minimum := plant_structure.Vec3{1e9, 1e9, 1e9}
    crown_maximum := plant_structure.Vec3{-1e9, -1e9, -1e9}
    has_crown := false
    for segment in plant.segments {
        if segment.depth <= 0 do continue
        crown_minimum = linalg.min(crown_minimum, linalg.min(segment.start, segment.end))
        crown_maximum = linalg.max(crown_maximum, linalg.max(segment.start, segment.end))
        has_crown = true
    }
    if !has_crown do return

    crown_center := (crown_minimum + crown_maximum) * .5
    crown_radius := max(crown_maximum[0] - crown_minimum[0], crown_maximum[2] - crown_minimum[2]) * .48
    mature_ring_count := detail == .Near ? 6 : detail == .Medium ? 4 : 3
    ring_count := clamp(2 + int(canopy_progress * f32(mature_ring_count - 2) + .5), 2, mature_ring_count)
    layer_count := canopy_progress > .68 ? (detail == .Near ? 3 : detail == .Medium ? 2 : 1) : 1
    for ring_index in 0 ..< ring_count {
        radial_fraction := ring_index == 0 ? f32(0) : f32(ring_index) / f32(ring_count - 1)
        station_count := ring_index == 0 ? 1 : 10 + ring_index * 6
        ring_phase := f32(ring_index) * .73
        for station_index in 0 ..< station_count {
            azimuth := ring_phase + f32(station_index) * math.PI * 2 / f32(station_count)
            radial := plant_structure.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
            tangent := plant_structure.Vec3{-radial[2], 0, radial[0]}
            perimeter_noise := .94 + math.sin(azimuth * 3 + f32(ring_index) * 1.7) * .06
            radial_jitter :=
                ring_index == 0 ? f32(0) : math.sin(azimuth * 5.17 + f32(ring_index) * 2.31) * .32 / f32(ring_count)
            height_jitter := math.sin(azimuth * 4.43 + f32(ring_index) * 1.19) * crown_radius * .045
            padded_radius := clamp(radial_fraction + radial_jitter, f32(0), f32(1))
            position :=
                crown_center +
                radial * crown_radius * padded_radius * perimeter_noise +
                plant_structure.Vec3{0, crown_radius * (.22 - padded_radius * padded_radius * .14) + height_jitter, 0}
            for layer_index in 0 ..< layer_count {
                layer_offset := f32(layer_index) - f32(layer_count - 1) * .5
                orientation_jitter := math.sin(azimuth * 2.71 + f32(layer_index) * 1.83)
                forward := linalg.normalize0(
                    radial * (.48 + orientation_jitter * .12) +
                    tangent * (layer_offset * .42 + orientation_jitter * .24) +
                    plant_structure.Vec3{0, .30 + math.abs(layer_offset) * .09, 0},
                )
                _, up := olive_leaf_frame(forward)
                append(
                    &plant.leaves,
                    plant_structure.Leaf {
                        position = position +
                        tangent * layer_offset * crown_radius * .050 +
                        plant_structure.Vec3{0, layer_offset * crown_radius * .090, 0},
                        forward = forward,
                        up = up,
                        depth = 3,
                    },
                )
            }
        }
    }
}

stone_pine_architecture :: proc(seed: u64, maturity: f32, iterations: int) -> plant_structure.Interpret_Result {
    result: plant_structure.Interpret_Result
    architecture_result_begin(&result)
    random := seed ~ 0xd6e8feb86659fd93
    if random == 0 do random = 1
    scale := .22 + maturity * .78
    trunk_segments := clamp(3 + int(maturity * 3.2), 3, 6)
    trunk_step := .43 * scale
    trunk_radius := .18 * (.28 + maturity * .72)
    position := plant_structure.Vec3{}
    trunk_points: [7]plant_structure.Vec3
    trunk_points[0] = position
    for index in 0 ..< trunk_segments {
        // A long, slightly wandering clear bole is the visual anchor of a
        // mature stone pine; the umbrella begins only in its upper quarter.
        next :=
            position +
            plant_structure.Vec3 {
                    olive_random_signed(&random) * .022 * scale,
                    trunk_step,
                    olive_random_signed(&random) * .022 * scale,
                }
        end_radius := trunk_radius * (.91 - f32(index) * .018)
        append(&result.plant.segments, plant_structure.Segment{position, next, trunk_radius, end_radius, 0})
        position = next
        trunk_points[index + 1] = position
        trunk_radius = end_radius
    }

    leader_count := iterations >= 3 ? 10 : iterations == 2 ? 7 : 6
    phase := f32(plant_structure.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    umbrella_progress := clamp((maturity - .35) / .65, f32(0), f32(1))
    juvenile_leader_length := .82 * (1 - umbrella_progress) * (1 - umbrella_progress) * scale
    if juvenile_leader_length > .01 {
        leader_start := trunk_points[trunk_segments]
        leader_end := leader_start + plant_structure.Vec3{0, juvenile_leader_length, 0}
        append(
            &result.plant.segments,
            plant_structure.Segment{leader_start, leader_end, trunk_radius * .72, trunk_radius * .18, 1},
        )
    }
    young_branch_lift := .42 + (.18 - .42) * umbrella_progress
    crown_branch_y := trunk_points[trunk_segments][1] + young_branch_lift * scale
    for leader_index in 0 ..< leader_count {
        azimuth := phase + f32(leader_index) * math.PI * 2 / f32(leader_count) + olive_random_signed(&random) * .12
        radial := plant_structure.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        origin_index := max(trunk_segments - leader_index % 2, 1)
        origin := trunk_points[origin_index]
        reach := (.78 + olive_random_signed(&random) * .10) * scale
        elbow :=
            origin +
            radial * reach * .46 +
            plant_structure.Vec3{0, crown_branch_y - origin[1] + olive_random_signed(&random) * .035 * scale, 0}
        tip_rise := .24 + (.045 - .24) * umbrella_progress
        tip :=
            elbow +
            radial * reach * .54 +
            plant_structure.Vec3{0, (tip_rise + olive_random_signed(&random) * .025) * scale, 0}
        branch_radius := max(trunk_radius * (.46 + olive_random_signed(&random) * .04), f32(.012))
        append(
            &result.plant.segments,
            plant_structure.Segment{origin, elbow, branch_radius, branch_radius * .72, 1},
            plant_structure.Segment{elbow, tip, branch_radius * .72, branch_radius * .42, 1},
        )

        // Layer terminal fans along the outer arm instead of emitting every
        // spray from its tip. A tip-only fan still reads as one pom-pom at the
        // end of each radial spoke, however many needles it carries. These
        // three overlapping tiers fill the crown from its dark interior to its
        // scalloped perimeter while retaining a shallow, flat-bottomed dome.
        tangent := plant_structure.Vec3{-radial[2], 0, radial[0]}
        fan_stations := [3]f32{.18, .54, .88}
        for fan_station, tier_index in fan_stations {
            fan_root := linalg.lerp(elbow, tip, fan_station)
            tier_progress := f32(tier_index) / f32(len(fan_stations) - 1)
            for side in -1 ..= 1 {
                side_fraction := f32(side)
                fork_direction := linalg.normalize0(
                    radial * (.50 + tier_progress * .22) +
                    tangent * side_fraction * (.62 - tier_progress * .08) +
                    plant_structure.Vec3 {
                            0,
                            .36 + (.13 - .36) * umbrella_progress + olive_random_signed(&random) * .04,
                            0,
                        },
                )
                fork_length := reach * (.18 + tier_progress * .10 + math.abs(side_fraction) * .020)
                fork_end := fan_root + fork_direction * fork_length
                fork_radius := branch_radius * (.38 - tier_progress * .08)
                append(
                    &result.plant.segments,
                    plant_structure.Segment{fan_root, fork_end, fork_radius, branch_radius * .10, 2},
                )
            }
        }

        // A shorter inward spray closes the hole between the trunk and the
        // outer fans without clothing the clear bole or turning the crown into
        // a solid ball.
        bridge_direction := linalg.normalize0(
            radial * .22 +
            tangent * olive_random_signed(&random) * .28 +
            plant_structure.Vec3{0, .42 + (.22 - .42) * umbrella_progress + olive_random_signed(&random) * .05, 0},
        )
        bridge_end := elbow + bridge_direction * reach * .30
        append(
            &result.plant.segments,
            plant_structure.Segment{elbow, bridge_end, branch_radius * .50, branch_radius * .13, 2},
        )
    }
    return result
}

olive_emit_spray :: proc(
    plant: ^plant_structure.Plant,
    random: ^u64,
    position, direction: plant_structure.Vec3,
    depth: int,
) {
    stem := linalg.normalize0(direction)
    side := linalg.normalize0(linalg.cross(stem, plant_structure.Vec3{0, 1, 0}))
    if linalg.dot(side, side) < .2 do side = {1, 0, 0}
    stem_up := linalg.normalize0(linalg.cross(side, stem))
    // Olive blades spread mostly sideways from a shoot. Choose either side
    // before applying the shallow roll; constraining every sample around the
    // positive side axis put every source leaf on the same side of its shoot
    // (most visible when Far detail collapses each opposite pair to one card).
    // A full 360-degree roll still creates implausible curtains of vertically
    // hanging leaves, so retain the narrow botanical fan on both sides.
    side_sign := plant_structure.random_next(random) & 1 == 0 ? f32(-1) : f32(1)
    phase := olive_random_signed(random) * .45
    forward := linalg.normalize0(side * side_sign * math.cos(phase) + stem_up * math.sin(phase))
    up := linalg.normalize0(linalg.cross(forward, stem))
    append(&plant.leaves, plant_structure.Leaf{position = position, forward = forward, up = up, depth = depth})
}

olive_grow_branch :: proc(
    plant: ^plant_structure.Plant,
    random, foliage_random: ^u64,
    start, initial_direction: plant_structure.Vec3,
    length, radius: f32,
    depth, generations: int,
) {
    if plant == nil || generations < 0 do return
    direction := linalg.normalize0(initial_direction)
    position := start
    current_radius := radius
    segment_count := generations > 0 ? 3 : 2
    for segment_index in 0 ..< segment_count {
        // Olive wood keeps the momentum of its parent while wandering and
        // turning upward. Small independent yaw and roll changes avoid the
        // radial spokes and planar fans produced by fixed turtle rotations.
        side := linalg.normalize0(linalg.cross(direction, plant_structure.Vec3{0, 1, 0}))
        if linalg.dot(side, side) < .2 do side = {1, 0, 0}
        binormal := linalg.normalize0(linalg.cross(side, direction))
        direction = linalg.normalize0(
            direction +
            side * olive_random_signed(random) * .24 +
            binormal * olive_random_signed(random) * .16 +
            plant_structure.Vec3{0, .05, 0},
        )
        // Compact, crooked runs let neighboring twigs overlap into an olive
        // crown instead of exposing long straight scaffold rays.
        segment_length := length * (.80 - f32(segment_index) * .075) * (1 + olive_random_signed(random) * .12)
        next := position + direction * segment_length
        end_radius := current_radius * (.80 - f32(segment_index) * .035)
        append(
            &plant.segments,
            plant_structure.Segment {
                start = position,
                end = next,
                radius_start = current_radius,
                radius_end = end_radius,
                depth = depth,
            },
        )
        position = next
        current_radius = end_radius
        if generations <= 2 || segment_index == segment_count - 1 {
            // Do not repeat identical stations on every recursive shoot. In
            // projection those shared .42/.73 fractions line up into obvious
            // horizontal foliage shelves. Small deterministic offsets retain
            // the olive's paired rhythm while breaking the procedural bands.
            inner_fraction := .40 + olive_random_signed(foliage_random) * .09
            outer_fraction := .72 + olive_random_signed(foliage_random) * .08
            olive_emit_spray(
                plant,
                foliage_random,
                position - direction * segment_length * (1 - inner_fraction),
                direction,
                depth,
            )
            olive_emit_spray(
                plant,
                foliage_random,
                position - direction * segment_length * (1 - outer_fraction),
                direction,
                depth,
            )
            if generations <= 1 {
                // Fill terminal shoots with one staggered station. Three
                // widely separated pairs exposed the branch as a ladder;
                // this keeps the opposite-pair habit while closing the crown.
                fill_fraction := .56 + olive_random_signed(foliage_random) * .06
                olive_emit_spray(
                    plant,
                    foliage_random,
                    position - direction * segment_length * (1 - fill_fraction),
                    direction,
                    depth,
                )
            }
            olive_emit_spray(plant, foliage_random, position, direction, depth)
        } else if generations >= 3 && segment_index == 1 {
            // One sparse interior pair visually carries foliage from the old
            // scaffold into the terminal crown. Leaving the whole primary
            // run bare produces long isolated arms with detached tip clumps.
            bridge_fraction := .68 + olive_random_signed(foliage_random) * .10
            bridge_position := position - direction * segment_length * (1 - bridge_fraction)
            olive_emit_spray(plant, foliage_random, bridge_position, direction, depth)
            olive_emit_spray(
                plant,
                foliage_random,
                bridge_position - direction * segment_length * .20,
                direction,
                depth,
            )
        }
    }
    if generations == 0 do return

    child_count := generations >= 2 ? 3 : 2
    parent_direction := direction
    parent_side := linalg.normalize0(linalg.cross(parent_direction, plant_structure.Vec3{0, 1, 0}))
    if linalg.dot(parent_side, parent_side) < .2 do parent_side = {1, 0, 0}
    parent_up := linalg.normalize0(linalg.cross(parent_side, parent_direction))
    phase := olive_random_signed(random) * math.PI
    for child_index in 0 ..< child_count {
        azimuth := phase + f32(child_index) * math.PI * 2 / f32(child_count)
        radial := parent_side * math.cos(azimuth) + parent_up * math.sin(azimuth)
        child_direction := linalg.normalize0(
            parent_direction * (.50 + olive_random_signed(random) * .08) +
            radial * (.66 + olive_random_signed(random) * .10) +
            plant_structure.Vec3{0, .12 + olive_random_signed(random) * .08, 0},
        )
        olive_grow_branch(
            plant,
            random,
            foliage_random,
            position,
            child_direction,
            length * (.62 + olive_random_signed(random) * .05),
            current_radius * .66,
            depth + 1,
            generations - 1,
        )
    }
}
