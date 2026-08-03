package main

import fixture_v0019 "../packages/fixture_history/v0019"
import vehicles "../packages/vehicles"
import "core:testing"

@(test)
fixture_migration_v0019_to_v0020_defaults_car_model_runtime_and_tuning :: proc(t: ^testing.T) {
    tentative := new(Fixture)
    testing.expect(t, tentative != nil)
    if tentative == nil do return
    defer free(tentative)
    tentative.car_handling_model = .Racer_Arcade
    tentative.car_drive.racer.drift_amount = .8
    tentative.tweak.car.racer.drift_rear_grip = .99

    migration_error := fixture_migrate_v0019_to_v0020(fixture_v0019.Fixture{}, tentative, {})
    testing.expect(t, migration_error.kind == .None)
    testing.expect(t, tentative.car_handling_model == .Current_Physics)
    testing.expect_value(t, tentative.car_drive.racer.drift_amount, f32(0))
    testing.expect_value(
        t,
        tentative.tweak.car.racer.drift_rear_grip,
        vehicles.CAR_DRIVE_SEDAN_TUNE.racer.drift_rear_grip,
    )

    registry := fixture_migration_production_registry()
    testing.expect(t, len(registry.steps) == FIXTURE_SCHEMA_VERSION - 1)
    testing.expect(t, registry.steps[18].from_version == 19)
    testing.expect(t, registry.steps[18].to_version == 20)
    testing.expect(t, registry.steps[18].wrapper == fixture_migration_step_v0019_to_v0020)
    for resolution in FIXTURE_MIGRATION_V0019_TO_V0020_RESOLUTIONS {
        testing.expect(t, resolution.kind == .Scripted)
    }
}
