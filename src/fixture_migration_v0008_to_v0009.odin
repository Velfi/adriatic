package main

import fixture_v0008 "../packages/fixture_history/v0008"
import terrain "../packages/terrain"
import "core:mem"

FIXTURE_MIGRATION_V0008_TO_V0009_FROM_VERSION :: 8
FIXTURE_MIGRATION_V0008_TO_V0009_TO_VERSION :: 9
FIXTURE_MIGRATION_V0008_TO_V0009_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.default_harbors", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Fixture.default_map_regeneration_seeds",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.default_marina_count", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Fixture.default_marina_islands",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.default_marinas", kind = .Scripted},
}

fixture_migrate_v0008_to_v0009 :: proc(
    #by_ptr historical: fixture_v0008.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = historical
    _ = allocator
    // Version 8 baked the generated terrain, roads, and structures into the
    // project but did not retain their seed provenance or runtime waterfront
    // plans. Default seeds faithfully describe all v8 production fixtures.
    tentative.default_map_regeneration_seeds = terrain.DEFAULT_ISLAND_SEEDS
    tentative.default_marinas = {}
    tentative.default_harbors = {}
    tentative.default_marina_islands = {}
    tentative.default_marina_count = 0
    return {}
}
