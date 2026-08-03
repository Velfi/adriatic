package main

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math"
import "core:testing"
import canvas2d "zelda_engine:canvas2d"

// Farm compounds are derived presentation/planning state. They deliberately
// contain no fixture-owned references: placement, farmland, and rendering can
// reconstruct the same bounded geometry from the committed farmstead.
Farm_Compound :: struct {
    region:                                 Settlement_Region,
    host_id:                                u64,
    host_footprint:                         architecture.Architecture_Footprint,
    center, envelope_center:                [2]f32,
    rotation:                               f32,
    envelope_width, envelope_depth:         f32,
    yard_center:                            [2]f32,
    yard_width, yard_depth:                 f32,
    threshing_center:                       [2]f32,
    threshing_radius:                       f32,
    field_gate, field_anchor:               [2]f32,
    field_yaw:                              f32,
    field_scale_x, field_scale_z:           f32,
    utility_center:                         [2]f32,
    shelter_center:                         [2]f32,
    has_thresher, has_shelter, has_lean_to: bool,
}

farm_compound_local_point :: #force_inline proc(compound: Farm_Compound, x, z: f32) -> [2]f32 {
    cosine, sine := f32(math.cos(f64(compound.rotation))), f32(math.sin(f64(compound.rotation)))
    return {compound.center[0] + x * cosine - z * sine, compound.center[1] + x * sine + z * cosine}
}

farm_compound_derive :: proc(
    region: Settlement_Region,
    host: terrain.Structure,
    project: ^terrain.Project = nil,
) -> Farm_Compound {
    aegean := region == .Aegean
    side := host.seed & 1 == 0 ? f32(-1) : f32(1)
    yard_width := clamp(host.width * (aegean ? f32(.72) : f32(.86)), f32(6.5), aegean ? f32(11) : f32(14))
    yard_depth := clamp(host.depth * (aegean ? f32(.52) : f32(.62)), f32(5.5), aegean ? f32(9) : f32(11))
    yard_offset := host.depth * .5 + yard_depth * .5 + (aegean ? f32(.75) : f32(1.0))
    compound := Farm_Compound {
        region           = region,
        host_id          = host.id,
        host_footprint   = architecture.architecture_footprint(host),
        center           = {host.center_x, host.center_z},
        rotation         = host.rotation,
        envelope_width   = max(host.width + 5, yard_width + (aegean ? f32(8) : f32(11))),
        envelope_depth   = host.depth + yard_depth + (aegean ? f32(12) : f32(15)),
        yard_width       = yard_width,
        yard_depth       = yard_depth,
        threshing_radius = aegean ? f32(3.2) : f32(3.8),
        field_yaw        = host.rotation,
        field_scale_x    = aegean ? f32(.76) : f32(1.12),
        field_scale_z    = aegean ? f32(1.18) : f32(.94),
        has_thresher     = true,
        has_shelter      = host.seed % (aegean ? u32(4) : u32(3)) == 0,
        has_lean_to      = !aegean && host.seed % 3 != 1,
    }
    compound.yard_center = farm_compound_local_point(compound, 0, -yard_offset)
    compound.field_gate = farm_compound_local_point(compound, 0, -(yard_offset + yard_depth * .5))
    field_distance := yard_offset + yard_depth * .5 + (aegean ? f32(6) : f32(7))
    compound.field_anchor = farm_compound_local_point(compound, 0, -field_distance)
    compound.threshing_center = farm_compound_local_point(
        compound,
        side * (yard_width * .5 + compound.threshing_radius + .8),
        -yard_offset,
    )
    compound.utility_center = farm_compound_local_point(compound, -side * (yard_width * .5 + 1.0), -yard_offset)
    compound.shelter_center = farm_compound_local_point(
        compound,
        -side * (yard_width * .5 + (aegean ? f32(3.2) : f32(4.2))),
        -(yard_offset + yard_depth * .35),
    )
    front := max(f32(2), compound.envelope_depth * .16)
    rear := compound.envelope_depth - front
    compound.envelope_center = farm_compound_local_point(compound, 0, -(rear - front) * .5)
    if aegean && project != nil {
        sample := f32(4)
        east := terrain.sample_surface_height(project, 0, compound.field_anchor[0] + sample, compound.field_anchor[1])
        west := terrain.sample_surface_height(project, 0, compound.field_anchor[0] - sample, compound.field_anchor[1])
        north := terrain.sample_surface_height(project, 0, compound.field_anchor[0], compound.field_anchor[1] + sample)
        south := terrain.sample_surface_height(project, 0, compound.field_anchor[0], compound.field_anchor[1] - sample)
        gradient := [2]f32{east - west, north - south}
        if gradient[0] * gradient[0] + gradient[1] * gradient[1] > .0001 {
            // Farmland local X is the long terrace axis. Align it to the
            // contour, perpendicular to the direction of steepest ascent.
            compound.field_yaw = f32(math.atan2(f64(-gradient[0]), f64(gradient[1])))
        }
    }
    return compound
}

farm_compound_contains_point :: #force_inline proc(compound: Farm_Compound, x, z: f32, margin: f32 = 0) -> bool {
    cosine, sine := f32(math.cos(f64(compound.rotation))), f32(math.sin(f64(compound.rotation)))
    dx, dz := x - compound.center[0], z - compound.center[1]
    local_x := dx * cosine + dz * sine
    local_z := -dx * sine + dz * cosine
    // The envelope extends predominantly behind the farmhouse, where the
    // work yard and field gate live, while retaining a small front margin.
    front := max(f32(2), compound.envelope_depth * .16)
    rear := compound.envelope_depth - front
    return(
        math.abs(local_x) <= compound.envelope_width * .5 + margin &&
        local_z <= front + margin &&
        local_z >= -rear - margin \
    )
}

farm_compound_host_for_barn :: proc(
    city_plan: ^architecture.City_Plan,
    region: Settlement_Region,
    ordinal: int,
    project: ^terrain.Project = nil,
) -> (
    Farm_Compound,
    bool,
) {
    if city_plan == nil do return {}, false
    host_indices: [8]int
    host_count := 0
    for structure, index in city_plan.structures[:city_plan.count] {
        identity := architecture.architecture_resolve_legacy_identity(structure)
        if identity.archetype != .Farmstead do continue
        if host_count < len(host_indices) {
            host_indices[host_count] = index
            host_count += 1
        }
    }
    if host_count <= 0 do return {}, false
    host := city_plan.structures[host_indices[abs(ordinal) % host_count]]
    return farm_compound_derive(region, host, project), true
}

farm_compound_envelope_clear :: proc(
    city_plan: ^architecture.City_Plan,
    candidate: Farm_Compound,
    project: ^terrain.Project = nil,
) -> bool {
    if city_plan == nil do return true
    for structure in city_plan.structures[:city_plan.count] {
        identity := architecture.architecture_resolve_legacy_identity(structure)
        if identity.archetype != .Farmstead do continue
        existing := farm_compound_derive(candidate.region, structure, project)
        if !settlement_oriented_rectangles_clear(
            candidate.envelope_center[0],
            candidate.envelope_center[1],
            candidate.envelope_width,
            candidate.envelope_depth,
            candidate.rotation,
            existing.envelope_center[0],
            existing.envelope_center[1],
            existing.envelope_width,
            existing.envelope_depth,
            existing.rotation,
            2,
        ) {
            return false
        }
    }
    return true
}

farm_compound_structure_clear :: proc(
    city_plan: ^architecture.City_Plan,
    region: Settlement_Region,
    x, z, width, depth, rotation: f32,
    allowed_host: ^Farm_Compound = nil,
    project: ^terrain.Project = nil,
) -> bool {
    if city_plan == nil do return true
    for structure in city_plan.structures[:city_plan.count] {
        identity := architecture.architecture_resolve_legacy_identity(structure)
        if identity.archetype != .Farmstead do continue
        compound := farm_compound_derive(region, structure, project)
        if allowed_host != nil && compound.center == allowed_host.center do continue
        if !settlement_oriented_rectangles_clear(
            x,
            z,
            width,
            depth,
            rotation,
            compound.envelope_center[0],
            compound.envelope_center[1],
            compound.envelope_width,
            compound.envelope_depth,
            compound.rotation,
            .45,
        ) {
            return false
        }
    }
    return true
}

farm_compound_feature_on_land :: proc(project: ^terrain.Project, point: [2]f32, radius: f32) -> bool {
    if project == nil do return false
    center := terrain.sample_surface_height(project, 0, point[0], point[1])
    if center <= project.sea_level + .35 || terrain.active_waterway_at(project, 0, point[0], point[1]) do return false
    directions := [4][2]f32{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
    for direction in directions {
        sample := point + direction * radius
        height := terrain.sample_surface_height(project, 0, sample[0], sample[1])
        if height <= project.sea_level + .35 || math.abs(height - center) > .75 do return false
    }
    return true
}

farm_compound_feature_clear :: proc(editor: ^Editor, compound: Farm_Compound, point: [2]f32, radius: f32) -> bool {
    if editor == nil do return false
    for site in editor.settlement_plan.sites[:editor.settlement_plan.site_count] {
        if !site.accepted || site.structure.id == compound.host_id do continue
        if settlement_point_structure_footprint_distance(point, site.structure) < radius do return false
    }
    return true
}

world_farm_compound_wall :: proc(editor: ^Editor, compound: Farm_Compound, ax, az, bx, bz: f32) {
    a := farm_compound_local_point(compound, ax, az)
    b := farm_compound_local_point(compound, bx, bz)
    midpoint := (a + b) * .5
    if !farm_compound_feature_on_land(&editor.project, midpoint, .35) ||
       !farm_compound_feature_clear(editor, compound, midpoint, .6) {
        return
    }
    delta := b - a
    length := f32(math.sqrt(f64(delta[0] * delta[0] + delta[1] * delta[1])))
    y := terrain.sample_surface_height(&editor.project, 0, midpoint[0], midpoint[1])
    color := compound.region == .Aegean ? canvas2d.Color{151, 151, 139, 255} : canvas2d.Color{157, 151, 132, 255}
    world_box_rotated(
        {midpoint[0], y + .36, midpoint[1]},
        {length, .72, .48},
        f32(math.atan2(f64(delta[1]), f64(delta[0]))),
        color,
    )
}

world_farm_compound_shelter :: proc(editor: ^Editor, compound: Farm_Compound) {
    point := compound.shelter_center
    if !compound.has_shelter ||
       !farm_compound_feature_on_land(&editor.project, point, 2.2) ||
       !farm_compound_feature_clear(editor, compound, point, 2.4) {
        return
    }
    y := terrain.sample_surface_height(&editor.project, 0, point[0], point[1])
    stone := compound.region == .Aegean ? canvas2d.Color{149, 146, 132, 255} : canvas2d.Color{143, 140, 124, 255}
    if compound.region == .Aegean {
        world_box_rotated({point[0], y + 1.15, point[1]}, {3.6, 2.3, 3.0}, compound.rotation, stone)
        world_box_rotated({point[0], y + 2.38, point[1]}, {3.9, .16, 3.3}, compound.rotation, {183, 180, 163, 255})
    } else {
        // Stacked low drums suggest the corbelled profile of a bunja/kažun
        // without adding a fixture-backed mesh asset.
        for course in 0 ..< 5 {
            radius := 2.1 - f32(course) * .31
            height := f32(.46)
            world_ellipse_material_uv(
                {point[0], y + f32(course) * .42 + height * .5, point[1]},
                radius,
                radius,
                0,
                stone,
                .BRDF,
            )
        }
    }
}

world_farm_compound :: proc(editor: ^Editor, compound: Farm_Compound) {
    if editor == nil do return
    yard := compound.yard_center
    if farm_compound_feature_on_land(&editor.project, yard, min(compound.yard_width, compound.yard_depth) * .35) {
        y := terrain.sample_surface_height(&editor.project, 0, yard[0], yard[1])
        paving := compound.region == .Aegean ? canvas2d.Color{194, 190, 169, 255} : canvas2d.Color{174, 157, 125, 255}
        world_box_rotated(
            {yard[0], y + .025, yard[1]},
            {compound.yard_width, .05, compound.yard_depth},
            compound.rotation,
            paving,
        )
        half_width, half_depth := compound.yard_width * .5, compound.yard_depth * .5
        world_farm_compound_wall(editor, compound, -half_width, -half_depth, -half_width, half_depth)
        world_farm_compound_wall(editor, compound, half_width, -half_depth, half_width, half_depth)
        // Leave the field gate open in the rear wall.
        gate_half := f32(1.25)
        world_farm_compound_wall(editor, compound, -half_width, -half_depth, -gate_half, -half_depth)
        world_farm_compound_wall(editor, compound, gate_half, -half_depth, half_width, -half_depth)
    }
    if compound.has_thresher &&
       farm_compound_feature_on_land(&editor.project, compound.threshing_center, compound.threshing_radius) {
        point := compound.threshing_center
        y := terrain.sample_surface_height(&editor.project, 0, point[0], point[1])
        world_ellipse_material_uv(
            {point[0], y + .08, point[1]},
            compound.threshing_radius,
            compound.threshing_radius,
            compound.rotation,
            compound.region == .Aegean ? canvas2d.Color{186, 181, 159, 255} : canvas2d.Color{166, 151, 124, 255},
            .BRDF,
        )
    }
    gate_delta := compound.field_anchor - compound.field_gate
    gate_length := f32(math.sqrt(f64(gate_delta[0] * gate_delta[0] + gate_delta[1] * gate_delta[1])))
    if gate_length > .2 {
        gate_midpoint := (compound.field_anchor + compound.field_gate) * .5
        if farm_compound_feature_on_land(&editor.project, gate_midpoint, .8) {
            y := terrain.sample_surface_height(&editor.project, 0, gate_midpoint[0], gate_midpoint[1])
            world_box_rotated(
                {gate_midpoint[0], y + .018, gate_midpoint[1]},
                {gate_length, .036, compound.region == .Aegean ? f32(1.35) : f32(2.0)},
                f32(math.atan2(f64(gate_delta[1]), f64(gate_delta[0]))),
                compound.region == .Aegean ? canvas2d.Color{173, 164, 142, 255} : canvas2d.Color{139, 119, 89, 255},
            )
        }
    }
    utility := compound.utility_center
    if farm_compound_feature_on_land(&editor.project, utility, 1.2) &&
       farm_compound_feature_clear(editor, compound, utility, 1.4) {
        y := terrain.sample_surface_height(&editor.project, 0, utility[0], utility[1])
        if compound.region == .Aegean {
            world_ellipse_material_uv({utility[0], y + .18, utility[1]}, 1.25, 1.25, 0, {139, 145, 139, 255}, .BRDF)
            world_ellipse_material_uv({utility[0], y + .38, utility[1]}, .72, .72, 0, {60, 74, 76, 255}, .BRDF)
            oven := farm_compound_local_point(compound, compound.yard_width * .35, -(compound.yard_depth + 2.0))
            if farm_compound_feature_on_land(&editor.project, oven, 1.0) &&
               farm_compound_feature_clear(editor, compound, oven, 1.2) {
                oven_y := terrain.sample_surface_height(&editor.project, 0, oven[0], oven[1])
                world_box_rotated(
                    {oven[0], oven_y + .62, oven[1]},
                    {1.7, 1.24, 1.55},
                    compound.rotation,
                    {190, 186, 169, 255},
                )
                world_ellipse_material_uv(
                    {oven[0], oven_y + 1.24, oven[1]},
                    .86,
                    .78,
                    compound.rotation,
                    {205, 201, 184, 255},
                    .BRDF,
                )
            }
        } else {
            world_box_rotated(
                {utility[0], y + .34, utility[1]},
                {2.4, .68, .72},
                compound.rotation,
                {151, 142, 122, 255},
            )
        }
    }
    if compound.has_lean_to {
        lean := farm_compound_local_point(compound, 0, -(compound.yard_depth + 1.5))
        if farm_compound_feature_on_land(&editor.project, lean, 2.0) &&
           farm_compound_feature_clear(editor, compound, lean, 2.4) {
            y := terrain.sample_surface_height(&editor.project, 0, lean[0], lean[1])
            timber := canvas2d.Color{91, 69, 48, 255}
            for side in -1 ..= 1 {
                if side == 0 do continue
                post := farm_compound_local_point(compound, f32(side) * 2.0, -(compound.yard_depth + 1.5))
                world_box_rotated({post[0], y + 1.25, post[1]}, {.18, 2.5, .18}, compound.rotation, timber)
            }
            world_box_rotated({lean[0], y + 2.48, lean[1]}, {4.5, .18, 2.2}, compound.rotation, {131, 123, 103, 255})
        }
    }
    world_farm_compound_shelter(editor, compound)
}

world_farm_compounds :: proc(editor: ^Editor) {
    if editor == nil || !editor.settlement_plan.valid do return
    for site in editor.settlement_plan.sites[:editor.settlement_plan.site_count] {
        if !site.accepted || site.kind != .Ordinary || site.purpose != .Farmstead do continue
        world_farm_compound(
            editor,
            farm_compound_derive(editor.settlement_plan.request.region, site.structure, &editor.project),
        )
    }
}

@(test)
farm_compound_derivation_is_deterministic_and_region_specific :: proc(t: ^testing.T) {
    host := terrain.structure_make(100, 200, 18, 14, 0, 9.6)
    host.width, host.depth, host.rotation, host.seed = 18, 14, .35, 42
    first := farm_compound_derive(.Adriatic, host)
    repeated := farm_compound_derive(.Adriatic, host)
    aegean := farm_compound_derive(.Aegean, host)
    testing.expect_value(t, first, repeated)
    testing.expect(t, first.field_scale_x > first.field_scale_z)
    testing.expect(t, aegean.field_scale_x < aegean.field_scale_z)
    testing.expect(t, first.envelope_width > aegean.envelope_width)
    testing.expect(t, first.yard_center != aegean.yard_center)
}

@(test)
farm_compound_field_gate_connects_yard_to_reserved_field_edge :: proc(t: ^testing.T) {
    host := terrain.structure_make(100, 200, 20, 16, 0, 9.6)
    host.width, host.depth, host.rotation, host.seed = 20, 16, -.48, 7
    for region in Settlement_Region {
        compound := farm_compound_derive(region, host)
        testing.expect(t, farm_compound_contains_point(compound, compound.yard_center[0], compound.yard_center[1]))
        testing.expect(t, farm_compound_contains_point(compound, compound.field_gate[0], compound.field_gate[1], .01))
        gate_to_field := compound.field_anchor - compound.field_gate
        testing.expect(t, gate_to_field[0] * gate_to_field[0] + gate_to_field[1] * gate_to_field[1] > 4)
    }
}

@(test)
farm_compound_assigns_barns_to_hosts_round_robin :: proc(t: ^testing.T) {
    city: architecture.City_Plan
    defer architecture.city_plan_destroy(&city)
    for index in 0 ..< 2 {
        host := terrain.structure_make(f32(index * 40), 0, 18, 14, 0, 9.6)
        host.width, host.depth, host.seed = 18, 14, u32(index + 1)
        host.building.archetype = .Farmstead
        host.building.region = .Adriatic
        append(&city.structures, host)
        city.count += 1
    }
    first, first_found := farm_compound_host_for_barn(&city, .Adriatic, 0)
    second, second_found := farm_compound_host_for_barn(&city, .Adriatic, 1)
    wrapped, wrapped_found := farm_compound_host_for_barn(&city, .Adriatic, 2)
    testing.expect(t, first_found && second_found && wrapped_found)
    testing.expect(t, first.center != second.center)
    testing.expect_value(t, first.center, wrapped.center)
}
