package tests

import fixture_schema "../packages/fixture_schema"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

MIGRATION_SCAFFOLD_EXPECTED_STATE_IDS :: [?]string {
    "field-add:adriatic:packages/farmland.Plan.height",
    "field-add:adriatic:packages/farmland.Plan.tradition",
    "field-add:adriatic:packages/farmland.Plan.width",
    "field-add:adriatic:packages/story.State.airfield_errand",
    "field-add:adriatic:packages/story.State.quest",
    "field-add:adriatic:src.Farm_Instance.scale_x",
    "field-add:adriatic:src.Farm_Instance.scale_z",
    "field-add:adriatic:src.Fixture.quest_tracking_revision",
    "field-add:adriatic:src.Fixture.quest_tracking_suppressed",
    "field-add:adriatic:src.Fixture.tracked_quest_node",
    "field-remove:adriatic:src.Settlement_Plan.city_plan",
    "field-type:adriatic:packages/architecture.City_Plan.alleys",
    "field-type:adriatic:packages/architecture.City_Plan.lamps",
    "field-type:adriatic:packages/architecture.City_Plan.parcels",
    "field-type:adriatic:packages/architecture.City_Plan.structures",
    "field-type:adriatic:packages/terrain.Project.structures",
}

MIGRATION_V0003_TO_V0004_STRUCTURAL_IDS :: [?]string {
    "field-add:adriatic:packages/architecture.City_Alley.curve_control_from",
    "field-add:adriatic:packages/architecture.City_Alley.curve_control_to",
    "field-add:adriatic:packages/architecture.City_Alley.curve_ready",
    "field-add:adriatic:packages/architecture.City_Alley.end_terminal",
    "field-add:adriatic:packages/architecture.City_Alley.household_demand",
    "field-add:adriatic:packages/architecture.City_Alley.start_terminal",
    "field-add:adriatic:packages/flight.Airframe.parasitic_drag_area",
    "field-add:adriatic:packages/postale.Runtime.ground_brake_amount",
    "field-add:adriatic:packages/postale.Runtime.ground_pitch_radians",
    "field-add:adriatic:packages/postale.Runtime.landing_intent",
    "field-add:adriatic:packages/postale.Runtime.landing_intent_seconds",
    "field-add:adriatic:packages/story.State.clinic_visits",
    "field-add:adriatic:packages/story.State.resident_action_seen",
    "field-add:adriatic:packages/terrain.Structure.entrance_side",
    "field-add:adriatic:src.Fixture.architecture_brush_preset",
    "field-add:adriatic:src.Fixture.architecture_brush_shape",
    "field-remove:adriatic:packages/flight.Airframe.maximum_speed",
    "field-remove:adriatic:packages/flight.Airframe.stall_speed",
    "field-remove:adriatic:packages/flight.Runtime.stall_speed_modifier",
    "field-remove:adriatic:packages/postale.Runtime.takeoff_armed",
    "field-remove:adriatic:packages/postale.Tuning.takeoff_stall_speed_scale",
    "field-remove:adriatic:packages/postale.Tuning.takeoff_vertical_assist",
    "field-remove:adriatic:src.Fixture.architecture_brush_radius",
    "field-remove:adriatic:src.Fixture.player_tail",
    "type-remove:adriatic:packages/mouse_tail.Point",
    "type-remove:adriatic:packages/mouse_tail.State",
}

migration_v0003_to_v0004_structural_id :: proc(id: string) -> bool {
    for structural_id in MIGRATION_V0003_TO_V0004_STRUCTURAL_IDS {
        if id == structural_id do return true
    }
    return false
}

MIGRATION_V0003_TO_V0004_ROOT_IDS :: [?]string {
    "field-add:adriatic:src.Fixture.farm_brush_yaw",
    "field-add:adriatic:src.Fixture.rondine",
    "field-add:adriatic:src.Fixture.rondine_visible",
    "field-add:adriatic:src.Fixture.wreck_brush_size",
    "field-add:adriatic:src.Fixture.wreck_brush_yaw",
    "field-add:adriatic:src.Fixture.wreck_count",
    "field-add:adriatic:src.Fixture.wreck_paint_mode",
    "field-add:adriatic:src.Fixture.wrecks",
}

migration_v0003_to_v0004_root_id :: proc(id: string) -> bool {
    for root_id in MIGRATION_V0003_TO_V0004_ROOT_IDS {
        if id == root_id do return true
    }
    return false
}

MIGRATION_V0003_TO_V0004_SETTLEMENT_IDS :: [?]string {
    "field-add:adriatic:src.Settlement_Metrics.dead_end_frontage",
    "field-add:adriatic:src.Settlement_Metrics.road_badness",
    "field-add:adriatic:src.Settlement_Plan.access_bad_door_approaches",
    "field-add:adriatic:src.Settlement_Plan.access_bad_road_approaches",
    "field-add:adriatic:src.Settlement_Plan.access_connected_count",
    "field-add:adriatic:src.Settlement_Plan.access_crossings",
    "field-add:adriatic:src.Settlement_Plan.access_excessive_grades",
    "field-add:adriatic:src.Settlement_Plan.access_hairpin_bends",
    "field-add:adriatic:src.Settlement_Plan.access_max_degree",
    "field-add:adriatic:src.Settlement_Plan.access_max_shared_width_step",
    "field-add:adriatic:src.Settlement_Plan.access_orphan_endpoints",
    "field-add:adriatic:src.Settlement_Plan.access_required_count",
    "field-add:adriatic:src.Settlement_Plan.access_routes_truncated",
    "field-add:adriatic:src.Settlement_Plan.access_shallow_junctions",
    "field-add:adriatic:src.Settlement_Plan.access_shared_segments",
    "field-add:adriatic:src.Settlement_Plan.access_stair_routes",
    "field-add:adriatic:src.Settlement_Plan.access_unsplit_junctions",
    "field-add:adriatic:src.Settlement_Plan.access_widened_segments",
    "field-add:adriatic:src.Settlement_Plan.activity_point_count",
    "field-add:adriatic:src.Settlement_Plan.activity_points",
    "field-add:adriatic:src.Settlement_Plan.brush_piece_count",
    "field-add:adriatic:src.Settlement_Plan.brush_pieces",
    "field-add:adriatic:src.Settlement_Plan.inhabitant_count",
    "field-add:adriatic:src.Settlement_Plan.inhabitants",
    "field-add:adriatic:src.Settlement_Plan.next_brush_component_id",
    "field-add:adriatic:src.Settlement_Plan.program",
    "field-add:adriatic:src.Settlement_Plan.road_badness_count",
    "field-add:adriatic:src.Settlement_Plan.road_badness_sum",
    "field-add:adriatic:src.Settlement_Plan.route_piece_ids",
    "field-add:adriatic:src.Settlement_Plan.site_piece_ids",
    "field-add:adriatic:src.Settlement_Request.density",
    "field-type:adriatic:src.Settlement_Plan.routes",
}

migration_v0003_to_v0004_settlement_id :: proc(id: string) -> bool {
    for settlement_id in MIGRATION_V0003_TO_V0004_SETTLEMENT_IDS {
        if id == settlement_id do return true
    }
    return false
}

migration_scaffold_production_report :: proc(t: ^testing.T) -> (report: fixture_schema.Schema_Diff_Report, ok: bool) {
    repo_root, root_error := os.get_working_directory(context.allocator)
    testing.expect(t, root_error == nil)
    if root_error != nil do return {}, false
    frozen, frozen_error := os.read_entire_file(fixture_schema.manifest_path(repo_root, 1), context.allocator)
    testing.expect(t, frozen_error == nil)
    if frozen_error != nil do return {}, false
    defer delete(frozen)
    candidate, candidate_error := os.read_entire_file(fixture_schema.manifest_path(repo_root, 2), context.allocator)
    testing.expect(t, candidate_error == nil)
    if candidate_error != nil do return {}, false
    defer delete(candidate)
    built_report, error, report_ok := fixture_schema.schema_diff_build_report(
        frozen,
        candidate,
        1,
        2,
        context.allocator,
    )
    testing.expect(t, report_ok && error.kind == .None)
    fixture_schema.schema_diff_error_dispose(&error)
    return built_report, report_ok
}

migration_scaffold_parse_error :: proc(t: ^testing.T, source: string, expected_path := "") {
    scaffold, error, ok := fixture_schema.migration_scaffold_parse(transmute([]byte)source, context.allocator)
    testing.expect(t, !ok && error.kind != .None)
    if expected_path != "" {
        testing.expect(t, strings.contains(error.path, expected_path))
    }
    if error.kind != .None do testing.expect(t, error.line >= 1 && error.column >= 1)
    fixture_schema.migration_scaffold_dispose(&scaffold)
    fixture_schema.migration_scaffold_error_dispose(&error)
}

migration_scaffold_replace :: proc(source, old, new: string) -> string {
    output, replace_ok := strings.replace_all(source, old, new, context.allocator)
    if !replace_ok do return ""
    return output
}

migration_scaffold_future_manifest :: proc(source: string, version: int) -> string {
    return migration_scaffold_replace(
        source,
        "fixture_schema_version=1",
        fmt.tprintf("fixture_schema_version=%d", version),
    )
}

migration_scaffold_many_entries :: proc(source: string, count: int) -> string {
    header := "FIXTURE_MIGRATION_V0001_TO_V0002_RESOLUTIONS :: [?]Fixture_Migration_Resolution {\n"
    header_start := strings.index(source, header)
    if header_start < 0 do return ""
    entries_start := header_start + len(header)
    close_offset := strings.index(source[entries_start:], "}\n\n")
    if close_offset < 0 do return ""
    builder, builder_error := strings.builder_make_len_cap(0, len(source) + count * 128, context.allocator)
    if builder_error != nil do return ""
    strings.write_string(&builder, source[:entries_start])
    for index in 0 ..< count {
        strings.write_string(
            &builder,
            "\tFixture_Migration_Resolution {\n\t\tchange_id = \"field-add:adriatic:test.src.Migration_",
        )
        fmt.sbprintf(&builder, "%04d", index)
        strings.write_string(&builder, "\",\n\t\tkind = .Unresolved,\n\t},\n")
    }
    strings.write_string(&builder, source[entries_start + close_offset:])
    return strings.to_string(builder)
}

migration_scaffold_large_report :: proc(count: int) -> (report: fixture_schema.Schema_Diff_Report, ok: bool) {
    report.allocator = context.allocator
    report.format_version = 1
    report.from_version = 1
    report.to_version = 2
    frozen_sha256, frozen_error := strings.clone(
        "0000000000000000000000000000000000000000000000000000000000000000",
        context.allocator,
    )
    if frozen_error != nil do return {}, false
    report.frozen_sha256 = frozen_sha256
    candidate_sha256, candidate_error := strings.clone(
        "1111111111111111111111111111111111111111111111111111111111111111",
        context.allocator,
    )
    if candidate_error != nil {
        fixture_schema.schema_diff_report_dispose(&report)
        return {}, false
    }
    report.candidate_sha256 = candidate_sha256
    changes, changes_error := make([dynamic]fixture_schema.Schema_Diff_Change, 0, count, context.allocator)
    if changes_error != nil {
        fixture_schema.schema_diff_report_dispose(&report)
        return {}, false
    }
    report.changes = changes
    for index in 0 ..< count {
        path := fmt.tprintf("adriatic:test.src.Migration_%04d", index)
        id := fmt.tprintf("field-add:%s", path)
        owned_id, id_error := strings.clone(id, context.allocator)
        owned_path, path_error := strings.clone(path, context.allocator)
        owned_after, after_error := strings.clone("builtin:u8", context.allocator)
        if id_error != nil || path_error != nil || after_error != nil {
            if id_error == nil do delete(owned_id, context.allocator)
            if path_error == nil do delete(owned_path, context.allocator)
            if after_error == nil do delete(owned_after, context.allocator)
            fixture_schema.schema_diff_report_dispose(&report)
            return {}, false
        }
        change := fixture_schema.Schema_Diff_Change {
            id     = owned_id,
            kind   = .Field_Add,
            class  = .State,
            policy = .Script_Required,
            path   = owned_path,
            before = "",
            after  = owned_after,
        }
        appended, append_error := append_elem(&report.changes, change)
        if append_error != nil || appended != 1 {
            fixture_schema.schema_diff_report_dispose(&report)
            return {}, false
        }
    }
    return report, true
}

@(test)
fixture_migration_scaffold_production_render_parse_validate :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    report, report_ok := migration_scaffold_production_report(t)
    if !report_ok do return
    defer fixture_schema.schema_diff_report_dispose(&report)

    before_sha := report.frozen_sha256
    source, error, render_ok := fixture_schema.migration_scaffold_render(&report, context.allocator)
    testing.expect(t, render_ok && error.kind == .None)
    if !render_ok {
        fixture_schema.migration_scaffold_error_dispose(&error)
        return
    }
    defer delete(source)
    second_source, second_error, second_render_ok := fixture_schema.migration_scaffold_render(
        &report,
        context.allocator,
    )
    testing.expect(t, second_render_ok && second_error.kind == .None && second_source == source)
    delete(second_source)
    fixture_schema.migration_scaffold_error_dispose(&second_error)
    testing.expect(t, !strings.contains(source, ";"))
    testing.expect(t, strings.contains(source, "Fixture_Migration_Resolution {\n\t\tchange_id = "))
    testing.expect(t, strings.contains(source, "#by_ptr historical: fixture_v0001.Fixture"))
    testing.expect(t, !strings.contains(source, "^const"))
    testing.expect(t, !strings.contains(source, "type=invalid"))
    testing.expect(t, strings.contains(source, "FIXTURE_MIGRATION_V0001_TO_V0002_FROM_VERSION :: 1"))
    testing.expect(t, strings.contains(source, "FIXTURE_MIGRATION_V0001_TO_V0002_TO_VERSION :: 2"))
    for id in MIGRATION_SCAFFOLD_EXPECTED_STATE_IDS {
        testing.expect(t, strings.contains(source, fmt.tprintf("change_id = \"%s\"", id)))
    }
    parsed, parse_error, parse_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)source,
        context.allocator,
    )
    testing.expect(t, parse_ok && parse_error.kind == .None)
    if parse_ok {
        expected_state_ids := MIGRATION_SCAFFOLD_EXPECTED_STATE_IDS
        testing.expect(t, parsed.from_version == 1 && parsed.to_version == 2)
        testing.expect(t, len(parsed.resolutions) == len(expected_state_ids))
        for resolution, index in parsed.resolutions {
            testing.expect(t, resolution.change_id == expected_state_ids[index])
            testing.expect(t, resolution.kind == .Unresolved)
        }
        validation_error, validation_ok := fixture_schema.migration_scaffold_validate(&parsed, &report)
        testing.expect(t, validation_ok && validation_error.kind == .None)
        fixture_schema.migration_scaffold_error_dispose(&validation_error)
        parsed.resolutions[0].kind = fixture_schema.Migration_Scaffold_Resolution_Kind(99)
        forged_error, forged_ok := fixture_schema.migration_scaffold_validate(&parsed, &report)
        testing.expect(t, !forged_ok && forged_error.kind == .Invalid_Input)
        fixture_schema.migration_scaffold_error_dispose(&forged_error)
    }
    fixture_schema.migration_scaffold_dispose(&parsed)
    fixture_schema.migration_scaffold_error_dispose(&parse_error)
    testing.expect(t, report.frozen_sha256 == before_sha)
}

@(test)
fixture_migration_scaffold_v0002_to_v0003_resolved_is_exact :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    report, report_ok := fixture_schema_diff_v0002_to_v0003_frozen_report(t)
    if !report_ok do return
    defer fixture_schema.schema_diff_report_dispose(&report)

    repo_root, root_error := os.get_working_directory(context.allocator)
    testing.expect(t, root_error == nil)
    if root_error != nil do return
    target := fmt.tprintf("%s/src/fixture_migration_v0002_to_v0003.odin", repo_root)
    source, read_error := os.read_entire_file(target, context.allocator)
    testing.expect(t, read_error == nil)
    if read_error != nil do return
    defer delete(source)

    generated := string(source)
    testing.expect(t, strings.contains(generated, "package main\n"))
    testing.expect(t, strings.contains(generated, "import fixture_v0002 \"../packages/fixture_history/v0002\""))
    testing.expect(t, strings.contains(generated, "FIXTURE_MIGRATION_V0002_TO_V0003_FROM_VERSION :: 2"))
    testing.expect(t, strings.contains(generated, "FIXTURE_MIGRATION_V0002_TO_V0003_TO_VERSION :: 3"))
    testing.expect(
        t,
        strings.contains(generated, "change_id = \"field-add:adriatic:src.Fixture.occupant\"") &&
        strings.contains(generated, "kind = .Scripted"),
    )
    testing.expect(t, !strings.contains(generated, "type-add:adriatic:packages/vehicles.Fixture_Occupant"))
    testing.expect(t, strings.contains(generated, "#by_ptr historical: fixture_v0002.Fixture"))
    testing.expect(t, strings.contains(generated, "fixture_migration_v0002_to_v0003_resolve_occupant"))
    testing.expect(t, strings.contains(generated, "tentative.occupant = .On_Foot"))

    parsed, parse_error, parse_ok := fixture_schema.migration_scaffold_parse(source, context.allocator)
    testing.expect(t, parse_ok && parse_error.kind == .None)
    if !parse_ok {
        fixture_schema.migration_scaffold_dispose(&parsed)
        fixture_schema.migration_scaffold_error_dispose(&parse_error)
        fixture_schema.migration_scaffold_error_dispose(&parse_error)
        return
    }
    testing.expect(t, parsed.from_version == 2 && parsed.to_version == 3)
    testing.expect(t, len(parsed.resolutions) == 1)
    if len(parsed.resolutions) == 1 {
        resolution := parsed.resolutions[0]
        testing.expect(
            t,
            resolution.change_id == "field-add:adriatic:src.Fixture.occupant" && resolution.kind == .Scripted,
        )
    }
    fixture_schema.migration_scaffold_error_dispose(&parse_error)
    validation_error, validation_ok := fixture_schema.migration_scaffold_validate(&parsed, &report)
    testing.expect(t, validation_ok && validation_error.kind == .None)
    fixture_schema.migration_scaffold_error_dispose(&validation_error)
    fixture_schema.migration_scaffold_dispose(&parsed)
    fixture_schema.migration_scaffold_dispose(&parsed)
    fixture_schema.migration_scaffold_error_dispose(&validation_error)

}

@(test)
fixture_migration_scaffold_v0003_to_v0004_resolved_is_exact :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    report, report_ok := fixture_schema_diff_v0003_to_v0004_frozen_report(t)
    if !report_ok do return
    defer fixture_schema.schema_diff_report_dispose(&report)

    repo_root, root_error := os.get_working_directory(context.allocator)
    testing.expect(t, root_error == nil)
    if root_error != nil do return
    target := fmt.tprintf("%s/src/fixture_migration_v0003_to_v0004.odin", repo_root)
    source, read_error := os.read_entire_file(target, context.allocator)
    testing.expect(t, read_error == nil)
    if read_error != nil do return
    defer delete(source)

    source_sha, source_sha_ok := fixture_schema.history_manifest_sha256_hex(source, context.allocator)
    testing.expect(
        t,
        source_sha_ok && source_sha == "abb7ba79049fd12096a7779eaa1281189913acc0a78e9afe567b3cb4d24b4e3d",
    )
    if !source_sha_ok do return
    defer delete(source_sha)

    generated := string(source)
    testing.expect(t, strings.contains(generated, "package main\n"))
    testing.expect(t, strings.contains(generated, "import fixture_v0003 \"../packages/fixture_history/v0003\""))
    testing.expect(t, strings.contains(generated, "FIXTURE_MIGRATION_V0003_TO_V0004_FROM_VERSION :: 3"))
    testing.expect(t, strings.contains(generated, "FIXTURE_MIGRATION_V0003_TO_V0004_TO_VERSION :: 4"))
    testing.expect(t, strings.contains(generated, "#by_ptr historical: fixture_v0003.Fixture"))
    testing.expect(t, !strings.contains(generated, "^const"))
    testing.expect(
        t,
        strings.contains(
            generated,
            "FIXTURE_MIGRATION_V0003_SETTLEMENT_ID :: \"field-add:adriatic:src.Settlement_Metrics.dead_end_frontage\"",
        ),
    )
    testing.expect(t, !strings.contains(generated, "FIXTURE_MIGRATION_V0003_FIRST_UNRESOLVED_ID"))

    parsed, parse_error, parse_ok := fixture_schema.migration_scaffold_parse(source, context.allocator)
    testing.expect(t, parse_ok && parse_error.kind == .None)
    if !parse_ok {
        fixture_schema.migration_scaffold_dispose(&parsed)
        fixture_schema.migration_scaffold_error_dispose(&parse_error)
        return
    }
    fixture_schema.migration_scaffold_error_dispose(&parse_error)
    defer fixture_schema.migration_scaffold_dispose(&parsed)
    testing.expect(t, parsed.from_version == 3 && parsed.to_version == 4)
    testing.expect(t, len(parsed.resolutions) == 100)
    testing.expect(t, len(MIGRATION_V0003_TO_V0004_STRUCTURAL_IDS) == 26)
    for structural_id in MIGRATION_V0003_TO_V0004_STRUCTURAL_IDS {
        matches := 0
        for resolution in parsed.resolutions {
            if resolution.change_id == structural_id {
                matches += 1
                testing.expect(t, resolution.kind == .Scripted)
            }
        }
        testing.expect(t, matches == 1)
    }
    testing.expect(t, len(MIGRATION_V0003_TO_V0004_ROOT_IDS) == 8)
    for root_id in MIGRATION_V0003_TO_V0004_ROOT_IDS {
        matches := 0
        for resolution in parsed.resolutions {
            if resolution.change_id == root_id {
                matches += 1
                testing.expect(t, resolution.kind == .Scripted)
            }
        }
        testing.expect(t, matches == 1)
    }
    testing.expect(t, len(MIGRATION_V0003_TO_V0004_SETTLEMENT_IDS) == 32)
    for settlement_id in MIGRATION_V0003_TO_V0004_SETTLEMENT_IDS {
        matches := 0
        for resolution in parsed.resolutions {
            if resolution.change_id == settlement_id {
                matches += 1
                testing.expect(t, resolution.kind == .Scripted)
            }
        }
        testing.expect(t, matches == 1)
    }

    state_count := 0
    supporting_count := 0
    scripted_count := 0
    unresolved_count := 0
    automatic_count := 0
    resolution_index := 0
    previous_id := ""
    for change in report.changes {
        if change.class == .Supporting {
            supporting_count += 1
            testing.expect(t, !strings.contains(generated, fmt.tprintf("change_id = \"%s\"", change.id)))
            continue
        }
        state_count += 1
        testing.expect(t, resolution_index < len(parsed.resolutions))
        if resolution_index >= len(parsed.resolutions) do continue
        resolution := parsed.resolutions[resolution_index]
        testing.expect(t, resolution.change_id == change.id)
        if change.kind == .Enum_Add ||
           change.kind == .Enum_Value ||
           migration_v0003_to_v0004_structural_id(change.id) ||
           migration_v0003_to_v0004_root_id(change.id) ||
           migration_v0003_to_v0004_settlement_id(change.id) {
            testing.expect(t, resolution.kind == .Scripted)
        } else {
            testing.expect(t, resolution.kind == .Unresolved)
        }
        switch resolution.kind {
        case .Scripted:
            scripted_count += 1
        case .Unresolved:
            unresolved_count += 1
        case .Automatic:
            automatic_count += 1
        }
        if resolution_index > 0 do testing.expect(t, previous_id < resolution.change_id)
        previous_id = resolution.change_id
        resolution_index += 1
    }
    testing.expect(
        t,
        state_count == 100 &&
        supporting_count == 19 &&
        scripted_count == 100 &&
        unresolved_count == 0 &&
        automatic_count == 0 &&
        resolution_index == len(parsed.resolutions),
    )
    validation_error, validation_ok := fixture_schema.migration_scaffold_validate(&parsed, &report)
    testing.expect(t, validation_ok && validation_error.kind == .None)
    fixture_schema.migration_scaffold_error_dispose(&validation_error)
}

@(test)
fixture_migration_scaffold_synthetic_resolutions_and_body_variants :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    report, report_ok := schema_diff_test_report_for(t, string(DIFF_SWEEP_FROZEN), string(DIFF_SWEEP_CANDIDATE))
    if !report_ok do return
    defer fixture_schema.schema_diff_report_dispose(&report)
    original_kind := report.changes[0].kind
    report.changes[0].kind = fixture_schema.Schema_Diff_Change_Kind(99)
    _, forged_report_error, forged_report_ok := fixture_schema.migration_scaffold_render(&report, context.allocator)
    testing.expect(t, !forged_report_ok && forged_report_error.kind == .Invalid_Input)
    fixture_schema.migration_scaffold_error_dispose(&forged_report_error)
    report.changes[0].kind = original_kind
    source, error, render_ok := fixture_schema.migration_scaffold_render(&report, context.allocator)
    testing.expect(t, render_ok && error.kind == .None)
    if !render_ok {
        fixture_schema.migration_scaffold_error_dispose(&error)
        return
    }
    defer delete(source)
    parsed, parse_error, parse_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)source,
        context.allocator,
    )
    testing.expect(t, parse_ok)
    if parse_ok {
        testing.expect(t, len(parsed.resolutions) == 7)
        expected_ids := [?]string {
            "enum-add:adriatic:test.src.Mode.On",
            "field-add:adriatic:test.src.Root.new_field",
            "field-remove:adriatic:test.src.Inner.remove_me",
            "field-tag:adriatic:test.src.Root.tagged",
            "field-type:adriatic:test.src.Root.grid",
            "field-type:adriatic:test.src.Root.payload",
            "type-remove:adriatic:test.src.Removed",
        }
        for resolution, index in parsed.resolutions {
            testing.expect(t, resolution.change_id == expected_ids[index])
        }
        parsed.resolutions[0].kind = .Automatic
        parsed.resolutions[1].kind = .Scripted
        validation_error, validation_ok := fixture_schema.migration_scaffold_validate(&parsed, &report)
        testing.expect(t, validation_ok && validation_error.kind == .None)
        fixture_schema.migration_scaffold_error_dispose(&validation_error)
    }
    fixture_schema.migration_scaffold_dispose(&parsed)
    fixture_schema.migration_scaffold_error_dispose(&parse_error)

    variant := migration_scaffold_replace(
        source,
        "import \"core:mem\"\n",
        "import \"core:mem\"\nimport \"core:strings\"\n",
    )
    variant = migration_scaffold_replace(variant, "\t_ = historical\n", "    if tentative != nil { _ = historical }\n")
    variant = migration_scaffold_replace(variant, "kind = .Unresolved,", "kind = .Automatic,")
    variant = migration_scaffold_replace(
        variant,
        "fixture_migrate_v0001_to_v0002 :: proc(",
        "helper :: proc() {}\nfixture_migrate_v0001_to_v0002 :: proc(",
    )
    variant_scaffold, variant_error, variant_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)variant,
        context.allocator,
    )
    testing.expect(t, variant_ok)
    if variant_ok {
        variant_validation_error, variant_validation_ok := fixture_schema.migration_scaffold_validate(
            &variant_scaffold,
            &report,
        )
        testing.expect(t, variant_validation_ok && variant_validation_error.kind == .None)
        fixture_schema.migration_scaffold_error_dispose(&variant_validation_error)
    }
    fixture_schema.migration_scaffold_dispose(&variant_scaffold)
    fixture_schema.migration_scaffold_error_dispose(&variant_error)
    delete(variant)

    future_frozen := migration_scaffold_future_manifest(string(DIFF_SWEEP_FROZEN), 2)
    future_candidate := migration_scaffold_future_manifest(string(DIFF_SWEEP_CANDIDATE), 3)
    future_report, future_report_ok := schema_diff_test_report_for(t, future_frozen, future_candidate, 2, 3)
    if future_report_ok {
        future_source, future_error, future_ok := fixture_schema.migration_scaffold_render(
            &future_report,
            context.allocator,
        )
        testing.expect(t, future_ok)
        if future_ok {
            future_scaffold, future_parse_error, future_parse_ok := fixture_schema.migration_scaffold_parse(
                transmute([]byte)future_source,
                context.allocator,
            )
            testing.expect(t, future_parse_ok && future_scaffold.from_version == 2 && future_scaffold.to_version == 3)
            fixture_schema.migration_scaffold_dispose(&future_scaffold)
            fixture_schema.migration_scaffold_error_dispose(&future_parse_error)
            delete(future_source)
        }
        fixture_schema.migration_scaffold_error_dispose(&future_error)
        fixture_schema.schema_diff_report_dispose(&future_report)
    }
    delete(future_frozen)
    delete(future_candidate)
}

@(test)
fixture_migration_scaffold_rejects_metadata_and_abi_edits :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    report, report_ok := schema_diff_test_report_for(t, string(DIFF_SWEEP_FROZEN), string(DIFF_SWEEP_CANDIDATE))
    if !report_ok do return
    defer fixture_schema.schema_diff_report_dispose(&report)
    source, error, render_ok := fixture_schema.migration_scaffold_render(&report, context.allocator)
    testing.expect(t, render_ok)
    if !render_ok {
        fixture_schema.migration_scaffold_error_dispose(&error)
        return
    }
    defer delete(source)

    cases := [?]struct {
        old, new, path: string,
    } {
        {"package main", "package wrong", "package"},
        {
            "import fixture_v0001 \"../packages/fixture_history/v0001\"",
            "import other \"../packages/fixture_history/v0001\"",
            "imports.fixture_history",
        },
        {"FROM_VERSION :: 1", "FROM_VERSION : int = 1", "from_version"},
        {"FROM_VERSION :: 1", "FROM_VERSION :: 0", "from_version"},
        {"FROM_VERSION :: 1", "FROM_VERSION :: 1 + 0", "from_version"},
        {"TO_VERSION :: 2", "TO_VERSION :: 4", "versions"},
        {"fixture_migrate_v0001_to_v0002 ::", "fixture_migrate_v0001_to_v0003 ::", "procedure"},
        {"#by_ptr historical: fixture_v0001.Fixture,", "historical: fixture_v0001.Fixture,", "procedure.historical"},
        {"#by_ptr historical: fixture_v0001.Fixture,", "historical: ^fixture_v0001.Fixture,", "procedure.historical"},
        {"tentative: ^Fixture,", "tentative: Fixture,", "procedure.tentative"},
        {"allocator: mem.Allocator,", "allocator: ^mem.Allocator,", "procedure.allocator"},
        {") -> Fixture_Migration_Error {", ") -> ^Fixture_Migration_Error {", "procedure.result"},
    }
    for test_case in cases {
        bad := migration_scaffold_replace(source, test_case.old, test_case.new)
        migration_scaffold_parse_error(t, bad, test_case.path)
        delete(bad)
    }
    comment_only := migration_scaffold_replace(
        source,
        "FIXTURE_MIGRATION_V0001_TO_V0002_FROM_VERSION :: 1",
        "// FIXTURE_MIGRATION_V0001_TO_V0002_FROM_VERSION :: 1",
    )
    migration_scaffold_parse_error(t, comment_only, "metadata")
    delete(comment_only)
}

@(test)
fixture_migration_scaffold_rejects_entries_versions_and_encoding :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    report, report_ok := schema_diff_test_report_for(t, string(DIFF_SWEEP_FROZEN), string(DIFF_SWEEP_CANDIDATE))
    if !report_ok do return
    defer fixture_schema.schema_diff_report_dispose(&report)
    source, error, render_ok := fixture_schema.migration_scaffold_render(&report, context.allocator)
    testing.expect(t, render_ok)
    if !render_ok {
        fixture_schema.migration_scaffold_error_dispose(&error)
        return
    }
    defer delete(source)
    first_entry := "Fixture_Migration_Resolution {\n\t\tchange_id = \"enum-add:adriatic:test.src.Mode.On\",\n\t\tkind = .Unresolved,\n\t},"
    duplicate := migration_scaffold_replace(source, first_entry, fmt.tprintf("%s\n%s", first_entry, first_entry))
    migration_scaffold_parse_error(t, duplicate, "resolutions[1]")
    delete(duplicate)
    unknown_kind := migration_scaffold_replace(source, "kind = .Unresolved", "kind = .Bogus")
    migration_scaffold_parse_error(t, unknown_kind, "resolutions[0]")
    delete(unknown_kind)
    missing := migration_scaffold_replace(source, fmt.tprintf("%s\n", first_entry), "")
    missing_scaffold, missing_error, missing_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)missing,
        context.allocator,
    )
    testing.expect(t, missing_ok)
    if missing_ok {
        validation_error, validation_ok := fixture_schema.migration_scaffold_validate(&missing_scaffold, &report)
        testing.expect(t, !validation_ok && strings.contains(validation_error.path, "resolutions"))
        fixture_schema.migration_scaffold_error_dispose(&validation_error)
    }
    fixture_schema.migration_scaffold_dispose(&missing_scaffold)
    fixture_schema.migration_scaffold_error_dispose(&missing_error)
    delete(missing)
    extra_entry := "\tFixture_Migration_Resolution {\n\t\tchange_id = \"type-add:adriatic:test.src.Extra\",\n\t\tkind = .Automatic,\n\t},\n"
    extra_tail := "\tFixture_Migration_Resolution {\n\t\tchange_id = \"type-remove:adriatic:test.src.Removed\",\n\t\tkind = .Unresolved,\n\t},\n"
    extra_replacement_parts := [?]string{extra_entry, extra_tail}
    extra_replacement, extra_replacement_error := strings.concatenate(extra_replacement_parts[:], context.allocator)
    testing.expect(t, extra_replacement_error == nil)
    extra := migration_scaffold_replace(source, extra_tail, extra_replacement)
    extra_scaffold, extra_error, extra_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)extra,
        context.allocator,
    )
    testing.expect(t, extra_ok)
    if extra_ok {
        validation_error, validation_ok := fixture_schema.migration_scaffold_validate(&extra_scaffold, &report)
        testing.expect(t, !validation_ok && strings.contains(validation_error.path, "resolutions"))
        fixture_schema.migration_scaffold_error_dispose(&validation_error)
    }
    fixture_schema.migration_scaffold_dispose(&extra_scaffold)
    fixture_schema.migration_scaffold_error_dispose(&extra_error)
    delete(extra_replacement)
    delete(extra)
    comment_id := migration_scaffold_replace(
        source,
        "change_id = \"enum-add:adriatic:test.src.Mode.On\"",
        "change_id = \"comment\"",
    )
    comment_scaffold, comment_error, comment_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)comment_id,
        context.allocator,
    )
    testing.expect(t, comment_ok)
    if comment_ok {
        validation_error, validation_ok := fixture_schema.migration_scaffold_validate(&comment_scaffold, &report)
        testing.expect(t, !validation_ok && strings.contains(validation_error.path, "resolutions[0]"))
        fixture_schema.migration_scaffold_error_dispose(&validation_error)
    }
    fixture_schema.migration_scaffold_dispose(&comment_scaffold)
    fixture_schema.migration_scaffold_error_dispose(&comment_error)
    delete(comment_id)
    bad_versions := [?]struct {
        old, new: string,
    } {
        {"FROM_VERSION :: 1", "FROM_VERSION :: 01"},
        {"FROM_VERSION :: 1", "FROM_VERSION :: -1"},
        {"FROM_VERSION :: 1", "FROM_VERSION :: 10000"},
        {"TO_VERSION :: 2", "TO_VERSION :: 3"},
        {"TO_VERSION :: 2", "TO_VERSION :: 1"},
    }
    for bad_version in bad_versions {
        bad := migration_scaffold_replace(source, bad_version.old, bad_version.new)
        migration_scaffold_parse_error(t, bad, "version")
        delete(bad)
    }
    invalid_utf8 := make([]byte, len(source) + 1, context.allocator)
    copy(invalid_utf8[:len(source)], transmute([]byte)source)
    invalid_utf8[len(source)] = 0xff
    migration_scaffold_parse_error(t, string(invalid_utf8), "$")
    delete(invalid_utf8)
    malformed := migration_scaffold_replace(source, "package main", "package main {")
    migration_scaffold_parse_error(t, malformed, "$")
    delete(malformed)
    tiny_limits := fixture_schema.Migration_Scaffold_Limits {
        max_bytes       = len(source) - 1,
        max_obligations = 1024,
    }
    _, limit_error, limit_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)source,
        context.allocator,
        tiny_limits,
    )
    testing.expect(t, !limit_ok && limit_error.kind == .Limit_Exceeded)
    fixture_schema.migration_scaffold_error_dispose(&limit_error)
    tiny_obligation_limits := fixture_schema.Migration_Scaffold_Limits {
        max_bytes       = len(source),
        max_obligations = 6,
    }
    _, obligation_error, obligation_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)source,
        context.allocator,
        tiny_obligation_limits,
    )
    testing.expect(t, !obligation_ok && obligation_error.kind == .Limit_Exceeded)
    fixture_schema.migration_scaffold_error_dispose(&obligation_error)
}

@(test)
fixture_migration_scaffold_positions_limits_names_and_extensibility :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    report, report_ok := schema_diff_test_report_for(t, string(DIFF_SWEEP_FROZEN), string(DIFF_SWEEP_CANDIDATE))
    if !report_ok do return
    defer fixture_schema.schema_diff_report_dispose(&report)
    source, render_error, render_ok := fixture_schema.migration_scaffold_render(&report, context.allocator)
    testing.expect(t, render_ok)
    fixture_schema.migration_scaffold_error_dispose(&render_error)
    if !render_ok do return
    defer delete(source)

    first_entry := "Fixture_Migration_Resolution {\n\t\tchange_id = \"enum-add:adriatic:test.src.Mode.On\",\n\t\tkind = .Unresolved,\n\t},"
    bad_id := migration_scaffold_replace(
        source,
        "change_id = \"enum-add:adriatic:test.src.Mode.On\"",
        "change_id = \"comment\"",
    )
    bad_id_scaffold, bad_id_parse_error, bad_id_parse_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)bad_id,
        context.allocator,
    )
    testing.expect(t, bad_id_parse_ok)
    if bad_id_parse_ok {
        bad_id_error, bad_id_ok := fixture_schema.migration_scaffold_validate(&bad_id_scaffold, &report)
        testing.expect(
            t,
            !bad_id_ok &&
            bad_id_error.kind == .Invalid_Input &&
            bad_id_error.line == bad_id_scaffold.resolutions[0].line &&
            bad_id_error.column == bad_id_scaffold.resolutions[0].column &&
            bad_id_error.line > 1,
        )
        fixture_schema.migration_scaffold_error_dispose(&bad_id_error)
        bad_id_scaffold.resolutions[0].kind = fixture_schema.Migration_Scaffold_Resolution_Kind(99)
        forged_kind_error, forged_kind_ok := fixture_schema.migration_scaffold_validate(&bad_id_scaffold, &report)
        testing.expect(
            t,
            !forged_kind_ok &&
            forged_kind_error.kind == .Invalid_Input &&
            forged_kind_error.line == bad_id_scaffold.resolutions[0].line &&
            forged_kind_error.column == bad_id_scaffold.resolutions[0].column,
        )
        fixture_schema.migration_scaffold_error_dispose(&forged_kind_error)
    }
    fixture_schema.migration_scaffold_dispose(&bad_id_scaffold)
    fixture_schema.migration_scaffold_error_dispose(&bad_id_parse_error)
    delete(bad_id)

    bad_kind := migration_scaffold_replace(source, "kind = .Unresolved", "kind = .Bogus")
    _, bad_kind_error, bad_kind_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)bad_kind,
        context.allocator,
    )
    testing.expect(
        t,
        !bad_kind_ok && bad_kind_error.kind == .Invalid_Input && bad_kind_error.line > 1 && bad_kind_error.column > 1,
    )
    fixture_schema.migration_scaffold_error_dispose(&bad_kind_error)
    delete(bad_kind)

    missing := migration_scaffold_replace(source, fmt.tprintf("%s\n", first_entry), "")
    missing_scaffold, missing_parse_error, missing_parse_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)missing,
        context.allocator,
    )
    testing.expect(t, missing_parse_ok)
    if missing_parse_ok {
        missing_error, missing_ok := fixture_schema.migration_scaffold_validate(&missing_scaffold, &report)
        testing.expect(
            t,
            !missing_ok &&
            missing_error.kind == .Invalid_Input &&
            missing_error.line == missing_scaffold.resolutions_line &&
            missing_error.column == missing_scaffold.resolutions_column &&
            missing_error.line > 1,
        )
        fixture_schema.migration_scaffold_error_dispose(&missing_error)
    }
    fixture_schema.migration_scaffold_dispose(&missing_scaffold)
    fixture_schema.migration_scaffold_error_dispose(&missing_parse_error)
    delete(missing)

    future_frozen := migration_scaffold_future_manifest(string(DIFF_SWEEP_FROZEN), 2)
    future_candidate := migration_scaffold_future_manifest(string(DIFF_SWEEP_CANDIDATE), 3)
    future_report, future_report_ok := schema_diff_test_report_for(t, future_frozen, future_candidate, 2, 3)
    if future_report_ok {
        future_source, future_render_error, future_render_ok := fixture_schema.migration_scaffold_render(
            &future_report,
            context.allocator,
        )
        testing.expect(t, future_render_ok)
        fixture_schema.migration_scaffold_error_dispose(&future_render_error)
        if future_render_ok {
            future_scaffold, future_parse_error, future_parse_ok := fixture_schema.migration_scaffold_parse(
                transmute([]byte)future_source,
                context.allocator,
            )
            testing.expect(t, future_parse_ok)
            if future_parse_ok {
                future_error, future_ok := fixture_schema.migration_scaffold_validate(&future_scaffold, &report)
                testing.expect(
                    t,
                    !future_ok &&
                    future_error.kind == .Invalid_Input &&
                    future_error.line == future_scaffold.from_line &&
                    future_error.column == future_scaffold.from_column &&
                    future_error.line > 1,
                )
                fixture_schema.migration_scaffold_error_dispose(&future_error)
            }
            fixture_schema.migration_scaffold_dispose(&future_scaffold)
            fixture_schema.migration_scaffold_error_dispose(&future_parse_error)
            delete(future_source)
        }
        fixture_schema.schema_diff_report_dispose(&future_report)
    }
    delete(future_frozen)
    delete(future_candidate)

    lower_boundary := fixture_schema.Migration_Scaffold_Limits {
        max_bytes       = len(source),
        max_obligations = 7,
    }
    lower_scaffold, lower_error, lower_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)source,
        context.allocator,
        lower_boundary,
    )
    testing.expect(t, lower_ok && len(lower_scaffold.resolutions) == 7)
    fixture_schema.migration_scaffold_dispose(&lower_scaffold)
    fixture_schema.migration_scaffold_error_dispose(&lower_error)

    at_hard_cap_source := migration_scaffold_many_entries(source, fixture_schema.MIGRATION_SCAFFOLD_MAX_OBLIGATIONS)
    at_hard_cap_scaffold, at_hard_cap_error, at_hard_cap_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)at_hard_cap_source,
        context.allocator,
    )
    testing.expect(
        t,
        at_hard_cap_ok && len(at_hard_cap_scaffold.resolutions) == fixture_schema.MIGRATION_SCAFFOLD_MAX_OBLIGATIONS,
    )
    fixture_schema.migration_scaffold_dispose(&at_hard_cap_scaffold)
    fixture_schema.migration_scaffold_error_dispose(&at_hard_cap_error)
    delete(at_hard_cap_source)

    over_hard_cap_source := migration_scaffold_many_entries(
        source,
        fixture_schema.MIGRATION_SCAFFOLD_MAX_OBLIGATIONS + 1,
    )
    _, over_hard_cap_error, over_hard_cap_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)over_hard_cap_source,
        context.allocator,
    )
    testing.expect(t, !over_hard_cap_ok && over_hard_cap_error.kind == .Limit_Exceeded)
    fixture_schema.migration_scaffold_error_dispose(&over_hard_cap_error)
    delete(over_hard_cap_source)

    above_hard_cap_limits := fixture_schema.Migration_Scaffold_Limits {
        max_bytes       = len(source),
        max_obligations = fixture_schema.MIGRATION_SCAFFOLD_MAX_OBLIGATIONS + 1,
    }
    _, above_hard_cap_error, above_hard_cap_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)source,
        context.allocator,
        above_hard_cap_limits,
    )
    testing.expect(t, !above_hard_cap_ok && above_hard_cap_error.kind == .Invalid_Input)
    fixture_schema.migration_scaffold_error_dispose(&above_hard_cap_error)

    invalid_limits := [?]fixture_schema.Migration_Scaffold_Limits {
        {max_bytes = -1, max_obligations = fixture_schema.MIGRATION_SCAFFOLD_MAX_OBLIGATIONS},
        {max_bytes = len(source), max_obligations = -1},
        {max_bytes = fixture_schema.MIGRATION_SCAFFOLD_MAX_SOURCE_BYTES + 1, max_obligations = 7},
    }
    for limits in invalid_limits {
        _, invalid_limits_error, invalid_limits_ok := fixture_schema.migration_scaffold_parse(
            transmute([]byte)source,
            context.allocator,
            limits,
        )
        testing.expect(t, !invalid_limits_ok && invalid_limits_error.kind == .Invalid_Input)
        fixture_schema.migration_scaffold_error_dispose(&invalid_limits_error)
    }

    large_report, large_report_ok := migration_scaffold_large_report(fixture_schema.MIGRATION_SCAFFOLD_MAX_OBLIGATIONS)
    testing.expect(t, large_report_ok)
    if large_report_ok {
        large_source, large_error, large_ok := fixture_schema.migration_scaffold_render(
            &large_report,
            context.allocator,
        )
        testing.expect(t, large_ok && large_error.kind == .None)
        fixture_schema.migration_scaffold_error_dispose(&large_error)
        if large_ok do delete(large_source)
        fixture_schema.schema_diff_report_dispose(&large_report)
    }
    over_large_report, over_large_report_ok := migration_scaffold_large_report(
        fixture_schema.MIGRATION_SCAFFOLD_MAX_OBLIGATIONS + 1,
    )
    testing.expect(t, over_large_report_ok)
    if over_large_report_ok {
        _, over_large_error, over_large_ok := fixture_schema.migration_scaffold_render(
            &over_large_report,
            context.allocator,
        )
        testing.expect(t, !over_large_ok && over_large_error.kind == .Limit_Exceeded)
        fixture_schema.migration_scaffold_error_dispose(&over_large_error)
        fixture_schema.schema_diff_report_dispose(&over_large_report)
    }

    multi_name := migration_scaffold_replace(
        source,
        "FIXTURE_MIGRATION_V0001_TO_V0002_FROM_VERSION :: 1",
        "hidden, FIXTURE_MIGRATION_V0001_TO_V0002_FROM_VERSION :: 1, 1",
    )
    migration_scaffold_parse_error(t, multi_name, "from_version")
    delete(multi_name)
    mem_alias := migration_scaffold_replace(source, "import \"core:mem\"", "import mem \"other\"\nimport \"core:mem\"")
    migration_scaffold_parse_error(t, mem_alias, "imports.core_mem")
    delete(mem_alias)
    history_alias := migration_scaffold_replace(
        source,
        "import fixture_v0001 \"../packages/fixture_history/v0001\"",
        "import fixture_v0001 \"other\"\nimport fixture_v0001 \"../packages/fixture_history/v0001\"",
    )
    migration_scaffold_parse_error(t, history_alias, "imports.fixture_history")
    delete(history_alias)
}

@(test)
fixture_migration_scaffold_allocator_failures_and_ownership :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    report, report_ok := schema_diff_test_report_for(t, string(DIFF_SWEEP_FROZEN), string(DIFF_SWEEP_CANDIDATE))
    if !report_ok do return
    defer fixture_schema.schema_diff_report_dispose(&report)
    baseline, baseline_error, baseline_ok := fixture_schema.migration_scaffold_render(&report, context.allocator)
    testing.expect(t, baseline_ok)
    fixture_schema.migration_scaffold_error_dispose(&baseline_error)
    if !baseline_ok do return
    defer delete(baseline)
    source_copy, source_copy_error := strings.clone(baseline, context.allocator)
    report_id_copy, report_id_copy_error := strings.clone(report.changes[0].id, context.allocator)
    testing.expect(t, source_copy_error == nil && report_id_copy_error == nil)
    defer {
        if source_copy_error == nil do delete(source_copy)
        if report_id_copy_error == nil do delete(report_id_copy)
    }

    success_state := Fixture_Schema_Diff_Fault_Allocator {
        backing    = runtime.default_allocator(),
        fail_index = -1,
    }
    success_allocator := fixture_schema_diff_fault_allocator(&success_state)
    rendered, render_error, rendered_ok := fixture_schema.migration_scaffold_render(&report, success_allocator)
    testing.expect(t, rendered_ok && rendered == baseline && success_state.attempts > 0)
    testing.expect(t, baseline == source_copy && report.changes[0].id == report_id_copy)
    if rendered_ok do delete(rendered, success_allocator)
    fixture_schema.migration_scaffold_error_dispose(&render_error)
    fixture_schema.migration_scaffold_error_dispose(&render_error)
    testing.expect(t, success_state.outstanding == 0)
    for fail_index in 0 ..< success_state.attempts {
        state := Fixture_Schema_Diff_Fault_Allocator {
            backing    = runtime.default_allocator(),
            fail_index = fail_index,
        }
        allocator := fixture_schema_diff_fault_allocator(&state)
        failed, failed_error, failed_ok := fixture_schema.migration_scaffold_render(&report, allocator)
        testing.expect(t, !failed_ok && len(failed) == 0 && failed_error.kind == .Out_Of_Memory)
        delete(failed, allocator)
        fixture_schema.migration_scaffold_error_dispose(&failed_error)
        fixture_schema.migration_scaffold_error_dispose(&failed_error)
        testing.expect(t, state.outstanding == 0)
    }

    parse_success_state := Fixture_Schema_Diff_Fault_Allocator {
        backing    = runtime.default_allocator(),
        fail_index = -1,
    }
    parse_allocator := fixture_schema_diff_fault_allocator(&parse_success_state)
    parsed, parse_error, parse_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)baseline,
        parse_allocator,
    )
    testing.expect(t, parse_ok && parse_success_state.attempts > 0)
    fixture_schema.migration_scaffold_dispose(&parsed)
    fixture_schema.migration_scaffold_error_dispose(&parse_error)
    fixture_schema.migration_scaffold_dispose(&parsed)
    fixture_schema.migration_scaffold_error_dispose(&parse_error)
    testing.expect(t, parse_success_state.outstanding == 0)
    for fail_index in 0 ..< parse_success_state.attempts {
        state := Fixture_Schema_Diff_Fault_Allocator {
            backing    = runtime.default_allocator(),
            fail_index = fail_index,
        }
        allocator := fixture_schema_diff_fault_allocator(&state)
        failed_scaffold, failed_error, failed_ok := fixture_schema.migration_scaffold_parse(
            transmute([]byte)baseline,
            allocator,
        )
        testing.expect(t, !failed_ok && failed_error.kind == .Out_Of_Memory)
        fixture_schema.migration_scaffold_dispose(&failed_scaffold)
        fixture_schema.migration_scaffold_error_dispose(&failed_error)
        fixture_schema.migration_scaffold_error_dispose(&failed_error)
        testing.expect(t, state.outstanding == 0)
    }
    _, nil_error, nil_ok := fixture_schema.migration_scaffold_parse(transmute([]byte)baseline, mem.Allocator{})
    testing.expect(t, !nil_ok && nil_error.kind == .Out_Of_Memory)
    fixture_schema.migration_scaffold_error_dispose(&nil_error)
    fixture_schema.migration_scaffold_error_dispose(&nil_error)

    _, nil_render_error, nil_render_ok := fixture_schema.migration_scaffold_render(&report, mem.Allocator{})
    testing.expect(t, !nil_render_ok && nil_render_error.kind == .Out_Of_Memory)
    fixture_schema.migration_scaffold_error_dispose(&nil_render_error)
    fixture_schema.migration_scaffold_error_dispose(&nil_render_error)
    _, nil_report_error, nil_report_ok := fixture_schema.migration_scaffold_render(nil, context.allocator)
    testing.expect(t, !nil_report_ok && nil_report_error.kind == .Invalid_Input)
    fixture_schema.migration_scaffold_error_dispose(&nil_report_error)
    fixture_schema.migration_scaffold_error_dispose(&nil_report_error)

    duplicate := migration_scaffold_replace(
        baseline,
        "Fixture_Migration_Resolution {\n\t\tchange_id = \"enum-add:adriatic:test.src.Mode.On\",\n\t\tkind = .Unresolved,\n\t},",
        "Fixture_Migration_Resolution {\n\t\tchange_id = \"enum-add:adriatic:test.src.Mode.On\",\n\t\tkind = .Unresolved,\n\t},\n\tFixture_Migration_Resolution {\n\t\tchange_id = \"enum-add:adriatic:test.src.Mode.On\",\n\t\tkind = .Unresolved,\n\t},",
    )
    diagnostic_success_state := Fixture_Schema_Diff_Fault_Allocator {
        backing    = runtime.default_allocator(),
        fail_index = -1,
    }
    diagnostic_success_allocator := fixture_schema_diff_fault_allocator(&diagnostic_success_state)
    _, diagnostic_error, diagnostic_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)duplicate,
        diagnostic_success_allocator,
    )
    testing.expect(
        t,
        !diagnostic_ok &&
        diagnostic_error.kind == .Invalid_Input &&
        diagnostic_error.line > 1 &&
        diagnostic_error.column > 1 &&
        diagnostic_success_state.attempts > 0,
    )
    fixture_schema.migration_scaffold_error_dispose(&diagnostic_error)
    fixture_schema.migration_scaffold_error_dispose(&diagnostic_error)
    testing.expect(t, diagnostic_success_state.outstanding == 0)
    for fail_index in 0 ..< diagnostic_success_state.attempts {
        state := Fixture_Schema_Diff_Fault_Allocator {
            backing    = runtime.default_allocator(),
            fail_index = fail_index,
        }
        allocator := fixture_schema_diff_fault_allocator(&state)
        failed_scaffold, failed_error, failed_ok := fixture_schema.migration_scaffold_parse(
            transmute([]byte)duplicate,
            allocator,
        )
        testing.expect(
            t,
            !failed_ok &&
            (failed_error.kind == .Out_Of_Memory ||
                    (failed_error.kind == .Invalid_Input && failed_error.line > 1 && failed_error.column > 1)),
        )
        fixture_schema.migration_scaffold_dispose(&failed_scaffold)
        fixture_schema.migration_scaffold_error_dispose(&failed_error)
        fixture_schema.migration_scaffold_error_dispose(&failed_error)
        testing.expect(t, state.outstanding == 0)
    }
    delete(duplicate)
}

@(test)
fixture_migration_scaffold_supports_later_version_names :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    frozen := migration_scaffold_future_manifest(string(DIFF_SWEEP_FROZEN), 2)
    candidate := migration_scaffold_future_manifest(string(DIFF_SWEEP_CANDIDATE), 3)
    report, report_ok := schema_diff_test_report_for(t, frozen, candidate, 2, 3)
    delete(frozen)
    delete(candidate)
    if !report_ok do return
    defer fixture_schema.schema_diff_report_dispose(&report)

    source, render_error, render_ok := fixture_schema.migration_scaffold_render(&report, context.allocator)
    testing.expect(t, render_ok && render_error.kind == .None)
    fixture_schema.migration_scaffold_error_dispose(&render_error)
    if !render_ok do return
    defer delete(source)
    testing.expect(t, strings.contains(source, "import fixture_v0002 \"../packages/fixture_history/v0002\""))
    testing.expect(t, strings.contains(source, "FIXTURE_MIGRATION_V0002_TO_V0003_FROM_VERSION :: 2"))
    testing.expect(t, strings.contains(source, "FIXTURE_MIGRATION_V0002_TO_V0003_TO_VERSION :: 3"))
    testing.expect(t, strings.contains(source, "FIXTURE_MIGRATION_V0002_TO_V0003_RESOLUTIONS"))
    testing.expect(t, strings.contains(source, "fixture_migrate_v0002_to_v0003"))
    testing.expect(t, strings.contains(source, "#by_ptr historical: fixture_v0002.Fixture"))
    testing.expect(t, !strings.contains(source, ";"))
    testing.expect(t, strings.contains(source, "\n\tFixture_Migration_Resolution {\n\t\tchange_id = "))

    parsed, parse_error, parse_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)source,
        context.allocator,
    )
    testing.expect(t, parse_ok && parse_error.kind == .None)
    if parse_ok {
        testing.expect(t, parsed.from_version == 2 && parsed.to_version == 3)
        validation_error, validation_ok := fixture_schema.migration_scaffold_validate(&parsed, &report)
        testing.expect(t, validation_ok && validation_error.kind == .None)
        fixture_schema.migration_scaffold_error_dispose(&validation_error)
    }
    fixture_schema.migration_scaffold_dispose(&parsed)
    fixture_schema.migration_scaffold_error_dispose(&parse_error)

    success_state := Fixture_Schema_Diff_Fault_Allocator {
        backing    = runtime.default_allocator(),
        fail_index = -1,
    }
    success_allocator := fixture_schema_diff_fault_allocator(&success_state)
    rendered, rendered_error, rendered_ok := fixture_schema.migration_scaffold_render(&report, success_allocator)
    testing.expect(t, rendered_ok && rendered == source && success_state.attempts > 0)
    if rendered_ok do delete(rendered, success_allocator)
    fixture_schema.migration_scaffold_error_dispose(&rendered_error)
    fixture_schema.migration_scaffold_error_dispose(&rendered_error)
    testing.expect(t, success_state.outstanding == 0)
    for fail_index in 0 ..< success_state.attempts {
        state := Fixture_Schema_Diff_Fault_Allocator {
            backing    = runtime.default_allocator(),
            fail_index = fail_index,
        }
        allocator := fixture_schema_diff_fault_allocator(&state)
        failed, failed_error, failed_ok := fixture_schema.migration_scaffold_render(&report, allocator)
        testing.expect(t, !failed_ok && len(failed) == 0 && failed_error.kind == .Out_Of_Memory)
        delete(failed, allocator)
        fixture_schema.migration_scaffold_error_dispose(&failed_error)
        fixture_schema.migration_scaffold_error_dispose(&failed_error)
        testing.expect(t, state.outstanding == 0)
    }
}
