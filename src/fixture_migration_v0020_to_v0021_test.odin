package main

import fixture_v0020 "../packages/fixture_history/v0020"
import postale_game "../packages/postale"
import "core:testing"

@(test)
fixture_migration_v0020_to_v0021_defaults_postale_ace_tuning :: proc(t: ^testing.T) {
    historical := new(fixture_v0020.Fixture)
    tentative := new(Fixture)
    defer free(historical)
    defer free(tentative)
    tentative.tweak.postale_ace_tuning = {}

    migration_error := fixture_migrate_v0020_to_v0021(historical^, tentative, context.allocator)

    testing.expect_value(t, migration_error.kind, Fixture_Migration_Error_Kind.None)
    testing.expect_value(t, tentative.tweak.postale_ace_tuning, postale_game.ace_tuning_preset())
    registry := fixture_migration_production_registry()
    testing.expect(t, len(registry.steps) == FIXTURE_SCHEMA_VERSION - 1)
    testing.expect(t, registry.steps[len(registry.steps) - 1].from_version == 20)
    testing.expect(t, registry.steps[len(registry.steps) - 1].to_version == 21)
    testing.expect(t, registry.steps[len(registry.steps) - 1].wrapper == fixture_migration_step_v0020_to_v0021)
    for resolution in FIXTURE_MIGRATION_V0020_TO_V0021_RESOLUTIONS {
        testing.expect(t, resolution.kind == .Scripted)
    }
}
