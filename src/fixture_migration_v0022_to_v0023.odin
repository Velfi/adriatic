package main

import fixture_v0022 "../packages/fixture_history/v0022"
import "core:mem"

FIXTURE_MIGRATION_V0022_TO_V0023_FROM_VERSION :: 22
FIXTURE_MIGRATION_V0022_TO_V0023_TO_VERSION :: 23
FIXTURE_MIGRATION_V0022_TO_V0023_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution{change_id = "enum-add:adriatic:src.Authoring_Tool.Mice", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.mouse_placement_count", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Fixture.mouse_placement_rotation",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.mouse_placements", kind = .Scripted},
}

fixture_migrate_v0022_to_v0023 :: proc(
    #by_ptr historical: fixture_v0022.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = historical
    _ = allocator
    if tentative == nil do return {kind = .Invalid_Argument}

    // Mice is appended, so every historical Authoring_Tool value retains its
    // meaning. Existing fixtures begin with no authored mice and neutral yaw.
    tentative.mouse_placements = {}
    tentative.mouse_placement_count = 0
    tentative.mouse_placement_rotation = 0
    return {}
}
