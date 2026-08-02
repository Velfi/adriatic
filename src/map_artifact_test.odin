package main

import terrain "../packages/terrain"
import "core:os"
import "core:path/filepath"
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
        artifact.project.river_water_splines[0].point_count = 1
        artifact.project.river_water_splines[0].points[0] = {
            position    = {12, -34},
            water_level = 7.5,
            width       = 4.25,
        }
        artifact.river_water_splines = artifact.project.river_water_splines
        artifact.project.structures = make([dynamic]terrain.Structure, 1)
        artifact.project.structure_count = 1
        artifact.project.structures[0] = {
            id     = 1,
            width  = 4,
            depth  = 5,
            height = 6,
            color  = {1, 2, 3, 255},
            kind   = .Rock,
        }
        for &level, index in artifact.project.levels {
            level.cell_size = terrain.FINE_CELL_SIZE * f32(u32(1) << u32(index))
            level.origin_x = -100
            level.origin_z = -100
        }
        artifact.default_marina_count = 0
        return artifact
    }

    map_artifact_fixture_test_destroy :: proc(fixture: ^Fixture) {
        if fixture == nil do return
        fixture_storage_destroy(fixture)
        free(fixture)
    }

    map_artifact_fixture_test_source :: proc() -> ^Fixture {
        fixture := new(Fixture)
        fixture.project.revision = 17
        fixture.project.island_transforms = terrain.default_island_transforms()
        fixture.project.island_transforms[1].current_x = 1800
        fixture.project.island_transforms[1].current_z = 2200
        fixture.project.sea_level = f32(2.5)
        fixture.project.next_structure_id = 8
        fixture.project.structures = make([dynamic]terrain.Structure, 1)
        fixture.project.structure_count = 1
        fixture.project.structures[0] = {
            id       = 7,
            center_x = 12,
            center_z = -18,
            width    = 4,
            depth    = 5,
            height   = 6,
            kind     = .Rock,
        }
        fixture.project.city_density[11] = 12
        fixture.project.climbing_leaf_density[13] = 14
        for &level, index in fixture.project.levels {
            level.cell_size = terrain.FINE_CELL_SIZE * f32(u32(1) << u32(index))
            level.origin_x = -100
            level.origin_z = -100
        }
        fixture.project.levels[0].heights[9] = f32(3.75)

        fixture.settlement_plan.valid = true
        fixture.settlement_plan.neighborhood_count = 2
        fixture.settlement_plan.route_count = 3

        fixture.marina_authored = true
        fixture.marina_authored_plan.seed = 0x4d415249
        fixture.marina_authored_plan.layout_seed = 0x13579bdf
        fixture.marina_authored_plan.valid = true
        fixture.harbor_authored_plan.seed = 0x48415242
        fixture.harbor_authored_plan.generation_version = 2
        fixture.harbor_authored_plan.valid = true
        fixture.harbor_authored_intervention.seed = 0x494e5445
        fixture.harbor_authored_intervention.valid = true

        fixture.farms[0] = {
            origin_x = 101,
            origin_z = -202,
            yaw      = .35,
            scale_x  = 1.25,
            scale_z  = .8,
        }
        fixture.farms[0].plan.width = 25
        fixture.farms[0].plan.height = 19
        fixture.farms[0].plan.tradition = .Ancient_Enclosure
        fixture.farm_count = 1
        fixture.wrecks[0].seed = 0x57524543
        fixture.wrecks[0].origin_x = 29
        fixture.wrecks[0].scale = 1.5
        fixture.wreck_count = 1

        fixture.default_marinas[0].seed = 0x4d415249
        fixture.default_marinas[0].valid = true
        fixture.default_harbors[0].seed = 0x48415242
        fixture.default_harbors[0].valid = true
        fixture.default_harbor_interventions[0].seed = 0x494e5445
        fixture.default_harbor_interventions[0].valid = true
        fixture.default_marina_islands[0] = .East
        fixture.default_marina_count = 1

        fixture.greek_placements[0] = {
            asset_index = 3,
            x           = 41,
            z           = -42,
            base_y      = 4,
            rotation    = .5,
            scale       = 1.75,
        }
        fixture.greek_placement_count = 1
        return fixture
    }

    @(test)
    map_artifact_sidecar_descriptor_contract :: proc(t: ^testing.T) {
        artifact := map_artifact_test_source()
        defer map_artifact_destroy(artifact)
        encoded, encode_error, encoded_ok := map_artifact_encode(artifact)
        defer delete(encoded)
        defer map_artifact_error_dispose(&encode_error)
        testing.expect(t, encoded_ok)
        if !encoded_ok do return
        sidecar, derived := fixture_map_sidecar_derive(encoded)
        testing.expect(t, derived)
        testing.expect(t, fixture_map_sidecar_valid(sidecar))
        testing.expect(t, sidecar.basename_count == FIXTURE_MAP_SIDECAR_BASENAME_LENGTH)
        testing.expect(t, sidecar.basename_count == 81)
        testing.expect(
            t,
            sidecar.basename[0] == 'm' &&
            sidecar.basename[1] == 'a' &&
            sidecar.basename[2] == 'p' &&
            sidecar.basename[3] == '-',
        )
        testing.expect(t, sidecar.basename[sidecar.basename_count - 13] == '.')

        repeated, repeated_ok := fixture_map_sidecar_derive(encoded)
        testing.expect(t, repeated_ok)
        testing.expect(t, sidecar.encoded_sha256 == repeated.encoded_sha256)
        testing.expect(
            t,
            slice.equal(sidecar.basename[:sidecar.basename_count], repeated.basename[:repeated.basename_count]),
        )
        testing.expect(t, fixture_map_sidecar_matches_encoded(sidecar, encoded))

        mismatched := make([]byte, len(encoded))
        defer delete(mismatched)
        copy(mismatched, encoded)
        mismatched[len(mismatched) - 1] ~= 1
        testing.expect(t, !fixture_map_sidecar_matches_encoded(sidecar, mismatched))

        empty, empty_ok := fixture_map_sidecar_derive(nil)
        testing.expect(t, !empty_ok && empty == {})

        inline_bytes := make([dynamic]u8, len(encoded))
        defer delete(inline_bytes)
        copy(inline_bytes[:], encoded)
        source := Fixture_Map_Source {
            kind         = .Inline,
            inline_bytes = inline_bytes,
        }
        testing.expect(t, fixture_map_source_valid(source))
        source = {
            kind    = .Sidecar,
            sidecar = sidecar,
        }
        testing.expect(t, fixture_map_source_valid(source))
        legacy := sidecar
        legacy.format_version = MAP_ARTIFACT_LEGACY_FORMAT_VERSION
        legacy.generator_version = MAP_ARTIFACT_INITIAL_GENERATOR_VERSION
        testing.expect(t, fixture_map_sidecar_valid(legacy))
        testing.expect(t, !fixture_map_sidecar_matches_encoded(legacy, encoded))
        legacy.generator_version = MAP_ARTIFACT_GENERATOR_VERSION
        testing.expect(t, !fixture_map_sidecar_valid(legacy))
        source.inline_bytes = inline_bytes
        testing.expect(t, !fixture_map_source_valid(source))
    }

    @(test)
    map_artifact_committed_dunes_sidecar_remains_compatible :: proc(t: ^testing.T) {
        fixture_bytes, fixture_read_error := os.read_entire_file("fixtures/labs/dunes.fixture", context.allocator)
        testing.expect(t, fixture_read_error == nil)
        if fixture_read_error != nil do return
        defer delete(fixture_bytes)

        decoded, decode_error, decoded_ok := fixture_codec_decode(fixture_bytes)
        testing.expect(t, decoded_ok && decode_error.kind == .None)
        fixture_codec_error_dispose(&decode_error)
        if !decoded_ok do return
        defer fixture_migration_result_dispose(&decoded)
        sidecar := decoded.fixture.map_source.sidecar
        testing.expect(
            t,
            decoded.fixture.map_source.kind == .Sidecar &&
                fixture_map_sidecar_valid(sidecar) &&
                sidecar.format_version == MAP_ARTIFACT_LEGACY_FORMAT_VERSION &&
                sidecar.generator_version == MAP_ARTIFACT_INITIAL_GENERATOR_VERSION,
        )

        sidecar_path, resolved := fixture_map_sidecar_resolve("fixtures/labs/dunes.fixture", sidecar)
        testing.expect(t, resolved)
        if !resolved do return
        defer delete(sidecar_path)
        sidecar_bytes, sidecar_read_error := os.read_entire_file(sidecar_path, context.allocator)
        testing.expect(t, sidecar_read_error == nil)
        if sidecar_read_error != nil do return
        defer delete(sidecar_bytes)
        derived, derived_ok := fixture_map_sidecar_derive(sidecar_bytes)
        testing.expect(t, derived_ok && derived == sidecar)
        testing.expect(t, fixture_map_sidecar_matches_encoded(sidecar, sidecar_bytes))

        artifact, map_error, decoded_map := map_artifact_decode(sidecar_bytes)
        testing.expect(t, decoded_map && map_error.kind == .None)
        map_artifact_error_dispose(&map_error)
        if !decoded_map do return
        defer map_artifact_destroy(artifact)
        testing.expect(t, artifact.generator_version == MAP_ARTIFACT_GENERATOR_VERSION)
    }

    @(test)
    map_artifact_sidecar_rejects_noncanonical_names_and_resolves_only_siblings :: proc(t: ^testing.T) {
        artifact := map_artifact_test_source()
        defer map_artifact_destroy(artifact)
        encoded, encode_error, encoded_ok := map_artifact_encode(artifact)
        defer delete(encoded)
        defer map_artifact_error_dispose(&encode_error)
        testing.expect(t, encoded_ok)
        if !encoded_ok do return
        sidecar, derived := fixture_map_sidecar_derive(encoded)
        testing.expect(t, derived)
        if !derived do return

        malformed := sidecar
        malformed.basename_count = 0
        testing.expect(t, !fixture_map_sidecar_valid(malformed))
        malformed = sidecar
        malformed.basename[0] = '/'
        testing.expect(t, !fixture_map_sidecar_valid(malformed))
        rejected, rejected_ok := fixture_map_sidecar_resolve("/fixture-playground/scene.fixture", malformed)
        testing.expect(t, !rejected_ok && len(rejected) == 0)
        malformed = sidecar
        malformed.basename[0] = '.'
        testing.expect(t, !fixture_map_sidecar_valid(malformed))
        malformed = sidecar
        malformed.basename[4] = 'A'
        testing.expect(t, !fixture_map_sidecar_valid(malformed))
        malformed = sidecar
        malformed.format_version += 1
        testing.expect(t, !fixture_map_sidecar_valid(malformed))
        malformed = sidecar
        malformed.encoded_sha256 = {}
        fixture_map_sidecar_set_basename(&malformed)
        testing.expect(t, !fixture_map_sidecar_valid(malformed))

        fixture_path := "/fixture-playground/scene.fixture"
        resolved, resolved_ok := fixture_map_sidecar_resolve(fixture_path, sidecar)
        testing.expect(t, resolved_ok)
        if !resolved_ok do return
        defer delete(resolved)
        expected, expected_error := filepath.join(
            []string{os.dir(fixture_path), string(sidecar.basename[:sidecar.basename_count])},
            context.temp_allocator,
        )
        testing.expect(t, expected_error == nil)
        testing.expect(t, resolved == expected)
        testing.expect(t, strings.has_prefix(resolved, os.dir(fixture_path)))
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
            testing.expect_value(t, decoded.river_water_splines, source.river_water_splines)
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
        testing.expect(t, len(artifact.project.structures) == 0)
        testing.expect(t, cap(artifact.project.structures) == 0)
        testing.expect(t, editor.gameplay_options.sound_fx_level == .37)
        testing.expect(t, editor.terrain_revision == 42)
    }

    @(test)
    map_artifact_fixture_helpers_round_trip_map_state :: proc(t: ^testing.T) {
        source := map_artifact_fixture_test_source()
        defer map_artifact_fixture_test_destroy(source)
        append(&source.project.terrain_pages, terrain.Terrain_Page{level = 0, page_x = 1, page_z = 2})
        source.project.terrain_pages[0].heights[3] = 6.25
        chunk := terrain.Bathymetry_Chunk{
            chunk_x = -3,
            chunk_z = 4,
            owner = .West,
            heights = make([dynamic]f16, terrain.BATHYMETRY_CHUNK_SAMPLES),
            material = make([dynamic]i8, terrain.BATHYMETRY_CHUNK_SAMPLES),
        }
        chunk.heights[5] = -7
        append(&source.project.bathymetry_chunks, chunk)
        terrain.terrain_sampling_lookup_rebuild(&source.project)
        seeds := terrain.DEFAULT_ISLAND_SEEDS
        seeds[0] = 0x10203040
        seeds[1] = 0x50607080
        artifact, capture_error, captured := map_artifact_capture_fixture(source, seeds)
        defer map_artifact_error_dispose(&capture_error)
        testing.expect(t, captured)
        if !captured do return
        defer map_artifact_destroy(artifact)
        testing.expect_value(t, len(source.project.terrain_pages), 1)
        testing.expect_value(t, source.project.terrain_pages[0].heights[3], f32(6.25))
        testing.expect_value(t, len(source.project.bathymetry_chunks), 1)
        testing.expect_value(t, f32(source.project.bathymetry_chunks[0].heights[5]), f32(-7))
        testing.expect(t, raw_data(source.project.terrain_pages) != raw_data(artifact.project.terrain_pages))
        testing.expect(t, raw_data(source.project.bathymetry_chunks[0].heights) != raw_data(artifact.project.bathymetry_chunks[0].heights))
        source.project.structures[0].id = 99

        encoded, encode_error, encoded_ok := map_artifact_encode(artifact)
        defer delete(encoded)
        defer map_artifact_error_dispose(&encode_error)
        testing.expect(t, encoded_ok)
        if !encoded_ok do return
        decoded, decode_error, decoded_ok := map_artifact_decode(encoded)
        defer map_artifact_error_dispose(&decode_error)
        testing.expect(t, decoded_ok)
        if !decoded_ok do return
        defer map_artifact_destroy(decoded)

        target := new(Fixture)
        defer map_artifact_fixture_test_destroy(target)
        target.project.structures = make([dynamic]terrain.Structure, 1)
        target.project.structure_count = 1
        target.project.structures[0].id = 99
        target.camera.yaw_radians = .99
        target.camera.distance = 77
        apply_error, applied := map_artifact_apply_fixture(target, decoded)
        defer map_artifact_error_dispose(&apply_error)
        testing.expect(t, applied)
        if !applied do return

        testing.expect(t, len(decoded.project.structures) == 0)
        testing.expect(t, cap(decoded.project.structures) == 0)
        testing.expect(t, target.project.structure_count == 1)
        testing.expect(t, target.project.structures[0].id == 7)
        testing.expect(t, target.project.levels[0].heights[9] == f32(3.75))
        testing.expect(t, target.project.city_density[11] == 12)
        testing.expect(t, target.project.climbing_leaf_density[13] == 14)
        testing.expect(t, target.project.island_transforms[1].current_x == 1800)
        testing.expect(t, target.project.island_transforms[1].current_z == 2200)
        testing.expect(t, target.project.river_water_splines[0].point_count > 1)
        testing.expect(t, target.project.river_water_splines[1].point_count > 1)
        testing.expect(t, target.settlement_plan.valid)
        testing.expect(t, target.settlement_plan.neighborhood_count == 2)
        testing.expect(t, target.settlement_plan.route_count == 3)
        testing.expect(t, target.marina_authored && target.marina_authored_plan.seed == 0x4d415249)
        testing.expect(t, target.harbor_authored_plan.seed == 0x48415242)
        testing.expect(t, target.harbor_authored_intervention.seed == 0x494e5445)
        testing.expect(t, target.farm_count == 1 && target.farms[0].plan.width == 25)
        testing.expect(t, target.wreck_count == 1 && target.wrecks[0].seed == 0x57524543)
        testing.expect(t, target.default_marina_count == 1)
        testing.expect(t, target.default_marinas[0].seed == 0x4d415249)
        testing.expect(t, target.default_harbors[0].seed == 0x48415242)
        testing.expect(t, target.default_harbor_interventions[0].seed == 0x494e5445)
        testing.expect(t, target.default_marina_islands[0] == .East)
        testing.expect(t, target.greek_placement_count == 1 && target.greek_placements[0].asset_index == 3)
        testing.expect(t, target.camera.yaw_radians == .99 && target.camera.distance == 77)
    }

    @(test)
    map_artifact_legacy_default_map_initializes_island_transforms :: proc(t: ^testing.T) {
        artifact, decode_error, decoded := map_artifact_read("assets/maps/default.adriatic-map")
        defer map_artifact_error_dispose(&decode_error)
        testing.expect(t, decoded)
        if !decoded do return
        defer map_artifact_destroy(artifact)
        defaults := terrain.default_island_transforms()
        testing.expect_value(t, artifact.project.island_transforms, defaults)
        testing.expect_value(t, artifact.generator_version, MAP_ARTIFACT_GENERATOR_VERSION)
    }

    @(test)
    map_artifact_fixture_apply_rejects_invalid_without_mutation :: proc(t: ^testing.T) {
        fixture := map_artifact_fixture_test_source()
        defer map_artifact_fixture_test_destroy(fixture)
        fixture.project.structures[0].id = 99
        fixture.camera.yaw_radians = .99
        artifact := map_artifact_test_source()
        defer map_artifact_destroy(artifact)
        artifact.project.levels[0].cell_size = 0
        error, applied := map_artifact_apply_fixture(fixture, artifact)
        defer map_artifact_error_dispose(&error)
        testing.expect(t, !applied && error.kind == .Invalid_State)
        testing.expect(t, fixture.project.structures[0].id == 99)
        testing.expect(t, fixture.settlement_plan.neighborhood_count == 2)
        testing.expect(t, fixture.camera.yaw_radians == .99)
        testing.expect(t, artifact.project.structures != nil)
    }
}
