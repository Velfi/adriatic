package tests

import "base:runtime"
import "core:mem"
import "core:strings"
import "core:testing"
import hs "zelda_engine:hs"
import toml "zelda_engine:toml"

#assert(int(hs.Portable_Kind.Invalid) == 0)
#assert(int(hs.Portable_Kind.Bool) == 1)
#assert(int(hs.Portable_Kind.Signed) == 2)
#assert(int(hs.Portable_Kind.Unsigned) == 3)
#assert(int(hs.Portable_Kind.Rune) == 4)
#assert(int(hs.Portable_Kind.Float) == 5)
#assert(int(hs.Portable_Kind.String) == 6)
#assert(int(hs.Portable_Kind.Struct) == 7)
#assert(int(hs.Portable_Kind.Array) == 8)
#assert(int(hs.Portable_Kind.Enum) == 9)
#assert(int(hs.Portable_Kind.Dynamic_Array) == 10)
#assert(int(hs.Portable_Kind.Enumerated_Array) == 11)
#assert(int(hs.Portable_Kind.Quaternion) == 12)
#assert(size_of(runtime.Raw_Quaternion64) == 8)
#assert(align_of(runtime.Raw_Quaternion64) == 2)
#assert(offset_of(runtime.Raw_Quaternion64, imag) == 0)
#assert(offset_of(runtime.Raw_Quaternion64, jmag) == 2)
#assert(offset_of(runtime.Raw_Quaternion64, kmag) == 4)
#assert(offset_of(runtime.Raw_Quaternion64, real) == 6)
#assert(size_of(runtime.Raw_Quaternion128) == 16)
#assert(align_of(runtime.Raw_Quaternion128) == 4)
#assert(offset_of(runtime.Raw_Quaternion128, imag) == 0)
#assert(offset_of(runtime.Raw_Quaternion128, jmag) == 4)
#assert(offset_of(runtime.Raw_Quaternion128, kmag) == 8)
#assert(offset_of(runtime.Raw_Quaternion128, real) == 12)

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

Portable_Retain_Tag_Source :: struct {
    value:     i32,
    map_value: i32 `fixture:"-" fixture_map:"-"`,
    scratch:   i32 `fixture:"-"`,
}

Portable_Additive_Source :: struct {
    kept:    i32,
    removed: i32,
}

Portable_Additive_Destination :: struct {
    kept:  i32,
    added: string,
}

Portable_Exact_Short_Field :: struct {
    a: i32,
}

Portable_Exact_Long_Field :: struct {
    substantially_longer_field_name: i32,
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

Portable_Bulk_Fixed_Nested :: struct {
    bytes:  [3]u8,
    floats: [3]f32,
}

Portable_Bulk_Fixed_Arrays :: struct {
    bytes:  [4]u8,
    floats: [3]f32,
    nested: Portable_Bulk_Fixed_Nested,
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

Portable_Enumerated_Index :: enum i8 {
    Lower = 3,
    Middle,
    Upper,
}

Portable_Enumerated_Other_Index :: enum i8 {
    Alpha = 3,
    Beta,
    Gamma,
}

Portable_Enumerated_State :: struct {
    values: [Portable_Enumerated_Index]u64,
}

Portable_Enumerated_Other_State :: struct {
    values: [Portable_Enumerated_Other_Index]u64,
}

Portable_Enumerated_Negative_Index :: enum i8 {
    Low = -2,
    Center,
    High,
}

Portable_Enumerated_Negative_State :: struct {
    values: [Portable_Enumerated_Negative_Index]u64,
}

Portable_Enumerated_Plain_State :: struct {
    values: [3]u64,
}

Portable_Story_Index :: enum u8 {
    R0,
    R1,
    R2,
    R3,
    R4,
    R5,
    R6,
    R7,
    R8,
    R9,
    R10,
}

Portable_Story_Enumerated_State :: struct {
    values: [Portable_Story_Index]u64,
}

Portable_Enumerated_Allocation_One :: struct {
    values: [1][Portable_Enumerated_Index]u64,
}

Portable_Enumerated_Allocation_Many :: struct {
    values: [128][Portable_Enumerated_Index]u64,
}

Portable_Recursive_Node :: struct {
    value:    i32,
    children: [dynamic]Portable_Recursive_Node,
}

Portable_Quaternion_Index :: enum i8 {
    Lower = 3,
    Middle,
    Upper,
}

Portable_Quaternion_Nested :: struct {
    rotation: quaternion128,
}

Portable_Quaternion_Composite :: struct {
    nested:         Portable_Quaternion_Nested,
    fixed:          [2]quaternion64,
    indexed:        [Portable_Quaternion_Index]quaternion128,
    dynamic_values: [dynamic]quaternion64,
}

Portable_Quaternion_Extra_Source :: struct {
    rotation: quaternion128,
    kept:     u32,
}

Portable_Quaternion_Extra_Destination :: struct {
    kept: u32,
}

Portable_Quaternion_Missing_Source :: struct {
    kept: u32,
}

Portable_Quaternion_Missing_Destination :: struct {
    rotation: quaternion128,
    kept:     u32,
}

Portable_Quaternion128_Field :: struct {
    rotation: quaternion128,
}

Portable_Quaternion64_Field :: struct {
    rotation: quaternion64,
}

Portable_Quaternion_Array_Field :: struct {
    rotation: [4]f32,
}

Portable_Quaternion_Scalar_Field :: struct {
    rotation: f32,
}

Portable_Quaternion_Fixed_One :: struct {
    values: [1]quaternion128,
}

Portable_Quaternion_Fixed_Many :: struct {
    values: [128]quaternion128,
}

Portable_Quaternion_Dynamic :: struct {
    values: [dynamic]quaternion128,
}

Portable_Test_Counting_Allocator :: struct {
    backing:     mem.Allocator,
    allocs:      int,
    outstanding: int,
    fail_at:     int,
}

Portable_Test_One_Shot_Allocator :: struct {
    backing:     mem.Allocator,
    allocs:      int,
    outstanding: int,
    fail_at:     int,
    failed:      bool,
}

Portable_Test_All_Fault_Allocator :: struct {
    backing:     mem.Allocator,
    attempts:    int,
    fail_at:     int,
    outstanding: int,
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

portable_test_one_shot_allocator_proc :: proc(
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
    state := (^Portable_Test_One_Shot_Allocator)(allocator_data)
    if (mode == .Alloc || mode == .Alloc_Non_Zeroed) &&
       !state.failed &&
       state.fail_at >= 0 &&
       state.allocs >= state.fail_at {
        state.failed = true
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

portable_test_all_fault_allocator_proc :: proc(
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
    state := (^Portable_Test_All_Fault_Allocator)(allocator_data)
    allocation := mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize || mode == .Resize_Non_Zeroed
    if allocation {
        attempt := state.attempts
        state.attempts += 1
        if state.fail_at >= 0 && attempt == state.fail_at do return nil, .Out_Of_Memory
    }
    result, err := state.backing.procedure(state.backing.data, mode, size, alignment, old_memory, old_size, location)
    if err == nil {
        switch mode {
        case .Alloc, .Alloc_Non_Zeroed:
            if result != nil do state.outstanding += 1
        case .Free:
            if old_memory != nil do state.outstanding -= 1
        case .Free_All:
            state.outstanding = 0
        case .Resize, .Resize_Non_Zeroed:
            if old_memory == nil && result != nil do state.outstanding += 1
            if old_memory != nil && result == nil do state.outstanding -= 1
        case .Query_Features, .Query_Info:
        }
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

portable_test_fixture_map_config :: proc() -> hs.Portable_Config {
    config := portable_test_fixture_config()
    config.retain_tag = "fixture_map"
    return config
}

@(test)
hs_portable_retain_tag_keeps_only_explicit_fixture_map_fields :: proc(t: ^testing.T) {
    source := Portable_Retain_Tag_Source {
        value     = 71,
        map_value = 72,
        scratch   = 73,
    }

    normal, normal_error, normal_ok := hs.portable_encode(
        portable_test_any(Portable_Retain_Tag_Source, &source),
        portable_test_fixture_config(),
        context.allocator,
    )
    testing.expect(t, normal_ok && normal_error.kind == .None)
    if normal_ok {
        defer delete(normal)
        normal_destination := Portable_Retain_Tag_Source{}
        decode_error, decode_ok := hs.portable_decode(
            portable_test_any(Portable_Retain_Tag_Source, &normal_destination),
            normal,
            portable_test_fixture_config(),
            context.allocator,
        )
        testing.expect(t, decode_ok && decode_error.kind == .None)
        hs.portable_error_dispose(&decode_error)
        testing.expect(t, normal_destination.value == source.value)
        testing.expect(t, normal_destination.map_value == 0)
        testing.expect(t, normal_destination.scratch == 0)
    }
    hs.portable_error_dispose(&normal_error)

    projection_config := portable_test_fixture_map_config()
    first, first_error, first_ok := hs.portable_encode(
        portable_test_any(Portable_Retain_Tag_Source, &source),
        projection_config,
        context.allocator,
    )
    second, second_error, second_ok := hs.portable_encode(
        portable_test_any(Portable_Retain_Tag_Source, &source),
        projection_config,
        context.allocator,
    )
    testing.expect(t, first_ok && first_error.kind == .None)
    testing.expect(t, second_ok && second_error.kind == .None)
    if first_ok && second_ok {
        defer delete(first)
        defer delete(second)
        testing.expect(t, len(first) == len(second))
        for index in 0 ..< min(len(first), len(second)) {
            testing.expect(t, first[index] == second[index])
        }

        projection_destination := Portable_Retain_Tag_Source{}
        decode_error, decode_ok := hs.portable_decode(
            portable_test_any(Portable_Retain_Tag_Source, &projection_destination),
            first,
            projection_config,
            context.allocator,
        )
        testing.expect(t, decode_ok && decode_error.kind == .None)
        hs.portable_error_dispose(&decode_error)
        testing.expect(t, projection_destination.value == source.value)
        testing.expect(t, projection_destination.map_value == source.map_value)
        testing.expect(t, projection_destination.scratch == 0)
    } else {
        if first_ok do delete(first)
        if second_ok do delete(second)
    }
    hs.portable_error_dispose(&first_error)
    hs.portable_error_dispose(&second_error)
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

portable_test_put_i64 :: proc(data: []byte, offset: int, value: i64) {
    portable_test_put_u64(data, offset, cast(u64)value)
}

portable_test_quaternion64 :: proc(bits: [4]u16) -> quaternion64 {
    raw := runtime.Raw_Quaternion64 {
        imag = transmute(f16)bits[0],
        jmag = transmute(f16)bits[1],
        kmag = transmute(f16)bits[2],
        real = transmute(f16)bits[3],
    }
    return transmute(quaternion64)raw
}

portable_test_quaternion128 :: proc(bits: [4]u32) -> quaternion128 {
    raw := runtime.Raw_Quaternion128 {
        imag = transmute(f32)bits[0],
        jmag = transmute(f32)bits[1],
        kmag = transmute(f32)bits[2],
        real = transmute(f32)bits[3],
    }
    return transmute(quaternion128)raw
}

portable_test_quaternion64_bits :: proc(value: quaternion64) -> [4]u16 {
    raw := transmute(runtime.Raw_Quaternion64)value
    return {transmute(u16)raw.imag, transmute(u16)raw.jmag, transmute(u16)raw.kmag, transmute(u16)raw.real}
}

portable_test_quaternion128_bits :: proc(value: quaternion128) -> [4]u32 {
    raw := transmute(runtime.Raw_Quaternion128)value
    return {transmute(u32)raw.imag, transmute(u32)raw.jmag, transmute(u32)raw.kmag, transmute(u32)raw.real}
}

portable_test_bytes_equal :: proc(a, b: []byte) -> bool {
    if len(a) != len(b) do return false
    for value, index in a {
        if value != b[index] do return false
    }
    return true
}

portable_test_body_start :: proc(data: []byte) -> int {
    return hs.Portable_Header_Size + int(portable_test_u32(data, 20))
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
        case .Enumerated_Array:
            cursor += 16
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

portable_test_enum_value_offset :: proc(data: []byte, enum_record, field_index: int) -> int {
    cursor := enum_record + 12
    field_count := int(portable_test_u32(data, enum_record + 8))
    if field_index < 0 || field_index >= field_count do return -1
    for index in 0 ..< field_count {
        name_length := int(portable_test_u32(data, cursor))
        value_offset := cursor + 4 + name_length
        if index == field_index do return value_offset
        cursor = value_offset + 8
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
hs_portable_enumerated_arrays_round_trip_and_preserve_index_semantics :: proc(t: ^testing.T) {
    testing.expect(t, u8(hs.Portable_Kind.Array) == 8)
    testing.expect(t, u8(hs.Portable_Kind.Enum) == 9)
    testing.expect(t, u8(hs.Portable_Kind.Dynamic_Array) == 10)
    testing.expect(t, u8(hs.Portable_Kind.Enumerated_Array) == 11)

    source := Portable_Enumerated_State{}
    source.values[.Lower] = 31
    source.values[.Middle] = 41
    source.values[.Upper] = 59
    first, first_error, first_ok := hs.portable_encode(
        portable_test_any(Portable_Enumerated_State, &source),
        alloc = context.allocator,
    )
    testing.expect(t, first_ok)
    testing.expect(t, first_error.kind == .None)
    if !first_ok do return
    defer delete(first)
    record := portable_test_find_type_record(first, .Enumerated_Array)
    testing.expect(t, record >= 0)
    testing.expect(t, portable_test_u32(first, record + 4) != 0)
    testing.expect(t, portable_test_u32(first, record + 8) != 0)
    testing.expect(t, portable_test_u32(first, record + 4) != portable_test_u32(first, record + 8))
    testing.expect(t, portable_test_u32(first, record + 12) == 3)

    second, second_error, second_ok := hs.portable_encode(
        portable_test_any(Portable_Enumerated_State, &source),
        alloc = context.allocator,
    )
    testing.expect(t, second_ok)
    testing.expect(t, second_error.kind == .None)
    if second_ok {
        testing.expect(t, len(first) == len(second))
        testing.expect(t, string(first) == string(second))
        delete(second)
    }

    exact_config := hs.portable_default_config()
    exact_config.exact_schema = true
    destination := Portable_Enumerated_State{}
    error, ok := hs.portable_decode(
        portable_test_any(Portable_Enumerated_State, &destination),
        first,
        exact_config,
        context.allocator,
    )
    testing.expect(t, ok)
    testing.expect(t, error.kind == .None)
    testing.expect(t, destination == source)
    portable_test_dispose_error(&error)

    plain := Portable_Enumerated_Plain_State {
        values = {101, 102, 103},
    }
    plain_before := plain
    error, ok = hs.portable_decode(
        portable_test_any(Portable_Enumerated_Plain_State, &plain),
        first,
        exact_config,
        context.allocator,
    )
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Type_Mismatch)
    testing.expect(t, plain == plain_before)
    portable_test_dispose_error(&error)
    portable_test_dispose_error(&error)

    other := Portable_Enumerated_Other_State{}
    other.values[.Alpha] = 201
    other.values[.Beta] = 202
    other.values[.Gamma] = 203
    other_before := other
    error, ok = hs.portable_decode(
        portable_test_any(Portable_Enumerated_Other_State, &other),
        first,
        exact_config,
        context.allocator,
    )
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Type_Mismatch)
    testing.expect(t, other == other_before)
    portable_test_dispose_error(&error)

    other = {}
    error, ok = hs.portable_decode(
        portable_test_any(Portable_Enumerated_Other_State, &other),
        first,
        alloc = context.allocator,
    )
    testing.expect(t, ok)
    testing.expect(t, error.kind == .None)
    testing.expect(t, other.values[.Alpha] == source.values[.Lower])
    testing.expect(t, other.values[.Beta] == source.values[.Middle])
    testing.expect(t, other.values[.Gamma] == source.values[.Upper])
    portable_test_dispose_error(&error)

    reordered := portable_test_copy(first)
    enum_record := portable_test_find_type_record(reordered, .Enum)
    first_value := portable_test_enum_value_offset(reordered, enum_record, 0)
    second_value := portable_test_enum_value_offset(reordered, enum_record, 1)
    third_value := portable_test_enum_value_offset(reordered, enum_record, 2)
    testing.expect(t, first_value >= 0 && second_value >= 0 && third_value >= 0)
    portable_test_put_i64(reordered, first_value, 5)
    portable_test_put_i64(reordered, second_value, 3)
    portable_test_put_i64(reordered, third_value, 4)
    reordered_destination := Portable_Enumerated_State{}
    error, ok = hs.portable_decode(
        portable_test_any(Portable_Enumerated_State, &reordered_destination),
        reordered,
        alloc = context.allocator,
    )
    testing.expect(t, ok)
    testing.expect(t, error.kind == .None)
    testing.expect(t, reordered_destination == source)
    portable_test_dispose_error(&error)
    delete(reordered)

    negative_source := Portable_Enumerated_Negative_State{}
    negative_source.values[.Low] = 101
    negative_source.values[.Center] = 202
    negative_source.values[.High] = 303
    negative_data, negative_encode_error, negative_encode_ok := hs.portable_encode(
        portable_test_any(Portable_Enumerated_Negative_State, &negative_source),
        alloc = context.allocator,
    )
    testing.expect(t, negative_encode_ok)
    testing.expect(t, negative_encode_error.kind == .None)
    if negative_encode_ok {
        negative_enum_record := portable_test_find_type_record(negative_data, .Enum)
        negative_first := portable_test_enum_value_offset(negative_data, negative_enum_record, 0)
        negative_second := portable_test_enum_value_offset(negative_data, negative_enum_record, 1)
        negative_third := portable_test_enum_value_offset(negative_data, negative_enum_record, 2)
        testing.expect(t, negative_first >= 0 && negative_second >= 0 && negative_third >= 0)
        portable_test_put_i64(negative_data, negative_first, 0)
        portable_test_put_i64(negative_data, negative_second, -2)
        portable_test_put_i64(negative_data, negative_third, -1)
        negative_destination := Portable_Enumerated_Negative_State{}
        negative_error, negative_ok := hs.portable_decode(
            portable_test_any(Portable_Enumerated_Negative_State, &negative_destination),
            negative_data,
            alloc = context.allocator,
        )
        testing.expect(t, negative_ok)
        testing.expect(t, negative_error.kind == .None)
        testing.expect(t, negative_destination == negative_source)
        portable_test_dispose_error(&negative_error)
        delete(negative_data)
    }

    story_source := Portable_Story_Enumerated_State{}
    for index in 0 ..< 11 {
        story_source.values[Portable_Story_Index(index)] = u64(1000 + index * 17)
    }
    story_data, story_encode_error, story_encode_ok := hs.portable_encode(
        portable_test_any(Portable_Story_Enumerated_State, &story_source),
        alloc = context.allocator,
    )
    testing.expect(t, story_encode_ok)
    testing.expect(t, story_encode_error.kind == .None)
    if story_encode_ok {
        story_destination := Portable_Story_Enumerated_State{}
        story_error, story_ok := hs.portable_decode(
            portable_test_any(Portable_Story_Enumerated_State, &story_destination),
            story_data,
            exact_config,
            context.allocator,
        )
        testing.expect(t, story_ok)
        testing.expect(t, story_error.kind == .None)
        testing.expect(t, story_destination == story_source)
        portable_test_dispose_error(&story_error)
        delete(story_data)
    }
}

@(test)
hs_portable_enumerated_array_metadata_is_hostile_safe :: proc(t: ^testing.T) {
    source := Portable_Enumerated_State{}
    source.values[.Lower] = 11
    source.values[.Middle] = 22
    source.values[.Upper] = 33
    encoded, encode_error, encode_ok := hs.portable_encode(
        portable_test_any(Portable_Enumerated_State, &source),
        alloc = context.allocator,
    )
    testing.expect(t, encode_ok)
    testing.expect(t, encode_error.kind == .None)
    if !encode_ok do return
    defer delete(encoded)
    array_record := portable_test_find_type_record(encoded, .Enumerated_Array)
    enum_record := portable_test_find_type_record(encoded, .Enum)
    testing.expect(t, array_record >= 0)
    testing.expect(t, enum_record >= 0)
    if array_record < 0 || enum_record < 0 do return

    bad_index_handle := portable_test_copy(encoded)
    portable_test_put_u32(bad_index_handle, array_record + 8, 0)
    error, ok := hs.portable_decode(
        portable_test_any(Portable_Enumerated_State, &Portable_Enumerated_State{}),
        bad_index_handle,
        alloc = context.allocator,
    )
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Invalid_Handle)
    portable_test_dispose_error(&error)
    portable_test_dispose_error(&error)
    delete(bad_index_handle)

    wrong_index_kind := portable_test_copy(encoded)
    portable_test_put_u32(wrong_index_kind, array_record + 8, portable_test_u32(wrong_index_kind, array_record + 4))
    error, ok = hs.portable_decode(
        portable_test_any(Portable_Enumerated_State, &Portable_Enumerated_State{}),
        wrong_index_kind,
        alloc = context.allocator,
    )
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Invalid_Metadata)
    portable_test_dispose_error(&error)
    delete(wrong_index_kind)

    base_record := portable_test_find_type_record(encoded, .Signed)
    testing.expect(t, base_record >= 0)
    if base_record < 0 do return

    wider_base := portable_test_copy(encoded)
    wider_base[base_record + 1] = 2
    wider_destination := Portable_Enumerated_State{}
    wider_destination.values[.Lower] = 401
    wider_destination.values[.Middle] = 402
    wider_destination.values[.Upper] = 403
    wider_before := wider_destination
    error, ok = hs.portable_decode(
        portable_test_any(Portable_Enumerated_State, &wider_destination),
        wider_base,
        alloc = context.allocator,
    )
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Type_Mismatch)
    testing.expect(t, error.path == "$.values")
    testing.expect(t, error.message == "enumerated array index base does not match destination")
    testing.expect(t, wider_destination == wider_before)
    portable_test_dispose_error(&error)
    portable_test_dispose_error(&error)
    delete(wider_base)

    unsigned_base := portable_test_copy(encoded)
    unsigned_base[base_record] = byte(hs.Portable_Kind.Unsigned)
    unsigned_base[base_record + 2] = 0
    unsigned_destination := Portable_Enumerated_State{}
    unsigned_destination.values[.Lower] = 501
    unsigned_destination.values[.Middle] = 502
    unsigned_destination.values[.Upper] = 503
    unsigned_before := unsigned_destination
    error, ok = hs.portable_decode(
        portable_test_any(Portable_Enumerated_State, &unsigned_destination),
        unsigned_base,
        alloc = context.allocator,
    )
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Type_Mismatch)
    testing.expect(t, error.path == "$.values")
    testing.expect(t, error.message == "enumerated array index base does not match destination")
    testing.expect(t, unsigned_destination == unsigned_before)
    portable_test_dispose_error(&error)
    portable_test_dispose_error(&error)
    delete(unsigned_base)

    bad_count := portable_test_copy(encoded)
    portable_test_put_u64(bad_count, array_record + 12, 4)
    error, ok = hs.portable_decode(
        portable_test_any(Portable_Enumerated_State, &Portable_Enumerated_State{}),
        bad_count,
        alloc = context.allocator,
    )
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Invalid_Metadata)
    portable_test_dispose_error(&error)
    delete(bad_count)

    first_value := portable_test_enum_value_offset(encoded, enum_record, 0)
    second_value := portable_test_enum_value_offset(encoded, enum_record, 1)
    third_value := portable_test_enum_value_offset(encoded, enum_record, 2)
    testing.expect(t, first_value >= 0 && second_value >= 0 && third_value >= 0)

    duplicate := portable_test_copy(encoded)
    portable_test_put_i64(duplicate, second_value, 3)
    error, ok = hs.portable_decode(
        portable_test_any(Portable_Enumerated_State, &Portable_Enumerated_State{}),
        duplicate,
        alloc = context.allocator,
    )
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Invalid_Metadata)
    portable_test_dispose_error(&error)
    delete(duplicate)

    gapped := portable_test_copy(encoded)
    portable_test_put_i64(gapped, third_value, 6)
    error, ok = hs.portable_decode(
        portable_test_any(Portable_Enumerated_State, &Portable_Enumerated_State{}),
        gapped,
        alloc = context.allocator,
    )
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Invalid_Metadata)
    portable_test_dispose_error(&error)
    delete(gapped)

    overflowing := portable_test_copy(encoded)
    portable_test_put_i64(overflowing, first_value, max(i64) - 1)
    portable_test_put_i64(overflowing, second_value, max(i64))
    portable_test_put_i64(overflowing, third_value, max(i64))
    error, ok = hs.portable_decode(
        portable_test_any(Portable_Enumerated_State, &Portable_Enumerated_State{}),
        overflowing,
        alloc = context.allocator,
    )
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Invalid_Metadata)
    portable_test_dispose_error(&error)
    delete(overflowing)

    cycle := portable_test_copy(encoded)
    portable_test_put_u32(cycle, array_record + 4, 1)
    error, ok = hs.portable_decode(
        portable_test_any(Portable_Enumerated_State, &Portable_Enumerated_State{}),
        cycle,
        alloc = context.allocator,
    )
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Invalid_Metadata)
    portable_test_dispose_error(&error)
    delete(cycle)

    error, ok = hs.portable_decode(
        portable_test_any(Portable_Enumerated_State, &Portable_Enumerated_State{}),
        encoded[:len(encoded) - 1],
        alloc = context.allocator,
    )
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Truncated)
    portable_test_dispose_error(&error)
}

@(test)
hs_portable_enumerated_arrays_have_bounded_allocations_and_oom_cleanup :: proc(t: ^testing.T) {
    one := Portable_Enumerated_Allocation_One{}
    many := Portable_Enumerated_Allocation_Many{}
    for outer in 0 ..< 128 {
        many.values[outer][.Lower] = u64(outer * 3 + 1)
        many.values[outer][.Middle] = u64(outer * 3 + 2)
        many.values[outer][.Upper] = u64(outer * 3 + 3)
    }
    one.values[0][.Lower] = 1
    one.values[0][.Middle] = 2
    one.values[0][.Upper] = 3
    one_data, one_encode_error, one_encode_ok := hs.portable_encode(
        portable_test_any(Portable_Enumerated_Allocation_One, &one),
        alloc = context.allocator,
    )
    many_data, many_encode_error, many_encode_ok := hs.portable_encode(
        portable_test_any(Portable_Enumerated_Allocation_Many, &many),
        alloc = context.allocator,
    )
    testing.expect(t, one_encode_ok && many_encode_ok)
    testing.expect(t, one_encode_error.kind == .None && many_encode_error.kind == .None)
    if !one_encode_ok || !many_encode_ok {
        if one_encode_ok do delete(one_data)
        if many_encode_ok do delete(many_data)
        return
    }
    defer delete(one_data)
    defer delete(many_data)

    exact_config := hs.portable_default_config()
    exact_config.exact_schema = true
    one_allocator_state := Portable_Test_Counting_Allocator {
        backing = context.allocator,
        fail_at = -1,
    }
    one_allocator := mem.Allocator {
        procedure = portable_test_counting_allocator_proc,
        data      = rawptr(&one_allocator_state),
    }
    one_destination := Portable_Enumerated_Allocation_One{}
    error, ok := hs.portable_decode(
        portable_test_any(Portable_Enumerated_Allocation_One, &one_destination),
        one_data,
        exact_config,
        one_allocator,
    )
    testing.expect(t, ok)
    testing.expect(t, error.kind == .None)
    testing.expect(t, one_destination == one)
    testing.expect(t, one_allocator_state.outstanding == 0)
    portable_test_dispose_error(&error)

    many_allocator_state := Portable_Test_Counting_Allocator {
        backing = context.allocator,
        fail_at = -1,
    }
    many_allocator := mem.Allocator {
        procedure = portable_test_counting_allocator_proc,
        data      = rawptr(&many_allocator_state),
    }
    many_destination := Portable_Enumerated_Allocation_Many{}
    error, ok = hs.portable_decode(
        portable_test_any(Portable_Enumerated_Allocation_Many, &many_destination),
        many_data,
        exact_config,
        many_allocator,
    )
    testing.expect(t, ok)
    testing.expect(t, error.kind == .None)
    testing.expect(t, many_destination == many)
    testing.expect(t, many_allocator_state.outstanding == 0)
    testing.expect(t, one_allocator_state.allocs == many_allocator_state.allocs)
    portable_test_dispose_error(&error)

    probe := Portable_Test_Counting_Allocator {
        backing = context.allocator,
        fail_at = -1,
    }
    probe_allocator := mem.Allocator {
        procedure = portable_test_counting_allocator_proc,
        data      = rawptr(&probe),
    }
    probe_data, probe_error, probe_ok := hs.portable_encode(
        portable_test_any(Portable_Enumerated_State, &Portable_Enumerated_State{}),
        alloc = probe_allocator,
    )
    testing.expect(t, probe_ok)
    testing.expect(t, probe_error.kind == .None)
    testing.expect(t, probe.allocs > 0)
    if probe_ok do delete(probe_data, probe_allocator)
    portable_test_dispose_error(&probe_error)
    testing.expect(t, probe.outstanding == 0)

    for fail_at in 0 ..< probe.allocs {
        failing := Portable_Test_Counting_Allocator {
            backing = context.allocator,
            fail_at = fail_at,
        }
        failing_allocator := mem.Allocator {
            procedure = portable_test_counting_allocator_proc,
            data      = rawptr(&failing),
        }
        failed_data, failed_error, failed_ok := hs.portable_encode(
            portable_test_any(Portable_Enumerated_State, &Portable_Enumerated_State{}),
            alloc = failing_allocator,
        )
        testing.expect(t, !failed_ok)
        testing.expect(t, failed_data == nil)
        testing.expect(t, failed_error.kind == .Limit_Exceeded)
        portable_test_dispose_error(&failed_error)
        portable_test_dispose_error(&failed_error)
        testing.expect(t, failing.outstanding == 0)
    }

    decode_probe := Portable_Test_Counting_Allocator {
        backing = context.allocator,
        fail_at = -1,
    }
    decode_probe_allocator := mem.Allocator {
        procedure = portable_test_counting_allocator_proc,
        data      = rawptr(&decode_probe),
    }
    decode_probe_destination := Portable_Enumerated_State{}
    error, ok = hs.portable_decode(
        portable_test_any(Portable_Enumerated_State, &decode_probe_destination),
        one_data,
        exact_config,
        decode_probe_allocator,
    )
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Type_Mismatch)
    portable_test_dispose_error(&error)
    testing.expect(t, decode_probe.outstanding == 0)

    source := Portable_Enumerated_State{}
    source.values[.Lower] = 71
    source.values[.Middle] = 72
    source.values[.Upper] = 73
    source_data, source_encode_error, source_encode_ok := hs.portable_encode(
        portable_test_any(Portable_Enumerated_State, &source),
        alloc = context.allocator,
    )
    testing.expect(t, source_encode_ok)
    testing.expect(t, source_encode_error.kind == .None)
    if source_encode_ok {
        decode_probe = {
            backing = context.allocator,
            fail_at = -1,
        }
        decode_probe_destination = {}
        error, ok = hs.portable_decode(
            portable_test_any(Portable_Enumerated_State, &decode_probe_destination),
            source_data,
            exact_config,
            decode_probe_allocator,
        )
        testing.expect(t, ok)
        testing.expect(t, error.kind == .None)
        testing.expect(t, decode_probe_destination == source)
        testing.expect(t, decode_probe.outstanding == 0)
        portable_test_dispose_error(&error)

        for fail_at in 0 ..< decode_probe.allocs {
            failing := Portable_Test_Counting_Allocator {
                backing = context.allocator,
                fail_at = fail_at,
            }
            failing_allocator := mem.Allocator {
                procedure = portable_test_counting_allocator_proc,
                data      = rawptr(&failing),
            }
            failed_destination := Portable_Enumerated_State{}
            failed_destination.values[.Lower] = 801
            failed_destination.values[.Middle] = 802
            failed_destination.values[.Upper] = 803
            before := failed_destination
            failed_error, failed_ok := hs.portable_decode(
                portable_test_any(Portable_Enumerated_State, &failed_destination),
                source_data,
                exact_config,
                failing_allocator,
            )
            testing.expect(t, !failed_ok)
            testing.expect(t, failed_error.kind == .Limit_Exceeded)
            testing.expect(t, failed_destination == before)
            portable_test_dispose_error(&failed_error)
            portable_test_dispose_error(&failed_error)
            testing.expect(t, failing.outstanding == 0)
        }
        delete(source_data)
    }

    encode_probe := Portable_Test_One_Shot_Allocator {
        backing = context.allocator,
        fail_at = -1,
    }
    encode_probe_allocator := mem.Allocator {
        procedure = portable_test_one_shot_allocator_proc,
        data      = rawptr(&encode_probe),
    }
    encode_probe_data, encode_probe_error, encode_probe_ok := hs.portable_encode(
        portable_test_any(Portable_Enumerated_State, &source),
        alloc = encode_probe_allocator,
    )
    testing.expect(t, encode_probe_ok)
    testing.expect(t, encode_probe_error.kind == .None)
    testing.expect(t, encode_probe.allocs > 0)
    if encode_probe_ok do delete(encode_probe_data, encode_probe_allocator)
    portable_test_dispose_error(&encode_probe_error)
    testing.expect(t, encode_probe.outstanding == 0)

    encode_path_failures := 0
    for fail_at in 0 ..< encode_probe.allocs {
        failing := Portable_Test_One_Shot_Allocator {
            backing = context.allocator,
            fail_at = fail_at,
        }
        failing_allocator := mem.Allocator {
            procedure = portable_test_one_shot_allocator_proc,
            data      = rawptr(&failing),
        }
        failed_data, failed_error, failed_ok := hs.portable_encode(
            portable_test_any(Portable_Enumerated_State, &source),
            alloc = failing_allocator,
        )
        testing.expect(t, !failed_ok)
        testing.expect(t, failed_data == nil)
        testing.expect(t, failing.failed)
        if failed_error.message == "field path allocation failed" {
            encode_path_failures += 1
            testing.expect(t, failed_error.kind == .Limit_Exceeded)
            testing.expect(t, failed_error.path == "$")
        }
        portable_test_dispose_error(&failed_error)
        portable_test_dispose_error(&failed_error)
        testing.expect(t, failing.outstanding == 0)
    }
    testing.expect(t, encode_path_failures == 2)

    additive_source := Portable_Additive_Source {
        kept    = 601,
        removed = 602,
    }
    additive_data, additive_encode_error, additive_encode_ok := hs.portable_encode(
        portable_test_any(Portable_Additive_Source, &additive_source),
        alloc = context.allocator,
    )
    testing.expect(t, additive_encode_ok)
    testing.expect(t, additive_encode_error.kind == .None)
    if additive_encode_ok {
        decode_path_probe := Portable_Test_One_Shot_Allocator {
            backing = context.allocator,
            fail_at = -1,
        }
        decode_path_probe_allocator := mem.Allocator {
            procedure = portable_test_one_shot_allocator_proc,
            data      = rawptr(&decode_path_probe),
        }
        additive_destination := Portable_Additive_Destination{}
        additive_error, additive_ok := hs.portable_decode(
            portable_test_any(Portable_Additive_Destination, &additive_destination),
            additive_data,
            alloc = decode_path_probe_allocator,
        )
        testing.expect(t, additive_ok)
        testing.expect(t, additive_error.kind == .None)
        testing.expect(t, additive_destination.kept == additive_source.kept)
        testing.expect(t, decode_path_probe.outstanding == 0)
        portable_test_dispose_error(&additive_error)

        decode_path_failures := 0
        for fail_at in 0 ..< decode_path_probe.allocs {
            failing := Portable_Test_One_Shot_Allocator {
                backing = context.allocator,
                fail_at = fail_at,
            }
            failing_allocator := mem.Allocator {
                procedure = portable_test_one_shot_allocator_proc,
                data      = rawptr(&failing),
            }
            failed_destination := Portable_Additive_Destination{}
            failed_error, failed_ok := hs.portable_decode(
                portable_test_any(Portable_Additive_Destination, &failed_destination),
                additive_data,
                alloc = failing_allocator,
            )
            testing.expect(t, !failed_ok)
            testing.expect(t, failing.failed)
            if failed_error.message == "field path allocation failed" {
                decode_path_failures += 1
                testing.expect(t, failed_error.kind == .Limit_Exceeded)
                testing.expect(t, failed_error.path == "$")
            }
            portable_test_dispose_error(&failed_error)
            portable_test_dispose_error(&failed_error)
            testing.expect(t, failing.outstanding == 0)
        }
        testing.expect(t, decode_path_failures == 2)
        delete(additive_data)
    }

    nil_allocator := mem.Allocator{}
    _, error, ok = hs.portable_encode(portable_test_any(Portable_Enumerated_State, &source), alloc = nil_allocator)
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Invalid_Argument)
    portable_test_dispose_error(&error)
    error, ok = hs.portable_decode(
        portable_test_any(Portable_Enumerated_State, &Portable_Enumerated_State{}),
        nil,
        alloc = nil_allocator,
    )
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Invalid_Argument)
    portable_test_dispose_error(&error)
}

@(test)
hs_portable_writer_oom_is_distinct_from_payload_limit :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    source := portable_test_state()
    config := portable_test_fixture_config()
    expected, expected_error, expected_ok := hs.portable_encode(
        portable_test_any(Portable_State, &source),
        config,
        context.allocator,
    )
    testing.expect(t, expected_ok && expected_error.kind == .None)
    portable_test_dispose_error(&expected_error)
    if !expected_ok do return
    defer delete(expected)

    probe := Portable_Test_One_Shot_Allocator {
        backing = runtime.default_allocator(),
        fail_at = -1,
    }
    probe_allocator := mem.Allocator {
        procedure = portable_test_one_shot_allocator_proc,
        data      = rawptr(&probe),
    }
    probe_data, probe_error, probe_ok := hs.portable_encode(
        portable_test_any(Portable_State, &source),
        config,
        probe_allocator,
    )
    testing.expect(t, probe_ok && probe_error.kind == .None && probe.allocs > 0)
    if probe_ok {
        testing.expect(t, len(probe_data) == len(expected))
        if len(probe_data) == len(expected) {
            for byte_value, index in probe_data {
                testing.expect(t, byte_value == expected[index])
            }
        }
        delete(probe_data, probe_allocator)
    }
    portable_test_dispose_error(&probe_error)
    testing.expect(t, probe.outstanding == 0)

    table_writer_oom := false
    body_writer_oom := false
    payload_writer_oom := false
    for fail_at in 0 ..< probe.allocs {
        failing := Portable_Test_One_Shot_Allocator {
            backing = runtime.default_allocator(),
            fail_at = fail_at,
        }
        failing_allocator := mem.Allocator {
            procedure = portable_test_one_shot_allocator_proc,
            data      = rawptr(&failing),
        }
        failed_data, failed_error, failed_ok := hs.portable_encode(
            portable_test_any(Portable_State, &source),
            config,
            failing_allocator,
        )
        testing.expect(t, !failed_ok && failed_data == nil && failing.failed)
        testing.expect(t, failed_error.kind == .Limit_Exceeded && strings.contains(failed_error.message, "allocation"))
        switch failed_error.message {
        case "type table allocation failed":
            table_writer_oom = true
        case "value body allocation failed":
            body_writer_oom = true
        case "payload allocation failed":
            payload_writer_oom = true
        case:
        }
        portable_test_dispose_error(&failed_error)
        portable_test_dispose_error(&failed_error)
        testing.expect(t, failing.outstanding == 0)
    }
    testing.expect(t, table_writer_oom && body_writer_oom && payload_writer_oom)

    limited_config := config
    limited_config.limits.max_payload = hs.Portable_Header_Size
    limited_data, limited_error, limited_ok := hs.portable_encode(
        portable_test_any(Portable_State, &source),
        limited_config,
        context.allocator,
    )
    testing.expect(t, !limited_ok && limited_data == nil)
    testing.expect(
        t,
        limited_error.kind == .Limit_Exceeded &&
        limited_error.message == "type table exceeds payload limit" &&
        !strings.contains(limited_error.message, "allocation"),
    )
    portable_test_dispose_error(&limited_error)
    portable_test_dispose_error(&limited_error)

    short_source := Portable_Exact_Short_Field {
        a = 91,
    }
    short_data, short_error, short_ok := hs.portable_encode(
        portable_test_any(Portable_Exact_Short_Field, &short_source),
        alloc = context.allocator,
    )
    testing.expect(t, short_ok && short_error.kind == .None)
    portable_test_dispose_error(&short_error)
    if !short_ok do return
    defer delete(short_data)

    exact_config := hs.portable_default_config()
    exact_config.exact_schema = true
    exact_probe := Portable_Test_All_Fault_Allocator {
        backing = runtime.default_allocator(),
        fail_at = -1,
    }
    exact_probe_allocator := mem.Allocator {
        procedure = portable_test_all_fault_allocator_proc,
        data      = rawptr(&exact_probe),
    }
    long_destination := Portable_Exact_Long_Field {
        substantially_longer_field_name = 707,
    }
    exact_error, exact_ok := hs.portable_decode(
        portable_test_any(Portable_Exact_Long_Field, &long_destination),
        short_data,
        exact_config,
        exact_probe_allocator,
    )
    testing.expect(t, !exact_ok)
    testing.expect(
        t,
        exact_error.kind == .Type_Mismatch &&
        exact_error.message == "saved type table length does not match destination" &&
        !strings.contains(exact_error.message, "allocation"),
    )
    testing.expect(t, long_destination.substantially_longer_field_name == 707)
    portable_test_dispose_error(&exact_error)
    portable_test_dispose_error(&exact_error)
    testing.expect(t, exact_probe.attempts > 0 && exact_probe.outstanding == 0)

    exact_table_allocation_failures := 0
    for fail_at in 0 ..< exact_probe.attempts {
        failing := Portable_Test_All_Fault_Allocator {
            backing = runtime.default_allocator(),
            fail_at = fail_at,
        }
        failing_allocator := mem.Allocator {
            procedure = portable_test_all_fault_allocator_proc,
            data      = rawptr(&failing),
        }
        failed_destination := Portable_Exact_Long_Field {
            substantially_longer_field_name = 808,
        }
        failed_error, failed_ok := hs.portable_decode(
            portable_test_any(Portable_Exact_Long_Field, &failed_destination),
            short_data,
            exact_config,
            failing_allocator,
        )
        testing.expect(t, !failed_ok)
        testing.expect(t, failed_error.kind == .Limit_Exceeded && strings.contains(failed_error.message, "allocation"))
        if failed_error.message == "exact type table allocation failed" {
            exact_table_allocation_failures += 1
        }
        testing.expect(t, failed_destination.substantially_longer_field_name == 808)
        portable_test_dispose_error(&failed_error)
        portable_test_dispose_error(&failed_error)
        testing.expect(t, failing.outstanding == 0)
    }
    testing.expect(t, exact_table_allocation_failures >= 2)
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
hs_portable_fixed_u8_and_f32_arrays_preserve_wire_and_failures :: proc(t: ^testing.T) {
    source := Portable_Bulk_Fixed_Arrays {
        bytes = {0, 1, 127, 255},
        floats = {1.0, -1.5, -2.25},
        nested = {bytes = {17, 34, 51}, floats = {0.5, -4.0, 7.25}},
    }
    encoded, encode_error, encode_ok := hs.portable_encode(
        portable_test_any(Portable_Bulk_Fixed_Arrays, &source),
        alloc = context.allocator,
    )
    testing.expect(t, encode_ok)
    testing.expect(t, encode_error.kind == .None)
    portable_test_dispose_error(&encode_error)
    if !encode_ok do return
    defer delete(encoded)

    expected := [31]byte {
        0,
        1,
        127,
        255,
        0,
        0,
        128,
        63,
        0,
        0,
        192,
        191,
        0,
        0,
        16,
        192,
        17,
        34,
        51,
        0,
        0,
        0,
        63,
        0,
        0,
        128,
        192,
        0,
        0,
        232,
        64,
    }
    body_start := portable_test_body_start(encoded)
    testing.expect(t, portable_test_bytes_equal(encoded[body_start:], expected[:]))

    again, again_error, again_ok := hs.portable_encode(
        portable_test_any(Portable_Bulk_Fixed_Arrays, &source),
        alloc = context.allocator,
    )
    testing.expect(t, again_ok)
    testing.expect(t, again_error.kind == .None)
    portable_test_dispose_error(&again_error)
    if again_ok {
        testing.expect(t, portable_test_bytes_equal(again, encoded))
        delete(again)
    }

    allocator_state := Portable_Test_Counting_Allocator {
        backing = context.allocator,
        fail_at = -1,
    }
    allocator := mem.Allocator {
        procedure = portable_test_counting_allocator_proc,
        data      = rawptr(&allocator_state),
    }
    decoded: Portable_Bulk_Fixed_Arrays
    decode_error, decode_ok := hs.portable_decode(
        portable_test_any(Portable_Bulk_Fixed_Arrays, &decoded),
        encoded,
        alloc = allocator,
    )
    testing.expect(t, decode_ok)
    testing.expect(t, decode_error.kind == .None)
    testing.expect(t, decoded == source)
    portable_test_dispose_error(&decode_error)
    testing.expect(t, allocator_state.outstanding == 0)

    corrupted := portable_test_copy(encoded)
    float_record := portable_test_find_type_record(corrupted, .Float)
    testing.expect(t, float_record >= 0)
    if float_record >= 0 {
        corrupted[float_record + 1] = 2
        corrupt_destination := Portable_Bulk_Fixed_Arrays {
            bytes  = {99, 99, 99, 99},
            floats = {99, 99, 99},
        }
        corrupt_error, corrupt_ok := hs.portable_decode(
            portable_test_any(Portable_Bulk_Fixed_Arrays, &corrupt_destination),
            corrupted,
            alloc = context.allocator,
        )
        testing.expect(t, !corrupt_ok)
        testing.expect(t, corrupt_error.kind == .Type_Mismatch)
        testing.expect(t, corrupt_error.path == "$.floats")
        testing.expect(t, corrupt_destination.bytes == source.bytes)
        testing.expect(t, corrupt_destination.floats == [3]f32{99, 99, 99})
        portable_test_dispose_error(&corrupt_error)
    }
    delete(corrupted)

    truncated := portable_test_copy(encoded[:len(encoded) - 2])
    portable_test_put_u32(truncated, 24, portable_test_u32(truncated, 24) - 2)
    truncated_destination := Portable_Bulk_Fixed_Arrays {
        bytes = {99, 99, 99, 99},
        floats = {99, 99, 99},
        nested = {bytes = {99, 99, 99}, floats = {99, 99, 99}},
    }
    truncated_error, truncated_ok := hs.portable_decode(
        portable_test_any(Portable_Bulk_Fixed_Arrays, &truncated_destination),
        truncated,
        alloc = context.allocator,
    )
    testing.expect(t, !truncated_ok)
    testing.expect(t, truncated_error.kind == .Truncated)
    testing.expect(t, truncated_error.path == "$.nested.floats")
    testing.expect(t, truncated_destination.bytes == source.bytes)
    testing.expect(t, truncated_destination.floats == source.floats)
    testing.expect(t, truncated_destination.nested.bytes == source.nested.bytes)
    testing.expect(t, truncated_destination.nested.floats[0] == source.nested.floats[0])
    testing.expect(t, truncated_destination.nested.floats[1] == source.nested.floats[1])
    testing.expect(t, truncated_destination.nested.floats[2] == 99)
    portable_test_dispose_error(&truncated_error)
    delete(truncated)
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
hs_portable_quaternion_exact_wire_and_round_trip :: proc(t: ^testing.T) {
    q64_bits := [4]u16{0x0001, 0x8000, 0x7e01, 0xfc00}
    q64 := portable_test_quaternion64(q64_bits)
    q64_data, q64_error, q64_ok := hs.portable_encode(portable_test_any(quaternion64, &q64))
    testing.expect(t, q64_ok)
    testing.expect(t, q64_error.kind == .None)
    portable_test_dispose_error(&q64_error)
    portable_test_dispose_error(&q64_error)
    if q64_ok {
        defer delete(q64_data)
        testing.expect(t, len(q64_data) == hs.Portable_Header_Size + 4 + 8)
        testing.expect(t, portable_test_u32(q64_data, 12) == 1)
        testing.expect(t, portable_test_u32(q64_data, 16) == 1)
        testing.expect(t, portable_test_u32(q64_data, 20) == 4)
        testing.expect(t, portable_test_u32(q64_data, 24) == 8)
        testing.expect(t, q64_data[hs.Portable_Header_Size] == byte(hs.Portable_Kind.Quaternion))
        testing.expect(t, q64_data[hs.Portable_Header_Size + 1] == 8)
        testing.expect(t, q64_data[hs.Portable_Header_Size + 2] == 0)
        testing.expect(t, q64_data[hs.Portable_Header_Size + 3] == 0)
        body := portable_test_body_start(q64_data)
        expected := [8]byte{0x01, 0x00, 0x00, 0x80, 0x01, 0x7e, 0x00, 0xfc}
        testing.expect(t, portable_test_bytes_equal(q64_data[body:], expected[:]))

        sentinel_bits := [4]u16{0x3c00, 0x4000, 0x4200, 0x4400}
        destination := portable_test_quaternion64(sentinel_bits)
        decode_error, decode_ok := hs.portable_decode(portable_test_any(quaternion64, &destination), q64_data)
        testing.expect(t, decode_ok)
        testing.expect(t, decode_error.kind == .None)
        testing.expect(t, portable_test_quaternion64_bits(destination) == q64_bits)
        portable_test_dispose_error(&decode_error)
        portable_test_dispose_error(&decode_error)

        round_trip, round_trip_error, round_trip_ok := hs.portable_encode(
            portable_test_any(quaternion64, &destination),
        )
        testing.expect(t, round_trip_ok)
        testing.expect(t, round_trip_error.kind == .None)
        if round_trip_ok {
            testing.expect(t, portable_test_bytes_equal(round_trip, q64_data))
            delete(round_trip)
        }
        portable_test_dispose_error(&round_trip_error)
    }

    q128_bits := [4]u32{0x0000_0001, 0x8000_0000, 0x7fc1_2345, 0xff80_0000}
    q128 := portable_test_quaternion128(q128_bits)
    q128_data, q128_error, q128_ok := hs.portable_encode(portable_test_any(quaternion128, &q128))
    testing.expect(t, q128_ok)
    testing.expect(t, q128_error.kind == .None)
    portable_test_dispose_error(&q128_error)
    portable_test_dispose_error(&q128_error)
    if q128_ok {
        defer delete(q128_data)
        testing.expect(t, len(q128_data) == hs.Portable_Header_Size + 4 + 16)
        testing.expect(t, portable_test_u32(q128_data, 12) == 1)
        testing.expect(t, portable_test_u32(q128_data, 16) == 1)
        testing.expect(t, portable_test_u32(q128_data, 20) == 4)
        testing.expect(t, portable_test_u32(q128_data, 24) == 16)
        testing.expect(t, q128_data[hs.Portable_Header_Size] == byte(hs.Portable_Kind.Quaternion))
        testing.expect(t, q128_data[hs.Portable_Header_Size + 1] == 16)
        testing.expect(t, q128_data[hs.Portable_Header_Size + 2] == 0)
        testing.expect(t, q128_data[hs.Portable_Header_Size + 3] == 0)
        body := portable_test_body_start(q128_data)
        expected := [16]byte {
            0x01,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x80,
            0x45,
            0x23,
            0xc1,
            0x7f,
            0x00,
            0x00,
            0x80,
            0xff,
        }
        testing.expect(t, portable_test_bytes_equal(q128_data[body:], expected[:]))

        sentinel_bits := [4]u32{0x3f80_0000, 0x4000_0000, 0x4040_0000, 0x4080_0000}
        destination := portable_test_quaternion128(sentinel_bits)
        decode_error, decode_ok := hs.portable_decode(portable_test_any(quaternion128, &destination), q128_data)
        testing.expect(t, decode_ok)
        testing.expect(t, decode_error.kind == .None)
        testing.expect(t, portable_test_quaternion128_bits(destination) == q128_bits)
        portable_test_dispose_error(&decode_error)
        portable_test_dispose_error(&decode_error)

        round_trip, round_trip_error, round_trip_ok := hs.portable_encode(
            portable_test_any(quaternion128, &destination),
        )
        testing.expect(t, round_trip_ok)
        testing.expect(t, round_trip_error.kind == .None)
        if round_trip_ok {
            testing.expect(t, portable_test_bytes_equal(round_trip, q128_data))
            delete(round_trip)
        }
        portable_test_dispose_error(&round_trip_error)
    }
}

@(test)
hs_portable_quaternion_nested_compatibility_and_atomic_failures :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    q64_a_bits := [4]u16{0x0001, 0x8000, 0x7e01, 0xfc00}
    q64_b_bits := [4]u16{0x3555, 0xb955, 0x7d01, 0x0400}
    q128_a_bits := [4]u32{0x0000_0001, 0x8000_0000, 0x7fc1_2345, 0xff80_0000}
    q128_b_bits := [4]u32{0x3eaa_aaab, 0xbf40_0000, 0x7fa0_0001, 0x0080_0000}
    source := Portable_Quaternion_Composite {
        nested = {rotation = portable_test_quaternion128(q128_a_bits)},
        fixed = {portable_test_quaternion64(q64_a_bits), portable_test_quaternion64(q64_b_bits)},
    }
    source.indexed[.Lower] = portable_test_quaternion128(q128_b_bits)
    source.indexed[.Middle] = portable_test_quaternion128(q128_a_bits)
    source.indexed[.Upper] = portable_test_quaternion128(q128_b_bits)
    source.dynamic_values = make([dynamic]quaternion64)
    append(&source.dynamic_values, portable_test_quaternion64(q64_b_bits))
    append(&source.dynamic_values, portable_test_quaternion64(q64_a_bits))
    defer delete(source.dynamic_values)

    encoded, encode_error, encode_ok := hs.portable_encode(portable_test_any(Portable_Quaternion_Composite, &source))
    testing.expect(t, encode_ok)
    testing.expect(t, encode_error.kind == .None)
    portable_test_dispose_error(&encode_error)
    if encode_ok {
        defer delete(encoded)
        original := portable_test_copy(encoded)
        defer delete(original)
        destination := Portable_Quaternion_Composite{}
        decode_error, decode_ok := hs.portable_decode(
            portable_test_any(Portable_Quaternion_Composite, &destination),
            encoded,
        )
        testing.expect(t, decode_ok)
        testing.expect(t, decode_error.kind == .None)
        testing.expect(t, portable_test_quaternion128_bits(destination.nested.rotation) == q128_a_bits)
        testing.expect(t, portable_test_quaternion64_bits(destination.fixed[0]) == q64_a_bits)
        testing.expect(t, portable_test_quaternion64_bits(destination.fixed[1]) == q64_b_bits)
        testing.expect(t, portable_test_quaternion128_bits(destination.indexed[.Lower]) == q128_b_bits)
        testing.expect(t, portable_test_quaternion128_bits(destination.indexed[.Middle]) == q128_a_bits)
        testing.expect(t, portable_test_quaternion128_bits(destination.indexed[.Upper]) == q128_b_bits)
        testing.expect(t, len(destination.dynamic_values) == 2)
        if len(destination.dynamic_values) == 2 {
            testing.expect(t, portable_test_quaternion64_bits(destination.dynamic_values[0]) == q64_b_bits)
            testing.expect(t, portable_test_quaternion64_bits(destination.dynamic_values[1]) == q64_a_bits)
        }
        if destination.dynamic_values != nil do delete(destination.dynamic_values)
        portable_test_dispose_error(&decode_error)
        portable_test_dispose_error(&decode_error)
        testing.expect(t, portable_test_bytes_equal(encoded, original))
    }

    extra_source := Portable_Quaternion_Extra_Source {
        rotation = portable_test_quaternion128(q128_a_bits),
        kept     = 0x1234_5678,
    }
    extra_data, extra_encode_error, extra_encode_ok := hs.portable_encode(
        portable_test_any(Portable_Quaternion_Extra_Source, &extra_source),
    )
    testing.expect(t, extra_encode_ok)
    testing.expect(t, extra_encode_error.kind == .None)
    portable_test_dispose_error(&extra_encode_error)
    if extra_encode_ok {
        extra_before := portable_test_copy(extra_data)
        extra_destination := Portable_Quaternion_Extra_Destination {
            kept = 0,
        }
        extra_error, extra_ok := hs.portable_decode(
            portable_test_any(Portable_Quaternion_Extra_Destination, &extra_destination),
            extra_data,
        )
        testing.expect(t, extra_ok)
        testing.expect(t, extra_error.kind == .None)
        testing.expect(t, extra_destination.kept == extra_source.kept)
        testing.expect(t, portable_test_bytes_equal(extra_data, extra_before))
        portable_test_dispose_error(&extra_error)
        portable_test_dispose_error(&extra_error)
        delete(extra_before)
        delete(extra_data)
    }

    missing_source := Portable_Quaternion_Missing_Source {
        kept = 0x8765_4321,
    }
    missing_data, missing_encode_error, missing_encode_ok := hs.portable_encode(
        portable_test_any(Portable_Quaternion_Missing_Source, &missing_source),
    )
    testing.expect(t, missing_encode_ok)
    testing.expect(t, missing_encode_error.kind == .None)
    portable_test_dispose_error(&missing_encode_error)
    if missing_encode_ok {
        sentinel := portable_test_quaternion128(q128_b_bits)
        missing_destination := Portable_Quaternion_Missing_Destination {
            rotation = sentinel,
            kept     = 0,
        }
        missing_error, missing_ok := hs.portable_decode(
            portable_test_any(Portable_Quaternion_Missing_Destination, &missing_destination),
            missing_data,
        )
        testing.expect(t, missing_ok)
        testing.expect(t, missing_error.kind == .None)
        testing.expect(t, portable_test_quaternion128_bits(missing_destination.rotation) == q128_b_bits)
        testing.expect(t, missing_destination.kept == missing_source.kept)
        portable_test_dispose_error(&missing_error)
        portable_test_dispose_error(&missing_error)
        delete(missing_data)
    }

    field_source := Portable_Quaternion128_Field {
        rotation = portable_test_quaternion128(q128_a_bits),
    }
    field_data, field_encode_error, field_encode_ok := hs.portable_encode(
        portable_test_any(Portable_Quaternion128_Field, &field_source),
    )
    testing.expect(t, field_encode_ok)
    testing.expect(t, field_encode_error.kind == .None)
    portable_test_dispose_error(&field_encode_error)
    if field_encode_ok {
        defer delete(field_data)
        field_before := portable_test_copy(field_data)
        defer delete(field_before)

        q64_destination := Portable_Quaternion64_Field {
            rotation = portable_test_quaternion64(q64_b_bits),
        }
        mismatch_error, mismatch_ok := hs.portable_decode(
            portable_test_any(Portable_Quaternion64_Field, &q64_destination),
            field_data,
        )
        testing.expect(t, !mismatch_ok)
        testing.expect(t, mismatch_error.kind == .Type_Mismatch)
        testing.expect(t, mismatch_error.path == "$.rotation")
        testing.expect(t, portable_test_quaternion64_bits(q64_destination.rotation) == q64_b_bits)
        portable_test_dispose_error(&mismatch_error)
        portable_test_dispose_error(&mismatch_error)

        array_destination := Portable_Quaternion_Array_Field {
            rotation = {1, 2, 3, 4},
        }
        mismatch_error, mismatch_ok = hs.portable_decode(
            portable_test_any(Portable_Quaternion_Array_Field, &array_destination),
            field_data,
        )
        testing.expect(t, !mismatch_ok)
        testing.expect(t, mismatch_error.kind == .Type_Mismatch)
        testing.expect(t, mismatch_error.path == "$.rotation")
        testing.expect(t, array_destination.rotation == [4]f32{1, 2, 3, 4})
        portable_test_dispose_error(&mismatch_error)

        scalar_destination := Portable_Quaternion_Scalar_Field {
            rotation = 91.25,
        }
        mismatch_error, mismatch_ok = hs.portable_decode(
            portable_test_any(Portable_Quaternion_Scalar_Field, &scalar_destination),
            field_data,
        )
        testing.expect(t, !mismatch_ok)
        testing.expect(t, mismatch_error.kind == .Type_Mismatch)
        testing.expect(t, mismatch_error.path == "$.rotation")
        testing.expect(t, scalar_destination.rotation == 91.25)
        portable_test_dispose_error(&mismatch_error)

        body_start := portable_test_body_start(field_data)
        for body_bytes in 0 ..< 16 {
            truncated := make([]byte, body_start + body_bytes)
            copy(truncated, field_data[:body_start + body_bytes])
            portable_test_put_u32(truncated, 24, u32(body_bytes))
            truncated_before := portable_test_copy(truncated)
            truncated_destination := Portable_Quaternion128_Field {
                rotation = portable_test_quaternion128(q128_b_bits),
            }
            truncated_error, truncated_ok := hs.portable_decode(
                portable_test_any(Portable_Quaternion128_Field, &truncated_destination),
                truncated,
            )
            testing.expect(t, !truncated_ok)
            testing.expect(t, truncated_error.kind == .Truncated)
            testing.expect(t, truncated_error.path == "$.rotation")
            testing.expect(t, truncated_error.offset == 0)
            testing.expect(t, portable_test_quaternion128_bits(truncated_destination.rotation) == q128_b_bits)
            testing.expect(t, portable_test_bytes_equal(truncated, truncated_before))
            portable_test_dispose_error(&truncated_error)
            portable_test_dispose_error(&truncated_error)
            delete(truncated_before)
            delete(truncated)
        }

        trailing := make([]byte, len(field_data) + 1)
        copy(trailing, field_data)
        trailing_before := portable_test_copy(trailing)
        trailing_destination := Portable_Quaternion128_Field {
            rotation = portable_test_quaternion128(q128_b_bits),
        }
        trailing_error, trailing_ok := hs.portable_decode(
            portable_test_any(Portable_Quaternion128_Field, &trailing_destination),
            trailing,
        )
        testing.expect(t, !trailing_ok)
        testing.expect(t, trailing_error.kind == .Trailing_Bytes)
        testing.expect(t, trailing_error.path == "$")
        testing.expect(t, trailing_error.offset == len(field_data))
        testing.expect(t, portable_test_quaternion128_bits(trailing_destination.rotation) == q128_b_bits)
        testing.expect(t, portable_test_bytes_equal(trailing, trailing_before))
        portable_test_dispose_error(&trailing_error)
        portable_test_dispose_error(&trailing_error)
        delete(trailing_before)
        delete(trailing)
        testing.expect(t, portable_test_bytes_equal(field_data, field_before))
    }
}

@(test)
hs_portable_quaternion_metadata_corruption_is_strict :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    q64_bits := [4]u16{0x0001, 0x8000, 0x7e01, 0xfc00}
    sentinel_bits := [4]u16{0x3c00, 0x4000, 0x4200, 0x4400}
    source := portable_test_quaternion64(q64_bits)
    encoded, encode_error, encode_ok := hs.portable_encode(portable_test_any(quaternion64, &source))
    testing.expect(t, encode_ok)
    testing.expect(t, encode_error.kind == .None)
    portable_test_dispose_error(&encode_error)
    portable_test_dispose_error(&encode_error)
    if !encode_ok do return
    defer delete(encoded)
    original := portable_test_copy(encoded)
    defer delete(original)

    bad_kind := portable_test_copy(encoded)
    bad_kind[hs.Portable_Header_Size] = byte(hs.Portable_Kind.Quaternion) + 1
    destination := portable_test_quaternion64(sentinel_bits)
    error, ok := hs.portable_decode(portable_test_any(quaternion64, &destination), bad_kind)
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Invalid_Metadata)
    testing.expect(t, error.path == "$table")
    testing.expect(t, error.offset == 4)
    testing.expect(t, portable_test_quaternion64_bits(destination) == sentinel_bits)
    portable_test_dispose_error(&error)
    portable_test_dispose_error(&error)
    delete(bad_kind)

    invalid_widths := [4]u8{0, 4, 32, 255}
    for width in invalid_widths {
        bad_width := portable_test_copy(encoded)
        bad_width[hs.Portable_Header_Size + 1] = width
        destination = portable_test_quaternion64(sentinel_bits)
        error, ok = hs.portable_decode(portable_test_any(quaternion64, &destination), bad_width)
        testing.expect(t, !ok)
        testing.expect(t, error.kind == .Invalid_Metadata)
        testing.expect(t, error.path == "$table")
        testing.expect(t, error.offset == 4)
        testing.expect(t, portable_test_quaternion64_bits(destination) == sentinel_bits)
        portable_test_dispose_error(&error)
        portable_test_dispose_error(&error)
        delete(bad_width)
    }

    bad_signed := portable_test_copy(encoded)
    bad_signed[hs.Portable_Header_Size + 2] = 1
    destination = portable_test_quaternion64(sentinel_bits)
    error, ok = hs.portable_decode(portable_test_any(quaternion64, &destination), bad_signed)
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Invalid_Metadata)
    testing.expect(t, error.path == "$table")
    testing.expect(t, error.offset == 4)
    testing.expect(t, portable_test_quaternion64_bits(destination) == sentinel_bits)
    portable_test_dispose_error(&error)
    portable_test_dispose_error(&error)
    delete(bad_signed)

    bad_reserved := portable_test_copy(encoded)
    bad_reserved[hs.Portable_Header_Size + 3] = 1
    destination = portable_test_quaternion64(sentinel_bits)
    error, ok = hs.portable_decode(portable_test_any(quaternion64, &destination), bad_reserved)
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Invalid_Metadata)
    testing.expect(t, error.path == "$table")
    testing.expect(t, error.offset == 4)
    testing.expect(t, portable_test_quaternion64_bits(destination) == sentinel_bits)
    portable_test_dispose_error(&error)
    portable_test_dispose_error(&error)
    delete(bad_reserved)

    table_bytes := int(portable_test_u32(encoded, 20))
    body_start := portable_test_body_start(encoded)
    trailing_table := make([]byte, len(encoded) + 1)
    copy(trailing_table[:body_start], encoded[:body_start])
    trailing_table[body_start] = 0
    copy(trailing_table[body_start + 1:], encoded[body_start:])
    portable_test_put_u32(trailing_table, 20, u32(table_bytes + 1))
    trailing_table_before := portable_test_copy(trailing_table)
    destination = portable_test_quaternion64(sentinel_bits)
    error, ok = hs.portable_decode(portable_test_any(quaternion64, &destination), trailing_table)
    testing.expect(t, !ok)
    testing.expect(t, error.kind == .Invalid_Metadata)
    testing.expect(t, error.path == "$table")
    testing.expect(t, error.offset == 4)
    testing.expect(t, portable_test_quaternion64_bits(destination) == sentinel_bits)
    testing.expect(t, portable_test_bytes_equal(trailing_table, trailing_table_before))
    portable_test_dispose_error(&error)
    portable_test_dispose_error(&error)
    delete(trailing_table_before)
    delete(trailing_table)

    q256: quaternion256
    unsupported_data, unsupported_error, unsupported_ok := hs.portable_encode(portable_test_any(quaternion256, &q256))
    testing.expect(t, !unsupported_ok)
    testing.expect(t, unsupported_data == nil)
    testing.expect(t, unsupported_error.kind == .Unsupported_Type)
    testing.expect(t, unsupported_error.path == "$")
    portable_test_dispose_error(&unsupported_error)
    portable_test_dispose_error(&unsupported_error)
    testing.expect(t, portable_test_bytes_equal(encoded, original))
}

@(test)
hs_portable_quaternion_allocations_ownership_and_oom_cleanup :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    q128_a_bits := [4]u32{0x0000_0001, 0x8000_0000, 0x7fc1_2345, 0xff80_0000}
    q128_b_bits := [4]u32{0x3eaa_aaab, 0xbf40_0000, 0x7fa0_0001, 0x0080_0000}
    one_source := Portable_Quaternion_Fixed_One {
        values = {portable_test_quaternion128(q128_a_bits)},
    }
    many_source := Portable_Quaternion_Fixed_Many{}
    for index in 0 ..< len(many_source.values) {
        if index & 1 == 0 {
            many_source.values[index] = portable_test_quaternion128(q128_a_bits)
        } else {
            many_source.values[index] = portable_test_quaternion128(q128_b_bits)
        }
    }

    one_encode_state := Portable_Test_Counting_Allocator {
        backing = runtime.default_allocator(),
        fail_at = -1,
    }
    one_encode_allocator := mem.Allocator {
        procedure = portable_test_counting_allocator_proc,
        data      = rawptr(&one_encode_state),
    }
    one_data, one_encode_error, one_encode_ok := hs.portable_encode(
        portable_test_any(Portable_Quaternion_Fixed_One, &one_source),
        alloc = one_encode_allocator,
    )
    testing.expect(t, one_encode_ok)
    testing.expect(t, one_encode_error.kind == .None)
    portable_test_dispose_error(&one_encode_error)
    portable_test_dispose_error(&one_encode_error)

    many_encode_state := Portable_Test_Counting_Allocator {
        backing = runtime.default_allocator(),
        fail_at = -1,
    }
    many_encode_allocator := mem.Allocator {
        procedure = portable_test_counting_allocator_proc,
        data      = rawptr(&many_encode_state),
    }
    many_data, many_encode_error, many_encode_ok := hs.portable_encode(
        portable_test_any(Portable_Quaternion_Fixed_Many, &many_source),
        alloc = many_encode_allocator,
    )
    testing.expect(t, many_encode_ok)
    testing.expect(t, many_encode_error.kind == .None)
    portable_test_dispose_error(&many_encode_error)
    portable_test_dispose_error(&many_encode_error)
    testing.expect(t, one_encode_state.allocs == many_encode_state.allocs)

    if one_encode_ok && many_encode_ok {
        one_decode_state := Portable_Test_Counting_Allocator {
            backing = runtime.default_allocator(),
            fail_at = -1,
        }
        one_decode_allocator := mem.Allocator {
            procedure = portable_test_counting_allocator_proc,
            data      = rawptr(&one_decode_state),
        }
        one_destination := Portable_Quaternion_Fixed_One{}
        one_decode_error, one_decode_ok := hs.portable_decode(
            portable_test_any(Portable_Quaternion_Fixed_One, &one_destination),
            one_data,
            alloc = one_decode_allocator,
        )
        testing.expect(t, one_decode_ok)
        testing.expect(t, one_decode_error.kind == .None)
        testing.expect(t, portable_test_quaternion128_bits(one_destination.values[0]) == q128_a_bits)
        portable_test_dispose_error(&one_decode_error)
        portable_test_dispose_error(&one_decode_error)
        testing.expect(t, one_decode_state.outstanding == 0)

        many_decode_state := Portable_Test_Counting_Allocator {
            backing = runtime.default_allocator(),
            fail_at = -1,
        }
        many_decode_allocator := mem.Allocator {
            procedure = portable_test_counting_allocator_proc,
            data      = rawptr(&many_decode_state),
        }
        many_destination := Portable_Quaternion_Fixed_Many{}
        many_decode_error, many_decode_ok := hs.portable_decode(
            portable_test_any(Portable_Quaternion_Fixed_Many, &many_destination),
            many_data,
            alloc = many_decode_allocator,
        )
        testing.expect(t, many_decode_ok)
        testing.expect(t, many_decode_error.kind == .None)
        testing.expect(t, portable_test_quaternion128_bits(many_destination.values[0]) == q128_a_bits)
        testing.expect(t, portable_test_quaternion128_bits(many_destination.values[127]) == q128_b_bits)
        portable_test_dispose_error(&many_decode_error)
        portable_test_dispose_error(&many_decode_error)
        testing.expect(t, many_decode_state.outstanding == 0)
        testing.expect(t, one_decode_state.allocs == many_decode_state.allocs)
    }
    if one_data != nil do delete(one_data, one_encode_allocator)
    if many_data != nil do delete(many_data, many_encode_allocator)
    testing.expect(t, one_encode_state.outstanding == 0)
    testing.expect(t, many_encode_state.outstanding == 0)

    dynamic_source := Portable_Quaternion_Dynamic {
        values = make([dynamic]quaternion128, 2),
    }
    dynamic_source.values[0] = portable_test_quaternion128(q128_a_bits)
    dynamic_source.values[1] = portable_test_quaternion128(q128_b_bits)
    defer delete(dynamic_source.values)
    dynamic_data, dynamic_encode_error, dynamic_encode_ok := hs.portable_encode(
        portable_test_any(Portable_Quaternion_Dynamic, &dynamic_source),
    )
    testing.expect(t, dynamic_encode_ok)
    testing.expect(t, dynamic_encode_error.kind == .None)
    portable_test_dispose_error(&dynamic_encode_error)
    if !dynamic_encode_ok do return
    defer delete(dynamic_data)
    dynamic_before := portable_test_copy(dynamic_data)
    defer delete(dynamic_before)

    ownership_state := Portable_Test_Counting_Allocator {
        backing = runtime.default_allocator(),
        fail_at = -1,
    }
    ownership_allocator := mem.Allocator {
        procedure = portable_test_counting_allocator_proc,
        data      = rawptr(&ownership_state),
    }
    owned_destination := Portable_Quaternion_Dynamic{}
    ownership_error, ownership_ok := hs.portable_decode(
        portable_test_any(Portable_Quaternion_Dynamic, &owned_destination),
        dynamic_data,
        alloc = ownership_allocator,
    )
    testing.expect(t, ownership_ok)
    testing.expect(t, ownership_error.kind == .None)
    testing.expect(t, len(owned_destination.values) == 2)
    if len(owned_destination.values) == 2 {
        testing.expect(t, portable_test_quaternion128_bits(owned_destination.values[0]) == q128_a_bits)
        testing.expect(t, portable_test_quaternion128_bits(owned_destination.values[1]) == q128_b_bits)
    }
    portable_test_dispose_error(&ownership_error)
    portable_test_dispose_error(&ownership_error)
    delete(owned_destination.values)
    testing.expect(t, ownership_state.outstanding == 0)

    encode_probe := Portable_Test_All_Fault_Allocator {
        backing = runtime.default_allocator(),
        fail_at = -1,
    }
    encode_probe_allocator := mem.Allocator {
        procedure = portable_test_all_fault_allocator_proc,
        data      = rawptr(&encode_probe),
    }
    probe_data, probe_error, probe_ok := hs.portable_encode(
        portable_test_any(Portable_Quaternion_Dynamic, &dynamic_source),
        alloc = encode_probe_allocator,
    )
    testing.expect(t, probe_ok)
    testing.expect(t, probe_error.kind == .None)
    testing.expect(t, encode_probe.attempts > 0)
    if probe_data != nil do delete(probe_data, encode_probe_allocator)
    portable_test_dispose_error(&probe_error)
    portable_test_dispose_error(&probe_error)
    testing.expect(t, encode_probe.outstanding == 0)

    for fail_at in 0 ..< encode_probe.attempts {
        failing := Portable_Test_All_Fault_Allocator {
            backing = runtime.default_allocator(),
            fail_at = fail_at,
        }
        failing_allocator := mem.Allocator {
            procedure = portable_test_all_fault_allocator_proc,
            data      = rawptr(&failing),
        }
        failed_data, failed_error, failed_ok := hs.portable_encode(
            portable_test_any(Portable_Quaternion_Dynamic, &dynamic_source),
            alloc = failing_allocator,
        )
        testing.expect(t, !failed_ok)
        testing.expect(t, failed_data == nil)
        testing.expect(t, failed_error.kind == .Limit_Exceeded)
        if failed_data != nil do delete(failed_data, failing_allocator)
        portable_test_dispose_error(&failed_error)
        portable_test_dispose_error(&failed_error)
        testing.expect(t, failing.outstanding == 0)
    }

    decode_probe := Portable_Test_All_Fault_Allocator {
        backing = runtime.default_allocator(),
        fail_at = -1,
    }
    decode_probe_allocator := mem.Allocator {
        procedure = portable_test_all_fault_allocator_proc,
        data      = rawptr(&decode_probe),
    }
    probe_destination := Portable_Quaternion_Dynamic{}
    decode_probe_error, decode_probe_ok := hs.portable_decode(
        portable_test_any(Portable_Quaternion_Dynamic, &probe_destination),
        dynamic_data,
        alloc = decode_probe_allocator,
    )
    testing.expect(t, decode_probe_ok)
    testing.expect(t, decode_probe_error.kind == .None)
    testing.expect(t, decode_probe.attempts > 0)
    portable_test_dispose_error(&decode_probe_error)
    portable_test_dispose_error(&decode_probe_error)
    delete(probe_destination.values)
    testing.expect(t, decode_probe.outstanding == 0)

    for fail_at in 0 ..< decode_probe.attempts {
        failing := Portable_Test_All_Fault_Allocator {
            backing = runtime.default_allocator(),
            fail_at = fail_at,
        }
        failing_allocator := mem.Allocator {
            procedure = portable_test_all_fault_allocator_proc,
            data      = rawptr(&failing),
        }
        failed_destination := Portable_Quaternion_Dynamic{}
        failed_error, failed_ok := hs.portable_decode(
            portable_test_any(Portable_Quaternion_Dynamic, &failed_destination),
            dynamic_data,
            alloc = failing_allocator,
        )
        testing.expect(t, !failed_ok)
        testing.expect(t, failed_error.kind == .Limit_Exceeded)
        if failed_destination.values != nil do delete(failed_destination.values)
        portable_test_dispose_error(&failed_error)
        portable_test_dispose_error(&failed_error)
        testing.expect(t, failing.outstanding == 0)
    }

    nil_allocator := mem.Allocator{}
    nil_data, nil_error, nil_ok := hs.portable_encode(
        portable_test_any(quaternion128, &dynamic_source.values[0]),
        alloc = nil_allocator,
    )
    testing.expect(t, !nil_ok)
    testing.expect(t, nil_data == nil)
    testing.expect(t, nil_error.kind == .Invalid_Argument)
    portable_test_dispose_error(&nil_error)
    portable_test_dispose_error(&nil_error)

    nil_destination := portable_test_quaternion128(q128_b_bits)
    nil_error, nil_ok = hs.portable_decode(
        portable_test_any(quaternion128, &nil_destination),
        dynamic_data,
        alloc = nil_allocator,
    )
    testing.expect(t, !nil_ok)
    testing.expect(t, nil_error.kind == .Invalid_Argument)
    testing.expect(t, portable_test_quaternion128_bits(nil_destination) == q128_b_bits)
    portable_test_dispose_error(&nil_error)
    portable_test_dispose_error(&nil_error)
    testing.expect(t, portable_test_bytes_equal(dynamic_data, dynamic_before))
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
