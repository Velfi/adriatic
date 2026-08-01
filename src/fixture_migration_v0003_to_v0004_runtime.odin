package main

import fixture_v0001 "../packages/fixture_history/v0001"
import fixture_v0002 "../packages/fixture_history/v0002"
import fixture_v0003 "../packages/fixture_history/v0003"
import hs "../packages/hs"
import "core:mem"

fixture_migration_v0003_decode_historical :: proc(
    value: any,
    payload: []byte,
    exact_schema: bool,
    allocator: mem.Allocator,
    fallback := Fixture_Migration_Error_Kind.Historical_Decode,
) -> Fixture_Migration_Error {
    config := fixture_codec_portable_config()
    config.exact_schema = exact_schema
    portable_error, portable_ok := hs.portable_decode(value, payload, config, allocator)
    if !portable_ok {
        error_kind := fixture_migration_decode_kind(portable_error, fallback)
        hs.portable_error_dispose(&portable_error)
        return {kind = error_kind}
    }
    hs.portable_error_dispose(&portable_error)
    return {}
}

fixture_migration_v0003_authenticate_source :: proc(
    payload: []byte,
    source_version: int,
    allocator: mem.Allocator,
) -> (
    architecture_brush_radius: f32,
    error: Fixture_Migration_Error,
) {
    switch source_version {
    case 1:
        source := new(fixture_v0001.Fixture, allocator)
        if source == nil do return 0, {kind = .Out_Of_Memory}
        error = fixture_migration_v0003_decode_historical(
            any{data = rawptr(source), id = typeid_of(fixture_v0001.Fixture)},
            payload,
            true,
            allocator,
        )
        if error.kind != .None do return 0, error
        return source.architecture_brush_radius, {}
    case 2:
        source := new(fixture_v0002.Fixture, allocator)
        if source == nil do return 0, {kind = .Out_Of_Memory}
        error = fixture_migration_v0003_decode_historical(
            any{data = rawptr(source), id = typeid_of(fixture_v0002.Fixture)},
            payload,
            true,
            allocator,
        )
        if error.kind != .None do return 0, error
        return source.architecture_brush_radius, {}
    case:
        return 0, {kind = .Invalid_Argument}
    }
}

fixture_migration_v0003_project_chained_oracle :: proc(
    payload: []byte,
    source_version: int,
    tentative: ^Fixture,
    historical: ^fixture_v0003.Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    architecture_brush_radius, authentication_error := fixture_migration_v0003_authenticate_source(
        payload,
        source_version,
        allocator,
    )
    if authentication_error.kind != .None do return authentication_error

    projected_payload, projection_error, projection_ok := hs.portable_encode(
        fixture_codec_value(tentative),
        fixture_codec_migration_portable_config(),
        allocator,
    )
    if !projection_ok {
        error_kind := fixture_migration_decode_kind(projection_error, .Step_Failure)
        hs.portable_error_dispose(&projection_error)
        return {kind = error_kind}
    }
    hs.portable_error_dispose(&projection_error)
    defer delete(projected_payload, allocator)

    projection_decode_error := fixture_migration_v0003_decode_historical(
        any{data = rawptr(historical), id = typeid_of(fixture_v0003.Fixture)},
        projected_payload,
        false,
        allocator,
        .Step_Failure,
    )
    if projection_decode_error.kind != .None do return projection_decode_error
    historical.architecture_brush_radius = architecture_brush_radius
    return {}
}

fixture_migration_step_v0003_to_v0004 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       step_context.source_version < 1 ||
       step_context.source_version > 3 ||
       step_context.target_version < 4 ||
       step_context.step_from_version != 3 ||
       step_context.step_to_version != 4 ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }
    transaction_arena := cast(^mem.Dynamic_Arena)step_context.transaction_allocator.data
    if transaction_arena == nil || transaction_arena.block_allocator.procedure == nil {
        return {kind = .Invalid_Argument}
    }

    historical_arena: mem.Dynamic_Arena
    historical_allocator, arena_ok := fixture_migration_arena_prepare(
        &historical_arena,
        transaction_arena.block_allocator,
    )
    if !arena_ok do return {kind = .Out_Of_Memory}
    defer mem.dynamic_arena_destroy(&historical_arena)

    historical := new(fixture_v0003.Fixture, historical_allocator)
    if historical == nil do return {kind = .Out_Of_Memory}
    if step_context.source_version == 3 {
        historical_error := fixture_migration_v0003_decode_historical(
            any{data = rawptr(historical), id = typeid_of(fixture_v0003.Fixture)},
            step_context.source_payload,
            true,
            historical_allocator,
        )
        if historical_error.kind != .None do return historical_error
    } else {
        projection_error := fixture_migration_v0003_project_chained_oracle(
            step_context.source_payload,
            step_context.source_version,
            step_context.tentative,
            historical,
            historical_allocator,
        )
        if projection_error.kind != .None do return projection_error
    }

    return fixture_migrate_v0003_to_v0004(historical^, step_context.tentative, step_context.transaction_allocator)
}
