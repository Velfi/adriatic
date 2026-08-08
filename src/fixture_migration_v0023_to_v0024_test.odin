package main

import fixture_v0023 "../packages/fixture_history/v0023"
import "core:testing"

@(test)
fixture_migration_v0023_to_v0024_discards_retired_dune_lab_state :: proc(t: ^testing.T) {
    historical: fixture_v0023.Fixture
    historical.lab.kind = .Dunes
    historical.lab.dunes = {
        seed       = 0x44554e45,
        wind_angle = .31,
        vegetation = .82,
    }
    target := new(Fixture)
    defer free(target)
    target.lab.kind = cast(Lab_Kind)1

    error := fixture_migrate_v0023_to_v0024(historical, target, context.allocator)
    testing.expect(t, error.kind == .None)
    testing.expect_value(t, target.lab.kind, Lab_Kind.None)
    for resolution in FIXTURE_MIGRATION_V0023_TO_V0024_RESOLUTIONS {
        testing.expect(t, resolution.kind == .Scripted)
    }
}

@(test)
fixture_migration_v0023_to_v0024_rejects_invalid_historical_lab_kind :: proc(t: ^testing.T) {
    historical: fixture_v0023.Fixture
    historical.lab.kind = cast(fixture_v0023.History_Type_0111)2
    target := new(Fixture)
    defer free(target)
    error := fixture_migrate_v0023_to_v0024(historical, target, context.allocator)
    testing.expect(t, error.kind == .Invalid_Source)
    testing.expect(t, error.change_id == "enum-remove:adriatic:src.Lab_Kind.Dunes")
}

@(test)
fixture_migration_registry_ends_with_v0023_to_v0024 :: proc(t: ^testing.T) {
    registry := fixture_migration_production_registry()
    testing.expect_value(t, len(registry.steps), FIXTURE_SCHEMA_VERSION - 1)
    last := registry.steps[len(registry.steps) - 1]
    testing.expect_value(t, last.from_version, 23)
    testing.expect_value(t, last.to_version, 24)
    testing.expect(t, last.wrapper == fixture_migration_step_v0023_to_v0024)
}
