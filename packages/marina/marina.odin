package marina

import boats "../boats"
import markov "../markov"
import "core:math"
import "core:sync"

GRID_WIDTH :: 27
GRID_HEIGHT :: 21
CELL_METERS :: f32(4)
DESIGN_VESSEL_LENGTH_METERS :: f32(8)
DESIGN_VESSEL_BEAM_METERS :: f32(2.9)
MAIN_PIER_WIDTH_METERS :: f32(2.2)
FINGER_PIER_WIDTH_METERS :: f32(1.25)
FINGER_PIER_LENGTH_METERS :: f32(6.8)
BERTH_CENTER_OFFSET_METERS :: f32(6)
MIN_SLIP_CENTER_SPACING_METERS :: f32(4.4)
MIN_FAIRWAY_WIDTH_METERS :: f32(14)
MOORING_FIELD_SPACING_METERS :: f32(24)
BREAKWATER_TOE_WIDTH_METERS :: f32(12)
SEGMENT_CAPACITY :: 96
SLIP_CAPACITY :: 40
PROP_CAPACITY :: 48
ROUTE_POINT_CAPACITY :: 8
GENERATION_CANDIDATES :: 8
BREAKWATER_WEST_X :: 3
BREAKWATER_EAST_X :: GRID_WIDTH - 4
MIN_EDGE_CLEARANCE_CELLS :: 3
MIN_OUTER_CLEARANCE_CELLS :: 4
OUTER_SECTION_LIMIT_Z :: 13

markov_generation_lock: sync.Mutex

Cell :: enum u8 {
    Water,
    Land,
    Quay,
    Breakwater,
    Natural_Jetty,
    Main_Pier,
    Finger_Pier,
    Slip,
    Mooring,
    Channel,
    Building,
    Props,
}

Site_Cell :: enum u8 {
    Water,
    Shore,
    Land,
    Blocked,
}

Site :: struct {
    enabled:   bool,
    origin:    Vec2,
    yaw:       f32,
    sea_level: f32,
    cells:     [GRID_WIDTH * GRID_HEIGHT]Site_Cell,
}

Segment_Kind :: enum u8 {
    Quay,
    Breakwater,
    Natural_Jetty,
    Main_Pier,
    Finger_Pier,
}

Basin_Style :: enum u8 {
    Fishing_Quay,
    Civic_Marina,
    Island_Harbour,
    Working_Port,
    Stone_Cove,
    Ferry_Quay,
    Boat_Yard,
    Lagoon_Marina,
}

Boundary_Form :: enum u8 {
    Enclosed_Basin,
    Wide_Twin_Moles,
    Offset_West,
    Offset_East,
    Open_Cove,
}

BOUNDARY_FORM_COUNT :: 5

Shoreline_Form :: enum u8 {
    Natural_Shore,
    Straight_Quay,
    West_Apron,
    East_Apron,
    Split_Aprons,
    Stepped_Quays,
}

SHORELINE_FORM_COUNT :: 6

Section_Form :: enum u8 {
    Straight,
    Hammerhead,
    Dogleg,
    Quay_Mole,
    Natural_Jetty,
    Floating_Pontoon,
    Island_Quay,
    Forked_Pier,
    Mooring_Field,
}

SECTION_FORM_COUNT :: 9

Vec2 :: struct {
    x, z: f32,
}

Segment :: struct {
    kind:  Segment_Kind,
    a, b:  Vec2,
    width: f32,
}

Berth_Kind :: enum u8 {
    Slip,
    Swing_Mooring,
}

Slip :: struct {
    position: Vec2,
    yaw:      f32,
    class:    boats.Class,
    occupied: bool,
    kind:     Berth_Kind,
}

Prop_Kind :: enum u8 {
    Lamp,
    Beacon,
    Bollard,
    Crates,
    Nets,
}

Prop :: struct {
    kind:     Prop_Kind,
    position: Vec2,
    yaw:      f32,
}

Route :: struct {
    points: [ROUTE_POINT_CAPACITY]Vec2,
    count:  int,
}

Plan :: struct {
    seed:                      u32,
    layout_seed:               u32,
    candidate_index:           int,
    candidates_evaluated:      int,
    style:                     Basin_Style,
    boundary_form:             Boundary_Form,
    shoreline_form:            Shoreline_Form,
    section_form_counts:       [SECTION_FORM_COUNT]int,
    cells:                     [GRID_WIDTH * GRID_HEIGHT]Cell,
    segments:                  [SEGMENT_CAPACITY]Segment,
    segment_count:             int,
    slips:                     [SLIP_CAPACITY]Slip,
    slip_count:                int,
    props:                     [PROP_CAPACITY]Prop,
    prop_count:                int,
    route:                     Route,
    office:                    Vec2,
    world_conditioned:         bool,
    world_origin:              Vec2,
    world_yaw:                 f32,
    // spacing_density is the fraction of usable basin cells occupied by
    // marina structure. spacing_badness_density is a normalized 0..1 score;
    // lower is better, and values above .35 deserve rejection or inspection.
    spacing_density:           f32,
    target_fill_density:       f32,
    fill_density:              f32,
    fill_density_error:        f32,
    berth_spacing_badness:     f32,
    structure_overlap_badness: f32,
    site_conformance_badness:  f32,
    spacing_badness_density:   f32,
    generation_quality:        f32,
    valid:                     bool,
}

MAX_SITE_CONFORMANCE_BADNESS :: f32(0.03)

@(no_instrumentation)
cell_index :: #force_inline proc(x, z: int) -> int {
    return z * GRID_WIDTH + x
}

@(no_instrumentation)
cell :: #force_inline proc(plan: ^Plan, x, z: int) -> Cell {
    if plan == nil || x < 0 || x >= GRID_WIDTH || z < 0 || z >= GRID_HEIGHT do return .Water
    return plan.cells[cell_index(x, z)]
}

set_cell :: proc(plan: ^Plan, x, z: int, value: Cell) {
    if plan == nil || x < 0 || x >= GRID_WIDTH || z < 0 || z >= GRID_HEIGHT do return
    plan.cells[cell_index(x, z)] = value
}

grid_position :: proc(x, z: int) -> Vec2 {
    return {(f32(x) - f32(GRID_WIDTH - 1) * .5) * CELL_METERS, (f32(z) - f32(GRID_HEIGHT - 1) * .5) * CELL_METERS}
}

default_site :: proc() -> Site {
    site: Site
    site.enabled = true
    for z in 0 ..< GRID_HEIGHT {
        for x in 0 ..< GRID_WIDTH {
            value := Site_Cell.Water
            if z < 4 do value = .Land
            if z == 4 do value = .Shore
            site.cells[cell_index(x, z)] = value
        }
    }
    return site
}

site_cell :: proc(site: ^Site, x, z: int) -> Site_Cell {
    if site == nil || x < 0 || x >= GRID_WIDTH || z < 0 || z >= GRID_HEIGHT do return .Blocked
    return site.cells[cell_index(x, z)]
}

set_site_cell :: proc(site: ^Site, x, z: int, value: Site_Cell) {
    if site == nil || x < 0 || x >= GRID_WIDTH || z < 0 || z >= GRID_HEIGHT do return
    site.cells[cell_index(x, z)] = value
}

site_world_position :: proc(site: ^Site, local: Vec2) -> Vec2 {
    if site == nil do return local
    cosine, sine := math.cos(site.yaw), math.sin(site.yaw)
    return {site.origin.x + local.x * cosine + local.z * sine, site.origin.z - local.x * sine + local.z * cosine}
}

plan_world_position :: proc(plan: ^Plan, local: Vec2) -> Vec2 {
    if plan == nil do return local
    cosine, sine := math.cos(plan.world_yaw), math.sin(plan.world_yaw)
    return {
        plan.world_origin.x + local.x * cosine + local.z * sine,
        plan.world_origin.z - local.x * sine + local.z * cosine,
    }
}

plan_world_yaw :: proc(plan: ^Plan, local_yaw: f32) -> f32 {
    if plan == nil do return local_yaw
    return local_yaw + plan.world_yaw
}

site_suitability :: proc(site: ^Site) -> f32 {
    if site == nil || !site.enabled do return 0
    backland_good, backland_total := 0, 0
    shore_good, shore_total := 0, 0
    basin_good, basin_total := 0, 0
    entrance_good, entrance_total := 0, 0
    for z in 0 ..< GRID_HEIGHT {
        for x in 0 ..< GRID_WIDTH {
            value := site_cell(site, x, z)
            if z < 4 {
                backland_total += 1
                if value == .Land || value == .Shore || value == .Blocked do backland_good += 1
            } else if z == 4 {
                shore_total += 1
                if value == .Shore || value == .Water {
                    shore_good += 1
                }
            } else {
                basin_total += 1
                if value == .Water do basin_good += 1
            }
            if x >= 12 && x <= 14 && z >= 5 {
                entrance_total += 1
                if value == .Water do entrance_good += 1
            }
        }
    }
    backland := f32(backland_good) / f32(max(backland_total, 1))
    shoreline := f32(shore_good) / f32(max(shore_total, 1))
    basin := f32(basin_good) / f32(max(basin_total, 1))
    entrance := f32(entrance_good) / f32(max(entrance_total, 1))
    return clamp(backland * .22 + shoreline * .23 + basin * .35 + entrance * .20, 0, 1)
}

add_segment :: proc(plan: ^Plan, kind: Segment_Kind, ax, az, bx, bz: int, width: f32) {
    if plan == nil || plan.segment_count >= len(plan.segments) do return
    plan.segments[plan.segment_count] = {kind, grid_position(ax, az), grid_position(bx, bz), width}
    plan.segment_count += 1
}

add_segment_world :: proc(plan: ^Plan, kind: Segment_Kind, a, b: Vec2, width: f32) {
    if plan == nil || plan.segment_count >= len(plan.segments) do return
    plan.segments[plan.segment_count] = {kind, a, b, width}
    plan.segment_count += 1
}

add_breakwater_segment :: proc(plan: ^Plan, ax, az, bx, bz: int, width: f32) {
    if plan == nil do return
    dx, dz := bx - ax, bz - az
    steps := max(abs(dx), abs(dz))
    if steps == 0 {
        set_cell(plan, ax, az, .Breakwater)
    } else {
        for step in 0 ..= steps {
            x := (ax * (steps - step) + bx * step + steps / 2) / steps
            z := (az * (steps - step) + bz * step + steps / 2) / steps
            set_cell(plan, x, z, .Breakwater)
        }
    }
    // Existing boundary recipes express relative mass in the 4.5--6 range.
    // Convert that design weight to a realistic 10--12 m rubble-mound toe;
    // the renderer derives the narrower walkable crown from this dimension.
    toe_width := clamp(width * 2, f32(10), BREAKWATER_TOE_WIDTH_METERS)
    add_segment(plan, .Breakwater, ax, az, bx, bz, toe_width)
}

add_prop :: proc(plan: ^Plan, kind: Prop_Kind, x, z: int, yaw: f32 = 0) {
    if plan == nil || plan.prop_count >= len(plan.props) do return
    plan.props[plan.prop_count] = {kind, grid_position(x, z), yaw}
    plan.prop_count += 1
}

add_breakwater_beacon :: proc(plan: ^Plan, segment: Segment, at_end: bool = true) {
    if plan == nil || plan.prop_count >= len(plan.props) || segment.kind != .Breakwater do return
    dx, dz := segment.b.x - segment.a.x, segment.b.z - segment.a.z
    length := f32(math.sqrt(f64(dx * dx + dz * dz)))
    if length <= .01 do return
    // Pull the beacon a full metre back from the exposed tip. Continuous
    // centerline placement works for diagonal moles without guessing which
    // raster cell happened to receive the breakwater mark.
    inset := min(f32(1), length * .25)
    direction_x, direction_z := dx / length, dz / length
    position := segment.b
    if at_end {
        position = {segment.b.x - direction_x * inset, segment.b.z - direction_z * inset}
    } else {
        position = {segment.a.x + direction_x * inset, segment.a.z + direction_z * inset}
    }
    plan.props[plan.prop_count] = {
        kind     = .Beacon,
        position = position,
        yaw      = math.atan2(dx, dz),
    }
    plan.prop_count += 1
}

add_quay :: proc(plan: ^Plan, ax, az, bx, bz: int, width: f32) {
    if plan == nil do return
    if ax == bx {
        lo, hi := min(az, bz), max(az, bz)
        for z in lo ..= hi do set_cell(plan, ax, z, .Quay)
    } else if az == bz {
        lo, hi := min(ax, bx), max(ax, bx)
        for x in lo ..= hi do set_cell(plan, x, az, .Quay)
    }
    add_segment(plan, .Quay, ax, az, bx, bz, width)
}

seed_bit :: proc(seed: u32, bit: uint) -> bool {
    mixed := seed * 0x9e3779b9
    mixed = (mixed ~ (mixed >> 16)) * 0x7feb352d
    return ((mixed >> bit) & 1) != 0
}

append_slip_at :: proc(plan: ^Plan, state: []u8, x, z: int, yaw: f32) {
    append_slip_world(plan, state, grid_position(x, z), x, z, yaw)
}

append_slip_world :: proc(plan: ^Plan, state: []u8, position: Vec2, x, z: int, yaw: f32) {
    if plan == nil || plan.slip_count >= len(plan.slips) do return
    if x <= 2 || x >= GRID_WIDTH - 3 do return
    berth_roll := (u32(x * 73 + z * 151) ~ plan.layout_seed) & 3
    occupied := variation(state, x, z, plan.layout_seed) || berth_roll != 0
    classes := [3]boats.Class{.Sail, .Motor, .Fishing}
    class := classes[(x + z + int(plan.layout_seed & 3)) % len(classes)]
    plan.slips[plan.slip_count] = {
        position = position,
        yaw      = yaw,
        class    = class,
        occupied = occupied,
        kind     = .Slip,
    }
    plan.slip_count += 1
    set_cell(plan, x, z, .Slip)
}

append_mooring_at :: proc(plan: ^Plan, state: []u8, x, z: int, yaw: f32) {
    if plan == nil || plan.slip_count >= len(plan.slips) do return
    if x <= BREAKWATER_WEST_X || x >= BREAKWATER_EAST_X do return
    berth_roll := (u32(x * 97 + z * 193) ~ plan.layout_seed) & 3
    classes := [2]boats.Class{.Sail, .Motor}
    plan.slips[plan.slip_count] = {
        position = grid_position(x, z),
        yaw      = yaw,
        class    = classes[(x + z + int(plan.layout_seed & 1)) % len(classes)],
        occupied = variation(state, x, z, plan.layout_seed) || berth_roll != 0,
        kind     = .Swing_Mooring,
    }
    plan.slip_count += 1
    set_cell(plan, x, z, .Mooring)
}

add_pier :: proc(
    plan: ^Plan,
    state: []u8,
    x, start_z, end_z: int,
    berth_stride: int = 3,
    west_berths: bool = true,
    east_berths: bool = true,
    hammerhead: bool = false,
) {
    if plan == nil || end_z <= start_z do return
    // Projecting sections occupy the inner working basin. The outer band is
    // reserved as maneuvering water between terminal heads and breakwaters.
    safe_end_z := min(end_z, OUTER_SECTION_LIMIT_Z)
    if safe_end_z <= start_z do return
    form := hammerhead ? Section_Form.Hammerhead : Section_Form.Straight
    plan.section_form_counts[int(form)] += 1
    for z in start_z ..= safe_end_z do set_cell(plan, x, z, .Main_Pier)
    add_segment(plan, .Main_Pier, x, start_z - 1, x, safe_end_z, MAIN_PIER_WIDTH_METERS)
    for z := start_z + 2; z <= safe_end_z - (hammerhead ? 2 : 0); z += berth_stride {
        if west_berths {
            set_cell(plan, x - 1, z, .Finger_Pier)
            pier := grid_position(x, z)
            add_segment_world(
                plan,
                .Finger_Pier,
                pier,
                {pier.x - FINGER_PIER_LENGTH_METERS, pier.z},
                FINGER_PIER_WIDTH_METERS,
            )
            add_slip(plan, state, x, z, -1)
        }
        if east_berths {
            set_cell(plan, x + 1, z, .Finger_Pier)
            pier := grid_position(x, z)
            add_segment_world(
                plan,
                .Finger_Pier,
                pier,
                {pier.x + FINGER_PIER_LENGTH_METERS, pier.z},
                FINGER_PIER_WIDTH_METERS,
            )
            add_slip(plan, state, x, z, 1)
        }
    }
    if hammerhead {
        left, right := x - 2, x + 2
        for hx in left ..= right do set_cell(plan, hx, safe_end_z, .Main_Pier)
        add_segment(plan, .Main_Pier, left, safe_end_z, right, safe_end_z, 2.5)
    }
}

add_dogleg_pier :: proc(plan: ^Plan, state: []u8, x, turn_z, direction: int) {
    if plan == nil || direction == 0 do return
    start_z, end_z := 5, OUTER_SECTION_LIMIT_Z
    bend_x := x + (direction < 0 ? -2 : 2)
    if bend_x <= BREAKWATER_WEST_X || bend_x >= BREAKWATER_EAST_X do return
    plan.section_form_counts[int(Section_Form.Dogleg)] += 1

    for z in start_z ..= turn_z do set_cell(plan, x, z, .Main_Pier)
    step := direction < 0 ? -1 : 1
    for px := x; px != bend_x + step; px += step do set_cell(plan, px, turn_z, .Main_Pier)
    for z in turn_z ..= end_z do set_cell(plan, bend_x, z, .Main_Pier)
    add_segment(plan, .Main_Pier, x, start_z - 1, x, turn_z, MAIN_PIER_WIDTH_METERS)
    add_segment(plan, .Main_Pier, x, turn_z, bend_x, turn_z, MAIN_PIER_WIDTH_METERS)
    add_segment(plan, .Main_Pier, bend_x, turn_z, bend_x, end_z, MAIN_PIER_WIDTH_METERS)

    // Berths follow the protected inside faces; the bend itself remains clear.
    for z := 7; z <= turn_z - 2; z += 3 {
        add_slip(plan, state, x, z, -1)
        add_slip(plan, state, x, z, 1)
    }
    inner_side := direction < 0 ? 1 : -1
    add_slip(plan, state, bend_x, end_z - 1, inner_side)
}

add_rasterized_pier_segment :: proc(plan: ^Plan, ax, az, bx, bz: int, width: f32) {
    if plan == nil do return
    dx, dz := bx - ax, bz - az
    steps := max(abs(dx), abs(dz))
    if steps == 0 {
        set_cell(plan, ax, az, .Main_Pier)
    } else {
        for step in 0 ..= steps {
            x := (ax * (steps - step) + bx * step + steps / 2) / steps
            z := (az * (steps - step) + bz * step + steps / 2) / steps
            set_cell(plan, x, z, .Main_Pier)
        }
    }
    add_segment(plan, .Main_Pier, ax, az, bx, bz, width)
}

add_forked_pier :: proc(plan: ^Plan, state: []u8, x: int) {
    if plan == nil do return
    stem_end_z, branch_end_z := 9, OUTER_SECTION_LIMIT_Z
    if !area_is_water(plan, x - 3, x + 3, 5, branch_end_z) do return
    plan.section_form_counts[int(Section_Form.Forked_Pier)] += 1
    add_rasterized_pier_segment(plan, x, 4, x, stem_end_z, MAIN_PIER_WIDTH_METERS)
    add_rasterized_pier_segment(plan, x, stem_end_z, x - 2, branch_end_z, 2.15)
    add_rasterized_pier_segment(plan, x, stem_end_z, x + 2, branch_end_z, 2.15)

    // Two stem berths and one berth outside each diagonal arm keep the fork's
    // center water room open. Branch yaw follows the actual segment tangent.
    append_slip_at(plan, state, x - 2, 7, -math.PI * .5)
    append_slip_at(plan, state, x + 2, 7, math.PI * .5)
    branch_yaw := f32(math.atan2(f64(2), f64(branch_end_z - stem_end_z)))
    append_slip_at(plan, state, x - 2, 11, -branch_yaw)
    append_slip_at(plan, state, x + 2, 11, branch_yaw)
}

add_quay_mole :: proc(plan: ^Plan, state: []u8, x, end_z, head_direction: int) {
    if plan == nil || head_direction == 0 do return
    safe_end_z := min(end_z, OUTER_SECTION_LIMIT_Z - 1)
    // Turn the short head away from the protected berth face. The old inward
    // head occupied the same water as the final parallel-moored hull.
    head_x := x - (head_direction < 0 ? -2 : 2)
    if head_x <= BREAKWATER_WEST_X || head_x >= BREAKWATER_EAST_X do return
    plan.section_form_counts[int(Section_Form.Quay_Mole)] += 1
    add_quay(plan, x, 4, x, safe_end_z, 4.8)
    add_quay(plan, x, safe_end_z, head_x, safe_end_z, 5.2)

    berth_side := head_direction < 0 ? -1 : 1
    berth_x := x + berth_side * 3
    for z := 6; z <= safe_end_z; z += 3 {
        append_slip_at(plan, state, berth_x, z, 0)
    }
}

add_natural_jetty :: proc(plan: ^Plan, state: []u8, x, end_z, inward: int, roll: u32) {
    if plan == nil || inward == 0 do return
    safe_end_z := min(end_z, OUTER_SECTION_LIMIT_Z - 1)
    bend_x := x + inward
    if bend_x <= BREAKWATER_WEST_X || bend_x >= BREAKWATER_EAST_X do return
    plan.section_form_counts[int(Section_Form.Natural_Jetty)] += 1

    first_turn_z := 8 + int(roll & 1)
    second_turn_z := min(first_turn_z + 2, safe_end_z)
    for z in 4 ..= first_turn_z do set_cell(plan, x, z, .Natural_Jetty)
    set_cell(plan, bend_x, second_turn_z, .Natural_Jetty)
    for z in second_turn_z ..= safe_end_z do set_cell(plan, bend_x, z, .Natural_Jetty)
    add_segment(plan, .Natural_Jetty, x, 4, x, first_turn_z, 3.8)
    add_segment(plan, .Natural_Jetty, x, first_turn_z, bend_x, second_turn_z, 4.2)
    add_segment(plan, .Natural_Jetty, bend_x, second_turn_z, bend_x, safe_end_z, 3.5)

    // Small craft lie along the protected inside face of the rubble jetty.
    berth_x := x + inward * 3
    for z := 6; z <= safe_end_z; z += 3 {
        append_slip_at(plan, state, berth_x, z, 0)
    }
}

area_is_water :: proc(plan: ^Plan, min_x, max_x, min_z, max_z: int) -> bool {
    if plan == nil do return false
    for z in min_z ..= max_z {
        for x in min_x ..= max_x {
            value := cell(plan, x, z)
            if value != .Water do return false
        }
    }
    return true
}

add_floating_pontoon :: proc(plan: ^Plan, state: []u8, start_x, end_x, z: int) {
    if plan == nil || end_x - start_x < 4 do return
    // The footprint includes finger piers and hull centers on both faces. It
    // must be a genuinely empty water room; this prevents a transverse fill
    // proposal from overwriting an existing longitudinal section.
    if !area_is_water(plan, start_x, end_x, z - 2, z + 2) do return
    plan.section_form_counts[int(Section_Form.Floating_Pontoon)] += 1
    for x in start_x ..= end_x do set_cell(plan, x, z, .Main_Pier)
    add_segment(plan, .Main_Pier, start_x, z, end_x, z, MAIN_PIER_WIDTH_METERS)
    for x := start_x + 1; x <= end_x - 1; x += 3 {
        set_cell(plan, x, z - 1, .Finger_Pier)
        set_cell(plan, x, z + 1, .Finger_Pier)
        pier := grid_position(x, z)
        add_segment_world(
            plan,
            .Finger_Pier,
            pier,
            {pier.x, pier.z - FINGER_PIER_LENGTH_METERS},
            FINGER_PIER_WIDTH_METERS,
        )
        add_segment_world(
            plan,
            .Finger_Pier,
            pier,
            {pier.x, pier.z + FINGER_PIER_LENGTH_METERS},
            FINGER_PIER_WIDTH_METERS,
        )
        append_slip_world(plan, state, {pier.x, pier.z - BERTH_CENTER_OFFSET_METERS}, x, z - 1, math.PI)
        append_slip_world(plan, state, {pier.x, pier.z + BERTH_CENTER_OFFSET_METERS}, x, z + 1, 0)
    }
}

add_island_quay :: proc(plan: ^Plan, state: []u8, start_x, end_x, start_z: int) {
    if plan == nil || end_x - start_x < 3 do return
    end_z := start_z + 1
    // Include both parallel-moored hull rows in the reservation. The island
    // may only occupy an untouched water room, never overwrite a lane or a
    // previously accepted section.
    if !area_is_water(plan, start_x, end_x, start_z - 3, end_z + 3) do return
    plan.section_form_counts[int(Section_Form.Island_Quay)] += 1
    for z in start_z ..= end_z {
        for x in start_x ..= end_x do set_cell(plan, x, z, .Quay)
    }
    add_quay(plan, start_x, start_z, end_x, start_z, 4.8)
    add_quay(plan, end_x, start_z, end_x, end_z, 4.8)
    add_quay(plan, end_x, end_z, start_x, end_z, 4.8)
    add_quay(plan, start_x, end_z, start_x, start_z, 4.8)
    for x := start_x; x <= end_x; x += 3 {
        append_slip_at(plan, state, x, start_z - 3, math.PI * .5)
        append_slip_at(plan, state, x, end_z + 3, -math.PI * .5)
    }
    add_prop(plan, .Bollard, start_x, start_z)
    add_prop(plan, .Bollard, end_x, end_z)
}

add_mooring_field :: proc(plan: ^Plan, state: []u8, start_x, start_z: int, columns: int = 2, rows: int = 2) {
    if plan == nil || columns < 1 || rows < 1 do return
    spacing_cells := int(MOORING_FIELD_SPACING_METERS / CELL_METERS)
    end_x := start_x + (columns - 1) * spacing_cells
    end_z := start_z + (rows - 1) * spacing_cells
    // Swing circles need more water than the marker itself. Reserve a cell
    // around the outside of the field. Swing moorings are deliberately much
    // farther apart than conventional slips because each vessel rotates
    // through its complete rode-plus-hull watch circle.
    if !area_is_water(plan, start_x - 1, end_x + 1, start_z - 1, end_z + 1) do return
    plan.section_form_counts[int(Section_Form.Mooring_Field)] += 1
    field_yaw := (plan.layout_seed & 1) == 0 ? f32(.10) : f32(-.10)
    for row in 0 ..< rows {
        for column in 0 ..< columns {
            x := start_x + column * spacing_cells
            z := start_z + row * spacing_cells
            yaw_variation := f32((row + column) & 1) * .08 - .04
            append_mooring_at(plan, state, x, z, field_yaw + yaw_variation)
        }
    }
}

style_uses_mooring_field :: proc(style: Basin_Style, seed: u32) -> bool {
    switch style {
    case .Island_Harbour, .Lagoon_Marina:
        return true
    case .Stone_Cove:
        return (seed & 3) != 0
    case .Civic_Marina:
        return (seed & 7) == 0
    case .Fishing_Quay, .Working_Port, .Ferry_Quay, .Boat_Yard:
        return false
    }
    return false
}

seed_mooring_field :: proc(plan: ^Plan, state: []u8, seed: u32) -> bool {
    if plan == nil || !style_uses_mooring_field(plan.style, seed) do return false
    prefer_west := seed_bit(seed, 14)
    for side_attempt in 0 ..< 2 {
        west := side_attempt == 0 ? prefer_west : !prefer_west
        trial := plan^
        field_x := west ? 6 : 20
        // Longitudinal pairs fit inside the protected basin while preserving
        // a full 24 m watch-circle separation and the central arrival lane.
        add_mooring_field(&trial, state, field_x, 8, 1, 2)
        if trial.section_form_counts[int(Section_Form.Mooring_Field)] ==
           plan.section_form_counts[int(Section_Form.Mooring_Field)] {
            continue
        }
        if !slips_have_clearance(&trial) do continue
        if measure_structure_overlaps(&trial) > 0 do continue
        if !structures_have_breakwater_clearance(&trial) do continue
        plan^ = trial
        return true
    }
    return false
}

is_spacing_structure :: proc(value: Cell) -> bool {
    return(
        value == .Quay ||
        value == .Breakwater ||
        value == .Natural_Jetty ||
        value == .Main_Pier ||
        value == .Finger_Pier ||
        value == .Slip ||
        value == .Mooring \
    )
}

measure_site_conformance :: proc(plan: ^Plan, site: ^Site) -> f32 {
    if plan == nil do return 1
    if site == nil || !site.enabled do return 0
    violations, samples := 0, 0
    for z in 0 ..< GRID_HEIGHT {
        for x in 0 ..< GRID_WIDTH {
            planned := cell(plan, x, z)
            existing := site_cell(site, x, z)
            fits := true
            relevant := true
            switch planned {
            case .Water:
                relevant = false
            case .Land:
                // Existing occupied backland can remain around the marina.
                fits = existing == .Land || existing == .Shore || existing == .Blocked
            case .Building, .Props:
                fits = existing == .Land || existing == .Shore
            case .Quay, .Breakwater, .Natural_Jetty:
                fits = existing == .Water || existing == .Shore || (existing == .Land && z <= 4)
            case .Main_Pier, .Finger_Pier, .Slip, .Mooring, .Channel:
                fits = existing == .Water
            }
            if !relevant do continue
            samples += 1
            if !fits do violations += 1
        }
    }
    if samples == 0 do return 1
    return f32(violations) / f32(samples)
}

plan_conforms_to_site :: proc(plan: ^Plan, site: ^Site) -> bool {
    if plan == nil do return false
    if site == nil || !site.enabled do return true
    if measure_site_conformance(plan, site) > MAX_SITE_CONFORMANCE_BADNESS do return false
    for z in 0 ..< GRID_HEIGHT {
        for x in 0 ..< GRID_WIDTH {
            if site_cell(site, x, z) != .Blocked do continue
            #partial switch cell(plan, x, z) {
            case .Main_Pier, .Finger_Pier, .Slip, .Mooring, .Channel:
                return false
            }
        }
    }
    return true
}

measure_spacing :: proc(plan: ^Plan) -> (density, badness_density: f32) {
    if plan == nil do return 0, 1
    // The shoreline and outer breakwater are boundary conditions, so only the
    // navigable basin interior contributes to the density measurement.
    min_x, max_x := 3, GRID_WIDTH - 4
    min_z, max_z := 5, GRID_HEIGHT - 4
    sample_count, occupied_count := 0, 0
    crowded_excess, empty_windows, window_count := 0, 0, 0
    edge_clearance_violations, edge_samples := 0, 0
    for z in min_z ..= max_z {
        for x in min_x ..= max_x {
            sample_count += 1
            if is_spacing_structure(cell(plan, x, z)) do occupied_count += 1

            local_occupied := 0
            for dz in -2 ..= 2 {
                for dx in -2 ..= 2 {
                    if is_spacing_structure(cell(plan, x + dx, z + dz)) {
                        local_occupied += 1
                    }
                }
            }
            // More than 11 occupied cells in a 5x5 navigation neighborhood is
            // visually and operationally cramped. Completely empty windows
            // indicate dead basin area, but carry a gentler penalty.
            if local_occupied > 11 do crowded_excess += local_occupied - 11
            if local_occupied == 0 do empty_windows += 1
            window_count += 1

        }
    }
    for z in 5 ..< GRID_HEIGHT {
        for x in 0 ..< GRID_WIDTH {
            value := cell(plan, x, z)
            if value != .Slip &&
               value != .Mooring &&
               value != .Quay &&
               value != .Natural_Jetty &&
               value != .Main_Pier &&
               value != .Finger_Pier {
                continue
            }
            edge_samples += 1
            too_close := false
            for dz in -MIN_OUTER_CLEARANCE_CELLS + 1 ..= MIN_OUTER_CLEARANCE_CELLS - 1 {
                for dx in -MIN_OUTER_CLEARANCE_CELLS + 1 ..= MIN_OUTER_CLEARANCE_CELLS - 1 {
                    bx, bz := x + dx, z + dz
                    if cell(plan, bx, bz) == .Breakwater {
                        required := bz >= 17 ? MIN_OUTER_CLEARANCE_CELLS : MIN_EDGE_CLEARANCE_CELLS
                        if dx * dx + dz * dz < required * required {
                            too_close = true
                        }
                    }
                }
            }
            if too_close do edge_clearance_violations += 1
        }
    }
    if sample_count == 0 || window_count == 0 do return 0, 1
    density = f32(occupied_count) / f32(sample_count)
    crowding := f32(crowded_excess) / f32(window_count * 14)
    emptiness := f32(empty_windows) / f32(window_count)
    edge_clearance := f32(0)
    if edge_samples > 0 {
        edge_clearance = f32(edge_clearance_violations) / f32(edge_samples)
    }
    // A useful marina needs enough structure to shape water rooms without
    // consuming the fairways. Penalize only the amount outside that band.
    density_penalty := f32(0)
    if density < .10 do density_penalty = (.10 - density) / .10
    if density > .30 do density_penalty = (density - .30) / .30
    berth_penalty := f32(0)
    berth_pairs := 0
    for a in 0 ..< plan.slip_count {
        for b in a + 1 ..< plan.slip_count {
            dx := plan.slips[a].position.x - plan.slips[b].position.x
            dz := plan.slips[a].position.z - plan.slips[b].position.z
            distance_squared := dx * dx + dz * dz
            required := required_berth_spacing(plan.slips[a], plan.slips[b])
            required_squared := required * required
            if distance_squared < required_squared {
                berth_penalty += (required_squared - distance_squared) / required_squared
            }
            berth_pairs += 1
        }
    }
    plan.berth_spacing_badness = 0
    if berth_pairs > 0 {
        plan.berth_spacing_badness = clamp(berth_penalty / f32(max(plan.slip_count, 1)), 0, 1)
    }
    badness_density = clamp(
        crowding * .55 +
        emptiness * .15 +
        density_penalty * .30 +
        edge_clearance * .70 +
        plan.berth_spacing_badness * 1.25,
        0,
        1,
    )
    return
}

required_berth_spacing :: proc(a, b: Slip) -> f32 {
    if a.kind == .Swing_Mooring && b.kind == .Swing_Mooring {
        return MOORING_FIELD_SPACING_METERS
    }
    if a.kind == .Swing_Mooring || b.kind == .Swing_Mooring {
        return MIN_FAIRWAY_WIDTH_METERS
    }
    return MIN_SLIP_CENTER_SPACING_METERS
}

slips_have_clearance :: proc(plan: ^Plan) -> bool {
    if plan == nil do return false
    for a in 0 ..< plan.slip_count {
        for b in a + 1 ..< plan.slip_count {
            dx := plan.slips[a].position.x - plan.slips[b].position.x
            dz := plan.slips[a].position.z - plan.slips[b].position.z
            required := required_berth_spacing(plan.slips[a], plan.slips[b])
            if dx * dx + dz * dz < required * required do return false
        }
    }
    return true
}

measure_structure_overlaps :: proc(plan: ^Plan) -> f32 {
    if plan == nil || plan.slip_count == 0 do return 0
    overlapping_slips := 0
    for slip in plan.slips[:plan.slip_count] {
        spec := boats.specifications(slip.class)
        forward_x, forward_z := math.sin(slip.yaw), math.cos(slip.yaw)
        side_x, side_z := math.cos(slip.yaw), -math.sin(slip.yaw)
        overlaps := false
        for segment in plan.segments[:plan.segment_count] {
            // Finger piers intentionally terminate alongside their assigned
            // hulls; all load-bearing and protective structures must clear.
            if segment.kind == .Finger_Pier do continue
            vx, vz := segment.b.x - segment.a.x, segment.b.z - segment.a.z
            length_squared := vx * vx + vz * vz
            if length_squared <= .001 do continue
            wx := slip.position.x - segment.a.x
            wz := slip.position.z - segment.a.z
            t := clamp((wx * vx + wz * vz) / length_squared, 0, 1)
            closest_x := segment.a.x + vx * t
            closest_z := segment.a.z + vz * t
            dx := slip.position.x - closest_x
            dz := slip.position.z - closest_z
            inverse_length := 1 / f32(math.sqrt(f64(length_squared)))
            normal_x := -vz * inverse_length
            normal_z := vx * inverse_length
            hull_radius :=
                abs(forward_x * normal_x + forward_z * normal_z) * spec.length * .5 +
                abs(side_x * normal_x + side_z * normal_z) * spec.beam * .5
            required := segment.width * .5 + hull_radius + .75
            if dx * dx + dz * dz < required * required {
                overlaps = true
                break
            }
        }
        if overlaps do overlapping_slips += 1
    }
    return f32(overlapping_slips) / f32(plan.slip_count)
}

slips_clear_structures :: proc(plan: ^Plan) -> bool {
    return plan != nil && measure_structure_overlaps(plan) == 0
}

interior_fill_density :: proc(plan: ^Plan) -> f32 {
    if plan == nil do return 0
    occupied, available := 0, 0
    for z in 5 ..= OUTER_SECTION_LIMIT_Z {
        for x in BREAKWATER_WEST_X + 1 ..< BREAKWATER_EAST_X {
            if x >= 12 && x <= 14 do continue
            available += 1
            value := cell(plan, x, z)
            if value == .Quay ||
               value == .Natural_Jetty ||
               value == .Main_Pier ||
               value == .Finger_Pier ||
               value == .Slip ||
               value == .Mooring {
                occupied += 1
            }
        }
    }
    if available == 0 do return 0
    return f32(occupied) / f32(available)
}

target_fill_density :: proc(style: Basin_Style) -> f32 {
    switch style {
    case .Fishing_Quay:
        return .21
    case .Civic_Marina:
        return .24
    case .Island_Harbour:
        return .19
    case .Working_Port:
        return .20
    case .Stone_Cove:
        return .18
    case .Ferry_Quay:
        return .22
    case .Boat_Yard:
        return .23
    case .Lagoon_Marina:
        return .17
    }
    return .21
}

quality_score :: proc(plan: ^Plan) -> f32 {
    if plan == nil do return 2
    density_error := abs(plan.fill_density - plan.target_fill_density)
    frontage_interest := f32(0)
    switch plan.shoreline_form {
    case .Natural_Shore:
        frontage_interest = .10
    case .Straight_Quay:
    case .West_Apron, .East_Apron:
        frontage_interest = .02
    case .Split_Aprons:
        frontage_interest = .08
    case .Stepped_Quays:
        frontage_interest = .13
    }
    section_interest := f32(0)
    if plan.section_form_counts[int(Section_Form.Hammerhead)] > 0 do section_interest += .045
    if plan.section_form_counts[int(Section_Form.Dogleg)] > 0 do section_interest += .015
    if plan.section_form_counts[int(Section_Form.Quay_Mole)] > 0 do section_interest += .01
    if plan.section_form_counts[int(Section_Form.Natural_Jetty)] > 0 do section_interest += .015
    if plan.section_form_counts[int(Section_Form.Floating_Pontoon)] > 0 do section_interest += .015
    if plan.section_form_counts[int(Section_Form.Island_Quay)] > 0 do section_interest += .025
    if plan.section_form_counts[int(Section_Form.Forked_Pier)] > 0 do section_interest += .035
    if plan.section_form_counts[int(Section_Form.Mooring_Field)] > 0 do section_interest += .04
    missing_mooring_field := f32(0)
    if (plan.style == .Island_Harbour || plan.style == .Lagoon_Marina) &&
       plan.section_form_counts[int(Section_Form.Mooring_Field)] == 0 {
        // A sheltered-harbor candidate without any swinging berths has failed
        // its archetype even when its generic density score is attractive.
        missing_mooring_field = .4
    }
    return clamp(
        plan.spacing_badness_density +
        plan.berth_spacing_badness * 1.5 +
        plan.structure_overlap_badness * 1.5 +
        plan.site_conformance_badness * 2 +
        density_error * 2 -
        frontage_interest -
        section_interest +
        missing_mooring_field,
        0,
        2,
    )
}

mix_seed :: proc(value: u32) -> u32 {
    mixed := (value ~ (value >> 16)) * 0x7feb352d
    mixed = (mixed ~ (mixed >> 15)) * 0x846ca68b
    return mixed ~ (mixed >> 16)
}

choose_boundary_form :: proc(style: Basin_Style, roll: u32) -> Boundary_Form {
    value := int(roll % 100)
    switch style {
    case .Fishing_Quay, .Working_Port:
        if value < 34 do return .Enclosed_Basin
        if value < 58 do return .Offset_West
        if value < 78 do return .Offset_East
        if value < 92 do return .Wide_Twin_Moles
        return .Open_Cove
    case .Civic_Marina, .Ferry_Quay:
        if value < 35 do return .Wide_Twin_Moles
        if value < 63 do return .Enclosed_Basin
        if value < 77 do return .Offset_West
        if value < 91 do return .Offset_East
        return .Open_Cove
    case .Island_Harbour, .Stone_Cove, .Lagoon_Marina:
        if value < 34 do return .Open_Cove
        if value < 57 do return .Offset_West
        if value < 80 do return .Offset_East
        if value < 93 do return .Wide_Twin_Moles
        return .Enclosed_Basin
    case .Boat_Yard:
        if value < 30 do return .Offset_West
        if value < 60 do return .Offset_East
        if value < 80 do return .Enclosed_Basin
        if value < 94 do return .Wide_Twin_Moles
        return .Open_Cove
    }
    return .Enclosed_Basin
}

choose_shoreline_form :: proc(style: Basin_Style, roll: u32) -> Shoreline_Form {
    value := int(roll % 100)
    switch style {
    case .Fishing_Quay, .Working_Port, .Boat_Yard:
        if value < 12 do return .Natural_Shore
        if value < 27 do return .Straight_Quay
        if value < 47 do return .West_Apron
        if value < 67 do return .East_Apron
        if value < 86 do return .Split_Aprons
        return .Stepped_Quays
    case .Civic_Marina, .Ferry_Quay:
        if value < 8 do return .Natural_Shore
        if value < 32 do return .Straight_Quay
        if value < 49 do return .West_Apron
        if value < 66 do return .East_Apron
        if value < 85 do return .Split_Aprons
        return .Stepped_Quays
    case .Island_Harbour, .Stone_Cove, .Lagoon_Marina:
        if value < 34 do return .Natural_Shore
        if value < 46 do return .Straight_Quay
        if value < 59 do return .West_Apron
        if value < 72 do return .East_Apron
        if value < 84 do return .Split_Aprons
        return .Stepped_Quays
    }
    return .Straight_Quay
}

add_quay_apron :: proc(plan: ^Plan, state: []u8, start_x, end_x, front_z: int) {
    if plan == nil || end_x - start_x < 3 || front_z <= 4 do return
    for z in 4 ..= front_z {
        for x in start_x ..= end_x do set_cell(plan, x, z, .Quay)
    }
    add_quay(plan, start_x, 4, start_x, front_z, 5)
    add_quay(plan, start_x, front_z, end_x, front_z, 5.5)
    add_quay(plan, end_x, front_z, end_x, 4, 5)
    // A short service pier turns the apron into a complete working quay
    // complex. It supplies properly spaced berths without occupying the
    // central arrival lane or relying on later proposals to make it viable.
    dock_x := (start_x + end_x) / 2
    add_pier(plan, state, dock_x, front_z + 1, min(front_z + 7, OUTER_SECTION_LIMIT_Z - 1), 3, true, true, false)
    add_prop(plan, .Bollard, start_x, front_z)
    add_prop(plan, .Bollard, end_x, front_z)
}

build_shoreline :: proc(plan: ^Plan, state: []u8, form: Shoreline_Form, seed: u32) {
    if plan == nil do return
    depth_variation := seed_bit(seed, 10) ? 1 : 0
    switch form {
    case .Natural_Shore:
    case .Straight_Quay:
        for x in 0 ..< GRID_WIDTH do set_cell(plan, x, 4, .Quay)
        add_quay(plan, 0, 4, GRID_WIDTH - 1, 4, 5)
    case .West_Apron:
        add_quay_apron(plan, state, 6, 11, 5 + depth_variation)
    case .East_Apron:
        add_quay_apron(plan, state, 15, 20, 5 + depth_variation)
    case .Split_Aprons:
        add_quay_apron(plan, state, 6, 11, 5)
        add_quay_apron(plan, state, 15, 20, 5)
    case .Stepped_Quays:
        if seed_bit(seed, 11) {
            add_quay_apron(plan, state, 6, 10, 5)
            add_quay_apron(plan, state, 16, 20, 6)
        } else {
            add_quay_apron(plan, state, 6, 10, 6)
            add_quay_apron(plan, state, 16, 20, 5)
        }
    }
}

build_boundary :: proc(plan: ^Plan, form: Boundary_Form, seed: u32) {
    if plan == nil do return
    switch form {
    case .Enclosed_Basin:
        west_tip := seed_bit(seed, 1) ? 10 : 9
        east_tip := seed_bit(seed, 2) ? 16 : 17
        west_knee := seed_bit(seed, 3) ? 17 : 18
        east_knee := seed_bit(seed, 4) ? 18 : 17
        add_breakwater_segment(plan, 3, 4, 3, west_knee, 5)
        add_breakwater_segment(plan, 3, west_knee, west_tip, 18, 5)
        add_breakwater_beacon(plan, plan.segments[plan.segment_count - 1])
        add_breakwater_segment(plan, 23, 4, 23, east_knee, 5)
        add_breakwater_segment(plan, 23, east_knee, east_tip, 18, 5)
        add_breakwater_beacon(plan, plan.segments[plan.segment_count - 1])
    case .Wide_Twin_Moles:
        add_breakwater_segment(plan, 3, 4, 3, 16, 5)
        add_breakwater_segment(plan, 3, 16, 8, 18, 5.5)
        add_breakwater_beacon(plan, plan.segments[plan.segment_count - 1])
        add_breakwater_segment(plan, 23, 4, 23, 16, 5)
        add_breakwater_segment(plan, 23, 16, 18, 18, 5.5)
        add_breakwater_beacon(plan, plan.segments[plan.segment_count - 1])
    case .Offset_West:
        add_breakwater_segment(plan, 3, 4, 3, 17, 5.5)
        add_breakwater_segment(plan, 3, 17, 10, 19, 6)
        add_breakwater_beacon(plan, plan.segments[plan.segment_count - 1])
        add_breakwater_segment(plan, 23, 4, 23, 13, 4.5)
        add_breakwater_segment(plan, 23, 13, 21, 15, 4.5)
        add_breakwater_beacon(plan, plan.segments[plan.segment_count - 1])
    case .Offset_East:
        add_breakwater_segment(plan, 23, 4, 23, 17, 5.5)
        add_breakwater_segment(plan, 23, 17, 16, 19, 6)
        add_breakwater_beacon(plan, plan.segments[plan.segment_count - 1])
        add_breakwater_segment(plan, 3, 4, 3, 13, 4.5)
        add_breakwater_segment(plan, 3, 13, 5, 15, 4.5)
        add_breakwater_beacon(plan, plan.segments[plan.segment_count - 1])
    case .Open_Cove:
        west_end := seed_bit(seed, 7) ? 11 : 12
        east_end := seed_bit(seed, 8) ? 12 : 11
        add_breakwater_segment(plan, 3, 4, 3, west_end, 4.5)
        add_breakwater_segment(plan, 23, 4, 23, east_end, 4.5)
        add_breakwater_beacon(plan, plan.segments[plan.segment_count - 2])
        add_breakwater_beacon(plan, plan.segments[plan.segment_count - 1])
    }
}

choose_section_form :: proc(style: Basin_Style, roll: u32) -> Section_Form {
    value := int(roll % 100)
    switch style {
    case .Fishing_Quay:
        if value < 33 do return .Quay_Mole
        if value < 56 do return .Straight
        if value < 71 do return .Floating_Pontoon
        if value < 84 do return .Dogleg
        if value < 92 do return .Island_Quay
        if value < 94 do return .Forked_Pier
        if value < 98 do return .Mooring_Field
        return .Hammerhead
    case .Civic_Marina:
        if value < 35 do return .Straight
        if value < 53 do return .Floating_Pontoon
        if value < 68 do return .Island_Quay
        if value < 78 do return .Forked_Pier
        if value < 86 do return .Hammerhead
        if value < 92 do return .Dogleg
        if value < 98 do return .Mooring_Field
        return .Quay_Mole
    case .Island_Harbour:
        if value < 25 do return .Island_Quay
        if value < 47 do return .Dogleg
        if value < 66 do return .Floating_Pontoon
        if value < 78 do return .Forked_Pier
        if value < 86 do return .Hammerhead
        if value < 91 do return .Straight
        if value < 98 do return .Mooring_Field
        return .Quay_Mole
    case .Working_Port:
        if value < 28 do return .Quay_Mole
        if value < 52 do return .Dogleg
        if value < 68 do return .Floating_Pontoon
        if value < 78 do return .Island_Quay
        if value < 86 do return .Forked_Pier
        if value < 92 do return .Straight
        if value < 98 do return .Mooring_Field
        return .Hammerhead
    case .Stone_Cove:
        if value < 46 do return .Natural_Jetty
        if value < 62 do return .Floating_Pontoon
        if value < 67 do return .Island_Quay
        if value < 81 do return .Quay_Mole
        if value < 91 do return .Dogleg
        if value < 93 do return .Forked_Pier
        if value < 98 do return .Mooring_Field
        return .Straight
    case .Ferry_Quay:
        if value < 38 do return .Quay_Mole
        if value < 62 do return .Straight
        if value < 75 do return .Floating_Pontoon
        if value < 85 do return .Island_Quay
        if value < 92 do return .Forked_Pier
        if value < 93 do return .Dogleg
        if value < 98 do return .Mooring_Field
        return .Natural_Jetty
    case .Boat_Yard:
        if value < 37 do return .Straight
        if value < 59 do return .Dogleg
        if value < 74 do return .Floating_Pontoon
        if value < 79 do return .Island_Quay
        if value < 87 do return .Forked_Pier
        if value < 91 do return .Quay_Mole
        if value < 97 do return .Mooring_Field
        return .Natural_Jetty
    case .Lagoon_Marina:
        if value < 20 do return .Island_Quay
        if value < 47 do return .Natural_Jetty
        if value < 65 do return .Floating_Pontoon
        if value < 76 do return .Forked_Pier
        if value < 85 do return .Dogleg
        if value < 88 do return .Straight
        if value < 97 do return .Mooring_Field
        return .Quay_Mole
    }
    return .Straight
}

section_lane_open :: proc(plan: ^Plan, anchor_x: int) -> bool {
    if plan == nil do return false
    for z in 5 ..= OUTER_SECTION_LIMIT_Z {
        for x in anchor_x - 3 ..= anchor_x + 3 {
            value := cell(plan, x, z)
            if value == .Quay ||
               value == .Natural_Jetty ||
               value == .Main_Pier ||
               value == .Finger_Pier ||
               value == .Slip ||
               value == .Mooring {
                return false
            }
        }
    }
    return true
}

structures_have_breakwater_clearance :: proc(plan: ^Plan) -> bool {
    if plan == nil do return false
    for z in 5 ..< GRID_HEIGHT {
        for x in 0 ..< GRID_WIDTH {
            value := cell(plan, x, z)
            if value != .Slip &&
               value != .Mooring &&
               value != .Quay &&
               value != .Natural_Jetty &&
               value != .Main_Pier &&
               value != .Finger_Pier {
                continue
            }
            for bz in 0 ..< GRID_HEIGHT {
                for bx in 0 ..< GRID_WIDTH {
                    if cell(plan, bx, bz) != .Breakwater do continue
                    required := MIN_EDGE_CLEARANCE_CELLS
                    if bz >= 17 do required = MIN_OUTER_CLEARANCE_CELLS
                    dx, dz := x - bx, z - bz
                    if dx * dx + dz * dz < required * required do return false
                }
            }
        }
    }
    return true
}

route_cell_clear :: proc(plan: ^Plan, x, z: int) -> bool {
    if plan == nil do return false
    if x < 0 || x >= GRID_WIDTH || z < 0 || z >= GRID_HEIGHT do return true
    half_fairway_cells := int(math.ceil(f64(MIN_FAIRWAY_WIDTH_METERS * .5 / CELL_METERS)))
    for dz in -half_fairway_cells ..= half_fairway_cells {
        for dx in -half_fairway_cells ..= half_fairway_cells {
            if is_spacing_structure(cell(plan, x + dx, z + dz)) do return false
        }
    }
    return true
}

clear_bay_column :: proc(plan: ^Plan, x: int) -> bool {
    if plan == nil do return false
    for z in 11 ..= 15 {
        if !route_cell_clear(plan, x, z) do return false
    }
    return true
}

find_route_column :: proc(plan: ^Plan, seed: u32) -> (int, bool) {
    if plan == nil do return 13, false
    prefer_west := seed_bit(seed, 12)
    for side_attempt in 0 ..< 2 {
        west := side_attempt == 0 ? prefer_west : !prefer_west
        offset_seed := mix_seed(seed ~ u32(side_attempt + 1) * u32(0x632be5ab))
        for offset in 0 ..< 6 {
            index := (int(offset_seed % 6) + offset) % 6
            x := west ? 5 + index : 16 + index
            if clear_bay_column(plan, x) do return x, true
        }
    }
    return 13, false
}

build_route_from_lanes :: proc(plan: ^Plan) {
    if plan == nil do return
    bay_x, found := find_route_column(plan, plan.layout_seed)
    if !found {
        bay_x = 13
    }
    plan.route = {
        points = {
            grid_position(13, GRID_HEIGHT + 3),
            grid_position(13, 19),
            grid_position(13, 16),
            grid_position(13, 15),
            grid_position(bay_x, 15),
            grid_position(bay_x, found ? 11 : 15),
            grid_position(bay_x, 15),
            grid_position(13, 15),
        },
        count  = 8,
    }
}

route_has_clearance :: proc(plan: ^Plan) -> bool {
    if plan == nil || plan.route.count < 2 do return false
    center_x := f32(GRID_WIDTH - 1) * .5
    center_z := f32(GRID_HEIGHT - 1) * .5
    for index in 0 ..< plan.route.count - 1 {
        a, b := plan.route.points[index], plan.route.points[index + 1]
        ax := int(a.x / CELL_METERS + center_x)
        az := int(a.z / CELL_METERS + center_z)
        bx := int(b.x / CELL_METERS + center_x)
        bz := int(b.z / CELL_METERS + center_z)
        if ax != bx && az != bz do return false
        if ax == bx {
            lo, hi := min(az, bz), max(az, bz)
            for z in lo ..= hi {
                if !route_cell_clear(plan, ax, z) do return false
            }
        } else {
            lo, hi := min(ax, bx), max(ax, bx)
            for x in lo ..= hi {
                if !route_cell_clear(plan, x, az) do return false
            }
        }
    }
    return true
}

variation_model :: proc() -> markov.Proc_Node {
    empty, grown, accent := 0, 1, 2
    return markov.node(
        markov.Proc_Tag.sequence,
        []markov.Proc_Attr{markov.kattr(.values, markov.values_count(3)), markov.kattr(.origin, true)},
        []markov.Proc_Node {
            markov.node(
                markov.Proc_Tag.one,
                []markov.Proc_Attr {
                    markov.kattr(
                        .in_,
                        markov.match_layer(
                            markov.match_row(markov.one_of(markov.sym(grown)), markov.one_of(markov.sym(empty))),
                        ),
                    ),
                    markov.kattr(.out, markov.write_layer(markov.write_row(markov.keep(), markov.sym(grown)))),
                    markov.kattr(.steps, 30),
                },
            ),
            markov.node(
                markov.Proc_Tag.one,
                []markov.Proc_Attr {
                    markov.kattr(.in_, markov.match_layer(markov.match_row(markov.one_of(markov.sym(grown))))),
                    markov.kattr(.out, markov.write_layer(markov.write_row(markov.sym(accent)))),
                    markov.kattr(.steps, 10),
                },
            ),
        },
    )
}

variation :: proc(state: []u8, x, z: int, seed: u32) -> bool {
    if len(state) == 49 {
        value := state[(z % 7) * 7 + (x % 7)]
        return value == 2 || (value == 1 && ((x * 17 + z * 31 + int(seed)) & 3) == 0)
    }
    mixed := seed ~ u32(x * 0x45d9f3b) ~ u32(z * 0x119de1f3)
    mixed = (mixed ~ (mixed >> 16)) * 0x7feb352d
    return (mixed & 3) != 0
}

add_slip :: proc(plan: ^Plan, state: []u8, pier_x, z, side: int) {
    x := pier_x + side
    yaw := side < 0 ? f32(-1.5707963) : f32(1.5707963)
    pier := grid_position(pier_x, z)
    append_slip_world(plan, state, {pier.x + f32(side) * BERTH_CENTER_OFFSET_METERS, pier.z}, x, z, yaw)
}

generate_candidate_for_site :: proc(
    seed, layout_seed: u32,
    candidate_index: int,
    site: ^Site,
    allocator := context.temp_allocator,
) -> Plan {
    previous_allocator := context.allocator
    context.allocator = allocator
    defer context.allocator = previous_allocator
    plan: Plan
    plan.seed = seed
    plan.layout_seed = layout_seed
    plan.candidate_index = candidate_index
    plan.candidates_evaluated = 1
    if site != nil && site.enabled {
        plan.world_conditioned = true
        plan.world_origin = site.origin
        plan.world_yaw = site.yaw
    }
    plan.style = Basin_Style(seed % u32(len(Basin_Style)))
    plan.boundary_form = choose_boundary_form(plan.style, mix_seed(layout_seed ~ u32(0xa511e9b3)))
    plan.shoreline_form = choose_shoreline_form(plan.style, mix_seed(layout_seed ~ u32(0x63d83595)))
    for &value in plan.cells do value = .Water

    // The Markov interpreter owns shared runtime state. Marina plans may be
    // generated concurrently by tests and streaming jobs, so serialize the
    // small variation pass while leaving geometry scoring parallel.
    state_storage: [49]u8
    state_count := 0
    {
        sync.mutex_lock(&markov_generation_lock)
        defer sync.mutex_unlock(&markov_generation_lock)
        model := variation_model()
        ip, loaded := markov.load_model_proc(model, {7, 7, 1})
        if loaded {
            frames := markov.run(ip, int(layout_seed), 0, false, allocator)
            if len(frames) > 0 {
                generated := frames[len(frames) - 1].state
                state_count = min(len(generated), len(state_storage))
                copy(state_storage[:state_count], generated[:state_count])
            }
            markov.frames_destroy(&frames, allocator)
            defer markov.interpreter_destroy(ip)
        }
    }
    state := state_storage[:state_count]

    for z in 0 ..= 3 {
        for x in 0 ..< GRID_WIDTH do set_cell(&plan, x, z, .Land)
    }
    build_shoreline(&plan, state, plan.shoreline_form, layout_seed)

    build_boundary(&plan, plan.boundary_form, layout_seed)

    for z in 5 ..< GRID_HEIGHT {
        for x in 12 ..= 14 do set_cell(&plan, x, z, .Channel)
    }

    // Sheltered and low-density harbor styles reserve their mooring field
    // before pier proposals consume the only water room large enough for
    // complete swing circles. Other styles can still discover a field through
    // the stochastic section grammar.
    _ = seed_mooring_field(&plan, state, layout_seed)

    // Fill the basin from stochastic section proposals. The central channel,
    // outer maneuvering band, and water lanes are immutable negative space;
    // style changes only the desired density and proposal probabilities.
    plan.target_fill_density = target_fill_density(plan.style)
    for attempt in 0 ..< 48 {
        plan.fill_density = interior_fill_density(&plan)
        section_count := 0
        for count in plan.section_form_counts do section_count += count
        if plan.fill_density >= plan.target_fill_density && plan.slip_count >= 6 && section_count >= 2 {
            break
        }

        roll := mix_seed(layout_seed ~ (u32(attempt + 1) * u32(0x9e3779b9)))
        west_side := attempt & 1 == 0
        anchor_x := 6 + int(roll % 5)
        if !west_side {
            anchor_x = 17 + int(roll % 5)
        }
        if !section_lane_open(&plan, anchor_x) do continue

        form := choose_section_form(plan.style, roll >> 8)
        inward := west_side ? 1 : -1
        // Some forms have a wider footprint. Fall back to a straight proposal
        // when their bend or head would consume the central fairway.
        if form == .Quay_Mole && ((west_side && anchor_x > 8) || (!west_side && anchor_x < 18)) {
            form = .Straight
        }
        if form == .Natural_Jetty && ((west_side && anchor_x > 8) || (!west_side && anchor_x < 18)) {
            form = .Straight
        }
        if form == .Dogleg && anchor_x != (west_side ? 8 : 18) {
            form = .Straight
        }
        if form == .Hammerhead && anchor_x != (west_side ? 8 : 18) {
            form = .Straight
        }
        if form == .Forked_Pier {
            anchor_x = west_side ? 8 : 18
            if !section_lane_open(&plan, anchor_x) do continue
        }

        trial := plan
        end_z := OUTER_SECTION_LIMIT_Z
        switch form {
        case .Straight, .Hammerhead:
            west_berths := west_side ? anchor_x >= 8 : true
            east_berths := west_side ? anchor_x <= 8 : anchor_x <= 18
            if !west_side {
                west_berths = anchor_x >= 18
            }
            add_pier(&trial, state, anchor_x, 5, end_z, 3, west_berths, east_berths, form == .Hammerhead)
        case .Dogleg:
            add_dogleg_pier(&trial, state, anchor_x, 9 + int((roll >> 20) & 1), inward)
        case .Quay_Mole:
            add_quay_mole(&trial, state, anchor_x, end_z, inward)
        case .Natural_Jetty:
            add_natural_jetty(&trial, state, anchor_x, end_z, inward, roll)
        case .Floating_Pontoon:
            pontoon_z := 8 + int((roll >> 20) % 5)
            if west_side {
                add_floating_pontoon(&trial, state, 6, 11, pontoon_z)
            } else {
                add_floating_pontoon(&trial, state, 15, 20, pontoon_z)
            }
        case .Island_Quay:
            island_z := 9 + int((roll >> 20) & 1)
            if west_side {
                add_island_quay(&trial, state, 7, 10, island_z)
            } else {
                add_island_quay(&trial, state, 16, 19, island_z)
            }
        case .Forked_Pier:
            add_forked_pier(&trial, state, anchor_x)
        case .Mooring_Field:
            field_z := 7
            field_x := west_side ? 6 : 20
            // A longitudinal pair fits the compact basin while retaining a
            // true 24 m watch-circle separation. Wider 2x2 fields are still
            // available to callers with a larger water sheet.
            add_mooring_field(&trial, state, field_x, field_z, 1, 2)
        }
        trial.fill_density = interior_fill_density(&trial)
        _, _ = measure_spacing(&trial)
        trial.structure_overlap_badness = measure_structure_overlaps(&trial)
        if trial.fill_density <= plan.fill_density do continue
        if !slips_have_clearance(&trial) do continue
        if trial.structure_overlap_badness > 0 do continue
        if !structures_have_breakwater_clearance(&trial) do continue
        plan = trial
    }
    plan.fill_density = interior_fill_density(&plan)

    plan.office = grid_position(5 + int(seed % 4), 2)
    set_cell(&plan, 5 + int(seed % 4), 2, .Building)
    shoreline_props := [4]Prop_Kind{.Lamp, .Bollard, .Crates, .Nets}
    for x := 3; x < GRID_WIDTH - 3; x += 3 {
        kind := shoreline_props[(x + int(layout_seed)) % len(shoreline_props)]
        add_prop(&plan, kind, x, 3)
        set_cell(&plan, x, 3, .Props)
    }
    if plan.style == .Fishing_Quay ||
       plan.style == .Working_Port ||
       plan.style == .Ferry_Quay ||
       plan.style == .Boat_Yard {
        for z := 6; z <= 12; z += 2 {
            kind := (z + int(layout_seed)) & 2 == 0 ? Prop_Kind.Crates : Prop_Kind.Nets
            add_prop(&plan, kind, 1, z, f32(z) * .17)
        }
    }
    build_route_from_lanes(&plan)
    plan.spacing_density, plan.spacing_badness_density = measure_spacing(&plan)
    plan.structure_overlap_badness = measure_structure_overlaps(&plan)
    plan.site_conformance_badness = measure_site_conformance(&plan, site)
    plan.fill_density_error = abs(plan.fill_density - plan.target_fill_density)
    plan.generation_quality = quality_score(&plan)
    plan.valid = validate(&plan) && plan_conforms_to_site(&plan, site)
    return plan
}

generate_candidate :: proc(seed, layout_seed: u32, candidate_index: int, allocator := context.temp_allocator) -> Plan {
    return generate_candidate_for_site(seed, layout_seed, candidate_index, nil, allocator)
}

generate_for_site_budget :: proc(
    seed: u32,
    site: ^Site,
    candidate_budget: int,
    allocator := context.temp_allocator,
) -> Plan {
    best: Plan
    best_score := f32(2)
    candidates := clamp(candidate_budget, 1, GENERATION_CANDIDATES)
    for candidate_index in 0 ..< candidates {
        layout_seed := seed ~ (u32(candidate_index) * u32(0x9e3779b9))
        candidate := generate_candidate_for_site(seed, layout_seed, candidate_index, site, allocator)
        score := candidate.generation_quality
        if candidate.valid && (!best.valid || score < best_score) {
            best = candidate
            best_score = score
        } else if !best.valid && score < best_score {
            best = candidate
            best_score = score
        }
    }
    best.candidates_evaluated = candidates
    return best
}

generate_for_site :: proc(seed: u32, site: ^Site, allocator := context.temp_allocator) -> Plan {
    return generate_for_site_budget(seed, site, GENERATION_CANDIDATES, allocator)
}

generate :: proc(seed: u32, allocator := context.temp_allocator) -> Plan {
    return generate_for_site(seed, nil, allocator)
}

validate :: proc(plan: ^Plan) -> bool {
    if plan == nil || plan.segment_count < 5 || plan.slip_count < 6 || plan.route.count < 4 do return false
    if plan.spacing_badness_density > .35 do return false
    if !slips_have_clearance(plan) do return false
    if !slips_clear_structures(plan) do return false
    if !structures_have_breakwater_clearance(plan) do return false
    if !route_has_clearance(plan) do return false
    if plan.fill_density < plan.target_fill_density * .75 do return false
    if plan.fill_density_error > .10 do return false
    for z in 5 ..< GRID_HEIGHT {
        for x in 12 ..= 14 {
            value := cell(plan, x, z)
            if value != .Channel && value != .Main_Pier do return false
        }
    }
    for segment in plan.segments[:plan.segment_count] {
        if segment.width <= 0 do return false
    }
    for slip in plan.slips[:plan.slip_count] {
        spec := boats.specifications(slip.class)
        if spec.length > CELL_METERS * 2.25 || spec.beam > CELL_METERS do return false
    }
    return true
}
