package main
import "core:math"

import architecture "../packages/architecture"
import dio "../packages/dio"
import hero "../packages/hero_buildings"
import terrain "../packages/terrain"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

world_architecture_oriented :: proc(
    structure: terrain.Structure,
    project: ^terrain.Project,
    lod: Structure_LOD = .Near,
) {
    identity := architecture.architecture_resolve_legacy_identity(structure)
    if identity.archetype == .Post_Office || identity.archetype == .Clinic {
        kind := identity.archetype == .Clinic ? hero.Kind.Clinic : hero.Kind.Post_Office
        // The hero generator owns the complete visible civic building. Its
        // architecture footprint still describes rooms, collision, doors,
        // and access, but rendering those masses again as ordinary buildings
        // stacks unrelated roofs over the purpose-built pavilion.
        world_architecture_hero_civic(structure, kind, lod)
        return
    }
    if identity.archetype == .Lighthouse {
        world_architecture_lighthouse(structure, lod)
        return
    }
    footprint := architecture.architecture_footprint(structure)
    if footprint.count <= 1 {
        mass := footprint.masses[0]
        child := structure
        child.center_x, child.center_z = architecture.architecture_mass_world(structure, mass)
        child.width = mass.width
        child.depth = mass.depth
        child.height = max(f32(0), structure.height * mass.height_scale)
        if identity.archetype == .Farmstead || identity.archetype == .Barn_Granary {
            child.color = identity.region == .Aegean ? [4]u8{178, 173, 153, 255} : [4]u8{184, 176, 151, 255}
            if identity.archetype == .Farmstead {
                child.color = identity.region == .Aegean ? [4]u8{236, 232, 216, 255} : [4]u8{204, 194, 169, 255}
            }
        }
        layout := architecture.architecture_opening_layout(structure, 0, 0)
        // Even a one-mass footprint may intentionally narrow or reshape the
        // authored lot (campanile and Cycladic bell). Render that resolved
        // mass, otherwise openings are placed against the smaller footprint
        // while the walls still use the original parcel-sized structure.
        world_architecture_mass(child, project, true, &layout, lod)
        return
    }
    frontage_index := architecture.architecture_frontage_mass_index(structure)
    compound_identity := architecture.architecture_resolve_legacy_identity(structure)
    if compound_identity.archetype == .Mixed_Use_Dwelling && footprint.count == 3 {
        // The gap between the paired private wings is a working service court,
        // not leftover lawn. A shallow stone surface and drain make deliveries
        // and rear circulation legible without changing the public frontage.
        left := footprint.masses[1]
        right := footprint.masses[2]
        court_left := left.local_x + left.width * .5
        court_right := right.local_x - right.width * .5
        court_width := max(court_right - court_left - .35, f32(1.2))
        court_depth := min(left.depth, right.depth) * .82
        court_local_x := (court_left + court_right) * .5
        court_local_z := (left.local_z + right.local_z) * .5
        court_x, court_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            court_local_x,
            court_local_z,
            structure.rotation,
        )
        world_box_rotated(
            {court_x, structure.base_y + .035, court_z},
            {court_width, .07, court_depth},
            structure.rotation,
            {166, 151, 123, 255},
        )
        drain_x, drain_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            court_local_x,
            court_local_z,
            structure.rotation,
        )
        world_box_rotated(
            {drain_x, structure.base_y + .078, drain_z},
            {.14, .018, court_depth * .82},
            structure.rotation,
            {83, 85, 77, 255},
        )
    }
    for mass, mass_index in footprint.masses[:footprint.count] {
        child := structure
        child.center_x, child.center_z = architecture.architecture_mass_world(structure, mass)
        child.width = mass.width
        child.depth = mass.depth
        child.height = max(f32(0), structure.height * mass.height_scale)
        // Keep palette identity while decoupling repeated openings and tiles.
        child.seed = structure.seed + u32(mass_index * 747796405)
        agricultural := compound_identity.archetype == .Farmstead || compound_identity.archetype == .Barn_Granary
        if agricultural {
            if compound_identity.region == .Aegean {
                // The inhabited frontage cell is limewashed; stable and
                // storage cells retain their native stone and remain visually
                // subordinate to the house.
                child.color =
                    (mass_index == frontage_index && compound_identity.archetype == .Farmstead ? [4]u8{236, 232, 216, 255} : [4]u8{171, 166, 146, 255})
            } else {
                child.color =
                    (mass_index == frontage_index && compound_identity.archetype == .Farmstead ? [4]u8{204, 194, 169, 255} : [4]u8{181, 174, 151, 255})
            }
        }
        if compound_identity.archetype == .Mixed_Use_Dwelling && mass_index != frontage_index {
            // Private rear ranges stay subordinate to the commercial street
            // bar. A consistent parapet avoids pitched secondary roofs
            // penetrating the taller mass at compound junctions.
            child.seed = (child.seed &~ u32(3)) | u32(3)
        }
        layout := architecture.architecture_opening_layout(structure, mass_index, frontage_index)
        world_architecture_mass(child, project, mass_index == frontage_index, &layout, lod)
    }
    // Render private-range doors after their wall masses so the shallow door
    // leaves and trim remain visible on the compound façade planes.
    if lod == .Near && compound_identity.archetype == .Mixed_Use_Dwelling && footprint.count == 3 {
        // Each private range opens directly into the working court. These are
        // deliberately modest service/family doors, subordinate to both the
        // glass storefront and the street-facing apartment stair entrances.
        for wing_index in 1 ..= 2 {
            wing := footprint.masses[wing_index]
            inward := wing_index == 1 ? f32(1) : f32(-1)
            world_architecture_mixed_use_service_door(
                structure,
                wing.local_x + inward * (wing.width * .5 + .10),
                wing.local_z,
                math.PI * .5,
                inward,
                0,
            )
        }
    } else if lod == .Near && compound_identity.archetype == .Mixed_Use_Dwelling && footprint.count == 2 {
        // L and T plans get one quiet rear-yard entrance into the private
        // range, completing circulation without adding another public door
        // beside the shopfront.
        wing := footprint.masses[1]
        world_architecture_mixed_use_service_door(
            structure,
            wing.local_x,
            wing.local_z - wing.depth * .5 - .10,
            math.PI,
            0,
            -1,
        )
        world_architecture_mixed_use_service_path(
            structure,
            wing.local_x,
            wing.local_z - wing.depth * .5 - .10,
            0,
            -1,
            clamp(structure.depth * .22, f32(2.8), f32(4.8)),
        )
    }
}

world_architecture :: proc(structure: terrain.Structure, project: ^terrain.Project, lod: Structure_LOD = .Near) {
    world_architecture_oriented(world_architecture_entrance_oriented(structure), project, lod)
}

world_architecture_alley_color :: proc(
    alley: architecture.City_Alley,
    preview, stair: bool,
    town: bool = false,
    aegean: bool = false,
) -> canvas2d.Color {
    if preview do return {176, 161, 128, 150}
    // Town access is civic fabric, not a hierarchy of rural tracks. Even a
    // one-house branch is a paved calle or stepped vicolo once it enters the
    // compact settlement envelope.
    if town do return aegean ? canvas2d.Color{181, 177, 161, 255} : canvas2d.Color{142, 139, 128, 255}
    if stair do return {139, 126, 103, 255}
    switch settlement_access_surface(alley) {
    case .Stone:
        return {142, 139, 128, 255}
    case .Gravel:
        return {151, 137, 110, 255}
    case .Packed_Earth:
        return {157, 135, 99, 255}
    }
    return {157, 135, 99, 255}
}

world_architecture_alley_render_cache :: proc(
    editor: ^Editor,
    plan: ^architecture.City_Plan,
    alley_index: int,
) -> ^Architecture_Alley_Render_Cache {
    if editor == nil || plan == nil || alley_index < 0 || alley_index >= plan.alley_count do return nil
    if world_renderer.architecture_alley_terrain_revision != editor.terrain_revision ||
       world_renderer.architecture_alley_project_revision != editor.project.revision {
        for &entry in world_renderer.architecture_alley_render_cache do entry.valid = false
        world_renderer.architecture_alley_terrain_revision = editor.terrain_revision
        world_renderer.architecture_alley_project_revision = editor.project.revision
    }
    if len(world_renderer.architecture_alley_render_cache) < plan.alley_count {
        resize(&world_renderer.architecture_alley_render_cache, plan.alley_count)
    }
    entry := &world_renderer.architecture_alley_render_cache[alley_index]
    alley := plan.alleys[alley_index]
    if entry.valid && entry.alley == alley do return entry

    entry^ = {
        valid = true,
        alley = alley,
    }
    entry.start_height = terrain.sample_height(&editor.project, 0, alley.start_x, alley.start_z)
    entry.end_height = terrain.sample_height(&editor.project, 0, alley.end_x, alley.end_z)
    curve := settlement_access_alley_curve(plan, alley_index)
    entry.curve_segments = settlement_access_curve_sample_count(curve)
    entry.curve_points[0] = curve.points[0]
    previous := entry.curve_points[0]
    previous_height := terrain.sample_height(&editor.project, 0, previous[0], previous[1])
    for curve_index in 1 ..= entry.curve_segments {
        amount := f32(curve_index) / f32(entry.curve_segments)
        current := settlement_access_curve_point(curve, amount)
        entry.curve_points[curve_index] = current
        run := linalg.length(current - previous)
        current_height := terrain.sample_height(&editor.project, 0, current[0], current[1])
        if run > .01 do entry.grade = max(entry.grade, math.abs(current_height - previous_height) / run)
        entry.curve_distances[curve_index] = entry.curve_distances[curve_index - 1] + run
        previous, previous_height = current, current_height
    }
    entry.curve_length = entry.curve_distances[entry.curve_segments]
    return entry
}

world_architecture_alley_overlap_plan_sync :: proc(plan: ^architecture.City_Plan) {
    if plan == nil do return
    changed := len(world_renderer.architecture_alley_overlap_plan) != plan.alley_count
    if !changed {
        for alley, index in plan.alleys[:plan.alley_count] {
            if world_renderer.architecture_alley_overlap_plan[index] != alley {
                changed = true
                break
            }
        }
    }
    if !changed do return
    resize(&world_renderer.architecture_alley_overlap_plan, plan.alley_count)
    copy(world_renderer.architecture_alley_overlap_plan[:], plan.alleys[:plan.alley_count])
    for &entry in world_renderer.architecture_alley_overlap_cache do entry.valid = false
}

world_architecture_structure_overlaps_alley_cached :: proc(
    plan: ^architecture.City_Plan,
    structure: terrain.Structure,
    structure_index: int,
) -> bool {
    if plan == nil || structure_index < 0 do return false
    if len(world_renderer.architecture_alley_overlap_cache) <= structure_index {
        resize(&world_renderer.architecture_alley_overlap_cache, structure_index + 1)
    }
    entry := &world_renderer.architecture_alley_overlap_cache[structure_index]
    if !entry.valid || entry.structure != structure {
        entry.valid = true
        entry.structure = structure
        entry.overlaps = settlement_access_structure_overlaps_alley(plan, structure)
    }
    return entry.overlaps
}

world_architecture_alleys :: proc(editor: ^Editor, plan: ^architecture.City_Plan, preview: bool = false) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "world_architecture_alleys")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    if editor == nil || plan == nil do return
    cacheable := !preview && !world_renderer.architecture_alley_geometry_building
    if cacheable {
        plan_matches := len(world_renderer.architecture_alley_geometry_plan) == plan.alley_count
        if plan_matches {
            for alley, index in plan.alleys[:plan.alley_count] {
                if world_renderer.architecture_alley_geometry_plan[index] != alley {
                    plan_matches = false
                    break
                }
            }
        }
        cache_valid :=
            world_renderer.architecture_alley_geometry_valid &&
            world_renderer.architecture_alley_geometry_terrain_revision == editor.terrain_revision &&
            world_renderer.architecture_alley_geometry_project_revision == editor.project.revision &&
            plan_matches
        if cache_valid {
            append(&world_renderer.vertices, ..world_renderer.architecture_alley_geometry_cache[:])
            return
        }
    }
    geometry_first := len(world_renderer.vertices)
    town_surface := editor.settlement_plan.valid && editor.settlement_plan.request.scale == .Town
    aegean_surface := editor.settlement_plan.valid && editor.settlement_plan.request.region == .Aegean
    if cacheable do world_renderer.architecture_alley_geometry_building = true
    defer {
        if cacheable {
            clear(&world_renderer.architecture_alley_geometry_cache)
            append(&world_renderer.architecture_alley_geometry_cache, ..world_renderer.vertices[geometry_first:])
            resize(&world_renderer.architecture_alley_geometry_plan, plan.alley_count)
            copy(world_renderer.architecture_alley_geometry_plan[:], plan.alleys[:plan.alley_count])
            world_renderer.architecture_alley_geometry_terrain_revision = editor.terrain_revision
            world_renderer.architecture_alley_geometry_project_revision = editor.project.revision
            world_renderer.architecture_alley_geometry_valid = true
            world_renderer.architecture_alley_geometry_building = false
        }
    }
    for alley, alley_index in plan.alleys[:plan.alley_count] {
        dx, dz := alley.end_x - alley.start_x, alley.end_z - alley.start_z
        length := f32(math.sqrt(f64(dx * dx + dz * dz)))
        if length <= .01 do continue
        center_x, center_z := (alley.start_x + alley.end_x) * .5, (alley.start_z + alley.end_z) * .5
        center_y := terrain.sample_height(&editor.project, 0, center_x, center_z)
        if !cacheable &&
           !world_sphere_in_view(editor, {center_x, center_y, center_z}, length * .5 + alley.half_width + 1) {
            continue
        }
        start_height := f32(0)
        end_height := f32(0)
        curve_segments := 0
        curve_points: [13][2]f32
        curve_distances: [13]f32
        grade := f32(0)
        if !preview {
            cache := world_architecture_alley_render_cache(editor, plan, alley_index)
            if cache == nil do continue
            start_height = cache.start_height
            end_height = cache.end_height
            curve_segments = cache.curve_segments
            curve_points = cache.curve_points
            curve_distances = cache.curve_distances
            grade = cache.grade
        } else {
            start_height = terrain.sample_height(&editor.project, 0, alley.start_x, alley.start_z)
            end_height = terrain.sample_height(&editor.project, 0, alley.end_x, alley.end_z)
            curve := settlement_access_alley_curve(plan, alley_index)
            curve_segments = settlement_access_curve_sample_count(curve)
            curve_points[0] = curve.points[0]
            previous := curve_points[0]
            previous_height := terrain.sample_height(&editor.project, 0, previous[0], previous[1])
            for curve_index in 1 ..= curve_segments {
                amount := f32(curve_index) / f32(curve_segments)
                current := settlement_access_curve_point(curve, amount)
                curve_points[curve_index] = current
                run := linalg.length(current - previous)
                current_height := terrain.sample_height(&editor.project, 0, current[0], current[1])
                if run > .01 do grade = max(grade, math.abs(current_height - previous_height) / run)
                curve_distances[curve_index] = curve_distances[curve_index - 1] + run
                previous, previous_height = current, current_height
            }
        }
        curve_length := curve_distances[curve_segments]
        stair := !preview && grade >= SETTLEMENT_ACCESS_STAIR_GRADE
        surface_color := world_architecture_alley_color(alley, preview, stair, town_surface, aegean_surface)
        previous := curve_points[0]
        // Each sampled span is rendered as a capsule rather than an isolated
        // rectangle. Overlapping round pads remove polygonal outside corners
        // and make neighboring curves melt into a single walked surface.
        if !stair {
            world_land_surface_disc(editor, previous[0], previous[1], alley.half_width, .13, surface_color)
        }
        for curve_index in 1 ..= curve_segments {
            current := curve_points[curve_index]
            segment_dx, segment_dz := current[0] - previous[0], current[1] - previous[1]
            segment_length := f32(math.sqrt(f64(segment_dx * segment_dx + segment_dz * segment_dz)))
            if segment_length > .01 && !stair {
                world_land_surface_rotated(
                    editor,
                    (previous[0] + current[0]) * .5,
                    (previous[1] + current[1]) * .5,
                    segment_length + .04,
                    alley.half_width * 2,
                    f32(math.atan2(f64(segment_dz), f64(segment_dx))),
                    .13,
                    surface_color,
                )
                world_land_surface_disc(editor, current[0], current[1], alley.half_width, .13, surface_color)
            }
            previous = current
        }
        door_terminals := [2]architecture.City_Alley_Terminal{alley.start_terminal, alley.end_terminal}
        for terminal, endpoint_index in door_terminals {
            if terminal != .Door do continue
            door_x, door_z := alley.start_x, alley.start_z
            direction_x, direction_z := dx, dz
            if endpoint_index == 1 {
                door_x, door_z = alley.end_x, alley.end_z
                direction_x, direction_z = -dx, -dz
            }
            apron_length, apron_width := settlement_access_door_apron(
                editor.settlement_plan.request.scale,
                alley,
                length,
            )
            apron_center_x := door_x + direction_x / length * apron_length * .5
            apron_center_z := door_z + direction_z / length * apron_length * .5
            world_land_surface_rotated(
                editor,
                apron_center_x,
                apron_center_z,
                apron_length,
                apron_width,
                f32(math.atan2(f64(direction_z), f64(direction_x))),
                .14,
                surface_color,
            )
        }
        road_terminals := [2]architecture.City_Alley_Terminal{alley.start_terminal, alley.end_terminal}
        for terminal, endpoint_index in road_terminals {
            if terminal != .Road do continue
            road_x, road_z := alley.start_x, alley.start_z
            inward_x, inward_z := dx, dz
            if endpoint_index == 1 {
                road_x, road_z = alley.end_x, alley.end_z
                inward_x, inward_z = -dx, -dz
            }
            apron_run, outer_width, apron_valid := settlement_access_road_apron(alley, length)
            if !apron_valid do continue
            world_land_surface_tapered(
                editor,
                road_x,
                road_z,
                inward_x,
                inward_z,
                apron_run,
                alley.half_width * 2,
                outer_width,
                .14,
                surface_color,
            )
        }
        if !preview && stair {
            // Terrain-sampled solids turn the generated access spline into an
            // actual stair rather than a continuous ramp with decorative
            // nosings. Each tread follows the curved route independently.
            // Door, road, and public-space terminals retain a clear landing
            // instead of carrying a riser directly against the threshold.
            run_start, run_finish, run_valid := settlement_access_stair_nosing_range(alley, curve_length)
            landing_lengths := [2]f32 {
                alley.start_terminal != .None ? min(f32(.65), curve_length * .5) : 0,
                alley.end_terminal != .None ? min(f32(.65), curve_length * .5) : 0,
            }
            for landing_length, endpoint_index in landing_lengths {
                if landing_length <= .01 do continue
                distance := endpoint_index == 0 ? landing_length * .5 : curve_length - landing_length * .5
                endpoint_height := start_height
                if endpoint_index == 1 do endpoint_height = end_height
                sample_index := 1
                for sample_index < curve_segments && curve_distances[sample_index] < distance {
                    sample_index += 1
                }
                span := max(curve_distances[sample_index] - curve_distances[sample_index - 1], f32(.001))
                span_amount := (distance - curve_distances[sample_index - 1]) / span
                point :=
                    curve_points[sample_index - 1] +
                    (curve_points[sample_index] - curve_points[sample_index - 1]) * span_amount
                tangent := linalg.normalize0(curve_points[sample_index] - curve_points[sample_index - 1])
                yaw := f32(math.atan2(f64(tangent[1]), f64(tangent[0])))
                landing_width := alley.half_width * 1.9
                terminal := endpoint_index == 0 ? alley.start_terminal : alley.end_terminal
                if terminal == .Door {
                    landing_width = max(landing_width, settlement_access_door_apron_width(alley))
                }
                world_box_rotated(
                    {point[0], endpoint_height + .08, point[1]},
                    {landing_length, .08, landing_width},
                    yaw,
                    surface_color,
                )
            }
            if !run_valid do continue
            run_length := run_finish - run_start
            rest_count := settlement_access_stair_rest_count(run_length)
            rest_length := f32(1.05)
            for rest_index in 0 ..< rest_count {
                distance := run_start + f32(rest_index + 1) / f32(rest_count + 1) * run_length
                sample_index := 1
                for sample_index < curve_segments && curve_distances[sample_index] < distance {
                    sample_index += 1
                }
                span := max(curve_distances[sample_index] - curve_distances[sample_index - 1], f32(.001))
                span_amount := (distance - curve_distances[sample_index - 1]) / span
                point :=
                    curve_points[sample_index - 1] +
                    (curve_points[sample_index] - curve_points[sample_index - 1]) * span_amount
                tangent := linalg.normalize0(curve_points[sample_index] - curve_points[sample_index - 1])
                yaw := f32(math.atan2(f64(tangent[1]), f64(tangent[0])))
                before := point - tangent * (rest_length * .5)
                after := point + tangent * (rest_length * .5)
                ground_before := terrain.sample_height(&editor.project, 0, before[0], before[1])
                ground_center := terrain.sample_height(&editor.project, 0, point[0], point[1])
                ground_after := terrain.sample_height(&editor.project, 0, after[0], after[1])
                top := max(max(ground_before, ground_center), ground_after) + .12
                bottom := min(min(ground_before, ground_center), ground_after) - .04
                landing_height := max(top - bottom, f32(.16))
                world_box_rotated(
                    {point[0], bottom + landing_height * .5, point[1]},
                    {rest_length, landing_height, alley.half_width * 2.1},
                    yaw,
                    surface_color,
                )
            }
            step_count := max(1, int(math.ceil(f64(run_length / .42))))
            for step_index in 0 ..< step_count {
                distance_0 := run_start + f32(step_index) / f32(step_count) * run_length
                distance_1 := run_start + f32(step_index + 1) / f32(step_count) * run_length
                if settlement_access_stair_interval_overlaps_rest(
                    distance_0,
                    distance_1,
                    run_start,
                    run_length,
                    rest_count,
                    rest_length,
                ) {
                    continue
                }
                distance := (distance_0 + distance_1) * .5
                sample_index := 1
                for sample_index < curve_segments && curve_distances[sample_index] < distance {
                    sample_index += 1
                }
                span := max(curve_distances[sample_index] - curve_distances[sample_index - 1], f32(.001))
                span_amount := (distance - curve_distances[sample_index - 1]) / span
                point :=
                    curve_points[sample_index - 1] +
                    (curve_points[sample_index] - curve_points[sample_index - 1]) * span_amount
                tangent := linalg.normalize0(curve_points[sample_index] - curve_points[sample_index - 1])
                yaw := f32(math.atan2(f64(tangent[1]), f64(tangent[0])))
                step_y := terrain.sample_height(&editor.project, 0, point[0], point[1])
                distance_span := run_length / f32(step_count)
                before := point - tangent * (distance_span * .5)
                after := point + tangent * (distance_span * .5)
                ground_before := terrain.sample_height(&editor.project, 0, before[0], before[1])
                ground_after := terrain.sample_height(&editor.project, 0, after[0], after[1])
                top := step_y + .12
                bottom := min(min(ground_before, ground_after), step_y) - .04
                tread_height := max(top - bottom, f32(.12))
                tread_color := surface_color
                if town_surface && step_index % 4 == 1 {
                    tread_color = {132, 130, 120, 255}
                } else if !town_surface && step_index % 4 == 1 {
                    tread_color = {132, 119, 97, 255}
                }
                world_box_rotated(
                    {point[0], bottom + tread_height * .5, point[1]},
                    {distance_span + .04, tread_height, alley.half_width * 1.9},
                    yaw,
                    tread_color,
                )
            }
        }
    }
    seen := make([dynamic][2]f32, context.temp_allocator)
    for alley in plan.alleys[:plan.alley_count] {
        endpoints := [2][2]f32{{alley.start_x, alley.start_z}, {alley.end_x, alley.end_z}}
        for point in endpoints {
            duplicate := false
            for existing in seen {
                if settlement_alley_point_near(existing, point) {
                    duplicate = true
                    break
                }
            }
            if duplicate do continue
            append(&seen, point)
            radius := settlement_access_node_paving_radius(plan, point)
            if radius <= .01 do continue
            height := terrain.sample_height(&editor.project, 0, point[0], point[1])
            if !cacheable && !world_sphere_in_view(editor, {point[0], height, point[1]}, radius + 1) do continue
            pad_alley := alley
            for candidate in plan.alleys[:plan.alley_count] {
                if candidate.household_demand <= pad_alley.household_demand do continue
                if settlement_alley_point_near(point, {candidate.start_x, candidate.start_z}) ||
                   settlement_alley_point_near(point, {candidate.end_x, candidate.end_z}) {
                    pad_alley = candidate
                }
            }
            pad_color := world_architecture_alley_color(pad_alley, preview, false, town_surface, aegean_surface)
            world_land_surface_disc(editor, point[0], point[1], radius, .135, pad_color)
        }
    }
}

// Compact Riviera buildings meet stone, not a halo of untouched lawn. A
// narrow terrain-following skirt anchors each accepted Town mass and lets
// door aprons and vicoli merge into one continuous inhabited surface. The
// strip is presentation-only: access clearance and attachment topology still
// come from the authored settlement plan.
world_settlement_town_skirt_supported :: proc(
    editor: ^Editor,
    center_x, center_z, length, rotation, building_base_y: f32,
) -> bool {
    if editor == nil do return false
    tangent := [2]f32{math.cos(rotation), math.sin(rotation)}
    half_run := max(length * .5 - .12, f32(0))
    heights := [3]f32 {
        terrain.sample_height(&editor.project, 0, center_x - tangent[0] * half_run, center_z - tangent[1] * half_run),
        terrain.sample_height(&editor.project, 0, center_x, center_z),
        terrain.sample_height(&editor.project, 0, center_x + tangent[0] * half_run, center_z + tangent[1] * half_run),
    }
    low, high := heights[0], heights[0]
    for height in heights[1:] {
        low, high = min(low, height), max(high, height)
    }
    // Do not drape paving down a bank or draw a detached stripe beneath an
    // elevated foundation. Those buildings are intentionally grounded by
    // masonry and their explicit stair landing instead.
    return high - low <= .20 && math.abs((low + high) * .5 - building_base_y) <= .28
}
