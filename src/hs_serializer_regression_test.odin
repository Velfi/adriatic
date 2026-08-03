package main

import hs "../packages/hs"
import vehicles "../packages/vehicles"
import "core:mem"
import "core:testing"

when ODIN_TEST {

HS_Serializer_Static_String_Slot :: struct {
    kind:      u8,
    name:      string,
    vehicle:   ^u8,
    available: bool,
}

HS_Serializer_Static_String_State :: struct {
    slots: [8]HS_Serializer_Static_String_Slot,
}

@(test)
hs_serializer_static_array_strings_round_trip :: proc(t: ^testing.T) {
    source := HS_Serializer_Static_String_State {
        slots = {
            {name = "P"},
            {name = "L"},
            {name = "M"},
            {name = "R"},
            {},
            {},
            {},
            {},
        },
    }
    encoded := hs.serialize(&source, {.Dynamics}, context.allocator)
    defer delete(encoded)

    destination: HS_Serializer_Static_String_State
    _ = hs.deserialize(&destination, encoded, {.Dynamics}, context.allocator)
    for index in 0 ..< 4 {
        testing.expect(t, destination.slots[index].name == source.slots[index].name)
    }
    for &slot in destination.slots do delete(slot.name)
}

@(test)
hs_serializer_aircraft_fleet_strings_round_trip :: proc(t: ^testing.T) {
    source := vehicles.Aircraft_Fleet {
        slots = {
            {kind = .Postale, name = "P", available = true},
            {kind = .Libellula, name = "L", available = true},
            {kind = .Libellula_Mk2, name = "M", available = true},
            {kind = .Rondine, name = "R", available = true},
            {},
            {},
            {},
            {},
        },
        count = 4,
        active = .Postale,
    }
    encoded := hs.serialize(&source, {.Dynamics}, context.allocator)
    defer delete(encoded)

    destination: vehicles.Aircraft_Fleet
    _ = hs.deserialize(&destination, encoded, {.Dynamics}, context.allocator)
    second_destination: vehicles.Aircraft_Fleet
    _ = hs.deserialize(&second_destination, encoded, {.Dynamics}, context.allocator)
    for index in 0 ..< source.count {
        testing.expect(t, destination.slots[index].name == source.slots[index].name)
        testing.expect(t, destination.slots[index].available == source.slots[index].available)
        testing.expect(t, second_destination.slots[index].name == source.slots[index].name)
        testing.expect(t, second_destination.slots[index].available == source.slots[index].available)
    }
    for &slot in destination.slots do delete(slot.name)
    for &slot in second_destination.slots do delete(slot.name)
}

@(test)
hs_serializer_fixture_strings_round_trip_in_arena :: proc(t: ^testing.T) {
    source := new(Fixture)
    detached := new(Fixture)
    defer free(source)
    defer free(detached)
    fixture_lifecycle_test_seed_live(source, .Postale, {.Postale, .Libellula, .Libellula_Mk2, .Rondine})
    testing.expect(t, fixture_lifecycle_detach(source, detached).kind == .None)

    arena, arena_ok := fixture_migration_arena_allocate(context.allocator)
    testing.expect(t, arena_ok)
    if !arena_ok do return
    arena_allocator := mem.dynamic_arena_allocator(arena)
    previous_allocator := context.allocator
    context.allocator = arena_allocator
    encoded := hs.serialize(detached, {.Dynamics}, arena_allocator)
    restored := new(Fixture, arena_allocator)
    _ = hs.deserialize(restored, encoded, {.Dynamics}, arena_allocator)
    context.allocator = previous_allocator

    testing.expect(t, restored.aircraft.slots[0].name == detached.aircraft.slots[0].name)
    testing.expect(t, restored.aircraft.slots[1].name == detached.aircraft.slots[1].name)
    fixture_migration_arena_dispose(arena, previous_allocator)
}

}
