package fixture_file

import "core:hash"
import "core:mem"

Fixture_Container_Magic :: [8]byte{'A', 'D', 'R', 'F', 'I', 'X', 0, 0}
Fixture_Container_Version :: u16(1)
Fixture_Container_Header_Size :: 32
Fixture_Container_Default_Payload_Cap :: 64 * 1024 * 1024

Fixture_Container_Error_Kind :: enum {
    None,
    Invalid_Argument,
    Truncated,
    Invalid_Magic,
    Unsupported_Version,
    Unsupported_Flags,
    Invalid_Schema_Version,
    Limit_Exceeded,
    Overflow,
    Trailing_Bytes,
    Checksum_Mismatch,
}

Fixture_Container_Error :: struct {
    kind:    Fixture_Container_Error_Kind,
    offset:  int,
    message: string,
}

Fixture_Container_Config :: struct {
    max_payload: int,
}

Fixture_Container_View :: struct {
    schema_version: u32,
    payload:        []byte,
}

FIXTURE_CONTAINER_DEFAULT_CONFIG :: Fixture_Container_Config {
    max_payload = Fixture_Container_Default_Payload_Cap,
}

fixture_container_default_config :: proc() -> Fixture_Container_Config {
    return FIXTURE_CONTAINER_DEFAULT_CONFIG
}

fixture_container_error :: proc(
    kind: Fixture_Container_Error_Kind,
    offset: int,
    message: string,
) -> Fixture_Container_Error {
    return {kind = kind, offset = offset, message = message}
}

fixture_container_validate_config :: proc(config: Fixture_Container_Config) -> Fixture_Container_Error {
    if config.max_payload < 0 {
        return fixture_container_error(.Invalid_Argument, 0, "fixture container payload cap is negative")
    }
    if config.max_payload > max(int) - Fixture_Container_Header_Size {
        return fixture_container_error(.Overflow, 0, "fixture container payload cap overflows host size")
    }
    return {}
}

fixture_container_put_u16 :: proc(data: []byte, offset: int, value: u16) {
    data[offset] = byte(value)
    data[offset + 1] = byte(value >> 8)
}

fixture_container_put_u32 :: proc(data: []byte, offset: int, value: u32) {
    data[offset] = byte(value)
    data[offset + 1] = byte(value >> 8)
    data[offset + 2] = byte(value >> 16)
    data[offset + 3] = byte(value >> 24)
}

fixture_container_put_u64 :: proc(data: []byte, offset: int, value: u64) {
    for i in 0 ..< 8 {
        data[offset + i] = byte(value >> (u64(i) * 8))
    }
}

fixture_container_get_u16 :: proc(data: []byte, offset: int) -> u16 {
    return u16(data[offset]) | u16(data[offset + 1]) << 8
}

fixture_container_get_u32 :: proc(data: []byte, offset: int) -> u32 {
    return u32(data[offset]) | u32(data[offset + 1]) << 8 | u32(data[offset + 2]) << 16 | u32(data[offset + 3]) << 24
}

fixture_container_get_u64 :: proc(data: []byte, offset: int) -> u64 {
    value: u64
    for i in 0 ..< 8 {
        value |= u64(data[offset + i]) << (u64(i) * 8)
    }
    return value
}

// Encode a payload in the product-local fixture envelope.
// The caller owns successful output and must delete it with the supplied allocator.
fixture_container_encode :: proc(
    payload: []byte,
    schema_version: u32,
    config := FIXTURE_CONTAINER_DEFAULT_CONFIG,
    alloc := context.allocator,
) -> (
    data: []byte,
    error: Fixture_Container_Error,
    ok: bool,
) {
    if config_error := fixture_container_validate_config(config); config_error.kind != .None {
        return nil, config_error, false
    }
    if alloc.procedure == nil {
        return nil,
            fixture_container_error(.Invalid_Argument, 0, "fixture container allocator has no procedure"),
            false
    }
    if schema_version == 0 {
        return nil, fixture_container_error(.Invalid_Schema_Version, 12, "fixture schema version is zero"), false
    }
    if len(payload) > config.max_payload {
        return nil, fixture_container_error(.Limit_Exceeded, 16, "fixture payload exceeds configured cap"), false
    }

    total_size := Fixture_Container_Header_Size + len(payload)
    data = make([]byte, total_size, alloc)
    defer if !ok do delete(data, alloc)

    magic := Fixture_Container_Magic
    copy(data[:8], magic[:])
    fixture_container_put_u16(data, 8, Fixture_Container_Version)
    fixture_container_put_u16(data, 10, 0)
    fixture_container_put_u32(data, 12, schema_version)
    fixture_container_put_u64(data, 16, u64(len(payload)))
    fixture_container_put_u64(data, 24, hash.fnv64a(payload))
    copy(data[Fixture_Container_Header_Size:], payload)
    return data, {}, true
}

// Validate a fixture envelope and return a borrowed payload view.
// The returned payload aliases data; the caller must keep data alive and unchanged as needed.
fixture_container_decode :: proc(
    data: []byte,
    config := FIXTURE_CONTAINER_DEFAULT_CONFIG,
) -> (
    view: Fixture_Container_View,
    error: Fixture_Container_Error,
    ok: bool,
) {
    if config_error := fixture_container_validate_config(config); config_error.kind != .None {
        return {}, config_error, false
    }
    if len(data) < Fixture_Container_Header_Size {
        return {}, fixture_container_error(.Truncated, len(data), "fixture container header is truncated"), false
    }
    magic := Fixture_Container_Magic
    for i in 0 ..< len(magic) {
        if data[i] != magic[i] {
            return {}, fixture_container_error(.Invalid_Magic, i, "fixture container magic is invalid"), false
        }
    }
    version := fixture_container_get_u16(data, 8)
    if version != Fixture_Container_Version {
        return {}, fixture_container_error(.Unsupported_Version, 8, "fixture container version is unsupported"), false
    }
    flags := fixture_container_get_u16(data, 10)
    if flags != 0 {
        return {}, fixture_container_error(.Unsupported_Flags, 10, "fixture container flags are unsupported"), false
    }
    schema_version := fixture_container_get_u32(data, 12)
    if schema_version == 0 {
        return {}, fixture_container_error(.Invalid_Schema_Version, 12, "fixture schema version is zero"), false
    }
    payload_size := fixture_container_get_u64(data, 16)
    if payload_size > u64(max(int)) {
        return {}, fixture_container_error(.Overflow, 16, "fixture payload length exceeds host size"), false
    }
    if payload_size > u64(config.max_payload) {
        return {}, fixture_container_error(.Limit_Exceeded, 16, "fixture payload exceeds configured cap"), false
    }

    available := len(data) - Fixture_Container_Header_Size
    payload_length := int(payload_size)
    if payload_length > available {
        return {}, fixture_container_error(.Truncated, len(data), "fixture container payload is truncated"), false
    }
    if payload_length < available {
        return {},
            fixture_container_error(
                .Trailing_Bytes,
                Fixture_Container_Header_Size + payload_length,
                "fixture container has trailing bytes",
            ),
            false
    }

    payload := data[Fixture_Container_Header_Size:Fixture_Container_Header_Size + payload_length]
    expected_checksum := fixture_container_get_u64(data, 24)
    if hash.fnv64a(payload) != expected_checksum {
        return {}, fixture_container_error(.Checksum_Mismatch, 24, "fixture payload checksum does not match"), false
    }
    return {schema_version = schema_version, payload = payload}, {}, true
}
