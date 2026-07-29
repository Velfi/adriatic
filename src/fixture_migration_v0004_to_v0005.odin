package main

import fixture_v0004 "../packages/fixture_history/v0004"
import flight "../packages/flight"
import postale_game "../packages/postale"
import "core:math"
import "core:mem"

FIXTURE_MIGRATION_V0004_TO_V0005_FROM_VERSION :: 4
FIXTURE_MIGRATION_V0004_TO_V0005_TO_VERSION :: 5
FIXTURE_MIGRATION_V0004_TO_V0005_BASIS_EPSILON :: f32(0.001)
FIXTURE_MIGRATION_V0004_TO_V0005_ANGULAR_ID :: "field-add:adriatic:packages/flight.Body_State.angular_velocity_world"
FIXTURE_MIGRATION_V0004_TO_V0005_BODY_ORIENTATION_ID :: "field-add:adriatic:packages/flight.Body_State.orientation"
FIXTURE_MIGRATION_V0004_TO_V0005_LIBELLULA_SPAWN_ID :: "field-add:adriatic:packages/libellula.Runtime.spawn_orientation"
FIXTURE_MIGRATION_V0004_TO_V0005_POSTALE_RUNTIME_ID :: "field-add:adriatic:packages/postale.Runtime.ace_runtime"
FIXTURE_MIGRATION_V0004_TO_V0005_POSTALE_TUNING_ID :: "field-add:adriatic:packages/postale.Runtime.ace_tuning"
FIXTURE_MIGRATION_V0004_TO_V0005_POSTALE_SPAWN_ID :: "field-add:adriatic:packages/postale.Runtime.spawn_orientation"
FIXTURE_MIGRATION_V0004_TO_V0005_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/flight.Body_State.angular_velocity_world",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/flight.Body_State.orientation",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/libellula.Runtime.spawn_orientation",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/postale.Runtime.ace_runtime",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/postale.Runtime.ace_tuning",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/postale.Runtime.flight_model",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/postale.Runtime.spawn_orientation",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-order:adriatic:packages/flight.Body_State", kind = .Automatic},
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:packages/flight.Body_State.angular_velocity",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:packages/flight.Body_State.basis",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:packages/libellula.Runtime.spawn_basis",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:packages/libellula.Runtime.telemetry",
        kind = .Automatic,
    },
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:packages/postale.Runtime.spawn_basis",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:packages/postale.Runtime.telemetry",
        kind = .Automatic,
    },
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:src.Fixture.camera_target_lock",
        kind = .Automatic,
    },
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/flight.Telemetry", kind = .Automatic},
    Fixture_Migration_Resolution {
        change_id = "type-remove:adriatic:packages/flight.Tri_Rotor_Telemetry",
        kind = .Automatic,
    },
}

fixture_migration_v0004_to_v0005_invalid_source :: proc(change_id: string) -> Fixture_Migration_Error {
    return {kind = .Invalid_Source, change_id = change_id}
}

fixture_migration_v0004_to_v0005_vec3_finite :: proc(value: fixture_v0004.History_Type_0033) -> bool {
    for component in value {
        if component != component || math.is_inf(component) do return false
    }
    return true
}

fixture_migration_v0004_to_v0005_vec3_zero :: proc(value: fixture_v0004.History_Type_0033) -> bool {
    return value[0] == 0 && value[1] == 0 && value[2] == 0
}

fixture_migration_v0004_to_v0005_dot :: proc(left, right: fixture_v0004.History_Type_0033) -> f32 {
    return left[0] * right[0] + left[1] * right[1] + left[2] * right[2]
}

fixture_migration_v0004_to_v0005_cross :: proc(
    left, right: fixture_v0004.History_Type_0033,
) -> fixture_v0004.History_Type_0033 {
    return {
        left[1] * right[2] - left[2] * right[1],
        left[2] * right[0] - left[0] * right[2],
        left[0] * right[1] - left[1] * right[0],
    }
}

fixture_migration_v0004_to_v0005_axis_unit :: proc(value: fixture_v0004.History_Type_0033) -> bool {
    return(
        math.abs(fixture_migration_v0004_to_v0005_dot(value, value) - 1) <=
        FIXTURE_MIGRATION_V0004_TO_V0005_BASIS_EPSILON \
    )
}

fixture_migration_v0004_to_v0005_basis_valid :: proc(value: fixture_v0004.History_Type_0026) -> bool {
    if !fixture_migration_v0004_to_v0005_vec3_finite(value.forward) ||
       !fixture_migration_v0004_to_v0005_vec3_finite(value.up) ||
       !fixture_migration_v0004_to_v0005_vec3_finite(value.right) {
        return false
    }
    epsilon := FIXTURE_MIGRATION_V0004_TO_V0005_BASIS_EPSILON
    if !fixture_migration_v0004_to_v0005_axis_unit(value.forward) ||
       !fixture_migration_v0004_to_v0005_axis_unit(value.up) ||
       !fixture_migration_v0004_to_v0005_axis_unit(value.right) {
        return false
    }
    if math.abs(fixture_migration_v0004_to_v0005_dot(value.forward, value.up)) > epsilon ||
       math.abs(fixture_migration_v0004_to_v0005_dot(value.forward, value.right)) > epsilon ||
       math.abs(fixture_migration_v0004_to_v0005_dot(value.up, value.right)) > epsilon {
        return false
    }
    handedness := fixture_migration_v0004_to_v0005_dot(
        fixture_migration_v0004_to_v0005_cross(value.forward, value.up),
        value.right,
    )
    return math.abs(handedness - 1) <= epsilon
}

fixture_migration_v0004_to_v0005_history_vec3 :: proc(value: fixture_v0004.History_Type_0033) -> flight.Vec3 {
    return {value[0], value[1], value[2]}
}

fixture_migration_v0004_to_v0005_history_basis :: proc(value: fixture_v0004.History_Type_0026) -> flight.Basis {
    return {
        forward = fixture_migration_v0004_to_v0005_history_vec3(value.forward),
        up = fixture_migration_v0004_to_v0005_history_vec3(value.up),
        right = fixture_migration_v0004_to_v0005_history_vec3(value.right),
    }
}

Fixture_Migration_V0004_To_V0005_Prepared :: struct {
    postale_body_orientation:    quaternion128,
    libellula_body_orientation:  quaternion128,
    rondine_body_orientation:    quaternion128,
    libellula_spawn_orientation: quaternion128,
    postale_spawn_orientation:   quaternion128,
    postale_ace_tuning:          flight.Ace_Tuning,
    postale_ace_runtime:         flight.Ace_Runtime,
}

fixture_migration_v0004_to_v0005_orientation_valid :: proc(value: quaternion128) -> bool {
    components := [?]f32{value.x, value.y, value.z, value.w}
    length_squared := f32(0)
    for component in components {
        if component != component || math.is_inf(component) do return false
        length_squared += component * component
    }
    return math.abs(length_squared - 1) <= FIXTURE_MIGRATION_V0004_TO_V0005_BASIS_EPSILON
}

fixture_migration_v0004_to_v0005_ace_runtime_valid :: proc(value: flight.Ace_Runtime) -> bool {
    return(
        value.energy == 0 &&
        value.edge_state == .Free &&
        value.edge_seconds == 0 &&
        fixture_migration_v0004_to_v0005_vec3_finite(value.local_rate) \
    )
}

fixture_migration_v0004_to_v0005_rondine_zero_body :: proc(#by_ptr historical: fixture_v0004.Fixture) -> bool {
    body := historical.rondine.body
    return(
        !historical.rondine_visible &&
        historical.aircraft.active != .Rondine &&
        historical.rondine.vehicle.locked &&
        fixture_migration_v0004_to_v0005_vec3_zero(body.position) &&
        fixture_migration_v0004_to_v0005_vec3_zero(body.velocity) &&
        fixture_migration_v0004_to_v0005_vec3_zero(body.angular_velocity) &&
        fixture_migration_v0004_to_v0005_vec3_zero(body.basis.forward) &&
        fixture_migration_v0004_to_v0005_vec3_zero(body.basis.up) &&
        fixture_migration_v0004_to_v0005_vec3_zero(body.basis.right) \
    )
}

fixture_migration_v0004_to_v0005_preflight :: proc(
    #by_ptr historical: fixture_v0004.Fixture,
) -> (
    prepared: Fixture_Migration_V0004_To_V0005_Prepared,
    error: Fixture_Migration_Error,
) {
    if !fixture_migration_v0004_to_v0005_vec3_finite(historical.postale.body.angular_velocity) ||
       !fixture_migration_v0004_to_v0005_vec3_finite(historical.libellula.body.angular_velocity) ||
       !fixture_migration_v0004_to_v0005_vec3_finite(historical.rondine.body.angular_velocity) {
        error = fixture_migration_v0004_to_v0005_invalid_source(FIXTURE_MIGRATION_V0004_TO_V0005_ANGULAR_ID)
        return
    }

    if !fixture_migration_v0004_to_v0005_basis_valid(historical.postale.body.basis) ||
       !fixture_migration_v0004_to_v0005_basis_valid(historical.libellula.body.basis) {
        error = fixture_migration_v0004_to_v0005_invalid_source(FIXTURE_MIGRATION_V0004_TO_V0005_BODY_ORIENTATION_ID)
        return
    }
    rondine_zero_body := fixture_migration_v0004_to_v0005_rondine_zero_body(historical)
    if !rondine_zero_body && !fixture_migration_v0004_to_v0005_basis_valid(historical.rondine.body.basis) {
        error = fixture_migration_v0004_to_v0005_invalid_source(FIXTURE_MIGRATION_V0004_TO_V0005_BODY_ORIENTATION_ID)
        return
    }
    if !fixture_migration_v0004_to_v0005_basis_valid(historical.libellula.spawn_basis) {
        error = fixture_migration_v0004_to_v0005_invalid_source(FIXTURE_MIGRATION_V0004_TO_V0005_LIBELLULA_SPAWN_ID)
        return
    }
    if !fixture_migration_v0004_to_v0005_basis_valid(historical.postale.spawn_basis) {
        error = fixture_migration_v0004_to_v0005_invalid_source(FIXTURE_MIGRATION_V0004_TO_V0005_POSTALE_SPAWN_ID)
        return
    }

    prepared.postale_body_orientation = flight.orientation_from_basis(
        fixture_migration_v0004_to_v0005_history_basis(historical.postale.body.basis),
    )
    prepared.libellula_body_orientation = flight.orientation_from_basis(
        fixture_migration_v0004_to_v0005_history_basis(historical.libellula.body.basis),
    )
    prepared.rondine_body_orientation = flight.identity_orientation()
    if !rondine_zero_body {
        prepared.rondine_body_orientation = flight.orientation_from_basis(
            fixture_migration_v0004_to_v0005_history_basis(historical.rondine.body.basis),
        )
    }
    prepared.libellula_spawn_orientation = flight.orientation_from_basis(
        fixture_migration_v0004_to_v0005_history_basis(historical.libellula.spawn_basis),
    )
    prepared.postale_spawn_orientation = flight.orientation_from_basis(
        fixture_migration_v0004_to_v0005_history_basis(historical.postale.spawn_basis),
    )

    if !fixture_migration_v0004_to_v0005_orientation_valid(prepared.postale_body_orientation) ||
       !fixture_migration_v0004_to_v0005_orientation_valid(prepared.libellula_body_orientation) ||
       !fixture_migration_v0004_to_v0005_orientation_valid(prepared.rondine_body_orientation) {
        error = fixture_migration_v0004_to_v0005_invalid_source(FIXTURE_MIGRATION_V0004_TO_V0005_BODY_ORIENTATION_ID)
        return
    }
    if !fixture_migration_v0004_to_v0005_orientation_valid(prepared.libellula_spawn_orientation) {
        error = fixture_migration_v0004_to_v0005_invalid_source(FIXTURE_MIGRATION_V0004_TO_V0005_LIBELLULA_SPAWN_ID)
        return
    }
    if !fixture_migration_v0004_to_v0005_orientation_valid(prepared.postale_spawn_orientation) {
        error = fixture_migration_v0004_to_v0005_invalid_source(FIXTURE_MIGRATION_V0004_TO_V0005_POSTALE_SPAWN_ID)
        return
    }

    prepared.postale_ace_tuning = postale_game.ace_tuning_preset()
    if !flight.ace_tuning_is_valid(prepared.postale_ace_tuning) {
        error = fixture_migration_v0004_to_v0005_invalid_source(FIXTURE_MIGRATION_V0004_TO_V0005_POSTALE_TUNING_ID)
        return
    }
    postale_body := flight.Body_State {
        orientation            = prepared.postale_body_orientation,
        angular_velocity_world = fixture_migration_v0004_to_v0005_history_vec3(
            historical.postale.body.angular_velocity,
        ),
    }
    prepared.postale_ace_runtime = flight.default_ace_runtime(postale_body, prepared.postale_ace_tuning)
    if !fixture_migration_v0004_to_v0005_ace_runtime_valid(prepared.postale_ace_runtime) {
        error = fixture_migration_v0004_to_v0005_invalid_source(FIXTURE_MIGRATION_V0004_TO_V0005_POSTALE_RUNTIME_ID)
        return
    }
    return
}

fixture_migration_v0004_to_v0005_apply :: proc(
    #by_ptr historical: fixture_v0004.Fixture,
    tentative: ^Fixture,
    #by_ptr prepared: Fixture_Migration_V0004_To_V0005_Prepared,
) {
    tentative.postale.body.angular_velocity_world = fixture_migration_v0004_to_v0005_history_vec3(
        historical.postale.body.angular_velocity,
    )
    tentative.libellula.body.angular_velocity_world = fixture_migration_v0004_to_v0005_history_vec3(
        historical.libellula.body.angular_velocity,
    )
    tentative.rondine.body.angular_velocity_world = fixture_migration_v0004_to_v0005_history_vec3(
        historical.rondine.body.angular_velocity,
    )

    tentative.postale.body.orientation = prepared.postale_body_orientation
    tentative.libellula.body.orientation = prepared.libellula_body_orientation
    tentative.rondine.body.orientation = prepared.rondine_body_orientation
    tentative.libellula.spawn_orientation = prepared.libellula_spawn_orientation
    tentative.postale.spawn_orientation = prepared.postale_spawn_orientation

    tentative.postale.flight_model = .Current_Aero
    tentative.postale.ace_tuning = prepared.postale_ace_tuning
    tentative.postale.ace_runtime = prepared.postale_ace_runtime
}

fixture_migrate_v0004_to_v0005 :: proc(
    #by_ptr historical: fixture_v0004.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = allocator
    if tentative == nil do return {kind = .Invalid_Argument}
    prepared, preflight_error := fixture_migration_v0004_to_v0005_preflight(historical)
    if preflight_error.kind != .None do return preflight_error
    fixture_migration_v0004_to_v0005_apply(historical, tentative, prepared)
    return {}
}
