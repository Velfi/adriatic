package architecture

import roads "../roads"
import terrain "../terrain"
import "core:math"

// A compact geometry-node graph: site -> street blocks -> façades/roofs ->
// landmark. Presentation is kept in the Adriatic renderer.
Node_Kind :: enum {
    Site,
    Street_Block,
    Landmark,
}
Roof_Style :: enum {
    Gable,
    Low_Gable,
    Hip,
    Parapet,
}
Node :: struct {
    kind:                           Node_Kind,
    x, z:                           f32,
    width, depth, height, rotation: f32,
    seed:                           u32,
}
Graph :: struct {
    nodes: [32]Node,
    count: int,
    seed:  u32,
}

architecture_color :: proc(seed: u32, landmark: bool = false) -> [4]u8 {
    if landmark do return {224, 219, 196, 255}
    palette := [4][4]u8{{213, 196, 166, 255}, {218, 188, 151, 255}, {204, 173, 166, 255}, {180, 199, 193, 255}}
    return palette[int(seed % u32(len(palette)))]
}

architecture_roof_color :: proc(seed: u32, landmark: bool = false) -> [4]u8 {
    if landmark do return {177, 92, 63, 255}
    palette := [4][4]u8{{184, 93, 61, 255}, {196, 108, 68, 255}, {171, 82, 62, 255}, {201, 119, 72, 255}}
    return palette[int(seed % u32(len(palette)))]
}

architecture_roof_tile_color :: proc(seed: u32, tone: int) -> [4]u8 {
    palette := [4][5][4]u8 {
        {{201, 105, 70, 255}, {177, 76, 52, 255}, {187, 86, 56, 255}, {181, 82, 54, 255}, {213, 117, 76, 255}},
        {{211, 116, 73, 255}, {185, 82, 54, 255}, {198, 96, 59, 255}, {191, 90, 57, 255}, {220, 130, 80, 255}},
        {{193, 96, 68, 255}, {166, 70, 54, 255}, {178, 79, 59, 255}, {172, 75, 57, 255}, {205, 108, 74, 255}},
        {{216, 124, 75, 255}, {188, 87, 55, 255}, {201, 101, 61, 255}, {194, 95, 59, 255}, {225, 139, 83, 255}},
    }
    tone_index := tone % 5
    if tone_index < 0 do tone_index += 5
    return palette[int(seed % 4)][tone_index]
}

roof_style_for_seed :: proc(seed: u32) -> Roof_Style {
    switch int(seed % 4) {
    case 0:
        return .Gable
    case 1:
        return .Low_Gable
    case 2:
        return .Hip
    case 3:
        return .Parapet
    }
    return .Gable
}

facade_style_for_seed :: proc(seed: u32) -> int {
    // A separate hash prevents roof and façade variants from becoming locked
    // together while keeping the same seed fully reproducible.
    return int((seed ~ 0x9e3779b9) % 4)
}

architecture_has_chimney :: proc(seed: u32) -> bool {
    // Keep chimneys sparse so they punctuate the block silhouette instead of
    // turning every roof into a repetitive row of stacks.
    return seed % 3 == 0
}

facade_floor_count :: proc(height: f32) -> int {
    return clamp(int(math.round(f64(height / 10.5))), 1, 7)
}

Sample_Point :: struct {
    x, z: f32,
}
Poisson_Result :: struct {
    points: [96]Sample_Point,
    count:  int,
}

node_add :: proc(graph: ^Graph, kind: Node_Kind, x, z, width, depth, height, rotation: f32) {
    if graph == nil || graph.count >= len(graph.nodes) do return
    index := graph.count
    graph.nodes[index] = {kind, x, z, width, depth, height, rotation, graph.seed + u32(index * 747796405)}
    graph.count += 1
}

adriatic_graph :: proc(center_x, center_z: f32, seed: u32 = 0xA71D3) -> Graph {
    graph := Graph {
        seed = seed,
    }
    node_add(&graph, .Site, center_x, center_z, 210, 150, 0, -.10)
    // Three slightly irregular street rows create a compact coastal town
    // silhouette without introducing a second graph format. The row count,
    // drift, and frontage scale are all seed-stable so previews never pop.
    block_index := 0
    for row in 0 ..< 3 {
        count := 4
        if ((seed + u32(row * 17)) & 1) != 0 do count = 5
        row_span: f32 = count == 5 ? 196 : 156
        frontage_gap: f32 = 7
        cursor := -row_span * f32(.5)
        row_offset := f32(row - 1) * graph_noise(seed, u32(row) + 31) * 5
        for column in 0 ..< count {
            index := u32(block_index)
            jitter_z := graph_noise(seed, index * 2 + 1) * 2.5
            // Adriatic houses are generally deeper than a single square cell,
            // but their street-facing footprint is still clearly rectangular.
            width_max: f32 = count == 5 ? 32 : 42
            width := f32(26) + graph_unit(seed, index + 7) * (width_max - f32(26))
            depth := 18 + graph_unit(seed, index + 13) * 10
            // Let the rear street climb toward the civic tower so the town
            // keeps a readable stepped skyline instead of a flat roof field.
            height := 18 + graph_unit(seed, index + 19) * 16 + f32(row) * 3 + f32(column % 2) * 2
            x := center_x + cursor + width * f32(.5) + row_offset
            z := center_z - 48 + f32(row) * 43 + jitter_z
            rotation := f32(row - 1) * .03 + graph_noise(seed, index + 23) * .055
            node_add(&graph, .Street_Block, x, z, width, depth, height, rotation)
            cursor += width + frontage_gap
            block_index += 1
        }
    }
    // The civic tower sits on the camera-facing flank, giving the town a clear
    // visual anchor without blocking the façades when the editor camera is pulled back.
    node_add(&graph, .Landmark, center_x + 80, center_z - 68, 22, 22, 75, .04)
    return graph
}

graph_unit :: proc(seed, index: u32) -> f32 {
    value := seed ~ (index * 747796405 + 2891336453)
    value = value * 1664525 + 1013904223
    return f32(value & 0x00ffffff) / f32(0x01000000)
}

graph_noise :: proc(seed, index: u32) -> f32 {
    return graph_unit(seed, index) * 2 - 1
}

random01 :: proc(state: ^u32) -> f32 {
    state^ = state^ * 1664525 + 1013904223
    return f32(state^ & 0x00ffffff) / f32(0x01000000)
}

architecture_footprint_radius :: proc(width, depth: f32) -> f32 {
    half_width, half_depth := width * .5, depth * .5
    return f32(math.sqrt(f64(half_width * half_width + half_depth * half_depth)))
}

City_Bounds :: struct {
    min_x, min_z, max_x, max_z: f32,
    valid:                      bool,
}

City_Plan :: struct {
    structures: [terrain.STRUCTURE_CAPACITY]terrain.Structure,
    count:      int,
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

city_density_index :: proc(x, z: int) -> int {
    return z * terrain.RING_RESOLUTION + x
}

city_density_world_position :: proc(x, z: int) -> (f32, f32) {
    half := f32(terrain.RING_RESOLUTION - 1) * .5
    return (f32(x) - half) * terrain.BASE_CELL_SIZE, (f32(z) - half) * terrain.BASE_CELL_SIZE
}

city_density_sample :: proc(field: ^[terrain.CITY_DENSITY_SAMPLES]u8, world_x, world_z: f32) -> f32 {
    if field == nil do return 0
    half := f32(terrain.RING_RESOLUTION - 1) * .5
    gx := world_x / terrain.BASE_CELL_SIZE + half
    gz := world_z / terrain.BASE_CELL_SIZE + half
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

city_hash :: proc(x, z: int, seed: u32) -> u32 {
    value := seed ~ (u32(i32(x)) * 0x9e3779b9) ~ (u32(i32(z)) * 0x85ebca6b)
    value = (value ~ (value >> 16)) * 0x7feb352d
    value = (value ~ (value >> 15)) * 0x846ca68b
    return value ~ (value >> 16)
}

city_hash_unit :: proc(x, z: int, seed: u32, lane: u32 = 0) -> f32 {
    return f32(city_hash(x, z, seed + lane * 0x9e3779b9) & 0x00ffffff) / f32(0x01000000)
}

city_nearest_road :: proc(
    graph: ^roads.Graph,
    x, z: f32,
) -> (
    found: bool,
    distance, tangent_x, tangent_z, clearance: f32,
) {
    if graph == nil do return
    distance = f32(1.0e20)
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
                if candidate < distance {
                    length := f32(math.sqrt(f64(length_sq)))
                    found, distance = true, candidate
                    tangent_x, tangent_z = vx / length, vz / length
                    clearance = edge.half_width + edge.shoulder_width + 2
                }
            }
            previous = current
        }
    }
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

city_structure_overlaps :: proc(a, b: terrain.Structure, padding: f32 = 1.5) -> bool {
    dx, dz := a.center_x - b.center_x, a.center_z - b.center_z
    minimum :=
        architecture_footprint_radius(a.width, a.depth) + architecture_footprint_radius(b.width, b.depth) + padding
    return dx * dx + dz * dz < minimum * minimum
}

city_accent_site_clear :: proc(
    project: ^terrain.Project,
    x, z, radius: f32,
    padding: f32 = 1.5,
) -> bool {
    if project == nil do return false
    clearance := max(radius + padding, f32(0))
    for structure in project.structures[:project.structure_count] {
        if structure.kind != .Architecture do continue
        dx, dz := x - structure.center_x, z - structure.center_z
        cosine, sine := math.cos(structure.rotation), math.sin(structure.rotation)
        local_x := dx * cosine + dz * sine
        local_z := -dx * sine + dz * cosine
        outside_x := max(math.abs(local_x) - structure.width * .5, f32(0))
        outside_z := max(math.abs(local_z) - structure.depth * .5, f32(0))
        if outside_x * outside_x + outside_z * outside_z < clearance * clearance do return false
    }
    return true
}

city_structure_site_valid :: proc(project: ^terrain.Project, structure: ^terrain.Structure) -> bool {
    if project == nil || structure == nil do return false
    cosine, sine := f32(math.cos(f64(structure.rotation))), f32(math.sin(f64(structure.rotation)))
    highest := f32(-1.0e20)
    lowest := f32(1.0e20)
    points := [5][2]f32 {
        {0, 0},
        {-structure.width * .5, -structure.depth * .5},
        {structure.width * .5, -structure.depth * .5},
        {structure.width * .5, structure.depth * .5},
        {-structure.width * .5, structure.depth * .5},
    }
    for point in points {
        px := structure.center_x + point[0] * cosine - point[1] * sine
        pz := structure.center_z + point[0] * sine + point[1] * cosine
        height := terrain.sample_height(project, 0, px, pz)
        if height <= project.sea_level + .15 do return false
        highest, lowest = max(highest, height), min(lowest, height)
    }
    allowed_relief := max(f32(2.5), min(structure.width, structure.depth) * .12)
    if highest - lowest > allowed_relief do return false
    structure.base_y = highest
    return true
}

city_plan_density :: proc(
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

    // Visit dense candidates first so a full structure budget preserves the
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
                density := city_density_sample(field, x, z)
                if density < .08 || density < band_low || (band < 3 && density >= band_high) do continue
                probability := clamp((density - .05) * 1.08, 0, 1)
                if city_hash_unit(gx, gz, seed, 3) > probability do continue

                compact := density * density
                width := 22 + city_hash_unit(gx, gz, seed, 4) * 15 - compact * 8
                depth := 15 + city_hash_unit(gx, gz, seed, 5) * 11 - compact * 4
                height := 9 + density * 42 + city_hash_unit(gx, gz, seed, 6) * (5 + density * 5)
                anchor := density > .85 && city_hash_unit(gx, gz, seed, 7) > .94
                if anchor do height = 60 + city_hash_unit(gx, gz, seed, 8) * 14
                rotation := (city_hash_unit(gx, gz, seed, 9) - .5) * .65

                found_road, road_distance, tangent_x, tangent_z, road_clearance := city_nearest_road(
                    &project.road_graph,
                    x,
                    z,
                )
                footprint_radius := architecture_footprint_radius(width, depth)
                if found_road && road_distance < road_clearance + footprint_radius do continue
                if found_road && road_distance < 96 {
                    rotation =
                        f32(math.atan2(f64(tangent_z), f64(tangent_x))) + (city_hash_unit(gx, gz, seed, 10) - .5) * .16
                } else {
                    gradient_x := city_density_sample(field, x + cell, z) - city_density_sample(field, x - cell, z)
                    gradient_z := city_density_sample(field, x, z + cell) - city_density_sample(field, x, z - cell)
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
                structure.seed = city_hash(gx, gz, seed)
                structure.color = architecture_color(structure.seed, anchor)
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
                if plan.count >= len(plan.structures) do return plan
                plan.structures[plan.count] = structure
                plan.count += 1
            }
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
    return terrain.sample_height(project, 0, x, z)
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
        radius := architecture_footprint_radius(width, depth)
        overlaps := false
        for existing in project.structures[:project.structure_count] {
            if existing.kind != .Architecture do continue
            dx, dz := point.x - existing.center_x, point.z - existing.center_z
            minimum_distance := radius + architecture_footprint_radius(existing.width, existing.depth) + 1.5
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
        structure.color = architecture_color(structure.seed)
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

generate :: proc(project: ^terrain.Project, center_x, center_z: f32, seed: u32 = 0xA71D3) -> int {
    if project == nil do return 0
    clear_architecture(project)
    graph := adriatic_graph(center_x, center_z, seed)
    created := 0
    for node in graph.nodes[:graph.count] {
        if node.kind == .Site do continue
        base_height := architecture_base_height(project, node.x, node.z)
        if base_height <= project.sea_level do continue
        structure := terrain.structure_make(node.x, node.z, node.width, node.depth, base_height, node.height)
        structure.kind = .Architecture
        structure.rotation = node.rotation
        structure.seed = node.seed
        structure.color = architecture_color(node.seed, node.kind == .Landmark)
        index := terrain.add_structure(project, structure)
        if index >= 0 {
            project.structures[index].seed = node.seed
            project.revision += 1
            created += 1
        }
    }
    return created
}
