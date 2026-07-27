package postale

import flight "../flight"
import vehicles "../vehicles"

// Checkpoint contains Postale-owned value state needed to resume the same
// simulation. External state such as world time, terrain, camera, and input
// recording belongs to the comparison harness. Vehicle.driver is deliberately
// excluded because ownership pointers cannot be transferred safely.
Checkpoint :: struct {
    valid:                    bool,
    body:                     flight.Body_State,
    airframe:                 flight.Airframe,
    flight_runtime:           flight.Runtime,
    telemetry:                flight.Telemetry,
    flight_model:             Flight_Model,
    ace_tuning:               flight.Ace_Tuning,
    ace_runtime:              flight.Ace_Runtime,
    ace_telemetry:            flight.Ace_Telemetry,
    throttle:                 f32,
    flap_fraction:            f32,
    propeller_turns:          f32,
    pitch:                    f32,
    roll:                     f32,
    yaw:                      f32,
    grounded:                 bool,
    crashed:                  bool,
    was_grounded:             bool,
    grounded_time:            f32,
    ground_pitch_radians:     f32,
    ground_brake_amount:      f32,
    gear_compression:         f32,
    gear_force:               f32,
    structural_damage:        f32,
    last_landing:             Landing_Impact,
    landing_feedback_seconds: f32,
    landing_intent_seconds:   f32,
    landing_intent:           bool,
    spawn_position:           flight.Vec3,
    spawn_orientation:        quaternion128,
    tuning:                   Tuning,
    interaction_radius:       f32,
    exit_distance:            f32,
    vehicle_locked:           bool,
}

capture_checkpoint :: proc(runtime: ^Runtime) -> (checkpoint: Checkpoint, ok: bool) {
    if runtime == nil do return
    checkpoint = {
        valid                    = true,
        body                     = runtime.body,
        airframe                 = runtime.airframe,
        flight_runtime           = runtime.flight_runtime,
        telemetry                = runtime.telemetry,
        flight_model             = runtime.flight_model,
        ace_tuning               = runtime.ace_tuning,
        ace_runtime              = runtime.ace_runtime,
        ace_telemetry            = runtime.ace_telemetry,
        throttle                 = runtime.throttle,
        flap_fraction            = runtime.flap_fraction,
        propeller_turns          = runtime.propeller_turns,
        pitch                    = runtime.pitch,
        roll                     = runtime.roll,
        yaw                      = runtime.yaw,
        grounded                 = runtime.grounded,
        crashed                  = runtime.crashed,
        was_grounded             = runtime.was_grounded,
        grounded_time            = runtime.grounded_time,
        ground_pitch_radians     = runtime.ground_pitch_radians,
        ground_brake_amount      = runtime.ground_brake_amount,
        gear_compression         = runtime.gear_compression,
        gear_force               = runtime.gear_force,
        structural_damage        = runtime.structural_damage,
        last_landing             = runtime.last_landing,
        landing_feedback_seconds = runtime.landing_feedback_seconds,
        landing_intent_seconds   = runtime.landing_intent_seconds,
        landing_intent           = runtime.landing_intent,
        spawn_position           = runtime.spawn_position,
        spawn_orientation        = runtime.spawn_orientation,
        tuning                   = runtime.tuning,
        interaction_radius       = runtime.vehicle.interaction_radius,
        exit_distance            = runtime.vehicle.exit_distance,
        vehicle_locked           = runtime.vehicle.locked,
    }
    return checkpoint, true
}

restore_checkpoint :: proc(runtime: ^Runtime, checkpoint: Checkpoint) -> bool {
    if runtime == nil || !checkpoint.valid do return false

    // Occupancy belongs to the live target, not to a portable checkpoint.
    // Preserve its pointer while restoring every value-owned field.
    driver := runtime.vehicle.driver
    runtime.body = checkpoint.body
    runtime.airframe = checkpoint.airframe
    runtime.flight_runtime = checkpoint.flight_runtime
    runtime.telemetry = checkpoint.telemetry
    runtime.flight_model = checkpoint.flight_model
    runtime.ace_tuning = checkpoint.ace_tuning
    runtime.ace_runtime = checkpoint.ace_runtime
    runtime.ace_telemetry = checkpoint.ace_telemetry
    runtime.throttle = checkpoint.throttle
    runtime.flap_fraction = checkpoint.flap_fraction
    runtime.propeller_turns = checkpoint.propeller_turns
    runtime.pitch = checkpoint.pitch
    runtime.roll = checkpoint.roll
    runtime.yaw = checkpoint.yaw
    runtime.grounded = checkpoint.grounded
    runtime.crashed = checkpoint.crashed
    runtime.was_grounded = checkpoint.was_grounded
    runtime.grounded_time = checkpoint.grounded_time
    runtime.ground_pitch_radians = checkpoint.ground_pitch_radians
    runtime.ground_brake_amount = checkpoint.ground_brake_amount
    runtime.gear_compression = checkpoint.gear_compression
    runtime.gear_force = checkpoint.gear_force
    runtime.structural_damage = checkpoint.structural_damage
    runtime.last_landing = checkpoint.last_landing
    runtime.landing_feedback_seconds = checkpoint.landing_feedback_seconds
    runtime.landing_intent_seconds = checkpoint.landing_intent_seconds
    runtime.landing_intent = checkpoint.landing_intent
    runtime.spawn_position = checkpoint.spawn_position
    runtime.spawn_orientation = checkpoint.spawn_orientation
    runtime.tuning = checkpoint.tuning
    runtime.vehicle.interaction_radius = checkpoint.interaction_radius
    runtime.vehicle.exit_distance = checkpoint.exit_distance
    runtime.vehicle.locked = checkpoint.vehicle_locked
    runtime.vehicle.driver = driver
    sync_vehicle(runtime)
    if driver != nil && driver.vehicle == &runtime.vehicle {
        vehicles.sync_driver(driver)
    }
    return true
}
