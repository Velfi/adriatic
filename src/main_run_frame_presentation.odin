#+feature using-stmt
package main

import atmosphere "../packages/atmosphere"
import boats "../packages/boats"
import chase_camera "../packages/chase_camera"
import dio "../packages/dio"
import engine_sound "../packages/engine_sound"
import flight "../packages/flight"
import game_input "../packages/game_input"
import libellula_game "../packages/libellula"
import ocean_audio "../packages/ocean_audio"
import particle_systems "../packages/particles"
import postale_game "../packages/postale"
import roads "../packages/roads"
import rondine_game "../packages/rondine"
import scene_stack "../packages/scene_stack"
import spray_audio "../packages/spray_audio"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import wind_audio "../packages/wind_audio"
import "core:fmt"
import "core:math"
import "core:time"
import sdl "vendor:sdl3"
import canvas2d "zelda_engine:canvas2d"
import physics "zelda_engine:physics"

run_frame_present :: proc(using run: ^Run_State, using frame_state: ^Run_Frame_State) -> bool {
    render_aircraft_body := active_aircraft_body(editor)
    interpolate_aircraft := driving_aircraft(editor) && editor.aircraft_previous_body_valid
    if interpolate_aircraft {
        saved_aircraft_body = render_aircraft_body^
        render_aircraft_body^ = aircraft_render_body(editor)
    }
    capture_camera_overridden := false
    capture_camera_original := editor.camera_pose
    capture_camera_active_original := editor.cameras.active
    capture_camera_slot :=
        selector_capture_pose_set ? third_person.Camera_Slot.Inspection : capture_camera_active_original
    capture_camera_slot_original := editor.cameras.poses[capture_camera_slot]
    if capture_mode &&
       request != nil &&
       (selector_capture_pose_set ||
               request.camera_eye_set ||
               request.camera_orbit_set ||
               request.camera_distance_set ||
               request.camera_offset_set ||
               request.turntable_frames > 0) {
        pose := selector_capture_pose_set ? selector_capture_pose : capture_camera_original
        if selector_capture_pose_set {
            // Re-resolve dynamic subjects at submission time. Flight
            // bodies continue moving while a sequence settles, and a pose
            // captured only during setup quickly points at empty air.
            live_pose, _, _, live_pose_ok := capture_selector_pose(
                editor,
                request.selector,
                request.selector_filters,
                request.selector_filter_count,
                request.selector_pick,
                request.presentation,
            )
            if live_pose_ok do pose = live_pose
        }
        if request.camera_eye_set {
            pose = third_person.camera_look_at(request.camera_eye, request.camera_look_at)
        } else {
            delta := pose.position - pose.target
            radius := f32(math.sqrt(f64(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)))
            if radius < .0001 {
                delta = {0, 0, 1}
                radius = 1
            }
            yaw := math.atan2(delta.x, delta.z)
            horizontal := f32(math.sqrt(f64(delta.x * delta.x + delta.z * delta.z)))
            pitch := math.atan2(delta.y, horizontal)
            if request.turntable_frames > 0 {
                yaw += f32(turntable_frame_index) / f32(request.turntable_frames) * f32(math.PI * 2)
            }
            if request.camera_orbit_set {
                degrees_to_radians := f32(math.PI / 180)
                yaw += request.camera_orbit_degrees[0] * degrees_to_radians
                pitch += request.camera_orbit_degrees[1] * degrees_to_radians
                pitch = clamp(pitch, f32(-math.PI * .495), f32(math.PI * .495))
            }
            if request.camera_distance_set do radius = request.camera_distance
            horizontal_radius := math.cos(pitch) * radius
            pose.position =
                pose.target +
                third_person.Vec3 {
                        math.sin(yaw) * horizontal_radius,
                        math.sin(pitch) * radius,
                        math.cos(yaw) * horizontal_radius,
                    }
            if request.camera_offset_set {
                pose.position += request.camera_offset
                pose.target += request.camera_offset
            }
        }
        editor.camera_pose = pose
        third_person.camera_set_pose(&editor.cameras, capture_camera_slot, pose)
        if selector_capture_pose_set do third_person.camera_set_active(&editor.cameras, capture_camera_slot)
        capture_camera_overridden = true
    }
    dio.flame_graph_begin_frame(&editor.flame_graph)
    canvas2d.BeginDrawing()
    if editor.default_map_regeneration_active {
        progress, message := default_map_regeneration_progress(editor)
        draw_startup_loading_screen(width, height, progress, message, postcard)
    } else {
        draw_terrain(editor, width, height, f32(canvas2d.GetTime()))
        pause_menu_draw(editor, width, height, postcard)
        cinematic_draw_wipe(editor, width, height)
        crash_recovery_draw(editor, width, height)
        photo_mode_capture_pending(editor)
    }
    live_capture_poll()
    live_control_poll(editor)
    mouse_emote_enforce_player_priority(editor)
    canvas2d.EndDrawing()
    if !startup_timings_emitted {
        first_frame_end := time.tick_now()
        first_frame_ms := startup_elapsed_ms(startup_timings.checkpoint, first_frame_end)
        total_ms := startup_elapsed_ms(startup_timings.started_at, first_frame_end)
        startup_kind := first_start ? "cold" : "reload"
        startup_mode := benchmark_mode ? "benchmark" : capture_mode ? "capture" : interactive_lab_mode ? "lab" : "game"
        fmt.eprintf(
            "startup total=%.1fms config=%.1fms window=%.1fms audio=%.1fms meshes=%.1fms terrain=%.1fms map_load=%.1fms physics=%.1fms renderer=%.1fms ready=%.1fms first_frame=%.1fms kind=%s mode=%s map=%s map_version=%d map_source=%s\n",
            total_ms,
            startup_timings.config_ms,
            startup_timings.window_ms,
            startup_timings.audio_ms,
            startup_timings.meshes_ms,
            startup_timings.terrain_ms,
            startup_timings.map_load_ms,
            startup_timings.physics_ms,
            startup_timings.renderer_ms,
            startup_timings.ready_ms,
            first_frame_ms,
            startup_kind,
            startup_mode,
            map_path,
            MAP_ARTIFACT_FORMAT_VERSION,
            map_source,
        )
        startup_timings_emitted = true
    }
    default_map_regeneration_step(editor)
    // World rendering is submitted during EndDrawing, so keep the capture
    // pose installed until after that submission has consumed it.
    if capture_camera_overridden {
        editor.camera_pose = capture_camera_original
        third_person.camera_set_pose(&editor.cameras, capture_camera_slot, capture_camera_slot_original)
        if selector_capture_pose_set do third_person.camera_set_active(&editor.cameras, capture_camera_active_original)
    }
    gpu_frame_ms, gpu_frame_available := canvas2d.GetGpuFrameTimeMs()
    dio.flame_graph_set_frame_metrics(&editor.flame_graph, 0, 0, f32(gpu_frame_ms), gpu_frame_available)
    dio.flame_graph_end_frame(&editor.flame_graph)
    if interpolate_aircraft {
        render_aircraft_body^ = saved_aircraft_body
    }
    car_damage_impact := f32(0)
    if driving_car(editor) do car_damage_impact = crash_severity
    editor.car_audio_damage = engine_sound.vehicle_audio_damage_step(
        editor.car_audio_damage,
        car_damage_impact,
        simulation_delta,
    )
    engine_controls := engine_sound.Controls{}
    if editor.pilot.mode == .Driving {
        engine_controls.active = true
        if driving_aircraft(editor) {
            if editor.aircraft.active == .Postale {
                engine_controls.rate = .12 + editor.postale.throttle * .88
                engine_controls.power =
                    editor.postale.throttle * clamp(editor.postale.flight_runtime.engine_output, 0, 1)
                engine_controls.propeller_mix = 1
                engine_controls.propeller_airspeed = clamp(postale_game.selected_airspeed(&editor.postale) / 65, 0, 1)
                engine_controls.damage = editor.postale.structural_damage
            } else if editor.aircraft.active == .Rondine {
                engine_controls.rate = .14 + editor.rondine.throttle * .86
                engine_controls.power = editor.rondine.throttle
                engine_controls.propeller_mix = 1
                engine_controls.propeller_airspeed = clamp(
                    editor.rondine.telemetry.speed / editor.rondine.tuning.maximum_speed,
                    0,
                    1,
                )
                engine_controls.damage = editor.rondine.crashed ? 1 : 0
            } else {
                rotor_rate :=
                    (editor.libellula.telemetry.rotor_rpm_normalized.x +
                        editor.libellula.telemetry.rotor_rpm_normalized.y +
                        editor.libellula.telemetry.rotor_rpm_normalized.z) /
                    3
                available_power :=
                    (editor.libellula.flight_runtime.left_engine_output +
                        editor.libellula.flight_runtime.right_engine_output +
                        editor.libellula.flight_runtime.rear_engine_output) /
                    3
                engine_controls.rate = .16 + clamp(rotor_rate, 0, 1) * .84
                engine_controls.rotor_rate_a = clamp(editor.libellula.telemetry.rotor_rpm_normalized.x, 0, 1)
                engine_controls.rotor_rate_b = clamp(editor.libellula.telemetry.rotor_rpm_normalized.y, 0, 1)
                engine_controls.rotor_rate_c = clamp(editor.libellula.telemetry.rotor_rpm_normalized.z, 0, 1)
                engine_controls.power = editor.libellula.throttle * clamp(available_power, 0, 1)
                engine_controls.rotor_mix = 1
                engine_controls.damage = editor.libellula.crashed ? 1 : 0
            }
        } else if driving_car(editor) {
            car_reversing := editor.car_drive.wheel_speed < 0
            normalized_wheel_speed :=
                math.abs(editor.car_drive.wheel_speed) / vehicles.CAR_DRIVE_SEDAN_TUNE.max_forward
            if car_reversing {
                normalized_wheel_speed =
                    math.abs(editor.car_drive.wheel_speed) / vehicles.CAR_DRIVE_SEDAN_TUNE.max_reverse
                engine_controls.reverse_mix = 1
            }
            engine_controls.rate = engine_sound.car_rate_step(
                &editor.car_audio_gearbox,
                normalized_wheel_speed,
                car_reversing,
            )
            engine_controls.shift = editor.car_audio_gearbox.shifted
            engine_controls.transmission_mix = 1
            engine_controls.gear = editor.car_audio_gearbox.gear
            engine_controls.damage = editor.car_audio_damage
            wheel_load := math.abs(
                editor.car_drive.wheel_speed -
                vehicles.car_drive_longitudinal_speed(editor.car_drive, editor.car.yaw_radians),
            )
            engine_controls.power = clamp(
                math.abs(editor.car_drive.acceleration_feedback) * .65 +
                wheel_load / vehicles.CAR_DRIVE_SEDAN_TUNE.max_forward,
                0,
                1,
            )
        }
    }
    wheel_slip_controls := engine_sound.Slip_Controls{}
    tire_wetness := surface_weather_sample(editor, active_surface_weather_position(editor))
    tire_surface := particle_systems.Dust_Surface.Grass
    postale_wheels_on_land := false
    if driving_aircraft(editor) && editor.aircraft.active == .Postale && editor.postale.grounded {
        terrain_height := terrain.sample_height(
            &editor.project,
            0,
            editor.postale.body.position.x,
            editor.postale.body.position.z,
        )
        postale_wheels_on_land = terrain_height >= editor.project.sea_level
        if postale_wheels_on_land {
            tire_surface, _ = road_car_surface(
                editor,
                {editor.postale.body.position.x, editor.postale.body.position.y, editor.postale.body.position.z},
            )
        }
    }
    if driving_car(editor) && !pause_menu_is_open(editor) {
        tire_surface, _ = road_car_surface(
            editor,
            {editor.car.position.x, editor.car.position.y, editor.car.position.z},
        )
        wheel_slip_controls.active = true
        wheel_slip_controls.wetness = tire_wetness
        wheel_slip_controls.surface = footstep_surface_from_dust(tire_surface)
        wheel_slip_controls.amount = editor.car_drive.slip_amount
        wheel_slip_controls.speed = clamp(
            vehicles.car_drive_speed(editor.car_drive) / vehicles.CAR_DRIVE_SEDAN_TUNE.max_forward,
            0,
            1,
        )
    } else if driving_aircraft(editor) &&
       editor.aircraft.active == .Postale &&
       postale_wheels_on_land &&
       editor.landing_wheel_squeal > 0 &&
       !pause_menu_is_open(editor) {
        wheel_slip_controls.active = true
        wheel_slip_controls.wetness = tire_wetness
        wheel_slip_controls.surface = footstep_surface_from_dust(tire_surface)
        wheel_slip_controls.amount = editor.landing_wheel_squeal
        wheel_slip_controls.speed = clamp(editor.landing_wheel_speed / 32, 0, 1)
    }
    tire_roll_controls := engine_sound.Roll_Controls{}
    if driving_car(editor) && !pause_menu_is_open(editor) {
        car_speed := vehicles.car_drive_speed(editor.car_drive)
        road_roughness, road_bump := car_road_audio_profile(editor, car_speed)
        tire_roll_controls.active = true
        tire_roll_controls.wetness = tire_wetness
        tire_roll_controls.damage = editor.car_audio_damage
        tire_roll_controls.speed = clamp(car_speed / vehicles.CAR_DRIVE_SEDAN_TUNE.max_forward, 0, 1)
        tire_roll_controls.surface = footstep_surface_from_dust(tire_surface)
        tire_roll_controls.roughness = road_roughness
        tire_roll_controls.bump = road_bump
    } else if driving_aircraft(editor) && !pause_menu_is_open(editor) {
        if postale_wheels_on_land {
            tire_roll_controls.active = true
            tire_roll_controls.wetness = tire_wetness
            tire_roll_controls.damage = editor.postale.structural_damage
            tire_roll_controls.speed = clamp(postale_game.selected_airspeed(&editor.postale) / 45, 0, 1)
            tire_roll_controls.surface = footstep_surface_from_dust(tire_surface)
            tire_roll_controls.roughness = tire_roughness_from_dust(tire_surface)
        }
    }
    if engine_audio_ready {
        _ = sdl.SetAudioStreamGain(editor.engine_audio.stream, editor.gameplay_options.sound_fx_level)
        if frame == 60 {
            fmt.eprintf(
                "audio runtime: stream=%v device=%d paused=%v queued=%d gain=%.3f volume=%.3f muted=%v menu=%v pause=%v console=%v map=%v\n",
                editor.engine_audio.stream != nil,
                sdl.GetAudioStreamDevice(editor.engine_audio.stream),
                sdl.AudioStreamDevicePaused(editor.engine_audio.stream),
                sdl.GetAudioStreamQueued(editor.engine_audio.stream),
                sdl.GetAudioStreamGain(editor.engine_audio.stream),
                editor.gameplay_options.sound_fx_level,
                sound_fx_muted(editor),
                editor.main_menu_active,
                menu_scene_current(editor),
                editor.console.open,
                editor.in_map,
            )
        }
        if pause_menu_is_open(editor) ||
           (!editor.attendant_dialogue_open && !lab_scene_is_active(editor, "dialogue-sound")) {
            engine_sound.dialogue_voice_stop(&editor.engine_audio)
        }
        engine_sound.update(
            &editor.engine_audio,
            engine_controls,
            wheel_slip_controls,
            tire_roll_controls,
            crash_severity,
            crash_water_mix,
            crash_slide_speed,
            crash_surface,
            footstep_triggered,
            footstep_intensity,
            footstep_surface,
            footstep_landing,
            tire_wetness,
            crash_profile,
            crash_wetness,
            crash_obliqueness,
            crash_pan,
            footstep_slide,
            sound_fx_muted(editor),
        )
    }
    editor.landing_wheel_squeal = max(0, editor.landing_wheel_squeal - simulation_delta * 1.65)
    if benchmark_mode && frame >= benchmark_warmup {
        benchmark_samples[benchmark_sample_count] = canvas2d.GetTime() - benchmark_frame_start
        benchmark_sample_count += 1
        if benchmark_sample_count >= benchmark_frames {
            benchmark_report(
                benchmark_scenario,
                benchmark_samples[:benchmark_sample_count],
                benchmark_window_width,
                benchmark_window_height,
                benchmark_world_width,
                benchmark_world_height,
            )
            return false
        }
    }
    return true
}
