package main

import atmosphere "../packages/atmosphere"
import fixture_v0010 "../packages/fixture_history/v0010"
import "core:mem"

FIXTURE_MIGRATION_V0010_TO_V0011_FROM_VERSION :: 10
FIXTURE_MIGRATION_V0010_TO_V0011_TO_VERSION :: 11
FIXTURE_MIGRATION_V0010_TO_V0011_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/atmosphere.Atmosphere.schedule",
        kind = .Scripted,
    },
}

fixture_migrate_v0010_to_v0011 :: proc(
    #by_ptr historical: fixture_v0010.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = historical
    _ = allocator
    // Old saves had only a global preset clock. Preserve every visible weather
    // field and begin the first spatial front after a fresh seeded rare-weather
    // interval, avoiding an abrupt storm during load.
    tentative.atmosphere.schedule = {}
    atmosphere.initialize_schedule(&tentative.atmosphere)
    tentative.tweak.atmosphere.schedule = {}
    atmosphere.initialize_schedule(&tentative.tweak.atmosphere)
    return {}
}
