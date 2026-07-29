package main

import architecture "../packages/architecture"
import markov "../packages/markov"
import roads "../packages/roads"
import story "../packages/story"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import "core:strconv"
import rl "zelda_engine:canvas2d"

MARKOV_TOWN_GRID :: 23
MARKOV_TOWN_CELL :: f32(20)

Settlement_Lab_Fixture :: enum {
    Default,
    Slope,
    Waterfront,
}

settlement_lab_target_parse :: proc(
    target: string,
) -> (
    fixture: Settlement_Lab_Fixture,
    vertical_map: bool,
    seed_target: string,
) {
    seed_target = target
    SLOPE_PREFIX :: "slope-"
    WATERFRONT_PREFIX :: "waterfront-"
    MAP_PREFIX :: "map-"
    if len(seed_target) > len(SLOPE_PREFIX) && seed_target[:len(SLOPE_PREFIX)] == SLOPE_PREFIX {
        fixture = .Slope
        seed_target = seed_target[len(SLOPE_PREFIX):]
    } else if len(seed_target) > len(WATERFRONT_PREFIX) && seed_target[:len(WATERFRONT_PREFIX)] == WATERFRONT_PREFIX {
        fixture = .Waterfront
        seed_target = seed_target[len(WATERFRONT_PREFIX):]
    }
    if len(seed_target) > len(MAP_PREFIX) && seed_target[:len(MAP_PREFIX)] == MAP_PREFIX {
        vertical_map = true
        seed_target = seed_target[len(MAP_PREFIX):]
    }
    return
}

Markov_Town_Cell :: enum u8 {
    Empty,
    Town,
    Landmark,
    Foliage,
}

markov_town_model :: proc(profile: Settlement_Profile) -> markov.Proc_Node {
    empty := int(Markov_Town_Cell.Empty)
    town := int(Markov_Town_Cell.Town)
    landmark := int(Markov_Town_Cell.Landmark)
    foliage := int(Markov_Town_Cell.Foliage)
    return markov.node(
        markov.Proc_Tag.sequence,
        []markov.Proc_Attr{markov.kattr(.values, markov.values_count(4)), markov.kattr(.origin, true)},
        []markov.Proc_Node {
            markov.node(
                markov.Proc_Tag.one,
                []markov.Proc_Attr {
                    markov.kattr(
                        .in_,
                        markov.match_layer(
                            markov.match_row(markov.one_of(markov.sym(town)), markov.one_of(markov.sym(empty))),
                        ),
                    ),
                    markov.kattr(.out, markov.write_layer(markov.write_row(markov.keep(), markov.sym(town)))),
                    markov.kattr(.steps, profile.neighborhood_steps),
                },
            ),
            markov.node(
                markov.Proc_Tag.one,
                []markov.Proc_Attr {
                    markov.kattr(.in_, markov.match_layer(markov.match_row(markov.one_of(markov.sym(town))))),
                    markov.kattr(.out, markov.write_layer(markov.write_row(markov.sym(landmark)))),
                    markov.kattr(.steps, profile.landmark_steps),
                },
            ),
            markov.node(
                markov.Proc_Tag.one,
                []markov.Proc_Attr {
                    markov.kattr(
                        .in_,
                        markov.match_layer(
                            markov.match_row(markov.one_of(markov.sym(town)), markov.one_of(markov.sym(empty))),
                        ),
                    ),
                    markov.kattr(.out, markov.write_layer(markov.write_row(markov.keep(), markov.sym(foliage)))),
                    markov.kattr(.steps, profile.foliage_steps),
                },
            ),
        },
    )
}

markov_town_height :: proc(project: ^terrain.Project, x, z: f32) -> f32 {
    return terrain.sample_height(project, 0, x, z)
}

markov_town_probe :: proc(frame: ^markov.Frame, x, z: int) -> bool {
    if frame == nil do return false
    cell := Markov_Town_Cell(frame.state[z * MARKOV_TOWN_GRID + x])
    return cell == .Town || cell == .Landmark
}

markov_town_add_road :: proc(
    project: ^terrain.Project,
    ax, az, bx, bz, width, shoulder: f32,
    pavement: roads.Pavement,
    bend: f32 = 0,
) {
    graph := &project.road_graph
    if graph.node_count + 2 > roads.MAX_NODES || graph.edge_count >= roads.MAX_EDGES do return
    fitted_ax, fitted_az := settlement_fit_landscape_point(project, ax, az, 28)
    fitted_bx, fitted_bz := settlement_fit_landscape_point(project, bx, bz, 28)
    a := roads.Vec3{fitted_ax, markov_town_height(project, fitted_ax, fitted_az), fitted_az}
    b := roads.Vec3{fitted_bx, markov_town_height(project, fitted_bx, fitted_bz), fitted_bz}
    from := roads.add_node(graph, a, width * .62)
    to := roads.add_node(graph, b, width * .62)
    if from < 0 || to < 0 do return
    dx, dz := fitted_bx - fitted_ax, fitted_bz - fitted_az
    length := f32(math.sqrt(f64(dx * dx + dz * dz)))
    if length <= .001 do return
    nx, nz := -dz / length, dx / length
    c0 := roads.Vec3{fitted_ax + dx * .34 + nx * bend, 0, fitted_az + dz * .34 + nz * bend}
    c1 := roads.Vec3{fitted_ax + dx * .66 + nx * bend, 0, fitted_az + dz * .66 + nz * bend}
    c0.x, c0.z = settlement_fit_landscape_point(project, c0.x, c0.z, 22)
    c1.x, c1.z = settlement_fit_landscape_point(project, c1.x, c1.z, 22)
    c0.y = markov_town_height(project, c0.x, c0.z)
    c1.y = markov_town_height(project, c1.x, c1.z)
    _ = roads.add_edge(graph, from, to, c0, c1, width, shoulder, pavement)
}

markov_town_add_landmark :: proc(project: ^terrain.Project, x, z, width, depth, height, rotation: f32, seed: u32) {
    structure := terrain.structure_make(x, z, width, depth, 0, height)
    structure.kind = .Architecture
    structure.width = width
    structure.depth = depth
    structure.height = height
    structure.rotation = rotation
    structure.seed = seed
    structure.color = architecture.architecture_color(seed, height > 58)
    _ = terrain.add_structure(project, structure)
}

settlement_park_site_clear :: proc(project: ^terrain.Project, x, z, width, depth: f32) -> bool {
    if project == nil do return false
    radius := f32(math.sqrt(f64(width * width + depth * depth))) * .5
    for structure in project.structures[:project.structure_count] {
        if structure.kind != .Architecture && structure.kind != .Foliage do continue
        other_radius := f32(math.sqrt(f64(structure.width * structure.width + structure.depth * structure.depth))) * .5
        dx, dz := structure.center_x - x, structure.center_z - z
        clearance := structure.kind == .Architecture ? f32(5) : f32(2)
        if dx * dx + dz * dz < (radius + other_radius + clearance) * (radius + other_radius + clearance) {
            return false
        }
    }
    return true
}

markov_town_add_grove :: proc(project: ^terrain.Project, x, z, width, depth, height: f32, seed: u32) {
    base_y := terrain.sample_height(project, 0, x, z)
    structure := terrain.structure_make(x, z, width, depth, base_y, height)
    structure.kind = .Foliage
    structure.width = width
    structure.depth = depth
    structure.seed = seed
    structure.rotation = f32(seed & 255) / 255 * math.PI
    _ = terrain.add_structure(project, structure)
}

markov_town_reseat_park_groves :: proc(plan: ^Settlement_Plan, project: ^terrain.Project) {
    if plan == nil || project == nil do return
    for &site in plan.sites[:plan.site_count] {
        if !site.accepted || site.kind != .Park do continue
        base_y := terrain.sample_height(project, 0, site.structure.center_x, site.structure.center_z)
        site.structure.base_y = base_y
        for &structure in project.structures[:project.structure_count] {
            if structure.id != site.structure.id do continue
            structure.base_y = base_y
            break
        }
    }
}

settlement_camera_site_clear :: proc(project: ^terrain.Project, x, z, clearance: f32) -> bool {
    if project == nil do return false
    for structure in project.structures[:project.structure_count] {
        if structure.kind != .Architecture do continue
        dx, dz := structure.center_x - x, structure.center_z - z
        radius :=
            f32(math.sqrt(f64(structure.width * structure.width + structure.depth * structure.depth))) * .5 + clearance
        if dx * dx + dz * dz < radius * radius do return false
    }
    return true
}

settlement_map_frame :: proc(
    project: ^terrain.Project,
    fallback_center: [2]f32,
    fallback_radius: f32,
) -> (
    focus: [2]f32,
    height: f32,
) {
    focus = fallback_center
    height = clamp(fallback_radius * 1.18, f32(125), f32(320))
    if project == nil do return
    minimum_x, minimum_z := f32(1e30), f32(1e30)
    maximum_x, maximum_z := f32(-1e30), f32(-1e30)
    count := 0
    for structure in project.structures[:project.structure_count] {
        if structure.kind != .Architecture do continue
        extent := f32(math.sqrt(f64(structure.width * structure.width + structure.depth * structure.depth))) * .5
        minimum_x = min(minimum_x, structure.center_x - extent)
        maximum_x = max(maximum_x, structure.center_x + extent)
        minimum_z = min(minimum_z, structure.center_z - extent)
        maximum_z = max(maximum_z, structure.center_z + extent)
        count += 1
    }
    if count == 0 do return
    focus = {(minimum_x + maximum_x) * .5, (minimum_z + maximum_z) * .5}
    span := max(maximum_x - minimum_x, maximum_z - minimum_z)
    height = clamp(max(span * 1.05, fallback_radius * .75), f32(95), f32(320))
    return
}

markov_city_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    return settlement_lab_configure(editor, target, SETTLEMENT_CITY, .Adriatic)
}

markov_town_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    return settlement_lab_configure(editor, target, SETTLEMENT_TOWN, .Adriatic)
}

markov_village_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    return settlement_lab_configure(editor, target, SETTLEMENT_VILLAGE, .Adriatic)
}

aegean_city_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    return settlement_lab_configure(editor, target, SETTLEMENT_CITY, .Aegean)
}

aegean_town_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    return settlement_lab_configure(editor, target, SETTLEMENT_TOWN, .Aegean)
}

aegean_village_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    return settlement_lab_configure(editor, target, SETTLEMENT_VILLAGE, .Aegean)
}

settlement_lab_configure :: proc(
    editor: ^Editor,
    target: string,
    profile: Settlement_Profile,
    region: Settlement_Region,
) -> bool {
    if editor == nil do return false
    fixture, vertical_map, seed_target := settlement_lab_target_parse(target)
    editor.settlement_vertical_map = vertical_map
    seed := 0x4d4a54
    if parsed, ok := strconv.parse_int(seed_target); ok && parsed >= 0 do seed = int(parsed)

    model := markov_town_model(profile)
    ip, loaded := markov.load_model_proc(model, {MARKOV_TOWN_GRID, MARKOV_TOWN_GRID, 1})
    if !loaded do return false
    defer markov.interpreter_destroy(ip)
    frames := markov.run(ip, seed, 0, false, context.temp_allocator)
    if len(frames) == 0 do return false
    frame := frames[len(frames) - 1]

    density_model := settlement_density_model(profile)
    density_ip, density_loaded := markov.load_model_proc(density_model, {MARKOV_TOWN_GRID, MARKOV_TOWN_GRID, 1})
    if !density_loaded do return false
    defer markov.interpreter_destroy(density_ip)
    density_frames := markov.run(density_ip, seed ~ 0x6d2b79f5, 0, false, context.temp_allocator)
    if len(density_frames) == 0 do return false
    density_frame := density_frames[len(density_frames) - 1]

    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    town_z := center + 105
    if fixture == .Waterfront do town_z = center + 180
    if fixture == .Slope {
        // Place the settlement on the shoulder of a deterministic broad ridge.
        // Two feathered raises make the fixture steep enough to exercise route
        // grade and contour logic without producing an isolated volcano.
        terrain.apply_stroke_with_hardness(&editor.project, .Raise, center, town_z - 115, 225, 24, 1, .18)
        terrain.apply_stroke_with_hardness(&editor.project, .Raise, center + 55, town_z - 95, 155, 13, 1, .24)
    }
    scale := profile.world_cell / SETTLEMENT_CITY.world_cell
    radius := 245 * scale
    editor.settlement_plan = {}
    editor.settlement_plan.request = {
        region = region,
        scale  = profile.scale,
        seed   = u32(seed),
        center = {center, town_z},
        radius = radius,
    }
    settlement_rng := settlement_rng_new(u32(seed))
    bounds := architecture.City_Bounds{center - radius, town_z - radius, center + radius, town_z + radius, true}
    district_target := 3
    switch profile.scale {
    case .City:
        district_target = 10
    case .Town:
        district_target = 6
    case .Village:
        district_target = 3
    }
    CELL_COUNT :: MARKOV_TOWN_GRID * MARKOV_TOWN_GRID
    candidate, connected: [CELL_COUNT]bool
    cell_density, cell_suitability: [CELL_COUNT]f32
    closest_cell := -1
    closest_distance := f32(1e9)
    for gz in 2 ..< MARKOV_TOWN_GRID - 2 {
        for gx in 2 ..< MARKOV_TOWN_GRID - 2 {
            x := center + f32(gx - MARKOV_TOWN_GRID / 2) * profile.world_cell
            z := town_z + f32(gz - MARKOV_TOWN_GRID / 2) * profile.world_cell
            suitability := settlement_site_suitability(&editor.project, x, z, profile)
            if suitability <= .08 do continue
            dx, dz := x - center, z - town_z
            normalized_distance := f32(math.sqrt(f64(dx * dx + dz * dz))) / max(radius, profile.world_cell)
            if normalized_distance > 1 do continue
            markov_density := settlement_density_smoothed(&density_frame, MARKOV_TOWN_GRID, gx, gz, profile)
            radial_density :=
                profile.density_ceiling -
                (profile.density_ceiling - profile.density_floor) * clamp(normalized_distance, 0, 1)
            density := (radial_density * .82 + max(markov_density, profile.density_floor) * .18) * suitability
            linear := gz * MARKOV_TOWN_GRID + gx
            candidate[linear] = true
            cell_density[linear] = density
            cell_suitability[linear] = suitability
            distance := dx * dx + dz * dz
            if distance < closest_distance {
                closest_cell = linear
                closest_distance = distance
            }
        }
    }
    if closest_cell < 0 do return false

    // Grow a single terrain-constrained frontier from the historic core.
    // Markov output is deliberately not used as the macro footprint: a local
    // rewrite field may form a thin walk, while a settlement envelope must
    // remain contiguous and spatially legible.
    connected[closest_cell] = true
    growth_count := 1
    growth_target := profile.neighborhood_steps
    switch profile.scale {
    case .City:
        growth_target = 138
    case .Town:
        growth_target = 60
    case .Village:
        growth_target = 28
    }
    growth_target = min(growth_target, CELL_COUNT)
    for growth_count < growth_target {
        best_cell, best_score := -1, f32(-1e9)
        for linear in 0 ..< CELL_COUNT {
            if !candidate[linear] || connected[linear] do continue
            gx, gz := linear % MARKOV_TOWN_GRID, linear / MARKOV_TOWN_GRID
            touches_growth := false
            for dz in -1 ..= 1 {
                for dx in -1 ..= 1 {
                    if dx == 0 && dz == 0 do continue
                    nx, nz := gx + dx, gz + dz
                    if nx < 0 || nz < 0 || nx >= MARKOV_TOWN_GRID || nz >= MARKOV_TOWN_GRID do continue
                    if connected[nz * MARKOV_TOWN_GRID + nx] {
                        touches_growth = true
                        break
                    }
                }
                if touches_growth do break
            }
            if !touches_growth do continue
            x := center + f32(gx - MARKOV_TOWN_GRID / 2) * profile.world_cell
            z := town_z + f32(gz - MARKOV_TOWN_GRID / 2) * profile.world_cell
            dx, dz := x - center, z - town_z
            normalized_distance := f32(math.sqrt(f64(dx * dx + dz * dz))) / max(radius, profile.world_cell)
            hash := u32(linear) * u32(0x9e3779b9) ~ u32(seed) * u32(0x85ebca6b)
            noise := f32(hash & 0xffff) / f32(0xffff)
            score := cell_suitability[linear] * 1.25 - normalized_distance * .72 + (noise - .5) * .34
            if score > best_score {
                best_cell, best_score = linear, score
            }
        }
        if best_cell < 0 do break
        connected[best_cell] = true
        growth_count += 1
    }
    core_gx, core_gz := closest_cell % MARKOV_TOWN_GRID, closest_cell / MARKOV_TOWN_GRID
    core_x := center + f32(core_gx - MARKOV_TOWN_GRID / 2) * profile.world_cell
    core_z := town_z + f32(core_gz - MARKOV_TOWN_GRID / 2) * profile.world_cell
    envelope_radius := f32(0)
    for linear in 0 ..< CELL_COUNT {
        if !connected[linear] do continue
        gx, gz := linear % MARKOV_TOWN_GRID, linear / MARKOV_TOWN_GRID
        x := center + f32(gx - MARKOV_TOWN_GRID / 2) * profile.world_cell
        z := town_z + f32(gz - MARKOV_TOWN_GRID / 2) * profile.world_cell
        dx, dz := x - core_x, z - core_z
        envelope_radius = max(envelope_radius, f32(math.sqrt(f64(dx * dx + dz * dz))))
    }
    radius = max(envelope_radius + profile.world_cell * .75, profile.world_cell * 3)
    editor.settlement_plan.request.center = {core_x, core_z}
    editor.settlement_plan.request.radius = radius
    bounds = {core_x - radius, core_z - radius, core_x + radius, core_z + radius, true}

    // Farthest-point seeds divide that connected envelope into adjacent
    // morphological patches. This replaces angular sector averages, which
    // could place a district center across empty terrain from its own cells.
    seed_cells: [14]int
    seed_count := 1
    seed_cells[0] = closest_cell
    for seed_count < district_target {
        best_cell, best_score := -1, f32(-1)
        for linear in 0 ..< CELL_COUNT {
            if !connected[linear] do continue
            gx, gz := linear % MARKOV_TOWN_GRID, linear / MARKOV_TOWN_GRID
            minimum_seed_distance := f32(1e9)
            for seed_index in 0 ..< seed_count {
                seed_linear := seed_cells[seed_index]
                sx, sz := seed_linear % MARKOV_TOWN_GRID, seed_linear / MARKOV_TOWN_GRID
                dx, dz := f32(gx - sx), f32(gz - sz)
                minimum_seed_distance = min(minimum_seed_distance, dx * dx + dz * dz)
            }
            score := minimum_seed_distance * (.55 + cell_suitability[linear] * .45)
            if score > best_score {
                best_cell, best_score = linear, score
            }
        }
        if best_cell < 0 || best_score < 2.25 do break
        seed_cells[seed_count] = best_cell
        seed_count += 1
    }

    cell_district: [CELL_COUNT]int
    district_x, district_z: [14]f32
    district_density, district_suitability, district_age, district_radius: [14]f32
    district_samples: [14]int
    for linear in 0 ..< CELL_COUNT {
        if !connected[linear] do continue
        gx, gz := linear % MARKOV_TOWN_GRID, linear / MARKOV_TOWN_GRID
        district, nearest_distance := 0, f32(1e9)
        for seed_index in 0 ..< seed_count {
            seed_linear := seed_cells[seed_index]
            sx, sz := seed_linear % MARKOV_TOWN_GRID, seed_linear / MARKOV_TOWN_GRID
            dx, dz := f32(gx - sx), f32(gz - sz)
            distance := dx * dx + dz * dz
            if distance < nearest_distance {
                district, nearest_distance = seed_index, distance
            }
        }
        cell_district[linear] = district
        x := center + f32(gx - MARKOV_TOWN_GRID / 2) * profile.world_cell
        z := town_z + f32(gz - MARKOV_TOWN_GRID / 2) * profile.world_cell
        core_dx, core_dz := f32(gx - core_gx), f32(gz - core_gz)
        age := clamp(
            f32(math.sqrt(f64(core_dx * core_dx + core_dz * core_dz))) * profile.world_cell / max(radius, f32(1)),
            0,
            1,
        )
        density := settlement_density_with_age(cell_density[linear], age, profile)
        district_x[district] += x
        district_z[district] += z
        district_density[district] += density
        district_suitability[district] += cell_suitability[linear]
        district_age[district] += age
        district_radius[district] = max(
            district_radius[district],
            f32(math.sqrt(f64(nearest_distance))) * profile.world_cell + profile.world_cell * .75,
        )
        district_samples[district] += 1
        _ = architecture.city_density_stamp(
            &editor.project.city_density,
            x,
            z,
            profile.world_cell * 1.45,
            density,
            .68,
        )
    }
    for district in 0 ..< seed_count {
        samples := district_samples[district]
        if samples == 0 do continue
        inverse := 1 / f32(samples)
        age := district_age[district] * inverse
        tissue :=
            age > .68 ? Settlement_Tissue.Later_Extension : settlement_tissue_pick(region, settlement_rng_unit(&settlement_rng))
        settlement_plan_add_neighborhood(
            &editor.settlement_plan,
            {district_x[district] * inverse, district_z[district] * inverse},
            max(profile.world_cell * 1.2, district_radius[district]),
            district_density[district] * inverse,
            district_suitability[district] * inverse,
            age,
            tissue,
            &settlement_rng,
        )
    }
    for linear in 0 ..< CELL_COUNT {
        if !connected[linear] || editor.settlement_plan.macro_cell_count >= len(editor.settlement_plan.macro_cells) {
            continue
        }
        gx, gz := linear % MARKOV_TOWN_GRID, linear / MARKOV_TOWN_GRID
        x := center + f32(gx - MARKOV_TOWN_GRID / 2) * profile.world_cell
        z := town_z + f32(gz - MARKOV_TOWN_GRID / 2) * profile.world_cell
        district := cell_district[linear]
        core_dx, core_dz := f32(gx - core_gx), f32(gz - core_gz)
        cell_age := clamp(
            f32(math.sqrt(f64(core_dx * core_dx + core_dz * core_dz))) * profile.world_cell / max(radius, f32(1)),
            0,
            1,
        )
        // Markov cells describe land-use membership, not surveyed parcel
        // coordinates. A small deterministic warp prevents the underlying
        // raster from appearing as parallel rows of buildings while keeping
        // the historic core tighter than later extensions.
        cell_hash := u32(linear) * u32(0x9e3779b9) ~ u32(seed) * u32(0x85ebca6b)
        tissue := editor.settlement_plan.neighborhoods[district].tissue
        warp_fraction := f32(.16)
        switch tissue {
        case .Later_Extension, .Dalmatian_Planned:
            warp_fraction = .09
        case .Venetian_Mercantile, .Harbor:
            warp_fraction = tissue == .Harbor ? f32(.20) : f32(.28)
        case .Hillside_Accretion, .Contour_Terrace, .Cycladic_Accretion:
            warp_fraction = .44
        case .Church_Cluster, .Fortified_Precinct:
            warp_fraction = .36
        }
        warp_amount := profile.world_cell * warp_fraction
        warp_x := (f32(cell_hash & 0xffff) / f32(0xffff) - .5) * 2 * warp_amount
        warp_z := (f32((cell_hash >> 16) & 0xffff) / f32(0xffff) - .5) * 2 * warp_amount
        x += warp_x
        z += warp_z
        macro := Settlement_Neighborhood {
            center      = {x, z},
            radius      = profile.world_cell * .62,
            density     = settlement_density_with_age(cell_density[linear], cell_age, profile),
            age         = cell_age,
            suitability = cell_suitability[linear],
            tissue      = tissue,
        }
        editor.settlement_plan.macro_cells[editor.settlement_plan.macro_cell_count] = macro
        editor.settlement_plan.macro_cell_count += 1
    }
    settlement_plan_build_macro_routes(&editor.settlement_plan, &editor.project, &settlement_rng)
    settlement_plan_split_route_intersections(&editor.settlement_plan)
    _ = settlement_plan_simplify_route_capacity(
        &editor.settlement_plan,
        roads.MAX_NODES - editor.project.road_graph.node_count,
        roads.MAX_EDGES - editor.project.road_graph.edge_count,
    )
    _ = settlement_plan_extract_route_faces(&editor.settlement_plan)
    settlement_plan_commit_routes(&editor.settlement_plan, &editor.project)
    for route in editor.settlement_plan.routes[:editor.settlement_plan.route_count] {
        if !route.drivable || route.class == .Civic_Spine {
            midpoint := route.geometry.points[route.geometry.count / 2]
            edit_kind := Settlement_Terrain_Edit_Kind.Neighborhood_Terrace
            if route.class == .Civic_Spine do edit_kind = .Road_Corridor
            settlement_plan_record_terrain_edit(
                &editor.settlement_plan,
                &editor.project,
                edit_kind,
                midpoint[0],
                midpoint[1],
                route.width * 1.5,
                route.width * 1.5,
                route.width,
            )
        }
    }
    // Civic anchors occupy meaningful positions: historic core first, then
    // low harbor ground, high sacred/fortified ground, and outer districts.
    landmark_target := 1
    switch profile.scale {
    case .City:
        landmark_target = 3 + seed % 4
    case .Town:
        landmark_target = 2 + seed % 2
    case .Village:
        landmark_target = 1
    }
    for landmark_index in 0 ..< landmark_target {
        landmark_kind := settlement_landmark_kind(region, landmark_index)
        anchor_index := settlement_landmark_anchor_index(&editor.settlement_plan, &editor.project, landmark_index)
        if anchor_index < 0 do continue
        anchor := editor.settlement_plan.neighborhoods[anchor_index]
        widths := region == .Aegean ? [3]f32{8, 13, 10} : [3]f32{10, 17, 13}
        depths := region == .Aegean ? [3]f32{8, 11, 9} : [3]f32{10, 14, 12}
        heights := region == .Aegean ? [3]f32{22, 15, 18} : [3]f32{42, 21, 30}
        variant := landmark_index % 3
        landmark_scale := f32(1)
        switch profile.scale {
        case .City:
            landmark_scale = 1
        case .Town:
            landmark_scale = .78
        case .Village:
            landmark_scale = .62
        }
        landmark_width := widths[variant] * landmark_scale
        landmark_depth := depths[variant] * landmark_scale
        landmark_height := heights[variant] * (.72 + landmark_scale * .28)
        x, z, rotation := anchor.center[0], anchor.center[1], f32(0)
        plaza_depth := profile.scale == .City ? f32(5) : (profile.scale == .Town ? f32(3.5) : f32(2.5))
        plaza_x, plaza_z := x, z
        route_origin, route_tangent, route_normal, route_width, route_shoulder, _, _, route_found :=
            settlement_nearest_route_frame(&editor.settlement_plan, anchor.center)
        if route_found {
            side := ((seed + landmark_index) & 1) == 0 ? f32(-1) : f32(1)
            setback := route_width * .5 + route_shoulder + plaza_depth + landmark_depth * .5 + .8
            x = route_origin[0] + route_normal[0] * setback * side
            z = route_origin[1] + route_normal[1] * setback * side
            if terrain.sample_height(&editor.project, 0, x, z) <= editor.project.sea_level + .6 {
                side = -side
                x = route_origin[0] + route_normal[0] * setback * side
                z = route_origin[1] + route_normal[1] * setback * side
            }
            plaza_x = route_origin[0] + route_normal[0] * (route_width * .5 + route_shoulder + plaza_depth * .5) * side
            plaza_z = route_origin[1] + route_normal[1] * (route_width * .5 + route_shoulder + plaza_depth * .5) * side
            rotation = f32(math.atan2(f64(route_tangent[1]), f64(route_tangent[0])))
        }
        previous_count := editor.project.structure_count
        markov_town_add_landmark(
            &editor.project,
            x,
            z,
            landmark_width,
            landmark_depth,
            landmark_height,
            rotation,
            settlement_landmark_seed(region, landmark_index, u32(seed)),
        )
        if editor.project.structure_count <= previous_count do continue
        editor.project.structures[editor.project.structure_count - 1].building = architecture.architecture_identity(
            {
                region = settlement_building_region(region),
                landmark_kind = settlement_building_landmark(landmark_kind),
                purpose_explicit = true,
            },
            settlement_landmark_seed(region, landmark_index, u32(seed)),
        )
        if region == .Aegean {
            editor.project.structures[editor.project.structure_count - 1].color = {240, 235, 218, 255}
        }
        settlement_plan_record_reserved_site(
            &editor.settlement_plan,
            editor.project.structures[editor.project.structure_count - 1],
            .Landmark,
            landmark_kind,
        )
        settlement_plan_record_terrain_edit(
            &editor.settlement_plan,
            &editor.project,
            .Plaza,
            plaza_x,
            plaza_z,
            landmark_width * .65,
            plaza_depth * .7,
            3,
        )
    }

    foliage_index := 0
    park_target := profile.scale == .City ? 3 : (profile.scale == .Town ? 2 : 1)
    grove_height := profile.scale == .Village ? f32(7) : (profile.scale == .Town ? f32(15) : f32(20))
    grove_footprint_scale := profile.scale == .Village ? f32(.52) : f32(1)
    for gz in 1 ..< MARKOV_TOWN_GRID - 1 {
        for gx in 1 ..< MARKOV_TOWN_GRID - 1 {
            linear := gz * MARKOV_TOWN_GRID + gx
            if !connected[linear] do continue
            cell_kind := Markov_Town_Cell(frame.state[gz * MARKOV_TOWN_GRID + gx])
            x := center + f32(gx - MARKOV_TOWN_GRID / 2) * profile.world_cell
            z := town_z + f32(gz - MARKOV_TOWN_GRID / 2) * profile.world_cell
            suitability := settlement_site_suitability(&editor.project, x, z, profile)
            if suitability <= .12 do continue
            if cell_kind == .Foliage {
                if foliage_index < park_target {
                    grove_width := (12 + f32((foliage_index * 7) % 7)) * (.7 + .3 * scale) * grove_footprint_scale
                    grove_depth := (11 + f32((foliage_index * 5) % 6)) * (.7 + .3 * scale) * grove_footprint_scale
                    if !settlement_park_site_clear(&editor.project, x, z, grove_width, grove_depth) {
                        foliage_index += 1
                        continue
                    }
                    previous_count := editor.project.structure_count
                    markov_town_add_grove(
                        &editor.project,
                        x,
                        z,
                        grove_width,
                        grove_depth,
                        grove_height,
                        u32(seed) ~ u32(0xa1 + foliage_index * 0x71),
                    )
                    if editor.project.structure_count > previous_count {
                        settlement_plan_record_reserved_site(
                            &editor.settlement_plan,
                            editor.project.structures[editor.project.structure_count - 1],
                            .Park,
                        )
                    }
                } else if editor.settlement_plan.decorative_foliage_count <
                   len(editor.settlement_plan.decorative_foliage) {
                    decorative_index := editor.settlement_plan.decorative_foliage_count
                    grove_width := (8 + f32((decorative_index * 5) % 8)) * (.7 + .3 * scale) * grove_footprint_scale
                    grove_depth := (7 + f32((decorative_index * 3) % 7)) * (.7 + .3 * scale) * grove_footprint_scale
                    grove_base_y := terrain.sample_height(&editor.project, 0, x, z)
                    grove := terrain.structure_make(x, z, grove_width, grove_depth, grove_base_y, grove_height)
                    grove.kind = .Foliage
                    grove.width = grove_width
                    grove.depth = grove_depth
                    grove.seed = u32(seed) ~ u32(0xc1 + decorative_index * 0x83)
                    grove.rotation = f32(grove.seed & 255) / 255 * math.PI
                    editor.settlement_plan.decorative_foliage[decorative_index] = grove
                    editor.settlement_plan.decorative_foliage_count += 1
                }
                foliage_index += 1
            }
        }
    }
    if settlement_plan_reserved_kind_count(&editor.settlement_plan, .Park) == 0 {
        fallback_width := f32(10) * (.7 + .3 * scale) * grove_footprint_scale
        fallback_depth := f32(9) * (.7 + .3 * scale) * grove_footprint_scale
        best_index, best_score := -1, f32(-1)
        for macro, macro_index in editor.settlement_plan.macro_cells[:editor.settlement_plan.macro_cell_count] {
            if !settlement_park_site_clear(
                &editor.project,
                macro.center[0],
                macro.center[1],
                fallback_width,
                fallback_depth,
            ) {
                continue
            }
            // Prefer the greener, later edge of the settlement so the
            // fallback reads as a grove or common rather than a vacant plaza.
            score := macro.age * .68 + macro.suitability * .32
            if score > best_score {
                best_index, best_score = macro_index, score
            }
        }
        if best_index >= 0 {
            point := editor.settlement_plan.macro_cells[best_index].center
            previous_count := editor.project.structure_count
            markov_town_add_grove(
                &editor.project,
                point[0],
                point[1],
                fallback_width,
                fallback_depth,
                grove_height,
                u32(seed) ~ 0x7f4a7c15,
            )
            if editor.project.structure_count > previous_count {
                settlement_plan_record_reserved_site(
                    &editor.settlement_plan,
                    editor.project.structures[editor.project.structure_count - 1],
                    .Park,
                )
            }
        }
    }
    // Reserve generated civic anchors and parks before ordinary parcels are
    // planned so a dense city cannot consume their structure capacity.
    plan := settlement_plan_generate_buildings(&editor.settlement_plan, &editor.project, &settlement_rng)
    settlement_plan_prepare_block_terrain(&editor.settlement_plan, &editor.project)
    markov_town_reseat_park_groves(&editor.settlement_plan, &editor.project)
    settlement_plan_seat_project_architecture(&editor.project)
    settlement_plan_seat_city(&plan, &editor.project)
    _ = architecture.city_commit_plan(&editor.project, &editor.project.city_density, bounds, &plan)
    decorative_budget := profile.scale == .City ? 12 : (profile.scale == .Town ? 8 : 4)
    decorative_commit_count := min(editor.settlement_plan.decorative_foliage_count, decorative_budget)
    for &structure in editor.settlement_plan.decorative_foliage[:decorative_commit_count] {
        structure.base_y =
            terrain.sample_height(&editor.project, 0, structure.center_x, structure.center_z)
        _ = terrain.add_structure(&editor.project, structure)
    }
    settlement_plan_import_city(&editor.settlement_plan, &plan, &editor.project)
    architecture.city_plan_replace(&editor.architecture_city_plan, plan)
    _ = settlement_village_attach_farmland(editor)
    settlement_plan_measure(&editor.settlement_plan)
    editor.settlement_plan.acceptance_failure = settlement_plan_acceptance_failure(
        &editor.settlement_plan,
        &editor.project,
    )
    editor.settlement_plan.valid = editor.settlement_plan.acceptance_failure == .None
    fmt.println("settlement:", settlement_plan_report(&editor.settlement_plan))
    if editor.settlement_plan.request.scale == .Village {
        fmt.println("settlement village:", settlement_village_program_report(&editor.settlement_plan))
    }
    if editor.settlement_plan.acceptance_failure == .Disconnected_Anchors {
        for route, route_index in editor.settlement_plan.routes[:editor.settlement_plan.route_count] {
            if route.required {
                fmt.println("settlement disconnected required route", route_index, route.class, route.geometry)
            }
        }
    }
    if editor.settlement_plan.acceptance_failure == .Route_Grade {
        for route, route_index in editor.settlement_plan.routes[:editor.settlement_plan.route_count] {
            limit := settlement_route_grade_limit(route.class)
            if route.maximum_grade > limit + .001 {
                fmt.println(
                    "settlement excessive route grade",
                    route_index,
                    route.class,
                    route.maximum_grade,
                    "limit",
                    limit,
                )
            }
        }
    }
    for class_index in 0 ..< SETTLEMENT_ROUTE_CLASS_COUNT {
        length_stats := editor.settlement_plan.metrics.route_length_by_class[class_index]
        if length_stats.count == 0 do continue
        fmt.println(
            "settlement route",
            Settlement_Route_Class(class_index),
            "length",
            settlement_stats_report(length_stats),
            "width",
            settlement_stats_report(editor.settlement_plan.metrics.route_width_by_class[class_index]),
        )
    }
    fmt.println(
        "settlement form:",
        "intersections",
        settlement_stats_report(editor.settlement_plan.metrics.intersection_spacing),
        "network_density",
        editor.settlement_plan.metrics.network_density,
        "block_aspect",
        settlement_stats_report(editor.settlement_plan.metrics.block_aspect),
        "block_irregularity",
        settlement_stats_report(editor.settlement_plan.metrics.block_irregularity),
        "frontage",
        settlement_stats_report(editor.settlement_plan.metrics.parcel_frontage),
        "depth",
        settlement_stats_report(editor.settlement_plan.metrics.parcel_depth),
        "footprint",
        settlement_stats_report(editor.settlement_plan.metrics.building_footprint),
        "floors",
        settlement_stats_report(editor.settlement_plan.metrics.building_floors),
        "attached",
        editor.settlement_plan.metrics.attached_share,
        "density_bands",
        editor.settlement_plan.metrics.density_band_count,
    )
    for structure in editor.project.structures[:editor.project.structure_count] {
        if structure.kind != .Architecture || structure.height > 58 || settlement_structure_is_landmark(structure) {
            continue
        }
        _ = architecture.city_density_stamp(
            &editor.project.climbing_leaf_density,
            structure.center_x,
            structure.center_z,
            max(structure.width, structure.depth) * .38,
            .62,
            .65,
        )
    }

    editor.capture_player_walk_pose = true
    editor.postale_visible = false
    editor.car.position = {center + 600, 0, town_z + 600}
    editor.libellula.vehicle.position = {center + 650, 0, town_z + 650}
    editor.architecture_node_mode = true
    camera := third_person.default_camera()
    camera.yaw_radians = -.72
    camera.pitch_radians = .12
    switch profile.scale {
    case .City:
        camera.distance = 92
    case .Town:
        camera.distance = 72
    case .Village:
        camera.distance = 70
    }
    lab_scene_configure_camera(editor, {core_x, 6, core_z}, camera)
    if editor.settlement_plan.route_count > 0 {
        look_x, look_z := core_x, core_z
        if plan.count > 0 {
            look_x, look_z = 0, 0
            for structure in plan.structures[:plan.count] {
                look_x += structure.center_x
                look_z += structure.center_z
            }
            look_x /= f32(plan.count)
            look_z /= f32(plan.count)
        }
        selected_outer, selected_inner := [2]f32{}, [2]f32{}
        selected_length := f32(0)
        selected_obstruction := f32(1e30)
        for planned_route in editor.settlement_plan.routes[:editor.settlement_plan.route_count] {
            if !planned_route.drivable do continue
            route := planned_route.geometry
            if route.count < 2 do continue
            for segment_index in 0 ..< route.count - 1 {
                first, second := route.points[segment_index], route.points[segment_index + 1]
                dx, dz := second[0] - first[0], second[1] - first[1]
                segment_length := f32(math.sqrt(f64(dx * dx + dz * dz)))
                if segment_length <= .01 do continue
                first_core_distance :=
                    (first[0] - core_x) * (first[0] - core_x) + (first[1] - core_z) * (first[1] - core_z)
                second_core_distance :=
                    (second[0] - core_x) * (second[0] - core_x) + (second[1] - core_z) * (second[1] - core_z)
                outer := first_core_distance > second_core_distance ? first : second
                inner := first_core_distance > second_core_distance ? second : first
                inward_x, inward_z := (inner[0] - outer[0]) / segment_length, (inner[1] - outer[1]) / segment_length
                candidate_camera_x := look_x - inward_x * camera.distance
                candidate_camera_z := look_z - inward_z * camera.distance
                obstruction := f32(0)
                for structure in editor.project.structures[:editor.project.structure_count] {
                    if structure.kind != .Foliage && structure.kind != .Architecture do continue
                    relative_x := structure.center_x - candidate_camera_x
                    relative_z := structure.center_z - candidate_camera_z
                    along := (relative_x * inward_x + relative_z * inward_z) / camera.distance
                    if along <= .06 || along >= .94 do continue
                    lateral_x := relative_x - inward_x * along * camera.distance
                    lateral_z := relative_z - inward_z * along * camera.distance
                    lateral_distance := f32(math.sqrt(f64(lateral_x * lateral_x + lateral_z * lateral_z)))
                    crown_radius := max(structure.width, structure.depth) * .5
                    clearance := structure.kind == .Foliage ? f32(4) : f32(2)
                    if lateral_distance < crown_radius + clearance {
                        kind_weight := structure.kind == .Architecture ? f32(1.8) : f32(1)
                        obstruction += (crown_radius + clearance - lateral_distance) * (1.15 - along) * kind_weight
                    }
                }
                if obstruction > selected_obstruction + .01 ||
                   (math.abs(obstruction - selected_obstruction) <= .01 && segment_length <= selected_length) {
                    continue
                }
                selected_outer, selected_inner = outer, inner
                selected_length = segment_length
                selected_obstruction = obstruction
            }
        }
        if selected_length > .01 {
            dx, dz :=
                (selected_inner[0] - selected_outer[0]) /
                selected_length,
                (selected_inner[1] - selected_outer[1]) /
                selected_length
            // Stand outside the complete form and look inward along the
            // approach road. Using the route endpoint itself placed village
            // captures only ~14 m from the common—inside the cluster—so most
            // of the settlement was behind or beside the camera.
            camera_x := look_x - dx * camera.distance
            camera_z := look_z - dz * camera.distance
            camera_y := terrain.sample_height(&editor.project, 0, camera_x, camera_z) + 2.4
            look_y := terrain.sample_height(&editor.project, 0, look_x, look_z) + 3.4
            streetscape := third_person.Camera_Pose {
                position = {camera_x, camera_y, camera_z},
                target   = {look_x, look_y, look_z},
            }
            editor.editor_focus = streetscape.target
            editor.camera_pose = streetscape
            third_person.camera_set_pose(&editor.cameras, .Inspection, streetscape)
            third_person.camera_set_active(&editor.cameras, .Inspection)
        }
    }
    if vertical_map {
        map_focus, map_height := settlement_map_frame(&editor.project, {core_x, core_z}, radius)
        focus := third_person.Vec3{map_focus[0], 0, map_focus[1]}
        overhead := third_person.Camera_Pose {
            position = {map_focus[0], map_height, map_focus[1] + map_height * .065},
            target   = focus,
        }
        editor.settlement_diagnostic_layer = -1
        editor.editor_focus = focus
        editor.camera_pose = overhead
        third_person.camera_set_pose(&editor.cameras, .Inspection, overhead)
        third_person.camera_set_active(&editor.cameras, .Inspection)
    }
    return true
}

settlement_tissue_overlay_color :: proc(tissue: Settlement_Tissue) -> rl.Color {
    switch tissue {
    case .Venetian_Mercantile:
        return {214, 113, 74, 118}
    case .Dalmatian_Planned:
        return {230, 184, 92, 118}
    case .Hillside_Accretion:
        return {158, 119, 188, 118}
    case .Harbor:
        return {72, 168, 206, 118}
    case .Later_Extension:
        return {155, 174, 184, 105}
    case .Fortified_Precinct:
        return {191, 79, 91, 125}
    case .Cycladic_Accretion:
        return {232, 226, 202, 125}
    case .Contour_Terrace:
        return {118, 190, 154, 118}
    case .Church_Cluster:
        return {218, 173, 219, 125}
    }
    return {200, 200, 200, 110}
}

settlement_route_overlay_color :: proc(class: Settlement_Route_Class) -> rl.Color {
    switch class {
    case .Civic_Spine:
        return {247, 211, 91, 225}
    case .Connector:
        return {236, 132, 70, 220}
    case .Street:
        return {225, 225, 216, 210}
    case .Lane:
        return {117, 202, 172, 210}
    case .Alley:
        return {96, 158, 212, 215}
    case .Stair:
        return {192, 121, 217, 220}
    case .Waterfront:
        return {72, 203, 224, 225}
    case .Ridge:
        return {231, 117, 142, 220}
    }
    return {220, 220, 220, 210}
}

world_settlement_route_overlay :: proc(editor: ^Editor, route: Settlement_Planned_Route, color: rl.Color) {
    for index in 0 ..< route.geometry.count - 1 {
        a, b := route.geometry.points[index], route.geometry.points[index + 1]
        dx, dz := b[0] - a[0], b[1] - a[1]
        length := f32(math.sqrt(f64(dx * dx + dz * dz)))
        if length <= .01 do continue
        world_land_surface_rotated(
            editor,
            (a[0] + b[0]) * .5,
            (a[1] + b[1]) * .5,
            length,
            max(route.width, f32(1.2)),
            f32(math.atan2(f64(dz), f64(dx))),
            .24,
            color,
        )
    }
}

world_settlement_diagnostics :: proc(editor: ^Editor) {
    if editor == nil || editor.settlement_diagnostic_layer < 0 do return
    plan := &editor.settlement_plan
    switch editor.settlement_diagnostic_layer {
    case 0:
        for cell in plan.macro_cells[:plan.macro_cell_count] {
            world_land_surface_rotated(
                editor,
                cell.center[0],
                cell.center[1],
                cell.radius * 1.55,
                cell.radius * 1.55,
                0,
                .18,
                settlement_tissue_overlay_color(cell.tissue),
            )
        }
    case 1, 2:
        for cell in plan.macro_cells[:plan.macro_cell_count] {
            value := editor.settlement_diagnostic_layer == 1 ? cell.density : cell.suitability
            low := rl.Color{48, 76, 123, 92}
            high := rl.Color{244, 213, 91, 176}
            if editor.settlement_diagnostic_layer == 2 {
                low, high = rl.Color{176, 67, 74, 112}, rl.Color{88, 210, 142, 176}
            }
            amount := clamp(value, 0, 1)
            color := rl.Color {
                u8(f32(low.r) + (f32(high.r) - f32(low.r)) * amount),
                u8(f32(low.g) + (f32(high.g) - f32(low.g)) * amount),
                u8(f32(low.b) + (f32(high.b) - f32(low.b)) * amount),
                u8(f32(low.a) + (f32(high.a) - f32(low.a)) * amount),
            }
            world_land_surface_rotated(
                editor,
                cell.center[0],
                cell.center[1],
                cell.radius * 1.55,
                cell.radius * 1.55,
                0,
                .18,
                color,
            )
        }
    case 3, 4:
        for route in plan.routes[:plan.route_count] {
            color := settlement_route_overlay_color(route.class)
            if editor.settlement_diagnostic_layer == 4 {
                amount := clamp(route.maximum_grade / max(settlement_route_grade_limit(route.class), f32(.01)), 0, 1)
                color = {u8(70 + amount * 180), u8(220 - amount * 150), 78, 225}
            }
            world_settlement_route_overlay(editor, route, color)
        }
    case 5:
        for block in plan.blocks[:plan.block_count] {
            rotation := f32(0)
            if block.corner_count >= 2 {
                edge := block.corners[1] - block.corners[0]
                rotation = f32(math.atan2(f64(edge[1]), f64(edge[0])))
            }
            world_land_surface_rotated(
                editor,
                block.center[0],
                block.center[1],
                block.long_side,
                block.short_side,
                rotation,
                .20,
                {174, 115, 219, 105},
            )
        }
    case 6:
        for edit in plan.terrain_edits[:plan.terrain_edit_count] {
            world_land_surface_rotated(
                editor,
                edit.center[0],
                edit.center[1],
                edit.half_extent[0] * 2,
                edit.half_extent[1] * 2,
                0,
                .22,
                {225, 143, 70, 125},
            )
        }
    case 7, 8, 9:
        wanted := Settlement_Site_Kind.Ordinary
        color := rl.Color{89, 211, 183, 230}
        if editor.settlement_diagnostic_layer == 8 {
            wanted = .Landmark
            color = {247, 205, 84, 240}
        } else if editor.settlement_diagnostic_layer == 9 {
            wanted = .Rejected
            color = {238, 76, 88, 235}
        }
        if wanted == .Rejected {
            for site in plan.rejected_sites[:plan.rejected_site_count] {
                world_structure_frame(site.structure, site.structure.base_y + .20, color)
            }
            break
        }
        for site in plan.sites[:plan.site_count] {
            if site.kind != wanted do continue
            world_structure_frame(site.structure, site.structure.base_y + .20, color)
        }
    }
}

world_markov_town_wanderers :: proc(editor: ^Editor) {
    if editor == nil || editor.settlement_vertical_map do return
    world_settlement_diagnostics(editor)
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    town_z := center + 95
    time := f32(rl.GetTime())
    for index in 0 ..< 6 {
        walking := index < 4
        angular_speed := .028 + f32(index) * .002
        phase := f32(index) * 1.07
        if walking do phase += time * angular_speed
        radius_x := 34 + f32(index % 3) * 13
        radius_z := 22 + f32((index + 1) % 3) * 11
        x := center + f32(math.cos(f64(phase))) * radius_x
        z := town_z + f32(math.sin(f64(phase))) * radius_z
        dx := -f32(math.sin(f64(phase))) * radius_x
        dz := f32(math.cos(f64(phase))) * radius_z
        // Mouse model forward is {-sin(yaw), +cos(yaw)}.
        rotation := f32(math.atan2(f64(-dx), f64(dz)))
        y := terrain.sample_height(&editor.project, 0, x, z)
        world_mouse_model_scaled(
            editor,
            {
                position = {x, y, z},
                rotation = rotation,
                accessory = index % 2 == 0 ? Mouse_Accessory.Paper_Boat : Mouse_Accessory.None,
                fur = index % 3 == 0 ? Mouse_Fur.Chestnut : Mouse_Fur.Cream,
                pattern = index % 2 == 0 ? Mouse_Fur_Pattern.Piebald : Mouse_Fur_Pattern.Solid,
                scarf_enabled = index % 3 == 1,
                scarf_color = {180, 78, 58, 255},
                grounded = true,
                player_controlled = walking,
            },
            .92 + f32(index % 3) * .05,
        )
    }
}

SETTLEMENT_DIAGNOSTIC_LAYERS := [?]string {
    "macro tissue",
    "density",
    "terrain suitability",
    "route class",
    "route grade",
    "blocks / clusters",
    "terraces",
    "parcels",
    "landmarks",
    "rejected candidates",
}

settlement_lab_process_input :: proc(editor: ^Editor) {
    if editor == nil do return
    if rl.IsKeyPressed(.TAB) {
        editor.settlement_diagnostic_layer =
            (editor.settlement_diagnostic_layer + 1) % len(SETTLEMENT_DIAGNOSTIC_LAYERS)
    }
}

settlement_lab_draw_ui :: proc(editor: ^Editor, _: i32, _: i32) {
    if editor == nil || editor.settlement_diagnostic_layer < 0 do return
    plan := &editor.settlement_plan
    region := plan.request.region == .Adriatic ? "ADRIATIC" : "AEGEAN"
    rl.DrawTextEx(
        rl.Font{},
        fmt.ctprintf("%s %v SETTLEMENT LAB", region, plan.request.scale),
        {38, 38},
        19,
        1,
        {245, 239, 192, 255},
    )
    rl.DrawTextEx(
        rl.Font{},
        fmt.ctprintf(
            "TAB  OVERLAY  %d/%d  %s",
            editor.settlement_diagnostic_layer + 1,
            len(SETTLEMENT_DIAGNOSTIC_LAYERS),
            SETTLEMENT_DIAGNOSTIC_LAYERS[editor.settlement_diagnostic_layer],
        ),
        {38, 70},
        13,
        1,
        {211, 250, 242, 255},
    )
    report := settlement_plan_report(plan)
    rl.DrawTextEx(rl.Font{}, fmt.ctprintf("%s", report), {38, 94}, 11, 1, {164, 190, 190, 255})
    rl.DrawTextEx(
        rl.Font{},
        fmt.ctprintf(
            "seed %u  neighborhoods %d  terrain edits %d  graph %d/%d nodes %d/%d edges",
            plan.request.seed,
            plan.neighborhood_count,
            plan.terrain_edit_count,
            editor.project.road_graph.node_count,
            roads.MAX_NODES,
            editor.project.road_graph.edge_count,
            roads.MAX_EDGES,
        ),
        {38, 114},
        11,
        1,
        plan.valid ? rl.Color{164, 220, 180, 255} : rl.Color{244, 130, 120, 255},
    )
    if plan.request.scale == .Village {
        village_report := settlement_village_program_report(plan)
        rl.DrawTextEx(rl.Font{}, fmt.ctprintf("%s", village_report), {38, 134}, 11, 1, {211, 220, 175, 255})
    }
}
