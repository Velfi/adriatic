package main

import fixture_v0004 "../packages/fixture_history/v0004"
import flight "../packages/flight"
import postale_game "../packages/postale"
import "base:runtime"
import "core:math"
import "core:mem"
import "core:testing"

when ODIN_TEST {
    Fixture_Migration_V0004_Test_Basis_Site :: enum {
        Postale_Body,
        Libellula_Body,
        Rondine_Body,
        Libellula_Spawn,
        Postale_Spawn,
    }

    Fixture_Migration_V0004_Test_Angular_Site :: enum {
        Postale,
        Libellula,
        Rondine,
    }

    fixture_migration_v0004_test_identity_basis :: proc() -> fixture_v0004.History_Type_0026 {
        return {forward = {0, 0, -1}, up = {0, 1, 0}, right = {1, 0, 0}}
    }

    fixture_migration_v0004_test_basis :: proc(
        forward, up, right: fixture_v0004.History_Type_0033,
    ) -> fixture_v0004.History_Type_0026 {
        return {forward = forward, up = up, right = right}
    }

    fixture_migration_v0004_test_sentinel_orientation :: proc(seed: f32) -> quaternion128 {
        result := flight.identity_orientation()
        result.x = seed
        result.y = seed + 1
        result.z = seed + 2
        result.w = seed + 3
        return result
    }

    fixture_migration_v0004_test_make :: proc(
        t: ^testing.T,
    ) -> (
        historical: ^fixture_v0004.Fixture,
        tentative: ^Fixture,
        ok: bool,
    ) {
        historical = new(fixture_v0004.Fixture, context.allocator)
        tentative = new(Fixture, context.allocator)
        testing.expect(t, historical != nil && tentative != nil)
        if historical == nil || tentative == nil {
            free(historical, context.allocator)
            free(tentative, context.allocator)
            return nil, nil, false
        }
        return historical, tentative, true
    }

    fixture_migration_v0004_test_destroy :: proc(historical: ^fixture_v0004.Fixture, tentative: ^Fixture) {
        free(historical, context.allocator)
        free(tentative, context.allocator)
    }

    fixture_migration_v0004_test_seed_valid :: proc(historical: ^fixture_v0004.Fixture, tentative: ^Fixture) {
        historical.postale.body.angular_velocity = {1, 2, 3}
        historical.postale.body.basis = fixture_migration_v0004_test_identity_basis()
        historical.libellula.body.angular_velocity = {-4, 5, -6}
        historical.libellula.body.basis = fixture_migration_v0004_test_basis({1, 0, 0}, {0, 1, 0}, {0, 0, 1})
        historical.rondine.body.angular_velocity = {7, -8, 9}
        historical.rondine.body.basis = fixture_migration_v0004_test_basis({0, 0, 1}, {0, 1, 0}, {-1, 0, 0})
        historical.aircraft.active = .Postale
        historical.rondine_visible = true
        historical.rondine.vehicle.locked = false
        historical.libellula.spawn_basis = fixture_migration_v0004_test_basis({-1, 0, 0}, {0, 1, 0}, {0, 0, -1})
        historical.postale.spawn_basis = fixture_migration_v0004_test_basis({0, -1, 0}, {0, 0, -1}, {1, 0, 0})

        tentative.postale.body.angular_velocity_world = {91, 92, 93}
        tentative.libellula.body.angular_velocity_world = {94, 95, 96}
        tentative.rondine.body.angular_velocity_world = {97, 98, 99}
        tentative.postale.body.orientation = fixture_migration_v0004_test_sentinel_orientation(1)
        tentative.libellula.body.orientation = fixture_migration_v0004_test_sentinel_orientation(5)
        tentative.rondine.body.orientation = fixture_migration_v0004_test_sentinel_orientation(9)
        tentative.libellula.spawn_orientation = fixture_migration_v0004_test_sentinel_orientation(13)
        tentative.postale.spawn_orientation = fixture_migration_v0004_test_sentinel_orientation(17)
        tentative.postale.flight_model = .Ace_Arcade
        tentative.postale.ace_tuning = {}
        tentative.postale.ace_tuning.pace = .25
        tentative.postale.ace_tuning.roll_snap = .75
        tentative.postale.ace_runtime = {
            energy       = .75,
            edge_state   = .Break,
            edge_seconds = 12,
            local_rate   = {21, 22, 23},
        }

        tentative.postale.body.position = {31, 32, 33}
        tentative.postale.body.velocity = {34, 35, 36}
        tentative.libellula.body.position = {37, 38, 39}
        tentative.rondine.body.velocity = {40, 41, 42}
        tentative.wreck_brush_yaw = 43
        tentative.rondine.wake_serial = 44
    }

    fixture_migration_v0004_test_call :: proc(
        t: ^testing.T,
        historical: ^fixture_v0004.Fixture,
        tentative: ^Fixture,
    ) -> Fixture_Migration_Error {
        state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = 0,
        }
        error := fixture_migrate_v0004_to_v0005(historical^, tentative, fixture_migration_test_allocator(&state))
        testing.expect(t, state.allocation_calls == 0 && state.outstanding == 0)
        return error
    }

    fixture_migration_v0004_test_snapshot_dispose :: proc(
        snapshot: ^Fixture_Migration_Structural_Snapshot,
        allocator: mem.Allocator,
    ) {
        if snapshot == nil do return
        delete(snapshot.root_bytes, allocator)
        delete(snapshot.project.bytes, allocator)
        delete(snapshot.city_structures.bytes, allocator)
        delete(snapshot.city_parcels.bytes, allocator)
        delete(snapshot.city_alleys.bytes, allocator)
        delete(snapshot.city_lamps.bytes, allocator)
        snapshot^ = {}
    }

    fixture_migration_v0004_test_expect_atomic_failure :: proc(
        t: ^testing.T,
        historical: ^fixture_v0004.Fixture,
        tentative: ^Fixture,
        expected_id: string,
    ) {
        snapshot_allocator := runtime.default_allocator()
        ambient_allocator := context.allocator
        context.allocator = snapshot_allocator
        target_snapshot, target_snapshot_ok := fixture_migration_structural_snapshot(tentative, snapshot_allocator)
        context.allocator = ambient_allocator
        testing.expect(t, target_snapshot_ok)
        if !target_snapshot_ok do return
        defer fixture_migration_v0004_test_snapshot_dispose(&target_snapshot, snapshot_allocator)

        source_snapshot, allocation_error := make([]byte, size_of(fixture_v0004.Fixture), snapshot_allocator)
        testing.expect(t, allocation_error == nil)
        if allocation_error != nil do return
        defer delete(source_snapshot, snapshot_allocator)
        copy(source_snapshot, mem.slice_ptr(cast([^]u8)historical, size_of(fixture_v0004.Fixture)))

        error := fixture_migration_v0004_test_call(t, historical, tentative)
        testing.expect(t, error.kind == .Invalid_Source && error.change_id == expected_id)
        testing.expect(t, fixture_migration_structural_snapshot_matches(target_snapshot, tentative))
        current_source := mem.slice_ptr(cast([^]u8)historical, size_of(fixture_v0004.Fixture))
        testing.expect(t, fixture_migration_test_bytes_equal(source_snapshot, current_source))
    }

    fixture_migration_v0004_test_set_basis :: proc(
        historical: ^fixture_v0004.Fixture,
        site: Fixture_Migration_V0004_Test_Basis_Site,
        value: fixture_v0004.History_Type_0026,
    ) {
        switch site {
        case .Postale_Body:
            historical.postale.body.basis = value
        case .Libellula_Body:
            historical.libellula.body.basis = value
        case .Rondine_Body:
            historical.rondine.body.basis = value
        case .Libellula_Spawn:
            historical.libellula.spawn_basis = value
        case .Postale_Spawn:
            historical.postale.spawn_basis = value
        }
    }

    fixture_migration_v0004_test_basis_id :: proc(site: Fixture_Migration_V0004_Test_Basis_Site) -> string {
        switch site {
        case .Postale_Body, .Libellula_Body, .Rondine_Body:
            return FIXTURE_MIGRATION_V0004_TO_V0005_BODY_ORIENTATION_ID
        case .Libellula_Spawn:
            return FIXTURE_MIGRATION_V0004_TO_V0005_LIBELLULA_SPAWN_ID
        case .Postale_Spawn:
            return FIXTURE_MIGRATION_V0004_TO_V0005_POSTALE_SPAWN_ID
        }
        return ""
    }

    fixture_migration_v0004_test_set_angular :: proc(
        historical: ^fixture_v0004.Fixture,
        site: Fixture_Migration_V0004_Test_Angular_Site,
        value: fixture_v0004.History_Type_0033,
    ) {
        switch site {
        case .Postale:
            historical.postale.body.angular_velocity = value
        case .Libellula:
            historical.libellula.body.angular_velocity = value
        case .Rondine:
            historical.rondine.body.angular_velocity = value
        }
    }

    fixture_migration_v0004_test_expected_orientation :: proc(
        value: fixture_v0004.History_Type_0026,
    ) -> quaternion128 {
        return flight.orientation_from_basis(fixture_migration_v0004_to_v0005_history_basis(value))
    }

    @(test)
    fixture_migration_v0004_to_v0005_structural_success_and_resolutions :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        historical, tentative, made := fixture_migration_v0004_test_make(t)
        if !made do return
        defer fixture_migration_v0004_test_destroy(historical, tentative)
        fixture_migration_v0004_test_seed_valid(historical, tentative)

        postale_position := tentative.postale.body.position
        postale_velocity := tentative.postale.body.velocity
        libellula_position := tentative.libellula.body.position
        rondine_velocity := tentative.rondine.body.velocity
        wreck_brush_yaw := tentative.wreck_brush_yaw
        wake_serial := tentative.rondine.wake_serial
        expected_postale_orientation := fixture_migration_v0004_test_expected_orientation(
            historical.postale.body.basis,
        )
        expected_libellula_orientation := fixture_migration_v0004_test_expected_orientation(
            historical.libellula.body.basis,
        )
        expected_rondine_orientation := fixture_migration_v0004_test_expected_orientation(
            historical.rondine.body.basis,
        )
        expected_libellula_spawn := fixture_migration_v0004_test_expected_orientation(historical.libellula.spawn_basis)
        expected_postale_spawn := fixture_migration_v0004_test_expected_orientation(historical.postale.spawn_basis)
        expected_tuning := postale_game.ace_tuning_preset()
        expected_body := tentative.postale.body
        expected_body.angular_velocity_world = fixture_migration_v0004_to_v0005_history_vec3(
            historical.postale.body.angular_velocity,
        )
        expected_body.orientation = expected_postale_orientation
        expected_runtime := flight.default_ace_runtime(expected_body, expected_tuning)

        error := fixture_migration_v0004_test_call(t, historical, tentative)
        testing.expect(t, error.kind == .None && error.change_id == "")
        testing.expect(
            t,
            tentative.postale.body.angular_velocity_world ==
                fixture_migration_v0004_to_v0005_history_vec3(historical.postale.body.angular_velocity) &&
            tentative.libellula.body.angular_velocity_world ==
                fixture_migration_v0004_to_v0005_history_vec3(historical.libellula.body.angular_velocity) &&
            tentative.rondine.body.angular_velocity_world ==
                fixture_migration_v0004_to_v0005_history_vec3(historical.rondine.body.angular_velocity),
        )
        testing.expect(
            t,
            tentative.postale.body.orientation == expected_postale_orientation &&
            tentative.libellula.body.orientation == expected_libellula_orientation &&
            tentative.rondine.body.orientation == expected_rondine_orientation &&
            tentative.libellula.spawn_orientation == expected_libellula_spawn &&
            tentative.postale.spawn_orientation == expected_postale_spawn,
        )
        testing.expect(
            t,
            fixture_migration_v0004_to_v0005_orientation_valid(tentative.postale.body.orientation) &&
            fixture_migration_v0004_to_v0005_orientation_valid(tentative.libellula.body.orientation) &&
            fixture_migration_v0004_to_v0005_orientation_valid(tentative.rondine.body.orientation) &&
            fixture_migration_v0004_to_v0005_orientation_valid(tentative.libellula.spawn_orientation) &&
            fixture_migration_v0004_to_v0005_orientation_valid(tentative.postale.spawn_orientation),
        )
        testing.expect(
            t,
            tentative.postale.flight_model == .Current_Aero &&
            tentative.postale.ace_tuning == expected_tuning &&
            tentative.postale.ace_runtime == expected_runtime &&
            tentative.postale.ace_runtime.energy == 0 &&
            tentative.postale.ace_runtime.edge_state == .Free &&
            tentative.postale.ace_runtime.edge_seconds == 0,
        )
        testing.expect(
            t,
            tentative.postale.body.position == postale_position &&
            tentative.postale.body.velocity == postale_velocity &&
            tentative.libellula.body.position == libellula_position &&
            tentative.rondine.body.velocity == rondine_velocity &&
            tentative.wreck_brush_yaw == wreck_brush_yaw &&
            tentative.rondine.wake_serial == wake_serial,
        )

        expected_resolutions := [?]Fixture_Migration_Resolution {
            {"field-add:adriatic:packages/flight.Body_State.angular_velocity_world", .Scripted},
            {"field-add:adriatic:packages/flight.Body_State.orientation", .Scripted},
            {"field-add:adriatic:packages/libellula.Runtime.spawn_orientation", .Scripted},
            {"field-add:adriatic:packages/postale.Runtime.ace_runtime", .Scripted},
            {"field-add:adriatic:packages/postale.Runtime.ace_tuning", .Scripted},
            {"field-add:adriatic:packages/postale.Runtime.flight_model", .Scripted},
            {"field-add:adriatic:packages/postale.Runtime.spawn_orientation", .Scripted},
            {"field-order:adriatic:packages/flight.Body_State", .Automatic},
            {"field-remove:adriatic:packages/flight.Body_State.angular_velocity", .Scripted},
            {"field-remove:adriatic:packages/flight.Body_State.basis", .Scripted},
            {"field-remove:adriatic:packages/libellula.Runtime.spawn_basis", .Scripted},
            {"field-remove:adriatic:packages/libellula.Runtime.telemetry", .Automatic},
            {"field-remove:adriatic:packages/postale.Runtime.spawn_basis", .Scripted},
            {"field-remove:adriatic:packages/postale.Runtime.telemetry", .Automatic},
            {"field-remove:adriatic:src.Fixture.camera_target_lock", .Automatic},
            {"type-remove:adriatic:packages/flight.Telemetry", .Automatic},
            {"type-remove:adriatic:packages/flight.Tri_Rotor_Telemetry", .Automatic},
        }
        testing.expect(
            t,
            FIXTURE_MIGRATION_V0004_TO_V0005_FROM_VERSION == 4 &&
            FIXTURE_MIGRATION_V0004_TO_V0005_TO_VERSION == 5 &&
            len(FIXTURE_MIGRATION_V0004_TO_V0005_RESOLUTIONS) == len(expected_resolutions),
        )
        scripted, automatic, unresolved := 0, 0, 0
        for resolution, index in FIXTURE_MIGRATION_V0004_TO_V0005_RESOLUTIONS {
            testing.expect(t, resolution == expected_resolutions[index])
            switch resolution.kind {
            case .Scripted:
                scripted += 1
            case .Automatic:
                automatic += 1
            case .Unresolved:
                unresolved += 1
            }
        }
        testing.expect(t, scripted == 11 && automatic == 6 && unresolved == 0)
    }

    @(test)
    fixture_migration_v0004_to_v0005_structural_basis_boundaries_and_hostile_sources :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        historical, tentative, made := fixture_migration_v0004_test_make(t)
        if !made do return
        defer fixture_migration_v0004_test_destroy(historical, tentative)

        epsilon := FIXTURE_MIGRATION_V0004_TO_V0005_BASIS_EPSILON
        axis_inside := transmute(f32)u32(1065357409)
        axis_outside := transmute(f32)u32(1065357410)
        handed_inside := transmute(f32)u32(1065347622)
        handed_outside := transmute(f32)u32(1065347621)
        axis_inside_delta := math.abs(axis_inside * axis_inside - 1)
        axis_outside_delta := math.abs(axis_outside * axis_outside - 1)
        handed_inside_delta := math.abs(handed_inside * handed_inside * handed_inside - 1)
        handed_outside_delta := math.abs(handed_outside * handed_outside * handed_outside - 1)
        testing.expect(
            t,
            axis_inside_delta <= epsilon &&
            axis_outside_delta > epsilon &&
            handed_inside_delta <= epsilon &&
            handed_outside_delta > epsilon,
        )
        accepted := [?]fixture_v0004.History_Type_0026 {
            fixture_migration_v0004_test_basis({0, 0, -axis_inside}, {0, 1, 0}, {1, 0, 0}),
            fixture_migration_v0004_test_basis({0, 0, -1}, {0, 1, 0}, {1, 0, -epsilon}),
            fixture_migration_v0004_test_basis({0, 0, -handed_inside}, {0, handed_inside, 0}, {handed_inside, 0, 0}),
        }
        for value in accepted {
            testing.expect(t, fixture_migration_v0004_to_v0005_basis_valid(value))
        }

        sites := [?]Fixture_Migration_V0004_Test_Basis_Site {
            .Postale_Body,
            .Libellula_Body,
            .Rondine_Body,
            .Libellula_Spawn,
            .Postale_Spawn,
        }
        for site in sites {
            for value in accepted {
                fixture_migration_v0004_test_seed_valid(historical, tentative)
                fixture_migration_v0004_test_set_basis(historical, site, value)
                error := fixture_migration_v0004_test_call(t, historical, tentative)
                testing.expect(t, error.kind == .None)
            }
        }

        nan := math.nan_f32()
        positive_infinity := math.inf_f32(1)
        invalid := [?]fixture_v0004.History_Type_0026 {
            fixture_migration_v0004_test_basis({nan, 0, -1}, {0, 1, 0}, {1, 0, 0}),
            fixture_migration_v0004_test_basis({positive_infinity, 0, -1}, {0, 1, 0}, {1, 0, 0}),
            {},
            fixture_migration_v0004_test_basis({0, 0, -axis_outside}, {0, 1, 0}, {1, 0, 0}),
            fixture_migration_v0004_test_basis({0, 0, -1}, {0, 1, 0}, {1, 0, -(epsilon * 1.01)}),
            fixture_migration_v0004_test_basis(
                {0, 0, -handed_outside},
                {0, handed_outside, 0},
                {handed_outside, 0, 0},
            ),
            fixture_migration_v0004_test_basis({0, 0, -1}, {0, 1, 0}, {-1, 0, 0}),
        }
        for site in sites {
            for value in invalid {
                fixture_migration_v0004_test_seed_valid(historical, tentative)
                fixture_migration_v0004_test_set_basis(historical, site, value)
                fixture_migration_v0004_test_expect_atomic_failure(
                    t,
                    historical,
                    tentative,
                    fixture_migration_v0004_test_basis_id(site),
                )
            }
        }

        angular_sites := [?]Fixture_Migration_V0004_Test_Angular_Site{.Postale, .Libellula, .Rondine}
        invalid_angular := [?]fixture_v0004.History_Type_0033{{nan, 0, 0}, {positive_infinity, 0, 0}}
        for site in angular_sites {
            for value in invalid_angular {
                fixture_migration_v0004_test_seed_valid(historical, tentative)
                fixture_migration_v0004_test_set_angular(historical, site, value)
                fixture_migration_v0004_test_expect_atomic_failure(
                    t,
                    historical,
                    tentative,
                    FIXTURE_MIGRATION_V0004_TO_V0005_ANGULAR_ID,
                )
            }
        }
    }

    @(test)
    fixture_migration_v0004_to_v0005_structural_zero_rondine_and_nil :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        historical, tentative, made := fixture_migration_v0004_test_make(t)
        if !made do return
        defer fixture_migration_v0004_test_destroy(historical, tentative)

        fixture_migration_v0004_test_seed_valid(historical, tentative)
        historical.rondine.body = {}
        historical.rondine.vehicle.locked = true
        historical.rondine_visible = false
        rondine_velocity := tentative.rondine.body.velocity
        wake_serial := tentative.rondine.wake_serial
        error := fixture_migration_v0004_test_call(t, historical, tentative)
        testing.expect(
            t,
            error.kind == .None &&
            tentative.rondine.body.angular_velocity_world == flight.Vec3{} &&
            tentative.rondine.body.orientation == flight.identity_orientation() &&
            tentative.rondine.body.velocity == rondine_velocity &&
            tentative.rondine.wake_serial == wake_serial,
        )

        fixture_migration_v0004_test_seed_valid(historical, tentative)
        nil_error := fixture_migration_v0004_test_call(t, historical, nil)
        testing.expect(t, nil_error.kind == .Invalid_Argument && nil_error.change_id == "")

        for near_miss in 0 ..< 7 {
            fixture_migration_v0004_test_seed_valid(historical, tentative)
            historical.rondine.body = {}
            historical.rondine.vehicle.locked = true
            historical.rondine_visible = false
            switch near_miss {
            case 0:
                historical.rondine.vehicle.locked = false
            case 1:
                historical.rondine_visible = true
            case 2:
                historical.rondine.body.position.x = .0001
            case 3:
                historical.rondine.body.velocity.y = .0001
            case 4:
                historical.rondine.body.angular_velocity.z = .0001
            case 5:
                historical.rondine.body.basis.right.x = .0001
            case 6:
                historical.aircraft.active = .Rondine
            }
            fixture_migration_v0004_test_expect_atomic_failure(
                t,
                historical,
                tentative,
                FIXTURE_MIGRATION_V0004_TO_V0005_BODY_ORIENTATION_ID,
            )
        }
    }
}
