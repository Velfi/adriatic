package main

import vehicles "../packages/vehicles"

Fixture_Lifecycle_Error_Kind :: enum {
    None,
    Invalid_Argument,
    Aliased_Arguments,
    Invalid_Fleet_Count,
    Invalid_Active,
    Invalid_Slot_Kind,
    Duplicate_Slot_Kind,
    Missing_Slot_Kind,
    Invalid_Live_Slot_Pointer,
    Invalid_Detached_Slot_Pointer,
    Invalid_Detached_Pilot_Pointer,
    Invalid_Detached_Driver_Pointer,
    Invalid_Occupant,
    Invalid_Occupancy_Mode,
    Invalid_Live_Occupancy,
    Occupant_Active_Mismatch,
    Occupied_Vehicle_Locked,
}

Fixture_Lifecycle_Error :: struct {
    kind:       Fixture_Lifecycle_Error_Kind,
    slot_index: int,
}

Fixture_Lifecycle_Bind_Plan :: struct {
    occupant:   vehicles.Fixture_Occupant,
    kind_slots: [4]int,
}

fixture_lifecycle_error :: proc(kind: Fixture_Lifecycle_Error_Kind, slot_index := -1) -> Fixture_Lifecycle_Error {
    return {kind = kind, slot_index = slot_index}
}

fixture_lifecycle_kind_index :: proc(kind: vehicles.Aircraft_Kind) -> (int, bool) {
    switch kind {
    case .Postale:
        return 0, true
    case .Libellula:
        return 1, true
    case .Libellula_Mk2:
        return 2, true
    case .Rondine:
        return 3, true
    }
    return 0, false
}

fixture_lifecycle_vehicle_for_kind :: proc(fixture: ^Fixture, kind: vehicles.Aircraft_Kind) -> ^vehicles.Vehicle {
    switch kind {
    case .Postale:
        return &fixture.postale.vehicle
    case .Libellula, .Libellula_Mk2:
        return &fixture.libellula.vehicle
    case .Rondine:
        return &fixture.rondine.vehicle
    }
    return nil
}

fixture_lifecycle_fleet_preflight :: proc(
    fixture: ^Fixture,
    detached: bool,
    kind_slots: ^[4]int,
) -> Fixture_Lifecycle_Error {
    if fixture == nil || kind_slots == nil {
        return fixture_lifecycle_error(.Invalid_Argument)
    }
    if fixture.aircraft.count != 4 {
        return fixture_lifecycle_error(.Invalid_Fleet_Count)
    }

    kind_slots^ = {-1, -1, -1, -1}
    for slot_index in 0 ..< fixture.aircraft.count {
        slot := &fixture.aircraft.slots[slot_index]
        kind_index, valid := fixture_lifecycle_kind_index(slot.kind)
        if !valid {
            return fixture_lifecycle_error(.Invalid_Slot_Kind, slot_index)
        }
        if kind_slots[kind_index] >= 0 {
            return fixture_lifecycle_error(.Duplicate_Slot_Kind, slot_index)
        }
        kind_slots[kind_index] = slot_index
    }
    for kind_index in 0 ..< len(kind_slots^) {
        if kind_slots[kind_index] < 0 {
            return fixture_lifecycle_error(.Missing_Slot_Kind, kind_index)
        }
    }

    for slot_index in fixture.aircraft.count ..< len(fixture.aircraft.slots) {
        slot := &fixture.aircraft.slots[slot_index]
        _, valid := fixture_lifecycle_kind_index(slot.kind)
        if !valid {
            return fixture_lifecycle_error(.Invalid_Slot_Kind, slot_index)
        }
        if slot.vehicle != nil {
            kind: Fixture_Lifecycle_Error_Kind = detached ? .Invalid_Detached_Slot_Pointer : .Invalid_Live_Slot_Pointer
            return fixture_lifecycle_error(kind, slot_index)
        }
    }

    active_index, active_valid := fixture_lifecycle_kind_index(fixture.aircraft.active)
    if !active_valid || kind_slots[active_index] < 0 {
        return fixture_lifecycle_error(.Invalid_Active)
    }

    for slot_index in 0 ..< fixture.aircraft.count {
        slot := &fixture.aircraft.slots[slot_index]
        if detached {
            if slot.vehicle != nil {
                return fixture_lifecycle_error(.Invalid_Detached_Slot_Pointer, slot_index)
            }
        } else if slot.vehicle != fixture_lifecycle_vehicle_for_kind(fixture, slot.kind) {
            return fixture_lifecycle_error(.Invalid_Live_Slot_Pointer, slot_index)
        }
    }
    return {}
}

fixture_lifecycle_derive :: proc(
    fixture: ^Fixture,
) -> (
    occupant: vehicles.Fixture_Occupant,
    error: Fixture_Lifecycle_Error,
) {
    if fixture == nil {
        return {}, fixture_lifecycle_error(.Invalid_Argument)
    }
    kind_slots: [4]int
    if fleet_error := fixture_lifecycle_fleet_preflight(fixture, false, &kind_slots); fleet_error.kind != .None {
        return {}, fleet_error
    }

    derived, ok := vehicles.fixture_occupant_derive(
        &fixture.pilot,
        &fixture.car,
        &fixture.postale.vehicle,
        &fixture.libellula.vehicle,
        &fixture.rondine.vehicle,
        fixture.aircraft.active,
    )
    if !ok {
        return {}, fixture_lifecycle_error(.Invalid_Live_Occupancy)
    }

    occupied_vehicle: ^vehicles.Vehicle
    occupied_slot := -1
    switch derived {
    case .On_Foot:
    case .Car:
        occupied_vehicle = &fixture.car
    case .Postale:
        occupied_vehicle = &fixture.postale.vehicle
        occupied_slot = kind_slots[0]
    case .Libellula:
        occupied_vehicle = &fixture.libellula.vehicle
        occupied_slot = kind_slots[1]
    case .Libellula_Mk2:
        occupied_vehicle = &fixture.libellula.vehicle
        occupied_slot = kind_slots[2]
    case .Rondine:
        occupied_vehicle = &fixture.rondine.vehicle
        occupied_slot = kind_slots[3]
    }
    if occupied_vehicle != nil && occupied_vehicle.locked {
        return {}, fixture_lifecycle_error(.Occupied_Vehicle_Locked, occupied_slot)
    }
    return derived, {}
}

fixture_lifecycle_detach :: proc(source, detached: ^Fixture) -> Fixture_Lifecycle_Error {
    if source == nil || detached == nil {
        return fixture_lifecycle_error(.Invalid_Argument)
    }
    if source == detached {
        return fixture_lifecycle_error(.Aliased_Arguments)
    }

    occupant, derive_error := fixture_lifecycle_derive(source)
    if derive_error.kind != .None do return derive_error

    detached^ = source^
    detached.occupant = occupant
    detached.pilot.vehicle = nil
    detached.car.driver = nil
    detached.postale.vehicle.driver = nil
    detached.libellula.vehicle.driver = nil
    detached.rondine.vehicle.driver = nil
    for &slot in detached.aircraft.slots do slot.vehicle = nil
    return {}
}

fixture_lifecycle_prepare :: proc(fixture: ^Fixture, plan: ^Fixture_Lifecycle_Bind_Plan) -> Fixture_Lifecycle_Error {
    if fixture == nil || plan == nil {
        return fixture_lifecycle_error(.Invalid_Argument)
    }

    kind_slots: [4]int
    if fleet_error := fixture_lifecycle_fleet_preflight(fixture, true, &kind_slots); fleet_error.kind != .None {
        return fleet_error
    }
    if fixture.pilot.vehicle != nil {
        return fixture_lifecycle_error(.Invalid_Detached_Pilot_Pointer)
    }
    if fixture.car.driver != nil {
        return fixture_lifecycle_error(.Invalid_Detached_Driver_Pointer)
    }
    drivers := [?]^vehicles.Character {
        fixture.postale.vehicle.driver,
        fixture.libellula.vehicle.driver,
        fixture.rondine.vehicle.driver,
    }
    driver_slots := [?]int{kind_slots[0], kind_slots[1], kind_slots[3]}
    for driver, index in drivers {
        if driver != nil {
            return fixture_lifecycle_error(.Invalid_Detached_Driver_Pointer, driver_slots[index])
        }
    }

    switch fixture.occupant {
    case .On_Foot, .Car, .Postale, .Libellula, .Libellula_Mk2, .Rondine:
    case:
        return fixture_lifecycle_error(.Invalid_Occupant)
    }
    switch fixture.pilot.mode {
    case .On_Foot, .Driving:
    case:
        return fixture_lifecycle_error(.Invalid_Occupancy_Mode)
    }

    occupied_vehicle: ^vehicles.Vehicle
    occupied_slot := -1
    expected_active := fixture.aircraft.active
    requires_active := false
    switch fixture.occupant {
    case .On_Foot:
    case .Car:
        occupied_vehicle = &fixture.car
    case .Postale:
        occupied_vehicle = &fixture.postale.vehicle
        occupied_slot = kind_slots[0]
        expected_active = .Postale
        requires_active = true
    case .Libellula:
        occupied_vehicle = &fixture.libellula.vehicle
        occupied_slot = kind_slots[1]
        expected_active = .Libellula
        requires_active = true
    case .Libellula_Mk2:
        occupied_vehicle = &fixture.libellula.vehicle
        occupied_slot = kind_slots[2]
        expected_active = .Libellula_Mk2
        requires_active = true
    case .Rondine:
        occupied_vehicle = &fixture.rondine.vehicle
        occupied_slot = kind_slots[3]
        expected_active = .Rondine
        requires_active = true
    }
    if requires_active && fixture.aircraft.active != expected_active {
        return fixture_lifecycle_error(.Occupant_Active_Mismatch, occupied_slot)
    }
    if occupied_vehicle != nil && occupied_vehicle.locked {
        return fixture_lifecycle_error(.Occupied_Vehicle_Locked, occupied_slot)
    }

    plan^ = {
        occupant   = fixture.occupant,
        kind_slots = kind_slots,
    }
    return {}
}

fixture_lifecycle_apply :: proc(fixture: ^Fixture, plan: ^Fixture_Lifecycle_Bind_Plan) {
    fixture.occupant = plan.occupant
    for &slot in fixture.aircraft.slots do slot.vehicle = nil
    kinds := [?]vehicles.Aircraft_Kind{.Postale, .Libellula, .Libellula_Mk2, .Rondine}
    for kind, kind_index in kinds {
        slot_index := plan.kind_slots[kind_index]
        fixture.aircraft.slots[slot_index].vehicle = fixture_lifecycle_vehicle_for_kind(fixture, kind)
    }
    fixture.pilot.vehicle = nil
    fixture.car.driver = nil
    fixture.postale.vehicle.driver = nil
    fixture.libellula.vehicle.driver = nil
    fixture.rondine.vehicle.driver = nil
    fixture.pilot.mode = plan.occupant == .On_Foot ? .On_Foot : .Driving
    occupied_vehicle: ^vehicles.Vehicle
    switch plan.occupant {
    case .On_Foot:
    case .Car:
        occupied_vehicle = &fixture.car
    case .Postale:
        occupied_vehicle = &fixture.postale.vehicle
    case .Libellula, .Libellula_Mk2:
        occupied_vehicle = &fixture.libellula.vehicle
    case .Rondine:
        occupied_vehicle = &fixture.rondine.vehicle
    }
    if occupied_vehicle != nil {
        fixture.pilot.vehicle = occupied_vehicle
        occupied_vehicle.driver = &fixture.pilot
    }
}

fixture_lifecycle_bind :: proc(fixture: ^Fixture) -> Fixture_Lifecycle_Error {
    plan: Fixture_Lifecycle_Bind_Plan
    prepare_error := fixture_lifecycle_prepare(fixture, &plan)
    if prepare_error.kind != .None do return prepare_error
    fixture_lifecycle_apply(fixture, &plan)
    return {}
}
