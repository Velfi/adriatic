package tests

import architecture "../packages/architecture"
import buildings "../packages/buildings"
import roads "../packages/roads"
import terrain "../packages/terrain"
import "core:math"
import "core:testing"

@(test)
adriatic_graph_is_seed_stable_and_has_a_landmark :: proc(t: ^testing.T) {
    first := architecture.adriatic_graph(100, 200, 0xA71D3)
    second := architecture.adriatic_graph(100, 200, 0xA71D3)
    testing.expect(t, first.count == second.count)
    testing.expect(t, first.count >= 13)
    testing.expect(t, first.nodes[first.count - 1].kind == .Landmark)
    testing.expect(t, first.nodes[first.count - 1].z < 200)
    for index in 0 ..< first.count {
        testing.expect(t, first.nodes[index].x == second.nodes[index].x)
        testing.expect(t, first.nodes[index].height == second.nodes[index].height)
    }
}

@(test)
architecture_palette_keeps_landmark_distinct :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    architecture.generate_append(project, 1300, 1300, 0xA71D3)
    found_landmark := false
    found_variant := false
    for structure in project.structures[:project.structure_count] {
        if structure.height > 60 {
            found_landmark = structure.color == [4]u8{224, 219, 196, 255}
        } else if structure.color[0] != 214 {
            found_variant = true
        }
    }
    testing.expect(t, found_landmark)
    testing.expect(t, found_variant)
}

@(test)
architecture_palette_has_legible_seed_variants :: proc(t: ^testing.T) {
    first := architecture.architecture_color(0)
    second := architecture.architecture_color(1)
    third := architecture.architecture_color(2)
    fourth := architecture.architecture_color(3)
    testing.expect(t, first[0] != second[0] || first[1] != second[1])
    testing.expect(t, second[0] != third[0] || second[1] != third[1])
    testing.expect(t, third[0] != fourth[0] || third[1] != fourth[1])
    testing.expect(t, architecture.architecture_color(7)[0] == fourth[0])
}

@(test)
architecture_roof_palette_has_seed_variants :: proc(t: ^testing.T) {
    first := architecture.architecture_roof_color(0)
    second := architecture.architecture_roof_color(1)
    third := architecture.architecture_roof_color(2)
    fourth := architecture.architecture_roof_color(3)
    testing.expect(t, first != second)
    testing.expect(t, second != third)
    testing.expect(t, third != fourth)
    testing.expect(t, architecture.architecture_roof_color(8) == first)
    testing.expect(t, architecture.architecture_roof_color(8, true) == [4]u8{177, 92, 63, 255})
}

@(test)
architecture_roof_tiles_vary_by_seed_and_tone :: proc(t: ^testing.T) {
    testing.expect(
        t,
        architecture.architecture_roof_tile_color(0, 0) != architecture.architecture_roof_tile_color(1, 0),
    )
    testing.expect(
        t,
        architecture.architecture_roof_tile_color(0, 0) != architecture.architecture_roof_tile_color(0, 1),
    )
    testing.expect(
        t,
        architecture.architecture_roof_tile_color(8, 0) == architecture.architecture_roof_tile_color(0, 0),
    )
    testing.expect(
        t,
        architecture.architecture_roof_tile_color(0, 7) == architecture.architecture_roof_tile_color(0, 2),
    )
}

@(test)
architecture_roof_tile_weathering_is_stable_and_mid_tone_weighted :: proc(t: ^testing.T) {
    counts: [5]int
    changed_with_seed := false
    for course in 0 ..< 16 {
        for segment in 0 ..< 16 {
            tone := architecture.architecture_roof_tile_tone(0x8128, course, segment)
            testing.expect(t, tone >= 0 && tone < len(counts))
            counts[tone] += 1
            if tone != architecture.architecture_roof_tile_tone(0x8129, course, segment) {
                changed_with_seed = true
            }
            testing.expect_value(t, architecture.architecture_roof_tile_tone(0x8128, course, segment), tone)
        }
    }
    for count in counts do testing.expect(t, count > 0)
    testing.expect(t, counts[2] > counts[1])
    testing.expect(t, counts[2] > counts[4])
    testing.expect(t, changed_with_seed)
}

@(test)
architecture_generation_rejects_sea_level_sites :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    created := architecture.generate_append(project, 0, 0, 0xA71D3)
    testing.expect(t, created == 0)
    testing.expect(t, project.structure_count == 0)
}

@(test)
architecture_append_generation_keeps_both_island_towns :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    west_x, west_z := terrain.default_town_center(-1)
    east_x, east_z := terrain.default_town_center(1)
    first_created := architecture.generate_append(project, west_x, west_z, 0xA71D3)
    second_created := architecture.generate_append(project, east_x, east_z, 0xD911C)
    testing.expect(t, first_created >= 12)
    testing.expect(t, second_created >= 12)
    testing.expect(t, project.structure_count == first_created + second_created)

    negative_town, positive_town := 0, 0
    for structure in project.structures[:project.structure_count] {
        if structure.kind != .Architecture do continue
        if structure.center_x < 0 do negative_town += 1
        if structure.center_x > 0 do positive_town += 1
    }
    testing.expect(t, negative_town == first_created)
    testing.expect(t, positive_town == second_created)
}

@(test)
legacy_architecture_generation_does_not_add_phantom_circulation :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)

    for index in 0 ..< 6 {
        structure := terrain.structure_make(f32(index % 3) * 20, f32(index / 3) * 20, 12, 10, 0, 18)
        structure.kind = .Architecture
        _ = terrain.add_structure(project, structure)
    }

    plan := architecture.circulation_plan(project)
    testing.expect_value(t, plan.count, 0)
}

@(test)
architecture_append_density_removes_buildings_without_scaling_survivors :: proc(t: ^testing.T) {
    full := terrain.new_project()
    sparse := terrain.new_project()
    defer terrain.free_project(full)
    defer terrain.free_project(sparse)
    full_created := architecture.generate_append(full, 1300, 1418, 0xA71D3)
    sparse_created := architecture.generate_append(sparse, 1300, 1418, 0xA71D3, .52)
    testing.expect(t, sparse_created >= 4)
    testing.expect(t, sparse_created < full_created)

    lowered_height := false
    for sparse_structure in sparse.structures[:sparse.structure_count] {
        matched := false
        for full_structure in full.structures[:full.structure_count] {
            if sparse_structure.center_x != full_structure.center_x ||
               sparse_structure.center_z != full_structure.center_z {
                continue
            }
            testing.expect(t, sparse_structure.width == full_structure.width)
            testing.expect(t, sparse_structure.depth == full_structure.depth)
            testing.expect(t, sparse_structure.height <= full_structure.height)
            if sparse_structure.height <= 22.2 && sparse_structure.height <= 60 {
                testing.expect(t, sparse_structure.seed % 5 == 0)
            }
            if sparse_structure.height < full_structure.height do lowered_height = true
            matched = true
            break
        }
        testing.expect(t, matched)
    }
    testing.expect(t, lowered_height)
}

@(test)
architecture_roof_styles_are_seed_stable :: proc(t: ^testing.T) {
    testing.expect(t, architecture.roof_style_for_seed(0) == .Gable)
    testing.expect(t, architecture.roof_style_for_seed(1) == .Low_Gable)
    testing.expect(t, architecture.roof_style_for_seed(2) == .Hip)
    testing.expect(t, architecture.roof_style_for_seed(3) == .Parapet)
    testing.expect(t, architecture.roof_style_for_seed(7) == architecture.roof_style_for_seed(3))
}

@(test)
architecture_facade_styles_are_decoupled_and_reproducible :: proc(t: ^testing.T) {
    variants: [4]bool
    for seed in 0 ..< 16 {
        style := architecture.facade_style_for_seed(u32(seed))
        testing.expect(t, style >= 0 && style < 4)
        testing.expect(t, style == architecture.facade_style_for_seed(u32(seed)))
        variants[style] = true
    }
    for variant in variants {
        testing.expect(t, variant)
    }
    testing.expect(t, architecture.facade_style_for_seed(0) != int(architecture.roof_style_for_seed(0)))
}

@(test)
architecture_chimney_variation_is_sparse_and_seed_stable :: proc(t: ^testing.T) {
    chimney_count := 0
    for seed in 0 ..< 12 {
        if architecture.architecture_has_chimney(u32(seed)) do chimney_count += 1
        testing.expect(t, architecture.architecture_has_chimney(u32(seed)) == (seed % 3 == 0))
    }
    testing.expect(t, chimney_count == 4)
}

@(test)
architecture_accent_sites_respect_rotated_building_footprints :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    building := terrain.structure_make(100, 200, 30, 18, 4, 24)
    building.kind = .Architecture
    building.rotation = math.PI / 4
    _ = terrain.add_structure(project, building)

    testing.expect(t, !architecture.city_accent_site_clear(project, 100, 200, 5))
    testing.expect(t, !architecture.city_accent_site_clear(project, 114, 214, 5))
    testing.expect(t, architecture.city_accent_site_clear(project, 130, 230, 5))
}

@(test)
architecture_facade_floor_count_tracks_height :: proc(t: ^testing.T) {
    testing.expect(t, architecture.facade_floor_count(18) == 4)
    testing.expect(t, architecture.facade_floor_count(33) == 7)
    testing.expect(t, architecture.facade_floor_count(50) == 10)
    testing.expect(t, architecture.facade_floor_count(80) == 16)
    testing.expect(t, math.abs(architecture.facade_window_row_y(50, 0) - 2.55) < .001)
    testing.expect(t, math.abs(architecture.facade_window_row_y(50, 9) - 47.45) < .001)
    low_rise_window_height := architecture.facade_window_height(11)
    low_rise_window_y := architecture.facade_window_row_y(11, 0)
    testing.expect(t, low_rise_window_height == 1.55)
    testing.expect(t, math.abs(low_rise_window_y - low_rise_window_height * .5 - 1.45) < .001)
    testing.expect(t, architecture.facade_floor_count(4.8) == 1)
    testing.expect(t, architecture.facade_floor_count(9.6) == 2)
    testing.expect(t, architecture.facade_floor_count(14.4) == 3)
    testing.expect(t, architecture.facade_fitted_height(9) == 9.6)
    testing.expect(t, architecture.facade_fitted_height(18) == 19.2)
    testing.expect(
        t,
        architecture.facade_floor_count(architecture.facade_fitted_height(33)) == architecture.facade_floor_count(33),
    )
    testing.expect(
        t,
        architecture.facade_fitted_height(architecture.facade_fitted_height(33)) ==
        architecture.facade_fitted_height(33),
    )
    testing.expect(t, architecture.facade_fitted_height(64) == 64)
    testing.expect(t, architecture.facade_fitted_height_in_range(5, 4, 11) == 4.8)
    testing.expect(t, architecture.facade_fitted_height_in_range(10, 4, 11) == 9.6)
    testing.expect(t, architecture.facade_fitted_height_in_range(7, 5, 15) == 9.6)
    testing.expect(t, math.abs(architecture.facade_step_height(9.6, 1) - 14.4) < .001)
    testing.expect(t, math.abs(architecture.facade_step_height(14.4, -1) - 9.6) < .001)
    testing.expect(t, architecture.facade_column_count(12) == 2)
    testing.expect(t, architecture.facade_column_count(16) == 4)
    testing.expect(t, architecture.facade_column_count(24) == 4)
    testing.expect(t, architecture.facade_column_count(28) == 4)
    testing.expect(t, architecture.facade_column_count(32) == 4)
    testing.expect(t, architecture.facade_column_count(46) == 6)
    testing.expect(t, architecture.facade_window_column_x(24, 0) < 0)
    testing.expect(t, architecture.facade_window_column_x(24, 1) < 0)
    testing.expect(t, architecture.facade_window_column_x(24, 2) > 0)
    testing.expect(t, architecture.facade_window_column_x(32, 1) < 0)
    testing.expect(t, architecture.facade_window_column_x(32, 2) > 0)
    narrow_door_width := clamp(f32(16) * .13, f32(1.8), f32(2.8))
    narrow_window_width := architecture.facade_window_width(16)
    inner_window_x := architecture.facade_window_column_x(16, 1)
    testing.expect(t, -inner_window_x - narrow_window_width * .5 > narrow_door_width * .5)
}

@(test)
architecture_lighthouse_slits_follow_taper_and_clear_keeper_door :: proc(t: ^testing.T) {
    previous_height := f32(0)
    previous_radius := f32(2)
    for level in 0 ..< architecture.LIGHTHOUSE_SLIT_COUNT {
        height_fraction := architecture.lighthouse_slit_height_fraction(level)
        radius_scale := architecture.lighthouse_shaft_radius_scale(height_fraction)
        testing.expect(t, height_fraction > previous_height)
        testing.expect(t, radius_scale < previous_radius)
        previous_height = height_fraction
        previous_radius = radius_scale
    }
    minimum_tower_height: f32 = 14
    door_top: f32 = 2.70
    slit_half_height: f32 = 1.15 * .5
    first_slit_bottom := minimum_tower_height * architecture.lighthouse_slit_height_fraction(0) - slit_half_height
    testing.expectf(
        t,
        first_slit_bottom - door_top >= architecture.ARCHITECTURE_DOOR_WINDOW_MARGIN,
        "lighthouse slit crowds keeper door clearance=%.3f",
        first_slit_bottom - door_top,
    )
}

@(test)
architecture_frontage_rotation_faces_both_sides_toward_the_road :: proc(t: ^testing.T) {
    tangents := [2][2]f32{{1, 0}, {.6, .8}}
    sides := [2]f32{-1, 1}
    for tangent in tangents {
        normal_x, normal_z := -tangent[1], tangent[0]
        for side in sides {
            rotation := architecture.architecture_frontage_rotation(tangent[0], tangent[1], side)
            front_x := -f32(math.sin(f64(rotation)))
            front_z := f32(math.cos(f64(rotation)))
            roadward_x, roadward_z := -normal_x * side, -normal_z * side
            testing.expect(t, front_x * roadward_x + front_z * roadward_z > .999)
        }
    }
}

@(test)
bougainvillea_maturity_is_bounded_and_monotonic :: proc(t: ^testing.T) {
    testing.expect(t, architecture.bougainvillea_maturity(0) == 0)
    testing.expect(t, architecture.bougainvillea_maturity(.035) == 0)
    testing.expect(t, architecture.bougainvillea_maturity(.72) == 1)
    testing.expect(t, architecture.bougainvillea_maturity(1) == 1)

    previous := f32(-1)
    for step in 0 ..= 20 {
        maturity := architecture.bougainvillea_maturity(f32(step) / 20)
        testing.expect(t, maturity >= previous)
        testing.expect(t, maturity >= 0 && maturity <= 1)
        previous = maturity
    }
}

@(test)
bougainvillea_growth_controls_reach_and_branch_hierarchy :: proc(t: ^testing.T) {
    covered_palette_habits: [3][2]bool
    planter_examples, soil_examples := 0, 0
    validation_branch_nodes := [6]int{7, 9, 11, 13, 14, 15}
    for seed in architecture.BOUGAINVILLEA_VALIDATION_SEEDS {
        palette := architecture.bougainvillea_palette(seed)
        habit := architecture.bougainvillea_training_habit(seed)
        testing.expect(t, palette >= 0 && palette < 3)
        testing.expect(t, habit >= 0 && habit < 2)
        covered_palette_habits[palette][habit] = true
        if architecture.bougainvillea_planter_rooted(seed) {
            planter_examples += 1
        } else {
            soil_examples += 1
        }
        mature_blooms := 0
        for branch_index in 1 ..= 5 {
            node_fraction := f32(validation_branch_nodes[branch_index]) / 15
            if architecture.bougainvillea_branch_flowering(1, node_fraction, seed, branch_index) {
                mature_blooms += 1
            }
        }
        testing.expect(t, mature_blooms >= 1)
        testing.expect(t, mature_blooms <= 4)
    }
    for palette in 0 ..< 3 {
        for habit in 0 ..< 2 {
            testing.expect(t, covered_palette_habits[palette][habit])
        }
    }
    testing.expect(t, planter_examples == 3)
    testing.expect(t, soil_examples == 3)

    testing.expect(t, math.abs(architecture.bougainvillea_height_fraction(0) - .24) < .0001)
    testing.expect(t, math.abs(architecture.bougainvillea_height_fraction(1) - .84) < .0001)
    testing.expect(t, architecture.bougainvillea_active_branch_count(0, 6) == 2)
    testing.expect(t, architecture.bougainvillea_active_branch_count(.5, 6) == 4)
    testing.expect(t, architecture.bougainvillea_active_branch_count(1, 6) == 6)
    testing.expect(t, architecture.bougainvillea_active_branch_count(1, 3) == 3)
    testing.expect(t, architecture.bougainvillea_active_branch_count(1, 0) == 0)
    testing.expect(t, architecture.bougainvillea_thorn_count(.38, 4) == 0)
    testing.expect(t, architecture.bougainvillea_thorn_count(.39, 4) == 1)
    testing.expect(t, architecture.bougainvillea_thorn_count(1, 4) == 4)
    testing.expect(t, architecture.bougainvillea_thorn_count(1, 2) == 2)
    testing.expect(t, architecture.bougainvillea_thorn_count(1, 0) == 0)
    testing.expect(t, architecture.bougainvillea_fallen_bract_count(.62) == 0)
    testing.expect(t, architecture.bougainvillea_fallen_bract_count(.63) == 2)
    testing.expect(t, architecture.bougainvillea_fallen_bract_count(1) == 5)
    testing.expect(t, architecture.bougainvillea_cascade_count(.56) == 0)
    testing.expect(t, architecture.bougainvillea_cascade_count(.57) == 1)
    testing.expect(t, architecture.bougainvillea_cascade_count(.83) == 1)
    testing.expect(t, architecture.bougainvillea_cascade_count(.84) == 2)
    testing.expect(t, architecture.bougainvillea_secondary_leader_strength(.46) == 0)
    testing.expect(t, architecture.bougainvillea_secondary_leader_strength(.63) > 0)
    testing.expect(t, architecture.bougainvillea_secondary_leader_strength(.63) < 1)
    testing.expect(t, architecture.bougainvillea_secondary_leader_strength(.80) == 1)
    testing.expect(t, math.abs(architecture.bougainvillea_woody_compliance(0) - 1) < .0001)
    testing.expect(t, math.abs(architecture.bougainvillea_woody_compliance(.5) - .57) < .0001)
    testing.expect(t, math.abs(architecture.bougainvillea_woody_compliance(1) - .14) < .0001)
    testing.expect(t, architecture.bougainvillea_detail_tier(0) == 2)
    testing.expect(t, architecture.bougainvillea_detail_tier(47.99) == 2)
    testing.expect(t, architecture.bougainvillea_detail_tier(48) == 1)
    testing.expect(t, architecture.bougainvillea_detail_tier(111.99) == 1)
    testing.expect(t, architecture.bougainvillea_detail_tier(112) == 0)
    testing.expect(t, architecture.bougainvillea_crown_detail_fade(88) == 1)
    testing.expect(t, math.abs(architecture.bougainvillea_crown_detail_fade(100) - .5) < .0001)
    testing.expect(t, architecture.bougainvillea_crown_detail_fade(112) == 0)
    testing.expect(t, architecture.bougainvillea_basal_shoot_count(.34) == 0)
    testing.expect(t, architecture.bougainvillea_basal_shoot_count(.35) == 1)
    testing.expect(t, architecture.bougainvillea_basal_shoot_count(.77) == 1)
    testing.expect(t, architecture.bougainvillea_basal_shoot_count(.78) == 2)
    testing.expect(t, architecture.bougainvillea_pruned_stub_count(.52) == 0)
    testing.expect(t, architecture.bougainvillea_pruned_stub_count(.53) == 1)
    testing.expect(t, architecture.bougainvillea_pruned_stub_count(.75) == 2)
    testing.expect(t, architecture.bougainvillea_pruned_stub_count(1) == 3)

    building := terrain.structure_make(1300, 1300, 24, 20, 4, 30)
    building.kind = .Architecture
    left_root := architecture.bougainvillea_root_attachment_x(building, -.2, 2)
    right_root := architecture.bougainvillea_root_attachment_x(building, .2, 2)
    tied_left := architecture.bougainvillea_root_attachment_x(building, 0, 2)
    tied_right := architecture.bougainvillea_root_attachment_x(building, 0, 3)
    testing.expect(t, left_root <= -building.width * .52)
    testing.expect(t, right_root >= building.width * .52)
    testing.expect(t, tied_left < 0)
    testing.expect(t, tied_right > 0)
}

@(test)
bougainvillea_palette_is_stable_and_uses_every_flower_family :: proc(t: ^testing.T) {
    seen: [3]bool
    for seed in 0 ..< 64 {
        palette := architecture.bougainvillea_palette(u32(seed))
        testing.expect(t, palette >= 0 && palette < len(seen))
        testing.expect(t, palette == architecture.bougainvillea_palette(u32(seed)))
        seen[palette] = true
    }
    for present in seen {
        testing.expect(t, present)
    }
}

@(test)
bougainvillea_training_habit_is_stable_and_varied :: proc(t: ^testing.T) {
    seen := [2]bool{}
    for seed in 0 ..< 64 {
        habit := architecture.bougainvillea_training_habit(u32(seed))
        testing.expect(t, habit >= 0 && habit < len(seen))
        testing.expect(t, habit == architecture.bougainvillea_training_habit(u32(seed)))
        seen[habit] = true
    }
    for present in seen {
        testing.expect(t, present)
    }
}

@(test)
bougainvillea_atlas_assigns_four_distinct_cells_to_every_flower_palette :: proc(t: ^testing.T) {
    expected_bases := [3]int{8, 4, 12}
    expected_colors := [3][4]u8{{213, 65, 132, 255}, {226, 100, 86, 255}, {144, 65, 190, 255}}
    occupied := [16]bool{}
    for palette in 0 ..< 3 {
        base := architecture.bougainvillea_flower_tile_base(palette)
        testing.expect(t, base == expected_bases[palette])
        testing.expect(t, architecture.bougainvillea_bract_color(palette) == expected_colors[palette])
        for variation in 0 ..< 4 {
            tile := base + variation
            testing.expect(t, tile >= 4 && tile < 16)
            testing.expect(t, !occupied[tile])
            occupied[tile] = true
        }
    }
    for leaf_tile in 0 ..< 4 {
        testing.expect(t, !occupied[leaf_tile])
    }
}

@(test)
bougainvillea_bract_value_keeps_fresh_tips_brighter_without_leaving_palette_range :: proc(t: ^testing.T) {
    protected := architecture.bougainvillea_bract_value(.8, .4, 0)
    terminal := architecture.bougainvillea_bract_value(.8, 1, 0)
    varied := architecture.bougainvillea_bract_value(.8, 1, 3)
    testing.expect(t, terminal > protected)
    testing.expect(t, varied >= terminal)
    for maturity_step in 0 ..= 4 {
        for node_step in 0 ..= 4 {
            for variation in -2 ..= 6 {
                value := architecture.bougainvillea_bract_value(f32(maturity_step) / 4, f32(node_step) / 4, variation)
                testing.expect(t, value >= .895 && value <= 1.01)
            }
        }
    }
}

@(test)
bougainvillea_density_and_laundry_clearance_share_lifecycle_rules :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 24, 20, 4, 30)
    structure.kind = .Architecture
    field: [terrain.CITY_DENSITY_SAMPLES]u8
    _ = architecture.city_density_stamp(&field, 1300, 1300, 80, 1, 1)
    density := architecture.bougainvillea_density_at_structure(&field, structure)
    testing.expect(t, density > .7)
    testing.expect(
        t,
        architecture.bougainvillea_laundry_conflict(structure, density, structure.base_y + structure.height * .5),
    )
    testing.expect(
        t,
        architecture.bougainvillea_laundry_conflict(
            structure,
            density,
            structure.base_y + structure.height * .84 + 1.2,
        ),
    )
    testing.expect(
        t,
        !architecture.bougainvillea_laundry_conflict(structure, density, structure.base_y + structure.height * .15),
    )
    testing.expect(
        t,
        !architecture.bougainvillea_laundry_conflict(structure, 0, structure.base_y + structure.height * .5),
    )
    testing.expect(
        t,
        architecture.bougainvillea_laundry_span_conflict(
            structure,
            density,
            structure.base_y + structure.height * .5,
            structure.center_x - 20,
            structure.center_z,
            structure.center_x + 20,
            structure.center_z,
        ),
    )
    testing.expect(
        t,
        !architecture.bougainvillea_laundry_span_conflict(
            structure,
            density,
            structure.base_y + structure.height * .5,
            structure.center_x - 20,
            structure.center_z + 40,
            structure.center_x + 20,
            structure.center_z + 40,
        ),
    )
}

@(test)
adriatic_graph_keeps_same_row_frontages_separated :: proc(t: ^testing.T) {
    graph := architecture.adriatic_graph(100, 200, 0xA71D3)
    for left_index in 0 ..< graph.count {
        left := graph.nodes[left_index]
        if left.kind != .Street_Block do continue
        for right_index in left_index + 1 ..< graph.count {
            right := graph.nodes[right_index]
            if right.kind != .Street_Block do continue
            if math.abs(left.z - right.z) > 12 do continue
            clearance := math.abs(left.x - right.x) - (left.width + right.width) * .5
            testing.expect(t, clearance >= -1)
        }
    }
}

@(test)
adriatic_graph_builds_a_rear_row_skyline :: proc(t: ^testing.T) {
    graph := architecture.adriatic_graph(100, 200, 0xA71D3)
    front_total, rear_total: f32
    front_count, rear_count := 0, 0
    for node in graph.nodes[:graph.count] {
        if node.kind != .Street_Block do continue
        if node.z < 180 {
            front_total += node.height
            front_count += 1
        } else if node.z > 220 {
            rear_total += node.height
            rear_count += 1
        }
    }
    testing.expect(t, front_count > 0 && rear_count > 0)
    testing.expect(t, rear_total / f32(rear_count) > front_total / f32(front_count) + 1)
}

@(test)
city_density_stamp_paints_erases_and_falls_off :: proc(t: ^testing.T) {
    field: [terrain.CITY_DENSITY_SAMPLES]u8
    radius := terrain.BASE_CELL_SIZE * 3
    _ = architecture.city_density_stamp(&field, 1300, 1300, radius, .6, .35)
    center := architecture.city_density_sample(&field, 1300, 1300)
    edge := architecture.city_density_sample(&field, 1300 + radius * .8, 1300)
    outside := architecture.city_density_sample(&field, 1300 + radius * 1.6, 1300)
    testing.expect(t, center > .45)
    testing.expect(t, edge > 0 && edge < center)
    testing.expect(t, outside == 0)
    _ = architecture.city_density_stamp(&field, 1300, 1300, radius, .2, .35, true)
    testing.expect(t, architecture.city_density_sample(&field, 1300, 1300) < center)
}

@(test)
city_density_clamps_after_repeated_strokes :: proc(t: ^testing.T) {
    field: [terrain.CITY_DENSITY_SAMPLES]u8
    for _ in 0 ..< 8 {
        _ = architecture.city_density_stamp(&field, 1300, 1300, 80, 1, 1)
    }
    testing.expect(t, architecture.city_density_sample(&field, 1300, 1300) == 1)
    for _ in 0 ..< 8 {
        _ = architecture.city_density_stamp(&field, 1300, 1300, 80, 1, 1, true)
    }
    testing.expect(t, architecture.city_density_sample(&field, 1300, 1300) == 0)
}

@(test)
city_plan_is_deterministic_and_density_controls_massing :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    low, high: [terrain.CITY_DENSITY_SAMPLES]u8
    bounds := architecture.City_Bounds{1120, 1120, 1480, 1480, true}
    _ = architecture.city_density_stamp(&low, 1300, 1300, 175, .34, .8)
    _ = architecture.city_density_stamp(&high, 1300, 1300, 175, 1, .8)
    low_plan := architecture.city_plan_density(project, &low, bounds)
    defer architecture.city_plan_destroy(&low_plan)
    high_plan := architecture.city_plan_density(project, &high, bounds)
    defer architecture.city_plan_destroy(&high_plan)
    repeat := architecture.city_plan_density(project, &high, bounds)
    defer architecture.city_plan_destroy(&repeat)
    testing.expect(t, low_plan.count > 0)
    testing.expect(t, high_plan.count >= low_plan.count)
    testing.expect(t, repeat.count == high_plan.count)
    low_height, high_height: f32
    for structure in low_plan.structures[:low_plan.count] do low_height += structure.height
    for index in 0 ..< high_plan.count {
        high_height += high_plan.structures[index].height
        testing.expect(t, high_plan.structures[index].seed == repeat.structures[index].seed)
        testing.expect(t, high_plan.structures[index].center_x == repeat.structures[index].center_x)
    }
    testing.expect(t, high_height / f32(high_plan.count) > low_height / f32(low_plan.count))
}

@(test)
city_planner_queries_curved_road_clearance_and_tangent :: proc(t: ^testing.T) {
    graph: roads.Graph
    a := roads.add_node(&graph, {1200, 4, 1200}, 8)
    b := roads.add_node(&graph, {1400, 4, 1200}, 8)
    _ = roads.add_edge(&graph, a, b, {1260, 4, 1280}, {1340, 4, 1280}, 10, 2)
    frontage := architecture.city_nearest_road_frontage(&graph, 1300, 1260)
    found, distance, tangent_x, tangent_z, clearance := architecture.city_nearest_road(&graph, 1300, 1260)
    testing.expect(t, frontage.found)
    testing.expect(t, math.abs(frontage.point_x - 1300) < 2)
    testing.expect(t, math.abs(frontage.point_z - 1260) < 30)
    testing.expect(t, found)
    testing.expect(t, distance < 30)
    testing.expect(t, clearance == 9)
    testing.expect(t, math.abs(tangent_x) > .8)
    testing.expect(t, math.abs(tangent_z) < .4)
}

@(test)
city_road_clearance_uses_the_rotated_footprint_instead_of_its_bounding_circle :: proc(t: ^testing.T) {
    graph: roads.Graph
    a := roads.add_node(&graph, {1200, 4, 1300}, 4)
    b := roads.add_node(&graph, {1400, 4, 1300}, 4)
    _ = roads.add_straight_edge(&graph, a, b, 10, 2)

    aligned := terrain.structure_make(1300, 1321, 36, 18, 4, 20)
    aligned.kind = .Architecture
    testing.expect(t, architecture.city_structure_road_clear(&graph, &aligned))

    intruding := aligned
    intruding.center_z = 1315
    testing.expect(t, !architecture.city_structure_road_clear(&graph, &intruding))
}

@(test)
city_site_validation_rejects_water_and_uses_high_foundation :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    water := terrain.structure_make(0, 0, 20, 20, 0, 12)
    testing.expect(t, !architecture.city_structure_site_valid(project, &water))
    land := terrain.structure_make(1300, 1300, 20, 20, 0, 12)
    testing.expect(t, architecture.city_structure_site_valid(project, &land))
    testing.expect(t, land.base_y > project.sea_level)
}

@(test)
architecture_foundation_spans_uneven_rotated_footprint :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    building := terrain.structure_make(1300, 1300, 30, 18, 0, 20)
    building.kind = .Architecture
    building.rotation = math.PI / 4
    corner_x := building.center_x + (building.width * .5 - building.depth * .5) * .70710678
    corner_z := building.center_z + (building.width * .5 + building.depth * .5) * .70710678
    terrain.apply_stroke(project, .Raise, corner_x, corner_z, 10, .8, 1)
    lowest, highest := architecture.architecture_foundation_height_range(project, building)
    testing.expect(t, highest >= lowest)
    testing.expect(t, highest - lowest > .01)
    testing.expect(t, architecture.city_structure_site_valid(project, &building))
    testing.expect(t, building.base_y == highest)
}

@(test)
architecture_foundation_detects_ridge_between_frontage_probes :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    building := terrain.structure_make(1300, 1300, 30, 18, 0, 20)
    building.kind = .Architecture
    // This lies on the front wall, but between the old corner, center, and
    // edge-midpoint probes that allowed the wall to pass through the ridge.
    ridge_x, ridge_z := f32(1293), f32(1309)
    before := terrain.sample_height(project, 0, ridge_x, ridge_z)
    terrain.apply_stroke(project, .Raise, ridge_x, ridge_z, 2.5, .8, 1)
    ridge_height := terrain.sample_height(project, 0, ridge_x, ridge_z)
    testing.expect(t, ridge_height > before)
    _, highest := architecture.architecture_foundation_height_range(project, building)
    testing.expect(t, highest >= ridge_height - .001)
}

@(test)
city_commit_replaces_architecture_but_preserves_other_formations :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    building := terrain.structure_make(1300, 1300, 20, 20, 4.5, 20)
    building.kind = .Architecture
    _ = terrain.add_structure(project, building)
    rock := terrain.structure_make(1320, 1300, 16, 16, 4.5, 10)
    rock.kind = .Rock
    _ = terrain.add_structure(project, rock)
    field: [terrain.CITY_DENSITY_SAMPLES]u8
    bounds := architecture.City_Bounds{1260, 1260, 1340, 1340, true}
    plan: architecture.City_Plan
    _ = architecture.city_commit_plan(project, &field, bounds, &plan)
    testing.expect(t, project.structure_count == 1)
    testing.expect(t, project.structures[0].kind == .Rock)
}

@(test)
city_preview_plan_matches_committed_structures :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    field: [terrain.CITY_DENSITY_SAMPLES]u8
    bounds := architecture.City_Bounds{1160, 1160, 1440, 1440, true}
    _ = architecture.city_density_stamp(&field, 1300, 1300, 130, .8, .7)
    plan := architecture.city_plan_density(project, &field, bounds)
    defer architecture.city_plan_destroy(&plan)
    created := architecture.city_commit_plan(project, &field, bounds, &plan)
    testing.expect(t, created == plan.count)
    testing.expect(t, project.structure_count == plan.count)
    for index in 0 ..< plan.count {
        testing.expect(t, project.structures[index].seed == plan.structures[index].seed)
        testing.expect(t, project.structures[index].height == plan.structures[index].height)
        testing.expect(t, project.structures[index].rotation == plan.structures[index].rotation)
        testing.expect(t, project.structures[index].building == plan.structures[index].building)
    }
}

@(test)
city_plan_region_can_distinguish_default_island_architecture :: proc(t: ^testing.T) {
    plan: architecture.City_Plan
    west := terrain.structure_make(-1300, -1418, 20, 20, 4.5, 20)
    west.kind = .Architecture
    append(&plan.structures, west)
    plan.count = 1
    defer architecture.city_plan_destroy(&plan)

    architecture.city_plan_set_region(&plan, .Aegean)

    testing.expect(t, plan.structures[0].building.region == buildings.Region.Aegean)
}

@(test)
city_plan_storage_grows_past_legacy_limit :: proc(t: ^testing.T) {
    plan: architecture.City_Plan
    defer architecture.city_plan_destroy(&plan)
    for index in 0 ..< 400 {
        append(&plan.structures, terrain.structure_make(f32(index), 0, 8, 10, 0, 7))
        append(&plan.parcels, architecture.City_Parcel{seed = u32(index)})
        append(&plan.alleys, architecture.City_Alley{start_x = f32(index)})
        append(&plan.lamps, architecture.City_Lamp{x = f32(index)})
        plan.count += 1
        plan.parcel_count += 1
        plan.alley_count += 1
        plan.lamp_count += 1
    }
    testing.expect_value(t, plan.count, 400)
    testing.expect_value(t, len(plan.structures), 400)
    testing.expect_value(t, plan.parcel_count, 400)
    testing.expect_value(t, len(plan.parcels), 400)
    testing.expect_value(t, plan.alley_count, 400)
    testing.expect_value(t, len(plan.alleys), 400)
    testing.expect_value(t, plan.lamp_count, 400)
    testing.expect_value(t, len(plan.lamps), 400)
    testing.expect_value(t, plan.parcels[399].seed, u32(399))
}

@(test)
city_planner_builds_accessible_frontage_parcels_and_deep_alleys :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    field: [terrain.CITY_DENSITY_SAMPLES]u8
    bounds := architecture.City_Bounds{1120, 1120, 1480, 1480, true}
    _ = architecture.city_density_stamp(&field, 1300, 1300, 185, 1, 1)
    plan := architecture.city_plan_density(project, &field, bounds)
    defer architecture.city_plan_destroy(&plan)
    testing.expect(t, plan.count > 0)
    testing.expect(t, plan.parcel_count == plan.count)
    testing.expect(t, plan.alley_count > 0)
    for alley in plan.alleys[:plan.alley_count] {
        testing.expect(t, alley.household_demand >= 2)
        testing.expect_value(t, alley.start_terminal, architecture.City_Alley_Terminal.Road)
        road_root := architecture.city_nearest_road_frontage(&project.road_graph, alley.start_x, alley.start_z)
        testing.expect(t, road_root.found)
        testing.expect(t, road_root.distance <= .05)
    }
    for parcel in plan.parcels[:plan.parcel_count] {
        testing.expect(t, parcel.frontage_width >= 8 && parcel.frontage_width <= 32)
        testing.expect(t, parcel.depth >= 13 && parcel.depth <= 36)
    }
}

@(test)
low_density_island_town_does_not_spawn_deep_alley_branches :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    field: [terrain.CITY_DENSITY_SAMPLES]u8
    center, town_z := terrain.default_town_center(-1)
    bounds := architecture.City_Bounds{center - 108, town_z - 68, center + 108, town_z + 68, true}

    road_start := roads.add_node(&project.road_graph, {center - 78, 4.5, town_z}, 0)
    road_finish := roads.add_node(&project.road_graph, {center + 78, 4.5, town_z}, 0)
    _ = roads.add_straight_edge(&project.road_graph, road_start, road_finish, 5.5, 1.4, .Cobblestone)
    _ = architecture.city_density_stamp(&field, center, town_z, 82, .20, .70)

    plan := architecture.city_plan_density(project, &field, bounds, 0xA71D3)
    defer architecture.city_plan_destroy(&plan)
    testing.expect(t, plan.count > 0)
    testing.expect_value(t, plan.alley_count, 0)
}

@(test)
alley_branch_snaps_to_and_splits_existing_network :: proc(t: ^testing.T) {
    plan: architecture.City_Plan
    defer architecture.city_plan_destroy(&plan)
    existing := architecture.City_Alley {
        start_x          = 5,
        start_z          = -5,
        end_x            = 5,
        end_z            = 5,
        half_width       = .8,
        household_demand = 3,
        end_terminal     = .Public_Space,
    }
    append(&plan.alleys, existing)
    plan.alley_count = 1

    x, z, amount, found := architecture.city_alley_segment_intersection(0, 0, 10, 0, existing)
    testing.expect(t, found)
    testing.expect(t, math.abs(x - 5) <= .001 && math.abs(z) <= .001)
    testing.expect(t, math.abs(amount - .5) <= .001)

    architecture.city_plan_split_alley_at(&plan, 0, x, z)
    testing.expect_value(t, plan.alley_count, 2)
    testing.expect(t, math.abs(plan.alleys[0].end_x - x) <= .001)
    testing.expect(t, math.abs(plan.alleys[1].start_x - x) <= .001)
    testing.expect_value(t, plan.alleys[0].end_terminal, architecture.City_Alley_Terminal.None)
    testing.expect_value(t, plan.alleys[1].start_terminal, architecture.City_Alley_Terminal.None)
    testing.expect_value(t, plan.alleys[1].end_terminal, architecture.City_Alley_Terminal.Public_Space)
}

@(test)
ground_level_details_stay_clear_of_the_narrowest_alley_frontage :: proc(t: ^testing.T) {
    testing.expect(t, architecture.GROUND_DETAIL_MAX_REACH < architecture.CITY_ALLEY_MIN_FRONT_CLEARANCE)
}

@(test)
city_height_generation_includes_broad_single_floor_buildings :: proc(t: ^testing.T) {
    found_single_floor := false
    found_multi_floor := false
    for seed in 0 ..< 1024 {
        height := architecture.city_building_height(28, 24, .9, u32(seed * 747796405))
        if architecture.facade_floor_count(height) == 1 {
            found_single_floor = true
        } else {
            found_multi_floor = true
        }
    }
    testing.expect(t, found_single_floor)
    testing.expect(t, found_multi_floor)

    // Narrow footprints retain the density-driven vertical massing.
    for seed in 0 ..< 64 {
        height := architecture.city_building_height(16, 18, .9, u32(seed * 747796405))
        testing.expect(t, architecture.facade_floor_count(height) > 1)
    }
}

@(test)
architecture_compound_footprints_are_seed_stable_and_use_exact_overlap :: proc(t: ^testing.T) {
    a := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    a.kind = .Architecture
    a.seed = 1
    first := architecture.architecture_footprint(a)
    second := architecture.architecture_footprint(a)
    testing.expect(t, first.count == 2)
    testing.expect(t, first == second)

    b := a
    b.center_x += 31
    testing.expect(t, !architecture.city_structure_overlaps(a, b, 0))
    b.center_x -= 3
    testing.expect(t, architecture.city_structure_overlaps(a, b, 0))
}

@(test)
architecture_frontage_mass_is_the_farthest_rendered_front_plane :: proc(t: ^testing.T) {
    for seed in 0 ..< 10 {
        structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
        structure.kind = .Architecture
        structure.seed = u32(seed)
        footprint := architecture.architecture_footprint(structure)
        selected := architecture.architecture_frontage_mass_index(structure)
        testing.expect(t, selected >= 0 && selected < footprint.count)
        selected_front := footprint.masses[selected].local_z + footprint.masses[selected].depth * .5
        for mass in footprint.masses[:footprint.count] {
            testing.expect(t, selected_front >= mass.local_z + mass.depth * .5)
        }
        frontage_structure := architecture.architecture_frontage_structure(structure)
        selected_mass := footprint.masses[selected]
        expected_x, expected_z := architecture.architecture_mass_world(structure, selected_mass)
        testing.expect(t, frontage_structure.center_x == expected_x)
        testing.expect(t, frontage_structure.center_z == expected_z)
        testing.expect(t, frontage_structure.width == selected_mass.width)
        testing.expect(t, frontage_structure.depth == selected_mass.depth)
    }
}

@(test)
architecture_frontage_proxy_uses_actual_compact_mass_height :: proc(t: ^testing.T) {
    cases := [3]struct {
        archetype:            buildings.Archetype,
        width, depth, height: f32,
        seed:                 u32,
    }{{.Dwelling, 8, 6, 4.8, 0}, {.Clinic, 14, 12, 7.2, 3}, {.Campanile, 18, 14, 9.6, 5}}
    for test_case in cases {
        structure := terrain.structure_make(1300, 1300, test_case.width, test_case.depth, 4, test_case.height)
        structure.width, structure.depth, structure.height = test_case.width, test_case.depth, test_case.height
        structure.kind = .Architecture
        structure.seed = test_case.seed
        structure.building.archetype = test_case.archetype
        footprint := architecture.architecture_footprint(structure)
        primary := architecture.architecture_frontage_mass_index(structure)
        frontage := architecture.architecture_frontage_structure(structure)
        expected_height := structure.height * footprint.masses[primary].height_scale
        testing.expectf(
            t,
            math.abs(frontage.height - expected_height) <= .001,
            "frontage height inflated archetype=%v actual=%.2f expected=%.2f",
            test_case.archetype,
            frontage.height,
            expected_height,
        )
    }
}

@(test)
architecture_dwelling_compounds_keep_the_full_width_range_on_the_street :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    structure.building.archetype = .Dwelling
    seeds := [3]u32{1, 3, 6}
    for seed in seeds {
        structure.seed = seed
        footprint := architecture.architecture_footprint(structure)
        testing.expect(t, footprint.count > 1)
        primary := architecture.architecture_frontage_mass_index(structure)
        testing.expect_value(t, primary, 0)
        testing.expect(t, footprint.masses[primary].width == structure.width)
        for mass in footprint.masses[1:footprint.count] {
            testing.expect(
                t,
                mass.local_z + mass.depth * .5 <
                footprint.masses[primary].local_z + footprint.masses[primary].depth * .5,
            )
        }
    }
}

@(test)
architecture_context_resolves_explicit_and_contextual_archetypes :: proc(t: ^testing.T) {
    shop := architecture.architecture_identity(
        {purpose = .Inn_Shop, density = .8, attached = true, route = .Civic, purpose_explicit = true},
        43,
    )
    testing.expect_value(t, shop.archetype, buildings.Archetype.Shop_House)

    mixed_use := architecture.architecture_identity(
        {purpose = .Inn_Shop, density = .65, route = .Street, purpose_explicit = true},
        47,
    )
    testing.expect_value(t, mixed_use.archetype, buildings.Archetype.Mixed_Use_Dwelling)
    testing.expect(t, buildings.is_habitable(mixed_use.archetype))

    townhouse := architecture.architecture_identity(
        {purpose = .Dwelling, density = .72, attached = true, purpose_explicit = true},
        42,
    )
    testing.expect_value(t, townhouse.archetype, buildings.Archetype.Townhouse)

    lighthouse := architecture.architecture_identity(
        {region = .Adriatic, landmark_kind = .Lighthouse, purpose_explicit = true},
        91,
    )
    testing.expect_value(t, lighthouse.archetype, buildings.Archetype.Lighthouse)
    testing.expect(t, buildings.is_landmark(lighthouse))
    testing.expect(t, !buildings.is_habitable(lighthouse.archetype))

    waterfront := architecture.Architecture_Context {
        density          = .45,
        waterfront       = true,
        route            = .Waterfront,
        purpose_explicit = false,
    }
    testing.expect(
        t,
        architecture.architecture_identity(waterfront, 0) == architecture.architecture_identity(waterfront, 0),
    )
    testing.expect(t, architecture.architecture_identity(waterfront, 0).purpose != .Dwelling)
}

@(test)
mixed_use_identity_reaches_all_compound_footprint_families :: proc(t: ^testing.T) {
    ctx := architecture.Architecture_Context {
        purpose          = .Inn_Shop,
        density          = .70,
        route            = .Street,
        purpose_explicit = true,
        frontage         = 24,
        depth            = 18,
    }
    mixed_count := 0
    found_l, found_t, found_court := false, false, false
    for seed in 0 ..< 512 {
        identity := architecture.architecture_identity(ctx, u32(seed))
        if identity.archetype != .Mixed_Use_Dwelling do continue
        mixed_count += 1

        structure := terrain.structure_make(1300, 1300, 30, 24, 4, 18)
        structure.kind = .Architecture
        structure.seed = u32(seed)
        structure.building = identity
        footprint := architecture.architecture_footprint(structure)
        if footprint.count == 3 {
            found_court = true
        } else if footprint.count == 2 && footprint.masses[1].local_x == 0 {
            found_t = true
        } else if footprint.count == 2 {
            found_l = true
        }
    }

    testing.expect(t, mixed_count > 100)
    testing.expect(t, found_l)
    testing.expect(t, found_t)
    testing.expect(t, found_court)
}

@(test)
architecture_archetypes_constrain_compound_massing :: proc(t: ^testing.T) {
    dwelling := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    dwelling.kind = .Architecture
    dwelling.seed = 3
    dwelling.building.archetype = .Dwelling
    dwelling_footprint := architecture.architecture_footprint(dwelling)
    testing.expect(t, dwelling_footprint.count == 3)

    townhouse := dwelling
    townhouse.building.archetype = .Townhouse
    townhouse.seed = 2
    townhouse_footprint := architecture.architecture_footprint(townhouse)
    testing.expect(t, townhouse_footprint.count == 2)

    narrow := dwelling
    narrow.width, narrow.depth = 10, 10
    testing.expect(t, architecture.architecture_footprint(narrow).count == 1)

    for mass in dwelling_footprint.masses[:dwelling_footprint.count] {
        testing.expect(t, mass.width >= 4.5)
        testing.expect(t, mass.depth >= 4.5)
    }
}

@(test)
architecture_asymmetric_floorplan_variants_really_mirror :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    cases := [4]struct {
        archetype:               buildings.Archetype,
        first_seed, second_seed: u32,
        mirrored_mass:           int,
    }{{.Dwelling, 1, 5, 1}, {.Townhouse, 1, 7, 1}, {.Shop_House, 0, 4, 1}, {.Storehouse, 0, 8, 1}}
    for test_case in cases {
        structure.building.archetype = test_case.archetype
        structure.seed = test_case.first_seed
        first := architecture.architecture_footprint(structure)
        structure.seed = test_case.second_seed
        second := architecture.architecture_footprint(structure)
        testing.expect_value(t, first.count, 2)
        testing.expect_value(t, second.count, 2)
        first_mass := first.masses[test_case.mirrored_mass]
        second_mass := second.masses[test_case.mirrored_mass]
        testing.expectf(
            t,
            first_mass.local_x == -second_mass.local_x && math.abs(first_mass.local_x) > .001,
            "eligible floorplan variants failed to mirror archetype=%v seeds=(%d,%d)",
            test_case.archetype,
            test_case.first_seed,
            test_case.second_seed,
        )
        testing.expect(t, first_mass.local_z == second_mass.local_z)
        testing.expect(t, first_mass.width == second_mass.width && first_mass.depth == second_mass.depth)
    }

    // Productive courts mirror the unequal sheds as a complete composition,
    // rather than merely swapping one attachment while changing its program.
    productive_archetypes := [3]buildings.Archetype{.Workshop, .Storehouse, .Fishery}
    for archetype in productive_archetypes {
        structure.building.archetype = archetype
        structure.seed = archetype == .Fishery ? 10 : 4
        first := architecture.architecture_footprint(structure)
        structure.seed = 22
        second := architecture.architecture_footprint(structure)
        testing.expect_value(t, first.count, 3)
        testing.expect_value(t, second.count, 3)
        testing.expect(t, first.masses[1].local_x == -second.masses[1].local_x)
        testing.expect(t, first.masses[2].local_x == -second.masses[2].local_x)
        testing.expect(t, first.masses[1].width == second.masses[1].width)
        testing.expect(t, first.masses[2].width == second.masses[2].width)
    }
}

@(test)
architecture_floorplans_offer_distinct_archetype_appropriate_topologies :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture

    structure.building.archetype = .Dwelling
    structure.seed = 3
    courtyard := architecture.architecture_footprint(structure)
    structure.seed = 6
    tee := architecture.architecture_footprint(structure)
    structure.seed = 1
    ell := architecture.architecture_footprint(structure)
    testing.expect_value(t, courtyard.count, 3)
    testing.expect_value(t, tee.count, 2)
    testing.expect_value(t, ell.count, 2)
    testing.expect(t, tee != ell)
    structure.seed = 3
    courtyard_primary := architecture.architecture_frontage_mass_index(structure)
    testing.expect_value(t, courtyard_primary, 0)
    for wing_index in 1 ..= 2 {
        wing_layout := architecture.architecture_opening_layout(structure, wing_index, courtyard_primary)
        garden_doors, court_doors := 0, 0
        expected_court_face := wing_index == 1 ? architecture.Face.Right : architecture.Face.Left
        for opening in wing_layout.openings[:wing_layout.count] {
            if opening.kind == .Service_Door {
                if opening.face == .Rear do garden_doors += 1
                if opening.face == expected_court_face do court_doors += 1
            }
        }
        testing.expect_value(t, garden_doors, 1)
        testing.expect_value(t, court_doors, 1)
    }

    structure.building.archetype = .Farmstead
    structure.seed = 0
    farm_service := architecture.architecture_footprint(structure)
    structure.building.archetype = .Dwelling
    dwelling_plain := architecture.architecture_footprint(structure)
    testing.expect_value(t, farm_service.count, 2)
    testing.expect_value(t, dwelling_plain.count, 1)
    testing.expect(t, farm_service.masses[0].width == structure.width)
    testing.expect(t, farm_service.masses[1].height_scale < farm_service.masses[0].height_scale)
    structure.building.archetype = .Farmstead
    testing.expect_value(t, architecture.architecture_frontage_mass_index(structure), 0)

    structure.building.archetype = .Townhouse
    structure.seed = 1
    rear_return := architecture.architecture_footprint(structure)
    structure.seed = 2
    stepped := architecture.architecture_footprint(structure)
    testing.expect_value(t, rear_return.count, 2)
    testing.expect_value(t, stepped.count, 2)
    testing.expect(t, rear_return != stepped)

    structure.building.archetype = .Shop_House
    structure.seed = 0
    shop_stockroom := architecture.architecture_footprint(structure)
    structure.building.archetype = .Townhouse
    townhouse_plain := architecture.architecture_footprint(structure)
    testing.expect_value(t, shop_stockroom.count, 2)
    testing.expect_value(t, townhouse_plain.count, 1)
    testing.expect(t, shop_stockroom.masses[0].width == structure.width)
    testing.expect(t, shop_stockroom.masses[1].height_scale < shop_stockroom.masses[0].height_scale)
    structure.building.archetype = .Shop_House
    testing.expect_value(t, architecture.architecture_frontage_mass_index(structure), 0)

    structure.building.archetype = .Workshop
    structure.seed = 4
    work_court := architecture.architecture_footprint(structure)
    structure.seed = 1
    service_wing := architecture.architecture_footprint(structure)
    testing.expect_value(t, work_court.count, 3)
    testing.expect_value(t, service_wing.count, 2)
    structure.seed = 4
    work_court_primary := architecture.architecture_frontage_mass_index(structure)
    testing.expect_value(t, work_court_primary, 0)
    work_hall_layout := architecture.architecture_opening_layout(structure, 0, work_court_primary)
    work_hall_doors := 0
    for opening in work_hall_layout.openings[:work_hall_layout.count] {
        if opening.kind == .Service_Door {
            work_hall_doors += 1
            testing.expect(t, opening.face == .Front)
            testing.expect(t, math.abs(opening.horizontal) <= .001)
        }
    }
    testing.expect_value(t, work_hall_doors, 1)

    structure.building.archetype = .Fishery
    structure.seed = 0
    fishery_tee := architecture.architecture_footprint(structure)
    structure.building.archetype = .Workshop
    fishery_comparison := architecture.architecture_footprint(structure)
    testing.expect_value(t, fishery_tee.count, 2)
    testing.expect_value(t, fishery_comparison.count, 1)
    testing.expect(t, fishery_tee.masses[0].width == structure.width)
    testing.expect(t, fishery_tee.masses[1].local_x == 0)
    testing.expect(t, fishery_tee.masses[1].height_scale < fishery_tee.masses[0].height_scale)
    structure.building.archetype = .Fishery
    fishery_primary := architecture.architecture_frontage_mass_index(structure)
    testing.expect_value(t, fishery_primary, 0)
    fishery_layout := architecture.architecture_opening_layout(structure, 1, fishery_primary)
    fishery_service_doors := 0
    for opening in fishery_layout.openings[:fishery_layout.count] {
        if opening.kind == .Service_Door {
            fishery_service_doors += 1
            testing.expect(t, opening.face == .Rear)
        }
    }
    testing.expect_value(t, fishery_service_doors, 1)

    structure.building.archetype = .Storehouse
    structure.seed = 0
    loading_annex := architecture.architecture_footprint(structure)
    structure.building.archetype = .Workshop
    workshop_plain := architecture.architecture_footprint(structure)
    testing.expect_value(t, loading_annex.count, 2)
    testing.expect_value(t, workshop_plain.count, 1)
    testing.expect(t, loading_annex.masses[0].width == structure.width)
    testing.expect(t, loading_annex.masses[1].local_x != 0)
    testing.expect(t, loading_annex.masses[1].depth < fishery_tee.masses[1].depth)
    structure.building.archetype = .Storehouse
    storehouse_primary := architecture.architecture_frontage_mass_index(structure)
    testing.expect_value(t, storehouse_primary, 0)
    loading_layout := architecture.architecture_opening_layout(structure, 1, storehouse_primary)
    loading_doors := 0
    for opening in loading_layout.openings[:loading_layout.count] {
        if opening.kind == .Service_Door {
            loading_doors += 1
            testing.expect(t, opening.face == .Rear)
        }
    }
    testing.expect_value(t, loading_doors, 1)

    structure.building.archetype = .Barn_Granary
    structure.seed = 0
    barn_aisle := architecture.architecture_footprint(structure)
    testing.expect_value(t, barn_aisle.count, 2)
    main_left := barn_aisle.masses[0].local_x - barn_aisle.masses[0].width * .5
    aisle_left := barn_aisle.masses[1].local_x - barn_aisle.masses[1].width * .5
    testing.expect(t, aisle_left < main_left)
    shared_width :=
        min(
            barn_aisle.masses[0].local_x + barn_aisle.masses[0].width * .5,
            barn_aisle.masses[1].local_x + barn_aisle.masses[1].width * .5,
        ) -
        max(main_left, aisle_left)
    testing.expect(t, shared_width >= 1.35 - .001)
    barn_primary := architecture.architecture_frontage_mass_index(structure)
    testing.expect_value(t, barn_primary, 0)
    aisle_layout := architecture.architecture_opening_layout(structure, 1, barn_primary)
    aisle_doors := 0
    expected_aisle_face := barn_aisle.masses[1].local_x < 0 ? architecture.Face.Left : architecture.Face.Right
    for opening in aisle_layout.openings[:aisle_layout.count] {
        if opening.kind == .Service_Door {
            aisle_doors += 1
            testing.expect_value(t, opening.face, expected_aisle_face)
        }
    }
    testing.expect_value(t, aisle_doors, 1)

    structure.building.archetype = .Mixed_Use_Dwelling
    structure.seed = 43
    mixed_use := architecture.architecture_footprint(structure)
    testing.expect_value(t, mixed_use.count, 2)
    testing.expect(t, mixed_use.masses[0].width == structure.width)
    testing.expect(t, mixed_use.masses[1].height_scale < mixed_use.masses[0].height_scale)

    structure.seed = 2
    mixed_use_t := architecture.architecture_footprint(structure)
    testing.expect_value(t, mixed_use_t.count, 2)
    testing.expect(t, mixed_use_t.masses[1].local_x == 0)
    testing.expect(t, mixed_use_t.masses[1].width > mixed_use.masses[1].width)

    structure.seed = 5
    mixed_use_court := architecture.architecture_footprint(structure)
    testing.expect_value(t, mixed_use_court.count, 3)
    testing.expect(t, mixed_use_court.masses[1].local_x < 0)
    testing.expect(t, mixed_use_court.masses[2].local_x > 0)
    testing.expect(t, mixed_use_court.masses[1].height_scale < mixed_use_court.masses[0].height_scale)
    street_bar_rear_edge := mixed_use_court.masses[0].local_z - mixed_use_court.masses[0].depth * .5
    for rear_wing in mixed_use_court.masses[1:3] {
        wing_front_edge := rear_wing.local_z + rear_wing.depth * .5
        testing.expect(t, wing_front_edge - street_bar_rear_edge >= 1.20)
    }

    structure.building.archetype = .Palace_Loggia
    structure.seed = 0
    civic_court := architecture.architecture_footprint(structure)
    testing.expect_value(t, civic_court.count, 3)
    testing.expect(t, civic_court.masses[1].local_x < 0 && civic_court.masses[2].local_x > 0)
    palace_primary := architecture.architecture_frontage_mass_index(structure)
    testing.expect_value(t, palace_primary, 0)
    for wing_index in 1 ..= 2 {
        wing_layout := architecture.architecture_opening_layout(structure, wing_index, palace_primary)
        garden_doors, court_doors := 0, 0
        expected_court_face := wing_index == 1 ? architecture.Face.Right : architecture.Face.Left
        for opening in wing_layout.openings[:wing_layout.count] {
            if opening.kind == .Service_Door {
                if opening.face == .Rear do garden_doors += 1
                if opening.face == expected_court_face do court_doors += 1
            }
        }
        testing.expect_value(t, garden_doors, 1)
        testing.expect_value(t, court_doors, 1)
    }

    structure.building.archetype = .Market_Hall
    market_tee := architecture.architecture_footprint(structure)
    testing.expect_value(t, market_tee.count, 2)
    testing.expect(t, market_tee.masses[1].local_x == 0)
    testing.expect(t, market_tee.masses[1].local_z < market_tee.masses[0].local_z)
    market_primary := architecture.architecture_frontage_mass_index(structure)
    testing.expect_value(t, market_primary, 0)
    trading_layout := architecture.architecture_opening_layout(structure, 1, market_primary)
    market_loading_doors := 0
    for opening in trading_layout.openings[:trading_layout.count] {
        if opening.kind == .Service_Door {
            market_loading_doors += 1
            testing.expect(t, opening.face == .Rear)
            testing.expect(t, math.abs(opening.horizontal) <= .001)
            testing.expect(t, opening.width >= 3.4 && opening.width <= 5.0)
            testing.expect(t, opening.height >= 3.8 && opening.height <= 5.0)
        }
    }
    testing.expect_value(t, market_loading_doors, 1)

    structure.building.archetype = .Harbor_Office
    harbor_yard := architecture.architecture_footprint(structure)
    testing.expect_value(t, harbor_yard.count, 3)
    testing.expect(t, harbor_yard.masses[1].local_x * harbor_yard.masses[2].local_x < 0)
    testing.expect(t, harbor_yard.masses[1].width > harbor_yard.masses[2].width)
    testing.expect(t, harbor_yard.masses[1].height_scale > harbor_yard.masses[2].height_scale)
    harbor_street_rear := harbor_yard.masses[0].local_z - harbor_yard.masses[0].depth * .5
    for rear_range in harbor_yard.masses[1:3] {
        testing.expect(t, rear_range.local_z + rear_range.depth * .5 - harbor_street_rear >= 1.20)
    }
    harbor_primary := architecture.architecture_frontage_mass_index(structure)
    testing.expect_value(t, harbor_primary, 0)
    for range_index in 1 ..= 2 {
        range_layout := architecture.architecture_opening_layout(structure, range_index, harbor_primary)
        quay_doors, yard_doors := 0, 0
        expected_yard_face :=
            harbor_yard.masses[range_index].local_x < 0 ? architecture.Face.Right : architecture.Face.Left
        for opening in range_layout.openings[:range_layout.count] {
            if opening.kind == .Service_Door {
                if opening.face == .Rear do quay_doors += 1
                if opening.face == expected_yard_face do yard_doors += 1
            }
        }
        testing.expect_value(t, quay_doors, 1)
        testing.expect_value(t, yard_doors, 1)
    }
    testing.expect(t, civic_court != market_tee && market_tee != harbor_yard)
}

@(test)
architecture_two_range_domestic_returns_have_rear_garden_access :: proc(t: ^testing.T) {
    cases := [7]struct {
        archetype: buildings.Archetype,
        seed:      u32,
    } {
        {.Dwelling, 1},
        {.Dwelling, 6},
        {.Farmstead, 1},
        {.Townhouse, 1},
        {.Townhouse, 2},
        {.Shop_House, 0},
        {.Shop_House, 2},
    }
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    for test_case in cases {
        structure.building.archetype = test_case.archetype
        structure.seed = test_case.seed
        footprint := architecture.architecture_footprint(structure)
        testing.expect_value(t, footprint.count, 2)
        primary := architecture.architecture_frontage_mass_index(structure)
        testing.expect(t, primary != 1)
        layout := architecture.architecture_opening_layout(structure, 1, primary)
        rear_doors := 0
        for opening in layout.openings[:layout.count] {
            if opening.kind == .Service_Door {
                rear_doors += 1
                testing.expect(t, opening.face == .Rear)
            }
        }
        testing.expectf(
            t,
            rear_doors == 1,
            "domestic return lacks single rear access archetype=%v seed=%d doors=%d",
            test_case.archetype,
            test_case.seed,
            rear_doors,
        )
    }
}

@(test)
architecture_productive_courts_assign_entrance_to_central_work_hall :: proc(t: ^testing.T) {
    archetypes := [3]buildings.Archetype{.Workshop, .Storehouse, .Fishery}
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    structure.seed = 10
    for archetype in archetypes {
        structure.building.archetype = archetype
        footprint := architecture.architecture_footprint(structure)
        testing.expect_value(t, footprint.count, 3)
        primary := architecture.architecture_frontage_mass_index(structure)
        testing.expect_value(t, primary, 0)
        hall_layout := architecture.architecture_opening_layout(structure, 0, primary)
        hall_doors := 0
        for opening in hall_layout.openings[:hall_layout.count] {
            if opening.kind == .Door || opening.kind == .Service_Door {
                hall_doors += 1
                testing.expect(t, opening.face == .Front)
            }
        }
        testing.expect_value(t, hall_doors, 1)
        for shed_index in 1 ..= 2 {
            shed_layout := architecture.architecture_opening_layout(structure, shed_index, primary)
            shed_doors := 0
            for opening in shed_layout.openings[:shed_layout.count] {
                if opening.kind == .Door || opening.kind == .Service_Door do shed_doors += 1
            }
            testing.expectf(
                t,
                shed_doors == 0,
                "projecting shed stole court entrance archetype=%v mass=%d doors=%d",
                archetype,
                shed_index,
                shed_doors,
            )
        }
    }
}

@(test)
architecture_productive_court_sheds_keep_serviceable_hall_connections :: proc(t: ^testing.T) {
    archetypes := [3]buildings.Archetype{.Workshop, .Storehouse, .Fishery}
    sizes := [3][3]f32{{20, 16, 9.6}, {30, 24, 24}, {60, 36, 48}}
    for archetype in archetypes {
        for size in sizes {
            for seed in 0 ..< 128 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                if footprint.count != 3 do continue
                hall := footprint.masses[0]
                for shed, shed_offset in footprint.masses[1:footprint.count] {
                    overlap_z :=
                        min(hall.local_z + hall.depth * .5, shed.local_z + shed.depth * .5) -
                        max(hall.local_z - hall.depth * .5, shed.local_z - shed.depth * .5)
                    testing.expectf(
                        t,
                        overlap_z >= 2.0 - .001,
                        "productive court shed has a pinched hall connection archetype=%v size=(%.1f,%.1f,%.1f) seed=%d mass=%d overlap=%.2f",
                        archetype,
                        size[0],
                        size[1],
                        size[2],
                        seed,
                        shed_offset + 1,
                        overlap_z,
                    )
                    if overlap_z < 2.0 - .001 do return
                }
            }
        }
    }
}

@(test)
architecture_productive_service_wings_do_not_steal_the_main_entrance :: proc(t: ^testing.T) {
    archetypes := [3]buildings.Archetype{.Workshop, .Storehouse, .Fishery}
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    // These seeds cover the generic projecting service wing plus the
    // purpose-specific loading annex and smokehouse branches.
    seeds := [3]u32{1, 0, 0}
    for archetype, archetype_index in archetypes {
        structure.building.archetype = archetype
        structure.seed = seeds[archetype_index]
        footprint := architecture.architecture_footprint(structure)
        testing.expect_value(t, footprint.count, 2)
        testing.expect_value(t, architecture.architecture_frontage_mass_index(structure), 0)

        hall_layout := architecture.architecture_opening_layout(structure, 0, 0)
        hall_entries := 0
        for opening in hall_layout.openings[:hall_layout.count] {
            if opening.kind != .Door && opening.kind != .Service_Door do continue
            hall_entries += 1
            testing.expect(t, opening.face == .Front)
            testing.expect(
                t,
                !architecture.architecture_opening_occluded_by_mass(
                    footprint,
                    0,
                    opening.face,
                    opening.horizontal,
                    opening.y,
                    opening.width,
                    opening.height,
                    structure.height,
                ),
            )
        }
        testing.expectf(t, hall_entries == 1, "productive hall lacks one exposed entrance archetype=%v", archetype)

        frontage := architecture.architecture_frontage_structure(structure)
        hall_x, hall_z := architecture.architecture_mass_world(structure, footprint.masses[0])
        testing.expect(t, frontage.center_x == hall_x && frontage.center_z == hall_z)
        testing.expect(t, frontage.width == footprint.masses[0].width)
        testing.expect(t, frontage.depth == footprint.masses[0].depth)
    }
}

@(test)
architecture_small_civic_buildings_gain_distinct_connected_service_ranges :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 20, 16, 4, 18)
    // structure_make applies terrain-cell minimums. Restore the authored lot
    // so this regression actually exercises the compact civic branches.
    structure.width, structure.depth = 20, 16
    structure.kind = .Architecture

    structure.building.archetype = .Post_Office
    structure.seed = 10
    post := architecture.architecture_footprint(structure)
    testing.expect_value(t, post.count, 2)
    testing.expect(t, math.abs(post.masses[1].local_x) <= .001)
    testing.expect(t, post.masses[1].width < post.masses[0].width)
    testing.expect(t, post.masses[1].height_scale < post.masses[0].height_scale)

    structure.building.archetype = .Clinic
    clinic_left := architecture.architecture_footprint(structure)
    structure.seed = 11
    clinic_right := architecture.architecture_footprint(structure)
    testing.expect_value(t, clinic_left.count, 2)
    testing.expect_value(t, clinic_right.count, 2)
    testing.expect(t, clinic_left.masses[1].local_x < 0)
    testing.expect(t, clinic_right.masses[1].local_x > 0)
    testing.expect(t, clinic_left != post)

    cases := [2]struct {
        archetype: buildings.Archetype,
        seed:      u32,
    }{{.Post_Office, 10}, {.Clinic, 11}}
    for test_case in cases {
        structure.building.archetype = test_case.archetype
        structure.seed = test_case.seed
        footprint := architecture.architecture_footprint(structure)
        public_bar, service_range := footprint.masses[0], footprint.masses[1]
        overlap_x :=
            min(public_bar.local_x + public_bar.width * .5, service_range.local_x + service_range.width * .5) -
            max(public_bar.local_x - public_bar.width * .5, service_range.local_x - service_range.width * .5)
        overlap_z :=
            min(public_bar.local_z + public_bar.depth * .5, service_range.local_z + service_range.depth * .5) -
            max(public_bar.local_z - public_bar.depth * .5, service_range.local_z - service_range.depth * .5)
        testing.expect(t, overlap_x >= 1.20 && overlap_z >= 1.20)

        primary := architecture.architecture_frontage_mass_index(structure)
        testing.expect_value(t, primary, 0)
        layout := architecture.architecture_opening_layout(structure, 1, primary)
        rear_doors, windows := 0, 0
        for opening in layout.openings[:layout.count] {
            if opening.kind == .Service_Door {
                rear_doors += 1
                testing.expect(t, opening.face == .Rear)
            } else if opening.kind == .Window {
                windows += 1
            }
        }
        testing.expect_value(t, rear_doors, 1)
        testing.expectf(t, windows > 0, "civic service range lacks daylight archetype=%v", test_case.archetype)
    }
}

@(test)
architecture_civic_service_ranges_use_purpose_specific_daylight :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 24, 18, 4, 18)
    structure.kind = .Architecture
    structure.seed = 11

    structure.building.archetype = .Post_Office
    post_primary := architecture.architecture_frontage_mass_index(structure)
    post_layout := architecture.architecture_opening_layout(structure, 1, post_primary)
    post_windows := 0
    for opening in post_layout.openings[:post_layout.count] {
        if opening.kind != .Window do continue
        post_windows += 1
        testing.expect(t, opening.width >= .80 && opening.width <= 1.05)
        testing.expect(t, opening.height >= .95 && opening.height <= 1.30)
        testing.expect(t, opening.row < 2)
    }
    testing.expect(t, post_windows > 0)

    structure.building.archetype = .Clinic
    clinic_primary := architecture.architecture_frontage_mass_index(structure)
    clinic_layout := architecture.architecture_opening_layout(structure, 1, clinic_primary)
    clinic_windows := 0
    clinic_faces: [4]bool
    for opening in clinic_layout.openings[:clinic_layout.count] {
        if opening.kind != .Window do continue
        clinic_windows += 1
        clinic_faces[int(opening.face)] = true
        testing.expect(t, opening.width >= 1.20 && opening.width <= 1.50)
        testing.expect(t, opening.height >= 1.60 && opening.height <= 2.00)
        testing.expect(t, opening.row < 3)
    }
    exposed_faces := 0
    for found in clinic_faces do if found do exposed_faces += 1
    testing.expect(t, clinic_windows > post_windows)
    testing.expectf(t, exposed_faces >= 3, "clinic ward daylight reaches only %d faces", exposed_faces)
}

@(test)
architecture_broad_clinic_can_wrap_a_daylit_healing_court :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 24, 18, 4, 18)
    structure.kind = .Architecture
    structure.building.archetype = .Clinic
    for seed in 0 ..< 64 {
        if seed % 4 != 2 do continue
        structure.seed = u32(seed)
        footprint := architecture.architecture_footprint(structure)
        testing.expect_value(t, footprint.count, 3)
        primary := architecture.architecture_frontage_mass_index(structure)
        testing.expect_value(t, primary, 0)
        wing_window_counts: [2][4]int
        for wing_index in 1 ..= 2 {
            wing := footprint.masses[wing_index]
            testing.expect(t, math.abs(wing.local_x) > 0)
            layout := architecture.architecture_opening_layout(structure, wing_index, primary)
            rear_doors, court_doors := 0, 0
            expected_court_face := wing_index == 1 ? architecture.Face.Right : architecture.Face.Left
            window_faces: [4]bool
            for opening in layout.openings[:layout.count] {
                if opening.kind == .Service_Door {
                    if opening.face == .Rear do rear_doors += 1
                    if opening.face == expected_court_face do court_doors += 1
                } else if opening.kind == .Window {
                    window_faces[int(opening.face)] = true
                    wing_window_counts[wing_index - 1][int(opening.face)] += 1
                    testing.expect(t, opening.width >= .55)
                    testing.expect(t, opening.height >= .75)
                }
            }
            exposed_window_faces := 0
            for found in window_faces do if found do exposed_window_faces += 1
            testing.expect_value(t, rear_doors, 1)
            testing.expect_value(t, court_doors, 1)
            testing.expectf(
                t,
                exposed_window_faces >= 3,
                "clinic court wing %d reaches only %d daylit faces",
                wing_index,
                exposed_window_faces,
            )
        }
        testing.expect_value(
            t,
            wing_window_counts[0][int(architecture.Face.Front)],
            wing_window_counts[1][int(architecture.Face.Front)],
        )
        testing.expect_value(
            t,
            wing_window_counts[0][int(architecture.Face.Rear)],
            wing_window_counts[1][int(architecture.Face.Rear)],
        )
        testing.expect_value(
            t,
            wing_window_counts[0][int(architecture.Face.Left)],
            wing_window_counts[1][int(architecture.Face.Right)],
        )
        testing.expect_value(
            t,
            wing_window_counts[0][int(architecture.Face.Right)],
            wing_window_counts[1][int(architecture.Face.Left)],
        )
    }
}

@(test)
architecture_civic_rear_ranges_keep_serviceable_public_connections :: proc(t: ^testing.T) {
    archetypes := [4]buildings.Archetype{.Clinic, .Palace_Loggia, .Harbor_Office, .Monastery}
    sizes := [3][3]f32{{24, 18, 18}, {30, 24, 24}, {60, 36, 48}}
    for archetype in archetypes {
        for size in sizes {
            for seed in 0 ..< 128 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                if footprint.count <= 1 do continue
                public_range := footprint.masses[0]
                for rear_range, mass_index in footprint.masses[1:footprint.count] {
                    overlap_z :=
                        min(
                            public_range.local_z + public_range.depth * .5,
                            rear_range.local_z + rear_range.depth * .5,
                        ) -
                        max(
                            public_range.local_z - public_range.depth * .5,
                            rear_range.local_z - rear_range.depth * .5,
                        )
                    testing.expectf(
                        t,
                        overlap_z >= 2.0 - .001,
                        "civic rear range has a pinched public connection archetype=%v size=(%.1f,%.1f,%.1f) seed=%d mass=%d overlap=%.2f",
                        archetype,
                        size[0],
                        size[1],
                        size[2],
                        seed,
                        mass_index + 1,
                        overlap_z,
                    )
                    if overlap_z < 2.0 - .001 do return
                }
            }
        }
    }
}

@(test)
architecture_broad_post_office_adds_a_connected_parcel_annex :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 24, 18, 4, 18)
    structure.kind = .Architecture
    structure.building.archetype = .Post_Office
    for seed in 0 ..< 64 {
        if seed % 4 != 2 do continue
        structure.seed = u32(seed)
        footprint := architecture.architecture_footprint(structure)
        testing.expect_value(t, footprint.count, 3)
        primary := architecture.architecture_frontage_mass_index(structure)
        testing.expect_value(t, primary, 0)
        sorting := footprint.masses[1]
        annex := footprint.masses[2]
        overlap_x :=
            min(sorting.local_x + sorting.width * .5, annex.local_x + annex.width * .5) -
            max(sorting.local_x - sorting.width * .5, annex.local_x - annex.width * .5)
        overlap_z :=
            min(sorting.local_z + sorting.depth * .5, annex.local_z + annex.depth * .5) -
            max(sorting.local_z - sorting.depth * .5, annex.local_z - annex.depth * .5)
        testing.expectf(
            t,
            overlap_x >= 2.0 && overlap_z >= 1.20,
            "parcel annex has a pinched sorting-room transfer seed=%d overlap=(%.2f,%.2f)",
            seed,
            overlap_x,
            overlap_z,
        )
        for work_index in 1 ..= 2 {
            layout := architecture.architecture_opening_layout(structure, work_index, primary)
            rear_doors, windows := 0, 0
            for opening in layout.openings[:layout.count] {
                if opening.kind == .Service_Door {
                    rear_doors += 1
                    testing.expect(t, opening.face == .Rear)
                    if work_index == 1 {
                        testing.expectf(
                            t,
                            opening.width < 3.0,
                            "sorting-room staff door became cart-scale seed=%d",
                            seed,
                        )
                    } else {
                        testing.expectf(
                            t,
                            opening.width >= 3.0,
                            "parcel annex lacks cart-scale loading door seed=%d",
                            seed,
                        )
                        testing.expect(t, opening.height >= 3.4)
                    }
                } else if opening.kind == .Window {
                    windows += 1
                    testing.expect(t, opening.width >= .55 && opening.width <= 1.05)
                    testing.expect(t, opening.height >= .75 && opening.height <= 1.30)
                }
            }
            testing.expect_value(t, rear_doors, 1)
            testing.expectf(
                t,
                windows > 0,
                "post-office work range %d lacks secure daylight seed=%d",
                work_index,
                seed,
            )
        }
    }
    structure.seed = 11
    testing.expect_value(t, architecture.architecture_footprint(structure).count, 2)
}

@(test)
architecture_post_offices_keep_serviceable_public_to_sorting_connection :: proc(t: ^testing.T) {
    sizes := [5][3]f32 {
        {16, 14, 9.6},
        {18, 16, 12},
        {24, 18, 18},
        {30, 24, 24},
        {60, 36, 48},
    }
    for size in sizes {
        for seed in 0 ..< 128 {
            structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
            structure.width, structure.depth, structure.height = size[0], size[1], size[2]
            structure.kind = .Architecture
            structure.seed = u32(seed)
            structure.building.archetype = .Post_Office
            footprint := architecture.architecture_footprint(structure)
            testing.expect(t, footprint.count >= 2)
            public_hall, sorting_room := footprint.masses[0], footprint.masses[1]
            overlap_z :=
                min(public_hall.local_z + public_hall.depth * .5, sorting_room.local_z + sorting_room.depth * .5) -
                max(public_hall.local_z - public_hall.depth * .5, sorting_room.local_z - sorting_room.depth * .5)
            testing.expectf(
                t,
                overlap_z >= 2.0 - .001,
                "post office has a pinched public-to-sorting connection size=(%.1f,%.1f,%.1f) seed=%d ranges=%d overlap=%.2f",
                size[0],
                size[1],
                size[2],
                seed,
                footprint.count,
                overlap_z,
            )
        }
    }
}

@(test)
architecture_civic_ell_keeps_full_width_hall_on_street :: proc(t: ^testing.T) {
    archetypes := [4]buildings.Archetype{.Palace_Loggia, .Market_Hall, .Harbor_Office, .Monastery}
    structure := terrain.structure_make(1300, 1300, 18, 18, 4, 19.2)
    structure.kind = .Architecture
    structure.seed = 1
    for archetype in archetypes {
        structure.building.archetype = archetype
        footprint := architecture.architecture_footprint(structure)
        testing.expect_value(t, footprint.count, 2)
        primary := architecture.architecture_frontage_mass_index(structure)
        testing.expect_value(t, primary, 0)
        testing.expect(t, footprint.masses[0].width == structure.width)
        testing.expect(
            t,
            footprint.masses[1].local_z + footprint.masses[1].depth * .5 <
            footprint.masses[0].local_z + footprint.masses[0].depth * .5,
        )
        return_layout := architecture.architecture_opening_layout(structure, 1, primary)
        rear_service_doors := 0
        for opening in return_layout.openings[:return_layout.count] {
            if opening.kind == .Service_Door {
                rear_service_doors += 1
                testing.expect(t, opening.face == .Rear)
            }
        }
        testing.expect_value(t, rear_service_doors, 1)
    }
}

@(test)
architecture_market_hall_can_use_a_connected_clerestoried_basilica_plan :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    structure.building.archetype = .Market_Hall
    structure.seed = 2
    footprint := architecture.architecture_footprint(structure)
    testing.expect_value(t, footprint.count, 3)
    testing.expect_value(t, architecture.architecture_frontage_mass_index(structure), 0)
    nave := footprint.masses[0]
    testing.expect(t, nave.depth == structure.depth)
    testing.expect(t, nave.height_scale == 1)

    for aisle_index in 1 ..= 2 {
        aisle := footprint.masses[aisle_index]
        testing.expect(t, aisle.local_x * footprint.masses[3 - aisle_index].local_x < 0)
        testing.expect(t, aisle.height_scale < nave.height_scale)
        overlap_x :=
            min(nave.local_x + nave.width * .5, aisle.local_x + aisle.width * .5) -
            max(nave.local_x - nave.width * .5, aisle.local_x - aisle.width * .5)
        overlap_z :=
            min(nave.local_z + nave.depth * .5, aisle.local_z + aisle.depth * .5) -
            max(nave.local_z - nave.depth * .5, aisle.local_z - aisle.depth * .5)
        testing.expect(t, overlap_x >= 1.20 && overlap_z >= 1.20)
        aisle_layout := architecture.architecture_opening_layout(structure, aisle_index, 0)
        loading_doors := 0
        high_windows := 0
        for opening in aisle_layout.openings[:aisle_layout.count] {
            if opening.kind == .Service_Door {
                loading_doors += 1
                testing.expect(t, opening.face == .Rear)
                testing.expect(t, opening.width >= 3.4)
            } else if opening.kind == .Window {
                high_windows += 1
                testing.expect(t, opening.row == 0)
                testing.expect(t, opening.width >= 1.20 && opening.width <= 1.60)
                testing.expect(t, opening.height >= 1.20 && opening.height <= 1.70)
                testing.expect(t, opening.y >= structure.height * aisle.height_scale * .70)
            }
        }
        testing.expect_value(t, loading_doors, 1)
        testing.expectf(t, high_windows > 0, "market basilica aisle %d lacks high daylight", aisle_index)
    }

    nave_layout := architecture.architecture_opening_layout(structure, 0, 0)
    aisle_roof_y := structure.height * footprint.masses[1].height_scale
    clerestory_windows := 0
    for opening in nave_layout.openings[:nave_layout.count] {
        if opening.kind != .Window || (opening.face != .Left && opening.face != .Right) do continue
        if opening.y - opening.height * .5 >= aisle_roof_y - .001 do clerestory_windows += 1
    }
    testing.expectf(t, clerestory_windows >= 2, "market basilica lacks exposed side clerestory")
}

@(test)
architecture_market_basilica_keeps_serviceable_aisle_connections :: proc(t: ^testing.T) {
    sizes := [4][3]f32 {
        {22, 18, 9.6},
        {24, 18, 12},
        {30, 24, 24},
        {60, 36, 48},
    }
    for size in sizes {
        for seed in 0 ..< 64 {
            if seed % 4 != 2 do continue
            structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
            structure.width, structure.depth, structure.height = size[0], size[1], size[2]
            structure.kind = .Architecture
            structure.seed = u32(seed)
            structure.building.archetype = .Market_Hall
            footprint := architecture.architecture_footprint(structure)
            testing.expect_value(t, footprint.count, 3)
            nave := footprint.masses[0]
            for aisle_index in 1 ..= 2 {
                aisle := footprint.masses[aisle_index]
                overlap_x :=
                    min(nave.local_x + nave.width * .5, aisle.local_x + aisle.width * .5) -
                    max(nave.local_x - nave.width * .5, aisle.local_x - aisle.width * .5)
                testing.expectf(
                    t,
                    overlap_x >= 2.0 - .001,
                    "market aisle joins nave through a pinched passage size=(%.1f,%.1f,%.1f) seed=%d aisle=%d overlap=%.2f",
                    size[0],
                    size[1],
                    size[2],
                    seed,
                    aisle_index,
                    overlap_x,
                )
            }
        }
    }
}

@(test)
architecture_church_uses_connected_latin_cross_plan :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 18, 24, 4, 24)
    structure.kind = .Architecture
    structure.seed = 17
    structure.building.archetype = .Church
    footprint := architecture.architecture_footprint(structure)

    testing.expect_value(t, footprint.count, 3)
    nave, transept, chancel := footprint.masses[0], footprint.masses[1], footprint.masses[2]
    testing.expect(t, nave.local_z > transept.local_z && transept.local_z > chancel.local_z)
    testing.expect(t, transept.width == structure.width)
    testing.expect(t, transept.width > nave.width && nave.width > chancel.width)
    testing.expect(t, nave.height_scale > chancel.height_scale && chancel.height_scale > transept.height_scale)
    testing.expect_value(t, architecture.architecture_frontage_mass_index(structure), 0)

    nave_rear := nave.local_z - nave.depth * .5
    transept_front := transept.local_z + transept.depth * .5
    transept_rear := transept.local_z - transept.depth * .5
    chancel_front := chancel.local_z + chancel.depth * .5
    testing.expect(t, transept_front - nave_rear >= 1.20)
    testing.expect(t, chancel_front - transept_rear >= 1.20)

    primary := architecture.architecture_frontage_mass_index(structure)
    chancel_layout := architecture.architecture_opening_layout(structure, 2, primary)
    chancel_service_doors := 0
    for opening in chancel_layout.openings[:chancel_layout.count] {
        if opening.kind == .Service_Door {
            chancel_service_doors += 1
            testing.expect(t, opening.face == .Rear)
            testing.expect(t, math.abs(opening.horizontal) <= .001)
        }
    }
    testing.expect_value(t, chancel_service_doors, 1)
}

@(test)
architecture_church_keeps_serviceable_chancel_connection :: proc(t: ^testing.T) {
    sizes := [5][3]f32 {
        {12, 12, 9.6},
        {14, 14, 12},
        {18, 18, 18},
        {24, 24, 24},
        {30, 36, 48},
    }
    for size in sizes {
        for seed in 0 ..< 64 {
            structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
            structure.width, structure.depth, structure.height = size[0], size[1], size[2]
            structure.kind = .Architecture
            structure.seed = u32(seed)
            structure.building.archetype = .Church
            footprint := architecture.architecture_footprint(structure)
            testing.expect_value(t, footprint.count, 3)
            transept, chancel := footprint.masses[1], footprint.masses[2]
            overlap_z :=
                min(transept.local_z + transept.depth * .5, chancel.local_z + chancel.depth * .5) -
                max(transept.local_z - transept.depth * .5, chancel.local_z - chancel.depth * .5)
            testing.expectf(
                t,
                overlap_z >= 2.0 - .001,
                "church chancel has a pinched transept connection size=(%.1f,%.1f,%.1f) seed=%d overlap=%.2f",
                size[0],
                size[1],
                size[2],
                seed,
                overlap_z,
            )
        }
    }
}

@(test)
architecture_low_church_avoids_sealed_transept_and_chancel_ranges :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 12, 16, 4, 4.8)
    structure.width, structure.depth, structure.height = 12, 16, 4.8
    structure.kind = .Architecture
    structure.seed = 17
    structure.building.archetype = .Church

    low := architecture.architecture_footprint(structure)
    testing.expect_value(t, low.count, 1)
    low_layout := architecture.architecture_opening_layout(structure, 0, 0)
    front_doors, windows := 0, 0
    for opening in low_layout.openings[:low_layout.count] {
        if opening.face == .Front && opening.kind == .Door do front_doors += 1
        if opening.kind == .Window do windows += 1
    }
    testing.expect_value(t, front_doors, 1)
    testing.expectf(t, windows > 0, "low church hall lost all daylight")

    structure.height = 7.2
    tall := architecture.architecture_footprint(structure)
    testing.expect_value(t, tall.count, 3)
    primary := architecture.architecture_frontage_mass_index(structure)
    chancel_layout := architecture.architecture_opening_layout(structure, 2, primary)
    chancel_entries := 0
    for opening in chancel_layout.openings[:chancel_layout.count] {
        if opening.face == .Rear && opening.kind == .Service_Door do chancel_entries += 1
    }
    testing.expect_value(t, chancel_entries, 1)
}

@(test)
architecture_monastery_uses_front_open_cloister_court :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    structure.seed = 0
    structure.building.archetype = .Monastery
    footprint := architecture.architecture_footprint(structure)

    testing.expect_value(t, footprint.count, 3)
    communal, left_cells, right_cells := footprint.masses[0], footprint.masses[1], footprint.masses[2]
    testing.expect(t, communal.local_z < left_cells.local_z && communal.local_z < right_cells.local_z)
    testing.expect(t, communal.width == structure.width)
    testing.expect(t, left_cells.local_x < 0 && right_cells.local_x > 0)
    testing.expect(t, left_cells.width == right_cells.width && left_cells.depth == right_cells.depth)
    testing.expect(t, left_cells.local_z + left_cells.depth * .5 >= structure.depth * .5 - .001)
    testing.expect_value(t, architecture.architecture_frontage_mass_index(structure), 0)

    communal_front := communal.local_z + communal.depth * .5
    for cells in footprint.masses[1:3] {
        cells_rear := cells.local_z - cells.depth * .5
        testing.expect(t, communal_front - cells_rear >= 1.20)
    }
    exposed_front := architecture.architecture_exposed_face_area(footprint, 0, .Front, structure.height)
    expected_exposed :=
        communal.width * structure.height -
        (left_cells.width + right_cells.width) * structure.height * left_cells.height_scale
    testing.expect(t, math.abs(exposed_front - expected_exposed) <= .001)

    communal_layout := architecture.architecture_opening_layout(structure, 0, 0)
    public_doors, service_doors := 0, 0
    for opening in communal_layout.openings[:communal_layout.count] {
        if opening.kind == .Door {
            public_doors += 1
            testing.expect(t, opening.face == .Front)
        } else if opening.kind == .Service_Door {
            service_doors += 1
            testing.expect(t, opening.face == .Rear)
        }
    }
    testing.expect_value(t, public_doors, 1)
    testing.expect_value(t, service_doors, 1)

    for cell_index in 1 ..= 2 {
        cell_layout := architecture.architecture_opening_layout(structure, cell_index, 0)
        expected_court_face := cell_index == 1 ? architecture.Face.Right : architecture.Face.Left
        court_doors := 0
        for opening in cell_layout.openings[:cell_layout.count] {
            if opening.kind == .Service_Door && opening.face == expected_court_face {
                court_doors += 1
                testing.expect(
                    t,
                    !architecture.architecture_opening_occluded_by_mass(
                        footprint,
                        cell_index,
                        opening.face,
                        opening.horizontal,
                        opening.y,
                        opening.width,
                        opening.height,
                        structure.height,
                    ),
                )
            }
        }
        testing.expectf(t, court_doors == 1, "monastery cell range %d lacks cloister access", cell_index)
    }
}

@(test)
architecture_fortress_gate_forms_connected_guard_court :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 24, 18, 4, 24)
    structure.kind = .Architecture
    structure.seed = 11
    structure.building.archetype = .Fortress_Gate
    footprint := architecture.architecture_footprint(structure)

    testing.expect_value(t, footprint.count, 3)
    left, right, guard_range := footprint.masses[0], footprint.masses[1], footprint.masses[2]
    testing.expect(t, left.local_x < 0 && right.local_x > 0)
    testing.expect(t, left.local_z == right.local_z && left.width == right.width)
    tower_gap := right.local_x - right.width * .5 - (left.local_x + left.width * .5)
    testing.expect(t, tower_gap >= structure.width * .15)
    testing.expect(t, guard_range.width == structure.width)
    testing.expect(t, guard_range.local_z < left.local_z)
    testing.expect(t, guard_range.height_scale < left.height_scale)

    for tower in footprint.masses[:2] {
        overlap_x :=
            min(tower.local_x + tower.width * .5, guard_range.local_x + guard_range.width * .5) -
            max(tower.local_x - tower.width * .5, guard_range.local_x - guard_range.width * .5)
        overlap_z :=
            min(tower.local_z + tower.depth * .5, guard_range.local_z + guard_range.depth * .5) -
            max(tower.local_z - tower.depth * .5, guard_range.local_z - guard_range.depth * .5)
        testing.expect(t, overlap_x >= 1.20 && overlap_z >= 1.20)
    }

    primary := architecture.architecture_frontage_mass_index(structure)
    testing.expect_value(t, primary, 2)
    frontage := architecture.architecture_frontage_structure(structure)
    expected_frontage_x, expected_frontage_z := architecture.architecture_mass_world(structure, guard_range)
    testing.expect(t, frontage.center_x == expected_frontage_x && frontage.center_z == expected_frontage_z)
    testing.expect(t, frontage.width == guard_range.width && frontage.depth == guard_range.depth)
    tower_doors := 0
    tower_vents := 0
    tower_rows: [3]bool
    for tower_index in 0 ..< 2 {
        tower_layout := architecture.architecture_opening_layout(structure, tower_index, primary)
        for opening in tower_layout.openings[:tower_layout.count] {
            if opening.kind == .Door || opening.kind == .Service_Door do tower_doors += 1
            if opening.kind == .Vent {
                tower_vents += 1
                testing.expect(t, opening.width >= .38 && opening.width <= .55)
                testing.expect(t, opening.height >= 1.10 && opening.height <= 1.60)
                testing.expect(t, opening.row >= 0 && opening.row < len(tower_rows))
                tower_rows[opening.row] = true
            }
        }
    }
    testing.expect_value(t, tower_doors, 0)
    testing.expectf(t, tower_vents > 0, "fortress towers lack defensive vents")
    testing.expect(t, tower_rows[0] && tower_rows[1] && tower_rows[2])

    guard_layout := architecture.architecture_opening_layout(structure, 2, primary)
    found_court_entry := false
    for opening in guard_layout.openings[:guard_layout.count] {
        if opening.kind == .Service_Door && opening.face == .Front {
            found_court_entry = true
            testing.expect(t, math.abs(opening.horizontal) <= .001)
        }
        if opening.kind == .Vent {
            testing.expect(
                t,
                !architecture.opening_layout_conflicts_with_door(
                    &guard_layout,
                    opening.face,
                    opening.horizontal,
                    opening.y,
                    opening.width,
                    opening.height,
                ),
            )
        }
    }
    testing.expect(t, found_court_entry)
}

@(test)
architecture_fortress_gate_keeps_cart_scale_central_passage :: proc(t: ^testing.T) {
    sizes := [5][3]f32 {
        {12, 12, 7.2},
        {14, 12, 9.6},
        {18, 18, 12},
        {24, 18, 24},
        {30, 24, 48},
    }
    for size in sizes {
        for seed in 0 ..< 64 {
            structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
            structure.width, structure.depth, structure.height = size[0], size[1], size[2]
            structure.kind = .Architecture
            structure.seed = u32(seed)
            structure.building.archetype = .Fortress_Gate
            footprint := architecture.architecture_footprint(structure)
            testing.expect_value(t, footprint.count, 3)
            left, right, guard_range := footprint.masses[0], footprint.masses[1], footprint.masses[2]
            passage_width :=
                right.local_x - right.width * .5 -
                (left.local_x + left.width * .5)
            testing.expectf(
                t,
                passage_width >= 3.0 - .001,
                "fortress gate pinches its central passage size=(%.1f,%.1f,%.1f) seed=%d width=%.2f",
                size[0],
                size[1],
                size[2],
                seed,
                passage_width,
            )
            for tower in footprint.masses[:2] {
                overlap_z :=
                    min(tower.local_z + tower.depth * .5, guard_range.local_z + guard_range.depth * .5) -
                    max(tower.local_z - tower.depth * .5, guard_range.local_z - guard_range.depth * .5)
                testing.expectf(
                    t,
                    overlap_z >= 1.20,
                    "widened fortress passage detached tower from guard range size=(%.1f,%.1f) seed=%d overlap=%.2f",
                    size[0],
                    size[1],
                    seed,
                    overlap_z,
                )
            }
        }
    }
}

@(test)
architecture_low_fortress_avoids_a_sealed_guard_range :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 12, 12, 4, 4.8)
    structure.width, structure.depth, structure.height = 12, 12, 4.8
    structure.kind = .Architecture
    structure.seed = 11
    structure.building.archetype = .Fortress_Gate

    low := architecture.architecture_footprint(structure)
    testing.expect_value(t, low.count, 1)
    low_layout := architecture.architecture_opening_layout(structure, 0, 0)
    low_front_doors := 0
    for opening in low_layout.openings[:low_layout.count] {
        if opening.face == .Front && opening.kind == .Service_Door do low_front_doors += 1
    }
    testing.expect_value(t, low_front_doors, 1)

    structure.height = 7.2
    tall := architecture.architecture_footprint(structure)
    testing.expect_value(t, tall.count, 3)
    primary := architecture.architecture_frontage_mass_index(structure)
    testing.expect_value(t, primary, 2)
    guard_layout := architecture.architecture_opening_layout(structure, primary, primary)
    guard_entries := 0
    for opening in guard_layout.openings[:guard_layout.count] {
        if opening.face == .Front && opening.kind == .Service_Door do guard_entries += 1
    }
    testing.expect_value(t, guard_entries, 1)
}

@(test)
architecture_campanile_uses_slender_square_tower_and_stacked_slits :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 30)
    structure.kind = .Architecture
    structure.seed = 17
    structure.building.archetype = .Campanile
    footprint := architecture.architecture_footprint(structure)
    testing.expect_value(t, footprint.count, 1)
    tower := footprint.masses[0]
    testing.expect(t, tower.width == tower.depth)
    testing.expect(t, tower.width <= 8 && tower.width < structure.width * .5)
    frontage := architecture.architecture_frontage_structure(structure)
    testing.expect(t, frontage.width == tower.width && frontage.depth == tower.depth)

    layout := architecture.architecture_opening_layout(structure, 0, 0)
    rows: [4]bool
    row_counts: [4]int
    top_faces: [4]bool
    vents, doors := 0, 0
    for opening in layout.openings[:layout.count] {
        if opening.kind == .Door || opening.kind == .Service_Door do doors += 1
        if opening.kind != .Vent do continue
        vents += 1
        testing.expect(t, opening.width >= .50 && opening.width <= .75)
        testing.expect(t, opening.height >= 1.10 && opening.height <= 1.70)
        testing.expect(t, opening.row >= 0 && opening.row < len(rows))
        rows[opening.row] = true
        row_counts[opening.row] += 1
        if opening.row == len(rows) - 1 do top_faces[int(opening.face)] = true
    }
    testing.expect_value(t, doors, 1)
    testing.expect(t, vents > 0)
    for found in rows do testing.expect(t, found)
    for row in 0 ..< len(rows) - 1 do testing.expect_value(t, row_counts[row], 1)
    testing.expect_value(t, row_counts[len(rows) - 1], 4)
    for found in top_faces do testing.expect(t, found)

    structure.building.archetype = .Cycladic_Bell
    cycladic := architecture.architecture_footprint(structure)
    cycladic_frontage := architecture.architecture_frontage_structure(structure)
    testing.expect(t, cycladic_frontage.width == cycladic.masses[0].width)
    testing.expect(t, cycladic_frontage.depth == cycladic.masses[0].depth)
    testing.expect(t, cycladic.masses[0].width <= 8.0 && cycladic.masses[0].depth <= 6.5)
    testing.expect(t, cycladic.masses[0].width > cycladic.masses[0].depth)
    testing.expect(t, cycladic.masses[0].depth < structure.depth * .5)

    structure.width, structure.depth = 8, 3
    shallow := architecture.architecture_footprint(structure)
    testing.expect(t, shallow.masses[0].width <= structure.width)
    testing.expect(t, shallow.masses[0].depth <= structure.depth)
    testing.expect(t, shallow.masses[0].depth > 0)
}

@(test)
architecture_shallow_bell_landmarks_keep_front_door_and_slits :: proc(t: ^testing.T) {
    archetypes := [2]buildings.Archetype{.Campanile, .Cycladic_Bell}
    structure := terrain.structure_make(1300, 1300, 8, 3, 4, 9.6)
    structure.width, structure.depth, structure.height = 8, 3, 9.6
    structure.kind = .Architecture
    structure.seed = 5
    for archetype in archetypes {
        structure.building.archetype = archetype
        footprint := architecture.architecture_footprint(structure)
        testing.expect_value(t, footprint.count, 1)
        testing.expect(t, footprint.masses[0].width >= architecture.ARCHITECTURE_MIN_OPENING_FACE_SPAN)
        testing.expect(t, footprint.masses[0].depth <= structure.depth)
        layout := architecture.architecture_opening_layout(structure, 0, 0)
        front_door, front_slits := 0, 0
        for opening in layout.openings[:layout.count] {
            if opening.face != .Front do continue
            if opening.kind == .Door || opening.kind == .Service_Door do front_door += 1
            if opening.kind == .Vent do front_slits += 1
        }
        testing.expectf(t, front_door == 1, "shallow bell landmark lacks front door archetype=%v", archetype)
        testing.expectf(t, front_slits > 0, "shallow bell landmark lacks front slits archetype=%v", archetype)
    }
}

@(test)
architecture_compound_floorplans_stay_inside_the_authored_lot_envelope :: proc(t: ^testing.T) {
    archetypes := []buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Post_Office,
        .Clinic,
        .Workshop,
        .Storehouse,
        .Fishery,
        .Barn_Granary,
        .Mill,
        .Palace_Loggia,
        .Market_Hall,
        .Harbor_Office,
        .Monastery,
        .Church,
        .Campanile,
        .Fortress_Gate,
        .Cycladic_Bell,
        .Lighthouse,
    }
    sizes := [9][2]f32{{8, 3}, {14, 3}, {24, 6}, {8, 8}, {12, 12}, {14, 14}, {18, 18}, {22, 18}, {30, 24}}
    for archetype in archetypes {
        for size in sizes {
            for seed in 0 ..< 32 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, 24)
                structure.width, structure.depth = size[0], size[1]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                for mass, mass_index in footprint.masses[:footprint.count] {
                    inside_x := math.abs(mass.local_x) + mass.width * .5 <= structure.width * .5 + .001
                    inside_z := math.abs(mass.local_z) + mass.depth * .5 <= structure.depth * .5 + .001
                    if !inside_x || !inside_z {
                        testing.expectf(
                            t,
                            false,
                            "footprint escaped lot archetype=%v seed=%d size=(%.1f,%.1f) mass=%d pose=(%.2f,%.2f,%.2f,%.2f)",
                            archetype,
                            seed,
                            size[0],
                            size[1],
                            mass_index,
                            mass.local_x,
                            mass.local_z,
                            mass.width,
                            mass.depth,
                        )
                        return
                    }
                }
            }
        }
    }
}

@(test)
architecture_compound_floorplans_stay_inside_threshold_adjacent_lots :: proc(t: ^testing.T) {
    archetypes := []buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Post_Office,
        .Clinic,
        .Workshop,
        .Storehouse,
        .Fishery,
        .Barn_Granary,
        .Mill,
        .Palace_Loggia,
        .Market_Hall,
        .Harbor_Office,
        .Monastery,
        .Church,
        .Campanile,
        .Fortress_Gate,
        .Cycladic_Bell,
        .Lighthouse,
    }
    // Exercise every integer dimension around the 8, 9, 12, 14, 16, 18,
    // 20, 22, 24, and 26 metre plan gates. This catches minimum-room clamps
    // that are safe on canonical lots but escape on a threshold-adjacent lot.
    // Include upper-bit samples because façade counts read distinct slices at
    // bits 9, 12, 15, and 18; a low consecutive seed range cannot exercise
    // those authored variations.
    seeds := [32]u32 {
        0, 1, 2, 3, 4, 5, 6, 7,
        8, 9, 10, 11, 12, 13, 14, 15,
        0x00000100, 0x00000101,
        0x00001000, 0x00001001,
        0x00010000, 0x00010001,
        0x00100000, 0x00100001,
        0x01000000, 0x01000001,
        0x10000000, 0x10000001,
        0x55555555, 0xaaaaaaaa, 0xdeadbeef, 0xffffffff,
    }
    for archetype in archetypes {
        for width in 3 ..= 32 {
            for depth in 3 ..= 30 {
                for seed in seeds {
                    structure := terrain.structure_make(1300, 1300, f32(width), f32(depth), 4, 24)
                    structure.width, structure.depth = f32(width), f32(depth)
                    structure.kind = .Architecture
                    structure.seed = seed
                    structure.building.archetype = archetype
                    footprint := architecture.architecture_footprint(structure)
                    primary := architecture.architecture_frontage_mass_index(structure)
                    for mass, mass_index in footprint.masses[:footprint.count] {
                        testing.expectf(
                            t,
                            math.abs(mass.local_x) + mass.width * .5 <= structure.width * .5 + .001 &&
                            math.abs(mass.local_z) + mass.depth * .5 <= structure.depth * .5 + .001,
                            "threshold-adjacent footprint escaped lot archetype=%v seed=%d size=(%d,%d) mass=%d pose=(%.2f,%.2f,%.2f,%.2f)",
                            archetype,
                            seed,
                            width,
                            depth,
                            mass_index,
                            mass.local_x,
                            mass.local_z,
                            mass.width,
                            mass.depth,
                        )
                        if footprint.count > 1 {
                            testing.expectf(
                                t,
                                mass.width >= 4.5 && mass.depth >= 4.5,
                                "threshold-adjacent compound made an unusable range archetype=%v seed=%d size=(%d,%d) mass=%d dimensions=(%.2f,%.2f)",
                                archetype,
                                seed,
                                width,
                                depth,
                                mass_index,
                                mass.width,
                                mass.depth,
                            )
                        }
                        layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                        wall_height := structure.height * mass.height_scale
                        for opening in layout.openings[:layout.count] {
                            span := architecture.face_span(mass, opening.face)
                            testing.expectf(
                                t,
                                math.abs(opening.horizontal) + opening.width * .5 <=
                                    span * .5 - architecture.ARCHITECTURE_OPENING_CORNER_MARGIN + .001 &&
                                opening.y - opening.height * .5 >= -.001 &&
                                opening.y + opening.height * .5 <= wall_height + .001,
                                "threshold-adjacent opening escaped wall archetype=%v seed=%d size=(%d,%d) mass=%d face=%v opening=(%.2f,%.2f,%.2f,%.2f) wall=(%.2f,%.2f)",
                                archetype,
                                seed,
                                width,
                                depth,
                                mass_index,
                                opening.face,
                                opening.horizontal,
                                opening.y,
                                opening.width,
                                opening.height,
                                span,
                                wall_height,
                            )
                            testing.expectf(
                                t,
                                !architecture.architecture_opening_occluded_by_mass(
                                    footprint,
                                    mass_index,
                                    opening.face,
                                    opening.horizontal,
                                    opening.y,
                                    opening.width,
                                    opening.height,
                                    structure.height,
                                ),
                                "threshold-adjacent opening buried in join archetype=%v seed=%d size=(%d,%d) mass=%d face=%v",
                                archetype,
                                seed,
                                width,
                                depth,
                                mass_index,
                                opening.face,
                            )
                        }
                        for a, a_index in layout.openings[:layout.count] {
                            for b in layout.openings[a_index + 1:layout.count] {
                                if a.face != b.face do continue
                                vertical_overlap :=
                                    math.abs(a.y - b.y) < (a.height + b.height) * .5 - .001
                                if !vertical_overlap do continue
                                a_is_door := a.kind == .Door || a.kind == .Service_Door
                                b_is_door := b.kind == .Door || b.kind == .Service_Door
                                // Windows, vents, and arcade openings need a
                                // material masonry pier, not merely a
                                // mathematically non-overlapping edge.
                                required_gap := architecture.ARCHITECTURE_WINDOW_PIER_MARGIN
                                if a_is_door != b_is_door {
                                    required_gap = architecture.ARCHITECTURE_DOOR_WINDOW_MARGIN
                                } else if a_is_door && b_is_door {
                                    required_gap = 0
                                }
                                horizontal_gap :=
                                    math.abs(a.horizontal - b.horizontal) -
                                    (a.width + b.width) * .5
                                if horizontal_gap < required_gap - .001 {
                                    testing.expectf(
                                        t,
                                        false,
                                        "threshold-adjacent openings collide archetype=%v seed=%d size=(%d,%d) mass=%d face=%v a=(%v,x%.2f,y%.2f,w%.2f,h%.2f) b=(%v,x%.2f,y%.2f,w%.2f,h%.2f) gap=%.2f required=%.2f",
                                        archetype,
                                        seed,
                                        width,
                                        depth,
                                        mass_index,
                                        a.face,
                                        a.kind,
                                        a.horizontal,
                                        a.y,
                                        a.width,
                                        a.height,
                                        b.kind,
                                        b.horizontal,
                                        b.y,
                                        b.width,
                                        b.height,
                                        horizontal_gap,
                                        required_gap,
                                    )
                                    return
                                }
                            }
                        }
                    }
                    if footprint.count > 1 {
                        reachable: [3]bool
                        reachable[0] = true
                        for _ in 0 ..< footprint.count {
                            for mass, mass_index in footprint.masses[:footprint.count] {
                                if !reachable[mass_index] do continue
                                for other, other_index in footprint.masses[:footprint.count] {
                                    if reachable[other_index] do continue
                                    overlap_x :=
                                        math.abs(mass.local_x - other.local_x) <=
                                        (mass.width + other.width) * .5 - 2.0
                                    overlap_z :=
                                        math.abs(mass.local_z - other.local_z) <=
                                        (mass.depth + other.depth) * .5 - 2.0
                                    if overlap_x && overlap_z do reachable[other_index] = true
                                }
                            }
                        }
                        for _, mass_index in footprint.masses[:footprint.count] {
                            if !reachable[mass_index] {
                                testing.expectf(
                                    t,
                                    false,
                                    "threshold-adjacent compound lacks a 2m connection archetype=%v seed=%d size=(%d,%d) mass=%d",
                                    archetype,
                                    seed,
                                    width,
                                    depth,
                                    mass_index,
                                )
                                return
                            }
                        }
                    }
                }
            }
        }
    }
}

@(test)
architecture_compound_floorplans_form_connected_building_shapes :: proc(t: ^testing.T) {
    archetypes := []buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Post_Office,
        .Clinic,
        .Workshop,
        .Storehouse,
        .Fishery,
        .Barn_Granary,
        .Mill,
        .Palace_Loggia,
        .Harbor_Office,
        .Market_Hall,
        .Monastery,
        .Church,
        .Fortress_Gate,
    }
    sizes := [12][2]f32 {
        {14, 3},
        {24, 6},
        {8, 8},
        {12, 12},
        {14, 14},
        {16, 14},
        {18, 18},
        {20, 16},
        {22, 18},
        {26, 20},
        {30, 24},
        {60, 36},
    }
    for archetype in archetypes {
        for size in sizes {
            for seed in 0 ..< 128 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, 24)
                structure.width, structure.depth = size[0], size[1]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                if footprint.count <= 1 do continue

                connected: [3]bool
                connected[0] = true
                for _ in 1 ..< footprint.count {
                    for candidate_index in 0 ..< footprint.count {
                        if connected[candidate_index] do continue
                        candidate := footprint.masses[candidate_index]
                        for existing_index in 0 ..< footprint.count {
                            if !connected[existing_index] do continue
                            existing := footprint.masses[existing_index]
                            // A corner or edge touch is not a usable interior
                            // connection. Require a full two-metre shared band
                            // in both axes for circulation between ranges.
                            overlap_x :=
                                math.abs(candidate.local_x - existing.local_x) <=
                                (candidate.width + existing.width) * .5 - 2.0
                            overlap_z :=
                                math.abs(candidate.local_z - existing.local_z) <=
                                (candidate.depth + existing.depth) * .5 - 2.0
                            if overlap_x && overlap_z {
                                connected[candidate_index] = true
                                break
                            }
                        }
                    }
                }
                for connected_mass, mass_index in connected[:footprint.count] {
                    if !connected_mass {
                        testing.expectf(
                            t,
                            false,
                            "mass lacks a serviceable compound connection archetype=%v seed=%d size=(%.1f,%.1f) mass=%d",
                            archetype,
                            seed,
                            size[0],
                            size[1],
                            mass_index,
                        )
                        return
                    }
                }
            }
        }
    }
}

@(test)
architecture_compound_masses_keep_a_program_legible_exterior_perimeter :: proc(t: ^testing.T) {
    archetypes := [18]buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Post_Office,
        .Clinic,
        .Palace_Loggia,
        .Harbor_Office,
        .Monastery,
        .Workshop,
        .Storehouse,
        .Fishery,
        .Barn_Granary,
        .Mill,
        .Market_Hall,
        .Church,
        .Fortress_Gate,
    }
    sizes := [3][3]f32{{18, 18, 9.6}, {30, 24, 24}, {60, 36, 48}}
    faces := [4]architecture.Face{.Front, .Rear, .Left, .Right}
    for archetype in archetypes {
        for size in sizes {
            for seed in 0 ..< 128 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                if footprint.count <= 1 do continue
                for mass, mass_index in footprint.masses[:footprint.count] {
                    if archetype == .Mill && mass_index == 1 do continue
                    wall_height := structure.height * mass.height_scale
                    total_wall_area := 2 * (mass.width + mass.depth) * wall_height
                    exposed_wall_area := f32(0)
                    for face in faces {
                        exposed_wall_area += architecture.architecture_exposed_face_area(
                            footprint,
                            mass_index,
                            face,
                            structure.height,
                        )
                    }
                    exposure_ratio := exposed_wall_area / max(total_wall_area, f32(.001))
                    minimum_exposure :=
                        (buildings.is_habitable(archetype) || archetype == .Post_Office) ? f32(.50) : f32(.40)
                    if exposure_ratio < minimum_exposure {
                        testing.expectf(
                            t,
                            false,
                            "compound mass is nearly swallowed archetype=%v size=(%.1f,%.1f,%.1f) seed=%d mass=%d exposure=%.3f target=%.2f dimensions=(%.2f,%.2f,%.2f)",
                            archetype,
                            size[0],
                            size[1],
                            size[2],
                            seed,
                            mass_index,
                            exposure_ratio,
                            minimum_exposure,
                            mass.width,
                            mass.depth,
                            wall_height,
                        )
                        return
                    }
                }
            }
        }
    }
}

@(test)
architecture_fortress_guard_range_vents_its_exposed_rear_wall :: proc(t: ^testing.T) {
    sizes := [3][3]f32{{18, 18, 9.6}, {30, 24, 24}, {60, 36, 48}}
    for size in sizes {
        for seed in 0 ..< 128 {
            structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
            structure.width, structure.depth, structure.height = size[0], size[1], size[2]
            structure.kind = .Architecture
            structure.seed = u32(seed)
            structure.building.archetype = .Fortress_Gate
            footprint := architecture.architecture_footprint(structure)
            if footprint.count != 3 do continue
            primary := architecture.architecture_frontage_mass_index(structure)
            guard_index := 2
            layout := architecture.architecture_opening_layout(structure, guard_index, primary)
            rear_vents := 0
            for opening in layout.openings[:layout.count] {
                if opening.face == .Rear && opening.kind == .Vent do rear_vents += 1
            }
            testing.expectf(
                t,
                rear_vents > 0,
                "fortress guard range left its exposed rear wall unventilated size=(%.1f,%.1f,%.1f) seed=%d",
                size[0],
                size[1],
                size[2],
                seed,
            )
        }
    }
}

@(test)
architecture_domestic_u_plan_wings_overlook_the_rear_court :: proc(t: ^testing.T) {
    archetypes := [2]buildings.Archetype{.Dwelling, .Farmstead}
    for archetype in archetypes {
        for seed in 3 ..< 128 {
            if seed % 8 != 3 do continue
            structure := terrain.structure_make(1300, 1300, 30, 24, 4, 19.2)
            structure.width, structure.depth, structure.height = 30, 24, 19.2
            structure.kind = .Architecture
            structure.seed = u32(seed)
            structure.building.archetype = archetype
            footprint := architecture.architecture_footprint(structure)
            // Farmstead's one-in-five productive range owns some eligible
            // seeds; only inspect variants that actually resolve to the U.
            if footprint.count != 3 do continue
            primary := architecture.architecture_frontage_mass_index(structure)
            for mass_index in 1 ..< footprint.count {
                court_face := mass_index == 1 ? architecture.Face.Right : architecture.Face.Left
                layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                court_windows := 0
                for opening in layout.openings[:layout.count] {
                    if opening.face == court_face && opening.kind == .Window {
                        court_windows += 1
                    }
                }
                testing.expectf(
                    t,
                    court_windows > 0,
                    "domestic U-plan wing has a blank court wall archetype=%v seed=%d mass=%d face=%v",
                    archetype,
                    seed,
                    mass_index,
                    court_face,
                )
            }
        }
    }
}

@(test)
architecture_domestic_u_plan_wings_keep_serviceable_street_range_connections :: proc(t: ^testing.T) {
    archetypes := [2]buildings.Archetype{.Dwelling, .Farmstead}
    sizes := [3][3]f32{{26, 20, 9.6}, {30, 24, 19.2}, {60, 36, 48}}
    for archetype in archetypes {
        for size in sizes {
            for seed in 0 ..< 128 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                if footprint.count != 3 do continue
                street_range := footprint.masses[0]
                for wing, wing_offset in footprint.masses[1:footprint.count] {
                    overlap_z :=
                        min(street_range.local_z + street_range.depth * .5, wing.local_z + wing.depth * .5) -
                        max(street_range.local_z - street_range.depth * .5, wing.local_z - wing.depth * .5)
                    testing.expectf(
                        t,
                        overlap_z >= 2.0 - .001,
                        "domestic U-plan wing has a pinched street-range connection archetype=%v size=(%.1f,%.1f,%.1f) seed=%d mass=%d overlap=%.2f",
                        archetype,
                        size[0],
                        size[1],
                        size[2],
                        seed,
                        wing_offset + 1,
                        overlap_z,
                    )
                    if overlap_z < 2.0 - .001 do return
                }
            }
        }
    }
}

@(test)
architecture_clinic_and_mixed_use_wings_overlook_their_courts :: proc(t: ^testing.T) {
    cases := [2]struct {
        archetype: buildings.Archetype,
        seeds:      [2]u32,
    } {
        {.Clinic, {2, 6}},
        {.Mixed_Use_Dwelling, {5, 11}},
    }
    for test_case in cases {
        for seed in test_case.seeds {
            structure := terrain.structure_make(1300, 1300, 30, 24, 4, 19.2)
            structure.width, structure.depth, structure.height = 30, 24, 19.2
            structure.kind = .Architecture
            structure.seed = seed
            structure.building.archetype = test_case.archetype
            footprint := architecture.architecture_footprint(structure)
            testing.expect_value(t, footprint.count, 3)
            primary := architecture.architecture_frontage_mass_index(structure)
            for mass_index in 1 ..< footprint.count {
                court_face := mass_index == 1 ? architecture.Face.Right : architecture.Face.Left
                layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                court_windows := 0
                for opening in layout.openings[:layout.count] {
                    if opening.face == court_face && opening.kind == .Window {
                        court_windows += 1
                    }
                }
                testing.expectf(
                    t,
                    court_windows > 0,
                    "inhabited court wing has a blank inner wall archetype=%v seed=%d mass=%d face=%v",
                    test_case.archetype,
                    seed,
                    mass_index,
                    court_face,
                )
            }
        }
    }
}

@(test)
architecture_mixed_use_private_ranges_keep_serviceable_shop_connections :: proc(t: ^testing.T) {
    sizes := [4][3]f32{{14, 14, 9.6}, {18, 16, 14.4}, {22, 18, 19.2}, {30, 24, 48}}
    for size in sizes {
        for seed in 0 ..< 128 {
            structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
            structure.width, structure.depth, structure.height = size[0], size[1], size[2]
            structure.kind = .Architecture
            structure.seed = u32(seed)
            structure.building.archetype = .Mixed_Use_Dwelling
            footprint := architecture.architecture_footprint(structure)
            testing.expectf(
                t,
                footprint.count > 1,
                "eligible mixed-use building lost private range size=(%.1f,%.1f,%.1f) seed=%d",
                size[0],
                size[1],
                size[2],
                seed,
            )
            shop := footprint.masses[0]
            for private_range, range_offset in footprint.masses[1:footprint.count] {
                overlap_z :=
                    min(shop.local_z + shop.depth * .5, private_range.local_z + private_range.depth * .5) -
                    max(shop.local_z - shop.depth * .5, private_range.local_z - private_range.depth * .5)
                testing.expectf(
                    t,
                    overlap_z >= 2.0 - .001,
                    "mixed-use private range has a pinched shop connection size=(%.1f,%.1f,%.1f) seed=%d mass=%d overlap=%.2f",
                    size[0],
                    size[1],
                    size[2],
                    seed,
                    range_offset + 1,
                    overlap_z,
                )
                if overlap_z < 2.0 - .001 do return
            }
        }
    }
}

@(test)
architecture_shop_house_stockrooms_keep_serviceable_sales_floor_connections :: proc(t: ^testing.T) {
    sizes := [4][3]f32{{16, 14, 9.6}, {18, 16, 14.4}, {24, 20, 24}, {60, 36, 48}}
    for size in sizes {
        for seed in 0 ..< 128 {
            if seed % 4 != 0 do continue
            structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
            structure.width, structure.depth, structure.height = size[0], size[1], size[2]
            structure.kind = .Architecture
            structure.seed = u32(seed)
            structure.building.archetype = .Shop_House
            footprint := architecture.architecture_footprint(structure)
            testing.expect_value(t, footprint.count, 2)
            sales, stock := footprint.masses[0], footprint.masses[1]
            overlap_z :=
                min(sales.local_z + sales.depth * .5, stock.local_z + stock.depth * .5) -
                max(sales.local_z - sales.depth * .5, stock.local_z - stock.depth * .5)
            testing.expectf(
                t,
                overlap_z >= 2.0 - .001,
                "shop stockroom has a pinched sales-floor connection size=(%.1f,%.1f,%.1f) seed=%d overlap=%.2f",
                size[0],
                size[1],
                size[2],
                seed,
                overlap_z,
            )
            if overlap_z < 2.0 - .001 do return
        }
    }
}

@(test)
architecture_attached_rear_returns_keep_serviceable_internal_passage :: proc(t: ^testing.T) {
    archetypes := [2]buildings.Archetype{.Townhouse, .Shop_House}
    sizes := [4][3]f32 {
        {16, 16, 9.6},
        {18, 18, 12},
        {24, 20, 24},
        {30, 24, 48},
    }
    for archetype in archetypes {
        for size in sizes {
            for seed in 0 ..< 64 {
                if seed % 6 != 1 do continue
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                testing.expect_value(t, footprint.count, 2)
                street_range, rear_return := footprint.masses[0], footprint.masses[1]
                overlap_z :=
                    min(street_range.local_z + street_range.depth * .5, rear_return.local_z + rear_return.depth * .5) -
                    max(street_range.local_z - street_range.depth * .5, rear_return.local_z - rear_return.depth * .5)
                testing.expectf(
                    t,
                    overlap_z >= 2.0 - .001,
                    "attached rear return has a pinched internal passage archetype=%v size=(%.1f,%.1f,%.1f) seed=%d overlap=%.2f",
                    archetype,
                    size[0],
                    size[1],
                    size[2],
                    seed,
                    overlap_z,
                )
            }
        }
    }
}

@(test)
architecture_stepped_townhouse_bars_keep_serviceable_internal_connections :: proc(t: ^testing.T) {
    archetypes := [2]buildings.Archetype{.Townhouse, .Shop_House}
    sizes := [4][3]f32{{12, 12, 9.6}, {16, 14, 14.4}, {24, 20, 24}, {60, 36, 48}}
    for archetype in archetypes {
        exercised := 0
        for size in sizes {
            for seed in 0 ..< 128 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                if footprint.count != 2 || math.abs(footprint.masses[0].local_x) < .001 do continue
                first, second := footprint.masses[0], footprint.masses[1]
                overlap_x :=
                    min(first.local_x + first.width * .5, second.local_x + second.width * .5) -
                    max(first.local_x - first.width * .5, second.local_x - second.width * .5)
                testing.expectf(
                    t,
                    overlap_x >= 2.0 - .001,
                    "stepped bars have a pinched internal connection archetype=%v size=(%.1f,%.1f,%.1f) seed=%d overlap=%.2f",
                    archetype,
                    size[0],
                    size[1],
                    size[2],
                    seed,
                    overlap_x,
                )
                if overlap_x < 2.0 - .001 do return
                exercised += 1
            }
        }
        testing.expectf(t, exercised > 0, "stepped topology was never exercised archetype=%v", archetype)
    }
}

@(test)
architecture_domestic_t_plans_keep_serviceable_internal_passage :: proc(t: ^testing.T) {
    archetypes := [2]buildings.Archetype{.Dwelling, .Farmstead}
    sizes := [4][3]f32 {
        {18, 18, 9.6},
        {22, 20, 12},
        {30, 24, 24},
        {60, 36, 48},
    }
    for archetype in archetypes {
        for size in sizes {
            for seed in 0 ..< 128 {
                if seed % 8 != 6 do continue
                if archetype == .Farmstead && seed % 5 == 0 do continue
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                testing.expect_value(t, footprint.count, 2)
                street_range, rear_range := footprint.masses[0], footprint.masses[1]
                testing.expect(t, math.abs(rear_range.local_x) <= .001)
                overlap_z :=
                    min(street_range.local_z + street_range.depth * .5, rear_range.local_z + rear_range.depth * .5) -
                    max(street_range.local_z - street_range.depth * .5, rear_range.local_z - rear_range.depth * .5)
                testing.expectf(
                    t,
                    overlap_z >= 2.0 - .001,
                    "domestic T-plan has a pinched internal passage archetype=%v size=(%.1f,%.1f,%.1f) seed=%d overlap=%.2f",
                    archetype,
                    size[0],
                    size[1],
                    size[2],
                    seed,
                    overlap_z,
                )
            }
        }
    }
}

@(test)
architecture_multi_storey_rear_returns_keep_lower_and_upper_daylight :: proc(t: ^testing.T) {
    cases := [5]struct {
        archetype: buildings.Archetype,
        seed:      u32,
    } {
        {.Dwelling, 1},
        {.Townhouse, 1},
        {.Mixed_Use_Dwelling, 0},
        {.Post_Office, 0},
        {.Clinic, 0},
    }
    for test_case in cases {
        structure := terrain.structure_make(1300, 1300, 18, 18, 4, 19.2)
        structure.width, structure.depth, structure.height = 18, 18, 19.2
        structure.kind = .Architecture
        structure.seed = test_case.seed
        structure.building.archetype = test_case.archetype
        footprint := architecture.architecture_footprint(structure)
        testing.expect_value(t, footprint.count, 2)
        primary := architecture.architecture_frontage_mass_index(structure)
        secondary := primary == 0 ? 1 : 0
        layout := architecture.architecture_opening_layout(structure, secondary, primary)
        lower_windows, upper_windows := 0, 0
        for opening in layout.openings[:layout.count] {
            if opening.kind != .Window do continue
            if opening.row == 0 {
                lower_windows += 1
            } else {
                upper_windows += 1
            }
        }
        testing.expectf(
            t,
            lower_windows > 0,
            "multi-storey return lacks lower-room daylight archetype=%v seed=%d",
            test_case.archetype,
            test_case.seed,
        )
        testing.expectf(
            t,
            upper_windows > 0,
            "multi-storey return lacks upper-room daylight archetype=%v seed=%d",
            test_case.archetype,
            test_case.seed,
        )
    }
}

@(test)
architecture_occupied_multi_storey_masses_keep_each_daylight_band :: proc(t: ^testing.T) {
    archetypes := [10]buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Post_Office,
        .Clinic,
        .Palace_Loggia,
        .Harbor_Office,
        .Monastery,
    }
    sizes := [5][3]f32{{18, 18, 7.2}, {18, 18, 9.6}, {18, 18, 19.2}, {30, 24, 24}, {60, 36, 48}}
    for archetype in archetypes {
        occupied := buildings.is_habitable(archetype) || archetype == .Post_Office
        if !occupied do continue
        for size in sizes {
            for seed in 0 ..< 64 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                if footprint.count <= 1 do continue
                primary := architecture.architecture_frontage_mass_index(structure)
                for mass, mass_index in footprint.masses[:footprint.count] {
                    if architecture.facade_floor_count(structure.height * mass.height_scale) <= 1 {
                        continue
                    }
                    harbor_service_range :=
                        archetype == .Harbor_Office && footprint.count == 3 && mass_index == 2
                    if harbor_service_range do continue
                    layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                    lower_windows, upper_windows := 0, 0
                    for opening in layout.openings[:layout.count] {
                        if opening.kind != .Window && opening.kind != .Loggia {
                            continue
                        }
                        if opening.row == 0 {
                            lower_windows += 1
                        } else {
                            upper_windows += 1
                        }
                    }
                    testing.expectf(
                        t,
                        lower_windows > 0 && upper_windows > 0,
                        "occupied mass lost a daylight band archetype=%v size=(%.1f,%.1f,%.1f) seed=%d mass=%d primary=%v lower=%d upper=%d",
                        archetype,
                        size[0],
                        size[1],
                        size[2],
                        seed,
                        mass_index,
                        mass_index == primary,
                        lower_windows,
                        upper_windows,
                    )
                }
            }
        }
    }
}

@(test)
architecture_compound_faces_keep_daylight_when_mostly_exposed :: proc(t: ^testing.T) {
    archetypes := [11]buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Clinic,
        .Palace_Loggia,
        .Harbor_Office,
        .Monastery,
        .Market_Hall,
        .Church,
    }
    sizes := [3][3]f32{{18, 18, 9.6}, {30, 24, 24}, {60, 36, 48}}
    faces := [4]architecture.Face{.Front, .Rear, .Left, .Right}
    for archetype in archetypes {
        profile := architecture.facade_profile(archetype)
        for size in sizes {
            for seed in 0 ..< 64 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                if footprint.count <= 1 do continue
                primary := architecture.architecture_frontage_mass_index(structure)
                for mass, mass_index in footprint.masses[:footprint.count] {
                    harbor_service_range :=
                        archetype == .Harbor_Office && footprint.count == 3 && mass_index == 2
                    if harbor_service_range do continue
                    layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                    wall_height := structure.height * mass.height_scale
                    for face in faces {
                        if (face == .Left || face == .Right) && profile.blank_sides do continue
                        span := architecture.face_span(mass, face)
                        if span < 6 do continue
                        exposed_area := architecture.architecture_exposed_face_area(
                            footprint,
                            mass_index,
                            face,
                            structure.height,
                        )
                        if exposed_area < span * wall_height * .55 do continue
                        daylight := 0
                        for opening in layout.openings[:layout.count] {
                            if opening.face == face &&
                               (opening.kind == .Window || opening.kind == .Loggia) {
                                daylight += 1
                            }
                        }
                        if daylight == 0 {
                            testing.expectf(
                                t,
                                false,
                                "mostly exposed occupied face is blank archetype=%v size=(%.1f,%.1f,%.1f) seed=%d mass=%d face=%v exposed=%.2f/%.2f",
                                archetype,
                                size[0],
                                size[1],
                                size[2],
                                seed,
                                mass_index,
                                face,
                                exposed_area,
                                span * wall_height,
                            )
                            return
                        }
                    }
                }
            }
        }
    }
}

@(test)
architecture_occupied_compound_faces_use_material_exterior_daylight :: proc(t: ^testing.T) {
    archetypes := [10]buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Clinic,
        .Palace_Loggia,
        .Harbor_Office,
        .Monastery,
        .Post_Office,
    }
    sizes := [3][3]f32{{18, 18, 9.6}, {30, 24, 24}, {60, 36, 48}}
    faces := [4]architecture.Face{.Front, .Rear, .Left, .Right}
    for archetype in archetypes {
        profile := architecture.facade_profile(archetype)
        for size in sizes {
            for seed in 0 ..< 128 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                if footprint.count <= 1 do continue
                primary := architecture.architecture_frontage_mass_index(structure)
                for mass, mass_index in footprint.masses[:footprint.count] {
                    harbor_service_range :=
                        archetype == .Harbor_Office && footprint.count == 3 && mass_index == 2
                    if harbor_service_range do continue
                    layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                    wall_height := structure.height * mass.height_scale
                    for face in faces {
                        if (face == .Left || face == .Right) && profile.blank_sides do continue
                        span := architecture.face_span(mass, face)
                        if span < 6 do continue
                        exposed_area := architecture.architecture_exposed_face_area(
                            footprint,
                            mass_index,
                            face,
                            structure.height,
                        )
                        if exposed_area < span * wall_height * .20 do continue
                        has_daylight := false
                        for opening in layout.openings[:layout.count] {
                            if opening.face == face &&
                               (opening.kind == .Window || opening.kind == .Loggia) {
                                has_daylight = true
                                break
                            }
                        }
                        if !has_daylight {
                            testing.expectf(
                                t,
                                false,
                                "materially exposed occupied face is blank archetype=%v size=(%.1f,%.1f,%.1f) seed=%d mass=%d face=%v exposed=%.2f/%.2f",
                                archetype,
                                size[0],
                                size[1],
                                size[2],
                                seed,
                                mass_index,
                                face,
                                exposed_area,
                                span * wall_height,
                            )
                            return
                        }
                    }
                }
            }
        }
    }
}

@(test)
architecture_compound_floorplan_masses_keep_usable_room_dimensions :: proc(t: ^testing.T) {
    archetypes := []buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Post_Office,
        .Clinic,
        .Workshop,
        .Storehouse,
        .Fishery,
        .Barn_Granary,
        .Mill,
        .Palace_Loggia,
        .Market_Hall,
        .Harbor_Office,
        .Monastery,
        .Church,
        .Fortress_Gate,
    }
    sizes := [7][2]f32{{9, 12}, {12, 12}, {14, 14}, {16, 14}, {18, 16}, {22, 18}, {30, 24}}
    for archetype in archetypes {
        for size in sizes {
            for seed in 0 ..< 32 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, 24)
                structure.width, structure.depth = size[0], size[1]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                if footprint.count <= 1 do continue
                for mass, mass_index in footprint.masses[:footprint.count] {
                    testing.expectf(
                        t,
                        mass.width >= 4.5 - .001 && mass.depth >= 4.5 - .001,
                        "compound mass is not a usable room archetype=%v size=(%.1f,%.1f) seed=%d mass=%d dimensions=(%.2f,%.2f)",
                        archetype,
                        size[0],
                        size[1],
                        seed,
                        mass_index,
                        mass.width,
                        mass.depth,
                    )
                }
            }
        }
    }
}

@(test)
architecture_shallow_fortress_avoids_an_unusable_guard_court :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 14, 3, 4, 9.6)
    structure.width, structure.depth = 14, 3
    structure.kind = .Architecture
    structure.building.archetype = .Fortress_Gate
    footprint := architecture.architecture_footprint(structure)
    testing.expect_value(t, footprint.count, 1)
    layout := architecture.architecture_opening_layout(structure, 0, 0)
    _, found_door := architecture.opening_layout_find(&layout, .Front, .Service_Door, 0, 0)
    testing.expect(t, found_door)
}

@(test)
mixed_use_dwelling_has_full_glass_storefront_grammar :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 18)
    structure.kind = .Architecture
    structure.seed = 43
    structure.building.archetype = .Mixed_Use_Dwelling
    structure.building.purpose = .Inn_Shop

    primary := architecture.architecture_frontage_mass_index(structure)
    layout := architecture.architecture_opening_layout(structure, primary, primary)
    storefront_panes := 0
    found_shop_door := false
    for opening in layout.openings[:layout.count] {
        if opening.face != .Front do continue
        if opening.kind == .Door {
            found_shop_door = true
        } else if opening.kind == .Window && opening.row == 0 {
            storefront_panes += 1
            testing.expect(t, opening.width >= 4.2)
            testing.expect(t, opening.y - opening.height * .5 <= .361)
        }
    }
    testing.expect(t, found_shop_door)
    testing.expect_value(t, storefront_panes, 2)
}

@(test)
mixed_use_dwelling_has_compact_one_window_storefront_grammar :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 10, 12, 4, 12)
    structure.width, structure.depth, structure.height = 10, 12, 12
    structure.kind = .Architecture
    structure.seed = 42
    structure.building.archetype = .Mixed_Use_Dwelling
    structure.building.purpose = .Inn_Shop

    primary := architecture.architecture_frontage_mass_index(structure)
    layout := architecture.architecture_opening_layout(structure, primary, primary)
    storefront_panes := 0
    door_horizontal := f32(0)
    pane_horizontal := f32(0)
    found_shop_door := false
    for opening in layout.openings[:layout.count] {
        if opening.face != .Front do continue
        if opening.kind == .Door {
            found_shop_door = true
            door_horizontal = opening.horizontal
        } else if opening.kind == .Window && opening.row == 0 {
            storefront_panes += 1
            pane_horizontal = opening.horizontal
            testing.expect(t, opening.width >= 4.2)
            testing.expect(t, opening.y - opening.height * .5 <= .361)
        }
    }
    testing.expect(t, found_shop_door)
    testing.expect_value(t, storefront_panes, 1)
    testing.expect(t, door_horizontal * pane_horizontal < 0)
}

@(test)
mixed_use_dwelling_narrow_frontages_keep_display_glazing :: proc(t: ^testing.T) {
    for width in 5 ..= 10 {
        for seed in 0 ..< 32 {
            structure := terrain.structure_make(1300, 1300, f32(width), 8, 4, 9.6)
            structure.width, structure.depth, structure.height = f32(width), 8, 9.6
            structure.kind = .Architecture
            structure.seed = u32(seed)
            structure.building.archetype = .Mixed_Use_Dwelling
            structure.building.purpose = .Inn_Shop
            primary := architecture.architecture_frontage_mass_index(structure)
            layout := architecture.architecture_opening_layout(structure, primary, primary)
            display_panes := 0
            for opening in layout.openings[:layout.count] {
                if opening.face == .Front && opening.kind == .Window && opening.row == 0 {
                    display_panes += 1
                    testing.expect(t, opening.width >= .70)
                    testing.expect(t, opening.y - opening.height * .5 <= .361)
                }
            }
            testing.expectf(
                t,
                display_panes > 0,
                "narrow mixed-use frontage lost all display glazing width=%d seed=%d",
                width,
                seed,
            )
        }
    }
}

@(test)
shop_house_narrow_frontages_keep_display_glazing :: proc(t: ^testing.T) {
    for width in 5 ..= 10 {
        for seed in 0 ..< 32 {
            structure := terrain.structure_make(1300, 1300, f32(width), 8, 4, 9.6)
            structure.width, structure.depth, structure.height = f32(width), 8, 9.6
            structure.kind = .Architecture
            structure.seed = u32(seed)
            structure.building.archetype = .Shop_House
            structure.building.purpose = .Inn_Shop
            primary := architecture.architecture_frontage_mass_index(structure)
            layout := architecture.architecture_opening_layout(structure, primary, primary)
            display_panes := 0
            for opening in layout.openings[:layout.count] {
                if opening.face == .Front && opening.kind == .Window && opening.row == 0 {
                    display_panes += 1
                    testing.expect(t, opening.width >= .70)
                    testing.expect(t, opening.y - opening.height * .5 <= .361)
                }
            }
            testing.expectf(
                t,
                display_panes > 0,
                "narrow shop-house frontage lost all display glazing width=%d seed=%d",
                width,
                seed,
            )
        }
    }
}

@(test)
market_hall_compact_frontages_keep_a_public_arcade_bay :: proc(t: ^testing.T) {
    for width in 6 ..= 14 {
        for seed in 0 ..< 32 {
            structure := terrain.structure_make(1300, 1300, f32(width), 10, 4, 9.6)
            structure.width, structure.depth, structure.height = f32(width), 10, 9.6
            structure.kind = .Architecture
            structure.seed = u32(seed)
            structure.building.archetype = .Market_Hall
            primary := architecture.architecture_frontage_mass_index(structure)
            layout := architecture.architecture_opening_layout(structure, primary, primary)
            arcade_bays := 0
            for opening in layout.openings[:layout.count] {
                if opening.face == .Front && opening.kind == .Loggia && opening.row == 0 {
                    arcade_bays += 1
                    testing.expect(t, opening.width >= .90)
                    testing.expect(t, opening.y - opening.height * .5 <= .201)
                }
            }
            testing.expectf(
                t,
                arcade_bays > 0,
                "compact market frontage lost every public arcade bay width=%d seed=%d",
                width,
                seed,
            )
        }
    }
}

@(test)
palace_loggia_compact_frontages_keep_an_open_ceremonial_bay :: proc(t: ^testing.T) {
    for width in 6 ..= 20 {
        for seed in 0 ..< 32 {
            structure := terrain.structure_make(1300, 1300, f32(width), 10, 4, 12)
            structure.width, structure.depth, structure.height = f32(width), 10, 12
            structure.kind = .Architecture
            structure.seed = u32(seed)
            structure.building.archetype = .Palace_Loggia
            primary := architecture.architecture_frontage_mass_index(structure)
            layout := architecture.architecture_opening_layout(structure, primary, primary)
            loggia_bays := 0
            for opening in layout.openings[:layout.count] {
                if opening.face == .Front && opening.kind == .Loggia && opening.row == 0 {
                    loggia_bays += 1
                    testing.expect(t, opening.width >= .90)
                    testing.expect(t, opening.y - opening.height * .5 <= .251)
                }
            }
            testing.expectf(
                t,
                loggia_bays > 0,
                "compact palace frontage lost every ceremonial loggia bay width=%d seed=%d",
                width,
                seed,
            )
        }
    }
}

@(test)
mixed_use_dwelling_side_windows_clear_apartment_doors :: proc(t: ^testing.T) {
    sizes := [6][3]f32{{7, 5, 24}, {8, 3, 4.8}, {10, 10, 7.2}, {14, 14, 9.6}, {30, 24, 18}, {60, 36, 28.8}}
    for size in sizes {
        apartment_door_faces: [2]int
        for seed in 0 ..< 64 {
            structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
            structure.width, structure.depth, structure.height = size[0], size[1], size[2]
            structure.kind = .Architecture
            structure.seed = u32(seed)
            structure.building.archetype = .Mixed_Use_Dwelling
            structure.building.purpose = .Inn_Shop

            primary := architecture.architecture_frontage_mass_index(structure)
            footprint := architecture.architecture_footprint(structure)
            layout := architecture.architecture_opening_layout(structure, primary, primary)
            mass := footprint.masses[primary]
            apartment_doors := 0
            for opening in layout.openings[:layout.count] {
                if opening.kind == .Service_Door && (opening.face == .Left || opening.face == .Right) {
                    apartment_doors += 1
                    apartment_door_faces[opening.face == .Left ? 0 : 1] += 1
                    maximum_horizontal := max(
                        f32(0),
                        mass.depth * .5 - architecture.ARCHITECTURE_OPENING_CORNER_MARGIN - opening.width * .5,
                    )
                    expected_horizontal := clamp(
                        opening.face == .Left ? mass.depth * .20 : -mass.depth * .20,
                        -maximum_horizontal,
                        maximum_horizontal,
                    )
                    testing.expect(t, math.abs(opening.horizontal - expected_horizontal) <= .001)
                    testing.expect(t, math.abs(opening.y - 1.62) <= .001)
                    testing.expect(t, math.abs(opening.width - 1.65) <= .001)
                    testing.expect(t, math.abs(opening.height - 3.05) <= .001)
                }
                if opening.kind != .Window || (opening.face != .Left && opening.face != .Right) {
                    continue
                }
                testing.expect(
                    t,
                    !architecture.opening_layout_conflicts_with_door(
                        &layout,
                        opening.face,
                        opening.horizontal,
                        opening.y,
                        opening.width,
                        opening.height,
                    ),
                )
            }
            needs_independent_apartment_entry :=
                size[2] >= 7.2 && size[1] >= architecture.ARCHITECTURE_MIN_OPENING_FACE_SPAN
            if needs_independent_apartment_entry {
                testing.expectf(
                    t,
                    apartment_doors == 1,
                    "mixed-use frontage needs exactly one exposed apartment door size=(%.1f,%.1f,%.1f) seed=%d doors=%d",
                    size[0],
                    size[1],
                    size[2],
                    seed,
                    apartment_doors,
                )
            } else {
                testing.expect_value(t, apartment_doors, 0)
            }
        }
        if size[2] >= 7.2 && size[1] >= architecture.ARCHITECTURE_MIN_OPENING_FACE_SPAN {
            testing.expectf(
                t,
                apartment_door_faces[0] > 0 && apartment_door_faces[1] > 0,
                "mixed-use apartment entries do not vary sides size=(%.1f,%.1f,%.1f) left=%d right=%d",
                size[0],
                size[1],
                size[2],
                apartment_door_faces[0],
                apartment_door_faces[1],
            )
        }
    }
}

@(test)
architecture_openings_respect_mass_bounds_and_primary_door_ownership :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    structure.seed = 3
    structure.building.archetype = .Dwelling
    footprint := architecture.architecture_footprint(structure)
    primary := architecture.architecture_frontage_mass_index(structure)

    for _, mass_index in footprint.masses[:footprint.count] {
        layout := architecture.architecture_opening_layout(structure, mass_index, primary)
        face_counts: [4]int
        doors := 0
        for opening in layout.openings[:layout.count] {
            face_counts[int(opening.face)] += 1
            if opening.kind == .Door {
                doors += 1
                testing.expect(t, opening.face == .Front)
                testing.expect(t, mass_index == primary)
            }
            span := architecture.face_span(footprint.masses[mass_index], opening.face)
            testing.expect(
                t,
                math.abs(opening.horizontal) + opening.width * .5 <=
                span * .5 - architecture.ARCHITECTURE_OPENING_CORNER_MARGIN + .001,
            )
        }
        testing.expect(t, doors == (mass_index == primary ? 1 : 0))
    }
}

@(test)
architecture_compound_floorplans_keep_one_exposed_primary_entrance :: proc(t: ^testing.T) {
    archetypes := [18]buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Post_Office,
        .Clinic,
        .Workshop,
        .Storehouse,
        .Fishery,
        .Barn_Granary,
        .Mill,
        .Palace_Loggia,
        .Harbor_Office,
        .Market_Hall,
        .Monastery,
        .Church,
        .Fortress_Gate,
    }
    sizes := [5][3]f32 {
        {12, 12, 7.2},
        {18, 18, 9.6},
        {24, 18, 12},
        {30, 24, 24},
        {60, 36, 48},
    }
    for archetype in archetypes {
        for size in sizes {
            for seed in 0 ..< 128 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                if footprint.count <= 1 do continue
                // The paired-tower gate itself is the public opening; the
                // hinged guard-room door behind it is intentionally secondary.
                if archetype == .Fortress_Gate do continue
                primary := architecture.architecture_frontage_mass_index(structure)
                layout := architecture.architecture_opening_layout(structure, primary, primary)
                entrances := 0
                for opening in layout.openings[:layout.count] {
                    if opening.kind != .Door && opening.kind != .Service_Door do continue
                    if !opening.primary do continue
                    entrances += 1
                    testing.expectf(
                        t,
                        opening.face == .Front,
                        "primary entrance left the approach facade archetype=%v size=(%.1f,%.1f,%.1f) seed=%d mass=%d face=%v",
                        archetype,
                        size[0],
                        size[1],
                        size[2],
                        seed,
                        primary,
                        opening.face,
                    )
                    testing.expectf(
                        t,
                        !architecture.architecture_opening_occluded_by_mass(
                            footprint,
                            primary,
                            opening.face,
                            opening.horizontal,
                            opening.y,
                            opening.width,
                            opening.height,
                            structure.height,
                        ),
                        "primary entrance is buried by an attached range archetype=%v size=(%.1f,%.1f,%.1f) seed=%d mass=%d",
                        archetype,
                        size[0],
                        size[1],
                        size[2],
                        seed,
                        primary,
                    )
                }
                if entrances != 1 {
                    testing.expectf(
                        t,
                        false,
                        "compound lacks one legible primary entrance archetype=%v size=(%.1f,%.1f,%.1f) seed=%d primary=%d entrances=%d",
                        archetype,
                        size[0],
                        size[1],
                        size[2],
                        seed,
                        primary,
                        entrances,
                    )
                    return
                }
            }
        }
    }
}

@(test)
architecture_broad_occupied_frontages_scale_primary_entrances_by_public_role :: proc(t: ^testing.T) {
    archetypes := [10]buildings.Archetype {
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Post_Office,
        .Clinic,
        .Palace_Loggia,
        .Market_Hall,
        .Harbor_Office,
        .Monastery,
        .Church,
    }
    structure := terrain.structure_make(1300, 1300, 60, 36, 4, 48)
    structure.kind = .Architecture
    for archetype in archetypes {
        structure.building.archetype = archetype
        checked := 0
        for seed in 0 ..< 64 {
            structure.seed = u32(seed)
            footprint := architecture.architecture_footprint(structure)
            primary := architecture.architecture_frontage_mass_index(structure)
            mass := footprint.masses[primary]
            if mass.width < 28 || structure.height * mass.height_scale < 14.4 do continue
            layout := architecture.architecture_opening_layout(structure, primary, primary)
            entrance: architecture.Opening
            found := false
            for opening in layout.openings[:layout.count] {
                if opening.primary && (opening.kind == .Door || opening.kind == .Service_Door) {
                    entrance, found = opening, true
                    break
                }
            }
            testing.expectf(t, found, "broad frontage lacks primary entrance archetype=%v seed=%d", archetype, seed)
            if !found do continue
            urban :=
                archetype == .Townhouse ||
                archetype == .Shop_House ||
                archetype == .Mixed_Use_Dwelling
            minimum_width := urban ? f32(3.0) : f32(3.2)
            maximum_width := urban ? f32(3.4) : f32(4.0)
            minimum_height := urban ? f32(4.0) : f32(4.2)
            maximum_height := urban ? f32(4.5) : f32(4.8)
            testing.expectf(
                t,
                entrance.width >= minimum_width && entrance.width <= maximum_width &&
                    entrance.height >= minimum_height && entrance.height <= maximum_height,
                "broad entrance lost role scale archetype=%v seed=%d size=(%.2f,%.2f) expected=(%.2f..%.2f,%.2f..%.2f)",
                archetype,
                seed,
                entrance.width,
                entrance.height,
                minimum_width,
                maximum_width,
                minimum_height,
                maximum_height,
            )
            checked += 1
        }
        testing.expectf(t, checked > 0, "broad entrance role was never exercised archetype=%v", archetype)
    }
}

@(test)
architecture_compact_work_hall_keeps_daylight_beside_shifted_entrance :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 12, 12, 4, 7.2)
    structure.width, structure.depth, structure.height = 12, 12, 7.2
    structure.kind = .Architecture
    structure.building.archetype = .Workshop
    for seed in 1 ..= 2 {
        structure.seed = u32(seed)
        footprint := architecture.architecture_footprint(structure)
        testing.expect_value(t, footprint.count, 2)
        primary := architecture.architecture_frontage_mass_index(structure)
        testing.expect_value(t, primary, 0)
        layout := architecture.architecture_opening_layout(structure, primary, primary)
        door_horizontal := f32(0)
        doors, front_windows := 0, 0
        free_edge_window := false
        attachment_side := footprint.masses[1].local_x < 0 ? f32(-1) : f32(1)
        for opening in layout.openings[:layout.count] {
            if opening.primary && (opening.kind == .Door || opening.kind == .Service_Door) {
                doors += 1
                door_horizontal = opening.horizontal
            }
        }
        for opening in layout.openings[:layout.count] {
            if opening.face != .Front || opening.kind != .Window do continue
            front_windows += 1
            if opening.horizontal * attachment_side < door_horizontal * attachment_side {
                free_edge_window = true
            }
        }
        testing.expect_value(t, doors, 1)
        testing.expectf(
            t,
            door_horizontal * attachment_side < -.01,
            "compact work-hall entrance did not move opposite its service wing seed=%d door_x=%.2f wing_x=%.2f",
            seed,
            door_horizontal,
            footprint.masses[1].local_x,
        )
        testing.expectf(
            t,
            front_windows > 0 && free_edge_window,
            "shifted work-hall entrance lost daylight toward its free frontage edge seed=%d door_x=%.2f windows=%d",
            seed,
            door_horizontal,
            front_windows,
        )
    }
}

@(test)
architecture_compound_openings_stay_out_of_attached_mass_joins :: proc(t: ^testing.T) {
    archetypes := []buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Workshop,
        .Storehouse,
        .Fishery,
        .Barn_Granary,
        .Mill,
        .Palace_Loggia,
        .Market_Hall,
        .Harbor_Office,
        .Monastery,
        .Church,
        .Fortress_Gate,
    }
    for archetype in archetypes {
        for seed in 0 ..< 32 {
            structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
            structure.kind = .Architecture
            structure.seed = u32(seed)
            structure.building.archetype = archetype
            footprint := architecture.architecture_footprint(structure)
            primary := architecture.architecture_frontage_mass_index(structure)
            for _, mass_index in footprint.masses[:footprint.count] {
                layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                for opening in layout.openings[:layout.count] {
                    if opening.kind == .Door || opening.kind == .Service_Door do continue
                    testing.expect(
                        t,
                        !architecture.architecture_opening_occluded_by_mass(
                            footprint,
                            mass_index,
                            opening.face,
                            opening.horizontal,
                            opening.y,
                            opening.width,
                            opening.height,
                            structure.height,
                        ),
                    )
                }
            }
        }
    }
}

@(test)
architecture_attached_eaves_reserve_clear_wall_bands_around_their_roofline :: proc(t: ^testing.T) {
    footprint: architecture.Architecture_Footprint
    footprint.masses[0] = {0, 0, 20, 20, 1}
    // The wing wall stops just short of the main mass's front plane at z=10,
    // but its rendered 5% roof overhang reaches across that plane.
    footprint.masses[1] = {0, 4, 12, 11.5, .60}
    footprint.count = 2

    testing.expect(
        t,
        architecture.architecture_opening_occluded_by_mass(
            footprint,
            0,
            .Front,
            0,
            12,
            1.4,
            .4,
            20,
        ),
    )
    testing.expect(
        t,
        !architecture.architecture_opening_occluded_by_mass(
            footprint,
            0,
            .Front,
            0,
            13,
            1.4,
            1,
            20,
        ),
    )
}

@(test)
architecture_generated_doors_stay_out_of_attached_mass_joins :: proc(t: ^testing.T) {
    archetypes := []buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Post_Office,
        .Clinic,
        .Workshop,
        .Storehouse,
        .Fishery,
        .Barn_Granary,
        .Mill,
        .Palace_Loggia,
        .Market_Hall,
        .Harbor_Office,
        .Monastery,
        .Church,
        .Fortress_Gate,
    }
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    for archetype in archetypes {
        structure.building.archetype = archetype
        for seed in 0 ..< 64 {
            structure.seed = u32(seed)
            footprint := architecture.architecture_footprint(structure)
            primary := architecture.architecture_frontage_mass_index(structure)
            for _, mass_index in footprint.masses[:footprint.count] {
                layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                for opening in layout.openings[:layout.count] {
                    if opening.kind != .Door && opening.kind != .Service_Door do continue
                    testing.expectf(
                        t,
                        !architecture.architecture_opening_occluded_by_mass(
                            footprint,
                            mass_index,
                            opening.face,
                            opening.horizontal,
                            opening.y,
                            opening.width,
                            opening.height,
                            structure.height,
                        ),
                        "door buried in compound join archetype=%v seed=%d mass=%d face=%v",
                        archetype,
                        seed,
                        mass_index,
                        opening.face,
                    )
                }
            }
        }
    }
}

@(test)
architecture_window_bays_never_overlap_on_a_facade :: proc(t: ^testing.T) {
    archetypes := []buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Post_Office,
        .Clinic,
        .Workshop,
        .Storehouse,
        .Fishery,
        .Barn_Granary,
        .Mill,
        .Palace_Loggia,
        .Harbor_Office,
        .Market_Hall,
        .Monastery,
        .Church,
        .Campanile,
        .Fortress_Gate,
        .Cycladic_Bell,
        .Lighthouse,
    }
    sizes := [7][3]f32 {
        {8, 6, 4.8},
        {14, 14, 7.2},
        {12, 12, 9.6},
        {14, 14, 9.6},
        {14, 14, 12.0},
        {30, 24, 24},
        {60, 36, 48},
    }
    for archetype in archetypes {
        for size in sizes {
            for seed in 0 ..< 256 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                primary := architecture.architecture_frontage_mass_index(structure)
                for _, mass_index in footprint.masses[:footprint.count] {
                    layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                    for a, a_index in layout.openings[:layout.count] {
                        if a.kind == .Door || a.kind == .Service_Door do continue
                        for b in layout.openings[a_index + 1:layout.count] {
                            if b.kind == .Door || b.kind == .Service_Door || a.face != b.face do continue
                            horizontal_gap :=
                                math.abs(a.horizontal - b.horizontal) - (a.width + b.width) * .5
                            vertical_overlap := math.abs(a.y - b.y) < (a.height + b.height) * .5 - .001
                            if horizontal_gap < architecture.ARCHITECTURE_WINDOW_PIER_MARGIN - .001 &&
                               vertical_overlap {
                                span := architecture.face_span(footprint.masses[mass_index], a.face)
                                primary_face := mass_index == primary && a.face == .Front
                                profile := architecture.facade_profile(archetype)
                                columns := architecture.facade_profile_bay_count(
                                    profile,
                                    structure,
                                    a.face,
                                    primary_face,
                                    span,
                                )
                                testing.expectf(
                                    t,
                                    false,
                                    "under-width facade pier archetype=%v seed=%d size=(%.1f,%.1f,%.1f) mass=%d face=%v span=%.2f columns=%d primary=%v gap=%.2f a=(r%d,c%d,x%.2f,y%.2f,w%.2f,h%.2f) b=(r%d,c%d,x%.2f,y%.2f,w%.2f,h%.2f)",
                                    archetype,
                                    seed,
                                    size[0],
                                    size[1],
                                    size[2],
                                    mass_index,
                                    a.face,
                                    span,
                                    columns,
                                    primary_face,
                                    horizontal_gap,
                                    a.row,
                                    a.column,
                                    a.horizontal,
                                    a.y,
                                    a.width,
                                    a.height,
                                    b.row,
                                    b.column,
                                    b.horizontal,
                                    b.y,
                                    b.width,
                                    b.height,
                                )
                                return
                            }
                        }
                    }
                }
            }
        }
    }
}

@(test)
architecture_opening_layouts_never_silently_saturate_capacity :: proc(t: ^testing.T) {
    archetypes := []buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Post_Office,
        .Clinic,
        .Workshop,
        .Storehouse,
        .Fishery,
        .Barn_Granary,
        .Mill,
        .Palace_Loggia,
        .Harbor_Office,
        .Market_Hall,
        .Monastery,
        .Church,
        .Campanile,
        .Fortress_Gate,
        .Cycladic_Bell,
        .Lighthouse,
    }
    sizes := [4][3]f32{{14, 14, 9.6}, {30, 24, 24}, {60, 36, 48}, {96, 54, 72}}
    for archetype in archetypes {
        for size in sizes {
            for seed in 0 ..< 256 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                primary := architecture.architecture_frontage_mass_index(structure)
                for _, mass_index in footprint.masses[:footprint.count] {
                    layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                    testing.expectf(
                        t,
                        layout.count < architecture.OPENING_LAYOUT_CAPACITY,
                        "opening layout saturated archetype=%v seed=%d size=(%.1f,%.1f,%.1f) mass=%d",
                        archetype,
                        seed,
                        size[0],
                        size[1],
                        size[2],
                        mass_index,
                    )
                }
            }
        }
    }
}

@(test)
architecture_generated_openings_keep_unique_logical_addresses :: proc(t: ^testing.T) {
    archetypes := []buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Post_Office,
        .Clinic,
        .Workshop,
        .Storehouse,
        .Fishery,
        .Barn_Granary,
        .Mill,
        .Palace_Loggia,
        .Harbor_Office,
        .Market_Hall,
        .Monastery,
        .Church,
        .Fortress_Gate,
    }
    sizes := [4][3]f32{{14, 14, 7.2}, {18, 18, 9.6}, {60, 36, 48}, {96, 54, 72}}
    for archetype in archetypes {
        for size in sizes {
            for seed in 0 ..< 128 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                primary := architecture.architecture_frontage_mass_index(structure)
                for _, mass_index in footprint.masses[:footprint.count] {
                    layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                    for opening, opening_index in layout.openings[:layout.count] {
                        for candidate, candidate_index in layout.openings[:layout.count] {
                            if candidate_index <= opening_index do continue
                            if opening.face == candidate.face &&
                               opening.kind == candidate.kind &&
                               opening.row == candidate.row &&
                               opening.column == candidate.column {
                                testing.expectf(
                                    t,
                                    false,
                                    "duplicate opening address archetype=%v size=(%.1f,%.1f,%.1f) seed=%d mass=%d face=%v kind=%v row=%d column=%d positions=(%.2f,%.2f)",
                                    archetype,
                                    size[0],
                                    size[1],
                                    size[2],
                                    seed,
                                    mass_index,
                                    opening.face,
                                    opening.kind,
                                    opening.row,
                                    opening.column,
                                    opening.horizontal,
                                    candidate.horizontal,
                                )
                                return
                            }
                            if opening.face == candidate.face &&
                               opening.kind == .Window &&
                               candidate.kind == .Window &&
                               opening.row == candidate.row {
                                left, right := opening, candidate
                                if left.horizontal > right.horizontal do left, right = right, left
                                if left.horizontal < right.horizontal - .001 && left.column >= right.column {
                                    testing.expectf(
                                        t,
                                        false,
                                        "window columns lost spatial order archetype=%v size=(%.1f,%.1f,%.1f) seed=%d mass=%d face=%v row=%d left=(%.2f,%d) right=(%.2f,%d)",
                                        archetype,
                                        size[0],
                                        size[1],
                                        size[2],
                                        seed,
                                        mass_index,
                                        opening.face,
                                        opening.row,
                                        left.horizontal,
                                        left.column,
                                        right.horizontal,
                                        right.column,
                                    )
                                    return
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@(test)
architecture_compound_floorplans_never_create_openingless_low_ranges :: proc(t: ^testing.T) {
    archetypes := []buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Post_Office,
        .Clinic,
        .Workshop,
        .Storehouse,
        .Fishery,
        .Barn_Granary,
        .Mill,
        .Palace_Loggia,
        .Market_Hall,
        .Harbor_Office,
        .Monastery,
        .Church,
        .Fortress_Gate,
    }
    heights := [5]f32{4.5, 4.8, 6.0, 7.2, 8.0}
    for archetype in archetypes {
        for height in heights {
            for seed in 0 ..< 64 {
                structure := terrain.structure_make(1300, 1300, 30, 24, 4, height)
                structure.width, structure.depth, structure.height = 30, 24, height
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                if footprint.count <= 1 do continue
                primary := architecture.architecture_frontage_mass_index(structure)
                for mass, mass_index in footprint.masses[:footprint.count] {
                    wall_height := structure.height * mass.height_scale
                    testing.expectf(
                        t,
                        wall_height >= architecture.ARCHITECTURE_MIN_OPENING_WALL_HEIGHT,
                        "compound retained openingless range archetype=%v height=%.1f seed=%d mass=%d wall=%.2f",
                        archetype,
                        height,
                        seed,
                        mass_index,
                        wall_height,
                    )
                    layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                    testing.expectf(
                        t,
                        layout.count > 0,
                        "usable compound range has empty opening layout archetype=%v height=%.1f seed=%d mass=%d",
                        archetype,
                        height,
                        seed,
                        mass_index,
                    )
                }
            }
        }
    }
}

@(test)
architecture_openings_fit_wall_bounds_and_clear_every_door :: proc(t: ^testing.T) {
    archetypes := []buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Post_Office,
        .Clinic,
        .Workshop,
        .Storehouse,
        .Fishery,
        .Barn_Granary,
        .Mill,
        .Palace_Loggia,
        .Harbor_Office,
        .Market_Hall,
        .Monastery,
        .Church,
        .Campanile,
        .Fortress_Gate,
        .Cycladic_Bell,
        .Lighthouse,
    }
    sizes := [10][3]f32 {
        {8, 6, 4.5},
        {8, 6, 4.8},
        {18, 18, 7.19},
        {18, 18, 7.2},
        {18, 18, 7.21},
        {18, 18, 9.59},
        {14, 14, 9.6},
        {18, 18, 9.61},
        {30, 24, 24},
        {60, 36, 48},
    }
    for archetype in archetypes {
        for size in sizes {
            for seed in 0 ..< 32 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                primary := architecture.architecture_frontage_mass_index(structure)
                for mass, mass_index in footprint.masses[:footprint.count] {
                    wall_height := structure.height * mass.height_scale
                    layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                    for opening in layout.openings[:layout.count] {
                        span := architecture.face_span(mass, opening.face)
                        testing.expect(t, opening.y - opening.height * .5 >= -.001)
                        testing.expect(t, opening.y + opening.height * .5 <= wall_height + .001)
                        testing.expect(
                            t,
                            math.abs(opening.horizontal) + opening.width * .5 <=
                            span * .5 - architecture.ARCHITECTURE_OPENING_CORNER_MARGIN + .001,
                        )
                        if opening.kind != .Door && opening.kind != .Service_Door do continue
                        for candidate in layout.openings[:layout.count] {
                            if candidate.face != opening.face ||
                               candidate.kind == .Door ||
                               candidate.kind == .Service_Door {
                                continue
                            }
                            horizontal_gap :=
                                math.abs(opening.horizontal - candidate.horizontal) -
                                (opening.width + candidate.width) * .5
                            vertical_overlap :=
                                math.abs(opening.y - candidate.y) < (opening.height + candidate.height) * .5
                            testing.expect(
                                t,
                                !vertical_overlap ||
                                horizontal_gap >= architecture.ARCHITECTURE_DOOR_WINDOW_MARGIN - .001,
                            )
                        }
                    }
                }
            }
        }
    }
}

@(test)
architecture_habitable_compound_wings_keep_an_exposed_window :: proc(t: ^testing.T) {
    archetypes := []buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Palace_Loggia,
        .Harbor_Office,
        .Monastery,
    }
    for archetype in archetypes {
        for seed in 0 ..< 64 {
            structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
            structure.kind = .Architecture
            structure.seed = u32(seed)
            structure.building.archetype = archetype
            if !buildings.is_habitable(archetype) do continue
            footprint := architecture.architecture_footprint(structure)
            if footprint.count <= 1 do continue
            primary := architecture.architecture_frontage_mass_index(structure)
            for _, mass_index in footprint.masses[:footprint.count] {
                if mass_index == primary do continue
                layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                harbor_service_range := archetype == .Harbor_Office && footprint.count == 3 && mass_index == 2
                windows := 0
                vents := 0
                service_doors := 0
                for opening in layout.openings[:layout.count] {
                    if opening.kind == .Window do windows += 1
                    if opening.kind == .Vent do vents += 1
                    if opening.kind == .Service_Door {
                        service_doors += 1
                        expected_service_face := architecture.Face.Rear
                        allowed_service_face := opening.face == expected_service_face
                        if archetype == .Mixed_Use_Dwelling && footprint.count == 3 {
                            expected_service_face = mass_index == 1 ? .Right : .Left
                            allowed_service_face = opening.face == expected_service_face
                        } else if (archetype == .Dwelling || archetype == .Farmstead) && footprint.count == 3 {
                            court_face := mass_index == 1 ? architecture.Face.Right : architecture.Face.Left
                            allowed_service_face = opening.face == .Rear || opening.face == court_face
                        } else if archetype == .Palace_Loggia && footprint.count == 3 {
                            court_face := mass_index == 1 ? architecture.Face.Right : architecture.Face.Left
                            allowed_service_face = opening.face == .Rear || opening.face == court_face
                        } else if archetype == .Monastery && footprint.count == 3 {
                            expected_service_face = mass_index == 1 ? .Right : .Left
                            allowed_service_face = opening.face == expected_service_face
                        } else if archetype == .Harbor_Office && footprint.count == 3 {
                            yard_face :=
                                footprint.masses[mass_index].local_x < 0 ? architecture.Face.Right : architecture.Face.Left
                            allowed_service_face = opening.face == .Rear || opening.face == yard_face
                        }
                        testing.expect(t, allowed_service_face)
                    }
                }
                if harbor_service_range {
                    testing.expectf(t, vents > 0, "harbor gear range has no vent seed=%d", seed)
                    testing.expectf(t, windows == 0, "harbor gear range received office windows seed=%d", seed)
                    testing.expectf(
                        t,
                        service_doors == 2,
                        "harbor gear range lacks quay/yard circulation seed=%d",
                        seed,
                    )
                } else {
                    testing.expect(t, windows > 0)
                    if archetype == .Palace_Loggia && footprint.count == 3 {
                        testing.expect_value(t, service_doors, 2)
                    } else if (archetype == .Dwelling || archetype == .Farmstead) && footprint.count == 3 {
                        testing.expect_value(t, service_doors, 2)
                    } else if archetype == .Monastery && footprint.count == 3 {
                        testing.expect_value(t, service_doors, 1)
                    } else if archetype == .Harbor_Office && footprint.count == 3 {
                        testing.expect_value(t, service_doors, 2)
                    }
                }
            }
        }
    }
}

@(test)
architecture_farmstead_work_ranges_use_compact_utility_windows :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    structure.building.archetype = .Farmstead
    for seed in 0 ..< 64 {
        if seed % 5 != 0 do continue
        structure.seed = u32(seed)
        footprint := architecture.architecture_footprint(structure)
        testing.expect_value(t, footprint.count, 2)
        primary := architecture.architecture_frontage_mass_index(structure)
        testing.expect_value(t, primary, 0)
        layout := architecture.architecture_opening_layout(structure, 1, primary)
        windows := 0
        service_doors := 0
        for opening in layout.openings[:layout.count] {
            if opening.kind == .Service_Door {
                service_doors += 1
                testing.expect(t, opening.face == .Rear)
                continue
            }
            if opening.kind != .Window do continue
            windows += 1
            testing.expect(t, opening.width >= .80 && opening.width <= 1.10)
            testing.expect(t, opening.height >= 1.00 && opening.height <= 1.40)
            testing.expect(t, opening.row <= 1)
        }
        testing.expectf(t, windows > 0, "farmstead work range has no daylight seed=%d", seed)
        testing.expectf(t, service_doors == 1, "farmstead work range lacks yard entry seed=%d", seed)
    }
}

@(test)
architecture_low_farmstead_avoids_a_sealed_utility_range :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 20, 18, 4, 4.8)
    structure.width, structure.depth, structure.height = 20, 18, 4.8
    structure.kind = .Architecture
    structure.seed = 0
    structure.building.archetype = .Farmstead

    low := architecture.architecture_footprint(structure)
    testing.expect_value(t, low.count, 1)
    low_layout := architecture.architecture_opening_layout(structure, 0, 0)
    front_doors, windows := 0, 0
    for opening in low_layout.openings[:low_layout.count] {
        if opening.face == .Front && opening.kind == .Door do front_doors += 1
        if opening.kind == .Window do windows += 1
    }
    testing.expect_value(t, front_doors, 1)
    testing.expectf(t, windows > 0, "low farmstead house lost all daylight")

    structure.height = 8.0
    tall := architecture.architecture_footprint(structure)
    testing.expect_value(t, tall.count, 2)
    primary := architecture.architecture_frontage_mass_index(structure)
    utility_layout := architecture.architecture_opening_layout(structure, 1, primary)
    rear_doors, utility_windows := 0, 0
    for opening in utility_layout.openings[:utility_layout.count] {
        if opening.face == .Rear && opening.kind == .Service_Door do rear_doors += 1
        if opening.kind == .Window do utility_windows += 1
    }
    testing.expect_value(t, rear_doors, 1)
    testing.expectf(t, utility_windows > 0, "usable farmstead utility range lacks daylight")
}

@(test)
architecture_shop_house_stockrooms_use_compact_secure_windows :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    structure.building.archetype = .Shop_House
    for seed in 0 ..< 64 {
        if seed % 4 != 0 do continue
        structure.seed = u32(seed)
        footprint := architecture.architecture_footprint(structure)
        testing.expect_value(t, footprint.count, 2)
        primary := architecture.architecture_frontage_mass_index(structure)
        testing.expect_value(t, primary, 0)
        layout := architecture.architecture_opening_layout(structure, 1, primary)
        windows := 0
        service_doors := 0
        for opening in layout.openings[:layout.count] {
            if opening.kind == .Service_Door {
                service_doors += 1
                testing.expect(t, opening.face == .Rear)
                continue
            }
            if opening.kind != .Window do continue
            windows += 1
            testing.expect(t, opening.width >= .75 && opening.width <= 1.05)
            testing.expect(t, opening.height >= .85 && opening.height <= 1.25)
            testing.expect(t, opening.row <= 1)
        }
        testing.expectf(t, windows > 0, "shop-house stockroom has no daylight seed=%d", seed)
        testing.expectf(t, service_doors == 1, "shop-house stockroom lacks yard entry seed=%d", seed)
    }
}

@(test)
architecture_habitable_primary_masses_keep_exterior_daylight :: proc(t: ^testing.T) {
    archetypes := []buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Post_Office,
        .Clinic,
        .Palace_Loggia,
        .Harbor_Office,
        .Market_Hall,
        .Monastery,
        .Church,
    }
    sizes := [3][3]f32{{8, 6, 4.8}, {14, 14, 9.6}, {30, 24, 24}}
    for archetype in archetypes {
        testing.expect(t, buildings.is_habitable(archetype))
        for size in sizes {
            for seed in 0 ..< 64 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                primary := architecture.architecture_frontage_mass_index(structure)
                layout := architecture.architecture_opening_layout(structure, primary, primary)
                found_window := false
                for opening in layout.openings[:layout.count] {
                    if opening.kind == .Window {
                        found_window = true
                        break
                    }
                }
                testing.expectf(
                    t,
                    found_window,
                    "primary mass has no daylight archetype=%v size=(%.1f,%.1f,%.1f) seed=%d",
                    archetype,
                    size[0],
                    size[1],
                    size[2],
                    seed,
                )
            }
        }
    }
}

@(test)
architecture_nested_mill_tower_keeps_an_exposed_high_vent :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 18, 18, 4, 19.2)
    structure.kind = .Architecture
    structure.seed = 7
    structure.building.archetype = .Mill
    footprint := architecture.architecture_footprint(structure)
    testing.expect_value(t, footprint.count, 2)
    primary := architecture.architecture_frontage_mass_index(structure)
    testing.expect_value(t, primary, 0)
    layout := architecture.architecture_opening_layout(structure, 1, primary)
    outer_height := structure.height * footprint.masses[0].height_scale
    found_high_vent := false
    vent_count := 0
    rows: [16]bool
    for opening in layout.openings[:layout.count] {
        if opening.kind != .Vent do continue
        found_high_vent = true
        vent_count += 1
        testing.expect(t, opening.width >= .55 && opening.width <= .80)
        testing.expect(t, opening.height >= .90 && opening.height <= 1.30)
        testing.expect(t, opening.row >= 0 && opening.row < len(rows))
        rows[opening.row] = true
        testing.expect(t, opening.y - opening.height * .5 >= outer_height - .001)
        testing.expect(
            t,
            !architecture.architecture_opening_occluded_by_mass(
                footprint,
                1,
                opening.face,
                opening.horizontal,
                opening.y,
                opening.width,
                opening.height,
                structure.height,
            ),
        )
    }
    testing.expect(t, found_high_vent)
    distinct_rows := 0
    for found in rows do if found do distinct_rows += 1
    testing.expect_value(t, vent_count, 8)
    testing.expect_value(t, distinct_rows, 2)
}

@(test)
architecture_low_mill_avoids_an_unusable_nested_tower :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 10, 10, 4, 4.8)
    structure.width, structure.depth, structure.height = 10, 10, 4.8
    structure.kind = .Architecture
    structure.building.archetype = .Mill
    low := architecture.architecture_footprint(structure)
    testing.expect_value(t, low.count, 1)
    low_layout := architecture.architecture_opening_layout(structure, 0, 0)
    low_vents := 0
    for opening in low_layout.openings[:low_layout.count] {
        if opening.kind == .Vent do low_vents += 1
    }
    testing.expectf(t, low_vents > 0, "low mill hall lost all ventilation")

    structure.height = 7.2
    tall := architecture.architecture_footprint(structure)
    testing.expect_value(t, tall.count, 2)
    tall_layout := architecture.architecture_opening_layout(structure, 1, 0)
    high_vents := 0
    for opening in tall_layout.openings[:tall_layout.count] {
        if opening.kind == .Vent do high_vents += 1
    }
    testing.expectf(t, high_vents > 0, "usable compact mill tower lacks upper vents")
}

@(test)
architecture_productive_floorplans_use_cart_scale_loading_doors :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    structure.seed = 0

    structure.building.archetype = .Barn_Granary
    barn := architecture.architecture_footprint(structure)
    testing.expect_value(t, barn.count, 2)
    barn_primary := architecture.architecture_frontage_mass_index(structure)
    barn_layout := architecture.architecture_opening_layout(structure, barn_primary, barn_primary)
    barn_door, found_barn_door := architecture.opening_layout_find(&barn_layout, .Front, .Service_Door, 0, 0)
    testing.expect(t, found_barn_door)
    if found_barn_door {
        testing.expect(t, barn_door.width >= 5.0)
        testing.expect(t, barn_door.height >= 5.0)
    }
    aisle_layout := architecture.architecture_opening_layout(structure, 1, barn_primary)
    aisle_face := barn.masses[1].local_x < 0 ? architecture.Face.Left : architecture.Face.Right
    aisle_door, found_aisle_door := architecture.opening_layout_find(&aisle_layout, aisle_face, .Service_Door, 0, 0)
    testing.expect(t, found_aisle_door)
    if found_aisle_door do testing.expect(t, aisle_door.width >= 3.8)

    structure.building.archetype = .Storehouse
    storehouse := architecture.architecture_footprint(structure)
    testing.expect_value(t, storehouse.count, 2)
    store_primary := architecture.architecture_frontage_mass_index(structure)
    store_layout := architecture.architecture_opening_layout(structure, store_primary, store_primary)
    store_door, found_store_door := architecture.opening_layout_find(&store_layout, .Front, .Service_Door, 0, 0)
    testing.expect(t, found_store_door)
    if found_store_door {
        testing.expect(t, store_door.width >= 4.8)
        testing.expect(t, store_door.height >= 4.5)
    }
    loading_layout := architecture.architecture_opening_layout(structure, 1, store_primary)
    loading_door, found_loading_door := architecture.opening_layout_find(&loading_layout, .Rear, .Service_Door, 0, 0)
    testing.expect(t, found_loading_door)
    if found_loading_door do testing.expect(t, loading_door.width >= 4.0)

    hall_cases := [2]struct {
        archetype:                     buildings.Archetype,
        seed:                          u32,
        minimum_width, minimum_height: f32,
    }{{.Workshop, 1, 3.2, 3.8}, {.Fishery, 0, 3.0, 3.6}}
    for test_case in hall_cases {
        structure.building.archetype = test_case.archetype
        structure.seed = test_case.seed
        primary := architecture.architecture_frontage_mass_index(structure)
        testing.expect_value(t, primary, 0)
        layout := architecture.architecture_opening_layout(structure, primary, primary)
        door, found_door := architecture.opening_layout_find(&layout, .Front, .Service_Door, 0, 0)
        testing.expectf(t, found_door, "productive hall lacks goods entrance archetype=%v", test_case.archetype)
        if found_door {
            testing.expect(t, door.width >= test_case.minimum_width)
            testing.expect(t, door.height >= test_case.minimum_height)
            for opening in layout.openings[:layout.count] {
                if opening.kind == .Door || opening.kind == .Service_Door do continue
                testing.expect(
                    t,
                    !architecture.opening_layout_conflicts_with_door(
                        &layout,
                        opening.face,
                        opening.horizontal,
                        opening.y,
                        opening.width,
                        opening.height,
                    ),
                )
            }
        }
    }
}

@(test)
architecture_barn_ranges_keep_high_hayloft_vents_above_loading_doors :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    structure.building.archetype = .Barn_Granary
    for seed in 0 ..< 64 {
        structure.seed = u32(seed)
        footprint := architecture.architecture_footprint(structure)
        primary := architecture.architecture_frontage_mass_index(structure)
        for mass, mass_index in footprint.masses[:footprint.count] {
            layout := architecture.architecture_opening_layout(structure, mass_index, primary)
            high_vents := 0
            for opening in layout.openings[:layout.count] {
                if opening.kind != .Vent do continue
                testing.expect(t, opening.width >= .70 && opening.width <= 1.05)
                testing.expect(t, opening.height >= .85 && opening.height <= 1.35)
                if opening.y >= structure.height * mass.height_scale * .60 {
                    high_vents += 1
                }
            }
            testing.expectf(
                t,
                high_vents > 0,
                "barn range lacks hayloft vent seed=%d mass=%d height=%.2f",
                seed,
                mass_index,
                structure.height * mass.height_scale,
            )
        }
    }
}

@(test)
architecture_low_barn_avoids_a_sealed_side_aisle :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 14, 14, 4, 4.8)
    structure.width, structure.depth, structure.height = 14, 14, 4.8
    structure.kind = .Architecture
    structure.seed = 0
    structure.building.archetype = .Barn_Granary

    low := architecture.architecture_footprint(structure)
    testing.expect_value(t, low.count, 1)
    low_layout := architecture.architecture_opening_layout(structure, 0, 0)
    front_doors, vents := 0, 0
    for opening in low_layout.openings[:low_layout.count] {
        if opening.face == .Front && opening.kind == .Service_Door do front_doors += 1
        if opening.kind == .Vent do vents += 1
    }
    testing.expect_value(t, front_doors, 1)
    testing.expectf(t, vents > 0, "low barn hall lost all ventilation")

    structure.height = 8.0
    tall := architecture.architecture_footprint(structure)
    testing.expect_value(t, tall.count, 2)
    primary := architecture.architecture_frontage_mass_index(structure)
    aisle_layout := architecture.architecture_opening_layout(structure, 1, primary)
    expected_face := tall.masses[1].local_x < 0 ? architecture.Face.Left : architecture.Face.Right
    aisle_doors, aisle_vents := 0, 0
    for opening in aisle_layout.openings[:aisle_layout.count] {
        if opening.face == expected_face && opening.kind == .Service_Door do aisle_doors += 1
        if opening.kind == .Vent do aisle_vents += 1
    }
    testing.expect_value(t, aisle_doors, 1)
    testing.expectf(t, aisle_vents > 0, "usable barn aisle lacks ventilation")
}

@(test)
architecture_barn_side_aisles_keep_serviceable_hall_connections :: proc(t: ^testing.T) {
    sizes := [5][3]f32 {
        {12, 12, 9.6},
        {14, 12, 9.6},
        {18, 16, 12},
        {24, 18, 24},
        {30, 24, 48},
    }
    for size in sizes {
        for seed in 0 ..< 64 {
            structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
            structure.width, structure.depth, structure.height = size[0], size[1], size[2]
            structure.kind = .Architecture
            structure.seed = u32(seed)
            structure.building.archetype = .Barn_Granary
            footprint := architecture.architecture_footprint(structure)
            testing.expect_value(t, footprint.count, 2)
            hall, aisle := footprint.masses[0], footprint.masses[1]
            overlap_x :=
                min(hall.local_x + hall.width * .5, aisle.local_x + aisle.width * .5) -
                max(hall.local_x - hall.width * .5, aisle.local_x - aisle.width * .5)
            testing.expectf(
                t,
                overlap_x >= 2.0 - .001,
                "barn side aisle has a pinched hall connection size=(%.1f,%.1f,%.1f) seed=%d overlap=%.2f",
                size[0],
                size[1],
                size[2],
                seed,
                overlap_x,
            )
        }
    }
}

@(test)
architecture_workshops_use_high_broad_daylight_instead_of_low_vents :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    structure.building.archetype = .Workshop
    for seed in 0 ..< 64 {
        structure.seed = u32(seed)
        footprint := architecture.architecture_footprint(structure)
        primary := architecture.architecture_frontage_mass_index(structure)
        for mass, mass_index in footprint.masses[:footprint.count] {
            layout := architecture.architecture_opening_layout(structure, mass_index, primary)
            windows, vents := 0, 0
            for opening in layout.openings[:layout.count] {
                if opening.kind == .Vent do vents += 1
                if opening.kind != .Window do continue
                windows += 1
                testing.expect(t, opening.width >= 1.20 && opening.width <= 1.80)
                testing.expect(t, opening.height >= 1.10 && opening.height <= 1.60)
                testing.expect(t, opening.y >= structure.height * mass.height_scale * .70)
            }
            testing.expectf(t, windows > 0, "workshop range lacks high daylight seed=%d mass=%d", seed, mass_index)
            testing.expectf(t, vents == 0, "workshop retained storage vents seed=%d mass=%d", seed, mass_index)
        }
    }
}

@(test)
architecture_fisheries_separate_daylit_work_halls_from_vented_service_ranges :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    structure.building.archetype = .Fishery
    for seed in 0 ..< 64 {
        structure.seed = u32(seed)
        footprint := architecture.architecture_footprint(structure)
        primary := architecture.architecture_frontage_mass_index(structure)
        main_layout := architecture.architecture_opening_layout(structure, 0, primary)
        main_windows, main_vents := 0, 0
        for opening in main_layout.openings[:main_layout.count] {
            if opening.kind == .Vent do main_vents += 1
            if opening.kind != .Window do continue
            main_windows += 1
            testing.expect(t, opening.width >= 1.00 && opening.width <= 1.45)
            testing.expect(t, opening.height >= 1.00 && opening.height <= 1.50)
            testing.expect(t, opening.y >= structure.height * footprint.masses[0].height_scale * .70)
        }
        testing.expectf(t, main_windows > 0, "fishery work hall lacks daylight seed=%d", seed)
        testing.expectf(t, main_vents == 0, "fishery work hall retained low vents seed=%d", seed)

        for _, mass_index in footprint.masses[1:footprint.count] {
            service_layout := architecture.architecture_opening_layout(structure, mass_index + 1, primary)
            service_vents := 0
            service_windows := 0
            for opening in service_layout.openings[:service_layout.count] {
                if opening.kind == .Vent do service_vents += 1
                if opening.kind == .Window do service_windows += 1
            }
            testing.expectf(
                t,
                service_vents > 0,
                "fishery service range lacks vents seed=%d mass=%d",
                seed,
                mass_index + 1,
            )
            testing.expectf(
                t,
                service_windows == 0,
                "fishery service range received work-hall windows seed=%d mass=%d",
                seed,
                mass_index + 1,
            )
        }
    }
}

@(test)
architecture_storehouses_keep_secure_vents_high_above_storage_walls :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    structure.building.archetype = .Storehouse
    for seed in 0 ..< 64 {
        structure.seed = u32(seed)
        footprint := architecture.architecture_footprint(structure)
        primary := architecture.architecture_frontage_mass_index(structure)
        for mass, mass_index in footprint.masses[:footprint.count] {
            layout := architecture.architecture_opening_layout(structure, mass_index, primary)
            vents, windows := 0, 0
            for opening in layout.openings[:layout.count] {
                if opening.kind == .Window do windows += 1
                if opening.kind != .Vent do continue
                vents += 1
                testing.expect(t, opening.width >= .70 && opening.width <= .95)
                testing.expect(t, opening.height >= .70 && opening.height <= 1.10)
                testing.expect(t, opening.y >= structure.height * mass.height_scale * .70)
            }
            testing.expectf(t, vents > 0, "storehouse range lacks secure vents seed=%d mass=%d", seed, mass_index)
            testing.expectf(
                t,
                windows == 0,
                "storehouse range received residential windows seed=%d mass=%d",
                seed,
                mass_index,
            )
        }
    }
}

@(test)
architecture_harbor_dispatch_wings_use_broader_upper_lookout_windows :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    structure.building.archetype = .Harbor_Office
    for seed in 0 ..< 64 {
        structure.seed = u32(seed)
        footprint := architecture.architecture_footprint(structure)
        testing.expect_value(t, footprint.count, 3)
        primary := architecture.architecture_frontage_mass_index(structure)
        layout := architecture.architecture_opening_layout(structure, 1, primary)
        lower_max, upper_max := f32(0), f32(0)
        highest_row := -1
        for opening in layout.openings[:layout.count] {
            if opening.kind == .Window do highest_row = max(highest_row, opening.row)
        }
        for opening in layout.openings[:layout.count] {
            if opening.kind != .Window do continue
            if opening.row == highest_row {
                upper_max = max(upper_max, opening.width)
                testing.expect(t, opening.height <= 2.25)
            } else {
                lower_max = max(lower_max, opening.width)
            }
        }
        testing.expectf(t, highest_row > 0, "dispatch wing lacks upper lookout row seed=%d", seed)
        testing.expectf(
            t,
            upper_max > lower_max + .05,
            "dispatch lookout not broader seed=%d lower=%.2f upper=%.2f",
            seed,
            lower_max,
            upper_max,
        )
    }
}

@(test)
architecture_service_compound_ranges_keep_an_exposed_vent :: proc(t: ^testing.T) {
    archetypes := [4]buildings.Archetype{.Storehouse, .Fishery, .Barn_Granary, .Mill}
    sizes := [5][3]f32{{8, 3, 4.8}, {10, 10, 7.2}, {14, 14, 9.6}, {30, 24, 24}, {60, 36, 48}}
    for size in sizes {
        structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
        structure.width, structure.depth, structure.height = size[0], size[1], size[2]
        structure.kind = .Architecture
        for archetype in archetypes {
            structure.building.archetype = archetype
            for seed in 0 ..< 64 {
                structure.seed = u32(seed)
                footprint := architecture.architecture_footprint(structure)
                if footprint.count <= 1 do continue
                primary := architecture.architecture_frontage_mass_index(structure)
                for _, mass_index in footprint.masses[:footprint.count] {
                    if mass_index == primary do continue
                    layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                    expected_kind :=
                        archetype == .Fishery && mass_index == 0 ? architecture.Opening_Kind.Window : architecture.Opening_Kind.Vent
                    found_opening := false
                    for opening in layout.openings[:layout.count] {
                        if opening.kind == expected_kind {
                            found_opening = true
                            break
                        }
                    }
                    testing.expectf(
                        t,
                        found_opening,
                        "productive range lacks role-specific opening archetype=%v size=(%.1f,%.1f,%.1f) seed=%d mass=%d kind=%v",
                        archetype,
                        size[0],
                        size[1],
                        size[2],
                        seed,
                        mass_index,
                        expected_kind,
                    )
                }
            }
        }
    }
}

@(test)
architecture_service_primary_masses_keep_a_door_clear_vent :: proc(t: ^testing.T) {
    archetypes := [7]buildings.Archetype {
        .Storehouse,
        .Barn_Granary,
        .Mill,
        .Campanile,
        .Fortress_Gate,
        .Cycladic_Bell,
        .Lighthouse,
    }
    sizes := [2][3]f32{{14, 14, 9.6}, {30, 24, 24}}
    for archetype in archetypes {
        for size in sizes {
            for seed in 0 ..< 64 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                primary := architecture.architecture_frontage_mass_index(structure)
                layout := architecture.architecture_opening_layout(structure, primary, primary)
                found_vent := false
                for opening in layout.openings[:layout.count] {
                    if opening.kind != .Vent do continue
                    found_vent = true
                    testing.expect(
                        t,
                        !architecture.opening_layout_conflicts_with_door(
                            &layout,
                            opening.face,
                            opening.horizontal,
                            opening.y,
                            opening.width,
                            opening.height,
                        ),
                    )
                }
                testing.expectf(
                    t,
                    found_vent,
                    "primary service mass has no vent archetype=%v seed=%d size=(%.1f,%.1f,%.1f)",
                    archetype,
                    seed,
                    size[0],
                    size[1],
                    size[2],
                )
            }
        }
    }
}

@(test)
architecture_compound_frontage_windows_clear_the_door :: proc(t: ^testing.T) {
    for seed in 0 ..< 64 {
        structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
        structure.kind = .Architecture
        structure.seed = u32(seed)
        structure.building.archetype = .Dwelling
        footprint := architecture.architecture_footprint(structure)
        if footprint.count <= 1 do continue

        primary := architecture.architecture_frontage_mass_index(structure)
        layout := architecture.architecture_opening_layout(structure, primary, primary)
        door, found := architecture.opening_layout_find(&layout, .Front, .Door, 0, 0)
        testing.expect(t, found)
        if !found do continue

        for opening in layout.openings[:layout.count] {
            if opening.face != .Front || opening.kind != .Window || opening.row != 0 do continue
            clearance := math.abs(opening.horizontal) - opening.width * .5 - door.width * .5
            testing.expect(t, clearance >= architecture.ARCHITECTURE_DOOR_WINDOW_MARGIN - .001)
        }
    }
}

@(test)
architecture_mixed_use_wing_windows_clear_service_doors :: proc(t: ^testing.T) {
    sizes := [3][3]f32{{14, 14, 9.6}, {30, 24, 19.2}, {60, 36, 38.4}}
    for size in sizes {
        structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
        structure.width, structure.depth, structure.height = size[0], size[1], size[2]
        structure.kind = .Architecture
        structure.building.archetype = .Mixed_Use_Dwelling
        for seed in 0 ..< 64 {
            structure.seed = u32(seed)
            footprint := architecture.architecture_footprint(structure)
            if footprint.count <= 1 do continue
            primary := architecture.architecture_frontage_mass_index(structure)
            for mass_index in 1 ..< footprint.count {
                layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                for opening in layout.openings[:layout.count] {
                    if opening.kind != .Window do continue
                    testing.expect(
                        t,
                        !architecture.opening_layout_conflicts_with_door(
                            &layout,
                            opening.face,
                            opening.horizontal,
                            opening.y,
                            opening.width,
                            opening.height,
                        ),
                    )
                }
            }
        }
    }
}

@(test)
architecture_mixed_use_private_entries_are_part_of_the_opening_layout :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 19.2)
    structure.kind = .Architecture
    structure.building.archetype = .Mixed_Use_Dwelling
    seeds := [2]u32{43, 5}
    expected_counts := [2]int{2, 3}
    for case_index in 0 ..< len(seeds) {
        structure.seed = seeds[case_index]
        footprint := architecture.architecture_footprint(structure)
        testing.expect_value(t, footprint.count, expected_counts[case_index])
        primary := architecture.architecture_frontage_mass_index(structure)
        private_entries := 0
        for mass_index in 1 ..< footprint.count {
            layout := architecture.architecture_opening_layout(structure, mass_index, primary)
            expected_face :=
                footprint.count == 2 ? architecture.Face.Rear : (mass_index == 1 ? architecture.Face.Right : architecture.Face.Left)
            for opening in layout.openings[:layout.count] {
                if opening.kind == .Service_Door {
                    private_entries += 1
                    testing.expect(t, opening.face == expected_face)
                    testing.expect(t, math.abs(opening.horizontal) <= .001)
                    testing.expect(t, math.abs(opening.y - 1.51) <= .001)
                    testing.expect(t, math.abs(opening.width - 1.66) <= .001)
                    testing.expect(t, math.abs(opening.height - 3.02) <= .001)
                } else if opening.kind == .Window {
                    testing.expect(
                        t,
                        !architecture.opening_layout_conflicts_with_door(
                            &layout,
                            opening.face,
                            opening.horizontal,
                            opening.y,
                            opening.width,
                            opening.height,
                        ),
                    )
                }
            }
        }
        testing.expect_value(t, private_entries, footprint.count - 1)
    }
}

@(test)
architecture_compact_masses_generate_grounded_single_storey_openings :: proc(t: ^testing.T) {
    structure := terrain.structure_make(0, 0, 8.2, 6.4, 0, 4.8)
    structure.kind = .Architecture
    structure.width, structure.depth, structure.height = 8.2, 6.4, 4.8
    structure.building.archetype = .Harbor_Office
    layout := architecture.architecture_opening_layout(structure, 0, 0)
    testing.expect(t, layout.count > 0)
    found_door, found_window := false, false
    for opening in layout.openings[:layout.count] {
        testing.expect(t, opening.y - opening.height * .5 >= -.001)
        testing.expect(t, opening.y + opening.height * .5 <= structure.height + .001)
        if opening.kind == .Door do found_door = true
        if opening.kind == .Window do found_window = true
    }
    testing.expect(t, found_door)
    testing.expect(t, found_window)
}

@(test)
architecture_window_rows_fit_actual_opening_height :: proc(t: ^testing.T) {
    heights := [6]f32{4.8, 7.2, 7.5, 9.6, 12.0, 16.8}
    opening_heights := [3]f32{1.55, 1.95, 2.35}
    for height in heights {
        for opening_height in opening_heights {
            rows := architecture.facade_opening_row_count(height, opening_height)
            testing.expect(t, rows >= 1 && rows <= architecture.facade_floor_count(height))
            previous_y := -f32(1e20)
            for row in 0 ..< rows {
                y := architecture.facade_opening_row_y_for_count(height, row, rows, opening_height)
                testing.expect(t, y - opening_height * .5 >= 1.45 - .001)
                testing.expect(t, y + opening_height * .5 <= height + .001)
                if rows > 1 && row == rows - 1 {
                    testing.expect(t, y + opening_height * .5 <= height - 1.45 + .001)
                }
                if row > 0 do testing.expect(t, y - previous_y >= opening_height + .35 - .001)
                previous_y = y
            }
        }
    }
    testing.expect_value(t, architecture.facade_opening_row_count(7.2, 2.35), 1)
    testing.expect_value(t, architecture.facade_opening_row_count(9.6, 2.35), 2)
}

@(test)
architecture_facade_profiles_match_archetype_targets :: proc(t: ^testing.T) {
    dwelling := architecture.facade_profile(.Dwelling)
    testing.expect(t, dwelling.front_bays_min == 1 && dwelling.front_bays_max == 2)
    testing.expect(t, dwelling.side_bays_min == 1 && dwelling.side_bays_max == 2)
    testing.expect(t, dwelling.window_width_min >= 1.05 && dwelling.window_width_max <= 1.35)
    testing.expect(t, dwelling.opening_ratio_min == .08 && dwelling.opening_ratio_max == .14)

    townhouse := architecture.facade_profile(.Townhouse)
    testing.expect(t, townhouse.front_bays_min == 2 && townhouse.front_bays_max == 3)
    testing.expect(t, townhouse.side_bays_min == 2 && townhouse.side_bays_max == 3)
    testing.expect(t, townhouse.opening_ratio_min == .12 && townhouse.opening_ratio_max == .20)

    service := architecture.facade_profile(.Storehouse)
    testing.expect(t, service.service)
    testing.expect(t, service.front_bays_max == 2 && service.side_bays_max == 1)
    testing.expect(t, service.opening_ratio_max <= .08)

    civic := architecture.facade_profile(.Palace_Loggia)
    testing.expect(t, civic.front_bays_min == 3 && civic.front_bays_max == 5)
    testing.expect(t, civic.window_width_max <= 1.70)
    testing.expect(t, civic.opening_ratio_min == .15 && civic.opening_ratio_max == .24)

    market := architecture.facade_profile(.Market_Hall)
    testing.expect(t, market.front_bays_min > civic.front_bays_min)
    testing.expect(t, market.window_width_min > civic.window_width_min)
    testing.expect_value(t, market.rows_max, 2)
    testing.expect(t, market.opening_ratio_min == .04 && market.opening_ratio_max == .11)

    harbor := architecture.facade_profile(.Harbor_Office)
    testing.expect(t, harbor.window_width_max < civic.window_width_max)
    testing.expect(t, harbor.window_height_max < civic.window_height_max)
    testing.expect(t, harbor.opening_ratio_min == .045 && harbor.opening_ratio_max == .10)
    testing.expect_value(t, harbor.rows_max, 3)

    church := architecture.facade_profile(.Church)
    testing.expect(t, church.front_bays_min == 2 && church.front_bays_max == 3)
    testing.expect(t, church.window_width_max < civic.window_width_max)
    testing.expect(t, church.window_height_min > civic.window_height_min)
    testing.expect(t, church.window_height_max == 3.00)
    testing.expect_value(t, church.rows_max, 2)
    testing.expect(t, church.opening_ratio_min == .035 && church.opening_ratio_max == .08)

    monastery := architecture.facade_profile(.Monastery)
    testing.expect(t, monastery.front_bays_max < civic.front_bays_max)
    testing.expect(t, monastery.side_bays_max < civic.side_bays_max)
    testing.expect(t, monastery.window_width_max < civic.window_width_max)
    testing.expect(t, monastery.opening_ratio_min == .08)
    testing.expect(t, monastery.opening_ratio_max == .15)
}

@(test)
architecture_church_windows_use_at_most_two_vertical_tiers :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 18, 24, 4, 24)
    structure.kind = .Architecture
    structure.building.archetype = .Church
    found_upper_tier := false
    for seed in 0 ..< 64 {
        structure.seed = u32(seed)
        footprint := architecture.architecture_footprint(structure)
        primary := architecture.architecture_frontage_mass_index(structure)
        for _, mass_index in footprint.masses[:footprint.count] {
            layout := architecture.architecture_opening_layout(structure, mass_index, primary)
            for opening in layout.openings[:layout.count] {
                if opening.kind != .Window do continue
                testing.expectf(
                    t,
                    opening.row <= 1,
                    "church generated domestic third window tier seed=%d mass=%d face=%v row=%d",
                    seed,
                    mass_index,
                    opening.face,
                    opening.row,
                )
                if opening.row == 1 do found_upper_tier = true
            }
        }
    }
    testing.expect(t, found_upper_tier)
}

@(test)
architecture_market_hall_windows_use_broad_two_tier_clerestory :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    structure.building.archetype = .Market_Hall
    found_upper_tier := false
    for seed in 0 ..< 64 {
        structure.seed = u32(seed)
        footprint := architecture.architecture_footprint(structure)
        primary := architecture.architecture_frontage_mass_index(structure)
        layout := architecture.architecture_opening_layout(structure, primary, primary)
        trading_bays, ground_windows, clerestory_windows := 0, 0, 0
        for opening in layout.openings[:layout.count] {
            testing.expect(t, opening.row <= 1)
            if opening.face == .Front && opening.kind == .Loggia {
                trading_bays += 1
                testing.expect(t, opening.row == 0)
                testing.expect(t, opening.width >= 2.00 && opening.width <= 3.50)
                testing.expect(t, opening.height >= 3.40 && opening.height <= 4.60)
                testing.expect(t, math.abs(opening.y - opening.height * .5 - .20) <= .001)
            } else if opening.face == .Front && opening.kind == .Window {
                if opening.row == 0 {
                    ground_windows += 1
                } else {
                    clerestory_windows += 1
                    testing.expect(t, opening.width >= 1.40 && opening.width <= 1.90)
                    found_upper_tier = true
                }
            }
        }
        testing.expectf(
            t,
            trading_bays >= 4,
            "market frontage lacks open trading bays seed=%d bays=%d",
            seed,
            trading_bays,
        )
        testing.expectf(t, ground_windows == 0, "market retained glazed ground row seed=%d", seed)
        testing.expectf(
            t,
            clerestory_windows >= 4,
            "market lacks clerestory rhythm seed=%d windows=%d",
            seed,
            clerestory_windows,
        )
    }
    testing.expect(t, found_upper_tier)
}

@(test)
architecture_palaces_use_open_ground_loggia_bays_below_glazed_rooms :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    structure.building.archetype = .Palace_Loggia
    for seed in 0 ..< 64 {
        structure.seed = u32(seed)
        primary := architecture.architecture_frontage_mass_index(structure)
        layout := architecture.architecture_opening_layout(structure, primary, primary)
        loggia_bays, ground_windows, upper_windows := 0, 0, 0
        for opening in layout.openings[:layout.count] {
            if opening.face != .Front do continue
            if opening.kind == .Loggia {
                loggia_bays += 1
                testing.expect(t, opening.row == 0)
                testing.expect(t, opening.width >= 2.10 && opening.width <= 3.20)
                testing.expect(t, opening.height >= 3.80 && opening.height <= 4.80)
                testing.expect(t, math.abs(opening.y - opening.height * .5 - .25) <= .001)
            } else if opening.kind == .Window && opening.row == 0 {
                ground_windows += 1
            } else if opening.kind == .Window && opening.row > 0 {
                upper_windows += 1
            }
        }
        testing.expectf(t, loggia_bays >= 2, "palace frontage lacks open loggia seed=%d bays=%d", seed, loggia_bays)
        testing.expectf(t, ground_windows == 0, "palace retained glazed ground row seed=%d", seed)
        testing.expectf(t, upper_windows > 0, "palace lacks glazed upper rooms seed=%d", seed)
    }
}

@(test)
architecture_monastery_communal_range_opens_into_cloister_arcade :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    structure.building.archetype = .Monastery
    for seed in 0 ..< 64 {
        if seed % 4 != 0 do continue
        structure.seed = u32(seed)
        footprint := architecture.architecture_footprint(structure)
        testing.expect_value(t, footprint.count, 3)
        primary := architecture.architecture_frontage_mass_index(structure)
        testing.expect_value(t, primary, 0)
        layout := architecture.architecture_opening_layout(structure, 0, primary)
        arcade_bays, ground_windows, upper_windows := 0, 0, 0
        for opening in layout.openings[:layout.count] {
            if opening.face != .Front do continue
            if opening.kind == .Loggia {
                arcade_bays += 1
                testing.expect(t, opening.row == 0)
                testing.expect(t, opening.width >= 1.55 && opening.width <= 2.35)
                testing.expect(t, opening.height >= 3.20 && opening.height <= 4.20)
                testing.expect(t, math.abs(opening.y - opening.height * .5 - .25) <= .001)
            } else if opening.kind == .Window && opening.row == 0 {
                ground_windows += 1
            } else if opening.kind == .Window && opening.row > 0 {
                upper_windows += 1
            }
        }
        testing.expectf(t, arcade_bays >= 2, "monastery cloister lacks arcade seed=%d bays=%d", seed, arcade_bays)
        testing.expectf(t, ground_windows == 0, "monastery cloister retained glazed ground row seed=%d", seed)
        testing.expectf(t, upper_windows > 0, "monastery communal range lacks upper glazing seed=%d", seed)
    }
}

@(test)
architecture_small_seeds_vary_bay_counts_across_faces :: proc(t: ^testing.T) {
    // Stay below the 28 m broad-façade rhythm threshold; broad elevations
    // intentionally derive a stable geometric count while small façades keep
    // seed-driven bay variation.
    structure := terrain.structure_make(1300, 1300, 24, 24, 4, 19.2)
    structure.kind = .Architecture
    structure.building.archetype = .Townhouse
    profile := architecture.facade_profile(.Townhouse)
    rear_counts: [4]bool
    left_counts: [4]bool
    right_counts: [4]bool
    for seed in 0 ..< 32 {
        structure.seed = u32(seed)
        rear := architecture.facade_profile_bay_count(profile, structure, .Rear, false, structure.width)
        left := architecture.facade_profile_bay_count(profile, structure, .Left, false, structure.depth)
        right := architecture.facade_profile_bay_count(profile, structure, .Right, false, structure.depth)
        rear_counts[clamp(rear, 0, len(rear_counts) - 1)] = true
        left_counts[clamp(left, 0, len(left_counts) - 1)] = true
        right_counts[clamp(right, 0, len(right_counts) - 1)] = true
    }
    rear_variants, left_variants, right_variants := 0, 0, 0
    for present in rear_counts do if present do rear_variants += 1
    for present in left_counts do if present do left_variants += 1
    for present in right_counts do if present do right_variants += 1
    testing.expect(t, rear_variants > 1)
    testing.expect(t, left_variants > 1)
    testing.expect(t, right_variants > 1)
}

@(test)
architecture_urban_homes_keep_useful_side_window_rhythms :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 18, 14, 4, 14.4)
    structure.kind = .Architecture
    for archetype in ([2]buildings.Archetype{.Dwelling, .Townhouse}) {
        structure.building.archetype = archetype
        profile := architecture.facade_profile(archetype)
        expected_minimum := archetype == .Townhouse ? 2 : 1
        for seed in 0 ..< 32 {
            structure.seed = u32(seed)
            left := architecture.facade_profile_bay_count(
                profile,
                structure,
                .Left,
                false,
                structure.depth,
                structure.height,
            )
            right := architecture.facade_profile_bay_count(
                profile,
                structure,
                .Right,
                false,
                structure.depth,
                structure.height,
            )
            testing.expectf(
                t,
                left >= expected_minimum && right >= expected_minimum,
                "urban home side rhythm too sparse archetype=%v seed=%d left=%d right=%d",
                archetype,
                seed,
                left,
                right,
            )
        }
    }
}

@(test)
architecture_small_seeds_vary_window_dimensions_across_faces :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 19.2)
    structure.kind = .Architecture
    structure.building.archetype = .Townhouse
    profile := architecture.facade_profile(.Townhouse)
    front_widths: [32]bool
    rear_heights: [32]bool
    for seed in 0 ..< 32 {
        structure.seed = u32(seed)
        front_width, _ := architecture.facade_profile_window_size(profile, structure, .Front)
        _, rear_height := architecture.facade_profile_window_size(profile, structure, .Rear)
        width_bucket := clamp(
            int(
                math.round(
                    f64(
                        (front_width - profile.window_width_min) *
                        31 /
                        (profile.window_width_max - profile.window_width_min),
                    ),
                ),
            ),
            0,
            31,
        )
        height_bucket := clamp(
            int(
                math.round(
                    f64(
                        (rear_height - profile.window_height_min) *
                        31 /
                        (profile.window_height_max - profile.window_height_min),
                    ),
                ),
            ),
            0,
            31,
        )
        front_widths[width_bucket] = true
        rear_heights[height_bucket] = true
        testing.expect(t, front_width >= profile.window_width_min && front_width <= profile.window_width_max)
        testing.expect(t, rear_height >= profile.window_height_min && rear_height <= profile.window_height_max)
    }
    width_variants, height_variants := 0, 0
    for present in front_widths do if present do width_variants += 1
    for present in rear_heights do if present do height_variants += 1
    testing.expect(t, width_variants >= 8)
    testing.expect(t, height_variants >= 8)
}

@(test)
architecture_window_height_module_aligns_around_corners :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 19.2)
    structure.kind = .Architecture
    structure.building.archetype = .Townhouse
    profile := architecture.facade_profile(.Townhouse)
    faces := [4]architecture.Face{.Front, .Rear, .Left, .Right}
    for seed in 0 ..< 256 {
        structure.seed = u32(seed)
        _, expected_height := architecture.facade_profile_window_size(profile, structure, .Front)
        distinct_width := false
        expected_width, _ := architecture.facade_profile_window_size(profile, structure, .Front)
        for face in faces[1:] {
            width, height := architecture.facade_profile_window_size(profile, structure, face)
            testing.expect(t, height == expected_height)
            if width != expected_width do distinct_width = true
        }
        if seed > 0 do testing.expect(t, distinct_width)
    }
}

@(test)
architecture_compound_window_rows_share_parent_pitch :: proc(t: ^testing.T) {
    archetypes := [5]buildings.Archetype{.Dwelling, .Townhouse, .Mixed_Use_Dwelling, .Palace_Loggia, .Monastery}
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    for archetype in archetypes {
        structure.building.archetype = archetype
        for seed in 0 ..< 32 {
            structure.seed = u32(seed)
            footprint := architecture.architecture_footprint(structure)
            if footprint.count <= 1 do continue
            primary := architecture.architecture_frontage_mass_index(structure)
            expected_y: [16][16]f32
            found_row: [16][16]bool
            for mass, mass_index in footprint.masses[:footprint.count] {
                storeys := clamp(
                    architecture.facade_floor_count(structure.height * mass.height_scale),
                    0,
                    len(expected_y) - 1,
                )
                layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                for opening in layout.openings[:layout.count] {
                    if opening.kind != .Window || opening.row <= 0 do continue
                    row := clamp(opening.row, 0, len(expected_y[storeys]) - 1)
                    if !found_row[storeys][row] {
                        expected_y[storeys][row], found_row[storeys][row] = opening.y, true
                    } else {
                        testing.expect(t, math.abs(opening.y - expected_y[storeys][row]) <= .001)
                    }
                }
            }
        }
    }
}

@(test)
architecture_ordinary_window_rows_share_vertical_bay_centers :: proc(t: ^testing.T) {
    archetypes := [7]buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Post_Office,
        .Clinic,
        .Harbor_Office,
        .Monastery,
    }
    sizes := [3][3]f32{{18, 18, 9.6}, {30, 24, 24}, {60, 36, 48}}
    faces := [4]architecture.Face{.Front, .Rear, .Left, .Right}
    for archetype in archetypes {
        for size in sizes {
            for seed in 0 ..< 128 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                primary := architecture.architecture_frontage_mass_index(structure)
                for _, mass_index in footprint.masses[:footprint.count] {
                    layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                    for face in faces {
                        for row in 1 ..< 16 {
                            current_count, reference_count, aligned := 0, 0, 0
                            closest := f32(1000)
                            for opening in layout.openings[:layout.count] {
                                if opening.face != face || opening.kind != .Window do continue
                                if opening.row == row do current_count += 1
                                if opening.row == 0 do reference_count += 1
                            }
                            if current_count == 0 || reference_count == 0 do continue
                            for opening in layout.openings[:layout.count] {
                                if opening.face != face || opening.kind != .Window || opening.row != row {
                                    continue
                                }
                                for reference in layout.openings[:layout.count] {
                                    if reference.face == face && reference.kind == .Window && reference.row == 0 {
                                        closest = min(closest, math.abs(reference.horizontal - opening.horizontal))
                                    }
                                    if reference.face == face &&
                                       reference.kind == .Window &&
                                       reference.row == 0 &&
                                       math.abs(reference.horizontal - opening.horizontal) <= .25 {
                                        aligned += 1
                                        break
                                    }
                                }
                            }
                            // A ground-floor entrance may move panes flanking
                            // its jambs, but at least half of every ordinary
                            // row should retain a readable vertical stack.
                            shared_count := min(current_count, reference_count)
                            required := shared_count < 2 ? 0 : max(1, shared_count / 2)
                            testing.expectf(
                                t,
                                aligned >= required,
                                "window rows drift across storeys archetype=%v size=(%.1f,%.1f,%.1f) seed=%d mass=%d face=%v row=%d aligned=%d required=%d counts=(%d,%d) closest=%.2f",
                                archetype,
                                size[0],
                                size[1],
                                size[2],
                                seed,
                                mass_index,
                                face,
                                row,
                                aligned,
                                required,
                                current_count,
                                reference_count,
                                closest,
                            )
                            if aligned < required do return
                        }
                    }
                }
            }
        }
    }
}

@(test)
architecture_broad_occupied_facades_emphasize_a_principal_floor_without_extra_glazing :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 60, 36, 4, 48)
    structure.kind = .Architecture
    structure.seed = 42
    structure.building.archetype = .Townhouse
    layout := architecture.architecture_opening_layout(structure, 0, 0)

    principal, ordinary: architecture.Opening
    found_principal, found_ordinary := false, false
    for opening in layout.openings[:layout.count] {
        if opening.face != .Front || opening.kind != .Window do continue
        if opening.row == 1 && !found_principal {
            principal, found_principal = opening, true
        } else if opening.row == 2 && opening.column == principal.column {
            ordinary, found_ordinary = opening, true
        }
    }

    testing.expect(t, found_principal && found_ordinary)
    if found_principal && found_ordinary {
        testing.expect(t, principal.width >= ordinary.width * 1.10)
        testing.expect(t, principal.height < ordinary.height)
        testing.expect(t, math.abs(principal.width * principal.height - ordinary.width * ordinary.height) < .001)
        testing.expect(t, math.abs(principal.horizontal - ordinary.horizontal) < .001)
    }
}

@(test)
architecture_mirrored_courtyard_wings_share_facade_grammar :: proc(t: ^testing.T) {
    cases := [4]struct {
        archetype: buildings.Archetype,
        seed:      u32,
    }{{.Dwelling, 3}, {.Mixed_Use_Dwelling, 5}, {.Palace_Loggia, 0}, {.Monastery, 0}}
    faces := [4]architecture.Face{.Front, .Rear, .Left, .Right}
    structure := terrain.structure_make(1300, 1300, 30, 24, 4, 24)
    structure.kind = .Architecture
    for test_case in cases {
        structure.building.archetype = test_case.archetype
        structure.seed = test_case.seed
        footprint := architecture.architecture_footprint(structure)
        testing.expect_value(t, footprint.count, 3)
        profile := architecture.facade_profile(test_case.archetype)
        left_layout := architecture.architecture_opening_layout(structure, 1, 0)
        right_layout := architecture.architecture_opening_layout(structure, 2, 0)
        for face in faces {
            counterpart := face
            if face == .Left {
                counterpart = .Right
            } else if face == .Right {
                counterpart = .Left
            }
            canonical := architecture.architecture_paired_profile_face(footprint, 2, counterpart)
            testing.expect_value(t, canonical, face)
            left_span := architecture.face_span(footprint.masses[1], face)
            right_span := architecture.face_span(footprint.masses[2], counterpart)
            left_columns := architecture.facade_profile_bay_count(profile, structure, face, false, left_span)
            right_columns := architecture.facade_profile_bay_count(profile, structure, canonical, false, right_span)
            testing.expect_value(t, left_columns, right_columns)
            left_width, left_height := architecture.facade_profile_window_size(profile, structure, face)
            right_width, right_height := architecture.facade_profile_window_size(profile, structure, canonical)
            testing.expect(t, left_width == right_width && left_height == right_height)

            left_count, right_count := 0, 0
            for opening in left_layout.openings[:left_layout.count] {
                if opening.face == face && (opening.kind == .Window || opening.kind == .Vent) do left_count += 1
            }
            for opening in right_layout.openings[:right_layout.count] {
                if opening.face == counterpart && (opening.kind == .Window || opening.kind == .Vent) do right_count += 1
            }
            testing.expect_value(t, left_count, right_count)
        }
    }
}

@(test)
architecture_very_wide_facades_extend_window_rhythm_to_wall_edges :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 60, 18, 4, 19.2)
    structure.kind = .Architecture
    structure.seed = 512
    structure.building.archetype = .Townhouse

    profile := architecture.facade_profile(structure.building.archetype)
    columns := architecture.facade_profile_bay_count(profile, structure, .Front, true, structure.width)
    testing.expect(t, columns >= 13)

    window_width, _ := architecture.facade_profile_window_size(profile, structure, .Front)
    left := architecture.facade_bay_center(structure.width, window_width, columns, 0)
    right := architecture.facade_bay_center(structure.width, window_width, columns, columns - 1)
    testing.expect(t, left < -structure.width * .40)
    testing.expect(t, right > structure.width * .40)

    service := architecture.facade_profile(.Storehouse)
    service_columns := architecture.facade_profile_bay_count(service, structure, .Front, true, structure.width)
    testing.expect(t, service_columns <= service.front_bays_max)
}

@(test)
architecture_broad_facades_group_bays_around_a_legible_centre :: proc(t: ^testing.T) {
    span, window_width := f32(60), f32(1.35)
    column_counts := [2]int{13, 14}
    for columns in column_counts {
        centres: [14]f32
        for column in 0 ..< columns {
            centres[column] = architecture.facade_bay_center(span, window_width, columns, column)
        }

        // Preserve a balanced elevation and the same useful edge reach.
        testing.expect(t, math.abs(centres[0] + centres[columns - 1]) < .001)
        testing.expect(t, centres[0] < -span * .40)
        testing.expect(t, centres[columns - 1] > span * .40)

        centre_left := columns / 2 - 1
        centre_right := columns / 2
        if columns % 2 == 1 do centre_right += 1
        central_gap := centres[centre_right] - centres[centre_left]
        wing_gap := centres[1] - centres[0]
        testing.expectf(
            t,
            central_gap > wing_gap * 1.20,
            "broad facade lacks central hierarchy columns=%d central=%.2f wing=%.2f",
            columns,
            central_gap,
            wing_gap,
        )
    }
}

@(test)
architecture_broad_facades_meet_profile_opening_ratio_floor :: proc(t: ^testing.T) {
    archetypes := [7]buildings.Archetype {
        .Dwelling,
        .Townhouse,
        .Mixed_Use_Dwelling,
        .Palace_Loggia,
        .Market_Hall,
        .Monastery,
        .Church,
    }
    structure := terrain.structure_make(1300, 1300, 60, 36, 4, 48)
    structure.kind = .Architecture
    for archetype in archetypes {
        structure.building.archetype = archetype
        for seed in 0 ..< 64 {
            structure.seed = u32(seed)
            profile := architecture.facade_profile(archetype)
            window_width, window_height := architecture.facade_profile_window_size(profile, structure, .Front)
            rows := architecture.facade_profile_row_count(profile, structure.height, window_height)
            columns := architecture.facade_profile_bay_count(
                profile,
                structure,
                .Front,
                true,
                structure.width,
                structure.height,
            )
            nominal_ratio := f32(columns * rows) * window_width * window_height / (structure.width * structure.height)
            testing.expectf(
                t,
                nominal_ratio >= profile.opening_ratio_min - .001,
                "broad facade misses ratio archetype=%v seed=%d ratio=%.3f target=%.3f columns=%d rows=%d",
                archetype,
                seed,
                nominal_ratio,
                profile.opening_ratio_min,
                columns,
                rows,
            )
            area_per_column := window_width * window_height * f32(rows)
            minimum_count := int(
                math.ceil(f64(profile.opening_ratio_min * structure.width * structure.height / area_per_column)),
            )
            maximum_count := int(
                math.floor(f64(profile.opening_ratio_max * structure.width * structure.height / area_per_column)),
            )
            if maximum_count >= minimum_count {
                testing.expectf(
                    t,
                    nominal_ratio <= profile.opening_ratio_max + .001,
                    "broad facade exceeds ratio archetype=%v seed=%d ratio=%.3f target=%.3f columns=%d rows=%d",
                    archetype,
                    seed,
                    nominal_ratio,
                    profile.opening_ratio_max,
                    columns,
                    rows,
                )
            }
        }
    }
}

@(test)
architecture_broad_primary_facades_meet_actual_opening_ratio_floor :: proc(t: ^testing.T) {
    archetypes := [12]buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Post_Office,
        .Clinic,
        .Palace_Loggia,
        .Harbor_Office,
        .Market_Hall,
        .Monastery,
        .Church,
    }
    structure := terrain.structure_make(1300, 1300, 60, 36, 4, 48)
    structure.kind = .Architecture
    for archetype in archetypes {
        structure.building.archetype = archetype
        profile := architecture.facade_profile(archetype)
        for seed in 0 ..< 64 {
            structure.seed = u32(seed)
            footprint := architecture.architecture_footprint(structure)
            primary := architecture.architecture_frontage_mass_index(structure)
            mass := footprint.masses[primary]
            layout := architecture.architecture_opening_layout(structure, primary, primary)
            opening_area := f32(0)
            for opening in layout.openings[:layout.count] {
                if opening.face == .Front && (opening.kind == .Window || opening.kind == .Loggia) {
                    opening_area += opening.width * opening.height
                }
            }
            wall_area := architecture.architecture_exposed_face_area(footprint, primary, .Front, structure.height)
            testing.expect(t, wall_area > 0)
            actual_ratio := opening_area / wall_area
            testing.expectf(
                t,
                actual_ratio >= profile.opening_ratio_min - .001,
                "actual broad facade misses ratio archetype=%v seed=%d ratio=%.3f target=%.3f openings=%d mass=(%.1f,%.1f)",
                archetype,
                seed,
                actual_ratio,
                profile.opening_ratio_min,
                layout.count,
                mass.width,
                structure.height * mass.height_scale,
            )
            testing.expectf(
                t,
                actual_ratio <= profile.opening_ratio_max + .001,
                "actual broad facade exceeds ratio archetype=%v seed=%d ratio=%.3f target=%.3f",
                archetype,
                seed,
                actual_ratio,
                profile.opening_ratio_max,
            )
        }
    }
}

@(test)
architecture_compact_primary_facades_respect_actual_opening_ratio_ceiling :: proc(t: ^testing.T) {
    archetypes := [7]buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Post_Office,
        .Clinic,
        .Harbor_Office,
        .Church,
    }
    sizes := [3][3]f32{{8, 6, 4.8}, {12, 12, 7.2}, {14, 14, 9.6}}
    for archetype in archetypes {
        profile := architecture.facade_profile(archetype)
        for size in sizes {
            for seed in 0 ..< 64 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                primary := architecture.architecture_frontage_mass_index(structure)
                layout := architecture.architecture_opening_layout(structure, primary, primary)
                opening_area := f32(0)
                for opening in layout.openings[:layout.count] {
                    if opening.face == .Front && (opening.kind == .Window || opening.kind == .Loggia) {
                        opening_area += opening.width * opening.height
                    }
                }
                wall_area := architecture.architecture_exposed_face_area(footprint, primary, .Front, structure.height)
                if wall_area <= 0 do continue
                actual_ratio := opening_area / wall_area
                testing.expectf(
                    t,
                    actual_ratio <= profile.opening_ratio_max + .001,
                    "compact facade exceeds ratio archetype=%v size=(%.1f,%.1f,%.1f) seed=%d ratio=%.3f target=%.3f",
                    archetype,
                    size[0],
                    size[1],
                    size[2],
                    seed,
                    actual_ratio,
                    profile.opening_ratio_max,
                )
            }
        }
    }
}

@(test)
architecture_compact_secondary_faces_avoid_repeated_overglazing :: proc(t: ^testing.T) {
    archetypes := [7]buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Post_Office,
        .Clinic,
        .Harbor_Office,
        .Church,
    }
    sizes := [2][3]f32{{12, 12, 7.2}, {14, 14, 9.6}}
    faces := [4]architecture.Face{.Front, .Rear, .Left, .Right}
    for archetype in archetypes {
        profile := architecture.facade_profile(archetype)
        for size in sizes {
            for seed in 0 ..< 64 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                primary := architecture.architecture_frontage_mass_index(structure)
                for _, mass_index in footprint.masses[:footprint.count] {
                    layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                    for face in faces {
                        opening_area := f32(0)
                        opening_count := 0
                        for opening in layout.openings[:layout.count] {
                            if opening.face == face && (opening.kind == .Window || opening.kind == .Loggia) {
                                opening_area += opening.width * opening.height
                                opening_count += 1
                                if opening.kind == .Window {
                                    testing.expectf(
                                        t,
                                        opening.width >= .55 && opening.height >= .75,
                                        "compact daylight opening became a pinhole archetype=%v size=(%.1f,%.1f,%.1f) seed=%d mass=%d face=%v dimensions=(%.2f,%.2f)",
                                        archetype,
                                        size[0],
                                        size[1],
                                        size[2],
                                        seed,
                                        mass_index,
                                        face,
                                        opening.width,
                                        opening.height,
                                    )
                                }
                            }
                        }
                        if opening_count == 0 do continue
                        wall_area := architecture.architecture_exposed_face_area(
                            footprint,
                            mass_index,
                            face,
                            structure.height,
                        )
                        if wall_area <= 0 do continue
                        actual_ratio := opening_area / wall_area
                        testing.expectf(
                            t,
                            actual_ratio <= profile.opening_ratio_max + .001,
                            "compact secondary face exceeds ratio archetype=%v size=(%.1f,%.1f,%.1f) seed=%d mass=%d face=%v ratio=%.3f target=%.3f",
                            archetype,
                            size[0],
                            size[1],
                            size[2],
                            seed,
                            mass_index,
                            face,
                            actual_ratio,
                            profile.opening_ratio_max,
                        )
                    }
                }
            }
        }
    }
}

@(test)
architecture_generated_windows_never_collapse_to_pinhole_glazing :: proc(t: ^testing.T) {
    archetypes := []buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Shop_House,
        .Mixed_Use_Dwelling,
        .Post_Office,
        .Clinic,
        .Workshop,
        .Storehouse,
        .Fishery,
        .Barn_Granary,
        .Mill,
        .Palace_Loggia,
        .Harbor_Office,
        .Market_Hall,
        .Monastery,
        .Church,
        .Fortress_Gate,
    }
    sizes := [6][3]f32 {
        {8, 6, 4.5},
        {14, 14, 7.2},
        {18, 18, 9.6},
        {30, 24, 24},
        {60, 36, 48},
        {96, 54, 72},
    }
    for archetype in archetypes {
        for size in sizes {
            for seed in 0 ..< 128 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                primary := architecture.architecture_frontage_mass_index(structure)
                for _, mass_index in footprint.masses[:footprint.count] {
                    layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                    for opening in layout.openings[:layout.count] {
                        if opening.kind != .Window do continue
                        if opening.width < .55 || opening.height < .75 {
                            testing.expectf(
                                t,
                                false,
                                "generated window collapsed to pinhole archetype=%v size=(%.1f,%.1f,%.1f) seed=%d mass=%d face=%v row=%d dimensions=(%.3f,%.3f)",
                                archetype,
                                size[0],
                                size[1],
                                size[2],
                                seed,
                                mass_index,
                                opening.face,
                                opening.row,
                                opening.width,
                                opening.height,
                            )
                            return
                        }
                    }
                }
            }
        }
    }
}

@(test)
architecture_broad_compound_faces_respect_actual_glazing_ceiling :: proc(t: ^testing.T) {
    archetypes := [8]buildings.Archetype {
        .Dwelling,
        .Farmstead,
        .Townhouse,
        .Post_Office,
        .Clinic,
        .Harbor_Office,
        .Church,
        .Legacy,
    }
    faces := [4]architecture.Face{.Front, .Rear, .Left, .Right}
    sizes := [3][3]f32{{30, 24, 24}, {60, 36, 48}, {96, 54, 72}}
    for archetype in archetypes {
        profile := architecture.facade_profile(archetype)
        for size in sizes {
          for seed in 0 ..< 128 {
            structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
            structure.width, structure.depth, structure.height = size[0], size[1], size[2]
            structure.kind = .Architecture
            structure.seed = u32(seed)
            structure.building.archetype = archetype
            footprint := architecture.architecture_footprint(structure)
            primary := architecture.architecture_frontage_mass_index(structure)
            for _, mass_index in footprint.masses[:footprint.count] {
                layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                for face in faces {
                    glazing_area := f32(0)
                    for opening in layout.openings[:layout.count] {
                        if opening.face == face && opening.kind == .Window {
                            glazing_area += opening.width * opening.height
                            testing.expectf(
                                t,
                                opening.width >= .55 && opening.height >= .75,
                                "broad exposed-area normalization made a pinhole archetype=%v seed=%d mass=%d face=%v dimensions=(%.2f,%.2f)",
                                archetype,
                                seed,
                                mass_index,
                                face,
                                opening.width,
                                opening.height,
                            )
                        }
                    }
                    if glazing_area <= .001 do continue
                    wall_area := architecture.architecture_exposed_face_area(
                        footprint,
                        mass_index,
                        face,
                        structure.height,
                    )
                    if wall_area <= .001 do continue
                    actual_ratio := glazing_area / wall_area
                    testing.expectf(
                        t,
                        actual_ratio <= profile.opening_ratio_max + .001,
                        "broad compound face exceeds glazing ceiling archetype=%v seed=%d mass=%d face=%v ratio=%.3f target=%.3f",
                        archetype,
                        seed,
                        mass_index,
                        face,
                        actual_ratio,
                        profile.opening_ratio_max,
                    )
                }
            }
          }
        }
    }
}

@(test)
architecture_broad_exposed_compound_faces_meet_actual_glazing_floor :: proc(t: ^testing.T) {
    archetypes := [6]buildings.Archetype {
        .Dwelling,
        .Townhouse,
        .Mixed_Use_Dwelling,
        .Palace_Loggia,
        .Monastery,
        .Church,
    }
    faces := [4]architecture.Face{.Front, .Rear, .Left, .Right}
    sizes := [2][3]f32{{60, 36, 48}, {96, 54, 72}}
    for archetype in archetypes {
        profile := architecture.facade_profile(archetype)
        for size in sizes {
            for seed in 0 ..< 128 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                if footprint.count <= 1 do continue
                primary := architecture.architecture_frontage_mass_index(structure)
                for mass, mass_index in footprint.masses[:footprint.count] {
                    layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                    wall_height := structure.height * mass.height_scale
                    for face in faces {
                        if (face == .Left || face == .Right) && profile.blank_sides do continue
                        span := architecture.face_span(mass, face)
                        if span < 28 do continue
                        exposed_area := architecture.architecture_exposed_face_area(
                            footprint,
                            mass_index,
                            face,
                            structure.height,
                        )
                        full_area := span * wall_height
                        if exposed_area < full_area * .75 do continue
                        glazing_area := f32(0)
                        for opening in layout.openings[:layout.count] {
                            if opening.face == face &&
                               (opening.kind == .Window || opening.kind == .Loggia) {
                                glazing_area += opening.width * opening.height
                            }
                        }
                        actual_ratio := glazing_area / exposed_area
                        if actual_ratio < profile.opening_ratio_min - .001 {
                            testing.expectf(
                                t,
                                false,
                                "broad exposed compound face misses glazing floor archetype=%v size=(%.1f,%.1f,%.1f) seed=%d mass=%d face=%v ratio=%.3f target=%.3f exposed=%.2f/%.2f",
                                archetype,
                                size[0],
                                size[1],
                                size[2],
                                seed,
                                mass_index,
                                face,
                                actual_ratio,
                                profile.opening_ratio_min,
                                exposed_area,
                                full_area,
                            )
                            return
                        }
                    }
                }
            }
        }
    }
}

@(test)
architecture_broad_service_faces_respect_actual_ventilation_ceiling :: proc(t: ^testing.T) {
    archetypes := [5]buildings.Archetype {
        .Workshop,
        .Storehouse,
        .Fishery,
        .Barn_Granary,
        .Mill,
    }
    faces := [4]architecture.Face{.Front, .Rear, .Left, .Right}
    sizes := [3][3]f32{{30, 24, 24}, {60, 36, 48}, {96, 54, 72}}
    for archetype in archetypes {
        profile := architecture.facade_profile(archetype)
        testing.expect(t, profile.service)
        for size in sizes {
            for seed in 0 ..< 128 {
                structure := terrain.structure_make(1300, 1300, size[0], size[1], 4, size[2])
                structure.width, structure.depth, structure.height = size[0], size[1], size[2]
                structure.kind = .Architecture
                structure.seed = u32(seed)
                structure.building.archetype = archetype
                footprint := architecture.architecture_footprint(structure)
                primary := architecture.architecture_frontage_mass_index(structure)
                for _, mass_index in footprint.masses[:footprint.count] {
                    layout := architecture.architecture_opening_layout(structure, mass_index, primary)
                    for face in faces {
                        ventilation_area := f32(0)
                        for opening in layout.openings[:layout.count] {
                            if opening.face == face &&
                               (opening.kind == .Vent || opening.kind == .Window) {
                                ventilation_area += opening.width * opening.height
                            }
                        }
                        if ventilation_area <= .001 do continue
                        wall_area := architecture.architecture_exposed_face_area(
                            footprint,
                            mass_index,
                            face,
                            structure.height,
                        )
                        if wall_area <= .001 do continue
                        actual_ratio := ventilation_area / wall_area
                        testing.expectf(
                            t,
                            actual_ratio <= profile.opening_ratio_max + .001,
                            "broad service face exceeds ventilation ceiling archetype=%v size=(%.1f,%.1f,%.1f) seed=%d mass=%d face=%v ratio=%.3f target=%.3f",
                            archetype,
                            size[0],
                            size[1],
                            size[2],
                            seed,
                            mass_index,
                            face,
                            actual_ratio,
                            profile.opening_ratio_max,
                        )
                    }
                }
            }
        }
    }
}

@(test)
architecture_sparse_bays_use_the_breadth_of_their_facade :: proc(t: ^testing.T) {
    span: f32 = 30
    window_width: f32 = 1.35
    for columns in 2 ..= 4 {
        left := architecture.facade_bay_center(span, window_width, columns, 0)
        right := architecture.facade_bay_center(span, window_width, columns, columns - 1)
        testing.expect(t, left <= -span * .25)
        testing.expect(t, right >= span * .25)
        testing.expect(
            t,
            math.abs(left) + window_width * .5 <= span * .5 - architecture.ARCHITECTURE_OPENING_CORNER_MARGIN + .001,
        )
        testing.expect(
            t,
            math.abs(right) + window_width * .5 <= span * .5 - architecture.ARCHITECTURE_OPENING_CORNER_MARGIN + .001,
        )
    }
}

@(test)
architecture_openings_stack_and_restore_central_upper_bay :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 24, 18, 4, 19.2)
    structure.kind = .Architecture
    structure.seed = 512
    structure.building.archetype = .Townhouse
    layout := architecture.architecture_opening_layout(structure, 0, 0)
    rows := architecture.facade_floor_count(structure.height)
    for opening in layout.openings[:layout.count] {
        if opening.face != .Front || opening.kind != .Window do continue
        if opening.row == 0 {
            testing.expect(t, opening.width >= 1.15 * .90 && opening.width <= 1.50 * .90)
        } else {
            testing.expect(t, opening.width >= 1.15 && opening.width <= 1.50)
        }
        testing.expect(t, math.abs(opening.horizontal) + opening.width * .5 <= structure.width * .5 - .75)
        if opening.row > 1 {
            previous, found := architecture.opening_layout_find(
                &layout,
                .Front,
                .Window,
                opening.row - 1,
                opening.column,
            )
            testing.expect(t, found)
            if found do testing.expect(t, previous.horizontal == opening.horizontal)
        }
    }
    central_upper := false
    for opening in layout.openings[:layout.count] {
        if opening.face == .Front &&
           opening.kind == .Window &&
           opening.row == rows - 1 &&
           math.abs(opening.horizontal) < .001 {
            central_upper = true
            ground_centre_occupied := false
            for ground in layout.openings[:layout.count] {
                if ground.face == .Front &&
                   ground.kind == .Window &&
                   ground.row == 0 &&
                   math.abs(ground.horizontal) < .001 {
                    ground_centre_occupied = true
                    break
                }
            }
            // Window columns are spatially reindexed after entrance panes
            // are culled, so compare the actual bay position rather than an
            // index whose meaning legitimately differs between rows.
            testing.expect(t, !ground_centre_occupied)
        }
    }
    testing.expect(t, central_upper)
}

@(test)
architecture_rural_and_service_profiles_allow_blank_sides :: proc(t: ^testing.T) {
    farmstead := terrain.structure_make(1300, 1300, 16, 12, 4, 14.4)
    farmstead.kind = .Architecture
    farmstead.seed = 0
    farmstead.building.archetype = .Farmstead
    layout := architecture.architecture_opening_layout(farmstead, 0, 0)
    side_windows := 0
    for opening in layout.openings[:layout.count] {
        if (opening.face == .Left || opening.face == .Right) && opening.kind == .Window do side_windows += 1
    }
    testing.expect(t, side_windows == 0)

    broad_farmstead := farmstead
    broad_farmstead.width, broad_farmstead.depth = 60, 60
    broad_layout := architecture.architecture_opening_layout(broad_farmstead, 0, 0)
    broad_side_windows := 0
    for opening in broad_layout.openings[:broad_layout.count] {
        if (opening.face == .Left || opening.face == .Right) && opening.kind == .Window {
            broad_side_windows += 1
        }
    }
    testing.expect(t, broad_side_windows == 0)

    deep_farmstead := farmstead
    deep_farmstead.width, deep_farmstead.depth = 12, 24
    deep_layout := architecture.architecture_opening_layout(deep_farmstead, 0, 0)
    long_axis_windows := 0
    for opening in deep_layout.openings[:deep_layout.count] {
        if (opening.face == .Left || opening.face == .Right) && opening.kind == .Window {
            long_axis_windows += 1
        }
    }
    testing.expect(t, long_axis_windows > 0)

    storehouse := farmstead
    storehouse.building.archetype = .Storehouse
    service_layout := architecture.architecture_opening_layout(storehouse, 0, 0)
    for opening in service_layout.openings[:service_layout.count] {
        if opening.kind == .Vent {
            testing.expect(t, opening.width <= 1.35)
            testing.expect(t, opening.height <= 1.20)
        }
    }
}

@(test)
architecture_service_faces_receive_sparse_vents :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 22, 18, 4, 10)
    structure.kind = .Architecture
    structure.seed = 512
    structure.building.archetype = .Storehouse
    primary := architecture.architecture_frontage_mass_index(structure)
    layout := architecture.architecture_opening_layout(structure, 0, primary)
    face_vents: [4]int
    vents := 0
    for opening in layout.openings[:layout.count] {
        if opening.kind == .Vent {
            face_vents[int(opening.face)] += 1
            vents += 1
        }
    }
    testing.expect(t, vents > 0)
    testing.expect(t, face_vents[int(architecture.Face.Front)] <= 2)
    testing.expect(t, face_vents[int(architecture.Face.Left)] <= 1)
    testing.expect(t, face_vents[int(architecture.Face.Right)] <= 1)
}

@(test)
terrain_v3_migration_preserves_structure_identity_and_marks_architecture_legacy :: proc(t: ^testing.T) {
    legacy := new(terrain.Project_V3)
    defer free(legacy)
    legacy.structure_count = 2
    legacy.next_structure_id = 9
    legacy.structures[0] = {
        id       = 7,
        group_id = 7,
        width    = 20,
        depth    = 16,
        height   = 12,
        kind     = .Architecture,
        seed     = 1234,
    }
    legacy.structures[1] = {
        id       = 8,
        group_id = 8,
        width    = 4,
        depth    = 4,
        height   = 4,
        kind     = .Rock,
        seed     = 5678,
    }
    migrated := new(terrain.Project)
    defer terrain.free_project(migrated)
    testing.expect(t, terrain.project_migrate_v3(migrated, legacy))
    testing.expect(t, migrated.structure_count == 2)
    testing.expect(t, migrated.next_structure_id == 9)
    testing.expect(t, migrated.structures[0].id == 7)
    testing.expect(t, migrated.structures[0].seed == 1234)
    testing.expect_value(t, migrated.structures[0].building.archetype, buildings.Archetype.Legacy)
    testing.expect(t, migrated.structures[1].building == buildings.Identity{})
}

@(test)
city_density_bounds_tracks_only_authored_density :: proc(t: ^testing.T) {
    field: [terrain.CITY_DENSITY_SAMPLES]u8
    testing.expect(t, !architecture.city_density_bounds(&field).valid)
    _ = architecture.city_density_stamp(&field, 1300, 1300, 40, 1, 1)
    bounds := architecture.city_density_bounds(&field)
    testing.expect(t, bounds.valid)
    testing.expect(t, architecture.city_bounds_contains(bounds, 1300, 1300))
}
