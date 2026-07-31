package main

import fixture_v0006 "../packages/fixture_history/v0006"
import "core:mem"

FIXTURE_MIGRATION_V0006_TO_V0007_FROM_VERSION :: 6
FIXTURE_MIGRATION_V0006_TO_V0007_TO_VERSION :: 7
FIXTURE_MIGRATION_V0006_TO_V0007_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/story.State.friendship_points",
        kind = .Scripted,
    },
}

fixture_migrate_v0006_to_v0007 :: proc(
    #by_ptr historical: fixture_v0006.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = historical
    _ = allocator
    tentative.story_state.friendship_points = 0
    return {}
}
