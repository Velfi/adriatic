package terrain

import roads "../roads"
import "base:runtime"
import "core:math"
import "core:os"

CLIPMAP_LEVELS :: 5
WORLD_SIZE_METERS :: 4000.0
RING_RESOLUTION :: 256
SAMPLES_PER_LEVEL :: RING_RESOLUTION * RING_RESOLUTION
BASE_CELL_SIZE :: WORLD_SIZE_METERS / f32(RING_RESOLUTION - 1)

// These are expressed as a fraction of the authored world's half extent. Every
// clipmap level samples the same world-space features at a different density.
DEFAULT_ISLAND_OFFSET :: 0.65
DEFAULT_ISLAND_RADIUS :: 0.14
DEFAULT_ISLAND_HEIGHT :: 4.5
DEFAULT_ISLAND_SIGNS :: [2]f32{-1, 1}
DEFAULT_RUNWAY_HALF_LENGTH :: 0.10
DEFAULT_RUNWAY_HALF_WIDTH :: 0.012
DEFAULT_RUNWAY_SPAWN_OFFSET :: 0.06
DEFAULT_PIER_INNER_OFFSET :: 0.10

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
    Architecture,
}

STRUCTURE_CAPACITY :: 256
PROJECT_FILE_VERSION :: u32(4)
PROJECT_FILE_MAGIC :: [8]u8{'A', 'D', 'R', 'T', 'E', 'R', 'R', '1'}

Project_File_Header :: struct {
    magic:        [8]u8,
    version:      u32,
    payload_size: u64,
}

Structure :: struct {
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

Clipmap_Level :: struct {
    cell_size: f32,
    heights:   [SAMPLES_PER_LEVEL]f32,
    material:  [SAMPLES_PER_LEVEL]f32,
}

Project :: struct {
    levels:            [CLIPMAP_LEVELS]Clipmap_Level,
    sea_level:         f32,
    revision:          u64,
    structures:        [STRUCTURE_CAPACITY]Structure,
    structure_count:   int,
    next_structure_id: u64,
    road_graph:        roads.Graph,
}

project_file_header_valid :: proc(header: ^Project_File_Header) -> bool {
    if header == nil || header.version != PROJECT_FILE_VERSION || header.payload_size != size_of(Project) do return false
    magic := PROJECT_FILE_MAGIC
    for index in 0 ..< len(PROJECT_FILE_MAGIC) {
        if header.magic[index] != magic[index] do return false
    }
    return true
}

save_project :: proc(project: ^Project, filename: string) -> bool {
    if project == nil || filename == "" do return false
    header_size := size_of(Project_File_Header)
    data := make([]byte, header_size + size_of(Project))
    defer delete(data)
    header := cast(^Project_File_Header)raw_data(data)
    header^ = {
        magic        = PROJECT_FILE_MAGIC,
        version      = PROJECT_FILE_VERSION,
        payload_size = size_of(Project),
    }
    runtime.mem_copy_non_overlapping(raw_data(data[header_size:]), cast(rawptr)project, size_of(Project))
    return os.write_entire_file(filename, data) == nil
}

load_project :: proc(project: ^Project, filename: string) -> bool {
    if project == nil || filename == "" do return false
    data, err := os.read_entire_file_from_path(filename, context.allocator)
    if err != nil do return false
    defer delete(data)
    header_size := size_of(Project_File_Header)
    if len(data) < header_size + size_of(Project) do return false
    header := cast(^Project_File_Header)raw_data(data)
    if !project_file_header_valid(header) do return false
    runtime.mem_copy_non_overlapping(cast(rawptr)project, raw_data(data[header_size:]), size_of(Project))
    return true
}

init_project :: proc(result: ^Project) {
    if result == nil do return
    result^ = {}
    result.sea_level = 0
    result.revision = 1
    result.next_structure_id = 1
    authored_half_extent := f32(WORLD_SIZE_METERS * .5)
    for level in 0 ..< CLIPMAP_LEVELS {
        data := &result.levels[level]
        data.cell_size = BASE_CELL_SIZE * f32(math.pow(2, f64(level)))
        for z in 0 ..< RING_RESOLUTION {
            for x in 0 ..< RING_RESOLUTION {
                world_x := (f32(x) - f32(RING_RESOLUTION - 1) * .5) * data.cell_size
                world_z := (f32(z) - f32(RING_RESOLUTION - 1) * .5) * data.cell_size
                data.heights[sample_index(x, z)] = default_height(world_x, world_z, authored_half_extent)
            }
        }
    }
}

snap_to_grid :: proc(value, grid: f32) -> f32 {
    if grid <= 0 do return value
    return f32(math.round(f64(value / grid))) * grid
}

structure_default_color :: proc() -> [4]u8 {
    return {112, 169, 181, 220}
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

add_structure :: proc(project: ^Project, structure: Structure) -> int {
    if project == nil || project.structure_count >= STRUCTURE_CAPACITY do return -1
    value := structure
    value.id = project.next_structure_id
    project.next_structure_id += 1
    if value.group_id == 0 do value.group_id = value.id
    value.seed = u32(value.id * 747796405)
    project.structures[project.structure_count] = value
    index := project.structure_count
    project.structure_count += 1
    project.revision += 1
    return index
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

sample_index :: proc(x, z: int) -> int { return z * RING_RESOLUTION + x }

default_height :: proc(world_x, world_z, half_extent: f32) -> f32 {
    radius := half_extent * DEFAULT_ISLAND_RADIUS
    for sign in DEFAULT_ISLAND_SIGNS {
        center_x := sign * half_extent * DEFAULT_ISLAND_OFFSET
        center_z := sign * half_extent * DEFAULT_ISLAND_OFFSET
        dx, dz := world_x - center_x, world_z - center_z
        distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
        if distance < radius {
            // A broad, flat top leaves enough usable land for the runway while
            // the outer third falls cleanly into the sea.
            falloff := clamp((radius - distance) / (radius * .34), 0, 1)
            return DEFAULT_ISLAND_HEIGHT * (.58 + falloff * .42)
        }
    }
    return 0
}

// sample_height returns a bilinear local sample. The MVP keeps an editable
// window per hierarchy level; world-space ring snapping keeps that window
// centered beneath the author while the ocean remains unbounded.
sample_height :: proc(project: ^Project, level: int, x, z: f32) -> f32 {
    if project == nil || level < 0 || level >= CLIPMAP_LEVELS do return 0
    data := &project.levels[level]
    grid_x := x / data.cell_size + f32(RING_RESOLUTION - 1) * .5
    grid_z := z / data.cell_size + f32(RING_RESOLUTION - 1) * .5
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

sample_material :: proc(project: ^Project, level: int, x, z: f32) -> f32 {
    if project == nil || level < 0 || level >= CLIPMAP_LEVELS do return 0
    data := &project.levels[level]
    grid_x := clamp(int(math.round(f64(x / data.cell_size + f32(RING_RESOLUTION - 1) * .5))), 0, RING_RESOLUTION - 1)
    grid_z := clamp(int(math.round(f64(z / data.cell_size + f32(RING_RESOLUTION - 1) * .5))), 0, RING_RESOLUTION - 1)
    return data.material[sample_index(grid_x, grid_z)]
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
    for level in 0 ..< CLIPMAP_LEVELS {
        data := &project.levels[level]
        // Coarse levels receive a footprint no smaller than their sampling cell so
        // an authoring stroke remains represented at every clipmap resolution.
        effective_radius := max(radius, data.cell_size * 1.5)
        for z in 0 ..< RING_RESOLUTION {
            for x in 0 ..< RING_RESOLUTION {
                world_sample_x := (f32(x) - f32(RING_RESOLUTION - 1) * .5) * data.cell_size
                world_sample_z := (f32(z) - f32(RING_RESOLUTION - 1) * .5) * data.cell_size
                dx, dz := world_sample_x - world_x, world_sample_z - world_z
                distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
                if distance > effective_radius do continue
                falloff := f32(math.pow(f64(1 - distance / effective_radius), f64(falloff_exponent)))
                index := sample_index(x, z)
                switch tool {
                case .Raise:
                    data.heights[index] += direction * strength * falloff * data.cell_size
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
                // Structure authoring is handled by the editor and never mutates
                // the heightfield.
                }
            }
        }
    }
    project.revision += 1
}
