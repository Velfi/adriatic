package tests

import hs "../packages/hs"
import toml "../packages/toml"
import "base:runtime"
import "core:mem"
import "core:strings"
import "core:testing"

Portable_Mode :: enum u8 {
    Idle    = 0,
    Sailing = 3,
}

Portable_Count :: distinct i32

Portable_Nested :: struct {
    value:       i32,
    label:       string,
    hidden_data: [16]u8 `fixture:"-"`,
    hidden_ptr:  ^int `fixture:"-"`,
    hidden_list: []u8 `fixture:"-"`,
}

Portable_State :: struct {
    enabled:  bool,
    signed:   i16,
    unsigned: u64,
    ratio:    f32,
    precise:  f64,
    text:     string,
    mode:     Portable_Mode,
    count:    Portable_Count,
    values:   [4]u8,
    nested:   Portable_Nested,
}

Bad_Pointer_State :: struct {
    value: i32,
    ptr:   ^int,
}

Excluded_Unsupported_State :: struct {
    value: i32,
    ptr:   ^int `fixture:"-"`,
    list:  []u8 `fixture:"-"`,
}

Portable_Additive_Source :: struct {
    kept:    i32,
    removed: i32,
}

Portable_Additive_Destination :: struct {
    kept:  i32,
    added: string,
}

Portable_Exact_Mode_Drift :: enum u8 {
    Idle    = 0,
    Sailing = 3,
    Docked  = 4,
}

Portable_Exact_Mode_Source :: struct {
    mode: Portable_Mode,
}

Portable_Exact_Mode_Destination :: struct {
    mode: Portable_Exact_Mode_Drift,
}

Portable_Representative :: struct {
    name:   string,
    bytes:  [256]u8,
    floats: [256]f32,
    nested: Portable_Nested,
}

Portable_Scalar_Widths :: struct {
    i8_value:   i8,
    i16_value:  i16,
    i32_value:  i32,
    i64_value:  i64,
    u8_value:   u8,
    u16_value:  u16,
    u32_value:  u32,
    u64_value:  u64,
    rune_value: rune,
    half_value: f16,
}

Portable_Moderate_Array :: struct {
    bytes: [4096]u8,
}

Portable_Duplicate_Struct :: struct {
    abcd: i32,
    wxyz: i32,
}

Portable_Duplicate_Enum :: enum u8 {
    ABCD = 0,
    WXYZ = 1,
}

Portable_Toml_Nested :: struct {
    value: i32,
    label: string,
}

Portable_Toml_Representative :: struct {
    name:   string,
    bytes:  [256]u8,
    floats: [256]f32,
    nested: Portable_Toml_Nested,
}

Portable_Dynamic_Item :: struct {
    value: i32,
    label: string,
}

Portable_Dynamic_State :: struct {
    empty:   [dynamic]i32,
    items:   [dynamic]Portable_Dynamic_Item,
    scratch: [dynamic][]u8 `fixture:"-"`,
}

Portable_Dynamic_Scalar_State :: struct {
    values: [dynamic]i32,
}

Portable_Fixed_Scalar_State :: struct {
    values: [3]i32,
}

Portable_Dynamic_Enum_State :: struct {
    values: [dynamic]Portable_Mode,
}

Portable_Fixed_Enum_State :: struct {
    values: [3]Portable_Mode,
}

Portable_Recursive_Node :: struct {
    value:    i32,
    children: [dynamic]Portable_Recursive_Node,
}

Portable_Test_Counting_Allocator :: struct {
    backing:     mem.Allocator,
    allocs:      int,
    outstanding: int,
    fail_at:     int,
}

portable_test_counting_allocator_proc :: proc(
    allocator_data: rawptr,
    mode: runtime.Allocator_Mode,
    size, alignment: int,
    old_memory: rawptr,
    old_size: int,
    location := #caller_location,
) -> (
    []byte,
    runtime.Allocator_Error,
) {
    state := (^Portable_Test_Counting_Allocator)(allocator_data)
    if (mode == .Alloc || mode == .Alloc_Non_Zeroed) && state.fail_at >= 0 && state.allocs >= state.fail_at {
        return nil, .Out_Of_Memory
    }
    result, err := state.backing.procedure(state.backing.data, mode, size, alignment, old_memory, old_size, location)
    if err == .None && (mode == .Alloc || mode == .Alloc_Non_Zeroed) {
        state.allocs += 1
        state.outstanding += 1
    }
    if err == .None && mode == .Free {
        state.outstanding -= 1
    }
    return result, err
}

portable_test_state :: proc() -> Portable_State {
    return {
        enabled = true,
        signed = -1234,
        unsigned = 0xfeed_beef_dead_beef,
        ratio = 0.125,
        precise = -12345.6789,
        text = "portable Adriatic state",
        mode = .Sailing,
        count = Portable_Count(77),
        values = [4]u8{1, 2, 127, 255},
        nested = {value = 456, label = "nested", hidden_ptr = nil},
    }
}

portable_test_fixture_config :: proc() -> hs.Portable_Config {
    config := hs.portable_default_config()
    config.exclusion_tag = "fixture"
    return config
}

portable_test_any :: proc($T: typeid, value: ^T) -> any {
    return any{data = rawptr(value), id = typeid_of(T)}
}

portable_test_copy :: proc(data: []byte) -> []byte {
    result := make([]byte, len(data), context.allocator)
    copy(result, data)
    return result
}

portable_test_u32 :: proc(data: []byte, offset: int) -> u32 {
    return u32(data[offset]) | u32(data[offset + 1]) << 8 | u32(data[offset + 2]) << 16 | u32(data[offset + 3]) << 24
}

portable_test_put_u32 :: proc(data: []byte, offset: int, value: u32) {
    data[offset] = byte(value)
    data[offset + 1] = byte(value >> 8)
    data[offset + 2] = byte(value >> 16)
    data[offset + 3] = byte(value >> 24)
}

portable_test_put_u16 :: proc(data: []byte, offset: int, value: u16) {
    data[offset] = byte(value)
    data[offset + 1] = byte(value >> 8)
}

portable_test_put_u64 :: proc(data: []byte, offset: int, value: u64) {
    for i in 0 ..< 8 {
        data[offset + i] = byte(value >> (u64(i) * 8))
    }
}

portable_test_dispose_error :: proc(error: ^hs.Portable_Error) {
    hs.portable_error_dispose(error)
}

portable_test_self_cycle_payload :: proc() -> []byte {
    payload := make([]byte, hs.Portable_Header_Size + 16, context.allocator)
    magic := hs.Portable_Magic
    copy(payload[:8], magic[:])
    portable_test_put_u16(payload, 8, hs.Portable_Version)
    portable_test_put_u32(payload, 12, 1)
    portable_test_put_u32(payload, 16, 1)
    portable_test_put_u32(payload, 20, 16)
    portable_test_put_u32(payload, 24, 0)
    payload[hs.Portable_Header_Size] = byte(hs.Portable_Kind.Array)
    portable_test_put_u32(payload, hs.Portable_Header_Size + 4, 1)
    portable_test_put_u64(payload, hs.Portable_Header_Size + 8, u64(16 * 1024 * 1024))
    return payload
}

portable_test_deep_chain_payload :: proc() -> []byte {
    config := hs.portable_default_config()
    array_count := config.limits.max_recursion_depth + 1
    table_bytes := array_count * 16 + 4
    payload := make([]byte, hs.Portable_Header_Size + table_bytes + 1, context.allocator)
    magic := hs.Portable_Magic
    copy(payload[:8], magic[:])
    portable_test_put_u16(payload, 8, hs.Portable_Version)
    portable_test_put_u32(payload, 12, 1)
    portable_test_put_u32(payload, 16, u32(array_count + 1))
    portable_test_put_u32(payload, 20, u32(table_bytes))
    portable_test_put_u32(payload, 24, 1)
    for i in 0 ..< array_count {
        record := hs.Portable_Header_Size + i * 16
        payload[record] = byte(hs.Portable_Kind.Array)
        portable_test_put_u32(payload, record + 4, u32(i + 2))
        portable_test_put_u64(payload, record + 8, 1)
    }
    scalar_record := hs.Portable_Header_Size + array_count * 16
    payload[scalar_record] = byte(hs.Portable_Kind.Unsigned)
    payload[scalar_record + 1] = 1
    return payload
}

portable_test_find_type_record :: proc(data: []byte, wanted: hs.Portable_Kind) -> int {
    cursor := hs.Portable_Header_Size
    type_count := int(portable_test_u32(data, 16))
    for _ in 0 ..< type_count {
        start := cursor
        kind := hs.Portable_Kind(data[cursor])
        cursor += 4
        #partial switch kind {
        case .Array:
            cursor += 12
        case .Dynamic_Array:
            cursor += 4
        case .Struct:
            field_count := int(portable_test_u32(data, cursor))
            cursor += 4
            for _ in 0 ..< field_count {
                name_length := int(portable_test_u32(data, cursor))
                cursor += 4 + name_length + 4
            }
        case .Enum:
            field_count := int(portable_test_u32(data, cursor + 4))
            cursor += 8
            for _ in 0 ..< field_count {
                name_length := int(portable_test_u32(data, cursor))
                cursor += 4 + name_length + 8
            }
        case:
        }
        if kind == wanted do return start
    }
    return -1
}

portable_test_destroy_dynamic_state :: proc(state: ^Portable_Dynamic_State, free_strings: bool) {
    if state == nil do return
    if free_strings {
        for &item in state.items {
            delete(item.label)
        }
    }
    delete(state.empty)
    delete(state.items)
    delete(state.scratch)
}

portable_test_dynamic_cycle_payload :: proc() -> []byte {
    payload := make([]byte, hs.Portable_Header_Size + 8, context.allocator)
    magic := hs.Portable_Magic
    copy(payload[:8], magic[:])
    portable_test_put_u16(payload, 8, hs.Portable_Version)
    portable_test_put_u32(payload, 12, 1)
    portable_test_put_u32(payload, 16, 1)
    portable_test_put_u32(payload, 20, 8)
    payload[hs.Portable_Header_Size] = byte(hs.Portable_Kind.Dynamic_Array)
    portable_test_put_u32(payload, hs.Portable_Header_Size + 4, 1)
    return payload
}

@(test)
hs_portable_dynamic_arrays_round_trip_and_exclusions :: proc(t: ^testing.T) {
    source := Portable_Dynamic_State {
        empty   = make([dynamic]i32, 0, context.allocator),
        items   = make([dynamic]Portable_Dynamic_Item, 2, context.allocator),
        scratch = make([dynamic][]u8, 1, context.allocator),
    }
    source.items[0] = {
        value = 17,
        label = "first dynamic item",
    }
    source.items[1] = {
        value = -23,
        label = "second dynamic item",
    }

    config := portable_test_fixture_config()
    first, first_error, first_ok := hs.portable_encode(
        portable_test_any(Portable_Dynamic_State, &source),
        config,
        context.allocator,
    )
    testing.expect(t, first_ok)
    testing.expect(t, first_error.kind == .None)
    if !first_ok {
        portable_test_destroy_dynamic_state(&source, false)
        return
    }
    defer delete(first)
    dynamic_record := portable_test_find_type_record(first, .Dynamic_Array)
    testing.expect(t, dynamic_record >= 0)
    testing.expect(t, first[dynamic_record] == byte(hs.Portable_Kind.Dynamic_Array))
    payload_text := string(first)
    testing.expect(t, !strings.contains(payload_text, "scratch"))

    second, second_error, second_ok := hs.portable_encode(
        portable_test_any(Portable_Dynamic_State, &source),
        config,
        context.allocator,
    )
    testing.expect(t, second_ok)
    testing.expect(t, second_error.kind == .None)
    if second_ok {
        testing.expect(t, len(first) == len(second))
        for index in 0 ..< len(first) {
            testing.expect(t, first[index] == second[index])
        }
        delete(second)
    }

    destination := Portable_Dynamic_State{}
    error, decode_ok := hs.portable_decode(
        portable_test_any(Portable_Dynamic_State, &destination),
        first,
        config,
        context.allocator,
    )
    testing.expect(t, decode_ok)
    testing.expect(t, error.kind == .None)
    testing.expect(t, len(destination.empty) == 0)
    testing.expect(t, len(destination.items) == 2)
    if len(destination.items) == 2 {
        testing.expect(t, destination.items[0].value == source.items[0].value)
        testing.expect(t, destination.items[0].label == source.items[0].label)
        testing.expect(t, destination.items[1].value == source.items[1].value)
        testing.expect(t, destination.items[1].label == source.items[1].label)
    }
    restored, restored_error, restored_ok := hs.portable_encode(
        portable_test_any(Portable_Dynamic_State, &destination),
        config,
        context.allocator,
    )
    testing.expect(t, restored_ok)
    testing.expect(t, restored_error.kind == .None)
    if restored_ok {
        testing.expect(t, len(first) == len(restored))
        for index in 0 ..< len(first) {
            testing.expect(t, first[index] == restored[index])
        }
        delete(restored)
    }
    hs.portable_error_dispose(&restored_error)
    portable_test_destroy_dynamic_state(&destination, true)
    portable_test_destroy_dynamic_state(&source, false)
}

@(test)
hs_portable_dynamic_arrays_cross_fixed_and_harden_failures :: proc(t: ^testing.T) {
    nil_source := Portable_Dynamic_Scalar_State{}
    empty_source := Portable_Dynamic_Scalar_State {
        values = make([dynamic]i32, 0, context.allocator),
    }
    nil_data, _, nil_ok := hs.portable_encode(
        portable_test_any(Portable_Dynamic_Scalar_State, &nil_source),
        alloc = context.allocator,
    )
    empty_data, _, empty_ok := hs.portable_encode(
        portable_test_any(Portable_Dynamic_Scalar_State, &empty_source),
        alloc = context.allocator,
    )
    testing.expect(t, nil_ok)
    testing.expect(t, empty_ok)
    if nil_ok && empty_ok {
        testing.expect(t, len(nil_data) == len(empty_data))
        for index in 0 ..< len(nil_data) {
            testing.expect(t, nil_data[index] == empty_data[index])
        }
    }
    if nil_ok do delete(nil_data)
    if empty_ok do delete(empty_data)
    delete(empty_source.values)

    single_source := Portable_Dynamic_Scalar_State {
        values = make([dynamic]i32, 1, context.allocator),
    }
    single_source.values[0] = 41
    single_data, _, single_ok := hs.portable_encode(
        portable_test_any(Portable_Dynamic_Scalar_State, &single_source),
        alloc = context.allocator,
    )
    testing.expect(t, single_ok)
    if single_ok do delete(single_data)
    delete(single_source.values)

    wide_config := hs.portable_default_config()
    wide_config.limits.max_array_elements = max(int)
    wide_source := Portable_Dynamic_Scalar_State {
        values = make([dynamic]i32, 1, context.allocator),
    }
    wide_source.values[0] = 99
    wide_data, wide_error, wide_ok := hs.portable_encode(
        portable_test_any(Portable_Dynamic_Scalar_State, &wide_source),
        wide_config,
        context.allocator,
    )
    testing.expect(t, wide_ok)
    testing.expect(t, wide_error.kind == .None)
    if wide_ok {
        wide_destination := Portable_Dynamic_Scalar_State{}
        error, wide_decode_ok := hs.portable_decode(
            portable_test_any(Portable_Dynamic_Scalar_State, &wide_destination),
            wide_data,
            wide_config,
            context.allocator,
        )
        testing.expect(t, wide_decode_ok)
        testing.expect(t, error.kind == .None)
        testing.expect(t, len(wide_destination.values) == 1)
        if wide_decode_ok do testing.expect(t, wide_destination.values[0] == 99)
        delete(wide_destination.values)
        delete(wide_data)
    }
    delete(wide_source.values)

    fixed_source := Portable_Fixed_Scalar_State {
        values = {7, 8, 9},
    }
    fixed_data, fixed_error, fixed_ok := hs.portable_encode(
        portable_test_any(Portable_Fixed_Scalar_State, &fixed_source),
        hs.portable_default_config(),
        context.allocator,
    )
    testing.expect(t, fixed_ok)
    testing.expect(t, fixed_error.kind == .None)
    error: hs.Portable_Error
    decode_ok: bool
    if fixed_ok {
        dynamic_destination := Portable_Dynamic_Scalar_State{}
        error, decode_ok = hs.portable_decode(
            portable_test_any(Portable_Dynamic_Scalar_State, &dynamic_destination),
            fixed_data,
            alloc = context.allocator,
        )
        testing.expect(t, decode_ok)
        testing.expect(t, error.kind == .None)
        testing.expect(t, len(dynamic_destination.values) == 3)
        if decode_ok {
            testing.expect(t, dynamic_destination.values[0] == 7)
            testing.expect(t, dynamic_destination.values[2] == 9)
        }
        delete(dynamic_destination.values)
        delete(fixed_data)
    }

    dynamic_source := Portable_Dynamic_Scalar_State {
        values = make([dynamic]i32, 3, context.allocator),
    }
    dynamic_source.values[0] = 13
    dynamic_source.values[1] = 14
    dynamic_source.values[2] = 15
    dynamic_data, dynamic_error, dynamic_ok := hs.portable_encode(
        portable_test_any(Portable_Dynamic_Scalar_State, &dynamic_source),
        alloc = context.allocator,
    )
    testing.expect(t, dynamic_ok)
    testing.expect(t, dynamic_error.kind == .None)
    if !dynamic_ok {
        delete(dynamic_source.values)
        return
    }

    counted_one_source := Portable_Dynamic_Scalar_State {
        values = make([dynamic]i32, 1, context.allocator),
    }
    counted_one_source.values[0] = 501
    counted_many_source := Portable_Dynamic_Scalar_State {
        values = make([dynamic]i32, 128, context.allocator),
    }
    for index in 0 ..< len(counted_many_source.values) {
        counted_many_source.values[index] = i32(700 + index)
    }
    counted_one_data, _, counted_one_ok := hs.portable_encode(
        portable_test_any(Portable_Dynamic_Scalar_State, &counted_one_source),
        alloc = context.allocator,
    )
    counted_many_data, _, counted_many_ok := hs.portable_encode(
        portable_test_any(Portable_Dynamic_Scalar_State, &counted_many_source),
        alloc = context.allocator,
    )
    testing.expect(t, counted_one_ok && counted_many_ok)
    if counted_one_ok && counted_many_ok {
        one_allocator_state := Portable_Test_Counting_Allocator {
            backing = context.allocator,
            fail_at = -1,
        }
        one_allocator := mem.Allocator {
            procedure = portable_test_counting_allocator_proc,
            data      = rawptr(&one_allocator_state),
        }
        one_destination := Portable_Dynamic_Scalar_State{}
        one_error, one_ok := hs.portable_decode(
            portable_test_any(Portable_Dynamic_Scalar_State, &one_destination),
            counted_one_data,
            alloc = one_allocator,
        )
        testing.expect(t, one_ok)
        testing.expect(t, one_error.kind == .None)
        testing.expect(t, len(one_destination.values) == 1)
        if one_ok do testing.expect(t, one_destination.values[0] == 501)
        delete(one_destination.values)
        testing.expect(t, one_allocator_state.outstanding == 0)

        many_allocator_state := Portable_Test_Counting_Allocator {
            backing = context.allocator,
            fail_at = -1,
        }
        many_allocator := mem.Allocator {
            procedure = portable_test_counting_allocator_proc,
            data      = rawptr(&many_allocator_state),
        }
        many_destination := Portable_Dynamic_Scalar_State{}
        many_error, many_ok := hs.portable_decode(
            portable_test_any(Portable_Dynamic_Scalar_State, &many_destination),
            counted_many_data,
            alloc = many_allocator,
        )
        testing.expect(t, many_ok)
        testing.expect(t, many_error.kind == .None)
        testing.expect(t, len(many_destination.values) == 128)
        if many_ok {
            testing.expect(t, many_destination.values[0] == 700)
            testing.expect(t, many_destination.values[127] == 827)
        }
        delete(many_destination.values)
        testing.expect(t, many_allocator_state.outstanding == 0)
        testing.expect(t, one_allocator_state.allocs == many_allocator_state.allocs)
        delete(counted_one_data)
        delete(counted_many_data)
    }
    delete(counted_one_source.values)
    delete(counted_many_source.values)

    probe := Portable_Test_Counting_Allocator {
        backing = context.allocator,
        fail_at = -1,
    }
    probe_allocator := mem.Allocator {
        procedure = portable_test_counting_allocator_proc,
        data      = rawptr(&probe),
    }
    probe_destination := Portable_Dynamic_Scalar_State{}
    probe_error, probe_ok := hs.portable_decode(
        portable_test_any(Portable_Dynamic_Scalar_State, &probe_destination),
        dynamic_data,
        alloc = probe_allocator,
    )
    testing.expect(t, probe_ok)
    testing.expect(t, probe_error.kind == .None)
    testing.expect(t, probe.allocs >= 3)
    delete(probe_destination.values)
    testing.expect(t, probe.outstanding == 0)

    failing := Portable_Test_Counting_Allocator {
        backing = context.allocator,
        fail_at = probe.allocs - 1,
    }
    failing_allocator := mem.Allocator {
        procedure = portable_test_counting_allocator_proc,
        data      = rawptr(&failing),
    }
    failed_destination := Portable_Dynamic_Scalar_State{}
    error, decode_ok = hs.portable_decode(
        portable_test_any(Portable_Dynamic_Scalar_State, &failed_destination),
        dynamic_data,
        alloc = failing_allocator,
    )
    testing.expect(t, !decode_ok)
    testing.expect(t, error.kind == .Limit_Exceeded)
    hs.portable_error_dispose(&error)
    delete(failed_destination.values)
    testing.expect(t, failing.outstanding == 0)

    occupied_destination := Portable_Dynamic_Scalar_State {
        values = make([dynamic]i32, 1, context.allocator),
    }
    error, decode_ok = hs.portable_decode(
        portable_test_any(Portable_Dynamic_Scalar_State, &occupied_destination),
        dynamic_data,
        alloc = context.allocator,
    )
    testing.expect(t, !decode_ok)
    testing.expect(t, error.kind == .Type_Mismatch)
    hs.portable_error_dispose(&error)
    delete(occupied_destination.values)

    fixed_destination := Portable_Fixed_Scalar_State{}
    error, decode_ok = hs.portable_decode(
        portable_test_any(Portable_Fixed_Scalar_State, &fixed_destination),
        dynamic_data,
        alloc = context.allocator,
    )
    testing.expect(t, decode_ok)
    testing.expect(t, fixed_destination.values[0] == 13)
    testing.expect(t, fixed_destination.values[2] == 15)

    truncated := dynamic_data[:len(dynamic_data) - 1]
    error, decode_ok = hs.portable_decode(
        portable_test_any(Portable_Fixed_Scalar_State, &Portable_Fixed_Scalar_State{}),
        truncated,
        alloc = context.allocator,
    )
    testing.expect(t, !decode_ok)
    testing.expect(t, error.kind == .Truncated)
    hs.portable_error_dispose(&error)

    bad_count := portable_test_copy(dynamic_data)
    body_start := hs.Portable_Header_Size + int(portable_test_u32(dynamic_data, 20))
    portable_test_put_u64(bad_count, body_start, u64(max(u64)))
    error, decode_ok = hs.portable_decode(
        portable_test_any(Portable_Dynamic_Scalar_State, &Portable_Dynamic_Scalar_State{}),
        bad_count,
        alloc = context.allocator,
    )
    testing.expect(t, !decode_ok)
    testing.expect(t, error.kind == .Limit_Exceeded)
    hs.portable_error_dispose(&error)
    delete(bad_count)

    bad_handle := portable_test_copy(dynamic_data)
    dynamic_record := portable_test_find_type_record(bad_handle, .Dynamic_Array)
    testing.expect(t, dynamic_record >= 0)
    portable_test_put_u32(bad_handle, dynamic_record + 4, 0)
    error, decode_ok = hs.portable_decode(
        portable_test_any(Portable_Dynamic_Scalar_State, &Portable_Dynamic_Scalar_State{}),
        bad_handle,
        alloc = context.allocator,
    )
    testing.expect(t, !decode_ok)
    testing.expect(t, error.kind == .Invalid_Handle)
    hs.portable_error_dispose(&error)
    delete(bad_handle)

    invalid_source := Portable_Dynamic_Scalar_State {
        values = make([dynamic]i32, 1, context.allocator),
    }
    raw := cast(^runtime.Raw_Dynamic_Array)&invalid_source.values
    original_data := raw.data
    raw.cap = 0
    _, invalid_error, encode_ok := hs.portable_encode(
        portable_test_any(Portable_Dynamic_Scalar_State, &invalid_source),
        alloc = context.allocator,
    )
    testing.expect(t, !encode_ok)
    testing.expect(t, invalid_error.kind == .Invalid_Metadata)
    hs.portable_error_dispose(&invalid_error)
    raw.cap = 1
    raw.data = nil
    _, invalid_error, encode_ok = hs.portable_encode(
        portable_test_any(Portable_Dynamic_Scalar_State, &invalid_source),
        alloc = context.allocator,
    )
    testing.expect(t, !encode_ok)
    testing.expect(t, invalid_error.kind == .Invalid_Metadata)
    hs.portable_error_dispose(&invalid_error)
    raw.data = original_data
    raw.len = -1
    raw.cap = -1
    _, invalid_error, encode_ok = hs.portable_encode(
        portable_test_any(Portable_Dynamic_Scalar_State, &invalid_source),
        alloc = context.allocator,
    )
    testing.expect(t, !encode_ok)
    testing.expect(t, invalid_error.kind == .Invalid_Metadata)
    hs.portable_error_dispose(&invalid_error)
    raw.len = 1
    raw.cap = 1
    delete(invalid_source.values)
    delete(dynamic_source.values)
    delete(dynamic_data)

    cycle := portable_test_dynamic_cycle_payload()
    error, decode_ok = hs.portable_decode(
        portable_test_any(Portable_Dynamic_Scalar_State, &Portable_Dynamic_Scalar_State{}),
        cycle,
        alloc = context.allocator,
    )
    testing.expect(t, !decode_ok)
    testing.expect(t, error.kind == .Invalid_Metadata)
    hs.portable_error_dispose(&error)
    delete(cycle)
}

@(test)
hs_portable_recursive_dynamic_encode_rejects_before_body :: proc(t: ^testing.T) {
    source := Portable_Recursive_Node {
        value    = 7,
        children = make([dynamic]Portable_Recursive_Node, 0, context.allocator),
    }
    data, error, ok := hs.portable_encode(
        portable_test_any(Portable_Recursive_Node, &source),
        alloc = context.allocator,
    )
    testing.expect(t, !ok)
    testing.expect(t, data == nil)
    testing.expect(t, error.kind == .Invalid_Metadata)
    cycle := portable_test_dynamic_cycle_payload()
    decode_error, decode_ok := hs.portable_decode(
        portable_test_any(Portable_Dynamic_Scalar_State, &Portable_Dynamic_Scalar_State{}),
        cycle,
        alloc = context.allocator,
    )
    testing.expect(t, !decode_ok)
    testing.expect(t, decode_error.kind == error.kind)
    testing.expect(t, decode_error.message == error.message)
    testing.expect(t, decode_error.path == error.path)
    hs.portable_error_dispose(&decode_error)
    delete(cycle)
    hs.portable_error_dispose(&error)
    delete(source.children)
}

@(test)
hs_portable_dynamic_to_fixed_validates_excess_enum_values :: proc(t: ^testing.T) {
    source := Portable_Dynamic_Enum_State {
        values = make([dynamic]Portable_Mode, 5, context.allocator),
    }
    source.values[0] = .Idle
    source.values[1] = .Sailing
    source.values[2] = .Idle
    source.values[3] = .Sailing
    source.values[4] = .Sailing
    data, error, ok := hs.portable_encode(
        portable_test_any(Portable_Dynamic_Enum_State, &source),
        alloc = context.allocator,
    )
    testing.expect(t, ok)
    testing.expect(t, error.kind == .None)
    if !ok {
        delete(source.values)
        return
    }

    destination := Portable_Fixed_Enum_State{}
    decode_error, decode_ok := hs.portable_decode(
        portable_test_any(Portable_Fixed_Enum_State, &destination),
        data,
        alloc = context.allocator,
    )
    testing.expect(t, decode_ok)
    testing.expect(t, decode_error.kind == .None)
    testing.expect(t, destination.values[0] == .Idle)
    testing.expect(t, destination.values[1] == .Sailing)
    testing.expect(t, destination.values[2] == .Idle)

    bad_excess := portable_test_copy(data)
    body_start := hs.Portable_Header_Size + int(portable_test_u32(data, 20))
    bad_excess[body_start + 8 + 3] = 1
    decode_error, decode_ok = hs.portable_decode(
        portable_test_any(Portable_Fixed_Enum_State, &Portable_Fixed_Enum_State{}),
        bad_excess,
        alloc = context.allocator,
    )
    testing.expect(t, !decode_ok)
    testing.expect(t, decode_error.kind == .Invalid_Metadata)
    hs.portable_error_dispose(&decode_error)
    delete(bad_excess)
    delete(data)
    delete(source.values)
}

@(test)
hs_portable_round_trip :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    source := portable_test_state()
    config := portable_test_fixture_config()
    encoded, encode_error, encode_ok := hs.portable_encode(portable_test_any(Portable_State, &source), config)
    testing.expect(t, encode_ok)
    testing.expect(t, encode_error.kind == .None)
    if !encode_ok do return

    decoded: Portable_State
    decode_error, decode_ok := hs.portable_decode(portable_test_any(Portable_State, &decoded), encoded, config)
    testing.expect(t, decode_ok)
    testing.expect(t, decode_error.kind == .None)
    testing.expect(t, decoded.enabled == source.enabled)
    testing.expect(t, decoded.signed == source.signed)
    testing.expect(t, decoded.unsigned == source.unsigned)
    testing.expect(t, decoded.ratio == source.ratio)
    testing.expect(t, decoded.precise == source.precise)
    testing.expect(t, decoded.text == source.text)
    testing.expect(t, decoded.mode == source.mode)
    testing.expect(t, decoded.count == source.count)
    testing.expect(t, decoded.values == source.values)
    testing.expect(t, decoded.nested.value == source.nested.value)
    testing.expect(t, decoded.nested.label == source.nested.label)
}

@(test)
hs_portable_all_scalar_widths_round_trip :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    source := Portable_Scalar_Widths {
        i8_value   = -8,
        i16_value  = -1600,
        i32_value  = -320000,
        i64_value  = -6400000000,
        u8_value   = 8,
        u16_value  = 1600,
        u32_value  = 320000,
        u64_value  = 6400000000,
        rune_value = 'Ж',
        half_value = f16(1.5),
    }
    encoded, _, encode_ok := hs.portable_encode(portable_test_any(Portable_Scalar_Widths, &source))
    testing.expect(t, encode_ok)
    if !encode_ok do return
    decoded: Portable_Scalar_Widths
    _, decode_ok := hs.portable_decode(portable_test_any(Portable_Scalar_Widths, &decoded), encoded)
    testing.expect(t, decode_ok)
    testing.expect(t, decoded.i8_value == source.i8_value)
    testing.expect(t, decoded.i16_value == source.i16_value)
    testing.expect(t, decoded.i32_value == source.i32_value)
    testing.expect(t, decoded.i64_value == source.i64_value)
    testing.expect(t, decoded.u8_value == source.u8_value)
    testing.expect(t, decoded.u16_value == source.u16_value)
    testing.expect(t, decoded.u32_value == source.u32_value)
    testing.expect(t, decoded.u64_value == source.u64_value)
    testing.expect(t, decoded.rune_value == source.rune_value)
    testing.expect(t, decoded.half_value == source.half_value)
}

@(test)
hs_portable_bytes_are_deterministic :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    a := portable_test_state()
    b := a
    a.nested.hidden_data[0] = 9
    b.nested.hidden_data[0] = 99
    config := portable_test_fixture_config()
    first, _, first_ok := hs.portable_encode(portable_test_any(Portable_State, &a), config)
    second, _, second_ok := hs.portable_encode(portable_test_any(Portable_State, &b), config)
    testing.expect(t, first_ok && second_ok)
    if first_ok && second_ok {
        testing.expect(t, string(first) == string(second))
        testing.expect(t, !strings.contains(string(first), "hidden_data"))
        testing.expect(t, !strings.contains(string(first), "hidden_ptr"))
        testing.expect(t, !strings.contains(string(first), "hidden_list"))
    }
}

@(test)
hs_portable_excluded_unsupported_subtree_is_ignored :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    first_pointer_value := 1
    second_pointer_value := 2
    first_bytes := [2]u8{1, 2}
    second_bytes := [2]u8{3, 4}
    first := Excluded_Unsupported_State {
        value = 17,
        ptr   = &first_pointer_value,
        list  = first_bytes[:],
    }
    second := Excluded_Unsupported_State {
        value = 17,
        ptr   = &second_pointer_value,
        list  = second_bytes[:],
    }
    config := portable_test_fixture_config()
    first_data, first_error, first_ok := hs.portable_encode(
        portable_test_any(Excluded_Unsupported_State, &first),
        config,
    )
    second_data, second_error, second_ok := hs.portable_encode(
        portable_test_any(Excluded_Unsupported_State, &second),
        config,
    )
    testing.expect(t, first_ok && second_ok)
    testing.expect(t, first_error.kind == .None && second_error.kind == .None)
    if first_ok && second_ok {
        testing.expect(t, string(first_data) == string(second_data))
        testing.expect(t, !strings.contains(string(first_data), "ptr"))
        testing.expect(t, !strings.contains(string(first_data), "list"))
    }
}

@(test)
hs_portable_default_policy_is_generic :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    value := Excluded_Unsupported_State {
        value = 17,
        ptr   = nil,
        list  = nil,
    }
    _, error, ok := hs.portable_encode(portable_test_any(Excluded_Unsupported_State, &value))
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Unsupported_Type)
}

@(test)
hs_portable_normal_allocator_owns_only_results :: proc(t: ^testing.T) {
    source := portable_test_state()
    config := portable_test_fixture_config()
    encoded, encode_error, encode_ok := hs.portable_encode(
        portable_test_any(Portable_State, &source),
        config,
        context.allocator,
    )
    testing.expect(t, encode_ok)
    testing.expect(t, encode_error.kind == .None)
    if !encode_ok do return
    decoded: Portable_State
    decode_error, decode_ok := hs.portable_decode(
        portable_test_any(Portable_State, &decoded),
        encoded,
        config,
        context.allocator,
    )
    testing.expect(t, decode_ok)
    testing.expect(t, decode_error.kind == .None)
    delete(encoded)
    delete(decoded.text)
    delete(decoded.nested.label)
}

@(test)
hs_portable_decoded_string_allocation_failure_cleans_scratch :: proc(t: ^testing.T) {
    source := portable_test_state()
    config := portable_test_fixture_config()
    encoded, _, encode_ok := hs.portable_encode(portable_test_any(Portable_State, &source), config, context.allocator)
    testing.expect(t, encode_ok)
    if !encode_ok do return

    probe := Portable_Test_Counting_Allocator {
        backing = context.allocator,
        fail_at = -1,
    }
    probe_allocator := mem.Allocator {
        procedure = portable_test_counting_allocator_proc,
        data      = rawptr(&probe),
    }
    decoded: Portable_State
    _, probe_ok := hs.portable_decode(portable_test_any(Portable_State, &decoded), encoded, config, probe_allocator)
    testing.expect(t, probe_ok)
    testing.expect(t, probe.allocs >= 2)
    delete(decoded.text)
    delete(decoded.nested.label)

    failing := Portable_Test_Counting_Allocator {
        backing = context.allocator,
        fail_at = probe.allocs - 1,
    }
    failing_allocator := mem.Allocator {
        procedure = portable_test_counting_allocator_proc,
        data      = rawptr(&failing),
    }
    partial: Portable_State
    error, decode_ok := hs.portable_decode(
        portable_test_any(Portable_State, &partial),
        encoded,
        config,
        failing_allocator,
    )
    testing.expect(t, !decode_ok)
    testing.expect(t, error.kind == .Limit_Exceeded)
    portable_test_dispose_error(&error)
    delete(partial.text)
    delete(partial.nested.label)
    delete(encoded)
}

@(test)
hs_portable_failure_cleanup_uses_normal_allocator :: proc(t: ^testing.T) {
    source := portable_test_state()
    fixture_config := portable_test_fixture_config()
    baseline, _, baseline_ok := hs.portable_encode(
        portable_test_any(Portable_State, &source),
        fixture_config,
        context.allocator,
    )
    testing.expect(t, baseline_ok)
    if !baseline_ok do return

    _, error, ok := hs.portable_encode(
        portable_test_any(Bad_Pointer_State, &Bad_Pointer_State{}),
        portable_test_fixture_config(),
        context.allocator,
    )
    testing.expect(t, !ok)
    portable_test_dispose_error(&error)

    config := portable_test_fixture_config()
    config.limits.max_string_bytes = 1
    _, error, ok = hs.portable_encode(portable_test_any(Portable_State, &source), config, context.allocator)
    testing.expect(t, !ok)
    portable_test_dispose_error(&error)

    bad_table := portable_test_copy(baseline)
    bad_table[hs.Portable_Header_Size + 3] = 1
    error, ok = hs.portable_decode(
        portable_test_any(Portable_State, &Portable_State{}),
        bad_table,
        fixture_config,
        context.allocator,
    )
    testing.expect(t, !ok)
    portable_test_dispose_error(&error)
    delete(bad_table)

    config.limits.max_payload = hs.Portable_Header_Size
    _, error, ok = hs.portable_encode(portable_test_any(Portable_State, &source), config, context.allocator)
    testing.expect(t, !ok)
    portable_test_dispose_error(&error)
    delete(baseline)
}

@(test)
hs_portable_moderate_array_has_bounded_payload_walk :: proc(t: ^testing.T) {
    value := Portable_Moderate_Array{}
    for i in 0 ..< len(value.bytes) {
        value.bytes[i] = u8(i)
    }
    encoded, error, ok := hs.portable_encode(
        portable_test_any(Portable_Moderate_Array, &value),
        hs.portable_default_config(),
        context.allocator,
    )
    testing.expect(t, ok)
    testing.expect(t, error.kind == .None)
    if !ok do return
    decoded: Portable_Moderate_Array
    _, decode_ok := hs.portable_decode(
        portable_test_any(Portable_Moderate_Array, &decoded),
        encoded,
        hs.portable_default_config(),
        context.allocator,
    )
    testing.expect(t, decode_ok)
    testing.expect(t, decoded.bytes == value.bytes)
    delete(encoded)
}

@(test)
hs_portable_unexcluded_pointer_reports_path :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    value := Bad_Pointer_State {
        value = 17,
        ptr   = nil,
    }
    _, error, ok := hs.portable_encode(portable_test_any(Bad_Pointer_State, &value))
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Unsupported_Type)
    testing.expect(t, strings.contains(error.path, "$.ptr"))
    testing.expect(t, error.path_owned)
    portable_test_dispose_error(&error)
    portable_test_dispose_error(&error)
    testing.expect(t, !error.path_owned)
}

@(test)
hs_portable_additive_structs_are_safe :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    source := Portable_Additive_Source {
        kept    = 42,
        removed = 99,
    }
    encoded, _, encode_ok := hs.portable_encode(portable_test_any(Portable_Additive_Source, &source))
    testing.expect(t, encode_ok)
    if !encode_ok do return
    destination := Portable_Additive_Destination{}
    error, decode_ok := hs.portable_decode(portable_test_any(Portable_Additive_Destination, &destination), encoded)
    testing.expect(t, decode_ok)
    testing.expect(t, error.kind == .None)
    testing.expect(t, destination.kept == source.kept)
    testing.expect(t, destination.added == "")

    exact_config := hs.portable_default_config()
    testing.expect(t, !exact_config.exact_schema)
    exact_config.exact_schema = true
    exact_destination := Portable_Additive_Source {
        kept    = -1,
        removed = -2,
    }
    error, decode_ok = hs.portable_decode(
        portable_test_any(Portable_Additive_Source, &exact_destination),
        encoded,
        exact_config,
        context.allocator,
    )
    testing.expect(t, decode_ok)
    testing.expect(t, error.kind == .None)
    testing.expect(t, exact_destination == source)
    portable_test_dispose_error(&error)

    incompatible_destination := Portable_Additive_Destination {
        kept  = -11,
        added = "unchanged",
    }
    error, decode_ok = hs.portable_decode(
        portable_test_any(Portable_Additive_Destination, &incompatible_destination),
        encoded,
        exact_config,
        context.allocator,
    )
    testing.expect(t, !decode_ok)
    testing.expect(t, error.kind == .Type_Mismatch)
    testing.expect(t, error.path == "$table")
    testing.expect(t, incompatible_destination.kept == -11)
    testing.expect(t, incompatible_destination.added == "unchanged")
    portable_test_dispose_error(&error)
    portable_test_dispose_error(&error)

    missing_source := Portable_Additive_Destination {
        kept  = 17,
        added = "saved",
    }
    missing_data, missing_encode_error, missing_encode_ok := hs.portable_encode(
        portable_test_any(Portable_Additive_Destination, &missing_source),
        hs.portable_default_config(),
        context.allocator,
    )
    testing.expect(t, missing_encode_ok)
    testing.expect(t, missing_encode_error.kind == .None)
    if missing_encode_ok {
        missing_destination := Portable_Additive_Source {
            kept    = -21,
            removed = -22,
        }
        error, decode_ok = hs.portable_decode(
            portable_test_any(Portable_Additive_Source, &missing_destination),
            missing_data,
            exact_config,
            context.allocator,
        )
        testing.expect(t, !decode_ok)
        testing.expect(t, error.kind == .Type_Mismatch)
        testing.expect(t, missing_destination.kept == -21 && missing_destination.removed == -22)
        portable_test_dispose_error(&error)
        delete(missing_data)
    }

    fixed_source := Portable_Fixed_Scalar_State {
        values = {7, 8, 9},
    }
    fixed_data, fixed_encode_error, fixed_encode_ok := hs.portable_encode(
        portable_test_any(Portable_Fixed_Scalar_State, &fixed_source),
        hs.portable_default_config(),
        context.allocator,
    )
    testing.expect(t, fixed_encode_ok)
    testing.expect(t, fixed_encode_error.kind == .None)
    if fixed_encode_ok {
        dynamic_destination := Portable_Dynamic_Scalar_State{}
        error, decode_ok = hs.portable_decode(
            portable_test_any(Portable_Dynamic_Scalar_State, &dynamic_destination),
            fixed_data,
            exact_config,
            context.allocator,
        )
        testing.expect(t, !decode_ok)
        testing.expect(t, error.kind == .Type_Mismatch)
        testing.expect(t, dynamic_destination.values == nil)
        portable_test_dispose_error(&error)
        delete(fixed_data)
    }

    mode_source := Portable_Exact_Mode_Source {
        mode = .Sailing,
    }
    mode_data, mode_encode_error, mode_encode_ok := hs.portable_encode(
        portable_test_any(Portable_Exact_Mode_Source, &mode_source),
        hs.portable_default_config(),
        context.allocator,
    )
    testing.expect(t, mode_encode_ok)
    testing.expect(t, mode_encode_error.kind == .None)
    if mode_encode_ok {
        mode_destination := Portable_Exact_Mode_Destination {
            mode = .Docked,
        }
        error, decode_ok = hs.portable_decode(
            portable_test_any(Portable_Exact_Mode_Destination, &mode_destination),
            mode_data,
            exact_config,
            context.allocator,
        )
        testing.expect(t, !decode_ok)
        testing.expect(t, error.kind == .Type_Mismatch)
        testing.expect(t, mode_destination.mode == .Docked)
        portable_test_dispose_error(&error)
        delete(mode_data)
    }

    malformed_header := portable_test_copy(encoded)
    portable_test_put_u16(malformed_header, 8, hs.Portable_Version + 1)
    malformed_destination := Portable_Additive_Source {
        kept    = -31,
        removed = -32,
    }
    error, decode_ok = hs.portable_decode(
        portable_test_any(Portable_Additive_Source, &malformed_destination),
        malformed_header,
        exact_config,
        context.allocator,
    )
    testing.expect(t, !decode_ok)
    testing.expect(t, error.kind == .Invalid_Header)
    testing.expect(t, malformed_destination.kept == -31 && malformed_destination.removed == -32)
    portable_test_dispose_error(&error)
    delete(malformed_header)

    malformed_table := portable_test_copy(encoded)
    malformed_table[hs.Portable_Header_Size + 3] = 1
    error, decode_ok = hs.portable_decode(
        portable_test_any(Portable_Additive_Source, &malformed_destination),
        malformed_table,
        exact_config,
        context.allocator,
    )
    testing.expect(t, !decode_ok)
    testing.expect(t, error.kind == .Invalid_Metadata)
    testing.expect(t, malformed_destination.kept == -31 && malformed_destination.removed == -32)
    portable_test_dispose_error(&error)
    delete(malformed_table)

    nil_allocator_destination := Portable_Additive_Source {
        kept    = -41,
        removed = -42,
    }
    error, decode_ok = hs.portable_decode(
        portable_test_any(Portable_Additive_Source, &nil_allocator_destination),
        encoded,
        exact_config,
        mem.Allocator{},
    )
    testing.expect(t, !decode_ok)
    testing.expect(t, error.kind == .Invalid_Argument)
    testing.expect(t, nil_allocator_destination.kept == -41 && nil_allocator_destination.removed == -42)
    portable_test_dispose_error(&error)
    portable_test_dispose_error(&error)

    probe_state := Portable_Test_Counting_Allocator {
        backing = runtime.default_allocator(),
        fail_at = -1,
    }
    probe_allocator := mem.Allocator {
        procedure = portable_test_counting_allocator_proc,
        data      = rawptr(&probe_state),
    }
    probe_destination := Portable_Additive_Source{}
    error, decode_ok = hs.portable_decode(
        portable_test_any(Portable_Additive_Source, &probe_destination),
        encoded,
        exact_config,
        probe_allocator,
    )
    testing.expect(t, decode_ok)
    testing.expect(t, error.kind == .None)
    testing.expect(t, probe_destination == source)
    testing.expect(t, probe_state.allocs > 0)
    testing.expect(t, probe_state.outstanding == 0)
    portable_test_dispose_error(&error)

    for fail_at in 0 ..< probe_state.allocs {
        failing_state := Portable_Test_Counting_Allocator {
            backing = runtime.default_allocator(),
            fail_at = fail_at,
        }
        failing_allocator := mem.Allocator {
            procedure = portable_test_counting_allocator_proc,
            data      = rawptr(&failing_state),
        }
        failing_destination := Portable_Additive_Source {
            kept    = -51,
            removed = -52,
        }
        error, decode_ok = hs.portable_decode(
            portable_test_any(Portable_Additive_Source, &failing_destination),
            encoded,
            exact_config,
            failing_allocator,
        )
        testing.expect(t, !decode_ok)
        testing.expect(t, error.kind == .Limit_Exceeded)
        testing.expect(t, failing_destination.kept == -51 && failing_destination.removed == -52)
        portable_test_dispose_error(&error)
        portable_test_dispose_error(&error)
        testing.expect(t, failing_state.outstanding == 0)
    }
}

@(test)
hs_portable_truncation_and_trailing_bytes_fail :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    source := portable_test_state()
    config := portable_test_fixture_config()
    encoded, _, encode_ok := hs.portable_encode(portable_test_any(Portable_State, &source), config)
    testing.expect(t, encode_ok)
    if !encode_ok do return
    for length in 0 ..< len(encoded) {
        _, ok := hs.portable_decode(portable_test_any(Portable_State, &Portable_State{}), encoded[:length], config)
        testing.expect(t, !ok)
    }
    trailing := make([]byte, len(encoded) + 1, context.allocator)
    copy(trailing, encoded)
    _, trailing_ok := hs.portable_decode(portable_test_any(Portable_State, &Portable_State{}), trailing, config)
    testing.expect(t, !trailing_ok)
}

@(test)
hs_portable_corrupt_header_and_handles_fail :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    source := portable_test_state()
    config := portable_test_fixture_config()
    encoded, _, encode_ok := hs.portable_encode(portable_test_any(Portable_State, &source), config)
    testing.expect(t, encode_ok)
    if !encode_ok do return

    bad_root := portable_test_copy(encoded)
    portable_test_put_u32(bad_root, 12, 0)
    _, ok := hs.portable_decode(portable_test_any(Portable_State, &Portable_State{}), bad_root, config)
    testing.expect(t, !ok)

    bad_types := portable_test_copy(encoded)
    portable_test_put_u32(bad_types, 16, 0)
    _, ok = hs.portable_decode(portable_test_any(Portable_State, &Portable_State{}), bad_types, config)
    testing.expect(t, !ok)

    bad_table := portable_test_copy(encoded)
    portable_test_put_u32(bad_table, 20, 0xffff_ffff)
    _, ok = hs.portable_decode(portable_test_any(Portable_State, &Portable_State{}), bad_table, config)
    testing.expect(t, !ok)

    bad_body := portable_test_copy(encoded)
    portable_test_put_u32(bad_body, 24, 0xffff_ffff)
    _, ok = hs.portable_decode(portable_test_any(Portable_State, &Portable_State{}), bad_body, config)
    testing.expect(t, !ok)

    table_bytes := int(portable_test_u32(encoded, 20))
    bad_field_handle := portable_test_copy(encoded)
    table_start := hs.Portable_Header_Size
    field_count := int(portable_test_u32(bad_field_handle, table_start + 4))
    testing.expect(t, field_count == 10)
    name_length_offset := table_start + 8
    name_length := int(portable_test_u32(bad_field_handle, name_length_offset))
    testing.expect(t, name_length == len("enabled"))
    handle_offset := name_length_offset + 4 + name_length
    testing.expect(t, handle_offset + 4 <= table_start + table_bytes)
    portable_test_put_u32(bad_field_handle, handle_offset, 0)
    _, ok = hs.portable_decode(portable_test_any(Portable_State, &Portable_State{}), bad_field_handle, config)
    testing.expect(t, !ok)

    bad_reserved := portable_test_copy(encoded)
    bad_reserved[table_start + 3] = 1
    _, ok = hs.portable_decode(portable_test_any(Portable_State, &Portable_State{}), bad_reserved, config)
    testing.expect(t, !ok)

    bad_utf8 := portable_test_copy(encoded)
    bad_utf8[table_start + 12] = 0xff
    _, ok = hs.portable_decode(portable_test_any(Portable_State, &Portable_State{}), bad_utf8, config)
    testing.expect(t, !ok)

    bad_array_count := portable_test_copy(encoded)
    array_record := portable_test_find_type_record(bad_array_count, .Array)
    testing.expect(t, array_record >= 0)
    portable_test_put_u64(bad_array_count, array_record + 8, u64(max(u64)))
    _, ok = hs.portable_decode(portable_test_any(Portable_State, &Portable_State{}), bad_array_count, config)
    testing.expect(t, !ok)

    bad_width := portable_test_copy(encoded)
    width_record := portable_test_find_type_record(bad_width, .Signed)
    testing.expect(t, width_record >= 0)
    bad_width[width_record + 1] = 3
    _, ok = hs.portable_decode(portable_test_any(Portable_State, &Portable_State{}), bad_width, config)
    testing.expect(t, !ok)

    bad_string_length := portable_test_copy(encoded)
    text_offset := strings.index(string(bad_string_length), source.text)
    testing.expect(t, text_offset >= 4)
    portable_test_put_u32(bad_string_length, text_offset - 4, 0xffff_ffff)
    _, ok = hs.portable_decode(portable_test_any(Portable_State, &Portable_State{}), bad_string_length, config)
    testing.expect(t, !ok)

    bad_enum := portable_test_copy(encoded)
    enum_record := portable_test_find_type_record(bad_enum, .Enum)
    testing.expect(t, enum_record >= 0)
    bad_enum[enum_record + 1] = 1
    _, ok = hs.portable_decode(portable_test_any(Portable_State, &Portable_State{}), bad_enum, config)
    testing.expect(t, !ok)

    bad_enum_base := portable_test_copy(encoded)
    portable_test_put_u32(bad_enum_base, enum_record + 4, 1)
    _, ok = hs.portable_decode(portable_test_any(Portable_State, &Portable_State{}), bad_enum_base, config)
    testing.expect(t, !ok)

    bad_enum_body := portable_test_copy(encoded)
    body_start := hs.Portable_Header_Size + table_bytes
    mode_offset := body_start + 1 + 2 + 8 + 4 + 8 + 4 + len(source.text)
    bad_enum_body[mode_offset] = 2
    _, ok = hs.portable_decode(portable_test_any(Portable_State, &Portable_State{}), bad_enum_body, config)
    testing.expect(t, !ok)
}

@(test)
hs_portable_self_cycle_rejected_before_body_walk :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    payload := portable_test_self_cycle_payload()
    error, ok := hs.portable_decode(portable_test_any(Portable_State, &Portable_State{}), payload)
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Invalid_Metadata)
}

@(test)
hs_portable_type_graph_depth_is_bounded :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    payload := portable_test_deep_chain_payload()
    error, ok := hs.portable_decode(portable_test_any(Portable_State, &Portable_State{}), payload)
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Limit_Exceeded)
    hs.portable_error_dispose(&error)
}

@(test)
hs_portable_duplicate_table_names_clean_partial_records :: proc(t: ^testing.T) {
    struct_source := Portable_Duplicate_Struct {
        abcd = 11,
        wxyz = 22,
    }
    struct_data, struct_encode_error, struct_encode_ok := hs.portable_encode(
        portable_test_any(Portable_Duplicate_Struct, &struct_source),
        hs.portable_default_config(),
        context.allocator,
    )
    testing.expect(t, struct_encode_ok)
    testing.expect(t, struct_encode_error.kind == .None)
    if !struct_encode_ok do return
    struct_record := portable_test_find_type_record(struct_data, .Struct)
    testing.expect(t, struct_record >= 0)
    first_name_length := int(portable_test_u32(struct_data, struct_record + 8))
    first_name_offset := struct_record + 12
    first_handle_offset := first_name_offset + first_name_length
    second_name_length_offset := first_handle_offset + 4
    second_name_offset := second_name_length_offset + 4
    second_name_length := int(portable_test_u32(struct_data, second_name_length_offset))
    testing.expect(t, first_name_length == 4)
    testing.expect(t, second_name_length == 4)
    copy(
        struct_data[second_name_offset:second_name_offset + second_name_length],
        struct_data[first_name_offset:first_name_offset + first_name_length],
    )
    struct_destination := Portable_Duplicate_Struct{}
    struct_error, struct_ok := hs.portable_decode(
        portable_test_any(Portable_Duplicate_Struct, &struct_destination),
        struct_data,
        hs.portable_default_config(),
        context.allocator,
    )
    testing.expect(t, !struct_ok)
    testing.expect(t, struct_error.kind == .Invalid_Metadata)
    hs.portable_error_dispose(&struct_error)
    delete(struct_data)

    enum_source := Portable_Duplicate_Enum.ABCD
    enum_data, enum_encode_error, enum_encode_ok := hs.portable_encode(
        portable_test_any(Portable_Duplicate_Enum, &enum_source),
        hs.portable_default_config(),
        context.allocator,
    )
    testing.expect(t, enum_encode_ok)
    testing.expect(t, enum_encode_error.kind == .None)
    if !enum_encode_ok do return
    enum_record := portable_test_find_type_record(enum_data, .Enum)
    testing.expect(t, enum_record >= 0)
    first_enum_name_length := int(portable_test_u32(enum_data, enum_record + 12))
    first_enum_name_offset := enum_record + 16
    first_enum_value_offset := first_enum_name_offset + first_enum_name_length
    second_enum_name_length_offset := first_enum_value_offset + 8
    second_enum_name_offset := second_enum_name_length_offset + 4
    second_enum_name_length := int(portable_test_u32(enum_data, second_enum_name_length_offset))
    testing.expect(t, first_enum_name_length == 4)
    testing.expect(t, second_enum_name_length == 4)
    copy(
        enum_data[second_enum_name_offset:second_enum_name_offset + second_enum_name_length],
        enum_data[first_enum_name_offset:first_enum_name_offset + first_enum_name_length],
    )
    enum_destination := Portable_Duplicate_Enum.ABCD
    enum_error, enum_ok := hs.portable_decode(
        portable_test_any(Portable_Duplicate_Enum, &enum_destination),
        enum_data,
        hs.portable_default_config(),
        context.allocator,
    )
    testing.expect(t, !enum_ok)
    testing.expect(t, enum_error.kind == .Invalid_Metadata)
    hs.portable_error_dispose(&enum_error)
    delete(enum_data)
}

@(test)
hs_portable_limits_fail_before_large_allocations :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    source := portable_test_state()
    config := hs.portable_default_config()
    config.limits.max_string_bytes = 0
    fixture_config := portable_test_fixture_config()
    config.exclusion_tag = fixture_config.exclusion_tag
    _, error, ok := hs.portable_encode(portable_test_any(Portable_State, &source), config)
    _ = error
    testing.expect(t, !ok)

    config = hs.portable_default_config()
    config.limits.max_payload = 8
    _, error, ok = hs.portable_encode(portable_test_any(Portable_State, &source), config)
    _ = error
    testing.expect(t, !ok)

    config = hs.portable_default_config()
    config.limits.max_recursion_depth = hs.PORTABLE_SAFE_MAX_RECURSION_DEPTH + 1
    _, error, ok = hs.portable_encode(portable_test_any(Portable_State, &source), config)
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Limit_Exceeded)

    config = hs.portable_default_config()
    config.limits.max_recursion_depth = 0
    _, error, ok = hs.portable_encode(portable_test_any(Portable_State, &source), config)
    _ = error
    testing.expect(t, !ok)

    config = hs.portable_default_config()
    config.exclusion_tag = "fixture"
    config.limits.max_payload = int(max(u32)) + 1
    _, error, ok = hs.portable_encode(portable_test_any(Portable_State, &source), config)
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Overflow)
}

@(test)
hs_portable_nil_allocator_is_rejected :: proc(t: ^testing.T) {
    source := Portable_Scalar_Widths{}
    nil_allocator := mem.Allocator{}
    _, error, ok := hs.portable_encode(
        portable_test_any(Portable_Scalar_Widths, &source),
        hs.portable_default_config(),
        nil_allocator,
    )
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Invalid_Argument)
    error, ok = hs.portable_decode(
        portable_test_any(Portable_Scalar_Widths, &source),
        nil,
        hs.portable_default_config(),
        nil_allocator,
    )
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Invalid_Argument)
}

@(test)
hs_portable_representative_binary_is_smaller_than_toml :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    value := Portable_Representative {
        name = "adriatic",
    }
    for i in 0 ..< len(value.bytes) {
        value.bytes[i] = u8(i * 3)
        value.floats[i] = f32(i) * 1234.567 - 98765.4321
    }
    value.nested.value = 12
    value.nested.label = "harbor"
    encoded, _, ok := hs.portable_encode(
        portable_test_any(Portable_Representative, &value),
        portable_test_fixture_config(),
    )
    testing.expect(t, ok)
    if !ok do return
    mirror := Portable_Toml_Representative {
        name = value.name,
        bytes = value.bytes,
        floats = value.floats,
        nested = {value = value.nested.value, label = value.nested.label},
    }
    table := toml.marshal(&mirror, context.allocator)
    defer toml.deep_delete(table, context.allocator)
    emitted := toml.emit(table)
    testing.expect(t, len(encoded) * 2 <= len(emitted))
}
