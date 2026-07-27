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
    Schema_Mismatch,
    Migration,
}

Fixture_Codec_Error :: struct {
    kind:      Fixture_Codec_Error_Kind,
    portable:  hs.Portable_Error,
    container: fixture_file.Fixture_Container_Error,
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
    error.migration = {}
}

fixture_codec_portable_config :: proc() -> hs.Portable_Config {
    config := hs.portable_default_config()
    config.exclusion_tag = "fixture"
    return config
}

fixture_codec_historical_portable_config :: proc() -> hs.Portable_Config {
    config := fixture_codec_portable_config()
    config.exact_schema = true
    return config
}

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

    container_data, container_error, container_ok := fixture_file.fixture_container_encode(
        portable,
        u32(FIXTURE_SCHEMA_VERSION),
        alloc = alloc,
    )
    if !container_ok {
        return nil, {kind = .Container_Encode, container = container_error}, false
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
