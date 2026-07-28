package terrain

import buildings "../buildings"
import roads "../roads"
import "base:runtime"
import "core:math"
import "core:os"

// The sixth, 32 m level keeps the full authored archipelago resident when the
// camera is near either island. Five levels only covered about 2 km from the
// camera, so the opposite island disappeared well before the 12 km far plane.
CLIPMAP_LEVELS :: 6
WORLD_SIZE_METERS :: 4000.0
RING_RESOLUTION :: 256
SAMPLES_PER_LEVEL :: RING_RESOLUTION * RING_RESOLUTION
BASE_CELL_SIZE :: WORLD_SIZE_METERS / f32(RING_RESOLUTION - 1)
FINE_CELL_SIZE :: f32(1.0)

// These are expressed as a fraction of the authored world's half extent. Every
// clipmap level samples the same world-space features at a different density.
DEFAULT_ISLAND_OFFSET :: 0.65
DEFAULT_ISLAND_RADIUS :: 0.14
DEFAULT_ISLAND_HEIGHT :: 4.5
DEFAULT_ISLAND_SIGNS :: [2]f32{-1, 1}
// 450 m gives the Postale enough field for a representative utility-STOL
// takeoff or landing while still demanding disciplined threshold use.
DEFAULT_RUNWAY_HALF_LENGTH :: 0.1125
DEFAULT_RUNWAY_HALF_WIDTH :: 0.012
DEFAULT_RUNWAY_SPAWN_OFFSET :: 0.06
DEFAULT_RUNWAY_SHOULDER :: f32(48)
DEFAULT_RUNWAY_TERRAIN_FEATHER :: f32(32)
DEFAULT_TOWN_OFFSET :: 118.0
DEFAULT_TOWN_HILL_HEIGHT :: 5.5
DEFAULT_TOWN_HILL_RADIUS_X :: 145.0
DEFAULT_TOWN_HILL_RADIUS_Z :: 65.0

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
}

LEGACY_STRUCTURE_CAPACITY :: 256
CITY_DENSITY_SAMPLES :: SAMPLES_PER_LEVEL
PROJECT_FILE_MAGIC :: [8]u8{'A', 'D', 'R', 'T', 'E', 'R', 'R', '6'}
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
    levels:                [CLIPMAP_LEVELS]Clipmap_Level,
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
    levels:                [CLIPMAP_LEVELS]Clipmap_Level,
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

project_migrate_v4 :: proc(project: ^Project, legacy: ^Project_V4) -> bool {
    if project == nil ||
       legacy == nil ||
       legacy.structure_count < 0 ||
       legacy.structure_count > LEGACY_STRUCTURE_CAPACITY {
        return false
    }
    loaded := new(Project)
    defer free(loaded)
    loaded.levels = legacy.levels
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

project_migrate_v5 :: proc(project: ^Project, payload: ^Project_File_Payload, structure_data: []byte) -> bool {
    if project == nil || payload == nil do return false
    structure_count := int(payload.structure_count)
    if structure_count < 0 ||
       structure_count > len(structure_data) / size_of(Structure_V5) ||
       structure_count * size_of(Structure_V5) != len(structure_data) {
        return false
    }
    loaded := new(Project)
    defer free(loaded)
    loaded.levels = payload.levels
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

project_migrate_v3 :: proc(project: ^Project, legacy: ^Project_V3) -> bool {
    if project == nil || legacy == nil do return false
    if legacy.structure_count < 0 || legacy.structure_count > LEGACY_STRUCTURE_CAPACITY do return false
    loaded := new(Project)
    defer free(loaded)
    loaded.levels = legacy.levels
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
    if project_file_magic_is(header, PROJECT_FILE_MAGIC_V5) {
        if header.payload_size != u64(len(data) - header_size) ||
           len(data) < header_size + size_of(Project_File_Payload) {
            return false
        }
        payload := cast(^Project_File_Payload)raw_data(data[header_size:])
        structure_data := data[header_size + size_of(Project_File_Payload):]
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

add_default_runways :: proc(project: ^Project) -> bool {
    if project == nil ||
       project.road_graph.node_count + len(DEFAULT_ISLAND_SIGNS) * 2 > roads.MAX_NODES ||
       project.road_graph.edge_count + len(DEFAULT_ISLAND_SIGNS) > roads.MAX_EDGES {
        return false
    }
    half_extent := f32(WORLD_SIZE_METERS * .5)
    runway_half_length := half_extent * DEFAULT_RUNWAY_HALF_LENGTH
    runway_width := half_extent * DEFAULT_RUNWAY_HALF_WIDTH * 2
    for sign in DEFAULT_ISLAND_SIGNS {
        center := sign * half_extent * DEFAULT_ISLAND_OFFSET
        runway_height := sample_height(project, 0, center, center)
        from := roads.add_node(&project.road_graph, {center - runway_half_length, runway_height, center}, 0)
        to := roads.add_node(&project.road_graph, {center + runway_half_length, runway_height, center}, 0)
        if from < 0 ||
           to < 0 ||
           roads.add_straight_edge(&project.road_graph, from, to, runway_width, 2, .Asphalt) < 0 {
            return false
        }
    }
    return true
}

init_project :: proc(result: ^Project) {
    if result == nil do return
    delete(result.structures)
    result^ = {}
    result.sea_level = 0
    result.revision = 1
    result.next_structure_id = 1
    authored_half_extent := f32(WORLD_SIZE_METERS * .5)
    gameplay_center := authored_half_extent * DEFAULT_ISLAND_OFFSET
    for level in 0 ..< CLIPMAP_LEVELS {
        data := &result.levels[level]
        data.cell_size = FINE_CELL_SIZE * f32(math.pow(2, f64(level)))
        level_center_x, level_center_z := gameplay_center, gameplay_center
        if level == 0 do level_center_x += authored_half_extent * DEFAULT_RUNWAY_SPAWN_OFFSET
        if level == CLIPMAP_LEVELS - 1 {
            level_center_x, level_center_z = 0, 0
        }
        half_grid := f32(RING_RESOLUTION - 1) * .5 * data.cell_size
        data.origin_x = level_center_x - half_grid
        data.origin_z = level_center_z - half_grid
        for z in 0 ..< RING_RESOLUTION {
            for x in 0 ..< RING_RESOLUTION {
                world_x := data.origin_x + f32(x) * data.cell_size
                world_z := data.origin_z + f32(z) * data.cell_size
                data.heights[sample_index(x, z)] = default_height(world_x, world_z, authored_half_extent)
            }
        }
    }
    _ = add_default_runways(result)
    refresh_derived_overlaps(result)
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
        width = max(width, BASE_CELL_SIZE),
        depth = max(depth, BASE_CELL_SIZE),
        base_y = base_y,
        height = max(height, BASE_CELL_SIZE),
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
sample_index :: #force_inline proc(x, z: int) -> int { return z * RING_RESOLUTION + x }

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
    feather:  f32,
    target:   f32,
}

terrain_smooth_weight :: proc(value: f32) -> f32 {
    t := clamp(value, 0, 1)
    return t * t * (3 - 2 * t)
}

terrain_constraint_weight :: proc(constraint: Terrain_Constraint, world_x, world_z: f32) -> f32 {
    if constraint.half_x <= 0 || constraint.half_z <= 0 do return 0
    dx := math.abs(world_x - constraint.center_x)
    dz := math.abs(world_z - constraint.center_z)
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

default_terrain_constraints :: proc(half_extent: f32) -> [6]Terrain_Constraint {
    constraints: [6]Terrain_Constraint
    island_radius := half_extent * DEFAULT_ISLAND_RADIUS
    runway_half_length := half_extent * DEFAULT_RUNWAY_HALF_LENGTH
    runway_half_width := half_extent * DEFAULT_RUNWAY_HALF_WIDTH
    for sign, island_index in DEFAULT_ISLAND_SIGNS {
        center := sign * half_extent * DEFAULT_ISLAND_OFFSET
        constraints[island_index] = {
            mode     = .Set,
            shape    = .Ellipse,
            curve    = .Smooth,
            priority = 0,
            center_x = center,
            center_z = center,
            half_x   = island_radius,
            half_z   = island_radius,
            feather  = island_radius * .34,
            target   = DEFAULT_ISLAND_HEIGHT,
        }
        constraints[2 + island_index] = {
            mode     = .Add,
            shape    = .Ellipse,
            curve    = .Quadratic,
            priority = 10,
            center_x = center + sign * 25,
            center_z = center + sign * DEFAULT_TOWN_OFFSET,
            half_x   = DEFAULT_TOWN_HILL_RADIUS_X,
            half_z   = DEFAULT_TOWN_HILL_RADIUS_Z,
            target   = DEFAULT_TOWN_HILL_HEIGHT,
        }
        constraints[4 + island_index] = {
            mode     = .Set,
            shape    = .Rectangle,
            curve    = .Smooth,
            priority = 20,
            center_x = center,
            center_z = center,
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
    return terrain_compose_constraints(0, constraints[:], world_x, world_z)
}

@(no_instrumentation)
level_contains :: #force_inline proc(data: ^Clipmap_Level, x, z: f32) -> bool {
    if data == nil do return false
    extent := f32(RING_RESOLUTION - 1) * data.cell_size
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
    extent := f32(RING_RESOLUTION - 1) * data.cell_size
    if max_x < data.origin_x ||
       max_z < data.origin_z ||
       min_x > data.origin_x + extent ||
       min_z > data.origin_z + extent {
        return
    }
    min_sample_x = clamp(int(math.floor(f64((min_x - data.origin_x) / data.cell_size))), 0, RING_RESOLUTION - 1)
    min_sample_z = clamp(int(math.floor(f64((min_z - data.origin_z) / data.cell_size))), 0, RING_RESOLUTION - 1)
    max_sample_x = clamp(int(math.ceil(f64((max_x - data.origin_x) / data.cell_size))), 0, RING_RESOLUTION - 1)
    max_sample_z = clamp(int(math.ceil(f64((max_z - data.origin_z) / data.cell_size))), 0, RING_RESOLUTION - 1)
    overlaps = true
    return
}

@(no_instrumentation)
sample_level_height :: #force_inline proc(data: ^Clipmap_Level, x, z: f32) -> f32 {
    if data == nil || !level_contains(data, x, z) do return 0
    grid_x := (x - data.origin_x) / data.cell_size
    grid_z := (z - data.origin_z) / data.cell_size
    x0 := clamp(int(math.floor(f64(grid_x))), 0, RING_RESOLUTION - 1)
    z0 := clamp(int(math.floor(f64(grid_z))), 0, RING_RESOLUTION - 1)
    x1 := min(x0 + 1, RING_RESOLUTION - 1)
    z1 := min(z0 + 1, RING_RESOLUTION - 1)
    tx := clamp(grid_x - f32(x0), 0, 1)
    tz := clamp(grid_z - f32(z0), 0, 1)
    a := data.heights[sample_index(x0, z0)] * (1 - tx) + data.heights[sample_index(x1, z0)] * tx
    b := data.heights[sample_index(x0, z1)] * (1 - tx) + data.heights[sample_index(x1, z1)] * tx
    return a * (1 - tz) + b * tz
}

@(no_instrumentation)
sample_level_material :: #force_inline proc(data: ^Clipmap_Level, x, z: f32) -> f32 {
    if data == nil || !level_contains(data, x, z) do return 0
    grid_x := clamp(int(math.round(f64((x - data.origin_x) / data.cell_size))), 0, RING_RESOLUTION - 1)
    grid_z := clamp(int(math.round(f64((z - data.origin_z) / data.cell_size))), 0, RING_RESOLUTION - 1)
    return data.material[sample_index(grid_x, grid_z)]
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
        for z in 0 ..< RING_RESOLUTION {
            sample_z := coarse.origin_z + f32(z) * coarse.cell_size
            for x in 0 ..< RING_RESOLUTION {
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
                right := data.heights[sample_index(min(x + 1, RING_RESOLUTION - 1), z)]
                up := data.heights[sample_index(x, max(z - 1, 0))]
                down := data.heights[sample_index(x, min(z + 1, RING_RESOLUTION - 1))]
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
