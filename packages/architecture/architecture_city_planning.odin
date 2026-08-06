package architecture

import buildings "../buildings"
import planar_geometry "zelda_engine:planar_geometry"
import roads "../roads"
import terrain "../terrain"
import "core:math"

@(no_instrumentation)
architecture_frontage_structure :: #force_inline proc(structure: terrain.Structure) -> terrain.Structure {
    result := structure
    if structure.kind != .Architecture do return result
    footprint := architecture_footprint(structure)
    if footprint.count <= 0 do return result
    frontage_index := architecture_frontage_mass_index(structure)
    frontage_mass := footprint.masses[frontage_index]
    result.center_x, result.center_z = architecture_mass_world(structure, frontage_mass)
    result.width = frontage_mass.width
    result.depth = frontage_mass.depth
    // Frontage consumers attach to rendered wall geometry, not terrain sample
    // resolution. Inflating a compact 4.8 m office to BASE_CELL_SIZE placed
    // vines, laundry, and other façade-dependent details above its roof.
    result.height = max(f32(0), structure.height * frontage_mass.height_scale)
    result.seed = structure.seed + u32(frontage_index * 747796405)
    return result
}

city_bounds_point :: proc(x, z, radius: f32) -> City_Bounds {
    return {x - radius, z - radius, x + radius, z + radius, true}
}

city_bounds_union :: proc(a, b: City_Bounds) -> City_Bounds {
    if !a.valid do return b
    if !b.valid do return a
    return {min(a.min_x, b.min_x), min(a.min_z, b.min_z), max(a.max_x, b.max_x), max(a.max_z, b.max_z), true}
}

city_bounds_expand :: proc(bounds: City_Bounds, amount: f32) -> City_Bounds {
    if !bounds.valid do return bounds
    return {bounds.min_x - amount, bounds.min_z - amount, bounds.max_x + amount, bounds.max_z + amount, true}
}

city_bounds_contains :: proc(bounds: City_Bounds, x, z: f32) -> bool {
    return bounds.valid && x >= bounds.min_x && x <= bounds.max_x && z >= bounds.min_z && z <= bounds.max_z
}

@(no_instrumentation)
city_density_index :: #force_inline proc(x, z: int) -> int {
    return z * terrain.RING_RESOLUTION + x
}

city_density_world_position :: proc(x, z: int) -> (f32, f32) {
    half := f32(terrain.RING_RESOLUTION - 1) * .5
    return (f32(x) - half) * terrain.BASE_CELL_SIZE, (f32(z) - half) * terrain.BASE_CELL_SIZE
}

city_density_bounds :: proc(field: ^[terrain.CITY_DENSITY_SAMPLES]u8) -> City_Bounds {
    if field == nil do return {}
    bounds: City_Bounds
    for z in 0 ..< terrain.RING_RESOLUTION {
        for x in 0 ..< terrain.RING_RESOLUTION {
            if field[city_density_index(x, z)] == 0 do continue
            world_x, world_z := city_density_world_position(x, z)
            point := City_Bounds{world_x, world_z, world_x, world_z, true}
            bounds = city_bounds_union(bounds, point)
        }
    }
    if bounds.valid do bounds = city_bounds_expand(bounds, terrain.BASE_CELL_SIZE * 2)
    return bounds
}

@(no_instrumentation)
city_density_sample :: #force_inline proc(
    field: ^[terrain.CITY_DENSITY_SAMPLES]u8,
    world_x, world_z: f32,
    project: ^terrain.Project = nil,
) -> f32 {
    if field == nil do return 0
    sample_x, sample_z := world_x, world_z
    if project != nil do sample_x, sample_z = terrain.island_source_position(project, world_x, world_z)
    half := f32(terrain.RING_RESOLUTION - 1) * .5
    gx := sample_x / terrain.BASE_CELL_SIZE + half
    gz := sample_z / terrain.BASE_CELL_SIZE + half
    x0 := clamp(int(math.floor(f64(gx))), 0, terrain.RING_RESOLUTION - 1)
    z0 := clamp(int(math.floor(f64(gz))), 0, terrain.RING_RESOLUTION - 1)
    x1 := min(x0 + 1, terrain.RING_RESOLUTION - 1)
    z1 := min(z0 + 1, terrain.RING_RESOLUTION - 1)
    tx, tz := clamp(gx - f32(x0), 0, 1), clamp(gz - f32(z0), 0, 1)
    a := f32(field[city_density_index(x0, z0)]) * (1 - tx) + f32(field[city_density_index(x1, z0)]) * tx
    b := f32(field[city_density_index(x0, z1)]) * (1 - tx) + f32(field[city_density_index(x1, z1)]) * tx
    return (a * (1 - tz) + b * tz) / 255
}

city_density_stamp :: proc(
    field: ^[terrain.CITY_DENSITY_SAMPLES]u8,
    world_x, world_z, radius, strength, hardness: f32,
    erase: bool = false,
) -> City_Bounds {
    if field == nil || radius <= 0 || strength <= 0 do return {}
    inner := radius * clamp(hardness, 0, 1)
    half := f32(terrain.RING_RESOLUTION - 1) * .5
    min_x := clamp(
        int(math.floor(f64((world_x - radius) / terrain.BASE_CELL_SIZE + half))),
        0,
        terrain.RING_RESOLUTION - 1,
    )
    max_x := clamp(
        int(math.ceil(f64((world_x + radius) / terrain.BASE_CELL_SIZE + half))),
        0,
        terrain.RING_RESOLUTION - 1,
    )
    min_z := clamp(
        int(math.floor(f64((world_z - radius) / terrain.BASE_CELL_SIZE + half))),
        0,
        terrain.RING_RESOLUTION - 1,
    )
    max_z := clamp(
        int(math.ceil(f64((world_z + radius) / terrain.BASE_CELL_SIZE + half))),
        0,
        terrain.RING_RESOLUTION - 1,
    )
    for z in min_z ..= max_z {
        for x in min_x ..= max_x {
            px, pz := city_density_world_position(x, z)
            dx, dz := px - world_x, pz - world_z
            distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
            if distance > radius do continue
            falloff: f32 = 1
            if distance > inner && radius > inner {
                t := clamp((distance - inner) / (radius - inner), 0, 1)
                falloff = 1 - t * t * (3 - 2 * t)
            }
            index := city_density_index(x, z)
            delta := int(math.round(f64(clamp(strength, 0, 1) * falloff * 255)))
            value := int(field[index])
            value += erase ? -delta : delta
            field[index] = u8(clamp(value, 0, 255))
        }
    }
    return city_bounds_point(world_x, world_z, radius)
}

@(no_instrumentation)
city_hash :: #force_inline proc(x, z: int, seed: u32) -> u32 {
    value := seed ~ (u32(i32(x)) * 0x9e3779b9) ~ (u32(i32(z)) * 0x85ebca6b)
    value = (value ~ (value >> 16)) * 0x7feb352d
    value = (value ~ (value >> 15)) * 0x846ca68b
    return value ~ (value >> 16)
}

city_hash_unit :: proc(x, z: int, seed: u32, lane: u32 = 0) -> f32 {
    return f32(city_hash(x, z, seed + lane * 0x9e3779b9) & 0x00ffffff) / f32(0x01000000)
}

City_Road_Frontage :: struct {
    found:                bool,
    distance:             f32,
    point_x, point_z:     f32,
    tangent_x, tangent_z: f32,
    clearance:            f32,
}

city_nearest_road_frontage :: proc(graph: ^roads.Graph, x, z: f32) -> City_Road_Frontage {
    hit := City_Road_Frontage {
        distance = f32(1.0e20),
    }
    if graph == nil do return hit
    for edge in graph.edges[:graph.edge_count] {
        previous := roads.edge_point(graph, edge, 0)
        for sample in 1 ..= 32 {
            current := roads.edge_point(graph, edge, f32(sample) / 32)
            vx, vz := current.x - previous.x, current.z - previous.z
            length_sq := vx * vx + vz * vz
            if length_sq > .0001 {
                amount := clamp(((x - previous.x) * vx + (z - previous.z) * vz) / length_sq, 0, 1)
                px, pz := previous.x + vx * amount, previous.z + vz * amount
                dx, dz := x - px, z - pz
                candidate := f32(math.sqrt(f64(dx * dx + dz * dz)))
                if candidate < hit.distance {
                    length := f32(math.sqrt(f64(length_sq)))
                    hit = {
                        found     = true,
                        distance  = candidate,
                        point_x   = px,
                        point_z   = pz,
                        tangent_x = vx / length,
                        tangent_z = vz / length,
                        clearance = edge.half_width + edge.shoulder_width + 2,
                    }
                }
            }
            previous = current
        }
    }
    return hit
}

city_nearest_road :: proc(
    graph: ^roads.Graph,
    x, z: f32,
) -> (
    found: bool,
    distance, tangent_x, tangent_z, clearance: f32,
) {
    if graph == nil do return
    hit := city_nearest_road_frontage(graph, x, z)
    found, distance = hit.found, hit.distance
    tangent_x, tangent_z, clearance = hit.tangent_x, hit.tangent_z, hit.clearance
    for node in graph.nodes[:graph.node_count] {
        dx, dz := x - node.position.x, z - node.position.z
        candidate := f32(math.sqrt(f64(dx * dx + dz * dz)))
        if candidate - node.junction_radius < distance - clearance {
            found, distance = true, candidate
            tangent_x, tangent_z = 1, 0
            clearance = node.junction_radius + 2
        }
    }
    return
}

@(no_instrumentation)
architecture_mass_world :: #force_inline proc(structure: terrain.Structure, mass: Architecture_Mass) -> (x, z: f32) {
    cosine, sine := f32(math.cos(f64(structure.rotation))), f32(math.sin(f64(structure.rotation)))
    return structure.center_x + mass.local_x * cosine - mass.local_z * sine,
        structure.center_z + mass.local_x * sine + mass.local_z * cosine
}

architecture_mass_overlaps :: proc(
    a: terrain.Structure,
    am: Architecture_Mass,
    b: terrain.Structure,
    bm: Architecture_Mass,
    padding: f32,
) -> bool {
    ax, az := architecture_mass_world(a, am)
    bx, bz := architecture_mass_world(b, bm)
    return(
        !planar_geometry.oriented_rectangles_clear(
            {ax, az},
            {am.width, am.depth},
            a.rotation,
            {bx, bz},
            {bm.width, bm.depth},
            b.rotation,
            padding,
        ) \
    )
}

city_structure_overlaps :: proc(a, b: terrain.Structure, padding: f32 = 1.5) -> bool {
    af, bf := architecture_footprint(a), architecture_footprint(b)
    for am in af.masses[:af.count] {
        for bm in bf.masses[:bf.count] {
            if architecture_mass_overlaps(a, am, b, bm, padding) do return true
        }
    }
    return false
}

city_accent_site_clear :: proc(project: ^terrain.Project, x, z, radius: f32, padding: f32 = 1.5) -> bool {
    if project == nil do return false
    clearance := max(radius + padding, f32(0))
    for structure in project.structures[:project.structure_count] {
        if structure.kind != .Architecture do continue
        cosine, sine := math.cos(structure.rotation), math.sin(structure.rotation)
        footprint := architecture_footprint(structure)
        for mass in footprint.masses[:footprint.count] {
            mass_x, mass_z := architecture_mass_world(structure, mass)
            dx, dz := x - mass_x, z - mass_z
            local_x := dx * cosine + dz * sine
            local_z := -dx * sine + dz * cosine
            outside_x := max(math.abs(local_x) - mass.width * .5, f32(0))
            outside_z := max(math.abs(local_z) - mass.depth * .5, f32(0))
            if outside_x * outside_x + outside_z * outside_z < clearance * clearance do return false
        }
    }
    return true
}

city_structure_site_valid :: proc(project: ^terrain.Project, structure: ^terrain.Structure) -> bool {
    if project == nil || structure == nil do return false
    lowest, highest_coarse := architecture_foundation_height_range(project, structure^, false)
    if lowest <= project.sea_level + .15 do return false
    allowed_relief := max(f32(2.5), min(structure.width, structure.depth) * .12)
    if highest_coarse - lowest > allowed_relief do return false
    _, highest := architecture_foundation_height_range(project, structure^)
    structure.base_y = highest
    return true
}

architecture_mass_height_range :: proc(
    project: ^terrain.Project,
    structure: terrain.Structure,
) -> (
    lowest, highest: f32,
) {
    if project == nil do return structure.base_y, structure.base_y
    cosine, sine := f32(math.cos(f64(structure.rotation))), f32(math.sin(f64(structure.rotation)))
    lowest = f32(1.0e20)
    highest = f32(-1.0e20)
    // A center/corner/edge-midpoint probe misses narrow ridges beneath long
    // façades. Seat the mass from a fine grid over its complete footprint so
    // no section of frontage can be generated below the visible ground.
    sample_spacing := terrain.FINE_CELL_SIZE
    x_intervals := clamp(int(math.ceil(f64(structure.width / sample_spacing))), 1, 128)
    z_intervals := clamp(int(math.ceil(f64(structure.depth / sample_spacing))), 1, 128)
    for z_index in 0 ..= z_intervals {
        local_z := -structure.depth * .5 + structure.depth * f32(z_index) / f32(z_intervals)
        for x_index in 0 ..= x_intervals {
            local_x := -structure.width * .5 + structure.width * f32(x_index) / f32(x_intervals)
            px := structure.center_x + local_x * cosine - local_z * sine
            pz := structure.center_z + local_x * sine + local_z * cosine
            height := terrain.sample_surface_height(project, 0, px, pz)
            lowest, highest = min(lowest, height), max(highest, height)
        }
    }
    return
}

architecture_foundation_height_range :: proc(
    project: ^terrain.Project,
    structure: terrain.Structure,
    dense: bool = true,
) -> (
    lowest, highest: f32,
) {
    if project == nil do return structure.base_y, structure.base_y
    lowest = f32(1.0e20)
    highest = f32(-1.0e20)
    footprint := architecture_footprint(structure)
    for mass in footprint.masses[:footprint.count] {
        child := structure
        child.center_x, child.center_z = architecture_mass_world(structure, mass)
        child.width, child.depth = mass.width, mass.depth
        mass_lowest, mass_highest: f32
        if dense {
            mass_lowest, mass_highest = architecture_mass_height_range(project, child)
        } else {
            cosine, sine := f32(math.cos(f64(child.rotation))), f32(math.sin(f64(child.rotation)))
            half_width, half_depth := child.width * .5, child.depth * .5
            points := [9][2]f32 {
                {0, 0},
                {-half_width, -half_depth},
                {0, -half_depth},
                {half_width, -half_depth},
                {half_width, 0},
                {half_width, half_depth},
                {0, half_depth},
                {-half_width, half_depth},
                {-half_width, 0},
            }
            mass_lowest, mass_highest = f32(1.0e20), f32(-1.0e20)
            for point in points {
                px := child.center_x + point[0] * cosine - point[1] * sine
                pz := child.center_z + point[0] * sine + point[1] * cosine
                height := terrain.sample_surface_height(project, 0, px, pz)
                mass_lowest, mass_highest = min(mass_lowest, height), max(mass_highest, height)
            }
        }
        lowest, highest = min(lowest, mass_lowest), max(highest, mass_highest)
    }
    return
}

city_structure_road_clear :: proc(graph: ^roads.Graph, structure: ^terrain.Structure) -> bool {
    if graph == nil || structure == nil do return false
    cosine, sine := f32(math.cos(f64(structure.rotation))), f32(math.sin(f64(structure.rotation)))
    footprint := architecture_footprint(structure^)
    for mass in footprint.masses[:footprint.count] {
        half_width, half_depth := mass.width * .5, mass.depth * .5
        samples := [9][2]f32 {
            {mass.local_x, mass.local_z},
            {mass.local_x - half_width, mass.local_z - half_depth},
            {mass.local_x, mass.local_z - half_depth},
            {mass.local_x + half_width, mass.local_z - half_depth},
            {mass.local_x + half_width, mass.local_z},
            {mass.local_x + half_width, mass.local_z + half_depth},
            {mass.local_x, mass.local_z + half_depth},
            {mass.local_x - half_width, mass.local_z + half_depth},
            {mass.local_x - half_width, mass.local_z},
        }
        for sample in samples {
            x := structure.center_x + sample[0] * cosine - sample[1] * sine
            z := structure.center_z + sample[0] * sine + sample[1] * cosine
            found, distance, _, _, clearance := city_nearest_road(graph, x, z)
            if found && distance < clearance do return false
        }
    }
    return true
}

city_plan_density_grid :: proc(
    project: ^terrain.Project,
    field: ^[terrain.CITY_DENSITY_SAMPLES]u8,
    rebuild_bounds: City_Bounds,
    seed: u32 = 0xA71D3,
) -> City_Plan {
    plan: City_Plan
    if project == nil || field == nil || !rebuild_bounds.valid do return plan
    cell := terrain.BASE_CELL_SIZE * 1.18
    min_x := int(math.floor(f64(rebuild_bounds.min_x / cell))) - 1
    max_x := int(math.ceil(f64(rebuild_bounds.max_x / cell))) + 1
    min_z := int(math.floor(f64(rebuild_bounds.min_z / cell))) - 1
    max_z := int(math.ceil(f64(rebuild_bounds.max_z / cell))) + 1

    // Visit dense candidates first so contested footprints belong to the
    // strongest town centers rather than whichever grid coordinate came first.
    for band in 0 ..< 4 {
        band_low := f32(3 - band) * .25
        band_high := band_low + .25
        for gz in min_z ..= max_z {
            for gx in min_x ..= max_x {
                jitter_x := (city_hash_unit(gx, gz, seed, 1) - .5) * cell * .72
                jitter_z := (city_hash_unit(gx, gz, seed, 2) - .5) * cell * .72
                x, z := (f32(gx) + .5) * cell + jitter_x, (f32(gz) + .5) * cell + jitter_z
                if !city_bounds_contains(rebuild_bounds, x, z) do continue
                density := city_density_sample(field, x, z, project)
                if density < .08 || density < band_low || (band < 3 && density >= band_high) do continue
                probability := clamp((density - .05) * 1.08, 0, 1)
                if city_hash_unit(gx, gz, seed, 3) > probability do continue

                compact := density * density
                width := 22 + city_hash_unit(gx, gz, seed, 4) * 15 - compact * 8
                depth := 15 + city_hash_unit(gx, gz, seed, 5) * 11 - compact * 4
                building_seed := city_hash(gx, gz, seed)
                height := city_building_height(width, depth, density, building_seed)
                anchor := density > .85 && city_hash_unit(gx, gz, seed, 7) > .94
                if anchor do height = 60 + city_hash_unit(gx, gz, seed, 8) * 14
                rotation := (city_hash_unit(gx, gz, seed, 9) - .5) * .65

                frontage := city_nearest_road_frontage(&project.road_graph, x, z)
                if frontage.found && frontage.distance < 96 {
                    rotation =
                        f32(math.atan2(f64(frontage.tangent_z), f64(frontage.tangent_x))) +
                        (city_hash_unit(gx, gz, seed, 10) - .5) * .08

                    // Preserve the candidate's side of the street, but derive
                    // its actual frontage from the road curve. This produces
                    // coherent street walls without making the road package
                    // aware of product-specific building rules.
                    normal_x, normal_z := -frontage.tangent_z, frontage.tangent_x
                    side := (x - frontage.point_x) * normal_x + (z - frontage.point_z) * normal_z
                    if math.abs(side) < .001 {
                        side = city_hash_unit(gx, gz, seed, 11) < .5 ? -1 : 1
                    }
                    side = side < 0 ? -1 : 1
                    if side > 0 do rotation += math.PI
                    setback := 2.5 + (1 - density) * 4
                    normal_extent :=
                        math.abs(f32(math.sin(f64(rotation))) * width * .5) +
                        math.abs(f32(math.cos(f64(rotation))) * depth * .5)
                    frontage_offset := frontage.clearance + normal_extent + setback
                    x = frontage.point_x + normal_x * side * frontage_offset
                    z = frontage.point_z + normal_z * side * frontage_offset
                    if !city_bounds_contains(rebuild_bounds, x, z) do continue
                } else {
                    gradient_x :=
                        city_density_sample(field, x + cell, z, project) -
                        city_density_sample(field, x - cell, z, project)
                    gradient_z :=
                        city_density_sample(field, x, z + cell, project) -
                        city_density_sample(field, x, z - cell, project)
                    if gradient_x * gradient_x + gradient_z * gradient_z > .001 {
                        rotation =
                            f32(math.atan2(f64(gradient_z), f64(gradient_x))) +
                            math.PI * .5 +
                            (city_hash_unit(gx, gz, seed, 10) - .5) * .35
                    }
                }

                structure := terrain.structure_make(x, z, width, depth, 0, height)
                structure.height = height
                structure.kind = .Architecture
                structure.rotation = rotation
                structure.seed = building_seed
                mercantile_frontage := frontage.found && density >= .45 && int((building_seed >> 11) % 8) <= 1
                structure.building = architecture_identity(
                    {
                        tissue = mercantile_frontage ? Context_Tissue.Mercantile : Context_Tissue.Unspecified,
                        density = density,
                        attached = density >= .68,
                        frontage = width,
                        depth = depth,
                        route = frontage.found ? Context_Route.Street : Context_Route.Unspecified,
                        landmark_kind = anchor ? buildings.Landmark_Kind.Campanile : buildings.Landmark_Kind.None,
                        purpose_explicit = false,
                    },
                    building_seed,
                )
                structure.color = architecture_color(structure.seed, anchor)
                if !city_structure_road_clear(&project.road_graph, &structure) do continue
                if !city_structure_site_valid(project, &structure) do continue

                overlaps := false
                for existing in project.structures[:project.structure_count] {
                    if existing.kind == .Architecture &&
                       city_bounds_contains(rebuild_bounds, existing.center_x, existing.center_z) {
                        continue
                    }
                    if city_structure_overlaps(structure, existing) {
                        overlaps = true
                        break
                    }
                }
                if overlaps do continue
                for existing in plan.structures[:plan.count] {
                    if city_structure_overlaps(structure, existing, 1 + (1 - density) * 5) {
                        overlaps = true
                        break
                    }
                }
                if overlaps do continue
                append(&plan.structures, structure)
                plan.count += 1
            }
        }
    }
    return plan
}

city_building_height :: proc(width, depth, density: f32, seed: u32) -> f32 {
    variation := f32(seed & 255) / 255
    height := 9 + density * 42 + variation * (5 + density * 5)

    // Broad footprints are not exclusively multi-storey town blocks. Keep a
    // seed-stable share of them at one façade row so painted towns can also
    // produce workshops, markets, warehouses, and courtyard houses.
    broad_footprint := width >= 22 || width * depth >= 520
    single_floor_variant := ((seed >> 8) & 255) < 112
    if broad_footprint && single_floor_variant {
        // A tall workshop/hall still uses one façade row. Keep its mass just
        // below the two-storey rounding boundary instead of overloading the
        // global height-to-row mapping with an archetype-specific exception.
        return 7.1
    }
    return facade_fitted_height(height)
}

city_plan_add_parcel_building :: proc(
    plan: ^City_Plan,
    project: ^terrain.Project,
    bounds: City_Bounds,
    center_x, center_z, tangent_x, tangent_z, frontage_side, frontage, depth, density: f32,
    seed: u32,
    alley_frontage: bool,
) {
    if plan == nil || project == nil do return
    if density < .08 || !city_bounds_contains(bounds, center_x, center_z) do return
    tangent_length := f32(math.sqrt(f64(tangent_x * tangent_x + tangent_z * tangent_z)))
    if tangent_length <= .001 do return
    tx, tz := tangent_x / tangent_length, tangent_z / tangent_length
    normal_x, normal_z := -tz, tx
    rotation := architecture_frontage_rotation(tx, tz, frontage_side)
    lot_frontage := clamp(frontage, f32(8), f32(32))
    lot_depth := clamp(depth, f32(13), f32(36))
    setback_front := alley_frontage ? f32(1.2) : 1.0 + (1 - density) * 4.0
    setback_side := density > .72 ? f32(.12) : 1.0 + (1 - density) * 2.2
    width := max(terrain.BASE_CELL_SIZE, lot_frontage - setback_side * 2)
    building_depth := max(terrain.BASE_CELL_SIZE, lot_depth - setback_front - (1 - density) * 4)
    height := city_building_height(width, building_depth, density, seed)
    anchor := density > .85 && ((seed >> 8) & 255) > 244
    if anchor do height = 60 + f32((seed >> 16) & 255) / 255 * 14

    structure := terrain.structure_make(center_x, center_z, width, building_depth, 0, height)
    structure.height = height
    structure.kind = .Architecture
    structure.rotation = rotation
    structure.seed = seed
    mercantile_frontage := !alley_frontage && density >= .45 && int((seed >> 11) % 8) <= 1
    structure.building = architecture_identity(
        {
            tissue = mercantile_frontage ? Context_Tissue.Mercantile : Context_Tissue.Unspecified,
            density = density,
            attached = density > .72,
            frontage = width,
            depth = building_depth,
            frontage_side = frontage_side,
            route = alley_frontage ? Context_Route.Alley : Context_Route.Street,
            landmark_kind = anchor ? buildings.Landmark_Kind.Campanile : buildings.Landmark_Kind.None,
            purpose_explicit = false,
        },
        seed,
    )
    structure.color = architecture_color(seed, anchor)
    if !city_structure_road_clear(&project.road_graph, &structure) do return
    if !city_structure_site_valid(project, &structure) do return
    for existing in project.structures[:project.structure_count] {
        if existing.kind == .Architecture && city_bounds_contains(bounds, existing.center_x, existing.center_z) do continue
        if city_structure_overlaps(structure, existing) do return
    }
    separation := density > .72 ? f32(.05) : 1 + (1 - density) * 4
    for existing in plan.structures[:plan.count] {
        if city_structure_overlaps(structure, existing, separation) do return
    }

    half_frontage, half_depth := lot_frontage * .5, lot_depth * .5
    parcel := City_Parcel {
        frontage_width = lot_frontage,
        depth          = lot_depth,
        density        = density,
        seed           = seed,
        alley_frontage = alley_frontage,
    }
    parcel.corners = {
        {center_x - tx * half_frontage - normal_x * half_depth, center_z - tz * half_frontage - normal_z * half_depth},
        {center_x + tx * half_frontage - normal_x * half_depth, center_z + tz * half_frontage - normal_z * half_depth},
        {center_x + tx * half_frontage + normal_x * half_depth, center_z + tz * half_frontage + normal_z * half_depth},
        {center_x - tx * half_frontage + normal_x * half_depth, center_z - tz * half_frontage + normal_z * half_depth},
    }
    append(&plan.parcels, parcel)
    plan.parcel_count += 1
    append(&plan.structures, structure)
    plan.count += 1
}
