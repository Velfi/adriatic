package tests

import harbor "../packages/harbor"
import terrain "../packages/terrain"
import "core:testing"

@(test)
shoreline_harbor_is_deterministic_and_world_space :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    terrain.init_project(project)
    center, _ := terrain.default_island_center(f32(-1))
    radius := f32(terrain.WORLD_SIZE_METERS * .5) * terrain.DEFAULT_ISLAND_RADIUS
    anchor := harbor.Vec2{center + radius * .70710678, center + radius * .70710678}
    site := harbor.analyze_coast(project, anchor, 260)
    testing.expect(t, site.valid)
    a := harbor.generate_for_coast(project, &site, .Town, 7123)
    b := harbor.generate_for_coast(project, &site, .Town, 7123)
    testing.expect(t, a.valid)
    testing.expect_value(t, a, b)
    testing.expect(t, a.diagnostics.footprint_diameter >= harbor.MIN_DIAMETER_METERS)
    testing.expect(t, a.structure_count >= 2)
    testing.expect(t, a.berth_count >= 6)
    testing.expect_value(t, a.diagnostics.mooring_lattice_matches, 0)
    testing.expect(t, a.terrain_edit_count <= harbor.TERRAIN_EDIT_CAPACITY)
}

@(test)
shoreline_harbor_seed_changes_layout :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    terrain.init_project(project)
    center, _ := terrain.default_island_center(f32(1))
    radius := f32(terrain.WORLD_SIZE_METERS * .5) * terrain.DEFAULT_ISLAND_RADIUS
    anchor := harbor.Vec2{center - radius * .70710678, center - radius * .70710678}
    site := harbor.analyze_coast(project, anchor, 320)
    testing.expect(t, site.valid)
    a := harbor.generate_for_coast(project, &site, .Village, 41)
    b := harbor.generate_for_coast(project, &site, .Village, 99)
    testing.expect(t, a.valid)
    testing.expect(t, b.valid)
    testing.expect(t, a.berths != b.berths || a.structures != b.structures)
}

@(test)
human_built_harbor_pipeline_is_deterministic :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    terrain.init_project(project)
    center, _ := terrain.default_island_center(f32(-1))
    survey := harbor.survey_coast(project, {center, center}, 720)
    testing.expect(t, survey.site_count > 0)
    program := harbor.derive_harbor_program(.Town, 1400, 0xadd1)
    site := harbor.select_harbor_site(project, &survey, &program, 0xadd1)
    testing.expect(t, site.valid)
    a := harbor.generate_intervention(project, &site, &program, 0xadd1)
    b := harbor.generate_intervention(project, &site, &program, 0xadd1)
    testing.expect(t, a.valid)
    testing.expect_value(t, a, b)
    testing.expect(t, a.phase_count > 0)
    testing.expect(t, a.waterfront_count >= 2)
    testing.expect(t, a.achieved_capacity >= program.minimum_capacity)
    testing.expect_value(t, harbor.finalize_intervention(&a), a.runtime_plan)
}

@(test)
intervention_strategy_respects_coast_and_budget :: proc(t: ^testing.T) {
    program := harbor.derive_harbor_program(.Village, 360, 17)
    exposed := harbor.Harbor_Site {
        valid             = true,
        exposure_score    = .92,
        curvature_score   = -.18,
        slope_score       = .7,
        open_water_score  = .8,
        construction_cost = program.construction_budget * 2,
    }
    strategy, downgraded, _ := harbor.choose_strategy(&exposed, &program)
    testing.expect_value(t, strategy, harbor.Harbor_Strategy.Beach_Landing)
    testing.expect(t, downgraded)

    cove := exposed
    cove.opportunity = .Cove
    cove.exposure_score = .6
    cove.curvature_score = .3
    cove.slope_score = .2
    cove.preferred_scale = 260
    cove.backland_score = .8
    cove.construction_cost = program.construction_budget * .25
    strategy, downgraded, _ = harbor.choose_strategy(&cove, &program)
    testing.expect(t, strategy == .Shoreline_Quay || strategy == .Single_Hooked_Mole)
    testing.expect(t, !downgraded)
}

@(test)
harbor_structures_are_supported_by_the_shore :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    terrain.init_project(project)
    center, _ := terrain.default_island_center(f32(1))
    survey := harbor.survey_coast(project, {center, center}, 720)
    program := harbor.derive_harbor_program(.Working_Port, 2100, 0x51de)
    intervention := harbor.generate_for_survey(project, &survey, &program, 0x51de)
    testing.expect(t, intervention.valid)
    site := intervention.site
    routed: [harbor.BERTH_CAPACITY]bool
    breakwater_count := 0
    for &structure in intervention.runtime_plan.structures[:intervention.runtime_plan.structure_count] {
        if structure.kind == .Quay {
            testing.expect(t, structure.count >= 6)
            for index in 1 ..< structure.count {
                testing.expect(t, harbor.distance(structure.points[index - 1], structure.points[index]) <= 24)
            }
        } else if structure.kind == .Breakwater {
            breakwater_count += 1
            landfall := structure.points[0]
            testing.expect(t, terrain.sample_surface_height(project, 0, landfall.x, landfall.z) > project.sea_level)
            local := harbor.world_to_local(site.anchor, site.tangent, site.outward, landfall)
            harborward_sign := local.x < 0 ? f32(1) : f32(-1)
            testing.expect(
                t,
                harbor.breakwater_path_is_sound(project, &site, harborward_sign, ..structure.points[:structure.count]),
            )
        }
    }
    for structure, structure_index in intervention.runtime_plan.structures[:intervention.runtime_plan.structure_count] {
        if structure.kind != .Pier do continue
        tip := structure.points[structure.count - 1]
        testing.expect(t, terrain.sample_surface_height(project, 0, tip.x, tip.z) <= project.sea_level + .2)
        for other in intervention.runtime_plan.structures[structure_index + 1:intervention.runtime_plan.structure_count] {
            for a_index in 0 ..< structure.count - 1 {
                for b_index in 0 ..< other.count - 1 {
                    testing.expect(
                        t,
                        !harbor.segments_cross(
                            structure.points[a_index],
                            structure.points[a_index + 1],
                            other.points[b_index],
                            other.points[b_index + 1],
                        ),
                    )
                }
            }
        }
    }
    for route in intervention.runtime_plan.routes[:intervention.runtime_plan.route_count] {
        testing.expect(t, route.berth_index >= 0 && route.berth_index < intervention.runtime_plan.berth_count)
        testing.expect(t, !routed[route.berth_index])
        routed[route.berth_index] = true
        berth := intervention.runtime_plan.berths[route.berth_index]
        testing.expect(t, berth.occupied)
        testing.expect(t, harbor.distance(route.points[route.count - 1], berth.position) <= 1)
    }
    for berth, berth_index in intervention.runtime_plan.berths[:intervention.runtime_plan.berth_count] {
        if berth.occupied do testing.expect(t, routed[berth_index])
        if berth.kind == .Slip do testing.expect(t, harbor.slip_has_structure_support(&intervention.runtime_plan, berth))
    }
    if intervention.strategy == .Single_Hooked_Mole do testing.expect_value(t, breakwater_count, 1)
    if intervention.strategy == .Offset_Twin_Moles do testing.expect_value(t, breakwater_count, 2)
}

@(test)
coastal_survey_covers_distance_and_scale_strata :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    terrain.init_project(project)
    center, _ := terrain.default_island_center(f32(-1))
    survey := harbor.survey_coast(project, {center, center}, 720)
    testing.expect(t, survey.site_count > 0)
    for count in survey.ring_valid_counts do testing.expect(t, count > 0)
    testing.expect(t, survey.minimum_scale <= 180)
    testing.expect(t, survey.maximum_scale >= 440)
}

@(test)
human_built_harbor_seed_suite_meets_acceptance_rate :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    terrain.init_project(project)
    center, _ := terrain.default_island_center(f32(1))
    survey := harbor.survey_coast(project, {center, center}, 720)
    accepted := 0
    suite_count := 20
    for suite_index in 0 ..< suite_count {
        seed := u32(0x7000 + suite_index * 977)
        program := harbor.derive_harbor_program(.Town, 1250, seed)
        intervention := harbor.generate_for_survey(project, &survey, &program, seed)
        if intervention.valid do accepted += 1
    }
    testing.expect(t, accepted * 5 >= suite_count * 4)
}

@(test)
ranked_coastal_site_trials_are_deterministic :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    terrain.init_project(project)
    center, _ := terrain.default_island_center(f32(-1))
    survey := harbor.survey_coast(project, {center, center}, 720)
    program := harbor.derive_harbor_program(.Working_Port, 2400, 0x4411)
    a := harbor.generate_for_survey(project, &survey, &program, 0x4411)
    b := harbor.generate_for_survey(project, &survey, &program, 0x4411)
    testing.expect(t, a.valid)
    testing.expect_value(t, a, b)
    testing.expect(t, a.site.valid)
}

@(test)
terrain_edits_follow_final_intervention_strategy :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    terrain.init_project(project)
    center, _ := terrain.default_island_center(f32(1))

    base := harbor.Harbor_Intervention {
        program = {construction_budget = .6},
        runtime_plan = {
            diagnostics = {footprint_diameter = 240},
            terrain_edits = {
                0 = {.Dredge, {center, center}, 3, project.sea_level - 1.2, 4},
                1 = {.Fill, {center + 40, center}, 3, project.sea_level + .18, 4},
            },
            terrain_edit_count = 2,
        },
    }

    anchorage := base
    anchorage.strategy = .Natural_Anchorage
    harbor.shape_terrain_edits_for_strategy(project, &anchorage)
    testing.expect_value(t, anchorage.runtime_plan.terrain_edit_count, 0)
    testing.expect_value(t, anchorage.terrain_edit_area, f32(0))

    quay := base
    quay.strategy = .Shoreline_Quay
    harbor.shape_terrain_edits_for_strategy(project, &quay)
    testing.expect_value(t, quay.runtime_plan.terrain_edit_count, 1)
    testing.expect_value(t, quay.runtime_plan.terrain_edits[0].kind, harbor.Terrain_Edit_Kind.Fill)
    testing.expect_value(t, quay.dredged_area, f32(0))
    testing.expect(t, quay.terrain_edit_area <= quay.terrain_area_limit)
    testing.expect(t, quay.cut_volume + quay.fill_volume <= quay.terrain_volume_limit)

    dredged := base
    dredged.strategy = .Dredged_Basin
    harbor.shape_terrain_edits_for_strategy(project, &dredged)
    testing.expect_value(t, dredged.runtime_plan.terrain_edit_count, 2)
    testing.expect(t, dredged.dredged_area > 0)
    testing.expect(t, dredged.terrain_edit_area <= dredged.terrain_area_limit)
}

@(test)
minimum_intervention_strategy_matrix :: proc(t: ^testing.T) {
    village := harbor.derive_harbor_program(.Village, 160, 1)
    town := harbor.derive_harbor_program(.Town, 900, 2)
    working_medium := harbor.derive_harbor_program(.Working_Port, 1500, 3)
    working := harbor.derive_harbor_program(.Working_Port, 3000, 3)

    sheltered := harbor.Harbor_Site {
        valid             = true,
        preferred_scale   = 260,
        open_water_score  = .85,
        backland_score    = .75,
        exposure_score    = .18,
        slope_score       = .25,
        construction_cost = .12,
        opportunity       = .Cove,
        curvature_score   = .28,
    }
    strategy, downgraded, _ := harbor.choose_strategy(&sheltered, &village)
    testing.expect_value(t, strategy, harbor.Harbor_Strategy.Natural_Anchorage)
    testing.expect(t, !downgraded)

    headland := sheltered
    headland.preferred_scale = 350
    headland.exposure_score = .60
    headland.curvature_score = -.15
    headland.opportunity = .Headland
    strategy, _, _ = harbor.choose_strategy(&headland, &town)
    testing.expect_value(t, strategy, harbor.Harbor_Strategy.Single_Hooked_Mole)

    bay := sheltered
    bay.preferred_scale = 400
    bay.exposure_score = .55
    bay.curvature_score = .20
    bay.opportunity = .Cove
    strategy, _, _ = harbor.choose_strategy(&bay, &town)
    testing.expect_value(t, strategy, harbor.Harbor_Strategy.Offset_Twin_Moles)

    shelf := sheltered
    shelf.preferred_scale = 450
    shelf.open_water_score = .50
    shelf.exposure_score = .55
    shelf.curvature_score = 0
    shelf.opportunity = .Open_Coast
    strategy, _, _ = harbor.choose_strategy(&shelf, &working_medium)
    testing.expect_value(t, strategy, harbor.Harbor_Strategy.Dredged_Basin)

    reclaimed := sheltered
    reclaimed.preferred_scale = 450
    reclaimed.open_water_score = .82
    reclaimed.backland_score = .60
    reclaimed.exposure_score = .65
    reclaimed.curvature_score = 0
    reclaimed.slope_score = .70
    reclaimed.opportunity = .Open_Coast
    strategy, _, _ = harbor.choose_strategy(&reclaimed, &working)
    testing.expect_value(t, strategy, harbor.Harbor_Strategy.Reclaimed_Port)
}

@(test)
navigable_envelope_follows_shore_and_stops_at_land :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    terrain.init_project(project)
    center, _ := terrain.default_island_center(f32(-1))
    radius := f32(terrain.WORLD_SIZE_METERS * .5) * terrain.DEFAULT_ISLAND_RADIUS
    site := harbor.analyze_coast(project, {center + radius * .7, center + radius * .7}, 280)
    testing.expect(t, site.valid)

    plan: harbor.Harbor_Plan
    harbor.build_water_envelope(&plan, project, &site, 280, 19)
    testing.expect_value(t, plan.navigable_water.count, 40)
    for index in 0 ..< 20 {
        fraction := f32(index) / 19
        shore := harbor.shoreline_sample(&site, fraction)
        inner := plan.navigable_water.points[index]
        testing.expect(t, abs(harbor.distance(shore, inner) - 7) < .1)
    }
    for point in plan.navigable_water.points[:plan.navigable_water.count] {
        testing.expect(t, point.x >= plan.bounds.minimum.x && point.x <= plan.bounds.maximum.x)
        testing.expect(t, point.z >= plan.bounds.minimum.z && point.z <= plan.bounds.maximum.z)
    }
    for sample_index in 0 ..= 10 {
        fraction := f32(sample_index) / 10
        extent := harbor.water_ray_extent(project, &site, fraction, 150)
        testing.expect(t, extent >= 7 && extent <= 150)
        shore := harbor.shoreline_sample(&site, fraction)
        outward := harbor.shoreline_outward(&site, fraction)
        endpoint := harbor.add(shore, harbor.scale(outward, extent))
        testing.expect(t, terrain.sample_surface_height(project, 0, endpoint.x, endpoint.z) <= project.sea_level + .08)
        if extent < 149 {
            obstruction := harbor.add(shore, harbor.scale(outward, extent + 5))
            testing.expect(
                t,
                terrain.sample_surface_height(project, 0, obstruction.x, obstruction.z) > project.sea_level + .08,
            )
        }
    }
}
