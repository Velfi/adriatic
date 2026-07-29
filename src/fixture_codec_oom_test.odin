package main

import fixture_file "../packages/fixture_file"
import "base:runtime"
import "core:mem"
import "core:testing"

when ODIN_TEST {
    fixture_codec_oom_test_put_u16 :: proc(data: []byte, offset: int, value: u16) {
        data[offset] = byte(value)
        data[offset + 1] = byte(value >> 8)
    }

    fixture_codec_oom_test_put_u32 :: proc(data: []byte, offset: int, value: u32) {
        data[offset] = byte(value)
        data[offset + 1] = byte(value >> 8)
        data[offset + 2] = byte(value >> 16)
        data[offset + 3] = byte(value >> 24)
    }

    fixture_codec_oom_test_put_u64 :: proc(data: []byte, offset: int, value: u64) {
        for index in 0 ..< 8 {
            data[offset + index] = byte(value >> (u64(index) * 8))
        }
    }

    fixture_codec_oom_test_allocator :: proc(state: ^fixture_migration_test_allocator_state) -> mem.Allocator {
        return fixture_migration_test_allocator(state)
    }

    fixture_codec_oom_test_success_count :: proc(t: ^testing.T, data, snapshot: []byte) -> int {
        state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        result, error, ok := fixture_codec_decode(data, fixture_codec_oom_test_allocator(&state))
        testing.expect(t, ok)
        testing.expect(t, error.kind == .None)
        testing.expect(t, result.fixture != nil)
        testing.expect(t, result.arena != nil)
        testing.expect(t, state.allocation_calls > 0)
        testing.expect(t, state.outstanding > 0)
        testing.expect(t, fixture_codec_test_bytes_equal(data, snapshot))
        if !ok {
            fixture_codec_error_dispose(&error)
            fixture_migration_result_dispose(&result)
            return 0
        }

        allocation_count := state.allocation_calls
        outstanding_before_error_dispose := state.outstanding
        fixture_codec_error_dispose(&error)
        fixture_codec_error_dispose(&error)
        testing.expect(t, state.outstanding == outstanding_before_error_dispose)
        fixture_migration_result_dispose(&result)
        testing.expect(t, state.outstanding == 0)
        fixture_migration_result_dispose(&result)
        testing.expect(t, fixture_migration_result_empty(&result))
        testing.expect(t, fixture_codec_test_bytes_equal(data, snapshot))
        return allocation_count
    }

    fixture_codec_oom_test_sweep :: proc(t: ^testing.T, data, snapshot: []byte, allocation_count: int) {
        for fail_at in 0 ..< allocation_count {
            state := fixture_migration_test_allocator_state {
                base    = runtime.default_allocator(),
                fail_at = fail_at,
            }
            result, error, ok := fixture_codec_decode(data, fixture_codec_oom_test_allocator(&state))
            testing.expect(t, !ok)
            testing.expect(t, error.kind == .Migration)
            testing.expect(t, error.migration.kind == .Out_Of_Memory)
            testing.expect(t, fixture_migration_result_empty(&result))
            testing.expect(t, result.fixture == nil)
            testing.expect(t, result.arena == nil)
            testing.expect(t, state.allocation_calls == fail_at + 1)
            testing.expect(t, state.outstanding == 0)
            testing.expect(t, fixture_codec_test_bytes_equal(data, snapshot))
            fixture_codec_test_expect_empty(t, &result, &error)
            testing.expect(t, state.outstanding == 0)
            testing.expect(t, state.allocation_calls == fail_at + 1)
            testing.expect(t, fixture_codec_test_bytes_equal(data, snapshot))
        }
    }

    fixture_codec_oom_test_expect_preflight :: proc(
        t: ^testing.T,
        data: []byte,
        container_kind: fixture_file.Fixture_Container_Error_Kind,
        schema_mismatch: bool,
    ) {
        snapshot := fixture_codec_test_copy(data)
        defer delete(snapshot)
        state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = 0,
        }
        result, error, ok := fixture_codec_decode(data, fixture_codec_oom_test_allocator(&state))
        testing.expect(t, !ok)
        if schema_mismatch {
            testing.expect(t, error.kind == .Schema_Mismatch)
        } else {
            testing.expect(t, error.kind == .Container_Decode)
            testing.expect(t, error.container.kind == container_kind)
        }
        testing.expect(t, state.allocation_calls == 0)
        testing.expect(t, state.outstanding == 0)
        testing.expect(t, fixture_migration_result_empty(&result))
        testing.expect(t, fixture_codec_test_bytes_equal(data, snapshot))
        fixture_codec_test_expect_empty(t, &result, &error)
        testing.expect(t, state.allocation_calls == 0)
        testing.expect(t, state.outstanding == 0)
        testing.expect(t, fixture_codec_test_bytes_equal(data, snapshot))
    }

    fixture_codec_oom_test_expect_semantic_failure :: proc(
        t: ^testing.T,
        data, snapshot: []byte,
        migration_kind: Fixture_Migration_Error_Kind,
        change_id: string,
    ) {
        state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        result, error, ok := fixture_codec_decode(data, fixture_codec_oom_test_allocator(&state))
        testing.expect(t, !ok)
        testing.expect(t, error.kind == .Migration)
        testing.expect(t, error.migration.kind == migration_kind)
        if change_id != "" {
            testing.expect(t, error.migration.change_id == change_id)
        }
        testing.expect(t, fixture_migration_result_empty(&result))
        testing.expect(t, state.allocation_calls > 0)
        testing.expect(t, state.outstanding == 0)
        testing.expect(t, fixture_codec_test_bytes_equal(data, snapshot))
        fixture_codec_test_expect_empty(t, &result, &error)
        testing.expect(t, state.outstanding == 0)
        testing.expect(t, fixture_codec_test_bytes_equal(data, snapshot))
    }

    @(test)
    fixture_codec_owned_decode_allocation_failures_and_preflight :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        source := fixture_codec_test_source()
        defer fixture_codec_test_destroy_source(source)
        current, current_error, current_ok := fixture_codec_encode(source, context.allocator)
        testing.expect(t, current_ok && current_error.kind == .None)
        fixture_codec_error_dispose(&current_error)
        fixture_codec_error_dispose(&current_error)
        if !current_ok do return
        defer delete(current)
        current_snapshot := fixture_codec_test_copy(current)
        defer delete(current_snapshot)

        v3_payload, v3_payload_ok := fixture_migration_v0003_runtime_v3_payload(t)
        testing.expect(t, v3_payload_ok)
        if !v3_payload_ok do return
        v3, v3_error, v3_ok := fixture_file.fixture_container_encode(v3_payload, 3, alloc = context.allocator)
        delete(v3_payload)
        testing.expect(t, v3_ok && v3_error.kind == .None)
        if !v3_ok do return
        defer delete(v3)
        v3_snapshot := fixture_codec_test_copy(v3)
        defer delete(v3_snapshot)

        v2_payload, v2_payload_ok := fixture_codec_test_v2_payload(t)
        testing.expect(t, v2_payload_ok)
        if !v2_payload_ok do return
        v2, v2_error, v2_ok := fixture_file.fixture_container_encode(v2_payload, 2, alloc = context.allocator)
        delete(v2_payload)
        testing.expect(t, v2_ok && v2_error.kind == .None)
        if !v2_ok do return
        defer delete(v2)
        v2_snapshot := fixture_codec_test_copy(v2)
        defer delete(v2_snapshot)

        v1_payload, v1_payload_ok := fixture_migration_v0002_to_v0003_test_v1_payload(t)
        testing.expect(t, v1_payload_ok)
        if !v1_payload_ok do return
        v1, v1_error, v1_ok := fixture_file.fixture_container_encode(v1_payload, 1, alloc = context.allocator)
        delete(v1_payload)
        testing.expect(t, v1_ok && v1_error.kind == .None)
        if !v1_ok do return
        defer delete(v1)
        v1_snapshot := fixture_codec_test_copy(v1)
        defer delete(v1_snapshot)

        current_allocation_count := fixture_codec_oom_test_success_count(t, current, current_snapshot)
        v3_allocation_count := fixture_codec_oom_test_success_count(t, v3, v3_snapshot)
        v2_allocation_count := fixture_codec_oom_test_success_count(t, v2, v2_snapshot)
        v1_allocation_count := fixture_codec_oom_test_success_count(t, v1, v1_snapshot)
        if current_allocation_count == 0 ||
           v3_allocation_count == 0 ||
           v2_allocation_count == 0 ||
           v1_allocation_count == 0 {
            return
        }
        fixture_codec_oom_test_sweep(t, current, current_snapshot, current_allocation_count)
        fixture_codec_oom_test_sweep(t, v3, v3_snapshot, v3_allocation_count)
        fixture_codec_oom_test_sweep(t, v2, v2_snapshot, v2_allocation_count)
        fixture_codec_oom_test_sweep(t, v1, v1_snapshot, v1_allocation_count)

        tiny_payload := []byte{0x5a}
        tiny, tiny_error, tiny_ok := fixture_file.fixture_container_encode(tiny_payload, 1, alloc = context.allocator)
        testing.expect(t, tiny_ok && tiny_error.kind == .None)
        if !tiny_ok do return
        defer delete(tiny)

        for length in 0 ..< fixture_file.Fixture_Container_Header_Size {
            fixture_codec_oom_test_expect_preflight(t, tiny[:length], .Truncated, false)
        }

        bad_magic := fixture_codec_test_copy(tiny)
        bad_magic[0] = bad_magic[0] ~ 1
        fixture_codec_oom_test_expect_preflight(t, bad_magic, .Invalid_Magic, false)
        delete(bad_magic)

        bad_version := fixture_codec_test_copy(tiny)
        fixture_codec_oom_test_put_u16(bad_version, 8, 2)
        fixture_codec_oom_test_expect_preflight(t, bad_version, .Unsupported_Version, false)
        delete(bad_version)

        bad_flags := fixture_codec_test_copy(tiny)
        fixture_codec_oom_test_put_u16(bad_flags, 10, 1)
        fixture_codec_oom_test_expect_preflight(t, bad_flags, .Unsupported_Flags, false)
        delete(bad_flags)

        bad_schema := fixture_codec_test_copy(tiny)
        fixture_codec_oom_test_put_u32(bad_schema, 12, 0)
        fixture_codec_oom_test_expect_preflight(t, bad_schema, .Invalid_Schema_Version, false)
        delete(bad_schema)

        bad_trailing := fixture_codec_test_copy(tiny)
        fixture_codec_oom_test_put_u64(bad_trailing, 16, 0)
        fixture_codec_oom_test_expect_preflight(t, bad_trailing, .Trailing_Bytes, false)
        delete(bad_trailing)

        bad_truncated := fixture_codec_test_copy(tiny)
        fixture_codec_oom_test_put_u64(bad_truncated, 16, 2)
        fixture_codec_oom_test_expect_preflight(t, bad_truncated, .Truncated, false)
        delete(bad_truncated)

        bad_overflow := fixture_codec_test_copy(tiny)
        fixture_codec_oom_test_put_u64(bad_overflow, 16, max(u64))
        fixture_codec_oom_test_expect_preflight(t, bad_overflow, .Overflow, false)
        delete(bad_overflow)

        bad_cap := fixture_codec_test_copy(tiny)
        fixture_codec_oom_test_put_u64(bad_cap, 16, u64(fixture_file.Fixture_Container_Default_Payload_Cap + 1))
        fixture_codec_oom_test_expect_preflight(t, bad_cap, .Limit_Exceeded, false)
        delete(bad_cap)

        bad_checksum := fixture_codec_test_copy(tiny)
        bad_checksum[24] = bad_checksum[24] ~ 1
        fixture_codec_oom_test_expect_preflight(t, bad_checksum, .Checksum_Mismatch, false)
        delete(bad_checksum)

        bad_payload := fixture_codec_test_copy(tiny)
        bad_payload[fixture_file.Fixture_Container_Header_Size] =
            bad_payload[fixture_file.Fixture_Container_Header_Size] ~ 1
        fixture_codec_oom_test_expect_preflight(t, bad_payload, .Checksum_Mismatch, false)
        delete(bad_payload)

        future, future_error, future_ok := fixture_file.fixture_container_encode(
            tiny_payload,
            u32(FIXTURE_SCHEMA_VERSION + 1),
            alloc = context.allocator,
        )
        testing.expect(t, future_ok && future_error.kind == .None)
        if future_ok {
            fixture_codec_oom_test_expect_preflight(t, future, .None, true)
            delete(future)
        }

        malformed_payload := []byte{1, 2, 3, 4}
        malformed, malformed_error, malformed_ok := fixture_file.fixture_container_encode(
            malformed_payload,
            u32(FIXTURE_SCHEMA_VERSION),
            alloc = context.allocator,
        )
        testing.expect(t, malformed_ok && malformed_error.kind == .None)
        if malformed_ok {
            malformed_snapshot := fixture_codec_test_copy(malformed)
            defer delete(malformed_snapshot)
            fixture_codec_oom_test_expect_semantic_failure(t, malformed, malformed_snapshot, .Tentative_Decode, "")
            delete(malformed)
        }

        invalid_payload, invalid_payload_ok := fixture_codec_test_invalid_historical_payload(t)
        testing.expect(t, invalid_payload_ok)
        if invalid_payload_ok {
            invalid, invalid_error, invalid_ok := fixture_file.fixture_container_encode(
                invalid_payload,
                1,
                alloc = context.allocator,
            )
            delete(invalid_payload)
            testing.expect(t, invalid_ok && invalid_error.kind == .None)
            if invalid_ok {
                invalid_snapshot := fixture_codec_test_copy(invalid)
                defer delete(invalid_snapshot)
                fixture_codec_oom_test_expect_semantic_failure(
                    t,
                    invalid,
                    invalid_snapshot,
                    .Step_Failure,
                    FIXTURE_MIGRATION_V0001_TERRAIN_STRUCTURES_ID,
                )
                delete(invalid)
            }
        }
    }
}
