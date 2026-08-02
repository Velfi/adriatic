package architecture
import buildings "../buildings"
import plants "../plants"
import terrain "../terrain"
import "core:math"
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
            width_max: f32 = count == 5 ? 32 : 42
            width := f32(26) + graph_unit(seed, index + 7) * (width_max - f32(26))
            depth := 18 + graph_unit(seed, index + 13) * 10
            height := 18 + graph_unit(seed, index + 19) * 16 + f32(row) * 3 + f32(column % 2) * 2
            x := center_x + cursor + width * f32(.5) + row_offset
            z := center_z - 48 + f32(row) * 43 + jitter_z
            rotation := f32(row - 1) * .03 + graph_noise(seed, index + 23) * .055
            node_add(&graph, .Street_Block, x, z, width, depth, height, rotation)
            cursor += width + frontage_gap
            block_index += 1
        }
    }
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
    structures:   [dynamic]terrain.Structure,
    count:        int,
    parcels:      [dynamic]City_Parcel,
    parcel_count: int,
    alleys:       [dynamic]City_Alley,
    alley_count:  int,
    lamps:        [dynamic]City_Lamp,
    lamp_count:   int,
}
city_plan_destroy :: proc(plan: ^City_Plan) {
    if plan == nil do return
    delete(plan.structures)
    delete(plan.parcels)
    delete(plan.alleys)
    delete(plan.lamps)
    plan^ = {}
}
city_plan_replace :: proc(target: ^City_Plan, source: City_Plan) {
    if target == nil do return
    city_plan_destroy(target)
    target^ = source
}
city_plan_set_region :: proc(plan: ^City_Plan, region: buildings.Region) {
    if plan == nil do return
    for &structure in plan.structures[:plan.count] {
        if structure.kind == .Architecture {
            structure.building.region = region
        }
    }
}
City_Parcel :: struct {
    corners:               [4][2]f32,
    frontage_width, depth: f32,
    density:               f32,
    seed:                  u32,
    attached:              bool,
    alley_frontage:        bool,
}
City_Alley_Terminal :: enum u8 {
    None,
    Door,
    Road,
    Public_Space,
}
City_Alley :: struct {
    start_x, start_z, end_x, end_z: f32,
    half_width:                     f32,
    household_demand:               u16,
    start_terminal, end_terminal:   City_Alley_Terminal,
    curve_control_from:             [2]f32,
    curve_control_to:               [2]f32,
    curve_ready:                    bool,
}
City_Lamp :: struct {
    x, z: f32,
    yaw:  f32,
}
