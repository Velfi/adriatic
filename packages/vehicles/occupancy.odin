package vehicles

import "core:math"
import "core:math/linalg"
import third_person "zelda_engine:third_person"

// The occupancy layer deliberately has no physics dependency. The game owns
// collision queries, then calls try_exit with whether the door-side spot is
// safe. This keeps the GTA-style interaction usable by cars, boats, and VTOLs.
Occupancy_Mode :: enum {
    On_Foot,
    Driving,
}

Fixture_Occupant :: enum u8 {
    On_Foot       = 0,
    Car           = 1,
    Postale       = 2,
    Libellula     = 3,
    Libellula_Mk2 = 4,
    Rondine       = 5,
}

Character :: struct {
    position:           third_person.Vec3,
    facing_yaw_radians: f32,
    mode:               Occupancy_Mode,
    vehicle:            ^Vehicle `fixture:"-"`,
}

Vehicle :: struct {
    position:           third_person.Vec3,
    yaw_radians:        f32,
    interaction_radius: f32,
    exit_distance:      f32,
    locked:             bool,
    driver:             ^Character `fixture:"-"`,
}

default_vehicle :: proc(position: third_person.Vec3) -> Vehicle {
    return {position = position, interaction_radius = 2.5, exit_distance = 1.8}
}

fixture_occupant_derive :: proc(
    character: ^Character,
    car, postale, libellula, rondine: ^Vehicle,
    active_aircraft: Aircraft_Kind,
) -> (
    Fixture_Occupant,
    bool,
) {
    if character == nil || car == nil || postale == nil || libellula == nil || rondine == nil do return {}, false
    if car == postale ||
       car == libellula ||
       car == rondine ||
       postale == libellula ||
       postale == rondine ||
       libellula == rondine {
        return {}, false
    }

    switch active_aircraft {
    case .Postale, .Libellula, .Libellula_Mk2, .Rondine:
    case:
        return {}, false
    }

    if character.mode == .On_Foot {
        if character.vehicle == nil &&
           car.driver == nil &&
           postale.driver == nil &&
           libellula.driver == nil &&
           rondine.driver == nil {
            return .On_Foot, true
        }
        return {}, false
    }
    if character.mode != .Driving do return {}, false

    if character.vehicle == car &&
       car.driver == character &&
       postale.driver == nil &&
       libellula.driver == nil &&
       rondine.driver == nil {
        return .Car, true
    }
    if character.vehicle == postale &&
       postale.driver == character &&
       car.driver == nil &&
       libellula.driver == nil &&
       rondine.driver == nil &&
       active_aircraft == .Postale {
        return .Postale, true
    }
    if character.vehicle == libellula &&
       libellula.driver == character &&
       car.driver == nil &&
       postale.driver == nil &&
       rondine.driver == nil {
        switch active_aircraft {
        case .Postale:
            return {}, false
        case .Libellula:
            return .Libellula, true
        case .Libellula_Mk2:
            return .Libellula_Mk2, true
        case .Rondine:
            return {}, false
        }
    }
    if character.vehicle == rondine &&
       rondine.driver == character &&
       car.driver == nil &&
       postale.driver == nil &&
       libellula.driver == nil &&
       active_aircraft == .Rondine {
        return .Rondine, true
    }
    return {}, false
}

// try_enter_nearest seats an on-foot character in the closest unlocked,
// unoccupied vehicle in range. A caller can use the returned pointer to switch
// its input routing from character movement to vehicle controls.
try_enter_nearest :: proc(character: ^Character, vehicles: []^Vehicle) -> (vehicle: ^Vehicle, entered: bool) {
    if character == nil || character.mode != .On_Foot do return
    closest_distance_squared := f32(0)
    for candidate in vehicles {
        if candidate == nil || candidate.locked || candidate.driver != nil do continue
        delta := character.position - candidate.position
        distance_squared := linalg.dot(delta, delta)
        radius := candidate.interaction_radius
        if radius <= 0 do radius = 2.5
        if distance_squared > radius * radius do continue
        if !entered || distance_squared < closest_distance_squared {
            vehicle = candidate
            closest_distance_squared = distance_squared
            entered = true
        }
    }
    if !entered do return
    vehicle.driver = character
    character.vehicle = vehicle
    character.mode = .Driving
    sync_driver(character)
    return
}

// sync_driver keeps the hidden on-foot character seated at the vehicle. Call
// after the vehicle physics step, before deriving the third-person camera.
sync_driver :: proc(character: ^Character) {
    if character == nil || character.mode != .Driving || character.vehicle == nil do return
    character.position = character.vehicle.position
    character.facing_yaw_radians = character.vehicle.yaw_radians
}

// try_exit places the driver beside the left door. Pass false when the product
// collision query finds an obstacle there; in that case the driver stays seated.
try_exit :: proc(character: ^Character, exit_position_clear: bool) -> (exited: bool) {
    if character == nil || character.mode != .Driving || character.vehicle == nil || !exit_position_clear do return
    vehicle := character.vehicle
    distance := vehicle.exit_distance
    if distance <= 0 do distance = 1.8
    left := third_person.Vec3{-math.cos(vehicle.yaw_radians), 0, math.sin(vehicle.yaw_radians)}
    character.position = vehicle.position + left * distance
    character.facing_yaw_radians = vehicle.yaw_radians
    character.vehicle = nil
    character.mode = .On_Foot
    vehicle.driver = nil
    return true
}
