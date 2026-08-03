package main
import "core:math"
import "core:time"

import architecture "../packages/architecture"
import buildings "../packages/buildings"
import circulation "../packages/circulation"
import dio "../packages/dio"
import fountains "../packages/fountains"
import plants "../packages/plants"
import plazas "../packages/plazas"
import terrain "../packages/terrain"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

world_town_mouse_wheel_position :: proc(area: circulation.Area) -> (x, z: f32) {
    wheel_radius := f32(1.68)
    local_x := max(-area.width * .5 + wheel_radius + .6, area.width * .5 - wheel_radius - .8)
    local_z := min(area.length * .24, area.length * .5 - wheel_radius - .55)
    return world_rotate_xz(area.center_x, area.center_z, local_x, local_z, area.rotation)
}

world_architecture_streets :: proc(editor: ^Editor, sun_direction: [3]f32, cloud_cover: f32) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "world_architecture_streets")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    if editor == nil || lab_scene_suppresses_procedural_circulation(editor) do return
    min_x, max_x := f32(1e9), f32(-1e9)
    min_z, max_z := f32(1e9), f32(-1e9)
    building_count := 0
    for structure in editor.project.structures[:editor.project.structure_count] {
        if structure.kind != .Architecture || structure.height > 60 do continue
        min_x = min(min_x, structure.center_x)
        max_x = max(max_x, structure.center_x)
        min_z = min(min_z, structure.center_z)
        max_z = max(max_z, structure.center_z)
        building_count += 1
    }
    if building_count < 4 || max_z <= min_z do return
    center_x := (min_x + max_x) * .5
    center_z := (min_z + max_z) * .5
    road_span := max(max_x - min_x + 36, 160)
    plan := editor_circulation_plan(editor)
    road := canvas2d.Color{117, 119, 110, 255}
    shoulder := canvas2d.Color{177, 164, 135, 255}
    path_color := canvas2d.Color{194, 184, 157, 255}
    if len(world_renderer.architecture_street_area_cache) < plan.count {
        resize(&world_renderer.architecture_street_area_cache, plan.count)
    }
    primary_plaza_index := -1
    primary_plaza_area := f32(0)
    for candidate, candidate_index in plan.areas[:plan.count] {
        if candidate.kind != .Plaza do continue
        candidate_area := candidate.width * candidate.length
        if candidate_area > primary_plaza_area {
            primary_plaza_area = candidate_area
            primary_plaza_index = candidate_index
        }
    }
    for area, area_index in plan.areas[:plan.count] {
        area_y := terrain.sample_surface_height(&editor.project, 0, area.center_x, area.center_z)
        area_radius := f32(math.sqrt(f64(area.width * area.width + area.length * area.length))) * .5 + 2
        if !world_sphere_in_view(editor, {area.center_x, area_y, area.center_z}, area_radius) do continue
        cache := &world_renderer.architecture_street_area_cache[area_index]
        cache_valid :=
            cache.valid &&
            cache.area == area &&
            cache.project_revision == editor.project.revision &&
            cache.terrain_revision == editor.terrain_revision
        if cache_valid {
            append(&world_renderer.vertices, ..cache.vertices[:])
        } else {
            first := len(world_renderer.vertices)
            switch area.kind {
            case .Street:
                world_land_surface_rotated(
                    editor,
                    area.center_x,
                    area.center_z,
                    area.width,
                    5.5,
                    area.rotation,
                    .12,
                    road,
                )
                for side in -1 ..= 1 {
                    if side == 0 do continue
                    offset_x := -math.sin(area.rotation) * f32(side) * 3.05
                    offset_z := math.cos(area.rotation) * f32(side) * 3.05
                    world_land_surface_rotated(
                        editor,
                        area.center_x + offset_x,
                        area.center_z + offset_z,
                        area.width,
                        .35,
                        area.rotation,
                        .15,
                        shoulder,
                    )
                }
                // Settlement routes author their own clearance-tested lamps. The
                // fallback grid exists for legacy/capture city plans; rendering
                // both systems produces clustered posts and stacked pools.
                if editor.architecture_city_plan.lamp_count == 0 {
                    lamp_count := clamp(int(area.width / 22), 2, 6)
                    for lamp in 0 ..< lamp_count {
                        along := -area.width * .5 + area.width * (f32(lamp) + .5) / f32(lamp_count)
                        side := lamp % 2 == 0 ? f32(-1) : f32(1)
                        lamp_x, lamp_z := world_rotate_xz(
                            area.center_x,
                            area.center_z,
                            along,
                            side * 3.65,
                            area.rotation,
                        )
                        world_architecture_municipal_lamp_fixture(
                            editor,
                            lamp_x,
                            lamp_z,
                            area.rotation + (side < 0 ? f32(0) : f32(math.PI)),
                        )
                    }
                }
            case .Plaza:
                seed := u32(i32(area.center_x * 10)) ~ (u32(i32(area.center_z * 10)) * u32(0x9e3779b9))
                plaza := plazas.generate(seed, area.width, area.length)
                for piece, piece_index in plaza.paving[:plaza.paving_count] {
                    piece_x, piece_z := world_rotate_xz(area.center_x, area.center_z, piece.x, piece.z, area.rotation)
                    color := canvas2d.Color{184, 177, 158, 255}
                    if piece.kind == .Border do color = {116, 111, 103, 255}
                    if piece.kind == .Mosaic || piece.kind == .Inlay {
                        mosaic_palette := [3]canvas2d.Color {
                            {77, 112, 119, 255},
                            {174, 91, 67, 255},
                            {211, 190, 135, 255},
                        }
                        color = mosaic_palette[piece.tone]
                    }
                    // Mosaic bars deliberately cross one another. Giving every
                    // decorative piece the same lift made those intersections
                    // coplanar and unstable in the depth buffer. Preserve the
                    // layered design with a sub-centimetre, deterministic stack;
                    // inlays sit above the mosaic as the final repair layer.
                    lift := f32(.16)
                    switch piece.kind {
                    case .Border:
                        lift = .19
                    case .Mosaic:
                        lift = .22 + f32(piece_index - 5) * .0005
                    case .Inlay:
                        lift = .24 + f32(piece_index - 21) * .0005
                    case .Field:
                    }
                    world_land_surface_rotated(
                        editor,
                        piece_x,
                        piece_z,
                        piece.width,
                        piece.length,
                        area.rotation + piece.rotation,
                        lift,
                        color,
                    )
                }
                // Cache the civic fountain's stonework and water surface with
                // the paving; only its time-dependent effects are emitted
                // after the static cache below.
                if area_index != primary_plaza_index && min(area.width, area.length) >= 16 {
                    fountain_radius := clamp(min(area.width, area.length) * .16, f32(2.4), f32(5.2))
                    fountain_style := fountains.Style(plazas.mix(seed ~ 0xA53C91E5) % 3)
                    fountain := fountains.generate(
                        seed ~ 0xF017A17,
                        {
                            radius = fountain_radius,
                            style = fountain_style,
                            jet_count = clamp(int(fountain_radius * 2.5), 6, 16),
                            jet_height = fountain_radius * .72,
                        },
                    )
                    fountain_y := terrain.sample_surface_height(&editor.project, 0, area.center_x, area.center_z) + .24
                    world_fountain_structure(&fountain, {area.center_x, fountain_y, area.center_z}, area.rotation)
                }
                for corner_x in -1 ..= 1 {
                    if corner_x == 0 do continue
                    for corner_z in -1 ..= 1 {
                        if corner_z == 0 do continue
                        lamp_x, lamp_z := world_rotate_xz(
                            area.center_x,
                            area.center_z,
                            f32(corner_x) * (area.width * .5 - 1.4),
                            f32(corner_z) * (area.length * .5 - 1.4),
                            area.rotation,
                        )
                        // local +Z rotates to (-sin(theta), cos(theta)); negate
                        // target X so the cantilever actually faces the square.
                        facing := f32(math.atan2(f64(lamp_x - area.center_x), f64(area.center_z - lamp_z)))
                        world_architecture_municipal_lamp_fixture(editor, lamp_x, lamp_z, facing)
                    }
                }
            case .Path, .Forecourt:
                world_land_surface_rotated(
                    editor,
                    area.center_x,
                    area.center_z,
                    area.width,
                    area.length,
                    area.rotation,
                    .20,
                    path_color,
                )
            }
            clear(&cache.vertices)
            append(&cache.vertices, ..world_renderer.vertices[first:])
            cache.area = area
            cache.project_revision = editor.project.revision
            cache.terrain_revision = editor.terrain_revision
            cache.valid = true
        }

        // Fountain spray, droplets, and impact rings depend on time. Emit only
        // those effects outside the plaza geometry cache so civic fountains
        // animate without rebuilding their stonework every frame.
        if area.kind == .Plaza && area_index != primary_plaza_index && min(area.width, area.length) >= 16 {
            seed := u32(i32(area.center_x * 10)) ~ (u32(i32(area.center_z * 10)) * u32(0x9e3779b9))
            fountain_radius := clamp(min(area.width, area.length) * .16, f32(2.4), f32(5.2))
            fountain_style := fountains.Style(plazas.mix(seed ~ 0xA53C91E5) % 3)
            fountain := fountains.generate(
                seed ~ 0xF017A17,
                {
                    radius = fountain_radius,
                    style = fountain_style,
                    jet_count = clamp(int(fountain_radius * 2.5), 6, 16),
                    jet_height = fountain_radius * .72,
                },
            )
            fountain_y := terrain.sample_surface_height(&editor.project, 0, area.center_x, area.center_z) + .24
            world_fountain_effects(&fountain, {area.center_x, fountain_y, area.center_z}, area.rotation)
        }

        if area_index == primary_plaza_index {
            wheel_x, wheel_z := world_town_mouse_wheel_position(area)
            wheel_y := terrain.sample_surface_height(&editor.project, 0, wheel_x, wheel_z)
            world_town_mouse_wheel(wheel_x, wheel_y, wheel_z, area.rotation, mouse_wheel_angle, mouse_wheel_jolt)
        }

        // Halos are camera-facing/daylight-sensitive and pools must remain in
        // the late transparent submission, so regenerate only these effects.
        if area.kind == .Street && editor.architecture_city_plan.lamp_count == 0 {
            lamp_count := clamp(int(area.width / 22), 2, 6)
            for lamp in 0 ..< lamp_count {
                along := -area.width * .5 + area.width * (f32(lamp) + .5) / f32(lamp_count)
                side := lamp % 2 == 0 ? f32(-1) : f32(1)
                lamp_x, lamp_z := world_rotate_xz(area.center_x, area.center_z, along, side * 3.65, area.rotation)
                world_architecture_municipal_lamp_effects(
                    editor,
                    lamp_x,
                    lamp_z,
                    area.rotation + (side < 0 ? f32(0) : f32(math.PI)),
                )
            }
        } else if area.kind == .Plaza {
            for corner_x in -1 ..= 1 {
                if corner_x == 0 do continue
                for corner_z in -1 ..= 1 {
                    if corner_z == 0 do continue
                    lamp_x, lamp_z := world_rotate_xz(
                        area.center_x,
                        area.center_z,
                        f32(corner_x) * (area.width * .5 - 1.4),
                        f32(corner_z) * (area.length * .5 - 1.4),
                        area.rotation,
                    )
                    facing := f32(math.atan2(f64(lamp_x - area.center_x), f64(area.center_z - lamp_z)))
                    world_architecture_municipal_lamp_effects(editor, lamp_x, lamp_z, facing, false)
                }
            }
        }
    }

    // Entrance decoration remains presentation-only, while the path beneath
    // it now comes from the shared circulation plan above.
    for structure in editor.project.structures[:editor.project.structure_count] {
        if structure.kind != .Architecture || structure.height > 60 do continue
        identity := architecture.architecture_resolve_legacy_identity(structure)
        if !buildings.is_habitable(identity.archetype) do continue
        if identity.archetype == .Mixed_Use_Dwelling {
            // Mixed-use storefronts own a commissioned climbing-plant pot at
            // the outer pier. Generic paired entrance pots collide with that
            // planter and create a blocky double-stack at its rim.
            continue
        }
        // The mass renderer owns pots on even seeds; keep this wider frontage
        // arrangement as the complementary residence variant, never a second
        // overlapping set.
        if structure.seed % 3 != 0 || structure.seed % 2 == 0 do continue
        structure_center, structure_radius := structure_visibility_sphere(structure)
        if !world_sphere_in_view(editor, structure_center, structure_radius, 2) do continue
        frontage := architecture.architecture_frontage_structure(structure)
        door_x, door_z := world_rotate_xz(
            frontage.center_x,
            frontage.center_z,
            0,
            frontage.depth * .5 + .22,
            frontage.rotation,
        )
        for pot_side in -1 ..= 1 {
            if pot_side == 0 do continue
            pot_x, pot_z := world_rotate_xz(
                door_x,
                door_z,
                f32(pot_side) * frontage.width * .27,
                .88,
                frontage.rotation,
            )
            world_architecture_residence_planter(
                &editor.project,
                pot_x,
                pot_z,
                frontage.rotation,
                structure.seed ~ 0x9e3779b9,
                pot_side,
                .44,
                cache_geometry = true,
            )
        }
    }
    world_architecture_laundry_webbing(editor)
    world_settlement_landscape(editor)
    world_settlement_gardens(editor)
    // Olive accents soften two lane intersections without changing terrain
    // data.
    for x_side in -1 ..= 1 {
        if x_side == 0 do continue
        for z_side in -1 ..= 1 {
            if z_side == 0 do continue
            tree_x := center_x + f32(x_side) * road_span * .42
            tree_z := center_z + f32(z_side) * ((max_z - min_z) * .5 + 7)
            tree_base := terrain.sample_surface_height(&editor.project, 0, tree_x, tree_z)
            if !world_sphere_in_view(editor, {tree_x, tree_base + 7, tree_z}, 8, 2) do continue
            if !architecture.city_accent_site_clear(&editor.project, tree_x, tree_z, 5) do continue
            if (x_side == -1 && z_side == 1) || (x_side == 1 && z_side == -1) {
                olive_x := tree_x - f32(x_side) * 8
                olive_z := tree_z - f32(z_side) * 5
                olive_base := terrain.sample_surface_height(&editor.project, 0, olive_x, olive_z)
                world_architecture_olive(
                    olive_x,
                    olive_z,
                    olive_base,
                    u32((x_side + 3) * 53 + (z_side + 3) * 17 + building_count * 9),
                )
            }
        }
    }
}

// Derive inhabited gardens from accepted settlement sites. The same
// settlement seed always produces the same planting, and previews remain
// presentation-only instead of mutating terrain structures.
settlement_structure_is_park_reservation :: proc(plan: ^Settlement_Plan, structure_id: u64) -> bool {
    if plan == nil || !plan.valid do return false
    for site in plan.sites[:plan.site_count] {
        if site.accepted && site.kind == .Park && site.structure.id == structure_id {
            return true
        }
    }
    return false
}

settlement_structure_is_decorative_grove :: proc(plan: ^Settlement_Plan, structure_id: u64) -> bool {
    if plan == nil || !plan.valid do return false
    for structure in plan.decorative_foliage[:plan.decorative_foliage_count] {
        if structure.id == structure_id do return true
    }
    return false
}

// Decorative town groves retain a foliage structure as their planning and
// collision reservation, but their visible canopy is assembled from the real
// generated-plant catalog. This keeps paths out of the planting bed without
// covering its individual trunks, crowns, and Mediterranean species with the
// legacy amorphous foliage hull.
world_settlement_decorative_grove :: proc(editor: ^Editor, structure: terrain.Structure) {
    if editor == nil do return
    count := clamp(int(math.round(structure.width * structure.depth / 34)), 4, 8)
    radius_x := max(structure.width * .34, f32(1.2))
    radius_z := max(structure.depth * .32, f32(1.1))
    for plant_index in 0 ..< count {
        mixed := garden_hash(structure.seed ~ u32(plant_index + 1) * u32(0x85ebca6b) ~ 0x47524f56)
        angle := f32(plant_index) / f32(count) * math.PI * 2 + f32(mixed & 63) / 63 * .24
        ring := plant_index == 0 ? f32(0) : (.62 + f32((mixed >> 8) & 31) / 100)
        local_x := math.cos(angle) * radius_x * ring
        local_z := math.sin(angle) * radius_z * ring
        x, z := world_rotate_xz(structure.center_x, structure.center_z, local_x, local_z, structure.rotation)
        base_y := terrain.sample_surface_height(&editor.project, 0, x, z)
        species, plant_scale, _ := settlement_garden_woody_species(
            editor.settlement_plan.request.region,
            .Park,
            plant_index,
            mixed,
        )
        _ = world_generated_plant(
            species,
            u64(mixed) ~ u64(structure.seed) << 32,
            {x, base_y, z},
            plant_scale * (.88 + f32((mixed >> 24) & 31) / 155),
            structure.rotation + angle + math.PI,
            .Free_Standing,
            nil,
            .Medium,
            0,
            .72 + f32((mixed >> 16) & 31) / 110,
        )
    }
}

settlement_garden_point_in_plot :: proc(site: Settlement_Site, x, z: f32, inset: f32 = 0) -> bool {
    point := [2]f32{x, z}
    corners := site.parcel.corners
    if site.kind == .Park {
        half_width := max(site.structure.width * .5 - inset, f32(0))
        half_depth := max(site.structure.depth * .5 - inset, f32(0))
        if half_width <= 0 || half_depth <= 0 do return false
        sine, cosine := math.sin(site.structure.rotation), math.cos(site.structure.rotation)
        delta := point - [2]f32{site.structure.center_x, site.structure.center_z}
        local_x := delta[0] * cosine + delta[1] * sine
        local_z := -delta[0] * sine + delta[1] * cosine
        return math.abs(local_x) <= half_width && math.abs(local_z) <= half_depth
    }

    winding := f32(0)
    for corner_index in 0 ..< len(corners) {
        a := corners[corner_index]
        b := corners[(corner_index + 1) % len(corners)]
        edge := b - a
        edge_length := linalg.length(edge)
        if edge_length <= .001 do return false
        cross := edge[0] * (point[1] - a[1]) - edge[1] * (point[0] - a[0])
        if math.abs(cross) <= inset * edge_length do return false
        if winding == 0 {
            winding = cross
        } else if cross * winding < 0 {
            return false
        }
    }
    return true
}

settlement_park_edge_segment_visible :: proc(segment, count: int) -> bool {
    if count < 8 || segment < 0 || segment >= count do return false
    // Opposing two-segment breaks keep the planted court visibly permeable
    // from either side instead of enclosing it like a private garden.
    return segment > 1 && segment < count / 2 || segment > count / 2 + 1
}

world_settlement_park_edge :: proc(editor: ^Editor, plot: Settlement_Garden_Plot) {
    if editor == nil do return
    segment_count := 12
    radius_x := max(plot.width * .46, f32(1.8))
    radius_z := max(plot.depth * .44, f32(1.6))
    stone := canvas2d.Color{177, 166, 139, 255}
    for segment in 0 ..< segment_count {
        if !settlement_park_edge_segment_visible(segment, segment_count) do continue
        angle_a := f32(segment) / f32(segment_count) * math.PI * 2
        angle_b := f32(segment + 1) / f32(segment_count) * math.PI * 2
        a := [2]f32{math.cos(angle_a) * radius_x, math.sin(angle_a) * radius_z}
        b := [2]f32{math.cos(angle_b) * radius_x, math.sin(angle_b) * radius_z}
        midpoint := (a + b) * .5
        x, z := world_rotate_xz(plot.center[0], plot.center[1], midpoint[0], midpoint[1], plot.rotation)
        base_y := terrain.sample_surface_height(&editor.project, 0, x, z)
        tangent := b - a
        yaw := plot.rotation + math.atan2(tangent[1], tangent[0])
        length := f32(math.sqrt(f64(tangent[0] * tangent[0] + tangent[1] * tangent[1])))
        world_box_rotated({x, base_y + .14, z}, {length + .08, .28, .30}, yaw, stone)
    }
}

settlement_garden_woody_species :: proc(
    region: Settlement_Region,
    style: Settlement_Garden_Style,
    plant_index: int,
    seed: u32,
) -> (
    species: plants.Species,
    scale: f32,
    woody: bool,
) {
    if style == .Courtyard {
        if region == .Aegean {
            courtyard := [4]plants.Species{.Agapanthus, .Oleander, .Myrtle, .Agapanthus}
            species = courtyard[int((seed >> 16) % u32(len(courtyard)))]
            return species, species == .Oleander ? f32(.72) : f32(.64), true
        }
        courtyard := [5]plants.Species{.Hydrangea_Bush, .Hydrangea_Tree, .Agapanthus, .Myrtle, .Hydrangea_Bush}
        species = courtyard[int((seed >> 16) % u32(len(courtyard)))]
        scale = species == .Hydrangea_Tree ? f32(.82) : species == .Hydrangea_Bush ? f32(.72) : f32(.66)
        return species, scale, true
    }
    if style == .Park && plant_index % 3 == 0 {
        if region == .Aegean {
            return plant_index % 2 == 0 ? .Olive : .Italian_Cypress, 1.32, true
        }
        return plant_index % 2 == 0 ? .Stone_Pine : .Italian_Cypress, 1.36, true
    }
    if style == .Kitchen && plant_index == 0 {
        return .Olive, .86, true
    }
    if style == .Wild || style == .Park || plant_index < 2 {
        shrubs := [3]plants.Species{.Myrtle, .Oleander, .Rosemary}
        if region == .Aegean {
            shrubs = {.Mastic, .Myrtle, .Oleander}
        }
        species = shrubs[int((seed >> 16) % u32(len(shrubs)))]
        scale = style == .Park ? 1.02 : .68
        return species, scale, true
    }
    return .Rosemary, .62, false
}

settlement_landscape_target :: proc(scale: Settlement_Scale) -> int {
    switch scale {
    case .City:
        return 18
    case .Town:
        return 14
    case .Village:
        return 10
    }
    return 0
}

settlement_landscape_species :: proc(
    region: Settlement_Region,
    plant_index: int,
    seed: u32,
) -> (
    species: plants.Species,
    scale: f32,
) {
    if plant_index % 3 == 0 {
        if region == .Aegean {
            return seed & 1 == 0 ? .Olive : .Italian_Cypress, 1.02
        }
        return seed & 1 == 0 ? .Stone_Pine : .Olive, 1.06
    }
    if region == .Aegean {
        shrubs := [3]plants.Species{.Mastic, .Myrtle, .Oleander}
        return shrubs[int((seed >> 8) % u32(len(shrubs)))], .64
    }
    shrubs := [3]plants.Species{.Myrtle, .Oleander, .Rosemary}
    return shrubs[int((seed >> 8) % u32(len(shrubs)))], .68
}

// Settlement landscape planting belongs to the public and residual fabric,
// not to garden ownership. Derive stable verge and fringe anchors from macro
// cells, then reject roads, buildings, groves, and steep or submerged ground.
// This intentionally works when garden_count is zero.
world_settlement_landscape :: proc(editor: ^Editor) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "world_settlement_landscape")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    if editor == nil || !editor.settlement_plan.valid do return
    plan := &editor.settlement_plan
    target := settlement_landscape_target(plan.request.scale)
    planted := 0
    for cell, cell_index in plan.macro_cells[:plan.macro_cell_count] {
        if planted >= target do break
        // Keep the dense historic core legible; planting belongs primarily to
        // younger edges and low-density residual cells.
        if cell.age < .34 && cell.density > .46 do continue
        for anchor_index in 0 ..< 2 {
            if planted >= target do break
            landscape_index := cell_index * 2 + anchor_index
            mixed := garden_hash(
                plan.request.seed ~
                u32(cell_index + 1) * u32(0x9e3779b9) ~
                u32(anchor_index + 1) * u32(0x85ebca6b) ~
                0x56455247,
            )
            angle := f32(mixed & 1023) / 1023 * math.PI * 2
            distance := 3.5 + f32((mixed >> 10) & 255) / 255 * 7.5
            x := cell.center[0] + math.cos(angle) * distance
            z := cell.center[1] + math.sin(angle) * distance
            species, plant_scale := settlement_landscape_species(plan.request.region, landscape_index, mixed)
            tree := landscape_index % 3 == 0
            footprint := tree ? f32(3.2) : f32(1.8)
            if !settlement_park_site_clear(&editor.project, x, z, footprint, footprint) do continue
            center_y := terrain.sample_surface_height(&editor.project, 0, x, z)
            if center_y <= editor.project.sea_level + .35 do continue
            relief := f32(0)
            for offset in ([4][2]f32{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) {
                height := terrain.sample_surface_height(
                    &editor.project,
                    0,
                    x + offset[0] * footprint,
                    z + offset[1] * footprint,
                )
                relief = max(relief, math.abs(height - center_y))
            }
            if relief > (tree ? f32(1.15) : f32(.75)) do continue
            planted += 1
            if !world_sphere_in_view(editor, {x, center_y + 3, z}, tree ? f32(7) : f32(3), 2) do continue
            _ = world_generated_plant(
                species,
                u64(mixed) ~ u64(plan.request.seed) << 32,
                {x, center_y, z},
                plant_scale * (.9 + f32((mixed >> 24) & 31) / 155),
                angle + math.PI,
                .Free_Standing,
                nil,
                .Medium,
                0,
                tree ? .86 : .74,
                true,
            )
        }
    }
}
