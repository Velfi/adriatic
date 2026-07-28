package architecture

import buildings "../buildings"
import circulation "../circulation"
import roads "../roads"
import terrain "../terrain"
import "core:math"

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
ARCHITECTURE_MIN_OPENING_WALL_HEIGHT :: f32(5.5)
ARCHITECTURE_OPENING_CORNER_MARGIN :: f32(.75)
ARCHITECTURE_DOOR_WINDOW_MARGIN :: f32(.55)
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
    lane_a := min_z + (max_z - min_z) / 3
    lane_b := min_z + (max_z - min_z) * 2 / 3
    road_span := max(max_x - min_x + 36, f32(160))
    lanes := [2]f32{lane_a, lane_b}
    for lane_z in lanes {
        _ = circulation.plan_add(
            plan,
            {
                center_x = center_x,
                center_z = lane_z,
                width = road_span,
                length = 6.5,
                kind = .Street,
                source = .Generated,
                pavement = .Cobblestone,
                walkable = true,
                driveable = true,
            },
        )
    }
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
        target_lane := f32(1e9)
        target_distance := f32(1e9)
        candidates := [2]f32{lane_a, lane_b}
        for candidate in candidates {
            candidate_dx, candidate_dz := center_x - door_x, candidate - door_z
            if candidate_dx * front_x + candidate_dz * front_z < 0 do continue
            candidate_distance := candidate_dx * candidate_dx + candidate_dz * candidate_dz
            if candidate_distance < target_distance {
                target_lane = candidate
                target_distance = candidate_distance
            }
        }
        if target_distance >= 1e9 do continue
        lane_direction := target_lane >= door_z ? f32(1) : f32(-1)
        target_z := target_lane - lane_direction * 3
        path_dx, path_dz := center_x - door_x, target_z - door_z
        path_length := f32(math.sqrt(f64(path_dx * path_dx + path_dz * path_dz)))
        if path_length <= 1.5 do continue
        _ = circulation.plan_add(
            plan,
            {
                center_x = (door_x + center_x) * .5,
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

// Produces the complete circulation intent for every architecture settlement.
// Rendering, vegetation, and gameplay queries consume this same plan.
circulation_plan :: proc(project: ^terrain.Project) -> circulation.Plan {
    plan: circulation.Plan
    if project == nil do return plan

    candidates := make([dynamic]int, 0, project.structure_count)
    defer delete(candidates)
    for structure, structure_index in project.structures[:project.structure_count] {
        if structure.kind != .Architecture || structure.height > 60 do continue
        append(&candidates, structure_index)
    }

    // Buildings connected through a 320 m neighborhood belong to one town.
    // The threshold comfortably spans a painted settlement while keeping the
    // two default islands, and other distant settlements, independent.
    CLUSTER_DISTANCE :: f32(320)
    assigned := make([]bool, len(candidates))
    cluster := make([]int, len(candidates))
    defer delete(assigned)
    defer delete(cluster)
    for candidate_index in 0 ..< len(candidates) {
        if assigned[candidate_index] do continue
        assigned[candidate_index] = true
        cluster[0] = candidates[candidate_index]
        cluster_count := 1
        for cursor := 0; cursor < cluster_count; cursor += 1 {
            anchor := project.structures[cluster[cursor]]
            for other_index in 0 ..< len(candidates) {
                if assigned[other_index] do continue
                other := project.structures[candidates[other_index]]
                dx, dz := other.center_x - anchor.center_x, other.center_z - anchor.center_z
                if dx * dx + dz * dz > CLUSTER_DISTANCE * CLUSTER_DISTANCE do continue
                assigned[other_index] = true
                cluster[cluster_count] = candidates[other_index]
                cluster_count += 1
            }
        }
        circulation_plan_add_town(&plan, project, cluster[:cluster_count])
    }
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

OPENING_LAYOUT_CAPACITY :: 512

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

Facade_Profile :: struct {
    front_bays_min, front_bays_max:       int,
    rear_bays_min, rear_bays_max:         int,
    side_bays_min, side_bays_max:         int,
    window_width_min, window_width_max:   f32,
    window_height_min, window_height_max: f32,
    opening_ratio_min, opening_ratio_max: f32,
    blank_sides:                          bool,
    service:                              bool,
    shop_ground_floor:                    bool,
}

facade_profile :: proc(archetype: buildings.Archetype) -> Facade_Profile {
    switch archetype {
    case .Dwelling, .Farmstead, .Legacy:
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
    case .Townhouse, .Shop_House, .Post_Office:
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
    case .Palace_Loggia, .Harbor_Office, .Market_Hall, .Monastery, .Church:
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
            opening_ratio_max = .22,
        }
    case .Campanile, .Fortress_Gate, .Cycladic_Bell:
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
    variant := int((structure.seed >> u32(9 + int(face) * 3)) & 255)
    count := low
    if high > low {
        count += variant % (high - low + 1)
    }
    count = int(math.floor(f64(f32(count) * ARCHITECTURE_WINDOW_DENSITY + .5)))
    if primary_face && !profile.service do count = max(count, 1)
    maximum_fit := max(1, int(math.floor(f64((span - 2 * 1.15 + 1.15) / (profile.window_width_min + 1.15)))))
    return clamp(count, 0, maximum_fit)
}

facade_profile_window_size :: proc(profile: Facade_Profile, structure: terrain.Structure, face: Face) -> (f32, f32) {
    width_t := f32((structure.seed >> u32(3 + int(face) * 2)) & 31) / 31
    height_t := f32((structure.seed >> u32(5 + int(face) * 2)) & 31) / 31
    return profile.window_width_min + (profile.window_width_max - profile.window_width_min) * width_t,
        profile.window_height_min + (profile.window_height_max - profile.window_height_min) * height_t
}

facade_bay_center :: proc(span, window_width: f32, columns, column: int) -> f32 {
    if columns <= 1 do return 0
    pitch := clamp((span - 2 * 1.15 - window_width) / f32(columns - 1), f32(2.8), f32(4.6))
    return (f32(clamp(column, 0, columns - 1)) - f32(columns - 1) * .5) * pitch
}

facade_opening_row_y :: proc(height: f32, row: int, opening_height: f32) -> f32 {
    rows := facade_floor_count(height)
    first_y := opening_height * .5 + 1.45
    if rows <= 1 do return first_y
    last_y := max(first_y, height - opening_height * .5 - 1.45)
    return first_y + (last_y - first_y) * f32(clamp(row, 0, rows - 1)) / f32(rows - 1)
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
    habitable := buildings.is_habitable(identity.archetype)
    primary_mass := mass_index == primary_mass_index
    faces := [4]Face{.Front, .Rear, .Left, .Right}
    rows := facade_floor_count(wall_height)

    for face in faces {
        span := face_span(mass, face)
        if span < ARCHITECTURE_MIN_OPENING_FACE_SPAN do continue
        primary_face := primary_mass && face == .Front
        door_width := f32(0)
        if primary_face {
            door_width = clamp(span * .13, f32(1.8), f32(2.8))
            door_height := clamp(wall_height * .075, f32(3.0), f32(4.0))
            _ = opening_layout_add(
                &layout,
                {
                    face = face,
                    kind = habitable ? Opening_Kind.Door : Opening_Kind.Service_Door,
                    horizontal = 0,
                    y = .20 + door_height * .5,
                    width = door_width,
                    height = door_height,
                    primary = true,
                },
            )
        }

        columns := facade_profile_bay_count(profile, structure, face, primary_face, span)
        if columns <= 0 do continue
        window_width, window_height := facade_profile_window_size(profile, structure, face)
        face_rows := profile.service ? 1 : rows
        for row in 0 ..< face_rows {
            opening_y := facade_opening_row_y(wall_height, row, window_height)
            for column in 0 ..< columns {
                horizontal := facade_bay_center(span, window_width, columns, column)
                central_bay := columns % 2 == 1 && column == columns / 2
                if primary_face && row == 0 && central_bay {
                    continue
                }
                if identity.archetype == .Mixed_Use_Dwelling &&
                   primary_mass &&
                   row == 0 &&
                   (face == .Left || face == .Right) {
                    // The renderer gives mixed-use dwellings a dedicated
                    // apartment stair door on each side wall. Reserve that
                    // ground-floor span here so the independently generated
                    // side-window grammar cannot draw through either door.
                    apartment_door_horizontal := face == .Left ? mass.depth * .20 : -mass.depth * .20
                    apartment_door_width: f32 = 1.65
                    if math.abs(horizontal - apartment_door_horizontal) <
                       window_width * .5 + apartment_door_width * .5 + ARCHITECTURE_DOOR_WINDOW_MARGIN {
                        continue
                    }
                }
                if math.abs(horizontal) + window_width * .5 > span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN {
                    continue
                }
                kind := Opening_Kind.Window
                opening_height := window_height
                opening_width := window_width
                if profile.service {
                    kind = .Vent
                    opening_y = max(opening_height * .5 + 1.15, f32(1.5))
                } else if profile.shop_ground_floor && primary_face && row == 0 {
                    // Shop glazing should begin near the pavement and approach
                    // the door head. Treating it like a slightly enlarged
                    // domestic window leaves the ground floor visually closed.
                    if identity.archetype == .Mixed_Use_Dwelling {
                        opening_width = clamp(span * .27, f32(4.2), f32(7.2))
                    } else {
                        opening_width = clamp(span / f32(columns + 1) * .62, f32(2.35), f32(3.60))
                    }
                    opening_height = min(window_height * 1.62, f32(3.40))
                    opening_y = .36 + opening_height * .5
                } else if primary_face && row == 0 {
                    opening_width *= .90
                    opening_height *= .85
                    opening_y = facade_opening_row_y(wall_height, row, opening_height)
                }
                if primary_face && row == 0 {
                    // Narrow frontage masses in compound footprints frequently
                    // select two bays. Their minimum pitch can otherwise leave
                    // a window touching or overlapping the centered entrance
                    // surround, so push the pair outward before checking the
                    // corner margin.
                    minimum_center := door_width * .5 + opening_width * .5 + ARCHITECTURE_DOOR_WINDOW_MARGIN
                    if horizontal < 0 {
                        horizontal = min(horizontal, -minimum_center)
                    } else {
                        horizontal = max(horizontal, minimum_center)
                    }
                    if math.abs(horizontal) + opening_width * .5 > span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN {
                        continue
                    }
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
    maturity := clamp((growth_density - .035) / (.72 - .035), 0, 1)
    return maturity * maturity * (3 - 2 * maturity)
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
    // Green juvenile leaders follow gusts readily. Lignified, wall-trained
    // trunks retain only a small amount of movement at full maturity.
    return 1 - clamp(maturity, 0, 1) * .86
}

@(no_instrumentation)
bougainvillea_detail_tier :: #force_inline proc(camera_distance: f32) -> int {
    // Preserve the trained silhouette throughout the city, but reserve tiny
    // bark, support, and layered-card details for distances where they occupy
    // meaningful screen area.
    if camera_distance < 48 do return 2
    if camera_distance < 112 do return 1
    return 0
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

    if (archetype == .Dwelling || archetype == .Farmstead) &&
       structure.width >= 26 &&
       structure.depth >= 20 &&
       variant % 8 == 3 {
        // A shallow U around a rear court is reserved for genuinely broad
        // parcels; smaller lots stay legible as houses rather than compounds.
        result.masses[0] = {0, -structure.depth * .32, structure.width, max(structure.depth * .36, f32(4.5)), 1}
        result.masses[1] = {
            -structure.width * .36,
            structure.depth * .12,
            max(structure.width * .28, f32(4.5)),
            max(structure.depth * .64, f32(4.5)),
            .72,
        }
        result.masses[2] = {
            structure.width * .36,
            structure.depth * .12,
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
            -structure.depth * .22,
            max(structure.width * .44, f32(4.5)),
            max(structure.depth * .56, f32(4.5)),
            .82,
        }
        result.count = 2
    } else if (archetype == .Dwelling || archetype == .Farmstead) &&
       structure.width >= 12 &&
       structure.depth >= 14 &&
       variant % 4 == 1 {
        // L plan: a street bar with a shorter rear wing.
        result.masses[0] = {0, -structure.depth * .25, structure.width, structure.depth * .5, 1}
        result.masses[1] = {
            (structure.seed & 1) == 0 ? -structure.width * .31 : structure.width * .31,
            structure.depth * .12,
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
            -structure.depth * .35,
            max(structure.width * .32, f32(4.5)),
            max(structure.depth * .42, f32(4.5)),
            .68,
        }
        result.masses[2] = {
            structure.width * .31,
            -structure.depth * .35,
            max(structure.width * .32, f32(4.5)),
            max(structure.depth * .42, f32(4.5)),
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
            -structure.depth * .29,
            variant % 3 == 2 ? max(structure.width * .54, f32(4.5)) : max(structure.width * .46, f32(4.5)),
            max(structure.depth * .42, f32(4.5)),
            variant % 3 == 2 ? f32(.76) : f32(.72),
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
            (variant & 1) == 0 ? -structure.width * .30 : structure.width * .30,
            -structure.depth * .28,
            max(structure.width * .40, f32(4.5)),
            max(structure.depth * .44, f32(4.5)),
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
            structure.width * .28,
            -structure.depth * .10,
            max(structure.width * .44, f32(4.5)),
            max(structure.depth * .80, f32(4.5)),
            .72,
        }
        result.count = 2
    } else if (archetype == .Workshop || archetype == .Storehouse || archetype == .Fishery) &&
       structure.width >= 20 &&
       structure.depth >= 16 &&
       variant % 6 == 4 {
        // A working court edged by two unequal sheds gives larger productive
        // sites a broken, three-part roofline instead of another residential L.
        result.masses[0] = {0, -structure.depth * .22, structure.width, structure.depth * .48, 1}
        result.masses[1] = {
            -structure.width * .35,
            structure.depth * .20,
            max(structure.width * .30, f32(4.5)),
            max(structure.depth * .48, f32(4.5)),
            .70,
        }
        result.masses[2] = {
            structure.width * .36,
            structure.depth * .12,
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
    } else if archetype == .Barn_Granary && structure.width >= 12 {
        result.masses[0] = {0, 0, structure.width, structure.depth, 1}
        if structure.depth >= 12 {
            result.masses[1] = {
                (variant & 1) == 0 ? -structure.width * .38 : structure.width * .38,
                structure.depth * .08,
                max(structure.width * .24, f32(4.5)),
                max(structure.depth * .70, f32(4.5)),
                .58,
            }
            result.count = 2
        }
    } else if archetype == .Mill && structure.width >= 9 && structure.depth >= 9 {
        result.masses[0] = {0, 0, structure.width * .78, structure.depth * .78, 1}
        result.masses[1] = {0, 0, max(structure.width * .42, f32(4.5)), max(structure.depth * .42, f32(4.5)), 1.28}
        result.count = 2
    } else if archetype == .Palace_Loggia ||
       archetype == .Market_Hall ||
       archetype == .Harbor_Office ||
       archetype == .Monastery {
        result.masses[0] = {0, -structure.depth * .12, structure.width, structure.depth * .76, 1}
        if structure.width >= 12 && structure.depth >= 12 {
            result.masses[1] = {
                (variant & 1) == 0 ? -structure.width * .30 : structure.width * .30,
                structure.depth * .25,
                max(structure.width * .40, f32(4.5)),
                max(structure.depth * .50, f32(4.5)),
                .78,
            }
            result.count = 2
        }
    } else if archetype == .Church && structure.width >= 9 && structure.depth >= 12 {
        result.masses[0] = {0, 0, max(structure.width * .72, f32(4.5)), structure.depth, 1}
        result.masses[1] = {0, structure.depth * .30, structure.width, max(structure.depth * .32, f32(4.5)), .70}
        result.count = 2
    } else if archetype == .Fortress_Gate && structure.width >= 12 {
        result.masses[0] = {-structure.width * .30, 0, max(structure.width * .40, f32(4.5)), structure.depth, 1}
        result.masses[1] = {structure.width * .30, 0, max(structure.width * .40, f32(4.5)), structure.depth, 1}
        result.count = 2
    } else if archetype == .Cycladic_Bell && structure.width >= 8 {
        result.masses[0] = {0, 0, max(structure.width * .70, f32(4.5)), structure.depth, 1}
    }
    return result
}

@(no_instrumentation)
architecture_frontage_mass_index :: #force_inline proc(structure: terrain.Structure) -> int {
    footprint := architecture_footprint(structure)
    if footprint.count <= 1 do return 0
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
    if footprint.count <= 1 do return result
    frontage_index := architecture_frontage_mass_index(structure)
    frontage_mass := footprint.masses[frontage_index]
    result.center_x, result.center_z = architecture_mass_world(structure, frontage_mass)
    result.width = frontage_mass.width
    result.depth = frontage_mass.depth
    result.height = max(terrain.BASE_CELL_SIZE, structure.height * frontage_mass.height_scale)
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
    lowest, highest := architecture_foundation_height_range(project, structure^)
    if lowest <= project.sea_level + .15 do return false
    allowed_relief := max(f32(2.5), min(structure.width, structure.depth) * .12)
    if highest - lowest > allowed_relief do return false
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
    half_width, half_depth := structure.width * .5, structure.depth * .5
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
    for point in points {
        px := structure.center_x + point[0] * cosine - point[1] * sine
        pz := structure.center_z + point[0] * sine + point[1] * cosine
        height := terrain.sample_height(project, 0, px, pz)
        lowest, highest = min(lowest, height), max(highest, height)
    }
    return
}

architecture_foundation_height_range :: proc(
    project: ^terrain.Project,
    structure: terrain.Structure,
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
        mass_lowest, mass_highest := architecture_mass_height_range(project, child)
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

generate :: proc(project: ^terrain.Project, center_x, center_z: f32, seed: u32 = 0xA71D3) -> int {
    if project == nil do return 0
    clear_architecture(project)
    return generate_append(project, center_x, center_z, seed)
}
