package fixture_file

import "core:hash"
import "core:testing"

Sectioned_Container_Magic :: [8]byte{'A', 'D', 'R', 'S', 'E', 'C', 0, 0}
Sectioned_Container_Version :: u16(1)
Sectioned_Container_Header_Size :: 48
Sectioned_Container_Entry_Size :: 40
Sectioned_Container_Max_Sections :: 65536
Sectioned_Container_Max_Section_Bytes :: 64 * 1024 * 1024

Artifact_Kind :: enum u16 {
    Fixture = 1,
    Map = 2,
}

Section_Kind :: enum u32 {
    Core = 1,
    Road_Proxy = 2,
    Road_Tile = 3,
}

Section_Key :: struct {
    kind: Section_Kind,
    x, z: i32,
}

Section_Input :: struct {
    key:   Section_Key,
    flags: u32,
    bytes: []byte,
}

Section_Entry :: struct {
    key:      Section_Key,
    flags:    u32,
    offset:   u64,
    size:     u64,
    checksum: u64,
}

Sectioned_Container_View :: struct {
    artifact_kind: Artifact_Kind,
    schema_version: u32,
    generator_version: u64,
    entries: []Section_Entry,
    data:    []byte,
}

Sectioned_Container_Error_Kind :: enum {
    None,
    Invalid_Argument,
    Truncated,
    Invalid_Magic,
    Unsupported_Version,
    Unsupported_Flags,
    Invalid_Artifact,
    Invalid_Directory,
    Duplicate_Section,
    Limit_Exceeded,
    Overflow,
    Trailing_Bytes,
    Checksum_Mismatch,
}

Sectioned_Container_Error :: struct {
    kind:    Sectioned_Container_Error_Kind,
    offset:  int,
    message: string,
}

sectioned_error :: proc(kind: Sectioned_Container_Error_Kind, offset: int, message: string) -> Sectioned_Container_Error {
    return {kind = kind, offset = offset, message = message}
}

sectioned_put_i32 :: proc(data: []byte, offset: int, value: i32) {
    fixture_container_put_u32(data, offset, cast(u32)value)
}

sectioned_get_i32 :: proc(data: []byte, offset: int) -> i32 {
    return cast(i32)fixture_container_get_u32(data, offset)
}

// Validate the untrusted directory shape before callers allocate its entry
// buffer. Full range and checksum validation remains in decode.
sectioned_container_directory_count :: proc(data: []byte) -> (
    count: int,
    error: Sectioned_Container_Error,
    ok: bool,
) {
    if len(data) < Sectioned_Container_Header_Size {
        return 0, sectioned_error(.Truncated, len(data), "sectioned container header is truncated"), false
    }
    count_u32 := fixture_container_get_u32(data, 24)
    if count_u32 == 0 || count_u32 > Sectioned_Container_Max_Sections {
        return 0, sectioned_error(.Limit_Exceeded, 24, "section directory count exceeds limit"), false
    }
    count = int(count_u32)
    directory_offset_u64 := fixture_container_get_u64(data, 32)
    if directory_offset_u64 > u64(max(int)) {
        return 0, sectioned_error(.Overflow, 32, "directory offset overflows host size"), false
    }
    directory_offset := int(directory_offset_u64)
    if count > (max(int) - Sectioned_Container_Header_Size) / Sectioned_Container_Entry_Size {
        return 0, sectioned_error(.Overflow, 24, "section directory size overflows host size"), false
    }
    directory_size := count * Sectioned_Container_Entry_Size
    if directory_offset < Sectioned_Container_Header_Size || directory_offset > len(data) ||
       directory_size > len(data) - directory_offset {
        return 0, sectioned_error(.Invalid_Directory, 32, "section directory lies outside the container"), false
    }
    return count, {}, true
}

sectioned_container_encode :: proc(
    artifact_kind: Artifact_Kind,
    schema_version: u32,
    generator_version: u64,
    sections: []Section_Input,
    alloc := context.allocator,
) -> (data: []byte, error: Sectioned_Container_Error, ok: bool) {
    if alloc.procedure == nil || schema_version == 0 || len(sections) == 0 {
        return nil, sectioned_error(.Invalid_Argument, 0, "sectioned container arguments are invalid"), false
    }
    if artifact_kind != .Fixture && artifact_kind != .Map {
        return nil, sectioned_error(.Invalid_Artifact, 10, "sectioned container artifact kind is invalid"), false
    }
    if len(sections) > Sectioned_Container_Max_Sections {
        return nil, sectioned_error(.Limit_Exceeded, 24, "section count exceeds limit"), false
    }
    payload_size := 0
    seen := make(map[Section_Key]bool, context.temp_allocator)
    for section in sections {
        if len(section.bytes) > Sectioned_Container_Max_Section_Bytes {
            return nil, sectioned_error(.Limit_Exceeded, 0, "section exceeds byte limit"), false
        }
        if seen[section.key] {
            return nil, sectioned_error(.Duplicate_Section, 0, "section key is duplicated"), false
        }
        seen[section.key] = true
        if payload_size > max(int) - len(section.bytes) {
            return nil, sectioned_error(.Overflow, 0, "section payload size overflows host size"), false
        }
        payload_size += len(section.bytes)
    }
    directory_size := len(sections) * Sectioned_Container_Entry_Size
    if directory_size > max(int) - Sectioned_Container_Header_Size ||
       payload_size > max(int) - Sectioned_Container_Header_Size - directory_size {
        return nil, sectioned_error(.Overflow, 0, "container size overflows host size"), false
    }
    total_size := Sectioned_Container_Header_Size + directory_size + payload_size
    data = make([]byte, total_size, alloc)
    defer if !ok do delete(data, alloc)
    magic := Sectioned_Container_Magic
    copy(data[:8], magic[:])
    fixture_container_put_u16(data, 8, Sectioned_Container_Version)
    fixture_container_put_u16(data, 10, u16(artifact_kind))
    fixture_container_put_u32(data, 12, schema_version)
    fixture_container_put_u64(data, 16, generator_version)
    fixture_container_put_u32(data, 24, u32(len(sections)))
    fixture_container_put_u32(data, 28, 0)
    fixture_container_put_u64(data, 32, Sectioned_Container_Header_Size)
    fixture_container_put_u64(data, 40, 0)
    payload_offset := Sectioned_Container_Header_Size + directory_size
    for section, index in sections {
        entry_offset := Sectioned_Container_Header_Size + index * Sectioned_Container_Entry_Size
        fixture_container_put_u32(data, entry_offset, u32(section.key.kind))
        fixture_container_put_u32(data, entry_offset + 4, section.flags)
        sectioned_put_i32(data, entry_offset + 8, section.key.x)
        sectioned_put_i32(data, entry_offset + 12, section.key.z)
        fixture_container_put_u64(data, entry_offset + 16, u64(payload_offset))
        fixture_container_put_u64(data, entry_offset + 24, u64(len(section.bytes)))
        checksum := hash.fnv64a(section.bytes)
        fixture_container_put_u64(data, entry_offset + 32, checksum)
        copy(data[payload_offset:payload_offset + len(section.bytes)], section.bytes)
        payload_offset += len(section.bytes)
    }
    directory := data[Sectioned_Container_Header_Size:Sectioned_Container_Header_Size + directory_size]
    fixture_container_put_u64(data, 40, hash.fnv64a(directory))
    return data, {}, true
}

sectioned_container_decode :: proc(
    data: []byte,
    entries: []Section_Entry,
) -> (view: Sectioned_Container_View, error: Sectioned_Container_Error, ok: bool) {
    if len(data) < Sectioned_Container_Header_Size {
        return {}, sectioned_error(.Truncated, len(data), "sectioned container header is truncated"), false
    }
    magic := Sectioned_Container_Magic
    for byte, index in magic {
        if data[index] != byte do return {}, sectioned_error(.Invalid_Magic, index, "sectioned container magic is invalid"), false
    }
    if fixture_container_get_u16(data, 8) != Sectioned_Container_Version {
        return {}, sectioned_error(.Unsupported_Version, 8, "sectioned container version is unsupported"), false
    }
    artifact_kind := Artifact_Kind(fixture_container_get_u16(data, 10))
    if artifact_kind != .Fixture && artifact_kind != .Map {
        return {}, sectioned_error(.Invalid_Artifact, 10, "sectioned container artifact kind is invalid"), false
    }
    section_count, count_error, count_ok := sectioned_container_directory_count(data)
    if !count_ok do return {}, count_error, false
    if len(entries) < section_count do return {}, sectioned_error(.Limit_Exceeded, 24, "section directory capacity is invalid"), false
    if fixture_container_get_u32(data, 28) != 0 {
        return {}, sectioned_error(.Unsupported_Flags, 28, "sectioned container flags are unsupported"), false
    }
    directory_offset_u64 := fixture_container_get_u64(data, 32)
    if directory_offset_u64 > u64(max(int)) do return {}, sectioned_error(.Overflow, 32, "directory offset overflows"), false
    directory_offset := int(directory_offset_u64)
    directory_size := section_count * Sectioned_Container_Entry_Size
    if directory_offset < Sectioned_Container_Header_Size || directory_offset > len(data) || directory_size > len(data) - directory_offset {
        return {}, sectioned_error(.Invalid_Directory, 32, "section directory lies outside the container"), false
    }
    directory := data[directory_offset:directory_offset + directory_size]
    if hash.fnv64a(directory) != fixture_container_get_u64(data, 40) {
        return {}, sectioned_error(.Checksum_Mismatch, 40, "section directory checksum does not match"), false
    }
    seen := make(map[Section_Key]bool, context.temp_allocator)
    expected_payload_offset := directory_offset + directory_size
    for index in 0 ..< section_count {
        entry_offset := directory_offset + index * Sectioned_Container_Entry_Size
        entry := Section_Entry {
            key = {
                kind = Section_Kind(fixture_container_get_u32(data, entry_offset)),
                x = sectioned_get_i32(data, entry_offset + 8),
                z = sectioned_get_i32(data, entry_offset + 12),
            },
            flags = fixture_container_get_u32(data, entry_offset + 4),
            offset = fixture_container_get_u64(data, entry_offset + 16),
            size = fixture_container_get_u64(data, entry_offset + 24),
            checksum = fixture_container_get_u64(data, entry_offset + 32),
        }
        if entry.flags != 0 do return {}, sectioned_error(.Unsupported_Flags, entry_offset + 4, "section flags are unsupported"), false
        if seen[entry.key] do return {}, sectioned_error(.Duplicate_Section, entry_offset, "section key is duplicated"), false
        seen[entry.key] = true
        if entry.offset > u64(max(int)) || entry.size > u64(max(int)) {
            return {}, sectioned_error(.Overflow, entry_offset + 16, "section range overflows host size"), false
        }
        offset, size := int(entry.offset), int(entry.size)
        if size > Sectioned_Container_Max_Section_Bytes || offset < directory_offset + directory_size || offset > len(data) || size > len(data) - offset {
            return {}, sectioned_error(.Invalid_Directory, entry_offset + 16, "section range lies outside the container"), false
        }
        if offset != expected_payload_offset {
            return {}, sectioned_error(.Invalid_Directory, entry_offset + 16, "section records are not contiguous in directory order"), false
        }
        if hash.fnv64a(data[offset:offset + size]) != entry.checksum {
            return {}, sectioned_error(.Checksum_Mismatch, entry_offset + 32, "section checksum does not match"), false
        }
        entries[index] = entry
        expected_payload_offset = offset + size
    }
    if expected_payload_offset != len(data) {
        return {}, sectioned_error(.Trailing_Bytes, expected_payload_offset, "sectioned container has trailing bytes"), false
    }
    return {
        artifact_kind = artifact_kind,
        schema_version = fixture_container_get_u32(data, 12),
        generator_version = fixture_container_get_u64(data, 16),
        entries = entries[:section_count],
        data = data,
    }, {}, true
}

sectioned_container_section :: proc(view: ^Sectioned_Container_View, key: Section_Key) -> ([]byte, bool) {
    if view == nil do return nil, false
    for entry in view.entries {
        if entry.key != key do continue
        offset, size := int(entry.offset), int(entry.size)
        return view.data[offset:offset + size], true
    }
    return nil, false
}

when ODIN_TEST {
    @(test)
    sectioned_container_round_trips_keyed_records :: proc(t: ^testing.T) {
        core := []byte{1, 2, 3}
        west := []byte{4, 5}
        east := []byte{6, 7, 8, 9}
        sections := []Section_Input {
            {key = {kind = .Core}, bytes = core},
            {key = {kind = .Road_Tile, x = -1, z = 2}, bytes = west},
            {key = {kind = .Road_Tile, x = 3, z = -4}, bytes = east},
        }
        encoded, encode_error, encoded_ok := sectioned_container_encode(.Map, 17, 9, sections)
        testing.expect(t, encoded_ok, encode_error.message)
        if !encoded_ok do return
        defer delete(encoded)
        entries: [3]Section_Entry
        view, decode_error, decoded := sectioned_container_decode(encoded, entries[:])
        testing.expect(t, decoded, decode_error.message)
        if !decoded do return
        testing.expect_value(t, view.schema_version, u32(17))
        decoded_west, found := sectioned_container_section(&view, {kind = .Road_Tile, x = -1, z = 2})
        testing.expect(t, found)
        testing.expect(t, len(decoded_west) == len(west))
        for value, index in west do testing.expect_value(t, decoded_west[index], value)
    }

    @(test)
    sectioned_container_rejects_corrupt_directory_and_payload :: proc(t: ^testing.T) {
        sections := []Section_Input{{key = {kind = .Core}, bytes = []byte{1, 2, 3}}}
        encoded, _, encoded_ok := sectioned_container_encode(.Fixture, 17, 0, sections)
        testing.expect(t, encoded_ok)
        if !encoded_ok do return
        defer delete(encoded)
        entries: [1]Section_Entry
        corrupt_directory := make([]byte, len(encoded))
        defer delete(corrupt_directory)
        copy(corrupt_directory, encoded)
        corrupt_directory[Sectioned_Container_Header_Size] = corrupt_directory[Sectioned_Container_Header_Size] ~ 1
        _, directory_error, directory_ok := sectioned_container_decode(corrupt_directory, entries[:])
        testing.expect(t, !directory_ok)
        testing.expect_value(t, directory_error.kind, Sectioned_Container_Error_Kind.Checksum_Mismatch)
        encoded[len(encoded) - 1] = encoded[len(encoded) - 1] ~ 1
        _, payload_error, payload_ok := sectioned_container_decode(encoded, entries[:])
        testing.expect(t, !payload_ok)
        testing.expect_value(t, payload_error.kind, Sectioned_Container_Error_Kind.Checksum_Mismatch)
    }

    @(test)
    sectioned_container_rejects_hostile_count_before_allocation :: proc(t: ^testing.T) {
        header: [Sectioned_Container_Header_Size]byte
        magic := Sectioned_Container_Magic
        copy(header[:8], magic[:])
        fixture_container_put_u32(header[:], 24, max(u32))
        count, error, ok := sectioned_container_directory_count(header[:])
        testing.expect(t, !ok)
        testing.expect_value(t, count, 0)
        testing.expect_value(t, error.kind, Sectioned_Container_Error_Kind.Limit_Exceeded)
    }
}
