package main

import fixture_v0013 "../packages/fixture_history/v0013"
import terrain "../packages/terrain"
import "core:mem"

FIXTURE_MIGRATION_V0013_TO_V0014_FROM_VERSION :: 13
FIXTURE_MIGRATION_V0013_TO_V0014_TO_VERSION :: 14
FIXTURE_MIGRATION_V0013_TO_V0014_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.cliff_elevation_mode", kind = .Scripted},
}

fixture_migrate_v0013_to_v0014 :: proc(
    #by_ptr historical: fixture_v0013.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = historical
    _ = allocator
    if tentative == nil do return {kind = .Invalid_Argument}
    fixture_v0014_initialize_cliff_tool(tentative)
    return {}
}

fixture_v0014_initialize_cliff_tool :: proc(tentative: ^Fixture) {
    if tentative == nil do return
    tentative.cliff_elevation_mode = .Raise
    selected := tentative.structure_selected
    removed_before := 0
    selected_was_cliff := false
    if selected >= 0 && selected < tentative.project.structure_count {
        for index in 0 ..= selected {
            if tentative.project.structures[index].kind != .Cliff do continue
            if index == selected do selected_was_cliff = true
            removed_before += 1
        }
    }
    _ = terrain.remove_legacy_cliffs(&tentative.project)
    if selected_was_cliff || selected >= tentative.project.structure_count + removed_before {
        tentative.structure_selected = -1
    } else if selected >= 0 {
        tentative.structure_selected = selected - removed_before
    }
}
