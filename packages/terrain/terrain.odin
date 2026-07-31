package terrain

import buildings "../buildings"
import dunes "../dunes"
import estuaries "../estuaries"
import islands "../islands"
import roads "../roads"
import spring_river "../spring_river"
import "base:runtime"
import "core:math"
import "core:math/linalg"
import "core:os"

// The sixth, 32 m level keeps the full authored archipelago resident when the
// camera is near either island. Five levels only covered about 2 km from the
// camera, so the opposite island disappeared well before the 12 km far plane.
CLIPMAP_LEVELS :: 6
WORLD_SIZE_METERS :: 8000.0
TERRAIN_RESOLUTION :: 512
RING_RESOLUTION :: 256
SAMPLES_PER_LEVEL :: TERRAIN_RESOLUTION * TERRAIN_RESOLUTION
BASE_CELL_SIZE :: WORLD_SIZE_METERS / f32(RING_RESOLUTION - 1)
FINE_CELL_SIZE :: f32(1.0)
// Authored structures are world-space objects, so their minimum footprint
// must not grow when the clipmap's world coverage changes. Sixteen metres
// preserves the former 4 km world's practical minimum while the 8 km terrain
// uses larger coarse cells.
MIN_STRUCTURE_SIZE :: f32(4000.0 / f32(RING_RESOLUTION - 1))

// These are expressed as a fraction of the authored world's half extent. Every
// clipmap level samples the same world-space features at a different density.
DEFAULT_ISLAND_OFFSET :: 0.65
// Generated islands need enough hinterland for the compact STOL runway to read
// as one piece of infrastructure rather than the island's defining shape.
DEFAULT_ISLAND_RADIUS :: 0.26
DEFAULT_ISLAND_HEIGHT :: 4.5
DEFAULT_ISLAND_SIGNS :: [2]f32{-1, 1}
// 400 m gives the Postale enough field for its validated utility-STOL takeoff
// and landing envelope without cutting an oversized stripe across an island.
// Fractions are halved with the doubled world extent so aviation
// infrastructure retains its authored real-world dimensions.
DEFAULT_RUNWAY_HALF_LENGTH :: 0.05
DEFAULT_RUNWAY_HALF_WIDTH :: 0.006
DEFAULT_RUNWAY_SPAWN_OFFSET :: 0.03
DEFAULT_RUNWAY_SHOULDER :: f32(48)
DEFAULT_RUNWAY_TERRAIN_FEATHER :: f32(32)
// On the doubled islands the town is a distinct destination between the
// airfield and coast, not apron-side dressing.
DEFAULT_TOWN_OFFSET :: 420.0
DEFAULT_TOWN_HILL_HEIGHT :: 7.5
DEFAULT_TOWN_HILL_RADIUS_X :: 145.0
DEFAULT_TOWN_HILL_RADIUS_Z :: 65.0
DEFAULT_TOWN_SITE_RADIUS :: f32(245)
DEFAULT_TOWN_RUNWAY_CLEARANCE :: f32(80)
DEFAULT_CHANNEL_DIAGONAL :: f32(.70710678)
DEFAULT_PLAYER_LANDFORM_HEIGHT :: f32(1.35)
DEFAULT_GENERATED_ISLAND_HALF_X :: f32(1300)
DEFAULT_GENERATED_ISLAND_HALF_Z :: f32(920)
DEFAULT_ISLAND_SEEDS :: [2]u32{0x6ab219f4, 0xc85d037e}
// Island dunes remain gentler and narrower than the lab's showcase belt, but
// need enough relief to read through stabilized ecology at gameplay scale.
// The half-metre inner clipmap now supports this bounded height without the
// terrain tears produced by the former coarse rendering path.
DEFAULT_DUNE_HEIGHT :: f32(5.4)
DEFAULT_DUNE_SPACING :: f32(38)
DEFAULT_DUNE_WIDTH :: f32(68)
DEFAULT_DUNE_MAX_WIDTH :: f32(82)
DEFAULT_ESTUARY_HALF_EXTENT :: f32(330)
DEFAULT_RIVER_LENGTH :: f32(380)

Default_Island_Hydrology :: struct {
    river:               spring_river.Plan,
    estuary:             estuaries.Plan,
    archetype:           estuaries.Archetype,
    estuary_center:      spring_river.Vec2,
    estuary_half_extent: f32,
    coast_position:      spring_river.Vec2,
}

default_island_hydrology_destroy :: proc(hydrology: ^Default_Island_Hydrology) {
    if hydrology == nil do return
    estuaries.destroy(&hydrology.estuary)
    hydrology^ = {}
}

default_main_land_south_shore :: proc(island: ^islands.Plan, local_x: f32) -> (south, north: f32, ok: bool) {
    if island == nil || islands.sample_signed_distance(island, local_x, 0) >= 0 do return
    south, north = 0, 0
    step := f32(.01)
    for z := f32(0); z >= -1; z -= step {
        if islands.sample_signed_distance(island, local_x, z) >= 0 {
            south = min(z + step, f32(0))
            break
        }
        south = z
    }
    for z := f32(0); z <= 1; z += step {
        if islands.sample_signed_distance(island, local_x, z) >= 0 {
            north = max(z - step, f32(0))
            break
        }
        north = z
    }
    ok = true
    return
}

default_island_hydrology_generate :: proc(
    island: ^islands.Plan,
    island_seed: u32,
    island_index: int,
    sign: f32,
) -> Default_Island_Hydrology {
    if island == nil do return {}
    unit := proc(value: u32) -> f32 { return f32(islands.hash(value) & 0xffff) / 65535 }
    // Drain the center-connected land mass on the island's outward flank.
    // This avoids detached coastal islets as well as the central runway and
    // inward-facing settlement district.
    preferred_x := .24 + unit(island_seed ~ 0x4d4f5558) * .06
    candidates := [9]f32{
        preferred_x,
        preferred_x - .04,
        preferred_x + .04,
        preferred_x - .08,
        preferred_x + .08,
        .22,
        .16,
        -.22,
        0,
    }
    local_mouth_x, local_coast_z := f32(0), f32(-.72)
    found_main_shore := false
    for candidate_x in candidates {
        south, north, ok := default_main_land_south_shore(island, clamp(candidate_x, f32(-.62), f32(.62)))
        if !ok do continue
        // Keep the source inside the same center-connected interval. The
        // estuary inlet is .76 domain radii inland of the shoreline.
        source_offset := (DEFAULT_ESTUARY_HALF_EXTENT * .76 + DEFAULT_RIVER_LENGTH) / DEFAULT_GENERATED_ISLAND_HALF_Z
        if south + source_offset >= north - .04 do continue
        local_mouth_x, local_coast_z = candidate_x, south
        found_main_shore = true
        break
    }
    if !found_main_shore {
        south, _, ok := default_main_land_south_shore(island, 0)
        if ok do local_coast_z = south
    }
    center_x, center_z := default_island_center(sign)
    world_mouth_x := center_x + local_mouth_x * DEFAULT_GENERATED_ISLAND_HALF_X * (sign < 0 ? f32(-1) : f32(1))
    world_coast_z := center_z + local_coast_z * DEFAULT_GENERATED_ISLAND_HALF_Z
    estuary_half := DEFAULT_ESTUARY_HALF_EXTENT
    // Canonical estuaries put the basin head near normalized +0.24. Align
    // that point with the generated shoreline; +1 remains the guaranteed
    // inland river connection and -1 opens onto the sea.
    estuary_center := spring_river.Vec2{world_mouth_x, world_coast_z - estuary_half * .24}
    river_mouth_z := estuary_center[1] + estuary_half
    archetype: estuaries.Archetype = island_index & 1 == 0 ? .Tidal_Estuary : .Distributary_Delta
    discharge := archetype == .Distributary_Delta ? f32(1.18) : f32(.72)
    source_height := 15 + unit(island_seed ~ 0x53524348) * 7
    river := spring_river.generate(
        {
            seed = islands.hash(island_seed ~ 0x52495652),
            source = {world_mouth_x, river_mouth_z + DEFAULT_RIVER_LENGTH},
            direction = {0, -1},
            source_height = source_height,
            length = DEFAULT_RIVER_LENGTH,
            segment_length = 8,
            gradient = source_height / DEFAULT_RIVER_LENGTH,
            discharge = discharge,
            meander = .48 + unit(island_seed ~ 0x4d45414e) * .34,
            spring_radius = 5 + discharge * 2.4,
        },
    )
    // Preserve seeded meanders, but contract individual bends toward the
    // proven center-connected drainage line whenever they leave the island.
    for point_index in 0 ..< river.point_count {
        point := &river.points[point_index]
        local_x := (point.position[0] - center_x) / DEFAULT_GENERATED_ISLAND_HALF_X
        if sign < 0 do local_x = -local_x
        local_z := (point.position[1] - center_z) / DEFAULT_GENERATED_ISLAND_HALF_Z
        if islands.sample_signed_distance(island, local_x, local_z) < 0 do continue
        proposed_x := point.position[0]
        inside_amount, outside_amount := f32(0), f32(1)
        for _ in 0 ..< 10 {
            amount := (inside_amount + outside_amount) * .5
            test_x := world_mouth_x + (proposed_x - world_mouth_x) * amount
            test_local_x := (test_x - center_x) / DEFAULT_GENERATED_ISLAND_HALF_X
            if sign < 0 do test_local_x = -test_local_x
            if islands.sample_signed_distance(island, test_local_x, local_z) < 0 {
                inside_amount = amount
            } else {
                outside_amount = amount
            }
        }
        point.position[0] = world_mouth_x + (proposed_x - world_mouth_x) * inside_amount * .96
    }
    mouth := spring_river.mouth(&river)
    config := estuaries.config_from_river_mouth(mouth, archetype, estuary_half)
    config.seed = islands.hash(island_seed ~ 0x45535455)
    config.orientation = .North
    config.mean_sea_level = 0
    estuary := estuaries.generate(config)
    return {
        river = river,
        estuary = estuary,
        archetype = archetype,
        estuary_center = estuary_center,
        estuary_half_extent = estuary_half,
        coast_position = {world_mouth_x, world_coast_z},
    }
}

Generated_Dune_Character :: struct {
    height:              f32,
    spacing:             f32,
    width:               f32,
    wind_strength:       f32,
    vegetation_strength: f32,
}

Generated_Coast_Context :: struct {
    outward_normal: dunes.Vec2,
    distance_scale: f32,
    bayness:        f32,
    wind_exposure:  f32,
}

Generated_Coastal_Morphology :: struct {
    beach_width:       f32,
    dune_height_scale: f32,
    dune_width_scale:  f32,
    vegetation_scale:  f32,
}

default_generated_dune_character :: proc(seed: u32) -> Generated_Dune_Character {
    unit := proc(value: u32) -> f32 {
        return f32(islands.hash(value) & 0xffff) / 65535
    }
    // Keep island-to-island character readable and bounded. The raised floor
    // prevents suitable coasts from collapsing into a flat ecology tint, while
    // the narrow range still excludes towering or terrain-tear-like ridges.
    return {
        height = 4.6 + unit(seed ~ 0x48454947) * 1.6,
        spacing = 34 + unit(seed ~ 0x53504143) * 11,
        width = 60 + unit(seed ~ 0x57494454) * 22,
        wind_strength = .58 + unit(seed ~ 0x57494e44) * .20,
        vegetation_strength = .58 + unit(seed ~ 0x56454745) * .24,
    }
}

default_generated_coastal_morphology :: proc(
    seed: u32,
    world_x, world_z: f32,
    bayness, wind_exposure: f32,
) -> Generated_Coastal_Morphology {
    bay := clamp(bayness, f32(-1), f32(1))
    exposure := clamp(wind_exposure, f32(0), f32(1))
    // Sheltered concave coasts retain a broader depositional beach and wider,
    // greener low dunes. Exposed convex coasts concentrate the same sand into
    // a narrower, more pronounced foredune. Seeded alongshore variation
    // remains, but no local context can leave the validated operating range.
    return {
        beach_width = clamp(
            default_generated_beach_width(seed, world_x, world_z) + bay * 4.5 + (1 - exposure) * 1.5,
            f32(18),
            f32(39),
        ),
        dune_height_scale = clamp(.78 + exposure * .24 + max(-bay, f32(0)) * .06, f32(.76), f32(1.08)),
        dune_width_scale = clamp(.92 + max(bay, f32(0)) * .13 - max(-bay, f32(0)) * .10, f32(.82), f32(1.05)),
        vegetation_scale = clamp(1.03 + max(bay, f32(0)) * .10 - exposure * .08, f32(.92), f32(1.13)),
    }
}

default_island_center :: #force_inline proc(sign: f32) -> (x, z: f32) {
    center := sign * f32(WORLD_SIZE_METERS * .5 * DEFAULT_ISLAND_OFFSET)
    return center, center
}

default_island_feature_seed :: #force_inline proc(island_index: int, salt: u32) -> u32 {
    if island_index < 0 || island_index >= len(DEFAULT_ISLAND_SEEDS) do return islands.hash(salt)
    seeds := DEFAULT_ISLAND_SEEDS
    return islands.hash(seeds[island_index] ~ salt)
}

// Give each generated island an airport site of its own instead of laying both
// strips across the mathematical island center. Offsets are deterministically
// derived from the island seed, kept well inside the generated core, and
// remain axis-aligned because the Postale's initial ground heading is -X.
default_runway_center_for_seed :: proc(sign: f32, seed: u32) -> (x, z: f32) {
    center_x, center_z := default_island_center(sign)
    unit := proc(value: u32) -> f32 {
        return f32(islands.hash(value) & 0xffff) / 65535 * 2 - 1
    }
    // Bias the airfield toward the channel-facing arrival district, then add
    // enough seeded cross-island variation to follow each silhouette.
    inward := -sign
    return center_x + inward * 54 + unit(seed ~ 0x52554e58) * 46, center_z + inward * 28 + unit(seed ~ 0x52554e5a) * 62
}

default_runway_center :: proc(sign: f32) -> (x, z: f32) {
    island_index := sign < 0 ? 0 : 1
    seeds := DEFAULT_ISLAND_SEEDS
    return default_runway_center_for_seed(sign, seeds[island_index])
}

// Keep the island's three arrival anchors in one compact, walkable district.
// Towns sit inland from the channel-facing marina while the runway crosses the
// same district at the island center.
default_town_center :: #force_inline proc(sign: f32) -> (x, z: f32) {
    center_x, center_z := default_island_center(sign)
    inward := -sign
    // The smaller cross-runway offset keeps the town close to the apron; the
    // full offset clears the runway shoulder and its terrain feather.
    return center_x + inward * DEFAULT_TOWN_OFFSET * .6, center_z + inward * DEFAULT_TOWN_OFFSET
}

default_town_center_for_project :: proc(
    project: ^Project,
    sign: f32,
    town_radius: f32 = DEFAULT_TOWN_SITE_RADIUS,
) -> (
    x, z: f32,
) {
    nominal_x, nominal_z := default_town_center(sign)
    if project == nil do return nominal_x, nominal_z
    island_x, island_z := default_island_center(sign)
    runway_x, runway_z := default_runway_center(sign)
    runway_half_length := f32(WORLD_SIZE_METERS * .5) * DEFAULT_RUNWAY_HALF_LENGTH
    best_x, best_z, best_score := nominal_x, nominal_z, f32(-1e30)
    step := f32(36)
    search_radius := f32(800)
    for offset_z := -search_radius; offset_z <= search_radius; offset_z += step {
        for offset_x := -search_radius; offset_x <= search_radius; offset_x += step {
            candidate_x, candidate_z := nominal_x + offset_x, nominal_z + offset_z
            if math.abs(candidate_x - island_x) > DEFAULT_GENERATED_ISLAND_HALF_X * .82 ||
               math.abs(candidate_z - island_z) > DEFAULT_GENERATED_ISLAND_HALF_Z * .82 {
                continue
            }
            runway_dx := max(math.abs(candidate_x - runway_x) - runway_half_length, f32(0))
            runway_dz := math.abs(candidate_z - runway_z)
            runway_distance := f32(math.sqrt(f64(runway_dx * runway_dx + runway_dz * runway_dz)))
            if runway_distance < town_radius + DEFAULT_TOWN_RUNWAY_CLEARANCE do continue
            minimum_height := sample_height(project, 0, candidate_x, candidate_z)
            maximum_height := minimum_height
            average_height := minimum_height
            sample_count := 1
            valid := minimum_height > project.sea_level + .8
            radii := [2]f32{town_radius * .55, town_radius}
            for radius in radii {
                for sample_index in 0 ..< 32 {
                    angle := f32(sample_index) * math.TAU / 32
                    sample_x := candidate_x + math.cos(angle) * radius
                    sample_z := candidate_z + math.sin(angle) * radius
                    height := sample_height(project, 0, sample_x, sample_z)
                    minimum_height = min(minimum_height, height)
                    maximum_height = max(maximum_height, height)
                    average_height += height
                    sample_count += 1
                    if height <= project.sea_level + .8 {
                        valid = false
                        break
                    }
                }
                if !valid do break
            }
            if !valid do continue
            average_height /= f32(sample_count)
            nominal_distance := linalg.length([2]f32{candidate_x - nominal_x, candidate_z - nominal_z})
            island_distance := linalg.length([2]f32{candidate_x - island_x, candidate_z - island_z})
            score :=
                -nominal_distance -
                (maximum_height - minimum_height) * 85 -
                math.abs(average_height - DEFAULT_ISLAND_HEIGHT) * 8 -
                island_distance * .01 +
                min(runway_distance, town_radius * 2) * .04
            if score > best_score {
                best_x, best_z, best_score = candidate_x, candidate_z, score
            }
        }
    }
    return best_x, best_z
}

// The airport forecourt sits just inland of the active threshold, directly on
// the town approach. Keeping this shared with road generation and gameplay
// placement prevents the terminal from drifting away from its access road.
default_airport_center_for_seed :: proc(sign: f32, seed: u32) -> (x, z: f32) {
    center_x, center_z := default_runway_center_for_seed(sign, seed)
    half_extent := f32(WORLD_SIZE_METERS * .5)
    runway_threshold_x := center_x - sign * half_extent * DEFAULT_RUNWAY_HALF_LENGTH
    town_x, town_z := default_town_center(sign)
    approach_amount := f32(.18)
    return runway_threshold_x + (town_x - runway_threshold_x) * approach_amount,
        center_z + (town_z - center_z) * approach_amount
}

default_airport_center :: proc(sign: f32) -> (x, z: f32) {
    island_index := sign < 0 ? 0 : 1
    seeds := DEFAULT_ISLAND_SEEDS
    return default_airport_center_for_seed(sign, seeds[island_index])
}

// Carry the town approach past the airport rather than through its open
// arcade. Two parallel-offset waypoints form a short bypass with enough
// clearance for the terminal footprint, road shoulder, and planted apron.
default_airport_road_bypass_for_seed :: proc(sign: f32, seed: u32) -> (before_x, before_z, after_x, after_z: f32) {
    center_x, center_z := default_runway_center_for_seed(sign, seed)
    half_extent := f32(WORLD_SIZE_METERS * .5)
    threshold_x := center_x - sign * half_extent * DEFAULT_RUNWAY_HALF_LENGTH
    town_x, town_z := default_town_center(sign)
    airport_x, airport_z := default_airport_center_for_seed(sign, seed)
    direction := linalg.normalize0([2]f32{town_x - threshold_x, town_z - center_z})
    normal := [2]f32{-direction[1], direction[0]}
    // Keep both islands' bypasses on the same visual side of their mirrored
    // terminals instead of allowing route direction to flip the offset.
    if normal[1] * sign < 0 do normal = -normal
    along := f32(27)
    clearance := f32(23)
    before := [2]f32{airport_x, airport_z} - direction * along + normal * clearance
    after := [2]f32{airport_x, airport_z} + direction * along + normal * clearance
    return before[0], before[1], after[0], after[1]
}

default_marina_direction :: #force_inline proc(sign: f32) -> (x, z: f32) {
    inward := -sign * DEFAULT_CHANNEL_DIAGONAL
    return inward, inward
}

Tool :: enum {
    Raise,
    Smooth,
    Paint,
    Structure,
}

Formation_Kind :: enum {
    Box,
    Rock,
    Spire,
    Mountain,
    Ridge,
    Cliff,
    Foliage,
    Architecture,
    Ruins,
}

LEGACY_STRUCTURE_CAPACITY :: 256
CITY_DENSITY_SAMPLES :: SAMPLES_PER_LEVEL
PROJECT_FILE_MAGIC :: [8]u8{'A', 'D', 'R', 'T', 'E', 'R', 'R', '7'}
PROJECT_FILE_MAGIC_V6 :: [8]u8{'A', 'D', 'R', 'T', 'E', 'R', 'R', '6'}
PROJECT_FILE_MAGIC_V5 :: [8]u8{'A', 'D', 'R', 'T', 'E', 'R', 'R', '5'}
PROJECT_FILE_MAGIC_V4 :: [8]u8{'A', 'D', 'R', 'T', 'E', 'R', 'R', '4'}
PROJECT_FILE_MAGIC_V3 :: [8]u8{'A', 'D', 'R', 'T', 'E', 'R', 'R', '3'}

Project_File_Header :: struct {
    magic:        [8]u8,
    payload_size: u64,
}

Entrance_Side :: enum u8 {
    Front,
    Right,
    Rear,
    Left,
}

Structure :: struct {
    id:            u64,
    group_id:      u64,
    center_x:      f32,
    center_z:      f32,
    width:         f32,
    depth:         f32,
    base_y:        f32,
    height:        f32,
    rotation:      f32,
    color:         [4]u8,
    kind:          Formation_Kind,
    entrance_side: Entrance_Side,
    seed:          u32,
    building:      buildings.Identity,
}

Clipmap_Level :: struct {
    cell_size: f32,
    origin_x:  f32,
    origin_z:  f32,
    heights:   [SAMPLES_PER_LEVEL]f32,
    material:  [SAMPLES_PER_LEVEL]f32,
}

LEGACY_TERRAIN_RESOLUTION :: 256
LEGACY_TERRAIN_SAMPLES :: LEGACY_TERRAIN_RESOLUTION * LEGACY_TERRAIN_RESOLUTION

Clipmap_Level_V6 :: struct {
    cell_size: f32,
    origin_x:  f32,
    origin_z:  f32,
    heights:   [LEGACY_TERRAIN_SAMPLES]f32,
    material:  [LEGACY_TERRAIN_SAMPLES]f32,
}

Project :: struct {
    levels:                [CLIPMAP_LEVELS]Clipmap_Level,
    sea_level:             f32,
    revision:              u64,
    structures:            [dynamic]Structure,
    structure_count:       int,
    next_structure_id:     u64,
    road_graph:            roads.Graph,
    city_density:          [CITY_DENSITY_SAMPLES]u8,
    climbing_leaf_density: [CITY_DENSITY_SAMPLES]u8,
}

Project_File_Payload :: struct {
    levels:                [CLIPMAP_LEVELS]Clipmap_Level,
    sea_level:             f32,
    revision:              u64,
    structure_count:       u64,
    next_structure_id:     u64,
    road_graph:            roads.Graph,
    city_density:          [CITY_DENSITY_SAMPLES]u8,
    climbing_leaf_density: [CITY_DENSITY_SAMPLES]u8,
}

Project_File_Payload_V6 :: struct {
    levels:                [CLIPMAP_LEVELS]Clipmap_Level_V6,
    sea_level:             f32,
    revision:              u64,
    structure_count:       u64,
    next_structure_id:     u64,
    road_graph:            roads.Graph,
    city_density:          [CITY_DENSITY_SAMPLES]u8,
    climbing_leaf_density: [CITY_DENSITY_SAMPLES]u8,
}

Structure_V5 :: struct {
    id:       u64,
    group_id: u64,
    center_x: f32,
    center_z: f32,
    width:    f32,
    depth:    f32,
    base_y:   f32,
    height:   f32,
    rotation: f32,
    color:    [4]u8,
    kind:     Formation_Kind,
    seed:     u32,
    building: buildings.Identity,
}

Project_V4 :: struct {
    levels:                [CLIPMAP_LEVELS]Clipmap_Level_V6,
    sea_level:             f32,
    revision:              u64,
    structures:            [LEGACY_STRUCTURE_CAPACITY]Structure_V5,
    structure_count:       int,
    next_structure_id:     u64,
    road_graph:            roads.Graph,
    city_density:          [CITY_DENSITY_SAMPLES]u8,
    climbing_leaf_density: [CITY_DENSITY_SAMPLES]u8,
}

Structure_V3 :: struct {
    id:       u64,
    group_id: u64,
    center_x: f32,
    center_z: f32,
    width:    f32,
    depth:    f32,
    base_y:   f32,
    height:   f32,
    rotation: f32,
    color:    [4]u8,
    kind:     Formation_Kind,
    seed:     u32,
}

Project_V3 :: struct {
    levels:                [CLIPMAP_LEVELS]Clipmap_Level_V6,
    sea_level:             f32,
    revision:              u64,
    structures:            [LEGACY_STRUCTURE_CAPACITY]Structure_V3,
    structure_count:       int,
    next_structure_id:     u64,
    road_graph:            roads.Graph,
    city_density:          [CITY_DENSITY_SAMPLES]u8,
    climbing_leaf_density: [CITY_DENSITY_SAMPLES]u8,
}

project_file_magic_is :: proc(header: ^Project_File_Header, magic: [8]u8) -> bool {
    if header == nil do return false
    for index in 0 ..< len(magic) {
        if header.magic[index] != magic[index] do return false
    }
    return true
}

project_replace :: proc(project, loaded: ^Project) {
    if project == nil || loaded == nil do return
    for &structure in loaded.structures[:loaded.structure_count] {
        // Structures are solid world geometry. Older projects inherited the
        // translucent editor swatch alpha (220), which made their terrain
        // show through once world alpha blending was enabled.
        if structure.kind != .Foliage do structure.color[3] = 255
    }
    delete(project.structures)
    project^ = loaded^
    loaded.structures = nil
}

structure_migrate_v5 :: proc(source: Structure_V5) -> Structure {
    return {
        id = source.id,
        group_id = source.group_id,
        center_x = source.center_x,
        center_z = source.center_z,
        width = source.width,
        depth = source.depth,
        base_y = source.base_y,
        height = source.height,
        rotation = source.rotation,
        color = source.color,
        kind = source.kind,
        entrance_side = .Front,
        seed = source.seed,
        building = source.building,
    }
}

legacy_level_contains :: #force_inline proc(level: ^Clipmap_Level_V6, x, z: f32) -> bool {
    if level == nil do return false
    extent := f32(LEGACY_TERRAIN_RESOLUTION - 1) * level.cell_size
    return x >= level.origin_x && z >= level.origin_z && x <= level.origin_x + extent && z <= level.origin_z + extent
}

terrain_lerp :: #force_inline proc(a, b, t: f32) -> f32 { return a + (b - a) * t }

legacy_level_sample :: proc(level: ^Clipmap_Level_V6, x, z: f32) -> (height, material: f32) {
    gx := clamp((x - level.origin_x) / level.cell_size, f32(0), f32(LEGACY_TERRAIN_RESOLUTION - 1))
    gz := clamp((z - level.origin_z) / level.cell_size, f32(0), f32(LEGACY_TERRAIN_RESOLUTION - 1))
    x0 := int(math.floor(f64(gx)))
    z0 := int(math.floor(f64(gz)))
    x1 := min(x0 + 1, LEGACY_TERRAIN_RESOLUTION - 1)
    z1 := min(z0 + 1, LEGACY_TERRAIN_RESOLUTION - 1)
    tx, tz := gx - f32(x0), gz - f32(z0)
    i00 := z0 * LEGACY_TERRAIN_RESOLUTION + x0
    i10 := z0 * LEGACY_TERRAIN_RESOLUTION + x1
    i01 := z1 * LEGACY_TERRAIN_RESOLUTION + x0
    i11 := z1 * LEGACY_TERRAIN_RESOLUTION + x1
    height = terrain_lerp(
        terrain_lerp(level.heights[i00], level.heights[i10], tx),
        terrain_lerp(level.heights[i01], level.heights[i11], tx),
        tz,
    )
    material = terrain_lerp(
        terrain_lerp(level.material[i00], level.material[i10], tx),
        terrain_lerp(level.material[i01], level.material[i11], tx),
        tz,
    )
    return
}

legacy_levels_sample :: proc(levels: ^[CLIPMAP_LEVELS]Clipmap_Level_V6, x, z: f32) -> (height, material: f32) {
    for level in 0 ..< CLIPMAP_LEVELS {
        if legacy_level_contains(&levels[level], x, z) {
            return legacy_level_sample(&levels[level], x, z)
        }
    }
    return legacy_level_sample(&levels[CLIPMAP_LEVELS - 1], x, z)
}

terrain_levels_migrate_v6 :: proc(
    destination: ^[CLIPMAP_LEVELS]Clipmap_Level,
    source: ^[CLIPMAP_LEVELS]Clipmap_Level_V6,
) {
    for level in 0 ..< CLIPMAP_LEVELS {
        old := &source[level]
        target := &destination[level]
        target.cell_size = old.cell_size
        old_extent := f32(LEGACY_TERRAIN_RESOLUTION - 1) * old.cell_size
        center_x := old.origin_x + old_extent * .5
        center_z := old.origin_z + old_extent * .5
        new_extent := f32(TERRAIN_RESOLUTION - 1) * target.cell_size
        target.origin_x = center_x - new_extent * .5
        target.origin_z = center_z - new_extent * .5
        for z in 0 ..< TERRAIN_RESOLUTION {
            world_z := target.origin_z + f32(z) * target.cell_size
            for x in 0 ..< TERRAIN_RESOLUTION {
                world_x := target.origin_x + f32(x) * target.cell_size
                height, material := legacy_levels_sample(source, world_x, world_z)
                index := z * TERRAIN_RESOLUTION + x
                target.heights[index] = height
                target.material[index] = material
            }
        }
    }
}

project_migrate_v4 :: proc(project: ^Project, legacy: ^Project_V4) -> bool {
    if project == nil ||
       legacy == nil ||
       legacy.structure_count < 0 ||
       legacy.structure_count > LEGACY_STRUCTURE_CAPACITY {
        return false
    }
    loaded := new(Project)
    defer free(loaded)
    terrain_levels_migrate_v6(&loaded.levels, &legacy.levels)
    loaded.sea_level = legacy.sea_level
    loaded.revision = legacy.revision
    loaded.structure_count = legacy.structure_count
    loaded.next_structure_id = legacy.next_structure_id
    loaded.road_graph = legacy.road_graph
    loaded.city_density = legacy.city_density
    loaded.climbing_leaf_density = legacy.climbing_leaf_density
    resize(&loaded.structures, loaded.structure_count)
    for source, index in legacy.structures[:loaded.structure_count] {
        loaded.structures[index] = structure_migrate_v5(source)
    }
    project_replace(project, loaded)
    return true
}

project_migrate_v5 :: proc(project: ^Project, payload: ^Project_File_Payload_V6, structure_data: []byte) -> bool {
    if project == nil || payload == nil do return false
    structure_count := int(payload.structure_count)
    if structure_count < 0 ||
       structure_count > len(structure_data) / size_of(Structure_V5) ||
       structure_count * size_of(Structure_V5) != len(structure_data) {
        return false
    }
    loaded := new(Project)
    defer free(loaded)
    terrain_levels_migrate_v6(&loaded.levels, &payload.levels)
    loaded.sea_level = payload.sea_level
    loaded.revision = payload.revision
    loaded.structure_count = structure_count
    loaded.next_structure_id = payload.next_structure_id
    loaded.road_graph = payload.road_graph
    loaded.city_density = payload.city_density
    loaded.climbing_leaf_density = payload.climbing_leaf_density
    resize(&loaded.structures, structure_count)
    if structure_count > 0 {
        legacy_structures := cast([^]Structure_V5)raw_data(structure_data)
        for index in 0 ..< structure_count {
            loaded.structures[index] = structure_migrate_v5(legacy_structures[index])
        }
    }
    project_replace(project, loaded)
    return true
}

project_migrate_v6 :: proc(project: ^Project, payload: ^Project_File_Payload_V6, structure_data: []byte) -> bool {
    if project == nil || payload == nil do return false
    structure_count := int(payload.structure_count)
    if structure_count < 0 ||
       structure_count > len(structure_data) / size_of(Structure) ||
       structure_count * size_of(Structure) != len(structure_data) {
        return false
    }
    loaded := new(Project)
    defer free(loaded)
    terrain_levels_migrate_v6(&loaded.levels, &payload.levels)
    loaded.sea_level = payload.sea_level
    loaded.revision = payload.revision + 1
    loaded.structure_count = structure_count
    loaded.next_structure_id = payload.next_structure_id
    loaded.road_graph = payload.road_graph
    loaded.city_density = payload.city_density
    loaded.climbing_leaf_density = payload.climbing_leaf_density
    resize(&loaded.structures, structure_count)
    if structure_count > 0 {
        runtime.mem_copy_non_overlapping(raw_data(loaded.structures), raw_data(structure_data), len(structure_data))
    }
    project_replace(project, loaded)
    return true
}

project_migrate_v3 :: proc(project: ^Project, legacy: ^Project_V3) -> bool {
    if project == nil || legacy == nil do return false
    if legacy.structure_count < 0 || legacy.structure_count > LEGACY_STRUCTURE_CAPACITY do return false
    loaded := new(Project)
    defer free(loaded)
    terrain_levels_migrate_v6(&loaded.levels, &legacy.levels)
    loaded.sea_level = legacy.sea_level
    loaded.revision = legacy.revision
    loaded.structure_count = legacy.structure_count
    loaded.next_structure_id = legacy.next_structure_id
    loaded.road_graph = legacy.road_graph
    loaded.city_density = legacy.city_density
    loaded.climbing_leaf_density = legacy.climbing_leaf_density
    resize(&loaded.structures, loaded.structure_count)
    for source, index in legacy.structures[:legacy.structure_count] {
        target := &loaded.structures[index]
        target.id = source.id
        target.group_id = source.group_id
        target.center_x = source.center_x
        target.center_z = source.center_z
        target.width = source.width
        target.depth = source.depth
        target.base_y = source.base_y
        target.height = source.height
        target.rotation = source.rotation
        target.color = source.color
        target.kind = source.kind
        target.seed = source.seed
        if source.kind == .Architecture do target.building.archetype = .Legacy
    }
    project_replace(project, loaded)
    return true
}

save_project :: proc(project: ^Project, filename: string) -> bool {
    if project == nil ||
       filename == "" ||
       project.structure_count < 0 ||
       project.structure_count > len(project.structures) {
        return false
    }
    header_size := size_of(Project_File_Header)
    payload_size := size_of(Project_File_Payload) + project.structure_count * size_of(Structure)
    data := make([]byte, header_size + payload_size)
    defer delete(data)
    header := cast(^Project_File_Header)raw_data(data)
    header^ = {
        magic        = PROJECT_FILE_MAGIC,
        payload_size = u64(payload_size),
    }
    payload := cast(^Project_File_Payload)raw_data(data[header_size:])
    payload^ = {
        levels                = project.levels,
        sea_level             = project.sea_level,
        revision              = project.revision,
        structure_count       = u64(project.structure_count),
        next_structure_id     = project.next_structure_id,
        road_graph            = project.road_graph,
        city_density          = project.city_density,
        climbing_leaf_density = project.climbing_leaf_density,
    }
    if project.structure_count > 0 {
        structure_data := data[header_size + size_of(Project_File_Payload):]
        runtime.mem_copy_non_overlapping(
            raw_data(structure_data),
            raw_data(project.structures),
            project.structure_count * size_of(Structure),
        )
    }
    return os.write_entire_file(filename, data) == nil
}

load_project :: proc(project: ^Project, filename: string) -> bool {
    if project == nil || filename == "" do return false
    data, err := os.read_entire_file_from_path(filename, context.allocator)
    if err != nil do return false
    defer delete(data)
    header_size := size_of(Project_File_Header)
    if len(data) < header_size do return false
    header := cast(^Project_File_Header)raw_data(data)
    if project_file_magic_is(header, PROJECT_FILE_MAGIC) {
        if header.payload_size != u64(len(data) - header_size) ||
           len(data) < header_size + size_of(Project_File_Payload) {
            return false
        }
        payload := cast(^Project_File_Payload)raw_data(data[header_size:])
        structure_bytes := len(data) - header_size - size_of(Project_File_Payload)
        if payload.structure_count > u64(structure_bytes / size_of(Structure)) ||
           int(payload.structure_count) * size_of(Structure) != structure_bytes {
            return false
        }
        loaded := new(Project)
        defer free(loaded)
        loaded.levels = payload.levels
        loaded.sea_level = payload.sea_level
        loaded.revision = payload.revision
        loaded.structure_count = int(payload.structure_count)
        loaded.next_structure_id = payload.next_structure_id
        loaded.road_graph = payload.road_graph
        loaded.city_density = payload.city_density
        loaded.climbing_leaf_density = payload.climbing_leaf_density
        resize(&loaded.structures, loaded.structure_count)
        if loaded.structure_count > 0 {
            structure_data := data[header_size + size_of(Project_File_Payload):]
            runtime.mem_copy_non_overlapping(raw_data(loaded.structures), raw_data(structure_data), structure_bytes)
        }
        project_replace(project, loaded)
        return true
    }
    if project_file_magic_is(header, PROJECT_FILE_MAGIC_V6) {
        if header.payload_size != u64(len(data) - header_size) ||
           len(data) < header_size + size_of(Project_File_Payload_V6) {
            return false
        }
        payload := cast(^Project_File_Payload_V6)raw_data(data[header_size:])
        structure_data := data[header_size + size_of(Project_File_Payload_V6):]
        return project_migrate_v6(project, payload, structure_data)
    }
    if project_file_magic_is(header, PROJECT_FILE_MAGIC_V5) {
        if header.payload_size != u64(len(data) - header_size) ||
           len(data) < header_size + size_of(Project_File_Payload_V6) {
            return false
        }
        payload := cast(^Project_File_Payload_V6)raw_data(data[header_size:])
        structure_data := data[header_size + size_of(Project_File_Payload_V6):]
        return project_migrate_v5(project, payload, structure_data)
    }
    if project_file_magic_is(header, PROJECT_FILE_MAGIC_V4) {
        if header.payload_size != size_of(Project_V4) || len(data) != header_size + size_of(Project_V4) {
            return false
        }
        return project_migrate_v4(project, cast(^Project_V4)raw_data(data[header_size:]))
    }
    if !project_file_magic_is(header, PROJECT_FILE_MAGIC_V3) ||
       header.payload_size != size_of(Project_V3) ||
       len(data) != header_size + size_of(Project_V3) {
        return false
    }
    return project_migrate_v3(project, cast(^Project_V3)raw_data(data[header_size:]))
}

add_default_runways_seeded :: proc(project: ^Project, seeds: [len(DEFAULT_ISLAND_SEEDS)]u32) -> bool {
    if project == nil ||
       project.road_graph.node_count + len(DEFAULT_ISLAND_SIGNS) * 5 > roads.MAX_NODES ||
       project.road_graph.edge_count + len(DEFAULT_ISLAND_SIGNS) * 4 > roads.MAX_EDGES {
        return false
    }
    half_extent := f32(WORLD_SIZE_METERS * .5)
    runway_half_length := half_extent * DEFAULT_RUNWAY_HALF_LENGTH
    runway_width := half_extent * DEFAULT_RUNWAY_HALF_WIDTH * 2
    for sign, island_index in DEFAULT_ISLAND_SIGNS {
        seed := seeds[island_index]
        center_x, center_z := default_runway_center_for_seed(sign, seed)
        runway_height := sample_height(project, 0, center_x, center_z)
        from := roads.add_node(&project.road_graph, {center_x - runway_half_length, runway_height, center_z}, 0)
        to := roads.add_node(&project.road_graph, {center_x + runway_half_length, runway_height, center_z}, 0)
        if from < 0 ||
           to < 0 ||
           roads.add_straight_edge(&project.road_graph, from, to, runway_width, 2, .Asphalt) < 0 {
            return false
        }
        town_x, town_z := default_town_center_for_project(project, sign)
        town_y := sample_height(project, 0, town_x, town_z)
        town := roads.add_node(&project.road_graph, {town_x, town_y, town_z}, 7)
        before_x, before_z, after_x, after_z := default_airport_road_bypass_for_seed(sign, seed)
        before_y := sample_height(project, 0, before_x, before_z)
        after_y := sample_height(project, 0, after_x, after_z)
        before := roads.add_node(&project.road_graph, {before_x, before_y, before_z}, 8)
        after := roads.add_node(&project.road_graph, {after_x, after_y, after_z}, 8)
        inward_threshold := sign < 0 ? to : from
        if town < 0 ||
           before < 0 ||
           after < 0 ||
           roads.add_straight_edge(&project.road_graph, inward_threshold, before, 8, 2, .Asphalt, .85) < 0 ||
           roads.add_straight_edge(&project.road_graph, before, after, 8, 2, .Asphalt, .85) < 0 ||
           roads.add_straight_edge(&project.road_graph, after, town, 7, 1.5, .Asphalt, .85) < 0 {
            return false
        }
    }
    return true
}

add_default_runways :: proc(project: ^Project) -> bool {
    return add_default_runways_seeded(project, DEFAULT_ISLAND_SEEDS)
}

terrain_erode_default_level :: proc(data: ^Clipmap_Level, scratch: []f32, half_extent: f32, iterations: int = 2) {
    if data == nil || len(scratch) < SAMPLES_PER_LEVEL || iterations <= 0 do return
    constraints := default_terrain_constraints(half_extent)
    talus := .32 + data.cell_size * .035
    for _ in 0 ..< iterations {
        copy(scratch, data.heights[:])
        for z in 1 ..< TERRAIN_RESOLUTION - 1 {
            world_z := data.origin_z + f32(z) * data.cell_size
            for x in 1 ..< TERRAIN_RESOLUTION - 1 {
                index := sample_index(x, z)
                height := scratch[index]
                if height <= 0 do continue
                neighbor_average :=
                    (scratch[sample_index(x - 1, z)] +
                        scratch[sample_index(x + 1, z)] +
                        scratch[sample_index(x, z - 1)] +
                        scratch[sample_index(x, z + 1)] +
                        scratch[sample_index(x - 1, z - 1)] +
                        scratch[sample_index(x + 1, z - 1)] +
                        scratch[sample_index(x - 1, z + 1)] +
                        scratch[sample_index(x + 1, z + 1)]) /
                    8
                delta := neighbor_average - height
                excess := math.abs(delta) - talus
                if excess <= 0 do continue
                world_x := data.origin_x + f32(x) * data.cell_size
                runway_protection := max(
                    terrain_constraint_weight(constraints[10], world_x, world_z),
                    terrain_constraint_weight(constraints[11], world_x, world_z),
                )
                erosion_strength := .18 * (1 - runway_protection)
                adjustment := clamp(excess * erosion_strength, 0, 1.1)
                if delta < 0 do adjustment = -adjustment
                eroded := max(height + adjustment, f32(0))
                // Do not leave isolated millimetric shelves in open water.
                data.heights[index] = eroded < .015 ? 0 : eroded
            }
        }
    }
}

next_default_island_seeds :: proc(current: [len(DEFAULT_ISLAND_SEEDS)]u32) -> [len(DEFAULT_ISLAND_SEEDS)]u32 {
    result := current
    defaults := DEFAULT_ISLAND_SEEDS
    for &seed, island_index in result {
        if seed == 0 do seed = defaults[island_index]
        seed = islands.hash(seed + 0x9e3779b9 + u32(island_index) * 0x85ebca6b)
    }
    return result
}

default_island_feature_seed_for :: #force_inline proc(island_seed, salt: u32) -> u32 {
    return islands.hash(island_seed ~ salt)
}

init_project_seeded :: proc(result: ^Project, seeds: [len(DEFAULT_ISLAND_SEEDS)]u32) {
    if result == nil do return
    delete(result.structures)
    result^ = {}
    result.sea_level = 0
    result.revision = 1
    result.next_structure_id = 1
    authored_half_extent := f32(WORLD_SIZE_METERS * .5)
    gameplay_center := authored_half_extent * DEFAULT_ISLAND_OFFSET
    generated_islands: [len(DEFAULT_ISLAND_SIGNS)]islands.Plan
    generated_hydrology: [len(DEFAULT_ISLAND_SIGNS)]Default_Island_Hydrology
    island_signs := DEFAULT_ISLAND_SIGNS
    for seed, island_index in seeds {
        generated_islands[island_index] = islands.generate(seed)
        generated_hydrology[island_index] = default_island_hydrology_generate(
            &generated_islands[island_index],
            seed,
            island_index,
            island_signs[island_index],
        )
    }
    defer for &plan in generated_islands do islands.destroy(&plan)
    defer for &hydrology in generated_hydrology do default_island_hydrology_destroy(&hydrology)
    erosion_scratch := make([]f32, SAMPLES_PER_LEVEL)
    defer delete(erosion_scratch)
    for level in 0 ..< CLIPMAP_LEVELS {
        data := &result.levels[level]
        data.cell_size = FINE_CELL_SIZE * f32(math.pow(2, f64(level)))
        level_center_x, level_center_z := gameplay_center, gameplay_center
        if level == 0 do level_center_x += authored_half_extent * DEFAULT_RUNWAY_SPAWN_OFFSET
        if level == CLIPMAP_LEVELS - 1 {
            level_center_x, level_center_z = 0, 0
        }
        half_grid := f32(TERRAIN_RESOLUTION - 1) * .5 * data.cell_size
        data.origin_x = level_center_x - half_grid
        data.origin_z = level_center_z - half_grid
        for z in 0 ..< TERRAIN_RESOLUTION {
            for x in 0 ..< TERRAIN_RESOLUTION {
                world_x := data.origin_x + f32(x) * data.cell_size
                world_z := data.origin_z + f32(z) * data.cell_size
                height, material := default_generated_height_filtered(
                    &generated_islands,
                    world_x,
                    world_z,
                    authored_half_extent,
                    data.cell_size,
                    &generated_hydrology,
                )
                data.heights[sample_index(x, z)] = height
                data.material[sample_index(x, z)] = material
            }
        }
        terrain_erode_default_level(data, erosion_scratch, authored_half_extent)
    }
    _ = add_default_runways_seeded(result, seeds)
    refresh_derived_overlaps(result)
}

init_project :: proc(result: ^Project) {
    init_project_seeded(result, DEFAULT_ISLAND_SEEDS)
}

snap_to_grid :: proc(value, grid: f32) -> f32 {
    if grid <= 0 do return value
    return f32(math.round(f64(value / grid))) * grid
}

structure_default_color :: proc() -> [4]u8 {
    return {112, 169, 181, 255}
}

structure_make :: proc(center_x, center_z, width, depth, base_y, height: f32) -> Structure {
    return {
        center_x = center_x,
        center_z = center_z,
        width = max(width, MIN_STRUCTURE_SIZE),
        depth = max(depth, MIN_STRUCTURE_SIZE),
        base_y = base_y,
        height = max(height, MIN_STRUCTURE_SIZE),
        color = structure_default_color(),
        kind = .Box,
    }
}

formation_kind_next :: proc(kind: Formation_Kind) -> Formation_Kind {
    switch kind {
    case .Box:
        return .Rock
    case .Rock:
        return .Spire
    case .Spire:
        return .Mountain
    case .Mountain:
        return .Ridge
    case .Ridge:
        return .Cliff
    case .Cliff:
        return .Foliage
    case .Foliage:
        return .Box
    case .Architecture:
        return .Box
    case .Ruins:
        return .Box
    }
    return .Box
}

formation_kind_for_gesture :: proc(width, depth, height: f32) -> Formation_Kind {
    wide := max(width, depth)
    narrow := max(min(width, depth), BASE_CELL_SIZE)
    aspect := wide / narrow
    if aspect >= 2.4 do return .Ridge
    if height >= wide * 1.65 do return .Spire
    if height >= narrow * 1.15 do return .Mountain
    return .Rock
}

formation_segments_can_merge :: proc(start_x, start_z, joint_x, joint_z, end_x, end_z, minimum_cosine: f32) -> bool {
    first_x, first_z := joint_x - start_x, joint_z - start_z
    second_x, second_z := end_x - joint_x, end_z - joint_z
    first_length_squared := first_x * first_x + first_z * first_z
    second_length_squared := second_x * second_x + second_z * second_z
    if first_length_squared <= 0 || second_length_squared <= 0 do return false
    inverse_lengths := 1 / f32(math.sqrt(f64(first_length_squared * second_length_squared)))
    cosine := (first_x * second_x + first_z * second_z) * inverse_lengths
    return cosine >= minimum_cosine
}

structure_contains_point :: proc(structure: Structure, x, z: f32) -> bool {
    dx, dz := x - structure.center_x, z - structure.center_z
    cosine, sine := math.cos(structure.rotation), math.sin(structure.rotation)
    local_x := dx * cosine + dz * sine
    local_z := -dx * sine + dz * cosine
    return math.abs(local_x) <= structure.width * .5 && math.abs(local_z) <= structure.depth * .5
}

structure_index_at :: proc(project: ^Project, x, z: f32) -> int {
    if project == nil do return -1
    for index := project.structure_count - 1; index >= 0; index -= 1 {
        if structure_contains_point(project.structures[index], x, z) do return index
    }
    return -1
}

structure_collision_surface_height :: proc(project: ^Project, x, z, fallback: f32) -> f32 {
    if project == nil do return fallback
    result := fallback
    for structure in project.structures[:project.structure_count] {
        if structure.kind == .Foliage ||
           structure.width <= 0 ||
           structure.depth <= 0 ||
           structure.height <= 0 ||
           !structure_contains_point(structure, x, z) {
            continue
        }
        result = max(result, structure.base_y + structure.height)
    }
    return result
}

add_structure :: proc(project: ^Project, structure: Structure) -> int {
    if project == nil do return -1
    value := structure
    value.id = project.next_structure_id
    project.next_structure_id += 1
    if value.group_id == 0 do value.group_id = value.id
    value.seed = u32(value.id * 747796405)
    index := project.structure_count
    if index < len(project.structures) {
        project.structures[index] = value
    } else {
        append(&project.structures, value)
    }
    project.structure_count += 1
    project.revision += 1
    return index
}

add_or_merge_foliage :: proc(project: ^Project, structure: Structure, padding: f32 = 0) -> int {
    if project == nil || structure.kind != .Foliage do return add_structure(project, structure)

    for index := project.structure_count - 1; index >= 0; index -= 1 {
        existing := &project.structures[index]
        if existing.kind != .Foliage do continue
        dx, dz := structure.center_x - existing.center_x, structure.center_z - existing.center_z
        existing_radius := max(existing.width, existing.depth) * .5
        incoming_radius := max(structure.width, structure.depth) * .5
        merge_radius := existing_radius + incoming_radius + max(padding, 0)
        if dx * dx + dz * dz > merge_radius * merge_radius do continue

        // Brush foliage is rotationally symmetric enough that an axis-aligned
        // union preserves its authored footprint while allowing later stamps
        // to coalesce with the enlarged node.
        minimum_x := min(existing.center_x - existing.width * .5, structure.center_x - structure.width * .5)
        maximum_x := max(existing.center_x + existing.width * .5, structure.center_x + structure.width * .5)
        minimum_z := min(existing.center_z - existing.depth * .5, structure.center_z - structure.depth * .5)
        maximum_z := max(existing.center_z + existing.depth * .5, structure.center_z + structure.depth * .5)
        maximum_y := max(existing.base_y + existing.height, structure.base_y + structure.height)
        existing.center_x = (minimum_x + maximum_x) * .5
        existing.center_z = (minimum_z + maximum_z) * .5
        existing.width = maximum_x - minimum_x
        existing.depth = maximum_z - minimum_z
        existing.base_y = min(existing.base_y, structure.base_y)
        existing.height = maximum_y - existing.base_y
        existing.rotation = 0
        project.revision += 1
        return index
    }
    return add_structure(project, structure)
}

add_or_merge_formation :: proc(
    project: ^Project,
    structure: Structure,
    padding: f32 = 0,
    classify: bool = true,
) -> int {
    if project == nil || structure.kind == .Foliage || structure.kind == .Architecture || structure.group_id == 0 {
        return add_structure(project, structure)
    }

    for index := project.structure_count - 1; index >= 0; index -= 1 {
        existing := &project.structures[index]
        if existing.kind == .Foliage || existing.kind == .Architecture || existing.group_id != structure.group_id {
            continue
        }
        dx, dz := structure.center_x - existing.center_x, structure.center_z - existing.center_z
        existing_radius := max(existing.width, existing.depth) * .5
        incoming_radius := max(structure.width, structure.depth) * .5
        merge_radius := existing_radius + incoming_radius + max(padding, 0)
        if dx * dx + dz * dz > merge_radius * merge_radius do continue

        minimum_x := min(existing.center_x - existing.width * .5, structure.center_x - structure.width * .5)
        maximum_x := max(existing.center_x + existing.width * .5, structure.center_x + structure.width * .5)
        minimum_z := min(existing.center_z - existing.depth * .5, structure.center_z - structure.depth * .5)
        maximum_z := max(existing.center_z + existing.depth * .5, structure.center_z + structure.depth * .5)
        maximum_y := max(existing.base_y + existing.height, structure.base_y + structure.height)
        existing.center_x = (minimum_x + maximum_x) * .5
        existing.center_z = (minimum_z + maximum_z) * .5
        existing.width = maximum_x - minimum_x
        existing.depth = maximum_z - minimum_z
        existing.base_y = min(existing.base_y, structure.base_y)
        existing.height = maximum_y - existing.base_y
        existing.rotation = 0
        if classify {
            existing.kind = formation_kind_for_gesture(existing.width, existing.depth, existing.height)
        }
        project.revision += 1
        return index
    }
    return add_structure(project, structure)
}

remove_structure :: proc(project: ^Project, index: int) -> bool {
    if project == nil || index < 0 || index >= project.structure_count do return false
    last := project.structure_count - 1
    if index != last do project.structures[index] = project.structures[last]
    project.structures[last] = {}
    project.structure_count -= 1
    project.revision += 1
    return true
}

duplicate_structure :: proc(project: ^Project, index: int, offset_x, offset_z: f32) -> int {
    if project == nil || index < 0 || index >= project.structure_count do return -1
    copy := project.structures[index]
    copy.group_id = 0
    copy.center_x += offset_x
    copy.center_z += offset_z
    return add_structure(project, copy)
}

new_project :: proc() -> ^Project {
    result := new(Project)
    init_project(result)
    return result
}

new_project_seeded :: proc(seeds: [len(DEFAULT_ISLAND_SEEDS)]u32) -> ^Project {
    result := new(Project)
    init_project_seeded(result, seeds)
    return result
}

destroy_project :: proc(project: ^Project) {
    if project == nil do return
    delete(project.structures)
    project.structures = nil
    project.structure_count = 0
}

free_project :: proc(project: ^Project) {
    if project == nil do return
    destroy_project(project)
    free(project)
}

@(no_instrumentation)
sample_index :: #force_inline proc(x, z: int) -> int { return z * TERRAIN_RESOLUTION + x }

Terrain_Constraint_Mode :: enum u8 {
    Add,
    Set,
}

Terrain_Constraint_Shape :: enum u8 {
    Ellipse,
    Rectangle,
}

Terrain_Constraint_Curve :: enum u8 {
    Smooth,
    Quadratic,
}

// Generators describe the surface they need without knowing which other
// generators overlap it. Constraints are composed in ascending priority:
// natural land, additive topography, then infrastructure leveling.
Terrain_Constraint :: struct {
    mode:     Terrain_Constraint_Mode,
    shape:    Terrain_Constraint_Shape,
    curve:    Terrain_Constraint_Curve,
    priority: i32,
    center_x: f32,
    center_z: f32,
    half_x:   f32,
    half_z:   f32,
    rotation: f32,
    feather:  f32,
    target:   f32,
}

terrain_smooth_weight :: proc(value: f32) -> f32 {
    t := clamp(value, 0, 1)
    return t * t * (3 - 2 * t)
}

terrain_constraint_weight :: proc(constraint: Terrain_Constraint, world_x, world_z: f32) -> f32 {
    if constraint.half_x <= 0 || constraint.half_z <= 0 do return 0
    offset_x := world_x - constraint.center_x
    offset_z := world_z - constraint.center_z
    cosine := f32(math.cos(f64(constraint.rotation)))
    sine := f32(math.sin(f64(constraint.rotation)))
    dx := math.abs(offset_x * cosine + offset_z * sine)
    dz := math.abs(-offset_x * sine + offset_z * cosine)
    weight: f32
    switch constraint.shape {
    case .Ellipse:
        normalized_x := dx / constraint.half_x
        normalized_z := dz / constraint.half_z
        distance := f32(math.sqrt(f64(normalized_x * normalized_x + normalized_z * normalized_z)))
        if distance >= 1 do return 0
        if constraint.curve == .Quadratic {
            weight = 1 - distance * distance
            return weight * weight
        }
        edge_fraction := constraint.feather / max(constraint.half_x, constraint.half_z)
        weight = (1 - distance) / max(edge_fraction, .0001)
    case .Rectangle:
        outside_x := max(dx - constraint.half_x, 0)
        outside_z := max(dz - constraint.half_z, 0)
        outside_distance := f32(math.sqrt(f64(outside_x * outside_x + outside_z * outside_z)))
        if outside_distance <= 0 do return 1
        if constraint.feather <= 0 || outside_distance >= constraint.feather do return 0
        weight = 1 - outside_distance / constraint.feather
    }
    return terrain_smooth_weight(weight)
}

terrain_apply_constraint :: proc(height: f32, constraint: Terrain_Constraint, world_x, world_z: f32) -> f32 {
    weight := terrain_constraint_weight(constraint, world_x, world_z)
    if weight <= 0 do return height
    switch constraint.mode {
    case .Add:
        return height + constraint.target * weight
    case .Set:
        return height * (1 - weight) + constraint.target * weight
    }
    return height
}

terrain_ellipse_signed_distance :: proc(constraint: Terrain_Constraint, world_x, world_z: f32) -> f32 {
    offset_x := world_x - constraint.center_x
    offset_z := world_z - constraint.center_z
    cosine := f32(math.cos(f64(constraint.rotation)))
    sine := f32(math.sin(f64(constraint.rotation)))
    local_x := offset_x * cosine + offset_z * sine
    local_z := -offset_x * sine + offset_z * cosine
    normalized_x := local_x / max(constraint.half_x, .001)
    normalized_z := local_z / max(constraint.half_z, .001)
    normalized_distance := f32(math.sqrt(f64(normalized_x * normalized_x + normalized_z * normalized_z)))
    return (normalized_distance - 1) * min(constraint.half_x, constraint.half_z)
}

terrain_smooth_min :: #force_inline proc(a, b, radius: f32) -> f32 {
    if radius <= 0 do return min(a, b)
    blend := clamp(.5 + .5 * (b - a) / radius, 0, 1)
    return b + (a - b) * blend - radius * blend * (1 - blend)
}

default_island_signed_distance :: proc(
    constraints: ^[12]Terrain_Constraint,
    island_index: int,
    world_x, world_z: f32,
) -> f32 {
    distance := terrain_ellipse_signed_distance(constraints[island_index], world_x, world_z)
    distance = terrain_smooth_min(
        distance,
        terrain_ellipse_signed_distance(constraints[2 + island_index], world_x, world_z),
        34,
    )
    distance = terrain_smooth_min(
        distance,
        terrain_ellipse_signed_distance(constraints[4 + island_index], world_x, world_z),
        34,
    )
    return distance
}

default_natural_land_height :: proc(
    constraints: ^[12]Terrain_Constraint,
    world_x, world_z: f32,
) -> (
    height, signed_distance: f32,
) {
    west := default_island_signed_distance(constraints, 0, world_x, world_z)
    east := default_island_signed_distance(constraints, 1, world_x, world_z)
    signed_distance = min(west, east)
    shoreline_feather := f32(52)
    weight := terrain_smooth_weight(-signed_distance / shoreline_feather)
    return DEFAULT_ISLAND_HEIGHT * weight, signed_distance
}

// Layer rolling ground beneath authored hills and infrastructure. The three
// oblique bands make forms that are legible on foot (roughly 25-100 m apart)
// without introducing one-meter noise that would jitter vehicles or physics.
// Coordinates are island-local so the distant archipelago does not inherit a
// conspicuous world-spanning pattern.
default_player_landform_offset :: proc(world_x, world_z, island_center, island_sign: f32) -> f32 {
    local_x := world_x - island_center
    local_z := world_z - island_center
    u := local_x * .84 + local_z * .54 * island_sign
    v := -local_x * .54 * island_sign + local_z * .84
    broad_phase := u * .061 + f32(math.sin(f64(v * .026))) * .85
    broad := f32(math.sin(f64(broad_phase)))
    cross := f32(math.sin(f64((u + v * .63) * .112 + island_sign * 1.7)))
    hummock := f32(math.cos(f64((u * .71 - v) * .178 - island_sign * .9)))
    return broad * DEFAULT_PLAYER_LANDFORM_HEIGHT + cross * .58 + hummock * .24
}

default_bluff_offset :: proc(world_x, world_z, island_center, island_sign: f32) -> f32 {
    local_x := world_x - island_center
    local_z := world_z - island_center
    west := island_sign < 0
    // Put the bluff opposite the channel-facing arrival district. Rotated
    // coordinates give each island a different escarpment silhouette.
    anchor_x := west ? f32(-118) : f32(112)
    anchor_z := west ? f32(104) : f32(92)
    rotation := west ? f32(.42) : f32(-.55)
    cosine := f32(math.cos(f64(rotation)))
    sine := f32(math.sin(f64(rotation)))
    offset_x, offset_z := local_x - anchor_x, local_z - anchor_z
    along := offset_x * cosine + offset_z * sine
    across := -offset_x * sine + offset_z * cosine

    // A long headland mask limits the shelf; the 14 m directional transition
    // makes its sea-facing edge read as a bluff rather than another hill.
    ellipse := 1 - (along / 142) * (along / 142) - (across / 88) * (across / 88)
    headland_weight := terrain_smooth_weight(ellipse / .38)
    face_weight := terrain_smooth_weight((across + 20) / 14)
    crown_rolloff := terrain_smooth_weight((76 - across) / 24)
    height := west ? f32(10.5) : f32(8.5)
    return height * headland_weight * face_weight * crown_rolloff
}

default_terrain_constraints :: proc(half_extent: f32) -> [12]Terrain_Constraint {
    constraints: [12]Terrain_Constraint
    runway_half_length := half_extent * DEFAULT_RUNWAY_HALF_LENGTH
    runway_half_width := half_extent * DEFAULT_RUNWAY_HALF_WIDTH
    for sign, island_index in DEFAULT_ISLAND_SIGNS {
        center := sign * half_extent * DEFAULT_ISLAND_OFFSET
        runway_x, runway_z := default_runway_center(sign)
        // Build each coast from three rotated, overlapping masses. A smaller
        // core leaves genuine bays between the lobes instead of hiding them
        // inside the old circular 560 m footprint.
        core_x := center + (island_index == 0 ? f32(-8) : f32(16))
        core_z := center + (island_index == 0 ? f32(12) : f32(-6))
        constraints[island_index] = {
            mode     = .Set,
            shape    = .Ellipse,
            curve    = .Smooth,
            priority = 0,
            center_x = core_x,
            center_z = core_z,
            half_x   = island_index == 0 ? f32(238) : f32(218),
            half_z   = island_index == 0 ? f32(182) : f32(205),
            rotation = island_index == 0 ? f32(-.34) : f32(.52),
            feather  = 58,
            target   = DEFAULT_ISLAND_HEIGHT,
        }
        constraints[2 + island_index] = {
            mode     = .Set,
            shape    = .Ellipse,
            curve    = .Smooth,
            priority = 1,
            center_x = center + (island_index == 0 ? f32(-112) : f32(112)),
            center_z = center + (island_index == 0 ? f32(112) : f32(92)),
            half_x   = island_index == 0 ? f32(168) : f32(142),
            half_z   = island_index == 0 ? f32(108) : f32(116),
            rotation = island_index == 0 ? f32(.48) : f32(-.58),
            feather  = 44,
            target   = DEFAULT_ISLAND_HEIGHT,
        }
        constraints[4 + island_index] = {
            mode     = .Set,
            shape    = .Ellipse,
            curve    = .Smooth,
            priority = 2,
            center_x = center + (island_index == 0 ? f32(118) : f32(-108)),
            center_z = center + (island_index == 0 ? f32(-82) : f32(-116)),
            half_x   = island_index == 0 ? f32(172) : f32(176),
            half_z   = island_index == 0 ? f32(98) : f32(102),
            rotation = island_index == 0 ? f32(-.38) : f32(.36),
            feather  = 42,
            target   = DEFAULT_ISLAND_HEIGHT,
        }
        town_x, town_z := default_town_center(sign)
        constraints[6 + island_index] = {
            mode     = .Add,
            shape    = .Ellipse,
            curve    = .Quadratic,
            priority = 10,
            center_x = town_x,
            center_z = town_z,
            half_x   = DEFAULT_TOWN_HILL_RADIUS_X,
            half_z   = DEFAULT_TOWN_HILL_RADIUS_Z,
            target   = DEFAULT_TOWN_HILL_HEIGHT,
        }
        constraints[8 + island_index] = {
            mode     = .Add,
            shape    = .Ellipse,
            curve    = .Quadratic,
            priority = 12,
            center_x = center + (island_index == 0 ? f32(-72) : f32(86)),
            center_z = center + (island_index == 0 ? f32(78) : f32(58)),
            half_x   = island_index == 0 ? f32(112) : f32(104),
            half_z   = island_index == 0 ? f32(42) : f32(48),
            rotation = island_index == 0 ? f32(.52) : f32(-.62),
            target   = island_index == 0 ? f32(8) : f32(6.5),
        }
        constraints[10 + island_index] = {
            mode     = .Set,
            shape    = .Rectangle,
            curve    = .Smooth,
            priority = 20,
            center_x = runway_x,
            center_z = runway_z,
            half_x   = runway_half_length + DEFAULT_RUNWAY_SHOULDER,
            half_z   = runway_half_width + DEFAULT_RUNWAY_SHOULDER,
            feather  = DEFAULT_RUNWAY_TERRAIN_FEATHER,
            target   = DEFAULT_ISLAND_HEIGHT,
        }
    }
    return constraints
}

terrain_compose_constraints :: proc(
    base_height: f32,
    constraints: []Terrain_Constraint,
    world_x, world_z: f32,
) -> f32 {
    height := base_height
    // Constraint producers return priority-ordered lists. Keeping composition
    // allocation-free matters because this runs for every clipmap sample.
    previous_priority: i32 = -2_147_483_647
    for constraint in constraints {
        assert(constraint.priority >= previous_priority)
        height = terrain_apply_constraint(height, constraint, world_x, world_z)
        previous_priority = constraint.priority
    }
    return height
}

default_height :: proc(world_x, world_z, half_extent: f32) -> f32 {
    constraints := default_terrain_constraints(half_extent)
    // Merge each island's three rotated masses as one continuous signed
    // distance field. This rounds the joins between lobes instead of layering
    // three independently rasterized ellipse edges.
    height, _ := default_natural_land_height(&constraints, world_x, world_z)
    if height > 0 {
        shoreline_weight := terrain_smooth_weight((height - .35) / (DEFAULT_ISLAND_HEIGHT - .35))
        for sign in DEFAULT_ISLAND_SIGNS {
            center := sign * half_extent * DEFAULT_ISLAND_OFFSET
            // Only the owning island contributes. Their footprints are far
            // enough apart that this inexpensive radius guard is unambiguous.
            dx, dz := world_x - center, world_z - center
            if dx * dx + dz * dz < 360 * 360 {
                height += default_player_landform_offset(world_x, world_z, center, sign) * shoreline_weight
                height += default_bluff_offset(world_x, world_z, center, sign) * shoreline_weight
                height = max(height, .12 * shoreline_weight)
                break
            }
        }
    }
    return terrain_compose_constraints(height, constraints[6:], world_x, world_z)
}

default_height_filtered :: proc(world_x, world_z, half_extent, cell_size: f32) -> f32 {
    center := default_height(world_x, world_z, half_extent)
    if cell_size <= 1 do return center
    constraints := default_terrain_constraints(half_extent)
    _, distance := default_natural_land_height(&constraints, world_x, world_z)
    // Supersample only the narrow shoreline band. Island interiors and the
    // open sea retain a single analytic evaluation, keeping project creation
    // inexpensive despite the 512×512 terrain levels.
    if math.abs(distance) > cell_size * 1.75 + 4 do return center
    offset := cell_size * .35
    a := default_height(world_x - offset, world_z - offset, half_extent)
    b := default_height(world_x + offset, world_z - offset, half_extent)
    c := default_height(world_x - offset, world_z + offset, half_extent)
    d := default_height(world_x + offset, world_z + offset, half_extent)
    return center * .4 + (a + b + c + d) * .15
}

default_generated_coast_context :: proc(
    plan: ^islands.Plan,
    local_x, local_z, island_sign: f32,
) -> Generated_Coast_Context {
    cell_x := DEFAULT_GENERATED_ISLAND_HALF_X * 2 / f32(islands.GRID_WIDTH - 1)
    cell_z := DEFAULT_GENERATED_ISLAND_HALF_Z * 2 / f32(islands.GRID_HEIGHT - 1)
    // Keep the scalar SDF metric stable across source-grid cells. Deriving
    // this scale from the local bilinear gradient shifts dune phase whenever
    // that gradient changes, producing narrow trench-like discontinuities.
    distance_scale := f32(math.sqrt(f64(cell_x * cell_z)))
    if plan == nil do return {outward_normal = {0, -1}, distance_scale = distance_scale}
    // Derive across one source-grid cell rather than one world metre. The
    // latter samples a bilinear field inside a single cell and yields a
    // piecewise-constant normal that jumps at cell boundaries.
    step_x := f32(2) / f32(islands.GRID_WIDTH - 1)
    step_z := f32(2) / f32(islands.GRID_HEIGHT - 1)
    left := islands.sample_signed_distance(plan, local_x - step_x, local_z)
    right := islands.sample_signed_distance(plan, local_x + step_x, local_z)
    back := islands.sample_signed_distance(plan, local_x, local_z - step_z)
    front := islands.sample_signed_distance(plan, local_x, local_z + step_z)
    grid_gradient_x := (right - left) * island_sign
    grid_gradient_z := front - back
    // The generated silhouette is stretched into a 2600-by-1840 metre island.
    // Transform its grid-space SDF gradient by the inverse world scale before
    // normalizing, otherwise diagonal and north/south shores inherit the
    // metric of an X-axis grid cell.
    gradient_x := grid_gradient_x / cell_x
    gradient_z := grid_gradient_z / cell_z
    length := f32(math.sqrt(f64(gradient_x * gradient_x + gradient_z * gradient_z)))
    normal := dunes.Vec2{0, -1}
    if length > .00001 do normal = {gradient_x / length, gradient_z / length}
    center := islands.sample_signed_distance(plan, local_x, local_z)
    laplacian_x := left + right - center * 2
    laplacian_z := back + front - center * 2
    // Preserve the established X-cell tuning while correcting the Z
    // contribution for the non-square world metric.
    laplacian := laplacian_x + laplacian_z * (cell_x * cell_x / (cell_z * cell_z))
    // Positive signed-distance curvature is a convex headland; negative
    // curvature is a concave bay. A broad clamp keeps coarse mask details from
    // overdriving beach morphology.
    bayness := clamp(-laplacian * .72, f32(-1), f32(1))
    inward := -normal
    prevailing_wind := dunes.Vec2{.18, .98}
    wind_length := f32(
        math.sqrt(f64(prevailing_wind[0] * prevailing_wind[0] + prevailing_wind[1] * prevailing_wind[1])),
    )
    prevailing_wind /= wind_length
    wind_inland := prevailing_wind[0] * inward[0] + prevailing_wind[1] * inward[1]
    wind_exposure := clamp((wind_inland + .12) / .82, f32(0), f32(1))
    return {outward_normal = normal, distance_scale = distance_scale, bayness = bayness, wind_exposure = wind_exposure}
}

default_generated_coast_normal :: proc(plan: ^islands.Plan, local_x, local_z, island_sign: f32) -> dunes.Vec2 {
    return default_generated_coast_context(plan, local_x, local_z, island_sign).outward_normal
}

default_generated_beach_width :: proc(seed: u32, world_x, world_z: f32) -> f32 {
    phase := f32(seed & 0xffff) * .0000958738
    broad := f32(math.sin(f64(world_x * .0037 + world_z * .0021 + phase)))
    detail := f32(math.sin(f64(world_x * -.0091 + world_z * .0063 + phase * 1.73)))
    return clamp(f32(27) + broad * 5 + detail * 2, f32(20), f32(35))
}

default_generated_shore_config :: proc(dry_beach_width: f32 = 24) -> dunes.Shore_Config {
    return {
        sea_level = 0,
        berm_height = .9,
        dry_beach_width = dry_beach_width,
        nearshore_width = 72,
        nearshore_depth = 3.2,
        shelf_width = 150,
        shelf_depth = 13,
        bar_strength = .74,
    }
}

default_apply_island_hydrology :: proc(
    hydrology: ^Default_Island_Hydrology,
    world_x, world_z, input_height, input_material: f32,
) -> (
    height, material: f32,
) {
    height, material = input_height, input_material
    if hydrology == nil do return

    river := spring_river.sample(&hydrology.river, {world_x, world_z})
    if river.bank_influence > .001 {
        bank_target := river.water_level + .18 + (1 - river.bank_influence) * 1.45
        height = min(height, height + (bank_target - height) * river.bank_influence)
        if river.inside_water do height = min(height, river.bed_height)
        material = -1 - river.wetness * .62
    }

    // A rejected coastal candidate must never be baked into normal terrain.
    // The independently constructive river remains useful and deterministic.
    if !hydrology.estuary.valid || len(hydrology.estuary.elevation) != estuaries.CELL_COUNT do return

    half := max(hydrology.estuary_half_extent, f32(1))
    nx := (world_x - hydrology.estuary_center[0]) / half
    nz := (world_z - hydrology.estuary_center[1]) / half
    if math.abs(nx) > 1 || math.abs(nz) > 1 do return
    class := estuaries.sample_wetland(&hydrology.estuary, nx, nz)
    if class == .Dry || class == .Open_Sea do return
    // The laboratory owns a finite square, but the island seabed does not.
    // Feather most of the outer domain and prevent deep-water cells from
    // being lifted into a square shelf. Channels may still carve through the
    // feather; deposition is restricted to naturally shallow coast water.
    edge := 1 - terrain_smooth_weight((max(math.abs(nx), math.abs(nz)) - .58) / .42)
    seaward := terrain_smooth_weight((nz + .42) / .20)
    edge *= seaward
    if edge <= .001 do return
    target := estuaries.sample_elevation(&hydrology.estuary, nx, nz)
    influence: f32
    #partial switch class {
    case .Channel:
        influence = 1
    case .Mudflat:
        influence = .88
    case .Marsh:
        influence = .82
    case .Shoal:
        influence = .76
    case:
        influence = 0
    }
    influence *= edge
    if class != .Marsh && target > height {
        depositional_core := terrain_smooth_weight((nz + .62) / .22)
        influence *= depositional_core
        target = min(target, f32(-.18))
    }
    if target > height {
        shallow_substrate := terrain_smooth_weight((height + 4.5) / 3.5)
        if class == .Marsh {
            // Marsh polygons are the generator's discrete depositional
            // islands. Let those build a little farther into the lobe while
            // keeping continuous shoal and channel fields tied to the
            // existing shallow seabed.
            lobe_deposition := terrain_smooth_weight((nz + .74) / .46) * edge
            lobe_core := terrain_smooth_weight((nz + .62) / .22)
            depth_support := terrain_smooth_weight((height + 9) / 6)
            target = max(target, .35 + lobe_deposition * .45)
            island_weight := lobe_deposition * lobe_core * (.72 + depth_support * .28)
            height = max(height, target * island_weight)
            influence = 0
        } else {
            influence *= shallow_substrate
        }
    }
    height += (target - height) * influence
    #partial switch class {
    case .Marsh:
        material = .35
    case .Channel, .Mudflat, .Shoal:
        material = -1.35
    case:
    }
    return
}

default_generated_height :: proc(
    plans: ^[len(DEFAULT_ISLAND_SIGNS)]islands.Plan,
    world_x, world_z, half_extent: f32,
    hydrologies: ^[len(DEFAULT_ISLAND_SIGNS)]Default_Island_Hydrology = nil,
) -> (
    height, signed_distance, material: f32,
) {
    signed_distance = 1e6
    if plans == nil do return
    for sign, island_index in DEFAULT_ISLAND_SIGNS {
        center := sign * half_extent * DEFAULT_ISLAND_OFFSET
        // Mirror the west island so both generated long axes point toward the
        // shared channel while retaining distinct seeded coastlines.
        local_x := (world_x - center) / DEFAULT_GENERATED_ISLAND_HALF_X
        local_z := (world_z - center) / DEFAULT_GENERATED_ISLAND_HALF_Z
        if sign < 0 do local_x = -local_x
        plan := &plans[island_index]
        grid_distance := islands.sample_signed_distance(plan, local_x, local_z)
        coast_context := default_generated_coast_context(plan, local_x, local_z, sign)
        distance_meters := grid_distance * coast_context.distance_scale
        signed_distance = min(signed_distance, distance_meters)
        if grid_distance >= 0 do continue
        generated := islands.sample_elevation(plan, local_x, local_z)
        bluff := islands.sample_bluff(plan, local_x, local_z)
        // Preserve the generator's natural coastal rise. The beach berm and
        // dunes add local relief below; a fixed 4.5 m minimum here filled bays
        // and low ridges into a broad table-flat shelf.
        shoreline := terrain_smooth_weight(-distance_meters / 38)
        // Retain small-scale traversable relief on broad generated shelves;
        // this operates inside the generated silhouette and does not prescribe
        // the coastline.
        generated += default_player_landform_offset(world_x, world_z, center, sign) * shoreline
        generated += default_bluff_offset(world_x, world_z, center, sign) * shoreline
        dune: dunes.Sample
        beach_material := f32(0)
        if distance_meters > -DEFAULT_DUNE_MAX_WIDTH {
            low_coast := terrain_smooth_weight((7 - generated) / 4)
            cliff_exclusion := terrain_smooth_weight((bluff - .46) / .32)
            coastal_suitability := low_coast * (1 - cliff_exclusion)
            morphology := default_generated_coastal_morphology(
                plan.selected_seed,
                world_x,
                world_z,
                coast_context.bayness,
                coast_context.wind_exposure,
            )
            inland_distance := -distance_meters
            // Resolve a continuous low-coast substrate before the dune ridges:
            // dark wet sand at the waterline, pale dry beach above it, then a
            // feather into the foredune matrix. Cliffs remain rock/soil.
            if coastal_suitability > .001 {
                beach_width := morphology.beach_width
                wet_width := clamp(beach_width * .27, f32(5.5), f32(9))
                shore_profile := dunes.shore_sample(default_generated_shore_config(beach_width), inland_distance)
                // Add only a low berm floor. Existing island relief and dune
                // ridges remain authoritative, and cliffs are unaffected.
                generated = max(generated, shore_profile.height * coastal_suitability)
                wetness := 1 - terrain_smooth_weight(inland_distance / wet_width)
                if wetness > .001 {
                    beach_material = (-1 - wetness) * coastal_suitability
                } else {
                    dry_beach := terrain_smooth_weight(
                        (beach_width - inland_distance) / max(f32(12), beach_width - wet_width),
                    )
                    beach_material = -dry_beach * coastal_suitability
                }
            }
            dune_character := default_generated_dune_character(plan.selected_seed)
            dune = dunes.sample_curved_coast(
                {
                    seed = plan.selected_seed ~ 0x44554e45,
                    wind_direction = {.18, .98},
                    wind_strength = dune_character.wind_strength,
                    dune_height = dune_character.height * morphology.dune_height_scale,
                    dune_spacing = dune_character.spacing,
                    dune_width = clamp(
                        dune_character.width * morphology.dune_width_scale,
                        f32(55),
                        DEFAULT_DUNE_MAX_WIDTH,
                    ),
                    vegetation_strength = clamp(
                        dune_character.vegetation_strength * morphology.vegetation_scale,
                        f32(0),
                        f32(1),
                    ),
                },
                {world_x, world_z},
                distance_meters,
                coast_context.outward_normal,
                coastal_suitability,
            )
            generated += dune.height_delta
        }
        if generated > height {
            height = generated
            material = min(material, beach_material)
            if dune.coverage > .01 {
                // Paint the ecological belt, not only the ridge height. A
                // height-gated mask produces isolated pale seams at distance;
                // the footprint gives the ridges a continuous sandy matrix
                // whose stable patches blend back into natural cover. Exposed
                // slip faces and blowouts retain enough pale sand contrast to
                // make the asymmetric ridge structure readable.
                active_sand := .56 + dune.exposure * .40
                dune_material := -active_sand * dune.sand_weight * dune.coverage
                material = min(material, dune_material)
            }
        }
    }
    if height <= 0 && signed_distance < 1e5 {
        coast := dunes.shore_sample(default_generated_shore_config(), -signed_distance)
        height = coast.height
        material = -1
    }
    if hydrologies != nil {
        for &hydrology in hydrologies {
            height, material = default_apply_island_hydrology(&hydrology, world_x, world_z, height, material)
        }
    }
    // Settlement parcels need a predictable construction datum before their
    // generated hill and the still-higher-priority runway are composed.
    infrastructure_weight := f32(0)
    for sign in DEFAULT_ISLAND_SIGNS {
        town_x, town_z := default_town_center(sign)
        foundation := Terrain_Constraint {
            mode     = .Set,
            shape    = .Ellipse,
            curve    = .Smooth,
            priority = 5,
            center_x = town_x,
            center_z = town_z,
            // A compact terrace, not a replacement landscape: the generated
            // island remains visible between parcels and immediately beyond
            // the civic core.
            half_x   = DEFAULT_TOWN_HILL_RADIUS_X + 5,
            half_z   = DEFAULT_TOWN_HILL_RADIUS_Z + 11,
            feather  = 50,
            target   = DEFAULT_ISLAND_HEIGHT,
        }
        foundation_weight := min(terrain_constraint_weight(foundation, world_x, world_z), f32(.72))
        infrastructure_weight = max(infrastructure_weight, foundation_weight)
        height = height * (1 - foundation_weight) + foundation.target * foundation_weight
        _, center_z := default_island_center(sign)
        access := Terrain_Constraint {
            mode     = .Set,
            shape    = .Rectangle,
            curve    = .Smooth,
            priority = 6,
            center_x = town_x,
            center_z = (center_z + town_z) * .5,
            half_x   = 25,
            half_z   = math.abs(town_z - center_z) * .5,
            feather  = 42,
            target   = DEFAULT_ISLAND_HEIGHT,
        }
        infrastructure_weight = max(infrastructure_weight, terrain_constraint_weight(access, world_x, world_z))
        height = terrain_apply_constraint(height, access, world_x, world_z)
    }
    constraints := default_terrain_constraints(half_extent)
    infrastructure_weight = max(
        infrastructure_weight,
        max(
            terrain_constraint_weight(constraints[10], world_x, world_z),
            terrain_constraint_weight(constraints[11], world_x, world_z),
        ),
    )
    height = terrain_compose_constraints(height, constraints[6:], world_x, world_z)
    material *= 1 - infrastructure_weight
    return
}

default_generated_height_filtered :: proc(
    plans: ^[len(DEFAULT_ISLAND_SIGNS)]islands.Plan,
    world_x, world_z, half_extent, cell_size: f32,
    hydrologies: ^[len(DEFAULT_ISLAND_SIGNS)]Default_Island_Hydrology = nil,
) -> (
    height, material: f32,
) {
    center, distance, center_material := default_generated_height(plans, world_x, world_z, half_extent, hydrologies)
    shoreline_filter := math.abs(distance) <= cell_size * 1.75 + 4
    dune_filter := distance < 0 && distance > -(DEFAULT_DUNE_MAX_WIDTH + cell_size * 1.75)
    if !shoreline_filter && !dune_filter do return center, center_material
    if cell_size <= 1 {
        if !dune_filter do return center, center_material
        // Keep one-metre ridge geometry intact, but prefilter its stabilization
        // color. At a player-height grazing angle a single nearby terrain
        // triangle can span much of the screen; abrupt per-vertex material
        // differences then reveal the triangulation as giant wedges.
        // The nearest grid is one metre, but at a low grazing angle each
        // triangle can still span dozens of pixels. Average stabilization
        // across a three-metre footprint while leaving ridge height untouched;
        // this removes checkerboard palette changes without blurring the dune
        // silhouette or connected blowout geometry.
        offset := f32(1.5)
        _, _, material_a := default_generated_height(
            plans,
            world_x - offset,
            world_z - offset,
            half_extent,
            hydrologies,
        )
        _, _, material_b := default_generated_height(
            plans,
            world_x + offset,
            world_z - offset,
            half_extent,
            hydrologies,
        )
        _, _, material_c := default_generated_height(
            plans,
            world_x - offset,
            world_z + offset,
            half_extent,
            hydrologies,
        )
        _, _, material_d := default_generated_height(
            plans,
            world_x + offset,
            world_z + offset,
            half_extent,
            hydrologies,
        )
        return center, center_material * .5 + (material_a + material_b + material_c + material_d) * .125
    }
    offset := cell_size * .35
    a, _, material_a := default_generated_height(plans, world_x - offset, world_z - offset, half_extent, hydrologies)
    b, _, material_b := default_generated_height(plans, world_x + offset, world_z - offset, half_extent, hydrologies)
    c, _, material_c := default_generated_height(plans, world_x - offset, world_z + offset, half_extent, hydrologies)
    d, _, material_d := default_generated_height(plans, world_x + offset, world_z + offset, half_extent, hydrologies)
    return center * .4 + (a + b + c + d) * .15,
        center_material * .4 + (material_a + material_b + material_c + material_d) * .15
}

@(no_instrumentation)
level_contains :: #force_inline proc(data: ^Clipmap_Level, x, z: f32) -> bool {
    if data == nil do return false
    extent := f32(TERRAIN_RESOLUTION - 1) * data.cell_size
    return x >= data.origin_x && x <= data.origin_x + extent && z >= data.origin_z && z <= data.origin_z + extent
}

level_contains_bounds :: proc(data: ^Clipmap_Level, min_x, min_z, max_x, max_z: f32) -> bool {
    return level_contains(data, min_x, min_z) && level_contains(data, max_x, max_z)
}

@(no_instrumentation)
level_sample_bounds :: #force_inline proc(
    data: ^Clipmap_Level,
    min_x, min_z, max_x, max_z: f32,
) -> (
    min_sample_x, min_sample_z, max_sample_x, max_sample_z: int,
    overlaps: bool,
) {
    if data == nil do return
    extent := f32(TERRAIN_RESOLUTION - 1) * data.cell_size
    if max_x < data.origin_x ||
       max_z < data.origin_z ||
       min_x > data.origin_x + extent ||
       min_z > data.origin_z + extent {
        return
    }
    min_sample_x = clamp(int(math.floor(f64((min_x - data.origin_x) / data.cell_size))), 0, TERRAIN_RESOLUTION - 1)
    min_sample_z = clamp(int(math.floor(f64((min_z - data.origin_z) / data.cell_size))), 0, TERRAIN_RESOLUTION - 1)
    max_sample_x = clamp(int(math.ceil(f64((max_x - data.origin_x) / data.cell_size))), 0, TERRAIN_RESOLUTION - 1)
    max_sample_z = clamp(int(math.ceil(f64((max_z - data.origin_z) / data.cell_size))), 0, TERRAIN_RESOLUTION - 1)
    overlaps = true
    return
}

@(no_instrumentation)
sample_level_height :: #force_inline proc(data: ^Clipmap_Level, x, z: f32) -> f32 {
    if data == nil || !level_contains(data, x, z) do return 0
    grid_x := (x - data.origin_x) / data.cell_size
    grid_z := (z - data.origin_z) / data.cell_size
    x0 := clamp(int(math.floor(f64(grid_x))), 0, TERRAIN_RESOLUTION - 1)
    z0 := clamp(int(math.floor(f64(grid_z))), 0, TERRAIN_RESOLUTION - 1)
    x1 := min(x0 + 1, TERRAIN_RESOLUTION - 1)
    z1 := min(z0 + 1, TERRAIN_RESOLUTION - 1)
    tx := clamp(grid_x - f32(x0), 0, 1)
    tz := clamp(grid_z - f32(z0), 0, 1)
    a := data.heights[sample_index(x0, z0)] * (1 - tx) + data.heights[sample_index(x1, z0)] * tx
    b := data.heights[sample_index(x0, z1)] * (1 - tx) + data.heights[sample_index(x1, z1)] * tx
    return a * (1 - tz) + b * tz
}

@(no_instrumentation)
sample_level_material :: #force_inline proc(data: ^Clipmap_Level, x, z: f32) -> f32 {
    if data == nil || !level_contains(data, x, z) do return 0
    grid_x := clamp(int(math.round(f64((x - data.origin_x) / data.cell_size))), 0, TERRAIN_RESOLUTION - 1)
    grid_z := clamp(int(math.round(f64((z - data.origin_z) / data.cell_size))), 0, TERRAIN_RESOLUTION - 1)
    return data.material[sample_index(grid_x, grid_z)]
}

// Rendering needs the continuous ecological field rather than the nearest
// discrete gameplay cell. Bilinear material sampling prevents half-metre
// clipmap vertices from repeating one-metre values in square blocks whose
// triangle interpolation reads as large diamonds at grazing camera angles.
// Keep sample_level_material nearest-neighbor for surface classification and
// editor behavior, where stable cell ownership is intentional.
@(no_instrumentation)
sample_level_render_material :: #force_inline proc(data: ^Clipmap_Level, x, z: f32) -> f32 {
    if data == nil || !level_contains(data, x, z) do return 0
    grid_x := (x - data.origin_x) / data.cell_size
    grid_z := (z - data.origin_z) / data.cell_size
    x0 := clamp(int(math.floor(f64(grid_x))), 0, TERRAIN_RESOLUTION - 1)
    z0 := clamp(int(math.floor(f64(grid_z))), 0, TERRAIN_RESOLUTION - 1)
    x1 := min(x0 + 1, TERRAIN_RESOLUTION - 1)
    z1 := min(z0 + 1, TERRAIN_RESOLUTION - 1)
    tx := clamp(grid_x - f32(x0), 0, 1)
    tz := clamp(grid_z - f32(z0), 0, 1)
    a := data.material[sample_index(x0, z0)] * (1 - tx) + data.material[sample_index(x1, z0)] * tx
    b := data.material[sample_index(x0, z1)] * (1 - tx) + data.material[sample_index(x1, z1)] * tx
    return a * (1 - tz) + b * tz
}

// Sampling starts at the requested level and falls back outward through the
// coarser nested grids when a coordinate is outside a fine level.
@(no_instrumentation)
sample_height :: #force_inline proc(project: ^Project, level: int, x, z: f32) -> f32 {
    if project == nil || level < 0 || level >= CLIPMAP_LEVELS do return 0
    for candidate in level ..< CLIPMAP_LEVELS {
        data := &project.levels[candidate]
        if !level_contains(data, x, z) do continue
        return sample_level_height(data, x, z)
    }
    return 0
}

// Blend a rendered fine-grid vertex onto the next coarser surface near the
// outside of its clipmap patch. At weight 1 the fine edge follows the coarse
// grid's bilinear surface exactly, eliminating the T-junction crack between
// the fine edge's intermediate vertices and the coarse ring.
@(no_instrumentation)
sample_clipmap_transition_height :: #force_inline proc(project: ^Project, level: int, x, z, weight: f32) -> f32 {
    fine := sample_height(project, level, x, z)
    if project == nil || level < 0 || level >= CLIPMAP_LEVELS - 1 || weight <= 0 do return fine
    coarse := sample_height(project, level + 1, x, z)
    blend := clamp(weight, 0, 1)
    return fine + (coarse - fine) * blend
}

@(no_instrumentation)
sample_material :: #force_inline proc(project: ^Project, level: int, x, z: f32) -> f32 {
    if project == nil || level < 0 || level >= CLIPMAP_LEVELS do return 0
    for candidate in level ..< CLIPMAP_LEVELS {
        data := &project.levels[candidate]
        if !level_contains(data, x, z) do continue
        return sample_level_material(data, x, z)
    }
    return 0
}

@(no_instrumentation)
sample_render_material :: #force_inline proc(project: ^Project, level: int, x, z: f32) -> f32 {
    if project == nil || level < 0 || level >= CLIPMAP_LEVELS do return 0
    for candidate in level ..< CLIPMAP_LEVELS {
        data := &project.levels[candidate]
        if !level_contains(data, x, z) do continue
        return sample_level_render_material(data, x, z)
    }
    return 0
}

// Ground_Surface is the discrete, drivable ground classification derived from
// the painted material channel and elevation. The heightfield stores only a
// continuous painted scalar, so this enum names the visible bands that
// consumers (surface particles, driving grip) can switch on. The set mirrors
// the bands the terrain renderer paints in terrain_color: painted soil, the
// low-elevation sand shelf, and the high-elevation grass.
Ground_Surface :: enum u8 {
    Sand,
    Dirt,
    Grass,
}

// classify_ground turns a raw material/height sample into the dominant visible
// ground band. Thresholds intentionally mirror the renderer's terrain_color so
// that effects keyed off this classifier match what the player sees:
//   - painted material above .5 reads as bare soil (Dirt),
//   - otherwise the sand->soil blend below .9m of elevation resolves to Sand
//     while its soil-dominated upper half resolves to Dirt,
//   - the soil->grass blend above .9m resolves to Grass once grass dominates.
// Ground at or below sea level is shoreline; it classifies as Sand because
// vehicles only ever contact the beach edge there, never open water.
@(no_instrumentation)
classify_ground :: #force_inline proc(material, height, sea_level: f32) -> Ground_Surface {
    if height <= sea_level do return .Sand
    if material < 0 {
        stabilization := clamp(material + 1, f32(0), f32(1))
        if stabilization < .74 do return .Sand
        elevation := height - sea_level
        return elevation >= 2.45 ? .Grass : .Dirt
    }
    if material > .5 do return .Dirt
    elevation := height - sea_level
    if elevation < .9 {
        return (elevation - .18) / .72 < .5 ? .Sand : .Dirt
    }
    return (elevation - .9) / 3.1 >= .5 ? .Grass : .Dirt
}

// ground_surface_at samples the classified ground under a world position. It is
// the sampling counterpart to classify_ground for callers that hold a project.
@(no_instrumentation)
ground_surface_at :: #force_inline proc(project: ^Project, level: int, x, z: f32) -> Ground_Surface {
    if project == nil do return .Grass
    return classify_ground(
        sample_material(project, level, x, z),
        sample_height(project, level, x, z),
        project.sea_level,
    )
}

// Coastal pioneer grasses establish before stabilized sand has blended far
// enough toward inland soil to classify as ordinary Grass. This predicate is
// deliberately narrower than general vegetation eligibility: it excludes wet
// beach and low active sand while exposing the transitional band to the
// renderer's deterministic density mask.
supports_coastal_grass :: #force_inline proc(material, height, sea_level: f32) -> bool {
    if classify_ground(material, height, sea_level) == .Grass do return true
    if material >= 0 || height < sea_level + .95 do return false
    stabilization := clamp(material + 1, f32(0), f32(1))
    return stabilization >= .42
}

// ground_grip keeps terrain-material handling policy beside the same bands the
// renderer and classifier use. Road grip still wins whenever a road hit exists.
ground_grip :: proc(surface: Ground_Surface) -> roads.Grip_Profile {
    switch surface {
    case .Sand:
        return {longitudinal = .48, lateral = .40, rolling_resistance = 1.55}
    case .Dirt:
        return roads.pavement_grip(.Dirt)
    case .Grass:
        return roads.offroad_grip()
    }
    return roads.offroad_grip()
}

refresh_derived_overlaps :: proc(project: ^Project) {
    if project == nil do return
    for level in 1 ..< CLIPMAP_LEVELS {
        finer := &project.levels[level - 1]
        coarse := &project.levels[level]
        for z in 0 ..< TERRAIN_RESOLUTION {
            sample_z := coarse.origin_z + f32(z) * coarse.cell_size
            for x in 0 ..< TERRAIN_RESOLUTION {
                sample_x := coarse.origin_x + f32(x) * coarse.cell_size
                if !level_contains(finer, sample_x, sample_z) do continue
                index := sample_index(x, z)
                coarse.heights[index] = sample_level_height(finer, sample_x, sample_z)
                coarse.material[index] = sample_level_material(finer, sample_x, sample_z)
            }
        }
    }
}

// apply_stroke keeps the original soft brush behavior for callers that do not
// need to expose falloff tuning. The editor uses apply_stroke_with_hardness.
apply_stroke :: proc(project: ^Project, tool: Tool, world_x, world_z, radius, strength, direction: f32) {
    apply_stroke_with_hardness(project, tool, world_x, world_z, radius, strength, direction, .5)
}

apply_stroke_with_hardness :: proc(
    project: ^Project,
    tool: Tool,
    world_x, world_z, radius, strength, direction, hardness: f32,
) {
    if project == nil || radius <= 0 || strength <= 0 do return
    falloff_exponent := 1 + (1 - clamp(hardness, 0, 1)) * 2
    authored_level := CLIPMAP_LEVELS - 1
    for level in 0 ..< CLIPMAP_LEVELS {
        if level_contains_bounds(
            &project.levels[level],
            world_x - radius,
            world_z - radius,
            world_x + radius,
            world_z + radius,
        ) {
            authored_level = level
            break
        }
    }
    data := &project.levels[authored_level]
    effective_radius := max(radius, data.cell_size * 1.5)
    min_x, min_z, max_x, max_z, _ := level_sample_bounds(
        data,
        world_x - effective_radius,
        world_z - effective_radius,
        world_x + effective_radius,
        world_z + effective_radius,
    )
    for z in min_z ..= max_z {
        for x in min_x ..= max_x {
            world_sample_x := data.origin_x + f32(x) * data.cell_size
            world_sample_z := data.origin_z + f32(z) * data.cell_size
            dx, dz := world_sample_x - world_x, world_sample_z - world_z
            distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
            if distance > effective_radius do continue
            falloff := f32(math.pow(f64(1 - distance / effective_radius), f64(falloff_exponent)))
            index := sample_index(x, z)
            switch tool {
            case .Raise:
                data.heights[index] += direction * strength * falloff
            case .Paint:
                data.material[index] = clamp(data.material[index] + direction * strength * falloff, 0, 1)
            case .Smooth:
                left := data.heights[sample_index(max(x - 1, 0), z)]
                right := data.heights[sample_index(min(x + 1, TERRAIN_RESOLUTION - 1), z)]
                up := data.heights[sample_index(x, max(z - 1, 0))]
                down := data.heights[sample_index(x, min(z + 1, TERRAIN_RESOLUTION - 1))]
                average := (left + right + up + down) * .25
                data.heights[index] += (average - data.heights[index]) * clamp(strength * falloff, 0, 1)
            case .Structure:
            }
        }
    }
    // A stroke may be authored at a coarser level when its bounds cross the
    // edge of a finer resident level. Refresh the affected finer overlap from
    // that authored source as well; otherwise the renderer exposes a square
    // stale-height seam wherever its nested clipmap changes LOD.
    for level in 0 ..< authored_level {
        finer := &project.levels[level]
        propagation_radius := effective_radius + data.cell_size * 2
        fine_min_x, fine_min_z, fine_max_x, fine_max_z, overlaps := level_sample_bounds(
            finer,
            world_x - propagation_radius,
            world_z - propagation_radius,
            world_x + propagation_radius,
            world_z + propagation_radius,
        )
        if !overlaps do continue
        for z in fine_min_z ..= fine_max_z {
            sample_z := finer.origin_z + f32(z) * finer.cell_size
            for x in fine_min_x ..= fine_max_x {
                sample_x := finer.origin_x + f32(x) * finer.cell_size
                dx, dz := sample_x - world_x, sample_z - world_z
                if dx * dx + dz * dz > effective_radius * effective_radius ||
                   !level_contains(data, sample_x, sample_z) {
                    continue
                }
                index := sample_index(x, z)
                finer.heights[index] = sample_level_height(data, sample_x, sample_z)
                finer.material[index] = sample_level_material(data, sample_x, sample_z)
            }
        }
    }
    // Coarser overlaps are derived data. Cascading one level at a time keeps
    // height and material samples identical wherever sampling changes LOD.
    for level in authored_level + 1 ..< CLIPMAP_LEVELS {
        finer := &project.levels[level - 1]
        coarse := &project.levels[level]
        propagation_radius := effective_radius + finer.cell_size * 2
        coarse_min_x, coarse_min_z, coarse_max_x, coarse_max_z, overlaps := level_sample_bounds(
            coarse,
            world_x - propagation_radius,
            world_z - propagation_radius,
            world_x + propagation_radius,
            world_z + propagation_radius,
        )
        if !overlaps do continue
        for z in coarse_min_z ..= coarse_max_z {
            sample_z := coarse.origin_z + f32(z) * coarse.cell_size
            for x in coarse_min_x ..= coarse_max_x {
                sample_x := coarse.origin_x + f32(x) * coarse.cell_size
                if !level_contains(finer, sample_x, sample_z) do continue
                index := sample_index(x, z)
                coarse.heights[index] = sample_level_height(finer, sample_x, sample_z)
                coarse.material[index] = sample_level_material(finer, sample_x, sample_z)
            }
        }
    }
    if tool == .Raise || tool == .Smooth {
        for index in 0 ..< project.structure_count {
            structure := &project.structures[index]
            dx, dz := structure.center_x - world_x, structure.center_z - world_z
            if dx * dx + dz * dz > effective_radius * effective_radius do continue
            structure.base_y = sample_height(project, 0, structure.center_x, structure.center_z)
        }
    }
    project.revision += 1
}
