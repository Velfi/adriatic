// Package leaf_mesh generates small, renderer-independent leaf meshes.
package leaf_mesh

import "core:math"
import "core:math/linalg"

Shape :: enum u8 {
    Elliptic,
    Lanceolate,
    Ovate,
    Cordate,
    Deltoid,
    Lobed,
    Fig,
    Grapevine,
    Ivy,
    Cypress_Spray,
}

SHAPE_COUNT :: int(Shape.Cypress_Spray) + 1

Config :: struct {
    shape:     Shape,
    length:    f32,
    width:     f32,
    segments:  int,
    serration: f32,
    curl:      f32,
    cup:       f32,
    stem:      f32,
}

Vertex :: struct {
    position: [3]f32,
    normal:   [3]f32,
    uv:       [2]f32,
}

MAX_SEGMENTS :: 48
MAX_VERTICES :: (MAX_SEGMENTS + 1) * 3
MAX_INDICES :: MAX_SEGMENTS * 12

Mesh :: struct {
    vertices:     [MAX_VERTICES]Vertex,
    vertex_count: int,
    indices:      [MAX_INDICES]u16,
    index_count:  int,
}

is_palmate :: #force_inline proc(shape: Shape) -> bool {
    return shape == .Fig || shape == .Grapevine || shape == .Ivy
}

shape_name :: proc(shape: Shape) -> string {
    #partial switch shape {
    case .Elliptic:
        return "ELLIPTIC"
    case .Lanceolate:
        return "LANCEOLATE"
    case .Ovate:
        return "OVATE"
    case .Cordate:
        return "CORDATE"
    case .Deltoid:
        return "DELTOID"
    case .Lobed:
        return "LOBED"
    case .Fig:
        return "FIG"
    case .Grapevine:
        return "GRAPE"
    case .Ivy:
        return "IVY"
    case .Cypress_Spray:
        return "CYPRESS SPRAY"
    }
    return "UNKNOWN"
}

defaults :: proc(shape: Shape) -> Config {
    result := Config {
        shape    = shape,
        length   = 2.4,
        width    = 1.15,
        segments = 20,
        curl     = .12,
        cup      = .06,
        stem     = .22,
    }
    switch shape {
    case .Lanceolate:
        result.width = .62
    case .Ovate:
        result.width = 1.30
    case .Cordate:
        result.width = 1.45
    case .Deltoid:
        result.width = 1.55
    case .Lobed:
        result.width = 1.55
        result.segments = 32
    case .Fig:
        result.width = 2.05
        result.length = 2.2
        result.segments = 36
        result.serration = .035
        result.cup = .10
    case .Grapevine:
        result.width = 1.85
        result.length = 2.1
        result.segments = 32
        result.serration = .075
        result.cup = .08
    case .Ivy:
        result.width = 1.75
        result.length = 2.15
        result.segments = 30
        result.cup = .04
    case .Cypress_Spray:
        // A flattened, overlapping fan of scale leaves. The repeated edge
        // lobes remain legible when the card represents an entire distant
        // spray rather than one microscopic leaf.
        result.width = .78
        result.length = 1.8
        result.segments = 20
        result.curl = .08
        result.cup = .12
    case .Elliptic:
    }
    return result
}

half_width :: proc(shape: Shape, t: f32) -> f32 {
    position := clamp(t, f32(0), f32(1))
    base: f32
    switch shape {
    case .Elliptic:
        base = math.sin(math.PI * position)
    case .Lanceolate:
        base = math.pow(math.sin(math.PI * position), f32(.62))
    case .Ovate:
        base = math.pow(math.sin(math.PI * math.pow(position, f32(.78))), f32(.82))
    case .Cordate:
        base = math.pow(math.sin(math.PI * position), f32(.72))
        base *= 1 + .28 * math.exp(-math.pow((position - .18) / .13, f32(2)))
        if position < .12 do base *= .50 + position * 4.2
    case .Deltoid:
        base = position < .38 ? position / .38 : (1 - position) / .62
        base = math.pow(max(base, f32(0)), f32(.62))
    case .Lobed:
        base = math.pow(math.sin(math.PI * position), f32(.68))
        base *= .72 + .28 * (1 + math.cos(position * math.PI * 8)) * .5
    case .Fig:
        // Five deep, rounded fingers: a long terminal lobe, two broad
        // shoulder lobes, and a smaller basal pair.
        envelope := math.pow(math.sin(math.PI * position), f32(.52))
        terminal := math.exp(-math.pow((position - .72) / .19, f32(2)))
        shoulder := math.exp(-math.pow((position - .43) / .105, f32(2)))
        basal := math.exp(-math.pow((position - .20) / .075, f32(2)))
        valleys :=
            .28 * math.exp(-math.pow((position - .56) / .06, f32(2))) +
            .20 * math.exp(-math.pow((position - .31) / .055, f32(2)))
        base = envelope * (.46 + .34 * terminal + .43 * shoulder + .25 * basal - valleys)
    case .Grapevine:
        // A cordate base with three shallow palmate lobes and soft sinuses.
        envelope := math.pow(math.sin(math.PI * position), f32(.62))
        shoulders := .30 * math.exp(-math.pow((position - .38) / .12, f32(2)))
        upper_lobe := .18 * math.exp(-math.pow((position - .68) / .15, f32(2)))
        sinus := .13 * math.exp(-math.pow((position - .54) / .055, f32(2)))
        base = envelope * (.72 + shoulders + upper_lobe - sinus)
        if position < .13 do base *= .42 + position * 4.45
    case .Ivy:
        // Angular evergreen ivy: a narrow point, strong lateral shoulders,
        // and a clipped basal pair.
        terminal := math.exp(-math.pow((position - .73) / .20, f32(2)))
        shoulder := math.exp(-math.pow((position - .40) / .075, f32(2)))
        basal := math.exp(-math.pow((position - .20) / .065, f32(2)))
        base = .12 + .40 * terminal + .62 * shoulder + .30 * basal
        base *= math.pow(math.sin(math.PI * position), f32(.32))
        if position < .10 do base *= position * 10
    case .Cypress_Spray:
        envelope := math.pow(math.sin(math.PI * position), f32(.42))
        scales := .58 + .42 * (.5 + .5 * math.cos(position * math.PI * 12))
        base = envelope * scales
        if position < .10 do base *= position * 10
    }
    return max(base, f32(0))
}

Palmate_Profile :: struct {
    points: [16][2]f32,
    count:  int,
}

// Right-hand contour landmarks run from the petiolar sinus to the apex.
// Mirroring them produces the complete bilateral blade. Extra landmarks
// around fig lobe tips round its coarse, obovate fingers; grape and ivy keep
// more angular ampelographic/dendrological silhouettes.
palmate_profile :: proc(shape: Shape) -> Palmate_Profile {
    profile: Palmate_Profile
    #partial switch shape {
    case .Fig:
        profile.count = 14
        profile.points = {
            {0, .055},
            {.17, .025},
            {.30, .095},
            {.37, .18},
            {.30, .25},
            {.23, .30},
            {.37, .36},
            {.49, .43},
            {.43, .50},
            {.28, .57},
            {.31, .72},
            {.29, .86},
            {.16, .98},
            {0, 1},
            {0, 0},
            {0, 0},
        }
    case .Grapevine:
        profile.count = 9
        profile.points = {
            {0, .105},
            {.24, .025},
            {.37, .16},
            {.26, .29},
            {.50, .47},
            {.28, .61},
            {.31, .79},
            {.13, .96},
            {0, 1},
            {0, 0},
            {0, 0},
            {0, 0},
            {0, 0},
            {0, 0},
            {0, 0},
            {0, 0},
        }
    case .Ivy:
        profile.count = 8
        profile.points = {
            {0, .085},
            {.25, .035},
            {.38, .19},
            {.22, .34},
            {.50, .49},
            {.24, .59},
            {.25, .82},
            {0, 1},
            {0, 0},
            {0, 0},
            {0, 0},
            {0, 0},
            {0, 0},
            {0, 0},
            {0, 0},
            {0, 0},
        }
    }
    return profile
}

mesh_finish_normals :: proc(mesh: ^Mesh) {
    if mesh == nil do return
    // All generators retain the package's historical -Z triangle winding,
    // while +Z is the botanical upper surface.
    for first := 0; first + 2 < mesh.index_count; first += 3 {
        ia := mesh.indices[first + 0]
        ib := mesh.indices[first + 1]
        ic := mesh.indices[first + 2]
        a := mesh.vertices[ia].position
        b := mesh.vertices[ib].position
        c := mesh.vertices[ic].position
        face := linalg.cross(c - a, b - a)
        mesh.vertices[ia].normal += face
        mesh.vertices[ib].normal += face
        mesh.vertices[ic].normal += face
    }
    for &vertex in mesh.vertices[:mesh.vertex_count] {
        vertex.normal = linalg.normalize0(vertex.normal)
        if linalg.dot(vertex.normal, vertex.normal) < .001 do vertex.normal = {0, 0, 1}
        if vertex.normal[2] < 0 do vertex.normal = -vertex.normal
    }
}

cross_2d :: #force_inline proc(a, b, c: [3]f32) -> f32 {
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
}

point_in_triangle_2d :: #force_inline proc(point, a, b, c: [3]f32) -> bool {
    ab := cross_2d(a, b, point)
    bc := cross_2d(b, c, point)
    ca := cross_2d(c, a, point)
    return ab >= -.00001 && bc >= -.00001 && ca >= -.00001
}

triangulate_concave :: proc(mesh: ^Mesh) {
    if mesh == nil || mesh.vertex_count < 3 do return
    remaining: [MAX_VERTICES]u16
    count := mesh.vertex_count
    area := f32(0)
    for index in 0 ..< count {
        next := (index + 1) % count
        a, b := mesh.vertices[index].position, mesh.vertices[next].position
        area += a[0] * b[1] - b[0] * a[1]
    }
    for index in 0 ..< count {
        remaining[index] = area >= 0 ? u16(index) : u16(count - 1 - index)
    }

    guard := 0
    for count > 3 && guard < MAX_VERTICES * MAX_VERTICES {
        clipped := false
        for position in 0 ..< count {
            previous_position := (position + count - 1) % count
            next_position := (position + 1) % count
            previous := remaining[previous_position]
            current := remaining[position]
            next := remaining[next_position]
            a := mesh.vertices[previous].position
            b := mesh.vertices[current].position
            c := mesh.vertices[next].position
            if cross_2d(a, b, c) <= .000001 do continue
            contains_vertex := false
            for candidate_position in 0 ..< count {
                candidate := remaining[candidate_position]
                if candidate == previous || candidate == current || candidate == next do continue
                if point_in_triangle_2d(mesh.vertices[candidate].position, a, b, c) {
                    contains_vertex = true
                    break
                }
            }
            if contains_vertex do continue
            // Preserve the package's historical -Z winding.
            mesh.indices[mesh.index_count + 0] = previous
            mesh.indices[mesh.index_count + 1] = next
            mesh.indices[mesh.index_count + 2] = current
            mesh.index_count += 3
            for shifted in position ..< count - 1 {
                remaining[shifted] = remaining[shifted + 1]
            }
            count -= 1
            clipped = true
            break
        }
        if !clipped do break
        guard += 1
    }
    if count == 3 {
        mesh.indices[mesh.index_count + 0] = remaining[0]
        mesh.indices[mesh.index_count + 1] = remaining[2]
        mesh.indices[mesh.index_count + 2] = remaining[1]
        mesh.index_count += 3
    }
}

generate_palmate :: proc(config: Config) -> Mesh {
    mesh: Mesh
    profile := palmate_profile(config.shape)
    if profile.count < 2 do return mesh
    length := max(config.length, f32(.01))
    width := max(config.width, f32(.01))
    steps := clamp(config.segments / max(profile.count - 1, 1), 1, 3)

    append_side := proc(
        mesh: ^Mesh,
        profile: Palmate_Profile,
        config: Config,
        length, width: f32,
        steps: int,
        side: f32,
        reverse: bool,
    ) {
        first_anchor := reverse ? profile.count - 1 : 0
        last_anchor := reverse ? 0 : profile.count - 1
        direction := reverse ? -1 : 1
        anchor := first_anchor
        for anchor != last_anchor {
            next := anchor + direction
            for step in 0 ..< steps {
                if mesh.vertex_count >= MAX_VERTICES do return
                fraction := f32(step) / f32(steps)
                source := profile.points[anchor] + (profile.points[next] - profile.points[anchor]) * fraction
                tooth := step % 2 == 1 ? config.serration : f32(0)
                x := source[0] * width * side * (1 + tooth)
                y := source[1] * length
                radial := math.abs(source[0]) * 2
                z := config.curl * math.sin(math.PI * source[1]) + config.cup * radial
                mesh.vertices[mesh.vertex_count] = {{x, y, z}, {}, {.5 + source[0] * side, source[1]}}
                mesh.vertex_count += 1
            }
            anchor = next
        }
        // Include the final landmark once.
        source := profile.points[last_anchor]
        x := source[0] * width * side
        y := source[1] * length
        z := config.curl * math.sin(math.PI * source[1]) + config.cup * math.abs(source[0]) * 2
        mesh.vertices[mesh.vertex_count] = {{x, y, z}, {}, {.5 + source[0] * side, source[1]}}
        mesh.vertex_count += 1
    }

    append_side(&mesh, profile, config, length, width, steps, 1, false)
    // Skip the duplicated apex when adding the mirrored return contour.
    right_count := mesh.vertex_count
    append_side(&mesh, profile, config, length, width, steps, -1, true)
    if right_count < mesh.vertex_count {
        for index in right_count ..< mesh.vertex_count - 1 {
            mesh.vertices[index] = mesh.vertices[index + 1]
        }
        mesh.vertex_count -= 1
    }
    // The mirrored return contour also ends at the petiolar-notch landmark.
    // Keep only one copy so the concave polygon is simple.
    mesh.vertex_count -= 1
    triangulate_concave(&mesh)
    mesh_finish_normals(&mesh)
    return mesh
}

generate :: proc(config: Config) -> Mesh {
    mesh: Mesh
    if int(config.shape) < 0 || int(config.shape) >= SHAPE_COUNT do return mesh
    if is_palmate(config.shape) do return generate_palmate(config)
    segments := clamp(config.segments, 3, MAX_SEGMENTS)
    length := max(config.length, f32(.01))
    width := max(config.width, f32(.01))

    for row in 0 ..= segments {
        t := f32(row) / f32(segments)
        y := t * length
        profile := half_width(config.shape, t)
        if config.serration > 0 && row > 0 && row < segments {
            tooth := row % 2 == 0 ? f32(1) : f32(-1)
            profile *= 1 + tooth * clamp(config.serration, f32(0), f32(.35))
        }
        half := width * .5 * profile
        spine_z := config.curl * math.sin(math.PI * t)
        edge_z := spine_z + config.cup * profile
        base := row * 3
        mesh.vertices[base + 0] = {{-half, y, edge_z}, {}, {0, t}}
        mesh.vertices[base + 1] = {{0, y, spine_z}, {}, {.5, t}}
        mesh.vertices[base + 2] = {{half, y, edge_z}, {}, {1, t}}
        mesh.vertex_count += 3
    }
    for row in 0 ..< segments {
        a := u16(row * 3)
        b := u16((row + 1) * 3)
        triangles := [12]u16{a, b, a + 1, a + 1, b, b + 1, a + 1, b + 1, a + 2, a + 2, b + 1, b + 2}
        for index in triangles {
            mesh.indices[mesh.index_count] = index
            mesh.index_count += 1
        }
    }
    mesh_finish_normals(&mesh)
    return mesh
}
