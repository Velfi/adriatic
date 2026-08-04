package plants

import plant_structure "../plant_structure"
import "core:math"
import "core:math/linalg"
prickly_pear_graph :: proc(seed: u64, maturity: f32) -> Plant_Graph {
    builder := graph_builder_make(.Prickly_Pear, seed, maturity)
    random := seed ~ 0x8cb92baa3f3d8dd7
    if random == 0 do random = 1
    scale := .34 + maturity * .66
    basal_count := maturity < .34 ? 1 : maturity < .64 ? 2 : 3
    child_count := maturity < .42 ? 0 : maturity < .74 ? 1 : 2
    phase := f32(plant_structure.random_next(&random) % 10_000) / 10_000 * math.PI * 2

    for basal_index in 0 ..< basal_count {
        centered := f32(basal_index) - f32(basal_count - 1) * .5
        base := plant_structure.Vec3{centered * .20 * scale, 0, olive_random_signed(&random) * .055 * scale}
        base_normal := phase + f32(basal_index) * .86 + olive_random_signed(&random) * .18
        stable_key := u64(100 + basal_index)
        axis, unit, visible := graph_builder_axis(
            &builder,
            -1,
            -1,
            .Leader,
            .Orthotropic,
            stable_key,
            f32(basal_index) * .12,
        )
        if !visible do continue
        basal := graph_builder_internode(
            &builder,
            axis,
            unit,
            -1,
            base,
            base + plant_structure.Vec3{0, .10 * scale, 0},
            .012 * scale,
            .008 * scale,
            stable_key * 256,
            f32(basal_index) * .12,
        )
        normal := plant_structure.Vec3{math.cos(base_normal), 0, math.sin(base_normal)}
        _ = graph_builder_organ(&builder, basal, 0, .Cladode, {0, 1, 0}, normal, stable_key * 256 + 1)

        for child_index in 0 ..< child_count {
            side := child_index == 0 ? f32(-1) : f32(1)
            outward := centered == 0 ? side : (centered < 0 ? f32(-1) : f32(1))
            child_base :=
                base +
                plant_structure.Vec3 {
                        outward * (.055 + .015 * f32(child_index)) * scale,
                        (.255 + .025 * f32((basal_index + child_index) % 2)) * scale,
                        side * (.055 + olive_random_signed(&random) * .018) * scale,
                    }
            child_normal := base_normal + side * (.48 + olive_random_signed(&random) * .14)
            child_key := stable_key * 16 + u64(child_index + 1)
            child_axis := graph_builder_lateral_shoot(
                &builder,
                basal,
                child_base - builder.graph.internodes[basal].end,
                max(
                    f32(
                        math.sqrt(
                            f64(
                                linalg.dot(
                                    child_base - builder.graph.internodes[basal].end,
                                    child_base - builder.graph.internodes[basal].end,
                                ),
                            ),
                        ),
                    ),
                    f32(.02),
                ),
                .006 * scale,
                child_key,
                .42 + f32(child_index) * .12,
            )
            if child_axis < 0 do continue
            child_node := len(builder.graph.internodes) - 1
            child_pad_normal := plant_structure.Vec3{math.cos(child_normal), 0, math.sin(child_normal)}
            _ = graph_builder_organ(
                &builder,
                child_node,
                1,
                .Cladode,
                {0, 1, 0},
                child_pad_normal,
                child_key * 256 + 1,
                .42,
            )

            if maturity < .82 do continue
            top_side := (basal_index + child_index) % 2 == 0 ? f32(-1) : f32(1)
            top_base :=
                child_base +
                plant_structure.Vec3 {
                        top_side * (.040 + math.abs(olive_random_signed(&random)) * .018) * scale,
                        (.215 + olive_random_signed(&random) * .015) * scale,
                        -side * .022 * scale,
                    }
            top_key := child_key * 16 + 1
            top_axis := graph_builder_lateral_shoot(
                &builder,
                child_node,
                top_base - builder.graph.internodes[child_node].end,
                max(
                    f32(
                        math.sqrt(
                            f64(
                                linalg.dot(
                                    top_base - builder.graph.internodes[child_node].end,
                                    top_base - builder.graph.internodes[child_node].end,
                                ),
                            ),
                        ),
                    ),
                    f32(.02),
                ),
                .004 * scale,
                top_key,
                .82,
            )
            if top_axis >= 0 {
                top_node := len(builder.graph.internodes) - 1
                top_normal_angle := child_normal + top_side * (.36 + olive_random_signed(&random) * .10)
                top_normal := plant_structure.Vec3{math.cos(top_normal_angle), 0, math.sin(top_normal_angle)}
                _ = graph_builder_organ(&builder, top_node, 1, .Cladode, {0, 1, 0}, top_normal, top_key * 256 + 1, .82)
            }
        }
    }
    return graph_builder_take(&builder)
}
succulent_emit_rosette :: proc(
    plant: ^plant_structure.Plant,
    center: plant_structure.Vec3,
    count: int,
    phase, rise, spread: f32,
    depth: int,
) {
    if plant == nil || count <= 0 do return
    for index in 0 ..< count {
        angle := phase + f32(index) * math.PI * 2 / f32(count)
        radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
        forward := linalg.normalize0(radial * spread + plant_structure.Vec3{0, rise, 0})
        tangent := plant_structure.Vec3{-radial[2], 0, radial[0]}
        // Attachment `up` is the leaf-face normal; renderers derive the
        // lateral width axis as cross(forward, up). Author a normal that
        // makes that axis follow the rosette tangent. Passing the tangent as
        // `up` turned leaf width vertically and reduced rosettes to edges.
        face_normal := linalg.normalize0(linalg.cross(tangent, forward))
        append(
            &plant.leaves,
            plant_structure.Leaf{position = center, forward = forward, up = face_normal, depth = depth},
        )
    }
}

fleshy_graph_rosette :: proc(
    builder: ^Graph_Builder,
    internode, count: int,
    phase, rise, spread: f32,
    stable_key: u64,
    emergence: f32,
) {
    for index in 0 ..< count {
        angle := phase + f32(index) * math.TAU / f32(max(count, 1))
        radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
        forward := linalg.normalize0(radial * spread + plant_structure.Vec3{0, rise, 0})
        tangent := plant_structure.Vec3{-radial[2], 0, radial[0]}
        face_normal := linalg.normalize0(linalg.cross(tangent, forward))
        _ = graph_builder_organ(
            builder,
            internode,
            .05,
            .Rosette_Leaf,
            forward,
            face_normal,
            stable_key * 64 + u64(index),
            emergence + f32(index) * .004,
            u8(index & 3),
        )
    }
}

fleshy_plant_graph :: proc(species: Species, seed: u64, maturity: f32, detail: Detail_Level) -> Plant_Graph {
    builder := graph_builder_make(species, seed, maturity)
    random := seed ~ 0xa0761d6478bd642f
    if random == 0 do random = 1
    phase := f32(plant_structure.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    growth := .28 + maturity * .72

    axis, unit, _ := graph_builder_axis(&builder, -1, -1, .Leader, .Orthotropic, 1)
    core := graph_builder_internode(&builder, axis, unit, -1, {}, {0, .06 * growth, 0}, .009, .006, 256)
    if species == .Golden_Barrel {
        rib_count := detail == .Near ? 20 : detail == .Medium ? 14 : 9
        radius := (.13 + maturity * .16)
        for index in 0 ..< rib_count {
            angle := phase + f32(index) * math.PI * 2 / f32(rib_count)
            radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
            rib_key := 1000 + u64(index)
            rib_axis := graph_builder_runner(&builder, core, radial, radius, .002, rib_key, f32(index) * .006)
            if rib_axis >= 0 {
                _ = graph_builder_organ(
                    &builder,
                    len(builder.graph.internodes) - 1,
                    1,
                    .Cactus_Rib,
                    {0, 1, 0},
                    radial,
                    rib_key * 256 + 1,
                    f32(index) * .006,
                )
            }
        }
        return graph_builder_take(&builder)
    }

    outer_count := detail == .Near ? 18 : detail == .Medium ? 12 : 8
    inner_count := detail == .Near ? 11 : detail == .Medium ? 7 : 5
    if species == .Agave {
        fleshy_graph_rosette(&builder, core, outer_count, phase, .30, 1, 2000, 0)
        if maturity >= .42 {
            fleshy_graph_rosette(&builder, core, inner_count, phase + .31, .70, .72, 3000, .42)
        }
    } else {
        // Aloe is a narrower, more upright clumping rosette. Mature plants
        // add two small deterministic offsets instead of becoming one agave.
        aloe_outer_count := detail == .Near ? 14 : detail == .Medium ? 10 : 7
        aloe_inner_count := detail == .Near ? 8 : detail == .Medium ? 6 : 4
        fleshy_graph_rosette(&builder, core, aloe_outer_count, phase, 1.05, .58, 4000, 0)
        fleshy_graph_rosette(&builder, core, aloe_inner_count, phase + .37, 1.20, .40, 5000, .18)
        if maturity >= .72 && detail != .Far {
            offset_count := detail == .Near ? 5 : 4
            first_axis := graph_builder_runner(&builder, core, {.18, .02, -.10}, .22 * growth, .004, 6000, .72)
            if first_axis >= 0 do fleshy_graph_rosette(&builder, len(builder.graph.internodes) - 1, offset_count, phase + 1.1, 1, .50, 6100, .72)
            second_axis := graph_builder_runner(&builder, core, {-.16, .02, .12}, .20 * growth, .004, 7000, .72)
            if second_axis >= 0 do fleshy_graph_rosette(&builder, len(builder.graph.internodes) - 1, offset_count, phase - .8, 1, .48, 7100, .72)
        }
    }
    return graph_builder_take(&builder)
}

succulent_catalog_graph :: proc(species: Species, seed: u64, maturity: f32, detail: Detail_Level) -> Plant_Graph {
    builder := graph_builder_make(species, seed, maturity)
    phase := f32((seed ~ 0xe7037ed1a0b428db) % 10_000) / 10_000 * math.TAU
    growth := .25 + maturity * .75

    if species == .Echeveria {
        axis, unit, _ := graph_builder_axis(&builder, -1, -1, .Leader, .Orthotropic, 1)
        core := graph_builder_internode(&builder, axis, unit, -1, {}, {0, .025, 0}, .008, .005, 256)
        fleshy_graph_rosette(&builder, core, detail == .Near ? 18 : detail == .Medium ? 12 : 8, phase, .32, 1, 1000, 0)
        fleshy_graph_rosette(
            &builder,
            core,
            detail == .Near ? 11 : detail == .Medium ? 7 : 5,
            phase + .29,
            .68,
            .70,
            2000,
            .18,
        )
        offset_axis := graph_builder_runner(&builder, core, {.21, .01, -.13}, .25 * growth, .004, 3000, .68)
        if offset_axis >= 0 && detail != .Far {
            fleshy_graph_rosette(&builder, len(builder.graph.internodes) - 1, 7, phase + .8, .48, .78, 3100, .68)
        }
        return graph_builder_take(&builder)
    }

    if species == .Aeonium {
        height := .24 + maturity * .62
        axis, unit, _ := graph_builder_axis(&builder, -1, -1, .Leader, .Orthotropic, 1)
        trunk := graph_builder_internode(
            &builder,
            axis,
            unit,
            -1,
            {},
            {0, height, 0},
            .045 * growth,
            .026 * growth,
            256,
        )
        rosette_count := detail == .Near ? 16 : detail == .Medium ? 11 : 7
        fleshy_graph_rosette(&builder, trunk, rosette_count, phase, .12, 1, 1000, 0)
        branch_count := detail == .Far ? 2 : 4
        for branch in 0 ..< branch_count {
            angle := phase + f32(branch) * math.TAU / f32(branch_count)
            radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
            branch_axis := graph_builder_lateral_shoot(
                &builder,
                trunk,
                radial * .78 + plant_structure.Vec3{0, .62, 0},
                .29 * growth,
                .025 * growth,
                2000 + u64(branch),
                .48 + f32(branch) * .025,
            )
            if branch_axis >= 0 {
                fleshy_graph_rosette(
                    &builder,
                    len(builder.graph.internodes) - 1,
                    max(rosette_count - 4, 5),
                    angle + .2,
                    .18,
                    1,
                    3000 + u64(branch) * 64,
                    .48,
                )
            }
        }
        return graph_builder_take(&builder)
    }

    if species == .Jade_Plant {
        stem_count := detail == .Near ? 5 : detail == .Medium ? 4 : 3
        node_count := detail == .Near ? 4 : detail == .Medium ? 3 : 2
        for stem in 0 ..< stem_count {
            key := 1000 + u64(stem)
            angle := phase + f32(stem) * math.TAU / f32(stem_count)
            radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
            axis, unit, visible := graph_builder_axis(
                &builder,
                -1,
                -1,
                .Renewal_Cane,
                .Orthotropic,
                key,
                f32(stem) * .018,
            )
            if !visible do continue
            position := radial * .035
            parent := -1
            for node in 0 ..< node_count {
                next :=
                    position + radial * (.030 + f32(node) * .008) * growth + plant_structure.Vec3{0, .13 * growth, 0}
                parent = graph_builder_internode(
                    &builder,
                    axis,
                    unit,
                    parent,
                    position,
                    next,
                    (.024 - f32(node) * .003) * growth,
                    (.021 - f32(node) * .003) * growth,
                    key * 256 + u64(node),
                    f32(node) * .06,
                )
                tangent := plant_structure.Vec3{-radial[2], 0, radial[0]}
                leaf_axis := node & 1 == 0 ? tangent : radial
                _ = graph_builder_organ(
                    &builder,
                    parent,
                    1,
                    .Leaf,
                    linalg.normalize0(leaf_axis + plant_structure.Vec3{0, .28, 0}),
                    radial,
                    key * 512 + u64(node) * 2,
                    f32(node) * .06,
                )
                _ = graph_builder_organ(
                    &builder,
                    parent,
                    1,
                    .Leaf,
                    linalg.normalize0(-leaf_axis + plant_structure.Vec3{0, .28, 0}),
                    -radial,
                    key * 512 + u64(node) * 2 + 1,
                    f32(node) * .06,
                )
                position = next
            }
        }
        return graph_builder_take(&builder)
    }

    if species == .Stonecrop {
        runner_count := detail == .Near ? 20 : detail == .Medium ? 13 : 8
        node_count := detail == .Near ? 5 : detail == .Medium ? 4 : 3
        for runner in 0 ..< runner_count {
            key := 1000 + u64(runner)
            angle := phase + f32(runner) * math.TAU / f32(runner_count)
            radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
            tangent := plant_structure.Vec3{-radial[2], 0, radial[0]}
            axis, unit, visible := graph_builder_axis(&builder, -1, -1, .Runner, .Prostrate, key, f32(runner) * .009)
            if !visible do continue
            position: plant_structure.Vec3
            parent := -1
            for node in 0 ..< node_count {
                next := position + radial * .060 * growth + plant_structure.Vec3{0, .012 + f32(node) * .003, 0}
                parent = graph_builder_internode(
                    &builder,
                    axis,
                    unit,
                    parent,
                    position,
                    next,
                    .010,
                    .007,
                    key * 256 + u64(node),
                    f32(node) * .045,
                )
                _ = graph_builder_organ(
                    &builder,
                    parent,
                    1,
                    .Leaf,
                    linalg.normalize0(radial * .42 + tangent * .22 + plant_structure.Vec3{0, .82, 0}),
                    tangent,
                    key * 512 + u64(node) * 2,
                    f32(node) * .045,
                )
                _ = graph_builder_organ(
                    &builder,
                    parent,
                    1,
                    .Leaf,
                    linalg.normalize0(radial * .18 - tangent * .48 + plant_structure.Vec3{0, .86, 0}),
                    radial,
                    key * 512 + u64(node) * 2 + 1,
                    f32(node) * .045,
                )
                position = next
            }
        }
        return graph_builder_take(&builder)
    }

    if species == .Blue_Chalk_Sticks {
        clump_count := detail == .Near ? 6 : detail == .Medium ? 4 : 3
        leaf_count := detail == .Near ? 8 : detail == .Medium ? 6 : 4
        for clump in 0 ..< clump_count {
            key := 1000 + u64(clump)
            angle := phase + f32(clump) * 2.399963
            distance := clump == 0 ? f32(0) : (.09 + f32(clump) * .045) * growth
            center := plant_structure.Vec3{math.cos(angle) * distance, .008, math.sin(angle) * distance}
            axis, unit, visible := graph_builder_axis(
                &builder,
                -1,
                -1,
                clump == 0 ? Axis_Role.Leader : .Runner,
                clump == 0 ? Axis_Orientation.Orthotropic : .Prostrate,
                key,
                f32(clump) * .04,
            )
            if !visible do continue
            node := graph_builder_internode(
                &builder,
                axis,
                unit,
                -1,
                {},
                center + plant_structure.Vec3{0, .025, 0},
                .007,
                .004,
                key * 256,
                f32(clump) * .04,
            )
            for leaf in 0 ..< leaf_count {
                leaf_angle := angle + f32(leaf) * 2.399963
                radial := plant_structure.Vec3{math.cos(leaf_angle), 0, math.sin(leaf_angle)}
                tangent := plant_structure.Vec3{-radial[2], 0, radial[0]}
                forward := linalg.normalize0(radial * (.18 + f32(leaf % 3) * .10) + plant_structure.Vec3{0, 1, 0})
                _ = graph_builder_organ(
                    &builder,
                    node,
                    1,
                    .Rosette_Leaf,
                    forward,
                    linalg.normalize0(linalg.cross(tangent, forward)),
                    key * 512 + u64(leaf),
                    f32(clump) * .04 + f32(leaf) * .006,
                )
            }
        }
        return graph_builder_take(&builder)
    }

    // Golden torch cactus: stable radial ribs surround a single column.
    axis, unit, _ := graph_builder_axis(&builder, -1, -1, .Leader, .Orthotropic, 1)
    column := graph_builder_internode(&builder, axis, unit, -1, {}, {0, .12 * growth, 0}, .012, .008, 256)
    rib_count := detail == .Near ? 18 : detail == .Medium ? 12 : 8
    for rib in 0 ..< rib_count {
        angle := phase + f32(rib) * math.TAU / f32(rib_count)
        radial := plant_structure.Vec3{math.cos(angle), 0, math.sin(angle)}
        _ = graph_builder_organ(&builder, column, 1, .Cactus_Rib, {0, 1, 0}, radial, 1000 + u64(rib), f32(rib) * .008)
    }
    return graph_builder_take(&builder)
}
