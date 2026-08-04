package plants

import plant_structure "../plant_structure"
import "core:math"
import "core:math/linalg"

Native_Woody_Form :: enum u8 {
    Orchard,
    Renewal,
    Broadleaf,
    Umbrella_Conifer,
}

Native_Woody_Config :: struct {
    form:           Native_Woody_Form,
    trunk_height:   f32,
    crown_rise:     f32,
    crown_spread:   f32,
    trunk_radius:   f32,
    scaffold_count: int,
    leaf_pairs:     int,
    upright:        f32,
}

native_woody_config :: proc(species: Species, detail: Detail_Level) -> Native_Woody_Config {
    near, medium, far := 8, 6, 4
    count := detail == .Near ? near : detail == .Medium ? medium : far
    #partial switch species {
    case .Olive:
        return {.Orchard, .72, .72, .82, .105, count, 2, .42}
    case .Fig:
        return {.Orchard, .58, .68, .92, .095, count, 2, .34}
    case .Lemon:
        return {.Orchard, .64, .72, .66, .082, count, 2, .54}
    case .Almond:
        return {.Orchard, .78, .86, .78, .082, count, 2, .62}
    case .Carob:
        return {.Broadleaf, .74, .72, .96, .115, count + 1, 2, .40}
    case .Strawberry_Tree:
        return {.Orchard, .54, .78, .70, .080, count, 2, .56}
    case .Pomegranate:
        return {.Renewal, .08, .92, .54, .034, count, 2, .74}
    case .Bay_Laurel:
        return {.Renewal, .12, 1.05, .46, .040, count - 1, 2, .82}
    case .Myrtle:
        return {.Renewal, .05, .70, .48, .024, count, 2, .78}
    case .Mastic:
        return {.Renewal, .04, .60, .68, .028, count, 2, .56}
    case .Holm_Oak:
        return {.Broadleaf, .78, .82, 1.00, .130, count + 2, 2, .38}
    case .Oriental_Plane:
        return {.Broadleaf, 1.05, 1.05, .94, .135, count + 1, 2, .60}
    case .European_Hackberry:
        return {.Broadleaf, .94, .92, .78, .108, count, 2, .68}
    case .White_Poplar:
        return {.Broadleaf, 1.16, 1.10, .58, .105, count - 1, 2, .86}
    case .Stone_Pine:
        return {.Umbrella_Conifer, 1.28, .54, 1.08, .130, count + 2, 3, .34}
    case:
        return {}
    }
}

native_woody_leaf_pair :: proc(
    builder: ^Graph_Builder,
    internode: int,
    radial, tangent: plant_structure.Vec3,
    stable_key: u64,
    emergence: f32,
    depth: int,
) {
    normal := linalg.normalize0(plant_structure.Vec3{0, .72, 0} + radial * .42)
    first := graph_builder_organ(builder, internode, .72, .Leaf, tangent, normal, stable_key * 2, emergence)
    second := graph_builder_organ(builder, internode, .72, .Leaf, -tangent, normal, stable_key * 2 + 1, emergence, 1)
    if first >= 0 do builder.graph.organs[first].render_depth = depth
    if second >= 0 do builder.graph.organs[second].render_depth = depth
}

native_renewal_woody_graph :: proc(
    builder_pointer: ^Graph_Builder,
    config: Native_Woody_Config,
    species: Species,
    maturity: f32,
    detail: Detail_Level,
    phase: f32,
) {
    builder := builder_pointer^
    growth := .20 + maturity * .80
    for cane in 0 ..< config.scaffold_count {
        key := 1000 + u64(cane)
        emergence := f32(cane) * .72 / f32(max(config.scaffold_count - 1, 1))
        angle := phase + f32(cane) * 2.399963
        radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
        tangent := plant_structure.Vec3{-radial[2], 0, radial[0]}
        axis, unit, visible := graph_builder_axis(&builder, -1, -1, .Renewal_Cane, .Arching, key, emergence)
        if !visible do continue
        position := radial * .025 * growth
        parent := -1
        radius := config.trunk_radius * (.30 + maturity * .70)
        for node in 0 ..< 4 {
            progress := f32(node + 1) / 4
            next :=
                radial * config.crown_spread * growth * progress +
                plant_structure.Vec3{0, config.crown_rise * growth * progress, 0} +
                tangent * math.sin(progress * math.PI) * .045 * growth
            parent = graph_builder_internode(
                &builder,
                axis,
                unit,
                parent,
                position,
                next,
                radius,
                radius * .76,
                key * 256 + u64(node),
                emergence + f32(node) * .05,
            )
            if parent >= 0 {
                native_woody_leaf_pair(
                    &builder,
                    parent,
                    radial,
                    tangent,
                    key * 1024 + u64(node),
                    emergence + f32(node) * .05,
                    node + 1,
                )
            }
            position = next
            radius *= .76
        }
        if parent >= 0 && detail != .Far {
            if species == .Pomegranate {
                // Reproductive type is selected deterministically from this
                // current-shoot depth by the shared attachment policy.
                native_woody_leaf_pair(&builder, parent, radial, tangent, key * 4096, max(emergence, f32(.22)), 3)
            } else if species == .Myrtle || species == .Mastic {
                _ = graph_builder_lateral_shoot(
                    &builder,
                    parent,
                    linalg.normalize0(radial + plant_structure.Vec3{0, .35, 0}),
                    .18 * growth,
                    radius,
                    key * 64,
                    max(emergence, f32(.46)),
                )
            }
        }
    }
    builder_pointer^ = builder
}

native_crowned_woody_graph :: proc(
    builder_pointer: ^Graph_Builder,
    config: Native_Woody_Config,
    species: Species,
    maturity: f32,
    detail: Detail_Level,
    phase: f32,
) {
    builder := builder_pointer^
    growth := .18 + maturity * .82
    leader_axis, leader_unit, _ := graph_builder_axis(&builder, -1, -1, .Leader, .Orthotropic, 1)
    trunk_nodes := 5
    trunk_parent := -1
    trunk_position: plant_structure.Vec3
    trunk_radius := config.trunk_radius * (.28 + maturity * .72)
    trunk_nodes_by_index: [5]int
    for node in 0 ..< trunk_nodes {
        next :=
            trunk_position +
            plant_structure.Vec3 {
                    math.cos(phase + f32(node) * 1.7) * .012 * growth,
                    config.trunk_height * growth / f32(trunk_nodes),
                    math.sin(phase + f32(node) * 1.7) * .012 * growth,
                }
        trunk_parent = graph_builder_internode(
            &builder,
            leader_axis,
            leader_unit,
            trunk_parent,
            trunk_position,
            next,
            trunk_radius,
            trunk_radius * .84,
            256 + u64(node),
            f32(node) * .045,
        )
        trunk_nodes_by_index[node] = trunk_parent
        trunk_position = next
        trunk_radius *= .84
    }
    for scaffold in 0 ..< config.scaffold_count {
        key := 1000 + u64(scaffold)
        emergence := .18 + f32(scaffold) * .62 / f32(max(config.scaffold_count - 1, 1))
        angle := phase + f32(scaffold) * 2.399963
        radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
        tangent := plant_structure.Vec3{-radial[2], 0, radial[0]}
        attachment_node := config.form == .Umbrella_Conifer ? 3 + scaffold % 2 : 2 + scaffold % 3
        trunk_node := trunk_nodes_by_index[attachment_node]
        axis, unit, visible := graph_builder_axis(
            &builder,
            leader_axis,
            trunk_node,
            .Scaffold,
            .Plagiotropic,
            key,
            emergence,
        )
        if !visible do continue
        origin := builder.graph.internodes[trunk_node].end
        position := origin
        parent := trunk_node
        radius := trunk_radius * (config.form == .Umbrella_Conifer ? f32(.82) : f32(.72))
        for node in 0 ..< 3 {
            progress := f32(node + 1) / 3
            umbrella_lift := config.form == .Umbrella_Conifer ? progress * progress : progress
            next :=
                origin +
                radial * config.crown_spread * growth * progress +
                plant_structure.Vec3{0, config.crown_rise * growth * umbrella_lift * config.upright, 0} +
                tangent * math.sin(progress * math.PI) * .035 * growth
            parent = graph_builder_internode(
                &builder,
                axis,
                unit,
                parent,
                position,
                next,
                radius,
                radius * .66,
                key * 256 + u64(node),
                emergence + f32(node) * .045,
            )
            if parent >= 0 {
                for pair in 0 ..< config.leaf_pairs {
                    rotated_tangent := linalg.normalize0(
                        tangent * math.cos(f32(pair) * 2.399963) + radial * math.sin(f32(pair) * 2.399963),
                    )
                    native_woody_leaf_pair(
                        &builder,
                        parent,
                        radial,
                        rotated_tangent,
                        key * 4096 + u64(node * config.leaf_pairs + pair),
                        emergence + f32(node) * .045,
                        node + 1,
                    )
                }
            }
            position = next
            radius *= .66
        }
        if parent >= 0 && detail != .Far {
            if species == .Strawberry_Tree {
                organ := graph_builder_reproductive(&builder, parent, 1, .Flower, key * 8192, max(emergence, f32(.30)))
                if organ >= 0 do builder.graph.organs[organ].render_depth = -12
            } else if species == .Carob {
                organ := graph_builder_reproductive(&builder, parent, 1, .Fruit, key * 8192, max(emergence, f32(.68)))
                if organ >= 0 do builder.graph.organs[organ].render_depth = -13
            }
        }
    }
    builder_pointer^ = builder
}

native_woody_graph :: proc(species: Species, seed: u64, maturity: f32, detail: Detail_Level) -> Plant_Graph {
    builder := graph_builder_make(species, seed, maturity)
    config := native_woody_config(species, detail)
    phase := f32((seed ~ 0x574f4f44595f4752) % 10_000) / 10_000 * math.TAU
    if config.form == .Renewal {
        native_renewal_woody_graph(&builder, config, species, maturity, detail, phase)
    } else {
        native_crowned_woody_graph(&builder, config, species, maturity, detail, phase)
    }
    return graph_builder_take(&builder)
}

native_cypress_graph :: proc(seed: u64, maturity: f32, detail: Detail_Level) -> Plant_Graph {
    builder := graph_builder_make(.Italian_Cypress, seed, maturity)
    phase := f32((seed ~ 0x435950524553535f) % 10_000) / 10_000 * math.TAU
    growth := .14 + maturity * .86
    retained_tiers := detail == .Near ? 18 : detail == .Medium ? 14 : 11
    leader_axis, leader_unit, _ := graph_builder_axis(&builder, -1, -1, .Leader, .Orthotropic, 1)
    position: plant_structure.Vec3
    parent := -1
    radius := f32(.082) * (.28 + maturity * .72)
    for slot in 0 ..< retained_tiers {
        tier := retained_tiers == 1 ? 0 : slot * 17 / (retained_tiers - 1)
        emergence := .08 + f32(tier) * .82 / 17
        next := plant_structure.Vec3 {
            math.cos(phase + f32(tier) * 1.31) * .008 * growth,
            f32(tier + 1) / 18 * 1.42 * growth,
            math.sin(phase + f32(tier) * 1.31) * .008 * growth,
        }
        node := graph_builder_internode(
            &builder,
            leader_axis,
            leader_unit,
            parent,
            position,
            next,
            radius,
            radius * .91,
            256 + u64(tier),
            emergence,
        )
        if node < 0 do continue
        position = builder.graph.internodes[node].end
        parent = node
        radius *= .91
        branch_count := detail == .Far ? 3 : 4
        tier_fraction := f32(tier) / 17
        branch_length := (.22 + math.sin(tier_fraction * math.PI) * .22) * growth
        for branch in 0 ..< branch_count {
            angle := phase + f32(tier) * 2.399963 + f32(branch) * math.TAU / f32(branch_count)
            radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
            direction := linalg.normalize0(radial * .88 + plant_structure.Vec3{0, .36 + tier_fraction * .20, 0})
            key := 1000 + u64(tier * 8 + branch)
            branch_axis := graph_builder_lateral_shoot(
                &builder,
                node,
                direction,
                branch_length,
                max(radius * .34, f32(.0025)),
                key,
                emergence,
            )
            if branch_axis < 0 do continue
            branch_node := len(builder.graph.internodes) - 1
            tangent := plant_structure.Vec3{-radial[2], 0, radial[0]}
            for spray in 0 ..< 2 {
                organ := graph_builder_organ(
                    &builder,
                    branch_node,
                    spray == 0 ? f32(.42) : f32(.88),
                    .Leaf,
                    direction,
                    tangent,
                    key * 16 + u64(spray),
                    emergence,
                    u8(spray),
                )
                if organ >= 0 do builder.graph.organs[organ].render_depth = 1
            }
        }
    }
    if parent >= 0 {
        for cap in 0 ..< (detail == .Near ? 3 : detail == .Medium ? 2 : 1) {
            angle := phase + f32(cap) * 2.399963
            radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
            organ := graph_builder_organ(
                &builder,
                parent,
                1,
                .Leaf,
                linalg.normalize0(radial * .22 + plant_structure.Vec3{0, 1, 0}),
                radial,
                9000 + u64(cap),
                .18,
                u8(cap),
            )
            if organ >= 0 do builder.graph.organs[organ].render_depth = -2
        }
    }
    return graph_builder_take(&builder)
}
