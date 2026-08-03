package main

import fixture_file "../packages/fixture_file"
import flight "../packages/flight"
import terrain "../packages/terrain"
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
        Sidecar_Open,
        Sidecar_Write,
        Sidecar_Sync,
        Sidecar_Close,
        Link,
        Sidecar_Read,
        Read,
    }

    Fixture_Editor_Store_Test_State :: struct {
        failure:     Fixture_Editor_Store_Test_Failure,
        write_calls: int,
        link_calls:  int,
        read_calls:  int,
    }

    fixture_editor_store_test_aux_mix :: proc(_: rawptr, _: []f32) {  }

    fixture_editor_store_test_open :: proc(data: rawptr, path: string) -> (^os.File, os.Error) {
        state := cast(^Fixture_Editor_Store_Test_State)data
        if state.failure == .Sidecar_Open do return nil, .Invalid_File
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
        case .Sidecar_Write:
            return 0, .Invalid_File
        case .None, .Sync, .Close, .Rename, .Sidecar_Open, .Sidecar_Sync, .Sidecar_Close, .Link, .Sidecar_Read, .Read:
        }
        return os.write(file, bytes)
    }

    fixture_editor_store_test_sync :: proc(data: rawptr, file: ^os.File) -> os.Error {
        state := cast(^Fixture_Editor_Store_Test_State)data
        if state.failure == .Sync || state.failure == .Sidecar_Sync do return .Invalid_File
        return os.sync(file)
    }

    fixture_editor_store_test_close :: proc(data: rawptr, file: ^os.File) -> os.Error {
        state := cast(^Fixture_Editor_Store_Test_State)data
        close_error := os.close(file)
        if state.failure == .Close || state.failure == .Sidecar_Close do return .Invalid_File
        return close_error
    }

    fixture_editor_store_test_rename :: proc(data: rawptr, old_path, new_path: string) -> os.Error {
        state := cast(^Fixture_Editor_Store_Test_State)data
        if state.failure == .Rename do return .Invalid_File
        return os.rename(old_path, new_path)
    }

    fixture_editor_store_test_link :: proc(data: rawptr, old_path, new_path: string) -> os.Error {
        state := cast(^Fixture_Editor_Store_Test_State)data
        state.link_calls += 1
        if state.failure == .Link do return .Invalid_File
        return os.link(old_path, new_path)
    }

    fixture_editor_store_test_remove :: proc(_: rawptr, path: string) -> os.Error {
        return os.remove(path)
    }

    fixture_editor_store_test_read :: proc(data: rawptr, path: string, alloc: mem.Allocator) -> ([]byte, os.Error) {
        state := cast(^Fixture_Editor_Store_Test_State)data
        state.read_calls += 1
        if state.failure == .Sidecar_Read || state.failure == .Read do return nil, .Invalid_File
        return os.read_entire_file(path, alloc)
    }

    fixture_editor_store_test_options :: proc(
        state: ^Fixture_Editor_Store_Test_State,
        temporary_path: string,
        sidecar_temporary_path := "",
    ) -> Fixture_Editor_Store_Options {
        return {
            operations = {
                data = rawptr(state),
                open_excl = fixture_editor_store_test_open,
                write = fixture_editor_store_test_write,
                sync = fixture_editor_store_test_sync,
                close = fixture_editor_store_test_close,
                rename = fixture_editor_store_test_rename,
                link = fixture_editor_store_test_link,
                remove = fixture_editor_store_test_remove,
                read = fixture_editor_store_test_read,
            },
            temporary_path = temporary_path,
            sidecar_temporary_path = sidecar_temporary_path,
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

    fixture_editor_store_test_expect_bytes :: proc(t: ^testing.T, path: string, expected: []byte) {
        stored, read_ok := fixture_editor_store_test_read_bytes(t, path)
        if !read_ok do return
        defer delete(stored)
        testing.expect(t, fixture_codec_test_bytes_equal(stored, expected))
    }

    @(test)
    fixture_editor_default_path_is_product_data_not_launch_relative :: proc(t: ^testing.T) {
        path, path_error, path_ok := fixture_editor_store_default_path(context.allocator)
        defer fixture_editor_store_error_dispose(&path_error)
        testing.expect(t, path_ok && path_error.kind == .None)
        if !path_ok do return
        defer delete(path)

        base, base_error := os.user_data_dir(context.allocator)
        testing.expect(t, base_error == nil && len(base) > 0)
        if base_error != nil || len(base) == 0 do return
        defer delete(base)

        expected, expected_error := strings.concatenate(
            {base, "/", FIXTURE_EDITOR_PRODUCT_DIRECTORY, "/", FIXTURE_EDITOR_FILE_NAME},
            context.allocator,
        )
        testing.expect(t, expected_error == nil)
        if expected_error != nil do return
        defer delete(expected)

        testing.expect(t, path == expected)
        testing.expect(t, os.is_absolute_path(path))
        testing.expect(t, path != FIXTURE_EDITOR_FILE_NAME)
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
        editor.vehicle_paint_layers[0][0] = 0x5a
        editor.sdf_obstacles[0].position = {}
        editor.sdf_obstacle_selected = -1

        load_error, loaded := fixture_editor_load_from_path(editor, path)
        testing.expect(t, loaded && load_error.kind == .None)
        fixture_editor_store_error_dispose(&load_error)
        if !loaded do return

        testing.expect(t, editor.project.sea_level == 19)
        testing.expect(t, editor.project.structures[0].id == 0x5151)
        testing.expect(t, editor.story_state.romance == .Corresponding)
        testing.expect(t, editor.vehicle_paint_layers[0][0] == 0x5a)
        testing.expect(t, editor.sdf_obstacle_count == 1)
        testing.expect(t, editor.sdf_obstacle_selected == 0)
        testing.expect(t, editor.sdf_obstacles[0].position == flight.Vec3{12, 8, -4})
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
        editor.sdf_obstacles = {}
        editor.sdf_obstacle_count = 0
        editor.sdf_obstacle_selected = -1
        editor.sdf_obstacle_interaction.hovered = -1

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

        empty_error, empty_loaded := fixture_editor_load_from_path(editor, path)
        testing.expect(t, empty_loaded && empty_error.kind == .None)
        fixture_editor_store_error_dispose(&empty_error)
        if !empty_loaded do return
        testing.expect(t, editor.sdf_obstacle_count == 0)
        testing.expect(t, editor.sdf_obstacle_selected == -1)
        testing.expect(t, editor.sdf_obstacle_interaction.hovered == -1)

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
    fixture_editor_pair_save_publishes_immutable_map_sidecar :: proc(t: ^testing.T) {
        directory, path, temporary_path, paths_ok := fixture_editor_store_test_paths(t)
        if !paths_ok do return
        defer fixture_editor_store_test_paths_destroy(directory, path, temporary_path)
        sidecar_temporary_path, sidecar_temporary_error := strings.concatenate(
            {directory, "/adriatic-map.tmp"},
            context.allocator,
        )
        testing.expect(t, sidecar_temporary_error == nil)
        if sidecar_temporary_error != nil do return
        defer {
            _ = os.remove(sidecar_temporary_path)
            delete(sidecar_temporary_path)
        }

        editor, editor_ok := fixture_editor_store_test_bound_editor(t)
        if !editor_ok do return
        defer fixture_editor_test_destroy(editor)
        editor.project.sea_level = 19
        editor.project.structures[0].id = 0x5151
        editor.story_state.romance = .Corresponding
        expected_sea_level := editor.project.sea_level
        expected_structure_id := editor.project.structures[0].id
        live_snapshot := fixture_editor_test_live_snapshot(editor)

        inline_error, inline_saved := fixture_editor_save_to_path(editor, path)
        testing.expect(t, inline_saved && inline_error.kind == .None)
        fixture_editor_store_error_dispose(&inline_error)
        if !inline_saved do return
        inline_fixture, inline_read := fixture_editor_store_test_read_bytes(t, path)
        if !inline_read do return
        defer delete(inline_fixture)

        first_state: Fixture_Editor_Store_Test_State
        first_error, first_saved := fixture_editor_save_pair_to_path_with_options(
            editor,
            path,
            fixture_editor_store_test_options(&first_state, temporary_path, sidecar_temporary_path),
        )
        testing.expect(t, first_saved && first_error.kind == .None && first_state.link_calls == 1)
        fixture_editor_store_error_dispose(&first_error)
        if !first_saved do return
        testing.expect(t, !os.exists(temporary_path) && !os.exists(sidecar_temporary_path))
        testing.expect(t, fixture_editor_test_live_equal(editor, live_snapshot))

        first_fixture, first_fixture_read := fixture_editor_store_test_read_bytes(t, path)
        if !first_fixture_read do return
        defer delete(first_fixture)
        testing.expect(t, len(first_fixture) < len(inline_fixture))
        decoded, decode_error, decoded_ok := fixture_codec_decode(first_fixture, context.allocator)
        testing.expect(t, decoded_ok && decode_error.kind == .None)
        fixture_codec_error_dispose(&decode_error)
        if !decoded_ok do return
        defer fixture_migration_result_dispose(&decoded)
        testing.expect(t, decoded.fixture.map_source.kind == .Sidecar)
        testing.expect(t, len(decoded.fixture.map_source.inline_bytes) == 0)
        testing.expect(t, fixture_map_sidecar_valid(decoded.fixture.map_source.sidecar))
        testing.expect(t, decoded.fixture.story_state.romance == .Corresponding)
        testing.expect(t, decoded.fixture.project.structure_count == 0)

        sidecar := decoded.fixture.map_source.sidecar
        sidecar_path, resolved := fixture_map_sidecar_resolve(path, sidecar, context.allocator)
        testing.expect(t, resolved)
        if !resolved do return
        defer delete(sidecar_path)
        sidecar_bytes, sidecar_read := fixture_editor_store_test_read_bytes(t, sidecar_path)
        if !sidecar_read do return
        defer delete(sidecar_bytes)
        testing.expect(t, fixture_map_sidecar_matches_encoded(sidecar, sidecar_bytes))
        artifact, artifact_error, artifact_ok := map_artifact_decode(sidecar_bytes, context.allocator)
        testing.expect(t, artifact_ok && artifact_error.kind == .None)
        map_artifact_error_dispose(&artifact_error)
        if !artifact_ok do return
        defer map_artifact_destroy(artifact)
        testing.expect(t, artifact.project.sea_level == expected_sea_level)
        testing.expect(t, artifact.project.structures[0].id == expected_structure_id)

        first_fixture_snapshot := fixture_codec_test_copy(first_fixture)
        defer delete(first_fixture_snapshot)
        first_sidecar_snapshot := fixture_codec_test_copy(sidecar_bytes)
        defer delete(first_sidecar_snapshot)
        second_state: Fixture_Editor_Store_Test_State
        second_error, second_saved := fixture_editor_save_pair_to_path_with_options(
            editor,
            path,
            fixture_editor_store_test_options(&second_state, temporary_path, sidecar_temporary_path),
        )
        testing.expect(
            t,
            second_saved && second_error.kind == .None && second_state.link_calls == 1 && second_state.read_calls == 1,
        )
        fixture_editor_store_error_dispose(&second_error)
        if !second_saved do return
        second_fixture, second_fixture_read := fixture_editor_store_test_read_bytes(t, path)
        if second_fixture_read {
            testing.expect(t, fixture_codec_test_bytes_equal(first_fixture_snapshot, second_fixture))
            delete(second_fixture)
        }
        second_sidecar, second_sidecar_read := fixture_editor_store_test_read_bytes(t, sidecar_path)
        if second_sidecar_read {
            testing.expect(t, fixture_codec_test_bytes_equal(first_sidecar_snapshot, second_sidecar))
            delete(second_sidecar)
        }

        wrong_sidecar := []byte{0x77, 0x72, 0x6f, 0x6e, 0x67}
        testing.expect(t, os.write_entire_file(sidecar_path, wrong_sidecar) == nil)
        testing.expect(t, os.write_entire_file(path, first_fixture_snapshot) == nil)
        wrong_error, wrong_saved := fixture_editor_save_pair_to_path_with_options(
            editor,
            path,
            fixture_editor_store_test_options(
                &Fixture_Editor_Store_Test_State{},
                temporary_path,
                sidecar_temporary_path,
            ),
        )
        testing.expect(
            t,
            !wrong_saved &&
            wrong_error.kind == .Sidecar_Digest_Mismatch &&
            wrong_error.path == path &&
            wrong_error.sidecar == sidecar,
        )
        fixture_editor_store_error_dispose(&wrong_error)
        testing.expect(t, !os.exists(temporary_path) && !os.exists(sidecar_temporary_path))
        fixture_editor_store_test_expect_bytes(t, path, first_fixture_snapshot)
        testing.expect(t, fixture_editor_test_live_equal(editor, live_snapshot))
        testing.expect(t, os.write_entire_file(sidecar_path, first_sidecar_snapshot) == nil)

        failures := [?]Fixture_Editor_Store_Test_Failure {
            .Sidecar_Open,
            .Sidecar_Write,
            .Sidecar_Sync,
            .Sidecar_Close,
            .Link,
            .Sidecar_Read,
        }
        expected := [?]Fixture_Editor_Store_Error_Kind {
            .Open_Sidecar_Temporary,
            .Write_Sidecar_Temporary,
            .Sync_Sidecar_Temporary,
            .Close_Sidecar_Temporary,
            .Link_Sidecar,
            .Read_Sidecar,
        }
        sentinel := "fixture-sentinel"
        for failure, index in failures {
            _ = os.remove(temporary_path)
            _ = os.remove(sidecar_temporary_path)
            testing.expect(t, os.write_entire_file(path, sentinel) == nil)
            state := Fixture_Editor_Store_Test_State {
                failure = failure,
            }
            error, saved := fixture_editor_save_pair_to_path_with_options(
                editor,
                path,
                fixture_editor_store_test_options(&state, temporary_path, sidecar_temporary_path),
            )
            testing.expect(
                t,
                !saved && error.kind == expected[index] && error.path == path && error.sidecar == sidecar,
            )
            fixture_editor_store_error_dispose(&error)
            fixture_editor_store_error_dispose(&error)
            testing.expect(t, !os.exists(temporary_path) && !os.exists(sidecar_temporary_path))
            fixture_editor_store_test_expect_sentinel(t, path, sentinel)
            testing.expect(t, fixture_editor_test_live_equal(editor, live_snapshot))
        }

        editor.project.sea_level = expected_sea_level + 1
        orphan_live_snapshot := fixture_editor_test_live_snapshot(editor)
        seeds := editor.default_map_regeneration_seeds
        defaults := terrain.DEFAULT_ISLAND_SEEDS
        for &seed, index in seeds do if seed == 0 do seed = defaults[index]
        orphan_artifact, orphan_capture_error, orphan_captured := map_artifact_capture_fixture(&editor.fixture, seeds)
        testing.expect(t, orphan_captured && orphan_capture_error.kind == .None)
        map_artifact_error_dispose(&orphan_capture_error)
        if !orphan_captured do return
        defer map_artifact_destroy(orphan_artifact)
        orphan_bytes, orphan_encode_error, orphan_encoded := map_artifact_encode(orphan_artifact)
        testing.expect(t, orphan_encoded && orphan_encode_error.kind == .None)
        map_artifact_error_dispose(&orphan_encode_error)
        if !orphan_encoded do return
        defer delete(orphan_bytes)
        orphan_sidecar, orphan_derived := fixture_map_sidecar_derive(orphan_bytes)
        testing.expect(t, orphan_derived)
        if !orphan_derived do return
        orphan_path, orphan_resolved := fixture_map_sidecar_resolve(path, orphan_sidecar, context.allocator)
        testing.expect(t, orphan_resolved)
        if !orphan_resolved do return
        defer delete(orphan_path)
        testing.expect(t, !os.exists(orphan_path))
        testing.expect(t, os.write_entire_file(path, sentinel) == nil)
        rename_state := Fixture_Editor_Store_Test_State {
            failure = .Rename,
        }
        rename_error, rename_saved := fixture_editor_save_pair_to_path_with_options(
            editor,
            path,
            fixture_editor_store_test_options(&rename_state, temporary_path, sidecar_temporary_path),
        )
        testing.expect(t, !rename_saved && rename_error.kind == .Rename_Target && rename_state.link_calls == 1)
        fixture_editor_store_error_dispose(&rename_error)
        testing.expect(t, !os.exists(temporary_path) && !os.exists(sidecar_temporary_path))
        fixture_editor_store_test_expect_sentinel(t, path, sentinel)
        testing.expect(t, fixture_editor_test_live_equal(editor, orphan_live_snapshot))
        orphan_stored, orphan_stored_ok := fixture_editor_store_test_read_bytes(t, orphan_path)
        if orphan_stored_ok {
            testing.expect(t, fixture_map_sidecar_matches_encoded(orphan_sidecar, orphan_stored))
            delete(orphan_stored)
        }
    }

    @(test)
    fixture_editor_public_pair_path_load_is_atomic :: proc(t: ^testing.T) {
        directory, path, temporary_path, paths_ok := fixture_editor_store_test_paths(t)
        if !paths_ok do return
        defer fixture_editor_store_test_paths_destroy(directory, path, temporary_path)

        editor, editor_ok := fixture_editor_store_test_bound_editor(t)
        if !editor_ok do return
        defer fixture_editor_test_destroy(editor)
        editor.project.sea_level = 19
        editor.project.structures[0].id = 0x5151
        editor.story_state.romance = .Corresponding

        testing.expect(t, fixture_editor_save_path(editor, path))
        fixture_bytes, fixture_read := fixture_editor_store_test_read_bytes(t, path)
        if !fixture_read do return
        defer delete(fixture_bytes)
        decoded, decode_error, decoded_ok := fixture_codec_decode(fixture_bytes, context.allocator)
        testing.expect(t, decoded_ok && decode_error.kind == .None)
        fixture_codec_error_dispose(&decode_error)
        if !decoded_ok do return
        defer fixture_migration_result_dispose(&decoded)
        testing.expect(t, decoded.fixture.map_source.kind == .Sidecar)
        testing.expect(t, len(decoded.fixture.map_source.inline_bytes) == 0)
        sidecar := decoded.fixture.map_source.sidecar
        testing.expect(t, fixture_map_sidecar_valid(sidecar))
        sidecar_path, resolved := fixture_map_sidecar_resolve(path, sidecar, context.allocator)
        testing.expect(t, resolved)
        if !resolved do return
        defer delete(sidecar_path)
        sidecar_bytes, sidecar_read := fixture_editor_store_test_read_bytes(t, sidecar_path)
        if !sidecar_read do return
        defer delete(sidecar_bytes)
        testing.expect(t, fixture_map_sidecar_matches_encoded(sidecar, sidecar_bytes))

        root_snapshot := fixture_editor_test_root_snapshot(editor)
        editor.project.sea_level = -7
        editor.project.structures[0].id = 3
        load_error, loaded := fixture_editor_load_from_path(editor, path)
        testing.expect(t, loaded && load_error.kind == .None)
        fixture_editor_store_error_dispose(&load_error)
        if !loaded do return
        testing.expect(t, editor.project.sea_level == 19 && editor.project.structures[0].id == 0x5151)
        testing.expect(t, fixture_editor_test_root_equal(editor, root_snapshot))

        failure_snapshot := fixture_editor_test_live_snapshot(editor)
        testing.expect(t, os.remove(sidecar_path) == nil)
        missing_error, missing_loaded := fixture_editor_load_from_path(editor, path)
        testing.expect(
            t,
            !missing_loaded &&
            missing_error.kind == .Read_Sidecar &&
            missing_error.path == path &&
            missing_error.sidecar == sidecar,
        )
        fixture_editor_store_error_dispose(&missing_error)
        testing.expect(t, fixture_editor_test_live_equal(editor, failure_snapshot))
        testing.expect(t, os.write_entire_file(sidecar_path, sidecar_bytes) == nil)

        wrong_sidecar := []byte{0x77, 0x72, 0x6f, 0x6e, 0x67}
        testing.expect(t, os.write_entire_file(sidecar_path, wrong_sidecar) == nil)
        digest_error, digest_loaded := fixture_editor_load_from_path(editor, path)
        testing.expect(
            t,
            !digest_loaded &&
            digest_error.kind == .Sidecar_Digest_Mismatch &&
            digest_error.path == path &&
            digest_error.sidecar == sidecar,
        )
        fixture_editor_store_error_dispose(&digest_error)
        testing.expect(t, fixture_editor_test_live_equal(editor, failure_snapshot))
        testing.expect(t, os.write_entire_file(sidecar_path, sidecar_bytes) == nil)

        malformed_adrmap := make([]byte, len(sidecar_bytes))
        defer delete(malformed_adrmap)
        copy(malformed_adrmap, sidecar_bytes)
        malformed_adrmap[len(malformed_adrmap) - 1] ~= 1
        malformed_sidecar, malformed_derived := fixture_map_sidecar_derive(malformed_adrmap)
        testing.expect(
            t,
            malformed_derived && fixture_map_sidecar_matches_encoded(malformed_sidecar, malformed_adrmap),
        )
        if !malformed_derived do return
        malformed_fixture, malformed_fixture_error, malformed_fixture_ok := fixture_codec_decode(
            fixture_bytes,
            context.allocator,
        )
        testing.expect(t, malformed_fixture_ok && malformed_fixture_error.kind == .None)
        fixture_codec_error_dispose(&malformed_fixture_error)
        if !malformed_fixture_ok do return
        defer fixture_migration_result_dispose(&malformed_fixture)
        malformed_fixture.fixture.map_source.sidecar = malformed_sidecar
        malformed_fixture_bytes, malformed_fixture_encode_error, malformed_fixture_encoded := fixture_codec_encode(
            malformed_fixture.fixture,
            context.allocator,
        )
        testing.expect(t, malformed_fixture_encoded && malformed_fixture_encode_error.kind == .None)
        fixture_codec_error_dispose(&malformed_fixture_encode_error)
        if !malformed_fixture_encoded do return
        defer delete(malformed_fixture_bytes)
        malformed_sidecar_path, malformed_sidecar_resolved := fixture_map_sidecar_resolve(
            path,
            malformed_sidecar,
            context.allocator,
        )
        testing.expect(t, malformed_sidecar_resolved)
        if !malformed_sidecar_resolved do return
        defer delete(malformed_sidecar_path)
        testing.expect(t, os.write_entire_file(path, malformed_fixture_bytes) == nil)
        testing.expect(t, os.write_entire_file(malformed_sidecar_path, malformed_adrmap) == nil)
        map_error, map_loaded := fixture_editor_load_from_path(editor, path)
        testing.expect(
            t,
            !map_loaded &&
            map_error.kind == .Load &&
            map_error.path == path &&
            map_error.sidecar == malformed_sidecar &&
            map_error.load.kind == .Invalid_State &&
            map_error.load.path == "map_source" &&
            map_error.load.map_error.kind == .Checksum_Mismatch,
        )
        fixture_editor_store_error_dispose(&map_error)
        testing.expect(t, fixture_editor_test_live_equal(editor, failure_snapshot))
        testing.expect(t, os.write_entire_file(path, fixture_bytes) == nil)
        testing.expect(t, os.write_entire_file(sidecar_path, sidecar_bytes) == nil)

        malformed, malformed_error, malformed_ok := fixture_codec_decode(fixture_bytes, context.allocator)
        testing.expect(t, malformed_ok && malformed_error.kind == .None)
        fixture_codec_error_dispose(&malformed_error)
        if !malformed_ok do return
        defer fixture_migration_result_dispose(&malformed)
        malformed.fixture.map_source.sidecar.basename_count = 0
        malformed_bytes, malformed_encode_error, malformed_encoded := fixture_codec_encode(
            malformed.fixture,
            context.allocator,
        )
        testing.expect(t, malformed_encoded && malformed_encode_error.kind == .None)
        fixture_codec_error_dispose(&malformed_encode_error)
        if !malformed_encoded do return
        defer delete(malformed_bytes)
        testing.expect(t, os.write_entire_file(path, malformed_bytes) == nil)
        read_state: Fixture_Editor_Store_Test_State
        resolver_error, resolver_loaded := fixture_editor_load_from_path_with_options(
            editor,
            path,
            fixture_editor_store_test_options(&read_state, temporary_path),
        )
        testing.expect(
            t,
            !resolver_loaded &&
            resolver_error.kind == .Resolve_Sidecar &&
            resolver_error.path == path &&
            resolver_error.sidecar.basename_count == 0 &&
            read_state.read_calls == 1,
        )
        fixture_editor_store_error_dispose(&resolver_error)
        testing.expect(t, fixture_editor_test_live_equal(editor, failure_snapshot))
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
