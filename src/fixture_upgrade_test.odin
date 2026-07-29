package main

import fixture_file "../packages/fixture_file"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

when ODIN_TEST {
    Fixture_Upgrade_Test_Report :: struct {
        paths:   [dynamic]string,
        results: [dynamic]Fixture_Upgrade_Result,
    }

    fixture_upgrade_test_report :: proc(data: rawptr, path: string, result: Fixture_Upgrade_Result, _: bool) {
        report := cast(^Fixture_Upgrade_Test_Report)data
        owned_path, allocation_error := strings.clone(path, context.allocator)
        if allocation_error != nil do return
        appended_path, path_error := append_elem(&report.paths, owned_path)
        if path_error != nil || appended_path != 1 {
            delete(owned_path)
            return
        }
        _, _ = append_elem(&report.results, result)
    }

    fixture_upgrade_test_report_destroy :: proc(report: ^Fixture_Upgrade_Test_Report) {
        if report == nil do return
        for path in report.paths do delete(path)
        delete(report.paths)
        delete(report.results)
        report^ = {}
    }

    fixture_upgrade_test_directory :: proc(t: ^testing.T) -> (string, bool) {
        directory, directory_error := os.make_directory_temp("", "adriatic-fixture-upgrade-*", context.allocator)
        testing.expect(t, directory_error == nil)
        return directory, directory_error == nil
    }

    fixture_upgrade_test_directory_destroy :: proc(directory: string) {
        if len(directory) == 0 do return
        _ = os.remove_all(directory)
        delete(directory)
    }

    fixture_upgrade_test_read :: proc(t: ^testing.T, path: string) -> ([]byte, bool) {
        data, read_error := os.read_entire_file(path, context.allocator)
        testing.expect(t, read_error == nil)
        return data, read_error == nil
    }

    fixture_upgrade_test_expect_file :: proc(t: ^testing.T, path: string, expected: []byte) {
        actual, read_ok := fixture_upgrade_test_read(t, path)
        if !read_ok do return
        defer delete(actual)
        testing.expect(t, fixture_codec_test_bytes_equal(actual, expected))
    }

    fixture_upgrade_test_write :: proc(t: ^testing.T, path: string, data: []byte) -> bool {
        write_error := os.write_entire_file(path, data)
        testing.expect(t, write_error == nil)
        return write_error == nil
    }

    @(test)
    fixture_upgrade_file_dry_run_current_and_historical_are_deterministic :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        directory, directory_ok := fixture_upgrade_test_directory(t)
        if !directory_ok do return
        defer fixture_upgrade_test_directory_destroy(directory)
        historical_path := fmt.tprintf("%s/playground.anything", directory)
        current_path := fmt.tprintf("%s/current.fixture", directory)

        historical := fixture_editor_test_v1_container(t)
        current := fixture_editor_test_current_container(t)
        testing.expect(t, historical != nil && current != nil)
        if historical == nil || current == nil {
            delete(historical)
            delete(current)
            return
        }
        defer delete(historical)
        defer delete(current)
        historical_snapshot := fixture_codec_test_copy(historical)
        current_snapshot := fixture_codec_test_copy(current)
        defer delete(historical_snapshot)
        defer delete(current_snapshot)
        if !fixture_upgrade_test_write(t, historical_path, historical) ||
           !fixture_upgrade_test_write(t, current_path, current) {
            return
        }

        dry_result, dry_error, dry_ok := fixture_upgrade_file(historical_path, true)
        testing.expect(
            t,
            dry_ok &&
            dry_error.kind == .None &&
            dry_result.source_version == 1 &&
            dry_result.target_version == FIXTURE_SCHEMA_VERSION &&
            dry_result.changed,
        )
        fixture_upgrade_error_dispose(&dry_error)
        fixture_upgrade_test_expect_file(t, historical_path, historical_snapshot)

        migrated_result, migrated_error, migrated_ok := fixture_upgrade_file(historical_path, false)
        testing.expect(t, migrated_ok && migrated_error.kind == .None && migrated_result.changed)
        fixture_upgrade_error_dispose(&migrated_error)
        if !migrated_ok do return

        migrated, migrated_read_ok := fixture_upgrade_test_read(t, historical_path)
        if !migrated_read_ok do return
        defer delete(migrated)
        migrated_view, migrated_container_error, migrated_container_ok := fixture_file.fixture_container_decode(
            migrated,
        )
        testing.expect(
            t,
            migrated_container_ok &&
            migrated_container_error.kind == .None &&
            migrated_view.schema_version == u32(FIXTURE_SCHEMA_VERSION),
        )
        decoded, decoded_error, decoded_ok := fixture_codec_decode(migrated)
        testing.expect(t, decoded_ok && decoded_error.kind == .None)
        fixture_codec_error_dispose(&decoded_error)
        if decoded_ok {
            testing.expect(
                t,
                decoded.fixture.occupant == .On_Foot &&
                decoded.fixture.project.structures[0].id == 0x1111 &&
                decoded.fixture.story_state.quest.definition_id == "two-island-story" &&
                decoded.fixture.story_state.quest.node_count == 13 &&
                decoded.fixture.story_state.quest.statuses[11] == .Available &&
                decoded.fixture.story_state.quest.revision == 1,
            )
        }
        fixture_migration_result_dispose(&decoded)

        migrated_snapshot := fixture_codec_test_copy(migrated)
        defer delete(migrated_snapshot)
        repeat_result, repeat_error, repeat_ok := fixture_upgrade_file(historical_path, false)
        testing.expect(
            t,
            repeat_ok &&
            repeat_error.kind == .None &&
            repeat_result.source_version == FIXTURE_SCHEMA_VERSION &&
            !repeat_result.changed,
        )
        fixture_upgrade_error_dispose(&repeat_error)
        fixture_upgrade_test_expect_file(t, historical_path, migrated_snapshot)

        current_result, current_error, current_ok := fixture_upgrade_file(current_path, false)
        testing.expect(
            t,
            current_ok &&
            current_error.kind == .None &&
            current_result.source_version == FIXTURE_SCHEMA_VERSION &&
            !current_result.changed,
        )
        fixture_upgrade_error_dispose(&current_error)
        fixture_upgrade_test_expect_file(t, current_path, current_snapshot)
    }

    @(test)
    fixture_upgrade_directory_is_recursive_sorted_and_ignores_other_files :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        directory, directory_ok := fixture_upgrade_test_directory(t)
        if !directory_ok do return
        defer fixture_upgrade_test_directory_destroy(directory)
        first_directory := fmt.tprintf("%s/a", directory)
        nested_directory := fmt.tprintf("%s/a/nested", directory)
        testing.expect(t, os.make_directory_all(nested_directory) == nil)
        current_path := fmt.tprintf("%s/current.fixture", first_directory)
        v4_path := fmt.tprintf("%s/m.fixture", nested_directory)
        v1_path := fmt.tprintf("%s/z.fixture", directory)
        unrelated_path := fmt.tprintf("%s/notes.txt", directory)
        loop_path := fmt.tprintf("%s/loop", first_directory)
        link_fixture_path := fmt.tprintf("%s/link.fixture", first_directory)

        current := fixture_editor_test_current_container(t)
        v1 := fixture_editor_test_v1_container(t)
        v4, v4_ok := fixture_codec_test_historical_container(t, 4)
        testing.expect(t, current != nil && v1 != nil && v4_ok)
        if current == nil || v1 == nil || !v4_ok {
            delete(current)
            delete(v1)
            delete(v4)
            return
        }
        defer delete(current)
        defer delete(v1)
        defer delete(v4)
        current_snapshot := fixture_codec_test_copy(current)
        v1_snapshot := fixture_codec_test_copy(v1)
        v4_snapshot := fixture_codec_test_copy(v4)
        unrelated_text: string = "leave me alone"
        unrelated := transmute([]byte)unrelated_text
        defer delete(current_snapshot)
        defer delete(v1_snapshot)
        defer delete(v4_snapshot)
        if !fixture_upgrade_test_write(t, current_path, current) ||
           !fixture_upgrade_test_write(t, v4_path, v4) ||
           !fixture_upgrade_test_write(t, v1_path, v1) ||
           !fixture_upgrade_test_write(t, unrelated_path, unrelated) {
            return
        }
        testing.expect(t, os.symlink(directory, loop_path) == nil)
        testing.expect(t, os.symlink(unrelated_path, link_fixture_path) == nil)

        dry_report: Fixture_Upgrade_Test_Report
        defer fixture_upgrade_test_report_destroy(&dry_report)
        dry_summary, dry_error, dry_ok := fixture_upgrade_path(
            directory,
            true,
            fixture_upgrade_test_report,
            rawptr(&dry_report),
        )
        testing.expect(
            t,
            dry_ok &&
            dry_error.kind == .None &&
            dry_summary.total == 3 &&
            dry_summary.changed == 2 &&
            dry_summary.current == 1 &&
            len(dry_report.paths) == 3 &&
            len(dry_report.results) == 3,
        )
        fixture_upgrade_error_dispose(&dry_error)
        if len(dry_report.paths) == 3 {
            testing.expect(
                t,
                strings.has_suffix(dry_report.paths[0], "/a/current.fixture") &&
                strings.has_suffix(dry_report.paths[1], "/a/nested/m.fixture") &&
                strings.has_suffix(dry_report.paths[2], "/z.fixture") &&
                dry_report.results[0].source_version == FIXTURE_SCHEMA_VERSION &&
                dry_report.results[1].source_version == 4 &&
                dry_report.results[2].source_version == 1,
            )
        }
        fixture_upgrade_test_expect_file(t, current_path, current_snapshot)
        fixture_upgrade_test_expect_file(t, v4_path, v4_snapshot)
        fixture_upgrade_test_expect_file(t, v1_path, v1_snapshot)
        fixture_upgrade_test_expect_file(t, unrelated_path, unrelated)

        real_report: Fixture_Upgrade_Test_Report
        defer fixture_upgrade_test_report_destroy(&real_report)
        real_summary, real_error, real_ok := fixture_upgrade_path(
            directory,
            false,
            fixture_upgrade_test_report,
            rawptr(&real_report),
        )
        testing.expect(
            t,
            real_ok &&
            real_error.kind == .None &&
            real_summary.total == 3 &&
            real_summary.changed == 2 &&
            real_summary.current == 1 &&
            len(real_report.paths) == 3,
        )
        fixture_upgrade_error_dispose(&real_error)
        fixture_upgrade_test_expect_file(t, current_path, current_snapshot)
        fixture_upgrade_test_expect_file(t, unrelated_path, unrelated)

        rerun_summary, rerun_error, rerun_ok := fixture_upgrade_path(directory, false)
        testing.expect(
            t,
            rerun_ok &&
            rerun_error.kind == .None &&
            rerun_summary.total == 3 &&
            rerun_summary.changed == 0 &&
            rerun_summary.current == 3,
        )
        fixture_upgrade_error_dispose(&rerun_error)

        cli_args := [4]string{"adriatic", "fixture-upgrade", "--dry-run", directory}
        handled, cli_ok := adriatic_cli(cli_args[:])
        testing.expect(t, handled && cli_ok)
    }

    @(test)
    fixture_upgrade_failures_preserve_targets_and_release_ownership :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        directory, directory_ok := fixture_upgrade_test_directory(t)
        if !directory_ok do return
        defer fixture_upgrade_test_directory_destroy(directory)
        path := fmt.tprintf("%s/hostile.fixture", directory)
        temporary_path := fmt.tprintf("%s/hostile.fixture.tmp", directory)

        historical := fixture_editor_test_v1_container(t)
        current := fixture_editor_test_current_container(t)
        testing.expect(t, historical != nil && current != nil)
        if historical == nil || current == nil {
            delete(historical)
            delete(current)
            return
        }
        defer delete(historical)
        defer delete(current)
        historical_snapshot := fixture_codec_test_copy(historical)
        defer delete(historical_snapshot)

        failures := [?]Fixture_Editor_Store_Test_Failure{.Partial_Then_Write, .Zero_Write, .Sync, .Close, .Rename}
        store_kinds := [?]Fixture_Editor_Store_Error_Kind {
            .Write_Temporary,
            .Write_Temporary,
            .Sync_Temporary,
            .Close_Temporary,
            .Rename_Target,
        }
        for failure, index in failures {
            testing.expect(t, fixture_upgrade_test_write(t, path, historical))
            _ = os.remove(temporary_path)
            state := Fixture_Editor_Store_Test_State {
                failure = failure,
            }
            options := Fixture_Upgrade_Options {
                store = fixture_editor_store_test_options(&state, temporary_path),
            }
            _, error, ok := fixture_upgrade_file_with_options(path, false, options)
            testing.expect(
                t,
                !ok && error.kind == .Store && error.path == path && error.store.kind == store_kinds[index],
            )
            fixture_upgrade_test_expect_file(t, path, historical_snapshot)
            testing.expect(t, !os.exists(temporary_path))
            fixture_upgrade_error_dispose(&error)
            fixture_upgrade_error_dispose(&error)
        }

        corrupt := fixture_codec_test_copy(current)
        corrupt[len(corrupt) - 1] ~= 0xff
        defer delete(corrupt)
        testing.expect(t, fixture_upgrade_test_write(t, path, corrupt))
        _, corrupt_error, corrupt_ok := fixture_upgrade_file(path, false)
        testing.expect(
            t,
            !corrupt_ok && corrupt_error.kind == .Container && corrupt_error.container.kind == .Checksum_Mismatch,
        )
        fixture_upgrade_test_expect_file(t, path, corrupt)
        fixture_upgrade_error_dispose(&corrupt_error)
        fixture_upgrade_error_dispose(&corrupt_error)

        future_payload := []byte{1}
        future, future_container_error, future_ok := fixture_file.fixture_container_encode(
            future_payload,
            u32(FIXTURE_SCHEMA_VERSION + 1),
            alloc = context.allocator,
        )
        testing.expect(t, future_ok && future_container_error.kind == .None)
        if future_ok {
            defer delete(future)
            testing.expect(t, fixture_upgrade_test_write(t, path, future))
            _, future_error, upgraded := fixture_upgrade_file(path, false)
            testing.expect(t, !upgraded && future_error.kind == .Codec && future_error.codec.kind == .Schema_Mismatch)
            fixture_upgrade_test_expect_file(t, path, future)
            fixture_upgrade_error_dispose(&future_error)
        }

        invalid_payload, invalid_payload_ok := fixture_codec_test_invalid_historical_payload(t)
        testing.expect(t, invalid_payload_ok)
        if invalid_payload_ok {
            defer delete(invalid_payload)
            invalid, invalid_container_error, invalid_container_ok := fixture_file.fixture_container_encode(
                invalid_payload,
                1,
                alloc = context.allocator,
            )
            testing.expect(t, invalid_container_ok && invalid_container_error.kind == .None)
            if invalid_container_ok {
                defer delete(invalid)
                testing.expect(t, fixture_upgrade_test_write(t, path, invalid))
                _, invalid_error, upgraded := fixture_upgrade_file(path, false)
                testing.expect(
                    t,
                    !upgraded &&
                    invalid_error.kind == .Codec &&
                    invalid_error.codec.kind == .Migration &&
                    invalid_error.codec.migration.kind == .Step_Failure &&
                    invalid_error.codec.migration.change_id == FIXTURE_MIGRATION_V0001_TERRAIN_STRUCTURES_ID,
                )
                fixture_upgrade_test_expect_file(t, path, invalid)
                fixture_upgrade_error_dispose(&invalid_error)
            }
        }

        testing.expect(t, fixture_upgrade_test_write(t, path, historical))
        read_state := Fixture_Editor_Store_Test_State {
            failure = .Read,
        }
        read_options := Fixture_Upgrade_Options {
            store = fixture_editor_store_test_options(&read_state, temporary_path),
        }
        _, read_error, read_ok := fixture_upgrade_file_with_options(path, false, read_options)
        testing.expect(t, !read_ok && read_error.kind == .Read_Source && read_error.path == path)
        fixture_upgrade_test_expect_file(t, path, historical_snapshot)
        fixture_upgrade_error_dispose(&read_error)

        missing_path := fmt.tprintf("%s/missing", directory)
        _, traverse_error, traverse_ok := fixture_upgrade_path(missing_path, false)
        testing.expect(t, !traverse_ok && traverse_error.kind == .Stat_Source && traverse_error.path == missing_path)
        fixture_upgrade_error_dispose(&traverse_error)

        _, nil_error, nil_ok := fixture_upgrade_file(path, false, {})
        testing.expect(t, !nil_ok && nil_error.kind == .Invalid_Argument)
        fixture_upgrade_error_dispose(&nil_error)
        fixture_upgrade_error_dispose(&nil_error)

        for fail_at in 0 ..< 4 {
            testing.expect(t, fixture_upgrade_test_write(t, path, historical))
            state := fixture_migration_test_allocator_state {
                base    = runtime.default_allocator(),
                fail_at = fail_at,
            }
            allocator := fixture_migration_test_allocator(&state)
            _, error, ok := fixture_upgrade_file(path, false, allocator)
            testing.expect(
                t,
                !ok &&
                (error.kind == .Out_Of_Memory || error.kind == .Codec || error.kind == .Encode) &&
                state.allocation_calls >= fail_at + 1,
            )
            fixture_upgrade_test_expect_file(t, path, historical_snapshot)
            fixture_upgrade_error_dispose(&error)
            fixture_upgrade_error_dispose(&error)
            testing.expect(t, state.outstanding == 0)
        }
    }
}
