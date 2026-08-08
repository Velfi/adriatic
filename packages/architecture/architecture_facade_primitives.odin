package architecture

import circulation "../circulation"
import terrain "../terrain"
import "core:math"

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
    _ = circulation.plan_add(plan, {
        center_x = center_x,
        center_z = center_z,
        width    = 28,
        length   = 18,
        kind     = .Plaza,
        source   = .Generated,
        pavement = .Cobblestone,
        walkable = true,
    })

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
        _ = circulation.plan_add(plan, {
            center_x = (door_x + target_x) * .5,
            center_z = (door_z + target_z) * .5,
            width    = 3.6,
            length   = path_length,
            rotation = math.atan2(path_dx, path_dz),
            kind     = .Path,
            source   = .Derived,
            pavement = .Cobblestone,
            walkable = true,
        })
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
        horizontal_gap := math.abs(horizontal - opening.horizontal) - (width + opening.width) * .5
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
