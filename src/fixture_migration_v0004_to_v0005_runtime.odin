package main

import fixture_v0001 "../packages/fixture_history/v0001"
import fixture_v0002 "../packages/fixture_history/v0002"
import fixture_v0003 "../packages/fixture_history/v0003"
import fixture_v0004 "../packages/fixture_history/v0004"
import "core:mem"
import hs "zelda_engine:hs"

Fixture_Migration_V0004_Legacy_Basis :: struct {
    forward: [3]f32,
    up:      [3]f32,
    right:   [3]f32,
}

Fixture_Migration_V0004_Legacy_Oracle :: struct {
    postale_angular_velocity:   [3]f32,
    postale_body_basis:         Fixture_Migration_V0004_Legacy_Basis,
    postale_spawn_basis:        Fixture_Migration_V0004_Legacy_Basis,
    libellula_angular_velocity: [3]f32,
    libellula_body_basis:       Fixture_Migration_V0004_Legacy_Basis,
    libellula_spawn_basis:      Fixture_Migration_V0004_Legacy_Basis,
    aircraft_active:            int,
}

fixture_migration_v0004_legacy_vec3 :: proc(value: $T) -> [3]f32 {
    return {value[0], value[1], value[2]}
}

fixture_migration_v0004_legacy_basis :: proc(value: $T) -> Fixture_Migration_V0004_Legacy_Basis {
    return {
        forward = fixture_migration_v0004_legacy_vec3(value.forward),
        up = fixture_migration_v0004_legacy_vec3(value.up),
        right = fixture_migration_v0004_legacy_vec3(value.right),
    }
}

fixture_migration_v0004_legacy_oracle :: proc(source: ^$T) -> Fixture_Migration_V0004_Legacy_Oracle {
    return {
        postale_angular_velocity = fixture_migration_v0004_legacy_vec3(source.postale.body.angular_velocity),
        postale_body_basis = fixture_migration_v0004_legacy_basis(source.postale.body.basis),
        postale_spawn_basis = fixture_migration_v0004_legacy_basis(source.postale.spawn_basis),
        libellula_angular_velocity = fixture_migration_v0004_legacy_vec3(source.libellula.body.angular_velocity),
        libellula_body_basis = fixture_migration_v0004_legacy_basis(source.libellula.body.basis),
        libellula_spawn_basis = fixture_migration_v0004_legacy_basis(source.libellula.spawn_basis),
        aircraft_active = int(source.aircraft.active),
    }
}

fixture_migration_v0004_copy_legacy_vec3 :: proc(destination: ^$T, source: [3]f32) {
    for &component, index in destination {
        component = source[index]
    }
}

fixture_migration_v0004_copy_legacy_basis :: proc(destination: ^$T, source: Fixture_Migration_V0004_Legacy_Basis) {
    fixture_migration_v0004_copy_legacy_vec3(&destination.forward, source.forward)
    fixture_migration_v0004_copy_legacy_vec3(&destination.up, source.up)
    fixture_migration_v0004_copy_legacy_vec3(&destination.right, source.right)
}

fixture_migration_v0004_decode :: proc(
    value: any,
    payload: []byte,
    exact_schema: bool,
    allocator: mem.Allocator,
    fallback: Fixture_Migration_Error_Kind,
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

fixture_migration_v0004_authenticate_source :: proc(
    payload: []byte,
    source_version: int,
    allocator: mem.Allocator,
) -> (
    oracle: Fixture_Migration_V0004_Legacy_Oracle,
    error: Fixture_Migration_Error,
) {
    switch source_version {
    case 1:
        source := new(fixture_v0001.Fixture, allocator)
        if source == nil do return {}, {kind = .Out_Of_Memory}
        error = fixture_migration_v0004_decode(
            any{data = rawptr(source), id = typeid_of(fixture_v0001.Fixture)},
            payload,
            true,
            allocator,
            .Historical_Decode,
        )
        if error.kind != .None do return {}, error
        return fixture_migration_v0004_legacy_oracle(source), {}
    case 2:
        source := new(fixture_v0002.Fixture, allocator)
        if source == nil do return {}, {kind = .Out_Of_Memory}
        error = fixture_migration_v0004_decode(
            any{data = rawptr(source), id = typeid_of(fixture_v0002.Fixture)},
            payload,
            true,
            allocator,
            .Historical_Decode,
        )
        if error.kind != .None do return {}, error
        return fixture_migration_v0004_legacy_oracle(source), {}
    case 3:
        source := new(fixture_v0003.Fixture, allocator)
        if source == nil do return {}, {kind = .Out_Of_Memory}
        error = fixture_migration_v0004_decode(
            any{data = rawptr(source), id = typeid_of(fixture_v0003.Fixture)},
            payload,
            true,
            allocator,
            .Historical_Decode,
        )
        if error.kind != .None do return {}, error
        return fixture_migration_v0004_legacy_oracle(source), {}
    case:
        return {}, {kind = .Invalid_Argument}
    }
}

fixture_migration_v0004_overlay_legacy_oracle :: proc(
    historical: ^fixture_v0004.Fixture,
    #by_ptr oracle: Fixture_Migration_V0004_Legacy_Oracle,
) {
    fixture_migration_v0004_copy_legacy_vec3(
        &historical.postale.body.angular_velocity,
        oracle.postale_angular_velocity,
    )
    fixture_migration_v0004_copy_legacy_basis(&historical.postale.body.basis, oracle.postale_body_basis)
    fixture_migration_v0004_copy_legacy_basis(&historical.postale.spawn_basis, oracle.postale_spawn_basis)
    fixture_migration_v0004_copy_legacy_vec3(
        &historical.libellula.body.angular_velocity,
        oracle.libellula_angular_velocity,
    )
    fixture_migration_v0004_copy_legacy_basis(&historical.libellula.body.basis, oracle.libellula_body_basis)
    fixture_migration_v0004_copy_legacy_basis(&historical.libellula.spawn_basis, oracle.libellula_spawn_basis)

    historical.rondine.body = {}
    historical.rondine.vehicle.locked = true
    historical.rondine_visible = false
    switch oracle.aircraft_active {
    case 0:
        historical.aircraft.active = .Postale
    case 1:
        historical.aircraft.active = .Libellula
    case 2:
        historical.aircraft.active = .Libellula_Mk2
    }
}

fixture_migration_v0004_project_chained_source :: proc(
    payload: []byte,
    source_version: int,
    tentative: ^Fixture,
    historical: ^fixture_v0004.Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    oracle, authentication_error := fixture_migration_v0004_authenticate_source(payload, source_version, allocator)
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

    decode_error := fixture_migration_v0004_decode(
        any{data = rawptr(historical), id = typeid_of(fixture_v0004.Fixture)},
        projected_payload,
        false,
        allocator,
        .Step_Failure,
    )
    if decode_error.kind != .None do return decode_error
    fixture_migration_v0004_overlay_legacy_oracle(historical, oracle)
    return {}
}

fixture_migration_v0004_transaction_arena_valid :: proc(arena: ^mem.Dynamic_Arena) -> bool {
    return arena != nil && arena.block_allocator.procedure != nil
}

fixture_migration_step_v0004_to_v0005 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       step_context.source_version < 1 ||
       step_context.source_version > 4 ||
       step_context.target_version < 5 ||
       step_context.step_from_version != 4 ||
       step_context.step_to_version != 5 ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }
    transaction_arena := cast(^mem.Dynamic_Arena)step_context.transaction_allocator.data
    if !fixture_migration_v0004_transaction_arena_valid(transaction_arena) {
        return {kind = .Invalid_Argument}
    }

    historical_arena: mem.Dynamic_Arena
    historical_allocator, arena_ok := fixture_migration_arena_prepare(
        &historical_arena,
        transaction_arena.block_allocator,
    )
    if !arena_ok do return {kind = .Out_Of_Memory}
    defer mem.dynamic_arena_destroy(&historical_arena)

    historical := new(fixture_v0004.Fixture, historical_allocator)
    if historical == nil do return {kind = .Out_Of_Memory}
    if step_context.source_version == 4 {
        decode_error := fixture_migration_v0004_decode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0004.Fixture)},
            step_context.source_payload,
            true,
            historical_allocator,
            .Historical_Decode,
        )
        if decode_error.kind != .None do return decode_error
    } else {
        projection_error := fixture_migration_v0004_project_chained_source(
            step_context.source_payload,
            step_context.source_version,
            step_context.tentative,
            historical,
            historical_allocator,
        )
        if projection_error.kind != .None do return projection_error
    }

    return fixture_migrate_v0004_to_v0005(historical^, step_context.tentative, step_context.transaction_allocator)
}
