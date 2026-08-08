package tests

import vehicles "../packages/vehicles"
import "core:testing"
import third_person "zelda_engine:third_person"

@(test)
vehicle_entry_uses_the_closest_available_vehicle :: proc(t: ^testing.T) {
    character := vehicles.Character {
        position = {},
    }
    far := vehicles.default_vehicle({2, 0, 0})
    near := vehicles.default_vehicle({1, 0, 0})
    vehicle, entered := vehicles.try_enter_nearest(&character, []^vehicles.Vehicle{&far, &near})
    testing.expect(t, entered && vehicle == &near)
    testing.expect(t, character.mode == .Driving && near.driver == &character)
}

@(test)
vehicle_exit_respects_a_blocked_door_and_restores_on_foot_control :: proc(t: ^testing.T) {
    car := vehicles.default_vehicle({4, 2, 3})
    character := vehicles.Character {
        position = {4, 2, 2},
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
    car.position = third_person.Vec3{9, 1, -4}
    car.yaw_radians = .5
    vehicles.sync_driver(&character)
    testing.expect(t, character.position.x == 9 && character.position.y == 1 && character.position.z == -4)
    testing.expect(t, character.facing_yaw_radians == .5)
}

fixture_occupancy_test_character_equal :: proc(a, b: vehicles.Character) -> bool {
    return(
        a.position.x == b.position.x &&
        a.position.y == b.position.y &&
        a.position.z == b.position.z &&
        a.facing_yaw_radians == b.facing_yaw_radians &&
        a.mode == b.mode &&
        a.vehicle == b.vehicle \
    )
}

fixture_occupancy_test_vehicle_equal :: proc(a, b: vehicles.Vehicle) -> bool {
    return(
        a.position.x == b.position.x &&
        a.position.y == b.position.y &&
        a.position.z == b.position.z &&
        a.yaw_radians == b.yaw_radians &&
        a.interaction_radius == b.interaction_radius &&
        a.exit_distance == b.exit_distance &&
        a.locked == b.locked &&
        a.driver == b.driver \
    )
}

fixture_occupancy_test_expect :: proc(
    t: ^testing.T,
    character: ^vehicles.Character,
    car, postale, libellula, rondine: ^vehicles.Vehicle,
    active_aircraft: vehicles.Aircraft_Kind,
    expected: vehicles.Fixture_Occupant,
    expected_ok: bool,
) {
    before_character: vehicles.Character
    before_car: vehicles.Vehicle
    before_postale: vehicles.Vehicle
    before_libellula: vehicles.Vehicle
    before_rondine: vehicles.Vehicle
    if character != nil do before_character = character^
    if car != nil do before_car = car^
    if postale != nil do before_postale = postale^
    if libellula != nil do before_libellula = libellula^
    if rondine != nil do before_rondine = rondine^

    occupant, ok := vehicles.fixture_occupant_derive(character, car, postale, libellula, rondine, active_aircraft)
    testing.expect(t, ok == expected_ok)
    if expected_ok do testing.expect(t, occupant == expected)
    if character != nil do testing.expect(t, fixture_occupancy_test_character_equal(character^, before_character))
    if car != nil do testing.expect(t, fixture_occupancy_test_vehicle_equal(car^, before_car))
    if postale != nil do testing.expect(t, fixture_occupancy_test_vehicle_equal(postale^, before_postale))
    if libellula != nil do testing.expect(t, fixture_occupancy_test_vehicle_equal(libellula^, before_libellula))
    if rondine != nil do testing.expect(t, fixture_occupancy_test_vehicle_equal(rondine^, before_rondine))
}

@(test)
fixture_occupant_derivation_covers_all_kinds_and_rejects_bad_links :: proc(t: ^testing.T) {
    testing.expect(t, u8(vehicles.Fixture_Occupant.On_Foot) == 0)
    testing.expect(t, u8(vehicles.Fixture_Occupant.Car) == 1)
    testing.expect(t, u8(vehicles.Fixture_Occupant.Postale) == 2)
    testing.expect(t, u8(vehicles.Fixture_Occupant.Libellula) == 3)
    testing.expect(t, u8(vehicles.Fixture_Occupant.Libellula_Mk2) == 4)
    testing.expect(t, u8(vehicles.Fixture_Occupant.Rondine) == 5)

    active_kinds := [?]vehicles.Aircraft_Kind{.Postale, .Libellula, .Libellula_Mk2, .Rondine}
    character := vehicles.Character{}
    car := vehicles.default_vehicle({1, 0, 0})
    postale := vehicles.default_vehicle({2, 0, 0})
    libellula := vehicles.default_vehicle({3, 0, 0})
    rondine := vehicles.default_vehicle({4, 0, 0})

    for active in active_kinds {
        fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, active, .On_Foot, true)
    }

    character.mode = .Driving
    character.vehicle = &car
    car.driver = &character
    for active in active_kinds {
        fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, active, .Car, true)
    }

    character = vehicles.Character {
        mode    = .Driving,
        vehicle = &postale,
    }
    car.driver = nil
    postale.driver = &character
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Postale, .Postale, true)

    character = vehicles.Character {
        mode    = .Driving,
        vehicle = &libellula,
    }
    postale.driver = nil
    libellula.driver = &character
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Libellula, .Libellula, true)
    testing.expect(t, character.vehicle == &libellula)
    fixture_occupancy_test_expect(
        t,
        &character,
        &car,
        &postale,
        &libellula,
        &rondine,
        .Libellula_Mk2,
        .Libellula_Mk2,
        true,
    )
    testing.expect(t, character.vehicle == &libellula)

    character = vehicles.Character {
        mode    = .Driving,
        vehicle = &rondine,
    }
    libellula.driver = nil
    rondine.driver = &character
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Rondine, .Rondine, true)
    rondine.driver = nil
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Rondine, .On_Foot, false)
    rondine.driver = &character
    car.driver = &character
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Rondine, .On_Foot, false)
    car.driver = nil
    wrong_rondine_kinds := [?]vehicles.Aircraft_Kind{.Postale, .Libellula, .Libellula_Mk2}
    for active in wrong_rondine_kinds {
        fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, active, .On_Foot, false)
    }
    foreign_rondine_driver := vehicles.Character{}
    rondine.driver = &foreign_rondine_driver
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Rondine, .On_Foot, false)
    rondine.driver = &character
    car.driver = &foreign_rondine_driver
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Rondine, .On_Foot, false)
    car.driver = nil
    postale.driver = &foreign_rondine_driver
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Rondine, .On_Foot, false)
    postale.driver = nil
    libellula.driver = &foreign_rondine_driver
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Rondine, .On_Foot, false)
    libellula.driver = nil

    character = vehicles.Character{}
    rondine.driver = nil
    for active in active_kinds {
        fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, active, .On_Foot, true)
    }

    character.mode = .Driving
    character.vehicle = &car
    car.driver = &character
    postale.driver = nil
    libellula.driver = nil
    foreign_character := vehicles.Character{}
    unknown := vehicles.default_vehicle({9, 0, 0})
    forged_aircraft := cast(vehicles.Aircraft_Kind)u8(255)
    forged_mode := cast(vehicles.Occupancy_Mode)u8(255)

    fixture_occupancy_test_expect(t, nil, &car, &postale, &libellula, &rondine, .Postale, .On_Foot, false)
    fixture_occupancy_test_expect(t, &character, nil, &postale, &libellula, &rondine, .Postale, .On_Foot, false)
    fixture_occupancy_test_expect(t, &character, &car, nil, &libellula, &rondine, .Postale, .On_Foot, false)
    fixture_occupancy_test_expect(t, &character, &car, &postale, nil, &rondine, .Postale, .On_Foot, false)
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, nil, .Postale, .On_Foot, false)
    fixture_occupancy_test_expect(t, &character, &car, &car, &libellula, &rondine, .Postale, .On_Foot, false)
    fixture_occupancy_test_expect(t, &character, &car, &postale, &postale, &rondine, .Postale, .On_Foot, false)
    fixture_occupancy_test_expect(t, &character, &car, &postale, &car, &rondine, .Postale, .On_Foot, false)
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &car, .Postale, .On_Foot, false)
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &postale, .Postale, .On_Foot, false)
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &libellula, .Postale, .On_Foot, false)
    fixture_occupancy_test_expect(
        t,
        &character,
        &car,
        &postale,
        &libellula,
        &rondine,
        forged_aircraft,
        .On_Foot,
        false,
    )

    rondine.driver = &foreign_character
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Rondine, .On_Foot, false)
    rondine.driver = nil

    character = vehicles.Character {
        mode    = .Driving,
        vehicle = &unknown,
    }
    car.driver = nil
    unknown.driver = &character
    unknown_before := unknown
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Postale, .On_Foot, false)
    testing.expect(t, fixture_occupancy_test_vehicle_equal(unknown, unknown_before))

    character = vehicles.Character {
        mode    = .Driving,
        vehicle = &car,
    }
    car.driver = &foreign_character
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Postale, .On_Foot, false)

    character = vehicles.Character {
        mode = .On_Foot,
    }
    car.driver = &character
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Postale, .On_Foot, false)
    character.vehicle = &car
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Postale, .On_Foot, false)

    character = vehicles.Character {
        mode = .Driving,
    }
    car.driver = nil
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Postale, .On_Foot, false)

    character = vehicles.Character {
        mode    = .Driving,
        vehicle = &car,
    }
    car.driver = nil
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Postale, .On_Foot, false)

    character = vehicles.Character {
        mode    = .Driving,
        vehicle = &car,
    }
    car.driver = &character
    postale.driver = &foreign_character
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Postale, .On_Foot, false)
    postale.driver = &character
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Postale, .On_Foot, false)

    character = vehicles.Character {
        mode    = .Driving,
        vehicle = &postale,
    }
    car.driver = nil
    postale.driver = &character
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Libellula, .On_Foot, false)

    character = vehicles.Character {
        mode    = .Driving,
        vehicle = &libellula,
    }
    postale.driver = nil
    libellula.driver = &character
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Postale, .On_Foot, false)

    character.mode = forged_mode
    character.vehicle = nil
    libellula.driver = nil
    fixture_occupancy_test_expect(t, &character, &car, &postale, &libellula, &rondine, .Postale, .On_Foot, false)
}
