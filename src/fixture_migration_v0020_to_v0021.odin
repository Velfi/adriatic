package main

import fixture_v0020 "../packages/fixture_history/v0020"
import postale_game "../packages/postale"
import "core:mem"

FIXTURE_MIGRATION_V0020_TO_V0021_FROM_VERSION :: 20
FIXTURE_MIGRATION_V0020_TO_V0021_TO_VERSION :: 21
FIXTURE_MIGRATION_V0020_TO_V0021_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Tweak_State.postale_ace_tuning",
        kind = .Scripted,
    },
}

fixture_migrate_v0020_to_v0021 :: proc(
    #by_ptr historical: fixture_v0020.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = historical
    _ = allocator
    if tentative == nil do return {kind = .Invalid_Argument}

    tentative.tweak.postale_ace_tuning = postale_game.ace_tuning_preset()
    return {}
}
