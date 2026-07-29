package roads

import "core:math"
import "core:math/linalg"
import "core:slice"

MAX_NODES :: 64
MAX_EDGES :: 128
MAX_JUNCTION_POINTS :: MAX_EDGES * 2
EDGE_LANE_COUNT :: 6
END_CAP_SEGMENTS :: 8
PAVEMENT_QUERY_SEGMENTS :: 12
PAVEMENT_QUERY_LEAF_EDGES :: 4

Vec3 :: [3]f32

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
    // Normalized circulation intensity. One is a maintained, frequently used
    // road; zero is neglected enough for vegetation to reclaim its joints.
    use_intensity:            f32,
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
    Verge,
}

Pavement :: enum u8 {
    Asphalt,
    Gravel,
    Cobblestone,
    Dirt,
}

Pavement_Hit :: struct {
    pavement:   Pavement,
    edge_index: int,
    distance:   f32,
    height:     f32,
    on_surface: bool,
}

Pavement_Query :: struct {
    points:                    [MAX_EDGES][PAVEMENT_QUERY_SEGMENTS + 1]Vec3,
    edge_bounds:               [MAX_EDGES]Pavement_Query_Bounds,
    edge_order:                [MAX_EDGES]int,
    nodes:                     [MAX_EDGES * 2 - 1]Pavement_Query_Node,
    edge_count:                int,
    node_count:                int,
    // Exposed for tests and profiling. This is the number of edge splines
    // whose segments were examined by the most recent query.
    last_candidate_edge_count: int,
}

Pavement_Query_Bounds :: struct {
    min_x, min_z: f32,
    max_x, max_z: f32,
}

Pavement_Query_Node :: struct {
    bounds:       Pavement_Query_Bounds,
    max_radius:   f32,
    first, count: int,
    left, right:  int,
}

Grip_Profile :: struct {
    longitudinal:       f32,
    lateral:            f32,
    rolling_resistance: f32,
}

Roughness_Profile :: struct {
    acceleration:                     f32,
    wavelength, secondary_wavelength: f32,
}

Vertex :: struct {
    position:        Vec3,
    normal:          Vec3,
    uv:              [2]f32,
    surface:         Surface,
    pavement:        Pavement,
    road_half_width: f32,
    use_intensity:   f32,
}

Mesh :: struct {
    vertices: [dynamic]Vertex,
    indices:  [dynamic]u32,
    chunks:   [dynamic]Mesh_Chunk,
}

Mesh_Chunk :: struct {
    first_index: int,
    index_count: int,
}

Edge_Boundaries :: [2][EDGE_LANE_COUNT]u32

Bake_Settings :: struct {
    target_segment_length: f32,
    max_segments_per_edge: int,
    target_chunk_length:   f32,
    min_spans_per_chunk:   int,
    max_spans_per_chunk:   int,
    surface_lift:          f32,
    shoulder_drop:         f32,
}

DEFAULT_BAKE_SETTINGS :: Bake_Settings {
    target_segment_length = 4,
    max_segments_per_edge = 96,
    target_chunk_length   = 40,
    min_spans_per_chunk   = 4,
    max_spans_per_chunk   = 12,
    surface_lift          = .16,
    shoulder_drop         = .08,
}

default_bake_settings :: proc() -> Bake_Settings {
    return DEFAULT_BAKE_SETTINGS
}

add_node :: proc(graph: ^Graph, position: Vec3, junction_radius: f32 = 4, up: Vec3 = {0, 1, 0}) -> int {
    if graph == nil || graph.node_count >= MAX_NODES do return -1
    index := graph.node_count
    ground_normal := linalg.normalize0(up)
    if linalg.dot(ground_normal, ground_normal) <= .000001 do ground_normal = {0, 1, 0}
    graph.nodes[index] = {
        position        = position,
        up              = ground_normal,
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
    use_intensity: f32 = 1,
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
        use_intensity  = clamp(use_intensity, f32(0), f32(1)),
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
    use_intensity: f32 = 1,
) -> int {
    if graph == nil || from < 0 || to < 0 || from >= graph.node_count || to >= graph.node_count do return -1
    start := graph.nodes[from].position
    end := graph.nodes[to].position
    return add_edge(
        graph,
        from,
        to,
        linalg.lerp(start, end, f32(1.0 / 3.0)),
        linalg.lerp(start, end, f32(2.0 / 3.0)),
        width,
        shoulder_width,
        pavement,
        use_intensity,
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

pavement_grip :: proc(pavement: Pavement) -> Grip_Profile {
    switch pavement {
    case .Asphalt:
        return {longitudinal = 1, lateral = 1, rolling_resistance = 1}
    case .Gravel:
        return {longitudinal = .74, lateral = .68, rolling_resistance = 1.18}
    case .Cobblestone:
        return {longitudinal = .86, lateral = .82, rolling_resistance = 1.08}
    case .Dirt:
        return {longitudinal = .62, lateral = .54, rolling_resistance = 1.30}
    }
    return {longitudinal = 1, lateral = 1, rolling_resistance = 1}
}

// Microprofile dimensions are deliberately longer than literal aggregate:
// the vehicle solver samples at 60 Hz, so sub-centimetre detail would alias
// into random impulses at road speed. The two incommensurate waves remain
// deterministic in world space and read as material texture through the
// suspension rather than as camera noise.
pavement_roughness :: proc(pavement: Pavement) -> Roughness_Profile {
    switch pavement {
    case .Asphalt:
        return {acceleration = .06, wavelength = 1.8, secondary_wavelength = .73}
    case .Gravel:
        return {acceleration = .62, wavelength = .82, secondary_wavelength = .37}
    case .Cobblestone:
        return {acceleration = 1.85, wavelength = .64, secondary_wavelength = .29}
    case .Dirt:
        return {acceleration = .88, wavelength = 1.7, secondary_wavelength = .61}
    }
    return {}
}

pavement_bump_acceleration :: proc(pavement: Pavement, x, z, speed: f32) -> f32 {
    profile := pavement_roughness(pavement)
    if profile.acceleration <= 0 || profile.wavelength <= 0 || profile.secondary_wavelength <= 0 do return 0
    speed_response := clamp((math.abs(speed) - .35) / 4.5, 0, 1)
    if speed_response <= 0 do return 0
    primary_distance := x * .83 + z * .56
    secondary_distance := x * -.31 + z * .95
    primary := math.sin(primary_distance * 2 * math.PI / profile.wavelength)
    secondary := math.sin(secondary_distance * 2 * math.PI / profile.secondary_wavelength + 1.17)
    return (primary * .72 + secondary * .28) * profile.acceleration * speed_response
}

offroad_grip :: proc() -> Grip_Profile {
    return {longitudinal = .54, lateral = .46, rolling_resistance = 1.40}
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

@(no_instrumentation)
bezier_point :: #force_inline proc(p0, p1, p2, p3: Vec3, t: f32) -> Vec3 {
    amount := clamp(t, 0, 1)
    u := 1 - amount
    return(
        p0 * (u * u * u) +
        p1 * (3 * u * u * amount) +
        p2 * (3 * u * amount * amount) +
        p3 * (amount * amount * amount) \
    )
}

bezier_tangent :: proc(p0, p1, p2, p3: Vec3, t: f32) -> Vec3 {
    amount := clamp(t, 0, 1)
    u := 1 - amount
    derivative := (p1 - p0) * (3 * u * u) + (p2 - p1) * (6 * u * amount) + (p3 - p2) * (3 * amount * amount)
    tangent := linalg.normalize0(derivative)
    if linalg.dot(tangent, tangent) <= .000001 {
        tangent = linalg.normalize0(p3 - p0)
        if linalg.dot(tangent, tangent) <= .000001 do tangent = {1, 0, 0}
    }
    return tangent
}

@(no_instrumentation)
edge_point :: #force_inline proc(graph: ^Graph, edge: Edge, t: f32) -> Vec3 {
    if graph == nil || edge.from < 0 || edge.to < 0 || edge.from >= graph.node_count || edge.to >= graph.node_count {
        return {}
    }
    return bezier_point(
        graph.nodes[edge.from].position,
        edge.control_from,
        edge.control_to,
        graph.nodes[edge.to].position,
        t,
    )
}

edge_tangent :: proc(graph: ^Graph, edge: Edge, t: f32) -> Vec3 {
    if graph == nil || edge.from < 0 || edge.to < 0 || edge.from >= graph.node_count || edge.to >= graph.node_count {
        return {1, 0, 0}
    }
    return bezier_tangent(
        graph.nodes[edge.from].position,
        edge.control_from,
        edge.control_to,
        graph.nodes[edge.to].position,
        t,
    )
}

pavement_query_bounds_union :: proc(a, b: Pavement_Query_Bounds) -> Pavement_Query_Bounds {
    return {min(a.min_x, b.min_x), min(a.min_z, b.min_z), max(a.max_x, b.max_x), max(a.max_z, b.max_z)}
}

pavement_query_build_node :: proc(graph: ^Graph, query: ^Pavement_Query, first, count: int) -> int {
    node_index := query.node_count
    query.node_count += 1
    node := &query.nodes[node_index]
    node.first = first
    node.count = count
    node.left = -1
    node.right = -1

    first_edge := query.edge_order[first]
    node.bounds = query.edge_bounds[first_edge]
    node.max_radius = graph.edges[first_edge].half_width + graph.edges[first_edge].shoulder_width
    for cursor in first + 1 ..< first + count {
        edge_index := query.edge_order[cursor]
        node.bounds = pavement_query_bounds_union(node.bounds, query.edge_bounds[edge_index])
        node.max_radius = max(
            node.max_radius,
            graph.edges[edge_index].half_width + graph.edges[edge_index].shoulder_width,
        )
    }
    if count <= PAVEMENT_QUERY_LEAF_EDGES do return node_index

    extent_x := node.bounds.max_x - node.bounds.min_x
    extent_z := node.bounds.max_z - node.bounds.min_z
    split_x := extent_x >= extent_z
    // MAX_EDGES is deliberately small, so an in-place insertion sort keeps
    // construction allocation-free without making query-time work linear.
    for cursor in first + 1 ..< first + count {
        edge_index := query.edge_order[cursor]
        edge_bounds := query.edge_bounds[edge_index]
        center := edge_bounds.min_z + edge_bounds.max_z
        if split_x do center = edge_bounds.min_x + edge_bounds.max_x
        insertion := cursor
        for insertion > first {
            other_index := query.edge_order[insertion - 1]
            other_bounds := query.edge_bounds[other_index]
            other_center := other_bounds.min_z + other_bounds.max_z
            if split_x do other_center = other_bounds.min_x + other_bounds.max_x
            if other_center < center || (other_center == center && other_index < edge_index) do break
            query.edge_order[insertion] = other_index
            insertion -= 1
        }
        query.edge_order[insertion] = edge_index
    }

    left_count := count / 2
    node.left = pavement_query_build_node(graph, query, first, left_count)
    node.right = pavement_query_build_node(graph, query, first + left_count, count - left_count)
    return node_index
}

pavement_query_build :: proc(graph: ^Graph, query: ^Pavement_Query) {
    if query == nil do return
    query^ = {}
    if graph == nil do return
    query.edge_count = graph.edge_count
    for edge, edge_index in graph.edges[:graph.edge_count] {
        query.edge_order[edge_index] = edge_index
        for segment in 0 ..= PAVEMENT_QUERY_SEGMENTS {
            query.points[edge_index][segment] = edge_point(graph, edge, f32(segment) / PAVEMENT_QUERY_SEGMENTS)
        }
        first := query.points[edge_index][0]
        bounds := Pavement_Query_Bounds{first.x, first.z, first.x, first.z}
        for point in query.points[edge_index][1:] {
            bounds.min_x = min(bounds.min_x, point.x)
            bounds.min_z = min(bounds.min_z, point.z)
            bounds.max_x = max(bounds.max_x, point.x)
            bounds.max_z = max(bounds.max_z, point.z)
        }
        query.edge_bounds[edge_index] = bounds
    }
    if graph.edge_count > 0 do _ = pavement_query_build_node(graph, query, 0, graph.edge_count)
}

pavement_query_bounds_distance_squared :: #force_inline proc(bounds: Pavement_Query_Bounds, position: Vec3) -> f32 {
    delta_x := max(max(bounds.min_x - position.x, f32(0)), position.x - bounds.max_x)
    delta_z := max(max(bounds.min_z - position.z, f32(0)), position.z - bounds.max_z)
    return delta_x * delta_x + delta_z * delta_z
}

Pavement_Query_State :: struct {
    hit, surface_hit:              Pavement_Hit,
    best_distance_squared:         f32,
    best_surface_distance_squared: f32,
}

pavement_query_node :: proc(
    graph: ^Graph,
    query: ^Pavement_Query,
    node_index: int,
    position: Vec3,
    state: ^Pavement_Query_State,
) {
    node := &query.nodes[node_index]
    bounds_distance_squared := pavement_query_bounds_distance_squared(node.bounds, position)
    radius := node.max_radius
    within_possible_surface :=
        position.x >= node.bounds.min_x - radius &&
        position.x <= node.bounds.max_x + radius &&
        position.z >= node.bounds.min_z - radius &&
        position.z <= node.bounds.max_z + radius
    if bounds_distance_squared > state.best_distance_squared && !within_possible_surface do return

    if node.left >= 0 {
        left_distance := pavement_query_bounds_distance_squared(query.nodes[node.left].bounds, position)
        right_distance := pavement_query_bounds_distance_squared(query.nodes[node.right].bounds, position)
        if right_distance < left_distance {
            pavement_query_node(graph, query, node.right, position, state)
            pavement_query_node(graph, query, node.left, position, state)
        } else {
            pavement_query_node(graph, query, node.left, position, state)
            pavement_query_node(graph, query, node.right, position, state)
        }
        return
    }

    for cursor in node.first ..< node.first + node.count {
        edge_index := query.edge_order[cursor]
        edge := graph.edges[edge_index]
        query.last_candidate_edge_count += 1
        previous := query.points[edge_index][0]
        for segment in 1 ..= PAVEMENT_QUERY_SEGMENTS {
            current := query.points[edge_index][segment]
            segment_x := current.x - previous.x
            segment_z := current.z - previous.z
            length_squared := segment_x * segment_x + segment_z * segment_z
            amount := f32(0)
            if length_squared > .00001 {
                amount = clamp(
                    ((position.x - previous.x) * segment_x + (position.z - previous.z) * segment_z) / length_squared,
                    0,
                    1,
                )
            }
            closest_x := previous.x + segment_x * amount
            closest_y := previous.y + (current.y - previous.y) * amount
            closest_z := previous.z + segment_z * amount
            delta_x := position.x - closest_x
            delta_z := position.z - closest_z
            distance_squared := delta_x * delta_x + delta_z * delta_z
            on_surface :=
                distance_squared <= (edge.half_width + edge.shoulder_width) * (edge.half_width + edge.shoulder_width)
            if distance_squared < state.best_distance_squared ||
               (distance_squared == state.best_distance_squared &&
                       (state.hit.edge_index < 0 || edge_index < state.hit.edge_index)) {
                state.best_distance_squared = distance_squared
                state.hit.pavement = edge.pavement
                state.hit.edge_index = edge_index
                state.hit.height = closest_y
                state.hit.on_surface = on_surface
            }
            // Surface membership is the union of every road corridor. A
            // nearby narrow branch must not make a point on a wider road look
            // off-road merely because that branch has the closest centerline.
            if on_surface &&
               (distance_squared < state.best_surface_distance_squared ||
                       (distance_squared == state.best_surface_distance_squared &&
                               (state.surface_hit.edge_index < 0 || edge_index < state.surface_hit.edge_index))) {
                state.best_surface_distance_squared = distance_squared
                state.surface_hit.pavement = edge.pavement
                state.surface_hit.edge_index = edge_index
                state.surface_hit.height = closest_y
                state.surface_hit.on_surface = true
            }
            previous = current
        }
    }
}

pavement_at_cached :: proc(graph: ^Graph, query: ^Pavement_Query, position: Vec3) -> Pavement_Hit {
    hit := Pavement_Hit {
        edge_index = -1,
        distance   = f32(1e9),
    }
    if graph == nil || query == nil || query.edge_count != graph.edge_count do return hit
    query.last_candidate_edge_count = 0
    state := Pavement_Query_State {
        hit                           = hit,
        surface_hit                   = hit,
        best_distance_squared         = f32(1e18),
        best_surface_distance_squared = f32(1e18),
    }
    if query.node_count > 0 do pavement_query_node(graph, query, 0, position, &state)
    if state.surface_hit.edge_index >= 0 {
        state.surface_hit.distance = f32(math.sqrt(f64(state.best_surface_distance_squared)))
        return state.surface_hit
    }
    if state.hit.edge_index >= 0 do state.hit.distance = f32(math.sqrt(f64(state.best_distance_squared)))
    return state.hit
}

pavement_at :: proc(graph: ^Graph, position: Vec3) -> Pavement_Hit {
    query: Pavement_Query
    pavement_query_build(graph, &query)
    return pavement_at_cached(graph, &query, position)
}

edge_control_polygon_length :: proc(graph: ^Graph, edge: Edge) -> f32 {
    p0 := graph.nodes[edge.from].position
    p3 := graph.nodes[edge.to].position
    return(
        linalg.length(edge.control_from - p0) +
        linalg.length(edge.control_to - edge.control_from) +
        linalg.length(p3 - edge.control_to) \
    )
}

edge_segment_count :: proc(graph: ^Graph, edge: Edge, settings: Bake_Settings) -> int {
    target := max(settings.target_segment_length, f32(.25))
    estimate := edge_control_polygon_length(graph, edge)
    return clamp(int(math.ceil(f64(estimate / target))), 2, max(settings.max_segments_per_edge, 2))
}

node_degree :: proc(graph: ^Graph, node_index: int) -> int {
    if graph == nil || node_index < 0 || node_index >= graph.node_count do return 0
    degree := 0
    for edge in graph.edges[:graph.edge_count] {
        if edge.from == node_index || edge.to == node_index do degree += 1
    }
    return degree
}

mesh_destroy :: proc(mesh: ^Mesh) {
    if mesh == nil do return
    if mesh.vertices != nil do delete(mesh.vertices)
    if mesh.indices != nil do delete(mesh.indices)
    if mesh.chunks != nil do delete(mesh.chunks)
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
    up := linalg.normalize0(linalg.lerp(graph.nodes[edge.from].up, graph.nodes[edge.to].up, t))
    if linalg.dot(up, up) <= .000001 do up = {0, 1, 0}
    side = linalg.normalize0(linalg.cross(up, tangent))
    if linalg.dot(side, side) <= .000001 do side = {-tangent.z, 0, tangent.x}
    normal = linalg.normalize0(linalg.cross(tangent, side))
    if linalg.dot(normal, normal) <= .000001 do normal = up
    return
}

edge_trim_range :: proc(graph: ^Graph, edge: Edge) -> (f32, f32) {
    length := max(edge_control_polygon_length(graph, edge), f32(.001))
    from_trim := f32(0)
    to_trim := f32(0)
    if node_degree(graph, edge.from) > 1 {
        from_trim = min(graph.nodes[edge.from].junction_radius / length, f32(.35))
    }
    if node_degree(graph, edge.to) > 1 {
        to_trim = min(graph.nodes[edge.to].junction_radius / length, f32(.35))
    }
    return from_trim, 1 - to_trim
}

bake_edge :: proc(mesh: ^Mesh, graph: ^Graph, edge: Edge, settings: Bake_Settings) -> Edge_Boundaries {
    boundaries: Edge_Boundaries
    segment_count := edge_segment_count(graph, edge, settings)
    start_t, end_t := edge_trim_range(graph, edge)
    road_width := edge.half_width
    outer_width := road_width + edge.shoulder_width
    verge_width := clamp(edge.shoulder_width * .58, f32(.35), f32(1.25))
    edge_phase :=
        graph.nodes[edge.from].position.x * .031 + graph.nodes[edge.from].position.z * .017 + f32(edge.pavement) * 1.73
    lane_uv := [EDGE_LANE_COUNT]f32{0, .20, .335, .665, .80, 1}
    previous: [EDGE_LANE_COUNT]u32
    distance_along: f32
    previous_center: Vec3
    chunk_first_index := len(mesh.indices)
    chunk_span_count := 0
    chunk_length: f32
    for sample in 0 ..= segment_count {
        fraction := f32(sample) / f32(segment_count)
        t := start_t + (end_t - start_t) * fraction
        center, side, normal := edge_frame(graph, edge, t)
        center = center + normal * settings.surface_lift
        if sample > 0 do distance_along += linalg.length(center - previous_center)
        // A pair of incommensurate waves gives the verge a restrained,
        // hand-shaped silhouette. Only the outer shoulder moves appreciably;
        // the carriageway remains stable for driving and junction welding.
        road_wobble :=
            f32(math.sin(f64(distance_along * .19 + edge_phase))) * min(edge.shoulder_width * .045, f32(.08))
        verge_wobble :=
            f32(math.sin(f64(distance_along * .13 + edge_phase))) * min(edge.shoulder_width * .12, f32(.18)) +
            f32(math.sin(f64(distance_along * .47 + edge_phase * 1.61))) * min(edge.shoulder_width * .055, f32(.08))
        sample_road_width := road_width + road_wobble
        sample_outer_width := outer_width + verge_wobble
        fringe_wobble :=
            f32(math.sin(f64(distance_along * .09 + edge_phase * 2.13))) * min(verge_width * .18, f32(.16)) +
            f32(math.sin(f64(distance_along * .71 + edge_phase * .73))) * min(verge_width * .07, f32(.06))
        sample_fringe_width := sample_outer_width + verge_width + fringe_wobble
        positions := [EDGE_LANE_COUNT]Vec3 {
            center - side * sample_fringe_width - normal * (settings.shoulder_drop * 1.35),
            center - side * sample_outer_width - normal * settings.shoulder_drop,
            center - side * sample_road_width,
            center + side * sample_road_width,
            center + side * sample_outer_width - normal * settings.shoulder_drop,
            center + side * sample_fringe_width - normal * (settings.shoulder_drop * 1.35),
        }
        current: [EDGE_LANE_COUNT]u32
        for lane in 0 ..< EDGE_LANE_COUNT {
            surface := Surface.Road
            if lane == 0 || lane == 5 {
                surface = .Verge
            } else if lane == 1 || lane == 4 {
                surface = .Shoulder
            }
            current[lane] = mesh_vertex(
                mesh,
                {
                    position = positions[lane],
                    normal = normal,
                    uv = {lane_uv[lane], distance_along},
                    surface = surface,
                    pavement = edge.pavement,
                    road_half_width = edge.half_width,
                    use_intensity = edge.use_intensity,
                },
            )
        }
        if sample > 0 {
            chunk_length += linalg.length(center - previous_center)
            for strip in 0 ..< EDGE_LANE_COUNT - 1 {
                mesh_quad(mesh, previous[strip], previous[strip + 1], current[strip + 1], current[strip])
            }
            chunk_span_count += 1
            minimum_spans := max(settings.min_spans_per_chunk, 1)
            maximum_spans := max(settings.max_spans_per_chunk, minimum_spans)
            reached_target :=
                chunk_span_count >= minimum_spans &&
                chunk_length >= max(settings.target_chunk_length, settings.target_segment_length)
            if reached_target || chunk_span_count >= maximum_spans || sample == segment_count {
                append(
                    &mesh.chunks,
                    Mesh_Chunk{first_index = chunk_first_index, index_count = len(mesh.indices) - chunk_first_index},
                )
                chunk_first_index = len(mesh.indices)
                chunk_span_count = 0
                chunk_length = 0
            }
        }
        if sample == 0 {
            boundaries[0] = current
        } else if sample == segment_count {
            boundaries[1] = current
        }
        previous = current
        previous_center = center
    }
    return boundaries
}

Junction_Point :: struct {
    position:       Vec3,
    angle:          f32,
    road_index:     u32,
    shoulder_index: u32,
    verge_index:    u32,
}

junction_add_edge_points :: proc(
    points: ^[MAX_JUNCTION_POINTS]Junction_Point,
    count: ^int,
    mesh: ^Mesh,
    graph: ^Graph,
    edge: Edge,
    boundaries: Edge_Boundaries,
    node_index: int,
) {
    if count^ + 2 > MAX_JUNCTION_POINTS do return
    at_start := edge.from == node_index
    endpoint := at_start ? 0 : 1
    for boundary_index in 0 ..< 2 {
        road_lane := boundary_index + 2
        shoulder_lane := boundary_index == 0 ? 1 : 4
        verge_lane := boundary_index == 0 ? 0 : 5
        road_index := boundaries[endpoint][road_lane]
        // Keep the three profile rings bundled while sorting by the road edge.
        // Matching angular order lets the junction extend the carriageway,
        // shoulder, and feathered verge through the same welded topology.
        point := mesh.vertices[road_index].position
        delta := point - graph.nodes[node_index].position
        points[count^] = {
            position       = point,
            angle          = math.atan2(delta.z, delta.x),
            road_index     = road_index,
            shoulder_index = boundaries[endpoint][shoulder_lane],
            verge_index    = boundaries[endpoint][verge_lane],
        }
        count^ += 1
    }
}

bake_end_cap :: proc(
    mesh: ^Mesh,
    graph: ^Graph,
    edge: Edge,
    boundaries: Edge_Boundaries,
    node_index: int,
    settings: Bake_Settings,
) {
    if mesh == nil || graph == nil do return
    at_start := edge.from == node_index
    endpoint := at_start ? 0 : 1
    boundary := boundaries[endpoint]
    node := graph.nodes[node_index]
    normal := linalg.normalize0(node.up)
    if linalg.dot(normal, normal) <= .000001 do normal = {0, 1, 0}
    center_position := node.position + normal * (settings.surface_lift + .002)
    tangent := edge_tangent(graph, edge, at_start ? 0 : 1)
    outward := at_start ? -tangent : tangent
    left_road := mesh.vertices[boundary[2]].position
    right_road := mesh.vertices[boundary[3]].position
    side := linalg.normalize0(right_road - left_road)
    if linalg.dot(side, side) <= .000001 do side = {0, 0, 1}

    left_road_radius := linalg.length(left_road - center_position)
    right_road_radius := linalg.length(right_road - center_position)
    left_shoulder_radius := linalg.length(mesh.vertices[boundary[1]].position - center_position)
    right_shoulder_radius := linalg.length(mesh.vertices[boundary[4]].position - center_position)
    left_verge_radius := linalg.length(mesh.vertices[boundary[0]].position - center_position)
    right_verge_radius := linalg.length(mesh.vertices[boundary[5]].position - center_position)

    road_arc: [END_CAP_SEGMENTS + 1]u32
    shoulder_arc: [END_CAP_SEGMENTS + 1]u32
    verge_arc: [END_CAP_SEGMENTS + 1]u32
    for sample in 0 ..= END_CAP_SEGMENTS {
        fraction := f32(sample) / f32(END_CAP_SEGMENTS)
        angle := fraction * math.PI
        direction := side * -math.cos(angle) + outward * math.sin(angle)
        if sample == 0 {
            road_arc[sample] = boundary[2]
            shoulder_arc[sample] = boundary[1]
            verge_arc[sample] = boundary[0]
        } else if sample == END_CAP_SEGMENTS {
            road_arc[sample] = boundary[3]
            shoulder_arc[sample] = boundary[4]
            verge_arc[sample] = boundary[5]
        } else {
            road_radius := left_road_radius + (right_road_radius - left_road_radius) * fraction
            shoulder_radius := left_shoulder_radius + (right_shoulder_radius - left_shoulder_radius) * fraction
            verge_radius := left_verge_radius + (right_verge_radius - left_verge_radius) * fraction
            road_arc[sample] = mesh_vertex(
                mesh,
                {
                    position = center_position + direction * road_radius,
                    normal = normal,
                    uv = {.335 + fraction * .33, 0},
                    surface = .Road,
                    pavement = edge.pavement,
                    road_half_width = edge.half_width,
                    use_intensity = edge.use_intensity,
                },
            )
            shoulder_arc[sample] = mesh_vertex(
                mesh,
                {
                    position = center_position + direction * shoulder_radius,
                    normal = normal,
                    uv = {.20 + fraction * .60, 0},
                    surface = .Shoulder,
                    pavement = edge.pavement,
                    road_half_width = edge.half_width,
                    use_intensity = edge.use_intensity,
                },
            )
            verge_arc[sample] = mesh_vertex(
                mesh,
                {
                    position = center_position + direction * verge_radius,
                    normal = normal,
                    uv = {fraction, 0},
                    surface = .Verge,
                    pavement = edge.pavement,
                    road_half_width = edge.half_width,
                    use_intensity = edge.use_intensity,
                },
            )
        }
    }

    center := mesh_vertex(
        mesh,
        {
            position = center_position,
            normal = normal,
            uv = {.5, 0},
            surface = .Junction,
            pavement = edge.pavement,
            road_half_width = edge.half_width,
            use_intensity = edge.use_intensity,
        },
    )
    for segment in 0 ..< END_CAP_SEGMENTS {
        mesh_triangle(mesh, center, road_arc[segment], road_arc[segment + 1])
        mesh_quad(mesh, road_arc[segment], shoulder_arc[segment], shoulder_arc[segment + 1], road_arc[segment + 1])
        mesh_quad(mesh, shoulder_arc[segment], verge_arc[segment], verge_arc[segment + 1], shoulder_arc[segment + 1])
    }
}

bake_junction :: proc(
    mesh: ^Mesh,
    graph: ^Graph,
    edge_boundaries: ^[MAX_EDGES]Edge_Boundaries,
    node_index: int,
    settings: Bake_Settings,
) {
    if node_degree(graph, node_index) == 1 {
        for edge, edge_index in graph.edges[:graph.edge_count] {
            if edge.from == node_index || edge.to == node_index {
                bake_end_cap(mesh, graph, edge, edge_boundaries[edge_index], node_index, settings)
                return
            }
        }
    }
    points: [MAX_JUNCTION_POINTS]Junction_Point
    point_count := 0
    for edge, edge_index in graph.edges[:graph.edge_count] {
        if edge.from == node_index || edge.to == node_index {
            junction_add_edge_points(&points, &point_count, mesh, graph, edge, edge_boundaries[edge_index], node_index)
        }
    }
    if point_count < 2 do return
    slice.stable_sort_by(points[:point_count], proc(a, b: Junction_Point) -> bool { return a.angle < b.angle })
    node := graph.nodes[node_index]
    normal := linalg.normalize0(node.up)
    if linalg.dot(normal, normal) <= .000001 do normal = {0, 1, 0}
    pavement := Pavement.Asphalt
    widest: f32 = -1
    incident_use_sum: f32
    incident_count: int
    for edge in graph.edges[:graph.edge_count] {
        if edge.from == node_index || edge.to == node_index {
            incident_use_sum += edge.use_intensity
            incident_count += 1
            if edge.half_width > widest {
                widest = edge.half_width
                pavement = edge.pavement
            }
        }
    }
    center_position := node.position + normal * (settings.surface_lift + .002)
    center := mesh_vertex(
        mesh,
        {
            position = center_position,
            normal = normal,
            uv = {.5, .5},
            surface = .Junction,
            pavement = pavement,
            road_half_width = max(widest, f32(0)),
            use_intensity = incident_count > 0 ? incident_use_sum / f32(incident_count) : 1,
        },
    )
    for index in 0 ..< point_count {
        next := (index + 1) % point_count
        mesh_triangle(mesh, center, points[index].road_index, points[next].road_index)
        mesh_quad(
            mesh,
            points[index].road_index,
            points[index].shoulder_index,
            points[next].shoulder_index,
            points[next].road_index,
        )
        mesh_quad(
            mesh,
            points[index].shoulder_index,
            points[index].verge_index,
            points[next].verge_index,
            points[next].shoulder_index,
        )
    }
}

bake :: proc(graph: ^Graph, settings: Bake_Settings = DEFAULT_BAKE_SETTINGS) -> Mesh {
    mesh: Mesh
    if graph == nil do return mesh
    mesh.vertices = make([dynamic]Vertex)
    mesh.indices = make([dynamic]u32)
    mesh.chunks = make([dynamic]Mesh_Chunk)
    edge_boundaries: [MAX_EDGES]Edge_Boundaries
    for edge, edge_index in graph.edges[:graph.edge_count] {
        edge_boundaries[edge_index] = bake_edge(&mesh, graph, edge, settings)
    }
    for node_index in 0 ..< graph.node_count {
        first_index := len(mesh.indices)
        bake_junction(&mesh, graph, &edge_boundaries, node_index, settings)
        if len(mesh.indices) > first_index {
            append(&mesh.chunks, Mesh_Chunk{first_index = first_index, index_count = len(mesh.indices) - first_index})
        }
    }
    return mesh
}
