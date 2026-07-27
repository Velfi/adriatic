package main

import fixture_v0001 "../packages/fixture_history/v0001"
import hs "../packages/hs"
import "core:mem"
import "core:strings"

FIXTURE_MIGRATION_ARENA_BLOCK_SIZE :: 128 * mem.Megabyte
FIXTURE_MIGRATION_ARENA_OUT_OF_BAND_SIZE :: 64 * mem.Megabyte
FIXTURE_MIGRATION_ARENA_TRACKING_CAPACITY :: 16

fixture_migration_arena_prepare :: proc(arena: ^mem.Dynamic_Arena, allocator: mem.Allocator) -> (mem.Allocator, bool) {
    if arena == nil || allocator.procedure == nil do return {}, false
    mem.dynamic_arena_init(
        arena,
        block_allocator = allocator,
        array_allocator = allocator,
        block_size = FIXTURE_MIGRATION_ARENA_BLOCK_SIZE,
        out_band_size = FIXTURE_MIGRATION_ARENA_OUT_OF_BAND_SIZE,
    )
    unused_blocks, allocation_error := make([dynamic]rawptr, 0, FIXTURE_MIGRATION_ARENA_TRACKING_CAPACITY, allocator)
    if allocation_error != nil {
        mem.dynamic_arena_destroy(arena)
        return {}, false
    }
    arena.unused_blocks = unused_blocks
    used_blocks: [dynamic]rawptr
    used_blocks, allocation_error = make([dynamic]rawptr, 0, FIXTURE_MIGRATION_ARENA_TRACKING_CAPACITY, allocator)
    if allocation_error != nil {
        mem.dynamic_arena_destroy(arena)
        return {}, false
    }
    arena.used_blocks = used_blocks
    out_band_allocations: [dynamic]rawptr
    out_band_allocations, allocation_error = make(
        [dynamic]rawptr,
        0,
        FIXTURE_MIGRATION_ARENA_TRACKING_CAPACITY,
        allocator,
    )
    if allocation_error != nil {
        mem.dynamic_arena_destroy(arena)
        return {}, false
    }
    arena.out_band_allocations = out_band_allocations
    arena_allocator := mem.dynamic_arena_allocator(arena)
    _, allocation_error = mem.dynamic_arena_alloc(arena, 1, 1)
    if allocation_error != nil {
        mem.dynamic_arena_destroy(arena)
        return {}, false
    }
    return arena_allocator, true
}

fixture_migration_arena_allocate :: proc(allocator: mem.Allocator) -> (^mem.Dynamic_Arena, bool) {
    arena_bytes, allocation_error := mem.alloc_bytes(
        size_of(mem.Dynamic_Arena),
        align_of(mem.Dynamic_Arena),
        allocator,
    )
    if allocation_error != nil || arena_bytes == nil {
        return nil, false
    }
    arena := cast(^mem.Dynamic_Arena)raw_data(arena_bytes)
    _, arena_ok := fixture_migration_arena_prepare(arena, allocator)
    if !arena_ok {
        _ = mem.free(rawptr(arena), allocator)
        return nil, false
    }
    return arena, true
}

fixture_migration_arena_dispose :: proc(arena: ^mem.Dynamic_Arena, allocator: mem.Allocator) {
    if arena == nil do return
    mem.dynamic_arena_destroy(arena)
    _ = mem.free(rawptr(arena), allocator)
}

fixture_migration_decode_kind :: proc(
    portable_error: hs.Portable_Error,
    fallback: Fixture_Migration_Error_Kind,
) -> Fixture_Migration_Error_Kind {
    if portable_error.kind == .Limit_Exceeded && strings.contains(portable_error.message, "allocation") {
        return .Out_Of_Memory
    }
    return fallback
}

fixture_migration_step_v0001_to_v0002 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       step_context.source_version != 1 ||
       step_context.step_from_version != 1 ||
       step_context.step_to_version != 2 ||
       step_context.target_version < step_context.step_to_version ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }
    tentative := step_context.tentative
    allocator := step_context.transaction_allocator
    transaction_arena := cast(^mem.Dynamic_Arena)allocator.data
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

    historical := new(fixture_v0001.Fixture, historical_allocator)
    if historical == nil do return {kind = .Out_Of_Memory}
    historical_value := any {
        data = rawptr(historical),
        id   = typeid_of(fixture_v0001.Fixture),
    }
    portable_error, portable_ok := hs.portable_decode(
        historical_value,
        step_context.source_payload,
        fixture_codec_historical_portable_config(),
        historical_allocator,
    )
    if !portable_ok {
        error_kind := fixture_migration_decode_kind(portable_error, .Historical_Decode)
        hs.portable_error_dispose(&portable_error)
        return {kind = error_kind}
    }
    hs.portable_error_dispose(&portable_error)

    step_error := fixture_migrate_v0001_to_v0002(historical^, tentative, allocator)
    if step_error.kind == .Unresolved && step_error.change_id == "" {
        step_error.change_id = FIXTURE_MIGRATION_V0001_TO_V0002_RESOLUTIONS[0].change_id
    }
    return step_error
}

fixture_migration_production_steps: [2]Fixture_Migration_Step = {
    {
        from_version = FIXTURE_MIGRATION_V0001_TO_V0002_FROM_VERSION,
        to_version = FIXTURE_MIGRATION_V0001_TO_V0002_TO_VERSION,
        wrapper = fixture_migration_step_v0001_to_v0002,
        change_id = "field-add:adriatic:packages/farmland.Plan.height",
    },
    {
        from_version = FIXTURE_MIGRATION_V0002_TO_V0003_FROM_VERSION,
        to_version = FIXTURE_MIGRATION_V0002_TO_V0003_TO_VERSION,
        wrapper = fixture_migration_step_v0002_to_v0003,
        change_id = "field-add:adriatic:src.Fixture.occupant",
    },
}

fixture_migration_production_registry :: proc() -> Fixture_Migration_Registry {
    return {steps = fixture_migration_production_steps[:]}
}

fixture_migration_registry_validate :: proc(
    source_version, target_version: int,
    registry: Fixture_Migration_Registry,
) -> (
    first_step, step_count: int,
    error: Fixture_Migration_Error,
    ok: bool,
) {
    if source_version <= 0 || target_version <= 0 || source_version > target_version {
        return 0, 0, {kind = .Invalid_Argument}, false
    }
    previous_to := 0
    first_step = -1
    for step, index in registry.steps {
        if step.from_version <= 0 ||
           step.to_version <= 0 ||
           step.to_version <= step.from_version ||
           step.to_version - step.from_version != 1 ||
           step.wrapper == nil {
            return 0, 0, {kind = .Invalid_Registry}, false
        }
        if index > 0 && step.from_version != previous_to {
            return 0, 0, {kind = .Invalid_Registry}, false
        }
        if first_step < 0 && step.from_version == source_version {
            first_step = index
        }
        previous_to = step.to_version
    }
    if len(registry.steps) == 0 {
        return 0, 0, {kind = .Invalid_Registry}, false
    }
    if target_version != previous_to {
        return 0, 0, {kind = .Unsupported_Version}, false
    }
    if source_version == target_version {
        return 0, 0, {}, true
    }
    if first_step < 0 {
        return 0, 0, {kind = .Unsupported_Version}, false
    }
    current_version := source_version
    for index := first_step; index < len(registry.steps); index += 1 {
        step := registry.steps[index]
        if step.from_version != current_version {
            return 0, 0, {kind = .Unsupported_Version}, false
        }
        current_version = step.to_version
        step_count += 1
        if current_version == target_version do break
        if current_version > target_version {
            return 0, 0, {kind = .Unsupported_Version}, false
        }
    }
    if current_version != target_version {
        return 0, 0, {kind = .Unsupported_Version}, false
    }
    return first_step, step_count, {}, true
}

fixture_migration_run_with_registry :: proc(
    payload: []byte,
    source_version, target_version: int,
    registry: Fixture_Migration_Registry,
    allocator := context.allocator,
) -> (
    result: Fixture_Migration_Result,
    error: Fixture_Migration_Error,
    ok: bool,
) {
    first_step, step_count, registry_error, registry_ok := fixture_migration_registry_validate(
        source_version,
        target_version,
        registry,
    )
    if !registry_ok do return {}, registry_error, false
    if allocator.procedure == nil do return {}, {kind = .Invalid_Argument}, false

    arena, arena_ok := fixture_migration_arena_allocate(allocator)
    if !arena_ok do return {}, {kind = .Out_Of_Memory}, false
    transaction_allocator := mem.dynamic_arena_allocator(arena)
    tentative := new(Fixture, transaction_allocator)
    if tentative == nil {
        fixture_migration_arena_dispose(arena, allocator)
        return {}, {kind = .Out_Of_Memory}, false
    }

    portable_config := fixture_codec_portable_config()
    if source_version == FIXTURE_SCHEMA_VERSION && target_version == FIXTURE_SCHEMA_VERSION {
        portable_config.exact_schema = true
    }
    portable_error, portable_ok := hs.portable_decode(
        fixture_codec_value(tentative),
        payload,
        portable_config,
        transaction_allocator,
    )
    if !portable_ok {
        error_kind := fixture_migration_decode_kind(portable_error, .Tentative_Decode)
        hs.portable_error_dispose(&portable_error)
        fixture_migration_arena_dispose(arena, allocator)
        return {}, {kind = error_kind}, false
    }
    hs.portable_error_dispose(&portable_error)

    for offset in 0 ..< step_count {
        step := registry.steps[first_step + offset]
        step_context := Fixture_Migration_Step_Context {
            source_payload        = payload,
            source_version        = source_version,
            target_version        = target_version,
            step_from_version     = step.from_version,
            step_to_version       = step.to_version,
            tentative             = tentative,
            transaction_allocator = transaction_allocator,
        }
        step_error := step.wrapper(&step_context)
        if step_error.kind == .None do continue
        if step_error.kind == .Unresolved && step_error.change_id == "" {
            step_error.change_id = step.change_id
        }
        if step_error.kind == .Invalid_Argument || step_error.kind == .Invalid_Source {
            step_error.kind = .Step_Failure
        }
        fixture_migration_arena_dispose(arena, allocator)
        return {}, step_error, false
    }
    return {fixture = tentative, arena = arena, arena_allocator = allocator}, {}, true
}

fixture_migration_run :: proc(
    payload: []byte,
    source_version, target_version: int,
    allocator := context.allocator,
) -> (
    result: Fixture_Migration_Result,
    error: Fixture_Migration_Error,
    ok: bool,
) {
    return fixture_migration_run_with_registry(
        payload,
        source_version,
        target_version,
        fixture_migration_production_registry(),
        allocator,
    )
}
