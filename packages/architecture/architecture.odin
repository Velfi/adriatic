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
    // Reserve a ground-floor band for entrances and a smaller cornice band,
    // then fill the remaining façade at a human-scale floor pitch.
    usable_height := max(height - 8, f32(0))
    return clamp(int(math.floor(f64(usable_height / 4.8 + .0001))) + 1, 1, 16)
}

facade_window_row_y :: proc(height: f32, row: int) -> f32 {
    rows := facade_floor_count(height)
    if rows <= 1 do return height * .5
    first_y: f32 = 5
    last_y := max(first_y, height - 3)
    clamped_row := clamp(row, 0, rows - 1)
    return first_y + (last_y - first_y) * f32(clamped_row) / f32(rows - 1)
}

facade_column_count :: proc(width: f32) -> int {
    return width >= 28 ? 3 : 2
}

facade_window_width :: proc(width: f32) -> f32 {
    return clamp(width * .13, f32(1.6), f32(2.6))
}

facade_window_height :: proc(height: f32) -> f32 {
    return clamp(height * .06, f32(2.2), f32(3.2))
}

facade_window_column_x :: proc(width: f32, column: int) -> f32 {
    columns := facade_column_count(width)
    window_width := facade_window_width(width)
    spacing := min(width * .42, (width - window_width) / f32(columns))
    return (f32(clamp(column, 0, columns - 1)) - f32(columns - 1) * .5) * spacing
}

architecture_frontage_rotation :: proc(tangent_x, tangent_z, frontage_side: f32) -> f32 {
    rotation := f32(math.atan2(f64(tangent_z), f64(tangent_x)))
    // With local +X along the road tangent, local +Z points along the road's
    // positive normal. Lots on that positive-normal side must turn around so
    // doors, windows, and attached growth face back toward their frontage.
    if frontage_side > 0 do rotation += math.PI
    return rotation
}

bougainvillea_maturity :: proc(growth_density: f32) -> f32 {
    maturity := clamp((growth_density - .035) / (.72 - .035), 0, 1)
    return maturity * maturity * (3 - 2 * maturity)
}

bougainvillea_palette :: proc(seed: u32) -> int {
    // Structure and vine seeds advance through related arithmetic sequences;
    // mix distant bits before selecting a palette so neighboring plants do
    // not become locked to one flower color.
    mixed := city_hash(int(seed & 0x0000ffff), int(seed >> 16), seed ~ 0xa511e9b3)
    return int(mixed % 3)
}

bougainvillea_training_habit :: proc(seed: u32) -> int {
    // Alternate between a balanced wall fan and a dominant wind-swept leader.
    // Hashing avoids locking habit to palette or neighboring seed sequences.
    mixed := city_hash(int(seed & 0x0000ffff), int(seed >> 16), seed ~ 0x6d2b79f5)
    return int(mixed % 2)
}

// Visual regression matrix: every palette/habit pair appears once, with an
// even split between planter-rooted and direct-soil plants.
BOUGAINVILLEA_VALIDATION_SEEDS :: [6]u32{2, 15, 0, 4, 12, 8}

bougainvillea_planter_rooted :: proc(seed: u32) -> bool {
    return seed % 3 != 0
}

bougainvillea_flower_tile_base :: proc(palette: int) -> int {
    switch ((palette % 3) + 3) % 3 {
    case 0:
        return 8 // magenta
    case 1:
        return 4 // coral
    case 2:
        return 12 // violet
    }
    return 8
}

bougainvillea_bract_color :: proc(palette: int) -> [4]u8 {
    switch ((palette % 3) + 3) % 3 {
    case 0:
        return {213, 65, 132, 255} // magenta
    case 1:
        return {226, 100, 86, 255} // coral
    case 2:
        return {144, 65, 190, 255} // violet
    }
    return {213, 65, 132, 255}
}

bougainvillea_bract_value :: proc(maturity, node_fraction: f32, variation: int) -> f32 {
    // Protected, older bracts sit deeper in value while fresh terminal growth
    // catches more light. Keep the range narrow enough to preserve palette
    // identity and the source atlas's internal painted shading.
    age_gradient := clamp(node_fraction, 0, 1)
    maturity_lift := clamp(maturity, 0, 1) * .012
    variation_lift := f32(((variation % 4) + 4) % 4) * .009
    return clamp(.895 + age_gradient * .075 + maturity_lift + variation_lift, .895, 1.01)
}

bougainvillea_active_branch_count :: proc(maturity: f32, available_branches: int) -> int {
    if available_branches <= 0 do return 0
    return min(2 + int(clamp(maturity, 0, 1) * 4.0 + .5), available_branches)
}

bougainvillea_thorn_count :: proc(maturity: f32, available_nodes: int) -> int {
    if available_nodes <= 0 || maturity <= .38 do return 0
    return min(1 + int((clamp(maturity, 0, 1) - .38) * 5.0), available_nodes)
}

bougainvillea_fallen_bract_count :: proc(maturity: f32) -> int {
    if maturity <= .62 do return 0
    return min(2 + int((clamp(maturity, 0, 1) - .62) * 8.0), 5)
}

bougainvillea_cascade_count :: proc(maturity: f32) -> int {
    if maturity <= .56 do return 0
    return maturity < .84 ? 1 : 2
}

bougainvillea_secondary_leader_strength :: proc(maturity: f32) -> f32 {
    strength := clamp((maturity - .46) / .34, 0, 1)
    return strength * strength * (3 - 2 * strength)
}

bougainvillea_woody_compliance :: proc(maturity: f32) -> f32 {
    // Green juvenile leaders follow gusts readily. Lignified, wall-trained
    // trunks retain only a small amount of movement at full maturity.
    return 1 - clamp(maturity, 0, 1) * .86
}

bougainvillea_detail_tier :: proc(camera_distance: f32) -> int {
    // Preserve the trained silhouette throughout the city, but reserve tiny
    // bark, support, and layered-card details for distances where they occupy
    // meaningful screen area.
    if camera_distance < 48 do return 2
    if camera_distance < 112 do return 1
    return 0
}

bougainvillea_crown_detail_fade :: proc(camera_distance: f32) -> f32 {
    // Secondary card layers are fully present through the middle distance,
    // then contract smoothly before the far silhouette-only tier begins.
    fade := clamp((112 - camera_distance) / 24, 0, 1)
    return fade * fade * (3 - 2 * fade)
}

bougainvillea_branch_flowering :: proc(maturity, node_fraction: f32, seed: u32, branch_index: int) -> bool {
    clamped_maturity := clamp(maturity, 0, 1)
    bloom_threshold := .82 - clamped_maturity * .26
    if clamped_maturity <= .16 || node_fraction <= bloom_threshold do return false

    // A fully established plant must not become all-green or uniformly
    // flower-covered because of one unlucky seed. Reserve one sheltered upper
    // branch as foliage and guarantee the terminal leader carries bracts.
    if clamped_maturity > .82 {
        if branch_index == 5 do return true
        resting_branch := 1 + int(city_hash(int(seed & 0xffff), int(seed >> 16), seed ~ 0x91e10da5) % 4)
        if branch_index == resting_branch do return false
    }

    bloom_slots := 1 + int(clamped_maturity * 3.99)
    mixed := city_hash(branch_index, int(seed & 0xffff), seed ~ 0x4f1bbcdc)
    return int(mixed % 5) < bloom_slots
}

bougainvillea_basal_shoot_count :: proc(maturity: f32) -> int {
    if maturity <= .34 do return 0
    return maturity < .78 ? 1 : 2
}

bougainvillea_pruned_stub_count :: proc(maturity: f32) -> int {
    if maturity <= .52 do return 0
    return min(1 + int((clamp(maturity, 0, 1) - .52) * 5.0), 3)
}

bougainvillea_root_attachment_x :: proc(structure: terrain.Structure, preferred_x: f32, seed: u32) -> f32 {
    if structure.kind != .Architecture do return preferred_x
    // Keep the planter or soil pocket outside the central entrance and its
    // immediate approach. Preserve the painted side preference whenever it is
    // already decisive; a seed only breaks an exactly central tie.
    side := preferred_x < 0 ? f32(-1) : f32(1)
    if math.abs(preferred_x) < .001 do side = seed & 1 == 0 ? f32(-1) : f32(1)
    // Compound frontage children can be narrower than the primary mass whose
    // entrance remains visible beside them. Let planters sit just beyond the
    // façade edge beside the plinth, as they commonly do in narrow streets,
    // instead of forcing every root back onto the entrance wall.
    minimum_offset := structure.width * .52
    resolved := side * max(math.abs(preferred_x), minimum_offset)
    return clamp(resolved, -structure.width * .58, structure.width * .58)
}

bougainvillea_height_fraction :: proc(maturity: f32) -> f32 {
    return .24 + clamp(maturity, 0, 1) * .60
}

bougainvillea_density_at_structure :: proc(
    field: ^[terrain.CITY_DENSITY_SAMPLES]u8,
    structure: terrain.Structure,
) -> f32 {
    if field == nil do return 0
    footprint := max(structure.width, structure.depth) * .42
    cosine, sine := f32(math.cos(f64(structure.rotation))), f32(math.sin(f64(structure.rotation)))
    density_sum: f32
    for sample in -2 ..= 2 {
        local_x := f32(sample) * footprint * .52
        local_z := f32((sample + int(structure.seed % 3)) % 3 - 1) * footprint * .16
        sample_x := structure.center_x + local_x * cosine - local_z * sine
        sample_z := structure.center_z + local_x * sine + local_z * cosine
        density_sum += city_density_sample(field, sample_x, sample_z)
    }
    return density_sum / 5
}

bougainvillea_laundry_conflict :: proc(structure: terrain.Structure, growth_density, line_world_y: f32) -> bool {
    if structure.kind != .Architecture || growth_density < .035 do return false
    maturity := bougainvillea_maturity(growth_density)
    if maturity <= .16 do return false
    branch_nodes := [6]int{7, 9, 11, 13, 14, 15}
    active_count := bougainvillea_active_branch_count(maturity, len(branch_nodes))
    lowest_node := branch_nodes[len(branch_nodes) - active_count]
    vine_height := structure.height * bougainvillea_height_fraction(maturity)
    crown_floor := structure.base_y + vine_height * f32(lowest_node) / 15 - .65
    crown_ceiling := structure.base_y + min(vine_height + 2.2, structure.height * .94)
    // Laundry hangs below its support line. Reserve enough room for the
    // deepest cloth panel as well as the line itself.
    laundry_drop: f32 = 1.35
    return line_world_y >= crown_floor && line_world_y - laundry_drop <= crown_ceiling
}

bougainvillea_laundry_span_conflict :: proc(
    structure: terrain.Structure,
    growth_density, line_world_y, start_x, start_z, finish_x, finish_z: f32,
) -> bool {
    if !bougainvillea_laundry_conflict(structure, growth_density, line_world_y) do return false
    facade := architecture_frontage_structure(structure)
    span_x, span_z := finish_x - start_x, finish_z - start_z
    span_length_squared := span_x * span_x + span_z * span_z
    if span_length_squared <= .0001 do return false
    projection := clamp(
        ((facade.center_x - start_x) * span_x + (facade.center_z - start_z) * span_z) / span_length_squared,
        0,
        1,
    )
    closest_x := start_x + span_x * projection
    closest_z := start_z + span_z * projection
    offset_x, offset_z := facade.center_x - closest_x, facade.center_z - closest_z
    // The span endpoint is offset to the façade plane, while center_x/z is
    // the middle of the mass. Include that depth before adding the crown's
    // lateral reach or deep compound masses miss their own laundry anchor.
    crown_radius := facade.depth * .5 + max(facade.width * .42, f32(2.4)) + .55
    return offset_x * offset_x + offset_z * offset_z <= crown_radius * crown_radius
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
    structures:   [terrain.STRUCTURE_CAPACITY]terrain.Structure,
    count:        int,
    parcels:      [terrain.STRUCTURE_CAPACITY]City_Parcel,
    parcel_count: int,
    alleys:       [128]City_Alley,
    alley_count:  int,
}

City_Parcel :: struct {
    corners:               [4][2]f32,
    frontage_width, depth: f32,
    density:               f32,
    seed:                  u32,
    alley_frontage:        bool,
}

City_Alley :: struct {
    start_x, start_z, end_x, end_z: f32,
    half_width:                     f32,
}

Architecture_Mass :: struct {
    local_x, local_z, width, depth, height_scale: f32,
}

Architecture_Footprint :: struct {
    masses: [3]Architecture_Mass,
    count:  int,
}

architecture_footprint :: proc(structure: terrain.Structure) -> Architecture_Footprint {
    result: Architecture_Footprint
    result.masses[0] = {0, 0, structure.width, structure.depth, 1}
    result.count = 1
    if structure.kind != .Architecture || structure.height > 60 do return result
    variant := structure.seed % 5
    if variant == 1 {
        // L plan: a street bar with a shorter rear wing.
        result.masses[0] = {0, -structure.depth * .25, structure.width, structure.depth * .5, 1}
        result.masses[1] = {
            (structure.seed & 1) == 0 ? -structure.width * .31 : structure.width * .31,
            structure.depth * .12,
            structure.width * .38,
            structure.depth * .76,
            .78,
        }
        result.count = 2
    } else if variant == 2 {
        // Stepped plan: two attached bars with unequal depth and height.
        result.masses[0] = {-structure.width * .22, 0, structure.width * .56, structure.depth, 1}
        result.masses[1] = {
            structure.width * .28,
            -structure.depth * .10,
            structure.width * .44,
            structure.depth * .80,
            .72,
        }
        result.count = 2
    } else if variant == 3 && structure.width >= 26 && structure.depth >= 20 {
        // Shallow U plan around a rear court.
        result.masses[0] = {0, -structure.depth * .32, structure.width, structure.depth * .36, 1}
        result.masses[1] = {
            -structure.width * .36,
            structure.depth * .12,
            structure.width * .28,
            structure.depth * .64,
            .72,
        }
        result.masses[2] = {
            structure.width * .36,
            structure.depth * .12,
            structure.width * .28,
            structure.depth * .64,
            .72,
        }
        result.count = 3
    }
    return result
}

architecture_frontage_mass_index :: proc(structure: terrain.Structure) -> int {
    footprint := architecture_footprint(structure)
    if footprint.count <= 1 do return 0
    best_index := 0
    best_front := f32(-1.0e20)
    for mass, mass_index in footprint.masses[:footprint.count] {
        // Architecture façades are rendered on +local-Z. Choose the mass
        // whose front plane reaches farthest in that direction so attached
        // details remain visible instead of landing behind a projecting wing.
        front := mass.local_z + mass.depth * .5
        if front > best_front {
            best_front = front
            best_index = mass_index
        }
    }
    return best_index
}

architecture_frontage_structure :: proc(structure: terrain.Structure) -> terrain.Structure {
    result := structure
    if structure.kind != .Architecture do return result
    footprint := architecture_footprint(structure)
    if footprint.count <= 1 do return result
    frontage_index := architecture_frontage_mass_index(structure)
    frontage_mass := footprint.masses[frontage_index]
    result.center_x, result.center_z = architecture_mass_world(structure, frontage_mass)
    result.width = frontage_mass.width
    result.depth = frontage_mass.depth
    result.height = max(terrain.BASE_CELL_SIZE, structure.height * frontage_mass.height_scale)
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

city_density_index :: proc(x, z: int) -> int {
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

architecture_mass_world :: proc(structure: terrain.Structure, mass: Architecture_Mass) -> (x, z: f32) {
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
    dx, dz := bx - ax, bz - az
    ac, as := f32(math.cos(f64(a.rotation))), f32(math.sin(f64(a.rotation)))
    bc, bs := f32(math.cos(f64(b.rotation))), f32(math.sin(f64(b.rotation)))
    axes := [4][2]f32{{ac, as}, {-as, ac}, {bc, bs}, {-bs, bc}}
    for axis in axes {
        distance := math.abs(dx * axis[0] + dz * axis[1])
        ar :=
            am.width * .5 * math.abs(ac * axis[0] + as * axis[1]) +
            am.depth * .5 * math.abs(-as * axis[0] + ac * axis[1])
        br :=
            bm.width * .5 * math.abs(bc * axis[0] + bs * axis[1]) +
            bm.depth * .5 * math.abs(-bs * axis[0] + bc * axis[1])
        if distance >= ar + br + padding do return false
    }
    return true
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
    cosine, sine := f32(math.cos(f64(structure.rotation))), f32(math.sin(f64(structure.rotation)))
    highest := f32(-1.0e20)
    lowest := f32(1.0e20)
    footprint := architecture_footprint(structure^)
    for mass in footprint.masses[:footprint.count] {
        points := [5][2]f32 {
            {mass.local_x, mass.local_z},
            {mass.local_x - mass.width * .5, mass.local_z - mass.depth * .5},
            {mass.local_x + mass.width * .5, mass.local_z - mass.depth * .5},
            {mass.local_x + mass.width * .5, mass.local_z + mass.depth * .5},
            {mass.local_x - mass.width * .5, mass.local_z + mass.depth * .5},
        }
        for point in points {
            px := structure.center_x + point[0] * cosine - point[1] * sine
            pz := structure.center_z + point[0] * sine + point[1] * cosine
            height := terrain.sample_height(project, 0, px, pz)
            if height <= project.sea_level + .15 do return false
            highest, lowest = max(highest, height), min(lowest, height)
        }
    }
    allowed_relief := max(f32(2.5), min(structure.width, structure.depth) * .12)
    if highest - lowest > allowed_relief do return false
    structure.base_y = highest
    return true
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
                if plan.count >= len(plan.structures) do return plan
                plan.structures[plan.count] = structure
                plan.count += 1
            }
        }
    }
    return plan
}

city_plan_add_parcel_building :: proc(
    plan: ^City_Plan,
    project: ^terrain.Project,
    bounds: City_Bounds,
    center_x, center_z, tangent_x, tangent_z, frontage_side, frontage, depth, density: f32,
    seed: u32,
    alley_frontage: bool,
) {
    if plan == nil || project == nil || plan.count >= len(plan.structures) do return
    if density < .08 || !city_bounds_contains(bounds, center_x, center_z) do return
    tangent_length := f32(math.sqrt(f64(tangent_x * tangent_x + tangent_z * tangent_z)))
    if tangent_length <= .001 do return
    tx, tz := tangent_x / tangent_length, tangent_z / tangent_length
    normal_x, normal_z := -tz, tx
    rotation := architecture_frontage_rotation(tx, tz, frontage_side)
    lot_frontage := clamp(frontage, f32(8), f32(20))
    lot_depth := clamp(depth, f32(13), f32(36))
    setback_front := alley_frontage ? f32(1.2) : 1.0 + (1 - density) * 4.0
    setback_side := density > .72 ? f32(.12) : 1.0 + (1 - density) * 2.2
    width := max(terrain.BASE_CELL_SIZE, lot_frontage - setback_side * 2)
    building_depth := max(terrain.BASE_CELL_SIZE, lot_depth - setback_front - (1 - density) * 4)
    height := 9 + density * 42 + f32(seed & 255) / 255 * (5 + density * 5)
    anchor := density > .85 && ((seed >> 8) & 255) > 244
    if anchor do height = 60 + f32((seed >> 16) & 255) / 255 * 14

    structure := terrain.structure_make(center_x, center_z, width, building_depth, 0, height)
    structure.height = height
    structure.kind = .Architecture
    structure.rotation = rotation
    structure.seed = seed
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

    if plan.parcel_count < len(plan.parcels) {
        half_frontage, half_depth := lot_frontage * .5, lot_depth * .5
        parcel := City_Parcel {
            frontage_width = lot_frontage,
            depth          = lot_depth,
            density        = density,
            seed           = seed,
            alley_frontage = alley_frontage,
        }
        parcel.corners = {
            {
                center_x - tx * half_frontage - normal_x * half_depth,
                center_z - tz * half_frontage - normal_z * half_depth,
            },
            {
                center_x + tx * half_frontage - normal_x * half_depth,
                center_z + tz * half_frontage - normal_z * half_depth,
            },
            {
                center_x + tx * half_frontage + normal_x * half_depth,
                center_z + tz * half_frontage + normal_z * half_depth,
            },
            {
                center_x - tx * half_frontage + normal_x * half_depth,
                center_z - tz * half_frontage + normal_z * half_depth,
            },
        }
        plan.parcels[plan.parcel_count] = parcel
        plan.parcel_count += 1
    }
    plan.structures[plan.count] = structure
    plan.count += 1
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
                        density := city_density_sample(field, probe_x, probe_z)
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

                        // Deep paint receives a narrow alley normal to the main
                        // street. Lots then front both sides of that alley.
                        deep_density := city_density_sample(
                            field,
                            current.x + normal_x * side * (edge.half_width + edge.shoulder_width + 62),
                            current.z + normal_z * side * (edge.half_width + edge.shoulder_width + 62),
                        )
                        if deep_density > .18 && (lot_seed & 7) == 0 && plan.alley_count < len(plan.alleys) {
                            alley_start := edge.half_width + edge.shoulder_width + 3
                            alley_length := 62 + deep_density * 22
                            alley := City_Alley {
                                start_x    = current.x + normal_x * side * alley_start,
                                start_z    = current.z + normal_z * side * alley_start,
                                end_x      = current.x + normal_x * side * (alley_start + alley_length),
                                end_z      = current.z + normal_z * side * (alley_start + alley_length),
                                half_width = 2.2,
                            }
                            plan.alleys[plan.alley_count] = alley
                            plan.alley_count += 1
                            for alley_step in 0 ..< 3 {
                                along := 22 + f32(alley_step) * 18
                                alley_x := alley.start_x + normal_x * side * along
                                alley_z := alley.start_z + normal_z * side * along
                                for alley_side_index in 0 ..< 2 {
                                    alley_side := alley_side_index == 0 ? f32(-1) : f32(1)
                                    lot_normal_x, lot_normal_z := -normal_z * side, normal_x * side
                                    alley_lot_depth := 14 + deep_density * 8
                                    alley_center_offset := alley.half_width + 1.2 + alley_lot_depth * .5
                                    bx := alley_x + lot_normal_x * alley_side * alley_center_offset
                                    bz := alley_z + lot_normal_z * alley_side * alley_center_offset
                                    bd := city_density_sample(field, bx, bz)
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
                        }
                    }
                    lot_cursor = 0
                    next_frontage = 10 + city_hash_unit(edge_index, int(accumulated), seed, 32) * 8
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
