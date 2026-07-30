package boats

// NPC boats are authored in metres, at real-world scale. Each class returns
// one combined triangle mesh: hull, deck furniture, rig and working gear stay
// in the same draw-ready object rather than becoming a hierarchy of meshes.

Class :: enum u8 {
    Motor,
    Sail,
    Fishing,
    Tug,
    Dinghy,
}

Part :: enum u8 {
    Hull,
    Deck,
    Cabin,
    Glass,
    Metal,
    Sail,
    Accent,
    Tire,
}

Specifications :: struct {
    length:              f32,
    beam:                f32,
    draft:               f32,
    height_or_clearance: f32,
    cruise_speed_mps:    f32,
    displacement_kg:     f32,
    engine_power_kw:     f32,
}

@(no_instrumentation)
specifications :: #force_inline proc(class: Class) -> Specifications {
    switch class {
    case .Dinghy:
        // A small rigid-hulled harbor tender for one or two mice.
        return {3.10, 1.35, .22, .72, 3.40, 145, 6}
    case .Motor:
        // Boston Whaler 210 Vantage hull: 6.5 m long, 2.6 m beam.
        return {6.50, 2.60, .48, 1.50, 9.25, 2214, 186}
    case .Sail:
        // Beneteau First 27: 7.99 m LOA, 2.54 m beam, 1.7 m draft,
        // and 12.2 m bridge clearance.
        return {7.99, 2.54, 1.70, 12.20, 3.10, 1770, 11.2}
    case .Fishing:
        // Parker 2520 XL Sport Cabin: 25'4" hull, 9'6" beam, 15" draft.
        return {7.72, 2.90, .38, 2.55, 5.65, 2404, 224}
    case .Tug:
        // Robert Allan RApport 2500 Hercules: 24.99 m LOA, 12.19 m
        // moulded beam, 5.18 m maximum draft.
        return {24.99, 12.19, 5.18, 9.20, 4.60, 350000, 4480}
    }
    return {}
}

class_name :: proc(class: Class) -> string {
    switch class {
    case .Dinghy:
        return "DINGHY"
    case .Motor:
        return "MOTOR BOAT"
    case .Sail:
        return "SAILBOAT"
    case .Fishing:
        return "FISHING BOAT"
    case .Tug:
        return "TUGBOAT"
    }
    return "BOAT"
}

Vertex :: struct {
    position: [3]f32,
    part:     Part,
}

Triangle :: struct {
    a, b, c: u16,
}

MESH_VERTEX_CAPACITY :: 1536
MESH_TRIANGLE_CAPACITY :: 512

Mesh :: struct {
    vertices:       [MESH_VERTEX_CAPACITY]Vertex,
    triangles:      [MESH_TRIANGLE_CAPACITY]Triangle,
    vertex_count:   int,
    triangle_count: int,
}

mesh_cache: [len(Class)]Mesh
mesh_cache_ready: [len(Class)]bool

vertices :: proc(mesh: ^Mesh) -> []Vertex {
    if mesh == nil do return nil
    return mesh.vertices[:mesh.vertex_count]
}

triangles :: proc(mesh: ^Mesh) -> []Triangle {
    if mesh == nil do return nil
    return mesh.triangles[:mesh.triangle_count]
}

@(no_instrumentation)
triangle :: #force_inline proc(mesh: ^Mesh, a, b, c: [3]f32, part: Part) {
    if mesh == nil || mesh.vertex_count + 3 > len(mesh.vertices) || mesh.triangle_count >= len(mesh.triangles) {
        return
    }
    first := mesh.vertex_count
    mesh.vertices[first + 0] = {a, part}
    mesh.vertices[first + 1] = {b, part}
    mesh.vertices[first + 2] = {c, part}
    mesh.triangles[mesh.triangle_count] = {u16(first), u16(first + 1), u16(first + 2)}
    mesh.vertex_count += 3
    mesh.triangle_count += 1
}

@(no_instrumentation)
quad :: #force_inline proc(mesh: ^Mesh, a, b, c, d: [3]f32, part: Part) {
    triangle(mesh, a, b, c, part)
    triangle(mesh, a, c, d, part)
}

// hull_end_cap closes the five-sided cross-section formed by the deck corners,
// chine points and lowered keel center. Boundary points must stay in the order
// seen from outside the hull; reverse_winding selects the +Z stern face.
hull_end_cap :: proc(mesh: ^Mesh, z, half_width, freeboard, chine_y, keel_y: f32, reverse_winding: bool, part: Part) {
    boundary := [5][3]f32 {
        {-half_width, freeboard, z},
        {half_width, freeboard, z},
        {half_width, chine_y, z},
        {0, keel_y, z},
        {-half_width, chine_y, z},
    }
    center := [3]f32{0, (freeboard + chine_y + keel_y) / 3, z}
    for index in 0 ..< len(boundary) {
        next := (index + 1) % len(boundary)
        if reverse_winding {
            triangle(mesh, center, boundary[next], boundary[index], part)
        } else {
            triangle(mesh, center, boundary[index], boundary[next], part)
        }
    }
}

box :: proc(mesh: ^Mesh, center, size: [3]f32, part: Part) {
    x, y, z := size[0] * .5, size[1] * .5, size[2] * .5
    p := [8][3]f32 {
        {center[0] - x, center[1] - y, center[2] - z},
        {center[0] + x, center[1] - y, center[2] - z},
        {center[0] + x, center[1] + y, center[2] - z},
        {center[0] - x, center[1] + y, center[2] - z},
        {center[0] - x, center[1] - y, center[2] + z},
        {center[0] + x, center[1] - y, center[2] + z},
        {center[0] + x, center[1] + y, center[2] + z},
        {center[0] - x, center[1] + y, center[2] + z},
    }
    quad(mesh, p[0], p[3], p[2], p[1], part)
    quad(mesh, p[4], p[5], p[6], p[7], part)
    quad(mesh, p[0], p[4], p[7], p[3], part)
    quad(mesh, p[1], p[2], p[6], p[5], part)
    quad(mesh, p[3], p[7], p[6], p[2], part)
    quad(mesh, p[0], p[1], p[5], p[4], part)
}

// hull adds one closed, faceted monohull. It faces -Z; the forward station is
// narrow and high, while the stern remains broad enough to read at distance.
hull :: proc(mesh: ^Mesh, spec: Specifications, freeboard: f32, part := Part.Hull) {
    half_l, half_b := spec.length * .5, spec.beam * .5
    stations := [5]f32{-half_l, -half_l * .63, 0, half_l * .72, half_l}
    widths := [5]f32{.08, .82, 1, .94, .72}
    keels := [5]f32{-.35, -spec.draft, -spec.draft, -spec.draft * .82, -spec.draft * .55}
    for index in 0 ..< 4 {
        next := index + 1
        z0, z1 := stations[index], stations[next]
        w0, w1 := half_b * widths[index], half_b * widths[next]
        top_y := freeboard
        // Port, starboard, deck and two bottom facets.
        quad(mesh, {-w0, keels[index], z0}, {-w1, keels[next], z1}, {-w1, top_y, z1}, {-w0, top_y, z0}, part)
        quad(mesh, {w0, keels[index], z0}, {w0, top_y, z0}, {w1, top_y, z1}, {w1, keels[next], z1}, part)
        quad(mesh, {-w0, top_y, z0}, {-w1, top_y, z1}, {w1, top_y, z1}, {w0, top_y, z0}, .Deck)
        triangle(
            mesh,
            {-w0, keels[index], z0},
            {0, keels[index] - spec.draft * .08, z0},
            {0, keels[next] - spec.draft * .08, z1},
            part,
        )
        triangle(mesh, {-w0, keels[index], z0}, {0, keels[next] - spec.draft * .08, z1}, {-w1, keels[next], z1}, part)
        triangle(
            mesh,
            {w0, keels[index], z0},
            {0, keels[next] - spec.draft * .08, z1},
            {0, keels[index] - spec.draft * .08, z0},
            part,
        )
        triangle(mesh, {w0, keels[index], z0}, {w1, keels[next], z1}, {0, keels[next] - spec.draft * .08, z1}, part)
    }
    // Close both five-sided ends with outward-facing winding.
    bow_width := half_b * widths[0]
    bow_keel := keels[0]
    hull_end_cap(mesh, stations[0], bow_width, freeboard, bow_keel, bow_keel - spec.draft * .08, false, part)
    stern_width := half_b * widths[4]
    stern_keel := keels[4]
    hull_end_cap(mesh, stations[4], stern_width, freeboard, stern_keel, stern_keel - spec.draft * .08, true, part)
}

motor_mesh :: proc() -> Mesh {
    mesh: Mesh
    spec := specifications(.Motor)
    hull(&mesh, spec, .58)
    box(&mesh, {0, .76, .32}, {1.72, .34, 2.18}, .Accent)
    box(&mesh, {0, 1.06, -.12}, {1.58, .56, .08}, .Glass)
    box(&mesh, {0, .50, 2.86}, {.72, .92, .38}, .Metal)
    return mesh
}

dinghy_mesh :: proc() -> Mesh {
    mesh: Mesh
    spec := specifications(.Dinghy)
    hull(&mesh, spec, .34)
    // The shared hull is watertight, so a dark recessed cockpit laid just over
    // its deck gives this tiny boat a readable open interior without requiring
    // a second hull topology.
    box(&mesh, {0, .355, .08}, {1.00, .025, 1.92}, .Tire)

    // Raised gunwales, a short foredeck and broad timber thwarts give the
    // tender a useful small-craft silhouette at gameplay camera distances.
    box(&mesh, {-.585, .395, .10}, {.075, .10, 2.22}, .Accent)
    box(&mesh, {.585, .395, .10}, {.075, .10, 2.22}, .Accent)
    box(&mesh, {0, .395, -1.16}, {.72, .10, .34}, .Accent)
    box(&mesh, {0, .49, -.46}, {1.12, .13, .25}, .Deck)
    box(&mesh, {0, .49, .48}, {1.12, .13, .25}, .Deck)

    // A two-piece outboard with a visible tiller reads more clearly than one
    // metal block, while the bow cleat gives the harbor tender a working detail.
    box(&mesh, {0, .57, 1.43}, {.28, .46, .22}, .Metal)
    box(&mesh, {0, .82, 1.40}, {.38, .18, .30}, .Accent)
    box(&mesh, {-.25, .80, 1.24}, {.34, .055, .055}, .Metal)
    box(&mesh, {0, .52, -1.30}, {.08, .16, .20}, .Metal)
    return mesh
}

sail_mesh :: proc() -> Mesh {
    mesh: Mesh
    spec := specifications(.Sail)
    hull(&mesh, spec, .62)
    box(&mesh, {0, .85, .74}, {1.55, .46, 1.95}, .Cabin)
    mast_height := spec.height_or_clearance - spec.draft
    box(&mesh, {0, .62 + mast_height * .5, -.35}, {.10, mast_height, .10}, .Metal)
    boom_y := f32(1.82)
    box(&mesh, {0, boom_y, 1.02}, {.08, .08, 2.75}, .Metal)
    mast_top := .62 + mast_height
    // Double-sided mainsail and jib remain part of this one combined mesh.
    triangle(&mesh, {0, boom_y, -.28}, {0, mast_top - .55, -.28}, {0, boom_y, 2.28}, .Sail)
    triangle(&mesh, {0, boom_y, 2.28}, {0, mast_top - .55, -.28}, {0, boom_y, -.28}, .Sail)
    triangle(&mesh, {0, boom_y, -.42}, {0, mast_top * .69, -.42}, {0, boom_y, -3.34}, .Accent)
    triangle(&mesh, {0, boom_y, -3.34}, {0, mast_top * .69, -.42}, {0, boom_y, -.42}, .Accent)
    return mesh
}

fishing_mesh :: proc() -> Mesh {
    mesh: Mesh
    spec := specifications(.Fishing)
    hull(&mesh, spec, .64)
    box(&mesh, {0, 1.30, -.30}, {2.32, 1.32, 2.45}, .Cabin)
    box(&mesh, {0, 1.55, -1.55}, {2.10, .56, .08}, .Glass)
    box(&mesh, {0, 2.08, -.25}, {2.52, .10, 2.72}, .Deck)
    supports := [2]f32{-1.06, 1.06}
    for x in supports {
        box(&mesh, {x, 2.80, .25}, {.07, 1.52, .07}, .Metal)
    }
    box(&mesh, {0, 3.52, .25}, {2.20, .07, .07}, .Metal)
    return mesh
}

tug_mesh :: proc() -> Mesh {
    mesh: Mesh
    spec := specifications(.Tug)
    hull(&mesh, spec, 1.52)
    box(&mesh, {0, 2.42, .65}, {8.35, 1.80, 8.15}, .Cabin)
    box(&mesh, {0, 4.14, -.58}, {6.85, 1.64, 4.62}, .Cabin)
    box(&mesh, {0, 4.45, -2.92}, {6.30, .82, .10}, .Glass)
    box(&mesh, {0, 5.30, -.58}, {7.15, .12, 4.95}, .Deck)
    box(&mesh, {0, 7.16, -.30}, {.20, 3.72, .20}, .Metal)
    box(&mesh, {0, 8.58, -.30}, {4.65, .15, .15}, .Metal)
    box(&mesh, {0, 1.84, -9.45}, {7.15, .54, 1.42}, .Tire)
    box(&mesh, {0, 1.84, 10.20}, {7.15, .54, 1.42}, .Tire)
    return mesh
}

mesh :: proc(class: Class) -> Mesh {
    switch class {
    case .Dinghy:
        return dinghy_mesh()
    case .Motor:
        return motor_mesh()
    case .Sail:
        return sail_mesh()
    case .Fishing:
        return fishing_mesh()
    case .Tug:
        return tug_mesh()
    }
    return {}
}

// NPC boat geometry is immutable after construction. Rendering used to rebuild
// and return the entire fixed-capacity mesh for every visible boat, every
// frame. Keep one canonical mesh per class and let callers borrow it instead.
@(no_instrumentation)
cached_mesh :: proc(class: Class) -> ^Mesh {
    index := int(class)
    if index < 0 || index >= len(mesh_cache) do return nil
    if !mesh_cache_ready[index] {
        mesh_cache[index] = mesh(class)
        mesh_cache_ready[index] = true
    }
    return &mesh_cache[index]
}
