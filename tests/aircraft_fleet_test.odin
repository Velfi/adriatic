package tests

import vehicles "../packages/vehicles"
import "core:testing"

@(test)
aircraft_fleet_switches_only_to_available_slots :: proc(t: ^testing.T) {
    postale := vehicles.default_vehicle({})
    libellula := vehicles.default_vehicle({10, 0, 0})
    fleet: vehicles.Aircraft_Fleet
    testing.expect(t, vehicles.aircraft_fleet_add(&fleet, .Postale, "Postale", &postale, true))
    testing.expect(t, vehicles.aircraft_fleet_add(&fleet, .Libellula, "Libellula", &libellula, false))
    testing.expect(t, !vehicles.aircraft_fleet_switch(&fleet, .Libellula))
    testing.expect(t, fleet.active == .Postale)
    libellula_slot := vehicles.aircraft_fleet_slot(&fleet, .Libellula)
    testing.expect(t, vehicles.aircraft_fleet_unlock(&fleet, .Libellula))
    testing.expect(t, libellula_slot.available)
    testing.expect(t, vehicles.aircraft_fleet_switch(&fleet, .Libellula))
    testing.expect(t, vehicles.aircraft_fleet_active(&fleet).vehicle == &libellula)
}
