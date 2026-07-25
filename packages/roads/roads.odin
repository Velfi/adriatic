package roads

import "core:math"

MAX_NODES :: 64
MAX_EDGES :: 128
MAX_JUNCTION_POINTS :: MAX_EDGES * 2

Vec3 :: struct {
    x, y, z: f32,
}

Node :: struct {
    position:        Vec3,
    up:              Vec3,
    junction_radius: f32,
}

Edge :: struct {
    from, to:                 int,
    control_from, control_to: Vec3,
    half_width:               f32,
    shoulder_width:           f32,
    pavement:                 Pavement,
}

Graph :: struct {
    nodes:      [MAX_NODES]Node,
    node_count: int,
    edges:      [MAX_EDGES]Edge,
    edge_count: int,
}

Surface :: enum u8 {
    Road,
    Shoulder,
    Junction,
}

Pavement :: enum u8 {
    Asphalt,
    Gravel,
    Cobblestone,
    Dirt,
}

Vertex :: struct {
    position: Vec3,
    normal:   Vec3,
    uv:       [2]f32,
    surface:  Surface,
    pavement: Pavement,
}

Mesh :: struct {
    vertices: [dynamic]Vertex,
    indices:  [dynamic]u32,
}

Bake_Settings :: struct {
    target_segment_length: f32,
    max_segments_per_edge: int,
    surface_lift:          f32,
    shoulder_drop:         f32,
}

DEFAULT_BAKE_SETTINGS :: Bake_Settings {
    target_segment_length = 4,
    max_segments_per_edge = 96,
    surface_lift          = .16,
    shoulder_drop         = .08,
}

default_bake_settings :: proc() -> Bake_Settings {
    return DEFAULT_BAKE_SETTINGS
}

vec_add :: proc(a, b: Vec3) -> Vec3 {
    return {a.x + b.x, a.y + b.y, a.z + b.z}
}

vec_sub :: proc(a, b: Vec3) -> Vec3 {
    return {a.x - b.x, a.y - b.y, a.z - b.z}
}

vec_scale :: proc(value: Vec3, scale: f32) -> Vec3 {
    return {value.x * scale, value.y * scale, value.z * scale}
}

vec_dot :: proc(a, b: Vec3) -> f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z
}

vec_cross :: proc(a, b: Vec3) -> Vec3 {
    return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}

vec_length :: proc(value: Vec3) -> f32 {
    return f32(math.sqrt(f64(vec_dot(value, value))))
}

vec_normalize_or :: proc(value, fallback: Vec3) -> Vec3 {
    length := vec_length(value)
    if length <= 0.00001 do return fallback
    return vec_scale(value, 1 / length)
}

lerp_vec :: proc(a, b: Vec3, amount: f32) -> Vec3 {
    return vec_add(a, vec_scale(vec_sub(b, a), amount))
}

add_node :: proc(graph: ^Graph, position: Vec3, junction_radius: f32 = 4, up: Vec3 = {0, 1, 0}) -> int {
    if graph == nil || graph.node_count >= MAX_NODES do return -1
    index := graph.node_count
    graph.nodes[index] = {
        position        = position,
        up              = vec_normalize_or(up, {0, 1, 0}),
        junction_radius = max(junction_radius, f32(0)),
    }
    graph.node_count += 1
    return index
}

add_edge :: proc(
    graph: ^Graph,
    from, to: int,
    control_from, control_to: Vec3,
    width: f32,
    shoulder_width: f32 = 1,
    pavement: Pavement = .Asphalt,
) -> int {
    if graph == nil ||
       graph.edge_count >= MAX_EDGES ||
       from < 0 ||
       to < 0 ||
       from >= graph.node_count ||
       to >= graph.node_count ||
       from == to ||
       width <= 0 {
        return -1
    }
    index := graph.edge_count
    graph.edges[index] = {
        from           = from,
        to             = to,
        control_from   = control_from,
        control_to     = control_to,
        half_width     = width * .5,
        shoulder_width = max(shoulder_width, f32(0)),
        pavement       = pavement,
    }
    graph.edge_count += 1
    return index
}

add_straight_edge :: proc(
    graph: ^Graph,
    from, to: int,
    width: f32,
    shoulder_width: f32 = 1,
    pavement: Pavement = .Asphalt,
) -> int {
    if graph == nil || from < 0 || to < 0 || from >= graph.node_count || to >= graph.node_count do return -1
    start := graph.nodes[from].position
    end := graph.nodes[to].position
    return add_edge(
        graph,
        from,
        to,
        lerp_vec(start, end, f32(1.0 / 3.0)),
        lerp_vec(start, end, f32(2.0 / 3.0)),
        width,
        shoulder_width,
        pavement,
    )
}

pavement_name :: proc(pavement: Pavement) -> string {
    switch pavement {
    case .Asphalt:
        return "ASPHALT"
    case .Gravel:
        return "GRAVEL"
    case .Cobblestone:
        return "COBBLESTONE"
    case .Dirt:
        return "DIRT"
    }
    return "ASPHALT"
}

pavement_next :: proc(pavement: Pavement) -> Pavement {
    switch pavement {
    case .Asphalt:
        return .Gravel
    case .Gravel:
        return .Cobblestone
    case .Cobblestone:
        return .Dirt
    case .Dirt:
        return .Asphalt
    }
    return .Asphalt
}

edge_between :: proc(graph: ^Graph, a, b: int) -> int {
    if graph == nil do return -1
    for edge, index in graph.edges[:graph.edge_count] {
        if (edge.from == a && edge.to == b) || (edge.from == b && edge.to == a) do return index
    }
    return -1
}

remove_edge :: proc(graph: ^Graph, index: int) -> bool {
    if graph == nil || index < 0 || index >= graph.edge_count do return false
    for cursor in index + 1 ..< graph.edge_count {
        graph.edges[cursor - 1] = graph.edges[cursor]
    }
    graph.edge_count -= 1
    graph.edges[graph.edge_count] = {}
    return true
}

remove_node :: proc(graph: ^Graph, index: int) -> bool {
    if graph == nil || index < 0 || index >= graph.node_count do return false
    edge_index := graph.edge_count - 1
    for edge_index >= 0 {
        edge := graph.edges[edge_index]
        if edge.from == index || edge.to == index {
            _ = remove_edge(graph, edge_index)
        }
        edge_index -= 1
    }
    for cursor in index + 1 ..< graph.node_count {
        graph.nodes[cursor - 1] = graph.nodes[cursor]
    }
    graph.node_count -= 1
    graph.nodes[graph.node_count] = {}
    for &edge in graph.edges[:graph.edge_count] {
        if edge.from > index do edge.from -= 1
        if edge.to > index do edge.to -= 1
    }
    return true
}

edge_point :: proc(graph: ^Graph, edge: Edge, t: f32) -> Vec3 {
    if graph == nil || edge.from < 0 || edge.to < 0 || edge.from >= graph.node_count || edge.to >= graph.node_count {
        return {}
    }
    p0 := graph.nodes[edge.from].position
    p1 := edge.control_from
    p2 := edge.control_to
    p3 := graph.nodes[edge.to].position
    amount := clamp(t, 0, 1)
    u := 1 - amount
    return vec_add(
        vec_add(vec_scale(p0, u * u * u), vec_scale(p1, 3 * u * u * amount)),
        vec_add(vec_scale(p2, 3 * u * amount * amount), vec_scale(p3, amount * amount * amount)),
    )
}

edge_tangent :: proc(graph: ^Graph, edge: Edge, t: f32) -> Vec3 {
    if graph == nil || edge.from < 0 || edge.to < 0 || edge.from >= graph.node_count || edge.to >= graph.node_count {
        return {1, 0, 0}
    }
    p0 := graph.nodes[edge.from].position
    p1 := edge.control_from
    p2 := edge.control_to
    p3 := graph.nodes[edge.to].position
    amount := clamp(t, 0, 1)
    u := 1 - amount
    derivative := vec_add(
        vec_add(vec_scale(vec_sub(p1, p0), 3 * u * u), vec_scale(vec_sub(p2, p1), 6 * u * amount)),
        vec_scale(vec_sub(p3, p2), 3 * amount * amount),
    )
    return vec_normalize_or(derivative, vec_normalize_or(vec_sub(p3, p0), {1, 0, 0}))
}

edge_control_polygon_length :: proc(graph: ^Graph, edge: Edge) -> f32 {
    p0 := graph.nodes[edge.from].position
    p3 := graph.nodes[edge.to].position
    return(
        vec_length(vec_sub(edge.control_from, p0)) +
        vec_length(vec_sub(edge.control_to, edge.control_from)) +
        vec_length(vec_sub(p3, edge.control_to)) \
    )
}

edge_segment_count :: proc(graph: ^Graph, edge: Edge, settings: Bake_Settings) -> int {
    target := max(settings.target_segment_length, f32(.25))
    estimate := edge_control_polygon_length(graph, edge)
    return clamp(int(math.ceil(f64(estimate / target))), 2, max(settings.max_segments_per_edge, 2))
}

mesh_destroy :: proc(mesh: ^Mesh) {
    if mesh == nil do return
    if mesh.vertices != nil do delete(mesh.vertices)
    if mesh.indices != nil do delete(mesh.indices)
    mesh^ = {}
}

mesh_vertex :: proc(mesh: ^Mesh, vertex: Vertex) -> u32 {
    index := u32(len(mesh.vertices))
    append(&mesh.vertices, vertex)
    return index
}

mesh_triangle :: proc(mesh: ^Mesh, a, b, c: u32) {
    append(&mesh.indices, a, b, c)
}

mesh_quad :: proc(mesh: ^Mesh, a, b, c, d: u32) {
    mesh_triangle(mesh, a, b, c)
    mesh_triangle(mesh, a, c, d)
}

edge_frame :: proc(graph: ^Graph, edge: Edge, t: f32) -> (center, side, normal: Vec3) {
    center = edge_point(graph, edge, t)
    tangent := edge_tangent(graph, edge, t)
    up := vec_normalize_or(lerp_vec(graph.nodes[edge.from].up, graph.nodes[edge.to].up, t), {0, 1, 0})
    side = vec_normalize_or(vec_cross(up, tangent), {-tangent.z, 0, tangent.x})
    normal = vec_normalize_or(vec_cross(tangent, side), up)
    return
}

edge_trim_range :: proc(graph: ^Graph, edge: Edge) -> (f32, f32) {
    length := max(edge_control_polygon_length(graph, edge), f32(.001))
    from_trim := min(graph.nodes[edge.from].junction_radius / length, f32(.35))
    to_trim := min(graph.nodes[edge.to].junction_radius / length, f32(.35))
    return from_trim, 1 - to_trim
}

bake_edge :: proc(mesh: ^Mesh, graph: ^Graph, edge: Edge, settings: Bake_Settings) -> [2][2]u32 {
    boundaries: [2][2]u32
    segment_count := edge_segment_count(graph, edge, settings)
    start_t, end_t := edge_trim_range(graph, edge)
    road_width := edge.half_width
    outer_width := road_width + edge.shoulder_width
    previous: [4]u32
    distance_along: f32
    previous_center: Vec3
    for sample in 0 ..= segment_count {
        fraction := f32(sample) / f32(segment_count)
        t := start_t + (end_t - start_t) * fraction
        center, side, normal := edge_frame(graph, edge, t)
        center = vec_add(center, vec_scale(normal, settings.surface_lift))
        if sample > 0 do distance_along += vec_length(vec_sub(center, previous_center))
        positions := [4]Vec3 {
            vec_add(vec_sub(center, vec_scale(side, outer_width)), vec_scale(normal, -settings.shoulder_drop)),
            vec_sub(center, vec_scale(side, road_width)),
            vec_add(center, vec_scale(side, road_width)),
            vec_add(vec_add(center, vec_scale(side, outer_width)), vec_scale(normal, -settings.shoulder_drop)),
        }
        current: [4]u32
        for lane in 0 ..< 4 {
            surface := Surface.Road
            if lane == 0 || lane == 3 do surface = .Shoulder
            current[lane] = mesh_vertex(
                mesh,
                {
                    position = positions[lane],
                    normal = normal,
                    uv = {f32(lane) / 3, distance_along},
                    surface = surface,
                    pavement = edge.pavement,
                },
            )
        }
        if sample > 0 {
            mesh_quad(mesh, previous[0], previous[1], current[1], current[0])
            mesh_quad(mesh, previous[1], previous[2], current[2], current[1])
            mesh_quad(mesh, previous[2], previous[3], current[3], current[2])
        }
        if sample == 0 {
            boundaries[0] = {current[1], current[2]}
        } else if sample == segment_count {
            boundaries[1] = {current[1], current[2]}
        }
        previous = current
        previous_center = center
    }
    return boundaries
}

Junction_Point :: struct {
    position: Vec3,
    angle:    f32,
    index:    u32,
}

junction_add_edge_points :: proc(
    points: ^[MAX_JUNCTION_POINTS]Junction_Point,
    count: ^int,
    mesh: ^Mesh,
    graph: ^Graph,
    edge: Edge,
    boundaries: [2][2]u32,
    node_index: int,
) {
    if count^ + 2 > MAX_JUNCTION_POINTS do return
    at_start := edge.from == node_index
    endpoint := at_start ? 0 : 1
    for boundary_index in 0 ..< 2 {
        vertex_index := boundaries[endpoint][boundary_index]
        // The boundary indices refer to vertices already emitted by the edge
        // sweep. Reusing them makes junctions topologically welded rather than
        // merely overlapping duplicate geometry at the seams.
        point := mesh.vertices[vertex_index].position
        delta := vec_sub(point, graph.nodes[node_index].position)
        points[count^] = {
            position = point,
            angle    = math.atan2(delta.z, delta.x),
            index    = vertex_index,
        }
        count^ += 1
    }
}

junction_sort :: proc(points: ^[MAX_JUNCTION_POINTS]Junction_Point, count: int) {
    for index in 1 ..< count {
        value := points[index]
        cursor := index
        for cursor > 0 && points[cursor - 1].angle > value.angle {
            points[cursor] = points[cursor - 1]
            cursor -= 1
        }
        points[cursor] = value
    }
}

bake_junction :: proc(
    mesh: ^Mesh,
    graph: ^Graph,
    edge_boundaries: ^[MAX_EDGES][2][2]u32,
    node_index: int,
    settings: Bake_Settings,
) {
    points: [MAX_JUNCTION_POINTS]Junction_Point
    point_count := 0
    for edge, edge_index in graph.edges[:graph.edge_count] {
        if edge.from == node_index || edge.to == node_index {
            junction_add_edge_points(&points, &point_count, mesh, graph, edge, edge_boundaries[edge_index], node_index)
        }
    }
    if point_count < 2 do return
    junction_sort(&points, point_count)
    node := graph.nodes[node_index]
    normal := vec_normalize_or(node.up, {0, 1, 0})
    pavement := Pavement.Asphalt
    widest: f32 = -1
    for edge in graph.edges[:graph.edge_count] {
        if (edge.from == node_index || edge.to == node_index) && edge.half_width > widest {
            widest = edge.half_width
            pavement = edge.pavement
        }
    }
    center_position := vec_add(node.position, vec_scale(normal, settings.surface_lift + .002))
    center := mesh_vertex(
        mesh,
        {position = center_position, normal = normal, uv = {.5, .5}, surface = .Junction, pavement = pavement},
    )
    if point_count == 2 {
        mesh_triangle(mesh, center, points[0].index, points[1].index)
        return
    }
    for index in 0 ..< point_count {
        next := (index + 1) % point_count
        mesh_triangle(mesh, center, points[index].index, points[next].index)
    }
}

bake :: proc(graph: ^Graph, settings: Bake_Settings = DEFAULT_BAKE_SETTINGS) -> Mesh {
    mesh: Mesh
    if graph == nil do return mesh
    mesh.vertices = make([dynamic]Vertex)
    mesh.indices = make([dynamic]u32)
    edge_boundaries: [MAX_EDGES][2][2]u32
    for edge, edge_index in graph.edges[:graph.edge_count] {
        edge_boundaries[edge_index] = bake_edge(&mesh, graph, edge, settings)
    }
    for node_index in 0 ..< graph.node_count {
        bake_junction(&mesh, graph, &edge_boundaries, node_index, settings)
    }
    return mesh
}
