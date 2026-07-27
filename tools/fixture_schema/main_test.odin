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
    }

}
