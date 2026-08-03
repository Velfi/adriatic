package main

import atmosphere "../packages/atmosphere"
import fixture_v0011 "../packages/fixture_history/v0011"
import "core:mem"

FIXTURE_MIGRATION_V0011_TO_V0012_FROM_VERSION :: 11
FIXTURE_MIGRATION_V0011_TO_V0012_TO_VERSION :: 12
FIXTURE_MIGRATION_V0011_TO_V0012_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/atmosphere.Atmosphere.climate",
        kind = .Scripted,
    },
}

fixture_migrate_v0011_to_v0012 :: proc(
    #by_ptr historical: fixture_v0011.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = historical
    _ = allocator
    // Climate-scale state is new in v12. Preserve all v11 weather/front state
    // and derive a deterministic regional regime from each atmosphere seed.
    tentative.atmosphere.climate = {}
    atmosphere.initialize_climate(&tentative.atmosphere)
    tentative.tweak.atmosphere.climate = {}
    atmosphere.initialize_climate(&tentative.tweak.atmosphere)
    return {}
}
