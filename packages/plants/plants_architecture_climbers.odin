package plants

import plant_structure "../plant_structure"
import "core:math"
import "core:math/linalg"

native_climber_graph :: proc(species: Species, seed: u64, maturity: f32, detail: Detail_Level) -> Plant_Graph {
    builder := graph_builder_make(species, seed, maturity)
    random := seed ~ 0x434c494d4245525f
    if random == 0 do random = 1
    growth := .12 + clamp(maturity, f32(0), f32(1)) * .88
    cane_count := detail == .Near ? 9 : detail == .Medium ? 7 : 5
    node_count := detail == .Near ? 7 : detail == .Medium ? 6 : 5
    twining := species == .Wisteria || species == .Star_Jasmine
    phase := f32(plant_structure.random_next(&random) % 10_000) / 10_000 * math.TAU
    for cane in 0 ..< cane_count {
        key := 20_000 + u64(cane)
        emergence := .03 + f32(cane) * .055
        axis, unit, visible := graph_builder_axis(
            &builder, -1, -1, .Climber, twining ? Axis_Orientation.Twining : .Arching, key, emergence, .72,
        )
        if !visible do continue
        lane := cane_count == 1 ? f32(0) : f32(cane) / f32(cane_count - 1) * 2 - 1
        position := plant_structure.Vec3{lane * .34 * growth, 0, 0}
        parent := -1
        radius :=
            (species == .Wisteria ? f32(.018) : species == .Grapevine ? f32(.014) : f32(.009)) * (.28 + maturity * .72)
        for node in 0 ..< node_count {
            progress := f32(node + 1) / f32(node_count)
            weave := math.sin(progress * math.TAU * (1.25 + f32(cane % 3) * .25) + phase + f32(cane))
            next :=
                position +
                plant_structure.Vec3{
                    weave * .075 * growth,
                    (.14 + f32(node) * .012) * growth,
                    math.cos(phase + f32(node) * 1.7) * .025 * growth,
                }
            parent = graph_builder_internode(
                &builder, axis, unit, parent, position, next, radius, radius * .84,
                key * 256 + u64(node), emergence + f32(node) * .045,
            )
            if parent < 0 do break
            direction := linalg.normalize0(next - position)
            side := linalg.normalize0(plant_structure.Vec3{-direction[2], .12, direction[0]})
            leaf := graph_builder_organ(
                &builder, parent, .72, .Leaf, side, direction, key * 1024 + u64(node) * 4,
                emergence + f32(node) * .045, u8((cane + node) & 3),
            )
            if leaf >= 0 do builder.graph.organs[leaf].render_depth = node + 1
            if maturity > .30 && detail != .Far && node >= 2 && (node + cane) % 3 == 0 {
                kind: Architecture_Organ
                depth := -10
                if species == .Grapevine {
                    kind = (node + cane) % 2 == 0 ? .Fruit : .Tendril
                    depth = -14
                } else if species == .Bougainvillea {
                    kind = (node + cane) % 4 == 0 ? .Thorn : .Flower
                    depth = -15
                } else {
                    kind = .Flower
                    if species == .Climbing_Rose do depth = -11
                    if species == .Star_Jasmine do depth = -16
                }
                organ := graph_builder_organ(
                    &builder, parent, 1, kind, direction, side, key * 1024 + u64(node) * 4 + 1,
                    .30 + f32(node) * .035, u8(node & 3),
                )
                if organ >= 0 do builder.graph.organs[organ].render_depth = depth
            }
            position = next
            radius *= .84
        }
    }
    return graph_builder_take(&builder)
}

pelargonium_graph :: proc(seed: u64, maturity: f32) -> Plant_Graph {
    builder := graph_builder_make(.Pelargonium, seed, maturity)
    growth := clamp(maturity, f32(0), f32(1))
    eased := growth * growth * (3 - 2 * growth)
    size := .16 + eased * .84
    random := seed ~ 0x70656c6172676f6e
    if random == 0 do random = 1
    phase := olive_random_signed(&random) * math.PI
    for stem in 0 ..< 12 {
        key := 1000 + u64(stem)
        emergence := f32(stem) / 15
        angle := phase + f32(stem) * 2.399963
        radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
        direction := linalg.normalize0(radial * (.34 + f32(stem % 4) * .035) + plant_structure.Vec3{0, .90, 0})
        axis, unit, visible := graph_builder_axis(&builder, -1, -1, .Renewal_Cane, .Arching, key, emergence)
        if !visible do continue
        position := radial * (.018 + f32(stem % 3) * .008) * size
        radius := .002 + eased * .0012
        parent := -1
        for node in 0 ..< 4 {
            node_emergence := emergence + f32(node) * .10
            length := (.055 + eased * .030) * (1 - f32(node) * .025) * size
            direction = linalg.normalize0(direction + radial * (.035 + f32(node) * .025))
            next := position + direction * length
            parent = graph_builder_internode(
                &builder, axis, unit, parent, position, next, radius, radius * .78,
                key * 256 + u64(node), node_emergence,
            )
            if parent >= 0 {
                _ = graph_builder_organ(
                    &builder, parent, 1, .Leaf, direction, radial, key * 512 + u64(node), node_emergence, u8(node),
                )
            }
            position = next
            radius *= .78
        }
        if stem & 1 == 0 && parent >= 0 {
            peduncle_direction := linalg.normalize0(direction * .34 + radial * .08 + plant_structure.Vec3{0, .94, 0})
            flower_axis := graph_builder_shoot(
                &builder, parent, peduncle_direction,
                (.055 + clamp((growth - .30) / .70, f32(0), f32(1)) * .028) * size,
                max(radius * .48, f32(.0012)), .Flowering_Shoot, .Orthotropic, key * 64,
                max(f32(.30), emergence + .30),
            )
            if flower_axis >= 0 {
                organ := graph_builder_reproductive(&builder, len(builder.graph.internodes) - 1, 1, .Flower, key * 1024, .30)
                if organ >= 0 do builder.graph.organs[organ].render_depth = -4
            }
        }
    }
    return graph_builder_take(&builder)
}

hydrangea_graph :: proc(species: Species, seed: u64, maturity: f32, detail: Detail_Level) -> Plant_Graph {
    builder := graph_builder_make(species, seed, maturity)
    growth := .22 + clamp(maturity, f32(0), f32(1)) * .78
    is_tree := species == .Hydrangea_Tree
    stem_count :=
        is_tree ? (detail == .Near ? 11 : detail == .Medium ? 8 : 6) : (detail == .Near ? 24 : detail == .Medium ? 20 : 18)
    phase := f32((seed ~ 0x68796472616e6765) % 10_000) / 10_000 * math.TAU
    crown_base: plant_structure.Vec3
    crown_parent, crown_axis := -1, -1
    crown_radius := f32(.010) * (.35 + maturity * .65)
    if is_tree {
        axis, unit, _ := graph_builder_axis(&builder, -1, -1, .Leader, .Orthotropic, 1)
        crown_axis = axis
        radius := f32(.045) * (.35 + maturity * .65)
        position: plant_structure.Vec3
        for node in 0 ..< 4 {
            angle := phase + f32(node) * 1.7
            next := position + plant_structure.Vec3{math.cos(angle) * .012 * growth, .245 * growth, math.sin(angle) * .012 * growth}
            crown_parent = graph_builder_internode(
                &builder, axis, unit, crown_parent, position, next, radius, radius * .84,
                256 + u64(node), f32(node) * .045,
            )
            position = next
            radius *= .84
        }
        crown_base = position
        crown_radius = radius * .30
    }
    for stem in 0 ..< stem_count {
        key := 1000 + u64(stem)
        emergence := f32(stem) * .70 / f32(max(stem_count - 1, 1))
        inner := !is_tree && stem % 3 == 0
        ring_count := inner ? max(stem_count / 3, 1) : max(stem_count - stem_count / 3, 1)
        ring_index := inner ? stem / 3 : stem - (stem + 2) / 3
        angle := (inner ? phase + math.PI / f32(ring_count) : phase) + f32(ring_index) * math.TAU / f32(ring_count)
        radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
        tangent := plant_structure.Vec3{-radial[2], 0, radial[0]}
        position := crown_base
        if !is_tree {
            spread := inner ? f32(.018) : f32(.052 + f32(ring_index % 3) * .012)
            position = radial * spread * growth
        }
        axis, unit, visible := graph_builder_axis(
            &builder, is_tree ? crown_axis : -1, is_tree ? crown_parent : -1,
            is_tree ? Axis_Role.Scaffold : .Renewal_Cane, .Arching, key, emergence,
        )
        if !visible do continue
        stem_origin := position
        radius := is_tree ? crown_radius : f32(.009) * (.35 + maturity * .65)
        reach := (is_tree ? f32(.52) : inner ? f32(.16) : f32(.50)) * growth
        rise := (is_tree ? f32(.56) : inner ? f32(.70) : f32(.58)) * growth
        parent := is_tree ? crown_parent : -1
        for node in 0 ..< 3 {
            progress := f32(node + 1) / 3
            next := stem_origin + radial * reach * math.sin(progress * math.PI * .5) +
                plant_structure.Vec3{0, rise * progress * (.78 + progress * .22), 0}
            parent = graph_builder_internode(
                &builder, axis, unit, parent, position, next, radius, radius * .72,
                key * 256 + u64(node), emergence + f32(node) * .045,
            )
            if parent >= 0 {
                normal := linalg.normalize0(plant_structure.Vec3{0, .72, 0} + radial * .62)
                _ = graph_builder_organ(
                    &builder, parent, .58, .Leaf, tangent, normal, key * 1024 + u64(node) * 2,
                    emergence + f32(node) * .045,
                )
                _ = graph_builder_organ(
                    &builder, parent, .58, .Leaf, -tangent, normal, key * 1024 + u64(node) * 2 + 1,
                    emergence + f32(node) * .045, 1,
                )
            }
            position = next
            radius *= .72
        }
        if parent >= 0 {
            organ := graph_builder_reproductive(&builder, parent, 1, .Flower, key * 4096, max(f32(.22), emergence))
            if organ >= 0 do builder.graph.organs[organ].render_depth = -9
        }
    }
    return graph_builder_take(&builder)
}
