package vehicles

// Aircraft_Fleet is the product-facing ownership and selection layer for
// aircraft. Physics and presentation can evolve independently: a slot owns
// the vehicle used for occupancy, while the game decides which flight model
// and mesh to drive for that slot.
Aircraft_Kind :: enum u8 {
    Postale,
    Libellula,
}

Aircraft_Slot :: struct {
    kind:      Aircraft_Kind,
    name:      string,
    vehicle:   ^Vehicle,
    available: bool,
}

Aircraft_Fleet :: struct {
    slots:  [8]Aircraft_Slot,
    count:  int,
    active: Aircraft_Kind,
}

aircraft_fleet_add :: proc(
    fleet: ^Aircraft_Fleet,
    kind: Aircraft_Kind,
    name: string,
    vehicle: ^Vehicle,
    available: bool,
) -> bool {
    if fleet == nil || vehicle == nil || fleet.count >= len(fleet.slots) do return false
    fleet.slots[fleet.count] = {
        kind      = kind,
        name      = name,
        vehicle   = vehicle,
        available = available,
    }
    fleet.count += 1
    return true
}

aircraft_fleet_slot :: proc(fleet: ^Aircraft_Fleet, kind: Aircraft_Kind) -> ^Aircraft_Slot {
    if fleet == nil do return nil
    for index in 0 ..< fleet.count {
        if fleet.slots[index].kind == kind do return &fleet.slots[index]
    }
    return nil
}

aircraft_fleet_active :: proc(fleet: ^Aircraft_Fleet) -> ^Aircraft_Slot {
    return aircraft_fleet_slot(fleet, fleet.active)
}

// Unlocking is explicit so product interactions such as talking to an
// attendant can grant access without weakening aircraft_fleet_switch's
// availability check.
aircraft_fleet_unlock :: proc(fleet: ^Aircraft_Fleet, kind: Aircraft_Kind) -> bool {
    slot := aircraft_fleet_slot(fleet, kind)
    if slot == nil do return false
    slot.available = true
    return true
}

// Selection is deliberately separate from entering. Marta can unlock a slot
// while the pilot is on foot; the caller then performs the actual occupancy
// transition and camera reset.
aircraft_fleet_switch :: proc(fleet: ^Aircraft_Fleet, kind: Aircraft_Kind) -> bool {
    slot := aircraft_fleet_slot(fleet, kind)
    if slot == nil || !slot.available do return false
    fleet.active = kind
    return true
}

aircraft_kind_name :: proc(kind: Aircraft_Kind) -> string {
    switch kind {
    case .Postale:
        return "POSTALE"
    case .Libellula:
        return "LIBELLULA"
    }
    return "AIRCRAFT"
}
