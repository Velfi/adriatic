package main

import architecture "../packages/architecture"
import ruins "../packages/ruins"
import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"

settlement_ruin_culture :: proc(region: Settlement_Region, seed: u32) -> ruins.Culture {
    if region == .Adriatic do return .Roman
    return ruins.hash(seed ~ 0x4d494e4f) & 3 == 0 ? .Minoan : .Aegean
}

settlement_ruin_profile :: proc(project: ^terrain.Project, point: [2]f32) -> ruins.Site {
    if project == nil do return ruins.default_site(.Flat)
    span := terrain.BASE_CELL_SIZE * 2
    left := terrain.sample_height(project, 0, point[0] - span, point[1])
    right := terrain.sample_height(project, 0, point[0] + span, point[1])
    back := terrain.sample_height(project, 0, point[0], point[1] - span)
    front := terrain.sample_height(project, 0, point[0], point[1] + span)
    slope_x, slope_z := (right - left) / (span * 2), (front - back) / (span * 2)
    grade := f32(math.sqrt(f64(slope_x * slope_x + slope_z * slope_z)))
    profile := grade > .12 ? ruins.Terrain_Profile.Terraced : grade > .035 ? .Incline : .Flat
    site := ruins.default_site(profile)
    site.slope_x, site.slope_z = slope_x, slope_z
    return site
}

settlement_ruin_translate :: proc(plan: ^ruins.Plan, point: [2]f32, base_y: f32) {
    if plan == nil do return
    for &building in plan.buildings[:plan.building_count] {
        building.center.x += point[0]
        building.center.z += point[1]
        building.base_y += base_y
    }
    for &prop in plan.props[:plan.prop_count] {
        prop.position.x += point[0]
        prop.position.z += point[1]
    }
    for &route in plan.routes[:plan.route_count] {
        route.a.x, route.a.z = route.a.x + point[0], route.a.z + point[1]
        route.b.x, route.b.z = route.b.x + point[0], route.b.z + point[1]
        route.a_y, route.b_y = route.a_y + base_y, route.b_y + base_y
    }
    for &feature in plan.features[:plan.feature_count] {
        feature.position.x += point[0]
        feature.position.z += point[1]
        feature.base_y += base_y
    }
    plan.court.center.x += point[0]
    plan.court.center.z += point[1]
    plan.court.base_y += base_y
}

settlement_ruin_plan :: proc(structure: terrain.Structure) -> ruins.Plan {
    region := structure.color[0] == 1 ? Settlement_Region.Aegean : .Adriatic
    culture := settlement_ruin_culture(region, structure.seed)
    mode := structure.color[1] == 1 ? ruins.Mode.Complex : .Ruin
    site := ruins.default_site(ruins.Terrain_Profile(structure.color[2] % u8(len(ruins.Terrain_Profile))))
    plan := ruins.generate_for_site(culture, mode, structure.seed, site)
    settlement_ruin_translate(&plan, {structure.center_x, structure.center_z}, structure.base_y)
    return plan
}

settlement_ruin_bounds :: proc(plan: ^ruins.Plan) -> (width, depth: f32) {
    if plan == nil || plan.building_count == 0 do return terrain.BASE_CELL_SIZE, terrain.BASE_CELL_SIZE
    low_x, high_x := f32(1e30), f32(-1e30)
    low_z, high_z := f32(1e30), f32(-1e30)
    for building in plan.buildings[:plan.building_count] {
        radius := f32(math.sqrt(f64(building.width * building.width + building.depth * building.depth))) * .5 + 2
        low_x, high_x = min(low_x, building.center.x - radius), max(high_x, building.center.x + radius)
        low_z, high_z = min(low_z, building.center.z - radius), max(high_z, building.center.z + radius)
    }
    return high_x - low_x, high_z - low_z
}

settlement_ruin_try_place :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    point: [2]f32,
    seed: u32,
    mode: ruins.Mode,
) -> bool {
    if plan == nil || project == nil do return false
    site := settlement_ruin_profile(project, point)
    generated := ruins.generate_for_site(settlement_ruin_culture(plan.request.region, seed), mode, seed, site)
    width, depth := settlement_ruin_bounds(&generated)
    empty_city: architecture.City_Plan
    if !settlement_brush_point_developable(project, point, SETTLEMENT_VILLAGE.max_slope) ||
       !settlement_structure_clear(project, &empty_city, point[0], point[1], width, depth, 0, 3) {
        return false
    }
    structure := terrain.structure_make(
        point[0],
        point[1],
        width,
        depth,
        terrain.sample_height(project, 0, point[0], point[1]),
        max(generated.elevation_range + f32(8), f32(12)),
    )
    structure.kind = .Ruins
    structure.seed = seed
    structure.color = {
        plan.request.region == .Aegean ? u8(1) : u8(0),
        mode == .Complex ? u8(1) : u8(0),
        u8(site.profile),
        255,
    }
    if terrain.add_structure(project, structure) < 0 do return false
    settlement_plan_record_reserved_site(plan, structure, .Ruin)
    return true
}

settlement_ruin_mode_for_scale :: proc(scale: Settlement_Scale) -> ruins.Mode {
    return scale == .City ? ruins.Mode.Complex : .Ruin
}

settlement_ruin_radial_fraction :: proc(scale: Settlement_Scale) -> f32 {
    switch scale {
    case .City:
        return .78
    case .Town:
        return .52
    case .Village:
        return .65
    }
    return .65
}

settlement_ruin_anchor_supported :: proc(
    scale: Settlement_Scale,
    project: ^terrain.Project,
    point: [2]f32,
) -> bool {
    if scale != .Town do return true
    return settlement_nearest_committed_road_distance(project, point) <= 20
}

settlement_ruins_generate :: proc(plan: ^Settlement_Plan, project: ^terrain.Project) -> bool {
    if plan == nil || project == nil || settlement_plan_reserved_kind_count(plan, .Ruin) > 0 do return false
    // A monumental archaeological complex can anchor a city edge, but at
    // town scale it reads as a second detached settlement and overwhelms the
    // nearby row houses. Towns and villages use a compact inherited ruin.
    mode := settlement_ruin_mode_for_scale(plan.request.scale)
    radial_fraction := settlement_ruin_radial_fraction(plan.request.scale)
    for attempt in 0 ..< 24 {
        seed := plan.request.seed ~ u32(attempt * 0x9e3779b9) ~ 0x5255494e
        angle := f32(attempt) * math.PI * 2 / 24 + ruins.random_range(seed, -.08, .08)
        point :=
            plan.request.center +
            [2]f32{math.cos(angle), math.sin(angle)} * plan.request.radius * radial_fraction
        if plan.macro_cell_count > 0 {
            best, best_distance := point, f32(1e30)
            for cell in plan.macro_cells[:plan.macro_cell_count] {
                distance := linalg.length(cell.center - point)
                if distance < best_distance {
                    best, best_distance = cell.center, distance
                }
            }
            point = best
        }
        if !settlement_ruin_anchor_supported(plan.request.scale, project, point) do continue
        if settlement_ruin_try_place(plan, project, point, seed, mode) do return true
    }
    return false
}

settlement_ruin_add_access :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan,
) -> bool {
    if plan == nil || project == nil || city_plan == nil do return false
    ruin_index := -1
    for site, site_index in plan.sites[:plan.site_count] {
        if site.accepted && site.kind == .Ruin {
            ruin_index = site_index
            break
        }
    }
    if ruin_index < 0 do return false
    ruin := plan.sites[ruin_index].structure
    ruin_center := [2]f32{ruin.center_x, ruin.center_z}
    route_origin, _, _, route_width, route_shoulder, _, _, route_found :=
        settlement_nearest_route_frame(plan, ruin_center)
    if !route_found do return false
    approach := settlement_structure_approach_point(ruin, route_origin, .45)
    outward := linalg.normalize0(approach - route_origin)
    if linalg.length(outward) <= .001 do return false
    road_edge := route_origin + outward * (route_width * .5 + route_shoulder + .3)
    path := settlement_access_path_find(
        project,
        city_plan,
        approach,
        road_edge,
        -1,
        .7,
        true,
    )
    if path.count < 2 do return false
    path_length := f32(0)
    for index in 0 ..< path.count - 1 {
        path_length += linalg.length(path.points[index + 1] - path.points[index])
    }
    if path_length > 24 do return false
    for index in 0 ..< path.count - 1 {
        append(
            &city_plan.alleys,
            architecture.City_Alley {
                start_x = path.points[index][0],
                start_z = path.points[index][1],
                end_x = path.points[index + 1][0],
                end_z = path.points[index + 1][1],
                half_width = .7,
                start_terminal = index == 0 ? .Public_Space : .None,
                end_terminal = index == path.count - 2 ? .Road : .None,
            },
        )
        city_plan.alley_count += 1
    }
    return true
}

world_settlement_ruin :: proc(structure: terrain.Structure, lod: Structure_LOD) {
    plan := settlement_ruin_plan(structure)
    world_ruins_plan(&plan, false, lod != .Far)
}
