#+feature using-stmt
package main

import atmosphere "../packages/atmosphere"
import chase_camera "../packages/chase_camera"
import flight "../packages/flight"
import fog_field "../packages/fog_field"
import rondine_game "../packages/rondine"
import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import vehicles "../packages/vehicles"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

run_prepare_world_and_flight_capture :: proc(editor: ^Editor, using config: ^Run_Config) {
    if capture_flight_mode && capture_target == "postale-bank-grid" {
        editor.capture_postale_bank_grid = true
        editor.capture_world_only = false
    }
    if (capture_map_mode && !capture_lab_mode) || (capture_flight_mode || capture_car_mode) && !capture_lab_mode {
        editor.player = {
            position = runway_spawn_position(editor),
            grounded = true,
        }
        editor.camera = third_person.default_camera()
        editor.camera_pose = third_person.camera_pose(editor.player.position, editor.camera)
    } else {
        // Scene-specific captures author their framing before the renderer
        // attaches. Enter gameplay without replacing that camera, and put
        // the player at its focus so range-limited gameplay vegetation is
        // populated around what the capture is actually inspecting.
        editor.player = {
            position = {
                editor.editor_focus.x,
                terrain.sample_surface_height(&editor.project, 0, editor.editor_focus.x, editor.editor_focus.z),
                editor.editor_focus.z,
            },
            grounded = true,
        }
        editor.camera = third_person.default_camera()
        third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
        third_person.camera_set_active(&editor.cameras, .Inspection)
        editor.capture_world_only = true
    }
    if config.fog_capture {
        half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
        field := fog_field.generate(
            editor.atmosphere.seed,
            editor.atmosphere.front_seconds,
            editor.atmosphere.weather,
            {{-half_extent, -half_extent}, {half_extent, half_extent}},
            editor.atmosphere.climate.current,
        )
        bank := field.banks[0]
        center := third_person.Vec3{bank.center.x, bank.top_altitude * .42, bank.center.y}
        offset := third_person.Vec3{bank.axis.x * bank.radii.x, 0, bank.axis.y * bank.radii.x}
        eye := center + offset * 1.75 + third_person.Vec3{0, 70, 0}
        if capture_target == "fog-boundary" do eye = center + offset * 1.02 + third_person.Vec3{0, 20, 0}
        if capture_target == "fog-inside" do eye = center + third_person.Vec3{0, 8, 0}
        if capture_target == "fog-above" do eye = center + third_person.Vec3{0, bank.top_altitude + 180, 0}
        editor.camera_pose = third_person.camera_look_at(eye, center)
        third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
        third_person.camera_set_active(&editor.cameras, .Inspection)
        editor.capture_world_only = true
    }
    if capture_sky_mode &&
       (capture_target == "sun" ||
               capture_target == "sun-air" ||
               capture_target == "sun-away" ||
               capture_target == "moon" ||
               capture_target == "stars") {
        sky_capture := atmosphere_sky(editor)
        // Observer elevation materially changes the required reflecting
        // slopes, so retain matched on-foot and airborne verification
        // views instead of tuning the BRDF to either camera.
        eye_height := capture_target == "sun-air" ? f32(180) : f32(3.2)
        eye := third_person.Vec3{0, eye_height, 0}
        view_sign := capture_target == "sun-away" ? f32(-1) : f32(1)
        view_direction := sky_capture.sun_direction
        if capture_target == "moon" do view_direction = sky_capture.moon_direction
        if capture_target == "stars" do view_direction = {0, .64, .77}
        editor.camera_pose = third_person.camera_look_at(
            eye,
            {
                eye.x + view_direction[0] * 100 * view_sign,
                eye.y + view_direction[1] * 100 + 1.2,
                eye.z + view_direction[2] * 100 * view_sign,
            },
        )
        third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
        third_person.camera_set_active(&editor.cameras, .Inspection)
        editor.capture_world_only = true
    }
    if capture_kind == .Map && capture_target == "airport" {
        airport := editor.attendant_position
        airport_sign := airport.x >= 0 ? f32(1) : f32(-1)
        airport_rotation := airport_sign > 0 ? -f32(math.PI) * .5 : f32(math.PI) * .5
        eye_x, eye_z := world_rotate_xz(airport.x, airport.z, -18, -23, airport_rotation)
        target_x, target_z := world_rotate_xz(airport.x, airport.z, 0, 4.5, airport_rotation)
        inspection_pose := third_person.camera_look_at(
            {eye_x, terrain.sample_surface_height(&editor.project, 0, eye_x, eye_z) + 8.5, eye_z},
            {target_x, terrain.sample_surface_height(&editor.project, 0, target_x, target_z) + 2.6, target_z},
        )
        player_place(
            editor,
            {eye_x, terrain.sample_surface_height(&editor.project, 0, eye_x, eye_z), eye_z},
            .Scene_Setup,
        )
        editor.postale_visible = false
        editor.libellula_visible = true
        editor.rondine_visible = false
        third_person.camera_set_pose(&editor.cameras, .Inspection, inspection_pose)
        third_person.camera_set_active(&editor.cameras, .Inspection)
        editor.camera_pose = inspection_pose
        editor.capture_world_only = true
    }
    editor.pilot.position = editor.player.position
    editor.in_map = true
    editor.map_time = f32(canvas2d.GetTime())
    if capture_flight_mode {
        capture_vehicle := &editor.postale.vehicle
        rondine_capture :=
            capture_target == "rondine" ||
            capture_target == "rondine-launch" ||
            capture_target == "rondine-landing" ||
            capture_target == "rondine-drift" ||
            capture_target == "rondine-countersteer" ||
            capture_target == "rondine-countersteer-left" ||
            capture_target == "rondine-breakaway" ||
            capture_target == "rondine-hookup"
        if rondine_capture {
            editor.aircraft.active = .Rondine
            editor.postale_visible = false
            editor.libellula_visible = false
            editor.rondine_visible = true
            editor.rondine.vehicle.locked = false
            editor.rondine.spawn_position = rondine_spawn_position(editor)
            rondine_game.reset(&editor.rondine, editor.project.sea_level)
            editor.pilot.position = editor.rondine.vehicle.position
            capture_vehicle = &editor.rondine.vehicle
        }
        _, entered := vehicles.try_enter_nearest(&editor.pilot, []^vehicles.Vehicle{capture_vehicle})
        if entered {
            // Give the flight capture a reproducible airborne state so visual
            // verification exercises the wing-trail and wind-response systems.
            if rondine_capture {
                rondine_drift_capture := capture_target == "rondine-drift"
                rondine_countersteer_capture :=
                    capture_target == "rondine-countersteer" || capture_target == "rondine-countersteer-left"
                rondine_countersteer_left := capture_target == "rondine-countersteer-left"
                rondine_breakaway_capture := capture_target == "rondine-breakaway"
                rondine_hookup_capture := capture_target == "rondine-hookup"
                rondine_landing_capture := capture_target == "rondine-landing"
                if rondine_drift_capture ||
                   rondine_countersteer_capture ||
                   rondine_breakaway_capture ||
                   rondine_hookup_capture {
                    editor.rondine.tuning.takeoff_speed = 200
                }
                if rondine_countersteer_capture {
                    initial_roll := rondine_countersteer_left ? f32(-1) : f32(1)
                    for _ in 0 ..< 540 {
                        rondine_game.step(
                            &editor.rondine,
                            {throttle_up = true, roll = initial_roll},
                            editor.project.sea_level,
                            1.0 / 120.0,
                        )
                    }
                    for _ in 0 ..< 64 {
                        rondine_game.step(
                            &editor.rondine,
                            {throttle_up = true, roll = -initial_roll},
                            editor.project.sea_level,
                            1.0 / 120.0,
                        )
                    }
                } else if rondine_breakaway_capture {
                    for _ in 0 ..< 520 {
                        rondine_game.step(&editor.rondine, {throttle_up = true}, editor.project.sea_level, 1.0 / 120.0)
                    }
                    for _ in 0 ..< 34 {
                        rondine_game.step(
                            &editor.rondine,
                            {throttle_up = true, roll = 1},
                            editor.project.sea_level,
                            1.0 / 120.0,
                        )
                    }
                } else if rondine_hookup_capture {
                    for _ in 0 ..< 540 {
                        rondine_game.step(
                            &editor.rondine,
                            {throttle_up = true, roll = 1},
                            editor.project.sea_level,
                            1.0 / 120.0,
                        )
                    }
                    for _ in 0 ..< 34 {
                        rondine_game.step(&editor.rondine, {throttle_up = true}, editor.project.sea_level, 1.0 / 120.0)
                    }
                } else if rondine_landing_capture {
                    for _ in 0 ..< 480 {
                        rondine_game.step(&editor.rondine, {throttle_up = true}, editor.project.sea_level, 1.0 / 120.0)
                    }
                    editor.rondine.body.position.y = editor.project.sea_level + rondine_game.GROUND_CLEARANCE + .2
                    editor.rondine.body.velocity.y = -8
                    editor.rondine.grounded = false
                    editor.rondine.wake_distance = 1.2
                    rondine_game.step(&editor.rondine, {throttle_up = true}, editor.project.sea_level, .05)
                } else {
                    // Let the launch target clear the surface decisively;
                    // this makes it a useful negative reference for
                    // surface-only spray and chine-contact verification.
                    step_count := capture_target == "rondine-launch" ? 480 : (rondine_drift_capture ? 720 : 640)
                    for _ in 0 ..< step_count {
                        rondine_game.step(
                            &editor.rondine,
                            {
                                throttle_up = true,
                                roll = rondine_drift_capture ? f32(1) : (capture_target == "rondine-launch" ? f32(0) : f32(.18)),
                            },
                            editor.project.sea_level,
                            1.0 / 120.0,
                        )
                    }
                }
            } else {
                editor.postale.body.position.y += 85
                basis := flight.basis_from_orientation(editor.postale.body.orientation)
                editor.postale.body.velocity = basis.forward * 58
                editor.postale.grounded = false
                editor.postale.was_grounded = false
                editor.postale.throttle = .82
            }
            if config.fog_capture {
                half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
                field := fog_field.generate(
                    editor.atmosphere.seed,
                    editor.atmosphere.front_seconds,
                    editor.atmosphere.weather,
                    {{-half_extent, -half_extent}, {half_extent, half_extent}},
                    editor.atmosphere.climate.current,
                )
                bank := field.banks[0]
                forward := flight.Vec3{-bank.axis.x, 0, -bank.axis.y}
                radial := f32(1.45)
                if capture_target == "fog-boundary" do radial = .98
                if capture_target == "fog-inside" do radial = 0
                altitude := bank.base_altitude + (bank.top_altitude - bank.base_altitude) * .45
                if capture_target == "fog-above" {
                    radial = 2.2
                    altitude = bank.top_altitude + 250
                }
                editor.postale.body.position = {
                    bank.center.x + bank.axis.x * bank.radii.x * radial,
                    altitude,
                    bank.center.y + bank.axis.y * bank.radii.x * radial,
                }
                editor.postale.body.orientation = flight.orientation_from_forward_and_up(forward, {0, 1, 0})
                editor.postale.body.velocity = forward * 58
                editor.postale.grounded = false
                editor.postale.was_grounded = false
                editor.postale.throttle = .82
                editor.pilot.position = editor.postale.body.position
            }
            if capture_target == "storm-front" {
                atmosphere.set_weather_override(&editor.atmosphere, .Automatic)
                atmosphere.trigger_front(&editor.atmosphere)
                front := &editor.atmosphere.schedule.front
                front.intensity = 1
                front.gustiness = 1
                front.rainfall = 1
                front.visibility_loss = .9
                front.cell_phase = f32(math.PI) / 3.4
                duration := front.end_seconds - front.start_seconds
                editor.atmosphere.schedule.elapsed_seconds = front.start_seconds + duration * .5
                body := active_aircraft_body(editor)
                age := editor.atmosphere.schedule.elapsed_seconds - front.start_seconds
                front.origin = {
                    body.position.x - front.direction[0] * front.speed * age,
                    body.position.z - front.direction[1] * front.speed * age,
                }
                local := atmosphere.sample_at(
                    &editor.atmosphere,
                    {body.position.x, body.position.y, body.position.z},
                    body.position.y,
                )
                editor.atmosphere.weather = {
                    local.cloud_cover,
                    local.precipitation,
                    local.haze,
                    local.severity,
                    {local.wind[0], local.wind[2]},
                }
            } else if !config.fog_capture {
                atmosphere.set_weather_override(&editor.atmosphere, .Windy)
                editor.atmosphere.weather = atmosphere.weather_for(.Windy)
            }
            editor.atmosphere.paused = true
            chase_camera.reset(&editor.flight_camera, aircraft_camera_target(editor))
            editor.camera_pose = editor.flight_camera.pose
            if config.fog_capture && capture_target == "fog-above" {
                // The chase camera deliberately favors the horizon. Use
                // the aircraft's established downward observation view so
                // this target frames both the crown and clear water beyond
                // the bank edge while remaining an in-flight capture.
                editor.bomber_mode = true
                editor.camera_pose = bomber_camera_pose(editor)
            }
            if capture_target == "bomber" {
                editor.bomber_mode = true
                editor.bomber_payload_kind = .Mail
                bomber_drop_release(editor)
                for _ in 0 ..< 10 do bomber_drop_step(editor, .05)
                editor.camera_pose = bomber_camera_pose(editor)
            }
        }
    }
}
