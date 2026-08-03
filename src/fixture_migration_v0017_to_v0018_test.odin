package main

import fixture_v0017 "../packages/fixture_history/v0017"
import "core:testing"

@(test)
fixture_migration_v0017_to_v0018_defaults_building_base_elevation :: proc(t: ^testing.T) {
    historical := new(fixture_v0017.Fixture)
    tentative := new(Fixture)
    defer free(historical)
    defer free(tentative)
    tentative.settlement_plan.metrics.building_base_elevation = {
        count = 4,
        min   = 3,
        max   = 9,
        mean  = 6,
    }

    migration_error := fixture_migrate_v0017_to_v0018(historical^, tentative, context.allocator)

    testing.expect_value(t, migration_error.kind, Fixture_Migration_Error_Kind.None)
    testing.expect_value(t, tentative.settlement_plan.metrics.building_base_elevation, Settlement_Scalar_Stats{})
}
