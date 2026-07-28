package main

import architecture "../packages/architecture"
import roads "../packages/roads"
import terrain "../packages/terrain"
import "core:fmt"
import "core:math"
import "core:testing"

@(test)
settlement_rng_is_deterministic :: proc(t: ^testing.T) {
    a, b := settlement_rng_new(0x51a7), settlement_rng_new(0x51a7)
    for _ in 0 ..< 256 do testing.expect_value(t, settlement_rng_u32(&a), settlement_rng_u32(&b))
}

@(test)
settlement_aegean_architecture_uses_flat_ordinary_roofs :: proc(t: ^testing.T) {
    for seed in 0 ..< 16 {
        aegean := terrain.structure_make(0, 0, 8, 10, 0, 6)
        aegean.kind = .Architecture
        aegean.seed = u32(seed)
        aegean.building = architecture.architecture_identity(
            {region = .Aegean, purpose = .Dwelling, purpose_explicit = true},
            aegean.seed,
        )
        testing.expect_value(t, world_architecture_roof_style(aegean), architecture.Roof_Style.Parapet)

        adriatic := aegean
        adriatic.building = architecture.architecture_identity(
            {region = .Adriatic, purpose = .Dwelling, purpose_explicit = true},
            adriatic.seed,
        )
        testing.expect_value(
            t,
            world_architecture_roof_style(adriatic),
            architecture.roof_style_for_seed(adriatic.seed),
        )
    }
}

@(test)
settlement_village_program_is_complete_and_reason_specific :: proc(t: ^testing.T) {
    for reason in Village_Reason {
        for seed in 0 ..< 64 {
            program: [24]Settlement_Building_Purpose
            count := settlement_village_program(reason, u32(seed), &program)
            testing.expect(t, count >= 12 && count <= 18)
            purpose_counts: [8]int
            for purpose in program[:count] do purpose_counts[int(purpose)] += 1
            testing.expect(t, purpose_counts[int(Settlement_Building_Purpose.Dwelling)] >= 7)
            testing.expect(t, purpose_counts[int(Settlement_Building_Purpose.Workshop)] == 1)
            testing.expect(t, purpose_counts[int(Settlement_Building_Purpose.Inn_Shop)] == 1)
            switch reason {
            case .Harbor_Fishery:
                testing.expect(t, purpose_counts[int(Settlement_Building_Purpose.Farmstead)] == 0)
                testing.expect(t, purpose_counts[int(Settlement_Building_Purpose.Barn_Granary)] == 0)
                testing.expect(t, purpose_counts[int(Settlement_Building_Purpose.Fishery)] == 2)
                testing.expect(t, purpose_counts[int(Settlement_Building_Purpose.Storehouse)] == 2)
            case .Agricultural_Terrace:
                testing.expect(t, purpose_counts[int(Settlement_Building_Purpose.Farmstead)] == 2)
                testing.expect(t, purpose_counts[int(Settlement_Building_Purpose.Barn_Granary)] == 3)
                testing.expect(t, purpose_counts[int(Settlement_Building_Purpose.Mill)] == 1)
            case .Upland_Pastoral:
                testing.expect(t, purpose_counts[int(Settlement_Building_Purpose.Farmstead)] == 1)
                testing.expect(t, purpose_counts[int(Settlement_Building_Purpose.Barn_Granary)] == 2)
                testing.expect(t, purpose_counts[int(Settlement_Building_Purpose.Storehouse)] == 1)
            case .Route_Stop:
                testing.expect(t, purpose_counts[int(Settlement_Building_Purpose.Farmstead)] == 1)
                testing.expect(t, purpose_counts[int(Settlement_Building_Purpose.Barn_Granary)] == 1)
                testing.expect(t, purpose_counts[int(Settlement_Building_Purpose.Storehouse)] == 1)
            }
        }
    }
}

@(test)
settlement_village_reason_responds_to_terrain_and_tissue :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    plan := Settlement_Plan {
        request = {region = .Adriatic, scale = .Village, seed = 7, center = {center, center}, radius = 100},
        neighborhood_count = 1,
    }
    plan.neighborhoods[0] = {
        center      = {center, center},
        density     = .4,
        suitability = 1,
        tissue      = .Harbor,
    }
    project.sea_level = terrain.sample_height(project, 0, center, center) - 2
    testing.expect_value(t, settlement_village_reason_pick(&plan, project), Village_Reason.Harbor_Fishery)
    project.sea_level = -100
    plan.neighborhoods[0].tissue = .Contour_Terrace
    testing.expect(
        t,
        settlement_village_reason_pick(&plan, project) == .Agricultural_Terrace ||
        settlement_village_reason_pick(&plan, project) == .Upland_Pastoral,
    )
}

@(test)
settlement_route_width_ranges_hold_across_seed_suite :: proc(t: ^testing.T) {
    for seed in 0 ..< 64 {
        rng := settlement_rng_new(u32(seed))
        for _ in 0 ..< 64 {
            civic := settlement_route_width_sample(&rng, .Civic_Spine)
            connector := settlement_route_width_sample(&rng, .Connector)
            street := settlement_route_width_sample(&rng, .Street)
            lane := settlement_route_width_sample(&rng, .Lane)
            alley := settlement_route_width_sample(&rng, .Alley)
            testing.expect(t, civic >= 5 && civic <= 11)
            testing.expect(t, connector >= 4 && connector <= 8)
            testing.expect(t, street >= 2.5 && street <= 6)
            testing.expect(t, lane >= 1.3 && lane <= 3.8)
            testing.expect(t, alley >= .8 && alley <= 2.5)
        }
    }
}

@(test)
settlement_block_presets_hold_across_seed_suite :: proc(t: ^testing.T) {
    tissues := [?]Settlement_Tissue{.Dalmatian_Planned, .Venetian_Mercantile, .Later_Extension, .Cycladic_Accretion}
    minimum_short := [?]f32{18, 28, 45, 12}
    maximum_short := [?]f32{36, 55, 85, 50}
    minimum_long := [?]f32{35, 50, 65, 20}
    maximum_long := [?]f32{70, 100, 125, 85}
    for seed in 0 ..< 64 {
        rng := settlement_rng_new(u32(seed) ~ 0xb10c)
        for tissue, index in tissues {
            for _ in 0 ..< 16 {
                short_side, long_side := settlement_block_dimensions(&rng, tissue)
                testing.expect(t, short_side >= minimum_short[index] && short_side <= maximum_short[index])
                testing.expect(t, long_side >= minimum_long[index] && long_side <= maximum_long[index])
            }
        }
    }
}

@(test)
settlement_generated_parcels_and_heights_hold_across_seed_suite :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    project.road_graph = {}
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    for region in Settlement_Region {
        for scale in Settlement_Scale {
            frontage_sum, depth_sum, height_sum: f32
            sample_count := 0
            for seed in 0 ..< 64 {
                plan: Settlement_Plan
                plan.request = {
                    region = region,
                    scale  = scale,
                    seed   = u32(seed),
                    center = {center, center},
                    radius = 100,
                }
                plan.routes[0].geometry.points[0] = {center - 90, center}
                plan.routes[0].geometry.points[1] = {center + 90, center}
                plan.routes[0].geometry.count = 2
                plan.routes[0].class = .Street
                plan.routes[0].width = 3.5
                plan.routes[0].shoulder = .8
                plan.routes[0].drivable = true
                plan.route_count = 1
                target_density := f32(.45)
                if region == .Adriatic {
                    switch scale {
                    case .City:
                        target_density = .37
                    case .Town:
                        target_density = .50
                    case .Village:
                        target_density = .41
                    }
                }
                for index in 0 ..< 16 {
                    column, row := index % 4, index / 4
                    plan.macro_cells[index] = {
                        center      = {center + (f32(column) - 1.5) * 18, center + (f32(row) - 1.5) * 18},
                        radius      = 12,
                        density     = target_density,
                        age         = f32(index % 4) * .12,
                        suitability = 1,
                        tissue      = region == .Aegean ? .Cycladic_Accretion : .Dalmatian_Planned,
                    }
                }
                plan.macro_cell_count = 16
                if scale == .Village {
                    village_tissue := Settlement_Tissue.Dalmatian_Planned
                    if region == .Aegean do village_tissue = .Cycladic_Accretion
                    for neighborhood_index in 0 ..< 3 {
                        plan.neighborhoods[neighborhood_index] = {
                            center      = {center + f32(neighborhood_index - 1) * 58, center + 10},
                            radius      = 22,
                            density     = target_density,
                            age         = f32(neighborhood_index) * .24,
                            suitability = 1,
                            tissue      = village_tissue,
                        }
                    }
                    plan.neighborhood_count = 3
                }
                rng := settlement_rng_new(u32(seed) ~ u32(region) * 0x9e37 ~ u32(scale) * 0x85eb)
                city := settlement_plan_generate_buildings(&plan, project, &rng)
                if city.count < 8 {
                    fmt.println("settlement seed-suite underflow", region, scale, seed, city.count)
                }
                testing.expect(t, city.count >= 8)
                if scale == .Village {
                    expected_program: [24]Settlement_Building_Purpose
                    expected_count := settlement_village_program(plan.village_reason, u32(seed), &expected_program)
                    if city.count != expected_count {
                        fmt.println(
                            "settlement village program mismatch",
                            region,
                            seed,
                            city.count,
                            expected_count,
                            expected_program[:expected_count],
                            plan.ordinary_purposes[:plan.ordinary_purpose_count],
                        )
                    }
                    testing.expect_value(t, city.count, expected_count)
                    testing.expect_value(t, plan.ordinary_purpose_count, expected_count)
                    maximum_alley_count := region == .Aegean ? 3 : 2
                    testing.expect(t, city.alley_count <= maximum_alley_count)
                    for alley in city.alleys[:city.alley_count] {
                        dx, dz := alley.end_x - alley.start_x, alley.end_z - alley.start_z
                        testing.expect(t, dx * dx + dz * dz <= 55 * 55)
                    }
                    centroid_x, centroid_z := f32(0), f32(0)
                    for structure in city.structures[:city.count] {
                        centroid_x += structure.center_x
                        centroid_z += structure.center_z
                    }
                    centroid_x /= f32(city.count)
                    centroid_z /= f32(city.count)
                    occupied: [4]bool
                    for structure in city.structures[:city.count] {
                        quadrant :=
                            (structure.center_x >= centroid_x ? 1 : 0) + (structure.center_z >= centroid_z ? 2 : 0)
                        occupied[quadrant] = true
                    }
                    quadrant_count := 0
                    for present in occupied {
                        if present do quadrant_count += 1
                    }
                    testing.expect(t, quadrant_count >= 3)
                    frontage_distance_sum := f32(0)
                    frontage_count := 0
                    for structure, structure_index in city.structures[:city.count] {
                        purpose := plan.ordinary_purposes[structure_index]
                        if purpose == .Barn_Granary ||
                           purpose == .Storehouse ||
                           purpose == .Mill ||
                           purpose == .Fishery {
                            continue
                        }
                        _, route_tangent, _, _, _, route_distance, _, route_found := settlement_nearest_route_frame(
                            &plan,
                            {structure.center_x, structure.center_z},
                        )
                        testing.expect(t, route_found)
                        structure_tangent := [2]f32 {
                            f32(math.cos(f64(structure.rotation))),
                            f32(math.sin(f64(structure.rotation))),
                        }
                        alignment := math.abs(
                            structure_tangent[0] * route_tangent[0] + structure_tangent[1] * route_tangent[1],
                        )
                        testing.expect(t, alignment > .98)
                        frontage_distance_sum += route_distance
                        frontage_count += 1
                    }
                    testing.expect(t, frontage_count > 0)
                    average_frontage_distance := frontage_distance_sum / f32(frontage_count)
                    if average_frontage_distance >= 16 {
                        fmt.println("settlement village frontage mismatch", region, seed, average_frontage_distance)
                        for structure, structure_index in city.structures[:city.count] {
                            purpose := plan.ordinary_purposes[structure_index]
                            _, _, _, _, _, route_distance, _, _ := settlement_nearest_route_frame(
                                &plan,
                                {structure.center_x, structure.center_z},
                            )
                            fmt.println("settlement village frontage site", purpose, route_distance)
                        }
                    }
                    testing.expect(t, average_frontage_distance < 16)
                    village_anchor := plan.neighborhoods[0].center
                    for structure in city.structures[:city.count] {
                        dx := structure.center_x - village_anchor[0]
                        dz := structure.center_z - village_anchor[1]
                        distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
                        maximum_radius := region == .Aegean ? f32(51) : f32(59)
                        testing.expect(t, distance < maximum_radius)
                    }
                    resource_centers: [24][2]f32
                    resource_count := 0
                    for structure, structure_index in city.structures[:city.count] {
                        purpose := plan.ordinary_purposes[structure_index]
                        if purpose != .Barn_Granary &&
                           purpose != .Storehouse &&
                           purpose != .Mill &&
                           purpose != .Fishery {
                            continue
                        }
                        resource_centers[resource_count] = {structure.center_x, structure.center_z}
                        resource_count += 1
                    }
                    testing.expect(t, resource_count >= 2)
                    for first in 0 ..< resource_count {
                        for second in first + 1 ..< resource_count {
                            dx := resource_centers[second][0] - resource_centers[first][0]
                            dz := resource_centers[second][1] - resource_centers[first][1]
                            distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
                            testing.expect(t, distance < 50)
                        }
                    }
                    core_plaza_found := false
                    for edit in plan.terrain_edits[:plan.terrain_edit_count] {
                        if edit.kind != .Plaza do continue
                        dx := edit.center[0] - village_anchor[0]
                        dz := edit.center[1] - village_anchor[1]
                        if dx * dx + dz * dz > .01 do continue
                        core_plaza_found = true
                        expected_half_x := region == .Aegean ? f32(6) : f32(8)
                        expected_half_z := region == .Aegean ? f32(5) : f32(6)
                        testing.expect_value(t, edit.half_extent[0], expected_half_x)
                        testing.expect_value(t, edit.half_extent[1], expected_half_z)
                    }
                    testing.expect(t, core_plaza_found)
                }
                for index in 0 ..< city.parcel_count {
                    parcel, structure := city.parcels[index], city.structures[index]
                    frontage_low, frontage_high := f32(4.5), f32(16)
                    depth_low, depth_high := f32(9), f32(28)
                    if region == .Aegean {
                        frontage_low, frontage_high = 4, 11
                        depth_low, depth_high = 5.5, 16
                    } else if scale == .Village {
                        frontage_low, frontage_high = 4.5, 13
                        depth_low, depth_high = 6, 18
                    }
                    minimum_height, maximum_height := settlement_height_band(region, scale)
                    testing.expect(t, parcel.frontage_width >= frontage_low && parcel.frontage_width <= frontage_high)
                    testing.expect(t, parcel.depth >= depth_low && parcel.depth <= depth_high)
                    testing.expect(t, structure.height >= minimum_height && structure.height <= maximum_height)
                    testing.expect(t, math.abs(structure.width - parcel.frontage_width) < .001)
                    testing.expect(t, math.abs(structure.depth - parcel.depth) < .001)
                    frontage_sum += parcel.frontage_width
                    depth_sum += parcel.depth
                    height_sum += structure.height
                    sample_count += 1
                }
                architecture.city_plan_destroy(&city)
            }
            testing.expect(t, sample_count > 512)
            frontage_target, depth_target := f32(8.5), f32(16)
            if region == .Aegean {
                frontage_target, depth_target = 6.5, 9
            } else if scale == .Village {
                frontage_target, depth_target = 7.5, 10.5
            }
            height_target := f32(6.5)
            if region == .Adriatic {
                switch scale {
                case .City:
                    height_target = 13
                case .Town:
                    height_target = 10
                case .Village:
                    height_target = 7
                }
            }
            inverse := 1 / f32(sample_count)
            if math.abs(depth_sum * inverse - depth_target) > depth_target * .10 {
                fmt.println(
                    "settlement seed-suite depth mean",
                    region,
                    scale,
                    depth_sum * inverse,
                    "target",
                    depth_target,
                )
            }
            testing.expect(t, math.abs(frontage_sum * inverse - frontage_target) <= frontage_target * .10)
            testing.expect(t, math.abs(depth_sum * inverse - depth_target) <= depth_target * .10)
            testing.expect(t, math.abs(height_sum * inverse - height_target) <= height_target * .10)
        }
    }
}

@(test)
settlement_village_occupies_multiple_route_arms :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    project.road_graph = {}
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    for region in Settlement_Region {
        for seed in 0 ..< 16 {
            plan: Settlement_Plan
            plan.request = {
                region = region,
                scale  = .Village,
                seed   = u32(seed),
                center = {center, center},
                radius = 100,
            }
            plan.neighborhoods[0] = {
                center      = {center, center},
                radius      = 24,
                density     = .42,
                suitability = 1,
                tissue      = region == .Aegean ? .Cycladic_Accretion : .Dalmatian_Planned,
            }
            plan.neighborhood_count = 1
            for route_index in 0 ..< 3 {
                angle := f64(route_index) * math.TAU / 3
                plan.routes[route_index].geometry.points[0] = {center, center}
                plan.routes[route_index].geometry.points[1] = {
                    center + f32(math.cos(angle)) * 90,
                    center + f32(math.sin(angle)) * 90,
                }
                plan.routes[route_index].geometry.count = 2
                plan.routes[route_index].class = .Street
                plan.routes[route_index].width = 3.5
                plan.routes[route_index].shoulder = .8
                plan.routes[route_index].drivable = true
            }
            plan.route_count = 3
            rng := settlement_rng_new(u32(seed) ~ u32(region) * 0x9e37)
            city := settlement_plan_generate_buildings(&plan, project, &rng)
            occupied: [3]bool
            for structure, structure_index in city.structures[:city.count] {
                purpose := plan.ordinary_purposes[structure_index]
                if purpose == .Barn_Granary || purpose == .Storehouse || purpose == .Mill || purpose == .Fishery {
                    continue
                }
                _, _, _, _, _, _, route_index, found := settlement_nearest_route_frame(
                    &plan,
                    {structure.center_x, structure.center_z},
                )
                if found && route_index >= 0 && route_index < len(occupied) {
                    occupied[route_index] = true
                }
            }
            occupied_count := 0
            for present in occupied {
                if present do occupied_count += 1
            }
            testing.expect(t, occupied_count >= 2)
            architecture.city_plan_destroy(&city)
        }
    }
}

@(test)
settlement_tissue_weights_are_regional :: proc(t: ^testing.T) {
    adriatic: [9]int
    aegean: [9]int
    SAMPLE_COUNT :: 10000
    for sample in 0 ..< SAMPLE_COUNT {
        roll := (f32(sample) + .5) / SAMPLE_COUNT
        adriatic[int(settlement_tissue_pick(.Adriatic, roll))] += 1
        aegean[int(settlement_tissue_pick(.Aegean, roll))] += 1
    }
    testing.expect_value(t, adriatic[int(Settlement_Tissue.Venetian_Mercantile)], 3000)
    testing.expect_value(t, adriatic[int(Settlement_Tissue.Dalmatian_Planned)], 2200)
    testing.expect_value(t, adriatic[int(Settlement_Tissue.Hillside_Accretion)], 1800)
    testing.expect_value(t, aegean[int(Settlement_Tissue.Cycladic_Accretion)], 4000)
    testing.expect_value(t, aegean[int(Settlement_Tissue.Contour_Terrace)], 2200)
    testing.expect_value(t, aegean[int(Settlement_Tissue.Church_Cluster)], 1500)
}

@(test)
settlement_landmark_sequences_are_region_specific :: proc(t: ^testing.T) {
    testing.expect_value(t, settlement_landmark_kind(.Adriatic, 0), Settlement_Landmark_Kind.Campanile)
    testing.expect_value(t, settlement_landmark_kind(.Adriatic, 1), Settlement_Landmark_Kind.Palace_Loggia)
    testing.expect_value(t, settlement_landmark_kind(.Aegean, 0), Settlement_Landmark_Kind.Cycladic_Bell)
    testing.expect_value(t, settlement_landmark_kind(.Aegean, 2), Settlement_Landmark_Kind.Monastery)
}

@(test)
settlement_village_landmark_reinforces_composed_core :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.request.scale = .Village
    plan.neighborhoods[0] = {
        center = {12, 8},
        age    = .8,
    }
    plan.neighborhoods[1] = {
        center = {90, 70},
        age    = .1,
    }
    plan.neighborhood_count = 2
    project := terrain.new_project()
    defer terrain.free_project(project)
    testing.expect_value(t, settlement_landmark_anchor_index(&plan, project, 0), 0)
}

@(test)
settlement_density_and_attachment_grade_outward :: proc(t: ^testing.T) {
    profiles := [?]Settlement_Profile{SETTLEMENT_CITY, SETTLEMENT_TOWN, SETTLEMENT_VILLAGE}
    for profile in profiles {
        previous_density := f32(1e9)
        previous_attachment := f32(1e9)
        for step in 0 ..= 100 {
            age := f32(step) / 100
            density := settlement_density_with_age(profile.density_ceiling, age, profile)
            attachment := settlement_attachment_probability(age)
            testing.expect(t, density <= previous_density)
            testing.expect(t, attachment <= previous_attachment)
            previous_density = density
            previous_attachment = attachment
        }
        testing.expect(t, settlement_attachment_probability(0) >= .65)
        testing.expect(t, settlement_attachment_probability(1) >= .15)
        testing.expect(t, settlement_attachment_probability(1) <= .50)
    }
}

@(test)
settlement_building_spacing_grades_outward_and_by_scale :: proc(t: ^testing.T) {
    city_core := settlement_building_separation(.Adriatic, .City, 0, true)
    city_edge := settlement_building_separation(.Adriatic, .City, 1, true)
    town_core := settlement_building_separation(.Adriatic, .Town, 0, true)
    village_core := settlement_building_separation(.Adriatic, .Village, 0, true)
    detached_core := settlement_building_separation(.Adriatic, .City, 0, false)
    detached_edge := settlement_building_separation(.Adriatic, .City, 1, false)

    testing.expect(t, city_core >= 2.4)
    testing.expect(t, city_edge > city_core)
    testing.expect(t, town_core > city_core)
    testing.expect(t, village_core > town_core)
    testing.expect(t, detached_core > city_core)
    testing.expect(t, detached_edge > detached_core)
    testing.expect(t, settlement_building_separation(.Aegean, .City, 0, true) < city_core)
}

@(test)
settlement_height_bands_match_region_and_scale :: proc(t: ^testing.T) {
    minimum, maximum := settlement_height_band(.Adriatic, .City)
    testing.expect(t, minimum == 7 && maximum == 22)
    minimum, maximum = settlement_height_band(.Adriatic, .Town)
    testing.expect(t, minimum == 5 && maximum == 15)
    minimum, maximum = settlement_height_band(.Adriatic, .Village)
    testing.expect(t, minimum == 4 && maximum == 11)
    for scale in Settlement_Scale {
        minimum, maximum = settlement_height_band(.Aegean, scale)
        testing.expect(t, minimum == 3.5 && maximum == 10)
    }
}

@(test)
settlement_metrics_are_idempotent :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.routes[0].geometry.points[0] = {0, 0}
    plan.routes[0].geometry.points[1] = {10, 0}
    plan.routes[0].geometry.count = 2
    plan.routes[0].class = .Street
    plan.routes[0].width = 3.5
    plan.routes[0].drivable = true
    plan.route_count = 1
    plan.sites[0] = {
        kind     = .Landmark,
        accepted = true,
    }
    plan.site_count = 1
    settlement_plan_measure(&plan)
    testing.expect_value(t, plan.metrics.landmark_count, 1)
    testing.expect_value(t, plan.metrics.route_length_by_class[int(Settlement_Route_Class.Street)].count, 1)
    settlement_plan_measure(&plan)
    testing.expect_value(t, plan.metrics.landmark_count, 1)
    testing.expect_value(t, plan.metrics.route_length_by_class[int(Settlement_Route_Class.Street)].count, 1)
}

@(test)
settlement_building_clearance_rejects_crowding :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(&city.structures, terrain.structure_make(0, 0, 9, 16, 0, 8))
    city.count = 1
    testing.expect(t, !settlement_structure_clear(project, &city, 12, 0, 9, 16, 0, .8))
    testing.expect(t, settlement_structure_clear(project, &city, 28, 0, 9, 16, 0, .8))

    road_project := new(terrain.Project)
    defer terrain.free_project(road_project)
    from := roads.add_node(&road_project.road_graph, {-20, 0, 0}, 2)
    to := roads.add_node(&road_project.road_graph, {20, 0, 0}, 2)
    _ = roads.add_edge(&road_project.road_graph, from, to, {-7, 0, 0}, {7, 0, 0}, 3, .8, .Cobblestone)
    empty_city: architecture.City_Plan
    testing.expect(t, !settlement_structure_clear(road_project, &empty_city, 0, 5, 8, 14, 0, .8))
    testing.expect(t, settlement_structure_clear(road_project, &empty_city, 0, 16, 8, 14, 0, .8))
}

@(test)
settlement_rejected_candidates_are_bounded_and_measured :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    for index in 0 ..< 40 {
        settlement_plan_record_rejected_site(&plan, f32(index), 0, 7, 10, 0)
    }
    testing.expect_value(t, plan.rejected_site_count, len(plan.rejected_sites))
    settlement_plan_measure(&plan)
    testing.expect_value(t, plan.metrics.rejected_count, len(plan.rejected_sites))
    testing.expect_value(t, plan.rejected_sites[0].kind, Settlement_Site_Kind.Rejected)
    testing.expect(t, !plan.rejected_sites[0].accepted)
}

@(test)
settlement_import_classifies_wide_pedestrian_access_as_lane :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    plan: Settlement_Plan
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(&city.alleys, architecture.City_Alley{start_x = 0, start_z = 0, end_x = 12, end_z = 0, half_width = 1})
    city.alley_count = 1
    settlement_plan_import_city(&plan, &city, project)
    testing.expect_value(t, plan.route_count, 1)
    testing.expect_value(t, plan.routes[0].class, Settlement_Route_Class.Lane)
    testing.expect(t, !plan.routes[0].drivable)
}

@(test)
settlement_attached_rows_use_footprints_not_bounding_circles :: proc(t: ^testing.T) {
    // Two deep, narrow row houses can sit side-by-side with a one metre
    // passage. The old circular approximation rejected this valid frontage.
    testing.expect(t, settlement_oriented_rectangles_clear(0, 0, 8, 18, 0, 9, 0, 8, 18, 0, .8))
    testing.expect(t, !settlement_oriented_rectangles_clear(0, 0, 8, 18, 0, 8.4, 0, 8, 18, 0, .8))

    // Detached buildings still retain their larger yard setback.
    testing.expect(t, !settlement_oriented_rectangles_clear(0, 0, 8, 18, 0, 9, 0, 8, 18, 0, 2.4))
    testing.expect(t, settlement_oriented_rectangles_clear(0, 0, 8, 18, 0, 11, 0, 8, 18, 0, 2.4))
}

@(test)
settlement_blocks_describe_built_groups :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(&city.parcels, architecture.City_Parcel{corners = {{0, 0}, {8, 0}, {8, 18}, {0, 18}}})
    append(&city.parcels, architecture.City_Parcel{corners = {{9, 0}, {17, 0}, {17, 18}, {9, 18}}})
    city.parcel_count = 2
    settlement_plan_record_built_group(&plan, &city, 0, 2, .Dalmatian_Planned)
    testing.expect_value(t, plan.block_count, 1)
    testing.expect(t, plan.blocks[0].short_side == 17)
    testing.expect(t, plan.blocks[0].long_side == 18)
    testing.expect(t, plan.blocks[0].area == 306)

    // A lone detached house is a parcel, not an invented urban block.
    settlement_plan_record_built_group(&plan, &city, 0, 1, .Later_Extension)
    testing.expect_value(t, plan.block_count, 1)
}

@(test)
settlement_parks_do_not_consume_civic_frontage :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    landmark := terrain.structure_make(0, 0, 12, 10, 0, 24)
    landmark.kind = .Architecture
    _ = terrain.add_structure(project, landmark)
    testing.expect(t, !settlement_park_site_clear(project, 9, 0, 10, 10))
    testing.expect(t, settlement_park_site_clear(project, 24, 0, 10, 10))
}

@(test)
settlement_small_scale_fabric_has_a_contiguous_core :: proc(t: ^testing.T) {
    for hash in u32(0) ..< 1000 {
        testing.expect(t, settlement_fabric_cell_kept(.Town, .58, hash))
        testing.expect(t, settlement_fabric_cell_kept(.Village, .48, hash))
        testing.expect(t, !settlement_fabric_cell_kept(.Town, .85, hash))
        testing.expect(t, !settlement_fabric_cell_kept(.Village, .70, hash))
    }
    testing.expect(t, settlement_fabric_cell_kept(.City, 1, 0))
}

@(test)
settlement_small_scale_fabric_remains_route_accessible :: proc(t: ^testing.T) {
    testing.expect(t, settlement_fabric_route_reachable(.Village, 30, true))
    testing.expect(t, !settlement_fabric_route_reachable(.Village, 30.1, true))
    testing.expect(t, settlement_fabric_route_reachable(.Town, 42, true))
    testing.expect(t, !settlement_fabric_route_reachable(.Town, 42.1, true))
    testing.expect(t, settlement_fabric_route_reachable(.City, 55, true))
    testing.expect(t, !settlement_fabric_route_reachable(.City, 55.1, true))
    testing.expect(t, !settlement_fabric_route_reachable(.City, 0, false))
}

@(test)
settlement_village_prunes_detached_building_islands :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(&city.structures, terrain.structure_make(0, 0, 8, 10, 0, 7))
    append(&city.structures, terrain.structure_make(12, 0, 8, 10, 0, 7))
    append(&city.structures, terrain.structure_make(80, 0, 8, 10, 0, 7))
    append(&city.parcels, architecture.City_Parcel{seed = 1})
    append(&city.parcels, architecture.City_Parcel{seed = 2})
    append(&city.parcels, architecture.City_Parcel{seed = 3})
    city.count = 3
    city.parcel_count = 3
    settlement_city_prune_to_largest_component(&city, 28)
    testing.expect_value(t, city.count, 2)
    testing.expect_value(t, city.parcel_count, 2)
    testing.expect_value(t, city.parcels[0].seed, u32(1))
    testing.expect_value(t, city.parcels[1].seed, u32(2))
}

@(test)
settlement_pedestrian_access_rejects_building_crossings :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(&city.structures, terrain.structure_make(10, 0, 8, 10, 0, 7))
    city.count = 1
    testing.expect(t, !settlement_pedestrian_segment_clear(&city, {0, 0}, {20, 0}))
    testing.expect(t, settlement_pedestrian_segment_clear(&city, {0, 10}, {20, 10}))
}

@(test)
settlement_pedestrian_access_is_sparse_and_bounded :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.request.scale = .Town
    plan.routes[0].geometry.points[0] = {-30, 0}
    plan.routes[0].geometry.points[1] = {30, 0}
    plan.routes[0].geometry.count = 2
    plan.routes[0].width = 4
    plan.routes[0].shoulder = .9
    plan.routes[0].drivable = true
    plan.route_count = 1
    for index in 0 ..< 8 {
        plan.blocks[index] = {
            center     = {f32(index), 13},
            short_side = 6,
            long_side  = 12,
        }
    }
    plan.block_count = 8
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    rng := settlement_rng_new(77)
    settlement_plan_generate_pedestrian_access(&plan, &city, &rng)
    testing.expect_value(t, city.alley_count, 1)
    testing.expect(t, city.alleys[0].half_width >= .4 && city.alleys[0].half_width <= 1.25)
    testing.expect(t, math.abs(city.alleys[0].start_z - 3.35) < .01)
}

@(test)
settlement_acceptance_rejects_wide_roads_and_height_outliers :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    plan: Settlement_Plan
    plan.request = {
        region = .Adriatic,
        scale  = .Village,
    }
    plan.routes[0].geometry.points[0] = {0, 0}
    plan.routes[0].geometry.points[1] = {10, 0}
    plan.routes[0].geometry.count = 2
    plan.routes[0].class = .Street
    plan.routes[0].required = true
    plan.route_count = 1
    plan.sites[0] = {
        structure = terrain.structure_make(0, 0, 7, 9, 0, 7),
        kind      = .Ordinary,
        accepted  = true,
    }
    for index in 1 ..< 8 {
        x := f32((index % 4) * 10 - 15)
        z := f32((index / 4) * 12 - 6)
        plan.sites[index] = {
            structure = terrain.structure_make(x, z, 7, 9, 0, 7),
            kind      = .Ordinary,
            accepted  = true,
        }
        plan.sites[index].structure.height = 7
    }
    plan.sites[8] = {
        structure = terrain.structure_make(10, 0, 8, 8, 0, 18),
        kind      = .Landmark,
        accepted  = true,
    }
    plan.sites[9] = {
        structure = terrain.structure_make(20, 0, 8, 8, 0, 4),
        kind      = .Park,
        accepted  = true,
    }
    plan.sites[0].structure.height = 7
    plan.sites[8].structure.height = 18
    plan.sites[9].structure.height = 4
    plan.site_count = 10
    minimum_height, maximum_height := settlement_height_band(plan.request.region, plan.request.scale)
    testing.expect_value(t, minimum_height, f32(4))
    testing.expect_value(t, maximum_height, f32(11))
    testing.expect_value(t, plan.sites[0].kind, Settlement_Site_Kind.Ordinary)
    testing.expect_value(t, plan.sites[0].structure.height, f32(7))
    settlement_plan_measure(&plan)
    testing.expect(t, plan.metrics.fabric_quadrants >= 2)
    testing.expect(t, plan.metrics.fabric_aspect_ratio <= 3.2)
    testing.expect_value(t, settlement_plan_acceptance_failure(&plan, project), Settlement_Acceptance_Failure.None)
    plan.metrics.wide_route_share = .13
    testing.expect(t, !settlement_plan_acceptance_valid(&plan, project))
    plan.metrics.wide_route_share = 0
    plan.sites[0].structure.height = 23
    testing.expect(t, !settlement_plan_acceptance_valid(&plan, project))
}

@(test)
settlement_acceptance_requires_urban_grouping :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    plan: Settlement_Plan
    plan.request = {
        region = .Aegean,
        scale  = .Town,
    }
    for index in 0 ..< 2 {
        plan.sites[index] = {
            structure = terrain.structure_make(f32(index * 12), 0, 7, 9, 0, 6),
            kind      = .Ordinary,
            accepted  = true,
        }
        plan.sites[index].structure.height = 6
    }
    for index in 2 ..< 4 {
        plan.sites[index] = {
            structure = terrain.structure_make(f32(index * 12), 0, 8, 8, 0, 12),
            kind      = index == 2 ? Settlement_Site_Kind.Landmark : Settlement_Site_Kind.Park,
            accepted  = true,
        }
    }
    plan.site_count = 4
    settlement_plan_measure(&plan)
    testing.expect_value(
        t,
        settlement_plan_acceptance_failure(&plan, project),
        Settlement_Acceptance_Failure.Missing_Blocks,
    )
}

@(test)
settlement_landmark_identity_is_explicit_and_regional :: proc(t: ^testing.T) {
    adriatic := settlement_landmark_seed(.Adriatic, 2, 17)
    aegean := settlement_landmark_seed(.Aegean, 2, 17)
    testing.expect(t, adriatic != aegean)
    structure := terrain.structure_make(0, 0, 10, 10, 0, 18)
    structure.seed = adriatic
    testing.expect(t, settlement_structure_is_landmark(structure))
    structure.seed = 17
    testing.expect(t, !settlement_structure_is_landmark(structure))
}

@(test)
settlement_reserved_site_counts_are_semantic :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.sites[0] = {
        kind     = .Park,
        accepted = true,
    }
    plan.sites[1] = {
        kind     = .Park,
        accepted = false,
    }
    plan.sites[2] = {
        kind     = .Landmark,
        accepted = true,
    }
    plan.site_count = 3
    testing.expect_value(t, settlement_plan_reserved_kind_count(&plan, .Park), 1)
    testing.expect_value(t, settlement_plan_reserved_kind_count(&plan, .Landmark), 1)
}

@(test)
settlement_route_anchors_exclude_fringe_tendrils :: proc(t: ^testing.T) {
    testing.expect(t, settlement_route_anchor_eligible(.City, .78))
    testing.expect(t, !settlement_route_anchor_eligible(.City, .781))
    testing.expect(t, settlement_route_anchor_eligible(.Town, .72))
    testing.expect(t, !settlement_route_anchor_eligible(.Town, .721))
    testing.expect(t, settlement_route_anchor_eligible(.Village, .62))
    testing.expect(t, !settlement_route_anchor_eligible(.Village, .621))
}

@(test)
settlement_route_anchors_require_local_fabric_support :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.request.scale = .City
    plan.macro_cells[0] = {
        center = {0, 0},
        radius = 6,
    }
    plan.macro_cells[1] = {
        center = {10, 0},
        radius = 6,
    }
    plan.macro_cells[2] = {
        center = {-10, 0},
        radius = 6,
    }
    plan.macro_cells[3] = {
        center = {0, 10},
        radius = 6,
    }
    plan.macro_cells[4] = {
        center = {40, 0},
        radius = 6,
    }
    plan.macro_cells[5] = {
        center = {50, 0},
        radius = 6,
    }
    plan.macro_cell_count = 6
    testing.expect(t, settlement_route_anchor_supported(&plan, 0))
    testing.expect(t, !settlement_route_anchor_supported(&plan, 4))
}

@(test)
settlement_route_intersections_are_split_before_commit :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.routes[0].geometry.points[0] = {-10, 0}
    plan.routes[0].geometry.points[1] = {10, 0}
    plan.routes[0].geometry.count = 2
    plan.routes[0].drivable = true
    plan.routes[1].geometry.points[0] = {0, -10}
    plan.routes[1].geometry.points[1] = {0, 10}
    plan.routes[1].geometry.count = 2
    plan.routes[1].drivable = true
    plan.route_count = 2
    settlement_plan_split_route_intersections(&plan)
    testing.expect_value(t, plan.routes[0].geometry.count, 3)
    testing.expect_value(t, plan.routes[1].geometry.count, 3)
    testing.expect(t, settlement_route_point_near(plan.routes[0].geometry.points[1], {0, 0}))
    testing.expect(t, settlement_route_point_near(plan.routes[1].geometry.points[1], {0, 0}))
    nodes, edges := settlement_plan_route_topology_size(&plan)
    testing.expect_value(t, nodes, 5)
    testing.expect_value(t, edges, 4)
}

@(test)
settlement_short_routes_remain_explicit_segments :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    route := settlement_route_find(project, 100, 100, 106, 104, .Civic_Spine)
    testing.expect_value(t, route.count, 2)
    testing.expect(t, settlement_route_point_near(route.points[0], {100, 100}))
    testing.expect(t, settlement_route_point_near(route.points[1], {106, 104}))
}

@(test)
settlement_capacity_simplification_preserves_required_routes :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    for index in 0 ..< 5 {
        plan.routes[index].geometry.points[0] = {f32(index * 20), 0}
        plan.routes[index].geometry.points[1] = {f32(index * 20 + 10), 0}
        plan.routes[index].geometry.count = 2
        plan.routes[index].class = index == 0 ? .Civic_Spine : .Street
        plan.routes[index].required = index < 2
        plan.routes[index].drivable = true
    }
    plan.route_count = 5
    testing.expect(t, settlement_plan_simplify_route_capacity(&plan, 4, 2))
    testing.expect_value(t, plan.route_count, 2)
    testing.expect(t, plan.routes[0].required && plan.routes[1].required)
}

@(test)
settlement_required_anchors_must_share_one_route_component :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    for index in 0 ..< 2 {
        offset := f32(index * 100)
        plan.routes[index].geometry.points[0] = {offset, 0}
        plan.routes[index].geometry.points[1] = {offset + 10, 0}
        plan.routes[index].geometry.count = 2
        plan.routes[index].required = true
        plan.routes[index].drivable = true
    }
    plan.route_count = 2
    testing.expect(t, !settlement_plan_required_routes_connected(&plan))
    plan.routes[1].geometry.points[0] = {10, 0}
    testing.expect(t, settlement_plan_required_routes_connected(&plan))
}

@(test)
settlement_route_submersion_checks_segments_not_only_vertices :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = 0
    terrain.apply_stroke_with_hardness(project, .Raise, -30, 0, 9, 8, 1, .8)
    terrain.apply_stroke_with_hardness(project, .Raise, 30, 0, 9, 8, 1, .8)
    route: Settlement_Route
    route.points[0] = {-30, 0}
    route.points[1] = {30, 0}
    route.count = 2
    testing.expect(t, terrain.sample_height(project, 0, -30, 0) > project.sea_level + .45)
    testing.expect(t, terrain.sample_height(project, 0, 30, 0) > project.sea_level + .45)
    testing.expect(t, settlement_route_crosses_sea(project, route))
}

@(test)
settlement_half_edge_walk_extracts_closed_route_faces :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    points := [4][2]f32{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
    for index in 0 ..< 4 {
        plan.routes[index].geometry.points[0] = points[index]
        plan.routes[index].geometry.points[1] = points[(index + 1) % 4]
        plan.routes[index].geometry.count = 2
        plan.routes[index].drivable = true
    }
    plan.route_count = 4
    testing.expect_value(t, settlement_plan_extract_route_faces(&plan), 1)
    testing.expect_value(t, plan.block_count, 1)
    testing.expect(t, math.abs(plan.blocks[0].area - 100) < .01)
    testing.expect_value(t, plan.blocks[0].corner_count, 4)
}

@(test)
settlement_lab_targets_select_deterministic_fixtures :: proc(t: ^testing.T) {
    fixture, map_view, seed := settlement_lab_target_parse("slope-map-83")
    testing.expect_value(t, fixture, Settlement_Lab_Fixture.Slope)
    testing.expect(t, map_view)
    testing.expect_value(t, seed, "83")
    fixture, map_view, seed = settlement_lab_target_parse("waterfront-211")
    testing.expect_value(t, fixture, Settlement_Lab_Fixture.Waterfront)
    testing.expect(t, !map_view)
    testing.expect_value(t, seed, "211")
}

@(test)
settlement_map_frame_follows_constructed_bounds :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    first := terrain.structure_make(0, 0, 10, 10, 0, 8)
    first.kind = .Architecture
    second := terrain.structure_make(100, 20, 10, 10, 0, 8)
    second.kind = .Architecture
    _ = terrain.add_structure(project, first)
    _ = terrain.add_structure(project, second)
    focus, height := settlement_map_frame(project, {500, 500}, 50)
    testing.expect(t, math.abs(focus[0] - 50) < .01)
    testing.expect(t, math.abs(focus[1] - 10) < .01)
    testing.expect(t, height > 127 && height < 130)
}

@(test)
settlement_terrain_edits_measure_cut_and_fill :: proc(t: ^testing.T) {
    target, cut, fill := settlement_cut_fill_estimate({0, 2, 4, 2, 2}, 100)
    testing.expect_value(t, target, f32(2))
    testing.expect_value(t, cut, f32(40))
    testing.expect_value(t, fill, f32(40))
}

@(test)
settlement_terrain_strokes_refresh_finer_lod_overlaps :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    before := terrain.sample_height(project, 0, center, center)
    terrain.apply_stroke_with_hardness(project, .Raise, center, center, 20, 5, 1, .5)
    fine := terrain.sample_height(project, 0, center, center)
    authored := terrain.sample_height(project, 1, center, center)
    testing.expect(t, fine > before + 2.5)
    testing.expect(t, math.abs(fine - authored) < .05)
}
