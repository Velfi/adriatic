package main

import fixture_file "../packages/fixture_file"
import vehicles "../packages/vehicles"
import "base:runtime"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

when ODIN_TEST {
    Fixture_Editor_Store_Test_Failure :: enum {
        None,
        Partial,
        Partial_Then_Write,
        Zero_Write,
        Sync,
        Close,
        Rename,
        Read,
    }

    Fixture_Editor_Store_Test_State :: struct {
        failure:     Fixture_Editor_Store_Test_Failure,
        write_calls: int,
    }

    fixture_editor_store_test_aux_mix :: proc(_: rawptr, _: []f32) {  }

    fixture_editor_store_test_open :: proc(_: rawptr, path: string) -> (^os.File, os.Error) {
        return os.open(path, {.Write, .Create, .Excl}, os.Permissions_Default_File)
    }

    fixture_editor_store_test_write :: proc(data: rawptr, file: ^os.File, bytes: []byte) -> (int, os.Error) {
        state := cast(^Fixture_Editor_Store_Test_State)data
        state.write_calls += 1
        switch state.failure {
        case .Partial:
            if len(bytes) > 1 do return os.write(file, bytes[:max(1, len(bytes) / 3)])
        case .Partial_Then_Write:
            if state.write_calls == 1 && len(bytes) > 1 {
                return os.write(file, bytes[:max(1, len(bytes) / 2)])
            }
            return 0, .Invalid_File
        case .Zero_Write:
            return 0, nil
        case .None, .Sync, .Close, .Rename, .Read:
        }
        return os.write(file, bytes)
    }

    fixture_editor_store_test_sync :: proc(data: rawptr, file: ^os.File) -> os.Error {
        state := cast(^Fixture_Editor_Store_Test_State)data
        if state.failure == .Sync do return .Invalid_File
        return os.sync(file)
    }

    fixture_editor_store_test_close :: proc(data: rawptr, file: ^os.File) -> os.Error {
        state := cast(^Fixture_Editor_Store_Test_State)data
        close_error := os.close(file)
        if state.failure == .Close do return .Invalid_File
        return close_error
    }

    fixture_editor_store_test_rename :: proc(data: rawptr, old_path, new_path: string) -> os.Error {
        state := cast(^Fixture_Editor_Store_Test_State)data
        if state.failure == .Rename do return .Invalid_File
        return os.rename(old_path, new_path)
    }

    fixture_editor_store_test_remove :: proc(_: rawptr, path: string) -> os.Error {
        return os.remove(path)
    }

    fixture_editor_store_test_read :: proc(data: rawptr, path: string, alloc: mem.Allocator) -> ([]byte, os.Error) {
        state := cast(^Fixture_Editor_Store_Test_State)data
        if state.failure == .Read do return nil, .Invalid_File
        return os.read_entire_file(path, alloc)
    }

    fixture_editor_store_test_options :: proc(
        state: ^Fixture_Editor_Store_Test_State,
        temporary_path: string,
    ) -> Fixture_Editor_Store_Options {
        return {
            operations = {
                data = rawptr(state),
                open_excl = fixture_editor_store_test_open,
                write = fixture_editor_store_test_write,
                sync = fixture_editor_store_test_sync,
                close = fixture_editor_store_test_close,
                rename = fixture_editor_store_test_rename,
                remove = fixture_editor_store_test_remove,
                read = fixture_editor_store_test_read,
            },
            temporary_path = temporary_path,
        }
    }

    fixture_editor_store_test_paths :: proc(t: ^testing.T) -> (directory, path, temporary_path: string, ok: bool) {
        directory_error: os.Error
        directory, directory_error = os.make_directory_temp("", "adriatic-fixture-store-*", context.allocator)
        testing.expect(t, directory_error == nil)
        if directory_error != nil do return "", "", "", false
        path_error, temporary_error: mem.Allocator_Error
        path, path_error = strings.concatenate({directory, "/adriatic.fixture"}, context.allocator)
        temporary_path, temporary_error = strings.concatenate({directory, "/adriatic.fixture.tmp"}, context.allocator)
        testing.expect(t, path_error == nil && temporary_error == nil)
        if path_error != nil || temporary_error != nil {
            if len(path) > 0 do delete(path)
            if len(temporary_path) > 0 do delete(temporary_path)
            _ = os.remove_all(directory)
            delete(directory)
            return "", "", "", false
        }
        return directory, path, temporary_path, true
    }

    fixture_editor_store_test_paths_destroy :: proc(directory, path, temporary_path: string) {
        if len(directory) > 0 do _ = os.remove_all(directory)
        if len(path) > 0 do delete(path)
        if len(temporary_path) > 0 do delete(temporary_path)
        if len(directory) > 0 do delete(directory)
    }

    fixture_editor_store_test_bound_editor :: proc(t: ^testing.T) -> (^Editor, bool) {
        data := fixture_editor_test_current_container(t)
        if data == nil do return nil, false
        defer delete(data)
        editor := fixture_editor_test_editor(t)
        error, ok := fixture_editor_load(editor, data)
        testing.expect(t, ok && error.kind == .None)
        fixture_editor_load_error_dispose(&error)
        if !ok {
            fixture_editor_test_destroy(editor)
            return nil, false
        }
        return editor, true
    }

    fixture_editor_store_test_read_bytes :: proc(t: ^testing.T, path: string) -> ([]byte, bool) {
        data, read_error := os.read_entire_file(path, context.allocator)
        testing.expect(t, read_error == nil)
        return data, read_error == nil
    }

    fixture_editor_store_test_expect_sentinel :: proc(t: ^testing.T, path, sentinel: string) {
        stored, read_ok := fixture_editor_store_test_read_bytes(t, path)
        if !read_ok do return
        defer delete(stored)
        testing.expect(t, string(stored) == sentinel)
    }

    @(test)
    fixture_editor_file_round_trip_restores_playground_and_preserves_root_state :: proc(t: ^testing.T) {
        directory, path, temporary_path, paths_ok := fixture_editor_store_test_paths(t)
        if !paths_ok do return
        defer fixture_editor_store_test_paths_destroy(directory, path, temporary_path)

        editor, editor_ok := fixture_editor_store_test_bound_editor(t)
        if !editor_ok do return
        defer fixture_editor_test_destroy(editor)

        vehicles.libellula_mesh_init(&editor.libellula_base_mesh)
        vehicles.libellula_mesh_init(&editor.libellula_mk2_base_mesh)
        vehicles.libellula_mesh_init(&editor.libellula_visual_mesh)
        vehicles.libellula_mesh_init(&editor.libellula_mk2_visual_mesh)
        defer {
            vehicles.libellula_mesh_destroy(&editor.libellula_mk2_visual_mesh)
            vehicles.libellula_mesh_destroy(&editor.libellula_visual_mesh)
            vehicles.libellula_mesh_destroy(&editor.libellula_mk2_base_mesh)
            vehicles.libellula_mesh_destroy(&editor.libellula_base_mesh)
        }
        editor.libellula_base_mesh.vertex_count = 1
        editor.libellula_mk2_base_mesh.vertex_count = 1
        editor.libellula_visual_mesh.vertex_count = 1
        editor.libellula_mk2_visual_mesh.vertex_count = 1
        editor.engine_audio.aux_mix = fixture_editor_store_test_aux_mix

        editor.project.sea_level = 19
        editor.project.structures[0].id = 0x5151
        editor.story_state.romance = .Corresponding
        editor.vehicle_paint_layers[0][0] = 0xc3
        root_snapshot := fixture_editor_test_root_snapshot(editor)
        audio_callback := editor.engine_audio.aux_mix
        base_vertices := raw_data(editor.libellula_base_mesh.vertices)
        base_triangles := raw_data(editor.libellula_base_mesh.triangles)
        visual_vertices := raw_data(editor.libellula_visual_mesh.vertices)
        visual_triangles := raw_data(editor.libellula_visual_mesh.triangles)
        mk2_base_vertices := raw_data(editor.libellula_mk2_base_mesh.vertices)
        mk2_visual_vertices := raw_data(editor.libellula_mk2_visual_mesh.vertices)

        save_error, saved := fixture_editor_save_to_path(editor, path)
        testing.expect(t, saved && save_error.kind == .None)
        fixture_editor_store_error_dispose(&save_error)
        if !saved do return
        testing.expect(t, fixture_lifecycle_test_bound(&editor.fixture, .Car))

        editor.project.sea_level = -7
        editor.project.structures[0].id = 3
        editor.story_state.romance = .Unintroduced
        editor.vehicle_paint_layers[0][0] = 0

        load_error, loaded := fixture_editor_load_from_path(editor, path)
        testing.expect(t, loaded && load_error.kind == .None)
        fixture_editor_store_error_dispose(&load_error)
        if !loaded do return

        testing.expect(t, editor.project.sea_level == 19)
        testing.expect(t, editor.project.structures[0].id == 0x5151)
        testing.expect(t, editor.story_state.romance == .Corresponding)
        testing.expect(t, editor.vehicle_paint_layers[0][0] == 0xc3)
        testing.expect(t, fixture_lifecycle_test_bound(&editor.fixture, .Car))
        testing.expect(t, editor.fixture_owner.fixture == &editor.fixture && editor.fixture_owner.arena != nil)
        testing.expect(t, fixture_editor_test_root_equal(editor, root_snapshot))
        testing.expect(t, editor.engine_audio.aux_mix == audio_callback)
        testing.expect(t, raw_data(editor.libellula_base_mesh.vertices) == base_vertices)
        testing.expect(t, raw_data(editor.libellula_base_mesh.triangles) == base_triangles)
        testing.expect(t, raw_data(editor.libellula_visual_mesh.vertices) == visual_vertices)
        testing.expect(t, raw_data(editor.libellula_visual_mesh.triangles) == visual_triangles)
        testing.expect(t, raw_data(editor.libellula_mk2_base_mesh.vertices) == mk2_base_vertices)
        testing.expect(t, raw_data(editor.libellula_mk2_visual_mesh.vertices) == mk2_visual_vertices)
        for _ in 0 ..< 3 {
            gameplay_physics_begin_frame(editor)
            car_physics_step(editor, .15, .02, false, vehicles.CAR_DRIVE_DEFAULT_SURFACE, 1.0 / 60.0, 0)
        }
        testing.expect(t, editor.gameplay_physics.world != nil && editor.car_physics_vehicle != nil)
    }

    @(test)
    fixture_editor_file_save_is_current_deterministic_and_load_reuses_migrations :: proc(t: ^testing.T) {
        directory, path, temporary_path, paths_ok := fixture_editor_store_test_paths(t)
        if !paths_ok do return
        defer fixture_editor_store_test_paths_destroy(directory, path, temporary_path)

        editor, editor_ok := fixture_editor_store_test_bound_editor(t)
        if !editor_ok do return
        defer fixture_editor_test_destroy(editor)

        first_error, first_saved := fixture_editor_save_to_path(editor, path)
        testing.expect(t, first_saved && first_error.kind == .None)
        fixture_editor_store_error_dispose(&first_error)
        if !first_saved do return
        first, first_ok := fixture_editor_store_test_read_bytes(t, path)
        if !first_ok do return
        defer delete(first)

        second_error, second_saved := fixture_editor_save_to_path(editor, path)
        testing.expect(t, second_saved && second_error.kind == .None)
        fixture_editor_store_error_dispose(&second_error)
        if !second_saved do return
        second, second_ok := fixture_editor_store_test_read_bytes(t, path)
        if !second_ok do return
        defer delete(second)
        testing.expect(t, fixture_codec_test_bytes_equal(first, second))
        view, container_error, container_ok := fixture_file.fixture_container_decode(second)
        testing.expect(t, container_ok && container_error.kind == .None)
        testing.expect(t, view.schema_version == u32(FIXTURE_SCHEMA_VERSION))

        v1 := fixture_editor_test_v1_container(t)
        testing.expect(t, v1 != nil)
        if v1 == nil do return
        defer delete(v1)
        v1_snapshot := fixture_codec_test_copy(v1)
        defer delete(v1_snapshot)
        testing.expect(t, os.write_entire_file(path, v1) == nil)

        root_snapshot := fixture_editor_test_root_snapshot(editor)
        load_error, loaded := fixture_editor_load_from_path(editor, path)
        testing.expect(t, loaded && load_error.kind == .None)
        fixture_editor_store_error_dispose(&load_error)
        if !loaded do return
        testing.expect(t, editor.project.structures[0].id == 0x1111)
        testing.expect(t, editor.fixture_owner.fixture == &editor.fixture && editor.fixture_owner.arena != nil)
        testing.expect(t, fixture_lifecycle_test_bound(&editor.fixture, .On_Foot))
        testing.expect(t, fixture_editor_test_root_equal(editor, root_snapshot))
        stored_v1, stored_ok := fixture_editor_store_test_read_bytes(t, path)
        if stored_ok {
            testing.expect(t, fixture_codec_test_bytes_equal(stored_v1, v1_snapshot))
            delete(stored_v1)
        }
    }

    @(test)
    fixture_editor_file_failures_are_atomic_and_clean :: proc(t: ^testing.T) {
        directory, path, temporary_path, paths_ok := fixture_editor_store_test_paths(t)
        if !paths_ok do return
        defer fixture_editor_store_test_paths_destroy(directory, path, temporary_path)

        editor, editor_ok := fixture_editor_store_test_bound_editor(t)
        if !editor_ok do return
        defer fixture_editor_test_destroy(editor)
        live_snapshot := fixture_editor_test_live_snapshot(editor)
        sentinel := "fixture-sentinel"

        partial_state := Fixture_Editor_Store_Test_State {
            failure = .Partial,
        }
        partial_error, partial_ok := fixture_editor_save_to_path_with_options(
            editor,
            path,
            fixture_editor_store_test_options(&partial_state, temporary_path),
        )
        testing.expect(t, partial_ok && partial_error.kind == .None && partial_state.write_calls > 1)
        testing.expect(t, !os.exists(temporary_path))
        fixture_editor_store_error_dispose(&partial_error)

        failures := [?]Fixture_Editor_Store_Test_Failure{.Partial_Then_Write, .Zero_Write, .Sync, .Close, .Rename}
        expected := [?]Fixture_Editor_Store_Error_Kind {
            .Write_Temporary,
            .Write_Temporary,
            .Sync_Temporary,
            .Close_Temporary,
            .Rename_Target,
        }
        for failure, index in failures {
            _ = os.remove(temporary_path)
            testing.expect(t, os.write_entire_file(path, sentinel) == nil)
            state := Fixture_Editor_Store_Test_State {
                failure = failure,
            }
            error, ok := fixture_editor_save_to_path_with_options(
                editor,
                path,
                fixture_editor_store_test_options(&state, temporary_path),
            )
            testing.expect(t, !ok && error.kind == expected[index] && error.path == path)
            testing.expect(t, !os.exists(temporary_path))
            fixture_editor_store_test_expect_sentinel(t, path, sentinel)
            testing.expect(t, fixture_editor_test_live_equal(editor, live_snapshot))
            fixture_editor_store_error_dispose(&error)
            fixture_editor_store_error_dispose(&error)
        }

        testing.expect(t, os.write_entire_file(path, sentinel) == nil)
        read_state := Fixture_Editor_Store_Test_State {
            failure = .Read,
        }
        read_error, read_ok := fixture_editor_load_from_path_with_options(
            editor,
            path,
            fixture_editor_store_test_options(&read_state, temporary_path),
        )
        testing.expect(t, !read_ok && read_error.kind == .Read_Source && read_error.path == path)
        testing.expect(t, fixture_editor_test_live_equal(editor, live_snapshot))
        fixture_editor_store_test_expect_sentinel(t, path, sentinel)
        fixture_editor_store_error_dispose(&read_error)
        fixture_editor_store_error_dispose(&read_error)

        invalid := []byte{1, 2, 3}
        testing.expect(t, os.write_entire_file(path, invalid) == nil)
        invalid_error, invalid_ok := fixture_editor_load_from_path(editor, path)
        testing.expect(t, !invalid_ok && invalid_error.kind == .Load)
        testing.expect(t, fixture_editor_test_live_equal(editor, live_snapshot))
        invalid_stored, invalid_stored_ok := fixture_editor_store_test_read_bytes(t, path)
        if invalid_stored_ok {
            testing.expect(t, fixture_codec_test_bytes_equal(invalid_stored, invalid))
            delete(invalid_stored)
        }
        fixture_editor_store_error_dispose(&invalid_error)
        fixture_editor_store_error_dispose(&invalid_error)

        nil_error, nil_ok := fixture_editor_save_to_path(editor, path, {})
        testing.expect(t, !nil_ok && nil_error.kind == .Invalid_Argument)
        testing.expect(t, fixture_editor_test_live_equal(editor, live_snapshot))
        fixture_editor_store_error_dispose(&nil_error)

        probe_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        _ = os.remove(temporary_path)
        probe_error, probe_ok := fixture_editor_save_to_path_with_options(
            editor,
            path,
            fixture_editor_store_test_options(&Fixture_Editor_Store_Test_State{}, temporary_path),
            fixture_migration_test_allocator(&probe_state),
        )
        testing.expect(t, probe_ok && probe_error.kind == .None)
        fixture_editor_store_error_dispose(&probe_error)
        allocation_count := probe_state.allocation_calls
        testing.expect(t, allocation_count > 1 && probe_state.outstanding == 0)

        // Lock the store snapshot and codec-entry boundaries here. Exhaustive
        // codec allocation sweeps belong to the codec tests; repeating the
        // 48 MB fixture encode for every allocation violates focused-test speed.
        expected_oom_kind := [?]Fixture_Editor_Store_Error_Kind{.Out_Of_Memory, .Codec}
        for fail_at in 0 ..< 2 {
            testing.expect(t, os.write_entire_file(path, sentinel) == nil)
            _ = os.remove(temporary_path)
            allocator_state := fixture_migration_test_allocator_state {
                base    = runtime.default_allocator(),
                fail_at = fail_at,
            }
            file_state: Fixture_Editor_Store_Test_State
            error, ok := fixture_editor_save_to_path_with_options(
                editor,
                path,
                fixture_editor_store_test_options(&file_state, temporary_path),
                fixture_migration_test_allocator(&allocator_state),
            )
            testing.expect(t, !ok)
            testing.expect(t, error.kind == expected_oom_kind[fail_at])
            testing.expect(t, allocator_state.allocation_calls == fail_at + 1)
            testing.expect(t, allocator_state.outstanding == 0)
            testing.expect(t, !os.exists(temporary_path))
            fixture_editor_store_test_expect_sentinel(t, path, sentinel)
            testing.expect(t, fixture_editor_test_live_equal(editor, live_snapshot))
            fixture_editor_store_error_dispose(&error)
            fixture_editor_store_error_dispose(&error)
        }
    }
}
