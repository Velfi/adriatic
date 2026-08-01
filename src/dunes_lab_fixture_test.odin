package main

import terrain "../packages/terrain"
import vehicles "../packages/vehicles"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

when ODIN_TEST {
    dunes_lab_fixture_test_config :: proc() -> Dunes_Lab_Config {
        return {seed = 0xdecafbad, wind_angle = -.32, vegetation = .41}
    }

    dunes_lab_fixture_test_bytes_equal :: proc(left, right: []byte) -> bool {
        if len(left) != len(right) do return false
        for value, index in left {
            if value != right[index] do return false
        }
        return true
    }

    dunes_lab_fixture_test_terrain_equal :: proc(left, right: ^terrain.Project) -> bool {
        if left == nil || right == nil do return false
        if left.sea_level != right.sea_level || left.revision != right.revision do return false
        for level_index in 0 ..< terrain.CLIPMAP_LEVELS {
            left_level := &left.levels[level_index]
            right_level := &right.levels[level_index]
            if left_level.cell_size != right_level.cell_size ||
               left_level.origin_x != right_level.origin_x ||
               left_level.origin_z != right_level.origin_z {
                return false
            }
            left_heights := mem.byte_slice(rawptr(&left_level.heights[0]), size_of(left_level.heights))
            right_heights := mem.byte_slice(rawptr(&right_level.heights[0]), size_of(right_level.heights))
            if !dunes_lab_fixture_test_bytes_equal(left_heights, right_heights) do return false
            left_material := mem.byte_slice(rawptr(&left_level.material[0]), size_of(left_level.material))
            right_material := mem.byte_slice(rawptr(&right_level.material[0]), size_of(right_level.material))
            if !dunes_lab_fixture_test_bytes_equal(left_material, right_material) do return false
        }
        return true
    }

    dunes_lab_fixture_test_seed_terrain :: proc(project: ^terrain.Project) {
        if project == nil do return
        project.sea_level = 3.25
        project.revision = 0xdecafbad
        for &level, level_index in project.levels {
            level.cell_size = .5 + f32(level_index) * 1.25
            level.origin_x = -17.5 + f32(level_index)
            level.origin_z = 23.25 - f32(level_index)
            first := level_index * 7919 % terrain.SAMPLES_PER_LEVEL
            second := (level_index * 104729 + 17) % terrain.SAMPLES_PER_LEVEL
            level.heights[first] = -f32(level_index) - .25
            level.heights[second] = f32(level_index) + .75
            level.material[first] = f32(level_index) * .125
            level.material[second] = -f32(level_index) * .375
        }
    }

    dunes_lab_fixture_test_expect_invalid_load :: proc(
        t: ^testing.T,
        lab: Lab_Fixture_State,
        expected_kind: Fixture_Editor_Load_Error_Kind,
        expected_path: string,
    ) {
        source := fixture_editor_test_source()
        defer fixture_editor_test_source_destroy(source)
        source.lab = lab
        data, encode_error, encoded := fixture_codec_encode(source, context.allocator)
        testing.expect(t, encoded && encode_error.kind == .None)
        fixture_codec_error_dispose(&encode_error)
        if !encoded do return
        defer delete(data)
        data_snapshot := fixture_codec_test_copy(data)
        defer delete(data_snapshot)

        editor := fixture_editor_test_editor(t)
        defer fixture_editor_test_destroy(editor)
        editor.lab = {
            kind  = .Dunes,
            dunes = dunes_lab_fixture_test_config(),
        }
        editor.active_lab_scene = "dunes"
        editor.dunes_lab_runtime.plan.dune_count = 73
        for &level, index in editor.project.levels {
            level.heights[index] = f32(index) + .125
            level.material[index] = -f32(index) - .375
        }
        live_snapshot := fixture_editor_test_live_snapshot(editor)
        lab_snapshot := editor.lab
        active_lab_snapshot := editor.active_lab_scene
        dune_count_snapshot := editor.dunes_lab_runtime.plan.dune_count
        sea_level_snapshot := editor.project.sea_level
        terrain_revision_snapshot := editor.project.revision

        load_error, loaded := fixture_editor_load(editor, data, context.allocator)
        testing.expect(t, !loaded && load_error.kind == expected_kind)
        if expected_path != "" do testing.expect(t, load_error.path == expected_path)
        testing.expect(t, fixture_editor_test_live_equal(editor, live_snapshot))
        testing.expect(t, editor.lab == lab_snapshot)
        testing.expect(t, editor.active_lab_scene == active_lab_snapshot)
        testing.expect_value(t, editor.dunes_lab_runtime.plan.dune_count, dune_count_snapshot)
        testing.expect(t, editor.project.sea_level == sea_level_snapshot)
        testing.expect(t, editor.project.revision == terrain_revision_snapshot)
        for level, index in editor.project.levels {
            testing.expect(t, level.heights[index] == f32(index) + .125)
            testing.expect(t, level.material[index] == -f32(index) - .375)
        }
        testing.expect(t, dunes_lab_fixture_test_bytes_equal(data, data_snapshot))
        fixture_editor_load_error_dispose(&load_error)
        fixture_editor_load_error_dispose(&load_error)
    }

    @(test)
    dunes_lab_fixture_load_rehydrates_without_mutating_terrain :: proc(t: ^testing.T) {
        source := fixture_editor_test_source()
        defer fixture_editor_test_source_destroy(source)
        source.lab = {
            kind  = .Dunes,
            dunes = dunes_lab_fixture_test_config(),
        }
        dunes_lab_fixture_test_seed_terrain(&source.project)
        source.camera_pose = {
            position = {31, 47, -59},
            target   = {-11, 13, 17},
        }
        data, encode_error, encoded := fixture_codec_encode(source, context.allocator)
        testing.expect(t, encoded && encode_error.kind == .None)
        fixture_codec_error_dispose(&encode_error)
        if !encoded do return
        defer delete(data)

        editor := fixture_editor_test_editor(t)
        defer fixture_editor_test_destroy(editor)
        editor.active_lab_scene = "dunes"
        editor.lab = {
            kind = .Dunes,
            dunes = {seed = 3, wind_angle = .4, vegetation = .9},
        }
        editor.dunes_lab_runtime.plan.dune_count = 91
        editor.camera_pose = {
            position = {7, 11, -13},
            target   = {-2, 5, 19},
        }
        load_error, loaded := fixture_editor_load(editor, data, context.allocator)
        testing.expect(t, loaded && load_error.kind == .None)
        fixture_editor_load_error_dispose(&load_error)
        if !loaded do return

        testing.expect(t, editor.lab.kind == .Dunes)
        testing.expect(t, editor.lab.dunes == source.lab.dunes)
        testing.expect(t, editor.active_lab_scene == "dunes")
        testing.expect(t, editor.dunes_lab_runtime.plan.dune_count > 0)
        testing.expect(t, editor.dunes_lab_runtime.shore.nearshore_width == 78)
        testing.expect(t, editor.dunes_lab_runtime.diagnostics.sampled > 0)
        testing.expect(t, editor.dunes_lab_runtime.diagnostics.grass_cards > 0)
        testing.expect(t, editor.camera_pose == source.camera_pose)
        testing.expect(t, dunes_lab_fixture_test_terrain_equal(&source.project, &editor.project))
    }

    @(test)
    dunes_lab_fixture_exit_and_ordinary_load_clear_runtime :: proc(t: ^testing.T) {
        editor := fixture_editor_test_editor(t)
        defer fixture_editor_test_destroy(editor)
        editor.lab = {
            kind  = .Dunes,
            dunes = dunes_lab_fixture_test_config(),
        }
        dunes_lab_rebuild_runtime(editor)
        editor.active_lab_scene = "dunes"
        lab_scene_exit_to_main_menu(editor)
        testing.expect(t, editor.lab.kind == .None)
        testing.expect(t, editor.active_lab_scene == "")
        testing.expect_value(t, editor.dunes_lab_runtime.plan.dune_count, 0)
        testing.expect_value(t, editor.dunes_lab_runtime.diagnostics.sampled, 0)

        data := fixture_editor_test_current_container(t)
        testing.expect(t, data != nil)
        if data == nil do return
        defer delete(data)
        editor.lab = {
            kind  = .Dunes,
            dunes = dunes_lab_fixture_test_config(),
        }
        editor.active_lab_scene = "dunes"
        editor.dunes_lab_runtime.plan.dune_count = 17
        editor.dunes_lab_runtime.diagnostics.sampled = 29

        load_error, loaded := fixture_editor_load(editor, data, context.allocator)
        testing.expect(t, loaded && load_error.kind == .None)
        fixture_editor_load_error_dispose(&load_error)
        if !loaded do return

        testing.expect(t, editor.lab.kind == .None)
        testing.expect(t, editor.active_lab_scene == "")
        testing.expect_value(t, editor.dunes_lab_runtime.plan.dune_count, 0)
        testing.expect_value(t, editor.dunes_lab_runtime.diagnostics.sampled, 0)
    }

    @(test)
    dunes_lab_fixture_lab_preflight_paths :: proc(t: ^testing.T) {
        testing.expect(t, lab_fixture_preflight({}) == "")
        unknown := Lab_Fixture_State {
            kind = cast(Lab_Kind)u8(255),
        }
        testing.expect(t, lab_fixture_preflight(unknown) == "lab.kind")
        testing.expect(
            t,
            lab_fixture_preflight({kind = .Dunes, dunes = {wind_angle = -.62, vegetation = 0}}) == "",
        )
        testing.expect(
            t,
            lab_fixture_preflight({kind = .Dunes, dunes = {wind_angle = .62, vegetation = 1}}) == "",
        )
        testing.expect(
            t,
            lab_fixture_preflight({kind = .Dunes, dunes = {wind_angle = -.63, vegetation = .5}}) ==
                "lab.dunes.wind_angle",
        )
        testing.expect(
            t,
            lab_fixture_preflight({kind = .Dunes, dunes = {wind_angle = .63, vegetation = .5}}) ==
                "lab.dunes.wind_angle",
        )
        testing.expect(
            t,
            lab_fixture_preflight({kind = .Dunes, dunes = {wind_angle = .5, vegetation = -.01}}) ==
                "lab.dunes.vegetation",
        )
        testing.expect(
            t,
            lab_fixture_preflight({kind = .Dunes, dunes = {wind_angle = .5, vegetation = 1.01}}) ==
                "lab.dunes.vegetation",
        )
        testing.expect(
            t,
            lab_fixture_preflight({kind = .Dunes, dunes = {wind_angle = math.nan_f32(), vegetation = .5}}) ==
                "lab.dunes.wind_angle",
        )
        testing.expect(
            t,
            lab_fixture_preflight({kind = .Dunes, dunes = {wind_angle = .5, vegetation = math.inf_f32(1)}}) ==
                "lab.dunes.vegetation",
        )
    }

    @(test)
    dunes_lab_fixture_hostile_lab_state_is_atomic :: proc(t: ^testing.T) {
        unknown := Lab_Fixture_State {
            kind = cast(Lab_Kind)u8(255),
        }
        dunes_lab_fixture_test_expect_invalid_load(t, unknown, .Decode, "")
        dunes_lab_fixture_test_expect_invalid_load(
            t,
            {kind = .Dunes, dunes = {wind_angle = math.nan_f32(), vegetation = .5}},
            .Invalid_State,
            "lab.dunes.wind_angle",
        )
        dunes_lab_fixture_test_expect_invalid_load(
            t,
            {kind = .Dunes, dunes = {wind_angle = .5, vegetation = math.inf_f32(1)}},
            .Invalid_State,
            "lab.dunes.vegetation",
        )
        dunes_lab_fixture_test_expect_invalid_load(
            t,
            {kind = .Dunes, dunes = {wind_angle = .5, vegetation = 1.01}},
            .Invalid_State,
            "lab.dunes.vegetation",
        )
    }

    @(test)
    dunes_lab_hot_state_rehydrates_without_mutating_terrain :: proc(t: ^testing.T) {
        directory, directory_error := os.make_directory_temp("", "adriatic-dunes-hot-*", context.allocator)
        testing.expect(t, directory_error == nil)
        if directory_error != nil do return
        path, path_error := strings.concatenate({directory, "/state.bin"}, context.allocator)
        testing.expect(t, path_error == nil)
        if path_error != nil {
            _ = os.remove(directory)
            return
        }
        defer {
            _ = os.remove(path)
            _ = os.remove(directory)
            delete(path)
            delete(directory)
        }

        source := new(Editor)
        restored := new(Editor)
        backing_allocator := context.allocator
        defer {
            free(source, backing_allocator)
            free(restored, backing_allocator)
        }
        arena, arena_ok := fixture_migration_arena_allocate(backing_allocator)
        testing.expect(t, arena_ok)
        if !arena_ok do return
        arena_allocator := mem.dynamic_arena_allocator(arena)
        context.allocator = arena_allocator
        defer {
            vehicles.libellula_mesh_destroy(&restored.libellula_visual_mesh)
            delete(restored.libellula_projected_faces)
            structure_storage_destroy(restored)
            context.allocator = backing_allocator
            fixture_migration_arena_dispose(arena, backing_allocator)
        }
        fixture_lifecycle_test_seed_live(&source.fixture, .On_Foot, {.Postale, .Libellula, .Libellula_Mk2, .Rondine})
        source.lab = {
            kind  = .Dunes,
            dunes = dunes_lab_fixture_test_config(),
        }
        dunes_lab_fixture_test_seed_terrain(&source.project)
        source.camera_pose = {
            position = {31, 47, -59},
            target   = {-11, 13, 17},
        }
        source.dunes_lab_runtime.plan.dune_count = 83

        testing.expect(t, hot_state_save(source, path))
        load_result := hot_state_load(restored, path)
        testing.expect(t, load_result == .Loaded)
        if load_result != .Loaded do return

        testing.expect(t, restored.lab.kind == .Dunes)
        testing.expect(t, restored.lab.dunes == source.lab.dunes)
        testing.expect(t, restored.active_lab_scene == "dunes")
        testing.expect(t, restored.dunes_lab_runtime.plan.dune_count > 0)
        testing.expect(t, restored.dunes_lab_runtime.shore.nearshore_width == 78)
        testing.expect(t, restored.dunes_lab_runtime.diagnostics.sampled > 0)
        testing.expect(t, restored.camera_pose == source.camera_pose)
        testing.expect(t, dunes_lab_fixture_test_terrain_equal(&source.project, &restored.project))

        source.lab.dunes.wind_angle = math.nan_f32()
        restored.dunes_lab_runtime.plan.dune_count = 97
        testing.expect(t, hot_state_save(source, path))
        invalid_result := hot_state_load(restored, path)
        testing.expect(t, invalid_result == .Invalid)
        testing.expect_value(t, restored.dunes_lab_runtime.plan.dune_count, 97)
        testing.expect(t, dunes_lab_fixture_test_terrain_equal(&source.project, &restored.project))
    }
}
