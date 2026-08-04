package plants

import plant_structure "../plant_structure"
import "core:math"
import "core:math/linalg"

oleander_graph :: proc(seed: u64, maturity: f32, detail: Detail_Level) -> Plant_Graph {
    builder := graph_builder_make(.Oleander, seed, maturity)
    random := seed ~ 0x6f6c65616e646572
    if random == 0 do random = 1
    growth := .18 + maturity * .82
    cane_count := detail == .Near ? 9 : detail == .Medium ? 7 : 5
    phase := f32(plant_structure.random_next(&random) % 10_000) / 10_000 * math.TAU
    for cane in 0 ..< cane_count {
        cane_slot := cane_count == 1 ? 0 : cane * 8 / (cane_count - 1)
        key := 1000 + u64(cane_slot)
        emergence := f32(cane_slot) * .075
        angle := phase + f32(cane_slot) * math.TAU / 9
        radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
        direction := linalg.normalize0(radial * .28 + plant_structure.Vec3{0, 1, 0})
        axis, unit, visible := graph_builder_axis(&builder, -1, -1, .Renewal_Cane, .Orthotropic, key, emergence)
        if !visible do continue
        position := radial * (.025 + f32(cane % 3) * .009)
        radius := .020 * (.24 + maturity * .76)
        parent := -1
        for node in 0 ..< 6 {
            next := position + direction * (.105 + f32(node) * .006) * growth
            parent = graph_builder_internode(
                &builder, axis, unit, parent, position, next, radius, radius * .84,
                key * 256 + u64(node), emergence + f32(node) * .025,
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
                    &builder, parent, 1, .Leaf, leaf_forward, direction,
                    key * 4096 + u64(node) * 8 + u64(leaf), emergence + f32(node) * .025, u8(leaf),
                )
            }
            if detail != .Far && node >= 4 {
                side := cane & 1 == 0 ? tangent : -tangent
                flower_axis := graph_builder_shoot(
                    &builder, parent, linalg.normalize0(direction * .35 + side * .75), .11 * growth,
                    radius * .42, .Flowering_Shoot, .Arching, key * 64 + u64(node),
                    max(f32(.48), emergence + f32(node) * .025),
                )
                if flower_axis >= 0 {
                    organ := graph_builder_reproductive(
                        &builder, len(builder.graph.internodes) - 1, 1, .Flower, key * 8192 + u64(node), .48,
                    )
                    if organ >= 0 do builder.graph.organs[organ].render_depth = -9
                }
            }
            position = next
            radius *= .84
        }
    }
    return graph_builder_take(&builder)
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
            &builder, core, 0, .Rosette_Leaf, forward, {-radial[2], 0, radial[0]},
            1000 + u64(leaf), f32(leaf) * .006, u8(leaf & 3),
        )
    }
    if detail != .Far {
        scape_count := detail == .Near ? 3 : 2
        for scape in 0 ..< scape_count {
            key := 2000 + u64(scape)
            angle := phase + f32(scape) * math.TAU / f32(scape_count)
            radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
            start := radial * (.035 + f32(scape % 2) * .018)
            scape_axis, scape_unit, visible := graph_builder_axis(
                &builder, -1, -1, .Inflorescence, .Orthotropic, key, .42 + f32(scape) * .035,
            )
            if !visible do continue
            node := graph_builder_internode(
                &builder, scape_axis, scape_unit, -1, start,
                start + radial * .120 + plant_structure.Vec3{0, (.60 + f32(scape) * .055) * growth, 0},
                .009, .0045, key * 256, .42 + f32(scape) * .035,
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
            next := radial * spread * growth * progress + plant_structure.Vec3{0, height * growth * progress, 0} +
                tangent * math.sin(progress * math.PI) * .025 * growth
            parent = graph_builder_internode(
                &builder, axis, unit, parent, position, next, current_radius, current_radius * .72,
                key * 256 + u64(node), emergence + f32(node) * .055,
            )
            if parent >= 0 {
                leaf_tilt := species == .Rosemary || species == .Lavender ? f32(.30) : f32(.16)
                _ = graph_builder_organ(
                    &builder, parent, .72, .Leaf, linalg.normalize0(tangent + plant_structure.Vec3{0, leaf_tilt, 0}),
                    radial, key * 1024 + u64(node) * 2, emergence + f32(node) * .055,
                )
                _ = graph_builder_organ(
                    &builder, parent, .72, .Leaf, linalg.normalize0(-tangent + plant_structure.Vec3{0, leaf_tilt, 0}),
                    -radial, key * 1024 + u64(node) * 2 + 1, emergence + f32(node) * .055, 1,
                )
            }
            position = next
            current_radius *= .72
        }
        if flower_modulus > 0 && stem % flower_modulus != 0 && parent >= 0 && detail != .Far {
            organ := graph_builder_reproductive(
                &builder, parent, 1, .Flower, key * 4096, max(flower_emergence, emergence),
            )
            if organ >= 0 do builder.graph.organs[organ].render_depth = flower_depth
        }
    }
    return graph_builder_take(&builder)
}
