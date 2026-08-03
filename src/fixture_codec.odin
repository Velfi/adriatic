package main

import fixture_file "../packages/fixture_file"
import hs "../packages/hs"
import "core:mem"

Fixture_Codec_Error_Kind :: enum {
    None,
    Invalid_Argument,
    Portable_Encode,
    Container_Encode,
    Container_Decode,
    Sectioned_Container_Encode,
    Sectioned_Container_Decode,
    Schema_Mismatch,
    Migration,
}

Fixture_Codec_Error :: struct {
    kind:      Fixture_Codec_Error_Kind,
    portable:  hs.Portable_Error,
    container: fixture_file.Fixture_Container_Error,
    sectioned: fixture_file.Sectioned_Container_Error,
    migration: Fixture_Migration_Error,
}

fixture_codec_error_dispose :: proc(error: ^Fixture_Codec_Error) {
    if error == nil do return
    if error.kind == .Portable_Encode {
        hs.portable_error_dispose(&error.portable)
    }
    if error.kind == .Migration {
        fixture_migration_error_dispose(&error.migration)
    }
    error.kind = .None
    error.portable = {}
    error.container = {}
    error.sectioned = {}
    error.migration = {}
}

fixture_codec_portable_config :: proc() -> hs.Portable_Config {
    config := hs.portable_default_config()
    config.exclusion_tag = "fixture"
    // Inline ADRMAP data is already bounded by the portable payload ceiling,
    // but valid maps can exceed the serializer's generic 16 MiB array limit.
    config.limits.max_array_elements = config.limits.max_payload
    return config
}

fixture_codec_historical_portable_config :: proc() -> hs.Portable_Config {
    config := fixture_codec_portable_config()
    config.exact_schema = true
    return config
}

fixture_codec_migration_portable_config :: proc() -> hs.Portable_Config {
    config := fixture_codec_portable_config()
    config.retain_tag = "fixture_map"
    return config
}

// Old migration projections retain map fields until v16→17. They omit only
// v17's ADRMAP descriptor because no frozen schema knows that field.
fixture_codec_value :: proc(fixture: ^Fixture) -> any {
    return any{data = rawptr(fixture), id = typeid_of(Fixture)}
}

// Encode the current Fixture schema in memory. The caller owns successful
// container bytes and must delete them with the supplied allocator.
fixture_codec_encode :: proc(
    fixture: ^Fixture,
    alloc := context.allocator,
) -> (
    data: []byte,
    error: Fixture_Codec_Error,
    ok: bool,
) {
    if fixture == nil || alloc.procedure == nil {
        return nil, {kind = .Invalid_Argument}, false
    }
    portable, portable_error, portable_ok := hs.portable_encode(
        fixture_codec_value(fixture),
        fixture_codec_portable_config(),
        alloc,
    )
    if !portable_ok {
        return nil, {kind = .Portable_Encode, portable = portable_error}, false
    }
    defer delete(portable, alloc)

    sections := []fixture_file.Section_Input{{key = {kind = .Core}, bytes = portable}}
    container_data, sectioned_error, container_ok := fixture_file.sectioned_container_encode(
        .Fixture,
        u32(FIXTURE_SCHEMA_VERSION),
        0,
        sections,
        alloc,
    )
    if !container_ok {
        return nil, {kind = .Sectioned_Container_Encode, sectioned = sectioned_error}, false
    }
    return container_data, {}, true
}

// Decode a versioned fixture into an owned migration result. The caller owns
// successful state through fixture_migration_result_dispose.
fixture_codec_decode :: proc(
    data: []byte,
    alloc := context.allocator,
) -> (
    result: Fixture_Migration_Result,
    error: Fixture_Codec_Error,
    ok: bool,
) {
    if alloc.procedure == nil {
        return {}, {kind = .Invalid_Argument}, false
    }
    sectioned_magic := fixture_file.Sectioned_Container_Magic
    sectioned := len(data) >= len(sectioned_magic)
    if sectioned {
        for value, index in sectioned_magic {
            if data[index] != value {
                sectioned = false
                break
            }
        }
    }
    if sectioned {
        if len(data) < fixture_file.Sectioned_Container_Header_Size {
            return {}, {kind = .Sectioned_Container_Decode, sectioned = {kind = .Truncated, offset = len(data)}}, false
        }
        section_count, count_error, count_ok := fixture_file.sectioned_container_directory_count(data)
        if !count_ok {
            return {}, {kind = .Sectioned_Container_Decode, sectioned = count_error}, false
        }
        entries := make([]fixture_file.Section_Entry, section_count, context.temp_allocator)
        view, sectioned_error, container_ok := fixture_file.sectioned_container_decode(data, entries)
        if !container_ok {
            return {}, {kind = .Sectioned_Container_Decode, sectioned = sectioned_error}, false
        }
        if view.artifact_kind != .Fixture {
            return {}, {kind = .Sectioned_Container_Decode, sectioned = {kind = .Invalid_Artifact, offset = 10}}, false
        }
        payload, found := fixture_file.sectioned_container_section(&view, {kind = .Core})
        if !found {
            return {}, {kind = .Sectioned_Container_Decode, sectioned = {kind = .Invalid_Directory, offset = 24}}, false
        }
        if view.schema_version < 1 || view.schema_version > u32(FIXTURE_SCHEMA_VERSION) {
            return {}, {kind = .Schema_Mismatch}, false
        }
        migration_result, migration_error, migration_ok := fixture_migration_run(
            payload,
            int(view.schema_version),
            FIXTURE_SCHEMA_VERSION,
            alloc,
        )
        if !migration_ok {
            if !fixture_migration_result_empty(&migration_result) do fixture_migration_result_dispose(&migration_result)
            return {}, {kind = .Migration, migration = migration_error}, false
        }
        return migration_result, {}, true
    }
    view, container_error, container_ok := fixture_file.fixture_container_decode(data)
    if !container_ok {
        return {}, {kind = .Container_Decode, container = container_error}, false
    }
    if view.schema_version < 1 || view.schema_version > u32(FIXTURE_SCHEMA_VERSION) {
        return {},
            {
                kind = .Schema_Mismatch,
                container = {
                    kind = .Invalid_Schema_Version,
                    offset = 12,
                    message = "fixture schema version is unsupported",
                },
            },
            false
    }
    migration_result, migration_error, migration_ok := fixture_migration_run(
        view.payload,
        int(view.schema_version),
        FIXTURE_SCHEMA_VERSION,
        alloc,
    )
    if !migration_ok {
        if !fixture_migration_result_empty(&migration_result) {
            fixture_migration_result_dispose(&migration_result)
        }
        return {}, {kind = .Migration, migration = migration_error}, false
    }
    return migration_result, {}, true
}
