package main

import plants "../packages/plants"
import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import "core:math"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

SETTLEMENT_PATIO_CAPACITY :: 48

Settlement_Patio_Style :: enum u8 {
    Adriatic,
    Aegean,
}

Settlement_Patio :: struct {
    center:   [2]f32,
    base_y:   f32,
    width:    f32,
    depth:    f32,
    rotation: f32,
    seed:     u32,
    host_id:  u64,
    style:    Settlement_Patio_Style,
}

settlement_patio_route_clear :: proc(plan: ^Settlement_Plan, patio: Settlement_Patio) -> bool {
    if plan == nil do return false
    patio_radius := min(patio.width, patio.depth) * .42
    for route in plan.routes[:plan.route_count] {
        geometry := route.geometry
        for point_index in 0 ..< geometry.count - 1 {
            a, b := geometry.points[point_index], geometry.points[point_index + 1]
            segment := b - a
            length_squared := linalg.dot(segment, segment)
            if length_squared <= 1e-5 do continue
            offset := patio.center - a
            amount := clamp(linalg.dot(offset, segment) / length_squared, 0, 1)
            nearest := a + segment * amount
            distance := linalg.length(patio.center - nearest)
            if distance < route.width * .5 + route.shoulder + patio_radius + .65 do return false
        }
    }
    return true
}

settlement_patio_terrain_seat :: proc(project: ^terrain.Project, patio: ^Settlement_Patio) -> bool {
    if project == nil || patio == nil do return false
    tangent := [2]f32{math.cos(patio.rotation), math.sin(patio.rotation)}
    normal := [2]f32{-tangent[1], tangent[0]}
    half_width, half_depth := patio.width * .5, patio.depth * .5
    heights: [5]f32
    heights[0] = terrain.sample_surface_height(project, 0, patio.center[0], patio.center[1])
    corners := [4][2]f32 {
        patio.center + tangent * half_width + normal * half_depth,
        patio.center + tangent * half_width - normal * half_depth,
        patio.center - tangent * half_width + normal * half_depth,
        patio.center - tangent * half_width - normal * half_depth,
    }
    minimum, maximum, total := heights[0], heights[0], heights[0]
    for corner, index in corners {
        height := terrain.sample_surface_height(project, 0, corner[0], corner[1])
        heights[index + 1] = height
        minimum, maximum = min(minimum, height), max(maximum, height)
        total += height
    }
    if minimum <= project.sea_level + .35 || maximum - minimum > .72 do return false
    // Seat the finished paving above the highest footprint sample. A deep
    // rendered skirt drops from this elevation to conceal the lower corners;
    // using the mean allowed uphill terrain to poke through the thin slab.
    _ = total
    patio.base_y = maximum + .02
    return true
}

settlement_patio_structures_clear :: proc(editor: ^Editor, patio: Settlement_Patio) -> bool {
    if editor == nil do return false
    for structure in editor.project.structures[:editor.project.structure_count] {
        if structure.id == patio.host_id do continue
        if structure.kind != .Architecture && structure.kind != .Foliage do continue
        if !settlement_oriented_rectangles_clear(
            patio.center[0],
            patio.center[1],
            patio.width,
            patio.depth,
            patio.rotation,
            structure.center_x,
            structure.center_z,
            structure.width,
            structure.depth,
            structure.rotation,
            .75,
        ) {
            return false
        }
    }
    for existing in editor.settlement_plan.patios[:editor.settlement_plan.patio_count] {
        if !settlement_oriented_rectangles_clear(
            patio.center[0],
            patio.center[1],
            patio.width,
            patio.depth,
            patio.rotation,
            existing.center[0],
            existing.center[1],
            existing.width,
            existing.depth,
            existing.rotation,
            2,
        ) {
            return false
        }
    }
    return true
}

settlement_patios_contain_point :: proc(editor: ^Editor, x, z: f32, padding: f32 = 0) -> bool {
    if editor == nil do return false
    for patio in editor.settlement_plan.patios[:editor.settlement_plan.patio_count] {
        cosine, sine := math.cos(patio.rotation), math.sin(patio.rotation)
        dx, dz := x - patio.center[0], z - patio.center[1]
        local_x := dx * cosine + dz * sine
        local_z := -dx * sine + dz * cosine
        if math.abs(local_x) <= patio.width * .5 + padding && math.abs(local_z) <= patio.depth * .5 + padding {
            return true
        }
    }
    return false
}

settlement_patio_candidate :: proc(
    site: Settlement_Site,
    direction_index: int,
    width, depth: f32,
    seed: u32,
    style: Settlement_Patio_Style,
) -> Settlement_Patio {
    structure := site.structure
    tangent := [2]f32{math.cos(structure.rotation), math.sin(structure.rotation)}
    normal := [2]f32{-tangent[1], tangent[0]}
    direction := [2]f32{}
    distance := f32(0)
    patio_width, patio_depth := width, depth
    if direction_index < 2 {
        sign := direction_index == 0 ? f32(-1) : f32(1)
        direction = normal * sign
        distance = structure.depth * .5 + depth * .5 + 1.15
    } else {
        sign := direction_index == 2 ? f32(-1) : f32(1)
        direction = tangent * sign
        distance = structure.width * .5 + depth * .5 + 1.15
        patio_width, patio_depth = depth, width
    }
    return {
        center = {structure.center_x, structure.center_z} + direction * distance,
        width = patio_width,
        depth = patio_depth,
        rotation = structure.rotation,
        seed = seed,
        host_id = structure.id,
        style = style,
    }
}

settlement_patios_generate :: proc(editor: ^Editor) {
    if editor == nil || editor.settlement_plan.patio_count >= SETTLEMENT_PATIO_CAPACITY do return
    world_renderer.retained_patio_dirty = true
    plan := &editor.settlement_plan
    target := 2
    switch plan.request.scale {
    case .City:
        target = 7
    case .Town:
        target = 4
    case .Village:
        target = 2
    }
    start_count := editor.settlement_plan.patio_count
    for pass in 0 ..< 3 {
        for site, site_index in plan.sites[:plan.site_count] {
            if editor.settlement_plan.patio_count - start_count >= target ||
               editor.settlement_plan.patio_count >= SETTLEMENT_PATIO_CAPACITY {
                return
            }
            if !site.accepted || site.kind != .Ordinary || site.attached do continue
            eligible := false
            if pass == 0 {
                eligible = site.purpose == .Inn_Shop
            } else if pass == 1 {
                eligible = site.purpose == .Workshop
            } else {
                hash := patio_hash(plan.request.seed ~ site.structure.seed ~ u32(site_index))
                eligible = site.purpose == .Dwelling && hash % 5 == 0
            }
            if !eligible do continue

            seed := patio_hash(plan.request.seed ~ site.structure.seed ~ 0x70617469)
            scale := plan.request.scale == .Village ? f32(.84) : f32(1)
            width := (6.8 + f32(seed & 3) * .55) * scale
            depth := (5.2 + f32((seed >> 3) & 3) * .45) * scale
            style := plan.request.region == .Aegean ? Settlement_Patio_Style.Aegean : .Adriatic
            first_direction := int((seed >> 8) & 3)
            for direction_attempt in 0 ..< 4 {
                direction := (first_direction + direction_attempt) % 4
                patio := settlement_patio_candidate(site, direction, width, depth, seed, style)
                if !settlement_patio_terrain_seat(&editor.project, &patio) ||
                   !settlement_patio_route_clear(plan, patio) ||
                   !settlement_patio_structures_clear(editor, patio) {
                    continue
                }
                editor.settlement_plan.patios[editor.settlement_plan.patio_count] = patio
                editor.settlement_plan.patio_count += 1
                break
            }
        }
    }
}

settlement_garden_plot_clear :: proc(editor: ^Editor, plot: Settlement_Garden_Plot) -> bool {
    if editor == nil || plot.site_index < 0 || plot.site_index >= editor.settlement_plan.site_count do return false
    site := editor.settlement_plan.sites[plot.site_index]
    tangent := [2]f32{math.cos(plot.rotation), math.sin(plot.rotation)}
    normal := [2]f32{-tangent[1], tangent[0]}
    half_width, half_depth := plot.width * .5, plot.depth * .5
    corners := [4][2]f32 {
        plot.center + tangent * half_width + normal * half_depth,
        plot.center + tangent * half_width - normal * half_depth,
        plot.center - tangent * half_width + normal * half_depth,
        plot.center - tangent * half_width - normal * half_depth,
    }
    for corner in corners {
        if !settlement_garden_point_in_plot(site, corner[0], corner[1], .2) do return false
    }
    footprint := Settlement_Patio {
        center   = plot.center,
        width    = plot.width,
        depth    = plot.depth,
        rotation = plot.rotation,
        host_id  = site.structure.id,
    }
    if !settlement_patio_route_clear(&editor.settlement_plan, footprint) ||
       !settlement_patio_structures_clear(editor, footprint) {
        return false
    }
    for existing in editor.settlement_plan.gardens[:editor.settlement_plan.garden_count] {
        if !settlement_oriented_rectangles_clear(
            plot.center[0],
            plot.center[1],
            plot.width,
            plot.depth,
            plot.rotation,
            existing.center[0],
            existing.center[1],
            existing.width,
            existing.depth,
            existing.rotation,
            1.5,
        ) {
            return false
        }
    }
    return true
}

settlement_gardens_generate :: proc(editor: ^Editor) {
    if editor == nil do return
    plan := &editor.settlement_plan
    plan.garden_count = 0
    target := plan.request.scale == .City ? 14 : (plan.request.scale == .Town ? 8 : 4)
    for site, site_index in plan.sites[:plan.site_count] {
        if plan.garden_count >= target || plan.garden_count >= SETTLEMENT_GARDEN_CAPACITY do break
        if !site.accepted || (site.kind != .Ordinary && site.kind != .Park) do continue
        seed := garden_hash(plan.request.seed ~ site.structure.seed ~ u32(site_index * 0x9e37))
        if site.kind == .Park {
            plan.gardens[plan.garden_count] = {
                center     = {site.structure.center_x, site.structure.center_z},
                width      = site.structure.width,
                depth      = site.structure.depth,
                rotation   = site.structure.rotation,
                seed       = seed,
                site_index = site_index,
                style      = .Park,
            }
            plan.garden_count += 1
            continue
        }
        if site.attached || (site.purpose != .Farmstead && site.density > .48) do continue
        if site.purpose != .Farmstead && seed & 3 == 0 do continue
        width := clamp(site.structure.width * .62, f32(4.5), f32(9))
        depth := clamp(site.structure.depth * .46, f32(3.8), f32(7))
        tangent := [2]f32{math.cos(site.structure.rotation), math.sin(site.structure.rotation)}
        normal := [2]f32{-tangent[1], tangent[0]}
        // The architecture frontage faces local +Z; household growing space
        // occupies the quieter rear residue of the parcel.
        center :=
            [2]f32{site.structure.center_x, site.structure.center_z} -
            normal * (site.structure.depth * .5 + depth * .5 + .8)
        style := Settlement_Garden_Style.Courtyard
        if site.purpose == .Farmstead {
            style = .Kitchen
        } else if site.tissue == .Hillside_Accretion || site.tissue == .Contour_Terrace || site.density < .22 {
            style = .Wild
        }
        plot := Settlement_Garden_Plot {
            center     = center,
            width      = width,
            depth      = depth,
            rotation   = site.structure.rotation,
            seed       = seed,
            site_index = site_index,
            style      = style,
        }
        if !settlement_garden_plot_clear(editor, plot) do continue
        plan.gardens[plan.garden_count] = plot
        plan.garden_count += 1
    }
}

settlement_patio_point :: proc(patio: Settlement_Patio, x, y, z: f32) -> third_person.Vec3 {
    cosine, sine := math.cos(patio.rotation), math.sin(patio.rotation)
    return {patio.center[0] + x * cosine - z * sine, patio.base_y + y, patio.center[1] + x * sine + z * cosine}
}

world_settlement_patio :: proc(patio: Settlement_Patio, include_plants := true) {
    foundation := patio.style == .Aegean ? canvas2d.Color{190, 207, 203, 255} : canvas2d.Color{198, 165, 123, 255}
    accent := patio.style == .Aegean ? PATIO_BLUE : PATIO_RED
    secondary := patio.style == .Aegean ? PATIO_CREAM : canvas2d.Color{240, 196, 124, 255}
    center := third_person.Vec3{patio.center[0], patio.base_y, patio.center[1]}
    world_box_rotated(
        {center.x, center.y - .16, center.z},
        {patio.width, .36, patio.depth},
        patio.rotation,
        foundation,
    )
    furniture_center := settlement_patio_point(patio, 0, .04, 0)
    patio_round_table(furniture_center, secondary)
    patio_umbrella(furniture_center, min(patio.width, patio.depth) * .38, accent, PATIO_CREAM)
    chair_count := 2 + int((patio.seed >> 12) & 1) * 2
    chair_radius := min(patio.width, patio.depth) * .36
    rotation_offset := f32((patio.seed >> 16) & 255) / 255 * math.PI * 2
    for chair_index in 0 ..< chair_count {
        angle := rotation_offset + f32(chair_index) * math.PI * 2 / f32(chair_count)
        local_x, local_z := math.cos(angle) * chair_radius, math.sin(angle) * chair_radius
        chair_center := settlement_patio_point(patio, local_x, .04, local_z)
        patio_chair(chair_center, patio.rotation + angle - math.PI / 2, accent)
    }
    if patio.seed & 2 != 0 {
        bench_center := settlement_patio_point(patio, 0, .04, patio.depth * .5 - .58)
        patio_bench(bench_center, patio.rotation + math.PI)
    }
    planter_x := patio.width * .5 - .55
    planter_z := patio.depth * .5 - .55
    planter_a := settlement_patio_point(patio, -planter_x, .04, planter_z)
    planter_b := settlement_patio_point(patio, planter_x, .04, -planter_z)
    patio_planter(planter_a, false)
    patio_planter(planter_b, false)
    if !include_plants do return
    world_settlement_patio_plants(patio, planter_a, planter_b)
}

world_settlement_patio_plants :: proc(
    patio: Settlement_Patio,
    planter_a: third_person.Vec3,
    planter_b: third_person.Vec3,
) {
    patio_species := patio.style == .Aegean ? plants.Species.Pelargonium : plants.Species.Rosemary
    _ = world_generated_plant(
        patio_species,
        u64(patio.seed) ~ 0x706174696f5f706c,
        {planter_a.x, planter_a.y + .84, planter_a.z},
        patio.style == .Aegean ? .72 : .88,
        patio.rotation,
    )
    _ = world_generated_plant(
        patio.seed & 4 != 0 ? plants.Species.Lavender : patio_species,
        u64(patio.seed) ~ 0x706174696f5f7072,
        {planter_b.x, planter_b.y + .84, planter_b.z},
        patio.style == .Aegean ? .72 : .88,
        patio.rotation + math.PI,
    )
}

world_settlement_patios :: proc(editor: ^Editor) {
    if editor == nil do return
    for patio in editor.settlement_plan.patios[:editor.settlement_plan.patio_count] {
        radius := f32(math.sqrt(f64(patio.width * patio.width + patio.depth * patio.depth + 36))) * .5
        if !world_sphere_in_view(editor, {patio.center[0], patio.base_y + 1.5, patio.center[1]}, radius, 2) {
            continue
        }
        planter_x := patio.width * .5 - .55
        planter_z := patio.depth * .5 - .55
        planter_a := settlement_patio_point(patio, -planter_x, .04, planter_z)
        planter_b := settlement_patio_point(patio, planter_x, .04, -planter_z)
        world_settlement_patio_plants(patio, planter_a, planter_b)
    }
}

world_retained_patio_rebuild :: proc(editor: ^Editor) {
    if editor == nil || !world_renderer.retained_patio_dirty || world_renderer.retained_patio_rebuilding do return
    world_renderer.retained_patio_rebuilding = true
    defer world_renderer.retained_patio_rebuilding = false
    clear(&world_renderer.vertices)
    clear(&world_renderer.retained_patio_vertices)
    clear(&world_renderer.retained_patio_indices)
    for patio in editor.settlement_plan.patios[:editor.settlement_plan.patio_count] {
        world_settlement_patio(patio, false)
    }
    world_farm_compounds(editor)
    world_settlement_cemetery(editor, true, false)
    world_authored_farmland(editor)
    world_authored_wrecks(editor)
    world_settlement_inhabitants(editor, false, true)
    world_infrastructure(editor)
    source_count := len(world_renderer.vertices)
    if source_count > 0 {
        resize(&world_renderer.retained_patio_vertices, source_count)
        resize(&world_renderer.retained_patio_indices, source_count)
        optimized_count := adriatic_optimize_unindexed_mesh(
            raw_data(world_renderer.retained_patio_vertices[:]),
            raw_data(world_renderer.retained_patio_indices[:]),
            raw_data(world_renderer.vertices[:]),
            u32(source_count),
            u32(size_of(World_Vertex)),
        )
        if optimized_count > 0 {
            resize(&world_renderer.retained_patio_vertices, int(optimized_count))
            resize(&world_renderer.retained_patio_indices, int(optimized_count))
        } else {
            clear(&world_renderer.retained_patio_vertices)
            clear(&world_renderer.retained_patio_indices)
        }
    }
    clear(&world_renderer.vertices)
    world_renderer.retained_patio_revision += 1
    if world_renderer.retained_patio_revision == 0 {
        world_renderer.retained_patio_revision = 1
        world_renderer.retained_patio_uploaded_revision = {}
    }
    world_renderer.retained_patio_dirty = false
    world_renderer.retained_static_dirty = true
}
