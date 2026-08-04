package main

import fixture_v0021 "../packages/fixture_history/v0021"
import terrain "../packages/terrain"
import "core:testing"

@(test)
fixture_migration_v0021_to_v0022_preserves_existing_formation_kind :: proc(t: ^testing.T) {
    historical := new(fixture_v0021.Fixture)
    tentative := new(Fixture)
    defer free(historical)
    defer free(tentative)
    tentative.structure_kind = .Ruins

    migration_error := fixture_migrate_v0021_to_v0022(historical^, tentative, context.allocator)

    testing.expect_value(t, migration_error.kind, Fixture_Migration_Error_Kind.None)
    testing.expect_value(t, tentative.structure_kind, terrain.Formation_Kind.Ruins)
    testing.expect_value(t, int(terrain.Formation_Kind.Field), 9)
    registry := fixture_migration_production_registry()
    testing.expect(t, len(registry.steps) == FIXTURE_SCHEMA_VERSION - 1)
    testing.expect(t, registry.steps[len(registry.steps) - 2].from_version == 21)
    testing.expect(t, registry.steps[len(registry.steps) - 2].to_version == 22)
    testing.expect(t, registry.steps[len(registry.steps) - 2].wrapper == fixture_migration_step_v0021_to_v0022)
    for resolution in FIXTURE_MIGRATION_V0021_TO_V0022_RESOLUTIONS {
        testing.expect(t, resolution.kind == .Scripted)
    }
}
