package architecture

import buildings "../buildings"
import roads "../roads"
import terrain "../terrain"
import "core:math"
import planar_geometry "zelda_engine:planar_geometry"

city_alley_segment_intersection :: proc(
    first_start_x, first_start_z, first_end_x, first_end_z: f32,
    second: City_Alley,
) -> (
    x, z, first_along: f32,
    found: bool,
) {
    intersection := planar_geometry.segment_intersection(
        {first_start_x, first_start_z},
        {first_end_x, first_end_z},
        {second.start_x, second.start_z},
        {second.end_x, second.end_z},
        .0001,
    )
    if !intersection.found do return
    first_amount, second_amount := intersection.along_ab, intersection.along_cd
    if first_amount <= .001 || first_amount >= .999 || second_amount < -.001 || second_amount > 1.001 {
        return
    }
    return intersection.point[0], intersection.point[1], first_amount, true
}

city_plan_split_alley_at :: proc(plan: ^City_Plan, alley_index: int, x, z: f32) {
    if plan == nil || alley_index < 0 || alley_index >= plan.alley_count do return
    original := plan.alleys[alley_index]
    start_dx, start_dz := x - original.start_x, z - original.start_z
    end_dx, end_dz := x - original.end_x, z - original.end_z
    if start_dx * start_dx + start_dz * start_dz <= .0025 || end_dx * end_dx + end_dz * end_dz <= .0025 {
        return
    }
    plan.alleys[alley_index].end_x = x
    plan.alleys[alley_index].end_z = z
    plan.alleys[alley_index].end_terminal = .None
    tail := original
    tail.start_x, tail.start_z = x, z
    tail.start_terminal = .None
    append(&plan.alleys, tail)
    plan.alley_count += 1
}

city_plan_density :: proc(
    project: ^terrain.Project,
    field: ^[terrain.CITY_DENSITY_SAMPLES]u8,
    rebuild_bounds: City_Bounds,
    seed: u32 = 0xA71D3,
) -> City_Plan {
    plan: City_Plan
    if project == nil || field == nil || !rebuild_bounds.valid do return plan

    // Frontage sampling makes authored roads the primary skeleton. A stable
    // jitter changes lot widths without allowing frame-to-frame preview pops.
    for edge, edge_index in project.road_graph.edges[:project.road_graph.edge_count] {
        previous := roads.edge_point(&project.road_graph, edge, 0)
        accumulated: f32
        lot_cursor: f32
        next_frontage := 10 + city_hash_unit(edge_index, 0, seed, 31) * 8
        for sample in 1 ..= 64 {
            t := f32(sample) / 64
            current := roads.edge_point(&project.road_graph, edge, t)
            vx, vz := current.x - previous.x, current.z - previous.z
            segment := f32(math.sqrt(f64(vx * vx + vz * vz)))
            if segment > .001 {
                accumulated += segment
                lot_cursor += segment
                if lot_cursor >= next_frontage {
                    tangent_x, tangent_z := vx / segment, vz / segment
                    normal_x, normal_z := -tangent_z, tangent_x
                    for side_index in 0 ..< 2 {
                        side := side_index == 0 ? f32(-1) : f32(1)
                        probe_x := current.x + normal_x * side * (edge.half_width + edge.shoulder_width + 15)
                        probe_z := current.z + normal_z * side * (edge.half_width + edge.shoulder_width + 15)
                        density := city_density_sample(field, probe_x, probe_z, project)
                        lot_seed := city_hash(edge_index * 131 + int(accumulated), side_index, seed)
                        depth := 15 + density * 15 + f32((lot_seed >> 12) & 255) / 255 * 5
                        center_offset := edge.half_width + edge.shoulder_width + 2 + depth * .5
                        center_x := current.x + normal_x * side * center_offset
                        center_z := current.z + normal_z * side * center_offset
                        city_plan_add_parcel_building(
                            &plan,
                            project,
                            rebuild_bounds,
                            center_x,
                            center_z,
                            tangent_x,
                            tangent_z,
                            side,
                            next_frontage,
                            depth,
                            density,
                            lot_seed,
                            false,
                        )

                        // Dense paint may support a narrow alley normal to the
                        // main street, but the alley is demand-driven: retain
                        // it only after multiple independently viable deep
                        // parcels have asked for shared access.
                        deep_density := city_density_sample(
                            field,
                            current.x + normal_x * side * (edge.half_width + edge.shoulder_width + 62),
                            current.z + normal_z * side * (edge.half_width + edge.shoulder_width + 62),
                            project,
                        )
                        if deep_density > .55 && (lot_seed & 7) == 0 {
                            alley_start := edge.half_width + edge.shoulder_width + 3
                            alley_length := 62 + deep_density * 22
                            network_length := alley_start + alley_length
                            alley := City_Alley {
                                // Root the branch on the sampled road
                                // centerline. Starting beyond the shoulder and
                                // labeling that point `.Road` only drew a
                                // convincing apron; it did not make the two
                                // networks geometrically connected.
                                start_x        = current.x,
                                start_z        = current.z,
                                end_x          = current.x + normal_x * side * network_length,
                                end_z          = current.z + normal_z * side * network_length,
                                half_width     = 2.2,
                                start_terminal = .Road,
                            }
                            joined_alley := -1
                            joined_x, joined_z: f32
                            joined_amount: f32 = 1
                            for existing, existing_index in plan.alleys[:plan.alley_count] {
                                intersection_x, intersection_z, amount, found := city_alley_segment_intersection(
                                    alley.start_x,
                                    alley.start_z,
                                    alley.end_x,
                                    alley.end_z,
                                    existing,
                                )
                                if found && amount < joined_amount {
                                    joined_alley = existing_index
                                    joined_x, joined_z = intersection_x, intersection_z
                                    joined_amount = amount
                                }
                            }
                            if joined_alley >= 0 {
                                alley.end_x, alley.end_z = joined_x, joined_z
                                alley.end_terminal = .None
                                network_length *= joined_amount
                            }
                            structure_start := plan.count
                            parcel_start := plan.parcel_count
                            for alley_step in 0 ..< 3 {
                                // Lots still begin beyond the road shoulder;
                                // only the access centerline reaches the
                                // network root.
                                along := alley_start + 22 + f32(alley_step) * 18
                                if along >= network_length - 2 do continue
                                alley_x := alley.start_x + normal_x * side * along
                                alley_z := alley.start_z + normal_z * side * along
                                for alley_side_index in 0 ..< 2 {
                                    alley_side := alley_side_index == 0 ? f32(-1) : f32(1)
                                    lot_normal_x, lot_normal_z := -normal_z * side, normal_x * side
                                    alley_lot_depth := 14 + deep_density * 8
                                    alley_center_offset := alley.half_width + 1.2 + alley_lot_depth * .5
                                    bx := alley_x + lot_normal_x * alley_side * alley_center_offset
                                    bz := alley_z + lot_normal_z * alley_side * alley_center_offset
                                    bd := city_density_sample(field, bx, bz, project)
                                    alley_seed := city_hash(
                                        edge_index * 257 + alley_step,
                                        side_index * 2 + alley_side_index,
                                        lot_seed,
                                    )
                                    city_plan_add_parcel_building(
                                        &plan,
                                        project,
                                        rebuild_bounds,
                                        bx,
                                        bz,
                                        normal_x * side,
                                        normal_z * side,
                                        alley_side,
                                        11 + city_hash_unit(alley_step, alley_side_index, alley_seed) * 5,
                                        alley_lot_depth,
                                        bd,
                                        alley_seed,
                                        true,
                                    )
                                }
                            }
                            household_demand := plan.count - structure_start
                            if household_demand >= 2 {
                                alley.household_demand = u16(household_demand)
                                if joined_alley >= 0 {
                                    city_plan_split_alley_at(&plan, joined_alley, joined_x, joined_z)
                                }
                                append(&plan.alleys, alley)
                                plan.alley_count += 1
                            } else {
                                // A single deep lot can use private access;
                                // it does not justify constructing a public
                                // branch or creating an isolated alley-front
                                // building merely to decorate that branch.
                                resize(&plan.structures, structure_start)
                                resize(&plan.parcels, parcel_start)
                                plan.count = structure_start
                                plan.parcel_count = parcel_start
                            }
                        }
                    }
                    lot_cursor = 0
                    frontage_seed := city_hash_unit(edge_index, int(accumulated), seed, 32)
                    next_frontage = 10 + frontage_seed * 8
                    if city_hash_unit(edge_index, int(accumulated), seed, 33) > .76 {
                        next_frontage += 8 + frontage_seed * 6
                    }
                }
            }
            previous = current
        }
    }
    return plan
}

city_commit_plan :: proc(
    project: ^terrain.Project,
    field: ^[terrain.CITY_DENSITY_SAMPLES]u8,
    rebuild_bounds: City_Bounds,
    plan: ^City_Plan,
) -> int {
    if project == nil || field == nil || plan == nil || !rebuild_bounds.valid do return 0
    project.city_density = field^
    for index := project.structure_count - 1; index >= 0; index -= 1 {
        structure := project.structures[index]
        if structure.kind == .Architecture &&
           city_bounds_contains(rebuild_bounds, structure.center_x, structure.center_z) {
            _ = terrain.remove_structure(project, index)
        }
    }
    created := 0
    for candidate in plan.structures[:plan.count] {
        structure_seed := candidate.seed
        index := terrain.add_structure(project, candidate)
        if index < 0 do break
        project.structures[index].seed = structure_seed
        created += 1
    }
    project.revision += 1
    return created
}

// Dart-throwing Poisson disk sampling is a good fit for a live paint tool:
// it has no grid artifacts, is deterministic per seed, and can stop quickly
// while the user is still dragging.
poisson_samples :: proc(min_x, min_z, max_x, max_z, radius: f32, seed: u32 = 0xA71D3) -> Poisson_Result {
    result: Poisson_Result
    if radius <= 0 || max_x <= min_x || max_z <= min_z do return result
    state := seed
    for attempt in 0 ..< 1800 {
        if result.count >= len(result.points) do break
        x := min_x + random01(&state) * (max_x - min_x)
        z := min_z + random01(&state) * (max_z - min_z)
        accepted := true
        for point in result.points[:result.count] {
            dx, dz := x - point.x, z - point.z
            if dx * dx + dz * dz < radius * radius {
                accepted = false
                break
            }
        }
        if accepted {
            result.points[result.count] = {x, z}
            result.count += 1
        }
    }
    return result
}

clear_architecture :: proc(project: ^terrain.Project) {
    if project == nil do return
    for index := project.structure_count - 1; index >= 0; index -= 1 {
        if project.structures[index].kind == .Architecture do terrain.remove_structure(project, index)
    }
}

architecture_base_height :: proc(project: ^terrain.Project, x, z: f32) -> f32 {
    if project == nil do return 0
    return terrain.sample_surface_height(project, 0, x, z)
}

generate_poisson :: proc(
    project: ^terrain.Project,
    min_x, min_z, max_x, max_z, radius, height: f32,
    seed: u32 = 0xA71D3,
) -> int {
    if project == nil do return 0
    clear_architecture(project)
    samples := poisson_samples(min_x, min_z, max_x, max_z, radius, seed)
    state := seed + 0x9e3779b9
    created := 0
    for point in samples.points[:samples.count] {
        base_height := architecture_base_height(project, point.x, point.z)
        if base_height <= project.sea_level do continue
        width := 24 + random01(&state) * 22
        depth := 15 + random01(&state) * 15
        building_radius := architecture_footprint_radius(width, depth)
        overlaps := false
        for existing in project.structures[:project.structure_count] {
            if existing.kind != .Architecture do continue
            dx, dz := point.x - existing.center_x, point.z - existing.center_z
            minimum_distance := building_radius + architecture_footprint_radius(existing.width, existing.depth) + 1.5
            if dx * dx + dz * dz < minimum_distance * minimum_distance {
                overlaps = true
                break
            }
        }
        if overlaps do continue
        building_height := max(height * (.62 + random01(&state) * .76), terrain.BASE_CELL_SIZE)
        rotation := (random01(&state) - .5) * .28
        structure := terrain.structure_make(point.x, point.z, width, depth, base_height, building_height)
        structure.kind = .Architecture
        structure.rotation = rotation
        structure_seed := u32(random01(&state) * f32(0xffffffff))
        structure.seed = structure_seed
        structure.building = architecture_identity({
                density          = clamp((building_height - 8) / 42, 0, 1),
                frontage         = width,
                depth            = depth,
                route            = .Unspecified,
                purpose_explicit = false,
            }, structure_seed)
        structure.color = architecture_color(structure.seed)
        foundation_low, foundation_high := architecture_foundation_height_range(project, structure)
        if foundation_low <= project.sea_level do continue
        structure.base_y = foundation_high
        index := terrain.add_structure(project, structure)
        if index >= 0 {
            // terrain.add_structure assigns IDs to ordinary authored forms;
            // architecture must restore its explicit procedural seed so a
            // regeneration keeps the same roof and façade style.
            project.structures[index].seed = structure_seed
            project.revision += 1
            created += 1
        }
    }
    return created
}

generate_append :: proc(
    project: ^terrain.Project,
    center_x, center_z: f32,
    seed: u32 = 0xA71D3,
    density: f32 = 1,
) -> int {
    if project == nil do return 0
    graph := adriatic_graph(center_x, center_z, seed)
    safe_density := clamp(density, f32(.2), f32(1))
    first_structure := project.structure_count
    created := 0
    for node, node_index in graph.nodes[:graph.count] {
        if node.kind == .Site do continue
        if node.kind == .Street_Block && graph_unit(seed, u32(node_index) + 211) > safe_density {
            continue
        }
        if node.kind == .Street_Block && safe_density < 1 {
            separated := true
            for existing in project.structures[first_structure:project.structure_count] {
                if existing.kind != .Architecture do continue
                dx, dz := node.x - existing.center_x, node.z - existing.center_z
                // Sparse settlements need visible gaps, not merely fewer
                // buildings selected from the same tight street wall.
                if dx * dx + dz * dz < 46 * 46 {
                    separated = false
                    break
                }
            }
            if !separated do continue
        }
        base_height := architecture_base_height(project, node.x, node.z)
        if base_height <= project.sea_level do continue
        building_height := node.height
        structure_seed := node.seed
        if node.kind == .Street_Block && safe_density < 1 {
            // Density controls vertical intensity as well as occupancy. This
            // keeps a lightly settled mouse town low-rise without uniformly
            // scaling its authored footprints, doors, or windows.
            building_height = min(building_height, 18 + safe_density * 8)
            // Compound L/U plans make one sparse lot read as several attached
            // towers. Select the simple single-mass presentation variant while
            // retaining the authored footprint dimensions and deterministic
            // palette variation.
            structure_seed -= structure_seed % 5
        }
        structure := terrain.structure_make(node.x, node.z, node.width, node.depth, base_height, building_height)
        structure.kind = .Architecture
        structure.rotation = node.rotation
        structure.seed = structure_seed
        structure.building = architecture_identity({
                density          = safe_density,
                attached         = safe_density >= .68,
                frontage         = node.width,
                depth            = node.depth,
                route            = .Street,
                landmark_kind    = node.kind == .Landmark ? buildings.Landmark_Kind.Campanile : buildings.Landmark_Kind.None,
                purpose_explicit = false,
            }, structure_seed)
        structure.color = architecture_color(structure_seed, node.kind == .Landmark)
        foundation_low, foundation_high := architecture_foundation_height_range(project, structure)
        if foundation_low <= project.sea_level do continue
        structure.base_y = foundation_high
        index := terrain.add_structure(project, structure)
        if index >= 0 {
            project.structures[index].seed = structure_seed
            project.revision += 1
            created += 1
        }
    }
    return created
}
