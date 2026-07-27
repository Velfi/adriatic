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

area_local_point :: proc(area: Area, x, z: f32) -> (local_x, local_z: f32) {
    dx, dz := x - area.center_x, z - area.center_z
    cosine, sine := math.cos(area.rotation), math.sin(area.rotation)
    return dx * cosine + dz * sine, -dx * sine + dz * cosine
}

area_contains :: proc(area: Area, x, z: f32) -> bool {
    local_x, local_z := area_local_point(area, x, z)
    return math.abs(local_x) <= area.width * .5 && math.abs(local_z) <= area.length * .5
}

area_distance :: proc(area: Area, x, z: f32) -> f32 {
    local_x, local_z := area_local_point(area, x, z)
    outside_x := max(math.abs(local_x) - area.width * .5, f32(0))
    outside_z := max(math.abs(local_z) - area.length * .5, f32(0))
    return f32(math.sqrt(f64(outside_x * outside_x + outside_z * outside_z)))
}

// Authored curved roads and generated planar circulation areas intentionally
// share one query result. Callers no longer need to know how a visible surface
// was produced in order to suppress vegetation or classify movement.
surface_at :: proc(graph: ^roads.Graph, plan: ^Plan, position: roads.Vec3) -> Surface_Hit {
    result := Surface_Hit {
        area_index = -1,
        edge_index = -1,
        distance   = f32(1e9),
    }
    authored := roads.pavement_at(graph, position)
    if authored.edge_index >= 0 {
        result = {
            found         = true,
            on_surface    = authored.on_surface,
            from_authored = true,
            area_index    = -1,
            edge_index    = authored.edge_index,
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
