package architecture

import buildings "../buildings"
import circulation "../circulation"
import terrain "../terrain"
import "core:math"

TOWN_ROUTE_NODE_CAPACITY :: 24
TOWN_ROUTE_EDGE_CAPACITY :: 32

Town_Route_Node :: struct {
    point:      [2]f32,
    fixed:      bool,
    y_junction: bool,
}

Town_Route_Edge :: struct {
    from, to: int,
}

Town_Route_Network :: struct {
    nodes:      [TOWN_ROUTE_NODE_CAPACITY]Town_Route_Node,
    node_count: int,
    edges:      [TOWN_ROUTE_EDGE_CAPACITY]Town_Route_Edge,
    edge_count: int,
}

town_route_add_node :: proc(network: ^Town_Route_Network, point: [2]f32, fixed := false) -> int {
    if network == nil || network.node_count >= len(network.nodes) do return -1
    index := network.node_count
    network.nodes[index] = {
        point = point,
        fixed = fixed,
    }
    network.node_count += 1
    return index
}

town_route_add_edge :: proc(network: ^Town_Route_Network, from, to: int) {
    if network == nil || network.edge_count >= len(network.edges) || from < 0 || to < 0 || from == to do return
    network.edges[network.edge_count] = {from, to}
    network.edge_count += 1
}

town_route_nodes_adjacent :: proc(network: ^Town_Route_Network, a, b: int) -> bool {
    for edge in network.edges[:network.edge_count] {
        if (edge.from == a && edge.to == b) || (edge.from == b && edge.to == a) do return true
    }
    return false
}

town_route_edges_equal :: proc(a, b: Town_Route_Edge) -> bool {
    return (a.from == b.from && a.to == b.to) || (a.from == b.to && a.to == b.from)
}

town_route_remove_duplicate_edges :: proc(network: ^Town_Route_Network) {
    write := 0
    for edge in network.edges[:network.edge_count] {
        if edge.from == edge.to do continue
        duplicate := false
        for previous in network.edges[:write] {
            if town_route_edges_equal(edge, previous) {
                duplicate = true
                break
            }
        }
        if duplicate do continue
        network.edges[write] = edge
        write += 1
    }
    network.edge_count = write
}

// Collapse nodes that the soft crowding force has brought into junction range.
// Rewiring rather than merely overlapping the points produces real shared
// topology, so subsequent rendering and movement see one consolidated route.
town_route_consolidate_crowding :: proc(network: ^Town_Route_Network, merge_distance: f32 = 8) {
    if network == nil do return
    for {
        merged := false
        for first in 0 ..< network.node_count {
            for second in first + 1 ..< network.node_count {
                if town_route_nodes_adjacent(network, first, second) do continue
                delta := network.nodes[second].point - network.nodes[first].point
                if delta[0] * delta[0] + delta[1] * delta[1] > merge_distance * merge_distance do continue
                if network.nodes[first].fixed && network.nodes[second].fixed do continue
                keep, remove := first, second
                if network.nodes[second].fixed {
                    keep, remove = second, first
                } else if !network.nodes[first].fixed {
                    network.nodes[keep].point = (network.nodes[first].point + network.nodes[second].point) * .5
                }
                network.nodes[keep].y_junction = network.nodes[first].y_junction || network.nodes[second].y_junction
                for &edge in network.edges[:network.edge_count] {
                    if edge.from == remove do edge.from = keep
                    if edge.to == remove do edge.to = keep
                }
                last := network.node_count - 1
                if remove != last {
                    network.nodes[remove] = network.nodes[last]
                    for &edge in network.edges[:network.edge_count] {
                        if edge.from == last do edge.from = remove
                        if edge.to == last do edge.to = remove
                    }
                }
                network.node_count -= 1
                town_route_remove_duplicate_edges(network)
                merged = true
                break
            }
            if merged do break
        }
        if !merged do break
    }
}

town_route_edge_other :: proc(edge: Town_Route_Edge, node: int) -> (other: int, incident: bool) {
    if edge.from == node do return edge.to, true
    if edge.to == node do return edge.from, true
    return -1, false
}

// Replace a tight V at an existing node with a short shared trunk and a new
// downstream branch node. Besides looking more plausibly evolved, the Y avoids
// two nearly coincident paved edges fighting for the same visual space.
town_route_merge_tight_vs :: proc(network: ^Town_Route_Network) {
    if network == nil do return
    COS_MAX_BRANCH_ANGLE :: f32(.819152) // 35 degrees.
    MIN_BRANCH_LENGTH :: f32(8)
    MAX_TRUNK_LENGTH :: f32(14)
    for apex in 0 ..< network.node_count {
        if network.nodes[apex].y_junction do continue
        merged := false
        for first_index in 0 ..< network.edge_count {
            first_other, first_incident := town_route_edge_other(network.edges[first_index], apex)
            if !first_incident do continue
            first_delta := network.nodes[first_other].point - network.nodes[apex].point
            first_length := f32(math.sqrt(f64(first_delta[0] * first_delta[0] + first_delta[1] * first_delta[1])))
            if first_length < MIN_BRANCH_LENGTH do continue
            for second_index in first_index + 1 ..< network.edge_count {
                second_other, second_incident := town_route_edge_other(network.edges[second_index], apex)
                if !second_incident || second_other == first_other do continue
                second_delta := network.nodes[second_other].point - network.nodes[apex].point
                second_length := f32(
                    math.sqrt(f64(second_delta[0] * second_delta[0] + second_delta[1] * second_delta[1])),
                )
                if second_length < MIN_BRANCH_LENGTH do continue
                first_direction := first_delta / first_length
                second_direction := second_delta / second_length
                alignment := first_direction[0] * second_direction[0] + first_direction[1] * second_direction[1]
                if alignment < COS_MAX_BRANCH_ANGLE do continue
                if network.node_count >= len(network.nodes) || network.edge_count >= len(network.edges) do return
                direction := first_direction + second_direction
                direction_length := f32(math.sqrt(f64(direction[0] * direction[0] + direction[1] * direction[1])))
                if direction_length <= .001 do continue
                direction /= direction_length
                trunk_length := min(min(first_length, second_length) * .32, MAX_TRUNK_LENGTH)
                junction := town_route_add_node(network, network.nodes[apex].point + direction * trunk_length)
                if junction < 0 do return
                network.nodes[junction].y_junction = true
                network.edges[first_index] = {junction, first_other}
                network.edges[second_index] = {junction, second_other}
                town_route_add_edge(network, apex, junction)
                merged = true
                break
            }
            if merged do break
        }
    }
}

// Return a soft world-space escape vector for a point inside a building's
// rotated clearance envelope. The influence fades toward the envelope edge,
// but remains strong inside the actual footprint so relaxation cannot settle
// a route control point beneath a building.
town_route_building_avoidance :: proc(point: [2]f32, structure: terrain.Structure) -> [2]f32 {
    clearance := clamp(min(structure.width, structure.depth) * .22, f32(3.5), f32(7))
    half_width := structure.width * .5
    half_depth := structure.depth * .5
    envelope_x, envelope_z := half_width + clearance, half_depth + clearance
    dx, dz := point[0] - structure.center_x, point[1] - structure.center_z
    cosine, sine := math.cos(structure.rotation), math.sin(structure.rotation)
    local_x := dx * cosine + dz * sine
    local_z := -dx * sine + dz * cosine
    if math.abs(local_x) >= envelope_x || math.abs(local_z) >= envelope_z do return {}

    escape_x := envelope_x - math.abs(local_x)
    escape_z := envelope_z - math.abs(local_z)
    local_force := [2]f32{}
    inside_footprint := math.abs(local_x) < half_width && math.abs(local_z) < half_depth
    strength := inside_footprint ? f32(3.2) : f32(1.15)
    if escape_x < escape_z {
        side := local_x < 0 ? f32(-1) : f32(1)
        if math.abs(local_x) <= .001 do side = structure.seed & 1 == 0 ? f32(-1) : f32(1)
        local_force[0] = side * strength * clamp(escape_x / clearance, .18, 1)
    } else {
        side := local_z < 0 ? f32(-1) : f32(1)
        if math.abs(local_z) <= .001 do side = structure.seed & 2 == 0 ? f32(-1) : f32(1)
        local_force[1] = side * strength * clamp(escape_z / clearance, .18, 1)
    }
    return {local_force[0] * cosine - local_force[1] * sine, local_force[0] * sine + local_force[1] * cosine}
}

// Relax a generated route graph before it becomes pavement. Neighbor springs
// remove mechanical kinks, while short-range node repulsion keeps nearby
// branches from collapsing into an accidental double road. Fixed perimeter
// anchors preserve useful approaches and make the result deterministic.
town_route_relax :: proc(
    network: ^Town_Route_Network,
    project: ^terrain.Project,
    structure_indices: []int,
    min_x, max_x, min_z, max_z: f32,
) {
    if network == nil do return
    for _ in 0 ..< 10 {
        next := network.nodes
        for &node, node_index in network.nodes[:network.node_count] {
            if node.fixed do continue
            neighbor_sum := [2]f32{}
            neighbor_count := 0
            for edge in network.edges[:network.edge_count] {
                neighbor := -1
                if edge.from == node_index {
                    neighbor = edge.to
                } else if edge.to == node_index {
                    neighbor = edge.from
                }
                if neighbor < 0 do continue
                neighbor_sum += network.nodes[neighbor].point
                neighbor_count += 1
            }
            force := [2]f32{}
            if neighbor_count > 0 {
                average := neighbor_sum / f32(neighbor_count)
                force += (average - node.point) * .22
            }
            for other, other_index in network.nodes[:network.node_count] {
                if other_index == node_index || town_route_nodes_adjacent(network, node_index, other_index) do continue
                delta := node.point - other.point
                distance_squared := delta[0] * delta[0] + delta[1] * delta[1]
                if distance_squared <= .001 || distance_squared >= 30 * 30 do continue
                distance := f32(math.sqrt(f64(distance_squared)))
                if distance < 7 {
                    force += delta / distance * ((7 - distance) * .07)
                } else {
                    // Independent routes in the same crowded pocket drift
                    // toward shared topology instead of running as parallel
                    // near-misses. The force stays light until they are close
                    // enough for the consolidation pass below.
                    attraction := (1 - (distance - 7) / 23) * .18
                    force -= delta / distance * attraction
                }
            }
            if project != nil {
                for structure_index in structure_indices {
                    force += town_route_building_avoidance(node.point, project.structures[structure_index])
                }
            }
            next[node_index].point[0] = clamp(node.point[0] + force[0], min_x, max_x)
            next[node_index].point[1] = clamp(node.point[1] + force[1], min_z, max_z)
        }
        // A long edge can cross a footprint even when both of its control
        // nodes are clear. Sample its middle and share the escape force across
        // movable endpoints, bending the whole span gently to one side.
        if project != nil {
            for edge in network.edges[:network.edge_count] {
                midpoint := (network.nodes[edge.from].point + network.nodes[edge.to].point) * .5
                edge_force := [2]f32{}
                for structure_index in structure_indices {
                    edge_force += town_route_building_avoidance(midpoint, project.structures[structure_index])
                }
                edge_force *= .55
                endpoints := [2]int{edge.from, edge.to}
                for endpoint in endpoints {
                    if network.nodes[endpoint].fixed do continue
                    next[endpoint].point[0] = clamp(next[endpoint].point[0] + edge_force[0], min_x, max_x)
                    next[endpoint].point[1] = clamp(next[endpoint].point[1] + edge_force[1], min_z, max_z)
                }
            }
        }
        network.nodes = next
    }
}

town_route_emit_streets :: proc(plan: ^circulation.Plan, network: ^Town_Route_Network) {
    if plan == nil || network == nil do return
    for edge in network.edges[:network.edge_count] {
        a, b := network.nodes[edge.from].point, network.nodes[edge.to].point
        dx, dz := b[0] - a[0], b[1] - a[1]
        length := f32(math.sqrt(f64(dx * dx + dz * dz)))
        if length <= .1 do continue
        _ = circulation.plan_add(plan, {
            center_x  = (a[0] + b[0]) * .5,
            center_z  = (a[1] + b[1]) * .5,
            width     = length + .35,
            length    = 6.5,
            rotation  = math.atan2(dz, dx),
            kind      = .Street,
            source    = .Generated,
            pavement  = .Cobblestone,
            walkable  = true,
            driveable = true,
        })
    }
}

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

GROUND_DETAIL_MAX_REACH :: f32(1.70)
CITY_ALLEY_MIN_FRONT_CLEARANCE :: f32(1.80)
ARCHITECTURE_MIN_OPENING_FACE_SPAN :: f32(4.5)
ARCHITECTURE_MIN_OPENING_WALL_HEIGHT :: f32(4.5)
ARCHITECTURE_OPENING_CORNER_MARGIN :: f32(.75)
ARCHITECTURE_DOOR_WINDOW_MARGIN :: f32(.55)
ARCHITECTURE_WINDOW_PIER_MARGIN :: f32(.45)
// Product-level tuning control for the archetype-specific façade grammar.
// Individual structures still choose coherent complete bays, never random
// holes in an otherwise aligned vertical stack.
ARCHITECTURE_WINDOW_DENSITY :: f32(1)

Context_Tissue :: enum u8 {
    Unspecified,
    Mercantile,
    Planned,
    Hillside,
    Harbor,
    Extension,
    Fortified,
    Agricultural,
    Religious,
}

Context_Route :: enum u8 {
    Unspecified,
    Civic,
    Street,
    Lane,
    Alley,
    Waterfront,
    Ridge,
}

Architecture_Context :: struct {
    region:           buildings.Region,
    purpose:          buildings.Purpose,
    tissue:           Context_Tissue,
    density:          f32,
    attached:         bool,
    frontage:         f32,
    depth:            f32,
    frontage_side:    f32,
    route:            Context_Route,
    waterfront:       bool,
    landmark_kind:    buildings.Landmark_Kind,
    purpose_explicit: bool,
}

architecture_landmark_archetype :: proc(kind: buildings.Landmark_Kind) -> buildings.Archetype {
    switch kind {
    case .Campanile:
        return .Campanile
    case .Palace_Loggia:
        return .Palace_Loggia
    case .Church:
        return .Church
    case .Monastery:
        return .Monastery
    case .Fortress_Gate:
        return .Fortress_Gate
    case .Harbor_Office:
        return .Harbor_Office
    case .Market_Hall:
        return .Market_Hall
    case .Cycladic_Bell:
        return .Cycladic_Bell
    case .Post_Office:
        return .Post_Office
    case .Clinic:
        return .Clinic
    case .Lighthouse:
        return .Lighthouse
    case .None:
        return .Legacy
    }
    return .Legacy
}

architecture_context_purpose :: proc(ctx: Architecture_Context, seed: u32) -> buildings.Purpose {
    if ctx.purpose_explicit do return ctx.purpose
    if ctx.waterfront || ctx.route == .Waterfront {
        lane := int((seed >> 7) % 8)
        if lane == 0 do return .Fishery
        if lane <= 2 do return .Storehouse
        if lane == 3 do return .Workshop
    }
    if ctx.tissue == .Agricultural {
        lane := int((seed >> 9) % 6)
        if lane == 0 do return .Mill
        if lane <= 2 do return .Barn_Granary
        return .Farmstead
    }
    if ctx.route == .Civic || ctx.tissue == .Mercantile {
        lane := int((seed >> 11) % 8)
        if lane <= 1 do return .Inn_Shop
        if lane == 2 do return .Workshop
    }
    if ctx.route == .Lane || ctx.route == .Alley {
        if (seed >> 13) % 7 == 0 do return .Workshop
    }
    if ctx.density < .30 && (seed >> 15) % 5 == 0 do return .Farmstead
    return .Dwelling
}

architecture_identity :: proc(ctx: Architecture_Context, seed: u32) -> buildings.Identity {
    identity := buildings.Identity {
        purpose       = architecture_context_purpose(ctx, seed),
        region        = ctx.region,
        landmark_kind = ctx.landmark_kind,
    }
    if ctx.landmark_kind != .None {
        identity.archetype = architecture_landmark_archetype(ctx.landmark_kind)
        return identity
    }
    switch identity.purpose {
    case .Dwelling:
        identity.archetype = ctx.attached && ctx.density >= .58 ? .Townhouse : .Dwelling
    case .Farmstead:
        identity.archetype = .Farmstead
    case .Barn_Granary:
        identity.archetype = .Barn_Granary
    case .Workshop:
        identity.archetype = .Workshop
    case .Inn_Shop:
        // Keep the established shop house while allowing some commercial
        // parcels to become a visibly domestic residence-over-shop. Hash the
        // choice independently: using raw seed % 3 here made mixed-use
        // selection mutually exclusive with its T-plan and court residues.
        shop_selector := city_hash(int(seed & 0x0000ffff), int(seed >> 16), seed ~ 0xa511e9b3)
        // Split commercial residences evenly between the established
        // shop-house and the more explicitly domestic mixed-use dwelling.
        // Inn/shop parcels are already uncommon outside civic/mercantile
        // tissue; a one-in-three split left ordinary deterministic towns with
        // no mixed-use storefront at all.
        identity.archetype = shop_selector & 1 == 0 ? .Mixed_Use_Dwelling : .Shop_House
    case .Mill:
        identity.archetype = .Mill
    case .Fishery:
        identity.archetype = .Fishery
    case .Storehouse:
        identity.archetype = .Storehouse
    }
    return identity
}

@(no_instrumentation)
architecture_resolve_legacy_identity :: #force_inline proc(structure: terrain.Structure) -> buildings.Identity {
    if structure.building.archetype != .Legacy do return structure.building
    return architecture_identity({
            purpose          = .Dwelling,
            density          = clamp((structure.height - 8) / 36, 0, 1),
            attached         = structure.width < 18,
            frontage         = structure.width,
            depth            = structure.depth,
            route            = .Street,
            purpose_explicit = false,
        }, structure.seed)
}

// Adds one connected settlement to the shared circulation plan. Keeping this
// local prevents distant towns from receiving kilometer-long streets and
// doorway paths through the sea.
