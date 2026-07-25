package architecture

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
    palette := [4][4]u8{
        {213, 196, 166, 255},
        {218, 188, 151, 255},
        {204, 173, 166, 255},
        {180, 199, 193, 255},
    }
    return palette[int(seed % u32(len(palette)))]
}

architecture_roof_color :: proc(seed: u32, landmark: bool = false) -> [4]u8 {
    if landmark do return {177, 92, 63, 255}
    palette := [4][4]u8{
        {184, 93, 61, 255},
        {196, 108, 68, 255},
        {171, 82, 62, 255},
        {201, 119, 72, 255},
    }
    return palette[int(seed % u32(len(palette)))]
}

architecture_roof_tile_color :: proc(seed: u32, tone: int) -> [4]u8 {
    palette := [4][5][4]u8{
        {
            {201, 105, 70, 255}, {177, 76, 52, 255}, {187, 86, 56, 255},
            {181, 82, 54, 255}, {213, 117, 76, 255},
        },
        {
            {211, 116, 73, 255}, {185, 82, 54, 255}, {198, 96, 59, 255},
            {191, 90, 57, 255}, {220, 130, 80, 255},
        },
        {
            {193, 96, 68, 255}, {166, 70, 54, 255}, {178, 79, 59, 255},
            {172, 75, 57, 255}, {205, 108, 74, 255},
        },
        {
            {216, 124, 75, 255}, {188, 87, 55, 255}, {201, 101, 61, 255},
            {194, 95, 59, 255}, {225, 139, 83, 255},
        },
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
    return clamp(int(height / 11), 2, 4)
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
        structure := terrain.structure_make(
            point.x,
            point.z,
            width,
            depth,
            base_height,
            building_height,
        )
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
        structure := terrain.structure_make(
            node.x,
            node.z,
            node.width,
            node.depth,
            base_height,
            node.height,
        )
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
