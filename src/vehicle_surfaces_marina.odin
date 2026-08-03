package main

import architecture "../packages/architecture"
import buildings "../packages/buildings"
import circulation "../packages/circulation"
import engine_sound "../packages/engine_sound"
import harbor "../packages/harbor"
import marina "../packages/marina"
import particle_systems "../packages/particles"
import roads "../packages/roads"
import terrain "../packages/terrain"
import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"

crash_surface_from_dust :: proc(surface: particle_systems.Dust_Surface) -> engine_sound.Crash_Surface {
    switch surface {
    case .Asphalt:
        return .Asphalt
    case .Cobblestone:
        return .Cobblestone
    case .Gravel:
        return .Gravel
    case .Dirt:
        return .Dirt
    case .Sand:
        return .Sand
    case .Grass:
        return .Grass
    }
    return .Dirt
}

ocean_shore_proximity :: proc(editor: ^Editor, x, z: f32) -> f32 {
    if editor == nil do return 1
    sea_level := editor.project.sea_level
    if terrain.sample_height(&editor.project, 0, x, z) < sea_level do return 1
    directions := [8][2]f32 {
        {1, 0},
        {-1, 0},
        {0, 1},
        {0, -1},
        {.707, .707},
        {-.707, .707},
        {.707, -.707},
        {-.707, -.707},
    }
    radii := [3]f32{30, 80, 160}
    proximity := [3]f32{1, .68, .34}
    for ring in 0 ..< len(radii) {
        for direction in directions {
            if terrain.sample_height(
                   &editor.project,
                   0,
                   x + direction[0] * radii[ring],
                   z + direction[1] * radii[ring],
               ) <
               sea_level {
                return proximity[ring]
            }
        }
    }
    return .12
}

tire_roughness_from_dust :: proc(surface: particle_systems.Dust_Surface) -> f32 {
    switch surface {
    case .Asphalt:
        return .12
    case .Cobblestone:
        return .72
    case .Gravel:
        return .9
    case .Dirt:
        return .62
    case .Sand:
        return .48
    case .Grass:
        return .38
    }
    return .38
}

car_surface_bump_acceleration :: proc(
    surface: particle_systems.Dust_Surface,
    position: roads.Vec3,
    speed: f32,
) -> f32 {
    pavement: roads.Pavement
    #partial switch surface {
    case .Asphalt:
        pavement = .Asphalt
    case .Gravel:
        pavement = .Gravel
    case .Cobblestone:
        pavement = .Cobblestone
    case .Dirt:
        pavement = .Dirt
    case .Grass, .Sand:
        return 0
    }
    return roads.pavement_bump_acceleration(pavement, position.x, position.z, speed)
}

car_road_audio_profile :: proc(editor: ^Editor, speed: f32) -> (roughness, bump: f32) {
    if editor == nil do return
    contacts := 0
    for wheel in editor.car_wheels {
        if !wheel.contact do continue
        wheel_position := roads.Vec3{wheel.position[0], wheel.position[1], wheel.position[2]}
        surface, _ := road_car_surface(editor, wheel_position)
        roughness += tire_roughness_from_dust(surface)
        bump += math.abs(car_surface_bump_acceleration(surface, wheel_position, speed)) / 1.85
        contacts += 1
    }
    if contacts > 0 {
        roughness /= f32(contacts)
        bump = clamp(bump / f32(contacts), 0, 1)
        return
    }
    surface, _ := road_car_surface(editor, editor.car.position)
    roughness = tire_roughness_from_dust(surface)
    bump = clamp(math.abs(car_surface_bump_acceleration(surface, editor.car.position, speed)) / 1.85, 0, 1)
    return
}

road_car_surface :: proc(
    editor: ^Editor,
    position: roads.Vec3,
) -> (
    particle_systems.Dust_Surface,
    vehicles.Car_Drive_Surface,
) {
    dust_surface := particle_systems.Dust_Surface.Grass
    grip := roads.offroad_grip()
    if editor != nil {
        plan := editor_circulation_plan(editor)
        hit := circulation.surface_at(&editor.project.road_graph, plan, position)
        if hit.on_surface {
            grip = roads.pavement_grip(hit.pavement)
            switch hit.pavement {
            case .Asphalt:
                dust_surface = .Asphalt
            case .Gravel:
                dust_surface = .Gravel
            case .Cobblestone:
                dust_surface = .Cobblestone
            case .Dirt:
                dust_surface = .Dirt
            case .Steps:
                dust_surface = .Cobblestone
            }
        } else {
            // Off pavement the ground itself drives the effect: classify the
            // terrain under the wheel instead of always falling back to Grass.
            ground := terrain.ground_surface_at(&editor.project, 0, position.x, position.z)
            dust_surface = terrain_dust_surface(ground)
            grip = terrain.ground_grip(ground)
        }
    }
    return dust_surface, {
        longitudinal_grip = grip.longitudinal,
        lateral_grip = grip.lateral,
        rolling_resistance = grip.rolling_resistance,
    }
}

seed_city_capture :: proc(editor: ^Editor, target: string = "") {
    if editor == nil do return
    seed_road_capture(editor)
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    radius := f32(76)
    _ = architecture.city_density_stamp(&editor.project.city_density, center - 92, center + 34, radius, .28, .72)
    _ = architecture.city_density_stamp(&editor.project.city_density, center, center + 34, radius, .58, .72)
    _ = architecture.city_density_stamp(&editor.project.city_density, center + 92, center + 34, radius, 1, .72)
    bounds := architecture.City_Bounds{center - 190, center - 70, center + 190, center + 140, true}
    plan := architecture.city_plan_density(&editor.project, &editor.project.city_density, bounds)
    defer architecture.city_plan_destroy(&plan)
    _ = architecture.city_commit_plan(&editor.project, &editor.project.city_density, bounds, &plan)
    architecture_count := 0
    for structure in editor.project.structures[:editor.project.structure_count] {
        if structure.kind == .Architecture do architecture_count += 1
    }
    if architecture_count == 0 {
        // Keep deterministic architectural QA available while road and site
        // policy evolves. These transient fixtures are created only for an
        // otherwise-empty capture world and never enter authored maps.
        fixture_seeds := [3]u32{5, 2, 43}
        fixture_offsets := [3][2]f32{{-48, 52}, {0, 66}, {48, 52}}
        for seed, fixture_index in fixture_seeds {
            x := center + fixture_offsets[fixture_index][0]
            z := center + fixture_offsets[fixture_index][1]
            base_y := terrain.sample_height(&editor.project, 0, x, z)
            structure := terrain.structure_make(x, z, 30, 24, base_y, 19.2)
            structure.kind = .Architecture
            structure.seed = seed
            structure.building = architecture.architecture_identity(
                {
                    purpose = .Inn_Shop,
                    tissue = .Mercantile,
                    density = .70,
                    frontage = structure.width,
                    depth = structure.depth,
                    route = .Street,
                    purpose_explicit = true,
                },
                seed,
            )
            structure.building.archetype = .Mixed_Use_Dwelling
            structure.building.purpose = .Inn_Shop
            added := terrain.add_structure(&editor.project, structure)
            if added >= 0 do editor.project.structures[added].seed = seed
        }
    }
    stoop_seed := -1
    switch target {
    case "stoop-straight":
        stoop_seed = 3
    case "stoop-left":
        stoop_seed = 4
    case "stoop-right":
        stoop_seed = 5
    }
    if stoop_seed >= 0 {
        // Dedicated QA fixture: lift an ordinary frontage above otherwise
        // untouched terrain so all three deterministic stair plans remain
        // visible regardless of changes to generated city placement.
        x, z := center, center + 176
        ground_y := terrain.sample_height(&editor.project, 0, x, z)
        structure := terrain.structure_make(x, z, 18, 14, ground_y + 2.2, 12)
        structure.kind = .Architecture
        structure.seed = u32(stoop_seed)
        structure.building = architecture.architecture_identity(
            {
                purpose = .Dwelling,
                tissue = .Unspecified,
                density = .45,
                frontage = structure.width,
                depth = structure.depth,
                route = .Street,
                purpose_explicit = true,
            },
            structure.seed,
        )
        structure.building.archetype = .Dwelling
        added := terrain.add_structure(&editor.project, structure)
        if added >= 0 do editor.project.structures[added].seed = structure.seed
    }
    // Give the architectural capture a restrained, deterministic vine pass so
    // surface attachment is visible without requiring interactive brush input.
    for structure in editor.project.structures[:editor.project.structure_count] {
        if structure.kind != .Architecture || structure.height > 52 do continue
        _ = architecture.city_density_stamp(
            &editor.project.climbing_leaf_density,
            structure.center_x,
            structure.center_z,
            max(structure.width, structure.depth) * .42,
            .72,
            .68,
        )
    }
    authoring_select_tool(editor, .Building)
    editor.structure_selected = -1
}

seed_default_island_towns_seeded :: proc(editor: ^Editor, island_seeds: [len(terrain.DEFAULT_ISLAND_SEEDS)]u32) {
    if editor == nil do return
    architecture.city_plan_destroy(&editor.architecture_city_plan)
    editor.settlement_plan.patio_count = 0
    world_renderer.retained_patio_dirty = true
    settlement_regions := [len(terrain.DEFAULT_ISLAND_SIGNS)]Settlement_Region{.Adriatic, .Aegean}
    for sign, island_index in terrain.DEFAULT_ISLAND_SIGNS {
        seed := terrain.default_island_feature_seed_for(island_seeds[island_index], 0x544f574e)
        first_structure := editor.project.structure_count
        target := fmt.tprintf("%d", seed)
        if !settlement_lab_configure(
            editor,
            target,
            SETTLEMENT_TOWN,
            settlement_regions[island_index],
            sign,
            false,
            true,
        ) {
            fmt.eprintf("default island town generation failed for island %d\n", island_index)
            continue
        }
        town_center := editor.settlement_plan.request.center
        region := settlement_building_region(settlement_regions[island_index])
        // Every town also needs a deterministic commercial address. In
        // particular, Zora's home pose deliberately looks for a storefront on
        // the Aegean island; leaving this to density luck made Fortuna (and
        // therefore Zora) disappear for otherwise valid town plans.
        storefront_index := -1
        storefront_score := -f32(1)
        for structure_index in first_structure ..< editor.project.structure_count {
            structure := &editor.project.structures[structure_index]
            if structure.kind != .Architecture || structure.height > 60 do continue
            identity := architecture.architecture_resolve_legacy_identity(structure^)
            if identity.archetype == .Post_Office || identity.archetype == .Clinic do continue
            // Prefer a separate end of the main street so the postal and
            // commercial landmarks give each generated town two anchors.
            score := math.abs(structure.center_x - town_center[0]) * 2 + math.abs(structure.center_z - town_center[1])
            if score > storefront_score {
                storefront_score = score
                storefront_index = structure_index
            }
        }
        if storefront_index >= 0 {
            storefront := &editor.project.structures[storefront_index]
            storefront.building = architecture.architecture_identity(
                {
                    region = region,
                    purpose = .Inn_Shop,
                    density = .8,
                    attached = true,
                    route = .Civic,
                    purpose_explicit = true,
                },
                storefront.seed,
            )
        }
        // A rejected town plan can roll its staged structures back below the
        // count captured before generation. In that case there is no new
        // architecture range to decorate.
        if first_structure < editor.project.structure_count {
            for structure in editor.project.structures[first_structure:editor.project.structure_count] {
                if structure.kind != .Architecture || structure.height > 60 do continue
                _ = architecture.city_density_stamp(
                    &editor.project.climbing_leaf_density,
                    structure.center_x,
                    structure.center_z,
                    max(structure.width, structure.depth) * .56,
                    .78,
                    .68,
                )
            }
        }
        seed_default_island_lighthouse(editor, sign, island_index)
        seed_default_runway_access(editor, sign)
        seed_default_hero_building_access(editor, sign, 0)
    }
    editor.architecture_node_mode = true
}

// Airports are POIs, not road-layout authorities. Join the inward runway
// threshold to the generated town over the cheapest buildable terrain route;
// marina, lighthouse, and town routes then provide the rest of the connected
// island network.
seed_default_runway_access :: proc(editor: ^Editor, sign: f32) -> bool {
    if editor == nil do return false
    airport_x, airport_z := terrain.default_airport_center_for_project(&editor.project, sign)
    runway_x, runway_z := terrain.default_runway_center_for_project(&editor.project, sign)
    runway_half_length := f32(terrain.WORLD_SIZE_METERS * .5) * terrain.DEFAULT_RUNWAY_HALF_LENGTH
    threshold_x := runway_x - sign * runway_half_length
    town_x, town_z := terrain.default_town_center_for_project(&editor.project, sign)
    route := settlement_route_find(&editor.project, threshold_x, runway_z, town_x, town_z, .Connector)
    if route.count < 2 || settlement_route_crosses_sea(&editor.project, route) do return false
    _, _, maximum_grade := settlement_route_length_and_grade(&editor.project, route)
    if maximum_grade > settlement_route_grade_limit(.Connector) + .001 do return false
    settlement_route_commit(&editor.project, route, 7, 1.25, .Gravel, .85)
    terminal := roads.add_node(
        &editor.project.road_graph,
        {airport_x, terrain.sample_height(&editor.project, 0, airport_x, airport_z), airport_z},
        5,
    )
    threshold := -1
    for node, node_index in editor.project.road_graph.nodes[:editor.project.road_graph.node_count] {
        if math.abs(node.position.x - threshold_x) < .01 && math.abs(node.position.z - runway_z) < .01 {
            threshold = node_index
            break
        }
    }
    if terminal >= 0 && threshold >= 0 {
        _ = roads.add_straight_edge(&editor.project.road_graph, terminal, threshold, 7, 1.25, .Gravel, .85)
    }
    return true
}

default_road_nearest_point :: proc(
    project: ^terrain.Project,
    point: [2]f32,
) -> (
    nearest: [2]f32,
    distance: f32,
    found: bool,
) {
    distance_squared := f32(1e30)
    if project == nil do return {}, 0, false
    graph := &project.road_graph
    for edge in graph.edges[:graph.edge_count] {
        for sample_index in 0 ..= 24 {
            sample := roads.edge_point(graph, edge, f32(sample_index) / 24)
            dx, dz := sample.x - point[0], sample.z - point[1]
            candidate := dx * dx + dz * dz
            if candidate < distance_squared {
                distance_squared = candidate
                nearest = {sample.x, sample.z}
                found = true
            }
        }
    }
    if found do distance = f32(math.sqrt(f64(distance_squared)))
    return
}

seed_default_hero_building_access :: proc(editor: ^Editor, sign: f32, first_structure: int) {
    if editor == nil do return
    for structure in editor.project.structures[first_structure:editor.project.structure_count] {
        if structure.kind != .Architecture || structure.center_x * sign <= 0 do continue
        identity := architecture.architecture_resolve_legacy_identity(structure)
        if identity.archetype != .Post_Office && identity.archetype != .Clinic do continue
        entrance := settlement_structure_front_door_point(structure, 1)
        _, road_distance, road_found := default_road_nearest_point(&editor.project, entrance)
        if road_found && road_distance <= 16 do continue
        nearest, _, found := default_road_nearest_point(&editor.project, entrance)
        if !found do continue
        from := roads.add_node(
            &editor.project.road_graph,
            {entrance[0], terrain.sample_height(&editor.project, 0, entrance[0], entrance[1]), entrance[1]},
            2,
        )
        to := roads.add_node(
            &editor.project.road_graph,
            {nearest[0], terrain.sample_height(&editor.project, 0, nearest[0], nearest[1]), nearest[1]},
            2,
        )
        if from >= 0 && to >= 0 do _ = roads.add_straight_edge(&editor.project.road_graph, from, to, 4, .8, .Cobblestone, .75)
    }
}

seed_default_island_towns :: proc(editor: ^Editor) {
    seed_default_island_towns_seeded(editor, terrain.DEFAULT_ISLAND_SEEDS)
}

DEFAULT_LIGHTHOUSE_TOWN_SEPARATION :: f32(320)

default_lighthouse_has_access :: proc(project: ^terrain.Project, x, z: f32) -> bool {
    if project == nil do return false
    graph := &project.road_graph
    for edge in graph.edges[:graph.edge_count] {
        node_indices := [2]int{edge.from, edge.to}
        for node_index in node_indices {
            if node_index < 0 || node_index >= graph.node_count do continue
            position := graph.nodes[node_index].position
            dx, dz := position.x - x, position.z - z
            if dx * dx + dz * dz <= 9 do return true
        }
    }
    _, distance, found := default_road_nearest_point(project, {x, z})
    if found && distance <= 4 do return true
    return false
}

seed_default_lighthouse_access :: proc(editor: ^Editor, sign: f32, structure: terrain.Structure) -> bool {
    if editor == nil do return false
    keeper, _, found := world_lighthouse_keeper_pose(editor, structure)
    if !found do return false
    if default_lighthouse_has_access(&editor.project, keeper.x, keeper.z) do return true
    town_x, town_z := terrain.default_town_center_for_project(&editor.project, sign)
    route := settlement_route_find(&editor.project, town_x, town_z, keeper.x, keeper.z, .Street)
    if route.count >= 2 && !settlement_route_crosses_sea(&editor.project, route) {
        _, _, maximum_grade := settlement_route_length_and_grade(&editor.project, route)
        if maximum_grade <= settlement_route_grade_limit(.Street) + .001 {
            settlement_route_commit(&editor.project, route, 4, 1, .Cobblestone, .55)
        }
    }
    if !default_lighthouse_has_access(&editor.project, keeper.x, keeper.z) {
        nearest, _, road_found := default_road_nearest_point(&editor.project, {keeper.x, keeper.z})
        if road_found {
            from := roads.add_node(&editor.project.road_graph, {keeper.x, keeper.y, keeper.z}, 2)
            to := roads.add_node(
                &editor.project.road_graph,
                {nearest[0], terrain.sample_height(&editor.project, 0, nearest[0], nearest[1]), nearest[1]},
                2,
            )
            if from >= 0 && to >= 0 do _ = roads.add_straight_edge(&editor.project.road_graph, from, to, 4, 1, .Cobblestone, .55)
        }
    }
    return default_lighthouse_has_access(&editor.project, keeper.x, keeper.z)
}

seed_default_island_lighthouse :: proc(editor: ^Editor, sign: f32, island_index: int) {
    if editor == nil do return
    center_x, center_z := terrain.default_island_center(sign)
    town_x, town_z := terrain.default_town_center_for_project(&editor.project, sign)
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    island_radius := half_extent * terrain.DEFAULT_ISLAND_RADIUS
    for structure in editor.project.structures[:editor.project.structure_count] {
        identity := architecture.architecture_resolve_legacy_identity(structure)
        if structure.kind != .Architecture || identity.archetype != .Lighthouse do continue
        dx, dz := structure.center_x - center_x, structure.center_z - center_z
        if dx * dx + dz * dz <= island_radius * island_radius {
            _ = seed_default_lighthouse_access(editor, sign, structure)
            return
        }
    }

    // Put the light on the exposed, seaward shoulder opposite the channel,
    // leaving the town, runway, and marina district clear on the inward side.
    diagonal := f32(.70710678)
    coast_offset := island_radius * .68
    x := center_x + sign * diagonal * coast_offset
    z := center_z + sign * diagonal * coast_offset
    rotation := -sign * f32(math.PI / 4)
    if sign < 0 do rotation += math.PI
    // Generated coves can put the old radial landmark point in water. Search
    // its exposed shoulder for a footprint whose tower and keeper doorway are
    // both on land.
    best_score := -f32(1e30)
    for dz in -4 ..= 4 {
        for dx in -4 ..= 4 {
            candidate_x := x + f32(dx) * 18
            candidate_z := z + f32(dz) * 18
            town_dx, town_dz := candidate_x - town_x, candidate_z - town_z
            if town_dx * town_dx + town_dz * town_dz <
               DEFAULT_LIGHTHOUSE_TOWN_SEPARATION * DEFAULT_LIGHTHOUSE_TOWN_SEPARATION {
                continue
            }
            keeper_x, keeper_z := world_rotate_xz(candidate_x, candidate_z, 10 * .23, 10 * .5 + 1.8, rotation)
            base := terrain.sample_height(&editor.project, 0, candidate_x, candidate_z)
            keeper_ground := terrain.sample_height(&editor.project, 0, keeper_x, keeper_z)
            if min(base, keeper_ground) <= editor.project.sea_level + .35 do continue
            distance_penalty := f32(dx * dx + dz * dz) * .04
            score := min(base, keeper_ground) - distance_penalty
            if score > best_score {
                best_score = score
                x, z = candidate_x, candidate_z
            }
        }
    }
    // The exposed shoulder may be a skerry too small for the full landmark.
    // Fall back toward the known-safe settlement datum, but remain far enough
    // outward that the lighthouse does not become part of the town fabric.
    if best_score <= -1e20 {
        x = town_x + sign * diagonal * DEFAULT_LIGHTHOUSE_TOWN_SEPARATION
        z = town_z + sign * diagonal * DEFAULT_LIGHTHOUSE_TOWN_SEPARATION
    }
    base_y := terrain.sample_height(&editor.project, 0, x, z)
    region := island_index == 0 ? buildings.Region.Adriatic : buildings.Region.Aegean
    structure := terrain.Structure {
        center_x      = x,
        center_z      = z,
        width         = 10,
        depth         = 10,
        base_y        = base_y,
        height        = 27,
        rotation      = rotation,
        color         = {235, 230, 210, 255},
        kind          = .Architecture,
        entrance_side = .Front,
        building      = architecture.architecture_identity(
            {region = region, landmark_kind = .Lighthouse, purpose_explicit = true},
            u32(0x1a17e000 + island_index),
        ),
    }
    structure_index := terrain.add_structure(&editor.project, structure)
    if structure_index >= 0 && !seed_default_lighthouse_access(editor, sign, structure) {
        keeper, _, keeper_found := world_lighthouse_keeper_pose(editor, structure)
        if keeper_found {
            nearest, _, road_found := default_road_nearest_point(&editor.project, {keeper.x, keeper.z})
            if road_found {
                placed := &editor.project.structures[structure_index]
                placed.center_x += nearest[0] - keeper.x
                placed.center_z += nearest[1] - keeper.z
                placed.base_y = terrain.sample_height(&editor.project, 0, placed.center_x, placed.center_z)
            }
        }
    }
}

DEFAULT_MARINA_TOWN_SEPARATION :: f32(420)
// Harbor surveys use large, morphology-dependent site diameters, so their
// analyzed shoreline anchor can sit a few hundred metres along the same cove
// from the compact marina office without representing a separate harbor.
DEFAULT_MARINA_HARBOR_ALIGNMENT :: f32(500)

default_marina_plan_clears_town :: proc(plan: ^marina.Plan, town: harbor.Vec2) -> bool {
    if plan == nil || !plan.valid do return false
    office := marina.plan_world_position(plan, plan.office)
    dx, dz := office.x - town.x, office.z - town.z
    return dx * dx + dz * dz >= DEFAULT_MARINA_TOWN_SEPARATION * DEFAULT_MARINA_TOWN_SEPARATION
}

default_marina_filter_candidate_coast :: proc(survey: ^harbor.Coastal_Survey, plan: ^marina.Plan) {
    if survey == nil || plan == nil || !plan.valid {
        if survey != nil do survey.site_count = 0
        return
    }
    kept := 0
    minimum_distance_squared := DEFAULT_MARINA_TOWN_SEPARATION * DEFAULT_MARINA_TOWN_SEPARATION
    maximum_alignment_squared := DEFAULT_MARINA_HARBOR_ALIGNMENT * DEFAULT_MARINA_HARBOR_ALIGNMENT
    office := marina.plan_world_position(plan, plan.office)
    for site in survey.sites[:survey.site_count] {
        town_dx := site.anchor.x - survey.settlement_anchor.x
        town_dz := site.anchor.z - survey.settlement_anchor.z
        if town_dx * town_dx + town_dz * town_dz < minimum_distance_squared do continue
        marina_dx := site.anchor.x - office.x
        marina_dz := site.anchor.z - office.z
        if marina_dx * marina_dx + marina_dz * marina_dz > maximum_alignment_squared do continue
        survey.sites[kept] = site
        kept += 1
    }
    survey.site_count = kept
}

default_marina_access_route :: proc(
    project: ^terrain.Project,
    town_x, town_z, marina_x, marina_z: f32,
) -> (
    Settlement_Route,
    bool,
) {
    route := settlement_route_find(project, town_x, town_z, marina_x, marina_z, .Street)
    if route.count < 2 || settlement_route_crosses_sea(project, route) do return route, false
    _, _, maximum_grade := settlement_route_length_and_grade(project, route)
    return route, maximum_grade <= settlement_route_grade_limit(.Street) + .001
}
