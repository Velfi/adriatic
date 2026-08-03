package circulation

import roads "../roads"
import "core:math"

MAX_AREAS :: 512

Area_Kind :: enum u8 {
    Street,
    Path,
    Plaza,
    Forecourt,
}

Source :: enum u8 {
    Authored,
    Generated,
    Derived,
}

Area :: struct {
    center_x, center_z: f32,
    width, length:      f32,
    rotation:           f32,
    kind:               Area_Kind,
    source:             Source,
    pavement:           roads.Pavement,
    walkable:           bool,
    driveable:          bool,
}

Plan :: struct {
    areas: [MAX_AREAS]Area,
    count: int,
}

Surface_Hit :: struct {
    found:         bool,
    on_surface:    bool,
    from_authored: bool,
    area_index:    int,
    edge_index:    int,
    amount:        f32,
    kind:          Area_Kind,
    pavement:      roads.Pavement,
    distance:      f32,
    height:        f32,
    walkable:      bool,
    driveable:     bool,
}

plan_add :: proc(plan: ^Plan, area: Area) -> int {
    if plan == nil || plan.count >= MAX_AREAS || area.width <= 0 || area.length <= 0 do return -1
    index := plan.count
    plan.areas[index] = area
    plan.count += 1
    return index
}

@(no_instrumentation)
area_local_point :: #force_inline proc(area: Area, x, z: f32) -> (local_x, local_z: f32) {
    dx, dz := x - area.center_x, z - area.center_z
    cosine, sine := math.cos(area.rotation), math.sin(area.rotation)
    return dx * cosine + dz * sine, -dx * sine + dz * cosine
}

area_contains :: proc(area: Area, x, z: f32) -> bool {
    local_x, local_z := area_local_point(area, x, z)
    return math.abs(local_x) <= area.width * .5 && math.abs(local_z) <= area.length * .5
}

// Every public circulation surface can carry a pedestrian passage. In
// particular, a plaza is not an obstacle that requires a second path or road
// surface to be laid over it.
area_is_passage :: proc(kind: Area_Kind) -> bool {
    switch kind {
    case .Street, .Path, .Plaza, .Forecourt:
        return true
    }
    return false
}

area_nearest_point :: proc(area: Area, x, z: f32) -> (nearest_x, nearest_z: f32) {
    local_x, local_z := area_local_point(area, x, z)
    local_x = clamp(local_x, -area.width * .5, area.width * .5)
    local_z = clamp(local_z, -area.length * .5, area.length * .5)
    cosine, sine := math.cos(area.rotation), math.sin(area.rotation)
    return area.center_x + local_x * cosine - local_z * sine, area.center_z + local_x * sine + local_z * cosine
}

area_overlaps :: proc(a, b: Area) -> bool {
    a_cosine, a_sine := math.cos(a.rotation), math.sin(a.rotation)
    b_cosine, b_sine := math.cos(b.rotation), math.sin(b.rotation)
    delta_x, delta_z := b.center_x - a.center_x, b.center_z - a.center_z
    // Separating-axis test for two oriented rectangles. Local +X and +Z from
    // both rectangles are the only axes that can separate them.
    axes := [4][2]f32{{a_cosine, a_sine}, {-a_sine, a_cosine}, {b_cosine, b_sine}, {-b_sine, b_cosine}}
    a_x := [2]f32{a_cosine, a_sine}
    a_z := [2]f32{-a_sine, a_cosine}
    b_x := [2]f32{b_cosine, b_sine}
    b_z := [2]f32{-b_sine, b_cosine}
    for axis in axes {
        center_distance := math.abs(delta_x * axis[0] + delta_z * axis[1])
        a_radius :=
            math.abs(a_x[0] * axis[0] + a_x[1] * axis[1]) * a.width * .5 +
            math.abs(a_z[0] * axis[0] + a_z[1] * axis[1]) * a.length * .5
        b_radius :=
            math.abs(b_x[0] * axis[0] + b_x[1] * axis[1]) * b.width * .5 +
            math.abs(b_z[0] * axis[0] + b_z[1] * axis[1]) * b.length * .5
        if center_distance > a_radius + b_radius do return false
    }
    return true
}

@(no_instrumentation)
area_distance :: #force_inline proc(area: Area, x, z: f32) -> f32 {
    local_x, local_z := area_local_point(area, x, z)
    outside_x := max(math.abs(local_x) - area.width * .5, f32(0))
    outside_z := max(math.abs(local_z) - area.length * .5, f32(0))
    return f32(math.sqrt(f64(outside_x * outside_x + outside_z * outside_z)))
}

// Authored curved roads and generated planar circulation areas intentionally
// share one query result. Callers no longer need to know how a visible surface
// was produced in order to suppress vegetation or classify movement.
surface_at_with_pavement :: proc(plan: ^Plan, position: roads.Vec3, authored: roads.Pavement_Hit) -> Surface_Hit {
    result := Surface_Hit {
        area_index = -1,
        edge_index = -1,
        distance   = f32(1e9),
    }
    if authored.edge_index >= 0 {
        result = {
            found         = true,
            on_surface    = authored.on_surface,
            from_authored = true,
            area_index    = -1,
            edge_index    = authored.edge_index,
            amount        = authored.amount,
            kind          = .Street,
            pavement      = authored.pavement,
            distance      = authored.distance,
            height        = authored.height,
            walkable      = authored.on_surface,
            driveable     = authored.on_surface,
        }
    }
    if plan == nil do return result
    for area, area_index in plan.areas[:plan.count] {
        distance := area_distance(area, position.x, position.z)
        if distance > result.distance do continue
        result = {
            found         = true,
            on_surface    = distance <= 0,
            from_authored = false,
            area_index    = area_index,
            edge_index    = -1,
            kind          = area.kind,
            pavement      = area.pavement,
            distance      = distance,
            height        = position.y,
            walkable      = area.walkable && distance <= 0,
            driveable     = area.driveable && distance <= 0,
        }
    }
    return result
}

surface_at :: proc(graph: ^roads.Graph, plan: ^Plan, position: roads.Vec3) -> Surface_Hit {
    return surface_at_with_pavement(plan, position, roads.pavement_at(graph, position))
}

surface_at_cached :: proc(
    graph: ^roads.Graph,
    plan: ^Plan,
    query: ^roads.Pavement_Query,
    position: roads.Vec3,
) -> Surface_Hit {
    return surface_at_with_pavement(plan, position, roads.pavement_at_cached(graph, query, position))
}
