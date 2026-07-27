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
    defer free(project)
    architecture.generate(project, 1300, 1300, 0xA71D3)
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
architecture_generation_rejects_sea_level_sites :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer free(project)
    created := architecture.generate(project, 0, 0, 0xA71D3)
    testing.expect(t, created == 0)
    testing.expect(t, project.structure_count == 0)
}

@(test)
architecture_regeneration_preserves_seeded_styles :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer free(project)
    architecture.generate(project, 1300, 1300, 0xA71D3)
    first_seed := project.structures[0].seed
    first_color := project.structures[0].color
    architecture.generate(project, 1300, 1300, 0xA71D3)
    testing.expect(t, project.structures[0].seed == first_seed)
    testing.expect(t, project.structures[0].color == first_color)
}

@(test)
architecture_append_generation_keeps_both_island_towns :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer free(project)
    first_created := architecture.generate_append(project, -1300, -1418, 0xA71D3)
    second_created := architecture.generate_append(project, 1300, 1418, 0xD911C)
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
architecture_append_density_removes_buildings_without_scaling_survivors :: proc(t: ^testing.T) {
    full := terrain.new_project()
    sparse := terrain.new_project()
    defer free(full)
    defer free(sparse)
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
    defer free(project)
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
    testing.expect(t, architecture.facade_window_row_y(50, 0) == 2.95)
    testing.expect(t, architecture.facade_window_row_y(50, 9) == 47.05)
    low_rise_window_height := architecture.facade_window_height(11)
    low_rise_window_y := architecture.facade_window_row_y(11, 0)
    testing.expect(t, low_rise_window_height == 2.2)
    testing.expect(t, math.abs(low_rise_window_y - low_rise_window_height * .5 - 1.45) < .001)
    testing.expect(t, architecture.facade_floor_count(4.8) == 1)
    testing.expect(t, architecture.facade_floor_count(9.6) == 2)
    testing.expect(t, architecture.facade_floor_count(14.4) == 3)
    testing.expect(t, architecture.facade_fitted_height(9) == 9.6)
    testing.expect(t, architecture.facade_fitted_height(18) == 19.2)
    testing.expect(t, architecture.facade_floor_count(architecture.facade_fitted_height(33)) == architecture.facade_floor_count(33))
    testing.expect(t, architecture.facade_fitted_height(architecture.facade_fitted_height(33)) == architecture.facade_fitted_height(33))
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
    defer free(project)
    low, high: [terrain.CITY_DENSITY_SAMPLES]u8
    bounds := architecture.City_Bounds{1120, 1120, 1480, 1480, true}
    _ = architecture.city_density_stamp(&low, 1300, 1300, 175, .34, .8)
    _ = architecture.city_density_stamp(&high, 1300, 1300, 175, 1, .8)
    low_plan := architecture.city_plan_density(project, &low, bounds)
    high_plan := architecture.city_plan_density(project, &high, bounds)
    repeat := architecture.city_plan_density(project, &high, bounds)
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
    defer free(project)
    water := terrain.structure_make(0, 0, 20, 20, 0, 12)
    testing.expect(t, !architecture.city_structure_site_valid(project, &water))
    land := terrain.structure_make(1300, 1300, 20, 20, 0, 12)
    testing.expect(t, architecture.city_structure_site_valid(project, &land))
    testing.expect(t, land.base_y > project.sea_level)
}

@(test)
architecture_foundation_spans_uneven_rotated_footprint :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer free(project)
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
    defer free(project)
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
    defer free(project)
    field: [terrain.CITY_DENSITY_SAMPLES]u8
    bounds := architecture.City_Bounds{1160, 1160, 1440, 1440, true}
    _ = architecture.city_density_stamp(&field, 1300, 1300, 130, .8, .7)
    plan := architecture.city_plan_density(project, &field, bounds)
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
    plan.structures[0] = west
    plan.count = 1

    architecture.city_plan_set_region(&plan, .Aegean)

    testing.expect(t, plan.structures[0].building.region == buildings.Region.Aegean)
}

@(test)
city_planner_builds_accessible_frontage_parcels_and_deep_alleys :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer free(project)
    field: [terrain.CITY_DENSITY_SAMPLES]u8
    bounds := architecture.City_Bounds{1120, 1120, 1480, 1480, true}
    _ = architecture.city_density_stamp(&field, 1300, 1300, 185, 1, 1)
    plan := architecture.city_plan_density(project, &field, bounds)
    testing.expect(t, plan.count > 0)
    testing.expect(t, plan.parcel_count == plan.count)
    testing.expect(t, plan.alley_count > 0)
    for parcel in plan.parcels[:plan.parcel_count] {
        testing.expect(t, parcel.frontage_width >= 8 && parcel.frontage_width <= 32)
        testing.expect(t, parcel.depth >= 13 && parcel.depth <= 36)
    }
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
        42,
    )
    testing.expect_value(t, shop.archetype, buildings.Archetype.Shop_House)

    townhouse := architecture.architecture_identity(
        {purpose = .Dwelling, density = .72, attached = true, purpose_explicit = true},
        42,
    )
    testing.expect_value(t, townhouse.archetype, buildings.Archetype.Townhouse)

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
        for count in face_counts do testing.expect(t, count > 0)
        testing.expect(t, doors == (mass_index == primary ? 1 : 0))
    }
}

@(test)
architecture_service_faces_receive_sparse_vents :: proc(t: ^testing.T) {
    structure := terrain.structure_make(1300, 1300, 22, 18, 4, 10)
    structure.kind = .Architecture
    structure.seed = 7
    structure.building.archetype = .Storehouse
    primary := architecture.architecture_frontage_mass_index(structure)
    layout := architecture.architecture_opening_layout(structure, 0, primary)
    face_vents: [4]int
    for opening in layout.openings[:layout.count] {
        if opening.kind == .Vent do face_vents[int(opening.face)] += 1
    }
    for count in face_vents do testing.expect(t, count > 0)
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
    defer free(migrated)
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
