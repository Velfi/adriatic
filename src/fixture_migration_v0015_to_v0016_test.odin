package main

import fixture_v0015 "../packages/fixture_history/v0015"
import "core:testing"

@(test)
fixture_migration_v0015_to_v0016_initializes_empty_notes :: proc(t: ^testing.T) {
    historical := new(fixture_v0015.Fixture)
    tentative := new(Fixture)
    defer free(historical)
    defer free(tentative)

    tentative.note_count = 7
    tentative.notes[0].target = .Structure
    tentative.notes[0].target_id = 99
    tentative.notes[0].text[0] = 'x'

    migration_error := fixture_migrate_v0015_to_v0016(historical^, tentative, context.allocator)
    testing.expect(t, migration_error.kind == .None)
    testing.expect(t, tentative.note_count == 0)
    testing.expect(t, tentative.notes[0].target_id == 0)
    testing.expect(t, tentative.notes[0].text[0] == 0)
}

@(test)
fixture_v0016_note_count_validation_rejects_invalid_bounds :: proc(t: ^testing.T) {
    fixture := new(Fixture)
    defer free(fixture)
    fixture.note_count = FIXTURE_NOTE_CAPACITY + 1
    migration_error := fixture_v0016_validate_notes(fixture)
    testing.expect(t, migration_error.kind == .Invalid_Source)
}
