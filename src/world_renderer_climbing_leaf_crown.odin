package main

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

Climbing_Leaf_Crown_Context :: struct {
    structure:                 terrain.Structure,
    vine_points:               [16]third_person.Vec3,
    vine_local_x:              [16]f32,
    vine_maturity, stem_end:   f32,
    seed, plant_seed:          u32,
    crown_detail_fade:         f32,
    mixed_use_storefront:      bool,
    surface_z, growth_density: f32,
}

world_climbing_leaf_crown :: proc(ctx: Climbing_Leaf_Crown_Context) {
    structure, vine_points, vine_local_x := ctx.structure, ctx.vine_points, ctx.vine_local_x
    vine_maturity, stem_end := ctx.vine_maturity, ctx.stem_end
    seed, plant_seed := ctx.seed, ctx.plant_seed
    crown_detail_fade := ctx.crown_detail_fade
    mixed_use_storefront := ctx.mixed_use_storefront
    surface_z, growth_density := ctx.surface_z, ctx.growth_density
    leaf_point_indices := structure.kind == .Architecture ? [6]int{7, 9, 11, 13, 14, 15} : [6]int{2, 5, 7, 10, 12, 15}
    crown_side := seed % 2 == 0 ? f32(1) : f32(-1)
    training_habit := architecture.bougainvillea_training_habit(plant_seed)
    for leaf_index in 0 ..< len(leaf_point_indices) {
        if structure.kind == .Architecture {
            active_branches := architecture.bougainvillea_active_branch_count(vine_maturity, len(leaf_point_indices))
            if leaf_index < len(leaf_point_indices) - active_branches do continue
        }
        point_index := leaf_point_indices[leaf_index]
        node_t := f32(point_index) / f32(len(vine_points) - 1)
        base := vine_points[point_index]
        leaf_side := leaf_index % 2 == 0 ? f32(1) : f32(-1)
        if structure.kind == .Architecture && leaf_index >= 3 {
            if training_habit == 0 {
                leaf_side = (leaf_index + int(seed)) % 2 == 0 ? f32(1) : f32(-1)
            } else {
                leaf_side = crown_side
                if leaf_index == 4 do leaf_side = -crown_side
            }
        }
        node_x := vine_local_x[point_index]
        branch_reach := structure.width * (.045 + node_t * .025)
        branch_rise := .08 + f32(leaf_index % 2) * .05
        if structure.kind == .Architecture {
            branch_reach = structure.width * (.018 + node_t * .038)
            branch_rise = .08 + node_t * .38 + f32(leaf_index % 2) * .12
            if mixed_use_storefront {
                branch_reach *= .42
            }
        }
        branch_x, branch_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            node_x + leaf_side * branch_reach,
            surface_z + .16,
            structure.rotation,
        )
        branch_end := third_person.Vec3{branch_x, min(base.y + branch_rise, stem_end + 1.8), branch_z}
        opening_badness := world_climbing_leaf_opening_badness(
            structure,
            node_x + leaf_side * branch_reach,
            branch_end.y - structure.base_y,
        )
        if opening_badness > .72 do continue
        branch_color := canvas2d.Color{62, 108, 55, 255}
        branch_base_radius := f32(.036)
        branch_tip_radius := f32(.032)
        if structure.kind == .Architecture {
            wood_age := clamp((vine_maturity - .06) / .50, 0, 1)
            wood_age = wood_age * wood_age * (3 - 2 * wood_age)
            branch_color = color_lerp({73, 103, 61, 255}, {105, 74, 51, 255}, wood_age)
            branch_base_radius = .034 + vine_maturity * .022
            branch_tip_radius = .027 + vine_maturity * .012
        }
        world_tube_between(base, branch_end, {0, 1, 0}, branch_base_radius, branch_tip_radius, branch_color)
        if structure.kind == .Architecture && vine_maturity > .24 {
            connector_amount := .52 + f32((seed + u32(leaf_index * 19)) % 3) * .08
            connector_center := third_person.Vec3 {
                base.x + (branch_end.x - base.x) * connector_amount,
                base.y + (branch_end.y - base.y) * connector_amount,
                base.z + (branch_end.z - base.z) * connector_amount,
            }
            connector_local_x := node_x + leaf_side * branch_reach * connector_amount
            connector_local_y := connector_center.y - structure.base_y
            connector_badness := world_climbing_leaf_opening_badness(structure, connector_local_x, connector_local_y)
            if connector_badness < .58 {
                outward_x, outward_z := world_rotate_xz(0, 0, 0, .11, structure.rotation)
                connector_center.x += outward_x
                connector_center.z += outward_z
                connector_scale := (.48 + vine_maturity * .22) * (1 - connector_badness * .34)
                connector_tile := int((seed + u32(leaf_index * 29)) % 4)
                connector_mirrored := leaf_side < 0
                connector_roll := leaf_side * (.018 + f32(leaf_index % 2) * .009)
                world_bougainvillea_card(
                    connector_center,
                    connector_scale * 1.06,
                    connector_scale * .82,
                    connector_tile,
                    connector_mirrored,
                    connector_roll,
                    .925,
                )
            }
        }
        cluster_structure := structure
        cluster_structure.base_y = branch_end.y - .72
        cluster_structure.seed = seed + u32(leaf_index * 41)
        cluster_x := node_x + leaf_side * branch_reach
        attachment_x, attachment_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            cluster_x,
            surface_z + .16,
            structure.rotation,
        )
        normal_sum := third_person.Vec3{}
        for normal_sample in -2 ..= 2 {
            sample_x := cluster_x + f32(normal_sample) * .12
            sample_z := surface_z + .16 + f32(math.sin(f64(f32(normal_sample) * .9))) * .06
            normal_local := linalg.normalize0(third_person.Vec3{sample_x, 0, sample_z})
            normal_world_x, normal_world_z := world_rotate_xz(0, 0, normal_local.x, normal_local.z, structure.rotation)
            normal_sum.x += normal_world_x
            normal_sum.z += normal_world_z
        }
        average_normal := linalg.normalize0(normal_sum)
        surface_rotation := -math.atan2(average_normal.x, average_normal.z)
        cluster_structure.rotation = surface_rotation
        offset_x := attachment_x - structure.center_x
        offset_z := attachment_z - structure.center_z
        surface_cosine, surface_sine := math.cos(surface_rotation), math.sin(surface_rotation)
        lobe_local_x := offset_x * surface_cosine + offset_z * surface_sine
        lobe_local_z := -offset_x * surface_sine + offset_z * surface_cosine
        world_tube_between(
            branch_end,
            {attachment_x, branch_end.y + .12, attachment_z},
            {0, 1, 0},
            .052,
            .045,
            {58, 101, 53, 255},
        )
        lobe_scale := 1 - opening_badness * .42
        crown_scale := f32(1)
        if structure.kind == .Architecture {
            maturity := architecture.bougainvillea_maturity(growth_density)
            maturity_scale := .52 + maturity * .48
            crown_scale = (.38 + node_t * 1.68) * maturity_scale
            if training_habit == 0 {
                if leaf_index >= 3 do crown_scale *= 1.06
            } else if leaf_side == crown_side {
                crown_scale *= 1.12
            }
            if mixed_use_storefront {
                crown_scale *= .52
            }
        }
        tangent := third_person.Vec3{-average_normal.z, 0, average_normal.x}
        cluster_center := third_person.Vec3 {
            attachment_x + average_normal.x * .32,
            branch_end.y + .10,
            attachment_z + average_normal.z * .32,
        }
        if structure.kind == .Architecture {
            maturity := architecture.bougainvillea_maturity(growth_density)
            flowering := architecture.bougainvillea_branch_flowering(maturity, node_t, seed, leaf_index)
            lateral_shape := math.abs(branch_reach) > branch_rise * .92
            variation := int((seed + u32(leaf_index * 7)) % 2) * 2 + (lateral_shape ? 1 : 0)
            tile := variation
            flower_base := architecture.bougainvillea_flower_tile_base(architecture.bougainvillea_palette(plant_seed))
            if flowering {
                tile = flower_base + variation
            }
            card_width := (2.34 + f32(variation % 2) * .20) * crown_scale * lobe_scale
            card_height := (1.84 + f32((variation + 1) % 3) * .14) * crown_scale * lobe_scale
            silhouette_step := f32(int((seed + u32(leaf_index * 11)) % 5) - 2)
            silhouette_shift := silhouette_step * card_width * .045
            cluster_center.y += silhouette_step * card_height * .035
            footprint_offsets := [5]f32{0, -.28, .28, -.48, .48}
            best_footprint_score := f32(1.0e20)
            footprint_badness := f32(1)
            clearance_shift := f32(0)
            attachment_local_y := cluster_center.y - structure.base_y
            for footprint_offset in footprint_offsets {
                candidate_shift := footprint_offset * card_width
                candidate_badness := f32(0)
                for footprint_x in -2 ..= 2 {
                    for footprint_y in 0 ..= 3 {
                        sample_x :=
                            cluster_x + silhouette_shift + candidate_shift + f32(footprint_x) * card_width * .34
                        sample_y := attachment_local_y + f32(footprint_y) * card_height * .30
                        candidate_badness = max(
                            candidate_badness,
                            world_climbing_leaf_stem_opening_badness(structure, sample_x, sample_y),
                        )
                    }
                }
                candidate_score := candidate_badness + math.abs(footprint_offset) * .05
                if candidate_score < best_footprint_score {
                    best_footprint_score = candidate_score
                    footprint_badness = candidate_badness
                    clearance_shift = candidate_shift
                }
            }
            if footprint_badness > .90 {
                continue
            } else if footprint_badness > .72 {
                card_width *= .62
                card_height *= .62
            } else if footprint_badness > .58 {
                card_width *= .80
                card_height *= .80
            }
            card_facade_right_x, card_facade_right_z := world_rotate_xz(0, 0, 1, 0, structure.rotation)
            resolved_shift := silhouette_shift + clearance_shift
            cluster_center.x += card_facade_right_x * resolved_shift
            cluster_center.z += card_facade_right_z * resolved_shift
            if math.abs(resolved_shift) > card_width * .12 {
                world_tube_between(
                    branch_end,
                    cluster_center,
                    {0, 1, 0},
                    branch_tip_radius * .72,
                    branch_tip_radius * .42,
                    branch_color,
                )
            }
            mirrored := (leaf_index + int(seed)) % 2 == 0
            card_camera := perspective_camera(world_renderer.editor.camera_pose, 1.35)
            branch_delta := third_person.Vec3{branch_end.x - base.x, branch_end.y - base.y, branch_end.z - base.z}
            if lateral_shape {
                mirrored = linalg.dot(branch_delta, card_camera.right) < 0
            }
            card_roll := f32(int((seed + u32(leaf_index * 17)) % 7) - 3) * .016
            card_value := .965 + f32((seed + u32(leaf_index * 23)) % 4) * .012
            if flowering {
                card_value = architecture.bougainvillea_bract_value(
                    maturity,
                    node_t,
                    int((seed + u32(leaf_index * 23)) % 4),
                )
            }
            if flowering && maturity > .34 {
                foliage_tile := (variation + int((seed + u32(leaf_index * 13)) % 2) * 2) % 4
                foliage_center := cluster_center
                foliage_center.x +=
                    tangent.x * card_width * (mirrored ? f32(.10) : f32(-.10)) - average_normal.x * .045
                foliage_center.y -= card_height * .13
                foliage_center.z +=
                    tangent.z * card_width * (mirrored ? f32(.10) : f32(-.10)) - average_normal.z * .045
                world_bougainvillea_card(
                    foliage_center,
                    card_width * (.60 + maturity * .08),
                    card_height * (.56 + maturity * .08),
                    foliage_tile,
                    !mirrored,
                    -card_roll * .72,
                    .91,
                )
            }
            world_bougainvillea_card(cluster_center, card_width, card_height, tile, mirrored, card_roll, card_value)
            resting_leaf_index := 3 + int(plant_seed % 2)
            if crown_detail_fade > .02 && flowering && maturity > .62 && leaf_index == resting_leaf_index {
                resting_center := cluster_center
                resting_side := mirrored ? f32(1) : f32(-1)
                resting_center.x += tangent.x * card_width * resting_side * .20 + average_normal.x * .09
                resting_center.y -= card_height * .12
                resting_center.z += tangent.z * card_width * resting_side * .20 + average_normal.z * .09
                resting_tile := (variation + 3) % 4
                world_bougainvillea_card(
                    resting_center,
                    card_width * .40 * crown_detail_fade,
                    card_height * .38 * crown_detail_fade,
                    resting_tile,
                    !mirrored,
                    -card_roll * .58,
                    .93,
                    false,
                    resting_side * .085,
                )
            }
            if crown_detail_fade > .02 && maturity > .52 && node_t > .68 && (leaf_index + int(seed)) % 2 == 0 {
                depth_amount := .20 + maturity * .26
                depth_center := cluster_center
                depth_center.x += average_normal.x * depth_amount - tangent.x * card_width * .08
                depth_center.y -= card_height * (.08 + f32(leaf_index % 2) * .04)
                depth_center.z += average_normal.z * depth_amount - tangent.z * card_width * .08
                world_tube_between(
                    branch_end,
                    depth_center,
                    {0, 1, 0},
                    branch_tip_radius * .78 * crown_detail_fade,
                    branch_tip_radius * .48 * crown_detail_fade,
                    branch_color,
                )
                depth_tile := tile
                if flowering {
                    depth_tile = flower_base + (variation + 1) % 4
                } else {
                    depth_tile = (tile + 2) % 4
                }
                depth_mirrored := !mirrored
                world_bougainvillea_card(
                    depth_center,
                    card_width * (.46 + maturity * .10) * crown_detail_fade,
                    card_height * (.44 + maturity * .10) * crown_detail_fade,
                    depth_tile,
                    depth_mirrored,
                    card_roll * .58,
                    card_value * .955,
                    false,
                    depth_mirrored ? f32(-.13) : f32(.13),
                )
            }
            terminal_emphasis :=
                training_habit == 0 ? leaf_index >= len(leaf_point_indices) - 2 : leaf_side == crown_side
            if node_t > .76 && terminal_emphasis {
                echo_tile := tile
                if flowering {
                    echo_tile = flower_base + (variation + 2) % 4
                } else {
                    echo_tile = (tile + 2) % 4
                }
                echo_center := cluster_center
                echo_center.x += tangent.x * card_width * .24
                echo_center.y -= card_height * .18
                echo_center.z += tangent.z * card_width * .24
                echo_mirrored := linalg.dot(tangent, card_camera.right) < 0
                world_bougainvillea_card(
                    echo_center,
                    card_width * .62,
                    card_height * .60,
                    echo_tile,
                    echo_mirrored,
                    -card_roll * .84,
                    card_value * .98,
                    false,
                    echo_mirrored ? f32(-.075) : f32(.075),
                )
            }
            if flowering && node_t > .76 && terminal_emphasis {
                cascade_count := architecture.bougainvillea_cascade_count(maturity)
                cascade_side := mirrored ? f32(-1) : f32(1)
                cascade_parent := cluster_center
                for cascade in 0 ..< cascade_count {
                    cascade_scale := 1 - f32(cascade) * .18
                    cascade_width := card_width * .43 * cascade_scale
                    cascade_height := card_height * .50 * cascade_scale
                    lateral_drop := cascade_side * card_width * (.14 + f32(cascade) * .10)
                    vertical_drop := card_height * (.34 + f32(cascade) * .30)
                    cascade_local_x := cluster_x + resolved_shift + lateral_drop
                    cascade_local_y := cluster_center.y - structure.base_y - vertical_drop
                    cascade_badness := f32(0)
                    for footprint_x in -1 ..= 1 {
                        for footprint_y in 0 ..= 2 {
                            sample_x := cascade_local_x + f32(footprint_x) * cascade_width * .34
                            sample_y := cascade_local_y + f32(footprint_y) * cascade_height * .32
                            cascade_badness = max(
                                cascade_badness,
                                world_climbing_leaf_stem_opening_badness(structure, sample_x, sample_y),
                            )
                        }
                    }
                    if cascade_badness > .72 do continue
                    cascade_center := cluster_center
                    cascade_center.x += tangent.x * lateral_drop + average_normal.x * (.10 + f32(cascade) * .06)
                    cascade_center.y -= vertical_drop
                    cascade_center.z += tangent.z * lateral_drop + average_normal.z * (.10 + f32(cascade) * .06)
                    world_tube_between(
                        cascade_parent,
                        cascade_center,
                        {0, 1, 0},
                        branch_tip_radius * (.54 - f32(cascade) * .08),
                        branch_tip_radius * .28,
                        branch_color,
                    )
                    cascade_tile := flower_base + (variation + cascade + 1) % 4
                    world_bougainvillea_card(
                        cascade_center,
                        cascade_width,
                        cascade_height,
                        cascade_tile,
                        cascade % 2 == 0 ? !mirrored : mirrored,
                        card_roll * .45 + cascade_side * .022,
                        card_value * (.985 - f32(cascade) * .018),
                    )
                    cascade_parent = cascade_center
                }
            }
        } else {
            world_foliage_lobe(
                cluster_structure,
                lobe_local_x,
                lobe_local_z,
                (1.52 + f32((seed + u32(leaf_index)) % 3) * .14) * lobe_scale * crown_scale,
                .86 * crown_scale,
                (1.42 + f32((seed + u32(leaf_index * 3)) % 3) * .14) * lobe_scale * crown_scale,
                0,
                false,
                1 + int((seed + u32(leaf_index)) % 3),
                0,
                false,
            )
        }
        if structure.kind == .Architecture do continue
        spray_scale := (.74 + f32((seed + u32(leaf_index)) % 3) * .09) * crown_scale
        world_foliage_card(
            {cluster_center.x + tangent.x * .14, cluster_center.y + .05, cluster_center.z + tangent.z * .14},
            spray_scale,
            spray_scale * .86,
            leaf_index * 5 + 7,
            world_foliage_vertex_color(3, 1 + int((seed + u32(leaf_index)) % 3)),
            leaf_index % 2 == 0,
        )
        world_foliage_card(
            {
                cluster_center.x - tangent.x * .18 + average_normal.x * .08,
                cluster_center.y - .08,
                cluster_center.z - tangent.z * .18 + average_normal.z * .08,
            },
            spray_scale * .68,
            spray_scale * .62,
            leaf_index * 7 + 3,
            world_foliage_vertex_color(2, 1 + int((seed + u32(leaf_index + 1)) % 3)),
            leaf_index % 2 != 0,
        )
        accent_count := structure.kind == .Architecture ? 4 : 3
        for leaf_accent in 0 ..< accent_count {
            accent_side := leaf_accent == 1 ? f32(-1) : f32(1)
            accent_offset := (f32(leaf_accent) - f32(accent_count - 1) * .5) * .24 * crown_scale
            accent_center := third_person.Vec3 {
                cluster_center.x + tangent.x * accent_offset + average_normal.x * (.10 + f32(leaf_accent % 2) * .05),
                cluster_center.y + f32(leaf_accent - 1) * .16,
                cluster_center.z + tangent.z * accent_offset + average_normal.z * (.10 + f32(leaf_accent % 2) * .05),
            }
            accent_width := (.22 + f32(leaf_accent % 2) * .04) * crown_scale
            accent_height := .10 * crown_scale
            accent_color := leaf_accent == 1 ? canvas2d.Color{93, 151, 70, 255} : canvas2d.Color{76, 135, 65, 255}
            if structure.kind == .Architecture {
                world_tapered_disc_depth_rotated(
                    accent_center,
                    accent_width,
                    accent_height,
                    accent_width * .78,
                    accent_height * .82,
                    .035,
                    surface_rotation + accent_side * .12,
                    accent_color,
                )
            } else {
                world_ellipsoid_rotated(
                    accent_center,
                    accent_width,
                    accent_height,
                    (.14 + f32(leaf_accent) * .015) * crown_scale,
                    surface_rotation + accent_side * .12,
                    accent_color,
                )
            }
        }
        flowering := (seed + u32(leaf_index * 5)) % 3 == 0
        if structure.kind == .Architecture {
            flowering = node_t > .58 && (seed + u32(leaf_index * 5)) % 4 != 0
        }
        if flowering {
            petal_count := structure.kind == .Architecture ? 36 : 3
            flower_palette := int(seed % 3)
            for petal in 0 ..< petal_count {
                flower_index := petal
                bract_index := 0
                flower_count := petal_count
                if structure.kind == .Architecture {
                    flower_index = petal / 3
                    bract_index = petal % 3
                    flower_count = petal_count / 3
                }
                petal_angle := f32(flower_index) * 2.399963
                petal_radius := (.11 + f32(petal % 4) * .09) * crown_scale
                if structure.kind == .Architecture {
                    petal_radius =
                        (.08 + f32(math.sqrt(f64(f32(flower_index + 1) / f32(flower_count)))) * .62) * crown_scale
                }
                bloom_center := third_person.Vec3 {
                    cluster_center.x +
                    tangent.x * f32(math.cos(f64(petal_angle))) * petal_radius +
                    average_normal.x * (.20 + f32(petal % 2) * .05),
                    cluster_center.y + .12 + f32(math.sin(f64(petal_angle))) * petal_radius * .72,
                    cluster_center.z +
                    tangent.z * f32(math.cos(f64(petal_angle))) * petal_radius +
                    average_normal.z * (.20 + f32(petal % 2) * .05),
                }
                bloom_color := canvas2d.Color{238, 121, 151, 255}
                switch flower_palette {
                case 0:
                    if petal % 3 == 0 {
                        bloom_color = {226, 90, 134, 255}
                    } else if petal % 3 == 1 {
                        bloom_color = {202, 57, 111, 255}
                    }
                case 1:
                    bloom_color = {245, 142, 112, 255}
                    if petal % 3 == 0 {
                        bloom_color = {231, 98, 82, 255}
                    } else if petal % 3 == 1 {
                        bloom_color = {202, 65, 70, 255}
                    }
                case 2:
                    bloom_color = {220, 123, 181, 255}
                    if petal % 3 == 0 {
                        bloom_color = {192, 78, 158, 255}
                    } else if petal % 3 == 1 {
                        bloom_color = {153, 57, 136, 255}
                    }
                }
                bloom_width := .14 * crown_scale
                bloom_height := .10 * crown_scale
                if structure.kind == .Architecture {
                    bloom_width = .15 * crown_scale
                    bloom_height = .112 * crown_scale
                    bract_rotation := f32(bract_index) * math.PI * 2 / 3 + f32(seed % 11) * .19
                    direction_x := tangent.x * f32(math.cos(f64(bract_rotation)))
                    direction_y := f32(math.sin(f64(bract_rotation)))
                    direction_z := tangent.z * f32(math.cos(f64(bract_rotation)))
                    perpendicular_x := tangent.x * -f32(math.sin(f64(bract_rotation)))
                    perpendicular_y := f32(math.cos(f64(bract_rotation)))
                    perpendicular_z := tangent.z * -f32(math.sin(f64(bract_rotation)))
                    bract_tip := third_person.Vec3 {
                        bloom_center.x + direction_x * bloom_height,
                        bloom_center.y + direction_y * bloom_height,
                        bloom_center.z + direction_z * bloom_height,
                    }
                    bract_left := third_person.Vec3 {
                        bloom_center.x - direction_x * bloom_height * .58 - perpendicular_x * bloom_width,
                        bloom_center.y - direction_y * bloom_height * .58 - perpendicular_y * bloom_width,
                        bloom_center.z - direction_z * bloom_height * .58 - perpendicular_z * bloom_width,
                    }
                    bract_right := third_person.Vec3 {
                        bloom_center.x - direction_x * bloom_height * .58 + perpendicular_x * bloom_width,
                        bloom_center.y - direction_y * bloom_height * .58 + perpendicular_y * bloom_width,
                        bloom_center.z - direction_z * bloom_height * .58 + perpendicular_z * bloom_width,
                    }
                    world_triangle_material(bract_tip, bract_left, bract_right, bloom_color, .Petal)
                    world_triangle_material(bract_tip, bract_right, bract_left, bloom_color, .Petal)
                    if bract_index == 2 {
                        flower_center := bloom_center
                        flower_center.x += average_normal.x * .018
                        flower_center.z += average_normal.z * .018
                        world_tapered_disc_depth_rotated(
                            flower_center,
                            .042 * crown_scale,
                            .034 * crown_scale,
                            .030 * crown_scale,
                            .026 * crown_scale,
                            .012,
                            surface_rotation,
                            {244, 218, 145, 255},
                        )
                    }
                } else {
                    world_ellipsoid_rotated(
                        bloom_center,
                        bloom_width,
                        bloom_height,
                        .12 * crown_scale,
                        surface_rotation,
                        bloom_color,
                    )
                }
            }
        }
        node_width := max(f32(.18), min(structure.width * .04, f32(.32)))
        node_color := leaf_index % 2 == 0 ? canvas2d.Color{63, 117, 62, 255} : canvas2d.Color{78, 136, 70, 255}
        if structure.kind == .Architecture {
            world_tapered_disc_depth_rotated(
                branch_end,
                node_width,
                .09,
                node_width * .72,
                .072,
                .035,
                surface_rotation,
                node_color,
            )
        } else {
            world_ellipsoid_rotated(branch_end, node_width, .09, .15, structure.rotation, node_color)
        }
    }
}
