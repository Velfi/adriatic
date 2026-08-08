package tests

import "core:mem"
import "core:testing"
import hs "zelda_engine:hs"

HS_Serializer_Bulk_Index :: enum u8 {
    First,
    Second,
    Third,
}

HS_Serializer_Bulk_Nested :: struct {
    bytes:          [3]u8,
    floats:         [2]f32,
    indexed_bytes:  [HS_Serializer_Bulk_Index]u8,
    indexed_floats: [HS_Serializer_Bulk_Index]f32,
}

HS_Serializer_Bulk_State :: struct {
    bytes:  [4]u8,
    floats: [3]f32,
    nested: HS_Serializer_Bulk_Nested,
    label:  string,
}

hs_serializer_bytes_equal :: proc(a, b: []byte) -> bool {
    if len(a) != len(b) do return false
    for value, index in a {
        if value != b[index] do return false
    }
    return true
}

hs_serializer_body_start :: proc(data: []byte) -> int {
    header := cast(^hs.SaveHeader)(&data[0])
    return(
        size_of(hs.SaveHeader) +
        len(header.types) * size_of(hs.TypeInfo) +
        len(header.struct_fields) * size_of(hs.Struct_Field) +
        len(header.bit_fields) * size_of(hs.Bit_Field) +
        len(header.enum_fields) * size_of(hs.Enum_Field) +
        len(header.handles) * size_of(hs.TypeInfo_Handle) +
        len(header.arena) \
    )
}

hs_serializer_body_field_equal :: proc(
    data: []byte,
    body_start: int,
    offset: uintptr,
    value: rawptr,
    size: int,
) -> bool {
    start := body_start + int(offset)
    actual := data[start:start + size]
    expected := mem.byte_slice(value, size)
    return hs_serializer_bytes_equal(actual, expected)
}

hs_serializer_destroy_state :: proc(state: ^HS_Serializer_Bulk_State) {
    if state == nil do return
    delete(state.label)
}

@(test)
hs_serializer_fixed_leaf_arrays_preserve_wire_and_dynamic_siblings :: proc(t: ^testing.T) {
    source := HS_Serializer_Bulk_State {
        bytes = {1, 2, 127, 255},
        floats = {transmute(f32)u32(0x3f800000), transmute(f32)u32(0x80000000), transmute(f32)u32(0x7fc00001)},
        nested = {
            bytes = {8, 9, 10},
            floats = {transmute(f32)u32(0x40400000), transmute(f32)u32(0xff800000)},
            indexed_bytes = {.First = 11, .Second = 12, .Third = 13},
            indexed_floats = {
                .First = transmute(f32)u32(0x00000001),
                .Second = transmute(f32)u32(0x3f000000),
                .Third = transmute(f32)u32(0x7f800000),
            },
        },
        label = "dynamic sibling",
    }

    encoded := hs.serialize(&source, {.Dynamics}, context.allocator)
    defer delete(encoded)

    body_start := hs_serializer_body_start(encoded)
    testing.expect(
        t,
        hs_serializer_body_field_equal(
            encoded,
            body_start,
            offset_of(HS_Serializer_Bulk_State, bytes),
            rawptr(&source.bytes),
            size_of(source.bytes),
        ),
    )
    testing.expect(
        t,
        hs_serializer_body_field_equal(
            encoded,
            body_start,
            offset_of(HS_Serializer_Bulk_State, floats),
            rawptr(&source.floats),
            size_of(source.floats),
        ),
    )
    testing.expect(
        t,
        hs_serializer_body_field_equal(
            encoded,
            body_start,
            offset_of(HS_Serializer_Bulk_State, nested),
            rawptr(&source.nested),
            size_of(source.nested),
        ),
    )

    destination := HS_Serializer_Bulk_State{}
    _ = hs.deserialize(&destination, encoded, {.Dynamics}, context.allocator)
    defer hs_serializer_destroy_state(&destination)

    testing.expect(t, destination.bytes == source.bytes)
    testing.expect(
        t,
        hs_serializer_bytes_equal(mem.ptr_to_bytes(&destination.floats), mem.ptr_to_bytes(&source.floats)),
    )
    testing.expect(t, destination.nested.bytes == source.nested.bytes)
    testing.expect(
        t,
        hs_serializer_bytes_equal(
            mem.ptr_to_bytes(&destination.nested.floats),
            mem.ptr_to_bytes(&source.nested.floats),
        ),
    )
    testing.expect(t, destination.nested.indexed_bytes == source.nested.indexed_bytes)
    testing.expect(
        t,
        hs_serializer_bytes_equal(
            mem.ptr_to_bytes(&destination.nested.indexed_floats),
            mem.ptr_to_bytes(&source.nested.indexed_floats),
        ),
    )
    testing.expect(t, destination.label == source.label)
}
