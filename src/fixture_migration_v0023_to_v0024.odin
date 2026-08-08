package main

import fixture_v0023 "../packages/fixture_history/v0023"
import "core:mem"

FIXTURE_MIGRATION_V0023_TO_V0024_FROM_VERSION :: 23
FIXTURE_MIGRATION_V0023_TO_V0024_TO_VERSION :: 24
FIXTURE_MIGRATION_V0023_TO_V0024_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution{change_id = "enum-remove:adriatic:src.Lab_Kind.Dunes", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-remove:adriatic:src.Lab_Fixture_State.dunes", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Dunes_Lab_Config", kind = .Scripted},
}

fixture_migrate_v0023_to_v0024 :: proc(
    #by_ptr historical: fixture_v0023.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = historical.lab.dunes
    _ = allocator
    if tentative == nil do return {kind = .Invalid_Argument}
    if int(historical.lab.kind) < int(fixture_v0023.History_Type_0111.None) ||
       int(historical.lab.kind) > int(fixture_v0023.History_Type_0111.Dunes) {
        return {kind = .Invalid_Source, change_id = "enum-remove:adriatic:src.Lab_Kind.Dunes"}
    }
    // Dunes was the only authored lab. Both historical values now resolve to
    // the sole supported state, and its retired configuration is discarded.
    tentative.lab = {}
    return {}
}
