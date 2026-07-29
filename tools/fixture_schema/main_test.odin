package main

import fixture_schema "../../packages/fixture_schema"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

when ODIN_TEST {

    migration_candidate_test_write :: proc(t: ^testing.T, path, source: string) -> bool {
        if err := os.make_directory_all(os.dir(path)); err != nil && err != .Exist {
            testing.expect(t, false)
            return false
        }
        ok := os.write_entire_file(path, source) == nil
        testing.expect(t, ok)
        return ok
    }

    migration_candidate_test_build :: proc(
        t: ^testing.T,
        repo_root, collection_root: string,
    ) -> (
        manifest: string,
        version: int,
        ok: bool,
    ) {
        diagnostics: string
        manifest, version, ok, diagnostics = fixture_schema.build_manifest_report(repo_root, collection_root)
        testing.expect(t, ok && diagnostics == "")
        return
    }

    migration_candidate_test_report :: proc(
        t: ^testing.T,
        frozen, candidate: []byte,
        from_version, to_version: int,
        expected_id: string,
    ) {
        report, error, ok := fixture_schema.schema_diff_build_report(
            frozen,
            candidate,
            from_version,
            to_version,
            context.allocator,
        )
        testing.expect(t, ok && error.kind == .None)
        if !ok {
            fixture_schema.schema_diff_error_dispose(&error)
            return
        }
        defer fixture_schema.schema_diff_report_dispose(&report)

        testing.expect(t, report.from_version == from_version && report.to_version == to_version)
        testing.expect(t, len(report.changes) == 1)
        if len(report.changes) != 1 {
            fixture_schema.schema_diff_error_dispose(&error)
            return
        }
        change := report.changes[0]
        testing.expect(t, change.id == expected_id)
        testing.expect(t, change.class == .State && change.policy == .Script_Required)
        state_count, supporting_count := fixture_schema.schema_diff_report_counts(&report)
        testing.expect(t, state_count == 1 && supporting_count == 0)

        rendered, render_ok := fixture_schema.schema_diff_report_render(&report, context.allocator)
        testing.expect(t, render_ok)
        if render_ok {
            rendered_again, rendered_again_ok := fixture_schema.schema_diff_report_render(&report, context.allocator)
            testing.expect(t, rendered_again_ok && rendered_again == rendered)
            delete(rendered)
            if rendered_again_ok do delete(rendered_again)
        }
        fixture_schema.schema_diff_error_dispose(&error)
    }

    @(test)
    migration_candidate_prefers_frozen_target_and_live_draft :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        repo_root, root_error := os.make_directory_temp("", "fixture-candidate-*", context.allocator)
        testing.expect(t, root_error == nil)
        if root_error != nil do return
        defer os.remove_all(repo_root)

        collection_root := fmt.tprintf("%s/zelda-engine/packages", repo_root)
        source_path := fmt.tprintf("%s/src/fixture.odin", repo_root)
        testing.expect(t, os.make_directory_all(collection_root) == nil)

        v1_source :=
            "package src\n\n" +
            "FIXTURE_SCHEMA_VERSION :: 1\n\n" +
            "Fixture :: struct {\n" +
            "    value: u8,\n" +
            "}\n"
        v2_source :=
            "package src\n\n" +
            "FIXTURE_SCHEMA_VERSION :: 2\n\n" +
            "Fixture :: struct {\n" +
            "    value: u8,\n" +
            "    target: u16,\n" +
            "}\n"
        live_v2_source :=
            "package src\n\n" +
            "FIXTURE_SCHEMA_VERSION :: 2\n\n" +
            "Fixture :: struct {\n" +
            "    value: u8,\n" +
            "    target: u16,\n" +
            "    draft: u32,\n" +
            "}\n"

        testing.expect(t, migration_candidate_test_write(t, source_path, v1_source))
        v1_manifest, v1_version, v1_ok := migration_candidate_test_build(t, repo_root, collection_root)
        testing.expect(t, v1_version == 1)
        if !v1_ok do return
        v1_frozen, v1_clone_error := strings.clone(v1_manifest, context.allocator)
        testing.expect(t, v1_clone_error == nil)
        if v1_clone_error != nil do return
        defer delete(v1_frozen)
        v1_path := fixture_schema.manifest_path(repo_root, 1)
        testing.expect(t, migration_candidate_test_write(t, v1_path, v1_frozen))

        testing.expect(t, migration_candidate_test_write(t, source_path, v2_source))
        v2_manifest, v2_version, v2_ok := migration_candidate_test_build(t, repo_root, collection_root)
        testing.expect(t, v2_version == 2)
        if !v2_ok do return
        v2_frozen, v2_clone_error := strings.clone(v2_manifest, context.allocator)
        testing.expect(t, v2_clone_error == nil)
        if v2_clone_error != nil do return
        defer delete(v2_frozen)
        v2_path := fixture_schema.manifest_path(repo_root, 2)
        testing.expect(t, migration_candidate_test_write(t, v2_path, v2_frozen))

        testing.expect(t, migration_candidate_test_write(t, source_path, live_v2_source))
        live_manifest, live_version, live_ok := migration_candidate_test_build(t, repo_root, collection_root)
        testing.expect(t, live_version == 2)
        if !live_ok do return
        live_draft, live_clone_error := strings.clone(live_manifest, context.allocator)
        testing.expect(t, live_clone_error == nil)
        if live_clone_error != nil do return
        defer delete(live_draft)
        testing.expect(t, live_draft != v2_frozen)

        frozen_candidate, frozen_ok := migration_candidate_data(repo_root, collection_root, 1, 2)
        testing.expect(t, frozen_ok && string(frozen_candidate) == v2_frozen)
        if !frozen_ok do return
        defer delete(frozen_candidate)
        migration_candidate_test_report(
            t,
            transmute([]byte)v1_frozen,
            frozen_candidate,
            1,
            2,
            "field-add:adriatic:src.Fixture.target",
        )

        live_candidate, live_candidate_ok := migration_candidate_data(repo_root, collection_root, 2, 3)
        testing.expect(t, live_candidate_ok && string(live_candidate) == live_draft)
        if !live_candidate_ok do return
        defer delete(live_candidate)
        migration_candidate_test_report(
            t,
            transmute([]byte)v2_frozen,
            live_candidate,
            2,
            3,
            "field-add:adriatic:src.Fixture.draft",
        )

        malformed := "this is not a fixture manifest\n"
        testing.expect(t, migration_candidate_test_write(t, v2_path, malformed))
        malformed_candidate, malformed_ok := migration_candidate_data(repo_root, collection_root, 1, 2)
        testing.expect(t, malformed_ok && string(malformed_candidate) == malformed)
        if !malformed_ok do return
        defer delete(malformed_candidate)
        report, error, report_ok := fixture_schema.schema_diff_build_report(
            transmute([]byte)v1_frozen,
            malformed_candidate,
            1,
            2,
            context.allocator,
        )
        testing.expect(t, !report_ok && error.kind != .None)
        if report_ok do fixture_schema.schema_diff_report_dispose(&report)
        fixture_schema.schema_diff_error_dispose(&error)

        v3_source :=
            "package src\n\n" +
            "FIXTURE_SCHEMA_VERSION :: 3\n\n" +
            "Fixture :: struct {\n" +
            "    value: u8,\n" +
            "}\n"
        v4_source :=
            "package src\n\n" +
            "FIXTURE_SCHEMA_VERSION :: 4\n\n" +
            "Fixture :: struct {\n" +
            "    value: u8,\n" +
            "    target_v4: u16,\n" +
            "}\n"
        live_v5_source :=
            "package src\n\n" +
            "FIXTURE_SCHEMA_VERSION :: 5\n\n" +
            "Fixture :: struct {\n" +
            "    value: u8,\n" +
            "    target_v4: u16,\n" +
            "    draft_v5: u32,\n" +
            "}\n"

        testing.expect(t, migration_candidate_test_write(t, source_path, v3_source))
        v3_manifest, v3_version, v3_ok := migration_candidate_test_build(t, repo_root, collection_root)
        testing.expect(t, v3_version == 3)
        if !v3_ok do return
        v3_frozen, v3_clone_error := strings.clone(v3_manifest, context.allocator)
        testing.expect(t, v3_clone_error == nil)
        if v3_clone_error != nil do return
        defer delete(v3_frozen)
        v3_path := fixture_schema.manifest_path(repo_root, 3)
        testing.expect(t, migration_candidate_test_write(t, v3_path, v3_frozen))

        testing.expect(t, migration_candidate_test_write(t, source_path, v4_source))
        v4_manifest, v4_version, v4_ok := migration_candidate_test_build(t, repo_root, collection_root)
        testing.expect(t, v4_version == 4)
        if !v4_ok do return
        v4_frozen, v4_clone_error := strings.clone(v4_manifest, context.allocator)
        testing.expect(t, v4_clone_error == nil)
        if v4_clone_error != nil do return
        defer delete(v4_frozen)
        v4_path := fixture_schema.manifest_path(repo_root, 4)
        testing.expect(t, migration_candidate_test_write(t, v4_path, v4_frozen))

        testing.expect(t, migration_candidate_test_write(t, source_path, live_v5_source))
        live_v5_manifest, live_v5_version, live_v5_ok := migration_candidate_test_build(t, repo_root, collection_root)
        testing.expect(t, live_v5_version == 5)
        if !live_v5_ok do return
        live_v5_draft, live_v5_clone_error := strings.clone(live_v5_manifest, context.allocator)
        testing.expect(t, live_v5_clone_error == nil)
        if live_v5_clone_error != nil do return
        defer delete(live_v5_draft)

        frozen_v4_candidate, frozen_v4_ok := migration_candidate_data(repo_root, collection_root, 3, 4)
        testing.expect(t, frozen_v4_ok && string(frozen_v4_candidate) == v4_frozen)
        if !frozen_v4_ok do return
        defer delete(frozen_v4_candidate)
        migration_candidate_test_report(
            t,
            transmute([]byte)v3_frozen,
            frozen_v4_candidate,
            3,
            4,
            "field-add:adriatic:src.Fixture.target_v4",
        )

        live_v5_candidate, live_v5_candidate_ok := migration_candidate_data(repo_root, collection_root, 4, 5)
        testing.expect(t, live_v5_candidate_ok && string(live_v5_candidate) == live_v5_draft)
        if !live_v5_candidate_ok do return
        defer delete(live_v5_candidate)
        migration_candidate_test_report(
            t,
            transmute([]byte)v4_frozen,
            live_v5_candidate,
            4,
            5,
            "field-add:adriatic:src.Fixture.draft_v5",
        )

        v5_path := fixture_schema.manifest_path(repo_root, 5)
        testing.expect(t, migration_candidate_test_write(t, v5_path, live_v5_draft))
        changed_live_v5_source :=
            "package src\n\n" +
            "FIXTURE_SCHEMA_VERSION :: 5\n\n" +
            "Fixture :: struct {\n" +
            "    value: u8,\n" +
            "    target_v4: u16,\n" +
            "    draft_v5: u32,\n" +
            "    later_draft_v5: u64,\n" +
            "}\n"
        testing.expect(t, migration_candidate_test_write(t, source_path, changed_live_v5_source))
        changed_live_v5_manifest, changed_live_v5_version, changed_live_v5_ok := migration_candidate_test_build(
            t,
            repo_root,
            collection_root,
        )
        testing.expect(
            t,
            changed_live_v5_ok && changed_live_v5_version == 5 && changed_live_v5_manifest != live_v5_draft,
        )
        if !changed_live_v5_ok do return
        defer delete(changed_live_v5_manifest)

        frozen_v5_candidate, frozen_v5_ok := migration_candidate_data(repo_root, collection_root, 4, 5)
        testing.expect(t, frozen_v5_ok && string(frozen_v5_candidate) == live_v5_draft)
        if !frozen_v5_ok do return
        defer delete(frozen_v5_candidate)
        migration_candidate_test_report(
            t,
            transmute([]byte)v4_frozen,
            frozen_v5_candidate,
            4,
            5,
            "field-add:adriatic:src.Fixture.draft_v5",
        )

        testing.expect(t, migration_candidate_test_write(t, v5_path, malformed))
        malformed_v5_candidate, malformed_v5_ok := migration_candidate_data(repo_root, collection_root, 4, 5)
        testing.expect(t, malformed_v5_ok && string(malformed_v5_candidate) == malformed)
        if !malformed_v5_ok do return
        defer delete(malformed_v5_candidate)
        malformed_v5_report, malformed_v5_error, malformed_v5_report_ok := fixture_schema.schema_diff_build_report(
            transmute([]byte)v4_frozen,
            malformed_v5_candidate,
            4,
            5,
            context.allocator,
        )
        testing.expect(t, !malformed_v5_report_ok && malformed_v5_error.kind != .None)
        if malformed_v5_report_ok do fixture_schema.schema_diff_report_dispose(&malformed_v5_report)
        fixture_schema.schema_diff_error_dispose(&malformed_v5_error)

        testing.expect(t, os.remove(v5_path) == nil)
        testing.expect(t, os.make_directory(v5_path) == nil)
        unreadable_v5_candidate, unreadable_v5_ok := migration_candidate_data(repo_root, collection_root, 4, 5)
        testing.expect(t, !unreadable_v5_ok && len(unreadable_v5_candidate) == 0)
        delete(unreadable_v5_candidate)
        testing.expect(t, os.remove_all(v5_path) == nil)
        testing.expect(t, migration_candidate_test_write(t, v5_path, live_v5_draft))

        testing.expect(t, migration_candidate_test_write(t, v4_path, malformed))
        malformed_v4_candidate, malformed_v4_ok := migration_candidate_data(repo_root, collection_root, 3, 4)
        testing.expect(t, malformed_v4_ok && string(malformed_v4_candidate) == malformed)
        if !malformed_v4_ok do return
        defer delete(malformed_v4_candidate)
        malformed_v4_report, malformed_v4_error, malformed_v4_report_ok := fixture_schema.schema_diff_build_report(
            transmute([]byte)v3_frozen,
            malformed_v4_candidate,
            3,
            4,
            context.allocator,
        )
        testing.expect(t, !malformed_v4_report_ok && malformed_v4_error.kind != .None)
        if malformed_v4_report_ok do fixture_schema.schema_diff_report_dispose(&malformed_v4_report)
        fixture_schema.schema_diff_error_dispose(&malformed_v4_error)
        testing.expect(t, migration_candidate_test_write(t, v4_path, v4_frozen))

        scaffold_target := migration_scaffold_target_path(repo_root, 3, 4)
        testing.expect(t, !os.exists(scaffold_target))
        testing.expect(t, migration_scaffold_command("migration-scaffold", repo_root, collection_root, 3, 4))
        first_scaffold, first_scaffold_error := os.read_entire_file(scaffold_target, context.allocator)
        testing.expect(t, first_scaffold_error == nil)
        if first_scaffold_error != nil do return
        defer delete(first_scaffold)
        first_info, first_info_error := os.stat(scaffold_target, context.allocator)
        testing.expect(t, first_info_error == nil)
        if first_info_error != nil do return
        defer os.file_info_delete(first_info, context.allocator)

        testing.expect(t, migration_scaffold_command("migration-scaffold", repo_root, collection_root, 3, 4))
        second_scaffold, second_scaffold_error := os.read_entire_file(scaffold_target, context.allocator)
        testing.expect(t, second_scaffold_error == nil)
        if second_scaffold_error != nil do return
        defer delete(second_scaffold)
        second_info, second_info_error := os.stat(scaffold_target, context.allocator)
        testing.expect(t, second_info_error == nil)
        if second_info_error != nil do return
        defer os.file_info_delete(second_info, context.allocator)
        testing.expect(t, string(second_scaffold) == string(first_scaffold))
        testing.expect(
            t,
            second_info.inode == first_info.inode &&
            second_info.size == first_info.size &&
            second_info.modification_time == first_info.modification_time,
        )
        testing.expect(t, migration_scaffold_command("migration-scaffold-check", repo_root, collection_root, 3, 4))

        malformed_scaffold := "package main {\n"
        testing.expect(t, migration_candidate_test_write(t, scaffold_target, malformed_scaffold))
        testing.expect(t, !migration_scaffold_command("migration-scaffold", repo_root, collection_root, 3, 4))
        testing.expect(t, !migration_scaffold_command("migration-scaffold-check", repo_root, collection_root, 3, 4))
        unchanged_malformed, unchanged_malformed_error := os.read_entire_file(scaffold_target, context.allocator)
        testing.expect(t, unchanged_malformed_error == nil && string(unchanged_malformed) == malformed_scaffold)
        if unchanged_malformed_error == nil do delete(unchanged_malformed)

        testing.expect(t, os.remove(scaffold_target) == nil)
        testing.expect(t, !migration_scaffold_command("migration-scaffold-check", repo_root, collection_root, 3, 4))
        testing.expect(t, !os.exists(scaffold_target))
    }

}
