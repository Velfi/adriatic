package main

import fixture_v0018 "../packages/fixture_history/v0018"
import hs "zelda_engine:hs"
import terrain "../packages/terrain"
import "base:runtime"
import "core:mem"
import "core:testing"

when ODIN_TEST {
    fixture_migration_v0018_to_v0019_payload :: proc(t: ^testing.T, paint_byte: u8, structure_count := 1) -> []byte {
        source := fixture_editor_test_source()
        testing.expect(t, source != nil)
        if source == nil do return nil
        defer fixture_editor_test_source_destroy(source)
        source.project.revision = 0x1819
        source.project.next_structure_id = 0x301
        source.project.structures[0].id = 0x300
        source.marina_authored = true
        source.marina_authored_plan.seed = 0x4d415249
        source.marina_authored_plan.valid = true
        source.default_marinas[0].seed = 0x4d415249
        source.default_marinas[0].valid = true
        source.default_marina_count = 1
        source.default_map_regeneration_seeds = {0x10203040, 0x50607080}

        projection, projection_error, projected := hs.portable_encode(
            fixture_codec_value(source),
            fixture_codec_migration_portable_config(),
            context.allocator,
        )
        testing.expect(t, projected && projection_error.kind == .None)
        hs.portable_error_dispose(&projection_error)
        if !projected do return nil
        defer delete(projection)

        historical_arena: mem.Dynamic_Arena
        historical_allocator, arena_ready := fixture_migration_arena_prepare(&historical_arena, context.allocator)
        testing.expect(t, arena_ready)
        if !arena_ready do return nil
        defer mem.dynamic_arena_destroy(&historical_arena)
        historical := new(fixture_v0018.Fixture, historical_allocator)
        testing.expect(t, historical != nil)
        if historical == nil do return nil
        decode_error, decoded := hs.portable_decode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0018.Fixture)},
            projection,
            fixture_codec_portable_config(),
            historical_allocator,
        )
        testing.expect(t, decoded && decode_error.kind == .None)
        hs.portable_error_dispose(&decode_error)
        if !decoded do return nil

        historical.active_lab_scene = "dunes"
        historical.vehicle_paint_layers[1][17] = paint_byte
        historical.project.structure_count = structure_count

        payload, portable_error, encoded := hs.portable_encode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0018.Fixture)},
            fixture_codec_historical_portable_config(),
            context.allocator,
        )
        testing.expect(t, encoded && portable_error.kind == .None)
        hs.portable_error_dispose(&portable_error)
        if !encoded do return nil
        return payload
    }

    fixture_migration_v0018_to_v0019_expect_inline :: proc(
        t: ^testing.T,
        fixture: ^Fixture,
        expected_structure_id: u64,
        expected_seed: u32,
    ) {
        testing.expect(
            t,
            fixture != nil &&
            fixture.map_source.kind == .Inline &&
            len(fixture.map_source.inline_bytes) > 0 &&
            fixture.map_source.sidecar == {},
        )
        if fixture == nil || fixture.map_source.kind != .Inline || len(fixture.map_source.inline_bytes) == 0 do return

        artifact, map_error, decoded := map_artifact_decode(fixture.map_source.inline_bytes[:])
        defer map_artifact_error_dispose(&map_error)
        testing.expect(t, decoded && map_error.kind == .None)
        if !decoded do return
        defer map_artifact_destroy(artifact)

        testing.expect(
            t,
            artifact.project.structure_count == 1 &&
            artifact.project.structures[0].id == expected_structure_id &&
            artifact.seeds[0] == expected_seed &&
            artifact.marina_authored,
        )
    }

    @(test)
    fixture_migration_v0018_to_v0019_captures_inline_map_discards_paint_and_chains_v1 :: proc(t: ^testing.T) {
        payload := fixture_migration_v0018_to_v0019_payload(t, 0xa5)
        testing.expect(t, payload != nil)
        if payload == nil do return
        defer delete(payload)
        payload_snapshot := fixture_codec_test_copy(payload)
        defer delete(payload_snapshot)

        result, migration_error, migrated := fixture_migration_run(
            payload,
            18,
            FIXTURE_SCHEMA_VERSION,
            runtime.default_allocator(),
        )
        defer fixture_migration_error_dispose(&migration_error)
        defer fixture_migration_result_dispose(&result)
        testing.expect(t, migrated && migration_error.kind == .None)
        testing.expect(t, fixture_codec_test_bytes_equal(payload, payload_snapshot))
        if !migrated do return
        fixture_migration_v0018_to_v0019_expect_inline(t, result.fixture, 0x300, 0x10203040)
        testing.expect(t, result.fixture.lab.kind == .None && result.fixture.sdf_obstacle_count == 0)

        alternate_payload := fixture_migration_v0018_to_v0019_payload(t, 0x3c)
        testing.expect(t, alternate_payload != nil)
        if alternate_payload != nil {
            defer delete(alternate_payload)
            alternate, alternate_error, alternate_ok := fixture_migration_run(
                alternate_payload,
                18,
                FIXTURE_SCHEMA_VERSION,
                runtime.default_allocator(),
            )
            defer fixture_migration_error_dispose(&alternate_error)
            defer fixture_migration_result_dispose(&alternate)
            testing.expect(t, alternate_ok && alternate_error.kind == .None)
            if alternate_ok {
                encoded, encoded_error, encoded_ok := fixture_codec_encode(result.fixture, context.allocator)
                defer fixture_codec_error_dispose(&encoded_error)
                defer if encoded_ok do delete(encoded)
                alternate_encoded, alternate_encoded_error, alternate_encoded_ok := fixture_codec_encode(
                    alternate.fixture,
                    context.allocator,
                )
                defer fixture_codec_error_dispose(&alternate_encoded_error)
                defer if alternate_encoded_ok do delete(alternate_encoded)
                testing.expect(t, encoded_ok && alternate_encoded_ok)
                if encoded_ok && alternate_encoded_ok do testing.expect(t, fixture_codec_test_bytes_equal(encoded, alternate_encoded))
            }
        }

        chained_payload, chained_payload_ok := fixture_migration_test_historical_payload(t)
        testing.expect(t, chained_payload_ok)
        if !chained_payload_ok do return
        defer delete(chained_payload)
        chained, chained_error, chained_ok := fixture_migration_run(
            chained_payload,
            1,
            FIXTURE_SCHEMA_VERSION,
            runtime.default_allocator(),
        )
        defer fixture_migration_error_dispose(&chained_error)
        defer fixture_migration_result_dispose(&chained)
        testing.expect(t, chained_ok && chained_error.kind == .None)
        if chained_ok do fixture_migration_v0018_to_v0019_expect_inline(t, chained.fixture, 0x1111, terrain.DEFAULT_ISLAND_SEEDS[0])

        registry := fixture_migration_production_registry()
        testing.expect(
            t,
            len(registry.steps) == FIXTURE_SCHEMA_VERSION - 1 &&
            registry.steps[17].from_version == 18 &&
            registry.steps[17].to_version == 19 &&
            registry.steps[17].wrapper == fixture_migration_step_v0018_to_v0019,
        )
    }

    @(test)
    fixture_migration_v0018_to_v0019_rejects_invalid_project_structure_count :: proc(t: ^testing.T) {
        source := fixture_editor_test_source()
        testing.expect(t, source != nil)
        if source == nil do return
        defer fixture_editor_test_source_destroy(source)
        original_count := source.project.structure_count
        original_inline_count := len(source.map_source.inline_bytes)
        direct_invalid_counts := [?]int{-1, len(source.project.structures) + 1}
        for structure_count in direct_invalid_counts {
            source.project.structure_count = structure_count
            direct_error := fixture_v0019_apply_map_source("", source, context.allocator)
            testing.expect(t, direct_error.kind == .Invalid_Source)
            testing.expect(t, source.project.structure_count == structure_count)
            testing.expect(t, len(source.map_source.inline_bytes) == original_inline_count)
            fixture_migration_error_dispose(&direct_error)
        }
        source.project.structure_count = original_count

        invalid_counts := [?]int{-1, 2}
        for structure_count in invalid_counts {
            payload := fixture_migration_v0018_to_v0019_payload(t, 0, structure_count)
            testing.expect(t, payload != nil)
            if payload == nil do continue
            defer delete(payload)
            snapshot := fixture_codec_test_copy(payload)
            defer delete(snapshot)

            result, migration_error, migrated := fixture_migration_run(
                payload,
                18,
                FIXTURE_SCHEMA_VERSION,
                runtime.default_allocator(),
            )
            testing.expect(
                t,
                !migrated &&
                migration_error.kind == .Step_Failure &&
                migration_error.change_id == "field-add:adriatic:src.Fixture.map_source" &&
                fixture_migration_result_empty(&result) &&
                fixture_codec_test_bytes_equal(payload, snapshot),
            )
            fixture_migration_error_dispose(&migration_error)
            fixture_migration_result_dispose(&result)
        }
    }
}
