package main

import fixture_v0012 "../packages/fixture_history/v0012"
import "core:mem"

FIXTURE_MIGRATION_V0012_TO_V0013_FROM_VERSION :: 12
FIXTURE_MIGRATION_V0012_TO_V0013_TO_VERSION :: 13
FIXTURE_MIGRATION_V0012_TO_V0013_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
	Fixture_Migration_Resolution {
		change_id = "enum-add:adriatic:packages/buildings.Archetype.Clinic",
		kind = .Scripted,
	},
	Fixture_Migration_Resolution {
		change_id = "enum-add:adriatic:packages/buildings.Landmark_Kind.Clinic",
		kind = .Scripted,
	},
}

fixture_migrate_v0012_to_v0013 :: proc(
	#by_ptr historical: fixture_v0012.Fixture,
	tentative: ^Fixture,
	allocator: mem.Allocator,
) -> Fixture_Migration_Error {
	_ = historical
	// Both values are appended. Existing u8 ordinals retain their exact
	// meaning, so decoding v12 into v13 is the complete migration.
	_ = tentative
	_ = allocator
	return {}
}
