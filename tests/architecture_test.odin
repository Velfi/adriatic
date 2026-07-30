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

    structure.building.archetype = .Townhouse
    structure.seed = 1
    rear_return := architecture.architecture_footprint(structure)
    structure.seed = 2
    stepped := architecture.architecture_footprint(structure)
    testing.expect_value(t, rear_return.count, 2)
    testing.expect_value(t, stepped.count, 2)
    testing.expect(t, rear_return != stepped)

    structure.building.archetype = .Workshop
    structure.seed = 4
    work_court := architecture.architecture_footprint(structure)
    structure.seed = 1
    service_wing := architecture.architecture_footprint(structure)
    testing.expect_value(t, work_court.count, 3)
    testing.expect_value(t, service_wing.count, 2)

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
        testing.expect(t, math.abs(wing_front_edge - street_bar_rear_edge) < .001)
    }
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
mixed_use_dwelling_side_windows_clear_apartment_doors :: proc(t: ^testing.T) {
    for seed in 0 ..< 64 {
        structure := terrain.structure_make(1300, 1300, 30, 24, 4, 18)
        structure.kind = .Architecture
        structure.seed = u32(seed)
        structure.building.archetype = .Mixed_Use_Dwelling
        structure.building.purpose = .Inn_Shop

        primary := architecture.architecture_frontage_mass_index(structure)
        footprint := architecture.architecture_footprint(structure)
        layout := architecture.architecture_opening_layout(structure, primary, primary)
        mass := footprint.masses[primary]
        for opening in layout.openings[:layout.count] {
            if opening.kind != .Window || opening.row != 0 || (opening.face != .Left && opening.face != .Right) {
                continue
            }
            door_horizontal := opening.face == .Left ? mass.depth * .20 : -mass.depth * .20
            clearance := math.abs(opening.horizontal - door_horizontal) - opening.width * .5 - f32(1.65) * .5
            testing.expect(t, clearance >= architecture.ARCHITECTURE_DOOR_WINDOW_MARGIN - .001)
        }
    }
}

@(test)
architecture_openings_cover_every_mass_face_without_cross_mass_culling :: proc(t: ^testing.T) {
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
        testing.expect(t, layout.count > 0)
        testing.expect(t, doors == (mass_index == primary ? 1 : 0))
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
architecture_compact_masses_do_not_generate_floating_openings :: proc(t: ^testing.T) {
    structure := terrain.structure_make(0, 0, 8.2, 6.4, 0, 4.8)
    structure.kind = .Architecture
    structure.height = 4.8
    structure.building.archetype = .Harbor_Office
    layout := architecture.architecture_opening_layout(structure, 0, 0)
    testing.expect_value(t, layout.count, 0)
}

@(test)
architecture_facade_profiles_match_archetype_targets :: proc(t: ^testing.T) {
    dwelling := architecture.facade_profile(.Dwelling)
    testing.expect(t, dwelling.front_bays_min == 1 && dwelling.front_bays_max == 2)
    testing.expect(t, dwelling.side_bays_min == 0 && dwelling.side_bays_max == 1)
    testing.expect(t, dwelling.window_width_min >= 1.05 && dwelling.window_width_max <= 1.35)
    testing.expect(t, dwelling.opening_ratio_min == .08 && dwelling.opening_ratio_max == .14)

    townhouse := architecture.facade_profile(.Townhouse)
    testing.expect(t, townhouse.front_bays_min == 2 && townhouse.front_bays_max == 3)
    testing.expect(t, townhouse.opening_ratio_min == .12 && townhouse.opening_ratio_max == .20)

    service := architecture.facade_profile(.Storehouse)
    testing.expect(t, service.service)
    testing.expect(t, service.front_bays_max == 2 && service.side_bays_max == 1)
    testing.expect(t, service.opening_ratio_max <= .08)

    civic := architecture.facade_profile(.Palace_Loggia)
    testing.expect(t, civic.front_bays_min == 3 && civic.front_bays_max == 5)
    testing.expect(t, civic.window_width_max <= 1.70)
    testing.expect(t, civic.opening_ratio_min == .15 && civic.opening_ratio_max == .22)
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
            testing.expect(t, !architecture.opening_layout_contains(&layout, .Front, .Window, 0, opening.column))
        }
    }
    testing.expect(t, central_upper)
}

@(test)
architecture_rural_and_service_profiles_allow_blank_sides :: proc(t: ^testing.T) {
    dwelling := terrain.structure_make(1300, 1300, 16, 12, 4, 14.4)
    dwelling.kind = .Architecture
    dwelling.seed = 0
    dwelling.building.archetype = .Dwelling
    layout := architecture.architecture_opening_layout(dwelling, 0, 0)
    side_windows := 0
    for opening in layout.openings[:layout.count] {
        if (opening.face == .Left || opening.face == .Right) && opening.kind == .Window do side_windows += 1
    }
    testing.expect(t, side_windows == 0)

    storehouse := dwelling
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
