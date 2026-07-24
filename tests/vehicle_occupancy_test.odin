package tests

import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:testing"

@(test)
vehicle_entry_uses_the_closest_available_vehicle :: proc(t: ^testing.T) {
    character := vehicles.Character {
        position = {},
    }
    far := vehicles.default_vehicle({x = 2})
    near := vehicles.default_vehicle({x = 1})
    vehicle, entered := vehicles.try_enter_nearest(&character, []^vehicles.Vehicle{&far, &near})
    testing.expect(t, entered && vehicle == &near)
    testing.expect(t, character.mode == .Driving && near.driver == &character)
}

@(test)
vehicle_exit_respects_a_blocked_door_and_restores_on_foot_control :: proc(t: ^testing.T) {
    car := vehicles.default_vehicle({x = 4, y = 2, z = 3})
    character := vehicles.Character {
        position = {x = 4, y = 2, z = 2},
    }
    _, entered := vehicles.try_enter_nearest(&character, []^vehicles.Vehicle{&car})
    testing.expect(t, entered)
    testing.expect(t, !vehicles.try_exit(&character, false) && character.mode == .Driving)
    testing.expect(t, vehicles.try_exit(&character, true))
    testing.expect(t, character.mode == .On_Foot && character.vehicle == nil && car.driver == nil)
    testing.expect(t, character.position.x < car.position.x)
}

@(test)
vehicle_driver_follows_vehicle_physics_position :: proc(t: ^testing.T) {
    car := vehicles.default_vehicle({})
    character := vehicles.Character{}
    _, entered := vehicles.try_enter_nearest(&character, []^vehicles.Vehicle{&car})
    testing.expect(t, entered)
    car.position = third_person.Vec3 {
        x = 9,
        y = 1,
        z = -4,
    }
    car.yaw_radians = .5
    vehicles.sync_driver(&character)
    testing.expect(t, character.position.x == 9 && character.position.y == 1 && character.position.z == -4)
    testing.expect(t, character.facing_yaw_radians == .5)
}
