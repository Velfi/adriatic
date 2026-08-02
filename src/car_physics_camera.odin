package main

import engine_sound "../packages/engine_sound"
import postale_game "../packages/postale"
import roads "../packages/roads"
import story "../packages/story"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:time"
import timezone "core:time/timezone"
import canvas2d "zelda_engine:canvas2d"
import physics "zelda_engine:physics"

car_physics_step :: proc(
    editor: ^Editor,
    throttle, steering: f32,
    handbrake: bool,
    surface: vehicles.Car_Drive_Surface,
    delta_seconds: f32,
    listener_yaw: f32,
) -> (
    impact_severity, impact_slide_speed, impact_obliqueness, impact_pan: f32,
) {
    if editor == nil || editor.car_physics_vehicle == nil || delta_seconds <= 0 do return
    body := physics.vehicle_body(editor.car_physics_vehicle)
    velocity := physics.get_linear_velocity(editor.car_physics_world, body)
    velocity_before := velocity
    body_rotation :=
        editor.car_physics_body_rotation_valid ? editor.car_physics_body_rotation : car_physics_rotation(editor.car.yaw_radians)
    forward := car_physics_rotate_vector(body_rotation, {0, 0, 1})
    physical_right_before := car_physics_rotate_vector(body_rotation, {1, 0, 0})
    longitudinal := velocity[0] * forward[0] + velocity[1] * forward[1] + velocity[2] * forward[2]
    lateral_before_step :=
        velocity[0] * physical_right_before[0] +
        velocity[1] * physical_right_before[1] +
        velocity[2] * physical_right_before[2]
    brake := f32(0)
    drive := throttle
    if throttle > .01 && longitudinal < -.5 {
        brake, drive = throttle, 0
    } else if throttle < -.01 && longitudinal > .5 {
        brake, drive = -throttle, 0
    }
    dt := max(delta_seconds, f32(.001))
    tune := editor.tweak.car
    if drive > 0 {
        drive *= clamp(tune.acceleration / max(vehicles.CAR_DRIVE_SEDAN_TUNE.acceleration, f32(.01)), 0, 1)
        if longitudinal >= tune.max_forward do drive = 0
    } else if drive < 0 {
        drive *= clamp(
            tune.reverse_acceleration / max(vehicles.CAR_DRIVE_SEDAN_TUNE.reverse_acceleration, f32(.01)),
            0,
            1,
        )
        if longitudinal <= -tune.max_reverse do drive = 0
    }
    brake *= clamp(tune.brake / max(vehicles.CAR_DRIVE_SEDAN_TUNE.brake, f32(.01)), 0, 1)
    editor.car_drive.steering += (steering - editor.car_drive.steering) * clamp(tune.steering_response * dt, 0, 1)
    physics_steering := vehicles.car_drive_speed_sensitive_steering(editor.car_drive.steering, longitudinal, tune)
    racer_assist: vehicles.Car_Racer_Assist
    if editor.car_handling_model == .Racer_Arcade {
        racer_assist = vehicles.car_racer_arcade_assist(
            &editor.car_drive.racer,
            editor.car_drive.steering,
            longitudinal,
            lateral_before_step,
            brake,
            handbrake,
            dt,
            tune,
        )
        physics_steering = racer_assist.steering

        // Pull velocity toward a readable slip angle before the tire solver.
        // The modest response preserves accumulated momentum and lets terrain
        // and collisions remain authoritative.
        lateral_assist :=
            (racer_assist.target_lateral_velocity - lateral_before_step) *
            clamp((2.2 + racer_assist.drift_amount * tune.racer.drift_lateral_response) * dt, 0, .35)
        if math.abs(lateral_assist) > .0001 {
            velocity[0] += physical_right_before[0] * lateral_assist
            velocity[1] += physical_right_before[1] * lateral_assist
            velocity[2] += physical_right_before[2] * lateral_assist
            physics.set_linear_velocity(editor.car_physics_world, body, velocity)
        }
    }
    physics.set_vehicle_input(
        editor.car_physics_world,
        editor.car_physics_vehicle,
        drive,
        physics_steering,
        brake,
        handbrake ? 1 : 0,
    )
    // Establish a safe fallback, then override each wheel before simulation.
    // Applying wheel grip after the step delays it by a frame, while this
    // global assignment on the next frame used to erase every override.
    physics.set_vehicle_grip(editor.car_physics_vehicle, surface.longitudinal_grip, surface.lateral_grip)
    bump_acceleration, bump_contacts := f32(0), 0
    for index in 0 ..< 4 {
        wheel_state, wheel_ok := physics.get_wheel_state(editor.car_physics_vehicle, u32(index))
        if !wheel_ok do continue
        editor.car_wheels[index] = wheel_state
        wheel := editor.car_wheels[index]
        wheel_position := roads.Vec3{wheel.position[0], wheel.position[1], wheel.position[2]}
        wheel_dust, wheel_surface := road_car_surface(editor, wheel_position)
        wheel_lateral_scale := f32(1)
        authored_lateral_scale := clamp(
            tune.lateral_grip / max(vehicles.CAR_DRIVE_SEDAN_TUNE.lateral_grip, f32(.01)),
            .05,
            4,
        )
        wheel_lateral_scale *= authored_lateral_scale
        if index >= 2 {
            if editor.car_handling_model == .Racer_Arcade {
                wheel_lateral_scale *= racer_assist.rear_grip_scale
            } else if handbrake {
                authored_handbrake_scale := clamp(
                    tune.handbrake_grip / max(vehicles.CAR_DRIVE_SEDAN_TUNE.handbrake_grip, f32(.01)),
                    0,
                    4,
                )
                wheel_lateral_scale *= .22 * authored_handbrake_scale
            }
        }
        physics.set_vehicle_wheel_grip(
            editor.car_physics_vehicle,
            u32(index),
            wheel_surface.longitudinal_grip,
            wheel_surface.lateral_grip * wheel_lateral_scale,
        )
        if wheel.contact {
            bump_acceleration += car_surface_bump_acceleration(wheel_dust, wheel_position, longitudinal)
            bump_contacts += 1
        }
    }
    if bump_contacts > 0 {
        bump_acceleration /= f32(bump_contacts)
        physics.add_force(editor.car_physics_world, body, {0, CAR_PHYSICS_MASS * bump_acceleration, 0})
    }

    gameplay_physics_sync_revisions(editor)
    editor.car_physics_terrain_revision = editor.gameplay_physics.terrain_revision
    gameplay_physics_step_world(editor, delta_seconds)

    position, body_rotation_after, body_ok := physics.get_transform(editor.car_physics_world, body)
    if !body_ok do return
    velocity = physics.get_linear_velocity(editor.car_physics_world, body)
    impact_severity, impact_slide_speed, impact_obliqueness = engine_sound.detect_vehicle_impact(
        &editor.car_impact_detector,
        velocity_before[0],
        velocity_before[1],
        velocity_before[2],
        velocity[0],
        velocity[1],
        velocity[2],
        delta_seconds,
    )
    if impact_severity > 0 {
        impact_pan = engine_sound.vehicle_impact_pan(
            velocity_before[0],
            velocity_before[2],
            velocity[0],
            velocity[2],
            listener_yaw,
        )
    }
    previous_yaw := editor.car.yaw_radians
    body_up := car_physics_rotate_vector(body_rotation_after, {0, 1, 0})
    editor.car.position = {
        position[0] - body_up[0] * .74,
        position[1] - body_up[1] * .74,
        position[2] - body_up[2] * .74,
    }
    editor.car_physics_body_rotation = body_rotation_after
    editor.car_physics_body_rotation_valid = true
    editor.car.yaw_radians = car_physics_yaw(body_rotation_after)
    x, y, z, w := body_rotation_after[0], body_rotation_after[1], body_rotation_after[2], body_rotation_after[3]
    editor.car_drive.body_pitch = math.asin(clamp(2 * (y * z - w * x), -1, 1))
    editor.car_drive.body_roll = math.asin(clamp(2 * (x * y + w * z), -1, 1))
    forward_after := car_physics_rotate_vector(body_rotation_after, {0, 0, 1})
    longitudinal_after :=
        velocity[0] * forward_after[0] + velocity[1] * forward_after[1] + velocity[2] * forward_after[2]
    acceleration_target := clamp(
        (longitudinal_after - longitudinal) / dt / max(vehicles.CAR_DRIVE_SEDAN_TUNE.acceleration, f32(1)),
        -1,
        1,
    )
    editor.car_drive.acceleration_feedback +=
        (acceleration_target - editor.car_drive.acceleration_feedback) * clamp(6 * dt, 0, 1)
    editor.car_drive.velocity = {velocity[0], velocity[1], velocity[2]}
    editor.car_drive.wheel_speed = longitudinal
    yaw_delta := editor.car.yaw_radians - previous_yaw
    for yaw_delta > math.PI do yaw_delta -= 2 * math.PI
    for yaw_delta < -math.PI do yaw_delta += 2 * math.PI
    editor.car_drive.yaw_rate = yaw_delta / dt
    editor.car_drive.handbrake_amount +=
        ((handbrake ? f32(1) : f32(0)) - editor.car_drive.handbrake_amount) * clamp(8 * dt, 0, 1)
    physical_right := car_physics_rotate_vector(body_rotation_after, {1, 0, 0})
    lateral := velocity[0] * physical_right[0] + velocity[1] * physical_right[1] + velocity[2] * physical_right[2]
    editor.car_drive.slip_amount +=
        (vehicles.car_drive_slip_angle_amount(longitudinal_after, lateral) - editor.car_drive.slip_amount) *
        clamp(8 * dt, 0, 1)
    for index in 0 ..< 4 {
        wheel_state, wheel_ok := physics.get_wheel_state(editor.car_physics_vehicle, u32(index))
        if !wheel_ok do continue
        editor.car_wheels[index] = wheel_state
    }
    return
}

car_trailer_hitch_position :: proc(editor: ^Editor, trailer: bool = false) -> third_person.Vec3 {
    if editor == nil do return {}
    origin := editor.car.position
    yaw := editor.car.yaw_radians
    if trailer && !editor.car_trailer_attached {
        origin = editor.car_trailer_position
        yaw = editor.car_trailer_yaw
    }
    hitch_z := trailer ? f32(1.36) : f32(1.48)
    return {origin.x - math.cos(yaw) * hitch_z, origin.y, origin.z - math.sin(yaw) * hitch_z}
}

car_trailer_can_attach :: proc(editor: ^Editor) -> bool {
    if editor == nil || editor.car_trailer_attached do return false
    delta := (car_trailer_hitch_position(editor) - car_trailer_hitch_position(editor, true))
    close := delta.x * delta.x + delta.z * delta.z <= .72 * .72
    yaw_delta := editor.car.yaw_radians - editor.car_trailer_yaw
    for yaw_delta > math.PI do yaw_delta -= math.PI * 2
    for yaw_delta < -math.PI do yaw_delta += math.PI * 2
    return close && math.abs(yaw_delta) <= .48
}

car_trailer_interaction_near :: proc(editor: ^Editor) -> bool {
    if editor == nil || editor.pilot.mode != .On_Foot do return false
    hitch := car_trailer_hitch_position(editor, !editor.car_trailer_attached)
    delta := (editor.player.position - hitch)
    return delta.x * delta.x + delta.z * delta.z <= 1.45 * 1.45
}

car_trailer_interact :: proc(editor: ^Editor) -> bool {
    if editor == nil || !car_trailer_interaction_near(editor) do return false
    if editor.car_trailer_attached {
        editor.car_trailer_position = editor.car.position
        editor.car_trailer_yaw = editor.car.yaw_radians
        editor.car_trailer.velocity = editor.car_drive.velocity
        editor.car_trailer.yaw_rate = editor.car_drive.yaw_rate
        editor.car_trailer_attached = false
        return true
    }
    if !car_trailer_can_attach(editor) do return false
    editor.car_trailer_position = editor.car.position
    editor.car_trailer_yaw = editor.car.yaw_radians
    editor.car_trailer.velocity = editor.car_drive.velocity
    editor.car_trailer.yaw_rate = editor.car_drive.yaw_rate
    editor.car_trailer_attached = true
    return true
}

vehicle_entry_prompt :: proc(editor: ^Editor) -> cstring {
    if editor == nil || editor.pilot.mode != .On_Foot do return nil
    if town_mouse_wheel_mounted {
        if controller_prompt_active(editor) {
            return "SOUTH > EAST > NORTH > WEST TO RUN  /  HOLD WEST TO DISMOUNT"
        }
        return "1 > 2 > 3 > 4 TO RUN  /  F DISMOUNT"
    }
    if town_mouse_wheel_near(editor) do return "PRESS F TO USE MOUSE WHEEL"
    car_delta := (editor.player.position - editor.car.position)
    car_distance := linalg.dot(car_delta, car_delta)
    car_radius := editor.car.interaction_radius
    if car_radius <= 0 do car_radius = 2.5
    aircraft := active_aircraft_vehicle(editor)
    aircraft_delta := (editor.player.position - aircraft.position)
    aircraft_distance := linalg.dot(aircraft_delta, aircraft_delta)
    aircraft_radius := aircraft.interaction_radius
    if aircraft_radius <= 0 do aircraft_radius = 2.5
    attendant_resident, _, attendant_near := nearest_service_attendant(editor)
    dockmaster_near := markov_marina_dockmaster_near(editor)
    harbor_mechanic_near := marin_near(editor)
    story_resident, _, story_near := nearest_story_resident(editor, require_action = true)
    trailer_near := car_trailer_interaction_near(editor)
    car_near := car_distance <= car_radius * car_radius
    aircraft_near := aircraft_distance <= aircraft_radius * aircraft_radius
    if trailer_near {
        if editor.car_trailer_attached do return "PRESS F TO DETACH TRAILER"
        if car_trailer_can_attach(editor) do return "PRESS F TO ATTACH TRAILER"
        return "ALIGN CAR TO ATTACH TRAILER"
    }
    if dockmaster_near {
        if controller_prompt_active(editor) {
            return fmt.ctprintf("PRESS %s TO TALK TO VESNA", controller_face_label(editor, .West))
        }
        return "PRESS F TO TALK TO VESNA"
    }
    if harbor_mechanic_near {
        if controller_prompt_active(editor) {
            return fmt.ctprintf("PRESS %s TO TALK TO MARIN", controller_face_label(editor, .West))
        }
        return "PRESS F TO TALK TO MARIN"
    }
    if story_near {
        if controller_prompt_active(editor) {
            return fmt.ctprintf(
                "PRESS %s TO TALK TO %s",
                controller_face_label(editor, .West),
                story.resident_name(story_resident),
            )
        }
        return fmt.ctprintf("PRESS F TO TALK TO %s", story.resident_name(story_resident))
    }
    if car_near && (!aircraft_near || car_distance <= aircraft_distance) {
        if controller_prompt_active(editor) {
            return fmt.ctprintf("PRESS %s TO ENTER CAR", controller_face_label(editor, .West))
        }
        return "PRESS F TO ENTER CAR"
    }
    if aircraft_near {
        if controller_prompt_active(editor) {
            return fmt.ctprintf(
                "PRESS %s TO ENTER %s",
                controller_face_label(editor, .West),
                vehicles.aircraft_kind_name(editor.aircraft.active),
            )
        }
        return fmt.ctprintf("PRESS F TO ENTER %s", vehicles.aircraft_kind_name(editor.aircraft.active))
    }
    if attendant_near {
        if controller_prompt_active(editor) {
            return fmt.ctprintf(
                "PRESS %s TO TALK TO %s",
                controller_face_label(editor, .West),
                story.resident_name(attendant_resident),
            )
        }
        return fmt.ctprintf("PRESS F TO TALK TO %s", story.resident_name(attendant_resident))
    }
    return nil
}

vehicle_showcase_camera_step :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil do return
    if canvas2d.IsMouseButtonDown(.MIDDLE) {
        mouse_delta := canvas2d.GetMouseDelta()
        third_person.look(&editor.camera, -mouse_delta.x, mouse_delta.y, .006)
    }
    editor.camera.distance = clamp(editor.camera.distance - canvas2d.GetMouseWheelMove() * .7, 2.5, 30)
    target := third_person.Vec3{0, editor.camera.height, 0}
    if editor.vehicle_showcase_target == "rondine" {
        position := editor.rondine.body.position
        target = {position.x, position.y + editor.camera.height, position.z}
    }
    editor.camera_pose = third_person.camera_pose(target, editor.camera)
}

editor_camera_pose :: proc() -> third_person.Camera_Pose {
    island_center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    return {position = {island_center + 650, 720, island_center + 650}, target = {island_center, 1.5, island_center}}
}
