package main

import hs "../packages/hs"
import vehicles "../packages/vehicles"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

when ODIN_TEST {
    Fixture_Lifecycle_Test_Allocator :: struct {
        calls: int,
    }

    fixture_lifecycle_test_allocator_proc :: proc(
        data: rawptr,
        mode: mem.Allocator_Mode,
        size, alignment: int,
        old_memory: rawptr,
        old_size: int,
        location := #caller_location,
    ) -> (
        []byte,
        mem.Allocator_Error,
    ) {
        state := cast(^Fixture_Lifecycle_Test_Allocator)data
        state.calls += 1
        return nil, .Out_Of_Memory
    }

    fixture_lifecycle_test_allocator :: proc(state: ^Fixture_Lifecycle_Test_Allocator) -> mem.Allocator {
        return {data = rawptr(state), procedure = fixture_lifecycle_test_allocator_proc}
    }

    fixture_lifecycle_test_bytes_equal :: proc(a, b: ^Fixture) -> bool {
        if a == nil || b == nil do return false
        left := mem.byte_slice(rawptr(a), size_of(Fixture))
        right := mem.byte_slice(rawptr(b), size_of(Fixture))
        for value, index in left {
            if value != right[index] do return false
        }
        return true
    }

    fixture_lifecycle_test_kind_name :: proc(kind: vehicles.Aircraft_Kind) -> string {
        switch kind {
        case .Postale:
            return "P"
        case .Libellula:
            return "L"
        case .Libellula_Mk2:
            return "M"
        case .Rondine:
            return "R"
        }
        return "?"
    }

    fixture_lifecycle_test_vehicle :: proc(
        fixture: ^Fixture,
        occupant: vehicles.Fixture_Occupant,
    ) -> ^vehicles.Vehicle {
        switch occupant {
        case .On_Foot:
            return nil
        case .Car:
            return &fixture.car
        case .Postale:
            return &fixture.postale.vehicle
        case .Libellula, .Libellula_Mk2:
            return &fixture.libellula.vehicle
        case .Rondine:
            return &fixture.rondine.vehicle
        }
        return nil
    }

    fixture_lifecycle_test_active :: proc(occupant: vehicles.Fixture_Occupant) -> vehicles.Aircraft_Kind {
        switch occupant {
        case .Postale:
            return .Postale
        case .Libellula:
            return .Libellula
        case .Libellula_Mk2:
            return .Libellula_Mk2
        case .Rondine:
            return .Rondine
        case .On_Foot, .Car:
            return .Libellula_Mk2
        }
        return .Postale
    }

    fixture_lifecycle_test_seed_live :: proc(
        fixture: ^Fixture,
        occupant: vehicles.Fixture_Occupant,
        order: [4]vehicles.Aircraft_Kind,
    ) {
        fixture^ = {}
        fixture.structure_selected = 731
        fixture.radius = 19.5
        fixture.occupant = occupant == .Rondine ? .Car : .Rondine
        fixture.aircraft.count = 4
        fixture.aircraft.active = fixture_lifecycle_test_active(occupant)
        for kind, slot_index in order {
            fixture.aircraft.slots[slot_index] = {
                kind      = kind,
                name      = fixture_lifecycle_test_kind_name(kind),
                vehicle   = fixture_lifecycle_vehicle_for_kind(fixture, kind),
                available = slot_index % 2 == 0,
            }
        }
        fixture.pilot.mode = occupant == .On_Foot ? .On_Foot : .Driving
        target := fixture_lifecycle_test_vehicle(fixture, occupant)
        if target != nil {
            fixture.pilot.vehicle = target
            target.driver = &fixture.pilot
        }
    }

    fixture_lifecycle_test_detached_pointers_nil :: proc(fixture: ^Fixture) -> bool {
        if fixture.pilot.vehicle != nil ||
           fixture.car.driver != nil ||
           fixture.postale.vehicle.driver != nil ||
           fixture.libellula.vehicle.driver != nil ||
           fixture.rondine.vehicle.driver != nil {
            return false
        }
        for slot in fixture.aircraft.slots {
            if slot.vehicle != nil do return false
        }
        return true
    }

    fixture_lifecycle_test_bound :: proc(fixture: ^Fixture, occupant: vehicles.Fixture_Occupant) -> bool {
        for slot_index in 0 ..< fixture.aircraft.count {
            slot := &fixture.aircraft.slots[slot_index]
            if slot.vehicle != fixture_lifecycle_vehicle_for_kind(fixture, slot.kind) do return false
        }
        for slot_index in fixture.aircraft.count ..< len(fixture.aircraft.slots) {
            if fixture.aircraft.slots[slot_index].vehicle != nil do return false
        }
        expected := fixture_lifecycle_test_vehicle(fixture, occupant)
        if fixture.pilot.vehicle != expected do return false
        expected_mode := occupant == .On_Foot ? vehicles.Occupancy_Mode.On_Foot : .Driving
        if fixture.pilot.mode != expected_mode do return false
        drivers := [?]^vehicles.Character {
            fixture.car.driver,
            fixture.postale.vehicle.driver,
            fixture.libellula.vehicle.driver,
            fixture.rondine.vehicle.driver,
        }
        driver_count := 0
        for driver in drivers {
            if driver != nil {
                if driver != &fixture.pilot do return false
                driver_count += 1
            }
        }
        return driver_count == (occupant == .On_Foot ? 0 : 1)
    }

    fixture_lifecycle_test_plan_equal :: proc(a, b: Fixture_Lifecycle_Bind_Plan) -> bool {
        if a.occupant != b.occupant do return false
        for value, index in a.kind_slots {
            if value != b.kind_slots[index] do return false
        }
        return true
    }

    fixture_lifecycle_test_expect_detached_error :: proc(
        t: ^testing.T,
        candidate, snapshot: ^Fixture,
        expected_kind: Fixture_Lifecycle_Error_Kind,
        expected_slot: int = -1,
    ) {
        snapshot^ = candidate^
        plan := Fixture_Lifecycle_Bind_Plan {
            occupant   = .Rondine,
            kind_slots = {7, 6, 5, 4},
        }
        plan_snapshot := plan
        allocator_state: Fixture_Lifecycle_Test_Allocator
        previous_allocator := context.allocator
        context.allocator = fixture_lifecycle_test_allocator(&allocator_state)
        prepare_error := fixture_lifecycle_prepare(candidate, &plan)
        bind_error := fixture_lifecycle_bind(candidate)
        context.allocator = previous_allocator

        testing.expect(t, prepare_error.kind == expected_kind)
        testing.expect_value(t, prepare_error.slot_index, expected_slot)
        testing.expect(t, bind_error.kind == expected_kind)
        testing.expect_value(t, bind_error.slot_index, expected_slot)
        testing.expect_value(t, allocator_state.calls, 0)
        testing.expect(t, fixture_lifecycle_test_plan_equal(plan, plan_snapshot))
        testing.expect(t, fixture_lifecycle_test_bytes_equal(candidate, snapshot))
    }

    fixture_lifecycle_test_expect_live_error :: proc(
        t: ^testing.T,
        source, source_snapshot, destination, destination_snapshot: ^Fixture,
        expected_kind: Fixture_Lifecycle_Error_Kind,
        expected_slot: int = -1,
    ) {
        source_snapshot^ = source^
        destination^ = {}
        destination.structure_selected = -991
        destination.radius = -77
        destination_snapshot^ = destination^
        allocator_state: Fixture_Lifecycle_Test_Allocator
        previous_allocator := context.allocator
        context.allocator = fixture_lifecycle_test_allocator(&allocator_state)
        _, derive_error := fixture_lifecycle_derive(source)
        detach_error := fixture_lifecycle_detach(source, destination)
        context.allocator = previous_allocator

        testing.expect(t, derive_error.kind == expected_kind)
        testing.expect_value(t, derive_error.slot_index, expected_slot)
        testing.expect(t, detach_error.kind == expected_kind)
        testing.expect_value(t, detach_error.slot_index, expected_slot)
        testing.expect_value(t, allocator_state.calls, 0)
        testing.expect(t, fixture_lifecycle_test_bytes_equal(source, source_snapshot))
        testing.expect(t, fixture_lifecycle_test_bytes_equal(destination, destination_snapshot))
    }

    @(test)
    fixture_lifecycle_detach_derives_all_identities_without_allocation :: proc(t: ^testing.T) {
        source := new(Fixture)
        detached := new(Fixture)
        snapshot := new(Fixture)
        defer free(source)
        defer free(detached)
        defer free(snapshot)

        occupants := [?]vehicles.Fixture_Occupant{.On_Foot, .Car, .Postale, .Libellula, .Libellula_Mk2, .Rondine}
        orders := [?][4]vehicles.Aircraft_Kind {
            {.Postale, .Libellula, .Libellula_Mk2, .Rondine},
            {.Rondine, .Libellula_Mk2, .Postale, .Libellula},
        }
        for occupant, occupant_index in occupants {
            fixture_lifecycle_test_seed_live(source, occupant, orders[occupant_index % len(orders)])
            snapshot^ = source^
            detached^ = {}
            detached.structure_selected = -909

            allocator_state: Fixture_Lifecycle_Test_Allocator
            previous_allocator := context.allocator
            context.allocator = fixture_lifecycle_test_allocator(&allocator_state)
            derived, derive_error := fixture_lifecycle_derive(source)
            detach_error := fixture_lifecycle_detach(source, detached)
            context.allocator = previous_allocator

            testing.expect(t, derive_error.kind == .None && derived == occupant)
            testing.expect(t, detach_error.kind == .None)
            testing.expect_value(t, allocator_state.calls, 0)
            testing.expect(t, fixture_lifecycle_test_bytes_equal(source, snapshot))
            testing.expect(t, detached.occupant == occupant)
            testing.expect_value(t, detached.structure_selected, 731)
            testing.expect(t, fixture_lifecycle_test_detached_pointers_nil(detached))
            for slot_index in 0 ..< 4 {
                testing.expect(t, detached.aircraft.slots[slot_index].kind == source.aircraft.slots[slot_index].kind)
                testing.expect(t, detached.aircraft.slots[slot_index].name == source.aircraft.slots[slot_index].name)
                testing.expect(
                    t,
                    detached.aircraft.slots[slot_index].available == source.aircraft.slots[slot_index].available,
                )
            }
        }

        detached^ = {}
        detached.structure_selected = -444
        source.aircraft.count = 3
        error := fixture_lifecycle_detach(source, detached)
        testing.expect(t, error.kind == .Invalid_Fleet_Count)
        testing.expect_value(t, detached.structure_selected, -444)
        testing.expect(t, fixture_lifecycle_detach(source, source).kind == .Aliased_Arguments)
        testing.expect(t, fixture_lifecycle_detach(nil, detached).kind == .Invalid_Argument)
    }

    @(test)
    fixture_lifecycle_prepare_and_bind_use_destination_owned_addresses :: proc(t: ^testing.T) {
        source := new(Fixture)
        candidate := new(Fixture)
        target := new(Fixture)
        defer free(source)
        defer free(candidate)
        defer free(target)

        occupants := [?]vehicles.Fixture_Occupant{.On_Foot, .Car, .Postale, .Libellula, .Libellula_Mk2, .Rondine}
        orders := [?][4]vehicles.Aircraft_Kind {
            {.Libellula, .Rondine, .Postale, .Libellula_Mk2},
            {.Libellula_Mk2, .Postale, .Rondine, .Libellula},
            {.Rondine, .Libellula, .Libellula_Mk2, .Postale},
        }
        for occupant, occupant_index in occupants {
            fixture_lifecycle_test_seed_live(source, occupant, orders[occupant_index % len(orders)])
            testing.expect(t, fixture_lifecycle_detach(source, candidate).kind == .None)
            candidate.pilot.mode = occupant == .On_Foot ? .Driving : .On_Foot

            plan := Fixture_Lifecycle_Bind_Plan {
                occupant   = .Car,
                kind_slots = {7, 6, 5, 4},
            }
            allocator_state: Fixture_Lifecycle_Test_Allocator
            previous_allocator := context.allocator
            context.allocator = fixture_lifecycle_test_allocator(&allocator_state)
            prepare_error := fixture_lifecycle_prepare(candidate, &plan)
            context.allocator = previous_allocator
            testing.expect(t, prepare_error.kind == .None)
            testing.expect_value(t, allocator_state.calls, 0)

            target^ = candidate^
            fixture_lifecycle_apply(target, &plan)
            testing.expect(t, target.occupant == occupant)
            testing.expect(t, fixture_lifecycle_test_bound(target, occupant))
            if occupant != .On_Foot {
                testing.expect(t, target.pilot.vehicle != source.pilot.vehicle)
                testing.expect(t, target.pilot.vehicle != candidate.pilot.vehicle)
            }
            for slot_index in 0 ..< target.aircraft.count {
                testing.expect(
                    t,
                    target.aircraft.slots[slot_index].vehicle != source.aircraft.slots[slot_index].vehicle,
                )
            }

            testing.expect(t, fixture_lifecycle_detach(source, candidate).kind == .None)
            candidate.pilot.mode = occupant == .On_Foot ? .Driving : .On_Foot
            bind_error := fixture_lifecycle_bind(candidate)
            testing.expect(t, bind_error.kind == .None)
            testing.expect(t, fixture_lifecycle_test_bound(candidate, occupant))
        }
    }

    @(test)
    fixture_lifecycle_hostile_states_fail_atomically :: proc(t: ^testing.T) {
        source := new(Fixture)
        source_snapshot := new(Fixture)
        candidate := new(Fixture)
        candidate_snapshot := new(Fixture)
        destination := new(Fixture)
        destination_snapshot := new(Fixture)
        defer free(source)
        defer free(source_snapshot)
        defer free(candidate)
        defer free(candidate_snapshot)
        defer free(destination)
        defer free(destination_snapshot)

        order := [4]vehicles.Aircraft_Kind{.Libellula, .Rondine, .Postale, .Libellula_Mk2}
        fixture_lifecycle_test_seed_live(source, .On_Foot, order)

        counts := [?]int{-1, 0, 3, 5, 9}
        for count in counts {
            testing.expect(t, fixture_lifecycle_detach(source, candidate).kind == .None)
            candidate.aircraft.count = count
            fixture_lifecycle_test_expect_detached_error(t, candidate, candidate_snapshot, .Invalid_Fleet_Count)
        }

        testing.expect(t, fixture_lifecycle_detach(source, candidate).kind == .None)
        candidate.aircraft.active = cast(vehicles.Aircraft_Kind)u8(255)
        fixture_lifecycle_test_expect_detached_error(t, candidate, candidate_snapshot, .Invalid_Active)

        testing.expect(t, fixture_lifecycle_detach(source, candidate).kind == .None)
        candidate.occupant = cast(vehicles.Fixture_Occupant)u8(255)
        fixture_lifecycle_test_expect_detached_error(t, candidate, candidate_snapshot, .Invalid_Occupant)

        testing.expect(t, fixture_lifecycle_detach(source, candidate).kind == .None)
        candidate.pilot.mode = cast(vehicles.Occupancy_Mode)u8(255)
        fixture_lifecycle_test_expect_detached_error(t, candidate, candidate_snapshot, .Invalid_Occupancy_Mode)

        for slot_index in 0 ..< len(candidate.aircraft.slots) {
            testing.expect(t, fixture_lifecycle_detach(source, candidate).kind == .None)
            candidate.aircraft.slots[slot_index].kind = cast(vehicles.Aircraft_Kind)u8(255)
            fixture_lifecycle_test_expect_detached_error(
                t,
                candidate,
                candidate_snapshot,
                .Invalid_Slot_Kind,
                slot_index,
            )
        }

        testing.expect(t, fixture_lifecycle_detach(source, candidate).kind == .None)
        candidate.aircraft.slots[3].kind = candidate.aircraft.slots[0].kind
        fixture_lifecycle_test_expect_detached_error(t, candidate, candidate_snapshot, .Duplicate_Slot_Kind, 3)

        for slot_index in 0 ..< len(candidate.aircraft.slots) {
            testing.expect(t, fixture_lifecycle_detach(source, candidate).kind == .None)
            candidate.aircraft.slots[slot_index].vehicle = &candidate.car
            fixture_lifecycle_test_expect_detached_error(
                t,
                candidate,
                candidate_snapshot,
                .Invalid_Detached_Slot_Pointer,
                slot_index,
            )
        }

        testing.expect(t, fixture_lifecycle_detach(source, candidate).kind == .None)
        candidate.pilot.vehicle = &candidate.car
        fixture_lifecycle_test_expect_detached_error(t, candidate, candidate_snapshot, .Invalid_Detached_Pilot_Pointer)

        foreign_character := vehicles.Character{}
        driver_targets := [?]^^vehicles.Character {
            &candidate.car.driver,
            &candidate.postale.vehicle.driver,
            &candidate.libellula.vehicle.driver,
            &candidate.rondine.vehicle.driver,
        }
        driver_slots := [?]int{-1, 2, 0, 1}
        for driver_target, driver_index in driver_targets {
            testing.expect(t, fixture_lifecycle_detach(source, candidate).kind == .None)
            driver_target^ = &foreign_character
            fixture_lifecycle_test_expect_detached_error(
                t,
                candidate,
                candidate_snapshot,
                .Invalid_Detached_Driver_Pointer,
                driver_slots[driver_index],
            )
        }

        aircraft_occupants := [?]vehicles.Fixture_Occupant{.Postale, .Libellula, .Libellula_Mk2, .Rondine}
        occupant_slots := [?]int{2, 0, 3, 1}
        for occupant, occupant_index in aircraft_occupants {
            fixture_lifecycle_test_seed_live(source, occupant, order)
            testing.expect(t, fixture_lifecycle_detach(source, candidate).kind == .None)
            candidate.aircraft.active = occupant == .Postale ? .Rondine : .Postale
            fixture_lifecycle_test_expect_detached_error(
                t,
                candidate,
                candidate_snapshot,
                .Occupant_Active_Mismatch,
                occupant_slots[occupant_index],
            )
        }

        locked_occupants := [?]vehicles.Fixture_Occupant{.Car, .Postale, .Libellula, .Libellula_Mk2, .Rondine}
        locked_slots := [?]int{-1, 2, 0, 3, 1}
        for occupant, occupant_index in locked_occupants {
            fixture_lifecycle_test_seed_live(source, occupant, order)
            fixture_lifecycle_test_vehicle(source, occupant).locked = true
            fixture_lifecycle_test_expect_live_error(
                t,
                source,
                source_snapshot,
                destination,
                destination_snapshot,
                .Occupied_Vehicle_Locked,
                locked_slots[occupant_index],
            )

            fixture_lifecycle_test_vehicle(source, occupant).locked = false
            testing.expect(t, fixture_lifecycle_detach(source, candidate).kind == .None)
            fixture_lifecycle_test_vehicle(candidate, occupant).locked = true
            fixture_lifecycle_test_expect_detached_error(
                t,
                candidate,
                candidate_snapshot,
                .Occupied_Vehicle_Locked,
                locked_slots[occupant_index],
            )
        }

        foreign_vehicle := vehicles.Vehicle{}
        fixture_lifecycle_test_seed_live(source, .On_Foot, order)
        source.aircraft.slots[0].vehicle = &foreign_vehicle
        fixture_lifecycle_test_expect_live_error(
            t,
            source,
            source_snapshot,
            destination,
            destination_snapshot,
            .Invalid_Live_Slot_Pointer,
            0,
        )
        fixture_lifecycle_test_seed_live(source, .On_Foot, order)
        source.aircraft.slots[0].vehicle = &source.car
        fixture_lifecycle_test_expect_live_error(
            t,
            source,
            source_snapshot,
            destination,
            destination_snapshot,
            .Invalid_Live_Slot_Pointer,
            0,
        )

        fixture_lifecycle_test_seed_live(source, .Car, order)
        source.car.driver = nil
        fixture_lifecycle_test_expect_live_error(
            t,
            source,
            source_snapshot,
            destination,
            destination_snapshot,
            .Invalid_Live_Occupancy,
        )
        fixture_lifecycle_test_seed_live(source, .Car, order)
        source.postale.vehicle.driver = &source.pilot
        fixture_lifecycle_test_expect_live_error(
            t,
            source,
            source_snapshot,
            destination,
            destination_snapshot,
            .Invalid_Live_Occupancy,
        )
        fixture_lifecycle_test_seed_live(source, .Car, order)
        source.car.driver = &foreign_character
        fixture_lifecycle_test_expect_live_error(
            t,
            source,
            source_snapshot,
            destination,
            destination_snapshot,
            .Invalid_Live_Occupancy,
        )

        live_counts := [?]int{-1, 9}
        for count in live_counts {
            fixture_lifecycle_test_seed_live(source, .On_Foot, order)
            source.aircraft.count = count
            fixture_lifecycle_test_expect_live_error(
                t,
                source,
                source_snapshot,
                destination,
                destination_snapshot,
                .Invalid_Fleet_Count,
            )
        }
        fixture_lifecycle_test_seed_live(source, .On_Foot, order)
        source.aircraft.slots[2].vehicle = nil
        fixture_lifecycle_test_expect_live_error(
            t,
            source,
            source_snapshot,
            destination,
            destination_snapshot,
            .Invalid_Live_Slot_Pointer,
            2,
        )

        fixture_lifecycle_test_seed_live(source, .Car, order)
        source.pilot.vehicle = &foreign_vehicle
        fixture_lifecycle_test_expect_live_error(
            t,
            source,
            source_snapshot,
            destination,
            destination_snapshot,
            .Invalid_Live_Occupancy,
        )
        physical_drivers := [?]^^vehicles.Character {
            &source.car.driver,
            &source.postale.vehicle.driver,
            &source.libellula.vehicle.driver,
            &source.rondine.vehicle.driver,
        }
        for driver in physical_drivers {
            fixture_lifecycle_test_seed_live(source, .On_Foot, order)
            driver^ = &foreign_character
            fixture_lifecycle_test_expect_live_error(
                t,
                source,
                source_snapshot,
                destination,
                destination_snapshot,
                .Invalid_Live_Occupancy,
            )
        }

        fixture_lifecycle_test_seed_live(source, .On_Foot, order)
        source.car.locked = true
        source.postale.vehicle.locked = true
        source.libellula.vehicle.locked = true
        source.rondine.vehicle.locked = true
        testing.expect(t, fixture_lifecycle_detach(source, candidate).kind == .None)
        testing.expect(t, fixture_lifecycle_bind(candidate).kind == .None)
        testing.expect(t, fixture_lifecycle_test_bound(candidate, .On_Foot))

        for occupant in aircraft_occupants {
            fixture_lifecycle_test_seed_live(source, occupant, order)
            for &slot in source.aircraft.slots[:source.aircraft.count] {
                if slot.kind == source.aircraft.active do slot.available = false
            }
            testing.expect(t, fixture_lifecycle_detach(source, candidate).kind == .None)
            testing.expect(t, fixture_lifecycle_bind(candidate).kind == .None)
            testing.expect(t, fixture_lifecycle_test_bound(candidate, occupant))
        }

        fixture_lifecycle_test_seed_live(source, .On_Foot, order)
        testing.expect(t, fixture_lifecycle_detach(source, candidate).kind == .None)
        plan := Fixture_Lifecycle_Bind_Plan {
            occupant   = .Rondine,
            kind_slots = {7, 6, 5, 4},
        }
        plan_snapshot := plan
        testing.expect(t, fixture_lifecycle_prepare(nil, &plan).kind == .Invalid_Argument)
        testing.expect(t, fixture_lifecycle_prepare(candidate, nil).kind == .Invalid_Argument)
        testing.expect(t, fixture_lifecycle_test_plan_equal(plan, plan_snapshot))
    }

    @(test)
    fixture_lifecycle_hot_state_round_trips_all_identities :: proc(t: ^testing.T) {
        directory, directory_error := os.make_directory_temp("", "adriatic-lifecycle-*", context.allocator)
        testing.expect(t, directory_error == nil)
        if directory_error != nil do return
        path, path_error := strings.concatenate({directory, "/state.bin"}, context.allocator)
        testing.expect(t, path_error == nil)
        if path_error != nil do return
        defer {
            _ = os.remove(path)
            _ = os.remove(directory)
            delete(path)
            delete(directory)
        }

        source := new(Editor)
        source_snapshot := new(Editor)
        payload_state := new(Editor)
        restored := new(Editor)
        defer free(source)
        defer free(source_snapshot)
        defer free(payload_state)
        defer free(restored)

        occupants := [?]vehicles.Fixture_Occupant{.On_Foot, .Car, .Postale, .Libellula, .Libellula_Mk2, .Rondine}
        orders := [?][4]vehicles.Aircraft_Kind {
            {.Postale, .Libellula, .Libellula_Mk2, .Rondine},
            {.Rondine, .Postale, .Libellula_Mk2, .Libellula},
            {.Libellula_Mk2, .Libellula, .Rondine, .Postale},
        }
        backing_allocator := context.allocator
        for occupant, occupant_index in occupants {
            fixture_lifecycle_test_seed_live(&source.fixture, occupant, orders[occupant_index % len(orders)])
            source_snapshot^ = source^
            payload_state^ = {}
            restored^ = {}

            arena, arena_ok := fixture_migration_arena_allocate(backing_allocator)
            testing.expect(t, arena_ok)
            if !arena_ok do return
            arena_allocator := mem.dynamic_arena_allocator(arena)

            previous_allocator := context.allocator
            context.allocator = arena_allocator
            save_ok := hot_state_save(source, path)
            context.allocator = previous_allocator
            testing.expect(t, save_ok)
            testing.expect(t, fixture_lifecycle_test_bytes_equal(&source.fixture, &source_snapshot.fixture))
            if !save_ok {
                fixture_migration_arena_dispose(arena, backing_allocator)
                return
            }

            data, read_error := os.read_entire_file(path, backing_allocator)
            testing.expect(t, read_error == nil)
            if read_error != nil {
                fixture_migration_arena_dispose(arena, backing_allocator)
                return
            }
            testing.expect(t, len(data) > size_of(Hot_State_File_Header))
            header := cast(^Hot_State_File_Header)(&data[0])
            payload := data[size_of(Hot_State_File_Header):]
            testing.expect(t, hot_state_header_valid(header, len(payload)))
            context.allocator = arena_allocator
            _ = hs.deserialize(payload_state, payload, {.Dynamics}, arena_allocator)
            context.allocator = previous_allocator
            testing.expect(t, payload_state.occupant == occupant)
            testing.expect(t, fixture_lifecycle_test_detached_pointers_nil(&payload_state.fixture))

            context.allocator = arena_allocator
            load_result := hot_state_load(restored, path)
            context.allocator = previous_allocator
            testing.expect(t, load_result == .Loaded)
            testing.expect(t, fixture_lifecycle_test_bound(&restored.fixture, occupant))
            testing.expect(
                t,
                restored.pilot.vehicle == nil ||
                (restored.pilot.vehicle != source.pilot.vehicle &&
                        restored.pilot.vehicle != payload_state.pilot.vehicle),
            )
            derived, derive_error := fixture_lifecycle_derive(&restored.fixture)
            testing.expect(t, derive_error.kind == .None && derived == occupant)
            testing.expect(t, fixture_lifecycle_test_bytes_equal(&source.fixture, &source_snapshot.fixture))

            context.allocator = arena_allocator
            vehicles.libellula_mesh_destroy(&restored.libellula_visual_mesh)
            delete(restored.libellula_projected_faces)
            structure_storage_destroy(restored)
            context.allocator = previous_allocator
            delete(data, backing_allocator)
            fixture_migration_arena_dispose(arena, backing_allocator)
        }

        fixture_lifecycle_test_seed_live(&source.fixture, .Car, {.Postale, .Libellula, .Libellula_Mk2, .Rondine})
        source.postale.vehicle.driver = &source.pilot
        testing.expect(t, !hot_state_save(source, path))

        fixture_lifecycle_test_seed_live(&source.fixture, .On_Foot, {.Postale, .Libellula, .Libellula_Mk2, .Rondine})
        payload_state^ = {}
        restored^ = {}
        arena, arena_ok := fixture_migration_arena_allocate(backing_allocator)
        testing.expect(t, arena_ok)
        if !arena_ok do return
        arena_allocator := mem.dynamic_arena_allocator(arena)
        previous_allocator := context.allocator
        context.allocator = arena_allocator
        save_ok := hot_state_save(source, path)
        context.allocator = previous_allocator
        testing.expect(t, save_ok)
        if !save_ok {
            fixture_migration_arena_dispose(arena, backing_allocator)
            return
        }

        data, read_error := os.read_entire_file(path, backing_allocator)
        testing.expect(t, read_error == nil)
        if read_error != nil {
            fixture_migration_arena_dispose(arena, backing_allocator)
            return
        }
        payload := data[size_of(Hot_State_File_Header):]
        context.allocator = arena_allocator
        _ = hs.deserialize(payload_state, payload, {.Dynamics}, arena_allocator)
        payload_state.aircraft.count = 3
        invalid_payload := hs.serialize(payload_state, {.Dynamics}, arena_allocator)
        context.allocator = previous_allocator
        invalid_header := Hot_State_File_Header {
            magic        = HOT_STATE_FILE_MAGIC,
            version      = HOT_STATE_FILE_VERSION,
            type_hash    = hs.type_hash(Editor),
            payload_size = u64(len(invalid_payload)),
        }
        invalid_file := make([dynamic]byte, 0, size_of(invalid_header) + len(invalid_payload), arena_allocator)
        append(&invalid_file, ..mem.ptr_to_bytes(&invalid_header))
        append(&invalid_file, ..invalid_payload)
        testing.expect(t, os.write_entire_file(path, invalid_file[:]) == nil)
        context.allocator = arena_allocator
        invalid_result := hot_state_load(restored, path)
        context.allocator = previous_allocator
        testing.expect(t, invalid_result == .Invalid)
        delete(data, backing_allocator)
        fixture_migration_arena_dispose(arena, backing_allocator)
    }
}
