package main

import harbor "../packages/harbor"
import hs "../packages/hs"
import marina "../packages/marina"
import story "../packages/story"
import terrain "../packages/terrain"
import "core:hash"
import "core:math"
import "core:mem"
import "core:os"

MAP_ARTIFACT_MAGIC :: [8]byte{'A', 'D', 'R', 'M', 'A', 'P', 0, 0}
MAP_ARTIFACT_CONTAINER_VERSION :: u16(1)
MAP_ARTIFACT_FORMAT_VERSION :: u32(1)
// Bump whenever procedural output changes in a way that requires shipped maps
// to be rebuilt. This is deliberately independent of Fixture schema versions.
MAP_ARTIFACT_GENERATOR_VERSION :: u64(1)
MAP_ARTIFACT_HEADER_SIZE :: 40
MAP_ARTIFACT_MAX_PAYLOAD :: 64 * 1024 * 1024
DEFAULT_MAP_ARTIFACT_PATH :: "assets/maps/default.adriatic-map"
EDITOR_MAP_ARTIFACT_PATH :: "adriatic.adriatic-map"

Map_Artifact :: struct {
    generator_version:            u64,
    seeds:                         [len(terrain.DEFAULT_ISLAND_SEEDS)]u32,
    project:                       terrain.Project,
    settlement_plan:               Settlement_Plan,
    marina_authored:               bool,
    marina_authored_plan:          marina.Plan,
    harbor_authored_plan:          harbor.Harbor_Plan,
    harbor_authored_intervention:  harbor.Harbor_Intervention,
    farms:                         [FARM_INSTANCE_CAPACITY]Farm_Instance,
    farm_count:                    int,
    wrecks:                        [WRECK_INSTANCE_CAPACITY]Wreck_Instance,
    wreck_count:                   int,
    default_marinas:               [len(terrain.DEFAULT_ISLAND_SIGNS)]marina.Plan,
    default_harbors:               [len(terrain.DEFAULT_ISLAND_SIGNS)]harbor.Harbor_Plan,
    default_harbor_interventions:  [len(terrain.DEFAULT_ISLAND_SIGNS)]harbor.Harbor_Intervention,
    default_marina_islands:        [len(terrain.DEFAULT_ISLAND_SIGNS)]story.Island,
    default_marina_count:          int,
    greek_placements:              [GREEK_PLACEMENT_CAPACITY]Greek_Placement,
    greek_placement_count:         int,
}

Map_Artifact_Error_Kind :: enum {
    None,
    Invalid_Argument,
    Truncated,
    Invalid_Magic,
    Unsupported_Container,
    Unsupported_Format,
    Stale_Generator,
    Invalid_Flags,
    Limit_Exceeded,
    Trailing_Bytes,
    Checksum_Mismatch,
    Portable,
    Invalid_State,
    Read,
    Write,
}

Map_Artifact_Error :: struct {
    kind:     Map_Artifact_Error_Kind,
    offset:   int,
    message:  string,
    os_error: os.Error,
    portable: hs.Portable_Error,
}

map_artifact_error_dispose :: proc(error: ^Map_Artifact_Error) {
    if error == nil do return
    hs.portable_error_dispose(&error.portable)
    error^ = {}
}

map_artifact_destroy :: proc(artifact: ^Map_Artifact, alloc := context.allocator) {
    if artifact == nil do return
    terrain.destroy_project(&artifact.project)
    free(artifact, alloc)
}

map_artifact_put_u16 :: proc(data: []byte, offset: int, value: u16) {
    data[offset] = byte(value)
    data[offset + 1] = byte(value >> 8)
}

map_artifact_put_u32 :: proc(data: []byte, offset: int, value: u32) {
    for index in 0 ..< 4 do data[offset + index] = byte(value >> (u32(index) * 8))
}

map_artifact_put_u64 :: proc(data: []byte, offset: int, value: u64) {
    for index in 0 ..< 8 do data[offset + index] = byte(value >> (u64(index) * 8))
}

map_artifact_get_u16 :: proc(data: []byte, offset: int) -> u16 {
    return u16(data[offset]) | u16(data[offset + 1]) << 8
}

map_artifact_get_u32 :: proc(data: []byte, offset: int) -> u32 {
    result: u32
    for index in 0 ..< 4 do result |= u32(data[offset + index]) << (u32(index) * 8)
    return result
}

map_artifact_get_u64 :: proc(data: []byte, offset: int) -> u64 {
    result: u64
    for index in 0 ..< 8 do result |= u64(data[offset + index]) << (u64(index) * 8)
    return result
}

map_artifact_portable_config :: proc() -> hs.Portable_Config {
    config := hs.portable_default_config()
    config.exact_schema = true
    return config
}

map_artifact_valid :: proc(artifact: ^Map_Artifact) -> (string, bool) {
    if artifact == nil do return "map is nil", false
    if artifact.generator_version != MAP_ARTIFACT_GENERATOR_VERSION do return "map generator version is stale", false
    if artifact.project.structure_count < 0 || artifact.project.structure_count > len(artifact.project.structures) {
        return "project structure count is invalid", false
    }
    if artifact.farm_count < 0 || artifact.farm_count > len(artifact.farms) do return "farm count is invalid", false
    if artifact.wreck_count < 0 || artifact.wreck_count > len(artifact.wrecks) do return "wreck count is invalid", false
    if artifact.default_marina_count < 0 || artifact.default_marina_count > len(artifact.default_marinas) {
        return "default marina count is invalid", false
    }
    if artifact.greek_placement_count < 0 || artifact.greek_placement_count > len(artifact.greek_placements) {
        return "Greek placement count is invalid", false
    }
    if math.is_nan(artifact.project.sea_level) || math.is_inf(artifact.project.sea_level, 0) {
        return "project sea level is not finite", false
    }
    for &level in artifact.project.levels {
        if math.is_nan(level.cell_size) || math.is_inf(level.cell_size, 0) || level.cell_size <= 0 {
            return "terrain cell size is invalid", false
        }
        if math.is_nan(level.origin_x) || math.is_inf(level.origin_x, 0) ||
           math.is_nan(level.origin_z) || math.is_inf(level.origin_z, 0) {
            return "terrain origin is not finite", false
        }
        for height in level.heights {
            if math.is_nan(height) || math.is_inf(height, 0) do return "terrain height is not finite", false
        }
        for material in level.material {
            if math.is_nan(material) || math.is_inf(material, 0) do return "terrain material is not finite", false
        }
    }
    return "", true
}

map_artifact_encode :: proc(artifact: ^Map_Artifact, alloc := context.allocator) -> ([]byte, Map_Artifact_Error, bool) {
    if artifact == nil || alloc.procedure == nil do return nil, {kind = .Invalid_Argument}, false
    if message, valid := map_artifact_valid(artifact); !valid {
        return nil, {kind = .Invalid_State, message = message}, false
    }
    payload, portable_error, encoded := hs.portable_encode(
        any{data = rawptr(artifact), id = typeid_of(Map_Artifact)},
        map_artifact_portable_config(),
        alloc,
    )
    if !encoded do return nil, {kind = .Portable, portable = portable_error}, false
    defer delete(payload, alloc)
    if len(payload) > MAP_ARTIFACT_MAX_PAYLOAD do return nil, {kind = .Limit_Exceeded}, false
    data, allocation_error := make([]byte, MAP_ARTIFACT_HEADER_SIZE + len(payload), alloc)
    if allocation_error != nil do return nil, {kind = .Limit_Exceeded}, false
    magic := MAP_ARTIFACT_MAGIC
    copy(data[:8], magic[:])
    map_artifact_put_u16(data, 8, MAP_ARTIFACT_CONTAINER_VERSION)
    map_artifact_put_u16(data, 10, 0)
    map_artifact_put_u32(data, 12, MAP_ARTIFACT_FORMAT_VERSION)
    map_artifact_put_u64(data, 16, artifact.generator_version)
    map_artifact_put_u64(data, 24, u64(len(payload)))
    map_artifact_put_u64(data, 32, hash.fnv64a(payload))
    copy(data[MAP_ARTIFACT_HEADER_SIZE:], payload)
    return data, {}, true
}

map_artifact_decode :: proc(data: []byte, alloc := context.allocator) -> (^Map_Artifact, Map_Artifact_Error, bool) {
    if alloc.procedure == nil do return nil, {kind = .Invalid_Argument}, false
    if len(data) < MAP_ARTIFACT_HEADER_SIZE do return nil, {kind = .Truncated, offset = len(data)}, false
    magic := MAP_ARTIFACT_MAGIC
    for index in 0 ..< len(magic) {
        if data[index] != magic[index] do return nil, {kind = .Invalid_Magic, offset = index}, false
    }
    if map_artifact_get_u16(data, 8) != MAP_ARTIFACT_CONTAINER_VERSION {
        return nil, {kind = .Unsupported_Container, offset = 8}, false
    }
    if map_artifact_get_u16(data, 10) != 0 do return nil, {kind = .Invalid_Flags, offset = 10}, false
    if map_artifact_get_u32(data, 12) != MAP_ARTIFACT_FORMAT_VERSION {
        return nil, {kind = .Unsupported_Format, offset = 12}, false
    }
    if map_artifact_get_u64(data, 16) != MAP_ARTIFACT_GENERATOR_VERSION {
        return nil, {kind = .Stale_Generator, offset = 16}, false
    }
    payload_size := map_artifact_get_u64(data, 24)
    if payload_size > MAP_ARTIFACT_MAX_PAYLOAD do return nil, {kind = .Limit_Exceeded, offset = 24}, false
    available := len(data) - MAP_ARTIFACT_HEADER_SIZE
    if payload_size > u64(available) do return nil, {kind = .Truncated, offset = len(data)}, false
    if payload_size < u64(available) {
        return nil, {kind = .Trailing_Bytes, offset = MAP_ARTIFACT_HEADER_SIZE + int(payload_size)}, false
    }
    payload := data[MAP_ARTIFACT_HEADER_SIZE:]
    if hash.fnv64a(payload) != map_artifact_get_u64(data, 32) {
        return nil, {kind = .Checksum_Mismatch, offset = 32}, false
    }
    artifact := new(Map_Artifact, alloc)
    if artifact == nil do return nil, {kind = .Limit_Exceeded}, false
    portable_error, decoded := hs.portable_decode(
        any{data = rawptr(artifact), id = typeid_of(Map_Artifact)},
        payload,
        map_artifact_portable_config(),
        alloc,
    )
    if !decoded {
        map_artifact_destroy(artifact, alloc)
        return nil, {kind = .Portable, portable = portable_error}, false
    }
    if message, valid := map_artifact_valid(artifact); !valid {
        map_artifact_destroy(artifact, alloc)
        return nil, {kind = .Invalid_State, message = message}, false
    }
    return artifact, {}, true
}

map_artifact_read :: proc(path: string, alloc := context.allocator) -> (^Map_Artifact, Map_Artifact_Error, bool) {
    data, read_error := os.read_entire_file(path, alloc)
    if read_error != nil do return nil, {kind = .Read, os_error = read_error}, false
    defer delete(data, alloc)
    return map_artifact_decode(data, alloc)
}

map_artifact_write :: proc(artifact: ^Map_Artifact, path: string, alloc := context.allocator) -> (Map_Artifact_Error, bool) {
    if path == "" do return {kind = .Invalid_Argument}, false
    data, encode_error, encoded := map_artifact_encode(artifact, alloc)
    if !encoded do return encode_error, false
    defer delete(data, alloc)
    store_error, stored := fixture_editor_store_replace_bytes_with_options(
        path,
        data,
        {operations = Fixture_Editor_Store_Default_File_Ops()},
    )
    defer fixture_editor_store_error_dispose(&store_error)
    if !stored do return {kind = .Write, os_error = store_error.os_error}, false
    return {}, true
}
