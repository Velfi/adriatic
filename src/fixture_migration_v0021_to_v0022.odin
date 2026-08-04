package main

import fixture_v0021 "../packages/fixture_history/v0021"
import "core:mem"

FIXTURE_MIGRATION_V0021_TO_V0022_FROM_VERSION :: 21
FIXTURE_MIGRATION_V0021_TO_V0022_TO_VERSION :: 22
FIXTURE_MIGRATION_V0021_TO_V0022_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution {
        change_id = "enum-add:adriatic:packages/terrain.Formation_Kind.Field",
        kind = .Scripted,
    },
}

fixture_migrate_v0021_to_v0022 :: proc(
    #by_ptr historical: fixture_v0021.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = historical
    _ = allocator
    if tentative == nil do return {kind = .Invalid_Argument}

    // Field is appended to Formation_Kind, so every v21 numeric value keeps
    // its meaning. The tentative portable decode already carries that value.
    return {}
}
