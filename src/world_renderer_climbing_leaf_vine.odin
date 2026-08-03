package main
import architecture "../packages/architecture"
import plants "../packages/plants"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"
world_climbing_leaf_vine :: proc(
    structure: terrain.Structure,
    local_x, root_local_x, surface_z, vine_height: f32,
    growth_density: f32,
    seed, plant_seed: u32,
    render_root: bool,
) {
    vine_maturity := f32(1)
    mixed_use_storefront :=
        structure.kind == .Architecture &&
        architecture.architecture_resolve_legacy_identity(structure).archetype == .Mixed_Use_Dwelling
    if structure.kind == .Architecture {
        vine_maturity = architecture.bougainvillea_maturity(growth_density)
    }
    detail_tier := 2
    crown_detail_fade := f32(1)
    if structure.kind == .Architecture && world_renderer.editor != nil {
        camera_position := world_renderer.editor.camera_pose.position
        camera_dx := camera_position.x - structure.center_x
        camera_dz := camera_position.z - structure.center_z
        camera_distance := f32(math.sqrt(f64(camera_dx * camera_dx + camera_dz * camera_dz)))
        detail_tier = architecture.bougainvillea_detail_tier(camera_distance)
        crown_detail_fade = architecture.bougainvillea_crown_detail_fade(camera_distance)
    }
    support := plants.Support_Surface {
        width   = max(structure.width, f32(1)),
        height  = max(vine_height, f32(1)),
        plane_z = surface_z,
        root_x  = 0,
    }
    skeleton_detail :=
        detail_tier >= 2 ? plants.Detail_Level.Near : detail_tier == 1 ? plants.Detail_Level.Medium : plants.Detail_Level.Far
    skeleton_entry := generated_plant_cached(
        .Bougainvillea,
        u64(plant_seed),
        skeleton_detail,
        .Wall_Trained,
        &support,
        vine_maturity,
    )
    uncached_skeleton: plants.Generate_Result
    skeleton: ^plants.Generate_Result
    if skeleton_entry != nil {
        skeleton = &skeleton_entry.result
    } else {
        // Preserve rendering if the fixed-capacity world cache is exhausted.
        uncached_skeleton = plants.generate(
            {
                species = .Bougainvillea,
                seed = u64(plant_seed),
                maturity = vine_maturity,
                detail = skeleton_detail,
                habit = .Wall_Trained,
                support = &support,
            },
        )
        skeleton = &uncached_skeleton
    }
    defer if skeleton_entry == nil do plants.destroy(&uncached_skeleton)
    root_scale := .78 + vine_maturity * .42
    stem_start := structure.base_y + .12 + f32(seed % 5) * .28
    planter_rooted := false
    mixed_use_planter := false
    if structure.kind == .Architecture {
        planter_rooted = architecture.bougainvillea_planter_rooted(plant_seed)
        if architecture.architecture_resolve_legacy_identity(structure).archetype == .Mixed_Use_Dwelling {
            planter_rooted = true
            mixed_use_planter = true
            root_scale = max(root_scale, f32(1.42))
        }
        stem_start = structure.base_y + (planter_rooted ? .50 * root_scale : .12)
    }
    stem_end := min(structure.base_y + vine_height, structure.base_y + structure.height * .86)
    if stem_end <= stem_start + .2 do return
    vine_points: [16]third_person.Vec3
    vine_local_x: [16]f32
    previous_x := local_x
    previous_y := stem_start - structure.base_y
    previous_delta := f32(0)
    for point_index in 0 ..< len(vine_points) {
        t := f32(point_index) / f32(len(vine_points) - 1)
        sway := f32(math.sin(f64(f32(seed) * .013 + t * 5.7))) * structure.width * (.025 + t * .055)
        drift := f32(math.cos(f64(f32(seed) * .021 + t * 4.1))) * (.16 + t * .08)
        if structure.kind == .Architecture {
            divergence := t * t * (3 - 2 * t)
            trained_x := root_local_x + (local_x - root_local_x) * divergence
            if skeleton.error == .None {
                proposed := plants.main_leader_sample(&skeleton.plant, t)
                proposed_offset := (proposed[0] - support.root_x) / max(support.width, f32(1))
                trained_x += proposed_offset * structure.width * divergence * .35
            }
            sway = trained_x - local_x + sway * divergence
        }
        local_y := stem_start + (stem_end - stem_start) * t - structure.base_y
        routed_x := world_climbing_leaf_route_x(
            structure,
            local_x + sway,
            previous_x,
            previous_y,
            previous_delta,
            local_y,
        )
        vine_local_x[point_index] = routed_x
        previous_delta = routed_x - previous_x
        previous_x = routed_x
        previous_y = local_y
        point_x, point_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            routed_x,
            surface_z + drift,
            structure.rotation,
        )
        vine_points[point_index] = {point_x, structure.base_y + local_y, point_z}
    }
    if structure.kind == .Architecture {
        for _ in 0 ..< 2 {
            smoothed_points := vine_points
            smoothed_local_x := vine_local_x
            for point_index in 1 ..< len(vine_points) - 1 {
                candidate_x :=
                    vine_local_x[point_index - 1] * .25 +
                    vine_local_x[point_index] * .50 +
                    vine_local_x[point_index + 1] * .25
                candidate_y := vine_points[point_index].y - structure.base_y
                left_mid_x := (vine_local_x[point_index - 1] + candidate_x) * .5
                left_mid_y := (vine_points[point_index - 1].y + vine_points[point_index].y) * .5 - structure.base_y
                right_mid_x := (candidate_x + vine_local_x[point_index + 1]) * .5
                right_mid_y := (vine_points[point_index].y + vine_points[point_index + 1].y) * .5 - structure.base_y
                candidate_badness := world_climbing_leaf_stem_opening_badness(structure, candidate_x, candidate_y)
                segment_badness := max(
                    world_climbing_leaf_stem_opening_badness(structure, left_mid_x, left_mid_y),
                    world_climbing_leaf_stem_opening_badness(structure, right_mid_x, right_mid_y),
                )
                if max(candidate_badness, segment_badness) < .42 {
                    smoothed_local_x[point_index] = candidate_x
                    smoothed_points[point_index].x =
                        vine_points[point_index - 1].x * .25 +
                        vine_points[point_index].x * .50 +
                        vine_points[point_index + 1].x * .25
                    smoothed_points[point_index].z =
                        vine_points[point_index - 1].z * .25 +
                        vine_points[point_index].z * .50 +
                        vine_points[point_index + 1].z * .25
                }
            }
            vine_points = smoothed_points
            vine_local_x = smoothed_local_x
        }
    }
    if structure.kind == .Architecture && render_root {
        root := vine_points[0]
        if planter_rooted {
            pottery := plant_seed % 2 == 0 ? canvas2d.Color{177, 92, 57, 255} : canvas2d.Color{156, 79, 53, 255}
            foot_color := plant_seed % 2 == 0 ? canvas2d.Color{139, 70, 47, 255} : canvas2d.Color{124, 62, 44, 255}
            if mixed_use_planter {
                pottery = plant_seed % 2 == 0 ? canvas2d.Color{196, 105, 65, 255} : canvas2d.Color{181, 91, 59, 255}
                foot_color = plant_seed % 2 == 0 ? canvas2d.Color{157, 77, 49, 255} : canvas2d.Color{145, 69, 46, 255}
            }
            pottery_lip := formation_face_color(pottery, .35, 0)
            world_box_rotated(
                {root.x, structure.base_y + .025 * root_scale, root.z},
                {.76 * root_scale, .05 * root_scale, .62 * root_scale},
                structure.rotation,
                foot_color,
            )
            world_tapered_box_rotated(
                {root.x, structure.base_y + .22 * root_scale, root.z},
                .40 * root_scale,
                .48 * root_scale,
                .38 * root_scale,
                .64 * root_scale,
                .50 * root_scale,
                structure.rotation,
                pottery,
            )
            world_box_rotated(
                {root.x, structure.base_y + .43 * root_scale, root.z},
                {.70 * root_scale, .12 * root_scale, .56 * root_scale},
                structure.rotation,
                pottery_lip,
            )
            world_box_rotated(
                {root.x, structure.base_y + .495 * root_scale, root.z},
                {.56 * root_scale, .025 * root_scale, .42 * root_scale},
                structure.rotation,
                {72, 55, 37, 255},
            )
            root_wood := color_lerp({151, 111, 72, 255}, {132, 91, 58, 255}, vine_maturity)
            root_crown := third_person.Vec3{root.x, structure.base_y + .502 * root_scale, root.z}
            world_ellipsoid_rotated(
                root_crown,
                (.070 + vine_maturity * .032) * root_scale,
                (.052 + vine_maturity * .024) * root_scale,
                (.060 + vine_maturity * .020) * root_scale,
                structure.rotation,
                root_wood,
            )
            if detail_tier >= 2 {
                for root_index in 0 ..< 3 {
                    root_angle := structure.rotation + (f32(root_index) - 1) * .82 + f32(plant_seed % 5) * .06
                    root_reach := (.12 + f32(root_index % 2) * .035) * root_scale
                    root_tip := third_person.Vec3 {
                        root.x + f32(math.cos(f64(root_angle))) * root_reach,
                        structure.base_y + .508 * root_scale,
                        root.z + f32(math.sin(f64(root_angle))) * root_reach,
                    }
                    world_tube_between(
                        root_crown,
                        root_tip,
                        {0, 1, 0},
                        (.040 + vine_maturity * .012) * root_scale,
                        .018 * root_scale,
                        root_wood,
                    )
                }
            }
        } else {
            world_tapered_box_rotated(
                {root.x, structure.base_y + .035, root.z},
                .07,
                .72 * root_scale,
                .46 * root_scale,
                .58 * root_scale,
                .36 * root_scale,
                structure.rotation,
                {76, 60, 40, 255},
            )
            for root_index in 0 ..< 3 {
                angle := structure.rotation + (f32(root_index) - 1) * .72
                root_tip := third_person.Vec3 {
                    root.x + math.cos(angle) * (.22 + f32(root_index) * .035) * root_scale,
                    structure.base_y + .075,
                    root.z + math.sin(angle) * (.22 + f32(root_index) * .035) * root_scale,
                }
                world_tube_between(
                    {root.x, structure.base_y + .13, root.z},
                    root_tip,
                    {0, 1, 0},
                    .045 * root_scale,
                    .025 * root_scale,
                    {112, 78, 50, 255},
                )
            }
        }
        fallen_count := architecture.bougainvillea_fallen_bract_count(vine_maturity)
        if fallen_count > 0 && detail_tier >= 2 {
            palette_color := architecture.bougainvillea_bract_color(architecture.bougainvillea_palette(plant_seed))
            bract_color := canvas2d.Color{palette_color[0], palette_color[1], palette_color[2], palette_color[3]}
            base_radius := planter_rooted ? .46 * root_scale : .20 * root_scale
            for fallen in 0 ..< fallen_count {
                angle := f32(plant_seed % 29) * .31 + f32(fallen) * 2.399963
                radius := base_radius + f32(fallen % 3) * .10 * root_scale
                direction_x, direction_z := f32(math.cos(f64(angle))), f32(math.sin(f64(angle)))
                tangent_x, tangent_z := -direction_z, direction_x
                center := third_person.Vec3 {
                    root.x + direction_x * radius,
                    structure.base_y + .018 + f32(fallen % 2) * .003,
                    root.z + direction_z * radius,
                }
                bract_length := (.055 + f32(fallen % 2) * .014) * root_scale
                bract_width := bract_length * .58
                tip := third_person.Vec3 {
                    center.x + direction_x * bract_length,
                    center.y,
                    center.z + direction_z * bract_length,
                }
                left := third_person.Vec3 {
                    center.x - direction_x * bract_length * .52 - tangent_x * bract_width,
                    center.y,
                    center.z - direction_z * bract_length * .52 - tangent_z * bract_width,
                }
                right := third_person.Vec3 {
                    center.x - direction_x * bract_length * .52 + tangent_x * bract_width,
                    center.y,
                    center.z - direction_z * bract_length * .52 + tangent_z * bract_width,
                }
                tone := f32(fallen % 3) * .06
                fallen_color := color_lerp(bract_color, {239, 188, 157, 255}, tone)
                world_triangle(tip, left, right, fallen_color)
                world_triangle(tip, right, left, fallen_color)
            }
        }
    }
    woody_color := canvas2d.Color{62, 108, 55, 255}
    woody_base_radius := f32(.055)
    woody_tip_radius := f32(.040)
    if structure.kind == .Architecture {
        wood_age := clamp((vine_maturity - .06) / .50, 0, 1)
        wood_age = wood_age * wood_age * (3 - 2 * wood_age)
        woody_color = color_lerp({78, 105, 63, 255}, {126, 91, 59, 255}, wood_age)
        woody_base_radius = .044 + vine_maturity * .030
        woody_tip_radius = .030 + vine_maturity * .012
    }
    secondary_strength := f32(0)
    facade_right_x, facade_right_z := f32(0), f32(0)
    facade_out_x, facade_out_z := f32(0), f32(0)
    if structure.kind == .Architecture {
        facade_right_x, facade_right_z = world_rotate_xz(0, 0, 1, 0, structure.rotation)
        facade_out_x, facade_out_z = world_rotate_xz(0, 0, 0, 1, structure.rotation)
        if render_root {
            secondary_strength = architecture.bougainvillea_secondary_leader_strength(vine_maturity)
        }
    }
    for point_index in 0 ..< len(vine_points) - 1 {
        segment_t := f32(point_index) / f32(len(vine_points) - 1)
        start_x := vine_local_x[point_index]
        end_x := vine_local_x[point_index + 1]
        middle_x := (start_x + end_x) * .5
        start_badness := world_climbing_leaf_stem_opening_badness(
            structure,
            start_x,
            vine_points[point_index].y - structure.base_y,
        )
        end_badness := world_climbing_leaf_stem_opening_badness(
            structure,
            end_x,
            vine_points[point_index + 1].y - structure.base_y,
        )
        middle_badness := world_climbing_leaf_stem_opening_badness(
            structure,
            middle_x,
            (vine_points[point_index].y + vine_points[point_index + 1].y) * .5 - structure.base_y,
        )
        needs_detour := max(start_badness, max(end_badness, middle_badness)) > .68
        segment_radius := woody_base_radius + (woody_tip_radius - woody_base_radius) * segment_t
        bark_value := .035 + f32((point_index + int(seed)) % 3) * .035
        segment_color :=
            point_index % 2 == 0 ? color_lerp(woody_color, {171, 128, 84, 255}, bark_value) : color_lerp(woody_color, {77, 55, 42, 255}, bark_value)
        if needs_detour {
            start_local_y := vine_points[point_index].y - structure.base_y
            end_local_y := vine_points[point_index + 1].y - structure.base_y
            detour_x := world_climbing_leaf_segment_detour_x(structure, start_x, start_local_y, end_x, end_local_y)
            detour := third_person.Vec3 {
                (vine_points[point_index].x + vine_points[point_index + 1].x) * .5,
                (vine_points[point_index].y + vine_points[point_index + 1].y) * .5,
                (vine_points[point_index].z + vine_points[point_index + 1].z) * .5,
            }
            detour.x += facade_right_x * (detour_x - middle_x) + facade_out_x * .08
            detour.z += facade_right_z * (detour_x - middle_x) + facade_out_z * .08
            middle_radius := segment_radius * .955
            world_tube_between(
                vine_points[point_index],
                detour,
                {0, 1, 0},
                segment_radius,
                middle_radius,
                segment_color,
            )
            world_tube_between(
                detour,
                vine_points[point_index + 1],
                {0, 1, 0},
                middle_radius,
                segment_radius * .91,
                segment_color,
            )
        } else {
            world_tube_between(
                vine_points[point_index],
                vine_points[point_index + 1],
                {0, 1, 0},
                segment_radius,
                segment_radius * .91,
                segment_color,
            )
        }
        if secondary_strength > 0 {
            start_t := f32(point_index) / f32(len(vine_points) - 1)
            finish_t := f32(point_index + 1) / f32(len(vine_points) - 1)
            start_envelope := f32(math.sin(f64(start_t * math.PI)))
            finish_envelope := f32(math.sin(f64(finish_t * math.PI)))
            weave_amplitude := (.075 + vine_maturity * .085) * secondary_strength
            start_weave :=
                f32(math.sin(f64(f32(seed) * .071 + start_t * math.PI * 4.4))) * weave_amplitude * start_envelope
            finish_weave :=
                f32(math.sin(f64(f32(seed) * .071 + finish_t * math.PI * 4.4))) * weave_amplitude * finish_envelope
            start_depth := f32(math.cos(f64(f32(seed) * .071 + start_t * math.PI * 4.4))) * .045 * start_envelope
            finish_depth := f32(math.cos(f64(f32(seed) * .071 + finish_t * math.PI * 4.4))) * .045 * finish_envelope
            secondary_start_local_x := start_x + start_weave
            secondary_finish_local_x := end_x + finish_weave
            secondary_middle_x := (secondary_start_local_x + secondary_finish_local_x) * .5
            secondary_badness := max(
                world_climbing_leaf_stem_opening_badness(
                    structure,
                    secondary_start_local_x,
                    vine_points[point_index].y - structure.base_y,
                ),
                max(
                    world_climbing_leaf_stem_opening_badness(
                        structure,
                        secondary_finish_local_x,
                        vine_points[point_index + 1].y - structure.base_y,
                    ),
                    world_climbing_leaf_stem_opening_badness(
                        structure,
                        secondary_middle_x,
                        (vine_points[point_index].y + vine_points[point_index + 1].y) * .5 - structure.base_y,
                    ),
                ),
            )
            if secondary_badness <= .68 {
                secondary_start := vine_points[point_index]
                secondary_start.x += facade_right_x * start_weave + facade_out_x * start_depth
                secondary_start.z += facade_right_z * start_weave + facade_out_z * start_depth
                secondary_finish := vine_points[point_index + 1]
                secondary_finish.x += facade_right_x * finish_weave + facade_out_x * finish_depth
                secondary_finish.z += facade_right_z * finish_weave + facade_out_z * finish_depth
                secondary_radius := segment_radius * (.50 + secondary_strength * .12)
                secondary_color := color_lerp(segment_color, {76, 52, 39, 255}, .18)
                world_tube_between(
                    secondary_start,
                    secondary_finish,
                    {0, 1, 0},
                    secondary_radius,
                    secondary_radius * .88,
                    secondary_color,
                )
            }
        }
        if structure.kind == .Architecture &&
           detail_tier >= 2 &&
           point_index > 0 &&
           point_index % 3 == 2 &&
           start_badness < .42 {
            anchor_x, anchor_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                start_x,
                structure.depth * .5 + .07,
                structure.rotation,
            )
            anchor := third_person.Vec3{anchor_x, vine_points[point_index].y, anchor_z}
            guide_half_span := .24 + vine_maturity * .22
            guide_local_y := anchor.y - structure.base_y
            guide_left_x := start_x - guide_half_span
            guide_right_x := start_x + guide_half_span
            guide_badness := max(
                world_climbing_leaf_stem_opening_badness(structure, guide_left_x, guide_local_y),
                max(
                    world_climbing_leaf_stem_opening_badness(structure, start_x, guide_local_y),
                    world_climbing_leaf_stem_opening_badness(structure, guide_right_x, guide_local_y),
                ),
            )
            if guide_badness < .42 {
                guide_left_world_x, guide_left_world_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    guide_left_x,
                    structure.depth * .5 + .065,
                    structure.rotation,
                )
                guide_right_world_x, guide_right_world_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    guide_right_x,
                    structure.depth * .5 + .065,
                    structure.rotation,
                )
                world_tube_between(
                    {guide_left_world_x, anchor.y, guide_left_world_z},
                    {guide_right_world_x, anchor.y, guide_right_world_z},
                    {0, 1, 0},
                    .011,
                    .011,
                    {76, 78, 72, 255},
                )
            }
            world_tube_between(anchor, vine_points[point_index], {0, 1, 0}, .018, .018, {117, 96, 67, 255})
            world_box_rotated({anchor.x, anchor.y, anchor.z}, {.11, .11, .045}, structure.rotation, {72, 74, 68, 255})
        }
    }
    if structure.kind == .Architecture && render_root {
        basal_count := architecture.bougainvillea_basal_shoot_count(vine_maturity)
        basal_indices := [2]int{1, 3}
        root_side := root_local_x < 0 ? f32(-1) : f32(1)
        for basal in 0 ..< basal_count {
            point_index := basal_indices[basal]
            node := vine_points[point_index]
            node_local_x := vine_local_x[point_index]
            reach := structure.width * (.022 + f32(basal) * .006)
            shoot_local_x := node_local_x + root_side * reach
            shoot_local_y := node.y - structure.base_y + .16 + f32(basal) * .08
            if world_climbing_leaf_stem_opening_badness(structure, shoot_local_x, shoot_local_y) > .48 {
                continue
            }
            shoot_x, shoot_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                shoot_local_x,
                surface_z + .18,
                structure.rotation,
            )
            shoot_end := third_person.Vec3{shoot_x, structure.base_y + shoot_local_y, shoot_z}
            basal_color := color_lerp({73, 103, 61, 255}, {105, 74, 51, 255}, vine_maturity)
            world_tube_between(
                node,
                shoot_end,
                {0, 1, 0},
                .027 + vine_maturity * .009,
                .018 + vine_maturity * .005,
                basal_color,
            )
            card_width := (.58 + vine_maturity * .18) * (1 - f32(basal) * .10)
            card_height := card_width * .82
            card_center := shoot_end
            card_center.y += card_height * .30
            footprint_clear := true
            for footprint_x in -1 ..= 1 {
                for footprint_y in 0 ..= 2 {
                    sample_x := shoot_local_x + f32(footprint_x) * card_width * .31
                    sample_y := shoot_local_y + f32(footprint_y) * card_height * .28
                    if world_climbing_leaf_stem_opening_badness(structure, sample_x, sample_y) > .48 {
                        footprint_clear = false
                    }
                }
            }
            if footprint_clear {
                tile := int((plant_seed + u32(basal * 11)) % 2) * 2
                roll := root_side * (.018 + f32(basal) * .007)
                world_bougainvillea_card(card_center, card_width, card_height, tile, root_side < 0, roll, .93, true)
            }
        }
    }
    if structure.kind == .Architecture && detail_tier >= 2 && vine_maturity > .38 {
        thorn_indices := [4]int{4, 7, 10, 13}
        thorn_count := architecture.bougainvillea_thorn_count(vine_maturity, len(thorn_indices))
        thorn_facade_right_x, thorn_facade_right_z := world_rotate_xz(0, 0, 1, 0, structure.rotation)
        thorn_facade_out_x, thorn_facade_out_z := world_rotate_xz(0, 0, 0, 1, structure.rotation)
        for thorn in 0 ..< thorn_count {
            point_index := thorn_indices[len(thorn_indices) - thorn_count + thorn]
            thorn_local_y := vine_points[point_index].y - structure.base_y
            if world_climbing_leaf_stem_opening_badness(structure, vine_local_x[point_index], thorn_local_y) > .48 {
                continue
            }
            side := ((thorn + int(seed)) & 1) == 0 ? f32(1) : f32(-1)
            thorn_length := .11 + vine_maturity * .07 + f32(thorn % 2) * .025
            root := vine_points[point_index]
            bend := third_person.Vec3 {
                root.x + thorn_facade_right_x * side * thorn_length * .68 + thorn_facade_out_x * .045,
                root.y + thorn_length * .32,
                root.z + thorn_facade_right_z * side * thorn_length * .68 + thorn_facade_out_z * .045,
            }
            tip := third_person.Vec3 {
                bend.x + thorn_facade_right_x * side * thorn_length * .32 + thorn_facade_out_x * .025,
                bend.y - thorn_length * .24,
                bend.z + thorn_facade_right_z * side * thorn_length * .32 + thorn_facade_out_z * .025,
            }
            thorn_color := color_lerp({84, 111, 64, 255}, {112, 77, 51, 255}, vine_maturity)
            thorn_radius := .007 + vine_maturity * .005
            world_tube_between(root, bend, {0, 1, 0}, thorn_radius, thorn_radius * .62, thorn_color)
            world_tube_between(bend, tip, {0, 1, 0}, thorn_radius * .62, .0015, thorn_color)
        }
    }
    if structure.kind == .Architecture && detail_tier >= 2 {
        stub_indices := [3]int{5, 8, 11}
        stub_count := architecture.bougainvillea_pruned_stub_count(vine_maturity)
        stub_facade_right_x, stub_facade_right_z := world_rotate_xz(0, 0, 1, 0, structure.rotation)
        stub_facade_out_x, stub_facade_out_z := world_rotate_xz(0, 0, 0, 1, structure.rotation)
        for stub in 0 ..< stub_count {
            point_index := stub_indices[stub]
            node := vine_points[point_index]
            node_local_x := vine_local_x[point_index]
            side := (stub + int(seed)) % 2 == 0 ? f32(1) : f32(-1)
            stub_length := .13 + f32(stub) * .025 + vine_maturity * .035
            tip := third_person.Vec3 {
                node.x + stub_facade_right_x * side * stub_length + stub_facade_out_x * .025,
                node.y + .055 + f32(stub % 2) * .025,
                node.z + stub_facade_right_z * side * stub_length + stub_facade_out_z * .025,
            }
            tip_local_x := node_local_x + side * stub_length
            if max(
                   world_climbing_leaf_stem_opening_badness(structure, node_local_x, node.y - structure.base_y),
                   world_climbing_leaf_stem_opening_badness(structure, tip_local_x, tip.y - structure.base_y),
               ) >
               .48 {
                continue
            }
            stub_radius := (.025 + vine_maturity * .009) * (1 - f32(stub) * .08)
            stub_color := color_lerp({104, 76, 52, 255}, {128, 91, 59, 255}, vine_maturity)
            world_tube_between(node, tip, {0, 1, 0}, stub_radius, stub_radius * .84, stub_color)
            cut_color := color_lerp({185, 143, 91, 255}, {220, 181, 119, 255}, vine_maturity)
            world_ellipsoid_rotated(
                tip,
                stub_radius * .93,
                stub_radius * .82,
                stub_radius * .34,
                structure.rotation,
                cut_color,
            )
        }
    }
    if structure.kind == .Architecture && vine_maturity > .28 {
        renewal_indices := [4]int{4, 6, 8, 10}
        renewal_count := min(1 + int((vine_maturity - .28) * 3.0), len(renewal_indices))
        for renewal in 0 ..< renewal_count {
            point_index := renewal_indices[len(renewal_indices) - renewal_count + renewal]
            node := vine_points[point_index]
            node_x := vine_local_x[point_index]
            side := node_x >= 0 ? f32(1) : f32(-1)
            reach := structure.width * (.024 + f32(renewal % 2) * .007)
            shoot_local_x := node_x + side * reach
            shoot_y := node.y + .20 + f32(renewal % 2) * .10
            if world_climbing_leaf_stem_opening_badness(structure, shoot_local_x, shoot_y - structure.base_y) > .52 {
                continue
            }
            shoot_x, shoot_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                shoot_local_x,
                surface_z + .16,
                structure.rotation,
            )
            shoot_end := third_person.Vec3{shoot_x, shoot_y, shoot_z}
            world_tube_between(
                node,
                shoot_end,
                {0, 1, 0},
                .030 + vine_maturity * .010,
                .021 + vine_maturity * .006,
                color_lerp({73, 103, 61, 255}, {105, 74, 51, 255}, vine_maturity),
            )
            card_width := (.62 + vine_maturity * .28) * (1 - f32(renewal) * .07)
            card_height := card_width * .76
            card_center := third_person.Vec3{shoot_end.x, shoot_end.y + card_height * .28, shoot_end.z}
            footprint_clear := true
            for footprint_x in -1 ..= 1 {
                for footprint_y in 0 ..= 2 {
                    sample_x := shoot_local_x + f32(footprint_x) * card_width * .30
                    sample_y := card_center.y - structure.base_y + f32(footprint_y - 1) * card_height * .28
                    if world_climbing_leaf_stem_opening_badness(structure, sample_x, sample_y) > .52 {
                        footprint_clear = false
                    }
                }
            }
            if footprint_clear {
                tile := int((seed + u32(renewal * 5)) % 4)
                tile -= tile % 2
                renewal_roll := f32(int((seed + u32(renewal * 17)) % 7) - 3) * .014
                world_bougainvillea_card(card_center, card_width, card_height, tile, side < 0, renewal_roll, .94, true)
            }
        }
    }
    world_climbing_leaf_crown(
        {
            structure,
            vine_points,
            vine_local_x,
            vine_maturity,
            stem_end,
            seed,
            plant_seed,
            crown_detail_fade,
            mixed_use_storefront,
            surface_z,
            growth_density,
        },
    )
}
