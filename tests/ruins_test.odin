package tests

import ruins "../packages/ruins"
import "core:math"
import "core:testing"

@(test)
ruins_generator_is_deterministic_and_seeded :: proc(t: ^testing.T) {
    first := ruins.generate(.Complex, 0x5255494e)
    repeat := ruins.generate(.Complex, 0x5255494e)
    alternate := ruins.generate(.Complex, 0x5255494f)
    testing.expect_value(t, first, repeat)
    testing.expect(t, first.buildings != alternate.buildings || first.props != alternate.props)
}

@(test)
ruin_complexes_are_valid_and_non_overlapping :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        for seed in 0 ..< 128 {
            plan := ruins.generate_for_culture(culture, .Complex, u32(seed))
            testing.expectf(
                t,
                plan.valid,
                "culture=%v seed=%d buildings=%d route_overlaps=%d",
                culture,
                seed,
                plan.building_count,
                plan.route_overlap_count,
            )
            testing.expectf(
                t,
                plan.building_count >= 4,
                "culture=%v seed=%d buildings=%d",
                culture,
                seed,
                plan.building_count,
            )
            for index in 0 ..< plan.building_count {
                testing.expect(t, plan.buildings[index].culture == culture)
                for other in index + 1 ..< plan.building_count {
                    testing.expect(t, !ruins.overlaps(plan.buildings[index], plan.buildings[other]))
                }
            }
        }
    }
}

@(test)
ruins_only_place_props_owned_by_generated_structures :: proc(t: ^testing.T) {
    for mode in ruins.Mode {
        plan := ruins.generate(mode, 1947)
        testing.expect(t, plan.prop_count > 0)
        for prop in plan.props[:plan.prop_count] {
            testing.expect(t, prop.building >= 0 && prop.building < plan.building_count)
        }
    }
}

@(test)
ruin_cultures_generate_distinct_architectural_programs :: proc(t: ^testing.T) {
    roman := ruins.generate_for_culture(.Roman, .Complex, 1947)
    minoan := ruins.generate_for_culture(.Minoan, .Complex, 1947)
    testing.expect(t, roman.buildings[0].kind == .Basilica || roman.buildings[0].kind == .Baths)
    testing.expect(t, minoan.buildings[0].kind == .Palace)
    roman_specific, minoan_specific := false, false
    for building in roman.buildings[:roman.building_count] {
        if building.kind == .Basilica || building.kind == .Baths || building.kind == .Villa do roman_specific = true
    }
    for building in minoan.buildings[:minoan.building_count] {
        if building.kind == .Palace || building.kind == .Magazine do minoan_specific = true
    }
    testing.expect(t, roman_specific)
    testing.expect(t, minoan_specific)
}

@(test)
roman_and_minoan_walls_retain_culture_specific_finishes :: proc(t: ^testing.T) {
    aegean := ruins.make_building_for_culture(.Aegean, .House, {}, 0, 1)
    roman := ruins.make_building_for_culture(.Roman, .Villa, {}, 0, 2)
    minoan := ruins.make_building_for_culture(.Minoan, .Palace, {}, 0, 3)
    testing.expect(t, aegean.wall_finish == .None)
    testing.expect(t, roman.wall_finish == .Roman_Painted_Plaster)
    testing.expect(t, minoan.wall_finish == .Minoan_Painted_Plaster)

    roman.damage = .15
    preserved_coverage := ruins.wall_finish_coverage(roman)
    roman.damage = .55
    weathered_coverage := ruins.wall_finish_coverage(roman)
    roman.damage = .90
    collapsed_coverage := ruins.wall_finish_coverage(roman)
    testing.expect(t, preserved_coverage > weathered_coverage)
    testing.expect(t, weathered_coverage > collapsed_coverage)
    testing.expect(t, ruins.wall_finish_coverage(aegean) == 0)
}

@(test)
ruin_floors_use_cultural_materials_and_erode_with_decay :: proc(t: ^testing.T) {
    aegean := ruins.make_building_for_culture(.Aegean, .House, {}, 0, 11)
    roman := ruins.make_building_for_culture(.Roman, .Villa, {}, 0, 12)
    minoan := ruins.make_building_for_culture(.Minoan, .Palace, {}, 0, 13)
    testing.expect(t, aegean.floor_finish == .Packed_Clay)
    testing.expect(t, roman.floor_finish == .Roman_Mosaic)
    testing.expect(t, minoan.floor_finish == .Minoan_Gypsum_Plaster)

    for building in ([3]ruins.Building{aegean, roman, minoan}) {
        preserved := building
        preserved.damage = .12
        collapsed := building
        collapsed.damage = .92
        testing.expect(t, ruins.floor_finish_coverage(preserved) > ruins.floor_finish_coverage(collapsed))
        testing.expect(t, ruins.floor_finish_coverage(collapsed) > 0)
    }
}

@(test)
ruin_complexes_preserve_stratigraphic_phase_diversity_across_decay :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        preserved := ruins.generate_for_culture(culture, .Complex, 0x57a71, .Preserved)
        collapsed := ruins.generate_for_culture(culture, .Complex, 0x57a71, .Collapsed)
        seen := [3]bool{}
        testing.expect(t, preserved.building_count == collapsed.building_count)
        for building, index in preserved.buildings[:preserved.building_count] {
            testing.expect(t, building.occupation_phase == collapsed.buildings[index].occupation_phase)
            testing.expect(t, building.center == collapsed.buildings[index].center)
            seen[int(building.occupation_phase)] = true
        }
        testing.expect(t, preserved.buildings[0].occupation_phase == .Founding)
        testing.expect(t, seen[int(ruins.Occupation_Phase.Founding)])
        testing.expect(t, seen[int(ruins.Occupation_Phase.Expansion)])
        testing.expect(t, seen[int(ruins.Occupation_Phase.Reoccupation)])
    }
}

@(test)
column_collapse_leaves_monotonic_stumps_and_fallen_drums :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        kind := culture == .Minoan ? ruins.Building_Kind.Palace : ruins.Building_Kind.Temple
        low_damage := ruins.make_building_for_culture(culture, kind, {}, 0, 0xc011)
        high_damage := low_damage
        low_damage.damage = .12
        high_damage.damage = .92
        low_standing, high_standing := 0, 0
        high_remains := 0
        painted := culture == .Minoan
        for index in 0 ..< low_damage.column_count {
            low_state := ruins.column_state(low_damage, index, painted)
            high_state := ruins.column_state(high_damage, index, painted)
            if low_state == .Standing do low_standing += 1
            if high_state == .Standing do high_standing += 1
            if high_state == .Stump || high_state == .Fallen do high_remains += 1
        }
        testing.expect(t, low_standing >= high_standing)
        testing.expect(t, high_remains > 0)
        testing.expect(t, high_standing + high_remains == high_damage.column_count)
    }
}

@(test)
vegetation_encroachment_increases_with_decay_and_keeps_archaeology_clear :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        preserved := ruins.generate_for_culture(culture, .Complex, 0x6a4555, .Preserved)
        collapsed := ruins.generate_for_culture(culture, .Complex, 0x6a4555, .Collapsed)
        preserved_growth, collapsed_growth := 0, 0
        for prop in preserved.props[:preserved.prop_count] {
            if prop.kind == .Grass_Tuft || prop.kind == .Scrub do preserved_growth += 1
        }
        for prop, prop_index in collapsed.props[:collapsed.prop_count] {
            if prop.kind != .Grass_Tuft && prop.kind != .Scrub do continue
            collapsed_growth += 1
            radius := prop.kind == .Scrub ? f32(.48) * prop.scale : f32(.22) * prop.scale
            testing.expect(
                t,
                ruins.vegetation_position_is_clear(&collapsed, prop.building, prop.position, radius, prop_index),
            )
        }
        testing.expect(t, preserved_growth > 0)
        testing.expect(t, collapsed_growth > preserved_growth)
    }
}

@(test)
ruin_pottery_never_blocks_doorways :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        for mode in ruins.Mode {
            for seed in 0 ..< 128 {
                plan := ruins.generate_for_culture(culture, mode, u32(seed))
                for prop in plan.props[:plan.prop_count] {
                    if prop.kind != .Pot &&
                       prop.kind != .Amphora &&
                       prop.kind != .Pithos &&
                       prop.kind != .Dolium &&
                       prop.kind != .Pottery_Sherds {
                        continue
                    }
                    building := plan.buildings[prop.building]
                    radius := f32(.50) * prop.scale
                    if prop.kind == .Pot do radius = .31 * prop.scale
                    if prop.kind == .Amphora do radius = .25 * prop.scale
                    if prop.kind == .Pithos do radius = .46 * prop.scale
                    if prop.kind == .Dolium do radius = .52 * prop.scale
                    testing.expect(t, !ruins.entrance_clearance_contains(building, prop.position, radius))
                }
            }
        }
    }
}

@(test)
ruins_generate_structured_debris_away_from_doorways :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        for seed in 0 ..< 128 {
            plan := ruins.generate_for_culture(culture, .Complex, u32(seed))
            tumbled_walls, rubble_piles := 0, 0
            for prop in plan.props[:plan.prop_count] {
                if prop.kind == .Tumbled_Wall do tumbled_walls += 1
                if prop.kind == .Masonry_Pile ||
                   prop.kind == .Roof_Tile_Pile ||
                   prop.kind == .Fallen_Timber ||
                   prop.kind == .Mudbrick_Fall {
                    rubble_piles += 1
                }
                if prop.kind == .Rubble ||
                   prop.kind == .Fallen_Column ||
                   prop.kind == .Tumbled_Wall ||
                   prop.kind == .Masonry_Pile ||
                   prop.kind == .Roof_Tile_Pile ||
                   prop.kind == .Fallen_Timber ||
                   prop.kind == .Mudbrick_Fall {
                    building := plan.buildings[prop.building]
                    testing.expect(t, !ruins.entrance_clearance_contains(building, prop.position, .55))
                    if prop.kind == .Fallen_Timber {
                        testing.expect(
                            t,
                            !ruins.entrance_clearance_contains(
                                building,
                                prop.position,
                                ruins.prop_traversal_radius(prop),
                            ),
                        )
                    }
                }
            }
            testing.expect(t, tumbled_walls >= plan.building_count)
            testing.expect(t, rubble_piles >= plan.building_count)
        }
    }
}

@(test)
upper_structure_debris_reflects_cultural_building_materials :: proc(t: ^testing.T) {
    aegean := ruins.generate_for_culture(.Aegean, .Complex, 0x700f, .Collapsed)
    roman := ruins.generate_for_culture(.Roman, .Complex, 0x700f, .Collapsed)
    minoan := ruins.generate_for_culture(.Minoan, .Complex, 0x700f, .Collapsed)
    aegean_tiles, roman_tiles, minoan_timber, minoan_mudbrick := 0, 0, 0, 0
    for prop in aegean.props[:aegean.prop_count] {
        if prop.kind == .Roof_Tile_Pile do aegean_tiles += 1
    }
    for prop in roman.props[:roman.prop_count] {
        if prop.kind == .Roof_Tile_Pile do roman_tiles += 1
    }
    for prop in minoan.props[:minoan.prop_count] {
        if prop.kind == .Fallen_Timber do minoan_timber += 1
        if prop.kind == .Mudbrick_Fall do minoan_mudbrick += 1
    }
    testing.expect(t, aegean_tiles > 0)
    testing.expect(t, roman_tiles > 0)
    testing.expect(t, minoan_timber > 0)
    testing.expect(t, minoan_mudbrick > 0)
}

@(test)
tumbled_wall_deposits_correspond_to_explicit_wall_breaches :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        for seed in 0 ..< 128 {
            plan := ruins.generate_for_culture(culture, .Complex, u32(seed))
            for building in plan.buildings[:plan.building_count] {
                testing.expect(t, building.collapsed_sides != 0)
                testing.expect(t, building.collapsed_sides & u8(1 << u32(building.entrance_side)) == 0)
                for side in 0 ..< 4 {
                    if building.collapsed_sides & u8(1 << u32(side)) == 0 do continue
                    extent := side == 0 || side == 2 ? building.width : building.depth
                    testing.expect(t, math.abs(building.collapse_centers[side]) <= extent * .26)
                }
            }
        }
    }
}

@(test)
structural_collapse_follows_a_stable_site_failure_direction :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        preserved := ruins.generate_for_culture(culture, .Complex, 0xc011a95e, .Preserved)
        collapsed := ruins.generate_for_culture(culture, .Complex, 0xc011a95e, .Collapsed)
        testing.expect(t, preserved.collapse_yaw == collapsed.collapse_yaw)
        for building, index in collapsed.buildings[:collapsed.building_count] {
            earlier := preserved.buildings[index]
            testing.expect(t, building.collapse_yaw == earlier.collapse_yaw)
            wall := ruins.collapse_wall_for_index(building, 0)
            testing.expect(t, wall != building.entrance_side)
            testing.expect(t, building.collapsed_sides & u8(1 << u32(wall)) != 0)
            outward := ruins.wall_outward_world(building, wall)
            direction := ruins.Vec2{math.cos(building.collapse_yaw), math.sin(building.collapse_yaw)}
            testing.expect(t, outward.x * direction.x + outward.z * direction.z >= -.001)
        }
    }
}

@(test)
ruin_complex_routes_reach_every_generated_building_entrance :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        for seed in 0 ..< 128 {
            plan := ruins.generate_for_culture(culture, .Complex, u32(seed))
            testing.expect(t, plan.route_count >= plan.building_count + 1)
            for index in 0 ..< plan.building_count {
                expected := ruins.entrance_position(plan.buildings[index])
                found := false
                for route in plan.routes[:plan.route_count] {
                    if route.building != index do continue
                    dx, dz := route.a.x - expected.x, route.a.z - expected.z
                    if dx * dx + dz * dz < .001 {
                        testing.expect(t, route.width >= 1.5)
                        found = true
                        break
                    }
                }
                testing.expect(t, found)
            }
        }
    }
}

@(test)
complex_building_thresholds_face_the_shared_court :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        for scale in ruins.Complex_Scale {
            for seed in 0 ..< 64 {
                plan := ruins.generate_for_culture(culture, .Complex, u32(seed), .Weathered, .Typical, scale)
                for building, building_index in plan.buildings[:plan.building_count] {
                    assigned_court := plan.court
                    if building.route_hub > 0 && building.route_hub <= plan.precinct_count {
                        assigned_court = plan.precincts[building.route_hub - 1]
                    }
                    entrance := ruins.entrance_position(building)
                    center_dx := building.center.x - assigned_court.center.x
                    center_dz := building.center.z - assigned_court.center.z
                    entrance_dx := entrance.x - assigned_court.center.x
                    entrance_dz := entrance.z - assigned_court.center.z
                    testing.expectf(
                        t,
                        entrance_dx * entrance_dx + entrance_dz * entrance_dz <
                        center_dx * center_dx + center_dz * center_dz,
                        "%s %s seed %d has a threshold facing away from its court",
                        ruins.culture_name(culture),
                        ruins.complex_scale_name(scale),
                        seed,
                    )
                    route_found := false
                    for route in plan.routes[:plan.route_count] {
                        start_dx := route.a.x - entrance.x
                        start_dz := route.a.z - entrance.z
                        if route.building != building_index || start_dx * start_dx + start_dz * start_dz >= .001 {
                            continue
                        }
                        outward_x := entrance.x - building.center.x
                        outward_z := entrance.z - building.center.z
                        departure_x := route.b.x - route.a.x
                        departure_z := route.b.z - route.a.z
                        testing.expectf(
                            t,
                            departure_x * outward_x + departure_z * outward_z > 0,
                            "%s %s seed %d has an approach entering through its owner footprint",
                            ruins.culture_name(culture),
                            ruins.complex_scale_name(scale),
                            seed,
                        )
                        route_found = true
                        break
                    }
                    testing.expect(t, route_found)
                }
            }
        }
    }
}

@(test)
extensive_complexes_form_connected_secondary_precincts :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        for seed in 0 ..< 64 {
            plan := ruins.generate_for_culture(culture, .Complex, u32(seed), .Weathered, .Typical, .Extensive)
            testing.expect(t, plan.precinct_count == ruins.PRECINCT_CAPACITY)
            assigned := 0
            for building in plan.buildings[:plan.building_count] {
                if building.route_hub > 0 do assigned += 1
                testing.expect(t, building.route_hub >= 0 && building.route_hub <= plan.precinct_count)
            }
            testing.expectf(
                t,
                assigned >= 2,
                "%s seed %d did not form a meaningful secondary precinct",
                ruins.culture_name(culture),
                seed,
            )
            for precinct in plan.precincts[:plan.precinct_count] {
                connected := false
                for route in plan.routes[:plan.route_count] {
                    from_dx := route.a.x - precinct.center.x
                    from_dz := route.a.z - precinct.center.z
                    to_dx := route.b.x - plan.court.center.x
                    to_dz := route.b.z - plan.court.center.z
                    if from_dx * from_dx + from_dz * from_dz < .001 && to_dx * to_dx + to_dz * to_dz < .001 {
                        connected = true
                        break
                    }
                }
                testing.expect(t, connected)
            }
        }
    }
}

@(test)
extensive_precinct_morphology_is_culture_specific :: proc(t: ^testing.T) {
    roman := ruins.generate_for_culture(.Roman, .Complex, 41, .Weathered, .Typical, .Extensive)
    minoan := ruins.generate_for_culture(.Minoan, .Complex, 41, .Weathered, .Typical, .Extensive)
    aegean_a := ruins.generate_for_culture(.Aegean, .Complex, 41, .Weathered, .Typical, .Extensive)
    aegean_b := ruins.generate_for_culture(.Aegean, .Complex, 42, .Weathered, .Typical, .Extensive)
    testing.expect(t, roman.precinct_layout == .Formal_Axis)
    testing.expect(t, minoan.precinct_layout == .Offset_Terraces)
    testing.expect(t, aegean_a.precinct_layout == .Irregular_Temenos)
    testing.expect(t, math.abs(roman.precincts[0].center.z - roman.court.center.z) < .001)
    testing.expect(t, math.abs(roman.precincts[1].center.z - roman.court.center.z) < .001)
    testing.expect(
        t,
        math.abs(
            (roman.precincts[0].center.x - roman.court.center.x) +
            (roman.precincts[1].center.x - roman.court.center.x),
        ) <
        .001,
    )
    testing.expect(t, minoan.precincts[0].center.z != minoan.precincts[1].center.z)
    testing.expect(t, minoan.precincts[0].yaw != minoan.precincts[1].yaw)
    testing.expect(t, aegean_a.precincts != aegean_b.precincts)
}

@(test)
complex_enclosures_are_cultural_and_keep_a_clear_gate :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        for seed in 0 ..< 64 {
            plan := ruins.generate_for_culture(culture, .Complex, u32(seed))
            expected := ruins.Enclosure_Layout.Irregular_Temenos
            if culture == .Roman do expected = .Rectilinear_Pomerium
            if culture == .Minoan do expected = .Terraced_Peribolos
            testing.expect(t, plan.enclosure_layout == expected)
            testing.expect(t, plan.enclosure_count >= 7)
            right_gate := plan.enclosure[2].b
            left_gate := plan.enclosure[3].a
            testing.expect(t, right_gate.x > 0 && left_gate.x < 0)
            testing.expect(t, right_gate.x - left_gate.x >= 6.3)
            testing.expect(t, math.abs(right_gate.z - left_gate.z) < .001)
            diagonal_boundary := false
            for segment in plan.enclosure[:5] {
                dx := math.abs(segment.b.x - segment.a.x)
                dz := math.abs(segment.b.z - segment.a.z)
                if dx > .01 && dz > .01 do diagonal_boundary = true
            }
            testing.expect(t, diagonal_boundary == (culture != .Roman))
        }
    }
}

@(test)
complex_gateways_are_cultural_and_preserve_the_approach_opening :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        for profile in ruins.Terrain_Profile {
            for seed in 0 ..< 64 {
                plan := ruins.generate_for_site(culture, .Complex, u32(seed), ruins.default_site(profile))
                expected := ruins.Gateway_Kind.Aegean_Propylon
                if culture == .Roman do expected = .Roman_Gatehouse
                if culture == .Minoan do expected = .Minoan_Guardrooms
                testing.expect(t, plan.has_gateway)
                testing.expect(t, plan.gateway.kind == expected)
                testing.expect(t, plan.gateway.clear_width >= 6.3)
                testing.expect(t, plan.gateway.depth >= 3)
                right_gate := plan.enclosure[2].b
                left_gate := plan.enclosure[3].a
                testing.expect(t, math.abs(plan.gateway.position.x) < .001)
                testing.expect(t, math.abs(plan.gateway.position.z - right_gate.z) < .001)
                testing.expect(t, math.abs(plan.gateway.clear_width - (right_gate.x - left_gate.x)) < .001)
                testing.expect(t, plan.gateway.base_y >= 0)
            }
        }
    }
    single := ruins.generate_for_culture(.Roman, .Ruin, 9)
    testing.expect(t, !single.has_gateway)
}

@(test)
ruin_building_families_receive_distinct_interior_layouts :: proc(t: ^testing.T) {
    temple := ruins.make_building_for_culture(.Aegean, .Temple, {}, 0, 1)
    basilica := ruins.make_building_for_culture(.Roman, .Basilica, {}, 0, 2)
    baths := ruins.make_building_for_culture(.Roman, .Baths, {}, 0, 3)
    villa := ruins.make_building_for_culture(.Roman, .Villa, {}, 0, 4)
    palace := ruins.make_building_for_culture(.Minoan, .Palace, {}, 0, 5)
    magazine := ruins.make_building_for_culture(.Minoan, .Magazine, {}, 0, 6)
    testing.expect(t, temple.interior_layout == .Cella && temple.room_count == 2)
    testing.expect(t, temple.colonnade_layout == .Peristyle && temple.column_count >= 10)
    testing.expect(t, basilica.interior_layout == .Aisled_Hall && basilica.room_count == 3)
    testing.expect(t, basilica.colonnade_layout == .Nave_Aisles && basilica.column_count >= 10)
    testing.expect(t, basilica.signature_remain == .Basilica_Tribunal)
    testing.expect(t, baths.interior_layout == .Chambers && baths.room_count >= 4)
    testing.expect(t, baths.signature_remain == .Bath_Hypocaust)
    testing.expect(t, villa.interior_layout == .Courtyard && villa.room_count >= 5)
    testing.expect(t, palace.interior_layout == .Courtyard && palace.room_count >= 7)
    testing.expect(t, palace.colonnade_layout == .Court && palace.column_count == 5)
    testing.expect(t, palace.signature_remain == .Palace_Grand_Stair)
    testing.expect(t, magazine.interior_layout == .Magazines && magazine.room_count == 3)
    testing.expect(t, magazine.signature_remain == .Magazine_Pithos_Beds)
}

@(test)
ruin_sites_condition_buildings_and_routes_to_terrain :: proc(t: ^testing.T) {
    flat := ruins.generate_for_site(.Aegean, .Complex, 1947, ruins.default_site(.Flat))
    incline := ruins.generate_for_site(.Aegean, .Complex, 1947, ruins.default_site(.Incline))
    terraced := ruins.generate_for_site(.Aegean, .Complex, 1947, ruins.default_site(.Terraced))
    testing.expect(t, flat.elevation_range == 0)
    testing.expect(t, incline.elevation_range > 0)
    testing.expect(t, terraced.elevation_range > 0)
    testing.expect(t, flat.buildings == ruins.generate_for_culture(.Aegean, .Complex, 1947).buildings)
    for building in incline.buildings[:incline.building_count] {
        testing.expect(t, building.base_y >= 0)
    }
    terrace_height := ruins.default_site(.Terraced).terrace_height
    for building in terraced.buildings[:terraced.building_count] {
        tier := building.base_y / terrace_height
        testing.expect(t, math.abs(tier - f32(math.round(tier))) < .001)
    }
    for route in terraced.routes[:terraced.route_count] {
        testing.expect(t, route.a_y >= 0)
        testing.expect(t, route.b_y >= 0)
    }
    flat_stairs, incline_stairs, terraced_stairs := 0, 0, 0
    for route in flat.routes[:flat.route_count] {
        if ruins.route_requires_stairs(&flat, route) do flat_stairs += 1
    }
    for route in incline.routes[:incline.route_count] {
        if ruins.route_requires_stairs(&incline, route) do incline_stairs += 1
    }
    for route in terraced.routes[:terraced.route_count] {
        if ruins.route_requires_stairs(&terraced, route) do terraced_stairs += 1
    }
    testing.expect(t, flat_stairs == 0)
    testing.expect(t, incline_stairs == 0)
    testing.expect(t, terraced_stairs > 0)
}

@(test)
ruin_routes_do_not_cross_unrelated_building_footprints :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        for profile in ruins.Terrain_Profile {
            for seed in 0 ..< 128 {
                plan := ruins.generate_for_site(culture, .Complex, u32(seed), ruins.default_site(profile))
                testing.expect(t, plan.route_overlap_count == 0)
                for route in plan.routes[:plan.route_count] {
                    for building, index in plan.buildings[:plan.building_count] {
                        if index == route.building do continue
                        testing.expect(t, !ruins.route_intersects_building(route.a, route.b, route.width, building))
                    }
                }
            }
        }
    }
}

@(test)
ruin_routes_remain_clear_of_foreign_archaeological_deposits :: proc(t: ^testing.T) {
    relocations := 0
    for culture in ruins.Culture {
        for profile in ruins.Terrain_Profile {
            for seed in 0 ..< 128 {
                plan := ruins.generate_for_site(culture, .Complex, u32(seed), ruins.default_site(profile))
                relocations += plan.relocated_prop_count
                for route in plan.routes[:plan.route_count] {
                    for prop in plan.props[:plan.prop_count] {
                        if prop.building == route.building do continue
                        testing.expect(t, !ruins.route_intersects_prop(route.a, route.b, route.width, prop))
                    }
                }
            }
        }
    }
    testing.expect(t, relocations > 0)
}

@(test)
ruin_complex_court_features_are_cultural_and_clear_of_access_routes :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        expected := ruins.Site_Feature_Kind.Altar_Platform
        if culture == .Roman do expected = .Cistern
        if culture == .Minoan do expected = .Lustral_Basin
        for profile in ruins.Terrain_Profile {
            for seed in 0 ..< 128 {
                plan := ruins.generate_for_site(culture, .Complex, u32(seed), ruins.default_site(profile))
                testing.expectf(
                    t,
                    plan.feature_count == 1,
                    "culture=%v profile=%v seed=%d generated no clear court feature",
                    culture,
                    profile,
                    seed,
                )
                if plan.feature_count == 0 do continue
                feature := plan.features[0]
                testing.expect(t, feature.kind == expected)
                testing.expect(t, feature.base_y >= 0)
                testing.expect(t, ruins.site_feature_is_clear(&plan, feature.kind, feature.position, feature.scale))
            }
        }
    }
}

@(test)
ruin_complexes_reserve_a_clear_cultural_court :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        for seed in 0 ..< 128 {
            plan := ruins.generate_for_culture(culture, .Complex, u32(seed))
            testing.expect(t, plan.court.width > 0 && plan.court.depth > 0)
            if culture == .Roman do testing.expect(t, plan.court.width > plan.court.depth)
            if culture == .Minoan do testing.expect(t, plan.court.depth > plan.court.width)
            footprint := ruins.Building {
                center = plan.court.center,
                width  = plan.court.width,
                depth  = plan.court.depth,
                yaw    = plan.court.yaw,
            }
            // The anchor fronts the court intentionally; all orbiting
            // structures must preserve its usable civic footprint.
            for building in plan.buildings[1:plan.building_count] {
                diameter := math.sqrt(building.width * building.width + building.depth * building.depth)
                testing.expect(
                    t,
                    !ruins.route_intersects_building(building.center, building.center, diameter + 2, footprint),
                )
            }
        }
    }
}

@(test)
preservation_profiles_change_decay_without_rerolling_the_site_plan :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        preserved_sherds, weathered_sherds, collapsed_sherds := 0, 0, 0
        for seed in 0 ..< 128 {
            preserved := ruins.generate_for_culture(culture, .Complex, u32(seed), .Preserved)
            weathered := ruins.generate_for_culture(culture, .Complex, u32(seed), .Weathered)
            collapsed := ruins.generate_for_culture(culture, .Complex, u32(seed), .Collapsed)
            testing.expect(t, preserved.building_count == weathered.building_count)
            testing.expect(t, weathered.building_count == collapsed.building_count)
            testing.expect(t, preserved.court == weathered.court && weathered.court == collapsed.court)
            for index in 0 ..< weathered.building_count {
                a, b, c := preserved.buildings[index], weathered.buildings[index], collapsed.buildings[index]
                testing.expect(t, a.center == b.center && b.center == c.center)
                testing.expect(t, a.kind == b.kind && b.kind == c.kind)
                testing.expect(t, a.damage < b.damage && b.damage < c.damage)
            }
            preserved_falls, collapsed_falls := 0, 0
            for prop in preserved.props[:preserved.prop_count] {
                if prop.kind == .Tumbled_Wall do preserved_falls += 1
            }
            for prop in collapsed.props[:collapsed.prop_count] {
                if prop.kind == .Tumbled_Wall do collapsed_falls += 1
            }
            for prop in preserved.props[:preserved.prop_count] {
                if prop.kind == .Pottery_Sherds do preserved_sherds += 1
            }
            for prop in weathered.props[:weathered.prop_count] {
                if prop.kind == .Pottery_Sherds do weathered_sherds += 1
            }
            for prop in collapsed.props[:collapsed.prop_count] {
                if prop.kind == .Pottery_Sherds do collapsed_sherds += 1
            }
            testing.expect(t, collapsed_falls > preserved_falls)
            testing.expect(t, preserved.prop_count <= collapsed.prop_count)
        }
        testing.expect(t, preserved_sherds < weathered_sherds)
        testing.expect(t, weathered_sherds < collapsed_sherds)
    }
}

@(test)
complex_enclosures_surround_the_site_and_leave_the_main_gate_clear :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        for profile in ruins.Terrain_Profile {
            for seed in 0 ..< 128 {
                plan := ruins.generate_for_site(culture, .Complex, u32(seed), ruins.default_site(profile))
                testing.expect(t, plan.enclosure_count == 7)
                north_z := plan.enclosure[2].a.z
                testing.expect(t, plan.routes[0].a.z > north_z)
                testing.expect(t, plan.routes[0].b.x == 0)
                // The two northern runs terminate on opposite sides of x=0;
                // no generated precinct masonry spans the ceremonial gate.
                testing.expect(t, plan.enclosure[2].b.x > 0)
                testing.expect(t, plan.enclosure[3].a.x < 0)
                gate_clearance := plan.enclosure[2].b.x - plan.enclosure[2].width * .5
                testing.expect(t, gate_clearance > plan.routes[0].width * .5 + .35)
                for segment in plan.enclosure[:plan.enclosure_count] {
                    testing.expect(t, segment.a_y >= 0 && segment.b_y >= 0)
                    testing.expect(t, segment.width > 0 && segment.height > 0)
                }
                half_x := math.abs(plan.enclosure[0].a.x)
                half_z := math.abs(plan.enclosure[0].a.z)
                for building in plan.buildings[:plan.building_count] {
                    radius := math.sqrt(building.width * building.width + building.depth * building.depth) * .5
                    testing.expect(t, math.abs(building.center.x) + radius <= half_x + .001)
                    testing.expect(t, math.abs(building.center.z) + radius <= half_z + .001)
                }
            }
        }
    }
}

@(test)
complex_drainage_is_cultural_downhill_and_clear_of_buildings :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        expected := ruins.Drainage_Kind.Runoff_Gutter
        if culture == .Roman do expected = .Capped_Drain
        if culture == .Minoan do expected = .Plaster_Channel
        for profile in ruins.Terrain_Profile {
            for seed in 0 ..< 128 {
                plan := ruins.generate_for_site(culture, .Complex, u32(seed), ruins.default_site(profile))
                testing.expectf(
                    t,
                    plan.drainage_count == 1,
                    "culture=%v profile=%v seed=%d has no building-clear drain",
                    culture,
                    profile,
                    seed,
                )
                if plan.drainage_count == 0 do continue
                channel := plan.drainage[0]
                testing.expect(t, channel.kind == expected)
                testing.expect(t, channel.a_y + .001 >= channel.b_y)
                testing.expect(t, channel.width > 0)
                testing.expect(t, ruins.route_is_clear_of_buildings(&plan, channel.a, channel.b, channel.width))
            }
        }
    }
}

@(test)
domestic_ruins_receive_more_pottery_than_tombs :: proc(t: ^testing.T) {
    house := ruins.make_building(.House, {}, 0, 17)
    tomb := ruins.make_building(.Tomb, {}, 0, 17)
    house_plan := ruins.Plan {
        building_count = 1,
    }
    tomb_plan := ruins.Plan {
        building_count = 1,
    }
    house_plan.buildings[0] = house
    tomb_plan.buildings[0] = tomb
    ruins.furnish(&house_plan, 0)
    ruins.furnish(&tomb_plan, 0)
    house_pottery, tomb_pottery := 0, 0
    for prop in house_plan.props[:house_plan.prop_count] {
        if prop.kind == .Pot ||
           prop.kind == .Amphora ||
           prop.kind == .Pithos ||
           prop.kind == .Dolium ||
           prop.kind == .Pottery_Sherds {
            house_pottery += 1
        }
    }
    for prop in tomb_plan.props[:tomb_plan.prop_count] {
        if prop.kind == .Pot ||
           prop.kind == .Amphora ||
           prop.kind == .Pithos ||
           prop.kind == .Dolium ||
           prop.kind == .Pottery_Sherds {
            tomb_pottery += 1
        }
    }
    testing.expect(t, house_pottery > tomb_pottery)
}

@(test)
storage_buildings_receive_culture_specific_large_vessels :: proc(t: ^testing.T) {
    magazine := ruins.make_building_for_culture(.Minoan, .Magazine, {}, 0, 0x5170)
    villa := ruins.make_building_for_culture(.Roman, .Villa, {}, 0, 0x5171)
    magazine.damage, villa.damage = 0, 0
    minoan := ruins.Plan {
        culture        = .Minoan,
        building_count = 1,
    }
    roman := ruins.Plan {
        culture        = .Roman,
        building_count = 1,
    }
    minoan.buildings[0] = magazine
    roman.buildings[0] = villa
    ruins.furnish(&minoan, 0)
    ruins.furnish(&roman, 0)
    pithoi, dolia := 0, 0
    for prop in minoan.props[:minoan.prop_count] {
        if prop.kind == .Pithos do pithoi += 1
    }
    for prop in roman.props[:roman.prop_count] {
        if prop.kind == .Dolium do dolia += 1
    }
    testing.expect(t, pithoi >= 2)
    testing.expect(t, dolia == 1)
}

@(test)
pottery_density_scales_finds_without_changing_architecture :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        sparse := ruins.generate_for_culture(culture, .Complex, 0xd3a517, .Weathered, .Sparse)
        typical := ruins.generate_for_culture(culture, .Complex, 0xd3a517, .Weathered, .Typical)
        abundant := ruins.generate_for_culture(culture, .Complex, 0xd3a517, .Weathered, .Abundant)
        testing.expect(t, sparse.buildings == typical.buildings)
        testing.expect(t, typical.buildings == abundant.buildings)
        sparse_count, typical_count, abundant_count := 0, 0, 0
        plans := [3]^ruins.Plan{&sparse, &typical, &abundant}
        counts := [3]^int{&sparse_count, &typical_count, &abundant_count}
        for plan, plan_index in plans {
            testing.expect(t, plan.valid)
            for prop in plan.props[:plan.prop_count] {
                if prop.kind == .Pot ||
                   prop.kind == .Amphora ||
                   prop.kind == .Pithos ||
                   prop.kind == .Dolium ||
                   prop.kind == .Pottery_Sherds {
                    counts[plan_index]^ += 1
                    radius := ruins.prop_traversal_radius(prop)
                    building := plan.buildings[prop.building]
                    testing.expect(t, !ruins.entrance_clearance_contains(building, prop.position, radius))
                }
            }
        }
        testing.expect(t, sparse_count < typical_count)
        testing.expect(t, typical_count < abundant_count)
    }
}

@(test)
complex_scale_orders_structure_counts_and_preserves_valid_access :: proc(t: ^testing.T) {
    for culture in ruins.Culture {
        for seed in 0 ..< 32 {
            compact := ruins.generate_for_culture(culture, .Complex, u32(seed), .Weathered, .Typical, .Compact)
            standard := ruins.generate_for_culture(culture, .Complex, u32(seed), .Weathered, .Typical, .Standard)
            extensive := ruins.generate_for_culture(culture, .Complex, u32(seed), .Weathered, .Typical, .Extensive)
            testing.expect(t, compact.valid)
            testing.expect(t, standard.valid)
            testing.expectf(
                t,
                extensive.valid,
                "extensive %s seed %d invalid: %d buildings, %d unresolved routes",
                ruins.culture_name(culture),
                seed,
                extensive.building_count,
                extensive.route_overlap_count,
            )
            testing.expect(t, compact.building_count <= standard.building_count)
            testing.expect(t, standard.building_count <= extensive.building_count)
            testing.expect(t, extensive.building_count >= 8)
            testing.expect(t, extensive.route_count <= ruins.ROUTE_CAPACITY)
            testing.expect(t, extensive.prop_count <= ruins.PROP_CAPACITY)
        }
    }
}
