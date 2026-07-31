package main

import architecture "../packages/architecture"
import cemeteries "../packages/cemeteries"
import plants "../packages/plants"
import roads "../packages/roads"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:testing"

@(test)
settlement_cemetery_scales_with_settlement_and_preserves_regional_style :: proc(t: ^testing.T) {
    village_width, village_depth, village_density := settlement_cemetery_dimensions(.Village)
    city_width, city_depth, city_density := settlement_cemetery_dimensions(.City)
    testing.expect(t, city_width > village_width)
    testing.expect(t, city_depth > village_depth)
    testing.expect(t, city_density > village_density)

    adriatic := cemeteries.generate(17, {width = village_width, depth = village_depth, density = village_density, style = .Adriatic_Medieval})
    aegean := cemeteries.generate(17, {width = village_width, depth = village_depth, density = village_density, style = .Classical_Aegean})
    testing.expect(t, adriatic.valid && aegean.valid)
    for grave in adriatic.graves[:adriatic.grave_count] do testing.expect(t, cemeteries.style_supports_marker(.Adriatic_Medieval, grave.marker))
    for grave in aegean.graves[:aegean.grave_count] do testing.expect(t, cemeteries.style_supports_marker(.Classical_Aegean, grave.marker))
}

@(test)
settlement_cemetery_reservation_tag_does_not_match_ordinary_foliage :: proc(t: ^testing.T) {
    ordinary := terrain.Structure{group_id = 42, kind = .Foliage}
    reserved := terrain.Structure{group_id = SETTLEMENT_CEMETERY_GROUP_TAG | 42, kind = .Foliage}
    testing.expect(t, !settlement_cemetery_structure_is_reservation(ordinary))
    testing.expect(t, settlement_cemetery_structure_is_reservation(reserved))
}

@(test)
settlement_cemetery_outer_radius_includes_macro_cell_extent :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.request.center = {10, 20}
    plan.macro_cells[0] = {center = {13, 24}, radius = 7}
    plan.macro_cell_count = 1
    testing.expect(t, math.abs(settlement_cemetery_outer_radius(&plan) - 12) < .001)
}

@(test)
settlement_garden_plants_stay_inside_their_plots :: proc(t: ^testing.T) {
    household := Settlement_Site {
        kind = .Ordinary,
        parcel = {corners = {{-5, -3}, {5, -3}, {5, 3}, {-5, 3}}},
    }
    testing.expect(t, settlement_garden_point_in_plot(household, 0, 0, .4))
    testing.expect(t, !settlement_garden_point_in_plot(household, 0, -3.1, .4))
    testing.expect(t, !settlement_garden_point_in_plot(household, 0, -2.8, .4))

    park := Settlement_Site {
        kind = .Park,
        structure = {center_x = 10, center_z = 20, width = 8, depth = 4, rotation = math.PI / 2},
    }
    testing.expect(t, settlement_garden_point_in_plot(park, 10, 23, .4))
    testing.expect(t, !settlement_garden_point_in_plot(park, 13, 20, .4))
}

@(test)
garden_courtyard_keeps_woody_trunks_off_the_cross_path :: proc(t: ^testing.T) {
    for seed in ([3]u32{1, 73, 211}) {
        plan := garden_generate(seed, .Courtyard)
        for plant in plan.plants[:plan.plant_count] {
            if plant.kind != .Cypress && plant.kind != .Shrub do continue
            testing.expect(t, math.abs(plant.position.x) >= .8)
            testing.expect(t, math.abs(plant.position.z) >= .8)
        }
    }
}

@(test)
settlement_gardens_mix_regional_trees_shrubs_and_groundcover :: proc(t: ^testing.T) {
    species, _, woody := settlement_garden_woody_species(.Adriatic, .Park, 0, 1)
    testing.expect_value(t, species, plants.Species.Stone_Pine)
    testing.expect(t, woody)

    species, _, woody = settlement_garden_woody_species(.Aegean, .Park, 0, 1)
    testing.expect_value(t, species, plants.Species.Olive)
    testing.expect(t, woody)

    species, _, woody = settlement_garden_woody_species(.Adriatic, .Kitchen, 0, 1)
    testing.expect_value(t, species, plants.Species.Olive)
    testing.expect(t, woody)

    species, _, woody = settlement_garden_woody_species(.Aegean, .Wild, 2, 0)
    testing.expect_value(t, species, plants.Species.Mastic)
    testing.expect(t, woody)

    _, _, woody = settlement_garden_woody_species(.Adriatic, .Courtyard, 3, 1)
    testing.expect(t, !woody)
}

@(test)
settlement_landscape_has_a_village_budget_without_gardens :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.request.scale = .Village
    plan.garden_count = 0
    testing.expect_value(t, settlement_landscape_target(plan.request.scale), 8)

    species, _ := settlement_landscape_species(.Adriatic, 0, 0)
    testing.expect_value(t, species, plants.Species.Stone_Pine)
    species, _ = settlement_landscape_species(.Aegean, 0, 0)
    testing.expect_value(t, species, plants.Species.Olive)
    species, _ = settlement_landscape_species(.Aegean, 1, 0)
    testing.expect_value(t, species, plants.Species.Mastic)
}

@(test)
settlement_brush_fixed_presets_and_shape_masks :: proc(t: ^testing.T) {
    testing.expect_value(t, settlement_brush_preset_span(.Small), f32(60))
    testing.expect_value(t, settlement_brush_preset_span(.Medium), f32(120))
    testing.expect_value(t, settlement_brush_preset_span(.Large), f32(220))

    circle := Settlement_Brush_Piece {
        shape    = .Circle,
        preset   = .Small,
        density  = 1,
        hardness = 1,
    }
    testing.expect(t, settlement_brush_signed_distance(circle, {0, 0}) < 0)
    testing.expect(t, math.abs(settlement_brush_signed_distance(circle, {30, 0})) < .001)
    testing.expect(t, settlement_brush_signed_distance(circle, {31, 0}) > 0)

    square := circle
    square.shape = .Square
    testing.expect(t, settlement_brush_signed_distance(square, {29, 29}) < 0)
    testing.expect(t, settlement_brush_signed_distance(square, {31, 0}) > 0)

    rectangle := circle
    rectangle.shape = .Rectangle
    testing.expect(t, settlement_brush_signed_distance(rectangle, {29, 16}) < 0)
    testing.expect(t, settlement_brush_signed_distance(rectangle, {0, 17}) > 0)
}

@(test)
settlement_brush_macaroni_is_a_bounded_curved_arc :: proc(t: ^testing.T) {
    piece := Settlement_Brush_Piece {
        shape    = .Macaroni,
        preset   = .Small,
        density  = 1,
        hardness = .5,
    }
    thickness := settlement_brush_preset_span(piece.preset) * .28
    centerline_radius := settlement_brush_preset_span(piece.preset) * .5 - thickness * .5
    testing.expect(t, settlement_brush_signed_distance(piece, {centerline_radius, 0}) < 0)
    testing.expect(t, settlement_brush_signed_distance(piece, {-centerline_radius, 0}) > 0)
    endpoint := [2]f32 {
        f32(math.cos(f64(math.PI / 3))) * centerline_radius,
        f32(math.sin(f64(math.PI / 3))) * centerline_radius,
    }
    testing.expect(t, settlement_brush_signed_distance(piece, endpoint) < 0)
}

@(test)
settlement_density_smooth_max_is_bounded_and_non_accumulating :: proc(t: ^testing.T) {
    testing.expect_value(t, settlement_density_smooth_max(.3, .8), f32(.8))
    repeated := settlement_density_smooth_max(.8, .8)
    testing.expect(t, math.abs(repeated - .8) < .0001)
    testing.expect(t, settlement_density_smooth_max(.76, .8) >= .76)
    testing.expect(t, settlement_density_smooth_max(.76, .8) <= .8)
}

@(test)
settlement_brush_components_attach_within_the_connection_margin :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    first := Settlement_Brush_Piece {
        shape  = .Circle,
        preset = .Small,
        center = {0, 0},
    }
    settlement_brush_assign_component(&plan, &first)
    plan.brush_pieces[0] = first
    plan.brush_piece_count = 1
    nearby := Settlement_Brush_Piece {
        shape  = .Square,
        preset = .Small,
        center = {80, 0},
    }
    settlement_brush_assign_component(&plan, &nearby)
    testing.expect_value(t, nearby.component_id, first.component_id)
    remote := Settlement_Brush_Piece {
        shape  = .Square,
        preset = .Small,
        center = {200, 0},
    }
    settlement_brush_assign_component(&plan, &remote)
    testing.expect(t, remote.component_id != first.component_id)
}

@(test)
settlement_brush_store_round_trips_authored_pieces :: proc(t: ^testing.T) {
    path := "/tmp/adriatic-settlement-brush-roundtrip.bin"
    defer os.remove(path)
    source: Settlement_Plan
    source.brush_piece_count = 2
    source.next_brush_component_id = 7
    source.brush_pieces[0] = {
        shape        = .Macaroni,
        preset       = .Large,
        center       = {12, -34},
        rotation     = .75,
        density      = .62,
        hardness     = .41,
        seed         = 99,
        component_id = 6,
    }
    source.brush_pieces[1] = {
        shape        = .Rectangle,
        preset       = .Small,
        center       = {-8, 5},
        rotation     = -.2,
        density      = .38,
        hardness     = .8,
        seed         = 101,
        component_id = 7,
        erased       = true,
    }
    testing.expect(t, settlement_brush_store_save(&source, path))
    loaded: Settlement_Plan
    testing.expect(t, settlement_brush_store_load(&loaded, path))
    testing.expect_value(t, loaded.brush_piece_count, 2)
    testing.expect_value(t, loaded.next_brush_component_id, u32(7))
    testing.expect_value(t, loaded.brush_pieces[0], source.brush_pieces[0])
    testing.expect_value(t, loaded.brush_pieces[1], source.brush_pieces[1])
}

@(test)
settlement_program_scale_promotes_at_fixed_building_thresholds :: proc(t: ^testing.T) {
    testing.expect_value(t, settlement_program_scale_from_target(8), Settlement_Scale.Village)
    testing.expect_value(t, settlement_program_scale_from_target(23), Settlement_Scale.Village)
    testing.expect_value(t, settlement_program_scale_from_target(24), Settlement_Scale.Town)
    testing.expect_value(t, settlement_program_scale_from_target(69), Settlement_Scale.Town)
    testing.expect_value(t, settlement_program_scale_from_target(70), Settlement_Scale.City)
}

@(test)
settlement_brush_piece_compiles_domain_program_and_primary_route :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    plan: Settlement_Plan
    plan.request = {
        region = .Adriatic,
        scale  = .Village,
        seed   = 81,
        center = {0, 0},
        radius = 60,
    }
    piece := Settlement_Brush_Piece {
        shape    = .Rectangle,
        preset   = .Medium,
        center   = {0, 0},
        rotation = .35,
        density  = .58,
        hardness = .62,
        seed     = 81,
    }
    settlement_brush_assign_component(&plan, &piece)
    plan.brush_pieces[0] = piece
    plan.brush_piece_count = 1
    field: [terrain.CITY_DENSITY_SAMPLES]u8
    bounds := settlement_brush_apply_piece(&field, project, piece, SETTLEMENT_VILLAGE.max_slope)
    testing.expect(t, bounds.valid)
    nonzero := 0
    for value in field {
        if value > 0 do nonzero += 1
    }
    testing.expect(t, nonzero > 0)
    plan.program = settlement_program_compile(&plan, project, piece.component_id)
    testing.expect(t, plan.program.developable_area > 0)
    testing.expect(t, plan.program.ordinary.target >= plan.program.ordinary.minimum)
    initial_edges := project.road_graph.edge_count
    testing.expect(t, settlement_brush_ensure_primary_route(&plan, project, piece, 1))
    testing.expect_value(t, project.road_graph.edge_count, initial_edges + 1)
    testing.expect_value(t, plan.route_count, 1)
    testing.expect_value(t, plan.route_piece_ids[0], u32(1))
}

@(test)
settlement_rng_is_deterministic :: proc(t: ^testing.T) {
    a, b := settlement_rng_new(0x51a7), settlement_rng_new(0x51a7)
    for _ in 0 ..< 256 do testing.expect_value(t, settlement_rng_u32(&a), settlement_rng_u32(&b))
}

@(test)
settlement_patio_candidates_are_deterministic_and_clear_their_host :: proc(t: ^testing.T) {
    site := Settlement_Site {
        structure = terrain.Structure{id = 77, center_x = 10, center_z = 20, width = 8, depth = 6, rotation = 0},
        kind = .Ordinary,
        accepted = true,
        purpose = .Inn_Shop,
    }
    first := settlement_patio_candidate(site, 0, 7, 5, 0x70617469, .Adriatic)
    repeated := settlement_patio_candidate(site, 0, 7, 5, 0x70617469, .Adriatic)
    testing.expect_value(t, first, repeated)
    testing.expect_value(t, first.host_id, u64(77))
    testing.expect(
        t,
        settlement_oriented_rectangles_clear(
            site.structure.center_x,
            site.structure.center_z,
            site.structure.width,
            site.structure.depth,
            site.structure.rotation,
            first.center[0],
            first.center[1],
            first.width,
            first.depth,
            first.rotation,
            1,
        ),
    )

    side := settlement_patio_candidate(site, 2, 7, 5, 0x70617469, .Adriatic)
    testing.expect_value(t, side.width, f32(5))
    testing.expect_value(t, side.depth, f32(7))
    testing.expect(t, side.center[0] < site.structure.center_x)
}

@(test)
settlement_lane_frontage_uses_rotated_edges_on_both_sides :: proc(t: ^testing.T) {
    rotation := f32(math.PI * .25)
    tangent := [2]f32{f32(math.cos(f64(rotation))), f32(math.sin(f64(rotation)))}
    normal := [2]f32{-tangent[1], tangent[0]}
    lane_origin := [2]f32{4, -3}

    first := terrain.structure_make(0, 0, 8, 10, 0, 6)
    first.width, first.depth, first.height = 8, 10, 6
    first.rotation = rotation
    first_front := settlement_access_structure_edge(first, 0)
    lane_origin = first_front.midpoint + first_front.outward * 2.4
    first_edge, first_setback, first_found := settlement_access_structure_edge_facing_lane(
        first,
        lane_origin,
        tangent,
        1,
        6,
    )
    testing.expect(t, first_found)
    testing.expect_value(t, first_edge.edge_index, 0)
    testing.expect(t, math.abs(first_setback - 2.4) < .001)

    // A building across the same lane faces it with the opposite rotated edge.
    second := first
    second.center_x = lane_origin[0] + normal[0] * 6.4
    second.center_z = lane_origin[1] + normal[1] * 6.4
    second.rotation += math.PI
    second_edge, second_setback, second_found := settlement_access_structure_edge_facing_lane(
        second,
        lane_origin,
        tangent,
        1,
        6,
    )
    testing.expect(t, second_found)
    testing.expect_value(t, second_edge.edge_index, 0)
    testing.expect(t, second_setback >= 1 && second_setback <= 6)

    _, _, perpendicular_found := settlement_access_structure_edge_facing_lane(first, lane_origin, normal, 1, 6)
    testing.expect(t, !perpendicular_found)
}

@(test)
settlement_access_doors_cover_all_rotated_rectangle_edges_without_moving_footprint :: proc(t: ^testing.T) {
    structure := terrain.structure_make(10, 20, 8, 16, 0, 6)
    structure.width, structure.depth = 8, 16
    structure.rotation = math.PI * .25
    original_rotation, original_width, original_depth := structure.rotation, structure.width, structure.depth
    sides := [4]terrain.Entrance_Side{.Front, .Right, .Rear, .Left}
    for side, edge_index in sides {
        structure.entrance_side = side
        edge := settlement_access_structure_edge(structure, edge_index)
        door := settlement_structure_front_door_point(structure)
        offset := door - edge.midpoint
        testing.expect(t, math.abs(linalg.dot(offset, edge.tangent)) < .001)
        testing.expect(t, linalg.dot(linalg.normalize0(offset), edge.outward) > .999)
        testing.expect(t, math.abs(linalg.length(offset) - .22) < .001)
    }
    testing.expect_value(t, structure.rotation, original_rotation)
    testing.expect_value(t, structure.width, original_width)
    testing.expect_value(t, structure.depth, original_depth)
}

@(test)
settlement_lamp_sampling_has_bounded_segment_cells :: proc(t: ^testing.T) {
    testing.expect_value(t, settlement_lamp_sample_count(16, 25), 0)
    testing.expect_value(t, settlement_lamp_sample_count(16.25, 25), 1)
    testing.expect_value(t, settlement_lamp_sample_count(25, 25), 1)
    testing.expect_value(t, settlement_lamp_sample_count(49, 25), 2)
    testing.expect_value(t, settlement_lamp_sample_count(50, 25), 2)
    testing.expect_value(t, settlement_lamp_sample_count(74, 25), 3)
}

@(test)
settlement_route_lighting_uses_pedestrian_scale_cadence :: proc(t: ^testing.T) {
    testing.expect_value(t, settlement_route_lamp_spacing(.Town, .Civic_Spine), f32(18))
    testing.expect_value(t, settlement_route_lamp_spacing(.Town, .Street), f32(22))
    testing.expect_value(t, settlement_route_lamp_spacing(.Town, .Waterfront), f32(22))
    testing.expect_value(t, settlement_route_lamp_spacing(.City, .Civic_Spine), f32(20))
    testing.expect_value(t, settlement_route_lamp_spacing(.City, .Street), f32(26))
    testing.expect_value(t, settlement_lamp_sample_count(49, settlement_route_lamp_spacing(.Town, .Street)), 3)
}

@(test)
settlement_municipal_lighting_badness_rejects_crowded_lamps :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(&city.lamps, architecture.City_Lamp{x = 0, z = 0})
    city.lamp_count = 1

    testing.expect_value(t, settlement_municipal_lighting_badness(&city, 0, 0), f32(1))
    testing.expect(t, settlement_municipal_lighting_badness(&city, 8, 0) > 0)
    testing.expect_value(
        t,
        settlement_municipal_lighting_badness(&city, SETTLEMENT_MUNICIPAL_LIGHT_MIN_SPACING, 0),
        f32(0),
    )
    testing.expect(t, !settlement_lamp_position_clear(&city, 15.99, 0))
    testing.expect(t, settlement_lamp_position_clear(&city, SETTLEMENT_MUNICIPAL_LIGHT_MIN_SPACING, 0))
}

settlement_shared_pedestrian_trunks_receive_sparse_lighting :: proc(t: ^testing.T) {
    plan := Settlement_Plan {
        request = {scale = .Town},
    }
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(
        &city.alleys,
        architecture.City_Alley {
            start_x = 0,
            start_z = 0,
            end_x = 40,
            end_z = 0,
            half_width = .5,
            household_demand = 4,
        },
    )
    city.alley_count = 1

    settlement_plan_generate_lamps(&plan, &city)
    testing.expect_value(t, city.lamp_count, 2)
    for lamp in city.lamps[:city.lamp_count] {
        testing.expect(t, math.abs(math.abs(lamp.z) - 1.05) < .001)
        testing.expect(t, !settlement_access_point_on_alley_surface(&city, {lamp.x, lamp.z}, .25))
    }
}

@(test)
settlement_access_surface_palette_tracks_route_hierarchy :: proc(t: ^testing.T) {
    private: architecture.City_Alley
    shared := private
    shared.household_demand = 2
    communal := private
    communal.household_demand = 4

    earth := world_architecture_alley_color(private, false, false)
    gravel := world_architecture_alley_color(shared, false, false)
    stone := world_architecture_alley_color(communal, false, false)
    stair := world_architecture_alley_color(private, false, true)
    testing.expect(t, earth != gravel)
    testing.expect(t, gravel != stone)
    testing.expect(t, stair != earth)
    testing.expect_value(t, world_architecture_alley_color(communal, true, false).a, u8(150))
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
settlement_village_reserves_lane_before_house_frontages :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    project.sea_level = -100
    project.road_graph = {}
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    plan := Settlement_Plan {
        request = {region = .Adriatic, scale = .Village, seed = 41, center = {center, center}, radius = 100},
        neighborhood_count = 1,
    }
    plan.neighborhoods[0] = {
        center      = {center, center + 10},
        radius      = 22,
        density     = .41,
        suitability = 1,
        tissue      = .Dalmatian_Planned,
    }
    plan.routes[0].geometry.points[0] = {center - 90, center}
    plan.routes[0].geometry.points[1] = {center + 90, center}
    plan.routes[0].geometry.count = 2
    plan.routes[0].class = .Street
    plan.routes[0].width = 3.5
    plan.routes[0].shoulder = .8
    plan.routes[0].drivable = true
    plan.route_count = 1

    rng := settlement_rng_new(41)
    city := settlement_plan_generate_village_buildings(&plan, project, &rng)
    defer architecture.city_plan_destroy(&city)

    lane_index := -1
    court_surface_count := 0
    workyard_surface_count := 0
    for alley, alley_index in city.alleys[:city.alley_count] {
        if alley.half_width >= 2.39 {
            court_surface_count += 1
        }
        if alley.half_width >= 2.19 do workyard_surface_count += 1
        if lane_index < 0 && alley.start_terminal == .Road && alley.half_width >= .9 {
            lane_index = alley_index
        }
    }
    testing.expect(t, lane_index >= 0)
    testing.expect(t, court_surface_count >= 1)
    testing.expect(t, workyard_surface_count >= 2)
    if lane_index < 0 do return
    lane := city.alleys[lane_index]
    lane_start := [2]f32{lane.start_x, lane.start_z}
    lane_tangent := [2]f32{lane.end_x - lane.start_x, lane.end_z - lane.start_z}
    lane_direction := linalg.normalize(lane_tangent)
    lane_length := f32(0)
    for segment in city.alleys[:city.alley_count] {
        segment_delta := [2]f32{segment.end_x - segment.start_x, segment.end_z - segment.start_z}
        segment_length := linalg.length(segment_delta)
        if segment.half_width < .9 ||
           segment_length <= .001 ||
           math.abs(linalg.dot(segment_delta / segment_length, lane_direction)) < .99 {
            continue
        }
        lane_length += segment_length
    }
    testing.expect(t, lane_length >= 61)
    frontage_count := 0
    lane_plot_count := 0
    public_frontage_plot_count := 0
    for structure, structure_index in city.structures[:city.count] {
        parcel := city.parcels[structure_index]
        if parcel.depth >= structure.depth + 3.5 && parcel.frontage_width >= structure.width + 2 {
            public_frontage_plot_count += 1
        }
        _, _, found := settlement_access_structure_edge_facing_lane(structure, lane_start, lane_tangent, 1, 3)
        if !found do continue
        frontage_count += 1
        if parcel.depth >= structure.depth + 3.5 && parcel.frontage_width >= structure.width + 2 {
            lane_plot_count += 1
        }
    }
    testing.expect(t, frontage_count >= 6)
    testing.expect(t, lane_plot_count >= 6)
    testing.expect(t, public_frontage_plot_count >= 8)
    direct_court_thresholds := 0
    for structure, structure_index in city.structures[:city.count] {
        parcel := city.parcels[structure_index]
        if parcel.depth < structure.depth + 3.5 || parcel.frontage_width < structure.width + 2 do continue
        door := settlement_structure_front_door_point(structure)
        front := settlement_structure_entrance_outward(structure)
        for threshold in city.alleys[:city.alley_count] {
            threshold_start := [2]f32{threshold.start_x, threshold.start_z}
            threshold_end := [2]f32{threshold.end_x, threshold.end_z}
            direction: [2]f32
            public_endpoint: [2]f32
            if threshold.start_terminal == .Door && settlement_alley_point_near(door, threshold_start) {
                direction, public_endpoint = threshold_end - door, threshold_end
            } else if threshold.end_terminal == .Door && settlement_alley_point_near(door, threshold_end) {
                direction, public_endpoint = threshold_start - door, threshold_start
            } else {
                continue
            }
            length := linalg.length(direction)
            if length <= .001 || length >= 5 || linalg.dot(direction / length, front) < .966 do continue
            on_court_surface := false
            for court in city.alleys[:city.alley_count] {
                if court.half_width < 2.39 do continue
                court_start := [2]f32{court.start_x, court.start_z}
                court_end := [2]f32{court.end_x, court.end_z}
                reach := court.half_width + .1
                if settlement_point_segment_distance_squared(public_endpoint, court_start, court_end) <=
                   reach * reach {
                    on_court_surface = true
                    break
                }
            }
            if !on_court_surface do continue
            direct_court_thresholds += 1
            break
        }
    }
    testing.expect(t, direct_court_thresholds >= 2)
}

@(test)
settlement_aegean_civic_buildings_face_their_route_on_sloped_ground :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    project.road_graph = {}
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    terrain.apply_stroke_with_hardness(project, .Raise, center + 35, center, 150, 12, 1, .22)
    plan := Settlement_Plan {
        request = {region = .Aegean, scale = .Village, seed = 27, center = {center, center}, radius = 100},
        neighborhood_count = 1,
    }
    plan.neighborhoods[0] = {
        center      = {center, center + 10},
        radius      = 22,
        density     = .41,
        suitability = 1,
        tissue      = .Cycladic_Accretion,
    }
    plan.routes[0].geometry.points[0] = {center - 90, center}
    plan.routes[0].geometry.points[1] = {center + 90, center}
    plan.routes[0].geometry.count = 2
    plan.routes[0].class = .Street
    plan.routes[0].width = 3.5
    plan.routes[0].shoulder = .8
    plan.routes[0].drivable = true
    plan.route_count = 1

    rng := settlement_rng_new(27)
    city := settlement_plan_generate_village_buildings(&plan, project, &rng)
    defer architecture.city_plan_destroy(&city)

    testing.expect(t, plan.access_connected_count >= city.count - 1)
    testing.expect(t, plan.access_max_degree <= 4)
    testing.expect_value(t, plan.access_shallow_junctions, 0)
    testing.expect_value(t, plan.access_hairpin_bends, 0)
    testing.expect_value(t, plan.access_crossings, 0)
    testing.expect_value(t, plan.access_unsplit_junctions, 0)
    testing.expect_value(t, plan.access_bad_door_approaches, 0)
    testing.expect_value(t, plan.access_bad_road_approaches, 0)
    testing.expect_value(t, plan.access_excessive_grades, 0)
    testing.expect(t, plan.access_max_shared_width_step <= .151)
    cluster_court_segments := 0
    road_rooted_cluster_access := false
    for alley in city.alleys[:city.alley_count] {
        if alley.half_width >= 1.59 && (alley.start_terminal == .Public_Space || alley.end_terminal == .Public_Space) {
            cluster_court_segments += 1
        }
        if alley.half_width >= .89 && (alley.start_terminal == .Road || alley.end_terminal == .Road) {
            road_rooted_cluster_access = true
        }
    }
    testing.expect(t, cluster_court_segments >= 3)
    testing.expect(t, road_rooted_cluster_access)
    civic_count := 0
    for structure, structure_index in city.structures[:city.count] {
        purpose := plan.ordinary_purposes[structure_index]
        if purpose != .Inn_Shop && purpose != .Workshop do continue
        door := settlement_structure_front_door_point(structure)
        route_origin, _, _, _, _, _, _, found := settlement_nearest_route_frame(&plan, door)
        testing.expect(t, found)
        if !found do continue
        toward_route := route_origin - [2]f32{structure.center_x, structure.center_z}
        door_direction := door - [2]f32{structure.center_x, structure.center_z}
        testing.expect(t, linalg.dot(linalg.normalize0(toward_route), linalg.normalize0(door_direction)) > .8)
        civic_count += 1
    }
    testing.expect_value(t, civic_count, 2)
}

@(test)
settlement_aegean_cluster_courts_preserve_program_and_topology :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    project.road_graph = {}
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    regression_seeds := [2]u32{0, 50}
    for seed in regression_seeds {
        plan := Settlement_Plan {
            request = {region = .Aegean, scale = .Village, seed = seed, center = {center, center}, radius = 100},
            neighborhood_count = 3,
        }
        for neighborhood_index in 0 ..< plan.neighborhood_count {
            plan.neighborhoods[neighborhood_index] = {
                center      = {center + f32(neighborhood_index - 1) * 58, center + 10},
                radius      = 22,
                density     = .45,
                suitability = 1,
                tissue      = .Cycladic_Accretion,
            }
        }
        plan.routes[0].geometry.points[0], plan.routes[0].geometry.points[1] =
            {center - 90, center}, {center + 90, center}
        plan.routes[0].geometry.count = 2
        plan.routes[0].class = .Street
        plan.routes[0].width = 3.5
        plan.routes[0].shoulder = .8
        plan.routes[0].drivable = true
        plan.route_count = 1
        rng := settlement_rng_new(
            seed ~ u32(Settlement_Region.Aegean) * 0x9e37 ~ u32(Settlement_Scale.Village) * 0x85eb,
        )
        city := settlement_plan_generate_village_buildings(&plan, project, &rng)
        expected_program: [24]Settlement_Building_Purpose
        expected_count := settlement_village_program(plan.village_reason, seed, &expected_program)
        testing.expect_value(t, city.count, expected_count)
        testing.expect_value(t, plan.ordinary_purpose_count, expected_count)
        testing.expect(t, plan.access_connected_count >= city.count - 2)
        testing.expect(t, plan.access_max_degree <= 4)
        testing.expect_value(t, plan.access_shallow_junctions, 0)
        testing.expect_value(t, plan.access_hairpin_bends, 0)
        architecture.city_plan_destroy(&city)
    }
}

@(test)
settlement_hillside_lane_follows_contour_behind_road_throat :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    plan := Settlement_Plan {
        request = {region = .Adriatic, scale = .Village, seed = 19, center = {center, center}, radius = 100},
    }
    lane: Settlement_Village_Frontage_Lane
    route_origin: [2]f32
    for row in -3 ..= 3 {
        for column in -3 ..= 3 {
            candidate := [2]f32{center + f32(column) * 18, center + f32(row) * 18}
            candidate_lane := settlement_village_frontage_lane(
                &plan,
                project,
                candidate,
                {1, 0},
                {0, 1},
                3.5,
                .8,
                .Contour_Terrace,
                true,
                true,
            )
            if !candidate_lane.valid do continue
            route_origin, lane = candidate, candidate_lane
            break
        }
        if lane.valid do break
    }
    testing.expect(t, lane.valid)
    if !lane.valid do return
    testing.expect(t, lane.connector_required)
    testing.expect(t, lane.contour_aligned)
    throat := linalg.normalize(lane.junction - lane.road_start)
    testing.expect(t, math.abs(linalg.dot(throat, [2]f32{0, 1})) > .99)

    sample := f32(10)
    gradient := [2]f32 {
        terrain.sample_height(project, 0, route_origin[0] + sample, route_origin[1]) -
        terrain.sample_height(project, 0, route_origin[0] - sample, route_origin[1]),
        terrain.sample_height(project, 0, route_origin[0], route_origin[1] + sample) -
        terrain.sample_height(project, 0, route_origin[0], route_origin[1] - sample),
    }
    if linalg.length(gradient) > .001 {
        testing.expect(t, math.abs(linalg.dot(linalg.normalize(gradient), lane.tangent)) < .36)
    }
    previous_height := terrain.sample_height(project, 0, lane.start[0], lane.start[1])
    maximum_grade := f32(0)
    for sample_index in 1 ..= 6 {
        point := lane.start + lane.tangent * (64 * f32(sample_index) / 6)
        height := terrain.sample_height(project, 0, point[0], point[1])
        maximum_grade = max(maximum_grade, math.abs(height - previous_height) / (64.0 / 6))
        previous_height = height
    }
    testing.expect(t, maximum_grade <= .1151)
}

@(test)
settlement_harbor_resources_receive_quay_frontage :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    project.road_graph = {}
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    plan := Settlement_Plan {
        request = {region = .Adriatic, scale = .Village, seed = 23, center = {center, center}, radius = 100},
        neighborhood_count = 1,
    }
    plan.neighborhoods[0] = {
        center      = {center, center + 10},
        radius      = 22,
        density     = .41,
        suitability = 1,
        tissue      = .Harbor,
    }
    plan.routes[0].geometry.points[0] = {center - 90, center}
    plan.routes[0].geometry.points[1] = {center + 90, center}
    plan.routes[0].geometry.count = 2
    plan.routes[0].class = .Waterfront
    plan.routes[0].width = 3.5
    plan.routes[0].shoulder = .8
    plan.routes[0].drivable = true
    plan.route_count = 1

    rng := settlement_rng_new(23)
    city := settlement_plan_generate_village_buildings(&plan, project, &rng)
    defer architecture.city_plan_destroy(&city)
    testing.expect_value(t, plan.village_reason, Village_Reason.Harbor_Fishery)

    resource_count, quay_plot_count := 0, 0
    for structure, structure_index in city.structures[:city.count] {
        purpose := plan.ordinary_purposes[structure_index]
        if purpose != .Fishery && purpose != .Storehouse do continue
        resource_count += 1
        parcel := city.parcels[structure_index]
        if parcel.depth >= structure.depth + 3.1 && parcel.frontage_width >= structure.width + 1.4 {
            quay_plot_count += 1
        }
    }
    testing.expect_value(t, resource_count, 4)
    testing.expect_value(t, quay_plot_count, 4)
    broad_quay_length := f32(0)
    for alley in city.alleys[:city.alley_count] {
        if alley.half_width < 1.59 do continue
        broad_quay_length += linalg.length([2]f32{alley.end_x - alley.start_x, alley.end_z - alley.start_z})
    }
    testing.expect(t, broad_quay_length >= 44)
    imported := plan
    settlement_plan_import_access_network(&imported, &city, project)
    waterfront_routes := 0
    for route in imported.routes[:imported.route_count] {
        if route.class == .Waterfront do waterfront_routes += 1
    }
    testing.expect(t, waterfront_routes >= 1)
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
                testing.expect_value(t, plan.access_required_count, city.count)
                if plan.access_connected_count != city.count {
                    fmt.println(
                        "settlement access connectivity failure",
                        region,
                        scale,
                        seed,
                        plan.access_connected_count,
                        city.count,
                    )
                    for structure, structure_index in city.structures[:city.count] {
                        door := settlement_structure_front_door_point(structure)
                        fmt.println(
                            "  door",
                            structure_index,
                            structure.entrance_side,
                            door,
                            "degree",
                            settlement_access_network_degree(&city, door),
                        )
                        for alley, alley_index in city.alleys[:city.alley_count] {
                            start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
                            if settlement_alley_point_near(door, start) || settlement_alley_point_near(door, finish) {
                                fmt.println(
                                    "    alley",
                                    alley_index,
                                    start,
                                    finish,
                                    alley.start_terminal,
                                    alley.end_terminal,
                                )
                            }
                        }
                    }
                }
                testing.expect_value(t, plan.access_connected_count, city.count)
                if plan.access_max_degree > 4 || plan.access_shallow_junctions > 0 || plan.access_hairpin_bends > 0 {
                    fmt.println(
                        "settlement access topology failure",
                        region,
                        scale,
                        seed,
                        plan.access_max_degree,
                        plan.access_shallow_junctions,
                        plan.access_hairpin_bends,
                    )
                }
                if plan.access_bad_door_approaches > 0 || plan.access_bad_road_approaches > 0 {
                    fmt.println(
                        "settlement access alignment failure",
                        region,
                        scale,
                        seed,
                        plan.access_bad_door_approaches,
                        plan.access_bad_road_approaches,
                    )
                }
                testing.expect(t, plan.access_max_degree <= 4)
                testing.expect_value(t, plan.access_shallow_junctions, 0)
                testing.expect_value(t, plan.access_hairpin_bends, 0)
                testing.expect_value(t, plan.access_crossings, 0)
                testing.expect_value(t, plan.access_unsplit_junctions, 0)
                testing.expect_value(t, plan.access_bad_door_approaches, 0)
                testing.expect_value(t, plan.access_bad_road_approaches, 0)
                testing.expect_value(t, plan.access_excessive_grades, 0)
                testing.expect(t, plan.access_widened_segments <= plan.access_shared_segments)
                testing.expect(t, plan.access_max_shared_width_step <= .151)
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
                    testing.expect(t, city.alley_count <= city.count * 4 + 3)
                    for alley in city.alleys[:city.alley_count] {
                        dx, dz := alley.end_x - alley.start_x, alley.end_z - alley.start_z
                        testing.expect(t, dx * dx + dz * dz <= 55 * 55)
                        testing.expect(t, alley.half_width * 2 >= .5)
                    }
                    imported := plan
                    settlement_plan_import_access_network(&imported, &city, project)
                    testing.expect(t, imported.route_count <= len(imported.routes))
                    for structure in city.structures[:city.count] {
                        door := settlement_structure_front_door_point(structure)
                        origin, _, _, route_width, route_shoulder, _, _, found := settlement_nearest_route_frame(
                            &plan,
                            door,
                        )
                        testing.expect(t, found)
                        direction := linalg.normalize0(door - origin)
                        road_edge := origin + direction * (route_width * .5 + route_shoulder + .45)
                        road_accessible := linalg.length(door - road_edge) < 1
                        accessible := road_accessible
                        for alley in city.alleys[:city.alley_count] {
                            start := [2]f32{alley.start_x, alley.start_z}
                            end := [2]f32{alley.end_x, alley.end_z}
                            reach := alley.half_width + .1
                            if settlement_point_segment_distance_squared(door, start, end) <= reach * reach {
                                accessible = true
                                break
                            }
                        }
                        testing.expect(t, accessible)
                        final_accessible := road_accessible
                        for route in imported.routes[:imported.route_count] {
                            if route.drivable do continue
                            reach := route.width * .5 + .1
                            for point_index in 0 ..< route.geometry.count - 1 {
                                if settlement_point_segment_distance_squared(
                                       door,
                                       route.geometry.points[point_index],
                                       route.geometry.points[point_index + 1],
                                   ) <=
                                   reach * reach {
                                    final_accessible = true
                                    break
                                }
                            }
                            if final_accessible do break
                        }
                        testing.expect(t, final_accessible)
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
                    maximum_dwelling_frontage_distance := f32(0)
                    frontage_count := 0
                    for structure, structure_index in city.structures[:city.count] {
                        purpose := plan.ordinary_purposes[structure_index]
                        if purpose == .Barn_Granary ||
                           purpose == .Storehouse ||
                           purpose == .Mill ||
                           purpose == .Fishery {
                            continue
                        }
                        frontage_point := settlement_structure_front_door_point(structure)
                        _, _, _, _, _, route_distance, _, route_found := settlement_nearest_route_frame(
                            &plan,
                            frontage_point,
                        )
                        testing.expect(t, route_found)
                        // A village building may front the authored domestic
                        // lane or court rather than the older through-road.
                        // Measure proximity to either public frontage, while
                        // door/network alignment is verified by the access
                        // acceptance metrics above.
                        frontage_distance := route_distance
                        for alley in city.alleys[:city.alley_count] {
                            if alley.half_width < .9 &&
                               alley.start_terminal != .Public_Space &&
                               alley.end_terminal != .Public_Space {
                                continue
                            }
                            lane_start := [2]f32{alley.start_x, alley.start_z}
                            lane_end := [2]f32{alley.end_x, alley.end_z}
                            frontage_distance = min(
                                frontage_distance,
                                f32(
                                    math.sqrt(
                                        f64(
                                            settlement_point_segment_distance_squared(
                                                frontage_point,
                                                lane_start,
                                                lane_end,
                                            ),
                                        ),
                                    ),
                                ),
                            )
                        }
                        frontage_distance_sum += frontage_distance
                        if purpose == .Dwelling {
                            maximum_dwelling_frontage_distance = max(
                                maximum_dwelling_frontage_distance,
                                frontage_distance,
                            )
                        }
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
                    // Adriatic row villages require close lane/road frontage.
                    // Cycladic court clusters permit one compact courtyard
                    // depth before reaching a broad shared route; their
                    // narrower intervening alleys are validated separately.
                    maximum_dwelling_frontage_limit := region == .Aegean ? f32(24) : f32(16)
                    testing.expect(t, maximum_dwelling_frontage_distance <= maximum_dwelling_frontage_limit)
                    village_anchor := plan.neighborhoods[0].center
                    for structure in city.structures[:city.count] {
                        dx := structure.center_x - village_anchor[0]
                        dz := structure.center_z - village_anchor[1]
                        distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
                        maximum_radius := region == .Aegean ? f32(58) : plan.request.radius - 4
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
                    frontage_low, frontage_high := f32(9), f32(28)
                    depth_low, depth_high := f32(4.5), f32(16)
                    if region == .Aegean {
                        frontage_low, frontage_high = 5.5, 16
                        depth_low, depth_high = 4, 11
                    } else if scale == .Village {
                        frontage_low, frontage_high = 6, 18
                        depth_low, depth_high = 4.5, 13
                    }
                    if scale == .Town {
                        frontage_low *= f32(1.41421356237)
                        frontage_high *= f32(1.41421356237)
                        depth_low *= f32(1.41421356237)
                        depth_high *= f32(1.41421356237)
                    }
                    minimum_height, maximum_height := settlement_height_band(region, scale)
                    testing.expect(t, structure.width >= frontage_low && structure.width <= frontage_high)
                    testing.expect(t, structure.depth >= depth_low && structure.depth <= depth_high)
                    testing.expect(t, structure.height >= minimum_height && structure.height <= maximum_height)
                    testing.expect(t, structure.width <= parcel.frontage_width + .001)
                    testing.expect(t, structure.depth <= parcel.depth + .001)
                    testing.expect(t, parcel.frontage_width >= parcel.depth)
                    frontage_sum += structure.width
                    depth_sum += structure.depth
                    height_sum += structure.height
                    sample_count += 1
                }
                architecture.city_plan_destroy(&city)
            }
            testing.expect(t, sample_count > 512)
            frontage_target, depth_target := f32(16), f32(8.5)
            if region == .Aegean {
                frontage_target, depth_target = 9, 6.5
            } else if scale == .Village {
                frontage_target, depth_target = 10.5, 7.5
            }
            if scale == .Town {
                frontage_target *= f32(1.41421356237)
                depth_target *= f32(1.41421356237)
            }
            // Ordinary façades are quantized to exact 4.8 m window-row
            // modules. Aegean fabric in this density matrix is predominantly
            // one storey; Adriatic villages mix one- and two-storey houses.
            height_target := f32(4.8)
            if region == .Adriatic {
                switch scale {
                case .City:
                    height_target = 13
                case .Town:
                    height_target = 10
                case .Village:
                    height_target = 5.7
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
    testing.expect_value(t, settlement_landmark_kind(.Adriatic, 3), Settlement_Landmark_Kind.Lighthouse)
    testing.expect_value(t, settlement_landmark_kind(.Aegean, 0), Settlement_Landmark_Kind.Cycladic_Bell)
    testing.expect_value(t, settlement_landmark_kind(.Aegean, 2), Settlement_Landmark_Kind.Lighthouse)
    testing.expect_value(t, settlement_landmark_kind(.Aegean, 3), Settlement_Landmark_Kind.Monastery)
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
    testing.expect(t, minimum == 4.5 && maximum == 12)
    minimum, maximum = settlement_height_band(.Adriatic, .Village)
    testing.expect(t, minimum == 4 && maximum == 11)
    for scale in Settlement_Scale {
        minimum, maximum = settlement_height_band(.Aegean, scale)
        testing.expect(t, minimum == 3.5 && maximum == 10)
    }
}

@(test)
settlement_town_profile_is_broader_and_lower_than_city :: proc(t: ^testing.T) {
    testing.expect(t, SETTLEMENT_TOWN.world_cell > SETTLEMENT_CITY.world_cell * .8)
    testing.expect(t, SETTLEMENT_TOWN.density_ceiling < SETTLEMENT_CITY.density_ceiling)
    testing.expect(t, SETTLEMENT_TOWN.density_ceiling <= .42)
    testing.expect(t, SETTLEMENT_VILLAGE.density_ceiling <= .32)
    testing.expect(t, SETTLEMENT_VILLAGE.density_ceiling < SETTLEMENT_TOWN.density_ceiling)
    _, town_maximum := settlement_height_band(.Adriatic, .Town)
    _, city_maximum := settlement_height_band(.Adriatic, .City)
    testing.expect(t, town_maximum < city_maximum * .6)
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
settlement_buildable_footprint_rejects_a_submerged_edge :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    center_x, center_z := terrain.default_island_center(-1)
    shoreline_x := center_x
    found := false
    // Walk from the west-island interior toward its exposed coast and retain
    // the final dry sample. The parcel center remains viable while its western
    // edge extends beyond the generated shoreline.
    for offset := f32(0); offset <= 1500; offset += 4 {
        candidate_x := center_x - offset
        if terrain.sample_height(project, 0, candidate_x, center_z) <= project.sea_level + .6 {
            found = true
            break
        }
        shoreline_x = candidate_x
    }
    testing.expect(t, found)
    testing.expect(t, terrain.sample_height(project, 0, shoreline_x, center_z) > project.sea_level + .6)
    testing.expect(t, !settlement_structure_footprint_on_land(project, shoreline_x, center_z, 16, 8, 0))
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
settlement_imported_pedestrian_geometry_follows_finished_spline :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    plan: Settlement_Plan
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(
        &city.alleys,
        architecture.City_Alley {
            start_x = 0,
            start_z = 0,
            end_x = 12,
            end_z = 0,
            half_width = .6,
            curve_control_from = {3, 5},
            curve_control_to = {9, 5},
            curve_ready = true,
            start_terminal = .Door,
            end_terminal = .Road,
        },
    )
    city.alley_count = 1

    settlement_plan_import_access_network(&plan, &city, project)

    testing.expect_value(t, plan.route_count, 1)
    route := plan.routes[0]
    testing.expect(t, route.geometry.count > 2)
    testing.expect(t, route.geometry.count <= SETTLEMENT_ROUTE_CAPACITY)
    maximum_offset := f32(0)
    for point in route.geometry.points[:route.geometry.count] {
        maximum_offset = max(maximum_offset, math.abs(point[1]))
        testing.expect(t, settlement_access_point_on_alley_surface(&city, point, .05))
    }
    for point_index in 0 ..< route.geometry.count - 1 {
        start, finish := route.geometry.points[point_index], route.geometry.points[point_index + 1]
        for sample in 1 ..< 4 {
            point := start + (finish - start) * (f32(sample) / 4)
            testing.expect(t, settlement_access_point_on_alley_surface(&city, point, .05))
        }
    }
    testing.expect(t, maximum_offset > 2)
    testing.expect(t, settlement_route_point_near(route.geometry.points[0], {0, 0}))
    testing.expect(t, settlement_route_point_near(route.geometry.points[route.geometry.count - 1], {12, 0}))
}

@(test)
settlement_imported_spline_sampling_preserves_chain_junctions_at_capacity :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    plan: Settlement_Plan
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    for index in 0 ..< 6 {
        start, finish := [2]f32{f32(index * 4), 0}, [2]f32{f32((index + 1) * 4), 0}
        bow := index & 1 == 0 ? f32(1.5) : f32(-1.5)
        append(
            &city.alleys,
            architecture.City_Alley {
                start_x = start[0],
                start_z = start[1],
                end_x = finish[0],
                end_z = finish[1],
                half_width = .5,
                curve_control_from = start + [2]f32{1, bow},
                curve_control_to = finish + [2]f32{-1, bow},
                curve_ready = true,
            },
        )
    }
    city.alley_count = 6

    settlement_plan_import_access_network(&plan, &city, project)

    testing.expect_value(t, plan.route_count, 2)
    for route in plan.routes[:plan.route_count] {
        testing.expect(t, route.geometry.count <= SETTLEMENT_ROUTE_CAPACITY)
        for point_index in 0 ..< route.geometry.count - 1 {
            start, finish := route.geometry.points[point_index], route.geometry.points[point_index + 1]
            for sample in 1 ..< 4 {
                point := start + (finish - start) * (f32(sample) / 4)
                testing.expect(t, settlement_access_point_on_alley_surface(&city, point, .05))
            }
        }
    }
    for junction_index in 0 ..= 6 {
        junction := [2]f32{f32(junction_index * 4), 0}
        preserved := false
        for route in plan.routes[:plan.route_count] {
            geometry := route.geometry
            for point in geometry.points[:geometry.count] {
                if settlement_route_point_near(point, junction) {
                    preserved = true
                    break
                }
            }
            if preserved do break
        }
        testing.expect(t, preserved)
    }
}

@(test)
settlement_import_compacts_access_segments_between_junctions :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    plan: Settlement_Plan
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    for index in 0 ..< 4 {
        append(
            &city.alleys,
            architecture.City_Alley{start_x = f32(index * 5), end_x = f32((index + 1) * 5), half_width = .4},
        )
    }
    city.alley_count = 4
    settlement_plan_import_access_network(&plan, &city, project)
    testing.expect_value(t, plan.route_count, 1)
    testing.expect_value(t, plan.routes[0].geometry.count, 5)
    testing.expect(t, settlement_route_point_near(plan.routes[0].geometry.points[0], {0, 0}))
    testing.expect(t, settlement_route_point_near(plan.routes[0].geometry.points[4], {20, 0}))
}

@(test)
settlement_metrics_measure_drivable_dead_ends_against_occupied_frontage :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.routes[0].geometry.points[0] = {0, 0}
    plan.routes[0].geometry.points[1] = {20, 0}
    plan.routes[0].geometry.count = 2
    plan.routes[0].class = .Street
    plan.routes[0].drivable = true
    plan.route_count = 1
    structure := terrain.structure_make(2, 5, 4, 4, 0, 7)
    structure.width, structure.depth = 4, 4
    plan.sites[0] = {
        structure = structure,
        kind      = .Ordinary,
        accepted  = true,
    }
    plan.site_count = 1

    settlement_plan_measure(&plan)

    testing.expect_value(t, plan.metrics.dead_end_frontage.count, 2)
    testing.expect(t, math.abs(plan.metrics.dead_end_frontage.min - 3) < .01)
    testing.expect(t, plan.metrics.dead_end_frontage.max > 16)
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
settlement_foliage_avoids_road_shoulders_and_favors_open_ground :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    from := roads.add_node(&project.road_graph, {-20, 0, 0}, 3)
    to := roads.add_node(&project.road_graph, {20, 0, 0}, 3)
    _ = roads.add_edge(&project.road_graph, from, to, {-8, 0, 0}, {8, 0, 0}, 3, 2, .Dirt)
    testing.expect(t, !settlement_park_site_clear(project, 0, 0, 6, 6))
    testing.expect(t, !settlement_park_site_clear(project, 0, 7, 6, 6))
    testing.expect(t, settlement_park_site_clear(project, 0, 14, 6, 6))
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
settlement_pedestrian_access_respects_oriented_building_footprints :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    structure := terrain.structure_make(0, 0, 4, 24, 0, 7)
    structure.rotation = f32(math.PI * .25)
    append(&city.structures, structure)
    city.count = 1
    // This crosses the long end of the rotated footprint, well beyond the
    // small circular proxy previously used for pedestrian clearance.
    testing.expect(t, !settlement_pedestrian_segment_clear(&city, {-12, 12}, {12, -12}))
    testing.expect(t, settlement_pedestrian_segment_clear(&city, {0, 15}, {15, 0}))
}

@(test)
settlement_building_placement_reserves_existing_route_corridors :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.routes[0].geometry.points[0] = {-30, 0}
    plan.routes[0].geometry.points[1] = {30, 0}
    plan.routes[0].geometry.count = 2
    plan.routes[0].width = 4
    plan.routes[0].shoulder = 1
    plan.route_count = 1

    crossing := terrain.structure_make(0, 0, 8, 10, 0, 7)
    testing.expect(t, !settlement_structure_routes_clear(&plan, crossing))

    frontage := crossing
    frontage.center_z = 20
    testing.expect(t, settlement_structure_routes_clear(&plan, frontage))

    frontage.rotation = math.PI * .5
    frontage.center_z = 7
    testing.expect(t, !settlement_structure_routes_clear(&plan, frontage))
}

@(test)
settlement_building_approach_points_stop_outside_oriented_facades :: proc(t: ^testing.T) {
    structure := terrain.structure_make(10, 20, 8, 16, 0, 7)
    structure.rotation = f32(math.PI * .5)
    approach := settlement_structure_approach_point(structure, {30, 20})
    testing.expect(t, math.abs(approach[0] - 18.85) < .01)
    testing.expect(t, math.abs(approach[1] - 20) < .01)
    testing.expect(t, !settlement_segment_intersects_structure_clearance({30, 20}, approach, structure, .8))
}

@(test)
settlement_building_access_connects_setback_facades_to_roads :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.request.scale = .Village
    plan.routes[0].geometry.points[0] = {-30, 0}
    plan.routes[0].geometry.points[1] = {30, 0}
    plan.routes[0].geometry.count = 2
    plan.routes[0].width = 4
    plan.routes[0].shoulder = .8
    plan.routes[0].drivable = true
    plan.route_count = 1
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    structure := terrain.structure_make(0, 14, 8, 8, 0, 7)
    structure.rotation = math.PI
    append(&city.structures, structure)
    city.count = 1
    rng := settlement_rng_new(31)
    connected := settlement_plan_generate_building_access(&plan, project, &city, &rng, 28)
    testing.expect_value(t, connected, 1)
    testing.expect_value(t, city.alley_count, 3)
    door := settlement_structure_front_door_point(city.structures[0])
    testing.expect(t, linalg.length([2]f32{city.alleys[0].start_x, city.alleys[0].start_z} - door) < .01)
    front := settlement_structure_entrance_outward(city.structures[0])
    doorstep_direction :=
        [2]f32{city.alleys[0].end_x, city.alleys[0].end_z} - [2]f32{city.alleys[0].start_x, city.alleys[0].start_z}
    testing.expect(t, linalg.dot(linalg.normalize0(doorstep_direction), front) > .999)
    road_endpoint_found := false
    for alley in city.alleys[:city.alley_count] {
        if math.abs(alley.start_z - 3.25) < .01 || math.abs(alley.end_z - 3.25) < .01 {
            road_endpoint_found = true
            break
        }
    }
    testing.expect(t, road_endpoint_found)
    testing.expect_value(t, plan.access_bad_door_approaches, 0)
    testing.expect_value(t, plan.access_bad_road_approaches, 0)
    testing.expect(
        t,
        settlement_access_segment_clear(
            &city,
            {city.alleys[0].start_x, city.alleys[0].start_z},
            {city.alleys[0].end_x, city.alleys[0].end_z},
            city.alleys[0].half_width,
            0,
        ),
    )
}

@(test)
settlement_building_access_selects_side_facade_without_rotating_footprint :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.request.scale = .Village
    plan.routes[0].geometry.points[0], plan.routes[0].geometry.points[1] = {0, -30}, {0, 30}
    plan.routes[0].geometry.count = 2
    plan.routes[0].width = 4
    plan.routes[0].shoulder = .8
    plan.routes[0].drivable = true
    plan.route_count = 1
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    structure := terrain.structure_make(14, 0, 8, 16, 0, 7)
    structure.width, structure.depth = 8, 16
    append(&city.structures, structure)
    city.count = 1
    rng := settlement_rng_new(37)
    connected := settlement_plan_generate_building_access(&plan, project, &city, &rng, 28)
    testing.expect_value(t, connected, 1)
    testing.expect_value(t, city.structures[0].entrance_side, terrain.Entrance_Side.Left)
    testing.expect_value(t, city.structures[0].rotation, structure.rotation)
    testing.expect_value(t, city.structures[0].width, structure.width)
    testing.expect_value(t, city.structures[0].depth, structure.depth)
    door := settlement_structure_front_door_point(city.structures[0])
    found_threshold := false
    for alley in city.alleys[:city.alley_count] {
        start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
        direction: [2]f32
        if alley.start_terminal == .Door && settlement_alley_point_near(start, door) {
            direction = linalg.normalize0(finish - start)
        } else if alley.end_terminal == .Door && settlement_alley_point_near(finish, door) {
            direction = linalg.normalize0(start - finish)
        } else {
            continue
        }
        testing.expect(t, linalg.dot(direction, settlement_structure_entrance_outward(city.structures[0])) > .999)
        found_threshold = true
        break
    }
    testing.expect(t, found_threshold)
}

@(test)
settlement_deep_households_establish_a_shared_side_lane :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.request.scale = .Village
    plan.routes[0].geometry.points[0], plan.routes[0].geometry.points[1] = {-40, 0}, {40, 0}
    plan.routes[0].geometry.count = 2
    plan.routes[0].width = 4
    plan.routes[0].shoulder = .8
    plan.routes[0].drivable = true
    plan.route_count = 1

    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    // Storage order is intentionally road-to-back. Access construction must
    // reverse that development pressure so the rear household establishes a
    // side lane and the foreground households join it.
    building_depths := [4]f32{12, 22, 32, 42}
    for z in building_depths {
        structure := terrain.structure_make(0, z, 6, 6, 0, 6)
        structure.width, structure.depth = 6, 6
        structure.rotation = math.PI
        append(&city.structures, structure)
    }
    city.count = 4

    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    rng := settlement_rng_new(731)
    connected := settlement_plan_generate_building_access(&plan, project, &city, &rng, 60)

    testing.expect_value(t, connected, 4)
    testing.expect_value(t, plan.access_connected_count, 4)
    shared_side_lane := false
    for alley in city.alleys[:city.alley_count] {
        if alley.household_demand < 3 do continue
        midpoint_x := (alley.start_x + alley.end_x) * .5
        if math.abs(midpoint_x) <= 3.5 do continue
        testing.expect(t, alley.half_width >= .899)
        shared_side_lane = true
    }
    testing.expect(t, shared_side_lane)
}

@(test)
settlement_town_access_repairs_seed_regressions :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    cases := [3]struct {
        region: Settlement_Region,
        seed:   u32,
    }{{.Adriatic, 15}, {.Aegean, 27}, {.Aegean, 51}}
    for regression in cases {
        plan: Settlement_Plan
        plan.request = {
            region = regression.region,
            scale  = .Town,
            seed   = regression.seed,
            center = {center, center},
            radius = 100,
        }
        plan.routes[0].geometry.points[0], plan.routes[0].geometry.points[1] =
            {center - 90, center}, {center + 90, center}
        plan.routes[0].geometry.count = 2
        plan.routes[0].class = .Street
        plan.routes[0].width = 3.5
        plan.routes[0].shoulder = .8
        plan.routes[0].drivable = true
        plan.route_count = 1
        density := regression.region == .Adriatic ? f32(.50) : f32(.45)
        for index in 0 ..< 16 {
            column, row := index % 4, index / 4
            plan.macro_cells[index] = {
                center      = {center + (f32(column) - 1.5) * 18, center + (f32(row) - 1.5) * 18},
                radius      = 12,
                density     = density,
                age         = f32(index % 4) * .12,
                suitability = 1,
                tissue      = regression.region == .Aegean ? .Cycladic_Accretion : .Dalmatian_Planned,
            }
        }
        plan.macro_cell_count = 16
        rng := settlement_rng_new(
            regression.seed ~ u32(regression.region) * 0x9e37 ~ u32(Settlement_Scale.Town) * 0x85eb,
        )
        city := settlement_plan_generate_buildings(&plan, project, &rng)
        defer architecture.city_plan_destroy(&city)
        testing.expect_value(t, plan.access_connected_count, city.count)
    }
}

@(test)
settlement_access_widths_follow_settlement_scale_when_space_allows :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    expected_half_widths := [3]f32{.7, .6, .5}
    for scale in Settlement_Scale {
        plan: Settlement_Plan
        plan.request.scale = scale
        plan.routes[0].geometry.points[0] = {-30, 0}
        plan.routes[0].geometry.points[1] = {30, 0}
        plan.routes[0].geometry.count = 2
        plan.routes[0].width = 4
        plan.routes[0].shoulder = .8
        plan.routes[0].drivable = true
        plan.route_count = 1
        city: architecture.City_Plan
        structure := terrain.structure_make(0, 14, 8, 8, 0, 7)
        structure.rotation = math.PI
        append(&city.structures, structure)
        city.count = 1
        rng := settlement_rng_new(91)

        connected := settlement_plan_generate_building_access(&plan, project, &city, &rng, 28)

        testing.expect_value(t, connected, 1)
        testing.expect_value(t, city.alley_count, 3)
        for alley in city.alleys[:city.alley_count] {
            testing.expect(t, math.abs(alley.half_width - expected_half_widths[int(scale)]) < .001)
        }
        architecture.city_plan_destroy(&city)
    }
}

@(test)
settlement_access_widths_reflect_building_use_when_space_allows :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    purposes := [3]Settlement_Building_Purpose{.Dwelling, .Inn_Shop, .Barn_Granary}
    expected_half_widths := [3]f32{.5, .8, .9}
    for purpose, purpose_index in purposes {
        plan: Settlement_Plan
        plan.request.scale = .Village
        plan.routes[0].geometry.points[0] = {-30, 0}
        plan.routes[0].geometry.points[1] = {30, 0}
        plan.routes[0].geometry.count = 2
        plan.routes[0].width = 4
        plan.routes[0].shoulder = .8
        plan.routes[0].drivable = true
        plan.route_count = 1
        plan.ordinary_purposes[0] = purpose
        plan.ordinary_purpose_count = 1
        city: architecture.City_Plan
        structure := terrain.structure_make(0, 14, 8, 8, 0, 7)
        structure.rotation = math.PI
        append(&city.structures, structure)
        city.count = 1
        rng := settlement_rng_new(117 + u32(purpose_index))

        connected := settlement_plan_generate_building_access(&plan, project, &city, &rng, 28)

        testing.expect_value(t, connected, 1)
        testing.expect(t, city.alley_count >= 1)
        for alley in city.alleys[:city.alley_count] {
            testing.expect(t, math.abs(alley.half_width - expected_half_widths[purpose_index]) < .001)
        }
        architecture.city_plan_destroy(&city)
    }
}

@(test)
settlement_service_widths_require_workable_grades :: proc(t: ^testing.T) {
    testing.expect(t, settlement_access_grade_allows_preferred_width(.Barn_Granary, .10))
    testing.expect(t, !settlement_access_grade_allows_preferred_width(.Barn_Granary, .101))
    testing.expect(t, settlement_access_grade_allows_preferred_width(.Farmstead, SETTLEMENT_ACCESS_STAIR_GRADE - .001))
    testing.expect(t, !settlement_access_grade_allows_preferred_width(.Farmstead, SETTLEMENT_ACCESS_STAIR_GRADE))
    // Public and domestic approaches may legitimately be broad stepped paths.
    testing.expect(t, settlement_access_grade_allows_preferred_width(.Inn_Shop, .25))
    testing.expect(t, settlement_access_grade_allows_preferred_width(.Dwelling, .25))
    testing.expect_value(t, settlement_access_direct_grade_limit(.Storehouse), f32(.10))
    testing.expect_value(t, settlement_access_direct_grade_limit(.Farmstead), SETTLEMENT_ACCESS_STAIR_GRADE)
    testing.expect_value(t, settlement_access_direct_grade_limit(.Dwelling), SETTLEMENT_ACCESS_SEVERE_GRADE)
    short_steep := settlement_access_candidate_score(10, .16, .10, false)
    gentle_detour := settlement_access_candidate_score(14, .04, .10, false)
    testing.expect(t, gentle_detour < short_steep)
    testing.expect(
        t,
        settlement_access_candidate_score(12, .04, .10, true) < settlement_access_candidate_score(12, .04, .10, false),
    )
    testing.expect(
        t,
        settlement_access_candidate_score(16, .04, .10, true) < settlement_access_candidate_score(12, .04, .10, false),
    )
}

@(test)
settlement_route_commit_fits_continuous_curve_controls :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    project.sea_level = -100
    route: Settlement_Route
    route.points[0], route.points[1], route.points[2], route.count = {0, 0}, {8, 0}, {12, 8}, 3
    settlement_route_commit(project, route, 3, .5, .Dirt)
    testing.expect_value(t, project.road_graph.edge_count, 2)
    first := project.road_graph.edges[0]
    first_start := project.road_graph.nodes[first.from].position
    first_finish := project.road_graph.nodes[first.to].position
    chord := [2]f32{first_finish.x - first_start.x, first_finish.z - first_start.z}
    control := [2]f32{first.control_to.x - first_start.x, first.control_to.z - first_start.z}
    cross := chord[0] * control[1] - chord[1] * control[0]
    testing.expect(t, math.abs(cross) > .01)
}

@(test)
settlement_steep_resource_access_remains_a_footpath :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    project.sea_level = -100
    level := &project.levels[0]
    level.cell_size, level.origin_x, level.origin_z = .25, -32, -32
    for z in 0 ..< terrain.RING_RESOLUTION {
        height := (level.origin_z + f32(z) * level.cell_size) * .2
        for x in 0 ..< terrain.RING_RESOLUTION {
            level.heights[terrain.sample_index(x, z)] = height
        }
    }
    plan: Settlement_Plan
    plan.request.scale = .Village
    plan.routes[0].geometry.points[0] = {-30, 0}
    plan.routes[0].geometry.points[1] = {30, 0}
    plan.routes[0].geometry.count = 2
    plan.routes[0].width = 4
    plan.routes[0].shoulder = .8
    plan.routes[0].drivable = true
    plan.route_count = 1
    plan.ordinary_purposes[0] = .Barn_Granary
    plan.ordinary_purpose_count = 1
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    structure := terrain.structure_make(0, 14, 8, 8, 0, 7)
    structure.rotation = math.PI
    append(&city.structures, structure)
    city.count = 1
    rng := settlement_rng_new(231)

    connected := settlement_plan_generate_building_access(&plan, project, &city, &rng, 40)

    testing.expect_value(t, connected, 1)
    testing.expect(t, city.alley_count > 0)
    for alley in city.alleys[:city.alley_count] {
        testing.expect(t, alley.half_width <= .501)
    }
}

@(test)
settlement_access_junctions_cap_degree_and_reject_shallow_wedges :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    directions := [4][2]f32{{10, 0}, {-10, 0}, {0, 10}, {0, -10}}
    for direction in directions {
        append(
            &city.alleys,
            architecture.City_Alley{start_x = 0, start_z = 0, end_x = direction[0], end_z = direction[1]},
        )
    }
    city.alley_count = 4
    testing.expect_value(t, settlement_access_network_degree(&city, {0, 0}), 4)
    topology_plan: Settlement_Plan
    settlement_plan_measure_access_topology(&topology_plan, &city)
    testing.expect_value(t, topology_plan.access_max_degree, 4)
    testing.expect_value(t, topology_plan.access_shallow_junctions, 0)

    // Use one incident segment to isolate the angular rule.
    city.alley_count = 1
    shallow, open, continuation, bent_continuation: Settlement_Route
    shallow_angle := f64(math.PI / 18)
    shallow.points[0] = {f32(math.cos(shallow_angle)) * 10, f32(math.sin(shallow_angle)) * 10}
    shallow.points[1], shallow.count = {0, 0}, 2
    open.points[0], open.points[1], open.count = {7, 7}, {0, 0}, 2
    continuation.points[0], continuation.points[1], continuation.count = {-10, 0}, {0, 0}, 2
    bent_continuation.points[0], bent_continuation.points[1], bent_continuation.count = {-10, 1}, {0, 0}, 2
    testing.expect(t, !settlement_access_junction_angle_valid(&city, shallow))
    testing.expect(t, settlement_access_junction_angle_valid(&city, open))
    testing.expect(t, settlement_access_junction_angle_valid(&city, continuation))
    testing.expect(t, settlement_access_junction_angle_valid(&city, bent_continuation))

    city.alleys[2].end_x, city.alleys[2].end_z = shallow.points[0][0], shallow.points[0][1]
    city.alley_count = 3
    settlement_plan_measure_access_topology(&topology_plan, &city)
    testing.expect_value(t, topology_plan.access_max_degree, 3)
    testing.expect_value(t, topology_plan.access_shallow_junctions, 1)
}

@(test)
settlement_access_intersections_become_explicit_network_junctions :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(&city.alleys, architecture.City_Alley{start_x = -5, start_z = 0, end_x = 5, end_z = 0, half_width = .5})
    append(&city.alleys, architecture.City_Alley{start_x = 0, start_z = -5, end_x = 0, end_z = 0, half_width = .5})
    city.alley_count = 2

    before: Settlement_Plan
    settlement_plan_measure_access_topology(&before, &city)
    testing.expect_value(t, before.access_unsplit_junctions, 1)

    settlement_access_split_intersections(&city)

    after: Settlement_Plan
    settlement_plan_measure_access_topology(&after, &city)
    testing.expect_value(t, city.alley_count, 3)
    testing.expect_value(t, after.access_max_degree, 3)
    testing.expect_value(t, after.access_crossings, 0)
    testing.expect_value(t, after.access_unsplit_junctions, 0)
}

@(test)
settlement_access_normalization_removes_sub_tolerance_slivers :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    segments := [3][2][2]f32{{{-1, 0}, {0, 0}}, {{0, 0}, {.03, 0}}, {{.03, 0}, {1, 0}}}
    for segment in segments {
        append(
            &city.alleys,
            architecture.City_Alley {
                start_x = segment[0][0],
                start_z = segment[0][1],
                end_x = segment[1][0],
                end_z = segment[1][1],
                half_width = .5,
            },
        )
    }
    city.alley_count = 3

    settlement_access_snap_near_endpoints(&city)
    settlement_access_remove_degenerate_segments(&city)
    settlement_access_deduplicate_segments(&city)

    plan: Settlement_Plan
    settlement_plan_measure_access_topology(&plan, &city)
    testing.expect_value(t, city.alley_count, 2)
    testing.expect_value(t, plan.access_max_degree, 2)
    testing.expect_value(t, plan.access_shallow_junctions, 0)
}

@(test)
settlement_access_normalization_chords_public_hairpin_bends :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(&city.alleys, architecture.City_Alley{start_x = 0, start_z = 0, end_x = 0, end_z = 5, half_width = .45})
    append(&city.alleys, architecture.City_Alley{start_x = 0, start_z = 0, end_x = 1, end_z = 5, half_width = .55})
    city.alley_count = 2

    plan: Settlement_Plan
    settlement_plan_measure_access_topology(&plan, &city)
    testing.expect_value(t, plan.access_hairpin_bends, 1)

    settlement_access_simplify_hairpin_bends(&plan, &city)
    settlement_plan_measure_access_topology(&plan, &city)

    testing.expect_value(t, city.alley_count, 1)
    testing.expect_value(t, plan.access_hairpin_bends, 0)
    testing.expect(t, city.alleys[0].half_width >= .55)
}

@(test)
settlement_access_collapses_sub_meter_double_junctions :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100

    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    segments := [5][2][2]f32 {
        {{-.4, 0}, {.4, 0}},
        {{-.4, 0}, {-3, -2}},
        {{-.4, 0}, {-3, 2}},
        {{.4, 0}, {3, -2}},
        {{.4, 0}, {3, 2}},
    }
    for segment, segment_index in segments {
        terminal := segment_index == 1 ? architecture.City_Alley_Terminal.Road : architecture.City_Alley_Terminal.None
        append(
            &city.alleys,
            architecture.City_Alley {
                start_x = segment[0][0],
                start_z = segment[0][1],
                end_x = segment[1][0],
                end_z = segment[1][1],
                half_width = .5,
                end_terminal = terminal,
            },
        )
    }
    city.alley_count = len(segments)
    plan: Settlement_Plan
    plan.request.scale = .Village

    testing.expect_value(t, settlement_access_network_degree(&city, {-.4, 0}), 3)
    testing.expect_value(t, settlement_access_network_degree(&city, {.4, 0}), 3)
    testing.expect_value(t, settlement_access_collapse_short_junction_links(&plan, project, &city), 1)
    testing.expect_value(t, city.alley_count, 4)
    testing.expect_value(t, settlement_access_network_degree(&city, {0, 0}), 4)
    settlement_plan_measure_access_topology(&plan, &city)
    testing.expect(t, plan.access_max_degree <= 4)
    testing.expect_value(t, plan.access_crossings, 0)
    testing.expect_value(t, plan.access_unsplit_junctions, 0)
}

@(test)
settlement_access_network_relaxation_shortens_only_anonymous_bends :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100

    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(
        &city.alleys,
        architecture.City_Alley {
            start_x = -6,
            start_z = 0,
            end_x = 0,
            end_z = 4,
            half_width = .5,
            start_terminal = .Road,
        },
    )
    append(
        &city.alleys,
        architecture.City_Alley{start_x = 0, start_z = 4, end_x = 6, end_z = 0, half_width = .5, end_terminal = .Door},
    )
    city.alley_count = 2
    before_length := linalg.length([2]f32{-6, 0} - [2]f32{0, 4}) + linalg.length([2]f32{0, 4} - [2]f32{6, 0})

    plan: Settlement_Plan
    moved := settlement_access_relax_degree_two_nodes(&plan, project, &city)
    relaxed_node := [2]f32{city.alleys[0].end_x, city.alleys[0].end_z}
    after_length := linalg.length([2]f32{-6, 0} - relaxed_node) + linalg.length(relaxed_node - [2]f32{6, 0})

    testing.expect(t, moved > 0)
    testing.expect(t, relaxed_node[1] < 4)
    testing.expect(t, after_length < before_length)
    testing.expect(t, settlement_alley_point_near({city.alleys[0].start_x, city.alleys[0].start_z}, {-6, 0}))
    testing.expect(t, settlement_alley_point_near({city.alleys[1].end_x, city.alleys[1].end_z}, {6, 0}))

    city.alleys[0].end_terminal = .Public_Space
    protected := relaxed_node
    testing.expect_value(t, settlement_access_relax_degree_two_nodes(&plan, project, &city), 0)
    testing.expect(t, settlement_alley_point_near({city.alleys[0].end_x, city.alleys[0].end_z}, protected))
}

@(test)
settlement_access_shared_house_trunks_widen_by_demand :: proc(t: ^testing.T) {
    testing.expect(t, settlement_access_shared_desired_half_width(.5, 2) < .9)
    testing.expect(t, settlement_access_shared_desired_half_width(.5, 3) >= .9)
    testing.expect(t, settlement_access_shared_desired_half_width(.7, 4) >= .9)

    plan: Settlement_Plan
    plan.routes[0].geometry.points[0], plan.routes[0].geometry.points[1] = {-20, 0}, {20, 0}
    plan.routes[0].geometry.count = 2
    plan.routes[0].width = 4
    plan.routes[0].shoulder = .8
    plan.routes[0].drivable = true
    plan.route_count = 1

    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    first := terrain.structure_make(-20, 12, 4, 4, 0, 5)
    second := terrain.structure_make(20, 12, 4, 4, 0, 5)
    first.rotation, second.rotation = math.PI, math.PI
    append(&city.structures, first, second)
    city.count = 2
    first_door := settlement_structure_front_door_point(first)
    second_door := settlement_structure_front_door_point(second)
    merge, road := [2]f32{0, 6}, [2]f32{0, 3.25}
    segments := [3][2][2]f32{{first_door, merge}, {second_door, merge}, {merge, road}}
    for segment in segments {
        append(
            &city.alleys,
            architecture.City_Alley {
                start_x = segment[0][0],
                start_z = segment[0][1],
                end_x = segment[1][0],
                end_z = segment[1][1],
                half_width = .5,
            },
        )
    }
    city.alley_count = 3

    testing.expect(t, settlement_access_segment_clear(&city, merge, road, .55, -1))
    settlement_access_widen_shared_trunks(&plan, &city)

    testing.expect_value(t, plan.access_shared_segments, 1)
    testing.expect_value(t, plan.access_widened_segments, 1)
    testing.expect(t, math.abs(city.alleys[0].half_width - .5) < .001)
    testing.expect(t, math.abs(city.alleys[1].half_width - .5) < .001)
    testing.expect(t, city.alleys[2].half_width > .5)
}

@(test)
settlement_access_building_journeys_promote_cross_town_passages :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    segments := [4][2][2]f32{{{-12, 8}, {-6, 8}}, {{-6, 8}, {6, 8}}, {{6, 8}, {12, 8}}, {{0, 8}, {0, 0}}}
    for segment in segments {
        append(
            &city.alleys,
            architecture.City_Alley {
                start_x = segment[0][0],
                start_z = segment[0][1],
                end_x = segment[1][0],
                end_z = segment[1][1],
                half_width = .5,
            },
        )
    }
    city.alley_count = len(segments)
    travel_length := [4]f32{6, 12, 6, 8}
    demand: [4]int

    found := settlement_access_accumulate_building_journey(
        &city,
        travel_length[:],
        len(segments),
        {-12, 8},
        {12, 8},
        demand[:],
    )

    testing.expect(t, found)
    testing.expect_value(t, demand[0], 0)
    testing.expect_value(t, demand[1], 1)
    testing.expect_value(t, demand[2], 0)
    testing.expect_value(t, demand[3], 0)
}

@(test)
settlement_access_household_routing_uses_spline_arc_length :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.request.scale = .Village
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    structure := terrain.structure_make(0, 0, 4, 4, 0, 5)
    append(&city.structures, structure)
    city.count = 1
    door := settlement_structure_front_door_point(structure)
    outward := settlement_structure_entrance_outward(structure)
    side := [2]f32{-outward[1], outward[0]}
    junction := door + outward * 3
    short_mid, short_road := junction - side, junction - side + outward * 4
    long_mid, long_road := junction + side * 3, junction + side * 3 + outward * 4
    segments := [5][2][2]f32 {
        {door, junction},
        {junction, short_mid},
        {short_mid, short_road},
        {junction, long_mid},
        {long_mid, long_road},
    }
    for segment, segment_index in segments {
        append(
            &city.alleys,
            architecture.City_Alley {
                start_x = segment[0][0],
                start_z = segment[0][1],
                end_x = segment[1][0],
                end_z = segment[1][1],
                half_width = .5,
                start_terminal = segment_index == 0 ? architecture.City_Alley_Terminal.Door : .None,
                end_terminal = segment_index == 2 || segment_index == 4 ? architecture.City_Alley_Terminal.Road : .None,
                curve_ready = true,
            },
        )
    }
    city.alley_count = len(segments)
    for &alley in city.alleys[:city.alley_count] {
        start, finish := [2]f32{alley.start_x, alley.start_z}, [2]f32{alley.end_x, alley.end_z}
        alley.curve_control_from = start + (finish - start) / 3
        alley.curve_control_to = start + (finish - start) * (f32(2) / 3)
    }
    // Endpoint chords make the left route shorter. Its cached spline takes a
    // large lateral bow, so actual walking distance favors the right route.
    short_curve_side := side * 7
    city.alleys[1].curve_control_from += short_curve_side
    city.alleys[1].curve_control_to += short_curve_side
    city.alleys[2].curve_control_from -= short_curve_side
    city.alleys[2].curve_control_to -= short_curve_side
    chord_short := linalg.length(short_mid - junction) + linalg.length(short_road - short_mid)
    chord_long := linalg.length(long_mid - junction) + linalg.length(long_road - long_mid)
    testing.expect(t, chord_short < chord_long)
    testing.expect(
        t,
        settlement_access_alley_length(&city, 1) + settlement_access_alley_length(&city, 2) >
        settlement_access_alley_length(&city, 3) + settlement_access_alley_length(&city, 4),
    )

    settlement_access_widen_shared_trunks(&plan, &city)
    testing.expect_value(t, city.alleys[0].household_demand, u16(1))
    testing.expect_value(t, city.alleys[1].household_demand, u16(0))
    testing.expect_value(t, city.alleys[2].household_demand, u16(0))
    testing.expect_value(t, city.alleys[3].household_demand, u16(1))
    testing.expect_value(t, city.alleys[4].household_demand, u16(1))
}

@(test)
settlement_access_curved_lane_widening_checks_spline_clearance :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(
        &city.alleys,
        architecture.City_Alley {
            start_x = 0,
            start_z = 0,
            end_x = 10,
            end_z = 0,
            half_width = .5,
            curve_control_from = {2, 4},
            curve_control_to = {8, 4},
            curve_ready = true,
        },
    )
    city.alley_count = 1
    curve := settlement_access_alley_curve(&city, 0)
    middle := settlement_access_curve_point(curve, .5)
    tangent_point := settlement_access_curve_point(curve, .51)
    tangent := linalg.normalize0(tangent_point - middle)
    normal := [2]f32{-tangent[1], tangent[0]}
    obstacle_center := middle + normal * .7
    obstacle := terrain.structure_make(obstacle_center[0], obstacle_center[1], .1, .1, 0, 3)
    obstacle.width, obstacle.depth = .1, .1
    append(&city.structures, obstacle)
    city.count = 1

    testing.expect(t, settlement_access_alley_width_clear(&city, 0, .5))
    testing.expect(t, !settlement_access_alley_width_clear(&city, 0, .8))
}

@(test)
settlement_village_doorsteps_cannot_be_public_through_nodes :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.request.scale = .Village

    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    structure := terrain.structure_make(0, 0, 4, 4, 0, 5)
    append(&city.structures, structure)
    city.count = 1
    door := settlement_structure_front_door_point(structure)
    outward := settlement_structure_entrance_outward(structure)
    append(
        &city.alleys,
        architecture.City_Alley {
            start_x = door[0],
            start_z = door[1],
            end_x = door[0] + outward[0] * 4,
            end_z = door[1] + outward[1] * 4,
            half_width = .5,
            start_terminal = .Door,
            end_terminal = .Road,
        },
    )
    append(
        &city.alleys,
        architecture.City_Alley {
            start_x = door[0],
            start_z = door[1],
            end_x = door[0] - outward[0] * 3,
            end_z = door[1] - outward[1] * 3,
            half_width = .5,
            end_terminal = .Road,
        },
    )
    city.alley_count = 2

    testing.expect_value(t, settlement_access_count_road_connected_doors(&plan, &city), 0)
    settlement_access_prune_road_spurs_at_doors(&plan, &city)
    testing.expect_value(t, city.alley_count, 1)
    testing.expect_value(t, settlement_access_network_degree(&city, door), 1)
    testing.expect_value(t, settlement_access_count_road_connected_doors(&plan, &city), 1)

    doubling_back: Settlement_Route
    doubling_back.points[0] = door
    doubling_back.points[1] = door + outward * 2
    doubling_back.points[2] = door + [2]f32{2, 2}
    doubling_back.points[3] = door
    doubling_back.count = 4
    testing.expect(t, !settlement_access_path_crossings_valid(&city, doubling_back, false, true))
}

@(test)
settlement_access_working_width_reaches_the_road_root :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.request.scale = .Village
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    structure := terrain.structure_make(0, 0, 4, 4, 0, 5)
    structure.rotation = 0
    append(&city.structures, structure)
    city.count = 1
    door := settlement_structure_front_door_point(structure)
    merge, road := door + [2]f32{0, 5}, door + [2]f32{0, 10}
    append(
        &city.alleys,
        architecture.City_Alley {
            start_x = door[0],
            start_z = door[1],
            end_x = merge[0],
            end_z = merge[1],
            half_width = .9,
            start_terminal = .Door,
        },
    )
    append(
        &city.alleys,
        architecture.City_Alley {
            start_x = merge[0],
            start_z = merge[1],
            end_x = road[0],
            end_z = road[1],
            half_width = .5,
            end_terminal = .Road,
        },
    )
    city.alley_count = 2

    settlement_access_widen_shared_trunks(&plan, &city)

    testing.expect_value(t, plan.access_connected_count, 1)
    testing.expect_value(t, plan.access_shared_segments, 0)
    testing.expect_value(t, plan.access_widened_segments, 0)
    testing.expect(t, city.alleys[1].half_width >= .899)
    testing.expect_value(t, city.alleys[0].household_demand, u16(1))
    testing.expect_value(t, city.alleys[1].household_demand, u16(1))
}

@(test)
settlement_access_topology_reports_unexplained_leaf_endpoints :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(&city.alleys, architecture.City_Alley{start_x = -3, start_z = 4, end_x = 3, end_z = 4, half_width = .5})
    city.alley_count = 1

    plan: Settlement_Plan
    settlement_plan_measure_access_topology(&plan, &city)

    testing.expect_value(t, plan.access_orphan_endpoints, 2)
}

@(test)
settlement_access_public_space_terminal_explains_road_rooted_spur :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(
        &city.alleys,
        architecture.City_Alley {
            start_x = 0,
            start_z = 0,
            end_x = 4,
            end_z = 0,
            half_width = .5,
            start_terminal = .Road,
        },
    )
    city.alley_count = 1

    settlement_access_prune_stale_terminal_free_stubs(&city)
    testing.expect_value(t, city.alley_count, 1)
    testing.expect_value(t, city.alleys[0].end_terminal, architecture.City_Alley_Terminal.Public_Space)
    plan: Settlement_Plan
    settlement_plan_measure_access_topology(&plan, &city)
    testing.expect_value(t, plan.access_orphan_endpoints, 0)
}

@(test)
settlement_access_straightens_only_the_terminal_road_throat :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.routes[0].geometry.points[0], plan.routes[0].geometry.points[1] = {-10, 0}, {10, 0}
    plan.routes[0].geometry.count = 2
    plan.routes[0].width = 4
    plan.routes[0].shoulder = 1
    plan.routes[0].drivable = true
    plan.route_count = 1

    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(
        &city.alleys,
        architecture.City_Alley {
            start_x = 0,
            start_z = 3.45,
            end_x = .4,
            end_z = 4.1,
            half_width = .5,
            start_terminal = .Road,
            end_terminal = .Public_Space,
        },
    )
    city.alley_count = 1

    settlement_access_straighten_road_throats(&plan, &city)
    testing.expect_value(t, city.alley_count, 2)
    testing.expect(t, math.abs(city.alleys[0].end_x) < .001)
    topology: Settlement_Plan
    topology.routes[0] = plan.routes[0]
    topology.route_count = 1
    settlement_plan_measure_access_topology(&topology, &city)
    testing.expect_value(t, topology.access_bad_road_approaches, 0)
}

@(test)
settlement_access_stairs_reserve_terminal_landings :: proc(t: ^testing.T) {
    terminal_run := architecture.City_Alley {
        start_terminal = .Door,
        end_terminal   = .Road,
    }
    start, finish, valid := settlement_access_stair_nosing_range(terminal_run, 2)
    testing.expect(t, valid)
    testing.expect(t, math.abs(start - .65) < .001)
    testing.expect(t, math.abs(finish - 1.35) < .001)

    _, _, short_valid := settlement_access_stair_nosing_range(terminal_run, 1)
    testing.expect(t, !short_valid)

    open_run: architecture.City_Alley
    open_start, open_finish, open_valid := settlement_access_stair_nosing_range(open_run, 1)
    testing.expect(t, open_valid)
    testing.expect(t, math.abs(open_start) < .001)
    testing.expect(t, math.abs(open_finish - 1) < .001)
}

@(test)
settlement_access_door_aprons_cover_narrow_thresholds :: proc(t: ^testing.T) {
    narrow := architecture.City_Alley {
        half_width = .25,
    }
    wide := architecture.City_Alley {
        half_width = .8,
    }
    testing.expect_value(t, settlement_access_door_apron_width(narrow), f32(1.1))
    testing.expect_value(t, settlement_access_door_apron_width(wide), f32(1.6))
}

@(test)
settlement_access_road_aprons_flare_only_broad_approaches :: proc(t: ^testing.T) {
    narrow := architecture.City_Alley {
        half_width = .5,
    }
    _, _, narrow_valid := settlement_access_road_apron(narrow, 4)
    testing.expect(t, !narrow_valid)

    public := architecture.City_Alley {
        half_width = .8,
    }
    run, outer_width, valid := settlement_access_road_apron(public, 4)
    testing.expect(t, valid)
    testing.expect_value(t, run, f32(.9))
    testing.expect_value(t, outer_width, f32(2.2))

    short_service := architecture.City_Alley {
        half_width = .9,
    }
    short_run, short_outer_width, short_valid := settlement_access_road_apron(short_service, .5)
    testing.expect(t, short_valid)
    testing.expect_value(t, short_run, f32(.5))
    testing.expect_value(t, short_outer_width, f32(2.4))
}

@(test)
settlement_access_surface_queries_include_flared_road_mouths :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(
        &city.alleys,
        architecture.City_Alley {
            start_x = 0,
            start_z = 0,
            end_x = 4,
            end_z = 0,
            half_width = .8,
            start_terminal = .Road,
        },
    )
    city.alley_count = 1
    testing.expect(t, settlement_access_point_on_alley_surface(&city, {.1, 1.05}, 0))
    testing.expect(t, !settlement_access_point_on_alley_surface(&city, {.8, 1.05}, 0))

    foliage := terrain.structure_make(.1, 1.25, .2, .2, 0, 2)
    foliage.width, foliage.depth = .2, .2
    testing.expect(t, settlement_access_structure_overlaps_alley(&city, foliage))
    city.alleys[0].start_terminal = .None
    testing.expect(t, !settlement_access_structure_overlaps_alley(&city, foliage))
}

@(test)
settlement_access_surface_excludes_vegetation_by_paved_width :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(&city.alleys, architecture.City_Alley{start_x = 0, start_z = 0, end_x = 10, end_z = 0, half_width = .6})
    city.alley_count = 1

    testing.expect(t, settlement_access_point_on_alley_surface(&city, {5, .7}))
    testing.expect(t, settlement_access_point_on_alley_surface(&city, {-.1, 0}))
    testing.expect(t, !settlement_access_point_on_alley_surface(&city, {5, .9}))
    testing.expect(t, !settlement_access_point_on_alley_surface(&city, {11, 0}))
    city.alleys[0].end_terminal = .Public_Space
    testing.expect(t, settlement_access_point_on_alley_surface(&city, {10, .9}))
    testing.expect(t, !settlement_access_point_on_alley_surface(&city, {10, 1.2}))
}

@(test)
settlement_access_surface_queries_follow_relaxed_curve_not_chord :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(
        &city.alleys,
        architecture.City_Alley{start_x = -12, end_x = 0, half_width = .4, start_terminal = .Road},
        architecture.City_Alley {
            start_x = 0,
            start_z = 0,
            end_x = 0,
            end_z = 12,
            half_width = .4,
            end_terminal = .Door,
        },
    )
    city.alley_count = 2
    curve := settlement_access_alley_curve(&city, 0)
    curved_point := settlement_access_curve_point(curve, .75)
    testing.expect(t, settlement_point_segment_distance_squared(curved_point, {-12, 0}, {0, 0}) > 1)
    testing.expect(t, settlement_access_point_on_alley_surface(&city, curved_point, 0))
    testing.expect(t, !settlement_access_point_on_alley_surface(&city, {curved_point[0], 0}, 0))
}

@(test)
settlement_access_three_way_junction_preserves_the_soft_through_line :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(
        &city.alleys,
        architecture.City_Alley{start_x = -10, end_x = 0, half_width = .5},
        architecture.City_Alley{start_x = 0, end_x = 10, half_width = .5},
        architecture.City_Alley{start_x = 0, end_z = 8, half_width = .5},
    )
    city.alley_count = 3

    incoming := settlement_access_alley_endpoint_tangent(&city, 0, 1)
    outgoing := settlement_access_alley_endpoint_tangent(&city, 1, 0)
    branch := settlement_access_alley_endpoint_tangent(&city, 2, 0)

    testing.expect(t, linalg.dot(incoming, [2]f32{1, 0}) > .99)
    testing.expect(t, linalg.dot(outgoing, [2]f32{1, 0}) > .99)
    testing.expect(t, linalg.dot(branch, [2]f32{0, 1}) > .55)
}

@(test)
settlement_curved_access_falls_back_before_clipping_rotated_building :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(
        &city.alleys,
        architecture.City_Alley{start_x = -12, end_x = 0, half_width = .4, start_terminal = .Road},
        architecture.City_Alley {
            start_x = 0,
            start_z = 0,
            end_x = 0,
            end_z = 12,
            half_width = .4,
            end_terminal = .Door,
        },
    )
    city.alley_count = 2
    raw_curve := settlement_access_alley_curve_raw(&city, 0)
    obstacle_center := settlement_access_curve_point(raw_curve, .75)
    obstacle := terrain.structure_make(obstacle_center[0], obstacle_center[1], .1, .1, 0, 4)
    obstacle.width, obstacle.depth = .1, .1
    obstacle.rotation = math.PI * .25
    append(&city.structures, obstacle)
    city.count = 1
    curve := settlement_access_alley_curve(&city, 0)
    expected_control := [2]f32{-8, 0}
    testing.expect(t, linalg.length(curve.points[1] - expected_control) < .001)
    previous := curve.points[0]
    for sample in 1 ..= 32 {
        current := settlement_access_curve_point(curve, f32(sample) / 32)
        testing.expect(t, !settlement_segment_intersects_structure_clearance(previous, current, obstacle, .65))
        previous = current
    }
    testing.expect_value(t, obstacle.rotation, f32(math.PI * .25))
}

@(test)
settlement_access_foliage_footprint_respects_alley_setback :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(&city.alleys, architecture.City_Alley{start_x = 0, start_z = 0, end_x = 10, end_z = 0, half_width = .5})
    city.alley_count = 1

    foliage := terrain.structure_make(5, 0, 2, 2, 0, 3)
    foliage.kind = .Foliage
    testing.expect(t, settlement_access_structure_overlaps_alley(&city, foliage))

    foliage.center_z = 20
    testing.expect(t, !settlement_access_structure_overlaps_alley(&city, foliage))

    foliage.center_z = 1.5
    foliage.width = .5
    foliage.depth = 3
    foliage.rotation = math.PI * .5
    testing.expect(t, !settlement_access_structure_overlaps_alley(&city, foliage))
    foliage.rotation = 0
    testing.expect(t, settlement_access_structure_overlaps_alley(&city, foliage))
}

@(test)
settlement_access_paving_caps_only_bends_and_junctions :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(&city.alleys, architecture.City_Alley{start_x = -4, start_z = 0, end_x = 0, end_z = 0, half_width = .5})
    append(&city.alleys, architecture.City_Alley{start_x = 0, start_z = 0, end_x = 4, end_z = 0, half_width = .6})
    city.alley_count = 2
    testing.expect_value(t, settlement_access_node_paving_radius(&city, {0, 0}), f32(0))

    city.alleys[1].end_x, city.alleys[1].end_z = 0, 4
    testing.expect_value(t, settlement_access_node_paving_radius(&city, {0, 0}), f32(.6))

    city.alleys[0].end_terminal = .Door
    testing.expect_value(t, settlement_access_node_paving_radius(&city, {0, 0}), f32(0))
    city.alleys[0].end_terminal = .None
    city.alleys[1].end_terminal = .Public_Space
    testing.expect_value(t, settlement_access_node_paving_radius(&city, {0, 4}), f32(.9))
}

@(test)
settlement_access_paths_relax_at_first_network_contact :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(
        &city.alleys,
        architecture.City_Alley {
            start_x = -5,
            start_z = 0,
            end_x = 5,
            end_z = 0,
            half_width = .5,
            start_terminal = .Road,
        },
    )
    city.alley_count = 1
    crossing: Settlement_Route
    crossing.points[0], crossing.points[1], crossing.count = {0, -5}, {0, 5}, 2

    testing.expect(t, !settlement_access_path_crossings_valid(&city, crossing, false))
    plan: Settlement_Plan
    relaxed, joined := settlement_access_path_relax_to_network(&plan, &city, crossing)
    testing.expect(t, joined)
    testing.expect_value(t, relaxed.count, 2)
    testing.expect(t, settlement_alley_point_near(relaxed.points[1], {0, 0}))
    testing.expect(t, settlement_access_path_crossings_valid(&city, relaxed, true))
    testing.expect(t, settlement_access_junction_angle_valid(&city, relaxed))

    near_contact: Settlement_Route
    near_contact.points[0], near_contact.points[1], near_contact.points[2], near_contact.count =
        {0, -5}, {.03, 0}, {5, 5}, 3
    testing.expect(t, !settlement_access_path_crossings_valid(&city, near_contact, false))
}

@(test)
settlement_access_split_preserves_outer_terminal_provenance :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(
        &city.alleys,
        architecture.City_Alley {
            start_x = 0,
            start_z = 0,
            end_x = 10,
            end_z = 0,
            half_width = .5,
            start_terminal = .Door,
            end_terminal = .Road,
        },
    )
    city.alley_count = 1

    testing.expect(t, settlement_access_split_alley(&city, 0, {4, 0}))
    testing.expect_value(t, city.alley_count, 2)
    testing.expect_value(t, city.alleys[0].start_terminal, architecture.City_Alley_Terminal.Door)
    testing.expect_value(t, city.alleys[0].end_terminal, architecture.City_Alley_Terminal.None)
    testing.expect_value(t, city.alleys[1].start_terminal, architecture.City_Alley_Terminal.None)
    testing.expect_value(t, city.alleys[1].end_terminal, architecture.City_Alley_Terminal.Road)
}

@(test)
settlement_access_reverse_deduplication_merges_terminal_provenance :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(
        &city.alleys,
        architecture.City_Alley {
            start_x = 0,
            start_z = 0,
            end_x = 5,
            end_z = 0,
            half_width = .4,
            start_terminal = .Door,
        },
    )
    append(
        &city.alleys,
        architecture.City_Alley {
            start_x = 5,
            start_z = 0,
            end_x = 0,
            end_z = 0,
            half_width = .6,
            start_terminal = .Road,
        },
    )
    city.alley_count = 2

    settlement_access_deduplicate_segments(&city)
    testing.expect_value(t, city.alley_count, 1)
    testing.expect_value(t, city.alleys[0].start_terminal, architecture.City_Alley_Terminal.Door)
    testing.expect_value(t, city.alleys[0].end_terminal, architecture.City_Alley_Terminal.Road)
    testing.expect_value(t, city.alleys[0].half_width, f32(.6))
}

@(test)
settlement_access_consolidates_anonymous_near_parallel_twigs :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    append(&city.alleys, architecture.City_Alley{start_x = 0, start_z = 0, end_x = 10, end_z = 0, half_width = .4})
    append(&city.alleys, architecture.City_Alley{start_x = 0, start_z = 0, end_x = 10, end_z = .3, half_width = .6})
    city.alley_count = 2

    settlement_access_consolidate_parallel_twigs(&city)
    testing.expect_value(t, city.alley_count, 1)
    testing.expect_value(t, city.alleys[0].half_width, f32(.6))
    testing.expect(t, settlement_alley_point_near({city.alleys[0].end_x, city.alleys[0].end_z}, {10, .15}))
}

@(test)
settlement_access_prunes_redundant_shallow_seed_branches :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    directions := [3][2]f32{{0, 10}, {.1, 6}, {10, 0}}
    for direction in directions {
        append(
            &city.alleys,
            architecture.City_Alley{start_x = 0, start_z = 0, end_x = direction[0], end_z = direction[1]},
        )
    }
    city.alley_count = 3

    settlement_access_prune_shallow_seed_branches(&city)

    plan: Settlement_Plan
    settlement_plan_measure_access_topology(&plan, &city)
    testing.expect_value(t, city.alley_count, 2)
    testing.expect_value(t, plan.access_shallow_junctions, 0)
}

@(test)
settlement_access_path_width_adapts_to_narrow_passages :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    left := terrain.structure_make(-2.3, 0, 4, 100, 0, 7)
    left.width, left.depth = 4, 100
    right := terrain.structure_make(2.3, 0, 4, 100, 0, 7)
    right.width, right.depth = 4, 100
    append(&city.structures, left)
    append(&city.structures, right)
    city.count = 2
    wide := settlement_access_path_find(project, &city, {0, -8}, {0, 8}, -1, .4)
    narrow := settlement_access_path_find(project, &city, {0, -8}, {0, 8}, -1, .25)
    testing.expect_value(t, wide.count, 0)
    testing.expect_value(t, narrow.count, 2)
}

@(test)
settlement_access_path_accepts_a_clear_long_apron_without_grid_search :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    start, goal := [2]f32{-24, 3}, [2]f32{24, 3}

    path := settlement_access_path_find(project, &city, start, goal, -1, .4, true, {1, 0}, {1, 0})

    testing.expect_value(t, path.count, 2)
    testing.expect(t, settlement_alley_point_near(path.points[0], start, .001))
    testing.expect(t, settlement_alley_point_near(path.points[1], goal, .001))
}

@(test)
settlement_access_path_preserves_a_gentle_detour_around_steep_ground :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    level := &project.levels[0]
    level.cell_size, level.origin_x, level.origin_z = .25, -20, -20
    for z in 0 ..< terrain.RING_RESOLUTION {
        world_z := level.origin_z + f32(z) * level.cell_size
        for x in 0 ..< terrain.RING_RESOLUTION {
            world_x := level.origin_x + f32(x) * level.cell_size
            if world_x >= 4 && world_x <= 6 && math.abs(world_z) < 2 {
                level.heights[terrain.sample_index(x, z)] = 3
            }
        }
    }
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    start, goal := [2]f32{0, 0}, [2]f32{10, 0}
    direct_grade := settlement_access_segment_max_grade(project, start, goal)
    path := settlement_access_path_find(project, &city, start, goal, -1)
    path_grade: f32
    for index in 0 ..< path.count - 1 {
        path_grade = max(
            path_grade,
            settlement_access_segment_max_grade(project, path.points[index], path.points[index + 1]),
        )
    }
    testing.expect(t, direct_grade > SETTLEMENT_ACCESS_STAIR_GRADE)
    testing.expect(t, path.count > 2)
    testing.expect(t, path_grade < direct_grade)
}

@(test)
settlement_working_access_seeks_a_gentler_available_detour :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    level := &project.levels[0]
    level.cell_size, level.origin_x, level.origin_z = .25, -20, -20
    for z in 0 ..< terrain.RING_RESOLUTION {
        world_z := level.origin_z + f32(z) * level.cell_size
        for x in 0 ..< terrain.RING_RESOLUTION {
            world_x := level.origin_x + f32(x) * level.cell_size
            cross_fade := clamp(3 - math.abs(world_x), f32(0), f32(1))
            longitudinal: f32
            if world_z >= 4 && world_z < 6 {
                longitudinal = (world_z - 4) * .16
            } else if world_z >= 6 && world_z <= 8 {
                longitudinal = .32
            } else if world_z > 8 && world_z <= 10 {
                longitudinal = (10 - world_z) * .16
            }
            level.heights[terrain.sample_index(x, z)] = longitudinal * cross_fade
        }
    }
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    start, goal := [2]f32{0, 10}, [2]f32{0, 0}
    domestic := settlement_access_path_find(
        project,
        &city,
        start,
        goal,
        -1,
        .4,
        true,
        {},
        {},
        SETTLEMENT_ACCESS_SEVERE_GRADE,
    )
    working := settlement_access_path_find(project, &city, start, goal, -1, .4, true, {}, {}, .10)
    domestic_grade := settlement_access_path_max_grade(project, domestic)
    working_grade := settlement_access_path_max_grade(project, working)
    testing.expect_value(t, domestic.count, 2)
    testing.expect(t, working.count > 2)
    testing.expect(t, working_grade < domestic_grade)
}

@(test)
settlement_acceptance_requires_every_building_access_connection :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    project := new(terrain.Project)
    defer free(project)
    plan.access_required_count = 12
    plan.access_connected_count = 11

    testing.expect_value(
        t,
        settlement_plan_acceptance_failure(&plan, project),
        Settlement_Acceptance_Failure.Building_Access,
    )
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

settlement_acceptance_rejects_wide_roads_and_height_outliers :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    plan: Settlement_Plan
    plan.request = {
        region = .Adriatic,
        scale  = .Village,
    }
    plan.village_reason = .Route_Stop
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
    purposes := [12]Settlement_Building_Purpose {
        .Dwelling,
        .Dwelling,
        .Dwelling,
        .Dwelling,
        .Dwelling,
        .Dwelling,
        .Dwelling,
        .Workshop,
        .Inn_Shop,
        .Farmstead,
        .Barn_Granary,
        .Storehouse,
    }
    plan.sites[0].purpose = purposes[0]
    for index in 1 ..< len(purposes) {
        x := f32((index % 4) * 10 - 15)
        z := f32((index / 4) * 12 - 12)
        plan.sites[index] = {
            structure = terrain.structure_make(x, z, 7, 9, 0, 7),
            kind      = .Ordinary,
            purpose   = purposes[index],
            accepted  = true,
        }
        plan.sites[index].structure.height = 7
    }
    plan.sites[12] = {
        structure = terrain.structure_make(10, 0, 8, 8, 0, 18),
        kind      = .Landmark,
        accepted  = true,
    }
    plan.sites[13] = {
        structure = terrain.structure_make(20, 0, 8, 8, 0, 4),
        kind      = .Park,
        accepted  = true,
    }
    plan.sites[0].structure.height = 7
    plan.sites[12].structure.height = 18
    plan.sites[13].structure.height = 4
    plan.site_count = 14
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
    plan.village_reason = .Harbor_Fishery
    testing.expect(t, settlement_plan_acceptance_failure(&plan, project) != .Wide_Route_Share)
    plan.metrics.wide_route_share = .33
    testing.expect(t, !settlement_plan_acceptance_valid(&plan, project))
    plan.village_reason = .Route_Stop
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

settlement_large_parks_generate_bounded_fountains :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.request = {
        region = .Adriatic,
        seed   = 73,
    }
    park := terrain.structure_make(4, 7, 18, 14, 0, 12)
    park.kind = .Foliage
    park.seed = 211
    settlement_plan_record_reserved_site(&plan, park, .Park)
    testing.expect_value(t, plan.site_count, 1)
    testing.expect(t, plan.sites[0].fountain_enabled)
    testing.expect(t, plan.sites[0].fountain_radius >= 2.2)
    testing.expect(t, plan.sites[0].fountain_radius < min(park.width, park.depth) * .5)

    small := terrain.structure_make(0, 0, 8, 8, 0, 5)
    settlement_plan_record_reserved_site(&plan, small, .Park)
    testing.expect(t, !plan.sites[1].fountain_enabled)
}

@(test)
settlement_park_groves_reseat_after_terrain_preparation :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    terrain.init_project(project)
    defer delete(project.structures)
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    markov_town_add_grove(project, center, center, 12, 11, 15, 17)
    testing.expect(t, project.structure_count > 0)
    if project.structure_count <= 0 do return
    grove_index := project.structure_count - 1
    plan: Settlement_Plan
    settlement_plan_record_reserved_site(&plan, project.structures[grove_index], .Park)
    original_base_y := project.structures[grove_index].base_y

    terrain.apply_stroke_with_hardness(project, .Raise, center, center, 40, 4, 1, .8)
    prepared_base_y := terrain.sample_height(project, 0, center, center)
    testing.expect(t, prepared_base_y > original_base_y)
    markov_town_reseat_park_groves(&plan, project)

    testing.expect_value(t, project.structures[grove_index].base_y, prepared_base_y)
    testing.expect_value(t, plan.sites[0].structure.base_y, prepared_base_y)
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
settlement_poi_road_network_is_sparse_connected_and_deterministic :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    pois := [5]Settlement_Road_Network_PoI {
        {position = {-70, -35}, required = true},
        {position = {-15, 30}},
        {position = {35, -20}},
        {position = {80, 35}, required = true},
        {position = {5, 85}},
    }
    first, second: Settlement_Plan
    first_rng := settlement_rng_new(91)
    second_rng := settlement_rng_new(91)

    first_connected := settlement_plan_connect_road_network(&first, project, pois[:], &first_rng)
    second_connected := settlement_plan_connect_road_network(&second, project, pois[:], &second_rng)

    testing.expect_value(t, first_connected, len(pois))
    testing.expect_value(t, first.route_count, len(pois) - 1)
    testing.expect_value(t, first.route_count, second.route_count)
    testing.expect(t, settlement_plan_required_routes_connected(&first))
    for route, index in first.routes[:first.route_count] {
        other := second.routes[index]
        testing.expect_value(t, route.geometry.count, other.geometry.count)
        testing.expect(t, !settlement_route_crosses_sea(project, route.geometry))
        testing.expect(t, route.maximum_grade <= settlement_route_grade_limit(.Connector) + .001)
        for point_index in 0 ..< route.geometry.count {
            testing.expect(
                t,
                settlement_route_point_near(route.geometry.points[point_index], other.geometry.points[point_index]),
            )
        }
    }
}

@(test)
settlement_poi_road_network_does_not_force_an_unbuildable_link :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = 0
    terrain.apply_stroke_with_hardness(project, .Raise, -35, 0, 10, 8, 1, .8)
    terrain.apply_stroke_with_hardness(project, .Raise, 35, 0, 10, 8, 1, .8)
    pois := [2]Settlement_Road_Network_PoI {
        {position = {-35, 0}, required = true},
        {position = {35, 0}, required = true},
    }
    plan: Settlement_Plan
    rng := settlement_rng_new(17)

    connected := settlement_plan_connect_road_network(&plan, project, pois[:], &rng)

    testing.expect_value(t, connected, 1)
    testing.expect_value(t, plan.route_count, 0)
}

@(test)
settlement_poi_road_network_terminates_at_existing_street_contact :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    plan: Settlement_Plan
    rng := settlement_rng_new(17)
    street: Settlement_Route
    street.points[0], street.points[1], street.count = [2]f32{0, -30}, [2]f32{0, 30}, 2
    settlement_plan_add_route(&plan, project, street, .Civic_Spine, true, true, &rng)
    pois := [2]Settlement_Road_Network_PoI {
        {position = {-20, 0}, required = true},
        {position = {20, 0}, required = true},
    }

    connected := settlement_plan_connect_road_network(&plan, project, pois[:], &rng)

    testing.expect_value(t, connected, 2)
    testing.expect_value(t, plan.route_count, 2)
    branch := plan.routes[1].geometry
    testing.expect(t, settlement_route_point_near(branch.points[0], pois[1].position))
    testing.expect(t, settlement_route_point_near(branch.points[branch.count - 1], {0, 0}, .1))
    testing.expect(t, settlement_route_length(branch) < 21)
}

settlement_overlapping_roads_are_widened_instead_of_duplicated :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    plan: Settlement_Plan
    rng := settlement_rng_new(17)
    first: Settlement_Route
    first.points[0] = {0, 0}
    first.points[1] = {40, 0}
    first.count = 2
    settlement_plan_add_route(&plan, project, first, .Street, false, true, &rng)
    original_width := plan.routes[0].width

    duplicate := first
    duplicate.points[0][1] = .25
    duplicate.points[1][1] = .25
    settlement_plan_add_route(&plan, project, duplicate, .Civic_Spine, true, true, &rng)

    testing.expect_value(t, plan.route_count, 1)
    testing.expect(t, plan.routes[0].width > original_width)
    testing.expect(t, plan.routes[0].required)
    testing.expect(t, plan.road_badness_count == 1 && plan.road_badness_sum >= SETTLEMENT_ROAD_OVERLAP_REJECT)
}

@(test)
settlement_crossing_roads_are_not_overlap_badness :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    plan: Settlement_Plan
    rng := settlement_rng_new(23)
    horizontal, vertical: Settlement_Route
    horizontal.points[0], horizontal.points[1], horizontal.count = {-30, 0}, {30, 0}, 2
    vertical.points[0], vertical.points[1], vertical.count = {0, -30}, {0, 30}, 2
    settlement_plan_add_route(&plan, project, horizontal, .Street, false, true, &rng)
    settlement_plan_add_route(&plan, project, vertical, .Street, false, true, &rng)

    testing.expect_value(t, plan.route_count, 2)
    testing.expect(t, plan.road_badness_sum < SETTLEMENT_ROAD_OVERLAP_REJECT)
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

settlement_test_village_growth_plan :: proc(seed: u32, reason: Village_Reason) -> Settlement_Plan {
    plan: Settlement_Plan
    plan.request = {
        region = .Adriatic,
        scale  = .Village,
        seed   = seed,
        center = {0, 0},
        radius = 120,
    }
    plan.village_reason = reason
    centers := [4][2]f32{{0, 0}, {-35, 0}, {34, 18}, {4, 42}}
    for center, index in centers {
        plan.neighborhoods[index] = {
            center      = center,
            radius      = 28,
            density     = .28 + f32(index) * .01,
            age         = f32(index) * .07,
            suitability = 1,
            tissue      = .Hillside_Accretion,
        }
    }
    plan.neighborhood_count = len(centers)
    return plan
}

settlement_village_backbone_uses_an_external_anchor_without_macro_cells :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    plan := settlement_test_village_growth_plan(73, .Route_Stop)
    rng := settlement_rng_new(73)

    settlement_plan_build_macro_routes(&plan, project, &rng)

    testing.expect_value(t, plan.macro_cell_count, 0)
    testing.expect(t, plan.growth_event_count >= 1)
    backbone := plan.routes[plan.growth_events[0].route_index].geometry
    root := plan.neighborhoods[0].center
    external := backbone.points[0]
    testing.expect(t, linalg.length(external - root) >= plan.request.radius * .44)
    for neighborhood in plan.neighborhoods[:plan.neighborhood_count] {
        testing.expect(t, !settlement_route_point_near(external, neighborhood.center, 1))
    }
}

@(test)
settlement_growth_topology_does_not_merge_nearby_disconnected_routes :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    plan.request.scale = .Village
    for route_index in 0 ..< 2 {
        plan.routes[route_index].geometry.points[0] = {0, f32(route_index)}
        plan.routes[route_index].geometry.points[1] = {10, f32(route_index)}
        plan.routes[route_index].geometry.count = 2
        plan.routes[route_index].drivable = true
        plan.growth_events[route_index].route_index = route_index
    }
    plan.route_count = 2
    plan.growth_event_count = 2

    topology := settlement_growth_topology(&plan)
    settlement_plan_measure(&plan)

    testing.expect_value(t, topology.node_count, 4)
    testing.expect_value(t, topology.edge_count, 2)
    testing.expect_value(t, plan.metrics.public_component_count, 2)
}

@(test)
settlement_route_frame_filter_keeps_a_cohort_on_its_assigned_edge :: proc(t: ^testing.T) {
    plan: Settlement_Plan
    for route_index in 0 ..< 2 {
        plan.routes[route_index].geometry.points[0] = {-10, f32(route_index * 20)}
        plan.routes[route_index].geometry.points[1] = {10, f32(route_index * 20)}
        plan.routes[route_index].geometry.count = 2
        plan.routes[route_index].drivable = true
        plan.routes[route_index].width = 3
    }
    plan.route_count = 2

    _, _, _, _, _, distance, route_index, found := settlement_nearest_route_frame(&plan, {0, 1}, 1)

    testing.expect(t, found)
    testing.expect_value(t, route_index, 1)
    testing.expect(t, distance > 18)
}

settlement_village_growth_is_deterministic_and_accretive :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    first := settlement_test_village_growth_plan(91, .Route_Stop)
    second := settlement_test_village_growth_plan(91, .Route_Stop)
    first_rng := settlement_rng_new(91)
    second_rng := settlement_rng_new(91)

    settlement_plan_build_village_routes(&first, project, &first_rng)
    settlement_plan_build_village_routes(&second, project, &second_rng)
    settlement_plan_split_route_intersections(&first)
    settlement_plan_split_route_intersections(&second)

    testing.expect(t, first.growth_event_count >= 1 && first.growth_event_count <= 3)
    testing.expect_value(t, first.growth_event_count, second.growth_event_count)
    testing.expect_value(t, first.route_count, second.route_count)
    testing.expect_value(t, first.growth_events[0].kind, Settlement_Growth_Event_Kind.Backbone)
    testing.expect(t, first.routes[first.growth_events[0].route_index].required)
    for event, event_index in first.growth_events[:first.growth_event_count] {
        other := second.growth_events[event_index]
        testing.expect_value(t, event.kind, other.kind)
        testing.expect_value(t, event.target_neighborhood, other.target_neighborhood)
        testing.expect_value(t, event.route_index, other.route_index)
        testing.expect(t, event.kind != .Densification)
        testing.expect(t, settlement_route_point_near(event.frontage_start, other.frontage_start))
        testing.expect(t, settlement_route_point_near(event.frontage_finish, other.frontage_finish))
        if event.kind == .Exploration {
            testing.expect(t, event.route_index > 0)
            route := first.routes[event.route_index].geometry
            joined := false
            for prior in first.routes[:event.route_index] {
                prior_geometry := prior.geometry
                for point in prior_geometry.points[:prior_geometry.count] {
                    if settlement_route_point_near(point, route.points[route.count - 1], 2) {
                        joined = true
                    }
                }
            }
            testing.expect(t, joined)
        }
    }
}

settlement_village_growth_is_a_bounded_tree_for_every_reason_and_region :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    for region in Settlement_Region {
        for reason in Village_Reason {
            plan := settlement_test_village_growth_plan(u32(41 + int(region) * 17 + int(reason)), reason)
            plan.request.region = region
            rng := settlement_rng_new(plan.request.seed)
            settlement_plan_build_village_routes(&plan, project, &rng)
            settlement_plan_split_route_intersections(&plan)
            topology := settlement_growth_topology(&plan)
            testing.expect(t, plan.growth_event_count >= 1 && plan.growth_event_count <= 3)
            testing.expect(t, plan.routes[plan.growth_events[0].route_index].required)
            testing.expect_value(t, topology.edge_count - topology.node_count + 1, 0)
            for node_index in 0 ..< topology.node_count {
                degree := 0
                for edge in topology.edges[:topology.edge_count] {
                    if edge[0] == node_index || edge[1] == node_index do degree += 1
                }
                testing.expect(t, degree <= 3)
            }
        }
    }
}

@(test)
settlement_village_growth_preserves_the_required_backbone_at_optional_capacity :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100
    plan := settlement_test_village_growth_plan(17, .Upland_Pastoral)
    // Leave room for exactly the required route; all exploration is optional.
    plan.route_count = SETTLEMENT_PLANNED_ROUTE_CAPACITY - 1
    rng := settlement_rng_new(17)

    settlement_plan_build_village_routes(&plan, project, &rng)

    testing.expect_value(t, plan.route_count, SETTLEMENT_PLANNED_ROUTE_CAPACITY)
    testing.expect_value(t, plan.growth_event_count, 1)
    testing.expect_value(t, plan.growth_events[0].kind, Settlement_Growth_Event_Kind.Backbone)
    testing.expect(t, plan.routes[plan.growth_events[0].route_index].required)
}

@(test)
settlement_route_submersion_checks_segments_not_only_vertices :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = 0
    terrain.apply_stroke_with_hardness(project, .Raise, -30, 0, 9, 30, 1, .8)
    terrain.apply_stroke_with_hardness(project, .Raise, 30, 0, 9, 30, 1, .8)
    route: Settlement_Route
    route.points[0] = {-30, 0}
    route.points[1] = {30, 0}
    route.count = 2
    testing.expect(t, terrain.sample_height(project, 0, -30, 0) > project.sea_level + .45)
    testing.expect(t, terrain.sample_height(project, 0, 30, 0) > project.sea_level + .45)
    testing.expect(t, settlement_route_crosses_sea(project, route))
}

@(test)
settlement_routes_split_preexisting_main_roads_into_shared_junctions :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    project.sea_level = -100
    from := roads.add_node(&project.road_graph, {-40, 0, 0}, 4)
    to := roads.add_node(&project.road_graph, {40, 0, 0}, 4)
    _ = roads.add_straight_edge(&project.road_graph, from, to, 8, 2, .Asphalt)
    plan: Settlement_Plan
    plan.routes[0] = {
        geometry = {points = {0 = {0, -30}, 1 = {0, 30}}, count = 2},
        class = .Street,
        width = 5,
        shoulder = 1,
        pavement = .Cobblestone,
        drivable = true,
    }
    plan.route_count = 1

    settlement_plan_split_project_road_intersections(&plan, project)

    testing.expect_value(t, project.road_graph.node_count, 3)
    testing.expect_value(t, project.road_graph.edge_count, 2)
    testing.expect_value(t, plan.routes[0].geometry.count, 3)
    junction := project.road_graph.nodes[2].position
    testing.expect(t, math.abs(junction.x) < .01 && math.abs(junction.z) < .01)
    testing.expect(t, settlement_route_point_near(plan.routes[0].geometry.points[1], {junction.x, junction.z}))

    settlement_plan_commit_routes(&plan, project)
    testing.expect_value(t, roads.node_degree(&project.road_graph, 2), 4)
}

@(test)
settlement_road_gateways_split_regional_roads_before_route_planning :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    project.sea_level = -100
    west := roads.add_node(&project.road_graph, {-100, 0, 0}, 4)
    east := roads.add_node(&project.road_graph, {100, 0, 0}, 4)
    _ = roads.add_straight_edge(&project.road_graph, west, east, 8, 2, .Asphalt)
    plan: Settlement_Plan
    plan.request = {
        center = {0, 0},
        radius = 60,
        scale  = .Town,
    }
    gateways: [SETTLEMENT_ROAD_GATEWAY_CAPACITY][2]f32

    count := settlement_plan_road_gateways(&plan, project, &gateways)

    testing.expect_value(t, count, 2)
    testing.expect_value(t, project.road_graph.node_count, 4)
    testing.expect_value(t, project.road_graph.edge_count, 3)
    testing.expect(t, linalg.length(gateways[0] - gateways[1]) >= 27)
    for gateway in gateways[:count] {
        testing.expect(t, math.abs(gateway[1]) < .01)
        testing.expect(t, math.abs(linalg.length(gateway) - plan.request.radius * .72) < 10)
    }
    local_route: Settlement_Route
    local_route.points[0], local_route.points[1], local_route.count = gateways[0], gateways[0] + [2]f32{0, 30}, 2
    settlement_route_commit(project, local_route, 5, 1, .Cobblestone)
    joined_node := -1
    for node, node_index in project.road_graph.nodes[:project.road_graph.node_count] {
        if settlement_route_point_near({node.position.x, node.position.z}, gateways[0], .01) {
            joined_node = node_index
            break
        }
    }
    testing.expect(t, joined_node >= 0)
    testing.expect_value(t, roads.node_degree(&project.road_graph, joined_node), 3)
}

@(test)
settlement_route_commit_does_not_merge_distinct_nearby_junctions :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    project.sea_level = -100
    existing := roads.add_node(&project.road_graph, {1.5, 0, 0}, 4)
    route: Settlement_Route
    route.points[0], route.points[1], route.count = {0, 0}, {0, 20}, 2

    settlement_route_commit(project, route, 5, 1, .Cobblestone)

    testing.expect_value(t, project.road_graph.node_count, 3)
    testing.expect(t, project.road_graph.edges[0].from != existing)
}

@(test)
settlement_streets_preserve_grade_safe_route_waypoints :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100

    route := settlement_route_find(project, -80, 0, 80, 0, .Street)

    testing.expect(t, route.count >= 2)
    maximum_grade := f32(0)
    for index in 0 ..< route.count - 1 {
        a, b := route.points[index], route.points[index + 1]
        distance := linalg.length(b - a)
        grade :=
            math.abs(terrain.sample_height(project, 0, b[0], b[1]) - terrain.sample_height(project, 0, a[0], a[1])) /
            distance
        maximum_grade = max(maximum_grade, grade)
    }
    testing.expect(t, maximum_grade <= settlement_route_grade_limit(.Street) + .001)
}

@(test)
settlement_connectors_preserve_grade_safe_route_waypoints :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    project.sea_level = -100

    route := settlement_route_find(project, -80, 0, 80, 0, .Connector)

    testing.expect(t, route.count >= 2)
    _, _, maximum_grade := settlement_route_length_and_grade(project, route)
    testing.expect(t, maximum_grade <= settlement_route_grade_limit(.Connector) + .001)
    testing.expect_value(t, settlement_route_grade_limit(.Stair), f32(.65))
}

@(test)
settlement_connectors_wind_across_steep_contours :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    project.sea_level = -100
    level := &project.levels[0]
    level.cell_size, level.origin_x, level.origin_z = .5, -80, -80
    for z in 0 ..< terrain.RING_RESOLUTION {
        for x in 0 ..< terrain.RING_RESOLUTION {
            world_x := level.origin_x + f32(x) * level.cell_size
            level.heights[terrain.sample_index(x, z)] = 20 + world_x * .15
        }
    }

    route := settlement_route_find(project, -30, 0, 30, 0, .Connector)

    testing.expect(t, route.count > 2)
    length, _, maximum_grade := settlement_route_length_and_grade(project, route)
    testing.expect(t, length > 75)
    testing.expect(t, maximum_grade <= settlement_route_grade_limit(.Connector) + .001)
    maximum_wander := f32(0)
    for point in route.points[:route.count] {
        maximum_wander = max(maximum_wander, math.abs(point[1]))
    }
    testing.expect(t, maximum_wander > 10)
}

@(test)
settlement_route_cost_samples_the_graded_cross_section :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    project.sea_level = -100
    level := &project.levels[0]
    level.cell_size, level.origin_x, level.origin_z = .5, -80, -80
    for z in 0 ..< terrain.RING_RESOLUTION {
        for x in 0 ..< terrain.RING_RESOLUTION {
            world_x := level.origin_x + f32(x) * level.cell_size
            level.heights[terrain.sample_index(x, z)] = world_x * .2
        }
    }

    // Both centerlines have a perfectly smooth profile. The contour-aligned
    // segment nevertheless crosses the hillside transversely and therefore
    // needs substantially more cut/fill across its full roadbed.
    across_slope := settlement_route_construction_cost(project, {-20, 0}, {20, 0}, 5)
    along_contour := settlement_route_construction_cost(project, {0, -20}, {0, 20}, 5)

    testing.expect(t, across_slope.cut + across_slope.fill < .01)
    testing.expect(t, along_contour.cut > 20)
    testing.expect(t, along_contour.fill > 20)
    testing.expect(t, along_contour.cross_slope > .15)
}

@(test)
settlement_short_street_detours_instead_of_accepting_an_over_grade_chord :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    project.sea_level = -100
    level := &project.levels[0]
    level.cell_size, level.origin_x, level.origin_z = .25, -20, -20
    for z in 0 ..< terrain.RING_RESOLUTION {
        for x in 0 ..< terrain.RING_RESOLUTION {
            world_x := level.origin_x + f32(x) * level.cell_size
            level.heights[terrain.sample_index(x, z)] = world_x * .15
        }
    }

    route := settlement_route_find(project, 0, 0, 8, 0, .Street)
    testing.expect(t, route.count > 2)
    maximum_grade := f32(0)
    for index in 0 ..< route.count - 1 {
        a, b := route.points[index], route.points[index + 1]
        distance := linalg.length(b - a)
        grade :=
            math.abs(terrain.sample_height(project, 0, b[0], b[1]) - terrain.sample_height(project, 0, a[0], a[1])) /
            max(distance, f32(.01))
        maximum_grade = max(maximum_grade, grade)
    }
    testing.expect(t, maximum_grade <= settlement_route_grade_limit(.Street) + .001)
}

settlement_access_routes_classify_steep_terrain_as_stairs :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    terrain.apply_stroke_with_hardness(project, .Raise, 5, 0, 6, 30, 1, .8)

    geometry: Settlement_Route
    geometry.points[0], geometry.points[1], geometry.count = {-5, 0}, {5, 0}, 2
    rise := math.abs(
        terrain.sample_height(project, 0, geometry.points[1][0], geometry.points[1][1]) -
        terrain.sample_height(project, 0, geometry.points[0][0], geometry.points[0][1]),
    )
    testing.expect(t, rise / 10 >= .18)

    plan: Settlement_Plan
    settlement_plan_import_access_route(&plan, project, geometry, 1.2)

    testing.expect_value(t, plan.route_count, 1)
    testing.expect_value(t, plan.routes[0].class, Settlement_Route_Class.Stair)
    testing.expect_value(t, plan.access_stair_routes, 1)
    testing.expect_value(t, plan.access_excessive_grades, 0)
}

@(test)
settlement_access_route_class_uses_shared_stair_threshold :: proc(t: ^testing.T) {
    testing.expect_value(
        t,
        settlement_access_route_class(SETTLEMENT_ACCESS_STAIR_GRADE - .001, 1.2),
        Settlement_Route_Class.Alley,
    )
    testing.expect_value(
        t,
        settlement_access_route_class(SETTLEMENT_ACCESS_STAIR_GRADE, 1.2),
        Settlement_Route_Class.Stair,
    )
    testing.expect_value(t, settlement_access_route_class(.05, 2), Settlement_Route_Class.Lane)
}

@(test)
settlement_access_surfaces_follow_use_width_and_network_demand :: proc(t: ^testing.T) {
    cottage := architecture.City_Alley {
        half_width       = .5,
        household_demand = 1,
    }
    public_approach := architecture.City_Alley {
        half_width       = .8,
        household_demand = 1,
    }
    shared_path := architecture.City_Alley {
        half_width       = .5,
        household_demand = 2,
    }
    shared_trunk := architecture.City_Alley {
        half_width       = .8,
        household_demand = 4,
    }
    testing.expect_value(t, settlement_access_surface(cottage), Settlement_Access_Surface.Packed_Earth)
    testing.expect_value(t, settlement_access_surface(public_approach), Settlement_Access_Surface.Gravel)
    testing.expect_value(t, settlement_access_surface(shared_path), Settlement_Access_Surface.Gravel)
    testing.expect_value(t, settlement_access_surface(shared_trunk), Settlement_Access_Surface.Stone)
    testing.expect_value(t, settlement_access_route_pavement(.05, 1.2), roads.Pavement.Dirt)
    testing.expect_value(t, settlement_access_route_pavement(.05, 1.6), roads.Pavement.Gravel)
    testing.expect_value(t, settlement_access_route_pavement(SETTLEMENT_ACCESS_STAIR_GRADE, 1.2), roads.Pavement.Steps)
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
    testing.expect(t, math.abs(focus.x - 50) < .01)
    testing.expect(t, math.abs(focus.z - 10) < .01)
    testing.expect_value(t, focus.y, terrain.sample_height(project, 0, focus.x, focus.z))
    testing.expect(t, height > 127 && height < 130)
}

@(test)
settlement_terrain_edits_measure_cut_and_fill :: proc(t: ^testing.T) {
    target, cut, fill := settlement_cut_fill_estimate({0, 2, 4, 2, 2}, 100)
    testing.expect_value(t, target, f32(2))
    testing.expect_value(t, cut, f32(40))
    testing.expect_value(t, fill, f32(40))
}

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

@(test)
generated_plants_select_detail_from_camera_distance :: proc(t: ^testing.T) {
    plant := third_person.Vec3{10, 40, -8}
    testing.expect_value(t, generated_plant_render_lod({10, -100, -8}, plant), Generated_Plant_Render_LOD.Hero)
    testing.expect_value(t, generated_plant_render_lod({17.99, 400, -8}, plant), Generated_Plant_Render_LOD.Hero)
    testing.expect_value(t, generated_plant_render_lod({18, 40, -8}, plant), Generated_Plant_Render_LOD.Near)
    testing.expect_value(t, generated_plant_render_lod({42, 40, -8}, plant), Generated_Plant_Render_LOD.Medium)
    testing.expect_value(t, generated_plant_render_lod({82, 40, -8}, plant), Generated_Plant_Render_LOD.Far)
    testing.expect_value(t, generated_plant_render_lod({154, 40, -8}, plant), Generated_Plant_Render_LOD.Distant)
    testing.expect_value(t, generated_plant_catalog_detail(.Hero), plants.Detail_Level.Near)
    testing.expect_value(t, generated_plant_catalog_detail(.Near), plants.Detail_Level.Near)
    testing.expect_value(t, generated_plant_catalog_detail(.Medium), plants.Detail_Level.Medium)
    testing.expect_value(t, generated_plant_catalog_detail(.Far), plants.Detail_Level.Far)
    testing.expect_value(t, generated_plant_catalog_detail(.Distant), plants.Detail_Level.Far)
    testing.expect(t, generated_plant_uses_hero_geometry(.Hero))
    testing.expect(t, !generated_plant_uses_hero_geometry(.Near))
    testing.expect(t, !generated_plant_uses_hero_geometry(.Medium))
    testing.expect(t, !generated_plant_uses_hero_geometry(.Far))
    testing.expect(t, !generated_plant_uses_hero_geometry(.Distant))
    testing.expect_value(t, generated_plant_apply_detail_floor(.Near, .Medium), plants.Detail_Level.Medium)
    testing.expect_value(t, generated_plant_apply_detail_floor(.Far, .Medium), plants.Detail_Level.Far)
    graded := generated_plant_point({4, 10, 7}, {2, 1, 0}, 0, 1, .25)
    testing.expect(t, abs(graded.x - 6) < .001)
    testing.expect(t, abs(graded.y - 11.5) < .001)
    testing.expect(t, abs(graded.z - 7) < .001)
    testing.expect_value(t, generated_plant_maturity_step(.59), u8(3))
    testing.expect_value(t, generated_plant_maturity_step(.81), u8(4))
    testing.expect_value(t, generated_plant_maturity_step(1.2), u8(5))
    testing.expect(t, abs(generated_plant_maturity_value(4) - .8) < .001)
    testing.expect(t, farmland_vineyard_heights_are_safe(10, {9.4, 10.6, 9.2, 10.8}))
    testing.expect(t, !farmland_vineyard_heights_are_safe(10, {7.9, 10.2, 10, 10}))
    testing.expect(t, !farmland_vineyard_heights_are_safe(10, {8.7, 11.3, 10, 10}))
    testing.expect(t, abs(farmland_vineyard_support_width(1) - 4.6) < .001)
    testing.expect(t, abs(farmland_vineyard_support_width(2) - 9.2) < .001)
    testing.expect_value(t, farmland_vineyard_render_mode(33.99), Farmland_Vineyard_Render_Mode.Generated_Medium)
    testing.expect_value(t, farmland_vineyard_render_mode(34), Farmland_Vineyard_Render_Mode.Generated_Far)
    testing.expect_value(t, farmland_vineyard_render_mode(58), Farmland_Vineyard_Render_Mode.Foliage)
}
