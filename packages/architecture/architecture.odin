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
    for row in 0 ..< 3 {
        for column in 0 ..< 4 {
            jitter_x := f32(math.sin(f64(f32(row * 13 + column * 7) + f32(seed) * .01))) * 4
            jitter_z := f32(math.cos(f64(f32(row * 9 + column * 5) + f32(seed) * .013))) * 3
            x := center_x - 67 + f32(column) * 44 + jitter_x
            z := center_z - 48 + f32(row) * 43 + jitter_z
            width := 30 + f32((row + column) % 2) * 9
            depth := 25 + f32((row * 2 + column) % 3) * 5
            height := 19 + f32((row + column) % 3) * 6 + f32(column) * 1.5
            node_add(&graph, .Street_Block, x, z, width, depth, height, -.08 + f32(column % 2) * .14)
        }
    }
    node_add(&graph, .Landmark, center_x + 77, center_z + 50, 22, 22, 75, .04)
    return graph
}

generate :: proc(project: ^terrain.Project, center_x, center_z: f32, seed: u32 = 0xA71D3) -> int {
    if project == nil do return 0
    for index := project.structure_count - 1; index >= 0; index -= 1 {
        if project.structures[index].kind == .Architecture do terrain.remove_structure(project, index)
    }
    graph := adriatic_graph(center_x, center_z, seed)
    created := 0
    for node in graph.nodes[:graph.count] {
        if node.kind == .Site do continue
        structure := terrain.structure_make(
            node.x,
            node.z,
            node.width,
            node.depth,
            terrain.sample_height(project, 0, node.x, node.z),
            node.height,
        )
        structure.kind = .Architecture
        structure.rotation = node.rotation
        structure.seed = node.seed
        structure.color = node.kind == .Landmark ? [4]u8{224, 219, 196, 255} : [4]u8{214, 199, 170, 255}
        if terrain.add_structure(project, structure) >= 0 do created += 1
    }
    return created
}
