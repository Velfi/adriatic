package main

import terrain "../packages/terrain"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

when ODIN_TEST {
    map_artifact_test_source :: proc() -> ^Map_Artifact {
        artifact := new(Map_Artifact)
        artifact.generator_version = MAP_ARTIFACT_GENERATOR_VERSION
        artifact.seeds = terrain.DEFAULT_ISLAND_SEEDS
        artifact.project.revision = 7
        artifact.project.sea_level = 1.25
        artifact.project.next_structure_id = 2
        artifact.project.structures = make([dynamic]terrain.Structure, 1)
        artifact.project.structure_count = 1
        artifact.project.structures[0] = {
            id = 1,
            width = 4,
            depth = 5,
            height = 6,
            color = {1, 2, 3, 255},
            kind = .Rock,
        }
        for &level, index in artifact.project.levels {
            level.cell_size = terrain.FINE_CELL_SIZE * f32(u32(1) << u32(index))
            level.origin_x = -100
            level.origin_z = -100
        }
        artifact.default_marina_count = 0
        return artifact
    }

    @(test)
    map_artifact_editor_path_uses_writable_user_data :: proc(t: ^testing.T) {
        base, base_error := os.user_data_dir(context.temp_allocator)
        path, path_ok := map_artifact_save_path(context.temp_allocator)
        testing.expect(t, base_error == nil)
        testing.expect(t, path_ok)
        if base_error == nil && path_ok {
            testing.expect(t, strings.has_prefix(path, base))
            testing.expect(t, strings.has_suffix(path, "/Adriatic/adriatic.adriatic-map"))
        }
    }

    @(test)
    map_artifact_round_trip_is_deterministic_and_rejects_bad_containers :: proc(t: ^testing.T) {
        source := map_artifact_test_source()
        defer map_artifact_destroy(source)
        first, first_error, first_ok := map_artifact_encode(source)
        defer delete(first)
        defer map_artifact_error_dispose(&first_error)
        testing.expect(t, first_ok)
        second, second_error, second_ok := map_artifact_encode(source)
        defer delete(second)
        defer map_artifact_error_dispose(&second_error)
        testing.expect(t, second_ok)
        testing.expect(t, len(first) == len(second))
        if len(first) == len(second) do testing.expect(t, slice.equal(first, second))

        decoded, decode_error, decode_ok := map_artifact_decode(first)
        defer map_artifact_error_dispose(&decode_error)
        testing.expect(t, decode_ok)
        if decode_ok {
            defer map_artifact_destroy(decoded)
            testing.expect(t, decoded.project.structure_count == 1)
            testing.expect(t, decoded.project.structures[0].height == 6)
            testing.expect(t, decoded.seeds == source.seeds)
        }

        truncated, truncated_error, truncated_ok := map_artifact_decode(first[:MAP_ARTIFACT_HEADER_SIZE - 1])
        _ = truncated
        defer map_artifact_error_dispose(&truncated_error)
        testing.expect(t, !truncated_ok && truncated_error.kind == .Truncated)

        corrupt := make([]byte, len(first))
        defer delete(corrupt)
        copy(corrupt, first)
        corrupt[len(corrupt) - 1] ~= 1
        corrupt_result, corrupt_error, corrupt_ok := map_artifact_decode(corrupt)
        _ = corrupt_result
        defer map_artifact_error_dispose(&corrupt_error)
        testing.expect(t, !corrupt_ok && corrupt_error.kind == .Checksum_Mismatch)

        trailing := make([]byte, len(first) + 1)
        defer delete(trailing)
        copy(trailing, first)
        trailing_result, trailing_error, trailing_ok := map_artifact_decode(trailing)
        _ = trailing_result
        defer map_artifact_error_dispose(&trailing_error)
        testing.expect(t, !trailing_ok && trailing_error.kind == .Trailing_Bytes)

        stale := make([]byte, len(first))
        defer delete(stale)
        copy(stale, first)
        map_artifact_put_u64(stale, 16, MAP_ARTIFACT_GENERATOR_VERSION + 1)
        stale_result, stale_error, stale_ok := map_artifact_decode(stale)
        _ = stale_result
        defer map_artifact_error_dispose(&stale_error)
        testing.expect(t, !stale_ok && stale_error.kind == .Stale_Generator)
    }

    @(test)
    map_artifact_apply_replaces_map_state_without_touching_root_state :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer {
            structure_storage_destroy(editor)
            free(editor)
        }
        editor.project.structures = make([dynamic]terrain.Structure, 1)
        editor.project.structure_count = 1
        editor.project.structures[0].id = 99
        editor.gameplay_options.sound_fx_level = .37
        editor.terrain_revision = 41
        artifact := map_artifact_test_source()
        defer map_artifact_destroy(artifact)
        error, applied := map_artifact_apply(editor, artifact)
        defer map_artifact_error_dispose(&error)
        testing.expect(t, applied)
        testing.expect(t, editor.project.structures[0].id == 1)
        testing.expect(t, artifact.project.structures == nil)
        testing.expect(t, editor.gameplay_options.sound_fx_level == .37)
        testing.expect(t, editor.terrain_revision == 42)
    }
}
