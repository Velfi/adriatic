package tests

import fixture_schema "../packages/fixture_schema"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

Synthetic_Repo :: struct {
    root:       string,
    collection: string,
}

Failure_Case :: struct {
    source:   string,
    expected: string,
}

make_synthetic_repo :: proc(t: ^testing.T) -> (repo: Synthetic_Repo, ok: bool) {
    root, root_err := os.make_directory_temp("", "fixture-schema-test-*", context.allocator)
    testing.expect(t, root_err == nil)
    if root_err != nil do return

    repo.root = root
    repo.collection = fmt.tprintf("%s/zelda-engine/packages", root)
    directories := [2]string{fmt.tprintf("%s/src", root), repo.collection}
    for directory in directories {
        if err := os.make_directory_all(directory); err != nil {
            testing.expect(t, false)
            _ = os.remove_all(root)
            return
        }
    }
    return repo, true
}

destroy_synthetic_repo :: proc(repo: Synthetic_Repo) {
    if repo.root != "" {
        _ = os.remove_all(repo.root)
    }
}

write_synthetic_file :: proc(t: ^testing.T, repo: Synthetic_Repo, relative, source: string) -> bool {
    path := fmt.tprintf("%s/%s", repo.root, relative)
    if err := os.make_directory_all(os.dir(path)); err != nil && err != .Exist {
        testing.expect(t, false)
        return false
    }
    ok := os.write_entire_file(path, source) == nil
    testing.expect(t, ok)
    return ok
}

fixture_source :: proc(fields, editor_fields: string) -> string {
    return fmt.tprintf(
        "package src\n\nFIXTURE_SCHEMA_VERSION :: 1\n\nFixture :: struct {{\n%s\n}}\n\nEditor :: struct {{\n%s\n}}\n",
        fields,
        editor_fields,
    )
}

build_synthetic :: proc(repo: Synthetic_Repo) -> (manifest, diagnostics: string, ok: bool) {
    manifest, _, ok, diagnostics = fixture_schema.build_manifest_report(repo.root, repo.collection)
    return
}

@(test)
fixture_schema_production_graph_matches_frozen_v4 :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    repo_root, repo_err := os.get_working_directory(context.allocator)
    testing.expect(t, repo_err == nil)
    if repo_err != nil do return

    generated, version, generated_ok, diagnostics := fixture_schema.build_manifest_report(
        repo_root,
        fmt.tprintf("%s/zelda-engine/packages", repo_root),
    )
    testing.expect(t, generated_ok)
    testing.expect(t, diagnostics == "")
    testing.expect(t, version == 4)
    stored_path := fixture_schema.manifest_path(repo_root, 4)
    stored, read_err := os.read_entire_file(stored_path, context.allocator)
    testing.expect(t, read_err == nil)
    if read_err != nil do return
    defer delete(stored)
    stored_manifest := string(stored)
    testing.expect(t, generated == stored_manifest)
    testing.expect(t, !strings.contains(generated, "invalid"))
    testing.expect(t, strings.contains(generated, "array[6]<adriatic:packages/terrain.Clipmap_Level>"))
    testing.expect(t, strings.contains(generated, "array[192]<adriatic:packages/particles.Particle>"))
    testing.expect(t, strings.contains(generated, "array[8388608]<builtin:u8>"))
    testing.expect(t, strings.contains(generated, "zelda_engine:canvas2d.Color"))
    testing.expect(
        t,
        strings.contains(
            generated,
            "field=adriatic:src.Fixture|name=occupant|using=0|tag=|type=adriatic:packages/vehicles.Fixture_Occupant",
        ),
    )
    testing.expect(
        t,
        strings.contains(
            generated,
            "field=adriatic:packages/story.State|name=resident_action_seen|using=0|tag=|type=enumerated_array[11;adriatic:packages/story.Resident]<builtin:u64>",
        ),
    )
    retained_names := [?]string {
        "marina_authored_plan",
        "farms",
        "boat_traffic",
        "settlement_plan",
        "story_state",
        "architecture_brush_shape",
        "architecture_brush_preset",
        "farm_brush_yaw",
        "wreck_paint_mode",
        "wreck_brush_size",
        "wreck_brush_yaw",
        "wrecks",
        "wreck_count",
        "rondine",
        "rondine_visible",
    }
    for name in retained_names {
        testing.expect(t, strings.contains(generated, fmt.tprintf("field=adriatic:src.Fixture|name=%s|", name)))
    }
    retained_story_names := [?]string{"clinic_visits", "resident_action_seen"}
    for name in retained_story_names {
        testing.expect(
            t,
            strings.contains(generated, fmt.tprintf("field=adriatic:packages/story.State|name=%s|", name)),
        )
    }
    excluded_names := [?]string {
        "circulation_plan",
        "circulation_revision",
        "circulation_plan_valid",
        "marina_preview_plan",
        "marina_preview_valid",
        "marina_preview_x",
        "marina_preview_z",
        "marina_preview_variation",
        "marina_brush_status",
        "marina_brush_suitability",
        "marina_brush_attempts",
        "farm_preview",
        "farm_preview_valid",
        "farm_preview_score",
        "farm_preview_site_score",
        "farm_preview_generation_score",
        "farm_preview_x",
        "farm_preview_z",
        "farm_preview_revision",
        "farm_preview_seed_offset",
        "wreck_preview",
        "wreck_preview_valid",
        "wreck_preview_x",
        "wreck_preview_z",
        "wreck_preview_revision",
        "wreck_preview_seed_offset",
        "default_marinas",
        "default_marina_islands",
        "default_marina_count",
        "player_tail",
        "cinematic_focal_length",
        "story_cinematic_shots",
        "story_cinematic_script",
        "story_cinematic_restore_pose",
        "story_meeting_cinematic_pending",
        "story_cinematic_active",
        "flight_throttle_overlay_value",
        "flight_throttle_overlay_changed_at",
        "flight_throttle_overlay_fade_started_at",
        "flight_throttle_overlay_initialized",
        "gameplay_physics",
        "player_placement_reason",
        "player_placement_revision",
        "car_physics_world",
        "car_physics_vehicle",
        "car_physics_terrain",
        "car_physics_terrain_revision",
        "car_physics_accumulator",
        "car_wheels",
        "photo_restore_pose",
        "photo_restore_inspection",
        "photo_restore_slot",
        "photo_yaw",
        "photo_pitch",
        "photo_capture_pending",
        "photo_capture_notice_until",
        "dialogue_resident",
        "main_menu_active",
        "main_menu_focus",
        "console",
        "customization_slider_drag",
        "customization_preview_dragging",
        "customization_preview_drag_x",
        "customization_preview_yaw",
        "map_time",
    }
    for name in excluded_names {
        testing.expect(t, !strings.contains(generated, fmt.tprintf("field=adriatic:src.Fixture|name=%s|", name)))
    }
    testing.expect(t, !strings.contains(generated, "type=adriatic:src.Game_Console|"))
    testing.expect(t, !strings.contains(generated, "name=structure_placing"))
    testing.expect(t, !strings.contains(generated, "name=active_slider"))
    testing.expect(t, !strings.contains(generated, "field=adriatic:packages/vehicles.Aircraft_Slot|name=vehicle|"))
    testing.expect(t, !strings.contains(generated, "field=adriatic:packages/vehicles.Character|name=vehicle|"))
    testing.expect(t, !strings.contains(generated, "field=adriatic:packages/vehicles.Vehicle|name=driver|"))
    testing.expect(t, !strings.contains(generated, "/Users/"))
}

@(test)
fixture_schema_synthetic_failures_fail_closed :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    cases := [7]Failure_Case {
        {source = fixture_source("    missing: Missing", "    runtime: int"), expected = "Fixture.missing"},
        {
            source = fixture_source("    values: [9223372036854775807 + 1]int", "    runtime: int"),
            expected = "integer addition overflow",
        },
        {source = fixture_source("    values: [1 / 0]int", "    runtime: int"), expected = "division by zero"},
        {
            source = fixture_source("    values: [1 << 64]int", "    runtime: int"),
            expected = "shift count must be between 0 and 63",
        },
        {source = fixture_source("    callback: proc()", "    runtime: int"), expected = "Fixture.callback"},
        {
            source = "package src\n\nFIXTURE_SCHEMA_VERSION :: 1\n\nCOUNT :: OTHER\nOTHER :: COUNT\n\nFixture :: struct {\n    values: [COUNT]int\n}\n",
            expected = "constant cycle",
        },
        {
            source = "package src\n\nFIXTURE_SCHEMA_VERSION :: 1\n\nAlias_A :: Alias_B\nAlias_B :: Alias_A\n\nFixture :: struct {\n    value: Alias_A\n}\n",
            expected = "type alias cycle",
        },
    }
    for test_case in cases {
        repo, repo_ok := make_synthetic_repo(t)
        if !repo_ok do continue
        write_synthetic_file(t, repo, "src/main.odin", test_case.source)
        manifest, diagnostics, generated_ok := build_synthetic(repo)
        testing.expect(t, !generated_ok)
        testing.expect(t, manifest == "")
        testing.expect(t, strings.contains(diagnostics, test_case.expected))
        testing.expect(t, strings.contains(diagnostics, "Fixture."))
        testing.expect(t, !strings.contains(manifest, "type=invalid"))
        destroy_synthetic_repo(repo)
    }
}

@(test)
fixture_schema_source_changes_and_exclusions_are_real :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    repo, repo_ok := make_synthetic_repo(t)
    testing.expect(t, repo_ok)
    if !repo_ok do return
    defer destroy_synthetic_repo(repo)

    initial := fixture_source(
        "    persisted: int\n    direct: ^Missing_Direct `fixture:\"-\"`\n    nested: Missing_Nested `fixture:\"-\"`",
        "    runtime: int",
    )
    initial = fmt.tprintf("%s\nMissing_Nested :: struct {{\n    broken: ^Missing_Nested_Type\n}}\n", initial)
    write_synthetic_file(t, repo, "src/main.odin", initial)
    original, diagnostics, ok := build_synthetic(repo)
    testing.expect(t, ok)
    testing.expect(t, diagnostics == "")
    testing.expect(t, !strings.contains(original, "name=direct"))
    testing.expect(t, !strings.contains(original, "name=nested"))
    testing.expect(t, !strings.contains(original, "adriatic:src.Missing_Nested"))

    manifest_path := fixture_schema.manifest_path(repo.root, 1)
    testing.expect(t, fixture_schema.write_manifest(repo.root, manifest_path, original))

    added_field := fixture_source(
        "    persisted: int\n    added: string\n    direct: ^Missing_Direct `fixture:\"-\"`\n    nested: Missing_Nested `fixture:\"-\"`",
        "    runtime: int\n    another_runtime: bool",
    )
    added_field = fmt.tprintf("%s\nMissing_Nested :: struct {{\n    broken: ^Missing_Nested_Type\n}}\n", added_field)
    write_synthetic_file(t, repo, "src/main.odin", added_field)
    changed, changed_diagnostics, changed_ok := build_synthetic(repo)
    testing.expect(t, changed_ok)
    testing.expect(t, changed_diagnostics == "")
    same, message := fixture_schema.compare_manifest(original, changed)
    testing.expect(t, !same)
    testing.expect(t, message != "")
    stored, read_err := os.read_entire_file(manifest_path, context.allocator)
    testing.expect(t, read_err == nil)
    if read_err == nil {
        defer delete(stored)
        stored_same, _ := fixture_schema.compare_manifest(string(stored), changed)
        testing.expect(t, !stored_same)
    }

    pointer_source := fixture_source("    bad: ^Missing", "    runtime: int")
    write_synthetic_file(t, repo, "src/main.odin", pointer_source)
    _, pointer_diagnostics, pointer_ok := build_synthetic(repo)
    testing.expect(t, !pointer_ok)
    testing.expect(t, strings.contains(pointer_diagnostics, "Fixture.bad"))

    editor_only := fixture_source("    persisted: int", "    runtime: int\n    changed_runtime: bool")
    write_synthetic_file(t, repo, "src/main.odin", editor_only)
    unchanged, unchanged_diagnostics, unchanged_ok := build_synthetic(repo)
    testing.expect(t, unchanged_ok)
    testing.expect(t, unchanged_diagnostics == "")
    testing.expect(t, original == unchanged)
}

@(test)
fixture_schema_constants_enums_and_declared_imports_resolve :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    repo, repo_ok := make_synthetic_repo(t)
    testing.expect(t, repo_ok)
    if !repo_ok do return
    defer destroy_synthetic_repo(repo)

    write_synthetic_file(t, repo, "packages/constants/main.odin", "package constants\n\nBASE, WIDTH :: 2, 4\n")
    source := "package src\n\nimport constants \"../packages/constants\"\n\nFIXTURE_SCHEMA_VERSION :: 1\n\nFixture :: struct {\n    values: [constants.WIDTH + constants.BASE]int\n}\n"
    write_synthetic_file(t, repo, "src/main.odin", source)
    manifest, diagnostics, ok := build_synthetic(repo)
    testing.expect(t, ok)
    testing.expect(t, diagnostics == "")
    testing.expect(t, strings.contains(manifest, "array[6]<builtin:int>"))

    enum_source := "package src\n\nFIXTURE_SCHEMA_VERSION :: 1\n\nState :: enum u8 {\n    Zero,\n    Explicit = 3,\n    Next,\n}\n\nFixture :: struct {\n    state: State\n}\n"
    write_synthetic_file(t, repo, "src/main.odin", enum_source)
    enum_manifest, enum_diagnostics, enum_ok := build_synthetic(repo)
    testing.expect(t, enum_ok)
    testing.expect(t, enum_diagnostics == "")
    testing.expect(t, strings.contains(enum_manifest, "enum=adriatic:src.State|name=Zero|value=0"))
    testing.expect(t, strings.contains(enum_manifest, "enum=adriatic:src.State|name=Explicit|value=3"))
    testing.expect(t, strings.contains(enum_manifest, "enum=adriatic:src.State|name=Next|value=4"))

    write_synthetic_file(
        t,
        repo,
        "packages/render_dir/main.odin",
        "package render2d\n\nColor :: struct {\n    r: u8\n}\n",
    )
    write_synthetic_file(
        t,
        repo,
        "packages/canvas_dir/main.odin",
        "package canvas2d\n\nimport \"../render_dir\"\n\nColor :: render2d.Color\n",
    )
    alias_source := "package src\n\nimport \"../packages/canvas_dir\"\n\nFIXTURE_SCHEMA_VERSION :: 1\n\nFixture :: struct {\n    color: canvas2d.Color\n}\n"
    write_synthetic_file(t, repo, "src/main.odin", alias_source)
    alias_manifest, alias_diagnostics, alias_ok := build_synthetic(repo)
    testing.expect(t, alias_ok)
    testing.expect(t, alias_diagnostics == "")
    testing.expect(t, strings.contains(alias_manifest, "adriatic:packages/canvas_dir.Color"))
    testing.expect(t, strings.contains(alias_manifest, "adriatic:packages/render_dir.Color"))
}

@(test)
fixture_schema_enumerated_arrays_are_deterministic_and_fail_closed :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    repo, repo_ok := make_synthetic_repo(t)
    testing.expect(t, repo_ok)
    if !repo_ok do return
    defer destroy_synthetic_repo(repo)

    write_synthetic_file(
        t,
        repo,
        "packages/indexes/main.odin",
        "package indexes\n\nResident :: enum i8 {\n    West = -1,\n    East,\n    Harbor,\n}\n",
    )
    source := "package src\n\nimport indexes \"../packages/indexes\"\n\nFIXTURE_SCHEMA_VERSION :: 1\n\nCamera_Slot :: enum {\n    Player,\n    Cutaway,\n    Count,\n}\n\nFixture :: struct {\n    seen: [indexes.Resident]u64\n    poses: [Camera_Slot.Count]u8\n}\n"
    write_synthetic_file(t, repo, "src/main.odin", source)
    first, first_diagnostics, first_ok := build_synthetic(repo)
    testing.expect(t, first_ok)
    testing.expect(t, first_diagnostics == "")
    testing.expect(t, strings.contains(first, "enumerated_array[3;adriatic:packages/indexes.Resident]<builtin:u64>"))
    testing.expect(t, strings.contains(first, "array[2]<builtin:u8>"))
    testing.expect(t, strings.contains(first, "type=adriatic:packages/indexes.Resident|kind=enum|"))
    testing.expect(t, strings.contains(first, "enum=adriatic:packages/indexes.Resident|name=West|value=-1"))

    second, second_diagnostics, second_ok := build_synthetic(repo)
    testing.expect(t, second_ok)
    testing.expect(t, second_diagnostics == "")
    testing.expect(t, first == second)

    hostile := "package src\n\nFIXTURE_SCHEMA_VERSION :: 1\n\nResident :: enum {\n    West,\n    East = 2,\n}\n\nFixture :: struct {\n    seen: [Resident]u64\n}\n"
    write_synthetic_file(t, repo, "src/main.odin", hostile)
    hostile_manifest, hostile_diagnostics, hostile_ok := build_synthetic(repo)
    testing.expect(t, !hostile_ok)
    testing.expect(t, hostile_manifest == "")
    testing.expect(t, strings.contains(hostile_diagnostics, "Fixture.seen.length"))
    testing.expect(t, strings.contains(hostile_diagnostics, "enumerated array index enum must be contiguous"))
}

@(test)
fixture_schema_duplicate_imports_and_paths_are_checked :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    repo, repo_ok := make_synthetic_repo(t)
    testing.expect(t, repo_ok)
    if !repo_ok do return
    defer destroy_synthetic_repo(repo)

    write_synthetic_file(t, repo, "packages/one/main.odin", "package one\n\nValue :: struct {\n    value: int\n}\n")
    write_synthetic_file(t, repo, "packages/two/main.odin", "package two\n\nValue :: struct {\n    value: int\n}\n")
    duplicate_source := "package src\n\nimport one \"../packages/one\"\nimport one \"../packages/two\"\n\nFIXTURE_SCHEMA_VERSION :: 1\n\nFixture :: struct {\n    value: one.Value\n}\n"
    write_synthetic_file(t, repo, "src/main.odin", duplicate_source)
    duplicate_manifest, duplicate_diagnostics, duplicate_ok := build_synthetic(repo)
    testing.expect(t, !duplicate_ok)
    testing.expect(t, duplicate_manifest == "")
    testing.expect(t, strings.contains(duplicate_diagnostics, "duplicate import alias one"))

    write_synthetic_file(
        t,
        repo,
        "packages/one/main.odin",
        "package one\n\nimport \"../two\"\n\nValue :: struct {\n    value: int\n}\n",
    )
    write_synthetic_file(
        t,
        repo,
        "packages/two/main.odin",
        "package two\n\nimport \"../one\"\n\nValue :: struct {\n    value: int\n}\n",
    )
    cycle_source := "package src\n\nimport \"../packages/one\"\n\nFIXTURE_SCHEMA_VERSION :: 1\n\nFixture :: struct {\n    value: one.Value\n}\n"
    write_synthetic_file(t, repo, "src/main.odin", cycle_source)
    cycle_manifest, cycle_diagnostics, cycle_ok := build_synthetic(repo)
    testing.expect(t, !cycle_ok)
    testing.expect(t, cycle_manifest == "")
    testing.expect(t, strings.contains(cycle_diagnostics, "import cycle detected"))

    write_synthetic_file(t, repo, "packages/one/main.odin", "package one\n\nValue :: struct {\n    value: int\n}\n")
    write_synthetic_file(t, repo, "packages/two/main.odin", "package two\n\nValue :: struct {\n    value: int\n}\n")
    write_synthetic_file(t, repo, "src/imports.odin", "package src\n\nimport one \"../packages/one\"\n")
    scope_source := "package src\n\nFIXTURE_SCHEMA_VERSION :: 1\n\nFixture :: struct {\n    value: one.Value\n}\n"
    write_synthetic_file(t, repo, "src/main.odin", scope_source)
    scope_manifest, scope_diagnostics, scope_ok := build_synthetic(repo)
    testing.expect(t, !scope_ok)
    testing.expect(t, scope_manifest == "")
    testing.expect(t, strings.contains(scope_diagnostics, "unknown import alias one"))

    path_source := fixture_source("    value: ^Missing", "    runtime: int")
    write_synthetic_file(t, repo, "src/main.odin", path_source)
    first, first_diagnostics, first_ok := build_synthetic(repo)
    testing.expect(t, !first_ok)
    testing.expect(t, first == "")
    testing.expect(t, strings.contains(first_diagnostics, "Fixture.value"))
    second_repo, second_repo_ok := make_synthetic_repo(t)
    testing.expect(t, second_repo_ok)
    if !second_repo_ok do return
    defer destroy_synthetic_repo(second_repo)
    write_synthetic_file(t, second_repo, "src/main.odin", path_source)
    second, second_diagnostics, second_ok := build_synthetic(second_repo)
    testing.expect(t, !second_ok)
    testing.expect(t, second == "")
    testing.expect(t, strings.contains(second_diagnostics, "Fixture.value"))
}

@(test)
fixture_schema_same_source_is_byte_identical_across_paths :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    first_repo, first_repo_ok := make_synthetic_repo(t)
    testing.expect(t, first_repo_ok)
    if !first_repo_ok do return
    defer destroy_synthetic_repo(first_repo)
    second_repo, second_repo_ok := make_synthetic_repo(t)
    testing.expect(t, second_repo_ok)
    if !second_repo_ok do return
    defer destroy_synthetic_repo(second_repo)

    source := fixture_source("    persisted: int", "    runtime: int")
    write_synthetic_file(t, first_repo, "src/main.odin", source)
    write_synthetic_file(t, second_repo, "src/main.odin", source)
    first, first_diagnostics, first_ok := build_synthetic(first_repo)
    second, second_diagnostics, second_ok := build_synthetic(second_repo)
    testing.expect(t, first_ok && second_ok)
    testing.expect(t, first_diagnostics == "" && second_diagnostics == "")
    testing.expect(t, first == second)
    testing.expect(t, !strings.contains(first, first_repo.root))
    testing.expect(t, !strings.contains(first, second_repo.root))
}
