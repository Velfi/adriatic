package tests

import fixture_file "../packages/fixture_file"
import "base:runtime"
import "core:hash"
import "core:mem"
import "core:testing"

fixture_file_test_payload :: proc(alloc := context.allocator) -> []byte {
    result := make([]byte, 7, alloc)
    values := [7]byte{0x00, 0x01, 0x7f, 0x80, 0xfe, 0xff, 0x42}
    copy(result, values[:])
    return result
}

fixture_file_test_copy :: proc(data: []byte) -> []byte {
    result := make([]byte, len(data), context.allocator)
    copy(result, data)
    return result
}

fixture_file_test_put_u32 :: proc(data: []byte, offset: int, value: u32) {
    data[offset] = byte(value)
    data[offset + 1] = byte(value >> 8)
    data[offset + 2] = byte(value >> 16)
    data[offset + 3] = byte(value >> 24)
}

fixture_file_test_put_u64 :: proc(data: []byte, offset: int, value: u64) {
    for i in 0 ..< 8 {
        data[offset + i] = byte(value >> (u64(i) * 8))
    }
}

fixture_file_test_get_u64 :: proc(data: []byte, offset: int) -> u64 {
    value: u64
    for i in 0 ..< 8 {
        value |= u64(data[offset + i]) << (u64(i) * 8)
    }
    return value
}

fixture_file_test_bytes_equal :: proc(left, right: []byte) -> bool {
    if len(left) != len(right) do return false
    for i in 0 ..< len(left) {
        if left[i] != right[i] do return false
    }
    return true
}

fixture_file_test_expect_failure :: proc(
    t: ^testing.T,
    data: []byte,
    expected: fixture_file.Fixture_Container_Error_Kind,
    config := fixture_file.FIXTURE_CONTAINER_DEFAULT_CONFIG,
) {
    view, error, ok := fixture_file.fixture_container_decode(data, config)
    testing.expect(t, !ok)
    testing.expect(t, error.kind == expected)
    testing.expect(t, view.schema_version == 0)
    testing.expect(t, view.payload == nil)
}

@(test)
fixture_container_round_trip_is_deterministic_and_portable :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    payload := fixture_file_test_payload()
    first, first_error, first_ok := fixture_file.fixture_container_encode(payload, 7)
    second, second_error, second_ok := fixture_file.fixture_container_encode(payload, 7)
    testing.expect(t, first_ok)
    testing.expect(t, second_ok)
    testing.expect(t, first_error.kind == .None)
    testing.expect(t, second_error.kind == .None)
    testing.expect(t, len(first) == fixture_file.Fixture_Container_Header_Size + len(payload))
    testing.expect(t, fixture_file_test_bytes_equal(first, second))

    magic := fixture_file.Fixture_Container_Magic
    for i in 0 ..< len(magic) {
        testing.expect(t, first[i] == magic[i])
    }
    testing.expect(t, first[8] == 1)
    testing.expect(t, first[9] == 0)
    testing.expect(t, first[10] == 0)
    testing.expect(t, first[11] == 0)
    testing.expect(t, first[12] == 7)
    testing.expect(t, first[13] == 0)
    testing.expect(t, first[14] == 0)
    testing.expect(t, first[15] == 0)
    testing.expect(t, fixture_file_test_get_u64(first, 16) == u64(len(payload)))
    testing.expect(t, fixture_file_test_get_u64(first, 24) == hash.fnv64a(payload))

    view, decode_error, decode_ok := fixture_file.fixture_container_decode(first)
    testing.expect(t, decode_ok)
    testing.expect(t, decode_error.kind == .None)
    testing.expect(t, view.schema_version == 7)
    testing.expect(t, len(view.payload) == len(payload))
    for i in 0 ..< len(payload) {
        testing.expect(t, view.payload[i] == payload[i])
    }
    before := view.payload[0]
    first[fixture_file.Fixture_Container_Header_Size] = first[fixture_file.Fixture_Container_Header_Size] ~ 0xff
    testing.expect(t, view.payload[0] == first[fixture_file.Fixture_Container_Header_Size])
    testing.expect(t, view.payload[0] != before)

    empty, empty_error, empty_ok := fixture_file.fixture_container_encode(nil, 9)
    testing.expect(t, empty_ok)
    testing.expect(t, empty_error.kind == .None)
    testing.expect(t, len(empty) == fixture_file.Fixture_Container_Header_Size)
    empty_view, empty_decode_error, empty_decode_ok := fixture_file.fixture_container_decode(empty)
    testing.expect(t, empty_decode_ok)
    testing.expect(t, empty_decode_error.kind == .None)
    testing.expect(t, empty_view.schema_version == 9)
    testing.expect(t, len(empty_view.payload) == 0)
}

@(test)
fixture_container_rejects_short_headers_and_payloads :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    payload := fixture_file_test_payload()
    encoded, _, ok := fixture_file.fixture_container_encode(payload, 1)
    testing.expect(t, ok)
    if !ok do return

    for length in 0 ..< fixture_file.Fixture_Container_Header_Size {
        fixture_file_test_expect_failure(t, encoded[:length], .Truncated)
    }
    for length in 0 ..< len(payload) {
        fixture_file_test_expect_failure(t, encoded[:fixture_file.Fixture_Container_Header_Size + length], .Truncated)
    }
}

@(test)
fixture_container_rejects_every_header_and_payload_corruption :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    payload := fixture_file_test_payload()
    encoded, _, ok := fixture_file.fixture_container_encode(payload, 1)
    testing.expect(t, ok)
    if !ok do return

    for i in 0 ..< len(fixture_file.Fixture_Container_Magic) {
        bad := fixture_file_test_copy(encoded)
        bad[i] = bad[i] ~ 1
        fixture_file_test_expect_failure(t, bad, .Invalid_Magic)
    }

    bad_version := fixture_file_test_copy(encoded)
    bad_version[8] = 2
    fixture_file_test_expect_failure(t, bad_version, .Unsupported_Version)

    bad_flags := fixture_file_test_copy(encoded)
    bad_flags[10] = 1
    fixture_file_test_expect_failure(t, bad_flags, .Unsupported_Flags)

    bad_schema := fixture_file_test_copy(encoded)
    fixture_file_test_put_u32(bad_schema, 12, 0)
    fixture_file_test_expect_failure(t, bad_schema, .Invalid_Schema_Version)

    bad_checksum := fixture_file_test_copy(encoded)
    bad_checksum[24] = bad_checksum[24] ~ 1
    fixture_file_test_expect_failure(t, bad_checksum, .Checksum_Mismatch)

    bad_payload := fixture_file_test_copy(encoded)
    bad_payload[fixture_file.Fixture_Container_Header_Size] =
        bad_payload[fixture_file.Fixture_Container_Header_Size] ~ 1
    fixture_file_test_expect_failure(t, bad_payload, .Checksum_Mismatch)
}

@(test)
fixture_container_rejects_forged_lengths_and_caps :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    payload := fixture_file_test_payload()
    encoded, _, ok := fixture_file.fixture_container_encode(payload, 1)
    testing.expect(t, ok)
    if !ok do return

    bad_zero := fixture_file_test_copy(encoded)
    fixture_file_test_put_u64(bad_zero, 16, 0)
    fixture_file_test_expect_failure(t, bad_zero, .Trailing_Bytes)

    bad_short := fixture_file_test_copy(encoded)
    fixture_file_test_put_u64(bad_short, 16, u64(len(payload) - 1))
    fixture_file_test_expect_failure(t, bad_short, .Trailing_Bytes)

    bad_long := fixture_file_test_copy(encoded)
    fixture_file_test_put_u64(bad_long, 16, u64(len(payload) + 1))
    fixture_file_test_expect_failure(t, bad_long, .Truncated)

    bad_overflow := fixture_file_test_copy(encoded)
    fixture_file_test_put_u64(bad_overflow, 16, max(u64))
    fixture_file_test_expect_failure(t, bad_overflow, .Overflow)

    appended := make([]byte, len(encoded) + 1, context.allocator)
    copy(appended, encoded)
    appended[len(encoded)] = 0xee
    fixture_file_test_expect_failure(t, appended, .Trailing_Bytes)

    small_config := fixture_file.fixture_container_default_config()
    small_config.max_payload = len(payload) - 1
    fixture_file_test_expect_failure(t, encoded, .Limit_Exceeded, small_config)

    invalid_config := fixture_file.fixture_container_default_config()
    invalid_config.max_payload = -1
    fixture_file_test_expect_failure(t, encoded, .Invalid_Argument, invalid_config)

    overflowing_config := fixture_file.fixture_container_default_config()
    overflowing_config.max_payload = max(int)
    fixture_file_test_expect_failure(t, encoded, .Overflow, overflowing_config)
}

@(test)
fixture_container_encode_validates_arguments_and_owns_output :: proc(t: ^testing.T) {
    payload := fixture_file_test_payload()
    defer delete(payload)
    nil_allocator := mem.Allocator{}
    encoded, error, ok := fixture_file.fixture_container_encode(payload, 1, alloc = nil_allocator)
    testing.expect(t, !ok)
    testing.expect(t, encoded == nil)
    testing.expect(t, error.kind == .Invalid_Argument)

    _, error, ok = fixture_file.fixture_container_encode(payload, 0)
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Invalid_Schema_Version)

    config := fixture_file.fixture_container_default_config()
    config.max_payload = len(payload) - 1
    encoded, error, ok = fixture_file.fixture_container_encode(payload, 1, config)
    testing.expect(t, !ok)
    testing.expect(t, encoded == nil)
    testing.expect(t, error.kind == .Limit_Exceeded)

    encoded, error, ok = fixture_file.fixture_container_encode(payload, 1, alloc = context.allocator)
    testing.expect(t, ok)
    testing.expect(t, error.kind == .None)
    if ok do delete(encoded)
}
