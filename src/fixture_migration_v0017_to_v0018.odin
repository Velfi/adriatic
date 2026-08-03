package main

import fixture_v0017 "../packages/fixture_history/v0017"
import "core:mem"

FIXTURE_MIGRATION_V0017_TO_V0018_FROM_VERSION :: 17
FIXTURE_MIGRATION_V0017_TO_V0018_TO_VERSION :: 18
FIXTURE_MIGRATION_V0017_TO_V0018_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Metrics.building_base_elevation",
        kind = .Scripted,
    },
}

fixture_migrate_v0017_to_v0018 :: proc(
    #by_ptr historical: fixture_v0017.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = historical
    _ = allocator
    if tentative == nil do return {kind = .Invalid_Argument}
    // This metric is derived from generated building elevations. Older fixtures
    // have no source samples to reconstruct it, so preserve an empty stats value.
    tentative.settlement_plan.metrics.building_base_elevation = {}
    return {}
}
