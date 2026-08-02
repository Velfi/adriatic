package main

import architecture "../packages/architecture"
import buildings "../packages/buildings"
import fountains "../packages/fountains"
import roads "../packages/roads"
import terrain "../packages/terrain"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"

Settlement_Region :: enum {
    Adriatic,
    Aegean,
}

Settlement_Brush_Shape :: enum u8 {
    Square,
    Rectangle,
    Circle,
    Macaroni,
}

Settlement_Brush_Preset :: enum u8 {
    Small,
    Medium,
    Large,
}

SETTLEMENT_BRUSH_PIECE_CAPACITY :: 64

Settlement_Brush_Piece :: struct {
    shape:        Settlement_Brush_Shape,
    preset:       Settlement_Brush_Preset,
    center:       [2]f32,
    rotation:     f32,
    density:      f32,
    hardness:     f32,
    seed:         u32,
    component_id: u32,
    erased:       bool,
}

Settlement_Tissue :: enum u8 {
    Venetian_Mercantile,
    Dalmatian_Planned,
    Hillside_Accretion,
    Harbor,
    Later_Extension,
    Fortified_Precinct,
    Cycladic_Accretion,
    Contour_Terrace,
    Church_Cluster,
}

Settlement_Route_Class :: enum u8 {
    Civic_Spine,
    Connector,
    Street,
    Lane,
    Alley,
    Stair,
    Waterfront,
    Ridge,
}

Settlement_Access_Surface :: enum u8 {
    Packed_Earth,
    Gravel,
    Stone,
}

Settlement_Site_Kind :: enum u8 {
    Ordinary,
    Landmark,
    Park,
    Ruin,
    Rejected,
}

Village_Reason :: enum u8 {
    Route_Stop,
    Agricultural_Terrace,
    Harbor_Fishery,
    Upland_Pastoral,
}

Settlement_Growth_Event_Kind :: enum u8 {
    Backbone,
    Exploration,
    Densification,
}

Settlement_Building_Purpose :: enum u8 {
    Dwelling,
    Farmstead,
    Barn_Granary,
    Workshop,
    Inn_Shop,
    Mill,
    Fishery,
    Storehouse,
}

Settlement_Landmark_Kind :: enum u8 {
    Campanile,
    Palace_Loggia,
    Church,
    Monastery,
    Fortress_Gate,
    Harbor_Office,
    Market_Hall,
    Cycladic_Bell,
    Lighthouse,
}

settlement_building_region :: proc(region: Settlement_Region) -> buildings.Region {
    return region == .Aegean ? .Aegean : .Adriatic
}

settlement_building_purpose :: proc(purpose: Settlement_Building_Purpose) -> buildings.Purpose {
    switch purpose {
    case .Dwelling:
        return .Dwelling
    case .Farmstead:
        return .Farmstead
    case .Barn_Granary:
        return .Barn_Granary
    case .Workshop:
        return .Workshop
    case .Inn_Shop:
        return .Inn_Shop
    case .Mill:
        return .Mill
    case .Fishery:
        return .Fishery
    case .Storehouse:
        return .Storehouse
    }
    return .Dwelling
}

settlement_building_landmark :: proc(kind: Settlement_Landmark_Kind) -> buildings.Landmark_Kind {
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
    case .Lighthouse:
        return .Lighthouse
    }
    return .None
}

settlement_architecture_tissue :: proc(tissue: Settlement_Tissue) -> architecture.Context_Tissue {
    switch tissue {
    case .Venetian_Mercantile:
        return .Mercantile
    case .Dalmatian_Planned:
        return .Planned
    case .Hillside_Accretion:
        return .Hillside
    case .Harbor:
        return .Harbor
    case .Later_Extension:
        return .Extension
    case .Fortified_Precinct:
        return .Fortified
    case .Cycladic_Accretion:
        return .Hillside
    case .Contour_Terrace:
        return .Agricultural
    case .Church_Cluster:
        return .Religious
    }
    return .Unspecified
}

settlement_architecture_route :: proc(class: Settlement_Route_Class) -> architecture.Context_Route {
    switch class {
    case .Civic_Spine:
        return .Civic
    case .Connector, .Street:
        return .Street
    case .Lane, .Stair:
        return .Lane
    case .Alley:
        return .Alley
    case .Waterfront:
        return .Waterfront
    case .Ridge:
        return .Ridge
    }
    return .Unspecified
}

Settlement_Terrain_Edit_Kind :: enum u8 {
    Road_Corridor,
    Building_Pad,
    Plaza,
    Neighborhood_Terrace,
    Retaining_Edge,
}

Settlement_Request :: struct {
    region:  Settlement_Region,
    scale:   Settlement_Scale,
    seed:    u32,
    center:  [2]f32,
    radius:  f32,
    density: f32,
}

Settlement_Program_Count :: struct {
    target:  int,
    minimum: int,
    placed:  int,
    reduced: int,
}

Settlement_Program :: struct {
    ordinary:             Settlement_Program_Count,
    purposes:             [8]Settlement_Program_Count,
    landmarks:            Settlement_Program_Count,
    plazas:               Settlement_Program_Count,
    parks:                Settlement_Program_Count,
    vegetation:           Settlement_Program_Count,
    residents:            Settlement_Program_Count,
    workers:              Settlement_Program_Count,
    developable_area:     f32,
    target_coverage:      f32,
    canonical_footprint:  f32,
    infeasible_essential: bool,
}

Settlement_Activity_Kind :: enum u8 {
    Home,
    Work,
    Plaza,
    Park,
    Street,
}

Settlement_Activity_Point :: struct {
    position:   [2]f32,
    kind:       Settlement_Activity_Kind,
    site_index: int,
}

Settlement_Inhabitant :: struct {
    home_activity: int,
    work_activity: int,
    seed:          u32,
    worker:        bool,
}

SETTLEMENT_ACTIVITY_CAPACITY :: 512
SETTLEMENT_INHABITANT_CAPACITY :: 256

SETTLEMENT_NEIGHBORHOOD_CAPACITY :: 96
SETTLEMENT_MACRO_CELL_CAPACITY :: 192
SETTLEMENT_GROWTH_EVENT_CAPACITY :: 96
// Drivable routes are bounded independently by roads.MAX_NODES/MAX_EDGES.
// This plan also retains one compact chain for each pedestrian-network branch,
// so dense cities need headroom proportional to the site capacity.
SETTLEMENT_PLANNED_ROUTE_CAPACITY :: 320
SETTLEMENT_BLOCK_CAPACITY :: 128
SETTLEMENT_SITE_CAPACITY :: 256
SETTLEMENT_GARDEN_CAPACITY :: 64
SETTLEMENT_TERRAIN_EDIT_CAPACITY :: 192
SETTLEMENT_ROUTE_CLASS_COUNT :: 8
SETTLEMENT_LANDMARK_SEED_MASK :: u32(0xffff0000)
SETTLEMENT_LANDMARK_SEED_TAG :: u32(0xa71d0000)

Settlement_Neighborhood :: struct {
    center:      [2]f32,
    radius:      f32,
    density:     f32,
    age:         f32,
    suitability: f32,
    tissue:      Settlement_Tissue,
}

Settlement_Planned_Route :: struct {
    geometry:      Settlement_Route,
    class:         Settlement_Route_Class,
    width:         f32,
    shoulder:      f32,
    pavement:      roads.Pavement,
    required:      bool,
    drivable:      bool,
    average_grade: f32,
    maximum_grade: f32,
}

Settlement_Growth_Event :: struct {
    kind:                Settlement_Growth_Event_Kind,
    age:                 f32,
    order:               int,
    target_neighborhood: int,
    route_index:         int,
    frontage_start:      [2]f32,
    frontage_finish:     [2]f32,
}

Settlement_Block :: struct {
    center:       [2]f32,
    corners:      [8][2]f32,
    corner_count: int,
    short_side:   f32,
    long_side:    f32,
    area:         f32,
    irregularity: f32,
    tissue:       Settlement_Tissue,
}

Settlement_Site :: struct {
    structure:           terrain.Structure,
    parcel:              architecture.City_Parcel,
    kind:                Settlement_Site_Kind,
    tissue:              Settlement_Tissue,
    density:             f32,
    attached:            bool,
    accepted:            bool,
    landmark_kind:       Settlement_Landmark_Kind,
    purpose:             Settlement_Building_Purpose,
    fountain_style:      fountains.Style,
    fountain_radius:     f32,
    fountain_jet_count:  int,
    fountain_jet_height: f32,
    fountain_enabled:    bool,
}

Settlement_Garden_Style :: enum u8 {
    Courtyard,
    Kitchen,
    Wild,
    Park,
}

Settlement_Garden_Plot :: struct {
    center:     [2]f32,
    width:      f32,
    depth:      f32,
    rotation:   f32,
    seed:       u32,
    site_index: int,
    style:      Settlement_Garden_Style,
}

Settlement_Terrain_Edit :: struct {
    kind:          Settlement_Terrain_Edit_Kind,
    center:        [2]f32,
    half_extent:   [2]f32,
    target_height: f32,
    feather:       f32,
    cut_volume:    f32,
    fill_volume:   f32,
}

Settlement_Scalar_Stats :: struct {
    count:  int,
    min:    f32,
    p10:    f32,
    median: f32,
    mean:   f32,
    p90:    f32,
    max:    f32,
}

Settlement_Metrics :: struct {
    route_length:               Settlement_Scalar_Stats,
    route_width:                Settlement_Scalar_Stats,
    route_grade:                Settlement_Scalar_Stats,
    route_length_by_class:      [SETTLEMENT_ROUTE_CLASS_COUNT]Settlement_Scalar_Stats,
    route_width_by_class:       [SETTLEMENT_ROUTE_CLASS_COUNT]Settlement_Scalar_Stats,
    intersection_spacing:       Settlement_Scalar_Stats,
    dead_end_frontage:          Settlement_Scalar_Stats,
    block_short_side:           Settlement_Scalar_Stats,
    block_long_side:            Settlement_Scalar_Stats,
    block_area:                 Settlement_Scalar_Stats,
    block_aspect:               Settlement_Scalar_Stats,
    block_irregularity:         Settlement_Scalar_Stats,
    parcel_frontage:            Settlement_Scalar_Stats,
    parcel_depth:               Settlement_Scalar_Stats,
    building_height:            Settlement_Scalar_Stats,
    building_base_elevation:    Settlement_Scalar_Stats,
    building_footprint:         Settlement_Scalar_Stats,
    building_floors:            Settlement_Scalar_Stats,
    network_density:            f32,
    road_badness:               f32,
    attached_share:             f32,
    density_band_count:         [3]int,
    wide_route_share:           f32,
    minor_route_share:          f32,
    fabric_aspect_ratio:        f32,
    fabric_quadrants:           int,
    drivable_dead_end_share:    f32,
    degree_four_plus_count:     int,
    paved_length_per_building:  f32,
    public_paving_per_building: f32,
    access_repair_share:        f32,
    public_route_count:         int,
    public_component_count:     int,
    public_cycle_count:         int,
    public_max_degree:          int,
    landmark_count:             int,
    park_count:                 int,
    rejected_count:             int,
    cut_volume:                 f32,
    fill_volume:                f32,
}

Settlement_Acceptance_Failure :: enum {
    None,
    Capacity,
    Wide_Route_Share,
    Required_Route,
    Disconnected_Anchors,
    Road_Topology,
    Building_Access,
    Route_Grade,
    Submerged_Route,
    Submerged_Site,
    Missing_Buildings,
    Insufficient_Buildings,
    Missing_Village_Program,
    Missing_Blocks,
    Fabric_Form,
    Height_Band,
    Height_Outlier,
    Landmark_Count,
    Park_Count,
    Undersized_Building,
}

Settlement_Plan :: struct {
    request:                      Settlement_Request,
    brush_pieces:                 [SETTLEMENT_BRUSH_PIECE_CAPACITY]Settlement_Brush_Piece,
    brush_piece_count:            int,
    next_brush_component_id:      u32,
    program:                      Settlement_Program,
    activity_points:              [SETTLEMENT_ACTIVITY_CAPACITY]Settlement_Activity_Point,
    activity_point_count:         int,
    inhabitants:                  [SETTLEMENT_INHABITANT_CAPACITY]Settlement_Inhabitant,
    inhabitant_count:             int,
    village_reason:               Village_Reason,
    neighborhoods:                [SETTLEMENT_NEIGHBORHOOD_CAPACITY]Settlement_Neighborhood,
    neighborhood_count:           int,
    macro_cells:                  [SETTLEMENT_MACRO_CELL_CAPACITY]Settlement_Neighborhood,
    macro_cell_count:             int,
    routes:                       [SETTLEMENT_PLANNED_ROUTE_CAPACITY]Settlement_Planned_Route,
    route_piece_ids:              [SETTLEMENT_PLANNED_ROUTE_CAPACITY]u32,
    route_count:                  int,
    access_routes_truncated:      bool,
    access_required_count:        int,
    access_connected_count:       int,
    access_max_degree:            int,
    access_shallow_junctions:     int,
    access_hairpin_bends:         int,
    access_crossings:             int,
    access_unsplit_junctions:     int,
    access_bad_door_approaches:   int,
    access_bad_road_approaches:   int,
    access_stair_routes:          int,
    access_excessive_grades:      int,
    access_shared_segments:       int,
    access_widened_segments:      int,
    access_max_shared_width_step: f32,
    access_orphan_endpoints:      int,
    access_repair_count:          int,
    road_badness_sum:             f32,
    road_badness_count:           int,
    growth_events:                [SETTLEMENT_GROWTH_EVENT_CAPACITY]Settlement_Growth_Event,
    growth_event_count:           int,
    blocks:                       [SETTLEMENT_BLOCK_CAPACITY]Settlement_Block,
    block_count:                  int,
    sites:                        [SETTLEMENT_SITE_CAPACITY]Settlement_Site,
    site_piece_ids:               [SETTLEMENT_SITE_CAPACITY]u32,
    site_count:                   int,
    gardens:                      [SETTLEMENT_GARDEN_CAPACITY]Settlement_Garden_Plot,
    garden_count:                 int,
    patios:                       [SETTLEMENT_PATIO_CAPACITY]Settlement_Patio,
    patio_count:                  int,
    rejected_sites:               [32]Settlement_Site,
    rejected_site_count:          int,
    decorative_foliage:           [32]terrain.Structure,
    decorative_foliage_count:     int,
    terrain_edits:                [SETTLEMENT_TERRAIN_EDIT_CAPACITY]Settlement_Terrain_Edit,
    terrain_edit_count:           int,
    ordinary_purposes:            [SETTLEMENT_SITE_CAPACITY]Settlement_Building_Purpose,
    ordinary_purpose_count:       int,
    metrics:                      Settlement_Metrics,
    acceptance_failure:           Settlement_Acceptance_Failure,
    valid:                        bool,
}

Settlement_Rng :: struct {
    state: u64,
}

settlement_rng_new :: proc(seed: u32) -> Settlement_Rng {
    return {state = u64(seed) + 0x9e3779b97f4a7c15}
}

settlement_rng_u32 :: proc(rng: ^Settlement_Rng) -> u32 {
    rng.state ~= rng.state >> 12
    rng.state ~= rng.state << 25
    rng.state ~= rng.state >> 27
    return u32((rng.state * 0x2545f4914f6cdd1d) >> 32)
}

settlement_rng_unit :: proc(rng: ^Settlement_Rng) -> f32 {
    return f32(settlement_rng_u32(rng) & 0x00ffffff) / f32(0x01000000)
}

settlement_landmark_seed :: proc(region: Settlement_Region, ordinal: int, variation: u32) -> u32 {
    return SETTLEMENT_LANDMARK_SEED_TAG | (u32(region) << 8) | ((variation & 15) << 4) | (u32(ordinal) & 15)
}

settlement_structure_is_landmark :: proc(structure: terrain.Structure) -> bool {
    return (structure.seed & SETTLEMENT_LANDMARK_SEED_MASK) == SETTLEMENT_LANDMARK_SEED_TAG
}

settlement_sample_triangular :: proc(rng: ^Settlement_Rng, low, mode, high: f32) -> f32 {
    if high <= low do return low
    u := settlement_rng_unit(rng)
    split := clamp((mode - low) / (high - low), 0, 1)
    if u < split {
        return low + f32(math.sqrt(f64(u * (high - low) * (mode - low))))
    }
    return high - f32(math.sqrt(f64((1 - u) * (high - low) * (high - mode))))
}

settlement_sample_lognormal :: proc(rng: ^Settlement_Rng, median, sigma, low, high: f32) -> f32 {
    u1 := max(settlement_rng_unit(rng), f32(.000001))
    u2 := settlement_rng_unit(rng)
    gaussian := f32(math.sqrt(f64(-2 * math.ln(u1)))) * f32(math.cos(f64(2 * math.PI * u2)))
    return clamp(median * f32(math.exp(f64(gaussian * sigma))), low, high)
}

settlement_tissue_pick :: proc(region: Settlement_Region, roll: f32) -> Settlement_Tissue {
    if region == .Adriatic {
        if roll < .30 do return .Venetian_Mercantile
        if roll < .52 do return .Dalmatian_Planned
        if roll < .70 do return .Hillside_Accretion
        if roll < .85 do return .Harbor
        if roll < .95 do return .Later_Extension
        return .Fortified_Precinct
    }
    if roll < .40 do return .Cycladic_Accretion
    if roll < .62 do return .Contour_Terrace
    if roll < .77 do return .Church_Cluster
    if roll < .90 do return .Harbor
    return .Later_Extension
}

settlement_height_band :: proc(region: Settlement_Region, scale: Settlement_Scale) -> (minimum, maximum: f32) {
    if region == .Aegean do return 3.5, 10
    switch scale {
    case .City:
        return 7, 22
    case .Town:
        return 4.5, 12
    case .Village:
        return 4, 11
    }
    return 4, 11
}

settlement_attachment_probability :: proc(age: f32, scale: Settlement_Scale = .City) -> f32 {
    if scale == .Town {
        return .96 + (.68 - .96) * clamp(age, 0, 1)
    }
    return .82 + (.32 - .82) * clamp(age, 0, 1)
}

settlement_building_separation :: proc(
    region: Settlement_Region,
    scale: Settlement_Scale,
    age: f32,
    attached: bool,
) -> f32 {
    if scale == .Town {
        // Riviera town cores are read as continuous street walls. Leave only
        // a drainage/light slot between attached houses, then loosen the
        // fabric toward the younger edge. Detached villas still keep a real
        // side yard.
        base := attached ? (region == .Aegean ? f32(.24) : f32(.38)) : f32(2.6)
        return base + clamp(age, 0, 1) * (attached ? f32(.82) : f32(2.2))
    }
    scale_spacing := scale == .Village ? f32(1.2) : f32(0)
    base_spacing := attached ? (region == .Aegean ? f32(1.8) : f32(2.4)) : f32(4.5)
    return base_spacing + scale_spacing + clamp(age, 0, 1) * (attached ? f32(1.8) : f32(3))
}

settlement_density_with_age :: proc(raw_density, age: f32, profile: Settlement_Profile) -> f32 {
    radial_density := profile.density_ceiling * (1 - clamp(age, 0, 1) * .64)
    return clamp(raw_density * .62 + radial_density * .38, profile.density_floor * .72, profile.density_ceiling)
}

settlement_route_width_sample :: proc(rng: ^Settlement_Rng, class: Settlement_Route_Class) -> f32 {
    switch class {
    case .Civic_Spine, .Waterfront:
        return settlement_sample_triangular(rng, 5, 7, 11)
    case .Connector, .Ridge:
        return settlement_sample_triangular(rng, 4, 5.5, 8)
    case .Street:
        return settlement_sample_lognormal(rng, 3.5, .22, 2.5, 6)
    case .Lane:
        return settlement_sample_lognormal(rng, 2.2, .25, 1.3, 3.8)
    case .Alley, .Stair:
        return settlement_sample_lognormal(rng, 1.4, .24, .8, 2.5)
    }
    return 3
}

settlement_route_width_sample_for_scale :: proc(
    rng: ^Settlement_Rng,
    class: Settlement_Route_Class,
    scale: Settlement_Scale,
) -> f32 {
    if scale == .Town {
        // A Riviera town's hierarchy is expressed by paving, frontage, and
        // destination—not by city-width carriageways. Keep hillside
        // connectors intimate and the civic room narrow enough for adjacent
        // façades to enclose it.
        #partial switch class {
        case .Civic_Spine, .Waterfront:
            return settlement_sample_triangular(rng, 4.4, 5.3, 6.6)
        case .Connector:
            return settlement_sample_triangular(rng, 3.2, 4.2, 5.5)
        case .Street:
            // Ordinary town streets are paved shared spaces, not miniature
            // city carriageways. Narrowing this band also pulls the derived
            // frontage setback inward, so attached terraces enclose the
            // street instead of floating behind broad grass verges.
            return settlement_sample_triangular(rng, 2.7, 3.4, 4.2)
        case .Lane:
            return settlement_sample_triangular(rng, 1.7, 2.2, 2.9)
        case .Ridge:
            return settlement_sample_triangular(rng, 2.8, 3.6, 4.8)
        }
    }
    return settlement_route_width_sample(rng, class)
}

// Route hierarchy is also a useful stable proxy for long-term wear. It keeps
// civic streets maintained while allowing quiet lanes and alleys to weather
// back into the landscape without requiring a runtime traffic simulation.
settlement_route_use_intensity :: proc(class: Settlement_Route_Class) -> f32 {
    switch class {
    case .Civic_Spine:
        return .96
    case .Waterfront:
        return .82
    case .Connector:
        return .78
    case .Street:
        return .64
    case .Lane:
        return .38
    case .Ridge:
        return .34
    case .Alley:
        return .16
    case .Stair:
        return .08
    }
    return 1
}

settlement_route_length :: proc(route: Settlement_Route) -> f32 {
    total: f32
    for index in 0 ..< route.count - 1 {
        total += linalg.length(route.points[index + 1] - route.points[index])
    }
    return total
}

settlement_stats :: proc(values: []f32) -> Settlement_Scalar_Stats {
    result: Settlement_Scalar_Stats
    if len(values) == 0 do return result
    sorted := make([]f32, len(values), context.temp_allocator)
    copy(sorted, values)
    slice.sort(sorted)
    sum: f32
    for value in sorted do sum += value
    result = {
        count  = len(sorted),
        min    = sorted[0],
        p10    = sorted[(len(sorted) - 1) * 10 / 100],
        median = sorted[(len(sorted) - 1) / 2],
        mean   = sum / f32(len(sorted)),
        p90    = sorted[(len(sorted) - 1) * 90 / 100],
        max    = sorted[len(sorted) - 1],
    }
    return result
}

settlement_growth_topology :: proc(plan: ^Settlement_Plan) -> Settlement_Route_Topology {
    result: Settlement_Route_Topology
    if plan == nil do return result
    for event in plan.growth_events[:plan.growth_event_count] {
        if event.route_index < 0 || event.route_index >= plan.route_count do continue
        geometry := plan.routes[event.route_index].geometry
        indices: [SETTLEMENT_ROUTE_CAPACITY]int
        for point, point_index in geometry.points[:geometry.count] {
            node_index := -1
            for existing, existing_index in result.nodes[:result.node_count] {
                if settlement_route_point_near(existing, point, .0001) {
                    node_index = existing_index
                    break
                }
            }
            if node_index < 0 {
                if result.node_count >= len(result.nodes) do return result
                node_index = result.node_count
                result.nodes[result.node_count] = point
                result.node_count += 1
            }
            indices[point_index] = node_index
        }
        for point_index in 0 ..< geometry.count - 1 {
            from, to := indices[point_index], indices[point_index + 1]
            if from == to do continue
            duplicate := false
            for edge in result.edges[:result.edge_count] {
                if (edge[0] == from && edge[1] == to) || (edge[0] == to && edge[1] == from) {
                    duplicate = true
                    break
                }
            }
            if duplicate || result.edge_count >= len(result.edges) do continue
            result.edges[result.edge_count] = {from, to}
            result.edge_count += 1
        }
    }
    return result
}

settlement_point_structure_footprint_distance :: proc(point: [2]f32, structure: terrain.Structure) -> f32 {
    sine, cosine := math.sin(structure.rotation), math.cos(structure.rotation)
    delta := point - [2]f32{structure.center_x, structure.center_z}
    local := [2]f32{delta[0] * cosine + delta[1] * sine, -delta[0] * sine + delta[1] * cosine}
    outside := [2]f32 {
        max(math.abs(local[0]) - structure.width * .5, f32(0)),
        max(math.abs(local[1]) - structure.depth * .5, f32(0)),
    }
    return linalg.length(outside)
}

settlement_plan_measure :: proc(plan: ^Settlement_Plan) {
    if plan == nil do return
    plan.metrics = {}
    if plan.road_badness_count > 0 {
        plan.metrics.road_badness = plan.road_badness_sum / f32(plan.road_badness_count)
    }
    route_lengths := make([dynamic]f32, context.temp_allocator)
    route_widths := make([dynamic]f32, context.temp_allocator)
    route_grades := make([dynamic]f32, context.temp_allocator)
    route_lengths_by_class: [SETTLEMENT_ROUTE_CLASS_COUNT][dynamic]f32
    route_widths_by_class: [SETTLEMENT_ROUTE_CLASS_COUNT][dynamic]f32
    for class_index in 0 ..< SETTLEMENT_ROUTE_CLASS_COUNT {
        route_lengths_by_class[class_index] = make([dynamic]f32, context.temp_allocator)
        route_widths_by_class[class_index] = make([dynamic]f32, context.temp_allocator)
    }
    intersection_spacings := make([dynamic]f32, context.temp_allocator)
    dead_end_frontages := make([dynamic]f32, context.temp_allocator)
    block_short := make([dynamic]f32, context.temp_allocator)
    block_long := make([dynamic]f32, context.temp_allocator)
    block_areas := make([dynamic]f32, context.temp_allocator)
    block_aspects := make([dynamic]f32, context.temp_allocator)
    block_irregularities := make([dynamic]f32, context.temp_allocator)
    frontages := make([dynamic]f32, context.temp_allocator)
    depths := make([dynamic]f32, context.temp_allocator)
    heights := make([dynamic]f32, context.temp_allocator)
    base_elevations := make([dynamic]f32, context.temp_allocator)
    footprints := make([dynamic]f32, context.temp_allocator)
    floors := make([dynamic]f32, context.temp_allocator)
    total_route_length, wide_route_length, minor_route_length: f32
    fabric_minimum_x, fabric_minimum_z := f32(1e30), f32(1e30)
    fabric_maximum_x, fabric_maximum_z := f32(-1e30), f32(-1e30)
    fabric_center_x, fabric_center_z: f32
    fabric_count := 0
    for route in plan.routes[:plan.route_count] {
        length := settlement_route_length(route.geometry)
        append(&route_lengths, length)
        append(&route_widths, route.width)
        append(&route_grades, route.maximum_grade)
        append(&route_lengths_by_class[int(route.class)], length)
        append(&route_widths_by_class[int(route.class)], route.width)
        total_route_length += length
        if route.class == .Civic_Spine || route.class == .Waterfront do wide_route_length += length
        if route.class == .Lane || route.class == .Alley || route.class == .Stair do minor_route_length += length
    }
    for block in plan.blocks[:plan.block_count] {
        append(&block_short, block.short_side)
        append(&block_long, block.long_side)
        append(&block_areas, block.area)
        append(&block_aspects, block.long_side / max(block.short_side, f32(.01)))
        append(&block_irregularities, block.irregularity)
    }
    attached_count := 0
    for site in plan.sites[:plan.site_count] {
        if !site.accepted do continue
        if site.kind == .Landmark {
            plan.metrics.landmark_count += 1
        } else if site.kind == .Park {
            plan.metrics.park_count += 1
        } else if site.kind == .Ordinary {
            append(&frontages, site.parcel.frontage_width)
            append(&depths, site.parcel.depth)
            append(&heights, site.structure.height)
            append(&base_elevations, site.structure.base_y)
            append(&footprints, site.structure.width * site.structure.depth)
            append(&floors, max(f32(math.round(f64(site.structure.height / 3))), f32(1)))
            if site.attached do attached_count += 1
            density_band := site.density < .34 ? 0 : (site.density < .67 ? 1 : 2)
            plan.metrics.density_band_count[density_band] += 1
            fabric_minimum_x = min(fabric_minimum_x, site.structure.center_x)
            fabric_minimum_z = min(fabric_minimum_z, site.structure.center_z)
            fabric_maximum_x = max(fabric_maximum_x, site.structure.center_x)
            fabric_maximum_z = max(fabric_maximum_z, site.structure.center_z)
            fabric_center_x += site.structure.center_x
            fabric_center_z += site.structure.center_z
            fabric_count += 1
        }
    }
    plan.metrics.rejected_count = plan.rejected_site_count
    for edit in plan.terrain_edits[:plan.terrain_edit_count] {
        plan.metrics.cut_volume += edit.cut_volume
        plan.metrics.fill_volume += edit.fill_volume
    }
    plan.metrics.route_length = settlement_stats(route_lengths[:])
    plan.metrics.route_width = settlement_stats(route_widths[:])
    plan.metrics.route_grade = settlement_stats(route_grades[:])
    for class_index in 0 ..< SETTLEMENT_ROUTE_CLASS_COUNT {
        plan.metrics.route_length_by_class[class_index] = settlement_stats(route_lengths_by_class[class_index][:])
        plan.metrics.route_width_by_class[class_index] = settlement_stats(route_widths_by_class[class_index][:])
    }
    topology := settlement_plan_route_topology(plan)
    intersection_nodes: [roads.MAX_NODES]int
    intersection_count := 0
    drivable_dead_ends := 0
    for node_index in 0 ..< topology.node_count {
        degree := 0
        for edge in topology.edges[:topology.edge_count] {
            if edge[0] == node_index || edge[1] == node_index do degree += 1
        }
        if degree >= 3 {
            intersection_nodes[intersection_count] = node_index
            intersection_count += 1
            if degree >= 4 do plan.metrics.degree_four_plus_count += 1
        } else if degree == 1 {
            drivable_dead_ends += 1
            point := topology.nodes[node_index]
            nearest_frontage := f32(1e30)
            for site in plan.sites[:plan.site_count] {
                if !site.accepted || (site.kind != .Ordinary && site.kind != .Landmark) do continue
                nearest_frontage = min(
                    nearest_frontage,
                    settlement_point_structure_footprint_distance(point, site.structure),
                )
            }
            if nearest_frontage < f32(1e29) do append(&dead_end_frontages, nearest_frontage)
        }
    }
    for intersection_index in 0 ..< intersection_count {
        point := topology.nodes[intersection_nodes[intersection_index]]
        nearest := f32(1e30)
        for other_index in 0 ..< intersection_count {
            if other_index == intersection_index do continue
            other := topology.nodes[intersection_nodes[other_index]]
            nearest = min(nearest, linalg.length(other - point))
        }
        if nearest < f32(1e29) do append(&intersection_spacings, nearest)
    }
    plan.metrics.intersection_spacing = settlement_stats(intersection_spacings[:])
    plan.metrics.dead_end_frontage = settlement_stats(dead_end_frontages[:])
    if plan.request.scale == .Village && plan.growth_event_count > 0 {
        growth := settlement_growth_topology(plan)
        plan.metrics.public_route_count = plan.growth_event_count
        components := 0
        visited: [roads.MAX_NODES]bool
        queue: [roads.MAX_NODES]int
        for root in 0 ..< growth.node_count {
            if visited[root] do continue
            components += 1
            queue[0], visited[root] = root, true
            queue_start, queue_end := 0, 1
            for queue_start < queue_end {
                current := queue[queue_start]
                queue_start += 1
                degree := 0
                for edge in growth.edges[:growth.edge_count] {
                    neighbor := -1
                    if edge[0] == current {
                        neighbor = edge[1]
                    } else if edge[1] == current {
                        neighbor = edge[0]
                    }
                    if neighbor < 0 do continue
                    degree += 1
                    if !visited[neighbor] {
                        visited[neighbor] = true
                        queue[queue_end] = neighbor
                        queue_end += 1
                    }
                }
                plan.metrics.public_max_degree = max(plan.metrics.public_max_degree, degree)
                if degree >= 4 do plan.metrics.degree_four_plus_count += 1
            }
        }
        plan.metrics.public_component_count = components
        plan.metrics.public_cycle_count = max(growth.edge_count - growth.node_count + components, 0)
    }
    if topology.node_count > 0 {
        plan.metrics.drivable_dead_end_share = f32(drivable_dead_ends) / f32(topology.node_count)
    }
    plan.metrics.block_short_side = settlement_stats(block_short[:])
    plan.metrics.block_long_side = settlement_stats(block_long[:])
    plan.metrics.block_area = settlement_stats(block_areas[:])
    plan.metrics.block_aspect = settlement_stats(block_aspects[:])
    plan.metrics.block_irregularity = settlement_stats(block_irregularities[:])
    plan.metrics.parcel_frontage = settlement_stats(frontages[:])
    plan.metrics.parcel_depth = settlement_stats(depths[:])
    plan.metrics.building_height = settlement_stats(heights[:])
    plan.metrics.building_base_elevation = settlement_stats(base_elevations[:])
    plan.metrics.building_footprint = settlement_stats(footprints[:])
    plan.metrics.building_floors = settlement_stats(floors[:])
    if total_route_length > 0 {
        plan.metrics.wide_route_share = wide_route_length / total_route_length
        plan.metrics.minor_route_share = minor_route_length / total_route_length
    }
    if plan.request.radius > 0 {
        plan.metrics.network_density =
            total_route_length / (math.PI * plan.request.radius * plan.request.radius) * 1000
    }
    if fabric_count > 0 do plan.metrics.attached_share = f32(attached_count) / f32(fabric_count)
    if fabric_count > 0 {
        plan.metrics.paved_length_per_building = total_route_length / f32(fabric_count)
        public_length: f32
        for event in plan.growth_events[:plan.growth_event_count] {
            if event.route_index >= 0 && event.route_index < plan.route_count {
                public_length += settlement_route_length(plan.routes[event.route_index].geometry)
            }
        }
        plan.metrics.public_paving_per_building = public_length / f32(fabric_count)
        plan.metrics.access_repair_share = f32(plan.access_repair_count) / f32(fabric_count)
    }
    if fabric_count > 0 {
        fabric_center_x /= f32(fabric_count)
        fabric_center_z /= f32(fabric_count)
        fabric_width := max(fabric_maximum_x - fabric_minimum_x, f32(.01))
        fabric_depth := max(fabric_maximum_z - fabric_minimum_z, f32(.01))
        plan.metrics.fabric_aspect_ratio = max(fabric_width, fabric_depth) / min(fabric_width, fabric_depth)
        occupied: [4]bool
        for site in plan.sites[:plan.site_count] {
            if !site.accepted || site.kind != .Ordinary do continue
            quadrant := 0
            if site.structure.center_x >= fabric_center_x do quadrant += 1
            if site.structure.center_z >= fabric_center_z do quadrant += 2
            occupied[quadrant] = true
        }
        for present in occupied {
            if present do plan.metrics.fabric_quadrants += 1
        }
    }
}

settlement_plan_acceptance_failure :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
) -> Settlement_Acceptance_Failure {
    if plan == nil || project == nil do return .Capacity
    if project.road_graph.node_count > roads.MAX_NODES || project.road_graph.edge_count > roads.MAX_EDGES {
        return .Capacity
    }
    if plan.access_routes_truncated do return .Capacity
    wide_route_limit := f32(.1201)
    if plan.request.scale == .Village && plan.village_reason == .Harbor_Fishery {
        // A quay is a linear public working surface, not evidence that the
        // village street hierarchy is over-wide. Harbor villages may devote
        // more of their measured network to waterfront frontage while still
        // bounding genuinely excessive paving.
        wide_route_limit = .32
    }
    if plan.metrics.wide_route_share > wide_route_limit do return .Wide_Route_Share
    if !settlement_plan_required_routes_connected(plan) do return .Disconnected_Anchors
    if plan.request.scale == .Village &&
       (plan.metrics.public_component_count != 1 ||
               plan.metrics.public_cycle_count > 0 ||
               plan.metrics.public_max_degree > 3 ||
               plan.metrics.public_route_count > 4 ||
               plan.metrics.public_paving_per_building > 18) {
        return .Road_Topology
    }
    if plan.access_connected_count < plan.access_required_count do return .Building_Access
    for route in plan.routes[:plan.route_count] {
        if route.required && route.geometry.count < 2 do return .Required_Route
        if route.maximum_grade > settlement_route_grade_limit(route.class) + .001 do return .Route_Grade
        if settlement_route_crosses_sea(project, route.geometry) do return .Submerged_Route
    }
    ordinary_count, ordinary_above_22, in_target_band := 0, 0, 0
    village_purposes: [8]int
    minimum_height, maximum_height := settlement_height_band(plan.request.region, plan.request.scale)
    for site in plan.sites[:plan.site_count] {
        if !site.accepted do continue
        if site.kind == .Ordinary &&
           !settlement_structure_footprint_on_land(
                   project,
                   site.structure.center_x,
                   site.structure.center_z,
                   site.structure.width,
                   site.structure.depth,
                   site.structure.rotation,
               ) {
            return .Submerged_Site
        }
        if site.kind != .Ordinary do continue
        if !settlement_ordinary_building_dimensions_valid(
            site.structure.width,
            site.structure.depth,
        ) {
            return .Undersized_Building
        }
        ordinary_count += 1
        village_purposes[int(site.purpose)] += 1
        if site.structure.height > 22 do ordinary_above_22 += 1
        if site.structure.height >= minimum_height && site.structure.height <= maximum_height {
            in_target_band += 1
        }
    }
    if ordinary_count == 0 do return .Missing_Buildings
    if plan.request.scale != .Village && plan.block_count == 0 do return .Missing_Blocks
    minimum_buildings := 70
    switch plan.request.scale {
    case .City:
        minimum_buildings = 70
    case .Town:
        minimum_buildings = 24
    case .Village:
        minimum_buildings = 8
    }
    if ordinary_count < minimum_buildings do return .Insufficient_Buildings
    if plan.request.scale == .Village {
        if village_purposes[int(Settlement_Building_Purpose.Dwelling)] < 7 ||
           village_purposes[int(Settlement_Building_Purpose.Workshop)] < 1 ||
           village_purposes[int(Settlement_Building_Purpose.Inn_Shop)] < 1 {
            return .Missing_Village_Program
        }
        switch plan.village_reason {
        case .Harbor_Fishery:
            if village_purposes[int(Settlement_Building_Purpose.Fishery)] < 2 ||
               village_purposes[int(Settlement_Building_Purpose.Storehouse)] < 2 ||
               village_purposes[int(Settlement_Building_Purpose.Farmstead)] > 0 {
                return .Missing_Village_Program
            }
        case .Agricultural_Terrace:
            if village_purposes[int(Settlement_Building_Purpose.Farmstead)] < 2 ||
               village_purposes[int(Settlement_Building_Purpose.Barn_Granary)] < 3 ||
               village_purposes[int(Settlement_Building_Purpose.Mill)] < 1 {
                return .Missing_Village_Program
            }
        case .Upland_Pastoral:
            if village_purposes[int(Settlement_Building_Purpose.Farmstead)] < 1 ||
               village_purposes[int(Settlement_Building_Purpose.Barn_Granary)] < 2 ||
               village_purposes[int(Settlement_Building_Purpose.Storehouse)] < 1 {
                return .Missing_Village_Program
            }
        case .Route_Stop:
            if village_purposes[int(Settlement_Building_Purpose.Farmstead)] < 1 ||
               village_purposes[int(Settlement_Building_Purpose.Barn_Granary)] < 1 ||
               village_purposes[int(Settlement_Building_Purpose.Storehouse)] < 1 {
                return .Missing_Village_Program
            }
        }
    }
    minimum_quadrants := plan.request.scale == .Village ? 2 : 3
    maximum_aspect := plan.request.scale == .Village ? f32(3.2) : f32(3.5)
    if plan.metrics.fabric_quadrants < minimum_quadrants || plan.metrics.fabric_aspect_ratio > maximum_aspect {
        return .Fabric_Form
    }
    if f32(in_target_band) / f32(ordinary_count) < .80 do return .Height_Band
    if plan.request.scale == .City {
        if f32(ordinary_above_22) / f32(ordinary_count) > .0201 do return .Height_Outlier
    } else if ordinary_above_22 > 0 {
        return .Height_Outlier
    }
    landmark_minimum, landmark_maximum := 1, 1
    switch plan.request.scale {
    case .City:
        landmark_minimum, landmark_maximum = 3, 6
    case .Town:
        landmark_minimum, landmark_maximum = 2, 3
    case .Village:
        landmark_minimum, landmark_maximum = 1, 1
    }
    if plan.metrics.landmark_count < landmark_minimum || plan.metrics.landmark_count > landmark_maximum {
        return .Landmark_Count
    }
    if plan.metrics.park_count < 1 do return .Park_Count
    return .None
}

settlement_plan_acceptance_valid :: proc(plan: ^Settlement_Plan, project: ^terrain.Project) -> bool {
    return settlement_plan_acceptance_failure(plan, project) == .None
}

settlement_plan_report :: proc(plan: ^Settlement_Plan) -> string {
    if plan == nil do return ""
    return fmt.tprintf(
        "routes %d width %.2f [%.2f..%.2f] grade p90 %.3f access %d/%d J%d/%d/H%d X%d/T%d D%d/R%d S%d/E%d W%d/%d/Q%.2f O%d ends %d/%.1fm | blocks %d %.1fx%.1f | buildings %d height %.1f [%.1f..%.1f] step %.1fm form %.2f/%dQ | landmarks %d parks %d | terrain %d cut %.0f fill %.0f | wide %.1f%% minor %.1f%% | acceptance %v",
        plan.route_count,
        plan.metrics.route_width.mean,
        plan.metrics.route_width.min,
        plan.metrics.route_width.max,
        plan.metrics.route_grade.p90,
        plan.access_connected_count,
        plan.access_required_count,
        plan.access_max_degree,
        plan.access_shallow_junctions,
        plan.access_hairpin_bends,
        plan.access_crossings,
        plan.access_unsplit_junctions,
        plan.access_bad_door_approaches,
        plan.access_bad_road_approaches,
        plan.access_stair_routes,
        plan.access_excessive_grades,
        plan.access_widened_segments,
        plan.access_shared_segments,
        plan.access_max_shared_width_step,
        plan.access_orphan_endpoints,
        plan.metrics.dead_end_frontage.count,
        plan.metrics.dead_end_frontage.p90,
        plan.block_count,
        plan.metrics.block_short_side.mean,
        plan.metrics.block_long_side.mean,
        plan.metrics.building_height.count,
        plan.metrics.building_height.mean,
        plan.metrics.building_height.min,
        plan.metrics.building_height.max,
        plan.metrics.building_base_elevation.max - plan.metrics.building_base_elevation.min,
        plan.metrics.fabric_aspect_ratio,
        plan.metrics.fabric_quadrants,
        plan.metrics.landmark_count,
        plan.metrics.park_count,
        plan.terrain_edit_count,
        plan.metrics.cut_volume,
        plan.metrics.fill_volume,
        plan.metrics.wide_route_share * 100,
        plan.metrics.minor_route_share * 100,
        plan.acceptance_failure,
    )
}

settlement_village_program_report :: proc(plan: ^Settlement_Plan) -> string {
    if plan == nil || plan.request.scale != .Village do return ""
    counts: [8]int
    for site in plan.sites[:plan.site_count] {
        if site.accepted && site.kind == .Ordinary do counts[int(site.purpose)] += 1
    }
    return fmt.tprintf(
        "reason %v | homes %d farmsteads %d barns %d workshops %d inns %d mills %d fisheries %d stores %d",
        plan.village_reason,
        counts[int(Settlement_Building_Purpose.Dwelling)],
        counts[int(Settlement_Building_Purpose.Farmstead)],
        counts[int(Settlement_Building_Purpose.Barn_Granary)],
        counts[int(Settlement_Building_Purpose.Workshop)],
        counts[int(Settlement_Building_Purpose.Inn_Shop)],
        counts[int(Settlement_Building_Purpose.Mill)],
        counts[int(Settlement_Building_Purpose.Fishery)],
        counts[int(Settlement_Building_Purpose.Storehouse)],
    )
}

settlement_stats_report :: proc(stats: Settlement_Scalar_Stats) -> string {
    return fmt.tprintf(
        "n=%d mean=%.2f min=%.2f p10=%.2f median=%.2f p90=%.2f max=%.2f",
        stats.count,
        stats.mean,
        stats.min,
        stats.p10,
        stats.median,
        stats.p90,
        stats.max,
    )
}
