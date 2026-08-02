package main

import architecture "../packages/architecture"
import buildings "../packages/buildings"
import fountains "../packages/fountains"
import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"

settlement_plan_record_rejected_site :: proc(plan: ^Settlement_Plan, x, z, width, depth, rotation: f32) {
    if plan == nil || plan.rejected_site_count >= len(plan.rejected_sites) do return
    structure := terrain.structure_make(x, z, width, depth, 0, .25)
    structure.width = width
    structure.depth = depth
    structure.rotation = rotation
    plan.rejected_sites[plan.rejected_site_count] = {
        structure = structure,
        kind      = .Rejected,
        tissue    = settlement_nearest_tissue(plan, x, z),
        accepted  = false,
    }
    plan.rejected_site_count += 1
}

settlement_landmark_anchor_index :: proc(plan: ^Settlement_Plan, project: ^terrain.Project, ordinal: int) -> int {
    if plan == nil || plan.neighborhood_count == 0 do return -1
    // A village has one composed core around neighborhoods[0]. Its sole
    // landmark must reinforce that same center; selecting the globally oldest
    // tissue independently can strand a church or campanile beyond the farms.
    if plan.request.scale == .Village do return 0
    best := 0
    if ordinal == 0 {
        for neighborhood, index in plan.neighborhoods[:plan.neighborhood_count] {
            if neighborhood.age < plan.neighborhoods[best].age do best = index
        }
        return best
    }
    if ordinal == 1 {
        for neighborhood, index in plan.neighborhoods[:plan.neighborhood_count] {
            if terrain.sample_height(project, 0, neighborhood.center[0], neighborhood.center[1]) <
               terrain.sample_height(
                   project,
                   0,
                   plan.neighborhoods[best].center[0],
                   plan.neighborhoods[best].center[1],
               ) {
                best = index
            }
        }
        return best
    }
    if ordinal == 2 {
        for neighborhood, index in plan.neighborhoods[:plan.neighborhood_count] {
            if terrain.sample_height(project, 0, neighborhood.center[0], neighborhood.center[1]) >
               terrain.sample_height(
                   project,
                   0,
                   plan.neighborhoods[best].center[0],
                   plan.neighborhoods[best].center[1],
               ) {
                best = index
            }
        }
        return best
    }
    return (ordinal * 13 + plan.neighborhood_count / 3) % plan.neighborhood_count
}

settlement_alley_endpoint_degree :: proc(city_plan: ^architecture.City_Plan, point: [2]f32, half_width: f32) -> int {
    if city_plan == nil do return 0
    degree := 0
    for alley in city_plan.alleys[:city_plan.alley_count] {
        if math.abs(alley.half_width - half_width) > .05 do continue
        if settlement_alley_point_near(point, {alley.start_x, alley.start_z}) do degree += 1
        if settlement_alley_point_near(point, {alley.end_x, alley.end_z}) do degree += 1
    }
    return degree
}

settlement_access_route_class :: proc(maximum_grade, width: f32) -> Settlement_Route_Class {
    if maximum_grade >= SETTLEMENT_ACCESS_STAIR_GRADE do return .Stair
    if width >= 1.8 do return .Lane
    return .Alley
}

settlement_access_curve_grade_metrics :: proc(
    city_plan: ^architecture.City_Plan,
    project: ^terrain.Project,
    alley_indices: []int,
) -> (
    average_grade, maximum_grade: f32,
) {
    if city_plan == nil || project == nil do return
    total_length, weighted_grade := f32(0), f32(0)
    for alley_index in alley_indices {
        if alley_index < 0 || alley_index >= city_plan.alley_count do continue
        curve := settlement_access_alley_curve(city_plan, alley_index)
        sample_count := settlement_access_curve_sample_count(curve)
        previous := curve.points[0]
        previous_height := terrain.sample_height(project, 0, previous[0], previous[1])
        for sample in 1 ..= sample_count {
            current := settlement_access_curve_point(curve, f32(sample) / f32(sample_count))
            current_height := terrain.sample_height(project, 0, current[0], current[1])
            length := linalg.length(current - previous)
            if length > .01 {
                grade := math.abs(current_height - previous_height) / length
                total_length += length
                weighted_grade += grade * length
                maximum_grade = max(maximum_grade, grade)
            }
            previous, previous_height = current, current_height
        }
    }
    if total_length > .01 do average_grade = weighted_grade / total_length
    return
}

settlement_access_curve_navigation_intervals :: proc(curve: Settlement_Access_Curve) -> int {
    handle_deviation := max(
        settlement_point_segment_distance_squared(curve.points[1], curve.points[0], curve.points[3]),
        settlement_point_segment_distance_squared(curve.points[2], curve.points[0], curve.points[3]),
    )
    if handle_deviation <= .01 do return 1
    return settlement_access_curve_sample_count(curve)
}

// Preserve graph junctions while inserting spline samples. The caller chunks
// a long chain before this point, so every bend receives its requested sample
// density instead of competing with unrelated bends for the fixed payload.
settlement_access_curve_chain_geometry :: proc(
    city_plan: ^architecture.City_Plan,
    alley_indices: []int,
    chain_start: [2]f32,
) -> Settlement_Route {
    result: Settlement_Route
    if city_plan == nil || len(alley_indices) == 0 do return result
    count := min(len(alley_indices), SETTLEMENT_ROUTE_CAPACITY - 1)
    intervals: [SETTLEMENT_ROUTE_CAPACITY]int
    extra_budget := max(0, SETTLEMENT_ROUTE_CAPACITY - (count + 1))
    for alley_index, chain_index in alley_indices[:count] {
        intervals[chain_index] = 1
        curve := settlement_access_alley_curve(city_plan, alley_index)
        desired := settlement_access_curve_navigation_intervals(curve)
        added := min(max(0, desired - 1), extra_budget)
        intervals[chain_index] += added
        extra_budget -= added
    }

    result.points[0], result.count = chain_start, 1
    current := chain_start
    for alley_index, chain_index in alley_indices[:count] {
        curve := settlement_access_alley_curve(city_plan, alley_index)
        forward := settlement_alley_point_near(current, curve.points[0])
        if !forward && !settlement_alley_point_near(current, curve.points[3]) do return Settlement_Route{}
        interval_count := intervals[chain_index]
        for interval in 1 ..= interval_count {
            amount := f32(interval) / f32(interval_count)
            if !forward do amount = 1 - amount
            result.points[result.count] = settlement_access_curve_point(curve, amount)
            result.count += 1
        }
        current = result.points[result.count - 1]
    }
    return result
}

settlement_plan_import_access_route :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    geometry: Settlement_Route,
    width: f32,
    average_grade_override: f32 = -1,
    maximum_grade_override: f32 = -1,
) {
    if plan == nil || project == nil || geometry.count < 2 do return
    if plan.route_count >= len(plan.routes) {
        plan.access_routes_truncated = true
        return
    }
    total_length, weighted_grade, maximum_grade := f32(0), f32(0), f32(0)
    for index in 0 ..< geometry.count - 1 {
        a, b := geometry.points[index], geometry.points[index + 1]
        length := linalg.length(b - a)
        if length <= .01 do continue
        grade :=
            math.abs(terrain.sample_height(project, 0, b[0], b[1]) - terrain.sample_height(project, 0, a[0], a[1])) /
            length
        total_length += length
        weighted_grade += grade * length
        maximum_grade = max(maximum_grade, grade)
    }
    average_grade := total_length > .01 ? weighted_grade / total_length : f32(0)
    if average_grade_override >= 0 do average_grade = average_grade_override
    if maximum_grade_override >= 0 do maximum_grade = maximum_grade_override
    class := settlement_access_route_class(maximum_grade, width)
    if plan.village_reason == .Harbor_Fishery && width >= 3 && maximum_grade < SETTLEMENT_ACCESS_STAIR_GRADE {
        class = .Waterfront
    }
    pavement := settlement_access_route_pavement(maximum_grade, width)
    if class == .Stair do plan.access_stair_routes += 1
    // Above roughly 33 degrees a conventional outdoor stair becomes a
    // ladder-like intervention. Keep this visible as a planning failure
    // rather than silently presenting it as ordinary pedestrian paving.
    if maximum_grade > .65 do plan.access_excessive_grades += 1
    plan.routes[plan.route_count] = {
        geometry      = geometry,
        class         = class,
        width         = width,
        pavement      = pavement,
        drivable      = false,
        average_grade = average_grade,
        maximum_grade = maximum_grade,
    }
    plan.route_count += 1
}

settlement_access_stair_nosing_range :: proc(
    alley: architecture.City_Alley,
    length: f32,
) -> (
    start, finish: f32,
    valid: bool,
) {
    if length <= .01 do return
    start_landing := alley.start_terminal != .None ? f32(.65) : f32(0)
    end_landing := alley.end_terminal != .None ? f32(.65) : f32(0)
    start = min(start_landing, length * .5)
    finish = max(start, length - min(end_landing, length * .5))
    valid = finish - start >= .42
    return
}

settlement_access_stair_rest_count :: proc(run_length: f32) -> int {
    if run_length <= 7 do return 0
    return max(0, int(math.ceil(f64(run_length / 7))) - 1)
}

settlement_access_stair_interval_overlaps_rest :: proc(
    interval_start, interval_finish, run_start, run_length: f32,
    rest_count: int,
    rest_length: f32 = 1.05,
) -> bool {
    if rest_count <= 0 || run_length <= 0 || interval_finish <= interval_start do return false
    half_rest := max(rest_length, f32(0)) * .5
    for rest_index in 0 ..< rest_count {
        center := run_start + f32(rest_index + 1) / f32(rest_count + 1) * run_length
        if interval_finish > center - half_rest && interval_start < center + half_rest do return true
    }
    return false
}

settlement_access_door_apron_width :: proc(alley: architecture.City_Alley) -> f32 {
    return max(alley.half_width * 2, f32(1.1))
}

settlement_access_door_apron :: proc(
    scale: Settlement_Scale,
    alley: architecture.City_Alley,
    length: f32,
) -> (
    run, width: f32,
) {
    run = min(f32(.65), length)
    width = settlement_access_door_apron_width(alley)
    if scale == .Town {
        // A Riviera threshold is a tiny paved forecourt: enough room for a
        // stoop, pots, and two people passing, but still subordinate to the
        // adjoining vicolo.
        run = min(f32(1.6), length)
        width = max(width, f32(2.2))
    }
    return
}

settlement_access_road_apron :: proc(
    alley: architecture.City_Alley,
    length: f32,
) -> (
    run, outer_width: f32,
    valid: bool,
) {
    path_width := alley.half_width * 2
    if length <= .01 || path_width < 1.6 do return
    run = min(f32(.9), length)
    outer_width = min(path_width + .6, f32(3))
    valid = true
    return
}

settlement_plan_import_access_network :: proc(
    plan: ^Settlement_Plan,
    city_plan: ^architecture.City_Plan,
    project: ^terrain.Project,
) {
    if plan == nil || city_plan == nil || project == nil || city_plan.alley_count <= 0 do return
    plan.access_stair_routes = 0
    plan.access_excessive_grades = 0
    used := make([]bool, city_plan.alley_count, context.temp_allocator)
    for seed_index in 0 ..< city_plan.alley_count {
        if used[seed_index] do continue
        seed := city_plan.alleys[seed_index]
        seed_start := [2]f32{seed.start_x, seed.start_z}
        seed_end := [2]f32{seed.end_x, seed.end_z}
        start, finish := seed_start, seed_end
        if settlement_alley_endpoint_degree(city_plan, seed_end, seed.half_width) != 2 &&
           settlement_alley_endpoint_degree(city_plan, seed_start, seed.half_width) == 2 {
            start, finish = seed_end, seed_start
        }
        geometry: Settlement_Route
        alley_indices: [SETTLEMENT_ROUTE_CAPACITY]int
        alley_index_count := 1
        alley_indices[0] = seed_index
        geometry.points[0], geometry.points[1], geometry.count = start, finish, 2
        used[seed_index] = true
        current := finish
        for geometry.count < len(geometry.points) {
            if settlement_alley_endpoint_degree(city_plan, current, seed.half_width) != 2 do break
            next_index := -1
            next_point: [2]f32
            for alley, alley_index in city_plan.alleys[:city_plan.alley_count] {
                if used[alley_index] || math.abs(alley.half_width - seed.half_width) > .05 do continue
                alley_start := [2]f32{alley.start_x, alley.start_z}
                alley_end := [2]f32{alley.end_x, alley.end_z}
                if settlement_alley_point_near(current, alley_start) {
                    next_index, next_point = alley_index, alley_end
                    break
                }
                if settlement_alley_point_near(current, alley_end) {
                    next_index, next_point = alley_index, alley_start
                    break
                }
            }
            if next_index < 0 do break
            geometry.points[geometry.count], geometry.count = next_point, geometry.count + 1
            used[next_index] = true
            alley_indices[alley_index_count], alley_index_count = next_index, alley_index_count + 1
            current = next_point
        }
        chain_geometry := geometry
        chunk_start := 0
        for chunk_start < alley_index_count {
            chunk_end := chunk_start
            point_count := 1
            for chunk_end < alley_index_count {
                curve := settlement_access_alley_curve(city_plan, alley_indices[chunk_end])
                intervals := min(settlement_access_curve_navigation_intervals(curve), SETTLEMENT_ROUTE_CAPACITY - 1)
                if point_count + intervals > SETTLEMENT_ROUTE_CAPACITY && chunk_end > chunk_start do break
                point_count += min(intervals, SETTLEMENT_ROUTE_CAPACITY - point_count)
                chunk_end += 1
                if point_count >= SETTLEMENT_ROUTE_CAPACITY do break
            }
            if chunk_end <= chunk_start do chunk_end = chunk_start + 1
            chunk_indices := alley_indices[chunk_start:chunk_end]
            chunk_geometry := settlement_access_curve_chain_geometry(
                city_plan,
                chunk_indices,
                chain_geometry.points[chunk_start],
            )
            average_grade, maximum_grade := settlement_access_curve_grade_metrics(city_plan, project, chunk_indices)
            settlement_plan_import_access_route(
                plan,
                project,
                chunk_geometry,
                seed.half_width * 2,
                average_grade,
                maximum_grade,
            )
            chunk_start = chunk_end
        }
    }
}

settlement_plan_import_city :: proc(
    plan: ^Settlement_Plan,
    city_plan: ^architecture.City_Plan,
    project: ^terrain.Project,
) {
    if plan == nil || city_plan == nil || project == nil do return
    count := min(city_plan.count, city_plan.parcel_count)
    for index in 0 ..< count {
        if plan.site_count >= len(plan.sites) do break
        structure, parcel := city_plan.structures[index], city_plan.parcels[index]
        purpose := Settlement_Building_Purpose.Dwelling
        if index < plan.ordinary_purpose_count do purpose = plan.ordinary_purposes[index]
        site_kind := Settlement_Site_Kind.Ordinary
        if buildings.is_landmark(structure.building) do site_kind = .Landmark
        plan.sites[plan.site_count] = {
            structure = structure,
            parcel    = parcel,
            kind      = site_kind,
            tissue    = settlement_nearest_tissue(plan, structure.center_x, structure.center_z),
            density   = parcel.density,
            attached  = parcel.attached,
            accepted  = true,
            purpose   = purpose,
        }
        plan.site_count += 1
    }
    settlement_plan_import_access_network(plan, city_plan, project)
}

settlement_plan_seat_city :: proc(city_plan: ^architecture.City_Plan, project: ^terrain.Project) {
    if city_plan == nil || project == nil do return
    for &structure in city_plan.structures[:city_plan.count] {
        _, foundation_high := architecture.architecture_foundation_height_range(project, structure)
        structure.base_y = foundation_high
    }
}

settlement_plan_seat_project_architecture :: proc(project: ^terrain.Project) {
    if project == nil do return
    for &structure in project.structures[:project.structure_count] {
        if structure.kind != .Architecture do continue
        _, foundation_high := architecture.architecture_foundation_height_range(project, structure)
        structure.base_y = foundation_high
    }
}

// Turn the exposed downhill side of a steep town foundation into a modest
// limestone retaining edge. Foundation seating already prevents buildings
// from sinking into side slopes, but without a visible edge the resulting
// height change reads as a house hovering over one continuous grass sheet.
// Keep the entrance facade open for its stoop and generated access path.
settlement_town_retaining_wall :: proc(
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan,
    structure: terrain.Structure,
) -> (
    wall: terrain.Structure,
    valid: bool,
) {
    if project == nil || city_plan == nil || structure.kind != .Architecture do return
    local_x := [2]f32{f32(math.cos(f64(structure.rotation))), f32(math.sin(f64(structure.rotation)))}
    local_z := [2]f32{-local_x[1], local_x[0]}
    center := [2]f32{structure.center_x, structure.center_z}
    edge_offsets := [4][2]f32 {
        local_z * (structure.depth * .5),
        local_x * (structure.width * .5),
        -local_z * (structure.depth * .5),
        -local_x * (structure.width * .5),
    }
    lowest_edge, lowest_height := -1, f32(1e30)
    for offset, edge_index in edge_offsets {
        if edge_index == int(structure.entrance_side) do continue
        point := center + offset
        height := terrain.sample_height(project, 0, point[0], point[1])
        if height < lowest_height {
            lowest_edge, lowest_height = edge_index, height
        }
    }
    if lowest_edge < 0 do return
    exposed_height := structure.base_y - lowest_height
    if exposed_height < .65 do return

    edge_center := center + edge_offsets[lowest_edge]
    along := local_x
    length := structure.width + .7
    if lowest_edge == 1 || lowest_edge == 3 {
        along = local_z
        length = structure.depth + .7
    }
    wall_height := clamp(exposed_height + .12, f32(.7), f32(3.2))
    wall = terrain.structure_make(edge_center[0], edge_center[1], length, .34, lowest_height - .04, wall_height)
    wall.kind = .Box
    wall.width, wall.depth, wall.height = length, .34, wall_height
    wall.rotation = f32(math.atan2(f64(along[1]), f64(along[0])))
    wall.color = {151, 145, 132, 255}
    if !settlement_structure_committed_roads_clear(project, wall, .08) ||
       settlement_access_structure_overlaps_alley(city_plan, wall) {
        return {}, false
    }
    return wall, true
}

settlement_plan_commit_town_retaining_walls :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan,
) -> int {
    if plan == nil || project == nil || city_plan == nil || plan.request.scale != .Town do return 0
    committed := 0
    for structure in city_plan.structures[:city_plan.count] {
        if committed >= 18 do break
        wall, valid := settlement_town_retaining_wall(project, city_plan, structure)
        if !valid do continue
        if terrain.add_structure(project, wall) < 0 do break
        committed += 1
    }
    return committed
}

settlement_plan_record_reserved_site :: proc(
    plan: ^Settlement_Plan,
    structure: terrain.Structure,
    kind: Settlement_Site_Kind,
    landmark_kind: Settlement_Landmark_Kind = {},
) {
    if plan == nil || plan.site_count >= len(plan.sites) do return
    site := Settlement_Site {
        structure     = structure,
        kind          = kind,
        landmark_kind = landmark_kind,
        tissue        = settlement_nearest_tissue(plan, structure.center_x, structure.center_z),
        accepted      = true,
    }
    if kind == .Park && min(structure.width, structure.depth) >= 10 {
        radius := clamp(min(structure.width, structure.depth) * .18, f32(2.2), f32(4.6))
        style := plan.request.region == .Aegean ? fountains.Style.Bowl : fountains.Style.Courtyard
        site.fountain_style = style
        site.fountain_radius = radius
        site.fountain_jet_count = clamp(int(radius * 2.5), 6, 14)
        site.fountain_jet_height = radius * .62
        site.fountain_enabled = true
    }
    plan.sites[plan.site_count] = site
    plan.site_count += 1
}

settlement_landmark_kind :: proc(region: Settlement_Region, ordinal: int) -> Settlement_Landmark_Kind {
    adriatic := [?]Settlement_Landmark_Kind {
        .Campanile,
        .Palace_Loggia,
        .Church,
        .Lighthouse,
        .Harbor_Office,
        .Market_Hall,
        .Fortress_Gate,
    }
    aegean := [?]Settlement_Landmark_Kind {
        .Cycladic_Bell,
        .Church,
        .Lighthouse,
        .Monastery,
        .Harbor_Office,
        .Market_Hall,
        .Fortress_Gate,
    }
    if region == .Aegean do return aegean[ordinal % len(aegean)]
    return adriatic[ordinal % len(adriatic)]
}

settlement_plan_reserved_kind_count :: proc(plan: ^Settlement_Plan, kind: Settlement_Site_Kind) -> int {
    if plan == nil do return 0
    result := 0
    for site in plan.sites[:plan.site_count] {
        if site.accepted && site.kind == kind do result += 1
    }
    return result
}

settlement_cut_fill_estimate :: proc(
    sample_heights: [5]f32,
    area: f32,
) -> (
    target_height, cut_volume, fill_volume: f32,
) {
    for sample_height in sample_heights do target_height += sample_height
    target_height /= f32(len(sample_heights))
    for sample_height in sample_heights {
        delta := target_height - sample_height
        if delta > 0 {
            fill_volume += delta * area / f32(len(sample_heights))
        } else {
            cut_volume += -delta * area / f32(len(sample_heights))
        }
    }
    return
}

settlement_plan_record_terrain_edit :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    kind: Settlement_Terrain_Edit_Kind,
    x, z, half_x, half_z, feather: f32,
    smooth_strength: f32 = .72,
    smooth_hardness: f32 = .62,
) {
    if plan == nil || project == nil || plan.terrain_edit_count >= len(plan.terrain_edits) do return
    samples := [5][2]f32 {
        {x, z},
        {x - half_x, z - half_z},
        {x + half_x, z - half_z},
        {x + half_x, z + half_z},
        {x - half_x, z + half_z},
    }
    sample_heights: [5]f32
    for point, index in samples {
        sample_heights[index] = terrain.sample_height(project, 0, point[0], point[1])
    }
    area := max(half_x * 2, f32(1)) * max(half_z * 2, f32(1))
    height, cut_volume, fill_volume := settlement_cut_fill_estimate(sample_heights, area)
    height = max(height, project.sea_level + .6)
    plan.terrain_edits[plan.terrain_edit_count] = {
        kind          = kind,
        center        = {x, z},
        half_extent   = {half_x, half_z},
        target_height = height,
        feather       = feather,
        cut_volume    = cut_volume,
        fill_volume   = fill_volume,
    }
    plan.terrain_edit_count += 1
    // The lab terrain is disposable. Smoothing is bounded to the recorded pad
    // and cascades through clipmap levels in the terrain package.
    if kind != .Retaining_Edge {
        terrain.apply_stroke_with_hardness(
            project,
            .Smooth,
            x,
            z,
            max(half_x, half_z) + feather,
            smooth_strength,
            1,
            smooth_hardness,
        )
    }
}
