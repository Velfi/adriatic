package main

import fixture_v0009 "../packages/fixture_history/v0009"
import "core:mem"

FIXTURE_MIGRATION_V0009_TO_V0010_FROM_VERSION :: 9
FIXTURE_MIGRATION_V0009_TO_V0010_TO_VERSION :: 10
FIXTURE_MIGRATION_V0009_TO_V0010_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.player_mail", kind = .Scripted},
}

fixture_migrate_v0009_to_v0010 :: proc(
    #by_ptr historical: fixture_v0009.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = historical
    _ = allocator
    // Mail did not exist in v9. Start migrated players with an empty post box;
    // the next post-office visit evaluates current story progress and collects
    // every letter that is then available.
    tentative.player_mail = {}
    return {}
}
