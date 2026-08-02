package main

import harbor "../packages/harbor"
import marina "../packages/marina"
import story "../packages/story"
import terrain "../packages/terrain"
import "core:math"

default_marina_find_access_route :: proc(
    project: ^terrain.Project,
    town_x, town_z: f32,
    plan: ^marina.Plan,
    harbor_plan: ^harbor.Harbor_Plan,
) -> (
    Settlement_Route,
    bool,
) {
    if project == nil || plan == nil || !plan.valid do return Settlement_Route{}, false
    office := marina.plan_world_position(plan, plan.office)
    candidates: [14]harbor.Vec2
    candidates[0] = {office.x, office.z}
    if harbor_plan != nil && harbor_plan.valid {
        candidates[0] = harbor_plan.settlement_connection
        candidates[1] = {office.x, office.z}
    }
    // Generated harbor fills can move the nominal connection onto a steep or
    // wet cell. Walk a bounded distance inland toward town while remaining in
    // the same waterfront district, and choose the first terrain-safe route.
    start_index := harbor_plan != nil && harbor_plan.valid ? 2 : 1
    toward_town := harbor.Vec2{town_x - office.x, town_z - office.z}
    toward_town_length := f32(math.sqrt(f64(toward_town.x * toward_town.x + toward_town.z * toward_town.z)))
    if toward_town_length > .001 {
        toward_town.x /= toward_town_length
        toward_town.z /= toward_town_length
    }
    for index in start_index ..< len(candidates) {
        inland_distance := min(f32(index - start_index + 1) * 20, f32(240))
        candidates[index] = {office.x + toward_town.x * inland_distance, office.z + toward_town.z * inland_distance}
    }
    sign := town_x < 0 ? f32(-1) : f32(1)
    island_x, island_z := terrain.default_island_center(sign)
    origins := [2]harbor.Vec2{{town_x, town_z}, {island_x, island_z}}
    for origin in origins {
        for candidate in candidates {
            route, valid := default_marina_access_route(project, origin.x, origin.z, candidate.x, candidate.z)
            if valid do return route, true
        }
    }
    return Settlement_Route{}, false
}

seed_default_island_marinas_seeded :: proc(editor: ^Editor, island_seeds: [len(terrain.DEFAULT_ISLAND_SEEDS)]u32) {
    if editor == nil do return
    editor.default_marina_count = 0
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    island_radius := half_extent * terrain.DEFAULT_ISLAND_RADIUS
    for sign, island_index in terrain.DEFAULT_ISLAND_SIGNS {
        center, _ := terrain.default_island_center(sign)
        marina_x, marina_z := terrain.default_marina_direction(sign)
        // Move from the island center toward the channel between the islands.
        // The site search then rotates the full marina footprint to match the
        // locally sampled shoreline rather than assuming a circular coast.
        town_x, town_z := terrain.default_town_center_for_project(&editor.project, sign)
        plan: marina.Plan
        intervention: harbor.Harbor_Intervention
        seed := terrain.default_island_feature_seed_for(island_seeds[island_index], 0x4d415249)
        // Irregular generated coasts do not guarantee that the channel-facing
        // ray is the best harbor frontage. Sweep nearby aspects and seeds
        // until both the marina layout and coastal intervention agree.
        for attempt in 0 ..< 16 {
            // Try the channel aspect first, then survey the complete generated
            // coastline; a dramatic cove is allowed to move the marina.
            angle := attempt == 0 ? f32(0) : f32(attempt - 1) * math.TAU / 15
            cosine, sine := math.cos(angle), math.sin(angle)
            direction_x := marina_x * cosine - marina_z * sine
            direction_z := marina_x * sine + marina_z * cosine
            shoreline_anchor := markov_marina_find_shoreline_along_ray(
                &editor.project,
                {center, center},
                {direction_x, direction_z},
                island_radius * 2.2,
            )
            candidate_seed := seed + u32(attempt) * 0x9e3779b9
            candidate, _, _ := markov_marina_generate_world_plan(&editor.project, shoreline_anchor, candidate_seed)
            town := harbor.Vec2{town_x, town_z}
            if !default_marina_plan_clears_town(&candidate, town) do continue
            survey := harbor.survey_coast(&editor.project, {town_x, town_z}, 720)
            default_marina_filter_candidate_coast(&survey, &candidate)
            program := harbor.derive_harbor_program(.Town, 960 + island_index * 420, candidate_seed)
            candidate_intervention := harbor.generate_for_survey(&editor.project, &survey, &program, candidate_seed)
            if !candidate_intervention.valid do continue
            plan = candidate
            intervention = candidate_intervention
            break
        }
        if !plan.valid do continue
        harbor_plan: harbor.Harbor_Plan
        if intervention.valid {
            harbor.apply_harbor_terrain(&editor.project, &intervention)
            harbor_plan = harbor.finalize_intervention(&intervention)
        }
        // Reserve the town-to-waterfront route before settlement generation
        // consumes the remaining road graph capacity.
        access, access_valid := default_marina_find_access_route(&editor.project, town_x, town_z, &plan, &harbor_plan)
        if !access_valid do continue
        settlement_route_commit(&editor.project, access, 6, 1.25, .Cobblestone, .9)
        editor.default_marinas[editor.default_marina_count] = plan
        editor.default_harbors[editor.default_marina_count] = harbor_plan
        editor.default_harbor_interventions[editor.default_marina_count] = intervention
        editor.default_marina_islands[editor.default_marina_count] = sign > 0 ? story.Island.East : story.Island.West
        editor.default_marina_count += 1
    }
}

seed_default_island_marinas :: proc(editor: ^Editor) {
    seed_default_island_marinas_seeded(editor, terrain.DEFAULT_ISLAND_SEEDS)
}

capture_target_is_storefront_night :: proc(target: string) -> bool {
    prefix := "storefront-night-display-"
    return(
        target == "storefront-night" ||
        target == "storefront-night-storm" ||
        target == "storefront-generated-night" ||
        (len(target) > len(prefix) && target[:len(prefix)] == prefix) \
    )
}
