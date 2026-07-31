package main

import fixture_v0007 "../packages/fixture_history/v0007"
import story "../packages/story"
import "core:mem"

FIXTURE_MIGRATION_V0007_TO_V0008_FROM_VERSION :: 7
FIXTURE_MIGRATION_V0007_TO_V0008_TO_VERSION :: 8
FIXTURE_MIGRATION_V0007_TO_V0008_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution{change_id = "enum-add:adriatic:packages/story.Resident.Mirna", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-type:adriatic:packages/story.State.resident_action_seen",
        kind = .Scripted,
    },
}

fixture_migrate_v0007_to_v0008 :: proc(
    #by_ptr historical: fixture_v0007.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = allocator
    for index in 0 ..< len(historical.story_state.resident_action_seen) {
        historical_resident := fixture_v0007.History_Type_0108(index)
        tentative.story_state.resident_action_seen[story.Resident(index)] =
            historical.story_state.resident_action_seen[historical_resident]
    }
    tentative.story_state.resident_action_seen[.Mirna] = 0
    return {}
}
