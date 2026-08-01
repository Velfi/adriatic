package architecture

import buildings "../buildings"
import circulation "../circulation"
import plants "../plants"
import roads "../roads"
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
        _ = circulation.plan_add(
            plan,
            {
                center_x = (a[0] + b[0]) * .5,
                center_z = (a[1] + b[1]) * .5,
                width = length + .35,
                length = 6.5,
                rotation = math.atan2(dz, dx),
                kind = .Street,
                source = .Generated,
                pavement = .Cobblestone,
                walkable = true,
                driveable = true,
            },
        )
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
    return architecture_identity(
        {
            purpose = .Dwelling,
            density = clamp((structure.height - 8) / 36, 0, 1),
            attached = structure.width < 18,
            frontage = structure.width,
            depth = structure.depth,
            route = .Street,
            purpose_explicit = false,
        },
        structure.seed,
    )
}

// Adds one connected settlement to the shared circulation plan. Keeping this
// local prevents distant towns from receiving kilometer-long streets and
// doorway paths through the sea.
circulation_plan_add_town :: proc(plan: ^circulation.Plan, project: ^terrain.Project, structure_indices: []int) {
    if plan == nil || project == nil do return
    min_x, max_x := f32(1e9), f32(-1e9)
    min_z, max_z := f32(1e9), f32(-1e9)
    buildings := 0
    for structure_index in structure_indices {
        structure := project.structures[structure_index]
        min_x = min(min_x, structure.center_x)
        max_x = max(max_x, structure.center_x)
        min_z = min(min_z, structure.center_z)
        max_z = max(max_z, structure.center_z)
        buildings += 1
    }
    if buildings < 4 || max_z <= min_z do return

    center_x := (min_x + max_x) * .5
    center_z := (min_z + max_z) * .5
    road_span := max(max_x - min_x + 36, f32(160))
    public_area_start := plan.count
    half_span := road_span * .5
    network: Town_Route_Network
    rows := [2]f32{min_z + (max_z - min_z) * .31, min_z + (max_z - min_z) * .69}
    row_nodes: [2][5]int
    for row_z, row in rows {
        previous := -1
        for column in 0 ..< 5 {
            amount := f32(column) / 4
            x := center_x - half_span + road_span * amount
            // Coherent low-frequency bends read as routes responding to a
            // place; independent per-point noise reads as procedural wobble.
            bend := math.sin(amount * math.PI) * (row == 0 ? f32(7.5) : f32(-6.0))
            skew := (amount - .5) * (row == 0 ? f32(5) : f32(-4))
            node := town_route_add_node(&network, {x, row_z + bend + skew}, column == 0 || column == 4)
            row_nodes[row][column] = node
            if previous >= 0 do town_route_add_edge(&network, previous, node)
            previous = node
        }
    }
    // Three cross-links produce loops and choices. Offsetting their attachment
    // columns avoids the unmistakable ladder topology of a generated grid.
    town_route_add_edge(&network, row_nodes[0][1], row_nodes[1][2])
    town_route_add_edge(&network, row_nodes[0][3], row_nodes[1][3])
    town_route_merge_tight_vs(&network)
    town_route_relax(
        &network,
        project,
        structure_indices,
        center_x - half_span,
        center_x + half_span,
        min_z - 10,
        max_z + 10,
    )
    town_route_consolidate_crowding(&network)
    town_route_merge_tight_vs(&network)
    town_route_emit_streets(plan, &network)
    _ = circulation.plan_add(
        plan,
        {
            center_x = center_x,
            center_z = center_z,
            width = 28,
            length = 18,
            kind = .Plaza,
            source = .Generated,
            pavement = .Cobblestone,
            walkable = true,
        },
    )

    for structure_index in structure_indices {
        structure := project.structures[structure_index]
        frontage := architecture_frontage_structure(structure)
        sine, cosine := math.sin(frontage.rotation), math.cos(frontage.rotation)
        door_x := frontage.center_x - sine * (frontage.depth * .5 + .22)
        door_z := frontage.center_z + cosine * (frontage.depth * .5 + .22)
        front_x, front_z := -math.sin(structure.rotation), math.cos(structure.rotation)
        target_x, target_z := f32(1e9), f32(1e9)
        target_distance := f32(1e9)
        // Streets and plazas are both public passage surfaces. Connect each
        // threshold to the nearest forward-facing boundary and let movement
        // continue across that surface; do not lay a duplicate path through a
        // plaza as though the square were an obstacle.
        public_area_count := plan.count
        for candidate in plan.areas[public_area_start:public_area_count] {
            if !circulation.area_is_passage(candidate.kind) || candidate.source == .Derived do continue
            candidate_x, candidate_z := circulation.area_nearest_point(candidate, door_x, door_z)
            candidate_dx, candidate_dz := candidate_x - door_x, candidate_z - door_z
            if candidate_dx * front_x + candidate_dz * front_z < 0 do continue
            candidate_distance := candidate_dx * candidate_dx + candidate_dz * candidate_dz
            if candidate_distance < target_distance {
                target_x, target_z = candidate_x, candidate_z
                target_distance = candidate_distance
            }
        }
        if target_distance >= 1e9 do continue
        path_dx, path_dz := target_x - door_x, target_z - door_z
        path_length := f32(math.sqrt(f64(path_dx * path_dx + path_dz * path_dz)))
        if path_length <= 1.5 do continue
        _ = circulation.plan_add(
            plan,
            {
                center_x = (door_x + target_x) * .5,
                center_z = (door_z + target_z) * .5,
                width = 3.6,
                length = path_length,
                rotation = math.atan2(path_dx, path_dz),
                kind = .Path,
                source = .Derived,
                pavement = .Cobblestone,
                walkable = true,
            },
        )
    }
}

// Legacy architecture generation used to synthesize a second street network
// from building bounds here. Authored roads and settlement access alleys are
// now the canonical circulation systems; deriving another network from the
// same buildings produced overlapping visible roads and phantom gameplay
// surfaces. Keep the empty plan adapter until callers are migrated to query
// the road graph and City_Plan directly.
circulation_plan :: proc(project: ^terrain.Project) -> circulation.Plan {
    plan: circulation.Plan
    return plan
}

architecture_color :: proc(seed: u32, landmark: bool = false) -> [4]u8 {
    if landmark do return {224, 219, 196, 255}
    palette := [4][4]u8{{213, 196, 166, 255}, {218, 188, 151, 255}, {204, 173, 166, 255}, {180, 199, 193, 255}}
    return palette[int(seed % u32(len(palette)))]
}

@(no_instrumentation)
architecture_roof_color :: #force_inline proc(seed: u32, landmark: bool = false) -> [4]u8 {
    if landmark do return {177, 92, 63, 255}
    palette := [4][4]u8{{184, 93, 61, 255}, {196, 108, 68, 255}, {171, 82, 62, 255}, {201, 119, 72, 255}}
    return palette[int(seed % u32(len(palette)))]
}

@(no_instrumentation)
architecture_roof_tile_color :: #force_inline proc(seed: u32, tone: int) -> [4]u8 {
    palette := [4][5][4]u8 {
        {{201, 105, 70, 255}, {177, 76, 52, 255}, {187, 86, 56, 255}, {181, 82, 54, 255}, {213, 117, 76, 255}},
        {{211, 116, 73, 255}, {185, 82, 54, 255}, {198, 96, 59, 255}, {191, 90, 57, 255}, {220, 130, 80, 255}},
        {{193, 96, 68, 255}, {166, 70, 54, 255}, {178, 79, 59, 255}, {172, 75, 57, 255}, {205, 108, 74, 255}},
        {{216, 124, 75, 255}, {188, 87, 55, 255}, {201, 101, 61, 255}, {194, 95, 59, 255}, {225, 139, 83, 255}},
    }
    tone_index := tone % 5
    if tone_index < 0 do tone_index += 5
    return palette[int(seed % 4)][tone_index]
}

@(no_instrumentation)
architecture_roof_tile_tone :: #force_inline proc(seed: u32, course, segment: int) -> int {
    selector := city_hash(course, segment, seed ~ 0x6d2b79f5) % 16
    switch selector {
    case 0:
        // Rare sun-bleached cap or replacement tile.
        return 4
    case 1:
        // Rare deep-weathered tile.
        return 1
    case 2 ..= 4:
        return 0
    case 5 ..= 8:
        return 3
    case:
        // Keep the roof field anchored in its middle tone instead of cycling
        // evenly through every palette extreme.
        return 2
    }
}

@(no_instrumentation)
roof_style_for_seed :: #force_inline proc(seed: u32) -> Roof_Style {
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

@(no_instrumentation)
facade_style_for_seed :: #force_inline proc(seed: u32) -> int {
    // A separate hash prevents roof and façade variants from becoming locked
    // together while keeping the same seed fully reproducible.
    return int((seed ~ 0x9e3779b9) % 4)
}

@(no_instrumentation)
architecture_has_chimney :: #force_inline proc(seed: u32) -> bool {
    // Keep chimneys sparse so they punctuate the block silhouette instead of
    // turning every roof into a repetitive row of stacks.
    return seed % 3 == 0
}

@(no_instrumentation)
facade_floor_count :: #force_inline proc(height: f32) -> int {
    // Derive rows continuously from the storey module. Keeping the low-rise
    // exception in this height-only function made two-storey buildings
    // unreachable: the count jumped directly from one row to three.
    return clamp(int(math.round(f64(max(height, f32(0)) / 4.8))), 1, 16)
}

@(no_instrumentation)
facade_fitted_height :: #force_inline proc(height: f32) -> f32 {
    // Snap ordinary façades to the exact 4.8 m module represented by their
    // window rows. Very tall structures retain their authored height.
    if height >= 60 do return height
    rows := facade_floor_count(height)
    return f32(rows) * 4.8
}

@(no_instrumentation)
facade_fitted_height_in_range :: #force_inline proc(height, minimum, maximum: f32) -> f32 {
    lower, upper := min(minimum, maximum), max(minimum, maximum)
    if height >= 60 do return clamp(height, lower, upper)
    minimum_rows := clamp(int(math.ceil(f64(lower / 4.8))), 1, 16)
    maximum_rows := clamp(int(math.floor(f64(upper / 4.8))), 1, 16)
    if minimum_rows > maximum_rows {
        return clamp(facade_fitted_height(height), lower, upper)
    }
    rows := clamp(facade_floor_count(height), minimum_rows, maximum_rows)
    return f32(rows) * 4.8
}

@(no_instrumentation)
facade_step_height :: #force_inline proc(height: f32, storey_delta: int) -> f32 {
    if storey_delta == 0 do return facade_fitted_height(height)
    if height >= 60 do return max(f32(4.8), height + f32(storey_delta) * 4.8)
    rows := clamp(facade_floor_count(height) + storey_delta, 1, 16)
    return f32(rows) * 4.8
}

@(no_instrumentation)
facade_window_row_y :: #force_inline proc(height: f32, row: int) -> f32 {
    rows := facade_floor_count(height)
    window_height := facade_window_height(height)
    // Match the lower sill and upper head-room. The old 1.05 m sill combined
    // with a fixed 3 m top offset, leaving the grid visibly bottom-heavy.
    edge_clearance: f32 = 1.45
    first_y := window_height * .5 + edge_clearance
    if rows <= 1 do return first_y
    last_y := max(first_y, height - window_height * .5 - edge_clearance)
    clamped_row := clamp(row, 0, rows - 1)
    return first_y + (last_y - first_y) * f32(clamped_row) / f32(rows - 1)
}

@(no_instrumentation)
facade_column_count :: #force_inline proc(width: f32) -> int {
    // Use even column counts on broad entrance façades. An odd center column
    // sits directly behind the centered door on the ground floor, making a
    // three-column wide building read as only two windows with a blank bay.
    if width >= 42 do return 6
    if width >= 14 do return 4
    return 2
}

@(no_instrumentation)
facade_window_width :: #force_inline proc(width: f32) -> f32 {
    return clamp(width * .075, f32(1.05), f32(1.60))
}

@(no_instrumentation)
facade_window_height :: #force_inline proc(height: f32) -> f32 {
    return clamp(height * .045, f32(1.55), f32(2.20))
}

@(no_instrumentation)
facade_window_column_x :: #force_inline proc(width: f32, column: int) -> f32 {
    columns := facade_column_count(width)
    window_width := facade_window_width(width)
    if columns % 2 == 0 {
        // Reserve a centered entrance bay. Equal-pitch placement squeezes the
        // inner pair into the door surround on narrow compound frontage
        // masses, so distribute each half between a safe door clearance and
        // a consistent corner margin instead.
        door_width := clamp(width * .13, f32(1.8), f32(2.8))
        inner_center := (door_width + window_width) * .5 + .55
        outer_center := max(inner_center, width * .5 - window_width * .5 - 1)
        half_columns := columns / 2
        clamped_column := clamp(column, 0, columns - 1)
        side_index := clamped_column < half_columns ? clamped_column : clamped_column - half_columns
        side_t := half_columns <= 1 ? f32(0) : f32(side_index) / f32(half_columns - 1)
        center := inner_center + (outer_center - inner_center) * side_t
        return clamped_column < half_columns ? -center : center
    }
    spacing := min(width * .42, (width - window_width) / f32(columns))
    return (f32(clamp(column, 0, columns - 1)) - f32(columns - 1) * .5) * spacing
}

facade_window_column_x_for_count :: proc(width: f32, columns, column: int) -> f32 {
    safe_columns := max(columns, 1)
    window_width := facade_window_width(width)
    edge := max(width * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN - window_width * .5, f32(0))
    if safe_columns <= 1 do return 0
    return -edge + edge * 2 * f32(clamp(column, 0, safe_columns - 1)) / f32(safe_columns - 1)
}

Face :: enum u8 {
    Front,
    Rear,
    Left,
    Right,
}

Opening_Kind :: enum u8 {
    Window,
    Loggia,
    Door,
    Service_Door,
    Vent,
}

Opening :: struct {
    face:          Face,
    kind:          Opening_Kind,
    horizontal:    f32,
    y:             f32,
    width, height: f32,
    row, column:   int,
    primary:       bool,
}

// Broad 96 m by 54 m civic/residential masses can legitimately exceed one
// thousand openings across four faces and eight tiers. Keep enough fixed
// storage for that authored envelope; saturation silently drops later faces.
OPENING_LAYOUT_CAPACITY :: 1536

Opening_Layout :: struct {
    openings: [OPENING_LAYOUT_CAPACITY]Opening,
    count:    int,
}

face_span :: proc(mass: Architecture_Mass, face: Face) -> f32 {
    switch face {
    case .Front, .Rear:
        return mass.width
    case .Left, .Right:
        return mass.depth
    }
    return 0
}

architecture_face_follows_long_axis :: #force_inline proc(mass: Architecture_Mass, face: Face) -> bool {
    if mass.depth > mass.width {
        return face == .Left || face == .Right
    }
    return face == .Front || face == .Rear
}

architecture_paired_profile_face :: proc(footprint: Architecture_Footprint, mass_index: int, face: Face) -> Face {
    if footprint.count != 3 || mass_index != 2 do return face
    left, right := footprint.masses[1], footprint.masses[2]
    epsilon: f32 = .001
    mirrored_pair :=
        math.abs(left.local_x + right.local_x) <= epsilon &&
        math.abs(left.local_z - right.local_z) <= epsilon &&
        math.abs(left.width - right.width) <= epsilon &&
        math.abs(left.depth - right.depth) <= epsilon &&
        math.abs(left.height_scale - right.height_scale) <= epsilon
    if !mirrored_pair do return face
    if face == .Left do return .Right
    if face == .Right do return .Left
    return face
}

face_local_pose :: proc(
    mass: Architecture_Mass,
    face: Face,
    horizontal, outward: f32,
) -> (
    local_x, local_z, yaw_offset: f32,
) {
    switch face {
    case .Front:
        return mass.local_x + horizontal, mass.local_z + mass.depth * .5 + outward, 0
    case .Rear:
        return mass.local_x - horizontal, mass.local_z - mass.depth * .5 - outward, math.PI
    case .Left:
        return mass.local_x - mass.width * .5 - outward, mass.local_z + horizontal, -math.PI * .5
    case .Right:
        return mass.local_x + mass.width * .5 + outward, mass.local_z - horizontal, math.PI * .5
    }
    return mass.local_x, mass.local_z, 0
}

opening_layout_add :: proc(layout: ^Opening_Layout, opening: Opening) -> bool {
    if layout == nil || layout.count >= len(layout.openings) do return false
    layout.openings[layout.count] = opening
    layout.count += 1
    return true
}

opening_layout_contains :: proc(layout: ^Opening_Layout, face: Face, kind: Opening_Kind, row, column: int) -> bool {
    if layout == nil do return false
    for opening in layout.openings[:layout.count] {
        if opening.face == face && opening.kind == kind && opening.row == row && opening.column == column {
            return true
        }
    }
    return false
}

opening_layout_find :: proc(
    layout: ^Opening_Layout,
    face: Face,
    kind: Opening_Kind,
    row, column: int,
) -> (
    ^Opening,
    bool,
) {
    if layout == nil do return nil, false
    for opening, index in layout.openings[:layout.count] {
        if opening.face == face && opening.kind == kind && opening.row == row && opening.column == column {
            return &layout.openings[index], true
        }
    }
    return nil, false
}

opening_layout_conflicts_with_door :: proc(
    layout: ^Opening_Layout,
    face: Face,
    horizontal, y, width, height: f32,
) -> bool {
    if layout == nil do return false
    for opening in layout.openings[:layout.count] {
        if opening.face != face || (opening.kind != .Door && opening.kind != .Service_Door) do continue
        horizontal_gap := math.abs(horizontal - opening.horizontal) - (width + opening.width) * .5
        vertical_overlap := math.abs(y - opening.y) < (height + opening.height) * .5
        if vertical_overlap && horizontal_gap < ARCHITECTURE_DOOR_WINDOW_MARGIN - .001 do return true
    }
    return false
}

opening_layout_conflicts_with_opening :: proc(
    layout: ^Opening_Layout,
    face: Face,
    horizontal, y, width, height: f32,
) -> bool {
    if layout == nil do return false
    for opening in layout.openings[:layout.count] {
        if opening.face != face || opening.kind == .Door || opening.kind == .Service_Door do continue
        horizontal_gap :=
            math.abs(horizontal - opening.horizontal) - (width + opening.width) * .5
        vertical_overlap := math.abs(y - opening.y) < (height + opening.height) * .5 - .001
        if horizontal_gap < ARCHITECTURE_WINDOW_PIER_MARGIN - .001 && vertical_overlap do return true
    }
    return false
}

Facade_Profile :: struct {
    front_bays_min, front_bays_max:       int,
    rear_bays_min, rear_bays_max:         int,
    side_bays_min, side_bays_max:         int,
    window_width_min, window_width_max:   f32,
    window_height_min, window_height_max: f32,
    opening_ratio_min, opening_ratio_max: f32,
    rows_max:                             int,
    blank_sides:                          bool,
    service:                              bool,
    shop_ground_floor:                    bool,
}

facade_profile :: proc(archetype: buildings.Archetype) -> Facade_Profile {
    switch archetype {
    case .Dwelling, .Legacy:
        return {
            front_bays_min = 1,
            front_bays_max = 2,
            rear_bays_min = 1,
            rear_bays_max = 2,
            side_bays_min = 1,
            side_bays_max = 2,
            window_width_min = 1.05,
            window_width_max = 1.35,
            window_height_min = 1.55,
            window_height_max = 1.90,
            opening_ratio_min = .08,
            opening_ratio_max = .14,
        }
    case .Farmstead:
        return {
            front_bays_min = 1,
            front_bays_max = 2,
            rear_bays_min = 1,
            rear_bays_max = 2,
            side_bays_min = 0,
            side_bays_max = 1,
            window_width_min = 1.05,
            window_width_max = 1.35,
            window_height_min = 1.55,
            window_height_max = 1.90,
            opening_ratio_min = .08,
            opening_ratio_max = .14,
            blank_sides = true,
        }
    case .Townhouse:
        return {
            front_bays_min = 2,
            front_bays_max = 3,
            rear_bays_min = 1,
            rear_bays_max = 2,
            side_bays_min = 2,
            side_bays_max = 3,
            window_width_min = 1.15,
            window_width_max = 1.50,
            window_height_min = 1.70,
            window_height_max = 2.20,
            opening_ratio_min = .12,
            opening_ratio_max = .20,
        }
    case .Shop_House, .Post_Office, .Clinic:
        return {
            front_bays_min = 2,
            front_bays_max = 3,
            rear_bays_min = 1,
            rear_bays_max = 2,
            side_bays_min = 0,
            side_bays_max = 2,
            window_width_min = 1.15,
            window_width_max = 1.50,
            window_height_min = 1.70,
            window_height_max = 2.20,
            opening_ratio_min = .12,
            opening_ratio_max = .20,
            blank_sides = true,
            shop_ground_floor = archetype == .Shop_House,
        }
    case .Mixed_Use_Dwelling:
        return {
            // Two broad display bays flank the glazed shop entrance. Apartment
            // access is handled on the side walls, not by consuming frontage.
            front_bays_min    = 2,
            front_bays_max    = 2,
            rear_bays_min     = 1,
            rear_bays_max     = 2,
            side_bays_min     = 1,
            side_bays_max     = 2,
            window_width_min  = 1.35,
            window_width_max  = 1.70,
            window_height_min = 1.85,
            window_height_max = 2.25,
            opening_ratio_min = .15,
            opening_ratio_max = .22,
            blank_sides       = true,
            shop_ground_floor = true,
        }
    case .Workshop, .Storehouse, .Fishery, .Barn_Granary, .Mill:
        return {
            front_bays_min = 0,
            front_bays_max = 2,
            rear_bays_min = 0,
            rear_bays_max = 1,
            side_bays_min = 0,
            side_bays_max = 1,
            window_width_min = .80,
            window_width_max = 1.35,
            window_height_min = .65,
            window_height_max = 1.20,
            opening_ratio_min = 0,
            opening_ratio_max = .08,
            blank_sides = true,
            service = true,
        }
    case .Church:
        return {
            front_bays_min = 2,
            front_bays_max = 3,
            rear_bays_min = 1,
            rear_bays_max = 2,
            side_bays_min = 1,
            side_bays_max = 3,
            window_width_min = 1.00,
            window_width_max = 1.35,
            window_height_min = 2.20,
            window_height_max = 3.00,
            opening_ratio_min = .035,
            opening_ratio_max = .08,
            rows_max = 2,
        }
    case .Monastery:
        return {
            front_bays_min = 2,
            front_bays_max = 4,
            rear_bays_min = 1,
            rear_bays_max = 2,
            side_bays_min = 1,
            side_bays_max = 2,
            window_width_min = .95,
            window_width_max = 1.30,
            window_height_min = 1.70,
            window_height_max = 2.20,
            opening_ratio_min = .08,
            opening_ratio_max = .15,
        }
    case .Market_Hall:
        return {
            // Market halls are broad single-volume rooms. A dense horizontal
            // clerestory rhythm belongs here, but generic floor-count stacking
            // makes the elevation read as a palace or apartment block.
            front_bays_min    = 4,
            front_bays_max    = 6,
            rear_bays_min     = 2,
            rear_bays_max     = 4,
            side_bays_min     = 2,
            side_bays_max     = 4,
            window_width_min  = 1.40,
            window_width_max  = 1.90,
            window_height_min = 2.00,
            window_height_max = 2.60,
            opening_ratio_min = .04,
            opening_ratio_max = .11,
            rows_max          = 2,
        }
    case .Harbor_Office:
        return {
            front_bays_min = 3,
            front_bays_max = 5,
            rear_bays_min = 2,
            rear_bays_max = 3,
            side_bays_min = 1,
            side_bays_max = 3,
            window_width_min = 1.05,
            window_width_max = 1.45,
            window_height_min = 1.55,
            window_height_max = 2.05,
            opening_ratio_min = .045,
            opening_ratio_max = .10,
            rows_max = 3,
        }
    case .Palace_Loggia:
        return {
            front_bays_min = 3,
            front_bays_max = 5,
            rear_bays_min = 1,
            rear_bays_max = 3,
            side_bays_min = 1,
            side_bays_max = 3,
            window_width_min = 1.20,
            window_width_max = 1.70,
            window_height_min = 1.80,
            window_height_max = 2.35,
            opening_ratio_min = .15,
            opening_ratio_max = .24,
        }
    case .Campanile, .Fortress_Gate, .Cycladic_Bell, .Lighthouse:
        return {
            front_bays_min = 0,
            front_bays_max = 1,
            rear_bays_min = 0,
            rear_bays_max = 1,
            side_bays_min = 0,
            side_bays_max = 1,
            window_width_min = .75,
            window_width_max = 1.10,
            window_height_min = .75,
            window_height_max = 1.40,
            opening_ratio_min = 0,
            opening_ratio_max = .06,
            blank_sides = true,
            service = true,
        }
    }
    return {}
}

facade_profile_bay_count :: proc(
    profile: Facade_Profile,
    structure: terrain.Structure,
    face: Face,
    primary_face: bool,
    span: f32,
    wall_height: f32 = 0,
) -> int {
    low, high := profile.side_bays_min, profile.side_bays_max
    if face == .Rear {
        low, high = profile.rear_bays_min, profile.rear_bays_max
    } else if primary_face {
        low, high = profile.front_bays_min, profile.front_bays_max
    }
    if !primary_face && face != .Rear && !profile.blank_sides {
        low = max(low, 1)
    }
    if high <= 0 do return 0
    if primary_face && high >= 3 && span >= 28 do high = min(high + 1, 5)
    shift := u32(9 + int(face) * 3)
    face_multiplier := u32(0x9e3779b9) ~ (u32(int(face)) * u32(0x85ebca6b))
    low_seed := structure.seed & 255
    mixed := low_seed * face_multiplier
    folded := mixed ~ (mixed >> 8) ~ (mixed >> 16)
    // Retain the established high-bit slice while folding in low seed bits.
    // Small authored and capture seeds otherwise select the minimum bay count
    // on every face because all bits above bit eight are zero.
    variant := int(((structure.seed >> shift) ~ folded) & 255)
    count := low
    if high > low {
        count += variant % (high - low + 1)
    }
    count = int(math.floor(f64(f32(count) * ARCHITECTURE_WINDOW_DENSITY + .5)))
    if count > 0 && !profile.service && span >= 28 {
        // Archetype ranges describe ordinary façades, but using their fixed
        // maxima on very broad masses leaves the openings clustered around
        // the center because facade_bay_center caps pitch at 4.6 m. Add enough
        // bays to carry an existing rhythm across the usable wall instead.
        // A face that deliberately selected zero bays remains blank.
        usable_span := max(f32(0), span - 2 * 1.15 - profile.window_width_min)
        broad_face_count := int(math.ceil(f64(usable_span / 4.6))) + 1
        count = max(count, broad_face_count)
        if wall_height > 0 && profile.opening_ratio_min > 0 {
            window_width, window_height := facade_profile_window_size(profile, structure, face)
            rows := facade_profile_row_count(profile, wall_height, window_height)
            pane_area := window_width * window_height
            ground_factor := primary_face ? f32(.90 * .85) : f32(1)
            opening_area_per_column := pane_area * (f32(max(rows - 1, 0)) + ground_factor)
            if opening_area_per_column > .001 {
                // A centered entrance removes the middle ground pane whenever
                // the selected count is odd. Reserve one pane conservatively;
                // even counts may land slightly above the floor, never below.
                entrance_reserve := primary_face ? pane_area * ground_factor : f32(0)
                minimum_ratio_count := int(
                    math.ceil(
                        f64(
                            (profile.opening_ratio_min * span * wall_height + entrance_reserve) /
                            opening_area_per_column,
                        ),
                    ),
                )
                count = max(count, minimum_ratio_count)
                if profile.opening_ratio_max >= profile.opening_ratio_min {
                    maximum_ratio_count := int(
                        math.floor(
                            f64(
                                (profile.opening_ratio_max * span * wall_height + entrance_reserve) /
                                opening_area_per_column,
                            ),
                        ),
                    )
                    // A very narrow feasible interval can contain no integer
                    // bay count. In that case honor daylight minimum rather
                    // than forcing the wall below its profile floor.
                    if maximum_ratio_count >= minimum_ratio_count {
                        count = min(count, maximum_ratio_count)
                    }
                }
            }
        }
    }
    if count > 0 && !profile.service && span < 28 && wall_height > 0 && profile.opening_ratio_max > 0 {
        // On compact façades the archetype's seeded minimum bay count can be
        // denser than its own opening-ratio ceiling, especially when a cross
        // plan narrows a church frontage below the parcel width. Bound the
        // ordinary pane rhythm by actual wall area while retaining one bay
        // for daylight. Program-specific storefronts and arcades may override
        // this later because their minimum openings define the building use.
        window_width, window_height := facade_profile_window_size(profile, structure, face)
        rows := facade_profile_row_count(profile, wall_height, window_height)
        pane_area := window_width * window_height
        ground_factor := primary_face ? f32(.90 * .85) : f32(1)
        target_area := profile.opening_ratio_max * span * wall_height
        if pane_area > .001 {
            for count > 1 {
                ground_panes := count
                if primary_face && count % 2 == 1 do ground_panes -= 1
                estimated_area := pane_area * (f32(count * max(rows - 1, 0)) + f32(ground_panes) * ground_factor)
                if estimated_area <= target_area + .001 do break
                count -= 1
            }
        }
    }
    if primary_face && structure.building.archetype == .Mixed_Use_Dwelling && span < 42 {
        // Compact shops use a side door and one broad display pane. Ordinary
        // mixed-use frontage keeps the established door-between-two-panes
        // composition; only metropolitan-width bars repeat the rhythm.
        count = span < 14 ? 1 : 2
    }
    if primary_face && !profile.service do count = max(count, 1)
    minimum_gap := profile.rows_max > 0 ? f32(.95) : f32(1.15)
    maximum_fit := max(
        1,
        int(math.floor(f64((span - 2 * 1.15 + minimum_gap) / (profile.window_width_min + minimum_gap)))),
    )
    return clamp(count, 0, maximum_fit)
}

facade_profile_window_size :: proc(profile: Facade_Profile, structure: terrain.Structure, face: Face) -> (f32, f32) {
    face_multiplier := u32(0x9e3779b9) ~ (u32(int(face)) * u32(0x85ebca6b))
    mixed := (structure.seed & 255) * face_multiplier
    width_fold := mixed ~ (mixed >> 9) ~ (mixed >> 19)
    // Window widths may respond to each façade's proportions, but a shared
    // height module keeps sills and lintels aligned around building corners.
    height_mixed := (structure.seed & 255) * u32(0x85ebca6b)
    height_fold := (height_mixed >> 4) ~ (height_mixed >> 13) ~ (height_mixed >> 23)
    width_variant := (structure.seed >> u32(3 + int(face) * 2)) ~ width_fold
    height_variant := (structure.seed >> 5) ~ height_fold
    width_t := f32(width_variant & 31) / 31
    height_t := f32(height_variant & 31) / 31
    return profile.window_width_min + (profile.window_width_max - profile.window_width_min) * width_t,
        profile.window_height_min + (profile.window_height_max - profile.window_height_min) * height_t
}

facade_bay_center :: proc(span, window_width: f32, columns, column: int) -> f32 {
    if columns <= 1 do return 0
    usable_span := max(f32(0), span - 2 * 1.15 - window_width)
    // Sparse archetype profiles should remain sparse without collapsing into
    // a tight knot at the center of a broad wall. Carry the selected rhythm
    // across a useful portion of the elevation, while dense broad façades
    // retain their approximately 4.6 m cadence and corner clearance.
    occupied_span := min(usable_span, max(f32(columns - 1) * 4.6, span * .55))
    clamped_column := clamp(column, 0, columns - 1)
    if columns >= 7 && span >= 28 {
        // Broad elevations read as two inhabited wings around a civic or
        // domestic centre, rather than as one mechanically repeated grid.
        // Compress each half slightly and spend the recovered width on a
        // central breathing zone. The outermost bays remain fixed, so this
        // hierarchy does not trade away corner coverage or daylight area.
        ordinary_pitch := occupied_span / f32(columns - 1)
        centre_relief := min(f32(1.15), ordinary_pitch * .32)
        wing_span := max(f32(0), occupied_span - 2 * centre_relief)
        wing_pitch := wing_span / f32(columns - 1)
        centre := (f32(clamped_column) - f32(columns - 1) * .5) * wing_pitch
        if centre < -.001 {
            centre -= centre_relief
        } else if centre > .001 {
            centre += centre_relief
        }
        return centre
    }
    pitch := occupied_span / f32(columns - 1)
    return (f32(clamped_column) - f32(columns - 1) * .5) * pitch
}

facade_opening_row_count :: proc(height, opening_height: f32) -> int {
    desired := facade_floor_count(height)
    center_span := height - opening_height - 2 * 1.45
    if center_span <= 0 do return 1
    // Leave a visible strip of wall/trim between vertically adjacent panes.
    maximum_fit := int(math.floor(f64(center_span / (opening_height + .35)))) + 1
    return clamp(desired, 1, max(maximum_fit, 1))
}

facade_profile_row_count :: proc(profile: Facade_Profile, height, opening_height: f32) -> int {
    rows := facade_opening_row_count(height, opening_height)
    if profile.rows_max > 0 do rows = min(rows, profile.rows_max)
    return rows
}

facade_opening_row_y_for_count :: proc(height: f32, row, rows: int, opening_height: f32) -> f32 {
    first_y := opening_height * .5 + 1.45
    if rows <= 1 do return first_y
    last_y := max(first_y, height - opening_height * .5 - 1.45)
    return first_y + (last_y - first_y) * f32(clamp(row, 0, rows - 1)) / f32(rows - 1)
}

facade_opening_row_pitch :: proc(height: f32, rows: int, opening_height: f32) -> f32 {
    if rows <= 1 do return 0
    first_y := opening_height * .5 + 1.45
    last_y := max(first_y, height - opening_height * .5 - 1.45)
    return (last_y - first_y) / f32(rows - 1)
}

facade_opening_row_count_for_pitch :: proc(height, opening_height: f32, desired_rows: int, pitch: f32) -> int {
    if desired_rows <= 1 || pitch <= 0 do return 1
    first_y := opening_height * .5 + 1.45
    maximum_center := height - opening_height * .5 - .75
    if maximum_center <= first_y do return 1
    maximum_fit := int(math.floor(f64((maximum_center - first_y) / pitch))) + 1
    return clamp(desired_rows, 1, max(maximum_fit, 1))
}

facade_opening_row_y_for_pitch :: proc(row: int, opening_height, pitch: f32) -> f32 {
    return opening_height * .5 + 1.45 + f32(max(row, 0)) * pitch
}

facade_opening_row_y :: proc(height: f32, row: int, opening_height: f32) -> f32 {
    rows := facade_opening_row_count(height, opening_height)
    return facade_opening_row_y_for_count(height, row, rows, opening_height)
}

LIGHTHOUSE_SHAFT_DRUM_COUNT :: 5
LIGHTHOUSE_SLIT_COUNT :: 3

lighthouse_slit_height_fraction :: proc(level: int) -> f32 {
    // Keep the first slit well above the keeper door, then follow the internal
    // stair with an even vertical cadence through the occupied shaft.
    return .34 + f32(clamp(level, 0, LIGHTHOUSE_SLIT_COUNT - 1)) * .19
}

lighthouse_shaft_radius_scale :: proc(height_fraction: f32) -> f32 {
    drum := clamp(
        int(math.floor(f64(clamp(height_fraction, f32(0), f32(.9999)) * LIGHTHOUSE_SHAFT_DRUM_COUNT))),
        0,
        LIGHTHOUSE_SHAFT_DRUM_COUNT - 1,
    )
    return 1 - f32(drum) * .055
}

// Compound footprints are assembled from overlapping rectangular masses. A
// face can therefore be geometrically valid for one mass while sitting inside
// an attached wing. Suppress openings whose wall segment intersects another
// mass; otherwise windows and vents appear embedded in the join between roofs.
ARCHITECTURE_ATTACHED_EAVE_PLAN_MARGIN_FACTOR :: f32(.05)
ARCHITECTURE_ATTACHED_EAVE_VERTICAL_CLEARANCE :: f32(.30)

architecture_opening_occluded_by_mass :: proc(
    footprint: Architecture_Footprint,
    mass_index: int,
    face: Face,
    horizontal, y, width, height, structure_height: f32,
) -> bool {
    if mass_index < 0 || mass_index >= footprint.count do return false
    mass := footprint.masses[mass_index]
    opening_min_y, opening_max_y := y - height * .5, y + height * .5
    face_coordinate: f32
    opening_min, opening_max: f32
    switch face {
    case .Front:
        face_coordinate = mass.local_z + mass.depth * .5
        opening_min = mass.local_x + horizontal - width * .5
        opening_max = mass.local_x + horizontal + width * .5
    case .Rear:
        face_coordinate = mass.local_z - mass.depth * .5
        opening_min = mass.local_x - horizontal - width * .5
        opening_max = mass.local_x - horizontal + width * .5
    case .Left:
        face_coordinate = mass.local_x - mass.width * .5
        opening_min = mass.local_z + horizontal - width * .5
        opening_max = mass.local_z + horizontal + width * .5
    case .Right:
        face_coordinate = mass.local_x + mass.width * .5
        opening_min = mass.local_z - horizontal - width * .5
        opening_max = mass.local_z - horizontal + width * .5
    }

    epsilon: f32 = .001
    for other_index in 0 ..< footprint.count {
        if other_index == mass_index do continue
        other := footprint.masses[other_index]
        other_height := max(f32(0), structure_height * other.height_scale)
        body_vertical_overlap := opening_max_y > epsilon && opening_min_y < other_height - epsilon
        eave_vertical_overlap :=
            opening_max_y > other_height - ARCHITECTURE_ATTACHED_EAVE_VERTICAL_CLEARANCE &&
            opening_min_y < other_height + ARCHITECTURE_ATTACHED_EAVE_VERTICAL_CLEARANCE
        if !body_vertical_overlap && !eave_vertical_overlap do continue
        if face == .Front || face == .Rear {
            other_min := other.local_x - other.width * .5
            other_max := other.local_x + other.width * .5
            inside_depth :=
                face_coordinate >= other.local_z - other.depth * .5 - epsilon &&
                face_coordinate <= other.local_z + other.depth * .5 + epsilon
            if body_vertical_overlap &&
               inside_depth &&
               opening_max > other_min + epsilon &&
               opening_min < other_max - epsilon {
                return true
            }
            eave_margin_x := other.width * ARCHITECTURE_ATTACHED_EAVE_PLAN_MARGIN_FACTOR
            eave_margin_z := other.depth * ARCHITECTURE_ATTACHED_EAVE_PLAN_MARGIN_FACTOR
            inside_eave_depth :=
                face_coordinate >= other.local_z - other.depth * .5 - eave_margin_z - epsilon &&
                face_coordinate <= other.local_z + other.depth * .5 + eave_margin_z + epsilon
            if eave_vertical_overlap &&
               inside_eave_depth &&
               opening_max > other_min - eave_margin_x + epsilon &&
               opening_min < other_max + eave_margin_x - epsilon {
                return true
            }
        } else {
            other_min := other.local_z - other.depth * .5
            other_max := other.local_z + other.depth * .5
            inside_width :=
                face_coordinate >= other.local_x - other.width * .5 - epsilon &&
                face_coordinate <= other.local_x + other.width * .5 + epsilon
            if body_vertical_overlap &&
               inside_width &&
               opening_max > other_min + epsilon &&
               opening_min < other_max - epsilon {
                return true
            }
            eave_margin_x := other.width * ARCHITECTURE_ATTACHED_EAVE_PLAN_MARGIN_FACTOR
            eave_margin_z := other.depth * ARCHITECTURE_ATTACHED_EAVE_PLAN_MARGIN_FACTOR
            inside_eave_width :=
                face_coordinate >= other.local_x - other.width * .5 - eave_margin_x - epsilon &&
                face_coordinate <= other.local_x + other.width * .5 + eave_margin_x + epsilon
            if eave_vertical_overlap &&
               inside_eave_width &&
               opening_max > other_min - eave_margin_z + epsilon &&
               opening_min < other_max + eave_margin_z - epsilon {
                return true
            }
        }
    }
    return false
}

architecture_exposed_face_area :: proc(
    footprint: Architecture_Footprint,
    mass_index: int,
    face: Face,
    structure_height: f32,
) -> f32 {
    if mass_index < 0 || mass_index >= footprint.count do return 0
    mass := footprint.masses[mass_index]
    wall_height := max(f32(0), structure_height * mass.height_scale)
    span := face_span(mass, face)
    total_area := span * wall_height
    if total_area <= 0 do return 0

    face_coordinate: f32
    face_min, face_max: f32
    if face == .Front || face == .Rear {
        face_coordinate = mass.local_z + (face == .Front ? mass.depth * .5 : -mass.depth * .5)
        face_min, face_max = mass.local_x - mass.width * .5, mass.local_x + mass.width * .5
    } else {
        face_coordinate = mass.local_x + (face == .Right ? mass.width * .5 : -mass.width * .5)
        face_min, face_max = mass.local_z - mass.depth * .5, mass.local_z + mass.depth * .5
    }

    occluder_min, occluder_max: [2]f32
    occluder_height: [2]f32
    occluder_count := 0
    epsilon: f32 = .001
    for other_index in 0 ..< footprint.count {
        if other_index == mass_index || occluder_count >= 2 do continue
        other := footprint.masses[other_index]
        interval_min, interval_max: f32
        crosses_face := false
        if face == .Front || face == .Rear {
            crosses_face =
                face_coordinate >= other.local_z - other.depth * .5 - epsilon &&
                face_coordinate <= other.local_z + other.depth * .5 + epsilon
            interval_min = max(face_min, other.local_x - other.width * .5)
            interval_max = min(face_max, other.local_x + other.width * .5)
        } else {
            crosses_face =
                face_coordinate >= other.local_x - other.width * .5 - epsilon &&
                face_coordinate <= other.local_x + other.width * .5 + epsilon
            interval_min = max(face_min, other.local_z - other.depth * .5)
            interval_max = min(face_max, other.local_z + other.depth * .5)
        }
        if !crosses_face || interval_max <= interval_min + epsilon do continue
        occluder_min[occluder_count] = interval_min
        occluder_max[occluder_count] = interval_max
        occluder_height[occluder_count] = min(wall_height, max(f32(0), structure_height * other.height_scale))
        occluder_count += 1
    }

    covered_area := f32(0)
    for index in 0 ..< occluder_count {
        covered_area += (occluder_max[index] - occluder_min[index]) * occluder_height[index]
    }
    if occluder_count == 2 {
        shared_min := max(occluder_min[0], occluder_min[1])
        shared_max := min(occluder_max[0], occluder_max[1])
        if shared_max > shared_min {
            // Inclusion-exclusion prevents nested or overlapping attachments
            // from subtracting the same buried wall patch twice.
            covered_area -= (shared_max - shared_min) * min(occluder_height[0], occluder_height[1])
        }
    }
    return max(f32(0), total_area - covered_area)
}

architecture_opening_layout_add_habitable_row_on_face :: proc(
    layout: ^Opening_Layout,
    footprint: Architecture_Footprint,
    structure: terrain.Structure,
    mass_index: int,
    profile: Facade_Profile,
    face: Face,
    row: int,
) -> bool {
    if layout == nil || mass_index < 0 || mass_index >= footprint.count || row < 0 do return false
    mass := footprint.masses[mass_index]
    wall_height := max(f32(0), structure.height * mass.height_scale)
    span := face_span(mass, face)
    if span < ARCHITECTURE_MIN_OPENING_FACE_SPAN do return false
    profile_face := architecture_paired_profile_face(footprint, mass_index, face)
    window_width, window_height := facade_profile_window_size(profile, structure, profile_face)
    storey_rows := facade_floor_count(wall_height)
    if profile.rows_max > 0 do storey_rows = min(storey_rows, profile.rows_max)
    if storey_rows > 1 {
        fitted_window_height :=
            (wall_height - 2 * 1.45 - f32(storey_rows - 1) * .35) / f32(storey_rows)
        window_height = min(window_height, max(f32(.75), fitted_window_height - .01))
    }
    independent_range_pitch :=
        (structure.building.archetype == .Farmstead &&
            footprint.count == 2 &&
            mass_index == 1 &&
            structure.width >= 20 &&
            structure.depth >= 18 &&
            structure.seed % 5 == 0) ||
        (structure.building.archetype == .Shop_House &&
            footprint.count == 2 &&
            mass_index == 1 &&
            structure.width >= 16 &&
            structure.depth >= 14 &&
            structure.seed % 4 == 0) ||
        (structure.building.archetype == .Post_Office && mass_index > 0)
    reference_height := independent_range_pitch ? wall_height : structure.height
    reference_rows := facade_profile_row_count(profile, reference_height, window_height)
    reference_pitch := facade_opening_row_pitch(reference_height, reference_rows, window_height)
    desired_rows := facade_profile_row_count(profile, wall_height, window_height)
    fitted_rows := facade_opening_row_count_for_pitch(
        wall_height,
        window_height,
        desired_rows,
        reference_pitch,
    )
    if fitted_rows < desired_rows && desired_rows > 1 {
        // Preserve the parent datum while it represents every occupied level.
        // Near the one/two-storey threshold a shortened wing can physically
        // fit two rows but not the taller parent's second sill; use the wing's
        // own complete rhythm instead of silently deleting its upper floor.
        reference_pitch = facade_opening_row_pitch(wall_height, desired_rows, window_height)
        fitted_rows = desired_rows
    }
    if row >= fitted_rows do return false
    opening_y := facade_opening_row_y_for_pitch(row, window_height, reference_pitch)
    fitted_widths := [2]f32{window_width, min(window_width, f32(.55))}
    for fitted_width in fitted_widths {
        edge_center := max(f32(0), span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN - fitted_width * .5)
        centers: [21]f32
        centers[0], centers[1], centers[2], centers[3], centers[4] =
            0, -span * .25, span * .25, -edge_center, edge_center
        // The first five candidates preserve the compact fallback grammar.
        // A supplementary 16-point grid lets repeated calls populate a broad
        // exposed strip after an attachment culls the originally seeded bays.
        for grid_column in 0 ..< 16 {
            centers[5 + grid_column] =
                -edge_center + 2 * edge_center * f32(grid_column) / 15
        }
        for horizontal in centers {
            if math.abs(horizontal) + fitted_width * .5 > span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN {
                continue
            }
            if opening_layout_conflicts_with_door(
                layout,
                face,
                horizontal,
                opening_y,
                fitted_width,
                window_height,
            ) {
                continue
            }
            if architecture_opening_occluded_by_mass(
                footprint,
                mass_index,
                face,
                horizontal,
                opening_y,
                fitted_width,
                window_height,
                structure.height,
            ) {
                continue
            }
            if opening_layout_conflicts_with_opening(
                layout,
                face,
                horizontal,
                opening_y,
                fitted_width,
                window_height,
            ) {
                continue
            }
            logical_column := 0
            for existing in layout.openings[:layout.count] {
                if existing.face == face && existing.kind == .Window && existing.row == row {
                    logical_column = max(logical_column, existing.column + 1)
                }
            }
            return opening_layout_add(
                layout,
                {
                    face = face,
                    kind = .Window,
                    horizontal = horizontal,
                    y = opening_y,
                    width = fitted_width,
                    height = window_height,
                    row = row,
                    column = logical_column,
                },
            )
        }
    }
    return false
}

architecture_opening_layout_add_habitable_row_fallback :: proc(
    layout: ^Opening_Layout,
    footprint: Architecture_Footprint,
    structure: terrain.Structure,
    mass_index: int,
    profile: Facade_Profile,
    row: int,
) -> bool {
    fallback_faces := [4]Face{.Front, .Left, .Right, .Rear}
    for face in fallback_faces {
        if architecture_opening_layout_add_habitable_row_on_face(
            layout,
            footprint,
            structure,
            mass_index,
            profile,
            face,
            row,
        ) {
            return true
        }
    }
    return false
}

opening_layout_reindex_window_columns :: proc(layout: ^Opening_Layout) {
    if layout == nil do return
    row_counts: [4][16]int
    row_offsets: [4][16]int
    row_cursors: [4][16]int
    row_indices: [OPENING_LAYOUT_CAPACITY]int
    for opening in layout.openings[:layout.count] {
        if opening.kind != .Window || opening.row < 0 || opening.row >= 16 do continue
        row_counts[int(opening.face)][opening.row] += 1
    }
    offset := 0
    for face_index in 0 ..< 4 {
        for row in 0 ..< 16 {
            row_offsets[face_index][row] = offset
            row_cursors[face_index][row] = offset
            offset += row_counts[face_index][row]
        }
    }
    for opening, opening_index in layout.openings[:layout.count] {
        if opening.kind != .Window || opening.row < 0 || opening.row >= 16 do continue
        face_index := int(opening.face)
        cursor := row_cursors[face_index][opening.row]
        row_indices[cursor] = opening_index
        row_cursors[face_index][opening.row] += 1
    }
    for face_index in 0 ..< 4 {
        for row in 0 ..< 16 {
            row_count := row_counts[face_index][row]
            row_offset := row_offsets[face_index][row]
            // Rows rarely exceed a few dozen panes. Sorting each compact row
            // after two linear gathering passes retains stable order for equal
            // coordinates without rescanning the full layout per face/row.
            for index in 1 ..< row_count {
                opening_index := row_indices[row_offset + index]
                insert_at := index
                for insert_at > 0 &&
                    layout.openings[row_indices[row_offset + insert_at - 1]].horizontal >
                    layout.openings[opening_index].horizontal {
                    row_indices[row_offset + insert_at] = row_indices[row_offset + insert_at - 1]
                    insert_at -= 1
                }
                row_indices[row_offset + insert_at] = opening_index
            }
            for opening_index, spatial_column in row_indices[row_offset:row_offset + row_count] {
                layout.openings[opening_index].column = spatial_column
            }
        }
    }
}

architecture_opening_layout :: proc(
    structure: terrain.Structure,
    mass_index: int,
    primary_mass_index: int,
) -> Opening_Layout {
    layout: Opening_Layout
    footprint := architecture_footprint(structure)
    if mass_index < 0 || mass_index >= footprint.count do return layout
    mass := footprint.masses[mass_index]
    // Opening grammar must follow the rendered mass height. BASE_CELL_SIZE is
    // terrain sampling resolution (currently about 15.7 m), not a minimum
    // building storey height; clamping to it put openings far above compact
    // structures such as the 4.8 m marina office.
    wall_height := max(f32(0), structure.height * mass.height_scale)
    if wall_height < ARCHITECTURE_MIN_OPENING_WALL_HEIGHT do return layout

    identity := architecture_resolve_legacy_identity(structure)
    profile := facade_profile(identity.archetype)
    farmstead_work_range :=
        identity.archetype == .Farmstead &&
        footprint.count == 2 &&
        mass_index == 1 &&
        structure.width >= 20 &&
        structure.depth >= 18 &&
        structure.seed % 5 == 0
    if farmstead_work_range {
        // The low dairy/washhouse/tool range needs daylight, but repeating the
        // farmhouse's tall bedroom panes makes it read as another residence.
        // Use a compact two-tier utility rhythm while retaining Window kind.
        profile = {
            front_bays_min    = 1,
            front_bays_max    = 2,
            rear_bays_min     = 1,
            rear_bays_max     = 2,
            side_bays_min     = 0,
            side_bays_max     = 1,
            window_width_min  = .80,
            window_width_max  = 1.10,
            window_height_min = 1.00,
            window_height_max = 1.40,
            opening_ratio_min = .03,
            opening_ratio_max = .08,
            rows_max          = 2,
            blank_sides       = true,
        }
    }
    shop_stock_range :=
        identity.archetype == .Shop_House &&
        footprint.count == 2 &&
        mass_index == 1 &&
        structure.width >= 16 &&
        structure.depth >= 14 &&
        structure.seed % 4 == 0
    if shop_stock_range {
        // The authored rear stockroom is not another apartment range. Keep
        // one or two small inventory-room windows for daylight and security,
        // while other shop-house returns retain the residential profile.
        profile = {
            front_bays_min    = 1,
            front_bays_max    = 2,
            rear_bays_min     = 1,
            rear_bays_max     = 2,
            side_bays_min     = 0,
            side_bays_max     = 1,
            window_width_min  = .75,
            window_width_max  = 1.05,
            window_height_min = .85,
            window_height_max = 1.25,
            opening_ratio_min = .025,
            opening_ratio_max = .07,
            rows_max          = 2,
            blank_sides       = true,
        }
    }
    post_sorting_range := identity.archetype == .Post_Office && mass_index > 0
    if post_sorting_range {
        // Sorting rooms need controlled daylight and secure walls, not the
        // tall public-office rhythm of the counter hall.
        profile = {
            front_bays_min    = 1,
            front_bays_max    = 2,
            rear_bays_min     = 1,
            rear_bays_max     = 2,
            side_bays_min     = 0,
            side_bays_max     = 1,
            window_width_min  = .80,
            window_width_max  = 1.05,
            window_height_min = .95,
            window_height_max = 1.30,
            opening_ratio_min = .025,
            opening_ratio_max = .07,
            rows_max          = 2,
            blank_sides       = true,
        }
    }
    clinic_ward_range := identity.archetype == .Clinic && mass_index > 0
    if clinic_ward_range {
        // Examination and recovery rooms benefit from a regular daylight
        // rhythm on every exposed wall, while staying subordinate to the
        // taller public waiting-room bar.
        profile = {
            front_bays_min    = 2,
            front_bays_max    = 3,
            rear_bays_min     = 2,
            rear_bays_max     = 3,
            side_bays_min     = 1,
            side_bays_max     = 2,
            window_width_min  = 1.20,
            window_width_max  = 1.50,
            window_height_min = 1.60,
            window_height_max = 2.00,
            opening_ratio_min = .10,
            opening_ratio_max = .18,
            rows_max          = 3,
        }
    }
    fortress_tower := identity.archetype == .Fortress_Gate && footprint.count == 3 && mass_index < 2
    if fortress_tower {
        // Tower openings are defensive light slits rather than warehouse
        // vents. Stack a sparse narrow rhythm through the tower height so the
        // occupied guard levels remain legible without weakening the walls.
        profile = {
            front_bays_min    = 1,
            front_bays_max    = 1,
            rear_bays_min     = 1,
            rear_bays_max     = 1,
            side_bays_min     = 1,
            side_bays_max     = 1,
            window_width_min  = .38,
            window_width_max  = .55,
            window_height_min = 1.10,
            window_height_max = 1.60,
            opening_ratio_min = 0,
            opening_ratio_max = .035,
            rows_max          = 3,
            service           = true,
        }
    }
    fortress_guard_range :=
        identity.archetype == .Fortress_Gate && footprint.count == 3 && mass_index == 2
    if fortress_guard_range {
        // The low barracks wall is now exposed behind the streetward towers.
        // Guarantee one or two secure rear vents for the occupied guard room
        // while retaining the sparse defensive profile on every other face.
        profile.rear_bays_min = 1
        profile.rear_bays_max = max(profile.rear_bays_max, 2)
    }
    bell_tower := (identity.archetype == .Campanile || identity.archetype == .Cycladic_Bell) && mass_index == 0
    if bell_tower {
        // Bell towers need a vertical sequence of narrow stair/chamber lights;
        // the generic service profile leaves one low warehouse-like vent.
        profile = {
            front_bays_min    = 1,
            front_bays_max    = 1,
            rear_bays_min     = 1,
            rear_bays_max     = 1,
            side_bays_min     = 1,
            side_bays_max     = 1,
            window_width_min  = .50,
            window_width_max  = .75,
            window_height_min = 1.10,
            window_height_max = 1.70,
            opening_ratio_min = 0,
            opening_ratio_max = .045,
            rows_max          = 4,
            service           = true,
        }
    }
    mill_tower := identity.archetype == .Mill && footprint.count == 2 && mass_index == 1
    if mill_tower {
        profile = {
            front_bays_min    = 0,
            front_bays_max    = 0,
            rear_bays_min     = 0,
            rear_bays_max     = 0,
            side_bays_min     = 0,
            side_bays_max     = 0,
            window_width_min  = .55,
            window_width_max  = .80,
            window_height_min = .90,
            window_height_max = 1.30,
            opening_ratio_min = 0,
            opening_ratio_max = .04,
            rows_max          = 2,
            service           = true,
        }
    }
    barn_range := identity.archetype == .Barn_Granary
    if barn_range {
        // Barn walls need both low working ventilation and a high hayloft
        // opening. A single warehouse-sill row leaves tall barns blank above
        // their cart doors and hides the usable upper storage level.
        profile = {
            front_bays_min    = 1,
            front_bays_max    = 2,
            rear_bays_min     = 1,
            rear_bays_max     = 2,
            side_bays_min     = 1,
            side_bays_max     = 1,
            window_width_min  = .70,
            window_width_max  = 1.05,
            window_height_min = .85,
            window_height_max = 1.35,
            opening_ratio_min = .01,
            opening_ratio_max = .06,
            rows_max          = 2,
            service           = true,
        }
    }
    workshop_daylight := identity.archetype == .Workshop
    if workshop_daylight {
        // Working halls need broad high light over benches and machinery. Keep
        // a single clerestory band rather than treating workshops as dark
        // storehouses with small low vents.
        profile = {
            front_bays_min    = 2,
            front_bays_max    = 4,
            rear_bays_min     = 1,
            rear_bays_max     = 3,
            side_bays_min     = 1,
            side_bays_max     = 2,
            window_width_min  = 1.20,
            window_width_max  = 1.80,
            window_height_min = 1.10,
            window_height_max = 1.60,
            opening_ratio_min = .025,
            opening_ratio_max = .09,
            rows_max          = 1,
            service           = true,
        }
    }
    fishery_work_hall := identity.archetype == .Fishery && mass_index == 0
    if fishery_work_hall {
        // The main cleaning/packing hall needs washable walls but also strong
        // high daylight. Reserve the small vent grammar for smokehouses and
        // gear sheds attached behind it.
        profile = {
            front_bays_min    = 2,
            front_bays_max    = 3,
            rear_bays_min     = 1,
            rear_bays_max     = 2,
            side_bays_min     = 1,
            side_bays_max     = 2,
            window_width_min  = 1.00,
            window_width_max  = 1.45,
            window_height_min = 1.00,
            window_height_max = 1.50,
            opening_ratio_min = .02,
            opening_ratio_max = .08,
            rows_max          = 1,
            service           = true,
        }
    }
    storehouse_high_vents := identity.archetype == .Storehouse
    if storehouse_high_vents {
        // Preserve long uninterrupted walls for shelving and stacked goods.
        // Small secure vents belong near the wall head, clear of loading
        // leaves, rather than at domestic sill height.
        profile = {
            front_bays_min    = 1,
            front_bays_max    = 3,
            rear_bays_min     = 1,
            rear_bays_max     = 2,
            side_bays_min     = 1,
            side_bays_max     = 2,
            window_width_min  = .70,
            window_width_max  = .95,
            window_height_min = .70,
            window_height_max = 1.10,
            opening_ratio_min = .01,
            opening_ratio_max = .05,
            rows_max          = 1,
            service           = true,
        }
    }
    harbor_dispatch_range := identity.archetype == .Harbor_Office && footprint.count == 3 && mass_index == 1
    harbor_service_range := identity.archetype == .Harbor_Office && footprint.count == 3 && mass_index == 2
    if harbor_service_range {
        // The small third range in the quay-office yard stores wet gear and
        // records rather than office desks. Give it the sparse service vent
        // grammar while the public bar and dispatch wing remain habitable.
        profile = facade_profile(.Storehouse)
    }
    habitable := buildings.is_habitable(identity.archetype) && !harbor_service_range
    occupied_secondary_daylight := habitable || identity.archetype == .Post_Office
    storehouse_loading_range :=
        identity.archetype == .Storehouse &&
        footprint.count == 2 &&
        mass_index == 1 &&
        structure.width >= 20 &&
        structure.depth >= 16 &&
        structure.seed % 8 == 0
    fishery_smokehouse_range :=
        identity.archetype == .Fishery &&
        footprint.count == 2 &&
        mass_index == 1 &&
        structure.width >= 18 &&
        structure.depth >= 14 &&
        structure.seed % 4 == 0
    market_loading_range :=
        identity.archetype == .Market_Hall &&
        footprint.count == 2 &&
        mass_index == 1 &&
        structure.width >= 22 &&
        structure.depth >= 18
    market_basilica_aisle :=
        identity.archetype == .Market_Hall && footprint.count == 3 && mass_index > 0
    market_basilica_nave :=
        identity.archetype == .Market_Hall && footprint.count == 3 && mass_index == 0
    if market_basilica_aisle {
        // Permanent stall aisles need clear display and storage walls beneath
        // a compact high daylight band. Repeating the nave's large two-tier
        // civic panes makes the lower ranges read as separate market halls.
        profile = {
            front_bays_min = 2,
            front_bays_max = 3,
            rear_bays_min = 1,
            rear_bays_max = 2,
            side_bays_min = 1,
            side_bays_max = 2,
            window_width_min = 1.20,
            window_width_max = 1.60,
            window_height_min = 1.20,
            window_height_max = 1.70,
            opening_ratio_min = .03,
            opening_ratio_max = .08,
            rows_max = 1,
        }
    }
    monastery_cloister_range := identity.archetype == .Monastery && footprint.count == 3 && mass_index == 0
    primary_mass := mass_index == primary_mass_index
    faces := [4]Face{.Front, .Rear, .Left, .Right}
    mixed_use_apartment_face := (structure.seed >> 2) & 1 == 0 ? Face.Left : Face.Right
    if identity.archetype == .Mixed_Use_Dwelling && footprint.count == 2 {
        // Put the independent apartment stair on the side opposite an
        // asymmetric private rear wing. This keeps its approach legible and
        // avoids spending both side walls on duplicate residential doors.
        mixed_use_apartment_face = footprint.masses[1].local_x < 0 ? Face.Right : Face.Left
    }

    for face in faces {
        span := face_span(mass, face)
        if span < ARCHITECTURE_MIN_OPENING_FACE_SPAN do continue
        // The fortress's public entrance is the open slot between its paired
        // towers. Treating the arbitrarily selected frontage tower as an
        // ordinary primary mass punches a domestic-scale door beside the
        // gate and weakens the defensive silhouette.
        primary_face :=
            primary_mass && face == .Front && (identity.archetype != .Fortress_Gate || footprint.count == 1)
        guard_court_entry :=
            identity.archetype == .Fortress_Gate && footprint.count == 3 && mass_index == 2 && face == .Front
        utility_yard_entry :=
            (farmstead_work_range ||
                shop_stock_range ||
            harbor_service_range ||
            storehouse_loading_range ||
            fishery_smokehouse_range ||
            market_loading_range ||
            market_basilica_aisle) &&
            face == .Rear
        barn_aisle_entry :=
            identity.archetype == .Barn_Granary &&
            footprint.count == 2 &&
            mass_index == 1 &&
            face == (mass.local_x < 0 ? Face.Left : Face.Right)
        productive_court_hall_entry :=
            (identity.archetype == .Workshop || identity.archetype == .Storehouse || identity.archetype == .Fishery) &&
            footprint.count == 3 &&
            mass_index == 0 &&
            structure.seed % 6 == 4 &&
            face == .Front
        church_chancel_entry :=
            identity.archetype == .Church && footprint.count == 3 && mass_index == 2 && face == .Rear
        monastery_service_entry :=
            identity.archetype == .Monastery && footprint.count == 3 && mass_index == 0 && face == .Rear
        palace_wing_entry :=
            identity.archetype == .Palace_Loggia &&
            footprint.count == 3 &&
            (mass_index == 1 || mass_index == 2) &&
            (face == .Rear || face == (mass_index == 1 ? Face.Right : Face.Left))
        monastery_cell_court_entry :=
            identity.archetype == .Monastery &&
            footprint.count == 3 &&
            (mass_index == 1 || mass_index == 2) &&
            face == (mass_index == 1 ? Face.Right : Face.Left)
        harbor_yard_entry :=
            identity.archetype == .Harbor_Office &&
            footprint.count == 3 &&
            mass_index > 0 &&
            face == (mass.local_x < 0 ? Face.Right : Face.Left)
        domestic_court_wing_entry :=
            (identity.archetype == .Dwelling || identity.archetype == .Farmstead) &&
            footprint.count == 3 &&
            structure.seed % 8 == 3 &&
            (mass_index == 1 || mass_index == 2) &&
            (face == .Rear || face == (mass_index == 1 ? Face.Right : Face.Left))
        domestic_return_entry :=
            (identity.archetype == .Dwelling ||
                identity.archetype == .Farmstead ||
                identity.archetype == .Townhouse ||
                identity.archetype == .Shop_House) &&
            footprint.count == 2 &&
            mass_index == 1 &&
            face == .Rear
        civic_return_entry :=
            (identity.archetype == .Palace_Loggia ||
                identity.archetype == .Market_Hall ||
                identity.archetype == .Harbor_Office ||
                identity.archetype == .Monastery ||
                identity.archetype == .Post_Office ||
                identity.archetype == .Clinic) &&
            footprint.count >= 2 &&
            mass_index == 1 &&
            face == .Rear &&
            (footprint.count == 2 || identity.archetype == .Palace_Loggia || identity.archetype == .Harbor_Office)
        clinic_ward_entry :=
            identity.archetype == .Clinic &&
            mass_index > 0 &&
            (face == .Rear || (footprint.count == 3 && face == (mass_index == 1 ? Face.Right : Face.Left)))
        post_work_entry := identity.archetype == .Post_Office && mass_index > 0 && face == .Rear
        post_parcel_annex_entry :=
            identity.archetype == .Post_Office && footprint.count == 3 && mass_index == 2 && face == .Rear
        mixed_use_private_entry :=
            identity.archetype == .Mixed_Use_Dwelling &&
            ((footprint.count == 2 && mass_index == 1 && face == .Rear) ||
                    (footprint.count == 3 && mass_index == 1 && face == .Right) ||
                    (footprint.count == 3 && mass_index == 2 && face == .Left))
        mixed_use_apartment_entry :=
            identity.archetype == .Mixed_Use_Dwelling &&
            primary_mass &&
            wall_height >= 7.2 &&
            face == mixed_use_apartment_face
        secondary_service_entry :=
            guard_court_entry ||
            utility_yard_entry ||
            barn_aisle_entry ||
            productive_court_hall_entry ||
            church_chancel_entry ||
            monastery_service_entry ||
            palace_wing_entry ||
            monastery_cell_court_entry ||
            harbor_yard_entry ||
            domestic_court_wing_entry ||
            domestic_return_entry ||
            civic_return_entry ||
            clinic_ward_entry ||
            post_work_entry ||
            mixed_use_private_entry ||
            mixed_use_apartment_entry
        profile_face := architecture_paired_profile_face(footprint, mass_index, face)
        compact_storefront :=
            primary_face &&
            profile.shop_ground_floor &&
            ((identity.archetype == .Mixed_Use_Dwelling && span < 14) ||
                (identity.archetype == .Shop_House && span < 10))
        compact_market_arcade :=
            primary_face && identity.archetype == .Market_Hall && span < 15
        compact_palace_loggia :=
            primary_face && identity.archetype == .Palace_Loggia && span < 8
        compact_ground_frontage := compact_storefront || compact_market_arcade || compact_palace_loggia
        compact_frontage_door_side := (structure.seed & 1) == 0 ? f32(-1) : f32(1)
        door_width := f32(0)
        if primary_face || secondary_service_entry {
            door_width = clamp(span * .13, f32(1.8), f32(2.8))
            door_height := clamp(wall_height * .075, f32(3.0), f32(4.0))
            if primary_face && identity.archetype == .Barn_Granary {
                // The main threshing aisle must admit a loaded cart, not just
                // a person. Its broader leaf also becomes the organizing void
                // for the sparse front-vent rhythm.
                door_width = clamp(span * .26, f32(4.2), f32(6.0))
                door_height = clamp(wall_height * .22, f32(4.5), f32(6.0))
            } else if primary_face && identity.archetype == .Storehouse {
                door_width = clamp(span * .20, f32(3.4), f32(5.0))
                door_height = clamp(wall_height * .19, f32(4.0), f32(5.5))
            } else if primary_face && identity.archetype == .Workshop {
                // The work-hall entrance must pass benches, stock, and small
                // machinery. A domestic service leaf contradicts the broad
                // high-light workshop elevation it organizes.
                door_width = clamp(span * .18, f32(3.2), f32(4.8))
                door_height = clamp(wall_height * .18, f32(3.8), f32(5.0))
            } else if primary_face && identity.archetype == .Fishery {
                // Fishery halls move crates and handcarts through a washable
                // working frontage, but need not match a warehouse portal.
                door_width = clamp(span * .17, f32(3.0), f32(4.4))
                door_height = clamp(wall_height * .17, f32(3.6), f32(4.8))
            } else if storehouse_loading_range && face == .Rear {
                door_width = clamp(span * .25, f32(3.2), f32(4.8))
                door_height = clamp(wall_height * .28, f32(3.8), f32(5.0))
            } else if (market_loading_range || market_basilica_aisle) && face == .Rear {
                // The rear stem of the T-plan is the market's produce and
                // stall-loading hall. Preserve the centered public-to-service
                // circulation axis, but size its yard portal for handcarts
                // and loaded barrows instead of an ordinary civic side door.
                door_width = clamp(span * .24, f32(3.4), f32(5.0))
                door_height = clamp(wall_height * .25, f32(3.8), f32(5.0))
            } else if barn_aisle_entry {
                door_width = clamp(span * .24, f32(3.2), f32(4.8))
                door_height = clamp(wall_height * .28, f32(3.8), f32(5.0))
            } else if post_parcel_annex_entry {
                // The side annex is the cart-facing parcel dock, while the
                // centered sorting range retains a staff-scale yard door.
                // Giving both ranges the same narrow leaf hid their distinct
                // circulation roles and made bulk mail arrive through a
                // pedestrian opening.
                door_width = clamp(span * .30, f32(3.0), f32(4.2))
                door_height = clamp(wall_height * .30, f32(3.4), f32(4.6))
            } else if mixed_use_private_entry {
                // Match the complete jamb-and-lintel envelope drawn by the
                // bespoke private-entry renderer, rather than only its leaf.
                door_width = 1.66
                door_height = 3.02
            } else if mixed_use_apartment_entry {
                door_width = 1.65
                door_height = 3.05
            }
            broad_public_entrance :=
                primary_face &&
                span >= 28 &&
                wall_height >= 14.4 &&
                (identity.archetype == .Post_Office ||
                    identity.archetype == .Clinic ||
                    identity.archetype == .Palace_Loggia ||
                    identity.archetype == .Market_Hall ||
                    identity.archetype == .Harbor_Office ||
                    identity.archetype == .Monastery ||
                    identity.archetype == .Church)
            broad_urban_entrance :=
                primary_face &&
                span >= 28 &&
                wall_height >= 14.4 &&
                (identity.archetype == .Townhouse ||
                    identity.archetype == .Shop_House ||
                    identity.archetype == .Mixed_Use_Dwelling)
            if broad_public_entrance {
                // A civic frontage needs a legible pair of public leaves, but
                // it must remain distinct from cart-scale productive portals.
                door_width = clamp(span * .075, f32(3.2), f32(4.0))
                door_height = clamp(wall_height * .10, f32(4.2), f32(4.8))
            } else if broad_urban_entrance {
                // Metropolitan residential and shop bars use a restrained
                // double-leaf entry instead of stretching a domestic leaf to
                // the same 2.8 m cap on every large elevation.
                door_width = clamp(span * .060, f32(3.0), f32(3.4))
                door_height = clamp(wall_height * .09, f32(4.0), f32(4.5))
            }
            // Retain the shared corner and head clearance on compact authored
            // structures even when their program asks for a cart-scale leaf.
            door_width = min(door_width, max(f32(.8), span - ARCHITECTURE_OPENING_CORNER_MARGIN * 2))
            door_height = min(door_height, max(f32(.8), wall_height - .40))
            door_y := .20 + door_height * .5
            if mixed_use_private_entry do door_y = door_height * .5
            door_horizontal := f32(0)
            if compact_ground_frontage {
                // Pull the entrance to one jamb so the shortened frontage can
                // spend its remaining width on useful display or arcade bay.
                door_horizontal = compact_frontage_door_side *
                    (span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN - door_width * .5)
            } else if mixed_use_apartment_entry {
                door_y = 1.62
                desired_horizontal := face == .Left ? mass.depth * .20 : -mass.depth * .20
                maximum_horizontal := max(
                    f32(0),
                    span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN - door_width * .5,
                )
                // The apartment entrance favors the streetward end of each
                // side wall, but shallow mixed-use lots cannot sustain the
                // full proportional offset. Clamp the bespoke doorway to the
                // same jamb-to-corner clearance as generated windows.
                door_horizontal = clamp(desired_horizontal, -maximum_horizontal, maximum_horizontal)
            }
            door_occluded := architecture_opening_occluded_by_mass(
                footprint,
                mass_index,
                face,
                door_horizontal,
                door_y,
                door_width,
                door_height,
                structure.height,
            )
            if door_occluded {
                // Compact L and working-court plans can project an attachment
                // across the centered jamb even though another broad part of
                // the same approach wall remains exterior. Keep the authored
                // centerline when it is usable; otherwise search symmetric
                // quarter/edge bays for the nearest exposed entrance.
                maximum_door_center := max(
                    f32(0),
                    span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN - door_width * .5,
                )
                fallback_centers := [4]f32 {
                    -min(span * .25, maximum_door_center),
                    min(span * .25, maximum_door_center),
                    -maximum_door_center,
                    maximum_door_center,
                }
                for fallback_center in fallback_centers {
                    if architecture_opening_occluded_by_mass(
                        footprint,
                        mass_index,
                        face,
                        fallback_center,
                        door_y,
                        door_width,
                        door_height,
                        structure.height,
                    ) {
                        continue
                    }
                    door_horizontal = fallback_center
                    door_occluded = false
                    break
                }
            }
            if !door_occluded {
                _ = opening_layout_add(
                    &layout,
                    {
                        face = face,
                        kind = primary_face && habitable ? Opening_Kind.Door : Opening_Kind.Service_Door,
                        horizontal = door_horizontal,
                        y = door_y,
                        width = door_width,
                        height = door_height,
                        primary = primary_face,
                    },
                )
            }
        }

        bay_profile := profile
        domestic_u_court_face :=
            (identity.archetype == .Dwelling || identity.archetype == .Farmstead) &&
            footprint.count == 3 &&
            structure.seed % 8 == 3 &&
            (mass_index == 1 || mass_index == 2) &&
            face == (mass_index == 1 ? Face.Right : Face.Left)
        if domestic_u_court_face {
            // Rural blank-side policy belongs on exposed party/gable walls,
            // not on the inhabited faces enclosing a private rear court.
            // Give each wing a modest inward-looking rhythm while its court
            // door continues to own the ground circulation bay.
            bay_profile.blank_sides = false
            bay_profile.side_bays_min = 1
            bay_profile.side_bays_max = max(bay_profile.side_bays_max, 2)
        }
        if identity.archetype == .Monastery && footprint.count == 3 && mass_index == 0 && primary_face {
            // The paired cell ranges bury predictable strips of the communal
            // range's court-facing wall. Seed against a small pre-cull reserve
            // so the remaining exposed façade still meets the public 8% floor.
            bay_profile.opening_ratio_min = min(profile.opening_ratio_max, profile.opening_ratio_min + .01)
        }
        columns := facade_profile_bay_count(bay_profile, structure, profile_face, primary_face, span, wall_height)
        if habitable &&
           architecture_face_follows_long_axis(mass, face) &&
           columns <= 0 {
            // Blank-side profiles describe subordinate gable ends, not the
            // principal elevation of a deep bar. Always retain at least one
            // daylight bay on walls that follow the footprint's longest axis.
            columns = 1
        }
        if compact_ground_frontage {
            // The shifted entrance and fitted display pane are a one-bay
            // compact grammar. Seeded multi-bay counts would retain the broad
            // shop or market sizing path and cull every bay against the door.
            columns = 1
        }
        if market_basilica_nave && primary_face {
            // The nave is deliberately narrower than a T-plan's street bar.
            // Cap its arcade at four useful trading bays instead of squeezing
            // the generic six-bay maximum into sub-two-metre openings.
            columns = min(columns, 4)
        }
        if columns <= 0 do continue
        window_width, window_height := facade_profile_window_size(profile, structure, profile_face)
        storey_rows := facade_floor_count(wall_height)
        if profile.rows_max > 0 do storey_rows = min(storey_rows, profile.rows_max)
        if storey_rows > 1 {
            // At the exact two-storey threshold, a tall randomized pane can
            // consume the vertical wall band needed by the second level.
            // Fit height—not width or bay count—to preserve both daylight
            // rows and the profile's horizontal character.
            fitted_window_height :=
                (wall_height - 2 * 1.45 - f32(storey_rows - 1) * .35) / f32(storey_rows)
            // Leave a centimetre of numerical tolerance so the subsequent
            // row-count floor does not reject an exactly fitted second pane.
            window_height = min(window_height, max(f32(.75), fitted_window_height - .01))
        }
        // Residential compounds share parent-storey datums. Barn ranges have
        // independent loft floors under unequal roof heights, so distribute
        // their two ventilation levels within each range's actual wall.
        independent_range_pitch := barn_range || farmstead_work_range || shop_stock_range || post_sorting_range
        reference_height := independent_range_pitch ? wall_height : structure.height
        reference_rows := facade_profile_row_count(profile, reference_height, window_height)
        reference_pitch := facade_opening_row_pitch(reference_height, reference_rows, window_height)
        desired_face_rows := facade_profile_row_count(profile, wall_height, window_height)
        vertical_service_openings := fortress_tower || bell_tower || barn_range
        face_rows :=
            profile.service && !vertical_service_openings ? 1 : facade_opening_row_count_for_pitch(wall_height, window_height, desired_face_rows, reference_pitch)
        if !profile.service && face_rows < desired_face_rows && desired_face_rows > 1 {
            // A compact secondary range can cross the two-storey threshold
            // while remaining too short for its parent's upper sill. Retain
            // shared datums where possible, then fall back to the range's own
            // fitted pitch so an occupied level never becomes windowless.
            reference_pitch = facade_opening_row_pitch(wall_height, desired_face_rows, window_height)
            face_rows = desired_face_rows
        }
        for row in 0 ..< face_rows {
            if bell_tower && row < face_rows - 1 {
                // Follow the internal stair with one slit per lower level,
                // cycling across rear and side walls. Reserve the complete
                // four-face rhythm for the open bell chamber at the top, and
                // keep the entrance facade quiet below it.
                stair_face := 1 + int((structure.seed + u32(row)) % 3)
                if int(face) != stair_face do continue
            }
            opening_y := facade_opening_row_y_for_pitch(row, window_height, reference_pitch)
            for column in 0 ..< columns {
                horizontal := facade_bay_center(span, window_width, columns, column)
                central_bay := columns % 2 == 1 && column == columns / 2
                if primary_face && row == 0 && central_bay && !compact_ground_frontage {
                    continue
                }
                if math.abs(horizontal) + window_width * .5 > span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN {
                    continue
                }
                kind := Opening_Kind.Window
                opening_height := window_height
                opening_width := window_width
                principal_floor_archetype :=
                    identity.archetype == .Dwelling ||
                    identity.archetype == .Farmstead ||
                    identity.archetype == .Townhouse ||
                    identity.archetype == .Shop_House ||
                    identity.archetype == .Mixed_Use_Dwelling ||
                    identity.archetype == .Post_Office ||
                    identity.archetype == .Clinic
                if principal_floor_archetype &&
                   primary_face &&
                   span >= 28 &&
                   columns >= 7 &&
                   face_rows >= 3 &&
                   row == 1 {
                    // Give the first upper occupied floor a restrained
                    // horizontal emphasis. Preserve pane area exactly so the
                    // hierarchy changes architectural character without
                    // inflating the glazing ratio or weakening daylight on
                    // any other level.
                    principal_scale := f32(1.12)
                    opening_width *= principal_scale
                    opening_height /= principal_scale
                }
                if harbor_dispatch_range && face_rows > 1 && row == face_rows - 1 {
                    // The upper dispatch/watch room scans the quay through a
                    // broader horizontal band. Fit enlargement to the actual
                    // bay pitch and corner clearance so compact wings cannot
                    // overlap neighboring panes.
                    desired_width := window_width * 1.28
                    if columns > 1 {
                        next_center := facade_bay_center(span, window_width, columns, min(column + 1, columns - 1))
                        previous_center := facade_bay_center(span, window_width, columns, max(column - 1, 0))
                        neighbor_pitch :=
                            column < columns - 1 ? math.abs(next_center - horizontal) : math.abs(horizontal - previous_center)
                        desired_width = min(desired_width, max(window_width, neighbor_pitch - .55))
                    }
                    corner_fit := (span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN - math.abs(horizontal)) * 2
                    opening_width = min(desired_width, max(window_width, corner_fit))
                    opening_height = min(window_height * 1.10, f32(2.25))
                    opening_y = min(opening_y, wall_height - opening_height * .5 - .75)
                }
                if workshop_daylight || fishery_work_hall || market_basilica_aisle {
                    kind = .Window
                    opening_y = wall_height - opening_height * .5 - 1.10
                } else if storehouse_high_vents {
                    kind = .Vent
                    opening_y = wall_height - opening_height * .5 - 1.10
                } else if profile.service {
                    kind = .Vent
                    if !vertical_service_openings {
                        opening_y = max(opening_height * .5 + 1.15, f32(1.5))
                    }
                } else if profile.shop_ground_floor && primary_face && row == 0 {
                    // Shop glazing should begin near the pavement and approach
                    // the door head. Treating it like a slightly enlarged
                    // domestic window leaves the ground floor visually closed.
                    if compact_storefront && columns == 1 {
                        // A narrow shop cannot carry its ordinary pair of
                        // display panes. Fit one useful pane into the band
                        // opposite the side-shifted entrance while preserving
                        // both the corner and door clearances.
                        available_width :=
                            span -
                            ARCHITECTURE_OPENING_CORNER_MARGIN * 2 -
                            door_width -
                            ARCHITECTURE_DOOR_WINDOW_MARGIN
                        opening_width = clamp(available_width, f32(.70), f32(5.20))
                    } else if identity.archetype == .Mixed_Use_Dwelling {
                        if columns <= 2 {
                            opening_width = clamp(span * .27, f32(4.2), f32(7.2))
                        } else {
                            // Very broad mixed-use bars grow beyond the
                            // ordinary two display bays. Fit those panes to the
                            // generated rhythm instead of repeating the 7.2 m
                            // two-bay width until neighboring panes overlap.
                            opening_width = clamp(
                                (span - ARCHITECTURE_OPENING_CORNER_MARGIN * 2) / f32(columns) * .60,
                                f32(2.35),
                                f32(5.20),
                            )
                        }
                    } else {
                        opening_width = clamp(span / f32(columns + 1) * .62, f32(2.35), f32(3.60))
                    }
                    opening_height = min(window_height * 1.62, f32(3.40))
                    opening_y = .36 + opening_height * .5
                } else if identity.archetype == .Palace_Loggia && primary_face && row == 0 {
                    // The palace name must appear in its plan/elevation: tall
                    // open ground bays flank the ceremonial door while upper
                    // residential/state rooms retain glazed windows.
                    kind = .Loggia
                    opening_width = clamp(span / f32(columns + 1) * .58, f32(2.10), f32(3.20))
                    opening_height = min(clamp(wall_height * .16, f32(3.80), f32(4.80)), wall_height - .50)
                    opening_y = .25 + opening_height * .5
                } else if monastery_cloister_range && primary_face && row == 0 {
                    // The communal range faces the open cloister court between
                    // its cell wings. Make that ground band a shaded arcade,
                    // while upper cells and library rooms retain glazing.
                    kind = .Loggia
                    opening_width = clamp(span / f32(columns + 1) * .50, f32(1.55), f32(2.35))
                    opening_height = min(clamp(wall_height * .145, f32(3.20), f32(4.20)), wall_height - .50)
                    opening_y = .25 + opening_height * .5
                } else if identity.archetype == .Market_Hall && primary_face && row == 0 {
                    // Public trading spills through a permeable ground arcade;
                    // the second tier remains glazed clerestory light over the
                    // market floor.
                    kind = .Loggia
                    opening_width = clamp(span / f32(columns + 1) * .56, f32(2.00), f32(3.50))
                    opening_height = min(clamp(wall_height * .15, f32(3.40), f32(4.60)), wall_height - .50)
                    opening_y = .20 + opening_height * .5
                } else if primary_face && row == 0 {
                    opening_width *= .90
                    opening_height *= .85
                    opening_y = facade_opening_row_y(wall_height, row, opening_height)
                }
                if columns > 1 {
                    // Program-specific storefront and arcade panes can grow
                    // wider than the ordinary window module used to place
                    // their bay centers. Fit every enlarged opening to its
                    // local interval so adjacent panes retain a real masonry
                    // pier on irregular broad-façade rhythms.
                    neighbor_pitch := f32(0)
                    if column > 0 {
                        previous_center := facade_bay_center(span, window_width, columns, column - 1)
                        neighbor_pitch = math.abs(horizontal - previous_center)
                    }
                    if column < columns - 1 {
                        next_center := facade_bay_center(span, window_width, columns, column + 1)
                        next_pitch := math.abs(next_center - horizontal)
                        neighbor_pitch = neighbor_pitch <= 0 ? next_pitch : min(neighbor_pitch, next_pitch)
                    }
                    opening_width = min(
                        opening_width,
                        max(f32(.70), neighbor_pitch - ARCHITECTURE_WINDOW_PIER_MARGIN),
                    )
                }
                if kind == .Loggia && primary_face && row == 0 {
                    // Fit every arcade grammar—not only markets—to the actual
                    // half-façade interval between the entrance clearance and
                    // corner margin. Compact palaces otherwise overlap their
                    // minimum-width loggia bays before placement begins.
                    side_columns := max(columns / 2, 1)
                    usable_half_band :=
                        span * .5 -
                        ARCHITECTURE_OPENING_CORNER_MARGIN -
                        door_width * .5 -
                        ARCHITECTURE_DOOR_WINDOW_MARGIN
                    fit_width :=
                        (usable_half_band - f32(side_columns - 1) * ARCHITECTURE_WINDOW_PIER_MARGIN) /
                        f32(side_columns)
                    opening_width = min(opening_width, max(f32(.90), fit_width))
                }
                if primary_face && row == 0 {
                    // Lay each half of the ground-floor rhythm into the band
                    // between the corner margin and centered entrance. Merely
                    // nudging an inner bay away from the door can push it into
                    // its unchanged outer neighbor on four- and five-bay civic
                    // façades.
                    if compact_ground_frontage && columns == 1 {
                        // Mirror the lone display or arcade bay across from
                        // the side entrance, retaining the same corner datum
                        // as the full multi-bay frontage.
                        horizontal = -compact_frontage_door_side *
                            (span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN - opening_width * .5)
                    }
                    // Decide redistribution for the whole façade from its
                    // innermost surviving bay. Moving only the bay that
                    // directly conflicts with the door compresses it against
                    // an unchanged neighbor and can leave a paper-thin pier.
                    inner_column := max(columns / 2 - 1, 0)
                    inner_horizontal := facade_bay_center(span, window_width, columns, inner_column)
                    facade_needs_door_redistribution :=
                        !compact_ground_frontage && columns > 1 &&
                        opening_layout_conflicts_with_door(
                            &layout,
                            face,
                            inner_horizontal,
                            opening_y,
                            opening_width,
                            opening_height,
                        )
                    if compact_ground_frontage || facade_needs_door_redistribution {
                        side_columns := max(columns / 2, 1)
                        if facade_needs_door_redistribution {
                            usable_half_band :=
                                span * .5 -
                                ARCHITECTURE_OPENING_CORNER_MARGIN -
                                door_width * .5 -
                                ARCHITECTURE_DOOR_WINDOW_MARGIN
                            fit_width :=
                                (usable_half_band -
                                    f32(side_columns - 1) * ARCHITECTURE_WINDOW_PIER_MARGIN) /
                                f32(side_columns)
                            opening_width = min(opening_width, max(f32(.70), fit_width))
                        }
                        inner_center := door_width * .5 + opening_width * .5 + ARCHITECTURE_DOOR_WINDOW_MARGIN
                        outer_center := span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN - opening_width * .5
                        right_start := (columns + 1) / 2
                        if columns > 1 && column < side_columns {
                            t := side_columns <= 1 ? f32(1) : f32(column) / f32(side_columns - 1)
                            horizontal = -(outer_center + (inner_center - outer_center) * t)
                        } else if columns > 1 && column >= right_start {
                            side_column := column - right_start
                            t := side_columns <= 1 ? f32(0) : f32(side_column) / f32(side_columns - 1)
                            horizontal = inner_center + (outer_center - inner_center) * t
                        }
                    }
                    if math.abs(horizontal) + opening_width * .5 > span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN {
                        continue
                    }
                }
                if opening_layout_conflicts_with_door(
                    &layout,
                    face,
                    horizontal,
                    opening_y,
                    opening_width,
                    opening_height,
                ) {
                    continue
                }
                if architecture_opening_occluded_by_mass(
                    footprint,
                    mass_index,
                    face,
                    horizontal,
                    opening_y,
                    opening_width,
                    opening_height,
                    structure.height,
                ) {
                    continue
                }
                if opening_layout_conflicts_with_opening(
                    &layout,
                    face,
                    horizontal,
                    opening_y,
                    opening_width,
                    opening_height,
                ) {
                    continue
                }
                _ = opening_layout_add(
                    &layout,
                    {
                        face = face,
                        kind = kind,
                        horizontal = horizontal,
                        y = opening_y,
                        width = opening_width,
                        height = opening_height,
                        row = row,
                        column = column,
                        primary = primary_face,
                    },
                )
            }
        }
    }

    if mill_tower {
        // The inner tower is enclosed in plan by the lower mill body. Generic
        // rows start at ground level and are all culled by that enclosing
        // mass, leaving only a one-off fallback vent. Author two compact tiers
        // wholly within the exposed upper stage instead.
        outer_height := structure.height * footprint.masses[0].height_scale
        exposed_height := wall_height - outer_height
        for face in faces {
            span := face_span(mass, face)
            if span < ARCHITECTURE_MIN_OPENING_FACE_SPAN do continue
            window_width, window_height := facade_profile_window_size(profile, structure, face)
            // Leave a tiny numerical cushion around the paired .55 m sill and
            // head clearances; an exactly fitted compact vent can otherwise
            // be rejected by the subsequent floating-point bounds check.
            available_vent_height := exposed_height - 1.102
            if available_vent_height < .45 do continue
            window_height = min(window_height, available_vent_height)
            tier_pitch := window_height + .70
            tier_count := clamp(int(math.floor(f64((exposed_height - 1.10 + .70) / tier_pitch))), 1, 2)
            for tier in 0 ..< tier_count {
                opening_y := outer_height + .55 + window_height * .5 + f32(tier) * tier_pitch
                if opening_y + window_height * .5 > wall_height - .55 do continue
                if architecture_opening_occluded_by_mass(
                    footprint,
                    mass_index,
                    face,
                    0,
                    opening_y,
                    window_width,
                    window_height,
                    structure.height,
                ) {
                    continue
                }
                _ = opening_layout_add(
                    &layout,
                    {
                        face = face,
                        kind = .Vent,
                        horizontal = 0,
                        y = opening_y,
                        width = window_width,
                        height = window_height,
                        row = facade_floor_count(outer_height) + tier,
                        column = 0,
                    },
                )
            }
        }
    }

    if (!primary_mass && habitable) || profile.service {
        fallback_kind := habitable || workshop_daylight || fishery_work_hall ? Opening_Kind.Window : Opening_Kind.Vent
        has_exposed_opening := false
        for opening in layout.openings[:layout.count] {
            if opening.kind == fallback_kind {
                has_exposed_opening = true
                break
            }
        }
        if !has_exposed_opening {
            // A rear wing can have its only seeded bay removed because that
            // bay lands on the join with the street range. Find one modest
            // exposed opening so the attached volume still reads as occupied
            // or ventilated. Prefer high rows, which can remain visible above
            // a lower adjoining range or the mill's enclosing base mass.
            fallback_faces := [4]Face{.Front, .Left, .Right, .Rear}
            added := false
            for face in fallback_faces {
                span := face_span(mass, face)
                if span < ARCHITECTURE_MIN_OPENING_FACE_SPAN do continue
                profile_face := architecture_paired_profile_face(footprint, mass_index, face)
                window_width, window_height := facade_profile_window_size(profile, structure, profile_face)
                centers := [3]f32{0, -span * .25, span * .25}
                reference_rows := facade_profile_row_count(profile, structure.height, window_height)
                reference_pitch := facade_opening_row_pitch(structure.height, reference_rows, window_height)
                desired_fallback_rows := facade_profile_row_count(profile, wall_height, window_height)
                fallback_rows := facade_opening_row_count_for_pitch(
                    wall_height,
                    window_height,
                    desired_fallback_rows,
                    reference_pitch,
                )
                for reverse_row in 0 ..< fallback_rows {
                    row := fallback_rows - reverse_row - 1
                    opening_y := facade_opening_row_y_for_pitch(row, window_height, reference_pitch)
                    if storehouse_high_vents {
                        opening_y = wall_height - window_height * .5 - 1.10
                    } else if market_basilica_aisle {
                        opening_y = wall_height - window_height * .5 - 1.10
                    }
                    for horizontal, column in centers {
                        if math.abs(horizontal) + window_width * .5 > span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN {
                            continue
                        }
                        if opening_layout_conflicts_with_door(
                            &layout,
                            face,
                            horizontal,
                            opening_y,
                            window_width,
                            window_height,
                        ) {
                            continue
                        }
                        if architecture_opening_occluded_by_mass(
                            footprint,
                            mass_index,
                            face,
                            horizontal,
                            opening_y,
                            window_width,
                            window_height,
                            structure.height,
                        ) {
                            continue
                        }
                        _ = opening_layout_add(
                            &layout,
                            {
                                face = face,
                                kind = fallback_kind,
                                horizontal = horizontal,
                                y = opening_y,
                                width = window_width,
                                height = window_height,
                                row = row,
                                column = column,
                            },
                        )
                        added = true
                        break
                    }
                    if added do break
                }
                if added do break
            }
        }
    }
    if barn_range {
        has_vent := false
        for opening in layout.openings[:layout.count] {
            if opening.kind == .Vent {
                has_vent = true
                break
            }
        }
        if !has_vent {
            // A compact side aisle may expose only the cart-door wall. When
            // the parent's sill rhythm leaves no lateral bay, use the clear
            // hayloft band above that door instead of sealing the range or
            // squeezing a vent beside the jamb.
            for opening in layout.openings[:layout.count] {
                if opening.kind != .Service_Door do continue
                profile_face := architecture_paired_profile_face(footprint, mass_index, opening.face)
                vent_width, vent_height := facade_profile_window_size(profile, structure, profile_face)
                door_top := opening.y + opening.height * .5
                available_height :=
                    wall_height - .55 - door_top - ARCHITECTURE_WINDOW_PIER_MARGIN
                vent_height = min(vent_height, available_height)
                if vent_height < profile.window_height_min - .001 do continue
                vent_y := wall_height - .55 - vent_height * .5
                if architecture_opening_occluded_by_mass(
                    footprint,
                    mass_index,
                    opening.face,
                    opening.horizontal,
                    vent_y,
                    vent_width,
                    vent_height,
                    structure.height,
                ) {
                    continue
                }
                _ = opening_layout_add(
                    &layout,
                    {
                        face = opening.face,
                        kind = .Vent,
                        horizontal = opening.horizontal,
                        y = vent_y,
                        width = vent_width,
                        height = vent_height,
                        row = 1,
                        column = 0,
                    },
                )
                break
            }
        }
    }
    if !primary_mass && occupied_secondary_daylight {
        has_lower_window, has_upper_window := false, false
        for opening in layout.openings[:layout.count] {
            if opening.kind != .Window do continue
            if opening.row == 0 {
                has_lower_window = true
            } else {
                has_upper_window = true
            }
        }
        if !has_lower_window {
            _ = architecture_opening_layout_add_habitable_row_fallback(
                &layout,
                footprint,
                structure,
                mass_index,
                profile,
                0,
            )
        }
        if facade_floor_count(wall_height) > 1 && !has_upper_window {
            _ = architecture_opening_layout_add_habitable_row_fallback(
                &layout,
                footprint,
                structure,
                mass_index,
                profile,
                1,
            )
        }
    }
    if habitable || identity.archetype == .Post_Office {
        // A mass-level fallback can satisfy daylight by placing its lone pane
        // on another elevation, leaving a useful garden, court, or street wall
        // blank when a centered service door or attached range removes the
        // seeded bay. Repair each materially exposed elevation independently;
        // joined seams and intentionally blank gables stay quiet.
        daylight_faces := [4]Face{.Front, .Rear, .Left, .Right}
        for face in daylight_faces {
            if (face == .Left || face == .Right) &&
               profile.blank_sides &&
               !architecture_face_follows_long_axis(mass, face) {
                continue
            }
            span := face_span(mass, face)
            if span < 6 do continue
            exposed_area := architecture_exposed_face_area(footprint, mass_index, face, structure.height)
            if exposed_area < span * wall_height * .20 do continue
            has_face_daylight := false
            for opening in layout.openings[:layout.count] {
                if opening.face == face && (opening.kind == .Window || opening.kind == .Loggia) {
                    has_face_daylight = true
                    break
                }
            }
            if has_face_daylight do continue
            profile_face := architecture_paired_profile_face(footprint, mass_index, face)
            _, window_height := facade_profile_window_size(profile, structure, profile_face)
            desired_rows := facade_profile_row_count(profile, wall_height, window_height)
            for reverse_row in 0 ..< desired_rows {
                row := desired_rows - reverse_row - 1
                if architecture_opening_layout_add_habitable_row_on_face(
                    &layout,
                    footprint,
                    structure,
                    mass_index,
                    profile,
                    face,
                    row,
                ) {
                    break
                }
            }
        }
    }
    normalize_ordinary_glazing :=
        !profile.service &&
        (!profile.shop_ground_floor || !primary_mass) &&
        identity.archetype != .Market_Hall
    if normalize_ordinary_glazing && profile.opening_ratio_max > 0 {
        // A single minimum-size pane can exceed a compact wall's ratio ceiling,
        // while a broad compound face can retain a full seeded band after an
        // attachment buries most of its actual wall. Preserve rhythm and aspect
        // ratios, but scale ordinary glazing uniformly to the exposed-area
        // budget at every span. Purpose-defining storefronts and arcades remain
        // exempt because their openings describe program rather than a generic
        // daylight percentage.
        for face in faces {
            authored_primary_front :=
                primary_mass &&
                face == .Front &&
                (identity.archetype == .Palace_Loggia ||
                    identity.archetype == .Market_Hall ||
                    identity.archetype == .Monastery)
            if authored_primary_front do continue
            glazing_area := f32(0)
            for opening in layout.openings[:layout.count] {
                if opening.face == face && opening.kind == .Window {
                    glazing_area += opening.width * opening.height
                }
            }
            exposed_wall_area := architecture_exposed_face_area(footprint, mass_index, face, structure.height)
            span := face_span(mass, face)
            full_wall_area := span * wall_height
            minimum_target_area := profile.opening_ratio_min * exposed_wall_area
            if span >= 28 &&
               exposed_wall_area >= full_wall_area * .75 &&
               glazing_area > .001 &&
               glazing_area < minimum_target_area - .001 {
                // A broad stepped join can bury every seeded center even when
                // most of the wall remains exterior. Fill safe edge/center
                // candidates row by row before resizing anything; repeated
                // calls advance naturally because existing panes reject the
                // positions already claimed in earlier rounds.
                _, fallback_window_height := facade_profile_window_size(profile, structure, face)
                fallback_storeys := facade_floor_count(wall_height)
                if profile.rows_max > 0 do fallback_storeys = min(fallback_storeys, profile.rows_max)
                if fallback_storeys > 1 {
                    fitted_fallback_height :=
                        (wall_height - 2 * 1.45 - f32(fallback_storeys - 1) * .35) /
                        f32(fallback_storeys)
                    fallback_window_height = min(
                        fallback_window_height,
                        max(f32(.75), fitted_fallback_height - .01),
                    )
                }
                fallback_rows := facade_profile_row_count(profile, wall_height, fallback_window_height)
                for _ in 0 ..< 16 {
                    added_round := false
                    for row in 0 ..< fallback_rows {
                        if glazing_area >= minimum_target_area - .001 do break
                        previous_count := layout.count
                        if architecture_opening_layout_add_habitable_row_on_face(
                            &layout,
                            footprint,
                            structure,
                            mass_index,
                            profile,
                            face,
                            row,
                        ) {
                            added := layout.openings[previous_count]
                            glazing_area += added.width * added.height
                            added_round = true
                        }
                    }
                    if glazing_area >= minimum_target_area - .001 || !added_round do break
                }
                // Join culling can remove part of a broad row after bay count
                // has met its nominal ratio, leaving a mostly exposed wall a
                // few percent below its daylight floor. Grow panes vertically
                // only: horizontal door, corner, and neighbor clearances stay
                // untouched. Cap growth at wall heads/sills and adjacent rows.
                height_scale := minimum_target_area / glazing_area
                maximum_height_scale := height_scale
                for opening, opening_index in layout.openings[:layout.count] {
                    if opening.face != face || opening.kind != .Window do continue
                    wall_fit :=
                        2 * min(opening.y, wall_height - opening.y) /
                        max(opening.height, f32(.001))
                    maximum_height_scale = min(maximum_height_scale, wall_fit)
                    for candidate, candidate_index in layout.openings[:layout.count] {
                        if candidate_index <= opening_index ||
                           candidate.face != face ||
                           candidate.kind != .Window {
                            continue
                        }
                        horizontal_overlap :=
                            math.abs(opening.horizontal - candidate.horizontal) <
                            (opening.width + candidate.width) * .5 - .001
                        if !horizontal_overlap do continue
                        row_fit :=
                            2 * math.abs(opening.y - candidate.y) /
                            max(opening.height + candidate.height, f32(.001))
                        maximum_height_scale = min(maximum_height_scale, row_fit)
                    }
                }
                safe_maximum_height_scale := max(f32(1), maximum_height_scale)
                applied_height_scale := min(height_scale, safe_maximum_height_scale)
                if applied_height_scale > 1 {
                    for opening, opening_index in layout.openings[:layout.count] {
                        if opening.face != face || opening.kind != .Window do continue
                        layout.openings[opening_index].height *= applied_height_scale
                    }
                    glazing_area *= applied_height_scale
                }
            }
            target_area := profile.opening_ratio_max * exposed_wall_area
            if glazing_area <= target_area + .001 || glazing_area <= .001 do continue
            scale := f32(math.sqrt(f64(target_area / glazing_area)))
            for opening, opening_index in layout.openings[:layout.count] {
                if opening.face != face || opening.kind != .Window do continue
                layout.openings[opening_index].width *= scale
                layout.openings[opening_index].height *= scale
            }
        }
    }
    opening_layout_reindex_window_columns(&layout)
    return layout
}

architecture_frontage_rotation :: proc(tangent_x, tangent_z, frontage_side: f32) -> f32 {
    rotation := f32(math.atan2(f64(tangent_z), f64(tangent_x)))
    // With local +X along the road tangent, local +Z points along the road's
    // positive normal. Lots on that positive-normal side must turn around so
    // doors, windows, and attached growth face back toward their frontage.
    if frontage_side > 0 do rotation += math.PI
    return rotation
}

@(no_instrumentation)
bougainvillea_maturity :: #force_inline proc(growth_density: f32) -> f32 {
    return plants.maturity_for_species(.Bougainvillea, growth_density)
}

@(no_instrumentation)
bougainvillea_palette :: #force_inline proc(seed: u32) -> int {
    // Structure and vine seeds advance through related arithmetic sequences;
    // mix distant bits before selecting a palette so neighboring plants do
    // not become locked to one flower color.
    mixed := city_hash(int(seed & 0x0000ffff), int(seed >> 16), seed ~ 0xa511e9b3)
    return int(mixed % 3)
}

@(no_instrumentation)
bougainvillea_training_habit :: #force_inline proc(seed: u32) -> int {
    // Alternate between a balanced wall fan and a dominant wind-swept leader.
    // Hashing avoids locking habit to palette or neighboring seed sequences.
    mixed := city_hash(int(seed & 0x0000ffff), int(seed >> 16), seed ~ 0x6d2b79f5)
    return int(mixed % 2)
}

// Visual regression matrix: every palette/habit pair appears once, with an
// even split between planter-rooted and direct-soil plants.
BOUGAINVILLEA_VALIDATION_SEEDS :: [6]u32{2, 15, 0, 4, 12, 8}

@(no_instrumentation)
bougainvillea_planter_rooted :: #force_inline proc(seed: u32) -> bool {
    return seed % 3 != 0
}

@(no_instrumentation)
bougainvillea_flower_tile_base :: #force_inline proc(palette: int) -> int {
    switch ((palette % 3) + 3) % 3 {
    case 0:
        return 8 // magenta
    case 1:
        return 4 // coral
    case 2:
        return 12 // violet
    }
    return 8
}

bougainvillea_bract_color :: proc(palette: int) -> [4]u8 {
    switch ((palette % 3) + 3) % 3 {
    case 0:
        return {213, 65, 132, 255} // magenta
    case 1:
        return {226, 100, 86, 255} // coral
    case 2:
        return {144, 65, 190, 255} // violet
    }
    return {213, 65, 132, 255}
}

@(no_instrumentation)
bougainvillea_bract_value :: #force_inline proc(maturity, node_fraction: f32, variation: int) -> f32 {
    // Protected, older bracts sit deeper in value while fresh terminal growth
    // catches more light. Keep the range narrow enough to preserve palette
    // identity and the source atlas's internal painted shading.
    age_gradient := clamp(node_fraction, 0, 1)
    maturity_lift := clamp(maturity, 0, 1) * .012
    variation_lift := f32(((variation % 4) + 4) % 4) * .009
    return clamp(.895 + age_gradient * .075 + maturity_lift + variation_lift, .895, 1.01)
}

@(no_instrumentation)
bougainvillea_active_branch_count :: #force_inline proc(maturity: f32, available_branches: int) -> int {
    if available_branches <= 0 do return 0
    return min(2 + int(clamp(maturity, 0, 1) * 4.0 + .5), available_branches)
}

bougainvillea_thorn_count :: proc(maturity: f32, available_nodes: int) -> int {
    if available_nodes <= 0 || maturity <= .38 do return 0
    return min(1 + int((clamp(maturity, 0, 1) - .38) * 5.0), available_nodes)
}

@(no_instrumentation)
bougainvillea_fallen_bract_count :: #force_inline proc(maturity: f32) -> int {
    if maturity <= .62 do return 0
    return min(2 + int((clamp(maturity, 0, 1) - .62) * 8.0), 5)
}

@(no_instrumentation)
bougainvillea_cascade_count :: #force_inline proc(maturity: f32) -> int {
    if maturity <= .56 do return 0
    return maturity < .84 ? 1 : 2
}

@(no_instrumentation)
bougainvillea_secondary_leader_strength :: #force_inline proc(maturity: f32) -> f32 {
    strength := clamp((maturity - .46) / .34, 0, 1)
    return strength * strength * (3 - 2 * strength)
}

bougainvillea_woody_compliance :: proc(maturity: f32) -> f32 {
    return plants.woody_wind_compliance(.Bougainvillea, maturity)
}

@(no_instrumentation)
bougainvillea_detail_tier :: #force_inline proc(camera_distance: f32) -> int {
    return plants.detail_tier(camera_distance)
}

@(no_instrumentation)
bougainvillea_crown_detail_fade :: #force_inline proc(camera_distance: f32) -> f32 {
    // Secondary card layers are fully present through the middle distance,
    // then contract smoothly before the far silhouette-only tier begins.
    fade := clamp((112 - camera_distance) / 24, 0, 1)
    return fade * fade * (3 - 2 * fade)
}

@(no_instrumentation)
bougainvillea_branch_flowering :: #force_inline proc(
    maturity, node_fraction: f32,
    seed: u32,
    branch_index: int,
) -> bool {
    clamped_maturity := clamp(maturity, 0, 1)
    bloom_threshold := .82 - clamped_maturity * .26
    if clamped_maturity <= .16 || node_fraction <= bloom_threshold do return false

    // A fully established plant must not become all-green or uniformly
    // flower-covered because of one unlucky seed. Reserve one sheltered upper
    // branch as foliage and guarantee the terminal leader carries bracts.
    if clamped_maturity > .82 {
        if branch_index == 5 do return true
        resting_branch := 1 + int(city_hash(int(seed & 0xffff), int(seed >> 16), seed ~ 0x91e10da5) % 4)
        if branch_index == resting_branch do return false
    }

    bloom_slots := 1 + int(clamped_maturity * 3.99)
    mixed := city_hash(branch_index, int(seed & 0xffff), seed ~ 0x4f1bbcdc)
    return int(mixed % 5) < bloom_slots
}

@(no_instrumentation)
bougainvillea_basal_shoot_count :: #force_inline proc(maturity: f32) -> int {
    if maturity <= .34 do return 0
    return maturity < .78 ? 1 : 2
}

bougainvillea_pruned_stub_count :: proc(maturity: f32) -> int {
    if maturity <= .52 do return 0
    return min(1 + int((clamp(maturity, 0, 1) - .52) * 5.0), 3)
}

@(no_instrumentation)
bougainvillea_root_attachment_x :: #force_inline proc(
    structure: terrain.Structure,
    preferred_x: f32,
    seed: u32,
) -> f32 {
    if structure.kind != .Architecture do return preferred_x
    // Keep the planter or soil pocket outside the central entrance and its
    // immediate approach. Preserve the painted side preference whenever it is
    // already decisive; a seed only breaks an exactly central tie.
    side := preferred_x < 0 ? f32(-1) : f32(1)
    if math.abs(preferred_x) < .001 do side = seed & 1 == 0 ? f32(-1) : f32(1)
    // Compound frontage children can be narrower than the primary mass whose
    // entrance remains visible beside them. Let planters sit just beyond the
    // façade edge beside the plinth, as they commonly do in narrow streets,
    // instead of forcing every root back onto the entrance wall.
    minimum_offset := structure.width * .52
    resolved := side * max(math.abs(preferred_x), minimum_offset)
    return clamp(resolved, -structure.width * .58, structure.width * .58)
}

@(no_instrumentation)
bougainvillea_height_fraction :: #force_inline proc(maturity: f32) -> f32 {
    return .24 + clamp(maturity, 0, 1) * .60
}

bougainvillea_density_at_structure :: proc(
    field: ^[terrain.CITY_DENSITY_SAMPLES]u8,
    structure: terrain.Structure,
) -> f32 {
    if field == nil do return 0
    footprint := max(structure.width, structure.depth) * .42
    cosine, sine := f32(math.cos(f64(structure.rotation))), f32(math.sin(f64(structure.rotation)))
    density_sum: f32
    for sample in -2 ..= 2 {
        local_x := f32(sample) * footprint * .52
        local_z := f32((sample + int(structure.seed % 3)) % 3 - 1) * footprint * .16
        sample_x := structure.center_x + local_x * cosine - local_z * sine
        sample_z := structure.center_z + local_x * sine + local_z * cosine
        density_sum += city_density_sample(field, sample_x, sample_z)
    }
    return density_sum / 5
}

@(no_instrumentation)
bougainvillea_laundry_conflict :: #force_inline proc(
    structure: terrain.Structure,
    growth_density, line_world_y: f32,
) -> bool {
    if structure.kind != .Architecture || growth_density < .035 do return false
    maturity := bougainvillea_maturity(growth_density)
    if maturity <= .16 do return false
    branch_nodes := [6]int{7, 9, 11, 13, 14, 15}
    active_count := bougainvillea_active_branch_count(maturity, len(branch_nodes))
    lowest_node := branch_nodes[len(branch_nodes) - active_count]
    vine_height := structure.height * bougainvillea_height_fraction(maturity)
    crown_floor := structure.base_y + vine_height * f32(lowest_node) / 15 - .65
    crown_ceiling := structure.base_y + min(vine_height + 2.2, structure.height * .94)
    // Laundry hangs below its support line. Reserve enough room for the
    // deepest cloth panel as well as the line itself.
    laundry_drop: f32 = 1.35
    return line_world_y >= crown_floor && line_world_y - laundry_drop <= crown_ceiling
}

@(no_instrumentation)
bougainvillea_laundry_span_conflict :: #force_inline proc(
    structure: terrain.Structure,
    growth_density, line_world_y, start_x, start_z, finish_x, finish_z: f32,
) -> bool {
    if !bougainvillea_laundry_conflict(structure, growth_density, line_world_y) do return false
    facade := architecture_frontage_structure(structure)
    span_x, span_z := finish_x - start_x, finish_z - start_z
    span_length_squared := span_x * span_x + span_z * span_z
    if span_length_squared <= .0001 do return false
    projection := clamp(
        ((facade.center_x - start_x) * span_x + (facade.center_z - start_z) * span_z) / span_length_squared,
        0,
        1,
    )
    closest_x := start_x + span_x * projection
    closest_z := start_z + span_z * projection
    offset_x, offset_z := facade.center_x - closest_x, facade.center_z - closest_z
    // The span endpoint is offset to the façade plane, while center_x/z is
    // the middle of the mass. Include that depth before adding the crown's
    // lateral reach or deep compound masses miss their own laundry anchor.
    crown_radius := facade.depth * .5 + max(facade.width * .42, f32(2.4)) + .55
    return offset_x * offset_x + offset_z * offset_z <= crown_radius * crown_radius
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

Architecture_Mass :: struct {
    local_x, local_z, width, depth, height_scale: f32,
}

Architecture_Footprint :: struct {
    masses: [3]Architecture_Mass,
    count:  int,
}

@(no_instrumentation)
architecture_footprint :: #force_inline proc(structure: terrain.Structure) -> Architecture_Footprint {
    result: Architecture_Footprint
    result.masses[0] = {0, 0, structure.width, structure.depth, 1}
    result.count = 1
    if structure.kind != .Architecture do return result
    identity := architecture_resolve_legacy_identity(structure)
    archetype := identity.archetype
    variant := structure.seed

    if archetype == .Farmstead &&
       structure.width >= 20 &&
       structure.depth >= 18 &&
       structure.height >= ARCHITECTURE_MIN_OPENING_WALL_HEIGHT / .58 &&
       variant % 5 == 0 {
        // A broad farmhouse gains a lower connected work range rather than
        // sharing every domestic courtyard/L variant. The street bar remains
        // the public house; the offset rear range reads as dairy, washhouse,
        // or tool room while retaining an interior passage.
        result.masses[0] = {0, structure.depth * .20, structure.width, structure.depth * .60, 1}
        result.masses[1] = {
            (variant & 1) == 0 ? -structure.width * .25 : structure.width * .25,
            -structure.depth * .22,
            structure.width * .46,
            structure.depth * .56,
            .58,
        }
        result.count = 2
    } else if (archetype == .Dwelling || archetype == .Farmstead) &&
       structure.width >= 26 &&
       structure.depth >= 20 &&
       variant % 8 == 3 {
        // A shallow U around a rear court is reserved for genuinely broad
        // parcels; smaller lots stay legible as houses rather than compounds.
        result.masses[0] = {0, structure.depth * .32, structure.width, max(structure.depth * .36, f32(4.5)), 1}
        result.masses[1] = {
            -structure.width * .36,
            -structure.depth * .08,
            max(structure.width * .28, f32(4.5)),
            max(structure.depth * .64, f32(4.5)),
            .72,
        }
        result.masses[2] = {
            structure.width * .36,
            -structure.depth * .08,
            max(structure.width * .28, f32(4.5)),
            max(structure.depth * .64, f32(4.5)),
            .72,
        }
        result.count = 3
    } else if (archetype == .Dwelling || archetype == .Farmstead) &&
       structure.width >= 18 &&
       structure.depth >= 18 &&
       variant % 8 == 6 {
        // T plan: a broad street range with a centered rear range. Unlike the
        // mirrored L plans this reads as a different silhouette from either
        // side and gives medium-width rural parcels a compound option.
        result.masses[0] = {0, structure.depth * .24, structure.width, structure.depth * .52, 1}
        result.masses[1] = {
            0,
            -structure.depth * .19,
            max(structure.width * .44, f32(4.5)),
            max(structure.depth * .62, f32(4.5)),
            .82,
        }
        result.count = 2
    } else if (archetype == .Dwelling || archetype == .Farmstead) &&
       structure.width >= 12 &&
       structure.depth >= 14 &&
       variant % 4 == 1 {
        // L plan: a street bar with a shorter rear wing.
        result.masses[0] = {0, structure.depth * .25, structure.width, structure.depth * .5, 1}
        result.masses[1] = {
            // % 4 == 1 fixes bit zero, so use the next variant lane to
            // actually mirror successive eligible L plans.
            (variant / 4) & 1 == 0 ? -structure.width * .31 : structure.width * .31,
            -structure.depth * .12,
            max(structure.width * .38, f32(4.5)),
            max(structure.depth * .76, f32(4.5)),
            .78,
        }
        result.count = 2
    } else if archetype == .Mixed_Use_Dwelling && structure.width >= 22 && structure.depth >= 18 && variant % 6 == 5 {
        // Broad mixed-use parcels can wrap two private rear ranges around a
        // small service court. The full-width street bar still carries the
        // shop and upper apartments, preserving the storefront grammar.
        result.masses[0] = {0, structure.depth * .18, structure.width, structure.depth * .64, 1}
        result.masses[1] = {
            -structure.width * .31,
            -structure.depth * .20,
            max(structure.width * .32, f32(4.5)),
            max(structure.depth * .36, f32(4.5)),
            .68,
        }
        result.masses[2] = {
            structure.width * .31,
            -structure.depth * .20,
            max(structure.width * .32, f32(4.5)),
            max(structure.depth * .36, f32(4.5)),
            .68,
        }
        result.count = 3
    } else if archetype == .Mixed_Use_Dwelling && structure.width >= 14 && structure.depth >= 14 {
        // The full-width street range holds the shop and upper rooms; the
        // lower rear wing reads as the private part of the dwelling. Most
        // variants mirror an L; every third uses a centered T-plan.
        result.masses[0] = {0, structure.depth * .18, structure.width, structure.depth * .64, 1}
        result.masses[1] = {
            variant % 3 == 2 ? f32(0) : (variant & 1) == 0 ? -structure.width * .27 : structure.width * .27,
            -structure.depth * .20,
            variant % 3 == 2 ? max(structure.width * .54, f32(4.5)) : max(structure.width * .46, f32(4.5)),
            max(structure.depth * .42, f32(4.5)),
            variant % 3 == 2 ? f32(.76) : f32(.72),
        }
        result.count = 2
    } else if archetype == .Shop_House && structure.width >= 16 && structure.depth >= 14 && variant % 4 == 0 {
        // Shop houses need more than a townhouse silhouette: keep the public
        // sales room across the street edge and attach a lower rear stockroom
        // with a generous internal connection for goods circulation.
        result.masses[0] = {0, structure.depth * .22, structure.width, structure.depth * .56, 1}
        result.masses[1] = {
            // Eligible seeds are multiples of four; their parity cannot
            // select a side. Advance through those eligible variants instead.
            (variant / 4) & 1 == 0 ? -structure.width * .24 : structure.width * .24,
            -structure.depth * .17,
            structure.width * .48,
            structure.depth * .52,
            .70,
        }
        result.count = 2
    } else if (archetype == .Townhouse || archetype == .Shop_House) &&
       structure.width >= 16 &&
       structure.depth >= 16 &&
       variant % 6 == 1 {
        // Street range plus a narrow rear return. Attached buildings therefore
        // vary in depth as well as using the side-to-side stepped composition.
        result.masses[0] = {0, structure.depth * .18, structure.width, structure.depth * .64, 1}
        result.masses[1] = {
            // % 6 == 1 also fixes parity, so derive mirroring from the
            // sequence number among eligible return-plan seeds.
            (variant / 6) & 1 == 0 ? -structure.width * .30 : structure.width * .30,
            -structure.depth * .25,
            max(structure.width * .40, f32(4.5)),
            max(structure.depth * .50, f32(4.5)),
            .76,
        }
        result.count = 2
    } else if (archetype == .Townhouse || archetype == .Shop_House) &&
       structure.width >= 12 &&
       structure.depth >= 12 &&
       variant % 3 == 2 {
        // Stepped plan: two attached bars with unequal depth and height.
        result.masses[0] = {-structure.width * .22, 0, max(structure.width * .56, f32(4.5)), structure.depth, 1}
        result.masses[1] = {
            structure.width * .10,
            -structure.depth * .10,
            max(structure.width * .44, f32(4.5)),
            max(structure.depth * .80, f32(4.5)),
            .72,
        }
        result.count = 2
    } else if archetype == .Post_Office && structure.width >= 24 && structure.depth >= 18 && variant % 4 == 2 {
        // High-volume post offices add a lower parcel/loading annex beside
        // the centered sorting room. It joins the sorting range rather than
        // the public counter hall, keeping back-of-house circulation legible
        // while breaking the repeated civic T-plan silhouette.
        side := (variant & 4) == 0 ? f32(-1) : f32(1)
        parcel_depth := max(structure.depth * .20, f32(4.5))
        result.masses[0] = {0, structure.depth * .20, structure.width, structure.depth * .60, 1}
        result.masses[1] = {0, -structure.depth * .24, structure.width * .54, structure.depth * .52, .72}
        result.masses[2] = {
            side * structure.width * .325,
            -structure.depth * .5 + parcel_depth * .5,
            max(structure.width * .28, f32(4.5)),
            parcel_depth,
            .58,
        }
        result.count = 3
    } else if archetype == .Post_Office && structure.width >= 16 && structure.depth >= 14 {
        // Keep the public counter and post boxes on the street, with a lower
        // sorting/loading range behind. Centering the work range gives mail a
        // direct path from the public hall to the rear service yard.
        result.masses[0] = {0, structure.depth * .20, structure.width, structure.depth * .60, 1}
        result.masses[1] = {0, -structure.depth * .22, structure.width * .56, structure.depth * .56, .72}
        result.count = 2
    } else if archetype == .Clinic && structure.width >= 24 && structure.depth >= 18 && variant % 4 == 2 {
        // A broad clinic can wrap paired recovery wards around a sheltered
        // healing garden. The full-width public waiting/treatment hall stays
        // on the street, while both quieter wings retain deep internal joins
        // and direct rear-yard access.
        result.masses[0] = {0, structure.depth * .22, structure.width, structure.depth * .56, 1}
        result.masses[1] = {
            -structure.width * .35,
            -structure.depth * .18,
            max(structure.width * .30, f32(4.5)),
            max(structure.depth * .52, f32(4.5)),
            .78,
        }
        result.masses[2] = {
            structure.width * .35,
            -structure.depth * .18,
            max(structure.width * .30, f32(4.5)),
            max(structure.depth * .52, f32(4.5)),
            .78,
        }
        result.count = 3
    } else if archetype == .Clinic && structure.width >= 16 && structure.depth >= 14 {
        // Clinics gain a quieter examination/ward return behind the public
        // waiting-room bar. Mirror it by seed so repeated clinics do not all
        // expose the same side wall to their neighboring parcel.
        side := (variant & 1) == 0 ? f32(-1) : f32(1)
        result.masses[0] = {0, structure.depth * .20, structure.width, structure.depth * .60, 1}
        result.masses[1] = {
            side * structure.width * .25,
            -structure.depth * .20,
            structure.width * .50,
            structure.depth * .60,
            .78,
        }
        result.count = 2
    } else if archetype == .Storehouse && structure.width >= 20 && structure.depth >= 16 && variant % 8 == 0 {
        // Storehouses keep a broad street-facing warehouse with an offset,
        // lower loading/packing annex behind it. The shallow rear bar leaves
        // yard space while its deep overlap supports cart-width circulation.
        result.masses[0] = {0, structure.depth * .16, structure.width, structure.depth * .68, 1}
        result.masses[1] = {
            // Multiples of eight are all even; use their ordinal so loading
            // annexes genuinely alternate sides across generated lots.
            (variant / 8) & 1 == 0 ? -structure.width * .22 : structure.width * .22,
            -structure.depth * .25,
            structure.width * .56,
            structure.depth * .42,
            .64,
        }
        result.count = 2
    } else if archetype == .Fishery && structure.width >= 18 && structure.depth >= 14 && variant % 4 == 0 {
        // A waterfront processing hall keeps a broad working frontage while a
        // lower centered rear range reads as smokehouse, cold room, and gear
        // store. Their deep T junction supports a real internal work passage.
        result.masses[0] = {0, structure.depth * .18, structure.width, structure.depth * .64, 1}
        result.masses[1] = {0, -structure.depth * .22, structure.width * .40, structure.depth * .56, .62}
        result.count = 2
    } else if (archetype == .Workshop || archetype == .Storehouse || archetype == .Fishery) &&
       structure.width >= 20 &&
       structure.depth >= 16 &&
       variant % 6 == 4 {
        // A working court edged by two unequal sheds gives larger productive
        // sites a broken, three-part roofline instead of another residential L.
        // Keep orientation independent of both the % 6 court selector and
        // the earlier fishery/storehouse special-plan selectors. Low-bit or
        // ordinal choices collapse to one side for at least one archetype.
        court_side := variant & 16 == 0 ? f32(-1) : f32(1)
        result.masses[0] = {0, -structure.depth * .22, structure.width, structure.depth * .48, 1}
        result.masses[1] = {
            court_side * structure.width * .35,
            structure.depth * .13,
            max(structure.width * .30, f32(4.5)),
            max(structure.depth * .48, f32(4.5)),
            .70,
        }
        result.masses[2] = {
            -court_side * structure.width * .36,
            structure.depth * .06,
            max(structure.width * .28, f32(4.5)),
            max(structure.depth * .34, f32(4.5)),
            .58,
        }
        result.count = 3
    } else if (archetype == .Workshop || archetype == .Storehouse || archetype == .Fishery) &&
       structure.width >= 12 &&
       structure.depth >= 12 &&
       variant % 3 != 0 {
        // Productive buildings use a broad working hall and a lower service
        // wing rather than inheriting residential compound proportions.
        result.masses[0] = {0, -structure.depth * .10, structure.width, structure.depth * .76, 1}
        result.masses[1] = {
            (variant & 1) == 0 ? -structure.width * .30 : structure.width * .30,
            structure.depth * .28,
            max(structure.width * .40, f32(4.5)),
            max(structure.depth * .42, f32(4.5)),
            .68,
        }
        result.count = 2
    } else if archetype == .Barn_Granary &&
       structure.width >= 12 &&
       structure.height >= ARCHITECTURE_MIN_OPENING_WALL_HEIGHT / .58 {
        if structure.depth >= 12 {
            wing_width := max(structure.width * .28, f32(4.5))
            overlap := min(max(f32(2.0), structure.width * .10), wing_width * .45)
            main_width := structure.width - wing_width + overlap
            wing_x := structure.width * .5 - wing_width * .5
            side := (variant & 1) == 0 ? f32(-1) : f32(1)
            result.masses[0] = {-side * (wing_width - overlap) * .5, 0, main_width, structure.depth, 1}
            result.masses[1] = {
                side * wing_x,
                structure.depth * .08,
                wing_width,
                max(structure.depth * .70, f32(4.5)),
                .62,
            }
            result.count = 2
        }
    } else if archetype == .Mill && structure.width >= 9 && structure.depth >= 9 && structure.height >= 5.6 {
        // The 1.28-height inner stage needs enough exposure above the base
        // hall for a sill, a useful vent, and head clearance. Very low mills
        // remain single working halls instead of carrying a sealed roof nub.
        result.masses[0] = {0, 0, structure.width * .78, structure.depth * .78, 1}
        result.masses[1] = {0, 0, max(structure.width * .42, f32(4.5)), max(structure.depth * .42, f32(4.5)), 1.28}
        result.count = 2
    } else if archetype == .Palace_Loggia && structure.width >= 22 && structure.depth >= 18 && variant % 4 == 0 {
        // A palace wraps a rear ceremonial court behind its full-width public
        // street range. The paired wings overlap that range deeply enough for
        // real circulation.
        result.masses[0] = {0, structure.depth * .22, structure.width, structure.depth * .56, 1}
        result.masses[1] = {
            -structure.width * .34,
            -structure.depth * .18,
            structure.width * .32,
            structure.depth * .52,
            .78,
        }
        result.masses[2] = {
            structure.width * .34,
            -structure.depth * .18,
            structure.width * .32,
            structure.depth * .52,
            .78,
        }
        result.count = 3
    } else if archetype == .Monastery && structure.width >= 22 && structure.depth >= 18 && variant % 4 == 0 {
        // A monastery uses the inverse C-plan: a full-width communal range at
        // the rear and paired cell ranges reaching the street around a quiet,
        // front-open cloister court. This no longer duplicates the palace plan.
        result.masses[0] = {0, -structure.depth * .32, structure.width, structure.depth * .36, 1}
        result.masses[1] = {
            -structure.width * .34,
            structure.depth * .08,
            structure.width * .32,
            structure.depth * .84,
            .78,
        }
        result.masses[2] = {
            structure.width * .34,
            structure.depth * .08,
            structure.width * .32,
            structure.depth * .84,
            .78,
        }
        result.count = 3
    } else if archetype == .Market_Hall &&
       structure.width >= 22 &&
       structure.depth >= 18 &&
       variant % 4 == 2 {
        // A basilica market variant pairs a tall, full-depth trading nave
        // with lower permanent-stall aisles. The ten-percent-width joins
        // keep both aisles connected while leaving the nave wall exposed
        // above their roofs for a useful clerestory band.
        result.masses[0] = {0, 0, structure.width * .56, structure.depth, 1}
        result.masses[1] = {
            -structure.width * .34,
            -structure.depth * .06,
            structure.width * .32,
            structure.depth * .88,
            .68,
        }
        result.masses[2] = {
            structure.width * .34,
            -structure.depth * .06,
            structure.width * .32,
            structure.depth * .88,
            .68,
        }
        result.count = 3
    } else if archetype == .Market_Hall && structure.width >= 22 && structure.depth >= 18 {
        // A broad market gets a centered rear trading hall, producing a T-plan
        // with a full-width public frontage instead of a domestic-looking L.
        result.masses[0] = {0, structure.depth * .20, structure.width, structure.depth * .60, 1}
        result.masses[1] = {0, -structure.depth * .20, structure.width * .56, structure.depth * .60, .82}
        result.count = 2
    } else if archetype == .Harbor_Office && structure.width >= 22 && structure.depth >= 18 {
        // Large quay offices combine a public street counter with a taller
        // dispatch wing and a low records/gear range around an asymmetric
        // working yard. Both rear ranges overlap the street bar deeply enough
        // for real circulation while leaving the yard visibly open.
        side := (variant & 1) == 0 ? f32(-1) : f32(1)
        result.masses[0] = {0, structure.depth * .22, structure.width, structure.depth * .56, 1}
        result.masses[1] = {
            side * structure.width * .31,
            -structure.depth * .18,
            structure.width * .38,
            structure.depth * .52,
            .82,
        }
        result.masses[2] = {
            -side * structure.width * .37,
            -structure.depth * .16,
            structure.width * .26,
            structure.depth * .44,
            .58,
        }
        result.count = 3
    } else if archetype == .Palace_Loggia ||
       archetype == .Market_Hall ||
       archetype == .Harbor_Office ||
       archetype == .Monastery {
        result.masses[0] = {0, structure.depth * .18, structure.width, structure.depth * .64, 1}
        if structure.width >= 12 && structure.depth >= 12 {
            result.masses[1] = {
                (variant & 1) == 0 ? -structure.width * .30 : structure.width * .30,
                -structure.depth * .20,
                max(structure.width * .40, f32(4.5)),
                max(structure.depth * .56, f32(4.5)),
                .78,
            }
            result.count = 2
        }
    } else if archetype == .Campanile {
        // A campanile is a freestanding vertical landmark, not a full-parcel
        // hall with a small crown. Keep its square shaft centered within the
        // authored lot and cap extreme broad-lot growth at eight metres.
        short_side := min(structure.width, structure.depth)
        if short_side >= ARCHITECTURE_MIN_OPENING_FACE_SPAN {
            minimum_span := min(short_side, f32(4.5))
            maximum_span := min(short_side, f32(8))
            tower_span := clamp(short_side * .62, minimum_span, maximum_span)
            result.masses[0] = {0, 0, tower_span, tower_span, 1}
        }
    } else if archetype == .Church &&
       structure.width >= 9 &&
       structure.depth >= 12 &&
       structure.height >= ARCHITECTURE_MIN_OPENING_WALL_HEIGHT / .72 {
        // Build an actual Latin-cross plan instead of laying a shallow wide
        // roof bar over a full-depth rectangle. The nave reaches the street,
        // the transept connects both arms behind its midpoint, and a lower
        // chancel closes the rear of the lot. Size the chancel against the
        // transept's rear edge as well as the lot so every compound church
        // retains a two-metre internal passage rather than merely touching.
        // Delay the cross plan until its lowest transept walls can actually
        // carry openings.
        result.masses[0] = {0, structure.depth * .15, max(structure.width * .60, f32(4.5)), structure.depth * .70, 1}
        result.masses[1] = {0, -structure.depth * .10, structure.width, structure.depth * .42, .72}
        chancel_depth := max(
            max(structure.depth * .32, f32(4.8)),
            structure.depth * .19 + 2.05,
        )
        result.masses[2] = {
            0,
            -structure.depth * .5 + chancel_depth * .5,
            max(structure.width * .48, f32(4.5)),
            chancel_depth,
            .86,
        }
        result.count = 3
    } else if archetype == .Fortress_Gate &&
       structure.width >= 12 &&
       structure.depth >= 12 &&
       structure.height >= ARCHITECTURE_MIN_OPENING_WALL_HEIGHT / .68 {
        // Two freestanding towers read as props, not a usable gate complex.
        // A lower full-width guard range joins them across the rear, leaving
        // the central street approach open as a shallow protected court. Do
        // not author the compound until that .68-height guard range can carry
        // its court door; low fortified buildings remain one usable range.
        tower_z := structure.depth * .075
        tower_depth := structure.depth * .85
        tower_width := max(structure.width * .375, f32(4.5))
        tower_x := structure.width * .5 - tower_width * .5
        result.masses[0] = {
            -tower_x,
            tower_z,
            tower_width,
            tower_depth,
            1,
        }
        result.masses[1] = {
            tower_x,
            tower_z,
            tower_width,
            tower_depth,
            1,
        }
        guard_depth := max(structure.depth * .30, f32(4.5))
        result.masses[2] = {0, -structure.depth * .5 + guard_depth * .5, structure.width, guard_depth, .68}
        result.count = 3
    } else if archetype == .Cycladic_Bell && structure.width >= 8 {
        // A Cycladic bell landmark is a compact belfry, not a parcel-depth
        // hall beneath a tower crown. Constrain both axes while retaining a
        // slightly broader whitewashed front wall.
        bell_width := clamp(structure.width * .70, f32(4.5), min(structure.width, f32(8.0)))
        minimum_depth := min(structure.depth, f32(4.5))
        maximum_depth := min(structure.depth, f32(6.5))
        bell_depth := clamp(structure.depth * .48, minimum_depth, maximum_depth)
        result.masses[0] = {0, 0, bell_width, bell_depth, 1}
    }
    if result.count > 1 {
        for mass in result.masses[:result.count] {
            if structure.height * mass.height_scale >= ARCHITECTURE_MIN_OPENING_WALL_HEIGHT do continue
            // Compound ranges represent usable rooms, not roof decoration.
            // If even one authored attachment is too low for the shared door,
            // window, and vent grammar, retain the original full-lot range
            // until the building is tall enough to support the whole plan.
            result.masses[0] = {0, 0, structure.width, structure.depth, 1}
            result.count = 1
            break
        }
    }
    return result
}

@(no_instrumentation)
architecture_frontage_mass_index :: #force_inline proc(structure: terrain.Structure) -> int {
    footprint := architecture_footprint(structure)
    if footprint.count <= 1 do return 0
    identity := architecture_resolve_legacy_identity(structure)
    if identity.archetype == .Monastery &&
       footprint.count == 3 &&
       footprint.masses[0].local_z < footprint.masses[1].local_z {
        // The open cloister court is the monastery's approach. Keep its main
        // door on the communal range facing into that court instead of placing
        // it arbitrarily on one of the symmetric street-reaching cell wings.
        return 0
    }
    if identity.archetype == .Fortress_Gate && footprint.count == 3 {
        // The two towers project farthest, but neither owns a doorway. The
        // full-width rear guard range closes the central court and carries its
        // actual entrance, so paths and façade consumers must target it.
        return 2
    }
    if (identity.archetype == .Workshop || identity.archetype == .Storehouse || identity.archetype == .Fishery) &&
       footprint.count >= 2 {
        // Productive compounds are organized by their broad working hall.
        // A projecting low service wing (or either shed defining a working
        // court) must not steal the entrance and façade attachments merely
        // because its roof edge reaches slightly farther toward the street.
        return 0
    }
    best_index := 0
    best_front := f32(-1.0e20)
    for mass, mass_index in footprint.masses[:footprint.count] {
        // Architecture façades are rendered on +local-Z. Choose the mass
        // whose front plane reaches farthest in that direction so attached
        // details remain visible instead of landing behind a projecting wing.
        front := mass.local_z + mass.depth * .5
        if front > best_front {
            best_front = front
            best_index = mass_index
        }
    }
    return best_index
}

@(no_instrumentation)
architecture_frontage_structure :: #force_inline proc(structure: terrain.Structure) -> terrain.Structure {
    result := structure
    if structure.kind != .Architecture do return result
    footprint := architecture_footprint(structure)
    if footprint.count <= 0 do return result
    frontage_index := architecture_frontage_mass_index(structure)
    frontage_mass := footprint.masses[frontage_index]
    result.center_x, result.center_z = architecture_mass_world(structure, frontage_mass)
    result.width = frontage_mass.width
    result.depth = frontage_mass.depth
    // Frontage consumers attach to rendered wall geometry, not terrain sample
    // resolution. Inflating a compact 4.8 m office to BASE_CELL_SIZE placed
    // vines, laundry, and other façade-dependent details above its roof.
    result.height = max(f32(0), structure.height * frontage_mass.height_scale)
    result.seed = structure.seed + u32(frontage_index * 747796405)
    return result
}

city_bounds_point :: proc(x, z, radius: f32) -> City_Bounds {
    return {x - radius, z - radius, x + radius, z + radius, true}
}

city_bounds_union :: proc(a, b: City_Bounds) -> City_Bounds {
    if !a.valid do return b
    if !b.valid do return a
    return {min(a.min_x, b.min_x), min(a.min_z, b.min_z), max(a.max_x, b.max_x), max(a.max_z, b.max_z), true}
}

city_bounds_expand :: proc(bounds: City_Bounds, amount: f32) -> City_Bounds {
    if !bounds.valid do return bounds
    return {bounds.min_x - amount, bounds.min_z - amount, bounds.max_x + amount, bounds.max_z + amount, true}
}

city_bounds_contains :: proc(bounds: City_Bounds, x, z: f32) -> bool {
    return bounds.valid && x >= bounds.min_x && x <= bounds.max_x && z >= bounds.min_z && z <= bounds.max_z
}

@(no_instrumentation)
city_density_index :: #force_inline proc(x, z: int) -> int {
    return z * terrain.RING_RESOLUTION + x
}

city_density_world_position :: proc(x, z: int) -> (f32, f32) {
    half := f32(terrain.RING_RESOLUTION - 1) * .5
    return (f32(x) - half) * terrain.BASE_CELL_SIZE, (f32(z) - half) * terrain.BASE_CELL_SIZE
}

city_density_bounds :: proc(field: ^[terrain.CITY_DENSITY_SAMPLES]u8) -> City_Bounds {
    if field == nil do return {}
    bounds: City_Bounds
    for z in 0 ..< terrain.RING_RESOLUTION {
        for x in 0 ..< terrain.RING_RESOLUTION {
            if field[city_density_index(x, z)] == 0 do continue
            world_x, world_z := city_density_world_position(x, z)
            point := City_Bounds{world_x, world_z, world_x, world_z, true}
            bounds = city_bounds_union(bounds, point)
        }
    }
    if bounds.valid do bounds = city_bounds_expand(bounds, terrain.BASE_CELL_SIZE * 2)
    return bounds
}

@(no_instrumentation)
city_density_sample :: #force_inline proc(field: ^[terrain.CITY_DENSITY_SAMPLES]u8, world_x, world_z: f32) -> f32 {
    if field == nil do return 0
    half := f32(terrain.RING_RESOLUTION - 1) * .5
    gx := world_x / terrain.BASE_CELL_SIZE + half
    gz := world_z / terrain.BASE_CELL_SIZE + half
    x0 := clamp(int(math.floor(f64(gx))), 0, terrain.RING_RESOLUTION - 1)
    z0 := clamp(int(math.floor(f64(gz))), 0, terrain.RING_RESOLUTION - 1)
    x1 := min(x0 + 1, terrain.RING_RESOLUTION - 1)
    z1 := min(z0 + 1, terrain.RING_RESOLUTION - 1)
    tx, tz := clamp(gx - f32(x0), 0, 1), clamp(gz - f32(z0), 0, 1)
    a := f32(field[city_density_index(x0, z0)]) * (1 - tx) + f32(field[city_density_index(x1, z0)]) * tx
    b := f32(field[city_density_index(x0, z1)]) * (1 - tx) + f32(field[city_density_index(x1, z1)]) * tx
    return (a * (1 - tz) + b * tz) / 255
}

city_density_stamp :: proc(
    field: ^[terrain.CITY_DENSITY_SAMPLES]u8,
    world_x, world_z, radius, strength, hardness: f32,
    erase: bool = false,
) -> City_Bounds {
    if field == nil || radius <= 0 || strength <= 0 do return {}
    inner := radius * clamp(hardness, 0, 1)
    half := f32(terrain.RING_RESOLUTION - 1) * .5
    min_x := clamp(
        int(math.floor(f64((world_x - radius) / terrain.BASE_CELL_SIZE + half))),
        0,
        terrain.RING_RESOLUTION - 1,
    )
    max_x := clamp(
        int(math.ceil(f64((world_x + radius) / terrain.BASE_CELL_SIZE + half))),
        0,
        terrain.RING_RESOLUTION - 1,
    )
    min_z := clamp(
        int(math.floor(f64((world_z - radius) / terrain.BASE_CELL_SIZE + half))),
        0,
        terrain.RING_RESOLUTION - 1,
    )
    max_z := clamp(
        int(math.ceil(f64((world_z + radius) / terrain.BASE_CELL_SIZE + half))),
        0,
        terrain.RING_RESOLUTION - 1,
    )
    for z in min_z ..= max_z {
        for x in min_x ..= max_x {
            px, pz := city_density_world_position(x, z)
            dx, dz := px - world_x, pz - world_z
            distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
            if distance > radius do continue
            falloff: f32 = 1
            if distance > inner && radius > inner {
                t := clamp((distance - inner) / (radius - inner), 0, 1)
                falloff = 1 - t * t * (3 - 2 * t)
            }
            index := city_density_index(x, z)
            delta := int(math.round(f64(clamp(strength, 0, 1) * falloff * 255)))
            value := int(field[index])
            value += erase ? -delta : delta
            field[index] = u8(clamp(value, 0, 255))
        }
    }
    return city_bounds_point(world_x, world_z, radius)
}

@(no_instrumentation)
city_hash :: #force_inline proc(x, z: int, seed: u32) -> u32 {
    value := seed ~ (u32(i32(x)) * 0x9e3779b9) ~ (u32(i32(z)) * 0x85ebca6b)
    value = (value ~ (value >> 16)) * 0x7feb352d
    value = (value ~ (value >> 15)) * 0x846ca68b
    return value ~ (value >> 16)
}

city_hash_unit :: proc(x, z: int, seed: u32, lane: u32 = 0) -> f32 {
    return f32(city_hash(x, z, seed + lane * 0x9e3779b9) & 0x00ffffff) / f32(0x01000000)
}

City_Road_Frontage :: struct {
    found:                bool,
    distance:             f32,
    point_x, point_z:     f32,
    tangent_x, tangent_z: f32,
    clearance:            f32,
}

city_nearest_road_frontage :: proc(graph: ^roads.Graph, x, z: f32) -> City_Road_Frontage {
    hit := City_Road_Frontage {
        distance = f32(1.0e20),
    }
    if graph == nil do return hit
    for edge in graph.edges[:graph.edge_count] {
        previous := roads.edge_point(graph, edge, 0)
        for sample in 1 ..= 32 {
            current := roads.edge_point(graph, edge, f32(sample) / 32)
            vx, vz := current.x - previous.x, current.z - previous.z
            length_sq := vx * vx + vz * vz
            if length_sq > .0001 {
                amount := clamp(((x - previous.x) * vx + (z - previous.z) * vz) / length_sq, 0, 1)
                px, pz := previous.x + vx * amount, previous.z + vz * amount
                dx, dz := x - px, z - pz
                candidate := f32(math.sqrt(f64(dx * dx + dz * dz)))
                if candidate < hit.distance {
                    length := f32(math.sqrt(f64(length_sq)))
                    hit = {
                        found     = true,
                        distance  = candidate,
                        point_x   = px,
                        point_z   = pz,
                        tangent_x = vx / length,
                        tangent_z = vz / length,
                        clearance = edge.half_width + edge.shoulder_width + 2,
                    }
                }
            }
            previous = current
        }
    }
    return hit
}

city_nearest_road :: proc(
    graph: ^roads.Graph,
    x, z: f32,
) -> (
    found: bool,
    distance, tangent_x, tangent_z, clearance: f32,
) {
    if graph == nil do return
    hit := city_nearest_road_frontage(graph, x, z)
    found, distance = hit.found, hit.distance
    tangent_x, tangent_z, clearance = hit.tangent_x, hit.tangent_z, hit.clearance
    for node in graph.nodes[:graph.node_count] {
        dx, dz := x - node.position.x, z - node.position.z
        candidate := f32(math.sqrt(f64(dx * dx + dz * dz)))
        if candidate - node.junction_radius < distance - clearance {
            found, distance = true, candidate
            tangent_x, tangent_z = 1, 0
            clearance = node.junction_radius + 2
        }
    }
    return
}

@(no_instrumentation)
architecture_mass_world :: #force_inline proc(structure: terrain.Structure, mass: Architecture_Mass) -> (x, z: f32) {
    cosine, sine := f32(math.cos(f64(structure.rotation))), f32(math.sin(f64(structure.rotation)))
    return structure.center_x + mass.local_x * cosine - mass.local_z * sine,
        structure.center_z + mass.local_x * sine + mass.local_z * cosine
}

architecture_mass_overlaps :: proc(
    a: terrain.Structure,
    am: Architecture_Mass,
    b: terrain.Structure,
    bm: Architecture_Mass,
    padding: f32,
) -> bool {
    ax, az := architecture_mass_world(a, am)
    bx, bz := architecture_mass_world(b, bm)
    dx, dz := bx - ax, bz - az
    ac, as := f32(math.cos(f64(a.rotation))), f32(math.sin(f64(a.rotation)))
    bc, bs := f32(math.cos(f64(b.rotation))), f32(math.sin(f64(b.rotation)))
    axes := [4][2]f32{{ac, as}, {-as, ac}, {bc, bs}, {-bs, bc}}
    for axis in axes {
        distance := math.abs(dx * axis[0] + dz * axis[1])
        ar :=
            am.width * .5 * math.abs(ac * axis[0] + as * axis[1]) +
            am.depth * .5 * math.abs(-as * axis[0] + ac * axis[1])
        br :=
            bm.width * .5 * math.abs(bc * axis[0] + bs * axis[1]) +
            bm.depth * .5 * math.abs(-bs * axis[0] + bc * axis[1])
        if distance >= ar + br + padding do return false
    }
    return true
}

city_structure_overlaps :: proc(a, b: terrain.Structure, padding: f32 = 1.5) -> bool {
    af, bf := architecture_footprint(a), architecture_footprint(b)
    for am in af.masses[:af.count] {
        for bm in bf.masses[:bf.count] {
            if architecture_mass_overlaps(a, am, b, bm, padding) do return true
        }
    }
    return false
}

city_accent_site_clear :: proc(project: ^terrain.Project, x, z, radius: f32, padding: f32 = 1.5) -> bool {
    if project == nil do return false
    clearance := max(radius + padding, f32(0))
    for structure in project.structures[:project.structure_count] {
        if structure.kind != .Architecture do continue
        cosine, sine := math.cos(structure.rotation), math.sin(structure.rotation)
        footprint := architecture_footprint(structure)
        for mass in footprint.masses[:footprint.count] {
            mass_x, mass_z := architecture_mass_world(structure, mass)
            dx, dz := x - mass_x, z - mass_z
            local_x := dx * cosine + dz * sine
            local_z := -dx * sine + dz * cosine
            outside_x := max(math.abs(local_x) - mass.width * .5, f32(0))
            outside_z := max(math.abs(local_z) - mass.depth * .5, f32(0))
            if outside_x * outside_x + outside_z * outside_z < clearance * clearance do return false
        }
    }
    return true
}

city_structure_site_valid :: proc(project: ^terrain.Project, structure: ^terrain.Structure) -> bool {
    if project == nil || structure == nil do return false
    lowest, highest_coarse := architecture_foundation_height_range(project, structure^, false)
    if lowest <= project.sea_level + .15 do return false
    allowed_relief := max(f32(2.5), min(structure.width, structure.depth) * .12)
    if highest_coarse - lowest > allowed_relief do return false
    _, highest := architecture_foundation_height_range(project, structure^)
    structure.base_y = highest
    return true
}

architecture_mass_height_range :: proc(
    project: ^terrain.Project,
    structure: terrain.Structure,
) -> (
    lowest, highest: f32,
) {
    if project == nil do return structure.base_y, structure.base_y
    cosine, sine := f32(math.cos(f64(structure.rotation))), f32(math.sin(f64(structure.rotation)))
    lowest = f32(1.0e20)
    highest = f32(-1.0e20)
    // A center/corner/edge-midpoint probe misses narrow ridges beneath long
    // façades. Seat the mass from a fine grid over its complete footprint so
    // no section of frontage can be generated below the visible ground.
    sample_spacing := terrain.FINE_CELL_SIZE
    x_intervals := clamp(int(math.ceil(f64(structure.width / sample_spacing))), 1, 128)
    z_intervals := clamp(int(math.ceil(f64(structure.depth / sample_spacing))), 1, 128)
    for z_index in 0 ..= z_intervals {
        local_z := -structure.depth * .5 + structure.depth * f32(z_index) / f32(z_intervals)
        for x_index in 0 ..= x_intervals {
            local_x := -structure.width * .5 + structure.width * f32(x_index) / f32(x_intervals)
            px := structure.center_x + local_x * cosine - local_z * sine
            pz := structure.center_z + local_x * sine + local_z * cosine
            height := terrain.sample_height(project, 0, px, pz)
            lowest, highest = min(lowest, height), max(highest, height)
        }
    }
    return
}

architecture_foundation_height_range :: proc(
    project: ^terrain.Project,
    structure: terrain.Structure,
    dense: bool = true,
) -> (
    lowest, highest: f32,
) {
    if project == nil do return structure.base_y, structure.base_y
    lowest = f32(1.0e20)
    highest = f32(-1.0e20)
    footprint := architecture_footprint(structure)
    for mass in footprint.masses[:footprint.count] {
        child := structure
        child.center_x, child.center_z = architecture_mass_world(structure, mass)
        child.width, child.depth = mass.width, mass.depth
        mass_lowest, mass_highest: f32
        if dense {
            mass_lowest, mass_highest = architecture_mass_height_range(project, child)
        } else {
            cosine, sine := f32(math.cos(f64(child.rotation))), f32(math.sin(f64(child.rotation)))
            half_width, half_depth := child.width * .5, child.depth * .5
            points := [9][2]f32 {
                {0, 0},
                {-half_width, -half_depth},
                {0, -half_depth},
                {half_width, -half_depth},
                {half_width, 0},
                {half_width, half_depth},
                {0, half_depth},
                {-half_width, half_depth},
                {-half_width, 0},
            }
            mass_lowest, mass_highest = f32(1.0e20), f32(-1.0e20)
            for point in points {
                px := child.center_x + point[0] * cosine - point[1] * sine
                pz := child.center_z + point[0] * sine + point[1] * cosine
                height := terrain.sample_height(project, 0, px, pz)
                mass_lowest, mass_highest = min(mass_lowest, height), max(mass_highest, height)
            }
        }
        lowest, highest = min(lowest, mass_lowest), max(highest, mass_highest)
    }
    return
}

city_structure_road_clear :: proc(graph: ^roads.Graph, structure: ^terrain.Structure) -> bool {
    if graph == nil || structure == nil do return false
    cosine, sine := f32(math.cos(f64(structure.rotation))), f32(math.sin(f64(structure.rotation)))
    footprint := architecture_footprint(structure^)
    for mass in footprint.masses[:footprint.count] {
        half_width, half_depth := mass.width * .5, mass.depth * .5
        samples := [9][2]f32 {
            {mass.local_x, mass.local_z},
            {mass.local_x - half_width, mass.local_z - half_depth},
            {mass.local_x, mass.local_z - half_depth},
            {mass.local_x + half_width, mass.local_z - half_depth},
            {mass.local_x + half_width, mass.local_z},
            {mass.local_x + half_width, mass.local_z + half_depth},
            {mass.local_x, mass.local_z + half_depth},
            {mass.local_x - half_width, mass.local_z + half_depth},
            {mass.local_x - half_width, mass.local_z},
        }
        for sample in samples {
            x := structure.center_x + sample[0] * cosine - sample[1] * sine
            z := structure.center_z + sample[0] * sine + sample[1] * cosine
            found, distance, _, _, clearance := city_nearest_road(graph, x, z)
            if found && distance < clearance do return false
        }
    }
    return true
}

city_plan_density_grid :: proc(
    project: ^terrain.Project,
    field: ^[terrain.CITY_DENSITY_SAMPLES]u8,
    rebuild_bounds: City_Bounds,
    seed: u32 = 0xA71D3,
) -> City_Plan {
    plan: City_Plan
    if project == nil || field == nil || !rebuild_bounds.valid do return plan
    cell := terrain.BASE_CELL_SIZE * 1.18
    min_x := int(math.floor(f64(rebuild_bounds.min_x / cell))) - 1
    max_x := int(math.ceil(f64(rebuild_bounds.max_x / cell))) + 1
    min_z := int(math.floor(f64(rebuild_bounds.min_z / cell))) - 1
    max_z := int(math.ceil(f64(rebuild_bounds.max_z / cell))) + 1

    // Visit dense candidates first so contested footprints belong to the
    // strongest town centers rather than whichever grid coordinate came first.
    for band in 0 ..< 4 {
        band_low := f32(3 - band) * .25
        band_high := band_low + .25
        for gz in min_z ..= max_z {
            for gx in min_x ..= max_x {
                jitter_x := (city_hash_unit(gx, gz, seed, 1) - .5) * cell * .72
                jitter_z := (city_hash_unit(gx, gz, seed, 2) - .5) * cell * .72
                x, z := (f32(gx) + .5) * cell + jitter_x, (f32(gz) + .5) * cell + jitter_z
                if !city_bounds_contains(rebuild_bounds, x, z) do continue
                density := city_density_sample(field, x, z)
                if density < .08 || density < band_low || (band < 3 && density >= band_high) do continue
                probability := clamp((density - .05) * 1.08, 0, 1)
                if city_hash_unit(gx, gz, seed, 3) > probability do continue

                compact := density * density
                width := 22 + city_hash_unit(gx, gz, seed, 4) * 15 - compact * 8
                depth := 15 + city_hash_unit(gx, gz, seed, 5) * 11 - compact * 4
                building_seed := city_hash(gx, gz, seed)
                height := city_building_height(width, depth, density, building_seed)
                anchor := density > .85 && city_hash_unit(gx, gz, seed, 7) > .94
                if anchor do height = 60 + city_hash_unit(gx, gz, seed, 8) * 14
                rotation := (city_hash_unit(gx, gz, seed, 9) - .5) * .65

                frontage := city_nearest_road_frontage(&project.road_graph, x, z)
                if frontage.found && frontage.distance < 96 {
                    rotation =
                        f32(math.atan2(f64(frontage.tangent_z), f64(frontage.tangent_x))) +
                        (city_hash_unit(gx, gz, seed, 10) - .5) * .08

                    // Preserve the candidate's side of the street, but derive
                    // its actual frontage from the road curve. This produces
                    // coherent street walls without making the road package
                    // aware of product-specific building rules.
                    normal_x, normal_z := -frontage.tangent_z, frontage.tangent_x
                    side := (x - frontage.point_x) * normal_x + (z - frontage.point_z) * normal_z
                    if math.abs(side) < .001 {
                        side = city_hash_unit(gx, gz, seed, 11) < .5 ? -1 : 1
                    }
                    side = side < 0 ? -1 : 1
                    if side > 0 do rotation += math.PI
                    setback := 2.5 + (1 - density) * 4
                    normal_extent :=
                        math.abs(f32(math.sin(f64(rotation))) * width * .5) +
                        math.abs(f32(math.cos(f64(rotation))) * depth * .5)
                    frontage_offset := frontage.clearance + normal_extent + setback
                    x = frontage.point_x + normal_x * side * frontage_offset
                    z = frontage.point_z + normal_z * side * frontage_offset
                    if !city_bounds_contains(rebuild_bounds, x, z) do continue
                } else {
                    gradient_x := city_density_sample(field, x + cell, z) - city_density_sample(field, x - cell, z)
                    gradient_z := city_density_sample(field, x, z + cell) - city_density_sample(field, x, z - cell)
                    if gradient_x * gradient_x + gradient_z * gradient_z > .001 {
                        rotation =
                            f32(math.atan2(f64(gradient_z), f64(gradient_x))) +
                            math.PI * .5 +
                            (city_hash_unit(gx, gz, seed, 10) - .5) * .35
                    }
                }

                structure := terrain.structure_make(x, z, width, depth, 0, height)
                structure.height = height
                structure.kind = .Architecture
                structure.rotation = rotation
                structure.seed = building_seed
                mercantile_frontage := frontage.found && density >= .45 && int((building_seed >> 11) % 8) <= 1
                structure.building = architecture_identity(
                    {
                        tissue = mercantile_frontage ? Context_Tissue.Mercantile : Context_Tissue.Unspecified,
                        density = density,
                        attached = density >= .68,
                        frontage = width,
                        depth = depth,
                        route = frontage.found ? Context_Route.Street : Context_Route.Unspecified,
                        landmark_kind = anchor ? buildings.Landmark_Kind.Campanile : buildings.Landmark_Kind.None,
                        purpose_explicit = false,
                    },
                    building_seed,
                )
                structure.color = architecture_color(structure.seed, anchor)
                if !city_structure_road_clear(&project.road_graph, &structure) do continue
                if !city_structure_site_valid(project, &structure) do continue

                overlaps := false
                for existing in project.structures[:project.structure_count] {
                    if existing.kind == .Architecture &&
                       city_bounds_contains(rebuild_bounds, existing.center_x, existing.center_z) {
                        continue
                    }
                    if city_structure_overlaps(structure, existing) {
                        overlaps = true
                        break
                    }
                }
                if overlaps do continue
                for existing in plan.structures[:plan.count] {
                    if city_structure_overlaps(structure, existing, 1 + (1 - density) * 5) {
                        overlaps = true
                        break
                    }
                }
                if overlaps do continue
                append(&plan.structures, structure)
                plan.count += 1
            }
        }
    }
    return plan
}

city_building_height :: proc(width, depth, density: f32, seed: u32) -> f32 {
    variation := f32(seed & 255) / 255
    height := 9 + density * 42 + variation * (5 + density * 5)

    // Broad footprints are not exclusively multi-storey town blocks. Keep a
    // seed-stable share of them at one façade row so painted towns can also
    // produce workshops, markets, warehouses, and courtyard houses.
    broad_footprint := width >= 22 || width * depth >= 520
    single_floor_variant := ((seed >> 8) & 255) < 112
    if broad_footprint && single_floor_variant {
        // A tall workshop/hall still uses one façade row. Keep its mass just
        // below the two-storey rounding boundary instead of overloading the
        // global height-to-row mapping with an archetype-specific exception.
        return 7.1
    }
    return facade_fitted_height(height)
}

city_plan_add_parcel_building :: proc(
    plan: ^City_Plan,
    project: ^terrain.Project,
    bounds: City_Bounds,
    center_x, center_z, tangent_x, tangent_z, frontage_side, frontage, depth, density: f32,
    seed: u32,
    alley_frontage: bool,
) {
    if plan == nil || project == nil do return
    if density < .08 || !city_bounds_contains(bounds, center_x, center_z) do return
    tangent_length := f32(math.sqrt(f64(tangent_x * tangent_x + tangent_z * tangent_z)))
    if tangent_length <= .001 do return
    tx, tz := tangent_x / tangent_length, tangent_z / tangent_length
    normal_x, normal_z := -tz, tx
    rotation := architecture_frontage_rotation(tx, tz, frontage_side)
    lot_frontage := clamp(frontage, f32(8), f32(32))
    lot_depth := clamp(depth, f32(13), f32(36))
    setback_front := alley_frontage ? f32(1.2) : 1.0 + (1 - density) * 4.0
    setback_side := density > .72 ? f32(.12) : 1.0 + (1 - density) * 2.2
    width := max(terrain.BASE_CELL_SIZE, lot_frontage - setback_side * 2)
    building_depth := max(terrain.BASE_CELL_SIZE, lot_depth - setback_front - (1 - density) * 4)
    height := city_building_height(width, building_depth, density, seed)
    anchor := density > .85 && ((seed >> 8) & 255) > 244
    if anchor do height = 60 + f32((seed >> 16) & 255) / 255 * 14

    structure := terrain.structure_make(center_x, center_z, width, building_depth, 0, height)
    structure.height = height
    structure.kind = .Architecture
    structure.rotation = rotation
    structure.seed = seed
    mercantile_frontage := !alley_frontage && density >= .45 && int((seed >> 11) % 8) <= 1
    structure.building = architecture_identity(
        {
            tissue = mercantile_frontage ? Context_Tissue.Mercantile : Context_Tissue.Unspecified,
            density = density,
            attached = density > .72,
            frontage = width,
            depth = building_depth,
            frontage_side = frontage_side,
            route = alley_frontage ? Context_Route.Alley : Context_Route.Street,
            landmark_kind = anchor ? buildings.Landmark_Kind.Campanile : buildings.Landmark_Kind.None,
            purpose_explicit = false,
        },
        seed,
    )
    structure.color = architecture_color(seed, anchor)
    if !city_structure_road_clear(&project.road_graph, &structure) do return
    if !city_structure_site_valid(project, &structure) do return
    for existing in project.structures[:project.structure_count] {
        if existing.kind == .Architecture && city_bounds_contains(bounds, existing.center_x, existing.center_z) do continue
        if city_structure_overlaps(structure, existing) do return
    }
    separation := density > .72 ? f32(.05) : 1 + (1 - density) * 4
    for existing in plan.structures[:plan.count] {
        if city_structure_overlaps(structure, existing, separation) do return
    }

    half_frontage, half_depth := lot_frontage * .5, lot_depth * .5
    parcel := City_Parcel {
        frontage_width = lot_frontage,
        depth          = lot_depth,
        density        = density,
        seed           = seed,
        alley_frontage = alley_frontage,
    }
    parcel.corners = {
        {center_x - tx * half_frontage - normal_x * half_depth, center_z - tz * half_frontage - normal_z * half_depth},
        {center_x + tx * half_frontage - normal_x * half_depth, center_z + tz * half_frontage - normal_z * half_depth},
        {center_x + tx * half_frontage + normal_x * half_depth, center_z + tz * half_frontage + normal_z * half_depth},
        {center_x - tx * half_frontage + normal_x * half_depth, center_z - tz * half_frontage + normal_z * half_depth},
    }
    append(&plan.parcels, parcel)
    plan.parcel_count += 1
    append(&plan.structures, structure)
    plan.count += 1
}

city_alley_segment_intersection :: proc(
    first_start_x, first_start_z, first_end_x, first_end_z: f32,
    second: City_Alley,
) -> (
    x, z, first_along: f32,
    found: bool,
) {
    first_x, first_z := first_end_x - first_start_x, first_end_z - first_start_z
    second_x, second_z := second.end_x - second.start_x, second.end_z - second.start_z
    cross := first_x * second_z - first_z * second_x
    if math.abs(cross) <= .0001 do return
    offset_x, offset_z := second.start_x - first_start_x, second.start_z - first_start_z
    first_amount := (offset_x * second_z - offset_z * second_x) / cross
    second_amount := (offset_x * first_z - offset_z * first_x) / cross
    if first_amount <= .001 || first_amount >= .999 || second_amount < -.001 || second_amount > 1.001 {
        return
    }
    return first_start_x + first_x * first_amount, first_start_z + first_z * first_amount, first_amount, true
}

city_plan_split_alley_at :: proc(plan: ^City_Plan, alley_index: int, x, z: f32) {
    if plan == nil || alley_index < 0 || alley_index >= plan.alley_count do return
    original := plan.alleys[alley_index]
    start_dx, start_dz := x - original.start_x, z - original.start_z
    end_dx, end_dz := x - original.end_x, z - original.end_z
    if start_dx * start_dx + start_dz * start_dz <= .0025 || end_dx * end_dx + end_dz * end_dz <= .0025 {
        return
    }
    plan.alleys[alley_index].end_x = x
    plan.alleys[alley_index].end_z = z
    plan.alleys[alley_index].end_terminal = .None
    tail := original
    tail.start_x, tail.start_z = x, z
    tail.start_terminal = .None
    append(&plan.alleys, tail)
    plan.alley_count += 1
}

city_plan_density :: proc(
    project: ^terrain.Project,
    field: ^[terrain.CITY_DENSITY_SAMPLES]u8,
    rebuild_bounds: City_Bounds,
    seed: u32 = 0xA71D3,
) -> City_Plan {
    plan: City_Plan
    if project == nil || field == nil || !rebuild_bounds.valid do return plan

    // Frontage sampling makes authored roads the primary skeleton. A stable
    // jitter changes lot widths without allowing frame-to-frame preview pops.
    for edge, edge_index in project.road_graph.edges[:project.road_graph.edge_count] {
        previous := roads.edge_point(&project.road_graph, edge, 0)
        accumulated: f32
        lot_cursor: f32
        next_frontage := 10 + city_hash_unit(edge_index, 0, seed, 31) * 8
        for sample in 1 ..= 64 {
            t := f32(sample) / 64
            current := roads.edge_point(&project.road_graph, edge, t)
            vx, vz := current.x - previous.x, current.z - previous.z
            segment := f32(math.sqrt(f64(vx * vx + vz * vz)))
            if segment > .001 {
                accumulated += segment
                lot_cursor += segment
                if lot_cursor >= next_frontage {
                    tangent_x, tangent_z := vx / segment, vz / segment
                    normal_x, normal_z := -tangent_z, tangent_x
                    for side_index in 0 ..< 2 {
                        side := side_index == 0 ? f32(-1) : f32(1)
                        probe_x := current.x + normal_x * side * (edge.half_width + edge.shoulder_width + 15)
                        probe_z := current.z + normal_z * side * (edge.half_width + edge.shoulder_width + 15)
                        density := city_density_sample(field, probe_x, probe_z)
                        lot_seed := city_hash(edge_index * 131 + int(accumulated), side_index, seed)
                        depth := 15 + density * 15 + f32((lot_seed >> 12) & 255) / 255 * 5
                        center_offset := edge.half_width + edge.shoulder_width + 2 + depth * .5
                        center_x := current.x + normal_x * side * center_offset
                        center_z := current.z + normal_z * side * center_offset
                        city_plan_add_parcel_building(
                            &plan,
                            project,
                            rebuild_bounds,
                            center_x,
                            center_z,
                            tangent_x,
                            tangent_z,
                            side,
                            next_frontage,
                            depth,
                            density,
                            lot_seed,
                            false,
                        )

                        // Dense paint may support a narrow alley normal to the
                        // main street, but the alley is demand-driven: retain
                        // it only after multiple independently viable deep
                        // parcels have asked for shared access.
                        deep_density := city_density_sample(
                            field,
                            current.x + normal_x * side * (edge.half_width + edge.shoulder_width + 62),
                            current.z + normal_z * side * (edge.half_width + edge.shoulder_width + 62),
                        )
                        if deep_density > .55 && (lot_seed & 7) == 0 {
                            alley_start := edge.half_width + edge.shoulder_width + 3
                            alley_length := 62 + deep_density * 22
                            network_length := alley_start + alley_length
                            alley := City_Alley {
                                // Root the branch on the sampled road
                                // centerline. Starting beyond the shoulder and
                                // labeling that point `.Road` only drew a
                                // convincing apron; it did not make the two
                                // networks geometrically connected.
                                start_x        = current.x,
                                start_z        = current.z,
                                end_x          = current.x + normal_x * side * network_length,
                                end_z          = current.z + normal_z * side * network_length,
                                half_width     = 2.2,
                                start_terminal = .Road,
                            }
                            joined_alley := -1
                            joined_x, joined_z: f32
                            joined_amount: f32 = 1
                            for existing, existing_index in plan.alleys[:plan.alley_count] {
                                intersection_x, intersection_z, amount, found := city_alley_segment_intersection(
                                    alley.start_x,
                                    alley.start_z,
                                    alley.end_x,
                                    alley.end_z,
                                    existing,
                                )
                                if found && amount < joined_amount {
                                    joined_alley = existing_index
                                    joined_x, joined_z = intersection_x, intersection_z
                                    joined_amount = amount
                                }
                            }
                            if joined_alley >= 0 {
                                alley.end_x, alley.end_z = joined_x, joined_z
                                alley.end_terminal = .None
                                network_length *= joined_amount
                            }
                            structure_start := plan.count
                            parcel_start := plan.parcel_count
                            for alley_step in 0 ..< 3 {
                                // Lots still begin beyond the road shoulder;
                                // only the access centerline reaches the
                                // network root.
                                along := alley_start + 22 + f32(alley_step) * 18
                                if along >= network_length - 2 do continue
                                alley_x := alley.start_x + normal_x * side * along
                                alley_z := alley.start_z + normal_z * side * along
                                for alley_side_index in 0 ..< 2 {
                                    alley_side := alley_side_index == 0 ? f32(-1) : f32(1)
                                    lot_normal_x, lot_normal_z := -normal_z * side, normal_x * side
                                    alley_lot_depth := 14 + deep_density * 8
                                    alley_center_offset := alley.half_width + 1.2 + alley_lot_depth * .5
                                    bx := alley_x + lot_normal_x * alley_side * alley_center_offset
                                    bz := alley_z + lot_normal_z * alley_side * alley_center_offset
                                    bd := city_density_sample(field, bx, bz)
                                    alley_seed := city_hash(
                                        edge_index * 257 + alley_step,
                                        side_index * 2 + alley_side_index,
                                        lot_seed,
                                    )
                                    city_plan_add_parcel_building(
                                        &plan,
                                        project,
                                        rebuild_bounds,
                                        bx,
                                        bz,
                                        normal_x * side,
                                        normal_z * side,
                                        alley_side,
                                        11 + city_hash_unit(alley_step, alley_side_index, alley_seed) * 5,
                                        alley_lot_depth,
                                        bd,
                                        alley_seed,
                                        true,
                                    )
                                }
                            }
                            household_demand := plan.count - structure_start
                            if household_demand >= 2 {
                                alley.household_demand = u16(household_demand)
                                if joined_alley >= 0 {
                                    city_plan_split_alley_at(&plan, joined_alley, joined_x, joined_z)
                                }
                                append(&plan.alleys, alley)
                                plan.alley_count += 1
                            } else {
                                // A single deep lot can use private access;
                                // it does not justify constructing a public
                                // branch or creating an isolated alley-front
                                // building merely to decorate that branch.
                                resize(&plan.structures, structure_start)
                                resize(&plan.parcels, parcel_start)
                                plan.count = structure_start
                                plan.parcel_count = parcel_start
                            }
                        }
                    }
                    lot_cursor = 0
                    frontage_seed := city_hash_unit(edge_index, int(accumulated), seed, 32)
                    next_frontage = 10 + frontage_seed * 8
                    if city_hash_unit(edge_index, int(accumulated), seed, 33) > .76 {
                        next_frontage += 8 + frontage_seed * 6
                    }
                }
            }
            previous = current
        }
    }
    return plan
}

city_commit_plan :: proc(
    project: ^terrain.Project,
    field: ^[terrain.CITY_DENSITY_SAMPLES]u8,
    rebuild_bounds: City_Bounds,
    plan: ^City_Plan,
) -> int {
    if project == nil || field == nil || plan == nil || !rebuild_bounds.valid do return 0
    project.city_density = field^
    for index := project.structure_count - 1; index >= 0; index -= 1 {
        structure := project.structures[index]
        if structure.kind == .Architecture &&
           city_bounds_contains(rebuild_bounds, structure.center_x, structure.center_z) {
            _ = terrain.remove_structure(project, index)
        }
    }
    created := 0
    for candidate in plan.structures[:plan.count] {
        structure_seed := candidate.seed
        index := terrain.add_structure(project, candidate)
        if index < 0 do break
        project.structures[index].seed = structure_seed
        created += 1
    }
    project.revision += 1
    return created
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
        building_radius := architecture_footprint_radius(width, depth)
        overlaps := false
        for existing in project.structures[:project.structure_count] {
            if existing.kind != .Architecture do continue
            dx, dz := point.x - existing.center_x, point.z - existing.center_z
            minimum_distance := building_radius + architecture_footprint_radius(existing.width, existing.depth) + 1.5
            if dx * dx + dz * dz < minimum_distance * minimum_distance {
                overlaps = true
                break
            }
        }
        if overlaps do continue
        building_height := max(height * (.62 + random01(&state) * .76), terrain.BASE_CELL_SIZE)
        rotation := (random01(&state) - .5) * .28
        structure := terrain.structure_make(point.x, point.z, width, depth, base_height, building_height)
        structure.kind = .Architecture
        structure.rotation = rotation
        structure_seed := u32(random01(&state) * f32(0xffffffff))
        structure.seed = structure_seed
        structure.building = architecture_identity(
            {
                density = clamp((building_height - 8) / 42, 0, 1),
                frontage = width,
                depth = depth,
                route = .Unspecified,
                purpose_explicit = false,
            },
            structure_seed,
        )
        structure.color = architecture_color(structure.seed)
        foundation_low, foundation_high := architecture_foundation_height_range(project, structure)
        if foundation_low <= project.sea_level do continue
        structure.base_y = foundation_high
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

generate_append :: proc(
    project: ^terrain.Project,
    center_x, center_z: f32,
    seed: u32 = 0xA71D3,
    density: f32 = 1,
) -> int {
    if project == nil do return 0
    graph := adriatic_graph(center_x, center_z, seed)
    safe_density := clamp(density, f32(.2), f32(1))
    first_structure := project.structure_count
    created := 0
    for node, node_index in graph.nodes[:graph.count] {
        if node.kind == .Site do continue
        if node.kind == .Street_Block && graph_unit(seed, u32(node_index) + 211) > safe_density {
            continue
        }
        if node.kind == .Street_Block && safe_density < 1 {
            separated := true
            for existing in project.structures[first_structure:project.structure_count] {
                if existing.kind != .Architecture do continue
                dx, dz := node.x - existing.center_x, node.z - existing.center_z
                // Sparse settlements need visible gaps, not merely fewer
                // buildings selected from the same tight street wall.
                if dx * dx + dz * dz < 46 * 46 {
                    separated = false
                    break
                }
            }
            if !separated do continue
        }
        base_height := architecture_base_height(project, node.x, node.z)
        if base_height <= project.sea_level do continue
        building_height := node.height
        structure_seed := node.seed
        if node.kind == .Street_Block && safe_density < 1 {
            // Density controls vertical intensity as well as occupancy. This
            // keeps a lightly settled mouse town low-rise without uniformly
            // scaling its authored footprints, doors, or windows.
            building_height = min(building_height, 18 + safe_density * 8)
            // Compound L/U plans make one sparse lot read as several attached
            // towers. Select the simple single-mass presentation variant while
            // retaining the authored footprint dimensions and deterministic
            // palette variation.
            structure_seed -= structure_seed % 5
        }
        structure := terrain.structure_make(node.x, node.z, node.width, node.depth, base_height, building_height)
        structure.kind = .Architecture
        structure.rotation = node.rotation
        structure.seed = structure_seed
        structure.building = architecture_identity(
            {
                density = safe_density,
                attached = safe_density >= .68,
                frontage = node.width,
                depth = node.depth,
                route = .Street,
                landmark_kind = node.kind == .Landmark ? buildings.Landmark_Kind.Campanile : buildings.Landmark_Kind.None,
                purpose_explicit = false,
            },
            structure_seed,
        )
        structure.color = architecture_color(structure_seed, node.kind == .Landmark)
        foundation_low, foundation_high := architecture_foundation_height_range(project, structure)
        if foundation_low <= project.sea_level do continue
        structure.base_y = foundation_high
        index := terrain.add_structure(project, structure)
        if index >= 0 {
            project.structures[index].seed = structure_seed
            project.revision += 1
            created += 1
        }
    }
    return created
}
