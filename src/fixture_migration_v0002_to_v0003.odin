package main

import fixture_v0002 "../packages/fixture_history/v0002"
import "core:mem"

FIXTURE_MIGRATION_V0002_TO_V0003_FROM_VERSION :: 2
FIXTURE_MIGRATION_V0002_TO_V0003_TO_VERSION :: 3
FIXTURE_MIGRATION_V0002_TO_V0003_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.occupant", kind = .Scripted},
}

fixture_migration_v0002_to_v0003_resolve_occupant :: proc(tentative: ^Fixture) -> Fixture_Migration_Error {
    if tentative == nil do return {kind = .Invalid_Argument}
    tentative.occupant = .On_Foot
    return {}
}

fixture_migrate_v0002_to_v0003 :: proc(
    #by_ptr historical: fixture_v0002.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = historical
    _ = allocator
    return fixture_migration_v0002_to_v0003_resolve_occupant(tentative)
}
