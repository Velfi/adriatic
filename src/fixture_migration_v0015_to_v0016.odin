package main

import fixture_v0015 "../packages/fixture_history/v0015"
import "core:mem"

FIXTURE_MIGRATION_V0015_TO_V0016_FROM_VERSION :: 15
FIXTURE_MIGRATION_V0015_TO_V0016_TO_VERSION :: 16
FIXTURE_MIGRATION_V0015_TO_V0016_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:src.Fixture.note_count",
		kind = .Scripted,
	},
	Fixture_Migration_Resolution {
		change_id = "field-add:adriatic:src.Fixture.notes",
		kind = .Scripted,
	},
}

fixture_migrate_v0015_to_v0016 :: proc(
	#by_ptr historical: fixture_v0015.Fixture,
	tentative: ^Fixture,
	allocator: mem.Allocator,
) -> Fixture_Migration_Error {
	_ = historical
	_ = allocator
	if tentative == nil do return {kind = .Invalid_Argument}
	// Version 15 predates authored notes, so the only faithful default is an
	// empty collection. Clear both fields explicitly for deterministic reuse.
	tentative.notes = {}
	tentative.note_count = 0
	return fixture_v0016_validate_notes(tentative)
}

fixture_v0016_validate_notes :: proc(tentative: ^Fixture) -> Fixture_Migration_Error {
	if tentative == nil do return {kind = .Invalid_Argument}
	if tentative.note_count < 0 || tentative.note_count > FIXTURE_NOTE_CAPACITY {
		return {kind = .Invalid_Source, change_id = "field-add:adriatic:src.Fixture.note_count"}
	}
	return {}
}
